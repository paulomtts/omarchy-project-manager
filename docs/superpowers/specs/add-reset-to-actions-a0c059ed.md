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
