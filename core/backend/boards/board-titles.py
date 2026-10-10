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
or brd's own ok:false envelope unchanged, whatever brd's exit code,
or {"ok": false, "error": {"type", "message"}} with type Usage, RootMissing,
BrdMissing or BrdBadOutput (stdout not a JSON object; ok neither true nor
false; ok true with a non-zero exit; data not a list; a card at any depth not
an object, its id not a non-empty string, its title not a string, or its
children present, not null and not a list). Exit 0 ok, 1 failure, 2 usage.
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
    `children`; a repeated id keeps the entry visited last in pre-order.
    None when `data` is not a list or any card is not an object with a
    non-empty string id, a string title, and children absent, null or a list."""
    if not isinstance(data, list):
        return None
    titles = {}
    stack = list(reversed(data))
    while stack:
        card = stack.pop()
        if not isinstance(card, dict):
            return None
        card_id, title, children = card.get("id"), card.get("title"), card.get("children")
        if not (isinstance(card_id, str) and card_id) or not isinstance(title, str):
            return None
        if children is None:
            children = []
        if not isinstance(children, list):
            return None
        titles[card_id] = title
        stack.extend(reversed(children))
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
    try:
        envelope = json.loads(proc.stdout)
    except ValueError:
        return failure("BrdBadOutput", "brd tree did not print JSON (exit %d)." % proc.returncode)
    if not isinstance(envelope, dict):
        return failure("BrdBadOutput", "brd tree printed JSON that is not an object.")
    if envelope.get("ok") is False:
        return emit(envelope, 1)
    if envelope.get("ok") is not True:
        return failure("BrdBadOutput", "brd tree printed an envelope whose ok is neither true nor false.")
    if proc.returncode != 0:
        return failure("BrdBadOutput", "brd tree reported ok but exited with code %d." % proc.returncode)
    titles = flatten_titles(envelope.get("data"))
    if titles is None:
        return failure("BrdBadOutput", "brd tree printed cards that are not in the expected shape.")
    return emit({"ok": True, "titles": titles})


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
