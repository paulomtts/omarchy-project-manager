# 3.5 RunStore: control, resume settings and logs for a run of any project — design

Card `20ecca37` (subtask of story `fee6bfab` "Global runs store"), blocked by 3.4
(`7159b939`, landed: `docs/superpowers/specs/3-4-runstore-alerts-7159b939.md`, cited as
**3.4:§**). The parent design is `docs/superpowers/specs/2026-10-05-runs-all-projects-design.md`,
cited as **S6:line**.

3.4 hands this card this work: "control, resume settings (`get-run-settings` of
`run.project.root`), logs, removing the remaining guards and the `projectSwitched()` resets of
the cancel dialog, control error and flash" (3.4 "Out of scope").

All production code is in `core/stores/RunStore.qml`. The store tests are in
`tests/core/stores/tst_run_store.qml`. The card also puts three UI test fixtures and one UI
test in scope (§6), and this spec adds the matching `docs/architecture.md` sentences (§7),
because that file states the RunStore contract and would otherwise say the opposite of the code.

## Inherited constraints

- **Controls act on the run's own repository (S6:65-68).** Pause, resume and cancel pass the
  run's `repo_dir`. A milestone resume reads the verify set from the run settings of the run's
  project (`run.project.root`), never the open project's. The store's guard is "the run the
  request was for".
- **A control request for a run of another project (S6:169)** goes to that run's repo. Its
  result and error show on that run's row, never against the open project.
- **Run detail works for a run of any project (S6:59-60)** without switching the open project.
  The output pane reads through `am` by run id.
- **`project` keeps its meaning (S6:130-133)**: the open project's root, `""` when none. It is
  no longer a guard for anything about runs. The logs, settings and control runners drop their
  `guard: store.project` (S6:133). A project switch no longer resets pending requests
  (S6:133-134).
- **Dispatch stays project-bound (S6:83-85).** `dispatchDefaultsRunner`,
  `dispatchPreviewRunner`, the dispatch start runners and `runSettingsRunner` keep their guards.
- **Layering (S6:111; `docs/architecture.md`).** `RunStore.qml` imports only QtQml, Quickshell,
  Quickshell.Io and `../domain`. `tests/architecture` must pass (no duplicated components, icon
  glyph rules).
- **Comments state the contract only, no narrative** (card).
- **Verification:** `bash tests/run.sh` is green (card).

## Where the card is silent, and the reading this spec fixes

1. **A run with no usable `repo_dir` or `project.root`.** Every run the store builds from a
   snapshot has both: `normalizeRun` keeps the row's `repo_dir`, and `Runs.withProject` gives
   `project.root` a registry root (`RunStore.qml:990`). A run set directly (tests, or a future
   path) may lack them. The card forbids falling back to `store.project`. So:
   - a run whose `repo_dir` is not a non-empty string can't be paused, resumed or cancelled.
     `refusalOf` says `This run has no repository`;
   - a non-`task` run whose `project.root` is not a non-empty string (`project` missing, null,
     not an object, or its `root` not a non-empty string) can't be resumed. `refusalOf("resume", …)`
     says `This run's project is not known`. Pause and cancel of that run are unaffected.
   - `fetchLogs` launches nothing for a selected run with no usable `project.root`.
2. **Which root the logs use.** `runs-logs.py <project_root> …` passes it to `am logs
   --repo-dir`. The store passes the selected run's `project.root`. For a run of the open
   project that is the same value as before (the registry root), so the argv of every existing
   logs test is unchanged.
3. **The repository a milestone resume passes after its settings step.** The run can leave the
   snapshot while `get-run-settings` is in flight. The request keeps the `repo_dir` and the
   `project.root` it was made with, captured on its runner when `control()` starts it.
   `launchControl` reads them from the runner, never from `runs` or `project`.
4. **`controlDropped`.** It settled a request whose reply the guard dropped. Without a guard no
   reply is dropped, so it and the `onBusyChanged` hook that called it go. `dropRunner` stays.

## What the store must do

### 1. `control(action, runId)`

It starts a request and returns true when `refusalOf(action, runId)` is `""`. Otherwise it
returns false and launches nothing. That covers an unknown action, an id that is not a
non-empty string, a run not in `runs`, the two refusals of ambiguity 1, a pending request,
and an action `Runs.controls(run)` disables. **The open project is not consulted.** No project
open is not a refusal.

The request's runner (`controlC`) is created with `runId`, `action`, `token`, `repoDir` =
the run's `repo_dir` and `projectRoot` = the run's `project.root` (`""` when it has none,
which only a pause or a cancel or a `task` resume can reach). Its `guard` is `""`, the
`HelperRunner` default (`core/stores/HelperRunner.qml:15`). It has no `madeFor` property and
no `onBusyChanged` handler.

- **Pause, cancel, and a `task` run's resume:** `run-control.py ACTION RUN REPO` with
  `REPO` = `runner.repoDir`. The command is 5 elements: `python3`, the script, the action, the
  run id and the repo, each one argument verbatim.
- **Any other resume:** first `viewer-state.py get-run-settings <runner.projectRoot>` on the
  same runner (4 elements). The reply rules of `resumeWithSettings` are unchanged
  (`RunStore.qml:1216-1242`). A launched `run-control.py resume RUN REPO [--verify CMD]…
  [--allow-no-verification]` uses `runner.repoDir`.

### 2. Replies and a project switch

A control reply is applied whatever `project` is when it lands, and whatever it was when
the request started: `controlReplied` and `resumeWithSettings` are unchanged. `ok: true`
acknowledges the request, which stays pending until a snapshot settles it, and re-snapshots.
A failure settles it and sets `lastControlError` / `lastControlErrorRunId` to that run. Both
re-snapshot as today. A settings-step reply after a switch launches `run-control.py` as if no
switch happened.

### 3. `refusalOf(action, runId)`

The order is:

1. `Unknown control`
2. `This run is no longer in the snapshot`: an id that is not a non-empty string, or not in
   `runs`. With no project open, a run in `runs` is found like any other.
3. `This run has no repository`
4. `This run's project is not known`, only for a `resume` of a run whose `workflow` is not
   `"task"`
5. `A request for this run is pending`
6. `Runs.controls(run)[action].reason`

It changes nothing. `openCancel` and `confirmCancel` call it as today.

### 4. `projectSwitched()`

It does exactly this: `runSettings = {}`, `resetDispatch()`, then sets `runSettingsRunner.guard`
to the new project and runs `get-run-settings` for it when it is not `""` (3.4:§5). It no
longer calls `dismissControlError()`, `closeCancel()` or `flash("")`. A switch leaves
`cancelOpen`, `cancelRunId`, `cancelText`, `cancelError`, `flashText` (and `flashTimer`
running), `lastControlError`, `lastControlErrorRunId`, `pending`, `stillWaiting` and
`controlRunners` as they were. Its header comment lists these as kept.

### 5. Logs

- `selectAttempt(cardId, phase, attempt)` no longer needs a project. Nothing happens without
  a selected run or a real attempt (the rest of the rules are unchanged).
- `fetchLogs()` launches nothing when there is no selected run id, no selected attempt, the
  selected run is not in `runs`, or its `project.root` is not a non-empty string. Otherwise
  it launches `runs-logs.py ROOT RUN CARD PHASE ATTEMPT`, 7 elements, with `ROOT` = the
  selected run's `project.root` verbatim.
- `logsRunner` has no guard (`launchGuard` `""`). Latest-wins and `onBusyChanged` (idle means
  `logsLoading` false) are unchanged. A reply that lands after a project switch is applied:
  text, truncation, time and error as for any reply.
- `openDefaultAttempt` doesn't change. Its comments and those of `selectAttempt`, `fetchLogs`,
  `applyLogs` and `logsRunner` stop mentioning a project or a guard.

### 6. UI test fixtures and the one UI test (card)

- `tests/ui/tst_runs_flow.qml` `run()` (lines 21-25), `tests/ui/tst_shortcuts.qml` `normRun()`
  (435-439) and the literal run in `inRuns()` (316-317) each gain
  `project: { root: "/home/u/a", name: "alpha" }`.
- `tests/ui/tst_runs_flow.qml:244`
  `test_a_project_switch_on_the_run_view_leaves_it_and_drops_the_late_logs` is renamed
  `test_a_project_switch_on_the_run_view_leaves_it_and_the_late_logs_land`. Its last
  assertion becomes `logsText === "late"` and `logsLoading === false` (test 11).
- No other UI file changes. `ui/Shortcuts.qml:72` still gates p / r / c on a selected project
  (lifting that belongs to the UI story), so
  `tst_shortcuts.qml:555 test_without_a_project_the_run_keys_are_left_alone` passes unchanged.

### 7. Docs

In `docs/architecture.md:90-91`, these sentences are corrected:

- The logs launch reads "the selected run's project root first". "guarded by the project like
  the snapshot" goes.
- Control: "it refuses without a project" goes, and the two new refusals are listed. "guarded
  by the project … a reply for a project the user has left is dropped" becomes "no guard; a
  reply is applied whatever project is open". `REPO` is the run's `repo_dir`. The milestone
  resume reads `get-run-settings` of the run's `project.root`.
- "a project switch empties it and the control error" and "a project switch closes the dialog
  and clears the flash" become "a project switch keeps them".
- The `refusalOf` sentence list gains the two sentences in their order.

## Error paths

| input | behaviour |
|---|---|
| `control("pause", id)` with `project` `""` and the run in `runs` | starts; argv carries the run's `repo_dir` |
| a run of project B (`repo_dir` `/home/u/b-work`) paused with A open | argv `pause|id|/home/u/b-work`; never A's root |
| a milestone resume of a run of B with A open | `get-run-settings|<B root>`; then `resume|id|<run repo_dir>|--verify…` |
| the run leaves the snapshot while its resume settings are in flight | the settings reply still launches `run-control.py` with the captured `repo_dir` |
| a run with `repo_dir` `""` | `control` false, nothing launched; `refusalOf` `This run has no repository` |
| a milestone run with no `project` | `control("resume")` false; `refusalOf("resume")` `This run's project is not known`; pause and cancel of it work |
| a `task` run with no `project` | resume skips settings and runs `run-control.py resume RUN REPO` |
| a control reply after `project` changed (to B, or to `""`) | applied: ok acknowledges and re-snapshots; failure sets the error on that run |
| a project switch with the cancel dialog open, a flash showing, a control error and requests pending | all kept, flash timer still running |
| logs of a run of B selected with no project open | `runs-logs.py|<B root>|run|card|phase|n` |
| a logs reply after a project switch | applied; `logsLoading` false |
| the selected run has no `project.root` | no logs launch, `logsLoading` unchanged |

## Tests

The store tests are in the **store tier** (`tests/core/stores/tst_run_store.qml`, a QML
`TestCase` run by `bash tests/run.sh`). The behaviour is the store's own: runner argv, guards,
and reply-driven state, driven by stubbed `Process` replies with no UI. Only this tier can read
`controlRunners`, `launchGuard` and `pending` directly. They use the existing helpers `make`,
`makeWithRoots`, `makeWithProject`, `ctlStore`, `ctlEntry`, `running`, `dead`, `entry` (its
`root` argument sets `repo_dir`), `okEntry`, `allReply`, `okReply`, `snapshot`, `reply`,
`argv`, `ctlOk`, `ctlFail`, `settingsReply`, `logsReply`, `treeEntry`, and `rootA` / `rootB`.
To give a run a `repo_dir` that differs from its root, list it with `allReply([okEntry(rootB,
[e])])` where `e.repo_dir = "/home/u/b-work"`. The store tags by the entry's root, not by
`repo_dir`. The new tests go in a `// ---- control and logs for a run of any project (3.5)`
block that replaces `// ---- requests and logs across a project switch (3.1)`.

1. **Pause and cancel pass the run's `repo_dir`, with or without a project.** `makeWithRoots([rootA,
   rootB])`, no project. The reply lists `running("a1")` under A and a running `b1` under B with
   `repo_dir` `/home/u/b-work`. `control("pause", "b1")` is true. Its argv is
   `ctlCmd + "pause|b1|/home/u/b-work"`, 5 elements, `launchGuard` `""`. `control("cancel", "a1")`
   gives `cancel|a1|/home/u/my proj`. Then `project = rootA` and a new `control` on a third
   run of B still passes B's `repo_dir`.
2. **A `task` run's resume passes its `repo_dir` with no settings step.** A dead `task` run of B
   with A open: one launch, `resume|id|/home/u/b-work`.
3. **A milestone resume reads its own project's settings.** A dead milestone run of B with A
   open: the first launch is `viewer-state.py|get-run-settings|/home/u/b`, 4 elements,
   `launchGuard` `""`. After `settingsReply(["a"], false)` the second is
   `resume|id|/home/u/b-work|--verify|a`.
4. **The resume keeps the repository it was asked for.** As 3, but before the settings reply a
   snapshot lists no run of B. Then the settings reply still launches
   `resume|id|/home/u/b-work|--verify|a`, and `pending[id]` is `"resume"`.
5. **The two new refusals.** Set `store.runs` directly: `{…running, repo_dir: ""}` and a dead
   milestone run with `repo_dir` set and no `project`. The first gives `control` false and
   `refusalOf` `This run has no repository` for pause, resume and cancel. The second gives
   `refusalOf("resume")` `This run's project is not known`, `control("resume")` false, and
   `control("cancel")` true. A dead `task` run with no `project` resumes. Nothing else launches.
6. **A request for another project's run survives a project switch, and its reply shows on
   that run.** A open, `control("pause", "b1")`, then `project = rootB`, then `project = ""`:
   `pending.b1` is still `"pause"` and `controlRunners.length` 1. `ctlOk` acknowledges it
   (pending stays, snapshot seq +1, runner gone). A second request on `b2` answered
   `ctlFail("NotRunningError", …)` after a switch sets `lastControlError` `The run is not
   running` and `lastControlErrorRunId` `b2`. A milestone resume whose settings reply lands
   after a switch launches `run-control.py`.
7. **A project switch keeps the dialog, the flash, the control error and the requests.**
   `openCancel("r1")`, `cancelText` `can`, `cancelError` `x`, `flash("…")`, a failed control on
   r2 (control error set), and an in-flight pause on r3 with `stillWaiting` set. `project =
   rootB`: every one of them is unchanged and `flashTimer.running` is true. This replaces
   `test_a_project_switch_closes_the_dialog_and_clears_the_flash`.
8. **Logs of another project's run load with no project open.** `makeWithRoots([rootA,
   rootB])`, a reply with `treeEntry("rb", "started", rootB)` under B, then `selectedRunId =
   "rb"`: argv `python3|…/runs-logs.py|/home/u/b|rb|<openCard>|explore|1`, `launchGuard`
   `""`. A `logsReply("x\n")` sets `logsText` `x`.
9. **A logs reply after a project switch lands.** `opened()`, refresh, `project = rootB`, then
   reply `logsReply("late\n")`: `logsText` `late`, `logsLoading` false. This replaces
   `test_a_logs_fetch_in_flight_at_a_switch_ends_and_keeps_the_text`.
10. **No logs for a selected run without a project root.** Set `store.runs` to one tree run
    with no `project`, select it: `logsRunner.current` is null and `logsLoading` false.
11. **UI: the late logs land** (`tests/ui/tst_runs_flow.qml`, UI tier, because the card makes
    the existing Panel flow test assert it). The test from §6 is renamed, and it asserts
    `logsText === "late"` and `logsLoading === false` after the switch.

Existing store tests rewritten for the changed contract:

- `test_selecting_a_run_fetches_its_default_attempt` (2445): `launchGuard` `""`.
- `test_no_logs_launch_without_project_run_or_selection` (2471): renamed
  `test_no_logs_launch_without_a_run_or_a_selection`. The bare-store label reads "no run
  selected".
- `test_logs_argv_leads_with_the_current_project_root` (2690): renamed
  `…_leads_with_the_runs_project_root`. Its argv does not change.
- `test_pause_and_cancel_launch_the_exact_argv` (2751): `launchGuard` `""`.
- `test_control_refusals_launch_nothing` (2841): the bare-store line now asserts false with
  label "a run not in the snapshot" (an empty store has no runs).
- `test_a_finished_request_leaves_control_runners` (2887): the second half now asserts that a
  reply after a switch is applied (runner gone, snapshot seq +1).
- `test_refusal_of_says_why_a_control_would_not_start` (3156): the bare-store label becomes
  "not in the snapshot".
- `test_a_project_switch_closes_the_dialog_and_clears_the_flash` (3278) and the two tests at
  5428 and 5448 are replaced by new tests 7, 6 and 9.
- `test_a_reply_after_returning_to_the_project_is_applied` (3091) passes unchanged.
- `test_a_project_switch_leaves_the_run_list_and_the_live_state_alone` (395) passes unchanged.

Regression: every other control, resume, cancel-dialog and logs test passes with its argv
unchanged, because the fixtures' `repo_dir` and `project.root` equal `rootA`. Verification
is `bash tests/run.sh`, all green, including `tests/architecture`, `tst_app_runs.qml` and every
`tests/ui/tst_*.qml`.

## Out of scope

- **UI story `63a11d2f`:** lifting the project gate of `Shortcuts.handleRunKey`
  (`ui/Shortcuts.qml:72`), the Runs and Run detail `visible` gates, `Panel.openToastRun`, the
  **Open project** action, and any UI check of cross-project controls beyond §6.
- **Dispatch (S3, S6:83-85):** `dispatchDefaultsRunner` / `dispatchPreviewRunner` guards, the
  dispatch start runners' `madeFor`, `runSettingsRunner` and `resetDispatch` on a switch.
- Requests keyed by run id across two projects with the same id; any change to
  `core/domain/runs.js`, `run-control.py`, `runs-logs.py`, `viewer-state.py` or
  `HelperRunner.qml`; the snapshot, watch and alert rules of 3.1-3.4.

---

# 3.5 RunStore: control, resume settings and logs for a run of any project Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `RunStore`'s pause / resume / cancel and attempt logs act on the run's own `repo_dir` and `project.root`, with no project guard. A control or logs reply is applied whatever project is open, and a project switch no longer resets the cancel dialog, the flash, the control error or pending requests.

**Architecture:** Everything is in `core/stores/RunStore.qml`. A new `runRoot(run)` helper reads a run's `project.root`. `refusalOf` gains two sentences and stops consulting `project`. `control()` becomes "refusalOf is empty, then start". It captures `repoDir` / `projectRoot` on the request's runner (`controlC`), which loses its guard, `madeFor` and `onBusyChanged`, and `controlDropped` goes. `launchControl` and the milestone-resume settings read use the captured values. `fetchLogs` / `selectAttempt` stop needing a project and launch with the selected run's `project.root`, and `logsRunner` loses its guard. `projectSwitched()` stops calling `dismissControlError()`, `closeCancel()` and `flash("")`. `core/domain/runs.js`, the backends and `HelperRunner.qml` do not change.

**Tech Stack:** QML (Qt 6, Quickshell), the `core/domain/runs.js` domain library, QtTest (`qmltestrunner`) driven by `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/3-5-runstore-control-20ecca37.md` (prepended above).

## Global Constraints

- `RunStore.qml` imports only QtQml, Quickshell, Quickshell.Io and `../domain`. `tests/architecture` must pass (no duplicated components, icon glyph rules).
- Comments state the contract only, no narrative.
- `project` keeps its meaning: the open project's root, `""` when none. It is no longer a guard for anything about runs.
- Dispatch stays project-bound. `dispatchDefaultsRunner`, `dispatchPreviewRunner`, the dispatch start runners (`madeFor`) and `runSettingsRunner` keep their guards, and `projectSwitched()` still calls `resetDispatch()` and re-reads `get-run-settings` for the new project.
- No change to `core/domain/runs.js`, `run-control.py`, `runs-logs.py`, `viewer-state.py` or `HelperRunner.qml`.
- Refusal sentences, verbatim: `Unknown control`, `This run is no longer in the snapshot`, `This run has no repository`, `This run's project is not known`, `A request for this run is pending`, then `Runs.controls(run)[action].reason`. Checked in that order.
- `run-control.py` argv: `python3`, the script, ACTION, RUN, REPO (5 elements), REPO = the runner's `repoDir`; a milestone resume adds `--verify CMD`… or `--allow-no-verification`. The settings read argv: `python3`, `viewer-state.py`, `get-run-settings`, the runner's `projectRoot` (4 elements).
- `runs-logs.py` argv: `python3`, the script, ROOT, RUN, CARD, PHASE, ATTEMPT (7 elements), ROOT = the selected run's `project.root` verbatim.
- No UI production file changes. `ui/Shortcuts.qml:72` keeps its project gate.
- Verification: `bash tests/run.sh` is green.

## Review Focus

1. **A cancel dialog opened for another project's run, then the open project is closed (`project = ""`), then confirmed.** The dialog is kept, and the cancel launches with that run's `repo_dir`. Test in Task 2 (`test_a_cancel_dialog_for_another_projects_run_survives_closing_the_project_and_confirms`).
2. **`c` on a run with no `repo_dir`** (`openCancel`). No dialog opens, and the footer flashes `This run has no repository`. Test in Task 1 (`test_open_cancel_on_a_run_with_no_repository_flashes_why`).
3. **The selected run leaves the snapshot while its logs are shown.** No logs launch (a run not in `runs` has no root), `logsLoading` is not left true, and the shown text stays. Test in Task 3 (`test_a_selected_run_that_leaves_the_snapshot_launches_no_logs`).
4. **A registry root with odd characters.** `Runs.withProject` trims a trailing `/` from the root (3.1). The logs ROOT is the run's `project.root` byte for byte, which for a root without a trailing slash is the registry root. Test in Task 3 (`test_logs_argv_keeps_an_odd_root_verbatim`, rewritten so its root has no trailing slash; see "Deviation" below).
5. **A request made with no project open whose reply lands after a project is opened.** It is applied: the error shows on that run and the store re-snapshots. Test in Task 1 (`test_a_request_made_with_no_project_open_is_answered_after_one_opens`).

**Deviation from the spec, found while checking the plan against the code:** the spec says the argv of every existing logs test is unchanged "because the fixtures' `project.root` equal `rootA`". That holds for every fixture except `test_logs_argv_keeps_an_odd_root_verbatim` (`tst_run_store.qml:2699`). Its open project is `"/home/u/o'dd; $x/"` with a trailing slash, and `Runs.withProject` stores the run's `project.root` as `"/home/u/o'dd; $x"`. The logs launch now uses `project.root` (§5), so this test's root changes to `"/home/u/o'dd; $x"`, with no trailing slash. The quote, the semicolon and the `$` stay, so the test still checks that the root is one argument passed verbatim.

---

## File Structure

- Modify `core/stores/RunStore.qml`:
  - the header comment (lines 12-14);
  - `projectSwitched()` and its comment (648-664);
  - a new `runRoot(run)` after `runById` (762);
  - `selectAttempt` (764-772) and `fetchLogs` (787-796), with their comments;
  - the `applyLogs` comment (837-840);
  - `control()` (1083-1116), `launchControl` (1118-1123), `controlDropped` (1173-1181, removed), and the `controlReplied` comment (1183);
  - `refusalOf` (1288-1297);
  - the `logsRunner` comment and guard (1781-1791);
  - the `controlC` comment and properties (1974-1994).
- Modify `docs/architecture.md:90-91`: the logs and run-controls sentences.
- Test `tests/core/stores/tst_run_store.qml`:
  - the block `// ---- requests and logs across a project switch (3.1)` (5425-5464) becomes `// ---- control and logs for a run of any project (3.5)`;
  - the rewrites at 2445, 2471, 2690, 2699, 2751, 2841, 2887 and 3156;
  - `test_a_project_switch_closes_the_dialog_and_clears_the_flash` (3277-3291) is removed.
- Test `tests/ui/tst_shortcuts.qml:316-317, 435-439`: the fixtures gain `project`.
- Test `tests/ui/tst_runs_flow.qml:21-25, 244-254`: the fixture gains `project`; one test is renamed, with a new last assertion.

Line numbers are from the starting commit. Each task's edits shift later lines, so find every edit by the quoted text, not by its number.

## How to run the tests

- **Fast, one QML file** (no pytest). Run this from the worktree root:

  ```bash
  QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|Loc|Actual|Expected|TypeError|ReferenceError"
  ```

  To run single test functions, append `StoresRunStore::<test name>` (one or more) after the `-input <file>` argument. The UI files use the case names `RunsFlow::` (`tests/ui/tst_runs_flow.qml`) and `Shortcuts::` (`tests/ui/tst_shortcuts.qml`). UI files print many `QWARN ... Cannot read property 'width' of null` lines. Those warnings are pre-existing, and `tests/run.sh` filters them out, so ignore them.
- **Full gate:** `timeout 1200 bash tests/run.sh`. It runs pytest (about 2 min, including `tests/architecture`), then every `tst_*.qml`, and exits non-zero on any failure.

Fixture facts the tests rely on, all already in `tst_run_store.qml`:

- Roots: `rootA` = `"/home/u/my proj"` (`alpha`) and `rootB` = `"/home/u/b"` (`beta`).
- `entry(id, status, live, root)` builds a snapshot entry whose `repo_dir` is `root`, else rootA. It has no `project` key.
- `ctlEntry(id, status, live, workflow, requests, accepting)` takes `"milestone"` as its default workflow. `running(id)` and `dead(id)` are `ctlEntry` runs.
- `treeEntry(id, status, root)` is the started capture. Its open attempt is `openCard`/`explore`/`1`, and its `project` is `{id, repo_dir}` with no `root`.
- `make()` builds a bare store. `makeWithRoots(roots)` registers `roots` with no project open, and the snapshot of every root is in flight. `makeWithProject(root)` builds the same store with `root` open.
- `ctlStore(entries)` builds a store with A open whose first snapshot listed `entries`. `opened(status)` is A with `r1` (`treeEntry`) selected and its default attempt's logs in flight.
- Reply helpers: `reply(proc, text, code)`, `argv(proc)` (the command joined with `|`), `allReply(projects)`, `okEntry(root, runs)` and `okReply(entries)`.
- Control and logs replies: `ctlOk(data)`, `ctlFail(type, message)`, `settingsReply(verify, allow)`, `logsReply(stdout)` and `snapshot(store, entries)` (refresh, then an `okReply`).
- Commands: `tc.ctlCmd` = `"python3|/plugin/core/backend/runs/run-control.py|"` and `tc.logsCmd` = `"python3|/plugin/core/backend/runs/runs-logs.py|/home/u/my proj|"`.
- The test file imports `core/domain/runs.js` as `Runs`.
- `HelperRunner`:
  - `run(args)` creates a Process with `launchSeq` and `launchGuard` (the runner's `guard` at launch).
  - A reply is applied only when its `launchSeq` is the newest and its `launchGuard` equals the current `guard`.
  - `guard` defaults to `""`.

---

### Task 1: Controls act on the run's own repository, with no guard

**Files:**
- Modify: `core/stores/RunStore.qml`: `runById` (add `runRoot` after it), `control()`, `launchControl`, `controlDropped` (remove), the `controlReplied` comment, `refusalOf`, and the `controlC` component.
- Test: `tests/core/stores/tst_run_store.qml`: the 3.1 block header plus its control test (5425-5446) become the new 3.5 block, and the existing tests at 2751, 2841, 2887 and 3156 are rewritten.
- Test: `tests/ui/tst_shortcuts.qml:316-317, 435-439`.

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces:
  - `store.runRoot(run)` returns a `string`: `run.project.root` when that is a string, else `""`. A null or non-object run, or a missing or non-object `project`, gives `""`. Task 3 uses it.
  - Each `controlC` runner has `repoDir: string` and `projectRoot: string`, and no `madeFor`.
  - `refusalOf(action, runId)` returns the 6-step sentence order.
  - Test helpers in the new block, used by Tasks 2 and 3:
    - `tc.bRepo` is `"/home/u/b-work"`, and `tc.settingsCmdB` is `"python3|/plugin/core/backend/projects/viewer-state.py|get-run-settings|/home/u/b"`.
    - `bWork(e)` sets `e.repo_dir = tc.bRepo` and returns `e`.
    - `crossStore(open, aRuns, bRuns)` builds a store with A and B registered and `project = open`, whose first snapshot is answered with A listing `aRuns` and B listing `bRuns`.
    - `held(e, root)` turns a snapshot entry into a run as the store holds it. With `root` given it is tagged with `Runs.withProject`; otherwise it has no `project.root`.

- [ ] **Step 1: Replace the 3.1 block header and its control test with the new block's helpers and the control tests**

In `tests/core/stores/tst_run_store.qml`, find this text (it begins at line 5425):

```qml
  // ---- requests and logs across a project switch (3.1)

  // 12 (the control half)
  function test_a_control_request_in_flight_at_a_switch_is_settled_without_an_error() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    store.control("pause", "r1")
    store.control("cancel", "r2")
    var inFlight = store.controlRunners[0].current
    reply(store.controlRunners[1].current, ctlOk({ requested_at: "t2" }), 0)
    compare(store.pending.r2, "cancel", "acknowledged")
    store.stillWaiting = { r1: true, r2: true }
    store.project = rootB
    compare(store.pending.r1, "pause", "in flight until its runner goes idle")
    reply(inFlight, ctlFail("NotAcceptingError", "x"), 0)
    compare(store.pending.r1, undefined, "its dropped reply settles it: the buttons come back")
    compare(store.stillWaiting.r1, undefined)
    compare(store.lastControlError, "", "with no control error")
    compare(store.controlRunners.length, 0)
    compare(store.pending.r2, "cancel", "an acknowledged request stays pending until a snapshot settles it")
    compare(store.stillWaiting.r2, true)
  }

```

and replace it with this. The `// 12 (the logs half)` test that follows stays where it is; Task 3 replaces it.

```qml
  // ---- control and logs for a run of any project (3.5)

  property string bRepo: "/home/u/b-work"
  property string settingsCmdB: "python3|/plugin/core/backend/projects/viewer-state.py|get-run-settings|/home/u/b"

  // `e` with its repo_dir moved to bRepo: a run of rootB whose repository is
  // not the registry root (the store tags it by the entry's root).
  function bWork(e) {
    e.repo_dir = tc.bRepo
    return e
  }

  // rootA and rootB registered, `open` the open project ("" for none), and
  // the first snapshot listed aRuns under A and bRuns under B.
  function crossStore(open, aRuns, bRuns) {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return null
    store.project = open
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, aRuns), okEntry(tc.rootB, bRuns)]), 0)
    return store
  }

  // A run as the store holds it, built from snapshot entry `e`: normalized,
  // with no project root unless `root` is given.
  function held(e, root) {
    var row = {}
    for (var k in e) if (k !== "status") row[k] = e[k]
    var run = Runs.normalizeRun({ row: row, status: e.status })
    return root === undefined ? run : Runs.withProject(run, root, "")
  }

  // 1
  function test_pause_and_cancel_pass_the_runs_repo_dir_with_or_without_a_project() {
    var store = crossStore("", [running("a1")], [bWork(running("b1")), bWork(running("b2"))]); if (!store) return
    compare(store.project, "")
    compare(store.control("pause", "b1"), true, "no project open is not a refusal")
    var pause = store.controlRunners[0].current
    compare(argv(pause), tc.ctlCmd + "pause|b1|/home/u/b-work")
    compare(pause.command.length, 5)
    compare(pause.launchGuard, "", "no guard")
    compare(store.control("cancel", "a1"), true)
    compare(argv(store.controlRunners[1].current), tc.ctlCmd + "cancel|a1|/home/u/my proj")
    store.project = rootA
    compare(store.control("pause", "b2"), true)
    compare(argv(store.controlRunners[2].current), tc.ctlCmd + "pause|b2|/home/u/b-work", "never the open project's root")
  }

  // 2
  function test_a_task_runs_resume_passes_its_repo_dir_with_no_settings_step() {
    var store = crossStore(rootA, [running("a1")], [bWork(ctlEntry("b1", "started", false, "task"))]); if (!store) return
    compare(store.control("resume", "b1"), true)
    var runner = store.controlRunners[0]
    compare(runner.seq, 1, "one launch only")
    compare(argv(runner.current), tc.ctlCmd + "resume|b1|/home/u/b-work")
    compare(runner.current.command.length, 5)
  }

  // 3
  function test_a_milestone_resume_reads_its_own_projects_settings() {
    var store = crossStore(rootA, [running("a1")], [bWork(dead("b1"))]); if (!store) return
    compare(store.control("resume", "b1"), true)
    var runner = store.controlRunners[0]
    compare(argv(runner.current), tc.settingsCmdB, "B's run settings, not A's")
    compare(runner.current.command.length, 4)
    compare(runner.current.launchGuard, "")
    reply(runner.current, settingsReply(["a"], false), 0)
    compare(argv(store.controlRunners[0].current), tc.ctlCmd + "resume|b1|/home/u/b-work|--verify|a")
  }

  // 4
  function test_the_resume_keeps_the_repository_it_was_asked_for() {
    var store = crossStore(rootA, [running("a1")], [bWork(dead("b1"))]); if (!store) return
    store.control("resume", "b1")
    var runner = store.controlRunners[0]
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [])]), 0)
    compare(store.runById("b1"), null, "the run left the snapshot")
    compare(store.pending.b1, "resume", "a request in flight is never settled by a snapshot")
    reply(runner.current, settingsReply(["a"], false), 0)
    compare(argv(store.controlRunners[0].current), tc.ctlCmd + "resume|b1|/home/u/b-work|--verify|a")
    compare(store.pending.b1, "resume")
  }

  // 5
  function test_a_run_with_no_repository_or_no_project_root_is_refused() {
    var store = make(); if (!store) return
    var noRepo = held(running("r1"), rootA)
    noRepo.repo_dir = ""
    store.runs = [noRepo, held(dead("r2")), held(ctlEntry("r3", "started", false, "task"))]
    var actions = ["pause", "resume", "cancel"]
    for (var i = 0; i < actions.length; i++) {
      compare(store.refusalOf(actions[i], "r1"), "This run has no repository", actions[i])
      compare(store.control(actions[i], "r1"), false, actions[i])
    }
    compare(store.refusalOf("resume", "r2"), "This run's project is not known")
    compare(store.control("resume", "r2"), false)
    compare(store.controlRunners.length, 0, "nothing launched")
    compare(Object.keys(store.pending).length, 0)
    compare(store.refusalOf("cancel", "r2"), "", "a cancel needs no project root")
    compare(store.control("cancel", "r2"), true)
    compare(argv(store.controlRunners[0].current), tc.ctlCmd + "cancel|r2|/home/u/my proj")
    compare(store.refusalOf("resume", "r3"), "", "a task run's resume needs no project root")
    compare(store.control("resume", "r3"), true)
    compare(argv(store.controlRunners[1].current), tc.ctlCmd + "resume|r3|/home/u/my proj")
    compare(store.controlRunners[1].seq, 1)
    compare(store.controlRunners.length, 2)
  }

  // 6
  function test_a_request_for_another_projects_run_survives_a_switch_and_its_reply_shows_on_that_run() {
    var store = crossStore(rootA, [running("a1")],
                           [bWork(running("b1")), bWork(running("b2")), bWork(dead("b3"))]); if (!store) return
    compare(store.control("pause", "b1"), true)
    var proc = store.controlRunners[0].current
    store.project = rootB
    store.project = ""
    compare(store.pending.b1, "pause", "a switch settles nothing")
    compare(store.controlRunners.length, 1)
    var seq = store.snapshotRunner.seq
    reply(proc, ctlOk({ requested_at: "t1" }), 0)
    compare(store.pending.b1, "pause", "acknowledged: pending until a snapshot settles it")
    compare(store.snapshotRunner.seq, seq + 1, "and re-snapshots")
    compare(store.controlRunners.length, 0)

    compare(store.control("pause", "b2"), true)
    var proc2 = store.controlRunners[0].current
    store.project = rootA
    reply(proc2, ctlFail("NotRunningError", "not running"), 0)
    compare(store.pending.b2, undefined)
    compare(store.lastControlError, "The run is not running")
    compare(store.lastControlErrorRunId, "b2", "the error shows on that run")

    compare(store.control("resume", "b3"), true)
    var runner = store.controlRunners[0]
    store.project = rootB
    reply(runner.current, settingsReply(["a"], false), 0)
    compare(argv(store.controlRunners[0].current), tc.ctlCmd + "resume|b3|/home/u/b-work|--verify|a",
            "the settings reply after a switch launches run-control")
  }

  // Review Focus 5.
  function test_a_request_made_with_no_project_open_is_answered_after_one_opens() {
    var store = crossStore("", [running("a1")], [bWork(running("b1"))]); if (!store) return
    compare(store.control("pause", "b1"), true)
    var proc = store.controlRunners[0].current
    store.project = rootA
    var seq = store.snapshotRunner.seq
    reply(proc, ctlFail("NotRunningError", "not running"), 0)
    compare(store.pending.b1, undefined)
    compare(store.lastControlError, "The run is not running")
    compare(store.lastControlErrorRunId, "b1")
    compare(store.snapshotRunner.seq, seq + 1)
  }

  // Review Focus 2.
  function test_open_cancel_on_a_run_with_no_repository_flashes_why() {
    var store = make(); if (!store) return
    var run = held(running("r1"), rootA)
    run.repo_dir = ""
    store.runs = [run]
    compare(store.openCancel("r1"), false)
    compare(store.cancelOpen, false)
    compare(store.flashText, "This run has no repository")
    compare(store.controlRunners.length, 0)
  }

```

- [ ] **Step 2: Rewrite the four existing control tests for the new contract**

In `tests/core/stores/tst_run_store.qml`:

(a) In `test_pause_and_cancel_launch_the_exact_argv` (line 2751), replace

```qml
    compare(pause.running, true)
    compare(pause.launchGuard, "/home/u/my proj")
```

with

```qml
    compare(pause.running, true)
    compare(pause.launchGuard, "", "no guard")
```

(b) In `test_control_refusals_launch_nothing` (line 2841), replace

```qml
    compare(bare.control("pause", "r1"), false, "no project")
```

with

```qml
    compare(bare.control("pause", "r1"), false, "a run not in the snapshot")
```

(c) In `test_a_finished_request_leaves_control_runners` (line 2887), replace

```qml
    compare(other.controlRunners.length, 0, "a reply dropped by the guard still removes its runner")
    compare(other.snapshotRunner.seq, seq, "a dropped reply does not re-snapshot")
```

with

```qml
    compare(other.controlRunners.length, 0, "a reply after a switch is applied and removes its runner")
    compare(other.snapshotRunner.seq, seq + 1, "and re-snapshots")
```

(d) In `test_refusal_of_says_why_a_control_would_not_start` (line 3156), replace

```qml
    compare(bare.refusalOf("pause", "r1"), "This run is no longer in the snapshot", "no project")
```

with

```qml
    compare(bare.refusalOf("pause", "r1"), "This run is no longer in the snapshot", "not in the snapshot")
```

- [ ] **Step 3: Run the store tests to verify the new ones fail**

Run:

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)"
```

Expected: exactly these FAIL, and nothing else:

- `test_pause_and_cancel_launch_the_exact_argv` (no guard)
- `test_a_finished_request_leaves_control_runners` (and re-snapshots)
- `test_pause_and_cancel_pass_the_runs_repo_dir_with_or_without_a_project` (no project open is not a refusal)
- `test_a_task_runs_resume_passes_its_repo_dir_with_no_settings_step`
- `test_a_milestone_resume_reads_its_own_projects_settings` (B's run settings, not A's)
- `test_the_resume_keeps_the_repository_it_was_asked_for`
- `test_a_run_with_no_repository_or_no_project_root_is_refused` (pause)
- `test_a_request_for_another_projects_run_survives_a_switch_and_its_reply_shows_on_that_run`
- `test_a_request_made_with_no_project_open_is_answered_after_one_opens`
- `test_open_cancel_on_a_run_with_no_repository_flashes_why`

- [ ] **Step 4: Add `runRoot` after `runById`**

In `core/stores/RunStore.qml`, find

```qml
  // The run with this id in the snapshot, or null.
  function runById(id) {
    var list = store.runs
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id) return list[i]
    }
    return null
  }
```

and add right after it (one blank line between):

```qml

  // The run's project root when it is a non-empty string, else "".
  function runRoot(run) {
    var p = run !== null && typeof run === "object" ? run.project : null
    if (p === null || typeof p !== "object" || typeof p.root !== "string") return ""
    return p.root
  }
```

- [ ] **Step 5: Make `control()` start from `refusalOf` and capture the run's repository and root**

In `core/stores/RunStore.qml`, replace

```qml
  // Starts a pause, resume or cancel of one run of this project and returns
  // whether it started. Refused: no project, an unknown action, a run that is
  // not in the snapshot, an action Runs.controls says is disabled, or a run
  // that already has a request pending. Confirming a cancel is the caller's job.
  function control(action, runId) {
    if (store.project === "") return false
    if (action !== "pause" && action !== "resume" && action !== "cancel") return false
    if (typeof runId !== "string" || runId === "") return false
    var run = store.runById(runId)
    if (run === null) return false
    if (!Runs.controls(run)[action].enabled) return false
    if (store.hasKey(store.pending, runId)) return false
    store.dismissControlError()
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
    store.dismissControlError()
```

Then, in the same function, replace

```qml
    var runner = controlC.createObject(store, { runId: runId, action: action,
                                                token: controlState.nextToken, madeFor: store.project })
    controlState.runners = controlState.runners.concat([runner])
    if (action === "resume" && run.workflow !== "task") {
      // A milestone resume reuses the project's stored verify set: read it first.
      runner.settingsStep = true
      runner.script = store.backendDir + "projects/viewer-state.py"
      runner.run(["get-run-settings", store.project])
```

with

```qml
    var runner = controlC.createObject(store, { runId: runId, action: action, token: controlState.nextToken,
                                                repoDir: run.repo_dir, projectRoot: store.runRoot(run) })
    controlState.runners = controlState.runners.concat([runner])
    if (action === "resume" && run.workflow !== "task") {
      // A milestone resume reuses its project's stored verify set: read it first.
      runner.settingsStep = true
      runner.script = store.backendDir + "projects/viewer-state.py"
      runner.run(["get-run-settings", runner.projectRoot])
```

- [ ] **Step 6: `launchControl` passes the captured `repoDir`**

Replace

```qml
  // The request's run-control.py launch on its own runner: ACTION RUN REPO,
  // then `extra` (a resume's verify arguments).
  function launchControl(runner, extra) {
    runner.script = store.backendDir + "runs/run-control.py"
    runner.run([runner.action, runner.runId, store.project].concat(extra))
  }
```

with

```qml
  // The request's run-control.py launch on its own runner: ACTION RUN REPO,
  // REPO the repo_dir the request was made with, then `extra` (a resume's
  // verify arguments).
  function launchControl(runner, extra) {
    runner.script = store.backendDir + "runs/run-control.py"
    runner.run([runner.action, runner.runId, runner.repoDir].concat(extra))
  }
```

- [ ] **Step 7: Remove `controlDropped` and fix the `controlReplied` comment**

Replace

```qml
  // A runner whose reply its guard dropped (the open project changed while it
  // was in flight): a request still pending for its run is settled -- its
  // buttons come back, with no control error -- and the runner goes. A
  // request am already acknowledged has no runner left and stays pending
  // until a snapshot settles it.
  function controlDropped(runner) {
    if (store.requestOf(runner) !== null) store.settle(runner.runId)
    store.dropRunner(runner)
  }

  // One run-control.py reply, for the project the request was made in. ok:true
```

with

```qml
  // One run-control.py reply, whatever project is open. ok:true
```

Leave the rest of that comment and the bodies of `controlReplied` and `resumeWithSettings` as they are.

- [ ] **Step 8: `refusalOf` gets the two new sentences and stops consulting `project`**

Replace

```qml
  // "" when control(action, runId) would start a request; otherwise why not:
  // a run that is not in the snapshot (or no project), then a request already
  // pending for it, then the reason Runs.controls gives. Changes nothing.
  function refusalOf(action, runId) {
    if (action !== "pause" && action !== "resume" && action !== "cancel") return "Unknown control"
    var run = store.project === "" || typeof runId !== "string" || runId === "" ? null : store.runById(runId)
    if (run === null) return "This run is no longer in the snapshot"
    if (store.hasKey(store.pending, runId)) return "A request for this run is pending"
```

with

```qml
  // "" when control(action, runId) would start a request; otherwise why not:
  // a run that is not in the snapshot, then a run with no repo_dir, then a
  // resume (not of a task run) of a run with no project root, then a request
  // already pending for it, then the reason Runs.controls gives. Changes nothing.
  function refusalOf(action, runId) {
    if (action !== "pause" && action !== "resume" && action !== "cancel") return "Unknown control"
    var run = typeof runId !== "string" || runId === "" ? null : store.runById(runId)
    if (run === null) return "This run is no longer in the snapshot"
    if (typeof run.repo_dir !== "string" || run.repo_dir === "") return "This run has no repository"
    if (action === "resume" && run.workflow !== "task" && store.runRoot(run) === "") return "This run's project is not known"
    if (store.hasKey(store.pending, runId)) return "A request for this run is pending"
```

The last line (`return Runs.controls(run)[action].reason`) stays.

- [ ] **Step 9: The control runner loses its guard, `madeFor` and `onBusyChanged`, and gains `repoDir` / `projectRoot`**

Replace

```qml
  // One HelperRunner per control request, so requests for different runs never
  // stop each other. Guarded by the project: a reply for a project the user
  // has left is dropped, and when its process exits (the runner clears `busy`
  // but emits no `finished`) controlDropped settles its request and the
  // runner goes. A milestone resume uses its runner twice: viewer-state.py,
  // then run-control.py.
```

with

```qml
  // One HelperRunner per control request, so requests for different runs never
  // stop each other. No guard: a reply is applied whatever project is open.
  // A milestone resume uses its runner twice: viewer-state.py, then
  // run-control.py.
```

and, inside `Component { id: controlC ... }`, replace

```qml
      property int token: 0
      property string madeFor: ""         // the project the request was made in
      property bool settingsStep: false   // reading the run settings; run-control comes next
      guard: store.project
      onFinished: function(stdout, exitCode) { store.controlReplied(cr, stdout, exitCode) }
      onBusyChanged: if (!cr.busy && cr.guard !== cr.madeFor) store.controlDropped(cr)
```

with

```qml
      property int token: 0
      property string repoDir: ""         // the run's repo_dir when the request was made
      property string projectRoot: ""     // the run's project.root then; "" when it had none
      property bool settingsStep: false   // reading the run settings; run-control comes next
      onFinished: function(stdout, exitCode) { store.controlReplied(cr, stdout, exitCode) }
```

- [ ] **Step 10: Run the store tests to verify they pass**

Run:

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|Loc|TypeError|ReferenceError"
```

Expected: `Totals: <n> passed, 0 failed`. `test_a_project_switch_closes_the_dialog_and_clears_the_flash` and `test_a_logs_fetch_in_flight_at_a_switch_ends_and_keeps_the_text` still pass at this point, because the switch and the logs have not changed yet.

- [ ] **Step 11: Give the shortcut fixtures a project so a milestone run's `r` still reaches `Runs.controls`**

Without a `project.root`, a non-`task` run's resume is now refused with `This run's project is not known`. That breaks `test_c_r_and_p_act_on_the_cursor_run_while_the_search_is_empty` and `test_on_run_detail_the_keys_act_on_the_open_run_and_nowhere_else`. In `tests/ui/tst_shortcuts.qml`, replace (line 316)

```qml
    s.app.runs.runs = [{ id: "run-0000000000a1", repo_dir: "/home/u/a", milestone_id: "alpha", status: "escalated",
                         started_at: "", lease: null, rows: [], tree: { stories: [], subtasks: [] } }]
```

with

```qml
    s.app.runs.runs = [{ id: "run-0000000000a1", repo_dir: "/home/u/a", milestone_id: "alpha", status: "escalated",
                         started_at: "", lease: null, rows: [], tree: { stories: [], subtasks: [] },
                         project: { root: "/home/u/a", name: "alpha" } }]
```

and replace (`normRun`, line 435)

```qml
    return { id: id, repo_dir: "/home/u/a", milestone_id: "m", status: status, started_at: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: [], tree: { stories: [], subtasks: [] } }
```

with

```qml
    return { id: id, repo_dir: "/home/u/a", milestone_id: "m", status: status, started_at: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: [], tree: { stories: [], subtasks: [] }, project: { root: "/home/u/a", name: "alpha" } }
```

Run:

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_shortcuts.qml 2>&1 | grep -E "^(FAIL|Totals)|Loc"
```

Expected: `0 failed`. `test_without_a_project_the_run_keys_are_left_alone` passes unchanged, because `ui/Shortcuts.qml:72` still gates the keys.

- [ ] **Step 12: Run the full gate**

Run: `timeout 1200 bash tests/run.sh; echo exit $?`
Expected: `exit 0`, with no `FAIL` lines.

- [ ] **Step 13: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml tests/ui/tst_shortcuts.qml
git commit -m "feat(run-store): controls act on the run's own repo_dir and project root, with no guard"
```

---

### Task 2: A project switch keeps the dialog, the flash, the control error and the requests

**Files:**
- Modify: `core/stores/RunStore.qml`: `projectSwitched()` and its comment.
- Test: `tests/core/stores/tst_run_store.qml`: remove `test_a_project_switch_closes_the_dialog_and_clears_the_flash` (originally 3277-3291), and add test 7 and Review Focus 1 to the 3.5 block.

**Interfaces:**
- Consumes: from Task 1, `crossStore`, `bWork`, `ctlStore`, `running`, `ctlFail` and `argv`, plus the guard-free control runners.
- Produces: after this task, `projectSwitched()` touches only `runSettings`, `resetDispatch()` and `runSettingsRunner`.

- [ ] **Step 1: Remove the old switch test**

In `tests/core/stores/tst_run_store.qml`, delete this whole test, including its `// 6` comment and the blank line after it:

```qml
  // 6
  function test_a_project_switch_closes_the_dialog_and_clears_the_flash() {
    var store = ctlStore([running("r1")]); if (!store) return
    store.openCancel("r1")
    store.cancelText = "can"
    store.cancelError = "x"
    store.flash("The run has finished")
    store.project = rootB
    compare(store.cancelOpen, false)
    compare(store.cancelRunId, "")
    compare(store.cancelText, "")
    compare(store.cancelError, "")
    compare(store.flashText, "")
    compare(store.flashTimer.running, false)
  }

```

After the deletion, `test_a_run_that_changed_under_the_open_dialog_refuses_the_confirm`'s closing `}` is followed by a blank line and then `  // ---- alerts: the toasts (S2 4.4)`.

- [ ] **Step 2: Add test 7 and Review Focus 1 to the 3.5 block**

In `tests/core/stores/tst_run_store.qml`, insert the following right before the line `  // 12 (the logs half)`. That line is still in the 3.5 block, after `test_open_cancel_on_a_run_with_no_repository_flashes_why`.

```qml
  // 7
  function test_a_project_switch_keeps_the_dialog_the_flash_the_control_error_and_the_requests() {
    var store = ctlStore([running("r1"), running("r2"), running("r3")]); if (!store) return
    store.control("pause", "r3")
    store.control("pause", "r2")
    reply(store.controlRunners[1].current, ctlFail("NotRunningError", "not running"), 0)
    compare(store.lastControlErrorRunId, "r2")
    store.checkWaiting(Date.now() + 30000)
    compare(store.stillWaiting.r3, true)
    store.openCancel("r1")
    store.cancelText = "can"
    store.cancelError = "x"
    store.flash("The run has finished")
    store.project = rootB
    compare(store.cancelOpen, true)
    compare(store.cancelRunId, "r1")
    compare(store.cancelText, "can")
    compare(store.cancelError, "x")
    compare(store.flashText, "The run has finished")
    compare(store.flashTimer.running, true)
    compare(store.lastControlError, "The run is not running")
    compare(store.lastControlErrorRunId, "r2")
    compare(store.pending.r3, "pause")
    compare(store.stillWaiting.r3, true)
    compare(store.controlRunners.length, 1)
    compare(store.controlRunners[0].runId, "r3")
  }

  // Review Focus 1.
  function test_a_cancel_dialog_for_another_projects_run_survives_closing_the_project_and_confirms() {
    var store = crossStore(rootA, [running("a1")], [bWork(running("b1"))]); if (!store) return
    compare(store.openCancel("b1"), true)
    store.project = ""
    compare(store.cancelRunId, "b1", "the dialog is kept")
    store.cancelText = "cancel"
    compare(store.confirmCancel(), true)
    compare(argv(store.controlRunners[0].current), tc.ctlCmd + "cancel|b1|/home/u/b-work")
    compare(store.cancelOpen, false)
  }

```

- [ ] **Step 3: Run the two tests to verify they fail**

Run:

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_a_project_switch_keeps_the_dialog_the_flash_the_control_error_and_the_requests StoresRunStore::test_a_cancel_dialog_for_another_projects_run_survives_closing_the_project_and_confirms 2>&1 | grep -E "^(FAIL|Totals)"
```

Expected: both FAIL. The first fails on `compare(store.cancelOpen, true)`, the second on "the dialog is kept".

- [ ] **Step 4: `projectSwitched()` stops resetting the dialog, the flash and the control error**

In `core/stores/RunStore.qml`, replace

```qml
  // Another project was opened, or none. The run list, the selection, the
  // logs, the watch, the coverage, the requests, the alerts, the toasts and
  // the notify switch belong to every registered project and stay, and no
  // snapshot is launched. Reset: the run settings (loaded for the new project
  // on runSettingsRunner), the dispatch, the cancel dialog, the control error
  // and the footer flash.
  function projectSwitched() {
    store.runSettings = {}
    // The dispatch is the old project's, even mid-start: a start already
    // launched still runs, and its reply is no longer this dispatch's.
    store.resetDispatch()
    store.dismissControlError()
    store.closeCancel()
    store.flash("")
    runSettingsRunner.guard = store.project
```

with

```qml
  // Another project was opened, or none. The run list, the selection, the
  // logs, the watch, the coverage, the requests (pending, stillWaiting,
  // controlRunners), the control error, the cancel dialog, the footer flash,
  // the alerts, the toasts and the notify switch belong to every registered
  // project and stay, and no snapshot is launched. Reset: the run settings
  // (loaded for the new project on runSettingsRunner) and the dispatch.
  function projectSwitched() {
    store.runSettings = {}
    // The dispatch is the old project's, even mid-start: a start already
    // launched still runs, and its reply is no longer this dispatch's.
    store.resetDispatch()
    runSettingsRunner.guard = store.project
```

- [ ] **Step 5: Run the store tests to verify they pass**

Run:

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|Loc|TypeError|ReferenceError"
```

Expected: `0 failed`. `test_a_reply_after_returning_to_the_project_is_applied` and `test_a_project_switch_leaves_the_run_list_and_the_live_state_alone` pass unchanged.

- [ ] **Step 6: Run the full gate**

Run: `timeout 1200 bash tests/run.sh; echo exit $?`
Expected: `exit 0`.

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): a project switch keeps the cancel dialog, the flash, the control error and pending requests"
```

---

### Task 3: Logs of a run of any project, read with the run's own root and no guard

**Files:**
- Modify: `core/stores/RunStore.qml`: the header comment (lines 12-14), `selectAttempt`, `fetchLogs`, the `applyLogs` comment, and the `logsRunner` comment and guard.
- Test: `tests/core/stores/tst_run_store.qml`: rewrite the tests at 2445, 2471, 2690 and 2699, and replace `test_a_logs_fetch_in_flight_at_a_switch_ends_and_keeps_the_text` (the old `// 12 (the logs half)`) with tests 8, 9, 10 and Review Focus 3.
- Test: `tests/ui/tst_runs_flow.qml:21-25, 244-254`.

**Interfaces:**
- Consumes: from Task 1, `store.runRoot(run)`, and the test helpers `crossStore`, `held`, `treeEntry`, `logsReply`, `opened`, `snapshot` and `argv`.
- Produces: `fetchLogs()` launches `[runRoot(selected run), runId, card, phase, String(attempt)]` and launches nothing when that root is `""`. `logsRunner.guard` is `""`.

- [ ] **Step 1: Replace the old logs-across-a-switch test with tests 8, 9, 10 and Review Focus 3**

In `tests/core/stores/tst_run_store.qml`, find

```qml
  // 12 (the logs half)
  function test_a_logs_fetch_in_flight_at_a_switch_ends_and_keeps_the_text() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("kept\n"), 0)
    var fetched = store.logsFetchedMs
    store.refreshLogs()
    var pending = store.logsRunner.current
    compare(store.logsLoading, true)
    store.project = rootB
    compare(store.logsLoading, true, "still in flight")
    reply(pending, logsReply("late\n"), 0)
    compare(store.logsLoading, false, "the dropped reply ends the fetch")
    compare(store.logsText, "kept", "the shown text stays")
    compare(store.logsError, "")
    compare(store.logsFetchedMs, fetched)
    compare(store.selectedRunId, "r1")
    verify(store.selectedAttempt !== null)
  }
```

and replace it with

```qml
  // 8
  function test_logs_of_another_projects_run_load_with_no_project_open() {
    var store = crossStore("", [], [treeEntry("rb", "started", rootB)]); if (!store) return
    store.selectedRunId = "rb"
    var proc = store.logsRunner.current
    verify(proc, "the default attempt's logs were asked for")
    compare(argv(proc), "python3|/plugin/core/backend/runs/runs-logs.py|/home/u/b|rb|" + tc.openCard + "|explore|1")
    compare(proc.launchGuard, "")
    reply(proc, logsReply("x\n"), 0)
    compare(store.logsText, "x")
  }

  // 9
  function test_a_logs_reply_after_a_project_switch_lands() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("kept\n"), 0)
    store.refreshLogs()
    var pending = store.logsRunner.current
    compare(store.logsLoading, true)
    store.project = rootB
    compare(store.logsLoading, true, "still in flight")
    reply(pending, logsReply("late\n"), 0)
    compare(store.logsText, "late", "the reply is applied")
    compare(store.logsLoading, false)
    compare(store.logsError, "")
    compare(store.selectedRunId, "r1")
  }

  // 10
  function test_no_logs_for_a_selected_run_without_a_project_root() {
    var store = make(); if (!store) return
    store.runs = [held(treeEntry("r1", "started"))]
    compare(store.runs[0].project.root, undefined, "normalizeRun's project has no root")
    store.selectedRunId = "r1"
    verify(store.selectedAttempt !== null, "the default attempt is selected")
    verify(!store.logsRunner.current, "no logs launch")
    compare(store.logsLoading, false)
  }

  // Review Focus 3.
  function test_a_selected_run_that_leaves_the_snapshot_launches_no_logs() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("kept\n"), 0)
    var seq = store.logsRunner.seq
    snapshot(store, [])
    compare(store.runById("r1"), null)
    compare(store.logsRunner.seq, seq, "no launch for a run not in the snapshot")
    compare(store.logsLoading, false)
    compare(store.logsText, "kept")
  }
```

- [ ] **Step 2: Rewrite the four existing logs tests for the new contract**

(a) In `test_selecting_a_run_fetches_its_default_attempt` (line 2445), replace

```qml
    compare(proc.launchGuard, "/home/u/my proj", "guarded by the project")
```

with

```qml
    compare(proc.launchGuard, "", "no guard")
```

(b) Replace

```qml
  function test_no_logs_launch_without_project_run_or_selection() {
    var bare = make(); if (!bare) return
    bare.selectAttempt(tc.doneCard, "spec", 1)
    verify(!bare.logsRunner.current, "no project")
```

with

```qml
  function test_no_logs_launch_without_a_run_or_a_selection() {
    var bare = make(); if (!bare) return
    bare.selectAttempt(tc.doneCard, "spec", 1)
    verify(!bare.logsRunner.current, "no run selected")
```

The rest of that test stays.

(c) Replace

```qml
  // The logs launch: python3, the script, then the project root and the
  // attempt, five arguments; the root is the open project's, one element.
  function test_logs_argv_leads_with_the_current_project_root() {
```

with

```qml
  // The logs launch: python3, the script, then the project root and the
  // attempt, five arguments; the root is the selected run's project.root, one
  // element.
  function test_logs_argv_leads_with_the_runs_project_root() {
```

The body, and its argv, stay.

(d) Replace

```qml
  // The root reaches the runner byte-for-byte.
  function test_logs_argv_keeps_an_odd_root_verbatim() {
    var odd = "/home/u/o'dd; $x/"
```

with

```qml
  // The run's project.root reaches the runner byte-for-byte.
  function test_logs_argv_keeps_an_odd_root_verbatim() {
    var odd = "/home/u/o'dd; $x"
```

The body stays. The trailing `/` goes because `Runs.withProject` trims it from `project.root` (see "Deviation" at the top).

- [ ] **Step 3: Run the store tests to verify the new ones fail**

Run:

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)"
```

Expected: exactly these FAIL:

- `test_selecting_a_run_fetches_its_default_attempt` (no guard)
- `test_logs_of_another_projects_run_load_with_no_project_open` ('the default attempt's logs were asked for' returned FALSE)
- `test_a_logs_reply_after_a_project_switch_lands` (the reply is applied)
- `test_no_logs_for_a_selected_run_without_a_project_root` ('the default attempt is selected' returned FALSE)
- `test_a_selected_run_that_leaves_the_snapshot_launches_no_logs` (no launch for a run not in the snapshot)

`test_logs_argv_keeps_an_odd_root_verbatim` passes both before and after this task, because the open project and the run's root are the same slash-free string.

- [ ] **Step 4: `selectAttempt` no longer needs a project**

In `core/stores/RunStore.qml`, replace

```qml
  // the one shown starts from an empty pane -- its predecessor's text is never
  // shown under its heading. Nothing happens without a project, a selected run
  // or a real attempt (a non-empty card and phase, a number above 0).
  function selectAttempt(cardId, phase, attempt) {
    if (store.project === "" || store.selectedRunId === "") return
```

with

```qml
  // the one shown starts from an empty pane -- its predecessor's text is never
  // shown under its heading. Nothing happens without a selected run or a real
  // attempt (a non-empty card and phase, a number above 0).
  function selectAttempt(cardId, phase, attempt) {
    if (store.selectedRunId === "") return
```

- [ ] **Step 5: `fetchLogs` launches with the selected run's `project.root`**

Replace

```qml
  // One runs-logs.py launch for the current project and selection, the
  // project root first, remembering the status it was launched for (a
  // snapshot that changes it fetches again).
  function fetchLogs() {
    var sel = store.selectedAttempt
    if (store.project === "" || store.selectedRunId === "" || !sel) return
    store.logsStatus = Runs.attemptStatus(store.runById(store.selectedRunId), sel.card_id, sel.phase, sel.attempt)
    store.logsLoading = true
    logsRunner.run([store.project, store.selectedRunId, sel.card_id, sel.phase, String(sel.attempt)])
  }
```

with

```qml
  // One runs-logs.py launch for the selected attempt, the selected run's
  // project root first, remembering the status it was launched for (a
  // snapshot that changes it fetches again). Nothing launches for a run not
  // in the snapshot or one with no project root.
  function fetchLogs() {
    var sel = store.selectedAttempt
    if (store.selectedRunId === "" || !sel) return
    var run = store.runById(store.selectedRunId)
    var root = store.runRoot(run)
    if (root === "") return
    store.logsStatus = Runs.attemptStatus(run, sel.card_id, sel.phase, sel.attempt)
    store.logsLoading = true
    logsRunner.run([root, store.selectedRunId, sel.card_id, sel.phase, String(sel.attempt)])
  }
```

- [ ] **Step 6: The `applyLogs` comment and `logsRunner` stop mentioning a guard, and the runner loses it**

Replace

```qml
  // lastError: those belong to the snapshot. A reply for a project the user
  // has left, or for an older fetch, never gets here (the runner's guards).
```

with

```qml
  // lastError: those belong to the snapshot. A reply for an older fetch never
  // gets here (the runner's latest-wins).
```

and replace

```qml
  // The attempt-logs helper. Guarded by the project, so a reply for a project
  // the user has left is dropped; a newer fetch (another attempt, a Refresh)
  // wins over an older one. Whenever the runner goes idle, dropped reply or
  // not, no fetch is loading; the shown text, error and time stay.
  HelperRunner {
    id: logsRunner
    script: store.backendDir + "runs/runs-logs.py"
    guard: store.project
```

with

```qml
  // The attempt-logs helper. No guard: a reply is applied whatever project is
  // open. A newer fetch (another attempt, a Refresh) wins over an older one.
  // Whenever the runner goes idle, no fetch is loading.
  HelperRunner {
    id: logsRunner
    script: store.backendDir + "runs/runs-logs.py"
```

- [ ] **Step 7: The store header comment no longer gives `project` the controls and the logs**

Replace (lines 12-14)

```qml
// switch leaves the run list alone: `project`, the open project, decides only
// the run settings, the dispatch, the run controls and the attempt logs'
// root. Plus the selected run, the attempt the Run detail pane shows and that
```

with

```qml
// switch leaves the run list alone: `project`, the open project, decides only
// the run settings and the dispatch; the run controls and the attempt logs
// act on each run's own repo_dir and project root. Plus the selected run, the
// attempt the Run detail pane shows and that
```

- [ ] **Step 8: Run the store tests to verify they pass**

Run:

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|Loc|TypeError|ReferenceError"
```

Expected: `0 failed`.

- [ ] **Step 9: Give the runs-flow fixture a project, then rename the switch test and make it assert that the late logs land (test 11)**

Run the UI file first:

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_runs_flow.qml 2>&1 | grep -E "^(FAIL|Totals)|Loc"
```

Expected: 3 FAIL. They are `test_opening_a_run_shows_it_and_fetches_its_default_attempt`, `test_escape_returns_to_runs_and_clears_the_logs` and `test_a_project_switch_on_the_run_view_leaves_it_and_drops_the_late_logs`. The fixture runs have no `project.root`, so no logs launch.

In `tests/ui/tst_runs_flow.qml`, replace (`run()`, line 21)

```qml
    return { id: id, repo_dir: "/home/u/a", milestone_id: milestone, status: status, started_at: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: [], tree: { stories: [], subtasks: [] } }
```

with

```qml
    return { id: id, repo_dir: "/home/u/a", milestone_id: milestone, status: status, started_at: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: [], tree: { stories: [], subtasks: [] }, project: { root: "/home/u/a", name: "alpha" } }
```

and replace

```qml
  function test_a_project_switch_on_the_run_view_leaves_it_and_drops_the_late_logs() {
```

with

```qml
  function test_a_project_switch_on_the_run_view_leaves_it_and_the_late_logs_land() {
```

and, in that test, replace

```qml
    compare(p.app.runs.logsText, "", "the old project's late reply changes nothing")
```

with

```qml
    compare(p.app.runs.logsText, "late", "the late reply is applied")
    compare(p.app.runs.logsLoading, false)
```

Run the UI file again (same command). Expected: `0 failed`.

- [ ] **Step 10: Run the full gate**

Run: `timeout 1200 bash tests/run.sh; echo exit $?`
Expected: `exit 0`. This includes `tst_runs_real_data.qml`, whose runs come through snapshots and so already carry `project.root`.

- [ ] **Step 11: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml tests/ui/tst_runs_flow.qml
git commit -m "feat(run-store): attempt logs read the selected run's project root with no guard"
```

---

### Task 4: `docs/architecture.md` states the new contract

**Files:**
- Modify: `docs/architecture.md:90-91`

**Interfaces:**
- Consumes: the behaviour of Tasks 1-3.
- Produces: nothing for code.

The architecture file has no test. This task's check is a `grep` for the old sentences, then the full gate. Each edit below is one exact substring replacement inside the very long lines 90 and 91. Use the Edit tool with these strings.

- [ ] **Step 1: Confirm the old sentences are there**

Run:

```bash
grep -c "guarded by the project like the snapshot\|it refuses without a project, for an action\|guarded by the project), so requests\|a project switch empties it and the control error\|a project switch closes the dialog and clears the flash" docs/architecture.md
```

Expected: `2` (both lines 90 and 91 match).

- [ ] **Step 2: Edit the logs sentence (line 90)**

Replace

```
(`runs-logs.py` with the project root first, then the run, card, phase and attempt; guarded by the project like the snapshot)
```

with

```
(`runs-logs.py` with the selected run's project root first, then the run, card, phase and attempt; no guard, so a reply is applied whatever project is open; nothing launches for a selected run with no project root)
```

- [ ] **Step 3: Edit the run-controls sentences (line 91), six replacements**

1. Replace
   ```
   it refuses without a project, for an action `Runs.controls(run)` disables, and for a run that already has a request in `pending`.
   ```
   with
   ```
   it refuses a run with no `repo_dir`, a resume (not of a `task` run) of a run with no `project.root`, an action `Runs.controls(run)` disables, and a run that already has a request in `pending`; no project open is not a refusal.
   ```
2. Replace
   ```
   (`controlRunners`, guarded by the project), so requests for different runs never stop each other and a reply for a project the user has left is dropped.
   ```
   with
   ```
   (`controlRunners`, no guard; a reply is applied whatever project is open), so requests for different runs never stop each other.
   ```
3. Replace
   ```
   run `run-control.py ACTION RUN REPO`; any other resume first reads `viewer-state.py get-run-settings` and passes
   ```
   with
   ```
   run `run-control.py ACTION RUN REPO`, `REPO` the run's `repo_dir` as the request was made; any other resume first reads `viewer-state.py get-run-settings` of the run's `project.root` and passes
   ```
4. Replace
   ```
   Closing the panel keeps `pending`; a project switch empties it and the control error.
   ```
   with
   ```
   Closing the panel keeps `pending`; a project switch keeps it and the control error.
   ```
5. Replace
   ```
   (`This run is no longer in the snapshot`, then `A request for this run is pending`, then
   ```
   with
   ```
   (`This run is no longer in the snapshot`, then `This run has no repository`, then `This run's project is not known` (a resume, not of a `task` run), then `A request for this run is pending`, then
   ```
6. Replace
   ```
   which `flashTimer` clears 3 s later; a project switch closes the dialog and clears the flash.
   ```
   with
   ```
   which `flashTimer` clears 3 s later; a project switch keeps the dialog and the flash.
   ```

- [ ] **Step 4: Confirm the old sentences are gone**

Run the Step 1 `grep -c` again. Expected: `0`.

- [ ] **Step 5: Run the full gate**

Run: `timeout 1200 bash tests/run.sh; echo exit $?`
Expected: `exit 0`.

- [ ] **Step 6: Commit**

```bash
git add docs/architecture.md
git commit -m "docs: RunStore controls and logs act on the run's own repository with no project guard"
```

---

## Self-review against the spec

- **§1 `control(action, runId)`**:
  - Starting from `refusalOf` with no project consult: Task 1 Step 5.
  - The runner's `runId`, `action`, `token`, `repoDir` and `projectRoot`, guard `""`, no `madeFor` and no `onBusyChanged`: Task 1 Steps 5 and 9.
  - The pause, cancel and task-resume argv: Task 1 Step 6. The milestone settings read with `runner.projectRoot`: Step 5.
  - Tests 1, 2, 3 and 5, and the rewritten `test_pause_and_cancel_launch_the_exact_argv`.
- **§2 replies and a switch**: `controlReplied` and `resumeWithSettings` are unchanged (only a comment changes). The guard removal is Task 1 Step 9, and `controlDropped` is removed in Step 7. Tests 4 and 6, Review Focus 5, and the rewritten `test_a_finished_request_leaves_control_runners`.
- **§3 `refusalOf` order**: Task 1 Step 8. Test 5, Review Focus 2, and the rewritten bare-store labels at 2841 and 3156. `openCancel` and `confirmCancel` are unchanged and covered by Review Focus 1 and 2.
- **§4 `projectSwitched()`**: Task 2 Step 4, including the header comment that lists what is kept. Test 7 replaces `test_a_project_switch_closes_the_dialog_and_clears_the_flash`.
- **§5 logs**:
  - `selectAttempt` and `fetchLogs`: Task 3 Steps 4 and 5.
  - The `logsRunner` guard and the `applyLogs` / `logsRunner` comments: Step 6.
  - `openDefaultAttempt` is unchanged.
  - Tests 8, 9 and 10, Review Focus 3, and the rewrites at 2445, 2471, 2690 and 2699.
- **§6 UI fixtures and test 11**: `tst_shortcuts.qml` in Task 1 Step 11, where it first breaks. `tst_runs_flow.qml` in Task 3 Step 9. No UI production file changes.
- **§7 docs**: Task 4.
- **Inherited constraints**: dispatch guards untouched (no task edits `dispatch*Runner`, `dispatchStartC` or `runSettingsRunner`). The layering stays: no new import. `tests/architecture` runs in each task's full gate.
- **Error paths table**, every row:

  | row | covered by |
  |---|---|
  | pause with project `""` | test 1 |
  | B's run paused with A open | test 1 |
  | milestone resume of B with A open | test 3 |
  | the run leaves the snapshot mid-settings | test 4 |
  | `repo_dir` `""` | test 5 |
  | milestone run with no `project` | test 5 |
  | `task` run with no `project` | test 5 |
  | reply after `project` changed (to B or to `""`) | test 6, Review Focus 5 |
  | switch with dialog, flash, error and pending | test 7 |
  | logs of B with no project | test 8 |
  | logs reply after a switch | test 9, test 11 |
  | no `project.root` | test 10 |
- **Spec deviation**: `test_logs_argv_keeps_an_odd_root_verbatim` drops its trailing slash. This is stated at the top and in Task 3 Step 2(d).
- **Placeholders**: none. Every code step carries the full code.
- **Names**: `runRoot`, `repoDir`, `projectRoot`, `crossStore`, `bWork`, `held`, `tc.bRepo` and `tc.settingsCmdB` are used with the same spelling in every task.
<!-- task-pipeline: validated -->
