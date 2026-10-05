# Run events timeline (S5) — design

Status: proposed. Builds on `2026-10-03-am-run-monitor-design.md` (S1: `RunStore`,
Run detail) and uses the same `am` interfaces. Independent of S2/S3.

## Problem

The Runs screen renders the current state of a run (an `am status` snapshot). It
cannot answer "what happened, in what order, and when": there is no history, no
timestamps, no per-attempt duration, and no record of a phase that failed and was
retried. `am watch` has all of it, as the run's journal.

## Goal

Run detail gets an **Events** pane: a chronological timeline of the run's journal,
live while the run is going, for any run of the open project, including one started
from a terminal.

## Non-goals

- No cost or token figures: `am` no longer journals them. An attempt event carries
  `duration`, `exit_code`, `status`, the prompt/result/stdout paths and a
  `dispatch` (harness, model, role, cwd, timeout).
- No output text: the journal has none; the existing Output pane (`am logs`) stays.
- No cross-project view; the pane follows the open project like the rest of Runs.
- The plugin never reads the journal file. Only `am watch` is used.

## Data source (documented `am` interface)

`am watch RUN [--since SEQ]` (no `--follow`) prints one envelope
`{"ok": true, "data": {"events": [...]}}`. Each event is a journal line:

```
{seq, ts, run_id, event, story, card, phase, attempt, payload}
event ∈ run_upsert | story_upsert | subtask_upsert | phase_upsert | attempt_upsert
```

A status change is the same node recorded again, so a node appears several times.
`phase_upsert` carries `detail` when a phase failed. Cursor by `seq` (the highest
seen is the safe `--since`). Ignore unknown events and unknown payload keys. A run
that is `cancelled` today will be `canceled` after the spelling migration: accept
both everywhere.

## Architecture

Same layering as S1 (`docs/architecture.md`): pure domain, store, backend helper,
screens receive props.

- `core/domain/runEvents.js` (pure): `eventRow(event, titles)`, `foldEvents(rows,
  events, cap)`, `filterRows(rows, filter)`, `rowGlyph`, `durationText`.
- `core/backend/runs/runs-events.py RUN [--since SEQ]`: runs `am watch`, prints one
  JSON line `{ok, events, last_seq}`; an `am` refusal or failure is passed through as
  `{ok:false, error:{type,message}}`; exit 0 either way.
- `RunStore.qml`: `events` (rows, capped at 500, oldest dropped, with a count of
  dropped rows), `eventsCursor` (highest `seq`), `eventsStatus`
  (`idle|loading|ok|error`), `eventsFilter`. One `HelperRunner` (latest wins).
- `ui/components/EventsPane.qml`, wired into `ui/screens/RunDetailScreen.qml`.

### Behaviour

- Selecting a run (opening Run detail) resets the events and fetches all of them.
- The existing debounced `changed` signal for the selected run triggers one fetch
  `--since eventsCursor`; new rows are appended in `seq` order and deduplicated by
  `seq`. No second watch process.
- Leaving Run detail or switching runs clears the events and stops fetching.
- A project switch clears everything (the store's existing guard applies).

### Row model

`{seq, time:"HH:MM:SS", level: run|story|subtask|phase|attempt, label, status, glyph,
duration, detail}`:

- `label`: the story/subtask title from the run tree (fall back to the short card id),
  plus `phase` or `phase.attempt` where the event has one; `run_upsert` reads
  "run started" / "run done" / etc.
- `glyph` follows the S1 table (running, done, escalated `‼`, parked, cancelled).
- `duration` from an attempt's `duration` field, formatted (`4.2s`, `3m 12s`);
  empty otherwise. A phase's `detail` (why it failed) is shown under the row.
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

- Output and Events share the bottom area as two tabs; `e` toggles.
- Newest at the bottom; the pane follows new rows while scrolled to the bottom, and a
  `Jump ↓` appears when it is not. Clicking a row that names an attempt selects it in
  the tree and loads its output.
- Empty: "No events yet." Error: `errorText` with the raw message one click away.

## Errors

| case | behaviour |
|---|---|
| `am` missing | tab shows the S1 `missing` message |
| `UnknownRunError` | empty state, run dropped on the next snapshot |
| `am watch` exit 3 (corrupt journal) | "journal unreadable" with the message |
| unknown event or key | ignored |
| fetch while a fetch is running | latest wins (`HelperRunner`) |

## Testing

- `tests/core/domain/tst_run_events.qml`: `eventRow` for every event kind (titles,
  fallback ids, phase/attempt labels, duration, failure detail, glyphs), `foldEvents`
  (append, dedupe by `seq`, cap with dropped count, out-of-order input), `filterRows`,
  unknown events ignored, both `cancelled` and `canceled`.
- Backend pytest with a stub `am`: argv with and without `--since`, `last_seq`,
  refusal passthrough, missing `am`, corrupt journal.
- `tests/contract/test_am_shapes.py`: the `am watch RUN` envelope and the attempt
  payload keys (asserting no cost or token keys).
- `tests/core/stores/tst_run_store.qml`: reset on selection, `--since` after a
  `changed` signal, project switch, cap.
- `tests/ui/`: the tabs, `e` key, filter chips, follow/jump, row click selects the
  attempt.

## Open

- A cross-project Runs view is a separate follow-up (`am watch --all` is already
  cross-repo).
