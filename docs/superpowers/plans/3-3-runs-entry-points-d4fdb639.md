# 3.3 Runs entry points and gating Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From the Runs list, with or without a project open, **Start run** or a bare `d` opens the dispatch dialog at RunStore's project step (`app.runs.dispatchOpenFromRuns()`); Panel shows the dialog at every Runs step, binds its step props and signals to the store, gives it the focus at each step, and reads the dispatched card, its story and its blockers from the picked project's tree — while the card entry points behave exactly as before.

**Architecture:** Only two files of production code change. `ui/Shortcuts.qml` gains the Runs-list `d` and treats a dispatch at any Runs step as a modal (Task 1). `ui/Panel.qml` drops the S3 chip-row path, gates Start run on am + a usable registered root, widens `dispatchOpen` to `dispatchStep !== ""`, binds the dialog's step API and moves the focus on each step change (Task 2), then reads the dispatched card through one `dispatchCardMap` that is the store's `dispatchTargetCardMap` during a Runs dispatch and the open board's `cardMap` otherwise (Task 3). `RunStore`, `runs.js` and `DispatchDialog.qml` are not touched: everything below the wiring already exists.

**Tech Stack:** Qt 6 QML, QtTest (`qmltestrunner`, offscreen) run by `bash tests/run.sh [filter]` — pytest first (the architecture tier included), then every `tests/**/tst_*.qml` whose path contains the filter; the script fails on any `TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function` in the QML output. Test helpers: `tests/helpers/find.js` (`H.find(item, objectName)`, which also searches a `Flickable`'s `contentItem`). Stubs: `tests/stubs/qs/Ui/TextField.qml` is a plain `TextInput`; `tests/stubs/qs/Ui/Button.qml`'s `MouseArea` is disabled with the button (a `mouseClick` on a disabled button emits nothing, but calling `.clicked()` directly always runs `onClicked`).

**Spec:** `docs/superpowers/specs/3-3-runs-entry-points-d4fdb639.md` (copied verbatim below, under "Spec (verbatim)"). Parent design: `docs/superpowers/specs/2026-10-05-dispatch-from-runs-design.md`.

## Global Constraints

- Start run enabled iff `appStores.runs.amStatus !== "missing"` and `appStores.runs.usableRoots().length > 0`; the open project plays no part.
- Start run tooltip, first match wins: `am is not installed or not on PATH`, then `No projects registered`, else `Start an am run`.
- The string `Open a project to dispatch` no longer appears anywhere in `ui/`.
- `d` on the Runs list: bare `d` only (no modifier at all), `nav.searchQuery === ""`, not `modalOpen()`, not `nav.dropdownOpen`, am not missing, a usable root; never on Run detail (`viewMode === "run"`).
- `dispatchOpen` is `appStores.runs.dispatchState !== "idle" || appStores.runs.dispatchStep !== ""`; `modalOpen()` is also true while `app.runs.dispatchStep !== ""`.
- Card entries (card detail Dispatch, `d` on the board list / a card) behave byte-for-byte as before; their card map is still `board.cardMap`.
- No change to `RunStore.qml`, `runs.js`, `board-tree.py`, `start-run.py`, `DispatchDialog.qml` (its `targetChoices` API stays), `RunsScreen.qml`, `Sidebar`, `Navigator.showSection`, `docs/architecture.md`, `README.md`.
- No new component and no second copy of one; screens and components never import stores (`tests/architecture/test_layers.py`); `▶` stays the Start run icon (`tests/architecture/test_icon_glyphs.py`).
- Docstrings and comments state the contract only, no narrative.
- Tests first. Panel tests never let a helper run: `p.app.backendDir = "/plugin/core/backend/"`, each launch answered with `proc.outText = text; proc.exited(0)`.
- Verification: `bash tests/run.sh` green.

## Review Focus

1. **The registry empties while the Runs dialog is open at the project step** — the dialog must stay open on its empty state (`No projects registered`) and Start run behind it must turn disabled. Pinned in Task 2 (`test_a_registry_emptied_under_the_project_step_keeps_the_dialog`).
2. **Escape typed in the target step's filter field** — the dialog closes and the focus returns to the Runs search field, not to the key catcher or nowhere. Pinned in Task 2 (`test_escape_in_the_target_filter_closes_the_runs_dialog`).
3. **A Runs dispatch for the open project whose subtask is blocked by an issue** — the blocker reads `"<title>" (Issue · <state>)` from the open board's issues; for any other root (or none open) an issue id reads `<id> (not on this board)`. Pinned in Task 3 (test 6 and test 1).
4. **A Runs dispatch that picks the `board` row after a card row** — `dispatchCardId` must become `""` (the target line reads `Whole board`), never the earlier card's id. Pinned in Task 2 (`test_the_board_row_dispatches_the_whole_board`).
5. **A `d` typed at the Runs dialog's target step** — it types into the filter and opens nothing (the dialog keeps its step and root). Pinned in Task 2 (`test_d_typed_in_the_target_filter_filters`).

## Deviations from the spec's test list

- Spec test 9 lists "Run detail" among the `d` rows left alone; the existing `test_d_is_left_alone` data row `runs` (in `tests/ui/tst_shortcuts.qml`) asserts `d` on the Runs list with a project returns false, which is exactly the behaviour this card changes. That row (and its `case "runs"` line) is removed in Task 1; the Runs-list rows move into the new `test_d_on_the_runs_list_is_left_alone`.
- Spec tests 9, 11, 13 and 14 pass before their implementation (they pin behaviour that must not change, or that the old code already refused). They are written with their task anyway; each task's RED step says which tests are expected to fail and which are pins.

---

## Spec (verbatim)

### 3.3 Runs entry points and gating — design (spec title)

Card `d4fdb639` (subtask of story `7fad1523` "Dispatch from Runs UI"), after card 3.2
(`f377621e`, the dialog's target step). Parent design:
`docs/superpowers/specs/2026-10-05-dispatch-from-runs-design.md` (cited below as **P**, with line
numbers). Sibling specs: `3-1-dispatchdialog-the-e04a0de6.md` (**S31**, the project step) and
`3-2-dispatchdialog-the-f377621e.md` (**S32**, the target step), whose "Out of scope" (S32
217-221) hands this card the Panel wiring.

#### Problem

Everything below the UI wiring is done:

- `RunStore` runs the Runs flow (`core/stores/RunStore.qml:1866-2060`): `dispatchStep`
  (`""` | `project` | `target` | `form`), `dispatchOpenFromRuns()`, `dispatchProjectPick(root)`,
  `dispatchTargetPick(key)`, `dispatchBack()`, `dispatchProjectRows`, `dispatchTargetRows`,
  `dispatchTargetLoading`, `dispatchTargetKey`, `dispatchTargetCardMap`, `dispatchRoot`, and
  `usableRoots()` (`:694`). A card entry (`openDispatch`, `:1504`) clears the steps and sets
  `dispatchRoot` to the open project. `closeDispatch()` (`:1568`) clears the steps.
- `ui/components/DispatchDialog.qml` renders the project and target steps (props `step`,
  `projectName`, `projectRows`, `targetRows`, `targetLoading`, `targetKey`; signals
  `projectChosen(root)`, `targetPicked(key)`, `backRequested()`, `cancelRequested()`), handles its
  own Escape / arrows / Enter / Backspace, and its `focusItem` follows the step (`:89-91`).

What is missing is the panel:

1. **Start run** (`ui/Panel.qml:546-561`, `startRunButton`; it lives in Panel's toolbar, not in
   `RunsScreen`, whatever **P** 225 says) is disabled with no project open ("Open a project to
   dispatch") and opens the open project's whole board with S3's chip row
   (`openRunsDispatch`, `runsDispatchChoices`, `dispatchChoices`, `Panel.qml:266-358`).
2. `Panel.dispatchOpen` (`:274`) is `dispatchState !== "idle"`. At steps `project` and `target`
   the store's `dispatchState` **is** `idle` (`dispatchOpenFromRuns` and `dispatchBack` both go
   through `resetDispatch()`), so the dialog would be hidden and would not take the focus.
3. The `DispatchDialog` mount (`:892-929`) binds none of the step props or signals.
4. Panel reads the dispatched card, its story and its blockers from the **open** board's
   `cardMap` (`dispatchCard`, `dispatchStoryTitle`, `dispatchBlockedText`, `dispatchSuggestion`,
   `:275-302`). A Runs dispatch is for `dispatchRoot`'s tree (`dispatchTargetCardMap`), which may
   be another project's or exist with no project open.
5. `Shortcuts.handleDispatchKey` (`ui/Shortcuts.qml:86-98`) has no `d` on the Runs list, and
   `modalOpen()` / `closeRequested()` (`:44-53`) test only `dispatchState !== "idle"`, so a dialog
   at step `project` / `target` is not a modal for the chords and run keys.

#### Goal

From the Runs list, with or without a project open, **Start run** or a bare `d` opens the
dispatch dialog at the project step through `app.runs.dispatchOpenFromRuns()`; the user picks a
project, then a target, then S3's form starts the run and the panel lands on the new run's
detail. The card entry points behave exactly as before.

#### Inherited constraints

- Start run gating: enabled when `am` is present and at least one project is registered;
  otherwise disabled with "am is not installed or not on PATH" or "No projects registered":
  **P** 129, **P** 232, **P** 237.
- `d` on the Runs list, search empty, no modal open, opens the dialog at step 1 like Start run;
  `d` is not handled on Run detail; it sits beside `p` / `r` / `c`: **P** 116-118, **P** 130.
- Escape closes the dialog at any step; the dialog is one modal for `modalOpen()`, so no chord
  and no run key acts under it: **P** 122-123.
- The dialog shows and takes the focus (`Panel.focusItem`) with no project open: **P** 131.
- Sidebar, `Navigator.showSection`, card detail Dispatch and `d` on board / card detail are
  unchanged: **P** 29-30, **P** 132-133.
- Landing: on `started` the S3 path opens Run detail of the new run id; an unknown id follows S3
  (dialog closes, footer says it waits); the open project and the S6 project filter do not change:
  **P** 105-112.
- A Runs-opened dialog ignores a switch of the open project; a card-opened one keeps S3's
  behaviour (closes): **P** 209-212 (implemented in the store, `projectSwitched`, `:676`).
- UI is built on the existing components; no new shared component and no second copy of one;
  screens and components never import stores: **P** 221-226, `docs/architecture.md` layering,
  `tests/architecture/test_layers.py`, `tests/architecture/test_icon_glyphs.py`.
- Docstrings and comments state the contract only, no narrative (card).
- Tests first (card). Verification: `bash tests/run.sh` green.

#### Behaviour

##### B1. Start run (`ui/Panel.qml`, `startRunButton`)

- Visible exactly as today: on the Runs list (`viewMode === "runs"`), with or without a project,
  never on Run detail.
- **Enabled** iff `appStores.runs.amStatus !== "missing"` **and**
  `appStores.runs.usableRoots().length > 0` (the same roots the project step lists). The open
  project plays no part.
- **Tooltip**, first match wins:
  1. am missing → `am is not installed or not on PATH`
  2. no usable root → `No projects registered`
  3. otherwise → `Start an am run`

  The string `Open a project to dispatch` no longer appears anywhere in `ui/`.
- **Click** → `appStores.runs.dispatchOpenFromRuns()`. Nothing else: no card id, no chip row.
- The S3 chip-row path in Panel is removed: `openRunsDispatch`, `runsDispatchChoices`,
  `dispatchChoices`, `dispatchRetargeting`, and the mount's `targetChoices` / `targetChoice` /
  `onTargetChosen` bindings. `DispatchDialog`'s own `targetChoices` API is left as is (its
  default `[]` hides the row).

##### B2. The dialog's open state and focus (`ui/Panel.qml`)

- `dispatchOpen` is `appStores.runs.dispatchState !== "idle" || appStores.runs.dispatchStep !== ""`.
  So the dialog is shown at every Runs step (project, target, form — including a form whose
  dispatch went back to idle through `dispatchBack`) and for every card-opened dispatch as before.
- `focusItem` keeps its order (`dispatchOpen` → `dispatchDialog.focusItem`, `:183`), so with no
  project open the dialog's focus item still wins over `keyCatcher`.
- Opening, closing **and every change of `dispatchStep` while `dispatchOpen`** calls
  `focusForView()`, so the dialog's step focus item (`dispatchProjectKeys` at project, the filter
  at target, the base field or Cancel at form) holds the active focus after each step change.
  A re-preview still never moves the focus (S3 rule, `:313-318`).
- Closing (Cancel, Escape, backdrop) gives the focus back to the view's own item (the Runs search
  field on the Runs list).

##### B3. The mount's step bindings (`ui/Panel.qml`, `dispatchDialog`)

| dialog prop / signal | bound to |
|---|---|
| `step` | `appStores.runs.dispatchStep` |
| `projectRows` | `appStores.runs.dispatchProjectRows` |
| `projectName` | the `name` of the `dispatchProjectRows` row whose `root` is `dispatchRoot`; else the root itself; `""` with no `dispatchRoot` |
| `targetRows` | `appStores.runs.dispatchTargetRows` |
| `targetLoading` | `appStores.runs.dispatchTargetLoading` |
| `targetKey` | `appStores.runs.dispatchTargetKey` |
| `onProjectChosen(root)` | `appStores.runs.dispatchProjectPick(root)` |
| `onTargetPicked(key)` | `appStores.runs.dispatchTargetPick(key)`; when it returns true, Panel's `dispatchCardId` becomes the picked row's `card.id` (`""` for the `board` row, whose `card` is the string `"board"`; rows are `{key, level, card, label, depth}` with `key` `"board"` or `"card:<id>"`) |
| `onBackRequested()` | `appStores.runs.dispatchBack()` |
| `onCancelRequested()` | `appStores.runs.closeDispatch()` (unchanged) |

##### B4. The dispatched card in a Runs dispatch (`ui/Panel.qml`)

Panel reads the target card through one card map, `dispatchCardMap`:
`appStores.runs.dispatchTargetCardMap || {}` while `dispatchStep !== ""`, else
`appStores.board.cardMap` (card entries, unchanged). `dispatchCard`, `dispatchStoryTitle`,
`dispatchBlockedText` and `dispatchSuggestion` read that map instead of `board.cardMap`, so:

- A Runs dispatch of a subtask shows `Story   "<story title>"` and `Blocked by: …` from the picked
  project's tree, with or without a project open, and whichever project is open.
- A blocker id is resolved with `Board.resolvedCard(id, dispatchCardMap, issueMap)`, where
  `issueMap` is the open board's `issueMap` when `dispatchRoot` is the open project's root
  (`appStores.runs.project`), else `{}`. A card in the map reads `"<title>" (<Status>)`, an issue
  `"<title>" (<issue label>)`, anything else `<id> (not on this board)` (S3's wording).
- A blocked story's `Dispatch the milestone instead` is offered only when the milestone is in
  `dispatchCardMap`; `retargetToMilestone()` true sets `dispatchCardId` to it (unchanged).
- Card entries behave byte-for-byte as before (their map is still `board.cardMap`).

##### B5. Shortcuts (`ui/Shortcuts.qml`)

- `modalOpen()` is also true while `app.runs.dispatchStep !== ""`.
- `closeRequested()`'s dispatch branch fires when `dispatchState !== "idle" || dispatchStep !== ""`
  and calls `closeDispatch()` (refused while starting, unchanged).
- `handleDispatchKey(event)`: a bare `d` (no modifier at all) on the **Runs list**
  (`viewMode === "runs"`) calls `keys.app.runs.dispatchOpenFromRuns()` and returns true when all
  hold: `nav.searchQuery === ""`, not `modalOpen()`, not `nav.dropdownOpen`,
  `runs.amStatus !== "missing"`, `runs.usableRoots().length > 0`. With or without a project open.
  Otherwise on the Runs list it returns false (the letter types into the search). Shift+D,
  Ctrl+D: false. On Run detail (`viewMode === "run"`): false, nothing opens.
- The board-list / card-detail branch is unchanged (still needs a selected project, still goes
  through `actions.openDispatch(id)`).
- Panel's key routing (`handleGlobalKey || handleRunKey || handleDispatchKey`, `Panel.qml:402-407`)
  is unchanged; `handleRunKey` ignores `d`, so the order holds.
- The file's header and the `handleDispatchKey` / `modalOpen` comments state the new contract.

##### Error and edge paths

| case | behaviour |
|---|---|
| am missing | Start run disabled, tooltip `am is not installed or not on PATH` (wins over an empty registry); `d` on Runs types / does nothing |
| empty registry (or only unusable roots) | Start run disabled, `No projects registered`; `d` does nothing |
| registry empties while the dialog is open | the dialog stays open at the project step with its empty state (S31); Start run disabled behind it |
| a start is in flight and Start run / `d` is used | cannot happen through the UI: the dialog is open and modal; `dispatchOpenFromRuns()` also refuses while starting |
| open project switched while a Runs dialog is open | the dialog stays, at its step, on its own root (store guard); its card / story / blockers keep coming from `dispatchTargetCardMap` |
| open project switched while a card dialog is open | closes, as S3 |
| `d` with a non-empty Runs search | types into the search, opens nothing |
| `d` / chords while the Runs dialog is at project or target step | nothing acts under it (`modalOpen()`) |
| Escape at project / target step | the dialog closes (the dialog's own key handling, or `closeRequested()` if it reaches the key catcher) and the focus returns to the Runs search field |
| start replies with a known run id | dialog closes, Run detail of that run (S3 path, `onDispatchStarted`) |
| start replies with an id not yet listed / no id | dialog closes, Runs list, footer `Started — opening the run when it appears` / `Started — waiting for the run to appear` (S3, unchanged) |

#### Tests

All QML tests run with `qmltestrunner` offscreen through `bash tests/run.sh`. Panel tests never
let a helper run: `p.app.backendDir = "/plugin/core/backend/"` and each launch is answered through
`proc.outText = text; proc.exited(0)` (the `reply` helper in `tests/ui/tst_dispatch_flow.qml:81`).
Replies used: probe `{"ok":true,"projects":[{"root":R,"ok":true}]}` on
`app.runs.dispatchProjectRunner.current`; tree `{"ok":true,"data":[…brd tree…]}` on
`dispatchTargetRunner.current`; defaults `{"ok":true,"data":{"default_branch":"main"}}` on
`dispatchDefaultsRunner.current`; a non-open root's settings on `dispatchSettingsRunner.current`
(`get-run-settings` envelope with a `verify` list so the form passes); preview on
`dispatchPreviewRunner.current` for a board / milestone / story; start on
`dispatchStartRunners[0].current`.

##### UI flow tier — `tests/ui/tst_runs_flow.qml` (Panel + real stores; the behaviour is the wiring between Panel, the store and the dialog, which only the whole panel exercises)

1. **No project open → project → target → form → start → Run detail.** `makeNoProject()`
   (registry pA). Ctrl+6, Start run enabled with tooltip `Start an am run`; click. Dialog visible,
   `dispatchStep === "project"`, the active focus is `dispatchProjectKeys`. Reply the probe; Enter
   (or a click on the row) → step `target`, focus on the target filter, `projectName` is pA's
   name. Reply the tree; pick a subtask row (Down + Enter) → step `form`, `dispatchRoot` is pA's
   root, the story line shows the subtask's story from the replied tree. Reply defaults and
   settings until `ready`; Start twice (subtask confirm); reply start with a run id already in
   `app.runs.runs` → dialog hidden, `viewMode === "run"`, `selectedRunId` is the new id,
   `app.projects.selectedProject` still null.
2. **Start run disabled with an empty registry.** No project, registry `[]`: enabled false,
   tooltip `No projects registered`; a click opens nothing (`dispatchOpen` false, `dispatchStep`
   `""`). (Replaces `test_start_run_without_a_project_is_disabled_with_why`, `:871-885`.)
3. **Start run disabled with am missing.** No project, registry pA, `amStatus = "missing"`:
   disabled, tooltip `am is not installed or not on PATH`; with the registry also empty the
   tooltip is still the am one.
4. **Back and Escape from the Runs dialog.** At target, Back (button) → project step, focus on
   `dispatchProjectKeys`; at form, Back → target step with `targetKey` row under the cursor;
   Escape at the project step closes the dialog and the Runs search field has the focus.
5. **A Runs dialog with a project open keeps its project on a switch.** pA open, Start run, pick
   pA, pick a target; `navigator.chooseProject(pB)` (with the switch's runners disarmed) → dialog
   still visible, `dispatchRoot` unchanged, `dispatchStep` unchanged.
6. **The open project's board does not feed a Runs dispatch.** pA open with a board whose card
   ids overlap the replied tree's but with different titles: the Runs dispatch's story line shows
   the replied tree's title.

##### UI flow tier — `tests/ui/tst_shortcuts.qml` (Shortcuts on its own with a real App; the key guards are pure logic of that object)

7. **`d` on the Runs list opens the Runs dialog.** `inRuns()`, empty search: `handleDispatchKey(d)`
   true, `app.runs.dispatchStep === "project"`, no `dispatch:` action call. Cancel the probe runner
   afterwards.
8. **`d` on the Runs list with no project open.** Same with `selectedProject = null` and the
   registry still holding pA: true, step `project`.
9. **`d` on the Runs list is left alone (data-driven)**: search text; Shift+D; Ctrl+D; dropdown
   open; a modal open (e.g. `cancelOpen`); a dispatch already open (`dispatchStep = "project"`);
   am missing; empty registry; Run detail (`viewMode === "run"`). Each: returns false,
   `dispatchStep` stays as it was, no action call.
10. **A Runs dialog at a step is a modal.** `dispatchStep = "project"` with `dispatchState`
    `idle`: `modalOpen()` true, Ctrl+1 not handled, `p` on Runs not handled; `closeRequested()`
    closes it (`dispatchStep === ""`) and does not close the panel.
11. **Card entries unchanged**: the existing `d` board / card tests stay green; add one that `d`
    on the board list with a project leaves `dispatchStep === ""` (the action is called, the store
    is not opened from Runs).

##### UI flow tier — `tests/ui/tst_dispatch_flow.qml` and `tests/ui/tst_panel_toolbar.qml` (existing tests whose asserted behaviour this card changes)

12. Replace `test_the_runs_toolbar_opens_the_whole_board_with_a_row_of_targets` (`:367`) with:
    Start run with pA open opens at step `project` (not the whole board), with no chip row
    (`dispatchTargetChoices` not visible).
13. Replace `test_a_project_switch_drops_the_dialog_and_its_targets` (`:405`) with: a **card**
    dialog closes on a project switch (S3), and the Runs case is test 5.
14. **Card entry points skip the new steps**: card detail Dispatch and `d` on the board open with
    `dispatchStep === ""`, `dispatchRoot` the open project, dialog `step` `""` (no Back button,
    form shown at once).
15. `tests/ui/tst_panel_toolbar.qml` `test_start_run_shows_only_on_the_runs_list` (`:290-325`):
    the no-project tail asserts enabled true and `Start an am run` with pA registered, and the
    `Open a project to dispatch` assertion goes.

##### Architecture tier — `tests/architecture` (pytest, unchanged; stays green)

No new component, no store import in screens/components, icon glyph rules hold (`▶` is already
the Start run icon).

#### Out of scope

- `docs/architecture.md` and README updates: card 3.4 (`d3df5c9d`).
- Any change to `RunStore`, `runs.js`, `board-tree.py`, `start-run.py` or `DispatchDialog.qml`
  (including removing its now-unused `targetChoices` API).
- `RunsScreen.qml`, `Sidebar`, `Navigator.showSection`, card detail's Dispatch button.
- Skipping step 1 for a single project, offering `in_progress` subtasks (**P** 258-263).

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `ui/Shortcuts.qml` | modify | `d` on the Runs list opens the Runs dispatch; a dispatch at any Runs step is a modal for the chords, run keys and `d`, and closes on Escape (Task 1) |
| `ui/Panel.qml` | modify | Start run gating and click; `dispatchOpen`; focus on each step; the dialog's step bindings; the chip row removed (Task 2); one `dispatchCardMap` for the dispatched card, story, blockers and milestone offer (Task 3) |
| `tests/ui/tst_shortcuts.qml` | modify | spec tests 7–11; the `runs` row leaves `test_d_is_left_alone` (Task 1) |
| `tests/ui/tst_runs_flow.qml` | modify | spec tests 2–4 and Review Focus 1, 2, 4, 5 (Task 2); spec tests 1, 5, 6 and the milestone offer (Task 3); the F6 test goes |
| `tests/ui/tst_dispatch_flow.qml` | modify | spec tests 12–14 replace the two chip-row tests (Task 2) |
| `tests/ui/tst_panel_toolbar.qml` | modify | spec test 15 (Task 2) |

Run one file's tests with `bash tests/run.sh <path substring>`, e.g. `bash tests/run.sh ui/tst_shortcuts.qml`. pytest runs first (about a minute), then only the matching QML files. A failing QML test prints `FAIL!  : <Case>::<test>() ...` lines and a `Totals:` line per file.

---

### Task 1: `d` on the Runs list, and a Runs dispatch at a step is a modal

**Files:**
- Modify: `ui/Shortcuts.qml:1-98` (header comment, `closeRequested`, `modalOpen`, `handleDispatchKey`)
- Test: `tests/ui/tst_shortcuts.qml` (`test_d_is_left_alone_data` / `test_d_is_left_alone` at `:753-789`; new tests appended at the end of the file)

**Interfaces:**
- Consumes (existing, unchanged): `app.runs.dispatchOpenFromRuns(): bool`, `app.runs.dispatchStep: string` (`""` | `"project"` | `"target"` | `"form"`), `app.runs.dispatchState: string`, `app.runs.usableRoots(): [{root, name}]`, `app.runs.amStatus: string`, `app.runs.closeDispatch(): bool`, `app.runs.dispatchProjectRunner` (a `HelperRunner` with `cancel()`).
- Produces: `Shortcuts.modalOpen()` true while `app.runs.dispatchStep !== ""`; `Shortcuts.closeRequested()` closes a dispatch at any Runs step; `Shortcuts.handleDispatchKey(event): bool` opens the Runs dispatch on the Runs list. Panel's key routing (`handleGlobalKey || handleRunKey || handleDispatchKey`) is unchanged, so after this task a bare `d` in the empty Runs search opens the Runs dispatch through the panel too.

- [ ] **Step 1: Remove the `runs` row from the existing "left alone" test**

In `tests/ui/tst_shortcuts.qml`, `test_d_is_left_alone_data()` currently reads:

```qml
  function test_d_is_left_alone_data() {
    return [
      { tag: "shift" }, { tag: "ctrl" }, { tag: "search-text" }, { tag: "no-project" }, { tag: "am-missing" },
      { tag: "am-missing-on-story" },
      { tag: "dropdown" }, { tag: "modal" }, { tag: "dispatch-open" }, { tag: "runs" }, { tag: "graph" },
      { tag: "documents" }, { tag: "empty-board" }, { tag: "cursor-past-the-end" }, { tag: "other-letter" }
    ]
  }
```

Replace it with (the `runs` row is gone — `d` on the Runs list now opens the Runs dispatch; its own rows are in Step 2):

```qml
  function test_d_is_left_alone_data() {
    return [
      { tag: "shift" }, { tag: "ctrl" }, { tag: "search-text" }, { tag: "no-project" }, { tag: "am-missing" },
      { tag: "am-missing-on-story" },
      { tag: "dropdown" }, { tag: "modal" }, { tag: "dispatch-open" }, { tag: "graph" },
      { tag: "documents" }, { tag: "empty-board" }, { tag: "cursor-past-the-end" }, { tag: "other-letter" }
    ]
  }
```

and in `test_d_is_left_alone(data)` delete this one line of the `switch`:

```qml
    case "runs": s.navigator.showSection("runs"); break
```

- [ ] **Step 2: Write the new tests**

Append these functions to `tests/ui/tst_shortcuts.qml`, just before the file's final closing `}` (after `test_escape_while_a_start_is_in_flight_does_nothing`). They use the file's existing helpers `make()`, `inRuns()` (project A open, pA and pB registered, the Runs list shown, run `run-0000000000a1` escalated with no lease), `onBoard()`, `dispatched()`, `plain()`, `shift()`, `ctrl()` and `tc.calls`.

```qml
  // ---- d on the Runs list: the Runs dispatch (3.3)

  // 7
  function test_d_on_the_runs_list_opens_the_runs_dispatch_at_the_project_step() {
    var s = inRuns(); if (!s) return
    compare(s.app.nav.searchQuery, "")
    compare(s.handleDispatchKey(plain(Qt.Key_D)), true)
    compare(s.app.runs.dispatchStep, "project")
    compare(s.app.runs.dispatchState, "idle")
    compare(s.app.runs.dispatchRoot, "")
    compare(dispatched().length, 0, "no card dispatch is asked for")
    s.app.runs.dispatchProjectRunner.cancel()
  }

  // 8
  function test_d_on_the_runs_list_opens_the_runs_dispatch_with_no_project_open() {
    var s = inRuns(); if (!s) return
    s.app.projects.selectedProject = null
    s.app.nav.viewMode = "runs"
    compare(s.app.runs.usableRoots().length, 2, "the registry still lists A and B")
    compare(s.handleDispatchKey(plain(Qt.Key_D)), true)
    compare(s.app.runs.dispatchStep, "project")
    compare(dispatched().length, 0)
    s.app.runs.dispatchProjectRunner.cancel()
  }

  // 9
  function test_d_on_the_runs_list_is_left_alone_data() {
    return [
      { tag: "search-text" }, { tag: "shift" }, { tag: "ctrl" }, { tag: "dropdown" }, { tag: "modal" },
      { tag: "dispatch-open" }, { tag: "am-missing" }, { tag: "empty-registry" }, { tag: "run-detail" }
    ]
  }

  function test_d_on_the_runs_list_is_left_alone(data) {
    var s = inRuns(); if (!s) return
    var e = plain(Qt.Key_D)
    switch (data.tag) {
    case "search-text": s.app.nav.searchQuery = "al"; break
    case "shift": e = shift(Qt.Key_D); break
    case "ctrl": e = ctrl(Qt.Key_D); break
    case "dropdown":
      s.navigator.toggleDropdown()
      compare(s.app.nav.dropdownOpen, true)
      break
    case "modal": s.app.runs.cancelRunId = "run-0000000000a1"; break
    case "dispatch-open": s.app.runs.dispatchStep = "project"; break
    case "am-missing": s.app.runs.amStatus = "missing"; break
    case "empty-registry":
      s.app.runs.projectRoots = []
      s.app.runs.snapshotRunner.cancel()
      compare(s.app.runs.usableRoots().length, 0)
      break
    case "run-detail":
      s.navigator.openRun("run-0000000000a1", "runs")
      compare(s.app.nav.viewMode, "run")
      break
    }
    var before = s.app.runs.dispatchStep
    compare(s.handleDispatchKey(e), false)
    compare(s.app.runs.dispatchStep, before, "nothing opened")
    compare(dispatched().length, 0)
  }

  // 10
  function test_a_runs_dispatch_at_a_step_is_a_modal_data() {
    return [{ tag: "project", step: "project" }, { tag: "target", step: "target" }]
  }

  function test_a_runs_dispatch_at_a_step_is_a_modal(data) {
    var s = inRuns(); if (!s) return
    compare(s.modalOpen(), false)
    s.app.runs.dispatchStep = data.step
    compare(s.app.runs.dispatchState, "idle")
    compare(s.modalOpen(), true)
    compare(s.handleGlobalKey(ctrl(Qt.Key_1)), false)
    compare(s.app.nav.viewMode, "runs", "no chord acted")
    compare(s.handleRunKey(plain(Qt.Key_P)), false)
    compare(s.app.runs.flashText, "", "no run key acted")
    s.closeRequested()
    compare(s.app.runs.dispatchStep, "")
    compare(s.app.nav.viewMode, "runs", "that Escape closed the dialog only")
    compare(tc.calls.indexOf("close"), -1, "the panel stays open")
  }

  // 11
  function test_d_on_the_board_list_leaves_the_runs_steps_shut() {
    var s = onBoard(); if (!s) return
    compare(s.handleDispatchKey(plain(Qt.Key_D)), true)
    compare(dispatched().join(","), "dispatch:m1")
    compare(s.app.runs.dispatchStep, "")
  }
```

- [ ] **Step 3: Run the tests to verify the new ones fail**

Run: `bash tests/run.sh ui/tst_shortcuts.qml`
Expected: FAIL on
- `test_d_on_the_runs_list_opens_the_runs_dispatch_at_the_project_step` (`handleDispatchKey` returns false: `Actual (): false / Expected (): true`)
- `test_d_on_the_runs_list_opens_the_runs_dispatch_with_no_project_open` (same)
- `test_a_runs_dispatch_at_a_step_is_a_modal(project)` and `(target)` (`modalOpen()` is false)

`test_d_on_the_runs_list_is_left_alone(*)` and `test_d_on_the_board_list_leaves_the_runs_steps_shut` pass already — they pin the guards and the card entry. Every other test in the file passes.

- [ ] **Step 4: Implement the Runs-list `d`, the modal and the Escape branch**

In `ui/Shortcuts.qml`, replace the header comment (lines 4–12):

```qml
// Every key the panel reacts to, in one place: the Ctrl chords, the run keys
// (p / r / c), the dispatch key (d), the Escape chain, the arrows the key
// catcher reports, and the search field's own keys.
// The ORDER of the guards here is load bearing -- a modal must swallow the
// global shortcuts, and Escape must unwind the modals before it unwinds the
// navigation -- so nothing in this file may be reordered.
// The panel hands in `actions`: close(), scrollBy(px), switchPanel(direction),
// searchAtEnd() (is the caret at the end of the search text?) and
// openDispatch(target) (a card id: open the dispatch dialog on it).
```

with:

```qml
// Every key the panel reacts to, in one place: the Ctrl chords, the run keys
// (p / r / c), the dispatch key (d: a card's dispatch on the board list and
// a card, the Runs dispatch on the Runs list), the Escape chain, the arrows
// the key catcher reports, and the search field's own keys.
// The ORDER of the guards here is load bearing -- a modal must swallow the
// global shortcuts, and Escape must unwind the modals before it unwinds the
// navigation -- so nothing in this file may be reordered.
// The panel hands in `actions`: close(), scrollBy(px), switchPanel(direction),
// searchAtEnd() (is the caret at the end of the search text?) and
// openDispatch(target) (a card id: open the dispatch dialog on it).
```

Replace `closeRequested()` and its comment (lines 39–46):

```qml
  // Escape (and the key catcher's close gesture): innermost thing first. The
  // run toasts come right after the modals: they are not a modal, but an
  // Escape with toasts showing never goes Back or closes the panel. An open
  // dispatch closes like the other modals; while its start is in flight
  // closeDispatch() refuses, so that Escape does nothing at all.
  function closeRequested() {
    keys.app.deleter.deleteTarget ? keys.app.deleter.cancelDelete() : keys.app.board.archiveOpen ? keys.app.board.cancelArchive() : keys.app.memories.memoryDeleteOpen ? keys.app.memories.cancelMemoryDelete() : keys.app.memories.newMemoryOpen ? keys.app.memories.cancelNewMemory() : keys.app.milestones.dialogOpen ? keys.app.milestones.cancelDialog() : keys.app.runs.dispatchState !== "idle" ? keys.app.runs.closeDispatch() : keys.app.runs.cancelOpen ? keys.app.runs.closeCancel() : keys.app.runs.toasts.length > 0 ? keys.app.runs.dismissAllToasts() : (keys.app.nav.dropdownOpen ? keys.navigator.closeDropdown() : ((keys.app.nav.viewMode === "entry" || keys.app.nav.viewMode === "document" || keys.app.nav.viewMode === "memory" || keys.app.nav.viewMode === "issue" || keys.app.nav.viewMode === "run") ? keys.navigator.goBack() : keys.actions.close()))
  }
```

with:

```qml
  // Escape (and the key catcher's close gesture): innermost thing first. The
  // run toasts come right after the modals: they are not a modal, but an
  // Escape with toasts showing never goes Back or closes the panel. An open
  // dispatch -- any state but idle, or a Runs dispatch at any step -- closes
  // like the other modals; while its start is in flight closeDispatch()
  // refuses, so that Escape does nothing at all.
  function closeRequested() {
    keys.app.deleter.deleteTarget ? keys.app.deleter.cancelDelete() : keys.app.board.archiveOpen ? keys.app.board.cancelArchive() : keys.app.memories.memoryDeleteOpen ? keys.app.memories.cancelMemoryDelete() : keys.app.memories.newMemoryOpen ? keys.app.memories.cancelNewMemory() : keys.app.milestones.dialogOpen ? keys.app.milestones.cancelDialog() : (keys.app.runs.dispatchState !== "idle" || keys.app.runs.dispatchStep !== "") ? keys.app.runs.closeDispatch() : keys.app.runs.cancelOpen ? keys.app.runs.closeCancel() : keys.app.runs.toasts.length > 0 ? keys.app.runs.dismissAllToasts() : (keys.app.nav.dropdownOpen ? keys.navigator.closeDropdown() : ((keys.app.nav.viewMode === "entry" || keys.app.nav.viewMode === "document" || keys.app.nav.viewMode === "memory" || keys.app.nav.viewMode === "issue" || keys.app.nav.viewMode === "run") ? keys.navigator.goBack() : keys.actions.close()))
  }
```

Replace `modalOpen()` and its comment (lines 48–53):

```qml
  // A modal is open: the global shortcuts, the run keys and d do nothing under it.
  function modalOpen() {
    return !!(keys.app.deleter.deleteTarget || keys.app.memories.memoryDeleteOpen || keys.app.memories.newMemoryOpen
              || keys.app.milestones.dialogOpen || keys.app.board.archiveOpen || keys.app.runs.cancelOpen
              || keys.app.runs.dispatchState !== "idle")
  }
```

with:

```qml
  // A modal is open: the global shortcuts, the run keys and d do nothing under
  // it. A dispatch is one in any state but idle, and a Runs dispatch at any
  // step.
  function modalOpen() {
    return !!(keys.app.deleter.deleteTarget || keys.app.memories.memoryDeleteOpen || keys.app.memories.newMemoryOpen
              || keys.app.milestones.dialogOpen || keys.app.board.archiveOpen || keys.app.runs.cancelOpen
              || keys.app.runs.dispatchState !== "idle" || keys.app.runs.dispatchStep !== "")
  }
```

Replace `handleDispatchKey` and its comment (lines 80–98):

```qml
  // d with no modifier at all opens the dispatch dialog -- it never starts
  // anything: on the board list for the cursor card, there only while the
  // search is empty (the search field has the focus and every letter types
  // once it holds text; Shift+D always types), and on a card for that card.
  // Needs a project and am; under a modal or the open dropdown, or anywhere
  // else, the letter is left alone.
  function handleDispatchKey(event) {
    if (event.modifiers !== Qt.NoModifier || event.key !== Qt.Key_D) return false
    var mode = keys.app.nav.viewMode
    if (!keys.app.projects.selectedProject || (mode !== "board" && mode !== "entry")) return false
```

with (the rest of the function, from `if (keys.app.runs.amStatus === "missing" || keys.modalOpen() ...` down to its closing `}`, stays as it is):

```qml
  // d with no modifier at all opens the dispatch dialog -- it never starts
  // anything. On the Runs list it opens the Runs dispatch at its project
  // step (dispatchOpenFromRuns), with or without a project open; it needs am
  // and a usable registered root. On the board list it opens the cursor
  // card's dispatch and on a card that card's (actions.openDispatch); those
  // need a project and am. On both lists only while the search is empty: the
  // search field has the focus and every letter types once it holds text
  // (Shift+D always types). Under a modal or the open dropdown, on Run
  // detail, or anywhere else, the letter is left alone.
  function handleDispatchKey(event) {
    if (event.modifiers !== Qt.NoModifier || event.key !== Qt.Key_D) return false
    var mode = keys.app.nav.viewMode
    if (mode === "runs") {
      if (keys.app.nav.searchQuery !== "" || keys.modalOpen() || keys.app.nav.dropdownOpen) return false
      if (keys.app.runs.amStatus === "missing" || keys.app.runs.usableRoots().length === 0) return false
      keys.app.runs.dispatchOpenFromRuns()
      return true
    }
    if (!keys.app.projects.selectedProject || (mode !== "board" && mode !== "entry")) return false
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/run.sh ui/tst_shortcuts.qml`
Expected: every test in `tst_shortcuts.qml` passes (`Totals: N passed, 0 failed`), and no `TypeError` / `ReferenceError` lines.

Then run the panel-level files that route keys through Shortcuts, to see nothing else moved:
Run: `bash tests/run.sh tst_dispatch_flow`
Expected: all pass (no test there presses `d` on the Runs list; its two chip-row tests are replaced in Task 2). If any test fails, stop and fix before committing.

- [ ] **Step 6: Commit**

```bash
git add ui/Shortcuts.qml tests/ui/tst_shortcuts.qml
git commit -m "feat(dispatch): d on the Runs list opens the Runs dispatch, and a Runs step is a modal"
```

---

### Task 2: Start run, the dialog's open state, focus and step bindings in Panel

**Files:**
- Modify: `ui/Panel.qml:93-107` (the `appStores.runs` Connections), `:266-274` and `:308-357` (the dispatch section), `:401-403` (key routing comment), `:547-561` (Start run), `:892-929` (the `DispatchDialog` mount)
- Test: `tests/ui/tst_runs_flow.qml` (F6 test `:870-885` removed; new helpers and tests)
- Test: `tests/ui/tst_dispatch_flow.qml` (`:364-414` replaced)
- Test: `tests/ui/tst_panel_toolbar.qml` (`test_start_run_shows_only_on_the_runs_list` tail, `:318-325`)

**Interfaces:**
- Consumes (existing store API): `appStores.runs.dispatchOpenFromRuns(): bool`, `dispatchProjectPick(root: string): bool`, `dispatchTargetPick(key: string): bool`, `dispatchBack(): bool`, `closeDispatch(): bool`, `usableRoots(): [{root, name}]`, `dispatchStep: string`, `dispatchRoot: string`, `dispatchProjectRows: [{root, name, open, enabled, reason}]`, `dispatchTargetRows: [{key, level, card, label, depth}]` (`key` `"board"` or `"card:<id>"`, `card` the string `"board"` or a brd card object), `dispatchTargetLoading: bool`, `dispatchTargetKey: string`. Dialog API (existing): props `step`, `projectName`, `projectRows`, `targetRows`, `targetLoading`, `targetKey`; signals `projectChosen(string root)`, `targetPicked(string key)`, `backRequested()`, `cancelRequested()`; readonly `focusItem`, `targetCursor`. From Task 1: Shortcuts' Runs-list `d`.
- Produces (Panel, used by Task 3 and by tests): `readonly property bool dispatchOpen`, `property string dispatchCardId`, `readonly property string dispatchProjectName`, `function pickRunsTarget(key: string)`, `function openDispatch(target: string)` (unchanged contract). Removed: `dispatchChoices`, `dispatchRetargeting`, `openRunsDispatch`, `runsDispatchChoices`, `launchDispatch` (folded into `openDispatch`).

- [ ] **Step 1: Write the failing Panel-flow tests in `tests/ui/tst_runs_flow.qml`**

First delete the whole F6 test (lines 870–885 today), which asserts the `Open a project to dispatch` tooltip:

```qml
  // F6
  function test_start_run_without_a_project_is_disabled_with_why() {
    var p = makeNoProject(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    var button = H.find(p, "startRunButton")
    compare(button.visible, true)
    compare(button.enabled, false)
    compare(String(button.tooltipText), "Open a project to dispatch")
    mouseClick(button)
    compare(p.dispatchOpen, false, "a click opens nothing")
    compare(p.app.runs.dispatchState, "idle")
    p.app.runs.amStatus = "missing"
    compare(button.enabled, false)
    compare(String(button.tooltipText), "Open a project to dispatch", "no project wins over am missing")
  }
```

Then append the following before the file's final closing `}` (after `test_open_project_with_a_dirty_memory_draft_stays_on_runs`). It uses the file's existing `hostC`, `pA`, `pB`, `sampleRuns()`, `reply(proc, text, code)`, `disarmSwitch(p)` and `ctrl6(p)`.

```qml
  // ---- the Runs dispatch (3.3)

  // A brd card as board-tree.py lists it; blockedBy undefined leaves
  // blocked_by out.
  function card(id, title, status, children, blockedBy) {
    var c = { id: id, title: title, status: status, description: "d", children: children || [] }
    if (blockedBy !== undefined) c.blocked_by = blockedBy
    return c
  }

  // m1 > s1 > t0 (done), t1 (blocked by t0, issue i1 and an unknown id), t2;
  // m9 is a done milestone. Its target rows: board, m1, s1, t1, t2.
  function tree() {
    return [
      card("m1", "M one", "todo", [
        card("s1", "Story one", "todo", [
          card("t0", "Prep", "done", [], []),
          card("t1", "Do it", "todo", [], ["t0", "i1", "ghost"]),
          card("t2", "Loose end", "todo")
        ])
      ]),
      card("m9", "M nine", "done")
    ]
  }

  // A Panel on the Runs list whose helpers never run (each launch a test
  // cares about is answered through reply()): `registry` registered, pA open
  // when `open`, else no project open.
  function makeDispatch(registry, open) {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.app.backendDir = "/plugin/core/backend/"
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList(registry)
    disarmSwitch(p)
    p.app.extras.extrasLoading = false
    p.app.runs.snapshotRunner.cancel()
    if (!open) p.app.projects.selectedProject = null
    p.app.runs.runSettings = { verify: ["uv run pytest"] }
    p.app.runs.runs = sampleRuns()
    ctrl6(p)
    compare(p.app.nav.viewMode, "runs")
    return p
  }

  function dialog(p) { return H.find(p, "dispatchDialog") }
  function textOf(p, name) { return String(H.find(p, name).text) }

  // board-tree.py --probe's reply: every root in `roots` readable.
  function probeOk(p, roots) {
    reply(p.app.runs.dispatchProjectRunner.current,
          JSON.stringify({ ok: true, projects: roots.map(function(r) { return { root: r, ok: true } }) }) + "\n", 0)
  }

  // Start run clicked and the probe answered: the project step.
  function startRun(p) {
    H.find(p, "startRunButton").clicked()
    compare(p.app.runs.dispatchStep, "project")
    probeOk(p, p.app.runs.usableRoots().map(function(r) { return r.root }))
    wait(50)
  }

  // The dialog's pick of the project at `root`, then the tree read answered
  // with tree(): the target step.
  function toTarget(p, root) {
    dialog(p).projectChosen(root)
    compare(p.app.runs.dispatchStep, "target")
    reply(p.app.runs.dispatchTargetRunner.current, JSON.stringify({ ok: true, data: tree() }) + "\n", 0)
    compare(p.app.runs.dispatchTargetRows.map(function(r) { return r.key }).join(","),
            "board,card:m1,card:s1,card:t1,card:t2")
    wait(50)
  }

  // The dialog's pick of the target row `key`: the form step.
  function toForm(p, key) {
    dialog(p).targetPicked(key)
    compare(p.app.runs.dispatchStep, "form")
    wait(50)
  }

  // 2
  function test_start_run_with_an_empty_registry_is_disabled_with_why() {
    var p = makeDispatch([], false); if (!p) return
    wait(50)
    var button = H.find(p, "startRunButton")
    compare(button.visible, true)
    compare(button.enabled, false)
    compare(String(button.tooltipText), "No projects registered")
    mouseClick(button)
    compare(p.dispatchOpen, false, "a click opens nothing")
    compare(p.app.runs.dispatchStep, "")
  }

  // 3
  function test_start_run_with_am_missing_is_disabled_with_why() {
    var p = makeDispatch([tc.pA], false); if (!p) return
    p.app.runs.amStatus = "missing"
    wait(50)
    var button = H.find(p, "startRunButton")
    compare(button.enabled, false)
    compare(String(button.tooltipText), "am is not installed or not on PATH")
    p.app.projects.applyProjectsList([])
    p.app.runs.snapshotRunner.cancel()
    compare(p.app.runs.usableRoots().length, 0)
    compare(button.enabled, false)
    compare(String(button.tooltipText), "am is not installed or not on PATH", "am missing wins over an empty registry")
  }

  // 4
  function test_back_and_escape_in_the_runs_dialog() {
    var p = makeDispatch([tc.pA], false); if (!p) return
    var button = H.find(p, "startRunButton")
    compare(button.enabled, true)
    compare(String(button.tooltipText), "Start an am run")
    startRun(p)
    compare(dialog(p).visible, true)
    compare(String(dialog(p).step), "project")
    compare(p.focusItem.objectName, "dispatchProjectKeys")
    verify(H.find(p, "dispatchProjectKeys").activeFocus, "the project step has the keyboard")
    toTarget(p, "/home/u/a")
    compare(p.focusItem.objectName, "dispatchTargetFilter")
    verify(H.find(p, "dispatchTargetFilter").activeFocus, "the target step has the keyboard")
    H.find(p, "dispatchBack").clicked()
    compare(p.app.runs.dispatchStep, "project")
    compare(dialog(p).visible, true)
    wait(50)
    verify(H.find(p, "dispatchProjectKeys").activeFocus, "Back to the project step moves the keyboard there")
    toTarget(p, "/home/u/a")
    toForm(p, "card:t1")
    compare(p.dispatchCardId, "t1")
    H.find(p, "dispatchBack").clicked()
    compare(p.app.runs.dispatchStep, "target")
    compare(p.app.runs.dispatchTargetKey, "card:t1")
    wait(50)
    compare(dialog(p).targetCursor, 3, "the picked row is under the cursor")
    verify(H.find(p, "dispatchTargetFilter").activeFocus, "Back to the target step moves the keyboard there")
    H.find(p, "dispatchBack").clicked()
    wait(50)
    verify(H.find(p, "dispatchProjectKeys").activeFocus)
    keyClick(Qt.Key_Escape)
    compare(p.app.runs.dispatchStep, "")
    compare(dialog(p).visible, false)
    compare(p.app.nav.viewMode, "runs", "that Escape closed the dialog only")
    compare(p.opened, true)
    wait(50)
    compare(p.focusItem.objectName, "searchField")
    verify(H.find(p, "searchField").activeFocus, "the focus is back on the Runs search")
  }

  // Review Focus 2
  function test_escape_in_the_target_filter_closes_the_runs_dialog() {
    var p = makeDispatch([tc.pA], false); if (!p) return
    startRun(p)
    toTarget(p, "/home/u/a")
    verify(H.find(p, "dispatchTargetFilter").activeFocus)
    keyClick(Qt.Key_Escape)
    compare(p.app.runs.dispatchStep, "")
    compare(dialog(p).visible, false)
    compare(p.app.nav.viewMode, "runs")
    wait(50)
    verify(H.find(p, "searchField").activeFocus, "the focus is back on the Runs search")
  }

  // Review Focus 5
  function test_d_typed_in_the_target_filter_filters() {
    var p = makeDispatch([tc.pA], false); if (!p) return
    startRun(p)
    toTarget(p, "/home/u/a")
    keyClick("d")
    compare(String(H.find(p, "dispatchTargetFilter").text), "d", "the letter went into the filter")
    compare(p.app.runs.dispatchStep, "target")
    compare(p.app.runs.dispatchRoot, "/home/u/a")
    p.app.runs.closeDispatch()
  }

  // Review Focus 4
  function test_the_board_row_dispatches_the_whole_board() {
    var p = makeDispatch([tc.pA], false); if (!p) return
    startRun(p)
    toTarget(p, "/home/u/a")
    toForm(p, "card:m1")
    compare(p.dispatchCardId, "m1")
    compare(textOf(p, "dispatchTarget"), "Target   Milestone \"M one\"")
    H.find(p, "dispatchBack").clicked()
    toForm(p, "board")
    compare(p.dispatchCardId, "", "the board row has no card")
    compare(textOf(p, "dispatchTarget"), "Target   Whole board")
    p.app.runs.closeDispatch()
  }

  // Review Focus 1
  function test_a_registry_emptied_under_the_project_step_keeps_the_dialog() {
    var p = makeDispatch([tc.pA], false); if (!p) return
    startRun(p)
    p.app.projects.applyProjectsList([])
    p.app.runs.snapshotRunner.cancel()
    p.navigator.showSection("runs")
    wait(50)
    compare(dialog(p).visible, true)
    compare(p.app.runs.dispatchStep, "project")
    compare(H.find(p, "dispatchProjectEmpty").visible, true)
    compare(textOf(p, "dispatchProjectEmpty"), "No projects registered")
    compare(H.find(p, "startRunButton").enabled, false)
    compare(String(H.find(p, "startRunButton").tooltipText), "No projects registered")
    p.app.runs.closeDispatch()
  }

  // B5 through the panel: d in the empty Runs search.
  function test_d_in_the_empty_runs_search_opens_the_runs_dialog_without_typing() {
    var p = makeDispatch([tc.pA], false); if (!p) return
    wait(50)
    var field = H.find(p, "searchField")
    field.forceActiveFocus()
    keyClick("d")
    compare(p.app.runs.dispatchStep, "project")
    compare(dialog(p).visible, true)
    compare(String(field.text), "", "the handled letter was not typed")
    wait(50)
    verify(H.find(p, "dispatchProjectKeys").activeFocus, "the dialog took the keyboard")
    p.app.runs.closeDispatch()
  }
```

- [ ] **Step 2: Replace the two chip-row tests in `tests/ui/tst_dispatch_flow.qml`**

Replace the block from the `// 21` comment above `test_the_runs_toolbar_opens_the_whole_board_with_a_row_of_targets` through the end of `test_a_project_switch_drops_the_dialog_and_its_targets` (lines 366–414 today; `test_without_am_start_run_is_disabled` right after stays) with:

```qml
  // 21 (spec 12)
  function test_the_runs_toolbar_opens_the_project_step() {
    var p = make(); if (!p) return
    compare(p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 }), true)
    wait(50)
    var button = H.find(p, "startRunButton")
    compare(button.visible, true)
    compare(button.enabled, true)
    compare(String(button.tooltipText), "Start an am run")
    button.clicked()
    var dialog = H.find(p, "dispatchDialog")
    compare(dialog.visible, true)
    compare(p.app.runs.dispatchStep, "project")
    compare(p.app.runs.dispatchState, "idle")
    compare(p.app.runs.dispatchRoot, "")
    compare(String(dialog.step), "project")
    compare(H.find(p, "dispatchProjectList").visible, true)
    compare(H.find(p, "dispatchTarget").visible, false, "not the whole board")
    compare(H.find(p, "dispatchTargetChoices").visible, false, "no row of targets")
    p.app.runs.closeDispatch()
  }

  // 30 (spec 13): a card dialog closes on a project switch; a Runs dialog
  // stays (tests/ui/tst_runs_flow.qml).
  function test_a_project_switch_closes_a_card_dialog() {
    var p = make(); if (!p) return
    dispatchCard(p, "m1")
    compare(H.find(p, "dispatchDialog").visible, true)
    p.navigator.chooseProject(tc.pB)
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.runs.settingsLoadRunner.cancel()
    p.app.runs.runSettingsRunner.cancel()
    compare(p.app.runs.dispatchState, "idle")
    compare(p.app.runs.dispatchStep, "")
    compare(H.find(p, "dispatchDialog").visible, false)
  }

  // spec 14: the card entry points skip the Runs steps.
  function test_the_card_entries_open_the_form_at_once_data() {
    return [{ tag: "card-detail" }, { tag: "d-on-the-board" }]
  }

  function test_the_card_entries_open_the_form_at_once(data) {
    var p = make(); if (!p) return
    if (data.tag === "card-detail") {
      dispatchCard(p, "m1")
    } else {
      p.navigator.showSection("board")
      p.app.nav.cursorIndex = 0
      wait(50)
      H.find(p, "searchField").forceActiveFocus()
      keyClick("d")
    }
    var dialog = H.find(p, "dispatchDialog")
    compare(dialog.visible, true)
    compare(p.dispatchCardId, "m1")
    compare(p.app.runs.dispatchStep, "")
    compare(p.app.runs.dispatchRoot, "/home/u/a")
    compare(String(dialog.step), "")
    compare(H.find(p, "dispatchBack").visible, false, "no Back")
    compare(H.find(p, "dispatchForm").visible, true, "the form at once")
    verify(!p.app.runs.dispatchProjectRunner.current, "a card entry probes nothing")
  }
```

- [ ] **Step 3: Update spec test 15 in `tests/ui/tst_panel_toolbar.qml`**

In `test_start_run_shows_only_on_the_runs_list`, replace the tail (from `p.app.projects.selectedProject = null` to the end of the function):

```qml
    p.app.projects.selectedProject = null
    p.app.nav.viewMode = "runs"
    compare(button.visible, true, "no project: still shown")
    compare(button.enabled, false)
    compare(String(button.tooltipText), "Open a project to dispatch")
  }
```

with:

```qml
    p.app.runs.amStatus = "ok"
    p.app.projects.selectedProject = null
    p.app.nav.viewMode = "runs"
    compare(button.visible, true, "no project: still shown")
    compare(button.enabled, true, "pA is registered: there is a project to pick")
    compare(String(button.tooltipText), "Start an am run")
  }
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_runs_flow`
Expected FAIL: `test_start_run_with_an_empty_registry_is_disabled_with_why` (tooltip `Open a project to dispatch`), `test_start_run_with_am_missing_is_disabled_with_why` (tooltip), `test_back_and_escape_in_the_runs_dialog` (`dispatchStep` is `""` after Start run), `test_escape_in_the_target_filter_closes_the_runs_dialog`, `test_d_typed_in_the_target_filter_filters`, `test_the_board_row_dispatches_the_whole_board` (all: `dispatchStep` `""` after Start run), `test_a_registry_emptied_under_the_project_step_keeps_the_dialog` (same), `test_d_in_the_empty_runs_search_opens_the_runs_dialog_without_typing` (the store is at `project` after Task 1 but `dialog(p).visible` is false).

Run: `bash tests/run.sh tst_dispatch_flow`
Expected FAIL: `test_the_runs_toolbar_opens_the_project_step` (`dispatchStep` `""`, the old whole-board dialog). `test_a_project_switch_closes_a_card_dialog` and `test_the_card_entries_open_the_form_at_once(*)` pass already (pins).

Run: `bash tests/run.sh tst_panel_toolbar`
Expected FAIL: `test_start_run_shows_only_on_the_runs_list` (`enabled` false, tooltip `Open a project to dispatch`).

- [ ] **Step 5: Panel — focus on every step change**

In `ui/Panel.qml`, replace the `appStores.runs` Connections block (lines 93–107):

```qml
  // A different Runs chip means a different list: the cursor reset is App's,
  // the scroll is the panel's. The cancel confirmation takes the focus when it
  // opens and gives it back when it closes. A started dispatch closes its
  // dialog and goes to the run; the run is usually not in the snapshot yet,
  // so every new list may hold the run the navigator still waits for.
  Connections {
    target: appStores.runs
    function onRunFilterToggled() { Qt.callLater(root.scrollToTop) }
    function onCancelOpenChanged() { root.focusForView() }
    function onDispatchStarted(runId) {
      appStores.runs.closeDispatch()
      navi.openStartedRun(runId)
    }
    function onRunsChanged() { navi.openAwaitedRun() }
  }
```

with:

```qml
  // A different Runs chip means a different list: the cursor reset is App's,
  // the scroll is the panel's. The cancel confirmation takes the focus when it
  // opens and gives it back when it closes; the open dispatch dialog takes it
  // at each Runs step. A started dispatch closes its dialog and goes to the
  // run; the run is usually not in the snapshot yet, so every new list may
  // hold the run the navigator still waits for.
  Connections {
    target: appStores.runs
    function onRunFilterToggled() { Qt.callLater(root.scrollToTop) }
    function onCancelOpenChanged() { root.focusForView() }
    function onDispatchStepChanged() { if (root.dispatchOpen) root.focusForView() }
    function onDispatchStarted(runId) {
      appStores.runs.closeDispatch()
      navi.openStartedRun(runId)
    }
    function onRunsChanged() { navi.openAwaitedRun() }
  }
```

- [ ] **Step 6: Panel — the dispatch section's head**

Replace (lines 266–274):

```qml
  // ---- Dispatch (S3 4.2). Panel opens every dispatch: a refused plan does
  // not say which card it was for, and the dialog needs the card's title,
  // story and blockers, so the card is kept here. The Runs entry adds a row
  // of targets (the whole board, then each milestone that can be dispatched),
  // which survives a re-target but not a close.
  property string dispatchCardId: ""   // the target card's id; "" for the board
  property var dispatchChoices: []     // [{id, label}]; [] unless opened from Runs
  property bool dispatchRetargeting: false
  readonly property bool dispatchOpen: appStores.runs.dispatchState !== "idle"
```

with:

```qml
  // ---- Dispatch (S3 4.2). The card detail's Dispatch and d on the board
  // list or a card open it on a card (openDispatch); a refused plan does not
  // say which card it was for, and the dialog needs the card's title, story
  // and blockers, so the card is kept here. Start run and d on the Runs list
  // open it at RunStore's project step (dispatchOpenFromRuns); there the card
  // is the target row picked (pickRunsTarget).
  property string dispatchCardId: ""   // the target card's id; "" for the board
  // A dispatch in any state but idle, or a Runs dispatch at any step.
  readonly property bool dispatchOpen: appStores.runs.dispatchState !== "idle" || appStores.runs.dispatchStep !== ""
  // The target step's heading: the name of dispatchRoot's project row, else
  // the root itself; "" with no dispatchRoot.
  readonly property string dispatchProjectName: {
    var picked = appStores.runs.dispatchRoot
    if (picked === "") return ""
    var rows = appStores.runs.dispatchProjectRows
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].root !== picked) continue
      return typeof rows[i].name === "string" && rows[i].name !== "" ? rows[i].name : picked
    }
    return picked
  }
```

(Lines 275–306 — `dispatchCard` through `blockerText` — stay as they are in this task; Task 3 rewrites them.)

- [ ] **Step 7: Panel — open, pick and the focus handler; the chip-row path goes**

Replace the block from `  // The dialog takes the focus when it opens and gives it back when it closes,` (line 308) through the end of `launchDispatch` (line 357):

```qml
  // The dialog takes the focus when it opens and gives it back when it closes,
  // never on a re-preview, which would pull the caret out of the field being
  // typed in. A re-target passes through idle, so it lands on the new dialog;
  // any other way to idle (Cancel, Escape, a project switch) drops the target
  // row. Closing the panel is not one: RunStore keeps an open dispatch across
  // it, and the row stays with the dialog.
  onDispatchOpenChanged: {
    if (!root.dispatchOpen && !root.dispatchRetargeting) root.dispatchChoices = []
    root.focusForView()
  }

  // A card id or "board": the card detail's Dispatch and d. Neither shows the
  // target row.
  function openDispatch(target) {
    root.dispatchChoices = []
    root.launchDispatch(target)
  }

  // The Runs entry: Start run opens the whole board, a target chip re-opens on
  // its target. The row is built once per opening and kept across re-targets,
  // so the chip just clicked is never torn down under its own click.
  function openRunsDispatch(target) {
    root.dispatchRetargeting = true
    root.launchDispatch(target)
    root.dispatchRetargeting = false
    if (!root.dispatchOpen) root.dispatchChoices = []
    else if (root.dispatchChoices.length === 0) root.dispatchChoices = root.runsDispatchChoices()
  }

  // The whole board, then each root card dispatchPlan offers, in board order.
  // Read through cardMap: its cards carry the depth dispatchPlan needs.
  function runsDispatchChoices() {
    var choices = [{ id: "board", label: "Whole board" }]
    var roots = appStores.board.cardRoots
    for (var i = 0; i < roots.length; i++) {
      var card = roots[i] ? appStores.board.cardMap[roots[i].id] : null
      if (card && Runs.dispatchPlan(card, appStores.board.cardMap).offered)
        choices.push({ id: card.id, label: String(card.title || "") })
    }
    return choices
  }

  // The store refuses a re-open while a start is in flight; the card kept here
  // must then stay the one being started.
  function launchDispatch(target) {
    if (appStores.runs.dispatchState === "starting") return
    var board = target === "board"
    root.dispatchCardId = board ? "" : String(target)
    appStores.runs.openDispatch(board ? "board" : appStores.board.cardMap[target], appStores.board.cardMap)
  }
```

with:

```qml
  // The dialog takes the focus when it opens (and at each Runs step, see the
  // runs Connections) and gives it back when it closes, never on a
  // re-preview, which would pull the caret out of the field being typed in.
  // Closing the panel does not close it: RunStore keeps an open dispatch
  // across it.
  onDispatchOpenChanged: root.focusForView()

  // A card id or "board": the card detail's Dispatch and d on the board list
  // or a card. The store refuses a re-open while a start is in flight; the
  // card kept here must then stay the one being started.
  function openDispatch(target) {
    if (appStores.runs.dispatchState === "starting") return
    var board = target === "board"
    root.dispatchCardId = board ? "" : String(target)
    appStores.runs.openDispatch(board ? "board" : appStores.board.cardMap[target], appStores.board.cardMap)
  }

  // A row picked at the Runs target step: the store opens the form on it, and
  // only then is its card the dispatched one ("" for the board row).
  function pickRunsTarget(key) {
    if (!appStores.runs.dispatchTargetPick(key)) return
    var rows = appStores.runs.dispatchTargetRows
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].key !== key) continue
      var card = rows[i].card
      root.dispatchCardId = card !== null && typeof card === "object" ? String(card.id) : ""
      return
    }
  }
```

- [ ] **Step 8: Panel — the key routing comment**

Replace (lines 401–403):

```qml
    // The Ctrl chords, then the run keys (p / r / c on the Runs list and Run
    // detail), then d (the dispatch, on the board list and a card). An
    // accepted key is not typed into the search field.
```

with:

```qml
    // The Ctrl chords, then the run keys (p / r / c on the Runs list and Run
    // detail), then d (the dispatch: on the board list and a card for a card,
    // on the Runs list at the project step). An accepted key is not typed
    // into the search field.
```

- [ ] **Step 9: Panel — Start run**

Replace (lines 547–561):

```qml
          // The Runs list's way to start a run on the open project: the dialog
          // opens on its whole board with a row of targets. Shown with or
          // without a project; disabled with none or while am is missing, and
          // the tooltip says which (no project first).
          UI.ActionButton {
            objectName: "startRunButton"
            theme: panelTheme
            visible: appStores.nav.viewMode === "runs"
            enabled: !!appStores.projects.selectedProject && appStores.runs.amStatus !== "missing"
            iconText: "▶"
            text: "Start run"
            tooltipText: !appStores.projects.selectedProject ? "Open a project to dispatch"
              : appStores.runs.amStatus === "missing" ? "am is not installed or not on PATH" : "Start an am run"
            onClicked: root.openRunsDispatch("board")
          }
```

with:

```qml
          // The Runs list's way to start a run: the dialog opens at its
          // project step (dispatchOpenFromRuns). Shown on the Runs list with
          // or without a project; disabled while am is missing or no usable
          // project is registered, and the tooltip says which (am first).
          UI.ActionButton {
            objectName: "startRunButton"
            theme: panelTheme
            visible: appStores.nav.viewMode === "runs"
            enabled: appStores.runs.amStatus !== "missing" && appStores.runs.usableRoots().length > 0
            iconText: "▶"
            text: "Start run"
            tooltipText: appStores.runs.amStatus === "missing" ? "am is not installed or not on PATH"
              : appStores.runs.usableRoots().length === 0 ? "No projects registered" : "Start an am run"
            onClicked: appStores.runs.dispatchOpenFromRuns()
          }
```

- [ ] **Step 10: Panel — the dialog mount**

Replace the mount (lines 892–929):

```qml
      // The dispatch (S3 4.2): the card detail's Dispatch and d open it for a
      // card, the Runs toolbar's Start run for the whole board with a row of
      // targets. Panel keeps the card (dispatchCardId) and the row, and
      // composes the subtask's story and blockers; the store holds the rest.
      DispatchDialog {
        id: dispatchDialog
        objectName: "dispatchDialog"
        anchors.fill: parent
        shown: root.dispatchOpen
        theme: panelTheme
        dispatchState: appStores.runs.dispatchState
        target: appStores.runs.dispatchTarget
        targetTitle: root.dispatchCard ? String(root.dispatchCard.title || "") : ""
        targetLabel: appStores.runs.dispatchTargetLabel
        form: appStores.runs.dispatchForm
        preview: appStores.runs.dispatchPreview
        error: appStores.runs.dispatchError
        logPath: appStores.runs.dispatchLog
        logTail: appStores.runs.dispatchLogTail
        exitCode: appStores.runs.dispatchExitCode
        storyTitle: root.dispatchStoryTitle
        blockedText: root.dispatchBlockedText
        confirmFirst: root.dispatchSubtask
        suggestion: root.dispatchSuggestion
        targetChoices: root.dispatchChoices
        targetChoice: root.dispatchCardId === "" ? "board" : root.dispatchCardId
        onFieldEdited: function(name, value) { appStores.runs.setDispatchField(name, value) }
        onStartRequested: appStores.runs.dispatchStart()
        onCancelRequested: appStores.runs.closeDispatch()
        // The store reopens on the milestone and clears its suggestion; the
        // card follows only when it did.
        onSuggestionRequested: {
          if (!root.dispatchSuggestion) return
          var milestoneId = root.dispatchSuggestion.id
          if (appStores.runs.retargetToMilestone()) root.dispatchCardId = milestoneId
        }
        onTargetChosen: function(id) { root.openRunsDispatch(id) }
      }
```

with:

```qml
      // The dispatch (S3 4.2): the card detail's Dispatch and d open it for a
      // card at the form; Start run and d on the Runs list open it at the
      // store's project step, then its target step, then the form. Panel
      // keeps the card (dispatchCardId) and composes the subtask's story and
      // blockers; the store holds the rest.
      DispatchDialog {
        id: dispatchDialog
        objectName: "dispatchDialog"
        anchors.fill: parent
        shown: root.dispatchOpen
        theme: panelTheme
        step: appStores.runs.dispatchStep
        projectName: root.dispatchProjectName
        projectRows: appStores.runs.dispatchProjectRows
        targetRows: appStores.runs.dispatchTargetRows
        targetLoading: appStores.runs.dispatchTargetLoading
        targetKey: appStores.runs.dispatchTargetKey
        dispatchState: appStores.runs.dispatchState
        target: appStores.runs.dispatchTarget
        targetTitle: root.dispatchCard ? String(root.dispatchCard.title || "") : ""
        targetLabel: appStores.runs.dispatchTargetLabel
        form: appStores.runs.dispatchForm
        preview: appStores.runs.dispatchPreview
        error: appStores.runs.dispatchError
        logPath: appStores.runs.dispatchLog
        logTail: appStores.runs.dispatchLogTail
        exitCode: appStores.runs.dispatchExitCode
        storyTitle: root.dispatchStoryTitle
        blockedText: root.dispatchBlockedText
        confirmFirst: root.dispatchSubtask
        suggestion: root.dispatchSuggestion
        onProjectChosen: function(projectRoot) { appStores.runs.dispatchProjectPick(projectRoot) }
        onTargetPicked: function(key) { root.pickRunsTarget(key) }
        onBackRequested: appStores.runs.dispatchBack()
        onFieldEdited: function(name, value) { appStores.runs.setDispatchField(name, value) }
        onStartRequested: appStores.runs.dispatchStart()
        onCancelRequested: appStores.runs.closeDispatch()
        // The store reopens on the milestone and clears its suggestion; the
        // card follows only when it did.
        onSuggestionRequested: {
          if (!root.dispatchSuggestion) return
          var milestoneId = root.dispatchSuggestion.id
          if (appStores.runs.retargetToMilestone()) root.dispatchCardId = milestoneId
        }
      }
```

(The handler parameter is `projectRoot`, not `root`: `root` is Panel's id.)

- [ ] **Step 11: Check no stale name is left**

Run: `grep -rn "Open a project to dispatch\|dispatchChoices\|openRunsDispatch\|runsDispatchChoices\|dispatchRetargeting\|launchDispatch" ui/ tests/`
Expected: no output.

- [ ] **Step 12: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_runs_flow`
Expected: all pass, no `TypeError` / `ReferenceError` lines.

Run: `bash tests/run.sh tst_dispatch_flow`
Expected: all pass.

Run: `bash tests/run.sh tst_panel_toolbar`
Expected: all pass.

Run: `bash tests/run.sh ui/tst_shortcuts.qml`
Expected: all pass.

- [ ] **Step 13: Commit**

```bash
git add ui/Panel.qml tests/ui/tst_runs_flow.qml tests/ui/tst_dispatch_flow.qml tests/ui/tst_panel_toolbar.qml
git commit -m "feat(dispatch): Start run opens the Runs dispatch at the project step, gated on am and a registered project"
```

---

### Task 3: The dispatched card, its story and its blockers come from the picked tree

**Files:**
- Modify: `ui/Panel.qml` (the `dispatchCard` … `blockerText` block, lines 275–306 before Task 2; find it by its first line `  readonly property var dispatchCard: root.dispatchCardId !== ""`)
- Test: `tests/ui/tst_runs_flow.qml` (new tests appended after Task 2's)

**Interfaces:**
- Consumes: `appStores.runs.dispatchTargetCardMap: {id: card} | null`, `appStores.runs.dispatchStep`, `appStores.runs.dispatchRoot`, `appStores.runs.project: string` (the open project's root, `""` with none), `appStores.board.cardMap`, `appStores.board.issueMap`, `appStores.board.statusText(status): string`, `Board.resolvedCard(id, cardMap, issueMap): {id, title, status, inBoard, kind?}`, `Board.issueBlockerLabel(status): string`; from Task 2 `dispatchCardId`, `pickRunsTarget`, and the test helpers `makeDispatch`, `startRun`, `toTarget`, `toForm`, `dialog`, `textOf`, `probeOk`, `card`, `tree`.
- Produces: `readonly property var dispatchCardMap` on Panel; `dispatchCard`, `dispatchStoryTitle`, `dispatchBlockedText`, `dispatchSuggestion` and `blockerText(id)` read through it.

- [ ] **Step 1: Write the failing tests**

Append to `tests/ui/tst_runs_flow.qml`, before the final closing `}` (after Task 2's tests):

```qml
  // 1
  function test_with_no_project_start_run_walks_the_steps_and_lands_on_the_new_run() {
    var p = makeDispatch([tc.pA], false); if (!p) return
    var button = H.find(p, "startRunButton")
    compare(button.visible, true)
    compare(button.enabled, true)
    compare(String(button.tooltipText), "Start an am run")
    button.clicked()
    compare(dialog(p).visible, true)
    compare(p.app.runs.dispatchStep, "project")
    probeOk(p, ["/home/u/a"])
    wait(50)
    compare(p.focusItem.objectName, "dispatchProjectKeys")
    verify(H.find(p, "dispatchProjectKeys").activeFocus, "the project step has the keyboard")
    keyClick(Qt.Key_Return)
    compare(p.app.runs.dispatchStep, "target")
    compare(p.app.runs.dispatchRoot, "/home/u/a")
    compare(String(dialog(p).projectName), "alpha")
    compare(textOf(p, "dispatchHeading"), "Dispatch · 2 Target in alpha")
    reply(p.app.runs.dispatchTargetRunner.current, JSON.stringify({ ok: true, data: tree() }) + "\n", 0)
    wait(50)
    compare(p.focusItem.objectName, "dispatchTargetFilter")
    verify(H.find(p, "dispatchTargetFilter").activeFocus, "the target step has the keyboard")
    keyClick(Qt.Key_Down)
    keyClick(Qt.Key_Down)
    keyClick(Qt.Key_Down)
    compare(dialog(p).targetCursor, 3)
    keyClick(Qt.Key_Return)
    compare(p.app.runs.dispatchStep, "form")
    compare(p.dispatchCardId, "t1")
    compare(textOf(p, "dispatchTarget"), "Target   Subtask \"Do it\"")
    compare(textOf(p, "dispatchStory"), "Story   \"Story one\"")
    compare(textOf(p, "dispatchBlocked"),
            "Blocked by: \"Prep\" (Done), i1 (not on this board), ghost (not on this board)")
    reply(p.app.runs.dispatchDefaultsRunner.current, '{"ok":true,"data":{"default_branch":"main"}}\n', 0)
    reply(p.app.runs.dispatchSettingsRunner.current, '{"verify":["uv run pytest"]}\n', 0)
    compare(p.app.runs.dispatchState, "ready")
    var start = H.find(p, "dispatchStart")
    start.clicked()
    compare(p.app.runs.dispatchState, "ready", "the first click only arms")
    start.clicked()
    compare(p.app.runs.dispatchState, "starting")
    reply(p.app.runs.dispatchStartRunners[0].current, '{"ok":true,"run_id":"run-0000000000b2","message":"started"}\n', 0)
    // A good start fetches the runs again; that launch cannot run here.
    p.app.runs.snapshotRunner.cancel()
    compare(dialog(p).visible, false)
    compare(p.app.runs.dispatchStep, "")
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000b2")
    compare(p.app.projects.selectedProject, null, "no project was opened")
  }

  // 5
  function test_a_runs_dialog_keeps_its_project_across_a_project_switch() {
    var p = makeDispatch([tc.pA, tc.pB], true); if (!p) return
    startRun(p)
    toTarget(p, "/home/u/a")
    toForm(p, "card:t1")
    compare(textOf(p, "dispatchStory"), "Story   \"Story one\"")
    p.navigator.chooseProject(tc.pB)
    disarmSwitch(p)
    compare(p.app.projects.selectedProject.root_path, "/home/u/b")
    compare(dialog(p).visible, true)
    compare(p.app.runs.dispatchRoot, "/home/u/a")
    compare(p.app.runs.dispatchStep, "form")
    compare(p.dispatchCardId, "t1")
    compare(textOf(p, "dispatchStory"), "Story   \"Story one\"", "still the picked tree's story")
    compare(textOf(p, "dispatchBlocked"),
            "Blocked by: \"Prep\" (Done), i1 (not on this board), ghost (not on this board)",
            "another project is open: its issues name nothing here")
    p.app.runs.closeDispatch()
  }

  // 6 and Review Focus 3
  function test_the_open_board_does_not_feed_a_runs_dispatch() {
    var p = makeDispatch([tc.pA], true); if (!p) return
    p.app.board.applyTreeData([card("m1", "Board milestone", "todo", [
      card("s1", "Board story", "todo", [card("t1", "Board task", "todo", [], ["i1"])])])])
    p.app.board.applyIssueData([{ id: "i1", title: "Broken build", status: "open" }])
    wait(50)
    startRun(p)
    toTarget(p, "/home/u/a")
    toForm(p, "card:t1")
    compare(textOf(p, "dispatchTarget"), "Target   Subtask \"Do it\"")
    compare(textOf(p, "dispatchStory"), "Story   \"Story one\"", "the replied tree's story, not the board's")
    compare(textOf(p, "dispatchBlocked"),
            "Blocked by: \"Prep\" (Done), \"Broken build\" (Issue · open), ghost (not on this board)",
            "the open project's issues name a blocker of its own tree")
    p.app.runs.closeDispatch()
  }

  // B4: the milestone offer of a blocked story reads the picked tree.
  function test_a_blocked_story_of_a_runs_dispatch_offers_its_milestone() {
    var p = makeDispatch([tc.pA], false); if (!p) return
    startRun(p)
    toTarget(p, "/home/u/a")
    toForm(p, "card:s1")
    compare(p.dispatchCardId, "s1")
    reply(p.app.runs.dispatchDefaultsRunner.current, '{"ok":true,"data":{"default_branch":"main"}}\n', 0)
    reply(p.app.runs.dispatchSettingsRunner.current, '{"verify":["uv run pytest"]}\n', 0)
    compare(p.app.runs.dispatchState, "previewing")
    reply(p.app.runs.dispatchPreviewRunner.current,
          '{"ok":false,"error":{"type":"StoryBlockedError","message":"Story blocked by s0"}}\n', 0)
    compare(p.app.runs.dispatchState, "refused")
    var offer = H.find(p, "dispatchSuggest")
    compare(offer.visible, true, "the milestone is in the picked tree")
    offer.clicked()
    compare(p.dispatchCardId, "m1")
    compare(p.app.runs.dispatchTarget.level, "milestone")
    compare(textOf(p, "dispatchTarget"), "Target   Milestone \"M one\"")
    compare(p.app.runs.dispatchStep, "form")
    p.app.runs.closeDispatch()
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_runs_flow`
Expected FAIL:
- `test_with_no_project_start_run_walks_the_steps_and_lands_on_the_new_run` at the `dispatchStory` compare (`Story   ""`: no project open, the board's `cardMap` is empty).
- `test_a_runs_dialog_keeps_its_project_across_a_project_switch` at its first `dispatchStory` compare (same: no board was loaded).
- `test_the_open_board_does_not_feed_a_runs_dispatch` (`Story   "Board story"`).
- `test_a_blocked_story_of_a_runs_dispatch_offers_its_milestone` (`dispatchSuggest` not visible: `m1` is not in the board's `cardMap`).
Every Task 2 test still passes.

- [ ] **Step 3: Implement `dispatchCardMap`**

In `ui/Panel.qml`, replace this block (it starts right after `dispatchProjectName` from Task 2 and ends before the `// The dialog takes the focus ...` comment above `onDispatchOpenChanged`):

```qml
  readonly property var dispatchCard: root.dispatchCardId !== ""
    ? (appStores.board.cardMap[root.dispatchCardId] || null) : null
  readonly property bool dispatchSubtask: !!appStores.runs.dispatchTarget
    && appStores.runs.dispatchTarget.level === "subtask"
  // am has no dry run for one subtask, so its story and blockers are said
  // here instead; "" for any other target, and for a card the board dropped.
  readonly property string dispatchStoryTitle: {
    if (!root.dispatchSubtask || !root.dispatchCard) return ""
    var story = appStores.board.cardMap[root.dispatchCard.parentId]
    return story ? String(story.title || "") : ""
  }
  readonly property string dispatchBlockedText: {
    if (!root.dispatchSubtask || !root.dispatchCard) return ""
    var ids = root.dispatchCard.blocked_by
    var list = ids && typeof ids.length === "number" ? Array.prototype.slice.call(ids) : []
    if (list.length === 0) return "Blocked by: nothing"
    return "Blocked by: " + list.map(function(id) { return root.blockerText(id) }).join(", ")
  }
  // A refused story's milestone, offered only while it is on the board.
  readonly property var dispatchSuggestion: {
    var suggest = appStores.runs.dispatchSuggest
    return suggest && typeof suggest.id === "string" && appStores.board.cardMap[suggest.id] ? suggest : null
  }

  // One blocker as the dialog lists it: a card of this board with its status,
  // an issue with its state, anything else by its id.
  function blockerText(id) {
    var resolved = appStores.board.resolvedCard(id)
    if (resolved.inBoard) return "\"" + resolved.title + "\" (" + appStores.board.statusText(resolved.status) + ")"
    if (resolved.kind === "issue") return "\"" + resolved.title + "\" (" + Board.issueBlockerLabel(resolved.status) + ")"
    return id + " (not on this board)"
  }
```

with:

```qml
  // The card map the dispatched card, its story, its blockers and the
  // milestone offer are read from: a Runs dispatch's picked tree
  // (dispatchTargetCardMap, {} before its read), else the open board's.
  readonly property var dispatchCardMap: appStores.runs.dispatchStep !== ""
    ? (appStores.runs.dispatchTargetCardMap || {}) : appStores.board.cardMap
  readonly property var dispatchCard: root.dispatchCardId !== ""
    ? (root.dispatchCardMap[root.dispatchCardId] || null) : null
  readonly property bool dispatchSubtask: !!appStores.runs.dispatchTarget
    && appStores.runs.dispatchTarget.level === "subtask"
  // am has no dry run for one subtask, so its story and blockers are said
  // here instead; "" for any other target, and for a card the map dropped.
  readonly property string dispatchStoryTitle: {
    if (!root.dispatchSubtask || !root.dispatchCard) return ""
    var story = root.dispatchCardMap[root.dispatchCard.parentId]
    return story ? String(story.title || "") : ""
  }
  readonly property string dispatchBlockedText: {
    if (!root.dispatchSubtask || !root.dispatchCard) return ""
    var ids = root.dispatchCard.blocked_by
    var list = ids && typeof ids.length === "number" ? Array.prototype.slice.call(ids) : []
    if (list.length === 0) return "Blocked by: nothing"
    return "Blocked by: " + list.map(function(id) { return root.blockerText(id) }).join(", ")
  }
  // A refused story's milestone, offered only while it is in the card map.
  readonly property var dispatchSuggestion: {
    var suggest = appStores.runs.dispatchSuggest
    return suggest && typeof suggest.id === "string" && root.dispatchCardMap[suggest.id] ? suggest : null
  }

  // One blocker as the dialog lists it: a card of the card map with its
  // status, an issue of the open board with its state while the dispatch is
  // for the open project, anything else by its id.
  function blockerText(id) {
    var issues = appStores.runs.dispatchRoot === appStores.runs.project ? appStores.board.issueMap : {}
    var resolved = Board.resolvedCard(id, root.dispatchCardMap, issues)
    if (resolved.inBoard) return "\"" + resolved.title + "\" (" + appStores.board.statusText(resolved.status) + ")"
    if (resolved.kind === "issue") return "\"" + resolved.title + "\" (" + Board.issueBlockerLabel(resolved.status) + ")"
    return id + " (not on this board)"
  }
```

A card entry has `dispatchStep === ""` and `dispatchRoot === project` (`RunStore.openDispatch`), so its map is `board.cardMap` and its issues `board.issueMap` — exactly `board.resolvedCard(id)` as before.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_runs_flow`
Expected: all pass.

Run: `bash tests/run.sh tst_dispatch_flow`
Expected: all pass — in particular `test_a_subtask_shows_its_story_and_blockers_and_starts_on_the_second_click` still reads `Blocked by: "Prep" (Done), "Broken build" (Issue · open), ghost (not on this board)` (card entries unchanged).

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest green (the architecture tier included: no store import in screens/components, icon glyph rules hold), every QML file `Totals: N passed, 0 failed`, exit status 0, no `TypeError` / `ReferenceError` / `is not a function` lines.

- [ ] **Step 6: Commit**

```bash
git add ui/Panel.qml tests/ui/tst_runs_flow.qml
git commit -m "feat(dispatch): a Runs dispatch reads its card, story and blockers from the picked project's tree"
```

---

## Spec coverage check

| Spec item | Task |
|---|---|
| B1 Start run visibility, enabled, tooltip order, click, `Open a project to dispatch` gone, chip-row path removed | Task 2 (Steps 6, 7, 9, 10, 11); tests 2, 3, 15, Review Focus 1 |
| B2 `dispatchOpen`, `focusItem` order kept, focus on open / close / each step, re-preview never moves focus, close returns focus to the Runs search | Task 2 (Steps 5, 6, 7); tests 4, Review Focus 2; existing `test_a_re_preview_leaves_the_caret_in_the_field_being_typed_in` |
| B3 mount bindings (`step`, `projectRows`, `projectName`, `targetRows`, `targetLoading`, `targetKey`, `onProjectChosen`, `onTargetPicked` + `dispatchCardId`, `onBackRequested`, `onCancelRequested`) | Task 2 (Steps 6, 7, 10); tests 1, 4, Review Focus 4 |
| B4 `dispatchCardMap`, story, blockers with the issue map rule, milestone offer, card entries unchanged | Task 3; tests 1, 5, 6, milestone offer test; existing card-entry tests |
| B5 `modalOpen`, `closeRequested`, `handleDispatchKey` on the Runs list, board/card branch unchanged, comments | Task 1; tests 7–11; Task 2 panel-level `d` test |
| Error paths: am missing, empty registry, registry empties while open, `d` with search text, keys under the dialog, Escape at project / target, project switch (Runs / card), start landing | tests 2, 3, Review Focus 1, 9, 10, 4, Review Focus 2, 5, 13, 1; existing tests 24–27 in `tst_dispatch_flow.qml` |
| Tests 12–14 (`tst_dispatch_flow.qml`), 15 (`tst_panel_toolbar.qml`) | Task 2 Steps 2–3 |
| Architecture tier unchanged and green | Task 3 Step 5 |
<!-- task-pipeline: validated -->
