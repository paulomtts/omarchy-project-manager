# 4.4 Docs: run events timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `docs/architecture.md` and `README.md` describe the run events timeline exactly as built in cards 1.x-4.3: `runEvents.js`, `runs-events.py`, RunStore's events state and `detailTab`, `EventsPane`, Run detail's Output / Events tabs and the bare `e` key.

**Architecture:** Docs only. One task inserts or replaces named passages of the two files with text given verbatim in this plan; every sentence was traced to a source line at HEAD `f36a3a2`. No QML, JS, Python, test or fixture changes. Prose has no unit test, so the RED step is a `grep` that finds none of the new names (and still finds the stale `runs-events.py` wording), and the GREEN step is the same `grep` after the edits plus a negative `grep` for every S5-only name; the full suite (`bash tests/run.sh`) is the regression gate.

**Tech Stack:** Markdown; `grep`; `bash tests/run.sh` (pytest plus the QML tests).

**Spec:** `docs/superpowers/specs/4-4-docs-run-events-8ecb8330.md`. The full text is copied below.

## Spec (verbatim)

> # 4.4 Docs: run events timeline (card 8ecb8330)
>
> Parent story: 55a2dc57. Milestone spec: `docs/superpowers/specs/2026-10-05-run-events-timeline-design.md` (cited below as **S5:line**). Blocked by 62e53e6e (4.3, the Events tab and the `e` key), which is merged into this branch (`f36a3a2`).
>
> ## Scope
>
> Docs only. Edit `docs/architecture.md` and `README.md` so they describe the run events timeline **as built** in cards 1.x–4.3. Change no QML, JS, Python, test or fixture file.
>
> Where S5 and the code disagree, the code wins. Before writing a sentence, read the file it is about. The sources are:
> - `core/domain/runEvents.js`
> - `core/backend/runs/runs-events.py`
> - `core/stores/RunStore.qml`: the events state at L124-139, `stopLive` at ~L395, `onSelectedRunIdChanged` .. `foldReply` at ~L866-1048, `eventsRunner` at ~L1993, and `eventsState` at ~L2148
> - `core/stores/App.qml` (`titles:` at ~L112)
> - `ui/components/EventsPane.qml`
> - `ui/screens/RunDetailScreen.qml`
> - `ui/Shortcuts.qml` (`handleEventsKey`)
>
> ### Known S5-vs-built differences the docs must follow
>
> | S5 says | built (what the docs say) |
> |---|---|
> | helper runs `am events RUN [--after-seq] [--before-seq] [--tail] [--limit]`, prints `{ok, events, head}` (S5:44-47, 77-81) | `runs-events.py RUN [--since SEQ] [--tail N]` runs `am watch RUN` (plus `--since SEQ`), never `--follow`, `--repo-dir`, `--all`, `--since-seq` or `--pretty`; `--tail` is applied by the helper and never reaches am; prints `{ok, events, last_seq, total}` |
> | `mergeRows`, dedupe by `gseq` (S5:73) | `foldEvents(rows, events, cap)`: one row per `seq`, the last one taken wins, ascending, the lowest dropped past the cap (default 500), returns `{rows, dropped}` |
> | `rowGlyph` export (S5:74) | no such export; `eventRow` sets `glyph` from `Runs.glyphStateOf(status)`; EventsPane draws the `‼` glyph on any failure row |
> | `eventsHasEarlier`, `eventsOldestSeq`, a **Load earlier** control, `--before-seq` paging (S5:82-84, 96-97, 135) | none of these exist. `eventsDropped` counts the run's events that are not held. The pane shows `… N earlier events` when it is above 0. Nothing is paged backward. |
> | cursor is the highest `gseq` (S5:83) | `eventsCursor` is the highest `seq` seen (from `last_seq` and the rows held) and is passed back as `--since` |
> | tab count is the rows held, a lower bound (S5:147-148) | Events chip count = `events.length + eventsDropped` (RunDetailScreen L45, L257) |
> | `runsChanged(ids)` (S5:98) | `runsNudged(ids)` → `nudgeEvents(ids)` |
> | `e` toggles "while no modal or text field has the keys" (S5:139-140) | `handleEventsKey`: only a bare `e` with no modifier at all, only in view mode `run`, and not under a modal or the open dropdown. It calls `app.runs.toggleDetailTab()`. |
>
> Do not document anything from the left column.
>
> ## docs/architecture.md: what to add or correct
>
> Keep the existing section order and the dense one-line bullet style. Extend the existing entries; do not write second copies of them.
>
> 1. **Domain helpers paragraph** (L173-180, after the `runs.js` entry): add `runEvents.js`, the run events timeline. It is pure, never throws, and reads no clock and no time zone.
>    - `eventRow(event, titles, utcOffsetMinutes)` gives a row or null. Only the five `*_upsert` events give a row; other events and unknown payload keys are ignored.
>    - Row fields: `seq`, `time` (`HH:MM:SS` of the UTC `ts` at the given offset), `level`, `label`, `status`, `glyph`, `duration`, `detail`, `card`, `phase`, `attempt`.
>    - `label`: the title from `titles`, else `Runs.shortId`; a phase adds ` <phase>`, an attempt adds ` <phase>.<n>`; a run reads `run <word>`, where `stopped` reads `paused` and both `cancelled` and `canceled` read `cancelled`.
>    - `durationText(seconds)`: `S.Ss` below 60, else `Mm SSs`, else `""`.
>    - `foldEvents(rows, events, cap)` as in the table above.
>    - `filterRows(rows, filter)`: `Phases` keeps the phase and attempt levels; `Failures` keeps `failed`, `escalated`, `gate_failed`, `schema_invalid` and `harness_error` at any level; anything else keeps every row.
> 2. **`core/backend/runs/` paragraph** (L196): it already has a `runs-events.py` sentence. Check it word by word against the helper's docstring and correct it in place:
>    - Its error types are `CorruptJournal`, `AmBadOutput`, `AmMissing`, `HelperError` and `Usage`, plus am's own `ok: false` envelope unchanged.
>    - am's envelope `ok` decides, not am's exit code.
>    - Each am call has a 60 s timeout.
>    - `Usage` exits 2; every other path exits 0.
>    - `--tail` never reaches am.
> 3. **RunStore bullet** (L83-92): add an events paragraph after the `logsRunner` paragraph (L90). Cover:
>    - The state: `titles`, `events`, `eventsDropped`, `eventsCursor`, `eventsStatus` (`idle|loading|ok|error`), `eventsError`, and `eventsFilter` (`All|Phases|Failures`; the store never sets it, and the screen does). Also `detailTab` (`output|events`), with `setDetailTab` and `toggleDetailTab`.
>    - `eventsRunner` is a `HelperRunner` guarded by the selected run id, so a reply for a run that is no longer selected is dropped.
>    - Any change to `selectedRunId` empties the events, resets `eventsDropped`, `eventsCursor` and `eventsError`, drops the queued follow-up, and sets `detailTab` to `output`. With a run selected it then fetches `RUN --tail 200`. With none, it cancels the fetch in flight and the status goes to `idle`.
>    - `refreshEvents()` fetches `--tail 200` again.
>    - While `active`, a `runsNudged(ids)` that names the selected run fetches `RUN --since eventsCursor` (with cursor 0 it fetches `--tail 200` instead). If a fetch is already in flight, exactly one follow-up is queued and runs after it, never instead of it. `stopLive` drops the queued follow-up, and a project switch leaves the events alone.
>    - A reply's events become `eventRow` rows. They are labelled by `eventTitles()`: `titles` (App's open-project card map) completed by the selected run's tree story titles. Each row uses the local UTC offset, and the rows are folded with a cap of 500.
>    - `eventsDropped` after a `--tail` fetch is `total - received`, less the rows already held below the reply, plus the rows the cap dropped. After a `--since` fetch it adds the rows the cap dropped.
>    - A reply whose `last_seq` is below `eventsCursor` keeps the rows. A failure keeps the rows and sets `error` with `Runs.errorText`.
>    - **State this explicitly:** a subtask of a project that is not open shows a short card id, because neither `titles` nor `am status` gives a subtask title.
> 4. **Other `ui/` pieces / Shortcuts** (L94-110): add `handleEventsKey`. A bare `e` with no modifier, on Run detail only, toggles Output / Events (`toggleDetailTab`). Under a modal or the open dropdown, and on every other screen, the letter is left alone.
> 5. **Shared components list** (L114-155): add `EventsPane`. It is presentation only and covers:
>    - Its props are `rows`, `filter`, `dropped`, `status`, `errorText`, `errorMessage` and `maxListHeight`. `following` is read-only.
>    - The All / Phases / Failures chips emit `filterRequested`.
>    - Below the chips it shows `… N earlier events`, `Loading events…`, `No events yet.` or `No events match the filter.`.
>    - An error headline sits above the rows held, with the raw message behind **Details**.
>    - Failure rows use the `urgent` tint and the `‼` glyph from `runGlyphs.js`.
>    - The pane scrolls itself: its own list scrolls past `maxListHeight`, and a wheel at the list's ends reaches the enclosing Flickable.
>    - While the list is at its bottom, new rows keep it there. Otherwise **Jump ↓** returns it to the bottom.
>    - Clicking a row that names an attempt (non-empty card and phase, attempt > 0) emits `attemptRequested`; other rows do nothing.
> 6. **Run screens paragraph** (L165): extend the `RunDetailScreen` sentence.
>    - The bottom area has two tabs chosen by `Output` / `Events` chips (`app.runs.detailTab`). The Events chip count is the rows held plus `eventsDropped`.
>    - Events is an `EventsPane` over `app.runs.events`. Its filter chips set `app.runs.eventsFilter`.
>    - A row naming an attempt calls `selectAttempt` and then switches to Output.
> 7. **Refresh model** (L171): add that events are fetched on a selection, on `refreshEvents()`, and on a nudge naming the selected run. They are never fetched on a timer, and the only watch process is the store's existing one.
> 8. **Fixtures / tests** (L246-258): change nothing unless a sentence there is false against the code. `events.json` is an `am events` page; leave it.
> 9. **No cost or tokens:** state once, in the RunStore or runEvents text, that rows carry no cost or token figures because am no longer journals them (S5:33-35).
>
> ## README.md: what to add or correct
>
> Keep every existing sentence that is still true.
>
> - **Runs entry, Run detail part** (L154, after the output-pane sentence):
>   - Run detail's bottom area has **Output** and **Events** tabs. A bare `e` toggles them, and every run selection starts on Output.
>   - **Events** is the run's timeline, newest at the bottom: time, state glyph, label (title or short card id, phase, `phase.attempt`), status, an attempt's duration, and a failed phase's detail. It holds at most 500 rows; the tab count includes the events not held, shown as `… N earlier events`.
>   - The All / Phases / Failures chips filter the list.
>   - It updates live while the panel is open. The list has its own scrolling and follows new rows while it is at its bottom; **Jump ↓** returns to the bottom.
>   - Clicking an attempt row opens that attempt's output.
>   - Cost and tokens are not shown, because `am` no longer journals them.
>   - Subtasks of a project that is not open show short card ids.
>   - A failed fetch shows `Events unreadable.` with **Details**, and the pane keeps its rows.
> - **am commands paragraph** (L235):
>   - Add `am watch RUN [--since SEQ]` (one-shot, no `--follow`) to the list of am commands run.
>   - Add `runs/runs-events.py` to the helper list.
>
> ## Error paths the docs must state (from the code)
>
> - An `am` refusal, `CorruptJournal`, `AmBadOutput`, `AmMissing`, `HelperError` or timeout: `eventsStatus` becomes `error` and `eventsError` holds the message. The rows held are kept, and the pane shows `Events unreadable.` with the message behind **Details**.
> - A reply for a run that is no longer selected is dropped.
> - A reply older than the cursor keeps the rows.
> - Unknown events and unknown payload keys are ignored.
>
> ## Tests
>
> This card changes no behaviour, so it adds no new behaviour tests and no new files under `tests/`. The card's "TDD: tests first" is met by the existing gate. This follows the precedent of docs card 5.4 (`task-5-4-docs-runs-monitor-0fa83ffa-design.md`, Tests). A grep-for-names doc test would pin wording, not behaviour.
>
> - **Gate (existing, unchanged), tier: full suite.** `bash tests/run.sh` must be fully green. That includes:
>   - `tests/architecture/test_layers.py`, which shows the edit moved no import across layers.
>   - `tests/architecture/test_icon_glyphs.py`. Glyphs in `.md` files are outside its `ui/`/`vendor/` scope, so the docs may use `‼` and `↓`.
> - **Already-passing tests that pin the facts the docs state.** Cite them; do not modify them.
>   - `tests/core/domain/tst_run_events.qml` (domain tier): eventRow, foldEvents and filterRows.
>   - `tests/core/backend/runs/test_runs_events.py` (backend pytest tier): the helper's argv, output line and errors.
>   - `tests/core/stores/tst_run_store.qml` (store tier): selection reset, tail/since, follow-up, cap and eventsDropped.
>   - `tests/ui/components/tst_events_pane.qml` (component tier): the pane.
>   - `tests/ui/tst_runs_flow.qml` (UI-flow tier): the tabs and the `e` key.
> - **Manual review checks** (not automated):
>   - Every symbol, path, string and option the new text names exists in the code.
>   - Nothing from the left column of the S5-vs-built table appears.
>   - No sentence says that a screen or component imports `core/stores`.
>
> ## Out of scope
>
> - Any code, test or fixture change.
> - Backward paging / Load earlier.
> - Cost and token display.
> - Subtask titles for projects that are not open.
> - Changing the helper to `am events`.
> - Rewording unrelated doc sections.
> - S5 itself: it stays as written (status "proposed"). This card does not amend it.
> - Work of sibling cards in story 55a2dc57 (1.x–4.3), which are already built.
>
> ## Notes for the planner
>
> One task is enough: edit both files, then run the gate.
>
> - Global constraint: docstrings and comments state the contract only, with no narrative (card). The same applies to the doc prose: state what the code does, never what it will do.
> - Commit as `docs: describe the run events timeline in architecture and README`.

---

## Global Constraints

- Docs only: edit `docs/architecture.md` and `README.md`; change no QML, JS, Python, test or fixture file, and do not edit S5 or any file under `docs/superpowers/`.
- Where S5 and the code disagree, the code wins; nothing from the left column of the spec's S5-vs-built table appears (`am events RUN [--after-seq] ...`, `{ok, events, head}`, `mergeRows`, `rowGlyph`, `eventsHasEarlier`, `eventsOldestSeq`, **Load earlier**, `--before-seq`, a `gseq` cursor, `runsChanged`).
- Keep the existing section order and the dense one-line style of `docs/architecture.md`; extend existing entries, never write a second copy of one. `docs/architecture.md` writes ` -- ` for a dash.
- Keep every existing README sentence that is still true.
- Doc prose states what the code does, never what it will do; no narrative.
- No sentence says a screen or component imports `core/stores`.
- Cost and tokens: stated once in `docs/architecture.md` (the `runEvents.js` entry) and once in the README.
- `bash tests/run.sh` must be fully green.
- Commit message: `docs: describe the run events timeline in architecture and README`.

## Review Focus

1. A reader looking for a way to page back to older events (S5's **Load earlier** / `--before-seq`): the docs must say nothing is paged backward and only `… N earlier events` is shown -- pinned by Step 7's negative grep and Step 6's `earlier events` grep.
2. A user pressing `e` with Shift or Ctrl, or under a modal / the open dropdown, or on another screen, expecting a toggle: the docs must say "a bare `e`, with no modifier at all", Run detail only -- pinned by Step 6's `no modifier at all` grep.
3. A user expecting cost / token figures in the timeline: the docs must say rows carry none because am no longer journals them -- pinned by Step 6's `no longer journals` grep (architecture and README).
4. A user seeing short card ids for a subtask of a project that is not open and reading it as a bug: both files must say so -- pinned by Step 6's `short card id` grep.
5. A failed events fetch read as "the pane empties": the docs must say the rows are kept and `Events unreadable.` shows with **Details** -- pinned by Step 6's `Events unreadable` and `keeps the rows` greps.

---

### Task 1: Describe the run events timeline in `docs/architecture.md` and `README.md`

**Files:**
- Modify: `docs/architecture.md` (L83 RunStore header, after L90 `logsRunner`, L102-104 Shortcuts, after L148 `PhaseTimeline`, L165 run screens, L169 `runGlyphs.js` readers, L171 refresh model, L180 domain helpers, L196 `runs-events.py`)
- Modify: `README.md` (L154 Runs entry, L235 am commands)
- Test: none added; gate `bash tests/run.sh` (already-passing `tests/core/domain/tst_run_events.qml`, `tests/core/backend/runs/test_runs_events.py`, `tests/core/stores/tst_run_store.qml`, `tests/ui/components/tst_events_pane.qml`, `tests/ui/tst_runs_flow.qml` pin the facts stated)

**Interfaces:**
- Consumes: the code at `f36a3a2` -- `core/domain/runEvents.js` (`eventRow`, `durationText`, `foldEvents`, `filterRows`), `core/backend/runs/runs-events.py`, `core/stores/RunStore.qml` (`titles`, `events`, `eventsDropped`, `eventsCursor`, `eventsStatus`, `eventsError`, `eventsFilter`, `detailTab`, `setDetailTab`, `toggleDetailTab`, `selectEvents`, `refreshEvents`, `fetchEvents`, `nudgeEvents`, `fetchNewEvents`, `followUpEvents`, `eventTitles`, `applyEvents`, `foldReply`, `eventsRunner`, `stopLive`), `core/stores/App.qml` (`titles:`), `ui/components/EventsPane.qml`, `ui/screens/RunDetailScreen.qml`, `ui/Shortcuts.qml` (`handleEventsKey`).
- Produces: doc text only; nothing downstream consumes it.

Every edit below is an exact replacement: find OLD (it occurs exactly once in the file, checked at `f36a3a2`) and replace it with NEW, e.g. with the Edit tool. Before writing each edit, open the source file it describes and confirm each fact; if a fact is false against the code, the code wins and the edit is corrected to match it.

- [ ] **Step 1: RED -- the new names are absent and the stale helper sentence is present**

Run:

```bash
for p in 'runEvents.js' 'EventsPane' 'handleEventsKey' 'detailTab' 'eventsDropped' 'Events unreadable'; do printf '%-18s arch=%s readme=%s\n' "$p" "$(grep -c -- "$p" docs/architecture.md)" "$(grep -c -- "$p" README.md)"; done
grep -c 'is a one-shot `am watch RUN \[--since SEQ\]` read (no `--follow`, no `--repo-dir`)' docs/architecture.md
grep -c 'runs-events.py' README.md
```

Expected: every `arch=` and `readme=` count is `0`; the stale-sentence count is `1`; the README `runs-events.py` count is `0`.

- [ ] **Step 2: Edit `docs/architecture.md` -- `runEvents.js` in the domain helpers paragraph (L180)**

OLD:

```markdown
reports closed (merged, canceled, archived);
Python: `core/backend/common`
```

NEW:

```markdown
reports closed (merged, canceled, archived); `runEvents.js`, the run events timeline: pure JS, never throws, and reads no clock and no time zone. `eventRow(event, titles, utcOffsetMinutes)` gives one row for a `run_upsert`, `story_upsert`, `subtask_upsert`, `phase_upsert` or `attempt_upsert` event and null for anything else; every other event and every unknown payload key is ignored. A row is `{seq, time, level, label, status, glyph, duration, detail, card, phase, attempt}`: `time` the `HH:MM:SS` of the UTC `ts` at the given offset (`""` when `ts` is not `YYYY-MM-DDTHH:MM:SS[.f]Z`), `level` `run`, `story`, `subtask`, `phase` or `attempt`, `label` the node's title from `titles` (story id or card id -> title), else `Runs.shortId`, a phase adding ` <phase>` and an attempt ` <phase>.<n>` (` <phase>` when its number is unknown), a run reading `run <word>` (`stopped` reads `paused`, `cancelled` and `canceled` both read `cancelled`), `status` the payload's as written, `glyph` `Runs.glyphStateOf(status)`, `duration` an attempt's `durationText(payload.duration)`, `detail` a phase's `payload.detail`; rows carry no cost or token figures, because am no longer journals them. `durationText(seconds)` is `S.Ss` below 60, else `Mm SSs`, and `""` for anything but a finite non-negative number. `foldEvents(rows, events, cap)` keeps one row per `seq`, the last one taken winning (rows first, then events), ascending by `seq`, and drops the lowest past `cap` (500 when missing, not finite or negative); it returns `{rows, dropped}`, `dropped` the count the cap removed. `filterRows(rows, filter)`: `Phases` keeps the phase and attempt rows, `Failures` the rows whose status is `failed`, `escalated`, `gate_failed`, `schema_invalid` or `harness_error` at any level, and anything else keeps every row;
Python: `core/backend/common`
```

- [ ] **Step 3: Edit `docs/architecture.md` -- correct the `runs-events.py` sentence in place (L196)**

OLD:

```markdown
`runs-events.py RUN [--since SEQ] [--tail N]` is a one-shot `am watch RUN [--since SEQ]` read (no `--follow`, no `--repo-dir`) that prints `{ok, events, last_seq, total}` -- `total` the matched count, `events` at most the last N with `--tail`, `last_seq` the highest `seq` of every matched event (the `--since` value, or 0, when none) -- or `{ok: false, error}`: am's refusal unchanged, `CorruptJournal` (am exit 3 without an envelope), `AmBadOutput`, `AmMissing`, `HelperError` (60 s timeout); `Usage` exits 2, every other path 0.
```

NEW:

```markdown
`runs-events.py RUN [--since SEQ] [--tail N]` is a one-shot `am watch RUN` read, plus `--since SEQ` when given, with a 60 s timeout -- never `--follow`, `--repo-dir`, `--all`, `--since-seq` or `--pretty`; `--tail` never reaches am, the helper applies it. am's envelope `ok` decides, not am's exit code. It prints exactly one JSON line: `{ok: true, events, last_seq, total}` -- `total` the number of events am printed, `events` those events unchanged in am's order (only the last N with `--tail N`), `last_seq` the highest `seq` of them (the `--since` value, or 0, when there are none) -- or `{ok: false, error}`: am's own `ok: false` envelope unchanged (`UnknownRunError`, `StoreBusyError`, ...), `CorruptJournal` (am exited 3 without a usable envelope), `AmBadOutput` (no usable envelope, or an ok one without a `data.events` list or with an event lacking an integer `seq`), `AmMissing`, `HelperError` (any unexpected failure, a timeout included) or `Usage` (no RUN, an empty or `-`-prefixed RUN, a second positional, an unknown, repeated or valueless option, a SEQ that is not ASCII digits, an N that is not ASCII digits or is 0). `Usage` exits 2; every other path exits 0.
```

- [ ] **Step 4: Edit `docs/architecture.md` -- RunStore: `titles` in the header (L83) and an events paragraph after `logsRunner` (L90)**

Edit 4a. OLD:

```markdown
`backendDir` and `active` (App's `panelOpen`
```

NEW:

```markdown
`backendDir`, `titles` (the open project's card id -> title map, from the board's `cardMap`) and `active` (App's `panelOpen`
```

Edit 4b. OLD:

```markdown
another attempt starts from an empty pane.
  Run controls (S2 4.1):
```

NEW:

```markdown
another attempt starts from an empty pane.
  Run detail's events: `events` holds the selected run's `RunEvents.eventRow` rows, ascending by `seq`, at most 500; `eventsDropped` counts the run's events that are not held; `eventsCursor` is the highest `seq` seen (the replies' `last_seq` and the rows held), passed back as `--since`; `eventsStatus` is `idle`, `loading`, `ok` or `error`, and `eventsError` says why the last fetch failed (`""` after a good one and after a reset); `eventsFilter` is `All`, `Phases` or `Failures` -- the store never sets it, the screen does. `detailTab` (`output` or `events`) is Run detail's bottom area, changed by `setDetailTab(tab)` (any other value is refused and returns false) and `toggleDetailTab()`. `eventsRunner` is a `HelperRunner` (`runs-events.py`) guarded by the run id a fetch was launched for, so a reply for a run that is no longer selected is dropped. Any change of `selectedRunId` empties `events`, resets `eventsDropped`, `eventsCursor` and `eventsError`, drops the queued follow-up and sets `detailTab` to `output`; with a run selected it then fetches `RUN --tail 200`, and with none it cancels the fetch in flight and `eventsStatus` goes to `idle`. `refreshEvents()` fetches `--tail 200` again, the rows staying until the reply. While `active`, a `runsNudged(ids)` that names the selected run (`nudgeEvents`) fetches `RUN --since eventsCursor` (`--tail 200` while the cursor is 0); if a fetch is already in flight, exactly one follow-up is queued and runs after it, never instead of it. `stopLive` drops the queued follow-up (a fetch in flight runs to its end and is applied), and a project switch leaves the events alone. A good reply's events become `eventRow` rows labelled by `eventTitles()` -- `titles` completed by the selected run's tree story titles -- at the local UTC offset, folded into the rows held by `foldEvents` with a cap of 500. After a `--tail` fetch `eventsDropped` is `total - received`, less the rows already held below the reply's lowest `seq`, at least 0, plus the rows the cap dropped; after a `--since` fetch it grows by the rows the cap dropped. A reply whose `last_seq` is below `eventsCursor` keeps the rows. A failure -- am's refusal, `CorruptJournal`, `AmBadOutput`, `AmMissing`, `HelperError` (a timeout included) or a reply that cannot be read -- keeps the rows, `eventsDropped` and `eventsCursor`, sets `eventsStatus` to `error` and puts the `Runs.errorText` sentence in `eventsError` (`The events snapshot gave no usable result (exit N).` for an unreadable reply). A subtask of a project that is not open shows a short card id, because neither `titles` nor `am status` gives a subtask title.
  Run controls (S2 4.1):
```

- [ ] **Step 5: Edit `docs/architecture.md` -- Shortcuts, `EventsPane`, run screens, glyph readers and refresh model**

Edit 5a (Shortcuts, L102-104). OLD:

```markdown
dropdown; `modalOpen()` is the one guard the chords, the run keys and `d` obey,
and an open dispatch counts as a modal;
```

NEW:

```markdown
dropdown; `handleEventsKey` makes a bare `e`, with no modifier at all, toggle
Run detail's bottom area between Output and Events (`app.runs.toggleDetailTab()`)
and leaves the letter alone under a modal or the open dropdown and on every
other screen; `modalOpen()` is the one guard the chords, the run keys, `d` and
`e` obey, and an open dispatch counts as a modal;
```

Edit 5b (shared components, after the `PhaseTimeline` entry, L148). OLD:

```markdown
no colour-only state, no animation),
`RunIndicator` (
```

NEW:

```markdown
no colour-only state, no animation),
`EventsPane` (one run's event timeline; presentation only: the owner passes `rows` (`RunEvents.eventRow` rows, ascending, unfiltered), `filter`, `dropped`, `status`, `errorText` (default `Events unreadable.`), `errorMessage`, `maxListHeight` and `theme`, and `following` is read-only. All / Phases / Failures chips emit `filterRequested(filter)`; the pane shows `RunEvents.filterRows(rows, filter)` and never assigns `filter`. Below the chips it shows `… N earlier events` while `dropped` is above 0, and `Loading events…`, `No events yet.` or `No events match the filter.` when no row is shown. In `error` the `errorText` headline sits above the rows held, with the raw `errorMessage` behind **Details**. A row shows its time, glyph, label, status, duration and detail; a failure row (`filterRows`' `Failures`) is tinted `urgent` with the `‼` glyph from `runGlyphs.js`. The pane scrolls itself: its list scrolls past `maxListHeight`, and a wheel at the list's ends reaches the enclosing Flickable. While the list is at its bottom (`following`), new rows keep it there; otherwise it keeps its scroll position and **Jump ↓** returns it to the bottom. A click on a row that names an attempt (non-empty `card` and `phase`, `attempt` above 0) emits `attemptRequested(card, phase, attempt)`; other rows do nothing),
`RunIndicator` (
```

Edit 5c (run screens, L165). OLD:

```markdown
and the output pane: one attempt's `logsText`, labelled `snapshot <age> ago` plus `· last 200 lines` when it was cut, never a live tail, with a Refresh button and `logsError` in `urgent`.
```

NEW:

```markdown
and a bottom area of two tabs chosen by `Output` / `Events` chips (`app.runs.detailTab`, set through `setDetailTab`; the Events chip counts the rows held plus `eventsDropped`). Output is the output pane: one attempt's `logsText`, labelled `snapshot <age> ago` plus `· last 200 lines` when it was cut, never a live tail, with a Refresh button and `logsError` in `urgent`. Events is an `EventsPane` over `app.runs.events` (with `eventsDropped`, `eventsStatus` and `eventsError`); its filter chips set `app.runs.eventsFilter`, and a row naming an attempt calls `selectAttempt(card, phase, attempt)` and then switches to Output (`setDetailTab("output")`).
```

Edit 5d (glyph readers, L169). OLD:

```markdown
`RunMark`, `Sidebar` and the run screens
```

NEW:

```markdown
`RunMark`, `EventsPane`, `Sidebar` and the run screens
```

Edit 5e (refresh model, L171). OLD:

```markdown
(a one-shot snapshot or logs fetch already in flight runs to its end)
```

NEW:

```markdown
(a one-shot snapshot, logs or events fetch already in flight runs to its end)
```

Edit 5f (refresh model, L171). OLD:

```markdown
Logs are fetched on demand, and `Pulse` animates
```

NEW:

```markdown
Logs are fetched on demand; the selected run's events are fetched on a selection, on `refreshEvents()` and on a nudge naming that run, never on a timer, and the store's one watch is the only watch process; `Pulse` animates
```

- [ ] **Step 6: Edit `README.md` -- Runs entry (L154) and am commands (L235)**

Edit 6a. OLD:

```markdown
It is never a live tail: **Refresh** fetches it again, and a failed fetch says why and keeps the last text.
```

NEW:

```markdown
It is never a live tail: **Refresh** fetches it again, and a failed fetch says why and keeps the last text. Run detail's bottom area has **Output** and **Events** tabs; a bare `e` (no modifier) toggles them, and every run selection starts on Output. **Events** is the run's timeline, newest at the bottom: each row shows the time, a state glyph, a label (the title or a short card id, then the phase, or `phase.attempt` for an attempt), the status, an attempt's duration and a phase's detail. It holds at most 500 rows; the tab's count includes the events not held, shown as `… N earlier events` above the list. **All**, **Phases** and **Failures** chips filter the list. It updates live while the panel is open; the list scrolls on its own and follows new rows while it is at its bottom, and **Jump ↓** returns it there. Clicking an attempt row opens that attempt's output. Cost and tokens are not shown, because `am` no longer journals them, and subtasks of a project that is not open show a short card id. A failed fetch shows `Events unreadable.` with **Details**, and the pane keeps its rows.
```

Edit 6b. OLD:

```markdown
`am watch --all-projects --follow` and `am logs`)
```

NEW:

```markdown
`am watch --all-projects --follow`, `am logs` and the one-shot `am watch RUN [--since SEQ]`, never with `--follow`)
```

Edit 6c. OLD:

```markdown
`runs/runs-watch.py`, `runs/runs-logs.py`)
```

NEW:

```markdown
`runs/runs-watch.py`, `runs/runs-logs.py`, `runs/runs-events.py`)
```

- [ ] **Step 7: GREEN -- the new facts are present, the stale and S5-only text is absent**

Run:

```bash
for p in 'runEvents.js' 'EventsPane' 'handleEventsKey' 'detailTab' 'eventsDropped' 'Events unreadable' 'no modifier' 'no longer journals' 'short card id' 'earlier events' 'keeps the rows' 'keeps its rows'; do printf '%-18s arch=%s readme=%s\n' "$p" "$(grep -c -- "$p" docs/architecture.md)" "$(grep -c -- "$p" README.md)"; done
grep -c 'is a one-shot `am watch RUN \[--since SEQ\]` read (no `--follow`, no `--repo-dir`)' docs/architecture.md
grep -c 'runs-events.py' README.md
grep -n -E 'mergeRows|rowGlyph|eventsHasEarlier|eventsOldestSeq|Load earlier|before-seq|after-seq|runsChanged|\{ok, events, head\}' docs/architecture.md README.md
grep -c 'am events' docs/architecture.md README.md
grep -c 'gseq' docs/architecture.md
grep -c 'core/stores' docs/architecture.md README.md
```

Expected:
- `runEvents.js` arch=1 (the line carrying the domain entry); `EventsPane` arch>=3; `handleEventsKey` arch=1; `detailTab` arch>=2; `eventsDropped` arch>=2; `Events unreadable` arch=1 readme=1; `no modifier` arch=1 readme=1; `no longer journals` arch=1 readme=1; `short card id` arch=1 readme=1; `earlier events` arch=1 readme=1; `keeps the rows` arch=1; `keeps its rows` readme=1.
- the stale-sentence count is `0`; README `runs-events.py` count is `1`.
- the S5-only `grep -n -E` prints nothing (exit status 1).
- `am events`: `docs/architecture.md:1` (the untouched fixtures line), `README.md:0`.
- `gseq` still `4` (no new `gseq` text).
- `core/stores` still `docs/architecture.md:7` and `README.md:1` (no new import claim).

If any count differs, re-open the edit, fix it, and run this step again.

- [ ] **Step 8: Manual check against the code**

Open each source and confirm, name by name, that every symbol, path, string and option the new text names exists: `core/domain/runEvents.js` (`eventRow`, `durationText`, `foldEvents`, `filterRows`, `_DEFAULT_CAP = 500`, `_RUN_WORDS`, `_FAILURES`), `core/backend/runs/runs-events.py` (docstring, `AM_TIMEOUT = 60`, `parse_args`, `watch_argv`), `core/stores/RunStore.qml` L124-139, `stopLive`, L866-1048, `eventsRunner` (~L1993), `eventsState` (~L2148), `core/stores/App.qml` `titles:` (~L112), `ui/components/EventsPane.qml` (header comment, props, `"… " + pane.dropped + " earlier event"`, `Loading events…`, `No events yet.`, `No events match the filter.`, `Details`, `Jump ↓`), `ui/screens/RunDetailScreen.qml` L45, L251-258, L329-343, and `ui/Shortcuts.qml` `handleEventsKey`. Confirm no line of the S5 left column appears and no new sentence says a screen or component imports `core/stores`. Then run `git diff --stat` and confirm only `docs/architecture.md` and `README.md` changed.

Expected: `git diff --stat` lists exactly `README.md` and `docs/architecture.md`.

- [ ] **Step 9: Run the full gate**

Run: `timeout 1200 bash tests/run.sh`
Expected: exit 0, every pytest and QML test passing (including `tests/architecture/test_layers.py` and `tests/architecture/test_icon_glyphs.py`, whose glyph check covers only `ui/` and `vendor/`, so `‼` and `↓` in `.md` files are allowed).

- [ ] **Step 10: Commit**

```bash
git add docs/architecture.md README.md
git commit -m "docs: describe the run events timeline in architecture and README"
```
<!-- task-pipeline: validated -->
