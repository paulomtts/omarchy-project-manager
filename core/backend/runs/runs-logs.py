#!/usr/bin/env python3
"""One attempt's output snapshot: an `am logs` passthrough.

    runs-logs.py RUN CARD PHASE ATTEMPT

Runs `am logs RUN CARD --phase PHASE --attempt ATTEMPT` and re-prints am's
envelope unchanged as one JSON line, exit 0.
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

AM_TIMEOUT = 60


def logs_argv(run, card, phase, attempt):
    """am's argv after the executable. No --repo-dir: am resolves the run by id."""
    return ["logs", run, card, "--phase", phase, "--attempt", attempt]


def main(argv):
    run, card, phase, attempt = argv
    am = shutil.which("am")
    proc = subprocess.run([am, *logs_argv(run, card, phase, attempt)], capture_output=True,
                          text=True, stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    return emit(json.loads(proc.stdout))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
