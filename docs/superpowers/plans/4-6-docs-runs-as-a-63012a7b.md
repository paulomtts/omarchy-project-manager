# 4.6 Docs: Runs as a global destination: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `docs/architecture.md` and `README.md` describe Runs as a global destination exactly as built in 4.1 to 4.5: a per-project fan-out snapshot, per-project errors and arming, a project filter, controls on the run's own repo, a viewer-wide notify switch, and Runs reachable with no project open.

**Architecture:** Docs only. Each task rewrites named passages of one file with replacement text given verbatim in this plan; every sentence was traced to a source line at HEAD 0a3b562. No QML, JS, Python, test or comment changes. There is no failing unit test for prose, so each task's RED step is a `grep` that still finds the stale claim (or misses the new fact), and its GREEN step is the same `grep` after the edit; the full suite runs at the end of every task to prove nothing else moved.

**Tech Stack:** Markdown; `grep`; `python3` for one guarded line-range replacement; `bash tests/run.sh` (pytest plus the QML tests) as the regression gate.

**Spec:** `docs/superpowers/specs/4-6-docs-runs-as-a-63012a7b.md`. The full text is copied below.

## Spec (verbatim)

> # 4.6 Docs: Runs as a global destination (card 63012a7b)
>
> Parent story: 63a11d2f. Milestone spec: `docs/superpowers/specs/2026-10-05-runs-all-projects-design.md` (cited below as **S6**). Blocked by 86d8790e (4.5, done: commits b0a666a..0a3b562).
>
> ## Scope
>
> Docs only. Edit `docs/architecture.md` and `README.md` so they describe Runs as a global destination **as built** in 4.1 to 4.5. Change no QML, JS, Python, test or other file. Do not edit any file under `docs/superpowers/specs/` or `docs/superpowers/plans/`: those are history.
>
> **The code wins over S6.** The card says "State only what the code does". S6 promised a single `am runs --all-projects` call, no `runs-snapshot-all.py`, no `am_runs.py`, no per-project errors, per-run reads on a nudge and `as_of_seq` coverage (S6 L3-4, L88-90, L95-96, L113-121, L135-139, L146-153). The code does a **per-project fan-out** instead. Where S6 and the code disagree, write what the code does. Do not write the S6 version and do not mention the disagreement in the docs.
>
> Before writing a sentence about a file, read that file. The facts below were gathered at HEAD 0a3b562. The executor must re-check each one against the named source and not copy it blindly.
>
> ## Inherited constraints
>
> - Layering and section order of `docs/architecture.md` stay as they are (S6 L111 "Same layering as S1/S2 (`docs/architecture.md`)"). Extend or rewrite the existing entries. Never write a second copy of an entry.
> - Runs of unregistered repositories stay invisible (S6 L97). `brd projects` stays the registry (S6 L94).
> - Dispatch stays project-bound. **Start run** is disabled with the tooltip "Open a project to dispatch" when no project is open (S6 L83-85).
> - Card marks on Board and Graph are unchanged (S6 L86-87). Do not reword their docs.
> - Notify on escalation is one viewer-wide switch (S6 L73-78). The code agrees.
> - Alerts arm on the first good snapshot (S6 L79-82). The code does this **per project root**.
> - Each project lists its non-terminal runs plus its 10 newest terminal ones (S6 L105-107; `core/backend/common/am_runs.py` `TERMINAL_LIMIT = 10`, `LIST_LIMIT = 200`).
> - House style: `docs/architecture.md` uses one long bullet or paragraph line per entry, names properties and functions in backticks, and writes ` -- ` for a dash. `README.md` writes ` - `. Add no emoji. Use no glyph outside the ones the docs already use (⟳ ⏸ ‼ ✖ ⊘ ✔ ›).
> - Docstrings and comments are not touched. No source file changes.
>
> ## Facts the docs must state (from the code)
>
> Each fact names its source. The plan's tasks place them into the passages listed in the next section.
>
> **F1. Fan-out.** `RunStore` (`core/stores/RunStore.qml` header L6-37, `usableRoots`, `mergedRuns`) makes one list snapshot by running `core/backend/runs/runs-snapshot-all.py` with every usable root of `projectRoots`, in registry order. A usable root is a non-empty string that does not start with `-`; roots are deduplicated. `App.qml` (~L109) sets `projectRoots` from `app.projects.projects` as `[{root, name}]`; the store never reaches into another store. The helper runs `am runs --repo-dir <root> --limit 200` for each root, then `am status <id>` (never with `--repo-dir`) for every non-terminal run and the first 10 terminal ones. It runs up to 4 roots at once, gives each am call 60 s, and reports a failure in that root's entry only. The failure types are `RootMissing`, `AmMissing`, `AmTimeout`, `AmBadOutput`, `SchemaMismatch`, `HelperError`, or am's own error envelope (see the helper's docstring).
>
> **F2. State.** `runsByProject` is `{root: runs[]}`: each root's runs, normalized and tagged with their project (`Runs.withProject`). `projectErrors` is `{root: sentence}` for each root whose latest entry failed. A failed root keeps its previous runs. `runs` is every root merged in registry order. A run id is listed once, under the first root that lists it. `amStatus` is `missing` when every entry is `AmMissing`, and `error` when no entry matched. Only runs of registered roots appear, because unregistered repositories are never asked. With no usable root, `refresh()` launches nothing and empties `runs`, `runsByProject` and `projectErrors`. There are **no run reads**: `asOfSeq` is always 0 and `appliedSeq` is `{runId: 0}` for every listed run (RunStore L85-89, L1007-1019), so a snapshot only names which ids the store knows; it is not coverage. Do not describe it as run-read coverage, and do not say it is empty. Check this in RunStore before writing, and delete every doc sentence about `readRunners`, `runs-snapshot.py --run` used by the store, `appliedSeq`/`asOfSeq` coverage, or StoreBusy/UnknownRun handling in the store.
>
> **F3. Partial refresh and cost rules.** These are in RunStore `requestSnapshot`, `snapshotEnded`, `triggerNudges`, `refreshLive` and `registryChanged`.
> - `requestSnapshot(roots | "all")` allows one snapshot in flight plus **one** pending request, and a request never kills the snapshot in flight. When the pending requests merge, `"all"` wins; otherwise their roots are unioned. The pending request launches against the registry as it is when the running snapshot ends.
> - On a watch nudge (250 ms debounce), the store emits `runsNudged(ids)`, then snapshots only the roots whose `runsByProject` lists those ids. If some id is listed by no root, it snapshots every root.
> - The liveness tick (`livenessTimer`, 10 s, armed while a run is running) snapshots only the roots that hold a running run.
> - A registry change drops the runs, errors and arming of roots that left, re-merges the list without raising an alert, then snapshots every root.
> - When the panel opens (`startLive`), the store refreshes every root, reads the global settings and starts the stale clock. The `stale` flag means no good reply for 30 s while the panel is open.
> - When the panel closes (`stopLive`), `projectFilter` returns to `""`, the pending request is dropped, the watch and timers stop, and `armedRoots` and toasts are cleared. `runs` is kept.
>
> **F4. Watch.** `runs-watch.py` is started with every usable root that begins with `/` (`watchableRoots`) plus every known run id (`knownRunIds`). It is restarted after a good snapshot when the watchable roots changed. It follows `am watch --all-projects --follow` and nudges only the argv run ids and the runs whose `run_upsert` `repo_dir` has the same realpath as a root. A `cursorReset` hello or a new `storeId` starts over with a full snapshot. A `SchemaMismatch` or a `CorruptJournal` switches to the 5 s poll. Keep the existing helper prose at architecture L196 where it is still true.
>
> **F5. Per-project arming.** These are in RunStore `armedRoots`, `alertsOf` and `alertsArmed`.
> - `armedRoots` is `{root: true}`. A root is armed by its first ok entry, and that entry only arms: it never alerts the history it lists.
> - Alerts (`Runs.newAlerts`) are raised only for roots that are armed and answered ok in this reply. Each run id is alerted once, and each alert carries the `project` name.
> - A project registered later is armed by the first snapshot that lists it.
> - A failed entry, a root with no entry, or a closed panel never changes `armedRoots`.
> - `AmMissing` disarms every root. A root that leaves the registry loses its arming.
> - `alertsArmed` is true when any root is armed.
> - A toast is `{key, id, title, state, reason, project, expiresMs}`, with at most 3 shown. `RunToast` shows the project under the heading.
>
> **F6. Project filter.** These are in RunStore `projectFilter`, `toggleProjectFilter`, `keepProjectFilter`, `groups` and `filteredRuns`.
> - `projectFilter` is `""` for All projects, otherwise a root that is registered, usable and has at least one run.
> - `toggleProjectFilter(root)` selects that root. Toggling the active root, a non-filterable root or `""` selects All projects. It emits `projectFilterToggled` once per call.
> - The filter falls back to `""` when its project leaves the registry or has no runs any more.
> - **Lifetime:** the filter survives a section switch and a project switch, resets to All projects when the panel closes, and is never persisted.
> - `filteredRuns` is `Runs.displayOrder(Runs.groupByProject(Runs.filterByProject(Runs.searchRuns(Runs.filterRuns(runs, runFilter), searchQuery), projectFilter)))`. Display order puts groups with a run that needs attention first, then groups with a live run, then the rest by name. Each group keeps am's order. The screen, the navigator cursor and `handleRunKey` index this one list.
>
> **F7. Controls act on the run's own repo.** These are in RunStore `control()` and `projectSwitched`.
> - `control()` refuses a run with no `repo_dir`, a non-task resume of a run with no `project.root`, a disabled action, and a run that already has a request pending. Having no project open is not a refusal.
> - A resume reads `get-run-settings` of `run.project.root`.
> - A project switch keeps pending requests, the control error, the cancel dialog and the flash. It resets only `runSettings` and the dispatch.
> - Logs use the selected run's project root (`runs-logs.py`). Without that root, nothing launches.
>
> **F8. Viewer-wide notify.** These are in RunStore ~L158-160 and ~L1395-1430, and `core/backend/projects/viewer-state.py`.
> - The switch is read with `viewer-state.py get-global-settings`. On the first read with nothing stored, it is true when any project's stored value is true.
> - It is saved with `set-global-settings`. `notifyTouched` stops a late load from overwriting a change. When a save fails, the switch goes back to `notifySaved` and the flash reads "Notify on escalation could not be saved".
> - The per-project value is no longer read or written. `runSettings` (`get-run-settings` of the open project) only feeds dispatch.
>
> **F9. UI.**
> - `ui/Panel.qml` mounts `RunIndicator` in the toolbar with `runCounts = Runs.runFilterCounts(runs)` over every registered project. A segment click (`showRunsFiltered(filter)`) opens Runs on All projects with that status chip.
> - Panel feeds the Sidebar `runsAttention: Runs.attention(runs).length`.
> - Runs and Run detail are visible with no project open. A toast's Open works with no project open too.
> - `ui/screens/RunsScreen.qml` has:
>   - a project chip row: All projects, This project when a project is open, and one chip per project with runs, with its count;
>   - status chip counts taken within the project filter;
>   - group headers that show the `projectErrors` sentence;
>   - a flat list under a project filter;
>   - an **Open project** action on the cursor row of another registered project's run;
>   - the Notify on escalation switch, also shown with no project open.
> - `ui/Navigator.qml` opens Runs and Run detail with no project open.
> - `ui/Shortcuts.qml`: p / r / c work without a project, and `d` stays project-bound.
> - `ui/components/Sidebar.qml`: the Runs row is never disabled.
> - Executor: confirm each item, with its line, before writing it.
>
> **F10. Domain.** `core/domain/runs.js` exports `withProject(run, root, name)`, `filterByProject(runs, root)`, `groupByProject(runs)` and `displayOrder(groups)` (verified: L363, L378, L419, L453).
>
> ## Passages to change
>
> ### docs/architecture.md
>
> 1. **RunStore bullet (L83-92).**
>    - Rewrite L83-88 to F1, F2, F3, F4 and F5, and F6 where it touches the store.
>    - Remove "kept to the rows whose project is the selected one", "App hands it project" as the run guard, everything about run reads, `appliedSeq`/`asOfSeq` semantics, and "A project switch clears nudges ...".
>    - Keep L89-90 (chips, logs) where they are still true, and make the logs sentence match F7.
>    - Keep L91 (controls) and make it match F7.
>    - Keep L92 (dispatch) as it is.
>    - Add the global notify switch (F8).
> 2. **Navigator and Shortcuts paragraphs (~L94-108).** Runs and Run detail open with no project. p / r / c work without a project, and `d` stays project-bound (F9).
> 3. **RunIndicator (~L149) and Sidebar (~L160).** Add that Panel mounts `RunIndicator`, with counts over every registered project and a segment click that opens Runs filtered (F9). The phrase "not yet mounted" is not in the file at HEAD (grep confirms), so there is no sentence to delete. If an equivalent phrase is found, rewrite it.
> 4. **Run screens paragraph (~L165).** Add F9's RunsScreen items and no-project reachability. Replace the per-project notify wording ("the setting is the project's") with F8. Add the disabled Start run tooltip.
> 5. **Refresh model paragraph (~L171).** Replace "one run read ... `runs-snapshot.py --run`" with the F3 partial-refresh rules. Keep "no timers while idle".
> 6. **Domain helpers, `runs.js` (~L180).** Add `withProject`, `filterByProject`, `groupByProject` and `displayOrder`, with the ordering rule in F6.
> 7. **`core/backend/runs/` paragraph (L196).** State that `RunStore` uses `runs-snapshot-all.py`, not `runs-snapshot.py`. The no-argument and `--run` modes of `runs-snapshot.py` still exist and are not used by the store (confirm with grep of `RunStore.qml`). Make the `runs-snapshot-all.py` failure list match the helper's docstring (add `AmBadOutput` and `SchemaMismatch`). Keep the `am_runs` mention at L182-183.
> 8. Test-section references (~L226-262) stay as they are unless they claim the store makes run reads.
>
> ### README.md
>
> 1. **L8:** Runs are of every registered project, watched and also controlled. Do not keep "never controlled" if the code controls runs; it does (pause/resume/cancel).
> 2. **L154 Runs bullet:**
>    - Runs is global and reachable with no project open.
>    - By default it lists every registered project's runs in groups. A project filter (All projects / This project / one chip per project) survives a section or project switch and resets when the panel closes.
>    - Each project lists its non-terminal runs plus its 10 newest terminal ones. Runs of unregistered repositories never appear.
>    - Controls act on the run's own repository. **Open project** opens another project's run in its own project.
>    - The toolbar run indicator (counts over every project; a click opens Runs filtered) and the sidebar `‼N` count all projects.
>    - Toasts name the project.
>    - Notify on escalation is one switch for the whole viewer.
> 3. **L155 Dispatch:** Start run is disabled with "Open a project to dispatch" when no project is open.
> 4. **L235 helpers paragraph:** add `runs/runs-snapshot-all.py`. Describe the am calls as built: `am runs --repo-dir R` per registered project, `am status`, `am watch --all-projects --follow`, `am logs`.
> 5. **L259 Install:** keep the `as_of_seq` requirement. Each root's `am runs` / `am status` is still checked for it, and its absence is `SchemaMismatch` in that project's entry. Change "the list snapshot fails" to say that project's group shows the error. Re-check this wording against RunStore's `projectErrors` text before writing.
> 6. L33 (Ctrl+6) and L193 (breadcrumb) need no change unless they mention a project requirement.
>
> ## Error paths the docs must not misstate
>
> | case | what the docs say |
> |---|---|
> | one registered root fails (missing dir, timeout, refusal) | its group header shows the error, it keeps its previous runs, and other projects are unaffected |
> | `am` missing | every entry is `AmMissing`, so the screen shows the single missing state and all roots are disarmed |
> | no project registered | nothing is launched and the list is empty |
> | a project leaves the registry | its runs, error and arming go, with no alert; the filter falls back to All projects |
> | two registrations of one repo | each run is listed once, under the first |
> | a snapshot is running when a nudge or tick arrives | the request waits as the single pending one and is never stacked or killed |
>
> ## Out of scope
>
> - Any code, test or comment change.
> - The run events timeline (S5).
> - Milestone titles for other projects' runs (S6 Limits L102-104).
> - Rewriting S6 or any earlier spec or plan.
> - Sibling cards 4.1 to 4.5 (already done). Their docs gaps are fixed here only as prose.
>
> ## Tests
>
> No test reads `docs/architecture.md` or `README.md` prose. `tests/architecture/test_layers.py` and `test_icon_glyphs.py` read only `ui/`, `core/` and `vendor/` sources. A committed test pinning prose would be new scope and brittle, so none is added. TDD has no failing test for prose. The plan uses these checks instead:
>
> | check | tier | why |
> |---|---|---|
> | `bash tests/run.sh` green | full suite (regression) | proves no source file changed behaviour and the architecture tests still pass |
> | `git diff --name-only main...HEAD -- . ':!docs/superpowers'` lists only `README.md` and `docs/architecture.md` for this card's commits | manual verification step | proves the change is docs only |
> | `grep -n -e readRunners -e appliedSeq -e "one run read" -e "the setting is the project's" -e "lists the open project's" -e "never controlled" docs/architecture.md README.md` finds nothing that describes the store | manual verification step | proves the stale claims are gone |
> | `grep -n "runs-snapshot-all.py\|projectFilter\|armedRoots\|get-global-settings\|displayOrder\|Open a project to dispatch" docs/architecture.md` matches each term | manual verification step | proves the required facts are present |
> | each new sentence is traced to a source line (F1 to F10) | review | "state only what the code does" |
>
> ## Review focus (for the planner)
>
> 1. Stale S6 wording that creeps back in: "one call", "no per-project errors", "per-run read". The fan-out is real.
> 2. Claiming run reads, `asOfSeq` or `appliedSeq` coverage in the store. There is none.
> 3. Saying the filter persists or resets on a project switch. It survives the switch and resets on panel close.
> 4. Saying notify is per project anywhere in either file.
> 5. Losing true existing prose (dispatch, logs, card marks, archive text) while rewriting the long RunStore bullet.

## Global Constraints

- Docs only: change `docs/architecture.md` and `README.md` and nothing else. No QML, JS, Python, test, comment or docstring change.
- Never edit a file under `docs/superpowers/specs/` or `docs/superpowers/plans/`: those are history.
- The code wins over S6. Write what the code does (a per-project fan-out, per-project errors, no run reads); never write the S6 version ("one call", `am runs --all-projects` for the list, "no per-project errors", "per-run read"), and never mention the disagreement.
- Layering and section order of `docs/architecture.md` stay as they are. Extend or rewrite the existing entries; never write a second copy of an entry.
- Runs of unregistered repositories stay invisible; `brd projects` stays the registry.
- Dispatch stays project-bound: **Start run** is disabled with the tooltip "Open a project to dispatch" when no project is open.
- Card marks on Board and Graph are unchanged; do not reword their docs.
- Notify on escalation is one viewer-wide switch. Never call it per project.
- Alerts arm on the first good snapshot, per project root.
- Each project lists its non-terminal runs plus its 10 newest terminal ones (`TERMINAL_LIMIT = 10`, `LIST_LIMIT = 200`).
- House style: `docs/architecture.md` uses one long bullet or paragraph line per entry, names properties and functions in backticks, and writes ` -- ` for a dash. `README.md` writes ` - `. No emoji. No glyph outside ⟳ ⏸ ‼ ✖ ⊘ ✔ › (plus the ▶ and · the docs already use).
- Never run a process-killing command by pattern (`pkill -f`, `killall`); stop a stuck suite with `timeout`.

## Review Focus

1. Stale S6 wording creeping back ("one call", "no per-project errors", "per-run read", `am runs --all-projects` as the store's list call): a reader would expect the docs to describe the fan-out the code runs. Pinned by the RED/GREEN greps of Task 1 Step 2/5 and Task 2 Step 2/5 and the final grep in Task 3 Step 7.
2. A claim that the store makes run reads or keeps `asOfSeq`/`appliedSeq` coverage: the only `appliedSeq` sentence left must say `{runId: 0}`. Pinned by Task 1 Step 6.
3. The project filter's lifetime misstated (persisted, or reset on a project switch): it survives a section and project switch and resets when the panel closes. Pinned by Task 3 Step 6 (README) and Task 1 Step 6 (the existing architecture L89 sentence is kept).
4. Notify called per project anywhere: pinned by Task 2 Step 5 and Task 3 Step 6 (`the setting is the project's` gone, `get-global-settings` present).
5. True prose lost while rewriting the long RunStore bullet (dispatch, logs, controls, alerts, card marks, archive text): Task 1 replaces only lines 83-88 behind guarded prefixes and Task 1 Step 6 checks the kept lines are still there.

---

## File Structure

- Modify: `docs/architecture.md` -- the `RunStore.qml` bullet (lines 83-88 replaced, line 91 one clause), the `Navigator.qml` / `Shortcuts.qml` paragraph (lines 94-97), the run screens paragraph (line 165), the dispatch paragraph (line 167), the refresh model (line 171), the `runs.js` helpers (line 180), the `core/backend/runs/` paragraph (line 196) and one test-section clause (line 261).
- Modify: `README.md` -- the intro (line 8), the **Runs** bullet (line 154), the **Dispatch** bullet (line 155), the helpers paragraph (line 235) and the Install requirements (line 259).

Line numbers are at HEAD 0a3b562; every edit below finds its text by content, not by number.

---

### Task 1: `docs/architecture.md` -- the `RunStore.qml` bullet

**Files:**
- Modify: `docs/architecture.md:83-88` (replaced), `docs/architecture.md:91` (one clause)

**Interfaces:**
- Consumes: nothing.
- Produces: the RunStore bullet names `runs-snapshot-all.py`, `projectRoots`, `usableRoots()`, `runsByProject`, `projectErrors`, `requestSnapshot`, `pendingSnapshot`, `triggerNudges`, `refreshLive`, `registryChanged`, `startLive`, `stopLive`, `resetCursor`, `armedRoots`. Task 2's refresh-model paragraph refers to the same names.

Sources to re-read before writing (the executor confirms each sentence): `core/stores/RunStore.qml` header (L6-37), properties (L40-200), `refresh` (L234), `requestSnapshot` (L249), `launchSnapshot` (L268), `snapshotEnded` (L289), `startLive` (L360), `stopLive` (L375), `startWatch` / `watchableRoots` / `knownRunIds` (L412-450), `triggerNudges` (L523), `refreshLive` (L556), `resetCursor` / `forgetLive` (L575-595), `projectSwitched` (L655), `usableRoots` (L670), `mergedRuns` (L708), `registryChanged` (L731), `applySnapshot` / `applyProjects` (L909-1050), `alertsOf` (L1056), the timers (L1837-1875); `core/stores/App.qml:109`.

- [ ] **Step 1: Read the current bullet**

Run: `sed -n 83,92p docs/architecture.md`
Expected: line 83 starts `- \`RunStore.qml\` the am run monitor's data: a list snapshot of every project's am runs (\`runs-snapshot.py\` with no argument)`, line 88 starts `  \`amStatus\` is \`ok\`, \`missing\` (an \`AmMissing\` list snapshot`, line 89 starts `  The Runs list is \`filteredRuns\``.

- [ ] **Step 2: RED -- the stale claims are there and the fan-out is not**

Run:
```bash
grep -n -o -e readRunners -e "kept to the rows whose project is the selected one" -e "UnknownRunError\` launches" -e "applied run read" -e "A project switch clears \`nudges\`" docs/architecture.md
grep -c 'runs-snapshot-all.py` on `snapshotRunner`' docs/architecture.md
```
Expected: the first command prints at least five hits, all on lines 83-87; the second prints `0`.

- [ ] **Step 3: Write the replacement lines to a scratch file**

```bash
cat > /tmp/runstore-bullet.md <<'EOF'
- `RunStore.qml` the am run monitor's data: one list snapshot covers every registered project. It never reaches for another store: `App` hands it `projectRoots` (`[{root, name}]` from `app.projects.projects`, in registry order), `project` (the open project's root path, `""` when none), `backendDir` and `active` (App's `panelOpen`, which the panel binds to its `opened`). `usableRoots()` keeps each registry entry whose root is a non-empty string not starting with `-`, each root once, at its first position. A snapshot runs `runs-snapshot-all.py` on `snapshotRunner` with the usable roots it is for, in registry order; the helper asks am about each root on its own and reports a root's failure in that root's entry only. `runsByProject` (`{root: runs[]}`) holds each root's runs in am's order, each `Runs.withProject(Runs.normalizeRun(..), root, name)`; `projectErrors` (`{root: sentence}`, the `Runs.errorText` of the entry's error) holds each root whose latest entry failed, and a failed root keeps its previous runs; `runs` is every root's list merged in registry order (`mergedRuns`), a run id listed once, under the first root that lists it, so a repository registered twice lists each run once. Only registered roots are asked, so the runs of a repository `brd` has not registered never appear. With no usable root, `refresh()` launches nothing, stops a snapshot in flight, drops the pending request and empties `runs`, `runsByProject` and `projectErrors`. A project switch leaves the run list alone: `project` decides only `runSettings` and the dispatch. The store never fetches a single run: `asOfSeq` is always `0` and `appliedSeq` is `{runId: 0}` for every run in `runs`, so a snapshot only names the run ids the store knows.
  Snapshots: one runs at a time, plus at most one pending request (`requestSnapshot(roots)`, `roots` a list of roots or `"all"`; `snapshotRoots`, `pendingSnapshot`). A request never stops the snapshot in flight and is never stacked: requests that wait merge into the pending one, `"all"` winning, else the union of their roots, and when the running snapshot ends its reply is applied and the pending request launches against the registry as it is then. `refresh()` asks for `"all"`. Opening the panel (`startLive`) clears `armedRoots`, reads the notify switch, starts the stale clock and refreshes every root. Closing it (`stopLive`) puts `projectFilter` back to `""`, drops the pending request (a snapshot in flight runs to its end and is applied), stops the watch, the debounce and the poll, clears `stale`, `watchWarning`, `armedRoots` and `toasts`, and closes the dispatch unless a start is in flight; `runs`, the selection, the chip and `amStatus` stay for the next opening. A registry change (`registryChanged`) drops the runs, errors and arming of every root that left, merges `runs` again in the new order with the new names, raises no alert, then refreshes every root.
  Nudges, never folded into state: while `active`, the first good snapshot starts `runs-watch.py` (a plain `Process`, not a `HelperRunner`) with every usable root that begins with `/` (`watchableRoots`) and every run id the store lists (`knownRunIds`); a later good snapshot restarts a running watch only when those roots changed, and a watch that ended is not restarted until the next opening. Its `changed` lines say "run X changed at seq N"; the store keeps the highest `seq` per run in `nudges` and takes them once per 250 ms debounce window (`debounceTimer`, `triggerNudges`): it emits `runsNudged(ids)`, then requests a snapshot of the roots whose `runsByProject` list holds one of the ids, or of every root when some id is listed by none. The seqs gate nothing. `watchCursor` is the watch's last `{"cursor": C}`, held in memory only and never passed back to the helper; `storeId` is the last non-empty `storeId` a hello named (a list snapshot never reads one).
  Starting over (`resetCursor`): a hello with `cursorReset` true, or one naming a `storeId` other than the last one seen, stops the snapshot in flight, drops the pending request, forgets `watchCursor`, `nudges`, `runs`, `runsByProject` and `armedRoots`, and refreshes every root. The first `storeId` seen resets nothing, and `storeId` survives a project switch, a watch end and `AmMissing`.
  `amSchema` (the schema from the current watch's hello; `0` = unknown) and `amVersion` (am's version from it; `""` = unknown) are set from the watch's `{"hello": {"schema", "am", "head", "cursorReset", "storeId"}}` line -- `schema` when it is an integer of 1 or more, else `0`; `am` when it is a string, else `""`; `head` is not read -- and go back to unknown when a watch starts, stops or exits. Timers: the 250 ms debounce; a 10 s liveness tick (`livenessTimer`, only while the panel is open and a run is running) that snapshots only the roots whose list holds a running run (`refreshLive`); a `stale` flag 30 s after the last good snapshot (or the opening) while the panel is open; and a 5 s fallback poll (`pollTimer`, `refresh()`) after a watch ended with `SchemaMismatch` or `CorruptJournal`.
  A reply's entries are matched to the usable roots by exact `root`, the first entry of a root counting. `amStatus` is `ok` (some matched entry is ok), `missing` (every matched entry is `AmMissing`: `runs`, `runsByProject`, `projectErrors` and `appliedSeq` are emptied and every root is disarmed, so no run marks show), `schema` (the watch ended with `SchemaMismatch`: `watchSchemaError` holds the banner text, which stays up through the polling snapshots) or `error` (every matched entry failed, no entry matched, or the reply was an `ok: false` envelope or unreadable: the runs stay), with `lastError` saying why -- for failed entries the first one's sentence. A reply for roots none of which is registered any more changes nothing. A root whose `am runs` carries no `as_of_seq` gets a `SchemaMismatch` entry ("the plugin needs the newer am") like any other failed root. Only a reply with an ok entry settles controls and refreshes logs and, while `active`, starts a watch, restarts the stale clock and arms roots. A watch that ends with `CorruptJournal` sets `watchWarning` (the Runs screen's warning line) and starts the same 5 s poll.
EOF
```

- [ ] **Step 4: Splice it over lines 83-88, guarded by their prefixes**

```bash
python3 - <<'PY'
from pathlib import Path
p = Path("docs/architecture.md")
lines = p.read_text().split("\n")
start = next(i for i, l in enumerate(lines) if l.startswith("- `RunStore.qml` the am run monitor's data:"))
end = next(i for i, l in enumerate(lines) if l.startswith("  `amStatus` is `ok`, `missing` (an `AmMissing` list snapshot"))
assert end - start == 5, (start, end)
assert lines[start + 1].startswith("  Nudges, never folded into state:")
assert lines[end + 1].startswith("  The Runs list is `filteredRuns`")
new = Path("/tmp/runstore-bullet.md").read_text().rstrip("\n").split("\n")
assert len(new) == 6
lines[start:end + 1] = new
p.write_text("\n".join(lines))
PY
```
Expected: no output (every `assert` holds).

Then edit line 91's arming clause (Edit tool, exact strings):

old:
```
a root's first ok entry after an opening, a start-over, an `AmMissing` spell (every matched entry `AmMissing`, which disarms every root) or its return to the registry only arms it, so reopening the panel never replays history;
```
new:
```
a root's first ok entry after an opening, a start-over, an `AmMissing` spell (every matched entry `AmMissing`, which disarms every root), the project's first registration or its return to the registry only arms it, so reopening the panel never replays history and a project registered later is armed by the first snapshot that lists it;
```

- [ ] **Step 5: GREEN -- the stale claims are gone and the fan-out is there**

Run:
```bash
grep -n -o -e readRunners -e "kept to the rows whose project is the selected one" -e "UnknownRunError\` launches" -e "applied run read" -e "A project switch clears \`nudges\`" docs/architecture.md
grep -c 'runs-snapshot-all.py` on `snapshotRunner`' docs/architecture.md
grep -n -o -e "project's first registration" docs/architecture.md
```
Expected: the first command prints nothing; the second prints `1`; the third prints one hit on line 91.

- [ ] **Step 6: Check the kept lines and the one `appliedSeq` sentence**

Run:
```bash
grep -n -o 'appliedSeq` is `{runId: 0}`' docs/architecture.md
grep -c 'appliedSeq' docs/architecture.md
sed -n 89,92p docs/architecture.md | cut -c1-60
grep -n -o -e "The chip and the project filter survive a section and a project switch; the project filter resets to All when the panel closes and is never persisted" docs/architecture.md
```
Expected: the first prints one hit on line 83; the second prints `2` (line 83's `{runId: 0}` sentence and line 88's `missing` case, where `appliedSeq` is emptied); lines 89-92 still start `  The Runs list is`, `  Run detail's output pane`, `  Run controls (S2 4.1)`, `  Dispatch (S3 3.1)`; the last grep prints one hit on line 89. If the `appliedSeq` count differs, read every hit and make sure none describes run-read coverage.

- [ ] **Step 7: Run the full suite**

Run: `timeout 900 bash tests/run.sh`
Expected: PASS (exit 0). Docs are not read by any test; this proves no source file moved.

- [ ] **Step 8: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): RunStore snapshots every registered project per root, with per-project errors and arming"
```

---

### Task 2: `docs/architecture.md` -- navigator, shortcuts, screens, refresh model, `runs.js`, backend and tests

**Files:**
- Modify: `docs/architecture.md:94-97` (Navigator / Shortcuts), `:165` (run screens), `:167` (dispatch), `:171` (refresh model), `:180` (`runs.js`), `:196` (`core/backend/runs/`), `:261` (tests)

**Interfaces:**
- Consumes: the RunStore names Task 1 wrote (`requestSnapshot`, `refreshLive`, `projectErrors`, `projectFilter`, `toggleProjectFilter`, `notifyOnEscalation`).
- Produces: nothing later tasks use.

Sources to re-read before writing: `ui/Navigator.qml:40-50` (crumbs with no project) and `:170-180` (`showSection`, Runs the one section with no project); `ui/Shortcuts.qml:55-90` (`handleRunKey` with or without a project, `handleDispatchKey` needs one); `ui/screens/RunsScreen.qml:10-25` (header comment), `:44-60`, `:120-200` (`projectChipsOf`, `chooseProject`, `openProjectTargetOf`, `entriesOf`), `:280` (chip row `visible`), `:307` (`No projects registered.`), `:313-332` (notify switch), `:575-583` (Open project); `ui/Panel.qml:548-561` (`startRunButton`); `core/domain/runs.js:355-470` (`withProject`, `filterByProject`, `_compareGroups`, `groupByProject`, `displayOrder`); `core/backend/runs/runs-snapshot-all.py:1-30` (docstring); `grep -n "runs-snapshot" core/stores/RunStore.qml` (only `runs-snapshot-all.py`).

- [ ] **Step 1: Confirm the store never runs `runs-snapshot.py`**

Run: `grep -n "runs-snapshot" core/stores/RunStore.qml`
Expected: only lines naming `runs-snapshot-all.py` (L7, L667, L1775); none naming `runs-snapshot.py`.

- [ ] **Step 2: RED -- stale claims present, new facts missing**

Run:
```bash
grep -n -o -e "the setting is the project's" -e "one run read of that run" -e "run read, logs and" -e "the mode \`RunStore\` uses" -e "\`AmTimeout\`, \`HelperError\`, or am's or" docs/architecture.md
grep -c -e "displayOrder(groups)\` (" -e "Open a project to dispatch" -e "with or without a project open, pause" -e "the one section \`showSection\` opens with no project" docs/architecture.md
```
Expected: the first prints five hits (lines 165, 171, 261, 196, 196); the second prints `0`.

- [ ] **Step 3: Navigator and Shortcuts (lines 94-97), Edit tool**

Edit 1 -- old:
```
`Navigator.qml` (screen switching; `openRun(id, from)`
```
new:
```
`Navigator.qml` (screen switching; Runs is the one section `showSection` opens with no project, and Run detail opens with none too, both keeping their `Runs` / `Runs › <run>` crumbs; `openRun(id, from)`
```

Edit 2 -- old:
```
`handleRunKey` makes a bare `p` / `r` / `c`
```
new:
```
`handleRunKey` makes a bare `p` / `r` / `c`, with or without a project open,
```
(The `d` sentence already says it "leaves the letter alone without a project"; leave it.)

- [ ] **Step 4: Run screens (165), dispatch (167), refresh model (171), `runs.js` (180), backend (196), tests (261), Edit tool**

Edit 3 (line 165) -- old:
```
`ui/screens/RunsScreen.qml` (Ctrl+6) lists `filteredRuns`, one row each (state glyph, short id, title, done/total, current phase, age; a dead run's age is since its last heartbeat, and an escalated run adds `escalationReason`), under the Needs attention / Live / Parked / All chips with their `runFilterCounts`.
```
new:
```
`ui/screens/RunsScreen.qml` (Ctrl+6) and `ui/screens/RunDetailScreen.qml` show with or without an open project. `RunsScreen` lists `filteredRuns` -- every registered project's runs -- grouped by project, each group under a header that is not a cursor target (the project's name, else its root; its live, parked and needs-attention counts; and its `projectErrors` sentence, a failed root with no runs getting a header of its own), and flat, with no headers, under a project filter (the filtered project's error first when it has one); with an empty registry the list says `No projects registered.`. Each run is one row (state glyph, short id, title, done/total, current phase, age; a dead run's age is since its last heartbeat, and an escalated run adds `escalationReason`) whose index is its position in `filteredRuns`. A project chip row -- All projects, This project while a project is open (its run count, 0 when it has none), then one chip per other project with runs, with its count -- toggles `projectFilter` through `toggleProjectFilter`, and is hidden while am is missing and when no project is open and at most one project has runs; under it the Needs attention / Live / Parked / All chips carry `Runs.runFilterCounts` of the runs within the project filter. The row with the cursor shows `Open project` for a run of a registered project other than the open one, which asks the navigator to choose that project (`navigator.chooseProject`).
```

Edit 4 (line 165) -- old:
```
shown also while am is missing: the setting is the project's.
```
new:
```
shown also while am is missing and with no project open: it is RunStore's one viewer-wide switch (`viewer-state.py get-global-settings` / `set-global-settings`), and with it on every run toast also raises a desktop notification.
```

Edit 5 (line 167) -- old:
```
and the Runs toolbar's `▶ Start run` (`startRunButton`), which opens the whole board with a chip row
```
new:
```
and the Runs toolbar's `▶ Start run` (`startRunButton`, shown on the Runs list with or without a project and disabled with the tooltip `Open a project to dispatch` while none is open), which opens the open project's whole board with a chip row
```

Edit 6 (line 171) -- replace the whole line. old:
```
Refresh model: no timers while idle. A watch nudge costs one run read of that run (`runs-snapshot.py --run RUN`), or one list snapshot for a run the store does not know -- never a re-read per event. `RunStore`'s watch, its debounce, the liveness re-read (only while a run is running), the fallback poll,
```
new:
```
Refresh model: no timers while idle. A watch nudge costs one list snapshot of the projects whose runs it names (of every project when it names a run no project lists) -- never a re-read per event; the liveness tick snapshots only the projects with a running run; opening the panel, a registry change, a start-over and the fallback poll snapshot every project. One snapshot runs at a time, plus at most one pending request: a nudge or a tick that arrives while a snapshot runs waits as that one pending request, merged with any other (`"all"` winning, else the union of the roots), and is never stacked and never stops the snapshot in flight. `RunStore`'s watch, its debounce, the liveness tick (only while a run is running), the fallback poll,
```
(The rest of the line -- toast expiry, dispatch debounce, "run only while the panel is open", logs on demand, `Pulse` -- stays as it is.)

Edit 7 (line 180) -- old:
```
Filter and search: `runFilterCounts`, `filterRuns`, `searchRuns`.
```
new:
```
Filter and search: `runFilterCounts`, `filterRuns`, `searchRuns`. Projects: `withProject(run, root, name)` (a copy of the run tagged `project: {root, name}`, `root` with every trailing `/` removed, `name` trimmed, else the root's last segment), `filterByProject(runs, root)` (the runs whose `project.root` is `root`; `""` keeps every run), `groupByProject(runs)` (one `{project, runs, counts: {live, parked, attention}}` per project: groups with a run that needs attention first, then groups with a live run, then the rest, ties by name lower-cased, then root; each group keeps its runs in input order, which is am's; runs with no project form a last group) and `displayOrder(groups)` (the groups' runs as one list, group by group).
```

Edit 8 (line 196) -- old:
```
`runs-snapshot.py` has three modes: no argument runs `am runs --all-projects --limit 200` (every project's runs; the mode `RunStore` uses), `<project_root>` runs `am runs --repo-dir R --limit 200` (one project; `RunStore` does not use it), and `--run RUN`
```
new:
```
`RunStore`'s list snapshot is `runs-snapshot-all.py` (below). `runs-snapshot.py`, which `RunStore` does not use, has three modes: no argument runs `am runs --all-projects --limit 200` (every project's runs), `<project_root>` runs `am runs --repo-dir R --limit 200` (one project), and `--run RUN`
```

Edit 9 (line 196) -- old:
```
and reports a root's failure (`RootMissing`, `AmMissing`, `AmTimeout`, `HelperError`, or am's or `am_runs`' own error) in that root's entry only;
```
new:
```
and reports a root's failure in that root's entry only -- `RootMissing` (not a directory; am is not run for it), `AmMissing` (then in every entry), `AmTimeout`, `AmBadOutput`, `SchemaMismatch` (no non-negative integer `as_of_seq`: "the plugin needs the newer am") or `HelperError`, or am's own `ok: false` envelope's error unchanged (`StoreBusyError`, `RepoDirError`, ...);
```

Edit 10 (line 261) -- old:
```
`RunStore`'s list snapshot, run read, logs and
```
new:
```
`RunStore`'s list snapshot, logs and
```

Leave lines 149 (`RunIndicator`, already says Panel mounts it over the global run list) and 160 (`Sidebar.runsAttention`, already fed from `Runs.attention(runs).length`) as they are: re-read them and confirm they match `ui/Panel.qml` (`runIndicator`, `showRunsFiltered`) and `ui/components/Sidebar.qml:112` (the Runs row has no `enabled` gate). The phrase "not yet mounted" is not in the file (`grep -n "not yet mounted" docs/architecture.md` prints nothing).

- [ ] **Step 5: GREEN**

Run:
```bash
grep -n -o -e "the setting is the project's" -e "one run read of that run" -e "run read, logs and" -e "the mode \`RunStore\` uses" -e "\`AmTimeout\`, \`HelperError\`, or am's or" docs/architecture.md
grep -n -o -e "displayOrder(groups)\` (" -e "Open a project to dispatch" -e "with or without a project open," -e "the one section \`showSection\` opens with no project" -e "get-global-settings" -e "\`AmBadOutput\`, \`SchemaMismatch\`" docs/architecture.md
grep -n "runs-snapshot-all.py\|projectFilter\|armedRoots\|get-global-settings\|displayOrder\|Open a project to dispatch" docs/architecture.md | cut -c1-12
```
Expected: the first prints nothing; the second prints at least one hit for each of the six phrases (`get-global-settings` on lines 91 and 165, `AmBadOutput` twice on 196); the third lists lines for every term.

- [ ] **Step 6: Run the full suite**

Run: `timeout 900 bash tests/run.sh`
Expected: PASS (exit 0).

- [ ] **Step 7: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): Runs and Run detail open without a project; project filter, grouped list and the fan-out helpers"
```

---

### Task 3: `README.md` -- Runs as a global destination, plus the whole-card checks

**Files:**
- Modify: `README.md:8`, `:154`, `:155`, `:235`, `:259`

**Interfaces:**
- Consumes: nothing from the other tasks (the README names user-visible behaviour only).
- Produces: nothing.

Sources to re-read before writing: everything listed for Tasks 1 and 2, plus `ui/components/RunToast.qml` (project caption, Open / Dismiss), `ui/screens/RunsScreen.qml:313-332` (Notify on escalation: a desktop notification for every run toast), `core/backend/common/am_runs.py:14-19,34-38` (`LIST_LIMIT`, `TERMINAL_LIMIT`, the `SchemaMismatch` message), `core/domain/runs.js:507` (`errorText`: `Type: message`).

- [ ] **Step 1: RED**

Run:
```bash
grep -n -o -e "never controlled" -e "lists the open project's" -e "runs/runs-snapshot.py\`" -e "the list snapshot fails" -e "am runs --all-projects" README.md
grep -c -e "Open a project to dispatch" -e "All projects" -e "runs-snapshot-all.py" README.md
```
Expected: the first prints five hits (lines 8, 154, 235, 259, 154); the second prints `0`.

- [ ] **Step 2: Intro (line 8), Edit tool**

old:
```
and the **Runs** the `am` orchestrator makes on it (watched, never controlled).
```
new:
```
and the **Runs** the `am` orchestrator makes on every registered project (watched, and paused, resumed, cancelled or started from the panel).
```

- [ ] **Step 3: The Runs bullet (line 154), Edit tool**

Edit A -- old:
```
- **Runs** (Ctrl+6) - the runs the `am` orchestrator has made on the open project: the plugin reads every project's runs (`am runs --all-projects`) and lists the open project's, which it watches and can start (see **Dispatch** below); a run can also be paused, resumed or cancelled from the panel. Each row shows
```
new:
```
- **Runs** (Ctrl+6) - the runs the `am` orchestrator has made on every project `brd` has registered, reachable from the sidebar with or without a project open (Run detail too). The plugin asks `am` for each registered project's runs on its own (`am runs --repo-dir <project>`) and lists them grouped by project, each group under a header with the project's name and its live, parked and needs-attention counts; each project lists its non-terminal runs plus its 10 newest terminal ones, and runs of a repository `brd` has not registered never appear. A project that cannot be read (its folder is gone, `am` timed out or refused) shows why under its header and keeps the runs it had; the other projects are unaffected. With no project registered the list says `No projects registered.` A project chip row - **All projects**, **This project** while a project is open, and one chip per other project with runs, each with its run count - narrows the list to one project, shown flat; the chosen project survives a section or project switch, goes back to All projects when the panel closes, and is never saved. The panel watches the runs and can start them on the open project (see **Dispatch** below); a run of any registered project can also be paused, resumed or cancelled from the panel, which acts on the run's own repository whatever project is open, and the row under the cursor offers **Open project** for a run of another registered project, which opens that project. Each row shows
```

Edit B -- old:
```
**Needs attention** (escalated or dead), **Live** (running), **Parked** and **All** chips carry their counts, clicking
```
new:
```
**Needs attention** (escalated or dead), **Live** (running), **Parked** and **All** chips carry their counts within the chosen project, clicking
```

Edit C -- old:
```
The sidebar's Runs row shows `‼N` while N runs are escalated or dead. Nothing polls while the panel is closed.
```
new:
```
The toolbar's run indicator (`⟳N ⏸N ‼N`, counted over every registered project; a click opens the Runs list on All projects with that chip) and the sidebar's Runs row, which shows `‼N` while N runs are escalated or dead, count every registered project, whatever the Runs list's filters. While the panel is open, a run of any registered project that newly escalates or dies gets a toast naming the run and its project, with **Open** and **Dismiss**. **Notify on escalation**, under the Runs list, is one switch for the whole viewer: with it on, each such toast also raises a desktop notification. Nothing polls while the panel is closed.
```
(Everything between Edit A's and Edit B's text, and between Edit B's and Edit C's -- row contents, dead/escalated text, search, footer, Run detail, glyphs, Board/Graph marks, dimming, merged/canceled/archived -- stays word for word.)

- [ ] **Step 4: Dispatch (155), helpers (235), Install (259), Edit tool**

Edit D (155) -- old:
```
All three are disabled while `am` is missing.
```
new:
```
All three are disabled while `am` is missing, and **▶ Start run**, shown on the Runs list with or without a project, is disabled with `Open a project to dispatch` while no project is open.
```

Edit E (235) -- old:
```
(`am runs`, `am status`, `am watch --all-projects --follow` and `am logs`) through the helpers in `core/backend/runs/` (`runs/runs-snapshot.py`, `runs/runs-watch.py`, `runs/runs-logs.py`)
```
new:
```
(`am runs --repo-dir R` for each registered project, `am status`, `am watch --all-projects --follow` and `am logs`) through the helpers in `core/backend/runs/` (`runs/runs-snapshot-all.py`, `runs/runs-watch.py`, `runs/runs-logs.py`)
```
(`runs/runs-snapshot.py` leaves this list because the panel no longer runs it; `grep -rn "runs-snapshot.py" core/stores ui` prints nothing.)

Edit F (259) -- old:
```
With an older `am` the list snapshot fails and the Runs screen shows an error line saying the plugin needs the newer am;
```
new:
```
With an older `am` each project's snapshot fails with `SchemaMismatch`: its group on the Runs screen shows an error under its header saying the plugin needs the newer am (the footer says it too when no project could be read);
```

L33 (Ctrl+6) and L193 (breadcrumbs) mention no project requirement: leave them.

- [ ] **Step 5: GREEN**

Run:
```bash
grep -n -o -e "never controlled" -e "lists the open project's" -e "runs/runs-snapshot.py\`" -e "the list snapshot fails" -e "am runs --all-projects" README.md
grep -n -o -e "Open a project to dispatch" -e "All projects" -e "runs-snapshot-all.py" -e "10 newest terminal" -e "one switch for the whole viewer" README.md
```
Expected: the first prints nothing; the second prints a hit for each phrase.

- [ ] **Step 6: Review-focus checks across both files**

Run:
```bash
grep -n -o -i -e "one call" -e "no per-project error" -e "per-run read" -e "run read" -e "readRunners" docs/architecture.md README.md
grep -n -o -e "notify[^.]*per project" -e "the setting is the project's" -e "project's notify" docs/architecture.md README.md
grep -n -o -e "resets on a project switch" -e "persisted across" README.md docs/architecture.md
grep -n -o -e "survives a section or project switch" README.md
```
Expected: the first three print nothing (the only `run read`-like words left are in `runs-snapshot.py`'s own `--run RUN` mode description on line 196 -- if `run read` matches there, read the hit and confirm it describes the helper, not the store); the last prints one hit on line 154.

- [ ] **Step 7: Whole-card checks from the spec**

Run:
```bash
git diff --name-only main...HEAD -- . ':!docs/superpowers'
git status --short
grep -n -e readRunners -e "one run read" -e "the setting is the project's" -e "lists the open project's" -e "never controlled" docs/architecture.md README.md
grep -c "runs-snapshot-all.py\|projectFilter\|armedRoots\|get-global-settings\|displayOrder\|Open a project to dispatch" docs/architecture.md
timeout 900 bash tests/run.sh
```
Expected: the first lists only this card's files plus the 4.1-4.5 source files already on the branch (for this card's commits alone, `git diff --name-only HEAD~3 -- . ':!docs/superpowers'` lists exactly `README.md` and `docs/architecture.md`); `git status --short` shows only `README.md` before the commit (plus the untracked spec and plan under `docs/superpowers` if the workflow has not committed them yet); the stale grep prints nothing; the count is at least 6; the suite exits 0.

- [ ] **Step 8: Commit**

```bash
git add README.md
git commit -m "docs(readme): Runs lists every registered project, with a project filter, global notify and project-bound dispatch"
```

---

## Self-Review

**1. Spec coverage.**
- architecture passage 1 (RunStore L83-92): Task 1 replaces L83-88 with F1 (fan-out, `usableRoots`, App's `projectRoots`), F2 (state, no run reads, `{runId: 0}`), F3 (pending request, nudge, liveness, registry change, `startLive`, `stopLive`), F4 (watch roots and ids, restart, start-over, poll), F5 (arming; the existing L91 alerts text already holds `armedRoots`, `alertsOf`, toasts with `project`, `AmMissing` disarm, and gains the "registered later" clause). L89 (chips, F6) and L90 (logs, F7) are already true and kept; L91 controls (F7) and notify (F8) are already true and kept; L92 dispatch kept.
- passage 2 (Navigator, Shortcuts): Task 2 Edits 1-2.
- passage 3 (RunIndicator L149, Sidebar L160): already state Panel mounts it with global counts and a segment click opening Runs filtered, and the Sidebar feed; Task 2 Step 4 has the executor re-confirm and leave them. No "not yet mounted" phrase exists.
- passage 4 (run screens L165): Task 2 Edits 3-4; the Start run tooltip goes into the dispatch paragraph L167 (Edit 5), where `startRunButton` is already described, so the button is not described twice.
- passage 5 (refresh model L171): Task 2 Edit 6.
- passage 6 (`runs.js` L180): Task 2 Edit 7.
- passage 7 (backend L196): Task 2 Edits 8-9; `am_runs` mention at L182-183 untouched.
- passage 8 (tests L226-262): Task 2 Edit 10 removes the one "run read" claim about `RunStore`.
- README 1-6: Task 3 Steps 2-4. README item 4 says "add `runs/runs-snapshot-all.py`"; the plan replaces `runs/runs-snapshot.py` with it, since the panel runs no other list helper (state only what the code does).
- Error-path table: one root fails (Task 1 N1 + Task 3 Edit A), am missing (Task 1 N6), no project registered (Task 1 N1 `refresh()` + Task 2 Edit 3 + Task 3 Edit A), project leaves (Task 1 N2 + existing L89 fallback), two registrations (Task 1 N1), snapshot running when a nudge arrives (Task 1 N2 + Task 2 Edit 6).
- Tests table: Task 3 Step 7.

**2. Placeholder scan.** Every edit gives exact old and new text; no "TBD", no "similar to".

**3. Type consistency.** Names used across tasks match `RunStore.qml`: `requestSnapshot`, `pendingSnapshot`, `snapshotRoots`, `triggerNudges`, `refreshLive`, `registryChanged`, `resetCursor`, `startLive`, `stopLive`, `usableRoots`, `watchableRoots`, `knownRunIds`, `mergedRuns`, `armedRoots`, `projectErrors`, `runsByProject`, `projectFilter`, `toggleProjectFilter`, `livenessTimer`, `pollTimer`, `snapshotRunner`.

**4. Review Focus.** Five lines, each pinned to a grep step in the owning task.
<!-- task-pipeline: validated -->
