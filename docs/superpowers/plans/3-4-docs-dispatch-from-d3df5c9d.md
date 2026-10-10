# 3.4 Docs: dispatch from the Runs screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `docs/architecture.md` and `README.md` describe the dispatch from the Runs screen (project step, target step, form) exactly as built in cards 3.1 to 3.3, and remove the stale S3 chip-row / `Open a project to dispatch` wording.

**Architecture:** Docs only. Each edit is an exact substring replacement done by a short `python3` script that asserts its anchor occurs exactly once, so a drifted anchor fails loudly instead of editing the wrong place. The "failing test" is a set of `grep` checks: before the edits they find the stale phrases and miss the new ones; after the edits the reverse. The full suite (`bash tests/run.sh`) proves nothing else moved.

**Tech Stack:** Markdown, `python3` (string replacement only), `grep`, `bash tests/run.sh` (pytest, then every `tests/**/tst_*.qml` under `qmltestrunner`).

**Spec:** `docs/superpowers/specs/3-4-docs-dispatch-from-d3df5c9d.md` (reproduced in full below). Parent design: `docs/superpowers/specs/2026-10-05-dispatch-from-runs-design.md` (**P**).

## Global Constraints

- Edit only `docs/architecture.md` and `README.md`. Change no QML, JS, Python, test or other file; do not edit **P** or any other spec.
- Where **P** and the code disagree, the code wins. Every replacement text below was checked against `core/backend/boards/board-tree.py`, `core/domain/runs.js` (`dispatchProjects` ~517, `dispatchTargets` ~1196), `core/stores/RunStore.qml:1564-1573,1866-2082`, `ui/components/DispatchDialog.qml`, `ui/Shortcuts.qml:40-111`, `ui/Panel.qml:93-108,268-356,548-562,893-938`. Paste the replacement text exactly; do not reword it.
- `docs/architecture.md`: one paragraph is one long line, except where a paragraph is already wrapped (the `Shortcuts.qml` clause at lines 94-110 is wrapped at ~80 columns and stays wrapped); identifiers in backticks; ` -- ` as the dash; story tags such as `(S3 4.2)` only where the surrounding text uses them.
- `README.md`: each Features bullet is one line.
- Sentences state behaviour only: no history ("no longer", "was", "now"), no plans.
- Extend existing entries; never add a second copy of an entry.
- Mention no member, prop, signal or string the code does not have. Every quoted UI string is copied from the code (Task 1 Step 6 and Task 2 Step 5 grep each one).
- `docs/architecture.md:92` (RunStore "Dispatch (S3 3.1)" paragraph), `:165` (run screens) and `:94`'s Navigator part were checked against the code and need no change; do not touch them.
- Gate: `bash tests/run.sh` green before the first edit and after the last.

## Review Focus

1. **A user with no project open** must learn that **▶ Start run** and the Runs list's `d` work without one (the old text said `Open a project to dispatch`). Task 2 Step 5 greps the Dispatch bullet for `with or without a project open`.
2. **A user who picks another project** must not be told the run starts on the open project, or that the open project changes. Task 2 Step 5 greps for `never the open one` and `the open project does not change`; Task 2 Step 1 greps that `can start them on the open project` is gone.
3. **A project whose board cannot be read** must be described as shown disabled with its reason, not hidden. Task 2 Step 5 greps for `shown disabled with the reason`; Task 1 Step 6 greps `No project's board can be read`.
4. **A `d` typed into a non-empty Runs search** must be described as typing, not dispatching. Task 1 Step 6 greps the Shortcuts clause for `on the Runs list (view mode` followed by `while its search is empty`.
5. **A reader looking for the Runs chip row** must not be told one appears: Panel binds no `targetChoices`. Task 1 Step 6 greps that `drop the chip row` and `openRunsDispatch` are gone and that `Panel binds neither` is present.

---

## Spec (verbatim)

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

---

## File Structure

- Modify: `docs/architecture.md` -- the `Shortcuts.qml` clause (lines 99-105), the `DispatchDialog` entry (line 153), the "Panel owns the dispatch" paragraph (line 167), the `runs.js` Domain helpers item (end of line 180), and a new `core/backend/boards/board-tree.py` line after the `core/backend/runs/` line (after line 196). Task 1.
- Modify: `README.md` -- the **Runs** bullet (line 154), the **Dispatch** bullet (line 155), the helpers paragraph (line 235). Task 2.
- No other file changes. No test file is added (spec, "Tests": no test reads `docs/` or `README.md`, and a prose grep test would pin wording, not behaviour).

---

### Task 1: docs/architecture.md describes the Runs dispatch as built

**Files:**
- Modify: `docs/architecture.md:99-105` (Shortcuts clause), `:153` (DispatchDialog entry), `:167` (Panel owns the dispatch), `:180` (runs.js item, its end), after `:196` (new board-tree line)
- Test: `grep` checks (Steps 2 and 6) and `bash tests/run.sh` (Steps 1 and 7)

**Interfaces:**
- Consumes: nothing from another task.
- Produces: nothing code-level. Task 2 relies only on the same UI strings (`No projects registered`, `am is not installed or not on PATH`, `Reading the board…`, `Whole board`).

- [ ] **Step 1: Run the full suite before any edit (baseline)**

Run: `timeout 1800 bash tests/run.sh`
Expected: exits 0 (pytest summary `passed`, every QML test `PASS`). If it fails before any edit, stop and report: the failure is not this card's.

- [ ] **Step 2: Run the grep checks to see them fail (RED)**

```bash
cd "$(git rev-parse --show-toplevel)"
for s in "core/backend/boards/board-tree.py" "dispatchProjects(projectRoots" "dispatchTargets(roots" "pickRunsTarget" "Dispatch · 1 Project" "Panel binds neither" "dispatchOpenFromRuns()\`, and it leaves"; do
  printf '%-45s %s\n' "$s" "$(grep -cF "$s" docs/architecture.md)"
done
for s in "openRunsDispatch" "Open a project to dispatch" "drop the chip row" "Three entry points"; do
  printf 'stale %-39s %s\n' "$s" "$(grep -cF "$s" docs/architecture.md)"
done
```

Expected: every line of the first loop prints `0`; every `stale` line prints `1`. (After Step 4 the reverse holds.)

- [ ] **Step 3: Write the edit script**

Create `/tmp/arch-3-4.py` (outside the repo, so it is never committed) with exactly this content:

```python
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()


def sub(old, new):
    global text
    count = text.count(old)
    assert count == 1, "anchor found %d times: %r" % (count, old[:80])
    text = text.replace(old, new)


# 1. Shortcuts.qml clause (wrapped paragraph, keep ~80-column wrapping).
sub(r'''`c` only opens the cancel confirmation; `handleDispatchKey` makes a bare `d`
open the dispatch dialog -- never start anything -- for the board list's cursor
card while its search is empty, or for the open card, and leaves the letter
alone without a project, while am is missing, or under a modal or the open
dropdown; `modalOpen()` is the one guard the chords, the run keys and `d` obey,
and an open dispatch counts as a modal; Escape closes the dispatch dialog (and
does nothing at all while its start is in flight), then the cancel
''', r'''`c` only opens the cancel confirmation; `handleDispatchKey` makes a bare `d`
open the dispatch dialog and never start anything: on the Runs list (view mode
`runs`) while its search is empty, with or without a project open, it calls
`app.runs.dispatchOpenFromRuns()`, and it leaves the letter alone while am is
missing or no usable root is registered (`usableRoots()` empty); on the board
list while its search is empty, and on an open card, it opens the dispatch for
the cursor card or the open card, and it leaves the letter alone without a
project or while am is missing; under a modal or the open dropdown, on Run
detail and anywhere else the letter is left alone; `modalOpen()` is the one
guard the chords, the run keys and `d` obey, and an open dispatch -- one whose
`dispatchState` is not `idle` or whose `dispatchStep` is not `""` -- counts as
a modal; Escape closes the dispatch dialog through `closeDispatch()` (and does
nothing at all while its start is in flight), then the cancel
''')

# 2. DispatchDialog entry: the two steps above the form.
sub(r'''`DispatchDialog` (the dispatch modal: `Target   …`''',
    r'''`DispatchDialog` (the dispatch modal, in three steps chosen by its `step` prop: `project` and `target` are the Runs dispatch's two pickers, any other value is the form. The project step, headed `Dispatch · 1 Project`, lists `projectRows` (`[{root, name, open, enabled, reason}]`) one `ListRow` each, in the owner's order: the name, an `open` mark on the open project, and under a disabled row its reason; the cursor starts on the first enabled row, skips disabled rows and keeps its root across new rows, a disabled row ignores clicks, Up / Down move the cursor, Return picks its row (`projectChosen(root)`) and Escape cancels; with no enabled row it reads `No projects registered` when there are no rows, else `No project's board can be read`; it shows only Cancel. The target step, headed `Dispatch · 2 Target in <projectName>` (`Dispatch · 2 Target` with no `projectName`), has a `Filter by title or id…` field over a `FilterableList` of the `targetRows` (`[{key, level, card, label, depth}]`) whose title or short id holds the filter, each row indented by its depth and showing its level word, title and short id; it reads `Reading the board…` while `targetLoading` and `No target matches` when no row shows; Down / Up move the cursor, Return picks its row (`targetPicked(key)`), Backspace in an empty filter goes back and Escape cancels; the cursor starts on `targetKey`'s row (else the first row), keeps its row's key across new rows and filter changes, and stays in view; it shows Back and Cancel. The form step, headed `Dispatch`: `Target   …`''')

# 3. DispatchDialog entry: Back and focusItem.
sub(r'''Cancel and `▶ Start run`, Start enabled only in `ready`.''',
    r'''Cancel and `▶ Start run`, Start enabled only in `ready`. `Back` shows at the `target` and `form` steps and emits `backRequested()`, never while starting; Start shows only at the form; `focusItem` follows the step: the project step's key handler, the target filter, then the Base field (Cancel for a target refused without a form).''')

# 4. DispatchDialog entry: what the owner passes and maps.
sub(r'''error, log, tail and exit code, and maps `fieldEdited(name, value)`''',
    r'''error, log, tail and exit code, plus `dispatchStep`, `dispatchProjectRows`, `dispatchTargetRows`, `dispatchTargetLoading`, `dispatchTargetKey` and the picked project's name (`step`, `projectRows`, `targetRows`, `targetLoading`, `targetKey`, `projectName`), and maps `fieldEdited(name, value)`''')
sub(r'''onto `setDispatchField`, `dispatchStart` and `closeDispatch`. The verify rows''',
    r'''onto `setDispatchField`, `dispatchStart` and `closeDispatch`, and `projectChosen(root)`, `targetPicked(key)` and `backRequested()` onto `dispatchProjectPick`, `dispatchTargetPick` (through Panel's `pickRunsTarget`) and `dispatchBack`. The verify rows''')

# 5. DispatchDialog entry: the chip row is the dialog's, Panel does not use it.
sub(r'''draw a `ChipRow` of targets under the target line and emit `targetChosen(id)` for a chip other than the active one (busy while starting);''',
    r'''draw a `ChipRow` of targets under the target line at the form step and emit `targetChosen(id)` for a chip other than the active one (busy while starting) -- Panel binds neither, so it shows no such row;''')

# 6. Panel owns the dispatch: the whole paragraph.
lines = text.split("\n")
hits = [i for i, line in enumerate(lines) if line.startswith("Panel owns the dispatch (S3 4.2). Three entry points")]
assert len(hits) == 1, "Panel paragraph found %d times" % len(hits)
lines[hits[0]] = r'''Panel owns the dispatch (S3 4.2). Four entry points open `dispatchDialog`, and none starts anything. Two open it on a card of the open project, at the form, through `root.openDispatch(target)` with the open board's `board.cardMap`, and are disabled (`am is not installed or not on PATH`) while am is missing: `CardDetailScreen`'s `▶ Dispatch` on every card (its `dispatchRequested(cardId)`; a finished card -- `done`, `merged`, `canceled` or `archived` -- opens a dialog already `refused` with `The card is <status>`, a story opens on its own target (`--story`, S7), and only a story am refuses as blocked offers its milestone, through the dialog's `Dispatch the milestone instead` (`dispatchSuggestion`, `RunStore.retargetToMilestone()`)) and a bare `d` on the board list or a card (`Shortcuts.handleDispatchKey`). Two open it at RunStore's project step through `app.runs.dispatchOpenFromRuns()`: a bare `d` on the Runs list (`Shortcuts.handleDispatchKey`) and the toolbar's `▶ Start run` (`startRunButton`), shown in view mode `runs` with or without an open project and enabled while `amStatus` is not `missing` and `usableRoots()` is non-empty; its tooltip reads `am is not installed or not on PATH` while am is missing, else `No projects registered` with no usable root, else `Start an am run`. `root.openDispatch(target)` keeps the card id (`dispatchCardId`; a refused plan does not carry it) and calls `app.runs.openDispatch`; at the target step `pickRunsTarget(key)` calls `dispatchTargetPick(key)` and, when that succeeds, sets `dispatchCardId` to the picked row's card id (`""` for the board row). `dispatchProjectName`, the target step's heading, is the name of `dispatchRoot`'s project row, else the root itself, and `""` with no `dispatchRoot`. `dispatchCardMap` is `dispatchTargetCardMap` for a Runs dispatch (`{}` before its read) and `board.cardMap` for a card's; the dispatched card, its story title, its blockers and the milestone offer (shown only while the milestone is in that map) are read from it, and a blocker resolves against the open board's issues only while `dispatchRoot` is the open project. Panel composes a subtask's `Story   "<title>"` and `Blocked by: …` lines and binds `confirmFirst` to a subtask target, so a subtask's Start takes two clicks. `dispatchOpen` is `dispatchState !== "idle" || dispatchStep !== ""`; the dialog takes the focus when it opens and on every step change while it is open (`onDispatchStepChanged`), with or without a project, and gives it back when it closes -- never on a re-preview. Cancel, the backdrop and Escape close it (except while starting); a project switch closes one opened on a card and leaves one opened from Runs as it is; closing the panel does not close it: the store keeps an open dispatch, and the dialog is still there when the panel reopens. The milestone offer re-targets it. On `dispatchStarted` Panel closes it and calls `navi.openStartedRun(runId)`; a failed launch keeps it open with the failure.'''
text = "\n".join(lines)

# 7. runs.js Domain helpers item: the Dispatch group.
sub('''(merged, canceled, archived);\nPython: `core/backend/common`''',
    '''(merged, canceled, archived). Dispatch: `dispatchProjects(projectRoots, probe, openRoot)` gives one `{root, name, open, enabled, reason}` per project of `projectRoots` (`[{root, name}]`): `root` with every trailing `/` removed, an entry without a string root, or whose root is then empty, skipped, and only the first entry of a root giving a row; `name` the trimmed name, else the root's last segment; `open` when the root is `openRoot` (trailing `/` removed); `probe` is the `board-tree.py --probe` envelope or its `projects` array, a root whose entry has `ok === false` gives a disabled row with the entry's trimmed reason, else `unreachable`, and a root the probe does not name is enabled; ordered open first, then name lower-cased, then root. `dispatchTargets(roots, cardMap)` gives one `{key, level, card, label, depth}` per target of a brd tree (`Board.indexTree`'s roots and map): first the `board` row (`Whole board`, depth 0), then the tree depth-first in order, a card giving a row when `dispatchPlan` offers it as a milestone or a story, or as a subtask whose status is exactly `todo`, each id once, keyed `card:<id>` and labelled by `dispatchLabel`. Both never mutate and never throw;\nPython: `core/backend/common`''')

# 8. Backend: board-tree.py, a new line after the core/backend/runs/ line.
sub('''so the `XDG_DATA_HOME` it inherits matters.\n\nWhen a thing is needed a second time''',
    '''so the `XDG_DATA_HOME` it inherits matters.\n`core/backend/boards/board-tree.py` is the Runs dispatch's board reader. `board-tree.py ROOT` runs `brd tree` once with cwd `ROOT`, stdin `/dev/null` and a 20 s timeout (`TIMEOUT_SECONDS`), and prints brd's `{ok: true, data: [...]}` unchanged or `{ok: false, error: {type, message}}` with type `RootMissing`, `BrdMissing`, `BrdFailed` (brd's own message, a non-zero exit or the timeout), `BrdBadOutput` or `HelperError` (bad usage or an unexpected exception). `board-tree.py --probe ROOT...` runs no process and only stats paths: it prints `{ok: true, projects: [{root, ok, reason?}]}`, one entry per root in argv order with the root verbatim; a root is ok when it is a directory holding a `.brd` entry, else its `reason` is `not a directory` or `no .brd marker`. Every invocation prints one JSON line through `common.json_line.emit` and exits 0. `RunStore` runs the probe on `dispatchProjectRunner` and the tree read on `dispatchTargetRunner`, both `HelperRunner`s; its tests are `tests/core/backend/boards/test_board_tree.py`.\n\nWhen a thing is needed a second time''')

path.write_text(text)
print("ok")
```

- [ ] **Step 4: Apply the edits**

Run: `python3 /tmp/arch-3-4.py docs/architecture.md`
Expected: prints `ok`. An `AssertionError` naming an anchor means the file drifted from the plan: stop and report it; do not hand-edit around it.

- [ ] **Step 5: Re-read the paragraphs this task leaves alone**

Run: `git diff --stat -- docs/architecture.md` and `git diff -U0 -- docs/architecture.md | grep '^@@'`
Expected: hunks only around the Shortcuts clause (~99-111), the `DispatchDialog` entry (~159), the Panel paragraph (~173), the `runs.js` item (~186) and the new board-tree line (~203). No hunk touches the RunStore "Dispatch (S3 3.1)" paragraph (line 92), the run screens paragraph (line 165) or the Navigator part of line 94.

- [ ] **Step 6: Run the grep checks to see them pass (GREEN)**

```bash
cd "$(git rev-parse --show-toplevel)"
for s in "core/backend/boards/board-tree.py" "dispatchProjects(projectRoots" "dispatchTargets(roots" "pickRunsTarget" "dispatchOpenFromRuns" "No projects registered" "Dispatch · 1 Project" "Panel binds neither" "No project's board can be read"; do
  printf '%-45s %s\n' "$s" "$(grep -cF "$s" docs/architecture.md)"
done
for s in "openRunsDispatch" "runsDispatchChoices" "Open a project to dispatch" "drop the chip row" "Three entry points"; do
  printf 'stale %-39s %s\n' "$s" "$(grep -cF "$s" docs/architecture.md)"
done
# Review Focus 4: the Runs d is gated on an empty search.
grep -A1 "on the Runs list (view mode" docs/architecture.md
# Every quoted UI string added exists in the code.
for s in "Dispatch · 1 Project" "Dispatch · 2 Target in " "Filter by title or id…" "Reading the board…" "No target matches" "No projects registered" "No project's board can be read" "Start an am run" "am is not installed or not on PATH" "not a directory" "no .brd marker" "unreachable" "Whole board" "TIMEOUT_SECONDS = 20"; do
  printf 'code %-40s %s\n' "$s" "$(grep -rlF "$s" ui core | wc -l)"
done
```

Expected: every line of the first loop prints `1` or more; every `stale` line prints `0`; the `grep -A1` output shows `` `runs`) while its search is empty ``; every `code` line prints `1` or more.

- [ ] **Step 7: Run the full suite**

Run: `timeout 1800 bash tests/run.sh`
Expected: exits 0, the same pass counts as Step 1 (`tests/architecture` included).

- [ ] **Step 8: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): the Runs dispatch's project and target steps, its entry points and board-tree.py"
```

---

### Task 2: README.md describes the Runs dispatch as built

**Files:**
- Modify: `README.md:154` (Runs bullet), `:155` (Dispatch bullet), `:235` (helpers paragraph)
- Test: `grep` checks (Steps 1 and 5), `bash tests/run.sh` and the scope check (Step 6)

**Interfaces:**
- Consumes: Task 1's committed `docs/architecture.md` (only for the scope check in Step 6; no text dependency).
- Produces: nothing.

- [ ] **Step 1: Run the grep checks to see them fail (RED)**

```bash
cd "$(git rev-parse --show-toplevel)"
for s in "board-tree.py" "can start a run on any registered project" "with or without a project open" "never the open one" "the open project does not change" "shown disabled with the reason" "Reading the board…"; do
  printf '%-45s %s\n' "$s" "$(grep -cF "$s" README.md)"
done
for s in "Open a project to dispatch" "Three entry points" "can start them on the open project"; do
  printf 'stale %-39s %s\n' "$s" "$(grep -cF "$s" README.md)"
done
```

Expected: every line of the first loop prints `0` (`with or without a project open` may print `1`: the Runs bullet's first sentence says "with or without a project open" already -- note the number and expect it to grow by one in Step 5); every `stale` line prints `1`.

- [ ] **Step 2: Write the edit script**

Create `/tmp/readme-3-4.py` with exactly this content:

```python
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()


def sub(old, new):
    global text
    count = text.count(old)
    assert count == 1, "anchor found %d times: %r" % (count, old[:80])
    text = text.replace(old, new)


# 1. Runs bullet.
sub(r'''can start them on the open project (see **Dispatch** below);''',
    r'''can start a run on any registered project (see **Dispatch** below);''')

# 2. Dispatch bullet: entry points, project and target steps, gating, picked project.
sub(r'''Three entry points open the dispatch dialog, and none of them starts anything: a card's **▶ Dispatch** in card detail; a bare `d` on the board list's cursor card (while the search is empty) or on the open card; and the Runs toolbar's **▶ Start run**, which opens on the whole board with a row of `Whole board` plus each milestone that can be dispatched. All three are disabled while `am` is missing, and **▶ Start run**, shown on the Runs list with or without a project, is disabled with `Open a project to dispatch` while no project is open.''',
    r'''Four entry points open the dispatch dialog, and none of them starts anything. A card's **▶ Dispatch** in card detail and a bare `d` on the board list's cursor card (while the search is empty) or on the open card open it on that card of the open project, at the form. The Runs toolbar's **▶ Start run**, shown on the Runs list with or without a project open, and a bare `d` on the Runs list (while the search is empty) open it at a project step: every registered project, the open one first and marked `open`, then by name. A project whose folder is gone, that has no `.brd` marker, or whose board could not be read is shown disabled with the reason and cannot be picked. Picking a project reads that project's own board and lists its targets: **Whole board**, then each milestone and story that can be dispatched and each `todo` subtask, in tree order, filterable by title or id, with `Reading the board…` while it loads; **Back**, or Backspace in the empty filter, returns to the project step. Picking a target opens the form, whose **Back** returns to the target step. **▶ Start run** is disabled, and the Runs `d` does nothing, while `am` is missing (`am is not installed or not on PATH`) or no project is registered (`No projects registered`); the card entry points are disabled while `am` is missing. A run started from Runs starts on the picked project, never the open one: the open project does not change, the prefix and the remembered settings are the picked project's, and the dialog stays open across a project switch.''')

# 3. Helpers paragraph.
sub(r'''`milestones/agents.py`. For the run monitor''',
    r'''`milestones/agents.py`. For the Runs dispatch, `boards/board-tree.py` runs `brd tree` in a picked project's folder, and its `--probe` mode only checks that each project folder exists and holds `.brd`. For the run monitor''')

path.write_text(text)
print("ok")
```

- [ ] **Step 3: Apply the edits**

Run: `python3 /tmp/readme-3-4.py README.md`
Expected: prints `ok`. On an `AssertionError`, stop and report the anchor; do not hand-edit around it.

- [ ] **Step 4: Check the bullets are still one line each**

Run: `grep -n '^- \*\*Runs\*\*\|^- \*\*Dispatch\*\*\|^- \*\*Documents\*\*' README.md`
Expected: three consecutive line numbers (Runs, Dispatch, Documents), i.e. the Runs and Dispatch bullets are each still a single line.

- [ ] **Step 5: Run the grep checks to see them pass (GREEN)**

```bash
cd "$(git rev-parse --show-toplevel)"
for s in "board-tree.py" "Start run" "can start a run on any registered project" "with or without a project open" "never the open one" "the open project does not change" "shown disabled with the reason" "Reading the board…"; do
  printf '%-45s %s\n' "$s" "$(grep -cF "$s" README.md)"
done
for s in "Open a project to dispatch" "Three entry points" "can start them on the open project" "openRunsDispatch" "runsDispatchChoices"; do
  printf 'stale %-39s %s\n' "$s" "$(grep -cF "$s" README.md)"
done
# Every quoted UI string added exists in the code.
for s in "Reading the board…" "am is not installed or not on PATH" "No projects registered" "Whole board" "no .brd marker"; do
  printf 'code %-40s %s\n' "$s" "$(grep -rlF "$s" ui core | wc -l)"
done
```

Expected: every line of the first loop prints `1` or more (`with or without a project open` one more than in Step 1); every `stale` line prints `0`; every `code` line prints `1` or more.

- [ ] **Step 6: Run the full suite and the scope check**

Run: `timeout 1800 bash tests/run.sh`
Expected: exits 0, the same pass counts as Task 1 Step 1.

Run: `git diff --stat 4f78c7b..HEAD -- . ':!docs/architecture.md' ':!README.md' ':!docs/superpowers'` and `git status --porcelain -- . ':!README.md' ':!docs/superpowers'`
Expected: both print nothing (`4f78c7b` is this card's base, the tip of 3.3): only the two docs changed.

Run: `grep -n "Open a project to dispatch\|openRunsDispatch\|runsDispatchChoices\|Three entry points" docs/architecture.md README.md`
Expected: prints nothing (exit 1).

- [ ] **Step 7: Commit**

```bash
git add README.md
git commit -m "docs(readme): dispatch from the Runs screen on any registered project, and board-tree.py"
```

---

## Self-Review

- **Spec coverage.** architecture 1 (RunStore paragraph): checked against `RunStore.qml:1564-1573,1866-2082`, matches, left alone (Global Constraints, Task 1 Step 5). architecture 2 (Shortcuts): Task 1 script edit 1. architecture 3 (DispatchDialog): edits 2-5 (props, signals, both steps' headings, rows, cursor, keys, empty texts, Back, `focusItem`, owner's passes and maps, `targetChoices` kept but unused by Panel). architecture 4 (Panel): edit 6 (entry points, `startRunButton` visibility/enabled/tooltips, `dispatchOpen`, focus on step change, `pickRunsTarget`, `dispatchProjectName`, `dispatchCardMap`, blocker issues, removed chip row / `openRunsDispatch` / `Open a project to dispatch`, kept close rules and `onDispatchStarted`). architecture 5 (`runs.js`): edit 7. architecture 6 (board-tree): edit 8. architecture 7-8: no change, verified. README 1-3: Task 2 edits 1-3. README 4: no change. Tests table: Task 1 Steps 1/6/7, Task 2 Steps 5/6.
- **Placeholders.** None: every edit is literal text in a script with an anchor asserted unique (anchors checked against the current files: each occurs once).
- **Consistency.** Names used match the code: `dispatchOpenFromRuns`, `dispatchProjectPick`, `dispatchTargetPick`, `dispatchBack`, `pickRunsTarget`, `dispatchProjectName`, `dispatchCardMap`, `dispatchTargetCardMap`, `startRunButton`, `usableRoots()`, `projectChosen(root)`, `targetPicked(key)`, `backRequested()`, `targetChosen(id)`, `focusItem`, `TIMEOUT_SECONDS`.
- **Review Focus.** Each of the five lines has its grep in Task 1 Step 6 or Task 2 Steps 1/5.
<!-- task-pipeline: validated -->
