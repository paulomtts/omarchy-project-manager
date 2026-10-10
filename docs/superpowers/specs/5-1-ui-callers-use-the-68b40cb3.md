# 5.1 ui callers use the new run stores — design

Card: `68b40cb3` ("5.1 ui callers use the new run stores"). It is a subtask of story `97aa329f`
"Retire the RunStore shims", and its siblings are 5.2 `173b82e2` ("RunStore shims removed") and
5.3 `e7709c33` ("Docs: the four run stores"). The parent design is
`docs/superpowers/specs/2026-10-05-split-runstore-design.md`, cited below as "P l.N". Line numbers
into `ui/`, `tests/ui/` and `core/stores/` come from this card's start (`cced5e3`):
`core/stores/RunStore.qml` is 1136 lines, `RunControlStore.qml` 546, `RunAlertsStore.qml` 172,
`RunDispatchStore.qml` 459 and `App.qml` 191.

## Purpose

This card is a pure path change. Today every `ui/` and `tests/ui/` caller reaches the run
controls, the alerts and the dispatch through `RunStore`'s shims (`app.runs.X`), which forward to
the three stores App composes (`core/stores/App.qml:108-178`). After this card:

- Each read, write, call and signal connection of a member that moved goes to the store that owns
  it: `app.runControl`, `app.runAlerts` or `app.runDispatch` (P l.52-57, l.128-129).
- A member that stayed in `RunStore` keeps `app.runs`.
- Nothing in `ui/` or `tests/ui/` names a shim any more, so 5.2 can delete them (P l.128-130).

A user sees nothing different. Every helper gets the same argv, at the same moment. Every
`tests/ui` expectation stays exactly as it is, and only the path to the member changes. The one
exception is the two stub-app screen tests, whose stub moves members from one plain object to
another (see "Tests").

## Scope

### In scope

- `ui/Panel.qml`, `ui/Shortcuts.qml`, `ui/Navigator.qml`, `ui/screens/RunsScreen.qml`,
  `ui/screens/RunDetailScreen.qml` and `ui/screens/CardDetailScreen.qml`: every moved member they
  reach.
- Every file in `tests/ui/` that reaches a moved member. That includes the two stub apps in
  `tests/ui/screens/tst_runs_screen.qml` and `tests/ui/screens/tst_run_detail_screen.qml`.
- One new pytest guard, `tests/architecture/test_run_store_callers.py` (see "Tests"). It gives this
  card a real red step, and it keeps 5.2 safe: after this card nothing in `ui/` or `tests/ui/`
  reaches a moved member through `.runs.`.

### What the card names that does not exist

The card lists callers that the queued milestones would add (P l.117-121). None of them is in the
tree at `cced5e3`. Appendix A lists them as "not present at this commit" (P l.407-416), and a grep
of `core/`, `ui/` and `tests/` finds none of them:

- Resume and recover's `ResumeVerifyDialog` mount and the `resume*` members.
- `RunDetailScreen` / `StopReasonBlock` relaunch (`relaunchOpenFor`, `relaunch*`) and
  `lastControlErrorType`.
- Dispatch from the Runs screen's `DispatchDialog` steps (`dispatchStep`, `dispatchOpenFromRuns`,
  `dispatchBack`, `dispatchProject*`, `dispatchTarget*` as step members) and `dispatchRoot`.
- A `RunsScreen` "Start run" that opens a Runs-scoped dispatch, and a `Shortcuts` `d` that opens
  one from Runs. The `▶ Start run` button and `d` that exist today call `openDispatch` and are
  migrated like any other caller.

This card migrates only what exists. It adds no code for the missing members. A milestone that
lands them later lands them in the new stores (P l.132-142).

### Left to other cards

- **5.2:** deletes the shims and handles in `core/stores/RunStore.qml:119-219` and the App lines
  that set `controlStore`, `alertsStore` and `dispatchStore` (`App.qml:114-116`). It also adds the
  App test asserting that `RunStore` has none of the moved members (P l.129-130, l.163-164). This
  card does not touch `core/`.
- **5.3:** owns `docs/architecture.md` and `README.md`. That includes `docs/architecture.md:167`
  ("The run screens read `app.runs`", "read through the `app.runs` shims", `app.runs.control`,
  `app.runs.openCancel`, `app.runs.openDispatch`, `RunStore.retargetToMilestone()`). This card
  edits no doc.
- No `core/stores/*.qml`, `core/domain/*` or `core/backend/*` change.
- No new component, no new UI, and no change to a visible string.

## Inherited constraints

| constraint | source |
|---|---|
| Owners: `RunControlStore` = `app.runControl`, `RunAlertsStore` = `app.runAlerts`, `RunDispatchStore` = `app.runDispatch`, `RunStore` = `app.runs` | P l.52-57 |
| Every member lands in exactly one store; nothing duplicated | P l.61-63 |
| The last story first moves every `ui/` and `tests/ui/` caller to the three handles, then deletes the shims | P l.128-130 |
| `Panel` connects to `onCancelOpenChanged`; the shim had to notify, so the real store's notify must reach the same handler | P l.122-125 |
| No behaviour change, no renamed public member, no new helper argv, no change to which process starts when | P l.146-147 |
| No UI change apart from the callers' paths in the last story | P l.148 |
| The ui suites pass against the new paths | P l.163 |
| `tests/architecture` stays green: layer allowlists, no duplicated shared patterns, icon glyph rules | P l.105-106; card |
| Screens and components get `app` and never import `core/stores` | card; `docs/architecture.md:167` |
| Docstrings and comments state the contract only, with no narrative | card |
| Verification: `bash tests/run.sh` green | card |

## The member map (what moves where)

This map is the shim map at `core/stores/RunStore.qml:119-219`, which is exactly the set of moved
members that exist (P Appendix A, A.1 rows whose target is not RunStore and that have a shim).
Anything not listed stays on `app.runs`.

**→ `app.runControl`** (`RunControlStore`):
`pending`, `stillWaiting`, `stillWaitingText`, `lastControlError`, `lastControlErrorRunId`,
`cancelRunId`, `cancelOpen`, `cancelText`, `cancelError`, `flashText`, `controlRunners`,
`pendingTimer`, `flashTimer`, `notifyOnEscalation`, `notifySaved`, `notifyTouched`,
`settingsLoadRunner`, `settingsSaveRunner`, `control()`, `refusalOf()`, `flash()`, `openCancel()`,
`closeCancel()`, `confirmCancel()`, `setNotifyOnEscalation()`, and the two renamed shims below.

**→ `app.runAlerts`** (`RunAlertsStore`):
`armedRoots`, `alertsArmed`, `toasts`, `toastMs`, `toastTimer`, `notifyRunners`, `raiseAlerts()`,
`expireToasts()`, `dismissToast()`, `dismissAllToasts()`, `notify()`.

**→ `app.runDispatch`** (`RunDispatchStore`):
`dispatchState`, `dispatchTarget`, `dispatchTargetLabel`, `dispatchForm`, `dispatchPreview`,
`dispatchError`, `dispatchErrorType`, `dispatchErrors`, `dispatchSuggest`, `dispatchRunId`,
`dispatchMessage`, `dispatchLog`, `dispatchLogTail`, `dispatchExitCode`,
`dispatchDefaultsRunner`, `dispatchPreviewRunner`, `dispatchDebounceTimer`,
`dispatchStartRunners`, signal `dispatchStarted(runId)`, `openDispatch()`, `closeDispatch()`,
`retargetToMilestone()`, `setDispatchField()`, `dispatchStart()`, `checkDispatch()`.

**Stays on `app.runs`:** `runs`, `runById`, `filteredRuns`, `groups`, `selectedRunId`,
`selectedAttempt`, `selectAttempt`, `refreshLogs`, `logsText`, `logsTruncated`, `logsFetchedMs`,
`logsLoading`, `logsError`, `logsRunner`, `amStatus`, `amSchema`, `amVersion`, `lastError`,
`stale`, `watching`, `watchWarning`, `watchSchemaError`, `runFilter`, `projectFilter`,
`toggleRunFilter`, `toggleProjectFilter`, `projectRoots`, `projectErrors`, `project`,
`snapshotRunner`, `refresh`, `requestSnapshot`, `searchQuery`, `active`, and the signals
`runFilterToggled`, `projectFilterToggled` and `runsChanged`.

### The two shims whose names differ on the real store

| shim on `app.runs` | equivalent on `app.runControl` | why it is the same |
|---|---|---|
| `runSettingsRunner` (read) | `runSettingsLoadRunner` | the shim is `controlStore.runSettingsLoadRunner` (`RunStore.qml:166`) |
| `runSettings` (read) | `runSettingsOf(app.runs.project)` | the shim binds `controlStore.runSettingsOf(store.project)` (`RunStore.qml:161`); `store.project` is App's `app.runs.project` |
| `runSettings = X` (write) | `applyRunSettings(app.runs.project, X)` | the shim's `onRunSettingsChanged` calls `controlStore.applyRunSettings(store.project, store.runSettings)` (`RunStore.qml:162-165`) |

`RunControlStore.runSettings` is a different thing: the `{root: settings}` map
(`RunControlStore.qml:62`). Never assign a single project's settings to it.

## Behaviour by file (ui/)

Every change below is a path substitution. The screens and components keep getting `app` (or
`appStores` in `Panel`). None of them imports `core/stores`.

### `ui/Panel.qml`

- **Connections (`:98-107`).** Today there is one `Connections { target: appStores.runs }` with
  four handlers. It becomes three blocks, and each handler keeps its body. The comment above them
  keeps its contract text.
  - `target: appStores.runs`: `onRunFilterToggled`, `onRunsChanged`.
  - `target: appStores.runControl`: `onCancelOpenChanged() { root.focusForView() }`.
    `RunControlStore.cancelOpen` is a readonly binding on `cancelRunId`
    (`RunControlStore.qml:46`), so it notifies whenever the shim did (P l.124-125).
  - `target: appStores.runDispatch`: `onDispatchStarted(runId)`, whose body calls
    `appStores.runDispatch.closeDispatch()` and then `navi.openStartedRun(runId)`, in that order.
- **Moved reads and calls:** `:184` `cancelOpen`; `:240` `dismissToast`; `:243` `flash`; `:274`,
  `:277-278` `dispatchState` / `dispatchTarget`; `:295` `dispatchSuggest`; `:353`, `:356`
  `dispatchState` / `openDispatch`; `:730`, `:756`, `:765` `openCancel`; `:781-782` `toasts` /
  `dismissToast`. The cancel modal (`:831-842`) reads `cancelOpen`, `cancelRunId`, `cancelError`
  and `cancelText` and calls `confirmCancel` and `closeCancel`. Its `runById` (`:834`) stays on
  `appStores.runs`. The dispatch dialog (`:902-926`) has `Connections { target: … dispatchTarget }`
  at `:903`; it reads `dispatchState` through `dispatchExitCode` and calls `setDispatchField`,
  `dispatchStart`, `closeDispatch` and `retargetToMilestone`.
- **Two-way members.** `cancelText` (typed into the modal) and any `dispatchState` write now go
  straight to the owning store. The shim forwarded each write there (`RunStore.qml:126-142`,
  `:184-191`), so the final state is the same.
- **Stays:** `:252` `runs`, `:262-263` the filters, `:435` `runs`, `:555` and `:559` `amStatus`.

### `ui/Shortcuts.qml`

- `:45`: `dispatchState` and `closeDispatch` go to `runDispatch`; `cancelOpen` and `closeCancel` go
  to `runControl`; `toasts` and `dismissAllToasts` go to `runAlerts`.
- `:51` `cancelOpen` goes to `runControl`, and `:52` `dispatchState` goes to `runDispatch`.
- `:73-76` `refusalOf`, `flash`, `openCancel` and `control` go to `runControl`.
- `:126` `toasts` and `dismissAllToasts` go to `runAlerts`.
- **Stays:** `:70` `runById` / `selectedRunId` / `filteredRuns`, and `:90` `amStatus`.

### `ui/Navigator.qml`

- `:389` and `:398` `flash` go to `runControl`. Everything else (`:27`, `:50`, `:337-412`) stays on
  `runs`.

### `ui/screens/RunsScreen.qml`

- `:242` `control`, `:322-323` `notifyOnEscalation` / `setNotifyOnEscalation`, `:343-345`
  `flashText`, and `:570-573` `pending`, `stillWaiting`, `stillWaitingText`, `lastControlError`
  and `lastControlErrorRunId` go to `runControl`. Everything else stays.

### `ui/screens/RunDetailScreen.qml`

- `:161` `control`, `:224-227` the pending / waiting / control-error reads, and `:317` `flashText`
  go to `runControl`.
- `outputAge()` (`:130`, `var store = screen.app.runs`) reads only `logs*`, so it stays.

### `ui/screens/CardDetailScreen.qml`

- `:50` `control` and `:290-293` the pending / waiting / control-error reads go to `runControl`.
  Everything else stays.

### Unchanged

`BoardScreen.qml`, `GraphScreen.qml` and every file in `ui/components/` reach no moved member.
`RunControls.qml:32`'s comment names `RunStore.runs`, which stays.

## Equivalence (for the reviewer)

- **Reads.** Each shim property is a readonly binding to the same property on the owning store
  (`RunStore.qml:121-152`, `:166`, `:170-175`, `:184-208`). Reading the store directly gives the same value
  at the same moment, and notifies no later.
- **Calls.** Each shim function is a one-line forward that returns the target's result
  (`RunStore.qml:153-159`, `:176-180`, `:214-219`). The handle is always set under App, so the
  shim's `undefined` fallback never ran in any `tests/ui` suite built on the real App. Calling the
  target directly is the same call.
- **Writes.** `cancelRunId`, `cancelText` and `dispatchState` are two-way shims: they write
  through, and the store's value comes back through the Binding. Writing the store directly
  reaches the same state in one step. `runSettings = X` is replaced by its forward,
  `applyRunSettings(project, X)` (table above).
- **Signals.** The shim re-emits `dispatchStarted` synchronously from a `Connections` on
  `dispatchStore` (`RunStore.qml:209-213`). App has no handler on `runDispatch.dispatchStarted`
  (`App.qml:165-178`). Panel's handler connecting directly therefore runs at the same point and
  sees the same state. The same holds for `cancelOpenChanged`.

## Tests

The gate is `bash tests/run.sh`: pytest over `tests/` (including `tests/architecture`), then every
`tst_*.qml` through `qmltestrunner`.

### New guard (pytest, `tests/architecture/test_run_store_callers.py`)

Tier: pytest/architecture. The rule is a source-level property of the tree ("no caller names a
shim"). A QML run cannot see it while the shims still forward, and the existing layer rules
already live in this tier and in this style (`tests/architecture/test_layers.py`). It is the only
test that fails before the migration and passes after it.

- `MOVED` is a constant: the exact member names from "The member map" for all three stores, plus
  the shim-only names `runSettings` and `runSettingsRunner`. Each name gets a comment naming its
  owner.
- `test_no_ui_file_reaches_a_moved_member_through_runs[<path>]` is parametrized over every `.qml`
  and `.js` under `ui/` and `tests/ui/`. It asserts that no line matches
  `\.runs\.(<MOVED alternation>)\b`. On a match the failure lists `path:line` for every hit, so the
  red run reads as the migration's worklist. Comments are included: a comment naming
  `app.runs.flash` is a stale contract. Test-local recorders such as `controlCalls` and
  `notifyCalls` do not match, because of the word boundary.
- `test_no_ui_connections_on_runs_handles_a_moved_signal` scans every `Connections {` block in
  `ui/**/*.qml` with a brace-depth walk from the `Connections {` line to its matching `}`. For a
  block whose `target:` ends in `.runs` (for example `appStores.runs` or `app.runs`), it asserts
  that no handler is `onDispatchStarted` or `on<Name>Changed` for a `<Name>` in `MOVED`
  (case-adjusted: `cancelOpen` → `onCancelOpenChanged`). The regex guard cannot see a handler name,
  so this one exists for that case.
- `test_the_moved_set_is_not_empty_and_has_no_staying_member` is a sanity check. `MOVED` contains
  `cancelOpen`, `toasts` and `dispatchStarted`. It does not contain `runs`, `runById`, `amStatus`,
  `selectedRunId`, `project` or `refresh`. This stops a typo from silently shrinking the guard.

Before the migration the first two fail, naming the files and lines listed under "Behaviour by
file" and the `tests/ui` lines below. After the migration all three pass.

### Stub-app screen tests (QML, `tests/ui/screens/`)

Tier: QML unit (screen on its own, stub app). These are the only `tests/ui` suites that do not
build the real App. Their stub `rs` object carries both RunStore and RunControlStore members, so
they are where the screens' reads get a real red step.

- **`tst_runs_screen.qml`.** The `runsC` stub keeps the RunStore members (`:28-72`). A new
  component, `controlC` (id `rc`), takes the control members: `pending`, `stillWaiting`,
  `stillWaitingText`, `lastControlError`, `lastControlErrorRunId`, `controlCalls` with its
  recording `control(action, id)`, `flashText`, `notifyOnEscalation`, and `notifyCalls` with its
  recording `setNotifyOnEscalation(on)`. Their default values and bodies do not change. `appC`
  gains `property var runControl: null`. `make()` creates the control stub, passes it as
  `runControl`, and returns it as `control`, next to the existing `runs`. Every test line that
  reads or writes one of those members through `s.runs.X` becomes `s.control.X`. No expectation,
  message or value changes. The header comment says the stub carries "the RunStore properties and,
  apart, the RunControlStore properties the screen reads".
- **`tst_run_detail_screen.qml`.** The same split. `controlC` holds `pending`, `stillWaiting`,
  `stillWaitingText`, `lastControlError`, `lastControlErrorRunId`, `flashText` and `controlCalls`
  with `control`. `selected`, `refreshed`, `selectAttempt` and `refreshLogs` stay on `runsC`. The
  header comment is updated the same way.
- **Red step:** with the stubs split and the screens unchanged, the screens read `app.runs.pending`
  and the other moved members from a stub that no longer has them. The control, flash and notify
  tests in both files fail. Changing `RunsScreen.qml` and `RunDetailScreen.qml` makes them pass.

### Real-App ui suites (QML flow and screen tests)

Tier: QML flow tests (the real `Panel` or the real App plus the real screens). They already pin the
behaviour end to end. Their job here is to prove that the new paths drive the same flows. Through
the shims they pass both before and after, so the guard provides their red step.

In each file, every moved member reached as `p.app.runs.X`, `app.runs.X` or `s.app.runs.X` becomes
`….runControl.X`, `….runAlerts.X` or `….runDispatch.X` per the map. Staying members are left alone.
The renames:

- `….runs.runSettingsRunner` → `….runControl.runSettingsLoadRunner` (`tst_board_flow.qml:152`,
  `tst_runs_real_data.qml:50`, `tst_dispatch_flow.qml:70`, `tst_runs_flow.qml:55`, `:861`, `:909`).
- `….runs.runSettings = V` → `….runControl.applyRunSettings(….runs.project, V)`
  (`tst_board_flow.qml:153`, `tst_dispatch_flow.qml:72`).
- `settingsLoadRunner` and `settingsSaveRunner` → `runControl` with the same name
  (`tst_board_flow.qml:151`, `tst_runs_real_data.qml:49`, `tst_dispatch_flow.qml:69`,
  `tst_runs_flow.qml:54`, `:692`, `:702`, `:827-828`, `:860`, `:908`).
- `controlRunners`, `flashText` and `pending` → `runControl`. `toasts`, `raiseAlerts` and
  `notifyRunners` → `runAlerts`. `dispatchState`, `dispatchTarget`, `dispatch*Runner(s)`,
  `dispatchDebounceTimer`, `openDispatch`, `checkDispatch` and `closeDispatch` → `runDispatch`.

Files and their current count of lines with a moved member: `tst_runs_flow.qml` (67),
`tst_shortcuts.qml` (67), `tst_dispatch_flow.qml` (51), `tst_board_flow.qml` (18),
`screens/tst_card_detail_screen.qml` (7), `tst_runs_real_data.qml` (2) and `tst_navigator.qml`
(2). The guard's red run is the authoritative list.

The flows that pin the Panel `Connections` split, which must pass unchanged:

- `tst_runs_flow.qml::test_cancel_asks_for_the_typed_word_then_cancels_and_gives_the_focus_back`
  and `::test_a_cards_runs_row_cancel_opens_the_same_dialog_and_keep_running_closes_it` pin
  `onCancelOpenChanged` on `runControl`.
- `tst_dispatch_flow.qml::test_a_start_whose_run_is_listed_opens_its_run_detail`,
  `::test_a_start_before_the_snapshot_waits_for_the_run_then_opens_it` and
  `::test_a_start_without_a_run_id_goes_to_the_runs_list_and_says_so` pin `onDispatchStarted` on
  `runDispatch`, with the dialog closing before the navigator opens the run.
- `tst_runs_flow.qml`'s toast tests (`:585-786`) pin `toasts` and `dismissToast` on `runAlerts`.

Do not rename test-local names that only contain `runs` or `control`: `controlCalls`,
`notifyCalls`, `projectToggles`, `s.runs.selected`, `s.runs.refreshed`, `runs.length`, and
`runs.map`.

### Unchanged suites that must stay green

- `tests/core/**`, including `tests/core/stores/tst_app_runs.qml` and the store unit suites. No
  file there changes.
- `tests/architecture/test_layers.py` and `test_icon_glyphs.py`.
- Every other `tests/ui` suite (`tst_panel_toolbar`, `tst_board_screen`, `tst_graph_screen`,
  `tst_graph_flow`, `tst_sidebar_nav` and the rest) reaches only staying members.

## Review Focus (for the planner)

1. **A partial Connections split.** If `onCancelOpenChanged` or `onDispatchStarted` stays under
   `target: appStores.runs`, everything passes today through the shims and breaks silently after
   5.2: the cancel dialog no longer takes the focus, and a started dispatch no longer navigates.
   The `Connections` guard test pins this, so make it part of the Panel task.
2. **`runSettings` written to the map.** `p.app.runControl.runSettings = { verify: [...] }` would
   replace the `{root: settings}` map with a settings object. The dispatch's
   `runSettingsOf(project)` would then read `{}`, and the dispatch tests would show default verify
   commands. The only correct substitution is `applyRunSettings(p.app.runs.project, …)`.
3. **`runSettingsRunner` kept as a name.** `app.runControl.runSettingsRunner` does not exist, and
   `undefined.cancel()` throws in the test's init. The name is `runSettingsLoadRunner`.
4. **A staying member moved by mistake** (`runById`, `amStatus`, `selectedRunId` or `project` put
   on `runControl`) would read `undefined`, and the screen would fall back to empty states. The
   guard's sanity test and the unchanged expectations in the flow tests catch this, so keep every
   expectation byte-identical.
5. **Stub split drift.** In the stub screen tests, a member copied to `controlC` but left on
   `runsC` too would let the screens' old `app.runs.X` reads pass. Each moved member must exist on
   exactly one stub, matching rule 1 (P l.61-63). The red step must show the control, flash and
   notify tests failing before the screen edit.

## Hand-off to the planner

Suggested tasks, each ending green on its own touched suites. The whole `bash tests/run.sh` must
be green only at the end, when the guard turns fully green.

1. **Guard.** Write `tests/architecture/test_run_store_callers.py` and run it to see it fail with
   the worklist. Commit it as a failing test only if the repo convention allows that; otherwise
   keep it uncommitted until task 4, or mark the still-unmigrated parametrized paths `xfail(strict=True)`
   per task and remove the marks as each file is migrated. Prefer the strict-`xfail` route so
   every commit is green.
2. **Screens.** Split the two stub apps, see the red, then migrate `RunsScreen.qml`,
   `RunDetailScreen.qml` and `CardDetailScreen.qml` and `screens/tst_card_detail_screen.qml`.
3. **Navigator and Shortcuts.** Migrate `Navigator.qml` and `Shortcuts.qml` with
   `tst_navigator.qml` and `tst_shortcuts.qml`.
4. **Panel and the flow suites.** Do the `Connections` split and the rest of `Panel.qml`, then
   `tst_runs_flow.qml`, `tst_dispatch_flow.qml`, `tst_board_flow.qml` and `tst_runs_real_data.qml`.
   The guard is fully green after this task, and so is `bash tests/run.sh`.

Single QML suites run with `bash tests/run.sh <substring>`, for example
`bash tests/run.sh tst_runs_screen`. The pytest half always runs first. Wrap long runs in
`timeout`, for example `timeout 900 bash tests/run.sh`.
