# 2.3 RunStore dispatch: the target step — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `RunStore` gets the rest of the Runs-opened dispatch's target step: a project pick reads that root's brd tree (`board-tree.py ROOT`), the store exposes the tree's target rows, card map and a loading flag, `dispatchTargetPick(key)` opens S3's form on a row for the picked project, a failed read disables that project's row with the helper's message, Back from the form returns to the target step, and the registry fallback also covers the form.

**Architecture:** Everything new goes in the existing section `// ---- dispatch: project and target steps` of `core/stores/RunStore.qml` (today `:1862-1955`), plus one new `HelperRunner` (`dispatchTargetRunner`) right after `dispatchProjectRunner`, and one new import, `../domain/board.js`. The tree read runs on `dispatchTargetRunner` with `guard: store.dispatchRoot`; its reply is parsed by `dispatchTargetReplied`, indexed with `Board.indexTree` and listed with `Runs.dispatchTargets`. `dispatchTargetPick` hands the row's card and the card map to 2.1's `dispatchOpenFor`, which already computes the defaults and the settings read for `dispatchRoot`. Failures live in `dispatchProjectFailures` and reach `dispatchProjectRows` as probe entries placed before the probe's own. The existing `dispatchBack`, `dispatchClearSteps`, `dispatchOpenFromRuns` and `dispatchRegistryChanged` are extended in place.

**Tech Stack:** QML (Qt 6, Quickshell), the `runs.js` and `board.js` domain libraries (both unchanged), QtTest store tests run by `qmltestrunner` with the stub `Process` in `tests/stubs`, the `bash tests/run.sh` gate (pytest incl. `tests/architecture`, then every QML test).

**Spec:** `docs/superpowers/specs/2-3-runstore-dispatch-c3f687b6.md` (prepended below, headings demoted one level; executors read both).

## Global Constraints

- Every new member goes in the section `// ---- dispatch: project and target steps` of `core/stores/RunStore.qml`, prefixed `dispatch*`: `dispatchTargetCardMap`, `dispatchTargetRows`, `dispatchTargetLoading`, `dispatchTargetKey`, `dispatchTargetRunner` (the `HelperRunner` and its `readonly property alias`), `dispatchTargetReplied(stdout)`, `dispatchTargetPick(key)`, `dispatchProjectFailures`, plus the helpers `dispatchClearTarget()` and `dispatchProbeEntries()`. The `HelperRunner` goes right after `dispatchProjectRunner`'s.
- `dispatchTargetRunner`: `script: store.backendDir + "boards/board-tree.py"`, `guard: store.dispatchRoot`, launched as `run([store.dispatchRoot])`, so its argv is `python3 <backendDir>boards/board-tree.py <dispatchRoot>` (no `--probe`). Latest wins.
- `RunStore.qml` gains exactly one import: `import "../domain/board.js" as Board`. `core/domain/runs.js`, `core/domain/board.js`, `core/backend/boards/board-tree.py`, `ui/` and every test file other than `tests/core/stores/tst_run_store.qml` stay unchanged.
- "Target data" is `dispatchTargetCardMap`, `dispatchTargetRows`, `dispatchTargetLoading`, `dispatchTargetKey`; clearing it means cancelling `dispatchTargetRunner` and setting them to `null`, `[]`, `false`, `""`.
- The failure message is `error.message` trimmed when that is a non-empty string, else exactly `The board could not be read`.
- `dispatchState` stays `"idle"` at the `project` and `target` steps. `dispatchOpenFor`, `resetDispatch` and the `started` refresh (`requestSnapshot([store.dispatchRoot])`) are not changed.
- Comments state the contract only, with no narrative.
- Tests go in `tests/core/stores/tst_run_store.qml`, in a new block `// ---- dispatch: the target step (2.3)` placed right before `// ---- list snapshots`; each new test carries a `// 2.3 test N` comment.
- Gate: `bash tests/run.sh` green (pytest incl. `tests/architecture`, then every QML test, no `TypeError`/`ReferenceError` lines).

## Review Focus

1. **The tree read replies after the user switched the open project.** A Runs-opened dialog ignores the switch, so the reply must still apply for the picked root (the guard is `dispatchRoot`, not `project`). Pinned in Task 1, `test_dispatch_target_read_survives_a_project_switch`.
2. **The helper's message has stray whitespace, or is blank, or the line is not JSON, or a node is `null`.** The row shows the trimmed message, or `The board could not be read`; nothing throws. Pinned in Task 2, `test_dispatch_target_failure_disables_the_row` (the leading/trailing-space message and the four `unreadable` cases).
3. **The probe's reply lands after a tree read failed and says that root is fine.** The row stays disabled with the failure message. Pinned in Task 2, `test_dispatch_target_failure_disables_the_row` (`a later probe saying B is ok does not lift the failure`).
4. **The user goes Back and picks another project before the first tree read replies.** Only the second root's reply applies; the first root's valid tree or failure changes nothing. Pinned in Task 3, `test_dispatch_target_stale_replies_are_dropped` (the first two cases).
5. **The picked project leaves the registry while a start launched from the form is in flight.** Nothing changes until the start replies, and the start completes for its root. Pinned in Task 5, `test_dispatch_registry_change_at_form` (the `starting` case).

## Decisions the spec leaves to the plan

- **`dispatchTargetLoading` is a binding**: `readonly property bool dispatchTargetLoading: dispatchTargetRunner.busy`. `HelperRunner.run()` sets `busy` true, `cancel()` sets it false, and the newest run's exit sets it false before `finished` is emitted, so it is true exactly from the launch until the reply or a cancel, and callers cannot write it.
- **Failures feed the rows through `dispatchProbeEntries()`**: `{root, ok: false, reason: message}` for each failure, then the probe's `projects`. `Runs.dispatchProjects` accepts an entries array and the first entry per root wins (`runs.js:474-487`, `:510-512`), so a failure beats any probe entry, including a later one.
- **The target data is cleared by one helper**, `dispatchClearTarget()`, used by `dispatchProjectPick`, a failed reply, `dispatchBack` from `target`, `dispatchClearSteps`, `dispatchOpenFromRuns` and `dispatchRegistryChanged`.
- **Two 2.2 assertions change in Task 5.** `test_dispatch_back_from_target` asserts `dispatchBack()` at `form` returns false ("Back from the form is 2.3's"), and `test_dispatch_registry_change_while_open_drops_the_row` asserts the form ignores the registry ("the form's registry rule is 2.3's"). This card defines both behaviours (spec "`dispatchBack()` (extended)", "Clearing and the other entry points"), so those two assertions are updated to the new behaviour. No other existing assertion changes.
- **`checkDispatchIdle` is split.** Its S3 field checks move to a new helper `checkDispatchFieldsIdle(store, label)`, which `checkDispatchIdle` calls before checking the step and the four target fields. Tests 9 and 10 need the S3 checks without the step check. Every existing caller sees the same checks plus the new four.
- **Test 3 reads B's settings with `bSettings()`, not `dispatchSettings()`.** The open project A's `runSettings` are already `dispatchSettings()` (`runsStore()`), so the same values would not show which root's settings the form used. `bSettings()` (2.1, parallelism 2, verify `make test`, prefix `bpre`) shows B's are used. Test 11 uses it for the same reason.
- **Extra test helpers** (inside the 2.3 block): `treeFail(message)`, `pickedStore(root)`, `targetStore(root)`, `checkTargetCleared(store, label)`, in addition to the spec's `treeCmd`, `treeReply`, `treeData`, `targetKeys`.
- **Test 7's card-entry case** checks the step `""`, root A, the target data cleared and the card's dispatch untouched (`previewing`). `checkDispatchIdle` cannot hold there because a card entry opens a dispatch.
- **Test order in the file** follows the tasks: 1, 2, 8 (Task 1), 5 (Task 2), 6, 7 (Task 3), 3, 4, 11 (Task 4), 9, 10 (Task 5).
- **Every stage was checked** in a scratch copy at `3be444d`: each task's new tests fail against the previous task's code as stated in its "verify it fails" step, and the whole file passes after each task (328, 329, 331, 334, 336 tests).

## Running the tests

`Q` below stands for this command, run from the worktree root:

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml
```

Append `StoresRunStore::<test_name>` arguments to run single tests. Always write the full command in the shell; `Q` is shorthand in this document only. Before Task 1 the file reports `Totals: 325 passed, 0 failed`.

---

## Spec (prepended, headings demoted one level)

## 2.3 RunStore dispatch: the target step — design

Card: `c3f687b6` (subtask of story `8200b9d4`, the last of its three). It builds on 2.1
(`abbba4c7`, `docs/superpowers/specs/2-1-runstore-dispatch-abbba4c7.md`) and 2.2 (`080cfe16`,
`docs/superpowers/specs/2-2-runstore-dispatch-080cfe16.md`, cited as "2.2 spec"), both merged on
this branch. Parent design: `docs/superpowers/specs/2026-10-05-dispatch-from-runs-design.md`,
cited as "DFR l.N". The store contract today is `docs/architecture.md:92`, cited as "ARCH l.92".
Code lines are on this branch at `3be444d`.

### Purpose

After 2.2, `dispatchProjectPick(root)` moves the Runs-opened dispatch to the `target` step and
launches nothing. This card gives the store the rest of the target step (DFR l.81-94, l.204-208):

- the pick reads the picked project's brd tree (`board-tree.py ROOT`);
- the store exposes that tree's target rows and a loading flag;
- `dispatchTargetPick(key)` hands the picked target to S3's form, exactly as a card or the board
  entry does, with the picked project's defaults;
- a failed tree read returns to the project step with that row disabled and the helper's
  message (DFR l.74-75, l.234);
- a reply for a root the user has left is dropped (DFR l.205-206, l.235);
- Back from the form returns to the target step and keeps the picked row (DFR l.102-103).

Nothing in `ui/` calls these members yet. The dialog is card 3.1.

### Inherited constraints

- The new members go in the existing section `// ---- dispatch: project and target steps`
  (`core/stores/RunStore.qml:1862-1955`), each prefixed `dispatch*`, together with their runner
  and its alias, so the split can lift the section out whole (DFR l.185-193). The card names
  `dispatchTargetCardMap`, `dispatchTargetRows`, `dispatchTargetLoading`, `dispatchTargetRunner`,
  `dispatchTargetReplied(…)` and `dispatchTargetPick(key)` (DFR l.193). This spec adds two more
  section members, `dispatchTargetKey` and `dispatchProjectFailures` (see State).
- `dispatchTargetRunner` runs `board-tree.py ROOT`, latest wins, `guard: dispatchRoot`
  (DFR l.204-206). The helper prints one JSON line, `{"ok": true, "data": [...]}` (brd's tree
  unchanged) or `{"ok": false, "error": {"type", "message"}}`, and exits 0 whenever it printed a
  line (DFR l.148-152, l.158).
- The tree is indexed with `Board.indexTree` (`core/domain/board.js:12`), which sets `depth` and
  `parentId`, and that card map is the one a target picked here hands to the form
  (DFR l.159-161, l.206-208).
- The rows are `Runs.dispatchTargets(roots, cardMap)` (`core/domain/runs.js:1196`):
  `{key, level, card, label, depth}`, the `board` row first, then the offered cards in tree
  order with key `"card:" + id` (DFR l.86-94, l.179-181).
- Step 3 is S3's form unchanged, with its defaults computed for the picked project: the base
  from `dispatch-preview.py --defaults ROOT`, the prefix and the settings from ROOT's runs and
  run settings (DFR l.96-103). 2.1's `dispatchOpenFor(card, cardMap)` (`RunStore.qml:1532`)
  already does all of that for `dispatchRoot`.
- A failed tree read marks the project unreachable "the same way" as the probe: the row is
  disabled, shows the reason and ignores a pick, and the dialog returns to step 1
  (DFR l.72-75, l.234). The row's reason is the helper's message.
- The picked project leaving the registry returns the dialog to step 1 with the row gone; a
  launch already started completes (DFR l.236).
- A Runs-opened dialog ignores a switch of the open project (DFR l.209-212, 2.2 spec "Project
  switch").
- On `started` the card asks for a refresh of `dispatchRoot`'s project only. That is 2.1's code
  (`RunStore.qml:1821`, `requestSnapshot([store.dispatchRoot])`) and ARCH l.92. DFR l.107-109 and
  l.213-215 describe a global refresh instead. This card follows the card text and the code: it
  only adds a test, and it changes no refresh behaviour.
- Layering follows `docs/architecture.md:14`. `core/stores/*.qml` may import `../domain/*.js`,
  so `RunStore.qml` gains `import "../domain/board.js" as Board`, and no other import.
  `tests/architecture` must pass, and `bash tests/run.sh` must be green. Tests come first.
  Comments state the contract only, with no narrative (card).

### Behaviour

#### State

Everything below is declared in the section.

- `property var dispatchTargetCardMap: null`: the picked tree's `{id: card}` map, from
  `Board.indexTree`. It is non-null only after a successful tree read for the current
  `dispatchRoot`, and stays so at `target` and `form`. It is `null` otherwise.
- `property var dispatchTargetRows: []`: `Runs.dispatchTargets(roots, dispatchTargetCardMap)`
  over that tree. It is set from the same successful reply, kept at `target` and `form`, and
  `[]` otherwise: before the reply, while loading, after a failure, and after any clear.
- `dispatchTargetLoading` (bool, read-only to callers): true from the launch of a tree read
  until its reply is handled or it is cancelled; false otherwise.
- `property string dispatchTargetKey: ""`: the key of the row `dispatchTargetPick` took. It is
  set at `form`, kept by Back from `form` (so the UI puts the cursor back on it, DFR l.102-103),
  and `""` whenever the target data is cleared.
- `property var dispatchProjectFailures: ({})`: `{root: message}` for each root whose tree read
  failed since the dialog was opened from Runs. Roots are as `dispatchRoot` holds them
  (trailing `/` removed).
- `dispatchProjectRows` stays a binding (2.2 spec "State"). A root in `dispatchProjectFailures`
  gives a row with `enabled: false` and `reason` its message. This holds whatever the probe says
  about that root, including a probe reply that lands after the failure. Every other row
  follows 2.2's rule. The plan may feed the failures into `Runs.dispatchProjects` as probe
  entries placed before the probe's own, since the first entry per root wins
  (`runs.js:510-512`). `runs.js` itself does not change.
- `readonly property alias dispatchTargetRunner: dispatchTargetRunner`. Tests reach `.current`
  and `.seq` through it.

Target data means `dispatchTargetCardMap`, `dispatchTargetRows`, `dispatchTargetLoading` and
`dispatchTargetKey`. Clearing it means cancelling `dispatchTargetRunner` and setting those four
to `null`, `[]`, `false` and `""`.

#### `dispatchProjectPick(root)` (extended)

2.2's refusals are unchanged: false, nothing changes, nothing launched. They cover a wrong step,
an unknown root, a disabled row, and now also a row disabled by `dispatchProjectFailures`.

On success it sets `dispatchRoot` and `dispatchStep = "target"` as before. Then it clears the
target data and launches the tree read on `dispatchTargetRunner` with argv
`python3 <backendDir>boards/board-tree.py <dispatchRoot>` (no `--probe`). The guard is the new
`dispatchRoot`, so `dispatchRoot` is set before `run()`. `dispatchTargetLoading` is true and
`dispatchTargetRows` is `[]` until the reply. It returns true. `dispatchState` stays `idle`, and
no defaults, settings or preview runner is launched.

#### `dispatchTargetRunner` and `dispatchTargetReplied(stdout)`

- `HelperRunner`, `script: store.backendDir + "boards/board-tree.py"`, `guard: store.dispatchRoot`,
  `onFinished: function(stdout, exitCode) { store.dispatchTargetReplied(stdout) }`. Its contract
  comment says: latest wins; a reply whose launch root is no longer `dispatchRoot` is dropped;
  Back, any step clear and the registry fallback cancel it.
- A reply is applied only while `dispatchStep === "target"`. Otherwise it changes nothing.
  Combined with the guard and the runner's sequence, a reply is dropped after Back, after a
  re-pick, after `closeDispatch`, after a card entry, after `dispatchOpenFromRuns`, and after the
  registry fallback.
- In every applied case `dispatchTargetLoading` becomes false. The exit code is not read.
- **Success**: `store.parseEnvelope(stdout)` is an object with `ok === true` and an array
  `data`, and `Board.indexTree(data)` does not throw. Then `dispatchTargetCardMap` is the
  indexed `cardMap`, and `dispatchTargetRows` is `Runs.dispatchTargets(data, cardMap)`. The step
  stays `target`. An empty `data` gives only the `board` row (DFR l.94).
- **Failure**: anything else. That covers an unreadable line (`null`), `ok !== true`,
  `ok: true` without an array `data`, or `indexTree` throwing on a malformed node. The message
  is `error.message` trimmed when the envelope has a non-empty string there. Otherwise it is the
  fixed sentence `The board could not be read`. Then:
  `dispatchProjectFailures[dispatchRoot] = message` (assign a new object so the binding
  re-evaluates), the target data is cleared, `dispatchStep = "project"` and `dispatchRoot = ""`.
  The project rows show that root as `off` with the message. Every other row is unchanged, and
  the probe is neither changed nor relaunched.

#### `dispatchTargetPick(key)`

- It succeeds only when `dispatchStep === "target"` and `dispatchTargetRows` has a row with
  `row.key === key`. Otherwise it returns false and nothing changes: wrong step, still
  loading (rows `[]`), unknown key, `""`, or a non-string.
- It calls `store.dispatchOpenFor(row.card, store.dispatchTargetCardMap)`. `row.card` is
  `"board"` for the Whole board row and the card object otherwise, which is exactly what the
  card and board entry points pass (ARCH l.92). If that call returns false, the pick returns
  false, the step stays `target`, `dispatchTargetKey` is not set, and it calls `resetDispatch()`
  so S3's fields are back to "none" (`dispatchOpenFor` may have left `refused` behind; the rows
  come from `Runs.dispatchTargets`, which agrees with `dispatchPlan`, so this is a guard, not a
  tested path). Otherwise it sets `dispatchTargetKey = key` and `dispatchStep = "form"`, and
  returns true. The target rows and card map stay.
- The form is therefore S3's, for `dispatchRoot`. `dispatchTargetLabel` is
  `Runs.dispatchLabel(card, cardMap)`. `dispatchForm` comes from
  `dispatchDefaultsFor(dispatchSettingsSource())`. `dispatchDefaultsRunner` runs
  `--defaults <dispatchRoot>`. When `dispatchRoot !== project`, `dispatchSettingsRunner` runs
  `get-run-settings <dispatchRoot>`, and its reply re-derives the form (2.1). When the picked
  root is the open project, `runSettings` is used and no settings read is launched. No new
  behaviour is added to `dispatchOpenFor`.

#### `dispatchBack()` (extended)

- From `target`: as in 2.2, step `project` and `dispatchRoot ""`, with the probe and the project
  rows kept (failure marks included) and nothing relaunched. In addition, the target data is
  cleared, which cancels a tree read in flight. Its late reply is dropped. It returns true.
- From `form`: refused (false, nothing changes) while `dispatchState === "starting"`, as
  `closeDispatch` is. Otherwise it calls `resetDispatch()` (S3's fields back to "none", its
  runners cancelled, `dispatchRoot` kept), sets `dispatchStep = "target"`, and returns true.
  `dispatchTargetRows`, `dispatchTargetCardMap` and `dispatchTargetKey` are kept, and no tree
  read is launched.
- At `""` and `project` it returns false and nothing changes (2.2).

#### Clearing and the other entry points

- `dispatchClearSteps()` also clears the target data and sets `dispatchProjectFailures = {}`.
  `closeDispatch()`, a closing panel (`stopLive`) and a card entry (`openDispatch`) already call
  it (2.2), so all of them drop a tree read in flight.
- `dispatchOpenFromRuns()` starts over with the target data cleared and
  `dispatchProjectFailures` `{}`. A new probe judges every root afresh.
- `dispatchRegistryChanged()`: at `target`, and also at `form` unless `dispatchState` is
  `"starting"`, a `dispatchRoot` that is no longer a usable root (trailing `/` removed) goes back
  to `project` with `dispatchRoot ""`. The target data is cleared, and at `form` the dispatch is
  reset (`resetDispatch()`). While `starting` nothing changes, so the start completes for its
  root (DFR l.236). A failure entry for a root that left the registry gives no row, because the
  rows come from the registry. At `""` and `project` nothing changes (2.2).
- `projectSwitched()` is unchanged. A Runs-opened dialog keeps its step, root, target data and
  failures, and a tree read in flight still applies, because its guard is `dispatchRoot`, not
  `project`.
- `retargetToMilestone()` at `form` is unchanged. The step stays `form`, and `dispatchTargetKey`
  stays the picked row's key.

#### Docs and comments

- `RunStore.qml` header (`:33-38`): the pick reads the picked root's tree (`board-tree.py ROOT`,
  guarded by `dispatchRoot`). `dispatchTargetPick` opens S3's form on a target row. A failed
  read disables that project's row.
- Each new or changed member gets a contract comment in the section's style
  (`RunStore.qml:1862-1955`).
- ARCH l.92: extend the Runs sentence with the tree read and its argv, `dispatchTargetRows` /
  `dispatchTargetCardMap` / `dispatchTargetLoading` / `dispatchTargetKey`,
  `dispatchTargetPick(key)` → `dispatchOpenFor` and step `form`, a failure disabling the row
  with the helper's message, Back from `form` to `target`, and the registry fallback at `form`.

### Errors and edge cases

| case | behaviour |
|---|---|
| tree read slower than the user | `dispatchTargetLoading` true, rows `[]`; Back cancels it and its reply is dropped (DFR l.235) |
| `{"ok": false, "error": {"type": "BrdFailed", "message": "ProjectNotFoundError: …"}}` | back to `project`, root `""`, row `off` with that message |
| unreadable line, `ok: true` without an array `data`, a node `indexTree` cannot walk, or a blank message | the same, with `The board could not be read` |
| a probe reply landing after a failure says the root is ok | row stays `off` with the failure message |
| pick of a failed row | false, nothing launched |
| `dispatchOpenFromRuns()` after a failure | failures forgotten, fresh probe |
| Back, then pick another root before the first reply | only the second root's reply applies (seq and guard) |
| reply after `closeDispatch`, a card entry, `dispatchOpenFromRuns` or the registry fallback | dropped |
| open project switched while the read is in flight | the reply still applies (guard is `dispatchRoot`) |
| `dispatchTargetPick` while loading, with an unknown key, or at a wrong step | false, nothing changes |
| picked root is the open project | form from `runSettings`; no settings read; `--defaults <project>` |
| picked root is another project | form from that root's settings read; `--defaults <root>`, `get-run-settings <root>` |
| Back from `form` while `starting` | false, nothing changes |
| Back from `form` otherwise | step `target`, rows, card map and key kept, S3 fields idle, no re-read |
| picked root leaves the registry at `form` (not starting) | dispatch reset, back to `project`, row gone |
| the same while `starting` | nothing changes; the start completes for its root |
| tree with no offered card | rows: the `board` row only |

### Tests

Every test is in the **QML store tests** tier, `tests/core/stores/tst_run_store.qml`. The
behaviour is store state and helper argv, which only the store harness (stubbed `Process`,
`argv`, `reply`) can observe. `Runs.dispatchTargets` and `Board.indexTree` are already covered
by domain tests (`tst_runs.qml`, card 1.3), and `board-tree.py` has its pytest, so neither gets a
test here. The UI is unchanged, so no `tests/ui` test is added. Architecture tests
(`tests/architecture`) run unchanged: the one new import is an allowed `../domain/*.js`.

The tests go at the end of the `// ---- dispatch: project and target steps (2.2)` block (it ends
at `:5957`), before `// ---- list snapshots`. Each carries a `// 2.3 test N` comment. The block
gains:

- `property string treeCmd: "python3|/plugin/core/backend/boards/board-tree.py"`;
- `treeReply(data)`, which returns `JSON.stringify({ok: true, data: data}) + "\n"`;
- `treeData()`, a fresh brd tree each call: milestone `m1` (todo) holding story `s1` (todo),
  which holds subtask `t1` (todo) and subtask `t2` (done); and milestone `d1` (done). The cards
  carry `children` arrays and no `depth` or `parentId`, as brd prints them;
- `targetKeys(rows)`, which joins the keys with `,`.

`checkDispatchIdle` gains checks that `dispatchTargetRows.length` is 0, `dispatchTargetCardMap`
is `null`, `dispatchTargetLoading` is false and `dispatchTargetKey` is `""`. Every existing
caller is in a state with no step, so the existing tests stay unchanged.

1. **`test_dispatch_target_pick_launches_the_tree_read`**: on `runsStore()`, open from Runs,
   reply to the probe, then pick B. The tree runner's argv is `treeCmd + "|/home/u/b"`, with
   `command.length` 3 and no `--probe`. `dispatchTargetLoading` is true, the rows are `[]`, the
   card map is `null`, and `dispatchState` is `idle`. No defaults or settings runner is current.
   A refused pick (a disabled row, or at `target`) launches nothing: the tree runner's `seq` is
   unchanged.
2. **`test_dispatch_target_rows_from_the_tree`**: reply `treeReply(treeData())`. Loading is
   false and the step is `target`. `targetKeys` is `board,card:m1,card:s1,card:t1`. Row 0's
   `card` is `"board"` and its label is `Whole board`. `t1`'s row has depth 2 and level
   `subtask`. `dispatchTargetCardMap.t1.parentId` is `"s1"`, and the map holds `t2` and `d1`.
   A second store whose reply is `treeReply([])` has rows `board` only.
3. **`test_dispatch_target_pick_enters_the_form_for_another_project`**: after test 2's setup,
   `dispatchTargetPick("card:m1")` returns true. The step is `form`, `dispatchTargetKey` is
   `card:m1`, `dispatchRoot` is B, `dispatchState` is `previewing`, and `dispatchTarget.level`
   is `milestone`. `dispatchTargetLabel` is `Runs.dispatchLabel` of m1. The defaults runner's
   argv is `--defaults|/home/u/b`, and the settings runner's argv is `get-run-settings|/home/u/b`.
   After the settings reply (`dispatchSettings()`) and the defaults reply, the form carries
   parallelism 4 and verify `uv run pytest` from B's settings. The rows and card map are still
   there. On a fresh store, picking `board` gives level `board` and label `Whole board`.
4. **`test_dispatch_target_pick_for_the_open_project_and_refusals`**: pick A, the open project,
   then reply to the tree. `dispatchTargetPick("card:t1")` returns true with the step at `form`.
   No settings runner is launched, and the form is built from `runSettings` (prefix history
   `old`, parallelism 4). The defaults argv is `--defaults|/home/u/my proj`. Refusals, each
   returning false with nothing changed: a pick while loading (before the reply), `"card:t2"`
   (done, not offered), `"card:zz"`, `""`, a pick at `form`, and a pick on a store with no step.
5. **`test_dispatch_target_failure_disables_the_row`**: pick B and reply
   `{"ok": false, "error": {"type": "BrdFailed", "message": " ProjectNotFoundError: no project "}}`.
   The step is `project` and `dispatchRoot` is `""`. Loading is false, and the rows and card map
   are cleared. `rowsText` shows B as `off:ProjectNotFoundError: no project`, and A is unchanged.
   `dispatchProjectPick(B)` returns false and launches nothing. A late probe reply that says B is
   ok leaves B `off` with the message. Fresh runs of the same flow with an unreadable line, with
   `{"ok": true}`, with `{"ok": true, "data": [null]}`, and with an `ok: false` envelope whose
   message is blank each give `off:The board could not be read`. `dispatchOpenFromRuns()`
   afterwards shows B `on` again, because the failures are cleared.
6. **`test_dispatch_back_from_target_cancels_the_read`**: pick B with the reply pending.
   `dispatchBack()` returns true and loading is false. The probe and the rows are kept, and the
   probe runner's `seq` is unchanged. A reply to the captured tree process changes nothing: the
   step stays `project`, the rows stay `[]` and there is no failure mark. Picking B again
   launches a new read (the `seq` advances), and its reply applies. After a reply, Back clears
   the rows and card map.
7. **`test_dispatch_target_stale_replies_are_dropped`**: pick B, Back, then pick A. A reply to
   B's captured process (a valid tree) changes nothing. A failure reply to it marks nothing.
   A's reply applies. Each of the following then drops a captured in-flight reply and leaves
   `checkDispatchIdle` true, or for `dispatchOpenFromRuns` leaves the step at `project` with
   the rows `[]`: `closeDispatch()`, `openDispatch(m1)` (step `""`, root A), and
   `dispatchOpenFromRuns()`. In the registry case, pick B, then drop B from the registry while
   loading: the step is `project`, and a reply to the captured process changes nothing.
8. **`test_dispatch_target_read_survives_a_project_switch`**: pick B with the read in flight,
   then set `project = rootC`. The step stays `target` and the root stays B. The reply applies:
   the rows are filled.
9. **`test_dispatch_back_from_form_keeps_the_picked_row`**: from test 3's form,
   `dispatchBack()` returns true. The step is `target`, `dispatchRoot` is B, `dispatchTargetKey`
   is `card:m1`, and the rows and card map are the same objects. `dispatchState` is `idle` and
   the S3 fields are none: the `checkDispatchIdle` field checks, except the step, root and
   target data. The tree runner's `seq` is unchanged. Picking `card:s1` then opens the form for
   the story. Back from `form` while `starting` (reached through `dispatchStart()` on a ready
   subtask form) returns false, with the step still `form` and the state still `starting`.
10. **`test_dispatch_registry_change_at_form`**: at `form` for B (not starting), dropping B from
    the registry gives step `project`, root `""`, the dispatch idle and the target data cleared.
    Reordering the registry at `form` changes nothing. While `starting` for B, dropping B
    changes nothing: the step is `form` and the state is `starting`.
11. **`test_dispatch_start_from_runs_refreshes_only_its_root`**: projects A and B are
    registered, with A open and their first snapshot landed. Open from Runs, pick B, reply to
    the tree, and pick `card:t1`. Reply to the defaults and settings reads (the state is
    `ready`), then `dispatchStart()` and a start reply `{ok: true, run_id: "r9"}`. The snapshot
    runner's `seq` advances by exactly 1, and its argv is `snapCmd + "|/home/u/b"`, so A is not
    in it. The state is `started`.

Existing tests are unchanged, apart from the `checkDispatchIdle` addition. The plan must run the
whole of `tst_run_store.qml`, and then `bash tests/run.sh`.

### Out of scope

- `DispatchDialog`, `RunsScreen`, `Shortcuts`, `Panel`: the steps' UI, the filter, the "Reading
  the board…" text and the cursor (cards 3.1, 3.2). User docs (3.4).
- `board-tree.py`, `runs.js` (`dispatchProjects`, `dispatchTargets`) and `board.js`: no change.
- Changing the `started` refresh from per-root to global (DFR l.107-109): not this card. The
  code keeps `requestSnapshot([dispatchRoot])`.
- How `dispatchSettingsSource()` behaves when the open project switches while a Runs-opened
  form is up: S3/2.1's rule, unchanged.
- Relaunching `in_progress` subtasks, and skipping step 1 with one project (DFR l.258-263).
- The `RunDispatchStore` split.

---

## File Structure

- **Modify `core/stores/RunStore.qml`**
  - `:4` imports: add `import "../domain/board.js" as Board` (Task 1).
  - `:33-38` header comment: the tree read, `dispatchTargetPick`, the failure (Task 6).
  - Section `// ---- dispatch: project and target steps` (`:1862-1955`): new properties after `dispatchProjectRunner`'s alias (Tasks 1, 2), `dispatchProbeEntries` (Task 2), `dispatchTargetReplied` (Tasks 1, 2) and `dispatchTargetPick` (Task 4) between `dispatchProjectPick` and `dispatchBack`, `dispatchClearTarget` before `dispatchClearSteps` (Task 1); `dispatchProjectRows`, `dispatchOpenFromRuns`, `dispatchProjectPick`, `dispatchBack`, `dispatchClearSteps`, `dispatchRegistryChanged` changed in place (Tasks 1-3, 5).
  - The `dispatchTargetRunner` `HelperRunner` right after the `dispatchProjectRunner` one (`:1949-1955`) (Task 1).
- **Modify `tests/core/stores/tst_run_store.qml`**
  - `checkDispatchIdle` (`:3939-3955`) split into `checkDispatchIdle` + `checkDispatchFieldsIdle` (Task 1).
  - Two assertions in the 2.2 block (`test_dispatch_back_from_target`, `test_dispatch_registry_change_while_open_drops_the_row`) (Task 5).
  - New block `// ---- dispatch: the target step (2.3)` right before `// ---- list snapshots` (`:5958`), filled by Tasks 1-5.
- **Modify `docs/architecture.md`** `:92`, the Runs sentences of the dispatch paragraph (Task 6).

---

### Task 1: A project pick reads the picked root's tree and lists its target rows

**Files:**
- Modify: `core/stores/RunStore.qml:4` (import), `:1872-1873` (after `dispatchProjectRunner`'s alias), `:1903-1916` (`dispatchProjectPick`), `:1918` (before `dispatchBack`), `:1928` (before `dispatchClearSteps`), `:1951-1955` (after `dispatchProjectRunner`)
- Test: `tests/core/stores/tst_run_store.qml:3938-3955` (`checkDispatchIdle`), new block before `:5958`

**Interfaces:**
- Consumes: `Board.indexTree(roots) -> {cardMap}` (`core/domain/board.js:12`, mutates cards with `parentId`, `depth`; throws on a `null` node), `Runs.dispatchTargets(roots, cardMap) -> [{key, level, card, label, depth}]` (`core/domain/runs.js:1196`), `store.parseEnvelope(text) -> object|null`, `HelperRunner` (`run(args)`, `cancel()`, `busy`, `seq`, `current`, `guard`, signal `finished(stdout, exitCode, launchedGuard)`).
- Produces: `property var dispatchTargetCardMap` (`null` | `{id: card}`), `property var dispatchTargetRows` (array), `readonly property bool dispatchTargetLoading`, `property string dispatchTargetKey`, `readonly property alias dispatchTargetRunner`, `function dispatchTargetReplied(stdout)` (success path only in this task), `function dispatchClearTarget()`. Test helpers `checkDispatchFieldsIdle(store, label)`, `treeCmd`, `treeReply(data)`, `treeFail(message)`, `treeData()`, `targetKeys(rows)`, `pickedStore(root)`, `targetStore(root)`, `checkTargetCleared(store, label)`.

- [ ] **Step 1: Split `checkDispatchIdle` and add the target-data checks**

In `tests/core/stores/tst_run_store.qml`, replace

```qml
  // Every dispatch field at its "none" value.
  function checkDispatchIdle(store, label) {
    compare(store.dispatchState, "idle", label + ": state")
```

with

```qml
  // Every dispatch field at its "none" value, no step and no target data.
  function checkDispatchIdle(store, label) {
    checkDispatchFieldsIdle(store, label)
    compare(store.dispatchStep, "", label + ": step")
    compare(store.dispatchTargetRows.length, 0, label + ": target rows")
    compare(store.dispatchTargetCardMap, null, label + ": target card map")
    compare(store.dispatchTargetLoading, false, label + ": target loading")
    compare(store.dispatchTargetKey, "", label + ": target key")
  }

  // S3's dispatch fields at their "none" values.
  function checkDispatchFieldsIdle(store, label) {
    compare(store.dispatchState, "idle", label + ": state")
```

and, at the end of the same (now `checkDispatchFieldsIdle`) function, replace

```qml
    compare(store.dispatchTargetLabel, "", label + ": target label")
    compare(store.dispatchStep, "", label + ": step")
  }
```

with

```qml
    compare(store.dispatchTargetLabel, "", label + ": target label")
  }
```

- [ ] **Step 2: Add the 2.3 block with its helpers and tests 1, 2 and 8**

In the same file, insert this right before the line `  // ---- list snapshots` (after the last 2.2 test, `test_dispatch_open_project_switch_leaves_a_runs_dialog_alone`):

```qml
  // ---- dispatch: the target step (2.3)

  // board-tree.py ROOT's argv up to the root.
  property string treeCmd: "python3|/plugin/core/backend/boards/board-tree.py"

  // board-tree.py ROOT's reply line: {"ok": true, "data": data}.
  function treeReply(data) {
    return JSON.stringify({ ok: true, data: data }) + "\n"
  }

  // board-tree.py ROOT's failure line: {"ok": false, "error": {type, message}}.
  function treeFail(message) {
    return JSON.stringify({ ok: false, error: { type: "BrdFailed", message: message } }) + "\n"
  }

  // A fresh brd tree as brd prints it (children, no depth or parentId):
  // milestone m1 holding story s1, which holds subtask t1 (todo) and
  // subtask t2 (done); then the done milestone d1.
  function treeData() {
    return [
      { id: "m1", title: "M3 Document runs", status: "todo", children: [
        { id: "s1", title: "Dispatch store", status: "todo", children: [
          { id: "t1", title: "RunStore dispatch", status: "todo", children: [] },
          { id: "t2", title: "Docs", status: "done", children: [] }] }] },
      { id: "d1", title: "M2 Monitor runs", status: "done", children: [] }
    ]
  }

  // The target rows' keys, ","-joined.
  function targetKeys(rows) {
    return rows.map(function(r) { return r.key }).join(",")
  }

  // runsStore() opened from Runs, A and B probed ok, and `root` picked: its
  // tree read is in flight.
  function pickedStore(root) {
    var store = runsStore(); if (!store) return null
    store.dispatchOpenFromRuns()
    reply(store.dispatchProjectRunner.current, probeReply([{ root: tc.rootA, ok: true }, { root: tc.rootB, ok: true }]), 0)
    store.dispatchProjectPick(root)
    return store
  }

  // pickedStore(root) with treeData() read: the target rows are up.
  function targetStore(root) {
    var store = pickedStore(root); if (!store) return null
    reply(store.dispatchTargetRunner.current, treeReply(treeData()), 0)
    return store
  }

  // The target data at its cleared values.
  function checkTargetCleared(store, label) {
    compare(store.dispatchTargetRows.length, 0, label + ": target rows")
    compare(store.dispatchTargetCardMap, null, label + ": target card map")
    compare(store.dispatchTargetLoading, false, label + ": target loading")
    compare(store.dispatchTargetKey, "", label + ": target key")
  }

  // 2.3 test 1
  function test_dispatch_target_pick_launches_the_tree_read() {
    var store = runsStore(); if (!store) return
    store.dispatchOpenFromRuns()
    reply(store.dispatchProjectRunner.current, probeReply([{ root: tc.rootA, ok: true }, { root: tc.rootB, ok: true }]), 0)
    verify(!store.dispatchTargetRunner.current, "no tree read before a pick")
    compare(store.dispatchTargetLoading, false)
    compare(store.dispatchProjectPick(tc.rootB), true)
    var proc = store.dispatchTargetRunner.current
    verify(proc, "the pick reads B's tree")
    compare(argv(proc), tc.treeCmd + "|/home/u/b")
    compare(proc.command.length, 3, "no --probe")
    compare(proc.launchGuard, tc.rootB, "guarded by the picked root")
    compare(store.dispatchTargetLoading, true)
    compare(store.dispatchTargetRows.length, 0, "no rows until the reply")
    compare(store.dispatchTargetCardMap, null)
    compare(store.dispatchTargetKey, "")
    compare(store.dispatchState, "idle")
    verify(!store.dispatchDefaultsRunner.current, "no defaults lookup")
    verify(!store.dispatchSettingsRunner.current, "no settings read")
    verify(!store.dispatchPreviewRunner.current, "no preview")
    var seq = store.dispatchTargetRunner.seq
    compare(store.dispatchProjectPick(tc.rootA), false, "no pick at the target step")
    compare(store.dispatchTargetRunner.seq, seq, "a refused pick launches nothing")
    verify(store.dispatchTargetRunner.current === proc)
    compare(store.dispatchRoot, tc.rootB)

    var off = runsStore(); if (!off) return
    off.dispatchOpenFromRuns()
    reply(off.dispatchProjectRunner.current, probeReply([{ root: tc.rootB, ok: false, reason: "no .brd marker" }]), 0)
    var offSeq = off.dispatchTargetRunner.seq
    compare(off.dispatchProjectPick(tc.rootB), false, "a disabled row")
    compare(off.dispatchTargetRunner.seq, offSeq, "a disabled row launches nothing")
    verify(!off.dispatchTargetRunner.current)
    compare(off.dispatchTargetLoading, false)
  }

  // 2.3 test 2
  function test_dispatch_target_rows_from_the_tree() {
    var store = pickedStore(tc.rootB); if (!store) return
    reply(store.dispatchTargetRunner.current, treeReply(treeData()), 0)
    compare(store.dispatchTargetLoading, false)
    compare(store.dispatchStep, "target")
    compare(store.dispatchRoot, tc.rootB)
    compare(store.dispatchState, "idle")
    var rows = store.dispatchTargetRows
    compare(targetKeys(rows), "board,card:m1,card:s1,card:t1", "the board row, then the offered cards in tree order")
    compare(rows[0].card, "board")
    compare(rows[0].level, "board")
    compare(rows[0].label, "Whole board")
    compare(rows[1].level, "milestone")
    compare(rows[1].label, "Milestone \"M3 Document runs\"")
    compare(rows[3].level, "subtask")
    compare(rows[3].depth, 2)
    var map = store.dispatchTargetCardMap
    compare(map.t1.parentId, "s1", "indexed with Board.indexTree")
    compare(map.t1.depth, 2)
    compare(Object.keys(map).sort().join(","), "d1,m1,s1,t1,t2", "the map holds every card")
    verify(rows[3].card === map.t1, "the row's card is the map's card")

    var empty = pickedStore(tc.rootB); if (!empty) return
    reply(empty.dispatchTargetRunner.current, treeReply([]), 0)
    compare(targetKeys(empty.dispatchTargetRows), "board", "a tree with no offered card gives the board row only")
    compare(Object.keys(empty.dispatchTargetCardMap).length, 0)
    compare(empty.dispatchStep, "target")
  }

  // 2.3 test 8
  function test_dispatch_target_read_survives_a_project_switch() {
    var store = pickedStore(tc.rootB); if (!store) return
    var proc = store.dispatchTargetRunner.current
    store.project = tc.rootC
    compare(store.dispatchStep, "target", "the step is kept")
    compare(store.dispatchRoot, tc.rootB, "the root is kept")
    compare(store.dispatchTargetLoading, true, "the read is still in flight")
    verify(store.dispatchTargetRunner.current === proc, "and not relaunched")
    reply(proc, treeReply(treeData()), 0)
    compare(store.dispatchTargetLoading, false)
    compare(targetKeys(store.dispatchTargetRows), "board,card:m1,card:s1,card:t1", "the reply applies")
  }

```

- [ ] **Step 3: Run the file to verify it fails**

Run: `Q 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `Totals: 309 passed, 19 failed`. The three new tests fail with `Cannot read property 'current' of undefined` (no `dispatchTargetRunner`), and the 16 existing callers of `checkDispatchIdle` (for example `test_dispatch_starts_idle`, `test_dispatch_close_and_card_entry_clear_the_steps`) fail with `Cannot read property 'length' of undefined` (no `dispatchTargetRows`).

- [ ] **Step 4: Add the import**

In `core/stores/RunStore.qml`, replace

```qml
import "../domain/runs.js" as Runs
```

with

```qml
import "../domain/runs.js" as Runs
import "../domain/board.js" as Board
```

- [ ] **Step 5: Add the target properties**

In the section `// ---- dispatch: project and target steps`, right after the line `  readonly property alias dispatchProjectRunner: dispatchProjectRunner`, insert:

```qml
  // The picked root's brd tree as Board.indexTree's {id: card} map: set by a
  // good tree read for dispatchRoot and kept at the target and form steps;
  // else null.
  property var dispatchTargetCardMap: null
  // The target step's rows, Runs.dispatchTargets over that tree: set and
  // kept with dispatchTargetCardMap; else [].
  property var dispatchTargetRows: []
  // A tree read is in flight: from its launch until its reply or a cancel.
  readonly property bool dispatchTargetLoading: dispatchTargetRunner.busy
  // The key of the row dispatchTargetPick took; kept by Back from the form,
  // "" whenever the target data is cleared.
  property string dispatchTargetKey: ""
  readonly property alias dispatchTargetRunner: dispatchTargetRunner
```

- [ ] **Step 6: Make the project pick read the tree**

Replace `dispatchProjectPick` with its comment:

```qml
  // Takes the project step's enabled row for `root`: dispatchRoot is the
  // row's root and the step is target; nothing is launched. Refused (false,
  // nothing changes) at any other step and for a root with no enabled row.
  function dispatchProjectPick(root) {
    if (store.dispatchStep !== "project") return false
    var rows = store.dispatchProjectRows
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].root !== root || rows[i].enabled !== true) continue
      store.dispatchRoot = rows[i].root
      store.dispatchStep = "target"
      return true
    }
    return false
  }
```

with

```qml
  // Takes the project step's enabled row for `root`: dispatchRoot is the
  // row's root, the step is target, the target data is cleared and the
  // root's tree is read (board-tree.py ROOT); no defaults, settings or
  // preview is launched. Refused (false, nothing changes) at any other step
  // and for a root with no enabled row.
  function dispatchProjectPick(root) {
    if (store.dispatchStep !== "project") return false
    var rows = store.dispatchProjectRows
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].root !== root || rows[i].enabled !== true) continue
      store.dispatchRoot = rows[i].root
      store.dispatchStep = "target"
      store.dispatchClearTarget()
      dispatchTargetRunner.run([store.dispatchRoot])
      return true
    }
    return false
  }
```

- [ ] **Step 7: Add `dispatchTargetReplied` (the success path)**

Right before the line `  // From the target step back to the project step, dispatchRoot "". The` (the comment of `dispatchBack`), insert:

```qml
  // The tree read's reply, applied only at the target step. {ok: true,
  // data: [...]} that Board.indexTree walks gives dispatchTargetCardMap and
  // dispatchTargetRows. The exit code is not read.
  function dispatchTargetReplied(stdout) {
    if (store.dispatchStep !== "target") return
    var envelope = store.parseEnvelope(stdout)
    var data = envelope !== null && envelope.ok === true && Array.isArray(envelope.data) ? envelope.data : null
    var cardMap = null
    if (data !== null) {
      try { cardMap = Board.indexTree(data).cardMap } catch (e) { cardMap = null }
    }
    if (cardMap === null) return
    store.dispatchTargetCardMap = cardMap
    store.dispatchTargetRows = Runs.dispatchTargets(data, cardMap)
  }

```

- [ ] **Step 8: Add `dispatchClearTarget`**

Right before the line `  // The steps cleared: the probe cancelled, dispatchStep "" and` (the comment of `dispatchClearSteps`), insert:

```qml
  // The target data cleared: the tree read cancelled, dispatchTargetCardMap
  // null, dispatchTargetRows [] and dispatchTargetKey "".
  function dispatchClearTarget() {
    dispatchTargetRunner.cancel()
    store.dispatchTargetCardMap = null
    store.dispatchTargetRows = []
    store.dispatchTargetKey = ""
  }

```

- [ ] **Step 9: Add the runner**

Right after the `dispatchProjectRunner` `HelperRunner`, whose last two lines are

```qml
    onFinished: function(stdout, exitCode) { store.dispatchProjectReplied(stdout) }
  }
```

insert:

```qml

  // board-tree.py ROOT for the target step; latest wins. Guarded by
  // dispatchRoot: a reply whose launch root is no longer dispatchRoot is
  // dropped. Back, any step clear and the registry fallback cancel it.
  HelperRunner {
    id: dispatchTargetRunner
    script: store.backendDir + "boards/board-tree.py"
    guard: store.dispatchRoot
    onFinished: function(stdout, exitCode) { store.dispatchTargetReplied(stdout) }
  }
```

- [ ] **Step 10: Run the tests to verify they pass**

Run: `Q StoresRunStore::test_dispatch_target_pick_launches_the_tree_read StoresRunStore::test_dispatch_target_rows_from_the_tree StoresRunStore::test_dispatch_target_read_survives_a_project_switch StoresRunStore::test_dispatch_starts_idle`
Expected: all PASS, `0 failed`, no `TypeError`/`ReferenceError` line.

Run: `Q 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: `Totals: 328 passed, 0 failed`, nothing else.

- [ ] **Step 11: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): a project pick reads the picked root's tree into target rows"
```

---

### Task 2: A failed tree read disables the project's row

**Files:**
- Modify: `core/stores/RunStore.qml` section `// ---- dispatch: project and target steps`: `dispatchProjectRows`, after `dispatchTargetRunner`'s alias, `dispatchTargetReplied`, `dispatchOpenFromRuns`, `dispatchClearSteps`
- Test: `tests/core/stores/tst_run_store.qml`, the 2.3 block

**Interfaces:**
- Consumes: Task 1's `dispatchTargetReplied`, `dispatchClearTarget()`, `pickedStore(root)`, `treeFail(message)`, `treeReply(data)`, `checkTargetCleared(store, label)`; 2.2's `rowsText(rows)`, `probeReply(entries)`, `dispatchProjectReplied(stdout)`; `store.copyMap(map)`; `Runs.dispatchProjects(projectRoots, probe, openRoot)` (probe may be an entries array).
- Produces: `property var dispatchProjectFailures` (`{root: message}`), `function dispatchProbeEntries() -> [{root, ok, reason}...]`, the full `dispatchTargetReplied(stdout)`.

- [ ] **Step 1: Write the failing test**

In the 2.3 block, right after `test_dispatch_target_read_survives_a_project_switch`, insert:

```qml
  // 2.3 test 5
  function test_dispatch_target_failure_disables_the_row() {
    var store = pickedStore(tc.rootB); if (!store) return
    var probeSeq = store.dispatchProjectRunner.seq
    reply(store.dispatchTargetRunner.current, treeFail(" ProjectNotFoundError: no project "), 0)
    compare(store.dispatchStep, "project")
    compare(store.dispatchRoot, "")
    compare(store.dispatchState, "idle")
    checkTargetCleared(store, "failed")
    compare(rowsText(store.dispatchProjectRows),
            "/home/u/my proj:alpha:open:on: / /home/u/b:beta::off:ProjectNotFoundError: no project",
            "B is off with the helper's message, A unchanged")
    compare(store.dispatchProjectFailures[tc.rootB], "ProjectNotFoundError: no project")
    compare(store.dispatchProjectRunner.seq, probeSeq, "the probe is not relaunched")
    var seq = store.dispatchTargetRunner.seq
    compare(store.dispatchProjectPick(tc.rootB), false, "a failed row ignores a pick")
    compare(store.dispatchTargetRunner.seq, seq, "nothing launched")
    compare(store.dispatchStep, "project")
    store.dispatchProjectReplied(probeReply([{ root: tc.rootA, ok: true }, { root: tc.rootB, ok: true }]))
    compare(rowsText(store.dispatchProjectRows),
            "/home/u/my proj:alpha:open:on: / /home/u/b:beta::off:ProjectNotFoundError: no project",
            "a later probe saying B is ok does not lift the failure")

    var unreadable = ["Traceback: boom\n", JSON.stringify({ ok: true }) + "\n", treeReply([null]), treeFail("   ")]
    for (var i = 0; i < unreadable.length; i++) {
      var bad = pickedStore(tc.rootB); if (!bad) return
      reply(bad.dispatchTargetRunner.current, unreadable[i], i === 0 ? 1 : 0)
      compare(bad.dispatchStep, "project", "case " + i + ": back to step 1")
      compare(bad.dispatchRoot, "", "case " + i + ": no root")
      checkTargetCleared(bad, "case " + i)
      compare(rowsText(bad.dispatchProjectRows),
              "/home/u/my proj:alpha:open:on: / /home/u/b:beta::off:The board could not be read", "case " + i)
    }

    compare(store.dispatchOpenFromRuns(), true)
    compare(Object.keys(store.dispatchProjectFailures).length, 0, "a reopening forgets the failures")
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on: / /home/u/b:beta::on:", "B is judged afresh")
    compare(store.dispatchProjectPick(tc.rootB), true)

    var closed = pickedStore(tc.rootB); if (!closed) return
    reply(closed.dispatchTargetRunner.current, treeFail("gone"), 0)
    compare(closed.closeDispatch(), true)
    compare(Object.keys(closed.dispatchProjectFailures).length, 0, "a close forgets the failures")
  }

```

- [ ] **Step 2: Run it to verify it fails**

Run: `Q StoresRunStore::test_dispatch_target_failure_disables_the_row`
Expected: FAIL with `Compared values are not the same` at the first `compare(store.dispatchStep, "project")` (Task 1's reply ignores a failure, so the step is still `target`).

- [ ] **Step 3: Feed the failures into the project rows**

Replace

```qml
  // The project step's rows: Runs.dispatchProjects over the usable roots,
  // the probe and the open project while a step is open, else [].
  readonly property var dispatchProjectRows: store.dispatchStep !== ""
    ? Runs.dispatchProjects(store.usableRoots(), store.dispatchProjectProbe, store.project) : []
```

with

```qml
  // The project step's rows: Runs.dispatchProjects over the usable roots,
  // the probe entries (dispatchProbeEntries) and the open project while a
  // step is open, else [].
  readonly property var dispatchProjectRows: store.dispatchStep !== ""
    ? Runs.dispatchProjects(store.usableRoots(), store.dispatchProbeEntries(), store.project) : []
```

Right after the line `  readonly property alias dispatchTargetRunner: dispatchTargetRunner` (added in Task 1), insert:

```qml
  // {root: message} for each root whose tree read failed since the dialog
  // was opened from Runs, the root as dispatchRoot held it. Its row is
  // disabled with the message as its reason, whatever the probe says.
  property var dispatchProjectFailures: ({})

  // The probe entries the project rows read: {root, ok: false, reason} for
  // each dispatchProjectFailures root, then the probe's own entries; the
  // first entry for a root wins.
  function dispatchProbeEntries() {
    var failures = store.dispatchProjectFailures
    var entries = Object.keys(failures).map(function(root) { return { root: root, ok: false, reason: failures[root] } })
    var probe = store.dispatchProjectProbe
    return probe !== null ? entries.concat(probe.projects) : entries
  }
```

- [ ] **Step 4: Handle a failed reply**

Replace Task 1's `dispatchTargetReplied` with its comment:

```qml
  // The tree read's reply, applied only at the target step. {ok: true,
  // data: [...]} that Board.indexTree walks gives dispatchTargetCardMap and
  // dispatchTargetRows. The exit code is not read.
  function dispatchTargetReplied(stdout) {
    if (store.dispatchStep !== "target") return
    var envelope = store.parseEnvelope(stdout)
    var data = envelope !== null && envelope.ok === true && Array.isArray(envelope.data) ? envelope.data : null
    var cardMap = null
    if (data !== null) {
      try { cardMap = Board.indexTree(data).cardMap } catch (e) { cardMap = null }
    }
    if (cardMap === null) return
    store.dispatchTargetCardMap = cardMap
    store.dispatchTargetRows = Runs.dispatchTargets(data, cardMap)
  }

```

with

```qml
  // The tree read's reply, applied only at the target step. {ok: true,
  // data: [...]} that Board.indexTree walks gives dispatchTargetCardMap and
  // dispatchTargetRows. Anything else records dispatchRoot in
  // dispatchProjectFailures with error.message trimmed (else "The board
  // could not be read"), clears the target data and goes back to the
  // project step with dispatchRoot "". The exit code is not read.
  function dispatchTargetReplied(stdout) {
    if (store.dispatchStep !== "target") return
    var envelope = store.parseEnvelope(stdout)
    var data = envelope !== null && envelope.ok === true && Array.isArray(envelope.data) ? envelope.data : null
    var cardMap = null
    if (data !== null) {
      try { cardMap = Board.indexTree(data).cardMap } catch (e) { cardMap = null }
    }
    if (cardMap !== null) {
      store.dispatchTargetCardMap = cardMap
      store.dispatchTargetRows = Runs.dispatchTargets(data, cardMap)
      return
    }
    var err = envelope !== null && envelope.ok !== true ? envelope.error : null
    var message = err !== null && typeof err === "object" && typeof err.message === "string" ? err.message.trim() : ""
    var failures = store.copyMap(store.dispatchProjectFailures)
    failures[store.dispatchRoot] = message !== "" ? message : "The board could not be read"
    store.dispatchProjectFailures = failures
    store.dispatchClearTarget()
    store.dispatchStep = "project"
    store.dispatchRoot = ""
  }

```

- [ ] **Step 5: Forget the failures on every opening and clear**

Replace the head of `dispatchOpenFromRuns`:

```qml
  // Opens the dispatch from Runs at the project step with no root and probes
  // every usable root, in registry order. Refused (false, nothing changes)
  // while a start is in flight; else true, from any state or step: a second
  // call starts the step over. With no usable root nothing is launched and
  // the rows are [].
  function dispatchOpenFromRuns() {
    if (store.dispatchState === "starting") return false
    store.resetDispatch()
    store.dispatchRoot = ""
    store.dispatchStep = "project"
    store.dispatchProjectProbe = null
```

with

```qml
  // Opens the dispatch from Runs at the project step with no root and no
  // failures, and probes every usable root, in registry order. Refused
  // (false, nothing changes) while a start is in flight; else true, from
  // any state or step: a second call starts the step over. With no usable
  // root nothing is launched and the rows are [].
  function dispatchOpenFromRuns() {
    if (store.dispatchState === "starting") return false
    store.resetDispatch()
    store.dispatchRoot = ""
    store.dispatchStep = "project"
    store.dispatchProjectProbe = null
    store.dispatchProjectFailures = {}
```

Replace `dispatchClearSteps` with its comment:

```qml
  // The steps cleared: the probe cancelled, dispatchStep "" and
  // dispatchProjectProbe null.
  function dispatchClearSteps() {
    dispatchProjectRunner.cancel()
    store.dispatchStep = ""
    store.dispatchProjectProbe = null
  }
```

with

```qml
  // The steps cleared: the probe cancelled, dispatchStep "",
  // dispatchProjectProbe null and dispatchProjectFailures {}.
  function dispatchClearSteps() {
    dispatchProjectRunner.cancel()
    store.dispatchStep = ""
    store.dispatchProjectProbe = null
    store.dispatchProjectFailures = {}
  }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `Q StoresRunStore::test_dispatch_target_failure_disables_the_row StoresRunStore::test_dispatch_project_pick StoresRunStore::test_dispatch_rows_follow_project_roots`
Expected: all PASS, `0 failed`.

Run: `Q 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: `Totals: 329 passed, 0 failed`, nothing else.

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): a failed tree read disables the project's row with the helper's message"
```

---

### Task 3: Back, every clear and the registry fallback drop a tree read in flight

**Files:**
- Modify: `core/stores/RunStore.qml` section `// ---- dispatch: project and target steps`: `dispatchBack`, `dispatchClearSteps`, `dispatchOpenFromRuns`, `dispatchRegistryChanged`
- Test: `tests/core/stores/tst_run_store.qml`, the 2.3 block

**Interfaces:**
- Consumes: `dispatchClearTarget()` (Task 1); `pickedStore`, `checkTargetCleared`, `treeReply`, `treeFail`, `targetKeys` (Task 1); 2.1's `dispatchCards()`; `checkDispatchIdle(store, label)`.
- Produces: `dispatchBack()` and `dispatchRegistryChanged()` at `target` clear the target data; `dispatchClearSteps()` and `dispatchOpenFromRuns()` clear it too.

- [ ] **Step 1: Write the failing tests**

In the 2.3 block, right after `test_dispatch_target_failure_disables_the_row`, insert:

```qml
  // 2.3 test 6
  function test_dispatch_back_from_target_cancels_the_read() {
    var store = pickedStore(tc.rootB); if (!store) return
    var probe = store.dispatchProjectProbe
    var probeSeq = store.dispatchProjectRunner.seq
    var late = store.dispatchTargetRunner.current
    compare(store.dispatchBack(), true)
    compare(store.dispatchStep, "project")
    compare(store.dispatchRoot, "")
    compare(store.dispatchTargetLoading, false, "Back cancels the read")
    verify(store.dispatchProjectProbe === probe, "the probe is kept")
    compare(store.dispatchProjectRunner.seq, probeSeq, "the probe is not relaunched")
    compare(store.dispatchProjectRows.length, 2)
    reply(late, treeReply(treeData()), 0)
    compare(store.dispatchStep, "project", "the late reply changes nothing")
    checkTargetCleared(store, "late reply")
    compare(Object.keys(store.dispatchProjectFailures).length, 0, "and marks nothing")
    var seq = store.dispatchTargetRunner.seq
    compare(store.dispatchProjectPick(tc.rootB), true)
    verify(store.dispatchTargetRunner.seq > seq, "a new read")
    reply(store.dispatchTargetRunner.current, treeReply(treeData()), 0)
    compare(targetKeys(store.dispatchTargetRows), "board,card:m1,card:s1,card:t1", "its reply applies")
    compare(store.dispatchBack(), true)
    checkTargetCleared(store, "Back after the reply")
  }

  // 2.3 test 7
  function test_dispatch_target_stale_replies_are_dropped() {
    var store = pickedStore(tc.rootB); if (!store) return
    var lateB = store.dispatchTargetRunner.current
    store.dispatchBack()
    compare(store.dispatchProjectPick(tc.rootA), true)
    var procA = store.dispatchTargetRunner.current
    reply(lateB, treeReply(treeData()), 0)
    compare(store.dispatchRoot, tc.rootA)
    compare(store.dispatchTargetLoading, true, "B's reply leaves A's read in flight")
    compare(store.dispatchTargetRows.length, 0, "B's tree is not shown for A")
    reply(procA, treeReply([]), 0)
    compare(targetKeys(store.dispatchTargetRows), "board", "A's reply applies")

    var failed = pickedStore(tc.rootB); if (!failed) return
    var lateFail = failed.dispatchTargetRunner.current
    failed.dispatchBack()
    failed.dispatchProjectPick(tc.rootA)
    reply(lateFail, treeFail("gone"), 0)
    compare(failed.dispatchStep, "target", "B's failure does not send A back")
    compare(failed.dispatchRoot, tc.rootA)
    compare(Object.keys(failed.dispatchProjectFailures).length, 0, "and marks nothing")

    var closed = pickedStore(tc.rootB); if (!closed) return
    var lateClosed = closed.dispatchTargetRunner.current
    compare(closed.closeDispatch(), true)
    checkDispatchIdle(closed, "closed")
    reply(lateClosed, treeReply(treeData()), 0)
    checkDispatchIdle(closed, "a reply after the close")
    compare(closed.dispatchRoot, "")

    var card = pickedStore(tc.rootB); if (!card) return
    var lateCard = card.dispatchTargetRunner.current
    var cards = dispatchCards()
    compare(card.openDispatch(cards.m1, cards), true)
    compare(card.dispatchStep, "")
    compare(card.dispatchRoot, tc.rootA)
    checkTargetCleared(card, "card entry")
    reply(lateCard, treeReply(treeData()), 0)
    checkTargetCleared(card, "a reply after a card entry")
    compare(card.dispatchStep, "")
    compare(card.dispatchState, "previewing", "the card's dispatch is untouched")

    var reopened = pickedStore(tc.rootB); if (!reopened) return
    var lateReopen = reopened.dispatchTargetRunner.current
    compare(reopened.dispatchOpenFromRuns(), true)
    checkTargetCleared(reopened, "reopened")
    reply(lateReopen, treeReply(treeData()), 0)
    compare(reopened.dispatchStep, "project", "a reply after a reopening is dropped")
    checkTargetCleared(reopened, "a reply after a reopening")

    var dropped = pickedStore(tc.rootB); if (!dropped) return
    var lateDropped = dropped.dispatchTargetRunner.current
    dropped.projectRoots = registry([tc.rootA])
    compare(dropped.dispatchStep, "project")
    compare(dropped.dispatchRoot, "")
    checkTargetCleared(dropped, "registry fallback")
    reply(lateDropped, treeReply(treeData()), 0)
    compare(dropped.dispatchStep, "project", "a reply after the registry fallback is dropped")
    checkTargetCleared(dropped, "a reply after the registry fallback")
  }

```

- [ ] **Step 2: Run them to verify they fail**

Run: `Q StoresRunStore::test_dispatch_back_from_target_cancels_the_read StoresRunStore::test_dispatch_target_stale_replies_are_dropped`
Expected: both FAIL: the first on `Back cancels the read` (loading is still true), the second on `closed: target loading` (`closeDispatch` leaves the read in flight).

- [ ] **Step 3: Clear the target data on Back from the target step**

Replace `dispatchBack` with its comment:

```qml
  // From the target step back to the project step, dispatchRoot "". The
  // probe and its rows stay and nothing is relaunched. Refused (false,
  // nothing changes) at any other step.
  function dispatchBack() {
    if (store.dispatchStep !== "target") return false
    store.dispatchStep = "project"
    store.dispatchRoot = ""
    return true
  }
```

with

```qml
  // From the target step back to the project step: dispatchRoot "" and the
  // target data cleared; the probe, its rows and the failures stay and
  // nothing is relaunched. Refused (false, nothing changes) at any other
  // step.
  function dispatchBack() {
    if (store.dispatchStep !== "target") return false
    store.dispatchClearTarget()
    store.dispatchStep = "project"
    store.dispatchRoot = ""
    return true
  }
```

- [ ] **Step 4: Clear it on every step clear and every opening from Runs**

Replace Task 2's `dispatchClearSteps` with its comment:

```qml
  // The steps cleared: the probe cancelled, dispatchStep "",
  // dispatchProjectProbe null and dispatchProjectFailures {}.
  function dispatchClearSteps() {
    dispatchProjectRunner.cancel()
    store.dispatchStep = ""
    store.dispatchProjectProbe = null
    store.dispatchProjectFailures = {}
  }
```

with

```qml
  // The steps cleared: the probe cancelled, the target data cleared,
  // dispatchStep "", dispatchProjectProbe null and dispatchProjectFailures {}.
  function dispatchClearSteps() {
    dispatchProjectRunner.cancel()
    store.dispatchClearTarget()
    store.dispatchStep = ""
    store.dispatchProjectProbe = null
    store.dispatchProjectFailures = {}
  }
```

Replace Task 2's head of `dispatchOpenFromRuns`:

```qml
  // Opens the dispatch from Runs at the project step with no root and no
  // failures, and probes every usable root, in registry order. Refused
  // (false, nothing changes) while a start is in flight; else true, from
  // any state or step: a second call starts the step over. With no usable
  // root nothing is launched and the rows are [].
  function dispatchOpenFromRuns() {
    if (store.dispatchState === "starting") return false
    store.resetDispatch()
    store.dispatchRoot = ""
    store.dispatchStep = "project"
    store.dispatchProjectProbe = null
    store.dispatchProjectFailures = {}
```

with

```qml
  // Opens the dispatch from Runs at the project step with no root, no
  // failures and the target data cleared, and probes every usable root, in
  // registry order. Refused (false, nothing changes) while a start is in
  // flight; else true, from any state or step: a second call starts the
  // step over. With no usable root nothing is launched and the rows are [].
  function dispatchOpenFromRuns() {
    if (store.dispatchState === "starting") return false
    store.resetDispatch()
    store.dispatchRoot = ""
    store.dispatchStep = "project"
    store.dispatchProjectProbe = null
    store.dispatchProjectFailures = {}
    store.dispatchClearTarget()
```

- [ ] **Step 5: Clear it on the registry fallback**

Replace `dispatchRegistryChanged` with its comment:

```qml
  // The registry changed: at the target step, a dispatchRoot that is no
  // longer a usable root (trailing "/" removed) goes back to the project
  // step with dispatchRoot "". Any other step is left alone.
  function dispatchRegistryChanged() {
    if (store.dispatchStep !== "target") return
    var rows = Runs.dispatchProjects(store.usableRoots(), null, "")
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].root === store.dispatchRoot) return
    }
    store.dispatchStep = "project"
    store.dispatchRoot = ""
  }
```

with

```qml
  // The registry changed: at the target step, a dispatchRoot that is no
  // longer a usable root (trailing "/" removed) goes back to the project
  // step with dispatchRoot "" and the target data cleared. Any other step
  // is left alone.
  function dispatchRegistryChanged() {
    if (store.dispatchStep !== "target") return
    var rows = Runs.dispatchProjects(store.usableRoots(), null, "")
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].root === store.dispatchRoot) return
    }
    store.dispatchClearTarget()
    store.dispatchStep = "project"
    store.dispatchRoot = ""
  }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `Q StoresRunStore::test_dispatch_back_from_target_cancels_the_read StoresRunStore::test_dispatch_target_stale_replies_are_dropped StoresRunStore::test_dispatch_back_from_target StoresRunStore::test_dispatch_registry_change_while_open_drops_the_row`
Expected: all PASS, `0 failed`.

Run: `Q 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: `Totals: 331 passed, 0 failed`, nothing else.

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): Back, a step clear and the registry fallback drop the tree read"
```

---

### Task 4: `dispatchTargetPick` opens S3's form for the picked project

**Files:**
- Modify: `core/stores/RunStore.qml` section `// ---- dispatch: project and target steps`, between `dispatchTargetReplied` and `dispatchBack`
- Test: `tests/core/stores/tst_run_store.qml`, the 2.3 block

**Interfaces:**
- Consumes: `store.dispatchOpenFor(card, cardMap) -> bool` (2.1, `RunStore.qml:1532`; sets `dispatchTarget`, `dispatchTargetLabel`, `dispatchForm`, launches `--defaults <dispatchRoot>` and, when `dispatchRoot !== project`, `get-run-settings <dispatchRoot>`), `store.resetDispatch()`; test helpers `targetStore`, `pickedStore`, `bSettings()`, `defaultsOk(branch)`, `startOk(runId, message)`, `allReply`, `okEntry`, `previewCmd`, `viewerCmd`, `startCmd`, `snapCmd`, `bPreviewArgs`.
- Produces: `function dispatchTargetPick(key) -> bool` (Task 5 relies on it setting `dispatchStep = "form"` and `dispatchTargetKey = key`).

- [ ] **Step 1: Write the failing tests**

In the 2.3 block, right after `test_dispatch_target_stale_replies_are_dropped`, insert:

```qml
  // 2.3 test 3
  function test_dispatch_target_pick_enters_the_form_for_another_project() {
    var store = targetStore(tc.rootB); if (!store) return
    var rows = store.dispatchTargetRows
    var map = store.dispatchTargetCardMap
    compare(store.dispatchTargetPick("card:m1"), true)
    compare(store.dispatchStep, "form")
    compare(store.dispatchTargetKey, "card:m1")
    compare(store.dispatchRoot, tc.rootB)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "milestone")
    compare(store.dispatchTargetLabel, Runs.dispatchLabel(map.m1, map))
    compare(store.dispatchTargetLabel, "Milestone \"M3 Document runs\"")
    compare(argv(store.dispatchDefaultsRunner.current), tc.previewCmd + "--defaults|/home/u/b")
    compare(argv(store.dispatchSettingsRunner.current), tc.viewerCmd + "get-run-settings|/home/u/b")
    reply(store.dispatchSettingsRunner.current, bSettings(), 0)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchForm.parallelism, 2, "B's settings, not A's")
    compare(store.dispatchForm.verify.join(","), "make test")
    compare(store.dispatchForm.prefix, "bpre")
    compare(store.dispatchForm.base, "main")
    compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.bPreviewArgs, "B's milestone is previewed")
    verify(store.dispatchTargetRows === rows, "the rows stay")
    verify(store.dispatchTargetCardMap === map, "the card map stays")

    var board = targetStore(tc.rootB); if (!board) return
    compare(board.dispatchTargetPick("board"), true)
    compare(board.dispatchStep, "form")
    compare(board.dispatchTargetKey, "board")
    compare(board.dispatchTarget.level, "board")
    compare(board.dispatchTargetLabel, "Whole board")
  }

  // 2.3 test 4
  function test_dispatch_target_pick_for_the_open_project_and_refusals() {
    var store = pickedStore(tc.rootA); if (!store) return
    compare(store.dispatchTargetPick("board"), false, "no pick while loading")
    compare(store.dispatchStep, "target")
    compare(store.dispatchTargetLoading, true)
    reply(store.dispatchTargetRunner.current, treeReply(treeData()), 0)
    var refused = ["card:t2", "card:zz", "", "t1", null, 7]
    for (var i = 0; i < refused.length; i++) {
      compare(store.dispatchTargetPick(refused[i]), false, "key " + refused[i])
      compare(store.dispatchStep, "target", "key " + refused[i] + ": step")
      compare(store.dispatchTargetKey, "", "key " + refused[i] + ": key")
      compare(store.dispatchState, "idle", "key " + refused[i] + ": state")
    }
    verify(!store.dispatchDefaultsRunner.current, "a refused pick launches nothing")
    compare(store.dispatchTargetPick("card:t1"), true)
    compare(store.dispatchStep, "form")
    compare(store.dispatchTargetKey, "card:t1")
    compare(store.dispatchTarget.level, "subtask")
    compare(store.dispatchTargetLabel, "Subtask \"RunStore dispatch\"")
    verify(!store.dispatchSettingsRunner.current, "the open project's runSettings are used")
    compare(argv(store.dispatchDefaultsRunner.current), tc.previewCmd + "--defaults|/home/u/my proj")
    compare(store.dispatchForm.prefix, "old", "A's prefix history")
    compare(store.dispatchForm.parallelism, 4)
    var defaults = store.dispatchDefaultsRunner.current
    compare(store.dispatchTargetPick("card:m1"), false, "no pick at the form")
    compare(store.dispatchTargetKey, "card:t1")
    compare(store.dispatchTarget.level, "subtask")
    verify(store.dispatchDefaultsRunner.current === defaults, "nothing relaunched")

    var idle = runsStore(); if (!idle) return
    compare(idle.dispatchTargetPick("board"), false, "no pick without a step")
    checkDispatchIdle(idle, "no step")
  }

  // 2.3 test 11
  function test_dispatch_start_from_runs_refreshes_only_its_root() {
    var store = targetStore(tc.rootB); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    compare(store.dispatchTargetPick("card:t1"), true)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchSettingsRunner.current, bSettings(), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(argv(runner.current), tc.startCmd + "/home/u/b|card|t1|--base-branch|main|--branch-prefix|bpre|--max-concurrent|2|--verify|make test")
    var seq = store.snapshotRunner.seq
    reply(runner.current, startOk("r9", ""), 0)
    compare(store.dispatchState, "started")
    compare(store.dispatchRunId, "r9")
    compare(store.snapshotRunner.seq, seq + 1, "one snapshot is asked for")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|/home/u/b", "of B only")
    compare(store.dispatchStep, "form")
  }

```

- [ ] **Step 2: Run them to verify they fail**

Run: `Q StoresRunStore::test_dispatch_target_pick_enters_the_form_for_another_project StoresRunStore::test_dispatch_target_pick_for_the_open_project_and_refusals StoresRunStore::test_dispatch_start_from_runs_refreshes_only_its_root`
Expected: all three FAIL with `Property 'dispatchTargetPick' of object RunStore_QMLTYPE_... is not a function`.

- [ ] **Step 3: Implement `dispatchTargetPick`**

Right before the line `  // From the target step back to the project step: dispatchRoot "" and the` (the comment of `dispatchBack` after Task 3), insert:

```qml
  // Takes the target step's row with this key: dispatchOpenFor(row.card,
  // dispatchTargetCardMap) opens S3's form for dispatchRoot, the step is
  // form and dispatchTargetKey the key; the rows and the card map stay.
  // Refused (false, nothing changes) at any other step and for a key no row
  // has. When dispatchOpenFor refuses, the dispatch is reset, the step stays
  // target and it returns false.
  function dispatchTargetPick(key) {
    if (store.dispatchStep !== "target") return false
    var rows = store.dispatchTargetRows
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].key !== key) continue
      if (!store.dispatchOpenFor(rows[i].card, store.dispatchTargetCardMap)) {
        store.resetDispatch()
        return false
      }
      store.dispatchTargetKey = key
      store.dispatchStep = "form"
      return true
    }
    return false
  }

```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Q StoresRunStore::test_dispatch_target_pick_enters_the_form_for_another_project StoresRunStore::test_dispatch_target_pick_for_the_open_project_and_refusals StoresRunStore::test_dispatch_start_from_runs_refreshes_only_its_root`
Expected: all PASS, `0 failed`.

Run: `Q 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: `Totals: 334 passed, 0 failed`, nothing else.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): dispatchTargetPick opens the form for the picked project's target"
```

---

### Task 5: Back from the form and the registry fallback at the form

**Files:**
- Modify: `core/stores/RunStore.qml` section `// ---- dispatch: project and target steps`: `dispatchBack`, `dispatchRegistryChanged`
- Test: `tests/core/stores/tst_run_store.qml`: two assertions in the 2.2 block, and the 2.3 block

**Interfaces:**
- Consumes: `dispatchTargetPick(key)` (Task 4), `dispatchClearTarget()` (Task 1), `store.resetDispatch()`, `store.dispatchStart()`; test helpers `targetStore`, `checkDispatchFieldsIdle`, `checkTargetCleared`, `rowsText`, `registry(roots)`, `bSettings()`, `defaultsOk`, `startOk`.
- Produces: `dispatchBack()` from `form`, `dispatchRegistryChanged()` at `form`.

- [ ] **Step 1: Update the two 2.2 assertions that left these rules to 2.3**

In `test_dispatch_back_from_target` (the `form` store at its end), replace

```qml
    compare(form.dispatchBack(), false, "Back from the form is 2.3's")
    compare(form.dispatchStep, "form")
```

with

```qml
    compare(form.dispatchBack(), true, "Back from the form returns to the target step")
    compare(form.dispatchStep, "target")
```

In `test_dispatch_registry_change_while_open_drops_the_row` (its last lines, after `store.dispatchStep = "form"` and `store.projectRoots = registry([tc.rootB])`), replace

```qml
    compare(store.dispatchStep, "form", "the form's registry rule is 2.3's")
    compare(store.dispatchRoot, tc.rootA)
```

with

```qml
    compare(store.dispatchStep, "project", "the picked root left the form: back to step 1")
    compare(store.dispatchRoot, "")
```

- [ ] **Step 2: Write the failing tests**

In the 2.3 block, right after `test_dispatch_start_from_runs_refreshes_only_its_root`, insert:

```qml
  // 2.3 test 9
  function test_dispatch_back_from_form_keeps_the_picked_row() {
    var store = targetStore(tc.rootB); if (!store) return
    var rows = store.dispatchTargetRows
    var map = store.dispatchTargetCardMap
    var treeSeq = store.dispatchTargetRunner.seq
    compare(store.dispatchTargetPick("card:m1"), true)
    var defaults = store.dispatchDefaultsRunner.current
    var settings = store.dispatchSettingsRunner.current
    compare(store.dispatchBack(), true)
    compare(store.dispatchStep, "target")
    compare(store.dispatchRoot, tc.rootB)
    compare(store.dispatchTargetKey, "card:m1", "the picked row is kept")
    verify(store.dispatchTargetRows === rows, "the rows are kept")
    verify(store.dispatchTargetCardMap === map, "the card map is kept")
    compare(store.dispatchTargetLoading, false)
    compare(store.dispatchTargetRunner.seq, treeSeq, "the tree is not read again")
    checkDispatchFieldsIdle(store, "Back from the form")
    reply(defaults, defaultsOk("main"), 0)
    reply(settings, bSettings(), 0)
    compare(store.dispatchState, "idle", "the form's lookups are dropped")
    compare(store.dispatchForm, null)
    compare(store.dispatchTargetPick("card:s1"), true)
    compare(store.dispatchTarget.level, "story")
    compare(store.dispatchTargetKey, "card:s1")

    var starting = targetStore(tc.rootB); if (!starting) return
    compare(starting.dispatchTargetPick("card:t1"), true)
    reply(starting.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(starting.dispatchSettingsRunner.current, bSettings(), 0)
    compare(starting.dispatchStart(), true)
    compare(starting.dispatchBack(), false, "no Back while starting")
    compare(starting.dispatchStep, "form")
    compare(starting.dispatchState, "starting")
    compare(starting.dispatchTargetKey, "card:t1")
  }

  // 2.3 test 10
  function test_dispatch_registry_change_at_form() {
    var store = targetStore(tc.rootB); if (!store) return
    compare(store.dispatchTargetPick("card:m1"), true)
    var defaults = store.dispatchDefaultsRunner.current
    store.projectRoots = registry([tc.rootB, tc.rootA])
    compare(store.dispatchStep, "form", "a reorder keeps the form")
    compare(store.dispatchRoot, tc.rootB)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTargetKey, "card:m1")
    store.projectRoots = registry([tc.rootA])
    compare(store.dispatchStep, "project", "the picked root left: back to step 1")
    compare(store.dispatchRoot, "")
    checkDispatchFieldsIdle(store, "dropped at the form")
    checkTargetCleared(store, "dropped at the form")
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on:", "B's row is gone")
    reply(defaults, defaultsOk("main"), 0)
    compare(store.dispatchState, "idle", "the form's lookup is dropped")

    var starting = targetStore(tc.rootB); if (!starting) return
    compare(starting.dispatchTargetPick("card:t1"), true)
    reply(starting.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(starting.dispatchSettingsRunner.current, bSettings(), 0)
    compare(starting.dispatchStart(), true)
    var runner = starting.dispatchStartRunners[0]
    starting.projectRoots = registry([tc.rootA])
    compare(starting.dispatchStep, "form", "a start in flight keeps the form")
    compare(starting.dispatchState, "starting")
    compare(starting.dispatchRoot, tc.rootB)
    compare(starting.dispatchTargetKey, "card:t1")
    reply(runner.current, startOk("r9", ""), 0)
    compare(starting.dispatchState, "started", "the start completes for its root")
  }

```

- [ ] **Step 3: Run them to verify they fail**

Run: `Q StoresRunStore::test_dispatch_back_from_form_keeps_the_picked_row StoresRunStore::test_dispatch_registry_change_at_form StoresRunStore::test_dispatch_back_from_target StoresRunStore::test_dispatch_registry_change_while_open_drops_the_row`
Expected: all four FAIL: `test_dispatch_back_from_form_keeps_the_picked_row` with `Compared values are not the same` (Back at `form` returns false), `test_dispatch_back_from_target` on `Back from the form returns to the target step`, `test_dispatch_registry_change_at_form` on `the picked root left: back to step 1`, `test_dispatch_registry_change_while_open_drops_the_row` on `the picked root left the form: back to step 1`.

- [ ] **Step 4: Back from the form**

Replace Task 3's `dispatchBack` with its comment:

```qml
  // From the target step back to the project step: dispatchRoot "" and the
  // target data cleared; the probe, its rows and the failures stay and
  // nothing is relaunched. Refused (false, nothing changes) at any other
  // step.
  function dispatchBack() {
    if (store.dispatchStep !== "target") return false
    store.dispatchClearTarget()
    store.dispatchStep = "project"
    store.dispatchRoot = ""
    return true
  }
```

with

```qml
  // From the target step back to the project step: dispatchRoot "" and the
  // target data cleared; the probe, its rows and the failures stay and
  // nothing is relaunched. From the form back to the target step: the
  // dispatch reset (resetDispatch), dispatchRoot, the rows, the card map and
  // dispatchTargetKey kept, nothing relaunched; refused while starting.
  // Refused (false, nothing changes) at any other step.
  function dispatchBack() {
    if (store.dispatchStep === "form") {
      if (store.dispatchState === "starting") return false
      store.resetDispatch()
      store.dispatchStep = "target"
      return true
    }
    if (store.dispatchStep !== "target") return false
    store.dispatchClearTarget()
    store.dispatchStep = "project"
    store.dispatchRoot = ""
    return true
  }
```

- [ ] **Step 5: The registry fallback at the form**

Replace Task 3's `dispatchRegistryChanged` with its comment:

```qml
  // The registry changed: at the target step, a dispatchRoot that is no
  // longer a usable root (trailing "/" removed) goes back to the project
  // step with dispatchRoot "" and the target data cleared. Any other step
  // is left alone.
  function dispatchRegistryChanged() {
    if (store.dispatchStep !== "target") return
    var rows = Runs.dispatchProjects(store.usableRoots(), null, "")
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].root === store.dispatchRoot) return
    }
    store.dispatchClearTarget()
    store.dispatchStep = "project"
    store.dispatchRoot = ""
  }
```

with

```qml
  // The registry changed: at the target step, and at the form unless a
  // start is in flight, a dispatchRoot that is no longer a usable root
  // (trailing "/" removed) goes back to the project step with dispatchRoot
  // "" and the target data cleared; at the form the dispatch is reset too.
  // Any other step, and the form while starting, is left alone.
  function dispatchRegistryChanged() {
    var step = store.dispatchStep
    if (step !== "target" && step !== "form") return
    if (step === "form" && store.dispatchState === "starting") return
    var rows = Runs.dispatchProjects(store.usableRoots(), null, "")
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].root === store.dispatchRoot) return
    }
    if (step === "form") store.resetDispatch()
    store.dispatchClearTarget()
    store.dispatchStep = "project"
    store.dispatchRoot = ""
  }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `Q StoresRunStore::test_dispatch_back_from_form_keeps_the_picked_row StoresRunStore::test_dispatch_registry_change_at_form StoresRunStore::test_dispatch_back_from_target StoresRunStore::test_dispatch_registry_change_while_open_drops_the_row StoresRunStore::test_dispatch_close_and_card_entry_clear_the_steps`
Expected: all PASS, `0 failed`.

Run: `Q 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: `Totals: 336 passed, 0 failed`, nothing else.

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): Back from the form returns to the target step and the registry fallback covers the form"
```

---

### Task 6: Header comment, architecture doc and the full gate

**Files:**
- Modify: `core/stores/RunStore.qml:33-38` (header comment)
- Modify: `docs/architecture.md:92`

**Interfaces:**
- Consumes: everything above. Produces: no code.

- [ ] **Step 1: The store's header comment**

In `core/stores/RunStore.qml`, replace

```qml
// one HelperRunner per Start. It also opens from Runs with no root
// (dispatchOpenFromRuns): a probe of every usable root (board-tree.py
// --probe) gives the project step's rows, and dispatchProjectPick sets
// dispatchRoot. A dispatch opened from Runs survives a project switch.
```

with

```qml
// one HelperRunner per Start. It also opens from Runs with no root
// (dispatchOpenFromRuns): a probe of every usable root (board-tree.py
// --probe) gives the project step's rows; dispatchProjectPick sets
// dispatchRoot and reads its tree (board-tree.py ROOT, guarded by
// dispatchRoot), whose target rows dispatchTargetPick opens S3's form on;
// a failed tree read disables that project's row. A dispatch opened from
// Runs survives a project switch.
```

- [ ] **Step 2: The architecture doc**

In `docs/architecture.md` line 92, replace this exact text:

```text
`dispatchProjectRows` is `Runs.dispatchProjects` over the usable roots, the probe's envelope (`null` before its reply or when it is unreadable: every row enabled) and `project`, `dispatchProjectPick(root)` takes an enabled row (`dispatchRoot` = its root, step `target`, nothing launched), `dispatchBack()` goes from `target` back to `project` keeping the probe, and a registry change that drops the picked root does the same; `dispatchState` stays `idle` at both steps.
```

with:

```text
`dispatchProjectRows` is `Runs.dispatchProjects` over the usable roots, the probe's envelope (`null` before its reply or when it is unreadable: every row enabled) and `project`, a root in `dispatchProjectFailures` (`{root: message}`, `{}` on every opening and clear) giving a disabled row with that message whatever the probe says. `dispatchProjectPick(root)` takes an enabled row (`dispatchRoot` = its root, step `target`) and reads its tree with `board-tree.py ROOT` on `dispatchTargetRunner` (guarded by `dispatchRoot`, latest wins; `dispatchTargetLoading` while it is in flight): a reply that is `{ok: true, data: [...]}` and that `Board.indexTree` can walk gives `dispatchTargetCardMap` (its `{id: card}` map) and `dispatchTargetRows` (`Runs.dispatchTargets`: the `board` row, then the offered cards in tree order); any other reply records the helper's message (`The board could not be read` when there is none) in `dispatchProjectFailures` and goes back to `project` with `dispatchRoot` `""`. `dispatchTargetPick(key)` takes a target row: `dispatchOpenFor(row.card, dispatchTargetCardMap)`, step `form`, `dispatchTargetKey` its key. `dispatchBack()` goes from `target` back to `project` keeping the probe and clearing the target data (a read in flight is cancelled), and from `form` (refused while `starting`) back to `target` with the dispatch reset and the rows, the card map and `dispatchTargetKey` kept; a registry change that drops the picked root at `target`, or at `form` except while `starting`, goes back to `project` with the dispatch reset and the target data cleared. `dispatchState` stays `idle` at the `project` and `target` steps.
```

and, later in the same line, replace

```text
put the dispatch back to `idle`, `dispatchRoot` back to `""` and `dispatchStep` back to `""`;
```

with

```text
put the dispatch back to `idle`, `dispatchRoot` back to `""` and `dispatchStep` back to `""`, with the probe, the target data and `dispatchProjectFailures` cleared;
```

Each old text occurs exactly once in the file: `grep -c 'nothing launched)' docs/architecture.md` prints `1` before the first replacement and `0` after it.

- [ ] **Step 3: Run the store tests**

Run: `Q 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: `Totals: 336 passed, 0 failed`, nothing else.

- [ ] **Step 4: Run the full gate**

Run: `timeout 900 bash tests/run.sh 2>&1 | tail -60`
Expected: pytest reports no failures (including `tests/architecture/test_layers.py`, which accepts the new `"../domain/board.js"` import in a store), every `== tests/...` QML file prints a `Totals:` line with `0 failed`, no `FAIL`, `TypeError` or `ReferenceError` line, and the command exits 0 (`echo $?` prints `0`).

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml docs/architecture.md
git commit -m "docs(runs): the target step's tree read, target pick and failures"
```

---

## Self-review (against the spec)

**Spec coverage.**

| Spec requirement | Task |
|---|---|
| State: `dispatchTargetCardMap`, `dispatchTargetRows`, `dispatchTargetLoading`, `dispatchTargetKey`, alias `dispatchTargetRunner` | 1 |
| State: `dispatchProjectFailures`; failed root's row `off` with the message whatever the probe says | 2 |
| `dispatchProjectPick` clears the target data, launches `board-tree.py <dispatchRoot>`, guard set first, `idle`, no other runner | 1 (test 1) |
| Runner contract (latest wins, guard `dispatchRoot`, Back/clear/fallback cancel) | 1 (runner), 3 (tests 6, 7) |
| Reply applied only at `target`; success → map and rows; empty tree → `board` only | 1 (test 2) |
| Failure (unreadable, `ok !== true`, no array `data`, `indexTree` throws, blank message) → failure, cleared, step `project`, root `""`, probe untouched | 2 (test 5) |
| `dispatchTargetPick`: refusals, `dispatchOpenFor` hand-off, form for another root / for the open project, rows and map kept | 4 (tests 3, 4) |
| `dispatchTargetPick` guard when `dispatchOpenFor` refuses (`resetDispatch`, step kept) | 4 (code; untested by design, spec) |
| `dispatchBack` from `target` clears target data; from `form` resets, keeps rows/map/key; refused while `starting` | 3 (test 6), 5 (test 9) |
| `dispatchClearSteps` clears target data and failures; `closeDispatch`, `stopLive`, `openDispatch` inherit it | 2, 3 (tests 5, 7) |
| `dispatchOpenFromRuns` clears target data and failures | 2, 3 (tests 5, 7) |
| `dispatchRegistryChanged` at `form` (not `starting`) | 5 (test 10) |
| `projectSwitched` unchanged; read in flight still applies | 1 (test 8) |
| `retargetToMilestone` unchanged (keeps `dispatchTargetKey`) | no code change; `dispatchTargetKey` is only written by `dispatchTargetPick` and `dispatchClearTarget`, neither of which `retargetToMilestone` calls |
| `started` refreshes `[dispatchRoot]` only | 4 (test 11) |
| `checkDispatchIdle` gains the four target checks | 1 |
| Header comment, member comments, ARCH l.92 | 1-5 (comments), 6 |
| `import "../domain/board.js" as Board` only; `tests/architecture` and `bash tests/run.sh` green | 1, 6 |

**Placeholder scan.** No "TBD", "TODO", "similar to", or step without its code. Every replaced block is quoted in full, old and new.

**Type consistency.** `dispatchClearTarget()` (Task 1) is the name used in Tasks 2, 3, 5. `dispatchTargetReplied(stdout)` is called by the runner with `stdout` only. `dispatchProbeEntries()` is defined in Task 2 in the same step as the binding that calls it. Test helpers are defined in Task 1 and used by name in Tasks 2-5: `pickedStore`, `targetStore`, `treeReply`, `treeFail`, `treeData`, `targetKeys`, `checkTargetCleared`, `checkDispatchFieldsIdle`.

**Review Focus.** Each of its five lines has its pinned test in the owning task (1, 2, 2, 3, 5).
<!-- task-pipeline: validated -->
