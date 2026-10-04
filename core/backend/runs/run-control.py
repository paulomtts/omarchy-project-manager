#!/usr/bin/env python3
"""Pause, resume or cancel one run: an `am pause|resume|cancel` passthrough.

    run-control.py <pause|resume|cancel> RUN REPO [--verify CMD]... [--allow-no-verification]

Runs `am ACTION RUN --repo-dir REPO` as an argv list (no shell, stdin
/dev/null, 60 s timeout). Only resume takes options: every `--verify CMD` pair
is forwarded in the order given (CMD is the next argument verbatim, even if it
starts with `-`), then `--allow-no-verification`. --pretty is never sent. RUN,
REPO and CMD reach am unaltered; am refuses a bad repo or an unknown run itself.

Prints exactly one JSON line on EVERY path:
- am's envelope, unchanged, whether {"ok": true, "data": ...} or
  {"ok": false, "error": ...}. The envelope's `ok` decides, not am's exit code;
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

USAGE = ("usage: run-control.py <pause|resume|cancel> RUN REPO"
         " [--verify CMD]... [--allow-no-verification]")
ACTIONS = ("pause", "resume", "cancel")
AM_TIMEOUT = 60
TAIL_LINES = 20
TAIL_CHARS = 2000


class BadOutput(Exception):
    """am printed something that is not an envelope; the message says what."""


def failure(kind, message, code=0):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def parse(argv):
    """(action, run, repo, verify, allow) for a command line USAGE allows, else None."""
    if len(argv) < 3:
        return None
    action, run, repo = argv[:3]
    if action not in ACTIONS or not run or run.startswith("-") or not repo:
        return None
    verify, allow, rest = [], False, argv[3:]
    while rest:
        if rest[0] == "--verify" and len(rest) > 1:
            verify.append(rest[1])
            rest = rest[2:]
        elif rest[0] == "--allow-no-verification":
            allow = True
            rest = rest[1:]
        else:
            return None
    if action != "resume" and (verify or allow):
        return None
    return action, run, repo, verify, allow


def control_argv(action, run, repo, verify, allow):
    """am's argv after the executable: every --verify pair, then --allow-no-verification."""
    argv = [action, run, "--repo-dir", repo]
    for cmd in verify:
        argv += ["--verify", cmd]
    if allow:
        argv.append("--allow-no-verification")
    return argv


def envelope_of(action, stdout, returncode):
    """am's envelope, checked only for shape: a JSON object with a boolean `ok`."""
    name = "am " + action
    exit_note = " (exit " + str(returncode) + ")."
    try:
        envelope = json.loads(stdout)
    except ValueError:
        raise BadOutput(name + " did not print JSON" + exit_note)
    if not isinstance(envelope, dict):
        raise BadOutput(name + " printed JSON that is not an object" + exit_note)
    if not isinstance(envelope.get("ok"), bool):
        raise BadOutput(name + " printed an object without a boolean ok field" + exit_note)
    return envelope


def stderr_tail(stderr):
    """The end of am's stderr, where a crash names its cause: at most TAIL_LINES
    lines, and of those at most TAIL_CHARS characters."""
    lines = stderr.rstrip().splitlines()[-TAIL_LINES:]
    return "\n".join(lines)[-TAIL_CHARS:]


def report(action, stdout, stderr, returncode):
    try:
        envelope = envelope_of(action, stdout, returncode)
    except BadOutput as e:
        if returncode == 0:
            return failure("AmBadOutput", str(e))
        tail = stderr_tail(stderr)
        return failure("AmFailed", tail or "am " + action + " exited "
                       + str(returncode) + " with no output.")
    return emit(envelope)


def run_am(am, argv):
    """pause/cancel: am answers at once. Returns (stdout, stderr, returncode)."""
    proc = subprocess.run([am, *argv], capture_output=True, encoding="utf-8",
                          errors="replace", stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    return proc.stdout, proc.stderr, proc.returncode


def main(argv):
    parsed = parse(argv)
    if parsed is None:
        return failure("Usage", USAGE, 2)
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    return report(parsed[0], *run_am(am, control_argv(*parsed)))


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception (a timeout, an am that cannot start) - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The run control failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
