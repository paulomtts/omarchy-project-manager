"""runs-snapshot-all.py: one per-project snapshot per root, one JSON line on every path.

Hermetic: a fake `am` lives on a temp PATH and serves, from FAKE_AM_DIR, the
committed captures in tests/fixtures/am/ (a payload no capture holds is labelled
`synthetic:`), appending each call's argv to calls.log and its start/end times to
spans.log; HOME and XDG_DATA_HOME are temp. The real `am` and real data are never
touched.
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
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "runs-snapshot-all.py")

# The fake am logs its argv to calls.log and "start <t>" / "end <t>" (one shared
# monotonic clock) to spans.log, each line in one append-mode write. Its reply is
# keyed by <name>: "runs-<basename of the --repo-dir value>" for `am runs`, and
# "status-<run id>" for `am status`. It sleeps FAKE_AM_DIR/<name>.sleep seconds
# (default 0), prints FAKE_AM_DIR/<name>.out verbatim and exits with
# FAKE_AM_DIR/<name>.code (default 0). A reply that does not exist behaves like
# real am for an unknown run: an UnknownRunError envelope and exit 3.
FAKE_AM = '''#!/usr/bin/env python3
import json, os, sys, time
d = os.environ["FAKE_AM_DIR"]
args = sys.argv[1:]


def log(name, line):
    with open(os.path.join(d, name), "a") as f:
        f.write(line)


log("calls.log", json.dumps(args) + "\\n")
log("spans.log", "start %r\\n" % time.monotonic())
if args[:1] == ["runs"] and "--repo-dir" in args:
    name = "runs-" + os.path.basename(os.path.normpath(args[args.index("--repo-dir") + 1]))
else:
    name = "status-" + (args[1] if len(args) > 1 else "")
sleep = os.path.join(d, name + ".sleep")
if os.path.exists(sleep):
    time.sleep(float(open(sleep).read()))
out = os.path.join(d, name + ".out")
if os.path.exists(out):
    text = open(out).read()
    code_file = os.path.join(d, name + ".code")
    code = int(open(code_file).read()) if os.path.exists(code_file) else 0
else:
    text = json.dumps({"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}) + "\\n"
    code = 3
log("spans.log", "end %r\\n" % time.monotonic())
sys.stdout.write(text)
sys.exit(code)
'''

FIXTURES = os.path.join(ROOT, "tests", "fixtures", "am")
# synthetic: am error envelope; no capture holds one.
REPO_DIR_ERROR = {"error": {"message": "not a git repository", "type": "RepoDirError"}, "ok": False}
STATUS_CAPTURES = {"started": "status-started.json", "done": "status-done.json",
                   "escalated": "status-escalated.json"}
USAGE = "usage: runs-snapshot-all.py <root> [<root> ...]"
A = object()  # stands for project A's path in parametrized argv


def FILTER(root):
    """The `am runs` argv for one project root."""
    return ["runs", "--repo-dir", root, "--limit", "200"]


def STATUS(run_id):
    """The `am status` argv for one run: never a --repo-dir."""
    return ["status", run_id]


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
    """A temp PATH with a fake am, its reply dir, and a temp HOME/XDG_DATA_HOME."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "am", FAKE_AM)
    amdir = tmp_path / "am"
    amdir.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    return {"tmp": tmp_path, "bin": bindir, "am": amdir, "home": home,
            "data": tmp_path / "data"}


def project(world, name):
    """A project root directory named `name` (its basename keys the fake's reply)."""
    path = world["tmp"] / "projects" / name
    path.mkdir(parents=True)
    return str(path)


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


def empty_path(world):
    """A PATH holding no am."""
    empty = world["tmp"] / "empty-bin"
    empty.mkdir(exist_ok=True)
    return str(empty)


def run(world, args, drop=(), **extra):
    """Run the helper; assert stdout is exactly one JSON line; return (exit, payload)."""
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True,
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
    """synthetic: a test-local run id set on a copy of a real `am runs` row (the
    started row, or else the done row)."""
    row = runs_rows()[0 if status == "started" else 1]
    row["id"] = run_id
    return row


def status_for(run_id, status):
    """synthetic: the same run id set on a copy of the matching captured
    `am status` data."""
    data = status_envelope(STATUS_CAPTURES[status])["data"]
    data["run"]["id"] = run_id
    return data


def set_runs(world, root, runs):
    """`am runs --repo-dir root` serves the captured envelope without `_note`, its
    runs replaced by `runs` (synthetic: whenever runs is not the captured list)."""
    envelope = {k: v for k, v in fixture("runs.json").items() if not k.startswith("_")}
    envelope["data"]["runs"] = runs
    name = "runs-" + os.path.basename(os.path.normpath(root))
    (world["am"] / (name + ".out")).write_text(json.dumps(envelope) + "\n")


def set_status(world, run_id, data):
    (world["am"] / ("status-" + run_id + ".out")).write_text(
        json.dumps({"data": data, "ok": True}) + "\n")


def seed(world, root, run_id):
    """`am runs --repo-dir root` lists one started run `run_id` (synthetic: the
    captured started row and status data with a test-local id); returns the
    entry runs the helper must report for it."""
    row = row_for(run_id, "started")
    set_runs(world, root, [row])
    set_status(world, run_id, status_for(run_id, "started"))
    return [expected(row, status_for(run_id, "started"))]


def set_raw(world, name, text, code=0):
    (world["am"] / (name + ".out")).write_text(text)
    (world["am"] / (name + ".code")).write_text(str(code))


def set_sleep(world, name, seconds):
    (world["am"] / (name + ".sleep")).write_text(str(seconds))


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def expected(run, data):
    out = dict(run)
    out["status"] = data
    return out


def ok_entry(root, runs):
    return {"root": root, "ok": True, "runs": runs}


def load_helper():
    """The script as a module (its name has a hyphen, so no plain import)."""
    spec = importlib.util.spec_from_file_location("runs_snapshot_all", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def in_process(world, monkeypatch):
    """The helper module, with this world's environment set on the test process."""
    helper = load_helper()
    for key, value in env_for(world).items():
        monkeypatch.setenv(key, value)
    return helper


# --- success shape ----------------------------------------------------------------

def test_success_shape_and_argv(world):
    a, b = project(world, "proj-a"), project(world, "proj-b")
    a_rows = [row_for("a1", "started"), row_for("a2", "done")]
    b_rows = [row_for("b1", "started"), row_for("b2", "done")]
    set_runs(world, a, a_rows)
    set_runs(world, b, b_rows)
    for r, kind in [(a_rows[0], "started"), (a_rows[1], "done"),
                    (b_rows[0], "started"), (b_rows[1], "done")]:
        set_status(world, r["id"], status_for(r["id"], kind))
    code, out = run(world, [a, b])
    assert code == 0
    assert out == {"ok": True, "projects": [
        ok_entry(a, [expected(a_rows[0], status_for("a1", "started")),
                     expected(a_rows[1], status_for("a2", "done"))]),
        ok_entry(b, [expected(b_rows[0], status_for("b1", "started")),
                     expected(b_rows[1], status_for("b2", "done"))]),
    ], "data_dir": str(world["data"])}
    assert list(out) == ["ok", "projects", "data_dir"]
    assert [list(p) for p in out["projects"]] == [["root", "ok", "runs"]] * 2
    assert sorted(calls(world)) == sorted([FILTER(a), FILTER(b), STATUS("a1"), STATUS("a2"),
                                           STATUS("b1"), STATUS("b2")])
    assert not any("--repo-dir" in c for c in calls(world) if c[0] == "status")


def test_empty_project(world):
    a = project(world, "proj-a")
    # synthetic: the captured am runs data with an empty run list.
    set_runs(world, a, [])
    code, out = run(world, [a])
    assert code == 0
    assert out["projects"] == [{"root": a, "ok": True, "runs": []}]
    assert calls(world) == [FILTER(a)]


# --- per-root failures ------------------------------------------------------------

@pytest.mark.parametrize("case", ["refused", "bad-output", "schema"])
def test_partial_failure(world, case):
    a, b = project(world, "proj-a"), project(world, "proj-b")
    b_row = row_for("b1", "started")
    set_runs(world, b, [b_row])
    set_status(world, "b1", status_for("b1", "started"))
    if case == "refused":
        set_raw(world, "runs-proj-a", json.dumps(REPO_DIR_ERROR) + "\n", 2)
        want = REPO_DIR_ERROR["error"]
    elif case == "bad-output":
        set_raw(world, "runs-proj-a", "not json\n", 0)
        want = {"type": "AmBadOutput", "message": "am runs did not print JSON (exit 0)."}
    else:
        set_runs(world, a, [row_for("a1", "started")])
        # synthetic: the captured status data without its as_of_seq.
        data = status_for("a1", "started")
        data.pop("as_of_seq")
        set_status(world, "a1", data)
        want = {"type": "SchemaMismatch",
                "message": "am status a1 sent no non-negative integer as_of_seq; "
                           "the plugin needs the newer am."}
    code, out = run(world, [a, b])
    assert code == 0
    assert out["ok"] is True
    assert out["projects"][0] == {"root": a, "ok": False, "error": want}
    assert list(out["projects"][0]) == ["root", "ok", "error"]
    assert out["projects"][1] == ok_entry(b, [expected(b_row, status_for("b1", "started"))])


def test_refusal_without_error_key(world):
    a, b = project(world, "proj-a"), project(world, "proj-b")
    # synthetic: an ok:false envelope with no error key.
    set_raw(world, "runs-proj-a", json.dumps({"ok": False}) + "\n", 1)
    set_runs(world, b, [])
    code, out = run(world, [a, b])
    assert code == 0
    assert out["projects"] == [{"root": a, "ok": False, "error": None}, ok_entry(b, [])]


@pytest.mark.parametrize("case", ["deleted", "file", "never-existed", "dangling-symlink"])
def test_vanished_root(world, case):
    b = project(world, "proj-b")
    set_runs(world, b, [])
    gone = world["tmp"] / "gone"
    if case == "deleted":
        gone.mkdir()
        gone.rmdir()
    elif case == "file":
        gone.write_text("not a directory\n")
    elif case == "dangling-symlink":
        gone.symlink_to(world["tmp"] / "nowhere")
    r = str(gone)
    code, out = run(world, [r, b])
    assert code == 0
    assert out["projects"] == [
        {"root": r, "ok": False, "error": {"type": "RootMissing", "message": r + " is not a directory."}},
        ok_entry(b, []),
    ]
    assert not any(r in c for c in calls(world))


def test_unexpected_failure_is_per_root_helper_error(world):
    # An am that cannot be executed at all: subprocess raises OSError for each root.
    a, b = project(world, "proj-a"), project(world, "proj-b")
    write_exec(world["bin"] / "am", "#!/nonexistent/interpreter\n")
    code, out = run(world, [a, b])
    assert code == 0
    assert out["ok"] is True
    assert [p["root"] for p in out["projects"]] == [a, b]
    for p in out["projects"]:
        assert p["ok"] is False
        assert "runs" not in p
        assert p["error"]["type"] == "HelperError"
        assert p["error"]["message"].startswith("The runs snapshot failed: ")


# --- roots as given ---------------------------------------------------------------

def test_repeated_root(world):
    a = project(world, "proj-a")
    row = row_for("a1", "started")
    set_runs(world, a, [row])
    set_status(world, "a1", status_for("a1", "started"))
    code, out = run(world, [a, a])
    assert code == 0
    entry = ok_entry(a, [expected(row, status_for("a1", "started"))])
    assert out["projects"] == [entry, entry]
    assert calls(world).count(FILTER(a)) == 2
    assert calls(world).count(STATUS("a1")) == 2


def test_root_is_one_argv_element(world):
    proj = project(world, "my proj; echo x")
    # synthetic: the captured am runs data with an empty run list.
    set_runs(world, proj, [])
    code, out = run(world, [proj])
    assert code == 0
    assert out["projects"] == [ok_entry(proj, [])]
    assert calls(world) == [FILTER(proj)]


def test_root_used_as_given(world):
    a = project(world, "proj-a") + "/"
    set_runs(world, a, [])
    code, out = run(world, [a])
    assert code == 0
    assert out["projects"] == [ok_entry(a, [])]
    assert calls(world) == [FILTER(a)]


def test_root_with_newline_stays_one_line(world):
    a = project(world, "line\nbreak")
    set_runs(world, a, [])
    code, out = run(world, [a])  # run() asserts exactly one stdout line
    assert code == 0
    assert out["projects"] == [ok_entry(a, [])]


# --- usage, am missing, data_dir ---------------------------------------------------

@pytest.mark.parametrize("args", [
    [], [""], ["-x"], ["--all-projects"], ["--run", "R"], [A, "-x"], [A, ""],
], ids=["none", "empty", "dash-x", "all-projects", "run", "root-then-dash", "root-then-empty"])
def test_usage(world, args):
    a = project(world, "proj-a")
    set_runs(world, a, [])
    code, out = run(world, [a if x is A else x for x in args])
    assert code == 2
    assert out == {"ok": False, "error": {"type": "Usage", "message": USAGE}}
    assert calls(world) == []


def test_usage_before_am_lookup(world):
    code, out = run(world, [], PATH=empty_path(world))
    assert code == 2
    assert out == {"ok": False, "error": {"type": "Usage", "message": USAGE}}


def test_am_missing_in_every_entry(world):
    a = project(world, "proj-a")
    missing = str(world["tmp"] / "never")
    code, out = run(world, [a, missing], PATH=empty_path(world))
    am_missing = {"type": "AmMissing", "message": "am is not installed."}
    assert code == 0
    assert out == {"ok": True, "projects": [
        {"root": a, "ok": False, "error": am_missing},
        {"root": missing, "ok": False, "error": am_missing},
    ], "data_dir": str(world["data"])}


@pytest.mark.parametrize("case", ["absolute", "unset", "relative", "empty"])
def test_data_dir(world, case):
    a = project(world, "proj-a")
    # synthetic: the captured am runs data with an empty run list.
    set_runs(world, a, [])
    fallback = str(world["home"] / ".local" / "share")
    if case == "absolute":
        code, out = run(world, [a])
        want = str(world["data"])
    elif case == "unset":
        code, out = run(world, [a], drop=("XDG_DATA_HOME",))
        want = fallback
    elif case == "relative":
        code, out = run(world, [a], XDG_DATA_HOME="rel/data")
        want = fallback
    else:
        code, out = run(world, [a], XDG_DATA_HOME="")
        want = fallback
    assert code == 0
    assert out["data_dir"] == want


# --- catch-all and stdin ------------------------------------------------------------

def test_top_level_catch_all(world, monkeypatch, capsys):
    a = project(world, "proj-a")
    set_runs(world, a, [])
    helper = in_process(world, monkeypatch)

    def boom():
        raise RuntimeError("boom")

    monkeypatch.setattr(helper, "data_dir", boom)
    code = helper.guarded([a])
    lines = capsys.readouterr().out.splitlines()
    assert code == 1
    assert [json.loads(line) for line in lines] == [
        {"ok": False, "error": {"type": "HelperError", "message": "The runs snapshot failed: boom"}}]


def test_am_does_not_inherit_stdin(world):
    # The helper's stdin is an open pipe that never sends EOF. An am that reads
    # stdin must get EOF at once (stdin is /dev/null), not block on that pipe.
    a = project(world, "proj-a")
    runs_data = fixture("runs.json")["data"]
    # synthetic: the captured am runs data with an empty run list.
    write_exec(world["bin"] / "am",
               "#!/usr/bin/env python3\nimport json, sys\nsys.stdin.read()\n"
               "print(json.dumps({'ok': True, 'data': {'as_of_seq': %d, 'runs': [], "
               "'store_id': %r}}))\n" % (runs_data["as_of_seq"], runs_data["store_id"]))
    p = subprocess.Popen([sys.executable, SCRIPT, a], stdin=subprocess.PIPE,
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
    assert [json.loads(line) for line in lines] == [
        {"ok": True, "projects": [ok_entry(a, [])], "data_dir": str(world["data"])}]
