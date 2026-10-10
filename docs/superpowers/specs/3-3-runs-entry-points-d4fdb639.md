# 3.3 Runs entry points and gating — design

Card `d4fdb639` (subtask of story `7fad1523` "Dispatch from Runs UI"), after card 3.2
(`f377621e`, the dialog's target step). Parent design:
`docs/superpowers/specs/2026-10-05-dispatch-from-runs-design.md` (cited below as **P**, with line
numbers). Sibling specs: `3-1-dispatchdialog-the-e04a0de6.md` (**S31**, the project step) and
`3-2-dispatchdialog-the-f377621e.md` (**S32**, the target step), whose "Out of scope" (S32
217-221) hands this card the Panel wiring.

## Problem

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

## Goal

From the Runs list, with or without a project open, **Start run** or a bare `d` opens the
dispatch dialog at the project step through `app.runs.dispatchOpenFromRuns()`; the user picks a
project, then a target, then S3's form starts the run and the panel lands on the new run's
detail. The card entry points behave exactly as before.

## Inherited constraints

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

## Behaviour

### B1. Start run (`ui/Panel.qml`, `startRunButton`)

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

### B2. The dialog's open state and focus (`ui/Panel.qml`)

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

### B3. The mount's step bindings (`ui/Panel.qml`, `dispatchDialog`)

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

### B4. The dispatched card in a Runs dispatch (`ui/Panel.qml`)

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

### B5. Shortcuts (`ui/Shortcuts.qml`)

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

### Error and edge paths

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

## Tests

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

### UI flow tier — `tests/ui/tst_runs_flow.qml` (Panel + real stores; the behaviour is the wiring between Panel, the store and the dialog, which only the whole panel exercises)

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

### UI flow tier — `tests/ui/tst_shortcuts.qml` (Shortcuts on its own with a real App; the key guards are pure logic of that object)

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

### UI flow tier — `tests/ui/tst_dispatch_flow.qml` and `tests/ui/tst_panel_toolbar.qml` (existing tests whose asserted behaviour this card changes)

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

### Architecture tier — `tests/architecture` (pytest, unchanged; stays green)

No new component, no store import in screens/components, icon glyph rules hold (`▶` is already
the Start run icon).

## Out of scope

- `docs/architecture.md` and README updates: card 3.4 (`d3df5c9d`).
- Any change to `RunStore`, `runs.js`, `board-tree.py`, `start-run.py` or `DispatchDialog.qml`
  (including removing its now-unused `targetChoices` API).
- `RunsScreen.qml`, `Sidebar`, `Navigator.showSection`, card detail's Dispatch button.
- Skipping step 1 for a single project, offering `in_progress` subtasks (**P** 258-263).
