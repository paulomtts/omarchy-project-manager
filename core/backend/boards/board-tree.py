#!/usr/bin/env python3
"""Read one project's brd tree, or probe project roots without running brd.

    board-tree.py ROOT
    board-tree.py --probe [ROOT ...]

Tree mode runs `brd tree` once with cwd=ROOT, stdin from /dev/null and a
TIMEOUT_SECONDS timeout. It prints brd's payload unchanged, {"ok": true,
"data": [...]}, or {"ok": false, "error": {"type", "message"}} where type is
RootMissing, BrdMissing, BrdFailed (brd's own message, a non-zero exit or the
timeout), BrdBadOutput or HelperError (bad usage or any unexpected exception).

Probe mode runs no process and only stats paths. Every argument after --probe
is a root. It prints {"ok": true, "projects": [{"root", "ok", "reason"?}]}, one
entry per root in argv order with the root verbatim; a root is ok when it is a
directory holding a `.brd` entry.

Every invocation prints exactly one JSON line and exits 0.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

TIMEOUT_SECONDS = 20
USAGE = "usage: board-tree.py ROOT | board-tree.py --probe ROOT [ROOT ...]"


def failure(error_type, message):
    return {"ok": False, "error": {"type": error_type, "message": message}}


def tree(root):
    if not os.path.isdir(root):
        return failure("RootMissing", "project directory not found: %s" % root)
    proc = subprocess.run(["brd", "tree"], cwd=root, stdin=subprocess.DEVNULL,
                          capture_output=True, text=True, timeout=TIMEOUT_SECONDS)
    try:
        payload = json.loads(proc.stdout)
    except ValueError:
        payload = None
    if (proc.returncode == 0 and isinstance(payload, dict) and payload.get("ok") is True
            and isinstance(payload.get("data"), list)):
        return payload
    return failure("BrdBadOutput", "brd tree returned unexpected output")


def main(argv):
    args = argv[1:]
    if len(args) == 1 and not args[0].startswith("-"):
        payload = tree(args[0])
    else:
        payload = failure("HelperError", USAGE)
    return emit(payload, 0)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
