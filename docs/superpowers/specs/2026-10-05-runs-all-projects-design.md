# Runs as a global destination (S6) — design

Status: proposed; supersedes the earlier "This project | All projects" scope-switch
version of this spec (never built). Builds on `2026-10-03-am-run-monitor-design.md`
(S1) and the controls spec (S2); lands after `2026-10-05-run-events-timeline-design.md`
(S5) because both change `RunStore` and the Runs screen.

## Problem

Runs is a section of a project: the sidebar row is disabled with no project open and
the screen lists only the open project's runs. Runs are usually started from somewhere
else (a terminal, an agent session, another project's panel), so the run that needs
attention is often in a project that is not open, and nothing says so: no list entry,
no indicator, no toast.

## Decision

**Runs is not attached to a project.** It is a global destination that shows the runs of
every project registered with the plugin by default. There is no scope setting: the
global view is the view, and a project filter narrows it.

## Behaviour

- **Reachable with no project open.** The sidebar's Runs row is always enabled, and Runs
  is reachable from the project list too. `showSection("runs")` works with no project
  selected; nothing else about the other sections changes.
- **Default: every project, grouped.** Each group has a header (project name, counts of
  live / parked / needs-attention runs); groups with a run that needs attention come
  first, then groups with a live run, then the rest alphabetically; a project with no runs
  is omitted. The existing status filters (Needs attention / Live / Parked / All) apply
  across groups.
- **Project filter.** Chips: `All projects` (the default and the state the screen always
  opens in), `This project` when a project is open, and one chip per project that has
  runs. The choice lasts for the session and is not persisted. With one project selected
  the list is flat (no group header).
- **Run detail** works for a run of any project without switching the open project: the
  tree, the output pane and the Events pane read through `am` by run id, and card titles
  come from the run's own `am status` tree. A run row has an **Open project** action that
  switches the panel to that project.
- **Controls act on the run's OWN repository.** Pause, resume and cancel pass the run's
  `repo_dir`, never the open project's; the store's guard is "the run the request was for".
- **Indicators and alerts are always global.** The toolbar `RunIndicator`, the sidebar
  attention count and the escalation toasts / desktop notification (S2) cover every
  registered project, and an alert names the project. Opening, closing or switching a
  project does not reset or restart anything about runs.
- **Dispatch stays project-bound** (S3, S7): it starts from a card or a board of one project.
  The Runs toolbar's **Start run** works on the open project when one is open and is
  disabled with the tooltip "Open a project to dispatch" otherwise.
- **Card marks on Board and Graph** are unchanged: a run maps to a card by card id, so runs
  of other projects never match.
- A project whose snapshot fails (`am` missing, an `am` refusal, a vanished root) shows an
  inline error on its own group; the others still load.

## Non-goals

- No project is added to the registry (`brd projects` stays the registry).
- No `am` change: `am runs` stays per repository and the plugin fans out per project.
- Runs of repositories that are not registered stay invisible.

## Architecture

Same layering as S1/S2 (`docs/architecture.md`).

- `core/backend/common/am_runs.py` (new, shared): the per-project snapshot logic now in
  `runs-snapshot.py` (`am runs --repo-dir R`, then `am status` per selected run), so one
  implementation serves both helpers. `runs-snapshot.py` keeps its exact contract.
- `core/backend/runs/runs-snapshot-all.py <root> [<root> ...]` (new): the shared snapshot
  for each root, sequentially, 60 s per call, one JSON line
  `{ok, projects:[{root, ok, runs?, error?}], data_dir}`. One project's failure does not
  fail the others.
- `core/backend/runs/runs-watch.py`: accepts several roots (it already filters by
  `payload.repo_dir`); the watched set is every registered root.
- `core/domain/runs.js`: each normalized run carries `project` = `{root, name}`;
  `groupByProject(runs, projects)` (ordering above), `filterByProject(runs, root)`,
  `attentionAcross(runs)`.
- `RunStore.qml` becomes project-independent: `projectRoots` (set by `App.qml` from the
  project registry through an explicit property; the store never reaches into
  `ProjectStore`) drives the snapshot and the watch; `openProject` is an optional property
  used only for the `This project` chip and the Start run button; per-project
  `projectErrors`; `control()` uses the run's own `repo_dir`. The project-switch guards and
  resets of S1 go away for runs (the dispatch state machine keeps its own project binding).
- UI: no-project Runs, project filter chips, group headers, **Open project** action,
  project name on toasts; `RunIndicator` and the sidebar count read the global attention.

## Refresh cost

N registered projects means N `am runs` calls plus one `am status` per selected run on each
snapshot. Snapshots are already debounced to one per burst and re-run on the 10 s liveness
timer only while a run is live, so cost grows with projects, not with time. A project with
no runs costs one `am runs` call.

## Errors and edge cases

| case | behaviour |
|---|---|
| a registered root no longer exists | its group shows the error; others load |
| `am` missing | the Runs screen's single `missing` state, as today |
| no project registered | "No projects registered" empty state |
| project registry changes | the next snapshot uses the new list |
| a control request for a run of another project | goes to that run's repo; the result is not shown against the open project |
| a filtered project disappears from the registry | the filter falls back to All projects |

## Testing

- `tst_runs.qml`: `groupByProject` ordering, `filterByProject`, `attentionAcross`.
- Backend pytest with a stub `am`: the shared snapshot (unchanged outputs for
  `runs-snapshot.py`), `runs-snapshot-all.py` (partial failure, empty project, missing
  `am`, per-root timeout), `runs-watch.py` with several roots.
- `tst_run_store.qml`: multi-project refresh, per-project errors, a project switch does not
  reset runs or the watch, control passes the run's own repo, registry changes.
- `tests/ui/`: Runs reachable with no project open, the filter chips and their default,
  grouping, **Open project**, indicator and sidebar count and toasts across projects, Start
  run disabled without a project.
