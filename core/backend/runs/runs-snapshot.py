#!/usr/bin/env python3
"""List an am project's runs and each selected run's status.

    runs-snapshot.py <project_root>

Runs `am runs --repo-dir R` (newest first), keeps am's order and selects every
non-terminal run plus the first 10 terminal ones (terminal: done, escalated,
stopped, cancelled), then runs `am status <id> --repo-dir R` for each selected
run.

Prints exactly one JSON line on EVERY path:
{"ok": true, "runs": [{<am runs summary fields>, "status": <am status data>}],
 "data_dir": <XDG_DATA_HOME in effect, else ~/.local/share>}
or {"ok": false, "error": {"type", "message"}} with type AmMissing, AmBadOutput,
Usage (exit 2) or HelperError; an `ok:false` envelope from am is re-emitted
unchanged. Exit 0 ok, 1 failure, 2 usage. Only `am` commands are used, always as
argv lists; am's database and on-disk layout are never read.
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-snapshot.py <project_root>"
AM_TIMEOUT = 60
# The monitor spec's finished list. `stopped` is "parked" (resumable) in the domain
# table, but for the snapshot it is terminal and counts toward the cap.
TERMINAL = frozenset({"done", "escalated", "stopped", "cancelled"})
TERMINAL_LIMIT = 10


def failure(kind, message, code=1):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def data_dir():
    """XDG_DATA_HOME, but only when it is absolute (like `state_home()` in
    run-setup-milestone.py); otherwise ~/.local/share. No am subdirectory: that
    would assume am's on-disk layout."""
    data = os.environ.get("XDG_DATA_HOME") or ""
    if not os.path.isabs(data):
        return os.path.join(os.path.expanduser("~"), ".local", "share")
    return data


def call_am(am, args):
    proc = subprocess.run([am, *args], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    return json.loads(proc.stdout)["data"]


def select_runs(runs):
    """Every non-terminal run plus the first TERMINAL_LIMIT terminal ones, in am's
    (newest-first) order."""
    picked, terminal = [], 0
    for run in runs:
        if run["status"] in TERMINAL:
            if terminal >= TERMINAL_LIMIT:
                continue
            terminal += 1
        picked.append(run)
    return picked


def snapshot(am, root, runs):
    """Each selected run's summary with `status` replaced by its `am status` data."""
    out = []
    for run in select_runs(runs):
        entry = dict(run)
        entry["status"] = call_am(am, ["status", run["id"], "--repo-dir", root])
        out.append(entry)
    return out


def main(argv):
    if len(argv) != 1:
        return failure("Usage", USAGE, 2)
    root = argv[0]
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    runs = call_am(am, ["runs", "--repo-dir", root])["runs"]
    return emit({"ok": True, "runs": snapshot(am, root, runs), "data_dir": data_dir()})


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The runs snapshot failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
