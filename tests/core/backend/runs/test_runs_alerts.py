"""runs-alerts.py: `am watch --all --follow --from-now` turned into escalation alerts.

Hermetic: a fake `am` on a temp PATH replays FAKE_AM_DIR/script.json: a list of
steps (a JSON line, raw text, or a sleep), then a chosen stderr text and exit
code. A fake `brd` answers its Nth call from FAKE_BRD_DIR/responses.json (the
last answer repeats). The JSON lines are copies of the committed captures in
tests/fixtures/am/; a line no capture holds, or a capture copy with edited
fields, is labelled `synthetic:`. Both fakes log their argv to calls.log; the
fake am writes its pid to pid. HOME and XDG_* are temp. The real `am`, the real
`brd` and real data are never touched.
"""
import json
import os
import signal
import stat
import subprocess
import sys
import time

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "..")
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "runs-alerts.py")
USAGE = "usage: runs-alerts.py"

FAKE_AM = r'''#!/usr/bin/env python3
import json, os, sys, time
d = os.environ["FAKE_AM_DIR"]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\n")
with open(os.path.join(d, "pid"), "w") as f:
    f.write(str(os.getpid()))
with open(os.path.join(d, "script.json")) as f:
    script = json.load(f)
for step in script["steps"]:
    if "sleep" in step:
        time.sleep(step["sleep"])
        continue
    if "raw" in step:
        sys.stdout.write(step["raw"] + "\n")
    else:
        sys.stdout.write(json.dumps(step["line"], separators=(",", ":")) + "\n")
    sys.stdout.flush()
sys.stderr.write(script.get("stderr", ""))
sys.stderr.flush()
sys.exit(script.get("exit", 0))
'''

FAKE_BRD = r'''#!/usr/bin/env python3
import json, os, sys
d = os.environ["FAKE_BRD_DIR"]
log = os.path.join(d, "calls.log")
n = 0
if os.path.exists(log):
    with open(log) as f:
        n = len(f.read().splitlines())
with open(log, "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\n")
with open(os.path.join(d, "responses.json")) as f:
    answers = json.load(f)
answer = answers[min(n, len(answers) - 1)]
sys.stdout.write(answer.get("stdout", ""))
sys.stdout.flush()
sys.exit(answer.get("exit", 0))
'''

MISSING = object()
FIXTURES = os.path.join(ROOT, "tests", "fixtures", "am")


def fixture(name):
    """A fresh json.load of tests/fixtures/am/<name>, so an edit never reaches
    another call."""
    with open(os.path.join(FIXTURES, name)) as f:
        return json.load(f)


def events():
    """A fresh copy of the captured journal lines, in gseq order."""
    return fixture("watch-events.json")["data"]["events"]


# The run of every captured journal line.
RUN = events()[0]["run_id"]
# The project name of every synthetic `brd projects` entry unless a test says otherwise.
NAME = "omarchy-project-manager"


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def project(root, name=NAME):
    """synthetic: one `brd projects` entry in the shape brd prints."""
    return {"id": 1, "name": name, "root_path": str(root), "created_at": "2026-10-01T00:00:00Z"}


def projects(*entries):
    """synthetic: a successful `brd projects` answer listing `entries`."""
    return {"stdout": json.dumps({"ok": True, "data": list(entries)}) + "\n", "exit": 0}


def set_brd(world, *answers):
    """brd's answers, in call order; the last one repeats."""
    (world["brd"] / "responses.json").write_text(json.dumps(list(answers)))


@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am and a fake brd, their dirs, a temp HOME and an
    existing project dir `repo`, which brd registers unless a test says otherwise."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "am", FAKE_AM)
    write_exec(bindir / "brd", FAKE_BRD)
    amdir = tmp_path / "am"
    amdir.mkdir()
    brddir = tmp_path / "brd"
    brddir.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    repo = tmp_path / "repo"
    repo.mkdir()
    w = {"tmp": tmp_path, "bin": bindir, "am": amdir, "brd": brddir, "home": home,
         "repo": repo}
    set_brd(w, projects(project(repo)))
    return w


def env_for(world, **extra):
    e = {
        "PATH": str(world["bin"]) + os.pathsep + "/usr/bin" + os.pathsep + "/bin",
        "HOME": str(world["home"]),
        "FAKE_AM_DIR": str(world["am"]),
        "FAKE_BRD_DIR": str(world["brd"]),
    }
    for name in ("XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        e[name] = str(world["tmp"] / name.lower())
    e.update(extra)
    return e


def hello(schema=2, **edits):
    """The --follow hello: the captured schema_2 line, or the captured schema_1
    line (no head) for schema=1. synthetic: any other schema value is set on a
    schema_2 copy, MISSING drops the key. synthetic: each of edits is set on
    the copy, MISSING drops the key."""
    lines = fixture("watch-hello.json")
    if type(schema) is int and schema in (1, 2):
        line = lines["schema_%d" % schema]
    else:
        line = lines["schema_2"]
        edits = {"schema": schema, **edits}
    for key, value in edits.items():
        if value is MISSING:
            line.pop(key, None)
        else:
            line[key] = value
    return {"line": line}


def ev(event):
    """The first captured journal line whose event is `event`."""
    return {"line": next(e for e in events() if e["event"] == event)}


def upsert(status, repo_dir=MISSING, run_id=RUN):
    """synthetic: a copy of the captured run_upsert with run_id set, and
    payload.status and payload.repo_dir set to the given values (a path is
    passed as its text); MISSING drops the key."""
    line = ev("run_upsert")["line"]
    line["run_id"] = run_id
    for key, value in (("status", status), ("repo_dir", repo_dir)):
        if value is MISSING:
            line["payload"].pop(key, None)
        else:
            line["payload"][key] = os.fspath(value) if isinstance(value, os.PathLike) else value
    return {"line": line}


def alert(root, run_id=RUN, name=NAME):
    """The helper's alert line for `run_id` under the registered `root`."""
    return {"alert": {"run_id": run_id, "root": str(root), "project": name,
                      "state": "escalated"}}


def pause(seconds):
    return {"sleep": seconds}


def raw(text):
    return {"raw": text}


def set_script(world, steps, exit=0, stderr=""):
    (world["am"] / "script.json").write_text(
        json.dumps({"steps": steps, "exit": exit, "stderr": stderr}))


def run_helper(world, args=(), timeout=30, **extra):
    """Run the helper until it exits. Every stdout line must be JSON. Returns
    (exit code, parsed lines, stderr)."""
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True,
                       env=env_for(world, **extra), timeout=timeout)
    return p.returncode, [json.loads(line) for line in p.stdout.splitlines()], p.stderr


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def brd_calls(world):
    log = world["brd"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def start_helper(world):
    return subprocess.Popen([sys.executable, SCRIPT], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                            env=env_for(world))


def am_pid(world):
    return int((world["am"] / "pid").read_text())


def wait_for_am(world, within=10.0):
    """The fake am's pid, once it has started."""
    end = time.monotonic() + within
    while time.monotonic() < end:
        try:
            return am_pid(world)
        except (FileNotFoundError, ValueError):
            time.sleep(0.05)
    pytest.fail("am watch never started")


def assert_gone(pid, within=5.0):
    """The fake am process no longer exists (no orphaned `am watch`)."""
    end = time.monotonic() + within
    while time.monotonic() < end:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    os.kill(pid, signal.SIGKILL)
    pytest.fail("am watch was left running after the helper exited")


# --- the lines are capture copies -----------------------------------------------

def test_lines_are_capture_copies():
    captured = events()
    assert ev("run_upsert")["line"] == captured[1]
    assert captured[1]["payload"]["status"] == "started"
    assert captured[1]["payload"]["repo_dir"] == "/home/user/Code/omarchy-project-manager"
    assert {e["run_id"] for e in captured} == {RUN}
    assert hello(1) == {"line": fixture("watch-hello.json")["schema_1"]}
    assert "head" not in hello(1)["line"]
    assert hello() == hello(2) == {"line": fixture("watch-hello.json")["schema_2"]}


# --- argv, Usage, am missing ----------------------------------------------------

def test_argv(world):
    set_script(world, [hello()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == []
    # argv list, no shell: the fake am sees exactly these arguments.
    assert calls(world) == [["watch", "--all", "--follow", "--from-now"]]
    assert "--from-now" in calls(world)[0]


@pytest.mark.parametrize("args", [["x"], ["--from-now"], [""], ["/some/root"], ["a", "b"]],
                         ids=["word", "flag", "empty", "root", "two"])
def test_usage(world, args):
    set_script(world, [hello()])
    code, lines, _ = run_helper(world, args)
    assert code == 2
    assert lines == [{"ok": False, "error": {"type": "Usage", "message": USAGE}}]
    assert calls(world) == []  # am never spawned
    assert brd_calls(world) == []  # brd never run


def test_usage_before_am_lookup(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, lines, _ = run_helper(world, ["x"], PATH=str(empty))
    assert code == 2
    assert lines == [{"ok": False, "error": {"type": "Usage", "message": USAGE}}]


def test_am_missing(world):
    only_brd = world["tmp"] / "only-brd"
    only_brd.mkdir()
    write_exec(only_brd / "brd", FAKE_BRD)
    code, lines, _ = run_helper(world, PATH=str(only_brd))
    assert code == 1
    assert lines == [{"ok": False, "error": {"type": "AmMissing",
                                             "message": "am is not installed."}}]
    assert brd_calls(world) == []  # brd is not run when am is missing


# --- the hello line ---------------------------------------------------------------

def test_clean_exit_zero(world):
    set_script(world, [hello(), ev("phase_upsert")])
    code, lines, err = run_helper(world)
    assert code == 0
    assert lines == []
    assert "Traceback" not in err


@pytest.mark.parametrize("schema", [1, 2], ids=["schema-1", "schema-2"])
def test_hello_accepted_prints_nothing(world, schema):
    set_script(world, [hello(schema)])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == []


def assert_schema_mismatch(world, lines, began, received):
    assert time.monotonic() - began < 5
    assert len(lines) == 1, lines
    assert lines[0]["ok"] is False, lines
    assert lines[0]["error"]["type"] == "SchemaMismatch", lines
    assert lines[0]["error"]["message"] == (
        "am watch speaks schema " + received + "; this helper reads schema 1 or 2.")
    assert_gone(am_pid(world))  # am was terminated, not left streaming


@pytest.mark.parametrize("schema", [3, MISSING, "2", True],
                         ids=["synthetic: three", "synthetic: missing",
                              "synthetic: string-two", "synthetic: true"])
def test_schema_mismatch(world, schema):
    set_script(world, [hello(schema), pause(8)])
    began = time.monotonic()
    code, lines, _ = run_helper(world)
    assert code == 1
    assert_schema_mismatch(world, lines, began,
                           json.dumps(None if schema is MISSING else schema))


def test_second_hello_is_checked(world):
    set_script(world, [hello(2), hello(3), pause(8)])
    began = time.monotonic()
    code, lines, _ = run_helper(world)
    assert code == 1
    assert_schema_mismatch(world, lines, began, "3")


# --- how am ends -------------------------------------------------------------------

def test_exit_3_corrupt_journal(world):
    # synthetic: am's stderr text for a corrupt journal.
    set_script(world, [hello()], exit=3,
               stderr="am watch: journal line 4 of run r1 is not JSON\n")
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [{"ok": False, "error": {
        "type": "CorruptJournal",
        "message": "am watch: journal line 4 of run r1 is not JSON"}}]


def test_exit_3_without_stderr(world):
    set_script(world, [hello()], exit=3)
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [{"ok": False, "error": {"type": "CorruptJournal",
                                             "message": "am watch exited 3."}}]


def test_refusal_exit_3_is_corrupt_journal(world):
    # synthetic: an am refusal envelope; no capture holds one.
    envelope = {"error": {"message": "run r1: journal line 2 is not JSON",
                          "type": "CorruptJournalError"}, "ok": False}
    set_script(world, [{"line": envelope}], exit=3, stderr="ignored\n")
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [{"ok": False, "error": {"type": "CorruptJournal",
                                             "message": "run r1: journal line 2 is not JSON"}}]


def test_refusal_exit_3_empty_message_uses_stderr(world):
    # synthetic: an am refusal envelope with an empty message.
    envelope = {"error": {"message": "", "type": "CorruptJournalError"}, "ok": False}
    set_script(world, [{"line": envelope}], exit=3, stderr="bad journal\n")
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [{"ok": False, "error": {"type": "CorruptJournal",
                                             "message": "bad journal"}}]


# synthetic: am's StoreBusyError envelope; no capture holds one.
STORE_BUSY = {"error": {"message": "the am store is busy; try again",
                        "type": "StoreBusyError"}, "ok": False}


def test_refusal_store_busy_is_reemitted(world):
    set_script(world, [hello(), {"line": STORE_BUSY}], exit=3)
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [STORE_BUSY]


def test_other_exit_is_helper_error(world):
    # synthetic: am's stderr text for a crash.
    set_script(world, [hello()], exit=2, stderr="boom\n")
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [{"ok": False, "error": {"type": "HelperError", "message": "boom"}}]


def test_other_exit_without_stderr(world):
    set_script(world, [hello()], exit=2)
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [{"ok": False, "error": {"type": "HelperError",
                                             "message": "am watch exited 2."}}]


@pytest.mark.parametrize("exit", [0, 1], ids=["exit-0", "exit-1"])
def test_refusal_other_exit_is_reemitted(world, exit):
    # synthetic: an am refusal envelope; no capture holds one.
    envelope = {"error": {"message": "something else", "type": "OddError"}, "ok": False}
    set_script(world, [hello(), {"line": envelope}], exit=exit)
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [envelope]


# --- stopping: signals -------------------------------------------------------------

@pytest.mark.parametrize("sig", [signal.SIGTERM, signal.SIGINT], ids=["SIGTERM", "SIGINT"])
def test_signal_stops_am_and_exits_zero(world, sig):
    set_script(world, [hello(), pause(30)])
    p = start_helper(world)
    try:
        pid = wait_for_am(world)  # sync point: the helper has spawned am
        p.send_signal(sig)
        code = p.wait(timeout=10)
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
    out = p.stdout.read()
    err = p.stderr.read()
    p.stdout.close()
    p.stderr.close()
    assert code == 0, err
    assert out == ""  # no envelope
    assert "Traceback" not in err
    assert_gone(pid)
