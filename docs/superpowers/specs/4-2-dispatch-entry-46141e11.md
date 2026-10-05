# 4.2 Dispatch entry points (card 46141e11)

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

## Starting point (all on this branch)

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

## Scope

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

### Out of scope

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

## Decisions

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

## Behaviour

### Panel — the mounted dialog

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

### Panel — toolbar `Start run`

`UI.ActionButton { objectName: "startRunButton"; iconText: "▶"; text: "Start
run" }` in the toolbar row; `visible` only while `viewMode === "runs"` and a
project is selected; `enabled: amStatus !== "missing"`; `tooltipText` `am is
not installed or not on PATH` while missing, else `Start an am run`. Click →
`root.openRunsDispatch("board")`.

### Card detail — Dispatch button

Below the badge row: `UI.ActionButton { objectName: "cardDispatchButton";
iconText: "▶"; text: "Dispatch" }`, shown for every card (a story or finished
card opens the dialog, which says why it cannot start and, for a story, offers
its milestone); `enabled: app.runs.amStatus !== "missing"`. While missing a
caption `cardDispatchMissing` beside it reads `am is not installed or not on
PATH`; otherwise that caption is hidden. Click emits the new `signal
dispatchRequested(string cardId)` with the open card's id; Panel maps it to
`root.openDispatch(cardId)`.

### Shortcuts — `d`

`handleDispatchKey(event)` (D8), wired in Panel's `globalKeys` after
`handleRunKey`: returns true (and calls `actions.openDispatch(id)`) for the
board cursor card or the open card; false otherwise.

`modalOpen()` also returns true while `app.runs.dispatchState !== "idle"`.

`closeRequested()`: a new link `app.runs.dispatchState !== "idle" ?
app.runs.closeDispatch()` immediately before the `cancelOpen` link. While
`starting` `closeDispatch()` refuses, so Escape does nothing at all (no Back,
no panel close).

### Navigator

- `openStartedRun(runId)`: `showSection("runs")`; then `null`/`""` → flash D6;
  an id in `app.runs.runs` → `openRun(id, "runs")`; any other id →
  `awaitedRunId = id`, `awaitedProject = selectedProject.root_path`, flash
  `Started — opening the run when it appears`.
- `openAwaitedRun()`: nothing when `awaitedRunId === ""`. If `viewMode !==
  "runs"` or the selected project's `root_path` differs from `awaitedProject`,
  clears both and returns. If the run is now in `app.runs.runs`, clears both
  and calls `openRun(id, "runs")`. Otherwise keeps waiting.

Back from the opened run returns to the Runs list (`openRun` from `"runs"`).

### DispatchDialog — additions

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

## Errors and edge cases

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

## Tests

All written first. `bash tests/run.sh` is the gate (it also fails on any
TypeError / ReferenceError / "Unable to assign" / "is not a function" in the
output). In flow and Navigator tests the helpers cannot run: drive the store's
reply handlers directly — `p.app.runs.dispatchDefaultsReplied('{"ok":true,
"data":{"default_branch":"main"}}')`, `dispatchPreviewReplied(<ok envelope>)`,
and after `dispatchStart()` `dispatchStartReplied(p.app.runs.dispatchStartRunners[0],
'{"ok":true,"run_id":"run-…","message":"…"}')`; seed `p.app.runs.runs` to stand
in for the snapshot that follows.

### Component tier — `tests/ui/components/tst_dispatch_dialog.qml` (extend)

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

### Unit tier — `tests/ui/tst_shortcuts.qml` (extend)

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

### Unit tier — `tests/ui/tst_navigator.qml` (extend)

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

### Screen tier — `tests/ui/screens/tst_card_detail_screen.qml` (extend)

The button is the screen's; real `App` and `Navigator`.

16. `cardDispatchButton` visible on a milestone, a story and a done subtask,
    text `Dispatch`, `iconText` `▶`; a click emits `dispatchRequested` with the
    open card's id.
17. With `amStatus "missing"`: disabled, a click emits nothing,
    `cardDispatchMissing` visible with `am is not installed or not on PATH`;
    with `amStatus` `ok` the caption is hidden.

### Panel tier — `tests/ui/tst_panel_toolbar.qml` (extend)

18. `startRunButton` visible only in `runs` with a project (hidden on board,
    graph, memories, issues, a run detail, and with no project); text `Start
    run`, `iconText` `▶`; disabled with `amStatus "missing"`.

### Flow tier — new `tests/ui/tst_dispatch_flow.qml`

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

### Architecture tier — `tests/architecture` (unchanged, must pass)

`CardDetailScreen.qml` still imports no `core/stores`; no new QML type; the
dialog's additions reuse `ChipRow`, `ActionButton`, `ThemedText`; no
private-use glyph; no second copy of a guarded visual pattern.

## Review focus for the planner

- Focus theft: refocusing on every `dispatchStateChanged` would yank the caret
  out of a field on each re-preview (test 29).
- The run is usually not in `runs` when `dispatchStarted` fires; `openRun`
  silently no-ops (tests 13, 25).
- The `d` key must not swallow typing: non-empty search, `Shift+D` and every
  refused case return false (tests 7, 31).
- Escape while `starting` must not fall through to Back or close (tests 10, 28).
- Re-targeting passes through `idle`: the choices must survive a chip click but
  not a close (test 21).
