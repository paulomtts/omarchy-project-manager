# Runs as a global destination (S6) — design

Status: proposed; retargeted to the new `am` (single store, `am runs --all-projects`, one global
watch; `2026-10-06-am-snapshots-cursors-design.md`, row glb); supersedes the earlier "This project | All projects" scope-switch
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
- The installed `am` is the new one (single store): `am runs --all-projects` exists, each row
  carries `project: {id, repo_dir}` and the envelope carries `as_of_seq`. With an older `am` the
  panel shows the schema banner (the plugin needs the newer `am`); there is no per-project
  fallback.

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
- **Alerts arm on the first good snapshot.** That snapshot only arms; it never alerts its
  history. A project registered later is armed by the first snapshot that lists it. A failed
  snapshot keeps the previous runs and the armed state. Alerts while the panel is closed are the
  alerts spec's persisted cursor, not this arming.
- **Dispatch stays project-bound** (S3, S7): it starts from a card or a board of one project.
  The Runs toolbar's **Start run** works on the open project when one is open and is
  disabled with the tooltip "Open a project to dispatch" otherwise.
- **Card marks on Board and Graph** are unchanged: a run maps to a card by card id, so runs
  of other projects never match.
- The snapshot is one call, so a failure (`am` missing, an `am` refusal) is the list's error, not
  a group's. A registered project whose root has vanished still lists its runs: they come from
  `am`, not from the path.

## Non-goals

- No project is added to the registry (`brd projects` stays the registry).
- No per-project fan-out: one `am runs --all-projects` call returns every project's runs and the
  plugin filters by the registry.
- Runs of repositories that are not registered stay invisible.
- No milestone titles for runs of other projects (Limits).

## Limits (known, not fixed here)

- `Runs.runTitle` is the run's milestone id (a UUID) or the short run id: `am` records no
  milestone title and only stories carry one. Rows therefore read `…shortid` plus the
  project group; a title lookup per project is a separate piece of work.
- The snapshot lists every non-terminal run plus the newest terminal ones (`--limit`, same
  selection rule as `runs-snapshot.py`); older runs are invisible here (run history pages them),
  and the All chip means "all listed".

## Architecture

Same layering as S1/S2 (`docs/architecture.md`).

- No `core/backend/common/am_runs.py` and no `runs-snapshot-all.py`: there is no per-root fan-out
  to share. `core/backend/runs/runs-snapshot.py` runs `am runs --all-projects --limit N`, then
  `am status RUN` per selected run (every non-terminal run plus the newest K terminal ones), and
  forwards `as_of_seq`; its `<project_root>` argument becomes an optional filter (milestone 4,
  story 4.1.3). Its terminal-status set accepts `cancelled` and `canceled`.
- `core/backend/runs/runs-watch.py` takes no roots and no run ids: it follows
  `am watch --all-projects --follow` and prints nudges and a cursor (milestone 4, story 4.1.1;
  the nudge contract is in `2026-10-06-am-snapshots-cursors-design.md`). The registry filter
  happens in the store, from `project.repo_dir`.
- `core/domain/runs.js`: `withProject(run, root, name)` (resolved from the row's
  `project.repo_dir` and the registry name), `filterByProject(runs, root)` and
  `groupByProject(runs)` (ordering above; flattening into display order).
  `Runs.attention(runs)` already works over a list that spans projects, so there is no
  `attentionAcross`.
- `RunStore.qml` becomes project-independent. `projectRoots` (`[{root, name}]`, set by
  `App.qml` from the registry through an explicit property; the store never reaches into
  `ProjectStore`) is the registry filter: the store shows only runs whose `project.repo_dir` is a
  registered root. `project` KEEPS its meaning, the open
  project's root (`""` when none): S3's dispatch state machine, the `This project` chip
  and Start run read it, and it is no longer a guard for anything about runs. The snapshot,
  logs, settings and control runners drop their `guard: store.project`; `projectSwitched()`
  no longer resets runs, selection, watch, toasts, pending requests or the filter. `runs` is the
  filtered snapshot; `runsByProject` (`{root: runs[]}`) is derived by grouping on
  `project.repo_dir` (two registrations naming one repository share one group, named by the
  first); there is one list error, no per-project errors. `changedRunIds` is announced as a
  signal (`runsChanged(ids)`) for the events pane; it comes from the watch nudges
  (`changed: [{run, seq}]`), which refresh that run's snapshot, never fold into state.
- UI: no-project Runs, project filter chips, group headers, **Open project** action,
  project name on toasts; `RunIndicator` mounted, and it and the sidebar count read
  `Runs.attention` / run counts over the global list.

## Refresh cost

A full refresh is one `am runs --all-projects` call plus one `am status` per selected run
(non-terminal plus the newest terminal ones); the list refresh is one call regardless of the
number of projects. Two rules keep the hot path small:

1. **A nudge refreshes one run.** A watch line names run ids and seqs; the store runs
   `am status RUN` for a run whose nudge seq is above the `as_of_seq` it already holds, and the
   list call only for an unknown run, a registry change, the panel opening and the fallback
   poll. The 10 s liveness re-read is the list call.
2. **A snapshot in flight is never killed by a change.** The store allows one in flight and
   one pending request; the pending request starts when the running one ends. A latest-wins
   `HelperRunner` would restart a long snapshot on every nudge burst and apply nothing.

The `stale` flag is set when no good reply has arrived for 30 s while the panel is open.

## Errors and edge cases

| case | behaviour |
|---|---|
| a registered root no longer exists | its runs still list (they come from `am`); nothing special |
| `am` missing | the Runs screen's single `missing` state, as today |
| no project registered | "No projects registered" empty state |
| project registry changes | the filter uses the new list at once; a removed project's runs leave the list and its group goes |
| two registered roots name one repository | its runs are listed once, under the first |
| a control request for a run of another project | goes to that run's repo; the result and error show on that run's row, never against the open project |
| a filtered project disappears from the registry | the filter falls back to All projects |
| the run open in Run detail leaves the snapshot (its project was removed, or `am` dropped it) | Run detail shows its missing state and Back returns to the list |
| the first snapshot fails | alerts start with the first good snapshot, which only arms |
| `am` too old (no `as_of_seq` or `project` in the reply) | the schema banner; no list |
| a snapshot runs longer than the liveness interval | the next liveness request waits as the pending one; it never stacks |

## Testing

- `tst_runs.qml`: `withProject`, `filterByProject`, `groupByProject` ordering (attention
  first, live second, then name; ties by root; empty projects omitted; display-order
  flattening).
- Backend pytest with a fake `am`: `runs-snapshot.py --all-projects` (rows with `project`,
  `as_of_seq` forwarded, missing `am`, an old `am`), `runs-watch.py` global argv (no roots, no
  run ids; a stream spanning two repos), `viewer-state.py` global settings (default, migration
  read, round trip).
- `tst_run_store.qml`: grouping by `project.repo_dir` with registry filtering, refresh of one
  run on a nudge, no kill of a snapshot in flight, a project switch changes nothing, registry
  change, arming on the first good snapshot, control passes the run's `repo_dir`, resume reads
  the run's project settings, a request for another project's run survives a project switch.
- `tst_app_runs.qml`: `projectRoots` follows the registry.
- `tests/ui/`: Runs reachable with no project open (sidebar, Ctrl+6, toast Open, p / r / c),
  the chips and their default and reset on close, grouping and cursor order, **Open
  project**, `RunIndicator` mounted and its counts, sidebar count and toasts across
  projects, Start run disabled without a project, the notify switch with no project.
