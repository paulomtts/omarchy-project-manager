"""dispatch-preview.py: an `am run --dry-run` passthrough and the repo's default
branch, one JSON line on every path.

Hermetic: a fake `am` lives on a temp PATH and serves hand-written fixtures from
FAKE_AM_DIR, appending each call's argv to calls.log; HOME and XDG_DATA_HOME are
temp. The real `am` and real data are never touched.
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
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "dispatch-preview.py")

# The fake am logs its argv, then (keyed on the subcommand, so "run") writes
# FAKE_AM_DIR/run.err to stderr if present, prints FAKE_AM_DIR/run.out verbatim
# and exits with FAKE_AM_DIR/run.code (default 0). Fixtures are copied as bytes,
# so they may hold invalid UTF-8. A missing .out fixture behaves like real am for
# an unknown milestone: a MilestoneNotFoundError envelope and exit 3.
FAKE_AM = '''#!/usr/bin/env python3
import json, os, sys
d = os.environ["FAKE_AM_DIR"]
args = sys.argv[1:]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(args) + "\\n")
name = "run" if args[:1] == ["run"] else "other"
out = os.path.join(d, name + ".out")
if not os.path.exists(out):
    sys.stdout.write(json.dumps({"error": {"message": "milestone not found", "type": "MilestoneNotFoundError"}, "ok": False}) + "\\n")
    sys.exit(3)
err = os.path.join(d, name + ".err")
if os.path.exists(err):
    with open(err, "rb") as f:
        sys.stderr.buffer.write(f.read())
with open(out, "rb") as f:
    sys.stdout.buffer.write(f.read())
code = os.path.join(d, name + ".code")
sys.exit(int(open(code).read()) if os.path.exists(code) else 0)
'''

NOT_FOUND = {"error": {"message": "milestone not found", "type": "MilestoneNotFoundError"}, "ok": False}
USAGE_LINE = {"ok": False, "error": {"type": "Usage", "message":
              "usage: dispatch-preview.py ROOT (milestone ID | board) [--base-branch B]"
              " [--branch-prefix P] [--max-concurrent N] [--verify CMD]..."
              " [--allow-no-verification] | dispatch-preview.py --defaults ROOT"}}

# Recorded shapes of `am run --dry-run` data. Opaque to the helper: it must pass
# them through untouched (previewSummary in runs.js reads them).
MILESTONE_PLAN = {"ok": True, "data": {
    "max_concurrent": 4,
    "levels": [
        {"level": 0, "concurrent": 1, "stories": [
            {"story": "s1", "title": "Story one", "root": "main",
             "subtasks": [{"card": "c1", "branch": "m3-c1", "base": "main"}]}]},
    ],
    "already_done": [{"kind": "story", "id": "s4", "title": "Story four"}],
    "integrate": {"branch": "m3-integrate", "worktree": "/p/.worktrees/m3-integrate",
                  "order": [{"story": "s1", "tip": "m3-c1"}]},
}}
BOARD_PLAN = {"ok": True, "data": {
    "board": True,
    "max_concurrent": 4,
    "levels": [{"level": 0, "milestones": [
        {"milestone_id": "m1", "title": "M1 First", "branch_prefix": "m1",
         "base_branch": "main", "plan": {"levels": [], "already_done": []}}]}],
}}
CLAIMED = {"ok": False, "error": {"type": "ClaimedError",
                                  "message": "card c1 is claimed by run r9"}}


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am, its fixture dir, and a temp HOME/XDG_DATA_HOME."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "am", FAKE_AM)
    amdir = tmp_path / "am"
    amdir.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    return {"tmp": tmp_path, "bin": bindir, "am": amdir, "home": home,
            "data": tmp_path / "data"}


def env_for(world, **extra):
    e = {
        "PATH": str(world["bin"]) + os.pathsep + "/usr/bin" + os.pathsep + "/bin",
        "HOME": str(world["home"]),
        "XDG_DATA_HOME": str(world["data"]),
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


def set_raw(world, text, code=0, stderr=None):
    """am run prints `text` (str or bytes), writes `stderr` and exits `code`."""
    out = world["am"] / "run.out"
    out.write_bytes(text if isinstance(text, bytes) else text.encode())
    (world["am"] / "run.code").write_text(str(code))
    if stderr is not None:
        err = world["am"] / "run.err"
        err.write_bytes(stderr if isinstance(stderr, bytes) else stderr.encode())


def set_envelope(world, envelope, code=0):
    set_raw(world, json.dumps(envelope) + "\n", code)


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def load_helper():
    """The script as a module (its name has a hyphen, so no plain import)."""
    spec = importlib.util.spec_from_file_location("dispatch_preview", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def use_world(world, monkeypatch):
    for key, value in env_for(world).items():
        monkeypatch.setenv(key, value)


def one_line(capsys):
    lines = capsys.readouterr().out.splitlines()
    assert len(lines) == 1, lines
    return json.loads(lines[0])


# --- am argv -----------------------------------------------------------------

def test_milestone_argv(world):
    set_envelope(world, MILESTONE_PLAN)
    code, _ = run(world, ["/p", "milestone", "m1"])
    assert code == 0
    made = calls(world)
    assert made == [["run", "--milestone", "m1", "--dry-run", "--repo-dir", "/p"]]
    assert "--pretty" not in made[0]
    assert "--detach" not in made[0]


def test_board_argv(world):
    set_envelope(world, BOARD_PLAN)
    code, _ = run(world, ["/p", "board"])
    assert code == 0
    made = calls(world)
    assert made == [["run", "--board", "--dry-run", "--repo-dir", "/p"]]
    assert "--milestone" not in made[0]


def test_milestone_named_board(world):
    # The target is a literal word, so a milestone titled "board" stays a milestone.
    set_envelope(world, MILESTONE_PLAN)
    code, _ = run(world, ["/p", "milestone", "board"])
    assert code == 0
    assert calls(world) == [["run", "--milestone", "board", "--dry-run", "--repo-dir", "/p"]]


def test_options_forwarded_in_fixed_order(world):
    set_envelope(world, MILESTONE_PLAN)
    code, _ = run(world, ["/p", "milestone", "m1",
                          "--verify", "uv run pytest", "--max-concurrent", "2",
                          "--branch-prefix", "m3", "--base-branch", "main",
                          "--verify", "-x", "--allow-no-verification"])
    assert code == 0
    assert calls(world) == [["run", "--milestone", "m1", "--dry-run", "--repo-dir", "/p",
                             "--base-branch", "main", "--branch-prefix", "m3",
                             "--max-concurrent", "2",
                             "--verify", "uv run pytest", "--verify", "-x",
                             "--allow-no-verification"]]


def test_verify_values_verbatim(world):
    # Spaces, shell metacharacters, a leading dash and an empty string each arrive
    # as one unaltered argv element: no shell, no validation by the helper.
    values = ["uv run pytest -q", "make test; echo done", "echo $HOME", "-x", ""]
    args = ["/p", "board"]
    for value in values:
        args += ["--verify", value]
    set_envelope(world, BOARD_PLAN)
    code, _ = run(world, args)
    assert code == 0
    expected = ["run", "--board", "--dry-run", "--repo-dir", "/p"]
    for value in values:
        expected += ["--verify", value]
    assert calls(world) == [expected]


def test_root_and_id_verbatim(world):
    set_envelope(world, MILESTONE_PLAN)
    code, _ = run(world, ["/my repo; x", "milestone", "M3 Dispatch & preview",
                          "--max-concurrent", "two"])
    assert code == 0
    assert calls(world) == [["run", "--milestone", "M3 Dispatch & preview", "--dry-run",
                             "--repo-dir", "/my repo; x", "--max-concurrent", "two"]]


def test_board_with_branch_prefix(world):
    set_envelope(world, BOARD_PLAN)
    code, _ = run(world, ["/p", "board", "--branch-prefix", "x"])
    assert code == 0
    assert calls(world) == [["run", "--board", "--dry-run", "--repo-dir", "/p",
                             "--branch-prefix", "x"]]


def test_environment_passed_to_am(world):
    # am keeps its data under XDG_DATA_HOME/HOME, so it must see the helper's own;
    # its cwd is the helper's too.
    write_exec(world["bin"] / "am",
               "#!/usr/bin/env python3\nimport json, os\n"
               "with open(os.path.join(os.environ['FAKE_AM_DIR'], 'env.json'), 'w') as f:\n"
               "    json.dump({'HOME': os.environ.get('HOME'),"
               " 'XDG_DATA_HOME': os.environ.get('XDG_DATA_HOME'), 'cwd': os.getcwd()}, f)\n"
               "print(json.dumps({'ok': True, 'data': {'board': True, 'levels': []}}))\n")
    code, out = run(world, ["/p", "board"])
    assert code == 0
    assert out == {"ok": True, "data": {"board": True, "levels": []}}
    seen = json.loads((world["am"] / "env.json").read_text())
    assert seen == {"HOME": str(world["home"]), "XDG_DATA_HOME": str(world["data"]),
                    "cwd": os.getcwd()}


# --- envelope passthrough ------------------------------------------------------

def test_milestone_plan_passthrough(world):
    set_envelope(world, MILESTONE_PLAN)
    code, out = run(world, ["/p", "milestone", "m1", "--branch-prefix", "m3"])
    assert code == 0
    assert out == MILESTONE_PLAN


def test_board_plan_passthrough(world):
    set_envelope(world, BOARD_PLAN)
    code, out = run(world, ["/p", "board"])
    assert code == 0
    assert out == BOARD_PLAN


def test_pretty_envelope_reserialised_to_one_line(world):
    set_raw(world, json.dumps(MILESTONE_PLAN, indent=2) + "\n")
    code, out = run(world, ["/p", "milestone", "m1"])  # run() asserts exactly one line
    assert code == 0
    assert out == MILESTONE_PLAN


def test_refusal_passthrough_exit_3(world):
    set_envelope(world, CLAIMED, code=3)
    code, out = run(world, ["/p", "milestone", "m1"])
    assert code == 0
    assert out == CLAIMED


def test_default_fake_refusal(world):
    # No run.out: the fake answers like real am for an unknown milestone.
    code, out = run(world, ["/p", "milestone", "nope"])
    assert code == 0
    assert out == NOT_FOUND
    assert calls(world) == [["run", "--milestone", "nope", "--dry-run", "--repo-dir", "/p"]]


def test_ok_true_with_nonzero_exit_still_envelope(world):
    # The envelope's ok decides, not am's exit code; stderr never reaches stdout.
    set_raw(world, json.dumps(BOARD_PLAN) + "\n", code=1, stderr="warning: noisy\n")
    code, out = run(world, ["/p", "board"])
    assert code == 0
    assert out == BOARD_PLAN


def test_non_utf8_output_still_one_line(world):
    # Undecodable bytes are replaced, never a crash; non-ASCII text round-trips.
    set_raw(world, b'{"ok": true, "data": {"title": "caf\xc3\xa9 \xe2\x9c\x93 \xff"}}\n')
    code, out = run(world, ["/p", "board"])
    assert code == 0
    assert out == {"ok": True, "data": {"title": "caf\u00e9 \u2713 \ufffd"}}
    set_raw(world, b"", code=2, stderr=b"Error: bad \xff value\n")
    code, out = run(world, ["/p", "board"])
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmFailed", "message": "Error: bad \ufffd value"}}


def test_am_does_not_inherit_stdin(world):
    # The helper's stdin is an open pipe that never sends EOF. An am that reads
    # stdin must get EOF at once (stdin is /dev/null), not block on that pipe.
    write_exec(world["bin"] / "am",
               "#!/usr/bin/env python3\nimport json, sys\nsys.stdin.read()\n"
               "print(json.dumps({'ok': True, 'data': {'board': True, 'levels': []}}))\n")
    p = subprocess.Popen([sys.executable, SCRIPT, "/p", "board"], stdin=subprocess.PIPE,
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
    assert len(lines) == 1
    assert json.loads(lines[0]) == {"ok": True, "data": {"board": True, "levels": []}}


# --- failures --------------------------------------------------------------------

def test_am_failed_stderr_tail(world):
    # click's own rejections (missing --branch-prefix, --max-concurrent 0) print no
    # envelope, only a usage box on stderr: the tail is the message.
    stderr = "".join("line %d\n" % i for i in range(30))
    set_raw(world, "", code=2, stderr=stderr)
    code, out = run(world, ["/p", "milestone", "m1"])
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmFailed", "message":
                   "\n".join("line %d" % i for i in range(10, 30))}}
    set_raw(world, "", code=2, stderr="a" * 3000 + "b" * 2000 + "\n")
    code, out = run(world, ["/p", "milestone", "m1"])
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmFailed", "message": "b" * 2000}}


def test_am_failed_no_output(world):
    set_raw(world, "", code=2)
    code, out = run(world, ["/p", "board"])
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmFailed",
                                          "message": "am run exited 2 with no output."}}


@pytest.mark.parametrize("text,message", [
    ("not json\n", "am run did not print JSON (exit 0)."),
    ("[1]\n", "am run printed JSON that is not an object (exit 0)."),
    ('{"ok": "yes"}\n', "am run printed an object without a boolean ok field (exit 0)."),
], ids=["not-json", "list", "ok-string"])
def test_am_bad_output(world, text, message):
    set_raw(world, text, code=0)
    code, out = run(world, ["/p", "board"])
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmBadOutput", "message": message}}


def test_am_missing(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, out = run(world, ["/p", "board"], PATH=str(empty))
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmMissing", "message": "am is not installed."}}
    assert calls(world) == []
    # Checked only after the arguments are valid: a bad command line is still Usage.
    code, out = run(world, ["/p"], PATH=str(empty))
    assert code == 2
    assert out == USAGE_LINE


def test_timeout_is_helper_error(world, monkeypatch, capsys):
    # An am that hangs is cut off after AM_TIMEOUT (shortened here so the test does
    # not wait the real 60 s) and reported as HelperError.
    write_exec(world["bin"] / "am", "#!/usr/bin/env python3\nimport time\ntime.sleep(10)\n")
    helper = load_helper()
    assert helper.AM_TIMEOUT == 60
    monkeypatch.setattr(helper, "AM_TIMEOUT", 0.5)
    use_world(world, monkeypatch)
    code = helper.guarded(["/p", "board"])
    out = one_line(capsys)
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The dispatch preview failed: ")


def test_am_that_cannot_start_is_helper_error(world):
    # Executable (so shutil.which finds it) but unstartable: subprocess raises
    # OSError and guarded() must still print exactly one JSON line.
    write_exec(world["bin"] / "am", "#!/nonexistent/interpreter\n")
    code, out = run(world, ["/p", "board"])
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The dispatch preview failed: ")


# --- usage -------------------------------------------------------------------------

@pytest.mark.parametrize("args", [
    [],
    ["/p"],
    ["/p", "story", "x"],
    ["/p", "milestone"],
    ["/p", "milestone", ""],
    ["", "board"],
    ["-p", "board"],
    ["/p", "board", "extra"],
    ["/p", "milestone", "m1", "extra"],
    ["/p", "board", "--pretty"],
    ["/p", "board", "--verify"],
    ["/p", "board", "--base-branch", "a", "--base-branch", "b"],
    ["/p", "board", "--allow-no-verification", "--allow-no-verification"],
    ["--defaults"],
    ["--defaults", "/a", "/b"],
    ["--defaults", "/p", "--verify", "x"],
    ["--defaults", "-x"],
])
def test_usage_shapes(world, args):
    code, out = run(world, args)
    assert code == 2
    assert out == USAGE_LINE
    assert calls(world) == []
