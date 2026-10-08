"""runs-snapshot.py: am runs + am status fan-out, one JSON line on every path.

Hermetic: a fake `am` lives on a temp PATH and serves, from FAKE_AM_DIR, the
committed captures in tests/fixtures/am/ (a payload no capture holds is labelled
`synthetic:`), appending each call's argv to calls.log; HOME and XDG_DATA_HOME
are temp. The real `am` and real data are never touched.
"""
import importlib.util
import json
import os
import stat
import subprocess
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "..")
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "runs-snapshot.py")

# The fake am logs its argv, then prints FAKE_AM_DIR/<name>.out verbatim and exits
# with FAKE_AM_DIR/<name>.code (default 0), where <name> is "runs" or
# "status-<run id>". A status fixture that does not exist behaves like real am for
# an unknown run: an UnknownRunError envelope and exit 3.
FAKE_AM = '''#!/usr/bin/env python3
import json, os, sys
d = os.environ["FAKE_AM_DIR"]
args = sys.argv[1:]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(args) + "\\n")
name = "runs" if args[:1] == ["runs"] else "status-" + (args[1] if len(args) > 1 else "")
out = os.path.join(d, name + ".out")
if not os.path.exists(out):
    sys.stdout.write(json.dumps({"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}) + "\\n")
    sys.exit(3)
with open(out) as f:
    sys.stdout.write(f.read())
code = os.path.join(d, name + ".code")
sys.exit(int(open(code).read()) if os.path.exists(code) else 0)
'''

FIXTURES = os.path.join(ROOT, "tests", "fixtures", "am")
# synthetic: am error envelopes; no capture holds one.
UNKNOWN_RUN = {"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}
REPO_DIR_ERROR = {"error": {"message": "not a git repository", "type": "RepoDirError"}, "ok": False}
STATUS_CAPTURES = {"started": "status-started.json", "done": "status-done.json",
                   "escalated": "status-escalated.json"}


def fixture(name):
    """A fresh json.load of tests/fixtures/am/<name>, so an edit never reaches
    another call."""
    with open(os.path.join(FIXTURES, name)) as f:
        return json.load(f)


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am, its fixture dir, a temp HOME/XDG_DATA_HOME, and a
    project root whose name would break if it ever went through a shell."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "am", FAKE_AM)
    amdir = tmp_path / "am"
    amdir.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    proj = tmp_path / "my proj; echo x"
    proj.mkdir()
    return {"tmp": tmp_path, "bin": bindir, "am": amdir, "home": home,
            "data": tmp_path / "data", "proj": proj}


def env_for(world, drop=(), **extra):
    e = {
        "PATH": str(world["bin"]) + os.pathsep + "/usr/bin" + os.pathsep + "/bin",
        "HOME": str(world["home"]),
        "XDG_DATA_HOME": str(world["data"]),
        "FAKE_AM_DIR": str(world["am"]),
    }
    e.update(extra)
    for key in drop:
        e.pop(key, None)
    return e


def run(world, args=None, drop=(), **extra):
    """Run the helper; assert stdout is exactly one JSON line; return (exit, payload)."""
    argv = [str(world["proj"])] if args is None else args
    p = subprocess.run([sys.executable, SCRIPT, *argv], capture_output=True, text=True,
                       env=env_for(world, drop, **extra), timeout=60)
    lines = p.stdout.splitlines()
    assert len(lines) == 1, (p.stdout, p.stderr)
    return p.returncode, json.loads(lines[0])


def runs_rows():
    """The captured `am runs` rows, newest first: a started run, then a done one."""
    return fixture("runs.json")["data"]["runs"]


def status_envelope(name):
    """A captured `am status` envelope without its top-level `_` keys."""
    return {k: v for k, v in fixture(name).items() if not k.startswith("_")}


def row_for(run_id, status):
    """synthetic: a test-local run id, and for a status other than started, done
    or escalated a value no capture has, set on a copy of a real `am runs` row
    (the started row, the escalated run's row, or else the done row)."""
    if status == "escalated":
        row = fixture("status-escalated.json")["_am_runs_row"]
    else:
        row = runs_rows()[0 if status == "started" else 1]
    row["id"] = run_id
    row["status"] = status
    return row


def status_for(run_id, status):
    """synthetic: the same edits as row_for, set on a copy of the matching
    captured `am status` data (status-done for a status no capture has)."""
    data = status_envelope(STATUS_CAPTURES.get(status, "status-done.json"))["data"]
    data["run"]["id"] = run_id
    data["run"]["status"] = status
    return data


def set_runs(world, runs):
    (world["am"] / "runs.out").write_text(json.dumps({"data": {"runs": runs}, "ok": True}) + "\n")


def set_status(world, run_id, data):
    (world["am"] / ("status-" + run_id + ".out")).write_text(
        json.dumps({"data": data, "ok": True}) + "\n")


def seed(world, runs):
    """`am runs` lists `runs`; `am status` answers for every one of them."""
    set_runs(world, runs)
    for r in runs:
        set_status(world, r["id"], status_for(r["id"], r["status"]))


def set_raw(world, name, text, code=0):
    (world["am"] / (name + ".out")).write_text(text)
    (world["am"] / (name + ".code")).write_text(str(code))


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def expected(run, data):
    out = dict(run)
    out["status"] = data
    return out


# --- empty state, usage, am missing, data_dir, catch-all --------------------

def test_no_runs_is_empty_state(world):
    # synthetic: am runs of a project with no runs.
    set_runs(world, [])
    code, out = run(world)
    assert code == 0
    assert out == {"ok": True, "runs": [], "data_dir": str(world["data"])}
    assert calls(world) == [["runs", "--repo-dir", str(world["proj"])]]


@pytest.mark.parametrize("args", [[], ["a", "b"]])
def test_usage(world, args):
    code, out = run(world, args)
    assert code == 2
    assert out["ok"] is False
    assert out["error"]["type"] == "Usage"
    assert "runs-snapshot.py <project_root>" in out["error"]["message"]
    assert calls(world) == []


def test_am_missing(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, out = run(world, PATH=str(empty))
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "AmMissing"
    assert out["error"]["message"]


@pytest.mark.parametrize("case", ["absolute", "unset", "relative", "empty"])
def test_data_dir(world, case):
    # synthetic: am runs of a project with no runs.
    set_runs(world, [])
    fallback = str(world["home"] / ".local" / "share")
    if case == "absolute":
        code, out = run(world)
        want = str(world["data"])
    elif case == "unset":
        code, out = run(world, drop=("XDG_DATA_HOME",))
        want = fallback
    elif case == "relative":
        code, out = run(world, XDG_DATA_HOME="rel/data")
        want = fallback
    else:
        code, out = run(world, XDG_DATA_HOME="")
        want = fallback
    assert code == 0
    assert out["data_dir"] == want


def test_unexpected_failure_is_helper_error(world):
    # An am that cannot be executed at all: subprocess raises, guarded() must
    # still print exactly one JSON line.
    write_exec(world["bin"] / "am", "#!/nonexistent/interpreter\n")
    code, out = run(world)
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"]


def load_helper():
    """The script as a module (its name has a hyphen, so no plain import)."""
    spec = importlib.util.spec_from_file_location("runs_snapshot", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_am_timeout_is_helper_error(world, monkeypatch, capsys):
    # An am that hangs is cut off after AM_TIMEOUT and reported as HelperError
    # (shortened here so the test does not wait the real 60 s).
    write_exec(world["bin"] / "am", "#!/usr/bin/env python3\nimport time\ntime.sleep(10)\n")
    helper = load_helper()
    monkeypatch.setattr(helper, "AM_TIMEOUT", 0.5)
    for key, value in env_for(world).items():
        monkeypatch.setenv(key, value)
    code = helper.guarded([str(world["proj"])])
    lines = capsys.readouterr().out.splitlines()
    assert code == 1
    assert len(lines) == 1, lines
    out = json.loads(lines[0])
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"


def test_am_does_not_inherit_stdin(world):
    # The helper's stdin is an open pipe that never sends EOF. An am that reads
    # stdin must get EOF at once (stdin is /dev/null), not block on that pipe.
    # synthetic: am runs of a project with no runs.
    write_exec(world["bin"] / "am",
               "#!/usr/bin/env python3\nimport json, sys\nsys.stdin.read()\n"
               "print(json.dumps({'ok': True, 'data': {'runs': []}}))\n")
    p = subprocess.Popen([sys.executable, SCRIPT, str(world["proj"])], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                         env=env_for(world))
    try:
        code = p.wait(timeout=15)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait()
        pytest.fail("am blocked reading the helper's stdin")
    finally:
        p.stdin.close()
    lines = p.stdout.read().splitlines()
    p.stdout.close()
    p.stderr.close()
    assert code == 0
    assert lines == [json.dumps({"ok": True, "runs": [], "data_dir": str(world["data"])})]


# --- shape and fan-out -------------------------------------------------------

def test_fake_am_serves_the_captures(world):
    runs = runs_rows()
    seed(world, runs)
    # set_runs serves the captured rows; the capture's data-level as_of_seq and
    # store_id and its `_note` are not part of what it serves.
    assert json.loads((world["am"] / "runs.out").read_text()) == \
        {"data": {"runs": fixture("runs.json")["data"]["runs"]}, "ok": True}
    for row, name in zip(runs, ["status-started.json", "status-done.json"]):
        served = json.loads((world["am"] / ("status-" + row["id"] + ".out")).read_text())
        assert served == status_envelope(name)
    # status-escalated.json carries top-level `_` keys; the served envelope does not.
    assert any(k.startswith("_") for k in fixture("status-escalated.json"))
    assert set(status_envelope("status-escalated.json")) == {"data", "ok"}
    set_status(world, "e1", status_for("e1", "escalated"))
    served = json.loads((world["am"] / "status-e1.out").read_text())
    assert not any(k.startswith("_") for k in served)
    want = status_envelope("status-escalated.json")
    want["data"]["run"]["id"] = "e1"
    assert served == want
    # Every row_for row, capture status or not, has a real am runs row's 13 keys.
    keys = set(runs[0])
    assert len(keys) == 13
    for status in ["started", "done", "escalated", "cancelled", "canceled", "something-new"]:
        row = row_for("e1", status)
        assert set(row) == keys
        assert (row["id"], row["status"]) == ("e1", status)


def test_snapshot_shape(world):
    runs = runs_rows()
    seed(world, runs)
    code, out = run(world)  # run() asserts stdout is exactly one JSON line
    assert code == 0
    assert out == {
        "ok": True,
        "runs": [expected(runs[0], status_envelope("status-started.json")["data"]),
                 expected(runs[1], status_envelope("status-done.json")["data"])],
        "data_dir": str(world["data"]),
    }
    for entry, row in zip(out["runs"], runs):
        assert set(entry) == set(row)
        assert isinstance(entry["status"], dict)


def test_status_fanout_selection(world):
    # Newest first: non-terminal runs interleaved with 12 terminal ones, and one
    # non-terminal run older than every terminal one.
    runs = ([row_for("n1", "started")]
            + [row_for("t%d" % i, "done") for i in range(1, 6)]
            + [row_for("n2", "started")]
            + [row_for("t%d" % i, ["escalated", "cancelled", "canceled", "stopped"][i % 4])
               for i in range(6, 13)]
            + [row_for("n3", "started")])
    seed(world, runs)
    code, out = run(world)
    want = ["n1", "t1", "t2", "t3", "t4", "t5", "n2",
            "t6", "t7", "t8", "t9", "t10", "n3"]
    assert code == 0
    assert [r["id"] for r in out["runs"]] == want
    root = str(world["proj"])
    assert calls(world) == ([["runs", "--repo-dir", root]]
                            + [["status", i, "--repo-dir", root] for i in want])


# synthetic: stopped, cancelled, canceled, Canceled, CANCELED, " canceled",
# "canceled ", cancel, paused and something-new are run statuses no capture has.
@pytest.mark.parametrize("status,kept", [
    ("done", 10), ("escalated", 10), ("stopped", 10), ("cancelled", 10),
    ("canceled", 10),
    ("started", 12), ("paused", 12), ("something-new", 12),
    ("Canceled", 12), ("CANCELED", 12), (" canceled", 12), ("canceled ", 12),
    ("cancel", 12),
])
def test_terminal_set_pinned(world, status, kept):
    # `stopped` is "parked" in the domain table but terminal here: it counts
    # toward the cap of 10. Any status outside the five is non-terminal.
    runs = [row_for("x%02d" % i, status) for i in range(12)]
    seed(world, runs)
    code, out = run(world)
    assert code == 0
    assert [r["id"] for r in out["runs"]] == ["x%02d" % i for i in range(kept)]


def test_canceled_spelling_reported_verbatim(world):
    # Both spellings pass through as am printed them: no rewriting either way.
    runs = [row_for("c1", "canceled"), row_for("c2", "cancelled")]
    seed(world, runs)
    code, out = run(world)
    assert code == 0
    assert out["runs"] == [expected(runs[0], status_for("c1", "canceled")),
                           expected(runs[1], status_for("c2", "cancelled"))]
    assert [r["status"]["run"]["status"] for r in out["runs"]] == ["canceled", "cancelled"]


def test_repo_dir_passed(world):
    # The project dir is named "my proj; echo x": it must arrive as one argv element.
    seed(world, runs_rows())
    code, _ = run(world)
    assert code == 0
    made = calls(world)
    assert len(made) == 3
    for argv in made:
        assert argv[-2:] == ["--repo-dir", str(world["proj"])]


# --- am errors and bad output --------------------------------------------------

@pytest.mark.parametrize("envelope,exit_code", [(UNKNOWN_RUN, 3), (REPO_DIR_ERROR, 0)])
def test_am_error_envelope_passthrough_runs(world, envelope, exit_code):
    # The envelope's `ok` decides, not am's exit code: real `am runs` exits 0 with
    # ok:false for a RepoDirError.
    set_raw(world, "runs", json.dumps(envelope) + "\n", exit_code)
    code, out = run(world)
    assert code == 1
    assert out == envelope
    assert "data_dir" not in out
    assert calls(world) == [["runs", "--repo-dir", str(world["proj"])]]


def test_am_error_envelope_passthrough_status(world):
    # The second run has no status fixture, so the fake am answers UnknownRunError,
    # exit 3. The whole snapshot fails; no partial result is printed.
    runs = runs_rows()
    set_runs(world, runs)
    set_status(world, runs[0]["id"], status_for(runs[0]["id"], runs[0]["status"]))
    code, out = run(world)
    assert code == 1
    assert out == UNKNOWN_RUN
    assert "data_dir" not in out
    assert calls(world)[-1] == ["status", runs[1]["id"], "--repo-dir", str(world["proj"])]


# synthetic: garbage and malformed `am runs` / `am status` output.
@pytest.mark.parametrize("target,text,exit_code", [
    ("runs", "not json\n", 0),
    ("runs", "[1, 2]\n", 0),
    ("runs", "", 5),
    ("runs", '{"data": {"runs": []}}\n', 0),
    ("runs", '{"ok": true, "data": {"runs": "x"}}\n', 0),
    ("runs", '{"ok": true, "data": []}\n', 0),
    ("runs", '{"ok": true, "data": {"runs": [{"workflow": "m", "status": "done"}]}}\n', 0),
    ("runs", '{"ok": true, "data": {"runs": [{"id": "r1"}]}}\n', 0),
    ("runs", '{"ok": true, "data": {"runs": ["r1"]}}\n', 0),
    ("runs", '{"ok": true, "data": {"runs": [{"id": "", "status": "done"}]}}\n', 0),
    ("runs", '{"ok": true, "data": {"runs": [{"id": 7, "status": "done"}]}}\n', 0),
    ("runs", '{"ok": true, "data": {"runs": [{"id": "r1", "status": null}]}}\n', 0),
    ("status", '{"ok": true, "data": [1]}\n', 0),
    ("status", "Traceback (most recent call last):\n  boom\n", 1),
], ids=["not-json", "not-object", "crash-empty", "no-ok", "runs-not-list",
        "data-not-object", "run-without-id", "run-without-status", "run-not-object",
        "run-empty-id", "run-id-not-string", "run-status-not-string",
        "status-data-not-object", "status-traceback"])
def test_am_bad_output(world, target, text, exit_code):
    if target == "runs":
        set_raw(world, "runs", text, exit_code)
    else:
        runs = runs_rows()
        set_runs(world, runs)
        set_raw(world, "status-" + runs[0]["id"], text, exit_code)
    code, out = run(world)  # run() asserts exactly one JSON line
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "AmBadOutput"
    assert out["error"]["message"]
