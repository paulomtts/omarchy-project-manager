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
