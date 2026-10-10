#!/usr/bin/env python3
"""One project's card titles, from `brd tree`.

    board-titles.py ROOT

ROOT is non-empty and does not start with -; any other argv is a Usage error
(exit 2) and brd is not run. ROOT must be an existing directory, else
RootMissing and brd is not run. Runs `brd tree` once, as an argv list, with
cwd ROOT, stdin /dev/null and a TIMEOUT_SECONDS bound. Never writes; brd's
database is never read.

Prints exactly one JSON line on EVERY path:
{"ok": true, "titles": {<card id>: <title>}} for every card at any depth,
or {"ok": false, "error": {"type", "message"}} with type Usage, RootMissing or
BrdMissing. Exit 0 ok, 1 failure, 2 usage.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: board-titles.py ROOT"
TIMEOUT_SECONDS = 30


def failure(kind, message, code=1):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def parse_args(argv):
    """ROOT when argv is exactly one non-empty argument not starting with -;
    None otherwise."""
    if len(argv) == 1 and argv[0] and not argv[0].startswith("-"):
        return argv[0]
    return None


def flatten_titles(data):
    """{id: title} for every card in `data` and, recursively, in its
    `children`; a repeated id keeps the entry visited last in pre-order."""
    titles = {}
    stack = list(reversed(data))
    while stack:
        card = stack.pop()
        titles[card["id"]] = card["title"]
        stack.extend(reversed(card.get("children") or []))
    return titles


def main(argv):
    root = parse_args(argv)
    if root is None:
        return failure("Usage", USAGE, 2)
    if not os.path.isdir(root):
        return failure("RootMissing", "The project directory does not exist: " + root)
    try:
        proc = subprocess.run(["brd", "tree"], cwd=root, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, encoding="utf-8",
                              timeout=TIMEOUT_SECONDS)
    except FileNotFoundError:
        return failure("BrdMissing", "brd is not installed.")
    envelope = json.loads(proc.stdout)
    return emit({"ok": True, "titles": flatten_titles(envelope["data"])})


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
