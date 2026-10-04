"""runs-snapshot.py: am runs + am status fan-out, one JSON line on every path.

Hermetic: a fake `am` lives on a temp PATH and serves hand-written fixtures from
FAKE_AM_DIR, appending each call's argv to calls.log; HOME and XDG_DATA_HOME are
temp. The real `am` and real data are never touched.
"""
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

UNKNOWN_RUN = {"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}
REPO_DIR_ERROR = {"error": {"message": "not a git repository", "type": "RepoDirError"}, "ok": False}
SUMMARY_FIELDS = {"id", "workflow", "repo_dir", "base_branch", "branch_prefix", "status", "started_at"}


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


def summary(run_id, status, started_at="2026-10-01T12:00:00Z"):
    return {"id": run_id, "workflow": "orchestrator", "repo_dir": "/repo",
            "base_branch": "master", "branch_prefix": "m2", "status": status,
            "started_at": started_at}


def status_data(run_id, status):
    """`am status` data as the monitor spec describes it: run, the
    story/subtask/phase/attempt tree, flat rows, control.lease, requests, claims."""
    return {
        "run": summary(run_id, status),
        "stories": [{"id": "s1", "title": "Story", "subtasks": [
            {"id": "c1", "title": "Card", "phases": [
                {"name": "implement", "status": "done",
                 "attempts": [{"n": 1, "status": "done"}]}]}]}],
        "rows": [{"card_id": "c1", "phase": "implement", "attempt": 1, "status": "done"}],
        "control": {"lease": {"pid": 4121, "host": "box",
                              "heartbeat_at": "2026-10-01T12:00:05Z",
                              "accepting": True, "live": status == "started"}},
        "requests": [],
        "claims": [{"card_id": "c1", "run_id": run_id}],
    }


def set_runs(world, runs):
    (world["am"] / "runs.out").write_text(json.dumps({"data": {"runs": runs}, "ok": True}) + "\n")


def set_status(world, run_id, status="started", data=None):
    payload = status_data(run_id, status) if data is None else data
    (world["am"] / ("status-" + run_id + ".out")).write_text(
        json.dumps({"data": payload, "ok": True}) + "\n")


def seed(world, runs):
    """`am runs` lists `runs`; `am status` answers for every one of them."""
    set_runs(world, runs)
    for r in runs:
        set_status(world, r["id"], r["status"])


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
