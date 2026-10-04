# am run monitor (S1, read-only) — design

Status: proposed. Builds on `2026-09-24-core-ui-architecture-design.md`
(layers, stores, shared components). First of three plugin specs:
this one (monitor), `2026-10-03-am-run-controls-design.md` (S2),
`2026-10-03-am-run-dispatch-design.md` (S3). The agent-manager side is
`agent-manager/docs/superpowers/specs/2026-10-03-plugin-integration-design.md` (S4).

## Problem

`am` (agent-manager) runs a milestone, or one subtask, unattended: it dispatches
AI agents against the brd board, one phase at a time, and records every step.
Today the only way to follow a run is a terminal. The plugin already shows the
board; it should also show what `am` is doing to it, at every level, and tell the
user when a run needs them.

## Goal

Without leaving the panel the user can see: which runs exist for the open
project, which are live, parked, escalated, dead or finished; how far each got;
which card each is working on; and why an escalated run stopped. Works for runs
started from a terminal as well as from the plugin.

## Non-goals

- No control (pause, resume, cancel) and no starting runs: S2 and S3.
- No run output streaming. v1 shows the last-saved output of an attempt
  (`am logs` snapshot); a live tail needs an `am` change (S4).
- No runs from other repositories. The scope is the project the panel has open
  (`am runs --repo-dir <project root>`). The data model keeps `repo_dir` on every
  run so widening later is additive.
- The plugin never reads am's SQLite or its on-disk layout. Only `am` commands
  and the documented journal contract (schema 1) are used.
- Run state is never derived from brd card status. brd status stays as the board
  shows it today.

## Data sources (all documented `am` interfaces)

| need | command | notes |
|---|---|---|
| list runs | `am runs --repo-dir R` | `id, workflow, repo_dir, base_branch, branch_prefix, status, started_at` |
| one run's tree | `am status RUN --repo-dir R` | run, story/subtask/phase/attempt tree, flat `rows`, `control.lease{pid,host,heartbeat_at,accepting,live}`, pending `requests`, `claims` |
| change signal | `am watch --all --follow` | one JSON object per journal line; hello line `{"event":"watch","schema":1}` first |
| attempt output | `am logs RUN CARD --phase P --attempt N` | whole-file snapshot |

Every command prints `{"ok":true,"data":…}` or `{"ok":false,"error":{type,message}}`
(exit 3 on refusal). A run is finished when its `run_upsert` status is `done`,
`escalated`, `stopped` or `cancelled`. A phase failure carries `detail`.

## Architecture

Follows the existing layering; nothing new is allowed to import across it.

```
 ui/screens/RunsScreen ─┐                    core/backend/runs/
 ui/screens/RunDetail  ─┼─ app.runs ──►  RunStore.qml ──► runs-snapshot.py ─► am runs / am status
 ui/components/Run*    ─┘   (props)        │   ▲                              (one JSON line)
                                           │   └─ runs-watch.py ───────────► am watch --all --follow
                                           ▼                                  (change signals only)
                                  core/domain/runs.js  (pure)
```

New files:

- `core/domain/runs.js` — pure. `normalizeRun(raw)`, `runState(run)`,
  `cardRunState(runs, cardId)`, `rollup(runs, card)`, `attention(runs)`,
  `escalationReason(run)`, `errorText(error)`. No QML, no `Qt*`.
- `core/stores/RunStore.qml` — owns `runs`, `selectedRunId`, `watching`,
  `amStatus` (`ok | missing | schema | error`), debounce and liveness timers.
  Two `HelperRunner`s (snapshot, attempt logs) plus one long-lived `Process`
  for the watch helper. Receives `project` (root path) and `backendDir` through
  explicit properties from `App.qml`; never reaches for `BoardStore`.
- `core/backend/runs/runs-snapshot.py` — runs `am runs`, then `am status` for
  every non-terminal run and the latest 10 terminal ones, prints one normalised
  JSON line (via `common/json_line`).
- `core/backend/runs/runs-watch.py` — wraps `am watch --all --follow`; drops the
  hello line and any event older than its own start time (the backlog), keeps
  only events of this project's runs (run ids learned from the snapshot passed
  on argv, plus any new `run_upsert` whose `payload.repo_dir` matches), and emits
  a compact `{"changed":["<run-id>",…]}` line at most every 250 ms.
- `core/backend/runs/runs-logs.py` — `am logs` passthrough for one attempt.
- UI: `ui/screens/RunsScreen.qml`, `ui/screens/RunDetailScreen.qml`,
  `ui/components/RunBadge.qml`, `RunRollupBar.qml`, `PhaseTimeline.qml`,
  `RunIndicator.qml`. Reuse `ListRow`, `ListStatus`, `Chip(Row)`, `Badge`,
  `FilterableList`, `ThemedText`; no second copies (the architecture test
  rejects duplicates).
- Navigation: a **Runs** sidebar row after Issues and **Ctrl+6** in
  `Shortcuts.qml`; `Navigator` registers the two screens; Run detail is pushed
  with the existing `NavigationStore` push/pop.

Update `docs/architecture.md` (store list, shortcuts) in the same change.

## Refresh model

No timers while idle.

1. Panel opens (or project changes): `RunStore` runs `runs-snapshot.py`, then
   starts `runs-watch.py` with the snapshot's run ids.
2. A `changed` line starts a 250 ms debounce, then one re-snapshot. A burst of
   journal lines costs one snapshot.
3. While any run is `started` and its lease is live, a 10 s timer re-snapshots
   so a lease that dies without writing a journal line is noticed (heartbeat is
   5 s, dead after 30 s).
4. Panel closes: the watch process is killed and the timer stops. Runs are
   unaffected; they belong to `am`.

`HelperRunner` semantics apply to the snapshot (latest run wins, stale-exit guard).

## Domain model

**Run state** (one per run, from `am status`; not the brd status):

| state | rule |
|---|---|
| `running` | status `started` and `control.lease.live` |
| `dead` | status `started` and lease not live (process gone; resumable) |
| `parked` | status `stopped` (paused) |
| `escalated` | status `escalated` |
| `cancelled` | status `cancelled` |
| `done` | status `done` |

`stale` is not a run state: it is a store flag shown as a banner when the last
successful snapshot is more than 30 s old while the panel is open.

**Card mapping.** A run touches a card when the card id appears as a run's
`stories[].card_id` or `subtasks[].card_id`, or as `run.milestone_id`. Synthetic
ids `integrate`, `bases`, `base-<story-id>` never match a card; they appear as
labelled rows in Run detail only. When a card is in several runs, the newest
non-terminal run wins, else the newest run, shown dimmed.

**Terminal brd statuses.** A card whose brd status is `merged` (finished and
landed), `canceled` or `archived` (out of play; `archived` is treated exactly
like `canceled`) is never shown with a live run mark: a run that touched it
still lists it in Run detail, dimmed, but `cardRunState` returns `none` for it
and badges/rollups on the board skip it. `am` itself honours these statuses (it
treats `merged` as finished and ignores `canceled`/`archived` cards), so a
running run never contains one except as history.

**Card run state** (separate from brd status): `running`, `parked`, `escalated`,
`dead`, or `none`, plus the current phase and attempt number for a subtask.

**Rollup** for a milestone or story from am rows only:
`{running, parked, escalated, done, pending, total}`. It does not replace
`Board.subtreeCounts`, which counts brd status.

**Needs attention** = runs in `escalated` or `dead`. **Escalation reason** = the
`detail` of the failed phase in the run tree (the reason text `am` also posts to
the card as a brd comment); when absent, "escalated at <phase>".

## UI

Run state is a separate visual channel from brd status: a glyph and ring, never
colour alone. Merged purple (`#9b72cf`) and canceled red (`#d9534f`) are not used
for run states.

| state | glyph | treatment |
|---|---|---|
| running | `⟳` | neutral foreground ring; animates only while visible (same pulse as `StatusPips`, no second animation loop) |
| parked | `⏸` | amber-grey outline |
| escalated | `‼` | theme `urgent` token, filled |
| dead | `✖` | dashed outline |
| cancelled | `⊘` | neutral, struck through |
| done | `✔` | neutral, dimmed |

Glyphs must pass `tests/architecture/test_icon_glyphs.py`.

### On existing screens (additions only)

```
 Board / Graph card (subtask)           Board / Graph card (milestone)
┌───────────────────────────────┐      ┌───────────────────────────────┐
│ #253 Add --json flag          │      │ M3 Document milestone runs    │
│ in_progress   [⟳ implement]   │      │ in_progress        [⟳ 2 ⏸ 1]  │
└───────────────────────────────┘      │ ▰▰▰▰▱▱▱▱ 3/8   run: 2 live    │
                                       └───────────────────────────────┘
```

- `RunBadge` on each card that a run touches: glyph, plus current phase on a
  subtask and counts on a parent. `RunRollupBar` under a milestone/story title.
- `CardDetailScreen` gets a **Runs** section listing the runs that touch the card
  (state, phase, age); a row opens Run detail.
- Toolbar `RunIndicator` beside `MilestoneJobIndicator`, hidden when the project
  has no runs: `▶2 ⏸1 ‼1`. Click opens Runs with the matching filter.
- Sidebar **Runs** row shows a `‼N` count when anything needs attention.

### Runs screen (Ctrl+6)

```
┌ Runs ─────────────────────────────────────────── project: refactor ┐
│ [Needs attention 2] [Live 2] [Parked 1] [All]                      │
│────────────────────────────────────────────────────────────────────│
│ ‼ …bdc5838b  #251 Add --json flag      escalated at review         │
│     "verify failed twice: 3 tests red"                             │
│ ✖ …a1b2c3d4  M2 Docs                   dead — lease lost 4m ago    │
│ ⟳ …19efcddc  M3 Document runs   3/8    implement @ #252    12m     │
│ ⏸ …9a8b7c6d  M1 Setup                  parked 2h                   │
│────────────────────────────────────────────────────────────────────│
│ am 0.1.0 · schema 1 · watching                                     │
└────────────────────────────────────────────────────────────────────┘
```

`FilterableList` + `ListRow`. j/k or arrows move, Enter opens, `/` filters,
Esc returns. Empty state (`ListStatus`): "No runs for this project yet."

### Run detail

```
┌ Run …19efcddc  ⟳ running ──────────────────────────────────────────┐
│ Milestone M3 · prefix m3 · base master · lease pid 4121 live       │
│────────────────────────────────────────────────────────────────────│
│ Story A  ✔ done      #251 ✔   #252 ✔                               │
│ Story B  ⟳ running   #253 ⟳ implement (attempt 2)      ◄ selected  │
│            spec✔ → plan✔ → implement⟳ → verify· → review·          │
│ Story C  · pending (blocked by A, B)                               │
│ Integrate   not started                                            │
│────────────────────────────────────────────────────────────────────│
│ Output · #253 implement.2      snapshot 14s ago        [Refresh]   │
│ > editing core/domain/runs.js …                                    │
└────────────────────────────────────────────────────────────────────┘
```

The tree mirrors `am status` (story > subtask > phase > attempt); Integrate and
merged-base rows appear only when present. The output pane shows the selected
attempt's `am logs` snapshot, tail-limited to the last 200 lines, re-fetched when
that attempt's status changes and on Refresh. It is labelled as a snapshot with
its age; it is never presented as live.

## Errors and edge cases

| case | behaviour |
|---|---|
| `am` not on PATH | `amStatus: missing`; Runs screen shows one `ListStatus` ("am is not installed or not on PATH"); no badges, no indicator |
| hello `schema` ≠ 1 | banner "plugin and am disagree on the journal schema"; snapshot polling every 5 s replaces the watch signal |
| `am watch` exits 3 (corrupt journal) | warning chip; fall back to the 5 s snapshot poll |
| no data dir / no runs | empty state, not an error (am returns no events) |
| `am runs`/`status` envelope with `ok:false` | store keeps the previous runs, sets `amStatus: error`, shows `errorText(error)` in the footer |
| snapshot older than 30 s | `stale` banner; runs dimmed |
| run id in a different `XDG_DATA_HOME` | invisible by design (documented am limit); footer shows the data dir in use |
| unknown journal `event` or payload key | ignored (am's reading rules) |

## Testing

- `tests/core/domain/tst_runs.qml`: normalisation, every run-state rule,
  card mapping (including newest-wins and synthetic ids), rollup, attention,
  escalation reason, error text.
- `tests/core/stores/tst_run_store.qml`: refresh sequencing, debounce, liveness
  timer on/off, fallback to poll, stale flag, project switch clears runs.
- `tests/core/backend/runs/test_*.py` with a stub `am` on PATH serving recorded
  fixtures: snapshot shape, backlog dropping in `runs-watch.py`, project filtering.
- `tests/contract/test_am_shapes.py`: runs the installed `am` against a throwaway
  `XDG_DATA_HOME` and pins the `runs`, `status` and `watch` shapes; skipped when
  `am` is absent (mirrors `tests/contract/test_brd_shapes.py`).
- `tests/ui/` flow tests: Runs screen filters, badge on a card, indicator click,
  Run detail navigation and Esc.
- `tests/architecture/` must pass unchanged (layers, duplicates, icon glyphs).

## Dependencies and follow-ups

Works against `am` as it is today. S4 replaces two workarounds without changing
this spec's UI: a richer `am runs` (milestone, lease, progress) removes the
`status` fan-out in `runs-snapshot.py`, and `am watch --from-now` removes the
backlog dropping in `runs-watch.py`.
