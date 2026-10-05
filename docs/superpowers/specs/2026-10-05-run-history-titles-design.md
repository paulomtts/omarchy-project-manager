# Run history and titles — design

Status: proposed. Last of the queued run milestones. Builds on **Align the run model with
real am** (normalized run shape, `tests/fixtures/am/*`), **Runs: a global destination**
(`2026-10-05-runs-all-projects-design.md`: `projectRoots`, `runsByProject`, the grouped
list, `common/am_runs.py`), **Dispatch at story level** (`story_id` on an `am runs` row),
**Run events timeline** (its `titles` input) and **Split RunStore** (`RunStore`: snapshot,
watch, selection, events; `RunAlertsStore`: alerts and notifications). Written against the
post-split store names.

## Problem

1. **History is capped and cannot be widened.** The snapshot takes every non-terminal run
   plus the 10 newest terminal ones per project (`core/backend/runs/runs-snapshot.py:33-34`
   `TERMINAL`/`TERMINAL_LIMIT`, `select_runs` at `:95-104`; moved as is into
   `common/am_runs.py` by the global milestone). Older runs are invisible, and `stopped`
   counts toward the cap although it is a parked, resumable run: the 11th-newest parked run
   disappears from the list.
2. **No filter by final state or age.** The chips are Needs attention / Live / Parked / All
   (`core/domain/runs.js:383-403`). A finished run is only reachable under All.
3. **Runs have no readable title outside the open project.** `Runs.runTitle` is the
   milestone UUID, else the short run id (`runs.js:319-322`). `am` records no milestone or
   subtask title: in `am status` only `stories[].title` exists (checked on
   `20261004T204141Z-cb11063d`: `run` has `id, status, workflow, repo_dir, base_branch,
   branch_prefix, started_at`; subtasks have `card_id, branch, base_branch, status, phases,
   worktree_path`). The Run detail tree prints card ids and adds a title only from the open
   project's board (`ui/screens/RunDetailScreen.qml:70-79` reads `app.board.cardMap`). Toasts,
   the cancel dialog, the search and the card RUNS rows all use the same `runTitle`
   (`runs.js:413`, `:768`, `ui/Panel.qml:677`, `ui/screens/CardDetailScreen.qml:235`,
   `ui/screens/RunsScreen.qml:207`).

## How the plugin reads a board today (reused, not duplicated)

`BoardStore.fetchBoard()` runs `brd tree` as a plain `Process` with `workingDirectory` set
to the project root (`core/stores/BoardStore.qml:53-61`, `:220-243`): brd has no project
flag, it finds the project from the working directory (from `/tmp` it answers
`{"ok":false,"error":{"type":"ProjectNotFoundError",…}}`). `Board.indexTree` builds
`cardMap` (id → card) from it (`core/domain/board.js:12`). A `FileView` on the project's
database (path from `projects/resolve-db-path.py`) debounces a refetch on every brd write
(`BoardStore.qml:199-218`).

Measured on this machine: `brd tree` takes 0.08–0.21 s and prints 18 KB–934 KB (ori: 933
cards, descriptions included); `am runs` 0.22–0.45 s; one `am status` about 0.25 s.

## Goal

- Every run row reads as its work: the milestone title (a `--card` run: the subtask title;
  a `--story` run: the story title), with the short run id as secondary text, for runs of
  any registered project. Run detail's tree titles every story and subtask.
- Older finished runs can be shown on request, a bounded page at a time, filtered by final
  state and by age.

## Non-goals

- No `am` or `brd` change. No reading brd's or am's database.
- No persisted history settings; no history for unregistered repositories.
- No title editing; no brd status shown for another project's cards.

## Titles

### Lookup

- **The open project**: titles come from `BoardStore.cardMap`, which already follows the
  database watch. No second `brd tree` for it.
- **Every other project**: a new read-only helper,
  `core/backend/boards/board-titles.py ROOT`. It runs `brd tree` (argv list, `cwd=ROOT`,
  stdin `/dev/null`, 30 s timeout) — the same command and working-directory rule as
  `BoardStore` — and prints ONE JSON line `{"ok": true, "titles": {id: title}}` for every
  card at any depth, descriptions dropped (ori's map is a few KB, not 934 KB). Failures:
  brd's own `ok:false` envelope unchanged (e.g. `ProjectNotFoundError`), `BrdMissing`,
  `BrdBadOutput`, `RootMissing` (ROOT is not a directory), `HelperError`, `Usage` (exit 2).
  Exit 0 otherwise. It never writes.

### Cache and invalidation: `core/stores/RunTitlesStore.qml` (new)

`App` hands it `projectRoots`, `openRoot` (the open project's root, `""` when none),
`openCardMap` (`BoardStore.cardMap`), `active`, `backendDir`, and the run list. State:
`titlesByRoot` (`{root: {id: title}}`, the open root mirrored from `openCardMap` through
`Runs.titlesFromCards`), `titleStatus` (`{root: "loading" | "ok" | "unreachable"}`).

- One `HelperRunner`, one root at a time, roots queued without duplicates.
- A root is fetched when a listed run of that project needs a title and the root has no
  entry; when a run names an id (milestone, story, card, subtask) missing from an `ok` map
  (at most once per root until its next fetch lands, so an id brd does not have never loops);
  when the panel opens (every cached root is marked stale and refetched on its next need);
  and on demand (`refreshTitles()`, the Runs footer's **Refresh titles**).
- The open project's map changes with its board (the database watch). A registry change
  drops the maps of removed roots.
- **Unreachable** (`ProjectNotFoundError`, brd missing, a vanished root, a timeout): the
  root's status is `unreachable`, its runs fall back to ids, and it is not asked again until
  `refreshTitles()`, the panel reopening or a registry change. No toast, no banner, no
  `urgent` text: its group header carries a dim `titles unavailable` caption.

### Display: `core/domain/runs.js`

- `titlesFromCards(cardMap)`: `{id: title}` from an `indexTree` map.
- `runTitle(run, titles)`: a `--card` run (`card_id`): the card's title; a story run
  (`story_id`): the story's title, else `am status`' story title; a milestone run: the
  milestone's title. Fallback: `milestone …<last 8>`, `story …<last 8>` or `card …<last 8>`;
  the short run id when the run names nothing. Callers pass the run's project map
  (`titlesByRoot[run.project.root]`); a missing map is `{}`.
- `runSubtitle(run)`: `Runs.shortId(run)`.
- `cardTitle(id, run, titles)`: a tree card's title (the map, else the run's own story title),
  `""` when unknown — the tree then shows the short card id.
- `searchRuns(runs, q, titlesByRoot)` matches the title too; `newAlerts(prev, next,
  titlesByRoot)` uses it for the toast and the desktop notification.

### Where titles show

Runs rows (title, then the short id in `dim`), Run detail's header and tree (story >
subtask titles; ids only as fallback), the Events pane's `titles` input (now the run's
project map, so subtasks of a project that is not open get titles too), toasts and the
desktop notification, the cancel dialog's detail, and the card RUNS rows.

## History

### Data: `core/backend/runs/runs-history.py`

`runs-history.py ROOT --before ISO [--limit K] [--status S,…] [--since ISO]`: runs `am runs
--repo-dir ROOT` (newest first), keeps the rows whose status is in `--status` (default every
terminal-for-the-cap status: `done, escalated, stopped, cancelled, canceled`), whose
`started_at` is strictly before `--before` and, with `--since`, not before `--since`; takes
the first `K` (default 10, at most 25); runs `am status ID --repo-dir ROOT` for each (60 s per
call, as the snapshot); prints `{"ok": true, "runs": [{<am runs row>, "status": <am status
data>}], "more": bool}` — the same run shape as the snapshot, so `Runs.normalizeRun` and Run
detail work unchanged. Errors as the snapshot (`AmMissing`, `AmBadOutput`, am's envelope,
`HelperError`, `Usage`). Shares `common/am_runs.py`'s `call_am` and run-list check; nothing
is duplicated. Cost: one page is one `am runs` plus at most 10 `am status`, about 2.75 s.

### Filters: `core/domain/runs.js`

- Chips: Needs attention / Live / Parked / **Finished** / All. `filterRuns(runs, "finished")`
  keeps `done`, `escalated`, `cancelled`, `canceled`.
- Under Finished, a second chip row: **All finished / Done / Escalated / Cancelled**
  (`finishedState`).
- Under Finished and All, an age row: **Today / 7 days / All time** (`finishedAge`,
  default All time). Age is `started_at` (`am runs` and `am status` record no end time):
  Today is since local midnight, 7 days is the last 7×24 h.
  `withinAge(run, age, nowMs, utcOffsetMinutes)` is pure; tests pass fixed offsets.
- Age and finished-state filters never hide a run that is not finished (live, parked, dead).
- `historyStatuses(filter, finishedState)`: the `--status` list for a page under the
  current chips (All: all five; Parked: `stopped`; Needs attention: `escalated`; Finished: the
  chip's states). `historyCursor(runs, root)`: the oldest `started_at` among the listed
  terminal runs of that project.

### Store: `core/stores/RunHistoryStore.qml` (new)

`App` hands it `backendDir`, `active`, `snapshotByProject` (`RunStore.runsByProject`) and the
filter values. State per root: `historyByProject` (`{root: {runs, more, loading, error}}`).

- `showOlder(root)`: one page with `--before historyCursor`, the filter's `--status` and
  `--since`, latest wins per root. Rows already listed are dropped (snapshot wins).
- A terminal run that leaves a project's snapshot window (a newer run finished) while that
  project has history loaded moves into its history list; am never deletes a run, so it is
  still there and the list never gains a hole.
- A changed state or age filter drops every loaded page (they were fetched under the old
  filter); the panel closing drops them all; a registry change drops removed roots. The
  project filter keeps them.
- `runs` reach `RunStore.filteredRuns` through App (`historyRuns`): the display order puts a
  project's history after its snapshot runs, newest first. History runs are never compared
  by `RunAlertsStore` (alerts read the snapshot only), and the watch's changed ids never
  refetch history; a resumed history run shows up in the snapshot, which wins.

### UI

```
 [Needs attention 1] [Live 2] [Parked] [Finished 9] [All]
 [All finished] [Done] [Escalated] [Cancelled]   ·   [Today] [7 days] [All time]
 ── omarchy-project-manager ───────────────── ⟳1 ‼1 ─────
 ✔ am run controls and alerts          10/10 · 14h      …cb11063d
 ✔ am run monitor (read-only)          15/15 · 1d       …9c0be3a1
                                   [Show older]
 ── ori ───────────────────── titles unavailable ────────
 ✔ milestone …4f8e21aa                 6/6 · 3d         …77a1d0c2
```

- **Show older** sits at the end of each project's group (one at the end of a flat,
  filtered list) when that project listed `TERMINAL_LIMIT` terminal runs or its last page
  said `more`; it reads `Loading older runs…` while a page is in flight and the error sentence
  in `urgent` on failure. It is a button, not a cursor row.
- **Refresh titles** in the Runs footer calls `refreshTitles()`.
- Run detail of a history run is the same screen; its controls follow `Runs.controls`.

## Errors

| case | behaviour |
|---|---|
| a project's board unreachable | ids, dim `titles unavailable` on its group, no retry until Refresh titles / reopen / registry change |
| a card id brd no longer has | short id; asked once per fetch |
| a history page fails | its button shows the error; loaded rows stay |
| a filter change during a page | the reply is dropped (latest wins), pages cleared |
| `am` missing | Runs' missing state; no history, no title fetches |
| a project with no runs | no title fetch |

## Testing

- `tests/core/backend/boards/test_board_titles.py` (fake `brd`): argv and `cwd`, nested
  cards flattened, descriptions dropped, brd's envelope passthrough, missing brd, missing
  root, bad output, one line on every path.
- `tests/core/backend/runs/test_runs_history.py` (fake `am`): `--before`, `--since`,
  `--status` with both cancel spellings, limit and `more`, `am status` per row, envelope
  passthrough, missing `am`; `test_runs_snapshot.py` stays green untouched.
- `tests/core/domain/tst_runs.qml`: `titlesFromCards`, `runTitle` for milestone, story and
  card runs with and without titles, `cardTitle`, title search, alert titles; `filterRuns`
  finished, `withinAge` at fixed offsets around midnight, `historyStatuses`, `historyCursor`,
  non-finished runs never hidden. Fixtures from `tests/fixtures/am/`.
- `tests/core/stores/tst_run_titles_store.qml`: open project from `openCardMap`, queue one at
  a time, missing-id refetch once, unreachable stays quiet, Refresh, panel reopen, registry
  change. `tst_run_history_store.qml`: page cursor, dedupe, window overflow moves runs into
  history, filter change and close drop pages, latest wins. `tst_run_store.qml`: history in
  the display order, chips. `tst_run_alerts_store.qml`: titled toasts.
- `tests/ui/`: titled rows with the short id, the Finished chip and its two rows, Show
  older (visible, loading, error, gone when exhausted), `titles unavailable`, Refresh
  titles, Run detail titles for a project that is not open.

## Open questions

- Should Finished include `stopped` runs older than the cap? They are parked, so they stay
  under Parked and All, and Show older under Parked fetches them.
- Should age use the run's last phase `ended_at` (only in `am status`, per phase) instead
  of `started_at`? Started is chosen because it is on the `am runs` row the page filter reads.
