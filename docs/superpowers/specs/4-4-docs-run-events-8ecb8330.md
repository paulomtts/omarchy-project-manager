# 4.4 Docs: run events timeline (card 8ecb8330)

Parent story: 55a2dc57. Milestone spec: `docs/superpowers/specs/2026-10-05-run-events-timeline-design.md` (cited below as **S5:line**). Blocked by 62e53e6e (4.3, the Events tab and the `e` key), which is merged into this branch (`f36a3a2`).

## Scope

Docs only. Edit `docs/architecture.md` and `README.md` so they describe the run events timeline **as built** in cards 1.x–4.3. Change no QML, JS, Python, test or fixture file.

Where S5 and the code disagree, the code wins. Before writing a sentence, read the file it is about. The sources are:
- `core/domain/runEvents.js`
- `core/backend/runs/runs-events.py`
- `core/stores/RunStore.qml`: the events state at L124-139, `stopLive` at ~L395, `onSelectedRunIdChanged` .. `foldReply` at ~L866-1048, `eventsRunner` at ~L1993, and `eventsState` at ~L2148
- `core/stores/App.qml` (`titles:` at ~L112)
- `ui/components/EventsPane.qml`
- `ui/screens/RunDetailScreen.qml`
- `ui/Shortcuts.qml` (`handleEventsKey`)

### Known S5-vs-built differences the docs must follow

| S5 says | built (what the docs say) |
|---|---|
| helper runs `am events RUN [--after-seq] [--before-seq] [--tail] [--limit]`, prints `{ok, events, head}` (S5:44-47, 77-81) | `runs-events.py RUN [--since SEQ] [--tail N]` runs `am watch RUN` (plus `--since SEQ`), never `--follow`, `--repo-dir`, `--all`, `--since-seq` or `--pretty`; `--tail` is applied by the helper and never reaches am; prints `{ok, events, last_seq, total}` |
| `mergeRows`, dedupe by `gseq` (S5:73) | `foldEvents(rows, events, cap)`: one row per `seq`, the last one taken wins, ascending, the lowest dropped past the cap (default 500), returns `{rows, dropped}` |
| `rowGlyph` export (S5:74) | no such export; `eventRow` sets `glyph` from `Runs.glyphStateOf(status)`; EventsPane draws the `‼` glyph on any failure row |
| `eventsHasEarlier`, `eventsOldestSeq`, a **Load earlier** control, `--before-seq` paging (S5:82-84, 96-97, 135) | none of these exist. `eventsDropped` counts the run's events that are not held. The pane shows `… N earlier events` when it is above 0. Nothing is paged backward. |
| cursor is the highest `gseq` (S5:83) | `eventsCursor` is the highest `seq` seen (from `last_seq` and the rows held) and is passed back as `--since` |
| tab count is the rows held, a lower bound (S5:147-148) | Events chip count = `events.length + eventsDropped` (RunDetailScreen L45, L257) |
| `runsChanged(ids)` (S5:98) | `runsNudged(ids)` → `nudgeEvents(ids)` |
| `e` toggles "while no modal or text field has the keys" (S5:139-140) | `handleEventsKey`: only a bare `e` with no modifier at all, only in view mode `run`, and not under a modal or the open dropdown. It calls `app.runs.toggleDetailTab()`. |

Do not document anything from the left column.

## docs/architecture.md: what to add or correct

Keep the existing section order and the dense one-line bullet style. Extend the existing entries; do not write second copies of them.

1. **Domain helpers paragraph** (L173-180, after the `runs.js` entry): add `runEvents.js`, the run events timeline. It is pure, never throws, and reads no clock and no time zone.
   - `eventRow(event, titles, utcOffsetMinutes)` gives a row or null. Only the five `*_upsert` events give a row; other events and unknown payload keys are ignored.
   - Row fields: `seq`, `time` (`HH:MM:SS` of the UTC `ts` at the given offset), `level`, `label`, `status`, `glyph`, `duration`, `detail`, `card`, `phase`, `attempt`.
   - `label`: the title from `titles`, else `Runs.shortId`; a phase adds ` <phase>`, an attempt adds ` <phase>.<n>`; a run reads `run <word>`, where `stopped` reads `paused` and both `cancelled` and `canceled` read `cancelled`.
   - `durationText(seconds)`: `S.Ss` below 60, else `Mm SSs`, else `""`.
   - `foldEvents(rows, events, cap)` as in the table above.
   - `filterRows(rows, filter)`: `Phases` keeps the phase and attempt levels; `Failures` keeps `failed`, `escalated`, `gate_failed`, `schema_invalid` and `harness_error` at any level; anything else keeps every row.
2. **`core/backend/runs/` paragraph** (L196): it already has a `runs-events.py` sentence. Check it word by word against the helper's docstring and correct it in place:
   - Its error types are `CorruptJournal`, `AmBadOutput`, `AmMissing`, `HelperError` and `Usage`, plus am's own `ok: false` envelope unchanged.
   - am's envelope `ok` decides, not am's exit code.
   - Each am call has a 60 s timeout.
   - `Usage` exits 2; every other path exits 0.
   - `--tail` never reaches am.
3. **RunStore bullet** (L83-92): add an events paragraph after the `logsRunner` paragraph (L90). Cover:
   - The state: `titles`, `events`, `eventsDropped`, `eventsCursor`, `eventsStatus` (`idle|loading|ok|error`), `eventsError`, and `eventsFilter` (`All|Phases|Failures`; the store never sets it, and the screen does). Also `detailTab` (`output|events`), with `setDetailTab` and `toggleDetailTab`.
   - `eventsRunner` is a `HelperRunner` guarded by the selected run id, so a reply for a run that is no longer selected is dropped.
   - Any change to `selectedRunId` empties the events, resets `eventsDropped`, `eventsCursor` and `eventsError`, drops the queued follow-up, and sets `detailTab` to `output`. With a run selected it then fetches `RUN --tail 200`. With none, it cancels the fetch in flight and the status goes to `idle`.
   - `refreshEvents()` fetches `--tail 200` again.
   - While `active`, a `runsNudged(ids)` that names the selected run fetches `RUN --since eventsCursor` (with cursor 0 it fetches `--tail 200` instead). If a fetch is already in flight, exactly one follow-up is queued and runs after it, never instead of it. `stopLive` drops the queued follow-up, and a project switch leaves the events alone.
   - A reply's events become `eventRow` rows. They are labelled by `eventTitles()`: `titles` (App's open-project card map) completed by the selected run's tree story titles. Each row uses the local UTC offset, and the rows are folded with a cap of 500.
   - `eventsDropped` after a `--tail` fetch is `total - received`, less the rows already held below the reply, plus the rows the cap dropped. After a `--since` fetch it adds the rows the cap dropped.
   - A reply whose `last_seq` is below `eventsCursor` keeps the rows. A failure keeps the rows and sets `error` with `Runs.errorText`.
   - **State this explicitly:** a subtask of a project that is not open shows a short card id, because neither `titles` nor `am status` gives a subtask title.
4. **Other `ui/` pieces / Shortcuts** (L94-110): add `handleEventsKey`. A bare `e` with no modifier, on Run detail only, toggles Output / Events (`toggleDetailTab`). Under a modal or the open dropdown, and on every other screen, the letter is left alone.
5. **Shared components list** (L114-155): add `EventsPane`. It is presentation only and covers:
   - Its props are `rows`, `filter`, `dropped`, `status`, `errorText`, `errorMessage` and `maxListHeight`. `following` is read-only.
   - The All / Phases / Failures chips emit `filterRequested`.
   - Below the chips it shows `… N earlier events`, `Loading events…`, `No events yet.` or `No events match the filter.`.
   - An error headline sits above the rows held, with the raw message behind **Details**.
   - Failure rows use the `urgent` tint and the `‼` glyph from `runGlyphs.js`.
   - The pane scrolls itself: its own list scrolls past `maxListHeight`, and a wheel at the list's ends reaches the enclosing Flickable.
   - While the list is at its bottom, new rows keep it there. Otherwise **Jump ↓** returns it to the bottom.
   - Clicking a row that names an attempt (non-empty card and phase, attempt > 0) emits `attemptRequested`; other rows do nothing.
6. **Run screens paragraph** (L165): extend the `RunDetailScreen` sentence.
   - The bottom area has two tabs chosen by `Output` / `Events` chips (`app.runs.detailTab`). The Events chip count is the rows held plus `eventsDropped`.
   - Events is an `EventsPane` over `app.runs.events`. Its filter chips set `app.runs.eventsFilter`.
   - A row naming an attempt calls `selectAttempt` and then switches to Output.
7. **Refresh model** (L171): add that events are fetched on a selection, on `refreshEvents()`, and on a nudge naming the selected run. They are never fetched on a timer, and the only watch process is the store's existing one.
8. **Fixtures / tests** (L246-258): change nothing unless a sentence there is false against the code. `events.json` is an `am events` page; leave it.
9. **No cost or tokens:** state once, in the RunStore or runEvents text, that rows carry no cost or token figures because am no longer journals them (S5:33-35).

## README.md: what to add or correct

Keep every existing sentence that is still true.

- **Runs entry, Run detail part** (L154, after the output-pane sentence):
  - Run detail's bottom area has **Output** and **Events** tabs. A bare `e` toggles them, and every run selection starts on Output.
  - **Events** is the run's timeline, newest at the bottom: time, state glyph, label (title or short card id, phase, `phase.attempt`), status, an attempt's duration, and a failed phase's detail. It holds at most 500 rows; the tab count includes the events not held, shown as `… N earlier events`.
  - The All / Phases / Failures chips filter the list.
  - It updates live while the panel is open. The list has its own scrolling and follows new rows while it is at its bottom; **Jump ↓** returns to the bottom.
  - Clicking an attempt row opens that attempt's output.
  - Cost and tokens are not shown, because `am` no longer journals them.
  - Subtasks of a project that is not open show short card ids.
  - A failed fetch shows `Events unreadable.` with **Details**, and the pane keeps its rows.
- **am commands paragraph** (L235):
  - Add `am watch RUN [--since SEQ]` (one-shot, no `--follow`) to the list of am commands run.
  - Add `runs/runs-events.py` to the helper list.

## Error paths the docs must state (from the code)

- An `am` refusal, `CorruptJournal`, `AmBadOutput`, `AmMissing`, `HelperError` or timeout: `eventsStatus` becomes `error` and `eventsError` holds the message. The rows held are kept, and the pane shows `Events unreadable.` with the message behind **Details**.
- A reply for a run that is no longer selected is dropped.
- A reply older than the cursor keeps the rows.
- Unknown events and unknown payload keys are ignored.

## Tests

This card changes no behaviour, so it adds no new behaviour tests and no new files under `tests/`. The card's "TDD: tests first" is met by the existing gate. This follows the precedent of docs card 5.4 (`task-5-4-docs-runs-monitor-0fa83ffa-design.md`, Tests). A grep-for-names doc test would pin wording, not behaviour.

- **Gate (existing, unchanged), tier: full suite.** `bash tests/run.sh` must be fully green. That includes:
  - `tests/architecture/test_layers.py`, which shows the edit moved no import across layers.
  - `tests/architecture/test_icon_glyphs.py`. Glyphs in `.md` files are outside its `ui/`/`vendor/` scope, so the docs may use `‼` and `↓`.
- **Already-passing tests that pin the facts the docs state.** Cite them; do not modify them.
  - `tests/core/domain/tst_run_events.qml` (domain tier): eventRow, foldEvents and filterRows.
  - `tests/core/backend/runs/test_runs_events.py` (backend pytest tier): the helper's argv, output line and errors.
  - `tests/core/stores/tst_run_store.qml` (store tier): selection reset, tail/since, follow-up, cap and eventsDropped.
  - `tests/ui/components/tst_events_pane.qml` (component tier): the pane.
  - `tests/ui/tst_runs_flow.qml` (UI-flow tier): the tabs and the `e` key.
- **Manual review checks** (not automated):
  - Every symbol, path, string and option the new text names exists in the code.
  - Nothing from the left column of the S5-vs-built table appears.
  - No sentence says that a screen or component imports `core/stores`.

## Out of scope

- Any code, test or fixture change.
- Backward paging / Load earlier.
- Cost and token display.
- Subtask titles for projects that are not open.
- Changing the helper to `am events`.
- Rewording unrelated doc sections.
- S5 itself: it stays as written (status "proposed"). This card does not amend it.
- Work of sibling cards in story 55a2dc57 (1.x–4.3), which are already built.

## Notes for the planner

One task is enough: edit both files, then run the gate.

- Global constraint: docstrings and comments state the contract only, with no narrative (card). The same applies to the doc prose: state what the code does, never what it will do.
- Commit as `docs: describe the run events timeline in architecture and README`.
