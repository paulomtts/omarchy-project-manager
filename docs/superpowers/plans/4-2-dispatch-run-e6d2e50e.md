# 4.2 Dispatch run settings through RunControlStore — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move every run settings read and write (`get-run-settings` on a project change, `set-run-settings` after an ok start) out of `RunDispatchStore` and `RunStore` into `RunControlStore`, with the dispatch asking through signals that App routes, and `RunStore` keeping `runSettings` / `runSettingsRunner` as shims, with no behaviour a user can see changing.

**Architecture:** `RunControlStore` gains `runSettings` (`{root: settings}`), `runSettingsOf`, `applyRunSettings`, `loadRunSettings`, `saveRunSettings`, `mergedPrefixes`, `runSettingsSaveFailed`, and one `HelperRunner` per request (`runSettingsC`, tracked in `runSettingsState`). `RunDispatchStore` drops `runSettingsUpdated`, `mergedPrefixes`, `dispatchSaveReplied` and the start runner's second life; it emits `runSettingsWanted(root)` on each project change and `runSettingsSaveRequested(root, patch)` on each ok start, and gets `dispatchSaveFailed(root, patch)` as an entry point. App binds the dispatch's `runSettings` to `app.runControl.runSettingsOf(app.runs.project)` and routes the three signals. `RunStore` loses its loader and keeps a writable `runSettings` shim (the `cancelText` pattern) and a read-only `runSettingsRunner` shim.

**Tech Stack:** QML (Qt 6.11, Quickshell), qmltestrunner with stubs in `tests/stubs` (a stub `Process` never exits on its own: tests answer it with `reply(proc, text, code)`), pytest (architecture tests). Everything runs through `bash tests/run.sh [filter]` — pytest first (about 2 minutes), then each QML test file whose path contains the filter. Wrap it in `timeout 900`.

**Spec:** `docs/superpowers/specs/4-2-dispatch-run-e6d2e50e.md` (reproduced verbatim right below, before the tasks).

## Global Constraints

- Pure refactor: every helper gets the same argv; the same `get-run-settings` launches on the same project change; every ok start launches the same `set-run-settings`; no UI change; no change to `HelperRunner`, the backend helpers or `runs.js`.
- Every member lands in exactly one store. `mergedPrefixes` moves to `RunControlStore` (Task 1 adds it there, Task 2 deletes the dispatch's copy in the same branch).
- No duplicated helpers: envelopes are read with `Results.parseEnvelope`, maps handled with `Runs.copyMap` / `Runs.hasKey`.
- A store never imports or names a sibling. `RunDispatchStore` inputs stay `backendDir`, `project`, `active`, `runs`, `runSettings`; its run settings signals are exactly `runSettingsWanted(var root)` and `runSettingsSaveRequested(var root, var patch)`.
- `RunControlStore` interface, exactly: `runSettings: var`; `runSettingsOf(root) -> object`; `applyRunSettings(root, settings)`; `loadRunSettings(root)`; `saveRunSettings(root, patch)`; `signal runSettingsSaveFailed(var root, var patch)`; `runSettingsRunners` (alias, list); `runSettingsLoadRunner` (alias, `HelperRunner` or `null`).
- `RunDispatchStore` never launches `viewer-state.py` and never writes its own `runSettings`.
- `RunStore` launches no `get-run-settings`; its shims sit under the existing `// Moved to RunControlStore; removed by the last story` comment, check `store.controlStore` first, hold no state and no logic beyond the forward.
- The notice sentence is exactly `Dispatch settings could not be saved`.
- `ui/` and `tests/ui/` are untouched: `git diff --stat d7e0fc9 -- ui tests/ui` is empty.
- Docstrings and comments state the contract only, with no narrative.
- Gate: `bash tests/run.sh` green — pytest (incl. `tests/architecture`), then every qmltestrunner file, with no `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `is not a function` in the output; `Binding loop` is checked by `failOnWarning` in R-S3 and A-S4 (run.sh does not print warnings).

## Notes on the spec

1. **`tst_run_store.qml` has its own dispatch wiring** (`wireDispatch`, line ~3782) that connects `d.runSettingsUpdated` and binds `d.runSettings` to `store.runSettings`. The spec's test list does not name it, but once the signal is gone `d.runSettingsUpdated.connect` throws. Task 2 rewires it exactly like the dispatch harness (bound to the paired control store's `runSettingsOf(store.project)`, the three routes). Its tests' expectations do not change.
2. **The save runner carries the patch as a string.** `runSettingsC` has `root` (string), `json` (string, the `JSON.stringify(patch)` that goes into argv) and `saving` (bool) instead of a `patch` var: initial properties go through `createObject`, which is not trusted to keep a JS object as is. The failure signal emits `JSON.parse(runner.json)`, whose `JSON.stringify` is byte-identical to what was sent, which is what `dispatchSaveFailed` compares. (Checked on this machine: a JS object passed through a `var` signal parameter keeps its identity and key order.)
3. **A cancelled load never replies.** `tests/ui` call `app.runs.runSettingsRunner.cancel()`; `HelperRunner.cancel()` bumps `seq`, so the runner never emits `finished` and stays in `runSettingsRunners` and stays `runSettingsLoadRunner`. That is what keeps the shim non-null for a second `cancel()` (`ctrl6` in `tst_runs_flow.qml` cancels repeatedly). In production nothing cancels a load.
4. **D-N7's order.** The spec's order (`rootA`, `""`, `rootB`) cannot show the store is reset before it asks, because a dispatch cannot be open with no project. The test opens the dispatch on `rootA`, switches to `rootB` (the handler sees `idle`), then to `""` (no call). The counts the spec asks for are all asserted.
5. **D-N5** loses its last two lines (replying to the save on the start runner): there is no save on that runner any more. Its intent ("the store never writes its own run settings") is asserted unchanged.
6. **Comments move with their code.** The `RunDispatchStore`, `RunStore` and App comments the spec lists under "Docs" are rewritten in Task 2, in the same hunks as the code they describe; Task 1 writes `RunControlStore`'s header sentence; Task 3 edits only `docs/architecture.md`.
7. **The dispatch header avoids the literal `viewer-state.py`.** The spec's suggested sentence ("It launches no viewer-state.py: …") would make its own gate (`grep -rn "viewer-state.py" core/stores/RunDispatchStore.qml` finds nothing) fail, so the header says "It never reads or writes the run settings itself: …" with the rest of the spec's sentence unchanged.
8. **Redirect census in `tst_run_dispatch_store.qml`.** 14 reads of `runsOf(X).runSettingsRunner.current` become `loadOf(X).current` (lines 354, 400, 431, 951, 971, 1058, 1157, 1175, 1198, 1259, 1270, 1505, 1563, 1670). Ten reads of a start runner's `current` after its ok reply become `saveOf(X).current` (lines 916, 966, 980, 1081, 1142-1143, 1166, 1515, 1531, 1542, 1555). One `dispatchStartRunners.length` expected `1` while a save is in flight (914) becomes `0` plus `saveOf(store)` non-null. The edit script asserts each.

## Review Focus

1. **`tests/ui` writes `app.runs.runSettings`, or cancels `app.runs.runSettingsRunner`, right after selecting a project** (`tst_dispatch_flow.qml:70-72`, `tst_board_flow.qml:152-153`, `tst_runs_flow.qml:55, 861, 909`, `tst_runs_real_data.qml:50`): the write must reach the dispatch form and the runner must be non-null; a read-only shim prints `Unable to assign`, a `null` runner a `TypeError` → A-S4 in Task 2, R-S1 and R-S3 in Task 2, and the untouched ui suites in the gate.
2. **The writable shim or a fresh `{}` per call causes binding churn or a loop**: one write applies once, `runSettingsOf` of a missing root is one stable object → C-S1 in Task 1, R-S3 (with `failOnWarning(/Binding loop/)`) and A-S4 in Task 2.
3. **Switching back to a project visited earlier**: the form must never start from that project's old entry before its new reply → C-S3 in Task 1, A-S3 step 4 in Task 2.
4. **A run settings load or save runs while the notify read, the notify save or a resume's settings step is in flight**: none is stopped, each reply applies → C-S5 in Task 1.
5. **A save fails after the user switched project or closed the dispatch**: no flash; the same failure while still that start's dispatch flashes once → D-N6 and A-S5 in Task 2.

---

## Spec (verbatim)

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

---

## File structure

| File | Task | Responsibility after this card |
|---|---|---|
| `core/stores/RunControlStore.qml` | 1 | Owns every run settings read and write: the `{root: settings}` map, one runner per request, the save failure signal. |
| `tests/core/stores/tst_run_control_store.qml` | 1, 2 | C-S1 … C-S9 (bare store, Task 1); C-S10 (wired RunStore, Task 2). |
| `core/stores/RunDispatchStore.qml` | 2 | Asks for run settings and for saves; says a failed save of its own start; no `viewer-state.py`. |
| `core/stores/RunStore.qml` | 2 | No loader; `runSettings` (writable) and `runSettingsRunner` shims. |
| `core/stores/App.qml` | 2 | Binds the dispatch's `runSettings` to run control; routes the three run settings signals. |
| `tests/core/stores/tst_run_dispatch_store.qml` | 2 | Harness rewired; D-N3 … D-N8; redirects. |
| `tests/core/stores/tst_run_store.qml` | 2 | Three loader tests and one assertion deleted; `wireDispatch` rewired; R-S1 … R-S3. |
| `tests/core/stores/tst_app_runs.qml` | 2 | Three edits; A-S1 … A-S5. |
| `docs/architecture.md` | 3 | The sentences this card makes false. |

---

### Task 1: `RunControlStore` owns the run settings I/O, built alone

Nothing routes to the new members yet, so this task changes no behaviour. `RunDispatchStore` still has its own `mergedPrefixes` until Task 2.

**Files:**
- Modify: `core/stores/RunControlStore.qml` (header 19-22; properties after 55; aliases after 61; new section after 355; `QtObject` and `Component` at the end)
- Test: `tests/core/stores/tst_run_control_store.qml` (header 2-4; new section before line 313, `// ---- through a RunStore wired the way App wires app.runControl`)

**Interfaces:**
- Consumes: `Results.parseEnvelope(text) -> object|null` (`core/domain/results.js:44`), `Runs.copyMap(map) -> object`, `Runs.hasKey(map, key) -> bool` (`core/domain/runs.js:1358-1371`), `HelperRunner` (`script`, `guard`, `run(args)`, `current`, `signal finished(string stdout, int exitCode, string launchedGuard)`).
- Produces (Task 2 relies on these exact names):
  - `property var runSettings` — `{root: settings}`, replaced never mutated;
  - `function runSettingsOf(root)` — the entry, or one shared empty object;
  - `function applyRunSettings(root, settings)`;
  - `function loadRunSettings(root)`;
  - `function saveRunSettings(root, patch)`;
  - `function mergedPrefixes(stored, entry)`;
  - `signal runSettingsSaveFailed(var root, var patch)`;
  - `readonly property alias runSettingsRunners` — list of runners, each with `root: string`, `json: string`, `saving: bool`, `current` (its stub `Process`);
  - `readonly property alias runSettingsLoadRunner` — the newest load's runner until it replies, else `null`.

- [ ] **Step 1: Write the failing tests**

Save as `/tmp/t1_tests.py` and run `python3 /tmp/t1_tests.py` from the worktree root.

```python
p = "tests/core/stores/tst_run_control_store.qml"
t = open(p).read()

def cut(t, old, new):
    assert t.count(old) == 1, old[:80]
    return t.replace(old, new)

t = cut(t, r"""// The run controls store: control requests and their settling, the resume
// verify read, the still-waiting clock, the control error, the cancel
// confirmation, the footer flash and the notify switch. Built alone and""", r"""// The run controls store: control requests and their settling, the resume
// verify read, the still-waiting clock, the control error, the cancel
// confirmation, the footer flash, the notify switch and the run settings
// load and save. Built alone and""")

section = r"""  // ---- run settings (split-runstore 4.2)

  // get-run-settings with every key, as viewer-state.py prints it.
  function dispatchSettings() {
    return JSON.stringify({ verify: ["uv run pytest"], allowNoVerification: false, notifyOnEscalation: false,
                            prefixHistory: ["old"], parallelism: 4, confirmDispatch: true }) + "\n"
  }

  // C-S1
  function test_run_settings_start_empty() {
    var c = makeControl(); if (!c) return
    compare(Object.keys(c.runSettings).length, 0)
    compare(c.runSettingsRunners.length, 0)
    compare(c.runSettingsLoadRunner, null)
    verify(c.runSettingsOf("/x") === c.runSettingsOf("/y"), "one shared empty object")
    compare(Object.keys(c.runSettingsOf("/x")).length, 0)
  }

  // C-S2
  function test_a_load_launches_get_run_settings_and_replaces_the_map() {
    var c = makeControl(); if (!c) return
    var before = c.runSettings
    c.loadRunSettings(tc.rootA)
    compare(c.runSettingsRunners.length, 1)
    var runner = c.runSettingsRunners[0]
    verify(c.runSettingsLoadRunner === runner)
    var proc = runner.current
    compare(argv(proc), tc.viewerCmd + "get-run-settings|/home/u/my proj")
    compare(proc.command.length, 4)
    compare(proc.launchGuard, "")
    reply(proc, JSON.stringify({ verify: [], allowNoVerification: false, notifyOnEscalation: true }) + "\n", 0)
    compare(c.runSettingsOf(tc.rootA).notifyOnEscalation, true, "the object is kept as it was read")
    compare(c.notifyOnEscalation, false, "a stored per-project value is never the switch")
    compare(c.notifySaved, false)
    verify(c.runSettings !== before, "the map is replaced")
    compare(c.runSettingsRunners.length, 0)
    compare(c.runSettingsLoadRunner, null)
  }

  // C-S3 and Review Focus 3
  function test_a_load_reads_empty_until_its_reply_and_unreadable_is_empty() {
    var c = makeControl(); if (!c) return
    c.loadRunSettings(tc.rootA)
    reply(c.runSettingsLoadRunner.current, dispatchSettings(), 0)
    var old = c.runSettingsOf(tc.rootA)
    compare(old.parallelism, 4)
    c.loadRunSettings(tc.rootA)
    compare(Object.keys(c.runSettingsOf(tc.rootA)).length, 0, "empty until the reply")
    compare(old.parallelism, 4, "the old entry is not changed in place")
    reply(c.runSettingsLoadRunner.current, "Traceback: boom\n", 1)
    verify(Object.keys(c.runSettings).indexOf(tc.rootA) >= 0, "an unreadable reply still sets the entry")
    compare(Object.keys(c.runSettingsOf(tc.rootA)).length, 0, "an unreadable reply is {}")
  }

  // C-S4
  function test_two_loads_in_flight_both_apply() {
    var c = makeControl(); if (!c) return
    c.loadRunSettings(tc.rootA)
    var loadA = c.runSettingsLoadRunner
    c.loadRunSettings(tc.rootB)
    var loadB = c.runSettingsLoadRunner
    verify(loadA !== loadB, "one runner per request")
    compare(c.runSettingsRunners.length, 2)
    compare(loadA.current.running, true, "a newer load stops no older one")
    compare(loadB.current.running, true)
    reply(loadB.current, JSON.stringify({ parallelism: 9 }) + "\n", 0)
    compare(c.runSettingsLoadRunner, null, "the newest load replied")
    reply(loadA.current, dispatchSettings(), 0)
    compare(c.runSettingsOf(tc.rootA).parallelism, 4)
    compare(c.runSettingsOf(tc.rootB).parallelism, 9)
    compare(c.runSettingsRunners.length, 0)

    c.loadRunSettings(tc.rootA)
    var first = c.runSettingsLoadRunner
    c.loadRunSettings(tc.rootA)
    var second = c.runSettingsLoadRunner
    reply(second.current, JSON.stringify({ parallelism: 2 }) + "\n", 0)
    reply(first.current, JSON.stringify({ parallelism: 3 }) + "\n", 0)
    compare(c.runSettingsOf(tc.rootA).parallelism, 3, "for one root the reply that arrives last wins")
  }

  // C-S5 and Review Focus 4
  function test_a_load_stops_no_notify_or_resume_read() {
    var c = makeControl(); if (!c) return
    c.active = true
    var notifyLoad = c.settingsLoadRunner.current
    verify(notifyLoad, "the opening reads the notify switch")
    c.runs = [held(dead("r2"), tc.rootA)]
    compare(c.control("resume", "r2"), true)
    var resume = c.controlRunners[0]
    var resumeRead = resume.current
    compare(argv(resumeRead), tc.settingsCmd)
    c.loadRunSettings(tc.rootB)
    c.saveRunSettings(tc.rootB, { parallelism: 2 })
    compare(c.runSettingsRunners.length, 2)
    var load = c.runSettingsRunners[0]
    var save = c.runSettingsRunners[1]
    compare(notifyLoad.running, true, "the notify read")
    compare(resumeRead.running, true, "the resume's settings step")
    compare(load.current.running, true, "the load")
    compare(save.current.running, true, "the save")
    reply(notifyLoad, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(c.notifyOnEscalation, true)
    reply(resumeRead, settingsReply(["make test"], false), 0)
    compare(argv(resume.current), tc.ctlCmd + "resume|r2|/home/u/my proj|--verify|make test", "the resume went on to run-control")
    reply(load.current, JSON.stringify({ parallelism: 9 }) + "\n", 0)
    compare(c.runSettingsOf(tc.rootB).parallelism, 9)
    var failed = createTemporaryObject(spyC, tc, { target: c, signalName: "runSettingsSaveFailed" })
    reply(save.current, JSON.stringify({ ok: true }) + "\n", 0)
    compare(failed.count, 0)
    compare(c.runSettingsRunners.length, 0)
  }

  // C-S6
  function test_a_load_or_save_with_no_root_launches_nothing() {
    var c = makeControl(); if (!c) return
    var before = c.runSettings
    c.loadRunSettings("")
    c.saveRunSettings("", { a: 1 })
    c.saveRunSettings(tc.rootA, null)
    c.saveRunSettings(tc.rootA, "x")
    compare(c.runSettingsRunners.length, 0)
    verify(c.runSettings === before, "nothing changes")
  }

  // C-S7
  function test_a_save_merges_at_once_then_launches_set_run_settings() {
    var c = makeControl(); if (!c) return
    c.loadRunSettings(tc.rootA)
    reply(c.runSettingsLoadRunner.current,
          JSON.stringify({ prefixByMilestone: { m9: "x" }, confirmDispatch: true, parallelism: 4 }) + "\n", 0)
    var old = c.runSettingsOf(tc.rootA)
    var patch = { verify: ["make test"], parallelism: 2, prefixByMilestone: { m1: "p" } }
    c.saveRunSettings(tc.rootA, patch)
    var now = c.runSettingsOf(tc.rootA)
    compare(now.parallelism, 2)
    compare(now.confirmDispatch, true, "a key the patch does not write is kept")
    compare(now.verify.join(","), "make test")
    compare(Object.keys(now.prefixByMilestone).join(","), "m9,m1", "merged per milestone id")
    compare(old.parallelism, 4, "the old entry is not changed in place")
    compare(Object.keys(old.prefixByMilestone).join(","), "m9")
    compare(c.runSettingsRunners.length, 1)
    var save = c.runSettingsRunners[0]
    compare(c.runSettingsLoadRunner, null, "a save is not a load")
    compare(argv(save.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + JSON.stringify(patch))
    compare(save.current.command.length, 5)
    compare(save.current.launchGuard, "")
    var failed = createTemporaryObject(spyC, tc, { target: c, signalName: "runSettingsSaveFailed" })
    var map = c.runSettings
    reply(save.current, JSON.stringify({ ok: true }) + "\n", 0)
    compare(failed.count, 0)
    verify(c.runSettings === map, "an ok reply changes nothing more")
    compare(c.runSettingsRunners.length, 0)

    var stored = [["a"], "s", null]
    for (var i = 0; i < stored.length; i++) {
      var other = makeControl(); if (!other) return
      other.loadRunSettings(tc.rootA)
      reply(other.runSettingsLoadRunner.current, JSON.stringify({ prefixByMilestone: stored[i] }) + "\n", 0)
      other.saveRunSettings(tc.rootA, { prefixByMilestone: { m1: "p" } })
      compare(Object.keys(other.runSettingsOf(tc.rootA).prefixByMilestone).join(","), "m1", "stored " + i)
    }
  }

  // C-S8
  function test_a_failed_save_is_reported_once_and_keeps_the_merge() {
    var c = makeControl(); if (!c) return
    var failed = createTemporaryObject(spyC, tc, { target: c, signalName: "runSettingsSaveFailed" })
    var patch = { parallelism: 2, prefixHistory: ["m3", "old"], verify: ["make test"] }
    c.saveRunSettings(tc.rootA, patch)
    var map = c.runSettings
    compare(c.runSettingsOf(tc.rootA).parallelism, 2, "merged at once")
    reply(c.runSettingsRunners[0].current, JSON.stringify({ ok: false, error: "x" }) + "\n", 1)
    compare(failed.count, 1)
    compare(failed.signalArguments[0][0], tc.rootA)
    compare(JSON.stringify(failed.signalArguments[0][1]), JSON.stringify(patch), "the patch that save sent")
    verify(c.runSettings === map, "the merge is not undone")
    compare(c.runSettingsOf(tc.rootA).parallelism, 2)
    compare(c.flashText, "", "the store itself flashes nothing")
    c.saveRunSettings(tc.rootA, { parallelism: 3 })
    reply(c.runSettingsRunners[0].current, "garbage\n", 1)
    compare(failed.count, 2, "an unreadable reply is a failure too")
    compare(c.runSettingsRunners.length, 0)
  }

  // C-S9
  function test_apply_run_settings_replaces_one_root() {
    var c = makeControl(); if (!c) return
    var w = { parallelism: 7 }
    var before = c.runSettings
    c.applyRunSettings(tc.rootA, w)
    verify(c.runSettingsOf(tc.rootA) === w, "the same object, not a copy")
    verify(c.runSettings !== before, "a new map")
    c.applyRunSettings(tc.rootA, "x")
    compare(Object.keys(c.runSettingsOf(tc.rootA)).length, 0, "not an object: {}")
    var map = c.runSettings
    c.applyRunSettings("", w)
    verify(c.runSettings === map, "root \"\" changes nothing")
  }

"""
t = cut(t, "  // ---- through a RunStore wired the way App wires app.runControl\n",
        section + "  // ---- through a RunStore wired the way App wires app.runControl\n")
open(p, "w").write(t)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 900 bash tests/run.sh tst_run_control_store`
Expected: FAIL — the nine new tests fail (`TypeError: Property 'loadRunSettings' of object ... is not a function`, `runSettingsOf ... is not a function`, `compare` on `undefined`), the existing tests pass.

- [ ] **Step 3: Implement the members**

Save as `/tmp/t1_store.py` and run `python3 /tmp/t1_store.py`.

```python
p = "core/stores/RunControlStore.qml"
t = open(p).read()

def cut(t, old, new):
    assert t.count(old) == 1, old[:80]
    return t.replace(old, new)

# Header: one contract sentence.
t = cut(t, r"""// (set-global-settings); a failed save puts it back and flashes. A project
// switch changes nothing here.
Scope {""", r"""// (set-global-settings); a failed save puts it back and flashes. A project
// switch changes nothing here. Each project's run settings (`runSettings`,
// {root: settings}): loadRunSettings reads them and saveRunSettings merges
// and writes a patch, each on a runner of its own; a failed save is
// announced (runSettingsSaveFailed).
Scope {""")

# The map and the failure signal, after the notify switch's state.
t = cut(t, "  property bool notifyTouched: false\n", r"""  property bool notifyTouched: false
  // Each project's run settings, {root: settings}: the root's last
  // get-run-settings object as read, with the saves since merged in.
  // Replaced, never changed in place.
  property var runSettings: ({})
  // A save's reply was not {"ok": true}: `patch` is what that save sent.
  signal runSettingsSaveFailed(var root, var patch)
""")

# The aliases.
t = cut(t, "  readonly property alias settingsSaveRunner: settingsSaveRunner\n", r"""  readonly property alias settingsSaveRunner: settingsSaveRunner
  readonly property alias runSettingsRunners: runSettingsState.runners     // in-flight run settings loads and saves, oldest first
  readonly property alias runSettingsLoadRunner: runSettingsState.lastLoad // the newest load until it replies; else null
""")

# The functions, after the notify switch's.
t = cut(t, "  // Only while the panel is open and a control request is pending: closing the\n", r"""  // ---- run settings (split-runstore 4.2)

  // root's run settings: its entry in runSettings, else one shared empty
  // object, the same on every call, which the store never writes.
  function runSettingsOf(root) {
    return Runs.hasKey(control.runSettings, root) ? control.runSettings[root] : runSettingsState.empty
  }

  // root's entry becomes `settings` as given (not a copy) in a new map;
  // anything that is not a non-null object gives {}. Root "" changes nothing.
  function applyRunSettings(root, settings) {
    if (typeof root !== "string" || root === "") return
    var map = Runs.copyMap(control.runSettings)
    map[root] = settings !== null && typeof settings === "object" ? settings : {}
    control.runSettings = map
  }

  // viewer-state.py get-run-settings ROOT on a runner of its own: root's
  // entry is dropped until the reply, which is kept whole for root whatever
  // project is open ({} when unreadable; it never touches the notify
  // switch). Root "" launches nothing.
  function loadRunSettings(root) {
    if (typeof root !== "string" || root === "") return
    var map = Runs.copyMap(control.runSettings)
    delete map[root]
    control.runSettings = map
    runSettingsState.lastLoad = control.launchRunSettings({ root: root }, ["get-run-settings", root])
  }

  // patch is merged over root's entry at once (each key replaces, except
  // prefixByMilestone, merged per milestone id), then viewer-state.py
  // set-run-settings ROOT JSON(patch) runs on a runner of its own. A reply
  // other than {"ok": true} emits runSettingsSaveFailed(root, patch) and
  // undoes nothing. Root "" or a patch that is not a non-null object
  // launches nothing.
  function saveRunSettings(root, patch) {
    if (typeof root !== "string" || root === "" || patch === null || typeof patch !== "object") return
    var merged = Runs.copyMap(control.runSettingsOf(root))
    for (var key in patch) {
      merged[key] = key === "prefixByMilestone" ? control.mergedPrefixes(merged.prefixByMilestone, patch[key]) : patch[key]
    }
    control.applyRunSettings(root, merged)
    var json = JSON.stringify(patch)
    control.launchRunSettings({ root: root, json: json, saving: true }, ["set-run-settings", root, json])
  }

  // A fresh {milestone id: prefix} map: stored's own entries when stored is
  // an object that is not an array, then entry's, which override them, as
  // set-run-settings merges prefixByMilestone.
  function mergedPrefixes(stored, entry) {
    var merged = stored !== null && typeof stored === "object" && !Array.isArray(stored) ? Runs.copyMap(stored) : {}
    for (var id in entry) merged[id] = entry[id]
    return merged
  }

  // A new runSettingsC runner with `props`, added to runSettingsRunners and
  // launched with `args`; returns it.
  function launchRunSettings(props, args) {
    var runner = runSettingsC.createObject(control, props)
    runSettingsState.runners = runSettingsState.runners.concat([runner])
    runner.run(args)
    return runner
  }

  // A load's reply is kept for its root; a save's reply other than
  // {"ok": true} is announced. Either way the runner goes.
  function runSettingsReplied(runner, stdout) {
    if (runner.saving) {
      var reply = Results.parseEnvelope(stdout)
      if (!(reply !== null && reply.ok === true)) control.runSettingsSaveFailed(runner.root, JSON.parse(runner.json))
    } else {
      control.applyRunSettings(runner.root, Results.parseEnvelope(stdout))
    }
    control.dropRunSettingsRunner(runner)
  }

  // A run settings runner's request is over: it leaves runSettingsRunners
  // (and runSettingsLoadRunner) and is destroyed.
  function dropRunSettingsRunner(runner) {
    runSettingsState.runners = runSettingsState.runners.filter(function(r) { return r !== runner })
    if (runSettingsState.lastLoad === runner) runSettingsState.lastLoad = null
    runner.destroy()
  }

  // Only while the panel is open and a control request is pending: closing the
""")

# The state and the per-request runner, at the end.
assert t.endswith("  }\n}\n")
t = t[:-2] + r"""
  // The run settings requests' own state; kept apart so consumers cannot
  // write it. `lastLoad` is the newest load until it replies; `empty` is
  // runSettingsOf's shared empty object.
  QtObject {
    id: runSettingsState
    property var runners: []
    property var lastLoad: null
    property var empty: ({})
  }

  // One HelperRunner per run settings request, so loads and saves never stop
  // each other, the notify switch's runners or a resume's settings step. No
  // guard: a reply is applied whatever project is open.
  Component {
    id: runSettingsC

    HelperRunner {
      id: rr
      property string root: ""      // the project the request is for
      property string json: ""      // a save's patch as set-run-settings takes it; "" for a load
      property bool saving: false   // set-run-settings, not get-run-settings
      script: control.backendDir + "projects/viewer-state.py"
      onFinished: function(stdout, exitCode) { control.runSettingsReplied(rr, stdout) }
    }
  }
}
"""
open(p, "w").write(t)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 900 bash tests/run.sh tst_run_control_store`
Expected: pytest passes; `== tests/core/stores/tst_run_control_store.qml` shows `Totals: N passed, 0 failed` and no `TypeError`/`ReferenceError` lines; exit status 0.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunControlStore.qml tests/core/stores/tst_run_control_store.qml
git commit -m "feat(runs): RunControlStore owns the run settings load and save, built alone"
```

---

### Task 2: Dispatch emits, App routes, RunStore shims

These change together: the dispatch's `runSettings` input, the App routes, the RunStore shims and the harnesses that wire them. One commit.

**Files:**
- Modify: `core/stores/RunDispatchStore.qml` (header 7-21; signal 35-37; `onProjectChanged` 42-44; `resetDispatch` 80-87; `mergedPrefixes` 286-293 deleted; `dispatchStartReplied` + `dispatchSaveReplied` 335-396; `dispatchBook` 431-445; `dispatchStartC` 447-464)
- Modify: `core/stores/RunStore.qml` (header 12-14; shims after 159; 214-218, 244, 669-680, 1056-1062, 1082-1092 deleted)
- Modify: `core/stores/App.qml` (131-144, 157-174)
- Test: `tests/core/stores/tst_run_dispatch_store.qml`, `tests/core/stores/tst_run_store.qml`, `tests/core/stores/tst_run_control_store.qml`, `tests/core/stores/tst_app_runs.qml`

**Interfaces:**
- Consumes (Task 1): `RunControlStore.runSettingsOf(root)`, `.loadRunSettings(root)`, `.saveRunSettings(root, patch)`, `.applyRunSettings(root, settings)`, `signal runSettingsSaveFailed(var root, var patch)`, `.runSettingsRunners` (runners with `root`, `json`, `saving`, `current`), `.runSettingsLoadRunner`.
- Produces:
  - `RunDispatchStore`: `signal runSettingsWanted(var root)`, `signal runSettingsSaveRequested(var root, var patch)`, `function dispatchSaveFailed(root, patch)`; `runSettingsUpdated`, `mergedPrefixes`, `dispatchSaveReplied` and the start runner's `saving` are gone.
  - `RunStore`: `property var runSettings` (writable shim), `readonly property var runSettingsRunner` (shim).
  - Test helpers: `loadOf(d)` and `saveOf(d)` in `tst_run_dispatch_store.qml`; `saveOf(app)` in `tst_app_runs.qml`.

- [ ] **Step 1: Rewire the dispatch store tests**

Save as `/tmp/t2_dispatch_tests.py` and run `python3 /tmp/t2_dispatch_tests.py`.

```python
import re
p = "tests/core/stores/tst_run_dispatch_store.qml"
t = open(p).read()

def cut(t, old, new):
    assert t.count(old) == 1, old[:80]
    return t.replace(old, new)

def between(t, start, end, new):
    a = t.index(start)
    b = t.index(end, a)
    assert t.count(start) == 1 and t.count(end) == 1, (start[:60], end[:60])
    return t[:a] + new + t[b:]

# Header.
t = cut(t, r"""// The dispatch store: the dispatch state machine (open, the --defaults
// lookup, the debounced check and preview, Start on one runner per Start and
// that runner's settings write), the story target and retargetToMilestone,
// and the four signals it emits. Built alone, and wired to a RunStore and a
// RunControlStore the way App wires app.runDispatch, with stubbed Process
// objects standing in for every helper.""", r"""// The dispatch store: the dispatch state machine (open, the --defaults
// lookup, the debounced check and preview, Start on one runner per Start),
// the story target and retargetToMilestone, and the signals it emits,
// including the run settings it asks for and asks to save. Built alone, and
// wired to a RunStore and a RunControlStore the way App wires
// app.runDispatch, with stubbed Process objects standing in for every helper.""")

# The harness: make(), runsOf(), controlOf(), loadOf(), saveOf().
t = between(t, "  // Every {dispatch, runs, control} triple make() built.\n", "  // A root's registry entry", r"""  // Every {dispatch, runs, control} triple make() built.
  property var wired: []

  // A RunStore, a RunControlStore wired to it the way App wires
  // app.runControl, and a RunDispatchStore wired to both the way App wires
  // app.runDispatch: backendDir copied; project, active and runs bound to the
  // run store's own, runSettings to the control store's
  // runSettingsOf(project); refreshRequested to refresh() ("all") or
  // requestSnapshot(roots); noticeRequested to the control store's flash;
  // runSettingsWanted and runSettingsSaveRequested to its loadRunSettings and
  // saveRunSettings, and its runSettingsSaveFailed back to
  // dispatchSaveFailed. The run store's dispatchStore handle is not set.
  // Returns the dispatch store.
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
    d.runSettings = Qt.binding(function() { return c.runSettingsOf(store.project) })
    d.refreshRequested.connect(function(roots) {
      if (roots === "all") store.refresh()
      else store.requestSnapshot(roots)
    })
    d.noticeRequested.connect(function(text) { c.flash(text) })
    d.runSettingsWanted.connect(function(root) { c.loadRunSettings(root) })
    d.runSettingsSaveRequested.connect(function(root, patch) { c.saveRunSettings(root, patch) })
    c.runSettingsSaveFailed.connect(function(root, patch) { d.dispatchSaveFailed(root, patch) })
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

  // The paired control store's newest run settings load; null once it replied.
  function loadOf(d) { return controlOf(d).runSettingsLoadRunner }

  // The paired control store's newest run settings save in flight; null when none.
  function saveOf(d) {
    var saves = controlOf(d).runSettingsRunners.filter(function(r) { return r.saving })
    return saves.length > 0 ? saves[saves.length - 1] : null
  }

""")

# D-N3 .. D-N6 replaced, D-N7 and D-N8 added.
t = between(t, "  // D-N3 (A.3: the store's own project reaction)\n", "  // ---- dispatch (S3 3.1)\n", r"""  // D-N3 (A.3: the store's own project reaction)
  function test_its_own_project_change_resets_it_and_keeps_a_start_running() {
    var d = bareReady(); if (!d) return
    var started = spyC.createObject(tc, { target: d, signalName: "dispatchStarted" })
    var refresh = spyC.createObject(tc, { target: d, signalName: "refreshRequested" })
    var saves = spyC.createObject(tc, { target: d, signalName: "runSettingsSaveRequested" })
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
    compare(saves.count, 1, "the save is still asked for")
    compare(saves.signalArguments[0][0], tc.rootA, "recorded against A")
    compare(JSON.stringify(saves.signalArguments[0][1]), tc.savedJson)
    compare(d.dispatchStartRunners.length, 0)
  }

  // D-N4 (the coupling order of an ok start)
  function test_a_start_reply_emits_settings_then_refresh_then_started() {
    var d = bareReady(); if (!d) return
    var record = []
    var root = ""
    var patch = null
    var stateAtSettings = ""
    var stateAtStarted = ""
    d.runSettingsSaveRequested.connect(function(r, p) {
      record.push("settings")
      root = r
      patch = p
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
    compare(stateAtSettings, "starting", "the save is asked for before started")
    compare(stateAtStarted, "started")
    compare(root, tc.rootA)
    compare(patch.prefixHistory.join(","), "old")
    compare(patch.parallelism, 4)
    compare(patch.confirmDispatch, undefined, "the patch holds only what the start writes")
    compare(patch.prefixByMilestone.m1, "old")
    compare(d.dispatchStartRunners.length, 0)
  }

  // D-N5 (Review Focus 3 of 4.1)
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
    reply(d.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(d.dispatchState, "started")
    verify(d.runSettings === s, "the input is left as it was handed over")
    compare(d.runSettings.prefixByMilestone, undefined)
    compare(d.dispatchStartRunners.length, 0)
  }

  // bareReady() after an ok Start: `started`.
  function bareStarted() {
    var d = bareReady(); if (!d) return null
    compare(d.dispatchStart(), true)
    reply(d.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(d.dispatchState, "started")
    return d
  }

  // D-N6 (A.3: the notice) and Review Focus 5
  function test_a_failed_save_notices_only_while_it_is_this_dispatchs() {
    var d = bareStarted(); if (!d) return
    var notices = spyC.createObject(tc, { target: d, signalName: "noticeRequested" })
    d.dispatchSaveFailed(tc.rootA, JSON.parse(tc.savedJson))
    compare(notices.count, 1)
    compare(notices.signalArguments[0][0], "Dispatch settings could not be saved")
    d.dispatchSaveFailed(tc.rootA, JSON.parse(tc.savedJson))
    compare(notices.count, 1, "said once")

    var other = bareStarted(); if (!other) return
    var otherNotices = spyC.createObject(tc, { target: other, signalName: "noticeRequested" })
    other.dispatchSaveFailed(tc.rootA, { parallelism: 1 })
    other.dispatchSaveFailed(tc.rootB, JSON.parse(tc.savedJson))
    compare(otherNotices.count, 0, "another save's failure says nothing")

    var left = bareStarted(); if (!left) return
    var leftNotices = spyC.createObject(tc, { target: left, signalName: "noticeRequested" })
    left.project = tc.rootB
    left.dispatchSaveFailed(tc.rootA, JSON.parse(tc.savedJson))
    compare(leftNotices.count, 0, "no notice about A once the project changed")

    var closed = bareStarted(); if (!closed) return
    var closedNotices = spyC.createObject(tc, { target: closed, signalName: "noticeRequested" })
    compare(closed.closeDispatch(), true)
    closed.dispatchSaveFailed(tc.rootA, JSON.parse(tc.savedJson))
    compare(closedNotices.count, 0, "no notice once the dispatch was closed")
  }

  // D-N7 (the store's own project reaction asks for the run settings)
  function test_its_own_project_change_wants_the_run_settings() {
    var d = makeDispatch(); if (!d) return
    var wanted = spyC.createObject(tc, { target: d, signalName: "runSettingsWanted" })
    var states = []
    d.runSettingsWanted.connect(function(root) { states.push(d.dispatchState) })
    d.project = tc.rootA
    compare(wanted.count, 1)
    compare(wanted.signalArguments[0][0], tc.rootA)
    var cards = dispatchCards()
    compare(d.openDispatch(cards.m1, cards), true)
    compare(d.dispatchState, "previewing")
    d.project = tc.rootB
    compare(wanted.count, 2)
    compare(wanted.signalArguments[1][0], tc.rootB)
    d.project = ""
    compare(wanted.count, 2, "no project: nothing is wanted")
    compare(states.join(","), "idle,idle", "the store is reset before it asks")
  }

  // D-N8
  function test_a_start_launches_no_viewer_state_and_a_failed_start_saves_nothing() {
    var d = bareReady(); if (!d) return
    var saves = spyC.createObject(tc, { target: d, signalName: "runSettingsSaveRequested" })
    compare(d.dispatchStart(), true)
    var proc = d.dispatchStartRunners[0].current
    compare(argv(proc).indexOf("viewer-state.py"), -1)
    reply(proc, startOk("r-1", ""), 0)
    compare(d.dispatchStartRunners.length, 0, "no runner is left to write the settings")
    compare(saves.count, 1, "the save is only asked for")
    var replies = [ctlFail("AmExited", "am run exited at once (exit 2)"), startBlocked()]
    for (var i = 0; i < replies.length; i++) {
      var failed = bareReady(); if (!failed) return
      var none = spyC.createObject(tc, { target: failed, signalName: "runSettingsSaveRequested" })
      compare(failed.dispatchStart(), true)
      reply(failed.dispatchStartRunners[0].current, replies[i], 0)
      compare(none.count, 0, "reply " + i + ": nothing saved")
      compare(failed.dispatchStartRunners.length, 0, "reply " + i)
    }
  }
""")

# Moved bodies: the start runner no longer writes the settings (difference 3).
t = cut(t, r"""    compare(store.dispatchStartRunners.length, 1, "the same runner writes the settings")
    verify(store.dispatchStartRunners[0] === runner)
    var save = runner.current
""", r"""    compare(store.dispatchStartRunners.length, 0, "the start runner goes at its reply")
    verify(saveOf(store), "run control writes the settings")
    var save = saveOf(store).current
""")
t = cut(t, r"""    compare(store.dispatchStartRunners.length, 0, "the runner goes after the write")
""", r"""    compare(store.dispatchStartRunners.length, 0, "the runner goes after the write")
    compare(controlOf(store).runSettingsRunners.length, 0, "and so does the save's")
""")
t = cut(t, "    var saved = JSON.parse(runner.current.command[4])\n",
        "    var saved = JSON.parse(saveOf(store).current.command[4])\n")
t = cut(t, "    compare(argv(bareRunner.current), tc.viewerCmd +\n",
        "    compare(argv(saveOf(bare).current), tc.viewerCmd +\n")
t = cut(t, "      reply(runner.current, replies[i], 1)\n",
        "      reply(saveOf(store).current, replies[i], 1)\n")
t = cut(t, r"""    compare(argv(runner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson, "recorded against A")
    reply(runner.current, "garbage\n", 1)
""", r"""    compare(argv(saveOf(store).current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson, "recorded against A")
    reply(saveOf(store).current, "garbage\n", 1)
""")
t = cut(t, r"""    compare(argv(runner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson, "still recorded for A")
""", r"""    compare(argv(saveOf(store).current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson, "still recorded for A")
""")
t = cut(t, "    compare(argv(runner.current), tc.viewerCmd + \"set-run-settings|/home/u/my proj|\" +\n",
        "    compare(argv(saveOf(store).current), tc.viewerCmd + \"set-run-settings|/home/u/my proj|\" +\n")
t = cut(t, "    compare(runner.current.command[4], tc.savedJson, \"a milestone start keys its own id\")\n",
        "    compare(saveOf(store).current.command[4], tc.savedJson, \"a milestone start keys its own id\")\n")
t = cut(t, "    compare(argv(subtaskRunner.current), tc.viewerCmd +",
        "    compare(argv(saveOf(subtask).current), tc.viewerCmd +")
t = cut(t, "    compare(argv(boardRunner.current), tc.viewerCmd +",
        "    compare(argv(saveOf(board).current), tc.viewerCmd +")

# Moved bodies: the load is run control's.
t, n = re.subn(r"runsOf\((\w+)\)\.runSettingsRunner\.current", r"loadOf(\1).current", t)
assert n == 14, n

assert not re.search(r"runSettingsRunner\b", t)  # runSettingsRunners (plural) stays
assert "runSettingsUpdated" not in t
open(p, "w").write(t)
```

- [ ] **Step 2: Rewire the run store tests, delete the moved loader tests, add R-S1 … R-S3**

Save as `/tmp/t2_runstore_tests.py` and run `python3 /tmp/t2_runstore_tests.py`.

```python
p = "tests/core/stores/tst_run_store.qml"
t = open(p).read()

def cut(t, old, new):
    assert t.count(old) == 1, old[:80]
    return t.replace(old, new)

t = cut(t, r"""// tst_run_control_store.qml, the alerts in tst_run_alerts_store.qml. The
// dispatch is tested in tst_run_dispatch_store.qml.""", r"""// tst_run_control_store.qml, the alerts in tst_run_alerts_store.qml. The
// dispatch is tested in tst_run_dispatch_store.qml, the run settings load
// and save in tst_run_control_store.qml.""")

# RunStore no longer loads: A-S3 pins the load at App level.
t = cut(t, r"""    store.project = tc.rootB
    compare(argv(store.runSettingsRunner.current), tc.viewerCmd + "get-run-settings|" + tc.rootB,
            "the new project's run settings still load")
""", r"""    store.project = tc.rootB
""")

# The loader tests and their helpers move to tst_run_control_store.qml (C-S2, C-S3, C-S10).
a = t.index("  // ---- alerts: the setting and the desktop notifications (S2 4.4)\n")
b = t.index("  // ---- list snapshots\n")
assert "test_run_settings_follow_the_project" in t[a:b]
t = t[:a] + t[b:]

# wireDispatch: wired the way App now wires app.runDispatch.
t = cut(t, r"""  // A RunDispatchStore with backendDir copied, set as `store`'s dispatchStore
  // handle. When `bound`, it is wired the way App wires app.runDispatch:
  // project, active, runs and runSettings bound to the run store's own;
  // refreshRequested to refresh() ("all") or requestSnapshot(roots);
  // noticeRequested to the paired control store's flash; runSettingsUpdated
  // into the run store's runSettings. Otherwise nothing is bound or routed.""", r"""  // A RunDispatchStore with backendDir copied, set as `store`'s dispatchStore
  // handle. When `bound`, it is wired the way App wires app.runDispatch:
  // project, active and runs bound to the run store's own, runSettings to the
  // paired control store's runSettingsOf(project); refreshRequested to
  // refresh() ("all") or requestSnapshot(roots); noticeRequested to the
  // paired control store's flash; runSettingsWanted and
  // runSettingsSaveRequested to its loadRunSettings and saveRunSettings, and
  // its runSettingsSaveFailed back to dispatchSaveFailed. Otherwise nothing
  // is bound or routed.""")
t = cut(t, "      d.runSettings = Qt.binding(function() { return store.runSettings })\n",
        "      d.runSettings = Qt.binding(function() { return controlOf(store).runSettingsOf(store.project) })\n")
t = cut(t, "      d.runSettingsUpdated.connect(function(settings) { store.runSettings = settings })\n", r"""      var c = controlOf(store)
      d.runSettingsWanted.connect(function(root) { c.loadRunSettings(root) })
      d.runSettingsSaveRequested.connect(function(root, patch) { c.saveRunSettings(root, patch) })
      c.runSettingsSaveFailed.connect(function(root, patch) { d.dispatchSaveFailed(root, patch) })
""")

assert t.endswith("  }\n}\n")
t = t[:-2] + r"""
  // ---- the run settings shims (split-runstore 4.2)

  // R-S1 and Review Focus 1
  function test_without_a_control_store_the_run_settings_shims_are_empty() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var store = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    compare(Object.keys(store.runSettings).length, 0)
    compare(store.runSettingsRunner, null)
    store.project = tc.rootA
    store.project = tc.rootB
    compare(Object.keys(store.runSettings).length, 0)
    compare(store.runSettingsRunner, null, "nothing is loaded")
    var w = { verify: ["make check"] }
    store.runSettings = w
    verify(store.runSettings === w, "a write is kept as written")
  }

  // R-S2
  function test_the_run_settings_shims_follow_the_control_store() {
    var store = makeWithProject(rootA); if (!store) return
    var c = controlOf(store)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "runSettingsChanged" })
    compare(c.runSettingsRunners.length, 0, "the run store loads nothing on a project change")
    compare(store.runSettingsRunner, null)
    c.loadRunSettings(tc.rootA)
    verify(store.runSettingsRunner === c.runSettingsLoadRunner)
    reply(store.runSettingsRunner.current, JSON.stringify({ parallelism: 4 }) + "\n", 0)
    verify(store.runSettings === c.runSettingsOf(tc.rootA))
    compare(store.runSettings.parallelism, 4)
    store.project = tc.rootB
    compare(Object.keys(store.runSettings).length, 0)
    verify(spy.count >= 1, "the shim notifies")
  }

  // R-S3 and Review Focus 1, 2
  function test_writing_the_run_settings_shim_reaches_the_control_store() {
    failOnWarning(/Binding loop/)
    var store = makeWithProject(rootA); if (!store) return
    var c = controlOf(store)
    var w = { verify: ["make check"] }
    store.runSettings = w
    verify(c.runSettingsOf(tc.rootA) === w, "the write goes to the control store")
    verify(store.runSettings === w)
    c.loadRunSettings(tc.rootA)
    reply(c.runSettingsLoadRunner.current, JSON.stringify({ parallelism: 9 }) + "\n", 0)
    compare(store.runSettings.parallelism, 9, "the shim follows the control store again")
  }
}
"""
assert "runSettingsUpdated" not in t
open(p, "w").write(t)
```

- [ ] **Step 3: Add C-S10 to the control store tests**

Save as `/tmp/t2_control_tests.py` and run `python3 /tmp/t2_control_tests.py`.

```python
p = "tests/core/stores/tst_run_control_store.qml"
t = open(p).read()
assert t.endswith("  }\n}\n")
t = t[:-2] + r"""
  // C-S10 (moved from tst_run_store.qml)
  function test_run_settings_kept_even_after_notify_touched() {
    var store = makeWithProject(rootA); if (!store) return
    var c = controlOf(store)
    c.loadRunSettings(tc.rootA)
    compare(Object.keys(store.runSettings).length, 0, "{} until the reply")
    var load = c.runSettingsLoadRunner.current
    store.setNotifyOnEscalation(true)
    reply(load, dispatchSettings(), 0)
    compare(store.notifyOnEscalation, true, "the switch keeps the user's value")
    compare(store.runSettings.prefixHistory.length, 1)
    compare(store.runSettings.prefixHistory[0], "old")
    compare(store.runSettings.parallelism, 4)
    compare(store.runSettings.confirmDispatch, true)
    compare(store.runSettings.verify[0], "uv run pytest")
    compare(store.runSettings.notifyOnEscalation, false, "the object is kept as it was read")
  }
}
"""
open(p, "w").write(t)
```

- [ ] **Step 4: Update the App wiring tests and add A-S1 … A-S5**

Save as `/tmp/t2_app_tests.py` and run `python3 /tmp/t2_app_tests.py`.

```python
p = "tests/core/stores/tst_app_runs.qml"
t = open(p).read()

def cut(t, old, new):
    assert t.count(old) == 1, old[:80]
    return t.replace(old, new)

t = cut(t, r"""// store, and `app.runDispatch`, which App feeds with the run store's project,
// run list and run settings and whose refreshRequested, noticeRequested and
// runSettingsUpdated App routes. The stores' own behaviour is tested in""", r"""// store, and `app.runDispatch`, which App feeds with the run store's project
// and run list and run control's run settings, and whose refreshRequested,
// noticeRequested, runSettingsWanted and runSettingsSaveRequested App routes,
// as it routes run control's runSettingsSaveFailed back to the dispatch. The
// stores' own behaviour is tested in""")

# The save helper, after readyApp().
t = cut(t, "  // The argv prefix of a notify.py command.\n", r"""  // run control's newest run settings save in flight; null when none.
  function saveOf(app) {
    var saves = app.runControl.runSettingsRunners.filter(function(r) { return r.saving })
    return saves.length > 0 ? saves[saves.length - 1] : null
  }

  // The argv prefix of a notify.py command.
""")

# The save is run control's (difference 3): the expectations stay.
t = cut(t, "    var save = runner.current\n", "    var save = saveOf(app).current\n")
t = cut(t, r"""    reply(runner.current, ctlFail("Invalid", "x"), 1)
    compare(app.runs.flashText, "Dispatch settings could not be saved")""", r"""    reply(saveOf(app).current, ctlFail("Invalid", "x"), 1)
    compare(app.runs.flashText, "Dispatch settings could not be saved")""")
t = cut(t, r"""    reply(runner.current, ctlFail("Invalid", "x"), 1)
    compare(app.runControl.flashText, "Dispatch settings could not be saved")""", r"""    reply(saveOf(app).current, ctlFail("Invalid", "x"), 1)
    compare(app.runControl.flashText, "Dispatch settings could not be saved")""")

assert t.endswith("  }\n}\n")
t = t[:-2] + r"""
  // A-S1
  function test_the_dispatch_reads_its_run_settings_from_run_control() {
    var app = make(); if (!app) return
    var load = app.runControl.runSettingsLoadRunner
    verify(load, "selecting a project asks run control for its run settings")
    compare(argv(load.current), tc.viewerCmd + "get-run-settings|/home/u/my proj")
    reply(load.current, dispatchSettings(), 0)
    verify(app.runDispatch.runSettings === app.runControl.runSettingsOf("/home/u/my proj"))
    verify(app.runDispatch.runSettings === app.runs.runSettings, "the run store's shim reads the same object")
    compare(app.runDispatch.runSettings.parallelism, 4)
  }

  // A-S2
  function test_a_start_through_app_saves_through_run_control() {
    var app = readyApp(); if (!app) return
    compare(app.runControl.runSettingsRunners.length, 0, "the load has replied")
    compare(app.runDispatch.dispatchStart(), true)
    reply(app.runDispatch.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(app.runControl.runSettingsRunners.length, 1, "exactly one save")
    var save = saveOf(app)
    verify(save)
    compare(argv(save.current).indexOf(tc.viewerCmd + "set-run-settings|/home/u/my proj|"), 0)
    compare(app.runControl.runSettingsOf("/home/u/my proj").prefixByMilestone.m1, "old")
    verify(app.runDispatch.runSettings === app.runControl.runSettingsOf("/home/u/my proj"))
    compare(app.runDispatch.dispatchStartRunners.length, 0)
  }

  // A-S3 and Review Focus 3
  function test_a_project_switch_through_app_loads_each_projects_settings_apart() {
    var app = make(); if (!app) return
    var loadA = app.runControl.runSettingsLoadRunner
    app.projects.chooseProject(pB)
    compare(app.runControl.runSettingsRunners.length, 2, "A's load is not stopped")
    var loadB = app.runControl.runSettingsLoadRunner
    compare(argv(loadB.current), tc.viewerCmd + "get-run-settings|/home/u/b")
    reply(loadA.current, dispatchSettings(), 0)
    compare(Object.keys(app.runDispatch.runSettings).length, 0, "A's late reply is A's")
    compare(app.runControl.runSettingsOf("/home/u/my proj").parallelism, 4)
    reply(loadB.current, JSON.stringify({ parallelism: 9 }) + "\n", 0)
    compare(app.runDispatch.runSettings.parallelism, 9)
    app.projects.chooseProject(pA)
    compare(Object.keys(app.runDispatch.runSettings).length, 0, "A's old entry is not shown before its reply")
    reply(app.runControl.runSettingsLoadRunner.current, JSON.stringify({ parallelism: 6 }) + "\n", 0)
    compare(app.runDispatch.runSettings.parallelism, 6)
  }

  // A-S4 and Review Focus 1, 2
  function test_a_write_to_the_run_store_shim_reaches_the_dispatch_form() {
    failOnWarning(/Binding loop/)
    var app = make(); if (!app) return
    app.runs.runSettingsRunner.cancel()
    app.runs.runSettings = { verify: ["make check"] }
    verify(app.runDispatch.runSettings === app.runs.runSettings)
    var cards = dispatchCards()
    compare(app.runDispatch.openDispatch(cards.m1, cards), true)
    compare(app.runDispatch.dispatchForm.verify[0], "make check")
  }

  // A-S5 and Review Focus 5
  function test_a_save_failure_after_switching_away_flashes_nothing() {
    var app = readyApp(); if (!app) return
    compare(app.runDispatch.dispatchStart(), true)
    reply(app.runDispatch.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    var save = saveOf(app)
    verify(save)
    app.projects.chooseProject(pB)
    reply(save.current, ctlFail("Invalid", "x"), 1)
    compare(app.runControl.flashText, "")
  }
}
"""
open(p, "w").write(t)
```

- [ ] **Step 5: Run the tests to verify they fail**

Run: `timeout 900 bash tests/run.sh tests/core/stores/tst_`
Expected: FAIL — `tst_run_dispatch_store.qml` (e.g. `TypeError: Cannot call method 'connect' of undefined` from `d.runSettingsWanted.connect`), `tst_run_store.qml` (R-S2: `the run store loads nothing on a project change`; `wireDispatch` `connect of undefined`), `tst_app_runs.qml` (A-S1: `verify(load)` fails; `saveOf(app)` is `null`), `tst_run_control_store.qml` (C-S10: `store.runSettings` is the RunStore's own `{}`, not the control store's entry).

- [ ] **Step 6: `RunDispatchStore` asks instead of writing**

Save as `/tmp/t2_dispatch.py` and run `python3 /tmp/t2_dispatch.py`.

```python
p = "core/stores/RunDispatchStore.qml"
t = open(p).read()

def cut(t, old, new):
    assert t.count(old) == 1, old[:80]
    return t.replace(old, new)

def between(t, start, end, new):
    assert t.count(start) == 1 and t.count(end) == 1, (start[:60], end[:60])
    a = t.index(start)
    b = t.index(end, a)
    return t[:a] + new + t[b:]

# Header.
t = between(t, "// Dispatch (S3 3.1): starting an am run.", "Scope {\n", r"""// Dispatch (S3 3.1): starting an am run. The UI opens it for a target
// (openDispatch), edits the form (setDispatchField) and presses Start
// (dispatchStart); the store checks the form, previews it with
// dispatch-preview.py and starts it with start-run.py, one HelperRunner per
// Start. `dispatchState` is idle | previewing | ready | refused | starting |
// started | failed. Every object here is replaced, never changed in place.
// The backend directory, the open project's root, the panel-open flag, the
// run list and the open project's run settings are handed to it from
// outside -- it never reaches for another store. It never reads or writes
// the run settings itself: it asks for the open project's run settings
// (runSettingsWanted) on each project change and for an ok start's values to
// be saved (runSettingsSaveRequested, for the project the start was made
// in), reads runSettings as handed in, and says a failed save of this
// dispatch's start (dispatchSaveFailed) as a notice. It also asks for a
// re-snapshot (refreshRequested) and a footer sentence (noticeRequested), and
// announces a start (dispatchStarted). A project change resets it; closing
// the panel closes it unless a start is in flight. App composes it as
// `app.runDispatch`.
""")

# The two run settings signals.
t = cut(t, r"""  // After an ok start of this dispatch: the open project's run settings as
  // that start saves them (prefixByMilestone merged per milestone id).
  signal runSettingsUpdated(var settings)
""", r"""  // This project's run settings are wanted: `root` is the open project.
  signal runSettingsWanted(var root)
  // An ok start's values are to be saved for the project it was made in.
  signal runSettingsSaveRequested(var root, var patch)
""")

# The project reaction asks for the new project's run settings.
t = cut(t, r"""  // The dispatch is the old project's, even mid-start: a start already
  // launched still runs, and its reply is no longer this dispatch's.
  onProjectChanged: dispatch.resetDispatch()
""", r"""  // The dispatch is the old project's, even mid-start: a start already
  // launched still runs, and its reply is no longer this dispatch's. Then
  // the new project's run settings are wanted (none for no project).
  onProjectChanged: {
    dispatch.resetDispatch()
    if (dispatch.project !== "") dispatch.runSettingsWanted(dispatch.project)
  }
""")

# A reset forgets the save it watches.
t = cut(t, r"""  // pending check, the preview and the defaults lookup are dropped; a start
  // already launched runs on, but its reply is no longer this dispatch's.
  function resetDispatch() {
    dispatchDebounceTimer.stop()
    dispatchPreviewRunner.cancel()
    dispatchDefaultsRunner.cancel()
    dispatchBook.startRunner = null
""", r"""  // pending check, the preview and the defaults lookup are dropped; a start
  // already launched runs on, but its reply, and its save's failure, are no
  // longer this dispatch's.
  function resetDispatch() {
    dispatchDebounceTimer.stop()
    dispatchPreviewRunner.cancel()
    dispatchDefaultsRunner.cancel()
    dispatchBook.startRunner = null
    dispatchBook.savingFor = null
""")

# mergedPrefixes is RunControlStore's.
t = cut(t, r"""  // A fresh {milestone id: prefix} map: stored's own entries when stored is
  // an object that is not an array, then entry's, which override them, as
  // set-run-settings merges prefixByMilestone.
  function mergedPrefixes(stored, entry) {
    var merged = stored !== null && typeof stored === "object" && !Array.isArray(stored) ? Runs.copyMap(stored) : {}
    for (var id in entry) merged[id] = entry[id]
    return merged
  }

""", "")

# The start reply asks for the save; dispatchSaveFailed replaces dispatchSaveReplied.
t = between(t, "  // start-run.py's reply. When it is this dispatch's:", "  // A start runner's work is over:", r"""  // start-run.py's reply; the runner then goes. Any ok start, wherever it
  // was made, asks for its saved values to be saved for the project it was
  // made in (runSettingsSaveRequested). When it is this dispatch's: ok gives
  // the run id and message, that save request (watched by
  // dispatchSaveFailed), `started`, a re-snapshot of every root
  // (refreshRequested("all")) and dispatchStarted(id or null); a
  // StoryBlockedError gives `refused` with am's message, no log fields and
  // the blockedSuggest() milestone; anything else gives `failed` with what
  // the helper said. A start that is not ok asks for no save.
  function dispatchStartReplied(runner, stdout) {
    var here = dispatch.isHereStart(runner)
    var envelope = Results.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      // Parsed from the JSON that is written: a var property hands back a
      // list Runs.dispatchDefaults does not take for an array.
      var patch = JSON.parse(runner.savedJson)
      if (here) {
        dispatch.dispatchRunId = typeof envelope.run_id === "string" ? envelope.run_id : ""
        dispatch.dispatchMessage = typeof envelope.message === "string" ? envelope.message : ""
        dispatchBook.savingFor = { root: runner.madeFor, json: runner.savedJson }
        dispatch.runSettingsSaveRequested(runner.madeFor, patch)
        dispatch.dispatchState = "started"
        dispatch.refreshRequested("all")
        dispatch.dispatchStarted(dispatch.dispatchRunId !== "" ? dispatch.dispatchRunId : null)
      } else {
        dispatch.runSettingsSaveRequested(runner.madeFor, patch)
      }
    } else if (here) {
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

  // A save of `patch` for `root` failed (App routes run control's
  // runSettingsSaveFailed here): one notice, only when it is the save of this
  // dispatch's ok start -- the open project, the same values -- and only
  // once. A reset forgets that save.
  function dispatchSaveFailed(root, patch) {
    var saving = dispatchBook.savingFor
    if (saving === null || saving.root !== root || root !== dispatch.project || saving.json !== JSON.stringify(patch)) return
    dispatchBook.savingFor = null
    dispatch.noticeRequested("Dispatch settings could not be saved")
  }

""")

# The bookkeeping: the watched save.
t = cut(t, r"""  // and its entry for the target's milestone card (null when unknown).
  QtObject {
    id: dispatchBook
    property var runners: []
    property var startRunner: null
""", r"""  // and its entry for the target's milestone card (null when unknown);
  // `savingFor` is {root, json} of this dispatch's ok start's save until its
  // failure is said or a reset, else null.
  QtObject {
    id: dispatchBook
    property var runners: []
    property var startRunner: null
    property var savingFor: null
""")

# The per-Start runner: no second life (from its comment to the end of the file).
a = t.index("  // One HelperRunner per Start. Guard \"\":")
t = t[:a] + r"""  // One HelperRunner per Start. Guard "": start-run.py may take ~20 s, and
  // neither a preview, a project switch nor a Start in another project may
  // stop it. It goes when its start replies.
  Component {
    id: dispatchStartC

    HelperRunner {
      id: sr
      property string madeFor: ""     // the project the start was made in
      property string savedJson: ""   // `saved` as set-run-settings takes it
      script: dispatch.backendDir + "runs/start-run.py"
      guard: ""
      onFinished: function(stdout, exitCode) { dispatch.dispatchStartReplied(sr, stdout) }
    }
  }
}
"""

for gone in ("viewer-state.py", "runSettingsUpdated", "mergedPrefixes", "dispatchSaveReplied", "saving: false", "runner.saving"):
    assert gone not in t, gone
open(p, "w").write(t)
```

- [ ] **Step 7: `RunStore` drops its loader and keeps shims**

Save as `/tmp/t2_runstore.py` and run `python3 /tmp/t2_runstore.py`.

```python
p = "core/stores/RunStore.qml"
t = open(p).read()

def cut(t, old, new=""):
    assert t.count(old) == 1, old[:80]
    return t.replace(old, new)

# Header.
t = cut(t, r"""// switch leaves the run list alone: `project`, the open project, decides only
// the run settings; the attempt logs act on each run's own project
// root.""", r"""// switch leaves the run list alone: `project`, the open project, is read only
// by the run settings shims; the attempt logs act on each run's own project
// root.""")

# The shims, at the end of the run control shims.
t = cut(t, "  function setNotifyOnEscalation(on) { return store.controlStore ? store.controlStore.setNotifyOnEscalation(on) : undefined }\n", r"""  function setNotifyOnEscalation(on) { return store.controlStore ? store.controlStore.setNotifyOnEscalation(on) : undefined }
  property var runSettings: ({})
  Binding { target: store; property: "runSettings"; value: store.controlStore ? store.controlStore.runSettingsOf(store.project) : ({}) }
  onRunSettingsChanged: {
    if (!store.controlStore || store.runSettings === store.controlStore.runSettingsOf(store.project)) return
    store.controlStore.applyRunSettings(store.project, store.runSettings)
  }
  readonly property var runSettingsRunner: store.controlStore ? store.controlStore.runSettingsLoadRunner : null
""")

# The old property, its alias, the project reaction, the reply handler and the runner.
t = cut(t, r"""  // The open project's last get-run-settings object (runSettingsRunner), as
  // it was read: {} until its reply, when the reply is unreadable, and after
  // a project switch. The dispatch form starts from it; its
  // notifyOnEscalation is never read.
  property var runSettings: ({})

""")
t = cut(t, "  readonly property alias runSettingsRunner: runSettingsRunner\n")
t = cut(t, r"""  // Another project was opened, or none. The run list, the selection, the
  // logs, the watch, the coverage and the notify switch belong to every
  // registered project and stay, and no snapshot is launched. Reset: the run settings
  // (loaded for the new project on runSettingsRunner).
  function projectSwitched() {
    store.runSettings = {}
    runSettingsRunner.guard = store.project
    if (store.project !== "") runSettingsRunner.run(["get-run-settings", store.project])
  }

  onProjectChanged: store.projectSwitched()

""")
t = cut(t, r"""  // get-run-settings: one bare object, kept whole as runSettings ({} when
  // unreadable) on every reply. Never touches the notify switch.
  function applyRunSettings(stdout, exitCode) {
    var settings = Results.parseEnvelope(stdout)
    store.runSettings = settings !== null ? settings : {}
  }

""")
t = cut(t, r"""  // get-run-settings on a project switch, for runSettings only. Its guard is
  // set by projectSwitched() itself rather than bound to `project`:
  // projectSwitched() runs from onProjectChanged, before a binding here is
  // sure to have followed the project, and this launch must carry the NEW
  // project.
  HelperRunner {
    id: runSettingsRunner
    script: store.backendDir + "projects/viewer-state.py"
    onFinished: function(stdout, exitCode) { store.applyRunSettings(stdout, exitCode) }
  }

""")

for gone in ("viewer-state.py", "projectSwitched", "id: runSettingsRunner"):
    assert gone not in t, gone
open(p, "w").write(t)
```

- [ ] **Step 8: App routes the run settings**

Save as `/tmp/t2_app.py` and run `python3 /tmp/t2_app.py`.

```python
p = "core/stores/App.qml"
t = open(p).read()

def cut(t, old, new):
    assert t.count(old) == 1, old[:80]
    return t.replace(old, new)

t = cut(t, r"""  // The run controls never import the run store: App hands them the backend
  // directory, the open project's root, the panel-open flag and the run list,
  // settles their requests on each ok snapshot reply and routes their
  // refreshRequested to the run store.
  readonly property RunControlStore runControl: RunControlStore {
    backendDir: app.backendDir
    project: app.runs.project
    active: app.panelOpen
    runs: app.runs.runs
    onRefreshRequested: function(roots) {
      if (roots === "all") app.runs.refresh()
      else app.runs.requestSnapshot(roots)
    }
  }""", r"""  // The run controls never import the run store: App hands them the backend
  // directory, the open project's root, the panel-open flag and the run list,
  // settles their requests on each ok snapshot reply, routes their
  // refreshRequested to the run store and their runSettingsSaveFailed to the
  // dispatch's dispatchSaveFailed.
  readonly property RunControlStore runControl: RunControlStore {
    backendDir: app.backendDir
    project: app.runs.project
    active: app.panelOpen
    runs: app.runs.runs
    onRefreshRequested: function(roots) {
      if (roots === "all") app.runs.refresh()
      else app.runs.requestSnapshot(roots)
    }
    onRunSettingsSaveFailed: function(root, patch) { app.runDispatch.dispatchSaveFailed(root, patch) }
  }""")

t = cut(t, r"""  // The dispatch never imports the run store: App hands it the backend
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
  }""", r"""  // The dispatch never imports the run store or run control: App hands it the
  // backend directory, the open project's root, the panel-open flag, the run
  // list and the open project's run settings from run control, routes its
  // refreshRequested to the run store, its noticeRequested to run control's
  // flash, and its runSettingsWanted and runSettingsSaveRequested to run
  // control's loadRunSettings and saveRunSettings.
  readonly property RunDispatchStore runDispatch: RunDispatchStore {
    backendDir: app.backendDir
    project: app.runs.project
    active: app.panelOpen
    runs: app.runs.runs
    runSettings: app.runControl.runSettingsOf(app.runs.project)
    onRefreshRequested: function(roots) {
      if (roots === "all") app.runs.refresh()
      else app.runs.requestSnapshot(roots)
    }
    onNoticeRequested: function(text) { app.runControl.flash(text) }
    onRunSettingsWanted: function(root) { app.runControl.loadRunSettings(root) }
    onRunSettingsSaveRequested: function(root, patch) { app.runControl.saveRunSettings(root, patch) }
  }""")
open(p, "w").write(t)
```

- [ ] **Step 9: Run the full gate**

Run: `timeout 900 bash tests/run.sh; echo "exit $?"`
Expected: pytest passes (architecture included); every `== tests/...qml` block shows `Totals: N passed, 0 failed` — including all of `tests/ui/` — with no `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign` or `is not a function` lines; `exit 0`.

Then:

Run: `git diff --stat d7e0fc9 -- ui tests/ui`
Expected: no output.

Run: `grep -rn "viewer-state.py" core/stores/RunDispatchStore.qml core/stores/RunStore.qml; grep -rn "runSettingsUpdated\|projectSwitched\|dispatchSaveReplied" core tests`
Expected: no output.

If a ui test fails with `TypeError: Cannot call method 'cancel' of null`, a load replied before the test cancelled it; check that `App.qml`'s `runDispatch` routes `onRunSettingsWanted` and that `RunStore.runSettingsRunner` reads `runSettingsLoadRunner` (Notes on the spec, 3).

- [ ] **Step 10: Commit**

```bash
git add core/stores/RunDispatchStore.qml core/stores/RunStore.qml core/stores/App.qml \
        tests/core/stores/tst_run_dispatch_store.qml tests/core/stores/tst_run_store.qml \
        tests/core/stores/tst_run_control_store.qml tests/core/stores/tst_app_runs.qml
git commit -m "refactor(runs): the dispatch asks RunControlStore for its run settings, App routes them, RunStore keeps shims"
```

---

### Task 3: Docs — only the sentences this card makes false

**Files:**
- Modify: `docs/architecture.md` (lines 83, 91, 92, 93)

**Interfaces:**
- Consumes: the member names of Tasks 1 and 2, exactly as listed in their Interfaces blocks.
- Produces: nothing code reads.

- [ ] **Step 1: Check that every sentence to replace is there once (the "failing test")**

Run:
```bash
for s in 'A project switch leaves the run list alone: `project` decides only `runSettings`.' 'read on `runSettingsRunner` by every project switch (guarded by the new project)' '`runSettingsUpdated` carrying it merged per milestone id at once'; do grep -cF -- "$s" docs/architecture.md; done
```
Expected: `1` three times (these are the false sentences).

- [ ] **Step 2: Edit**

Save as `/tmp/t3_docs.py` and run `python3 /tmp/t3_docs.py`.

```python
p = "docs/architecture.md"
t = open(p).read()

def cut(t, old, new):
    assert t.count(old) == 1, old[:80]
    return t.replace(old, new)

# RunStore (line 83).
t = cut(t, "A project switch leaves the run list alone: `project` decides only `runSettings`.",
        "A project switch leaves the run list alone: `project` is read only by the run settings shims.")

# The run control shims (line 91).
t = cut(t, "`settingsLoadRunner`, `settingsSaveRunner` and `setNotifyOnEscalation` as shims through `controlStore`",
        "`settingsLoadRunner`, `settingsSaveRunner`, `setNotifyOnEscalation`, `runSettings` and `runSettingsRunner` as shims through `controlStore`")
t = cut(t, "`cancelText` and `cancelRunId` are writable (a write goes to the control store, and the shim then follows it again)",
        "`cancelText`, `cancelRunId` and `runSettings` are writable (a write goes to the control store -- `runSettings` through `applyRunSettings(project, value)` -- and the shim then follows it again); `runSettings` is the control store's `runSettingsOf(project)` and `runSettingsRunner` its `runSettingsLoadRunner`, the newest load")

# The dispatch paragraph (line 92).
t = cut(t, "App hands it `backendDir`, `project`, `active`, `runs` and `runSettings`, and routes `refreshRequested` to the run store, `noticeRequested` to `app.runControl.flash` and `runSettingsUpdated` into `app.runs.runSettings`.",
        "App hands it `backendDir`, `project`, `active`, `runs` and `runSettings` (`app.runControl.runSettingsOf(project)`), and routes `refreshRequested` to the run store, `noticeRequested` to `app.runControl.flash`, `runSettingsWanted` / `runSettingsSaveRequested` to `app.runControl.loadRunSettings` / `saveRunSettings`, and run control's `runSettingsSaveFailed` back to `dispatchSaveFailed`. It launches no `viewer-state.py`.")
t = cut(t, "read on `runSettingsRunner` by every project switch (guarded by the new project)",
        "asked for on every project change (`runSettingsWanted`)")
t = cut(t, "After any successful start the same runner writes `set-run-settings` for the project it was made in",
        "After any successful start the dispatch asks run control to save (`runSettingsSaveRequested`, which runs `set-run-settings`) for the project it was made in")
t = cut(t, "`runSettingsUpdated` carrying it merged per milestone id at once",
        "merged per milestone id at once by run control")
t = cut(t, "when that fails while the dispatch is still that start's.",
        "when that fails while the dispatch is still that start's (`dispatchSaveFailed`; a reset forgets it).")

# RunControlStore (line 93).
t = cut(t, "App binds `app.runAlerts.notifyOnEscalation` to it.",
        "App binds `app.runAlerts.notifyOnEscalation` to it. Each project's run settings are here too: `runSettings` (`{root: settings}`, replaced, never changed in place) holds each root's last `get-run-settings` object as read, with the saves since merged in, and `runSettingsOf(root)` reads one entry (one shared empty object when there is none). `loadRunSettings(root)` drops the root's entry until its reply and runs `viewer-state.py get-run-settings ROOT` on a `HelperRunner` of its own (`runSettingsRunners`; the newest load is `runSettingsLoadRunner` until it replies; no guard), whose reply is applied to that root whatever project is open (`{}` when unreadable; its `notifyOnEscalation` never touches the switch). `saveRunSettings(root, patch)` merges `patch` over the root's entry at once through `applyRunSettings` (`prefixByMilestone` per milestone id, as `set-run-settings` merges it), then runs `set-run-settings ROOT JSON` on a runner of its own; a reply other than `{\"ok\": true}` emits `runSettingsSaveFailed(root, patch)` and undoes nothing. Root `\"\"` launches nothing. No run settings request stops another, the notify switch's load or save, or a resume's settings step. App routes the dispatch's `runSettingsWanted` / `runSettingsSaveRequested` here and `runSettingsSaveFailed` back to the dispatch.")

for gone in ("runSettingsUpdated", "decides only `runSettings`", "read on `runSettingsRunner`"):
    assert gone not in t, gone
open(p, "w").write(t)
```

- [ ] **Step 3: Verify**

Run:
```bash
grep -c "runSettingsUpdated\|projectSwitched\|runSettingsRunner\` by every" docs/architecture.md; grep -c "loadRunSettings" docs/architecture.md
```
Expected: `0`, then a number of at least `2`.

Run: `timeout 900 bash tests/run.sh tst_app_runs; echo "exit $?"`
Expected: `exit 0` (pytest, which reads no prose but guards the repo layout, still passes).

- [ ] **Step 4: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): run settings are RunControlStore's, the dispatch asks for them"
```

---

## Self-review against the spec

- **RunControlStore table** (`runSettings`, `runSettingsOf`, `applyRunSettings`, `loadRunSettings`, `saveRunSettings`, `runSettingsSaveFailed`, `runSettingsRunners`, `runSettingsLoadRunner`), Load, Save, implementation shape, header → Task 1 Step 3; C-S1 … C-S9 → Task 1 Step 1; C-S10 → Task 2 Step 3.
- **RunDispatchStore table** (signals, `onProjectChanged`, `dispatchStartReplied` order, `dispatchSaveFailed`, `mergedPrefixes` gone, `saving` gone, `savingFor`), header → Task 2 Step 6; D-N3 … D-N8, harness, `loadOf` / `saveOf`, redirects → Task 2 Step 1.
- **RunStore** removals, `project` header sentence, `runSettings` writable shim, `runSettingsRunner` shim → Task 2 Step 7; test deletions, 507-509 removal, R-S1 … R-S3 → Task 2 Step 2 (plus the `wireDispatch` rewire the spec did not list, Notes 1).
- **App** binding and the three routes, both comments → Task 2 Step 8; existing-test edits and A-S1 … A-S5 → Task 2 Step 4.
- **Gate** (run.sh green, ui untouched, no `viewer-state.py` in the two stores, no `Binding loop`) → Task 2 Step 9, with `Binding loop` covered by `failOnWarning` in R-S3 and A-S4.
- **Docs** lines 83, 91, 92, 93 → Task 3.
- **Equivalence**: same argv (C-S2, C-S7, the moved argv expectations in `tst_run_dispatch_store.qml` and `tst_app_runs.qml`); `{}` from the switch until the reply (C-S3, A-S3); the merge before `started` (D-N4); the flash only while that start's (D-N6, A-S5, moved test 30 and 32).
- Placeholder scan: every step carries the code or the exact command. Type consistency: `runSettingsRunners` items expose `root`, `json`, `saving`, `current` (Task 1) and `loadOf` / `saveOf` / `saveOf(app)` use only those; `dispatchSaveFailed(root, patch)` matches `runSettingsSaveFailed(var root, var patch)`.
<!-- task-pipeline: validated -->
