# 4.1 RunDispatchStore: the dispatch state machine — design

Card: `e7c8225b` ("4.1 RunDispatchStore: the dispatch state machine"), a subtask of story
`d11a4680` "Extract RunDispatchStore". Its sibling 4.2 (`e6d2e50e`, "Dispatch run settings
through RunControlStore") comes after it. Parent design:
`docs/superpowers/specs/2026-10-05-split-runstore-design.md`, cited below as "P l.N". Line numbers
into `core/stores/RunStore.qml` (1557 lines), `core/stores/App.qml` (167 lines) and the test files
come from the files at the start of this card (commit `7676feb`). Appendix A's line numbers
(P l.168) come from an older 2038-line file. This spec cites Appendix A rows only by their own
line in the parent spec.

## Purpose

This card is a pure refactor. The S3/S7 dispatch state machine moves out of `RunStore` into a
new `core/stores/RunDispatchStore.qml`, composed by App as `app.runDispatch` (P l.57). The move
covers:

- the state, the form, the debounced preview, the default-branch lookup, `dispatchStart` with its
  per-Start runner, the S7 story target and `retargetToMilestone`, and `dispatchStarted(runId)`;
- the runners and the timer that go with them.

The calls into other concerns become signals that App routes (P l.79, A.3 P l.436-437, 443-446).
`RunStore` keeps stateless shims under the old names (P l.122-127), so `ui/` and `tests/ui/` do
not change.

Nothing a user can see or a helper can receive changes. The same argv launches at the same
moments under the same guards. The same values land, the same sentence flashes, and
`dispatchStarted` reaches Panel, and through it the Navigator, exactly as it does today.

## Scope: what the card names that does not exist

The card, and P l.57 and l.79, name members that the queued milestones would have added. None of
them is in the repository at `7676feb`. `grep -rE 'dispatchRoot|dispatchStep|dispatchOpenFromRuns|relaunch|board-tree'`
over `core/`, `ui/` and `tests/` finds nothing, and Appendix A's A.2 (P l.411-414) records the same
thing: "not in `RunStore.qml` at this commit; mapped whole when it lands". This card moves only
what exists, and it invents none of the following:

| named by the card or P l.79 | at this commit | this card |
|---|---|---|
| `dispatchRoot` | absent | not added |
| `// ---- dispatch: project and target steps` (`dispatchStep`, `dispatchOpenFromRuns`, `dispatchBack`, `dispatchProject*`, `dispatchTarget*`, two `board-tree.py` runners) | absent | not added |
| `// ---- relaunch` (`relaunchOpenFor`, `relaunch*`) | absent | not added |
| `projectRoots` input ("read by the project step") | the project step is absent, so nothing would read it | not added: an input nothing reads is new surface (P l.146-148) |
| `cardMap` input (`app.board.cardMap`) | the card map is an **argument** of `openDispatch(card, cardMap)` (RunStore.qml 1093) and is kept in `dispatchBook.cardMap` | not added: the argument stays exactly as it is |
| "a start asking for `[dispatchRoot]` only" / "`tst_app_runs.qml` pins started → re-snapshot of `dispatchRoot` only" | a start re-snapshots **every usable root** (`store.refresh()`, RunStore.qml 1352), pinned by `tst_run_store.qml::test_a_dispatch_start_refreshes_every_usable_root` (3586) and `tst_app_runs.qml::test_a_dispatch_start_through_app_snapshots_every_registered_root` (374) | `refreshRequested("all")`; the App pin stays "every registered root" (A.3 P l.443-444). Narrowing it to one root would change behaviour, which P l.146 forbids. |

When Dispatch from the Runs screen or Resume and recover land, they land in `RunDispatchStore`
(P l.132-142). That is their work, not this card's.

## Scope: what this card leaves to siblings

- **Run settings I/O (card 4.2).** `runSettings`, `runSettingsRunner`, `applyRunSettings`, the
  `runSettings = {}` reset and the `get-run-settings` reload in `projectSwitched` (RunStore.qml
  179, 1052-1055, 664-671, 1417-1421) all stay in `RunStore`, unchanged in body. The 3.2 spec
  (`3-2-runcontrolstore-run-e546c85f.md`, "Scope") left them there for 4.2 too.
  `runSettingsWanted(root)`, `runSettingsSaveRequested(root, patch)` and
  `RunControlStore.loadRunSettings` / `saveRunSettings` are 4.2's work.
- **The per-Start settings write.** This card moves it as it is: after an ok start, the
  `dispatchStartC` runner itself runs `viewer-state.py set-run-settings` (RunStore.qml 1355-1357).
  The card's "settings runners moved as they are" means this runner. 4.2 replaces it with
  `runSettingsSaveRequested`.
- **Moving `ui/` and `tests/ui/` callers to `app.runDispatch`, and deleting the shims.** That is
  the last story's work (P l.128-131).
- **Rewriting `docs/architecture.md` into one paragraph per store.** That is a later docs card.
  This card only edits the sentences it makes false (see "Docs").

## Inherited constraints

- Every member lands in exactly one store. Nothing is duplicated, and nothing is dropped unless
  no code or test reads it (P l.61-67). This includes the A.1 rows P l.235-249, 270-273, 361-380,
  386-387, 395, 401 and 404.
- No duplicated helpers. Replies are read with `Results.parseEnvelope`, and maps are handled with
  `Runs.copyMap` / `Runs.hasKey`, imported from `core/domain/` (P l.68-71). The new store imports
  only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain/*.js`
  (`tests/architecture/test_layers.py:133`).
- Inputs come from App, and each store gets only what it reads (P l.72-79). A store never imports
  or names a sibling (P l.46-50). The shim handle `RunStore.dispatchStore` is the one temporary
  exception, following `controlStore` / `alertsStore`.
- Cross-concern calls become App-routed signals (P l.80-91, A.3 P l.436-437, 443-446).
- Lifecycle stays per store. `stopLive`'s `closeDispatch()` becomes the dispatch store's own
  `active` reaction (A.3 P l.436). `projectSwitched`'s `resetDispatch()` becomes its own
  `project` reaction (A.3 P l.437). `dispatchDebounceTimer` keeps its behaviour (P l.92-97).
- Shims (P l.122-127):
  - A property shim is a binding through the handle, and it notifies like the original.
  - A function shim is a one-line forward that returns the target's result.
  - A signal shim is re-emitted.
  - Shims hold no state and no logic.
  - The only comment above them is `// Moved to RunDispatchStore; removed by the last story`.
- Tests move with their members. Only construction and the wiring of inputs change, never an
  expectation. A test that crosses two concerns is pinned at App level (P l.98-104, l.152-164).
- `tests/architecture` stays green (P l.105-106).
- No behaviour change, no renamed public member, no new helper argv, no change to which process
  starts when, and no UI change (P l.146-150).
- From the card:
  - `bash tests/run.sh` is green;
  - TDD: tests first;
  - docstrings and comments state the contract only, with no narrative;
  - `tests/ui` passes untouched.

## The members that move

Every row leaves `RunStore.qml` and lands in `RunDispatchStore.qml`. The body is unchanged except
for these edits:

- `store.` becomes `dispatch.`, the new store's root id.
- The calls listed under "Couplings that become signals" change.

| member | RunStore.qml today | Appendix A row |
|---|---|---|
| the dispatch comment block | 181-186 | into the store's contract comment |
| `dispatchState` … `dispatchExitCode` (14 properties) | 187-200 | P l.235-248 |
| `signal dispatchStarted(var runId)` and its comment | 201-203 | P l.249 |
| aliases `dispatchDefaultsRunner`, `dispatchPreviewRunner`, `dispatchDebounceTimer`, `dispatchStartRunners` (→ `dispatchBook.runners`) | 229-232 | P l.270-273 |
| `// ---- dispatch (S3 3.1)` section: `clearDispatchError`, `resetDispatch`, `openDispatch`, `closeDispatch`, `blockedSuggest`, `retargetToMilestone`, `withField`, `dispatchTargetArgs`, `dispatchCommands`, `dispatchOptionArgs`, `dispatchDefaultsReplied`, `checkDispatch`, `dispatchPreviewReplied`, `setDispatchField`, `mergedPrefixes`, `dispatchStart`, `isHereStart`, `dispatchStartReplied`, `dispatchSaveReplied`, `dropStartRunner` | 1057-1392 | P l.361-380 |
| `HelperRunner dispatchDefaultsRunner` (`runs/dispatch-preview.py`, `guard: dispatch.project`) | 1423-1429 | P l.386 |
| `HelperRunner dispatchPreviewRunner` (same script, same guard) | 1431-1437 | P l.387 |
| `Timer dispatchDebounceTimer` (400 ms, `objectName` kept) | 1478-1485 | P l.395 |
| `QtObject dispatchBook` and its comment | 1504-1518 | P l.401 |
| `Component dispatchStartC` (`runs/start-run.py`, `guard: ""`, `madeFor`, `savedJson`, `saving`) and its comment | 1520-1539 | P l.404 |

These stay in `RunStore`, apart from the edits listed:

- `runSettings` and its whole I/O (card 4.2);
- `stopLive`, minus its last two lines (`// A start in flight refuses and lands normally.` /
  `store.closeDispatch()`, 387-388). Its comment drops "and no dispatch outlives the opening (a
  start in flight runs to its end)".
- `projectSwitched`, minus its dispatch lines (665-667). Its comment's "Reset: the run settings …
  and the dispatch" becomes "Reset: the run settings (loaded for the new project on
  runSettingsRunner)".

## Behaviour: `RunDispatchStore`

### Inputs and signals

The file header follows `RunControlStore.qml`: the same three imports and the two domain imports,
then `Scope { id: dispatch`.

| member | kind | App binds / routes | contract |
|---|---|---|---|
| `backendDir` | `property string`, `""` | `app.backendDir` | `<plugin>/core/backend/` |
| `project` | `property string`, `""` | `app.runs.project` | the open project's root; `""` when none is open |
| `active` | `property bool`, `false` | `app.panelOpen` | the panel is open |
| `runs` | `property var`, `[]` | `app.runs.runs` | the run store's merged run list, read by `Runs.dispatchDefaults` |
| `runSettings` | `property var`, `({})` | `app.runs.runSettings` | the open project's run settings; the store never writes it |
| `refreshRequested(var roots)` | signal | `"all"` → `app.runs.refresh()`, else `app.runs.requestSnapshot(roots)` (as `runControl`, App.qml 136-139) | a re-snapshot is wanted; this store only ever asks for `"all"` |
| `noticeRequested(string text)` | signal | `app.runControl.flash(text)` | a sentence for the footer flash |
| `runSettingsUpdated(var settings)` | signal | `app.runs.runSettings = settings` | after a start of this dispatch: the open project's run settings as that start saves them |
| `dispatchStarted(var runId)` | signal | none (the RunStore shim re-emits it; see below) | unchanged |

`runSettingsUpdated` is this card's stand-in for the old direct write
`store.runSettings = settings` (RunStore.qml 1350, A.3 P l.445). The store must not assign to its
own `runSettings`: that would break App's binding, and a later project switch would then leave
the old project's settings in the dispatch form. Card 4.2 replaces this signal with
`runSettingsSaveRequested`.

### Unchanged from RunStore

Every behaviour that the moved tests pin holds as it does today, read against this store's own
inputs:

- the state machine `idle → previewing → ready / refused → starting → started / failed`;
- every argv, its element count and its `launchGuard`;
- the 400 ms debounce, with one preview per burst;
- the `--defaults` lookup, once per opening, which a user-set base beats;
- the target label, the S7 story target, the `StoryBlockedError` suggestion and
  `retargetToMilestone`, which goes once to the milestone recorded at the opening;
- the keyed `prefixByMilestone` merge and the 20-entry prefix history;
- one `HelperRunner` per Start, `guard ""`, which no preview, project switch or other Start stops;
- `isHereStart` (`madeFor === dispatch.project` and it is the runner that put the store into
  `starting`);
- the settings write by the same runner after any ok start, wherever that start was made, with
  the runner going when the write replies or at once after a failed start.

### Couplings that become signals or own reactions

1. **A start's ok reply, when it is this dispatch's** (`dispatchStartReplied`, RunStore.qml
   1332-1361). The order is kept exactly:
   1. set `dispatchRunId` and `dispatchMessage`;
   2. compute `settings` as today (`Runs.copyMap(dispatch.runSettings)` plus the saved keys, with
      `prefixByMilestone` merged through `mergedPrefixes`);
   3. emit `runSettingsUpdated(settings)` (was `store.runSettings = settings`);
   4. set `dispatchState = "started"`;
   5. emit `refreshRequested("all")` (was `store.refresh()`);
   6. emit `dispatchStarted(dispatchRunId !== "" ? dispatchRunId : null)`.

   Then the runner starts its `set-run-settings` write, as today. A reply that is not this
   dispatch's emits none of the three signals, as today it neither writes nor refreshes nor
   emits.
2. **The settings write fails while the dispatch is still that start's** (`dispatchSaveReplied`,
   1380-1384). The store emits `noticeRequested("Dispatch settings could not be saved")`, where
   today it calls `store.flash(...)`. It emits nothing otherwise. The runner goes either way.
3. **Closing the panel.** `onActiveChanged: if (!dispatch.active) dispatch.closeDispatch()`.
   `closeDispatch` still refuses while `starting`, so a start in flight runs on and lands
   normally. `active` turning true does nothing.
4. **A project change.** `onProjectChanged: dispatch.resetDispatch()`. This holds even from
   `starting`: the start still runs, and its reply is no longer this dispatch's. `resetDispatch`
   reads no run settings, so it does not depend on the order relative to `RunStore`'s own
   `runSettings = {}`.
5. **Reads of `store.project`, `store.runs`, `store.runSettings` and `store.backendDir`** become
   reads of this store's inputs of the same names. `dispatchStartC.createObject(dispatch, …)`
   parents each start runner to this store.

### Contract comment

The header comment states only the contract. It covers:

- what the store does (the state machine, `dispatch-preview.py`, `start-run.py` on one runner per
  Start, and that runner's `set-run-settings` write);
- its inputs, and that it never reaches for another store;
- its four out-signals;
- that a project change resets it and closing the panel closes it unless a start is in flight;
- that App composes it as `app.runDispatch`.

The moved members keep their comments, with "the store" read as this store.

## Behaviour: `RunStore`

### Removed

All the rows in "The members that move", plus the two coupling lines in `stopLive` and
`projectSwitched`. `RunStore` launches no `dispatch-preview.py` and no `start-run.py` of its own.
It still launches `get-run-settings` on `runSettingsRunner`.

### Shims

The shims go in a new block after the alerts shims (RunStore.qml 155-166), under
`// Moved to RunDispatchStore; removed by the last story`. They start with
`property var dispatchStore: null`. Every shim checks `store.dispatchStore` first, so a store with
no handle never throws (`tests/run.sh` fails a file whose output contains `TypeError`).

| name | shim | without a handle |
|---|---|---|
| `dispatchState` | **writable**, following the `cancelText` pattern (RunStore.qml 132-139): a plain `property string`, a `Binding` from the handle, and an `on…Changed` that writes a differing value through to the handle, or resets it to `"idle"` without one | `"idle"` |
| `dispatchTarget`, `dispatchForm`, `dispatchPreview`, `dispatchSuggest`, `dispatchExitCode` | `readonly property var` | `null` |
| `dispatchTargetLabel`, `dispatchError`, `dispatchErrorType`, `dispatchRunId`, `dispatchMessage`, `dispatchLog`, `dispatchLogTail` | `readonly property string` | `""` |
| `dispatchErrors` | `readonly property var` | `[]` |
| `dispatchDefaultsRunner`, `dispatchPreviewRunner`, `dispatchDebounceTimer` | `readonly property var` | `null` |
| `dispatchStartRunners` | `readonly property var` | `[]` |
| `openDispatch(card, cardMap)`, `closeDispatch()`, `retargetToMilestone()`, `setDispatchField(name, value)`, `dispatchStart()`, `checkDispatch()` | a one-line forward returning the target's result | returns `undefined`, does nothing |
| `signal dispatchStarted(var runId)` | stays declared on `RunStore`; a `Connections { target: store.dispatchStore; function onDispatchStarted(runId) { store.dispatchStarted(runId) } }` re-emits it | never emitted |

**Why `dispatchState` is writable.** `tests/ui` writes it on a real `RunStore`, and those files
must pass untouched:

- `tests/ui/tst_dispatch_flow.qml:203` writes `"previewing"`, then the dialog's suggestion must
  be refused by the store;
- `tests/ui/tst_shortcuts.qml:778` and `:836` write `"ready"` (an open dispatch is a modal);
- `tests/ui/tst_shortcuts.qml:861` writes `"starting"`, then Escape's `closeDispatch()` must
  refuse.

Each of these needs the write to reach the dispatch store. No other dispatch member is written
outside `RunStore.qml` and the moved tests: the planner confirms this with
`grep -rnE 'runs\.dispatch[A-Za-z]* *=[^=]' ui tests`.

**Why only these six functions get a forward.** They are the only dispatch functions that `ui/`,
`tests/ui/` or `tst_app_runs.qml` call on `app.runs` (`checkDispatch` only at
`tests/ui/tst_dispatch_flow.qml:304`). The other fourteen are internal, so they get no shim, as
3.2 did for `applyGlobalSettings`. Before deleting, the planner greps `ui/`, `tests/ui/`,
`tst_app_runs.qml` and the tests that stay in `tst_run_store.qml` for each name. Any hit gets a
forward shim instead.

**`dispatchStarted` is re-emitted once.** It is re-emitted by `RunStore` alone; App adds no
second route. Panel (`ui/Panel.qml:102-105`) listens on `app.runs` and calls `closeDispatch()`
then `navi.openStartedRun(runId)`. A second emission would open the run twice.

`runSettings`, `runSettingsRunner` and `applyRunSettings` are unchanged and are not shims.

### Header comment

The header (RunStore.qml 7-37) changes in two places:

- The two dispatch sentences ("Dispatch (openDispatch .. dispatchStart) previews … one
  HelperRunner per Start.", 31-33) are replaced by one contract sentence. For example: "The
  dispatch is RunDispatchStore's; its members here are shims through `dispatchStore`."
- "the open project, decides only the run settings and the dispatch" (13-14) becomes "… decides
  only the run settings".

## Behaviour: `App`

- A new `readonly property RunDispatchStore runDispatch: RunDispatchStore { … }`, placed after
  `runAlerts`. It binds and routes exactly as the inputs table above says. Its comment, in the
  style of App.qml 131-134 and 141-144: "The dispatch never imports the run store: App hands it
  the backend directory, the open project's root, the panel-open flag, the run list and the run
  settings, routes its refreshRequested to the run store, its noticeRequested to run control's
  flash and its runSettingsUpdated into the run store's runSettings."
- `runs` gains `dispatchStore: app.runDispatch`, and its comment's handle list (App.qml 106-107)
  adds `dispatchStore`.

## Equivalence argument (for the reviewer)

- **Same launches.** One opening still launches exactly one `--defaults` lookup, and one check
  launches at most one preview. Each Start is still one `start-run.py`, followed on an ok reply by
  one `set-run-settings` on the same runner. The guards (`dispatch.project`, and `""` for starts)
  follow the same root, because `dispatch.project` is bound to `app.runs.project`.
- **A project switch.** Today one handler does `runSettings = {}`, then `resetDispatch()`, then
  sets the runner guard and loads. Now `RunStore` does the reset and the load, and the dispatch
  store resets itself on its own `project` change. Both are synchronous in the same change.
  `resetDispatch` reads no run settings, and the load reads nothing of the dispatch, so no
  observable value depends on which runs first.
- **A start's ok reply.** The `runSettingsUpdated` route is a synchronous signal handler, so App
  writes `app.runs.runSettings` and the dispatch store's bound `runSettings` follows before
  `dispatchState` turns `started`, as today. `refreshRequested("all")` reaches `app.runs.refresh()`,
  which is the call made today.
- **The flash.** It lands on the same `flashText` / `flashTimer`. Today `store.flash` already
  forwards to `RunControlStore` through 3.1's shim.
- **Closing the panel.** Both stores bind `active` to `app.panelOpen`. The dispatch is closed by
  its own reaction rather than by `stopLive`. Nothing else in `stopLive` reads the dispatch.

## Tests

TDD: each new or changed test is written first and fails before its code exists. Everything runs
through `bash tests/run.sh` (pytest, then qmltestrunner offscreen with `tests/stubs`).
`bash tests/run.sh tst_run_dispatch_store` runs one file (the filter is a substring of the path).
The tiers:

- **store unit, dispatch:** `tests/core/stores/tst_run_dispatch_store.qml`, new. It pins the
  dispatch's behaviour on the store that owns it. It has two harnesses:
  - a bare builder, `makeDispatch()`, which builds a `RunDispatchStore` with `backendDir`
    `"/plugin/core/backend/"` and nothing bound;
  - a "wired the way App wires it" builder, described below.
- **RunStore unit:** `tests/core/stores/tst_run_store.qml`. It pins the shims, the removal, and
  the run-settings tests that stay.
- **App wiring:** `tests/core/stores/tst_app_runs.qml`. It pins the new composition and every
  route.
- **UI and architecture:** `tests/ui/**` (untouched) and `pytest tests` (architecture, contract,
  install).

### Moved tests (store unit tier: whole, every expectation kept)

All 59 test functions from `test_dispatch_starts_idle` (tst_run_store.qml 2908) through
`test_a_late_blocked_start_reply_changes_nothing` (4186-4210) leave `tst_run_store.qml`. They land
in `tst_run_dispatch_store.qml` under the same names, in the same order, under the same section
headers (`// ---- dispatch (S3 3.1)` and `// ---- dispatch: story target, retarget and keyed
prefix (2.1)`), keeping their numbered comments.

The helpers and properties defined in 2831-4210 move with them:

- `previewCmd`, `startCmd`, `dispatchCards`, `dispatchStore`, `checkDispatchIdle`, `defaultsOk`,
  `previewOk`, `dispatchDryRun`, `previewingStore`, `previewArgs`, `startOk`, `readyStore`,
  `savedJson`;
- `keyedSettings`, `storyDryRun`, `storyPreviewingStore`, `storyPreviewArgs`, `blockedMessage`,
  `dispatchFields`, `checkRetargetRefused`, `storyReadyStore`, `startBlocked`.

These three tests in that range **stay** in `tst_run_store.qml`, because they pin `runSettings`,
which stays:

- `test_run_settings_load_per_project_and_never_set_the_switch` (2800);
- `test_run_settings_kept_even_after_notify_touched` (2843);
- `test_run_settings_follow_the_project` (2858).

`dispatchSettings()` (2837) is used on both sides, so it is copied into the new file and also
kept. The new file also copies the shared helpers its tests call:

- from tst_run_store.qml: `reply`, `argv`, `rootEntry`, `registry`, `allReply`, `okEntry`,
  `okReply`, `entry`, and the `rootA` / `rootB` / `snapCmd` / `viewerCmd` properties;
- `spyC`.

The planner lists the exact set by grepping the moved bodies.

**The wired harness.** The construction helpers `make()`, `makeWithProject(root)`,
`makeWithRoots(roots)` and `activeStore(root)` keep their names and their RunStore-side steps.
Each one builds:

1. a `RunStore`;
2. a `RunControlStore` wired as `tst_run_store.qml`'s `wireControl` does (54-70), so the flash
   lands;
3. a `RunDispatchStore`, wired the way App wires `app.runDispatch`:
   - `backendDir` copied;
   - `project`, `active`, `runs` and `runSettings` bound to the RunStore's own;
   - `refreshRequested` → `refresh()` for `"all"`, else `requestSnapshot(roots)`;
   - `noticeRequested` → the control store's `flash`;
   - `runSettingsUpdated` → `runStore.runSettings = settings`.

Each helper **returns the dispatch store**. It does not set `runStore.dispatchStore`, so the moved
tests prove the store and not the shims. `runsOf(d)` and `controlOf(d)` return the paired stores.

**The only edits inside moved bodies.** Every read, write or call of a member that stays outside
the dispatch store is redirected to the store that owns it. The expectations are untouched.

| in the moved bodies | becomes |
|---|---|
| `X.project = …` (7) | `runsOf(X).project = …` |
| `X.active = …` (5) | `runsOf(X).active = …` |
| `X.runs = […]` (3791) | `runsOf(X).runs = […]` |
| `X.runSettingsRunner` (10) | `runsOf(X).runSettingsRunner` |
| `X.snapshotRunner` (12) | `runsOf(X).snapshotRunner` |
| `X.flashText` (3) | `controlOf(X).flashText` |
| `X.notifyOnEscalation`, `X.settingsSaveRunner` (3615-3616, `test_settings_write_failure_flashes`) | `controlOf(X)…` |

`X` is whatever the local is called (`store`, `pending`, `cleared`, `back`, `keyed`, `fresh`,
`ready`, …). Reads of `X.runSettings` stay on the dispatch store, whose bound input carries the
same value. A `SignalSpy` on `dispatchStarted` targets the dispatch store.

The file's header comment says what it covers: the dispatch state machine, built alone and wired
to a RunStore and a RunControlStore the way App wires `app.runDispatch`, with stubbed Process
objects.

### New tests

**Store unit (`tst_run_dispatch_store.qml`, bare store, section `// ---- the store alone`):**

- **D-N1 `test_a_bare_dispatch_store_is_idle_with_empty_inputs`.** `makeDispatch()` passes
  `checkDispatchIdle`. Also:
  - `project` is `""`, `active` is `false`, `runs` has length 0 and `runSettings` has no keys;
  - `dispatchStartRunners` has length 0, `dispatchDebounceTimer.running` is `false`, and neither
    runner has a `current`;
  - `openDispatch(cards.m1, cards)` returns `false`.

  Tier: store unit, because it pins the defaults on the owner with nothing bound.
- **D-N2 `test_its_own_active_closes_it_but_not_a_start`.**
  1. On a bare store, set `project = rootA` and `runSettings` to the parsed `dispatchSettings()`.
  2. Set `active = true`, open m1 and reply `defaultsOk("main")`.
  3. Set `active = false`. The store is idle (`checkDispatchIdle`).
  4. Set `active = true` again, open m1, reach `ready` (defaults reply, then preview reply), and
     call `dispatchStart()`.
  5. Set `active = false`. `dispatchState` stays `"starting"`, and the start process is still
     running.

  Tier: store unit, because it proves the close is the store's own reaction (A.3 P l.436), with no
  RunStore.
- **D-N3 `test_its_own_project_change_resets_it_and_keeps_a_start_running`.**
  1. On a bare store, from `ready`, call `dispatchStart()`.
  2. Set `project = rootB`. The store is idle, and the start process is still running.
  3. A late ok reply to that start emits no `dispatchStarted`, no `refreshRequested` and no
     `runSettingsUpdated` (`SignalSpy` counts 0).
  4. The runner then shows a `set-run-settings` argv for `rootA`.

  Tier: store unit (A.3 P l.437).
- **D-N4 `test_a_start_reply_emits_settings_then_refresh_then_started`.**
  1. On a bare store from `ready`, connect one recorder to all three signals. The recorder pushes
     `"settings"`, `"refresh:" + JSON.stringify(roots)` and `"started:" + runId`.
  2. Reply `startOk("r-1", "")`.
  3. The record is exactly `settings`, `refresh:"all"`, `started:r-1`.
  4. The `runSettingsUpdated` payload has these values:
     - `prefixHistory` `["old"]`;
     - `parallelism` 4;
     - `confirmDispatch` `true` (a key the start does not write is kept);
     - `prefixByMilestone.m1` `"old"`.
  5. `dispatchState` is `"started"` once `started` is recorded.

  Tier: store unit, because it pins the order of the coupling signals (see "Couplings").
- **D-N5 `test_the_store_never_writes_its_own_run_settings`.** On a bare store whose
  `runSettings` is set to object `S`, with nothing connected to `runSettingsUpdated`, an ok start
  leaves `runSettings === S`. Tier: store unit. It guards the App binding (Review Focus 3).
- **D-N6 `test_a_failed_settings_write_emits_one_notice_only_while_here`.**
  1. On a bare store from `started`, reply `garbage` to the write. `noticeRequested` fires once,
     with `"Dispatch settings could not be saved"`.
  2. A second bare store starts, then its `project` changes, then the start and the write both
     fail. That gives 0 notices.

  Tier: store unit (A.3 P l.446).

**RunStore unit (`tst_run_store.qml`, new section `// ---- the dispatch shims (split-runstore
4.1)`):**

- **R-D1 `test_without_a_dispatch_store_the_shims_are_empty_and_inert`.** A `RunStore` built bare
  (no handle):
  - every property shim reads its "without a handle" value from the table;
  - each of the six functions returns `undefined`;
  - writing `dispatchState = "ready"` leaves it `"idle"`;
  - `active = true` then `active = false`, and `project = rootA` then `project = rootB`, produce
    no `TypeError`.

  Tier: RunStore unit, because the shims live there.
- **R-D2 `test_the_dispatch_shims_follow_the_dispatch_store_and_notify`.** Use a `RunStore` with a
  `RunDispatchStore` handle (`store.dispatchStore = d`, the dispatch wired as above).
  1. `store.dispatchDefaultsRunner === d.dispatchDefaultsRunner`, and likewise for the preview
     runner, the timer and `dispatchStartRunners`.
  2. A `SignalSpy` on `store`'s `dispatchStateChanged` counts 1 after `store.openDispatch(cards.m1, cards)` (with the project open),
     and `store.dispatchState` is `"previewing"`.
  3. `store.setDispatchField("prefix", "x")` returns `true`, and `d.dispatchForm.prefix` is
     `"x"`.
  4. `store.closeDispatch()` returns `true`, and `d.dispatchState` is `"idle"`.

  Tier: RunStore unit.
- **R-D3 `test_writing_the_dispatch_state_shim_reaches_the_dispatch_store`.** Writing
  `store.dispatchState = "starting"` sets `d.dispatchState` to `"starting"`. Then
  `store.closeDispatch()` returns `false`. Then `d.resetDispatch()` brings `store.dispatchState`
  back to `"idle"`, which shows the binding is intact after a write. Tier: RunStore unit, pinning
  what `tests/ui/tst_shortcuts.qml:861` relies on.
- **R-D4 `test_dispatch_started_is_re_emitted_once`.** A `SignalSpy` on `store.dispatchStarted`.
  Then `d.dispatchStarted("r-9")`. The count is 1, with argument `"r-9"`. Tier: RunStore unit.
- **R-D5 `test_closing_and_switching_the_run_store_touch_no_dispatch`.** A `RunStore` wired to
  its own dispatch store, with the dispatch **not** bound to the RunStore's `active` / `project`
  (bare `d`, handle set). Open on the RunStore, then:
  - `store.active = true; store.active = false` leaves `d.dispatchState` `"previewing"`;
  - `store.project = rootB` leaves it too.

  Tier: RunStore unit, because it pins that `stopLive` and `projectSwitched` no longer reach the
  dispatch (the leftover-call failure mode).

**App wiring (`tst_app_runs.qml`):**

- **Unchanged, still passing through the shims:**
  - `test_a_dispatch_start_through_app_snapshots_every_registered_root` (374);
  - `test_a_dispatch_settings_save_failure_through_app_flashes` (391);
  - `test_a_project_switch_through_app_resets_the_dispatch_and_reloads_run_settings` (403);
  - `test_closing_the_panel_through_app_empties_toasts_disarms_and_closes_the_dispatch` (440).
- **A-D1 `test_app_composes_run_dispatch_wired_to_the_run_store`.** With `make()`:
  - `app.runDispatch` exists;
  - `app.runs.dispatchStore === app.runDispatch`;
  - `app.runDispatch.backendDir` is `"/plugin/core/backend/"`;
  - `project` is `"/home/u/my proj"`, and follows `app.projects.chooseProject(pB)`;
  - `active` follows `app.panelOpen`;
  - `runs === app.runs.runs`;
  - `runSettings === app.runs.runSettings` after a `get-run-settings` reply.

  Tier: App wiring.
- **A-D2 `test_a_start_through_app_writes_the_run_settings_back_and_keeps_the_binding`.**
  1. `readyApp()`, then `app.runDispatch.dispatchStart()`, then an ok reply.
  2. `app.runs.runSettings.prefixByMilestone.m1` is `"old"`, and
     `app.runDispatch.runSettings === app.runs.runSettings`.
  3. `app.projects.chooseProject(pB)`. Both now have 0 keys.
  4. A `get-run-settings` reply for B with `{parallelism: 9}` reaches `app.runDispatch.runSettings`.

  Tier: App wiring, because it is Dispatch → RunStore (A.3 P l.445).
- **A-D3 `test_a_start_through_app_announces_started_once_on_each_store`.** Spies on
  `app.runDispatch` and `app.runs` `dispatchStarted`. After an ok start, each counts 1, with
  `"r-1"`. Tier: App wiring. It guards against a double route that would make Panel open the run
  twice.
- **A-D4 `test_a_dispatch_notice_through_app_is_run_controls_flash`.** After a failed settings
  write, `app.runControl.flashText` is `"Dispatch settings could not be saved"` and
  `app.runControl.flashTimer.running` is `true`. Tier: App wiring (A.3 P l.446).
- **A-D5 `test_closing_the_panel_through_app_keeps_a_start_in_flight`.**
  1. `readyApp()` with `app.panelOpen = true`, then `dispatchStart()`.
  2. `app.panelOpen = false`. `app.runDispatch.dispatchState` is `"starting"`.
  3. An ok reply gives `"started"`.

  Tier: App wiring (A.3 P l.436).

The file's header comment adds `app.runDispatch` to what it covers.

### Test wiring changes in `tst_run_store.qml`

- Delete the 59 moved tests and the helpers that only they use.
- Keep `dispatchSettings()` and the three run-settings tests.
- The header comment (1-9) adds: "The dispatch is tested in tst_run_dispatch_store.qml."
- If a remaining test reads a dispatch member, it goes through the shim only when it is wired with
  a handle. The planner greps the remaining file for `dispatch` after the deletion. Any hit is
  either moved (if it is a dispatch test) or given the handle through a `wireDispatch(store)`
  modelled on `wireControl`.

### Gate

- `bash tests/run.sh` is green: pytest, including `tests/architecture`, then every qmltestrunner
  file, with no `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign` or `is not a
  function` in the output.
- `git diff --stat -- ui tests/ui` is empty.

## Docs

Only the sentences this card makes false are edited.

- **`docs/architecture.md:84`.** In `stopLive`'s list, "and closes the dispatch unless a start is
  in flight" is removed.
- **`docs/architecture.md:92`.** The paragraph opens "Dispatch (S3 3.1) is `RunDispatchStore`'s
  (`app.runDispatch`)" in place of "the store also starts am runs". It adds one sentence: App
  hands it `backendDir`, `project`, `active`, `runs` and `runSettings`, and routes
  `refreshRequested` to the run store, `noticeRequested` to `app.runControl.flash` and
  `runSettingsUpdated` into `app.runs.runSettings`. In the closing sentence, "closing the panel
  (except while `starting`)" becomes its own `active` reaction. "the store's own `runSettings`
  merging it" becomes "`runSettingsUpdated` carrying it".
- **`docs/architecture.md:91`** (the shim sentence). It adds that `RunStore` keeps the dispatch
  properties, `dispatchDefaultsRunner`, `dispatchPreviewRunner`, `dispatchDebounceTimer`,
  `dispatchStartRunners`, `openDispatch`, `closeDispatch`, `retargetToMilestone`,
  `setDispatchField`, `dispatchStart`, `checkDispatch` and a re-emitted `dispatchStarted` as shims
  through `dispatchStore`, and that `dispatchState` is writable.
- **`docs/architecture.md:173`.** "`RunStore`'s watch, … and the dispatch debounce" becomes
  "`RunStore`'s watch, …, `RunDispatchStore`'s dispatch debounce".
- **The RunStore header comment.** See "Header comment" above.
- **The RunDispatchStore header comment.** See "Contract comment" above.

## Review Focus (for the planner)

These are the failure modes the moved tests do not obviously exercise. Each line names the
condition and the expected behaviour. The planner adds each test to the task that owns the code.

1. **A ui test writes `app.runs.dispatchState`** (`tst_shortcuts.qml:778, 836, 861`,
   `tst_dispatch_flow.qml:203`). Expected: the write reaches the dispatch store. A later
   `closeDispatch()` sees `"starting"` and refuses, and the shim keeps following the store
   afterwards. A read-only shim would throw `Unable to assign`. Pinned by R-D3 and the untouched
   ui suites.
2. **`dispatchStarted` delivered twice or not at all** (App and RunStore both forwarding, or
   neither). Expected: exactly once on `app.runs`, so Panel closes the dialog once and opens the
   run once. Pinned by A-D3 and R-D4.
3. **The dispatch store writes its own `runSettings`.** That breaks App's binding, so a later
   project switch leaves the old project's settings in the next form. Expected: the write goes
   through `runSettingsUpdated`, and the binding survives. Pinned by D-N5 and A-D2.
4. **A RunStore with no dispatch handle opens, closes or switches projects** (every
   `tst_run_store.qml` / `tst_run_alerts_store.qml` builder without a handle). Expected: no
   `TypeError`, and the shims read their empty values. Pinned by R-D1 and R-D5.
5. **The panel closes while a start is in flight, through App.** Expected: the start stays
   `starting` and lands normally, because the store's own `active` reaction goes through
   `closeDispatch`, which refuses, not through `resetDispatch`. Pinned by D-N2 and A-D5.

## Hand-off to the planner

Suggested tasks, each with its own test cycle:

1. **`RunDispatchStore` exists and owns the dispatch.**
   - Files: create `core/stores/RunDispatchStore.qml` and
     `tests/core/stores/tst_run_dispatch_store.qml`.
   - Add the members in "The members that move", the inputs and signals, and `onActiveChanged` /
     `onProjectChanged`. `RunStore` keeps its own copy for now. Nothing binds to the new store
     yet, so this is safe.
   - Tests first: D-N1 … D-N6, then the 59 moved tests copied in with the wired harness and the
     redirects. Do not delete them from `tst_run_store.qml` yet.
2. **`RunStore` shims, App composition and test moves, in one commit.**
   - Files: `core/stores/RunStore.qml`, `core/stores/App.qml`,
     `tests/core/stores/tst_run_store.qml` (delete the moved tests, R-D1 … R-D5), and
     `tests/core/stores/tst_app_runs.qml` (A-D1 … A-D5).
   - Remove the RunStore members, add the shims, compose `app.runDispatch`.
   - Grep for the no-shim functions before deleting them.
   - Run the full gate, and confirm that `ui/` and `tests/ui/` are untouched.
3. **Docs.** The `docs/architecture.md` edits above and both header comments. Contract only, no
   narrative.

The member interfaces later tasks rely on, exactly:

- `RunDispatchStore` inputs: `backendDir: string`, `project: string`, `active: bool`,
  `runs: var` (list), `runSettings: var` (object).
- `RunDispatchStore` signals: `dispatchStarted(var runId)`, `refreshRequested(var roots)` (always
  `"all"` here), `noticeRequested(string text)`, `runSettingsUpdated(var settings)`.
- `RunDispatchStore` keeps every public name in the table under "The members that move", with
  today's signatures: `openDispatch(card, cardMap) -> bool`, `closeDispatch() -> bool`,
  `retargetToMilestone() -> bool`, `setDispatchField(name, value) -> bool`,
  `dispatchStart() -> bool`, `checkDispatch()`, `resetDispatch()`, and the readonly aliases
  `dispatchDefaultsRunner`, `dispatchPreviewRunner`, `dispatchDebounceTimer` and
  `dispatchStartRunners`.
- `RunStore.dispatchStore: var` (the handle, `null` by default).
- `App.runDispatch: RunDispatchStore`.
