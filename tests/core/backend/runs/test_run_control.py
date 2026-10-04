"""run-control.py: an `am pause|resume|cancel` passthrough, one JSON line on every path.

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
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "run-control.py")

# The fake am logs its argv, then (keyed on the subcommand: pause, resume or
# cancel) writes FAKE_AM_DIR/<name>.err to stderr if present, prints
# FAKE_AM_DIR/<name>.out verbatim and exits with FAKE_AM_DIR/<name>.code
# (default 0). Fixtures are copied as bytes, so they may hold invalid UTF-8. A
# missing .out fixture behaves like real am for an unknown run: an
# UnknownRunError envelope and exit 3.
FAKE_AM = '''#!/usr/bin/env python3
import json, os, sys
d = os.environ["FAKE_AM_DIR"]
args = sys.argv[1:]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(args) + "\\n")
name = args[0] if args[:1] in (["pause"], ["resume"], ["cancel"]) else "other"
out = os.path.join(d, name + ".out")
if not os.path.exists(out):
    sys.stdout.write(json.dumps({"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}) + "\\n")
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

UNKNOWN_RUN = {"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}
USAGE = {"ok": False, "error": {"type": "Usage", "message":
         "usage: run-control.py <pause|resume|cancel> RUN REPO"
         " [--verify CMD]... [--allow-no-verification]"}}
TRACEBACK = "Traceback (most recent call last):\nValueError: boom\n"


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


def set_raw(world, name, text, code=0, stderr=None):
    """am <name> prints `text` (str or bytes), writes `stderr` and exits `code`."""
    out = world["am"] / (name + ".out")
    out.write_bytes(text if isinstance(text, bytes) else text.encode())
    (world["am"] / (name + ".code")).write_text(str(code))
    if stderr is not None:
        err = world["am"] / (name + ".err")
        err.write_bytes(stderr if isinstance(stderr, bytes) else stderr.encode())


def set_envelope(world, name, envelope, code=0):
    set_raw(world, name, json.dumps(envelope) + "\n", code)


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def load_helper():
    """The script as a module (its name has a hyphen, so no plain import)."""
    spec = importlib.util.spec_from_file_location("run_control", SCRIPT)
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


OK = {"ok": True, "data": {"run_id": "r1"}}


# --- am argv -----------------------------------------------------------------

def test_pause_argv(world):
    set_envelope(world, "pause", OK)
    code, _ = run(world, ["pause", "r1", "/p"])
    assert code == 0
    made = calls(world)
    assert made == [["pause", "r1", "--repo-dir", "/p"]]
    assert "--pretty" not in made[0]
    assert "--verify" not in made[0]


def test_cancel_argv(world):
    set_envelope(world, "cancel", OK)
    code, _ = run(world, ["cancel", "r1", "/p"])
    assert code == 0
    assert calls(world) == [["cancel", "r1", "--repo-dir", "/p"]]


def test_resume_argv_bare(world):
    set_envelope(world, "resume", OK)
    code, _ = run(world, ["resume", "r1", "/p"])
    assert code == 0
    assert calls(world) == [["resume", "r1", "--repo-dir", "/p"]]


def test_resume_argv_repeated_verify_in_order(world):
    set_envelope(world, "resume", OK)
    code, _ = run(world, ["resume", "r1", "/p", "--verify", "pytest -q", "--verify", "npm test"])
    assert code == 0
    assert calls(world) == [["resume", "r1", "--repo-dir", "/p",
                             "--verify", "pytest -q", "--verify", "npm test"]]


def test_resume_argv_allow_no_verification(world):
    set_envelope(world, "resume", OK)
    code, _ = run(world, ["resume", "r1", "/p", "--allow-no-verification"])
    assert code == 0
    assert calls(world) == [["resume", "r1", "--repo-dir", "/p", "--allow-no-verification"]]


def test_resume_argv_verify_then_allow(world):
    # Both flags: every --verify pair first, in the order given, then the allow flag.
    set_envelope(world, "resume", OK)
    code, _ = run(world, ["resume", "r1", "/p", "--allow-no-verification",
                          "--verify", "make check", "--verify", "ruff ."])
    assert code == 0
    assert calls(world) == [["resume", "r1", "--repo-dir", "/p", "--verify", "make check",
                             "--verify", "ruff .", "--allow-no-verification"]]


def test_args_reach_am_verbatim(world):
    # Spaces, shell metacharacters and a leading dash each arrive as one argv
    # element; a --verify value that looks like a flag is a value, not a flag.
    set_envelope(world, "resume", OK)
    code, _ = run(world, ["resume", "r 1; echo x", "/p $(whoami) & y",
                          "--verify", "-x", "--verify", "--allow-no-verification",
                          "--verify", "echo hi; ls $(pwd) &"])
    assert code == 0
    assert calls(world) == [["resume", "r 1; echo x", "--repo-dir", "/p $(whoami) & y",
                             "--verify", "-x", "--verify", "--allow-no-verification",
                             "--verify", "echo hi; ls $(pwd) &"]]


# --- envelope passthrough ------------------------------------------------------

@pytest.mark.parametrize("action,data", [
    ("pause", {"run_id": "r1", "action": "pause", "already_requested": True}),
    ("cancel", {"run_id": "r1", "action": "cancel", "already_requested": False}),
    ("resume", {"run_id": "r1", "status": "done"}),
])
def test_ok_envelope_passed_through(world, action, data):
    # resume's fake exits at once, so it lands inside the grace window.
    envelope = {"ok": True, "data": data}
    set_envelope(world, action, envelope)
    code, out = run(world, [action, "r1", "/p"])  # run() asserts exactly one JSON line
    assert code == 0
    assert out == envelope


@pytest.mark.parametrize("action,kind", [
    ("pause", "UnknownRunError"),
    ("pause", "NotRunningError"),
    ("cancel", "DeadRunError"),
    ("pause", "NotAcceptingError"),
    ("resume", "RunIsLiveError"),
    ("resume", "NotResumableError"),
    ("resume", "ClaimedError"),
    ("cancel", "LockTimeoutError"),
])
def test_refusal_passed_through_exit_0(world, action, kind):
    refusal = {"ok": False, "error": {"type": kind, "message": "refused: " + kind}}
    set_envelope(world, action, refusal, code=3)
    code, out = run(world, [action, "r1", "/p"])
    assert code == 0
    assert out == refusal


def test_missing_fixture_unknown_run(world):
    # No pause.out: the fake am answers UnknownRunError with exit 3.
    code, out = run(world, ["pause", "r1", "/p"])
    assert code == 0
    assert out == UNKNOWN_RUN
    assert calls(world) == [["pause", "r1", "--repo-dir", "/p"]]


def test_ok_wins_over_exit_code_and_stderr(world):
    # The envelope's `ok` decides, not am's exit code; am's stderr never reaches
    # the helper's stdout line.
    envelope = {"ok": True, "data": {"run_id": "r1", "already_requested": True}}
    set_raw(world, "cancel", json.dumps(envelope) + "\n", code=3,
            stderr="warning: noisy\nmore noise\n")
    code, out = run(world, ["cancel", "r1", "/p"])
    assert code == 0
    assert out == envelope


def test_pretty_printed_output_becomes_one_line(world):
    envelope = {"ok": True, "data": {"run_id": "r1", "already_requested": False}}
    set_raw(world, "pause", json.dumps(envelope, indent=2) + "\n")
    code, out = run(world, ["pause", "r1", "/p"])  # run() asserts exactly one line
    assert code == 0
    assert out == envelope


# --- failures -------------------------------------------------------------------

NOT_ENVELOPES = ["", "not json\n", "[1, 2]\n", '{"data": {}}\n', '{"ok": "true"}\n']
NOT_ENVELOPE_IDS = ["empty", "not-json", "list", "no-ok", "ok-string"]


@pytest.mark.parametrize("text", NOT_ENVELOPES, ids=NOT_ENVELOPE_IDS)
def test_exit_0_without_envelope_is_am_bad_output(world, text):
    set_raw(world, "pause", text, code=0, stderr=TRACEBACK)
    code, out = run(world, ["pause", "r1", "/p"])
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "AmBadOutput"
    assert out["error"]["message"].startswith("am pause ")
    assert out["error"]["message"].endswith("(exit 0).")


def test_am_missing(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, out = run(world, ["pause", "r1", "/p"], PATH=str(empty))
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmMissing", "message": "am is not installed."}}
    assert calls(world) == []


def test_usage_wins_over_am_missing(world):
    # The arguments are checked before am is looked for.
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, out = run(world, ["stop", "r1", "/p"], PATH=str(empty))
    assert code == 2
    assert out == USAGE


@pytest.mark.parametrize("args", [
    [],
    ["pause", "r1"],
    ["stop", "r1", "/p"],
    ["pause", "r1", "/p", "extra"],
    ["pause", "r1", "/p", "--verify", "pytest"],
    ["cancel", "r1", "/p", "--verify", "pytest"],
    ["pause", "r1", "/p", "--allow-no-verification"],
    ["resume", "r1", "/p", "--verify"],
    ["resume", "r1", "/p", "--pretty"],
    ["pause", "", "/p"],
    ["pause", "r1", ""],
    ["pause", "-r1", "/p"],
], ids=["none", "two", "unknown-action", "extra-positional", "verify-pause",
        "verify-cancel", "allow-pause", "verify-last", "unknown-option",
        "empty-run", "empty-repo", "dash-run"])
def test_usage(world, args):
    code, out = run(world, args)
    assert code == 2
    assert out == USAGE
    assert calls(world) == []


@pytest.mark.parametrize("action", ["pause", "resume"])
def test_am_cannot_start_is_helper_error(world, action):
    # Executable (so shutil.which finds it) but unstartable: subprocess raises
    # OSError and guarded() must still print exactly one JSON line.
    write_exec(world["bin"] / "am", "#!/nonexistent/interpreter\n")
    code, out = run(world, [action, "r1", "/p"])
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The run control failed: ")


def test_am_does_not_inherit_stdin(world):
    # The helper's stdin is an open pipe that never sends EOF. An am that reads
    # stdin must get EOF at once (stdin is /dev/null), not block on that pipe.
    write_exec(world["bin"] / "am",
               "#!/usr/bin/env python3\nimport json, sys\nsys.stdin.read()\n"
               "print(json.dumps({'ok': True, 'data': {'run_id': 'r1'}}))\n")
    p = subprocess.Popen([sys.executable, SCRIPT, "pause", "r1", "/p"], stdin=subprocess.PIPE,
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
    assert json.loads(lines[0]) == {"ok": True, "data": {"run_id": "r1"}}


# --- timing ---------------------------------------------------------------------

def test_pause_timeout_is_helper_error(world, monkeypatch, capsys):
    # An am that hangs is cut off after AM_TIMEOUT and reported as HelperError
    # (shortened here so the test does not wait the real 60 s).
    write_exec(world["bin"] / "am", "#!/usr/bin/env python3\nimport time\ntime.sleep(10)\n")
    helper = load_helper()
    assert helper.AM_TIMEOUT == 60
    monkeypatch.setattr(helper, "AM_TIMEOUT", 0.5)
    use_world(world, monkeypatch)
    code = helper.guarded(["pause", "r1", "/p"])
    out = one_line(capsys)
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The run control failed: ")

# --- am crashed -----------------------------------------------------------------

@pytest.mark.parametrize("text", NOT_ENVELOPES, ids=NOT_ENVELOPE_IDS)
def test_nonzero_exit_without_envelope_is_am_failed(world, text):
    set_raw(world, "cancel", text, code=1, stderr=TRACEBACK)
    code, out = run(world, ["cancel", "r1", "/p"])
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "AmFailed"
    assert out["error"]["message"].endswith("ValueError: boom")


def test_am_failed_message_is_the_stderr_tail(world):
    lines = ["line %02d" % i for i in range(50)]
    set_raw(world, "cancel", "", code=1, stderr="\n".join(lines) + "\n")
    _, out = run(world, ["cancel", "r1", "/p"])
    assert out["error"]["type"] == "AmFailed"
    assert out["error"]["message"] == "\n".join(lines[30:])

    set_raw(world, "cancel", "", code=1, stderr="a" * 3000 + "b" * 2000 + "\n")
    _, out = run(world, ["cancel", "r1", "/p"])
    assert out["error"]["type"] == "AmFailed"
    assert out["error"]["message"] == "b" * 2000


def test_am_failed_tail_drops_trailing_whitespace(world):
    set_raw(world, "cancel", "", code=1, stderr="boom\n\n  \n\t\n")
    _, out = run(world, ["cancel", "r1", "/p"])
    assert out["error"] == {"type": "AmFailed", "message": "boom"}


def test_am_failed_with_no_stderr(world):
    set_raw(world, "cancel", "", code=1)
    code, out = run(world, ["cancel", "r1", "/p"])
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmFailed",
                                          "message": "am cancel exited 1 with no output."}}


def test_am_failed_with_invalid_utf8_stderr(world):
    # Bytes that are not UTF-8 must not turn into a HelperError.
    set_raw(world, "cancel", b"", code=1, stderr=b"bad \xff byte\n")
    code, out = run(world, ["cancel", "r1", "/p"])
    assert code == 0
    assert out["error"] == {"type": "AmFailed", "message": "bad � byte"}
