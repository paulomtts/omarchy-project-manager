#!/usr/bin/env python3
"""List an am project's runs and each selected run's status.

    runs-snapshot.py <project_root>

Runs `am runs --repo-dir R` (newest first), keeps am's order and selects every
non-terminal run plus the first 10 terminal ones (terminal: done, escalated,
stopped, cancelled, canceled), then runs `am status <id> --repo-dir R` for each
selected run.

Prints exactly one JSON line on EVERY path:
{"ok": true, "runs": [{<am runs summary fields>, "status": <am status data>}],
 "data_dir": <XDG_DATA_HOME in effect, else ~/.local/share>}
or {"ok": false, "error": {"type", "message"}} with type AmMissing, AmBadOutput,
Usage (exit 2) or HelperError; an `ok:false` envelope from am is re-emitted
unchanged. Exit 0 ok, 1 failure, 2 usage. If any `am status` call fails the whole
snapshot fails (no partial result). Only `am` commands are used, always as argv
lists; am's database and on-disk layout are never read.
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
# The finished statuses, matched exactly. A cancelled run is terminal under either
# spelling, `cancelled` or `canceled`. `stopped` is "parked" (resumable) in the
# domain table, but for the snapshot it is terminal and counts toward the cap.
TERMINAL = frozenset({"done", "escalated", "stopped", "cancelled", "canceled"})
TERMINAL_LIMIT = 10


class AmFailure(Exception):
    """An am call that gave no usable data; `payload` is the one line to emit."""

    def __init__(self, payload):
        super().__init__("am call failed")
        self.payload = payload


def bad_output(message):
    return AmFailure({"ok": False, "error": {"type": "AmBadOutput", "message": message}})


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
    """Run one am command and return its envelope's `data`. The envelope's `ok`
    decides, not the exit code: an `ok:false` envelope is raised as-is (to be
    re-emitted unchanged); anything that is not an envelope is AmBadOutput."""
    proc = subprocess.run([am, *args], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    what = "am " + args[0]
    try:
        envelope = json.loads(proc.stdout)
    except ValueError:
        raise bad_output(what + " did not print JSON (exit " + str(proc.returncode) + ").")
    if not isinstance(envelope, dict):
        raise bad_output(what + " printed JSON that is not an object.")
    if envelope.get("ok") is False:
        raise AmFailure(envelope)
    if envelope.get("ok") is not True:
        raise bad_output(what + " printed an object without an ok field.")
    return envelope.get("data")


def run_list(data):
    """`am runs` data's run list, checked: a list of objects with string id/status."""
    runs = data.get("runs") if isinstance(data, dict) else None
    if not isinstance(runs, list):
        raise bad_output("am runs data has no runs list.")
    for run in runs:
        if not (isinstance(run, dict) and isinstance(run.get("id"), str) and run["id"]
                and isinstance(run.get("status"), str)):
            raise bad_output("am runs listed a run without an id or status.")
    return runs


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
        status = call_am(am, ["status", run["id"], "--repo-dir", root])
        if not isinstance(status, dict):
            raise bad_output("am status " + run["id"] + " data is not an object.")
        entry = dict(run)
        entry["status"] = status
        out.append(entry)
    return out


def main(argv):
    if len(argv) != 1:
        return failure("Usage", USAGE, 2)
    root = argv[0]
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    try:
        runs = run_list(call_am(am, ["runs", "--repo-dir", root]))
        result = snapshot(am, root, runs)
    except AmFailure as e:
        return emit(e.payload, 1)
    return emit({"ok": True, "runs": result, "data_dir": data_dir()})


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception (a timeout, an am that cannot start) - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The runs snapshot failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
