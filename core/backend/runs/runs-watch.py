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


def say(payload, code=0):
    """emit() one line and flush it now: stdout is a pipe, so it is block-buffered."""
    emit(payload)
    sys.stdout.flush()
    return code


def failure(kind, message, code=1):
    return say({"ok": False, "error": {"type": kind, "message": message}}, code)


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


def stream(lines):
    """Drain am's stream until it ends."""
    while True:
        try:
            raw = lines.get(timeout=IDLE_POLL)
        except queue.Empty:
            continue
        if raw is EOF:
            return


def main(argv):
    if not argv:
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
        stream(lines)
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
