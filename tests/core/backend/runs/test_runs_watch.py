"""runs-watch.py: `am watch --all --follow` turned into debounced change signals.

Hermetic: a fake `am` on a temp PATH replays FAKE_AM_DIR/script.json: a list of
steps (a JSON line, raw text, or a sleep), then a chosen stderr text and exit
code. The JSON lines are copies of the committed captures in tests/fixtures/am/;
a line no capture holds is labelled `synthetic:`. A step line's "ts" of "PAST"
(an hour ago) or "NOW" is stamped at the moment the fake am prints it, so PAST
is backlog and NOW is live for the helper, which records its start time before
spawning am. The fake am logs its argv to calls.log and its pid to pid. HOME and
XDG_* are temp. The real `am` and real data are never touched.
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
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "runs-watch.py")

FAKE_AM = r'''#!/usr/bin/env python3
import datetime, json, os, sys, time
d = os.environ["FAKE_AM_DIR"]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\n")
with open(os.path.join(d, "pid"), "w") as f:
    f.write(str(os.getpid()))
with open(os.path.join(d, "script.json")) as f:
    script = json.load(f)


def stamp(value):
    now = datetime.datetime.now(datetime.timezone.utc)
    if value == "PAST":
        now -= datetime.timedelta(hours=1)
    elif value != "NOW":
        return value
    return now.strftime("%Y-%m-%dT%H:%M:%S.%fZ")


for step in script["steps"]:
    if "sleep" in step:
        time.sleep(step["sleep"])
        continue
    if "raw" in step:
        sys.stdout.write(step["raw"] + "\n")
    else:
        line = dict(step["line"])
        if "ts" in line:
            line["ts"] = stamp(line["ts"])
        sys.stdout.write(json.dumps(line, separators=(",", ":")) + "\n")
    sys.stdout.flush()
sys.stderr.write(script.get("stderr", ""))
sys.stderr.flush()
sys.exit(script.get("exit", 0))
'''

MISSING = object()
FIXTURES = os.path.join(ROOT, "tests", "fixtures", "am")


def fixture(name):
    """A fresh json.load of tests/fixtures/am/<name>, so an edit never reaches
    another call."""
    with open(os.path.join(FIXTURES, name)) as f:
        return json.load(f)


# The run of every captured journal line.
WATCHED = fixture("watch-events.json")["data"]["events"][0]["run_id"]


def hello_line(schema):
    """The helper's hello output line for the capture's schema_<schema> hello."""
    line = fixture("watch-hello.json")["schema_%d" % schema]
    return {"hello": {"schema": line["schema"], "am": line["am"]}}


HELLO1 = hello_line(1)
HELLO2 = hello_line(2)


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am, its script dir, a temp HOME, and a project root
    whose name would break if it ever went through a shell."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "am", FAKE_AM)
    amdir = tmp_path / "am"
    amdir.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    proj = tmp_path / "my proj; echo x"
    proj.mkdir()
    return {"tmp": tmp_path, "bin": bindir, "am": amdir, "home": home, "proj": proj}


def env_for(world, **extra):
    e = {
        "PATH": str(world["bin"]) + os.pathsep + "/usr/bin" + os.pathsep + "/bin",
        "HOME": str(world["home"]),
        "FAKE_AM_DIR": str(world["am"]),
    }
    for name in ("XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        e[name] = str(world["tmp"] / name.lower())
    e.update(extra)
    return e


KEEP = object()


def hello(schema=1, am=KEEP):
    """The --follow hello: the captured schema_1 line, or the capture's derived
    schema_2 line for schema=2. synthetic: any other schema value is set on a
    schema_1 copy; MISSING leaves the key out. synthetic: am, unless KEEP, is set
    to the given value on the copy; MISSING leaves the key out."""
    lines = fixture("watch-hello.json")
    if type(schema) is int and schema in (1, 2):
        line = lines["schema_%d" % schema]
    else:
        line = lines["schema_1"]
        if schema is MISSING:
            del line["schema"]
        else:
            line["schema"] = schema
    if am is MISSING:
        del line["am"]
    elif am is not KEEP:
        line["am"] = am
    return {"line": line}


def ev(event="phase_upsert", ts="NOW"):
    """The first captured journal line whose event is `event` (a WATCHED line).
    edited copy: ts is the fake am's PAST/NOW marker."""
    line = next(e for e in fixture("watch-events.json")["data"]["events"]
                if e["event"] == event)
    line["ts"] = ts
    return {"line": line}


def upsert(ts="NOW"):
    """The captured run_upsert, carrying its repo_dir (not the run's first line:
    lease_acquired comes before it)."""
    return ev("run_upsert", ts)


def other(run_id, event="phase_upsert", ts="NOW", repo_dir=None, payload_keys=None,
          **extra):
    """synthetic: a line the single-run capture has no copy of, built on a copy of
    ev(event): run_id set to the given id (MISSING drops it); an event no capture
    has laid on a phase_upsert copy; ts set to any value (MISSING drops it);
    repo_dir sets a run_upsert's payload.id and payload.repo_dir; payload_keys
    and extra add keys to the payload and the top level."""
    captured = {e["event"] for e in fixture("watch-events.json")["data"]["events"]}
    step = ev(event if event in captured else "phase_upsert")
    line = step["line"]
    line["event"] = event
    if run_id is MISSING:
        del line["run_id"]
    else:
        line["run_id"] = run_id
    if ts is MISSING:
        del line["ts"]
    else:
        line["ts"] = ts
    if repo_dir is not None:
        line["payload"]["id"] = run_id
        line["payload"]["repo_dir"] = repo_dir
    line["payload"].update(payload_keys or {})
    line.update(extra)
    return step


def pause(seconds):
    return {"sleep": seconds}


def raw(text):
    return {"raw": text}


def set_script(world, steps, exit=0, stderr=""):
    (world["am"] / "script.json").write_text(
        json.dumps({"steps": steps, "exit": exit, "stderr": stderr}))


def run_helper(world, args=None, timeout=30, **extra):
    """Run the helper until it exits (default argv: project root, run id WATCHED).
    Every stdout line must be JSON. Returns (exit code, parsed lines, stderr)."""
    argv = [str(world["proj"]), WATCHED] if args is None else args
    p = subprocess.run([sys.executable, SCRIPT, *argv], capture_output=True, text=True,
                       env=env_for(world, **extra), timeout=timeout)
    return p.returncode, [json.loads(line) for line in p.stdout.splitlines()], p.stderr


def changed(lines):
    """Each line's run ids, sorted (order inside a line is not part of the
    contract). Every line must be a non-empty, duplicate-free changed line that
    carries nothing but run ids."""
    for line in lines:
        assert set(line) == {"changed"}, line
        assert line["changed"], line
        assert all(isinstance(i, str) for i in line["changed"]), line
        assert len(line["changed"]) == len(set(line["changed"])), line
    return [sorted(line["changed"]) for line in lines]


def split(lines, greeting=HELLO1):
    """The lines after the leading hello line, which must be `greeting`."""
    assert lines, lines
    assert lines[0] == greeting, lines
    return lines[1:]


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


# --- the lines are capture copies -----------------------------------------------

def test_lines_are_capture_copies():
    events = fixture("watch-events.json")["data"]["events"]
    for name in ["run_upsert", "subtask_upsert", "phase_upsert", "attempt_upsert"]:
        first = next(e for e in events if e["event"] == name)
        line = ev(name, "NOW")["line"]
        assert set(line) == set(first)
        assert line["ts"] == "NOW"
        assert {k: v for k, v in line.items() if k != "ts"} == \
            {k: v for k, v in first.items() if k != "ts"}
    # An unedited run_upsert is a WATCHED line: it is kept for argv, never adopted.
    assert upsert()["line"] == ev("run_upsert")["line"]
    assert upsert()["line"]["run_id"] == WATCHED
    assert hello() == {"line": fixture("watch-hello.json")["schema_1"]}
    assert hello(2) == {"line": fixture("watch-hello.json")["schema_2"]}
    assert HELLO1 == {"hello": {"schema": 1, "am": "0.1.0"}}
    assert HELLO2 == {"hello": {"schema": 2, "am": "0.1.0"}}


# --- usage, am missing, clean exit --------------------------------------------

def test_clean_exit_zero(world):
    set_script(world, [hello()])
    code, lines, err = run_helper(world)
    assert code == 0
    assert lines == [HELLO1]
    assert "Traceback" not in err
    # argv list, no shell: the fake am sees exactly these three arguments.
    assert calls(world) == [["watch", "--all", "--follow"]]


def test_usage(world):
    set_script(world, [hello()])
    code, lines, _ = run_helper(world, [])
    assert code == 2
    assert len(lines) == 1, lines
    assert lines[0]["ok"] is False
    assert lines[0]["error"]["type"] == "Usage"
    assert "runs-watch.py <project_root>" in lines[0]["error"]["message"]
    assert calls(world) == []


def test_am_missing(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, lines, _ = run_helper(world, PATH=str(empty))
    assert code == 1
    assert len(lines) == 1, lines
    assert lines[0]["ok"] is False
    assert lines[0]["error"]["type"] == "AmMissing"
    assert lines[0]["error"]["message"]


# --- backlog, filter, unknown input ------------------------------------------

def test_forwards_hello_and_drops_backlog(world):
    # WATCHED's lines were written an hour before the helper started: backlog,
    # dropped. r2's line is live and proves the helper is reading at all.
    set_script(world, [hello(), ev(ts="PAST"), ev("subtask_upsert", ts="PAST"),
                       other("r2")])
    code, lines, _ = run_helper(world, [str(world["proj"]), WATCHED, "r2"])
    assert code == 0
    assert changed(split(lines)) == [["r2"]]


def test_live_event_for_watched_run_emits_changed(world):
    set_script(world, [hello(), ev()])
    code, lines, _ = run_helper(world)
    assert code == 0
    # Exactly this object: run ids only, no event contents.
    assert lines == [HELLO1, {"changed": [WATCHED]}]


def test_filters_unwatched_runs(world):
    # WATCHED's live line is the positive control: the helper is reading, and
    # only the unwatched runs are dropped.
    set_script(world, [hello(), other("r9"), other("r8", "attempt_upsert"),
                       other("r7", "run_upsert", repo_dir="/somewhere/else"), ev()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert changed(split(lines)) == [[WATCHED]]


def test_ignores_unknown_events_and_keys(world):
    set_script(world, [
        hello(),
        raw("not json"),                               # synthetic: garbage lines
        raw("[1, 2]"),
        raw(""),
        other("r2", "future_upsert"),                  # unknown event: ignored
        other(MISSING),                                # no run_id: ignored
        other(WATCHED, payload_keys={"shiny": {"new": 1}},
              brand_new_key=[1, 2, 3]),                # extra keys: kept
    ])
    code, lines, err = run_helper(world, [str(world["proj"]), WATCHED, "r2"])
    assert code == 0
    assert "Traceback" not in err
    assert changed(split(lines)) == [[WATCHED]]


def test_missing_or_unparseable_ts_is_kept(world):
    # Not provably backlog, so kept.
    set_script(world, [hello(), other(WATCHED, ts=MISSING), other("r2", ts="yesterday-ish")])
    code, lines, _ = run_helper(world, [str(world["proj"]), WATCHED, "r2"])
    assert code == 0
    assert changed(split(lines)) == [sorted([WATCHED, "r2"])]


# --- debounce -------------------------------------------------------------------

def test_debounce_batches_and_dedupes(world):
    set_script(world, [hello(), ev(), other("r2"), ev(), other("r2", "attempt_upsert"),
                       ev("subtask_upsert"), pause(0.6)])
    code, lines, _ = run_helper(world, [str(world["proj"]), WATCHED, "r2"])
    assert code == 0
    assert changed(split(lines)) == [sorted([WATCHED, "r2"])]


def test_debounce_separate_windows(world):
    set_script(world, [hello(), ev(), pause(0.6), ev(), pause(0.6)])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert changed(split(lines)) == [[WATCHED], [WATCHED]]


def test_debounce_continuous_stream_is_rate_limited(world):
    # An event every 50 ms for over a second: the window must still close on
    # time (more than one line), and lines never come faster than one per 250 ms.
    steps = [hello()]
    for _ in range(20):
        steps += [ev(), pause(0.05)]
    set_script(world, steps)
    began = time.monotonic()
    code, lines, _ = run_helper(world)
    elapsed = time.monotonic() - began
    assert code == 0
    got = changed(split(lines))
    assert all(ids == [WATCHED] for ids in got)
    assert len(got) >= 2, got
    assert len(got) <= int(elapsed / 0.25) + 1, (len(got), elapsed)


# --- adoption of new runs in this project -------------------------------------

@pytest.mark.parametrize("form", ["exact", "trailing-slash", "dot-segment"])
def test_new_run_upsert_in_project_is_adopted(world, form):
    root = str(world["proj"])
    repo_dir = {"exact": root, "trailing-slash": root + "/", "dot-segment": root + "/./"}[form]
    set_script(world, [
        hello(),
        other("n1", "run_upsert", repo_dir=repo_dir),          # this project: adopted and signalled
        other("n2", "run_upsert", repo_dir="/somewhere/else"),  # other repo: ignored
        other("n2"),                                            # still not watched
        pause(0.6),
        other("n1"),                                            # adopted: kept from now on
        pause(0.6),
    ])
    code, lines, _ = run_helper(world, [root])  # zero run ids on argv is valid
    assert code == 0
    assert changed(split(lines)) == [["n1"], ["n1"]]


# --- the hello line ---------------------------------------------------------------

@pytest.mark.parametrize("schema, greeting", [(1, HELLO1), (2, HELLO2)], ids=["one", "two"])
def test_hello_forwarded_for_schema(world, schema, greeting):
    # Only schema and am are forwarded (not event or runs_dir), before the
    # changed line that follows the hello.
    set_script(world, [hello(schema), ev()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [greeting, {"changed": [WATCHED]}]


# synthetic: hellos whose am is missing, a number, null or an object.
@pytest.mark.parametrize("am", [MISSING, 5, None, {"v": 1}],
                         ids=["synthetic: missing", "synthetic: number", "synthetic: null",
                              "synthetic: object"])
def test_hello_am_not_a_string(world, am):
    set_script(world, [hello(2, am=am), ev()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [{"hello": {"schema": 2, "am": ""}}, {"changed": [WATCHED]}]


def test_hello_unknown_keys_not_forwarded(world):
    step = hello(2)
    step["line"]["shiny"] = {"new": 1}  # synthetic: a hello key no capture has
    set_script(world, [step, ev()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [HELLO2, {"changed": [WATCHED]}]


def test_hello_forwarded_once(world):
    set_script(world, [hello(1), hello(2), hello(1), ev()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert [line for line in lines if "hello" in line] == [HELLO1]
    assert changed(split(lines)) == [[WATCHED]]


def test_hello_mid_batch_keeps_the_batch(world):
    # WATCHED's line opens a batch; the hello is printed at once without
    # flushing or clearing it, so r2 joins the same changed line.
    set_script(world, [ev(), hello(1), other("r2"), pause(0.6)])
    code, lines, _ = run_helper(world, [str(world["proj"]), WATCHED, "r2"])
    assert code == 0
    assert changed(split(lines)) == [sorted([WATCHED, "r2"])]


@pytest.mark.parametrize("steps", [
    [hello(1), hello(3), ev(), pause(8)],
    [hello(1), ev(), hello(3), ev(), pause(8)],  # the pending batch is dropped
], ids=["synthetic: three", "synthetic: three, pending-batch"])
def test_later_bad_hello_is_schema_mismatch(world, steps):
    set_script(world, steps)
    began = time.monotonic()
    code, lines, _ = run_helper(world)
    assert time.monotonic() - began < 5
    assert code != 0
    assert len(lines) == 2, lines
    assert lines[0] == HELLO1
    assert lines[1]["ok"] is False
    assert lines[1]["error"]["type"] == "SchemaMismatch"
    assert lines[1]["error"]["message"]
    assert_gone(am_pid(world))


@pytest.mark.parametrize("schema, greeting", [(1, HELLO1), (2, HELLO2)], ids=["one", "two"])
def test_journal_same_under_both_schemas(world, schema, greeting):
    root = str(world["proj"])
    set_script(world, [
        hello(schema),
        ev(ts="PAST"),                                          # backlog: dropped
        other("r9"),                                            # unwatched: dropped
        other("r7", "run_upsert", repo_dir="/somewhere/else"),  # other repo: ignored
        other("n1", "run_upsert", repo_dir=root),               # this project: adopted
        ev(), other("n1"), ev("subtask_upsert"),                # one debounced burst
        pause(0.6),
        other("n1"),                                            # adopted: kept from now on
        pause(0.6),
    ])
    code, lines, _ = run_helper(world, [root, WATCHED])
    assert code == 0
    assert changed(split(lines, greeting)) == [sorted([WATCHED, "n1"]), ["n1"]]


def test_no_hello_still_streams(world):
    set_script(world, [ev()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [{"changed": [WATCHED]}]


# --- error paths -----------------------------------------------------------------

@pytest.mark.parametrize("schema", [3, "1", MISSING, True, 0, 2.0, "2"],
                         ids=["synthetic: three", "string-one", "missing", "synthetic: true",
                              "synthetic: zero", "synthetic: two-float", "synthetic: string-two"])
def test_schema_mismatch(world, schema):
    # am would keep streaming for 8 s; the helper must stop it and leave at once.
    set_script(world, [hello(schema), ev(), pause(8)])
    began = time.monotonic()
    code, lines, _ = run_helper(world)
    assert time.monotonic() - began < 5
    assert code != 0
    assert len(lines) == 1, lines
    assert lines[0]["ok"] is False
    assert lines[0]["error"]["type"] == "SchemaMismatch"
    message = lines[0]["error"]["message"]
    assert message
    received = json.dumps(None if schema is MISSING else schema)
    assert "schema " + received in message, message
    assert "1 or 2" in message, message
    assert_gone(am_pid(world))  # am was terminated, not left streaming


def test_exit_3_corrupt_journal(world):
    # synthetic: am's stderr text for a corrupt journal.
    set_script(world, [hello(), ev()], exit=3,
               stderr="am watch: journal line 4 of run r1 is not JSON\n")
    code, lines, _ = run_helper(world)
    assert code != 0
    assert len(lines) == 3, lines
    assert lines[0] == HELLO1
    assert lines[1] == {"changed": [WATCHED]}  # the pending batch is flushed first
    assert lines[2]["ok"] is False
    assert lines[2]["error"]["type"] == "CorruptJournal"
    assert "journal line 4 of run r1 is not JSON" in lines[2]["error"]["message"]


def test_other_exit_is_helper_error(world):
    # synthetic: am's stderr text for a crash.
    set_script(world, [hello(), ev()], exit=1, stderr="boom\n")
    code, lines, _ = run_helper(world)
    assert code != 0
    assert len(lines) == 3, lines
    assert lines[0] == HELLO1
    assert lines[1] == {"changed": [WATCHED]}
    assert lines[2]["ok"] is False
    assert lines[2]["error"]["type"] == "HelperError"
    assert "boom" in lines[2]["error"]["message"]


def test_refusal_exit_3_is_corrupt_journal(world):
    # synthetic: an am refusal envelope; no capture holds one.
    envelope = {"error": {"message": "run r1: journal line 2 is not JSON",
                          "type": "CorruptJournalError"}, "ok": False}
    set_script(world, [{"line": envelope}], exit=3)
    code, lines, _ = run_helper(world)
    assert code != 0
    assert len(lines) == 1, lines
    assert lines[0]["ok"] is False
    assert lines[0]["error"]["type"] == "CorruptJournal"
    assert lines[0]["error"]["message"] == "run r1: journal line 2 is not JSON"


def test_refusal_other_exit_is_reemitted(world):
    # synthetic: an am refusal envelope; no capture holds one.
    envelope = {"error": {"message": "something else", "type": "OddError"}, "ok": False}
    set_script(world, [{"line": envelope}], exit=0)
    code, lines, _ = run_helper(world)
    assert code != 0
    assert lines == [envelope]


def test_refusal_after_hello_is_reemitted(world):
    # synthetic: an am refusal envelope; no capture holds one.
    envelope = {"error": {"message": "something else", "type": "OddError"}, "ok": False}
    set_script(world, [hello(2), {"line": envelope}], exit=0)
    code, lines, _ = run_helper(world)
    assert code != 0
    assert lines == [HELLO2, envelope]


# --- stopping: signals and a closed stdout ---------------------------------------

def start_helper(world, args=None):
    argv = [str(world["proj"]), WATCHED] if args is None else args
    return subprocess.Popen([sys.executable, SCRIPT, *argv], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                            env=env_for(world))


def am_pid(world):
    return int((world["am"] / "pid").read_text())


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


@pytest.mark.parametrize("sig", [signal.SIGTERM, signal.SIGINT], ids=["SIGTERM", "SIGINT"])
def test_signal_stops_am_and_exits_zero(world, sig):
    set_script(world, [hello(), ev(), pause(30)])
    p = start_helper(world)
    try:
        assert json.loads(p.stdout.readline()) == HELLO1
        second = p.stdout.readline()  # sync point: am is running, helper is streaming
        assert json.loads(second) == {"changed": [WATCHED]}
        p.send_signal(sig)
        code = p.wait(timeout=10)
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
    err = p.stderr.read()
    p.stdout.close()
    p.stderr.close()
    assert code == 0, err
    assert "Traceback" not in err
    assert_gone(am_pid(world))


def test_closed_stdout_exits_zero(world):
    set_script(world, [hello(), ev(), pause(0.6), ev(), pause(30)])
    p = start_helper(world)
    p.stdout.close()  # the reader goes away before the first changed line
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
    assert "BrokenPipeError" not in err
    assert_gone(am_pid(world))
