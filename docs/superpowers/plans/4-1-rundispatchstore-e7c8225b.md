# 4.1 RunDispatchStore: the dispatch state machine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the S3/S7 dispatch state machine out of `RunStore` into a new `core/stores/RunDispatchStore.qml` composed by App as `app.runDispatch`, with its cross-concern calls turned into App-routed signals and stateless shims left on `RunStore`, with no behaviour change.

**Architecture:** `RunDispatchStore` (`id: dispatch`) gets the dispatch members verbatim (`store.` → `dispatch.`), five inputs (`backendDir`, `project`, `active`, `runs`, `runSettings`), three new out-signals (`refreshRequested`, `noticeRequested`, `runSettingsUpdated`) replacing `store.refresh()`, `store.flash(...)` and `store.runSettings = settings`, and its own `onActiveChanged` / `onProjectChanged` reactions replacing the lines in `stopLive` / `projectSwitched`. `RunStore` loses those members and gains shims through a new `dispatchStore` handle (a writable `dispatchState`, read-only properties, six one-line function forwards, a re-emitted `dispatchStarted`). App composes and routes. The 59 dispatch tests move to a new test file with a harness wired the way App wires the store.

**Tech Stack:** QML (Qt 6, Quickshell), qmltestrunner with stubs in `tests/stubs`, pytest (architecture tests). Everything runs through `bash tests/run.sh [filter]` — pytest runs first (about 2 minutes), then each QML test file whose path contains the filter. Wrap it in `timeout 900`.

**Spec:** `docs/superpowers/specs/4-1-rundispatchstore-e7c8225b.md` (reproduced verbatim right below, before the tasks).

## Global Constraints

- Pure refactor: no behaviour change, no renamed public member, no new helper argv, no change to which process starts when, no UI change.
- Every member lands in exactly one store; nothing duplicated, nothing dropped unless no code or test reads it. (Task 1 leaves a temporary duplicate in `RunStore` that Task 2 removes in the same branch.)
- No duplicated helpers: replies are read with `Results.parseEnvelope`, maps handled with `Runs.copyMap` / `Runs.hasKey`, imported from `core/domain/`.
- `RunDispatchStore.qml` imports only `QtQml`, `Quickshell`, `Quickshell.Io`, `"../domain/results.js" as Results` and `"../domain/runs.js" as Runs` (`tests/architecture/test_layers.py:133`).
- `RunDispatchStore` inputs are exactly `backendDir`, `project`, `active`, `runs`, `runSettings`; no `dispatchRoot`, `projectRoots` or `cardMap` input (the card map stays an argument of `openDispatch`).
- `RunDispatchStore` never assigns its own `runSettings`; an ok start emits `runSettingsUpdated(settings)` and App writes `app.runs.runSettings`.
- An ok start of this dispatch keeps the order: run id + message, settings computed, `runSettingsUpdated(settings)`, `dispatchState = "started"`, `refreshRequested("all")`, `dispatchStarted(id or null)`; then the same runner launches `set-run-settings`.
- A store never imports or names a sibling; the one exception is the shim handle `RunStore.dispatchStore` (like `controlStore` / `alertsStore`).
- Shims: under the single comment `// Moved to RunDispatchStore; removed by the last story`; property shims bind through the handle and notify like the original; `dispatchState` is writable following the `cancelText` pattern; function shims are one-line forwards returning the target's result (`undefined` without a handle); `dispatchStarted` is re-emitted by `RunStore` only (App adds no second route); no state, no logic; every shim checks `store.dispatchStore` first.
- Only six function shims: `openDispatch`, `closeDispatch`, `retargetToMilestone`, `setDispatchField`, `dispatchStart`, `checkDispatch`.
- `runSettings`, `runSettingsRunner`, `applyRunSettings` and the `get-run-settings` reload stay in `RunStore` unchanged in body (card 4.2). The per-Start `set-run-settings` write stays on the start runner.
- Tests move with their members; only construction and input wiring change, never an expectation (see "Notes on the spec" for the one census line that must follow the moved timer).
- `ui/` and `tests/ui/` are untouched: `git diff --stat 7676feb -- ui tests/ui` is empty.
- Docstrings and comments state the contract only, with no narrative.
- Gate: `bash tests/run.sh` green — pytest (incl. `tests/architecture`), then every qmltestrunner file, with no `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign` or `is not a function` in the output.

## Notes on the spec

Two lines in the tests that stay in `tst_run_store.qml` read the dispatch, which the spec's "Test wiring changes" asks the planner to find:

1. `test_a_project_switch_leaves_the_run_list_and_the_live_state_alone` ends with `compare(store.dispatchState, "idle", "and the dispatch is still reset")`. It is a project-switch test, not a dispatch test, so it stays and is given the handle with `wireDispatch(store, true)` (the spec's prescribed fix). Its expectation is unchanged.
2. `test_logs_add_no_timer_and_none_runs_while_idle` lists `RunStore`'s own `Timer` children: `"debounceTimer,dispatchDebounceTimer,livenessTimer,pollTimer,staleTimer"`. `dispatchDebounceTimer` is a member that moves, so after the move it is no longer a child of `RunStore` and the list becomes `"debounceTimer,livenessTimer,pollTimer,staleTimer"`. This is the one expected string that changes; the timer itself is pinned on its new owner (D-N1 and moved test 16, `test_change_restarts_400ms_debounce_and_one_preview_per_burst`, which checks `objectName`, 400 ms and one-shot). The reviewer should accept it as the census following the member, not as a weakened expectation.

The spec's redirect table counts `runSettingsRunner` 10 and `snapshotRunner` 12; the moved bodies actually hold 14 `runSettingsRunner` reads (11 on `store`, one each on `back`, `bare`, `keyed`). The move script asserts the real totals: 43 RunStore redirects and 5 RunControlStore redirects.

The spec lists `entry` among the helpers to copy; no moved body or new test calls it (`okReply([])` does not), so it is not copied.

## Review Focus

1. **A ui test writes `app.runs.dispatchState`** (`tests/ui/tst_shortcuts.qml:778, 836, 861`, `tests/ui/tst_dispatch_flow.qml:203`): the write must reach the dispatch store, a later `closeDispatch()` must see `"starting"` and refuse, and the shim must follow the store afterwards; a read-only shim would print `Unable to assign` → R-D3 in Task 2, plus the untouched ui suites in the gate.
2. **`dispatchStarted` delivered twice or not at all**: exactly once on `app.runs`, so Panel closes the dialog once and opens the run once → R-D4 and A-D3 in Task 2.
3. **The dispatch store writes its own `runSettings`**: that would break App's binding and leave the old project's settings in the next form → D-N5 in Task 1 and A-D2 in Task 2.
4. **A RunStore with no dispatch handle opens, closes or switches projects** (every `tst_run_store.qml` / `tst_run_alerts_store.qml` builder): no `TypeError`, shims read empty values; and a leftover `closeDispatch()` / `resetDispatch()` in `stopLive` / `projectSwitched` must not reach a handle → R-D1 and R-D5 in Task 2.
5. **The panel closes while a start is in flight, through App**: the start stays `starting` and lands normally (the store's own `active` reaction goes through `closeDispatch`, which refuses, not `resetDispatch`) → D-N2 in Task 1 and A-D5 in Task 2.

---

## Spec (verbatim)

> # 4.1 RunDispatchStore: the dispatch state machine — design
>
> Card: `e7c8225b` ("4.1 RunDispatchStore: the dispatch state machine"), a subtask of story
> `d11a4680` "Extract RunDispatchStore". Its sibling 4.2 (`e6d2e50e`, "Dispatch run settings
> through RunControlStore") comes after it. Parent design:
> `docs/superpowers/specs/2026-10-05-split-runstore-design.md`, cited below as "P l.N". Line numbers
> into `core/stores/RunStore.qml` (1557 lines), `core/stores/App.qml` (167 lines) and the test files
> come from the files at the start of this card (commit `7676feb`). Appendix A's line numbers
> (P l.168) come from an older 2038-line file. This spec cites Appendix A rows only by their own
> line in the parent spec.
>
> ## Purpose
>
> This card is a pure refactor. The S3/S7 dispatch state machine moves out of `RunStore` into a
> new `core/stores/RunDispatchStore.qml`, composed by App as `app.runDispatch` (P l.57). The move
> covers:
>
> - the state, the form, the debounced preview, the default-branch lookup, `dispatchStart` with its
>   per-Start runner, the S7 story target and `retargetToMilestone`, and `dispatchStarted(runId)`;
> - the runners and the timer that go with them.
>
> The calls into other concerns become signals that App routes (P l.79, A.3 P l.436-437, 443-446).
> `RunStore` keeps stateless shims under the old names (P l.122-127), so `ui/` and `tests/ui/` do
> not change.
>
> Nothing a user can see or a helper can receive changes. The same argv launches at the same
> moments under the same guards. The same values land, the same sentence flashes, and
> `dispatchStarted` reaches Panel, and through it the Navigator, exactly as it does today.
>
> ## Scope: what the card names that does not exist
>
> The card, and P l.57 and l.79, name members that the queued milestones would have added. None of
> them is in the repository at `7676feb`. `grep -rE 'dispatchRoot|dispatchStep|dispatchOpenFromRuns|relaunch|board-tree'`
> over `core/`, `ui/` and `tests/` finds nothing, and Appendix A's A.2 (P l.411-414) records the same
> thing: "not in `RunStore.qml` at this commit; mapped whole when it lands". This card moves only
> what exists, and it invents none of the following:
>
> | named by the card or P l.79 | at this commit | this card |
> |---|---|---|
> | `dispatchRoot` | absent | not added |
> | `// ---- dispatch: project and target steps` (`dispatchStep`, `dispatchOpenFromRuns`, `dispatchBack`, `dispatchProject*`, `dispatchTarget*`, two `board-tree.py` runners) | absent | not added |
> | `// ---- relaunch` (`relaunchOpenFor`, `relaunch*`) | absent | not added |
> | `projectRoots` input ("read by the project step") | the project step is absent, so nothing would read it | not added: an input nothing reads is new surface (P l.146-148) |
> | `cardMap` input (`app.board.cardMap`) | the card map is an **argument** of `openDispatch(card, cardMap)` (RunStore.qml 1093) and is kept in `dispatchBook.cardMap` | not added: the argument stays exactly as it is |
> | "a start asking for `[dispatchRoot]` only" / "`tst_app_runs.qml` pins started → re-snapshot of `dispatchRoot` only" | a start re-snapshots **every usable root** (`store.refresh()`, RunStore.qml 1352), pinned by `tst_run_store.qml::test_a_dispatch_start_refreshes_every_usable_root` (3586) and `tst_app_runs.qml::test_a_dispatch_start_through_app_snapshots_every_registered_root` (374) | `refreshRequested("all")`; the App pin stays "every registered root" (A.3 P l.443-444). Narrowing it to one root would change behaviour, which P l.146 forbids. |
>
> When Dispatch from the Runs screen or Resume and recover land, they land in `RunDispatchStore`
> (P l.132-142). That is their work, not this card's.
>
> ## Scope: what this card leaves to siblings
>
> - **Run settings I/O (card 4.2).** `runSettings`, `runSettingsRunner`, `applyRunSettings`, the
>   `runSettings = {}` reset and the `get-run-settings` reload in `projectSwitched` (RunStore.qml
>   179, 1052-1055, 664-671, 1417-1421) all stay in `RunStore`, unchanged in body. The 3.2 spec
>   (`3-2-runcontrolstore-run-e546c85f.md`, "Scope") left them there for 4.2 too.
>   `runSettingsWanted(root)`, `runSettingsSaveRequested(root, patch)` and
>   `RunControlStore.loadRunSettings` / `saveRunSettings` are 4.2's work.
> - **The per-Start settings write.** This card moves it as it is: after an ok start, the
>   `dispatchStartC` runner itself runs `viewer-state.py set-run-settings` (RunStore.qml 1355-1357).
>   The card's "settings runners moved as they are" means this runner. 4.2 replaces it with
>   `runSettingsSaveRequested`.
> - **Moving `ui/` and `tests/ui/` callers to `app.runDispatch`, and deleting the shims.** That is
>   the last story's work (P l.128-131).
> - **Rewriting `docs/architecture.md` into one paragraph per store.** That is a later docs card.
>   This card only edits the sentences it makes false (see "Docs").
>
> ## Inherited constraints
>
> - Every member lands in exactly one store. Nothing is duplicated, and nothing is dropped unless
>   no code or test reads it (P l.61-67). This includes the A.1 rows P l.235-249, 270-273, 361-380,
>   386-387, 395, 401 and 404.
> - No duplicated helpers. Replies are read with `Results.parseEnvelope`, and maps are handled with
>   `Runs.copyMap` / `Runs.hasKey`, imported from `core/domain/` (P l.68-71). The new store imports
>   only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain/*.js`
>   (`tests/architecture/test_layers.py:133`).
> - Inputs come from App, and each store gets only what it reads (P l.72-79). A store never imports
>   or names a sibling (P l.46-50). The shim handle `RunStore.dispatchStore` is the one temporary
>   exception, following `controlStore` / `alertsStore`.
> - Cross-concern calls become App-routed signals (P l.80-91, A.3 P l.436-437, 443-446).
> - Lifecycle stays per store. `stopLive`'s `closeDispatch()` becomes the dispatch store's own
>   `active` reaction (A.3 P l.436). `projectSwitched`'s `resetDispatch()` becomes its own
>   `project` reaction (A.3 P l.437). `dispatchDebounceTimer` keeps its behaviour (P l.92-97).
> - Shims (P l.122-127):
>   - A property shim is a binding through the handle, and it notifies like the original.
>   - A function shim is a one-line forward that returns the target's result.
>   - A signal shim is re-emitted.
>   - Shims hold no state and no logic.
>   - The only comment above them is `// Moved to RunDispatchStore; removed by the last story`.
> - Tests move with their members. Only construction and the wiring of inputs change, never an
>   expectation. A test that crosses two concerns is pinned at App level (P l.98-104, l.152-164).
> - `tests/architecture` stays green (P l.105-106).
> - No behaviour change, no renamed public member, no new helper argv, no change to which process
>   starts when, and no UI change (P l.146-150).
> - From the card:
>   - `bash tests/run.sh` is green;
>   - TDD: tests first;
>   - docstrings and comments state the contract only, with no narrative;
>   - `tests/ui` passes untouched.
>
> ## The members that move
>
> Every row leaves `RunStore.qml` and lands in `RunDispatchStore.qml`. The body is unchanged except
> for these edits:
>
> - `store.` becomes `dispatch.`, the new store's root id.
> - The calls listed under "Couplings that become signals" change.
>
> | member | RunStore.qml today | Appendix A row |
> |---|---|---|
> | the dispatch comment block | 181-186 | into the store's contract comment |
> | `dispatchState` … `dispatchExitCode` (14 properties) | 187-200 | P l.235-248 |
> | `signal dispatchStarted(var runId)` and its comment | 201-203 | P l.249 |
> | aliases `dispatchDefaultsRunner`, `dispatchPreviewRunner`, `dispatchDebounceTimer`, `dispatchStartRunners` (→ `dispatchBook.runners`) | 229-232 | P l.270-273 |
> | `// ---- dispatch (S3 3.1)` section: `clearDispatchError`, `resetDispatch`, `openDispatch`, `closeDispatch`, `blockedSuggest`, `retargetToMilestone`, `withField`, `dispatchTargetArgs`, `dispatchCommands`, `dispatchOptionArgs`, `dispatchDefaultsReplied`, `checkDispatch`, `dispatchPreviewReplied`, `setDispatchField`, `mergedPrefixes`, `dispatchStart`, `isHereStart`, `dispatchStartReplied`, `dispatchSaveReplied`, `dropStartRunner` | 1057-1392 | P l.361-380 |
> | `HelperRunner dispatchDefaultsRunner` (`runs/dispatch-preview.py`, `guard: dispatch.project`) | 1423-1429 | P l.386 |
> | `HelperRunner dispatchPreviewRunner` (same script, same guard) | 1431-1437 | P l.387 |
> | `Timer dispatchDebounceTimer` (400 ms, `objectName` kept) | 1478-1485 | P l.395 |
> | `QtObject dispatchBook` and its comment | 1504-1518 | P l.401 |
> | `Component dispatchStartC` (`runs/start-run.py`, `guard: ""`, `madeFor`, `savedJson`, `saving`) and its comment | 1520-1539 | P l.404 |
>
> These stay in `RunStore`, apart from the edits listed:
>
> - `runSettings` and its whole I/O (card 4.2);
> - `stopLive`, minus its last two lines (`// A start in flight refuses and lands normally.` /
>   `store.closeDispatch()`, 387-388). Its comment drops "and no dispatch outlives the opening (a
>   start in flight runs to its end)".
> - `projectSwitched`, minus its dispatch lines (665-667). Its comment's "Reset: the run settings …
>   and the dispatch" becomes "Reset: the run settings (loaded for the new project on
>   runSettingsRunner)".
>
> ## Behaviour: `RunDispatchStore`
>
> ### Inputs and signals
>
> The file header follows `RunControlStore.qml`: the same three imports and the two domain imports,
> then `Scope { id: dispatch`.
>
> | member | kind | App binds / routes | contract |
> |---|---|---|---|
> | `backendDir` | `property string`, `""` | `app.backendDir` | `<plugin>/core/backend/` |
> | `project` | `property string`, `""` | `app.runs.project` | the open project's root; `""` when none is open |
> | `active` | `property bool`, `false` | `app.panelOpen` | the panel is open |
> | `runs` | `property var`, `[]` | `app.runs.runs` | the run store's merged run list, read by `Runs.dispatchDefaults` |
> | `runSettings` | `property var`, `({})` | `app.runs.runSettings` | the open project's run settings; the store never writes it |
> | `refreshRequested(var roots)` | signal | `"all"` → `app.runs.refresh()`, else `app.runs.requestSnapshot(roots)` (as `runControl`, App.qml 136-139) | a re-snapshot is wanted; this store only ever asks for `"all"` |
> | `noticeRequested(string text)` | signal | `app.runControl.flash(text)` | a sentence for the footer flash |
> | `runSettingsUpdated(var settings)` | signal | `app.runs.runSettings = settings` | after a start of this dispatch: the open project's run settings as that start saves them |
> | `dispatchStarted(var runId)` | signal | none (the RunStore shim re-emits it; see below) | unchanged |
>
> `runSettingsUpdated` is this card's stand-in for the old direct write
> `store.runSettings = settings` (RunStore.qml 1350, A.3 P l.445). The store must not assign to its
> own `runSettings`: that would break App's binding, and a later project switch would then leave
> the old project's settings in the dispatch form. Card 4.2 replaces this signal with
> `runSettingsSaveRequested`.
>
> ### Unchanged from RunStore
>
> Every behaviour that the moved tests pin holds as it does today, read against this store's own
> inputs:
>
> - the state machine `idle → previewing → ready / refused → starting → started / failed`;
> - every argv, its element count and its `launchGuard`;
> - the 400 ms debounce, with one preview per burst;
> - the `--defaults` lookup, once per opening, which a user-set base beats;
> - the target label, the S7 story target, the `StoryBlockedError` suggestion and
>   `retargetToMilestone`, which goes once to the milestone recorded at the opening;
> - the keyed `prefixByMilestone` merge and the 20-entry prefix history;
> - one `HelperRunner` per Start, `guard ""`, which no preview, project switch or other Start stops;
> - `isHereStart` (`madeFor === dispatch.project` and it is the runner that put the store into
>   `starting`);
> - the settings write by the same runner after any ok start, wherever that start was made, with
>   the runner going when the write replies or at once after a failed start.
>
> ### Couplings that become signals or own reactions
>
> 1. **A start's ok reply, when it is this dispatch's** (`dispatchStartReplied`, RunStore.qml
>    1332-1361). The order is kept exactly:
>    1. set `dispatchRunId` and `dispatchMessage`;
>    2. compute `settings` as today (`Runs.copyMap(dispatch.runSettings)` plus the saved keys, with
>       `prefixByMilestone` merged through `mergedPrefixes`);
>    3. emit `runSettingsUpdated(settings)` (was `store.runSettings = settings`);
>    4. set `dispatchState = "started"`;
>    5. emit `refreshRequested("all")` (was `store.refresh()`);
>    6. emit `dispatchStarted(dispatchRunId !== "" ? dispatchRunId : null)`.
>
>    Then the runner starts its `set-run-settings` write, as today. A reply that is not this
>    dispatch's emits none of the three signals, as today it neither writes nor refreshes nor
>    emits.
> 2. **The settings write fails while the dispatch is still that start's** (`dispatchSaveReplied`,
>    1380-1384). The store emits `noticeRequested("Dispatch settings could not be saved")`, where
>    today it calls `store.flash(...)`. It emits nothing otherwise. The runner goes either way.
> 3. **Closing the panel.** `onActiveChanged: if (!dispatch.active) dispatch.closeDispatch()`.
>    `closeDispatch` still refuses while `starting`, so a start in flight runs on and lands
>    normally. `active` turning true does nothing.
> 4. **A project change.** `onProjectChanged: dispatch.resetDispatch()`. This holds even from
>    `starting`: the start still runs, and its reply is no longer this dispatch's. `resetDispatch`
>    reads no run settings, so it does not depend on the order relative to `RunStore`'s own
>    `runSettings = {}`.
> 5. **Reads of `store.project`, `store.runs`, `store.runSettings` and `store.backendDir`** become
>    reads of this store's inputs of the same names. `dispatchStartC.createObject(dispatch, …)`
>    parents each start runner to this store.
>
> ### Contract comment
>
> The header comment states only the contract. It covers:
>
> - what the store does (the state machine, `dispatch-preview.py`, `start-run.py` on one runner per
>   Start, and that runner's `set-run-settings` write);
> - its inputs, and that it never reaches for another store;
> - its four out-signals;
> - that a project change resets it and closing the panel closes it unless a start is in flight;
> - that App composes it as `app.runDispatch`.
>
> The moved members keep their comments, with "the store" read as this store.
>
> ## Behaviour: `RunStore`
>
> ### Removed
>
> All the rows in "The members that move", plus the two coupling lines in `stopLive` and
> `projectSwitched`. `RunStore` launches no `dispatch-preview.py` and no `start-run.py` of its own.
> It still launches `get-run-settings` on `runSettingsRunner`.
>
> ### Shims
>
> The shims go in a new block after the alerts shims (RunStore.qml 155-166), under
> `// Moved to RunDispatchStore; removed by the last story`. They start with
> `property var dispatchStore: null`. Every shim checks `store.dispatchStore` first, so a store with
> no handle never throws (`tests/run.sh` fails a file whose output contains `TypeError`).
>
> | name | shim | without a handle |
> |---|---|---|
> | `dispatchState` | **writable**, following the `cancelText` pattern (RunStore.qml 132-139): a plain `property string`, a `Binding` from the handle, and an `on…Changed` that writes a differing value through to the handle, or resets it to `"idle"` without one | `"idle"` |
> | `dispatchTarget`, `dispatchForm`, `dispatchPreview`, `dispatchSuggest`, `dispatchExitCode` | `readonly property var` | `null` |
> | `dispatchTargetLabel`, `dispatchError`, `dispatchErrorType`, `dispatchRunId`, `dispatchMessage`, `dispatchLog`, `dispatchLogTail` | `readonly property string` | `""` |
> | `dispatchErrors` | `readonly property var` | `[]` |
> | `dispatchDefaultsRunner`, `dispatchPreviewRunner`, `dispatchDebounceTimer` | `readonly property var` | `null` |
> | `dispatchStartRunners` | `readonly property var` | `[]` |
> | `openDispatch(card, cardMap)`, `closeDispatch()`, `retargetToMilestone()`, `setDispatchField(name, value)`, `dispatchStart()`, `checkDispatch()` | a one-line forward returning the target's result | returns `undefined`, does nothing |
> | `signal dispatchStarted(var runId)` | stays declared on `RunStore`; a `Connections { target: store.dispatchStore; function onDispatchStarted(runId) { store.dispatchStarted(runId) } }` re-emits it | never emitted |
>
> **Why `dispatchState` is writable.** `tests/ui` writes it on a real `RunStore`, and those files
> must pass untouched:
>
> - `tests/ui/tst_dispatch_flow.qml:203` writes `"previewing"`, then the dialog's suggestion must
>   be refused by the store;
> - `tests/ui/tst_shortcuts.qml:778` and `:836` write `"ready"` (an open dispatch is a modal);
> - `tests/ui/tst_shortcuts.qml:861` writes `"starting"`, then Escape's `closeDispatch()` must
>   refuse.
>
> Each of these needs the write to reach the dispatch store. No other dispatch member is written
> outside `RunStore.qml` and the moved tests: the planner confirms this with
> `grep -rnE 'runs\.dispatch[A-Za-z]* *=[^=]' ui tests`.
>
> **Why only these six functions get a forward.** They are the only dispatch functions that `ui/`,
> `tests/ui/` or `tst_app_runs.qml` call on `app.runs` (`checkDispatch` only at
> `tests/ui/tst_dispatch_flow.qml:304`). The other fourteen are internal, so they get no shim, as
> 3.2 did for `applyGlobalSettings`. Before deleting, the planner greps `ui/`, `tests/ui/`,
> `tst_app_runs.qml` and the tests that stay in `tst_run_store.qml` for each name. Any hit gets a
> forward shim instead.
>
> **`dispatchStarted` is re-emitted once.** It is re-emitted by `RunStore` alone; App adds no
> second route. Panel (`ui/Panel.qml:102-105`) listens on `app.runs` and calls `closeDispatch()`
> then `navi.openStartedRun(runId)`. A second emission would open the run twice.
>
> `runSettings`, `runSettingsRunner` and `applyRunSettings` are unchanged and are not shims.
>
> ### Header comment
>
> The header (RunStore.qml 7-37) changes in two places:
>
> - The two dispatch sentences ("Dispatch (openDispatch .. dispatchStart) previews … one
>   HelperRunner per Start.", 31-33) are replaced by one contract sentence. For example: "The
>   dispatch is RunDispatchStore's; its members here are shims through `dispatchStore`."
> - "the open project, decides only the run settings and the dispatch" (13-14) becomes "… decides
>   only the run settings".
>
> ## Behaviour: `App`
>
> - A new `readonly property RunDispatchStore runDispatch: RunDispatchStore { … }`, placed after
>   `runAlerts`. It binds and routes exactly as the inputs table above says. Its comment, in the
>   style of App.qml 131-134 and 141-144: "The dispatch never imports the run store: App hands it
>   the backend directory, the open project's root, the panel-open flag, the run list and the run
>   settings, routes its refreshRequested to the run store, its noticeRequested to run control's
>   flash and its runSettingsUpdated into the run store's runSettings."
> - `runs` gains `dispatchStore: app.runDispatch`, and its comment's handle list (App.qml 106-107)
>   adds `dispatchStore`.
>
> ## Equivalence argument (for the reviewer)
>
> - **Same launches.** One opening still launches exactly one `--defaults` lookup, and one check
>   launches at most one preview. Each Start is still one `start-run.py`, followed on an ok reply by
>   one `set-run-settings` on the same runner. The guards (`dispatch.project`, and `""` for starts)
>   follow the same root, because `dispatch.project` is bound to `app.runs.project`.
> - **A project switch.** Today one handler does `runSettings = {}`, then `resetDispatch()`, then
>   sets the runner guard and loads. Now `RunStore` does the reset and the load, and the dispatch
>   store resets itself on its own `project` change. Both are synchronous in the same change.
>   `resetDispatch` reads no run settings, and the load reads nothing of the dispatch, so no
>   observable value depends on which runs first.
> - **A start's ok reply.** The `runSettingsUpdated` route is a synchronous signal handler, so App
>   writes `app.runs.runSettings` and the dispatch store's bound `runSettings` follows before
>   `dispatchState` turns `started`, as today. `refreshRequested("all")` reaches `app.runs.refresh()`,
>   which is the call made today.
> - **The flash.** It lands on the same `flashText` / `flashTimer`. Today `store.flash` already
>   forwards to `RunControlStore` through 3.1's shim.
> - **Closing the panel.** Both stores bind `active` to `app.panelOpen`. The dispatch is closed by
>   its own reaction rather than by `stopLive`. Nothing else in `stopLive` reads the dispatch.
>
> ## Tests
>
> TDD: each new or changed test is written first and fails before its code exists. Everything runs
> through `bash tests/run.sh` (pytest, then qmltestrunner offscreen with `tests/stubs`).
> `bash tests/run.sh tst_run_dispatch_store` runs one file (the filter is a substring of the path).
> The tiers:
>
> - **store unit, dispatch:** `tests/core/stores/tst_run_dispatch_store.qml`, new. It pins the
>   dispatch's behaviour on the store that owns it. It has two harnesses:
>   - a bare builder, `makeDispatch()`, which builds a `RunDispatchStore` with `backendDir`
>     `"/plugin/core/backend/"` and nothing bound;
>   - a "wired the way App wires it" builder, described below.
> - **RunStore unit:** `tests/core/stores/tst_run_store.qml`. It pins the shims, the removal, and
>   the run-settings tests that stay.
> - **App wiring:** `tests/core/stores/tst_app_runs.qml`. It pins the new composition and every
>   route.
> - **UI and architecture:** `tests/ui/**` (untouched) and `pytest tests` (architecture, contract,
>   install).
>
> ### Moved tests (store unit tier: whole, every expectation kept)
>
> All 59 test functions from `test_dispatch_starts_idle` (tst_run_store.qml 2908) through
> `test_a_late_blocked_start_reply_changes_nothing` (4186-4210) leave `tst_run_store.qml`. They land
> in `tst_run_dispatch_store.qml` under the same names, in the same order, under the same section
> headers (`// ---- dispatch (S3 3.1)` and `// ---- dispatch: story target, retarget and keyed
> prefix (2.1)`), keeping their numbered comments.
>
> The helpers and properties defined in 2831-4210 move with them:
>
> - `previewCmd`, `startCmd`, `dispatchCards`, `dispatchStore`, `checkDispatchIdle`, `defaultsOk`,
>   `previewOk`, `dispatchDryRun`, `previewingStore`, `previewArgs`, `startOk`, `readyStore`,
>   `savedJson`;
> - `keyedSettings`, `storyDryRun`, `storyPreviewingStore`, `storyPreviewArgs`, `blockedMessage`,
>   `dispatchFields`, `checkRetargetRefused`, `storyReadyStore`, `startBlocked`.
>
> These three tests in that range **stay** in `tst_run_store.qml`, because they pin `runSettings`,
> which stays:
>
> - `test_run_settings_load_per_project_and_never_set_the_switch` (2800);
> - `test_run_settings_kept_even_after_notify_touched` (2843);
> - `test_run_settings_follow_the_project` (2858).
>
> `dispatchSettings()` (2837) is used on both sides, so it is copied into the new file and also
> kept. The new file also copies the shared helpers its tests call:
>
> - from tst_run_store.qml: `reply`, `argv`, `rootEntry`, `registry`, `allReply`, `okEntry`,
>   `okReply`, `entry`, and the `rootA` / `rootB` / `snapCmd` / `viewerCmd` properties;
> - `spyC`.
>
> The planner lists the exact set by grepping the moved bodies.
>
> **The wired harness.** The construction helpers `make()`, `makeWithProject(root)`,
> `makeWithRoots(roots)` and `activeStore(root)` keep their names and their RunStore-side steps.
> Each one builds:
>
> 1. a `RunStore`;
> 2. a `RunControlStore` wired as `tst_run_store.qml`'s `wireControl` does (54-70), so the flash
>    lands;
> 3. a `RunDispatchStore`, wired the way App wires `app.runDispatch`:
>    - `backendDir` copied;
>    - `project`, `active`, `runs` and `runSettings` bound to the RunStore's own;
>    - `refreshRequested` → `refresh()` for `"all"`, else `requestSnapshot(roots)`;
>    - `noticeRequested` → the control store's `flash`;
>    - `runSettingsUpdated` → `runStore.runSettings = settings`.
>
> Each helper **returns the dispatch store**. It does not set `runStore.dispatchStore`, so the moved
> tests prove the store and not the shims. `runsOf(d)` and `controlOf(d)` return the paired stores.
>
> **The only edits inside moved bodies.** Every read, write or call of a member that stays outside
> the dispatch store is redirected to the store that owns it. The expectations are untouched.
>
> | in the moved bodies | becomes |
> |---|---|
> | `X.project = …` (7) | `runsOf(X).project = …` |
> | `X.active = …` (5) | `runsOf(X).active = …` |
> | `X.runs = […]` (3791) | `runsOf(X).runs = […]` |
> | `X.runSettingsRunner` (10) | `runsOf(X).runSettingsRunner` |
> | `X.snapshotRunner` (12) | `runsOf(X).snapshotRunner` |
> | `X.flashText` (3) | `controlOf(X).flashText` |
> | `X.notifyOnEscalation`, `X.settingsSaveRunner` (3615-3616, `test_settings_write_failure_flashes`) | `controlOf(X)…` |
>
> `X` is whatever the local is called (`store`, `pending`, `cleared`, `back`, `keyed`, `fresh`,
> `ready`, …). Reads of `X.runSettings` stay on the dispatch store, whose bound input carries the
> same value. A `SignalSpy` on `dispatchStarted` targets the dispatch store.
>
> The file's header comment says what it covers: the dispatch state machine, built alone and wired
> to a RunStore and a RunControlStore the way App wires `app.runDispatch`, with stubbed Process
> objects.
>
> ### New tests
>
> **Store unit (`tst_run_dispatch_store.qml`, bare store, section `// ---- the store alone`):**
>
> - **D-N1 `test_a_bare_dispatch_store_is_idle_with_empty_inputs`.** `makeDispatch()` passes
>   `checkDispatchIdle`. Also:
>   - `project` is `""`, `active` is `false`, `runs` has length 0 and `runSettings` has no keys;
>   - `dispatchStartRunners` has length 0, `dispatchDebounceTimer.running` is `false`, and neither
>     runner has a `current`;
>   - `openDispatch(cards.m1, cards)` returns `false`.
>
>   Tier: store unit, because it pins the defaults on the owner with nothing bound.
> - **D-N2 `test_its_own_active_closes_it_but_not_a_start`.**
>   1. On a bare store, set `project = rootA` and `runSettings` to the parsed `dispatchSettings()`.
>   2. Set `active = true`, open m1 and reply `defaultsOk("main")`.
>   3. Set `active = false`. The store is idle (`checkDispatchIdle`).
>   4. Set `active = true` again, open m1, reach `ready` (defaults reply, then preview reply), and
>      call `dispatchStart()`.
>   5. Set `active = false`. `dispatchState` stays `"starting"`, and the start process is still
>      running.
>
>   Tier: store unit, because it proves the close is the store's own reaction (A.3 P l.436), with no
>   RunStore.
> - **D-N3 `test_its_own_project_change_resets_it_and_keeps_a_start_running`.**
>   1. On a bare store, from `ready`, call `dispatchStart()`.
>   2. Set `project = rootB`. The store is idle, and the start process is still running.
>   3. A late ok reply to that start emits no `dispatchStarted`, no `refreshRequested` and no
>      `runSettingsUpdated` (`SignalSpy` counts 0).
>   4. The runner then shows a `set-run-settings` argv for `rootA`.
>
>   Tier: store unit (A.3 P l.437).
> - **D-N4 `test_a_start_reply_emits_settings_then_refresh_then_started`.**
>   1. On a bare store from `ready`, connect one recorder to all three signals. The recorder pushes
>      `"settings"`, `"refresh:" + JSON.stringify(roots)` and `"started:" + runId`.
>   2. Reply `startOk("r-1", "")`.
>   3. The record is exactly `settings`, `refresh:"all"`, `started:r-1`.
>   4. The `runSettingsUpdated` payload has these values:
>      - `prefixHistory` `["old"]`;
>      - `parallelism` 4;
>      - `confirmDispatch` `true` (a key the start does not write is kept);
>      - `prefixByMilestone.m1` `"old"`.
>   5. `dispatchState` is `"started"` once `started` is recorded.
>
>   Tier: store unit, because it pins the order of the coupling signals (see "Couplings").
> - **D-N5 `test_the_store_never_writes_its_own_run_settings`.** On a bare store whose
>   `runSettings` is set to object `S`, with nothing connected to `runSettingsUpdated`, an ok start
>   leaves `runSettings === S`. Tier: store unit. It guards the App binding (Review Focus 3).
> - **D-N6 `test_a_failed_settings_write_emits_one_notice_only_while_here`.**
>   1. On a bare store from `started`, reply `garbage` to the write. `noticeRequested` fires once,
>      with `"Dispatch settings could not be saved"`.
>   2. A second bare store starts, then its `project` changes, then the start and the write both
>      fail. That gives 0 notices.
>
>   Tier: store unit (A.3 P l.446).
>
> **RunStore unit (`tst_run_store.qml`, new section `// ---- the dispatch shims (split-runstore
> 4.1)`):**
>
> - **R-D1 `test_without_a_dispatch_store_the_shims_are_empty_and_inert`.** A `RunStore` built bare
>   (no handle):
>   - every property shim reads its "without a handle" value from the table;
>   - each of the six functions returns `undefined`;
>   - writing `dispatchState = "ready"` leaves it `"idle"`;
>   - `active = true` then `active = false`, and `project = rootA` then `project = rootB`, produce
>     no `TypeError`.
>
>   Tier: RunStore unit, because the shims live there.
> - **R-D2 `test_the_dispatch_shims_follow_the_dispatch_store_and_notify`.** Use a `RunStore` with a
>   `RunDispatchStore` handle (`store.dispatchStore = d`, the dispatch wired as above).
>   1. `store.dispatchDefaultsRunner === d.dispatchDefaultsRunner`, and likewise for the preview
>      runner, the timer and `dispatchStartRunners`.
>   2. A `SignalSpy` on `store`'s `dispatchStateChanged` counts 1 after `store.openDispatch(cards.m1, cards)` (with the project open),
>      and `store.dispatchState` is `"previewing"`.
>   3. `store.setDispatchField("prefix", "x")` returns `true`, and `d.dispatchForm.prefix` is
>      `"x"`.
>   4. `store.closeDispatch()` returns `true`, and `d.dispatchState` is `"idle"`.
>
>   Tier: RunStore unit.
> - **R-D3 `test_writing_the_dispatch_state_shim_reaches_the_dispatch_store`.** Writing
>   `store.dispatchState = "starting"` sets `d.dispatchState` to `"starting"`. Then
>   `store.closeDispatch()` returns `false`. Then `d.resetDispatch()` brings `store.dispatchState`
>   back to `"idle"`, which shows the binding is intact after a write. Tier: RunStore unit, pinning
>   what `tests/ui/tst_shortcuts.qml:861` relies on.
> - **R-D4 `test_dispatch_started_is_re_emitted_once`.** A `SignalSpy` on `store.dispatchStarted`.
>   Then `d.dispatchStarted("r-9")`. The count is 1, with argument `"r-9"`. Tier: RunStore unit.
> - **R-D5 `test_closing_and_switching_the_run_store_touch_no_dispatch`.** A `RunStore` wired to
>   its own dispatch store, with the dispatch **not** bound to the RunStore's `active` / `project`
>   (bare `d`, handle set). Open on the RunStore, then:
>   - `store.active = true; store.active = false` leaves `d.dispatchState` `"previewing"`;
>   - `store.project = rootB` leaves it too.
>
>   Tier: RunStore unit, because it pins that `stopLive` and `projectSwitched` no longer reach the
>   dispatch (the leftover-call failure mode).
>
> **App wiring (`tst_app_runs.qml`):**
>
> - **Unchanged, still passing through the shims:**
>   - `test_a_dispatch_start_through_app_snapshots_every_registered_root` (374);
>   - `test_a_dispatch_settings_save_failure_through_app_flashes` (391);
>   - `test_a_project_switch_through_app_resets_the_dispatch_and_reloads_run_settings` (403);
>   - `test_closing_the_panel_through_app_empties_toasts_disarms_and_closes_the_dispatch` (440).
> - **A-D1 `test_app_composes_run_dispatch_wired_to_the_run_store`.** With `make()`:
>   - `app.runDispatch` exists;
>   - `app.runs.dispatchStore === app.runDispatch`;
>   - `app.runDispatch.backendDir` is `"/plugin/core/backend/"`;
>   - `project` is `"/home/u/my proj"`, and follows `app.projects.chooseProject(pB)`;
>   - `active` follows `app.panelOpen`;
>   - `runs === app.runs.runs`;
>   - `runSettings === app.runs.runSettings` after a `get-run-settings` reply.
>
>   Tier: App wiring.
> - **A-D2 `test_a_start_through_app_writes_the_run_settings_back_and_keeps_the_binding`.**
>   1. `readyApp()`, then `app.runDispatch.dispatchStart()`, then an ok reply.
>   2. `app.runs.runSettings.prefixByMilestone.m1` is `"old"`, and
>      `app.runDispatch.runSettings === app.runs.runSettings`.
>   3. `app.projects.chooseProject(pB)`. Both now have 0 keys.
>   4. A `get-run-settings` reply for B with `{parallelism: 9}` reaches `app.runDispatch.runSettings`.
>
>   Tier: App wiring, because it is Dispatch → RunStore (A.3 P l.445).
> - **A-D3 `test_a_start_through_app_announces_started_once_on_each_store`.** Spies on
>   `app.runDispatch` and `app.runs` `dispatchStarted`. After an ok start, each counts 1, with
>   `"r-1"`. Tier: App wiring. It guards against a double route that would make Panel open the run
>   twice.
> - **A-D4 `test_a_dispatch_notice_through_app_is_run_controls_flash`.** After a failed settings
>   write, `app.runControl.flashText` is `"Dispatch settings could not be saved"` and
>   `app.runControl.flashTimer.running` is `true`. Tier: App wiring (A.3 P l.446).
> - **A-D5 `test_closing_the_panel_through_app_keeps_a_start_in_flight`.**
>   1. `readyApp()` with `app.panelOpen = true`, then `dispatchStart()`.
>   2. `app.panelOpen = false`. `app.runDispatch.dispatchState` is `"starting"`.
>   3. An ok reply gives `"started"`.
>
>   Tier: App wiring (A.3 P l.436).
>
> The file's header comment adds `app.runDispatch` to what it covers.
>
> ### Test wiring changes in `tst_run_store.qml`
>
> - Delete the 59 moved tests and the helpers that only they use.
> - Keep `dispatchSettings()` and the three run-settings tests.
> - The header comment (1-9) adds: "The dispatch is tested in tst_run_dispatch_store.qml."
> - If a remaining test reads a dispatch member, it goes through the shim only when it is wired with
>   a handle. The planner greps the remaining file for `dispatch` after the deletion. Any hit is
>   either moved (if it is a dispatch test) or given the handle through a `wireDispatch(store)`
>   modelled on `wireControl`.
>
> ### Gate
>
> - `bash tests/run.sh` is green: pytest, including `tests/architecture`, then every qmltestrunner
>   file, with no `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign` or `is not a
>   function` in the output.
> - `git diff --stat -- ui tests/ui` is empty.
>
> ## Docs
>
> Only the sentences this card makes false are edited.
>
> - **`docs/architecture.md:84`.** In `stopLive`'s list, "and closes the dispatch unless a start is
>   in flight" is removed.
> - **`docs/architecture.md:92`.** The paragraph opens "Dispatch (S3 3.1) is `RunDispatchStore`'s
>   (`app.runDispatch`)" in place of "the store also starts am runs". It adds one sentence: App
>   hands it `backendDir`, `project`, `active`, `runs` and `runSettings`, and routes
>   `refreshRequested` to the run store, `noticeRequested` to `app.runControl.flash` and
>   `runSettingsUpdated` into `app.runs.runSettings`. In the closing sentence, "closing the panel
>   (except while `starting`)" becomes its own `active` reaction. "the store's own `runSettings`
>   merging it" becomes "`runSettingsUpdated` carrying it".
> - **`docs/architecture.md:91`** (the shim sentence). It adds that `RunStore` keeps the dispatch
>   properties, `dispatchDefaultsRunner`, `dispatchPreviewRunner`, `dispatchDebounceTimer`,
>   `dispatchStartRunners`, `openDispatch`, `closeDispatch`, `retargetToMilestone`,
>   `setDispatchField`, `dispatchStart`, `checkDispatch` and a re-emitted `dispatchStarted` as shims
>   through `dispatchStore`, and that `dispatchState` is writable.
> - **`docs/architecture.md:173`.** "`RunStore`'s watch, … and the dispatch debounce" becomes
>   "`RunStore`'s watch, …, `RunDispatchStore`'s dispatch debounce".
> - **The RunStore header comment.** See "Header comment" above.
> - **The RunDispatchStore header comment.** See "Contract comment" above.
>
> ## Review Focus (for the planner)
>
> These are the failure modes the moved tests do not obviously exercise. Each line names the
> condition and the expected behaviour. The planner adds each test to the task that owns the code.
>
> 1. **A ui test writes `app.runs.dispatchState`** (`tst_shortcuts.qml:778, 836, 861`,
>    `tst_dispatch_flow.qml:203`). Expected: the write reaches the dispatch store. A later
>    `closeDispatch()` sees `"starting"` and refuses, and the shim keeps following the store
>    afterwards. A read-only shim would throw `Unable to assign`. Pinned by R-D3 and the untouched
>    ui suites.
> 2. **`dispatchStarted` delivered twice or not at all** (App and RunStore both forwarding, or
>    neither). Expected: exactly once on `app.runs`, so Panel closes the dialog once and opens the
>    run once. Pinned by A-D3 and R-D4.
> 3. **The dispatch store writes its own `runSettings`.** That breaks App's binding, so a later
>    project switch leaves the old project's settings in the next form. Expected: the write goes
>    through `runSettingsUpdated`, and the binding survives. Pinned by D-N5 and A-D2.
> 4. **A RunStore with no dispatch handle opens, closes or switches projects** (every
>    `tst_run_store.qml` / `tst_run_alerts_store.qml` builder without a handle). Expected: no
>    `TypeError`, and the shims read their empty values. Pinned by R-D1 and R-D5.
> 5. **The panel closes while a start is in flight, through App.** Expected: the start stays
>    `starting` and lands normally, because the store's own `active` reaction goes through
>    `closeDispatch`, which refuses, not through `resetDispatch`. Pinned by D-N2 and A-D5.
>
> ## Hand-off to the planner
>
> Suggested tasks, each with its own test cycle:
>
> 1. **`RunDispatchStore` exists and owns the dispatch.**
>    - Files: create `core/stores/RunDispatchStore.qml` and
>      `tests/core/stores/tst_run_dispatch_store.qml`.
>    - Add the members in "The members that move", the inputs and signals, and `onActiveChanged` /
>      `onProjectChanged`. `RunStore` keeps its own copy for now. Nothing binds to the new store
>      yet, so this is safe.
>    - Tests first: D-N1 … D-N6, then the 59 moved tests copied in with the wired harness and the
>      redirects. Do not delete them from `tst_run_store.qml` yet.
> 2. **`RunStore` shims, App composition and test moves, in one commit.**
>    - Files: `core/stores/RunStore.qml`, `core/stores/App.qml`,
>      `tests/core/stores/tst_run_store.qml` (delete the moved tests, R-D1 … R-D5), and
>      `tests/core/stores/tst_app_runs.qml` (A-D1 … A-D5).
>    - Remove the RunStore members, add the shims, compose `app.runDispatch`.
>    - Grep for the no-shim functions before deleting them.
>    - Run the full gate, and confirm that `ui/` and `tests/ui/` are untouched.
> 3. **Docs.** The `docs/architecture.md` edits above and both header comments. Contract only, no
>    narrative.
>
> The member interfaces later tasks rely on, exactly:
>
> - `RunDispatchStore` inputs: `backendDir: string`, `project: string`, `active: bool`,
>   `runs: var` (list), `runSettings: var` (object).
> - `RunDispatchStore` signals: `dispatchStarted(var runId)`, `refreshRequested(var roots)` (always
>   `"all"` here), `noticeRequested(string text)`, `runSettingsUpdated(var settings)`.
> - `RunDispatchStore` keeps every public name in the table under "The members that move", with
>   today's signatures: `openDispatch(card, cardMap) -> bool`, `closeDispatch() -> bool`,
>   `retargetToMilestone() -> bool`, `setDispatchField(name, value) -> bool`,
>   `dispatchStart() -> bool`, `checkDispatch()`, `resetDispatch()`, and the readonly aliases
>   `dispatchDefaultsRunner`, `dispatchPreviewRunner`, `dispatchDebounceTimer` and
>   `dispatchStartRunners`.
> - `RunStore.dispatchStore: var` (the handle, `null` by default).
> - `App.runDispatch: RunDispatchStore`.

---

## File structure

| file | change | responsibility |
|---|---|---|
| `core/stores/RunDispatchStore.qml` | create (Task 1) | the dispatch state machine, its runners and timer, its inputs and four out-signals |
| `tests/core/stores/tst_run_dispatch_store.qml` | create (Task 1) | the store alone (D-N1 … D-N6) and the 59 moved tests on a harness wired the way App wires `app.runDispatch` |
| `core/stores/RunStore.qml` | modify (Task 2) | loses the dispatch; gains the `dispatchStore` handle and shims; header comment |
| `core/stores/App.qml` | modify (Task 2) | composes `runDispatch`, routes its signals, hands `runs` its handle |
| `tests/core/stores/tst_run_store.qml` | modify (Task 2) | moved tests deleted; R-D1 … R-D5; the two lines in "Notes on the spec" |
| `tests/core/stores/tst_app_runs.qml` | modify (Task 2) | A-D1 … A-D5; header comment |
| `docs/architecture.md` | modify (Task 3) | only the sentences this card makes false |

All commands run from the worktree root. Scripts are saved under `/tmp/` (outside the repo) and run with `python3`; each asserts that every text it replaces occurs exactly once, so a script that does not match the file stops with an `AssertionError` instead of editing the wrong place.

---

### Task 1: `RunDispatchStore` exists and owns the dispatch, built alone

**Files:**
- Create: `core/stores/RunDispatchStore.qml`
- Create: `tests/core/stores/tst_run_dispatch_store.qml`

**Interfaces:**
- Consumes: nothing from other tasks. Reads (does not change) `tests/core/stores/tst_run_store.qml` lines 2831-2841 and 2871-4210 at commit `7676feb`, and builds `RunStore.qml` / `RunControlStore.qml` in its wired harness.
- Produces (Task 2 relies on these exact names):
  - `RunDispatchStore` inputs: `property string backendDir`, `property string project`, `property bool active`, `property var runs` (list), `property var runSettings` (object, `({})` by default).
  - Signals: `dispatchStarted(var runId)`, `refreshRequested(var roots)` (always `"all"`), `noticeRequested(string text)`, `runSettingsUpdated(var settings)`.
  - Properties `dispatchState` … `dispatchExitCode` (14), readonly aliases `dispatchDefaultsRunner`, `dispatchPreviewRunner`, `dispatchDebounceTimer`, `dispatchStartRunners`.
  - Functions with today's signatures: `openDispatch(card, cardMap) -> bool`, `closeDispatch() -> bool`, `retargetToMilestone() -> bool`, `setDispatchField(name, value) -> bool`, `dispatchStart() -> bool`, `checkDispatch()`, `resetDispatch()`, plus the internal `clearDispatchError`, `blockedSuggest`, `withField`, `dispatchTargetArgs`, `dispatchCommands`, `dispatchOptionArgs`, `dispatchDefaultsReplied`, `dispatchPreviewReplied`, `mergedPrefixes`, `isHereStart`, `dispatchStartReplied`, `dispatchSaveReplied`, `dropStartRunner`.

`RunStore` keeps its own copy of everything during this task; nothing binds to the new store yet.

- [ ] **Step 1: Write the test file's header, harness and the six bare-store tests (D-N1 … D-N6)**

Create `tests/core/stores/tst_run_dispatch_store.qml` with exactly this content (the file is not closed yet; Step 2 appends the moved tests and the closing brace). The D-N tests call `dispatchSettings`, `dispatchCards`, `defaultsOk`, `previewOk`, `dispatchDryRun`, `startOk`, `checkDispatchIdle` and `savedJson`, which arrive with the moved section in Step 2.

```qml
// tests/core/stores/tst_run_dispatch_store.qml
// The dispatch store: the dispatch state machine (open, the --defaults
// lookup, the debounced check and preview, Start on one runner per Start and
// that runner's settings write), the story target and retargetToMilestone,
// and the four signals it emits. Built alone, and wired to a RunStore and a
// RunControlStore the way App wires app.runDispatch, with stubbed Process
// objects standing in for every helper.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "StoresRunDispatchStore"

  property string rootA: "/home/u/my proj"
  property string rootB: "/home/u/b"
  property string snapCmd: "python3|/plugin/core/backend/runs/runs-snapshot-all.py"
  property string viewerCmd: "python3|/plugin/core/backend/projects/viewer-state.py|"

  Component { id: spyC; SignalSpy {} }

  // A RunDispatchStore built alone, with nothing bound.
  function makeDispatch() {
    var comp = Qt.createComponent("../../../core/stores/RunDispatchStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }

  // Every {dispatch, runs, control} triple make() built.
  property var wired: []

  // A RunStore, a RunControlStore wired to it the way App wires
  // app.runControl, and a RunDispatchStore wired to both the way App wires
  // app.runDispatch: backendDir copied; project, active, runs and runSettings
  // bound to the run store's own; refreshRequested to refresh() ("all") or
  // requestSnapshot(roots); noticeRequested to the control store's flash;
  // runSettingsUpdated into the run store's runSettings. The run store's
  // dispatchStore handle is not set. Returns the dispatch store.
  function make() {
    var runsComp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (runsComp.status !== Component.Ready) { fail(runsComp.errorString()); return null }
    var store = runsComp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    var controlComp = Qt.createComponent("../../../core/stores/RunControlStore.qml")
    if (controlComp.status !== Component.Ready) { fail(controlComp.errorString()); return null }
    var c = controlComp.createObject(tc, { backendDir: store.backendDir })
    c.project = Qt.binding(function() { return store.project })
    c.active = Qt.binding(function() { return store.active })
    c.runs = Qt.binding(function() { return store.runs })
    store.controlStore = c
    store.snapshotReplied.connect(function(root, outcome) { if (outcome === "ok") c.settleAfterSnapshot() })
    c.refreshRequested.connect(function(roots) {
      if (roots === "all") store.refresh()
      else store.requestSnapshot(roots)
    })
    var d = makeDispatch(); if (!d) return null
    d.backendDir = store.backendDir
    d.project = Qt.binding(function() { return store.project })
    d.active = Qt.binding(function() { return store.active })
    d.runs = Qt.binding(function() { return store.runs })
    d.runSettings = Qt.binding(function() { return store.runSettings })
    d.refreshRequested.connect(function(roots) {
      if (roots === "all") store.refresh()
      else store.requestSnapshot(roots)
    })
    d.noticeRequested.connect(function(text) { c.flash(text) })
    d.runSettingsUpdated.connect(function(settings) { store.runSettings = settings })
    tc.wired = tc.wired.concat([{ dispatch: d, runs: store, control: c }])
    return d
  }

  // The RunStore make() paired with dispatch store `d`; null when none.
  function runsOf(d) {
    for (var i = 0; i < tc.wired.length; i++) {
      if (tc.wired[i].dispatch === d) return tc.wired[i].runs
    }
    return null
  }

  // The RunControlStore make() paired with dispatch store `d`; null when none.
  function controlOf(d) {
    for (var i = 0; i < tc.wired.length; i++) {
      if (tc.wired[i].dispatch === d) return tc.wired[i].control
    }
    return null
  }

  // A root's registry entry: rootA is "alpha", rootB "beta", any other "proj".
  function rootEntry(root) {
    return { root: root, name: root === tc.rootA ? "alpha" : root === tc.rootB ? "beta" : "proj" }
  }

  // The registry of `roots`, in that order, as App hands it over.
  function registry(roots) {
    return roots.map(function(r) { return tc.rootEntry(r) })
  }

  // make() with `roots` registered and no project open: the snapshot of
  // every root is in flight.
  function makeWithRoots(roots) {
    var d = make(); if (!d) return null
    runsOf(d).projectRoots = registry(roots)
    return d
  }

  // make() with one registered project, `root`, open: its first snapshot (of
  // that root alone) and its run settings load are in flight.
  function makeWithProject(root) {
    var d = make(); if (!d) return null
    runsOf(d).projectRoots = [rootEntry(root)]
    runsOf(d).project = root
    return d
  }

  // makeWithProject(root) with the panel open.
  function activeStore(root) {
    var d = make(); if (!d) return null
    runsOf(d).active = true
    runsOf(d).projectRoots = [rootEntry(root)]
    runsOf(d).project = root
    return d
  }

  // A stubbed process's reply: its stdout, then its exit code.
  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // A process's argv, joined with "|".
  function argv(proc) { return proc.command.join("|") }

  // A timer firing on its own: a one-shot timer has stopped by the time its
  // triggered() is emitted.
  function fire(timer) {
    if (!timer.repeat) timer.stop()
    timer.triggered()
  }

  function ctlFail(type, message) {
    return JSON.stringify({ ok: false, error: { type: type, message: message } }) + "\n"
  }

  // runs-snapshot-all.py's reply line: {"ok": true, "projects": projects, "data_dir"}.
  function allReply(projects) {
    return JSON.stringify({ ok: true, projects: projects, data_dir: "/home/u/.local/share" }) + "\n"
  }

  // One root's entry that answered, listing `runs`.
  function okEntry(root, runs) { return { root: root, ok: true, runs: runs } }

  // A reply where every root answered: rootA's entry, then one per other
  // root the entries' repo_dir names, in first-seen order, each listing the
  // entries with that repo_dir.
  function okReply(entries) {
    var order = [tc.rootA]
    var byRoot = {}
    byRoot[tc.rootA] = []
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      var root = e !== null && typeof e === "object" && typeof e.repo_dir === "string" ? e.repo_dir : tc.rootA
      if (!byRoot.hasOwnProperty(root)) {
        byRoot[root] = []
        order.push(root)
      }
      byRoot[root].push(e)
    }
    return allReply(order.map(function(r) { return tc.okEntry(r, byRoot[r]) }))
  }

  // ---- the store alone (split-runstore 4.1)

  // A bare store on project A with dispatchSettings() as its run settings and
  // milestone m1's preview landed: Start is allowed.
  function bareReady() {
    var d = makeDispatch(); if (!d) return null
    d.project = tc.rootA
    d.runSettings = JSON.parse(dispatchSettings())
    var cards = dispatchCards()
    compare(d.openDispatch(cards.m1, cards), true)
    reply(d.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(d.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(d.dispatchState, "ready")
    return d
  }

  // D-N1
  function test_a_bare_dispatch_store_is_idle_with_empty_inputs() {
    var d = makeDispatch(); if (!d) return
    checkDispatchIdle(d, "bare")
    compare(d.backendDir, "/plugin/core/backend/")
    compare(d.project, "")
    compare(d.active, false)
    compare(d.runs.length, 0)
    compare(Object.keys(d.runSettings).length, 0)
    compare(d.dispatchStartRunners.length, 0)
    compare(d.dispatchDebounceTimer.running, false)
    verify(!d.dispatchDefaultsRunner.current)
    verify(!d.dispatchPreviewRunner.current)
    var cards = dispatchCards()
    compare(d.openDispatch(cards.m1, cards), false, "no project: refused")
    checkDispatchIdle(d, "after the refused opening")
  }

  // D-N2 (A.3: the store's own active reaction)
  function test_its_own_active_closes_it_but_not_a_start() {
    var d = makeDispatch(); if (!d) return
    d.project = tc.rootA
    d.runSettings = JSON.parse(dispatchSettings())
    d.active = true
    var cards = dispatchCards()
    compare(d.openDispatch(cards.m1, cards), true)
    reply(d.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(d.dispatchState, "previewing")
    d.active = false
    checkDispatchIdle(d, "closed")

    d.active = true
    checkDispatchIdle(d, "opening the panel does nothing")
    compare(d.openDispatch(cards.m1, cards), true)
    reply(d.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(d.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(d.dispatchState, "ready")
    compare(d.dispatchStart(), true)
    var proc = d.dispatchStartRunners[0].current
    d.active = false
    compare(d.dispatchState, "starting", "a start in flight is not closed")
    compare(proc.running, true)
  }

  // D-N3 (A.3: the store's own project reaction)
  function test_its_own_project_change_resets_it_and_keeps_a_start_running() {
    var d = bareReady(); if (!d) return
    var started = spyC.createObject(tc, { target: d, signalName: "dispatchStarted" })
    var refresh = spyC.createObject(tc, { target: d, signalName: "refreshRequested" })
    var updated = spyC.createObject(tc, { target: d, signalName: "runSettingsUpdated" })
    compare(d.dispatchStart(), true)
    var runner = d.dispatchStartRunners[0]
    var proc = runner.current
    d.project = tc.rootB
    checkDispatchIdle(d, "after the switch from starting")
    compare(proc.running, true, "the start is not stopped")
    reply(proc, startOk("r-1", ""), 0)
    checkDispatchIdle(d, "after A's late start")
    compare(started.count, 0)
    compare(refresh.count, 0)
    compare(updated.count, 0)
    compare(argv(runner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson, "recorded against A")
  }

  // D-N4 (the coupling order of an ok start)
  function test_a_start_reply_emits_settings_then_refresh_then_started() {
    var d = bareReady(); if (!d) return
    var record = []
    var payload = null
    var stateAtSettings = ""
    var stateAtStarted = ""
    d.runSettingsUpdated.connect(function(settings) {
      record.push("settings")
      payload = settings
      stateAtSettings = d.dispatchState
    })
    d.refreshRequested.connect(function(roots) { record.push("refresh:" + JSON.stringify(roots)) })
    d.dispatchStarted.connect(function(runId) {
      record.push("started:" + runId)
      stateAtStarted = d.dispatchState
    })
    compare(d.dispatchStart(), true)
    reply(d.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(JSON.stringify(record), JSON.stringify(["settings", 'refresh:"all"', "started:r-1"]))
    compare(stateAtSettings, "starting", "the settings are announced before started")
    compare(stateAtStarted, "started")
    compare(payload.prefixHistory.join(","), "old")
    compare(payload.parallelism, 4)
    compare(payload.confirmDispatch, true, "a key the start does not write is kept")
    compare(payload.prefixByMilestone.m1, "old")
  }

  // D-N5 (Review Focus 3)
  function test_the_store_never_writes_its_own_run_settings() {
    var d = makeDispatch(); if (!d) return
    var s = JSON.parse(dispatchSettings())
    d.project = tc.rootA
    d.runSettings = s
    var cards = dispatchCards()
    d.openDispatch(cards.m1, cards)
    reply(d.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(d.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(d.dispatchStart(), true)
    var runner = d.dispatchStartRunners[0]
    reply(runner.current, startOk("r-1", ""), 0)
    compare(d.dispatchState, "started")
    verify(d.runSettings === s, "the input is left as it was handed over")
    compare(d.runSettings.prefixByMilestone, undefined)
    reply(runner.current, JSON.stringify({ ok: true }) + "\n", 0)
    verify(d.runSettings === s)
  }

  // D-N6 (A.3: the notice)
  function test_a_failed_settings_write_emits_one_notice_only_while_here() {
    var d = bareReady(); if (!d) return
    var notices = spyC.createObject(tc, { target: d, signalName: "noticeRequested" })
    d.dispatchStart()
    var runner = d.dispatchStartRunners[0]
    reply(runner.current, startOk("r-1", ""), 0)
    compare(notices.count, 0, "nothing to say before the write replies")
    reply(runner.current, "garbage\n", 1)
    compare(notices.count, 1)
    compare(notices.signalArguments[0][0], "Dispatch settings could not be saved")
    compare(d.dispatchStartRunners.length, 0)

    var left = bareReady(); if (!left) return
    var leftNotices = spyC.createObject(tc, { target: left, signalName: "noticeRequested" })
    left.dispatchStart()
    var leftRunner = left.dispatchStartRunners[0]
    left.project = tc.rootB
    reply(leftRunner.current, startOk("r-2", ""), 0)
    reply(leftRunner.current, "garbage\n", 1)
    compare(leftNotices.count, 0, "no notice about A once the project changed")
    compare(left.dispatchStartRunners.length, 0)

    var ok = bareReady(); if (!ok) return
    var okNotices = spyC.createObject(tc, { target: ok, signalName: "noticeRequested" })
    ok.dispatchStart()
    var okRunner = ok.dispatchStartRunners[0]
    reply(okRunner.current, startOk("r-3", ""), 0)
    reply(okRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
    compare(okNotices.count, 0, "a saved write says nothing")
  }
```

- [ ] **Step 2: Copy the 59 dispatch tests in, with the RunStore/RunControlStore redirects**

Save this script as `/tmp/move_tests.py` and run `python3 /tmp/move_tests.py` from the worktree root. It copies `tst_run_store.qml` lines 2831-2841 (the `// ---- dispatch (S3 3.1)` header, `previewCmd`, `startCmd`, `dispatchSettings()`) and 2871-4210 (`dispatchCards()` through `test_a_late_blocked_start_reply_changes_nothing`, including the `// ---- dispatch: story target, retarget and keyed prefix (2.1)` section) — skipping the three run-settings tests that stay — and redirects every read, write or call of a member that stays outside the dispatch store: `X.project`, `X.active`, `X.runs`, `X.runSettingsRunner`, `X.snapshotRunner` → `runsOf(X).…`; `X.flashText`, `X.notifyOnEscalation`, `X.settingsSaveRunner` → `controlOf(X).…`. Nothing else changes; reads of `X.runSettings` stay on the dispatch store (its bound input). `tst_run_store.qml` itself is not modified.

```python
import re
src = open("tests/core/stores/tst_run_store.qml").read().split("\n")
lines = src[2831 - 1:2841] + src[2871 - 1:4210]
assert lines[0] == "  // ---- dispatch (S3 3.1)", lines[0]
assert lines[-1] == "  }" and src[4212 - 1] == "  // ---- list snapshots"
text = "\n".join(lines)
assert text.count("function test_") == 59
runs_re = re.compile(r"\b(?!tc\b)([a-z][A-Za-z]*)\.(project|active|runs|runSettingsRunner|snapshotRunner)\b")
control_re = re.compile(r"\b(?!tc\b)([a-z][A-Za-z]*)\.(flashText|notifyOnEscalation|settingsSaveRunner)\b")
text, n_runs = runs_re.subn(r"runsOf(\1).\2", text)
text, n_control = control_re.subn(r"controlOf(\1).\2", text)
assert (n_runs, n_control) == (43, 5), (n_runs, n_control)
path = "tests/core/stores/tst_run_dispatch_store.qml"
with open(path, "a") as out:
    out.write(text + "\n}\n")
```

Expected: no output, exit 0. Then check:

Run: `grep -c 'function test_' tests/core/stores/tst_run_dispatch_store.qml`
Expected: `65` (6 new + 59 moved)

- [ ] **Step 3: Run the new test file to verify it fails**

Run: `timeout 900 bash tests/run.sh tst_run_dispatch_store`
Expected: pytest passes, then `== tests/core/stores/tst_run_dispatch_store.qml` reports failures: every test fails at `fail(comp.errorString())` because `RunDispatchStore.qml` does not exist (the message names `RunDispatchStore.qml`), and the script exits 1.

- [ ] **Step 4: Create `core/stores/RunDispatchStore.qml`**

Exactly this content. The members are `RunStore.qml`'s (lines 187-203, 229-232, 1059-1391, 1423-1438, 1478-1485, 1505-1538) with `store.` → `dispatch.`, plus these edits only: the header and the inputs/signals block; `createObject(dispatch, …)`; in `dispatchStartReplied`, `store.runSettings = settings` → `dispatch.runSettingsUpdated(settings)` and `store.refresh()` → `dispatch.refreshRequested("all")` (same position, so the order is kept) and its comment names them; in `dispatchSaveReplied`, `store.flash(…)` → `dispatch.noticeRequested(…)`; and the two reactions `onActiveChanged` / `onProjectChanged`.

```qml
import QtQml
import Quickshell
import Quickshell.Io
import "../domain/results.js" as Results
import "../domain/runs.js" as Runs

// Dispatch (S3 3.1): starting an am run. The UI opens it for a target
// (openDispatch), edits the form (setDispatchField) and presses Start
// (dispatchStart); the store checks the form, previews it with
// dispatch-preview.py and starts it with start-run.py, one HelperRunner per
// Start, which after an ok start writes the saved values with viewer-state.py
// set-run-settings. `dispatchState` is idle | previewing | ready | refused |
// starting | started | failed. Every object here is replaced, never changed
// in place. The backend directory, the open project's root, the panel-open
// flag, the run list and the open project's run settings are handed to it
// from outside -- it never reaches for another store. It asks for a
// re-snapshot (refreshRequested), a footer sentence (noticeRequested) and
// the run settings an ok start saves (runSettingsUpdated; it never writes
// its own runSettings), and announces a start (dispatchStarted). A project
// change resets it; closing the panel closes it unless a start is in flight.
// App composes it as `app.runDispatch`.
Scope {
  id: dispatch

  property string backendDir: ""      // <plugin>/core/backend/
  property string project: ""         // the open project's root path; "" when none is open
  property bool active: false         // App binds this to "panel open" (app.panelOpen)
  property var runs: []               // the run store's merged run list; App binds it
  property var runSettings: ({})      // the open project's run settings; App binds it, the store never writes it

  // A re-snapshot is wanted: always "all" (every usable root) here.
  signal refreshRequested(var roots)
  // A sentence for the footer flash.
  signal noticeRequested(string text)
  // After an ok start of this dispatch: the open project's run settings as
  // that start saves them (prefixByMilestone merged per milestone id).
  signal runSettingsUpdated(var settings)

  // Closing the panel closes the dispatch; a start in flight refuses and
  // lands normally.
  onActiveChanged: if (!dispatch.active) dispatch.closeDispatch()
  // The dispatch is the old project's, even mid-start: a start already
  // launched still runs, and its reply is no longer this dispatch's.
  onProjectChanged: dispatch.resetDispatch()

  property string dispatchState: "idle"
  property var dispatchTarget: null     // Runs.dispatchPlan of the opened target; null while idle
  property string dispatchTargetLabel: "" // Runs.dispatchLabel of the opened target; "" while idle
  property var dispatchForm: null       // {base, prefix, verify, parallelism, allowNoVerification}; null while idle
  property var dispatchPreview: null    // Runs.previewSummary of the latest good preview
  property string dispatchError: ""     // the sentence for refused / failed
  property string dispatchErrorType: "" // am's or the helper's error.type, "Form", "Target" or ""
  property var dispatchErrors: []       // Runs.validateDispatch errors of a form refusal
  property var dispatchSuggest: null    // a blocked story's milestone {id, title}, which retargetToMilestone() opens; else null
  property string dispatchRunId: ""     // the started run's id; "" when none (yet)
  property string dispatchMessage: ""   // start-run.py's message after a start
  property string dispatchLog: ""       // a failed start's log path
  property string dispatchLogTail: ""   // the end of that log
  property var dispatchExitCode: null   // a failed start's exit code, when a number
  // A start for the current project went: the run id, or null while am does
  // not list it yet.
  signal dispatchStarted(var runId)

  readonly property alias dispatchDefaultsRunner: dispatchDefaultsRunner
  readonly property alias dispatchPreviewRunner: dispatchPreviewRunner
  readonly property alias dispatchDebounceTimer: dispatchDebounceTimer
  readonly property alias dispatchStartRunners: dispatchBook.runners // in-flight start runners, oldest first

  // No refusal, failure or suggestion to show.
  function clearDispatchError() {
    dispatch.dispatchError = ""
    dispatch.dispatchErrorType = ""
    dispatch.dispatchErrors = []
    dispatch.dispatchLog = ""
    dispatch.dispatchLogTail = ""
    dispatch.dispatchExitCode = null
    dispatch.dispatchSuggest = null
  }

  // Every dispatch field back to its "none" value; runSettings stays. The
  // pending check, the preview and the defaults lookup are dropped; a start
  // already launched runs on, but its reply is no longer this dispatch's.
  function resetDispatch() {
    dispatchDebounceTimer.stop()
    dispatchPreviewRunner.cancel()
    dispatchDefaultsRunner.cancel()
    dispatchBook.startRunner = null
    dispatchBook.baseTouched = false
    dispatchBook.defaultsPending = false
    dispatchBook.cardMap = null
    dispatchBook.milestone = null
    dispatch.dispatchState = "idle"
    dispatch.dispatchTarget = null
    dispatch.dispatchTargetLabel = ""
    dispatch.dispatchForm = null
    dispatch.dispatchPreview = null
    dispatch.clearDispatchError()
    dispatch.dispatchRunId = ""
    dispatch.dispatchMessage = ""
  }

  // Opens the dispatch for a brd card (as Board.indexTree() leaves it) or
  // "board", with its {id: card} map, and returns whether it may be started.
  // Refused (false, nothing changes) without a project or while a start is in
  // flight. Every opening sets dispatchTargetLabel and records cardMap and
  // cardMap's entry for the target's milestone (Runs.dispatchMilestone), or
  // null. A target dispatchPlan does not offer is `refused` at once; any
  // other starts from dispatchDefaults with this project's runSettings and
  // the Runs snapshot, and looks up the default branch before anything is
  // checked.
  function openDispatch(card, cardMap) {
    if (dispatch.project === "" || dispatch.dispatchState === "starting") return false
    dispatch.resetDispatch()
    var plan = Runs.dispatchPlan(card, cardMap)
    var milestone = Runs.dispatchMilestone(card, cardMap)
    var isMap = cardMap !== null && typeof cardMap === "object"
    dispatchBook.cardMap = cardMap
    dispatchBook.milestone = milestone !== null && isMap && Runs.hasKey(cardMap, milestone.id) ? cardMap[milestone.id] : null
    dispatch.dispatchTarget = plan
    dispatch.dispatchTargetLabel = Runs.dispatchLabel(card, cardMap)
    if (!plan.offered) {
      dispatch.dispatchState = "refused"
      dispatch.dispatchError = plan.reason
      dispatch.dispatchErrorType = "Target"
      return false
    }
    var d = Runs.dispatchDefaults({ defaultBranch: "", settings: dispatch.runSettings }, card, cardMap, dispatch.runs)
    dispatch.dispatchForm = { base: d.base, prefix: d.prefix, verify: d.verify, parallelism: d.parallelism,
                           allowNoVerification: d.allowNoVerification }
    dispatch.dispatchState = "previewing"
    dispatchBook.defaultsPending = true
    dispatchDefaultsRunner.run(["--defaults", dispatch.project])
    return true
  }

  // Back to idle. Refused while a start is in flight: its outcome must land in
  // a dialog that still shows what was started.
  function closeDispatch() {
    if (dispatch.dispatchState === "starting") return false
    dispatch.resetDispatch()
    return true
  }

  // The milestone a StoryBlockedError refusal offers: the recorded milestone
  // card as Runs.dispatchMilestone's {id, title} when the target is a story
  // and its milestone is known, else null.
  function blockedSuggest() {
    if (dispatch.dispatchTarget === null || dispatch.dispatchTarget.level !== "story" || dispatchBook.milestone === null) return null
    return Runs.dispatchMilestone(dispatchBook.milestone, dispatchBook.cardMap)
  }

  // From a blocked story's refusal (`refused` with a dispatchSuggest), opens
  // the dispatch afresh on the milestone card and cardMap recorded at the
  // story's opening and returns openDispatch's result. Refused (false,
  // nothing changes) in any other state or refusal.
  function retargetToMilestone() {
    if (dispatch.dispatchState !== "refused" || dispatch.dispatchSuggest === null) return false
    return dispatch.openDispatch(dispatchBook.milestone, dispatchBook.cardMap)
  }

  // A copy of the form with one field set as given; verify is copied as a
  // fresh array when it is one. The store converts nothing else.
  function withField(form, name, value) {
    var next = Runs.copyMap(form)
    next[name] = name === "verify" && Array.isArray(value) ? value.slice() : value
    return next
  }

  // The helpers' target words: milestone ID, card ID or board.
  function dispatchTargetArgs() {
    var plan = dispatch.dispatchTarget
    return plan.command === "board" ? ["board"] : [plan.command, plan.flags[1]]
  }

  // The form's verify commands that are non-blank strings, verbatim, in order.
  function dispatchCommands(form) {
    var list = Array.isArray(form.verify) ? form.verify : []
    return list.filter(function(c) { return typeof c === "string" && c.trim() !== "" })
  }

  // The options the preview and the start share. A blank base is left out, so
  // am uses its own default; each verify command is one argument.
  function dispatchOptionArgs() {
    var form = dispatch.dispatchForm
    var args = []
    var base = typeof form.base === "string" ? form.base.trim() : ""
    if (base !== "") args.push("--base-branch", base)
    args.push("--branch-prefix", form.prefix.trim(), "--max-concurrent", String(form.parallelism))
    var commands = dispatch.dispatchCommands(form)
    for (var i = 0; i < commands.length; i++) args.push("--verify", commands[i])
    if (form.allowNoVerification === true) args.push("--allow-no-verification")
    return args
  }

  // The --defaults reply: a non-blank default branch becomes base unless the
  // user set base since the opening; anything else leaves base as it is.
  // Then the form is checked at once.
  function dispatchDefaultsReplied(stdout) {
    if (!dispatchBook.defaultsPending || dispatch.dispatchState !== "previewing") return
    dispatchBook.defaultsPending = false
    var envelope = Results.parseEnvelope(stdout)
    var data = envelope !== null && envelope.ok === true ? envelope.data : null
    var branch = data !== null && typeof data === "object" && typeof data.default_branch === "string"
        ? data.default_branch.trim() : ""
    if (branch !== "" && !dispatchBook.baseTouched) dispatch.dispatchForm = dispatch.withField(dispatch.dispatchForm, "base", branch)
    dispatch.checkDispatch()
  }

  // The form is checked: an invalid one is refused and launches nothing, a
  // subtask is ready (am has no dry run for one card), a milestone, a story
  // or the board is previewed. Waits for the defaults lookup, whose reply checks.
  function checkDispatch() {
    if (dispatchBook.defaultsPending || dispatch.dispatchState !== "previewing") return
    dispatchDebounceTimer.stop()
    var result = Runs.validateDispatch(dispatch.dispatchForm)
    if (!result.ok) {
      dispatch.dispatchState = "refused"
      dispatch.dispatchErrors = result.errors
      dispatch.dispatchError = result.errors[0].message
      dispatch.dispatchErrorType = "Form"
      return
    }
    if (dispatch.dispatchTarget.level === "subtask") {
      dispatch.dispatchState = "ready"
      return
    }
    dispatchPreviewRunner.run([dispatch.project].concat(dispatch.dispatchTargetArgs(), dispatch.dispatchOptionArgs()))
  }

  // The newest preview's reply for this project and these values (a form
  // change cancels the runner). ok: ready with Runs.previewSummary for the
  // target's level, except a story with nothing left, refused as `Nothing
  // left to run` (Empty); am's refusal: its message verbatim, and for a
  // StoryBlockedError the blockedSuggest() milestone; anything else cannot
  // be read.
  function dispatchPreviewReplied(stdout) {
    if (dispatch.dispatchState !== "previewing") return
    var envelope = Results.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var level = dispatch.dispatchTarget.level
      var preview = Runs.previewSummary(envelope.data, level)
      if (level === "story" && preview.summary === "Nothing left to run") {
        dispatch.dispatchState = "refused"
        dispatch.dispatchError = preview.summary
        dispatch.dispatchErrorType = "Empty"
        return
      }
      dispatch.dispatchPreview = preview
      dispatch.dispatchState = "ready"
      return
    }
    var err = envelope !== null && envelope.ok === false ? envelope.error : null
    var message = err !== null && typeof err === "object" && typeof err.message === "string" ? err.message : ""
    dispatch.dispatchState = "refused"
    if (message.trim() !== "") {
      dispatch.dispatchError = message
      dispatch.dispatchErrorType = typeof err.type === "string" ? err.type : ""
      if (dispatch.dispatchErrorType === "StoryBlockedError") dispatch.dispatchSuggest = dispatch.blockedSuggest()
    } else {
      dispatch.dispatchError = "The preview could not be read"
      dispatch.dispatchErrorType = ""
    }
  }

  // One form field changed (name one of base, prefix, verify, parallelism,
  // allowNoVerification) while the form may be edited: back to previewing,
  // the preview, any refusal or failure and any preview in flight dropped,
  // and the 400 ms check restarted, so a burst of changes costs one check.
  // Refused (false, nothing changes) for another name, without a form, and
  // while idle, starting or started.
  function setDispatchField(name, value) {
    if (["base", "prefix", "verify", "parallelism", "allowNoVerification"].indexOf(name) < 0) return false
    var state = dispatch.dispatchState
    if (state !== "previewing" && state !== "ready" && state !== "refused" && state !== "failed") return false
    if (dispatch.dispatchForm === null) return false
    dispatch.dispatchForm = dispatch.withField(dispatch.dispatchForm, name, value)
    if (name === "base") dispatchBook.baseTouched = true
    dispatch.dispatchState = "previewing"
    dispatch.dispatchPreview = null
    dispatch.clearDispatchError()
    dispatchPreviewRunner.cancel()
    dispatchDebounceTimer.restart()
    return true
  }

  // A fresh {milestone id: prefix} map: stored's own entries when stored is
  // an object that is not an array, then entry's, which override them, as
  // set-run-settings merges prefixByMilestone.
  function mergedPrefixes(stored, entry) {
    var merged = stored !== null && typeof stored === "object" && !Array.isArray(stored) ? Runs.copyMap(stored) : {}
    for (var id in entry) merged[id] = entry[id]
    return merged
  }

  // Start: only from ready. start-run.py runs on a HelperRunner of its own
  // (guard "", madeFor this project), which no preview, project switch or
  // other Start stops. The settings a successful start saves are fixed now,
  // from this project's runSettings: the non-blank verify commands sent, the
  // opt-out, the prefix sent followed by the stored history without it (at
  // most 20), the parallelism and, for a story or milestone whose milestone
  // card is known, prefixByMilestone {<milestone id>: prefix sent}.
  function dispatchStart() {
    if (dispatch.dispatchState !== "ready") return false
    var form = dispatch.dispatchForm
    var prefix = form.prefix.trim()
    var history = [prefix]
    var stored = Array.isArray(dispatch.runSettings.prefixHistory) ? dispatch.runSettings.prefixHistory : []
    for (var i = 0; i < stored.length && history.length < 20; i++) {
      var p = stored[i]
      if (typeof p === "string" && p.trim() !== "" && p !== prefix) history.push(p)
    }
    var saved = { verify: dispatch.dispatchCommands(form), allowNoVerification: form.allowNoVerification === true,
                  prefixHistory: history, parallelism: form.parallelism }
    var level = dispatch.dispatchTarget.level
    if ((level === "story" || level === "milestone") && dispatchBook.milestone !== null) {
      var keyed = {}
      keyed[dispatchBook.milestone.id] = prefix
      saved.prefixByMilestone = keyed
    }
    var runner = dispatchStartC.createObject(dispatch, { madeFor: dispatch.project, savedJson: JSON.stringify(saved) })
    dispatchBook.runners = dispatchBook.runners.concat([runner])
    dispatchBook.startRunner = runner
    dispatch.dispatchState = "starting"
    runner.run([dispatch.project].concat(dispatch.dispatchTargetArgs(), dispatch.dispatchOptionArgs()))
    return true
  }

  // A start runner's reply is this dispatch's: it was made in the current
  // project and is the runner that put the store into `starting` (an idle
  // reset, and so a project switch, forgets it).
  function isHereStart(runner) {
    return runner.madeFor === dispatch.project && dispatchBook.startRunner === runner
  }

  // start-run.py's reply. When it is this dispatch's: ok gives `started`,
  // the run id and message, the saved values over runSettings
  // (runSettingsUpdated, prefixByMilestone merged per milestone id), a
  // re-snapshot of every root (refreshRequested("all")) and
  // dispatchStarted(id or null);
  // a StoryBlockedError gives `refused` with am's message, no log fields and
  // the blockedSuggest() milestone; anything else gives `failed` with what
  // the helper said. After any successful start, wherever it was made, the
  // same runner writes the saved values for the project it was made in.
  function dispatchStartReplied(runner, stdout) {
    if (runner.saving) {
      dispatch.dispatchSaveReplied(runner, stdout)
      return
    }
    var here = dispatch.isHereStart(runner)
    var envelope = Results.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      if (here) {
        dispatch.dispatchRunId = typeof envelope.run_id === "string" ? envelope.run_id : ""
        dispatch.dispatchMessage = typeof envelope.message === "string" ? envelope.message : ""
        var settings = Runs.copyMap(dispatch.runSettings)
        // Parsed from the JSON that is written: a var property hands back a
        // list Runs.dispatchDefaults does not take for an array.
        var saved = JSON.parse(runner.savedJson)
        for (var key in saved) {
          settings[key] = key === "prefixByMilestone" ? dispatch.mergedPrefixes(settings.prefixByMilestone, saved[key]) : saved[key]
        }
        dispatch.runSettingsUpdated(settings)
        dispatch.dispatchState = "started"
        dispatch.refreshRequested("all")
        dispatch.dispatchStarted(dispatch.dispatchRunId !== "" ? dispatch.dispatchRunId : null)
      }
      runner.saving = true
      runner.script = dispatch.backendDir + "projects/viewer-state.py"
      runner.run(["set-run-settings", runner.madeFor, runner.savedJson])
      return
    }
    if (here) {
      var failure = envelope !== null && envelope.ok === false ? envelope : {}
      var err = failure.error
      var isErr = err !== null && err !== undefined && typeof err === "object"
      var message = isErr && typeof err.message === "string" ? err.message : ""
      var type = isErr && typeof err.type === "string" ? err.type : ""
      var blocked = type === "StoryBlockedError"
      dispatch.dispatchState = blocked ? "refused" : "failed"
      dispatch.dispatchError = message.trim() !== "" ? message : "The launch could not be read"
      dispatch.dispatchErrorType = type
      dispatch.dispatchLog = !blocked && typeof failure.log === "string" ? failure.log : ""
      dispatch.dispatchLogTail = !blocked && typeof failure.log_tail === "string" ? failure.log_tail : ""
      dispatch.dispatchExitCode = !blocked && typeof failure.exit_code === "number" ? failure.exit_code : null
      dispatch.dispatchSuggest = blocked ? dispatch.blockedSuggest() : null
    }
    dispatch.dropStartRunner(runner)
  }

  // set-run-settings after a start: a failure is said only while the
  // dispatch is still this one. The runner then goes.
  function dispatchSaveReplied(runner, stdout) {
    var reply = Results.parseEnvelope(stdout)
    if (dispatch.isHereStart(runner) && !(reply !== null && reply.ok === true)) dispatch.noticeRequested("Dispatch settings could not be saved")
    dispatch.dropStartRunner(runner)
  }

  // A start runner's work is over: it leaves dispatchStartRunners and is destroyed.
  function dropStartRunner(runner) {
    dispatchBook.runners = dispatchBook.runners.filter(function(r) { return r !== runner })
    if (dispatchBook.startRunner === runner) dispatchBook.startRunner = null
    runner.destroy()
  }

  // dispatch-preview.py --defaults, once per opening. Guarded by the project:
  // a reply for a project the user has left is dropped.
  HelperRunner {
    id: dispatchDefaultsRunner
    script: dispatch.backendDir + "runs/dispatch-preview.py"
    guard: dispatch.project
    onFinished: function(stdout, exitCode) { dispatch.dispatchDefaultsReplied(stdout) }
  }

  // The dispatch preview; latest wins, and every form change cancels it.
  HelperRunner {
    id: dispatchPreviewRunner
    script: dispatch.backendDir + "runs/dispatch-preview.py"
    guard: dispatch.project
    onFinished: function(stdout, exitCode) { dispatch.dispatchPreviewReplied(stdout) }
  }

  // only while a change waits to be checked.
  Timer {
    id: dispatchDebounceTimer
    objectName: "dispatchDebounceTimer"
    interval: 400
    repeat: false
    onTriggered: dispatch.checkDispatch()
  }

  // The dispatch's own bookkeeping; kept apart so consumers cannot write it.
  // `startRunner` is the runner that put the store into `starting`, forgotten
  // by an idle reset (and so by a project switch); `baseTouched` says the user
  // set base since the opening; `defaultsPending` that the --defaults lookup
  // has not replied yet; `cardMap` and `milestone` are the opening's card map
  // and its entry for the target's milestone card (null when unknown).
  QtObject {
    id: dispatchBook
    property var runners: []
    property var startRunner: null
    property bool baseTouched: false
    property bool defaultsPending: false
    property var cardMap: null
    property var milestone: null
  }

  // One HelperRunner per Start. Guard "": start-run.py may take ~20 s, and
  // neither a preview, a project switch nor a Start in another project may
  // stop it. After a successful start the same runner writes the settings
  // for `madeFor`; it goes when that write replies, or at once after a
  // failed start.
  Component {
    id: dispatchStartC

    HelperRunner {
      id: sr
      property string madeFor: ""     // the project the start was made in
      property string savedJson: ""   // `saved` as set-run-settings takes it
      property bool saving: false     // the settings write is in flight
      script: dispatch.backendDir + "runs/start-run.py"
      guard: ""
      onFinished: function(stdout, exitCode) { dispatch.dispatchStartReplied(sr, stdout) }
    }
  }
}
```

- [ ] **Step 5: Run the new test file to verify it passes**

Run: `timeout 900 bash tests/run.sh tst_run_dispatch_store`
Expected: `Totals: 67 passed, 0 failed` for `tst_run_dispatch_store.qml` (65 tests plus initTestCase/cleanupTestCase), no `TypeError` / `ReferenceError` lines, exit 0.

- [ ] **Step 6: Run the full suite**

Run: `timeout 900 bash tests/run.sh`
Expected: exit 0; every `Totals:` line shows `0 failed`; `tests/architecture` passes (the new store's imports are allowed).

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunDispatchStore.qml tests/core/stores/tst_run_dispatch_store.qml
git commit -m "feat(runs): RunDispatchStore owns the dispatch state machine, built alone"
```

---

### Task 2: `RunStore` shims, App composition and the test moves

**Files:**
- Modify: `core/stores/RunStore.qml` (header 13-15 and 31-34; shims after 166; delete 181-203, 229-232, the last two lines and comment of `stopLive` 378-389, the dispatch lines and comment of `projectSwitched` 660-667, 1057-1392, 1423-1438, 1477-1485, 1505-1539)
- Modify: `core/stores/App.qml:103-129` and after `runAlerts` (155)
- Modify: `tests/core/stores/tst_run_store.qml`
- Modify: `tests/core/stores/tst_app_runs.qml`

**Interfaces:**
- Consumes: everything Task 1 produced (names above).
- Produces: `RunStore.dispatchStore: var` (the handle, `null` by default); `App.runDispatch: RunDispatchStore`; on `RunStore`, the shims `dispatchState` (writable), `dispatchTarget`, `dispatchTargetLabel`, `dispatchForm`, `dispatchPreview`, `dispatchError`, `dispatchErrorType`, `dispatchErrors`, `dispatchSuggest`, `dispatchRunId`, `dispatchMessage`, `dispatchLog`, `dispatchLogTail`, `dispatchExitCode`, `dispatchDefaultsRunner`, `dispatchPreviewRunner`, `dispatchDebounceTimer`, `dispatchStartRunners`, `openDispatch`, `closeDispatch`, `retargetToMilestone`, `setDispatchField`, `dispatchStart`, `checkDispatch`, and the re-emitted `signal dispatchStarted(var runId)`.

- [ ] **Step 1: Confirm which dispatch members outside callers write or call**

Run: `grep -rnE 'runs\.dispatch[A-Za-z]* *=[^=]' ui tests`
Expected: exactly four lines — `tests/ui/tst_dispatch_flow.qml:203`, `tests/ui/tst_shortcuts.qml:778`, `:836`, `:861` — all writing `dispatchState` (the only writable shim).

Run:
```bash
for n in clearDispatchError resetDispatch blockedSuggest withField dispatchTargetArgs dispatchCommands dispatchOptionArgs dispatchDefaultsReplied dispatchPreviewReplied mergedPrefixes isHereStart dispatchStartReplied dispatchSaveReplied dropStartRunner; do echo "$n: $(grep -rlw "$n" ui tests --include=*.qml --include=*.js | grep -v tst_run_dispatch_store | tr '\n' ' ')"; done
```
Expected: all fourteen names print an empty list (no `ui/` or test file calls them). These get no shim. If any prints a file, stop: that name needs a one-line forward shim like `checkDispatch`'s.

- [ ] **Step 2: Rewire `tst_run_store.qml`: delete the moved tests, add R-D1 … R-D5, fix the two dispatch reads**

Save as `/tmp/runstore_tests_edit.py` and run `python3 /tmp/runstore_tests_edit.py`. It:
- adds "The dispatch is tested in tst_run_dispatch_store.qml." to the header comment;
- turns the `// ---- dispatch (S3 3.1)` header into `// ---- run settings` and drops `previewCmd` / `startCmd` (only the moved tests used them); keeps `dispatchSettings()` and the three run-settings tests;
- deletes `dispatchCards()` through `test_a_late_blocked_start_reply_changes_nothing` (asserting 59 tests are removed);
- appends the section `// ---- the dispatch shims (split-runstore 4.1)` with `dispatchCards()` (needed by R-D tests), `wireDispatch(store, bound)` and R-D1 … R-D5;
- gives `test_a_project_switch_leaves_the_run_list_and_the_live_state_alone` the handle and updates the timer census (see "Notes on the spec").

```python
p = "tests/core/stores/tst_run_store.qml"
t = open(p).read()

def swap(t, old, new):
    assert t.count(old) == 1, old[:80]
    return t.replace(old, new)

t = swap(t, """// objects. The run controls and the notify switch are tested in
// tst_run_control_store.qml, the alerts in tst_run_alerts_store.qml.""", """// objects. The run controls and the notify switch are tested in
// tst_run_control_store.qml, the alerts in tst_run_alerts_store.qml. The
// dispatch is tested in tst_run_dispatch_store.qml.""")

# The section header and the two command prefixes only the moved tests use.
t = swap(t, """  // ---- dispatch (S3 3.1)

  property string previewCmd: "python3|/plugin/core/backend/runs/dispatch-preview.py|"
  property string startCmd: "python3|/plugin/core/backend/runs/start-run.py|"

  // get-run-settings with every key""", """  // ---- run settings

  // get-run-settings with every key""")

# The moved tests and their helpers: from dispatchCards() to the end of
# test_a_late_blocked_start_reply_changes_nothing().
start = t.index("""  // A milestone, its story, the story's subtask and a done milestone, as
  // Board.indexTree() leaves them; the object is also their {id: card} map.
  function dispatchCards() {""")
end_marker = """    compare(back.dispatchTargetLabel, 'Milestone "M3 Document runs"')
  }

"""
end = t.index(end_marker, start) + len(end_marker)
assert t[start:end].count("function test_") == 59
t = t[:start] + t[end:]

shims = '''
  // ---- the dispatch shims (split-runstore 4.1)

  // A milestone, its story, the story's subtask and a done milestone, as
  // Board.indexTree() leaves them; the object is also their {id: card} map.
  function dispatchCards() {
    return {
      m1: { id: "m1", title: "M3 Document runs", status: "todo", parentId: "", depth: 0 },
      s1: { id: "s1", title: "Dispatch store", status: "todo", parentId: "m1", depth: 1 },
      t1: { id: "t1", title: "RunStore dispatch", status: "todo", parentId: "s1", depth: 2 },
      d1: { id: "d1", title: "M2 Monitor runs", status: "done", parentId: "", depth: 0 }
    }
  }

  // A RunDispatchStore with backendDir copied, set as `store`'s dispatchStore
  // handle. When `bound`, it is wired the way App wires app.runDispatch:
  // project, active, runs and runSettings bound to the run store's own;
  // refreshRequested to refresh() ("all") or requestSnapshot(roots);
  // noticeRequested to the paired control store's flash; runSettingsUpdated
  // into the run store's runSettings. Otherwise nothing is bound or routed.
  function wireDispatch(store, bound) {
    var comp = Qt.createComponent("../../../core/stores/RunDispatchStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var d = comp.createObject(tc, { backendDir: store.backendDir })
    if (bound) {
      d.project = Qt.binding(function() { return store.project })
      d.active = Qt.binding(function() { return store.active })
      d.runs = Qt.binding(function() { return store.runs })
      d.runSettings = Qt.binding(function() { return store.runSettings })
      d.refreshRequested.connect(function(roots) {
        if (roots === "all") store.refresh()
        else store.requestSnapshot(roots)
      })
      d.noticeRequested.connect(function(text) { controlOf(store).flash(text) })
      d.runSettingsUpdated.connect(function(settings) { store.runSettings = settings })
    }
    store.dispatchStore = d
    return d
  }

  // R-D1 and Review Focus 4
  function test_without_a_dispatch_store_the_shims_are_empty_and_inert() {
    var store = make(); if (!store) return
    compare(store.dispatchStore, null)
    compare(store.dispatchState, "idle")
    compare(store.dispatchTarget, null)
    compare(store.dispatchForm, null)
    compare(store.dispatchPreview, null)
    compare(store.dispatchSuggest, null)
    compare(store.dispatchExitCode, null)
    compare(store.dispatchTargetLabel, "")
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    compare(store.dispatchRunId, "")
    compare(store.dispatchMessage, "")
    compare(store.dispatchLog, "")
    compare(store.dispatchLogTail, "")
    compare(JSON.stringify(store.dispatchErrors), "[]")
    compare(store.dispatchDefaultsRunner, null)
    compare(store.dispatchPreviewRunner, null)
    compare(store.dispatchDebounceTimer, null)
    compare(JSON.stringify(store.dispatchStartRunners), "[]")
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), undefined)
    compare(store.closeDispatch(), undefined)
    compare(store.retargetToMilestone(), undefined)
    compare(store.setDispatchField("prefix", "x"), undefined)
    compare(store.dispatchStart(), undefined)
    compare(store.checkDispatch(), undefined)
    store.dispatchState = "ready"
    compare(store.dispatchState, "idle", "no handle: a write is put back")
    store.active = true
    store.active = false
    store.project = rootA
    store.project = rootB
    compare(store.dispatchState, "idle")
  }

  // R-D2
  function test_the_dispatch_shims_follow_the_dispatch_store_and_notify() {
    var store = makeWithProject(rootA); if (!store) return
    var d = wireDispatch(store, true); if (!d) return
    verify(store.dispatchDefaultsRunner === d.dispatchDefaultsRunner)
    verify(store.dispatchPreviewRunner === d.dispatchPreviewRunner)
    verify(store.dispatchDebounceTimer === d.dispatchDebounceTimer)
    verify(store.dispatchStartRunners === d.dispatchStartRunners)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "dispatchStateChanged" })
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(spy.count, 1, "the shim notifies like the original")
    compare(store.dispatchState, "previewing")
    verify(store.dispatchTarget === d.dispatchTarget)
    compare(store.dispatchTargetLabel, 'Milestone "M3 Document runs"')
    verify(store.dispatchForm === d.dispatchForm)
    compare(store.setDispatchField("prefix", "x"), true)
    compare(d.dispatchForm.prefix, "x")
    compare(store.dispatchForm.prefix, "x")
    compare(store.closeDispatch(), true)
    compare(d.dispatchState, "idle")
    compare(store.dispatchState, "idle")
  }

  // R-D3 and Review Focus 1
  function test_writing_the_dispatch_state_shim_reaches_the_dispatch_store() {
    var store = makeWithProject(rootA); if (!store) return
    var d = wireDispatch(store, true); if (!d) return
    store.dispatchState = "starting"
    compare(d.dispatchState, "starting", "the write goes to the dispatch store")
    compare(store.closeDispatch(), false, "and closeDispatch sees it")
    d.resetDispatch()
    compare(store.dispatchState, "idle", "the shim follows the dispatch store again")
  }

  // R-D4 and Review Focus 2
  function test_dispatch_started_is_re_emitted_once() {
    var store = make(); if (!store) return
    var d = wireDispatch(store, true); if (!d) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "dispatchStarted" })
    d.dispatchStarted("r-9")
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], "r-9")
  }

  // R-D5 and Review Focus 4
  function test_closing_and_switching_the_run_store_touch_no_dispatch() {
    var store = makeWithProject(rootA); if (!store) return
    var d = wireDispatch(store, false); if (!d) return
    d.project = rootA
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(d.dispatchState, "previewing")
    store.active = true
    store.active = false
    compare(d.dispatchState, "previewing", "closing the run store leaves the dispatch")
    store.project = rootB
    compare(d.dispatchState, "previewing", "switching the run store's project leaves the dispatch")
  }
}
'''
assert t.endswith("\n  }\n}\n")
t = t[:-len("}\n")] + shims
# A project-switch test that reads the dispatch: through the shim, with a handle.
t = swap(t, """  function test_a_project_switch_leaves_the_run_list_and_the_live_state_alone() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
""", """  function test_a_project_switch_leaves_the_run_list_and_the_live_state_alone() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    if (!wireDispatch(store, true)) return
""")

# The run store's own timers: the dispatch debounce is no longer one of them.
t = swap(t, '''    compare(timers.sort().join(","), "debounceTimer,dispatchDebounceTimer,livenessTimer,pollTimer,staleTimer", "the logs add no timer")''',
            '''    compare(timers.sort().join(","), "debounceTimer,livenessTimer,pollTimer,staleTimer", "the logs add no timer")''')

open(p, "w").write(t)
```

Expected: no output, exit 0. Then:

Run: `grep -n 'dispatch' tests/core/stores/tst_run_store.qml | awk -F: '$1 < 2840'`
Expected: only the header line, the `dispatchState` read in `test_a_project_switch_leaves_the_run_list_and_the_live_state_alone` (now wired), the `wireDispatch` call there, and `dispatchSettings` uses / definition.

- [ ] **Step 3: Add A-D1 … A-D5 to `tst_app_runs.qml`**

Save as `/tmp/app_tests_edit.py` and run `python3 /tmp/app_tests_edit.py`. The four existing dispatch tests (374, 391, 403, 440) stay unchanged and keep passing through the shims.

```python
p = "tests/core/stores/tst_app_runs.qml"
t = open(p).read()

def swap(t, old, new):
    assert t.count(old) == 1, old[:80]
    return t.replace(old, new)

t = swap(t, """// each ok snapshotReplied and whose refreshRequested App routes to the run
// store. The stores' own behaviour is tested in tst_run_store.qml,
// tst_run_alerts_store.qml and tst_run_control_store.qml.""", """// each ok snapshotReplied and whose refreshRequested App routes to the run
// store, and `app.runDispatch`, which App feeds with the run store's project,
// run list and run settings and whose refreshRequested, noticeRequested and
// runSettingsUpdated App routes. The stores' own behaviour is tested in
// tst_run_store.qml, tst_run_alerts_store.qml, tst_run_control_store.qml and
// tst_run_dispatch_store.qml.""")

added = '''
  // ---- app.runDispatch (split-runstore 4.1)

  // A-D1
  function test_app_composes_run_dispatch_wired_to_the_run_store() {
    var app = make(); if (!app) return
    verify(app.runDispatch, "App composes the dispatch store")
    verify(app.runs.dispatchStore === app.runDispatch, "the run store's shim handle")
    compare(app.runDispatch.backendDir, "/plugin/core/backend/")
    compare(app.runDispatch.project, "/home/u/my proj")
    compare(app.runDispatch.active, false)
    app.panelOpen = true
    compare(app.runDispatch.active, true, "active follows panelOpen")
    app.panelOpen = false
    compare(app.runDispatch.active, false)
    verify(app.runDispatch.runs === app.runs.runs, "the run store's merged list")
    reply(app.runs.snapshotRunner.current, listReply([runningIn("r1")], []), 0)
    compare(app.runDispatch.runs.length, 1)
    verify(app.runDispatch.runs === app.runs.runs)
    reply(app.runs.runSettingsRunner.current, dispatchSettings(), 0)
    verify(app.runDispatch.runSettings === app.runs.runSettings, "the run store's run settings")
    compare(app.runDispatch.runSettings.parallelism, 4)
    app.projects.chooseProject(pB)
    compare(app.runDispatch.project, "/home/u/b", "the project follows the selection")
  }

  // A-D2 and Review Focus 3
  function test_a_start_through_app_writes_the_run_settings_back_and_keeps_the_binding() {
    var app = readyApp(); if (!app) return
    compare(app.runDispatch.dispatchStart(), true)
    reply(app.runDispatch.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(app.runDispatch.dispatchState, "started")
    compare(app.runs.runSettings.prefixByMilestone.m1, "old", "the start's values reach the run store")
    verify(app.runDispatch.runSettings === app.runs.runSettings, "the binding survives the write")
    app.projects.chooseProject(pB)
    compare(Object.keys(app.runs.runSettings).length, 0)
    compare(Object.keys(app.runDispatch.runSettings).length, 0, "B's form will not start from A's settings")
    reply(app.runs.runSettingsRunner.current, JSON.stringify({ parallelism: 9 }) + "\\n", 0)
    compare(app.runDispatch.runSettings.parallelism, 9)
  }

  // A-D3 and Review Focus 2
  function test_a_start_through_app_announces_started_once_on_each_store() {
    var app = readyApp(); if (!app) return
    var onDispatch = createTemporaryObject(spyC, tc, { target: app.runDispatch, signalName: "dispatchStarted" })
    var onRuns = createTemporaryObject(spyC, tc, { target: app.runs, signalName: "dispatchStarted" })
    compare(app.runDispatch.dispatchStart(), true)
    reply(app.runDispatch.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(onDispatch.count, 1)
    compare(onDispatch.signalArguments[0][0], "r-1")
    compare(onRuns.count, 1, "re-emitted once: Panel opens the run once")
    compare(onRuns.signalArguments[0][0], "r-1")
  }

  // A-D4
  function test_a_dispatch_notice_through_app_is_run_controls_flash() {
    var app = readyApp(); if (!app) return
    compare(app.runDispatch.dispatchStart(), true)
    var runner = app.runDispatch.dispatchStartRunners[0]
    reply(runner.current, startOk("r-1", ""), 0)
    compare(app.runControl.flashText, "")
    reply(runner.current, ctlFail("Invalid", "x"), 1)
    compare(app.runControl.flashText, "Dispatch settings could not be saved")
    compare(app.runControl.flashTimer.running, true)
  }

  // A-D5 and Review Focus 5
  function test_closing_the_panel_through_app_keeps_a_start_in_flight() {
    var app = readyApp(); if (!app) return
    app.panelOpen = true
    compare(app.runDispatch.dispatchState, "ready", "opening the panel leaves the dispatch")
    compare(app.runDispatch.dispatchStart(), true)
    var proc = app.runDispatch.dispatchStartRunners[0].current
    app.panelOpen = false
    compare(app.runDispatch.dispatchState, "starting", "a start in flight is not closed")
    compare(proc.running, true)
    reply(proc, startOk("r-1", ""), 0)
    compare(app.runDispatch.dispatchState, "started", "it lands normally")
  }
}
'''
assert t.endswith("\n  }\n}\n")
t = t[:-len("}\n")] + added
open(p, "w").write(t)
```

Expected: no output, exit 0.

- [ ] **Step 4: Run the changed test files to verify they fail**

Run: `timeout 900 bash tests/run.sh tst_run_store`
Expected: exit 1. R-D1 fails (there is no `dispatchStore` property yet, and `openDispatch` on the old store returns `false`, not `undefined`); R-D2 … R-D5 and `test_a_project_switch_leaves_the_run_list_and_the_live_state_alone` fail at `store.dispatchStore = d` ("Cannot assign to non-existent property"); `test_logs_add_no_timer_and_none_runs_while_idle` fails on the timer list (`dispatchDebounceTimer` is still a RunStore child).

Run: `timeout 900 bash tests/run.sh tst_app_runs`
Expected: exit 1; A-D1 … A-D5 fail with `TypeError` on `app.runDispatch` (undefined).

- [ ] **Step 5: Move the dispatch out of `RunStore.qml` and add the shims**

Save as `/tmp/runstore_edit.py` and run `python3 /tmp/runstore_edit.py`. It:
- edits the header: "decides only the run settings" (was "… and the dispatch"), and replaces the two dispatch sentences with "The dispatch is RunDispatchStore's; its members here are shims through `dispatchStore`.";
- inserts the shim block after the alerts shims (after `function notify(alert)`), under `// Moved to RunDispatchStore; removed by the last story`;
- deletes the dispatch comment, the 14 properties and `dispatchStarted` with its comment (it is redeclared in the shim block), the four aliases, `stopLive`'s `closeDispatch()` lines (and "and no dispatch outlives the opening (a start in flight runs to its end)" from its comment), `projectSwitched`'s `resetDispatch()` lines (and "and the dispatch" from its comment), the whole `// ---- dispatch (S3 3.1)` function section, both dispatch `HelperRunner`s, `dispatchDebounceTimer`, `dispatchBook` and `dispatchStartC`.

```python
import re
p = "core/stores/RunStore.qml"
t = open(p).read()

def cut(t, old, new=""):
    assert t.count(old) == 1, old[:80]
    return t.replace(old, new)

# Header: the open project decides only the run settings; the dispatch is RunDispatchStore's.
t = cut(t, """// the run settings and the dispatch; the attempt logs act on each run's own
// project root. Plus""", """// the run settings; the attempt logs act on each run's own project
// root. Plus""")
t = cut(t, """// Dispatch (openDispatch .. dispatchStart) previews a run with
// dispatch-preview.py and starts it with start-run.py, one HelperRunner per
// Start. Each applied list snapshot reply is announced per project
// (snapshotReplied).""", """// The dispatch is RunDispatchStore's; its members here are shims through
// `dispatchStore`. Each applied list snapshot reply is announced per project
// (snapshotReplied).""")

# The shims, after the alerts shims.
t = cut(t, """  function notify(alert) { return store.alertsStore ? store.alertsStore.notify(alert) : undefined }
""", """  function notify(alert) { return store.alertsStore ? store.alertsStore.notify(alert) : undefined }

  // Moved to RunDispatchStore; removed by the last story
  property var dispatchStore: null
  property string dispatchState: "idle"
  Binding { target: store; property: "dispatchState"; value: store.dispatchStore ? store.dispatchStore.dispatchState : "idle" }
  onDispatchStateChanged: {
    var target = store.dispatchStore ? store.dispatchStore.dispatchState : "idle"
    if (store.dispatchState === target) return
    if (store.dispatchStore) store.dispatchStore.dispatchState = store.dispatchState
    else store.dispatchState = "idle"
  }
  readonly property var dispatchTarget: store.dispatchStore ? store.dispatchStore.dispatchTarget : null
  readonly property string dispatchTargetLabel: store.dispatchStore ? store.dispatchStore.dispatchTargetLabel : ""
  readonly property var dispatchForm: store.dispatchStore ? store.dispatchStore.dispatchForm : null
  readonly property var dispatchPreview: store.dispatchStore ? store.dispatchStore.dispatchPreview : null
  readonly property string dispatchError: store.dispatchStore ? store.dispatchStore.dispatchError : ""
  readonly property string dispatchErrorType: store.dispatchStore ? store.dispatchStore.dispatchErrorType : ""
  readonly property var dispatchErrors: store.dispatchStore ? store.dispatchStore.dispatchErrors : []
  readonly property var dispatchSuggest: store.dispatchStore ? store.dispatchStore.dispatchSuggest : null
  readonly property string dispatchRunId: store.dispatchStore ? store.dispatchStore.dispatchRunId : ""
  readonly property string dispatchMessage: store.dispatchStore ? store.dispatchStore.dispatchMessage : ""
  readonly property string dispatchLog: store.dispatchStore ? store.dispatchStore.dispatchLog : ""
  readonly property string dispatchLogTail: store.dispatchStore ? store.dispatchStore.dispatchLogTail : ""
  readonly property var dispatchExitCode: store.dispatchStore ? store.dispatchStore.dispatchExitCode : null
  readonly property var dispatchDefaultsRunner: store.dispatchStore ? store.dispatchStore.dispatchDefaultsRunner : null
  readonly property var dispatchPreviewRunner: store.dispatchStore ? store.dispatchStore.dispatchPreviewRunner : null
  readonly property var dispatchDebounceTimer: store.dispatchStore ? store.dispatchStore.dispatchDebounceTimer : null
  readonly property var dispatchStartRunners: store.dispatchStore ? store.dispatchStore.dispatchStartRunners : []
  signal dispatchStarted(var runId)
  Connections {
    target: store.dispatchStore
    function onDispatchStarted(runId) { store.dispatchStarted(runId) }
  }
  function openDispatch(card, cardMap) { return store.dispatchStore ? store.dispatchStore.openDispatch(card, cardMap) : undefined }
  function closeDispatch() { return store.dispatchStore ? store.dispatchStore.closeDispatch() : undefined }
  function retargetToMilestone() { return store.dispatchStore ? store.dispatchStore.retargetToMilestone() : undefined }
  function setDispatchField(name, value) { return store.dispatchStore ? store.dispatchStore.setDispatchField(name, value) : undefined }
  function dispatchStart() { return store.dispatchStore ? store.dispatchStore.dispatchStart() : undefined }
  function checkDispatch() { return store.dispatchStore ? store.dispatchStore.checkDispatch() : undefined }

""")

# The dispatch state, its comment and the dispatchStarted declaration with its comment.
t = cut(t, """  property var runSettings: ({})

  // Dispatch (S3 3.1): starting an am run.""", """  property var runSettings: ({})

  // DISPATCH-CUT-START Dispatch (S3 3.1): starting an am run.""")
t = re.sub(r"  // DISPATCH-CUT-START .*?  signal dispatchStarted\(var runId\)\n", "", t, count=1, flags=re.S)
assert "DISPATCH-CUT-START" not in t

# The four aliases.
t = cut(t, """  readonly property alias dispatchDefaultsRunner: dispatchDefaultsRunner
  readonly property alias dispatchPreviewRunner: dispatchPreviewRunner
  readonly property alias dispatchDebounceTimer: dispatchDebounceTimer
  readonly property alias dispatchStartRunners: dispatchBook.runners // in-flight start runners, oldest first
""")

# stopLive: its comment and its last two lines.
t = cut(t, """  // The panel closed: no process and no timer is left running, and no
  // dispatch outlives the opening (a start in flight runs to its end). The
  // pending snapshot request is dropped;""", """  // The panel closed: no process and no timer is left running. The
  // pending snapshot request is dropped;""")
t = cut(t, """    store.watchWarning = ""
    // A start in flight refuses and lands normally.
    store.closeDispatch()
  }""", """    store.watchWarning = ""
  }""")

# projectSwitched: its comment and its dispatch lines.
t = cut(t, """  // registered project and stay, and no snapshot is launched. Reset: the run settings
  // (loaded for the new project on runSettingsRunner) and the dispatch.
  function projectSwitched() {
    store.runSettings = {}
    // The dispatch is the old project's, even mid-start: a start already
    // launched still runs, and its reply is no longer this dispatch's.
    store.resetDispatch()
""", """  // registered project and stay, and no snapshot is launched. Reset: the run settings
  // (loaded for the new project on runSettingsRunner).
  function projectSwitched() {
    store.runSettings = {}
""")

# The dispatch section: from its header to the end of dropStartRunner.
start = t.index("  // ---- dispatch (S3 3.1)\n")
end_marker = """    if (dispatchBook.startRunner === runner) dispatchBook.startRunner = null
    runner.destroy()
  }

"""
end = t.index(end_marker, start) + len(end_marker)
t = t[:start] + t[end:]

# The two dispatch runners.
t = cut(t, """  // dispatch-preview.py --defaults, once per opening. Guarded by the project:
  // a reply for a project the user has left is dropped.
  HelperRunner {
    id: dispatchDefaultsRunner
    script: store.backendDir + "runs/dispatch-preview.py"
    guard: store.project
    onFinished: function(stdout, exitCode) { store.dispatchDefaultsReplied(stdout) }
  }

  // The dispatch preview; latest wins, and every form change cancels it.
  HelperRunner {
    id: dispatchPreviewRunner
    script: store.backendDir + "runs/dispatch-preview.py"
    guard: store.project
    onFinished: function(stdout, exitCode) { store.dispatchPreviewReplied(stdout) }
  }

""")

# The debounce timer.
t = cut(t, """  // only while a change waits to be checked.
  Timer {
    id: dispatchDebounceTimer
    objectName: "dispatchDebounceTimer"
    interval: 400
    repeat: false
    onTriggered: store.checkDispatch()
  }

""")

# The bookkeeping and the per-Start runner component.
start = t.index("  // The dispatch's own bookkeeping; kept apart so consumers cannot write it.\n")
end_marker = """      onFinished: function(stdout, exitCode) { store.dispatchStartReplied(sr, stdout) }
    }
  }

"""
end = t.index(end_marker, start) + len(end_marker)
t = t[:start] + t[end:]

open(p, "w").write(t)
```

Expected: no output, exit 0.

- [ ] **Step 6: Compose `runDispatch` in `App.qml`**

Save as `/tmp/app_edit.py` and run `python3 /tmp/app_edit.py`. It adds `dispatchStore` to the `runs` comment's handle list, `dispatchStore: app.runDispatch` to `runs`, and the `runDispatch` block after `runAlerts`, which becomes:

```qml
  // The dispatch never imports the run store: App hands it the backend
  // directory, the open project's root, the panel-open flag, the run list and
  // the run settings, routes its refreshRequested to the run store, its
  // noticeRequested to run control's flash and its runSettingsUpdated into
  // the run store's runSettings.
  readonly property RunDispatchStore runDispatch: RunDispatchStore {
    backendDir: app.backendDir
    project: app.runs.project
    active: app.panelOpen
    runs: app.runs.runs
    runSettings: app.runs.runSettings
    onRefreshRequested: function(roots) {
      if (roots === "all") app.runs.refresh()
      else app.runs.requestSnapshot(roots)
    }
    onNoticeRequested: function(text) { app.runControl.flash(text) }
    onRunSettingsUpdated: function(settings) { app.runs.runSettings = settings }
  }
```

No `onDispatchStarted` route: `RunStore` re-emits it and Panel listens on `app.runs` (Review Focus 2).

```python
p = "core/stores/App.qml"
t = open(p).read()

def swap(t, old, new):
    assert t.count(old) == 1, old[:80]
    return t.replace(old, new)

t = swap(t, """  // stops its watch, and the stores its shims read (controlStore,
  // alertsStore).""", """  // stops its watch, and the stores its shims read (controlStore,
  // alertsStore, dispatchStore).""")
t = swap(t, """    controlStore: app.runControl
""", """    controlStore: app.runControl
    dispatchStore: app.runDispatch
""")
t = swap(t, """    projectRoots: app.runs.projectRoots
  }
""", """    projectRoots: app.runs.projectRoots
  }

  // The dispatch never imports the run store: App hands it the backend
  // directory, the open project's root, the panel-open flag, the run list and
  // the run settings, routes its refreshRequested to the run store, its
  // noticeRequested to run control's flash and its runSettingsUpdated into
  // the run store's runSettings.
  readonly property RunDispatchStore runDispatch: RunDispatchStore {
    backendDir: app.backendDir
    project: app.runs.project
    active: app.panelOpen
    runs: app.runs.runs
    runSettings: app.runs.runSettings
    onRefreshRequested: function(roots) {
      if (roots === "all") app.runs.refresh()
      else app.runs.requestSnapshot(roots)
    }
    onNoticeRequested: function(text) { app.runControl.flash(text) }
    onRunSettingsUpdated: function(settings) { app.runs.runSettings = settings }
  }
""")
open(p, "w").write(t)
```

Expected: no output, exit 0.

- [ ] **Step 7: Verify the structural invariants**

Run: `grep -nE 'dispatch-preview\.py|start-run\.py|resetDispatch|dispatchBook|dispatchStartC|store\.flash\(' core/stores/RunStore.qml`
Expected: no output (RunStore launches no dispatch helper of its own; `get-run-settings` stays).

Run: `grep -c 'get-run-settings' core/stores/RunStore.qml`
Expected: `1` or more (the run settings reload stays).

Run: `grep -nE 'onDispatchStarted' core/stores/App.qml`
Expected: no output.

Run: `grep -nE 'runSettings *=' core/stores/RunDispatchStore.qml`
Expected: no output (the store never writes its own runSettings).

- [ ] **Step 8: Run the changed test files to verify they pass**

Run: `timeout 900 bash tests/run.sh tst_run_store`
Expected: `0 failed` for `tst_run_store.qml`, exit 0.

Run: `timeout 900 bash tests/run.sh tst_app_runs`
Expected: `0 failed`, exit 0.

- [ ] **Step 9: Run the full gate**

Run: `timeout 900 bash tests/run.sh`
Expected: exit 0; every `Totals:` line `0 failed`; no `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign` or `is not a function` lines (the `tests/ui` suites write `app.runs.dispatchState` through the writable shim).

Run: `git diff --stat 7676feb -- ui tests/ui`
Expected: no output.

- [ ] **Step 10: Commit**

```bash
git add core/stores/RunStore.qml core/stores/App.qml tests/core/stores/tst_run_store.qml tests/core/stores/tst_app_runs.qml
git commit -m "refactor(runs): the dispatch moves to RunDispatchStore, RunStore keeps shims, App composes and routes runDispatch"
```

---

### Task 3: Docs — only the sentences this card makes false

**Files:**
- Modify: `docs/architecture.md:84, 91, 92, 173`

**Interfaces:**
- Consumes: the names from Tasks 1 and 2. Both store header comments were written in those tasks (`RunDispatchStore.qml`'s contract header in Task 1 Step 4, `RunStore.qml`'s two edits in Task 2 Step 5).
- Produces: nothing code relies on.

- [ ] **Step 1: Write the check and see it fail**

Save as `/tmp/docs_check.py`:

```python
t = open("docs/architecture.md").read()
must = ["Dispatch (S3 3.1) is `RunDispatchStore`'s (`app.runDispatch`).",
        "`noticeRequested` to `app.runControl.flash`",
        "`runSettingsUpdated` carrying it merged per milestone id",
        "as shims through `dispatchStore`",
        "`RunDispatchStore`'s dispatch debounce"]
never = ["and closes the dispatch unless a start is in flight;",
         "the store also starts am runs",
         "the store's own `runSettings` merging it",
         "the fallback poll and the dispatch debounce"]
bad = [m for m in must if m not in t] + [n for n in never if n in t]
print("\n".join(bad) if bad else "docs ok")
raise SystemExit(1 if bad else 0)
```

Run: `python3 /tmp/docs_check.py`
Expected: exit 1, listing all five "must" sentences and all four "never" sentences.

- [ ] **Step 2: Apply the edits**

Save as `/tmp/docs_edit.py` and run `python3 /tmp/docs_edit.py`. It removes "and closes the dispatch unless a start is in flight" from `stopLive`'s list (84); appends the dispatch shim sentence to the shim paragraph (91); opens the dispatch paragraph with `RunDispatchStore`'s ownership and App's inputs and routes, says `runSettingsUpdated` carries the keyed prefix, and makes closing the panel the store's own `active` reaction (92); and names `RunDispatchStore`'s dispatch debounce among the timers (173).

```python
p = "docs/architecture.md"
t = open(p).read()

def swap(t, old, new):
    assert t.count(old) == 1, old[:80]
    return t.replace(old, new)

# stopLive's list (line 84).
t = swap(t, "clears `stale` and `watchWarning`, and closes the dispatch unless a start is in flight; `runs`, the selection",
            "clears `stale` and `watchWarning`; `runs`, the selection")

# The shim sentences (line 91).
t = swap(t, "`dismissAllToasts` and `notify` as read-only shims through `alertsStore` (the handle App sets; without one they are empty and do nothing) until the last story of the split removes them.",
            "`dismissAllToasts` and `notify` as read-only shims through `alertsStore` (the handle App sets; without one they are empty and do nothing) until the last story of the split removes them. "
            "`RunStore` likewise keeps the dispatch properties (`dispatchState` .. `dispatchExitCode`), `dispatchDefaultsRunner`, `dispatchPreviewRunner`, `dispatchDebounceTimer`, `dispatchStartRunners`, `openDispatch`, `closeDispatch`, `retargetToMilestone`, `setDispatchField`, `dispatchStart`, `checkDispatch` and a re-emitted `dispatchStarted` as shims through `dispatchStore` (the handle App sets; without one they are empty and do nothing) until the last story of the split removes them; `dispatchState` is writable (a write goes to the dispatch store, and the shim then follows it again).")

# The dispatch paragraph (line 92).
t = swap(t, "  Dispatch (S3 3.1): the store also starts am runs. ",
            "  Dispatch (S3 3.1) is `RunDispatchStore`'s (`app.runDispatch`). App hands it `backendDir`, `project`, `active`, `runs` and `runSettings`, and routes `refreshRequested` to the run store, `noticeRequested` to `app.runControl.flash` and `runSettingsUpdated` into `app.runs.runSettings`. ")
t = swap(t, "the store's own `runSettings` merging it per milestone id at once",
            "`runSettingsUpdated` carrying it merged per milestone id at once")
t = swap(t, "`closeDispatch()`, a project switch (even from `starting`) and closing the panel (except while `starting`) put the dispatch back to `idle`.",
            "`closeDispatch()` and a project switch (even from `starting`, the store's own `project` reaction) put the dispatch back to `idle`, and so does closing the panel (the store's own `active` reaction), except while `starting`.")

# The timers (line 173).
t = swap(t, "the liveness tick (only while a run is running), the fallback poll and the dispatch debounce (`dispatchDebounceTimer`,",
            "the liveness tick (only while a run is running) and the fallback poll, `RunDispatchStore`'s dispatch debounce (`dispatchDebounceTimer`,")

open(p, "w").write(t)
```

Expected: no output, exit 0.

- [ ] **Step 3: Run the check again and see it pass**

Run: `python3 /tmp/docs_check.py`
Expected: `docs ok`, exit 0.

Run: `grep -n 'RunDispatchStore' core/stores/RunStore.qml core/stores/RunDispatchStore.qml | head`
Expected: RunStore's header sentence and its shim comment; RunDispatchStore's header names `app.runDispatch`.

- [ ] **Step 4: Run the full gate once more**

Run: `timeout 900 bash tests/run.sh`
Expected: exit 0 (pytest includes the docs/contract tests).

- [ ] **Step 5: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): the dispatch is RunDispatchStore's, RunStore keeps shims"
```

---

## Self-review against the spec

- Members that move (spec table): Task 1 Step 4 (store), Task 2 Step 5 (removal). `stopLive` / `projectSwitched` lines and comments: Task 2 Step 5.
- Inputs and signals table, `runSettingsUpdated` instead of a write: Task 1 Step 4; App routes: Task 2 Step 6.
- Couplings 1-5: order pinned by D-N4; notice by D-N6 / A-D4; `active` by D-N2 / A-D5; `project` by D-N3; reads of the inputs by the moved tests on the wired harness.
- Contract comment: Task 1 Step 4 header. RunStore header: Task 2 Step 5.
- Shims table (writable `dispatchState`, empty values, six forwards, re-emitted signal): Task 2 Step 5; pinned by R-D1 … R-D4.
- App: `runDispatch` after `runAlerts`, `dispatchStore: app.runDispatch`, comment: Task 2 Step 6; A-D1 … A-D5.
- Moved tests (59, same names, order, section headers, numbered comments) and copied helpers: Task 1 Steps 1-2; deleted from `tst_run_store.qml` with `dispatchSettings()` and the three run-settings tests kept: Task 2 Step 2.
- Gate and `git diff --stat -- ui tests/ui` empty: Task 2 Step 9.
- Docs 84, 91, 92, 173: Task 3.
- Out of scope, untouched: `runSettings` I/O (4.2), `ui/` callers and shim deletion (last story), `dispatchRoot` / project step / relaunch (not added).
<!-- task-pipeline: validated -->
