"""common.am_runs: the am calls and the snapshot, against a fake am in tmp_path.

The fake am logs each argv as a JSON line to calls.log beside it, prints the
reply for its call ("runs" or "status-<id>"; "" when none) and exits with the
given code. The real am is never run.
"""
import copy
import json
import os
import subprocess
import sys
import time

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), *[".."] * 4, "core", "backend"))
from common import am_runs  # noqa: E402

FAKE_AM = '''#!/usr/bin/env python3
import json, os, sys
here = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]
with open(os.path.join(here, "calls.log"), "a") as f:
    f.write(json.dumps(args) + "\\n")
replies = json.loads(%r)
name = "runs" if args[:1] == ["runs"] else "status-" + (args[1] if len(args) > 1 else "")
sys.stdout.write(replies.get(name, ""))
sys.exit(%d)
'''

# An am that sleeps 10 s on `am status`, and answers `am runs` at once with one
# started run r1.
SLOW_STATUS_AM = '''#!/usr/bin/env python3
import json, sys, time
if sys.argv[1:2] == ["status"]:
    time.sleep(10)
sys.stdout.write(json.dumps({"ok": True, "data": {"as_of_seq": 1, "store_id": "s",
                 "runs": [{"id": "r1", "status": "started"}]}}))
'''

NEWER_AM = " sent no non-negative integer as_of_seq; the plugin needs the newer am."


def write_exec(path, text):
    path.write_text(text)
    path.chmod(0o755)
    return str(path)


def fake_am(tmp_path, replies, code=0):
    """The fake am at tmp_path/am; `replies` maps "runs" / "status-<id>" to stdout text."""
    return write_exec(tmp_path / "am", FAKE_AM % (json.dumps(replies), code))


def ok(data):
    return json.dumps({"ok": True, "data": data})


def calls(tmp_path):
    log = tmp_path / "calls.log"
    if not log.exists():
        return []
    return [json.loads(line) for line in log.read_text().splitlines()]


def error_of(excinfo):
    return excinfo.value.payload["error"]


# --- call_am ------------------------------------------------------------------

def test_call_am_returns_data_of_an_ok_envelope(tmp_path):
    am = fake_am(tmp_path, {"runs": ok({"runs": [], "as_of_seq": 3})})
    args = ["runs", "--all-projects", "--limit", "200"]
    assert am_runs.call_am(am, args, 5) == {"runs": [], "as_of_seq": 3}
    assert calls(tmp_path) == [args]


def test_call_am_raises_the_refusal_unchanged(tmp_path):
    envelope = {"error": {"message": "store busy", "type": "StoreBusyError"}, "ok": False}
    am = fake_am(tmp_path, {"runs": json.dumps(envelope)}, code=3)
    with pytest.raises(am_runs.AmFailure) as excinfo:
        am_runs.call_am(am, ["runs", "--all-projects"], 5)
    assert excinfo.value.payload == envelope


@pytest.mark.parametrize("stdout, message", [
    ("not json", "am runs did not print JSON (exit 3)."),
    ("[]", "am runs printed JSON that is not an object."),
    ("{}", "am runs printed an object without an ok field."),
    ('{"ok": "yes"}', "am runs printed an object without an ok field."),
], ids=["non-json", "array", "no-ok", "ok-not-bool"])
def test_call_am_bad_output(tmp_path, stdout, message):
    am = fake_am(tmp_path, {"runs": stdout}, code=3)
    with pytest.raises(am_runs.AmFailure) as excinfo:
        am_runs.call_am(am, ["runs"], 5)
    assert excinfo.value.payload == {"ok": False, "error": {"type": "AmBadOutput", "message": message}}


def test_call_am_honours_timeout(tmp_path):
    am = write_exec(tmp_path / "am", "#!/usr/bin/env python3\nimport time\ntime.sleep(10)\n")
    start = time.monotonic()
    with pytest.raises(subprocess.TimeoutExpired):
        am_runs.call_am(am, ["runs"], 0.5)
    assert time.monotonic() - start < 5


# --- as_of_seq, store_id, data_dir ---------------------------------------------

@pytest.mark.parametrize("seq", [0, 7])
def test_as_of_seq_accepts_non_negative_ints(seq):
    assert am_runs.as_of_seq({"as_of_seq": seq}, "am runs") == seq


DROP = object()


@pytest.mark.parametrize("seq", [DROP, -1, True, 1.0, "1"],
                         ids=["missing", "negative", "bool", "float", "string"])
def test_as_of_seq_accepts_only_non_negative_ints(seq):
    data = {} if seq is DROP else {"as_of_seq": seq}
    with pytest.raises(am_runs.AmFailure) as excinfo:
        am_runs.as_of_seq(data, "am status r1")
    assert excinfo.value.payload == {"ok": False, "error": {
        "type": "SchemaMismatch", "message": "am status r1" + NEWER_AM}}


def test_store_id_and_data_dir(tmp_path, monkeypatch):
    assert am_runs.store_id({"store_id": "s1"}) == "s1"
    assert am_runs.store_id({"store_id": 7}) == ""
    assert am_runs.store_id({}) == ""
    monkeypatch.setenv("HOME", str(tmp_path))
    fallback = os.path.join(str(tmp_path), ".local", "share")
    monkeypatch.setenv("XDG_DATA_HOME", "relative/data")
    assert am_runs.data_dir() == fallback
    monkeypatch.setenv("XDG_DATA_HOME", "")
    assert am_runs.data_dir() == fallback
    monkeypatch.delenv("XDG_DATA_HOME")
    assert am_runs.data_dir() == fallback
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    assert am_runs.data_dir() == str(tmp_path / "data")


# --- TERMINAL, select_runs, run_list -------------------------------------------

def test_terminal_set_is_the_five_exact_statuses():
    assert am_runs.TERMINAL == {"done", "escalated", "stopped", "cancelled", "canceled"}
    assert isinstance(am_runs.TERMINAL, frozenset)
    assert am_runs.TERMINAL_LIMIT == 10
    assert am_runs.LIST_LIMIT == 200
    assert am_runs.AM_TIMEOUT == 60


@pytest.mark.parametrize("status, kept", [
    ("cancelled", 10), ("canceled", 10),
    ("Canceled", 12), (" canceled", 12), ("started", 12),
])
def test_select_runs_caps_terminal_under_either_cancel_spelling(status, kept):
    runs = [{"id": "t%d" % i, "status": status} for i in range(12)]
    runs.insert(3, {"id": "early", "status": "started"})
    runs.append({"id": "late", "status": "started"})
    before = copy.deepcopy(runs)
    picked = am_runs.select_runs(runs)
    expected = ["t0", "t1", "t2", "early"] + ["t%d" % i for i in range(3, kept)] + ["late"]
    assert [run["id"] for run in picked] == expected
    assert runs == before
    assert picked is not runs


def test_select_runs_of_nothing_is_nothing():
    assert am_runs.select_runs([]) == []


@pytest.mark.parametrize("data, message", [
    ({}, "am runs data has no runs list."),
    (None, "am runs data has no runs list."),
    ({"runs": {}}, "am runs data has no runs list."),
    ({"runs": [{"status": "done"}]}, "am runs listed a run without an id or status."),
    ({"runs": [{"id": "", "status": "done"}]}, "am runs listed a run without an id or status."),
    ({"runs": [{"id": "r1", "status": 3}]}, "am runs listed a run without an id or status."),
    ({"runs": ["r1"]}, "am runs listed a run without an id or status."),
], ids=["no-runs", "not-object", "runs-not-list", "no-id", "empty-id", "status-not-str", "row-not-object"])
def test_run_list_rejects_malformed_rows(data, message):
    with pytest.raises(am_runs.AmFailure) as excinfo:
        am_runs.run_list(data)
    assert error_of(excinfo) == {"type": "AmBadOutput", "message": message}


# --- run_status, list_snapshot, single_snapshot ---------------------------------

def test_run_status_rejects_non_object_data(tmp_path):
    am = fake_am(tmp_path, {"status-r1": ok([1, 2])})
    with pytest.raises(am_runs.AmFailure) as excinfo:
        am_runs.run_status(am, "r1", 5)
    assert error_of(excinfo) == {"type": "AmBadOutput", "message": "am status r1 data is not an object."}
    assert calls(tmp_path) == [["status", "r1"]]


def test_run_status_without_as_of_seq_is_schema_mismatch(tmp_path):
    am = fake_am(tmp_path, {"status-r1": ok({"run": {"id": "r1"}})})
    with pytest.raises(am_runs.AmFailure) as excinfo:
        am_runs.run_status(am, "r1", 5)
    assert error_of(excinfo) == {"type": "SchemaMismatch", "message": "am status r1" + NEWER_AM}


def test_list_snapshot_checks_the_list_before_any_status_call(tmp_path, capsys):
    am = fake_am(tmp_path, {"runs": ok({"runs": [{"id": "r1", "status": "started"}]}),
                            "status-r1": ok({"as_of_seq": 1})})
    with pytest.raises(am_runs.AmFailure) as excinfo:
        am_runs.list_snapshot(am, ["--all-projects"], 5)
    assert error_of(excinfo) == {"type": "SchemaMismatch", "message": "am runs" + NEWER_AM}
    assert calls(tmp_path) == [["runs", "--all-projects", "--limit", "200"]]
    assert capsys.readouterr().out == ""


def test_list_snapshot_passes_scope_and_limit(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    r1 = {"as_of_seq": 6, "store_id": "s1", "run": {"id": "r1", "status": "started"}}
    r2 = {"as_of_seq": 7, "store_id": "s1", "run": {"id": "r2", "status": "done"}}
    am = fake_am(tmp_path, {
        "runs": ok({"as_of_seq": 5, "store_id": "s1", "runs": [
            {"id": "r1", "status": "started", "repo_dir": "/r"},
            {"id": "r2", "status": "done", "repo_dir": "/r"}]}),
        "status-r1": ok(r1), "status-r2": ok(r2)})
    result = am_runs.list_snapshot(am, ["--repo-dir", "/r"], 5)
    assert calls(tmp_path) == [["runs", "--repo-dir", "/r", "--limit", "200"],
                               ["status", "r1"], ["status", "r2"]]
    assert list(result) == ["ok", "as_of_seq", "store_id", "runs", "data_dir"]
    assert result == {"ok": True, "as_of_seq": 5, "store_id": "s1", "runs": [
        {"id": "r1", "status": r1, "repo_dir": "/r"},
        {"id": "r2", "status": r2, "repo_dir": "/r"}], "data_dir": str(tmp_path / "data")}
    assert capsys.readouterr().out == ""


def test_list_snapshot_bounds_each_status_call_by_timeout(tmp_path):
    am = write_exec(tmp_path / "am", SLOW_STATUS_AM)
    start = time.monotonic()
    with pytest.raises(subprocess.TimeoutExpired):
        am_runs.list_snapshot(am, ["--all-projects"], 0.5)
    assert time.monotonic() - start < 5


def test_single_snapshot_shape_and_key_order(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    status = {"as_of_seq": 9, "store_id": 4, "run": {"id": "r1", "status": "canceled"}}
    am = fake_am(tmp_path, {"status-r1": ok(status)})
    result = am_runs.single_snapshot(am, "r1", 5)
    assert calls(tmp_path) == [["status", "r1"]]
    assert list(result) == ["ok", "run", "as_of_seq", "store_id", "status", "data_dir"]
    assert result == {"ok": True, "run": "r1", "as_of_seq": 9, "store_id": "",
                      "status": status, "data_dir": str(tmp_path / "data")}
