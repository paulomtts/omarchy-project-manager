#!/usr/bin/env python3
"""One run's events snapshot: a one-shot `am watch RUN` read.

    runs-events.py RUN [--since SEQ] [--tail N]

Runs `am watch RUN`, plus `--since SEQ` when given (SEQ verbatim), as an argv
list (no shell, stdin /dev/null, 60 s timeout); never `--follow`, `--repo-dir`,
`--all`, `--since-seq` or `--pretty`. am resolves RUN by id. `--tail` never
reaches am.

Prints exactly one JSON line on EVERY path:
- {"ok": true, "events": [...], "last_seq": N, "total": M} when am's envelope
  is `ok: true`; the envelope's `ok` decides, not am's exit code. `total` is
  the number of events am printed; `events` are those events in am's order,
  each unchanged, only the last N with `--tail N`; `last_seq` is the highest
  `seq` of every event am printed, or the `--since` value (0 without it) when
  there are none, so it can always be passed back as `--since`;
- am's {"ok": false, "error": ...} envelope, unchanged (UnknownRunError,
  StoreBusyError, ...), whatever am's exit code;
- {"ok": false, "error": {"type": "CorruptJournal", ...}} when am exits 3 and
  its stdout is not a JSON object with a boolean `ok`; the message is am's
  stderr, stripped, or "am watch exited 3.";
- {"ok": false, "error": {"type": "AmBadOutput", ...}} when am's stdout, at
  any other exit code, is not a JSON object with a boolean `ok`, or when an
  `ok: true` envelope has no object `data`, no list `data.events`, or an event
  that is not an object with an integer `seq`;
- {"ok": false, "error": {"type": "AmMissing", ...}} when am is not on PATH;
- {"ok": false, "error": {"type": "HelperError", ...}} on any unexpected
  failure (a timeout, an am that cannot start);
- {"ok": false, "error": {"type": "Usage", ...}} for any other argv: no RUN, an
  empty or `-`-prefixed RUN, a second positional, an unknown, repeated or
  valueless option, a SEQ that is not ASCII digits, an N that is not ASCII
  digits or is 0.
Exit 0 whenever a line was printed, refusals and errors included; exit 2 for
Usage only. Only the documented `am watch` command is used; am's database and
on-disk layout are never read.
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


class BadOutput(Exception):
    """am printed something that is not a usable envelope; the message says what."""


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


def is_int(value):
    """True for a JSON integer (a bool is not one)."""
    return isinstance(value, int) and not isinstance(value, bool)


def envelope_of(stdout, returncode):
    """am's envelope, checked only for shape: a JSON object with a boolean `ok`."""
    exit_note = " (exit " + str(returncode) + ")."
    try:
        envelope = json.loads(stdout)
    except ValueError:
        raise BadOutput("am watch did not print JSON" + exit_note)
    if not isinstance(envelope, dict):
        raise BadOutput("am watch printed JSON that is not an object" + exit_note)
    if not isinstance(envelope.get("ok"), bool):
        raise BadOutput("am watch printed an object without a boolean ok field" + exit_note)
    return envelope


def events_of(envelope, returncode):
    """An ok envelope's `data.events`: a list of objects, each with an integer `seq`."""
    exit_note = " (exit " + str(returncode) + ")."
    data = envelope.get("data")
    if not isinstance(data, dict):
        raise BadOutput("am watch printed ok without a data object" + exit_note)
    events = data.get("events")
    if not isinstance(events, list):
        raise BadOutput("am watch printed data without an events list" + exit_note)
    if not all(isinstance(event, dict) and is_int(event.get("seq")) for event in events):
        raise BadOutput("am watch printed an event without an integer seq" + exit_note)
    return events


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
    if am is None:
        return failure("AmMissing", "am is not installed.")
    proc = subprocess.run([am, *watch_argv(run, since)], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    try:
        envelope = envelope_of(proc.stdout, proc.returncode)
    except BadOutput as e:
        if proc.returncode == 3:
            return failure("CorruptJournal", proc.stderr.strip() or "am watch exited 3.")
        return failure("AmBadOutput", str(e))
    if not envelope["ok"]:
        return emit(envelope)
    try:
        events = events_of(envelope, proc.returncode)
    except BadOutput as e:
        return failure("AmBadOutput", str(e))
    return emit(snapshot(events, since, tail))


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception (a timeout, an am that cannot start) - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The events snapshot failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
