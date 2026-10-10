#!/usr/bin/env python3
"""Nudge the plugin when am runs change, from `am watch --all-projects --follow`.

    runs-watch.py <root> [<root> ...] [run_id ...] [--since-seq N]

Arguments, in any order: one beginning with `/` is a root (used as given, never
checked for existence), `--since-seq` takes the next one as N (one or more ASCII
decimal digits, passed as its integer), and any other non-empty one not
beginning with `-` is a run id. No root, a second --since-seq, or any other
argument is a Usage error (exit 2) and am is not looked up or started.
Long-lived. Spawns `am watch --all-projects --follow`, plus `--since-seq N` when
given, as an argv list, never a shell; roots and run ids never reach am. Prints
one JSON object per line, flushed at once:
  {"hello": {"schema": N, "am": V, "head": H, "cursorReset": B, "storeId": S}}
      for the first hello line (event "watch") only. Every hello must carry an
      integer schema of 1 or higher and a non-negative integer head, else
      SchemaMismatch. am and storeId are "" when not strings; cursorReset is
      true only for a JSON true. No other hello key is forwarded.
  {"changed": [{"run": "<run id>", "seq": G}, ...]}
      at most once per 250 ms, never empty, one entry per run holding the
      highest gseq of that run's kept nudges in the window; directly followed by
  {"cursor": C}
      the highest gseq of every kept nudge since the helper started.
  {"ok": false, "error": {"type", "message"}}
      then exit 1, with type SchemaMismatch, CorruptJournal (am exited 3),
      HelperError or AmMissing (Usage exits 2). An am refusal envelope is
      re-emitted unchanged when am exits other than 3, or when its type is
      StoreBusyError.
A nudge is a JSON object whose event is one of EVENTS, whose run_id is a
non-empty string and whose gseq is an integer of 1 or more. Every other line is
ignored; event contents are never forwarded. A nudge is kept when its run is
watched: the argv run ids, plus every run whose run_upsert nudge has a
payload.repo_dir naming the same directory (realpath) as any root, from that
run_upsert on, for good. Every other nudge is dropped: it prints nothing and
moves neither the batch nor the cursor. am exiting 0, SIGINT, SIGTERM or a
closed stdout end the helper with exit 0. Only the `am` command is used; am's
database and on-disk layout are never read.
"""
import json
import os
import queue
import shutil
import signal
import subprocess
import sys
import threading
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-watch.py <root> [<root> ...] [run_id ...] [--since-seq N]"
IDLE_POLL = 1.0  # seconds; the longest the main loop blocks with nothing pending
WINDOW = 0.25  # seconds; at most one {"changed": [...]} line per window
EOF = object()
# The event kinds that nudge. Any other `event` value is ignored.
EVENTS = frozenset({"run_upsert", "story_upsert", "subtask_upsert", "phase_upsert",
                    "attempt_upsert", "lease_acquired", "lease_taken_over",
                    "control_requested", "control_handled", "claim_conflict"})


class SchemaMismatch(Exception):
    """A hello line without an integer schema of 1 or higher, or without a
    non-negative integer head."""


class Stop(Exception):
    """SIGINT or SIGTERM: the store (or a user) is done with this watch."""


def on_signal(signum, frame):
    raise Stop()


def say(payload, code=0):
    """emit() one line and flush it now: stdout is a pipe, so it is block-buffered."""
    emit(payload)
    sys.stdout.flush()
    return code


def failure(kind, message, code=1):
    return say({"ok": False, "error": {"type": kind, "message": message}}, code)


def parse_args(argv):
    """(roots, run ids, extra) for the helper's argv, or None for a Usage error.
    Left to right: `--since-seq` takes the next argument as N (one or more ASCII
    decimal digits; extra is ["--since-seq", N's integer as decimal text], else
    []); an argument beginning with `/` is a root; any other non-empty argument
    not beginning with `-` is a run id. No root, a second --since-seq, or an
    empty or other `-` argument is None."""
    roots, run_ids, extra = [], [], None
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--since-seq":
            value = argv[i + 1] if i + 1 < len(argv) else ""
            if extra is not None or not (value and value.isascii() and value.isdigit()):
                return None
            extra = ["--since-seq", value.lstrip("0") or "0"]
            i += 2
            continue
        if arg.startswith("/"):
            roots.append(arg)
        elif not arg or arg.startswith("-"):
            return None
        else:
            run_ids.append(arg)
        i += 1
    if not roots:
        return None
    return roots, run_ids, extra or []


def check_hello(hello):
    """The printed fields of a hello line: schema, am ("" when not a string),
    head, cursorReset (true only for a JSON true) and storeId ("" when not a
    string). Raises SchemaMismatch."""
    schema = hello.get("schema")
    if not (type(schema) is int and schema >= 1):
        raise SchemaMismatch("am watch speaks schema " + json.dumps(schema)
                             + "; this helper reads schema 1 or higher.")
    head = hello.get("head")
    if not (type(head) is int and head >= 0):
        raise SchemaMismatch("am watch sent no head; the plugin needs the newer am.")
    version, store = hello.get("am"), hello.get("store_id")
    return {"schema": schema, "am": version if isinstance(version, str) else "",
            "head": head, "cursorReset": hello.get("cursor_reset") is True,
            "storeId": store if isinstance(store, str) else ""}


def nudge(line):
    """(run id, gseq) for a parsed stream line that is a nudge, else None."""
    if not isinstance(line, dict):
        return None
    event, run_id, gseq = line.get("event"), line.get("run_id"), line.get("gseq")
    if not (isinstance(event, str) and event in EVENTS):
        return None
    if not (isinstance(run_id, str) and run_id and type(gseq) is int and gseq >= 1):
        return None
    return run_id, gseq


def same_dir(path, roots):
    """True when `path` names the same directory as one of `roots` (realpaths).
    A path realpath cannot take (an embedded NUL) names none."""
    try:
        return os.path.realpath(path) in roots
    except (ValueError, OSError):
        return False


def watch(line, run_id, watched, roots):
    """True when the nudge `line` of `run_id` is kept: the run is in `watched`,
    or the line is a run_upsert whose payload.repo_dir is a string naming the
    same directory as one of `roots` (realpaths), which adds the run to
    `watched` for good."""
    if run_id in watched:
        return True
    payload = line.get("payload")
    if not (line.get("event") == "run_upsert" and isinstance(payload, dict)):
        return False
    repo_dir = payload.get("repo_dir")
    if not (isinstance(repo_dir, str) and same_dir(repo_dir, roots)):
        return False
    watched.add(run_id)
    return True


def spawn(am, extra):
    return subprocess.Popen([am, "watch", "--all-projects", "--follow", *extra],
                            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, encoding="utf-8",
                            errors="replace")


def pump(stream, sink):
    """Reader thread: every line am prints, then EOF."""
    for raw in stream:
        sink.put(raw)
    sink.put(EOF)


def collect(stream, parts):
    """Reader thread: am's whole stderr, so a chatty am never blocks on a full pipe."""
    parts.append(stream.read())


def stop(proc):
    """Terminate am if it is still running, and reap it."""
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def flush(batch, cursor):
    """Print a non-empty batch (run id -> highest gseq) and the cursor after it."""
    say({"changed": [{"run": run_id, "seq": gseq} for run_id, gseq in batch.items()]})
    say({"cursor": cursor})


def stream(lines, roots, watched):
    """Turn am's stream into the hello line and debounced changed + cursor lines
    until it ends. Every hello line (event "watch") is checked; the first is
    printed at once without touching the batch; later ones print nothing. Only
    nudges `watch` keeps (`roots`: realpaths; `watched`: run ids, grown in
    place) reach the batch and the cursor.
    Trailing edge: the first nudge into an empty batch opens a WINDOW; when it
    closes the batch is printed once and cleared. A pending batch is printed
    when the stream ends. Returns am's refusal envelope (the last line with an
    "ok" key) if it printed one, else None. Raises SchemaMismatch."""
    batch, deadline, refusal, greeted, cursor = {}, None, None, False, 0
    while True:
        if deadline is not None and time.monotonic() >= deadline:
            flush(batch, cursor)
            batch, deadline = {}, None
        wait = IDLE_POLL if deadline is None else max(0.0, deadline - time.monotonic())
        try:
            raw = lines.get(timeout=wait)
        except queue.Empty:
            continue
        if raw is EOF:
            if batch:
                flush(batch, cursor)
            return refusal
        try:
            line = json.loads(raw)
        except ValueError:
            continue
        if isinstance(line, dict) and "ok" in line:
            refusal = line
            continue
        if isinstance(line, dict) and line.get("event") == "watch":
            fields = check_hello(line)
            if not greeted:
                say({"hello": fields})
                greeted = True
            continue
        hit = nudge(line)
        if hit is None:
            continue
        run_id, gseq = hit
        if not watch(line, run_id, watched, roots):
            continue
        batch[run_id] = max(gseq, batch.get(run_id, 0))
        cursor = max(cursor, gseq)
        if deadline is None:
            deadline = time.monotonic() + WINDOW


def finish(code, refusal, stderr):
    """Print the last line, if any, for how am ended; return the helper's exit code."""
    if refusal is not None:
        error = refusal.get("error")
        if code != 3 or (isinstance(error, dict) and error.get("type") == "StoreBusyError"):
            return say(refusal, 1)
        message = error.get("message") if isinstance(error, dict) else None
        if not (isinstance(message, str) and message):
            message = stderr or "am watch refused with exit 3."
        return failure("CorruptJournal", message)
    if code == 0:
        return 0
    if code == 3:
        return failure("CorruptJournal", stderr or "am watch exited 3.")
    return failure("HelperError", stderr or "am watch exited " + str(code) + ".")


def main(argv):
    parsed = parse_args(argv)
    if parsed is None:
        return failure("Usage", USAGE, 2)
    roots, run_ids, extra = parsed
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    proc = spawn(am, extra)
    lines, err = queue.Queue(), []
    threading.Thread(target=pump, args=(proc.stdout, lines), daemon=True).start()
    err_reader = threading.Thread(target=collect, args=(proc.stderr, err), daemon=True)
    err_reader.start()
    try:
        try:
            refusal = stream(lines, {os.path.realpath(root) for root in roots}, set(run_ids))
        except SchemaMismatch as e:
            return failure("SchemaMismatch", str(e))
        code = proc.wait()
        err_reader.join(timeout=2)
    finally:
        stop(proc)  # no-op once am has exited; terminates it on every other path
    return finish(code, refusal, "".join(err).strip())


def quiet_exit():
    """Ended by a signal or a closed stdout: exit 0 without a traceback. stdout
    is pointed at /dev/null so the interpreter's final flush cannot raise."""
    try:
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
    except OSError:
        pass
    return 0


def guarded(argv):
    """SIGINT, SIGTERM and a closed stdout end the helper quietly with exit 0
    (main's finally has already stopped am). Any other unexpected exception
    still ends with one HelperError line."""
    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)  # explicit: SIGINT may be inherited as ignored
    try:
        return main(argv)
    except (Stop, KeyboardInterrupt, BrokenPipeError):
        return quiet_exit()
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        try:
            return failure("HelperError", "The runs watch failed: " + reason)
        except BrokenPipeError:
            return quiet_exit()


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
