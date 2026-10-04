<!-- task-pipeline: validated -->
# Task 2.3: runs-logs.py, one attempt's output snapshot (card 4e4ae17d)

Parent story: 92b4d150 "Run backend helpers". Milestone design: `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` (Data sources table row "attempt output | `am logs RUN CARD --phase P --attempt N` | whole-file snapshot", the helper list entry "`runs-logs.py` — `am logs` passthrough for one attempt", Errors table, Testing). Blocked by 2.2 (done). The files from 2.1 and 2.2 (`core/backend/runs/runs-snapshot.py`, `runs-watch.py`, `tests/core/backend/runs/test_runs_snapshot.py`, `test_runs_watch.py`) are already present in this worktree, so both directories exist. Do not modify those files. Mirror runs-snapshot.py's conventions: an argv-list `am`, `AmMissing` via `shutil.which`, `AmBadOutput` for non-envelope output, a `guarded()` catch-all that emits `HelperError`, and every line printed through `emit`.

## Scope

In scope:
- `core/backend/runs/runs-logs.py` (new)
- `tests/core/backend/runs/test_runs_logs.py` (new)

Out of scope: runs-snapshot.py (2.1), runs-watch.py (2.2), `tests/contract/test_am_shapes.py` (2.4, which does not pin `logs`), RunStore.qml, runs.js, any UI, and the 200-line tail limit, which belongs to the store/UI. Also out of scope: any `docs/architecture.md` edit, which is left to the story.

## Conventions

- Shebang `#!/usr/bin/env python3`. Write a module docstring that gives the argv and every output path and exit code.
- Use the stdlib plus `core/backend/common` only. Add `sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))`, then `from common.json_line import emit  # noqa: E402`. Do not write a local copy of `emit`, `inside`, `write_atomic`, `split_frontmatter` or `frontmatter_of`. `tests/architecture/test_layers.py` must pass unchanged.
- Use only the documented `am logs` command. Never read am's SQLite, its on-disk layout or brd.
- Start `am` as an argv list with no shell: `subprocess.run([am, "logs", RUN, CARD, "--phase", PHASE, "--attempt", ATTEMPT], capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=60)`. Here `am` is the path that `shutil.which("am")` returns.

## Interface

`runs-logs.py RUN CARD PHASE ATTEMPT`

This takes exactly four positional args. They are passed to am verbatim as strings. The helper does not validate them, so am's own refusal, for example for a non-integer attempt or an unknown run, flows through as a passthrough. The helper is one-shot and prints exactly one JSON line on every path.

Flagged decision: the card gives no project root, so the helper sends no `--repo-dir` and relies on am resolving the run by id. If the store later needs `--repo-dir`, that is a change to this card's interface and must be agreed, not added silently.

## Observable behavior

1. When am prints a JSON object with `"ok": true`, the helper re-emits am's envelope unchanged as one compact JSON line (`{"ok":true,"data":...}`) and exits 0. The helper does not inspect or reshape `data` and does not trim it. The whole-file snapshot is passed through.
2. When am prints a JSON object with `"ok": false` (a refusal, typically am exit 3), the helper re-emits that envelope unchanged and exits 0. The exit code is decided by the envelope's `ok`, not by am's exit code.
3. Every path that prints a line exits 0, including the error lines below. The only exception is the usage error.

## Error paths

| Condition | Output line | Exit |
|---|---|---|
| argv count is not 4 | `{"ok":false,"error":{"type":"Usage","message":"usage: runs-logs.py RUN CARD PHASE ATTEMPT"}}` | 2 (matches siblings; the card's "exit 0 even on refusal" covers am refusals, not caller misuse) |
| `am` not on PATH | `{"ok":false,"error":{"type":"AmMissing","message":...}}` | 0 |
| am stdout is not JSON, is JSON but not an object, or is an object without a boolean `ok` | `{"ok":false,"error":{"type":"AmBadOutput","message":...}}` (message names `am logs` and its exit code where useful) | 0 |
| am returns `ok:false` | am's envelope, unchanged | 0 |
| any unexpected exception (timeout, am cannot start, and so on) | `{"ok":false,"error":{"type":"HelperError","message":...}}` from `guarded()` | 0 |

## Tests (TDD: write these first)

Every test below goes in `tests/core/backend/runs/test_runs_logs.py`. That file is in the backend pytest tier (`tests/core/backend/<domain>/`), as set by the "How to add / A helper script" and "Tests" sections of docs/architecture.md and by the milestone spec's Testing section (a stub `am` on PATH with recorded fixtures). None of these tests belong in `tests/contract/`, which pins the real am and is 2.4's tier. None belong in `tests/architecture/`, `tests/ui/` or the QML tiers either. The tests never call the real `am`.

The tests are hermetic and follow `test_runs_snapshot.py`. A fake `am` Python script is written to `tmp_path/bin` and put first on PATH. HOME and XDG_DATA_HOME point at temp dirs. The stub logs its argv to `calls.log`, prints `FAKE_AM_DIR/<name>.out`, and exits with `<name>.code`. Give it a `logs` branch keyed on the subcommand. For a missing fixture, the stub returns an `UnknownRunError` envelope with exit 3. The helper runs through `subprocess` with `sys.executable`, using a path computed from `__file__`. Every test asserts that stdout is exactly one JSON line.

1. `test_ok_envelope_passed_through`: a fixture `{"ok":true,"data":{prompt,result,stdout,stderr...}}` is printed back as an equal object on one line, with exit 0.
2. `test_exact_am_argv`: `calls.log` shows exactly `logs RUN CARD --phase PHASE --attempt ATTEMPT`, with no `--repo-dir` and no `--pretty`.
3. `test_pretty_printed_am_output_becomes_one_line`: multi-line JSON from the stub comes out as a single line.
4. `test_refusal_passed_through_exit_0`: the stub prints an `ok:false` envelope and exits 3. The helper prints that envelope unchanged and exits 0.
5. `test_missing_fixture_unknown_run`: the stub's default `UnknownRunError` envelope with exit 3 is passed through, with exit 0.
6. `test_non_json_output_is_am_bad_output`: the stub prints plain text. The output type is `AmBadOutput`, with exit 0.
7. `test_non_object_or_no_ok_is_am_bad_output`: a JSON list, and an object without `ok`, each give `AmBadOutput` with exit 0.
8. `test_am_missing`: PATH is set to an empty temp dir. The output is `AmMissing`, with exit 0.
9. `test_usage_wrong_argc`: 3 args and 5 args each give `Usage` with exit 2, and `am` is never called (no `calls.log` entry).
10. `test_am_cannot_start_is_helper_error`: the stub `am` on PATH is executable but cannot be started (for example a shebang naming a nonexistent interpreter, so `subprocess.run` raises `OSError`), giving a `HelperError` line with exit 0. A merely non-executable file would not do: `shutil.which` skips it and the result would be `AmMissing`. This proves `guarded()` covers the case.

`bash tests/run.sh` must pass. `tests/architecture` must pass unchanged.

---

# runs-logs.py Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `core/backend/runs/runs-logs.py`, a one-shot helper that runs `am logs RUN CARD --phase PHASE --attempt ATTEMPT` and re-prints am's envelope (ok or refusal) as exactly one JSON line, exiting 0 on every printed path except Usage (exit 2).

**Architecture:** A single stdlib-only Python script in the `runs` backend domain, imports `emit` from `core/backend/common/json_line.py` via the standard `sys.path.insert` of the parent dir, starts `am` as an argv list (no shell, stdin `/dev/null`, 60 s timeout), validates only that the output is a JSON object with a boolean `ok`, and wraps everything in `guarded()` so every unexpected exception still yields one `HelperError` line. Tests run the script as a subprocess against a stub `am` on a temp PATH, like `tests/core/backend/runs/test_runs_snapshot.py`.

**Tech Stack:** Python 3 stdlib (`json`, `os`, `shutil`, `subprocess`, `sys`), pytest.

**Spec:** `docs/superpowers/specs/task-2-3-runs-logs-py-one-4e4ae17d-design.md` (reproduced verbatim above).

**Workspace:** worktree `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-2-3-runs-logs-py-one-4e4ae17d`, branch `mon/task-2-3-runs-logs-py-one-4e4ae17d`, cut from `mon/task-2-2-runs-watch-py-d53c7d55`. All commands below run from the worktree root. `core/backend/runs/` and `tests/core/backend/runs/` already exist there (they hold 2.1/2.2's files, which must not be touched). If `python3 -c 'import pytest'` fails, prefix pytest commands with `uv run --with pytest` (the same fallback `tests/run.sh` uses), i.e. `uv run --with pytest python3 -m pytest ...`.

## Global Constraints

- Only two files are created: `core/backend/runs/runs-logs.py` and `tests/core/backend/runs/test_runs_logs.py`. Do not modify `runs-snapshot.py`, `runs-watch.py`, their tests, `docs/architecture.md`, or anything under `tests/contract/`, `tests/architecture/`, `tests/ui/`, `core/stores/`, `core/domain/`, `ui/`.
- `core/backend/**` may import only the Python stdlib and `core/backend/common`. No QML/JS under `core/backend/`.
- Use `from common.json_line import emit  # noqa: E402` after `sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))`. Neither new file may contain the text `def emit(`, `def inside(`, `def write_atomic(`, `def split_frontmatter(` or `def frontmatter_of(` (`tests/architecture/test_layers.py::test_shared_python_helpers_are_defined_once` greps for these).
- am is started exactly as `subprocess.run([am, "logs", RUN, CARD, "--phase", PHASE, "--attempt", ATTEMPT], capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=60)` where `am = shutil.which("am")`. No shell, no `--repo-dir`, no `--pretty`.
- Usage line: `{"ok":false,"error":{"type":"Usage","message":"usage: runs-logs.py RUN CARD PHASE ATTEMPT"}}`, exit 2. Every other printed line exits 0.
- Error types are exactly `Usage`, `AmMissing`, `AmBadOutput`, `HelperError`. am's own `ok:false` envelopes are re-emitted unchanged.
- The helper never inspects, reshapes or trims `data` (no 200-line tail limit here).
- "Compact one line" means one line as produced by `emit` (`json.dumps` with default separators); tests compare parsed objects, not byte strings.
- Tests never call the real `am`; HOME and XDG_DATA_HOME point at temp dirs.

## Review Focus

1. Attempt output with embedded newlines, CRLF, ANSI escape codes, tabs and non-ASCII text: a person expects the helper still to print one line and the text to round-trip byte-for-byte after JSON decoding. Pinned by `test_control_and_unicode_text_round_trips` in Task 1.
2. A very large whole-file snapshot (thousands of lines of captured stdout): a person expects nothing to be trimmed, since tail-limiting is the store's job. Pinned by `test_large_output_not_trimmed` in Task 1.
3. Arguments containing spaces, shell metacharacters or a leading dash (e.g. a run id `r 1; echo x`, attempt `-1`): a person expects each to reach am as one verbatim argv element, with am's own refusal passed through. Pinned by `test_args_reach_am_verbatim` in Task 1.
4. am exiting non-zero while printing an `ok:true` envelope and writing noise to stderr: a person expects the envelope's `ok` to decide, exit 0, and stderr never to leak into the stdout line. Pinned by `test_ok_wins_over_am_exit_code_and_stderr` in Task 1.
5. am crashing with empty stdout, or printing an object whose `ok` is not a boolean (`"true"`, `1`, `null`): a person expects `AmBadOutput`, not a passthrough of a malformed envelope. Pinned by the extra parametrize cases in `test_non_json_output_is_am_bad_output` and `test_non_object_or_no_ok_is_am_bad_output` in Task 2.

---

## File Structure

- Create `core/backend/runs/runs-logs.py`: the helper. Responsibilities: argv check, locate `am`, run `am logs`, validate the envelope shape, emit one line, catch-all. Public names used by tests: module globals `AM_TIMEOUT` (int, seconds) and `guarded(argv: list[str]) -> int`.
- Create `tests/core/backend/runs/test_runs_logs.py`: hermetic pytest file with its own stub `am` (a `logs` branch) and fixture helpers, mirroring `tests/core/backend/runs/test_runs_snapshot.py`.

---

### Task 1: Passthrough of am's envelope for one attempt

**Files:**
- Create: `tests/core/backend/runs/test_runs_logs.py`
- Create: `core/backend/runs/runs-logs.py`

**Interfaces:**
- Consumes: `core/backend/common/json_line.py` `emit(payload, code=0) -> int` (prints `json.dumps(payload)` and returns `code`).
- Produces: script `core/backend/runs/runs-logs.py` taking argv `RUN CARD PHASE ATTEMPT`; module global `AM_TIMEOUT = 60`; function `logs_argv(run, card, phase, attempt) -> list[str]` returning `["logs", run, card, "--phase", phase, "--attempt", attempt]`; function `main(argv) -> int`. Test-file helpers `world` fixture, `env_for(world, drop=(), **extra)`, `run(world, args=None, drop=(), **extra) -> (exit, payload)`, `set_logs(world, envelope, code=0)`, `set_raw(world, text, code=0, stderr=None)`, `calls(world) -> list[list[str]]`, `write_exec(path, text)`, constants `ARGS`, `UNKNOWN_RUN`, `LOGS_DATA`, `FAKE_AM`, `SCRIPT`. Task 2 appends to this file and uses all of these.

- [ ] **Step 1: Write the failing tests**

Create `tests/core/backend/runs/test_runs_logs.py` with exactly:

```python
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
```

(`importlib.util` is imported now because Task 2 appends `load_helper()`, which uses it.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_logs.py -q`
Expected: FAIL, all 10 tests. Each fails on `assert len(lines) == 1` because `core/backend/runs/runs-logs.py` does not exist (stderr shows `can't open file ... runs-logs.py`, stdout is empty).

- [ ] **Step 3: Write the minimal implementation**

Create `core/backend/runs/runs-logs.py` with exactly:

```python
#!/usr/bin/env python3
"""One attempt's output snapshot: an `am logs` passthrough.

    runs-logs.py RUN CARD PHASE ATTEMPT

Runs `am logs RUN CARD --phase PHASE --attempt ATTEMPT` and re-prints am's
envelope unchanged as one JSON line, exit 0.
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

AM_TIMEOUT = 60


def logs_argv(run, card, phase, attempt):
    """am's argv after the executable. No --repo-dir: am resolves the run by id."""
    return ["logs", run, card, "--phase", phase, "--attempt", attempt]


def main(argv):
    run, card, phase, attempt = argv
    am = shutil.which("am")
    proc = subprocess.run([am, *logs_argv(run, card, phase, attempt)], capture_output=True,
                          text=True, stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    return emit(json.loads(proc.stdout))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_logs.py -q`
Expected: PASS, `10 passed`.

- [ ] **Step 5: Run the architecture tier to confirm no layering or duplication break**

Run: `python3 -m pytest tests/architecture -q`
Expected: PASS (no failures; `test_shared_python_helpers_are_defined_once` and `test_layers_import_only_what_their_allowlist_permits` included).

- [ ] **Step 6: Commit**

```bash
git add core/backend/runs/runs-logs.py tests/core/backend/runs/test_runs_logs.py
git commit -m "feat(runs): runs-logs.py passes one attempt's am logs envelope through"
```

---

### Task 2: Error paths (AmBadOutput, AmMissing, Usage, HelperError) and the final docstring

**Files:**
- Modify: `tests/core/backend/runs/test_runs_logs.py` (append at end of file)
- Modify: `core/backend/runs/runs-logs.py` (replace whole file)

**Interfaces:**
- Consumes: from Task 1's test file: `world`, `env_for`, `run`, `set_raw`, `calls`, `write_exec`, `ARGS`, `SCRIPT`; from Task 1's helper: `AM_TIMEOUT`, `logs_argv`, `main`.
- Produces: helper names `USAGE = "usage: runs-logs.py RUN CARD PHASE ATTEMPT"`, `class BadOutput(Exception)`, `failure(kind, message, code=0) -> int`, `envelope_of(stdout, returncode) -> dict`, `guarded(argv) -> int` (the `__main__` entry point). Test helper `load_helper()` returning the script loaded as module `runs_logs`.

- [ ] **Step 1: Write the failing tests**

Append to the end of `tests/core/backend/runs/test_runs_logs.py`:

```python


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
    assert out["error"]["message"]


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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_logs.py -q`
Expected: the 10 Task 1 tests PASS; the 15 new test cases FAIL:
- `test_non_json_output_is_am_bad_output[*]` and `test_non_object_or_no_ok_is_am_bad_output[list|null|string]`: `assert len(lines) == 1` fails (json.loads raises a traceback, stdout empty) or `out["ok"]` fails for non-dict output.
- `test_non_object_or_no_ok_is_am_bad_output[no-ok|ok-string|ok-int|ok-null]`: the object is passed through, so `out["ok"] is False` or `out["error"]` fails.
- `test_am_missing`: `assert len(lines) == 1` fails (TypeError traceback from running `None`).
- `test_usage_wrong_argc[*]`: `assert len(lines) == 1` fails (ValueError from unpacking).
- `test_am_cannot_start_is_helper_error`: `assert len(lines) == 1` fails (OSError traceback).
- `test_am_timeout_is_helper_error`: `AttributeError: module 'runs_logs' has no attribute 'guarded'`.

- [ ] **Step 3: Write the implementation**

Replace the whole of `core/backend/runs/runs-logs.py` with:

```python
#!/usr/bin/env python3
"""One attempt's output snapshot: an `am logs` passthrough.

    runs-logs.py RUN CARD PHASE ATTEMPT

Runs `am logs RUN CARD --phase PHASE --attempt ATTEMPT` as an argv list (no
shell, stdin /dev/null, 60 s timeout). No --repo-dir is sent: am resolves the
run by id. The four arguments go to am verbatim; am refuses bad ones itself.

Prints exactly one JSON line on EVERY path:
- am's envelope, unchanged, whether {"ok": true, "data": ...} or
  {"ok": false, "error": ...}. The envelope's `ok` decides, not am's exit code;
  `data` is neither inspected nor trimmed (tail-limiting is the store's job);
- {"ok": false, "error": {"type": "AmMissing", ...}} when am is not on PATH;
- {"ok": false, "error": {"type": "AmBadOutput", ...}} when am's stdout is not
  JSON, is not an object, or has no boolean `ok`;
- {"ok": false, "error": {"type": "HelperError", ...}} on any unexpected
  failure (a timeout, an am that cannot start);
- {"ok": false, "error": {"type": "Usage", ...}} when not given exactly four
  arguments.
Exit 0 whenever a line was printed, refusals and errors included; exit 2 for
Usage only. Only the documented `am logs` command is used; am's database and
on-disk layout are never read.
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-logs.py RUN CARD PHASE ATTEMPT"
AM_TIMEOUT = 60


class BadOutput(Exception):
    """am printed something that is not an envelope; the message says what."""


def failure(kind, message, code=0):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def logs_argv(run, card, phase, attempt):
    """am's argv after the executable. No --repo-dir: am resolves the run by id."""
    return ["logs", run, card, "--phase", phase, "--attempt", attempt]


def envelope_of(stdout, returncode):
    """am's envelope, checked only for shape: a JSON object with a boolean `ok`."""
    exit_note = " (exit " + str(returncode) + ")."
    try:
        envelope = json.loads(stdout)
    except ValueError:
        raise BadOutput("am logs did not print JSON" + exit_note)
    if not isinstance(envelope, dict):
        raise BadOutput("am logs printed JSON that is not an object" + exit_note)
    if not isinstance(envelope.get("ok"), bool):
        raise BadOutput("am logs printed an object without a boolean ok field" + exit_note)
    return envelope


def main(argv):
    if len(argv) != 4:
        return failure("Usage", USAGE, 2)
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    proc = subprocess.run([am, *logs_argv(*argv)], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    try:
        envelope = envelope_of(proc.stdout, proc.returncode)
    except BadOutput as e:
        return failure("AmBadOutput", str(e))
    return emit(envelope)


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception (a timeout, an am that cannot start) - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The logs snapshot failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_logs.py -q`
Expected: PASS, `25 passed`.

- [ ] **Step 5: Run the full verification**

Run: `bash ./tests/run.sh`
Expected: pytest reports no failures (including `tests/architecture` unchanged and the 2.1/2.2 runs tests), every QML test file prints `Totals` with 0 failed, no `TypeError|ReferenceError|...` lines, script exits 0.

- [ ] **Step 6: Confirm scope**

Run: `git status --porcelain`
Expected: only `core/backend/runs/runs-logs.py` and `tests/core/backend/runs/test_runs_logs.py` listed as modified (plus this plan/spec under `docs/superpowers/` if not yet committed). `runs-snapshot.py`, `runs-watch.py` and their tests must not appear.

- [ ] **Step 7: Commit**

```bash
git add core/backend/runs/runs-logs.py tests/core/backend/runs/test_runs_logs.py
git commit -m "feat(runs): runs-logs.py error paths - AmBadOutput, AmMissing, Usage, HelperError"
```
