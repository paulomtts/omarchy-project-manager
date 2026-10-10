# 3.3 Run detail: Why it stopped and Relaunch (card b7ef64db)

Narrowed from `docs/superpowers/specs/2026-10-05-resume-recover-design.md`
(the parent): "Why it stopped (Run detail)" (lines 124-163), "Relaunch"
(lines 200-215), the `offersRelaunch` paragraph of "Refusals in user terms"
(lines 229-232), the "UI" bullet of "Architecture" (lines 279-285), "Errors
and edge cases" (lines 287-298), "Testing" (lines 321-325), "Limits" (lines
327-332) and "Open" (lines 340-342). Parent story 215a0691. Blocked by
ad383829 (3.2 `ResumeVerifyDialog`, done).

## Inherited constraints

- The block shows for a run in state `escalated`, `parked`, `dead` or
  `cancelled`, "between the header and the controls" (parent lines 126-127).
- Escalated names the subtask (short card id, its story's title), the failed
  phase and its `detail`; a synthetic node is named as the tree names it
  (parent lines 141-143). Parked: "Paused at a phase boundary" and the
  subtasks recorded `stopped` (line 144). Dead: "The run's process died" with
  the last heartbeat's age and the in-flight subtask and phase (lines
  145-146). Cancelled: the cancelled sentence and the subtasks it parked
  (lines 147-148). All of these are already computed by `Runs.stopReport`.
- am's note: the escalated subtask's card's note for this run, else the
  milestone card's `run-end` note; `reason`, `detail`, `next`, `why` lines;
  hidden when there is none; read from the OPEN project's comments only
  (parent lines 149-153, Limits 329-330, Non-goals line 120).
- **Open card** opens that card's detail; "offered only when the run belongs
  to the open project" (parent lines 153-155).
- The output heading for attempt `0` reads `Output · <card> verify (newest)`
  (parent lines 156-160).
- Relaunch is offered for a `cancelled` run, an escalated `task` run, and a
  stopped run whose last resume am refused with `NotResumableError` or
  `CheckpointMismatchError` (parent lines 202-204, 229-230).
- Relaunch opens S3's dispatch dialog through `relaunchOpenFor` with the run's
  prefix and base (parent lines 205-210); "For a run of a project that is not
  open, Relaunch is disabled with "Open this run's project to relaunch it""
  (lines 211-214); a finished target is refused by `dispatchPlan` (lines
  214-215, table line 297). Kept disabled, no one-click open-then-relaunch
  (Open, lines 340-342).
- "run of another project | the block shows without am's note; Open card and
  Relaunch are disabled with the reason" (table line 296). `cancelled` and
  `canceled` are both cancelled (line 298; `Runs.runState` does it).
- `StopReasonBlock` is "presentation only: the owner passes the report, the
  comment and the actions", placed in `RunDetailScreen`, "which looks the
  target card up in `app.board.cardMap` for Relaunch" (parent lines 282-285).
- Components and screens never import `core/stores`
  (`tests/architecture/test_layers.py`, `violations_screen`); no local QML
  type shares a shell/Controls type name; no second copy of a guarded visual
  pattern (`GUARDS`, `test_layers.py:246-273`): text is `UI.ThemedText`,
  buttons are `UI.ActionButton`, no `font.family:`, no `bordered: true`, no
  `radius: height/2`. Glyphs come from `ui/components/runGlyphs.js` only
  (`‼ ⏸ ✖ ⊘`, none private-use), so `tests/architecture/test_icon_glyphs.py`
  is unaffected.
- Docstrings and comments state the contract only, no narrative (card).
- UI strings use `…`, never `...`.
- Verification: `bash tests/run.sh` green; it also fails on `TypeError`,
  `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item`
  or `is not a function` in QML test output. TDD: tests first (card).

## Starting point (already done by sibling cards; consume as is)

- `core/domain/runs.js`:
  - `stopReport(run)` (`:1148`): null, or `{state, headline, cardId, storyId,
    storyTitle, phase, detail, heartbeatAt, attempt, parked, relaunch}`.
    `headline` is complete (`Escalated at <phase>`, `Escalated at <synthetic
    label>`, `The run's process died`, `Paused at a phase boundary`, the
    cancelled sentence). `cardId` is `""` for parked, cancelled and a synthetic
    escalation; `storyTitle` is the synthetic label then. `relaunch` is
    `{level, cardId, prefix, base}` or null.
  - `stopComment(comments, runId)` (`:1239`): `{createdAt, kind, fields:
    [{key, value}]}` or null; fields in `reason`, `detail`, `next`, `why` order.
  - `controls(run).resume` (`:893`): disabled for cancelled, done, running,
    unknown, and an escalated `workflow: "task"` run.
  - `offersRelaunch(error)` (`:956`): reads envelope or bare `{type}`.
  - `withProject({}, root, "").project.root`: a root with trailing `/`
    removed, `""` for a non-string (used by `RunStore.projectRootOf`, `:318`).
  - `snapshotAgeText(fetchedMs, nowMs)` (`:670`): `"5m"` etc., `""` when unusable.
- `core/stores/RunStore.qml`: `project` (`:42`, the open project's root, `""`
  when none), `lastControlError` / `lastControlErrorRunId` /
  `lastControlErrorType` (`:128-130`), `flash(text)` (`:1336`),
  `relaunchOpenFor(card, cardMap, relaunch)` (`:1897`; false without a card
  or relaunch object; otherwise `openDispatch`, which refuses a finished card
  into `dispatchState "refused"`), and `openDefaultAttempt` (`:828`), which
  already selects `stopReport.attempt`, attempt `0` included.
- `core/stores/ExtrasStore.qml` `commentsFor(entityId)` (`:95`): the card's
  comments `{author, body, createdAt, …}`, oldest first, `[]` by default.
- `ui/Panel.qml` shows `DispatchDialog` while `runs.dispatchState !== "idle"`
  and passes `navigator: navi` to `RunDetailScreen` (`:762-768`).
- `ui/Navigator.qml` `openCard(id)` (`:198`).

## Scope

- Create `ui/components/StopReasonBlock.qml`.
- Create `tests/ui/components/tst_stop_reason_block.qml`.
- Modify `ui/screens/RunDetailScreen.qml`: mount the block (replacing
  `runDetailReason`), the note / project / relaunch lookups, the `(newest)`
  heading.
- Modify `tests/ui/screens/tst_run_detail_screen.qml`: stub additions, the
  two tests that read `runDetailReason`, new cases.
- Modify `tests/ui/tst_runs_flow.qml`: one new case.

### Out of scope

- `docs/architecture.md` and README: card 3.4 (20869d96) owns them.
- Any change to `core/` (`runs.js`, `RunStore`, `ExtrasStore`, the backend).
  A store defect found here is reported, not fixed.
- A **Resume** button in the block. The parent's mock-up (line 137) and
  signal list (line 284, `resumeRequested()`) include one; this card's
  deliverable names only Open card and Relaunch, and `UI.RunControls`
  (`runDetailControls`, directly below the block) already carries Resume with
  its reason. The block declares no `resumeRequested` signal.
- `ResumeVerifyDialog`, `VerifyCommandsField`, `DispatchDialog`, the
  `controlError` sentences: other cards, unchanged.
- Fetching comments of a project that is not open (parent Non-goals, line 120).
- Opening another project and relaunching in one click (parent Open, line 340).

## Behaviour

### `StopReasonBlock` — the component's interface

A `Column`, default `objectName: "stopReasonBlock"`, `visible` exactly when
`report` is a non-null object. Presentation only: it imports
`runGlyphs.js` and `../components`/`../theme`, no store and no `core/`
module. It never changes its inputs.

Properties (owner → block):

| property | type | default | meaning |
|---|---|---|---|
| `theme` | var | `T.Theme {}` | colours and fonts |
| `report` | var | `null` | `Runs.stopReport(run)` |
| `note` | var | `null` | `Runs.stopComment(…)` or null |
| `heartbeatAge` | string | `""` | the dead run's last heartbeat age without "ago" (`"5m"`), `""` for none |
| `openCardId` | string | `""` | the card Open card opens; `""` hides the button |
| `openCardReason` | string | `""` | why Open card is disabled; `""` = enabled |
| `relaunchOffered` | bool | `false` | Relaunch is shown |
| `relaunchReason` | string | `""` | why Relaunch is disabled; `""` = enabled |

Signals (block → owner):

- `openCardRequested(string id)`: a click on Open card while it is enabled,
  with `openCardId`.
- `relaunchRequested()`: a click on Relaunch while it is enabled.

### What it shows, top to bottom

1. `stopTitle`: `Why it stopped` (bold).
2. `stopHeadline`, word-wrapped: the state's glyph
   (`RunGlyphs.glyphOf(report.state)`) and a space when the glyph is not `""`,
   then `report.headline`, then, when `report.cardId` is not `""`:
   ` · #` + the first 8 characters of `report.cardId`, and, when
   `report.storyTitle` is also not `""`, ` · story "<storyTitle>"`; then, for
   state `dead` with `report.phase` not `""`, ` · at <phase>`. Colour
   `theme.urgent` for `escalated` and `dead`, `theme.foreground` otherwise.
   Example: `‼ Escalated at verify · #5bfe746d · story "Dry run of a board"`.
   A synthetic escalation (cardId `""`) is its headline alone:
   `‼ Escalated at Integrate`.
3. `stopDetail`, word-wrapped, visible when `report.detail` is a non-blank
   string: the detail verbatim, urgent for `escalated` and `dead`.
4. `stopHeartbeat`, visible when `report.state === "dead"` and `heartbeatAge`
   is not `""`: `Last heartbeat <heartbeatAge> ago`.
5. `stopNoteHeading`, visible when `note` is a non-null object: `am's note`,
   then ` · HH:mm` (`Qt.formatTime(new Date(note.createdAt), "hh:mm")`, local
   time) when `Date.parse(note.createdAt)` is finite.
6. One `stopNoteField<i>` per entry of `note.fields` (a non-array gives none),
   indented one step (`Style.space(12)`), word-wrapped: `<key>  <value>` (two
   spaces). Hidden with the heading.
7. `stopParked`, visible when `report.parked` is a non-empty array:
   `Parked: ` + each id as `#` + its first 8 characters, joined `, `.
8. A row of `UI.ActionButton`s: `stopOpenCard` (`Open card`, visible when
   `openCardId !== ""`, `enabled: openCardReason === ""`, `tooltipText:
   openCardReason`) and `stopRelaunch` (`Relaunch`, visible when
   `relaunchOffered`, `enabled: relaunchReason === ""`, `tooltipText:
   relaunchReason`). The row is hidden when neither button shows.
9. `stopActionReason`, caption, word-wrapped, visible when not `""`: the
   distinct non-empty reasons of the shown disabled buttons, Open card first,
   joined ` · ` (a disabled shell Button gets no hover, as
   `RunControls.qml:24-26` states, so the reason is written out).

A `null` or non-object `report` shows nothing and throws nothing; missing
fields of a report read as `""` / `[]`.

### `RunDetailScreen`

Mount `UI.StopReasonBlock { objectName: "runDetailStop"; width: parent.width;
theme: screen.theme; … }` directly after `runDetailMeta` and before
`runDetailControls`. `runDetailReason` is removed: the block's headline and
detail say the same and more. Read-only properties and helpers on the screen:

- `stopReport`: `Runs.stopReport(screen.run)`.
- `inOpenProject` (bool): `screen.app.runs.project` is not `""`, the run has
  an object `project` whose `root` is a non-empty string, and that root equals
  `Runs.withProject({}, screen.app.runs.project, "").project.root`.
  A run with no `project` is not in the open project.
- `stopNote` / `stopNoteCardId`: when `inOpenProject` and `screen.app.extras`
  exists: `Runs.stopComment(app.extras.commentsFor(report.cardId), run.id)`
  when `report.cardId` is not `""` and that is not null (card `report.cardId`);
  else `Runs.stopComment(app.extras.commentsFor(run.milestone_id), run.id)`
  when `run.milestone_id` is a non-empty string (card `run.milestone_id`);
  else null / `""`. Otherwise null / `""`. It re-reads when the extras store
  replaces its comments.
- The block's inputs:
  - `report: screen.stopReport`, `note: screen.stopNote`
  - `heartbeatAge`: `Runs.snapshotAgeText(Date.parse(report.heartbeatAt),
    screen.nowMs)` for a dead report, else `""`.
  - `openCardId`: `report.cardId` when not `""`, else `stopNoteCardId`.
  - `openCardReason`: `""` when `inOpenProject`, else
    `Open this run's project to open its card`.
  - `relaunchOffered`: `report.relaunch` is an object AND
    (`!Runs.controls(run).resume.enabled` OR
    (`app.runs.lastControlErrorRunId === run.id` AND
    `Runs.offersRelaunch({ type: app.runs.lastControlErrorType })`)).
  - `relaunchReason`: `""` when `inOpenProject`, else
    `Open this run's project to relaunch it`.
- `onOpenCardRequested(id)`: `screen.navigator.openCard(id)` when a navigator
  is set.
- `onRelaunchRequested`: `card = screen.cardOf(report.relaunch.cardId)`; with
  a card, `screen.app.runs.relaunchOpenFor(card, screen.app.board.cardMap,
  report.relaunch)` (Panel then shows the dispatch dialog; a finished card
  shows the dialog's refusal). Without one, nothing is opened and
  `screen.app.runs.flash("The card to relaunch is no longer on the board")`.

### Output heading

`runOutputHeading` reads `Output · <card_id> <phase>.<attempt>` for an
attempt above 0 (unchanged) and `Output · <card_id> <phase> (newest)` for
attempt `0`; `Output` with no selection.

## Errors and edge cases

| case | behaviour |
|---|---|
| running, done or unknown run | no block (`stopReport` null) |
| escalated milestone run, resume enabled, no refusal | block, no Relaunch (Resume is in the controls) |
| escalated `task` run | Relaunch shown and enabled (open project) |
| a resume refused with `NotResumableError` / `CheckpointMismatchError` for THIS run | Relaunch shown beside the controls' refusal line |
| that refusal is about another run, or of another type | no Relaunch |
| `report.relaunch` null (run names no target) | no Relaunch, whatever the controls say |
| run of another project | block shown; no note even when comments exist; Open card and Relaunch disabled; `stopActionReason` lists both reasons |
| no project open (`app.runs.project === ""`) | as another project |
| run carries no `project` | as another project |
| no am note on either card, or only another run's / a non-am author's | note hidden |
| note `createdAt` unparseable | heading `am's note` without time |
| parked / cancelled run, no note | no Open card (`openCardId` `""`) |
| synthetic escalation with a milestone `run-end` note | Open card opens the milestone card |
| relaunch target missing from `cardMap` | no dispatch; flash `The card to relaunch is no longer on the board` |
| relaunch target finished | the dispatch dialog's refusal (store, unchanged) |
| dead run with an unparseable or empty `heartbeat_at` | no heartbeat line |
| attempt 0 selected | heading `… <phase> (newest)` |
| `canceled` spelling | cancelled block (domain) |
| block `theme` / `report` / `note` set to null, destroyed | no error output |

## Tests

### New: `tests/ui/components/tst_stop_reason_block.qml`

Tier: QML component test (qmltestrunner via `tests/run.sh`). Why: the
contract is the block's rendered items and signals given props; no store is
involved. Modelled on `tst_run_controls.qml` / `tst_resume_verify_dialog.qml`:
`TestCase { when: windowShown; visible: true }`, `createTemporaryObject`,
`SignalSpy`, `H.find`, `wait(30)` before clicks. Reports are built with
`Runs.stopReport` over small normalised runs, or as literal objects where a
field must be pinned.

1. **escalated subtask**: headline `‼ Escalated at verify · #5bfe746d · story
   "Dry run of a board"` in urgent; detail shown in urgent; no heartbeat line.
2. **synthetic escalation**: cardId `""`, headline alone (`‼ Escalated at
   Integrate`), no `#`.
3. **parked**: `⏸ Paused at a phase boundary` in foreground; `stopParked`
   `Parked: #6c1e09aa, #9f02b7d1`; detail hidden.
4. **dead**: `✖ The run's process died · #… · story "…" · at implement`;
   `heartbeatAge: "5m"` → `Last heartbeat 5m ago`; `""` → hidden.
5. **cancelled**: `⊘` + the cancelled sentence; parked line when parked is
   non-empty, hidden when `[]`.
6. **no report**: `null` and a string → block not visible.
7. **note shown**: fields `reason`, `next` → heading `am's note · ` +
   `Qt.formatTime(new Date(createdAt), "hh:mm")`; `stopNoteField0` text
   `reason  tests do not cover the empty list`, `stopNoteField1`
   `next  am resume …`; bad `createdAt` → `am's note`.
8. **note hidden**: `note: null` → heading and fields not visible.
9. **Open card**: `openCardId: ""` → hidden; `"t1"` and no reason → enabled,
   click emits one `openCardRequested("t1")`; with a reason → disabled, a
   click emits nothing, `stopActionReason` shows the reason.
10. **Relaunch**: not offered → hidden; offered, no reason → enabled, click
    emits one `relaunchRequested`; offered with
    `Open this run's project to relaunch it` → disabled, no signal, the reason
    shown; both disabled with distinct reasons → joined ` · `, Open card's
    first; the same reason twice → once.
11. **null inputs are quiet**: set `theme`, `report`, `note` to null and
    destroy → no error output.

### Modified: `tests/ui/screens/tst_run_detail_screen.qml`

Tier: QML screen test. Why: the lookups that feed the block (open-project
rule, note card choice, relaunch condition, card map lookup, navigation) are
the screen's; a stub app makes each input controllable. Stub additions:
`runs.project` (`"/home/u/a"`), `runs.lastControlErrorType`, recorders
`runs.relaunchOpenFor(card, cardMap, relaunch)` (records the three, returns
true) and `runs.flash(text)`; `app.extras` with `commentsFor(id)` reading a
settable `{id: comments}` map; a `navigator` stub `QtObject` recording
`openCard(id)`; board `cardMap` gains a milestone card `M3`. Test runs get
`project: { root: "/home/u/a", name: "alpha" }` where they belong to the
open project.

Rewritten: `test_the_header_names_the_run_its_state_and_its_branches` checks
`runDetailStop` not visible for a running run (instead of
`runDetailReason`); `test_an_escalated_run_shows_its_reason_in_urgent` checks
the block's `stopDetail` text `tests red after 3 attempts` in urgent.

New:

12. **the block sits between the header and the controls**: escalated run →
    `runDetailStop` visible, its `y` below `runDetailMeta` and above
    `runDetailControls`.
13. **note from the escalated card**: comments on `t1` with an am note for
    this run → `stopNoteField0` shown; Open card enabled; click →
    navigator recorded `openCard("t1")`.
14. **note falls back to the milestone card**: no note on `t1`, a run-end
    note for this run on `M3` and another run's note on `t1` → the `M3` note.
15. **another project**: run root `/home/u/b` with notes present → note
    hidden, Open card and Relaunch (cancelled run) disabled, `stopActionReason`
    contains `Open this run's project to relaunch it`; same with
    `runs.project = ""` and with no `project` on the run.
16. **cancelled run relaunches its milestone**: cancelled run (milestone
    `M3`, prefix `m3`, base `master`) → Relaunch enabled; click →
    `relaunchOpenFor` got `cardMap.M3`, the board's `cardMap`, and
    `{level: "milestone", cardId: "M3", prefix: "m3", base: "master"}`.
17. **missing target**: milestone id not in `cardMap` → click calls no
    `relaunchOpenFor` and flashes `The card to relaunch is no longer on the
    board`.
18. **refusal-driven Relaunch**: escalated milestone run → no Relaunch; set
    `lastControlErrorType: "NotResumableError"`, `lastControlErrorRunId` the
    run → Relaunch shown; error run id another run → hidden;
    `RunIsLiveError` → hidden.
19. **escalated task run**: `workflow: "task"`, `card_id: "t1"` → Relaunch
    shown and enabled.
20. **dead heartbeat**: dead run with `lease.heartbeat_at` two minutes before
    now → `Last heartbeat 2m ago`.
21. **the heading for attempt 0**: selection `{t1, verify, 0}` → `Output · t1
    verify (newest)`; `{t1, implement, 2}` → `Output · t1 implement.2`.

### Modified: `tests/ui/tst_runs_flow.qml`

Tier: QML Panel-level flow test. Why: only the full Panel joins the screen,
the real `RunStore.relaunchOpenFor` / `openDispatch` and the mounted
`DispatchDialog`; the prefill is observable only there.

22. **cancelled run → Relaunch → dispatch dialog prefilled**: `make()`, then
    `p.app.backendDir = "/plugin/core/backend/"`, `p.app.runs.runSettings =
    { verify: ["uv run pytest"] }`, `p.app.board.applyTreeData([{ id: "m1",
    title: "M one", status: "todo", description: "d", children: [] }])`, and
    one run (`run()` shape, project `/home/u/a`) with `status: "cancelled"`,
    `milestone_id: "m1"`, `branch_prefix: "old-m1"`, `base_branch: "release"`.
    Open it (Ctrl+6, Return) → `runDetailStop` visible with the cancelled
    headline; `stopRelaunch` enabled; click → `dispatchState` `previewing`,
    `dispatchDialog` visible, `dispatchPrefix.text` `old-m1`,
    `dispatchBase.text` `release`; reply the defaults runner with
    `{"ok":true,"data":{"default_branch":"main"}}` → `dispatchBase.text`
    still `release`.

### Existing: `tests/architecture`, other UI tests

Tier: pytest guards / QML. Why: the new component must import no store,
copy no guarded pattern, add no unknown glyph; `tst_runs_real_data.qml` and
the flow's existing heading checks use attempts above 0 and stay unchanged.
Not edited.

## Plan hand-off notes

- Order: component tests → component; screen tests → screen; flow case.
  Run `bash tests/run.sh stop_reason_block`, `bash tests/run.sh
  run_detail_screen`, `bash tests/run.sh runs_flow`, then the full
  `bash tests/run.sh`.
- `tests/run.sh` takes one substring filter over QML test paths (its line 4).
- `screen.cardOf` already does the own-key-safe `cardMap` lookup; reuse it.
- `Runs.withProject` trims the open root the way runs are tagged; do not add
  a second `rootKey` to the screen.
- The block's header comment states its contract: what it shows, its props,
  its signals, its objectNames, that it never changes its inputs.
