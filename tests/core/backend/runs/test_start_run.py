"""start-run.py: `am run` detached, the run id it started found through `am runs`,
one JSON line on every path.

Hermetic: a fake `am` lives on a temp PATH and is driven by fixture files in
FAKE_AM_DIR, appending each call's argv to calls.log; HOME, XDG_DATA_HOME and
XDG_STATE_HOME are temp. The real `am` and real data are never touched, and no
fake outlives its test (the world fixture SIGKILLs a still-running fake's group).
"""
import datetime
import importlib.util
import json
import os
import re
import select
import signal
import stat
import subprocess
import sys
import time

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "..")
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "start-run.py")

# The fake am logs its argv to calls.log, then:
# - `run`: writes run.pid, run.sid (its session id), run.cwd and run.stdin (what
#   fd 0 points at); copies run.out to stdout and run.err to stderr (flushed at
#   once, so they are in the log while it sleeps); if run.rows exists, writes it
#   to runs.json with every "NOW" replaced by its own UTC time to the second (so
#   the run "appears" after the spawn); sleeps run.sleep seconds (default 0);
#   writes run.done; exits run.code (default 0).
# - `runs`: counts its calls in runs.count; while the count is <= runs.fail
#   (default 0) it fails like a locked database (stderr, exit 1, no envelope);
#   else prints runs.out verbatim if present, otherwise
#   {"ok": true, "data": {"runs": <runs.json or []>}}, and exits runs.code.
# Every fixture file it writes is replaced atomically, so a reader never sees half.
FAKE_AM = '''#!/usr/bin/env python3
import datetime, json, os, sys, time
d = os.environ["FAKE_AM_DIR"]
args = sys.argv[1:]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(args) + "\\n")


def path(name):
    return os.path.join(d, name)


def read(name, default=None):
    if not os.path.exists(path(name)):
        return default
    with open(path(name)) as f:
        return f.read()


def write(name, text):
    with open(path(name + ".tmp"), "w") as f:
        f.write(text)
    os.replace(path(name + ".tmp"), path(name))


if args[:1] == ["run"]:
    write("run.pid", str(os.getpid()))
    write("run.sid", str(os.getsid(0)))
    write("run.cwd", os.getcwd())
    write("run.stdin", os.readlink("/proc/self/fd/0"))
    if os.path.exists(path("run.out")):
        with open(path("run.out"), "rb") as f:
            sys.stdout.buffer.write(f.read())
    if os.path.exists(path("run.err")):
        with open(path("run.err"), "rb") as f:
            sys.stderr.buffer.write(f.read())
    sys.stdout.flush()
    sys.stderr.flush()
    rows = read("run.rows")
    if rows is not None:
        now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        write("runs.json", rows.replace("NOW", now))
    time.sleep(float(read("run.sleep", "0")))
    write("run.done", "")
    sys.exit(int(read("run.code", "0")))
if args[:1] == ["runs"]:
    count = int(read("runs.count", "0")) + 1
    write("runs.count", str(count))
    if count <= int(read("runs.fail", "0")):
        sys.stderr.write("am runs: database is locked\\n")
        sys.exit(1)
    out = read("runs.out")
    if out is None:
        out = json.dumps({"ok": True, "data": {"runs": json.loads(read("runs.json", "[]"))}}) + "\\n"
    sys.stdout.write(out)
    sys.exit(int(read("runs.code", "0")))
sys.exit(2)
'''

USAGE_LINE = {"ok": False, "error": {"type": "Usage", "message":
              "usage: start-run.py ROOT (milestone ID | card ID | board) [--base-branch B]"
              " [--branch-prefix P] [--max-concurrent N] [--verify CMD]..."
              " [--allow-no-verification]"}}
CLAIMED = {"ok": False, "error": {"type": "ClaimedError",
                                  "message": "card c1 is claimed by run r9"}}
STARTED_AT_RE = r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$"


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am, its fixture dir, temp HOME/XDG dirs and a project dir."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "am", FAKE_AM)
    amdir = tmp_path / "am"
    amdir.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    project = tmp_path / "proj"
    project.mkdir()
    yield {"tmp": tmp_path, "bin": bindir, "am": amdir, "home": home,
           "data": tmp_path / "data", "state": tmp_path / "state", "project": project}
    pid_file = amdir / "run.pid"
    if pid_file.exists() and not (amdir / "run.done").exists():
        try:
            # The fake is a session leader, so its pid is its process group id.
            os.killpg(int(pid_file.read_text()), signal.SIGKILL)
        except (ProcessLookupError, PermissionError, ValueError):
            pass


def env_for(world, **extra):
    e = {
        "PATH": str(world["bin"]) + os.pathsep + "/usr/bin" + os.pathsep + "/bin",
        "HOME": str(world["home"]),
        "XDG_DATA_HOME": str(world["data"]),
        "XDG_STATE_HOME": str(world["state"]),
        "FAKE_AM_DIR": str(world["am"]),
    }
    e.update(extra)
    return e


def run(world, args, **extra):
    """Run the helper; assert stdout is exactly one JSON line; return (exit, payload)."""
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True,
                       env=env_for(world, **extra), timeout=60)
    lines = p.stdout.splitlines()
    assert len(lines) == 1, (p.stdout, p.stderr)
    return p.returncode, json.loads(lines[0])


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def run_calls(world):
    return [c for c in calls(world) if c[:1] == ["run"]]


def load_helper():
    """The script as a module (its name has a hyphen, so no plain import)."""
    spec = importlib.util.spec_from_file_location("start_run", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def use_world(world, monkeypatch):
    for key, value in env_for(world).items():
        monkeypatch.setenv(key, value)


def fast_helper(monkeypatch, world, window=5, interval=0.05):
    """The module, in the world's environment, with a short poll window and interval."""
    helper = load_helper()
    monkeypatch.setattr(helper, "POLL_WINDOW", window)
    monkeypatch.setattr(helper, "POLL_INTERVAL", interval)
    use_world(world, monkeypatch)
    return helper


def one_line(capsys):
    lines = capsys.readouterr().out.splitlines()
    assert len(lines) == 1, lines
    return json.loads(lines[0])


def wait_for(path, timeout=10):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if path.exists():
            return True
        time.sleep(0.05)
    return path.exists()


def read_pid(world):
    assert wait_for(world["am"] / "run.pid")
    return int((world["am"] / "run.pid").read_text())


# --- am argv -----------------------------------------------------------------

def test_milestone_argv(world):
    root = str(world["project"])
    code, _ = run(world, [root, "milestone", "m1", "--branch-prefix", "m3"])
    assert code == 0
    made = run_calls(world)
    assert made == [["run", "--milestone", "m1", "--repo-dir", root, "--branch-prefix", "m3"]]
    for never in ("--dry-run", "--detach", "--pretty"):
        assert never not in made[0]


def test_card_argv(world):
    root = str(world["project"])
    code, _ = run(world, [root, "card", "c9", "--branch-prefix", "m3"])
    assert code == 0
    assert run_calls(world) == [["run", "--card", "c9", "--repo-dir", root, "--branch-prefix", "m3"]]


def test_board_argv(world):
    root = str(world["project"])
    code, _ = run(world, [root, "board"])
    assert code == 0
    made = run_calls(world)
    assert made == [["run", "--board", "--repo-dir", root]]
    assert "--milestone" not in made[0]


def test_options_forwarded_in_fixed_order(world):
    root = str(world["project"])
    code, _ = run(world, [root, "milestone", "m1",
                          "--verify", "uv run pytest", "--max-concurrent", "2",
                          "--branch-prefix", "m3", "--base-branch", "main",
                          "--verify", "-x", "--allow-no-verification"])
    assert code == 0
    assert run_calls(world) == [["run", "--milestone", "m1", "--repo-dir", root,
                                 "--base-branch", "main", "--branch-prefix", "m3",
                                 "--max-concurrent", "2",
                                 "--verify", "uv run pytest", "--verify", "-x",
                                 "--allow-no-verification"]]


def test_verify_values_verbatim(world):
    # Spaces, shell metacharacters, a leading dash and an empty string each arrive
    # as one unaltered argv element: no shell, no validation by the helper.
    root = str(world["project"])
    values = ["uv run pytest -q", "make test; echo done", "echo $HOME", "-x", ""]
    args = [root, "board"]
    for v in values:
        args += ["--verify", v]
    code, _ = run(world, args)
    assert code == 0
    expected = ["run", "--board", "--repo-dir", root]
    for v in values:
        expected += ["--verify", v]
    assert run_calls(world) == [expected]


# --- detached spawn -------------------------------------------------------------

def test_child_runs_in_its_own_session(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world, window=0.3)
    (world["am"] / "run.sleep").write_text("5")
    assert helper.guarded([str(world["project"]), "board"]) == 0
    out = one_line(capsys)
    pid = read_pid(world)
    assert out["pid"] == pid
    assert wait_for(world["am"] / "run.stdin")
    sid = int((world["am"] / "run.sid").read_text())
    assert sid == pid
    assert sid != os.getsid(0)
    assert (os.path.realpath((world["am"] / "run.cwd").read_text())
            == os.path.realpath(world["project"]))


def test_child_stdin_is_devnull(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world, window=0.3)
    (world["am"] / "run.sleep").write_text("5")
    assert helper.guarded([str(world["project"]), "board"]) == 0
    one_line(capsys)
    assert wait_for(world["am"] / "run.stdin")
    assert (world["am"] / "run.stdin").read_text() == "/dev/null"


def test_helper_never_signals_child():
    # A guard for "never waits on or kills am run": the child outlives the helper.
    with open(SCRIPT) as f:
        source = f.read()
    for token in (".wait(", ".kill(", ".terminate(", "killpg", "send_signal"):
        assert token not in source, token


def test_not_visible_yet(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world, window=0.3)
    (world["am"] / "run.sleep").write_text("5")
    assert helper.guarded([str(world["project"]), "milestone", "m1", "--branch-prefix", "m3"]) == 0
    out = one_line(capsys)
    pid = read_pid(world)
    assert out == {"ok": True, "pid": pid, "log": out["log"], "started_at": out["started_at"],
                   "run_id": None, "message": "started, run not visible yet"}
    assert re.match(STARTED_AT_RE, out["started_at"])
    os.kill(pid, 0)  # still alive: raises ProcessLookupError otherwise
    assert not (world["am"] / "run.done").exists()


def test_error_after_spawn_carries_the_launch(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world)

    def boom(proc, launch):
        raise RuntimeError("boom")

    monkeypatch.setattr(helper, "early_exit", boom)
    assert helper.guarded([str(world["project"]), "board"]) == 0
    out = one_line(capsys)
    assert out["ok"] is False
    assert out["error"] == {"type": "HelperError", "message": "The launch failed: boom"}
    assert out["pid"] == read_pid(world)
    assert os.path.exists(out["log"])
    assert re.match(STARTED_AT_RE, out["started_at"])


# --- log -------------------------------------------------------------------------

def test_log_placement_and_modes(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world)
    logs = world["state"] / "omarchy-project-manager" / "am-runs"
    logs.mkdir(parents=True)
    logs.chmod(0o755)
    (world["am"] / "run.out").write_text("to stdout\n")
    (world["am"] / "run.err").write_text("to stderr\n")
    for mask in (0o000, 0o077):
        old = os.umask(mask)
        try:
            assert helper.guarded([str(world["project"]), "board"]) == 0
        finally:
            os.umask(old)
        out = one_line(capsys)
        assert out["ok"] is False  # am exited at once: an early exit, so its output is all in
        log = out["log"]
        assert os.path.isabs(log)
        assert os.path.dirname(log) == str(logs)
        assert stat.S_IMODE(os.stat(logs).st_mode) == 0o700
        assert stat.S_IMODE(os.stat(log).st_mode) == 0o600
        assert re.match(r"^\d{8}T\d{6}Z-proj-[0-9a-f]{8}\.log$", os.path.basename(log))
        with open(log) as f:
            text = f.read()
        assert "to stdout" in text
        assert "to stderr" in text


def test_relative_xdg_state_home_ignored(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world)
    cwd = world["tmp"] / "cwd"
    cwd.mkdir()
    monkeypatch.chdir(cwd)
    monkeypatch.setenv("XDG_STATE_HOME", "rel")
    assert helper.guarded([str(world["project"]), "board"]) == 0
    log = one_line(capsys)["log"]
    assert os.path.dirname(log) == str(world["home"] / ".local" / "state"
                                       / "omarchy-project-manager" / "am-runs")
    assert list(cwd.iterdir()) == []


def test_project_name_sanitized(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world)
    odd = world["tmp"] / "my proj;x"
    odd.mkdir()
    # A trailing slash still names the log after the directory, not "project".
    assert helper.guarded([str(odd) + "/", "board"]) == 0
    name = os.path.basename(one_line(capsys)["log"])
    assert re.match(r"^\d{8}T\d{6}Z-my_proj_x-[0-9a-f]{8}\.log$", name), name


def test_two_launches_get_two_logs(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world)
    fixed = time.gmtime(1790000000)
    monkeypatch.setattr(helper.time, "gmtime", lambda *a: fixed)  # same second, twice
    paths = []
    for _ in range(2):
        assert helper.guarded([str(world["project"]), "board"]) == 0
        paths.append(one_line(capsys)["log"])
    assert paths[0] != paths[1]
    assert os.path.basename(paths[0])[:16] == os.path.basename(paths[1])[:16]
    assert all(os.path.exists(p) for p in paths)


# --- errors ------------------------------------------------------------------------

def test_am_missing(world):
    empty = world["tmp"] / "empty"
    empty.mkdir()
    code, out = run(world, [str(world["project"]), "board"], PATH=str(empty))
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmMissing", "message": "am is not installed."}}
    assert not (world["state"] / "omarchy-project-manager").exists()


def test_spawn_failed_bad_root(world):
    code, out = run(world, [str(world["tmp"] / "missing"), "board"])
    assert code == 0
    assert set(out) == {"ok", "error", "log"}
    assert out["ok"] is False
    assert out["error"]["type"] == "SpawnFailed"
    assert out["error"]["message"].startswith("Could not start am run: ")
    assert stat.S_IMODE(os.stat(out["log"]).st_mode) == 0o600
    with open(out["log"]) as f:
        assert f.read().startswith("start-run: could not start am: ")
    assert calls(world) == []


def test_unexpected_error_is_helper_error(world):
    blocker = world["tmp"] / "afile"
    blocker.write_text("")
    code, out = run(world, [str(world["project"]), "board"],
                    XDG_STATE_HOME=str(blocker / "state"))
    assert code == 0
    assert set(out) == {"ok", "error"}
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The launch failed: ")
    assert calls(world) == []


@pytest.mark.parametrize("args", [
    [],
    ["/p"],
    ["/p", "story", "x"],
    ["/p", "milestone"],
    ["/p", "card", ""],
    ["", "board"],
    ["-p", "board"],
    ["/p", "board", "extra"],
    ["/p", "milestone", "m1", "--dry-run"],
    ["/p", "board", "--detach"],
    ["/p", "board", "--pretty"],
    ["/p", "board", "--verify"],
    ["/p", "board", "--base-branch", "a", "--base-branch", "b"],
    ["/p", "board", "--allow-no-verification", "--allow-no-verification"],
])
def test_usage_shapes(world, args):
    code, out = run(world, args)
    assert code == 2
    assert out == USAGE_LINE
    assert calls(world) == []
    assert not (world["state"] / "omarchy-project-manager").exists()
