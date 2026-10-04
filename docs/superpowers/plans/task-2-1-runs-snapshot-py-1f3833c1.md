<!-- task-pipeline: validated -->
# 2.1 runs-snapshot.py: list runs and their status (card 1f3833c1)

Parent story: 92b4d150 "Run backend helpers". Milestone design: `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` (the "monitor spec" below). This document narrows that design to one helper and its tests.

## Scope

In scope:
- `core/backend/runs/runs-snapshot.py`, a new file in a new directory.
- `tests/core/backend/runs/test_runs_snapshot.py`, a new file in a new directory.

Out of scope, because these belong to sibling cards or later stories: `runs-watch.py` (2.2), `runs-logs.py` (2.3), `tests/contract/test_am_shapes.py` (2.4), `core/domain/runs.js` and its `normalizeRun`, `RunStore.qml`, any UI or navigation, timers, polling, debounce, and the journal. This card adds no `docs/architecture.md` changes beyond, at most, one line that names the new `core/backend/runs/` directory.

## Constraints

- Imports are limited to the Python stdlib and `core/backend/common` (`docs/architecture.md` layering). Use the header idiom from `core/backend/documents/list-docs.py`: insert the parent directory into `sys.path`, then `from common.json_line import emit  # noqa: E402`. Add a docstring that gives the usage and the output shape.
- Do not redefine `emit`, `inside`, `write_atomic`, `split_frontmatter` or `frontmatter_of`. `tests/architecture/test_layers.py` and `tests/architecture/test_icon_glyphs.py` must pass unchanged.
- Use only `am` commands. Never read am's SQLite or its on-disk layout.
- Every subprocess call uses an argv list and never a shell. Resolve `am` with `shutil.which("am")`.
- The helper is a one-shot process. It has no timers, no polling and no loops waiting on am.

## Observable behaviour

Invocation: `runs-snapshot.py <project root>`. If the argument count is wrong, the helper prints `{ok:false, error:{type:"Usage", message:<usage>}}` and exits 2.

1. Run `am runs --repo-dir R`. On success, am returns `{"ok":true,"data":{"runs":[...]}}`. The runs are ordered newest first, and each summary has `id, workflow, repo_dir, base_branch, branch_prefix, status, started_at`.
2. Select runs from that list, keeping am's order:
   - every non-terminal run;
   - the first 10 terminal runs, which are the latest 10.
   - Terminal statuses are exactly `done`, `escalated`, `stopped` and `cancelled`, taken from the monitor spec's "Data sources" finished list. `stopped` counts as terminal even though the domain table also calls it "parked" or resumable. A test pins this.
   - Terminal runs after the tenth are left out of the output.
3. For each selected run, in order, run `am status <id> --repo-dir R` and take its `data` object.
4. Print one line: `{"ok":true, "runs":[{...summary fields..., "status":<am status data>}], "data_dir":<path>}` and exit 0.
   - The output follows the card's shape literally, so the `status` key holds the `am status` data object and replaces the summary's status string. The run's state can still be read from that object's run section.
   - The helper does no other normalisation.
5. No runs gives `{ok:true, runs:[], data_dir:...}`. This is an empty state, not an error.

`data_dir` decision (open in the card): the value is the `XDG_DATA_HOME` in effect. If `XDG_DATA_HOME` is set and absolute, use it. Otherwise use `~/.local/share`, mirroring `state_home()` in `run-setup-milestone.py`. Do not append an am subdirectory, because that would assume am's on-disk layout, which is a spec non-goal. am does not report this path itself (`am runs` returns only `{"runs":[]}`), so the helper derives it from the environment.

## Error paths

Every path prints exactly one JSON line, including unexpected failure. A `guarded(argv)` wrapper does this, matching `run-setup-milestone.py`.

| Case | Output | Exit |
|---|---|---|
| `am` is not on PATH | `{ok:false, error:{type:"AmMissing", message:...}}` | 1 |
| `am runs` or any `am status` returns an `ok:false` envelope, for example `{"error":{"message":...,"type":"UnknownRunError"},"ok":false}` with exit 3 | that envelope, re-emitted unchanged, with no `data_dir` added | 1 |
| am prints output that is not JSON or not a JSON object, or an `ok:true` envelope whose `data` lacks the expected shape (`data.runs` not a list, a run without `id`/`status`, or `am status` data not an object) | `{ok:false, error:{type:"AmBadOutput", message:...}}` | 1 |
| any other exception | `{ok:false, error:{type:"HelperError", message:<reason>}}` | 1 |

The `ok` field of the envelope decides success, not am's exit code: real `am runs` returns exit 0 with `ok:false` for a `RepoDirError`, and that is re-emitted like any other error envelope. A non-zero exit with no parseable envelope is `AmBadOutput`. Each am call has a generous timeout (60 s); expiry is `HelperError`. This is a bound on a one-shot call, not polling.

If any `am status` call fails, the whole snapshot fails. HelperRunner re-snapshots on the next change signal, so the helper does not merge partial results.

## Tests

All of these tests are Python helper behaviour. Under the test-placement rule (`docs/architecture.md` "How to add a helper script" and "Tests", plus the monitor spec's "Testing"), they belong in the pytest tier at `tests/core/backend/runs/test_runs_snapshot.py`.

They do not belong in `tests/contract/`: the real-`am` shape check is card 2.4. They do not belong in the QML tiers either, because this card has no JS, store or UI.

Harness:
- Each test builds a fake `am` executable in `tmp_path/bin`, following the fake-PATH pattern in `tests/core/backend/milestones/test_run_setup_milestone.py`: `PATH = bin + os.pathsep + "/usr/bin" + os.pathsep + "/bin"`. HOME and the XDG dirs are temporary.
- The fake `am` serves hand-written fixtures and appends its argv to a log file, so tests can assert which calls were made. The fixtures are `am runs` data, and `am status` data shaped as the monitor spec describes it: run, the story/subtask/phase/attempt tree, `rows`, `control.lease`, `requests` and `claims`.
- The fixtures and the stub are created inside the test. No files are added under `tests/stubs`.
- The helper is run with `sys.executable` and an argv list. The real `am` and real data are never touched.

Test list (all in the pytest tier, `tests/core/backend/runs/`):
1. `test_no_runs_is_empty_state`: `{ok:true, runs:[], data_dir}`, exit 0, and no `am status` calls.
2. `test_snapshot_shape`: each run keeps the summary fields, `status` equals that run's `am status` data, and stdout is exactly one JSON line.
3. `test_status_fanout_selection`: given non-terminal runs plus more than 10 terminal runs, every non-terminal run is included, only the latest 10 terminal runs are included, am's order is preserved, and the argv log shows exactly those `am status <id> --repo-dir R` calls.
4. `test_terminal_set_pinned`: `done`, `escalated`, `stopped` and `cancelled` are treated as terminal. In particular, `stopped` counts toward the cap of 10 and is not always included. `started` and other statuses are non-terminal.
5. `test_repo_dir_passed`: every am call carries `--repo-dir <project root>`.
6. `test_am_missing`: with a PATH that has no `am`, the output is `{ok:false, error:{type:"AmMissing"}}`.
7. `test_am_error_envelope_passthrough_runs` and `test_am_error_envelope_passthrough_status`: an `UnknownRunError` envelope with exit 3 is re-emitted unchanged, as one line.
8. `test_am_bad_output`: non-JSON output from the stub gives `AmBadOutput` on one line.
9. `test_data_dir`: an absolute `XDG_DATA_HOME` is reported as-is, and an unset or relative value falls back to `$HOME/.local/share`.
10. `test_usage`: no arguments gives `type:"Usage"` and exit 2.

Verification: run `bash ./tests/run.sh`. The suite passes, including the unchanged architecture tests.

---

# runs-snapshot.py Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `core/backend/runs/runs-snapshot.py`, a one-shot helper that lists a project's am runs, fans out `am status` for every non-terminal run plus the latest 10 terminal ones, and prints exactly one JSON line on every path.

**Architecture:** A single stdlib-only Python script in a new `core/backend/runs/` domain directory, using the repo's helper header idiom (`sys.path` insert of the parent, `from common.json_line import emit`). It shells out to `am` via argv lists only, validates am's `{ok,data}` envelope, and wraps `main` in a `guarded` catch-all like `run-setup-milestone.py`. Tests are hermetic pytest tests that put a fake `am` (built inside `tmp_path`) on a temp PATH and serve hand-written fixtures.

**Tech Stack:** Python 3 stdlib (`json`, `os`, `shutil`, `subprocess`, `sys`), pytest, `bash ./tests/run.sh`.

**Spec:** `docs/superpowers/specs/task-2-1-runs-snapshot-py-1f3833c1-design.md` (prepended above, verbatim).

All paths below are relative to the worktree root `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-2-1-runs-snapshot-py-1f3833c1`; run every command from there. The branch is `mon/task-2-1-runs-snapshot-py-1f3833c1`; do not assume any sibling subtask's code (runs-watch.py, runs-logs.py, runs.js, RunStore.qml) exists.

Running one pytest file: `python3 -m pytest tests/core/backend/runs/test_runs_snapshot.py -q`. If `python3` has no pytest (a uv-managed interpreter), use `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_snapshot.py -q` instead, exactly as `tests/run.sh` does.

## Global Constraints

- `core/backend/**` imports only the Python stdlib and `core/backend/common`; no `.qml`/`.js` under `core/backend/`.
- Header idiom: `sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))` then `from common.json_line import emit  # noqa: E402`; docstring gives usage and output shape.
- Never define `def emit(`, `def inside(`, `def write_atomic(`, `def split_frontmatter(` or `def frontmatter_of(` in the new file (`tests/architecture/test_layers.py::test_shared_python_helpers_are_defined_once`).
- Only `am` commands; never read am's SQLite or on-disk layout.
- Every subprocess call is an argv list, never a shell; `am` is resolved with `shutil.which("am")`.
- One-shot: no timers, no polling, no loops waiting on am; each am call has a 60 s timeout.
- Terminal statuses are exactly `done`, `escalated`, `stopped`, `cancelled`; cap of 10 terminal runs.
- Success line: `{"ok": true, "runs": [{<summary fields>, "status": <am status data>}], "data_dir": <path>}`, exit 0.
- `data_dir`: `XDG_DATA_HOME` if set and absolute, else `~/.local/share`; no am subdirectory.
- Error types: `Usage` (exit 2), `AmMissing`, am's own `ok:false` envelope re-emitted unchanged (no `data_dir`), `AmBadOutput`, `HelperError` (all exit 1).
- Tests live only in `tests/core/backend/runs/test_runs_snapshot.py`; no files under `tests/stubs`, nothing in `tests/contract/`.
- Verification: `bash ./tests/run.sh`.

## Review Focus

- A project root containing spaces or shell metacharacters (e.g. `my proj; echo x`): it must reach `am` as a single `--repo-dir` argv element, never split or interpreted. Pinned in Task 2 `test_repo_dir_passed` (the fixture project dir is named `my proj; echo x`).
- `am runs` exiting 0 but printing `ok:false` (real `RepoDirError` behaviour, e.g. the root is not a git repo or does not exist): must be re-emitted as the error, not treated as an empty list. Pinned in Task 3 `test_am_error_envelope_passthrough_runs` (parametrized over exit 3 and exit 0).
- `am` crashing with a non-zero exit and empty stdout or a Python traceback: must give `AmBadOutput`, one line. Pinned in Task 3 `test_am_bad_output` cases `crash-empty` and `status-traceback`.
- An `am` on PATH that cannot be executed (broken interpreter line): must still print one `HelperError` line, never a Python traceback. Pinned in Task 1 `test_unexpected_failure_is_helper_error`.
- A status value am adds in the future (e.g. `paused`): must be treated as non-terminal and always included, never silently capped. Pinned in Task 2 `test_terminal_set_pinned` (`something-new` case).

---

## File Structure

- Create `core/backend/runs/runs-snapshot.py`: the whole helper (argv check, `am` resolution, am envelope parsing/validation, run selection, status fan-out, `data_dir`, `guarded` catch-all).
- Create `tests/core/backend/runs/test_runs_snapshot.py`: the hermetic harness (fake `am`, fixtures, env) and all tests. Sibling test dirs (`tests/core/backend/milestones/`, `documents/`) have no `__init__.py`; do not add one.
- Modify `docs/architecture.md:122`: one sentence naming `core/backend/runs/`.

---

### Task 1: Helper skeleton, harness, empty state, usage, AmMissing, data_dir, catch-all

**Files:**
- Create: `core/backend/runs/runs-snapshot.py`
- Test: `tests/core/backend/runs/test_runs_snapshot.py`

**Interfaces:**
- Consumes: `common.json_line.emit(payload, code=0) -> int` (prints `json.dumps(payload)`, returns `code`).
- Produces (inside `runs-snapshot.py`): `USAGE: str`, `AM_TIMEOUT = 60`, `failure(kind: str, message: str, code: int = 1) -> int`, `data_dir() -> str`, `call_am(am: str, args: list[str]) -> object` (returns the envelope's `data`), `main(argv: list[str]) -> int`, `guarded(argv: list[str]) -> int`.
- Produces (inside the test file, used by Tasks 2 and 3): fixture `world` (dict with keys `tmp`, `bin`, `am`, `home`, `data`, `proj`), `write_exec(path, text)`, `env_for(world, drop=(), **extra) -> dict`, `run(world, args=None, drop=(), **extra) -> (int, dict)`, `summary(run_id, status, started_at=...) -> dict`, `status_data(run_id, status) -> dict`, `set_runs(world, runs)`, `set_status(world, run_id, status="started", data=None)`, `seed(world, runs)`, `set_raw(world, name, text, code=0)`, `calls(world) -> list[list[str]]`, `expected(run, data) -> dict`, constants `UNKNOWN_RUN`, `REPO_DIR_ERROR`, `SUMMARY_FIELDS`.

- [ ] **Step 1: Write the failing tests (harness + Task 1 tests)**

Create `tests/core/backend/runs/test_runs_snapshot.py` with exactly:

```python
"""runs-snapshot.py: am runs + am status fan-out, one JSON line on every path.

Hermetic: a fake `am` lives on a temp PATH and serves hand-written fixtures from
FAKE_AM_DIR, appending each call's argv to calls.log; HOME and XDG_DATA_HOME are
temp. The real `am` and real data are never touched.
"""
import json
import os
import stat
import subprocess
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "..")
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "runs-snapshot.py")

# The fake am logs its argv, then prints FAKE_AM_DIR/<name>.out verbatim and exits
# with FAKE_AM_DIR/<name>.code (default 0), where <name> is "runs" or
# "status-<run id>". A status fixture that does not exist behaves like real am for
# an unknown run: an UnknownRunError envelope and exit 3.
FAKE_AM = '''#!/usr/bin/env python3
import json, os, sys
d = os.environ["FAKE_AM_DIR"]
args = sys.argv[1:]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(args) + "\\n")
name = "runs" if args[:1] == ["runs"] else "status-" + (args[1] if len(args) > 1 else "")
out = os.path.join(d, name + ".out")
if not os.path.exists(out):
    sys.stdout.write(json.dumps({"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}) + "\\n")
    sys.exit(3)
with open(out) as f:
    sys.stdout.write(f.read())
code = os.path.join(d, name + ".code")
sys.exit(int(open(code).read()) if os.path.exists(code) else 0)
'''

UNKNOWN_RUN = {"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}
REPO_DIR_ERROR = {"error": {"message": "not a git repository", "type": "RepoDirError"}, "ok": False}
SUMMARY_FIELDS = {"id", "workflow", "repo_dir", "base_branch", "branch_prefix", "status", "started_at"}


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
    argv = [str(world["proj"])] if args is None else args
    p = subprocess.run([sys.executable, SCRIPT, *argv], capture_output=True, text=True,
                       env=env_for(world, drop, **extra), timeout=60)
    lines = p.stdout.splitlines()
    assert len(lines) == 1, (p.stdout, p.stderr)
    return p.returncode, json.loads(lines[0])


def summary(run_id, status, started_at="2026-10-01T12:00:00Z"):
    return {"id": run_id, "workflow": "orchestrator", "repo_dir": "/repo",
            "base_branch": "master", "branch_prefix": "m2", "status": status,
            "started_at": started_at}


def status_data(run_id, status):
    """`am status` data as the monitor spec describes it: run, the
    story/subtask/phase/attempt tree, flat rows, control.lease, requests, claims."""
    return {
        "run": summary(run_id, status),
        "stories": [{"id": "s1", "title": "Story", "subtasks": [
            {"id": "c1", "title": "Card", "phases": [
                {"name": "implement", "status": "done",
                 "attempts": [{"n": 1, "status": "done"}]}]}]}],
        "rows": [{"card_id": "c1", "phase": "implement", "attempt": 1, "status": "done"}],
        "control": {"lease": {"pid": 4121, "host": "box",
                              "heartbeat_at": "2026-10-01T12:00:05Z",
                              "accepting": True, "live": status == "started"}},
        "requests": [],
        "claims": [{"card_id": "c1", "run_id": run_id}],
    }


def set_runs(world, runs):
    (world["am"] / "runs.out").write_text(json.dumps({"data": {"runs": runs}, "ok": True}) + "\n")


def set_status(world, run_id, status="started", data=None):
    payload = status_data(run_id, status) if data is None else data
    (world["am"] / ("status-" + run_id + ".out")).write_text(
        json.dumps({"data": payload, "ok": True}) + "\n")


def seed(world, runs):
    """`am runs` lists `runs`; `am status` answers for every one of them."""
    set_runs(world, runs)
    for r in runs:
        set_status(world, r["id"], r["status"])


def set_raw(world, name, text, code=0):
    (world["am"] / (name + ".out")).write_text(text)
    (world["am"] / (name + ".code")).write_text(str(code))


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def expected(run, data):
    out = dict(run)
    out["status"] = data
    return out


# --- empty state, usage, am missing, data_dir, catch-all --------------------

def test_no_runs_is_empty_state(world):
    set_runs(world, [])
    code, out = run(world)
    assert code == 0
    assert out == {"ok": True, "runs": [], "data_dir": str(world["data"])}
    assert calls(world) == [["runs", "--repo-dir", str(world["proj"])]]


@pytest.mark.parametrize("args", [[], ["a", "b"]])
def test_usage(world, args):
    code, out = run(world, args)
    assert code == 2
    assert out["ok"] is False
    assert out["error"]["type"] == "Usage"
    assert "runs-snapshot.py <project_root>" in out["error"]["message"]
    assert calls(world) == []


def test_am_missing(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, out = run(world, PATH=str(empty))
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "AmMissing"
    assert out["error"]["message"]


@pytest.mark.parametrize("case", ["absolute", "unset", "relative", "empty"])
def test_data_dir(world, case):
    set_runs(world, [])
    fallback = str(world["home"] / ".local" / "share")
    if case == "absolute":
        code, out = run(world)
        want = str(world["data"])
    elif case == "unset":
        code, out = run(world, drop=("XDG_DATA_HOME",))
        want = fallback
    elif case == "relative":
        code, out = run(world, XDG_DATA_HOME="rel/data")
        want = fallback
    else:
        code, out = run(world, XDG_DATA_HOME="")
        want = fallback
    assert code == 0
    assert out["data_dir"] == want


def test_unexpected_failure_is_helper_error(world):
    # An am that cannot be executed at all: subprocess raises, guarded() must
    # still print exactly one JSON line.
    write_exec(world["bin"] / "am", "#!/nonexistent/interpreter\n")
    code, out = run(world)
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_snapshot.py -q`
Expected: FAIL, every test. The script does not exist, so `python` prints `can't open file ... runs-snapshot.py` on stderr, stdout is empty, and each test fails at `assert len(lines) == 1`.

- [ ] **Step 3: Write the minimal implementation**

Create `core/backend/runs/runs-snapshot.py` with exactly:

```python
#!/usr/bin/env python3
"""List an am project's runs and each selected run's status.

    runs-snapshot.py <project_root>

Runs `am runs --repo-dir R` (newest first), keeps am's order and selects every
non-terminal run plus the first 10 terminal ones (terminal: done, escalated,
stopped, cancelled), then runs `am status <id> --repo-dir R` for each selected
run.

Prints exactly one JSON line on EVERY path:
{"ok": true, "runs": [{<am runs summary fields>, "status": <am status data>}],
 "data_dir": <XDG_DATA_HOME in effect, else ~/.local/share>}
or {"ok": false, "error": {"type", "message"}} with type AmMissing, AmBadOutput,
Usage (exit 2) or HelperError; an `ok:false` envelope from am is re-emitted
unchanged. Exit 0 ok, 1 failure, 2 usage. Only `am` commands are used, always as
argv lists; am's database and on-disk layout are never read.
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-snapshot.py <project_root>"
AM_TIMEOUT = 60


def failure(kind, message, code=1):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def data_dir():
    """XDG_DATA_HOME, but only when it is absolute (like `state_home()` in
    run-setup-milestone.py); otherwise ~/.local/share. No am subdirectory: that
    would assume am's on-disk layout."""
    data = os.environ.get("XDG_DATA_HOME") or ""
    if not os.path.isabs(data):
        return os.path.join(os.path.expanduser("~"), ".local", "share")
    return data


def call_am(am, args):
    proc = subprocess.run([am, *args], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    return json.loads(proc.stdout)["data"]


def main(argv):
    if len(argv) != 1:
        return failure("Usage", USAGE, 2)
    root = argv[0]
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    runs = call_am(am, ["runs", "--repo-dir", root])["runs"]
    return emit({"ok": True, "runs": runs, "data_dir": data_dir()})


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The runs snapshot failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_snapshot.py -q`
Expected: PASS (all 9 test items: 1 empty state, 2 usage, 1 am missing, 4 data_dir, 1 helper error).

Then run: `python3 -m pytest tests/architecture -q`
Expected: PASS (the new file defines no `emit`/`inside`/... and is `.py` under `core/backend/`).

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-snapshot.py tests/core/backend/runs/test_runs_snapshot.py
git commit -m "feat(runs): runs-snapshot.py skeleton with empty state, usage, AmMissing and data_dir"
```

---

### Task 2: Run selection and `am status` fan-out

**Files:**
- Modify: `core/backend/runs/runs-snapshot.py` (replace whole file)
- Test: `tests/core/backend/runs/test_runs_snapshot.py` (append)

**Interfaces:**
- Consumes: from Task 1 test file: `world`, `run`, `seed`, `summary`, `status_data`, `calls`, `expected`, `SUMMARY_FIELDS`. From Task 1 script: `failure`, `data_dir`, `call_am`, `guarded`, `USAGE`, `AM_TIMEOUT`.
- Produces (inside `runs-snapshot.py`): `TERMINAL = frozenset({"done", "escalated", "stopped", "cancelled"})`, `TERMINAL_LIMIT = 10`, `select_runs(runs: list[dict]) -> list[dict]`, `snapshot(am: str, root: str, runs: list[dict]) -> list[dict]`.

- [ ] **Step 1: Write the failing tests**

Append to the end of `tests/core/backend/runs/test_runs_snapshot.py`:

```python


# --- shape and fan-out -------------------------------------------------------

def test_snapshot_shape(world):
    runs = [summary("r2", "started", "2026-10-02T09:00:00Z"),
            summary("r1", "done", "2026-10-01T09:00:00Z")]
    seed(world, runs)
    code, out = run(world)  # run() asserts stdout is exactly one JSON line
    assert code == 0
    assert out == {
        "ok": True,
        "runs": [expected(runs[0], status_data("r2", "started")),
                 expected(runs[1], status_data("r1", "done"))],
        "data_dir": str(world["data"]),
    }
    for entry in out["runs"]:
        assert set(entry) == SUMMARY_FIELDS
        assert isinstance(entry["status"], dict)


def test_status_fanout_selection(world):
    # Newest first: non-terminal runs interleaved with 12 terminal ones, and one
    # non-terminal run older than every terminal one.
    runs = ([summary("n1", "started")]
            + [summary("t%d" % i, "done") for i in range(1, 6)]
            + [summary("n2", "started")]
            + [summary("t%d" % i, ["escalated", "cancelled", "stopped"][i % 3])
               for i in range(6, 13)]
            + [summary("n3", "started")])
    seed(world, runs)
    code, out = run(world)
    want = ["n1", "t1", "t2", "t3", "t4", "t5", "n2",
            "t6", "t7", "t8", "t9", "t10", "n3"]
    assert code == 0
    assert [r["id"] for r in out["runs"]] == want
    root = str(world["proj"])
    assert calls(world) == ([["runs", "--repo-dir", root]]
                            + [["status", i, "--repo-dir", root] for i in want])


@pytest.mark.parametrize("status,kept", [
    ("done", 10), ("escalated", 10), ("stopped", 10), ("cancelled", 10),
    ("started", 12), ("paused", 12), ("something-new", 12),
])
def test_terminal_set_pinned(world, status, kept):
    # `stopped` is "parked" in the domain table but terminal here: it counts
    # toward the cap of 10. Any status outside the four is non-terminal.
    runs = [summary("x%02d" % i, status) for i in range(12)]
    seed(world, runs)
    code, out = run(world)
    assert code == 0
    assert [r["id"] for r in out["runs"]] == ["x%02d" % i for i in range(kept)]


def test_repo_dir_passed(world):
    # The project dir is named "my proj; echo x": it must arrive as one argv element.
    seed(world, [summary("r2", "started"), summary("r1", "done")])
    code, _ = run(world)
    assert code == 0
    made = calls(world)
    assert len(made) == 3
    for argv in made:
        assert argv[-2:] == ["--repo-dir", str(world["proj"])]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_snapshot.py -q -k "shape or fanout or terminal_set or repo_dir"`
Expected: FAIL. `test_snapshot_shape` fails because `status` is still the summary string; `test_status_fanout_selection` fails because all 15 runs are returned and no `status` calls are logged; the terminal-status cases fail with 12 ids instead of 10; `test_repo_dir_passed` fails on `len(made) == 3` (only 1 call). The non-terminal cases of `test_terminal_set_pinned` (`started`, `paused`, `something-new`) may already pass; that is expected.

- [ ] **Step 3: Write the implementation**

Replace `core/backend/runs/runs-snapshot.py` with exactly:

```python
#!/usr/bin/env python3
"""List an am project's runs and each selected run's status.

    runs-snapshot.py <project_root>

Runs `am runs --repo-dir R` (newest first), keeps am's order and selects every
non-terminal run plus the first 10 terminal ones (terminal: done, escalated,
stopped, cancelled), then runs `am status <id> --repo-dir R` for each selected
run.

Prints exactly one JSON line on EVERY path:
{"ok": true, "runs": [{<am runs summary fields>, "status": <am status data>}],
 "data_dir": <XDG_DATA_HOME in effect, else ~/.local/share>}
or {"ok": false, "error": {"type", "message"}} with type AmMissing, AmBadOutput,
Usage (exit 2) or HelperError; an `ok:false` envelope from am is re-emitted
unchanged. Exit 0 ok, 1 failure, 2 usage. Only `am` commands are used, always as
argv lists; am's database and on-disk layout are never read.
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-snapshot.py <project_root>"
AM_TIMEOUT = 60
# The monitor spec's finished list. `stopped` is "parked" (resumable) in the domain
# table, but for the snapshot it is terminal and counts toward the cap.
TERMINAL = frozenset({"done", "escalated", "stopped", "cancelled"})
TERMINAL_LIMIT = 10


def failure(kind, message, code=1):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def data_dir():
    """XDG_DATA_HOME, but only when it is absolute (like `state_home()` in
    run-setup-milestone.py); otherwise ~/.local/share. No am subdirectory: that
    would assume am's on-disk layout."""
    data = os.environ.get("XDG_DATA_HOME") or ""
    if not os.path.isabs(data):
        return os.path.join(os.path.expanduser("~"), ".local", "share")
    return data


def call_am(am, args):
    proc = subprocess.run([am, *args], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    return json.loads(proc.stdout)["data"]


def select_runs(runs):
    """Every non-terminal run plus the first TERMINAL_LIMIT terminal ones, in am's
    (newest-first) order."""
    picked, terminal = [], 0
    for run in runs:
        if run["status"] in TERMINAL:
            if terminal >= TERMINAL_LIMIT:
                continue
            terminal += 1
        picked.append(run)
    return picked


def snapshot(am, root, runs):
    """Each selected run's summary with `status` replaced by its `am status` data."""
    out = []
    for run in select_runs(runs):
        entry = dict(run)
        entry["status"] = call_am(am, ["status", run["id"], "--repo-dir", root])
        out.append(entry)
    return out


def main(argv):
    if len(argv) != 1:
        return failure("Usage", USAGE, 2)
    root = argv[0]
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    runs = call_am(am, ["runs", "--repo-dir", root])["runs"]
    return emit({"ok": True, "runs": snapshot(am, root, runs), "data_dir": data_dir()})


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The runs snapshot failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_snapshot.py -q`
Expected: PASS (all Task 1 and Task 2 items).

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-snapshot.py tests/core/backend/runs/test_runs_snapshot.py
git commit -m "feat(runs): select non-terminal + latest 10 terminal runs and fan out am status"
```

---

### Task 3: am error envelopes, bad output, docs line, full verification

**Files:**
- Modify: `core/backend/runs/runs-snapshot.py` (replace whole file)
- Modify: `docs/architecture.md:122`
- Test: `tests/core/backend/runs/test_runs_snapshot.py` (append)

**Interfaces:**
- Consumes: from Task 1 test file: `world`, `run`, `seed`, `set_runs`, `set_status`, `set_raw`, `summary`, `calls`, `UNKNOWN_RUN`, `REPO_DIR_ERROR`. From Task 2 script: `TERMINAL`, `TERMINAL_LIMIT`, `select_runs`, `snapshot`.
- Produces (inside `runs-snapshot.py`): `class AmFailure(Exception)` with attribute `payload: dict` (the exact line to emit), `bad_output(message: str) -> AmFailure`, `run_list(data: object) -> list[dict]`; `call_am(am, args)` now raises `AmFailure` instead of returning bad data; `main` catches `AmFailure` and emits `e.payload` with exit 1.

- [ ] **Step 1: Write the failing tests**

Append to the end of `tests/core/backend/runs/test_runs_snapshot.py`:

```python


# --- am errors and bad output --------------------------------------------------

@pytest.mark.parametrize("envelope,exit_code", [(UNKNOWN_RUN, 3), (REPO_DIR_ERROR, 0)])
def test_am_error_envelope_passthrough_runs(world, envelope, exit_code):
    # The envelope's `ok` decides, not am's exit code: real `am runs` exits 0 with
    # ok:false for a RepoDirError.
    set_raw(world, "runs", json.dumps(envelope) + "\n", exit_code)
    code, out = run(world)
    assert code == 1
    assert out == envelope
    assert "data_dir" not in out
    assert calls(world) == [["runs", "--repo-dir", str(world["proj"])]]


def test_am_error_envelope_passthrough_status(world):
    # r2 has no status fixture, so the fake am answers UnknownRunError, exit 3. The
    # whole snapshot fails; no partial result is printed.
    set_runs(world, [summary("r1", "started"), summary("r2", "started")])
    set_status(world, "r1", "started")
    code, out = run(world)
    assert code == 1
    assert out == UNKNOWN_RUN
    assert "data_dir" not in out
    assert calls(world)[-1] == ["status", "r2", "--repo-dir", str(world["proj"])]


@pytest.mark.parametrize("target,text,exit_code", [
    ("runs", "not json\n", 0),
    ("runs", "[1, 2]\n", 0),
    ("runs", "", 5),
    ("runs", '{"data": {"runs": []}}\n', 0),
    ("runs", '{"ok": true, "data": {"runs": "x"}}\n', 0),
    ("runs", '{"ok": true, "data": []}\n', 0),
    ("runs", '{"ok": true, "data": {"runs": [{"workflow": "m", "status": "done"}]}}\n', 0),
    ("runs", '{"ok": true, "data": {"runs": [{"id": "r1"}]}}\n', 0),
    ("runs", '{"ok": true, "data": {"runs": ["r1"]}}\n', 0),
    ("status", '{"ok": true, "data": [1]}\n', 0),
    ("status", "Traceback (most recent call last):\n  boom\n", 1),
], ids=["not-json", "not-object", "crash-empty", "no-ok", "runs-not-list",
        "data-not-object", "run-without-id", "run-without-status", "run-not-object",
        "status-data-not-object", "status-traceback"])
def test_am_bad_output(world, target, text, exit_code):
    if target == "runs":
        set_raw(world, "runs", text, exit_code)
    else:
        set_runs(world, [summary("r1", "started")])
        set_raw(world, "status-r1", text, exit_code)
    code, out = run(world)  # run() asserts exactly one JSON line
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "AmBadOutput"
    assert out["error"]["message"]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_snapshot.py -q -k "passthrough or bad_output"`
Expected: FAIL. The passthrough tests get a `HelperError` line (`KeyError: 'data'`) instead of the envelope; most bad-output cases get `HelperError` instead of `AmBadOutput`, and `no-ok` gets `ok:true` with empty runs.

- [ ] **Step 3: Write the implementation**

Replace `core/backend/runs/runs-snapshot.py` with exactly:

```python
#!/usr/bin/env python3
"""List an am project's runs and each selected run's status.

    runs-snapshot.py <project_root>

Runs `am runs --repo-dir R` (newest first), keeps am's order and selects every
non-terminal run plus the first 10 terminal ones (terminal: done, escalated,
stopped, cancelled), then runs `am status <id> --repo-dir R` for each selected
run.

Prints exactly one JSON line on EVERY path:
{"ok": true, "runs": [{<am runs summary fields>, "status": <am status data>}],
 "data_dir": <XDG_DATA_HOME in effect, else ~/.local/share>}
or {"ok": false, "error": {"type", "message"}} with type AmMissing, AmBadOutput,
Usage (exit 2) or HelperError; an `ok:false` envelope from am is re-emitted
unchanged. Exit 0 ok, 1 failure, 2 usage. If any `am status` call fails the whole
snapshot fails (no partial result). Only `am` commands are used, always as argv
lists; am's database and on-disk layout are never read.
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-snapshot.py <project_root>"
AM_TIMEOUT = 60
# The monitor spec's finished list. `stopped` is "parked" (resumable) in the domain
# table, but for the snapshot it is terminal and counts toward the cap.
TERMINAL = frozenset({"done", "escalated", "stopped", "cancelled"})
TERMINAL_LIMIT = 10


class AmFailure(Exception):
    """An am call that gave no usable data; `payload` is the one line to emit."""

    def __init__(self, payload):
        super().__init__("am call failed")
        self.payload = payload


def bad_output(message):
    return AmFailure({"ok": False, "error": {"type": "AmBadOutput", "message": message}})


def failure(kind, message, code=1):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def data_dir():
    """XDG_DATA_HOME, but only when it is absolute (like `state_home()` in
    run-setup-milestone.py); otherwise ~/.local/share. No am subdirectory: that
    would assume am's on-disk layout."""
    data = os.environ.get("XDG_DATA_HOME") or ""
    if not os.path.isabs(data):
        return os.path.join(os.path.expanduser("~"), ".local", "share")
    return data


def call_am(am, args):
    """Run one am command and return its envelope's `data`. The envelope's `ok`
    decides, not the exit code: an `ok:false` envelope is raised as-is (to be
    re-emitted unchanged); anything that is not an envelope is AmBadOutput."""
    proc = subprocess.run([am, *args], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    what = "am " + args[0]
    try:
        envelope = json.loads(proc.stdout)
    except ValueError:
        raise bad_output(what + " did not print JSON (exit " + str(proc.returncode) + ").")
    if not isinstance(envelope, dict):
        raise bad_output(what + " printed JSON that is not an object.")
    if envelope.get("ok") is False:
        raise AmFailure(envelope)
    if envelope.get("ok") is not True:
        raise bad_output(what + " printed an object without an ok field.")
    return envelope.get("data")


def run_list(data):
    """`am runs` data's run list, checked: a list of objects with string id/status."""
    runs = data.get("runs") if isinstance(data, dict) else None
    if not isinstance(runs, list):
        raise bad_output("am runs data has no runs list.")
    for run in runs:
        if not (isinstance(run, dict) and isinstance(run.get("id"), str) and run["id"]
                and isinstance(run.get("status"), str)):
            raise bad_output("am runs listed a run without an id or status.")
    return runs


def select_runs(runs):
    """Every non-terminal run plus the first TERMINAL_LIMIT terminal ones, in am's
    (newest-first) order."""
    picked, terminal = [], 0
    for run in runs:
        if run["status"] in TERMINAL:
            if terminal >= TERMINAL_LIMIT:
                continue
            terminal += 1
        picked.append(run)
    return picked


def snapshot(am, root, runs):
    """Each selected run's summary with `status` replaced by its `am status` data."""
    out = []
    for run in select_runs(runs):
        status = call_am(am, ["status", run["id"], "--repo-dir", root])
        if not isinstance(status, dict):
            raise bad_output("am status " + run["id"] + " data is not an object.")
        entry = dict(run)
        entry["status"] = status
        out.append(entry)
    return out


def main(argv):
    if len(argv) != 1:
        return failure("Usage", USAGE, 2)
    root = argv[0]
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    try:
        runs = run_list(call_am(am, ["runs", "--repo-dir", root]))
        result = snapshot(am, root, runs)
    except AmFailure as e:
        return emit(e.payload, 1)
    return emit({"ok": True, "runs": result, "data_dir": data_dir()})


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception (a timeout, an am that cannot start) - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The runs snapshot failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_snapshot.py -q`
Expected: PASS (every item from Tasks 1-3).

- [ ] **Step 5: Name the new directory in docs/architecture.md**

In `docs/architecture.md`, replace the line

```
dialog states before the run starts.
```

with

```
dialog states before the run starts.
`core/backend/runs/` is the run-monitor backend: `runs-snapshot.py` runs `am runs`, then `am status` for every non-terminal run and the latest 10 terminal ones, and prints one JSON line (`{ok, runs, data_dir}` or an error).
```

- [ ] **Step 6: Run the full suite**

Run: `bash ./tests/run.sh`
Expected: pytest reports all passed (including `tests/architecture/test_layers.py` and `tests/architecture/test_icon_glyphs.py`, unchanged), every QML test prints `Totals: ... 0 failed`, and the script exits 0.

- [ ] **Step 7: Commit**

```bash
git add core/backend/runs/runs-snapshot.py tests/core/backend/runs/test_runs_snapshot.py docs/architecture.md
git commit -m "feat(runs): pass through am error envelopes, reject bad am output, document core/backend/runs"
```
