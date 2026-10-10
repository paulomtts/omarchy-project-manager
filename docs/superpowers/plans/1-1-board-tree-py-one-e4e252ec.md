# 1.1 board-tree.py: one project's brd tree by root — design

Card: `e4e252ec` (subtask of story `66107096`). Parent design:
`docs/superpowers/specs/2026-10-05-dispatch-from-runs-design.md`, cited below as "DFR l.N".

## Purpose

The Runs-screen dispatch dialog has to read the board of a project that may not be the open
one. `BoardStore` can read only the open project's tree (DFR l.139-144). This card adds a
read-only backend helper, `core/backend/boards/board-tree.py`, with two modes:

- `board-tree.py ROOT` returns one project's `brd tree` as one JSON line.
- `board-tree.py --probe ROOT [ROOT ...]` gives a fast, brd-free reachability check for many
  roots.

Nothing calls the helper yet. The store wiring belongs to a later card.

## Inherited constraints

- `board-tree.py ROOT` runs `brd tree` with `cwd=ROOT`, as an argv list, with stdin from
  devnull and a 20 s timeout, and prints one JSON line (DFR l.148-149).
- Success is `{"ok": true, "data": [...]}`, which is brd's tree unchanged (DFR l.149-150).
- Failure is `{"ok": false, "error": {"type", "message"}}`. The type is one of `RootMissing`,
  `BrdMissing`, `BrdFailed` (brd's own error message, for example `ProjectNotFoundError`),
  `BrdBadOutput` or `HelperError` (DFR l.150-152).
- `--probe ROOT [ROOT ...]` never runs brd. It prints
  `{"ok": true, "projects": [{"root", "ok", "reason"?}]}` in argv order. A root is ok when it
  is a directory holding `.brd` (DFR l.153-156).
- Both modes use `common.json_line.emit` and exit 0 whenever a line was printed (DFR l.158).
- Only documented brd commands are used, and brd's database is never read (DFR l.158-159).
- Follow `core/backend/boards/archive-milestones.py`'s conventions (DFR l.145-146; card).
- Tests go in `tests/core/backend/boards/test_board_tree.py` with a fake `brd` on PATH. They
  cover: the cwd is ROOT, passthrough, each error type, the timeout, probe ok and not ok in
  argv order, and that the probe never runs brd (DFR l.242-244; card).
- Layering per `docs/architecture.md`, and `tests/architecture` must pass. `emit` is defined
  once repo-wide (`tests/architecture/test_layers.py:231`), so it is imported and never
  redefined. `core/backend/` holds no `.qml`/`.js` (`test_layers.py:223`).
- Verification is `bash tests/run.sh` green. Tests come first (TDD). Docstrings and comments
  state the contract only, with no narrative (card).

## Behaviour

### Invocation and output

- Every invocation prints exactly one line on stdout: a compact JSON object made by
  `emit(payload, 0)`. It then exits 0. Nothing else is written to stdout. stderr is not part
  of the contract.
- The argv forms are:
  - `board-tree.py ROOT`: tree mode. There is exactly one positional argument, and it does not
    start with `-`.
  - `board-tree.py --probe [ROOT ...]`: probe mode. `--probe` must be the first argument.
    Every argument after it is a root taken verbatim, including one that starts with `-`.
  - Anything else is a usage error: no arguments, two or more roots without `--probe`, or a
    single argument that starts with `-` other than `--probe` (such as `--help`). It prints
    `{"ok": false, "error": {"type": "HelperError", "message": "usage: board-tree.py ROOT | board-tree.py --probe ROOT [ROOT ...]"}}`
    and runs nothing.

### Tree mode (`board-tree.py ROOT`)

The checks run in this order:

1. **RootMissing.** If `os.path.isdir(ROOT)` is false (missing, a file, or `""`), the helper
   prints `{"type": "RootMissing", "message": "project directory not found: ROOT"}`
   (ROOT verbatim). brd is not run.
2. **Run.** Otherwise it runs `subprocess.run(["brd", "tree"], cwd=ROOT,
   stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=TIMEOUT_SECONDS)` with
   module constant `TIMEOUT_SECONDS = 20`. brd is found on `PATH`. Only `brd tree` is ever run,
   once.
3. **BrdMissing.** On `FileNotFoundError`, the message is `"brd was not found on PATH"`.
4. **Timeout.** On `subprocess.TimeoutExpired`, the type is **`BrdFailed`** and the message
   is `"brd tree timed out after 20 s"`. The number is `TIMEOUT_SECONDS`, formatted with
   `%g`. `subprocess.run` kills the child, so the helper still prints its line promptly. The
   parent spec does not name a type for this case. `BrdFailed` is chosen because brd ran and
   did not answer, and the dialog treats every non-ok tree read the same way (DFR l.234).
5. **Parse.** stdout is parsed with `json.loads`. If that fails, the payload is `None`.
6. **Success.** If the exit code is 0 and the payload is a dict with `ok is True` and a list
   `data`, the helper prints the payload as parsed. The result equals brd's JSON value: the
   same keys, the same key order and every extra top-level key brd sent. It is re-serialized
   onto one line. Pretty-printed or multi-line brd output is accepted. Non-ASCII may come out
   `\u`-escaped, and that is still the same JSON value.
7. **BrdFailed (brd said no).** If the payload is a dict whose `error` is a dict with a
   non-empty `message`, the message is that string verbatim. This holds whatever the exit
   code is. Example: in a directory brd does not know, the message is
   `"no registered project at or above /tmp; run \`brd init\` there"` (type
   `ProjectNotFoundError` on brd's side, exit 1).
8. **BrdFailed (other non-zero exit).** If the exit code is not 0 and step 7 did not apply,
   the message is stderr stripped. If that is empty, it is stdout stripped. If that is also
   empty, it is `"brd tree exited with N"`.
9. **BrdBadOutput.** If the exit code is 0 and none of the above applied (stdout not JSON, not
   an object, `ok` not `true`, or `data` missing or not a list), the message is
   `"brd tree returned unexpected output"`.
10. **HelperError (unexpected).** Any other exception escaping the steps above (for example
    `PermissionError` when ROOT cannot be entered) is caught at the top level. It prints
    `{"type": "HelperError", "message": str(exc) or exc class name}`. No traceback goes to
    stdout.

A failure line is always exactly `{"ok": false, "error": {"type": T, "message": M}}`, where
`M` is a non-empty string.

### Probe mode (`board-tree.py --probe ROOT ...`)

- It never runs brd or any other process, and it reads no file contents. It only stats paths.
- Output: `{"ok": true, "projects": [...]}`. There is one entry per argv root, in argv order.
  Duplicates are repeated rather than merged. `--probe` with no roots gives `"projects": []`.
- Each entry, checked in order:
  - `{"root": R, "ok": false, "reason": "not a directory"}` when `os.path.isdir(R)` is false.
  - `{"root": R, "ok": false, "reason": "no .brd marker"}` when
    `os.path.exists(os.path.join(R, ".brd"))` is false. The marker may be a file or a
    directory.
  - `{"root": R, "ok": true}` otherwise, with no `reason` key.
- `root` is the argv string verbatim, never normalized, so the caller can match rows by key.

## Open issue for the reviewer: the `.brd` marker does not exist on this machine

The probe rule above (card and DFR l.72-73, l.154-155) assumes that every brd project has a
`.brd` marker in its root. On 2026-10-09, none of the 8 roots from `brd projects` on this
machine has a `.brd` entry. All of them are directories. The repo's own `.gitignore` lists
`.brd` (commit `a200565`), so older brd versions apparently wrote it. Current brd resolves
the project from its registry by path ("no registered project at or above …"). As specified,
the probe would therefore report every real project as `"no .brd marker"`, and step 1 of the
dialog would disable all of them.

This card implements the specified contract, because it is the card's and the parent spec's
explicit rule, and all tests use temporary directories with a `.brd` they create. Before the
store card wires `--probe` into step 1, someone has to decide whether the marker rule should
change, for example to "is a directory" only, with a failed tree read as the real check
(DFR l.74-75 already handles that path). Changing it is out of scope here. It is
a one-line change to the probe's second check and its test.

## Out of scope

- Wiring into `RunStore` (`dispatchProjectRunner`, `dispatchTargetRunner`), `HelperRunner`
  registration, and `docs/architecture.md:112` (sibling store card).
- `Runs.dispatchProjects` / `dispatchTargets` in `core/domain/runs.js` (sibling domain card).
- Indexing the tree (`Board.indexTree`), filtering targets, and any UI.
- `start-run.py` run-id discovery (DFR l.163-172).
- Any other brd command, reading brd's database, or caching.

## Files

- Create `core/backend/boards/board-tree.py` (executable, `#!/usr/bin/env python3`). Its
  module docstring states both argv forms, the output shapes, the error types and exit 0. The
  layout follows `archive-milestones.py`: `sys.path.insert(0, <dir>/..)`, then
  `from common.json_line import emit  # noqa: E402`, `TIMEOUT_SECONDS = 20`, a
  `main(argv) -> int` that returns `emit(..., 0)`, and `sys.exit(main(sys.argv))`.
  Suggested internal split: `tree(root) -> dict`, `probe(roots) -> dict`, and
  `failure(type, message) -> dict`, with `main` holding the usage check and the top-level
  `except Exception`.
- Create `tests/core/backend/boards/test_board_tree.py`.
- No other file changes.

## Tests

All of these tests are in the backend pytest tier, in `tests/core/backend/boards/test_board_tree.py`.
The helper is a standalone process whose contract is argv, cwd, PATH, stdout and exit code,
so it is tested end to end as a subprocess, the same way `test_archive_milestones.py` is.
The exception is the timeout test, which runs in-process (see T6).

Fixture: as in `test_archive_milestones.py`. A fake `brd` shell script goes in
`tmp_path/bin`. It is made executable and is the only thing on `PATH`
(`env = {"PATH": bindir, "CALLS": log, ...}`). It appends `brd $* (cwd=$(pwd))` to `$CALLS`,
then behaves according to env vars: `FAKE_OUT` (printed to stdout), `FAKE_ERR` (stderr),
`FAKE_EXIT` (exit code, default 0) and `FAKE_SLEEP` (seconds to sleep first). The sleep must
be `exec sleep "$FAKE_SLEEP"`. Without `exec`, the killed `sh` leaves an orphan `sleep`
holding the stdout pipe open, and `subprocess.run`'s post-kill `communicate()` waits for it. The project is
`tmp_path/"my project"` (with a space), which contains `.brd/`. `run(box, *args)` returns
`(returncode, json of the last stdout line)` and also asserts that stdout has exactly one
line.

| # | test | asserts |
|---|---|---|
| T1 | tree runs `brd tree` once in ROOT | exit 0; calls log == `["brd tree (cwd=<project resolved>)"]` |
| T2 | tree passes brd's payload through | fake prints `{"ok": true, "data": [{"id": "a", "children": [], "title": "é"}], "extra": 1}`; output == that value exactly (incl. `extra`) |
| T3 | pretty-printed brd output still passes through as one line | fake prints multi-line JSON; one stdout line, equal value |
| T4 | stdin is devnull | the helper is run with `input="leak\n"`; the fake does `read l; echo "stdin=$l" >> $CALLS`; the log shows `stdin=` (empty) |
| T5 | RootMissing for a missing path, a file and `""` (parametrized) | `error.type == "RootMissing"`, message contains ROOT; calls log empty |
| T6 | timeout gives BrdFailed and kills brd | in-process: load the module with `importlib.util.spec_from_file_location`, `monkeypatch.setattr(mod, "TIMEOUT_SECONDS", 0.5)`, `monkeypatch.setenv("PATH", bindir)`, fake sleeps 30; `mod.main([...])` returns 0 within a few seconds; captured line has type `BrdFailed` and message `"brd tree timed out after 0.5 s"`. Plus `mod.TIMEOUT_SECONDS == 20` checked separately. |
| T7 | BrdMissing | PATH is an empty dir; type `BrdMissing`, message `"brd was not found on PATH"` |
| T8 | BrdFailed carries brd's own message | fake prints the real ProjectNotFoundError line and exits 1; message == brd's `error.message` verbatim |
| T9 | BrdFailed falls back to stderr, then stdout, then exit code (parametrized) | non-JSON stderr only / non-JSON stdout only / nothing, exit 3; messages stderr text / stdout text / `"brd tree exited with 3"` |
| T10 | BrdBadOutput (parametrized) | exit 0 with: `not json`, `[]`, `{"ok": false}`, `{"ok": true}`, `{"ok": true, "data": {}}`; type `BrdBadOutput` |
| T11 | HelperError on usage (parametrized) | no args, two roots, `--help`; type `HelperError`, message starts `usage:`; exit 0; calls log empty |
| T12 | HelperError on an unexpected exception | ROOT is a dir with mode 000, so entering it raises `PermissionError`; type `HelperError`, exit 0, one line. Skipped when running as root (`os.geteuid() == 0`). |
| T13 | every printed line exits 0 | covered by asserting `code == 0` in T1-T12 and T14-T16 |
| T14 | probe in argv order with reasons | roots: ok project, missing path, a file, a dir without `.brd`, a dir with a `.brd` *file*, the ok project again; `projects` == exact list in that order with reasons `not a directory` / `not a directory` / `no .brd marker`, ok entries without a `reason` key, duplicate repeated |
| T15 | probe never runs brd | PATH holds the fake brd; after a probe of several roots the calls log is empty. Also with PATH empty, the probe still prints `ok: true` |
| T16 | probe with no roots | `{"ok": true, "projects": []}` |
| T17 | probe takes a `-`-leading root verbatim | `--probe -x` gives `[{"root": "-x", "ok": false, "reason": "not a directory"}]` |

`tests/architecture` needs no new test. It must still pass. In particular, the helper never
defines `emit`.

## Review focus (failure modes the tests above pin)

1. A ROOT with spaces or non-ASCII must reach brd as the cwd intact (T1 uses "my project", T2
   uses non-ASCII data).
2. brd waiting on stdin would hang the dialog until the timeout (T4).
3. A helper crash must still produce one parseable line, or the store gets nothing (T11, T12).
4. A probe that shells out would make opening the dialog slow on a large registry (T15).
5. Probe rows must keep the caller's exact strings and order, because the store matches them
   to `projectRoots` (T14, T17).

## Verification

`bash tests/run.sh` is green: pytest, including `tests/architecture`, and the QML suites,
which are untouched.

---

# 1.1 board-tree.py (card e4e252ec) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `core/backend/boards/board-tree.py`, a read-only helper that prints one project's `brd tree` as one JSON line (`board-tree.py ROOT`) or a brd-free reachability check for many roots (`board-tree.py --probe ROOT ...`).

**Architecture:** One standalone Python script in the `archive-milestones.py` style: `failure()`, `tree(root)`, `probe(roots)` build payload dicts; `main(argv)` picks the mode, catches any unexpected exception as `HelperError`, and prints the payload once through the shared `common.json_line.emit`, always exiting 0. Tests drive it as a subprocess against a fake `brd` shell script that is the only thing on `PATH`; the timeout test loads it in-process to shrink `TIMEOUT_SECONDS`.

**Tech Stack:** Python 3 stdlib (`json`, `os`, `subprocess`, `sys`), pytest.

**Spec:** `docs/superpowers/specs/1-1-board-tree-py-one-e4e252ec.md` (prepended above, verbatim).

## Global Constraints

- Tree mode runs exactly `["brd", "tree"]`, `cwd=ROOT`, `stdin=subprocess.DEVNULL`, `capture_output=True`, `text=True`, `timeout=TIMEOUT_SECONDS`, once; `TIMEOUT_SECONDS = 20` (module constant, read at call time).
- Success line is brd's parsed payload unchanged (`{"ok": true, "data": [...]}` plus any extra keys, same order).
- Failure line is exactly `{"ok": false, "error": {"type": T, "message": M}}`, `M` non-empty, `T` ∈ `RootMissing`, `BrdMissing`, `BrdFailed`, `BrdBadOutput`, `HelperError`.
- Usage message, verbatim: `usage: board-tree.py ROOT | board-tree.py --probe ROOT [ROOT ...]`.
- Messages, verbatim: `project directory not found: ROOT`, `brd was not found on PATH`, `brd tree timed out after %g s`, `brd tree exited with N`, `brd tree returned unexpected output`.
- Probe never runs any process and reads no file contents; reasons are `not a directory` and `no .brd marker`; ok entries have no `reason` key; `root` is the argv string verbatim.
- Every invocation prints exactly one stdout line via `emit(payload, 0)` and exits 0.
- `emit` is imported from `common.json_line`, never redefined (`tests/architecture/test_layers.py` checks `def emit(` appears once repo-wide). No `.qml`/`.js` under `core/backend/`.
- Only documented brd commands; brd's database is never read.
- Docstrings and comments state the contract only, no narrative.
- File list is exactly: create `core/backend/boards/board-tree.py` (mode 755, `#!/usr/bin/env python3`), create `tests/core/backend/boards/test_board_tree.py`. No other file changes.
- Verification: `bash tests/run.sh` green.

## Review Focus

The spec's own five review-focus items are pinned by T1/T2, T4, T11/T12, T15 and T14/T17. These five further inputs are implied by the spec but not in its test table; each gets a test in the owning task:

1. brd answers `{"ok": false, "error": {"message": ...}}` with **exit 0**: must be `BrdFailed` with brd's message, not `BrdBadOutput` (spec step 7 "whatever the exit code is"). Test: Task 2 `test_brd_error_message_wins_even_with_exit_zero`.
2. brd prints a valid success payload but **exits non-zero**: must not pass through; `BrdFailed` with stderr. Test: Task 2 `test_a_success_payload_with_a_non_zero_exit_is_brdfailed`.
3. brd's error object has an **empty message**: falls back to stderr rather than printing an empty message. Test: Task 2 `test_an_empty_brd_error_message_falls_back_to_stderr`.
4. A **relative ROOT** resolves against the helper's own cwd, and brd runs there. Test: Task 1 `test_a_relative_root_resolves_against_the_helpers_cwd`.
5. A probe root with a **trailing slash** (or other non-normalized form) is echoed back verbatim, so the store's key match still works. Test: Task 3 `test_probe_echoes_a_non_normalized_root_verbatim`.

## File structure

- `core/backend/boards/board-tree.py` — the helper. Functions: `failure(error_type, message) -> dict`, `tree(root) -> dict`, `probe(roots) -> dict`, `main(argv) -> int`. Constants: `TIMEOUT_SECONDS = 20`, `USAGE`.
- `tests/core/backend/boards/test_board_tree.py` — subprocess tests against a fake `brd`, plus two in-process tests (timeout constant, timeout behaviour).

## Running tests

`python3` on this machine has no pytest, so every pytest command below uses uv's throwaway environment (the same fallback `tests/run.sh` uses). If `python3 -c 'import pytest'` succeeds for you, `python3 -m pytest ...` is equivalent. Never kill stuck tests by name; the commands are wrapped in `timeout`.

---

### Task 1: Tree mode happy path, usage, RootMissing, BrdBadOutput

**Files:**
- Create: `core/backend/boards/board-tree.py`
- Create: `tests/core/backend/boards/test_board_tree.py`

**Interfaces:**
- Consumes: `common.json_line.emit(payload, code=0) -> int` (prints `json.dumps(payload)` on one line, returns `code`).
- Produces: `board-tree.py` module with `TIMEOUT_SECONDS = 20`, `USAGE: str`, `failure(error_type: str, message: str) -> dict`, `tree(root: str) -> dict`, `main(argv: list[str]) -> int`. Test helpers `SCRIPT`, `FAKE_BRD`, fixture `box`, `run(box, *args, extra_env=None, stdin_text="", cwd=None) -> (int, dict)`, `calls(box) -> list[str]`, `load_module()` — reused by Tasks 2 and 3.

- [ ] **Step 1: Write the failing tests**

Create `tests/core/backend/boards/test_board_tree.py` with exactly this content:

```python
"""board-tree.py against a fake `brd` on PATH: tree mode runs only `brd tree`, once,
in ROOT; probe mode never runs brd. Every call prints one JSON line and exits 0."""
import importlib.util
import json
import os
import shutil
import stat
import subprocess
import sys
import time

import pytest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "core", "backend", "boards", "board-tree.py")

FAKE_BRD = """#!/bin/sh
echo "brd $* (cwd=$(pwd))" >> "$CALLS"
if [ -n "$FAKE_READ" ]; then
  read l
  echo "stdin=$l" >> "$CALLS"
fi
if [ -n "$FAKE_SLEEP" ]; then
  exec "$SLEEP_BIN" "$FAKE_SLEEP"
fi
printf '%s' "$FAKE_OUT"
printf '%s' "$FAKE_ERR" >&2
exit "${FAKE_EXIT:-0}"
"""

USAGE = "usage: board-tree.py ROOT | board-tree.py --probe ROOT [ROOT ...]"


@pytest.fixture
def box(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    brd = bindir / "brd"
    brd.write_text(FAKE_BRD)
    brd.chmod(brd.stat().st_mode | stat.S_IEXEC)
    empty = tmp_path / "empty"
    empty.mkdir()
    project = tmp_path / "my project"
    (project / ".brd").mkdir(parents=True)
    calls_log = tmp_path / "calls.log"
    calls_log.write_text("")
    env = {"PATH": str(bindir), "CALLS": str(calls_log), "SLEEP_BIN": shutil.which("sleep")}
    return {"env": env, "bindir": bindir, "empty": empty, "project": project, "calls": calls_log, "tmp": tmp_path}


def run(box, *args, extra_env=None, stdin_text="", cwd=None):
    env = dict(box["env"], **(extra_env or {}))
    proc = subprocess.run([sys.executable, SCRIPT, *args], env=env, input=stdin_text, cwd=cwd,
                          capture_output=True, text=True, timeout=60)
    lines = proc.stdout.splitlines()
    assert len(lines) == 1, proc.stdout + proc.stderr
    return proc.returncode, json.loads(lines[0])


def calls(box):
    return box["calls"].read_text().splitlines()


def load_module():
    spec = importlib.util.spec_from_file_location("board_tree", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


OK_TREE = {"ok": True, "data": []}


def test_tree_runs_brd_tree_once_in_root(box):
    code, out = run(box, str(box["project"]), extra_env={"FAKE_OUT": json.dumps(OK_TREE)})
    assert code == 0
    assert out == OK_TREE
    assert calls(box) == ["brd tree (cwd=%s)" % box["project"].resolve()]


def test_tree_passes_brds_payload_through_unchanged(box):
    payload = {"ok": True, "data": [{"id": "a", "children": [], "title": "é"}], "extra": 1}
    code, out = run(box, str(box["project"]), extra_env={"FAKE_OUT": json.dumps(payload, ensure_ascii=False)})
    assert code == 0
    assert out == payload
    assert list(out) == ["ok", "data", "extra"]


def test_pretty_printed_brd_output_passes_through_as_one_line(box):
    payload = {"ok": True, "data": [{"id": "a", "children": [{"id": "b", "children": []}]}]}
    code, out = run(box, str(box["project"]), extra_env={"FAKE_OUT": json.dumps(payload, indent=2)})
    assert code == 0
    assert out == payload


def test_brd_gets_devnull_as_stdin(box):
    code, out = run(box, str(box["project"]), stdin_text="leak\n",
                    extra_env={"FAKE_READ": "1", "FAKE_OUT": json.dumps(OK_TREE)})
    assert code == 0
    assert out == OK_TREE
    assert calls(box)[1] == "stdin="


def test_a_relative_root_resolves_against_the_helpers_cwd(box):
    code, out = run(box, "my project", cwd=str(box["tmp"]), extra_env={"FAKE_OUT": json.dumps(OK_TREE)})
    assert code == 0
    assert out == OK_TREE
    assert calls(box) == ["brd tree (cwd=%s)" % box["project"].resolve()]


@pytest.mark.parametrize("kind", ["missing", "file", "empty string"])
def test_a_missing_root_is_rootmissing_and_runs_nothing(box, kind):
    if kind == "missing":
        root = str(box["tmp"] / "nope")
    elif kind == "file":
        a_file = box["tmp"] / "a file"
        a_file.write_text("x")
        root = str(a_file)
    else:
        root = ""
    code, out = run(box, root)
    assert code == 0
    assert out == {"ok": False, "error": {"type": "RootMissing", "message": "project directory not found: %s" % root}}
    assert calls(box) == []


@pytest.mark.parametrize("stdout", ["not json", "[]", '{"ok": false}', '{"ok": true}', '{"ok": true, "data": {}}'])
def test_unexpected_output_with_exit_zero_is_brdbadoutput(box, stdout):
    code, out = run(box, str(box["project"]), extra_env={"FAKE_OUT": stdout})
    assert code == 0
    assert out == {"ok": False, "error": {"type": "BrdBadOutput", "message": "brd tree returned unexpected output"}}


@pytest.mark.parametrize("args", [[], ["a", "b"], ["--help"], ["-x"]])
def test_bad_usage_is_a_helpererror_and_runs_nothing(box, args):
    code, out = run(box, *args)
    assert code == 0
    assert out == {"ok": False, "error": {"type": "HelperError", "message": USAGE}}
    assert out["error"]["message"].startswith("usage:")
    assert calls(box) == []


def test_timeout_constant_is_twenty_seconds():
    assert load_module().TIMEOUT_SECONDS == 20
```

Note: `two roots` uses `["a", "b"]`; neither exists, which proves usage is checked before any root.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/boards/test_board_tree.py -q`
Expected: every test FAILs or ERRORs — the subprocess tests with `assert len(lines) == 1` (python prints "can't open file ... board-tree.py" to stderr, nothing to stdout), `test_timeout_constant_is_twenty_seconds` with `FileNotFoundError`.

- [ ] **Step 3: Write the minimal implementation**

Create `core/backend/boards/board-tree.py` with exactly this content:

```python
#!/usr/bin/env python3
"""Read one project's brd tree, or probe project roots without running brd.

    board-tree.py ROOT
    board-tree.py --probe [ROOT ...]

Tree mode runs `brd tree` once with cwd=ROOT, stdin from /dev/null and a
TIMEOUT_SECONDS timeout. It prints brd's payload unchanged, {"ok": true,
"data": [...]}, or {"ok": false, "error": {"type", "message"}} where type is
RootMissing, BrdMissing, BrdFailed (brd's own message, a non-zero exit or the
timeout), BrdBadOutput or HelperError (bad usage or any unexpected exception).

Probe mode runs no process and only stats paths. Every argument after --probe
is a root. It prints {"ok": true, "projects": [{"root", "ok", "reason"?}]}, one
entry per root in argv order with the root verbatim; a root is ok when it is a
directory holding a `.brd` entry.

Every invocation prints exactly one JSON line and exits 0.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

TIMEOUT_SECONDS = 20
USAGE = "usage: board-tree.py ROOT | board-tree.py --probe ROOT [ROOT ...]"


def failure(error_type, message):
    return {"ok": False, "error": {"type": error_type, "message": message}}


def tree(root):
    if not os.path.isdir(root):
        return failure("RootMissing", "project directory not found: %s" % root)
    proc = subprocess.run(["brd", "tree"], cwd=root, stdin=subprocess.DEVNULL,
                          capture_output=True, text=True, timeout=TIMEOUT_SECONDS)
    try:
        payload = json.loads(proc.stdout)
    except ValueError:
        payload = None
    if (proc.returncode == 0 and isinstance(payload, dict) and payload.get("ok") is True
            and isinstance(payload.get("data"), list)):
        return payload
    return failure("BrdBadOutput", "brd tree returned unexpected output")


def main(argv):
    args = argv[1:]
    if len(args) == 1 and not args[0].startswith("-"):
        payload = tree(args[0])
    else:
        payload = failure("HelperError", USAGE)
    return emit(payload, 0)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

Then make it executable:

```bash
chmod 755 core/backend/boards/board-tree.py
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/boards/test_board_tree.py tests/architecture -q`
Expected: all PASS (architecture included: `emit` is imported, not defined).

- [ ] **Step 5: Commit**

```bash
git add core/backend/boards/board-tree.py tests/core/backend/boards/test_board_tree.py
git commit -m "feat(boards): board-tree.py prints one project's brd tree as one JSON line"
```

---

### Task 2: Tree mode failures — BrdMissing, timeout, BrdFailed, HelperError

**Files:**
- Modify: `core/backend/boards/board-tree.py` (functions `tree` and `main`)
- Test: `tests/core/backend/boards/test_board_tree.py` (append)

**Interfaces:**
- Consumes: from Task 1 — `failure(error_type, message) -> dict`, `USAGE`, `TIMEOUT_SECONDS`; test helpers `box`, `run(...)`, `calls(box)`, `load_module()`.
- Produces: final `tree(root) -> dict` and `main(argv) -> int` (with the top-level `except Exception` → `HelperError`). Task 3 edits only `main`'s mode dispatch.

- [ ] **Step 1: Write the failing tests**

Append to `tests/core/backend/boards/test_board_tree.py`:

```python
def test_a_brd_that_hangs_times_out_as_brdfailed_and_is_killed(box, monkeypatch, capsys):
    mod = load_module()
    monkeypatch.setattr(mod, "TIMEOUT_SECONDS", 0.5)
    for key, value in box["env"].items():
        monkeypatch.setenv(key, value)
    monkeypatch.setenv("FAKE_SLEEP", "30")
    started = time.monotonic()
    code = mod.main(["board-tree.py", str(box["project"])])
    elapsed = time.monotonic() - started
    assert code == 0
    assert elapsed < 10
    lines = capsys.readouterr().out.splitlines()
    assert len(lines) == 1
    assert json.loads(lines[0]) == {"ok": False, "error": {"type": "BrdFailed", "message": "brd tree timed out after 0.5 s"}}


def test_brd_missing_from_path_is_brdmissing(box):
    code, out = run(box, str(box["project"]), extra_env={"PATH": str(box["empty"])})
    assert code == 0
    assert out == {"ok": False, "error": {"type": "BrdMissing", "message": "brd was not found on PATH"}}


BRD_NOT_FOUND = {"ok": False, "error": {"type": "ProjectNotFoundError",
                                        "message": "no registered project at or above /tmp; run `brd init` there"}}


def test_brdfailed_carries_brds_own_message(box):
    code, out = run(box, str(box["project"]), extra_env={"FAKE_OUT": json.dumps(BRD_NOT_FOUND), "FAKE_EXIT": "1"})
    assert code == 0
    assert out == {"ok": False, "error": {"type": "BrdFailed", "message": BRD_NOT_FOUND["error"]["message"]}}


def test_brd_error_message_wins_even_with_exit_zero(box):
    code, out = run(box, str(box["project"]), extra_env={"FAKE_OUT": json.dumps(BRD_NOT_FOUND), "FAKE_EXIT": "0"})
    assert code == 0
    assert out == {"ok": False, "error": {"type": "BrdFailed", "message": BRD_NOT_FOUND["error"]["message"]}}


def test_an_empty_brd_error_message_falls_back_to_stderr(box):
    payload = {"ok": False, "error": {"type": "X", "message": ""}}
    code, out = run(box, str(box["project"]),
                    extra_env={"FAKE_OUT": json.dumps(payload), "FAKE_ERR": "fallback text\n", "FAKE_EXIT": "1"})
    assert code == 0
    assert out == {"ok": False, "error": {"type": "BrdFailed", "message": "fallback text"}}


def test_a_success_payload_with_a_non_zero_exit_is_brdfailed(box):
    code, out = run(box, str(box["project"]),
                    extra_env={"FAKE_OUT": json.dumps({"ok": True, "data": []}), "FAKE_ERR": "partial failure", "FAKE_EXIT": "2"})
    assert code == 0
    assert out == {"ok": False, "error": {"type": "BrdFailed", "message": "partial failure"}}


@pytest.mark.parametrize("fake_out,fake_err,message", [
    ("", "  boom on stderr \n", "boom on stderr"),
    ("  boom on stdout \n", "", "boom on stdout"),
    ("", "", "brd tree exited with 3"),
])
def test_brdfailed_falls_back_to_stderr_then_stdout_then_exit_code(box, fake_out, fake_err, message):
    code, out = run(box, str(box["project"]), extra_env={"FAKE_OUT": fake_out, "FAKE_ERR": fake_err, "FAKE_EXIT": "3"})
    assert code == 0
    assert out == {"ok": False, "error": {"type": "BrdFailed", "message": message}}


@pytest.mark.skipif(os.geteuid() == 0, reason="root can enter a mode-000 directory")
def test_an_unexpected_exception_is_a_helpererror_line(box):
    locked = box["tmp"] / "locked"
    locked.mkdir()
    locked.chmod(0)
    try:
        code, out = run(box, str(locked))
    finally:
        locked.chmod(0o755)
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert isinstance(out["error"]["message"], str) and out["error"]["message"]
    assert calls(box) == []
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/boards/test_board_tree.py -q`
Expected: the Task 1 tests still PASS; the new ones FAIL — the timeout test with `subprocess.TimeoutExpired` raised out of `main`, BrdMissing and the mode-000 test with `assert len(lines) == 1` (a traceback, no stdout line), the BrdFailed tests with `'BrdBadOutput' != 'BrdFailed'` style dict mismatches.

- [ ] **Step 3: Implement the failure branches**

In `core/backend/boards/board-tree.py`, replace the whole `tree` function with:

```python
def tree(root):
    if not os.path.isdir(root):
        return failure("RootMissing", "project directory not found: %s" % root)
    try:
        proc = subprocess.run(["brd", "tree"], cwd=root, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=TIMEOUT_SECONDS)
    except FileNotFoundError:
        return failure("BrdMissing", "brd was not found on PATH")
    except subprocess.TimeoutExpired:
        return failure("BrdFailed", "brd tree timed out after %g s" % TIMEOUT_SECONDS)
    try:
        payload = json.loads(proc.stdout)
    except ValueError:
        payload = None
    if (proc.returncode == 0 and isinstance(payload, dict) and payload.get("ok") is True
            and isinstance(payload.get("data"), list)):
        return payload
    error = payload.get("error") if isinstance(payload, dict) else None
    if isinstance(error, dict) and isinstance(error.get("message"), str) and error["message"]:
        return failure("BrdFailed", error["message"])
    if proc.returncode != 0:
        message = (proc.stderr.strip() or proc.stdout.strip()
                   or "brd tree exited with %d" % proc.returncode)
        return failure("BrdFailed", message)
    return failure("BrdBadOutput", "brd tree returned unexpected output")
```

and replace the whole `main` function with:

```python
def main(argv):
    args = argv[1:]
    try:
        if len(args) == 1 and not args[0].startswith("-"):
            payload = tree(args[0])
        else:
            payload = failure("HelperError", USAGE)
    except Exception as exc:
        payload = failure("HelperError", str(exc) or type(exc).__name__)
    return emit(payload, 0)
```

`TIMEOUT_SECONDS` must stay a module global read inside `tree` (not a default argument), so the in-process test's `monkeypatch.setattr` takes effect.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/boards/test_board_tree.py tests/architecture -q`
Expected: all PASS; the timeout test finishes in well under 10 s.

- [ ] **Step 5: Commit**

```bash
git add core/backend/boards/board-tree.py tests/core/backend/boards/test_board_tree.py
git commit -m "feat(boards): board-tree.py reports BrdMissing, BrdFailed and HelperError"
```

---

### Task 3: Probe mode

**Files:**
- Modify: `core/backend/boards/board-tree.py` (add `probe`, extend `main`'s dispatch)
- Test: `tests/core/backend/boards/test_board_tree.py` (append)

**Interfaces:**
- Consumes: from Tasks 1-2 — `failure`, `tree`, `USAGE`, final `main` with its `try/except`; test helpers `box`, `run(...)`, `calls(box)`.
- Produces: `probe(roots: list[str]) -> dict` returning `{"ok": True, "projects": [{"root": str, "ok": bool, "reason"?: str}]}`; `board-tree.py --probe ROOT ...` CLI consumed by the later store card.

- [ ] **Step 1: Write the failing tests**

Append to `tests/core/backend/boards/test_board_tree.py`:

```python
def test_probe_reports_each_root_in_argv_order(box):
    ok = str(box["project"])
    missing = str(box["tmp"] / "nope")
    a_file = box["tmp"] / "a file"
    a_file.write_text("x")
    bare = box["tmp"] / "bare"
    bare.mkdir()
    marker_file = box["tmp"] / "marker file"
    marker_file.mkdir()
    (marker_file / ".brd").write_text("")
    code, out = run(box, "--probe", ok, missing, str(a_file), str(bare), str(marker_file), ok)
    assert code == 0
    assert out == {"ok": True, "projects": [
        {"root": ok, "ok": True},
        {"root": missing, "ok": False, "reason": "not a directory"},
        {"root": str(a_file), "ok": False, "reason": "not a directory"},
        {"root": str(bare), "ok": False, "reason": "no .brd marker"},
        {"root": str(marker_file), "ok": True},
        {"root": ok, "ok": True},
    ]}


def test_probe_never_runs_brd(box):
    roots = [str(box["project"]), str(box["tmp"] / "nope"), str(box["empty"])]
    code, out = run(box, "--probe", *roots)
    assert code == 0
    assert out["ok"] is True
    assert calls(box) == []
    code, out = run(box, "--probe", *roots, extra_env={"PATH": str(box["empty"])})
    assert code == 0
    assert out["ok"] is True
    assert [p["ok"] for p in out["projects"]] == [True, False, False]


def test_probe_with_no_roots_is_an_empty_list(box):
    code, out = run(box, "--probe")
    assert code == 0
    assert out == {"ok": True, "projects": []}


def test_probe_takes_a_dash_leading_root_verbatim(box):
    code, out = run(box, "--probe", "-x")
    assert code == 0
    assert out == {"ok": True, "projects": [{"root": "-x", "ok": False, "reason": "not a directory"}]}


def test_probe_echoes_a_non_normalized_root_verbatim(box):
    root = str(box["project"]) + "/"
    code, out = run(box, "--probe", root)
    assert code == 0
    assert out == {"ok": True, "projects": [{"root": root, "ok": True}]}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/boards/test_board_tree.py -q`
Expected: Tasks 1-2 tests PASS; the five probe tests FAIL with dict mismatches against `{"ok": False, "error": {"type": "HelperError", "message": "usage: ..."}}`.

- [ ] **Step 3: Implement probe mode**

In `core/backend/boards/board-tree.py`, add this function directly after `tree`:

```python
def probe(roots):
    projects = []
    for root in roots:
        if not os.path.isdir(root):
            projects.append({"root": root, "ok": False, "reason": "not a directory"})
        elif not os.path.exists(os.path.join(root, ".brd")):
            projects.append({"root": root, "ok": False, "reason": "no .brd marker"})
        else:
            projects.append({"root": root, "ok": True})
    return {"ok": True, "projects": projects}
```

and replace the whole `main` function with:

```python
def main(argv):
    args = argv[1:]
    try:
        if args and args[0] == "--probe":
            payload = probe(args[1:])
        elif len(args) == 1 and not args[0].startswith("-"):
            payload = tree(args[0])
        else:
            payload = failure("HelperError", USAGE)
    except Exception as exc:
        payload = failure("HelperError", str(exc) or type(exc).__name__)
    return emit(payload, 0)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/boards/test_board_tree.py tests/architecture -q`
Expected: all PASS.

- [ ] **Step 5: Run the full verification suite**

Run: `timeout 600 bash tests/run.sh`
Expected: pytest reports no failures; every QML suite prints `Totals` with 0 failed; exit status 0. Then confirm the file set and mode:

```bash
git status --short
git ls-files -s core/backend/boards/board-tree.py
```

Expected: only the two files from this plan are changed (plus the spec/plan docs, committed by the workflow), and after commit the helper's mode is `100755`.

- [ ] **Step 6: Commit**

```bash
git add core/backend/boards/board-tree.py tests/core/backend/boards/test_board_tree.py
git commit -m "feat(boards): board-tree.py --probe checks roots for a .brd marker without brd"
```
<!-- task-pipeline: validated -->
