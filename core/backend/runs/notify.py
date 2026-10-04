#!/usr/bin/env python3
"""Show a desktop notification through notify-send.

    notify.py TITLE BODY

Runs `notify-send -- TITLE BODY` as an argv list (no shell, stdin /dev/null,
output captured, a NOTIFY_TIMEOUT s timeout). TITLE and BODY reach notify-send
verbatim; `--` keeps a TITLE starting with `-` from being read as an option.
TITLE must not be blank; BODY may be empty. Whether to alert at all is the
caller's call: this script reads no settings and no files.

Prints exactly one JSON line on EVERY path:
- {"ok": true, "sent": true} when notify-send ran;
- {"ok": true, "sent": false} when notify-send is not on PATH (nothing is run);
- {"ok": false, "error": {"type": "Usage", ...}} for any other command line.
Exit 0 whenever a line was printed; exit 2 for Usage only.
"""
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: notify.py TITLE BODY"
NOTIFY_TIMEOUT = 10


def failure(kind, message, code=0):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def main(argv):
    if len(argv) != 2 or not argv[0].strip():
        return failure("Usage", USAGE, 2)
    notify_send = shutil.which("notify-send")
    if notify_send is None:
        return emit({"ok": True, "sent": False})
    title, body = argv
    subprocess.run([notify_send, "--", title, body], capture_output=True, encoding="utf-8",
                   errors="replace", stdin=subprocess.DEVNULL, timeout=NOTIFY_TIMEOUT)
    return emit({"ok": True, "sent": True})


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
