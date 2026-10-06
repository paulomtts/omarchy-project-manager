# Run events timeline (S5) — design

Status: proposed; retargeted to the new `am` (`am events` pages, nudges as the live signal;
`2026-10-06-am-snapshots-cursors-design.md`, row evt). Builds on `2026-10-03-am-run-monitor-design.md` (S1: `RunStore`,
Run detail) and uses the same `am` interfaces. Lands AFTER
`2026-10-05-runs-all-projects-design.md` (S6): S6 removes the project guards from
`RunStore` and adds the changed-run signal this spec consumes, so the events state is
written once against the final store. Independent of S2/S3.

## Preconditions

- The run model reads the real `am status` shape (nested `stories[].subtasks[]`); the
  cards stop and escalate when `Runs.normalizeRun` of a recorded real payload has an empty
  tree. Fixtures for `am events` are recorded from the installed `am`, which is the new one
  (single store, global `gseq` cursor, `am events`); with an older `am` the pane shows the
  schema banner.

## Problem

The Runs screen renders the current state of a run (an `am status` snapshot). It
cannot answer "what happened, in what order, and when": there is no history, no
timestamps, no per-attempt duration, and no record of a phase that failed and was
retried. `am events` has all of it: the run's recorded events.

## Goal

Run detail gets an **Events** pane: a chronological timeline of the run's events,
live while the run is going, for any run the Runs screen lists, including one started
from a terminal and one of a project that is not open (S6).

## Non-goals

- No cost or token figures: `am` no longer journals them. An attempt event carries
  `duration`, `exit_code`, `status`, the prompt/result/stdout paths and a
  `dispatch` (harness, model, role, cwd, timeout).
- No output text: the events have none; the existing Output pane (`am logs`) stays.
- The plugin never reads `am`'s files or database. Only `am events` is used.
- No second `am watch --follow` process: the store's one watch already says when the
  selected run changed (a nudge), and the pane never replays a run from its start.
- No event reducer: the pane lists events; run state still comes from the snapshot.

## Data source (documented `am` interface)

`am events RUN [--after-seq N] [--limit K] [--tail N] [--before-seq N]` (no `--repo-dir`: it
resolves by run id) prints one envelope `{"ok": true, "data": {"events": [...], "head": H}}`,
events in `seq` order. `--after-seq` pages forward, `--tail N` returns the last N events and
`--before-seq N` pages backward from one (the agreed `am` surface, `am` spec Decisions 5).
Each event keeps the journal line shape and adds the global `gseq`; `seq` stays the per-run
number (field list to be confirmed against the recorded fixture):

```
{seq, gseq, ts, run_id, event, story, card, phase, attempt, payload}
event ∈ run_upsert | story_upsert | subtask_upsert | phase_upsert | attempt_upsert
      (new kinds control_requested | control_handled | lease_* | claim_conflict: ignored)
```

A status change is the same node recorded again, so a node appears several times.
`phase_upsert` carries `detail` when a phase failed. Statuses: run `started | done |
escalated | stopped | cancelled`, story and subtask `pending | started | done | stopped |
escalated`, phase `started | done | failed`, attempt `started | ok | schema_invalid |
gate_failed | harness_error`. Cursor by `gseq` for the live append (the highest seen is the safe `--after-seq`), by `seq` for
backward paging. Ignore unknown events and unknown payload keys. History from before the
store migration is coarser (no control, lease or claim events); the pane just shows what
exists. A run that is `cancelled` today will be
`canceled` after the spelling migration: accept both everywhere.

## Architecture

Same layering as S1 (`docs/architecture.md`): pure domain, store, backend helper,
screens receive props.

- `core/domain/runEvents.js` (pure, presentation only): `eventRow(event, titles, utcOffsetMinutes)`,
  `mergeRows(rows, events, cap)` (dedupe by `gseq`, order, cap; not a state reducer),
  `filterRows(rows, filter)`, `rowGlyph`, `durationText`.
  `time` is the event's `ts` shifted by `utcOffsetMinutes` (the store passes the local
  offset; tests pass fixed offsets, so no test depends on the machine's time zone).
- `core/backend/runs/runs-events.py RUN [--after-seq N] [--before-seq N] [--tail N] [--limit K]`:
  a thin `am events` passthrough that prints one JSON line `{ok, events, head}` as `am` returned
  it, so a long run's events never cross into QML whole (a page is at most `--limit` or
  `--tail`). An `am` refusal or failure is passed through as `{ok:false, error:{type,message}}`;
  exit 0 either way.
- `RunStore.qml`: `events` (rows, capped at 500, oldest dropped), `eventsHasEarlier` (the
  oldest page held was full, or rows were dropped by the cap), `eventsCursor` (highest `gseq`),
  `eventsOldestSeq` (lowest `seq` held, for `--before-seq`), `eventsStatus` (`idle|loading|ok|error`),
  `eventsFilter`, `eventsError`. One `HelperRunner` (latest wins), not guarded by the open
  project. `titles` is a property App hands in: the open project's card id to title map; the
  run's own story titles from its `am status` tree complete it. A subtask has no title in
  `am status`, so a run of a project that is not open shows short card ids for its
  subtasks.
- `ui/components/EventsPane.qml`, wired into `ui/screens/RunDetailScreen.qml`.

### Behaviour

- Selecting a run (opening Run detail) resets the events and fetches the last 200 with
  `--tail 200`. It never replays the run from its start.
- Scrolling to the top (the earlier-events control) fetches the previous page with
  `--before-seq eventsOldestSeq --limit 200`, prepended and deduplicated.
- The store's debounced change signal for the selected run (`runsChanged(ids)` from S6, fed by
  watch nudges) triggers one fetch `--after-seq eventsCursor`; new rows are appended in order
  and deduplicated by `gseq`. A fetch for a change that arrives while one is in flight runs after it, never
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
- `glyph` is a `runGlyphs.js` state key (running, parked, escalated, dead, cancelled, done),
  through `Runs.glyphStateOf`; an attempt `ok` is done, a failed phase is dead. The UI
  resolves the character, so `core/domain` imports nothing from `ui/`.
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
│  … earlier events                           [Load earlier] [Jump ↓]  │
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
- The Events tab count is the rows held (a lower bound while `eventsHasEarlier`; `am events`
  does not report a total).
- Empty: "No events yet." Error: `errorText` with the raw message one click away.

## Errors

| case | behaviour |
|---|---|
| `am` missing | tab shows the S1 `missing` message |
| `UnknownRunError` | empty state, run dropped on the next snapshot |
| `am events` exit 3 (store unreadable or busy) | "events unreadable" with the message; the pane keeps its rows and retries on the next nudge |
| `am` too old (no `am events`, or no `head`) | the schema banner; no pane |
| unknown event or key | ignored |
| fetch while a fetch is running | latest wins for a new selection; for a change signal the follow-up runs after |
| a very long run | at most 200 rows cross per page, 500 are held |

## Testing

- `tests/core/domain/tst_run_events.qml`: `eventRow` for every event kind (titles,
  fallback ids, phase/attempt labels, duration, failure detail, glyphs, fixed UTC offsets),
  `mergeRows` (append, prepend, dedupe by `gseq`, cap, out-of-order input),
  `filterRows`, unknown events (including the new control, lease and claim kinds) ignored,
  both `cancelled` and `canceled`.
- Backend pytest with a stub `am`: argv for `--tail`, `--before-seq`, `--after-seq` and
  `--limit`, `head` passthrough, refusal passthrough, missing `am`, store unreadable.
- `tests/contract/test_am_shapes.py`: the `am events RUN` envelope (`events`, `head`), the
  five events' payload keys and the `gseq` key recorded from the installed `am`, and no cost or
  token keys.
- `tests/core/stores/tst_run_store.qml`: reset on selection, `--after-seq` after a change
  signal, `--before-seq` for earlier events, follow-up fetch while one is in flight, stale reply dropped, cap, error status,
  a project switch changes nothing.
- `tests/ui/`: the tabs, `e` key, filter chips, follow/jump, bounded list, row click selects
  the attempt and shows Output.
