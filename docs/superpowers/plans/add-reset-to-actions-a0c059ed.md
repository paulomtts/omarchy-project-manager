# run-control.py learns `reset` — design

Card: `a0c059ed` ("Add reset to ACTIONS/USAGE/docstring + Python tests"), a subtask of story
`cc7f1fd6`. The parent design is `docs/superpowers/specs/runs-screen-row-redesign-design.md`,
cited below as "P l.N". Line numbers into `core/` and `tests/` come from this card's start
(`9321152`).

## Purpose

The Runs screen gets a **Close** action that runs `am reset` on a parked, escalated or dead run
(P l.11, l.80). Nothing in the plugin calls `am reset` today (P l.7). The QML store reaches am only
through `core/backend/runs/run-control.py`, which accepts `pause`, `resume` and `cancel` and nothing
else. This card makes the helper accept a fourth action, `reset`, and pins that with Python tests
(P l.84-85, l.134).

A user sees nothing yet: no store, domain or UI code sends `reset` until sibling cards land.

## Required behavior

All of it is observable through the helper's command line, the argv the (fake) `am` receives, the
helper's single stdout JSON line, and its exit code.

### Command line

- `run-control.py reset RUN REPO` is accepted (P l.84). The same RUN/REPO rules as every other
  action apply: RUN non-empty and not starting with `-`, REPO non-empty
  (`core/backend/runs/run-control.py:66`).
- `reset` takes no options. `reset RUN REPO --verify CMD` and
  `reset RUN REPO --allow-no-verification` are Usage errors, exactly as for pause and cancel
  (P l.84; `run-control.py:78`). Any other extra argument is a Usage error too.
- A Usage error prints `{"ok": false, "error": {"type": "Usage", "message": USAGE}}` and exits 2,
  and `am` is never called. Usage is checked before `am` is looked for on PATH.
- `USAGE` (the message, and the synopsis in the module docstring) becomes exactly:

  ```
  usage: run-control.py <pause|resume|cancel|reset> RUN REPO [--verify CMD]... [--allow-no-verification]
  ```

  Every action's Usage error carries this new text, not only reset's.

### What am receives

- argv after the executable: `["reset", RUN, "--repo-dir", REPO]` (P l.85), each element verbatim
  (spaces and shell metacharacters stay one element; no shell). Never `--pretty`, never `--verify`.
- stdin is `/dev/null`.

### What the helper prints

`reset` is a quick action like pause and cancel, not a long-running one like resume (P l.84):

- It runs through the same synchronous path as pause/cancel with the 60 s `AM_TIMEOUT`. It is never
  started detached and never answers `{"action": "resume", ..., "detached": true}`, however long am
  takes within the timeout.
- am's envelope is printed unchanged as one line, `{"ok": true, ...}` or `{"ok": false, ...}`, with
  exit 0. The envelope's `ok` decides, not am's exit code. Refusals am returns for reset (for
  example `RunIsLiveError`, `NotResettableError`, `UnknownRunError`) pass through untouched; the
  helper does not interpret error types.
- am exits 0 without an envelope → `AmBadOutput`, message starts `am reset ` and ends `(exit 0).`
- am exits non-zero without an envelope → `AmFailed` with the tail of am's stderr.
- am not on PATH → `AmMissing`. am hangs past `AM_TIMEOUT` or cannot start → `HelperError`, message
  starting `The run control failed: `.
- Exit 0 on every path but Usage.

These are the existing pause/cancel behaviors (module docstring, `run-control.py:18-32`); the card
extends them to reset, it does not change them.

### Documentation in the file

The module docstring (`run-control.py:2-32`) names reset everywhere it lists the actions: the title
line ("Pause, resume, cancel or reset one run: an `am pause|resume|cancel|reset` passthrough"), the
synopsis, the sentence "pause and cancel answer at once…" (now "pause, cancel and reset…"), and the
HelperError bullet ("a pause/cancel/reset timeout"). `run_am`'s docstring likewise says
pause/cancel/reset. "Only resume takes options" stays true and stays.

## Constraints inherited

- `core/backend/**` is Python stdlib only (P l.21). No new imports are needed.
- The one-JSON-line-on-every-path contract and exit 2 for Usage only (`run-control.py:18-32`).
- `tests/run.sh` is green before and after (P l.136).

## Tests

All in `tests/core/backend/runs/test_run_control.py`, pytest tier. That file is hermetic (a fake
`am` on a temp PATH serving fixtures), and the helper's contract is its subprocess I/O, so this is
the right tier: no QML is involved and the real `am` must not be touched.

Fixture change, required for any reset test: the fake am's fixture key
(`test_run_control.py:36`) must include `["reset"]`; otherwise reset falls to the name `other`,
finds no fixture and answers `UnknownRunError`. Its comment (l.24-25) and the module docstring
(l.1) name the four actions. The `USAGE` constant (l.52-54) becomes the new text, which also
re-pins every existing Usage test to it.

| Test | Proves |
|---|---|
| `test_reset_argv` | `reset r1 /p` → am called once with `["reset","r1","--repo-dir","/p"]`; no `--pretty`, no `--verify`; exit 0. |
| `test_ok_envelope_passed_through[reset]` | An ok reset envelope (e.g. `{"ok":true,"data":{"run_id":"r1","action":"reset","status":"canceled","open_in":[]}}`, the `{"ok", "data"}` shape the existing rows use) comes back unchanged. |
| `test_refusal_passed_through_exit_0` rows `("reset","RunIsLiveError")`, `("reset","NotResettableError")` | Refusals with am exit 3 pass through unchanged with exit 0. |
| `test_usage` rows `verify-reset` (`reset r1 /p --verify pytest`), `allow-reset` (`reset r1 /p --allow-no-verification`), `extra-reset` (`reset r1 /p extra`) | Options and extras are Usage (exit 2, new text, no am call). |
| `test_usage` (all existing rows) | The new USAGE text is what every Usage error prints. |
| `test_am_cannot_start_is_helper_error[reset]` | reset goes through `guarded()`'s catch-all. |
| `test_reset_bad_output_names_reset` | am exits 0 with `not json` → `AmBadOutput`, message starts `am reset ` and ends `(exit 0).` |
| `test_reset_timeout_is_helper_error` | A hanging am with `AM_TIMEOUT` patched to 0.5 → `HelperError` (in-process via `load_helper`, as `test_pause_timeout_is_helper_error`). |
| `test_reset_is_never_detached` | With `RESUME_GRACE` patched to 0.2 and an am that sleeps 1 s then prints an ok envelope, the helper prints that envelope, not a detached one. |

## Out of scope

- `core/domain/runs.js` (`controls().close`, `visibleActions`, reset error sentences) — sibling
  cards (P l.87-93).
- `core/stores/RunControlStore.qml`, `ControlFacts`, `CloseRunDialog.qml`, `RunsScreen`,
  `RunControls.qml` and their QML tests (P l.95-123, l.127-132).
- `docs/architecture.md` and the historical specs that list the old action triple
  (`2026-10-03-am-run-controls-design.md`, `2-1-run-control-py-*`, `4-1-runstore-control-*`): not
  edited.
- Any change to resume's detach logic, pause/cancel behavior, or error types.
- The QML/domain row tests currently skipped awaiting story B.

## Planner notes

- Implementation is a data change: the `ACTIONS` tuple (`run-control.py:46`), `USAGE` (l.44-45)
  and docstrings. `parse()`, `control_argv()` and `main()` already route any non-resume action
  correctly; do not restructure them.
- TDD order: fake-am key + `USAGE` constant first (existing tests then fail on the new text — that
  is the red), then the reset tests, then the source change.
- Fast loop: `python3 -m pytest tests/core/backend/runs/test_run_control.py -q` (or
  `uv run --with pytest python3 -m pytest ...`). Full gate: `bash tests/run.sh`.

---

# run-control.py learns `reset` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `core/backend/runs/run-control.py` accepts a fourth action, `reset`, passed to `am reset RUN --repo-dir REPO` on the same synchronous path as pause/cancel, with the new USAGE text and pytest coverage.

**Architecture:** A data and docstring change to the helper: add `"reset"` to `ACTIONS`, widen `USAGE` and the docstrings. `parse()`, `control_argv()` and `main()` already send every non-resume action through `run_am()` with `AM_TIMEOUT`, so they stay as they are. The hermetic test file's fake `am` learns the `reset` fixture key, and new tests pin argv, passthrough, Usage, failures, timeout and never-detached.

**Tech Stack:** Python 3 stdlib only (helper); pytest (tests), run through `uv run --with pytest` because the machine's `python3` has no pytest.

**Spec:** `docs/superpowers/specs/add-reset-to-actions-a0c059ed.md` (reproduced above this plan).

## Global Constraints

- `core/backend/**` is Python stdlib only. No new imports.
- One JSON line on stdout on every path; exit 2 for Usage only, exit 0 everywhere else.
- USAGE is exactly: `usage: run-control.py <pause|resume|cancel|reset> RUN REPO [--verify CMD]... [--allow-no-verification]`
- reset argv to am: `["reset", RUN, "--repo-dir", REPO]`. Never `--pretty`, never `--verify`, stdin `/dev/null`.
- reset is never started detached and never answers `{"action": "resume", ..., "detached": true}`.
- "Only resume takes options" stays in the docstring.
- Do not restructure `parse()`, `control_argv()` or `main()`; do not change resume's detach logic, pause/cancel behavior or error types.
- Do not edit `core/domain/runs.js`, any QML, `docs/architecture.md` or older specs.
- `bash tests/run.sh` is green at the end.

## Review Focus

1. **RUN/REPO with spaces and shell metacharacters on reset** (`reset "r 1; echo x" "/p $(whoami) & y"`): each reaches am as one argv element, unaltered. Pinned by `test_reset_args_reach_am_verbatim` (Task 1).
2. **am crashes during reset** (non-zero exit, traceback on stderr, no envelope): `AmFailed` with the stderr tail; with no stderr, the message `am reset exited 1 with no output.`. Pinned by `test_reset_am_failed` and `test_reset_am_failed_with_no_stderr` (Task 1).
3. **Reset of a run am does not know** (am answers `UnknownRunError` with exit 3): passed through unchanged, exit 0, am called once. Pinned by `test_reset_missing_fixture_unknown_run` (Task 1).
4. **am not installed when reset is pressed**: `AmMissing`, exit 0, no call. Pinned by `test_reset_am_missing` (Task 1).
5. **Near-miss reset command lines** (`Reset` capitalized, `-r1` as RUN, empty RUN, missing REPO): Usage, exit 2, no am call. Pinned by the `test_usage` rows `capital-reset`, `dash-run-reset`, `empty-run-reset`, `two-reset` (Task 1).

---

### Task 1: `reset` in run-control.py, with its Python tests

One task: the USAGE text names reset, so changing it without accepting reset would leave the helper advertising an action it refuses. A reviewer would approve or reject both together.

**Files:**
- Modify: `tests/core/backend/runs/test_run_control.py` (lines 1, 24-29, 36, 52-54, and new tests after lines 154, 199, 233, 241, 277, 286, 313, 330, 373, 412)
- Modify: `core/backend/runs/run-control.py:2-4,12,29,44-46,128`

**Interfaces:**
- Consumes: the existing test helpers in `test_run_control.py`: `world` fixture, `run(world, args, **env) -> (exit, payload)`, `set_envelope(world, name, envelope, code=0)`, `set_raw(world, name, text, code=0, stderr=None)`, `calls(world) -> list[list[str]]`, `load_helper()`, `use_world(world, monkeypatch)`, `one_line(capsys) -> dict`, `write_exec(path, text)`, constants `OK`, `UNKNOWN_RUN`, `USAGE`, `TRACEBACK`, `DETACHED`. Helper module attributes `AM_TIMEOUT` (60), `RESUME_GRACE` (10), `guarded(argv) -> int`.
- Produces: `run-control.py` with `ACTIONS = ("pause", "resume", "cancel", "reset")` and the new `USAGE`. Sibling cards (store, domain) call `run-control.py reset RUN REPO` and get am's envelope back.

All test commands run from the worktree root. Fast loop:
`timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_run_control.py -q`

- [ ] **Step 1: Teach the fake am the `reset` key and the tests the new USAGE text**

In `tests/core/backend/runs/test_run_control.py`, replace line 1:

```python
"""run-control.py: an `am pause|resume|cancel` passthrough, one JSON line on every path.
```

with:

```python
"""run-control.py: an `am pause|resume|cancel|reset` passthrough, one JSON line on every path.
```

Replace the comment at lines 24-29:

```python
# The fake am logs its argv, then (keyed on the subcommand: pause, resume or
# cancel) writes FAKE_AM_DIR/<name>.err to stderr if present, prints
# FAKE_AM_DIR/<name>.out verbatim and exits with FAKE_AM_DIR/<name>.code
# (default 0). Fixtures are copied as bytes, so they may hold invalid UTF-8. A
# missing .out fixture behaves like real am for an unknown run: an
# UnknownRunError envelope and exit 3.
```

with:

```python
# The fake am logs its argv, then (keyed on the subcommand: pause, resume,
# cancel or reset) writes FAKE_AM_DIR/<name>.err to stderr if present, prints
# FAKE_AM_DIR/<name>.out verbatim and exits with FAKE_AM_DIR/<name>.code
# (default 0). Fixtures are copied as bytes, so they may hold invalid UTF-8. A
# missing .out fixture behaves like real am for an unknown run: an
# UnknownRunError envelope and exit 3.
```

Replace line 36 (inside the `FAKE_AM` string):

```python
name = args[0] if args[:1] in (["pause"], ["resume"], ["cancel"]) else "other"
```

with:

```python
name = args[0] if args[:1] in (["pause"], ["resume"], ["cancel"], ["reset"]) else "other"
```

Replace lines 52-54:

```python
USAGE = {"ok": False, "error": {"type": "Usage", "message":
         "usage: run-control.py <pause|resume|cancel> RUN REPO"
         " [--verify CMD]... [--allow-no-verification]"}}
```

with:

```python
USAGE = {"ok": False, "error": {"type": "Usage", "message":
         "usage: run-control.py <pause|resume|cancel|reset> RUN REPO"
         " [--verify CMD]... [--allow-no-verification]"}}
```

- [ ] **Step 2: Add the reset argv tests**

After `test_cancel_argv` (ends at line 154), insert:

```python


def test_reset_argv(world):
    set_envelope(world, "reset", OK)
    code, _ = run(world, ["reset", "r1", "/p"])
    assert code == 0
    made = calls(world)
    assert made == [["reset", "r1", "--repo-dir", "/p"]]
    assert "--pretty" not in made[0]
    assert "--verify" not in made[0]
```

After `test_args_reach_am_verbatim` (ends at line 199), insert:

```python


def test_reset_args_reach_am_verbatim(world):
    # reset has no options, but RUN and REPO still arrive as one argv element each.
    set_envelope(world, "reset", OK)
    code, _ = run(world, ["reset", "r 1; echo x", "/p $(whoami) & y"])
    assert code == 0
    assert calls(world) == [["reset", "r 1; echo x", "--repo-dir", "/p $(whoami) & y"]]
```

- [ ] **Step 3: Add the reset passthrough rows and tests**

In the `test_ok_envelope_passed_through` parametrize list, replace:

```python
    ("resume", {"run_id": "r1", "status": "done"}),
])
def test_ok_envelope_passed_through(world, action, data):
```

with:

```python
    ("resume", {"run_id": "r1", "status": "done"}),
    ("reset", {"run_id": "r1", "action": "reset", "status": "canceled", "open_in": []}),
])
def test_ok_envelope_passed_through(world, action, data):
```

In the `test_refusal_passed_through_exit_0` parametrize list, replace:

```python
    ("cancel", "LockTimeoutError"),
])
def test_refusal_passed_through_exit_0(world, action, kind):
```

with:

```python
    ("cancel", "LockTimeoutError"),
    ("reset", "RunIsLiveError"),
    ("reset", "NotResettableError"),
])
def test_refusal_passed_through_exit_0(world, action, kind):
```

After `test_missing_fixture_unknown_run` (ends at line 241), insert:

```python


def test_reset_missing_fixture_unknown_run(world):
    # No reset.out: the fake am answers UnknownRunError with exit 3.
    code, out = run(world, ["reset", "r1", "/p"])
    assert code == 0
    assert out == UNKNOWN_RUN
    assert calls(world) == [["reset", "r1", "--repo-dir", "/p"]]
```

- [ ] **Step 4: Add the reset failure tests**

After `test_exit_0_without_envelope_is_am_bad_output` (ends at line 277), insert:

```python


def test_reset_bad_output_names_reset(world):
    set_raw(world, "reset", "not json\n", code=0, stderr=TRACEBACK)
    code, out = run(world, ["reset", "r1", "/p"])
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "AmBadOutput"
    assert out["error"]["message"].startswith("am reset ")
    assert out["error"]["message"].endswith("(exit 0).")
```

After `test_am_missing` (ends at line 286), insert:

```python


def test_reset_am_missing(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, out = run(world, ["reset", "r1", "/p"], PATH=str(empty))
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmMissing", "message": "am is not installed."}}
    assert calls(world) == []
```

Replace the `test_usage` parametrize block (lines 298-313):

```python
@pytest.mark.parametrize("args", [
    [],
    ["pause", "r1"],
    ["stop", "r1", "/p"],
    ["pause", "r1", "/p", "extra"],
    ["pause", "r1", "/p", "--verify", "pytest"],
    ["cancel", "r1", "/p", "--verify", "pytest"],
    ["pause", "r1", "/p", "--allow-no-verification"],
    ["resume", "r1", "/p", "--verify"],
    ["resume", "r1", "/p", "--pretty"],
    ["pause", "", "/p"],
    ["pause", "r1", ""],
    ["pause", "-r1", "/p"],
], ids=["none", "two", "unknown-action", "extra-positional", "verify-pause",
        "verify-cancel", "allow-pause", "verify-last", "unknown-option",
        "empty-run", "empty-repo", "dash-run"])
```

with:

```python
@pytest.mark.parametrize("args", [
    [],
    ["pause", "r1"],
    ["stop", "r1", "/p"],
    ["pause", "r1", "/p", "extra"],
    ["pause", "r1", "/p", "--verify", "pytest"],
    ["cancel", "r1", "/p", "--verify", "pytest"],
    ["pause", "r1", "/p", "--allow-no-verification"],
    ["resume", "r1", "/p", "--verify"],
    ["resume", "r1", "/p", "--pretty"],
    ["pause", "", "/p"],
    ["pause", "r1", ""],
    ["pause", "-r1", "/p"],
    ["reset", "r1", "/p", "--verify", "pytest"],
    ["reset", "r1", "/p", "--allow-no-verification"],
    ["reset", "r1", "/p", "extra"],
    ["Reset", "r1", "/p"],
    ["reset", "-r1", "/p"],
    ["reset", "", "/p"],
    ["reset", "r1"],
], ids=["none", "two", "unknown-action", "extra-positional", "verify-pause",
        "verify-cancel", "allow-pause", "verify-last", "unknown-option",
        "empty-run", "empty-repo", "dash-run", "verify-reset", "allow-reset",
        "extra-reset", "capital-reset", "dash-run-reset", "empty-run-reset",
        "two-reset"])
```

(The `def test_usage(world, args):` body below it is unchanged.)

Replace the `test_am_cannot_start_is_helper_error` decorator:

```python
@pytest.mark.parametrize("action", ["pause", "resume"])
def test_am_cannot_start_is_helper_error(world, action):
```

with:

```python
@pytest.mark.parametrize("action", ["pause", "resume", "reset"])
def test_am_cannot_start_is_helper_error(world, action):
```

- [ ] **Step 5: Add the reset timing tests**

After `test_pause_timeout_is_helper_error` (its last line is
`    assert out["error"]["message"].startswith("The run control failed: ")` at line 373, followed by a
single blank line and `# --- am crashed ---`), insert directly after line 373:

```python


def test_reset_timeout_is_helper_error(world, monkeypatch, capsys):
    # reset answers at once like pause: a hanging am is cut off after AM_TIMEOUT.
    write_exec(world["bin"] / "am", "#!/usr/bin/env python3\nimport time\ntime.sleep(10)\n")
    helper = load_helper()
    assert helper.AM_TIMEOUT == 60
    monkeypatch.setattr(helper, "AM_TIMEOUT", 0.5)
    use_world(world, monkeypatch)
    code = helper.guarded(["reset", "r1", "/p"])
    out = one_line(capsys)
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The run control failed: ")


def test_reset_is_never_detached(world, monkeypatch, capsys):
    # An am reset slower than RESUME_GRACE is still waited for and its envelope
    # printed: only resume is ever started detached.
    envelope = {"ok": True, "data": {"run_id": "r1", "action": "reset",
                                     "status": "canceled", "open_in": []}}
    write_exec(world["bin"] / "am",
               "#!/usr/bin/env python3\nimport json, time\ntime.sleep(1)\n"
               "print(json.dumps(%r))\n" % (envelope,))
    helper = load_helper()
    monkeypatch.setattr(helper, "RESUME_GRACE", 0.2)
    use_world(world, monkeypatch)
    code = helper.guarded(["reset", "r1", "/p"])
    out = one_line(capsys)
    assert code == 0
    assert out == envelope
```

(`%r` of the dict gives a Python literal with `True`/`[]`, which `json.dumps` inside the fake am turns into the JSON envelope.)

After `test_am_failed_with_no_stderr` (ends at line 412), insert:

```python


def test_reset_am_failed(world):
    set_raw(world, "reset", "", code=1, stderr=TRACEBACK)
    code, out = run(world, ["reset", "r1", "/p"])
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmFailed",
                                          "message": "Traceback (most recent call last):\n"
                                                     "ValueError: boom"}}


def test_reset_am_failed_with_no_stderr(world):
    set_raw(world, "reset", "", code=1)
    code, out = run(world, ["reset", "r1", "/p"])
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmFailed",
                                          "message": "am reset exited 1 with no output."}}
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_run_control.py -q`

Expected: FAIL, `33 failed, 47 passed`. Every `test_usage` row (the seven new reset rows included) and `test_usage_wins_over_am_missing` fail because the helper still prints the old USAGE text (`<pause|resume|cancel>`). Every test that runs `reset` successfully fails because the helper answers Usage with exit 2: `test_reset_argv`, `test_reset_args_reach_am_verbatim`, `test_ok_envelope_passed_through[reset-...]`, both `reset` refusal rows, `test_reset_missing_fixture_unknown_run`, `test_reset_bad_output_names_reset`, `test_reset_am_missing`, `test_am_cannot_start_is_helper_error[reset]`, `test_reset_timeout_is_helper_error`, `test_reset_is_never_detached`, `test_reset_am_failed`, `test_reset_am_failed_with_no_stderr`. All other pause/resume/cancel tests still pass.

- [ ] **Step 7: Make the helper accept `reset`**

In `core/backend/runs/run-control.py`, replace lines 2-4:

```python
"""Pause, resume or cancel one run: an `am pause|resume|cancel` passthrough.

    run-control.py <pause|resume|cancel> RUN REPO [--verify CMD]... [--allow-no-verification]
```

with:

```python
"""Pause, resume, cancel or reset one run: an `am pause|resume|cancel|reset` passthrough.

    run-control.py <pause|resume|cancel|reset> RUN REPO [--verify CMD]... [--allow-no-verification]
```

Replace line 12:

```python
pause and cancel answer at once and run with a 60 s timeout. An accepted resume
```

with:

```python
pause, cancel and reset answer at once and run with a 60 s timeout. An accepted resume
```

Replace line 29:

```python
  failure (a pause/cancel timeout, an am that cannot start);
```

with:

```python
  failure (a pause/cancel/reset timeout, an am that cannot start);
```

Replace lines 44-46:

```python
USAGE = ("usage: run-control.py <pause|resume|cancel> RUN REPO"
         " [--verify CMD]... [--allow-no-verification]")
ACTIONS = ("pause", "resume", "cancel")
```

with:

```python
USAGE = ("usage: run-control.py <pause|resume|cancel|reset> RUN REPO"
         " [--verify CMD]... [--allow-no-verification]")
ACTIONS = ("pause", "resume", "cancel", "reset")
```

Replace line 128 (the `run_am` docstring):

```python
    """pause/cancel: am answers at once. Returns (stdout, stderr, returncode)."""
```

with:

```python
    """pause/cancel/reset: am answers at once. Returns (stdout, stderr, returncode)."""
```

Leave `parse()`, `control_argv()`, `main()` and every other line untouched. `parse()` already rejects options for any action other than resume, and `main()` already sends every non-resume action through `run_am()`.

- [ ] **Step 8: Run the tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_run_control.py -q`

Expected: PASS, 60 previous tests plus 20 new test ids (`test_reset_argv`, `test_reset_args_reach_am_verbatim`, 1 ok-envelope row, 2 refusal rows, `test_reset_missing_fixture_unknown_run`, `test_reset_bad_output_names_reset`, `test_reset_am_missing`, 7 usage rows, 1 cannot-start row, `test_reset_timeout_is_helper_error`, `test_reset_is_never_detached`, `test_reset_am_failed`, `test_reset_am_failed_with_no_stderr`), so `80 passed`.

Then check that no old action list is left in the two files:

Run: `grep -n "pause|resume|cancel>\|pause|resume|cancel\`\|pause/cancel:\|pause/cancel timeout\|resume or cancel one" core/backend/runs/run-control.py tests/core/backend/runs/test_run_control.py`

Expected: no output.

- [ ] **Step 9: Run the full gate**

Run: `timeout 600 bash tests/run.sh`

Expected: exit 0. pytest reports all passed, and no QML test prints a `FAIL` line or a `TypeError`/`ReferenceError`. The skipped row-contract tests stay skipped.

- [ ] **Step 10: Commit**

```bash
git add core/backend/runs/run-control.py tests/core/backend/runs/test_run_control.py
git commit -m "feat(runs): run-control.py accepts reset, passed to am reset like pause and cancel"
```

---

## Self-review against the spec

- Command line accepted, RUN/REPO rules, no options, extras are Usage, Usage before PATH lookup: Step 4 usage rows, plus `test_usage_wins_over_am_missing` (unchanged, re-pinned to new text) and `test_reset_am_missing`.
- New USAGE text on every action's Usage error: Step 1 constant re-pins all `test_usage` rows; Step 7 source.
- am argv verbatim, no `--pretty`/`--verify`: `test_reset_argv`, `test_reset_args_reach_am_verbatim`. stdin `/dev/null`: shared `run_am()` path, already pinned for pause by `test_am_does_not_inherit_stdin`; reset reaches the same call (Step 7 changes no code path).
- Synchronous, 60 s timeout, never detached: `test_reset_timeout_is_helper_error` (asserts `AM_TIMEOUT == 60`), `test_reset_is_never_detached`.
- Envelope passthrough, refusals, AmBadOutput, AmFailed, AmMissing, HelperError: Steps 3-5.
- Docstrings: Step 7, checked by the grep in Step 8.
- Out-of-scope files are not touched; `tests/run.sh` gate in Step 9.
<!-- task-pipeline: validated -->
