# 2.1 run-control.py (card b661b0a4)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-controls-design.md` (S2):
"Control actions" (lines 29-53), "Architecture" bullet 2 (lines 62-64),
"Errors" row 2 (line 143) and "Testing" bullet 3 (lines 155-156). Parent story
90acc3d7. Not blocked by anything; the `runs.js` half of S2 (`controls`,
`controlError`, `newAlerts`) is already on this branch (commits 0515d01, ccf5090,
c7655b7) and is not touched.

## Starting point

- `core/backend/runs/` has three helpers: `runs-snapshot.py`, `runs-watch.py`,
  `runs-logs.py`. `runs-logs.py` is the closest model: a one-shot `am`
  passthrough that finds `am` with `shutil.which`, runs it as an argv list with
  `capture_output`, `stdin=DEVNULL` and a 60 s timeout, checks only the
  envelope's shape (`envelope_of`), wraps `main` in `guarded()` so every path
  prints one line, and exits 0 on every printed line except `Usage` (exit 2).
- `emit(payload, code=0)` lives in `core/backend/common/json_line.py` and must be
  imported, never redefined (`tests/architecture/test_layers.py:231`,
  `DUPLICATED_PY`; `docs/architecture.md` lines 174-180). Local `failure()`,
  `guarded()` and `AM_TIMEOUT` per script are the accepted pattern.
- Backend code may import only the stdlib and `core/backend/common`
  (`tests/architecture/test_layers.py`). New helpers go at
  `core/backend/<domain>/name.py`, print one JSON line, insert their parent dir on
  `sys.path` for `common`, and are tested under `tests/core/backend/<domain>/`
  (`docs/architecture.md` lines 190-192).
- `tests/core/backend/runs/test_runs_logs.py` is the test model: a fake `am` on a
  temp `PATH` appends its argv as JSON to `FAKE_AM_DIR/calls.log` and serves
  fixtures; `HOME` and `XDG_DATA_HOME` are temp. Its fake is keyed on `logs`
  only, so the new test file has its own fake keyed on the subcommand.
- The real `am` (checked with `--help` and against a throwaway repo):
  - `am pause RUN_ID --repo-dir R [--pretty]` and `am cancel RUN_ID --repo-dir R
    [--pretty]`: no `--verify`. They return at once (parent spec lines 39-41).
  - `am resume RUN_ID --repo-dir R [--verify STR]... [--allow-no-verification]
    [--pretty]`: `--verify` is repeatable. **`am resume` does not return at once:
    "Continue a stopped, escalated or killed run from its checkpoints, and drive
    it to the end."** A refusal (`UnknownRunError`, `RunIsLiveError`,
    `NotResumableError`, ...) comes back immediately; an accepted resume keeps
    the `am` process alive, driving the run, for as long as the run lasts.
  - Refusals print `{"error": {"message", "type"}, "ok": false}` and exit 3 (seen
    for `UnknownRunError` and `RepoDirError`).
- `core/stores/HelperRunner.qml` runs one process at a time and stops the current
  one (`running = false`) when the next call starts. A helper that blocked for
  the length of a resumed run would be killed by the store's next helper call.

## Scope

One new helper, `core/backend/runs/run-control.py`, and its pytest file,
`tests/core/backend/runs/test_run_control.py`. Tests first.

### Out of scope

- `RunStore.qml` `control(action, runId)`, `pending`, `lastError`, the
  re-snapshot after a control call and the 30 s "still waiting" message (parent
  spec lines 65-69): the RunStore card.
- `TypedConfirmDialog` generalisation, `ui/components/RunControls.qml`,
  keyboard shortcuts, `RunToast.qml`, `notify.py`, the "Notify on escalation"
  setting, `tests/ui/` flows: their own cards.
- Storing the per-project verify set (parent spec lines 49-53, 168-170; decided
  in S3). This helper only forwards whatever `--verify` values it is given.
- `tests/contract/test_am_shapes.py` control envelopes (parent spec line 161):
  not in this card's description; left for the contract card.
- `docs/architecture.md` (the `core/backend/runs/` paragraph, line 172): left for
  S2's docs card, as S1 did with its docs card.
- `runs.js` (`controls`, `controlError`, `newAlerts`) and every existing helper
  and test: unchanged.

## Behaviour

### Command line

```
run-control.py <pause|resume|cancel> RUN REPO [--verify CMD]... [--allow-no-verification]
```

- Exactly three positionals, in that order: ACTION, RUN, REPO. Options come after
  them.
- ACTION must be `pause`, `resume` or `cancel`.
- `--verify CMD` takes the next argument as CMD verbatim (it may contain spaces,
  shell metacharacters, or start with `-`) and may repeat; order is kept.
  `--allow-no-verification` takes no value. Both are accepted **only with
  `resume`** (parent spec line 34: only Resume carries `--verify`; `am pause` and
  `am cancel` reject the flag). Giving both `--verify` and
  `--allow-no-verification` is not checked by the helper; am decides.
- RUN must be non-empty and must not start with `-` (am would read it as an
  option). REPO must be non-empty. Neither is otherwise checked: a missing or
  bad repo, or an unknown run, is am's refusal to report.
- Any other shape is a `Usage` failure: fewer than three positionals, an unknown
  action, an unknown option, `--verify` as the last argument, `--verify` or
  `--allow-no-verification` with `pause`/`cancel`, an extra positional, an empty
  RUN or REPO, a RUN starting with `-`. `Usage` prints
  `{"ok": false, "error": {"type": "Usage", "message": USAGE}}` where USAGE is
  exactly
  `usage: run-control.py <pause|resume|cancel> RUN REPO [--verify CMD]... [--allow-no-verification]`,
  exits 2, and never runs am.

### am argv

The argv after the `am` executable, always an argv list, never a shell:

| call | am argv |
|---|---|
| `pause r1 /p` | `["pause", "r1", "--repo-dir", "/p"]` |
| `cancel r1 /p` | `["cancel", "r1", "--repo-dir", "/p"]` |
| `resume r1 /p` | `["resume", "r1", "--repo-dir", "/p"]` |
| `resume r1 /p --verify "pytest -q" --verify "npm test"` | `["resume", "r1", "--repo-dir", "/p", "--verify", "pytest -q", "--verify", "npm test"]` |
| `resume r1 /p --allow-no-verification` | `["resume", "r1", "--repo-dir", "/p", "--allow-no-verification"]` |

With both flags given, every `--verify` pair comes first (in the order given),
then `--allow-no-verification`. `--pretty` is never sent. RUN and REPO arrive as
one argv element each, unaltered. am's stdin is `/dev/null`. The helper's
environment (including `HOME` and `XDG_DATA_HOME`, where am keeps its runs) is
passed to am unchanged.

### Output: exactly one JSON line on every path

The envelope's `ok` decides what is printed, not am's exit code. am's stderr
never appears on stdout except as the `AmFailed` tail below.

1. **Envelope.** am's stdout parses as a JSON object with a boolean `ok`: the
   helper prints that object unchanged on one line (pretty-printed output is
   re-serialised to one line) and exits 0. This covers success (`ok: true`,
   including the idempotent `already_requested` case, which is inside `data` and
   not inspected) and every refusal (`ok: false`, any `error.type`: the eight
   named in parent spec lines 59-60 and any other am prints, e.g.
   `RepoDirError`, `UsageError`). `data` and `error` are never inspected or
   trimmed.
2. **AmFailed.** am exited non-zero and its stdout is not an envelope (empty,
   not JSON, JSON that is not an object, or no boolean `ok`):
   `{"ok": false, "error": {"type": "AmFailed", "message": M}}`, exit 0. M is
   the **stderr tail**: am's stderr with trailing whitespace stripped, keeping
   only its last 20 lines, and of that only the last 2000 characters. If that
   tail is empty, M is `am <action> exited <code> with no output.` (e.g.
   `am cancel exited 1 with no output.`). For a run killed by a signal, `<code>`
   is the negative return code Python reports.
3. **AmBadOutput.** am exited 0 but its stdout is not an envelope:
   `{"ok": false, "error": {"type": "AmBadOutput", "message": M}}`, exit 0, where
   M names the action and says what was wrong, ending `(exit 0).`, e.g.
   `am pause did not print JSON (exit 0).` (same wording family as
   `runs-logs.py`).
4. **AmMissing.** `am` is not on `PATH`:
   `{"ok": false, "error": {"type": "AmMissing", "message": "am is not installed."}}`,
   exit 0. Checked after the arguments are valid.
5. **HelperError.** Any unexpected failure (am cannot start, pause/cancel time
   out, anything raised): `{"ok": false, "error": {"type": "HelperError",
   "message": "The run control failed: <reason>"}}`, exit 0. `<reason>` is the
   exception's text, else its class name.
6. **Usage**: above, exit 2.

### Timeouts

**pause and cancel** run with `AM_TIMEOUT = 60` seconds (as `runs-logs.py`). An
am that hangs past it is killed and reported as `HelperError`.

**resume** must not be bounded by a timeout or tied to the helper's lifetime:
an accepted resume is the run itself, and killing it would leave a dead lease
(the very thing the user was trying to recover from). So for `resume` only:

- am is started in its own session (a new process group), so a signal to the
  helper's group (HelperRunner stopping it, the panel closing) does not reach am.
- am's stdout and stderr go to anonymous temporary files (already unlinked;
  nothing is left on disk), not pipes, so am can keep writing after the helper
  exits.
- The helper waits up to `RESUME_GRACE = 10` seconds for am to exit.
  - If am exits within the grace window, its stdout/stderr are read back and
    handled exactly as rules 1-3 above (so every resume refusal reaches the
    store as am's own envelope, exit 0).
  - If am is still running when the window ends, the resume was accepted and
    the run is being driven. The helper prints
    `{"ok": true, "data": {"action": "resume", "run_id": RUN, "detached": true}}`
    and exits 0, leaving am running. It does not wait for, signal or reap am.
    The run's progress is then visible through `am status` / `am watch` as for
    any running run (S1's snapshot and watch).
- `RESUME_GRACE` is a module constant so tests can shorten it.

This is a deliberate refinement of parent spec line 63 ("runs the `am` command,
prints its envelope"): for `resume` the envelope am prints at the end of the run
is never seen by the helper; the `detached` envelope stands in for it.

## Tests (all in `tests/core/backend/runs/test_run_control.py`)

Tier: **backend pytest with a stub `am`** (parent spec lines 155-156;
`docs/architecture.md` lines 190-192). Every test runs the real script as a
subprocess (or, for timing tests, loads it as a module) against a fake `am` on a
temp `PATH` with temp `HOME`/`XDG_DATA_HOME`/`FAKE_AM_DIR`. This tier is right
because the helper's whole contract is argv in, one JSON line and an exit code
out; the real `am` cannot be made to refuse with each error type on demand, and
no Qt is involved. Every subprocess test asserts stdout is exactly one JSON line.

The fake `am` appends its argv to `calls.log`, then keys on the subcommand
(`pause`/`resume`/`cancel`): writes `<name>.err` to stderr if present, prints
`<name>.out` verbatim, exits with `<name>.code` (default 0). With no `.out`
fixture it answers like real am for an unknown run (`UnknownRunError`, exit 3).

Argv:
1. `test_pause_argv` — exact `["pause", "r1", "--repo-dir", "/p"]`; no
   `--pretty`, no `--verify`.
2. `test_cancel_argv` — exact cancel argv.
3. `test_resume_argv_bare` — exact resume argv with no options.
4. `test_resume_argv_repeated_verify_in_order` — two `--verify` values, order
   kept, each one argv element.
5. `test_resume_argv_allow_no_verification`.
6. `test_resume_argv_verify_then_allow` — both flags, `--verify` pairs first.
7. `test_args_reach_am_verbatim` — RUN, REPO and a CMD with spaces, `;`, `$( )`,
   `&` and a leading `-` (`--verify -x`, and `--verify --allow-no-verification`
   taken as a CMD string, not a flag) each arrive as one unaltered element.

Envelope passthrough:
8. `test_ok_envelope_passed_through[pause|cancel|resume]` — `ok: true` envelope
   (with `already_requested` in `data` for pause/cancel) printed unchanged, exit
   0; resume's fake exits at once so it is inside the grace window.
9. `test_refusal_passed_through_exit_0` — parametrised over the eight types
   `UnknownRunError`, `NotRunningError`, `DeadRunError`, `NotAcceptingError`,
   `RunIsLiveError`, `NotResumableError`, `ClaimedError`, `LockTimeoutError`,
   each with am exit 3: printed unchanged, exit 0. Paired with a plausible
   action (e.g. `NotAcceptingError` with pause, `RunIsLiveError` with resume).
10. `test_missing_fixture_unknown_run` — no fixture: `UnknownRunError` envelope
    passed through.
11. `test_ok_wins_over_exit_code_and_stderr` — `ok: true` with exit 3 and noisy
    stderr: printed unchanged, stderr absent.
12. `test_pretty_printed_output_becomes_one_line`.

Failures:
13. `test_nonzero_exit_without_envelope_is_am_failed` — parametrised: empty
    stdout, non-JSON stdout, a JSON list, an object without boolean `ok`; each
    with exit 1 and stderr `"Traceback ...\nValueError: boom\n"`: type
    `AmFailed`, message ends with `ValueError: boom`.
14. `test_am_failed_message_is_the_stderr_tail` — 50 lines of stderr: message is
    exactly the last 20 lines; a single 5000-character line: message is its
    last 2000 characters.
15. `test_am_failed_with_no_stderr` — exit 1, empty stdout and stderr: message
    exactly `am cancel exited 1 with no output.`
16. `test_exit_0_without_envelope_is_am_bad_output` — parametrised as 13 but exit
    0: type `AmBadOutput`, message names `am <action>` and contains `(exit 0)`.
17. `test_am_missing` — empty `PATH` dir: `AmMissing`, exit 0, no call.
18. `test_usage` — parametrised: no args; two args; unknown action `stop`; extra
    positional; `--verify` with pause; `--verify` with cancel;
    `--allow-no-verification` with pause; `--verify` last with no value; unknown
    option `--pretty`; empty RUN; empty REPO; RUN `-r1`. Each: exact Usage
    envelope, exit 2, `calls.log` empty.
19. `test_am_cannot_start_is_helper_error` — fake am with a nonexistent
    interpreter: `HelperError`, message starts `The run control failed: `, exit 0
    (pause, and resume).
20. `test_am_does_not_inherit_stdin` — an am that reads stdin gets EOF at once
    (pause; the helper's own stdin is an open pipe that never closes).

Timing (module-loaded, constants shortened with `monkeypatch`):
21. `test_pause_timeout_is_helper_error` — `AM_TIMEOUT == 60` asserted, then
    shortened to 0.5 s; a sleeping am gives `HelperError`, one line, exit 0.
22. `test_resume_still_running_after_grace_is_detached` — `RESUME_GRACE == 10`
    asserted, then shortened to 0.5 s; a fake am that sleeps, then writes a
    marker file: the helper returns within a few seconds with
    `{"ok": true, "data": {"action": "resume", "run_id": "r1", "detached": true}}`,
    exit 0, one line; the marker file appears afterwards (am was neither killed
    nor waited for).
23. `test_detached_resume_survives_the_helper_group_being_killed` — a small
    driver script written to `tmp_path` loads `run-control.py` as a module, sets
    `RESUME_GRACE = 0.5` and calls `guarded(["resume", "r1", "/p"])`; the test
    starts it with `start_new_session=True` and the fake-am env, reads the
    detached line, then `os.killpg(driver.pid, SIGKILL)`; the fake am (sleep 2 s,
    then write a marker file) still writes the marker.
24. `test_resume_refusal_within_grace_passed_through` — `RunIsLiveError` exit 3
    returns immediately (well under `RESUME_GRACE`), envelope unchanged, exit 0.
25. `test_resume_am_failed_within_grace` — resume exits 1 with no envelope within
    the grace window: `AmFailed` with the stderr tail (proves the temp-file path
    reads stderr back).

Architecture tier (existing, unchanged): `tests/architecture` must stay green —
no redefinition of `emit`, stdlib-only imports, no glyph literals (all strings
ASCII).

Verification: `bash tests/run.sh` green.

## Review focus (inputs most likely to bite, for the planner)

1. A resume that am accepts: the helper must return in about `RESUME_GRACE`
   seconds and the run must keep going after the helper exits or is killed.
2. Refusals arriving with exit 3: must still be passed through with exit 0, or
   the store loses the error type.
3. `--verify` values that look like options (`-x`, `--allow-no-verification`
   as a CMD string) must be taken as values, not parsed as flags.
4. am crashing with a long Python traceback: the `AmFailed` message must be the
   tail (last lines), not the head, and bounded.
5. Run ids or repo paths with spaces or shell metacharacters must reach am as
   single argv elements.

---

# run-control.py Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `core/backend/runs/run-control.py`, a one-JSON-line `am pause|resume|cancel` passthrough whose accepted resume is detached so it outlives the helper. Write it test-first, with every test in `tests/core/backend/runs/test_run_control.py`.

**Architecture:** One stdlib-only script modelled on `core/backend/runs/runs-logs.py`. `parse` checks the command line and returns `None` for a `Usage` failure. `control_argv` builds am's argv. pause and cancel go through `run_am` (`subprocess.run`, 60 s timeout). resume goes through `start_resume` (`subprocess.Popen` in a new session, output to unlinked temp files, wait `RESUME_GRACE`). `report` turns `(stdout, stderr, returncode)` into the envelope, `AmFailed` or `AmBadOutput`, and `guarded` turns anything raised into `HelperError`. Three tasks: (1) the argv, the passthrough and the `runs-logs.py`-style failure paths, (2) `AmFailed` with the stderr tail, (3) detached resume.

**Tech Stack:** Python 3 stdlib (`subprocess`, `tempfile`, `shutil`, `json`), `common.json_line.emit`, pytest with a fake `am` on a temp `PATH`.

**Spec:** `docs/superpowers/specs/2-1-run-control-py-b661b0a4.md` (prepended above). Parent design: `docs/superpowers/specs/2026-10-03-am-run-controls-design.md` (S2).

**Worktree / branch:** all paths are relative to `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/ctl/task-2-1-run-control-py-b661b0a4`, branch `ctl/task-2-1-run-control-py-b661b0a4`. Run every command from that directory.

**Running pytest:** `python3` here may be a uv-managed interpreter without pytest (see `tests/run.sh`). Every pytest command below is written as `uv run --with pytest python3 -m pytest ...`. If `python3 -c 'import pytest'` succeeds, `python3 -m pytest ...` works as well.

## Global Constraints

- Command line: `run-control.py <pause|resume|cancel> RUN REPO [--verify CMD]... [--allow-no-verification]`. USAGE is exactly `usage: run-control.py <pause|resume|cancel> RUN REPO [--verify CMD]... [--allow-no-verification]`. A `Usage` failure exits 2 and never runs am.
- Imports are the stdlib plus `common` only. `emit` comes from `common.json_line` and is never redefined: `tests/architecture/test_layers.py` `DUPLICATED_PY` must stay green.
- Shebang `#!/usr/bin/env python3`. Put `sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))` before `from common.json_line import emit  # noqa: E402`.
- Exactly one JSON line on stdout on every path. Exit 0 for every printed line except `Usage` (exit 2).
- am is always started as an argv list, never through a shell. Its stdin is `/dev/null`. `--pretty` is never sent. The environment is passed through unchanged.
- `AM_TIMEOUT = 60` (pause and cancel). `RESUME_GRACE = 10` (resume). Both are module constants.
- The stderr tail is trailing whitespace stripped, the last 20 lines, then the last 2000 characters.
- Error types and messages: `AmMissing` / `am is not installed.`; `HelperError` / `The run control failed: <reason>`; `AmFailed` / tail or `am <action> exited <code> with no output.`; `AmBadOutput` / `am <action> ... (exit 0).`.
- Detached envelope: `{"ok": true, "data": {"action": "resume", "run_id": RUN, "detached": true}}`.
- All strings are ASCII: no glyph literals.
- Do not touch `runs.js`, `RunStore.qml`, `docs/architecture.md`, `tests/contract/` or any existing helper or test.
- Verification: `bash tests/run.sh` green.

## Review Focus

The spec's own review-focus list is pinned by named tests: accepted resume by `test_resume_still_running_after_grace_is_detached` and `test_detached_resume_survives_the_helper_group_being_killed`; exit-3 refusals by `test_refusal_passed_through_exit_0`; flag-looking `--verify` values and metacharacters by `test_args_reach_am_verbatim`; long tracebacks by `test_am_failed_message_is_the_stderr_tail`. The five further inputs below are what the spec implies but does not list. Each has a test in the task that owns the code:

1. am writes bytes that are not UTF-8 (a crash in a non-UTF-8 locale, binary garbage). The expected result is an `AmFailed` carrying U+FFFD replacement characters, not a `HelperError` from a decode crash. Pinned by `test_am_failed_with_invalid_utf8_stderr` (Task 2, pause/cancel path) and `test_resume_invalid_utf8_stderr` (Task 3, temp-file path).
2. A bad command line on a machine without am. The expected result is `Usage`, exit 2, because the arguments are checked before am is looked for. Pinned by `test_usage_wins_over_am_missing` (Task 1).
3. A stderr that ends in blank or whitespace-only lines. The expected message is the last real line (`boom`), not empty and not padded. Pinned by `test_am_failed_tail_drops_trailing_whitespace` (Task 2).
4. A detached resume of a run id with spaces or metacharacters. The detached envelope's `run_id` must be RUN verbatim. Pinned by `test_detached_envelope_echoes_run_verbatim` (Task 3).
5. A detached resume must leave nothing in the temp dir ("nothing is left on disk"). The expected result is an empty `TMPDIR` both after the helper returns and after am finishes. Pinned by `test_detached_resume_leaves_no_temp_files` (Task 3).

## File Structure

- Create: `core/backend/runs/run-control.py`. It holds the whole helper: `parse`, `control_argv`, `envelope_of`, `stderr_tail`, `report`, `run_am`, `start_resume`, `main` and `guarded`.
- Create: `tests/core/backend/runs/test_run_control.py`. It holds every test, with its own fake `am` keyed on `pause`/`resume`/`cancel`.

No other file changes.

---

### Task 1: Command line, am argv, envelope passthrough, AmBadOutput/AmMissing/HelperError/Usage

**Files:**
- Create: `core/backend/runs/run-control.py`
- Test: `tests/core/backend/runs/test_run_control.py` (create)

**Interfaces:**
- Consumes: `common.json_line.emit(payload, code=0) -> int`. It prints `json.dumps(payload)` and returns `code`.
- Produces (later tasks rely on these exact names):
  - `USAGE: str`, `ACTIONS = ("pause", "resume", "cancel")`, `AM_TIMEOUT = 60`
  - `class BadOutput(Exception)`
  - `failure(kind: str, message: str, code: int = 0) -> int`
  - `parse(argv: list[str]) -> tuple[str, str, str, list[str], bool] | None`, returning `(action, run, repo, verify, allow)`
  - `control_argv(action, run, repo, verify, allow) -> list[str]`
  - `envelope_of(action: str, stdout: str, returncode: int) -> dict`, which raises `BadOutput`
  - `report(action: str, stdout: str, stderr: str, returncode: int) -> int`
  - `run_am(am: str, argv: list[str]) -> tuple[str, str, int]`, returning `(stdout, stderr, returncode)`
  - `main(argv) -> int`, `guarded(argv) -> int`
  - Test helpers in `test_run_control.py`: `FAKE_AM`, `UNKNOWN_RUN`, `USAGE`, `TRACEBACK`, `OK`, `NOT_ENVELOPES`, `NOT_ENVELOPE_IDS`, `write_exec(path, text)`, the `world` fixture, `env_for(world, **extra)`, `run(world, args, **extra) -> (exit, payload)`, `set_raw(world, name, text, code=0, stderr=None)` (`text`/`stderr` may be `str` or `bytes`), `set_envelope(world, name, envelope, code=0)`, `calls(world)`, `load_helper()`, `use_world(world, monkeypatch)`, `one_line(capsys)`.

- [ ] **Step 1: Write the failing tests**

Create `tests/core/backend/runs/test_run_control.py` with exactly:

```python
"""run-control.py: an `am pause|resume|cancel` passthrough, one JSON line on every path.

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
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "run-control.py")

# The fake am logs its argv, then (keyed on the subcommand: pause, resume or
# cancel) writes FAKE_AM_DIR/<name>.err to stderr if present, prints
# FAKE_AM_DIR/<name>.out verbatim and exits with FAKE_AM_DIR/<name>.code
# (default 0). Fixtures are copied as bytes, so they may hold invalid UTF-8. A
# missing .out fixture behaves like real am for an unknown run: an
# UnknownRunError envelope and exit 3.
FAKE_AM = '''#!/usr/bin/env python3
import json, os, sys
d = os.environ["FAKE_AM_DIR"]
args = sys.argv[1:]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(args) + "\\n")
name = args[0] if args[:1] in (["pause"], ["resume"], ["cancel"]) else "other"
out = os.path.join(d, name + ".out")
if not os.path.exists(out):
    sys.stdout.write(json.dumps({"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}) + "\\n")
    sys.exit(3)
err = os.path.join(d, name + ".err")
if os.path.exists(err):
    with open(err, "rb") as f:
        sys.stderr.buffer.write(f.read())
with open(out, "rb") as f:
    sys.stdout.buffer.write(f.read())
code = os.path.join(d, name + ".code")
sys.exit(int(open(code).read()) if os.path.exists(code) else 0)
'''

UNKNOWN_RUN = {"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}
USAGE = {"ok": False, "error": {"type": "Usage", "message":
         "usage: run-control.py <pause|resume|cancel> RUN REPO"
         " [--verify CMD]... [--allow-no-verification]"}}
TRACEBACK = "Traceback (most recent call last):\nValueError: boom\n"


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


def env_for(world, **extra):
    e = {
        "PATH": str(world["bin"]) + os.pathsep + "/usr/bin" + os.pathsep + "/bin",
        "HOME": str(world["home"]),
        "XDG_DATA_HOME": str(world["data"]),
        "FAKE_AM_DIR": str(world["am"]),
    }
    e.update(extra)
    return e


def run(world, args, **extra):
    """Run the helper; assert stdout is exactly one JSON line; return (exit, payload)."""
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True,
                       env=env_for(world, **extra), timeout=60)
    lines = p.stdout.splitlines()
    assert len(lines) == 1, (p.stdout, p.stderr)
    return p.returncode, json.loads(lines[0])


def set_raw(world, name, text, code=0, stderr=None):
    """am <name> prints `text` (str or bytes), writes `stderr` and exits `code`."""
    out = world["am"] / (name + ".out")
    out.write_bytes(text if isinstance(text, bytes) else text.encode())
    (world["am"] / (name + ".code")).write_text(str(code))
    if stderr is not None:
        err = world["am"] / (name + ".err")
        err.write_bytes(stderr if isinstance(stderr, bytes) else stderr.encode())


def set_envelope(world, name, envelope, code=0):
    set_raw(world, name, json.dumps(envelope) + "\n", code)


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def load_helper():
    """The script as a module (its name has a hyphen, so no plain import)."""
    spec = importlib.util.spec_from_file_location("run_control", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def use_world(world, monkeypatch):
    for key, value in env_for(world).items():
        monkeypatch.setenv(key, value)


def one_line(capsys):
    lines = capsys.readouterr().out.splitlines()
    assert len(lines) == 1, lines
    return json.loads(lines[0])


OK = {"ok": True, "data": {"run_id": "r1"}}


# --- am argv -----------------------------------------------------------------

def test_pause_argv(world):
    set_envelope(world, "pause", OK)
    code, _ = run(world, ["pause", "r1", "/p"])
    assert code == 0
    made = calls(world)
    assert made == [["pause", "r1", "--repo-dir", "/p"]]
    assert "--pretty" not in made[0]
    assert "--verify" not in made[0]


def test_cancel_argv(world):
    set_envelope(world, "cancel", OK)
    code, _ = run(world, ["cancel", "r1", "/p"])
    assert code == 0
    assert calls(world) == [["cancel", "r1", "--repo-dir", "/p"]]


def test_resume_argv_bare(world):
    set_envelope(world, "resume", OK)
    code, _ = run(world, ["resume", "r1", "/p"])
    assert code == 0
    assert calls(world) == [["resume", "r1", "--repo-dir", "/p"]]


def test_resume_argv_repeated_verify_in_order(world):
    set_envelope(world, "resume", OK)
    code, _ = run(world, ["resume", "r1", "/p", "--verify", "pytest -q", "--verify", "npm test"])
    assert code == 0
    assert calls(world) == [["resume", "r1", "--repo-dir", "/p",
                             "--verify", "pytest -q", "--verify", "npm test"]]


def test_resume_argv_allow_no_verification(world):
    set_envelope(world, "resume", OK)
    code, _ = run(world, ["resume", "r1", "/p", "--allow-no-verification"])
    assert code == 0
    assert calls(world) == [["resume", "r1", "--repo-dir", "/p", "--allow-no-verification"]]


def test_resume_argv_verify_then_allow(world):
    # Both flags: every --verify pair first, in the order given, then the allow flag.
    set_envelope(world, "resume", OK)
    code, _ = run(world, ["resume", "r1", "/p", "--allow-no-verification",
                          "--verify", "make check", "--verify", "ruff ."])
    assert code == 0
    assert calls(world) == [["resume", "r1", "--repo-dir", "/p", "--verify", "make check",
                             "--verify", "ruff .", "--allow-no-verification"]]


def test_args_reach_am_verbatim(world):
    # Spaces, shell metacharacters and a leading dash each arrive as one argv
    # element; a --verify value that looks like a flag is a value, not a flag.
    set_envelope(world, "resume", OK)
    code, _ = run(world, ["resume", "r 1; echo x", "/p $(whoami) & y",
                          "--verify", "-x", "--verify", "--allow-no-verification",
                          "--verify", "echo hi; ls $(pwd) &"])
    assert code == 0
    assert calls(world) == [["resume", "r 1; echo x", "--repo-dir", "/p $(whoami) & y",
                             "--verify", "-x", "--verify", "--allow-no-verification",
                             "--verify", "echo hi; ls $(pwd) &"]]


# --- envelope passthrough ------------------------------------------------------

@pytest.mark.parametrize("action,data", [
    ("pause", {"run_id": "r1", "action": "pause", "already_requested": True}),
    ("cancel", {"run_id": "r1", "action": "cancel", "already_requested": False}),
    ("resume", {"run_id": "r1", "status": "done"}),
])
def test_ok_envelope_passed_through(world, action, data):
    # resume's fake exits at once, so it lands inside the grace window.
    envelope = {"ok": True, "data": data}
    set_envelope(world, action, envelope)
    code, out = run(world, [action, "r1", "/p"])  # run() asserts exactly one JSON line
    assert code == 0
    assert out == envelope


@pytest.mark.parametrize("action,kind", [
    ("pause", "UnknownRunError"),
    ("pause", "NotRunningError"),
    ("cancel", "DeadRunError"),
    ("pause", "NotAcceptingError"),
    ("resume", "RunIsLiveError"),
    ("resume", "NotResumableError"),
    ("resume", "ClaimedError"),
    ("cancel", "LockTimeoutError"),
])
def test_refusal_passed_through_exit_0(world, action, kind):
    refusal = {"ok": False, "error": {"type": kind, "message": "refused: " + kind}}
    set_envelope(world, action, refusal, code=3)
    code, out = run(world, [action, "r1", "/p"])
    assert code == 0
    assert out == refusal


def test_missing_fixture_unknown_run(world):
    # No pause.out: the fake am answers UnknownRunError with exit 3.
    code, out = run(world, ["pause", "r1", "/p"])
    assert code == 0
    assert out == UNKNOWN_RUN
    assert calls(world) == [["pause", "r1", "--repo-dir", "/p"]]


def test_ok_wins_over_exit_code_and_stderr(world):
    # The envelope's `ok` decides, not am's exit code; am's stderr never reaches
    # the helper's stdout line.
    envelope = {"ok": True, "data": {"run_id": "r1", "already_requested": True}}
    set_raw(world, "cancel", json.dumps(envelope) + "\n", code=3,
            stderr="warning: noisy\nmore noise\n")
    code, out = run(world, ["cancel", "r1", "/p"])
    assert code == 0
    assert out == envelope


def test_pretty_printed_output_becomes_one_line(world):
    envelope = {"ok": True, "data": {"run_id": "r1", "already_requested": False}}
    set_raw(world, "pause", json.dumps(envelope, indent=2) + "\n")
    code, out = run(world, ["pause", "r1", "/p"])  # run() asserts exactly one line
    assert code == 0
    assert out == envelope


# --- failures -------------------------------------------------------------------

NOT_ENVELOPES = ["", "not json\n", "[1, 2]\n", '{"data": {}}\n', '{"ok": "true"}\n']
NOT_ENVELOPE_IDS = ["empty", "not-json", "list", "no-ok", "ok-string"]


@pytest.mark.parametrize("text", NOT_ENVELOPES, ids=NOT_ENVELOPE_IDS)
def test_exit_0_without_envelope_is_am_bad_output(world, text):
    set_raw(world, "pause", text, code=0, stderr=TRACEBACK)
    code, out = run(world, ["pause", "r1", "/p"])
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "AmBadOutput"
    assert out["error"]["message"].startswith("am pause ")
    assert out["error"]["message"].endswith("(exit 0).")


def test_am_missing(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, out = run(world, ["pause", "r1", "/p"], PATH=str(empty))
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmMissing", "message": "am is not installed."}}
    assert calls(world) == []


def test_usage_wins_over_am_missing(world):
    # The arguments are checked before am is looked for.
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, out = run(world, ["stop", "r1", "/p"], PATH=str(empty))
    assert code == 2
    assert out == USAGE


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
def test_usage(world, args):
    code, out = run(world, args)
    assert code == 2
    assert out == USAGE
    assert calls(world) == []


@pytest.mark.parametrize("action", ["pause", "resume"])
def test_am_cannot_start_is_helper_error(world, action):
    # Executable (so shutil.which finds it) but unstartable: subprocess raises
    # OSError and guarded() must still print exactly one JSON line.
    write_exec(world["bin"] / "am", "#!/nonexistent/interpreter\n")
    code, out = run(world, [action, "r1", "/p"])
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The run control failed: ")


def test_am_does_not_inherit_stdin(world):
    # The helper's stdin is an open pipe that never sends EOF. An am that reads
    # stdin must get EOF at once (stdin is /dev/null), not block on that pipe.
    write_exec(world["bin"] / "am",
               "#!/usr/bin/env python3\nimport json, sys\nsys.stdin.read()\n"
               "print(json.dumps({'ok': True, 'data': {'run_id': 'r1'}}))\n")
    p = subprocess.Popen([sys.executable, SCRIPT, "pause", "r1", "/p"], stdin=subprocess.PIPE,
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
    assert json.loads(lines[0]) == {"ok": True, "data": {"run_id": "r1"}}


# --- timing ---------------------------------------------------------------------

def test_pause_timeout_is_helper_error(world, monkeypatch, capsys):
    # An am that hangs is cut off after AM_TIMEOUT and reported as HelperError
    # (shortened here so the test does not wait the real 60 s).
    write_exec(world["bin"] / "am", "#!/usr/bin/env python3\nimport time\ntime.sleep(10)\n")
    helper = load_helper()
    assert helper.AM_TIMEOUT == 60
    monkeypatch.setattr(helper, "AM_TIMEOUT", 0.5)
    use_world(world, monkeypatch)
    code = helper.guarded(["pause", "r1", "/p"])
    out = one_line(capsys)
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The run control failed: ")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_run_control.py -q`
Expected: FAIL. Every test fails because `core/backend/runs/run-control.py` does not exist yet. The subprocess tests fail on `assert len(lines) == 1` with python's "can't open file" on stderr. The module-loaded test fails with `FileNotFoundError`.

- [ ] **Step 3: Write the minimal implementation**

Create `core/backend/runs/run-control.py` with exactly:

```python
#!/usr/bin/env python3
"""Pause, resume or cancel one run: an `am pause|resume|cancel` passthrough.

    run-control.py <pause|resume|cancel> RUN REPO [--verify CMD]... [--allow-no-verification]

Runs `am ACTION RUN --repo-dir REPO` as an argv list (no shell, stdin
/dev/null, 60 s timeout). Only resume takes options: every `--verify CMD` pair
is forwarded in the order given (CMD is the next argument verbatim, even if it
starts with `-`), then `--allow-no-verification`. --pretty is never sent. RUN,
REPO and CMD reach am unaltered; am refuses a bad repo or an unknown run itself.

Prints exactly one JSON line on EVERY path:
- am's envelope, unchanged, whether {"ok": true, "data": ...} or
  {"ok": false, "error": ...}. The envelope's `ok` decides, not am's exit code;
- {"ok": false, "error": {"type": "AmBadOutput", ...}} when am's stdout is not
  JSON, is not an object, or has no boolean `ok`;
- {"ok": false, "error": {"type": "AmMissing", ...}} when am is not on PATH;
- {"ok": false, "error": {"type": "HelperError", ...}} on any unexpected
  failure (a timeout, an am that cannot start);
- {"ok": false, "error": {"type": "Usage", ...}} for any other command line.
Exit 0 whenever a line was printed, refusals and errors included; exit 2 for
Usage only.
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = ("usage: run-control.py <pause|resume|cancel> RUN REPO"
         " [--verify CMD]... [--allow-no-verification]")
ACTIONS = ("pause", "resume", "cancel")
AM_TIMEOUT = 60


class BadOutput(Exception):
    """am printed something that is not an envelope; the message says what."""


def failure(kind, message, code=0):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def parse(argv):
    """(action, run, repo, verify, allow) for a command line USAGE allows, else None."""
    if len(argv) < 3:
        return None
    action, run, repo = argv[:3]
    if action not in ACTIONS or not run or run.startswith("-") or not repo:
        return None
    verify, allow, rest = [], False, argv[3:]
    while rest:
        if rest[0] == "--verify" and len(rest) > 1:
            verify.append(rest[1])
            rest = rest[2:]
        elif rest[0] == "--allow-no-verification":
            allow = True
            rest = rest[1:]
        else:
            return None
    if action != "resume" and (verify or allow):
        return None
    return action, run, repo, verify, allow


def control_argv(action, run, repo, verify, allow):
    """am's argv after the executable: every --verify pair, then --allow-no-verification."""
    argv = [action, run, "--repo-dir", repo]
    for cmd in verify:
        argv += ["--verify", cmd]
    if allow:
        argv.append("--allow-no-verification")
    return argv


def envelope_of(action, stdout, returncode):
    """am's envelope, checked only for shape: a JSON object with a boolean `ok`."""
    name = "am " + action
    exit_note = " (exit " + str(returncode) + ")."
    try:
        envelope = json.loads(stdout)
    except ValueError:
        raise BadOutput(name + " did not print JSON" + exit_note)
    if not isinstance(envelope, dict):
        raise BadOutput(name + " printed JSON that is not an object" + exit_note)
    if not isinstance(envelope.get("ok"), bool):
        raise BadOutput(name + " printed an object without a boolean ok field" + exit_note)
    return envelope


def report(action, stdout, stderr, returncode):
    try:
        envelope = envelope_of(action, stdout, returncode)
    except BadOutput as e:
        return failure("AmBadOutput", str(e))
    return emit(envelope)


def run_am(am, argv):
    """pause/cancel: am answers at once. Returns (stdout, stderr, returncode)."""
    proc = subprocess.run([am, *argv], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    return proc.stdout, proc.stderr, proc.returncode


def main(argv):
    parsed = parse(argv)
    if parsed is None:
        return failure("Usage", USAGE, 2)
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    return report(parsed[0], *run_am(am, control_argv(*parsed)))


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception (a timeout, an am that cannot start) - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The run control failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
```

Make it executable: `chmod +x core/backend/runs/run-control.py`. Check that the other helpers are executable too with `ls -l core/backend/runs/`, and match them.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_run_control.py tests/architecture -q`
Expected: PASS (44 tests in `test_run_control.py`, plus the architecture tests).

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/run-control.py tests/core/backend/runs/test_run_control.py
git commit -m "feat(runs): run-control.py passes am pause/resume/cancel envelopes through (card b661b0a4)"
```

---

### Task 2: AmFailed with the stderr tail; non-UTF-8 output

**Files:**
- Modify: `core/backend/runs/run-control.py`: the docstring's output list, the constants, `report`, `run_am`
- Test: `tests/core/backend/runs/test_run_control.py` (append at end of file)

**Interfaces:**
- Consumes (from Task 1): `report(action, stdout, stderr, returncode) -> int`, `envelope_of`, `BadOutput`, `failure`, `run_am`; test helpers `run`, `set_raw`, `TRACEBACK`, `NOT_ENVELOPES`, `NOT_ENVELOPE_IDS`.
- Produces: `TAIL_LINES = 20`, `TAIL_CHARS = 2000`, `stderr_tail(stderr: str) -> str`. `report` now gives `AmFailed` for a non-zero exit without an envelope. `run_am` decodes as UTF-8 with `errors="replace"`. Task 3's resume path reuses `report` and `stderr_tail` unchanged.

- [ ] **Step 1: Write the failing tests**

Append to the end of `tests/core/backend/runs/test_run_control.py`:

```python
# --- am crashed -----------------------------------------------------------------

@pytest.mark.parametrize("text", NOT_ENVELOPES, ids=NOT_ENVELOPE_IDS)
def test_nonzero_exit_without_envelope_is_am_failed(world, text):
    set_raw(world, "cancel", text, code=1, stderr=TRACEBACK)
    code, out = run(world, ["cancel", "r1", "/p"])
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "AmFailed"
    assert out["error"]["message"].endswith("ValueError: boom")


def test_am_failed_message_is_the_stderr_tail(world):
    lines = ["line %02d" % i for i in range(50)]
    set_raw(world, "cancel", "", code=1, stderr="\n".join(lines) + "\n")
    _, out = run(world, ["cancel", "r1", "/p"])
    assert out["error"]["type"] == "AmFailed"
    assert out["error"]["message"] == "\n".join(lines[30:])

    set_raw(world, "cancel", "", code=1, stderr="a" * 3000 + "b" * 2000 + "\n")
    _, out = run(world, ["cancel", "r1", "/p"])
    assert out["error"]["type"] == "AmFailed"
    assert out["error"]["message"] == "b" * 2000


def test_am_failed_tail_drops_trailing_whitespace(world):
    set_raw(world, "cancel", "", code=1, stderr="boom\n\n  \n\t\n")
    _, out = run(world, ["cancel", "r1", "/p"])
    assert out["error"] == {"type": "AmFailed", "message": "boom"}


def test_am_failed_with_no_stderr(world):
    set_raw(world, "cancel", "", code=1)
    code, out = run(world, ["cancel", "r1", "/p"])
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmFailed",
                                          "message": "am cancel exited 1 with no output."}}


def test_am_failed_with_invalid_utf8_stderr(world):
    # Bytes that are not UTF-8 must not turn into a HelperError.
    set_raw(world, "cancel", b"", code=1, stderr=b"bad \xff byte\n")
    code, out = run(world, ["cancel", "r1", "/p"])
    assert code == 0
    assert out["error"] == {"type": "AmFailed", "message": "bad � byte"}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_run_control.py -q`
Expected: 9 failed, 44 passed. The five `test_nonzero_exit_without_envelope_is_am_failed[...]` tests, `test_am_failed_message_is_the_stderr_tail`, `test_am_failed_tail_drops_trailing_whitespace` and `test_am_failed_with_no_stderr` fail because the type is still `AmBadOutput`. `test_am_failed_with_invalid_utf8_stderr` fails because the type is still `HelperError` (`'utf-8' codec can't decode byte 0xff`).

- [ ] **Step 3: Write the minimal implementation**

In `core/backend/runs/run-control.py` make these four edits.

(a) In the docstring, replace

```python
- {"ok": false, "error": {"type": "AmBadOutput", ...}} when am's stdout is not
  JSON, is not an object, or has no boolean `ok`;
```

with

```python
- {"ok": false, "error": {"type": "AmFailed", ...}} when am exited non-zero
  without an envelope; the message is the tail of am's stderr;
- {"ok": false, "error": {"type": "AmBadOutput", ...}} when am exited 0
  without an envelope;
```

(b) Replace

```python
AM_TIMEOUT = 60
```

with

```python
AM_TIMEOUT = 60
TAIL_LINES = 20
TAIL_CHARS = 2000
```

(c) Replace

```python
def report(action, stdout, stderr, returncode):
    try:
        envelope = envelope_of(action, stdout, returncode)
    except BadOutput as e:
        return failure("AmBadOutput", str(e))
    return emit(envelope)
```

with

```python
def stderr_tail(stderr):
    """The end of am's stderr, where a crash names its cause: at most TAIL_LINES
    lines, and of those at most TAIL_CHARS characters."""
    lines = stderr.rstrip().splitlines()[-TAIL_LINES:]
    return "\n".join(lines)[-TAIL_CHARS:]


def report(action, stdout, stderr, returncode):
    try:
        envelope = envelope_of(action, stdout, returncode)
    except BadOutput as e:
        if returncode == 0:
            return failure("AmBadOutput", str(e))
        tail = stderr_tail(stderr)
        return failure("AmFailed", tail or "am " + action + " exited "
                       + str(returncode) + " with no output.")
    return emit(envelope)
```

(d) In `run_am`, replace

```python
    proc = subprocess.run([am, *argv], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
```

with

```python
    proc = subprocess.run([am, *argv], capture_output=True, encoding="utf-8",
                          errors="replace", stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_run_control.py tests/architecture -q`
Expected: PASS (53 tests in `test_run_control.py`).

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/run-control.py tests/core/backend/runs/test_run_control.py
git commit -m "feat(runs): run-control.py reports a crashed am as AmFailed with its stderr tail (card b661b0a4)"
```

---

### Task 3: Detached resume

**Files:**
- Modify: `core/backend/runs/run-control.py`: the docstring, the imports (`tempfile`), the constants (`RESUME_GRACE`), the new `start_resume`, `main`
- Test: `tests/core/backend/runs/test_run_control.py`: the import block, plus a block appended at the end of the file

**Interfaces:**
- Consumes (from Tasks 1 and 2): `parse`, `control_argv`, `run_am`, `report`, `emit`, `AM_TIMEOUT`; test helpers `write_exec`, `world`, `env_for`, `run`, `set_raw`, `set_envelope`, `calls`, `load_helper`, `use_world`, `one_line`, `TRACEBACK`.
- Produces: `RESUME_GRACE = 10`, `start_resume(am: str, argv: list[str]) -> tuple[str, str, int] | None`. It returns `None` when am is still running after `RESUME_GRACE` and is left detached. Test helpers: `SLOW_AM`, `wait_for(path, seconds=10) -> bool`, `DETACHED`.

Why this shape: `core/stores/HelperRunner.qml` stops the running helper whenever the next helper call starts, and an accepted `am resume` lives as long as the run. am therefore gets its own session (`start_new_session=True`), so the helper's group signal does not reach it. Its stdout and stderr go to `tempfile.TemporaryFile()` objects (anonymous, already unlinked) instead of pipes, so am can keep writing after the helper exits. If the wait times out, the `Popen` object is dropped without `kill`/`terminate`/`wait`. At garbage collection Python may emit a `ResourceWarning` ("subprocess N is still running"). That is expected, and it does not fail the tests.

- [ ] **Step 1: Write the failing tests**

(a) In `tests/core/backend/runs/test_run_control.py` replace the import block

```python
import importlib.util
import json
import os
import stat
import subprocess
import sys
```

with

```python
import importlib.util
import json
import os
import select
import signal
import stat
import subprocess
import sys
import tempfile
import time
```

(b) Append to the end of the file:

```python
# --- resume ---------------------------------------------------------------------

# A resume that am accepted: it logs its argv, keeps driving the run for 3 s,
# then leaves a marker file (proof it was neither killed nor waited for).
SLOW_AM = '''#!/usr/bin/env python3
import json, os, sys, time
d = os.environ["FAKE_AM_DIR"]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
time.sleep(3)
with open(os.path.join(d, "marker"), "w") as f:
    f.write("still ran")
print(json.dumps({"ok": True, "data": {"status": "done"}}))
'''


def wait_for(path, seconds=10):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if path.exists():
            return True
        time.sleep(0.05)
    return False


DETACHED = {"ok": True, "data": {"action": "resume", "run_id": "r1", "detached": True}}


def test_resume_still_running_after_grace_is_detached(world, monkeypatch, capsys):
    # An accepted resume keeps am alive driving the run: the helper reports it
    # detached after RESUME_GRACE and leaves it running.
    write_exec(world["bin"] / "am", SLOW_AM)
    helper = load_helper()
    assert helper.RESUME_GRACE == 10
    monkeypatch.setattr(helper, "RESUME_GRACE", 0.5)
    use_world(world, monkeypatch)
    started = time.monotonic()
    code = helper.guarded(["resume", "r1", "/p"])
    elapsed = time.monotonic() - started
    out = one_line(capsys)
    assert code == 0
    assert out == DETACHED
    assert elapsed < 2.5
    assert not (world["am"] / "marker").exists()  # am was not waited for...
    assert wait_for(world["am"] / "marker")  # ...and not killed
    assert calls(world) == [["resume", "r1", "--repo-dir", "/p"]]


def test_detached_envelope_echoes_run_verbatim(world, monkeypatch, capsys):
    write_exec(world["bin"] / "am", SLOW_AM)
    helper = load_helper()
    monkeypatch.setattr(helper, "RESUME_GRACE", 0.5)
    use_world(world, monkeypatch)
    code = helper.guarded(["resume", "r 1; $(x)", "/p"])
    assert code == 0
    assert one_line(capsys) == {"ok": True, "data": {"action": "resume",
                                                     "run_id": "r 1; $(x)", "detached": True}}
    assert wait_for(world["am"] / "marker")


def test_detached_resume_leaves_no_temp_files(world, monkeypatch, capsys, tmp_path):
    # am's output goes to anonymous (already unlinked) temp files.
    scratch = tmp_path / "scratch"
    scratch.mkdir()
    monkeypatch.setattr(tempfile, "tempdir", str(scratch))
    write_exec(world["bin"] / "am", SLOW_AM)
    helper = load_helper()
    monkeypatch.setattr(helper, "RESUME_GRACE", 0.5)
    use_world(world, monkeypatch)
    assert helper.guarded(["resume", "r1", "/p"]) == 0
    assert one_line(capsys) == DETACHED
    assert list(scratch.iterdir()) == []
    assert wait_for(world["am"] / "marker")
    assert list(scratch.iterdir()) == []


def test_detached_resume_survives_the_helper_group_being_killed(world, tmp_path):
    # HelperRunner stopping the helper, or the panel closing, signals the
    # helper's process group. am runs in its own session, so it must survive.
    write_exec(world["bin"] / "am", SLOW_AM)
    driver = tmp_path / "driver.py"
    driver.write_text(
        "import importlib.util, sys, time\n"
        "spec = importlib.util.spec_from_file_location('run_control', %r)\n"
        "m = importlib.util.module_from_spec(spec)\n"
        "spec.loader.exec_module(m)\n"
        "m.RESUME_GRACE = 0.5\n"
        "m.guarded(['resume', 'r1', '/p'])\n"
        "sys.stdout.flush()\n"
        "time.sleep(30)\n" % SCRIPT)
    p = subprocess.Popen([sys.executable, str(driver)], stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, env=env_for(world),
                         start_new_session=True)
    try:
        ready, _, _ = select.select([p.stdout], [], [], 15)
        assert ready, "the helper printed nothing"
        assert json.loads(p.stdout.readline()) == DETACHED
        assert not (world["am"] / "marker").exists()
    finally:
        os.killpg(p.pid, signal.SIGKILL)
        p.wait()
        p.stdout.close()
    assert wait_for(world["am"] / "marker")


def test_resume_refusal_within_grace_passed_through(world):
    # A refusal comes back at once: no wait for the (real, 10 s) grace window.
    refusal = {"ok": False, "error": {"type": "RunIsLiveError", "message": "run r1 is live"}}
    set_envelope(world, "resume", refusal, code=3)
    started = time.monotonic()
    code, out = run(world, ["resume", "r1", "/p"])
    assert time.monotonic() - started < 5
    assert code == 0
    assert out == refusal


def test_resume_am_failed_within_grace(world):
    # Proves the temp-file path reads am's stderr back.
    set_raw(world, "resume", "", code=1, stderr=TRACEBACK)
    code, out = run(world, ["resume", "r1", "/p"])
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmFailed",
                                          "message": "Traceback (most recent call last):\n"
                                                     "ValueError: boom"}}


def test_resume_invalid_utf8_stderr(world):
    set_raw(world, "resume", b"", code=1, stderr=b"bad \xff byte\n")
    code, out = run(world, ["resume", "r1", "/p"])
    assert code == 0
    assert out["error"] == {"type": "AmFailed", "message": "bad � byte"}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_run_control.py -q`
Expected: 4 failed, 56 passed.
- `test_resume_still_running_after_grace_is_detached` fails on `assert helper.RESUME_GRACE == 10` with `AttributeError`.
- `test_detached_envelope_echoes_run_verbatim` and `test_detached_resume_leaves_no_temp_files` fail because `monkeypatch.setattr` of a missing `RESUME_GRACE` raises `AttributeError`.
- `test_detached_resume_survives_the_helper_group_being_killed` fails because the driver's `subprocess.run` blocks for 3 s and prints am's own `{"ok": true, "data": {"status": "done"}}`, not `DETACHED`.
- `test_resume_refusal_within_grace_passed_through`, `test_resume_am_failed_within_grace` and `test_resume_invalid_utf8_stderr` already pass through `run_am`. They pin that the new temp-file path keeps this behaviour, and they must still pass after Step 3.

- [ ] **Step 3: Write the minimal implementation**

Replace the whole of `core/backend/runs/run-control.py` with exactly the content below. It is the Task 2 file with the docstring's resume paragraph and detached bullet, `import tempfile`, `RESUME_GRACE = 10`, `start_resume`, and the resume branch in `main`:

```python
#!/usr/bin/env python3
"""Pause, resume or cancel one run: an `am pause|resume|cancel` passthrough.

    run-control.py <pause|resume|cancel> RUN REPO [--verify CMD]... [--allow-no-verification]

Runs `am ACTION RUN --repo-dir REPO` as an argv list (no shell, stdin
/dev/null). Only resume takes options: every `--verify CMD` pair is forwarded
in the order given (CMD is the next argument verbatim, even if it starts with
`-`), then `--allow-no-verification`. --pretty is never sent. RUN, REPO and CMD
reach am unaltered; am refuses a bad repo or an unknown run itself.

pause and cancel answer at once and run with a 60 s timeout. An accepted resume
is the run itself and must outlive this helper, so am is started in its own
session with its output going to unlinked temp files: the helper waits up to
RESUME_GRACE seconds and, if am is still going, reports it detached and leaves
it running (never killed, signalled or waited for).

Prints exactly one JSON line on EVERY path:
- am's envelope, unchanged, whether {"ok": true, "data": ...} or
  {"ok": false, "error": ...}. The envelope's `ok` decides, not am's exit code;
- {"ok": true, "data": {"action": "resume", "run_id": RUN, "detached": true}}
  when resume is still running after RESUME_GRACE;
- {"ok": false, "error": {"type": "AmFailed", ...}} when am exited non-zero
  without an envelope; the message is the tail of am's stderr;
- {"ok": false, "error": {"type": "AmBadOutput", ...}} when am exited 0
  without an envelope;
- {"ok": false, "error": {"type": "AmMissing", ...}} when am is not on PATH;
- {"ok": false, "error": {"type": "HelperError", ...}} on any unexpected
  failure (a pause/cancel timeout, an am that cannot start);
- {"ok": false, "error": {"type": "Usage", ...}} for any other command line.
Exit 0 whenever a line was printed, refusals and errors included; exit 2 for
Usage only.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = ("usage: run-control.py <pause|resume|cancel> RUN REPO"
         " [--verify CMD]... [--allow-no-verification]")
ACTIONS = ("pause", "resume", "cancel")
AM_TIMEOUT = 60
RESUME_GRACE = 10
TAIL_LINES = 20
TAIL_CHARS = 2000


class BadOutput(Exception):
    """am printed something that is not an envelope; the message says what."""


def failure(kind, message, code=0):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def parse(argv):
    """(action, run, repo, verify, allow) for a command line USAGE allows, else None."""
    if len(argv) < 3:
        return None
    action, run, repo = argv[:3]
    if action not in ACTIONS or not run or run.startswith("-") or not repo:
        return None
    verify, allow, rest = [], False, argv[3:]
    while rest:
        if rest[0] == "--verify" and len(rest) > 1:
            verify.append(rest[1])
            rest = rest[2:]
        elif rest[0] == "--allow-no-verification":
            allow = True
            rest = rest[1:]
        else:
            return None
    if action != "resume" and (verify or allow):
        return None
    return action, run, repo, verify, allow


def control_argv(action, run, repo, verify, allow):
    """am's argv after the executable: every --verify pair, then --allow-no-verification."""
    argv = [action, run, "--repo-dir", repo]
    for cmd in verify:
        argv += ["--verify", cmd]
    if allow:
        argv.append("--allow-no-verification")
    return argv


def envelope_of(action, stdout, returncode):
    """am's envelope, checked only for shape: a JSON object with a boolean `ok`."""
    name = "am " + action
    exit_note = " (exit " + str(returncode) + ")."
    try:
        envelope = json.loads(stdout)
    except ValueError:
        raise BadOutput(name + " did not print JSON" + exit_note)
    if not isinstance(envelope, dict):
        raise BadOutput(name + " printed JSON that is not an object" + exit_note)
    if not isinstance(envelope.get("ok"), bool):
        raise BadOutput(name + " printed an object without a boolean ok field" + exit_note)
    return envelope


def stderr_tail(stderr):
    """The end of am's stderr, where a crash names its cause: at most TAIL_LINES
    lines, and of those at most TAIL_CHARS characters."""
    lines = stderr.rstrip().splitlines()[-TAIL_LINES:]
    return "\n".join(lines)[-TAIL_CHARS:]


def report(action, stdout, stderr, returncode):
    try:
        envelope = envelope_of(action, stdout, returncode)
    except BadOutput as e:
        if returncode == 0:
            return failure("AmBadOutput", str(e))
        tail = stderr_tail(stderr)
        return failure("AmFailed", tail or "am " + action + " exited "
                       + str(returncode) + " with no output.")
    return emit(envelope)


def run_am(am, argv):
    """pause/cancel: am answers at once. Returns (stdout, stderr, returncode)."""
    proc = subprocess.run([am, *argv], capture_output=True, encoding="utf-8",
                          errors="replace", stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    return proc.stdout, proc.stderr, proc.returncode


def start_resume(am, argv):
    """resume: (stdout, stderr, returncode) if am exits within RESUME_GRACE, else None.

    am gets its own session, so a signal to this helper's process group does not
    reach it, and unlinked temp files instead of pipes, so it can keep writing
    after this helper exits. On None am is left running, never killed or waited for."""
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        proc = subprocess.Popen([am, *argv], stdin=subprocess.DEVNULL, stdout=out,
                                stderr=err, start_new_session=True)
        try:
            returncode = proc.wait(timeout=RESUME_GRACE)
        except subprocess.TimeoutExpired:
            return None
        out.seek(0)
        err.seek(0)
        return (out.read().decode("utf-8", "replace"),
                err.read().decode("utf-8", "replace"), returncode)


def main(argv):
    parsed = parse(argv)
    if parsed is None:
        return failure("Usage", USAGE, 2)
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    action, run = parsed[0], parsed[1]
    if action != "resume":
        return report(action, *run_am(am, control_argv(*parsed)))
    result = start_resume(am, control_argv(*parsed))
    if result is None:
        return emit({"ok": True, "data": {"action": "resume", "run_id": run, "detached": True}})
    return report(action, *result)


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception (a timeout, an am that cannot start) - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The run control failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_run_control.py tests/architecture -q`
Expected: PASS (60 tests in `test_run_control.py`). Each detached test waits up to about 3 s for the fake am's marker.

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest reports all passed (no failures). Every QML test prints `Totals: ... 0 failed`, and the script exits 0.

- [ ] **Step 6: Commit**

```bash
git add core/backend/runs/run-control.py tests/core/backend/runs/test_run_control.py
git commit -m "feat(runs): run-control.py detaches an accepted am resume so the run outlives the helper (card b661b0a4)"
```

---

## Self-Review

**Spec coverage.**
- Command-line shape and every Usage case: Task 1 (`parse`, `test_usage`, `test_usage_wins_over_am_missing`).
- The am argv table, including both flags with `--verify` first: Task 1 (tests 1-7).
- Rule 1 (envelope, `ok` decides, pretty to one line): Task 1 (tests 8-12).
- Rule 2 (AmFailed: tail, 20 lines, 2000 chars, no-output message, negative code for a signal via `str(returncode)`): Task 2 (tests 13-15).
- Rule 3 (AmBadOutput ending `(exit 0).`): Task 1 (test 16).
- Rule 4 (AmMissing after argument checks): Task 1 (test 17).
- Rule 5 (HelperError `The run control failed: `): Task 1 (test 19 for pause and resume, test 21).
- Rule 6 (Usage): Task 1 (test 18).
- stdin /dev/null: Task 1 (test 20).
- Timeouts: pause/cancel `AM_TIMEOUT` in Task 1 (test 21). Resume's own session, temp files, grace and detached envelope in Task 3 (tests 22-25).
- `RESUME_GRACE` as a module constant: Task 3.
- Architecture tier unchanged: run in Step 4 of every task.
- Spec test numbering maps to names one-to-one, with the five Review Focus tests added on top.

**Placeholder scan.** No "TBD", "TODO" or "similar to". Every code step carries the full code or an exact old/new replacement.

**Type consistency.** `parse` returns the 5-tuple that `control_argv(*parsed)` takes. `run_am` and `start_resume` both return `(stdout, stderr, returncode)`, which `report(action, *result)` takes. `start_resume` returns `None` only for detached. Test helper names (`set_raw`, `set_envelope`, `one_line`, `use_world`, `wait_for`, `DETACHED`, `SLOW_AM`) are defined before use, and in the task that first needs them.

**Staged check.** The plan's three stages were built and run in a scratch copy of the repo: Task 1 stage 44 passed; Task 2 red 9 failed / 44 passed, then 53 passed; Task 3 red 4 failed / 56 passed, then 60 passed; architecture tests green.
<!-- task-pipeline: validated -->
