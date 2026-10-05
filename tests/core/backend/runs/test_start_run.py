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


# --- early exit ------------------------------------------------------------------

EARLY_KEYS = {"ok", "error", "pid", "log", "started_at", "exit_code", "log_tail"}


def test_early_exit_with_am_refusal(world):
    # Trailing blank lines after the envelope: the last NON-EMPTY line decides.
    (world["am"] / "run.out").write_text(json.dumps(CLAIMED) + "\n\n")
    (world["am"] / "run.code").write_text("3")
    code, out = run(world, [str(world["project"]), "milestone", "m1", "--branch-prefix", "m3"])
    assert code == 0
    assert set(out) == EARLY_KEYS
    assert out["ok"] is False
    assert out["error"] == CLAIMED["error"]
    assert out["exit_code"] == 3
    assert json.dumps(CLAIMED) in out["log_tail"]
    assert out["pid"] == read_pid(world)


def test_early_exit_without_envelope(world):
    lines = ["line %d" % i for i in range(1, 31)]
    (world["am"] / "run.err").write_text("\n".join(lines) + "\n")
    (world["am"] / "run.code").write_text("2")
    code, out = run(world, [str(world["project"]), "board"])
    assert code == 0
    assert set(out) == EARLY_KEYS
    assert out["error"] == {"type": "AmExited",
                            "message": "am run exited 2 before its run appeared."}
    assert out["exit_code"] == 2
    assert out["log_tail"] == "\n".join(lines[-20:])
    # One 5000-character line is cut to its last 2000 characters.
    assert load_helper().log_tail("x" * 3000 + "y" * 2000 + "\n") == "y" * 2000


def test_last_line_not_a_refusal(world):
    # JSON, ok false, but the error is not an object: not am's refusal shape.
    (world["am"] / "run.out").write_text(json.dumps({"ok": False, "error": "text"}) + "\n")
    (world["am"] / "run.code").write_text("4")
    code, out = run(world, [str(world["project"]), "board"])
    assert code == 0
    assert out["error"] == {"type": "AmExited",
                            "message": "am run exited 4 before its run appeared."}
    assert out["exit_code"] == 4


def test_early_exit_zero(world):
    # An am that finishes at once without a visible run is still an early exit.
    code, out = run(world, [str(world["project"]), "board"])
    assert code == 0
    assert set(out) == EARLY_KEYS
    assert out["ok"] is False
    assert out["error"] == {"type": "AmExited",
                            "message": "am run exited 0 before its run appeared."}
    assert out["exit_code"] == 0


def test_early_exit_empty_log(world):
    (world["am"] / "run.code").write_text("1")
    code, out = run(world, [str(world["project"]), "board"])
    assert code == 0
    assert out["exit_code"] == 1
    assert out["log_tail"] == ""
    assert out["error"]["type"] == "AmExited"


# --- run-id discovery ----------------------------------------------------------------

NOON = datetime.datetime(2026, 10, 5, 12, 0, 0, 700000, tzinfo=datetime.timezone.utc)
SINCE = datetime.datetime(2026, 10, 5, 12, 0, 0, tzinfo=datetime.timezone.utc)


def row(run_id, started_at, prefix="m3"):
    return {"id": run_id, "workflow": "orchestrator", "repo_dir": "/p", "base_branch": "main",
            "branch_prefix": prefix, "status": "running", "started_at": started_at}


def serve_rows(world, rows):
    """The fake `am run` publishes these rows once it starts ("NOW" = its start second)."""
    (world["am"] / "run.rows").write_text(json.dumps(rows))


def seed_runs(world, rows):
    """`am runs` serves these rows from the start."""
    (world["am"] / "runs.json").write_text(json.dumps(rows))


def at_noon(helper, monkeypatch):
    """The helper's clock reads NOON, so its started_at is 2026-10-05T12:00:00Z."""
    monkeypatch.setattr(helper, "utc_now", lambda: NOON)


def test_finds_run_by_prefix_and_start_time(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world)
    at_noon(helper, monkeypatch)
    seed_runs(world, [row("other", "2026-10-05T12:00:05Z", prefix="m9"),
                      row("mine", "2026-10-05T12:00:03Z"),
                      row("old", "2026-10-05T11:59:00Z")])
    (world["am"] / "run.sleep").write_text("2")
    root = str(world["project"])
    assert helper.guarded([root, "milestone", "m1", "--branch-prefix", "m3"]) == 0
    out = one_line(capsys)
    assert out == {"ok": True, "pid": read_pid(world), "log": out["log"],
                   "started_at": "2026-10-05T12:00:00Z", "run_id": "mine", "message": ""}
    assert ["runs", "--repo-dir", root] in calls(world)


def test_started_at_same_second_counts(world, monkeypatch, capsys):
    # The helper's clock is 12:00:00.7, am stamps 12:00:00: same second, so found.
    helper = fast_helper(monkeypatch, world)
    at_noon(helper, monkeypatch)
    seed_runs(world, [row("same", "2026-10-05T12:00:00Z"),
                      row("before", "2026-10-05T11:59:59Z")])
    (world["am"] / "run.sleep").write_text("2")
    assert helper.guarded([str(world["project"]), "milestone", "m1", "--branch-prefix", "m3"]) == 0
    assert one_line(capsys)["run_id"] == "same"


def test_started_at_with_offset_parsed():
    helper = load_helper()
    assert helper.find_run([row("a", "2026-10-05T12:00:01+00:00")], "milestone", "m3", SINCE) == "a"
    assert helper.find_run([row("b", "2026-10-05T12:00:01")], "milestone", "m3", SINCE) == "b"
    # 13:59:59+02:00 is 11:59:59Z: before the spawn, so the offset is applied, not dropped.
    assert helper.find_run([row("c", "2026-10-05T13:59:59+02:00")], "milestone", "m3", SINCE) is None
    assert helper.find_run([row("d", "yesterday")], "milestone", "m3", SINCE) is None
    assert helper.find_run([row("e", 12345)], "milestone", "m3", SINCE) is None


def test_board_prefix_rule():
    helper = load_helper()
    when = "2026-10-05T12:00:01Z"
    assert helper.find_run([row("r", when, prefix="x-m3")], "board", "x", SINCE) == "r"
    assert helper.find_run([row("r", when, prefix="x")], "board", "x", SINCE) == "r"
    assert helper.find_run([row("r", when, prefix="xy-m3")], "board", "x", SINCE) is None
    # Only the board derives <prefix>-<stem>; a milestone's prefix must be equal.
    assert helper.find_run([row("r", when, prefix="x-m3")], "milestone", "x", SINCE) is None
    # A row without a branch_prefix never matches a given prefix.
    assert helper.find_run([row("r", when, prefix=None)], "board", "x", SINCE) is None
    # No --branch-prefix given: any prefix, even none.
    assert helper.find_run([row("r", when, prefix="anything")], "board", None, SINCE) == "r"
    assert helper.find_run([row("r", when, prefix=None)], "board", None, SINCE) == "r"


def test_earliest_matching_run_wins():
    helper = load_helper()
    # am lists newest first.
    rows = [row("later", "2026-10-05T12:00:09Z"), row("earlier", "2026-10-05T12:00:02Z")]
    assert helper.find_run(rows, "milestone", "m3", SINCE) == "earlier"
    tie = [row("listed-first", "2026-10-05T12:00:02Z"), row("listed-last", "2026-10-05T12:00:02Z")]
    assert helper.find_run(tie, "milestone", "m3", SINCE) == "listed-last"


def test_malformed_rows_skipped():
    helper = load_helper()
    when = "2026-10-05T12:00:01Z"
    rows = [None, "r", 5, [], {"id": "", "started_at": when}, {"id": 7, "started_at": when},
            {"started_at": when}, {"id": "no-time"}]
    assert helper.find_run(rows, "board", None, SINCE) is None


def test_runs_errors_are_retried(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world)
    at_noon(helper, monkeypatch)
    seed_runs(world, [row("mine", "2026-10-05T12:00:03Z")])
    (world["am"] / "runs.fail").write_text("3")
    (world["am"] / "run.sleep").write_text("3")
    assert helper.guarded([str(world["project"]), "milestone", "m1", "--branch-prefix", "m3"]) == 0
    out = one_line(capsys)
    assert out["ok"] is True
    assert out["run_id"] == "mine"
    assert int((world["am"] / "runs.count").read_text()) >= 4


@pytest.mark.parametrize("runs_out", [
    "not json\n",
    json.dumps({"ok": False, "error": {"type": "X", "message": "y"}}) + "\n",
    json.dumps({"ok": True}) + "\n",
    json.dumps({"ok": True, "data": []}) + "\n",
    json.dumps({"ok": True, "data": {"runs": {}}}) + "\n",
    json.dumps({"ok": True, "data": {"runs": [None, "x", {"id": ""},
                                              {"id": 5, "started_at": "2099-01-01T00:00:00Z"},
                                              {"id": "r", "branch_prefix": "x"}]}}) + "\n",
    "[]\n",
])
def test_runs_bad_output_ignored(world, monkeypatch, capsys, runs_out):
    helper = fast_helper(monkeypatch, world, window=0.3)
    (world["am"] / "runs.out").write_text(runs_out)
    (world["am"] / "run.sleep").write_text("5")
    assert helper.guarded([str(world["project"]), "board"]) == 0
    out = one_line(capsys)
    assert out["ok"] is True
    assert out["run_id"] is None
    assert out["message"] == "started, run not visible yet"


def test_run_found_even_if_child_exited(world):
    serve_rows(world, [row("r-new", "NOW")])
    code, out = run(world, [str(world["project"]), "milestone", "m1", "--branch-prefix", "m3"])
    assert code == 0
    assert out["ok"] is True
    assert out["run_id"] == "r-new"
    assert out["message"] == ""


def test_child_exiting_during_query_is_not_early_exit(world, monkeypatch, capsys):
    # am exits while the first `am runs` is in flight; that query does not show the
    # row yet. The exit was not seen before the query, so the next tick looks again
    # and finds the run instead of reporting an early exit.
    helper = fast_helper(monkeypatch, world)
    serve_rows(world, [row("r-new", "NOW")])
    (world["am"] / "run.sleep").write_text("0.3")  # still running at the first tick
    real = helper.list_runs
    seen = []

    def lagging(am, root):
        seen.append(True)
        if len(seen) == 1:
            assert wait_for(world["am"] / "run.done")
            time.sleep(0.3)  # let the fake finish exiting
            return []
        return real(am, root)

    monkeypatch.setattr(helper, "list_runs", lagging)
    assert helper.guarded([str(world["project"]), "milestone", "m1", "--branch-prefix", "m3"]) == 0
    out = one_line(capsys)
    assert out["ok"] is True
    assert out["run_id"] == "r-new"


def test_helper_returns_while_child_runs(world):
    serve_rows(world, [row("r-new", "NOW")])
    (world["am"] / "run.sleep").write_text("5")
    began = time.monotonic()
    code, out = run(world, [str(world["project"]), "milestone", "m1", "--branch-prefix", "m3"])
    assert time.monotonic() - began < 4
    assert code == 0
    assert out["ok"] is True
    assert out["run_id"] == "r-new"
    assert out["message"] == ""
    assert not (world["am"] / "run.done").exists()


def test_child_survives_the_helper_group_being_killed(world, tmp_path):
    # HelperRunner stopping the helper, or the panel closing, signals the helper's
    # process group. am runs in its own session, so it must survive.
    serve_rows(world, [row("r-new", "NOW")])
    (world["am"] / "run.sleep").write_text("2")
    driver = tmp_path / "driver.py"
    driver.write_text(
        "import importlib.util, sys, time\n"
        "spec = importlib.util.spec_from_file_location('start_run', %r)\n"
        "m = importlib.util.module_from_spec(spec)\n"
        "spec.loader.exec_module(m)\n"
        "m.POLL_INTERVAL = 0.05\n"
        "m.guarded([%r, 'milestone', 'm1', '--branch-prefix', 'm3'])\n"
        "sys.stdout.flush()\n"
        "time.sleep(30)\n" % (SCRIPT, str(world["project"])))
    p = subprocess.Popen([sys.executable, str(driver)], stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, env=env_for(world),
                         start_new_session=True)
    try:
        ready, _, _ = select.select([p.stdout], [], [], 15)
        assert ready, "the helper printed nothing"
        assert json.loads(p.stdout.readline())["run_id"] == "r-new"
        assert not (world["am"] / "run.done").exists()
    finally:
        os.killpg(p.pid, signal.SIGKILL)
        p.wait()
        p.stdout.close()
    assert wait_for(world["am"] / "run.done")
