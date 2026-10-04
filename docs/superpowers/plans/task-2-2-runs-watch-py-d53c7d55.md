<!-- task-pipeline: validated -->
# Task 2.2: runs-watch.py, change signals only (card d53c7d55)

Parent story: 92b4d150 "Run backend helpers". Milestone design: `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` (runs-watch.py description, Refresh model, Errors table, Testing). Blocked by 2.1 (done). Its files (`core/backend/runs/runs-snapshot.py`, `tests/core/backend/runs/test_runs_snapshot.py`) are present in this tree; both directories already exist. Do not modify them. Mirror runs-snapshot.py's conventions (argv-list `am`, `AmMissing` via `shutil.which`, `HelperError` type, failure lines through `emit`).

## Scope

In scope:
- `core/backend/runs/runs-watch.py` (new)
- `tests/core/backend/runs/test_runs_watch.py` (new)

Out of scope: `runs-snapshot.py` (2.1), `runs-logs.py` (2.3), `tests/contract/test_am_shapes.py` (2.4), RunStore.qml, runs.js, any UI, and any `docs/architecture.md` edits.

## Conventions

- Shebang `#!/usr/bin/env python3`. Add a module docstring that states the usage and the output lines.
- Imports are limited to the stdlib plus `core/backend/common`. Reach `common` through `sys.path.insert(0, <parent dir>)`, following `core/backend/documents/list-docs.py`. Every line printed to stdout goes through `from common.json_line import emit`. `emit` does not flush, so call `sys.stdout.flush()` after every `emit` (stdout is a pipe and block-buffered). Do not write a local copy of `emit`, `inside`, `write_atomic`, `split_frontmatter` or `frontmatter_of`, because `tests/architecture/test_layers.py` must still pass unchanged.
- Use only the `am` command and its schema-1 journal contract. Never read am's SQLite or on-disk layout.
- Start `am` with an argv list (`["am", "watch", "--all", "--follow"]`), not through a shell. Resolve `am` from PATH.

## Interface

`runs-watch.py <project-root> [run-id ...]`

This matches 2.1's `<project root>` first-argument convention. With zero run ids the helper is still valid: it watches only for new runs in this project. The helper is long-lived and writes one JSON line per output event to stdout, flushing after each line.

## Observable behavior

1. **Start time.** Record the helper's own start time in UTC before spawning `am`.
2. **Hello line.** The first stream line is `{"am":..,"event":"watch","runs_dir":..,"schema":1}`. Drop it. If `schema != 1`, emit `{"ok":false,"error":{"type":"SchemaMismatch","message":...}}`, terminate `am`, and exit non-zero.
3. **Backlog drop.** Parse each journal line's `ts` (ISO 8601 UTC) and drop the line when `ts` is earlier than the start time. A missing or unparseable `ts` is not provably backlog, so keep the line. Keep this check in one small, clearly named function or block so it can be deleted when `am watch --from-now` lands (S4).
4. **Filter.** Keep a journal line only if one of these holds:
   - its `run_id` is in the watched set, which starts as the argv run ids; or
   - it is a `run_upsert` whose `payload.repo_dir` equals the project root. Compare normalized absolute paths. That run_id is added to the watched set from then on.
   
   Ignore unknown `event` values, extra payload keys and lines that are not JSON. Do not crash on any of them.
5. **Debounce.** Collect the run ids of kept events into a de-duplicated batch. Trailing-edge window: the first kept event into an empty batch starts a 250 ms timer, and when it expires emit exactly one `{"changed":["<run-id>",...]}` line and clear the batch (the next kept event starts a new window). Never emit more than one `changed` line per 250 ms, and never emit an empty one. Emit only run ids, never event contents. Ordering within the list is not part of the contract.
6. **Clean end.** When `am` exits 0 (Ctrl-C or a closed pipe), flush any pending batch and exit 0. On SIGINT, SIGTERM or a broken stdout pipe, terminate the `am` child and exit 0 without a traceback.

## Error paths

| Condition | Output | Exit |
|---|---|---|
| `am` prints a refusal envelope (a line with an `"ok"` key) before the stream | emit `{"ok":false,"error":{"type":"CorruptJournal",...}}` if `am` exits 3 (message from the envelope's error), otherwise re-emit the envelope unchanged, as 2.1 does | non-zero |
| `am` exits 3 mid-stream (stderr `am watch: <msg>`) | flush the pending batch, then emit `{"ok":false,"error":{"type":"CorruptJournal","message":<stderr msg>}}` | non-zero |
| hello `schema != 1` | `{"ok":false,"error":{"type":"SchemaMismatch",...}}` | non-zero |
| `am` exits with any code other than 0 or 3 mid-stream | flush the pending batch, then `{"ok":false,"error":{"type":"HelperError","message":<stderr or exit code>}}` | non-zero |
| `am` not on PATH (optional, mirrors 2.1) | `{"ok":false,"error":{"type":"AmMissing",...}}` | non-zero |

Falling back to polling after a watcher failure is the store's job, not this helper's.

## Tests (TDD: write these first)

All tests live in `tests/core/backend/runs/test_runs_watch.py`, the **backend pytest tier** (`tests/core/backend/<domain>/`, run by the pytest step of `bash tests/run.sh`). This follows the architecture.md "Tests" rule and the spec's Testing section ("stub `am` with recorded fixtures … backlog dropping in `runs-watch.py`, project filtering"). None of these tests go in the contract, architecture, ui or QML tiers.

The tests are hermetic and follow `tests/core/backend/milestones/test_run_setup_milestone.py`. A fake `am` Python script is written to a temp dir, and that dir is prepended to PATH. HOME and XDG_* are pointed at temp. The helper is run with `subprocess` and `sys.executable`, using a path computed from `__file__`. The fake `am` prints a hello line, then fixture journal lines with `ts` set relative to now (past means backlog, future or now means live), then exits with a configurable code and stderr message.

1. `test_drops_hello_and_backlog`: past-`ts` events for a watched run produce no `changed` output.
2. `test_live_event_for_watched_run_emits_changed`: a live event for an argv run id produces `{"changed":[id]}`.
3. `test_filters_unwatched_runs`: live events for other run ids produce no output.
4. `test_new_run_upsert_in_project_is_adopted`: a live `run_upsert` whose `payload.repo_dir` equals the root emits that id, and a later event for that id is also kept. A `run_upsert` for a different repo_dir is ignored.
5. `test_ignores_unknown_events_and_keys`: unknown `event` values and extra payload keys do not crash the helper.
6. `test_schema_mismatch`: a hello line with `schema: 2` produces `SchemaMismatch` and a non-zero exit.
7. `test_exit_3_corrupt_journal`: the fake `am` exits 3 with `am watch: ...` on stderr. Output is `CorruptJournal` with a non-zero exit.
8. `test_debounce_batches_and_dedupes`: a burst of events for two run ids, including repeats, sent within one window yields a single `changed` line containing each id once.
9. `test_debounce_separate_windows`: two events separated by more than 250 ms (the fake `am` sleeps between them) yield two `changed` lines.
10. `test_clean_exit_zero`: when the fake `am` exits 0, the helper exits 0.

Optional, only if AmMissing is implemented: 11. `test_am_missing`, which runs with PATH set to an empty temp dir and expects `AmMissing`.

`bash tests/run.sh` must pass, and `tests/architecture` must pass unchanged.

---

# runs-watch.py Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `core/backend/runs/runs-watch.py`, a long-lived helper that wraps `am watch --all --follow`. It drops the hello line and the backlog, keeps events for watched runs (and adopts new runs of this project), and prints debounced `{"changed":[run ids]}` lines. Tests go in `tests/core/backend/runs/test_runs_watch.py`.

**Architecture:** There is a single stdlib-only script. A reader thread pumps am's stdout lines into a `queue.Queue`, and a second thread collects am's stderr. The main thread runs `stream()`. That loop gets a line with a timeout equal to the time left in the current 250 ms window, runs the line through `keep()` (event check, backlog drop, watched/adopt filter) and flushes the batch when the window expires. Once am's stdout ends, `finish()` maps am's exit code and any refusal envelope to the last line and the exit code. `guarded()` turns SIGINT, SIGTERM and a broken stdout pipe into a quiet exit 0, and `main()` always reaps am in a `finally`.

**Tech Stack:** Python 3 stdlib (`subprocess`, `threading`, `queue`, `datetime`, `signal`), `common.json_line.emit`, pytest (hermetic fake `am` on a temp PATH).

**Spec:** `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-2-2-runs-watch-py-d53c7d55/docs/superpowers/specs/task-2-2-runs-watch-py-d53c7d55-design.md` (copied verbatim above).

**Working directory for every command:** `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-2-2-runs-watch-py-d53c7d55` (branch `mon/task-2-2-runs-watch-py-d53c7d55`). Use `python3 -m pytest`. If `python3 -c 'import pytest'` fails (uv-managed interpreter), use `uv run --with pytest python3 -m pytest` instead, exactly as `tests/run.sh` does.

**Existing code this plan relies on (already on the branch):**
- `core/backend/common/json_line.py`: `emit(payload, code=0)` prints `json.dumps(payload)` and returns `code`. It does not flush.
- `core/backend/runs/runs-snapshot.py` (2.1, do not modify). Its conventions are copied here: `sys.path.insert(0, <parent dir>)`, `failure(kind, message, code=1)`, `Usage` exit 2, `AmMissing` via `shutil.which("am")`, a `guarded()` catch-all giving `HelperError`, and `stdin=subprocess.DEVNULL`.
- `tests/core/backend/runs/test_runs_snapshot.py` (2.1, do not modify). The `world` fixture, `write_exec` and `ROOT`/`SCRIPT` path constants are mirrored in the new test file. Test files are standalone (no shared conftest helpers), so they are copied, not imported.
- `tests/architecture/test_layers.py`: it fails if any `.py` file other than `core/backend/common/json_line.py` contains the text `def emit(` (and likewise `def inside(`, `def write_atomic(`, `def split_frontmatter(`, `def frontmatter_of(`). Neither new file may contain those strings. The flush wrapper is therefore called `say`.

## Global Constraints

- Shebang `#!/usr/bin/env python3` plus a module docstring that states the usage and the output lines.
- Imports: stdlib plus `core/backend/common` only, reached via `sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))`.
- Every stdout line goes through `from common.json_line import emit`, followed by `sys.stdout.flush()`.
- Never define `def emit(`, `def inside(`, `def write_atomic(`, `def split_frontmatter(` or `def frontmatter_of(`.
- Only the `am` command and its schema-1 journal contract. Never read am's SQLite or on-disk layout.
- `am` is spawned as the argv list `[<am from PATH>, "watch", "--all", "--follow"]`, with no shell.
- Interface: `runs-watch.py <project-root> [run-id ...]`. Zero run ids is valid.
- Output `{"changed":[...]}` at most once per 250 ms, never empty, run ids only.
- All tests in `tests/core/backend/runs/test_runs_watch.py` (backend pytest tier). Nothing goes in the contract, architecture, ui or QML tiers.
- Do not modify `runs-snapshot.py`, `test_runs_snapshot.py`, RunStore.qml, runs.js, any UI, `docs/architecture.md` or `tests/contract/`.
- `bash ./tests/run.sh` must pass, and `tests/architecture` must pass unchanged.

## Review Focus

Each input or condition below is implied by the spec but not covered by the spec's ten listed tests. Each now has a test in its owning task.

1. A journal line with a missing or unparseable `ts` is kept, because it is not provably backlog. Test: `test_missing_or_unparseable_ts_is_kept` (Task 2).
2. A continuous stream (an event every 50 ms for over a second) still gets periodic `changed` lines and never more than one per 250 ms. Test: `test_debounce_continuous_stream_is_rate_limited` (Task 3).
3. A `run_upsert` whose `payload.repo_dir` is the project root written differently (trailing `/`, `/./`) is still adopted. Test: `test_new_run_upsert_in_project_is_adopted` parametrized over path forms (Task 4).
4. If `am` exits with a code other than 0 or 3, or prints a refusal envelope, the user sees one error line rather than silence. Tests: `test_other_exit_is_helper_error`, `test_refusal_exit_3_is_corrupt_journal`, `test_refusal_other_exit_is_reemitted` (Task 5).
5. When the store stops the helper (SIGTERM or SIGINT) or closes its stdout, the helper exits 0 with no traceback and leaves no orphaned `am watch` process. Tests: `test_signal_stops_am_and_exits_zero`, `test_closed_stdout_exits_zero` (Task 6).

---

## File Structure

- `core/backend/runs/runs-watch.py` (create). The whole helper. It contains these functions:
  - `say` (emit + flush) and `failure`.
  - `parse_ts`, plus `is_backlog`, the isolated S4-removable block.
  - `same_dir`, `keep` (event/backlog/watched/adopt filter) and `check_schema`.
  - `spawn`, `pump`, `collect` and `stop` (child process I/O).
  - `stream` (debounce loop), `finish` (exit-code mapping) and `main`.
  - `on_signal`, `quiet_exit` and `guarded`.
- `tests/core/backend/runs/test_runs_watch.py` (create). Holds the fake `am`, the fixtures and all tests.

---

### Task 1: Skeleton: usage, AmMissing, spawn `am`, clean exit 0

**Files:**
- Create: `tests/core/backend/runs/test_runs_watch.py`
- Create: `core/backend/runs/runs-watch.py`

**Interfaces:**
- Consumes: `common.json_line.emit(payload, code=0)`.
- Produces (script): `say(payload, code=0) -> int`, `failure(kind: str, message: str, code: int = 1) -> int`, `spawn(am: str) -> subprocess.Popen` (text mode), `pump(stream, sink: queue.Queue)` (puts each raw line, then the `EOF` sentinel), `collect(stream, parts: list)`, `stop(proc)`, `main(argv: list[str]) -> int`, `guarded(argv) -> int`. The constants are `USAGE`, `IDLE_POLL = 1.0` and `EOF = object()`.
- Produces (tests): the `FAKE_AM` script, the `MISSING` sentinel and these helpers: `world` fixture (keys `tmp`, `bin`, `am`, `home`, `proj`), `env_for(world, **extra) -> dict`, `hello(schema=1) -> step`, `ev(run_id, event="phase_upsert", ts="NOW", payload=None, **extra) -> step`, `upsert(run_id, repo_dir, ts="NOW") -> step`, `pause(seconds) -> step`, `raw(text) -> step`, `set_script(world, steps, exit=0, stderr="")`, `run_helper(world, args=None, timeout=30, **extra) -> (code, lines, stderr)`, `changed(lines) -> list[list[str]]` and `calls(world) -> list[list[str]]`.

- [ ] **Step 1: Write the failing tests (harness + three tests)**

Create `tests/core/backend/runs/test_runs_watch.py`:

```python
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q`
Expected: 3 failed. The script does not exist, so Python exits 2 with "can't open file" and stdout is empty. `test_clean_exit_zero` fails on `assert code == 0`, and `test_usage` and `test_am_missing` fail on `assert len(lines) == 1`.

- [ ] **Step 3: Write the minimal implementation**

Create `core/backend/runs/runs-watch.py`:

```python
#!/usr/bin/env python3
"""Signal which watched am runs changed, from `am watch --all --follow`.

    runs-watch.py <project_root> [run_id ...]

Long-lived. Spawns `am watch --all --follow` (an argv list, never a shell) and
prints one JSON line per output event, flushed at once:
  {"changed": ["<run id>", ...]}  at most once per 250 ms, never empty, run ids
                                  only (event contents are never forwarded)
  {"ok": false, "error": {"type", "message"}}  then exit 1, with type
                                  SchemaMismatch, CorruptJournal, HelperError or
                                  AmMissing (Usage exits 2); an am refusal
                                  envelope with an exit other than 3 is
                                  re-emitted unchanged.
The hello line is dropped (its schema must be 1). Journal lines written before
the helper started (the backlog) are dropped. A journal line is kept when its
event is one of the five schema-1 events and its run id is watched: the argv run
ids, plus every run whose run_upsert payload.repo_dir is this project root.
Unknown events, unknown keys and non-JSON lines are ignored. am exiting 0,
SIGINT, SIGTERM or a closed stdout end the helper with exit 0. Only the `am`
command is used; am's database and on-disk layout are never read.
"""
import os
import queue
import shutil
import subprocess
import sys
import threading

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-watch.py <project_root> [run_id ...]"
IDLE_POLL = 1.0  # seconds; the longest the main loop blocks with nothing pending
EOF = object()


def say(payload, code=0):
    """emit() one line and flush it now: stdout is a pipe, so it is block-buffered."""
    emit(payload)
    sys.stdout.flush()
    return code


def failure(kind, message, code=1):
    return say({"ok": False, "error": {"type": kind, "message": message}}, code)


def spawn(am):
    return subprocess.Popen([am, "watch", "--all", "--follow"], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, encoding="utf-8", errors="replace")


def pump(stream, sink):
    """Reader thread: every line am prints, then EOF."""
    for raw in stream:
        sink.put(raw)
    sink.put(EOF)


def collect(stream, parts):
    """Reader thread: am's whole stderr, so a chatty am never blocks on a full pipe."""
    parts.append(stream.read())


def stop(proc):
    """Terminate am if it is still running, and reap it."""
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def stream(lines):
    """Drain am's stream until it ends."""
    while True:
        try:
            raw = lines.get(timeout=IDLE_POLL)
        except queue.Empty:
            continue
        if raw is EOF:
            return


def main(argv):
    if not argv:
        return failure("Usage", USAGE, 2)
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    proc = spawn(am)
    lines, err = queue.Queue(), []
    threading.Thread(target=pump, args=(proc.stdout, lines), daemon=True).start()
    err_reader = threading.Thread(target=collect, args=(proc.stderr, err), daemon=True)
    err_reader.start()
    try:
        stream(lines)
        code = proc.wait()
        err_reader.join(timeout=2)
    finally:
        stop(proc)
    return 0 if code == 0 else 1


def guarded(argv):
    """No unexpected exception may end the helper without a JSON line."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The runs watch failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_watch.py tests/architecture -q`
Expected: all pass. The architecture tests pass because there is no second `def emit(`.

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-watch.py tests/core/backend/runs/test_runs_watch.py
git commit -m "feat(runs): runs-watch.py skeleton spawning am watch --all --follow"
```

---

### Task 2: Backlog drop, watched-run filter, unknown input ignored (one batch flushed at EOF)

**Files:**
- Modify: `core/backend/runs/runs-watch.py` (imports, constants, new `parse_ts`/`is_backlog`/`keep`, replace `stream` and `main`)
- Test: `tests/core/backend/runs/test_runs_watch.py` (append)

**Interfaces:**
- Consumes: `say`, `EOF`, `IDLE_POLL`, `spawn`, `pump`, `collect` and `stop` from Task 1, plus the test helpers from Task 1.
- Produces: `EVENTS: frozenset[str]`, `parse_ts(value) -> datetime | None`, `is_backlog(line: dict, started: datetime) -> bool`, `keep(line, watched: set[str], started: datetime) -> str | None` (Task 4 widens it to `keep(line, watched, root, started)`) and `stream(lines, watched, started) -> None`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/core/backend/runs/test_runs_watch.py`:

```python


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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q`
Expected: 4 failed. `test_drops_hello_and_backlog` gives `[] == [['r2']]`. `test_live_event_for_watched_run_emits_changed` gives `[] == [{'changed': ['r1']}]`. `test_ignores_unknown_events_and_keys` and `test_missing_or_unparseable_ts_is_kept` also fail with empty output. `test_filters_unwatched_runs` already passes, because Task 1 prints nothing. It is a guard for this task's filter.

- [ ] **Step 3: Write the minimal implementation**

In `core/backend/runs/runs-watch.py`, replace the import block:

```python
import os
import queue
import shutil
import subprocess
import sys
import threading
```

with:

```python
import datetime
import json
import os
import queue
import shutil
import subprocess
import sys
import threading
```

Replace the constants block:

```python
USAGE = "usage: runs-watch.py <project_root> [run_id ...]"
IDLE_POLL = 1.0  # seconds; the longest the main loop blocks with nothing pending
EOF = object()
```

with:

```python
USAGE = "usage: runs-watch.py <project_root> [run_id ...]"
IDLE_POLL = 1.0  # seconds; the longest the main loop blocks with nothing pending
EOF = object()
# The schema-1 journal events. Any other `event` value is ignored.
EVENTS = frozenset({"run_upsert", "story_upsert", "subtask_upsert", "phase_upsert",
                    "attempt_upsert"})
```

Directly after the `failure` function, insert:

```python


def parse_ts(value):
    """A journal `ts` (ISO 8601, UTC, usually ending in Z) as an aware datetime,
    or None when it is missing or unparseable."""
    if not isinstance(value, str):
        return None
    text = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        ts = datetime.datetime.fromisoformat(text)
    except ValueError:
        return None
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=datetime.timezone.utc)
    return ts


# --- Backlog drop (S4 workaround) ------------------------------------------------
# `am watch --follow` replays every journal line before going live. Until
# `am watch --from-now` exists (S4), lines written before this helper started
# are dropped here. When S4 lands: pass --from-now in spawn(), delete this
# function, and delete its one call in keep().
def is_backlog(line, started):
    ts = parse_ts(line.get("ts"))
    return ts is not None and ts < started


def keep(line, watched, started):
    """The run id a parsed stream line signals, or None to ignore the line."""
    if not isinstance(line, dict):
        return None
    run_id = line.get("run_id")
    if not (isinstance(run_id, str) and run_id) or line.get("event") not in EVENTS:
        return None
    if is_backlog(line, started):
        return None
    return run_id if run_id in watched else None
```

Replace the whole `stream` function with:

```python
def stream(lines, watched, started):
    """Collect the run ids of kept lines until am's stream ends, then print them."""
    batch = []
    while True:
        try:
            raw = lines.get(timeout=IDLE_POLL)
        except queue.Empty:
            continue
        if raw is EOF:
            if batch:
                say({"changed": batch})
            return
        try:
            line = json.loads(raw)
        except ValueError:
            continue
        run_id = keep(line, watched, started)
        if run_id is not None and run_id not in batch:
            batch.append(run_id)
```

Replace the whole `main` function with:

```python
def main(argv):
    if not argv:
        return failure("Usage", USAGE, 2)
    watched = set(argv[1:])
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    started = datetime.datetime.now(datetime.timezone.utc)  # before am starts
    proc = spawn(am)
    lines, err = queue.Queue(), []
    threading.Thread(target=pump, args=(proc.stdout, lines), daemon=True).start()
    err_reader = threading.Thread(target=collect, args=(proc.stderr, err), daemon=True)
    err_reader.start()
    try:
        stream(lines, watched, started)
        code = proc.wait()
        err_reader.join(timeout=2)
    finally:
        stop(proc)
    return 0 if code == 0 else 1
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q`
Expected: 8 passed.

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-watch.py tests/core/backend/runs/test_runs_watch.py
git commit -m "feat(runs): runs-watch drops backlog and keeps only watched runs"
```

---

### Task 3: 250 ms trailing-edge debounce

**Files:**
- Modify: `core/backend/runs/runs-watch.py` (imports, `WINDOW` constant, replace `stream`)
- Test: `tests/core/backend/runs/test_runs_watch.py` (append)

**Interfaces:**
- Consumes: `keep(line, watched, started)`, `say`, `EOF` and `IDLE_POLL` from earlier tasks.
- Produces: `WINDOW = 0.25` and `stream(lines, watched, started) -> None`, now flushing on the window boundary as well as at EOF.

- [ ] **Step 1: Write the failing tests**

Append to `tests/core/backend/runs/test_runs_watch.py`:

```python


# --- debounce -------------------------------------------------------------------

def test_debounce_batches_and_dedupes(world):
    set_script(world, [hello(), ev("r1"), ev("r2"), ev("r1"), ev("r2", "attempt_upsert"),
                       ev("r1", "subtask_upsert"), pause(0.6)])
    code, lines, _ = run_helper(world, [str(world["proj"]), "r1", "r2"])
    assert code == 0
    assert changed(lines) == [["r1", "r2"]]


def test_debounce_separate_windows(world):
    set_script(world, [hello(), ev("r1"), pause(0.6), ev("r1"), pause(0.6)])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert changed(lines) == [["r1"], ["r1"]]


def test_debounce_continuous_stream_is_rate_limited(world):
    # An event every 50 ms for over a second: the window must still close on
    # time (more than one line), and lines never come faster than one per 250 ms.
    steps = [hello()]
    for _ in range(20):
        steps += [ev("r1"), pause(0.05)]
    set_script(world, steps)
    began = time.monotonic()
    code, lines, _ = run_helper(world)
    elapsed = time.monotonic() - began
    assert code == 0
    got = changed(lines)
    assert all(ids == ["r1"] for ids in got)
    assert len(got) >= 2, got
    assert len(got) <= int(elapsed / 0.25) + 1, (len(got), elapsed)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q -k debounce`
Expected: 2 failed. `test_debounce_separate_windows` gives `[['r1']] == [['r1'], ['r1']]`, and `test_debounce_continuous_stream_is_rate_limited` fails `len(got) >= 2` with `[['r1']]`. `test_debounce_batches_and_dedupes` already passes, because the EOF flush batches everything. It guards the dedupe once the timer exists.

- [ ] **Step 3: Write the minimal implementation**

In `core/backend/runs/runs-watch.py`, replace:

```python
import threading
```

with:

```python
import threading
import time
```

Replace:

```python
IDLE_POLL = 1.0  # seconds; the longest the main loop blocks with nothing pending
```

with:

```python
IDLE_POLL = 1.0  # seconds; the longest the main loop blocks with nothing pending
WINDOW = 0.25  # seconds; at most one {"changed": [...]} line per window
```

Replace the whole `stream` function with:

```python
def stream(lines, watched, started):
    """Turn am's stream into debounced {"changed": [...]} lines until it ends.
    Trailing edge: the first kept run id into an empty batch opens a WINDOW;
    when it closes the batch is printed once and cleared."""
    batch, deadline = [], None
    while True:
        if deadline is not None and time.monotonic() >= deadline:
            say({"changed": batch})
            batch, deadline = [], None
        wait = IDLE_POLL if deadline is None else max(0.0, deadline - time.monotonic())
        try:
            raw = lines.get(timeout=wait)
        except queue.Empty:
            continue
        if raw is EOF:
            if batch:
                say({"changed": batch})
            return
        try:
            line = json.loads(raw)
        except ValueError:
            continue
        run_id = keep(line, watched, started)
        if run_id is not None and run_id not in batch:
            batch.append(run_id)
            if deadline is None:
                deadline = time.monotonic() + WINDOW
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q`
Expected: 11 passed.

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-watch.py tests/core/backend/runs/test_runs_watch.py
git commit -m "feat(runs): runs-watch debounces change signals to one line per 250 ms"
```

---

### Task 4: Adopt new runs of this project via `run_upsert.payload.repo_dir`

**Files:**
- Modify: `core/backend/runs/runs-watch.py` (new `same_dir`, replace `keep`, `stream` and `main`)
- Test: `tests/core/backend/runs/test_runs_watch.py` (append)

**Interfaces:**
- Consumes: `EVENTS`, `is_backlog`, `say`, `EOF`, `IDLE_POLL` and `WINDOW` from earlier tasks.
- Produces: `same_dir(a: str, b: str) -> bool`, `keep(line, watched: set[str], root: str, started) -> str | None` (it mutates `watched` on adoption) and `stream(lines, watched, root, started) -> None`.

- [ ] **Step 1: Write the failing test**

Append to `tests/core/backend/runs/test_runs_watch.py`:

```python


# --- adoption of new runs in this project -------------------------------------

@pytest.mark.parametrize("form", ["exact", "trailing-slash", "dot-segment"])
def test_new_run_upsert_in_project_is_adopted(world, form):
    root = str(world["proj"])
    repo_dir = {"exact": root, "trailing-slash": root + "/", "dot-segment": root + "/./"}[form]
    set_script(world, [
        hello(),
        upsert("n1", repo_dir),                  # this project: adopted and signalled
        upsert("n2", "/somewhere/else"),         # other repo: ignored
        ev("n2"),                                # still not watched
        pause(0.6),
        ev("n1"),                                # adopted: kept from now on
        pause(0.6),
    ])
    code, lines, _ = run_helper(world, [root])  # zero run ids on argv is valid
    assert code == 0
    assert changed(lines) == [["n1"], ["n1"]]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q -k adopted`
Expected: 3 failed, each with `[] == [['n1'], ['n1']]`.

- [ ] **Step 3: Write the minimal implementation**

In `core/backend/runs/runs-watch.py`, replace the whole `keep` function with:

```python
def same_dir(a, b):
    """True when two paths name the same directory (normalized, absolute)."""
    return os.path.realpath(a) == os.path.realpath(b)


def keep(line, watched, root, started):
    """The run id a parsed stream line signals, or None to ignore the line. A
    live run_upsert whose payload.repo_dir is the project root adds its run to
    `watched` for good."""
    if not isinstance(line, dict):
        return None
    run_id = line.get("run_id")
    if not (isinstance(run_id, str) and run_id) or line.get("event") not in EVENTS:
        return None
    if is_backlog(line, started):
        return None
    if run_id in watched:
        return run_id
    payload = line.get("payload")
    if (line["event"] == "run_upsert" and isinstance(payload, dict)
            and isinstance(payload.get("repo_dir"), str)
            and same_dir(payload["repo_dir"], root)):
        watched.add(run_id)
        return run_id
    return None
```

In the `stream` function, replace the signature line:

```python
def stream(lines, watched, started):
```

with:

```python
def stream(lines, watched, root, started):
```

and replace the line:

```python
        run_id = keep(line, watched, started)
```

with:

```python
        run_id = keep(line, watched, root, started)
```

In `main`, replace:

```python
    watched = set(argv[1:])
```

with:

```python
    root, watched = argv[0], set(argv[1:])
```

and replace:

```python
        stream(lines, watched, started)
```

with:

```python
        stream(lines, watched, root, started)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q`
Expected: 14 passed.

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-watch.py tests/core/backend/runs/test_runs_watch.py
git commit -m "feat(runs): runs-watch adopts new runs of this project"
```

---

### Task 5: Error paths: SchemaMismatch, CorruptJournal (exit 3 and refusal), HelperError

**Files:**
- Modify: `core/backend/runs/runs-watch.py` (new `SchemaMismatch`, `check_schema` and `finish`; replace `stream` and `main`)
- Test: `tests/core/backend/runs/test_runs_watch.py` (append)

**Interfaces:**
- Consumes: `keep(line, watched, root, started)`, `say`, `failure`, `spawn`, `pump`, `collect`, `stop`, `EOF`, `IDLE_POLL` and `WINDOW`.
- Produces: `class SchemaMismatch(Exception)`, `check_schema(hello: dict) -> None` (raises `SchemaMismatch`), `stream(lines, watched, root, started) -> dict | None` (returns the refusal envelope if am printed one) and `finish(code: int, refusal: dict | None, stderr: str) -> int`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/core/backend/runs/test_runs_watch.py`:

```python


# --- error paths -----------------------------------------------------------------

@pytest.mark.parametrize("schema", [2, "1", MISSING], ids=["two", "string-one", "missing"])
def test_schema_mismatch(world, schema):
    # am would keep streaming for 8 s; the helper must stop it and leave at once.
    set_script(world, [hello(schema), ev("r1"), pause(8)])
    began = time.monotonic()
    code, lines, _ = run_helper(world)
    assert time.monotonic() - began < 5
    assert code != 0
    assert len(lines) == 1, lines
    assert lines[0]["ok"] is False
    assert lines[0]["error"]["type"] == "SchemaMismatch"
    assert lines[0]["error"]["message"]


def test_exit_3_corrupt_journal(world):
    set_script(world, [hello(), ev("r1")], exit=3,
               stderr="am watch: journal line 4 of run r1 is not JSON\n")
    code, lines, _ = run_helper(world)
    assert code != 0
    assert len(lines) == 2, lines
    assert lines[0] == {"changed": ["r1"]}  # the pending batch is flushed first
    assert lines[1]["ok"] is False
    assert lines[1]["error"]["type"] == "CorruptJournal"
    assert "journal line 4 of run r1 is not JSON" in lines[1]["error"]["message"]


def test_other_exit_is_helper_error(world):
    set_script(world, [hello(), ev("r1")], exit=1, stderr="boom\n")
    code, lines, _ = run_helper(world)
    assert code != 0
    assert len(lines) == 2, lines
    assert lines[0] == {"changed": ["r1"]}
    assert lines[1]["ok"] is False
    assert lines[1]["error"]["type"] == "HelperError"
    assert "boom" in lines[1]["error"]["message"]


def test_refusal_exit_3_is_corrupt_journal(world):
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
    envelope = {"error": {"message": "something else", "type": "OddError"}, "ok": False}
    set_script(world, [{"line": envelope}], exit=0)
    code, lines, _ = run_helper(world)
    assert code != 0
    assert lines == [envelope]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q -k "schema or exit or refusal"`
Expected: 7 failed (`test_clean_exit_zero` is selected by `-k exit` and still passes). In detail:
- The `test_schema_mismatch` cases fail on the elapsed-time assertion. Task 4 ignores the hello line and waits about 8 s for am.
- `test_exit_3_corrupt_journal` and `test_other_exit_is_helper_error` fail on `len(lines) == 2`, because only the changed line is printed.
- The refusal tests fail on an empty output.

- [ ] **Step 3: Write the minimal implementation**

In `core/backend/runs/runs-watch.py`, directly after the constants block (after the `EVENTS = ...` assignment), insert:

```python


class SchemaMismatch(Exception):
    """The hello line announced a journal schema other than 1."""
```

Directly after the `keep` function, insert:

```python


def check_schema(hello):
    schema = hello.get("schema")
    if not (type(schema) is int and schema == 1):
        raise SchemaMismatch("am watch speaks journal schema " + json.dumps(schema)
                             + "; this helper reads schema 1.")
```

Replace the whole `stream` function with:

```python
def stream(lines, watched, root, started):
    """Turn am's stream into debounced {"changed": [...]} lines until it ends.
    Trailing edge: the first kept run id into an empty batch opens a WINDOW;
    when it closes the batch is printed once and cleared. A pending batch is
    printed when the stream ends. Returns am's refusal envelope (the only line
    with an "ok" key) if it printed one, else None. Raises SchemaMismatch."""
    batch, deadline, refusal = [], None, None
    while True:
        if deadline is not None and time.monotonic() >= deadline:
            say({"changed": batch})
            batch, deadline = [], None
        wait = IDLE_POLL if deadline is None else max(0.0, deadline - time.monotonic())
        try:
            raw = lines.get(timeout=wait)
        except queue.Empty:
            continue
        if raw is EOF:
            if batch:
                say({"changed": batch})
            return refusal
        try:
            line = json.loads(raw)
        except ValueError:
            continue
        if isinstance(line, dict) and "ok" in line:
            refusal = line
            continue
        if isinstance(line, dict) and line.get("event") == "watch":
            check_schema(line)
            continue
        run_id = keep(line, watched, root, started)
        if run_id is not None and run_id not in batch:
            batch.append(run_id)
            if deadline is None:
                deadline = time.monotonic() + WINDOW
```

Directly after the `stream` function, insert:

```python


def finish(code, refusal, stderr):
    """Print the last line, if any, for how am ended; return the helper's exit code."""
    if refusal is not None:
        if code != 3:
            return say(refusal, 1)
        error = refusal.get("error")
        message = error.get("message") if isinstance(error, dict) else None
        if not (isinstance(message, str) and message):
            message = stderr or "am watch refused with exit 3."
        return failure("CorruptJournal", message)
    if code == 0:
        return 0
    if code == 3:
        return failure("CorruptJournal", stderr or "am watch exited 3.")
    return failure("HelperError", stderr or "am watch exited " + str(code) + ".")
```

Replace the whole `main` function with:

```python
def main(argv):
    if not argv:
        return failure("Usage", USAGE, 2)
    root, watched = argv[0], set(argv[1:])
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    started = datetime.datetime.now(datetime.timezone.utc)  # before am starts
    proc = spawn(am)
    lines, err = queue.Queue(), []
    threading.Thread(target=pump, args=(proc.stdout, lines), daemon=True).start()
    err_reader = threading.Thread(target=collect, args=(proc.stderr, err), daemon=True)
    err_reader.start()
    try:
        try:
            refusal = stream(lines, watched, root, started)
        except SchemaMismatch as e:
            return failure("SchemaMismatch", str(e))
        code = proc.wait()
        err_reader.join(timeout=2)
    finally:
        stop(proc)  # no-op once am has exited; terminates it on every other path
    return finish(code, refusal, "".join(err).strip())
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q`
Expected: 21 passed.

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-watch.py tests/core/backend/runs/test_runs_watch.py
git commit -m "feat(runs): runs-watch reports SchemaMismatch, CorruptJournal and HelperError"
```

---

### Task 6: SIGINT, SIGTERM and closed stdout end quietly with exit 0 and stop `am`

**Files:**
- Modify: `core/backend/runs/runs-watch.py` (import `signal`, new `Stop`/`on_signal`/`quiet_exit`, replace `guarded`)
- Test: `tests/core/backend/runs/test_runs_watch.py` (append)

**Interfaces:**
- Consumes: `main(argv)` (its `finally: stop(proc)` reaps am on every exit path) and `failure`.
- Produces: `class Stop(Exception)`, `on_signal(signum, frame)` (raises `Stop`), `quiet_exit() -> int` (returns 0) and `guarded(argv) -> int`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/core/backend/runs/test_runs_watch.py`:

```python


# --- stopping: signals and a closed stdout ---------------------------------------

def start_helper(world, args=None):
    argv = [str(world["proj"]), "r1"] if args is None else args
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
    set_script(world, [hello(), ev("r1"), pause(30)])
    p = start_helper(world)
    try:
        first = p.stdout.readline()  # sync point: am is running, helper is streaming
        assert json.loads(first) == {"changed": ["r1"]}
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
    set_script(world, [hello(), ev("r1"), pause(0.6), ev("r1"), pause(30)])
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q -k "signal or closed_stdout"`
Expected: 3 failed.
- SIGTERM: `assert code == 0` fails with -15. The default action kills the helper, so am may be orphaned.
- SIGINT: the catch-all prints a HelperError line and exits 1.
- Closed stdout: the BrokenPipeError escapes the catch-all's own print, which gives exit 1 and a "Traceback" on stderr.

- [ ] **Step 3: Write the minimal implementation**

In `core/backend/runs/runs-watch.py`, replace:

```python
import shutil
import subprocess
```

with:

```python
import shutil
import signal
import subprocess
```

Directly after the `SchemaMismatch` class, insert:

```python


class Stop(Exception):
    """SIGINT or SIGTERM: the store (or a user) is done with this watch."""


def on_signal(signum, frame):
    raise Stop()
```

Replace the whole `guarded` function with:

```python
def quiet_exit():
    """Ended by a signal or a closed stdout: exit 0 without a traceback. stdout
    is pointed at /dev/null so the interpreter's final flush cannot raise."""
    try:
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
    except OSError:
        pass
    return 0


def guarded(argv):
    """SIGINT, SIGTERM and a closed stdout end the helper quietly with exit 0
    (main's finally has already stopped am). Any other unexpected exception
    still ends with one HelperError line."""
    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)  # explicit: SIGINT may be inherited as ignored
    try:
        return main(argv)
    except (Stop, KeyboardInterrupt, BrokenPipeError):
        return quiet_exit()
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        try:
            return failure("HelperError", "The runs watch failed: " + reason)
        except BrokenPipeError:
            return quiet_exit()
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q`
Expected: 24 passed.

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-watch.py tests/core/backend/runs/test_runs_watch.py
git commit -m "feat(runs): runs-watch exits 0 and stops am on SIGINT, SIGTERM or closed stdout"
```

---

### Task 7: Full verification

**Files:**
- None modified. This task only verifies the earlier ones.

**Interfaces:**
- Consumes: everything above.
- Produces: nothing new.

- [ ] **Step 1: Make the script executable like its siblings**

Run: `ls -l core/backend/runs/runs-snapshot.py core/backend/runs/runs-watch.py`
If `runs-snapshot.py` has the `x` bit and `runs-watch.py` does not, run `chmod +x core/backend/runs/runs-watch.py` and then `git add core/backend/runs/runs-watch.py && git commit -m "chore(runs): make runs-watch.py executable"`. If neither has it, do nothing.

- [ ] **Step 2: Check the architecture tier is unchanged and passes**

Run: `python3 -m pytest tests/architecture -q && git status --short tests/architecture`
Expected: all pass, and `git status` prints nothing for `tests/architecture`.

- [ ] **Step 3: Check the forbidden strings are absent from both new files**

Run: `grep -nE "def (emit|inside|write_atomic|split_frontmatter|frontmatter_of)\(|sqlite|shell=True" core/backend/runs/runs-watch.py tests/core/backend/runs/test_runs_watch.py`
Expected: no output (grep exits 1).

- [ ] **Step 4: Run the repo's full verification**

Run: `bash ./tests/run.sh`
Expected: the pytest step passes, including the 24 tests in `tests/core/backend/runs/test_runs_watch.py` and the unchanged `test_runs_snapshot.py`. Every QML test reports `Totals` with 0 failed, and the script exits 0.

- [ ] **Step 5: Confirm only in-scope files changed on the branch**

Run: `git diff --stat mon/task-2-1-runs-snapshot-py-1f3833c1...HEAD`
Expected: the only changes are `core/backend/runs/runs-watch.py`, `tests/core/backend/runs/test_runs_watch.py` and the spec/plan docs under `docs/superpowers/`.
