#!/usr/bin/env python3
"""One attempt's (or the phase's newest) output snapshot: an `am logs` passthrough.

    runs-logs.py <project_root> RUN CARD PHASE ATTEMPT

Runs `am logs RUN CARD --phase PHASE --attempt ATTEMPT --repo-dir ROOT` as an
argv list (no shell, stdin /dev/null, 60 s timeout). With ATTEMPT `0` no
--attempt is sent (`am logs RUN CARD --phase PHASE --repo-dir ROOT`), so am
returns the phase's newest recorded output: this is how a step's output is read,
since steps record no attempts in `am status`. Any other ATTEMPT is sent verbatim
with --attempt. The arguments reach am unvalidated, attempt `0` being the one
exception; am refuses bad ones itself.

Prints exactly one JSON line on EVERY path:
- am's envelope, unchanged, whether {"ok": true, "data": ...} or
  {"ok": false, "error": ...}. The envelope's `ok` decides, not am's exit code;
  `data` is neither inspected nor trimmed (tail-limiting is the store's job);
- {"ok": false, "error": {"type": "AmMissing", ...}} when am is not on PATH;
- {"ok": false, "error": {"type": "AmBadOutput", ...}} when am's stdout is not
  JSON, is not an object, or has no boolean `ok`;
- {"ok": false, "error": {"type": "HelperError", ...}} on any unexpected
  failure (a timeout, an am that cannot start);
- {"ok": false, "error": {"type": "Usage", ...}} when not given exactly five
  arguments.
Exit 0 whenever a line was printed, refusals and errors included; exit 2 for
Usage only. Only the documented `am logs` command is used; am's database and
on-disk layout are never read.
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-logs.py <project_root> RUN CARD PHASE ATTEMPT"
AM_TIMEOUT = 60


class BadOutput(Exception):
    """am printed something that is not an envelope; the message says what."""


def failure(kind, message, code=0):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def logs_argv(root, run, card, phase, attempt):
    """am's argv after the executable: --attempt ATTEMPT, omitted when ATTEMPT is
    exactly "0" (am's newest output of the phase), then --repo-dir ROOT."""
    chosen = [] if attempt == "0" else ["--attempt", attempt]
    return ["logs", run, card, "--phase", phase, *chosen, "--repo-dir", root]


def envelope_of(stdout, returncode):
    """am's envelope, checked only for shape: a JSON object with a boolean `ok`."""
    exit_note = " (exit " + str(returncode) + ")."
    try:
        envelope = json.loads(stdout)
    except ValueError:
        raise BadOutput("am logs did not print JSON" + exit_note)
    if not isinstance(envelope, dict):
        raise BadOutput("am logs printed JSON that is not an object" + exit_note)
    if not isinstance(envelope.get("ok"), bool):
        raise BadOutput("am logs printed an object without a boolean ok field" + exit_note)
    return envelope


def main(argv):
    if len(argv) != 5:
        return failure("Usage", USAGE, 2)
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    proc = subprocess.run([am, *logs_argv(*argv)], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    try:
        envelope = envelope_of(proc.stdout, proc.returncode)
    except BadOutput as e:
        return failure("AmBadOutput", str(e))
    return emit(envelope)


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception (a timeout, an am that cannot start) - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The logs snapshot failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
