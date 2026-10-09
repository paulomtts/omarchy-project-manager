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
