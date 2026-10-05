# Run events timeline (S5) — design

Status: proposed. Builds on `2026-10-03-am-run-monitor-design.md` (S1: `RunStore`,
Run detail) and uses the same `am` interfaces. Lands AFTER
`2026-10-05-runs-all-projects-design.md` (S6): S6 removes the project guards from
`RunStore` and adds the changed-run signal this spec consumes, so the events state is
written once against the final store. Independent of S2/S3.

## Preconditions

- The run model reads the real `am status` shape (nested `stories[].subtasks[]`); the
  cards stop and escalate when `Runs.normalizeRun` of a recorded real payload has an empty
  tree. Fixtures for `am watch` are recorded from the installed `am`.

## Problem

The Runs screen renders the current state of a run (an `am status` snapshot). It
cannot answer "what happened, in what order, and when": there is no history, no
timestamps, no per-attempt duration, and no record of a phase that failed and was
retried. `am watch` has all of it, as the run's journal.

## Goal

Run detail gets an **Events** pane: a chronological timeline of the run's journal,
live while the run is going, for any run the Runs screen lists, including one started
from a terminal and one of a project that is not open (S6).

## Non-goals

- No cost or token figures: `am` no longer journals them. An attempt event carries
  `duration`, `exit_code`, `status`, the prompt/result/stdout paths and a
  `dispatch` (harness, model, role, cwd, timeout).
- No output text: the journal has none; the existing Output pane (`am logs`) stays.
- The plugin never reads the journal file. Only `am watch` is used.
- No second `am watch --follow` process: the store's one watch already says when the
  selected run changed.

## Data source (documented `am` interface)

`am watch RUN [--since SEQ]` (no `--follow`, no `--repo-dir`: it resolves by run id) prints
one envelope `{"ok": true, "data": {"events": [...]}}`. Each event is a journal line:

```
{seq, ts, run_id, event, story, card, phase, attempt, payload}
event ∈ run_upsert | story_upsert | subtask_upsert | phase_upsert | attempt_upsert
```

A status change is the same node recorded again, so a node appears several times.
`phase_upsert` carries `detail` when a phase failed. Statuses: run `started | done |
escalated | stopped | cancelled`, story and subtask `pending | started | done | stopped |
escalated`, phase `started | done | failed`, attempt `started | ok | schema_invalid |
gate_failed | harness_error`. Cursor by `seq` (the highest seen is the safe `--since`).
Ignore unknown events and unknown payload keys. A run that is `cancelled` today will be
`canceled` after the spelling migration: accept both everywhere.

## Architecture

Same layering as S1 (`docs/architecture.md`): pure domain, store, backend helper,
screens receive props.

- `core/domain/runEvents.js` (pure): `eventRow(event, titles, utcOffsetMinutes)`,
  `foldEvents(rows, events, cap)`, `filterRows(rows, filter)`, `rowGlyph`, `durationText`.
  `time` is the event's `ts` shifted by `utcOffsetMinutes` (the store passes the local
  offset; tests pass fixed offsets, so no test depends on the machine's time zone).
- `core/backend/runs/runs-events.py RUN [--since SEQ] [--tail N]`: runs `am watch`, prints one
  JSON line `{ok, events, last_seq, total}`. `total` is how many events matched; with
  `--tail N` only the last N are returned, so a long run's journal (thousands of lines, each
  attempt line several hundred bytes) never crosses into QML whole. An `am` refusal or
  failure is passed through as `{ok:false, error:{type,message}}`; exit 0 either way.
- `RunStore.qml`: `events` (rows, capped at 500, oldest dropped), `eventsDropped` (rows not
  held: the helper's `total` minus the rows received on the first fetch, plus rows dropped by
  the cap), `eventsCursor` (highest `seq`), `eventsStatus` (`idle|loading|ok|error`),
  `eventsFilter`, `eventsError`. One `HelperRunner` (latest wins), not guarded by the open
  project. `titles` is a property App hands in: the open project's card id to title map; the
  run's own story titles from its `am status` tree complete it. A subtask has no title in
  `am status`, so a run of a project that is not open shows short card ids for its
  subtasks.
- `ui/components/EventsPane.qml`, wired into `ui/screens/RunDetailScreen.qml`.

### Behaviour

- Selecting a run (opening Run detail) resets the events and fetches the last 200 with
  `--tail 200`.
- The store's debounced change signal for the selected run (`runsChanged(ids)` from S6) triggers
  one fetch `--since eventsCursor`; new rows are appended in `seq` order and deduplicated by
  `seq`. A fetch for a change that arrives while one is in flight runs after it, never
  instead of it, and a reply for a run that is no longer selected is dropped. No second
  watch process.
- Leaving Run detail or switching runs clears the events and stops fetching.
- A run that finishes while Run detail is open gets its last fetch from the same signal.
- The panel closing stops fetching with the rest of the store's live work.

### Row model

`{seq, time:"HH:MM:SS", level: run|story|subtask|phase|attempt, label, status, glyph,
duration, detail, card, phase, attempt}`:

- `label`: the story/subtask title from `titles` (fall back to the short card id), plus
  `phase` or `phase.attempt` where the event has one; `run_upsert` reads
  "run started" / "run done" / "run paused" / "run escalated" / "run cancelled".
- `glyph` follows the S1 table (`runGlyphs.js`: running, done, escalated `‼`, parked,
  cancelled; an attempt `ok` is done, a failed phase is dead).
- `duration` from an attempt's `duration` field, formatted (`4.2s`, `3m 12s`); empty
  otherwise. A phase's `detail` (why it failed) is shown under the row.
- `card`, `phase`, `attempt` are carried so a click can name the attempt.
- Failures (`failed`, `escalated`, `gate_failed`, `schema_invalid`, `harness_error`)
  use the `urgent` token with the `‼` glyph, never red/purple (reserved for brd).

## UI

```
┌ Run …19efcddc ⟳ running ─────────────────────────────────────────────┐
│ …tree…                                                               │
│──────────────────────────────────────────────────────────────────────│
│ [Output] [Events 142]      filter: [All] [Phases] [Failures]         │
│ 01:14:03 ⟳ #253 implement.2            started                       │
│ 01:11:52 ✔ #253 verify.1               ok               2m 11s       │
│ 01:11:50 ‼ #253 verify                 failed   "3 tests red"        │
│ 01:09:38 ✔ #253 implement.1            ok               7m 02s       │
│  … 96 earlier events                                       [Jump ↓]  │
└──────────────────────────────────────────────────────────────────────┘
```

- Output and Events share the bottom area as two tabs; `e` toggles them while Run detail is
  open and no modal or text field has the keys.
- The page itself scrolls (the panel's flickable), so the list has its own bounded height and
  its own scrolling: a wheel over the list scrolls the list, and at its ends the page takes
  over. Newest at the bottom; the list follows new rows while it is scrolled to the bottom,
  and a `Jump ↓` appears when it is not.
- Clicking a row that names an attempt selects it in the tree, loads its output and switches
  to the Output tab; a row without an attempt does nothing.
- The Events tab count is the rows held plus `eventsDropped`.
- Empty: "No events yet." Error: `errorText` with the raw message one click away.

## Errors

| case | behaviour |
|---|---|
| `am` missing | tab shows the S1 `missing` message |
| `UnknownRunError` | empty state, run dropped on the next snapshot |
| `am watch` exit 3 (corrupt journal) | "journal unreadable" with the message |
| unknown event or key | ignored |
| fetch while a fetch is running | latest wins for a new selection; for a change signal the follow-up runs after |
| a very long run | at most 200 rows cross in the first fetch, 500 are held |

## Testing

- `tests/core/domain/tst_run_events.qml`: `eventRow` for every event kind (titles,
  fallback ids, phase/attempt labels, duration, failure detail, glyphs, fixed UTC offsets),
  `foldEvents` (append, dedupe by `seq`, cap with dropped count, out-of-order input),
  `filterRows`, unknown events ignored, both `cancelled` and `canceled`.
- Backend pytest with a fake `am`: argv with and without `--since`, `--tail` and `total`,
  `last_seq`, refusal passthrough, missing `am`, corrupt journal.
- `tests/contract/test_am_shapes.py`: the `am watch RUN` envelope, the five events' payload
  keys recorded from the installed `am`, and no cost or token keys.
- `tests/core/stores/tst_run_store.qml`: reset on selection, `--since` after a change
  signal, follow-up fetch while one is in flight, stale reply dropped, cap, error status,
  a project switch changes nothing.
- `tests/ui/`: the tabs, `e` key, filter chips, follow/jump, bounded list, row click selects
  the attempt and shows Output.
