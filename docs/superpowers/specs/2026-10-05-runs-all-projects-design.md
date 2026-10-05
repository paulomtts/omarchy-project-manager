# Runs: an "All projects" scope (S6) — design

Status: proposed. Builds on `2026-10-03-am-run-monitor-design.md` (S1) and the
controls spec (S2); lands after `2026-10-05-run-events-timeline-design.md` (S5)
because both change `RunStore` and the Runs screen.

## Problem

The Runs screen lists the runs of the open project only (S1's scope decision). Runs
are usually started from somewhere else (a terminal, an agent session, another
project's panel), so the run that needs attention is often in a project that is not
open, and nothing says so: no list entry, no indicator, no toast.

## Goal

A scope switch on the Runs screen, **This project | All projects**. With *All
projects* the user sees, and can control, every run of every project registered with
the plugin, grouped by project, and the indicators and alerts cover them too.

## Non-goals

- No project is added to the registry (brd's `brd projects` stays the registry).
- No `am` change: `am runs` stays per repository. The plugin fans out per project.
- No dispatching across projects: Dispatch (S3) stays tied to the open project.
- Runs of repositories that are not registered stay invisible.

## Behaviour

- Scope is a per-viewer setting, `runs_scope: "project" | "all"`, default `project`
  (today's behaviour), stored with the other viewer state and remembered.
- **All projects** list: grouped by project; each group has a header (project name,
  counts of live / parked / needs-attention runs); groups with a run that needs
  attention come first, then groups with a live run, then the rest alphabetically; a
  group with no runs is omitted. The existing filters (Needs attention / Live /
  Parked / All) apply across all groups.
- Run detail works for a run of any project without switching the open project:
  the tree, the output pane and the Events pane read through `am` by run id.
  Card titles come from the run's own `am status` tree, not from the open project's
  board. A run row has an **Open project** action that switches the panel to that
  project.
- Controls (S2) act on the run's OWN repository: pause, resume and cancel pass the
  run's `repo_dir`, never the open project's. The store's guard becomes
  "the run the request was for".
- Indicators and alerts follow the scope: with *All projects*, the toolbar
  `RunIndicator`, the sidebar attention count and the escalation toasts / desktop
  notification (S2) cover every registered project, and an alert names the project.
  With *This project* nothing changes.
- A project whose snapshot fails (`am` missing, an `am` refusal, a vanished root)
  shows an inline error on its own group header; the other projects still load.

## Architecture

Same layering as S1/S2 (`docs/architecture.md`).

- `core/backend/common/am_runs.py` (new, shared): the per-project snapshot logic now
  in `runs-snapshot.py` (`am runs --repo-dir R`, then `am status` per selected run),
  so one implementation serves both helpers. `runs-snapshot.py` keeps its exact
  contract and output.
- `core/backend/runs/runs-snapshot-all.py <root> [<root> ...]` (new): runs the shared
  snapshot for each root (sequentially, 60 s per call) and prints one JSON line
  `{ok, projects:[{root, ok, runs?, error?}], data_dir}`. One project's failure does
  not fail the others.
- `core/backend/runs/runs-watch.py`: accepts several project roots (it already filters
  by `payload.repo_dir`); the watched set is every registered root.
- `run-control.py` and the run's `repo_dir`: unchanged helper; the STORE passes
  `run.repo_dir`. `runs-logs.py` and `runs-events.py` already resolve by run id.
- `core/domain/runs.js`: each normalized run carries `project` = `{root, name}`;
  `groupByProject(runs, projects)` (ordering rules above), `attentionAcross(runs)`,
  `scopedRuns(runs, scope, openRoot)`.
- `RunStore.qml`: `scope`, `projectRoots` (set by `App.qml` from the project
  registry through an explicit property; the store never reaches into
  `ProjectStore`), `runs` for the active scope, per-project `projectErrors`. In
  *project* scope it behaves exactly as today. In *all* scope it snapshots every root
  and watches every root. `control()` uses the run's own `repo_dir`.
- `viewer-state.py`: `get-runs-scope` / `set-runs-scope` (or a field in the existing
  run settings; reuse whichever store the S2 settings use).
- UI: scope chips on `RunsScreen`, project group headers in the list, an **Open
  project** row action, project name on toasts; `RunIndicator` and the sidebar count
  read the scoped attention.

## Refresh cost

N registered projects means N `am runs` calls plus one `am status` per selected run
on each snapshot. The snapshot is already debounced to one per burst and re-run on
the 10 s liveness timer only while a run is live, so the cost grows with projects,
not with time. A project with no runs costs one `am runs` call.

## Errors and edge cases

| case | behaviour |
|---|---|
| a registered root no longer exists | its group shows the error; others load |
| `am` missing | the Runs screen's single `missing` state, as today |
| a run id appears in two projects | impossible (ids include a timestamp and a card id); dedupe by id anyway |
| scope switched while a snapshot is running | latest wins; the old reply is dropped |
| project registry changes (project added/removed) | next snapshot uses the new list |
| a control request for a run of another project | goes to that run's repo; the result is not shown against the open project |

## Testing

- `tst_runs.qml`: `groupByProject` ordering (attention first, live next, then
  alphabetical, empty omitted), `attentionAcross`, `scopedRuns`.
- Backend pytest with a stub `am`: the shared snapshot (unchanged outputs for
  `runs-snapshot.py`), `runs-snapshot-all.py` (partial failure, empty project, missing
  `am`, per-root timeout), `runs-watch.py` with several roots.
- `tst_run_store.qml`: scope persistence, multi-project refresh, per-project errors,
  control passes the run's own repo, project-registry change, scope switch races.
- `tests/ui/`: scope chips, grouped list, Open project, indicator and sidebar count
  under both scopes, toast shows the project name.

## Open

- A user-wide view that includes unregistered repositories would need an `am` change
  (`am runs` across repositories); not part of this spec.
