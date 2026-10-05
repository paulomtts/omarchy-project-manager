#!/usr/bin/env python3
"""Preview a dispatch: an `am run --dry-run` passthrough.

    dispatch-preview.py ROOT (milestone ID | board) [--base-branch B] [--branch-prefix P]
                        [--max-concurrent N] [--verify CMD]... [--allow-no-verification]

Runs `am run (--milestone ID | --board) --dry-run --repo-dir ROOT`, then the
options given in a fixed order (--base-branch, --branch-prefix,
--max-concurrent, every --verify pair in the order given,
--allow-no-verification), as an argv list (no shell, stdin /dev/null, 60 s
timeout). Every value is the next argument verbatim, even if it starts with
`-`; am refuses bad ones itself. --pretty, --detach and --card are never sent.
A dry run writes nothing, so am is not detached: the store SIGTERMs this helper
when a newer preview starts, and am finishing alone harms nothing.

Prints exactly one JSON line on EVERY path:
- am's envelope, unchanged, whether {"ok": true, "data": ...} or
  {"ok": false, "error": ...}. The envelope's `ok` decides, not am's exit code;
  `data` is never inspected (previewSummary in runs.js reads it);
- {"ok": false, "error": {"type": "AmFailed", ...}} when am exited non-zero
  without an envelope; the message is the tail of am's stderr;
- {"ok": false, "error": {"type": "AmBadOutput", ...}} when am exited 0
  without an envelope;
- {"ok": false, "error": {"type": "AmMissing", ...}} when am is not on PATH;
- {"ok": false, "error": {"type": "HelperError", ...}} on any unexpected
  failure (a timeout, an am that cannot start);
- {"ok": false, "error": {"type": "Usage", ...}} for any other command line.
Exit 0 whenever a line was printed, refusals and errors included; exit 2 for
Usage only.
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = ("usage: dispatch-preview.py ROOT (milestone ID | board) [--base-branch B]"
         " [--branch-prefix P] [--max-concurrent N] [--verify CMD]..."
         " [--allow-no-verification] | dispatch-preview.py --defaults ROOT")
VALUED = ("--base-branch", "--branch-prefix", "--max-concurrent")
AM_TIMEOUT = 60
TAIL_LINES = 20
TAIL_CHARS = 2000


class BadOutput(Exception):
    """am printed something that is not an envelope; the message says what."""


def failure(kind, message, code=0):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def good_root(root):
    return bool(root) and not root.startswith("-")


def parse(argv):
    """("preview", root, milestone, options) for a command line USAGE allows, else None.

    milestone is None for the board. options always maps "--verify" to the list
    of commands in the order given, maps each given VALUED flag to its value and
    "--allow-no-verification" to True when given; a once-only flag given twice
    is a usage error."""
    if len(argv) < 2 or not good_root(argv[0]):
        return None
    root, target, rest = argv[0], argv[1], argv[2:]
    if target == "milestone":
        if not rest or not rest[0]:
            return None
        milestone, rest = rest[0], rest[1:]
    elif target == "board":
        milestone = None
    else:
        return None
    options = {"--verify": []}
    while rest:
        flag = rest[0]
        if flag == "--verify" and len(rest) > 1:
            options["--verify"].append(rest[1])
            rest = rest[2:]
        elif flag in VALUED and len(rest) > 1 and flag not in options:
            options[flag] = rest[1]
            rest = rest[2:]
        elif flag == "--allow-no-verification" and flag not in options:
            options[flag] = True
            rest = rest[1:]
        else:
            return None
    return "preview", root, milestone, options


def preview_argv(root, milestone, options):
    """am's argv after the executable, in a fixed order whatever order the options came in."""
    argv = ["run", "--board"] if milestone is None else ["run", "--milestone", milestone]
    argv += ["--dry-run", "--repo-dir", root]
    for flag in VALUED:
        if flag in options:
            argv += [flag, options[flag]]
    for cmd in options["--verify"]:
        argv += ["--verify", cmd]
    if "--allow-no-verification" in options:
        argv.append("--allow-no-verification")
    return argv


def envelope_of(stdout, returncode):
    """am's envelope, checked only for shape: a JSON object with a boolean `ok`."""
    exit_note = " (exit " + str(returncode) + ")."
    try:
        envelope = json.loads(stdout)
    except ValueError:
        raise BadOutput("am run did not print JSON" + exit_note)
    if not isinstance(envelope, dict):
        raise BadOutput("am run printed JSON that is not an object" + exit_note)
    if not isinstance(envelope.get("ok"), bool):
        raise BadOutput("am run printed an object without a boolean ok field" + exit_note)
    return envelope


def stderr_tail(stderr):
    """The end of am's stderr, where click's usage box or a crash names its cause:
    at most TAIL_LINES lines, and of those at most TAIL_CHARS characters."""
    lines = stderr.rstrip().splitlines()[-TAIL_LINES:]
    return "\n".join(lines)[-TAIL_CHARS:]


def report(stdout, stderr, returncode):
    try:
        envelope = envelope_of(stdout, returncode)
    except BadOutput as e:
        if returncode == 0:
            return failure("AmBadOutput", str(e))
        tail = stderr_tail(stderr)
        return failure("AmFailed", tail or "am run exited " + str(returncode) + " with no output.")
    return emit(envelope)


def run_am(am, argv):
    """(stdout, stderr, returncode) of one dry run."""
    proc = subprocess.run([am, *argv], capture_output=True, encoding="utf-8",
                          errors="replace", stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    return proc.stdout, proc.stderr, proc.returncode


def preview(root, milestone, options):
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    return report(*run_am(am, preview_argv(root, milestone, options)))


def main(argv):
    parsed = parse(argv)
    if parsed is None:
        return failure("Usage", USAGE, 2)
    return preview(*parsed[1:])


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception (a timeout, an am that cannot start) - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The dispatch preview failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
