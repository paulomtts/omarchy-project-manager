# 4.6 Docs: Runs as a global destination (card 63012a7b)

Parent story: 63a11d2f. Milestone spec: `docs/superpowers/specs/2026-10-05-runs-all-projects-design.md` (cited below as **S6**). Blocked by 86d8790e (4.5, done: commits b0a666a..0a3b562).

## Scope

Docs only. Edit `docs/architecture.md` and `README.md` so they describe Runs as a global destination **as built** in 4.1 to 4.5. Change no QML, JS, Python, test or other file. Do not edit any file under `docs/superpowers/specs/` or `docs/superpowers/plans/`: those are history.

**The code wins over S6.** The card says "State only what the code does". S6 promised a single `am runs --all-projects` call, no `runs-snapshot-all.py`, no `am_runs.py`, no per-project errors, per-run reads on a nudge and `as_of_seq` coverage (S6 L3-4, L88-90, L95-96, L113-121, L135-139, L146-153). The code does a **per-project fan-out** instead. Where S6 and the code disagree, write what the code does. Do not write the S6 version and do not mention the disagreement in the docs.

Before writing a sentence about a file, read that file. The facts below were gathered at HEAD 0a3b562. The executor must re-check each one against the named source and not copy it blindly.

## Inherited constraints

- Layering and section order of `docs/architecture.md` stay as they are (S6 L111 "Same layering as S1/S2 (`docs/architecture.md`)"). Extend or rewrite the existing entries. Never write a second copy of an entry.
- Runs of unregistered repositories stay invisible (S6 L97). `brd projects` stays the registry (S6 L94).
- Dispatch stays project-bound. **Start run** is disabled with the tooltip "Open a project to dispatch" when no project is open (S6 L83-85).
- Card marks on Board and Graph are unchanged (S6 L86-87). Do not reword their docs.
- Notify on escalation is one viewer-wide switch (S6 L73-78). The code agrees.
- Alerts arm on the first good snapshot (S6 L79-82). The code does this **per project root**.
- Each project lists its non-terminal runs plus its 10 newest terminal ones (S6 L105-107; `core/backend/common/am_runs.py` `TERMINAL_LIMIT = 10`, `LIST_LIMIT = 200`).
- House style: `docs/architecture.md` uses one long bullet or paragraph line per entry, names properties and functions in backticks, and writes ` -- ` for a dash. `README.md` writes ` - `. Add no emoji. Use no glyph outside the ones the docs already use (⟳ ⏸ ‼ ✖ ⊘ ✔ ›).
- Docstrings and comments are not touched. No source file changes.

## Facts the docs must state (from the code)

Each fact names its source. The plan's tasks place them into the passages listed in the next section.

**F1. Fan-out.** `RunStore` (`core/stores/RunStore.qml` header L6-37, `usableRoots`, `mergedRuns`) makes one list snapshot by running `core/backend/runs/runs-snapshot-all.py` with every usable root of `projectRoots`, in registry order. A usable root is a non-empty string that does not start with `-`; roots are deduplicated. `App.qml` (~L109) sets `projectRoots` from `app.projects.projects` as `[{root, name}]`; the store never reaches into another store. The helper runs `am runs --repo-dir <root> --limit 200` for each root, then `am status <id>` (never with `--repo-dir`) for every non-terminal run and the first 10 terminal ones. It runs up to 4 roots at once, gives each am call 60 s, and reports a failure in that root's entry only. The failure types are `RootMissing`, `AmMissing`, `AmTimeout`, `AmBadOutput`, `SchemaMismatch`, `HelperError`, or am's own error envelope (see the helper's docstring).

**F2. State.** `runsByProject` is `{root: runs[]}`: each root's runs, normalized and tagged with their project (`Runs.withProject`). `projectErrors` is `{root: sentence}` for each root whose latest entry failed. A failed root keeps its previous runs. `runs` is every root merged in registry order. A run id is listed once, under the first root that lists it. `amStatus` is `missing` when every entry is `AmMissing`, and `error` when no entry matched. Only runs of registered roots appear, because unregistered repositories are never asked. With no usable root, `refresh()` launches nothing and empties `runs`, `runsByProject` and `projectErrors`. There are **no run reads**: `asOfSeq` is always 0 and `appliedSeq` is `{runId: 0}` for every listed run (RunStore L85-89, L1007-1019), so a snapshot only names which ids the store knows; it is not coverage. Do not describe it as run-read coverage, and do not say it is empty. Check this in RunStore before writing, and delete every doc sentence about `readRunners`, `runs-snapshot.py --run` used by the store, `appliedSeq`/`asOfSeq` coverage, or StoreBusy/UnknownRun handling in the store.

**F3. Partial refresh and cost rules.** These are in RunStore `requestSnapshot`, `snapshotEnded`, `triggerNudges`, `refreshLive` and `registryChanged`.
- `requestSnapshot(roots | "all")` allows one snapshot in flight plus **one** pending request, and a request never kills the snapshot in flight. When the pending requests merge, `"all"` wins; otherwise their roots are unioned. The pending request launches against the registry as it is when the running snapshot ends.
- On a watch nudge (250 ms debounce), the store emits `runsNudged(ids)`, then snapshots only the roots whose `runsByProject` lists those ids. If some id is listed by no root, it snapshots every root.
- The liveness tick (`livenessTimer`, 10 s, armed while a run is running) snapshots only the roots that hold a running run.
- A registry change drops the runs, errors and arming of roots that left, re-merges the list without raising an alert, then snapshots every root.
- When the panel opens (`startLive`), the store refreshes every root, reads the global settings and starts the stale clock. The `stale` flag means no good reply for 30 s while the panel is open.
- When the panel closes (`stopLive`), `projectFilter` returns to `""`, the pending request is dropped, the watch and timers stop, and `armedRoots` and toasts are cleared. `runs` is kept.

**F4. Watch.** `runs-watch.py` is started with every usable root that begins with `/` (`watchableRoots`) plus every known run id (`knownRunIds`). It is restarted after a good snapshot when the watchable roots changed. It follows `am watch --all-projects --follow` and nudges only the argv run ids and the runs whose `run_upsert` `repo_dir` has the same realpath as a root. A `cursorReset` hello or a new `storeId` starts over with a full snapshot. A `SchemaMismatch` or a `CorruptJournal` switches to the 5 s poll. Keep the existing helper prose at architecture L196 where it is still true.

**F5. Per-project arming.** These are in RunStore `armedRoots`, `alertsOf` and `alertsArmed`.
- `armedRoots` is `{root: true}`. A root is armed by its first ok entry, and that entry only arms: it never alerts the history it lists.
- Alerts (`Runs.newAlerts`) are raised only for roots that are armed and answered ok in this reply. Each run id is alerted once, and each alert carries the `project` name.
- A project registered later is armed by the first snapshot that lists it.
- A failed entry, a root with no entry, or a closed panel never changes `armedRoots`.
- `AmMissing` disarms every root. A root that leaves the registry loses its arming.
- `alertsArmed` is true when any root is armed.
- A toast is `{key, id, title, state, reason, project, expiresMs}`, with at most 3 shown. `RunToast` shows the project under the heading.

**F6. Project filter.** These are in RunStore `projectFilter`, `toggleProjectFilter`, `keepProjectFilter`, `groups` and `filteredRuns`.
- `projectFilter` is `""` for All projects, otherwise a root that is registered, usable and has at least one run.
- `toggleProjectFilter(root)` selects that root. Toggling the active root, a non-filterable root or `""` selects All projects. It emits `projectFilterToggled` once per call.
- The filter falls back to `""` when its project leaves the registry or has no runs any more.
- **Lifetime:** the filter survives a section switch and a project switch, resets to All projects when the panel closes, and is never persisted.
- `filteredRuns` is `Runs.displayOrder(Runs.groupByProject(Runs.filterByProject(Runs.searchRuns(Runs.filterRuns(runs, runFilter), searchQuery), projectFilter)))`. Display order puts groups with a run that needs attention first, then groups with a live run, then the rest by name. Each group keeps am's order. The screen, the navigator cursor and `handleRunKey` index this one list.

**F7. Controls act on the run's own repo.** These are in RunStore `control()` and `projectSwitched`.
- `control()` refuses a run with no `repo_dir`, a non-task resume of a run with no `project.root`, a disabled action, and a run that already has a request pending. Having no project open is not a refusal.
- A resume reads `get-run-settings` of `run.project.root`.
- A project switch keeps pending requests, the control error, the cancel dialog and the flash. It resets only `runSettings` and the dispatch.
- Logs use the selected run's project root (`runs-logs.py`). Without that root, nothing launches.

**F8. Viewer-wide notify.** These are in RunStore ~L158-160 and ~L1395-1430, and `core/backend/projects/viewer-state.py`.
- The switch is read with `viewer-state.py get-global-settings`. On the first read with nothing stored, it is true when any project's stored value is true.
- It is saved with `set-global-settings`. `notifyTouched` stops a late load from overwriting a change. When a save fails, the switch goes back to `notifySaved` and the flash reads "Notify on escalation could not be saved".
- The per-project value is no longer read or written. `runSettings` (`get-run-settings` of the open project) only feeds dispatch.

**F9. UI.**
- `ui/Panel.qml` mounts `RunIndicator` in the toolbar with `runCounts = Runs.runFilterCounts(runs)` over every registered project. A segment click (`showRunsFiltered(filter)`) opens Runs on All projects with that status chip.
- Panel feeds the Sidebar `runsAttention: Runs.attention(runs).length`.
- Runs and Run detail are visible with no project open. A toast's Open works with no project open too.
- `ui/screens/RunsScreen.qml` has:
  - a project chip row: All projects, This project when a project is open, and one chip per project with runs, with its count;
  - status chip counts taken within the project filter;
  - group headers that show the `projectErrors` sentence;
  - a flat list under a project filter;
  - an **Open project** action on the cursor row of another registered project's run;
  - the Notify on escalation switch, also shown with no project open.
- `ui/Navigator.qml` opens Runs and Run detail with no project open.
- `ui/Shortcuts.qml`: p / r / c work without a project, and `d` stays project-bound.
- `ui/components/Sidebar.qml`: the Runs row is never disabled.
- Executor: confirm each item, with its line, before writing it.

**F10. Domain.** `core/domain/runs.js` exports `withProject(run, root, name)`, `filterByProject(runs, root)`, `groupByProject(runs)` and `displayOrder(groups)` (verified: L363, L378, L419, L453).

## Passages to change

### docs/architecture.md

1. **RunStore bullet (L83-92).**
   - Rewrite L83-88 to F1, F2, F3, F4 and F5, and F6 where it touches the store.
   - Remove "kept to the rows whose project is the selected one", "App hands it project" as the run guard, everything about run reads, `appliedSeq`/`asOfSeq` semantics, and "A project switch clears nudges ...".
   - Keep L89-90 (chips, logs) where they are still true, and make the logs sentence match F7.
   - Keep L91 (controls) and make it match F7.
   - Keep L92 (dispatch) as it is.
   - Add the global notify switch (F8).
2. **Navigator and Shortcuts paragraphs (~L94-108).** Runs and Run detail open with no project. p / r / c work without a project, and `d` stays project-bound (F9).
3. **RunIndicator (~L149) and Sidebar (~L160).** Add that Panel mounts `RunIndicator`, with counts over every registered project and a segment click that opens Runs filtered (F9). The phrase "not yet mounted" is not in the file at HEAD (grep confirms), so there is no sentence to delete. If an equivalent phrase is found, rewrite it.
4. **Run screens paragraph (~L165).** Add F9's RunsScreen items and no-project reachability. Replace the per-project notify wording ("the setting is the project's") with F8. Add the disabled Start run tooltip.
5. **Refresh model paragraph (~L171).** Replace "one run read ... `runs-snapshot.py --run`" with the F3 partial-refresh rules. Keep "no timers while idle".
6. **Domain helpers, `runs.js` (~L180).** Add `withProject`, `filterByProject`, `groupByProject` and `displayOrder`, with the ordering rule in F6.
7. **`core/backend/runs/` paragraph (L196).** State that `RunStore` uses `runs-snapshot-all.py`, not `runs-snapshot.py`. The no-argument and `--run` modes of `runs-snapshot.py` still exist and are not used by the store (confirm with grep of `RunStore.qml`). Make the `runs-snapshot-all.py` failure list match the helper's docstring (add `AmBadOutput` and `SchemaMismatch`). Keep the `am_runs` mention at L182-183.
8. Test-section references (~L226-262) stay as they are unless they claim the store makes run reads.

### README.md

1. **L8:** Runs are of every registered project, watched and also controlled. Do not keep "never controlled" if the code controls runs; it does (pause/resume/cancel).
2. **L154 Runs bullet:**
   - Runs is global and reachable with no project open.
   - By default it lists every registered project's runs in groups. A project filter (All projects / This project / one chip per project) survives a section or project switch and resets when the panel closes.
   - Each project lists its non-terminal runs plus its 10 newest terminal ones. Runs of unregistered repositories never appear.
   - Controls act on the run's own repository. **Open project** opens another project's run in its own project.
   - The toolbar run indicator (counts over every project; a click opens Runs filtered) and the sidebar `‼N` count all projects.
   - Toasts name the project.
   - Notify on escalation is one switch for the whole viewer.
3. **L155 Dispatch:** Start run is disabled with "Open a project to dispatch" when no project is open.
4. **L235 helpers paragraph:** add `runs/runs-snapshot-all.py`. Describe the am calls as built: `am runs --repo-dir R` per registered project, `am status`, `am watch --all-projects --follow`, `am logs`.
5. **L259 Install:** keep the `as_of_seq` requirement. Each root's `am runs` / `am status` is still checked for it, and its absence is `SchemaMismatch` in that project's entry. Change "the list snapshot fails" to say that project's group shows the error. Re-check this wording against RunStore's `projectErrors` text before writing.
6. L33 (Ctrl+6) and L193 (breadcrumb) need no change unless they mention a project requirement.

## Error paths the docs must not misstate

| case | what the docs say |
|---|---|
| one registered root fails (missing dir, timeout, refusal) | its group header shows the error, it keeps its previous runs, and other projects are unaffected |
| `am` missing | every entry is `AmMissing`, so the screen shows the single missing state and all roots are disarmed |
| no project registered | nothing is launched and the list is empty |
| a project leaves the registry | its runs, error and arming go, with no alert; the filter falls back to All projects |
| two registrations of one repo | each run is listed once, under the first |
| a snapshot is running when a nudge or tick arrives | the request waits as the single pending one and is never stacked or killed |

## Out of scope

- Any code, test or comment change.
- The run events timeline (S5).
- Milestone titles for other projects' runs (S6 Limits L102-104).
- Rewriting S6 or any earlier spec or plan.
- Sibling cards 4.1 to 4.5 (already done). Their docs gaps are fixed here only as prose.

## Tests

No test reads `docs/architecture.md` or `README.md` prose. `tests/architecture/test_layers.py` and `test_icon_glyphs.py` read only `ui/`, `core/` and `vendor/` sources. A committed test pinning prose would be new scope and brittle, so none is added. TDD has no failing test for prose. The plan uses these checks instead:

| check | tier | why |
|---|---|---|
| `bash tests/run.sh` green | full suite (regression) | proves no source file changed behaviour and the architecture tests still pass |
| `git diff --name-only main...HEAD -- . ':!docs/superpowers'` lists only `README.md` and `docs/architecture.md` for this card's commits | manual verification step | proves the change is docs only |
| `grep -n -e readRunners -e appliedSeq -e "one run read" -e "the setting is the project's" -e "lists the open project's" -e "never controlled" docs/architecture.md README.md` finds nothing that describes the store | manual verification step | proves the stale claims are gone |
| `grep -n "runs-snapshot-all.py\|projectFilter\|armedRoots\|get-global-settings\|displayOrder\|Open a project to dispatch" docs/architecture.md` matches each term | manual verification step | proves the required facts are present |
| each new sentence is traced to a source line (F1 to F10) | review | "state only what the code does" |

## Review focus (for the planner)

1. Stale S6 wording that creeps back in: "one call", "no per-project errors", "per-run read". The fan-out is real.
2. Claiming run reads, `asOfSeq` or `appliedSeq` coverage in the store. There is none.
3. Saying the filter persists or resets on a project switch. It survives the switch and resets on panel close.
4. Saying notify is per project anywhere in either file.
5. Losing true existing prose (dispatch, logs, card marks, archive text) while rewriting the long RunStore bullet.
