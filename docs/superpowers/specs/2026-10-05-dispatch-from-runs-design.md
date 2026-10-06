# Dispatch from the Runs screen — design

Status: proposed; retargeted to the new `am` (run-id discovery over `am runs --all-projects`, no
per-root refresh; `2026-10-06-am-snapshots-cursors-design.md`, row dfr). Builds on the S3 dispatch spec (`2026-10-03-am-run-dispatch-design.md`), S7
(`2026-10-05-dispatch-story-level-design.md`) and S6 (`2026-10-05-runs-all-projects-design.md`).
All of them are merged on main when this starts, so read their code before changing it. It
lands BEFORE "Split RunStore" (`2026-10-05-split-runstore-design.md`), so it is written against
the single `core/stores/RunStore.qml` (`app.runs`): S3's dispatch state machine (form, preview,
start, its `dispatch*` members), S7's story target and retarget, the run settings
(`get-run-settings` / `set-run-settings` through `viewer-state.py`), S6's `projectRoots` and
per-root refresh, and the control requests all live in that one store.

## Problem

S3's Runs toolbar **Start run** dispatches only for the open project. With S6, Runs is a
global destination reachable with no project open, and there **Start run** is disabled with
"Open a project to dispatch". A run of another project means a detour: open that project
(which moves the panel to its Board), come back to Runs and start the run. The global screen
cannot start the runs it lists.

## Goal

From the Runs screen, with or without a project open, the user picks a registered project,
then a target in it, and dispatches through S3's unchanged form, preview and launch. The user
then lands on the new run's detail. The open project does not change.

## Non-goals

- S3's per-card entry points (Dispatch in card detail, `d` on the board list and card detail)
  are unchanged. They dispatch the open project's card and never show the new steps.
- No change to the form, the preview (`dispatch-preview.py`) or the launcher's spawn
  (`start-run.py`, `am run ... --repo-dir ROOT`). They already take the project root as an
  argument. The launcher's run-id discovery is retargeted, see Architecture ("Run-id
  discovery").
- No board editing, and no dispatch for a repository that is not registered with brd.
- No new run settings: the per-project run settings are read and written as S3 and S7 do,
  keyed by the picked root.

## Flow

```
Runs  [▶ Start run]   (or `d` on the Runs list, search empty)
        │
        ▼
┌ Dispatch · 1 Project ─────────────────────┐
│ ▸ omarchy-project-manager  (open)         │
│   agent-manager                           │
│   ori                                     │
│   py-ai-toolkit   board unreachable: …    │  ← disabled, reason shown
└───────────────────────────────────────────┘
        │ Enter / click
        ▼
┌ Dispatch · 2 Target in agent-manager ─────┐
│ [filter…]                                 │
│ ▸ Whole board                             │
│   Milestone  M4 Run story                 │
│     Story    Story dispatch backend       │
│       Subtask 1.2 runs.js: … (todo)       │
│ [Back]                                    │
└───────────────────────────────────────────┘
        │ Enter / click
        ▼
 S3 form (base, prefix, verify, parallelism) + preview + cost warning
 [Back] [Cancel] [▶ Start run]   → detached am run → Run detail of the new run
```

### Step 1: project

- Rows are the registered projects (`brd projects`), from the S6 `projectRoots` (`[{root, name}]`)
  that App already hands the run stores. The order is the open project first (marked `open`),
  then by name (case-blind, then root). The cursor starts on the first enabled row.
- When the step opens, one probe checks every root. A root that is not a directory, or that has
  no `.brd` marker, is **unreachable**. Its row is disabled and shows the reason. Disabled rows
  are skipped by the cursor and ignore clicks. A project whose tree read fails later (step 2) is
  marked unreachable the same way, and the dialog returns to step 1 with the reason on its row.
- **Empty states.** With no project registered, the step reads "No projects registered" and has
  only Cancel. With every project unreachable, it reads "No project's board can be read".
  **Start run** in the toolbar is already disabled when the registry is empty, so the first case
  is reached only when the registry empties while the dialog is open.

### Step 2: target

The target list for the picked project comes from its own brd tree (see Architecture), never
from the open project's `BoardStore`:

- **Whole board** first (`am run --board`, S3).
- Then, in tree order, every milestone that is not finished (`am run --milestone`), every story
  that is not finished (`am run --story`, S7), and every subtask whose status is `todo`
  (`am run --card`). The rows are indented by depth. A finished card (`done`, `merged`,
  `canceled`, `archived`) is omitted, and so is any card that S3's or S7's `dispatchPlan` does
  not offer. A container whose children all drop out still shows itself if it is offered.
- A filter field at the top (the shared `FilterableList`) narrows the list by title or short id.
  An empty match reads "No target matches".
- A project whose tree has no offered target shows only **Whole board**.

### Step 3: form

The S3 form, unchanged, with its defaults computed for the picked project. The base is
`dispatch-preview.py --defaults ROOT`. The prefix comes from S7's order, from the runs whose
`project.root` is ROOT (`Runs.filterByProject`, S6), then the milestone-keyed map, then the
history, then the stem. The verify set, parallelism and the confirm setting come from ROOT's run
settings. Starting it writes ROOT's run settings, never the open project's. A **Back** button
returns to step 2 and keeps the picked target's row under the cursor.

### Landing

On `started`, the S3 path opens Run detail for the new run id. After S6, Run detail works for
a run of any project. The store refreshes the run list once (the global snapshot, `am runs
--all-projects`), so the new run appears; there is no per-root refresh any more. A run id that is not yet known follows
S3: the dialog closes, a toast says "Started — waiting for the run to appear", and the Runs
list stays. The S6 project filter is not changed. If the filter hides ROOT, Run detail still
opens, because it is reached by id.

## Keyboard

- On the Runs list, with the search field empty and no modal open, a bare `d` opens the dialog
  at step 1, the same as **Start run**. It sits beside `p` / `r` / `c` in `Shortcuts.handleRunKey`
  (`ui/Shortcuts.qml:57-75` today). `d` is not handled on Run detail.
- Steps 1 and 2: Up and Down move the cursor over enabled rows, and Enter picks. In step 2 the
  filter field has the focus, and its arrows and Enter drive the list (the same pattern as
  `Shortcuts.handleSearchKey`). Backspace in an empty filter goes back to step 1.
- Escape closes the dialog at any step, like every modal (`Shortcuts.closeRequested`). The
  dialog is one modal for `modalOpen()`, so no chord and no run key acts under it.

## Gating (what changes)

| place | before (after S6) | after |
|---|---|---|
| Runs toolbar **Start run** (S3 4.2, S6 4.1) | disabled with no project: "Open a project to dispatch" | enabled when `am` is present and at least one project is registered. Otherwise disabled with "am is not installed or not on PATH" or "No projects registered" |
| `Shortcuts` | no `d` on the Runs list | `d` as above |
| `Panel` | the dispatch dialog's mount and focus may assume a selected project (S3) | the dialog shows, and takes the focus (`Panel.focusItem`, `ui/Panel.qml:169-178` today), with no project open |
| `Sidebar`, `Navigator.showSection` | Runs already enabled with no project (S6) | unchanged |
| card detail Dispatch, `d` on board / card detail | S3 | unchanged |

## Architecture

### Reading another project's board

Today the board is read only for the open project. `BoardStore.fetchBoard()`
(`core/stores/BoardStore.qml:53-63`) sets `treeProc.workingDirectory` to
`board.project.root_path` and runs `brd tree` there (`:220-244`). brd resolves the project from
the working directory: `brd tree` in a directory with no `.brd` marker answers
`ProjectNotFoundError` with exit 1. BoardStore has one `project`, and changing it is a project
switch (`App.qml:47-55`), so it cannot read a second board. The smallest addition is a
read-only helper, following `core/backend/boards/archive-milestones.py` (which already runs brd
with `cwd=root`):

- `core/backend/boards/board-tree.py ROOT` runs `brd tree` with `cwd=ROOT` (argv list, stdin
  devnull, 20 s timeout) and prints one JSON line. It prints `{"ok": true, "data": [...]}`,
  brd's tree unchanged, or `{"ok": false, "error": {"type", "message"}}` with the type
  `RootMissing`, `BrdMissing`, `BrdFailed` (brd's own error message, for example
  `ProjectNotFoundError`), `BrdBadOutput` or `HelperError`.
- `board-tree.py --probe ROOT [ROOT ...]` never runs brd. It prints
  `{"ok": true, "projects": [{"root", "ok", "reason"?}]}` in argv order: a root is ok when it is
  a directory holding `.brd`. Measured on this machine, one `brd tree` costs about 0.08 s, but
  the probe stays brd-free so that opening the dialog is instant whatever the registry size.

Both use `common.json_line.emit` and exit 0 whenever a line was printed. Only documented brd
commands are used, and brd's database is never read. The parsed tree is indexed with the
existing `Board.indexTree` (`core/domain/board.js:12`), which sets the `depth` and `parentId`
that `Runs.dispatchPlan(card, cardMap)` reads.

### Run-id discovery (`core/backend/runs/start-run.py`)

After the spawn the helper still polls for the new run's id for up to `POLL_WINDOW` seconds,
matching on target, prefix and `started_at >= spawn` as today (`find_run`). What changes is the
read: `list_runs` calls `am runs --all-projects --limit N` (N covering the newest runs) instead
of `am runs --repo-dir ROOT`; rows carry `project.repo_dir`, so a match still has to be a row of
ROOT. Optionally the helper captures the global head (`as_of_seq` of that first call, before the
spawn) and prefers rows whose events come after it; the `started_at` rule stays the fallback.
`am run` itself keeps `--repo-dir ROOT`. Its output line (`run_id`, `pid`, `log`, `started_at`)
is unchanged.

### Domain (`core/domain/runs.js`)

- `dispatchProjects(projectRoots, probe, openRoot)` returns the step 1 rows
  `{root, name, open, enabled, reason}` in the order above. A root missing from the probe counts
  as enabled until its tree read says otherwise.
- `dispatchTargets(roots, cardMap)` returns the step 2 rows
  `{key, level: board|milestone|story|subtask, card, label, depth}` in tree order. The rule is
  above, and every row's offer comes from `dispatchPlan`, so the two never disagree.

### Store (`RunStore`, its dispatch sections)

`RunStore.qml` keeps growing until the split, so the new members are grouped in delimited
sections the split can lift out whole into `RunDispatchStore`. Each opens with one header line
in the file's existing style (`// ---- attempt logs (5.2)`, `RunStore.qml:288` on main at
`84a9217`) and holds only its own members, all prefixed `dispatch*`:

| where | members |
|---|---|
| S3's dispatch section, beside the form | `dispatchRoot` |
| `// ---- dispatch: project and target steps` (right after S3's dispatch section) | `dispatchStep`, `dispatchOpenFromRuns()`, `dispatchBack()`; `dispatchProjectProbe`, `dispatchProjectRows`, `dispatchProjectRunner`, `dispatchProjectReplied(…)`, `dispatchProjectPick(root)`; `dispatchTargetCardMap`, `dispatchTargetRows`, `dispatchTargetLoading`, `dispatchTargetRunner`, `dispatchTargetReplied(…)`, `dispatchTargetPick(key)` |

- **`dispatchRoot`**, the project the dialog is for. Every dispatch launch (defaults, preview,
  start) and every run-settings launch the dispatch section makes (S3's `get-run-settings`
  read and `set-run-settings` save, S7's `prefixByMilestone` save) carries `dispatchRoot`,
  never `project`. A card entry point sets `dispatchRoot = project` and skips steps 1 and 2.
  The Runs entry point leaves it empty until step 1 picks.
- **`dispatchStep`** (`project` | `target` | `form`), `dispatchOpenFromRuns()`,
  `dispatchProjectPick(root)`, `dispatchTargetPick(key)`, `dispatchBack()`. The inputs are
  members the store already has: `projectRoots` (S6, bound by App) and `runs`. No new App
  binding.
- Two `HelperRunner`s: `dispatchProjectRunner` (`board-tree.py --probe`, latest wins) and
  `dispatchTargetRunner` (`board-tree.py ROOT`, latest wins, `guard: dispatchRoot`). A reply
  for a project the user has moved away from is dropped. The picked tree, indexed with
  `Board.indexTree`, is `dispatchTargetCardMap`, the card map a target picked here hands to
  the form.
- **Guards.** A dialog opened from Runs ignores a switch of the open project: its root is its
  own (the dispatch section's project-switch reaction, S3's, sits in or beside
  `projectSwitched()`, `RunStore.qml:253` on main, and skips a dialog with a non-empty
  `dispatchStep`). A dialog opened from a card keeps S3's behaviour on a project switch. A
  launch in flight completes for the root it was started for (S3's rule), and its result names
  that root. On `started` the store asks for one refresh of the global snapshot (the per-root
  refresh step collapses; the signal that carried `[dispatchRoot]` carries no roots).
- Story targets need `am run --story` (S7). This milestone does not re-check it, because S7's
  contract test gates `am` before S7 merges.

### UI

- `ui/components/DispatchDialog.qml` gains steps 1 and 2 above S3's form, reading
  `app.runs.dispatchStep`, `dispatchProjectRows`, `dispatchTargetRows` and
  `dispatchTargetLoading`. It is built on `ModalCard`, `ListRow`, `FilterableList` and
  `ActionButton`, with no new shared component and no second copy of one.
- `ui/screens/RunsScreen.qml` (**Start run** enablement and tooltip), `ui/Shortcuts.qml` (`d`)
  and `ui/Panel.qml` (the dialog without a project) follow the gating table.

## Errors

| case | behaviour |
|---|---|
| no project registered | toolbar Start run disabled ("No projects registered"); step 1 empty state if the registry empties while open |
| a root is gone or has no `.brd` | step 1 row disabled with the reason |
| `brd` missing or failing on the picked root | back to step 1, row disabled with the helper's message |
| tree read slower than the user | step 2 shows "Reading the board…"; Back cancels it (its reply is dropped) |
| the picked project leaves the registry while the dialog is open | the dialog returns to step 1 with the row gone; a launch already started completes |
| `am` missing | Start run disabled (S3's `missing` message) |
| preview or start refusal | S3 / S7, unchanged |

## Testing

- Backend pytest (`tests/core/backend/boards/test_board_tree.py`) with a fake `brd` on PATH:
  the cwd is ROOT, the tree passes through, each error type, the timeout, probe ok and not ok
  in argv order, and that the probe never runs brd.
- `tests/core/domain/tst_runs.qml`: `dispatchProjects` (order, open first, unreachable
  disabled, empty) and `dispatchTargets` (board first, tree order, finished omitted, only todo
  subtasks, stories included, agreement with `dispatchPlan`).
- `tests/core/stores/tst_run_store.qml` (the one store test file until the split moves its
  tests by concern), in its own dispatch block so the split can move it whole: `dispatchRoot`
  drives the defaults, preview, start and settings argv; a card entry uses the open project;
  the steps and `dispatchBack()`; the probe and tree runners and their guards; a failed tree
  read marks the row; an open-project switch leaves a Runs-opened dialog alone; the project
  step reads the store's `projectRoots`; `started` refreshes the global snapshot once.
- `tests/ui/`: Start run with no project open, through all three steps, with a stubbed launcher,
  landing on Run detail. Also: `d` on the Runs list; a disabled project row; the empty registry;
  Back at each step; Escape; filter, arrows and Enter in step 2; the card entry points unchanged.

## Open questions

- Should the target list also offer subtasks that are `in_progress` (a relaunch)? Assumed no:
  Resume and recover owns relaunch.
- Should step 1 be skipped when exactly one project is registered? Assumed no, so the flow
  stays the same everywhere and the user sees which project they are about to spend tokens on.
