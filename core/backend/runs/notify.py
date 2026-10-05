#!/usr/bin/env python3
"""Show a desktop notification through notify-send.

    notify.py TITLE BODY

Runs `notify-send -- TITLE BODY` as an argv list (no shell, stdin /dev/null,
output captured, a NOTIFY_TIMEOUT s timeout). TITLE and BODY reach notify-send
verbatim; `--` keeps a TITLE starting with `-` from being read as an option.
TITLE must not be blank; BODY may be empty. Whether to alert at all is the
caller's call: this script reads no settings and no files.

Prints exactly one JSON line on EVERY path:
- {"ok": true, "sent": true} when notify-send exited 0 (its output is ignored);
- {"ok": true, "sent": false} when notify-send is not on PATH (nothing is run);
- {"ok": false, "error": {"type": "NotifyFailed", ...}} when notify-send exited
  non-zero; the message is "notify-send exited N: " and the tail of its stderr,
  or "notify-send exited N with no output." when stderr is blank;
- {"ok": false, "error": {"type": "HelperError", ...}} on any unexpected
  failure (a timeout, a notify-send that cannot start);
- {"ok": false, "error": {"type": "Usage", ...}} for any other command line.
Exit 0 whenever a line was printed, failures included; exit 2 for Usage only.
"""
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: notify.py TITLE BODY"
NOTIFY_TIMEOUT = 10
TAIL_LINES = 20
TAIL_CHARS = 2000


def failure(kind, message, code=0):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def stderr_tail(stderr):
    """The end of notify-send's stderr, where a failure names its cause: at most
    TAIL_LINES lines, and of those at most TAIL_CHARS characters."""
    lines = stderr.rstrip().splitlines()[-TAIL_LINES:]
    return "\n".join(lines)[-TAIL_CHARS:]


def main(argv):
    if len(argv) != 2 or not argv[0].strip():
        return failure("Usage", USAGE, 2)
    notify_send = shutil.which("notify-send")
    if notify_send is None:
        return emit({"ok": True, "sent": False})
    title, body = argv
    proc = subprocess.run([notify_send, "--", title, body], capture_output=True,
                          encoding="utf-8", errors="replace", stdin=subprocess.DEVNULL,
                          timeout=NOTIFY_TIMEOUT)
    if proc.returncode != 0:
        exited = "notify-send exited " + str(proc.returncode)
        tail = stderr_tail(proc.stderr)
        return failure("NotifyFailed", exited + ": " + tail if tail else exited + " with no output.")
    return emit({"ok": True, "sent": True})


def guarded(argv):
    """The caller parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception (a timeout, a notify-send that cannot start) - may end
    without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The notification failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
