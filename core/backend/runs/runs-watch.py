#!/usr/bin/env python3
"""Signal which watched am runs changed, from `am watch --all --follow`.

    runs-watch.py <project_root> [run_id ...]

Long-lived. Spawns `am watch --all --follow` (an argv list, never a shell) and
prints one JSON line per output event, flushed at once:
  {"changed": ["<run id>", ...]}  at most once per 250 ms, never empty, run ids
                                  only (event contents are never forwarded)
  {"ok": false, "error": {"type", "message"}}  then exit 1, with type
                                  SchemaMismatch, CorruptJournal, HelperError or
                                  AmMissing (Usage exits 2); an am refusal
                                  envelope with an exit other than 3 is
                                  re-emitted unchanged.
The hello line is dropped (its schema must be 1). Journal lines written before
the helper started (the backlog) are dropped. A journal line is kept when its
event is one of the five schema-1 events and its run id is watched: the argv run
ids, plus every run whose run_upsert payload.repo_dir is this project root.
Unknown events, unknown keys and non-JSON lines are ignored. am exiting 0,
SIGINT, SIGTERM or a closed stdout end the helper with exit 0. Only the `am`
command is used; am's database and on-disk layout are never read.
"""
import datetime
import json
import os
import queue
import shutil
import subprocess
import sys
import threading

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-watch.py <project_root> [run_id ...]"
IDLE_POLL = 1.0  # seconds; the longest the main loop blocks with nothing pending
EOF = object()
# The schema-1 journal events. Any other `event` value is ignored.
EVENTS = frozenset({"run_upsert", "story_upsert", "subtask_upsert", "phase_upsert",
                    "attempt_upsert"})


def say(payload, code=0):
    """emit() one line and flush it now: stdout is a pipe, so it is block-buffered."""
    emit(payload)
    sys.stdout.flush()
    return code


def failure(kind, message, code=1):
    return say({"ok": False, "error": {"type": kind, "message": message}}, code)


def parse_ts(value):
    """A journal `ts` (ISO 8601, UTC, usually ending in Z) as an aware datetime,
    or None when it is missing or unparseable."""
    if not isinstance(value, str):
        return None
    text = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        ts = datetime.datetime.fromisoformat(text)
    except ValueError:
        return None
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=datetime.timezone.utc)
    return ts


# --- Backlog drop (S4 workaround) ------------------------------------------------
# `am watch --follow` replays every journal line before going live. Until
# `am watch --from-now` exists (S4), lines written before this helper started
# are dropped here. When S4 lands: pass --from-now in spawn(), delete this
# function, and delete its one call in keep().
def is_backlog(line, started):
    ts = parse_ts(line.get("ts"))
    return ts is not None and ts < started


def keep(line, watched, started):
    """The run id a parsed stream line signals, or None to ignore the line."""
    if not isinstance(line, dict):
        return None
    run_id = line.get("run_id")
    if not (isinstance(run_id, str) and run_id) or line.get("event") not in EVENTS:
        return None
    if is_backlog(line, started):
        return None
    return run_id if run_id in watched else None


def spawn(am):
    return subprocess.Popen([am, "watch", "--all", "--follow"], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, encoding="utf-8", errors="replace")


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


def stream(lines, watched, started):
    """Collect the run ids of kept lines until am's stream ends, then print them."""
    batch = []
    while True:
        try:
            raw = lines.get(timeout=IDLE_POLL)
        except queue.Empty:
            continue
        if raw is EOF:
            if batch:
                say({"changed": batch})
            return
        try:
            line = json.loads(raw)
        except ValueError:
            continue
        run_id = keep(line, watched, started)
        if run_id is not None and run_id not in batch:
            batch.append(run_id)


def main(argv):
    if not argv:
        return failure("Usage", USAGE, 2)
    watched = set(argv[1:])
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    started = datetime.datetime.now(datetime.timezone.utc)  # before am starts
    proc = spawn(am)
    lines, err = queue.Queue(), []
    threading.Thread(target=pump, args=(proc.stdout, lines), daemon=True).start()
    err_reader = threading.Thread(target=collect, args=(proc.stderr, err), daemon=True)
    err_reader.start()
    try:
        stream(lines, watched, started)
        code = proc.wait()
        err_reader.join(timeout=2)
    finally:
        stop(proc)
    return 0 if code == 0 else 1


def guarded(argv):
    """No unexpected exception may end the helper without a JSON line."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The runs watch failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
