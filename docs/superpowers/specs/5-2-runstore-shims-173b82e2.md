# 5.2 RunStore shims removed — design

Card: `173b82e2` ("5.2 RunStore shims removed"). It is a subtask of story `97aa329f` "Retire the
RunStore shims". It is blocked by 5.1 `68b40cb3` ("ui callers use the new run stores"), which has
landed on this branch (`ba0457d`), and its sibling is 5.3 `e7709c33` ("Docs: the four run stores").
The parent design is `docs/superpowers/specs/2026-10-05-split-runstore-design.md`, cited below as
"P l.N". Line numbers into `core/` and `tests/` come from this card's start (`ba0457d`).

## Purpose

Subtasks 2.2, 3.1, 3.2, 4.1 and 4.2 moved the run alerts, the run controls, the dispatch and the
run settings out of `RunStore` into `RunAlertsStore`, `RunControlStore` and `RunDispatchStore`.
They left `RunStore` a shim of the same name for each moved member, read through three handles
that App sets (P l.122-127). 5.1 moved every `ui/` and `tests/ui/` caller to `app.runControl`,
`app.runAlerts` and `app.runDispatch`. This card does the rest (P l.128-130):

- `RunStore` declares none of the moved members and none of the three handles.
- App no longer sets the handles.
- Every test outside `tests/ui/` that still reaches a moved member through the run store reaches
  it on the store that owns it.
- An App test asserts that `RunStore` has none of the moved members, and that each of the three
  new stores is composed with its inputs (P l.129-130, l.163-164).

A user sees nothing different. No helper gets a different argv, and no process starts at a
different moment (P l.146-147). The full suite passes.

## Scope

### In scope

- `core/stores/RunStore.qml`: delete the three shim blocks and fix the header comment.
- `core/stores/App.qml`: delete the three handle lines and fix the comment above `runs`.
- `tests/core/stores/tst_app_runs.qml`: the new absence test, the composition assertions, and every
  `app.runs.<moved>` path.
- `tests/core/stores/tst_run_store.qml`: the shim test sections, the handle assignments in the
  wiring helpers, and every `store.<moved>` read in the remaining tests.
- `tests/core/stores/tst_run_control_store.qml`, `tst_run_alerts_store.qml` and
  `tst_run_dispatch_store.qml`: their handle assignments and the comments that name the handles.

### Out of scope

- **5.3** owns `docs/architecture.md` and `README.md`. That includes the shim paragraph at
  `docs/architecture.md:91` and the `app.runs` mentions at `:83` and `:167`. This card edits no doc
  apart from this spec and its plan.
- `ui/` and `tests/ui/`: 5.1 finished them, and `tests/architecture/test_run_store_callers.py`
  already guards them.
- `RunControlStore.qml`, `RunAlertsStore.qml` and `RunDispatchStore.qml`: no change. Their public
  members, inputs and signals stay as they are.
- No new member, signal or input on any store. No renamed member that stays.
- No change to what any remaining test expects. Only the store a test reads a member from changes,
  and the construction of the tests that exist only to test the shims (they are deleted, see
  "Tests").
- The members Appendix A lists as "not present at this commit" (P l.407-416). None of them exists,
  so there is nothing of theirs to delete.

## Inherited constraints

| constraint | source |
|---|---|
| Owners: `RunStore` = `app.runs`, `RunControlStore` = `app.runControl`, `RunAlertsStore` = `app.runAlerts`, `RunDispatchStore` = `app.runDispatch` | P l.52-57 |
| A store never imports or names a sibling; the shim handles were the one temporary exception, and the last story removes them | P l.46-50 |
| Every member lands in exactly one store; nothing is duplicated | P l.61-63 |
| Inputs come from App; each store gets only what it reads (the inputs table) | P l.71-79 |
| `RunStore`'s inputs include `project` (the open root) | P l.76 |
| The last story deletes the shims and the handles; an App test then asserts that `RunStore` has none of the moved members | P l.128-130 |
| No behaviour change, no new helper argv, no change to which process starts when | P l.146-147 |
| Tests move with their members; only construction and wiring change, never an expectation | P l.98-104 |
| `tests/architecture` stays green: store imports, no duplicated shared patterns, layer allowlists, icon glyph rules | P l.105-106; card |
| The last story: the App test asserts that the shims are gone | P l.163-164 |
| Docstrings and comments state the contract only, with no narrative | card |
| Verification: `bash tests/run.sh` green | card |

## The moved members

The set is `MOVED` in `tests/architecture/test_run_store_callers.py:15-79` (63 names). It is the
shim set at `core/stores/RunStore.qml:119-217`, the members of P Appendix A.1 whose target is not
`RunStore` and that exist at this commit:

- **Run control** (`RunStore.qml:119-166`): `pending`, `stillWaiting`, `stillWaitingText`,
  `lastControlError`, `lastControlErrorRunId`, `cancelRunId`, `cancelOpen`, `cancelText`,
  `cancelError`, `flashText`, `controlRunners`, `pendingTimer`, `flashTimer`,
  `notifyOnEscalation`, `notifySaved`, `notifyTouched`, `settingsLoadRunner`,
  `settingsSaveRunner`, `control`, `refusalOf`, `flash`, `openCancel`, `closeCancel`,
  `confirmCancel`, `setNotifyOnEscalation`, `runSettings`, `runSettingsRunner`.
- **Alerts** (`RunStore.qml:168-180`): `armedRoots`, `alertsArmed`, `toasts`, `toastMs`,
  `toastTimer`, `notifyRunners`, `raiseAlerts`, `expireToasts`, `dismissToast`,
  `dismissAllToasts`, `notify`.
- **Dispatch** (`RunStore.qml:182-217`): `dispatchState`, `dispatchTarget`, `dispatchTargetLabel`,
  `dispatchForm`, `dispatchPreview`, `dispatchError`, `dispatchErrorType`, `dispatchErrors`,
  `dispatchSuggest`, `dispatchRunId`, `dispatchMessage`, `dispatchLog`, `dispatchLogTail`,
  `dispatchExitCode`, `dispatchDefaultsRunner`, `dispatchPreviewRunner`, `dispatchDebounceTimer`,
  `dispatchStartRunners`, the signal `dispatchStarted`, `openDispatch`, `closeDispatch`,
  `retargetToMilestone`, `setDispatchField`, `dispatchStart`, `checkDispatch`.
- **The handles**: `controlStore`, `alertsStore`, `dispatchStore`.

Also deleted: the `Binding` objects and `on…Changed` handlers that served the writable shims
(`cancelRunId`, `cancelText`, `runSettings`, `dispatchState`), and the `Connections` that
re-emitted `dispatchStarted`.

Two shims have a different name on the store that owns them (5.1 spec, "The two shims whose names
differ"). A test that read them reads:

| shim on the run store | on `RunControlStore` |
|---|---|
| `runSettingsRunner` | `runSettingsLoadRunner` |
| `runSettings` (read) | `runSettingsOf(<run store>.project)` |
| `runSettings = X` (write) | `applyRunSettings(<run store>.project, X)` |

`RunControlStore.runSettings` is the `{root: settings}` map, not one project's settings. Never
compare one project's settings to it.

## Behaviour

### `core/stores/RunStore.qml`

- After the change, the file declares none of the names in "The moved members". Nothing else
  changes: every member that stays keeps its name, type, default and behaviour.
- `project` stays. It is a `RunStore` input (P l.76), and App reads it as `app.runs.project` to
  feed `runControl.project`, `runDispatch.project` and `runDispatch.runSettings`
  (`App.qml:138`, `:167`, `:170`). After the change no code inside `RunStore` reads it.
- The header comment states the contract of what is left. Two passages go:
  - `:13-14` "`project`, the open project, is read only by the run settings shims". It becomes a
    statement that `project` is the open project's root, held for App, and that the store itself
    reads it for nothing (for example "A project switch leaves the run list alone; `project`, the
    open project's root, is an input App hands on to the other run stores").
  - `:32-33` "The dispatch is RunDispatchStore's; its members here are shims through
    `dispatchStore`." It goes. The sentence after it ("Each applied list snapshot reply is
    announced per project (snapshotReplied).") stays.
  - The comment says nothing about shims, handles or the other three stores' members.

### `core/stores/App.qml`

- `runs` no longer sets `alertsStore`, `controlStore` or `dispatchStore` (`:114-116`).
- The comment above `runs` (`:103-106`) drops "and the stores its shims read (controlStore,
  alertsStore, dispatchStore)". It keeps the rest: the registry's roots and names in registry
  order, the selected project's root path, the panel-open flag.
- The `onSnapshotReplied` routing, `runControl`, `runAlerts` and `runDispatch` and their comments
  stay exactly as they are.

### Error paths

There are none new. Each shim had a fallback for a missing handle (an empty value, or a function
that returned `undefined`). With the shims gone, a caller that names a moved member on `app.runs`
gets `undefined` for a property, and a `TypeError` for a call. 5.1's guard keeps `ui/` and
`tests/ui/` from doing that, and the absence test below pins the result for every name.

## Tests

TDD order: the absence test is written first and fails (every shim still answers). Then the core
deletions make it pass. The rest of the suite is then moved off the shims so that it passes again.

### `tests/core/stores/tst_app_runs.qml` (QML unit tier, `qmltestrunner`)

This tier is right because the claims are about App's composed object graph. Only a real `App.qml`
instance shows which members `app.runs` answers to and what each new store is bound to.

New tests:

1. **`test_the_run_store_has_none_of_the_moved_members`.** For each of the 63 moved names and the
   three handle names, `typeof app.runs[name] === "undefined"`. It reports each name that is still
   there in one failure message (collect, then `compare(found, [])`), so a red run names every
   leftover. The list is written into the test, in the same order as `MOVED`.
   Against vacuity, the same test asserts that a few members that stay are defined:
   `runs`, `project`, `refresh`, `requestSnapshot`, `snapshotReplied`, `runsChanged`.
2. **`test_each_owner_answers_to_its_moved_members`.** For each moved name except the two renamed
   ones, `typeof app.<owner>[name] !== "undefined"`, where `<owner>` is `runControl`, `runAlerts`
   or `runDispatch` as listed in "The moved members". For `runSettingsRunner` the test checks
   `app.runControl.runSettingsLoadRunner`, and for `runSettings` it checks
   `app.runControl.runSettingsOf` and `applyRunSettings`. This shows that nothing was dropped
   (P l.61-63).

Changed tests:

3. **Composition tests** `test_app_composes_run_alerts_wired_to_the_run_store` (`:494`),
   `test_app_composes_run_control_wired_to_the_run_store` (`:551`) and
   `test_app_composes_run_dispatch_wired_to_the_run_store` (`:694`). Each drops its handle
   assertion (`:497`, `:554`, `:697`) and asserts every input of its store from P l.71-79 as App
   binds it (`App.qml:133-171`):
   - `runAlerts`: `backendDir`, `active`, `notifyOnEscalation` (follows
     `app.runControl.notifyOnEscalation`), `projectRoots` (`=== app.runs.projectRoots`). The test
     already asserts these (`:498-512`).
   - `runControl`: `backendDir`, `project` (follows `app.runs.project` across a selection change),
     `active` (follows `panelOpen`), `runs` (`=== app.runs.runs` after a snapshot).
   - `runDispatch`: `backendDir`, `project`, `active`, `runs`, and `runSettings`
     (`=== app.runControl.runSettingsOf(app.runs.project)` after the settings load replies).
   The test names keep "wired to the run store", because the inputs still come from `app.runs`.
   The assertions that each test already makes stay.
4. **Shim-equality assertions** `:524` (`app.runs.toasts === app.runAlerts.toasts`), `:577` and
   `:586` (`pending`), `:667` (`settingsLoadRunner`), `:710`, `:723`, `:778` and `:822`
   (`runSettings`). Each one compared a shim with its owner, so it is deleted. The owner-side
   assertion around it stays. `:710`, `:723`, `:778` and `:822` become
   `app.runDispatch.runSettings === app.runControl.runSettingsOf(app.runs.project)`, which is the
   binding they were proving.
5. **`test_a_write_to_the_run_store_shim_reaches_the_dispatch_form`** (`:817`). It tested the
   shim's write path, so it is deleted. `applyRunSettings` reaching the dispatch is the claim of
   `test_the_dispatch_reads_its_run_settings_from_run_control` (`:771`), which stays.
6. **Every other `app.runs.<moved>` path** in the file (`:178-184`, `:331-489`, `:709-727`, and
   any other hit for a moved name) goes to its owner, with the renames above. Each expectation and
   message stays as written.

### `tests/core/stores/tst_run_store.qml` (QML unit tier)

This is the run store's own suite. After the change it builds `RunStore` beside its three
siblings, wired the way App wires them, and reads each moved member on its owner.

- **Helpers.** `wireControl` (`:57-70`) and `wireAlerts` (`:89-100`) stop setting
  `store.controlStore` / `store.alertsStore`. Every other binding and connection stays. Their
  comments drop "store.controlStore set" and "store.alertsStore set". `controlOf(store)` and
  `alerts(store)` stay.
- **`wireDispatch`** (`:3707-3729`) moves up beside the other wiring helpers, together with
  `dispatchCards` (`:3689-3696`), because `test_a_project_switch_leaves_the_run_list_and_the_live_state_alone`
  (`:465`) uses it. It stops setting `store.dispatchStore`. It records its pair the way the other
  two do (`dispatchPairs`, read through a `dispatchOf(store)` helper). Its comment drops "set as
  `store`'s dispatchStore handle".
- **Reads in the tests that stay.** Every `store.<moved>` before the shim sections goes to its
  owner: `controlOf(store).X`, `alerts(store).X` or `dispatchOf(store).X`. That is 36 hits at this
  commit, among them `:301-367`, `:473-509`, `:534`, `:844-845`, `:1114-1151`, `:2688`, `:2790`
  (`toastIds`), `:2841`, `:3056-3082`, `:3184-3216`. The helpers that take a run store and read a
  moved member (for example `toastIds`) read it on the owner. No expectation changes.
- **Shim sections deleted.** These sections exist only to test the shims, and each claim they make
  is either gone or already pinned on the owner's own suite:
  - `:3467-3524` "the alerts shims" (3 tests).
  - `:3526-3646` "the run control shims": the 3 shim tests at `:3529`, `:3569` and `:3613`.
  - `:3731-3826` "the dispatch shims" (5 tests, including the re-emit test at `:3804`).
  - `:3828-3876` "the run settings shims" (3 tests).
- **Two tests in the control section stay, rewritten:**
  - `test_a_snapshot_settles_nothing_without_the_route` (`:3648`) keeps its claim (a snapshot
    alone settles nothing in run control). It drops `store.controlStore = c` and the last line
    `compare(store.pending.r1, "pause")`. `compare(c.pending.r1, "pause", …)` stays.
  - `test_opening_the_run_store_alone_reads_no_switch` (`:3670`) keeps its claim (the run store
    opened alone launches no settings read, and it still snapshots). The three shim reads
    (`settingsLoadRunner`, `settingsSaveRunner`, `notifyOnEscalation` on the run store) become
    one assertion per name that `typeof store[name] === "undefined"`. The snapshot assertions
    stay.
  - Their section heading comment becomes one that names the claim, not the shims
    (for example "the run store alone").
- **`test_closing_and_switching_the_run_store_touch_no_dispatch`** (`:3814`) keeps its claim. Its
  `store.openDispatch(...)` becomes `d.openDispatch(...)`, and the test moves with
  `wireDispatch`.

### `tests/core/stores/tst_run_control_store.qml`, `tst_run_alerts_store.qml`, `tst_run_dispatch_store.qml` (QML unit tier)

- `tst_run_control_store.qml:541` (`store.controlStore = c` in `wireControl`),
  `tst_run_alerts_store.qml:318` (`store.alertsStore = a` in `wireAlerts`) and
  `tst_run_dispatch_store.qml:52` (`store.controlStore = c`) are deleted. The comments that name
  them (`tst_run_control_store.qml:532`, `tst_run_alerts_store.qml:310`,
  `tst_run_dispatch_store.qml:40`, "The run store's dispatchStore handle is not set") drop the
  handle wording.
- No test in these files reads a moved member through a run store at this commit. A grep for
  `\.(<moved>)\b` on a run store variable must stay empty after the change.

### `tests/architecture` (pytest tier)

No new test. `test_run_store_callers.py` keeps guarding `ui/` and `tests/ui/`. The whole directory
must stay green (P l.105-106).

### Full suite

`bash tests/run.sh` passes: pytest, then every `tst_*.qml` under `qmltestrunner` (offscreen).

## Acceptance

1. `core/stores/RunStore.qml` declares none of the 63 moved names and none of the three handles,
   and no comment in it mentions shims or the handles.
2. `core/stores/App.qml` sets no handle on `runs`, and no comment in it mentions shims.
3. A grep of `core/`, `ui/` and `tests/` for `controlStore`, `alertsStore` and `dispatchStore`
   finds only test helper function names (`tst_run_dispatch_store.qml`'s `dispatchStore()`) and
   this card's absence test list.
4. `tst_app_runs.qml` has the absence test and the owner test, and the three composition tests
   assert each store's inputs.
5. `bash tests/run.sh` is green.

## Review focus for the planner

- **`in` versus `typeof`.** QML's `in` on a `QObject` wrapper is not a reliable absence check. Use
  `typeof app.runs[name] === "undefined"`. None of the 66 names collides with a `QObject` built-in
  (`objectName`, `destroyed`, `deleteLater`, `toString`), so `typeof` is exact.
- **A missed `store.<moved>` read in `tst_run_store.qml`.** A read of a deleted property returns
  `undefined`. `compare(store.toasts.length, 0)` throws, but a negative check such as
  `verify(!store.alertsArmed)` or `compare(store.pending.r1, undefined)`-style reads can pass by
  accident. After the edit, grep the file for every moved name on a run store variable and expect
  no hit.
- **`wireDispatch` callers.** It is used at `:467` before its definition section. When the shim
  section is deleted, it must survive, moved up with `dispatchCards`.
- **`runSettings` renames.** Any assertion that compared one project's settings to
  `RunControlStore.runSettings` (the map) is wrong. Use `runSettingsOf(project)`.
- **The `project` header comment.** `project` must stay a declared input even though `RunStore`
  reads it for nothing after the change. Deleting it would break App's bindings at `App.qml:138`,
  `:167` and `:170`.
