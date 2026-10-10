"""The am calls, the run snapshot and the time parser shared by the run helpers.

Runs only `am runs <scope> --limit LIST_LIMIT` and `am status RUN` (never with
--repo-dir), as argv lists, each bounded by the caller's `timeout`; reads
nothing but am's stdout. Every failure is an AmFailure whose `payload` is the
one line to print, except subprocess.TimeoutExpired and OSError (am hangs or
cannot start), which propagate. Prints nothing and never exits.
"""
import datetime
import json
import os
import subprocess

AM_TIMEOUT = 60
LIST_LIMIT = 200
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


def schema_mismatch(what):
    return AmFailure({"ok": False, "error": {
        "type": "SchemaMismatch",
        "message": what + " sent no non-negative integer as_of_seq; "
                          "the plugin needs the newer am."}})


def as_of_seq(data, what):
    """`data`'s as_of_seq, a non-negative JSON integer (not a bool, float or
    string); else SchemaMismatch, naming the am command `what`."""
    seq = data.get("as_of_seq")
    if not (type(seq) is int and seq >= 0):
        raise schema_mismatch(what)
    return seq


def store_id(data):
    """`data`'s store_id when a string, else ""."""
    store = data.get("store_id")
    return store if isinstance(store, str) else ""


def data_dir():
    """XDG_DATA_HOME, but only when it is absolute (like `state_home()` in
    run-setup-milestone.py); otherwise ~/.local/share. No am subdirectory: that
    would assume am's on-disk layout."""
    data = os.environ.get("XDG_DATA_HOME") or ""
    if not os.path.isabs(data):
        return os.path.join(os.path.expanduser("~"), ".local", "share")
    return data


def parse_time(value):
    """An ISO-8601 time (`Z` or an offset) as an aware datetime; no offset means UTC.
    None when it does not parse."""
    if not isinstance(value, str):
        return None
    try:
        when = datetime.datetime.fromisoformat(value)
    except ValueError:
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=datetime.timezone.utc)
    return when


def call_am(am, args, timeout):
    """Run one am command (at most `timeout` seconds) and return its envelope's
    `data`. The envelope's `ok` decides, not the exit code: an `ok:false`
    envelope is raised as-is (to be re-emitted unchanged); anything that is not
    an envelope is AmBadOutput."""
    proc = subprocess.run([am, *args], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=timeout)
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


def run_status(am, run_id, timeout):
    """`am status RUN` data (never with --repo-dir), checked: an object
    (else AmBadOutput) with an as_of_seq (else SchemaMismatch)."""
    status = call_am(am, ["status", run_id], timeout)
    if not isinstance(status, dict):
        raise bad_output("am status " + run_id + " data is not an object.")
    as_of_seq(status, "am status " + run_id)
    return status


def list_snapshot(am, scope, timeout):
    """`am runs <scope> --limit LIST_LIMIT`, checked before any status call, then
    each selected run's row with `status` replaced by its `am status` data; every
    am call gets `timeout`."""
    data = call_am(am, ["runs", *scope, "--limit", str(LIST_LIMIT)], timeout)
    runs = run_list(data)
    seq = as_of_seq(data, "am runs")
    out = []
    for run in select_runs(runs):
        entry = dict(run)
        entry["status"] = run_status(am, run["id"], timeout)
        out.append(entry)
    return {"ok": True, "as_of_seq": seq, "store_id": store_id(data), "runs": out,
            "data_dir": data_dir()}


def single_snapshot(am, run_id, timeout):
    """`am status RUN` alone: the run id as given, its status data verbatim and
    that data's as_of_seq and store_id."""
    status = run_status(am, run_id, timeout)
    return {"ok": True, "run": run_id, "as_of_seq": status["as_of_seq"],
            "store_id": store_id(status), "status": status, "data_dir": data_dir()}
