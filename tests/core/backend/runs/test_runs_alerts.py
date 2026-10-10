"""runs-alerts.py: escalation alerts from `am watch --all --follow --from-now` and
dead alerts from `am runs --repo-dir R`.

Hermetic: a fake `am` on a temp PATH. For `am runs` it answers from
FAKE_AM_DIR/runs.json: per --repo-dir value a list of answers ({stdout, exit},
optional sleep before answering), the Nth call for a root getting the Nth answer
(the last repeats), any other root the "default" answer; it writes its pid to
runs.pid. For every other argv (`am watch`) it replays FAKE_AM_DIR/script.json:
a list of steps (a JSON line, raw text, or a sleep), then a chosen stderr text
and exit code, and writes its pid to pid. A fake `brd` answers its Nth call from
FAKE_BRD_DIR/responses.json (the last answer repeats). The JSON lines are copies
of the committed captures in tests/fixtures/am/; a line no capture holds, or a
capture copy with edited fields, is labelled `synthetic:`. Both fakes log their
argv to calls.log. HOME and XDG_* are temp. The real `am`, the real `brd` and
real data are never touched. The in-process tests load the module with
importlib and drive `Tracker` with an injected clock; am is still the fake.
"""
import importlib.util
import json
import os
import queue
import signal
import stat
import subprocess
import sys
import threading
import time

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "..")
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "runs-alerts.py")
USAGE = "usage: runs-alerts.py"

FAKE_AM = r'''#!/usr/bin/env python3
import json, os, sys, time
d = os.environ["FAKE_AM_DIR"]
argv = sys.argv[1:]
log = os.path.join(d, "calls.log")
before = []
if os.path.exists(log):
    with open(log) as f:
        before = f.read().splitlines()
with open(log, "a") as f:
    f.write(json.dumps(argv) + "\n")
if argv[:1] == ["runs"]:
    with open(os.path.join(d, "runs.pid"), "w") as f:
        f.write(str(os.getpid()))
    with open(os.path.join(d, "runs.json")) as f:
        table = json.load(f)
    root = argv[argv.index("--repo-dir") + 1] if "--repo-dir" in argv else None
    answers = table["answers"].get(root) or [table["default"]]
    answer = answers[min(before.count(json.dumps(argv)), len(answers) - 1)]
    time.sleep(answer.get("sleep", 0))
    sys.stdout.buffer.write(answer.get("stdout", "").encode("utf-8", "surrogateescape"))
    sys.stdout.flush()
    sys.exit(answer.get("exit", 0))
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


# The captured started run (row 0 of tests/fixtures/am/runs.json).
RUN_A = fixture("runs.json")["data"]["runs"][0]["id"]
RUN_B = "20261008T150000Z-0000000b"  # synthetic: a second run id
LIVE = object()


def row(run_id=RUN_A, status="started", lease=LIVE):
    """A copy of captured row 0 (started, lease live) with id set. synthetic:
    when run_id, status or lease is edited; MISSING drops lease, LIVE keeps the
    capture's live lease."""
    r = fixture("runs.json")["data"]["runs"][0]
    r["id"] = run_id
    r["status"] = status
    if lease is MISSING:
        r.pop("lease")
    elif lease is not LIVE:
        r["lease"] = lease
    return r


def done_row():
    """Captured row 1: done, lease null."""
    return fixture("runs.json")["data"]["runs"][1]


def runs_reply(*rows):
    """An `am runs` answer: the captured envelope (without the capture's _note)
    whose runs are `rows`."""
    reply = fixture("runs.json")
    reply.pop("_note")
    reply["data"]["runs"] = list(rows)
    return {"stdout": json.dumps(reply) + "\n", "exit": 0}


# synthetic: `am runs` answers that are failed reads.
RUNS_FAILURES = {
    "ok-false": {"stdout": json.dumps({"ok": False, "error": {
        "type": "StoreBusyError", "message": "the am store is busy; try again"}}) + "\n",
        "exit": 1},
    "not-json": {"stdout": "not json\n", "exit": 0},
    "no-runs": {"stdout": json.dumps({"ok": True, "data": {"as_of_seq": 1}}) + "\n",
                "exit": 0},
    "row-without-id": runs_reply({"status": "started", "lease": {"live": True}}),
    "undecodable": {"stdout": "\udcff\n", "exit": 0},
}


def set_runs(world, answers=None):
    """`am runs` answers per --repo-dir value (a path is keyed by its text), in
    call order, the last repeating; any other root gets runs_reply()."""
    table = {str(root): list(replies) for root, replies in (answers or {}).items()}
    (world["am"] / "runs.json").write_text(
        json.dumps({"answers": table, "default": runs_reply()}))


@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am and a fake brd, their dirs, a temp HOME and an
    existing project dir `repo`, which brd registers unless a test says otherwise.
    Every `am runs` answers with an empty run list unless a test says otherwise."""
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
    set_runs(w)
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


def dead(root, run_id=RUN_A, name=NAME):
    """The helper's dead alert line for `run_id` under the registered `root`."""
    return {"alert": {"run_id": run_id, "root": str(root), "project": name,
                      "state": "dead"}}


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


def am_path(world):
    return str(world["bin"] / "am")


def runs_calls(world):
    """The fake am's `am runs` argv lists, in call order."""
    return [c for c in calls(world) if c[:1] == ["runs"]]


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

WATCH = ["watch", "--all", "--follow", "--from-now"]


def test_argv(world):
    set_script(world, [hello()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == []
    # argv lists, no shell: the fake am sees exactly these arguments.
    assert calls(world) == [["runs", "--repo-dir", str(world["repo"])], WATCH]


def test_argv_empty_registry(world):
    set_brd(world, projects())
    set_script(world, [hello()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == []
    assert calls(world) == [WATCH]


def test_seed_argv_order(world):
    real1 = world["tmp"] / "real1"
    real1.mkdir()
    r1 = world["tmp"] / "r1"
    r1.symlink_to(real1)
    r2 = world["tmp"] / "r2"
    r2.mkdir()
    set_brd(world, projects(project(r1, name="one"), project(r2, name="two")))
    set_script(world, [hello()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == []
    # once per root, brd's order, the root as brd printed it (the link), before the watch.
    assert calls(world) == [["runs", "--repo-dir", str(r1)],
                            ["runs", "--repo-dir", str(r2)], WATCH]


def test_seed_never_alerts(world):
    set_runs(world, {world["repo"]: [runs_reply(row(lease=None), row(RUN_B))]})
    set_script(world, [hello()])
    code, lines, err = run_helper(world)
    assert code == 0, err
    assert lines == []


@pytest.mark.parametrize("failure", ["ok-false", "not-json", "no-runs"])
def test_failed_seed_of_one_root(world, failure):
    r1, r2 = world["tmp"] / "r1", world["tmp"] / "r2"
    r1.mkdir()
    r2.mkdir()
    set_brd(world, projects(project(r1, name="one"), project(r2, name="two")))
    set_runs(world, {r1: [RUNS_FAILURES[failure]], r2: [runs_reply(row(RUN_B))]})
    set_script(world, [hello(), upsert("escalated", r2, run_id=RUN_B)])
    code, lines, err = run_helper(world)
    assert code == 0, err
    assert "Traceback" not in err
    assert lines == [alert(r2, run_id=RUN_B, name="two")]
    assert calls(world) == [["runs", "--repo-dir", str(r1)],
                            ["runs", "--repo-dir", str(r2)], WATCH]


def test_no_poll_when_idle_subprocess(world):
    set_script(world, [hello(), pause(2)])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == []
    assert calls(world) == [["runs", "--repo-dir", str(world["repo"])], WATCH]


def wait_for_runs(world, within=10.0):
    """The pid of the fake am's latest `am runs`, once one has started."""
    end = time.monotonic() + within
    while time.monotonic() < end:
        try:
            return int((world["am"] / "runs.pid").read_text())
        except (FileNotFoundError, ValueError):
            time.sleep(0.05)
    pytest.fail("am runs never started")


@pytest.mark.parametrize("sig", [signal.SIGTERM, signal.SIGINT], ids=["SIGTERM", "SIGINT"])
def test_signal_during_seed_leaves_no_am(world, sig):
    set_runs(world, {world["repo"]: [{**runs_reply(row()), "sleep": 30}]})
    set_script(world, [hello()])
    p = start_helper(world)
    try:
        pid = wait_for_runs(world)  # sync point: the seed read is running
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
    assert out == ""
    assert "Traceback" not in err
    assert_gone(pid)
    assert calls(world) == [["runs", "--repo-dir", str(world["repo"])]]  # no watch spawned


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


# --- the alert ---------------------------------------------------------------------

def test_no_backlog_alert(world):
    # synthetic: an escalated upsert before the hello is ignored, state and all.
    set_script(world, [upsert("escalated", world["repo"]), hello(),
                       upsert("escalated", world["repo"])])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"])]


@pytest.mark.parametrize("schema", [1, 2], ids=["schema-1", "schema-2"])
def test_hello_accepted_then_alert(world, schema):
    set_script(world, [hello(schema), upsert("escalated", world["repo"])])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"])]


def test_alert_line_shape_and_realpath_match(world):
    real_dir = world["tmp"] / "real"
    real_dir.mkdir()
    link = world["tmp"] / "link"
    link.symlink_to(real_dir)
    set_brd(world, projects(project(link, name="proj")))
    # synthetic: the run's repo_dir is the real directory, brd printed the link.
    set_script(world, [hello(), upsert("escalated", real_dir)])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [{"alert": {"run_id": RUN, "root": str(link), "project": "proj",
                                "state": "escalated"}}]
    assert list(lines[0]) == ["alert"]
    assert list(lines[0]["alert"]) == ["run_id", "root", "project", "state"]


def test_no_duplicate(world):
    set_script(world, [hello()] + [upsert("escalated", world["repo"])] * 3)
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"])]


def test_re_alert_after_resume(world):
    set_script(world, [hello(), upsert("escalated", world["repo"]),
                       upsert("started", world["repo"]), upsert("escalated", world["repo"])])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"])] * 2


def test_repo_dir_carried(world):
    set_script(world, [hello(), upsert("started", world["repo"]), upsert("escalated")])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"])]


def test_no_repo_dir_no_alert(world):
    set_script(world, [hello(), upsert("escalated"), upsert("escalated", "")])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == []
    assert brd_calls(world) == [["projects"]]


# --- the registry ------------------------------------------------------------------

def test_unregistered_is_ignored(world):
    set_script(world, [hello(), upsert("escalated", world["tmp"] / "elsewhere")])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == []
    assert brd_calls(world) == [["projects"], ["projects"]]  # start + one re-read


def test_root_learned(world):
    set_brd(world, projects(), projects(project(world["repo"])))
    set_script(world, [hello(), upsert("escalated", world["repo"])])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"])]
    assert brd_calls(world) == [["projects"], ["projects"]]


def test_registered_root_does_not_re_read(world):
    set_script(world, [hello(),
                       upsert("started", world["tmp"] / "a"),
                       upsert("started", world["tmp"] / "b", run_id="r2"),
                       upsert("escalated", world["repo"])])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"])]
    assert brd_calls(world) == [["projects"]]


BRD_FAILURES = ["missing", "exit-1", "garbage", "ok-false", "data-not-list"]


@pytest.mark.parametrize("failure", BRD_FAILURES)
def test_brd_failing_at_start(world, failure):
    registering = projects(project(world["repo"]))["stdout"]
    answers = {
        "exit-1": {"stdout": registering, "exit": 1},
        "garbage": {"stdout": "not json\n", "exit": 0},
        # synthetic: brd refusal envelope.
        "ok-false": {"stdout": json.dumps({"ok": False, "error": {"type": "X",
                                                                   "message": "no"}}) + "\n"},
        "data-not-list": {"stdout": json.dumps({"ok": True, "data": {}}) + "\n"},
    }
    if failure == "missing":
        os.unlink(world["bin"] / "brd")
    else:
        set_brd(world, answers[failure])
    set_script(world, [hello(), upsert("escalated", world["repo"])])
    code, lines, err = run_helper(world)
    assert code == 0, err
    assert lines == []
    assert "Traceback" not in err
    assert brd_calls(world) == ([] if failure == "missing" else [["projects"], ["projects"]])


def test_failed_re_read_keeps_registry(world):
    set_brd(world, projects(project(world["repo"])), {"stdout": "", "exit": 1})
    set_script(world, [hello(),
                       upsert("escalated", world["tmp"] / "elsewhere"),
                       upsert("escalated", world["repo"], run_id="r2")])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"], run_id="r2")]
    assert brd_calls(world) == [["projects"], ["projects"]]


# --- review focus ------------------------------------------------------------------

def test_non_string_status_keeps_last_status(world):
    set_script(world, [hello(), upsert("escalated", world["repo"]),
                       upsert(None, world["repo"]), upsert("escalated", world["repo"])])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"])]


def test_repo_dir_with_nul_is_ignored(world):
    # synthetic: a repo_dir realpath cannot take.
    set_script(world, [hello(), upsert("escalated", str(world["repo"]) + "\u0000x"),
                       upsert("escalated", world["repo"], run_id="r2")])
    code, lines, err = run_helper(world)
    assert code == 0, err
    assert lines == [alert(world["repo"], run_id="r2")]
    assert brd_calls(world) == [["projects"]]  # no re-read for the NUL path


def test_bad_registry_entries_are_skipped(world):
    good = project(world["repo"], name="good")
    nameless = project(world["tmp"] / "nameless")
    del nameless["name"]
    set_brd(world, projects("not an object", project(str(world["tmp"]) + "\u0000x"),
                            {**project(""), "root_path": ""}, nameless,
                            {**project(world["tmp"] / "n"), "root_path": 5}, good))
    set_script(world, [hello(), upsert("escalated", world["repo"])])
    code, lines, err = run_helper(world)
    assert code == 0, err
    assert lines == [alert(world["repo"], name="good")]


def test_first_registry_entry_wins(world):
    link = world["tmp"] / "link"
    link.symlink_to(world["repo"])
    set_brd(world, projects(project(link, name="first"), project(world["repo"], name="second")))
    set_script(world, [hello(), upsert("escalated", world["repo"])])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(link, name="first")]


def test_runs_are_tracked_separately(world):
    set_script(world, [hello(),
                       upsert("escalated", world["repo"], run_id="r1"),
                       upsert("escalated", world["repo"], run_id="r2"),
                       upsert("escalated", world["repo"], run_id="r1"),
                       upsert("escalated", world["repo"], run_id="r2")])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"], run_id="r1"), alert(world["repo"], run_id="r2")]


# --- ignored lines -----------------------------------------------------------------

def test_ignored_lines(world):
    empty_run = upsert("escalated", world["repo"], run_id="")
    bad_payload = upsert("escalated", world["repo"])
    bad_payload["line"]["payload"] = "escalated"
    # synthetic: another event kind carrying an escalated status and a repo_dir.
    phase = ev("phase_upsert")
    phase["line"]["payload"] = {"status": "escalated", "repo_dir": str(world["repo"])}
    set_script(world, [hello(), raw("not json"), raw("[1, 2]"), raw('"text"'), empty_run,
                       bad_payload, phase, upsert("escalated", world["repo"])])
    code, lines, err = run_helper(world)
    assert code == 0, err
    assert "Traceback" not in err
    assert lines == [alert(world["repo"])]
    assert brd_calls(world) == [["projects"]]


# --- flushing and a closed stdout --------------------------------------------------

def test_alert_flushed_at_once(world):
    set_script(world, [hello(), upsert("escalated", world["repo"]), pause(30)])
    p = start_helper(world)
    try:
        began = time.monotonic()
        line = p.stdout.readline()
        assert time.monotonic() - began < 10  # read while am still runs
        assert json.loads(line) == alert(world["repo"])
        pid = am_pid(world)
        p.send_signal(signal.SIGTERM)
        code = p.wait(timeout=10)
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
    p.stdout.close()
    p.stderr.close()
    assert code == 0
    assert_gone(pid)


def test_closed_stdout_exits_zero(world):
    set_script(world, [hello(), pause(0.6), upsert("escalated", world["repo"]), pause(30)])
    p = start_helper(world)
    p.stdout.close()  # the reader goes away before the alert
    try:
        code = p.wait(timeout=10)
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
    err = p.stderr.read()
    p.stderr.close()
    assert code == 0, err
    assert "Traceback" not in err
    assert_gone(am_pid(world))


# --- in-process: the Tracker with an injected clock ----------------------------------

def load_module():
    """Import the helper in-process (its file name is not a Python identifier)."""
    spec = importlib.util.spec_from_file_location("runs_alerts", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Clock:
    """The injected clock: returns `now`, which only the test moves."""

    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now


@pytest.fixture
def mod(world, monkeypatch):
    """The helper module, loaded in-process with the fake am and brd on PATH."""
    for name, value in env_for(world).items():
        monkeypatch.setenv(name, value)
    return load_module()


def registry(*entries):
    """A registry as read_registry builds it: realpath(root) -> (root text, name)."""
    return {os.path.realpath(str(root)): (str(root), name) for root, name in entries}


def printed(capsys):
    """The JSON lines printed since the last call."""
    return [json.loads(line) for line in capsys.readouterr().out.splitlines()]


def at(clock, tracker, now):
    """Move the clock to `now` and give the tracker its "poll if due" call."""
    clock.now = now
    tracker.poll_if_due()


def seeded(mod, world, *answers):
    """A Tracker on the fake am and a Clock at 0, seeded from a registry of
    `repo` alone whose `am runs` answers are `answers`."""
    set_runs(world, {world["repo"]: answers})
    clock = Clock()
    tracker = mod.Tracker(am_path(world), clock)
    tracker.seed(registry((world["repo"], NAME)))
    return tracker, clock


def test_dead_once(world, mod, capsys):
    tracker, clock = seeded(mod, world, runs_reply(row()), runs_reply(row(lease=None)))
    assert printed(capsys) == []  # the seed prints nothing
    at(clock, tracker, 60)
    lines = printed(capsys)
    assert lines == [dead(world["repo"])]
    assert list(lines[0]) == ["alert"]
    assert list(lines[0]["alert"]) == ["run_id", "root", "project", "state"]
    at(clock, tracker, 120)
    assert printed(capsys) == []
    assert runs_calls(world) == [["runs", "--repo-dir", str(world["repo"])]] * 3


@pytest.mark.parametrize("lease", [None, MISSING, {}, {"live": False}, {"live": "true"},
                                   {"live": 1}, "live"],
                         ids=["synthetic: null", "synthetic: missing", "synthetic: empty",
                              "synthetic: false", "synthetic: string-true", "synthetic: one",
                              "synthetic: string"])
def test_not_live_shapes(world, mod, capsys, lease):
    tracker, clock = seeded(mod, world, runs_reply(row()), runs_reply(row(lease=lease)))
    at(clock, tracker, 60)
    assert printed(capsys) == [dead(world["repo"])]


def test_re_armed_after_resume(world, mod, capsys):
    tracker, clock = seeded(mod, world, runs_reply(row()), runs_reply(row(lease=None)),
                            runs_reply(row()), runs_reply(row(lease=None)))
    at(clock, tracker, 60)
    assert printed(capsys) == [dead(world["repo"])]
    at(clock, tracker, 120)
    assert printed(capsys) == []
    at(clock, tracker, 180)
    assert printed(capsys) == [dead(world["repo"])]


def test_seeded_dead_waits_for_live(world, mod, capsys):
    tracker, clock = seeded(mod, world, *[runs_reply(row(lease=None))] * 3,
                            runs_reply(row()), runs_reply(row(lease=None)))
    for now in (60, 120, 180):
        at(clock, tracker, now)
    assert printed(capsys) == []
    at(clock, tracker, 240)
    assert printed(capsys) == [dead(world["repo"])]
    assert len(runs_calls(world)) == 5


def test_poll_interval(world, mod):
    tracker, clock = seeded(mod, world, runs_reply(row()))
    at(clock, tracker, 59.9)
    assert len(runs_calls(world)) == 1
    at(clock, tracker, 60)
    assert len(runs_calls(world)) == 2
    at(clock, tracker, 60)  # the same instant: not due again
    at(clock, tracker, 119.9)
    assert len(runs_calls(world)) == 2
    at(clock, tracker, 120)
    assert len(runs_calls(world)) == 3


def test_no_poll_when_idle(world, mod):
    tracker, clock = seeded(mod, world, runs_reply(done_row()))
    for now in (60, 600, 3600):
        at(clock, tracker, now)
    assert len(runs_calls(world)) == 1


def test_polls_only_roots_with_started(world, mod):
    r1, r2 = world["tmp"] / "r1", world["tmp"] / "r2"
    r1.mkdir()
    r2.mkdir()
    set_runs(world, {r1: [runs_reply(row())]})
    clock = Clock()
    tracker = mod.Tracker(am_path(world), clock)
    tracker.seed(registry((r1, "one"), (r2, "two")))
    assert runs_calls(world) == [["runs", "--repo-dir", str(r1)],
                                 ["runs", "--repo-dir", str(r2)]]
    at(clock, tracker, 60)
    assert runs_calls(world)[2:] == [["runs", "--repo-dir", str(r1)]]


def test_polls_in_registry_order(world, mod):
    r1, r2 = world["tmp"] / "r1", world["tmp"] / "r2"
    r1.mkdir()
    r2.mkdir()
    set_runs(world, {r1: [runs_reply(row())], r2: [runs_reply(row(RUN_B))]})
    clock = Clock()
    tracker = mod.Tracker(am_path(world), clock)
    tracker.seed(registry((r2, "two"), (r1, "one")))
    at(clock, tracker, 60)
    assert runs_calls(world) == [["runs", "--repo-dir", str(r2)],
                                 ["runs", "--repo-dir", str(r1)]] * 2


@pytest.mark.parametrize("status", ["done", "stopped", "escalated", "cancelled", "canceled",
                                    "waiting"],
                         ids=["done", "stopped", "escalated", "cancelled", "canceled",
                              "synthetic: other"])
def test_terminal_dropped(world, mod, capsys, status):
    tracker, clock = seeded(mod, world, runs_reply(row()),
                            runs_reply(row(status=status, lease=None)))
    at(clock, tracker, 60)
    assert printed(capsys) == []
    at(clock, tracker, 120)
    at(clock, tracker, 600)
    assert len(runs_calls(world)) == 2


def test_absent_row_dropped(world, mod, capsys):
    tracker, clock = seeded(mod, world, runs_reply(row()), runs_reply())
    at(clock, tracker, 60)
    assert printed(capsys) == []
    at(clock, tracker, 120)
    at(clock, tracker, 600)
    assert len(runs_calls(world)) == 2


@pytest.mark.parametrize("failure", sorted(RUNS_FAILURES))
def test_failed_poll_keeps_runs(world, mod, capsys, failure):
    tracker, clock = seeded(mod, world, runs_reply(row()), RUNS_FAILURES[failure],
                            runs_reply(row(lease=None)))
    at(clock, tracker, 60)
    assert printed(capsys) == []
    assert len(runs_calls(world)) == 2
    at(clock, tracker, 119.9)
    assert len(runs_calls(world)) == 2
    at(clock, tracker, 120)
    assert printed(capsys) == [dead(world["repo"])]


def test_poll_timeout_keeps_runs(world, mod, capsys, monkeypatch):
    monkeypatch.setattr(mod, "AM_TIMEOUT", 1.0)
    slow = {**runs_reply(row(lease=None)), "sleep": 8}
    tracker, clock = seeded(mod, world, runs_reply(row()), slow, runs_reply(row(lease=None)))
    began = time.monotonic()
    at(clock, tracker, 60)
    assert time.monotonic() - began < 6
    assert printed(capsys) == []
    assert_gone(int((world["am"] / "runs.pid").read_text()))  # the slow am runs was reaped
    at(clock, tracker, 120)
    assert printed(capsys) == [dead(world["repo"])]


def test_poll_am_cannot_start_keeps_runs(world, mod, capsys):
    tracker, clock = seeded(mod, world, runs_reply(row()), runs_reply(row(lease=None)))
    am = world["bin"] / "am"
    am.chmod(0o644)
    at(clock, tracker, 60)
    assert printed(capsys) == []
    assert len(runs_calls(world)) == 1
    am.chmod(0o755)
    at(clock, tracker, 120)
    assert printed(capsys) == [dead(world["repo"])]


def test_new_started_row_in_poll(world, mod, capsys):
    tracker, clock = seeded(mod, world, runs_reply(row()),
                            runs_reply(row(), row(RUN_B, lease=None)),
                            runs_reply(row(), row(RUN_B)),
                            runs_reply(row(), row(RUN_B, lease=None)))
    at(clock, tracker, 60)
    assert printed(capsys) == []
    at(clock, tracker, 120)
    assert printed(capsys) == []
    at(clock, tracker, 180)
    assert printed(capsys) == [dead(world["repo"], run_id=RUN_B)]


def test_upsert_started_tracks(world, mod, capsys):
    repo = world["repo"]
    tracker, clock = seeded(mod, world, runs_reply(), runs_reply(row(lease=None)))
    watcher = mod.Watcher(registry((repo, NAME)), tracker)
    clock.now = 10
    watcher.see(RUN_A, {"status": "started", "repo_dir": str(repo)})
    at(clock, tracker, 60)  # 50 s after the tracked set became non-empty
    at(clock, tracker, 69.9)
    assert len(runs_calls(world)) == 1
    at(clock, tracker, 70)
    assert len(runs_calls(world)) == 2
    assert printed(capsys) == [dead(repo)]
    assert brd_calls(world) == []


def test_upsert_started_unregistered_not_tracked(world, mod, capsys):
    tracker, clock = seeded(mod, world, runs_reply())
    watcher = mod.Watcher(registry((world["repo"], NAME)), tracker)
    watcher.see(RUN_A, {"status": "started", "repo_dir": str(world["tmp"] / "elsewhere")})
    watcher.see(RUN_B, {"status": "started"})  # no repo_dir at all
    for now in (60, 600):
        at(clock, tracker, now)
    assert len(runs_calls(world)) == 1
    assert printed(capsys) == []
    assert brd_calls(world) == []  # no registry re-read for a started run


@pytest.mark.parametrize("status", ["escalated", "cancelled", "done"])
def test_upsert_other_status_drops(world, mod, capsys, status):
    repo = world["repo"]
    tracker, clock = seeded(mod, world, runs_reply(row()), runs_reply(row(lease=None)))
    watcher = mod.Watcher(registry((repo, NAME)), tracker)
    watcher.see(RUN_A, {"status": status, "repo_dir": str(repo)})
    for now in (60, 600):
        at(clock, tracker, now)
    assert len(runs_calls(world)) == 1
    assert printed(capsys) == ([alert(repo, run_id=RUN_A)] if status == "escalated" else [])
    assert brd_calls(world) == []


def test_upsert_never_arms_and_non_string_status_keeps(world, mod, capsys):
    repo = world["repo"]
    tracker, clock = seeded(mod, world, runs_reply(row(lease=None)))
    watcher = mod.Watcher(registry((repo, NAME)), tracker)
    watcher.see(RUN_A, {"status": "started", "repo_dir": str(repo)})
    watcher.see(RUN_A, {"status": None, "repo_dir": str(repo)})
    at(clock, tracker, 60)
    at(clock, tracker, 120)
    assert printed(capsys) == []  # seeded unarmed; an upsert never arms
    assert len(runs_calls(world)) == 3  # still tracked: polled at 60 and 120


def test_stream_polls_when_due(world, mod, capsys):
    tracker, clock = seeded(mod, world, runs_reply(row()), runs_reply(row(lease=None)))
    watcher = mod.Watcher(registry((world["repo"], NAME)), tracker)
    lines = queue.Queue()
    lines.put(json.dumps(hello()["line"]) + "\n")
    lines.put(mod.EOF)
    clock.now = 60
    assert mod.stream(lines, watcher) is None
    assert printed(capsys) == [dead(world["repo"])]


def test_stream_polls_on_idle_wake(world, mod, capsys):
    tracker, clock = seeded(mod, world, runs_reply(row()), runs_reply(row(lease=None)))
    watcher = mod.Watcher(registry((world["repo"], NAME)), tracker)
    lines = queue.Queue()

    def later():
        time.sleep(0.3)
        clock.now = 60  # due while no am line is pending
        time.sleep(2.5)
        lines.put(mod.EOF)

    feeder = threading.Thread(target=later, daemon=True)
    feeder.start()
    assert mod.stream(lines, watcher) is None
    feeder.join(timeout=10)
    assert printed(capsys) == [dead(world["repo"])]
    assert len(runs_calls(world)) == 2
