# 2.2 RunStore dispatch: the project step — design

Card: `080cfe16` (subtask of story `8200b9d4`). It builds on 2.1 (`abbba4c7`,
`docs/superpowers/specs/2-1-runstore-dispatch-abbba4c7.md`, merged on this branch), and 2.3
(`c3f687b6`, the target step) builds on it.
Parent design: `docs/superpowers/specs/2026-10-05-dispatch-from-runs-design.md`, cited below as
"DFR l.N". The store contract today is `docs/architecture.md:92` ("Dispatch (S3 3.1)"), cited as
"ARCH l.92". Code lines are on this branch at `35f149d`.

## Purpose

The Runs-screen dispatch starts at a project step (DFR l.67-79). This card gives `RunStore` the
store side of that step. `dispatchOpenFromRuns()` opens a dialog with no root. It probes every
registered root once and exposes the step's rows. `dispatchProjectPick(root)` takes an enabled
row and moves to the target step. `dispatchBack()` returns from the target step. A dialog opened
from Runs survives a switch of the open project. Nothing in `ui/` calls these members yet; the
UI is card 3.1.

## Inherited constraints

- The new members go in a delimited section with the header line
  `// ---- dispatch: project and target steps`. It sits right after S3's dispatch section,
  holds only its own members, and every member is prefixed `dispatch*` (DFR l.185-193; card).
  S3's section is `// ---- dispatch (S3 3.1)` (`core/stores/RunStore.qml:1447`) and ends with
  `dropStartRunner` (`:1843-1847`). The new section goes right after it, before the
  `snapshotRunner` declaration (`:1849-1856`). Its property declarations, its functions, its
  `HelperRunner` and the runner's alias all go inside the section, so the split can lift it out
  whole.
- This card's members are `dispatchStep`, `dispatchOpenFromRuns()`, `dispatchBack()`,
  `dispatchProjectProbe`, `dispatchProjectRows`, `dispatchProjectRunner`,
  `dispatchProjectReplied(…)` and `dispatchProjectPick(root)` (DFR l.193, l.200-205). The
  `dispatchTarget*` members of that row belong to 2.3.
- `dispatchStep` is `project` | `target` | `form` (DFR l.200). The inputs are members the store
  already has: `projectRoots` (S6, bound by App) and `project`. There is no new App binding
  (DFR l.201-203).
- `dispatchProjectRunner` runs `board-tree.py --probe` with latest wins (DFR l.204). The probe
  never runs brd. It prints `{"ok": true, "projects": [{root, ok, reason?}]}` in argv order
  (DFR l.153-156, `core/backend/boards/board-tree.py:63-72`).
- The rows are `Runs.dispatchProjects(projectRoots, probe, openRoot)`: `{root, name, open,
  enabled, reason}`, with the open project first. A root missing from the probe counts as
  enabled (DFR l.176-178, `core/domain/runs.js:500-536`). Disabled rows ignore a pick
  (DFR l.73-74).
- The Runs entry point leaves `dispatchRoot` empty until step 1 picks (DFR l.198-199).
- **Guard.** A dialog opened from Runs ignores a switch of the open project. The dispatch's
  project-switch reaction, in or beside `projectSwitched()`, skips a dialog whose
  `dispatchStep` is not empty. A dialog opened from a card keeps S3's behaviour on a project
  switch (DFR l.209-212; card).
- If the picked project leaves the registry while the dialog is open, the dialog returns to
  step 1 and the row is gone (DFR l.236).
- Layering follows `docs/architecture.md`. The store imports no other store, and only
  `../domain/runs.js` is used. `tests/architecture` must pass, and `bash tests/run.sh` must be
  green. Tests come first. Comments state the contract only, with no narrative (card).

## Behaviour

### State

All of the following is declared in the new section.

- `property string dispatchStep: ""`. It is `"project"` or `"target"` while a dialog opened
  from Runs is at that step. It is `"form"` once 2.3's target pick hands over to S3's form. It
  is `""` otherwise: idle, a card entry, or after a close. Comment: "the Runs dialog's step:
  project | target | form; "" when the dispatch was not opened from Runs (idle or a card
  entry)".
- `property var dispatchProjectProbe: null` holds the latest probe envelope read by
  `dispatchProjectReplied`, or `null`. It is `null` before the reply, when the reply is
  unreadable, and whenever the step state is cleared.
- `readonly property var dispatchProjectRows` is a binding. While `dispatchStep !== ""` it is
  `Runs.dispatchProjects(store.usableRoots(), store.dispatchProjectProbe, store.project)`.
  Otherwise it is `[]`. Because it is a binding, the rows follow `projectRoots` (add, remove,
  rename, reorder), the probe and the open project (the `open` mark) with no extra code.
- `readonly property alias dispatchProjectRunner: dispatchProjectRunner`. Tests reach the
  runner's `.current` through it.
- `dispatchState` keeps S3's meaning. At the `project` and `target` steps it stays `"idle"`,
  and every S3 field keeps its "none" value. A dispatch is open when `dispatchState !== "idle"`
  or `dispatchStep !== ""`. The UI cards must use that test, not `dispatchState` alone.

### `dispatchOpenFromRuns()`

- It is refused while `dispatchState === "starting"`: it returns false and nothing changes.
- Otherwise it calls `resetDispatch()`, sets `dispatchRoot = ""`, `dispatchStep = "project"`
  and `dispatchProjectProbe = null`, and launches the probe. Then it returns true. It runs
  whether the dialog was idle, open from a card, or already open from Runs at any step. A second
  call starts the step over, and the newer probe wins.
- The probe argv is `python3 <backendDir>boards/board-tree.py --probe ROOT...`. The roots are
  `usableRoots()` in registry order, each root once, with no root starting with `-`.
- With no usable root it launches nothing and still returns true. The step is open with
  `dispatchProjectRows` `[]`, which is the UI's "No projects registered" state (DFR l.76-79).
- No project needs to be open.

### `dispatchProjectRunner` and `dispatchProjectReplied(stdout)`

- `HelperRunner`, `script: store.backendDir + "boards/board-tree.py"`, no guard (`""`): the probe
  does not depend on a root. Latest wins. Its contract comment says that, and that any step
  clear cancels it.
- `onFinished: function(stdout, exitCode) { store.dispatchProjectReplied(stdout) }`.
- `dispatchProjectReplied(stdout)` reads the reply with `store.parseEnvelope`. When the reply is
  an object with `ok === true` and an array `projects`, it sets `dispatchProjectProbe` to that
  object. Otherwise it sets `null`, and every row is enabled by `Runs.dispatchProjects`' rule.
  The exit code is not read: `board-tree.py` exits 0 whenever it printed a line. The reply is
  applied only while `dispatchStep !== ""`. It is also applied at the `target` step, so Back
  shows the probed rows.

### `dispatchProjectPick(root)`

- It succeeds only when `dispatchStep === "project"` and `dispatchProjectRows` has a row whose
  `root === root` with `enabled === true`. Then it sets `dispatchRoot = row.root`,
  `dispatchStep = "target"` and returns true. This card launches nothing on a pick. The tree
  read is 2.3's.
- Otherwise it returns false and nothing changes. That covers a disabled row, an unknown root,
  `""`, and any step other than `project`.
- A pick before the probe replies is allowed: a row with no probe entry is enabled.

### `dispatchBack()`

- From `target`, it sets `dispatchStep = "project"` and `dispatchRoot = ""`, then returns true.
  The probe and its rows are kept, and nothing is relaunched.
- At `""` or `project` it returns false and nothing changes. Step 1 has no Back (DFR l.50,
  Cancel only).
- At `form` it returns false in this card. 2.3 owns Back from the form, which keeps the picked
  target row.

### Clearing the steps

There is one new section function, `dispatchClearSteps()`. It cancels `dispatchProjectRunner`
and sets `dispatchStep = ""` and `dispatchProjectProbe = null`. A probe reply after a clear is
dropped by the runner's sequence.

- `closeDispatch()`, when it succeeds, resets the dispatch, sets `dispatchRoot = ""` and clears
  the steps. When it is refused (while `starting`), nothing changes. This also covers closing
  the panel, since `stopLive` calls `closeDispatch()`.
- `openDispatch(card, cardMap)`, the card entry, keeps its refusals (no project, `starting`). On
  the open path it clears the steps before it sets `dispatchRoot = project`. A card entry
  always has `dispatchStep === ""`.
- `resetDispatch()` and `dispatchOpenFor()` do not touch the step state. `dispatchOpenFor` is
  what 2.3's target pick calls, and it must keep `dispatchStep`.

### Project switch

`projectSwitched()` (`RunStore.qml:667-675`) still clears `runSettings` and reads the new
project's run settings on `runSettingsRunner` in every case. The dispatch reset (`resetDispatch()`
plus `dispatchRoot = ""`) happens only when `dispatchStep === ""`. A dialog opened from Runs
keeps its step, root, probe and S3 state, and its rows' `open` mark follows the new `project`.
The function's contract comment and the header comment say so.

### Registry change

The rows follow `projectRoots` through the binding, so a removed root's row disappears. No
probe is relaunched: a root added while the step is open has no probe entry and shows enabled.
At the `target` step, if `dispatchRoot` is no longer the root of a usable registry entry
(compared with trailing `/` removed, as `Runs.dispatchProjects` does), the store sets
`dispatchStep = "project"` and `dispatchRoot = ""`. Compute this from `usableRoots()`, not from
the rows binding, because the order of the change notifications is not guaranteed. This reaction
is a section function, `dispatchRegistryChanged()`. It is called from the end of
`registryChanged()` or from a second `onProjectRootsChanged` line in the section; the plan picks
one. At `""`, `project` and `form` it changes nothing in this card.

### Docs and comments

- `RunStore.qml` header (`:32-35`): the dispatch also opens from Runs with no root
  (`dispatchOpenFromRuns`), picks a project (`dispatchProjectPick`) after a probe of every
  usable root, and a Runs-opened dialog survives a project switch.
- `docs/architecture.md:92`: add one sentence on the steps (`dispatchStep`,
  `dispatchOpenFromRuns`, the probe argv, `dispatchProjectRows`, `dispatchProjectPick`,
  `dispatchBack`). Amend the last sentence: a project switch resets only a dispatch whose
  `dispatchStep` is `""`.

## Errors and edge cases

| case | behaviour |
|---|---|
| `dispatchOpenFromRuns` while `starting` | false, nothing changes, no probe |
| no usable root | true, step `project`, rows `[]`, no probe launched |
| probe unreadable, `ok` not true, or exit ≠ 0 with no line | probe `null`, every row enabled |
| a root the probe reports not ok | row disabled, reason the probe's (`not a directory`, `no .brd marker`) |
| reopened while a probe is in flight | the older reply is dropped (latest wins) |
| probe reply after `closeDispatch` / card entry | dropped (runner cancelled), step stays `""` |
| pick of a disabled, unknown or `""` root, or at the wrong step | false, nothing changes |
| registry entry with a trailing `/` | the probe gets it as registered; the row and `dispatchRoot` carry it trimmed |
| root removed while at `project` | its row goes, no relaunch |
| picked root removed while at `target` | back to `project`, `dispatchRoot` `""` |
| open project switched while the Runs dialog is open | step, root, probe kept; `runSettings` reloaded for the new project; `open` mark moves |
| open project switched under a card dialog | reset as today (2.1 test 1 unchanged) |

## Tests

Every test is in the **QML store tests** tier, `tests/core/stores/tst_run_store.qml`. The
behaviour is store state and helper argv, which only the store harness (stubbed `Process`,
`reply`, `argv`) can observe. `Runs.dispatchProjects` is already covered in `tst_runs.qml`
(card 1.2), so no domain test is added. The UI is unchanged, so no `tests/ui` test is added.
`board-tree.py` already has its pytest.

The new tests go in their own block, `// ---- dispatch: project and target steps (2.2)`, after
2.1's block (which ends at `:5628`) and before `// ---- list snapshots`. The block has a
`probeCmd` property, `"python3|/plugin/core/backend/boards/board-tree.py|--probe"`, and a
`probeReply(entries)` helper that prints `{"ok": true, "projects": entries}` + `"\n"`.
`checkDispatchIdle` gains `compare(store.dispatchStep, "", …)`. Every existing caller is in a
state with no step, so all existing tests stay unchanged.

1. **`test_dispatch_step_empty_for_idle_and_card_entry`**: a fresh store has step `""`, rows
   `[]` and probe `null`. On `dispatchStore()`, `openDispatch(m1)` leaves step `""` and rows
   `[]`.
2. **`test_dispatch_open_from_runs_argv_and_rows`**: projects A and B are registered, and A is
   open with its settings read. `dispatchOpenFromRuns()` returns true. Step is `project`,
   `dispatchRoot` is `""` and `dispatchState` is `idle`. The probe argv is
   `probeCmd + "|/home/u/my proj|/home/u/b"`. Before the reply the rows are
   `[A (open, enabled), B (enabled)]`. After `probeReply([{root: A, ok: true}, {root: B, ok:
   false, reason: "no .brd marker"}])`, B is disabled with that reason. A second store with no
   project open has no row marked `open`, and the rows are ordered by name.
3. **`test_dispatch_open_from_runs_with_no_root_and_while_starting`**: with an empty registry
   the call returns true, the step is `project`, the rows are `[]` and nothing is launched. On
   `readyStore()`, after `dispatchStart()`, the call returns false, the state is `starting`, the
   step is `""` and nothing is launched.
4. **`test_dispatch_project_probe_unreadable_and_latest_wins`**: an unreadable reply leaves the
   probe `null` and every row enabled. Opening twice and replying to the first process (B not
   ok) changes nothing. The second reply applies.
5. **`test_dispatch_project_pick`**: picking A (enabled) returns true, with step `target` and
   `dispatchRoot` A, and nothing is launched (no defaults or settings runner current). Picking
   B when it is disabled returns false with the step and root unchanged. Picking `"/nope"` or
   `""` returns false. Picking again at `target` returns false, and so does a pick at step
   `""`.
6. **`test_dispatch_back_from_target`**: pick B (enabled), then `dispatchBack()` returns true.
   The step is `project`, the root is `""`, the probe is the same object and the probe runner's
   `seq` has not changed. A second `dispatchBack()` at `project` returns false. On a store with
   no step it returns false.
7. **`test_dispatch_close_and_card_entry_clear_the_steps`**: from step `project`,
   `closeDispatch()` returns true, the step is `""`, the probe is `null` and the rows are `[]`.
   A late reply from the cancelled probe process leaves the probe `null`. Reopening and then
   calling `openDispatch(m1)` gives step `""` and `dispatchRoot` A. Reopening and then setting
   `active` from true to false (the panel closes) gives step `""`.
8. **`test_dispatch_registry_change_while_open_drops_the_row`**: at `project`, setting
   `projectRoots = registry([A])` removes B's row and launches no new probe (the `seq` is
   unchanged). Reopen with A and B, pick B, and drop B from the registry: the step is
   `project` and the root is `""`. Pick A, then reorder the registry: the step stays `target`
   with root A.
9. **`test_dispatch_open_project_switch_leaves_a_runs_dialog_alone`**: open from Runs, reply to
   the probe and pick B. Setting `project = rootC` (registered) leaves the step `target`, the
   root B and the probe kept. `runSettingsRunner` was launched with `get-run-settings|/home/u/c`.
   Back shows the rows with C marked `open`. Switching to `project = ""` also keeps the step.
   2.1 test 1 still shows that a card dialog is reset by the switch.
10. **`test_dispatch_rows_follow_project_roots`**: while at `project`, rename B (`name:
    "zeta"`), add C and reorder. The rows follow (names, membership, order by name with the
    open row first), with no new probe. C is enabled, because it has no probe entry. An entry
    `{root: "-x"}` gives no row and is not in the probe argv when the dialog is reopened. A
    root `"/home/u/b/"` is probed as `/home/u/b/`, and its row and its pick give `/home/u/b`.

Existing tests are unchanged, apart from the `checkDispatchIdle` addition above. The plan must
run the whole of `tst_run_store.qml` to show that card-entry dispatch is unaffected.

## Out of scope

- 2.3: `dispatchTargetRunner`, `dispatchTargetCardMap`, `dispatchTargetRows`,
  `dispatchTargetLoading`, `dispatchTargetReplied`, `dispatchTargetPick`, a failed tree read
  marking a row disabled (2.3 may fold that into the probe input of `dispatchProjectRows`),
  Back from `form`, and the registry and project-switch rules at `form`. One example is the
  settings source: `dispatchSettingsSource()` compares `dispatchRoot` with `project`, and a
  switch can change that while a Runs-opened form is up.
- The `started` refresh (2.1's choice, `requestSnapshot([dispatchRoot])`) is unchanged.
- `DispatchDialog`, `RunsScreen`, `Shortcuts`, `Panel` (cards 3.1, 3.2), user docs (3.4),
  `board-tree.py`, `runs.js`.
