"""runs-watch.py: `am watch --all --follow` turned into debounced change signals.

Hermetic: a fake `am` on a temp PATH replays FAKE_AM_DIR/script.json: a list of
steps (a JSON line, raw text, or a sleep), then a chosen stderr text and exit
code. A step line's "ts" of "PAST" (an hour ago) or "NOW" is stamped at the
moment the fake am prints it, so PAST is backlog and NOW is live for the helper,
which records its start time before spawning am. The fake am logs its argv to
calls.log and its pid to pid. HOME and XDG_* are temp. The real `am` and real
data are never touched.
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


def hello(schema=1):
    """The --follow hello line; pass schema=MISSING to leave the key out."""
    line = {"am": "0.1.0", "event": "watch", "runs_dir": "/nowhere/agent-manager/runs"}
    if schema is not MISSING:
        line["schema"] = schema
    return {"line": line}


def ev(run_id, event="phase_upsert", ts="NOW", payload=None, **extra):
    """One schema-1 journal line. ts=None leaves the key out; extra keys are added
    to (or override) the top level."""
    line = {"seq": 1, "ts": ts, "run_id": run_id, "event": event, "story": "s1",
            "card": "c1", "phase": "implement", "attempt": None,
            "payload": {"name": "implement", "status": "started"} if payload is None else payload}
    if ts is None:
        del line["ts"]
    line.update(extra)
    return {"line": line}


def upsert(run_id, repo_dir, ts="NOW"):
    """A run_upsert, the first line of every run, carrying its repo_dir."""
    return ev(run_id, "run_upsert", ts,
              {"id": run_id, "repo_dir": repo_dir, "milestone_id": None, "status": "started"},
              story=None, card=None, phase=None)


def pause(seconds):
    return {"sleep": seconds}


def raw(text):
    return {"raw": text}


def set_script(world, steps, exit=0, stderr=""):
    (world["am"] / "script.json").write_text(
        json.dumps({"steps": steps, "exit": exit, "stderr": stderr}))


def run_helper(world, args=None, timeout=30, **extra):
    """Run the helper until it exits (default argv: project root, run id r1).
    Every stdout line must be JSON. Returns (exit code, parsed lines, stderr)."""
    argv = [str(world["proj"]), "r1"] if args is None else args
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


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


# --- usage, am missing, clean exit --------------------------------------------

def test_clean_exit_zero(world):
    set_script(world, [hello()])
    code, lines, err = run_helper(world)
    assert code == 0
    assert lines == []
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

def test_drops_hello_and_backlog(world):
    # r1's lines were written an hour before the helper started: backlog, dropped.
    # r2's line is live and proves the helper is reading at all.
    set_script(world, [hello(), ev("r1", ts="PAST"), ev("r1", "subtask_upsert", ts="PAST"),
                       ev("r2")])
    code, lines, _ = run_helper(world, [str(world["proj"]), "r1", "r2"])
    assert code == 0
    assert changed(lines) == [["r2"]]


def test_live_event_for_watched_run_emits_changed(world):
    set_script(world, [hello(), ev("r1")])
    code, lines, _ = run_helper(world)
    assert code == 0
    # Exactly this object: run ids only, no event contents.
    assert lines == [{"changed": ["r1"]}]


def test_filters_unwatched_runs(world):
    set_script(world, [hello(), ev("r9"), ev("r8", "attempt_upsert"),
                       upsert("r7", "/somewhere/else")])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == []


def test_ignores_unknown_events_and_keys(world):
    set_script(world, [
        hello(),
        raw("not json"),
        raw("[1, 2]"),
        raw(""),
        ev("r2", "future_upsert"),                     # unknown event: ignored
        {"line": {"event": "phase_upsert", "ts": "NOW"}},  # no run_id: ignored
        ev("r1", payload={"name": "implement", "status": "done", "shiny": {"new": 1}},
           brand_new_key=[1, 2, 3]),                   # extra keys: kept
    ])
    code, lines, err = run_helper(world, [str(world["proj"]), "r1", "r2"])
    assert code == 0
    assert "Traceback" not in err
    assert changed(lines) == [["r1"]]


def test_missing_or_unparseable_ts_is_kept(world):
    # Not provably backlog, so kept.
    set_script(world, [hello(), ev("r1", ts=None), ev("r2", ts="yesterday-ish")])
    code, lines, _ = run_helper(world, [str(world["proj"]), "r1", "r2"])
    assert code == 0
    assert changed(lines) == [["r1", "r2"]]
