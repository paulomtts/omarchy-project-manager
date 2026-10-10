# 2.3 RunStore dispatch: the target step — design

Card: `c3f687b6` (subtask of story `8200b9d4`, the last of its three). It builds on 2.1
(`abbba4c7`, `docs/superpowers/specs/2-1-runstore-dispatch-abbba4c7.md`) and 2.2 (`080cfe16`,
`docs/superpowers/specs/2-2-runstore-dispatch-080cfe16.md`, cited as "2.2 spec"), both merged on
this branch. Parent design: `docs/superpowers/specs/2026-10-05-dispatch-from-runs-design.md`,
cited as "DFR l.N". The store contract today is `docs/architecture.md:92`, cited as "ARCH l.92".
Code lines are on this branch at `3be444d`.

## Purpose

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

## Inherited constraints

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

## Behaviour

### State

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

### `dispatchProjectPick(root)` (extended)

2.2's refusals are unchanged: false, nothing changes, nothing launched. They cover a wrong step,
an unknown root, a disabled row, and now also a row disabled by `dispatchProjectFailures`.

On success it sets `dispatchRoot` and `dispatchStep = "target"` as before. Then it clears the
target data and launches the tree read on `dispatchTargetRunner` with argv
`python3 <backendDir>boards/board-tree.py <dispatchRoot>` (no `--probe`). The guard is the new
`dispatchRoot`, so `dispatchRoot` is set before `run()`. `dispatchTargetLoading` is true and
`dispatchTargetRows` is `[]` until the reply. It returns true. `dispatchState` stays `idle`, and
no defaults, settings or preview runner is launched.

### `dispatchTargetRunner` and `dispatchTargetReplied(stdout)`

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

### `dispatchTargetPick(key)`

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

### `dispatchBack()` (extended)

- From `target`: as in 2.2, step `project` and `dispatchRoot ""`, with the probe and the project
  rows kept (failure marks included) and nothing relaunched. In addition, the target data is
  cleared, which cancels a tree read in flight. Its late reply is dropped. It returns true.
- From `form`: refused (false, nothing changes) while `dispatchState === "starting"`, as
  `closeDispatch` is. Otherwise it calls `resetDispatch()` (S3's fields back to "none", its
  runners cancelled, `dispatchRoot` kept), sets `dispatchStep = "target"`, and returns true.
  `dispatchTargetRows`, `dispatchTargetCardMap` and `dispatchTargetKey` are kept, and no tree
  read is launched.
- At `""` and `project` it returns false and nothing changes (2.2).

### Clearing and the other entry points

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

### Docs and comments

- `RunStore.qml` header (`:33-38`): the pick reads the picked root's tree (`board-tree.py ROOT`,
  guarded by `dispatchRoot`). `dispatchTargetPick` opens S3's form on a target row. A failed
  read disables that project's row.
- Each new or changed member gets a contract comment in the section's style
  (`RunStore.qml:1862-1955`).
- ARCH l.92: extend the Runs sentence with the tree read and its argv, `dispatchTargetRows` /
  `dispatchTargetCardMap` / `dispatchTargetLoading` / `dispatchTargetKey`,
  `dispatchTargetPick(key)` → `dispatchOpenFor` and step `form`, a failure disabling the row
  with the helper's message, Back from `form` to `target`, and the registry fallback at `form`.

## Errors and edge cases

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

## Tests

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

## Out of scope

- `DispatchDialog`, `RunsScreen`, `Shortcuts`, `Panel`: the steps' UI, the filter, the "Reading
  the board…" text and the cursor (cards 3.1, 3.2). User docs (3.4).
- `board-tree.py`, `runs.js` (`dispatchProjects`, `dispatchTargets`) and `board.js`: no change.
- Changing the `started` refresh from per-root to global (DFR l.107-109): not this card. The
  code keeps `requestSnapshot([dispatchRoot])`.
- How `dispatchSettingsSource()` behaves when the open project switches while a Runs-opened
  form is up: S3/2.1's rule, unchanged.
- Relaunching `in_progress` subtasks, and skipping step 1 with one project (DFR l.258-263).
- The `RunDispatchStore` split.
