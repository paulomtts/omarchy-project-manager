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
