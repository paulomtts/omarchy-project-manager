# 2.2 RunStore dispatch: the project step — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `RunStore` gets the store side of the Runs-screen dispatch's project step: `dispatchOpenFromRuns()` opens a dialog with no root and probes every usable root, `dispatchProjectRows` lists the step's rows, `dispatchProjectPick(root)` moves to the target step, `dispatchBack()` returns from it, and a Runs-opened dialog survives a project switch.

**Architecture:** Everything new lives in one new delimited section of `core/stores/RunStore.qml`, `// ---- dispatch: project and target steps`, inserted right after S3's dispatch section (after `dropStartRunner`, before the `snapshotRunner` comment). The section holds its properties, functions, its `HelperRunner` (`dispatchProjectRunner`, `board-tree.py --probe`) and the runner's alias. `dispatchProjectRows` is a binding over `usableRoots()`, the probe and `project`, so it follows the registry and the open project with no extra code. Four existing functions get one-line hooks into the section: `closeDispatch` and `openDispatch` call `dispatchClearSteps()`, `registryChanged` calls `dispatchRegistryChanged()` at its end, and `projectSwitched` skips the dispatch reset when `dispatchStep !== ""`.

**Tech Stack:** QML (Qt 6, Quickshell), the `runs.js` domain library (unchanged; `Runs.dispatchProjects` already exists), QtTest store tests run by `qmltestrunner` with the stub `Process` in `tests/stubs`, the `bash tests/run.sh` gate (pytest incl. `tests/architecture`, then every QML test).

**Spec:** `docs/superpowers/specs/2-2-runstore-dispatch-080cfe16.md` (prepended below, headings demoted one level; executors read both).

## Global Constraints

- The new members go in a delimited section with the header line `// ---- dispatch: project and target steps`, right after S3's dispatch section (which ends with `dropStartRunner`) and before the `snapshotRunner` comment. Its properties, functions, `HelperRunner` and the runner's alias all go inside the section.
- Every new member is prefixed `dispatch*`: `dispatchStep`, `dispatchProjectProbe`, `dispatchProjectRows`, `dispatchProjectRunner`, `dispatchOpenFromRuns()`, `dispatchProjectReplied(stdout)`, `dispatchProjectPick(root)`, `dispatchBack()`, `dispatchClearSteps()`, `dispatchRegistryChanged()`. No `dispatchTarget*` member (that is 2.3).
- `dispatchStep` is `project` | `target` | `form`, or `""` (idle, a card entry, after a close).
- The probe argv is `python3 <backendDir>boards/board-tree.py --probe ROOT...`, the roots being `usableRoots()` in registry order. No guard. Latest wins.
- The rows are `Runs.dispatchProjects(store.usableRoots(), store.dispatchProjectProbe, store.project)` while `dispatchStep !== ""`, else `[]`.
- `dispatchState` stays `"idle"` at the `project` and `target` steps; every S3 field keeps its "none" value there.
- `resetDispatch()` and `dispatchOpenFor()` do not touch the step state.
- No new App binding. The store imports no other store; only `../domain/runs.js`. No change to `core/domain/runs.js`, `board-tree.py`, `ui/`, or any `tests/ui` / `tst_runs.qml` test.
- Comments state the contract only, with no narrative.
- Existing tests are unchanged, apart from the one `checkDispatchIdle` line in Task 1.
- Gate: `bash tests/run.sh` green (pytest incl. `tests/architecture`, then every QML test, no `TypeError`/`ReferenceError` lines).

## Review Focus

1. **The probe replies after the user switched the open project, while the Runs dialog is at the project step.** Expect the reply applied (the runner has no guard) and the `open` mark on the new project. Pinned in Task 5, `test_dispatch_open_project_switch_leaves_a_runs_dialog_alone` (the `inFlight` case).
2. **The registry holds unusable entries (`-x`, `""`, `null`, no root).** Expect no row and no argv entry, so the user never sees a row for a root `board-tree.py` would treat as a flag. Pinned in Task 1, `test_dispatch_open_from_runs_with_no_root_and_while_starting` (the `unusable` case), and Task 2, `test_dispatch_rows_follow_project_roots` (the `-x` entry).
3. **The registry is emptied while a probe is in flight and the dialog is reopened.** Expect nothing launched and the older probe's late reply dropped. Pinned in Task 1, same test (the `emptied` case).
4. **The picked root gains a trailing `/` in the registry (or the registry is reordered) while at the target step.** Expect the dialog to stay at `target` with the same root. Pinned in Task 4, `test_dispatch_registry_change_while_open_drops_the_row`.
5. **Close or card entry refused while a start is in flight from a Runs-opened form.** Expect the step kept (`form`). Pinned in Task 3, `test_dispatch_close_and_card_entry_clear_the_steps` (the `starting` case, which sets `dispatchStep = "form"` directly since 2.3 owns reaching it).

## Decisions the spec leaves to the plan

- **Registry hook.** `dispatchRegistryChanged()` is called from the end of `registryChanged()`, after `store.refresh()`. A second `onProjectRootsChanged:` line in the same object is a QML error (duplicate signal handler), so that option is not available.
- **Trailing-`/` comparison in `dispatchRegistryChanged`.** It reuses `Runs.dispatchProjects(store.usableRoots(), null, "")` and looks for a row whose `root === dispatchRoot`, so it trims exactly as the rows do.
- **Reopen with no usable root.** `dispatchOpenFromRuns()` calls `dispatchProjectRunner.cancel()` when it launches nothing, so an older probe still in flight cannot land on the new step.
- **Project-switch reaction.** In `projectSwitched()` itself: the `resetDispatch()` + `dispatchRoot = ""` pair is wrapped in `if (store.dispatchStep === "")`.
- **Test order in the file.** The 2.2 block holds the tests in task order (1-4, 5, 6, 10, 7, 8, 9); each keeps its `// 2.2 test N` label.

## Running the tests

`Q` below stands for this command, run from the worktree root:

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml
```

Append `StoresRunStore::<test_name>` arguments to run single tests. Always write the full command in the shell; `Q` is shorthand in this document only.

---

## Spec (prepended, headings demoted one level)

## 2.2 RunStore dispatch: the project step — design

Card: `080cfe16` (subtask of story `8200b9d4`). It builds on 2.1 (`abbba4c7`,
`docs/superpowers/specs/2-1-runstore-dispatch-abbba4c7.md`, merged on this branch), and 2.3
(`c3f687b6`, the target step) builds on it.
Parent design: `docs/superpowers/specs/2026-10-05-dispatch-from-runs-design.md`, cited below as
"DFR l.N". The store contract today is `docs/architecture.md:92` ("Dispatch (S3 3.1)"), cited as
"ARCH l.92". Code lines are on this branch at `35f149d`.

### Purpose

The Runs-screen dispatch starts at a project step (DFR l.67-79). This card gives `RunStore` the
store side of that step. `dispatchOpenFromRuns()` opens a dialog with no root. It probes every
registered root once and exposes the step's rows. `dispatchProjectPick(root)` takes an enabled
row and moves to the target step. `dispatchBack()` returns from the target step. A dialog opened
from Runs survives a switch of the open project. Nothing in `ui/` calls these members yet; the
UI is card 3.1.

### Inherited constraints

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

### Behaviour

#### State

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

#### `dispatchOpenFromRuns()`

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

#### `dispatchProjectRunner` and `dispatchProjectReplied(stdout)`

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

#### `dispatchProjectPick(root)`

- It succeeds only when `dispatchStep === "project"` and `dispatchProjectRows` has a row whose
  `root === root` with `enabled === true`. Then it sets `dispatchRoot = row.root`,
  `dispatchStep = "target"` and returns true. This card launches nothing on a pick. The tree
  read is 2.3's.
- Otherwise it returns false and nothing changes. That covers a disabled row, an unknown root,
  `""`, and any step other than `project`.
- A pick before the probe replies is allowed: a row with no probe entry is enabled.

#### `dispatchBack()`

- From `target`, it sets `dispatchStep = "project"` and `dispatchRoot = ""`, then returns true.
  The probe and its rows are kept, and nothing is relaunched.
- At `""` or `project` it returns false and nothing changes. Step 1 has no Back (DFR l.50,
  Cancel only).
- At `form` it returns false in this card. 2.3 owns Back from the form, which keeps the picked
  target row.

#### Clearing the steps

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

#### Project switch

`projectSwitched()` (`RunStore.qml:667-675`) still clears `runSettings` and reads the new
project's run settings on `runSettingsRunner` in every case. The dispatch reset (`resetDispatch()`
plus `dispatchRoot = ""`) happens only when `dispatchStep === ""`. A dialog opened from Runs
keeps its step, root, probe and S3 state, and its rows' `open` mark follows the new `project`.
The function's contract comment and the header comment say so.

#### Registry change

The rows follow `projectRoots` through the binding, so a removed root's row disappears. No
probe is relaunched: a root added while the step is open has no probe entry and shows enabled.
At the `target` step, if `dispatchRoot` is no longer the root of a usable registry entry
(compared with trailing `/` removed, as `Runs.dispatchProjects` does), the store sets
`dispatchStep = "project"` and `dispatchRoot = ""`. Compute this from `usableRoots()`, not from
the rows binding, because the order of the change notifications is not guaranteed. This reaction
is a section function, `dispatchRegistryChanged()`. It is called from the end of
`registryChanged()` or from a second `onProjectRootsChanged` line in the section; the plan picks
one. At `""`, `project` and `form` it changes nothing in this card.

#### Docs and comments

- `RunStore.qml` header (`:32-35`): the dispatch also opens from Runs with no root
  (`dispatchOpenFromRuns`), picks a project (`dispatchProjectPick`) after a probe of every
  usable root, and a Runs-opened dialog survives a project switch.
- `docs/architecture.md:92`: add one sentence on the steps (`dispatchStep`,
  `dispatchOpenFromRuns`, the probe argv, `dispatchProjectRows`, `dispatchProjectPick`,
  `dispatchBack`). Amend the last sentence: a project switch resets only a dispatch whose
  `dispatchStep` is `""`.

### Errors and edge cases

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

### Tests

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

### Out of scope

- 2.3: `dispatchTargetRunner`, `dispatchTargetCardMap`, `dispatchTargetRows`,
  `dispatchTargetLoading`, `dispatchTargetReplied`, `dispatchTargetPick`, a failed tree read
  marking a row disabled (2.3 may fold that into the probe input of `dispatchProjectRows`),
  Back from `form`, and the registry and project-switch rules at `form`. One example is the
  settings source: `dispatchSettingsSource()` compares `dispatchRoot` with `project`, and a
  switch can change that while a Runs-opened form is up.
- The `started` refresh (2.1's choice, `requestSnapshot([dispatchRoot])`) is unchanged.
- `DispatchDialog`, `RunsScreen`, `Shortcuts`, `Panel` (cards 3.1, 3.2), user docs (3.4),
  `board-tree.py`, `runs.js`.

---

## File Structure

- Modify: `core/stores/RunStore.qml`
  - new section `// ---- dispatch: project and target steps` after `dropStartRunner` (currently ends at line 1847), before `// The one list snapshot in flight (requestSnapshot).` (line 1849)
  - `projectSwitched()` (lines 660-675), `registryChanged()` (lines 740-759), `openDispatch()` (lines 1487-1494), `closeDispatch()` (lines 1549-1557): one-line hooks and contract comments
  - header comment (lines 32-34) and the `dispatchRoot` property comment (lines 177-178)
- Modify: `tests/core/stores/tst_run_store.qml`
  - `checkDispatchIdle` (line 3939-3954): one added line
  - new block `// ---- dispatch: project and target steps (2.2)` right before `// ---- list snapshots` (line 5630)
- Modify: `docs/architecture.md:92`: one inserted sentence, last sentence amended

---

### Task 1: The project step opens from Runs and probes every usable root

**Files:**
- Modify: `core/stores/RunStore.qml` (new section after `dropStartRunner`)
- Test: `tests/core/stores/tst_run_store.qml` (`checkDispatchIdle`; new 2.2 block before `// ---- list snapshots`)

**Interfaces:**
- Consumes: `store.usableRoots()` → `[{root, name}]`; `store.parseEnvelope(text)` → object or `null`; `store.resetDispatch()`; `Runs.dispatchProjects(projectRoots, probe, openRoot)` → `[{root, name, open, enabled, reason}]`; `HelperRunner` (`run(args)`, `cancel()`, `current`, `seq`, `finished(stdout, exitCode, launchedGuard)`).
- Produces: `property string dispatchStep` (`""` | `"project"` | `"target"` | `"form"`); `property var dispatchProjectProbe` (envelope or `null`); `readonly property var dispatchProjectRows`; `readonly property alias dispatchProjectRunner`; `function dispatchOpenFromRuns()` → bool; `function dispatchProjectReplied(stdout)`. Test helpers: `tc.probeCmd`, `probeReply(entries)` → string, `rowsText(rows)` → string, `runsStore()` → store.

- [ ] **Step 1: Add the step check to `checkDispatchIdle`**

In `tests/core/stores/tst_run_store.qml`, inside `function checkDispatchIdle(store, label)`, after the line

```qml
    compare(store.dispatchTargetLabel, "", label + ": target label")
```

add

```qml
    compare(store.dispatchStep, "", label + ": step")
```

- [ ] **Step 2: Write the helpers and tests 1-4**

In `tests/core/stores/tst_run_store.qml`, insert the following right before the line `  // ---- list snapshots` (after 2.1's last test, `test_dispatch_start_in_flight_completes_for_its_root_after_a_switch`, and its closing `}` plus blank line):

```qml
  // ---- dispatch: project and target steps (2.2)

  property string probeCmd: "python3|/plugin/core/backend/boards/board-tree.py|--probe"

  // board-tree.py --probe's reply line: {"ok": true, "projects": entries}.
  function probeReply(entries) {
    return JSON.stringify({ ok: true, projects: entries }) + "\n"
  }

  // The project step's rows as "root:name:open:on|off:reason", " / "-joined.
  function rowsText(rows) {
    return rows.map(function(r) {
      return r.root + ":" + r.name + ":" + (r.open ? "open" : "") + ":" + (r.enabled ? "on" : "off") + ":" + r.reason
    }).join(" / ")
  }

  // Projects A and B registered, A open with its settings read (dispatchSettings).
  function runsStore() {
    var store = make(); if (!store) return null
    store.projectRoots = registry([tc.rootA, tc.rootB])
    store.project = tc.rootA
    reply(store.runSettingsRunner.current, dispatchSettings(), 0)
    return store
  }

  // 2.2 test 1
  function test_dispatch_step_empty_for_idle_and_card_entry() {
    var fresh = make(); if (!fresh) return
    compare(fresh.dispatchStep, "", "fresh")
    compare(fresh.dispatchProjectRows.length, 0, "fresh: no rows")
    compare(fresh.dispatchProjectProbe, null, "fresh: no probe")

    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchStep, "", "a card entry has no step")
    compare(store.dispatchProjectRows.length, 0, "a card entry has no rows")
    verify(!store.dispatchProjectRunner.current, "a card entry probes nothing")
  }
  // 2.2 test 2
  function test_dispatch_open_from_runs_argv_and_rows() {
    var store = runsStore(); if (!store) return
    compare(store.dispatchOpenFromRuns(), true)
    compare(store.dispatchStep, "project")
    compare(store.dispatchRoot, "", "no root until a pick")
    compare(store.dispatchState, "idle")
    compare(store.dispatchTarget, null, "S3's fields keep their none values")
    compare(store.dispatchForm, null)
    var probe = store.dispatchProjectRunner.current
    verify(probe, "the probe is launched")
    compare(argv(probe), tc.probeCmd + "|/home/u/my proj|/home/u/b")
    compare(probe.command.length, 5)
    compare(store.dispatchProjectProbe, null, "null before the reply")
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on: / /home/u/b:beta::on:",
            "before the reply every row is enabled, the open project first")
    reply(probe, probeReply([{ root: tc.rootA, ok: true }, { root: tc.rootB, ok: false, reason: "no .brd marker" }]), 0)
    compare(store.dispatchProjectProbe.ok, true)
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on: / /home/u/b:beta::off:no .brd marker")

    var none = makeWithRoots([tc.rootB, tc.rootA]); if (!none) return
    compare(none.dispatchOpenFromRuns(), true, "no project needs to be open")
    compare(argv(none.dispatchProjectRunner.current), tc.probeCmd + "|/home/u/b|/home/u/my proj", "registry order")
    compare(rowsText(none.dispatchProjectRows), "/home/u/my proj:alpha::on: / /home/u/b:beta::on:", "no row open, ordered by name")
  }
  // 2.2 test 3
  function test_dispatch_open_from_runs_with_no_root_and_while_starting() {
    var empty = make(); if (!empty) return
    compare(empty.dispatchOpenFromRuns(), true)
    compare(empty.dispatchStep, "project")
    compare(empty.dispatchProjectRows.length, 0, "No projects registered")
    verify(!empty.dispatchProjectRunner.current, "nothing to probe")

    var unusable = make(); if (!unusable) return
    unusable.projectRoots = [{ root: "-x", name: "x" }, { root: "", name: "empty" }, null, { name: "no root" }]
    compare(unusable.dispatchOpenFromRuns(), true)
    compare(unusable.dispatchProjectRows.length, 0, "an unusable entry gives no row")
    verify(!unusable.dispatchProjectRunner.current, "an unusable entry is not probed")

    var emptied = runsStore(); if (!emptied) return
    emptied.dispatchOpenFromRuns()
    var old = emptied.dispatchProjectRunner.current
    emptied.projectRoots = []
    compare(emptied.dispatchOpenFromRuns(), true)
    compare(emptied.dispatchProjectRows.length, 0)
    reply(old, probeReply([{ root: tc.rootA, ok: true }]), 0)
    compare(emptied.dispatchProjectProbe, null, "a reopening with no root drops the older probe")

    var starting = readyStore(); if (!starting) return
    compare(starting.dispatchStart(), true)
    compare(starting.dispatchOpenFromRuns(), false)
    compare(starting.dispatchState, "starting")
    compare(starting.dispatchStep, "")
    compare(starting.dispatchRoot, tc.rootA)
    verify(!starting.dispatchProjectRunner.current, "nothing launched")
  }
  // 2.2 test 4
  function test_dispatch_project_probe_unreadable_and_latest_wins() {
    var store = runsStore(); if (!store) return
    var bad = probeReply([{ root: tc.rootB, ok: false, reason: "not a directory" }])
    var unreadable = ["Traceback: boom\n", "", "[1, 2]\n",
                      JSON.stringify({ ok: false, error: { type: "Usage", message: "no roots" } }) + "\n",
                      JSON.stringify({ ok: true, projects: "nope" }) + "\n"]
    for (var i = 0; i < unreadable.length; i++) {
      store.dispatchOpenFromRuns()
      reply(store.dispatchProjectRunner.current, bad, 0)
      verify(store.dispatchProjectProbe !== null, "case " + i + ": a good reply first")
      store.dispatchProjectReplied(unreadable[i])
      compare(store.dispatchProjectProbe, null, "case " + i + ": unreadable is null")
      compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on: / /home/u/b:beta::on:",
              "case " + i + ": every row enabled")
    }

    store.dispatchOpenFromRuns()
    var first = store.dispatchProjectRunner.current
    compare(store.dispatchOpenFromRuns(), true, "a second call starts the step over")
    var second = store.dispatchProjectRunner.current
    verify(first !== second, "a new probe")
    reply(first, bad, 0)
    compare(store.dispatchProjectProbe, null, "the older reply is dropped")
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on: / /home/u/b:beta::on:")
    reply(second, bad, 0)
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on: / /home/u/b:beta::off:not a directory",
            "the newer reply applies")
  }
```

Leave one blank line between the last `}` and `  // ---- list snapshots`.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `Q StoresRunStore::test_dispatch_step_empty_for_idle_and_card_entry StoresRunStore::test_dispatch_open_from_runs_argv_and_rows StoresRunStore::test_dispatch_open_from_runs_with_no_root_and_while_starting StoresRunStore::test_dispatch_project_probe_unreadable_and_latest_wins StoresRunStore::test_dispatch_starts_idle`
Expected: all five FAIL — test 1 and `test_dispatch_starts_idle` on `Compared values are not the same` (`dispatchStep` is `undefined`), tests 2-4 on `TypeError: Property 'dispatchOpenFromRuns' of object ... is not a function`.

- [ ] **Step 4: Add the section with the state, the opening, the reply and the runner**

In `core/stores/RunStore.qml`, find the end of `dropStartRunner` and the comment after it:

```qml
  // A start runner's work is over: it leaves dispatchStartRunners and is destroyed.
  function dropStartRunner(runner) {
    dispatchBook.runners = dispatchBook.runners.filter(function(r) { return r !== runner })
    if (dispatchBook.startRunner === runner) dispatchBook.startRunner = null
    runner.destroy()
  }

  // The one list snapshot in flight (requestSnapshot). No guard: its reply is
```

Replace it with:

```qml
  // A start runner's work is over: it leaves dispatchStartRunners and is destroyed.
  function dropStartRunner(runner) {
    dispatchBook.runners = dispatchBook.runners.filter(function(r) { return r !== runner })
    if (dispatchBook.startRunner === runner) dispatchBook.startRunner = null
    runner.destroy()
  }

  // ---- dispatch: project and target steps

  // The Runs dialog's step: project | target | form; "" when the dispatch
  // was not opened from Runs (idle or a card entry).
  property string dispatchStep: ""
  // The latest board-tree.py --probe envelope ({ok: true, projects}) while a
  // step is open; null before its reply, when the reply is unreadable and
  // whenever the steps are cleared.
  property var dispatchProjectProbe: null
  // The project step's rows: Runs.dispatchProjects over the usable roots,
  // the probe and the open project while a step is open, else [].
  readonly property var dispatchProjectRows: store.dispatchStep !== ""
    ? Runs.dispatchProjects(store.usableRoots(), store.dispatchProjectProbe, store.project) : []
  readonly property alias dispatchProjectRunner: dispatchProjectRunner

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
    var roots = store.usableRoots().map(function(p) { return p.root })
    if (roots.length > 0) dispatchProjectRunner.run(["--probe"].concat(roots))
    else dispatchProjectRunner.cancel()
    return true
  }

  // The probe's reply: dispatchProjectProbe is its envelope when that is
  // {ok: true, projects: [...]}, else null (every row enabled). The exit code
  // is not read. Applied only while a step is open.
  function dispatchProjectReplied(stdout) {
    if (store.dispatchStep === "") return
    var reply = store.parseEnvelope(stdout)
    store.dispatchProjectProbe = reply !== null && reply.ok === true && Array.isArray(reply.projects) ? reply : null
  }

  // board-tree.py --probe ROOT... for the project step; latest wins. No
  // guard: the probe depends on no root.
  HelperRunner {
    id: dispatchProjectRunner
    script: store.backendDir + "boards/board-tree.py"
    onFinished: function(stdout, exitCode) { store.dispatchProjectReplied(stdout) }
  }

  // The one list snapshot in flight (requestSnapshot). No guard: its reply is
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Q StoresRunStore::test_dispatch_step_empty_for_idle_and_card_entry StoresRunStore::test_dispatch_open_from_runs_argv_and_rows StoresRunStore::test_dispatch_open_from_runs_with_no_root_and_while_starting StoresRunStore::test_dispatch_project_probe_unreadable_and_latest_wins StoresRunStore::test_dispatch_starts_idle`
Expected: `Totals: 5 passed, 0 failed` (plus initTestCase/cleanupTestCase counted by qmltestrunner if it lists them), no `TypeError`/`ReferenceError` line.

- [ ] **Step 6: Run the whole store file**

Run: `Q 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: one `Totals:` line with `0 failed`, nothing else.

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): dispatchOpenFromRuns opens the project step and probes every usable root"
```

---

### Task 2: Pick a project and go back

**Files:**
- Modify: `core/stores/RunStore.qml` (the new section, before the `dispatchProjectRunner` comment)
- Test: `tests/core/stores/tst_run_store.qml` (2.2 block, before `// ---- list snapshots`)

**Interfaces:**
- Consumes: `dispatchStep`, `dispatchProjectRows`, `dispatchProjectProbe`, `dispatchProjectRunner`, `dispatchOpenFromRuns()` (Task 1); test helpers `tc.probeCmd`, `probeReply`, `rowsText`, `runsStore` (Task 1).
- Produces: `function dispatchProjectPick(root)` → bool; `function dispatchBack()` → bool.

- [ ] **Step 1: Write tests 5, 6 and 10**

In `tests/core/stores/tst_run_store.qml`, insert right before `  // ---- list snapshots` (after test 4's closing `}` and blank line):

```qml
  // 2.2 test 5
  function test_dispatch_project_pick() {
    var store = runsStore(); if (!store) return
    store.dispatchOpenFromRuns()
    reply(store.dispatchProjectRunner.current,
          probeReply([{ root: tc.rootA, ok: true }, { root: tc.rootB, ok: false, reason: "no .brd marker" }]), 0)
    compare(store.dispatchProjectPick(tc.rootB), false, "a disabled row")
    compare(store.dispatchProjectPick("/nope"), false, "an unknown root")
    compare(store.dispatchProjectPick(""), false, "no root")
    compare(store.dispatchStep, "project", "a refused pick keeps the step")
    compare(store.dispatchRoot, "", "a refused pick sets no root")
    compare(store.dispatchProjectPick(tc.rootA), true)
    compare(store.dispatchStep, "target")
    compare(store.dispatchRoot, tc.rootA)
    compare(store.dispatchState, "idle")
    verify(!store.dispatchDefaultsRunner.current, "a pick looks up no defaults")
    verify(!store.dispatchSettingsRunner.current, "a pick reads no settings")
    verify(!store.dispatchPreviewRunner.current, "a pick previews nothing")
    compare(store.dispatchProjectPick(tc.rootA), false, "no pick at the target step")
    compare(store.dispatchStep, "target")
    compare(store.dispatchRoot, tc.rootA)

    var idle = runsStore(); if (!idle) return
    compare(idle.dispatchProjectPick(tc.rootA), false, "no pick without a step")
    compare(idle.dispatchStep, "")
    compare(idle.dispatchRoot, "")

    var early = runsStore(); if (!early) return
    early.dispatchOpenFromRuns()
    compare(early.dispatchProjectPick(tc.rootB), true, "a row with no probe entry is enabled")
    compare(early.dispatchRoot, tc.rootB)
  }
  // 2.2 test 6
  function test_dispatch_back_from_target() {
    var store = runsStore(); if (!store) return
    store.dispatchOpenFromRuns()
    reply(store.dispatchProjectRunner.current, probeReply([{ root: tc.rootA, ok: true }, { root: tc.rootB, ok: true }]), 0)
    var probe = store.dispatchProjectProbe
    var seq = store.dispatchProjectRunner.seq
    compare(store.dispatchProjectPick(tc.rootB), true)
    compare(store.dispatchBack(), true)
    compare(store.dispatchStep, "project")
    compare(store.dispatchRoot, "")
    verify(store.dispatchProjectProbe === probe, "the probe is kept")
    compare(store.dispatchProjectRunner.seq, seq, "nothing relaunched")
    compare(store.dispatchProjectRows.length, 2)
    compare(store.dispatchBack(), false, "step 1 has no Back")
    compare(store.dispatchStep, "project")

    var idle = runsStore(); if (!idle) return
    compare(idle.dispatchBack(), false, "no Back without a step")
    compare(idle.dispatchStep, "")

    var form = runsStore(); if (!form) return
    form.dispatchOpenFromRuns()
    form.dispatchProjectPick(tc.rootB)
    form.dispatchStep = "form"
    compare(form.dispatchBack(), false, "Back from the form is 2.3's")
    compare(form.dispatchStep, "form")
    compare(form.dispatchRoot, tc.rootB)
  }
  // 2.2 test 10
  function test_dispatch_rows_follow_project_roots() {
    var store = runsStore(); if (!store) return
    store.dispatchOpenFromRuns()
    var seq = store.dispatchProjectRunner.seq
    reply(store.dispatchProjectRunner.current,
          probeReply([{ root: tc.rootA, ok: true }, { root: tc.rootB, ok: false, reason: "not a directory" }]), 0)
    store.projectRoots = [tc.rootEntry(tc.rootA), { root: tc.rootB, name: "zeta" }]
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on: / /home/u/b:zeta::off:not a directory", "renamed")
    store.projectRoots = [tc.rootEntry(tc.rootA), { root: tc.rootB, name: "zeta" }, tc.rootEntry(tc.rootC)]
    compare(rowsText(store.dispatchProjectRows),
            "/home/u/my proj:alpha:open:on: / /home/u/c:proj::on: / /home/u/b:zeta::off:not a directory",
            "C added, enabled with no probe entry")
    store.projectRoots = [tc.rootEntry(tc.rootC), { root: tc.rootB, name: "zeta" }, tc.rootEntry(tc.rootA)]
    compare(rowsText(store.dispatchProjectRows),
            "/home/u/my proj:alpha:open:on: / /home/u/c:proj::on: / /home/u/b:zeta::off:not a directory",
            "reordered: still the open row first, then by name")
    compare(store.dispatchProjectRunner.seq, seq, "no new probe")

    store.projectRoots = [{ root: "-x", name: "x" }, tc.rootEntry(tc.rootA), { root: "/home/u/b/", name: "beta" }]
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on: / /home/u/b:beta::off:not a directory",
            "no row for -x; the trailing / is trimmed")
    store.dispatchOpenFromRuns()
    compare(argv(store.dispatchProjectRunner.current), tc.probeCmd + "|/home/u/my proj|/home/u/b/",
            "-x is not probed; the root is probed as registered")
    compare(store.dispatchProjectPick("/home/u/b/"), false, "a pick names the row's root")
    compare(store.dispatchProjectPick("/home/u/b"), true)
    compare(store.dispatchRoot, "/home/u/b")
  }
```

Leave one blank line between the last `}` and `  // ---- list snapshots`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Q StoresRunStore::test_dispatch_project_pick StoresRunStore::test_dispatch_back_from_target StoresRunStore::test_dispatch_rows_follow_project_roots`
Expected: all three FAIL with `TypeError: Property 'dispatchProjectPick' of object ... is not a function`.

- [ ] **Step 3: Add `dispatchProjectPick` and `dispatchBack`**

In `core/stores/RunStore.qml`, find

```qml
  // board-tree.py --probe ROOT... for the project step; latest wins. No
  // guard: the probe depends on no root.
```

and insert right before it:

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

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Q StoresRunStore::test_dispatch_project_pick StoresRunStore::test_dispatch_back_from_target StoresRunStore::test_dispatch_rows_follow_project_roots`
Expected: all three PASS, `0 failed`, no `TypeError`/`ReferenceError` line.

- [ ] **Step 5: Run the whole store file**

Run: `Q 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: one `Totals:` line with `0 failed`, nothing else.

- [ ] **Step 6: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): dispatchProjectPick takes an enabled row and dispatchBack returns to the project step"
```

---

### Task 3: A close, a panel close and a card entry clear the steps

**Files:**
- Modify: `core/stores/RunStore.qml` (`openDispatch`, `closeDispatch`, the new section)
- Test: `tests/core/stores/tst_run_store.qml` (2.2 block, before `// ---- list snapshots`)

**Interfaces:**
- Consumes: `dispatchStep`, `dispatchProjectProbe`, `dispatchProjectRunner`, `dispatchOpenFromRuns()`, `dispatchProjectReplied(stdout)` (Task 1); `dispatchProjectPick(root)` (Task 2); `stopLive()` (calls `closeDispatch()`, unchanged).
- Produces: `function dispatchClearSteps()` (cancels `dispatchProjectRunner`, `dispatchStep = ""`, `dispatchProjectProbe = null`).

- [ ] **Step 1: Write test 7**

In `tests/core/stores/tst_run_store.qml`, insert right before `  // ---- list snapshots` (after test 10's closing `}` and blank line):

```qml
  // 2.2 test 7
  function test_dispatch_close_and_card_entry_clear_the_steps() {
    var store = runsStore(); if (!store) return
    store.dispatchOpenFromRuns()
    var late = store.dispatchProjectRunner.current
    compare(store.closeDispatch(), true)
    compare(store.dispatchStep, "")
    compare(store.dispatchProjectProbe, null)
    compare(store.dispatchProjectRows.length, 0)
    checkDispatchIdle(store, "closed")
    reply(late, probeReply([{ root: tc.rootB, ok: false, reason: "no .brd marker" }]), 0)
    compare(store.dispatchProjectProbe, null, "a reply after the close is dropped")
    compare(store.dispatchStep, "")
    store.dispatchProjectReplied(probeReply([{ root: tc.rootB, ok: true }]))
    compare(store.dispatchProjectProbe, null, "a reply is applied only while a step is open")

    var cards = dispatchCards()
    store.dispatchOpenFromRuns()
    var lateCard = store.dispatchProjectRunner.current
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchStep, "", "a card entry clears the steps")
    compare(store.dispatchRoot, tc.rootA)
    compare(store.dispatchProjectRows.length, 0)
    reply(lateCard, probeReply([{ root: tc.rootB, ok: false, reason: "no .brd marker" }]), 0)
    compare(store.dispatchProjectProbe, null, "a reply after a card entry is dropped")

    var panel = make(); if (!panel) return
    panel.active = true
    panel.projectRoots = registry([tc.rootA, tc.rootB])
    panel.dispatchOpenFromRuns()
    compare(panel.dispatchProjectPick(tc.rootB), true)
    panel.active = false
    compare(panel.dispatchStep, "", "closing the panel clears the steps")
    compare(panel.dispatchRoot, "")

    var starting = readyStore(); if (!starting) return
    compare(starting.dispatchStart(), true)
    starting.dispatchStep = "form"
    compare(starting.closeDispatch(), false)
    compare(starting.dispatchStep, "form", "a refused close keeps the step")
    compare(starting.openDispatch(cards.m1, cards), false)
    compare(starting.dispatchStep, "form", "a refused card entry keeps the step")
  }
```

Leave one blank line between the last `}` and `  // ---- list snapshots`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `Q StoresRunStore::test_dispatch_close_and_card_entry_clear_the_steps`
Expected: FAIL with `Compared values are not the same` (actual `project`, expected `""`) at the first `compare(store.dispatchStep, "")` after `closeDispatch()`.

- [ ] **Step 3: Add `dispatchClearSteps` to the section**

In `core/stores/RunStore.qml`, find

```qml
  // board-tree.py --probe ROOT... for the project step; latest wins. No
  // guard: the probe depends on no root.
  HelperRunner {
```

and replace it with:

```qml
  // The steps cleared: the probe cancelled, dispatchStep "" and
  // dispatchProjectProbe null.
  function dispatchClearSteps() {
    dispatchProjectRunner.cancel()
    store.dispatchStep = ""
    store.dispatchProjectProbe = null
  }

  // board-tree.py --probe ROOT... for the project step; latest wins. No
  // guard: the probe depends on no root. dispatchClearSteps() cancels it.
  HelperRunner {
```

- [ ] **Step 4: Clear the steps in `closeDispatch`**

In `core/stores/RunStore.qml`, replace

```qml
  // Back to idle, and dispatchRoot back to "". Refused (false, nothing
  // changes) while a start is in flight: its outcome must land in a dialog
  // that still shows what was started.
  function closeDispatch() {
    if (store.dispatchState === "starting") return false
    store.resetDispatch()
    store.dispatchRoot = ""
    return true
  }
```

with

```qml
  // Back to idle, dispatchRoot back to "" and the steps cleared
  // (dispatchClearSteps). Refused (false, nothing changes) while a start is
  // in flight: its outcome must land in a dialog that still shows what was
  // started.
  function closeDispatch() {
    if (store.dispatchState === "starting") return false
    store.resetDispatch()
    store.dispatchRoot = ""
    store.dispatchClearSteps()
    return true
  }
```

- [ ] **Step 5: Clear the steps in `openDispatch`**

In `core/stores/RunStore.qml`, replace

```qml
  // The card entry: opens the dispatch for the open project (dispatchRoot =
  // project) and returns dispatchOpenFor's result. Refused (false, nothing
  // changes) without a project or while a start is in flight.
  function openDispatch(card, cardMap) {
    if (store.project === "" || store.dispatchState === "starting") return false
    store.dispatchRoot = store.project
```

with

```qml
  // The card entry: clears the steps (a card entry has no step), opens the
  // dispatch for the open project (dispatchRoot = project) and returns
  // dispatchOpenFor's result. Refused (false, nothing changes) without a
  // project or while a start is in flight.
  function openDispatch(card, cardMap) {
    if (store.project === "" || store.dispatchState === "starting") return false
    store.dispatchClearSteps()
    store.dispatchRoot = store.project
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `Q StoresRunStore::test_dispatch_close_and_card_entry_clear_the_steps`
Expected: PASS, `0 failed`, no `TypeError`/`ReferenceError` line.

- [ ] **Step 7: Run the whole store file**

Run: `Q 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: one `Totals:` line with `0 failed`, nothing else.

- [ ] **Step 8: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): closeDispatch and the card entry clear the dispatch steps"
```

---

### Task 4: A registry change that drops the picked root returns to the project step

**Files:**
- Modify: `core/stores/RunStore.qml` (`registryChanged`, the new section)
- Test: `tests/core/stores/tst_run_store.qml` (2.2 block, before `// ---- list snapshots`)

**Interfaces:**
- Consumes: `dispatchStep`, `dispatchProjectRows`, `dispatchProjectRunner`, `dispatchOpenFromRuns()` (Task 1); `dispatchProjectPick(root)` (Task 2); `store.usableRoots()`; `Runs.dispatchProjects`.
- Produces: `function dispatchRegistryChanged()`, called last in `registryChanged()`.

- [ ] **Step 1: Write test 8**

In `tests/core/stores/tst_run_store.qml`, insert right before `  // ---- list snapshots` (after test 7's closing `}` and blank line):

```qml
  // 2.2 test 8
  function test_dispatch_registry_change_while_open_drops_the_row() {
    var store = runsStore(); if (!store) return
    store.dispatchOpenFromRuns()
    var seq = store.dispatchProjectRunner.seq
    store.projectRoots = registry([tc.rootA])
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on:", "B's row is gone")
    compare(store.dispatchProjectRunner.seq, seq, "no new probe")
    compare(store.dispatchStep, "project")

    store.projectRoots = registry([tc.rootA, tc.rootB])
    store.dispatchOpenFromRuns()
    compare(store.dispatchProjectPick(tc.rootB), true)
    store.projectRoots = registry([tc.rootA])
    compare(store.dispatchStep, "project", "the picked root left: back to step 1")
    compare(store.dispatchRoot, "")
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on:")

    compare(store.dispatchProjectPick(tc.rootA), true)
    store.projectRoots = registry([tc.rootB, tc.rootA])
    compare(store.dispatchStep, "target", "a reorder keeps the step")
    compare(store.dispatchRoot, tc.rootA)
    store.projectRoots = [{ root: tc.rootA + "/", name: "alpha" }, tc.rootEntry(tc.rootB)]
    compare(store.dispatchStep, "target", "a trailing / is the same root")
    compare(store.dispatchRoot, tc.rootA)

    store.dispatchStep = "form"
    store.projectRoots = registry([tc.rootB])
    compare(store.dispatchStep, "form", "the form's registry rule is 2.3's")
    compare(store.dispatchRoot, tc.rootA)
  }
```

Leave one blank line between the last `}` and `  // ---- list snapshots`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `Q StoresRunStore::test_dispatch_registry_change_while_open_drops_the_row`
Expected: FAIL with `the picked root left: back to step 1` (actual `target`, expected `project`).

- [ ] **Step 3: Add `dispatchRegistryChanged` to the section**

In `core/stores/RunStore.qml`, find

```qml
  // board-tree.py --probe ROOT... for the project step; latest wins. No
  // guard: the probe depends on no root. dispatchClearSteps() cancels it.
```

and insert right before it:

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

- [ ] **Step 4: Call it at the end of `registryChanged`**

In `core/stores/RunStore.qml`, replace

```qml
  // The registry changed. First the roots no longer usable lose their runs,
  // their errors and their arming (armedRoots is replaced only when a root
  // went), and `runs` is merged again in the new order with the new names;
  // no alert is raised. Then every usable root is snapshotted.
```

with

```qml
  // The registry changed. First the roots no longer usable lose their runs,
  // their errors and their arming (armedRoots is replaced only when a root
  // went), and `runs` is merged again in the new order with the new names;
  // no alert is raised. Then every usable root is snapshotted, and the
  // dispatch's target step follows the registry (dispatchRegistryChanged).
```

and, in the same function, replace

```qml
    store.runs = store.mergedRuns(byProject, usable).runs
    store.refresh()
  }
```

with

```qml
    store.runs = store.mergedRuns(byProject, usable).runs
    store.refresh()
    store.dispatchRegistryChanged()
  }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `Q StoresRunStore::test_dispatch_registry_change_while_open_drops_the_row`
Expected: PASS, `0 failed`, no `TypeError`/`ReferenceError` line.

- [ ] **Step 6: Run the whole store file**

Run: `Q 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: one `Totals:` line with `0 failed`, nothing else.

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): the dispatch returns to the project step when the picked root leaves the registry"
```

---

### Task 5: A Runs-opened dialog survives a project switch; docs

**Files:**
- Modify: `core/stores/RunStore.qml` (`projectSwitched`, header comment, `dispatchRoot` property comment)
- Modify: `docs/architecture.md:92`
- Test: `tests/core/stores/tst_run_store.qml` (2.2 block, before `// ---- list snapshots`)

**Interfaces:**
- Consumes: everything from Tasks 1-4; `runSettingsRunner`; `tc.viewerCmd` (`"python3|/plugin/core/backend/projects/viewer-state.py|"`, already defined in the test file).
- Produces: nothing new for later cards beyond the documented contract.

- [ ] **Step 1: Write test 9**

In `tests/core/stores/tst_run_store.qml`, insert right before `  // ---- list snapshots` (after test 8's closing `}` and blank line):

```qml
  // 2.2 test 9
  function test_dispatch_open_project_switch_leaves_a_runs_dialog_alone() {
    var store = make(); if (!store) return
    store.projectRoots = registry([tc.rootA, tc.rootB, tc.rootC])
    store.project = tc.rootA
    reply(store.runSettingsRunner.current, dispatchSettings(), 0)
    store.dispatchOpenFromRuns()
    reply(store.dispatchProjectRunner.current,
          probeReply([{ root: tc.rootA, ok: true }, { root: tc.rootB, ok: true }, { root: tc.rootC, ok: true }]), 0)
    var probe = store.dispatchProjectProbe
    compare(store.dispatchProjectPick(tc.rootB), true)
    store.project = tc.rootC
    compare(store.dispatchStep, "target", "the step is kept")
    compare(store.dispatchRoot, tc.rootB, "the root is kept")
    verify(store.dispatchProjectProbe === probe, "the probe is kept")
    compare(store.dispatchState, "idle")
    compare(Object.keys(store.runSettings).length, 0, "the run settings are the new project's")
    compare(argv(store.runSettingsRunner.current), tc.viewerCmd + "get-run-settings|/home/u/c")
    compare(store.dispatchBack(), true)
    compare(rowsText(store.dispatchProjectRows),
            "/home/u/c:proj:open:on: / /home/u/my proj:alpha::on: / /home/u/b:beta::on:", "the open mark follows")
    store.project = ""
    compare(store.dispatchStep, "project", "closing the project keeps the step")
    compare(rowsText(store.dispatchProjectRows),
            "/home/u/my proj:alpha::on: / /home/u/b:beta::on: / /home/u/c:proj::on:", "no row open")

    var inFlight = runsStore(); if (!inFlight) return
    inFlight.dispatchOpenFromRuns()
    var proc = inFlight.dispatchProjectRunner.current
    inFlight.project = tc.rootB
    reply(proc, probeReply([{ root: tc.rootA, ok: false, reason: "no .brd marker" }]), 0)
    compare(rowsText(inFlight.dispatchProjectRows),
            "/home/u/b:beta:open:on: / /home/u/my proj:alpha::off:no .brd marker", "a probe across a switch still applies")
  }
```

Leave one blank line between the last `}` and `  // ---- list snapshots`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `Q StoresRunStore::test_dispatch_open_project_switch_leaves_a_runs_dialog_alone`
Expected: FAIL with `the root is kept` (actual `""`, expected `/home/u/b`).

- [ ] **Step 3: Guard the dispatch reset in `projectSwitched`**

In `core/stores/RunStore.qml`, replace

```qml
  // project and stay, and no snapshot is launched. Reset: the run settings
  // (loaded for the new project on runSettingsRunner), the dispatch and
  // dispatchRoot ("").
  function projectSwitched() {
    store.runSettings = {}
    // The dispatch is the old project's, even mid-start: a start already
    // launched still runs, and its reply is no longer this dispatch's.
    store.resetDispatch()
    store.dispatchRoot = ""
    runSettingsRunner.guard = store.project
```

with

```qml
  // project and stay, and no snapshot is launched. Reset: the run settings
  // (loaded for the new project on runSettingsRunner) and, when dispatchStep
  // is "", the dispatch and dispatchRoot (""). A dispatch opened from Runs
  // keeps its step, root, probe and state.
  function projectSwitched() {
    store.runSettings = {}
    // A card dispatch is the old project's, even mid-start: a start already
    // launched still runs, and its reply is no longer this dispatch's.
    if (store.dispatchStep === "") {
      store.resetDispatch()
      store.dispatchRoot = ""
    }
    runSettingsRunner.guard = store.project
```

- [ ] **Step 4: Run the test to verify it passes, and 2.1's card-dialog switch test with it**

Run: `Q StoresRunStore::test_dispatch_open_project_switch_leaves_a_runs_dialog_alone StoresRunStore::test_dispatch_root_starts_empty_and_card_entry_sets_project StoresRunStore::test_dispatch_start_in_flight_completes_for_its_root_after_a_switch`
Expected: all three PASS, `0 failed`, no `TypeError`/`ReferenceError` line.

- [ ] **Step 5: Update the store's header comment**

In `core/stores/RunStore.qml`, replace

```qml
// Dispatch (openDispatch, dispatchOpenFor .. dispatchStart) previews a run
// for dispatchRoot with dispatch-preview.py and starts it with start-run.py,
// one HelperRunner per Start.
```

with

```qml
// Dispatch (openDispatch, dispatchOpenFor .. dispatchStart) previews a run
// for dispatchRoot with dispatch-preview.py and starts it with start-run.py,
// one HelperRunner per Start. It also opens from Runs with no root
// (dispatchOpenFromRuns): a probe of every usable root (board-tree.py
// --probe) gives the project step's rows, and dispatchProjectPick sets
// dispatchRoot. A dispatch opened from Runs survives a project switch.
```

- [ ] **Step 6: Update the `dispatchRoot` property comment**

In `core/stores/RunStore.qml`, replace

```qml
  // The project root the dispatch is for; every dispatch launch carries it;
  // "" while no dispatch has been opened since the last close or project switch.
  property string dispatchRoot: ""
```

with

```qml
  // The project root the dispatch is for; every dispatch launch carries it;
  // "" while no dispatch has been opened since the last close or project
  // switch, and at the Runs dialog's project step.
  property string dispatchRoot: ""
```

- [ ] **Step 7: Update `docs/architecture.md:92`**

Line 92 is one long paragraph. Use the Edit tool with these exact strings (they occur once each).

Find:

```text
`closeDispatch()`, a project switch (even from `starting`) and closing the panel (except while `starting`) put the dispatch back to `idle` and `dispatchRoot` back to `""`.
```

Replace with:

```text
The Runs screen opens the dispatch with no root: `dispatchOpenFromRuns()` (refused while `starting`) resets it, sets `dispatchRoot` to `""` and `dispatchStep` (`project` | `target` | `form`; `""` when idle or opened from a card) to `project`, and runs `board-tree.py --probe ROOT...` with every usable root in registry order on `dispatchProjectRunner` (no guard, latest wins); `dispatchProjectRows` is `Runs.dispatchProjects` over the usable roots, the probe's envelope (`null` before its reply or when it is unreadable: every row enabled) and `project`, `dispatchProjectPick(root)` takes an enabled row (`dispatchRoot` = its root, step `target`, nothing launched), `dispatchBack()` goes from `target` back to `project` keeping the probe, and a registry change that drops the picked root does the same; `dispatchState` stays `idle` at both steps. `closeDispatch()` and closing the panel (except while `starting`) put the dispatch back to `idle`, `dispatchRoot` back to `""` and `dispatchStep` back to `""`; a card entry (`openDispatch`) clears `dispatchStep` too; a project switch (even from `starting`) puts the dispatch back to `idle` and `dispatchRoot` back to `""` only when `dispatchStep` is `""`, and leaves a dispatch opened from Runs as it is.
```

- [ ] **Step 8: Check the docs and comments landed**

Run: `grep -c "dispatchOpenFromRuns" docs/architecture.md core/stores/RunStore.qml && grep -n "^  // ---- dispatch" core/stores/RunStore.qml`
Expected: `docs/architecture.md:1`, `core/stores/RunStore.qml:` a count of at least 3; and exactly two section lines, `// ---- dispatch (S3 3.1)` and, below it, `// ---- dispatch: project and target steps`.

- [ ] **Step 9: Run the full gate**

Run: `timeout 900 bash tests/run.sh 2>&1 | tail -60`
Expected: pytest passes (including `tests/architecture`); every `== tests/...tst_*.qml` line is followed by a `Totals:` line with `0 failed`; no `FAIL`, `TypeError` or `ReferenceError` line; exit status 0.

- [ ] **Step 10: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml docs/architecture.md
git commit -m "feat(runs): a dispatch opened from Runs survives a project switch"
```

---

## Self-review (against the spec)

- **State** (`dispatchStep`, `dispatchProjectProbe`, `dispatchProjectRows` binding, alias, `dispatchState` stays idle): Task 1, tests 1-2; the binding following `projectRoots`/`project`: tests 8, 9, 10.
- **`dispatchOpenFromRuns()`** (refused while starting, reset, root `""`, step, probe argv in registry order, no root → nothing launched, no project needed, second call starts over): Task 1, tests 2-4.
- **Runner and reply** (no guard, latest wins, envelope rule, exit code unread, applied only while a step is open, also at `target`): Task 1 test 4; Task 3 test 7 (step `""`); Task 5 test 9 (across a switch); applied at `target` follows from the `dispatchStep !== ""` check (Back after a reply shows the probed rows, test 6).
- **`dispatchProjectPick`**: Task 2 test 5, trailing `/`: test 10.
- **`dispatchBack`** (from `target`; refused at `""`, `project`, `form`): Task 2 test 6.
- **Clearing the steps** (`closeDispatch`, panel close via `stopLive`, `openDispatch`, refused close/entry keep the step; `resetDispatch`/`dispatchOpenFor` untouched): Task 3 test 7.
- **Project switch** (Runs dialog kept, `runSettings` reloaded, `open` mark moves, card dialog reset unchanged): Task 5 test 9 + 2.1 test 1 and test 8 re-run.
- **Registry change** (row drops, no relaunch, picked root removed at `target` → `project`, trailing `/`, reorder, `form` untouched): Task 4 test 8, Task 2 test 10.
- **Docs and comments**: Task 5 steps 5-8; contract comments in Tasks 3-5.
- **`checkDispatchIdle` gains the step check**: Task 1 step 1.
- **Whole `tst_run_store.qml` run**: every task's "Run the whole store file" step; full gate in Task 5.
<!-- task-pipeline: validated -->
