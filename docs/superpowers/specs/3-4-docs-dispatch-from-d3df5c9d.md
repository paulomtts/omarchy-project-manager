# 3.4 Docs: dispatch from the Runs screen — design

Card `d3df5c9d` (subtask of story `7fad1523` "Dispatch from Runs UI"), after card 3.3
(`d4fdb639`, Runs entry points and gating), which is done. Parent design:
`docs/superpowers/specs/2026-10-05-dispatch-from-runs-design.md` (cited below as **P**, with line
numbers). Sibling specs: `3-3-runs-entry-points-d4fdb639.md` (**S33**) and the earlier 3.1 / 3.2
dialog specs.

## Scope

Docs only. Edit `docs/architecture.md` and `README.md` so that they describe the dispatch from the
Runs screen **as built** in 3.1 to 3.3. Change no QML, JS, Python, test or other file, and do not
edit **P** or any other spec.

Where **P** and the code disagree, the code wins. Before writing a sentence, read the file it is
about: `core/backend/boards/board-tree.py`, `core/domain/runs.js` (`dispatchProjects` at `:517`,
`dispatchTargets` at `:1196`), `core/stores/RunStore.qml` (`dispatchRoot` and the
`// ---- dispatch: project and target steps` section), `ui/components/DispatchDialog.qml`,
`ui/screens/RunsScreen.qml`, `ui/Shortcuts.qml`, `ui/Panel.qml`. Known disagreements the docs
must follow:

- **Start run lives in Panel's toolbar** (`ui/Panel.qml:553`, `startRunButton`), not in
  `RunsScreen` as **P** 225 says. `RunsScreen.qml` has no dispatch code.
- **The empty project step** reads `No projects registered` with no rows, and
  `No project's board can be read` when no row is enabled (`DispatchDialog.qml:656`), as **P**
  76-77 says.
- **The dialog still has `targetChoices` / `targetChoice` / `targetChosen(id)`**
  (`DispatchDialog.qml:54-55, 160`), but Panel no longer binds them; S3's chip row, Panel's
  `openRunsDispatch`, `runsDispatchChoices` and `dispatchChoices` are gone.

## Writing rules

- Keep the existing style: in `docs/architecture.md` one paragraph is one long markdown line (or
  the existing wrapped lines where a paragraph is already wrapped), identifiers in backticks,
  story tags such as `(S3 4.2)` where the surrounding text uses them. In `README.md` the
  Features bullets are one line each.
- Sentences state behaviour only: what the code does now. No history ("no longer", "was",
  "now"), no plans, no narrative.
- Extend the existing entries. Do not add second copies of an entry that already exists.
- Do not mention a member, prop, signal or string that the code does not have. Every quoted
  UI string is copied from the code.

## docs/architecture.md: what to change

1. **RunStore dispatch paragraph** (`docs/architecture.md:92`, "Dispatch (S3 3.1): …"). Already
   matches the code (`RunStore.qml:1501-1508, 1564-1573, 1867-2082`): `dispatchOpenFromRuns`,
   `dispatchStep`, the probe on `dispatchProjectRunner`, `dispatchProjectRows` /
   `dispatchProjectFailures`, `dispatchProjectPick`, `dispatchTargetRunner` /
   `dispatchTargetLoading` / `dispatchTargetCardMap` / `dispatchTargetRows` / `dispatchTargetKey`,
   `dispatchTargetPick`, `dispatchBack`, the registry-change fallback, `closeDispatch` clearing
   the steps, a project switch leaving a Runs dispatch alone (**P** 195-215). Re-read it against
   the code; change a clause only where it is wrong. No rewrite.
2. **Shortcuts paragraph** (`docs/architecture.md:94-105`, the `handleDispatchKey` clause).
   Replace the `d` clause so it states `Shortcuts.qml:93-111`: on the Runs list (view mode
   `runs`), with its search empty, no modal and the dropdown closed, a bare `d` calls
   `app.runs.dispatchOpenFromRuns()`, with or without a project open, and is left alone while am
   is missing or no usable root is registered (`usableRoots()` empty); on the board list (search
   empty) and an open card it keeps its rules (needs a project, am present, no modal or open
   dropdown) and opens the dispatch for the cursor card or the open card; it is not handled on
   Run detail (**P** 116-118). `modalOpen()` and Escape treat a dispatch as open while
   `dispatchState` is not `idle` **or** `dispatchStep` is not `""` (`Shortcuts.qml:47, 56`;
   **P** 122-123); Escape calls `closeDispatch()`, which does nothing while a start is in flight.
3. **DispatchDialog entry** (`docs/architecture.md:153`). Keep the form, preview, Start, refusal,
   suggestion and `confirmFirst` text. Add the two steps above the form (**P** 67-94, 119-121),
   as built in `ui/components/DispatchDialog.qml`:
   - Props `step` (`project` | `target` | anything else = the form), `projectName`,
     `projectRows` (`[{root, name, open, enabled, reason}]`), `targetRows`
     (`[{key, level, card, label, depth}]`), `targetLoading`, `targetKey`; signals
     `projectChosen(root)`, `targetPicked(key)`, `backRequested()`.
   - Project step, heading `Dispatch · 1 Project`: one `ListRow` per project (its name, an `open`
     mark on the open project, a disabled row showing its reason); the cursor skips disabled rows
     and a disabled row ignores clicks; Up / Down / Return drive it; empty text
     `No projects registered` or `No project's board can be read`; only Cancel.
   - Target step, heading `Dispatch · 2 Target in <projectName>` (`Dispatch · 2 Target` with no
     name): a `Filter by title or id…` field matching a row's title or short id, a
     `FilterableList` of rows indented by depth (level word, title, short id),
     `Reading the board…` while `targetLoading`, `No target matches`; Down / Up move the
     cursor, Return picks, Backspace in an empty filter goes Back, Escape cancels; the cursor
     keeps its row's key across new rows and filter changes and starts on `targetKey`; Back and
     Cancel.
   - Form step: Back shows at the target and form steps and is refused while starting;
     `focusItem` follows the step (project list, target filter, Base field).
   - The "Presentation only" sentence: the owner also passes the step, the project and target
     rows, the loading flag and the target key, and maps `projectChosen`, `targetPicked` and
     `backRequested`.
   - The `targetChoices` / `targetChoice` sentence: state that the dialog still supports the
     owner-driven chip row and `targetChosen(id)`, and that Panel does not use it.
4. **Panel owns the dispatch** (`docs/architecture.md:167`). Rewrite the entry-point and chip-row
   sentences to `ui/Panel.qml` (**P** 125-133; **S33**):
   - Entry points: card detail `▶ Dispatch` and a bare `d` on the board list or a card
     (`root.openDispatch(target)`, the open project's board and `board.cardMap`, unchanged S3
     behaviour), and the Runs list's `d` and the toolbar's `▶ Start run` (`startRunButton`),
     which call `app.runs.dispatchOpenFromRuns()` and open the dialog at the project step.
   - `startRunButton`: shown in view mode `runs` with or without an open project; enabled when
     `amStatus` is not `missing` and `usableRoots()` is non-empty; tooltip
     `am is not installed or not on PATH`, else `No projects registered`, else
     `Start an am run`.
   - `dispatchOpen` is `dispatchState !== "idle" || dispatchStep !== ""`; the dialog takes the
     focus on open and on every step change while open (`onDispatchStepChanged`), with or without
     a project.
   - `pickRunsTarget(key)` calls `dispatchTargetPick(key)` and, when it succeeds, sets
     `dispatchCardId` to the picked row's card id (`""` for the board row).
   - `dispatchProjectName`: the name of `dispatchRoot`'s project row, else the root, `""` with no
     `dispatchRoot`. `dispatchCardMap`: for a Runs dispatch `dispatchTargetCardMap` (`{}` before
     its read), else `board.cardMap`; the card, its story title, its blockers and the milestone
     offer are read from it; blocker text uses the open board's issues only when `dispatchRoot`
     is the open project.
   - Remove `root.openRunsDispatch`, the chip row, "drop the chip row", "a chip … re-targets it"
     and `Open a project to dispatch`. Keep: Cancel, the backdrop, Escape close it (except while
     starting); closing the panel keeps it; `onDispatchStarted` closes it and calls
     `navi.openStartedRun(runId)`; a failed launch keeps it open.
5. **`runs.js` entry** (the Domain helpers paragraph, `docs/architecture.md:180` region; today it
   names no dispatch function). Add a Dispatch group with only the two functions this story
   added (**P** 174-181):
   - `dispatchProjects(projectRoots, probe, openRoot)` → `{root, name, open, enabled, reason}`:
     trailing `/` stripped; an entry without a string root, or with an empty one, skipped; the
     first entry per root wins; name the trimmed name, else the root's last segment; `open` when
     the root is `openRoot`; `probe` is the `--probe` envelope or its `projects` array, an entry
     with `ok === false` gives a disabled row with its trimmed reason, else `unreachable`; a root
     the probe does not name is enabled; ordered open first, then name lower-cased, then root.
   - `dispatchTargets(roots, cardMap)` → `{key, level, card, label, depth}`: first the `board`
     row (`Whole board`, depth 0), then the tree depth-first in order, a card giving a row when
     `dispatchPlan` offers it as a milestone or story, or as a subtask whose status is exactly
     `todo`; each id once; key `card:<id>`; label `dispatchLabel`.
   - Both never mutate and never throw.
6. **Boards helpers**. `core/backend/boards/board-tree.py` is not documented anywhere. Add a
   short entry beside the other backend paragraphs (`core/backend/milestones/` and
   `core/backend/runs/`, `docs/architecture.md` ~184-196), stating the module docstring and code
   (**P** 137-161):
   - `board-tree.py ROOT` runs `brd tree` with cwd `ROOT`, stdin `/dev/null` and a 20 s timeout
     (`TIMEOUT_SECONDS`), and prints brd's `{ok: true, data: [...]}` unchanged or
     `{ok: false, error: {type, message}}` with type `RootMissing`, `BrdMissing`, `BrdFailed`
     (brd's own message, a non-zero exit or the timeout), `BrdBadOutput` or `HelperError`
     (bad usage or an unexpected exception).
   - `board-tree.py --probe ROOT...` runs no process, only stats paths, and prints
     `{ok: true, projects: [{root, ok, reason?}]}` in argv order, roots verbatim; a root is ok
     when it is a directory holding a `.brd` entry, else `reason` is `not a directory` or
     `no .brd marker`.
   - One JSON line through `common.json_line.emit`, exit 0 always. `RunStore` runs both modes
     through `HelperRunner`s; tests in `tests/core/backend/boards/test_board_tree.py`.
7. **Run screens paragraph** (`docs/architecture.md:165`). Matches the code (no dispatch in
   `RunsScreen`; `No projects registered.`; `am is not installed or not on PATH`). No change
   unless a clause is found wrong.
8. **Navigator** (`docs/architecture.md:94`). Already documents Runs and Run detail without a
   project and `openStartedRun`. No change.

## README.md: what to change

1. **Runs bullet** (`README.md:154`). Replace "can start them on the open project (see
   **Dispatch** below)" with: can start a run on any registered project (see **Dispatch**
   below). Nothing else in the bullet changes.
2. **Dispatch bullet** (`README.md:155`). Replace the third entry point and the
   `Open a project to dispatch` sentence (**P** 39-112, 125-133, 228-238):
   - Entry points: a card's **▶ Dispatch** and a bare `d` on the board list's cursor card (search
     empty) or the open card dispatch that card of the open project; the Runs toolbar's
     **▶ Start run** (shown on the Runs list with or without a project open) and a bare `d` on
     the Runs list (search empty) open the dialog at a project step. None starts anything.
   - Project step: every registered project, the open one first and marked `open`, then by
     name. A project whose folder is gone, that has no `.brd` marker, or whose board could not be
     read is shown disabled with the reason and cannot be picked.
   - Target step for the picked project, read from that project's own board: **Whole board**,
     then each milestone and story that can be dispatched and each `todo` subtask, in tree
     order, filterable by title or id; `Reading the board…` while it loads; **Back** returns to
     the project step, Backspace in the empty filter too.
   - Then the form; its **Back** returns to the target step.
   - **▶ Start run** and the Runs `d` are disabled while `am` is missing
     (`am is not installed or not on PATH`) or no project is registered
     (`No projects registered`); the card entry points while `am` is missing.
   - The run starts on the picked project, never the open one; the open project does not
     change; the prefix and the remembered settings are the picked project's; a dialog opened
     from Runs stays open across a project switch.
   - Keep the rest of the bullet (form fields, preview, refusals, prefix order, landing on the
     new run, `am run --story`).
3. **Helpers paragraph** (`README.md:222-236`). Add `boards/board-tree.py` to the helper list:
   it runs `brd tree` in a picked project's folder for the Runs dispatch, and its `--probe`
   mode only checks that each project folder exists and holds `.brd`.
4. No other README section mentions dispatch or a bare `d`; the `## Keybinding (optional)`
   section is the Hyprland toggle, unchanged.

## Out of scope

- Any code, test, or helper change; any edit to **P** or other specs.
- Documenting S3 / S7 dispatch functions in `runs.js` that predate this story (`dispatchPlan`,
  `dispatchLabel`, `dispatchDefaults`, `validateDispatch`, `previewSummary`) beyond naming them
  where the new functions use them.
- The run-id discovery change in `start-run.py` (**P** 163-172) unless the existing runs backend
  paragraph is found to contradict the code; it is not part of this card's list.
- Split RunStore (a later milestone).

## Tests

This card changes only markdown. No test in the repo reads `docs/` or `README.md`, and a test
that greps prose would pin wording, not behaviour, so no new test file is added.

| check | tier | why |
|---|---|---|
| `bash tests/run.sh` green before the first edit and after the last | full suite (pytest + every `tests/**/tst_*.qml`) | the card's gate; proves the docs-only change touched no code and `tests/architecture` (layers, icon glyphs) still passes |
| `git diff --stat 4f78c7b..HEAD -- . ':!docs/architecture.md' ':!README.md' ':!docs/superpowers'` prints nothing (`4f78c7b` is this card's base, the tip of 3.3) | manual, in the plan's final step | proves the scope is docs only |
| `grep -n "Open a project to dispatch\|openRunsDispatch\|runsDispatchChoices\|Three entry points" docs/architecture.md README.md` prints nothing | manual, in the plan's final step | the stale S3 wording is gone |
| `grep -c "board-tree.py" docs/architecture.md` ≥ 1, and `dispatchProjects`, `dispatchTargets`, `dispatchOpenFromRuns`, `pickRunsTarget`, `No projects registered` each found in `docs/architecture.md`; `board-tree.py` and `Start run` in `README.md` | manual, in the plan's final step | each required item is present |
| for every quoted UI string added, `grep -rn` of it in `ui/` or `core/` finds it | manual, per edit | the docs state only what the code does |
