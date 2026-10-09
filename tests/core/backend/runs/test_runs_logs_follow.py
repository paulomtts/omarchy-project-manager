"""runs-logs-follow.py: one attempt's `am logs --follow` stdout as a stream.

Hermetic: a fake `am` on a temp PATH replays FAKE_AM_DIR/script.json: a list of
steps (a JSON line, raw text, a sleep, or ignore_term, which makes it ignore
SIGTERM), then a chosen stderr text and exit code. The JSON lines are copies of
the committed captures tests/fixtures/am/logs-follow-agent.jsonl,
logs-follow-step.jsonl and logs-follow-refusal.json; a line no capture holds is
built by a helper labelled `synthetic:`. The fake am logs its argv to calls.log
and its pid to pid. HOME and XDG_* are temp. The real `am` and real data are
never touched.
"""
import json
import os
import signal
import stat
import subprocess
import sys
import threading
import time

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "..")
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "runs-logs-follow.py")
USAGE = "usage: runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT [OFFSET]"
FIXTURES = os.path.join(ROOT, "tests", "fixtures", "am")

# The run, card and phase of the agent capture (its hello's path); REPO never
# has to exist.
REPO = "/some/repo"
RUN = "20261009T185646Z-b772d3d6"
CARD = "f9027ac2-537c-4066-a83b-827a15d45c0e"
PHASE = "review"
ARGS = [REPO, RUN, CARD, PHASE, "1"]
MISSING = object()
IGNORE_TERM = {"ignore_term": True}

FAKE_AM = r'''#!/usr/bin/env python3
import json, os, signal, sys, time
d = os.environ["FAKE_AM_DIR"]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\n")
with open(os.path.join(d, "pid"), "w") as f:
    f.write(str(os.getpid()))
with open(os.path.join(d, "script.json")) as f:
    script = json.load(f)
out = sys.stdout.buffer
for step in script["steps"]:
    if "sleep" in step:
        time.sleep(step["sleep"])
        continue
    if "ignore_term" in step:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        continue
    if "raw" in step:
        text = step["raw"]
    else:
        text = json.dumps(step["line"], separators=(",", ":"))
    out.write((text + "\n").encode("utf-8"))
    out.flush()
sys.stderr.write(script.get("stderr", ""))
sys.stderr.flush()
sys.exit(script.get("exit", 0))
'''


def capture_text(name):
    """The raw lines of tests/fixtures/am/<name>."""
    with open(os.path.join(FIXTURES, name)) as f:
        return [line for line in f.read().splitlines() if line]


def lines_of(name):
    """A fresh parse of each line of tests/fixtures/am/<name>."""
    return [json.loads(line) for line in capture_text(name)]


def agent():
    """The agent capture: [hello, chunk, end] of review attempt 1."""
    return lines_of("logs-follow-agent.jsonl")


def step_capture():
    """The step capture: [hello, chunk, end] of a verify step (ATTEMPT 0)."""
    return lines_of("logs-follow-step.jsonl")


def refusal():
    """The captured refusal envelope (UnknownAttemptError)."""
    return lines_of("logs-follow-refusal.json")[0]


def compact(obj):
    return json.dumps(obj, separators=(",", ":"))


def edited(line, **edits):
    """synthetic: a copy of `line` with each of `edits` set (appended when new,
    so key order is kept), MISSING drops the key."""
    copy = dict(line)
    for key, value in edits.items():
        if value is MISSING:
            copy.pop(key, None)
        else:
            copy[key] = value
    return copy


def step(line):
    return {"line": line}


def raw(text):
    return {"raw": text}


def pause(seconds):
    return {"sleep": seconds}


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am, its script dir and a temp HOME."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "am", FAKE_AM)
    amdir = tmp_path / "am"
    amdir.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    return {"tmp": tmp_path, "bin": bindir, "am": amdir, "home": home}


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


def set_script(world, steps, exit=0, stderr=""):
    (world["am"] / "script.json").write_text(
        json.dumps({"steps": steps, "exit": exit, "stderr": stderr}))


def run_helper(world, args=ARGS, timeout=30, **extra):
    """Run the helper until it exits (default argv: ARGS). Every stdout line must
    be JSON. Returns (exit code, parsed lines, stderr, raw stdout lines)."""
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True,
                       env=env_for(world, **extra), timeout=timeout)
    out = p.stdout.splitlines()
    return p.returncode, [json.loads(line) for line in out], p.stderr, out


def error(kind, message):
    return {"ok": False, "error": {"type": kind, "message": message}}


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def start_helper(world, args=ARGS):
    return subprocess.Popen([sys.executable, SCRIPT, *args], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                            env=env_for(world))


def am_pid(world):
    return int((world["am"] / "pid").read_text())


def assert_gone(pid, within=5.0):
    """The fake am process no longer exists (no orphaned `am logs`)."""
    end = time.monotonic() + within
    while time.monotonic() < end:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    os.kill(pid, signal.SIGKILL)
    pytest.fail("am logs was left running after the helper exited")


def kill_am(world):
    """SIGKILL the recorded fake am if it is still alive (test cleanup only)."""
    pid_file = world["am"] / "pid"
    if not pid_file.exists():
        return
    try:
        os.kill(am_pid(world), signal.SIGKILL)
    except ProcessLookupError:
        pass


def read_lines(p, n, within=5.0):
    """The next `n` stdout lines of the running helper `p`, parsed; fails unless
    all of them arrive within `within` seconds."""
    got = []

    def reader():
        for _ in range(n):
            line = p.stdout.readline()
            if not line:
                return
            got.append(json.loads(line))

    t = threading.Thread(target=reader, daemon=True)
    t.start()
    t.join(within)
    assert len(got) == n and not t.is_alive(), got
    return got


def reap(p):
    """Kill the helper if a test left it running, and close its pipes."""
    if p.poll() is None:
        p.kill()
        p.wait()
    for pipe in (p.stdout, p.stderr):
        if pipe is not None and not pipe.closed:
            pipe.close()


# --- the lines are capture copies -----------------------------------------------

def test_lines_are_capture_copies():
    for name in ("logs-follow-agent.jsonl", "logs-follow-step.jsonl"):
        lines = lines_of(name)
        assert [compact(line) for line in lines] == capture_text(name)
        assert lines[0]["event"] == "logs" and lines[0]["schema"] == 1
        assert lines[-1] == {"event": "end", "status": "ok"}
        assert all("ok" not in line for line in lines)
    assert [compact(refusal())] == capture_text("logs-follow-refusal.json")
    assert refusal()["ok"] is False
    assert "/" + RUN + "/" + CARD + "/" + PHASE + ".1/" in agent()[0]["path"]


# --- argv, Usage, am missing ------------------------------------------------------

@pytest.mark.parametrize("attempt, attempt_flags", [("0", []), ("2", ["--attempt", "2"])],
                         ids=["attempt-0", "attempt-2"])
@pytest.mark.parametrize("offset, offset_flags",
                         [(None, []), ("0", []), ("512", ["--since-offset", "512"])],
                         ids=["no-offset", "offset-0", "offset-512"])
def test_argv(world, attempt, attempt_flags, offset, offset_flags):
    set_script(world, [])
    args = [REPO, RUN, CARD, PHASE, attempt] + ([] if offset is None else [offset])
    code, lines, _, _ = run_helper(world, args)
    assert code == 0
    assert lines == []
    assert calls(world) == [["logs", RUN, CARD, "--phase", PHASE, *attempt_flags, "--follow",
                             *offset_flags, "--repo-dir", REPO]]


@pytest.mark.parametrize("numbers, flags", [
    (["003", "0040"], ["--attempt", "3", "--follow", "--since-offset", "40"]),
    (["00"], ["--follow"]),
    (["00", "000"], ["--follow"]),
], ids=["leading-zeros", "attempt-00", "both-zero"])
def test_argv_leading_zeros(world, numbers, flags):
    set_script(world, [])
    code, _, _, _ = run_helper(world, [REPO, RUN, CARD, PHASE, *numbers])
    assert code == 0
    assert calls(world) == [["logs", RUN, CARD, "--phase", PHASE, *flags, "--repo-dir", REPO]]


def test_argv_values_reach_am_verbatim(world):
    repo, run, card, phase = "/a repo/$(x)", "run;echo pwned", "card`id`", "phase with space"
    set_script(world, [])
    code, _, _, _ = run_helper(world, [repo, run, card, phase, "1"])
    assert code == 0
    assert calls(world) == [["logs", run, card, "--phase", phase, "--attempt", "1", "--follow",
                             "--repo-dir", repo]]


@pytest.mark.parametrize("args", [
    [REPO, RUN, CARD, PHASE],
    [REPO, RUN, CARD, PHASE, "1", "0", "extra"],
    [REPO, RUN, CARD, PHASE, "x"],
    [REPO, RUN, CARD, PHASE, "-1"],
    [REPO, RUN, CARD, PHASE, "1.5"],
    [REPO, RUN, CARD, PHASE, ""],
    [REPO, RUN, CARD, PHASE, "٣"],
    [REPO, RUN, CARD, PHASE, "1", "-5"],
    [REPO, RUN, CARD, PHASE, "1", "abc"],
], ids=["four-args", "seven-args", "attempt-letters", "attempt-negative", "attempt-float",
        "attempt-empty", "attempt-arabic-indic-digit", "offset-negative", "offset-letters"])
def test_usage(world, args):
    set_script(world, [])
    code, lines, _, out = run_helper(world, args)
    assert code == 2
    assert lines == [error("Usage", USAGE)]
    assert out == [compact(error("Usage", USAGE))]
    assert calls(world) == []  # am never spawned


def test_usage_before_am_lookup(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, lines, _, _ = run_helper(world, [REPO, RUN], PATH=str(empty))
    assert code == 2
    assert lines == [error("Usage", USAGE)]


def test_am_missing(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, lines, _, _ = run_helper(world, PATH=str(empty))
    assert code == 0
    assert lines == [error("AmMissing", "am is not installed.")]

# --- passthrough --------------------------------------------------------------------

@pytest.mark.parametrize("name, attempt", [("logs-follow-agent.jsonl", "1"),
                                           ("logs-follow-step.jsonl", "0")],
                         ids=["agent", "step"])
def test_capture_passes_through(world, name, attempt):
    captured = lines_of(name)
    set_script(world, [step(line) for line in captured])
    code, lines, err, out = run_helper(world, [REPO, RUN, CARD, PHASE, attempt])
    assert code == 0
    assert lines == captured
    assert out == capture_text(name)  # compact, key order and values kept
    assert "skipped" not in err


def test_non_objects_skipped_and_counted(world):
    hello, chunk, end = agent()
    set_script(world, [raw("not json"), step(hello), raw("[1,2]"), step(chunk), raw('"s"'),
                       raw("null"), step(end)])
    code, lines, err, _ = run_helper(world)
    assert code == 0
    assert lines == [hello, chunk, end]
    assert "runs-logs-follow: skipped 4 non-JSON lines" in err


def test_unknown_objects_kept(world):
    hello, chunk, end = agent()
    extra = edited(chunk, later="synthetic")
    note = {"event": "note", "detail": [1, {"x": None}]}  # synthetic: a kind this helper does not know
    set_script(world, [step(hello), step(extra), step(note), step(end)])
    code, lines, _, out = run_helper(world)
    assert code == 0
    assert lines == [hello, extra, note, end]
    assert out[1] == compact(extra) and out[2] == compact(note)


def test_non_ascii_text_passes_through(world):
    hello, chunk, end = agent()
    wide = edited(chunk, text="café ✓ — 日本\n")
    set_script(world, [step(hello), raw(json.dumps(wide, separators=(",", ":"), ensure_ascii=False)),
                       step(end)])
    code, lines, err, _ = run_helper(world)
    assert code == 0
    assert lines == [hello, wide, end]
    assert "skipped" not in err


def test_long_chunk_passes_through_whole(world):
    hello, chunk, end = agent()
    big = edited(chunk, text="x" * 1_000_000 + "\n")
    set_script(world, [step(hello), step(big), step(end)])
    code, lines, _, _ = run_helper(world)
    assert code == 0
    assert lines == [hello, big, end]


def test_each_line_flushed_while_am_runs(world):
    hello, chunk, _ = agent()
    set_script(world, [step(hello), step(chunk), pause(30)])
    p = start_helper(world)
    try:
        assert read_lines(p, 2, within=5) == [hello, chunk]
        p.send_signal(signal.SIGTERM)
        p.wait(timeout=10)
    finally:
        reap(p)
        kill_am(world)


def test_am_exit_zero_without_end_line(world):
    hello, chunk, _ = agent()
    set_script(world, [step(hello), step(chunk)])
    code, lines, _, _ = run_helper(world)
    assert code == 0
    assert lines == [hello, chunk]


# --- refusal ------------------------------------------------------------------------

def test_refusal_passes_through(world):
    set_script(world, [step(refusal())], exit=3, stderr="am logs: refused\n")
    code, lines, _, out = run_helper(world)
    assert code == 0
    assert lines == [refusal()]
    assert out == capture_text("logs-follow-refusal.json")


def test_refusal_is_the_only_line(world):
    _, chunk, _ = agent()
    set_script(world, [step(refusal()), step(chunk), raw("noise")], exit=3)
    code, lines, err, _ = run_helper(world)
    assert code == 0
    assert lines == [refusal()]
    assert "skipped" not in err  # later lines are ignored, not counted


def test_refusal_after_a_skipped_line_is_still_the_refusal(world):
    set_script(world, [raw("noise"), step(refusal())], exit=3)
    code, lines, err, _ = run_helper(world)
    assert code == 0
    assert lines == [refusal()]
    assert "skipped 1 non-JSON lines" in err


def test_ok_object_after_a_printed_line_is_skipped(world):
    hello, chunk, end = agent()
    set_script(world, [step(hello), step(refusal()), step(chunk), step(end)])
    code, lines, err, _ = run_helper(world)
    assert code == 0
    assert lines == [hello, chunk, end]
    assert "runs-logs-follow: skipped 1 non-JSON lines" in err
