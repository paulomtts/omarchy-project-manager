#!/usr/bin/env python3
"""Print an alert when a run of a registered project escalates, from
`am watch --all --follow --from-now`.

    runs-alerts.py

Takes no argument; any argument is a Usage error (exit 2) and neither am nor
brd is looked up or run. Long-lived. Spawns `am watch --all --follow
--from-now` as an argv list, never a shell. Prints one JSON object per line,
flushed at once:
  {"ok": false, "error": {"type", "message"}}
      then exit 1, with type SchemaMismatch, CorruptJournal (am exited 3),
      HelperError or AmMissing (Usage exits 2). An am refusal envelope is
      re-emitted unchanged when am exits other than 3, or when its type is
      StoreBusyError.
Every hello line (event "watch") must carry an integer schema of 1 or 2, else
SchemaMismatch. Every other line is ignored. am exiting 0, SIGINT, SIGTERM or
a closed stdout end the helper with exit 0. Only the `am` command is used;
am's database and on-disk layout are never read.
"""
import json
import os
import queue
import shutil
import signal
import subprocess
import sys
import threading

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-alerts.py"
IDLE_POLL = 1.0  # seconds; the longest the main loop blocks with nothing pending
EOF = object()


class SchemaMismatch(Exception):
    """A hello line whose schema is not the integer 1 or 2."""


class Stop(Exception):
    """SIGINT or SIGTERM: the service (or a user) is done with these alerts."""


def on_signal(signum, frame):
    raise Stop()


def say(payload, code=0):
    """emit() one line and flush it now: stdout is a pipe, so it is block-buffered."""
    emit(payload)
    sys.stdout.flush()
    return code


def failure(kind, message, code=1):
    return say({"ok": False, "error": {"type": kind, "message": message}}, code)


def check_hello(hello):
    """Raises SchemaMismatch unless the hello line's schema is the integer 1 or 2."""
    schema = hello.get("schema")
    if not (type(schema) is int and schema in (1, 2)):
        raise SchemaMismatch("am watch speaks schema " + json.dumps(schema)
                             + "; this helper reads schema 1 or 2.")


def spawn(am):
    return subprocess.Popen([am, "watch", "--all", "--follow", "--from-now"],
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


def stream(lines):
    """Read am's stream until it ends. Every hello line (event "watch") is
    checked; every other line is ignored. Returns am's refusal envelope (the
    last line with an "ok" key) if it printed one, else None. Raises
    SchemaMismatch."""
    refusal = None
    while True:
        try:
            raw = lines.get(timeout=IDLE_POLL)
        except queue.Empty:
            continue
        if raw is EOF:
            return refusal
        try:
            line = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(line, dict):
            continue
        if "ok" in line:
            refusal = line
            continue
        if line.get("event") == "watch":
            check_hello(line)


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
    if argv:
        return failure("Usage", USAGE, 2)
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    proc = spawn(am)
    lines, err = queue.Queue(), []
    threading.Thread(target=pump, args=(proc.stdout, lines), daemon=True).start()
    err_reader = threading.Thread(target=collect, args=(proc.stderr, err), daemon=True)
    err_reader.start()
    try:
        try:
            refusal = stream(lines)
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
            return failure("HelperError", "The runs alerts failed: " + reason)
        except BrokenPipeError:
            return quiet_exit()


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
