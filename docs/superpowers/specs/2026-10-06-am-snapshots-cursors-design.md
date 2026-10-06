# Run monitor on am snapshots and cursors (milestone 4) — design

Status: proposed. Companion of `agent-manager`'s
`docs/superpowers/specs/2026-10-06-single-store-events-design.md` (milestones 1-3 of the same
stack); it cannot start until those are landed, verified and the new `am` is installed. Builds on
`2026-10-03-am-run-monitor-design.md` (S1), the S2 controls spec and the queued specs listed in
"Retargets". Code references are measured against `main` at `9d1c3b8` and drift: re-read before
acting.

## Problem

The panel and the helpers consume `am watch`, a stream of journal lines, and several queued specs
plan to reduce those lines into state. That couples the plugin to the journal's shape, makes
every cold start replay history (the `is_backlog` workaround in `runs-watch.py` drops it), and
makes one project-scoped fan-out per project the only way to see all runs. `am` is moving
state into one database with a global event cursor (`seq`) and snapshots that carry
`as_of_seq`. The plugin should read snapshots and treat events as nudges.

## What the code does today (verified)

The brief assumed `RunStore` and `runs.js` fold events into state. They do not, today:

- `core/stores/RunStore.qml:245-260` (`watchLine`): a `{"changed": [...]}` line only restarts a
  debounce timer; the snapshot (`refresh()`, `runs-snapshot.py`) is the only source of run
  state. `Runs.newAlerts(prev, next)` (`core/domain/runs.js:842`) diffs two snapshots.
- `core/domain/runs.js` has no event reducer. `normalizeRun` reads `am runs` / `am status`.
- The event logic lives in the helper: `core/backend/runs/runs-watch.py` filters journal lines
  (`EVENTS`, `keep`), maps a run to a project through `run_upsert.payload.repo_dir`, drops the
  backlog by timestamp (`is_backlog`, an S4 workaround for the missing `--from-now`) and
  debounces 250 ms.
- Folds exist only in the QUEUED specs: `foldEvents` / `eventRow` in the events timeline
  (`runEvents.js`, not in the tree), and a per-run "last status from `run_upsert`" reducer in the
  alerts-while-closed helper `runs-alerts.py` (not in the tree).
- None of S6 (runs as a global destination), S5 (timeline), the split RunStore, the alerts
  service, live output or run history has landed: `runs-watch.py` takes one root, there is no
  `common/am_runs.py`, no `RunAlertsStore`. So this milestone mostly retargets SPECS and
  CARDS that are not built yet, and simplifies the few built files. Which of them are built when
  this starts must be re-checked (`git log`, `ls core/stores`).

So "stop folding" means: do not introduce the folds, and shrink `runs-watch.py` and the planned
alerts helper to nudges and cursors.

## Goal

- RunStore and `runs.js` never fold events into state. A watch line is a nudge: "run X changed
  at seq N". The store debounces and refreshes that run's snapshot, ignoring a nudge whose seq is
  `<= as_of_seq` of the snapshot it already holds.
- The timeline reads history with `am events` and live updates from the watch; it never replays a
  run from its start on open.
- The Global Runs screen uses `am runs --all-projects` (one call; the per-project fan-out helper
  is dropped).
- Alerts while the panel is closed use a persisted last-seen seq cursor and, on open, ask `am`
  for escalation events after it.
- Live output is unchanged.

## Non-goals

- No reading of `am.db`, the journal files or the data-dir layout: only `am` commands, as argv
  lists (existing rule).
- No new run state computed in the plugin; `am` owns state.
- No dead-run detection from events: a run that dies writes nothing. The lease poll (`lease.live`
  from `am runs`) stays the only source of `dead`.
- No change to `am logs` consumption (`runs-logs.py`, the live-output spec's follow stream).
- No hard dependency on `am` features outside the companion spec; where a flag is only
  recommended there, it is marked here.

## Design

### The am interface the plugin reads (from the companion spec)

| call | use |
|---|---|
| `am runs --all-projects [--limit N] [--before RUN]` | the snapshot of every project; each row has `project: {id, repo_dir}`; envelope carries `as_of_seq` |
| `am status RUN` (no `--repo-dir` needed) | one run's tree and state; carries `as_of_seq` |
| `am events RUN [--after-seq N] [--limit K]` | history of one run, paged forward; envelope has `head` |
| `am watch --all-projects --follow [--since-seq N \| --from-now]` | the live feed; hello `{schema, head, cursor_reset, am}`; each line has `gseq` (global) and `seq` (per run) |
| `am logs ...` | unchanged |

Rules: a snapshot plus the events with `gseq > as_of_seq` is complete and has no repeats; lines
with an unknown `event` or key are ignored (existing rule; the new kinds `control_requested`,
`control_handled`, `lease_*`, `claim_conflict` are expected and mostly ignored).

### The watch helper becomes a nudge source

`core/backend/runs/runs-watch.py` is reduced:

- argv: no roots and no run ids (the helper watches `--all-projects`); an optional
  `--since-seq N` for resuming. Spawns `am watch --all-projects --follow` (or `--since-seq N`).
  Deleted: `is_backlog`, `same_dir`, the `watched` set and `repo_dir` mapping (the project is
  now `am`'s `project_id`, and registered-project filtering happens in the store from the
  snapshot's `project.repo_dir`).
- hello: `{"hello": {"schema": N, "am": V, "head": H, "cursorReset": bool}}`. `schema` is
  accepted when it is 1 or higher and the hello has `head`; a hello without `head` (an old
  `am`) is `SchemaMismatch` with the message that the plugin needs the new `am`.
- output: at most one `{"changed": [{"run": "<id>", "seq": N}, ...]}` per 250 ms window, the
  highest `gseq` per run, never event contents. It also prints `{"cursor": N}` (the highest `gseq`
  seen) with each changed line so the store can persist it.
- It keeps the `AmMissing`, `SchemaMismatch`, `CorruptJournal` (renamed `StoreUnreadable`? see
  Open questions), `HelperError` envelopes and quiet exits.

### `RunStore` and `runs.js`

- `RunStore.qml`: `watchLine` handles `{"changed": [...]}` by recording `pending[run] =
  max(seq)` and restarting the debounce (unchanged behaviour); on trigger it refreshes ONLY the
  runs whose pending seq is greater than the store's `appliedSeq[run]` (`as_of_seq` of the
  snapshot that last covered that run) through `am status RUN`, and refreshes the list through
  `am runs --all-projects --limit` when a run is unknown. A hello with `cursorReset` discards
  `appliedSeq`, the persisted cursor and the list, then does a full snapshot. New members:
  `asOfSeq` (global, from the last `am runs`), `appliedSeq` (map), `watchCursor`. `startWatch`
  no longer passes the run ids or the project (argv shrinks).
- `Runs.normalizeRun` accepts the new keys (`project`, `as_of_seq` is read by the store, not kept
  on the run model) and keeps ignoring unknown keys. Nothing is removed from `runs.js`: it has no
  fold to remove. `Runs.newAlerts` stays (snapshot diff) for the open panel.
- `runs-snapshot.py` shrinks to `am runs --all-projects --limit N` followed by `am status` per
  selected run (same selection rule: every non-terminal run plus the newest K terminal ones),
  forwarding `as_of_seq`; the per-project `<project_root>` argument becomes an optional filter.

### Timeline (Events pane)

Opening Run detail asks `am events RUN` for the most recent page (needs a `--tail` or
`--before-seq` that the agreed `am events` lacks: companion open question 10), then the pane
subscribes to nudges for that run and fetches `am events RUN --after-seq <last gseq seen>` when
one arrives. It never replays from the start. `runs-events.py` shrinks to a thin `am events`
passthrough (`--after-seq`, `--limit`, one JSON line). The pure `runEvents.js` keeps only
presentation (`eventRow`, `filterRows`, glyphs, durations); `foldEvents` becomes a dedupe by
`gseq` and a cap, not a state reducer. History before the migration is coarser (no control, lease
or claim events; `source: imported` is not on the wire, so the pane just shows what exists).

### Global Runs

One snapshot call replaces the per-project fan-out: `am runs --all-projects` returns rows of
every project, each with `project.repo_dir`. The store groups by `project.repo_dir` and shows only
the projects in the plugin's registry (`brd projects`) unless the viewer chooses "all". The
helper `common/am_runs.py` (planned by S6) is not created.

### Alerts while the panel is closed

The service persists a last-seen cursor (`gseq`) in the viewer-state global settings (alongside
`notifyOnEscalation`; one integer, per viewer). While running, the helper follows
`am watch --all-projects --follow --since-seq <cursor>` and prints an alert line for a
`run_upsert` whose `payload.status` is `escalated` in a registered project; the cursor advances
as lines are consumed (written after the notification is sent, so a crash can repeat one alert
at worst). On start, or when the panel opens after a gap, it asks `am` for escalation events after
the cursor (companion open question 11; fallback: page `am watch --all-projects --since-seq N`
without `--follow` and filter client-side) instead of replaying history. A hello with
`cursorReset` clears the cursor to `head` and alerts nothing. `dead` still comes from the 60 s
lease poll (`am runs --all-projects`). The `--from-now` start of the old design is replaced by the
cursor, so a run that escalated while the shell was down IS notified once (a behaviour change from
the alerts spec's "No replay"; open question 4).

## Retargets (existing specs, cards, files)

Card ids are the ones given for this milestone; the spec mapping is by title and was not
checked against `brd` (open question 6).

| card | spec | what changes |
|---|---|---|
| glb a7d98ede | `2026-10-05-runs-all-projects-design.md` (S6) | drop the per-root fan-out, `common/am_runs.py` and the multi-root `runs-watch.py`; use `am runs --all-projects` and the single global watch; group by `project.repo_dir`; keep registry filtering and the grouped list |
| evt afce5d08 | `2026-10-05-run-events-timeline-design.md` (S5) | replace `am watch RUN --since SEQ` and the replay-with-cap `foldEvents` with `am events RUN` pages and nudge-driven `--after-seq`; `runs-events.py` becomes a passthrough; `runEvents.js` loses the state-style fold |
| alr 81a57c43 | `2026-10-05-alerts-panel-closed-design.md` | persisted last-seen cursor, `--since-seq` instead of `--from-now`, no per-run last-status reducer beyond the escalation test, `cursorReset` handling; revise "No replay" |
| rsm 0d38da32 | `2026-10-05-resume-recover-design.md` | control calls (`run-control.py`) and resume read the run from `am status RUN` without `--repo-dir` (the run carries its project); the stopped-run attempt choice reads the status snapshot; no event dependence |
| hst d74a734a | `2026-10-05-run-history-titles-design.md` | `runs-history.py ... --before ISO` becomes `am runs --all-projects --limit K --before RUN` (keyset page); no client-side cap; `common/am_runs.py` not used |
| liv e9599fe3 | `2026-10-05-live-output-design.md` | no change to the follow stream; update its dependency notes (the watch is now a nudge feed) and its Events pane statement |
| spl 2360abd3 | `2026-10-05-split-runstore-design.md` | the watch row of the split table loses the run-id argv and gains `asOfSeq`, `appliedSeq`, `watchCursor`; `RunAlertsStore` owns the persisted cursor |
| dfr a8842502 | `2026-10-05-dispatch-from-runs-design.md` | `start-run.py` run-id discovery (poll `am runs --repo-dir`, `started_at >= spawn`) moves to `am runs --all-projects --limit`, optionally keyed by the head captured before the spawn; the per-root refresh step collapses |
| sty 5d48ef7a | `2026-10-05-dispatch-story-level-design.md` | the precondition note that `am` is "not editable" is corrected (the install was editable until the companion spec's prerequisite P1 landed); `story_id` stays on the row; contract tests include the new `project` key |

Files (built today unless noted):

- `core/backend/runs/runs-watch.py`: reduced as above. `runs-snapshot.py`: `--all-projects`,
  `as_of_seq`. `start-run.py`: discovery (dfr). `run-control.py`, `runs-logs.py`: drop
  `--repo-dir` only if the live-output and controls specs still pass it for other reasons
  (unverified; `am logs` keeps `--repo-dir`).
- `core/stores/RunStore.qml`: the members and `watchLine` above. `core/domain/runs.js`:
  `normalizeRun` tolerates the new keys; no fold removed.
- `docs/architecture.md:204` (describes `runs-snapshot.py` and `runs-watch.py`): rewritten.
- Not built yet: `runs-events.py`, `runEvents.js`, `runs-alerts.py`, `RunAlertsService.qml`,
  `RunAlertsStore`, `runs-history.py`, `common/am_runs.py`: their specs are edited, not code.

## Dev safety

- The installed `am` must be a regular, non-editable `uv tool install` (companion spec,
  prerequisite P1). This milestone is verified against the NEW `am`, built in a worktree and run
  as `XDG_DATA_HOME=<scratch> uv run am` from there, with that `am` first on `PATH` for the
  test run. The user's installed `am` is replaced only by the deliberate reinstall after the
  whole stack is verified, never while any `am` run is live.
- `tests/contract/test_am_fixtures.py` has a live check that reads the real data dir with the
  installed `am`. In this milestone the live check runs against the dev `am` and the scratch data
  dir, so it neither depends on nor reads the user's real runs.
- Fixtures are recorded from a throwaway data dir (fake harness, a scratch repo), not from the
  migrated real data, so no real paths or prompts end up in the repo.

## Errors

| case | behaviour |
|---|---|
| `am` missing | unchanged (`AmMissing`, badges empty) |
| `am` too old (hello without `head`, or `runs` without `as_of_seq`) | `SchemaMismatch`: "the plugin needs the newer am"; panel shows the schema banner; no watch |
| hello `cursorReset` | clear `appliedSeq`, the persisted cursor and the list, full snapshot, no alerts |
| nudge for a run already covered (`seq <= appliedSeq[run]`) | ignored |
| nudge for an unknown run | refresh the list (`am runs --all-projects --limit`) |
| `am status RUN` refuses (unknown run) | the run is dropped from the list on the next list snapshot; no error toast |
| `am` store busy (`StoreBusyError`, exit 3) | helper re-emits the envelope; the store keeps the last good snapshot, shows `stale`, and retries on the next nudge or poll |
| watch exits while open | existing behaviour: polling snapshots until the watch is restarted |
| cursor setting unreadable | start at the head (`--from-now`-equivalent), alert nothing |

## Testing

- **Contract tests on recorded envelopes** (`tests/contract/test_am_shapes.py`,
  `test_am_fixtures.py`): regenerate `tests/fixtures/am/*.json` from the new `am` (`runs.json`,
  `status-started|done|escalated|escalated-integrate|done-integrate.json`, `watch-events.json`,
  `watch-hello.json`, `logs-attempt.json`) and add `events.json`; key sets gain `project` on a
  runs row, `as_of_seq` on `runs` and `status`, `gseq` on a watch line, `head` and `cursor_reset`
  on the hello. Notes in the fixtures name the `am` version and how they were captured. The live
  check skips only when `am` is absent, and fails loudly when `am` lacks `as_of_seq`.
- **`tst_runs.qml`**: `normalizeRun` with `project`; no event input anywhere.
- **`tst_run_store.qml`** and **tst_* flows**: refresh-on-nudge (a changed line refreshes only
  that run, once, debounced); a stale nudge (`seq <= as_of_seq`) is ignored; latest wins;
  `cursorReset`; project switch guard; unknown run triggers a list refresh; timeline pages and
  nudge-driven `--after-seq`.
- **Catch-up after the panel was closed**: a flow where the cursor is persisted, events occur
  while the store is inactive, and on open the store asks for escalations after the cursor and
  raises exactly one toast per escalated run, none for history before the cursor.
- **Backend pytest with a stub `am`** (`tests/core/backend/runs/`): `runs-watch.py` argv,
  hello with and without `head`, `changed` batching with highest seq per run, `cursor` line,
  refusal passthrough; `runs-snapshot.py --all-projects`; `runs-events.py` passthrough.
- **Real-data-flow test** (`3-4-real-data-flow`-style): drive a fake-harness run under a scratch
  data dir and check snapshot plus nudges converge to the same state as a fresh snapshot.

## Where it goes (layering)

Unchanged plugin rules (`docs/architecture.md`): pure model code in `core/domain/*.js`, stores in
`core/stores/*.qml` (only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain`), helpers in
`core/backend/runs/*.py` using `am` only, UI in `ui/`. This milestone adds no layer:
nudge handling and cursors live in `RunStore` (and `RunAlertsStore` after the split), the cursor
persistence in `viewer-state.py` global settings, no new helper except those the retargeted specs
already plan.

## Order and sizing

Starts only after the `agent-manager` stack is merged and verified and the new `am` is installed
(deliberate reinstall, no run live). One story per surface; each subtask is one worktree, one
branch, the full suite green on its own.

**M4 scope on the board is stories 4.0, 4.1 (including 4.1.4) and 4.4 only.** Story 4.2 (the spec
retargets) is the docs PR `docs/retarget-specs-new-am`, which also carries this spec: it is not a
board story. Story 4.3 (behaviour on the retargeted specs) is dropped: the retargeted milestones
carry that work, so a spec edit in 4.2 is the whole change this milestone makes for each of them.
The rows of 4.2 and 4.3 are kept below for the record; the Retargets table remains the authority
for what the docs PR does.

| story | subtask | deliverable |
|---|---|---|
| 4.0 Contract | 4.0.1 | contract test that fails naming the missing capability when `am` lacks `as_of_seq` / `head` (skips only when `am` is absent) |
| | 4.0.2 | regenerate `tests/fixtures/am/*.json` from the new `am` and add `events.json` |
| | 4.0.3 | `normalizeRun` tolerates `project` and the new keys; `tst_runs.qml` |
| 4.1 Nudges | 4.1.1 | `runs-watch.py` as a nudge and cursor source (no backlog filter, no run-id argv) |
| | 4.1.2 | `runs-snapshot.py --all-projects` with `as_of_seq` and a single-run read |
| | 4.1.3 | `RunStore` refresh-on-nudge with `appliedSeq` and `cursorReset`, using the single-run read |
| | 4.1.4 | store_id reset: the consumer clears `appliedSeq`, the persisted cursor and the list when `store_id` (hello or snapshot) differs from the one it last saw, then does a full snapshot |
| 4.2 Specs retarget (the docs PR, not a board story) | 4.2.1 | edit S6, S5 and history specs (glb, evt, hst) |
| | 4.2.2 | edit alerts, split, dispatch-from-runs, resume and story specs (alr, spl, dfr, rsm, sty) and the live-output notes (liv) |
| 4.3 Behaviour on the retargeted specs (dropped) | 4.3.1 | Global Runs on `am runs --all-projects` |
| | 4.3.2 | timeline on `am events` and nudges |
| | 4.3.3 | persisted alert cursor and catch-up on open |
| | 4.3.4 | `start-run.py` run-id discovery from `am runs --all-projects` |
| 4.4 Docs | 4.4.1 | `docs/architecture.md` and README run-monitor sections, read from the code |

4.1.2 depends on 4.1.1; 4.1.3 depends on 4.1.2 (the store's refresh needs the helper's single-run read) and on the 4.0.2 fixtures; 4.1.4 depends on 4.1.3. In M4 the watch cursor is held in memory only; persisting it belongs to the Alerts milestone.

## Decisions (user, 2026-10-06)

The six decisions in the am spec's "Decisions" section apply here: the hello stays at schema 2 with
additive `head`, `gseq`, `cursor_reset` and a `store_id` (the plugin resets its cursor and list when the
`store_id` changes); `am backup` exists; `am migrate` is explicit; `am events` has `--tail`,
`--before-seq` and a cross-run escalation read (the timeline pages backwards with `--before-seq`, and the
alerts helper uses the escalation read); and alerts catch up on escalations from while the panel was
closed from a persisted last-seen `gseq`, with dismissal advancing the cursor. Treat the matching items in
the open questions below as resolved.

## Open questions

1. Which of S6, S5, the split, alerts and history are built when this starts? The plan assumes
   none beyond `9d1c3b8` and must be re-checked; every row of "Retargets" turns into code edits
   for a built spec.
2. **`am events` tail access**: the agreed `--after-seq` / `--limit` pages forward only, so the
   "last 200 events" view needs `--tail N` or `--before-seq` (companion open question 10).
3. **Escalations since a cursor across runs**: a kind-filtered cross-run read, or client
   filtering of a paged `am watch --since-seq` (companion open question 11).
4. **Alerts replay**: with a persisted cursor a run that escalated while the shell was down is now
   notified once on start. Intended (the user asked for "alerts while closed"), but it reverses the
   alerts spec's "No replay" rule; confirm.
5. **Hello schema**: the plugin accepts "has `head`" rather than a version number while the
   companion spec decides 2 versus 3 (companion open question 1). Rename of the `CorruptJournal`
   envelope type (the journal file is no longer what is read) is deferred to keep the panel's
   error mapping unchanged.
6. **Card-to-spec mapping**: the nine card ids were mapped to specs by title and not checked on the
   board.
7. **Per-run `am status` cost**: `runs-snapshot.py` still runs one `am status` per selected run;
   whether `am runs` should embed enough for the list view is left to the companion spec's
   follow-ups.
8. **Persisting the cursor**: global per viewer (this spec) versus per project; and what a
   restored (older) `am.db` does to a cursor held in viewer state (handled by `cursorReset` only
   when the head is lower; a `store_id`, companion open question 2, would also catch a larger
   replacement).
