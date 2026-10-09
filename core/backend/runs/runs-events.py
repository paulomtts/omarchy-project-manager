#!/usr/bin/env python3
"""One run's events snapshot: a one-shot `am watch RUN` read.

    runs-events.py RUN [--since SEQ] [--tail N]

Runs `am watch RUN`, plus `--since SEQ` when given (SEQ verbatim), as an argv
list (no shell, stdin /dev/null, 60 s timeout); never `--follow`, `--repo-dir`,
`--all`, `--since-seq` or `--pretty`. am resolves RUN by id. `--tail` never
reaches am.

Prints exactly one JSON line:
- {"ok": true, "events": [...], "last_seq": N, "total": M}: `total` is the
  number of events am printed; `events` are those events in am's order, each
  unchanged, only the last N with `--tail N`; `last_seq` is the highest `seq`
  of every event am printed, or the `--since` value (0 without it) when there
  are none, so it can always be passed back as `--since`;
- {"ok": false, "error": {"type": "Usage", ...}} for any other argv: no RUN, an
  empty or `-`-prefixed RUN, a second positional, an unknown, repeated or
  valueless option, a SEQ that is not ASCII digits, an N that is not ASCII
  digits or is 0.
Exit 0 whenever a line was printed; exit 2 for Usage only. Only the documented
`am watch` command is used; am's database and on-disk layout are never read.
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-events.py RUN [--since SEQ] [--tail N]"
AM_TIMEOUT = 60
OPTIONS = ("--since", "--tail")


def failure(kind, message, code=0):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def ascii_digits(text):
    """True for one or more ASCII digits."""
    return text.isascii() and text.isdigit()


def parse_args(argv):
    """(run, since, tail): since a digit string or None, tail an int of 1 or more
    or None; None for any argv the usage line does not allow."""
    if not argv or argv[0] == "" or argv[0].startswith("-"):
        return None
    options = {}
    rest = list(argv[1:])
    while rest:
        flag = rest.pop(0)
        if flag not in OPTIONS or flag in options or not rest:
            return None
        options[flag] = rest.pop(0)
    since = options.get("--since")
    tail = options.get("--tail")
    if since is not None and not ascii_digits(since):
        return None
    if tail is not None and not (ascii_digits(tail) and int(tail) > 0):
        return None
    return argv[0], since, None if tail is None else int(tail)


def watch_argv(run, since):
    """am's argv after the executable: the run, then --since SEQ when given."""
    return ["watch", run] + ([] if since is None else ["--since", since])


def snapshot(events, since, tail):
    """The success line for am's events; see the module docstring."""
    floor = 0 if since is None else int(since)
    return {
        "ok": True,
        "events": events if tail is None else events[-tail:],
        "last_seq": max((event["seq"] for event in events), default=floor),
        "total": len(events),
    }


def main(argv):
    parsed = parse_args(argv)
    if parsed is None:
        return failure("Usage", USAGE, 2)
    run, since, tail = parsed
    am = shutil.which("am")
    proc = subprocess.run([am, *watch_argv(run, since)], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    envelope = json.loads(proc.stdout)
    return emit(snapshot(envelope["data"]["events"], since, tail))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
