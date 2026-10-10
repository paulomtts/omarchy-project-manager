"""runs-logs.py: an `am logs` passthrough for one attempt, one JSON line on every path.

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

RUN_ARGS = ["r1", "c1", "implement", "2"]
FIXTURES = os.path.join(ROOT, "tests", "fixtures", "am")
# synthetic: am's error envelope for an unknown run; no capture holds one.
UNKNOWN_RUN = {"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}

# The fake am, plus real am's resolution rule: it answers UnknownRunError (exit 3)
# unless the value after --repo-dir is FAKE_AM_REPO. It still logs every call.
REPO_CHECK = '''repo = args[args.index("--repo-dir") + 1] if "--repo-dir" in args[:-1] else None
if repo != os.environ["FAKE_AM_REPO"]:
    sys.stdout.write(json.dumps({"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}) + "\\n")
    sys.exit(3)
'''
REPO_CHECKING_AM = FAKE_AM.replace('name = "logs"', REPO_CHECK + 'name = "logs"', 1)
assert REPO_CHECKING_AM != FAKE_AM


def fixture(name):
    """A fresh json.load of tests/fixtures/am/<name>, so an edit never reaches
    another call."""
    with open(os.path.join(FIXTURES, name)) as f:
        return json.load(f)


def logs_data():
    """The captured `am logs` data of one attempt. Opaque to the helper: it must
    pass whatever `data` am prints through untouched."""
    return fixture("logs-attempt.json")["data"]


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


def default_args(world):
    """The helper's argv for one attempt of the world's project."""
    return [str(world["proj"]), *RUN_ARGS]


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


def run(world, args=None, drop=(), cwd=None, **extra):
    """Run the helper (in `cwd` when given); assert stdout is exactly one JSON line;
    return (exit, payload)."""
    argv = default_args(world) if args is None else args
    p = subprocess.run([sys.executable, SCRIPT, *argv], capture_output=True, text=True,
                       env=env_for(world, drop, **extra), cwd=cwd, timeout=60)
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

def test_logs_data_is_the_capture():
    assert logs_data() == fixture("logs-attempt.json")["data"]
    # The capture's top-level `_note` is an annotation, not part of am's envelope.
    assert {"ok": True, "data": logs_data()} == \
        {k: v for k, v in fixture("logs-attempt.json").items() if not k.startswith("_")}
    # Each call is a fresh copy: an edit to one never reaches the next.
    first = logs_data()
    first["artifacts"]["stdout"]["text"] = "edited"
    assert logs_data() == fixture("logs-attempt.json")["data"]


def test_ok_envelope_passed_through(world):
    envelope = {"ok": True, "data": logs_data()}
    set_logs(world, envelope)
    code, out = run(world)  # run() asserts stdout is exactly one JSON line
    assert code == 0
    assert out == envelope


def test_exact_am_argv(world):
    # The project dir is named "my proj; echo x": it must arrive as one argv element.
    set_logs(world, {"ok": True, "data": logs_data()})
    code, _ = run(world)
    assert code == 0
    made = calls(world)
    assert made == [["logs", "r1", "c1", "--phase", "implement", "--attempt", "2",
                     "--repo-dir", str(world["proj"])]]
    assert "--pretty" not in made[0]


# --- attempt 0: the phase's newest output ------------------------------------

@pytest.mark.parametrize("phase", ["verify", "implement"])
def test_attempt_zero_sends_no_attempt_flag(world, phase):
    # Attempt 0 means "no --attempt": am returns the phase's newest recorded output,
    # the only way to read a step, which records no attempts in `am status`.
    proj = str(world["proj"])
    envelope = {"ok": True, "data": logs_data()}
    set_logs(world, envelope)
    code, out = run(world, [proj, "r1", "c1", phase, "0"])
    assert code == 0
    assert out == envelope
    made = calls(world)
    assert made == [["logs", "r1", "c1", "--phase", phase, "--repo-dir", proj]]
    assert "--attempt" not in made[0]
    assert "0" not in made[0]


@pytest.mark.parametrize("attempt", ["2", "1"])
def test_nonzero_attempt_is_sent_verbatim(world, attempt):
    proj = str(world["proj"])
    set_logs(world, {"ok": True, "data": logs_data()})
    code, _ = run(world, [proj, "r1", "c1", "verify", attempt])
    assert code == 0
    assert calls(world) == [["logs", "r1", "c1", "--phase", "verify", "--attempt", attempt,
                             "--repo-dir", proj]]


@pytest.mark.parametrize("attempt", ["00", "-0", " 0", "", "+0", "0 ", "0\n"],
                         ids=["double-zero", "minus-zero", "leading-space", "empty",
                              "plus-zero", "trailing-space", "trailing-newline"])
def test_only_exact_zero_is_special(world, attempt):
    # Only the exact string "0" drops --attempt: the helper parses no integers and
    # strips nothing, so am refuses these itself.
    proj = str(world["proj"])
    set_logs(world, {"ok": True, "data": logs_data()})
    code, _ = run(world, [proj, "r1", "c1", "verify", attempt])
    assert code == 0
    assert calls(world) == [["logs", "r1", "c1", "--phase", "verify", "--attempt", attempt,
                             "--repo-dir", proj]]


def test_attempt_zero_refusal_passed_through(world):
    proj = str(world["proj"])
    # synthetic: am's refusal when the phase has no recorded output; no capture holds one.
    refusal = {"ok": False, "error": {"type": "NotFoundError",
                                      "message": "no output recorded for phase verify"}}
    set_logs(world, refusal, code=3)
    code, out = run(world, [proj, "r1", "c1", "verify", "0"])
    assert code == 0
    assert out == refusal
    assert calls(world) == [["logs", "r1", "c1", "--phase", "verify", "--repo-dir", proj]]


def test_attempt_zero_bad_output_is_am_bad_output(world):
    # synthetic: am output that is not JSON.
    set_raw(world, "not json\n", 1)
    code, out = run(world, [str(world["proj"]), "r1", "c1", "verify", "0"])
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "AmBadOutput"
    assert "am logs" in out["error"]["message"]
    assert "(exit 1)" in out["error"]["message"]


def test_args_reach_am_verbatim(world):
    # Spaces, shell metacharacters and a leading dash must each arrive as one argv
    # element: no shell, no validation by the helper. The root does not exist.
    root = str(world["tmp"] / "r$(id) & z")
    args = [root, "r 1; echo x", "c$(whoami)", "plan & review", "-1"]
    set_logs(world, {"ok": True, "data": logs_data()})
    code, _ = run(world, args)
    assert code == 0
    assert calls(world) == [["logs", "r 1; echo x", "c$(whoami)",
                             "--phase", "plan & review", "--attempt", "-1",
                             "--repo-dir", root]]


@pytest.mark.parametrize("root", [".", "/some/proj/", "", "-proj"],
                         ids=["relative-dot", "trailing-slash", "empty", "leading-dash"])
def test_root_reaches_am_unnormalised(world, root):
    # The root is neither resolved, stripped nor checked: am refuses a bad one itself.
    set_logs(world, {"ok": True, "data": logs_data()})
    code, _ = run(world, [root, *RUN_ARGS])
    assert code == 0
    assert calls(world) == [["logs", "r1", "c1", "--phase", "implement", "--attempt", "2",
                             "--repo-dir", root]]


def test_root_that_is_a_file_is_left_to_am(world):
    root = world["tmp"] / "not-a-dir"
    root.write_text("")
    # synthetic: am's refusal of a repo dir that is not a directory; no capture holds one.
    refusal = {"ok": False, "error": {"type": "UsageError",
                                      "message": "--repo-dir is not a directory"}}
    set_logs(world, refusal, code=3)
    code, out = run(world, [str(root), *RUN_ARGS])
    assert code == 0
    assert out == refusal
    assert calls(world) == [["logs", "r1", "c1", "--phase", "implement", "--attempt", "2",
                             "--repo-dir", str(root)]]


def test_pretty_printed_am_output_becomes_one_line(world):
    envelope = {"ok": True, "data": logs_data()}
    set_raw(world, json.dumps(envelope, indent=2) + "\n")
    code, out = run(world)  # run() asserts exactly one line
    assert code == 0
    assert out == envelope


def test_refusal_passed_through_exit_0(world):
    # synthetic: an am refusal envelope; no capture holds one.
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
    assert calls(world) == [["logs", "r1", "c1", "--phase", "implement", "--attempt", "2",
                             "--repo-dir", str(world["proj"])]]


def test_ok_wins_over_am_exit_code_and_stderr(world):
    # The envelope's `ok` decides, not am's exit code; am's stderr never reaches
    # the helper's stdout line.
    envelope = {"ok": True, "data": logs_data()}
    # synthetic: am stderr noise.
    set_raw(world, json.dumps(envelope) + "\n", code=3, stderr="warning: noisy\nmore noise\n")
    code, out = run(world)
    assert code == 0
    assert out == envelope


def test_large_output_not_trimmed(world):
    # Whole-file snapshot: tail-limiting is the store's job, not this helper's.
    # synthetic: an attempt output longer than any capture.
    big = "".join("line %d of captured output\n" % i for i in range(5000))
    data = logs_data()
    data["artifacts"]["stdout"]["text"] = big
    envelope = {"ok": True, "data": data}
    set_logs(world, envelope)
    code, out = run(world)
    assert code == 0
    assert out["data"]["artifacts"]["stdout"]["text"] == big
    assert len(out["data"]["artifacts"]["stdout"]["text"].splitlines()) == 5000


def test_control_and_unicode_text_round_trips(world):
    # synthetic: control and non-ASCII text in an attempt's stdout and stderr.
    text = "a\nb\r\n\x1b[31mred\x1b[0m\tcafé ✓ 日本\n"
    data = logs_data()
    data["artifacts"]["stdout"]["text"] = text
    data["artifacts"]["stderr"]["text"] = text
    envelope = {"ok": True, "data": data}
    set_logs(world, envelope)
    code, out = run(world)  # still exactly one line
    assert code == 0
    assert out == envelope


def test_am_does_not_inherit_stdin(world):
    # The helper's stdin is an open pipe that never sends EOF. An am that reads
    # stdin must get EOF at once (stdin is /dev/null), not block on that pipe.
    envelope = {"ok": True, "data": logs_data()}
    set_logs(world, envelope)
    write_exec(world["bin"] / "am",
               "#!/usr/bin/env python3\nimport os, sys\nsys.stdin.read()\n"
               "sys.stdout.write(open(os.path.join(os.environ['FAKE_AM_DIR'], 'logs.out')).read())\n")
    p = subprocess.Popen([sys.executable, SCRIPT, *default_args(world)], stdin=subprocess.PIPE,
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
    assert json.loads(lines[0]) == envelope


# --- a step, and the repository decides -----------------------------------------

def test_attempt_0_omits_attempt(world):
    envelope = {"ok": True, "data": logs_data()}
    set_logs(world, envelope)
    proj = str(world["proj"])
    code, out = run(world, [proj, "r1", "c1", "verify", "0"])
    assert code == 0
    assert out == envelope
    made = calls(world)
    assert made == [["logs", "r1", "c1", "--phase", "verify", "--repo-dir", proj]]
    assert "--attempt" not in made[0]


@pytest.mark.parametrize("attempt", ["00", " 0", ""], ids=["double-zero", "space-zero", "empty"])
def test_only_the_literal_0_is_a_step(world, attempt):
    # The helper never parses ATTEMPT: anything but the string "0" goes to am as is.
    set_logs(world, {"ok": True, "data": logs_data()})
    proj = str(world["proj"])
    code, _ = run(world, [proj, "r1", "c1", "verify", attempt])
    assert code == 0
    assert calls(world) == [["logs", "r1", "c1", "--phase", "verify", "--attempt", attempt,
                             "--repo-dir", proj]]


def test_a_step_refusal_passes_through(world):
    # synthetic: am's refusal of a step that records no log yet; no capture holds one.
    refusal = {"ok": False, "error": {"type": "UnknownAttemptError",
                                      "message": "phase 'worktree' has no recorded attempt yet"}}
    set_logs(world, refusal, code=3)
    proj = str(world["proj"])
    code, out = run(world, [proj, "r1", "c1", "worktree", "0"])
    assert code == 0
    assert out == refusal
    assert calls(world) == [["logs", "r1", "c1", "--phase", "worktree", "--repo-dir", proj]]


@pytest.mark.parametrize("attempt", ["2", "0"], ids=["attempt", "step"])
@pytest.mark.parametrize("where", ["elsewhere", "root"])
def test_a_cwd_outside_the_repo_still_reaches_it(world, attempt, where):
    # am resolves the run against --repo-dir only; the helper's cwd never matters.
    write_exec(world["bin"] / "am", REPO_CHECKING_AM)
    envelope = {"ok": True, "data": logs_data()}
    set_logs(world, envelope)
    proj = str(world["proj"])
    if where == "elsewhere":
        cwd = world["tmp"] / "elsewhere"
        cwd.mkdir()
    else:
        cwd = "/"
    assert str(cwd) != proj
    code, out = run(world, [proj, "r1", "c1", "implement", attempt], cwd=str(cwd),
                    FAKE_AM_REPO=proj)
    assert code == 0
    assert out == envelope
    made = calls(world)
    assert len(made) == 1
    assert made[0][-2:] == ["--repo-dir", proj]
    assert ("--attempt" in made[0]) == (attempt != "0")


def test_the_repo_checking_am_refuses_another_repo(world):
    # The check above is real: a --repo-dir other than FAKE_AM_REPO is an unknown run.
    write_exec(world["bin"] / "am", REPO_CHECKING_AM)
    set_logs(world, {"ok": True, "data": logs_data()})
    code, out = run(world, FAKE_AM_REPO=str(world["tmp"] / "other"))
    assert code == 0
    assert out == UNKNOWN_RUN


# --- bad output, am missing, usage, catch-all ---------------------------------

# synthetic: am output that is not JSON.
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


# synthetic: am JSON that is not an object or has no boolean ok.
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


@pytest.mark.parametrize("shape", ["none", "old-four", "four-with-root", "six"])
def test_usage_wrong_argc(world, shape):
    proj = str(world["proj"])
    args = {
        "none": [],
        "old-four": ["r1", "c1", "implement", "2"],
        "four-with-root": [proj, "r1", "c1", "implement"],
        "six": [proj, "r1", "c1", "implement", "2", "extra"],
    }[shape]
    code, out = run(world, args)
    assert code == 2
    assert out == {"ok": False, "error": {
        "type": "Usage",
        "message": "usage: runs-logs.py <project_root> RUN CARD PHASE ATTEMPT"}}
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
    code = helper.guarded(default_args(world))
    lines = capsys.readouterr().out.splitlines()
    assert code == 0
    assert len(lines) == 1, lines
    out = json.loads(lines[0])
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The logs snapshot failed: ")
