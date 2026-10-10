<!-- The spec this plan implements, verbatim. The plan follows the rule below. -->

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

---

# 3.3 Run detail: Why it stopped and Relaunch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run detail explains why a stopped run stopped (headline, detail, heartbeat, am's note, parked cards) in a new presentation-only `StopReasonBlock`, with Open card and Relaunch buttons wired through `RunDetailScreen`, and the output heading says `(newest)` for attempt 0.

**Architecture:** `ui/components/StopReasonBlock.qml` renders what its owner hands it (`Runs.stopReport`, `Runs.stopComment`, button facts) and emits `openCardRequested(id)` / `relaunchRequested()`. `ui/screens/RunDetailScreen.qml` computes those inputs (open-project rule, note card choice, relaunch condition) from the run store, the extras store and the board, mounts the block between `runDetailMeta` and `runDetailControls` in place of `runDetailReason`, and turns the signals into `navigator.openCard` / `runs.relaunchOpenFor` / `runs.flash`. No `core/` change.

**Tech Stack:** QML (Qt 6, Quickshell shell `qs.Commons` / `qs.Ui`), plain JS libraries (`core/domain/runs.js`, `ui/components/runGlyphs.js`), qmltestrunner via `bash tests/run.sh <filter>`, pytest architecture guards.

**Spec:** `docs/superpowers/specs/3-3-run-detail-why-it-b7ef64db.md` (prepended above, verbatim).

## Global Constraints

- Components and screens never import `core/stores` (`tests/architecture/test_layers.py`, `violations_screen`).
- No local QML type shares a shell/Controls type name.
- Text is `UI.ThemedText`, buttons are `UI.ActionButton`; no `font.family:`, no `bordered: true`, no `radius: height/2` outside their GUARDS owners.
- Glyphs come from `ui/components/runGlyphs.js` only (`‼ ⏸ ✖ ⊘`), none private-use.
- Docstrings and comments state the contract only, no narrative.
- UI strings use `…`, never `...`.
- No change to `core/` (`runs.js`, `RunStore`, `ExtrasStore`, the backend), `docs/architecture.md` or README.
- The block declares no `resumeRequested` signal and has no Resume button.
- Verification: `bash tests/run.sh` green; it also fails on `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item` or `is not a function` in QML test output. TDD: tests first.
- Exact strings: `Why it stopped`, `Last heartbeat <age> ago`, `am's note`, `Parked: `, `Open card`, `Relaunch`, `Open this run's project to open its card`, `Open this run's project to relaunch it`, `The card to relaunch is no longer on the board`, `Output · <card> <phase> (newest)`.

## Review Focus

1. An open project root with a trailing `/` (`"/home/u/a/"`) against a run tagged `"/home/u/a"`: the run is still in the open project (note shown, buttons enabled). Pinned in Task 2, test 15.
2. A synthetic escalation (Integrate) whose only am note is the milestone's `run-end` note: Open card shows and opens the milestone card, not nothing. Pinned in Task 2, test 14.
3. A run's control refusal flips between this run and another run, or between `NotResumableError` and `CheckpointMismatchError` / `RunIsLiveError`: Relaunch follows live, without reopening the screen. Pinned in Task 2, test 18.
4. Clicking a disabled Open card or Relaunch (the shell Button may still deliver a click): nothing navigates, nothing dispatches. Pinned in Task 1, tests 9-10, and Task 2, test 15.
5. A note whose `fields` is not an array, or a parked list holding non-strings: the block renders without errors and shows no bogus lines. Pinned in Task 1, tests 7 and 3.

---

## Execution notes

- Arrays handed to a component through `createObject`'s property map arrive as QML lists, for which `Array.isArray` is false (see `ui/components/RunToast.qml:28-31`). The block therefore tests lists with `isList` (an object with a numeric `length`), never `Array.isArray`.
- `tests/run.sh` hides the pre-existing `Cannot read property 'width' of null` warnings from Board/CardDetail screens; they are not this card's.

## File Structure

- Create `ui/components/StopReasonBlock.qml` — the presentation-only block (one responsibility: render a stop report, a note and two buttons).
- Create `tests/ui/components/tst_stop_reason_block.qml` — its component tests.
- Modify `ui/screens/RunDetailScreen.qml` — mount the block in place of `runDetailReason` (lines 207-216), add the lookup properties/functions, change `runOutputHeading`'s text (lines 260-262).
- Modify `tests/ui/screens/tst_run_detail_screen.qml` — stub additions, two rewritten tests, tests 12-21.
- Modify `tests/ui/tst_runs_flow.qml` — test 22.

---

### Task 1: `StopReasonBlock` component

**Files:**
- Create: `ui/components/StopReasonBlock.qml`
- Test: `tests/ui/components/tst_stop_reason_block.qml`

**Interfaces:**
- Consumes: `Runs.stopReport(run)` → null or `{state, headline, cardId, storyId, storyTitle, phase, detail, heartbeatAt, attempt, parked, relaunch}` (tests only); `RunGlyphs.glyphOf(state)` → string.
- Produces: QML type `UI.StopReasonBlock` (`import "../components" as UI`), a `Column` with default `objectName: "stopReasonBlock"`, properties `theme: var`, `report: var`, `note: var`, `heartbeatAge: string`, `openCardId: string`, `openCardReason: string`, `relaunchOffered: bool`, `relaunchReason: string`; signals `openCardRequested(string id)`, `relaunchRequested()`; child objectNames `stopTitle`, `stopHeadline`, `stopDetail`, `stopHeartbeat`, `stopNoteHeading`, `stopNoteField<i>`, `stopParked`, `stopActions`, `stopOpenCard`, `stopRelaunch`, `stopActionReason`.

- [ ] **Step 1: Write the failing test file**

Create `tests/ui/components/tst_stop_reason_block.qml`:

```qml
// tests/ui/components/tst_stop_reason_block.qml
// ui/components/StopReasonBlock.qml on its own: the rendered lines for each
// stopped state, am's note, the parked cards, and the Open card / Relaunch
// buttons with their signals and written-out reasons.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components/runGlyphs.js" as RG
import "../../../core/domain/runs.js" as Runs
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "StopReasonBlock"
  when: windowShown
  visible: true
  width: 520; height: 700

  Component { id: blockC; UI.StopReasonBlock { width: 480 } }
  SignalSpy { id: opens; signalName: "openCardRequested" }
  SignalSpy { id: relaunches; signalName: "relaunchRequested" }

  readonly property string card: "5bfe746d-8ac3-41c4-8e3e-abb939e0b45a"
  readonly property string noteAt: "2026-10-04T17:45:00Z"

  // A block with `over` as its props; the spies follow it.
  function make(over) {
    var b = createTemporaryObject(blockC, tc, over || {})
    opens.target = b; relaunches.target = b
    opens.clear(); relaunches.clear()
    wait(30)
    return b
  }
  // A freshly laid-out item is placed on the next frame: wait, so the click
  // lands on the item and not where it was.
  function click(item) { wait(30); mouseClick(item, item.width / 2, item.height / 2) }
  function part(b, name) { return H.find(b, name) }

  // Pinned literal reports: the fields the block reads, every one given.
  function escalatedReport() {
    return { state: "escalated", headline: "Escalated at verify", cardId: tc.card, storyId: "s1",
             storyTitle: "Dry run of a board", phase: "verify", detail: "VerifyError: could not run none",
             heartbeatAt: "", attempt: { card_id: tc.card, phase: "verify", attempt: 0 }, parked: [], relaunch: null }
  }
  function syntheticReport() {
    return { state: "escalated", headline: "Escalated at Integrate", cardId: "", storyId: "integrate",
             storyTitle: "Integrate", phase: "integrate", detail: "", heartbeatAt: "", attempt: null, parked: [],
             relaunch: null }
  }
  function deadReport() {
    return { state: "dead", headline: "The run's process died", cardId: "7d2c0e11-0000-4000-8000-000000000001",
             storyId: "s1", storyTitle: "Runs screens", phase: "implement", detail: "",
             heartbeatAt: "2026-10-04T17:40:00Z", attempt: null, parked: [], relaunch: null }
  }
  // A normalised run whose subtasks are `stopped` (parked) cards, in `status`.
  function stoppedRun(status, parkedIds) {
    var subtasks = []
    for (var i = 0; i < parkedIds.length; i++) subtasks.push({ card_id: parkedIds[i], status: "stopped", phases: [] })
    return { id: "run-x-stop0001", status: status, milestone_id: "M3", lease: null, rows: [],
             tree: { stories: [], subtasks: subtasks } }
  }
  function note(createdAt, fields) { return { createdAt: createdAt, kind: "escalated", fields: fields } }

  // 1
  function test_an_escalated_subtask_names_its_card_story_and_detail_in_urgent() {
    var b = make({ report: escalatedReport(), heartbeatAge: "5m" })
    compare(b.visible, true)
    compare(b.objectName, "stopReasonBlock")
    compare(part(b, "stopTitle").text, "Why it stopped")
    compare(part(b, "stopTitle").font.bold, true)
    var head = part(b, "stopHeadline")
    compare(head.text, "‼ Escalated at verify · #5bfe746d · story \"Dry run of a board\"")
    compare(head.wrapMode, Text.WordWrap)
    verify(Qt.colorEqual(head.color, b.theme.urgent), "escalated is urgent")
    var detail = part(b, "stopDetail")
    compare(detail.visible, true)
    compare(detail.text, "VerifyError: could not run none")
    compare(detail.wrapMode, Text.WordWrap)
    verify(Qt.colorEqual(detail.color, b.theme.urgent))
    compare(part(b, "stopHeartbeat").visible, false, "only a dead run has a heartbeat line")
    compare(part(b, "stopParked").visible, false)
  }

  // 2
  function test_a_synthetic_escalation_is_its_headline_alone() {
    var b = make({ report: syntheticReport() })
    compare(part(b, "stopHeadline").text, "‼ Escalated at Integrate")
    compare(part(b, "stopHeadline").text.indexOf("#"), -1)
    compare(part(b, "stopDetail").visible, false, "no detail")
  }

  // 3
  function test_a_parked_run_lists_its_parked_cards_in_foreground() {
    var report = Runs.stopReport(stoppedRun("stopped", ["6c1e09aa-1111-4000-8000-000000000001",
                                                        "9f02b7d1-2222-4000-8000-000000000002"]))
    var b = make({ report: report })
    var head = part(b, "stopHeadline")
    compare(head.text, RG.glyphOf("parked") + " Paused at a phase boundary")
    verify(Qt.colorEqual(head.color, b.theme.foreground), "parked is not urgent")
    compare(part(b, "stopParked").visible, true)
    compare(part(b, "stopParked").text, "Parked: #6c1e09aa, #9f02b7d1")
    compare(part(b, "stopDetail").visible, false)
    var odd = Runs.stopReport(stoppedRun("stopped", []))
    odd.parked = [5, null, "", "abc"]
    b.report = odd
    compare(part(b, "stopParked").text, "Parked: #abc", "only non-empty string ids are listed")
  }

  // 4
  function test_a_dead_run_names_its_phase_and_last_heartbeat() {
    var b = make({ report: deadReport(), heartbeatAge: "5m" })
    var head = part(b, "stopHeadline")
    compare(head.text, "✖ The run's process died · #7d2c0e11 · story \"Runs screens\" · at implement")
    verify(Qt.colorEqual(head.color, b.theme.urgent), "dead is urgent")
    compare(part(b, "stopHeartbeat").visible, true)
    compare(part(b, "stopHeartbeat").text, "Last heartbeat 5m ago")
    b.heartbeatAge = ""
    compare(part(b, "stopHeartbeat").visible, false)
  }

  // 5
  function test_a_cancelled_run_says_so_and_lists_what_it_parked() {
    var report = Runs.stopReport(stoppedRun("cancelled", ["6c1e09aa-1111-4000-8000-000000000001"]))
    var b = make({ report: report })
    compare(part(b, "stopHeadline").text, RG.glyphOf("cancelled") + " " + report.headline)
    verify(Qt.colorEqual(part(b, "stopHeadline").color, b.theme.foreground))
    compare(part(b, "stopParked").text, "Parked: #6c1e09aa")
    b.report = Runs.stopReport(stoppedRun("canceled", []))
    compare(part(b, "stopHeadline").text, RG.glyphOf("cancelled") + " " + report.headline, "canceled too")
    compare(part(b, "stopParked").visible, false)
  }

  // 6
  function test_no_report_shows_nothing() {
    var b = make({ report: null })
    compare(b.visible, false)
    b.report = "escalated"
    compare(b.visible, false)
    b.report = { state: "escalated" }
    compare(b.visible, true, "missing fields read as empty")
    compare(part(b, "stopHeadline").text, "‼ ")
  }

  // 7
  function test_ams_note_shows_its_time_and_fields() {
    var b = make({ report: escalatedReport(), note: note(tc.noteAt, [
      { key: "reason", value: "tests do not cover the empty list" },
      { key: "next", value: "am resume 20261004T165007Z-4a51d663" }]) })
    var heading = part(b, "stopNoteHeading")
    compare(heading.visible, true)
    compare(heading.text, "am's note · " + Qt.formatTime(new Date(tc.noteAt), "hh:mm"))
    var f0 = part(b, "stopNoteField0")
    compare(f0.text, "reason  tests do not cover the empty list")
    compare(f0.x, 12, "indented one step")
    compare(f0.wrapMode, Text.WordWrap)
    compare(part(b, "stopNoteField1").text, "next  am resume 20261004T165007Z-4a51d663")
    compare(part(b, "stopNoteField2"), null)
    b.note = note("yesterday", [])
    compare(heading.text, "am's note", "an unparseable time is left out")
    b.note = { createdAt: tc.noteAt, kind: "escalated", fields: "x" }
    compare(heading.visible, true)
    compare(part(b, "stopNoteField0"), null, "non-array fields give no lines")
  }

  // 8
  function test_no_note_hides_the_heading_and_fields() {
    var b = make({ report: escalatedReport(), note: null })
    compare(part(b, "stopNoteHeading").visible, false)
    compare(part(b, "stopNoteField0"), null)
  }

  // 9
  function test_open_card_emits_its_id_only_while_enabled() {
    var b = make({ report: escalatedReport(), openCardId: "" })
    compare(part(b, "stopOpenCard").visible, false)
    compare(part(b, "stopActions").visible, false, "no button, no row")
    b.openCardId = "t1"
    var open = part(b, "stopOpenCard")
    compare(open.visible, true)
    compare(open.text, "Open card")
    compare(open.enabled, true)
    compare(part(b, "stopActionReason").visible, false)
    click(open)
    compare(opens.count, 1)
    compare(opens.signalArguments[0][0], "t1")
    b.openCardReason = "Open this run's project to open its card"
    compare(open.enabled, false)
    compare(open.tooltipText, "Open this run's project to open its card")
    click(open)
    compare(opens.count, 1, "a disabled Open card emits nothing")
    compare(part(b, "stopActionReason").visible, true)
    compare(part(b, "stopActionReason").text, "Open this run's project to open its card")
  }

  // 10
  function test_relaunch_emits_only_while_enabled_and_reasons_are_written_out() {
    var b = make({ report: escalatedReport(), relaunchOffered: false })
    compare(part(b, "stopRelaunch").visible, false)
    b.relaunchOffered = true
    var relaunch = part(b, "stopRelaunch")
    compare(relaunch.visible, true)
    compare(relaunch.text, "Relaunch")
    compare(relaunch.enabled, true)
    click(relaunch)
    compare(relaunches.count, 1)
    b.relaunchReason = "Open this run's project to relaunch it"
    compare(relaunch.enabled, false)
    click(relaunch)
    compare(relaunches.count, 1, "a disabled Relaunch emits nothing")
    compare(part(b, "stopActionReason").text, "Open this run's project to relaunch it")
    b.openCardId = "t1"
    b.openCardReason = "A"
    b.relaunchReason = "B"
    compare(part(b, "stopActionReason").text, "A · B", "Open card's reason first")
    b.relaunchReason = "A"
    compare(part(b, "stopActionReason").text, "A", "the same reason once")
    b.relaunchOffered = false
    b.relaunchReason = "B"
    compare(part(b, "stopActionReason").text, "A", "a hidden button's reason is not written")
  }

  // 11
  function test_null_inputs_are_quiet() {
    var b = make({ report: deadReport(), heartbeatAge: "5m", openCardId: "t1", relaunchOffered: true,
                   note: note(tc.noteAt, [{ key: "reason", value: "r" }]) })
    b.theme = null
    wait(20)
    compare(part(b, "stopHeadline").text.indexOf("The run's process died") >= 0, true)
    b.report = null
    b.note = null
    wait(20)
    compare(b.visible, false)
    b.destroy()
    wait(20)
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/run.sh stop_reason_block`
Expected: FAIL — qmltestrunner reports `StopReasonBlock is not a type` (the component does not exist yet).

- [ ] **Step 3: Write the component**

Create `ui/components/StopReasonBlock.qml`:

```qml
import QtQuick
import qs.Commons
import "runGlyphs.js" as RunGlyphs
import "../components" as UI
import "../theme" as T

// Why a stopped run stopped, for Run detail, top to bottom: "Why it stopped";
// the headline (the state's glyph, Runs.stopReport's headline, the card as
// "#<first 8>" with its story's title, and a dead run's phase), urgent for
// escalated and dead; the detail; a dead run's "Last heartbeat <age> ago"; am's
// note (a heading with its local time, then one indented "<key>  <value>" line
// per field); the parked cards; the Open card and Relaunch buttons; and the
// reasons of the shown disabled buttons, written out because a disabled shell
// Button gets no hover.
//
// Presentation only: it imports no store and never changes its inputs. The
// owner passes `report` (Runs.stopReport), `note` (Runs.stopComment),
// `heartbeatAge`, the card Open card opens with why it is disabled, and
// whether Relaunch shows with why it is disabled. A click on an enabled button
// emits openCardRequested(openCardId) or relaunchRequested(). Visible exactly
// when `report` is an object; a missing field of it reads as "" or [].
//
// objectNames: stopTitle, stopHeadline, stopDetail, stopHeartbeat,
// stopNoteHeading, stopNoteField<i>, stopParked, stopActions, stopOpenCard,
// stopRelaunch, stopActionReason.
Column {
  id: block
  objectName: "stopReasonBlock"

  property var theme: T.Theme {}
  // Runs.stopReport(run), or null.
  property var report: null
  // Runs.stopComment(…), or null.
  property var note: null
  // A dead run's last heartbeat age without "ago" ("5m"); "" for none.
  property string heartbeatAge: ""
  // The card Open card opens; "" hides the button.
  property string openCardId: ""
  // Why Open card is disabled; "" when it is enabled.
  property string openCardReason: ""
  property bool relaunchOffered: false
  // Why Relaunch is disabled; "" when it is enabled.
  property string relaunchReason: ""

  signal openCardRequested(string id)
  signal relaunchRequested()

  readonly property bool hasReport: block.isObject(block.report)
  readonly property string stopState: block.hasReport ? block.textOf(block.report.state) : ""
  readonly property bool urgent: block.stopState === "escalated" || block.stopState === "dead"
  readonly property string detailText: block.hasReport ? block.textOf(block.report.detail) : ""
  readonly property bool hasNote: block.isObject(block.note)
  readonly property var noteFields: block.hasNote && block.isList(block.note.fields) ? block.note.fields : []
  readonly property string parkedText: block.parkedLine(block.hasReport ? block.report.parked : null)
  readonly property bool openShown: block.openCardId !== ""
  // The distinct non-empty reasons of the shown disabled buttons, Open card first.
  readonly property string actionReason: {
    var out = []
    if (block.openShown && block.openCardReason !== "") out.push(block.openCardReason)
    if (block.relaunchOffered && block.relaunchReason !== "" && out.indexOf(block.relaunchReason) < 0)
      out.push(block.relaunchReason)
    return out.join(" · ")
  }

  visible: block.hasReport
  spacing: Style.space(2)

  function isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }
  function textOf(v) { return typeof v === "string" ? v : "" }
  // Not Array.isArray: a list handed in through createObject's property map
  // arrives as a QML list, for which Array.isArray is false although length
  // and indexing work.
  function isList(v) { return v !== null && typeof v === "object" && typeof v.length === "number" }
  function shortCard(id) { return "#" + id.substring(0, 8) }

  // "<glyph> <headline> · #<card> · story "<title>" · at <phase>", each part
  // only when it has something; the phase for a dead run only.
  function headlineOf(r) {
    if (!block.isObject(r)) return ""
    var glyph = RunGlyphs.glyphOf(r.state)
    var line = (glyph !== "" ? glyph + " " : "") + block.textOf(r.headline)
    var cardId = block.textOf(r.cardId)
    if (cardId !== "") {
      line += " · " + block.shortCard(cardId)
      var story = block.textOf(r.storyTitle)
      if (story !== "") line += " · story \"" + story + "\""
    }
    var phase = block.textOf(r.phase)
    if (r.state === "dead" && phase !== "") line += " · at " + phase
    return line
  }

  // "am's note", with " · HH:mm" (local) when createdAt parses.
  function noteHeadingOf(n) {
    var at = block.isObject(n) ? block.textOf(n.createdAt) : ""
    return isFinite(Date.parse(at)) ? "am's note · " + Qt.formatTime(new Date(at), "hh:mm") : "am's note"
  }

  function fieldText(f) { return block.isObject(f) ? block.textOf(f.key) + "  " + block.textOf(f.value) : "" }

  // "Parked: #<first 8>, …" over the non-empty string ids; "" when none.
  function parkedLine(ids) {
    if (!block.isList(ids)) return ""
    var out = []
    for (var i = 0; i < ids.length; i++) {
      if (typeof ids[i] === "string" && ids[i] !== "") out.push(block.shortCard(ids[i]))
    }
    return out.length > 0 ? "Parked: " + out.join(", ") : ""
  }

  function colorOf(isUrgent) {
    if (!block.theme) return isUrgent ? Color.urgent : Color.foreground
    return isUrgent ? block.theme.urgent : block.theme.foreground
  }

  UI.ThemedText {
    objectName: "stopTitle"
    theme: block.theme
    text: "Why it stopped"
    font.bold: true
  }

  UI.ThemedText {
    objectName: "stopHeadline"
    theme: block.theme
    width: parent.width
    text: block.headlineOf(block.report)
    color: block.colorOf(block.urgent)
    wrapMode: Text.WordWrap
  }

  UI.ThemedText {
    objectName: "stopDetail"
    variant: "small"
    theme: block.theme
    width: parent.width
    visible: block.detailText.trim() !== ""
    text: block.detailText
    color: block.colorOf(block.urgent)
    wrapMode: Text.WordWrap
  }

  UI.ThemedText {
    objectName: "stopHeartbeat"
    variant: "caption"
    theme: block.theme
    visible: block.stopState === "dead" && block.heartbeatAge !== ""
    text: "Last heartbeat " + block.heartbeatAge + " ago"
  }

  UI.ThemedText {
    objectName: "stopNoteHeading"
    variant: "caption"
    theme: block.theme
    visible: block.hasNote
    text: block.noteHeadingOf(block.note)
  }

  Repeater {
    model: block.noteFields.length
    delegate: UI.ThemedText {
      required property int index
      objectName: "stopNoteField" + index
      variant: "small"
      theme: block.theme
      x: Style.space(12)
      width: block.width - Style.space(12)
      text: block.fieldText(block.noteFields[index])
      wrapMode: Text.WordWrap
    }
  }

  UI.ThemedText {
    objectName: "stopParked"
    variant: "small"
    theme: block.theme
    width: parent.width
    visible: block.parkedText !== ""
    text: block.parkedText
    wrapMode: Text.WordWrap
  }

  Row {
    objectName: "stopActions"
    visible: block.openShown || block.relaunchOffered
    spacing: Style.space(6)

    UI.ActionButton {
      id: openButton
      objectName: "stopOpenCard"
      theme: block.theme
      visible: block.openShown
      text: "Open card"
      enabled: block.openCardReason === ""
      tooltipText: block.openCardReason
      onClicked: if (openButton.enabled) block.openCardRequested(block.openCardId)
    }

    UI.ActionButton {
      id: relaunchButton
      objectName: "stopRelaunch"
      theme: block.theme
      visible: block.relaunchOffered
      text: "Relaunch"
      enabled: block.relaunchReason === ""
      tooltipText: block.relaunchReason
      onClicked: if (relaunchButton.enabled) block.relaunchRequested()
    }
  }

  UI.ThemedText {
    objectName: "stopActionReason"
    variant: "caption"
    theme: block.theme
    width: parent.width
    visible: block.actionReason !== ""
    text: block.actionReason
    wrapMode: Text.WordWrap
  }
}
```

- [ ] **Step 4: Run the component test to verify it passes**

Run: `bash tests/run.sh stop_reason_block`
Expected: PASS — `Totals: N passed, 0 failed`, no `TypeError` / `ReferenceError` lines, exit 0. (The pytest suite also runs first and must pass, including `tests/architecture`.)

- [ ] **Step 5: Commit**

```bash
git add ui/components/StopReasonBlock.qml tests/ui/components/tst_stop_reason_block.qml
git commit -m "feat(ui): StopReasonBlock says why a run stopped, with Open card and Relaunch"
```

---

### Task 2: `RunDetailScreen` mounts the block, feeds it, and labels attempt 0 `(newest)`

**Files:**
- Modify: `ui/screens/RunDetailScreen.qml` (header comment lines 10-18; properties after line 38; functions after `requestControl`, line 159; replace `runDetailReason`, lines 207-216; `runOutputHeading` text, lines 260-262)
- Test: `tests/ui/screens/tst_run_detail_screen.qml`

**Interfaces:**
- Consumes: `UI.StopReasonBlock` and its props/signals from Task 1; `Runs.stopReport(run)`, `Runs.stopComment(comments, runId)`, `Runs.controls(run).resume.enabled`, `Runs.offersRelaunch({type})`, `Runs.withProject({}, root, "").project.root`, `Runs.snapshotAgeText(fetchedMs, nowMs)`; `app.runs.project`, `app.runs.lastControlErrorRunId`, `app.runs.lastControlErrorType`, `app.runs.relaunchOpenFor(card, cardMap, relaunch)`, `app.runs.flash(text)`; `app.extras.commentsFor(id)`; `navigator.openCard(id)`; existing `screen.cardOf(id)`.
- Produces: on the screen, `readonly property var stopReport`, `readonly property bool inOpenProject`, `readonly property var stopNote`, `readonly property string stopNoteCardId`; functions `belongsTo(run, openRoot) → bool`, `noteOf(run, report, inProject) → {note, cardId}`, `heartbeatAgeOf(report) → string`, `offersRelaunch(run, report) → bool`, `relaunch()`; child `objectName: "runDetailStop"`. `runDetailReason` no longer exists.

- [ ] **Step 1: Extend the test stubs and helpers**

In `tests/ui/screens/tst_run_detail_screen.qml`:

1a. Replace the header comment (lines 1-6) with:

```qml
// tests/ui/screens/tst_run_detail_screen.qml
// ui/screens/RunDetailScreen.qml on its own: the header, the Why it stopped
// block and what feeds it, the story > subtask > attempt tree with its
// bookkeeping rows, the output pane and the missing-run line. A stub app: a
// REAL NavigationStore, a plain object carrying the RunStore properties the
// screen reads (with recorders for selectAttempt, refreshLogs, control,
// relaunchOpenFor and flash), an extras stub whose commentsFor reads a
// settable map, a board whose cardMap lends titles and brd statuses, and a
// navigator stub recording openCard.
```

1b. In the `runsC` QtObject, after `function control(action, id) { … }` (before the closing `}` of the QtObject), add:

```qml
      // The open project's root (RunStore.project); "" when none is open.
      property string project: "/home/u/a"
      property string lastControlErrorType: ""
      // relaunchOpenFor and flash only record.
      property var relaunchCalls: []
      function relaunchOpenFor(card, cardMap, relaunch) {
        rs.relaunchCalls = rs.relaunchCalls.concat([{ card: card, cardMap: cardMap, relaunch: relaunch }])
        return true
      }
      property var flashes: []
      function flash(text) {
        rs.flashes = rs.flashes.concat([text])
        rs.flashText = text
      }
```

1c. After the `runsC` Component, add two stub components:

```qml
  Component {
    id: extrasC
    QtObject {
      id: ex
      // {cardId: comments}, as ExtrasStore.commentsByEntity: replaced, never edited.
      property var comments: ({})
      function commentsFor(id) {
        return Object.prototype.hasOwnProperty.call(ex.comments, id) ? ex.comments[id] : []
      }
    }
  }

  Component {
    id: naviC
    QtObject {
      id: nv
      property var opened: []
      function openCard(id) { nv.opened = nv.opened.concat([id]) }
    }
  }
```

1d. In `appC`, add `property var extras: null` after `property var runs: null`, and add the milestone card to `cardMap` after the `t3` entry:

```qml
        t3: { id: "t3", title: "Shelved", status: "archived" },
        M3: { id: "M3", title: "Milestone three", status: "in_progress" }
```

(the `t3` line gains a trailing comma).

1e. Replace `make` with:

```qml
  function make(list, selectedId, attempt) {
    var host = createTemporaryObject(hostC, tc)
    var navComp = Qt.createComponent("../../../core/stores/NavigationStore.qml")
    if (navComp.status !== Component.Ready) { fail(navComp.errorString()); return null }
    var nav = navComp.createObject(host)
    var runs = runsC.createObject(host)
    var extras = extrasC.createObject(host)
    var app = appC.createObject(host, { nav: nav, runs: runs, extras: extras })
    var navi = naviC.createObject(host)
    var sC = Qt.createComponent("../../../ui/screens/RunDetailScreen.qml")
    if (sC.status !== Component.Ready) { fail(sC.errorString()); return null }
    var screen = sC.createObject(host, { width: 500, app: app, navigator: navi })
    nav.viewMode = "run"
    runs.runs = list || []
    runs.selectedRunId = selectedId === undefined ? "run-20261004-19efcddc" : selectedId
    runs.selectedAttempt = attempt === undefined ? null : attempt
    wait(20)
    return { app: app, runs: runs, nav: nav, screen: screen, extras: extras, navi: navi }
  }
```

1f. Replace `run` with:

```qml
  // A normalised run, as RunStore holds them. live === null means no lease.
  // It belongs to the open project unless opts.project says otherwise (null:
  // no project at all); opts.workflow and opts.card set workflow and card_id.
  function run(id, status, live, opts) {
    var o = opts || {}
    var r = { id: id, repo_dir: "/home/u/a", milestone_id: o.milestone === undefined ? "M3" : o.milestone,
              base_branch: o.base === undefined ? "master" : o.base,
              branch_prefix: o.prefix === undefined ? "m3" : o.prefix,
              status: status, started_at: "",
              lease: live === null ? null : { pid: 4121, host: "h", heartbeat_at: "", accepting: true, live: live },
              rows: o.rows || [], tree: o.tree || { stories: [], subtasks: [] } }
    if (o.project !== null) r.project = o.project === undefined ? { root: "/home/u/a", name: "alpha" } : o.project
    if (o.workflow !== undefined) r.workflow = o.workflow
    if (o.card !== undefined) r.card_id = o.card
    return r
  }
```

1g. After `function sel(card, phase, n) { … }`, add:

```qml
  // The escalated run of the reason test: t1's review failed.
  function failedTree() {
    return { stories: [], subtasks: [{ card_id: "t1", phases: [
      { name: "review", status: "failed", detail: "tests red after 3 attempts" }] }] }
  }
  function escalatedRun(opts) {
    return run("run-x-escl0002", "escalated", null, Object.assign({ tree: failedTree() }, opts || {}))
  }
  // One am note on cardId for runId, as ExtrasStore.commentsFor gives it.
  function amNote(runId, cardId, kind, fieldLines, createdAt) {
    var body = ["am · " + kind + " · run " + runId].concat(fieldLines)
      .concat(["am-key: " + runId + "/" + cardId + "/" + kind + ":0a1b2c3d"]).join("\n")
    return { id: "c-" + createdAt, entityId: cardId, author: "am", body: body, createdAt: createdAt }
  }
  function stop(s) { return H.find(s.screen, "runDetailStop") }
  function part(s, name) { return H.find(stop(s), name) }
```

- [ ] **Step 2: Rewrite the two tests that read `runDetailReason`**

Replace the last line of `test_the_header_names_the_run_its_state_and_its_branches`:

```qml
    compare(H.find(s.screen, "runDetailReason").visible, false, "only an escalated run has a reason")
```

with:

```qml
    compare(H.find(s.screen, "runDetailReason"), null, "the block replaced the reason line")
    compare(stop(s).visible, false, "a running run has no Why it stopped")
```

Replace the whole of `test_an_escalated_run_shows_its_reason_in_urgent` with:

```qml
  function test_an_escalated_run_shows_its_reason_in_urgent() {
    var s = make([escalatedRun()], "run-x-escl0002"); if (!s) return
    compare(H.find(s.screen, "runDetailState").text, RG.glyphOf("escalated") + " escalated")
    verify(Qt.colorEqual(H.find(s.screen, "runDetailState").color, s.screen.theme.urgent))
    compare(stop(s).visible, true)
    compare(part(s, "stopHeadline").text, RG.glyphOf("escalated") + " Escalated at review · #t1")
    var reason = part(s, "stopDetail")
    compare(reason.visible, true)
    compare(reason.text, "tests red after 3 attempts")
    verify(Qt.colorEqual(reason.color, s.screen.theme.urgent))
  }
```

- [ ] **Step 3: Add the new screen tests (12-21)**

Insert this section before `// ---- tree`:

```qml
  // ---- why it stopped (RR 3.3)

  // 12
  function test_the_block_sits_between_the_header_and_the_controls() {
    var s = make([escalatedRun()], "run-x-escl0002"); if (!s) return
    var block = stop(s)
    compare(block.visible, true)
    verify(block.y > H.find(s.screen, "runDetailMeta").y, "below the meta line")
    verify(block.y < H.find(s.screen, "runDetailControls").y, "above the controls")
  }

  // 13
  function test_ams_note_comes_from_the_escalated_card_and_open_card_opens_it() {
    var s = make([escalatedRun()], "run-x-escl0002"); if (!s) return
    compare(part(s, "stopNoteHeading").visible, false, "no comments yet")
    s.extras.comments = { t1: [amNote("run-x-escl0002", "t1", "escalated",
                                      ["reason: tests do not cover the empty list"], "2026-10-04T17:45:00Z")] }
    compare(part(s, "stopNoteHeading").visible, true, "re-read when the comments are replaced")
    compare(part(s, "stopNoteField0").text, "reason  tests do not cover the empty list")
    compare(s.screen.stopNoteCardId, "t1")
    var open = part(s, "stopOpenCard")
    compare(open.visible, true)
    compare(open.enabled, true)
    tap(open)
    compare(s.navi.opened.join(","), "t1")
  }

  // 14
  function test_the_note_falls_back_to_the_milestone_card() {
    var s = make([escalatedRun()], "run-x-escl0002"); if (!s) return
    s.extras.comments = {
      t1: [amNote("run-x-other0009", "t1", "escalated", ["reason: someone else"], "2026-10-04T17:40:00Z")],
      M3: [amNote("run-x-escl0002", "M3", "run-end", ["next: am resume run-x-escl0002"], "2026-10-04T17:46:00Z")] }
    compare(part(s, "stopNoteField0").text, "next  am resume run-x-escl0002")
    compare(s.screen.stopNoteCardId, "M3")
    compare(H.find(s.screen, "runDetailStop").openCardId, "t1", "the escalated card is still the one to open")
    // Review Focus 2: a synthetic escalation opens the milestone card of its run-end note.
    s.runs.runs = [run("run-x-escl0002", "escalated", null,
                       { rows: [{ card_id: "integrate", phase: "integrate", status: "failed" }] })]
    compare(part(s, "stopHeadline").text, RG.glyphOf("escalated") + " Escalated at Integrate")
    compare(H.find(s.screen, "runDetailStop").openCardId, "M3")
    tap(part(s, "stopOpenCard"))
    compare(s.navi.opened.join(","), "M3")
  }

  // 15
  function test_a_run_of_another_project_shows_no_note_and_disables_its_buttons() {
    var other = { root: "/home/u/b", name: "beta" }
    var s = make([escalatedRun({ workflow: "task", card: "t1", project: other })], "run-x-escl0002"); if (!s) return
    s.extras.comments = {
      t1: [amNote("run-x-escl0002", "t1", "escalated", ["reason: tests red"], "2026-10-04T17:45:00Z")],
      M3: [amNote("run-x-escl0002", "M3", "run-end", ["next: relaunch"], "2026-10-04T17:46:00Z")] }
    var both = "Open this run's project to open its card · Open this run's project to relaunch it"
    compare(stop(s).visible, true)
    compare(part(s, "stopNoteHeading").visible, false, "no note from another project")
    compare(part(s, "stopOpenCard").visible, true)
    compare(part(s, "stopOpenCard").enabled, false)
    compare(part(s, "stopRelaunch").visible, true)
    compare(part(s, "stopRelaunch").enabled, false)
    compare(part(s, "stopActionReason").text, both)
    tap(part(s, "stopRelaunch"))
    tap(part(s, "stopOpenCard"))
    compare(s.runs.relaunchCalls.length, 0, "a disabled Relaunch dispatches nothing")
    compare(s.navi.opened.length, 0, "a disabled Open card navigates nowhere")

    s.runs.runs = [escalatedRun({ workflow: "task", card: "t1" })]
    compare(part(s, "stopNoteHeading").visible, true, "the open project's run shows its note")
    compare(part(s, "stopActionReason").visible, false)
    s.runs.project = ""
    compare(part(s, "stopNoteHeading").visible, false, "no project open")
    compare(part(s, "stopActionReason").text, both)
    // Review Focus 1.
    s.runs.project = "/home/u/a/"
    compare(part(s, "stopNoteHeading").visible, true, "the open root is compared without its trailing /")
    compare(part(s, "stopActionReason").visible, false)
    s.runs.runs = [escalatedRun({ workflow: "task", card: "t1", project: null })]
    compare(part(s, "stopNoteHeading").visible, false, "a run with no project")
    compare(part(s, "stopActionReason").text, both)
    s.runs.runs = [run("run-x-escl0002", "cancelled", null, { project: other })]
    compare(part(s, "stopOpenCard").visible, false, "a cancelled run names no card")
    compare(part(s, "stopRelaunch").enabled, false)
    compare(part(s, "stopActionReason").text, "Open this run's project to relaunch it")
  }

  // 16
  function test_a_cancelled_run_relaunches_its_milestone() {
    var s = make([run("run-x-canc0004", "cancelled", null, {})], "run-x-canc0004"); if (!s) return
    compare(part(s, "stopOpenCard").visible, false, "a cancelled run with no note names no card")
    var relaunch = part(s, "stopRelaunch")
    compare(relaunch.visible, true)
    compare(relaunch.enabled, true)
    tap(relaunch)
    compare(s.runs.relaunchCalls.length, 1)
    var call = s.runs.relaunchCalls[0]
    verify(call.card === s.app.board.cardMap.M3, "the milestone card")
    verify(call.cardMap === s.app.board.cardMap, "the board's cardMap")
    compare(JSON.stringify(call.relaunch), '{"level":"milestone","cardId":"M3","prefix":"m3","base":"master"}')
    compare(s.runs.flashes.length, 0)
  }

  // 17
  function test_a_relaunch_target_missing_from_the_board_flashes_why() {
    var s = make([run("run-x-canc0004", "cancelled", null, { milestone: "M404" })], "run-x-canc0004"); if (!s) return
    var relaunch = part(s, "stopRelaunch")
    compare(relaunch.enabled, true)
    tap(relaunch)
    compare(s.runs.relaunchCalls.length, 0)
    compare(s.runs.flashes.join("|"), "The card to relaunch is no longer on the board")
    compare(H.find(s.screen, "runDetailFlash").text, "The card to relaunch is no longer on the board")
  }

  // 18
  function test_a_refused_resume_of_this_run_offers_relaunch() {
    var s = make([escalatedRun()], "run-x-escl0002"); if (!s) return
    var relaunch = part(s, "stopRelaunch")
    compare(relaunch.visible, false, "a resumable escalated run: Resume is in the controls")
    s.runs.lastControlErrorType = "NotResumableError"
    s.runs.lastControlErrorRunId = "run-x-escl0002"
    compare(relaunch.visible, true)
    compare(relaunch.enabled, true)
    s.runs.lastControlErrorRunId = "run-x-other0009"
    compare(relaunch.visible, false, "another run's refusal")
    s.runs.lastControlErrorRunId = "run-x-escl0002"
    s.runs.lastControlErrorType = "RunIsLiveError"
    compare(relaunch.visible, false, "a refusal relaunching does not answer")
    s.runs.lastControlErrorType = "CheckpointMismatchError"
    compare(relaunch.visible, true)
    s.runs.runs = [escalatedRun({ milestone: "" })]
    compare(relaunch.visible, false, "no relaunch target, whatever the refusal")
  }

  // 19
  function test_an_escalated_task_run_offers_relaunch() {
    var s = make([escalatedRun({ workflow: "task", card: "t1" })], "run-x-escl0002"); if (!s) return
    var relaunch = part(s, "stopRelaunch")
    compare(relaunch.visible, true)
    compare(relaunch.enabled, true)
    tap(relaunch)
    compare(s.runs.relaunchCalls.length, 1)
    verify(s.runs.relaunchCalls[0].card === s.app.board.cardMap.t1)
    compare(s.runs.relaunchCalls[0].relaunch.level, "card")
  }

  // 20
  function test_a_dead_run_shows_its_last_heartbeat_age() {
    var tree = { stories: [], subtasks: [{ card_id: "t1", phases: [
      { name: "implement", status: "started", attempts: [{ n: 1, status: "started" }] }] }] }
    var r = run("run-x-dead0005", "started", false, { tree: tree })
    r.lease.heartbeat_at = new Date(Date.now() - 150000).toISOString()
    var s = make([r], "run-x-dead0005"); if (!s) return
    compare(part(s, "stopHeadline").text, RG.glyphOf("dead") + " The run's process died · #t1 · at implement")
    compare(part(s, "stopHeartbeat").visible, true)
    compare(part(s, "stopHeartbeat").text, "Last heartbeat 2m ago")
    var bad = run("run-x-dead0005", "started", false, { tree: tree })
    bad.lease.heartbeat_at = "garbage"
    s.runs.runs = [bad]
    compare(part(s, "stopHeartbeat").visible, false, "an unparseable heartbeat")
  }

  // 21
  function test_the_heading_for_attempt_0_says_newest() {
    var s = make(detail(), undefined, sel("t1", "verify", 0)); if (!s) return
    compare(H.find(s.screen, "runOutputHeading").text, "Output · t1 verify (newest)")
    s.runs.selectedAttempt = sel("t1", "implement", 2)
    compare(H.find(s.screen, "runOutputHeading").text, "Output · t1 implement.2")
  }
```

- [ ] **Step 4: Run the screen tests to verify they fail**

Run: `bash tests/run.sh run_detail_screen`
Expected: FAIL — the rewritten tests and tests 12-21 fail (`runDetailStop` is null, so `stop(s).visible` throws `TypeError: Cannot read property 'visible' of null`; the attempt-0 heading reads `Output · t1 verify.0`).

- [ ] **Step 5: Implement the screen changes**

In `ui/screens/RunDetailScreen.qml`:

5a. Replace the header comment (lines 10-18) with:

```qml
// One am run (the "run" view): a header with its state, milestone, branch
// prefix and base and lease; for a stopped run, Why it stopped
// (StopReasonBlock: Runs.stopReport, am's note from the open project's
// comments, Open card and Relaunch); its story > subtask > phase > attempt
// tree, with the orchestrator's own Integrate / Bases / Base rows when it has
// them; and an output pane holding ONE attempt's `am logs` snapshot --
// labelled with its age, never presented as a live tail. Run state always
// comes from am (the run store), never from a brd status; brd's board only
// lends titles, dims the cards it has closed and holds the card Relaunch
// opens. It reads the run store and asks it to show another attempt, fetch
// again or open a relaunch; it owns no state of its own. A run outside the
// open project shows no note, and its Open card and Relaunch are disabled with
// the reason. Ages are read against the clock when a logs reply lands or a
// snapshot replaces the runs: no timer.
```

5b. After `readonly property real nowMs: …` (line 38), add:

```qml
  readonly property var stopReport: Runs.stopReport(screen.run)
  readonly property bool inOpenProject: screen.belongsTo(screen.run, screen.app.runs.project)
  readonly property var stopNoteFound: screen.noteOf(screen.run, screen.stopReport, screen.inOpenProject)
  readonly property var stopNote: screen.stopNoteFound.note
  readonly property string stopNoteCardId: screen.stopNoteFound.cardId
```

5c. After `function requestControl(action) { … }` (ends line 159), add:

```qml
  // The run is in the open project: both roots are non-empty and equal, the
  // open one with trailing "/" removed as runs are tagged.
  function belongsTo(run, openRoot) {
    if (typeof openRoot !== "string" || openRoot === "") return false
    if (!run || run.project === null || typeof run.project !== "object") return false
    var root = run.project.root
    return typeof root === "string" && root !== "" && root === Runs.withProject({}, openRoot, "").project.root
  }

  // am's note on the stopped run, {note, cardId}: from the report's card, else
  // from the milestone card; {null, ""} outside the open project or without
  // an extras store.
  function noteOf(run, report, inProject) {
    var none = { note: null, cardId: "" }
    var extras = screen.app.extras
    if (!inProject || !extras || !report || !run) return none
    if (report.cardId !== "") {
      var onCard = Runs.stopComment(extras.commentsFor(report.cardId), run.id)
      if (onCard !== null) return { note: onCard, cardId: report.cardId }
    }
    if (typeof run.milestone_id === "string" && run.milestone_id !== "") {
      var onMilestone = Runs.stopComment(extras.commentsFor(run.milestone_id), run.id)
      if (onMilestone !== null) return { note: onMilestone, cardId: run.milestone_id }
    }
    return none
  }

  // A dead run's last heartbeat age without "ago"; "" otherwise or unparseable.
  function heartbeatAgeOf(report) {
    if (!report || report.state !== "dead") return ""
    return Runs.snapshotAgeText(Date.parse(report.heartbeatAt), screen.nowMs)
  }

  // Relaunch shows for a run with a relaunch target that cannot be resumed,
  // or whose last resume am refused with a type relaunching answers.
  function offersRelaunch(run, report) {
    if (!report || report.relaunch === null || typeof report.relaunch !== "object") return false
    if (!Runs.controls(run).resume.enabled) return true
    var store = screen.app.runs
    return store.lastControlErrorRunId === run.id && Runs.offersRelaunch({ type: store.lastControlErrorType })
  }

  // Opens the dispatch on the relaunch target's card; a card no longer on the
  // board opens nothing and flashes why.
  function relaunch() {
    var report = screen.stopReport
    if (!report || report.relaunch === null || typeof report.relaunch !== "object") return
    var card = screen.cardOf(report.relaunch.cardId)
    if (card === null) {
      screen.app.runs.flash("The card to relaunch is no longer on the board")
      return
    }
    screen.app.runs.relaunchOpenFor(card, screen.app.board.cardMap, report.relaunch)
  }
```

5d. Replace the `runDetailReason` block (lines 207-216):

```qml
    UI.ThemedText {
      objectName: "runDetailReason"
      variant: "caption"
      theme: screen.theme
      width: parent.width
      visible: screen.runState === "escalated"
      text: Runs.escalationReason(screen.run)
      color: screen.theme.urgent
      wrapMode: Text.WordWrap
    }
```

with:

```qml
    UI.StopReasonBlock {
      objectName: "runDetailStop"
      width: parent.width
      theme: screen.theme
      report: screen.stopReport
      note: screen.stopNote
      heartbeatAge: screen.heartbeatAgeOf(screen.stopReport)
      openCardId: screen.stopReport && screen.stopReport.cardId !== "" ? screen.stopReport.cardId : screen.stopNoteCardId
      openCardReason: screen.inOpenProject ? "" : "Open this run's project to open its card"
      relaunchOffered: screen.offersRelaunch(screen.run, screen.stopReport)
      relaunchReason: screen.inOpenProject ? "" : "Open this run's project to relaunch it"
      onOpenCardRequested: function(id) { if (screen.navigator) screen.navigator.openCard(id) }
      onRelaunchRequested: screen.relaunch()
    }
```

5e. Replace `runOutputHeading`'s text (lines 260-262):

```qml
          text: screen.selection
            ? "Output · " + screen.selection.card_id + " " + screen.selection.phase + "." + screen.selection.attempt
            : "Output"
```

with:

```qml
          text: !screen.selection ? "Output"
            : screen.selection.attempt > 0
              ? "Output · " + screen.selection.card_id + " " + screen.selection.phase + "." + screen.selection.attempt
              : "Output · " + screen.selection.card_id + " " + screen.selection.phase + " (newest)"
```

- [ ] **Step 6: Run the screen tests to verify they pass**

Run: `bash tests/run.sh run_detail_screen`
Expected: PASS — `Totals: N passed, 0 failed`, no `TypeError` / `ReferenceError` / `Unable to assign` lines, exit 0.

- [ ] **Step 7: Run the other run-detail consumers**

Run: `bash tests/run.sh runs_` (covers `tst_runs_flow.qml`, `tst_runs_real_data.qml`, `tst_runs_screen.qml`)
Expected: PASS, exit 0 — their headings use attempts above 0 and nothing else reads `runDetailReason`.

- [ ] **Step 8: Commit**

```bash
git add ui/screens/RunDetailScreen.qml tests/ui/screens/tst_run_detail_screen.qml
git commit -m "feat(ui): Run detail shows Why it stopped with am's note, Open card and Relaunch"
```

---

### Task 3: Panel flow — a cancelled run relaunches into the prefilled dispatch dialog

**Files:**
- Modify: `tests/ui/tst_runs_flow.qml` (add an import after line 10; add one test before the final `}`)

**Interfaces:**
- Consumes: Task 2's `runDetailStop` / `stopHeadline` / `stopRelaunch` in the mounted Panel; the real `RunStore.relaunchOpenFor`, `openDispatch`, `dispatchDefaultsRunner`; Panel's `dispatchDialog`, `dispatchPrefix`, `dispatchBase`; this file's `make()`, `run()`, `key()`, `reply(proc, text, code)`.
- Produces: nothing for later tasks.

- [ ] **Step 1: Write the flow test**

Add after `import "../../core/domain/runs.js" as Runs` (line 10):

```qml
import "../../ui/components/runGlyphs.js" as RG
```

Add before the final closing `}` of the TestCase:

```qml
  // ---- why it stopped (RR 3.3)

  // 22
  function test_a_cancelled_run_relaunches_into_the_prefilled_dispatch_dialog() {
    var p = make(); if (!p) return
    p.app.backendDir = "/plugin/core/backend/"
    p.app.runs.runSettings = { verify: ["uv run pytest"] }
    p.app.board.applyTreeData([{ id: "m1", title: "M one", status: "todo", description: "d", children: [] }])
    var r = run("run-0000000000f7", "cancelled", null, "m1")
    r.branch_prefix = "old-m1"
    r.base_branch = "release"
    p.app.runs.runs = [r]
    p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 })
    wait(50)
    p.shortcuts.handleSearchKey(key(Qt.Key_Return))
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000f7")
    wait(50)
    var block = H.find(p, "runDetailStop")
    compare(block.visible, true)
    compare(H.find(block, "stopHeadline").text, RG.glyphOf("cancelled") + " " + Runs.stopReport(r).headline)
    var relaunch = H.find(block, "stopRelaunch")
    compare(relaunch.visible, true)
    compare(relaunch.enabled, true)
    mouseClick(relaunch)
    compare(p.app.runs.dispatchState, "previewing")
    wait(50)
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(H.find(p, "dispatchPrefix").text, "old-m1")
    compare(H.find(p, "dispatchBase").text, "release")
    reply(p.app.runs.dispatchDefaultsRunner.current, '{"ok":true,"data":{"default_branch":"main"}}', 0)
    compare(H.find(p, "dispatchBase").text, "release", "the run's base is kept over the default branch")
  }
```

- [ ] **Step 2: Run the flow test**

Run: `bash tests/run.sh runs_flow`
Expected: PASS for the new test (Tasks 1 and 2 already wired the screen; this case pins the Panel-level join the stub-based screen test cannot reach). If it fails, read the failing `compare` and fix the screen wiring from Task 2, not the store (store defects are reported, not fixed here).

- [ ] **Step 3: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest passes (including `tests/architecture` layer, guard and glyph checks), every QML file reports `0 failed`, no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `anchors on an item` / `is not a function` lines, exit status 0.

- [ ] **Step 4: Commit**

```bash
git add tests/ui/tst_runs_flow.qml
git commit -m "test(ui): a cancelled run's Relaunch opens the dispatch dialog prefilled"
```

---

## Self-review against the spec

- Block interface (props, signals, objectName, visible rule, presentation only, no `resumeRequested`): Task 1 Step 3.
- What it shows, items 1-9: Task 1 Step 3; tests 1-11 cover each item, including glyph/separator formats, urgent vs foreground, heartbeat only for dead, note heading time and unparseable time, indented `<key>  <value>` lines, parked `#<8>` list, button visibility/enabled/tooltip, written-out distinct reasons with Open card first, row hidden with no button, null/non-object report.
- `RunDetailScreen`: mount between meta and controls replacing `runDetailReason` (Task 2 5d, test 12 and rewritten header test); `stopReport`, `inOpenProject` using `Runs.withProject` (5b/5c, test 15 incl. trailing `/`, `""`, no project); `stopNote`/`stopNoteCardId` card then milestone, re-read on comment replacement (tests 13-14); `heartbeatAge` (test 20); `openCardId` fallback (test 14); reasons (test 15); `relaunchOffered` (tests 16, 18, 19, null target in 18); open/relaunch handlers with `cardOf` and flash (tests 13, 16, 17).
- Output heading `(newest)`: Task 2 5e, test 21.
- Flow case 22: Task 3.
- Edge-case table: running/done no block (header test); escalated milestone no Relaunch (18); task run (19); refusal this run / other run / other type (18); null relaunch (18); another project / no project / no project field (15); no note or another run's note (13 start, 14); unparseable createdAt (Task 1 test 7); parked/cancelled no Open card (16, Task 1 test 9); synthetic escalation with run-end note (14); missing target (17); finished target — store-owned, unchanged, not re-tested here; dead with unparseable heartbeat (20); attempt 0 (21); `canceled` (Task 1 test 5); null theme/report/note and destroy (Task 1 test 11).
- Placeholder scan: none. Names consistent: `stopReport`, `inOpenProject`, `stopNote`, `stopNoteCardId`, `belongsTo`, `noteOf`, `heartbeatAgeOf`, `offersRelaunch`, `relaunch` used identically in 5b-5d and tests.
<!-- task-pipeline: validated -->
