# 2.3 RunStore: the Resume dialog state Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A milestone resume with no stored verify set opens a Resume dialog state in `RunStore` instead of failing, the dialog's confirm launches the resume with the typed commands (or the opt-out) and saves them for the run's project, and every failed control request records am's error type in `lastControlErrorType`.

**Architecture:** All changes are in `core/stores/RunStore.qml`. `failControl` gains a `type` argument stored in a new `lastControlErrorType` beside the control error pair. The request setup in `control()` moves into a helper `startRequest(action, runId)` in the run-controls section, shared by `control()` and the new `resumeConfirm()`. A new `// ---- resume dialog` section, placed between the cancel confirmation section and `// ---- alerts (S2 4.4)`, holds the `resume*` state, functions, its own `resumeSaveRunner` HelperRunner and that runner's alias. The no-stored-set branch of `resumeWithSettings` settles the request and calls `resumeOpenFor(runId)`.

**Tech Stack:** QML/JS (Qt 6, Quickshell), QML TestCase run by `qmltestrunner` through `bash tests/run.sh`, stub `HelperRunner`/`Process` in `tests/stubs`.

**Spec:** `docs/superpowers/specs/2-3-runstore-the-resume-d592e35f.md` (reproduced in full below).

## Global Constraints

- New state goes in a delimited section whose header line is literally `// ---- resume dialog`; it holds only `resumeRunId`, `resumeVerify`, `resumeAllowNoVerification`, `resumeError`, `resumeOpenFor(runId)`, `resumeClose()`, `resumeConfirm()`, `resumeSaveRunner` (HelperRunner + `readonly property alias resumeSaveRunner`), `resumeSaveReplied(…)`.
- `lastControlErrorType` sits beside `lastControlError`/`lastControlErrorRunId`, set in `failControl`, cleared in `dismissControlError`; not in the new section.
- The shared request start (`startRequest`) lives in the run-controls section, is not a `resume*` member, and `control()`'s observable behaviour is unchanged.
- The confirm must not go through `control("resume", id)`.
- Save argv: `set-run-settings ROOT {"verify":[...],"allowNoVerification":bool}` — keys in that order, blanks dropped, on `resumeSaveRunner` (never `settingsSaveRunner`).
- Failed save flashes exactly `The verify commands could not be saved`.
- Verify refusal message is exactly `Add a verify command or choose to run without verification` (from `Runs.validateDispatch`, only the `field === "verify"` error).
- Stores import only QtQml, Quickshell, Quickshell.Io and `../domain`, never another store. No new imports are needed.
- `tests/architecture` must pass; `bash tests/run.sh` must be green; TDD.
- Docstrings and comments state the contract only, with no narrative.
- Store tests live in `tests/core/stores/tst_run_store.qml`, the new ones in a block `// ---- resume dialog (2.3)` after the cancel confirmation block and before `// ---- alerts: the toasts (S2 4.4)`.

## Review Focus

1. An `ok:false` run-control reply whose `error` is a string, whose `error.type` is not a string, or that has no `error` at all must leave `lastControlErrorType` `""` (not `undefined`, not a number) — test in Task 1.
2. Confirming twice in a row (a double click) must launch one run-control process and one save; the second confirm finds the dialog closed and returns `false` — assertion in Task 3, `test_confirm_with_commands_passes_them_in_order_dropping_blanks`.
3. Non-string entries in `resumeVerify` (a UI bug, or a model value) must be dropped from both the argv and the saved list, never sent as `"5"` — test in Task 3.
4. Commands with leading/trailing spaces are passed and saved verbatim, not trimmed (a quoted shell command can depend on them) — test in Task 3.
5. A resume of a second run that finds nothing stored while the dialog is open for another run replaces the dialog (new run id, fields reset) — test in Task 2.

---

## Spec (prepended; headings demoted one level)

## 2.3 RunStore: the Resume dialog state — design

Card: `d592e35f` (subtask of story `d44f2afe`, blocked by `eeaaa018`, which is done on this
branch). Parent design: `docs/superpowers/specs/2026-10-05-resume-recover-design.md`, cited
below as "RR l.N".

### Purpose

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

### Inherited constraints

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

### Behaviour

#### Control error type

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

#### The no-stored-set branch

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

#### `// ---- resume dialog`

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

### Error paths

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

### Out of scope

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

### Tests

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

#### Changed existing tests (run controls block)

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

#### New block `// ---- resume dialog (2.3)`

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

### Review focus (for the planner)

- A confirm that went through `control()` would loop back into the dialog. Test 9 fails if it
  does, because it expects a run-control argv and not a `get-run-settings` argv.
- The dialog opening must leave no `pending` entry, or every confirm would be refused with
  "A request for this run is pending" (test 2 asserts `refusalOf === ""`).
- The save JSON's key order and the dropped blanks must match exactly, because the argv is
  compared verbatim (test 12).
- Validation must ignore the `prefix` and `parallelism` errors that `validateDispatch` always
  returns for this partial form. Test 10 would fail otherwise.

---

## File Structure

- Modify: `core/stores/RunStore.qml` — the control error type (props at `:128-129`, `failControl`/`dismissControlError` at `:1179-1188`, `controlReplied` at `:1201-1227`), `startRequest` + `control()` at `:1114-1138`, `resumeWithSettings` at `:1234-1256`, the new `// ---- resume dialog` section inserted between the end of `confirmCancel()` (`:1360`) and `// ---- alerts (S2 4.4)` (`:1362`).
- Modify: `tests/core/stores/tst_run_store.qml` — the run controls block (`:2894-3329`) and a new block inserted right before `  // ---- alerts: the toasts (S2 4.4)` (`:3460`).

Line numbers are those of this branch before any task runs; later tasks shift them, so locate code by the quoted text.

---

### Task 1: `lastControlErrorType`

**Files:**
- Modify: `core/stores/RunStore.qml` (props `:128-129`; `failControl`/`dismissControlError` `:1179-1188`; `controlReplied` `:1220-1224`; `resumeWithSettings` `:1237`)
- Test: `tests/core/stores/tst_run_store.qml` (`test_control_defaults` `:2924`, `test_a_new_request_and_dismiss_clear_the_control_error` `:3087`, `test_garbled_run_settings_end_the_resume` `:3149`)

**Interfaces:**
- Consumes: nothing new.
- Produces: `property string lastControlErrorType` on RunStore; `failControl(runId, sentence, type)` — `type` stored when a string, else `""`; `dismissControlError()` clears all three fields.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_store.qml`, in `test_control_defaults`, after `compare(store.lastControlErrorRunId, "")` add:

```qml
    compare(store.lastControlErrorType, "")
```

Replace the whole of `test_a_new_request_and_dismiss_clear_the_control_error` with:

```qml
  function test_a_new_request_and_dismiss_clear_the_control_error() {
    var store = ctlStore([running("r1")]); if (!store) return
    store.control("pause", "r1")
    reply(store.controlRunners[0].current, ctlFail("LockTimeoutError", "busy"), 0)
    compare(store.lastControlError, "am is busy; try again in a moment")
    compare(store.lastControlErrorType, "LockTimeoutError", "am's error type is kept")
    compare(store.control("pause", "r1"), true, "the failed request no longer blocks the run")
    compare(store.lastControlError, "")
    compare(store.lastControlErrorRunId, "")
    compare(store.lastControlErrorType, "", "a new request clears the type")
    reply(store.controlRunners[0].current, ctlFail("LockTimeoutError", "busy"), 0)
    compare(store.lastControlErrorRunId, "r1")
    compare(store.lastControlErrorType, "LockTimeoutError")
    store.dismissControlError()
    compare(store.lastControlError, "")
    compare(store.lastControlErrorRunId, "")
    compare(store.lastControlErrorType, "")
  }

  // Review Focus 1.
  function test_the_control_error_type_is_empty_without_a_string_type() {
    var store = ctlStore([running("r1")]); if (!store) return
    var replies = [JSON.stringify({ ok: false, error: "boom" }) + "\n",
                   JSON.stringify({ ok: false, error: { type: 5, message: "x" } }) + "\n",
                   JSON.stringify({ ok: false }) + "\n",
                   "garbage\n"]
    for (var i = 0; i < replies.length; i++) {
      compare(store.control("pause", "r1"), true)
      reply(store.controlRunners[0].current, replies[i], 1)
      compare(store.lastControlErrorRunId, "r1", "reply " + i + " failed the request")
      verify(store.lastControlError !== "", "reply " + i + " says something")
      compare(store.lastControlErrorType, "", "reply " + i + " carries no string type")
    }
  }
```

In `test_garbled_run_settings_end_the_resume`, after `compare(store.lastControlErrorRunId, "r1")` add:

```qml
    compare(store.lastControlErrorType, "")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL lines for `test_control_defaults`, `test_a_new_request_and_dismiss_clear_the_control_error`, `test_the_control_error_type_is_empty_without_a_string_type` and `test_garbled_run_settings_end_the_resume` (`Actual (): undefined` / `Expected (): ""`), Totals with failures.

- [ ] **Step 3: Write the implementation**

In `core/stores/RunStore.qml`, replace

```qml
  property string lastControlError: ""      // Runs.controlError sentence of the last failed request
  property string lastControlErrorRunId: "" // the run that sentence is about
```

with

```qml
  property string lastControlError: ""      // Runs.controlError sentence of the last failed request
  property string lastControlErrorRunId: "" // the run that sentence is about
  property string lastControlErrorType: ""  // am's error type of that failure; "" when it carried none
```

Replace

```qml
  // A request ended without am taking it: the buttons come back and the
  // sentence shows under that run.
  function failControl(runId, sentence) {
    store.settle(runId)
    store.lastControlError = sentence
    store.lastControlErrorRunId = runId
  }

  function dismissControlError() {
    store.lastControlError = ""
    store.lastControlErrorRunId = ""
  }
```

with

```qml
  // A request ended without am taking it: the buttons come back and the
  // sentence shows under that run. `type` is am's error type when a string,
  // else "".
  function failControl(runId, sentence, type) {
    store.settle(runId)
    store.lastControlError = sentence
    store.lastControlErrorRunId = runId
    store.lastControlErrorType = typeof type === "string" ? type : ""
  }

  function dismissControlError() {
    store.lastControlError = ""
    store.lastControlErrorRunId = ""
    store.lastControlErrorType = ""
  }
```

In `controlReplied`, replace

```qml
    } else if (envelope !== null && envelope.ok === false) {
      store.failControl(runner.runId, Runs.controlError(envelope))
    } else {
      store.failControl(runner.runId, "The run control gave no usable result (exit " + exitCode + ").")
    }
```

with

```qml
    } else if (envelope !== null && envelope.ok === false) {
      var err = envelope.error
      var type = err !== null && typeof err === "object" && typeof err.type === "string" ? err.type : ""
      store.failControl(runner.runId, Runs.controlError(envelope), type)
    } else {
      store.failControl(runner.runId, "The run control gave no usable result (exit " + exitCode + ").", "")
    }
```

In `resumeWithSettings`, replace

```qml
      store.failControl(runner.runId, "The run settings gave no usable result (exit " + exitCode + ").")
```

with

```qml
      store.failControl(runner.runId, "The run settings gave no usable result (exit " + exitCode + ").", "")
```

(The third `failControl` call, the "Resume needs verify commands" one, is removed in Task 2; leave it as it is now.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: `Totals: … 0 failed`, no FAIL lines, no TypeError/ReferenceError lines.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): lastControlErrorType keeps am's error type of the last failed control request"
```

---

### Task 2: The resume dialog opens when nothing is stored

**Files:**
- Modify: `core/stores/RunStore.qml` (`resumeWithSettings` `:1229-1256`; new section after `confirmCancel()` ending `:1360`, before `  // ---- alerts (S2 4.4)`)
- Test: `tests/core/stores/tst_run_store.qml` (`noVerifySentence` `:3103`, `test_milestone_resume_with_nothing_stored_launches_nothing` `:3137`, `test_a_verify_set_with_a_non_string_is_not_used` `:3177`; new block before `  // ---- alerts: the toasts (S2 4.4)`)

**Interfaces:**
- Consumes: `failControl(runId, sentence, type)` (Task 1); existing `settle(runId)`, `dropRunner(runner)`, `runById(id)`.
- Produces: `property string resumeRunId` (`""` = closed), `property var resumeVerify` (`[]` closed), `property bool resumeAllowNoVerification` (`false` closed), `property string resumeError` (`""` closed); `resumeOpenFor(runId) → bool`; `resumeClose()`. Test helper `resumeDialogStore(entries, id)` in the test file.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_store.qml` delete the line

```qml
  property string noVerifySentence: "Resume needs verify commands: none are stored for this project, and running without verification was not chosen."
```

Replace the whole of `test_milestone_resume_with_nothing_stored_launches_nothing` with:

```qml
  function test_milestone_resume_with_nothing_stored_launches_nothing() {
    var store = ctlStore([dead("r1")]); if (!store) return
    store.control("resume", "r1")
    var runner = store.controlRunners[0]
    var seq = store.snapshotRunner.seq
    reply(runner.current, settingsReply([], false), 0)
    compare(runner.seq, 1, "run-control was never launched")
    compare(store.controlRunners.length, 0)
    compare(Object.keys(store.pending).length, 0)
    compare(store.lastControlError, "")
    compare(store.lastControlErrorRunId, "")
    compare(store.resumeRunId, "r1", "the Resume dialog asks for the commands")
    compare(store.snapshotRunner.seq, seq, "nothing was asked of am, so no snapshot")
  }
```

Replace the whole of `test_a_verify_set_with_a_non_string_is_not_used` with:

```qml
  // Review Focus 3.
  function test_a_verify_set_with_a_non_string_is_not_used() {
    var store = ctlStore([dead("r1"), dead("r2")]); if (!store) return
    store.control("resume", "r1")
    var runner = store.controlRunners[0]
    reply(runner.current, settingsReply(["a", 5], false), 0)
    compare(runner.seq, 1, "run-control was never launched")
    compare(store.resumeRunId, "r1", "the dialog opens instead")
    compare(store.lastControlError, "")
    store.control("resume", "r2")
    reply(store.controlRunners[0].current, settingsReply(["a", 5], true), 0)
    compare(argv(store.controlRunners[0].current), tc.ctlCmd + "resume|r2|/home/u/my proj|--allow-no-verification")
  }
```

Immediately before the line `  // ---- alerts: the toasts (S2 4.4)` insert:

```qml
  // ---- resume dialog (2.3)

  // Project A listing `entries`, with the Resume dialog opened for `id` by a
  // milestone resume that found nothing stored.
  function resumeDialogStore(entries, id) {
    var store = ctlStore(entries); if (!store) return null
    compare(store.control("resume", id), true)
    reply(store.controlRunners[store.controlRunners.length - 1].current, settingsReply([], false), 0)
    compare(store.resumeRunId, id, "the dialog is open")
    return store
  }

  // 1
  function test_resume_dialog_defaults() {
    var store = make(); if (!store) return
    compare(store.resumeRunId, "")
    compare(store.resumeVerify.length, 0)
    compare(store.resumeAllowNoVerification, false)
    compare(store.resumeError, "")
  }

  // 2
  function test_nothing_stored_opens_the_dialog_and_leaves_nothing_pending() {
    var store = ctlStore([dead("r1")]); if (!store) return
    store.control("resume", "r1")
    var seq = store.snapshotRunner.seq
    reply(store.controlRunners[0].current, settingsReply([], false), 0)
    compare(store.resumeRunId, "r1")
    compare(store.resumeVerify.length, 0)
    compare(store.resumeAllowNoVerification, false)
    compare(store.resumeError, "")
    compare(Object.keys(store.pending).length, 0)
    compare(Object.keys(store.stillWaiting).length, 0)
    compare(store.refusalOf("resume", "r1"), "", "no request is left pending, so the confirm can go")
    compare(store.controlRunners.length, 0)
    compare(store.snapshotRunner.seq, seq, "no snapshot")
    compare(store.lastControlError, "")
    compare(store.lastControlErrorRunId, "")
    compare(store.lastControlErrorType, "")
  }

  // 3
  function test_garbled_settings_open_no_dialog() {
    var store = ctlStore([dead("r1")]); if (!store) return
    store.control("resume", "r1")
    reply(store.controlRunners[0].current, "oops\n", 2)
    compare(store.resumeRunId, "")
    compare(store.lastControlError, "The run settings gave no usable result (exit 2).")
    compare(store.lastControlErrorRunId, "r1")
    compare(store.lastControlErrorType, "")
  }

  // 4
  function test_a_task_run_never_opens_the_dialog() {
    var store = ctlStore([ctlEntry("r1", "started", false, "task")]); if (!store) return
    compare(store.control("resume", "r1"), true)
    compare(argv(store.controlRunners[0].current), tc.ctlCmd + "resume|r1|/home/u/my proj")
    compare(store.resumeRunId, "")
    var other = ctlStore([ctlEntry("r1", "started", false, "task")]); if (!other) return
    compare(other.resumeOpenFor("r1"), false, "not even when called directly")
    compare(other.resumeRunId, "")
  }

  // 5 (and Review Focus 5)
  function test_open_for_resets_the_fields_and_refuses_unknown_runs() {
    var store = ctlStore([dead("r1"), dead("r2")]); if (!store) return
    store.resumeVerify = ["a"]
    store.resumeAllowNoVerification = true
    store.resumeError = "old"
    compare(store.resumeOpenFor("r1"), true)
    compare(store.resumeRunId, "r1")
    compare(store.resumeVerify.length, 0)
    compare(store.resumeAllowNoVerification, false)
    compare(store.resumeError, "")
    store.resumeVerify = ["b"]
    store.resumeAllowNoVerification = true
    var refused = ["", "nope", 5]
    for (var i = 0; i < refused.length; i++) {
      compare(store.resumeOpenFor(refused[i]), false, "refused: " + refused[i])
      compare(store.resumeRunId, "r1", "unchanged after " + refused[i])
      compare(JSON.stringify(store.resumeVerify), '["b"]')
      compare(store.resumeAllowNoVerification, true)
    }
    compare(store.resumeOpenFor("r2"), true, "another run replaces the dialog")
    compare(store.resumeRunId, "r2")
    compare(store.resumeVerify.length, 0)
    compare(store.resumeAllowNoVerification, false)

    store.resumeVerify = ["c"]
    store.control("resume", "r1")
    reply(store.controlRunners[0].current, settingsReply([], false), 0)
    compare(store.resumeRunId, "r1", "a resume that finds nothing stored replaces the open dialog")
    compare(store.resumeVerify.length, 0)
  }

  // 6
  function test_close_clears_every_field() {
    var store = resumeDialogStore([dead("r1")], "r1"); if (!store) return
    store.resumeVerify = ["a"]
    store.resumeAllowNoVerification = true
    store.resumeError = "old"
    store.resumeClose()
    compare(store.resumeRunId, "")
    compare(store.resumeVerify.length, 0)
    compare(store.resumeAllowNoVerification, false)
    compare(store.resumeError, "")
    store.resumeClose()
    compare(store.resumeRunId, "", "closing a closed dialog is harmless")
  }

```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL for `test_milestone_resume_with_nothing_stored_launches_nothing` (`lastControlError` is the old sentence), `test_a_verify_set_with_a_non_string_is_not_used`, and every new test 1-6 (`resumeRunId` undefined / `resumeOpenFor` is not a function).

- [ ] **Step 3: Write the implementation**

In `core/stores/RunStore.qml`, replace the whole `resumeWithSettings` function and its comment:

```qml
  // The run settings' reply for a milestone resume. A stored verify set (a
  // non-empty list of strings) goes to run-control as --verify pairs in its
  // order; otherwise the stored opt-out as --allow-no-verification; with
  // neither, or no readable reply, run-control is never launched and the
  // request ends with a sentence -- no re-snapshot, nothing was asked of am.
  function resumeWithSettings(runner, stdout, exitCode) {
```

through its closing brace (the block ending with `store.failControl(runner.runId, "Resume needs verify commands: …")`, `store.dropRunner(runner)`, `}`, `}`) with:

```qml
  // The run settings' reply for a milestone resume. A stored verify set (a
  // non-empty list of strings) goes to run-control as --verify pairs in its
  // order; otherwise the stored opt-out as --allow-no-verification. With
  // neither, the request is settled and the Resume dialog opens for the run;
  // with no readable reply, the request ends with a sentence. In both,
  // run-control is never launched and there is no re-snapshot.
  function resumeWithSettings(runner, stdout, exitCode) {
    var settings = store.parseEnvelope(stdout)
    if (settings === null) {
      store.failControl(runner.runId, "The run settings gave no usable result (exit " + exitCode + ").", "")
      store.dropRunner(runner)
      return
    }
    var verify = Array.isArray(settings.verify) ? settings.verify : []
    var usable = verify.length > 0
    for (var i = 0; i < verify.length; i++) {
      if (typeof verify[i] !== "string") usable = false
    }
    if (usable) {
      var extra = []
      for (var j = 0; j < verify.length; j++) extra.push("--verify", verify[j])
      store.launchControl(runner, extra)
    } else if (settings.allowNoVerification === true) {
      store.launchControl(runner, ["--allow-no-verification"])
    } else {
      var runId = runner.runId
      store.settle(runId)
      store.dropRunner(runner)
      store.resumeOpenFor(runId)
    }
  }
```

Then, between the closing `}` of `confirmCancel()` and the line `  // ---- alerts (S2 4.4)`, insert (keeping one blank line before the alerts header):

```qml

  // ---- resume dialog

  // The Resume dialog: a milestone resume with no stored verify set asks for
  // the commands here. `resumeRunId` is the run it asks about ("" = closed),
  // `resumeVerify` the commands as typed (blanks allowed),
  // `resumeAllowNoVerification` the opt-out, and `resumeError` why the last
  // confirm was refused.
  property string resumeRunId: ""
  property var resumeVerify: []
  property bool resumeAllowNoVerification: false
  property string resumeError: ""

  // Opens the dialog for runId with empty fields, replacing any open one, and
  // returns true. Returns false and changes nothing when runId is not a
  // non-empty string, its run is not in the snapshot, or it is a task run.
  function resumeOpenFor(runId) {
    if (typeof runId !== "string" || runId === "") return false
    var run = store.runById(runId)
    if (run === null || run.workflow === "task") return false
    store.resumeVerify = []
    store.resumeAllowNoVerification = false
    store.resumeError = ""
    store.resumeRunId = runId
    return true
  }

  function resumeClose() {
    store.resumeRunId = ""
    store.resumeVerify = []
    store.resumeAllowNoVerification = false
    store.resumeError = ""
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: `Totals: … 0 failed`, no FAIL lines, no TypeError/ReferenceError lines.

- [ ] **Step 5: Confirm the old sentence is gone**

Run: `grep -rn "Resume needs verify commands" core tests ui || echo none`
Expected: `none`

- [ ] **Step 6: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): a milestone resume with nothing stored opens the Resume dialog state"
```

---

### Task 3: `resumeConfirm`, the shared request start and the save

**Files:**
- Modify: `core/stores/RunStore.qml` (`control()` `:1110-1138`; the `// ---- resume dialog` section from Task 2)
- Test: `tests/core/stores/tst_run_store.qml` (the `// ---- resume dialog (2.3)` block from Task 2)

**Interfaces:**
- Consumes: `resumeRunId`, `resumeVerify`, `resumeAllowNoVerification`, `resumeError`, `resumeOpenFor`, `resumeClose` (Task 2); `failControl(runId, sentence, type)`, `lastControlErrorType` (Task 1); existing `refusalOf(action, runId)`, `dispatchCommands(form)`, `launchControl(runner, extra)`, `flash(text)`, `parseEnvelope(text)`, `Runs.validateDispatch(form)`; test helper `resumeDialogStore(entries, id)` (Task 2).
- Produces: `startRequest(action, runId) → runner` (run-controls section; runner not yet launched, already in `controlRunners`, `pending[runId] = action`); `resumeConfirm() → bool`; `resumeSaveRunner` (HelperRunner, alias); `resumeSaveReplied(stdout, exitCode)`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_store.qml`, directly after `test_close_clears_every_field` (end of the Task 2 block, before `  // ---- alerts: the toasts (S2 4.4)`), insert:

```qml
  property string resumeSaveCmd: "python3|/plugin/core/backend/projects/viewer-state.py|set-run-settings|/home/u/my proj|"
  property string resumeSaveFailed: "The verify commands could not be saved"

  // 7
  function test_confirm_with_the_dialog_closed_does_nothing() {
    var store = ctlStore([dead("r1")]); if (!store) return
    compare(store.resumeConfirm(), false)
    compare(store.controlRunners.length, 0)
    compare(Object.keys(store.pending).length, 0)
    compare(store.resumeSaveRunner.seq, 0, "nothing saved")
  }

  // 8
  function test_confirm_without_commands_or_opt_out_is_refused() {
    var store = resumeDialogStore([dead("r1")], "r1"); if (!store) return
    store.resumeVerify = ["", "  "]
    compare(store.resumeConfirm(), false)
    compare(store.resumeError, "Add a verify command or choose to run without verification")
    compare(store.resumeRunId, "r1", "the dialog stays open")
    compare(store.controlRunners.length, 0)
    compare(Object.keys(store.pending).length, 0)
    compare(store.resumeSaveRunner.seq, 0)
  }

  // 9 (and Review Focus 2)
  function test_confirm_with_commands_passes_them_in_order_dropping_blanks() {
    var store = resumeDialogStore([dead("r1")], "r1"); if (!store) return
    store.resumeVerify = ["a", "", "  ", "-b c"]
    compare(store.resumeConfirm(), true)
    compare(store.controlRunners.length, 1)
    var runner = store.controlRunners[0]
    compare(runner.runId, "r1")
    compare(runner.action, "resume")
    compare(runner.seq, 1, "run-control directly, no settings read")
    compare(argv(runner.current), tc.ctlCmd + "resume|r1|/home/u/my proj|--verify|a|--verify|-b c")
    compare(runner.current.command.length, 9)
    compare(store.pending.r1, "resume")
    compare(store.resumeRunId, "")
    compare(store.resumeVerify.length, 0)
    compare(store.resumeError, "")
    compare(store.resumeConfirm(), false, "a second confirm finds the dialog closed")
    compare(store.controlRunners.length, 1, "one run-control launch")
    compare(store.resumeSaveRunner.seq, 1, "one save")
  }

  // 10
  function test_confirm_with_the_opt_out_passes_allow_no_verification() {
    var store = resumeDialogStore([dead("r1")], "r1"); if (!store) return
    store.resumeVerify = []
    store.resumeAllowNoVerification = true
    compare(store.resumeConfirm(), true)
    var proc = store.controlRunners[0].current
    compare(argv(proc), tc.ctlCmd + "resume|r1|/home/u/my proj|--allow-no-verification")
    compare(proc.command.length, 6)
  }

  // 11
  function test_commands_win_over_the_opt_out() {
    var store = resumeDialogStore([dead("r1")], "r1"); if (!store) return
    store.resumeVerify = ["a"]
    store.resumeAllowNoVerification = true
    compare(store.resumeConfirm(), true)
    var proc = store.controlRunners[0].current
    compare(argv(proc), tc.ctlCmd + "resume|r1|/home/u/my proj|--verify|a")
    compare(proc.command.indexOf("--allow-no-verification"), -1)
  }

  // 12
  function test_confirm_saves_the_set_for_the_runs_project() {
    var store = resumeDialogStore([dead("r1"), dead("r2")], "r1"); if (!store) return
    store.resumeVerify = ["a", "", "-b c"]
    store.resumeConfirm()
    var save = store.resumeSaveRunner.current
    compare(argv(save), tc.resumeSaveCmd + '{"verify":["a","-b c"],"allowNoVerification":false}')
    compare(save.command.length, 5, "the root with a space and the JSON are one argument each")
    compare(save.launchGuard, "", "no guard")
    compare(store.resumeOpenFor("r2"), true)
    store.resumeAllowNoVerification = true
    store.resumeConfirm()
    compare(argv(store.resumeSaveRunner.current), tc.resumeSaveCmd + '{"verify":[],"allowNoVerification":true}')
  }

  // Review Focus 3.
  function test_non_string_commands_are_neither_passed_nor_saved() {
    var store = resumeDialogStore([dead("r1")], "r1"); if (!store) return
    store.resumeVerify = [5, "a", null]
    compare(store.resumeConfirm(), true)
    compare(argv(store.controlRunners[0].current), tc.ctlCmd + "resume|r1|/home/u/my proj|--verify|a")
    compare(argv(store.resumeSaveRunner.current), tc.resumeSaveCmd + '{"verify":["a"],"allowNoVerification":false}')
    var only = resumeDialogStore([dead("r1")], "r1"); if (!only) return
    only.resumeVerify = [5]
    compare(only.resumeConfirm(), false, "a non-string is not a command")
    compare(only.resumeError, "Add a verify command or choose to run without verification")
  }

  // Review Focus 4.
  function test_commands_are_passed_and_saved_verbatim() {
    var store = resumeDialogStore([dead("r1")], "r1"); if (!store) return
    store.resumeVerify = ["  make test  "]
    compare(store.resumeConfirm(), true)
    compare(store.controlRunners[0].current.command[6], "  make test  ")
    compare(argv(store.resumeSaveRunner.current), tc.resumeSaveCmd + '{"verify":["  make test  "],"allowNoVerification":false}')
  }

  // 13
  function test_the_resume_does_not_wait_for_the_save() {
    var store = resumeDialogStore([dead("r1")], "r1"); if (!store) return
    store.resumeVerify = ["a"]
    compare(store.resumeConfirm(), true)
    compare(store.resumeSaveRunner.busy, true, "the save has not replied")
    var proc = store.controlRunners[0].current
    compare(argv(proc), tc.ctlCmd + "resume|r1|/home/u/my proj|--verify|a")
    compare(proc.running, true)
    compare(store.pending.r1, "resume")
    compare(store.resumeRunId, "")
  }

  // 14
  function test_a_changed_run_keeps_the_dialog_open() {
    var store = resumeDialogStore([dead("r1")], "r1"); if (!store) return
    store.resumeVerify = ["a"]
    snapshot(store, [running("r1")])
    compare(store.resumeConfirm(), false)
    compare(store.resumeError, store.refusalOf("resume", "r1"))
    compare(store.resumeError, "The run is still running")
    compare(store.resumeRunId, "r1")
    compare(store.controlRunners.length, 0)
    compare(store.resumeSaveRunner.seq, 0)
    snapshot(store, [])
    compare(store.resumeConfirm(), false)
    compare(store.resumeError, "This run is no longer in the snapshot")
    compare(store.resumeRunId, "r1")
    compare(store.controlRunners.length, 0)
    compare(store.resumeSaveRunner.seq, 0)
  }

  // 15
  function test_a_pending_request_refuses_the_confirm() {
    var store = resumeDialogStore([dead("r1")], "r1"); if (!store) return
    compare(store.control("cancel", "r1"), true)
    store.resumeVerify = ["a"]
    compare(store.resumeConfirm(), false)
    compare(store.resumeError, "A request for this run is pending")
    compare(store.resumeRunId, "r1")
    compare(store.controlRunners.length, 1, "only the cancel")
    compare(store.resumeSaveRunner.seq, 0)
  }

  // 16
  function test_a_failed_save_flashes_but_the_resume_runs() {
    var replies = [[JSON.stringify({ ok: false, error: { type: "X", message: "y" } }) + "\n", 1],
                   ["garbage\n", 0],
                   ["", 1]]
    for (var i = 0; i < replies.length; i++) {
      var store = resumeDialogStore([dead("r1")], "r1"); if (!store) return
      store.resumeVerify = ["a"]
      store.resumeConfirm()
      reply(store.resumeSaveRunner.current, replies[i][0], replies[i][1])
      compare(store.flashText, tc.resumeSaveFailed, "reply " + i)
      compare(store.controlRunners.length, 1, "the run-control runner is still there")
      compare(store.pending.r1, "resume")
      compare(store.lastControlError, "")
      compare(store.resumeRunId, "")
    }
  }

  // 17
  function test_a_good_save_flashes_nothing() {
    var store = resumeDialogStore([dead("r1")], "r1"); if (!store) return
    store.resumeVerify = ["a"]
    store.resumeConfirm()
    reply(store.resumeSaveRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
    compare(store.flashText, "")
    compare(store.pending.r1, "resume")
  }

  // 18
  function test_the_resume_save_runner_is_not_the_notify_runner() {
    var store = resumeDialogStore([dead("r1")], "r1"); if (!store) return
    var resumeSeq = store.resumeSaveRunner.seq
    store.setNotifyOnEscalation(true)
    compare(store.resumeSaveRunner.seq, resumeSeq, "the switch does not use the resume runner")
    var notifySeq = store.settingsSaveRunner.seq
    var notifySave = store.settingsSaveRunner.current
    store.resumeVerify = ["a"]
    store.resumeConfirm()
    compare(store.settingsSaveRunner.seq, notifySeq, "the confirm does not use the notify runner")
    reply(notifySave, "garbage\n", 1)
    compare(store.flashText, "Notify on escalation could not be saved", "not the resume sentence")
    reply(store.resumeSaveRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
    compare(store.flashText, "Notify on escalation could not be saved", "a good resume save changes nothing")
  }

  // 19
  function test_the_confirmed_resume_clears_the_control_error() {
    var store = ctlStore([dead("r1")]); if (!store) return
    compare(store.control("cancel", "r1"), true)
    reply(store.controlRunners[0].current, ctlFail("LockTimeoutError", "busy"), 0)
    compare(store.lastControlErrorRunId, "r1")
    compare(store.lastControlErrorType, "LockTimeoutError")
    compare(store.resumeOpenFor("r1"), true)
    store.resumeVerify = ["a"]
    compare(store.resumeConfirm(), true)
    compare(store.lastControlError, "")
    compare(store.lastControlErrorRunId, "")
    compare(store.lastControlErrorType, "")
  }

  // 20
  function test_a_refused_confirmed_resume_keeps_ams_error_type() {
    var store = resumeDialogStore([dead("r1")], "r1"); if (!store) return
    store.resumeVerify = ["a"]
    store.resumeConfirm()
    var text = ctlFail("NotResumableError", "x")
    reply(store.controlRunners[0].current, text, 0)
    compare(store.lastControlError, Runs.controlError(JSON.parse(text)))
    compare(store.lastControlErrorType, "NotResumableError")
    compare(store.lastControlErrorRunId, "r1")
    compare(store.pending.r1, undefined, "the request is settled")
    compare(store.controlRunners.length, 0)
  }

```

Note on test 19: the spec names "a prior failed pause on r1", but a pause of a dead run is refused by `refusalOf` (`Runs.controls`: pause needs a running run), and the dialog needs a dead run; a failed cancel sets the same three fields, so the test uses a cancel.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL for tests 7-20 and the two Review Focus tests (`resumeConfirm` is not a function / `resumeSaveRunner` undefined). Tasks 1-2 tests still pass.

- [ ] **Step 3: Extract `startRequest` and use it in `control()`**

In `core/stores/RunStore.qml`, replace

```qml
  // Starts a pause, resume or cancel of one run in `runs`, of any project, and
  // returns whether it started: only when refusalOf(action, runId) is "".
  // The request acts on the run's repo_dir; a milestone resume reads the run
  // settings of the run's project.root. Confirming a cancel is the caller's job.
  function control(action, runId) {
    if (store.refusalOf(action, runId) !== "") return false
    var run = store.runById(runId)
    store.dismissControlError()
    controlState.nextToken += 1
    var requests = store.copyMap(controlState.requests)
    requests[runId] = { token: controlState.nextToken, action: action, baseline: Runs.runState(run),
                        launchedMs: Date.now(), acknowledged: false, requestedAt: "" }
    controlState.requests = requests
    var p = store.copyMap(store.pending)
    p[runId] = action
    store.pending = p
    var runner = controlC.createObject(store, { runId: runId, action: action, token: controlState.nextToken,
                                                repoDir: run.repo_dir, projectRoot: store.runRoot(run) })
    controlState.runners = controlState.runners.concat([runner])
    if (action === "resume" && run.workflow !== "task") {
```

with

```qml
  // Starts a pause, resume or cancel of one run in `runs`, of any project, and
  // returns whether it started: only when refusalOf(action, runId) is "".
  // The request acts on the run's repo_dir; a milestone resume reads the run
  // settings of the run's project.root. Confirming a cancel is the caller's job.
  function control(action, runId) {
    if (store.refusalOf(action, runId) !== "") return false
    var run = store.runById(runId)
    var runner = store.startRequest(action, runId)
    if (action === "resume" && run.workflow !== "task") {
```

and directly above that `// Starts a pause, resume or cancel …` comment insert:

```qml
  // A new request for runId, a run in `runs`: the control error is dismissed,
  // the request is recorded with the run's state as its baseline, pending is
  // set, and its runner (repo_dir and project.root of the run, not launched
  // yet) joins controlRunners and is returned.
  function startRequest(action, runId) {
    var run = store.runById(runId)
    store.dismissControlError()
    controlState.nextToken += 1
    var requests = store.copyMap(controlState.requests)
    requests[runId] = { token: controlState.nextToken, action: action, baseline: Runs.runState(run),
                        launchedMs: Date.now(), acknowledged: false, requestedAt: "" }
    controlState.requests = requests
    var p = store.copyMap(store.pending)
    p[runId] = action
    store.pending = p
    var runner = controlC.createObject(store, { runId: runId, action: action, token: controlState.nextToken,
                                                repoDir: run.repo_dir, projectRoot: store.runRoot(run) })
    controlState.runners = controlState.runners.concat([runner])
    return runner
  }

```

- [ ] **Step 4: Add `resumeConfirm`, `resumeSaveReplied` and `resumeSaveRunner` to the resume dialog section**

In the `// ---- resume dialog` section, directly after the closing `}` of `resumeClose()` (and before the blank line preceding `  // ---- alerts (S2 4.4)`), insert:

```qml

  // The dialog's confirm. Refused, with resumeError and the dialog left open,
  // when the form has no non-blank command and no opt-out, or when the run
  // cannot be resumed now (refusalOf). Otherwise the resume starts as
  // control() starts one and launches run-control at once: the non-blank
  // commands as --verify pairs in order, else --allow-no-verification. The
  // set is saved for the run's project without waiting for the reply, the
  // dialog closes, and true is returned.
  function resumeConfirm() {
    if (store.resumeRunId === "") return false
    var form = { verify: store.resumeVerify, allowNoVerification: store.resumeAllowNoVerification }
    var missing = Runs.validateDispatch(form).errors.filter(function(e) { return e.field === "verify" })
    if (missing.length > 0) {
      store.resumeError = missing[0].message
      return false
    }
    var runId = store.resumeRunId
    var reason = store.refusalOf("resume", runId)
    if (reason !== "") {
      store.resumeError = reason
      return false
    }
    var commands = store.dispatchCommands(form)
    var extra = []
    for (var i = 0; i < commands.length; i++) extra.push("--verify", commands[i])
    if (commands.length === 0) extra = ["--allow-no-verification"]
    var runner = store.startRequest("resume", runId)
    store.launchControl(runner, extra)
    resumeSaveRunner.run(["set-run-settings", runner.projectRoot,
                          JSON.stringify({ verify: commands, allowNoVerification: store.resumeAllowNoVerification === true })])
    store.resumeClose()
    return true
  }

  // set-run-settings: {"ok": true} changes nothing; anything else flashes.
  // Never touches the request, the control error or the dialog.
  function resumeSaveReplied(stdout, exitCode) {
    var reply = store.parseEnvelope(stdout)
    if (reply !== null && reply.ok === true) return
    store.flash("The verify commands could not be saved")
  }

  // set-run-settings for a confirmed resume; latest wins. No guard: the save
  // is for the run's project, whatever project is open.
  HelperRunner {
    id: resumeSaveRunner
    script: store.backendDir + "projects/viewer-state.py"
    onFinished: function(stdout, exitCode) { store.resumeSaveReplied(stdout, exitCode) }
  }
  readonly property alias resumeSaveRunner: resumeSaveRunner
```

- [ ] **Step 5: Run the store tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: `Totals: … 0 failed`, no FAIL lines, no TypeError/ReferenceError/"Unable to assign" lines.

If QML reports a duplicate-name error for `resumeSaveRunner` (id and alias share the name), check it against the existing `readonly property alias settingsSaveRunner: settingsSaveRunner`, which uses the same pattern and loads; the difference would only be placement, and QML accepts property declarations after child objects.

- [ ] **Step 6: Run the full suite**

Run: `timeout 900 bash tests/run.sh`
Expected: pytest ends with `passed` and no failures (including `tests/architecture`), every `== tests/…/tst_*.qml` line is followed by a `Totals: … 0 failed` line, exit status 0.

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): the Resume dialog's confirm launches the resume with the typed commands and saves them"
```

---

## Self-review against the spec

- Control error type: Task 1 (`failControl` 3-arg, three callers, `dismissControlError`, defaults; `control()` clears via `startRequest` → `dismissControlError`; confirm clears — test 19).
- No-stored-set branch: Task 2 (settle, drop runner, `resumeOpenFor`, no `failControl`, no refresh); unchanged branches keep their existing tests; non-string list → dialog (changed test 4); garbled settings → no dialog (test 3).
- Section header literally `// ---- resume dialog`, order properties → functions → HelperRunner → alias: Tasks 2-3; `startRequest` in run-controls section: Task 3 Step 3.
- `resumeOpenFor` refusals (non-string, empty, unknown, task) and replacement: tests 4, 5. `resumeClose`: test 6.
- `resumeConfirm` steps 1-6: tests 7 (closed), 8 (verify rule, message), 10 (prefix/parallelism ignored), 14/15 (`refusalOf`), 9/10/11 (argv, order, blanks dropped, commands win), 12 (save argv, key order), 13 (no wait), 9 (dialog closes).
- `resumeSaveRunner` no guard (test 12 `launchGuard ""`), own runner (test 18). `resumeSaveReplied`: tests 16, 17.
- Changed existing tests 1-5: Task 1 (1, 2), Task 2 (3, 4, 5).
- Deviation recorded: test 19 uses a failed cancel because a pause of a dead run is refused.
<!-- task-pipeline: validated -->
