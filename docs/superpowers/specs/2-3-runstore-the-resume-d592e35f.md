# 2.3 RunStore: the Resume dialog state — design

Card: `d592e35f` (subtask of story `d44f2afe`, blocked by `eeaaa018`, which is done on this
branch). Parent design: `docs/superpowers/specs/2026-10-05-resume-recover-design.md`, cited
below as "RR l.N".

## Purpose

A milestone resume (any non-`task` run) reads the run settings of the run's project
(`viewer-state.py get-run-settings <run.project.root>`) and passes the stored verify set or
the stored opt-out to `run-control.py resume`. When neither is stored, the resume ends today
with the sentence "Resume needs verify commands: none are stored for this project, and
running without verification was not chosen." (`core/stores/RunStore.qml:1253`). A run
started from a terminal can therefore never be resumed from the panel.

This card changes the store only. In that branch the store opens a **Resume dialog** state
for the run. The dialog's confirm asks for the verify commands (or the opt-out), launches the
resume with them, and saves them for the project. The card also adds `lastControlErrorType`,
the am error type of the last failed control request. The UI that renders the dialog
(`ResumeVerifyDialog`, `VerifyCommandsField`, Panel's mount) belongs to sibling cards.

Line numbers below are this branch's, not main's (the card's `:501-530`, `:625-647`, `:644`
are main's and stale):

| member | current lines |
|---|---|
| `lastControlError`, `lastControlErrorRunId` | `RunStore.qml:128-129` |
| runner aliases | `RunStore.qml:205-219` |
| `// ---- run controls (S2 4.1)`, `control()` | `:1095`, `:1114-1138` |
| `launchControl`, `settle`, `failControl`, `dismissControlError`, `dropRunner` | `:1143`, `:1159`, `:1179-1183`, `:1185-1188`, `:1191` |
| `controlReplied` (the two `failControl` calls) | `:1201-1227` (`:1221`, `:1223`) |
| `resumeWithSettings` (refusal at `:1253`) | `:1234-1256` |
| `// ---- cancel confirmation and the footer flash (S2 4.3)` | `:1299` |
| `refusalOf`, `flash`, `openCancel`/`closeCancel`/`confirmCancel` | `:1305-1313`, `:1317`, `:1323-1360` |
| `// ---- alerts (S2 4.4)` | `:1362` |
| `notifySaveReplied` (save-reply precedent) | `:1442-1450` |
| `dispatchCommands(form)` | `:1561-1564` |
| `settingsSaveRunner` (notify switch; not reused) | `:1830-1835` |
| `Runs.validateDispatch`, `_DISPATCH_VERIFY_MISSING` | `core/domain/runs.js:1529-1540`, `:1518` |

## Inherited constraints

- New state goes in a delimited section whose header line is literally
  `// ---- resume dialog`. It holds only its own members, all prefixed `resume`:
  `resumeRunId`, `resumeVerify`, `resumeAllowNoVerification`, `resumeError`,
  `resumeOpenFor(runId)`, `resumeClose()`, `resumeConfirm()`, `resumeSaveRunner`,
  `resumeSaveReplied(…)`. The split moves the section whole to `RunControlStore` (RR l.17-25,
  l.269-272).
- `lastControlErrorType` joins the control error pair in place, not in the new section. It is
  set in `failControl` and cleared in `dismissControlError` (RR l.28-30, l.229-231, l.266).
- The no-stored-set branch of `resumeWithSettings` settles the request and calls
  `resumeOpenFor(runId)` instead of `failControl`. Nothing is asked of am and no request stays
  pending (RR l.167-173, l.266-268).
- A usable stored set or the stored opt-out still resumes at once, as today (RR l.169-170).
- Resume is allowed when the form passes the verify rule of `Runs.validateDispatch`: at least
  one non-blank command, or the opt-out ticked. The store reads only that rule's `verify` error
  (RR l.187-189).
- `resumeConfirm()` re-checks `refusalOf("resume", id)`. If the run changed under the dialog,
  the dialog stays open with `resumeError` (RR l.189-190, l.292).
- The resume is launched with `--verify` pairs in order (blank lines dropped), or with
  `--allow-no-verification`, exactly as a stored set would be (RR l.190-192).
- The confirm saves `set-run-settings ROOT {"verify": [...], "allowNoVerification": bool}` on
  `resumeSaveRunner`, which is its own runner and not the notify switch's
  `settingsSaveRunner` (RR l.192-193, l.270-271).
- The resume does not wait for the save. A failed save flashes
  `The verify commands could not be saved` through the existing `flash` (RR l.193-194, l.293).
- A `task` run's resume never opens the dialog (RR l.195).
- Store tests live in `tests/core/stores/tst_run_store.qml`, in their own resume-dialog block
  (RR l.311-318).
- Card rules:
  - stores import only QtQml, Quickshell, Quickshell.Io and `../domain`, never another store
    (`docs/architecture.md`);
  - `tests/architecture` must pass;
  - `bash tests/run.sh` must be green;
  - TDD;
  - docstrings and comments state the contract only, with no narrative.

## Behaviour

### Control error type

- `property string lastControlErrorType: ""` is declared beside `lastControlError` and
  `lastControlErrorRunId` (`:128-129`). Its comment: the am error type of the last failed
  request, `""` when the failure carried none.
- `failControl(runId, sentence, type)` sets all three fields. `type` is stored when it is a
  string, else `""`. Its callers:
  - an `ok:false` envelope in `controlReplied` (`:1221`) passes `envelope.error.type` when
    `error` is an object and `type` is a string, else `""`;
  - the unusable run-control reply (`:1223`) passes `""`;
  - the unreadable settings reply in `resumeWithSettings` (`:1237`) passes `""`.
- `dismissControlError()` clears all three. `control()` already calls it first, so a new
  request clears the type too. So does the resume dialog's launch (below).

### The no-stored-set branch

`resumeWithSettings(runner, stdout, exitCode)` keeps its two other branches unchanged:

| settings reply | behaviour |
|---|---|
| not a readable object (`parseEnvelope` null) | unchanged: `failControl(runId, "The run settings gave no usable result (exit N).", "")`, the runner dropped |
| `verify` is a non-empty list of strings | unchanged: run-control with `--verify` pairs, and the opt-out is ignored |
| else, `allowNoVerification === true` | unchanged: run-control with `--allow-no-verification` |
| else (no list, an empty list, or a list with a non-string, and no opt-out) | **new**: the request is settled (`pending`, `stillWaiting` and the request entry for the run go), the runner is dropped (it leaves `controlRunners`, and run-control is never launched), and `resumeOpenFor(runId)` is called. No `failControl`: `lastControlError`, `lastControlErrorRunId` and `lastControlErrorType` stay `""`. No refresh and no snapshot. |

The refusal sentence is removed from the store. A settings reply for a request that is no
longer the pending one is still dropped by `controlReplied` before this function runs, so it
opens no dialog.

### `// ---- resume dialog`

The section sits right after the cancel confirmation section (it ends at `:1360`) and before
`// ---- alerts (S2 4.4)`. It declares, in this order, the properties, the functions, the
`resumeSaveRunner` HelperRunner and its `readonly property alias resumeSaveRunner`. QML allows
declarations anywhere in the object body, so the section stays liftable. Nothing else goes in
the section.

**State.**

| member | type | closed value | meaning |
|---|---|---|---|
| `resumeRunId` | string | `""` | the run the dialog asks about; `""` = closed |
| `resumeVerify` | var (list) | `[]` | the commands as typed, one per line, blanks allowed |
| `resumeAllowNoVerification` | bool | `false` | the opt-out box |
| `resumeError` | string | `""` | why the last confirm was refused |

There is no `resumeOpen` boolean: the card names none. The UI uses `resumeRunId !== ""`.

**`resumeOpenFor(runId)` → bool.**
- Refused, returning `false` and changing nothing, when `runId` is not a non-empty string,
  when the run is not in the snapshot (`runById` is null), or when its `workflow` is `"task"`.
- Otherwise it sets `resumeRunId = runId`, `resumeVerify = []`,
  `resumeAllowNoVerification = false` and `resumeError = ""`, and returns `true`.
- Opening for another run while open replaces the dialog: fields reset, new run id.
- It does not consult `refusalOf`. The confirm re-checks the run.

**`resumeClose()`.** Sets the four fields back to their closed values. Calling it when the
dialog is already closed is harmless.

**`resumeConfirm()` → bool.** The steps run in order, and the first that refuses ends it:

1. `resumeRunId === ""`: return `false` and change nothing.
2. The verify rule: `Runs.validateDispatch({ verify: resumeVerify, allowNoVerification:
   resumeAllowNoVerification })`. Only the error whose `field === "verify"` counts; prefix and
   parallelism errors are ignored. When there is one, `resumeError` becomes its message
   (`"Add a verify command or choose to run without verification"`). Return `false`. The
   dialog stays open, nothing is launched and nothing is saved.
3. The run: `reason = refusalOf("resume", resumeRunId)`. When it is non-empty, `resumeError`
   becomes `reason`. Return `false`. The dialog stays open, nothing is launched and nothing is
   saved. Examples: the run left the snapshot, it is now running, it is now cancelled, or a
   request for it is pending.
4. The launch. `commands = dispatchCommands({ verify: resumeVerify })`: the non-blank string
   commands, verbatim and in order. `extra` is `["--verify", c]` for each command when there
   is at least one. Otherwise it is `["--allow-no-verification"]` (step 2 guarantees the
   opt-out then). Commands win over a ticked opt-out, as the stored set does in
   `resumeWithSettings`. The request starts exactly as `control()` starts one:
   - the control error is dismissed;
   - a new token is taken;
   - a request entry is added with `baseline` the run's current state;
   - `pending[runId] = "resume"`;
   - a control runner with `runId`, `action "resume"`, `repoDir run.repo_dir` and
     `projectRoot runRoot(run)` is appended to `controlRunners`.

   Then `launchControl(runner, extra)` is called directly, with no settings step. The
   resulting argv is `python3|…/runs/run-control.py|resume|<id>|<repo_dir>|<extra…>`. The
   confirm must not go through `control("resume", id)`: with nothing stored, that would read
   the settings again and reopen the dialog.
5. The save. `resumeSaveRunner.run(["set-run-settings", runRoot(run),
   JSON.stringify({ verify: commands, allowNoVerification: resumeAllowNoVerification ===
   true })])`. Keys go in this order: `verify`, then `allowNoVerification`. `verify` is the
   dropped-blank list, `[]` when only the opt-out was chosen. The resume does not wait for the
   save: the run-control process is already launched and `pending` is set before the save
   replies.
6. `resumeClose()`. Return `true`.

**The shared start.** The request setup that `control()` does today (`:1117-1128`) moves
into one helper in the run-controls section, used by both `control()` and `resumeConfirm()`,
so there is no second copy. The planner names it, for example
`startRequest(action, runId)` returning the runner. It is not a `resume*` member and does not
belong in the new section. `control()`'s observable behaviour is unchanged.

**`resumeSaveRunner`.**
- A `HelperRunner` with script `backendDir + "projects/viewer-state.py"` and no guard: the
  save is for the run's project, whatever project is open.
- Its `onFinished` calls `resumeSaveReplied(stdout, exitCode)`.
- It is exposed as `readonly property alias resumeSaveRunner`.
- It is latest-wins, as every HelperRunner is: a second confirm before the first save replies
  supersedes the first save's reply.

**`resumeSaveReplied(stdout, exitCode)`.**
- When `parseEnvelope(stdout)` is an object with `ok === true`, nothing happens.
- Anything else (no line, garbled text, `ok:false`, any exit code with an unreadable reply)
  calls `flash("The verify commands could not be saved")`.
- It never touches `pending`, the control runners, the control error or the dialog state.
  The resume already runs.

## Error paths

| case | behaviour |
|---|---|
| no stored set and no opt-out, non-`task` run | dialog opens for the run; nothing pending; no control error; no run-control launch; no snapshot |
| stored list holds a non-string, no opt-out | same as above (the list is not usable) |
| stored list holds a non-string, opt-out stored | unchanged: `--allow-no-verification` |
| settings reply unreadable | unchanged: `failControl` with the settings sentence, type `""`; no dialog |
| `task` run resume | unchanged: straight to run-control, no settings read; `resumeOpenFor` refuses a `task` run even when called directly |
| `resumeOpenFor` for an unknown, empty or non-string id | `false`, state unchanged |
| confirm with the dialog closed | `false`, nothing changes |
| confirm with only blank or whitespace lines and no opt-out | `false`, `resumeError` = the verify message, nothing launched or saved |
| confirm after the run changed (now live, cancelled, gone, or pending) | `false`, `resumeError` = `refusalOf` reason, dialog stays open, nothing launched or saved |
| confirm with commands and the opt-out ticked | `--verify` pairs only; saved `allowNoVerification: true` alongside the commands |
| save fails | resume already launched; flash `The verify commands could not be saved` |
| run-control later refuses the resume (`ok:false`) | the existing `controlReplied` path: `failControl` with `Runs.controlError(envelope)` and `lastControlErrorType` = am's type |

## Out of scope

- `ResumeVerifyDialog`, `VerifyCommandsField`, Panel's mount, focus and Escape handling, and
  the `r` key and Resume buttons (they already call `control("resume", …)`). These belong to
  the UI sibling cards (RR l.196-198, l.279-282).
- `Runs.controlError` sentences, `Runs.offersRelaunch`, the escalated-`task` resume rule, and
  `stopReport`/`stopComment` (domain cards).
- `// ---- relaunch` / `relaunchOpenFor`, and any consumer of `lastControlErrorType`
  (relaunch card).
- Updating the open project's `runSettings` after a resume save. Later resumes re-read the
  settings from disk; the dispatch dialog picks the saved set up on its next settings load.
  The card does not ask for it.
- Showing the stored set before a resume that has one (RR l.336-338: keep the one-click
  resume).
- `docs/architecture.md` prose for the dialog (the UI card documents the component). Card
  2.4/docs cards own the docs.

## Tests

Tier: **store unit (QML TestCase)**, `tests/core/stores/tst_run_store.qml`, run by
`bash tests/run.sh tst_run_store`. Every behaviour here is store state and the argv of
helper processes, which this tier observes with the stub `HelperRunner`/`Process`
(`reply(proc, text, code)`, `argv(proc)`, `runner.seq`, `runner.current`). No UI exists yet,
so a UI or flow tier cannot apply. No Python changes, so there is no pytest tier. The
architecture tests (`tests/architecture`) run in the same suite and need no new test.

Fixtures and helpers: `ctlStore`, `dead`, `running`, `ctlEntry(id, status, live, workflow)`,
`settingsReply(verify, allow)`, `ctlOk`, `ctlFail(type, message)`, `tc.ctlCmd`,
`tc.settingsCmd`, `rootA` = `/home/u/my proj` (also the fixture's `project.root` and
`repo_dir`).

### Changed existing tests (run controls block)

1. `test_control_defaults`: also `lastControlErrorType === ""`.
2. `test_a_new_request_and_dismiss_clear_the_control_error`: after the
   `ctlFail("LockTimeoutError", …)` reply, `lastControlErrorType === "LockTimeoutError"`. A new
   `control()` clears it. After the second failure it is set again, and `dismissControlError()`
   clears it.
3. `test_milestone_resume_with_nothing_stored_launches_nothing`: keeps
   `runner.seq === 1`, `controlRunners.length === 0`, no pending and no snapshot seq change.
   Now also `lastControlError === ""`, `lastControlErrorRunId === ""` and
   `resumeRunId === "r1"`.
4. `test_a_verify_set_with_a_non_string_is_not_used`: r1 now opens the dialog
   (`resumeRunId === "r1"`, `lastControlError === ""`). r2's opt-out path is unchanged.
5. `noVerifySentence` is removed (no remaining use).

### New block `// ---- resume dialog (2.3)`

The block sits after the cancel confirmation block and before `// ---- alerts: the toasts`.

| # | test | proves |
|---|---|---|
| 1 | `test_resume_dialog_defaults` | `resumeRunId ""`, `resumeVerify` length 0, `resumeAllowNoVerification false`, `resumeError ""` on a fresh store |
| 2 | `test_nothing_stored_opens_the_dialog_and_leaves_nothing_pending` | after `settingsReply([], false)`: `resumeRunId "r1"`, `pending` and `stillWaiting` empty, `refusalOf("resume","r1") === ""`, `controlRunners.length 0`, snapshot seq unchanged, no control error |
| 3 | `test_garbled_settings_open_no_dialog` | unreadable reply: `resumeRunId ""`, settings sentence, `lastControlErrorType ""` |
| 4 | `test_a_task_run_never_opens_the_dialog` | `control("resume")` on a dead `task` run goes straight to run-control (`…resume|r1|/home/u/my proj`), `resumeRunId ""`; `resumeOpenFor` on that run returns `false` |
| 5 | `test_open_for_resets_the_fields_and_refuses_unknown_runs` | after setting fields, `resumeOpenFor("r1")` resets them and returns true. `resumeOpenFor("")`, `("nope")` and `(5)` return false and change nothing. Opening for `r2` replaces `r1` |
| 6 | `test_close_clears_every_field` | `resumeClose()` back to the closed values |
| 7 | `test_confirm_with_the_dialog_closed_does_nothing` | `false`; no runner, no save (`resumeSaveRunner.seq` unchanged) |
| 8 | `test_confirm_without_commands_or_opt_out_is_refused` | `resumeVerify ["", "  "]`, opt-out off: `false`, `resumeError === "Add a verify command or choose to run without verification"`, dialog open, no control runner, no save |
| 9 | `test_confirm_with_commands_passes_them_in_order_dropping_blanks` | `["a", "", "  ", "-b c"]` gives `…resume|r1|/home/u/my proj|--verify|a|--verify|-b c`, `command.length 9`, `pending.r1 "resume"`, dialog closed, returns true |
| 10 | `test_confirm_with_the_opt_out_passes_allow_no_verification` | `[]` and opt-out give `…|--allow-no-verification`, `command.length 6` |
| 11 | `test_commands_win_over_the_opt_out` | `["a"]` and opt-out: no `--allow-no-verification` in argv |
| 12 | `test_confirm_saves_the_set_for_the_runs_project` | save argv `python3|/plugin/core/backend/projects/viewer-state.py|set-run-settings|/home/u/my proj|{"verify":["a","-b c"],"allowNoVerification":false}`; the opt-out variant saves `{"verify":[],"allowNoVerification":true}` |
| 13 | `test_the_resume_does_not_wait_for_the_save` | before any save reply: the run-control process is launched (`controlRunners[0].current` has the run-control argv), `pending.r1` is set and the dialog is closed |
| 14 | `test_a_changed_run_keeps_the_dialog_open` | (a) a new snapshot shows r1 `running`: `false`, `resumeError` = `refusalOf("resume","r1")`, `resumeRunId "r1"`, no control runner, no save. (b) r1 gone from the snapshot: `resumeError "This run is no longer in the snapshot"` |
| 15 | `test_a_pending_request_refuses_the_confirm` | the dialog is open for r1, then `control("cancel","r1")` is pending (a pause of a dead run is refused, so it cannot be the pending request): confirm gives `resumeError "A request for this run is pending"` |
| 16 | `test_a_failed_save_flashes_but_the_resume_runs` | save reply `{"ok":false,…}` and exit 1, or garbled text: `flashText === "The verify commands could not be saved"`. The run-control runner is still there and `pending.r1` is still set |
| 17 | `test_a_good_save_flashes_nothing` | `{"ok":true}` reply: `flashText ""` |
| 18 | `test_the_resume_save_runner_is_not_the_notify_runner` | `setNotifyOnEscalation(true)` leaves `resumeSaveRunner.seq` unchanged. A resume confirm leaves `settingsSaveRunner.seq` unchanged. A notify save failure does not flash the resume sentence |
| 19 | `test_the_confirmed_resume_clears_the_control_error` | a prior failed pause on r1 (error and type set), then the dialog opens and confirms: `lastControlError`, `lastControlErrorRunId` and `lastControlErrorType` are all `""` |
| 20 | `test_a_refused_confirmed_resume_keeps_ams_error_type` | the run-control reply to the confirmed resume is `ctlFail("NotResumableError", "x")`: `lastControlErrorType "NotResumableError"`, `lastControlErrorRunId "r1"`, pending cleared |

Placement note: tests 2-4 exercise `control()` through `resumeWithSettings`. They belong in
the resume-dialog block because they prove the dialog's entry, and the split moves that block
with `RunControlStore`.

## Review focus (for the planner)

- A confirm that went through `control()` would loop back into the dialog. Test 9 fails if it
  does, because it expects a run-control argv and not a `get-run-settings` argv.
- The dialog opening must leave no `pending` entry, or every confirm would be refused with
  "A request for this run is pending" (test 2 asserts `refusalOf === ""`).
- The save JSON's key order and the dropped blanks must match exactly, because the argv is
  compared verbatim (test 12).
- Validation must ignore the `prefix` and `parallelism` errors that `validateDispatch` always
  returns for this partial form. Test 10 would fail otherwise.
