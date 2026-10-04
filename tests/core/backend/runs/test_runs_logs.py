"""runs-logs.py: an `am logs` passthrough for one attempt, one JSON line on every path.

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
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "runs-logs.py")

# The fake am logs its argv, then (keyed on the subcommand, so "logs") writes
# FAKE_AM_DIR/logs.err to stderr if present, prints FAKE_AM_DIR/logs.out verbatim
# and exits with FAKE_AM_DIR/logs.code (default 0). A missing .out fixture behaves
# like real am for an unknown run: an UnknownRunError envelope and exit 3.
FAKE_AM = '''#!/usr/bin/env python3
import json, os, sys
d = os.environ["FAKE_AM_DIR"]
args = sys.argv[1:]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(args) + "\\n")
name = "logs" if args[:1] == ["logs"] else "other"
out = os.path.join(d, name + ".out")
if not os.path.exists(out):
    sys.stdout.write(json.dumps({"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}) + "\\n")
    sys.exit(3)
err = os.path.join(d, name + ".err")
if os.path.exists(err):
    with open(err) as f:
        sys.stderr.write(f.read())
with open(out) as f:
    sys.stdout.write(f.read())
code = os.path.join(d, name + ".code")
sys.exit(int(open(code).read()) if os.path.exists(code) else 0)
'''

ARGS = ["r1", "c1", "implement", "2"]
UNKNOWN_RUN = {"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}
# Opaque to the helper: it must pass whatever `data` am prints through untouched.
LOGS_DATA = {
    "run_id": "r1", "card_id": "c1", "phase": "implement", "attempt": 2,
    "prompt": "Implement the card.\nUse TDD.",
    "result": {"status": "done"},
    "stdout": "collecting...\n3 passed\n",
    "stderr": "",
}


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
    argv = ARGS if args is None else args
    p = subprocess.run([sys.executable, SCRIPT, *argv], capture_output=True, text=True,
                       env=env_for(world, drop, **extra), timeout=60)
    lines = p.stdout.splitlines()
    assert len(lines) == 1, (p.stdout, p.stderr)
    return p.returncode, json.loads(lines[0])


def set_logs(world, envelope, code=0):
    (world["am"] / "logs.out").write_text(json.dumps(envelope) + "\n")
    (world["am"] / "logs.code").write_text(str(code))


def set_raw(world, text, code=0, stderr=None):
    (world["am"] / "logs.out").write_text(text)
    (world["am"] / "logs.code").write_text(str(code))
    if stderr is not None:
        (world["am"] / "logs.err").write_text(stderr)


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


# --- passthrough -------------------------------------------------------------

def test_ok_envelope_passed_through(world):
    envelope = {"ok": True, "data": LOGS_DATA}
    set_logs(world, envelope)
    code, out = run(world)  # run() asserts stdout is exactly one JSON line
    assert code == 0
    assert out == envelope


def test_exact_am_argv(world):
    set_logs(world, {"ok": True, "data": LOGS_DATA})
    code, _ = run(world)
    assert code == 0
    made = calls(world)
    assert made == [["logs", "r1", "c1", "--phase", "implement", "--attempt", "2"]]
    assert "--repo-dir" not in made[0]
    assert "--pretty" not in made[0]


def test_args_reach_am_verbatim(world):
    # Spaces, shell metacharacters and a leading dash must each arrive as one argv
    # element: no shell, no validation by the helper.
    args = ["r 1; echo x", "c$(whoami)", "plan & review", "-1"]
    set_logs(world, {"ok": True, "data": LOGS_DATA})
    code, _ = run(world, args)
    assert code == 0
    assert calls(world) == [["logs", "r 1; echo x", "c$(whoami)",
                             "--phase", "plan & review", "--attempt", "-1"]]


def test_pretty_printed_am_output_becomes_one_line(world):
    envelope = {"ok": True, "data": LOGS_DATA}
    set_raw(world, json.dumps(envelope, indent=2) + "\n")
    code, out = run(world)  # run() asserts exactly one line
    assert code == 0
    assert out == envelope


def test_refusal_passed_through_exit_0(world):
    refusal = {"ok": False, "error": {"type": "UsageError",
                                      "message": "--attempt must be an integer"}}
    set_logs(world, refusal, code=3)
    code, out = run(world)
    assert code == 0
    assert out == refusal


def test_missing_fixture_unknown_run(world):
    # No logs.out: the fake am answers UnknownRunError with exit 3.
    code, out = run(world)
    assert code == 0
    assert out == UNKNOWN_RUN
    assert calls(world) == [["logs", "r1", "c1", "--phase", "implement", "--attempt", "2"]]


def test_ok_wins_over_am_exit_code_and_stderr(world):
    # The envelope's `ok` decides, not am's exit code; am's stderr never reaches
    # the helper's stdout line.
    envelope = {"ok": True, "data": LOGS_DATA}
    set_raw(world, json.dumps(envelope) + "\n", code=3, stderr="warning: noisy\nmore noise\n")
    code, out = run(world)
    assert code == 0
    assert out == envelope


def test_large_output_not_trimmed(world):
    # Whole-file snapshot: tail-limiting is the store's job, not this helper's.
    big = "".join("line %d of captured output\n" % i for i in range(5000))
    envelope = {"ok": True, "data": dict(LOGS_DATA, stdout=big)}
    set_logs(world, envelope)
    code, out = run(world)
    assert code == 0
    assert out["data"]["stdout"] == big
    assert len(out["data"]["stdout"].splitlines()) == 5000


def test_control_and_unicode_text_round_trips(world):
    text = "a\nb\r\n\x1b[31mred\x1b[0m\tcafé ✓ 日本\n"
    envelope = {"ok": True, "data": dict(LOGS_DATA, stdout=text, stderr=text)}
    set_logs(world, envelope)
    code, out = run(world)  # still exactly one line
    assert code == 0
    assert out == envelope


def test_am_does_not_inherit_stdin(world):
    # The helper's stdin is an open pipe that never sends EOF. An am that reads
    # stdin must get EOF at once (stdin is /dev/null), not block on that pipe.
    write_exec(world["bin"] / "am",
               "#!/usr/bin/env python3\nimport json, sys\nsys.stdin.read()\n"
               "print(json.dumps({'ok': True, 'data': {'stdout': ''}}))\n")
    p = subprocess.Popen([sys.executable, SCRIPT, *ARGS], stdin=subprocess.PIPE,
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
    assert json.loads(lines[0]) == {"ok": True, "data": {"stdout": ""}}


# --- bad output, am missing, usage, catch-all ---------------------------------

@pytest.mark.parametrize("text,exit_code", [
    ("not json\n", 0),
    ("", 1),
    ("Traceback (most recent call last):\n  boom\n", 1),
], ids=["plain-text", "crash-empty", "traceback"])
def test_non_json_output_is_am_bad_output(world, text, exit_code):
    set_raw(world, text, exit_code)
    code, out = run(world)  # run() asserts exactly one JSON line
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "AmBadOutput"
    assert "am logs" in out["error"]["message"]
    # am's exit code is named in the message, so a crash is told from a bad print.
    assert "(exit %d)" % exit_code in out["error"]["message"]


@pytest.mark.parametrize("text", [
    "[1, 2]\n",
    "null\n",
    '"ok"\n',
    '{"data": {"stdout": ""}}\n',
    '{"ok": "true", "data": {}}\n',
    '{"ok": 1, "data": {}}\n',
    '{"ok": null, "data": {}}\n',
], ids=["list", "null", "string", "no-ok", "ok-string", "ok-int", "ok-null"])
def test_non_object_or_no_ok_is_am_bad_output(world, text):
    set_raw(world, text, 0)
    code, out = run(world)
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "AmBadOutput"
    assert "am logs" in out["error"]["message"]
    assert "(exit 0)" in out["error"]["message"]


def test_am_missing(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, out = run(world, PATH=str(empty))
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "AmMissing"
    assert out["error"]["message"]


@pytest.mark.parametrize("args", [["r1", "c1", "implement"],
                                  ["r1", "c1", "implement", "2", "extra"]],
                         ids=["three", "five"])
def test_usage_wrong_argc(world, args):
    code, out = run(world, args)
    assert code == 2
    assert out == {"ok": False, "error": {"type": "Usage",
                                          "message": "usage: runs-logs.py RUN CARD PHASE ATTEMPT"}}
    assert calls(world) == []


def test_am_cannot_start_is_helper_error(world):
    # Executable (so shutil.which finds it) but unstartable: subprocess raises
    # OSError and guarded() must still print exactly one JSON line.
    write_exec(world["bin"] / "am", "#!/nonexistent/interpreter\n")
    code, out = run(world)
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The logs snapshot failed: ")


def load_helper():
    """The script as a module (its name has a hyphen, so no plain import)."""
    spec = importlib.util.spec_from_file_location("runs_logs", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_am_timeout_is_helper_error(world, monkeypatch, capsys):
    # An am that hangs is cut off after AM_TIMEOUT and reported as HelperError
    # (shortened here so the test does not wait the real 60 s).
    write_exec(world["bin"] / "am", "#!/usr/bin/env python3\nimport time\ntime.sleep(10)\n")
    helper = load_helper()
    assert helper.AM_TIMEOUT == 60
    monkeypatch.setattr(helper, "AM_TIMEOUT", 0.5)
    for key, value in env_for(world).items():
        monkeypatch.setenv(key, value)
    code = helper.guarded(list(ARGS))
    lines = capsys.readouterr().out.splitlines()
    assert code == 0
    assert len(lines) == 1, lines
    out = json.loads(lines[0])
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The logs snapshot failed: ")
