# 4.2 RunDetailScreen: the live output pane — design

Card `17de0cff-af11-49a6-b7a0-fd25b21e02cf`, a subtask of `1e0d855b`.
Parent spec: `docs/superpowers/specs/2026-10-05-live-output-design.md` (cited below as
**LO** with line numbers). Layering: `docs/architecture.md` (cited as **ARCH**).

## Problem

`ui/screens/RunDetailScreen.qml` shows one attempt's `am logs` snapshot only
(`runOutputPane`, lines 261-327; header comment lines 14-15 "never presented as a live
tail"; `outputAge()` lines 134-145 "Never live"). Everything the live pane needs already
exists and is not read by any screen yet:

- `app.runOutput` (`core/stores/App.qml:139-146`), a `RunOutputStore` with `followStatus`
  (`idle | connecting | following | ended | unsupported | error`), `endStatus`, `liveText`,
  `liveDropped`, `hasOutput`, `followError` (`core/stores/RunOutputStore.qml:54-66`).
- `UI.TailScroll` (`ui/components/TailScroll.qml`): `theme`, `model`, `rowDelegate`,
  `maxHeight`, `listName`, `jumpName`, read-only `following`, `jump()`; invisible with no rows.
- Step entries in `Runs.runTree` (`core/domain/runs.js:740-775`):
  `{phase, attempt: 0, step: true, status}`.
- `RunStore.selectAttempt(cardId, phase, attempt, step)` (`core/stores/RunStore.qml:795-820`):
  a step is `(card, phase, 0, true)`, stored as `{card_id, phase, attempt: 0, step: true}`.
- `RunStore.logsNote` (`RunStore.qml:123`, set to `This step records no output` at
  `RunStore.qml:1092`): never shown by the screen today.

The tree's `AttemptRow` (lines 431-458) ignores step rows: it renders a step as
`verify.?` and does nothing on a click (guard `attempt > 0`, 3-argument `selectAttempt`).
`isSelected` (line 129) cannot mark a step selection.

## Goal

The output pane presents `app.runOutput` whenever its `followStatus` is not `idle` (card),
with the labels, end line and Refresh rule of **LO** "UI" (lines 192-212), and the tree's step
rows select a step. With `followStatus` `idle` the pane behaves exactly as today.

## Inherited constraints

- Label texts: `⟳ live`, `⟳ live · waiting for output`, `ended · <status>` (`gate_failed`,
  `schema_invalid`, `harness_error` in `urgent` with `‼`), `snapshot <age> ago`, the fallback
  sentence before `snapshot …` when unsupported. **LO 203-206.**
- Refresh is shown for a snapshot only. **LO 207.**
- The text is inside `TailScroll`: follows while at the bottom, scrolled up it stays put and
  shows `Jump ↓`. **LO 208-210.**
- The end line `— ended: <status> —` is the pane's last line, not mixed into the text.
  **LO 211.**
- The step row reads `verify` with its phase glyph and no attempt number. **LO 212.** A step
  selection is `{card_id, phase, attempt: 0, step: true}`. **LO 105-106.**
- A step with no log shows `This step records no output`, never in `urgent`. **LO 108-109,
  189-190, 221.**
- For a step, the end triggers a snapshot fetch and "the pane shows the snapshot".
  **LO 182-184.**
- `unsupported`: snapshot with the fallback sentence; Refresh works. **LO 185-187, 218-219.**
- The run left the projection: `error`, am's message (`followError`). **LO 223.**
- Glyphs only from `ui/components/runGlyphs.js` (`RunGlyphs.glyphOf("running")` = ⟳,
  `RunGlyphs.glyphOf("escalated")` = ‼); no glyph literal in the screen. **ARCH 176**;
  `tests/architecture/test_icon_glyphs.py`.
- `ui/screens/**` must not import `core/stores`; the screen reads `app.runOutput` only.
  **ARCH 15**; `tests/architecture/test_layers.py` (no duplicated helpers/components).
- Comments and docstrings state the contract only (card).

## Behavior

Notation: `ro` = `app.runOutput`, `rs` = `app.runs`. "Live mode" = `ro.followStatus` is one
of `connecting`, `following`, `ended`, `error`. "Snapshot mode" = `ro.followStatus` is
`idle` or `unsupported`, or `ro` is absent/null (a missing `runOutput` is treated as idle,
never a throw). With no selection the pane shows `runOutputNone` (`No attempt selected`) and
nothing else, whatever `ro` says.

### Heading (`runOutputHeading`)

- Attempt selection: `Output · <card> <phase>.<n>` (unchanged).
- Step selection (`selection.step === true`): `Output · <card> <phase>` — no `.0`.
- No selection: `Output`.

### Status label (`runOutputAge`, one caption line; empty → hidden)

| `followStatus` | condition | text | colour |
|---|---|---|---|
| `connecting` | — | `⟳ live · waiting for output` | foreground (caption) |
| `following` | `!hasOutput` | `⟳ live · waiting for output` | foreground |
| `following` | `hasOutput` | `⟳ live` | foreground |
| `ended` | `endStatus` ∈ {`gate_failed`, `schema_invalid`, `harness_error`} | `‼ ended · <endStatus>` | `theme.urgent` |
| `ended` | any other non-empty `endStatus` (e.g. `ok`) | `ended · <endStatus>` | foreground |
| `ended` | `endStatus === ""` (step with no log) | `followError` as given (`This step records no output`) | foreground, never urgent |
| `error` | — | `⟳ live` is NOT shown; the label is empty and `followError` shows in `runOutputError` (below) | — |
| `unsupported` | — | `<followError> · <snapshot label>` where the snapshot label is today's `outputAge()` text (`snapshot <age> ago[ · last 200 lines]`, `loading…`, or empty; when it is empty, the sentence alone) | foreground |
| `idle` | — | today's `outputAge()` text, unchanged | foreground |

`⟳` is `RunGlyphs.glyphOf("running")`; `‼` is `RunGlyphs.glyphOf("escalated")`.
The urgent set is exactly those three statuses; any other `endStatus` string is shown
plainly.

### Refresh (`runOutputRefresh`)

Visible iff there is a selection and the pane is in snapshot mode (`idle` or `unsupported`).
Hidden for `connecting`, `following`, `ended`, `error`. Click still calls
`rs.refreshLogs()`.

### Error line (`runOutputError`, urgent caption)

- Snapshot mode: `rs.logsError` (unchanged).
- `error`: `ro.followError` in `theme.urgent` (e.g. `Live output stopped: …`, am's message).
- Other live statuses: hidden.

### Note line (`runOutputNote`, new, dim caption, not urgent)

Snapshot mode with a selection and `rs.logsNote !== ""`: shows `rs.logsNote`. Hidden
otherwise. (Makes a finished step with no log read `This step records no output` instead of
an empty pane; LO 108-109.)

### Body

- Snapshot mode: `runOutputText` (`rs.logsText`, unchanged); the live list is not visible.
- Live mode: `runOutputText` is not visible; the body is a `UI.TailScroll` with
  `listName: "runOutputList"`, `jumpName: "runOutputJump"`, `objectName: "runOutputTail"`.
  Its model is an array of row strings:
  - the source text split on `\n` — the source is `ro.liveText`, except for an ended **step**
    selection whose snapshot has landed (`rs.logsFetchedMs > 0`), where the source is
    `rs.logsText` (LO 182-184: the step's stderr is only in the snapshot). An empty source
    contributes no rows (not one empty row); a trailing `\n` contributes no trailing empty
    row.
  - then, only when `followStatus === "ended"` and `endStatus !== ""`, one last row
    `— ended: <endStatus> —`. The end line is always the model's last element and is never
    part of `liveText`.
  - `liveText` already starts with `… N earlier lines` when lines were dropped; the screen
    adds nothing for `liveDropped`.
  Each row is drawn as a `small` `ThemedText`, `Text.PlainText`, `Text.WrapAnywhere`, the
  list's width. With no rows (e.g. `connecting`, `error` with no text) the list takes no room.
- `error` keeps whatever `liveText` the store still holds in the list, above nothing else;
  the error line explains it.

### Tree: step rows and selection

- A step entry (`step === true`) of `AttemptRow` reads `<glyph> <phase> <status>` (e.g.
  `⟳ verify started`, `✔ docs_commit done`): no `.N`, no `.?`. The `› ` / two-space selection
  prefix and urgent colour rules are unchanged.
- An unnumbered non-step attempt still reads `<phase>.?` and is still not clickable
  (existing test `test_an_unnumbered_attempt_is_listed_but_not_clickable` keeps passing).
- A click on a step row calls `rs.selectAttempt(card_id, phase, 0, true)`; its cursor is the
  pointing hand. A numbered attempt still calls `selectAttempt(card_id, phase, n)`.
- `isSelected` marks a step row iff `selection.step === true` and card and phase match; it
  marks an attempt row iff `selection.step !== true` and card, phase and attempt match. So
  `{t1, verify, 0, step:true}` never marks an attempt row and vice versa.
- `SubtaskRow` click is unchanged (card says only the tree's step rows).
- The Events pane's `attemptRequested` path is unchanged.

### Header comment

The file header comment states the new pane contract (live when `app.runOutput.followStatus`
is not idle, otherwise the snapshot) and drops "never presented as a live tail";
`outputAge()`'s "Never live" comment is reworded to its contract.

## Error paths and odd inputs

- `app.runOutput` missing or null: snapshot mode, no warning, no throw.
- `liveText` not a string: treated as empty (no rows).
- `endStatus` an unknown string: `ended · <it>` plain, end line `— ended: <it> —`.
- `followStatus` an unknown string: treated as idle (snapshot mode).
- Selection changes while `ro` still reports the previous key's status: the screen shows what
  `ro` reports; keeping `ro` in step with the selection is the store's job (out of scope).

## Tests

All in `tests/ui/screens/tst_run_detail_screen.qml` (tier: QML UI test via `bash tests/run.sh`
— the behavior is rendering and click wiring of one screen against a stub app; no backend,
no store logic). Fixture changes:

- The stub `RunStore` (`runsC`) gains `logsNote: ""` and `selectAttempt(cardId, phase,
  attempt, step)` recording `[cardId, phase, attempt, step === true]` in `selected` and
  storing the step form when `step === true`. Existing assertions using
  `selected.join("|")` become `"t1|spec|1|false"` etc., or compare the first three elements.
- The stub app (`appC`) gains `runOutput`: a `QtObject` with `followStatus: "idle"`,
  `endStatus: ""`, `liveText: ""`, `liveDropped: 0`, `hasOutput: false`, `followError: ""`;
  `make()` creates it and returns it as `s.ro`.
- A tree helper with a step: subtask `t1` with phases `implement` (`n:1 done`) and
  `verify` (`kind: "deterministic"`, `status: "started"`, `attempts: []`).

Tests (names indicative):

1. `test_following_with_output_reads_live` — label `⟳ live` (glyph from `RG`), foreground.
2. `test_connecting_and_following_without_output_read_waiting` — both `⟳ live · waiting for output`.
3. `test_ended_ok_reads_ended_and_the_end_line_is_last` — label `ended · ok`, foreground;
   `runOutputList`'s last delegate / model element is `— ended: ok —`; liveText rows precede it.
4. `test_ended_failures_are_urgent_with_the_escalated_glyph` — data-driven over
   `gate_failed`, `schema_invalid`, `harness_error`: label `‼ ended · <s>` (via
   `RG.glyphOf("escalated")`) in `theme.urgent`; end line `— ended: <s> —`.
5. `test_a_step_with_no_log_reads_a_plain_sentence` — `ended`, `endStatus ""`, followError
   `This step records no output`: label is that sentence, not urgent; no end line, list empty.
6. `test_unsupported_puts_the_sentence_before_the_snapshot` — label
   `This am cannot stream output (am logs --follow is missing) · snapshot 14s ago`;
   `runOutputText` shows `logsText`; Refresh visible.
7. `test_a_follow_error_is_urgent` — `error` + followError: `runOutputError` shows it in
   urgent; Refresh hidden; label hidden.
8. `test_refresh_only_for_a_snapshot` — data-driven over all six statuses: visible for
   `idle`, `unsupported`; hidden for `connecting`, `following`, `ended`, `error`.
9. `test_idle_keeps_the_snapshot_pane` — with `followStatus idle` and non-empty `liveText`,
   the list is not visible and `runOutputText` shows `logsText` (existing snapshot tests stay
   unchanged and green).
10. `test_a_step_row_reads_its_phase_without_a_number` — label `  ⟳ verify started`.
11. `test_clicking_a_step_row_selects_the_step` — `tap` → `selected` is
    `["t1", "verify", 0, true]`; the step row becomes `› …`, the `implement.1` row does not.
12. `test_a_step_selection_heading_has_no_number` — `Output · t1 verify`.
13. `test_the_live_list_follows_growing_text_and_offers_jump` — `following` with 80 lines:
    `runOutputTail.following` true, at the bottom, `runOutputJump` hidden; grow `liveText` to
    160 lines → still at the bottom; scroll the list up (`contentY = originY`) → `following`
    false, Jump visible; grow again → contentY unchanged; tap Jump → at the bottom,
    `following` true. (Pattern: `tests/ui/components/tst_tail_scroll.qml`,
    `tst_events_pane.qml:488-547`.)
14. `test_an_ended_step_shows_its_snapshot_then_the_end_line` — step selection, `ended ok`,
    `rs.logsFetchedMs > 0`, `rs.logsText "a\nb"`: list rows `a`, `b`, `— ended: ok —`.
15. `test_a_logs_note_shows_dim_not_urgent` — snapshot mode, `logsNote` set: `runOutputNote`
    visible with that text, not urgent.
16. `test_no_run_output_object_is_the_snapshot` — `app.runOutput = null`: no throw, snapshot
    pane, Refresh visible.

Architecture tier (`tests/architecture`, pytest, run by `tests/run.sh`): unchanged and must
stay green — proves no glyph literal and no `core/stores` import were introduced.

The existing test `test_the_output_pane_is_a_labelled_snapshot_never_live` stays as is (it
runs with `followStatus idle`), and may be renamed to `…_while_idle`.

## Out of scope

- `RunOutputStore`, `RunStore`, `runs.js`, `logStream.js`, the backend helpers and `App`
  wiring (cards 1.x-3.x, done).
- `TailScroll` and `EventsPane` (card 4.1, done) — consumed as is, not modified.
- `docs/architecture.md` and README text about the pane ("never a live tail", ARCH 172) — the
  docs subtask of this milestone.
- `SubtaskRow` selecting a step when its current phase is a started step.
- Auto-moving to the next attempt when the followed one ends (LO 255-256).
- Showing `liveDropped` separately, search/copy/save, ANSI colour (LO 87-94).

## Handoff to the planner

One file changes in production (`ui/screens/RunDetailScreen.qml`) and one test file
(`tests/ui/screens/tst_run_detail_screen.qml`). Suggested tasks, each test-first:
(1) fixtures (stub `runOutput`, 4-arg `selectAttempt`, `logsNote`) with existing tests still
green; (2) step rows: text, click, `isSelected`, heading; (3) labels, error, note and Refresh
rules; (4) live body in `TailScroll` with the end line and the ended-step snapshot source;
follow/Jump test; header comment. Verification: `bash tests/run.sh` green (single file:
`bash tests/run.sh tst_run_detail_screen`).

---

# 4.2 RunDetailScreen: the live output pane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run detail's Output pane presents `app.runOutput` (live label, end line, follow-the-bottom list) whenever its `followStatus` is not `idle`, and the tree's step rows read `verify` and select the step.

**Architecture:** One production file, `ui/screens/RunDetailScreen.qml`, gains a few read-only properties (`ro`, `followStatus`, `live`) and pure helper functions (`roText`, `endIsUrgent`, `statusLabel`, `statusUrgent`, `liveRows`) that its existing pane elements bind to; the live body is the existing `UI.TailScroll`, consumed unchanged. The screen still owns no state: it reads `app.runs` and `app.runOutput` and calls `app.runs.selectAttempt` / `refreshLogs`.

**Tech Stack:** QML (Qt 6, QtQuick), QtTest via `qmltestrunner`, pytest architecture tests; all run by `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/4-2-rundetailscreen-the-17de0cff.md` (reproduced above this plan).

## Global Constraints

- Label texts exactly: `⟳ live`, `⟳ live · waiting for output`, `ended · <status>`, `‼ ended · <status>` for `gate_failed`, `schema_invalid`, `harness_error` (in `theme.urgent`), `snapshot <age> ago`, and `<followError> · <snapshot label>` when unsupported.
- End line exactly `— ended: <endStatus> —` (em dashes), always the list model's last element, never part of `liveText`.
- Refresh is shown for a snapshot only (`idle`, `unsupported`), and only with a selection.
- Glyphs only through `RunGlyphs.glyphOf("running")` (⟳) and `RunGlyphs.glyphOf("escalated")` (‼); no glyph literal in the screen (`tests/architecture/test_icon_glyphs.py`).
- `ui/screens/**` must not import `core/stores`; the screen reads `app.runOutput` only (`tests/architecture/test_layers.py`).
- `TailScroll`, `EventsPane`, `RunStore`, `RunOutputStore`, `runs.js` are not modified.
- A missing/null `app.runOutput` or an unknown `followStatus` is snapshot mode, never a throw.
- `This step records no output` is never drawn in `urgent`.
- Comments and docstrings state the contract only.
- Never use bare `git stash`; never `pkill`/`killall`. Stop a stuck test with `timeout`.

## Review Focus

1. A live `app.runOutput` while nothing is selected: the pane must show only `No attempt selected` — no label, no list, no Refresh, no error, no note. (Task 2 `test_no_selection_ignores_a_live_run_output`; Task 3 `test_no_selection_shows_no_live_list`.)
2. A step selection and an unnumbered attempt of the same phase (`verify` step + `verify.?`): exactly one row is marked `› `, and an attempt-shaped selection `{t1, verify, 0}` never marks the step row. (Task 1 `test_a_step_and_an_attempt_of_one_phase_are_never_both_selected`.)
3. Garbage from the store: an unknown `followStatus`, a non-string `liveText` / `endStatus` / `followError` — snapshot mode or no rows, no TypeError. (Task 2 `test_an_unknown_follow_status_is_the_snapshot`; Task 3 `test_a_non_string_live_text_gives_no_rows`.)
4. The follow going back to `idle` (e.g. the store stops following): the list disappears and the snapshot text, its age and Refresh come back. (Task 3 `test_going_back_to_idle_restores_the_snapshot`.)
5. Output with blank lines and a trailing newline: interior empty lines stay as empty rows, the trailing newline adds no row. (Task 3 `test_blank_lines_are_kept_and_a_trailing_newline_adds_no_row`.)

---

## File Structure

- Modify: `ui/screens/RunDetailScreen.qml` — the only production change. Header comment; new properties `ro`, `followStatus`, `live`; new functions `roText`, `endIsUrgent`, `statusLabel`, `statusUrgent`, `liveRows`; changed `attemptText`, `isSelected`, `outputAge` comment; `runOutputHeading`, `runOutputAge`, `runOutputRefresh`, `runOutputError`, `runOutputText` bindings; new `runOutputNote` and `runOutputTail`; `AttemptRow` step handling.
- Modify: `tests/ui/screens/tst_run_detail_screen.qml` — stub `runsC` gains `logsNote` and a 4-argument `selectAttempt`; new stub `roC`; `appC` gains `runOutput`; `make()` returns `ro`; new helpers and tests.

## How to run the tests

- One file: `timeout 600 bash tests/run.sh tst_run_detail_screen` (runs the pytest tier first, then only QML test paths containing the filter). A QML failure prints a line starting `FAIL!  : RunDetailScreen::<test>()` followed by `   Loc:`; the `Totals:` line shows the counts. The script exits non-zero on any failure or on any `TypeError` / `ReferenceError` / `Unable to assign` warning.
- Everything: `timeout 900 bash tests/run.sh`.

---

### Task 1: Step rows in the tree, step selection and the step heading

**Files:**
- Modify: `ui/screens/RunDetailScreen.qml:118-132` (`attemptText`, `isSelected`), `:271-277` (`runOutputHeading`), `:431-458` (`AttemptRow`)
- Test: `tests/ui/screens/tst_run_detail_screen.qml`

**Interfaces:**
- Consumes: tree attempt entries from `Runs.runTree` — attempts `{phase, attempt, status}`, steps `{phase, attempt: 0, step: true, status}`; `app.runs.selectAttempt(cardId, phase, attempt, step)` (step form `(card, phase, 0, true)`); `app.runs.selectedAttempt` — `{card_id, phase, attempt}` or `{card_id, phase, attempt: 0, step: true}`.
- Produces: `screen.isSelected(cardId, phase, attempt, step)` → bool (step `true` matches only a step selection); `screen.attemptText(entry)` → `"<glyph> <phase> <status>"` for a step. Test stub `rs.selected` becomes `[cardId, phase, attempt, step === true]`; test helpers `stepTree()`, `stepRun()`, `stepSel(card, phase)`.

- [ ] **Step 1: Update the stub `selectAttempt` and the three assertions that read `selected`**

In `tests/ui/screens/tst_run_detail_screen.qml`, replace lines 40-43:

```qml
      function selectAttempt(cardId, phase, attempt) {
        rs.selected = [cardId, phase, attempt]
        rs.selectedAttempt = { card_id: cardId, phase: phase, attempt: attempt }
      }
```

with:

```qml
      // As RunStore: (card, phase, 0, true) is a step, stored with step: true.
      function selectAttempt(cardId, phase, attempt, step) {
        rs.selected = [cardId, phase, attempt, step === true]
        rs.selectedAttempt = step === true ? { card_id: cardId, phase: phase, attempt: 0, step: true }
                                           : { card_id: cardId, phase: phase, attempt: attempt }
      }
```

Then change these three assertions (exact old → new):

- `compare(s.runs.selected.join("|"), "t1|spec|1")` → `compare(s.runs.selected.join("|"), "t1|spec|1|false")` (in `test_clicking_an_attempt_selects_it`)
- `compare(s.runs.selected.join("|"), "t2|spec|1")` → `compare(s.runs.selected.join("|"), "t2|spec|1|false")` (in `test_clicking_a_subtask_selects_its_current_attempt`)
- `compare(s.runs.selected.join("|"), "t1|implement|1")` → `compare(s.runs.selected.join("|"), "t1|implement|1|false")` (in `test_a_row_naming_an_attempt_selects_it_and_shows_output`)

- [ ] **Step 2: Run the file to confirm the fixture change keeps everything green**

Run: `timeout 600 bash tests/run.sh tst_run_detail_screen`
Expected: `Totals:` with `0 failed`, exit 0.

- [ ] **Step 3: Add the step-tree helpers**

In the test file, directly after the line `function sel(card, phase, n) { return { card_id: card, phase: phase, attempt: n } }`, add:

```qml
  // t1 with a numbered implement.1 and a started verify step (kind
  // deterministic, no attempts): the tree lists implement.1 then the step.
  function stepTree() {
    return { stories: [{ card_id: "s1", status: "started", subtasks: ["t1"] }],
             subtasks: [{ card_id: "t1", status: "started", phases: [
               { name: "implement", status: "done", attempts: [{ n: 1, status: "done" }] },
               { name: "verify", kind: "deterministic", status: "started", attempts: [] }] }] }
  }
  function stepRun() { return [run("run-20261004-19efcddc", "started", true, { tree: stepTree() })] }
  function stepSel(card, phase) { return { card_id: card, phase: phase, attempt: 0, step: true } }
```

- [ ] **Step 4: Write the failing tests**

In the test file, directly after `test_an_unnumbered_attempt_is_listed_but_not_clickable` (it ends with `compare(s.runs.selected, null)` and `}`), add:

```qml
  // ---- step rows

  function test_a_step_row_reads_its_phase_without_a_number() {
    var s = make(stepRun(), undefined, sel("t1", "implement", 1)); if (!s) return
    compare(H.find(s.screen, "runAttemptLabel0_0_0").text, "› " + RG.glyphOf("done") + " implement.1 done")
    compare(H.find(s.screen, "runAttemptLabel0_0_1").text, "  " + RG.glyphOf("running") + " verify started")
  }

  function test_clicking_a_step_row_selects_the_step() {
    var s = make(stepRun(), undefined, sel("t1", "implement", 1)); if (!s) return
    compare(H.find(s.screen, "runAttempt0_0_1").hoverCursorShape, Qt.PointingHandCursor)
    tap(H.find(s.screen, "runAttempt0_0_1"))
    compare(JSON.stringify(s.runs.selected), JSON.stringify(["t1", "verify", 0, true]))
    compare(H.find(s.screen, "runAttemptLabel0_0_1").text, "› " + RG.glyphOf("running") + " verify started")
    compare(H.find(s.screen, "runAttemptLabel0_0_1").font.bold, true)
    compare(H.find(s.screen, "runAttemptLabel0_0_0").text, "  " + RG.glyphOf("done") + " implement.1 done")
    tap(H.find(s.screen, "runAttempt0_0_0"))
    compare(s.runs.selected.join("|"), "t1|implement|1|false", "a numbered attempt still selects itself")
  }

  function test_a_step_selection_heading_has_no_number() {
    var s = make(stepRun(), undefined, stepSel("t1", "verify")); if (!s) return
    compare(H.find(s.screen, "runOutputHeading").text, "Output · t1 verify")
    s.runs.selectedAttempt = sel("t1", "implement", 1)
    compare(H.find(s.screen, "runOutputHeading").text, "Output · t1 implement.1")
    s.runs.selectedAttempt = null
    compare(H.find(s.screen, "runOutputHeading").text, "Output")
  }

  // Review Focus 2.
  function test_a_step_and_an_attempt_of_one_phase_are_never_both_selected() {
    var tree = stepTree()
    tree.subtasks[0].phases[1].attempts = [{ status: "started" }]
    var s = make([run("run-20261004-19efcddc", "started", true, { tree: tree })], undefined, stepSel("t1", "verify")); if (!s) return
    var step = H.find(s.screen, "runAttemptLabel0_0_1")
    var unnumbered = H.find(s.screen, "runAttemptLabel0_0_2")
    compare(step.text, "› " + RG.glyphOf("running") + " verify started")
    compare(unnumbered.text, "  " + RG.glyphOf("running") + " verify.? started", "the step selection is not the attempt's")
    s.runs.selectedAttempt = sel("t1", "verify", 0)
    compare(step.text.indexOf("  "), 0, "an attempt-shaped selection never marks the step")
    compare(unnumbered.text.indexOf("› "), 0)
  }
```

- [ ] **Step 5: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_run_detail_screen`
Expected: FAIL lines for `test_a_step_row_reads_its_phase_without_a_number` (actual `"  ⟳ verify.? started"`), `test_clicking_a_step_row_selects_the_step` (cursor is the arrow / `selected` stays null), `test_a_step_selection_heading_has_no_number` (actual `"Output · t1 verify.0"`), `test_a_step_and_an_attempt_of_one_phase_are_never_both_selected`.

- [ ] **Step 6: Implement step text and step-aware selection**

In `ui/screens/RunDetailScreen.qml`, replace `attemptText` and `isSelected` (lines 118-132):

```qml
  function attemptText(a) {
    var glyph = screen.glyphOf(a.status)
    var label = a.phase + "." + (a.attempt > 0 ? a.attempt : "?")
    return (glyph !== "" ? glyph + " " : "") + label + (a.status !== "" ? " " + a.status : "")
  }

  function syntheticText(entry) {
    var glyph = screen.glyphOf(entry.status)
    return (glyph !== "" ? glyph + " " : "") + entry.label + " " + (entry.status !== "" ? entry.status : "not started")
  }

  function isSelected(cardId, phase, attempt) {
    var s = screen.selection
    return !!s && s.card_id === cardId && s.phase === phase && s.attempt === attempt
  }
```

with:

```qml
  // "<glyph> <phase>.<n> <status>"; a step reads its phase alone, an
  // unnumbered attempt "<phase>.?".
  function attemptText(a) {
    var glyph = screen.glyphOf(a.status)
    var label = a.step === true ? a.phase : a.phase + "." + (a.attempt > 0 ? a.attempt : "?")
    return (glyph !== "" ? glyph + " " : "") + label + (a.status !== "" ? " " + a.status : "")
  }

  function syntheticText(entry) {
    var glyph = screen.glyphOf(entry.status)
    return (glyph !== "" ? glyph + " " : "") + entry.label + " " + (entry.status !== "" ? entry.status : "not started")
  }

  // A step row is selected by a step selection of its card and phase; an
  // attempt row by an attempt selection of its card, phase and number.
  function isSelected(cardId, phase, attempt, step) {
    var s = screen.selection
    if (!s || s.card_id !== cardId || s.phase !== phase) return false
    return step === true ? s.step === true : s.step !== true && s.attempt === attempt
  }
```

Replace the `runOutputHeading` text binding (lines 274-276):

```qml
          text: screen.selection
            ? "Output · " + screen.selection.card_id + " " + screen.selection.phase + "." + screen.selection.attempt
            : "Output"
```

with:

```qml
          text: !screen.selection ? "Output"
            : "Output · " + screen.selection.card_id + " " + screen.selection.phase
              + (screen.selection.step === true ? "" : "." + screen.selection.attempt)
```

In `component AttemptRow` (lines 431-449), replace:

```qml
    readonly property bool selected: screen.isSelected(attemptRow.subtask.card_id, attemptRow.attempt.phase, attemptRow.attempt.attempt)
    readonly property string key: attemptRow.storyIndex + "_" + attemptRow.subtaskIndex + "_" + attemptRow.index

    objectName: "runAttempt" + attemptRow.key
    width: screen.width
    theme: screen.theme
    contentMargin: Style.space(32)
    hoverCursorShape: attemptRow.attempt.attempt > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
    onActivated: {
      if (attemptRow.attempt.attempt > 0)
        screen.app.runs.selectAttempt(attemptRow.subtask.card_id, attemptRow.attempt.phase, attemptRow.attempt.attempt)
    }
```

with:

```qml
    readonly property bool isStep: attemptRow.attempt.step === true
    readonly property bool selected: screen.isSelected(attemptRow.subtask.card_id, attemptRow.attempt.phase, attemptRow.attempt.attempt, attemptRow.isStep)
    readonly property string key: attemptRow.storyIndex + "_" + attemptRow.subtaskIndex + "_" + attemptRow.index

    objectName: "runAttempt" + attemptRow.key
    width: screen.width
    theme: screen.theme
    contentMargin: Style.space(32)
    hoverCursorShape: attemptRow.isStep || attemptRow.attempt.attempt > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
    onActivated: {
      if (attemptRow.isStep)
        screen.app.runs.selectAttempt(attemptRow.subtask.card_id, attemptRow.attempt.phase, 0, true)
      else if (attemptRow.attempt.attempt > 0)
        screen.app.runs.selectAttempt(attemptRow.subtask.card_id, attemptRow.attempt.phase, attemptRow.attempt.attempt)
    }
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_run_detail_screen`
Expected: `Totals:` with `0 failed`, exit 0 (including the unchanged `test_an_unnumbered_attempt_is_listed_but_not_clickable`).

- [ ] **Step 8: Commit**

```bash
git add ui/screens/RunDetailScreen.qml tests/ui/screens/tst_run_detail_screen.qml
git commit -m "feat(screens): Run detail's step rows read their phase and select the step"
```

---

### Task 2: The live status label, follow error, logs note and the Refresh rule

**Files:**
- Modify: `ui/screens/RunDetailScreen.qml` (properties after `eventsHeld` at line 45; new functions after `outputAge` at line 145; `runOutputAge`, `runOutputRefresh`, `runOutputError` at lines 279-314; new `runOutputNote`)
- Test: `tests/ui/screens/tst_run_detail_screen.qml`

**Interfaces:**
- Consumes: `app.runOutput` — `followStatus` (`idle | connecting | following | ended | unsupported | error`), `endStatus` (string), `hasOutput` (bool), `followError` (string); `app.runs.logsNote` (string), `app.runs.logsError`; `screen.outputAge()` (existing) → snapshot label string.
- Produces (used by Task 3): `screen.ro` (the runOutput object or `null`), `screen.followStatus` (string, normalised: unknown → `"idle"`), `screen.live` (bool: `connecting | following | ended | error`), `screen.roText(key)` → string field of `ro` or `""`, `screen.endIsUrgent(end)` → bool, `screen.statusLabel()` → string, `screen.statusUrgent()` → bool. Test helpers: stub `roC`; `make()` returns `s.ro`; `setLive(s, fields)`.

- [ ] **Step 1: Add the runOutput stub, `logsNote` and the `setLive` helper**

In the test file, inside `runsC`'s `QtObject`, directly after `property string logsError: ""`, add:

```qml
      property string logsNote: ""
```

Directly after the `runsC` `Component { ... }` block (before `Component { id: appC`), add:

```qml
  // The RunOutputStore surface the screen reads. Fields a store could hand
  // over malformed are var, so tests can put garbage in them.
  Component {
    id: roC
    QtObject {
      property var followStatus: "idle"
      property var endStatus: ""
      property var liveText: ""
      property int liveDropped: 0
      property bool hasOutput: false
      property var followError: ""
    }
  }
```

Inside `appC`'s `QtObject`, directly after `property var runs: null`, add:

```qml
      property var runOutput: null
```

In `make()`, replace:

```qml
    var runs = runsC.createObject(host)
    var app = appC.createObject(host, { nav: nav, runs: runs })
```

with:

```qml
    var runs = runsC.createObject(host)
    var ro = roC.createObject(host)
    var app = appC.createObject(host, { nav: nav, runs: runs, runOutput: ro })
```

and replace `return { app: app, runs: runs, nav: nav, screen: screen }` with `return { app: app, runs: runs, nav: nav, screen: screen, ro: ro }`.

Directly after the `make()` function, add:

```qml
  // Puts each field of `fields` on the stub runOutput.
  function setLive(s, fields) {
    for (var key in fields) s.ro[key] = fields[key]
  }
```

Update the file's header comment (lines 4-7) from:

```qml
// output pane and the events pane, and the missing-run line. A stub app: a
// REAL NavigationStore, a plain object carrying the RunStore properties the
// screen reads (with recorders for selectAttempt, refreshLogs and
// setDetailTab), and a board whose cardMap lends titles and brd statuses.
```

to:

```qml
// output pane (snapshot or live) and the events pane, and the missing-run
// line. A stub app: a REAL NavigationStore, a plain object carrying the
// RunStore properties the screen reads (with recorders for selectAttempt,
// refreshLogs and setDetailTab), a plain object carrying the RunOutputStore
// properties, and a board whose cardMap lends titles and brd statuses.
```

- [ ] **Step 2: Run the file to confirm the fixture change keeps everything green**

Run: `timeout 600 bash tests/run.sh tst_run_detail_screen`
Expected: `0 failed`, exit 0.

- [ ] **Step 3: Write the failing tests**

In the test file, directly after `test_refresh_asks_the_store_again` (ends with `compare(s.runs.refreshed, 1)` and `}`), add:

```qml
  // ---- live output: label, error, note, Refresh

  function test_following_with_output_reads_live() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "following", hasOutput: true, liveText: "collecting...\n" })
    var age = H.find(s.screen, "runOutputAge")
    compare(age.visible, true)
    compare(age.text, RG.glyphOf("running") + " live")
    verify(Qt.colorEqual(age.color, s.screen.theme.dim), "a plain caption")
    compare(H.find(s.screen, "runOutputError").visible, false)
  }

  function test_connecting_and_following_without_output_read_waiting() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    var age = H.find(s.screen, "runOutputAge")
    setLive(s, { followStatus: "connecting" })
    compare(age.text, RG.glyphOf("running") + " live · waiting for output")
    setLive(s, { followStatus: "following", hasOutput: false })
    compare(age.text, RG.glyphOf("running") + " live · waiting for output")
    setLive(s, { hasOutput: true })
    compare(age.text, RG.glyphOf("running") + " live")
  }

  function test_ended_ok_reads_ended_plainly() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "ended", endStatus: "ok", hasOutput: true, liveText: "3 passed\n" })
    var age = H.find(s.screen, "runOutputAge")
    compare(age.text, "ended · ok")
    verify(Qt.colorEqual(age.color, s.screen.theme.dim))
    setLive(s, { endStatus: "weird_status" })
    compare(age.text, "ended · weird_status", "an unknown end status is shown plainly")
    verify(Qt.colorEqual(age.color, s.screen.theme.dim))
  }

  function test_ended_failures_are_urgent_with_the_escalated_glyph_data() {
    return [{ tag: "gate_failed", status: "gate_failed" },
            { tag: "schema_invalid", status: "schema_invalid" },
            { tag: "harness_error", status: "harness_error" }]
  }

  function test_ended_failures_are_urgent_with_the_escalated_glyph(data) {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "ended", endStatus: data.status, hasOutput: true, liveText: "x\n" })
    var age = H.find(s.screen, "runOutputAge")
    compare(age.text, RG.glyphOf("escalated") + " ended · " + data.status)
    verify(Qt.colorEqual(age.color, s.screen.theme.urgent))
  }

  function test_a_step_with_no_log_reads_a_plain_sentence() {
    var s = make(stepRun(), undefined, stepSel("t1", "verify")); if (!s) return
    setLive(s, { followStatus: "ended", endStatus: "", followError: "This step records no output" })
    var age = H.find(s.screen, "runOutputAge")
    compare(age.text, "This step records no output")
    verify(!Qt.colorEqual(age.color, s.screen.theme.urgent), "never urgent")
    compare(H.find(s.screen, "runOutputError").visible, false)
  }

  function test_unsupported_puts_the_sentence_before_the_snapshot() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "unsupported", followError: "This am cannot stream output (am logs --follow is missing)" })
    var age = H.find(s.screen, "runOutputAge")
    compare(age.text, "This am cannot stream output (am logs --follow is missing)", "no snapshot yet: the sentence alone")
    s.runs.logsText = "3 passed"
    s.runs.logsFetchedMs = Date.now() - 14000
    compare(age.text, "This am cannot stream output (am logs --follow is missing) · snapshot 14s ago")
    verify(Qt.colorEqual(age.color, s.screen.theme.dim))
    compare(H.find(s.screen, "runOutputText").visible, true)
    compare(H.find(s.screen, "runOutputText").text, "3 passed")
    compare(H.find(s.screen, "runOutputRefresh").visible, true)
    tap(H.find(s.screen, "runOutputRefresh"))
    compare(s.runs.refreshed, 1, "Refresh works")
  }

  function test_a_follow_error_is_urgent() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsError = "an older snapshot error"
    setLive(s, { followStatus: "error", followError: "Live output stopped: run not found" })
    var err = H.find(s.screen, "runOutputError")
    compare(err.visible, true)
    compare(err.text, "Live output stopped: run not found")
    verify(Qt.colorEqual(err.color, s.screen.theme.urgent))
    compare(H.find(s.screen, "runOutputRefresh").visible, false)
    compare(H.find(s.screen, "runOutputAge").visible, false, "no live label for an error")
  }

  function test_refresh_only_for_a_snapshot_data() {
    return [{ tag: "idle", status: "idle", shown: true },
            { tag: "unsupported", status: "unsupported", shown: true },
            { tag: "connecting", status: "connecting", shown: false },
            { tag: "following", status: "following", shown: false },
            { tag: "ended", status: "ended", shown: false },
            { tag: "error", status: "error", shown: false }]
  }

  function test_refresh_only_for_a_snapshot(data) {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: data.status })
    compare(H.find(s.screen, "runOutputRefresh").visible, data.shown)
  }

  function test_a_logs_note_shows_dim_not_urgent() {
    var s = make(stepRun(), undefined, stepSel("t1", "verify")); if (!s) return
    var note = H.find(s.screen, "runOutputNote")
    compare(note.visible, false, "no note, no line")
    s.runs.logsNote = "This step records no output"
    compare(note.visible, true)
    compare(note.text, "This step records no output")
    verify(Qt.colorEqual(note.color, s.screen.theme.dim))
    verify(!Qt.colorEqual(note.color, s.screen.theme.urgent))
    setLive(s, { followStatus: "following" })
    compare(note.visible, false, "a snapshot's note only")
  }

  function test_no_run_output_object_is_the_snapshot() {
    failOnWarning(/TypeError|ReferenceError|is not a function|Unable to assign/)
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.app.runOutput = null
    s.runs.logsText = "3 passed"
    s.runs.logsFetchedMs = Date.now() - 14000
    compare(H.find(s.screen, "runOutputAge").text, "snapshot 14s ago")
    compare(H.find(s.screen, "runOutputText").text, "3 passed")
    compare(H.find(s.screen, "runOutputRefresh").visible, true)
    s.app.runOutput = undefined
    compare(H.find(s.screen, "runOutputRefresh").visible, true, "undefined too")
  }

  // Review Focus 1.
  function test_no_selection_ignores_a_live_run_output() {
    var s = make(detail()); if (!s) return
    s.runs.logsNote = "This step records no output"
    setLive(s, { followStatus: "error", followError: "Live output stopped" })
    compare(H.find(s.screen, "runOutputNone").visible, true)
    compare(H.find(s.screen, "runOutputAge").visible, false)
    compare(H.find(s.screen, "runOutputError").visible, false)
    compare(H.find(s.screen, "runOutputNote").visible, false)
    compare(H.find(s.screen, "runOutputRefresh").visible, false)
    setLive(s, { followStatus: "following", hasOutput: true, liveText: "a\n" })
    compare(H.find(s.screen, "runOutputAge").visible, false)
  }

  // Review Focus 3.
  function test_an_unknown_follow_status_is_the_snapshot() {
    failOnWarning(/TypeError|ReferenceError|is not a function|Unable to assign/)
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsFetchedMs = Date.now() - 14000
    setLive(s, { followStatus: "bogus" })
    compare(H.find(s.screen, "runOutputAge").text, "snapshot 14s ago")
    compare(H.find(s.screen, "runOutputRefresh").visible, true)
    setLive(s, { followStatus: 7 })
    compare(H.find(s.screen, "runOutputAge").text, "snapshot 14s ago")
    setLive(s, { followStatus: "ended", endStatus: 5, followError: null })
    compare(H.find(s.screen, "runOutputAge").visible, false, "a non-string end status is none, and so is the sentence")
    setLive(s, { followStatus: "error", followError: 9 })
    compare(H.find(s.screen, "runOutputError").visible, false)
  }
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_run_detail_screen`
Expected: FAIL lines for the new tests, e.g. `test_following_with_output_reads_live` (actual `""` for the label), `test_refresh_only_for_a_snapshot(connecting)` (Refresh still visible), `test_a_logs_note_shows_dim_not_urgent` (`runOutputNote` not found: `H.find` returns null → TypeError reading `visible`).

- [ ] **Step 5: Add the live-mode properties**

In `ui/screens/RunDetailScreen.qml`, directly after:

```qml
  readonly property int eventsHeld: Array.isArray(screen.app.runs.events) ? screen.app.runs.events.length : 0
```

add:

```qml
  // app.runOutput, or null when the app has none.
  readonly property var ro: screen.app.runOutput || null
  // ro's followStatus; "idle" without ro or for anything it does not name.
  readonly property string followStatus: {
    var f = screen.ro ? screen.ro.followStatus : "idle"
    return ["connecting", "following", "ended", "error", "unsupported"].indexOf(f) >= 0 ? f : "idle"
  }
  // The pane presents ro (live mode) rather than the snapshot.
  readonly property bool live: ["connecting", "following", "ended", "error"].indexOf(screen.followStatus) >= 0
```

- [ ] **Step 6: Add the label helpers and reword `outputAge`'s comment**

Replace the `outputAge` comment (lines 134-135):

```qml
  // The pane's age line: the snapshot's age (and "last 200 lines" when cut),
  // "loading…" before the first reply, "" otherwise. Never "live".
```

with:

```qml
  // The snapshot's label: its age (and "last 200 lines" when cut),
  // "loading…" before the first reply, "" otherwise or with no selection.
```

Directly after the closing `}` of `outputAge()`, add:

```qml
  // A string field of ro; "" without ro or when it is not a string.
  function roText(key) {
    var v = screen.ro ? screen.ro[key] : ""
    return typeof v === "string" ? v : ""
  }

  // The end statuses drawn urgent, with the escalated glyph.
  function endIsUrgent(end) {
    return end === "gate_failed" || end === "schema_invalid" || end === "harness_error"
  }

  // The pane's status line: live or waiting, ended with its status (or ro's
  // sentence for an end without one), the unsupported sentence before the
  // snapshot's label, or the snapshot's label. "" with no selection and for a
  // follow error, which runOutputError states.
  function statusLabel() {
    if (!screen.selection) return ""
    var f = screen.followStatus
    var running = RunGlyphs.glyphOf("running")
    if (f === "connecting" || (f === "following" && screen.ro.hasOutput !== true)) return running + " live · waiting for output"
    if (f === "following") return running + " live"
    if (f === "error") return ""
    if (f === "ended") {
      var end = screen.roText("endStatus")
      if (end === "") return screen.roText("followError")
      return (screen.endIsUrgent(end) ? RunGlyphs.glyphOf("escalated") + " " : "") + "ended · " + end
    }
    var age = screen.outputAge()
    if (f !== "unsupported") return age
    var sentence = screen.roText("followError")
    return sentence !== "" && age !== "" ? sentence + " · " + age : sentence + age
  }

  // The status line is drawn urgent: an ended attempt with an urgent status.
  function statusUrgent() {
    return !!screen.selection && screen.followStatus === "ended" && screen.endIsUrgent(screen.roText("endStatus"))
  }
```

- [ ] **Step 7: Bind the label, Refresh and error line; add the note line**

Replace the `runOutputAge` element:

```qml
        UI.ThemedText {
          objectName: "runOutputAge"
          variant: "caption"
          theme: screen.theme
          visible: text !== ""
          text: screen.outputAge()
        }
```

with:

```qml
        UI.ThemedText {
          objectName: "runOutputAge"
          variant: "caption"
          theme: screen.theme
          visible: text !== ""
          text: screen.statusLabel()
          color: screen.statusUrgent() ? screen.theme.urgent : screen.theme.dim
        }
```

In the `runOutputRefresh` element, replace `visible: !!screen.selection` with:

```qml
          visible: !!screen.selection && !screen.live
```

Replace the `runOutputError` element:

```qml
      UI.ThemedText {
        objectName: "runOutputError"
        variant: "caption"
        theme: screen.theme
        width: parent.width
        visible: !!screen.selection && screen.app.runs.logsError !== ""
        text: screen.app.runs.logsError
        color: screen.theme.urgent
        wrapMode: Text.WordWrap
      }
```

with:

```qml
      // The snapshot's fetch error, or in live mode the follow's error.
      UI.ThemedText {
        objectName: "runOutputError"
        variant: "caption"
        theme: screen.theme
        width: parent.width
        visible: text !== ""
        text: !screen.selection ? ""
          : !screen.live ? screen.app.runs.logsError
          : screen.followStatus === "error" ? screen.roText("followError") : ""
        color: screen.theme.urgent
        wrapMode: Text.WordWrap
      }

      // The snapshot's neutral note (a step that records no output), never urgent.
      UI.ThemedText {
        objectName: "runOutputNote"
        variant: "dim"
        theme: screen.theme
        width: parent.width
        visible: text !== ""
        text: !!screen.selection && !screen.live && typeof screen.app.runs.logsNote === "string" ? screen.app.runs.logsNote : ""
        wrapMode: Text.WordWrap
      }
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_run_detail_screen`
Expected: `0 failed`, exit 0; the existing snapshot tests (`test_the_output_pane_is_a_labelled_snapshot_never_live`, `test_loading_then_an_error_that_keeps_the_text`, `test_refresh_asks_the_store_again`, `test_no_selection_shows_no_attempt_rows`) still pass.

- [ ] **Step 9: Commit**

```bash
git add ui/screens/RunDetailScreen.qml tests/ui/screens/tst_run_detail_screen.qml
git commit -m "feat(screens): Run detail labels live output, its end and its error, and offers Refresh for a snapshot only"
```

---

### Task 3: The live body in a TailScroll, the end line, the ended-step snapshot, and the header comment

**Files:**
- Modify: `ui/screens/RunDetailScreen.qml` (header comment lines 10-23; new `liveRows()` after `statusUrgent()`; `runOutputText` visibility; new `UI.TailScroll` after `runOutputText`)
- Test: `tests/ui/screens/tst_run_detail_screen.qml`

**Interfaces:**
- Consumes: from Task 2 — `screen.ro`, `screen.followStatus`, `screen.live`, `screen.roText(key)`; `app.runOutput.liveText`, `.endStatus`; `app.runs.logsText`, `.logsFetchedMs`; `screen.selection.step`; `UI.TailScroll` (`theme`, `model`, `rowDelegate`, `listName`, `jumpName`, read-only `following`, `jump()`; invisible with no rows; default `maxHeight` `Style.space(320)` = 320 in tests).
- Produces: `screen.liveRows()` → array of row strings; objects `runOutputTail` (the TailScroll), `runOutputList` (its ListView), `runOutputJump` (its Jump button), `runOutputRow<i>` (row delegates).

- [ ] **Step 1: Add the test helpers**

In the test file, directly after the `setLive` function, add:

```qml
  // n numbered lines, each ended by a newline.
  function lines(n) {
    var out = []
    for (var i = 1; i <= n; i++) out.push("line " + i)
    return out.join("\n") + "\n"
  }

  function atBottom(list) {
    return Math.abs(list.contentY - (list.originY + list.contentHeight - list.height)) <= 1
  }

  // The live list's model, as JSON.
  function liveModel(s) { return JSON.stringify(H.find(s.screen, "runOutputTail").model) }
```

- [ ] **Step 2: Write the failing tests**

Directly after `test_an_unknown_follow_status_is_the_snapshot` (added in Task 2), add:

```qml
  // ---- live output: the list

  function test_idle_keeps_the_snapshot_pane() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsText = "3 passed"
    setLive(s, { followStatus: "idle", liveText: "live stuff\n", hasOutput: true })
    compare(H.find(s.screen, "runOutputTail").visible, false)
    compare(H.find(s.screen, "runOutputList").count, 0)
    compare(H.find(s.screen, "runOutputText").visible, true)
    compare(H.find(s.screen, "runOutputText").text, "3 passed")
  }

  function test_following_shows_the_live_text_not_the_snapshot() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsText = "old snapshot"
    setLive(s, { followStatus: "following", hasOutput: true, liveText: "… 3 earlier lines\ncollecting...\n" })
    wait(30)
    compare(H.find(s.screen, "runOutputText").visible, false)
    compare(H.find(s.screen, "runOutputTail").visible, true)
    compare(liveModel(s), JSON.stringify(["… 3 earlier lines", "collecting..."]))
    var row = H.find(s.screen, "runOutputRow1")
    compare(row.text, "collecting...")
    compare(row.textFormat, Text.PlainText)
    compare(row.wrapMode, Text.WrapAnywhere)
    compare(row.width, H.find(s.screen, "runOutputList").width)
  }

  function test_ended_ok_reads_ended_and_the_end_line_is_last() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "ended", endStatus: "ok", hasOutput: true, liveText: "a\nb\n" })
    wait(30)
    compare(H.find(s.screen, "runOutputAge").text, "ended · ok")
    compare(liveModel(s), JSON.stringify(["a", "b", "— ended: ok —"]))
    compare(H.find(s.screen, "runOutputRow2").text, "— ended: ok —")
    compare(s.ro.liveText, "a\nb\n", "the end line is never part of liveText")
  }

  function test_ended_failures_end_with_their_end_line_data() {
    return [{ tag: "gate_failed", status: "gate_failed" },
            { tag: "schema_invalid", status: "schema_invalid" },
            { tag: "harness_error", status: "harness_error" }]
  }

  function test_ended_failures_end_with_their_end_line(data) {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "ended", endStatus: data.status, hasOutput: true, liveText: "x\n" })
    compare(liveModel(s), JSON.stringify(["x", "— ended: " + data.status + " —"]))
  }

  function test_a_step_with_no_log_has_no_end_line_and_no_rows() {
    var s = make(stepRun(), undefined, stepSel("t1", "verify")); if (!s) return
    setLive(s, { followStatus: "ended", endStatus: "", followError: "This step records no output" })
    compare(liveModel(s), "[]")
    compare(H.find(s.screen, "runOutputTail").visible, false)
    compare(H.find(s.screen, "runOutputText").visible, false)
  }

  function test_an_ended_step_shows_its_snapshot_then_the_end_line() {
    var s = make(stepRun(), undefined, stepSel("t1", "verify")); if (!s) return
    setLive(s, { followStatus: "ended", endStatus: "ok", hasOutput: true, liveText: "x\n" })
    compare(liveModel(s), JSON.stringify(["x", "— ended: ok —"]), "before the snapshot lands: the live text")
    s.runs.logsText = "a\nb"
    s.runs.logsFetchedMs = Date.now()
    compare(liveModel(s), JSON.stringify(["a", "b", "— ended: ok —"]))
    s.runs.selectedAttempt = sel("t1", "implement", 1)
    compare(liveModel(s), JSON.stringify(["x", "— ended: ok —"]), "an attempt always shows its live text")
  }

  function test_an_error_keeps_the_live_text_it_has() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "error", followError: "Live output stopped: run not found", liveText: "kept\n" })
    compare(liveModel(s), JSON.stringify(["kept"]))
    compare(H.find(s.screen, "runOutputText").visible, false)
    setLive(s, { liveText: "" })
    compare(H.find(s.screen, "runOutputTail").visible, false, "no text, no room")
  }

  function test_connecting_has_no_rows() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsText = "old snapshot"
    setLive(s, { followStatus: "connecting" })
    compare(liveModel(s), "[]")
    compare(H.find(s.screen, "runOutputTail").visible, false)
    compare(H.find(s.screen, "runOutputText").visible, false)
  }

  function test_the_live_list_follows_growing_text_and_offers_jump() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "following", hasOutput: true, liveText: lines(80) })
    wait(50)
    var tail = H.find(s.screen, "runOutputTail")
    var list = H.find(s.screen, "runOutputList")
    var jump = H.find(s.screen, "runOutputJump")
    compare(list.count, 80)
    verify(list.contentHeight > list.height, "the list scrolls")
    tryVerify(function () { return atBottom(list) }, 1000, "it opens at its bottom")
    compare(tail.following, true)
    compare(jump.visible, false)
    s.ro.liveText = lines(160)
    wait(50)
    compare(list.count, 160)
    tryVerify(function () { return atBottom(list) }, 1000, "growing text is followed")
    compare(tail.following, true)
    list.contentY = list.originY
    wait(30)
    compare(tail.following, false)
    compare(jump.visible, true)
    var before = list.contentY
    s.ro.liveText = lines(200)
    wait(50)
    compare(list.count, 200)
    compare(list.contentY, before, "scrolled up, it stays put")
    tap(jump)
    tryVerify(function () { return atBottom(list) }, 1000, "Jump puts it at its bottom")
    compare(tail.following, true)
  }

  // Review Focus 1.
  function test_no_selection_shows_no_live_list() {
    var s = make(detail()); if (!s) return
    setLive(s, { followStatus: "following", hasOutput: true, liveText: "a\n" })
    compare(liveModel(s), "[]")
    compare(H.find(s.screen, "runOutputTail").visible, false)
    compare(H.find(s.screen, "runOutputNone").visible, true)
  }

  // Review Focus 3.
  function test_a_non_string_live_text_gives_no_rows() {
    failOnWarning(/TypeError|ReferenceError|is not a function|Unable to assign/)
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "following", hasOutput: true, liveText: 42 })
    compare(liveModel(s), "[]")
    setLive(s, { liveText: null })
    compare(liveModel(s), "[]")
    setLive(s, { followStatus: "ended", endStatus: { s: 1 }, liveText: "a\n" })
    compare(liveModel(s), JSON.stringify(["a"]), "a non-string end status adds no end line")
  }

  // Review Focus 4.
  function test_going_back_to_idle_restores_the_snapshot() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsText = "3 passed"
    s.runs.logsFetchedMs = Date.now() - 14000
    setLive(s, { followStatus: "following", hasOutput: true, liveText: "a\n" })
    compare(H.find(s.screen, "runOutputTail").visible, true)
    compare(H.find(s.screen, "runOutputRefresh").visible, false)
    setLive(s, { followStatus: "idle" })
    compare(H.find(s.screen, "runOutputTail").visible, false)
    compare(H.find(s.screen, "runOutputText").visible, true)
    compare(H.find(s.screen, "runOutputText").text, "3 passed")
    compare(H.find(s.screen, "runOutputAge").text, "snapshot 14s ago")
    compare(H.find(s.screen, "runOutputRefresh").visible, true)
  }

  // Review Focus 5.
  function test_blank_lines_are_kept_and_a_trailing_newline_adds_no_row() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "following", hasOutput: true, liveText: "a\n\nb\n" })
    compare(liveModel(s), JSON.stringify(["a", "", "b"]))
    setLive(s, { liveText: "a\n\nb" })
    compare(liveModel(s), JSON.stringify(["a", "", "b"]), "a partial last line is a row")
  }
```

Also rename the existing test `test_the_output_pane_is_a_labelled_snapshot_never_live` to `test_the_output_pane_is_a_labelled_snapshot_while_idle` (name only; body unchanged).

- [ ] **Step 3: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_run_detail_screen`
Expected: FAIL lines for the new list tests; most read `runOutputTail` / `runOutputList`, which do not exist yet, so `H.find` returns null and the test fails with a TypeError on `.visible` / `.model` / `.count` (the run script also prints the `TypeError` line and exits 1).

- [ ] **Step 4: Add `liveRows()`**

In `ui/screens/RunDetailScreen.qml`, directly after the closing `}` of `statusUrgent()`, add:

```qml
  // The live list's rows: the source text's lines (an ended step's landed
  // snapshot, else ro's liveText; no trailing empty row), then the end line
  // once ro has ended with a status. [] with no selection or outside live mode.
  function liveRows() {
    if (!screen.selection || !screen.live) return []
    var store = screen.app.runs
    var ended = screen.followStatus === "ended"
    var source = ended && screen.selection.step === true && store.logsFetchedMs > 0
      ? store.logsText : screen.roText("liveText")
    var rows = typeof source === "string" && source !== "" ? source.split("\n") : []
    if (rows.length > 0 && rows[rows.length - 1] === "") rows.pop()
    var end = screen.roText("endStatus")
    if (ended && end !== "") rows.push("— ended: " + end + " —")
    return rows
  }
```

- [ ] **Step 5: Hide the snapshot text in live mode and add the TailScroll**

Replace the `runOutputText` element:

```qml
      // Read-only by nature: a Text, in the theme's font, never an editor.
      UI.ThemedText {
        objectName: "runOutputText"
        variant: "small"
        theme: screen.theme
        width: parent.width
        visible: !!screen.selection && text !== ""
        text: screen.app.runs.logsText
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
      }
```

with:

```qml
      // The snapshot. Read-only by nature: a Text, in the theme's font, never an editor.
      UI.ThemedText {
        objectName: "runOutputText"
        variant: "small"
        theme: screen.theme
        width: parent.width
        visible: !!screen.selection && !screen.live && text !== ""
        text: screen.app.runs.logsText
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
      }

      // Live mode's text, one row per line, following its bottom; outside
      // live mode it has no rows and takes no room.
      UI.TailScroll {
        objectName: "runOutputTail"
        width: parent.width
        theme: screen.theme
        model: screen.liveRows()
        listName: "runOutputList"
        jumpName: "runOutputJump"

        rowDelegate: UI.ThemedText {
          id: outputRow
          required property var modelData
          required property int index

          objectName: "runOutputRow" + outputRow.index
          width: outputRow.ListView.view ? outputRow.ListView.view.width : 0
          variant: "small"
          theme: screen.theme
          text: outputRow.modelData
          textFormat: Text.PlainText
          wrapMode: Text.WrapAnywhere
        }
      }
```

- [ ] **Step 6: Rewrite the header comment**

Replace the file header comment (lines 10-23):

```qml
// One am run (the "run" view): a header with its state, milestone, branch
// prefix and base and lease; its story > subtask > phase > attempt tree, with
// the orchestrator's own Integrate / Bases / Base rows when it has them; and a
// bottom area of two tabs, app.runs.detailTab, chosen by the Output / Events
// chips. Output holds ONE attempt's `am logs` snapshot -- labelled with its
// age, never presented as a live tail. Events is the run's event timeline
// (EventsPane over app.runs.events); its filter chips set app.runs.eventsFilter,
// and a row naming an attempt selects that attempt and shows Output. The
// Events chip counts the rows held plus app.runs.eventsDropped. Run state
// always comes from am (the run store), never from a brd status; brd's board
// only lends titles and dims the cards it has closed. It reads the run store
// and asks it to show another attempt or tab or fetch again; it owns no state
// of its own. Ages are read against the clock when a logs reply lands or a
// snapshot replaces the runs: no timer.
```

with:

```qml
// One am run (the "run" view): a header with its state, milestone, branch
// prefix and base and lease; its story > subtask > phase > attempt tree (a
// step row reads its phase and selects the step), with the orchestrator's own
// Integrate / Bases / Base rows when it has them; and a bottom area of two
// tabs, app.runs.detailTab, chosen by the Output / Events chips. Output shows
// ONE selected attempt or step. While app.runOutput's followStatus is
// connecting, following, ended or error it is live: app.runOutput's text in
// a TailScroll under a live / ended label, closed by an end line once ended,
// and no Refresh. Otherwise (idle, unsupported, or no app.runOutput) it is
// the selection's `am logs` snapshot labelled with its age, with Refresh.
// Events is the run's event timeline (EventsPane over app.runs.events); its
// filter chips set app.runs.eventsFilter, and a row naming an attempt selects
// that attempt and shows Output. The Events chip counts the rows held plus
// app.runs.eventsDropped. Run state always comes from am (the run store),
// never from a brd status; brd's board only lends titles and dims the cards
// it has closed. It reads the run store and app.runOutput and asks the run
// store to show another attempt or tab or fetch again; it owns no state of
// its own. Ages are read against the clock when a logs reply lands or a
// snapshot replaces the runs: no timer.
```

- [ ] **Step 7: Run the file to verify it passes**

Run: `timeout 600 bash tests/run.sh tst_run_detail_screen`
Expected: `0 failed`, exit 0.

- [ ] **Step 8: Run the whole suite (architecture tier included)**

Run: `timeout 900 bash tests/run.sh`
Expected: pytest line `passed` with no failures (proves no glyph literal and no `core/stores` import were introduced; `grep -n '⟳\|‼' ui/screens/RunDetailScreen.qml` prints nothing), every QML file's `Totals:` with `0 failed`, exit 0.

- [ ] **Step 9: Commit**

```bash
git add ui/screens/RunDetailScreen.qml tests/ui/screens/tst_run_detail_screen.qml
git commit -m "feat(screens): Run detail shows live output in a TailScroll that ends with an end line"
```

---

## Self-review against the spec

- Heading (attempt / step / none): Task 1 `test_a_step_selection_heading_has_no_number`.
- Status label table, every row: `connecting`/`following` (Task 2 tests 1-2), `ended` urgent set / other / empty (Task 2 `…_urgent_with_the_escalated_glyph`, `…_ended_plainly`, `…_a_plain_sentence`), `error` (label hidden, Task 2 `test_a_follow_error_is_urgent`), `unsupported` with and without a snapshot label (Task 2), `idle` (existing snapshot tests + Task 3 `test_idle_keeps_the_snapshot_pane`).
- Refresh rule: Task 2 data-driven test over all six statuses; no-selection in Task 2 RF1 and the existing `test_no_selection_shows_no_attempt_rows`.
- Error line (snapshot / error / other live): existing `test_loading_then_an_error_that_keeps_the_text`, Task 2 `test_a_follow_error_is_urgent` (followError wins over logsError), RF3.
- Note line: Task 2 `test_a_logs_note_shows_dim_not_urgent`.
- Body: source split, no empty/trailing rows, end line last, ended-step snapshot source, error keeps text, connecting no rows, row drawing (small, PlainText, WrapAnywhere, list width): Task 3. Follow/Jump: Task 3 test 13.
- Tree step rows: text, click with pointing hand, `isSelected` both directions, unnumbered attempt unchanged: Task 1. SubtaskRow and the Events path unchanged (existing tests, with the `|false` suffix).
- Header comment and `outputAge` comment: Task 3 Step 6, Task 2 Step 6.
- Error paths: null/undefined runOutput (Task 2), non-string liveText (Task 3), unknown endStatus (Task 2 `weird_status`), unknown followStatus (Task 2 RF3).
- Types: `isSelected(cardId, phase, attempt, step)`, `roText(key)`, `followStatus`, `live`, `liveRows()` are defined before use and named identically in every task; test helpers `stepTree/stepRun/stepSel` (Task 1), `roC/setLive/s.ro` (Task 2), `lines/atBottom/liveModel` (Task 3).
<!-- task-pipeline: validated -->
