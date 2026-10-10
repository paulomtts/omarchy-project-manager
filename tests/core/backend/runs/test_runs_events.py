"""runs-events.py: one run's events through a one-shot `am watch RUN`, one JSON line on every path.

Hermetic: a fake `am` lives on a temp PATH and serves, from FAKE_AM_DIR, the
committed capture tests/fixtures/am/watch-events.json (a payload no capture holds
is labelled `synthetic:`), appending each call's argv to calls.log; HOME and
XDG_DATA_HOME are temp. The real `am` and real data are never touched.
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
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "runs-events.py")

# The fake am logs its argv, then (keyed on the subcommand, so "watch") writes
# FAKE_AM_DIR/watch.err to stderr if present, prints FAKE_AM_DIR/watch.out verbatim
# and exits with FAKE_AM_DIR/watch.code (default 0). A missing .out fixture behaves
# like real am for an unknown run: an UnknownRunError envelope and exit 3.
FAKE_AM = '''#!/usr/bin/env python3
import json, os, sys
d = os.environ["FAKE_AM_DIR"]
args = sys.argv[1:]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(args) + "\\n")
name = "watch" if args[:1] == ["watch"] else "other"
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

RUN = "20261008T143807Z-63060df3"
FIXTURES = os.path.join(ROOT, "tests", "fixtures", "am")
USAGE_LINE = {"ok": False, "error": {
    "type": "Usage", "message": "usage: runs-events.py RUN [--since SEQ] [--tail N]"}}
# synthetic: am's error envelope for an unknown run; no capture holds one.
UNKNOWN_RUN = {"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}


def fixture(name):
    """A fresh json.load of tests/fixtures/am/<name>, so an edit never reaches
    another call."""
    with open(os.path.join(FIXTURES, name)) as f:
        return json.load(f)


def watch_envelope():
    """The captured `am watch RUN` envelope without the capture's `_note`."""
    return {k: v for k, v in fixture("watch-events.json").items() if not k.startswith("_")}


def watch_events():
    """The captured run's 60 events, seq 1..60, in am's order."""
    return watch_envelope()["data"]["events"]


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am, its fixture dir and a temp HOME/XDG_DATA_HOME."""
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
    argv = [RUN] if args is None else args
    p = subprocess.run([sys.executable, SCRIPT, *argv], capture_output=True, text=True,
                       env=env_for(world, drop, **extra), timeout=60)
    lines = p.stdout.splitlines()
    assert len(lines) == 1, (p.stdout, p.stderr)
    return p.returncode, json.loads(lines[0])


def set_watch(world, envelope, code=0):
    (world["am"] / "watch.out").write_text(json.dumps(envelope) + "\n")
    (world["am"] / "watch.code").write_text(str(code))


def set_raw(world, text, code=0, stderr=None):
    (world["am"] / "watch.out").write_text(text)
    (world["am"] / "watch.code").write_text(str(code))
    if stderr is not None:
        (world["am"] / "watch.err").write_text(stderr)


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def event(seq, **extra):
    """synthetic: one journal event of RUN with the given seq."""
    e = {"seq": seq, "gseq": 100 + seq, "ts": "2026-10-08T14:38:07Z", "run_id": RUN,
         "event": "phase_upsert", "story": None, "card": None, "phase": None,
         "attempt": None, "payload": {}}
    e.update(extra)
    return e


# --- fixture and am's argv ------------------------------------------------------

def test_fixture_is_one_run_in_seq_order():
    events = watch_events()
    assert watch_envelope()["ok"] is True
    assert len(events) == 60
    assert {e["run_id"] for e in events} == {RUN}
    seqs = [e["seq"] for e in events]
    assert seqs == sorted(set(seqs))
    assert seqs[0] == 1 and seqs[-1] == 60


def test_argv_without_since(world):
    set_watch(world, watch_envelope())
    code, _ = run(world, [RUN])
    assert code == 0
    made = calls(world)
    assert made == [["watch", RUN]]
    for flag in ("--follow", "--repo-dir", "--pretty", "--all", "--since-seq"):
        assert flag not in made[0]


@pytest.mark.parametrize("seq", ["12", "0"])
def test_argv_with_since(world, seq):
    set_watch(world, watch_envelope())
    code, _ = run(world, [RUN, "--since", seq])
    assert code == 0
    assert calls(world) == [["watch", RUN, "--since", seq]]


@pytest.mark.parametrize("args", [
    [RUN, "--tail", "5", "--since", "3"],
    [RUN, "--since", "3", "--tail", "5"],
], ids=["tail-first", "since-first"])
def test_tail_is_not_passed_to_am(world, args):
    set_watch(world, watch_envelope())
    code, _ = run(world, args)
    assert code == 0
    assert calls(world) == [["watch", RUN, "--since", "3"]]


def test_since_leading_zeros(world):
    # SEQ reaches am as typed; an empty match still reports it as an integer.
    # synthetic: am's envelope when no event is newer than --since.
    set_watch(world, {"ok": True, "data": {"events": []}})
    code, out = run(world, [RUN, "--since", "007"])
    assert code == 0
    assert calls(world) == [["watch", RUN, "--since", "007"]]
    assert out == {"ok": True, "events": [], "last_seq": 7, "total": 0}


def test_run_reaches_am_verbatim(world):
    run_id = "r 1; echo $(id) & x"
    set_watch(world, watch_envelope())
    code, _ = run(world, [run_id])
    assert code == 0
    assert calls(world) == [["watch", run_id]]


# --- the snapshot ----------------------------------------------------------------

def test_all_events_without_tail(world):
    set_watch(world, watch_envelope())
    code, out = run(world)
    assert code == 0
    assert out == {"ok": True, "events": watch_events(), "last_seq": 60, "total": 60}
    assert list(out) == ["ok", "events", "last_seq", "total"]


def test_tail_keeps_last_n_and_counts_all(world):
    set_watch(world, watch_envelope())
    code, out = run(world, [RUN, "--tail", "5"])
    assert code == 0
    assert out == {"ok": True, "events": watch_events()[-5:], "last_seq": 60, "total": 60}
    assert [e["seq"] for e in out["events"]] == [56, 57, 58, 59, 60]


@pytest.mark.parametrize("tail", ["500", "60", "99999999999999999999"])
def test_tail_larger_than_match(world, tail):
    set_watch(world, watch_envelope())
    code, out = run(world, [RUN, "--tail", tail])
    assert code == 0
    assert out == {"ok": True, "events": watch_events(), "last_seq": 60, "total": 60}


def test_last_seq_is_max_over_all_matched(world):
    # synthetic: am order whose highest seq is not the last event.
    set_watch(world, {"ok": True, "data": {"events": [event(5), event(9), event(7)]}})
    code, out = run(world, [RUN, "--tail", "1"])
    assert code == 0
    assert out == {"ok": True, "events": [event(7)], "last_seq": 9, "total": 3}


@pytest.mark.parametrize("args,last_seq", [
    ([RUN, "--since", "42"], 42),
    ([RUN], 0),
    ([RUN, "--since", "42", "--tail", "3"], 42),
], ids=["since", "no-since", "since-and-tail"])
def test_empty_match_last_seq(world, args, last_seq):
    # synthetic: am's envelope when no event matched.
    set_watch(world, {"ok": True, "data": {"events": []}})
    code, out = run(world, args)
    assert code == 0
    assert out == {"ok": True, "events": [], "last_seq": last_seq, "total": 0}


def test_unknown_event_keys_pass_through(world):
    # synthetic: an event kind and a key no capture holds.
    odd = event(3, event="brand_new_kind", extra_key={"nested": [1, "two"]})
    set_watch(world, {"ok": True, "data": {"events": [event(2), odd]}})
    code, out = run(world)
    assert code == 0
    assert out["events"] == [event(2), odd]
    assert out["last_seq"] == 3 and out["total"] == 2


def test_pretty_output_is_one_line(world):
    set_raw(world, json.dumps(watch_envelope(), indent=2) + "\n")
    code, out = run(world)  # run() asserts exactly one line
    assert code == 0
    assert out == {"ok": True, "events": watch_events(), "last_seq": 60, "total": 60}


def test_am_does_not_inherit_stdin(world):
    # The helper's stdin is an open pipe that never sends EOF. An am that reads
    # stdin must get EOF at once (stdin is /dev/null), not block on that pipe.
    set_watch(world, watch_envelope())
    write_exec(world["bin"] / "am",
               "#!/usr/bin/env python3\nimport os, sys\nsys.stdin.read()\n"
               "sys.stdout.write(open(os.path.join(os.environ['FAKE_AM_DIR'], 'watch.out')).read())\n")
    p = subprocess.Popen([sys.executable, SCRIPT, RUN], stdin=subprocess.PIPE,
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
    assert json.loads(lines[0]) == {"ok": True, "events": watch_events(),
                                    "last_seq": 60, "total": 60}


# --- usage -----------------------------------------------------------------------

@pytest.mark.parametrize("args", [
    [],
    [""],
    ["-x"],
    ["--since", "3", RUN],
    [RUN, "other"],
    [RUN, "--bogus", "1"],
    [RUN, "--since"],
    [RUN, "--tail"],
    [RUN, "--since", "-1"],
    [RUN, "--since", "abc"],
    [RUN, "--since", ""],
    [RUN, "--since", "1.5"],
    [RUN, "--since", " 3"],
    [RUN, "--since", "٣"],
    [RUN, "--since=5"],
    [RUN, "--tail", "0"],
    [RUN, "--tail", "00"],
    [RUN, "--tail", "x"],
    [RUN, "--tail", "-3"],
    [RUN, "--tail", "²"],
    [RUN, "--since", "1", "--since", "2"],
    [RUN, "--tail", "1", "--tail", "2"],
    [RUN, "--since", "--tail", "5"],
], ids=["none", "empty-run", "dash-run", "option-before-run", "two-positionals",
        "unknown-option", "since-no-value", "tail-no-value", "since-negative",
        "since-abc", "since-empty", "since-float", "since-space", "since-arabic-digit",
        "since-equals", "tail-zero", "tail-double-zero", "tail-x", "tail-negative",
        "tail-superscript", "since-twice", "tail-twice", "since-value-is-flag"])
def test_usage(world, args):
    set_watch(world, watch_envelope())
    code, out = run(world, args)
    assert code == 2
    assert out == USAGE_LINE
    assert calls(world) == []


# --- am's refusal, corrupt journal, bad output -----------------------------------

# synthetic: am refusals other than the fake's UnknownRunError default.
STORE_BUSY = {"ok": False, "error": {"type": "StoreBusyError", "message": "store is busy"}}
CLI_ERROR = {"ok": False, "error": {"type": "CliError", "message": "--since must be >= 0"}}


@pytest.mark.parametrize("envelope,exit_code", [
    (None, 3),
    (STORE_BUSY, 3),
    (CLI_ERROR, 0),
], ids=["unknown-run-default", "store-busy", "cli-error-exit-0"])
def test_refusal_passthrough(world, envelope, exit_code):
    if envelope is None:
        expected = UNKNOWN_RUN  # no watch.out: the fake answers UnknownRunError, exit 3
    else:
        set_watch(world, envelope, code=exit_code)
        expected = envelope
    code, out = run(world)
    assert code == 0
    assert out == expected
    assert calls(world) == [["watch", RUN]]


def test_refusal_with_stderr_is_not_corrupt(world):
    # synthetic: a refusal at exit 3 with stderr noise stays am's refusal.
    (world["am"] / "watch.err").write_text("warning: noisy\n")
    set_watch(world, STORE_BUSY, code=3)
    code, out = run(world)
    assert code == 0
    assert out == STORE_BUSY


def test_ok_wins_over_exit_code_and_stderr(world):
    # The envelope's `ok` decides, not am's exit code; am's stderr never reaches
    # the helper's stdout line.
    for exit_code in (3, 1):
        # synthetic: am stderr noise.
        set_raw(world, json.dumps(watch_envelope()) + "\n", code=exit_code,
                stderr="warning: noisy\nmore noise\n")
        code, out = run(world, [RUN, "--tail", "2"])
        assert code == 0
        assert out == {"ok": True, "events": watch_events()[-2:], "last_seq": 60, "total": 60}


# synthetic: am exit 3 output that is not an envelope.
@pytest.mark.parametrize("text", [
    "",
    "store unreadable\n",
    "Traceback (most recent call last):\n  sqlite3.DatabaseError: file is not a database\n",
], ids=["empty", "text", "traceback"])
@pytest.mark.parametrize("stderr,message", [
    (None, "am watch exited 3."),
    ("", "am watch exited 3."),
    ("  journal is corrupt\n\n", "journal is corrupt"),
], ids=["no-stderr", "empty-stderr", "stderr"])
def test_corrupt_journal_exit_3(world, text, stderr, message):
    set_raw(world, text, code=3, stderr=stderr)
    code, out = run(world)
    assert code == 0
    assert out == {"ok": False, "error": {"type": "CorruptJournal", "message": message}}


# synthetic: am failing without an envelope at an exit code other than 3.
@pytest.mark.parametrize("text,exit_code", [
    ("boom\n", 1),
    ("Usage: am watch [OPTIONS] [RUN]\nError: Invalid value\n", 2),
], ids=["exit-1", "exit-2"])
def test_other_nonzero_without_envelope_is_bad_output(world, text, exit_code):
    set_raw(world, text, code=exit_code, stderr="error\n")
    code, out = run(world)
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "AmBadOutput"
    assert "am watch" in out["error"]["message"]
    assert "(exit %d)" % exit_code in out["error"]["message"]


# synthetic: am output at exit 0 that is not a usable envelope.
@pytest.mark.parametrize("text", [
    "not json\n",
    "",
    "[1, 2]\n",
    "null\n",
    '{"data": {"events": []}}\n',
    '{"ok": "true", "data": {"events": []}}\n',
    '{"ok": true}\n',
    '{"ok": true, "data": [1]}\n',
    '{"ok": true, "data": {}}\n',
    '{"ok": true, "data": {"events": {"seq": 1}}}\n',
    '{"ok": true, "data": {"events": [{"event": "run_upsert"}]}}\n',
    '{"ok": true, "data": {"events": [{"seq": "1"}]}}\n',
    '{"ok": true, "data": {"events": [{"seq": true}]}}\n',
    '{"ok": true, "data": {"events": [{"seq": 1.0}]}}\n',
    '{"ok": true, "data": {"events": [{"seq": 1}, 2]}}\n',
], ids=["not-json", "empty", "list", "null", "no-ok", "ok-string", "no-data",
        "data-list", "no-events", "events-object", "event-without-seq", "seq-string",
        "seq-bool", "seq-float", "event-not-object"])
def test_bad_output_at_exit_0(world, text):
    set_raw(world, text, code=0)
    code, out = run(world)
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "AmBadOutput"
    assert "am watch" in out["error"]["message"]
    assert "(exit 0)" in out["error"]["message"]


# --- am missing, catch-all ---------------------------------------------------------

def test_am_missing(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, out = run(world, PATH=str(empty))
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmMissing", "message": "am is not installed."}}


def test_am_cannot_start_is_helper_error(world):
    # Executable (so shutil.which finds it) but unstartable: subprocess raises
    # OSError and guarded() must still print exactly one JSON line.
    write_exec(world["bin"] / "am", "#!/nonexistent/interpreter\n")
    code, out = run(world)
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The events snapshot failed: ")


def load_helper():
    """The script as a module (its name has a hyphen, so no plain import)."""
    spec = importlib.util.spec_from_file_location("runs_events", SCRIPT)
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
    code = helper.guarded([RUN])
    lines = capsys.readouterr().out.splitlines()
    assert code == 0
    assert len(lines) == 1, lines
    out = json.loads(lines[0])
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The events snapshot failed: ")
