# Runs as a global destination (S6) — design

Status: proposed; supersedes the earlier "This project | All projects" scope-switch
version of this spec (never built). Builds on `2026-10-03-am-run-monitor-design.md`
(S1) and the controls spec (S2). Lands BEFORE `2026-10-05-run-events-timeline-design.md`
(S5): this milestone removes the project guards from `RunStore` and adds the
changed-run plumbing the events pane reuses, so S5 is written once against the final
store.

## Preconditions

- The run model reads the real `am status` shape (nested `stories[].subtasks[].phases[]`,
  flat `rows[]` keyed `story` / `subtask` / `state`). `Runs.normalizeRun` of a real payload
  must give a populated tree. A milestone that builds on a model that reads nothing from
  real `am` data cannot be verified; the cards say to stop and escalate when it does.
- Fixtures are recorded from the installed `am`, not hand-shaped.

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

- **Reachable with no project open.** The sidebar's Runs row is always enabled, Runs is
  reachable from the project list too, and `showSection("runs")` works with no project
  selected. Every gate that today requires a selected project on the run surfaces is lifted
  for Runs and Run detail only: `Navigator.showSection`, the `visible` of `RunsScreen` and
  `RunDetailScreen`, Panel's focus choice, search field and key catcher, `Shortcuts.handleRunKey`
  (p / r / c), and `Panel.openToastRun`. Every other section stays project-bound.
- **Default: every project, grouped.** Each group has a header (project name, counts of
  live / parked / needs-attention runs); groups with a run that needs attention come
  first, then groups with a live run, then the rest by name (case-blind, then root path);
  a project with no runs is omitted. The existing status filters (Needs attention / Live /
  Parked / All) apply across groups.
- **One list order.** `RunStore.filteredRuns` is the list in DISPLAY order (group by group,
  each group in am's order). The screen, the navigator's cursor and `handleRunKey` all index
  that one list; group headers are not cursor targets.
- **Project filter.** Chips: `All projects`, `This project` when a project is open, and one
  chip per project that has runs. The choice survives section switches while the panel is
  open and resets to `All projects` when the panel closes; it is never persisted and a
  project switch does not touch it. With one project selected the list is flat (no group
  header). A filtered project that leaves the registry, or has no runs any more, falls back
  to `All projects`.
- **Run detail** works for a run of any project without switching the open project: the
  tree, the output pane and (S5) the Events pane read through `am` by run id. Card titles
  of the OPEN project come from its board; other projects' runs show ids (see Limits).
  A run row has an **Open project** action that selects that project; the panel then shows
  that project's Board (the existing `ProjectStore.onSelected` behaviour) and Ctrl+6 returns
  to Runs.
- **Controls act on the run's OWN repository.** Pause, resume and cancel pass the run's
  `repo_dir`. A milestone resume reads the verify set from the run settings of the run's
  project (`run.project.root`), never the open project's. The store's guard is "the run the
  request was for".
- **Indicators and alerts are always global.** The toolbar `RunIndicator`, the sidebar
  attention count and the escalation toasts / desktop notification cover every registered
  project, and an alert names the project. `RunIndicator` exists but is NOT mounted in
  `Panel` today: this milestone mounts it beside `MilestoneJobIndicator`.
- **Notify on escalation is one viewer-wide switch.** It was per project (`get-run-settings`
  `notifyOnEscalation`); with global alerts a per-project switch would silence some alerts
  and not others with no way to see which. It moves to `viewer-state.py get-global-settings` /
  `set-global-settings`; the first read, when nothing is stored, is true when any project's
  stored value is true. The per-project value is no longer read or written. The switch is
  shown on the Runs screen with no project open too.
- **Alerts arm per project.** A project's first good snapshot only arms that project; a project
  whose first reply comes late, or whose reply failed, never alerts its history. A project
  whose snapshot fails keeps its previous runs and its armed state.
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
- No milestone titles for runs of other projects (Limits).

## Limits (known, not fixed here)

- `Runs.runTitle` is the run's milestone id (a UUID) or the short run id: `am` records no
  milestone title and only stories carry one. Rows therefore read `…shortid` plus the
  project group; a title lookup per project is a separate piece of work.
- Each project lists its non-terminal runs plus its 10 newest terminal ones; older runs are
  invisible, and the All chip means "all listed".

## Architecture

Same layering as S1/S2 (`docs/architecture.md`).

- `core/backend/common/am_runs.py` (new, shared): the per-project snapshot logic now in
  `runs-snapshot.py` (`am runs --repo-dir R`, then `am status` per selected run), moved
  as is so one implementation serves both helpers; the one change is that its terminal-status
  set accepts `cancelled` and `canceled` (the pending spelling migration). `runs-snapshot.py`
  keeps its exact CLI contract and output.
- `core/backend/runs/runs-snapshot-all.py <root> [<root> ...]` (new): the shared snapshot
  for each root, up to 4 roots at a time, 60 s per `am` call, one JSON line
  `{ok, projects:[{root, ok, runs?, error?}], data_dir}` with the projects in argv order.
  One project's failure does not fail the others.
- `core/backend/runs/runs-watch.py`: accepts several roots. Arguments that begin with `/`
  are roots, any other argument is a run id (run ids never begin with `/`); at least one
  root is required and a single root behaves exactly as today. The watched set is the
  argv run ids plus every run whose `run_upsert` `repo_dir` is any root.
- `core/domain/runs.js`: `withProject(run, root, name)`, `filterByProject(runs, root)` and
  `groupByProject(runs)` (ordering above; flattening into display order).
  `Runs.attention(runs)` already works over a list that spans projects, so there is no
  `attentionAcross`.
- `RunStore.qml` becomes project-independent. `projectRoots` (`[{root, name}]`, set by
  `App.qml` from the registry through an explicit property; the store never reaches into
  `ProjectStore`) drives the snapshot and the watch. `project` KEEPS its meaning, the open
  project's root (`""` when none): S3's dispatch state machine, the `This project` chip
  and Start run read it, and it is no longer a guard for anything about runs. The snapshot,
  logs, settings and control runners drop their `guard: store.project`; `projectSwitched()`
  no longer resets runs, selection, watch, toasts, pending requests or the filter. State per
  project: `runsByProject` (`{root: runs[]}`), `projectErrors` (`{root: message}`);
  `runs` is their concatenation in registry order, de-duplicated by run id (first root wins:
  two registrations can name one repository). `changedRunIds` is announced as a signal
  (`runsChanged(ids)`) for the events pane.
- UI: no-project Runs, project filter chips, group headers, **Open project** action,
  project name on toasts; `RunIndicator` mounted, and it and the sidebar count read
  `Runs.attention` / run counts over the global list.

## Refresh cost

N registered projects cost N `am runs` calls plus one `am status` per selected run
(non-terminal plus 10 terminal per project); measured on this machine one `am` call is about
0.25 s, so five projects with a full history are about 14 s sequentially. Two rules keep that
off the hot path:

1. **A change refreshes only its projects.** A watch line names run ids; the store maps them
   to the roots that listed them and runs `runs-snapshot-all.py` for those roots only. An id
   it does not know, a registry change, the panel opening and the fallback poll refresh every
   root. The 10 s liveness re-read covers only the projects that have a running run.
2. **A snapshot in flight is never killed by a change.** The store allows one in flight and
   one pending request per root set (the request asks for the union of roots wanted); the
   pending request starts when the running one ends. Today's latest-wins `HelperRunner`
   would restart a long snapshot on every journal burst and apply nothing.

Results merge per project; a project not refreshed keeps its runs. The `stale` flag is
global: set when no project has had a good reply for 30 s while the panel is open.

## Errors and edge cases

| case | behaviour |
|---|---|
| a registered root no longer exists | its group shows the error; others load |
| `am` missing | the Runs screen's single `missing` state, as today |
| no project registered | "No projects registered" empty state |
| project registry changes | the next snapshot uses the new list; a removed project's runs leave the list and its group goes |
| two registered roots name one repository | its runs are listed once, under the first |
| a control request for a run of another project | goes to that run's repo; the result and error show on that run's row, never against the open project |
| a filtered project disappears from the registry | the filter falls back to All projects |
| the run open in Run detail leaves the snapshot (its project was removed, or `am` dropped it) | Run detail shows its missing state and Back returns to the list |
| the first snapshot of a project fails | that project is not armed; alerts for it start with its first good snapshot, which only arms it |
| a project snapshot runs longer than the liveness interval | the next liveness request waits as the pending one; it never stacks |

## Testing

- `tst_runs.qml`: `withProject`, `filterByProject`, `groupByProject` ordering (attention
  first, live second, then name; ties by root; empty projects omitted; display-order
  flattening).
- Backend pytest with a fake `am`: `am_runs` moved unchanged (the existing
  `runs-snapshot.py` tests stay green untouched), `runs-snapshot-all.py` (partial failure,
  empty project, missing `am`, per-root timeout, argv order, concurrency bound),
  `runs-watch.py` with several roots (argv roots versus run ids, a stream spanning two
  repos), `viewer-state.py` global settings (default, migration read, round trip).
- `tst_run_store.qml`: per-project merge and errors, partial refresh by changed ids, no
  kill of a snapshot in flight, a project switch changes nothing, registry change,
  per-project arming, control passes the run's `repo_dir`, resume reads the run's project
  settings, a request for another project's run survives a project switch.
- `tst_app_runs.qml`: `projectRoots` follows the registry.
- `tests/ui/`: Runs reachable with no project open (sidebar, Ctrl+6, toast Open, p / r / c),
  the chips and their default and reset on close, grouping and cursor order, **Open
  project**, `RunIndicator` mounted and its counts, sidebar count and toasts across
  projects, Start run disabled without a project, the notify switch with no project.
