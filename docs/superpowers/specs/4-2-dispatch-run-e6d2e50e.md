# 4.2 Dispatch run settings through RunControlStore — design

Card: `e6d2e50e` ("4.2 Dispatch run settings through RunControlStore"), a subtask of story
`d11a4680` "Extract RunDispatchStore", after its sibling 4.1 (`e7c8225b`, landed: `f010b95`,
`a6505ac`). Parent design: `docs/superpowers/specs/2026-10-05-split-runstore-design.md`, cited as
"P l.N". 4.1's spec, `docs/superpowers/specs/4-1-rundispatchstore-e7c8225b.md`, is cited as
"S41". Line numbers into `core/stores/RunDispatchStore.qml` (465 lines), `RunStore.qml` (1166),
`RunControlStore.qml` (425), `App.qml` (187) and the test files are from this card's start
(`d7e0fc9`).

## Purpose

This card is a pure refactor. The run settings I/O moves out of the dispatch and the run store
into `RunControlStore`, which owns every run or global settings read and write through
`viewer-state.py` (P l.55). After this card:

- `RunDispatchStore` launches no `viewer-state.py`. It asks for its project's settings with
  `runSettingsWanted(root)`, asks for a start's values to be saved with
  `runSettingsSaveRequested(root, patch)`, and reads `runSettings` as an input (P l.79).
- App routes those two signals to `RunControlStore.loadRunSettings(root)` and
  `saveRunSettings(root, patch)`.
- `RunControlStore` holds `runSettings` as `{root: settings}`, a map that is replaced and never
  changed in place. Each request runs on a `HelperRunner` of its own, the way `controlRunners`
  does.
- `RunStore` launches no `get-run-settings`. It keeps `runSettings` and `runSettingsRunner` as
  shims, so `ui/` and `tests/ui/` do not change.

A user sees nothing different, and every helper gets the same argv. The same `get-run-settings`
read launches on the same project change, and every ok start launches the same
`set-run-settings` write. A dispatch form opens from the same values, and the same sentence
flashes when a save fails. The only differences are timing and process-lifetime ones, listed
under "Equivalence".

## Scope

### What the card names that does not exist

- **`dispatchRoot`.** No QML file has it (`grep -rn dispatchRoot core ui tests` finds nothing).
  Appendix A, P l.411, records it as "not in `RunStore.qml` at this commit", and S41 "Scope" did
  not add it. Where the card says "root is dispatchRoot, as the moved code uses", this card uses
  the roots the code actually uses:
  - for `runSettingsSaveRequested`, the start runner's `madeFor`, which is the project the start
    was made in (`RunDispatchStore.qml` 320, 369);
  - for `runSettingsWanted`, the store's `project` input.

  When Dispatch from the Runs screen lands, it changes these roots. That is its work.
- **`resumeSaveRunner` and the Resume dialog** (P l.55). Neither is in this tree. This card adds
  neither.

### Left to other cards

- The global settings (`get/set-global-settings`, the notify switch). They are already
  `RunControlStore`'s (3.x) and are unchanged.
- The milestone resume's own `get-run-settings` read inside `control()` (`RunControlStore.qml`
  82-87). It stays on its control runner, and this card does not change it. The only requirement
  here is that no run settings request stops it.
- Moving `ui/` and `tests/ui/` callers to `app.runControl` and deleting the shims. That is the
  last story's work (P l.128-131).
- The alerts cursor's settings route (P l.56). That belongs to a later card.
- Rewriting `docs/architecture.md` into one paragraph per store. That is a later docs card. This
  card edits only the sentences it makes false.

## Inherited constraints

- Every member lands in exactly one store. Nothing is duplicated, and nothing is dropped unless no
  code or test reads it (P l.61-67). Appendix A maps `runSettings`, `runSettingsRunner`,
  `applyRunSettings` and the `projectSwitched` load to `RunControlStore` (P l.234, 268, 308-309,
  359, 384).
- No duplicated helpers: envelopes are read with `Results.parseEnvelope`, and maps are handled
  with `Runs.copyMap` / `Runs.hasKey` (P l.68-71). `mergedPrefixes` moves from the dispatch store
  to `RunControlStore`; it is not copied.
- A store never imports or names a sibling (P l.46-50). The dispatch's inputs and signals are as
  P l.79 lists them: `runSettings` from `RunControlStore`, out `runSettingsWanted(root)` and
  `runSettingsSaveRequested(root, patch)`.
- The cross-concern couplings follow A.3:
  - `dispatchStartReplied` → `runSettingsSaveRequested(root, patch)`, "then `runSettings` comes
    back in as an input" (P l.443-444);
  - `openDispatch` reads `runSettings` that App binds (P l.446);
  - the save failure's flash goes through `noticeRequested(text)` (P l.445).
- Lifecycle stays per store (P l.92-97). The load on a project change becomes the dispatch's own
  `project` reaction, which emits the request that App routes.
- Shims (P l.122-127, with the writable precedent of `cancelText` at `RunStore.qml` 135-142 and
  S41's `dispatchState`):
  - each shim checks its handle first;
  - shims hold no state of their own and no logic beyond the forward;
  - the comment above them is the existing `// Moved to RunControlStore; removed by the last
    story` (RunStore.qml 119).
- Tests move with their members, and only construction and wiring change. A coupling between two
  concerns is pinned at App level (P l.98-104, 152-164).
- `tests/architecture` stays green: store imports, no duplicated components, icon glyph rules
  (P l.105-106).
- Non-goals (P l.146-150): no new helper argv, no change to `HelperRunner`, the backend helpers or
  `runs.js` semantics, and no UI change.
- From the card:
  - `bash tests/run.sh` is green;
  - TDD: tests first;
  - docstrings and comments state the contract only, with no narrative;
  - `tests/ui` passes untouched.

## Behaviour: `RunControlStore`

A new section, `// ---- run settings (split-runstore 4.2)`, after the notify switch.

| member | kind | contract |
|---|---|---|
| `runSettings` | `property var`, `({})` | `{root: settings}`: each root's last `get-run-settings` object, as read, with any saves since merged in. It is replaced, never changed in place. |
| `runSettingsOf(root)` | function | `runSettings[root]` when that key exists. Otherwise one shared empty object, the same object on every call. The store never writes into that object. |
| `applyRunSettings(root, settings)` | function | `root`'s entry becomes `settings`, as given (the same object, not a copy), in a new `runSettings` map. Anything that is not a non-null object gives `{}`. Root `""` changes nothing. |
| `loadRunSettings(root)` | function | See "Load" below. |
| `saveRunSettings(root, patch)` | function | See "Save" below. |
| `runSettingsSaveFailed(var root, var patch)` | signal | A save's reply was not `{"ok": true}`. `patch` is the patch that save sent. |
| `runSettingsRunners` | `readonly property alias` → `runSettingsState.runners` | The in-flight load and save runners, oldest first. |
| `runSettingsLoadRunner` | `readonly property alias` → `runSettingsState.lastLoad` | The runner of the newest `loadRunSettings` call until it replies; then `null`. |

### Load

`loadRunSettings(root)`:

- **Root `""`.** Nothing is launched and nothing changes.
- **Any other root.** `root`'s key is removed from `runSettings` (in a new map), so
  `runSettingsOf(root)` reads empty until the reply. Then one new runner launches:
  - argv `python3 <backendDir>projects/viewer-state.py get-run-settings <root>`, 4 elements;
  - guard `""`.

  It becomes `runSettingsLoadRunner`.
- **The reply.** Whatever project is open, it goes through `applyRunSettings(root,
  Results.parseEnvelope(stdout))`:
  - the parsed object is kept whole, `notifyOnEscalation` included;
  - an unreadable reply gives `{}`;
  - the notify switch is never touched.

  The runner then leaves `runSettingsRunners` and is destroyed. If it was
  `runSettingsLoadRunner`, that becomes `null`.
- **Concurrent requests.** Two loads each apply to their own root, and for the same root the
  reply that arrives last wins. A load never stops another load, a save, the
  `settingsLoadRunner` / `settingsSaveRunner` reads and writes, or a control runner's resume
  settings step.

### Save

`saveRunSettings(root, patch)`:

- **Root `""`, or a patch that is not a non-null object.** Nothing is launched and nothing
  changes.
- **Merge, synchronously, before the launch.** `root`'s entry becomes a new object:
  1. start from `Runs.copyMap(runSettingsOf(root))`;
  2. put every key of `patch` over it;
  3. for `prefixByMilestone`, use `mergedPrefixes(stored, patch.prefixByMilestone)` instead. That
     takes the stored entries when the stored value is a non-array object, then `patch`'s, which
     override them, as `set-run-settings` merges them.

  This is `applyRunSettings(root, merged)`, so the old entry object is left unchanged.
- **Launch.** Then one new runner launches:
  - argv `python3 <backendDir>projects/viewer-state.py set-run-settings <root>
    <JSON.stringify(patch)>`, 5 elements;
  - guard `""`.
- **The reply.**
  - `{"ok": true}` changes nothing more.
  - Anything else emits `runSettingsSaveFailed(root, patch)` once and leaves `runSettings` as it
    is. The merge is not undone, which matches today, where the in-memory write is not undone
    either. The store itself flashes nothing.

  Either way the runner leaves `runSettingsRunners` and is destroyed.

### Implementation shape

The planner fixes the details. The shape follows `controlC` / `controlState` / `dropRunner`
(`RunControlStore.qml` 411-424, 400-405, 144-147):

- a `QtObject runSettingsState { runners; lastLoad }`;
- a `Component runSettingsC` holding a `HelperRunner` with `root`, `patch` (var), `saving`
  (bool) and `script` set to viewer-state.py;
- a drop function.

### Header comment

The header comment adds one contract sentence. For example: "Each project's run settings
(`runSettings`, `{root: settings}`): `loadRunSettings` reads them and `saveRunSettings` merges and
writes a patch, each on a runner of its own; a failed save is announced
(`runSettingsSaveFailed`)."

## Behaviour: `RunDispatchStore`

| member | change |
|---|---|
| `signal runSettingsUpdated(var settings)` | removed |
| `signal runSettingsWanted(var root)` | new: "This project's run settings are wanted: `root` is the open project." |
| `signal runSettingsSaveRequested(var root, var patch)` | new: "An ok start's values are to be saved for the project it was made in." |
| `runSettings` input | same contract: the open project's run settings, never written by the store |
| `onProjectChanged` | `resetDispatch()`, then, when `project !== ""`, `runSettingsWanted(project)` |
| `dispatchStartReplied(runner, stdout)` | see below |
| `dispatchSaveReplied` | replaced by `dispatchSaveFailed(root, patch)` (below) |
| `mergedPrefixes` | moves to `RunControlStore` |
| `dispatchStartC`'s `saving` property, and the script swap | removed; `madeFor` and `savedJson` stay |
| `dispatchBook.savingFor` | new: `null`, or `{root, json}` for the save of this dispatch's ok start; `resetDispatch()` sets it to `null` |

### `dispatchStartReplied` on an ok envelope

`patch = JSON.parse(runner.savedJson)`.

- **This dispatch's start** (`isHereStart(runner)`). The steps keep 4.1's order (S41 "Couplings"
  1), with the settings step changed:
  1. set `dispatchRunId` and `dispatchMessage`;
  2. set `dispatchBook.savingFor = {root: runner.madeFor, json: runner.savedJson}`;
  3. emit `runSettingsSaveRequested(runner.madeFor, patch)`;
  4. set `dispatchState = "started"`;
  5. emit `refreshRequested("all")`;
  6. emit `dispatchStarted(id or null)`.
- **Any other ok start.** Emit `runSettingsSaveRequested(runner.madeFor, patch)` only.
- **Then, in both cases,** `dropStartRunner(runner)`. A start runner always leaves
  `dispatchStartRunners` at its start reply.

A failed or blocked start emits no save request (as today: "nothing saved").

### `dispatchSaveFailed(root, patch)`

When `dispatchBook.savingFor` is not `null`, `savingFor.root === root === dispatch.project` and
`savingFor.json === JSON.stringify(patch)`:

- emit `noticeRequested("Dispatch settings could not be saved")` once;
- set `savingFor` to `null`.

In any other case nothing happens. Like today's `isHereStart` check in `dispatchSaveReplied`, this
reports a failure only while the dispatch is still that start's. A reset, which covers a project
switch, a close and a new opening, forgets it.

### Header comment

Replace the start runner's "which after an ok start writes the saved values with viewer-state.py
set-run-settings" and "the run settings an ok start saves (runSettingsUpdated; …)" with contract
sentences. For example: "It launches no viewer-state.py: it asks for the open project's run
settings (runSettingsWanted) on each project change and for an ok start's values to be saved
(runSettingsSaveRequested, for the project the start was made in), reads runSettings as handed
in, and says a failed save of this dispatch's start (dispatchSaveFailed) as a notice."

## Behaviour: `RunStore`

### Removed

- `HelperRunner runSettingsRunner` (1082-1091) and its alias (244).
- `applyRunSettings` (1056-1061).
- `projectSwitched()` and `onProjectChanged` (669-679). Their comment's run-settings sentence
  goes with them.
- `property var runSettings` with its comment (214-218). The shim below replaces it.

`project` stays. App binds it, and the other stores and the shim read `app.runs.project`. The
header's "`project`, the open project, decides only the run settings" (12-14) becomes "`project`,
the open project, is read only by the run settings shims".

### Shims

These go in the existing `// Moved to RunControlStore` block (119-159).

| name | shim | without a handle |
|---|---|---|
| `runSettings` | **Writable**, following `cancelText` (135-142). It is a plain `property var runSettings: ({})` with a `Binding { target: store; property: "runSettings"; value: store.controlStore ? store.controlStore.runSettingsOf(store.project) : ({}) }`. Its `onRunSettingsChanged` returns when `controlStore` is null or when the value `===` `controlStore.runSettingsOf(project)`. Otherwise it forwards with `controlStore.applyRunSettings(store.project, store.runSettings)`. | a write is kept as written, and nothing is loaded |
| `runSettingsRunner` | `readonly property var runSettingsRunner: store.controlStore ? store.controlStore.runSettingsLoadRunner : null` | `null` |

**Why `runSettings` is writable.** `tests/ui/tst_dispatch_flow.qml:72` and
`tests/ui/tst_board_flow.qml:153` write `p.app.runs.runSettings = { verify: [...] }` and then
expect the dispatch form to start from it. The write therefore has to reach what the dispatch
reads. **Why it cannot loop:**

- After the forward, the binding yields the written object itself, so the `===` check returns.
- Without a handle, the shim does not write back at all.
- `runSettingsOf` returns a stable empty object, so a missing key never re-fires.

**Why `runSettingsRunner` is the newest load.** The `tests/ui` files call
`p.app.runs.runSettingsRunner.cancel()` right after selecting a project
(`tst_dispatch_flow.qml:70`, `tst_board_flow.qml:152`, `tst_runs_flow.qml:55, 861, 909`,
`tst_runs_real_data.qml:50`). `tst_app_runs.qml` reads `.current`. In each of these, a load for
the selected project is in flight, so the shim is a runner. Cancelling it bumps its `seq`, and its
reply is then never applied.

## Behaviour: `App`

`runDispatch`:

- `runSettings: app.runControl.runSettingsOf(app.runs.project)`;
- `onRunSettingsWanted: function(root) { app.runControl.loadRunSettings(root) }`;
- `onRunSettingsSaveRequested: function(root, patch) { app.runControl.saveRunSettings(root, patch) }`;
- `onRunSettingsUpdated` is removed.

`runControl`:

- `onRunSettingsSaveFailed: function(root, patch) { app.runDispatch.dispatchSaveFailed(root, patch) }`.

The comments above both are updated to name these routes (App.qml 141-144, 157-161), for
example: "… hands it … the open project's run settings from run control, and routes its
runSettingsWanted and runSettingsSaveRequested to run control's loadRunSettings and
saveRunSettings …"

## Equivalence (for the reviewer)

**Same argv, same moments.**

- A project change to a non-empty root launches exactly one `get-run-settings <root>`, as
  `projectSwitched` did. A change to `""` launches none.
- Every ok start launches exactly one `set-run-settings <madeFor> <savedJson>`. The bytes are the
  same because `JSON.stringify(JSON.parse(s))` returns `s` for a string `JSON.stringify` made.
  The top-level keys are not array-index-like.
- A failed or blocked start launches no save.

**The same values.**

- The form reads the open project's settings: `{}` from the switch until the reply, then the reply
  as read, with `{}` for an unreadable reply. The load removes the key, so a project visited
  earlier never shows its old entry before its reply.
- A here-start's merge lands synchronously, inside the `runSettingsSaveRequested` emission and
  before `started`, exactly where `runSettingsUpdated` landed before. It uses the same base (that
  project's settings) and the same per-milestone `prefixByMilestone` merge.
- A not-here start's merge lands on its own root's entry. When that root is not the open project,
  the open project's form never reads it, just as today's write never touched the open project's
  settings, and a later switch back reloads. When it is the open project (the dispatch was reset or
  closed after the start), see difference 5.

**The same flash.** "Dispatch settings could not be saved" flashes on `app.runControl` only while
the dispatch is still that start's, and never after a reset.

**Differences, all invisible to a user:**

1. **A load for a project the user has left is no longer stopped or dropped.** It lands in that
   root's own entry, which the open project's form never reads. A newer load does not stop an
   older one, which is the card's "one HelperRunner per request".
2. **The settings write launches before the start's re-snapshot.** Today it launches after. The
   two processes are independent.
3. **A start runner leaves `dispatchStartRunners` at its start reply.** Today it stays until its
   save replies. The write is now in `app.runControl.runSettingsRunners`.
4. **One degenerate case can now flash where today nothing would.** It needs all of these:
   - an earlier start's save, for the same project and with byte-identical values, fails;
   - that failure lands after the dispatch was reset;
   - a later start was then made in the same project;
   - that later start's own save is still pending.

   Today that failure says nothing. Now it flashes once, and the later save's own failure then
   says nothing. The planner should not try to close this: the card fixes the signal signatures,
   so there is no request token to compare.
5. **A not-here start in the still-open project updates that project's `runSettings`.** The
   dispatch was closed or reset after the start, and the project did not change. Today only the
   disk write follows and the open `runSettings` is untouched until a reload. Now the merge lands in
   that project's entry, so a later opening starts from the saved values. Nothing visible changes
   while the dispatch is closed, and a dispatch opened after the reply is the only reader. This
   follows from the card's routing (the store cannot tell here from not-here once the request is
   emitted), so the planner does not close it, and no test pins today's behaviour.

## Tests

TDD: each new or changed test is written first and fails before its code exists. Everything runs
through `bash tests/run.sh`. One file runs with `bash tests/run.sh tst_run_control_store`.

### Store unit: `tests/core/stores/tst_run_control_store.qml`

New section `// ---- run settings (split-runstore 4.2)`. These are store-unit tests because the
I/O is now this store's, and they are built bare with `makeControl()` unless noted. The header
comment adds "the run settings load and save".

- **C-S1 `test_run_settings_start_empty`.**
  - `runSettings` has no keys and `runSettingsRunners` is `[]`.
  - `runSettingsLoadRunner` is `null`.
  - `runSettingsOf("/x") === runSettingsOf("/y")`, and that object has no keys.
- **C-S2 `test_a_load_launches_get_run_settings_and_replaces_the_map`.**
  - `loadRunSettings(rootA)` launches one runner, and `argv` is
    `viewerCmd + "get-run-settings|/home/u/my proj"`, 4 elements, `launchGuard` `""`.
  - `runSettingsLoadRunner` is that runner.
  - A reply with `notifyOnEscalation: true` makes `runSettingsOf(rootA).notifyOnEscalation`
    `true` (the object is kept as read). `notifyOnEscalation` and `notifySaved` on the store stay
    `false`.
  - The map object before the call `!==` the one after.
  - The runner has left `runSettingsRunners`, and `runSettingsLoadRunner` is `null`.

  Moved from `tst_run_store.qml::test_run_settings_load_per_project_and_never_set_the_switch`.
- **C-S3 `test_a_load_reads_empty_until_its_reply_and_unreadable_is_empty`.** A has
  `parallelism` 4. `loadRunSettings(rootA)` again makes `runSettingsOf(rootA)` have 0 keys, and
  the old entry object still has `parallelism` 4 (not mutated). A `"Traceback: boom\n"` reply,
  exit 1, makes `Object.keys(runSettings)` include rootA, with 0 keys in the entry. Moved from
  `test_run_settings_follow_the_project`.
- **C-S4 `test_two_loads_in_flight_both_apply`.**
  - Load A, then load B. Both processes `running`, and `runSettingsLoadRunner` is B's.
  - Reply B, then A. Both entries are set.

  Concurrency is the card's "one HelperRunner per request".
- **C-S5 `test_a_load_stops_no_notify_or_resume_read`.**
  1. `active = true`, so `settingsLoadRunner` is in flight.
  2. `runs` holds a milestone run, and `control("resume", id)`, so the control runner's settings
     step is in flight.
  3. `loadRunSettings(rootB)` and `saveRunSettings(rootB, {parallelism: 2})`.
  4. All four processes are still `running`.
  5. Answer them all: the switch, the resume (now running `run-control.py … --verify …`), B's
     entry and the save each apply.
- **C-S6 `test_a_load_or_save_with_no_root_launches_nothing`.** `loadRunSettings("")`,
  `saveRunSettings("", {a: 1})` and `saveRunSettings(rootA, null)` leave `runSettingsRunners`
  empty, and `runSettings` is the same object as before.
- **C-S7 `test_a_save_merges_at_once_then_launches_set_run_settings`.**
  1. A is loaded with `prefixByMilestone {m9: "x"}`, `confirmDispatch: true` and `parallelism: 4`.
  2. Call `saveRunSettings(rootA, patch)` with patch `{verify: ["make test"], parallelism: 2,
     prefixByMilestone: {m1: "p"}}`. Before any reply:
     - `runSettingsOf(rootA)` has `parallelism` 2, `confirmDispatch` `true`, and
       `prefixByMilestone` with keys `m9,m1`;
     - the old entry is unchanged.
  3. `argv` is `viewerCmd + "set-run-settings|/home/u/my proj|" + JSON.stringify(patch)`, with 5
     elements.
  4. Repeat with a stored `prefixByMilestone` of `["a"]`, `"s"` and `null`. Each gives only `m1`.
  5. An ok reply emits no `runSettingsSaveFailed`, leaves `runSettings` the same object, and drops
     the runner.
- **C-S8 `test_a_failed_save_is_reported_once_and_keeps_the_merge`.**
  - An `ok:false` reply makes the `runSettingsSaveFailed` spy count 1, with arguments `rootA` and
    a patch whose `JSON.stringify` equals the sent one.
  - `runSettings` is the same object as before the reply, and `flashText` is `""`.
  - A second save answered with `garbage` makes the count 2.
  - Both runners are gone.
- **C-S9 `test_apply_run_settings_replaces_one_root`.**
  - `applyRunSettings(rootA, W)` makes `runSettingsOf(rootA) === W`, with a new map.
  - `applyRunSettings(rootA, "x")` gives an empty entry.
  - `applyRunSettings("", W)` leaves the map the same object.
- **C-S10 `test_run_settings_kept_even_after_notify_touched`.** Moved from `tst_run_store.qml`
  (2842). `setNotifyOnEscalation(true)` comes before the load reply. The switch stays `true`, and
  the entry is as read. This test uses the `RunStore` wired harness the file already has, because
  it was a RunStore test.

### Store unit: `tests/core/stores/tst_run_dispatch_store.qml`

**Bare store (section `// ---- the store alone`):**

- **D-N3 `test_its_own_project_change_resets_it_and_keeps_a_start_running`.** Updated. The late
  ok reply emits no `dispatchStarted` and no `refreshRequested`. It emits
  `runSettingsSaveRequested` once, with `rootA` and a patch whose `JSON.stringify ===
  tc.savedJson` ("recorded against A"). After it, `dispatchStartRunners.length` is 0.
- **D-N4 `test_a_start_reply_emits_settings_then_refresh_then_started`.** Updated. The recorder
  listens to `runSettingsSaveRequested` (recorded as `settings`), `refreshRequested` and
  `dispatchStarted`. The record is exactly `settings`, `refresh:"all"`, `started:r-1`.
  - The payload root is `rootA`.
  - The patch has `prefixHistory` `["old"]`, `parallelism` 4, and no `confirmDispatch`.
  - `prefixByMilestone.m1` is `"old"`.
  - `dispatchStartRunners.length` is 0 after the reply.
- **D-N5 `test_the_store_never_writes_its_own_run_settings`.** Unchanged in intent: with nothing
  connected, an ok start leaves `runSettings === S`.
- **D-N6 `test_a_failed_save_notices_only_while_it_is_this_dispatchs`.** Replaces 4.1's D-N6.
  1. From `started`, `dispatchSaveFailed(rootA, JSON.parse(tc.savedJson))` makes the
     `noticeRequested` count 1, with `"Dispatch settings could not be saved"`.
  2. The same call again gives 0 more.
  3. On a second store, a different patch gives 0.
  4. A third store is started, then `project = rootB`, then the failure: 0.
  5. A fourth store is started, then `closeDispatch()`, then the failure: 0.
- **D-N7 `test_its_own_project_change_wants_the_run_settings`.** New. A spy on
  `runSettingsWanted`:
  - `project = rootA` gives 1 call (`rootA`);
  - `project = ""` gives 1 call in total;
  - `project = rootB` gives 2 (`rootB`).

  Each time the store is `idle` before the signal arrives, which a handler connected to the
  signal checks.
- **D-N8 `test_a_start_launches_no_viewer_state_and_a_failed_start_saves_nothing`.** New.
  - After an ok start, no object under the store has a command containing `viewer-state.py`.
    Check this through `dispatchStartRunners`, which is empty, and through the spy, where the save
    is only requested.
  - A `failed` reply and a `StoryBlockedError` reply each emit no `runSettingsSaveRequested`.

**The wired harness (`make()` and the helpers built on it).** It is rewired the way App now wires
these stores:

- `d.runSettings` is bound to `c.runSettingsOf(store.project)`;
- `d.runSettingsWanted` connects to `c.loadRunSettings`;
- `d.runSettingsSaveRequested` connects to `c.saveRunSettings`;
- `c.runSettingsSaveFailed` connects to `d.dispatchSaveFailed`;
- `runSettingsUpdated` is no longer connected.

Two new helpers:

- `loadOf(d)`, which returns `controlOf(d).runSettingsLoadRunner`;
- `saveOf(d)`, which returns the newest save runner in `controlOf(d).runSettingsRunners`.

**The only edits inside moved bodies.** The expectations stay as they are.

| in the moved bodies | becomes |
|---|---|
| `runsOf(X).runSettingsRunner` | `loadOf(X)` |
| the save on the start runner: `runner.current` after an ok start reply (e.g. 918, 1142, 1166, 1515, 1542, 1555) | `saveOf(X).current` |
| `X.dispatchStartRunners.length` expected `1` while a save is in flight | `0`, plus `saveOf(X)` non-null (difference 3) |

The planner greps every `runner.current` and `dispatchStartRunners` use after an ok start. Reads
of `X.runSettings` stay on the dispatch store, whose bound input carries the same value. The
header comment (34-38) is updated to describe the new wiring.

### RunStore unit: `tests/core/stores/tst_run_store.qml`

- **Delete** these three tests, which C-S2, C-S3, C-S10 and A-S3 now cover:
  - `test_run_settings_load_per_project_and_never_set_the_switch` (2802);
  - `test_run_settings_kept_even_after_notify_touched` (2842);
  - `test_run_settings_follow_the_project` (2857).

  Also delete `runSettings(notify)` (2797), and `dispatchSettings()` (2836) if nothing else uses
  it.
- **Remove the assertion at 507-509** ("the new project's run settings still load"). `RunStore`
  no longer loads, and A-S3 pins the load at App level.
- New section `// ---- the run settings shims (split-runstore 4.2)`:
  - **R-S1 `test_without_a_control_store_the_run_settings_shims_are_empty`.** A bare store:
    - `runSettings` has 0 keys and `runSettingsRunner` is `null`;
    - `project = rootA`, then `project = rootB`, gives no `TypeError`;
    - `runSettings = W` keeps `W`.
  - **R-S2 `test_the_run_settings_shims_follow_the_control_store`.** A store wired to a control
    store (`wireControl`) with `project = rootA`:
    - the project change launches no load (`c.runSettingsRunners.length` is 0);
    - `c.loadRunSettings(rootA)` makes `store.runSettingsRunner === c.runSettingsLoadRunner`;
    - the reply makes `store.runSettings === c.runSettingsOf(rootA)` (parallelism 4);
    - `project = rootB` gives 0 keys;
    - a spy on `runSettingsChanged` counts at least 1 across these steps.
  - **R-S3 `test_writing_the_run_settings_shim_reaches_the_control_store`.** On the same wired
    store, `store.runSettings = W` makes `c.runSettingsOf(rootA) === W`. A later
    `c.loadRunSettings(rootA)` reply with `{parallelism: 9}` makes `store.runSettings.parallelism`
    9, so the binding survived the write. No `Binding loop` warning is in the output.

### App wiring: `tests/core/stores/tst_app_runs.qml`

**Existing tests, minimal edits with the expectations kept.** Through the shim,
`app.runs.runSettingsRunner.current` and `app.runs.runSettings` keep working unchanged in
`readyApp()` (176), at 408-409, 421-422 and 701-720, and in
`test_a_project_switch_through_app_resets_the_dispatch_and_reloads_run_settings`.

- `test_a_dispatch_start_through_app_snapshots_every_registered_root` (377): `save` becomes the
  newest process in `app.runControl.runSettingsRunners`. Length 5 and the 4-element prefix are
  unchanged.
- `test_a_dispatch_settings_save_failure_through_app_flashes` (394) and
  `test_a_dispatch_notice_through_app_is_run_controls_flash` (737): the failing reply goes to that
  save process. The flash expectations are unchanged. `dispatchStartRunners.length` stays 0.
- The header comment (5-13): `runSettingsUpdated` becomes `runSettingsWanted` and
  `runSettingsSaveRequested`, and run control's `runSettingsSaveFailed` is added.

**New tests, all in the App wiring tier, because each pins a route between two stores:**

- **A-S1 `test_the_dispatch_reads_its_run_settings_from_run_control`.** With `make()`:
  - `app.runControl.runSettingsLoadRunner` has `argv` `viewerCmd +
    "get-run-settings|/home/u/my proj"`;
  - after the reply, `app.runDispatch.runSettings === app.runControl.runSettingsOf("/home/u/my
    proj")`, and `=== app.runs.runSettings`.
- **A-S2 `test_a_start_through_app_saves_through_run_control`.**
  1. `readyApp()`, then an ok start.
  2. Exactly one new process exists in `app.runControl.runSettingsRunners`, and its `argv` starts
     `viewerCmd + "set-run-settings|/home/u/my proj|"`.
  3. `app.runControl.runSettingsOf(pA root).prefixByMilestone.m1` is `"old"`, and
     `app.runDispatch.runSettings` is that object.
  4. `app.runDispatch.dispatchStartRunners.length` is 0.
- **A-S3 `test_a_project_switch_through_app_loads_each_projects_settings_apart`.**
  1. With A's load in flight, `chooseProject(pB)`. `runControl.runSettingsRunners.length` is 2,
     and B's load `argv` is `get-run-settings|/home/u/b`.
  2. The late A reply lands, and `app.runDispatch.runSettings` still has 0 keys.
  3. The B reply with `{parallelism: 9}` gives 9.
  4. `chooseProject(pA)` makes `app.runDispatch.runSettings` have 0 keys until A's new load
     replies.
- **A-S4 `test_a_write_to_the_run_store_shim_reaches_the_dispatch_form`.** This pins what
  `tests/ui` relies on.
  1. `make()`, then `app.runs.runSettingsRunner.cancel()`.
  2. `app.runs.runSettings = { verify: ["make check"] }`.
  3. `openDispatch(cards.m1, cards)` makes `app.runDispatch.dispatchForm.verify[0]` `"make
     check"`.
- **A-S5 `test_a_save_failure_after_switching_away_flashes_nothing`.**
  1. `readyApp()`, ok start, then `chooseProject(pB)`.
  2. The save fails.
  3. `app.runControl.flashText` is `""`.

### Gate

- `bash tests/run.sh` is green: pytest (architecture included), then every qmltestrunner file,
  with no `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `is not a function`
  or `Binding loop`.
- `git diff --stat -- ui tests/ui` is empty.
- `grep -rn "viewer-state.py" core/stores/RunDispatchStore.qml core/stores/RunStore.qml` finds
  nothing.

## Docs

Only the sentences this card makes false are edited.

- **`docs/architecture.md:83`.** "`project` decides only `runSettings`" becomes "`project` is read
  only by the run settings shims".
- **`docs/architecture.md:92`.**
  - The App sentence becomes: App hands it `runSettings` from
    `app.runControl.runSettingsOf(project)`, and routes `runSettingsWanted` /
    `runSettingsSaveRequested` to `app.runControl.loadRunSettings` / `saveRunSettings` and run
    control's `runSettingsSaveFailed` back to `dispatchSaveFailed`.
  - "read on `runSettingsRunner` by every project switch (guarded by the new project)" becomes
    "asked for on every project change (`runSettingsWanted`)".
  - "After any successful start the same runner writes `set-run-settings`" becomes "After any
    successful start the dispatch asks run control to save, for the project it was made in"; the
    rest of the payload description stays.
  - "`runSettingsUpdated` carrying it merged per milestone id at once" becomes "merged per
    milestone id at once by run control".
- **`docs/architecture.md:93`** (`RunControlStore`). Add the run settings sentences: `runSettings`
  `{root: settings}` replaced never mutated, `runSettingsOf`, `loadRunSettings` (key dropped
  until the reply, one runner per request, no guard, unreadable → `{}`), `saveRunSettings`
  (merge at once with `prefixByMilestone` per milestone id, then `set-run-settings ROOT JSON`, a
  failed reply emits `runSettingsSaveFailed` and undoes nothing), and that no run settings
  request stops another or the notify or resume reads.
- **The shim sentence (`docs/architecture.md:91`).** Add `runSettings` (writable, writes reach
  `applyRunSettings`) and `runSettingsRunner` (the newest load) to the run control shims.
- **The three store header comments and App's two comments**, as described above.

## Review Focus (for the planner)

1. **`tests/ui` writes `app.runs.runSettings`, or cancels `app.runs.runSettingsRunner`, right
   after selecting a project.** Expected: the write reaches the dispatch form, and the runner is
   non-null. A read-only shim gives `Unable to assign`, and a `null` runner gives `TypeError`.
   Pinned by A-S4, R-S1, R-S3 and the untouched ui suites.
2. **A shim write-through, or a fresh `{}` per call, causes binding churn or a loop.** Expected:
   one write applies once, and `runSettingsOf` of a missing root is stable. Pinned by C-S1 and
   R-S3, and by the gate's `Binding loop` check.
3. **Switching back to a project visited earlier.** Expected: the form never starts from that
   project's old entry before its reply. The key is dropped on load. Pinned by C-S3 and A-S3
   step 4.
4. **A dispatch load runs while the notify read, the notify save or a resume's settings step is
   in flight.** Expected: none of them is stopped, and each reply applies. Pinned by C-S5.
5. **A save fails after the user switched project or closed the dispatch.** Expected: no flash.
   The same failure while still that start's dispatch flashes once. Pinned by D-N6 and A-S5.

## Hand-off to the planner

Suggested tasks, each with its own test cycle:

1. **`RunControlStore` owns the run settings I/O.**
   - Files: `core/stores/RunControlStore.qml` and `tests/core/stores/tst_run_control_store.qml`.
   - Tests C-S1 … C-S9 first, then the members above. Nothing routes to them yet, so this is safe
     alone.
2. **Dispatch emits, App routes, RunStore shims, all in one commit.** These cannot be split: the
   dispatch's input and the shims change together.
   - Files: `core/stores/RunDispatchStore.qml`, `RunStore.qml`, `App.qml`,
     `tests/core/stores/tst_run_dispatch_store.qml` (D-N3 … D-N8, harness rewire, redirects),
     `tst_run_store.qml` (deletions, R-S1 … R-S3), `tst_run_control_store.qml` (C-S10), and
     `tst_app_runs.qml` (edits, A-S1 … A-S5).
   - Run the full gate.
3. **Docs.** The `docs/architecture.md` edits and the header and App comments. Contract only, no
   narrative.

The interfaces later tasks rely on, exactly:

- `RunControlStore`:
  - `runSettings: var`;
  - `runSettingsOf(root) -> object`;
  - `applyRunSettings(root, settings)`;
  - `loadRunSettings(root)`;
  - `saveRunSettings(root, patch)`;
  - `signal runSettingsSaveFailed(var root, var patch)`;
  - `runSettingsRunners: var` (list);
  - `runSettingsLoadRunner: var` (a `HelperRunner` or `null`).
- `RunDispatchStore`:
  - `signal runSettingsWanted(var root)`;
  - `signal runSettingsSaveRequested(var root, var patch)`;
  - `dispatchSaveFailed(root, patch)`;
  - the `runSettings: var` input, unchanged;
  - `runSettingsUpdated` is gone.
- `RunStore` shims: `runSettings: var` (writable) and `runSettingsRunner: var`.
