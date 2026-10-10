# 5.1 UI callers use the new run stores Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every `ui/` and `tests/ui/` caller of a member that moved out of `RunStore` reaches it on the store that owns it (`app.runControl`, `app.runAlerts`, `app.runDispatch`) instead of through `RunStore`'s shims (`app.runs.X`). A pytest guard keeps it that way, so card 5.2 can delete the shims.

**Architecture:** This is a path-only change. The screens, `Navigator`, `Shortcuts` and `Panel` keep getting `app` (`appStores` in `Panel`) and only swap `.runs.` for the owning handle. `Panel`'s single `Connections { target: appStores.runs }` splits into three blocks, one per store. A new source-level guard, `tests/architecture/test_run_store_callers.py`, fails on any `.runs.<moved member>` and on any moved handler under a `Connections` targeting `.runs`. While the migration is in progress, the files not yet migrated are strict-`xfail` so every commit is green, and each task removes its own files from that set. The two stub-app screen tests split their stub so that the screens' reads get a real QML red step. `core/` and the docs do not change.

**Tech Stack:** QML (Qt 6 / Quickshell, stubbed in `tests/stubs`), QtTest via `qmltestrunner`, pytest. Everything runs through `bash tests/run.sh [filter]`: pytest over `tests/` first, then every `tst_*.qml` whose path contains the filter. The run fails on any `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item` or `is not a function` in the output. `python3` here has no pytest, so run pytest on its own as `uv run --with pytest python3 -m pytest ...`, the same fallback `tests/run.sh` uses.

**Spec:** `docs/superpowers/specs/5-1-ui-callers-use-the-68b40cb3.md` (copied verbatim below, with every heading demoted one level).

## Global Constraints

- Owners: `RunControlStore` = `app.runControl`, `RunAlertsStore` = `app.runAlerts`, `RunDispatchStore` = `app.runDispatch`, `RunStore` = `app.runs` (P l.52-57).
- Every member lands in exactly one store, and nothing is duplicated (P l.61-63). This also holds for the two test stubs.
- No behaviour change, no renamed public member, no new helper argv, and no change to which process starts when (P l.146-147).
- No UI change and no visible string change. Only the callers' paths change.
- Do not touch `core/stores/*.qml`, `core/domain/*`, `core/backend/*`, `docs/architecture.md` or `README.md` (they belong to 5.2 and 5.3).
- Screens and components get `app` and never import `core/stores`.
- Docstrings and comments state the contract only, with no narrative.
- Every `tests/ui` expectation, message and value stays byte-identical. Only the path to the member changes.
- Do not rename test-local names: `controlCalls`, `notifyCalls`, `projectToggles`, `s.runs.selected`, `s.runs.refreshed`, `runs.length`, `runs.map`.
- `runSettingsRunner` → `runControl.runSettingsLoadRunner`. `runs.runSettings = V` → `runControl.applyRunSettings(<app>.runs.project, V)`. Never assign to `runControl.runSettings`: it is the `{root: settings}` map.
- Verification: `bash tests/run.sh` is green at the end. `tests/architecture` stays green at every commit.
- Never run `pkill`, `killall` or a pattern `kill`. Wrap long runs in `timeout`.

## Review Focus

1. **A partial `Connections` split in Panel.** If `onCancelOpenChanged` or `onDispatchStarted` stays under `target: appStores.runs`, everything still passes through the shims today and breaks silently after 5.2. Pinned by `test_no_ui_connections_on_runs_handles_a_moved_signal` (Task 1, strict-xfail until Task 4) and by the cancel/dispatch flow tests (Task 4).
2. **`runSettings` written to the map.** `runControl.runSettings = {verify: [...]}` would wipe the per-root map, and the dispatch tests would then show default verify commands. Task 4 uses `applyRunSettings(p.app.runs.project, …)`, and `tst_dispatch_flow` / `tst_board_flow` pin the outcome.
3. **`runSettingsRunner` kept as a name on `runControl`.** It does not exist there, and `undefined.cancel()` throws in `make()`. Task 4's substitution rewrites it to `runSettingsLoadRunner` before the general control rule runs, and the `run.sh` TypeError check catches any leftover.
4. **A staying member moved by mistake** (`runById`, `amStatus`, `selectedRunId`, `project`, `runs`). The substitution only matches the names in the member map, the guard's sanity test pins that `MOVED` holds no staying name (Task 1), and the unchanged flow expectations catch a wrong read.
5. **Stub split drift.** A member copied to `controlC` but left on `runsC` would let the unmigrated screen reads pass. Task 2 deletes each moved member from `runsC` and requires the red run (control, flash, notify and footer tests failing) before the screens change.

---

## The spec (verbatim)

## 5.1 ui callers use the new run stores — design

Card: `68b40cb3` ("5.1 ui callers use the new run stores"). It is a subtask of story `97aa329f`
"Retire the RunStore shims", and its siblings are 5.2 `173b82e2` ("RunStore shims removed") and
5.3 `e7709c33` ("Docs: the four run stores"). The parent design is
`docs/superpowers/specs/2026-10-05-split-runstore-design.md`, cited below as "P l.N". Line numbers
into `ui/`, `tests/ui/` and `core/stores/` come from this card's start (`cced5e3`):
`core/stores/RunStore.qml` is 1136 lines, `RunControlStore.qml` 546, `RunAlertsStore.qml` 172,
`RunDispatchStore.qml` 459 and `App.qml` 191.

### Purpose

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

### Scope

#### In scope

- `ui/Panel.qml`, `ui/Shortcuts.qml`, `ui/Navigator.qml`, `ui/screens/RunsScreen.qml`,
  `ui/screens/RunDetailScreen.qml` and `ui/screens/CardDetailScreen.qml`: every moved member they
  reach.
- Every file in `tests/ui/` that reaches a moved member. That includes the two stub apps in
  `tests/ui/screens/tst_runs_screen.qml` and `tests/ui/screens/tst_run_detail_screen.qml`.
- One new pytest guard, `tests/architecture/test_run_store_callers.py` (see "Tests"). It gives this
  card a real red step, and it keeps 5.2 safe: after this card nothing in `ui/` or `tests/ui/`
  reaches a moved member through `.runs.`.

#### What the card names that does not exist

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

#### Left to other cards

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

### Inherited constraints

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

### The member map (what moves where)

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

#### The two shims whose names differ on the real store

| shim on `app.runs` | equivalent on `app.runControl` | why it is the same |
|---|---|---|
| `runSettingsRunner` (read) | `runSettingsLoadRunner` | the shim is `controlStore.runSettingsLoadRunner` (`RunStore.qml:166`) |
| `runSettings` (read) | `runSettingsOf(app.runs.project)` | the shim binds `controlStore.runSettingsOf(store.project)` (`RunStore.qml:161`); `store.project` is App's `app.runs.project` |
| `runSettings = X` (write) | `applyRunSettings(app.runs.project, X)` | the shim's `onRunSettingsChanged` calls `controlStore.applyRunSettings(store.project, store.runSettings)` (`RunStore.qml:162-165`) |

`RunControlStore.runSettings` is a different thing: the `{root: settings}` map
(`RunControlStore.qml:62`). Never assign a single project's settings to it.

### Behaviour by file (ui/)

Every change below is a path substitution. The screens and components keep getting `app` (or
`appStores` in `Panel`). None of them imports `core/stores`.

#### `ui/Panel.qml`

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

#### `ui/Shortcuts.qml`

- `:45`: `dispatchState` and `closeDispatch` go to `runDispatch`; `cancelOpen` and `closeCancel` go
  to `runControl`; `toasts` and `dismissAllToasts` go to `runAlerts`.
- `:51` `cancelOpen` goes to `runControl`, and `:52` `dispatchState` goes to `runDispatch`.
- `:73-76` `refusalOf`, `flash`, `openCancel` and `control` go to `runControl`.
- `:126` `toasts` and `dismissAllToasts` go to `runAlerts`.
- **Stays:** `:70` `runById` / `selectedRunId` / `filteredRuns`, and `:90` `amStatus`.

#### `ui/Navigator.qml`

- `:389` and `:398` `flash` go to `runControl`. Everything else (`:27`, `:50`, `:337-412`) stays on
  `runs`.

#### `ui/screens/RunsScreen.qml`

- `:242` `control`, `:322-323` `notifyOnEscalation` / `setNotifyOnEscalation`, `:343-345`
  `flashText`, and `:570-573` `pending`, `stillWaiting`, `stillWaitingText`, `lastControlError`
  and `lastControlErrorRunId` go to `runControl`. Everything else stays.

#### `ui/screens/RunDetailScreen.qml`

- `:161` `control`, `:224-227` the pending / waiting / control-error reads, and `:317` `flashText`
  go to `runControl`.
- `outputAge()` (`:130`, `var store = screen.app.runs`) reads only `logs*`, so it stays.

#### `ui/screens/CardDetailScreen.qml`

- `:50` `control` and `:290-293` the pending / waiting / control-error reads go to `runControl`.
  Everything else stays.

#### Unchanged

`BoardScreen.qml`, `GraphScreen.qml` and every file in `ui/components/` reach no moved member.
`RunControls.qml:32`'s comment names `RunStore.runs`, which stays.

### Equivalence (for the reviewer)

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

### Tests

The gate is `bash tests/run.sh`: pytest over `tests/` (including `tests/architecture`), then every
`tst_*.qml` through `qmltestrunner`.

#### New guard (pytest, `tests/architecture/test_run_store_callers.py`)

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

#### Stub-app screen tests (QML, `tests/ui/screens/`)

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

#### Real-App ui suites (QML flow and screen tests)

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

#### Unchanged suites that must stay green

- `tests/core/**`, including `tests/core/stores/tst_app_runs.qml` and the store unit suites. No
  file there changes.
- `tests/architecture/test_layers.py` and `test_icon_glyphs.py`.
- Every other `tests/ui` suite (`tst_panel_toolbar`, `tst_board_screen`, `tst_graph_screen`,
  `tst_graph_flow`, `tst_sidebar_nav` and the rest) reaches only staying members.

### Review Focus (for the planner)

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

### Hand-off to the planner

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

---

## File Structure

| file | change | task |
|---|---|---|
| `tests/architecture/test_run_store_callers.py` | **create**: the guard (`MOVED`, the line regex, the `Connections` walk). Strict-`xfail` for files not migrated yet, until Task 4 | 1, 2, 3, 4 |
| `tests/ui/screens/tst_runs_screen.qml` | stub split: new `controlC`, `appC.runControl`, `make()` returns `control`, `s.runs.X` → `s.control.X` | 2 |
| `tests/ui/screens/tst_run_detail_screen.qml` | the same stub split | 2 |
| `ui/screens/RunsScreen.qml` | 10 moved reads/calls → `runControl` | 2 |
| `ui/screens/RunDetailScreen.qml` | 6 moved reads/calls → `runControl` | 2 |
| `ui/screens/CardDetailScreen.qml` | 5 moved reads/calls → `runControl` | 2 |
| `tests/ui/screens/tst_card_detail_screen.qml` | 7 moved reads → `runControl` / `runDispatch` | 2 |
| `ui/Navigator.qml` | 2 `flash` → `runControl` | 3 |
| `ui/Shortcuts.qml` | 8 lines → `runControl` / `runAlerts` / `runDispatch` | 3 |
| `tests/ui/tst_navigator.qml`, `tests/ui/tst_shortcuts.qml` | moved reads → owning handle | 3 |
| `ui/Panel.qml` | `Connections` split into three, 36 lines → owning handle | 4 |
| `tests/ui/tst_runs_flow.qml`, `tst_dispatch_flow.qml`, `tst_board_flow.qml`, `tst_runs_real_data.qml` | moved reads → owning handle, the two renames | 4 |

### The substitution (used by Tasks 2, 3 and 4)

Every real-App caller reaches RunStore as `…app.runs.` or `appStores.runs.` (the only prefixes in the tree: `appStores`, `screen.app`, `detailCard.app`, `navi.app`, `keys.app`, `n.app`, `p.app`, `s.app`). No caller aliases the store (`var store = screen.app.runs` in `RunDetailScreen.outputAge()` reads only `logs*`, which stay), and no test passes the store to `tryCompare` with a property name string. So one `sed` program over the member map does the whole path change. Its first rule renames `runSettingsRunner` before the control rule could see it. `\b` stops `flash` from matching `flashText` and `control` from matching `controlCalls`. Each task below runs this exact block on its own file list, given as the arguments at the end:

```bash
CONTROL='pending|stillWaiting|stillWaitingText|lastControlError|lastControlErrorRunId|cancelRunId|cancelOpen|cancelText|cancelError|flashText|controlRunners|pendingTimer|flashTimer|notifyOnEscalation|notifySaved|notifyTouched|settingsLoadRunner|settingsSaveRunner|control|refusalOf|flash|openCancel|closeCancel|confirmCancel|setNotifyOnEscalation'
ALERTS='armedRoots|alertsArmed|toasts|toastMs|toastTimer|notifyRunners|raiseAlerts|expireToasts|dismissToast|dismissAllToasts|notify'
DISPATCH='dispatchState|dispatchTarget|dispatchTargetLabel|dispatchForm|dispatchPreview|dispatchError|dispatchErrorType|dispatchErrors|dispatchSuggest|dispatchRunId|dispatchMessage|dispatchLog|dispatchLogTail|dispatchExitCode|dispatchDefaultsRunner|dispatchPreviewRunner|dispatchDebounceTimer|dispatchStartRunners|dispatchStarted|openDispatch|closeDispatch|retargetToMilestone|setDispatchField|dispatchStart|checkDispatch'
sed -E -i \
  -e "s/\b(appStores|app)\.runs\.runSettingsRunner\b/\1.runControl.runSettingsLoadRunner/g" \
  -e "s/\b(appStores|app)\.runs\.($CONTROL)\b/\1.runControl.\2/g" \
  -e "s/\b(appStores|app)\.runs\.($ALERTS)\b/\1.runAlerts.\2/g" \
  -e "s/\b(appStores|app)\.runs\.($DISPATCH)\b/\1.runDispatch.\2/g" \
  <files…>
```

`runs.runSettings = V` is the one caller this program does not handle. Task 4 edits it by hand **before** running the program.

---

### Task 1: The guard: no ui caller reaches a moved member through `.runs.`

**Files:**
- Create: `tests/architecture/test_run_store_callers.py`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `UNMIGRATED` (a `set[str]` of repo-relative paths). Tasks 2 and 3 delete their own entries from it, and Task 4 deletes the set, `caller_params()` and the `xfail` on `test_no_ui_connections_on_runs_handles_a_moved_signal`. Test ids are repo-relative paths, for example `test_no_ui_file_reaches_a_moved_member_through_runs[ui/Panel.qml]`.

- [ ] **Step 1: Write the failing guard**

Create `tests/architecture/test_run_store_callers.py` with exactly this content:

```python
"""No ui/ or tests/ui/ caller reaches a member RunStore no longer owns through `.runs.`.

Each moved member is read, written, called and connected on the store that owns it:
`runControl` (RunControlStore), `runAlerts` (RunAlertsStore) or `runDispatch` (RunDispatchStore).
"""
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
CALLER_DIRS = ["ui", "tests/ui"]

# member -> the App handle that owns it
MOVED = {
    "pending": "runControl",
    "stillWaiting": "runControl",
    "stillWaitingText": "runControl",
    "lastControlError": "runControl",
    "lastControlErrorRunId": "runControl",
    "cancelRunId": "runControl",
    "cancelOpen": "runControl",
    "cancelText": "runControl",
    "cancelError": "runControl",
    "flashText": "runControl",
    "controlRunners": "runControl",
    "pendingTimer": "runControl",
    "flashTimer": "runControl",
    "notifyOnEscalation": "runControl",
    "notifySaved": "runControl",
    "notifyTouched": "runControl",
    "settingsLoadRunner": "runControl",
    "settingsSaveRunner": "runControl",
    "control": "runControl",
    "refusalOf": "runControl",
    "flash": "runControl",
    "openCancel": "runControl",
    "closeCancel": "runControl",
    "confirmCancel": "runControl",
    "setNotifyOnEscalation": "runControl",
    "runSettings": "runControl (runSettingsOf / applyRunSettings with app.runs.project)",
    "runSettingsRunner": "runControl (runSettingsLoadRunner)",
    "armedRoots": "runAlerts",
    "alertsArmed": "runAlerts",
    "toasts": "runAlerts",
    "toastMs": "runAlerts",
    "toastTimer": "runAlerts",
    "notifyRunners": "runAlerts",
    "raiseAlerts": "runAlerts",
    "expireToasts": "runAlerts",
    "dismissToast": "runAlerts",
    "dismissAllToasts": "runAlerts",
    "notify": "runAlerts",
    "dispatchState": "runDispatch",
    "dispatchTarget": "runDispatch",
    "dispatchTargetLabel": "runDispatch",
    "dispatchForm": "runDispatch",
    "dispatchPreview": "runDispatch",
    "dispatchError": "runDispatch",
    "dispatchErrorType": "runDispatch",
    "dispatchErrors": "runDispatch",
    "dispatchSuggest": "runDispatch",
    "dispatchRunId": "runDispatch",
    "dispatchMessage": "runDispatch",
    "dispatchLog": "runDispatch",
    "dispatchLogTail": "runDispatch",
    "dispatchExitCode": "runDispatch",
    "dispatchDefaultsRunner": "runDispatch",
    "dispatchPreviewRunner": "runDispatch",
    "dispatchDebounceTimer": "runDispatch",
    "dispatchStartRunners": "runDispatch",
    "dispatchStarted": "runDispatch",
    "openDispatch": "runDispatch",
    "closeDispatch": "runDispatch",
    "retargetToMilestone": "runDispatch",
    "setDispatchField": "runDispatch",
    "dispatchStart": "runDispatch",
    "checkDispatch": "runDispatch",
}

MOVED_RE = re.compile(r"\.runs\.(" + "|".join(sorted(MOVED, key=len, reverse=True)) + r")\b")
CONNECTIONS_RE = re.compile(r"\bConnections\s*\{")
TARGET_RE = re.compile(r"^\s*target:\s*([\w.]+)\s*$", re.M)
HANDLER_RE = re.compile(r"\bfunction\s+(on[A-Z]\w*)\s*\(|^\s*(on[A-Z]\w*)\s*:", re.M)
RUNS_TARGET_RE = re.compile(r"(?:^|\.)runs$")


def rel(path):
    return path.relative_to(ROOT).as_posix()


def caller_files(*dirs, suffixes=(".qml", ".js")):
    return sorted(p for top in dirs for p in (ROOT / top).rglob("*") if p.suffix in suffixes)


def moved_hits(text):
    """(line number, member) for every moved member `text` reaches through `.runs.`, comments included."""
    return [(n, m.group(1)) for n, line in enumerate(text.splitlines(), 1) for m in MOVED_RE.finditer(line)]


def connections_blocks(text):
    """The text of every `Connections {` block, from its opening brace to the matching closing one."""
    blocks = []
    for m in CONNECTIONS_RE.finditer(text):
        start = m.end() - 1
        depth = 0
        for i in range(start, len(text)):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    blocks.append(text[start:i + 1])
                    break
    return blocks


def moved_handlers(block):
    """The handlers of a Connections block whose target ends in `.runs` that belong to a moved member."""
    target = TARGET_RE.search(block)
    if not target or not RUNS_TARGET_RE.search(target.group(1)):
        return []
    wanted = set()
    for name in MOVED:
        wanted |= {"on" + name[0].upper() + name[1:], "on" + name[0].upper() + name[1:] + "Changed"}
    return [h for h in (a or b for a, b in HANDLER_RE.findall(block)) if h in wanted]


def test_the_guard_helpers_flag_and_accept_what_they_should():
    assert moved_hits("x: app.runs.cancelOpen\ny: appStores.runs.flash(t) // app.runs.toasts") == \
        [(1, "cancelOpen"), (2, "flash"), (2, "toasts")]
    assert moved_hits("app.runControl.cancelOpen; app.runs.runById(id); s.runs.controlCalls; "
                      "app.runs.amStatus; app.runs.flashTextual") == []
    qml = ("Connections {\n  target: appStores.runs\n  function onRunsChanged() { if (a) { b() } }\n"
           "  function onCancelOpenChanged() { f() }\n}\n"
           "Connections {\n  target: appStores.runControl\n  function onCancelOpenChanged() { f() }\n}\n"
           "Connections {\n  target: app.runs\n  onDispatchStarted: g()\n}\n")
    blocks = connections_blocks(qml)
    assert len(blocks) == 3
    assert [moved_handlers(b) for b in blocks] == [["onCancelOpenChanged"], [], ["onDispatchStarted"]]


def test_the_moved_set_is_not_empty_and_has_no_staying_member():
    assert {"cancelOpen", "toasts", "dispatchStarted"} <= set(MOVED)
    assert not {"runs", "runById", "amStatus", "selectedRunId", "project", "refresh"} & set(MOVED)
    assert set(MOVED.values()) <= {"runControl", "runAlerts", "runDispatch"} | {
        MOVED["runSettings"], MOVED["runSettingsRunner"]}


@pytest.mark.parametrize("path", caller_files(*CALLER_DIRS), ids=rel)
def test_no_ui_file_reaches_a_moved_member_through_runs(path):
    hits = [f"{rel(path)}:{n} {member} -> {MOVED[member]}" for n, member in moved_hits(path.read_text())]
    assert hits == []


def test_no_ui_connections_on_runs_handles_a_moved_signal():
    found = [f"{rel(p)}: {h}" for p in caller_files("ui", suffixes=(".qml",))
             for block in connections_blocks(p.read_text()) for h in moved_handlers(block)]
    assert found == []
```

- [ ] **Step 2: Run it to see the worklist**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture/test_run_store_callers.py -q`
Expected: `16 failed, 104 passed`. The failures are `test_no_ui_connections_on_runs_handles_a_moved_signal` (it reports `ui/Panel.qml: onCancelOpenChanged` and `ui/Panel.qml: onDispatchStarted`) and `test_no_ui_file_reaches_a_moved_member_through_runs[...]` for exactly these 15 files: `ui/Panel.qml`, `ui/Navigator.qml`, `ui/Shortcuts.qml`, `ui/screens/RunsScreen.qml`, `ui/screens/RunDetailScreen.qml`, `ui/screens/CardDetailScreen.qml`, `tests/ui/screens/tst_runs_screen.qml`, `tests/ui/screens/tst_run_detail_screen.qml`, `tests/ui/screens/tst_card_detail_screen.qml`, `tests/ui/tst_navigator.qml`, `tests/ui/tst_shortcuts.qml`, `tests/ui/tst_runs_flow.qml`, `tests/ui/tst_dispatch_flow.qml`, `tests/ui/tst_board_flow.qml`, `tests/ui/tst_runs_real_data.qml`. The two helper tests pass. If any other file fails, stop: the tree differs from the spec's starting point.

- [ ] **Step 3: Mark the not-yet-migrated callers strict-xfail**

The repo keeps every commit green. Edit `tests/architecture/test_run_store_callers.py` in three places.

(a) Insert this block directly above the line `MOVED_RE = re.compile(...)`:

```python
# Callers still on the RunStore shims; each migrating task removes its own paths, the last removes the set.
UNMIGRATED = {
    "ui/Panel.qml",
    "ui/Navigator.qml",
    "ui/Shortcuts.qml",
    "ui/screens/RunsScreen.qml",
    "ui/screens/RunDetailScreen.qml",
    "ui/screens/CardDetailScreen.qml",
    "tests/ui/screens/tst_runs_screen.qml",
    "tests/ui/screens/tst_run_detail_screen.qml",
    "tests/ui/screens/tst_card_detail_screen.qml",
    "tests/ui/tst_navigator.qml",
    "tests/ui/tst_shortcuts.qml",
    "tests/ui/tst_runs_flow.qml",
    "tests/ui/tst_dispatch_flow.qml",
    "tests/ui/tst_board_flow.qml",
    "tests/ui/tst_runs_real_data.qml",
}

```

(b) Insert this function directly above `def moved_hits(text):`:

```python
def caller_params():
    return [pytest.param(p, id=rel(p), marks=pytest.mark.xfail(strict=True, reason="still on the RunStore shims"))
            if rel(p) in UNMIGRATED else pytest.param(p, id=rel(p)) for p in caller_files(*CALLER_DIRS)]


```

(c) Change the two test decorators:

```python
@pytest.mark.parametrize("path", caller_params())
def test_no_ui_file_reaches_a_moved_member_through_runs(path):
```

(replacing `@pytest.mark.parametrize("path", caller_files(*CALLER_DIRS), ids=rel)`), and

```python
@pytest.mark.xfail(strict=True, reason="Panel still connects to the RunStore shims")
def test_no_ui_connections_on_runs_handles_a_moved_signal():
```

- [ ] **Step 4: Run it green**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture -q`
Expected: every test passes, and `test_run_store_callers.py` shows `104 passed, 16 xfailed` (the totals include `test_layers.py` and `test_icon_glyphs.py`, which also pass).

- [ ] **Step 5: Commit**

```bash
git add tests/architecture/test_run_store_callers.py
git commit -m "test(architecture): no ui caller reaches a member RunStore no longer owns through .runs" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The screens read run control from `app.runControl`

**Files:**
- Modify: `tests/ui/screens/tst_runs_screen.qml:1-7` (header), `:37` (`flashText`), `:75-94` (control and notify members), `:98-108` (`appC`), `:125-140` (`make()`), and every `s.runs.<control member>` (19 lines between `:753` and `:1003`)
- Modify: `tests/ui/screens/tst_run_detail_screen.qml:1-6` (header), `:36` (`flashText`), `:43-53` (control members), `:57-70` (`appC`), `:74-90` (`make()`), `:401-440` (7 lines)
- Modify: `ui/screens/RunsScreen.qml:242`, `:322-323`, `:343-345`, `:570-573`
- Modify: `ui/screens/RunDetailScreen.qml:161`, `:224-227`, `:317`
- Modify: `ui/screens/CardDetailScreen.qml:50`, `:290-293`
- Modify: `tests/ui/screens/tst_card_detail_screen.qml:451-454`, `:470-471`, `:502`
- Modify: `tests/architecture/test_run_store_callers.py` (`UNMIGRATED`)

**Interfaces:**
- Consumes: `UNMIGRATED` from Task 1.
- Produces: the screens read `app.runControl.{pending, stillWaiting, stillWaitingText, lastControlError, lastControlErrorRunId, flashText, notifyOnEscalation}` and call `app.runControl.control(action, id)` and `app.runControl.setNotifyOnEscalation(on)`. A stub app for these screens therefore needs a `runControl` object. In both stub tests, `make()` returns `{ …, control: <the control stub> }`.

- [ ] **Step 1: Split the `tst_runs_screen.qml` stub (the failing test)**

In `tests/ui/screens/tst_runs_screen.qml`:

Replace the header lines 2-7:

```qml
// ui/screens/RunsScreen.qml on its own: the rows it renders, the chips, the
// footer and banners, and the empty and missing states. A stub app: a REAL
// NavigationStore, plus a plain object carrying the RunStore properties the
// screen reads (the real store's `watching` is a read-only alias that cannot
// be set from a test), filtered through the same domain functions the store
// uses. The navigator is a recorder.
```

with:

```qml
// ui/screens/RunsScreen.qml on its own: the rows it renders, the chips, the
// footer and banners, and the empty and missing states. A stub app: a REAL
// NavigationStore, plus plain objects carrying the RunStore properties and,
// apart, the RunControlStore properties the screen reads (the real store's
// `watching` is a read-only alias that cannot be set from a test); the run
// list is filtered through the same domain functions the store uses. The
// navigator is a recorder.
```

Delete line 37 of `runsC`, `      property string flashText: ""` (it sits between `property string watchSchemaError: ""` and the `// The current watch's hello` comment).

Replace the end of `runsC` (from the `onRunsChanged:` line through the component's closing braces):

```qml
      onRunsChanged: if (rs.projectFilter !== "" && !rs.hasRoot(rs.projectFilter)) rs.projectFilter = ""
      // The control surface the rows read (S2 4.2). `control` only records.
      property var pending: ({})
      property var stillWaiting: ({})
      readonly property string stillWaitingText: "still waiting — the run may be between phases or dead"
      property string lastControlError: ""
      property string lastControlErrorRunId: ""
      property var controlCalls: []
      function control(action, id) {
        rs.controlCalls = rs.controlCalls.concat([action + "|" + id])
        return true
      }
      // The Notify on escalation switch (S2 4.4). `setNotifyOnEscalation`
      // only records.
      property bool notifyOnEscalation: false
      property var notifyCalls: []
      function setNotifyOnEscalation(on) {
        rs.notifyCalls = rs.notifyCalls.concat([on])
        return true
      }
    }
  }
```

with:

```qml
      onRunsChanged: if (rs.projectFilter !== "" && !rs.hasRoot(rs.projectFilter)) rs.projectFilter = ""
    }
  }

  Component {
    id: controlC
    QtObject {
      id: rc
      property string flashText: ""
      // The control surface the rows read (S2 4.2). `control` only records.
      property var pending: ({})
      property var stillWaiting: ({})
      readonly property string stillWaitingText: "still waiting — the run may be between phases or dead"
      property string lastControlError: ""
      property string lastControlErrorRunId: ""
      property var controlCalls: []
      function control(action, id) {
        rc.controlCalls = rc.controlCalls.concat([action + "|" + id])
        return true
      }
      // The Notify on escalation switch (S2 4.4). `setNotifyOnEscalation`
      // only records.
      property bool notifyOnEscalation: false
      property var notifyCalls: []
      function setNotifyOnEscalation(on) {
        rc.notifyCalls = rc.notifyCalls.concat([on])
        return true
      }
    }
  }
```

In `appC`, under `property var runs: null`, add:

```qml
      property var runControl: null
```

In `make(list)`, replace:

```qml
    var app = appC.createObject(host, { nav: nav, runs: runs })
    var navi = naviC.createObject(host)
```

with:

```qml
    var control = controlC.createObject(host)
    var app = appC.createObject(host, { nav: nav, runs: runs, runControl: control })
    var navi = naviC.createObject(host)
```

and replace its return line:

```qml
    return { app: app, runs: runs, nav: nav, navi: navi, screen: screen }
```

with:

```qml
    return { app: app, runs: runs, control: control, nav: nav, navi: navi, screen: screen }
```

Move the tests' reads and writes to the control stub. Only these nine names are rewritten, and `s.runs.runs`, `s.runs.amStatus`, `s.runs.projectToggles` and the rest stay:

```bash
sed -E -i 's/\bs\.runs\.(pending|stillWaiting|stillWaitingText|lastControlError|lastControlErrorRunId|controlCalls|flashText|notifyOnEscalation|notifyCalls)\b/s.control.\1/g' tests/ui/screens/tst_runs_screen.qml
```

Check: `grep -nE 's\.runs\.(pending|stillWaiting|lastControlError|controlCalls|flashText|notifyOnEscalation|notifyCalls)' tests/ui/screens/tst_runs_screen.qml` prints nothing, and `grep -c 's\.control\.' tests/ui/screens/tst_runs_screen.qml` prints `23`. Also check that `runsC` no longer declares `flashText`, `pending`, `stillWaiting`, `stillWaitingText`, `lastControlError`, `lastControlErrorRunId`, `controlCalls`, `control`, `notifyOnEscalation`, `notifyCalls` or `setNotifyOnEscalation`, and that each now exists only in `controlC`.

- [ ] **Step 2: Split the `tst_run_detail_screen.qml` stub**

In `tests/ui/screens/tst_run_detail_screen.qml`:

Replace header lines 4-6:

```qml
// line. A stub app: a REAL NavigationStore, a plain object carrying the
// RunStore properties the screen reads (with recorders for selectAttempt and
// refreshLogs), and a board whose cardMap lends titles and brd statuses.
```

with:

```qml
// line. A stub app: a REAL NavigationStore, a plain object carrying the
// RunStore properties the screen reads (with recorders for selectAttempt and
// refreshLogs) and, apart, one carrying the RunControlStore properties it
// reads (with a recorder for control), and a board whose cardMap lends titles
// and brd statuses.
```

Delete line 36 of `runsC`, `      property string flashText: ""` (directly under `property string amStatus: "ok"`).

Replace the end of `runsC`:

```qml
      function refreshLogs() { rs.refreshed += 1 }
      // The control surface the header reads (S2 4.2). `control` only records.
      property var pending: ({})
      property var stillWaiting: ({})
      readonly property string stillWaitingText: "still waiting — the run may be between phases or dead"
      property string lastControlError: ""
      property string lastControlErrorRunId: ""
      property var controlCalls: []
      function control(action, id) {
        rs.controlCalls = rs.controlCalls.concat([action + "|" + id])
        return true
      }
    }
  }
```

with:

```qml
      function refreshLogs() { rs.refreshed += 1 }
    }
  }

  Component {
    id: controlC
    QtObject {
      id: rc
      property string flashText: ""
      // The control surface the header reads (S2 4.2). `control` only records.
      property var pending: ({})
      property var stillWaiting: ({})
      readonly property string stillWaitingText: "still waiting — the run may be between phases or dead"
      property string lastControlError: ""
      property string lastControlErrorRunId: ""
      property var controlCalls: []
      function control(action, id) {
        rc.controlCalls = rc.controlCalls.concat([action + "|" + id])
        return true
      }
    }
  }
```

In `appC`, under `property var runs: null`, add:

```qml
      property var runControl: null
```

In `make(list, selectedId, attempt)`, replace:

```qml
    var app = appC.createObject(host, { nav: nav, runs: runs })
    var sC = Qt.createComponent("../../../ui/screens/RunDetailScreen.qml")
```

with:

```qml
    var control = controlC.createObject(host)
    var app = appC.createObject(host, { nav: nav, runs: runs, runControl: control })
    var sC = Qt.createComponent("../../../ui/screens/RunDetailScreen.qml")
```

and its return line:

```qml
    return { app: app, runs: runs, nav: nav, screen: screen }
```

with:

```qml
    return { app: app, runs: runs, control: control, nav: nav, screen: screen }
```

Then:

```bash
sed -E -i 's/\bs\.runs\.(pending|stillWaiting|stillWaitingText|lastControlError|lastControlErrorRunId|controlCalls|flashText|notifyOnEscalation|notifyCalls)\b/s.control.\1/g' tests/ui/screens/tst_run_detail_screen.qml
```

Check: `grep -c 's\.control\.' tests/ui/screens/tst_run_detail_screen.qml` prints `9`. `s.runs.selected`, `s.runs.refreshed` and `s.runs.selectedAttempt` are untouched.

- [ ] **Step 3: Run the two stub suites to see them fail**

Run: `timeout 900 bash tests/run.sh tests/ui/screens/tst_run`
Expected: FAIL, and the run exits non-zero. `RunDetailScreen` shows 3 failures (`test_pause_goes_to_the_store_and_cancel_only_asks`, `test_the_flash_line_shows_only_while_there_is_a_flash` and `test_the_runs_own_error_and_waiting_lines`) and `RunDetailScreen.qml:161: TypeError: Property 'control' of object … is not a function`. `RunsScreen` shows about 21 failures, among them `test_pause_and_resume_go_to_the_store_and_do_not_open_the_run`, `test_the_error_and_waiting_lines_show_under_their_own_run_only`, `test_the_notify_switch_reads_and_asks_the_store`, `test_a_flash_takes_the_footer_and_then_gives_it_back` and the footer tests (the screen reads `app.runs.flashText`, which is now `undefined`), and `RunsScreen.qml:242: TypeError: … is not a function`. If they pass, a moved member was left on `runsC`: fix the stub, not the screen.

- [ ] **Step 4: Migrate the three screens and the card detail test**

Run the substitution block from "The substitution" with these files as its arguments:

```bash
CONTROL='pending|stillWaiting|stillWaitingText|lastControlError|lastControlErrorRunId|cancelRunId|cancelOpen|cancelText|cancelError|flashText|controlRunners|pendingTimer|flashTimer|notifyOnEscalation|notifySaved|notifyTouched|settingsLoadRunner|settingsSaveRunner|control|refusalOf|flash|openCancel|closeCancel|confirmCancel|setNotifyOnEscalation'
ALERTS='armedRoots|alertsArmed|toasts|toastMs|toastTimer|notifyRunners|raiseAlerts|expireToasts|dismissToast|dismissAllToasts|notify'
DISPATCH='dispatchState|dispatchTarget|dispatchTargetLabel|dispatchForm|dispatchPreview|dispatchError|dispatchErrorType|dispatchErrors|dispatchSuggest|dispatchRunId|dispatchMessage|dispatchLog|dispatchLogTail|dispatchExitCode|dispatchDefaultsRunner|dispatchPreviewRunner|dispatchDebounceTimer|dispatchStartRunners|dispatchStarted|openDispatch|closeDispatch|retargetToMilestone|setDispatchField|dispatchStart|checkDispatch'
sed -E -i \
  -e "s/\b(appStores|app)\.runs\.runSettingsRunner\b/\1.runControl.runSettingsLoadRunner/g" \
  -e "s/\b(appStores|app)\.runs\.($CONTROL)\b/\1.runControl.\2/g" \
  -e "s/\b(appStores|app)\.runs\.($ALERTS)\b/\1.runAlerts.\2/g" \
  -e "s/\b(appStores|app)\.runs\.($DISPATCH)\b/\1.runDispatch.\2/g" \
  ui/screens/RunsScreen.qml ui/screens/RunDetailScreen.qml ui/screens/CardDetailScreen.qml tests/ui/screens/tst_card_detail_screen.qml
```

Then `git diff ui/screens` must show exactly these changed lines and no others.

`ui/screens/RunsScreen.qml`:

```qml
    else screen.app.runControl.control(action, id)
      checked: screen.app.runControl.notifyOnEscalation
      onToggled: screen.app.runControl.setNotifyOnEscalation(!screen.app.runControl.notifyOnEscalation)
    visible: (!screen.amMissing && screen.app.runs.amStatus !== "schema") || screen.app.runControl.flashText !== ""
    text: screen.app.runControl.flashText !== ""
      ? screen.app.runControl.flashText
        pendingAction: ControlFacts.pendingOf(screen.app.runControl.pending, row.run)
        waiting: ControlFacts.waitingOf(screen.app.runControl.stillWaiting, row.run)
        waitingText: screen.app.runControl.stillWaitingText
        errorText: ControlFacts.errorOf(screen.app.runControl.lastControlError, screen.app.runControl.lastControlErrorRunId, row.run)
```

`ui/screens/RunDetailScreen.qml`:

```qml
    else screen.app.runControl.control(action, id)
      pendingAction: ControlFacts.pendingOf(screen.app.runControl.pending, screen.run)
      waiting: ControlFacts.waitingOf(screen.app.runControl.stillWaiting, screen.run)
      waitingText: screen.app.runControl.stillWaitingText
      errorText: ControlFacts.errorOf(screen.app.runControl.lastControlError, screen.app.runControl.lastControlErrorRunId, screen.run)
      text: screen.app.runControl.flashText
```

`ui/screens/CardDetailScreen.qml`:

```qml
    else detailCard.app.runControl.control(action, id)
        pendingAction: ControlFacts.pendingOf(detailCard.app.runControl.pending, runRow.run)
        waiting: ControlFacts.waitingOf(detailCard.app.runControl.stillWaiting, runRow.run)
        waitingText: detailCard.app.runControl.stillWaitingText
        errorText: ControlFacts.errorOf(detailCard.app.runControl.lastControlError, detailCard.app.runControl.lastControlErrorRunId, runRow.run)
```

`tests/ui/screens/tst_card_detail_screen.qml` (the real App) now reads `s.app.runControl.pending` (`:451`, `:471`), `s.app.runControl.controlRunners` (`:452-454`, `:470`) and `s.app.runDispatch.dispatchState` (`:502`). Its messages and values are unchanged.

`RunDetailScreen.outputAge()`'s `var store = screen.app.runs` stays: it reads only `logs*`.

- [ ] **Step 5: Remove the six migrated paths from the guard's `UNMIGRATED`**

In `tests/architecture/test_run_store_callers.py`, delete these six lines from `UNMIGRATED`:

```python
    "ui/screens/RunsScreen.qml",
    "ui/screens/RunDetailScreen.qml",
    "ui/screens/CardDetailScreen.qml",
    "tests/ui/screens/tst_runs_screen.qml",
    "tests/ui/screens/tst_run_detail_screen.qml",
    "tests/ui/screens/tst_card_detail_screen.qml",
```

- [ ] **Step 6: Run the screen suites and the guard**

Run: `timeout 900 bash tests/run.sh tests/ui/screens/`
Expected: pytest passes, with `test_run_store_callers.py` at `110 passed, 10 xfailed`, and every `tests/ui/screens/tst_*.qml` prints `Totals: … 0 failed` with no `TypeError` / `is not a function` line. The exit status is 0.

- [ ] **Step 7: Commit**

```bash
git add tests/architecture/test_run_store_callers.py tests/ui/screens/tst_runs_screen.qml tests/ui/screens/tst_run_detail_screen.qml tests/ui/screens/tst_card_detail_screen.qml ui/screens/RunsScreen.qml ui/screens/RunDetailScreen.qml ui/screens/CardDetailScreen.qml
git commit -m "refactor(runs): the run screens read run control from app.runControl, their stubs carry it apart" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Navigator and Shortcuts reach the owning stores

**Files:**
- Modify: `ui/Navigator.qml:389`, `:398`
- Modify: `ui/Shortcuts.qml:45`, `:51-52`, `:73-76`, `:126`
- Modify: `tests/ui/tst_navigator.qml:381`, `:401`
- Modify: `tests/ui/tst_shortcuts.qml` (67 lines, `:475-863`)
- Modify: `tests/architecture/test_run_store_callers.py` (`UNMIGRATED`)

**Interfaces:**
- Consumes: `UNMIGRATED` from Task 1 (as Task 2 left it).
- Produces: `Navigator.openStartedRun` / `openAwaitedRun` flash through `app.runControl.flash(text)`. `Shortcuts.closeRequested()`, `modalOpen()`, `runKey…` and the toast Escape read `app.runDispatch.dispatchState`, `app.runControl.cancelOpen` and `app.runAlerts.toasts`, and call the matching store.

- [ ] **Step 1: Make the guard strict for these four files (the failing test)**

Both suites use the real App, so they pass before and after this task through the shims. The guard is their red step. In `tests/architecture/test_run_store_callers.py`, delete these four lines from `UNMIGRATED`:

```python
    "ui/Navigator.qml",
    "ui/Shortcuts.qml",
    "tests/ui/tst_navigator.qml",
    "tests/ui/tst_shortcuts.qml",
```

- [ ] **Step 2: Run the guard to see it fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture/test_run_store_callers.py -q`
Expected: `4 failed`, namely `test_no_ui_file_reaches_a_moved_member_through_runs[ui/Navigator.qml]`, `[ui/Shortcuts.qml]`, `[tests/ui/tst_navigator.qml]` and `[tests/ui/tst_shortcuts.qml]`. Each failure lists its `path:line member -> owner` hits, for example `ui/Navigator.qml:389 flash -> runControl`. The rest show `110 passed, 6 xfailed`.

- [ ] **Step 3: Migrate the four files**

```bash
CONTROL='pending|stillWaiting|stillWaitingText|lastControlError|lastControlErrorRunId|cancelRunId|cancelOpen|cancelText|cancelError|flashText|controlRunners|pendingTimer|flashTimer|notifyOnEscalation|notifySaved|notifyTouched|settingsLoadRunner|settingsSaveRunner|control|refusalOf|flash|openCancel|closeCancel|confirmCancel|setNotifyOnEscalation'
ALERTS='armedRoots|alertsArmed|toasts|toastMs|toastTimer|notifyRunners|raiseAlerts|expireToasts|dismissToast|dismissAllToasts|notify'
DISPATCH='dispatchState|dispatchTarget|dispatchTargetLabel|dispatchForm|dispatchPreview|dispatchError|dispatchErrorType|dispatchErrors|dispatchSuggest|dispatchRunId|dispatchMessage|dispatchLog|dispatchLogTail|dispatchExitCode|dispatchDefaultsRunner|dispatchPreviewRunner|dispatchDebounceTimer|dispatchStartRunners|dispatchStarted|openDispatch|closeDispatch|retargetToMilestone|setDispatchField|dispatchStart|checkDispatch'
sed -E -i \
  -e "s/\b(appStores|app)\.runs\.runSettingsRunner\b/\1.runControl.runSettingsLoadRunner/g" \
  -e "s/\b(appStores|app)\.runs\.($CONTROL)\b/\1.runControl.\2/g" \
  -e "s/\b(appStores|app)\.runs\.($ALERTS)\b/\1.runAlerts.\2/g" \
  -e "s/\b(appStores|app)\.runs\.($DISPATCH)\b/\1.runDispatch.\2/g" \
  ui/Navigator.qml ui/Shortcuts.qml tests/ui/tst_navigator.qml tests/ui/tst_shortcuts.qml
```

Then `git diff ui/` must show exactly these lines and no others.

`ui/Navigator.qml`:

```qml
      navi.app.runControl.flash("Started — waiting for the run to appear")
    navi.app.runControl.flash("Started — opening the run when it appears")
```

`ui/Shortcuts.qml`. Line 45 is the Escape chain. Only its three run links change, and the order is kept:

```qml
    keys.app.deleter.deleteTarget ? keys.app.deleter.cancelDelete() : keys.app.board.archiveOpen ? keys.app.board.cancelArchive() : keys.app.memories.memoryDeleteOpen ? keys.app.memories.cancelMemoryDelete() : keys.app.memories.newMemoryOpen ? keys.app.memories.cancelNewMemory() : keys.app.milestones.dialogOpen ? keys.app.milestones.cancelDialog() : keys.app.runDispatch.dispatchState !== "idle" ? keys.app.runDispatch.closeDispatch() : keys.app.runControl.cancelOpen ? keys.app.runControl.closeCancel() : keys.app.runAlerts.toasts.length > 0 ? keys.app.runAlerts.dismissAllToasts() : (keys.app.nav.dropdownOpen ? keys.navigator.closeDropdown() : ((keys.app.nav.viewMode === "entry" || keys.app.nav.viewMode === "document" || keys.app.nav.viewMode === "memory" || keys.app.nav.viewMode === "issue" || keys.app.nav.viewMode === "run") ? keys.navigator.goBack() : keys.actions.close()))
```

```qml
              || keys.app.milestones.dialogOpen || keys.app.board.archiveOpen || keys.app.runControl.cancelOpen
              || keys.app.runDispatch.dispatchState !== "idle")
```

```qml
    var reason = keys.app.runControl.refusalOf(action, id)
    if (reason !== "") keys.app.runControl.flash(reason)
    else if (action === "cancel") keys.app.runControl.openCancel(id)
    else keys.app.runControl.control(action, id)
```

```qml
      if (keys.app.runAlerts.toasts.length > 0) keys.app.runAlerts.dismissAllToasts()
```

`:70` (`runById` / `selectedRunId` / `filteredRuns`) and `:90` (`amStatus`) stay on `keys.app.runs`.

`tests/ui/tst_navigator.qml:381` and `:401` read `n.app.runControl.flashText`. In `tests/ui/tst_shortcuts.qml`, `pending`, `flashText`, `cancelOpen`, `cancelRunId`, `closeCancel`, `openCancel` and `controlRunners` move to `s.app.runControl`, `raiseAlerts` and `toasts` move to `s.app.runAlerts`, and `dispatchState` and `openDispatch` move to `s.app.runDispatch`. The writes `s.app.runControl.cancelRunId = "run-0000000000a1"` (`:777`) and `s.app.runDispatch.dispatchState = "ready"` / `"starting"` (`:778`, `:836`, `:861`) now set the owning store directly, which is the state the shim's write-through reached. No message or value changes.

- [ ] **Step 4: Remove the four paths from `UNMIGRATED`**

Step 1 already deleted them. Confirm `UNMIGRATED` now holds exactly these five:

```python
UNMIGRATED = {
    "ui/Panel.qml",
    "tests/ui/tst_runs_flow.qml",
    "tests/ui/tst_dispatch_flow.qml",
    "tests/ui/tst_board_flow.qml",
    "tests/ui/tst_runs_real_data.qml",
}
```

- [ ] **Step 5: Run the guard and the two suites**

Run: `timeout 900 bash tests/run.sh tests/ui/tst_navigator && timeout 900 bash tests/run.sh tests/ui/tst_shortcuts`
Expected: pytest passes in each run, with `test_run_store_callers.py` at `114 passed, 6 xfailed`. Both suites print `Totals: … 0 failed` with no `TypeError` line, and the exit status is 0. The filter `tests/ui/tst_shortcuts` also runs `tst_shortcuts_delete.qml`, which must stay green.

- [ ] **Step 6: Commit**

```bash
git add tests/architecture/test_run_store_callers.py ui/Navigator.qml ui/Shortcuts.qml tests/ui/tst_navigator.qml tests/ui/tst_shortcuts.qml
git commit -m "refactor(runs): Navigator and Shortcuts reach run control, alerts and the dispatch on their own stores" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Panel connects to each store, and the flow suites follow

**Files:**
- Modify: `ui/Panel.qml:93-107` (the `Connections` split) and the 36 moved lines (`:103`, `:184`, `:240`, `:243`, `:274`, `:277-278`, `:295`, `:353`, `:356`, `:730`, `:756`, `:765`, `:781-782`, `:831-842`, `:902-926`)
- Modify: `tests/ui/tst_board_flow.qml:151-153` and `:168-280`
- Modify: `tests/ui/tst_dispatch_flow.qml:69-72` and the other moved lines
- Modify: `tests/ui/tst_runs_flow.qml` (67 lines)
- Modify: `tests/ui/tst_runs_real_data.qml:49-50`
- Modify: `tests/architecture/test_run_store_callers.py` (final form: `UNMIGRATED`, `caller_params()` and the `xfail` are removed)

**Interfaces:**
- Consumes: Task 1's guard, as Tasks 2 and 3 left it.
- Produces: nothing in `ui/` or `tests/ui/` reaches a moved member through `.runs.`, so 5.2 can delete the shims. `Panel` has three `Connections` blocks: `appStores.runs` (`onRunFilterToggled`, `onRunsChanged`), `appStores.runControl` (`onCancelOpenChanged`) and `appStores.runDispatch` (`onDispatchStarted`).

- [ ] **Step 1: Make the guard strict for everything (the failing test)**

Put `tests/architecture/test_run_store_callers.py` in its final form. Delete the whole `UNMIGRATED` block including its comment line, and delete `caller_params()`. Then change the two decorated tests back to:

```python
@pytest.mark.parametrize("path", caller_files(*CALLER_DIRS), ids=rel)
def test_no_ui_file_reaches_a_moved_member_through_runs(path):
    hits = [f"{rel(path)}:{n} {member} -> {MOVED[member]}" for n, member in moved_hits(path.read_text())]
    assert hits == []


def test_no_ui_connections_on_runs_handles_a_moved_signal():
    found = [f"{rel(p)}: {h}" for p in caller_files("ui", suffixes=(".qml",))
             for block in connections_blocks(p.read_text()) for h in moved_handlers(block)]
    assert found == []
```

The file is now byte-identical to the Step 1 content of Task 1. Check with `grep -cE 'UNMIGRATED|xfail|caller_params' tests/architecture/test_run_store_callers.py`, which must print `0`.

- [ ] **Step 2: Run the guard to see it fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture/test_run_store_callers.py -q`
Expected: `6 failed, 114 passed`. The failures are `test_no_ui_connections_on_runs_handles_a_moved_signal` (`ui/Panel.qml: onCancelOpenChanged`, `ui/Panel.qml: onDispatchStarted`) and the parametrized test for `ui/Panel.qml`, `tests/ui/tst_runs_flow.qml`, `tests/ui/tst_dispatch_flow.qml`, `tests/ui/tst_board_flow.qml` and `tests/ui/tst_runs_real_data.qml`.

- [ ] **Step 3: Split Panel's `Connections`**

In `ui/Panel.qml`, replace (`:98-107`):

```qml
  Connections {
    target: appStores.runs
    function onRunFilterToggled() { Qt.callLater(root.scrollToTop) }
    function onCancelOpenChanged() { root.focusForView() }
    function onDispatchStarted(runId) {
      appStores.runs.closeDispatch()
      navi.openStartedRun(runId)
    }
    function onRunsChanged() { navi.openAwaitedRun() }
  }
```

with:

```qml
  Connections {
    target: appStores.runs
    function onRunFilterToggled() { Qt.callLater(root.scrollToTop) }
    function onRunsChanged() { navi.openAwaitedRun() }
  }
  Connections {
    target: appStores.runControl
    function onCancelOpenChanged() { root.focusForView() }
  }
  Connections {
    target: appStores.runDispatch
    function onDispatchStarted(runId) {
      appStores.runDispatch.closeDispatch()
      navi.openStartedRun(runId)
    }
  }
```

The comment above (`// A different Runs chip means a different list: … the navigator still waits for.`) stays word for word. `onDispatchStarted` still closes the dialog first and navigates second.

- [ ] **Step 4: Replace the two `runSettings` writes by hand**

This must happen before the substitution, which does not handle them. In `tests/ui/tst_board_flow.qml:153` and `tests/ui/tst_dispatch_flow.qml:72`, replace:

```qml
    p.app.runs.runSettings = { verify: ["uv run pytest"] }
```

with:

```qml
    p.app.runControl.applyRunSettings(p.app.runs.project, { verify: ["uv run pytest"] })
```

Equivalently, as one command:

```bash
sed -i 's/p\.app\.runs\.runSettings = { verify: \["uv run pytest"\] }/p.app.runControl.applyRunSettings(p.app.runs.project, { verify: ["uv run pytest"] })/' tests/ui/tst_board_flow.qml tests/ui/tst_dispatch_flow.qml
```

Check: `grep -n 'applyRunSettings' tests/ui/*.qml` shows exactly `tst_board_flow.qml:153` and `tst_dispatch_flow.qml:72`, and `grep -rn 'runControl\.runSettings\b' tests/ui ui` prints nothing.

- [ ] **Step 5: Migrate Panel's other lines and the four flow suites**

```bash
CONTROL='pending|stillWaiting|stillWaitingText|lastControlError|lastControlErrorRunId|cancelRunId|cancelOpen|cancelText|cancelError|flashText|controlRunners|pendingTimer|flashTimer|notifyOnEscalation|notifySaved|notifyTouched|settingsLoadRunner|settingsSaveRunner|control|refusalOf|flash|openCancel|closeCancel|confirmCancel|setNotifyOnEscalation'
ALERTS='armedRoots|alertsArmed|toasts|toastMs|toastTimer|notifyRunners|raiseAlerts|expireToasts|dismissToast|dismissAllToasts|notify'
DISPATCH='dispatchState|dispatchTarget|dispatchTargetLabel|dispatchForm|dispatchPreview|dispatchError|dispatchErrorType|dispatchErrors|dispatchSuggest|dispatchRunId|dispatchMessage|dispatchLog|dispatchLogTail|dispatchExitCode|dispatchDefaultsRunner|dispatchPreviewRunner|dispatchDebounceTimer|dispatchStartRunners|dispatchStarted|openDispatch|closeDispatch|retargetToMilestone|setDispatchField|dispatchStart|checkDispatch'
sed -E -i \
  -e "s/\b(appStores|app)\.runs\.runSettingsRunner\b/\1.runControl.runSettingsLoadRunner/g" \
  -e "s/\b(appStores|app)\.runs\.($CONTROL)\b/\1.runControl.\2/g" \
  -e "s/\b(appStores|app)\.runs\.($ALERTS)\b/\1.runAlerts.\2/g" \
  -e "s/\b(appStores|app)\.runs\.($DISPATCH)\b/\1.runDispatch.\2/g" \
  ui/Panel.qml tests/ui/tst_runs_flow.qml tests/ui/tst_dispatch_flow.qml tests/ui/tst_board_flow.qml tests/ui/tst_runs_real_data.qml
```

Then check `ui/Panel.qml` against this list (`git diff ui/Panel.qml`):

- `:184` `: appStores.runControl.cancelOpen ? runCancelModal.focusItem`
- `:240` `appStores.runAlerts.dismissToast(key)`, and `:243` `appStores.runControl.flash("This run is no longer in the snapshot")`
- `:274` `readonly property bool dispatchOpen: appStores.runDispatch.dispatchState !== "idle"`
- `:277-278` `!!appStores.runDispatch.dispatchTarget` / `&& appStores.runDispatch.dispatchTarget.level === "subtask"`
- `:295` `var suggest = appStores.runDispatch.dispatchSuggest`
- `:353` `if (appStores.runDispatch.dispatchState === "starting") return`, and `:356` `appStores.runDispatch.openDispatch(board ? "board" : appStores.board.cardMap[target], appStores.board.cardMap)`
- `:730`, `:756`, `:765` `onCancelRequested: function(runId) { appStores.runControl.openCancel(runId) }`
- `:781-782` `toasts: appStores.runAlerts.toasts` / `onDismissRequested: function(key) { appStores.runAlerts.dismissToast(key) }`
- the cancel modal:

```qml
        shown: appStores.runControl.cancelOpen
        confirmWord: "cancel"
        message: "Cancel run " + Runs.shortId({ id: appStores.runControl.cancelRunId }) + "? Cancel is final. The run cannot be resumed, only relaunched; cards keep their current status. A phase in flight finishes first."
        detail: appStores.runs.runById(appStores.runControl.cancelRunId) ? Runs.runTitle(appStores.runs.runById(appStores.runControl.cancelRunId)) : ""
        confirmLabel: "Cancel run"
        dismissLabel: "Keep running"
        error: appStores.runControl.cancelError
        typedText: appStores.runControl.cancelText
        theme: panelTheme
        onTypedEdited: function(text) { appStores.runControl.cancelText = text }
        onConfirmRequested: appStores.runControl.confirmCancel()
        onCancelRequested: appStores.runControl.closeCancel()
```

  `runById` stays on `appStores.runs`.
- the dispatch dialog:

```qml
        dispatchState: appStores.runDispatch.dispatchState
        target: appStores.runDispatch.dispatchTarget
        targetTitle: root.dispatchCard ? String(root.dispatchCard.title || "") : ""
        targetLabel: appStores.runDispatch.dispatchTargetLabel
        form: appStores.runDispatch.dispatchForm
        preview: appStores.runDispatch.dispatchPreview
        error: appStores.runDispatch.dispatchError
        logPath: appStores.runDispatch.dispatchLog
        logTail: appStores.runDispatch.dispatchLogTail
        exitCode: appStores.runDispatch.dispatchExitCode
```

```qml
        onFieldEdited: function(name, value) { appStores.runDispatch.setDispatchField(name, value) }
        onStartRequested: appStores.runDispatch.dispatchStart()
        onCancelRequested: appStores.runDispatch.closeDispatch()
```

```qml
          if (appStores.runDispatch.retargetToMilestone()) root.dispatchCardId = milestoneId
```

- these stay on `appStores.runs`: `:252` and `:435` `runs`, `:262-263` the filters, and `:555` / `:559` `amStatus`.

In the flow suites, check the renames:

```bash
grep -n 'runSettingsLoadRunner\|settingsLoadRunner' tests/ui/tst_board_flow.qml tests/ui/tst_runs_real_data.qml tests/ui/tst_dispatch_flow.qml tests/ui/tst_runs_flow.qml
```

Every hit reads `p.app.runControl.settingsLoadRunner.cancel()` or `p.app.runControl.runSettingsLoadRunner.cancel()` (`tst_board_flow.qml:151-152`, `tst_runs_real_data.qml:49-50`, `tst_dispatch_flow.qml:69-70`, `tst_runs_flow.qml:54-55`, `:860-861`, `:908-909`). `p.app.runs.snapshotRunner.cancel()` and `p.app.runs.runs = …` stay.

- [ ] **Step 6: Run the guard and the full suite**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture -q`
Expected: all pass, with `test_run_store_callers.py` at `120 passed` and no xfail.

Run: `timeout 1500 bash tests/run.sh`
Expected: exit status 0, pytest all passed, and every `Totals:` line shows `0 failed`, with no `TypeError` / `ReferenceError` / `is not a function` line. These must pass unchanged in particular: `tst_runs_flow.qml::test_cancel_asks_for_the_typed_word_then_cancels_and_gives_the_focus_back` and `::test_a_cards_runs_row_cancel_opens_the_same_dialog_and_keep_running_closes_it` (`onCancelOpenChanged` on `runControl`), `tst_dispatch_flow.qml::test_a_start_whose_run_is_listed_opens_its_run_detail`, `::test_a_start_before_the_snapshot_waits_for_the_run_then_opens_it` and `::test_a_start_without_a_run_id_goes_to_the_runs_list_and_says_so` (`onDispatchStarted` on `runDispatch`), and `tst_runs_flow.qml`'s toast tests (`toasts` / `dismissToast` on `runAlerts`). If a dispatch test now shows default verify commands, Step 4 was skipped or `runControl.runSettings` was assigned.

- [ ] **Step 7: Commit**

```bash
git add tests/architecture/test_run_store_callers.py ui/Panel.qml tests/ui/tst_runs_flow.qml tests/ui/tst_dispatch_flow.qml tests/ui/tst_board_flow.qml tests/ui/tst_runs_real_data.qml
git commit -m "refactor(runs): Panel connects to run control and the dispatch on their own stores, the flow suites follow" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Self-review against the spec

- **Member map / every moved member reached on its owner:** the substitution's three alternations are the spec's three lists verbatim, and the guard's `MOVED` is the same set plus `runSettings` and `runSettingsRunner` (Tasks 1-4).
- **Renamed shims:** `runSettingsRunner` → `runSettingsLoadRunner` (the substitution's first rule, Task 4) and `runSettings = V` → `applyRunSettings(project, V)` (Task 4, Step 4). `runSettings` is read nowhere in `ui/` or `tests/ui/`.
- **Panel `Connections` split:** Task 4, Step 3, pinned by the `Connections` guard and the cancel/dispatch flow tests.
- **Every `ui/` file in scope:** Panel (Task 4), Shortcuts and Navigator (Task 3), and RunsScreen, RunDetailScreen and CardDetailScreen (Task 2). BoardScreen, GraphScreen and `ui/components/` reach no moved member, and the guard proves it.
- **Every `tests/ui` file:** the guard's Task 1 worklist is exactly the 9 test files and 6 ui files, all covered by Tasks 2-4.
- **Stub-app tests and their real red step:** Task 2, Steps 1-3. The red step was confirmed by a dry run: 3 failures in `RunDetailScreen`, 21 in `RunsScreen`.
- **Guard tests named in the spec:** `test_no_ui_file_reaches_a_moved_member_through_runs[<path>]`, `test_no_ui_connections_on_runs_handles_a_moved_signal` and `test_the_moved_set_is_not_empty_and_has_no_staying_member`, plus a helper self-test in the style of `test_layers.py::test_guard_helpers_flag_and_accept_what_they_should`.
- **Out of scope respected:** no `core/`, doc or README change, and none of the members missing at this commit gets code.
- **Dry run:** all four tasks' edits were applied to a scratch copy of `cced5e3`. The guard went to `120 passed`, and `bash tests/run.sh` exited 0.
<!-- task-pipeline: validated -->
