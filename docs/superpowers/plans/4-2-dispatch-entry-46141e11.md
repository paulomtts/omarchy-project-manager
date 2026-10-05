# 4.2 Dispatch entry points Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mount the 4.1 `DispatchDialog` in `Panel.qml` and reach it from three entry points (the card detail's `▶ Dispatch`, a bare `d` on the board list or a card, and the Runs toolbar's `▶ Start run` with a row of target chips), add the dialog's three deferred features (target chips, the story → milestone offer, the subtask's two-click Start), and after a start close the dialog and take the user to the run — waiting for the snapshot that lists it.

**Architecture:** Panel owns every dispatch: `root.openDispatch(target)` records the card id and calls `RunStore.openDispatch`, and the Runs entry's `root.openRunsDispatch(target)` does the same while keeping a list of target chips. The dialog stays presentation only (new props `targetChoices`, `targetChoice`, `suggestion`, `confirmFirst`, readonly `armed`; new signals `targetChosen(id)`, `suggestionRequested()`). Shortcuts gets `handleDispatchKey` plus the dispatch link in `modalOpen()` and the Escape chain; Navigator gets `openStartedRun(runId)` / `openAwaitedRun()`, which waits for the snapshot that lists the started run. No store, domain file or backend helper changes.

**Tech Stack:** QML (Qt 6 / Quickshell shell types from `qs.Ui`, stubbed in `tests/stubs`), QtTest via `qmltestrunner`, run by `bash tests/run.sh [filter]` (pytest runs first, then every `tst_*.qml` whose path contains the filter; the run fails on any `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item` or `is not a function` in the output).

**Spec:** `docs/superpowers/specs/4-2-dispatch-entry-46141e11.md` (copied verbatim below, headings demoted one level).

---

## The spec (verbatim)

## 4.2 Dispatch entry points (card 46141e11)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-dispatch-design.md` (S3,
"the parent" below): "Dispatch levels" (lines 30-41), the Flow diagram's three
entries (lines 46-52) and its end state (line 68), the confirm rule (lines
82-85), "Architecture" (lines 108-112: on `started` the navigation to Run detail
is a signal the `Navigator` handles; lines 118-121: a Dispatch button in
`CardDetailScreen` and the Runs toolbar, key `d` in `Shortcuts.qml`), "Safety"
(lines 123-134), "Errors" (line 140: am missing disables the button; line 144:
run id not found → dialog closes, "Started — waiting for the run to appear",
Runs screen), "Testing" (line 157: UI flows from each entry point, Start
navigates to Run detail). Parent story c56468c7 ("Dispatch UI"). Sibling card
4.1 (dfc0ac87, spec `docs/superpowers/specs/4-1-dispatchdialog-dfc0ac87.md`)
built `ui/components/DispatchDialog.qml` and left to this card (its "Out of
scope"): mounting it, `focusItem` in Panel's chain, `modalOpen()`, key `d`, the
Runs toolbar target pick, the story → milestone offer, the subtask's extra
confirm, composing the subtask's story and `blocked_by` strings, and the
navigation after `started`.

This card mounts the dialog, adds the three entry points, adds the three small
dialog features 4.1 deferred, and navigates after a start. It changes no store,
no domain file and no backend helper.

### Starting point (all on this branch)

- `core/stores/RunStore.qml`: `openDispatch(card, cardMap)` (line 914; `card`
  as `Board.indexTree` leaves it, or the string `"board"`; returns false and
  changes nothing without a project or while `starting`; a story, finished card
  or no card goes straight to `refused` with `dispatchErrorType` `Target` and,
  for a story, `dispatchSuggest = {id, title}` of its milestone);
  `closeDispatch()` (line 937; false while `starting`); `setDispatchField(name,
  value)` (line 1041); `dispatchStart()` (line 1062; only from `ready`); signal
  `dispatchStarted(var runId)` (line 126; `null` when am does not list the run
  yet), emitted right after `store.refresh()`, which is asynchronous, so the run
  is normally **not** in `runs` yet when the signal fires. `flash(text)` (line
  745) shows text for 3 s in the Runs screen's `runsFooter`. A project switch
  resets the dispatch to `idle` (line 320). A refused plan carries no card id
  (`core/domain/runs.js` line 811: `flags: []`).
- `core/domain/runs.js` `dispatchPlan` (line 820): depth 0 → `milestone`, 1 →
  `story` (refused, `A story is dispatched through its milestone`), ≥2 →
  `subtask`; a card whose status is finished is refused `The card is <status>`.
- `ui/components/DispatchDialog.qml` (4.1): props `shown`, `theme`,
  `dispatchState`, `target`, `targetTitle`, `form`, `preview`, `error`,
  `logPath`, `logTail`, `exitCode`, `storyTitle`, `blockedText`; readonly
  `focusItem`, `canStart`, `busy`, `editable`; signals `fieldEdited(name,
  value)`, `startRequested()`, `cancelRequested()`. Not mounted anywhere.
- `ui/Shortcuts.qml`: `handleRunKey` (line 57) is the pattern for a bare
  letter: no modifier, a selected project, `!modalOpen()`, dropdown closed, and
  on a list only while `nav.searchQuery === ""` (the search field has focus and
  letters type). `closeRequested()` (line 41) is the Escape chain; `modalOpen()`
  (line 46) the one guard for chords and run keys. The file header says the
  guard order is load-bearing.
- `ui/Panel.qml`: `globalKeys` (line ~285) calls `sc.handleGlobalKey(event) ||
  sc.handleRunKey(event)`; both the key catcher and the search field forward to
  it. `focusItem` chain at lines 169-178. Toolbar `RowLayout` at lines ~337-425.
  Dialogs mounted at the end (z 100 over `RunToast` z 50). `openToastRun` (line
  ~229) is the existing "go to Runs, open a run or flash why not" pattern.
- `ui/Navigator.qml`: `showSection(name)` (line 168), `openRun(id, from)` (line
  330; returns silently for an id not in `app.runs.runs`).
- The board list (`viewMode` `board`) lists root cards only
  (`BoardStore.boardCards`, line 139): its cursor is always on a milestone. The
  card detail (`viewMode` `entry`) shows any card:
  `app.board.cardMap[app.board.selectedCardId]`.
- The S1 "missing" sentence is `am is not installed or not on PATH`
  (`ui/screens/RunsScreen.qml` line 105).
- There is no plain-text toast: `RunToast` renders only escalation alerts
  (`{key, id, title, state, reason}`); the only generic message channel is
  `flash()`.
- Panel's toolbar row (`panelToolbar`) has no Runs-only button, and there is no
  target picker anywhere.

### Scope

In scope:

- `ui/Panel.qml`: mount `DispatchDialog`; the owner functions and bindings
  below; the `Start run` toolbar button; focus; the started → navigate wiring.
- `ui/Shortcuts.qml`: key `d`; dispatch in `modalOpen()` and in the Escape chain.
- `ui/Navigator.qml`: `openStartedRun(runId)` and `openAwaitedRun()`.
- `ui/screens/CardDetailScreen.qml`: the Dispatch button.
- `ui/components/DispatchDialog.qml`: target choices, the milestone offer, the
  confirm-first step.
- `docs/architecture.md`: the `DispatchDialog` entry (no longer "Not yet
  mounted"; the three new features), the `Shortcuts.qml` sentence (`d`,
  dispatch in `modalOpen()` and Escape), the `Navigator.qml` sentence
  (`openStartedRun`, `openAwaitedRun`), and one sentence on the Panel-owned
  dispatch (who opens it, who closes it, where it navigates).
- Tests listed under "Tests".

#### Out of scope

- Any change to `RunStore.qml`, `App.qml`, `runs.js`, `board.js` or a backend
  helper. If a test needs store behaviour that does not exist, that is a
  finding to report, not a store change.
- The per-viewer "Confirm dispatches" setting (parent lines 82-85) and its
  storage: here the subtask's extra confirm is always on, and milestone and
  board dispatches have no extra confirm (they are gated by their preview,
  parent lines 125-126).
- A read-only mode (parent lines 166-167).
- Turning a `ClaimedError`'s other run id into a link (parent lines 128-129).
- A new toast kind or any change to `RunToast` (D6).
- A timeout for a run awaited after start; reopening the panel onto it.
- Dispatch from the Graph, the Issues section or a Run detail.
- Navigator's own `showSection` guard list: the dialog's backdrop covers the
  sidebar and `modalOpen()` blocks the chords, so nothing reaches it.

### Decisions

- **D1. Panel opens every dispatch.** A refused plan does not say which card it
  was for (`runs.js` line 811), and the dialog needs the card's title, story and
  blockers, so one owner function records the card and opens the store:
  `root.openDispatch(target)` with `target` a card id or `"board"`. It sets
  `root.dispatchCardId` (the id, or `""` for the board), clears
  `root.dispatchChoices`, and calls `appStores.runs.openDispatch(target ===
  "board" ? "board" : appStores.board.cardMap[target], appStores.board.cardMap)`.
  The card detail reaches it through a signal (screens import no store,
  `tests/architecture/test_layers.py`); Shortcuts through a new `actions`
  member `openDispatch(target)`, like `close` and `scrollBy`.
- **D2. The Runs entry is a toolbar button that opens the dialog with a target
  row.** `Start run` (Panel toolbar, Runs only) calls
  `root.openRunsDispatch("board")`: the dialog opens on the whole board, with a
  row of target chips — `Whole board` then each root card `Runs.dispatchPlan`
  offers (not finished), in `app.board.cardRoots` order, labelled by title.
  Clicking another chip calls `root.openRunsDispatch(id)`, which re-opens the
  store on that target and keeps the chips. No separate picker step and no new
  component: the chips are `UI.ChipRow` inside the dialog. The board is the
  default because it is the one target only reachable here; its preview is a
  dry run, and its warning names every open milestone.
- **D3. The story offer is a dialog button.** For `refused` with a
  `suggestion` whose id is on the board, the dialog shows the refusal sentence
  (4.1) and a button `Dispatch its milestone "<title>"`; its click emits
  `suggestionRequested()`, and Panel calls `root.openDispatch(suggest.id)`. That
  is "offers its milestone and says so" (parent line 37).
- **D4. The subtask's explicit confirm lives in the dialog.** A new prop
  `confirmFirst` (Panel binds it to `dispatchTarget.level === "subtask"`).
  While `confirmFirst` and `canStart`, the first click on Start only arms the
  dialog: Start reads `Confirm start` and a line `Click Confirm start to start
  this subtask.` shows; the second click emits `startRequested()`. The arming is
  dropped whenever `dispatchState`, `target` or `form` changes, `confirmFirst`
  turns false, or the dialog hides. Rationale: a subtask is `ready` the moment
  its form validates (RunStore line 1005), so `ready` alone is not the explicit
  confirm parent line 126 asks for.
- **D5. The owner composes the subtask strings.** For a subtask target:
  `storyTitle` = the title of `cardMap[card.parentId]` (`""` if absent);
  `blockedText` = `Blocked by: nothing` when `blocked_by` is empty, else
  `Blocked by: ` followed by one entry per id, in `blocked_by` order, joined by
  `, `, each from `app.board.resolvedCard(id)`: `inBoard` true → `"<title>"
  (<app.board.statusText(status)>)`; `kind === "issue"` → `"<title>" (Issue ·
  <status>)` (`Board.issueBlockerLabel`); anything else (`inBoard` false, no
  `kind`) → `<id> (not on this board)`. Other levels pass
  `""` for both.
- **D6. "Toast" is the footer flash.** `RunToast` is the escalation-alert
  surface with its own shape and Open button; a started dispatch is not an
  alert. The parent's toast (line 144) is `app.runs.flash(...)` shown on the
  Runs screen's footer, which is where the user is taken anyway. Text verbatim
  from the parent: `Started — waiting for the run to appear` (em dash U+2014).
- **D7. Navigation waits for the snapshot.** `dispatchStarted(id)` fires before
  the re-snapshot lands, so `openRun` would usually no-op. With an id the
  Navigator goes to the Runs list and, if the run is already in `runs`, opens
  it; otherwise it remembers the id (`awaitedRunId`, with the project's
  `root_path`) and flashes `Started — opening the run when it appears`. Every
  change of `app.runs.runs` calls `navi.openAwaitedRun()`, which opens the run
  once it is there — but only while the panel is still on the Runs list of the
  same project; anywhere else it forgets the id and does nothing. With `null`
  it goes to the Runs list and flashes the D6 sentence.
- **D8. `d` follows the run keys' rules.** Bare `d` only (`Shift+D` types);
  needs a selected project, `amStatus !== "missing"`, no modal, the dropdown
  closed. On the board list it needs `searchQuery === ""` and a card under the
  cursor (`app.board.boardCards[app.nav.cursorIndex]`, the list the board's
  keyboard cursor walks); on the card detail the open card. Anywhere else, or when a condition
  fails, it returns false and the letter is left alone (on the board list it
  then types into the search field, exactly as a refused `p` does on the Runs
  list). It never starts anything: it only opens the dialog (parent lines
  133-134).
- **D9. Focus moves only on open and close.** Panel refocuses
  (`focusForView()`) when `dispatchState` changes to or from `idle`, never on
  `previewing → ready → refused` while open, so a re-preview never pulls the
  caret out of the field being typed in. A re-target (chip or offer) passes
  through `idle` synchronously, so focus lands on the new dialog's
  `focusItem`.
- **D10. Glyphs.** `▶` (U+25B6) is the only glyph added (Dispatch and Start run
  buttons); it is not private-use, so `test_icon_glyphs.py` has nothing to
  check.

### Behaviour

#### Panel — the mounted dialog

`DispatchDialog { id: dispatchDialog; objectName: "dispatchDialog"; anchors.fill:
parent }` among the other dialogs, bound:

| prop | value |
|---|---|
| `shown` | `appStores.runs.dispatchState !== "idle"` |
| `theme` | `panelTheme` |
| `dispatchState`, `target`, `form`, `preview`, `error`, `logPath`, `logTail`, `exitCode` | `dispatchState`, `dispatchTarget`, `dispatchForm`, `dispatchPreview`, `dispatchError`, `dispatchLog`, `dispatchLogTail`, `dispatchExitCode` |
| `targetTitle` | `cardMap[dispatchCardId].title`, `""` for the board or a card no longer on the board |
| `storyTitle`, `blockedText` | D5 |
| `confirmFirst` | `dispatchTarget` non-null and `dispatchTarget.level === "subtask"` |
| `suggestion` | `dispatchSuggest` when its `id` is a key of `cardMap`, else `null` |
| `targetChoices` | `root.dispatchChoices` (`[]` unless opened from Runs) |
| `targetChoice` | `dispatchCardId === "" ? "board" : dispatchCardId` |

Signals: `fieldEdited(n, v)` → `runs.setDispatchField(n, v)`; `startRequested`
→ `runs.dispatchStart()`; `cancelRequested` → `runs.closeDispatch()`;
`suggestionRequested` → `root.openDispatch(dispatchSuggest.id)`;
`targetChosen(id)` → `root.openRunsDispatch(id)`.

`root.dispatchChoices` is emptied whenever `dispatchState` becomes `idle` by
any route other than a re-target (close, project switch, panel close).

`focusItem` chain: `appStores.runs.dispatchState !== "idle" ?
dispatchDialog.focusItem` sits immediately before the `runCancelModal` link.

`Connections { target: appStores.runs }` gains:
- `onDispatchStateChanged`: refocus per D9.
- `onDispatchStarted(runId)`: `appStores.runs.closeDispatch()`, then
  `navi.openStartedRun(runId)`.
- `onRunsChanged`: `navi.openAwaitedRun()`.

#### Panel — toolbar `Start run`

`UI.ActionButton { objectName: "startRunButton"; iconText: "▶"; text: "Start
run" }` in the toolbar row; `visible` only while `viewMode === "runs"` and a
project is selected; `enabled: amStatus !== "missing"`; `tooltipText` `am is
not installed or not on PATH` while missing, else `Start an am run`. Click →
`root.openRunsDispatch("board")`.

#### Card detail — Dispatch button

Below the badge row: `UI.ActionButton { objectName: "cardDispatchButton";
iconText: "▶"; text: "Dispatch" }`, shown for every card (a story or finished
card opens the dialog, which says why it cannot start and, for a story, offers
its milestone); `enabled: app.runs.amStatus !== "missing"`. While missing a
caption `cardDispatchMissing` beside it reads `am is not installed or not on
PATH`; otherwise that caption is hidden. Click emits the new `signal
dispatchRequested(string cardId)` with the open card's id; Panel maps it to
`root.openDispatch(cardId)`.

#### Shortcuts — `d`

`handleDispatchKey(event)` (D8), wired in Panel's `globalKeys` after
`handleRunKey`: returns true (and calls `actions.openDispatch(id)`) for the
board cursor card or the open card; false otherwise.

`modalOpen()` also returns true while `app.runs.dispatchState !== "idle"`.

`closeRequested()`: a new link `app.runs.dispatchState !== "idle" ?
app.runs.closeDispatch()` immediately before the `cancelOpen` link. While
`starting` `closeDispatch()` refuses, so Escape does nothing at all (no Back,
no panel close).

#### Navigator

- `openStartedRun(runId)`: `showSection("runs")`; then `null`/`""` → flash D6;
  an id in `app.runs.runs` → `openRun(id, "runs")`; any other id →
  `awaitedRunId = id`, `awaitedProject = selectedProject.root_path`, flash
  `Started — opening the run when it appears`.
- `openAwaitedRun()`: nothing when `awaitedRunId === ""`. If `viewMode !==
  "runs"` or the selected project's `root_path` differs from `awaitedProject`,
  clears both and returns. If the run is now in `app.runs.runs`, clears both
  and calls `openRun(id, "runs")`. Otherwise keeps waiting.

Back from the opened run returns to the Runs list (`openRun` from `"runs"`).

#### DispatchDialog — additions

| prop / signal | type, default | meaning |
|---|---|---|
| `targetChoices` | var, `[]` | `[{id, label}]`; non-empty only from the Runs entry |
| `targetChoice` | string, `""` | the active choice's id |
| `suggestion` | var, `null` | `{id, title}` of a refused story's milestone |
| `confirmFirst` | bool, `false` | Start needs two clicks (D4) |
| `readonly armed` | bool | the first click happened (D4) |
| `targetChosen(string id)` | signal | a chip other than the active one was clicked |
| `suggestionRequested()` | signal | the offer button was clicked |

Layout additions (objectNames):

- `dispatchTargetChoices` — `UI.ChipRow` right under `dispatchTarget`,
  `chipPrefix: "dispatchTargetChoice"`, `model` = the choices, `active` =
  `targetChoice`, `busy` while `busy`; visible only when `targetChoices` is a
  non-empty list. A click on the active chip emits nothing.
- `dispatchSuggest` — `UI.ActionButton` under `dispatchRefusal`, text
  `Dispatch its milestone "<suggestion.title>"`, visible only while
  `dispatchState === "refused"` and `suggestion` has a non-empty string `id`;
  click emits `suggestionRequested()`. An empty title reads `Dispatch its
  milestone`.
- `dispatchConfirmNote` — caption `Click Confirm start to start this
  subtask.`, visible only while `armed`.
- `dispatchStart` text: `Starting…` while `busy`, else `Confirm start` while
  `armed`, else `Start run`. Enabled exactly as before (`canStart`). Click:
  when `confirmFirst && !armed` it arms; otherwise it emits `startRequested()`.

### Errors and edge cases

| case | behaviour |
|---|---|
| am missing | `cardDispatchButton` and `startRunButton` disabled with `am is not installed or not on PATH`; `d` left alone |
| no project | `startRunButton` hidden; `d` left alone; `openDispatch` refuses anyway |
| board list with search text | `d` types into the search |
| `d` with a modal or the dropdown open | left alone |
| `d` while the dialog is open | left alone (`modalOpen()`) |
| `d` / Dispatch on a story | dialog: `Target   Story "<title>"`, the refusal, `Dispatch its milestone "<m>"`; click re-opens on the milestone with its preview |
| `d` / Dispatch on a finished card | dialog shows `The card is done` (etc.), no offer, Start disabled |
| a story whose milestone is not on the board | refusal only, no offer button |
| subtask | story and blocked lines (D5), Start needs two clicks; editing a field disarms |
| Escape while open | closes; focus back to the view |
| Escape while `starting` | nothing happens |
| Cancel / backdrop while `starting` | nothing (4.1) |
| launch failure | dialog stays open in `failed`, no navigation |
| started, run already in `runs` | dialog closes, Run detail of that run |
| started, run not yet in `runs` | dialog closes, Runs list, flash `Started — opening the run when it appears`; the next snapshot that lists it opens Run detail |
| started, user leaves the Runs list before it appears | the run is not opened later |
| started with `null` run id | dialog closes, Runs list, flash `Started — waiting for the run to appear` |
| project switched while open | store resets to `idle`; the dialog hides; choices cleared |
| re-target via chip while `starting` | chips are busy; no click |

### Tests

All written first. `bash tests/run.sh` is the gate (it also fails on any
TypeError / ReferenceError / "Unable to assign" / "is not a function" in the
output). In flow and Navigator tests the helpers cannot run: drive the store's
reply handlers directly — `p.app.runs.dispatchDefaultsReplied('{"ok":true,
"data":{"default_branch":"main"}}')`, `dispatchPreviewReplied(<ok envelope>)`,
and after `dispatchStart()` `dispatchStartReplied(p.app.runs.dispatchStartRunners[0],
'{"ok":true,"run_id":"run-…","message":"…"}')`; seed `p.app.runs.runs` to stand
in for the snapshot that follows.

#### Component tier — `tests/ui/components/tst_dispatch_dialog.qml` (extend)

The new dialog features are presentation only: plain prop objects and
`SignalSpy`, no store, as 4.1's tests do.

1. `dispatchTargetChoices` hidden with no choices; with `[{id:"board",
   label:"Whole board"}, {id:"m1", label:"M one"}]` and `targetChoice:
   "board"`, both chips exist (`dispatchTargetChoiceboard`,
   `dispatchTargetChoicem1`), the board chip is `active`; clicking `m1` emits
   `targetChosen("m1")` once; clicking the active chip emits nothing; while
   `starting` a click emits nothing.
2. `dispatchSuggest`: refused + `suggestion {id:"m1", title:"M one"}` → visible,
   text `Dispatch its milestone "M one"`, click emits `suggestionRequested`
   once; hidden in `ready`, hidden with `suggestion: null`, hidden with an
   empty id.
3. Confirm-first: `confirmFirst: true`, `ready` → first click emits no
   `startRequested`, `armed` true, Start text `Confirm start`,
   `dispatchConfirmNote` visible; second click emits exactly once.
4. Disarming: after arming, each of (a) assigning a new `form`, (b)
   `dispatchState` → `previewing` → `ready`, (c) `shown: false` then `true`,
   (d) `confirmFirst: false` leaves `armed` false and Start reading `Start run`.
5. `confirmFirst: false` (default): one click emits (4.1 behaviour unchanged).

#### Unit tier — `tests/ui/tst_shortcuts.qml` (extend)

Shortcuts is tested on its own against the real `App` and `Navigator`, with
`actions.openDispatch` recording its argument.

6. Board list, project selected, empty search, cursor on `m1`: bare `d`
   returns true and records `"m1"`.
7. Returns false and records nothing for: `Shift+D`; `Ctrl+D`; non-empty
   search; no project; `amStatus "missing"`; dropdown open; a modal open
   (`runs.cancelOpen` set); `dispatchState` not `idle`; `viewMode` `runs`,
   `graph`, `documents`; an empty board.
8. Card detail on `s1`: `d` records `"s1"`.
9. `modalOpen()` true while `dispatchState` is `ready`; a Ctrl+1 is then
   ignored.
10. Escape chain: with `dispatchState` `refused` (open a story), `closeRequested()`
    sets it `idle` and leaves `viewMode` unchanged; with `dispatchState`
    `starting` (set directly) `closeRequested()` leaves it `starting`, does not
    go Back from `entry` and does not call `actions.close`.

#### Unit tier — `tests/ui/tst_navigator.qml` (extend)

The navigation rules are Navigator's alone; real `App`, stub actions.

11. `openStartedRun(null)`: `viewMode` `runs`, `flashText` `Started — waiting
    for the run to appear`.
12. `openStartedRun("run-a")` with `run-a` in `runs`: `viewMode` `run`,
    `selectedRunId` `run-a`; `goBack()` lands on `runs`.
13. `openStartedRun("run-b")` with `run-b` absent: `viewMode` `runs`, flash
    `Started — opening the run when it appears`, `awaitedRunId` `run-b`; then
    `runs` gains `run-b` and `openAwaitedRun()` opens it and clears
    `awaitedRunId`.
14. Awaited but the user went to `board` first: `openAwaitedRun()` with `run-b`
    present leaves `viewMode` `board` and clears `awaitedRunId`.
15. Awaited, `runs` changes without `run-b`: still `runs`, still awaiting.

#### Screen tier — `tests/ui/screens/tst_card_detail_screen.qml` (extend)

The button is the screen's; real `App` and `Navigator`.

16. `cardDispatchButton` visible on a milestone, a story and a done subtask,
    text `Dispatch`, `iconText` `▶`; a click emits `dispatchRequested` with the
    open card's id.
17. With `amStatus "missing"`: disabled, a click emits nothing,
    `cardDispatchMissing` visible with `am is not installed or not on PATH`;
    with `amStatus` `ok` the caption is hidden.

#### Panel tier — `tests/ui/tst_panel_toolbar.qml` (extend)

18. `startRunButton` visible only in `runs` with a project (hidden on board,
    graph, memories, issues, a run detail, and with no project); text `Start
    run`, `iconText` `▶`; disabled with `amStatus "missing"`.

#### Flow tier — new `tests/ui/tst_dispatch_flow.qml`

The whole Panel (`make()` as `tst_runs_flow.qml` lines 25-50 builds it, plus a
board with milestone `m1` "M one" → story `s1` "Story one" → subtasks `t1`
"Do it" (`blocked_by: ["t0", "i1", "ghost"]`, `t0` a done card "Prep", `i1` an
open issue "Broken build") and a done milestone `m9`), because each entry point
crosses Panel, Shortcuts or a screen, Navigator, the store and the dialog.

19. Card detail entry: open `m1`, click `cardDispatchButton` → `dispatchDialog`
    visible, `dispatchTarget` text `Target   Milestone "M one"`; after the
    defaults and preview replies `dispatchStart` enabled; `p.focusItem` is
    `dispatchBase`.
20. Board `d`: cursor on `m1`, key `d` through the search field → dialog open on
    `m1`, the search field still empty.
21. Runs entry: Ctrl+6, click `startRunButton` → dialog open, target `Whole
    board`, chips `Whole board` and `M one` (no `m9`), board chip active;
    click `dispatchTargetChoicem1` → target `Milestone "M one"`, chips still
    shown, `m1` active; Cancel → dialog hidden, `dispatchChoices` empty; card
    detail Dispatch afterwards shows no chips.
22. Story: card detail on `s1`, Dispatch → `Story "Story one"`, refusal `A
    story is dispatched through its milestone`, `dispatchSuggest` `Dispatch
    its milestone "M one"`; click → target `Milestone "M one"`, state
    `previewing`, `dispatchSuggest` hidden.
23. Subtask: card detail on `t1`, Dispatch, defaults reply → `ready`;
    `dispatchStory` `Story   "Story one"`; `dispatchBlocked` `Blocked by:
    "Prep" (Done), "Broken build" (Issue · open), ghost (not on this board)`;
    first Start click leaves `dispatchState` `ready` and no start runner;
    second click → `starting`, one runner in `dispatchStartRunners`.
24. Started with the run listed: reply `run_id` `run-new`, `runs` already
    containing it → dialog hidden, `viewMode` `run`, `selectedRunId`
    `run-new`; Back → `runs`.
25. Started before the snapshot: reply `run_id` `run-late`, not in `runs` →
    dialog hidden, `viewMode` `runs`, `runsFooter` text `Started — opening the
    run when it appears`; then assign `runs` with `run-late` → `viewMode`
    `run`, `selectedRunId` `run-late`.
26. Started without an id: reply `{"ok":true,"message":"…"}` → dialog hidden,
    `viewMode` `runs`, `runsFooter` `Started — waiting for the run to appear`.
27. Failed launch: reply `{"ok":false,"error":{"type":"Spawn","message":"no
    am"},"log":"/tmp/l","exit_code":2}` → dialog still shown, state `failed`,
    `viewMode` unchanged.
28. Escape: dialog open (refused story) → key catcher Escape closes it,
    `viewMode` still `entry`, focus back on `keyCatcher`; in `starting` Escape
    leaves the dialog shown and `viewMode` `entry`.
29. Focus stays put while open: focus `dispatchPrefix`, edit it, let the store
    go `previewing` → `ready` (debounce + preview reply) → `dispatchPrefix`
    still has `activeFocus`.
30. Project switch while open: dialog hidden, `dispatchChoices` empty.
31. am missing: `cardDispatchButton` and `startRunButton` disabled; `d` on the
    board types `d` into the search instead of opening anything.

#### Architecture tier — `tests/architecture` (unchanged, must pass)

`CardDetailScreen.qml` still imports no `core/stores`; no new QML type; the
dialog's additions reuse `ChipRow`, `ActionButton`, `ThemedText`; no
private-use glyph; no second copy of a guarded visual pattern.

### Review focus for the planner

- Focus theft: refocusing on every `dispatchStateChanged` would yank the caret
  out of a field on each re-preview (test 29).
- The run is usually not in `runs` when `dispatchStarted` fires; `openRun`
  silently no-ops (tests 13, 25).
- The `d` key must not swallow typing: non-empty search, `Shift+D` and every
  refused case return false (tests 7, 31).
- Escape while `starting` must not fall through to Back or close (tests 10, 28).
- Re-targeting passes through `idle`: the choices must survive a chip click but
  not a close (test 21).

---

## Global Constraints

- No change to `core/stores/RunStore.qml`, `core/stores/App.qml`, `core/domain/runs.js`, `core/domain/board.js` or any backend helper. A test that needs store behaviour that does not exist is a finding to report, not a store change.
- Screens import no `core/stores` (`tests/architecture/test_layers.py`): `CardDetailScreen` reaches Panel through a signal, never a store call for dispatch.
- No new QML type and no new shared component: the dialog's additions reuse `UI.ChipRow`, `UI.ActionButton`, `UI.ThemedText`.
- `▶` (U+25B6) is the only glyph added; no private-use glyph.
- `ui/Shortcuts.qml`: "the ORDER of the guards here is load bearing" — only insert links where this plan says, never reorder existing ones.
- Strings, verbatim: `Dispatch`, `Start run`, `Start an am run`, `am is not installed or not on PATH`, `Whole board`, `Dispatch its milestone "<title>"` (empty title → `Dispatch its milestone`), `Confirm start`, `Click Confirm start to start this subtask.`, `Started — waiting for the run to appear`, `Started — opening the run when it appears` (both with an em dash U+2014), `Blocked by: nothing`, `Blocked by: ` + entries joined by `, `, entries `"<title>" (<statusText>)`, `"<title>" (Issue · <status>)`, `<id> (not on this board)`.
- The subtask's extra confirm is always on; milestone and board dispatches have no extra confirm.
- Gate: `bash tests/run.sh` (it fails on any `TypeError` / `ReferenceError` / `Unable to assign` / `is not a function` in the output).
- No test may let a real helper run: Panel-level tests set `p.app.backendDir = "/plugin/core/backend/"` before selecting a project and answer each launch they care about through `reply(proc, text)` (`proc.outText = text; proc.exited(0)`), the way `tests/core/stores/tst_run_store.qml` does.

## Review Focus

1. A board list cursor left past the end of the list (the board refetched smaller) — `d` must return false and open nothing, not throw. Pinned in Task 3 (`cursor-past-the-end` row of `test_d_is_left_alone`).
2. The dispatched card leaving the board while the dialog is open (a refetch dropped it) — the dialog keeps working with an empty title, no story or blocked line, no TypeError, and Cancel still closes it. Pinned in Task 5 (`test_a_card_dropped_from_the_board_while_open_leaves_a_working_dialog`).
3. A second start while an earlier one is still awaited — the newer start replaces the awaited run, so the older run never opens later. Pinned in Task 2 (`test_a_second_start_replaces_the_awaited_run`).
4. A subtask with no `blocked_by` key at all (or an empty list) — reads `Blocked by: nothing`. Pinned in Task 5 (`test_a_subtask_without_blockers_says_so`).
5. Typing `d` (or any letter) inside a dialog field — it types into the field; it never re-opens the dispatch through the global keys. Pinned in Task 5 (`test_d_typed_in_a_dialog_field_types`).

---

## File map

| File | Change | Task |
|---|---|---|
| `ui/components/DispatchDialog.qml` | target chips, milestone offer, confirm-first | 1 |
| `tests/ui/components/tst_dispatch_dialog.qml` | extend (tests 1-5) | 1 |
| `ui/Navigator.qml` | `awaitedRunId`, `awaitedProject`, `openStartedRun`, `openAwaitedRun` | 2 |
| `tests/ui/tst_navigator.qml` | extend (tests 11-15, RF3) | 2 |
| `ui/Shortcuts.qml` | `handleDispatchKey`, dispatch in `modalOpen()` and Escape | 3 |
| `tests/ui/tst_shortcuts.qml` | extend (tests 6-10, RF1) | 3 |
| `ui/screens/CardDetailScreen.qml` | `dispatchRequested` signal, Dispatch button and caption | 4 |
| `tests/ui/screens/tst_card_detail_screen.qml` | extend (tests 16-17) | 4 |
| `ui/Panel.qml` | mount the dialog, owner functions, focus, `d`, card entry | 5 |
| `tests/ui/tst_dispatch_flow.qml` | new (tests 19, 20, 22, 23, 28, 29, 31, RF2, RF4, RF5) | 5 |
| `ui/Panel.qml` | `Start run` toolbar button, target chips | 6 |
| `tests/ui/tst_panel_toolbar.qml` | extend (test 18) | 6 |
| `tests/ui/tst_dispatch_flow.qml` | extend (tests 21, 30, 31) | 6 |
| `ui/Panel.qml` | started → close and navigate | 7 |
| `tests/ui/tst_dispatch_flow.qml` | extend (tests 24-27) | 7 |
| `docs/architecture.md` | DispatchDialog, Navigator, Shortcuts, Panel dispatch | 8 |

Run a single QML file with `bash tests/run.sh <substring of its path>` (pytest runs first; it is quick). A failing QML test prints `FAIL!  : <TestCase>::<test>()` lines and a `Totals:` line with a non-zero fail count.

---

### Task 1: DispatchDialog — target chips, the milestone offer, the two-click Start

**Files:**
- Modify: `ui/components/DispatchDialog.qml`
- Test: `tests/ui/components/tst_dispatch_dialog.qml`

**Interfaces:**
- Consumes: nothing new (4.1's dialog).
- Produces (Panel binds these in Tasks 5 and 6):
  - `property var targetChoices: []` — `[{id, label}]`
  - `property string targetChoice: ""`
  - `property var suggestion: null` — `{id, title}`
  - `property bool confirmFirst: false`
  - `readonly property bool armed`
  - `signal targetChosen(string id)`, `signal suggestionRequested()`
  - objectNames `dispatchTargetChoices` (chips `dispatchTargetChoice<id>`), `dispatchSuggest`, `dispatchConfirmNote`; `dispatchStart` text `Starting…` / `Confirm start` / `Start run`.

- [ ] **Step 1: Write the failing tests**

In `tests/ui/components/tst_dispatch_dialog.qml`, add two spies right after the existing `SignalSpy { id: cancels; signalName: "cancelRequested" }` line:

```qml
  SignalSpy { id: chosen; signalName: "targetChosen" }
  SignalSpy { id: offers; signalName: "suggestionRequested" }
```

Replace the existing `make(over)` function with:

```qml
  function make(over) {
    var d = createTemporaryObject(dialogC, tc, milestone(over))
    edits.target = d; starts.target = d; cancels.target = d; chosen.target = d; offers.target = d
    edits.clear(); starts.clear(); cancels.clear(); chosen.clear(); offers.clear()
    d.shown = true
    wait(30)
    return d
  }
```

Then append these tests before the file's final closing `}`:

```qml
  // ---- the Runs entry's target row (S3 4.2) ------------------------------

  property var boardChoices: [{ id: "board", label: "Whole board" }, { id: "m1", label: "M one" }]

  // 1
  function test_the_target_row_is_hidden_without_choices() {
    var d = make()
    var row = H.find(d, "dispatchTargetChoices")
    verify(row, "the target row")
    compare(row.visible, false)
  }

  // 1
  function test_the_target_row_shows_the_choices_and_emits_another_one() {
    var d = make({ target: { level: "board" }, targetTitle: "", targetChoices: tc.boardChoices, targetChoice: "board" })
    compare(H.find(d, "dispatchTargetChoices").visible, true)
    var board = H.find(d, "dispatchTargetChoiceboard")
    var m1 = H.find(d, "dispatchTargetChoicem1")
    verify(board && m1, "both chips")
    compare(board.text, "Whole board")
    compare(m1.text, "M one")
    compare(board.active, true)
    compare(m1.active, false)
    click(board)
    compare(chosen.count, 0, "the active chip emits nothing")
    click(m1)
    compare(chosen.count, 1)
    compare(chosen.signalArguments[0][0], "m1")
    compare(starts.count, 0)
  }

  // 1
  function test_the_target_row_is_busy_while_starting() {
    var d = make({ target: { level: "board" }, targetChoices: tc.boardChoices, targetChoice: "board" })
    d.dispatchState = "starting"
    var m1 = H.find(d, "dispatchTargetChoicem1")
    compare(m1.busy, true)
    click(m1)
    compare(chosen.count, 0)
  }

  // ---- the story's milestone offer (S3 4.2) -------------------------------

  function storyRefusal(over) {
    return Object.assign({ dispatchState: "refused", target: { level: "story", offered: false }, targetTitle: "Story one",
                           form: null, preview: null, error: "A story is dispatched through its milestone",
                           suggestion: { id: "m1", title: "M one" } }, over || {})
  }

  // 2
  function test_a_refused_story_offers_its_milestone() {
    var d = make(storyRefusal())
    var offer = H.find(d, "dispatchSuggest")
    verify(offer, "the offer button")
    compare(offer.visible, true)
    compare(offer.text, "Dispatch its milestone \"M one\"")
    click(offer)
    compare(offers.count, 1)
    compare(starts.count, 0)
    compare(cancels.count, 0)
  }

  // 2
  function test_the_offer_shows_only_for_a_refusal_with_a_milestone_id_data() {
    return [
      { tag: "ready", over: { dispatchState: "ready" } },
      { tag: "no-suggestion", over: { suggestion: null } },
      { tag: "empty-id", over: { suggestion: { id: "", title: "M one" } } },
      { tag: "non-string-id", over: { suggestion: { id: 7, title: "M one" } } }
    ]
  }

  function test_the_offer_shows_only_for_a_refusal_with_a_milestone_id(data) {
    var d = make(storyRefusal(data.over))
    var offer = H.find(d, "dispatchSuggest")
    compare(offer.visible, false)
    offer.clicked()
    compare(offers.count, 0, "a hidden offer emits nothing")
  }

  // 2
  function test_an_untitled_milestone_offer_reads_without_a_title() {
    var d = make(storyRefusal({ suggestion: { id: "m1", title: "" } }))
    compare(H.find(d, "dispatchSuggest").text, "Dispatch its milestone")
  }

  // ---- the subtask's two-click Start (S3 4.2) -----------------------------

  function subtask(over) {
    return Object.assign({ target: { level: "subtask", offered: true }, targetTitle: "Do it", preview: null,
                           confirmFirst: true }, over || {})
  }

  // 3
  function test_confirm_first_needs_a_second_click() {
    var d = make(subtask())
    var start = H.find(d, "dispatchStart")
    var note = H.find(d, "dispatchConfirmNote")
    verify(note, "the confirm note")
    compare(d.armed, false)
    compare(note.visible, false)
    click(start)
    compare(starts.count, 0, "the first click only arms")
    compare(d.armed, true)
    compare(start.text, "Confirm start")
    compare(note.visible, true)
    compare(note.text, "Click Confirm start to start this subtask.")
    click(start)
    compare(starts.count, 1)
  }

  // 4
  function test_the_arming_is_dropped_data() {
    return [{ tag: "new-form" }, { tag: "re-preview" }, { tag: "hidden" }, { tag: "confirm-off" }, { tag: "new-target" }]
  }

  function test_the_arming_is_dropped(data) {
    var d = make(subtask())
    var start = H.find(d, "dispatchStart")
    click(start)
    compare(d.armed, true)
    if (data.tag === "new-form") d.form = milestoneForm({ prefix: "m4" })
    else if (data.tag === "re-preview") { d.dispatchState = "previewing"; d.dispatchState = "ready" }
    else if (data.tag === "hidden") { d.shown = false; d.shown = true }
    else if (data.tag === "confirm-off") d.confirmFirst = false
    else d.target = { level: "subtask", offered: true }
    compare(d.armed, false)
    compare(start.text, "Start run")
    compare(H.find(d, "dispatchConfirmNote").visible, false)
    compare(starts.count, 0)
    compare(edits.count, 0, "a new form echoes nothing")
  }

  // 5
  function test_without_confirm_first_one_click_starts() {
    var d = make(subtask({ confirmFirst: false }))
    click(H.find(d, "dispatchStart"))
    compare(starts.count, 1)
    compare(d.armed, false)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: FAIL — the new tests fail (`the target row` / `the offer button` / `the confirm note` verify messages, `Cannot assign to non-existent property "targetChoices"` style errors from `createTemporaryObject`, and `d.armed` undefined); the 4.1 tests still pass.

- [ ] **Step 3: Implement**

In `ui/components/DispatchDialog.qml`:

(a) Replace the header comment (lines 7-11) with:

```qml
// The dispatch modal over a dimmed backdrop: what will run, the form the store
// checks, what am would do, and what it costs. Renders and emits only -- the
// owner passes RunStore's dispatch values in and maps fieldEdited,
// startRequested and cancelRequested onto setDispatchField, dispatchStart and
// closeDispatch. Only a click on Start starts a run: Return never does. The
// owner may add a row of targets (targetChosen), a refused story's milestone
// (suggestionRequested) and a Start that takes two clicks (confirmFirst).
```

(b) After `property string blockedText: ""` add:

```qml
  // The Runs entry's targets, [{id, label}]; [] hides the row. targetChoice is
  // the active one's id.
  property var targetChoices: []
  property string targetChoice: ""
  // A refused story's milestone {id, title}, offered as a target of its own.
  property var suggestion: null
  // Start takes two clicks: the first only arms it (a subtask has no preview,
  // so ready alone is not an explicit confirm).
  property bool confirmFirst: false
  readonly property bool armed: arming.armed
```

(c) After the `readonly property int verifyRows: ...` line add:

```qml
  readonly property bool hasChoices: !!dialog.targetChoices && typeof dialog.targetChoices.length === "number"
    && dialog.targetChoices.length > 0
  readonly property bool canOffer: dialog.dispatchState === "refused" && !!dialog.suggestion
    && typeof dialog.suggestion.id === "string" && dialog.suggestion.id !== ""
  readonly property string offerText: {
    var title = dialog.suggestion && typeof dialog.suggestion.title === "string" ? dialog.suggestion.title : ""
    return title !== "" ? "Dispatch its milestone \"" + title + "\"" : "Dispatch its milestone"
  }
```

(d) Replace

```qml
  signal fieldEdited(string name, var value)
  signal startRequested()
  signal cancelRequested()

  visible: shown
  onShownChanged: dialog.syncFields()
  onFormChanged: dialog.syncFields()
  Component.onCompleted: dialog.syncFields()
```

with

```qml
  signal fieldEdited(string name, var value)
  signal startRequested()
  signal cancelRequested()
  signal targetChosen(string id)
  signal suggestionRequested()

  visible: shown
  // Any change to what Start would start drops the first click.
  onShownChanged: { arming.armed = false; dialog.syncFields() }
  onFormChanged: { arming.armed = false; dialog.syncFields() }
  onDispatchStateChanged: arming.armed = false
  onTargetChanged: arming.armed = false
  onConfirmFirstChanged: arming.armed = false
  Component.onCompleted: dialog.syncFields()

  QtObject {
    id: arming
    property bool armed: false
  }

  // A click on Start: from ready only; with confirmFirst the first click arms
  // and only the second starts.
  function start() {
    if (!dialog.canStart) return
    if (dialog.confirmFirst && !arming.armed) {
      arming.armed = true
      return
    }
    dialog.startRequested()
  }
```

(e) Right after the `dispatchTarget` `UI.ThemedText { ... }` block (the one with `text: "Target   " + dialog.targetText`) add:

```qml
    // The Runs entry's targets; a click on the active one says nothing.
    UI.ChipRow {
      objectName: "dispatchTargetChoices"
      width: parent.width
      visible: dialog.hasChoices
      chipPrefix: "dispatchTargetChoice"
      theme: dialog.theme
      model: dialog.hasChoices ? dialog.targetChoices : []
      active: dialog.targetChoice
      busy: dialog.busy
      onChosen: function(id) { if (id !== dialog.targetChoice) dialog.targetChosen(id) }
    }
```

(f) Right after the `dispatchRefusal` `UI.ThemedText { ... }` block add:

```qml
    // A story is dispatched through its milestone: offer it.
    UI.ActionButton {
      objectName: "dispatchSuggest"
      visible: dialog.canOffer
      text: dialog.offerText
      theme: dialog.theme
      onClicked: if (dialog.canOffer) dialog.suggestionRequested()
    }
```

(g) Right after the `dispatchWarning` `UI.ThemedText { ... }` block (before the button `Row`) add:

```qml
    UI.ThemedText {
      objectName: "dispatchConfirmNote"
      variant: "caption"
      theme: dialog.theme
      visible: arming.armed
      width: parent.width
      text: "Click Confirm start to start this subtask."
      wrapMode: Text.WordWrap
    }
```

(h) Replace the Start button's two lines

```qml
        text: dialog.busy ? "Starting…" : "Start run"
        enabled: dialog.canStart
        theme: dialog.theme
        onClicked: if (dialog.canStart) dialog.startRequested()
```

with

```qml
        text: dialog.busy ? "Starting…" : arming.armed ? "Confirm start" : "Start run"
        enabled: dialog.canStart
        theme: dialog.theme
        onClicked: dialog.start()
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: PASS — `Totals: N passed, 0 failed`, and no `TypeError` / `ReferenceError` lines.

- [ ] **Step 5: Commit**

```bash
git add ui/components/DispatchDialog.qml tests/ui/components/tst_dispatch_dialog.qml
git commit -m "DispatchDialog.qml: target chips, the milestone offer and the two-click Start (S3 4.2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Navigator — open the started run, or wait for it

**Files:**
- Modify: `ui/Navigator.qml` (after `restoreCardFromRun()`, before `goBack()`)
- Test: `tests/ui/tst_navigator.qml`

**Interfaces:**
- Consumes: `navi.showSection(name)`, `navi.openRun(id, from)`, `app.runs.runById(id)`, `app.runs.flash(text)`, `app.projects.selectedProject.root_path`.
- Produces (Panel calls these in Task 7):
  - `property string awaitedRunId` (`""` when none), `property string awaitedProject`
  - `function openStartedRun(runId)` — `runId` a string or `null`
  - `function openAwaitedRun()`

- [ ] **Step 1: Write the failing tests**

Append before the final `}` of `tests/ui/tst_navigator.qml` (it already has `make()`, `runOf(id, status, live, milestone)` and `pA`/`pB`):

```qml
  // ---- After a dispatch (S3 4.2)

  // The board of project A, with run-a in the snapshot.
  function startedRuns() {
    var n = make(); if (!n) return null
    n.app.runs.snapshotRunner.cancel()
    n.app.runs.runs = [runOf("run-a", "started", true, "m1")]
    n.showSection("board")
    return n
  }

  // 11
  function test_a_start_without_a_run_id_goes_to_the_runs_list_and_says_so() {
    var n = startedRuns(); if (!n) return
    n.openStartedRun(null)
    compare(n.app.nav.viewMode, "runs")
    compare(n.app.runs.flashText, "Started — waiting for the run to appear")
    compare(n.awaitedRunId, "")
  }

  // 12
  function test_a_listed_run_opens_at_once_and_back_lands_on_the_runs_list() {
    var n = startedRuns(); if (!n) return
    n.openStartedRun("run-a")
    compare(n.app.nav.viewMode, "run")
    compare(n.app.runs.selectedRunId, "run-a")
    compare(n.awaitedRunId, "")
    n.goBack()
    compare(n.app.nav.viewMode, "runs")
  }

  // 13
  function test_an_unlisted_run_is_awaited_and_opens_when_a_snapshot_lists_it() {
    var n = startedRuns(); if (!n) return
    n.openStartedRun("run-b")
    compare(n.app.nav.viewMode, "runs")
    compare(n.app.runs.flashText, "Started — opening the run when it appears")
    compare(n.awaitedRunId, "run-b")
    compare(n.awaitedProject, "/home/u/a")
    n.app.runs.runs = n.app.runs.runs.concat([runOf("run-b", "started", true, "m1")])
    n.openAwaitedRun()
    compare(n.app.nav.viewMode, "run")
    compare(n.app.runs.selectedRunId, "run-b")
    compare(n.awaitedRunId, "")
    n.goBack()
    compare(n.app.nav.viewMode, "runs")
  }

  // 14
  function test_leaving_the_runs_list_forgets_the_awaited_run() {
    var n = startedRuns(); if (!n) return
    n.openStartedRun("run-b")
    n.showSection("board")
    n.app.runs.runs = n.app.runs.runs.concat([runOf("run-b", "started", true, "m1")])
    n.openAwaitedRun()
    compare(n.app.nav.viewMode, "board")
    compare(n.app.runs.selectedRunId, "")
    compare(n.awaitedRunId, "")
    n.showSection("runs")
    n.openAwaitedRun()
    compare(n.app.nav.viewMode, "runs", "forgotten for good")
  }

  // 15
  function test_a_snapshot_without_the_run_keeps_waiting() {
    var n = startedRuns(); if (!n) return
    n.openStartedRun("run-b")
    n.app.runs.runs = [runOf("run-c", "started", true, "m1")]
    n.openAwaitedRun()
    compare(n.app.nav.viewMode, "runs")
    compare(n.awaitedRunId, "run-b")
  }

  function test_another_project_forgets_the_awaited_run() {
    var n = startedRuns(); if (!n) return
    n.openStartedRun("run-b")
    n.chooseProject(tc.pB)
    n.showSection("runs")
    n.app.runs.snapshotRunner.cancel()
    n.app.runs.runs = [runOf("run-b", "started", true, "m1")]
    n.openAwaitedRun()
    compare(n.app.nav.viewMode, "runs")
    compare(n.app.runs.selectedRunId, "")
    compare(n.awaitedRunId, "")
  }

  // Review Focus 3
  function test_a_second_start_replaces_the_awaited_run() {
    var n = startedRuns(); if (!n) return
    n.openStartedRun("run-b")
    n.openStartedRun(null)
    compare(n.awaitedRunId, "")
    n.app.runs.runs = n.app.runs.runs.concat([runOf("run-b", "started", true, "m1")])
    n.openAwaitedRun()
    compare(n.app.nav.viewMode, "runs")
    compare(n.app.runs.selectedRunId, "")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_navigator`
Expected: FAIL — `TypeError: Property 'openStartedRun' of object Navigator_QMLTYPE… is not a function` in each new test.

- [ ] **Step 3: Implement**

In `ui/Navigator.qml`, after the closing `}` of `restoreCardFromRun()` and before `function goBack() {`, add:

```qml
  // ---- After a dispatch (S3 4.2). The store says a run started before its
  // re-snapshot lands, so the run is usually not listed yet: it is awaited,
  // and the next snapshot that lists it opens it -- but only while the panel
  // is still on that project's Runs list. A newer start replaces it.
  property string awaitedRunId: ""
  property string awaitedProject: ""

  function openStartedRun(runId) {
    navi.showSection("runs")
    navi.awaitedRunId = ""
    navi.awaitedProject = ""
    if (typeof runId !== "string" || runId === "") {
      navi.app.runs.flash("Started — waiting for the run to appear")
      return
    }
    if (navi.app.runs.runById(runId) !== null) {
      navi.openRun(runId, "runs")
      return
    }
    navi.awaitedRunId = runId
    navi.awaitedProject = navi.app.projects.selectedProject ? navi.app.projects.selectedProject.root_path : ""
    navi.app.runs.flash("Started — opening the run when it appears")
  }

  // Every change of the runs: open the awaited run once it is listed; away
  // from this project's Runs list, forget it.
  function openAwaitedRun() {
    if (navi.awaitedRunId === "") return
    var id = navi.awaitedRunId
    var project = navi.app.projects.selectedProject
    var here = navi.app.nav.viewMode === "runs" && !!project && project.root_path === navi.awaitedProject
    if (here && navi.app.runs.runById(id) === null) return
    navi.awaitedRunId = ""
    navi.awaitedProject = ""
    if (here) navi.openRun(id, "runs")
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_navigator`
Expected: PASS — `Totals: N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add ui/Navigator.qml tests/ui/tst_navigator.qml
git commit -m "Navigator.qml: open a started run, or wait for the snapshot that lists it (S3 4.2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Shortcuts — `d`, an open dispatch is a modal, Escape closes it

**Files:**
- Modify: `ui/Shortcuts.qml`
- Test: `tests/ui/tst_shortcuts.qml`

**Interfaces:**
- Consumes: `actions.openDispatch(target)` (a new member of the `actions` object Panel hands in — Task 5 adds it there), `app.runs.dispatchState`, `app.runs.closeDispatch()`, `app.runs.amStatus`, `app.board.boardCards`, `app.board.cardMap`, `app.board.selectedCardId`.
- Produces: `function handleDispatchKey(event)` → bool (Panel's `globalKeys` calls it in Task 5); `modalOpen()` true while `dispatchState !== "idle"`; `closeRequested()` closes the dispatch first among the run modals.

- [ ] **Step 1: Write the failing tests**

In `tests/ui/tst_shortcuts.qml`, in `make()`, replace the Shortcuts `actions` object

```qml
    var s = scC.createObject(tc, { app: app, navigator: n, actions: {
      close: function() { tc.calls.push("close") },
      scrollBy: navActions.scrollBy,
      switchPanel: function(direction) { tc.calls.push("switch:" + direction) },
      searchAtEnd: function() { return tc.atEnd }
    } })
```

with

```qml
    var s = scC.createObject(tc, { app: app, navigator: n, actions: {
      close: function() { tc.calls.push("close") },
      scrollBy: navActions.scrollBy,
      switchPanel: function(direction) { tc.calls.push("switch:" + direction) },
      searchAtEnd: function() { return tc.atEnd },
      openDispatch: function(target) { tc.calls.push("dispatch:" + target) }
    } })
```

Then append before the final `}`:

```qml
  // ---- d: the dispatch dialog (S3 4.2)

  // Project A's board list: milestone m1 (story s1 under it) under the cursor,
  // the search empty, am installed.
  function onBoard() {
    var s = make(); if (!s) return null
    s.app.runs.snapshotRunner.cancel()
    s.app.board.applyTreeData([card("m1", "Milestone", "todo", [card("s1", "Story", "todo")])])
    wait(20)
    s.navigator.showSection("board")
    s.app.nav.cursorIndex = 0
    return s
  }
  function dispatched() { return tc.calls.filter(function(c) { return c.indexOf("dispatch:") === 0 }) }

  // 6
  function test_d_on_the_board_list_asks_for_the_cursor_cards_dispatch() {
    var s = onBoard(); if (!s) return
    compare(s.app.board.boardCards[0].id, "m1")
    compare(s.handleDispatchKey(plain(Qt.Key_D)), true)
    compare(dispatched().join(","), "dispatch:m1")
    compare(s.app.runs.dispatchState, "idle", "the key only asks the panel")
  }

  // 7 (and Review Focus 1)
  function test_d_is_left_alone_data() {
    return [
      { tag: "shift" }, { tag: "ctrl" }, { tag: "search-text" }, { tag: "no-project" }, { tag: "am-missing" },
      { tag: "dropdown" }, { tag: "modal" }, { tag: "dispatch-open" }, { tag: "runs" }, { tag: "graph" },
      { tag: "documents" }, { tag: "empty-board" }, { tag: "cursor-past-the-end" }, { tag: "other-letter" }
    ]
  }

  function test_d_is_left_alone(data) {
    var s = onBoard(); if (!s) return
    var e = plain(Qt.Key_D)
    switch (data.tag) {
    case "shift": e = shift(Qt.Key_D); break
    case "ctrl": e = ctrl(Qt.Key_D); break
    case "search-text": s.app.nav.searchQuery = "mile"; break
    case "no-project": s.app.projects.selectedProject = null; s.app.nav.viewMode = "board"; break
    case "am-missing": s.app.runs.amStatus = "missing"; break
    case "dropdown": s.navigator.toggleDropdown(); break
    case "modal": s.app.runs.cancelRunId = "run-0000000000a1"; break
    case "dispatch-open": s.app.runs.dispatchState = "ready"; break
    case "runs": s.navigator.showSection("runs"); break
    case "graph": s.navigator.showSection("graph"); break
    case "documents": s.navigator.showSection("documents"); break
    case "empty-board": s.app.board.applyTreeData([]); break
    case "cursor-past-the-end": s.app.nav.cursorIndex = 5; break
    case "other-letter": e = plain(Qt.Key_E); break
    }
    compare(s.handleDispatchKey(e), false)
    compare(dispatched().length, 0)
  }

  // 8
  function test_d_on_a_card_asks_for_that_cards_dispatch() {
    var s = onBoard(); if (!s) return
    s.navigator.openCard("s1")
    compare(s.app.nav.viewMode, "entry")
    compare(s.handleDispatchKey(plain(Qt.Key_D)), true)
    compare(dispatched().join(","), "dispatch:s1")
  }

  // 9
  function test_an_open_dispatch_is_a_modal() {
    var s = onBoard(); if (!s) return
    compare(s.modalOpen(), false)
    s.app.runs.dispatchState = "ready"
    compare(s.modalOpen(), true)
    compare(s.handleGlobalKey(ctrl(Qt.Key_1)), false)
    compare(s.handleGlobalKey(ctrl(Qt.Key_6)), false)
    compare(s.app.nav.viewMode, "board")
  }

  // 10
  function test_escape_closes_an_open_dispatch_before_anything_else() {
    var s = onBoard(); if (!s) return
    s.navigator.openCard("s1")
    compare(s.app.runs.openDispatch(s.app.board.cardMap["s1"], s.app.board.cardMap), false, "a story is refused at once")
    compare(s.app.runs.dispatchState, "refused")
    s.closeRequested()
    compare(s.app.runs.dispatchState, "idle")
    compare(s.app.nav.viewMode, "entry", "that Escape closed the dialog only")
    compare(tc.calls.indexOf("close"), -1)
    s.closeRequested()
    compare(s.app.nav.viewMode, "board", "the next one goes back as before")
  }

  // 10
  function test_escape_while_a_start_is_in_flight_does_nothing() {
    var s = onBoard(); if (!s) return
    s.navigator.openCard("s1")
    s.app.runs.dispatchState = "starting"
    s.closeRequested()
    compare(s.app.runs.dispatchState, "starting")
    compare(s.app.nav.viewMode, "entry", "no Back")
    compare(tc.calls.indexOf("close"), -1, "no panel close")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_shortcuts`
Expected: FAIL — `TypeError: Property 'handleDispatchKey' … is not a function` in the `d` tests; `test_an_open_dispatch_is_a_modal` fails `compare(s.modalOpen(), true)`; the Escape tests fail (`viewMode` goes Back to `board` / `dispatchState` stays `refused`).

- [ ] **Step 3: Implement**

In `ui/Shortcuts.qml`:

(a) Replace the header comment lines 4-11 with:

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

(b) Replace the comment and body of `closeRequested()`:

```qml
  // Escape (and the key catcher's close gesture): innermost thing first. The
  // run toasts come right after the modals: they are not a modal, but an
  // Escape with toasts showing never goes Back or closes the panel.
  function closeRequested() {
    keys.app.deleter.deleteTarget ? keys.app.deleter.cancelDelete() : keys.app.board.archiveOpen ? keys.app.board.cancelArchive() : keys.app.memories.memoryDeleteOpen ? keys.app.memories.cancelMemoryDelete() : keys.app.memories.newMemoryOpen ? keys.app.memories.cancelNewMemory() : keys.app.milestones.dialogOpen ? keys.app.milestones.cancelDialog() : keys.app.runs.cancelOpen ? keys.app.runs.closeCancel() : keys.app.runs.toasts.length > 0 ? keys.app.runs.dismissAllToasts() : (keys.app.nav.dropdownOpen ? keys.navigator.closeDropdown() : ((keys.app.nav.viewMode === "entry" || keys.app.nav.viewMode === "document" || keys.app.nav.viewMode === "memory" || keys.app.nav.viewMode === "issue" || keys.app.nav.viewMode === "run") ? keys.navigator.goBack() : keys.actions.close()))
  }
```

with (one link inserted before `cancelOpen`; nothing else moves):

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

(c) Replace `modalOpen()`:

```qml
  // A modal is open: the global shortcuts and the run keys do nothing under it.
  function modalOpen() {
    return !!(keys.app.deleter.deleteTarget || keys.app.memories.memoryDeleteOpen || keys.app.memories.newMemoryOpen
              || keys.app.milestones.dialogOpen || keys.app.board.archiveOpen || keys.app.runs.cancelOpen)
  }
```

with

```qml
  // A modal is open: the global shortcuts, the run keys and d do nothing under it.
  function modalOpen() {
    return !!(keys.app.deleter.deleteTarget || keys.app.memories.memoryDeleteOpen || keys.app.memories.newMemoryOpen
              || keys.app.milestones.dialogOpen || keys.app.board.archiveOpen || keys.app.runs.cancelOpen
              || keys.app.runs.dispatchState !== "idle")
  }
```

(d) After the closing `}` of `handleRunKey(event)` add:

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
    if (keys.app.runs.amStatus === "missing" || keys.modalOpen() || keys.app.nav.dropdownOpen) return false
    if (mode === "board" && keys.app.nav.searchQuery !== "") return false
    var card = mode === "entry" ? keys.app.board.cardMap[keys.app.board.selectedCardId]
                                : keys.app.board.boardCards[keys.app.nav.cursorIndex]
    var id = card && typeof card.id === "string" ? card.id : ""
    if (id === "") return false
    keys.actions.openDispatch(id)
    return true
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_shortcuts`
Expected: PASS — both `tst_shortcuts.qml` and `tst_shortcuts_delete.qml` report `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add ui/Shortcuts.qml tests/ui/tst_shortcuts.qml
git commit -m "Shortcuts.qml: d asks for a dispatch; an open dispatch is a modal and Escape closes it (S3 4.2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: CardDetailScreen — the Dispatch button

**Files:**
- Modify: `ui/screens/CardDetailScreen.qml` (signals near line 26; after the badge `Row`, before `PanelSeparator`)
- Test: `tests/ui/screens/tst_card_detail_screen.qml`

**Interfaces:**
- Consumes: `app.runs.amStatus`, the open `card`.
- Produces: `signal dispatchRequested(string cardId)` (Panel maps it in Task 5); objectNames `cardDispatchButton`, `cardDispatchMissing`.

- [ ] **Step 1: Write the failing tests**

In `tests/ui/screens/tst_card_detail_screen.qml`, add after the `Component { id: flickC; … }` line:

```qml
  SignalSpy { id: dispatchSpy; signalName: "dispatchRequested" }
```

Append before the final `}`:

```qml
  // ---- Dispatch (S3 4.2)

  // 16
  function test_every_card_has_a_dispatch_button_that_asks_the_owner_data() {
    return [{ tag: "milestone", id: "m1" }, { tag: "story", id: "s1" }, { tag: "done-subtask", id: "t1" }]
  }

  function test_every_card_has_a_dispatch_button_that_asks_the_owner(data) {
    var s = make(); if (!s) return
    s.app.runs.snapshotRunner.cancel()
    dispatchSpy.target = s
    dispatchSpy.clear()
    s.navigator.openCard(data.id)
    wait(50)
    var button = H.find(s, "cardDispatchButton")
    verify(button, "the Dispatch button")
    compare(button.visible, true)
    compare(String(button.text), "Dispatch")
    compare(String(button.iconText), "▶")
    compare(button.enabled, true)
    compare(H.find(s, "cardDispatchMissing").visible, false)
    mouseClick(button)
    compare(dispatchSpy.count, 1)
    compare(dispatchSpy.signalArguments[0][0], data.id)
    compare(s.app.runs.dispatchState, "idle", "the screen opens nothing itself")
  }

  // 17
  function test_without_am_the_dispatch_button_is_disabled_and_says_why() {
    var s = make(); if (!s) return
    s.app.runs.snapshotRunner.cancel()
    dispatchSpy.target = s
    dispatchSpy.clear()
    s.app.runs.amStatus = "missing"
    s.navigator.openCard("m1")
    wait(50)
    var button = H.find(s, "cardDispatchButton")
    compare(button.enabled, false)
    mouseClick(button)
    compare(dispatchSpy.count, 0)
    var caption = H.find(s, "cardDispatchMissing")
    compare(caption.visible, true)
    compare(String(caption.text), "am is not installed or not on PATH")
    s.app.runs.amStatus = "ok"
    compare(caption.visible, false)
    compare(button.enabled, true)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_card_detail_screen`
Expected: FAIL — `the Dispatch button` verify fails, then `TypeError: Cannot read property 'enabled' of null` in the am-missing test.

- [ ] **Step 3: Implement**

In `ui/screens/CardDetailScreen.qml`:

(a) After `signal cancelRequested(string runId)` add:

```qml
  // The card's Dispatch was clicked. Opening a dispatch is the owner's job;
  // nothing here starts a run.
  signal dispatchRequested(string cardId)
```

(b) Between the badge `Row { … }` (the one ending with the `cardDetailIssueBadge` `Badge`) and `PanelSeparator { foreground: detailCard.theme.foreground }` add:

```qml
  // Every card has it: a story or a finished card opens a dialog that says
  // why it cannot start (and offers a story's milestone). Without am it is
  // disabled, and the caption says why.
  Row {
    spacing: Style.space(8)

    UI.ActionButton {
      objectName: "cardDispatchButton"
      theme: detailCard.theme
      iconText: "▶"
      text: "Dispatch"
      enabled: detailCard.app.runs.amStatus !== "missing"
      onClicked: if (detailCard.card) detailCard.dispatchRequested(detailCard.card.id)
    }

    UI.ThemedText {
      objectName: "cardDispatchMissing"
      variant: "caption"
      theme: detailCard.theme
      visible: detailCard.app.runs.amStatus === "missing"
      text: "am is not installed or not on PATH"
    }
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_card_detail_screen`
Expected: PASS — `0 failed`, including every existing card-detail test.

Also run: `python3 -m pytest tests/architecture -q` (or `uv run --with pytest python3 -m pytest tests/architecture -q` when `python3` has no pytest)
Expected: PASS (the screen still imports no `core/stores`; `bordered: true` is not written here — `ActionButton` carries it).

- [ ] **Step 5: Commit**

```bash
git add ui/screens/CardDetailScreen.qml tests/ui/screens/tst_card_detail_screen.qml
git commit -m "CardDetailScreen.qml: a Dispatch button on every card, disabled without am (S3 4.2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Panel — mount the dialog; the card detail and `d` entries; focus and Escape

**Files:**
- Modify: `ui/Panel.qml`
- Create: `tests/ui/tst_dispatch_flow.qml`

**Interfaces:**
- Consumes: Task 1's dialog props/signals, Task 3's `sc.handleDispatchKey(event)` and `actions.openDispatch`, Task 4's `dispatchRequested(cardId)`, `Board.issueBlockerLabel(status)`, `appStores.board.resolvedCard(id)` / `statusText(status)`, `appStores.runs.openDispatch(card, cardMap)` / `setDispatchField` / `dispatchStart` / `closeDispatch`.
- Produces (Tasks 6 and 7 build on them):
  - `property string dispatchCardId` (`""` for the board)
  - `readonly property bool dispatchOpen` (`dispatchState !== "idle"`)
  - `readonly property var dispatchCard`, `readonly property bool dispatchSubtask`, `readonly property string dispatchStoryTitle`, `readonly property string dispatchBlockedText`, `readonly property var dispatchSuggestion`
  - `function openDispatch(target)` (card id or `"board"`), `function launchDispatch(target)`, `function blockerText(id)`
  - `onDispatchOpenChanged` handler (Task 6 extends it)
  - `DispatchDialog { id: dispatchDialog; objectName: "dispatchDialog" }`

- [ ] **Step 1: Write the failing tests**

Create `tests/ui/tst_dispatch_flow.qml`:

```qml
// tests/ui/tst_dispatch_flow.qml
// The dispatch around the whole panel (S3 4.2): each entry point (the card
// detail's Dispatch, d on the board list, the Runs toolbar's Start run) opens
// the mounted dialog; the story's milestone offer, the subtask's lines and
// two-click Start, Escape, the focus, and where a start takes the user. The
// dialog's own rendering is tests/ui/components/tst_dispatch_dialog.qml; the
// store's rules are tests/core/stores/tst_run_store.qml.
import QtQuick
import QtTest
import "../helpers/find.js" as H

TestCase {
  id: tc
  name: "DispatchFlow"
  when: windowShown
  visible: true
  width: 900; height: 700
  Component { id: hostC; Item { width: 900; height: 700 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })

  function card(id, title, status, children, blockedBy) {
    var c = { id: id, title: title, status: status, description: "d", children: children || [] }
    if (blockedBy !== undefined) c.blocked_by = blockedBy
    return c
  }

  // m1 > s1 > t0 (done), t1 (blocked by t0, issue i1 and an unknown id), t2
  // (no blocked_by at all); m9 is a done milestone.
  function roots() {
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

  function run(id) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: "M one", status: "started", started_at: "",
             lease: { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: true },
             rows: [], tree: { stories: [], subtasks: [] } }
  }

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    // No helper may really run here (start-run.py starts am): every script
    // path leads nowhere, and each launch a test cares about is answered
    // through reply() before the event loop could deliver its real exit.
    p.app.backendDir = "/plugin/core/backend/"
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([pA, pB])
    if (!p.app.projects.selectedProject) { fail("project A is selected"); return null }
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.extras.extrasLoading = false
    p.app.runs.snapshotRunner.cancel()
    p.app.runs.settingsLoadRunner.cancel()
    // A stored verify command, so a fresh form passes the store's checks.
    p.app.runs.runSettings = { verify: ["uv run pytest"] }
    p.app.board.applyTreeData(roots())
    p.app.board.applyIssueData([{ id: "i1", title: "Broken build", status: "open" }])
    p.app.runs.runs = [run("run-0000000000a1")]
    wait(50)
    return p
  }

  // A helper's reply, delivered the way its Process would deliver it.
  function reply(proc, text) {
    proc.outText = text
    proc.exited(0)
  }

  // Answers the --defaults lookup and, for a milestone or the board, the dry
  // run it launches: the dispatch lands in ready.
  function toReady(p) {
    reply(p.app.runs.dispatchDefaultsRunner.current, '{"ok":true,"data":{"default_branch":"main"}}')
    if (p.app.runs.dispatchState === "previewing")
      reply(p.app.runs.dispatchPreviewRunner.current, '{"ok":true,"data":{"max_concurrent":4,"levels":[]}}')
    compare(p.app.runs.dispatchState, "ready")
  }

  // The card detail of `id`, and a click on its Dispatch.
  function dispatchCard(p, id) {
    p.navigator.openCard(id)
    wait(50)
    compare(p.app.nav.viewMode, "entry")
    H.find(p, "cardDispatchButton").clicked()
    wait(50)
  }

  function text(p, name) { return String(H.find(p, name).text) }

  // ---- entry points

  // 19
  function test_the_card_detail_dispatch_opens_the_dialog_on_that_card() {
    var p = make(); if (!p) return
    dispatchCard(p, "m1")
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(p.dispatchCardId, "m1")
    compare(text(p, "dispatchTarget"), "Target   Milestone \"M one\"")
    toReady(p)
    compare(H.find(p, "dispatchStart").enabled, true)
    compare(text(p, "dispatchStart"), "Start run", "a milestone starts on one click")
    wait(50)
    compare(p.focusItem.objectName, "dispatchBase")
    verify(H.find(p, "dispatchBase").activeFocus, "the dialog has the keyboard")
  }

  // 20
  function test_d_on_the_board_list_opens_the_dialog_on_the_cursor_card_without_typing() {
    var p = make(); if (!p) return
    p.navigator.showSection("board")
    p.app.nav.cursorIndex = 0
    compare(p.app.board.boardCards[0].id, "m1")
    wait(50)
    var field = H.find(p, "searchField")
    field.forceActiveFocus()
    keyClick("d")
    compare(p.app.runs.dispatchState, "previewing")
    compare(p.dispatchCardId, "m1")
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(text(p, "dispatchTarget"), "Target   Milestone \"M one\"")
    compare(String(field.text), "", "the handled letter was not typed")
    compare(p.app.nav.searchQuery, "")
  }

  // 22
  function test_a_story_offers_its_milestone_and_the_offer_reopens_on_it() {
    var p = make(); if (!p) return
    dispatchCard(p, "s1")
    compare(p.app.runs.dispatchState, "refused")
    compare(text(p, "dispatchTarget"), "Target   Story \"Story one\"")
    compare(text(p, "dispatchRefusal"), "A story is dispatched through its milestone")
    compare(H.find(p, "dispatchStart").enabled, false)
    var offer = H.find(p, "dispatchSuggest")
    compare(offer.visible, true)
    compare(String(offer.text), "Dispatch its milestone \"M one\"")
    offer.clicked()
    compare(p.dispatchCardId, "m1")
    compare(p.app.runs.dispatchState, "previewing")
    compare(text(p, "dispatchTarget"), "Target   Milestone \"M one\"")
    compare(offer.visible, false)
    wait(50)
    compare(p.focusItem.objectName, "dispatchBase", "the re-opened dialog has the focus")
  }

  // 23
  function test_a_subtask_shows_its_story_and_blockers_and_starts_on_the_second_click() {
    var p = make(); if (!p) return
    dispatchCard(p, "t1")
    compare(text(p, "dispatchTarget"), "Target   Subtask \"Do it\"")
    toReady(p)
    compare(text(p, "dispatchStory"), "Story   \"Story one\"")
    compare(text(p, "dispatchBlocked"), "Blocked by: \"Prep\" (Done), \"Broken build\" (Issue · open), ghost (not on this board)")
    var start = H.find(p, "dispatchStart")
    start.clicked()
    compare(p.app.runs.dispatchState, "ready", "the first click only arms")
    compare(p.app.runs.dispatchStartRunners.length, 0)
    compare(String(start.text), "Confirm start")
    compare(H.find(p, "dispatchConfirmNote").visible, true)
    start.clicked()
    compare(p.app.runs.dispatchState, "starting")
    compare(p.app.runs.dispatchStartRunners.length, 1)
    p.app.runs.dispatchStartRunners[0].cancel()
  }

  // Review Focus 4
  function test_a_subtask_without_blockers_says_so() {
    var p = make(); if (!p) return
    dispatchCard(p, "t2")
    toReady(p)
    compare(text(p, "dispatchStory"), "Story   \"Story one\"")
    compare(text(p, "dispatchBlocked"), "Blocked by: nothing")
  }

  // ---- Escape and the focus

  // 28
  function test_escape_closes_the_dialog_and_gives_the_focus_back() {
    var p = make(); if (!p) return
    dispatchCard(p, "s1")
    compare(H.find(p, "dispatchDialog").visible, true)
    var kc = H.find(p, "keyCatcher")
    kc.closeRequested()
    compare(p.app.runs.dispatchState, "idle")
    compare(H.find(p, "dispatchDialog").visible, false)
    compare(p.app.nav.viewMode, "entry", "that Escape closed the dialog only")
    compare(p.opened, true)
    wait(50)
    compare(p.focusItem.objectName, "keyCatcher")
    verify(kc.activeFocus, "the focus is back on the card")
  }

  // 28
  function test_escape_while_starting_does_nothing() {
    var p = make(); if (!p) return
    dispatchCard(p, "m1")
    toReady(p)
    compare(p.app.runs.dispatchStart(), true)
    p.app.runs.dispatchStartRunners[0].cancel()
    H.find(p, "keyCatcher").closeRequested()
    compare(p.app.runs.dispatchState, "starting")
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(p.app.nav.viewMode, "entry", "no Back")
    compare(p.opened, true, "no panel close")
  }

  // 29
  function test_a_re_preview_leaves_the_caret_in_the_field_being_typed_in() {
    var p = make(); if (!p) return
    dispatchCard(p, "m1")
    toReady(p)
    wait(50)
    var prefix = H.find(p, "dispatchPrefix")
    prefix.forceActiveFocus()
    prefix.text = "m-one-b"
    compare(p.app.runs.dispatchState, "previewing")
    compare(p.app.runs.dispatchForm.prefix, "m-one-b")
    // The 400 ms debounce, run now; then the dry run's reply.
    p.app.runs.dispatchDebounceTimer.stop()
    p.app.runs.checkDispatch()
    reply(p.app.runs.dispatchPreviewRunner.current, '{"ok":true,"data":{"max_concurrent":4,"levels":[]}}')
    compare(p.app.runs.dispatchState, "ready")
    wait(50)
    verify(prefix.activeFocus, "the caret stayed in Prefix")
  }

  // Review Focus 5
  function test_d_typed_in_a_dialog_field_types() {
    var p = make(); if (!p) return
    dispatchCard(p, "m1")
    toReady(p)
    wait(50)
    var prefix = H.find(p, "dispatchPrefix")
    prefix.forceActiveFocus()
    var before = String(prefix.text)
    keyClick("d")
    compare(String(prefix.text).length, before.length + 1, "the letter went into the field")
    compare(p.app.runs.dispatchForm.prefix, String(prefix.text), "an edit, not a re-opened dispatch")
    compare(p.app.runs.dispatchState, "previewing")
    compare(p.dispatchCardId, "m1")
  }

  // Review Focus 2
  function test_a_card_dropped_from_the_board_while_open_leaves_a_working_dialog() {
    var p = make(); if (!p) return
    dispatchCard(p, "t1")
    toReady(p)
    p.app.board.applyTreeData([card("m9", "M nine", "done")])
    wait(50)
    compare(H.find(p, "dispatchDialog").visible, true, "the store still holds the dispatch")
    compare(text(p, "dispatchTarget"), "Target   Subtask \"\"")
    compare(H.find(p, "dispatchStory").visible, false)
    compare(H.find(p, "dispatchBlocked").visible, false)
    H.find(p, "dispatchCancel").clicked()
    compare(p.app.runs.dispatchState, "idle")
    compare(H.find(p, "dispatchDialog").visible, false)
  }

  // ---- am missing

  // 31
  function test_without_am_the_card_dispatch_is_disabled_and_d_types() {
    var p = make(); if (!p) return
    p.app.runs.amStatus = "missing"
    p.navigator.openCard("m1")
    wait(50)
    compare(H.find(p, "cardDispatchButton").enabled, false)
    compare(text(p, "cardDispatchMissing"), "am is not installed or not on PATH")
    p.navigator.goBack()
    compare(p.app.nav.viewMode, "board")
    p.app.nav.cursorIndex = 0
    wait(50)
    var field = H.find(p, "searchField")
    field.forceActiveFocus()
    keyClick("d")
    compare(String(field.text), "d", "the letter typed into the search")
    compare(p.app.runs.dispatchState, "idle")
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_dispatch_flow`
Expected: FAIL — `TypeError: Cannot read property 'visible' of null` (no `dispatchDialog` in the panel) and `compare(p.dispatchCardId, …)` failures; the am-missing test may already pass (nothing opens yet).

- [ ] **Step 3: Implement**

In `ui/Panel.qml`:

(a) After `import qs.Ui` add:

```qml
import "../core/domain/board.js" as Board
```

(b) In the `Shortcuts { id: sc … }` block, replace

```qml
    actions: ({
      close: function() { root.close() },
      scrollBy: root.scrollBy,
      switchPanel: function(direction) { root.switchPanel(direction) },
      searchAtEnd: function() { return searchField.cursorPosition === searchField.text.length }
    })
```

with

```qml
    actions: ({
      close: function() { root.close() },
      scrollBy: root.scrollBy,
      switchPanel: function(direction) { root.switchPanel(direction) },
      searchAtEnd: function() { return searchField.cursorPosition === searchField.text.length },
      openDispatch: function(target) { root.openDispatch(target) }
    })
```

and change the comment above `Shortcuts {` from

```qml
  // Every key the panel reacts to. Like the navigator it owns no Items: closing
  // the panel, scrolling, switching panel and "is the caret at the end of the
  // search text?" are handed in.
```

to

```qml
  // Every key the panel reacts to. Like the navigator it owns no Items: closing
  // the panel, scrolling, switching panel, "is the caret at the end of the
  // search text?" and opening a dispatch are handed in.
```

(c) In `focusItem`, replace

```qml
    : appStores.milestones.dialogOpen ? newMilestoneDialog.focusItem
    : appStores.runs.cancelOpen ? runCancelModal.focusItem
```

with

```qml
    : appStores.milestones.dialogOpen ? newMilestoneDialog.focusItem
    : root.dispatchOpen ? dispatchDialog.focusItem
    : appStores.runs.cancelOpen ? runCancelModal.focusItem
```

(d) After the closing `}` of `openToastRun(key, runId)` add:

```qml
  // ---- Dispatch (S3 4.2). Panel opens every dispatch: a refused plan does
  // not say which card it was for, and the dialog needs the card's title,
  // story and blockers, so the card is kept here.
  property string dispatchCardId: ""   // the target card's id; "" for the board
  readonly property bool dispatchOpen: appStores.runs.dispatchState !== "idle"
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

  // The dialog takes the focus when it opens and gives it back when it closes,
  // never on a re-preview, which would pull the caret out of the field being
  // typed in. A re-target passes through idle, so it lands on the new dialog.
  onDispatchOpenChanged: root.focusForView()

  // A card id or "board": the card detail's Dispatch, d, and a story's offer.
  function openDispatch(target) {
    root.launchDispatch(target)
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

(e) Replace the `globalKeys` item

```qml
    // The Ctrl chords, then the run keys (p / r / c on the Runs list and Run
    // detail). An accepted key is not typed into the search field.
    Item {
      id: globalKeys
      Keys.onPressed: function(event) { if (sc.handleGlobalKey(event) || sc.handleRunKey(event)) event.accepted = true }
    }
```

with

```qml
    // The Ctrl chords, then the run keys (p / r / c on the Runs list and Run
    // detail), then d (the dispatch, on the board list and a card). An
    // accepted key is not typed into the search field.
    Item {
      id: globalKeys
      Keys.onPressed: function(event) {
        if (sc.handleGlobalKey(event) || sc.handleRunKey(event) || sc.handleDispatchKey(event)) event.accepted = true
      }
    }
```

(f) In the `CardDetailScreen { … }` block (the one whose properties are `width`, `app`, `navigator`, `theme`, `onRevealRequested`; `RunsScreen` and `RunDetailScreen` have the same `onCancelRequested` line -- do not touch them), after its `onCancelRequested: function(runId) { appStores.runs.openCancel(runId) }` add:

```qml
            onDispatchRequested: function(cardId) { root.openDispatch(cardId) }
```

(g) After the closing `}` of the `NewMilestoneDialog { id: newMilestoneDialog … }` block (the last child of `keyCatcher`) add:

```qml
      // The dispatch (S3 4.2): the card detail's Dispatch and d open it for a
      // card. Panel keeps the card (dispatchCardId) and composes the
      // subtask's story and blockers; the store holds everything else.
      DispatchDialog {
        id: dispatchDialog
        objectName: "dispatchDialog"
        anchors.fill: parent
        shown: root.dispatchOpen
        theme: panelTheme
        dispatchState: appStores.runs.dispatchState
        target: appStores.runs.dispatchTarget
        targetTitle: root.dispatchCard ? String(root.dispatchCard.title || "") : ""
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
        onFieldEdited: function(name, value) { appStores.runs.setDispatchField(name, value) }
        onStartRequested: appStores.runs.dispatchStart()
        onCancelRequested: appStores.runs.closeDispatch()
        onSuggestionRequested: if (root.dispatchSuggestion) root.openDispatch(root.dispatchSuggestion.id)
      }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_dispatch_flow`
Expected: PASS — `Totals: N passed, 0 failed`, no `TypeError` / `ReferenceError` / `Unable to assign` lines.

Then run: `bash tests/run.sh tst_` (every QML test)
Expected: PASS — in particular `tst_runs_flow`, `tst_board_flow`, `tst_panel_toolbar` and `tst_shortcuts` stay green.

- [ ] **Step 5: Commit**

```bash
git add ui/Panel.qml tests/ui/tst_dispatch_flow.qml
git commit -m "Panel.qml: mount the dispatch dialog; open it from a card and with d (S3 4.2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Panel — the Runs toolbar's `Start run` and its target chips

**Files:**
- Modify: `ui/Panel.qml`
- Test: `tests/ui/tst_panel_toolbar.qml`, `tests/ui/tst_dispatch_flow.qml`

**Interfaces:**
- Consumes: Task 5's `dispatchCardId`, `dispatchOpen`, `launchDispatch(target)`, `onDispatchOpenChanged`, `dispatchDialog`; Task 1's `targetChoices`, `targetChoice`, `targetChosen(id)`; `Runs.dispatchPlan(card, cardMap)`; `appStores.board.cardRoots`.
- Produces:
  - `property var dispatchChoices` (`[{id, label}]`, `[]` unless opened from Runs), `property bool dispatchRetargeting`
  - `function openRunsDispatch(target)`, `function runsDispatchChoices()`
  - toolbar `UI.ActionButton { objectName: "startRunButton" }`

- [ ] **Step 1: Write the failing tests**

Append before the final `}` of `tests/ui/tst_panel_toolbar.qml`:

```qml
  // ---- Start run (S3 4.2)

  // 18
  function test_start_run_shows_only_on_the_runs_list_of_a_project() {
    var p = make(); if (!p) return
    p.app.runs.snapshotRunner.cancel()
    p.app.runs.runs = [{ id: "run-0000000000a1", repo_dir: "/home/u/my proj", milestone_id: "alpha", status: "started",
                         started_at: "", lease: null, rows: [], tree: { stories: [], subtasks: [] } }]
    var button = H.find(p, "startRunButton")
    verify(button, "the Start run button")
    var hidden = ["board", "graph", "memories", "issues"]
    for (var i = 0; i < hidden.length; i++) {
      p.navigator.showSection(hidden[i])
      compare(button.visible, false, hidden[i])
    }
    p.navigator.showSection("runs")
    wait(50)
    compare(button.visible, true)
    compare(String(button.text), "Start run")
    compare(String(button.iconText), "▶")
    compare(button.enabled, true)
    compare(String(button.tooltipText), "Start an am run")
    p.navigator.openRun("run-0000000000a1", "runs")
    compare(p.app.nav.viewMode, "run")
    compare(button.visible, false, "run detail")
    p.navigator.goBack()
    compare(button.visible, true)
    p.app.runs.amStatus = "missing"
    compare(button.enabled, false)
    compare(String(button.tooltipText), "am is not installed or not on PATH")
    p.app.projects.selectedProject = null
    p.app.nav.viewMode = "runs"
    compare(button.visible, false, "no project")
  }
```

Append before the final `}` of `tests/ui/tst_dispatch_flow.qml`:

```qml
  // ---- the Runs entry

  // 21
  function test_the_runs_toolbar_opens_the_whole_board_with_a_row_of_targets() {
    var p = make(); if (!p) return
    compare(p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 }), true)
    wait(50)
    var button = H.find(p, "startRunButton")
    compare(button.visible, true)
    button.clicked()
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(p.dispatchCardId, "")
    compare(text(p, "dispatchTarget"), "Target   Whole board")
    compare(H.find(p, "dispatchTargetChoices").visible, true)
    compare(p.dispatchChoices.map(function(c) { return c.id + ":" + c.label }).join(","), "board:Whole board,m1:M one")
    verify(H.find(p, "dispatchTargetChoiceboard"), "the board chip")
    verify(!H.find(p, "dispatchTargetChoicem9"), "a done milestone is not offered")
    compare(H.find(p, "dispatchTargetChoiceboard").active, true)
    toReady(p)
    H.find(p, "dispatchTargetChoicem1").clicked()
    compare(p.dispatchCardId, "m1")
    compare(p.app.runs.dispatchState, "previewing")
    compare(text(p, "dispatchTarget"), "Target   Milestone \"M one\"")
    compare(H.find(p, "dispatchTargetChoices").visible, true, "the row survives a re-target")
    compare(p.dispatchChoices.length, 2)
    compare(H.find(p, "dispatchTargetChoicem1").active, true)
    compare(H.find(p, "dispatchTargetChoiceboard").active, false)
    H.find(p, "dispatchCancel").clicked()
    compare(H.find(p, "dispatchDialog").visible, false)
    compare(p.dispatchChoices.length, 0, "a close drops the row")
    dispatchCard(p, "m1")
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(H.find(p, "dispatchTargetChoices").visible, false, "the card detail has no row")
  }

  // 30
  function test_a_project_switch_drops_the_dialog_and_its_targets() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    H.find(p, "startRunButton").clicked()
    compare(p.dispatchChoices.length, 2)
    p.navigator.chooseProject(tc.pB)
    compare(p.app.runs.dispatchState, "idle")
    compare(H.find(p, "dispatchDialog").visible, false)
    compare(p.dispatchChoices.length, 0)
  }

  // 31
  function test_without_am_start_run_is_disabled() {
    var p = make(); if (!p) return
    p.app.runs.amStatus = "missing"
    p.navigator.showSection("runs")
    wait(50)
    compare(H.find(p, "startRunButton").enabled, false)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_panel_toolbar` then `bash tests/run.sh tst_dispatch_flow`
Expected: FAIL — `the Start run button` verify fails; the new flow tests throw `TypeError: Cannot read property 'visible' of null` / `… 'clicked' of null`; the Task 5 flow tests still pass.

- [ ] **Step 3: Implement**

In `ui/Panel.qml`:

(a) In the dispatch block added in Task 5, replace

```qml
  // ---- Dispatch (S3 4.2). Panel opens every dispatch: a refused plan does
  // not say which card it was for, and the dialog needs the card's title,
  // story and blockers, so the card is kept here.
  property string dispatchCardId: ""   // the target card's id; "" for the board
```

with

```qml
  // ---- Dispatch (S3 4.2). Panel opens every dispatch: a refused plan does
  // not say which card it was for, and the dialog needs the card's title,
  // story and blockers, so the card is kept here. The Runs entry adds a row
  // of targets (the whole board, then each milestone that can be dispatched),
  // which survives a re-target but not a close.
  property string dispatchCardId: ""   // the target card's id; "" for the board
  property var dispatchChoices: []     // [{id, label}]; [] unless opened from Runs
  property bool dispatchRetargeting: false
```

(b) Replace

```qml
  // The dialog takes the focus when it opens and gives it back when it closes,
  // never on a re-preview, which would pull the caret out of the field being
  // typed in. A re-target passes through idle, so it lands on the new dialog.
  onDispatchOpenChanged: root.focusForView()

  // A card id or "board": the card detail's Dispatch, d, and a story's offer.
  function openDispatch(target) {
    root.launchDispatch(target)
  }
```

with

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

  // A card id or "board": the card detail's Dispatch, d, and a story's offer.
  // None of them shows the target row.
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
```

(c) In the toolbar `RowLayout`, after the closing `}` of the `archiveFinishedButton` `UI.ActionButton { … }` add:

```qml
          // The Runs list's way to start a run: the dialog opens on the whole
          // board with a row of targets. Disabled while am is missing.
          UI.ActionButton {
            objectName: "startRunButton"
            theme: panelTheme
            visible: appStores.nav.viewMode === "runs" && !!appStores.projects.selectedProject
            enabled: appStores.runs.amStatus !== "missing"
            iconText: "▶"
            text: "Start run"
            tooltipText: appStores.runs.amStatus === "missing" ? "am is not installed or not on PATH" : "Start an am run"
            onClicked: root.openRunsDispatch("board")
          }
```

(d) In the `DispatchDialog { id: dispatchDialog … }` block, replace its comment

```qml
      // The dispatch (S3 4.2): the card detail's Dispatch and d open it for a
      // card. Panel keeps the card (dispatchCardId) and composes the
      // subtask's story and blockers; the store holds everything else.
```

with

```qml
      // The dispatch (S3 4.2): the card detail's Dispatch and d open it for a
      // card, the Runs toolbar's Start run for the whole board with a row of
      // targets. Panel keeps the card (dispatchCardId) and the row, and
      // composes the subtask's story and blockers; the store holds the rest.
```

and after its `suggestion: root.dispatchSuggestion` line add:

```qml
        targetChoices: root.dispatchChoices
        targetChoice: root.dispatchCardId === "" ? "board" : root.dispatchCardId
```

and after its `onSuggestionRequested: …` line add:

```qml
        onTargetChosen: function(id) { root.openRunsDispatch(id) }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_panel_toolbar` then `bash tests/run.sh tst_dispatch_flow`
Expected: PASS — `0 failed` in both, no `TypeError` lines.

- [ ] **Step 5: Commit**

```bash
git add ui/Panel.qml tests/ui/tst_panel_toolbar.qml tests/ui/tst_dispatch_flow.qml
git commit -m "Panel.qml: Start run on the Runs list, with a row of dispatch targets (S3 4.2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Panel — after a start, close the dialog and go to the run

**Files:**
- Modify: `ui/Panel.qml` (the `Connections { target: appStores.runs }` block, line ~95)
- Test: `tests/ui/tst_dispatch_flow.qml`

**Interfaces:**
- Consumes: `appStores.runs.dispatchStarted(runId)` (signal; `runId` a string or `null`), `appStores.runs.closeDispatch()`, Task 2's `navi.openStartedRun(runId)` and `navi.openAwaitedRun()`.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing tests**

Append before the final `}` of `tests/ui/tst_dispatch_flow.qml`:

```qml
  // ---- after a start

  // A ready subtask t1, started (two clicks), then start-run.py's reply.
  function startT1(p, replyText) {
    dispatchCard(p, "t1")
    toReady(p)
    var start = H.find(p, "dispatchStart")
    start.clicked()
    start.clicked()
    compare(p.app.runs.dispatchState, "starting")
    reply(p.app.runs.dispatchStartRunners[0].current, replyText)
    // A good start fetches the runs again; that launch cannot run here either.
    p.app.runs.snapshotRunner.cancel()
  }

  // 24
  function test_a_start_whose_run_is_listed_opens_its_run_detail() {
    var p = make(); if (!p) return
    p.app.runs.runs = [run("run-0000000000a1"), run("run-new")]
    startT1(p, '{"ok":true,"run_id":"run-new","message":"started"}')
    compare(H.find(p, "dispatchDialog").visible, false)
    compare(p.app.runs.dispatchState, "idle")
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-new")
    p.shortcuts.closeRequested()
    compare(p.app.nav.viewMode, "runs", "Back lands on the Runs list")
  }

  // 25
  function test_a_start_before_the_snapshot_waits_for_the_run_then_opens_it() {
    var p = make(); if (!p) return
    startT1(p, '{"ok":true,"run_id":"run-late","message":"started"}')
    compare(H.find(p, "dispatchDialog").visible, false)
    compare(p.app.nav.viewMode, "runs")
    wait(50)
    compare(text(p, "runsFooter"), "Started — opening the run when it appears")
    p.app.runs.runs = p.app.runs.runs.concat([run("run-late")])
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-late")
  }

  // 26
  function test_a_start_without_a_run_id_goes_to_the_runs_list_and_says_so() {
    var p = make(); if (!p) return
    startT1(p, '{"ok":true,"message":"started, run not visible yet"}')
    compare(H.find(p, "dispatchDialog").visible, false)
    compare(p.app.nav.viewMode, "runs")
    wait(50)
    compare(text(p, "runsFooter"), "Started — waiting for the run to appear")
  }

  // 27
  function test_a_failed_launch_keeps_the_dialog_and_goes_nowhere() {
    var p = make(); if (!p) return
    startT1(p, '{"ok":false,"error":{"type":"Spawn","message":"no am"},"log":"/tmp/l","exit_code":2}')
    compare(p.app.runs.dispatchState, "failed")
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(text(p, "dispatchRefusal"), "no am")
    compare(p.app.nav.viewMode, "entry")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_dispatch_flow`
Expected: FAIL — tests 24-26 fail at `compare(H.find(p, "dispatchDialog").visible, false)` (the dialog stays open in `started`); test 27 passes already (nothing navigates on a failure).

- [ ] **Step 3: Implement**

In `ui/Panel.qml`, replace

```qml
  // A different Runs chip means a different list: the cursor reset is App's,
  // the scroll is the panel's. The cancel confirmation takes the focus when it
  // opens and gives it back when it closes.
  Connections {
    target: appStores.runs
    function onRunFilterToggled() { Qt.callLater(root.scrollToTop) }
    function onCancelOpenChanged() { root.focusForView() }
  }
```

with

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

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_dispatch_flow`
Expected: PASS — `0 failed`.

Then run: `bash tests/run.sh tst_runs_flow`
Expected: PASS (an assignment to `runs` with nothing awaited does nothing).

- [ ] **Step 5: Commit**

```bash
git add ui/Panel.qml tests/ui/tst_dispatch_flow.qml
git commit -m "Panel.qml: a started dispatch closes and opens its run, or waits for it (S3 4.2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: `docs/architecture.md`, and the full gate

**Files:**
- Modify: `docs/architecture.md` (line 98 Navigator, lines 102-104 Shortcuts, line 151 DispatchDialog, after line 163)

**Interfaces:** none.

- [ ] **Step 1: Navigator sentence** — replace

```
from the Runs list Back restores the list through `restoreRunsList()`), `Shortcuts.qml` (key
```

with

```
from the Runs list Back restores the list through `restoreRunsList()`; after a dispatch `openStartedRun(runId)` shows the Runs list and opens the run when the snapshot already lists it, else remembers it (`awaitedRunId`, `awaitedProject`) and flashes `Started — opening the run when it appears` -- `openAwaitedRun()`, called on every change of `app.runs.runs`, opens it once it is listed while the panel is still on that project's Runs list and forgets it anywhere else; a start with no run id flashes `Started — waiting for the run to appear`), `Shortcuts.qml` (key
```

- [ ] **Step 2: Shortcuts sentence** — replace

```
`c` only opens the cancel confirmation; `modalOpen()` is the one guard both the
chords and the run keys obey, and Escape closes the cancel confirmation, then
```

with

```
`c` only opens the cancel confirmation; `handleDispatchKey` makes a bare `d`
open the dispatch dialog -- never start anything -- for the board list's cursor
card while its search is empty, or for the open card, and leaves the letter
alone without a project, while am is missing, or under a modal or the open
dropdown; `modalOpen()` is the one guard the chords, the run keys and `d` obey,
and an open dispatch counts as a modal; Escape closes the dispatch dialog (and
does nothing at all while its start is in flight), then the cancel
confirmation, then
```

- [ ] **Step 3: DispatchDialog entry** — replace

```
The verify rows are counted, not listed, so typing never recreates the row under the cursor. Not yet mounted: card 4.2 mounts it),
```

with

```
The verify rows are counted, not listed, so typing never recreates the row under the cursor. Three owner-driven extras (S3 4.2): `targetChoices` / `targetChoice` draw a `ChipRow` of targets under the target line and emit `targetChosen(id)` for a chip other than the active one (busy while starting); a `refused` dialog with a `suggestion` `{id, title}` shows `Dispatch its milestone "<title>"`, which emits `suggestionRequested()`; with `confirmFirst` the first click on Start only arms it (`armed`: Start reads `Confirm start` and `Click Confirm start to start this subtask.` shows), the second emits `startRequested()`, and any change of state, target, form, `confirmFirst` or visibility disarms it. Panel mounts it as `dispatchDialog`),
```

- [ ] **Step 4: The Panel-owned dispatch** — replace

```
Every age on these screens is read against the clock once per snapshot (or logs reply): there is no timer.
```

with (the same sentence, then a new paragraph)

```
Every age on these screens is read against the clock once per snapshot (or logs reply): there is no timer.

Panel owns the dispatch (S3 4.2). Three entry points open `dispatchDialog`, never start anything, and are disabled (`am is not installed or not on PATH`) while am is missing: `CardDetailScreen`'s `▶ Dispatch` on every card (its `dispatchRequested(cardId)`; a story or a finished card opens a dialog that says why, and a story's offers its milestone), a bare `d` on the board list or a card (`Shortcuts.handleDispatchKey`), and the Runs toolbar's `▶ Start run` (`startRunButton`), which opens the whole board with a chip row of `Whole board` plus every milestone `Runs.dispatchPlan` offers. `root.openDispatch(target)` / `root.openRunsDispatch(target)` keep the card id (`dispatchCardId`; a refused plan does not carry it) and call `app.runs.openDispatch`; Panel composes a subtask's `Story   "<title>"` and `Blocked by: …` lines and binds `confirmFirst` to a subtask target, so a subtask's Start takes two clicks. The dialog takes the focus when it opens and gives it back when it closes -- never on a re-preview. Cancel, the backdrop, Escape and a project switch all close it (except while starting) and drop the chip row -- closing the panel does not: the store keeps an open dispatch, and the dialog and its chips are still there when the panel reopens; a chip or the milestone offer re-targets it. On `dispatchStarted` Panel closes it and calls `navi.openStartedRun(runId)`; a failed launch keeps it open with the failure.
```

- [ ] **Step 5: Run the full gate**

Run: `bash tests/run.sh`
Expected: pytest `passed` with no failures (including `tests/architecture`), every QML file `Totals: … 0 failed`, no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `anchors on an item` / `is not a function` lines, exit status 0.

- [ ] **Step 6: Commit**

```bash
git add docs/architecture.md
git commit -m "architecture.md: the dispatch's entry points, its owner and where a start goes (S3 4.2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Self-review against the spec

| Spec item | Task |
|---|---|
| D1 Panel opens every dispatch (`openDispatch`, `dispatchCardId`, signal from card detail, `actions.openDispatch`) | 3, 4, 5 |
| D2 Runs toolbar button + target chips, board default, chips survive re-target | 6 |
| D3 story offer button → `openDispatch(suggest.id)` | 1, 5 |
| D4 `confirmFirst`, `armed`, disarm rules | 1, 5 |
| D5 story title and blocked text composition | 5 |
| D6 footer flash, verbatim sentence | 2, 7 |
| D7 awaited run, project + Runs-list rule | 2, 7 |
| D8 `d` rules | 3, 5 |
| D9 focus only on open/close | 5 (tests 19, 22, 28, 29) |
| D10 `▶` only | 4, 6 |
| Panel table of bindings and signals | 5, 6 |
| `dispatchChoices` emptied on close / project switch (panel close does not reset the store's dispatch, so it keeps the dialog and its chips) | 6 |
| `focusItem` chain before `runCancelModal` | 5 |
| `Connections` additions | 5 (focus via `onDispatchOpenChanged`), 7 |
| Toolbar `Start run` visibility, enabled, tooltip | 6 |
| Card detail button + caption | 4 |
| Shortcuts `modalOpen`, Escape chain before `cancelOpen` | 3 |
| Navigator `openStartedRun`, `openAwaitedRun` | 2 |
| Errors table rows | 3 (d refusals), 4/5/6 (am missing), 5 (story, finished, Escape, starting), 6 (project switch, chips busy via Task 1), 7 (launch failure, the three started cases), 2 (user leaves Runs list) |
| Tests 1-31 | 1 (1-5), 3 (6-10), 2 (11-15), 4 (16-17), 6 (18, 21, 30, 31), 5 (19, 20, 22, 23, 28, 29, 31), 7 (24-27) |
| Architecture tier unchanged and passing | 4 (step 4), 8 (step 5) |
| `docs/architecture.md` four edits | 8 |

Notes for the implementer:

- `onDispatchOpenChanged` is how D9's "refocus when `dispatchState` changes to or from `idle`" is done: `dispatchOpen` is a binding on `dispatchState !== "idle"`, so it changes exactly on those transitions; a re-target goes open → idle → open synchronously inside `openDispatch`, and both refocus calls are `Qt.callLater`, so the focus lands on the new dialog's `focusItem`.
- The spec's "`dispatchChoices` emptied whenever `dispatchState` becomes `idle` by any route other than a re-target" is `onDispatchOpenChanged` with the `dispatchRetargeting` flag `openRunsDispatch` raises around its store call. The row is built only when it is empty, so a chip click never replaces the model under the chip being clicked.
- A finished milestone (`m9` in the flow) is left out of the chips because `Runs.dispatchPlan` refuses it — the same rule the store applies.
- The flow tests never let a real helper run: `make()` points `app.backendDir` at a path that does not exist, and each launch a test needs answered gets `reply()` straight away. Do not add a `wait()` between a launch and its `reply()`; the path that does not exist would exit first and the store would take that empty reply.
<!-- task-pipeline: validated -->
