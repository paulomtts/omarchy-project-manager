# 3.3 RunStore: the project filter and the display order — design

Card `58c3c3f4` (subtask of story `fee6bfab` "Global runs store"), blocked by 3.2
(`b54795cd`, landed: `docs/superpowers/specs/3-2-runstore-the-watch-b54795cd.md`, cited as
**3.2:§**). 3.1 is `docs/superpowers/specs/3-1-runstore-the-d6d38ee2.md` (**3.1:§**). The parent
design is `docs/superpowers/specs/2026-10-05-runs-all-projects-design.md`, cited as **S6:line**.

Both earlier specs hand this card exactly this work: "**3.3**: `projectFilter`, `groups`,
display order, `filteredRuns` by group" (3.1 line 198; 3.2 line 204).

## Inherited constraints

- **One list order (S6:50-52).** `RunStore.filteredRuns` is the list in display order: group
  by group, each group in am's order. The screen, the navigator's cursor and
  `Shortcuts.handleRunKey` all index that one list. Group headers are not cursor targets.
- **Grouping (S6:45-49).** Groups with a run that needs attention come first, then groups with
  a live run, then the rest by name (case-blind, then root). A project with no runs is
  omitted. The status chips (Needs attention / Live / Parked / All) apply across groups.
  `Runs.groupByProject` already implements this ordering (`core/domain/runs.js:392-447`), and
  `Runs.displayOrder` flattens it (`core/domain/runs.js:449-463`). This card adds nothing to
  the domain.
- **Project filter lifetime (S6:53-58).** The choice survives section switches while the panel
  is open. It resets to All projects when the panel closes. It is never persisted. A project
  switch does not touch it. A filtered project that leaves the registry, or has no runs any
  more, falls back to All projects. S6:167 and S6:170 say the same thing.
- **Layering (S6:111, S6:127-129; `docs/architecture.md`).** `RunStore.qml` imports only
  QtQml, Quickshell, Quickshell.Io and `../domain`. It reads the registry only through
  `projectRoots` and never reaches into another store. `tests/architecture` must pass.
- **Comments state the contract only, no narrative** (card).

## Where the card is ambiguous, and the reading this spec fixes

- **What `groups` covers.** The card says "`groups` (Runs.groupByProject of the
  status-filtered, searched runs) and `filteredRuns` = Runs.displayOrder(groups) after
  Runs.filterByProject". This spec reads it as one pipeline. `groups` is grouped **after**
  the project filter, so `Runs.displayOrder(store.groups)` is `store.filteredRuns`: the same
  objects in the same order. Card 4.2 draws a header per group from `groups` while row
  `i` reads `filteredRuns[i]`. That only works when the two agree.
- **What "has no runs" means.** It is judged against `store.runs`, the registry-filtered
  snapshot. It is never judged against the chip-filtered or searched list. Suppose project A
  is filtered and the Live chip or a search leaves A with no rows. The list is then empty,
  and the project filter stays A. It does not jump to every project.
- **How the fallback shows.** It is a real change of `projectFilter` to `""`, not a derived
  "effective" value. The stored value is always the one in force. A project that comes back
  later does not bring its filter back.

## What the store must do

### 1. State

| member | kind | contract |
|---|---|---|
| `projectFilter` | `property string`, default `""` | `""` is All projects, else a project root as `Runs.withProject` tags it: trailing `/` removed, `"/"` for a root of only slashes. Its value is always either `""` or a **filterable root** (§3). |
| `projectFilterToggled()` | signal | The project filter's list changed under the cursor. Emitted by §2 and §3 only. |
| `toggleProjectFilter(root)` | function | §2. |
| `groups` | `readonly property var` | `Runs.groupByProject(Runs.filterByProject(Runs.searchRuns(Runs.filterRuns(store.runs, store.runFilter), store.searchQuery), store.projectFilter))` |
| `filteredRuns` | `readonly property var` (existing, redefined) | `Runs.displayOrder(store.groups)` |

`runFilter`, `searchQuery`, `runFilterToggled` and `toggleRunFilter` are unchanged.

Consequences the tests pin:

- With `projectFilter` `""`, `groups` has one group per project that has a run passing the
  chip and the search, in S6:46-48 order. `filteredRuns` is their runs, group by group.
  Inside a group the runs keep the order of `runs`, which is am's order per root (3.1).
- With `projectFilter` set, `groups` has at most one group, and `filteredRuns` is that
  project's runs that pass the chip and the search.
- A single-project store lists the same `filteredRuns` as today (input order). The
  existing tests at `tests/core/stores/tst_run_store.qml:2051-2097` pass unchanged.

### 2. `toggleProjectFilter(root)` (card)

1. Normalize `root`. A string has its trailing `/` removed (`"/"` stays for a root of only
   slashes). The empty string, and anything that is not a string, becomes `""`.
2. If the normalized root is `""` or equals the current `projectFilter`, `projectFilter`
   becomes `""`: the active chip again, or the All chip, means All. Otherwise it becomes
   the normalized root.
3. If the result is not a filterable root (§3), `projectFilter` becomes `""`.
4. `projectFilterToggled()` is emitted **exactly once** per call, whether or not the value
   changed. That matches `toggleRunFilter`, which always emits (`RunStore.qml:279-282`).

The call never changes `runFilter`, `searchQuery`, `selectedRunId`, `project` or any request
state. It launches no process.

### 3. The fallback (S6:57-58, S6:167, S6:170)

A **filterable root** is a root `r` with both properties:

- `r` equals the trailing-`/`-stripped root of some entry of `usableRoots()`, and
- some run in `store.runs` has `project.root === r`.

When `projectRoots` or `runs` changes and `projectFilter` is not `""` and not a filterable
root, `projectFilter` becomes `""` and `projectFilterToggled()` is emitted once. This happens
synchronously: by the time the assignment to `projectRoots`, or the reply that replaced
`runs`, returns to the test, `projectFilter` reads `""`. When `projectFilter` is `""` or still
filterable, nothing happens and nothing is emitted.

Paths that reach the fallback:

- A registry change drops the filtered root (`registryChanged`, `RunStore.qml:664-676`).
- A snapshot reply leaves the filtered root with no runs (`applyProjects`).
- `refresh()` with an empty registry empties `runs` (`RunStore.qml:213-221`).
- Starting over (`resetCursor` → `forgetLive`, `RunStore.qml:510-520`) empties `runs`. That
  resets the filter too. Starting over means am's store was replaced, so the old choice is
  not kept.

A failed entry for the filtered root keeps that root's runs (3.1 "Applying a reply"). It
therefore keeps the filter.

### 4. Lifetime (S6:53-56)

- **The panel closes** (`stopLive`, `RunStore.qml:298-316`). `projectFilter` becomes `""`. The
  signal is not emitted: the list is not on screen, and App's reset on the next opening
  belongs to the UI cards. Nothing else in `stopLive` changes.
- **The panel opens** (`startLive`). `projectFilter` is not touched. It is already `""`.
- **A project switch** (`project` changes, `projectSwitched`, `RunStore.qml:581-598`).
  `projectFilter` is not touched and no signal is emitted.
- **A section switch** is not visible to the store, so the filter survives it.
- **Never persisted.** No backend call reads or writes it.

### 5. App wiring (card: "so App resets the cursor and scroll like runFilterToggled")

`App.qml`'s `RunStore` gains an `onProjectFilterToggled` handler identical to
`onRunFilterToggled` (`core/stores/App.qml:113-116`): `app.nav.cursorIndex = 0` and
`app.nav.scrollOnCursor = false`. The Panel's scroll-to-top (`ui/Panel.qml:100`) belongs to
the UI story (`63a11d2f`, files include `ui/Panel.qml`) and is out of scope here.

## Error paths

| input | behaviour |
|---|---|
| `toggleProjectFilter(undefined / null / 42 / {})` | `projectFilter` becomes `""`; one emission |
| `toggleProjectFilter("/home/u/b/")` while `"/home/u/b"` is filterable | `projectFilter` is `"/home/u/b"` |
| `toggleProjectFilter(root)` for an unregistered root | `""`; one emission |
| `toggleProjectFilter(root)` for a registered root with no runs (for example "This project" with nothing run yet) | `""`; one emission |
| a registry entry registered as `"/home/u/b/"` | its runs carry `project.root` `"/home/u/b"`; filtering by either spelling selects it |
| `groups` / `filteredRuns` with `runs` `[]` | `[]` / `[]` |

## Tests

Store tests go in `tests/core/stores/tst_run_store.qml`. That is the **store tier**: the
behaviour is the store's own state machine, driven through stubbed Process replies with no
UI. They go in a new `// ---- the project filter and the display order (3.3)` block next to
the 5.1 filter block. They use the existing helpers `makeWithRoots`, `activeRoots`,
`makeWithProject`, `reply`, `allReply`, `okEntry`, `failEntry`, `entry`, `ids` and `spyC`,
with `rootA` "alpha", `rootB` "beta" and `rootC` "proj".

1. **Display order across projects.** Register A, B, C. A has only parked runs, B has an
   escalated run, C has a live run. The list reads B's runs, then C's, then A's, and
   `groups` names B, C, A with their counts. Store tier: it pins the store's composition of
   the domain ordering over the merged `runs`.
2. **`displayOrder(groups)` is `filteredRuns`.** In the setup of test 1, with a chip and a
   search set, `ids(Runs.displayOrder(store.groups)) === ids(store.filteredRuns)`. Store tier.
3. **Chip + search + project compose.** Register A and B, both with live and escalated runs.
   Toggle B, set `runFilter` "attention", then set a search. Each step narrows to B's
   matching runs, and `groups` holds at most the B group. Clearing the chip and the search
   lists all of B's runs. Store tier.
4. **Chip leaves the filtered project empty.** With B filtered, a chip under which B has no
   run gives `filteredRuns` `[]`, and `projectFilter` stays B (the reading in "What 'has no
   runs' means"). Store tier.
5. **Toggle semantics and the signal.** B, then C, then C again is `""`. Toggling `""` gives
   `""`. A trailing-`/` root selects its project. A non-string gives `""`. An unregistered
   root gives `""`. A registered root with no runs gives `""`. The spy counts exactly one
   emission per call. Store tier.
6. **Fallback: the registry drops the filtered root.** With B filtered, reassign
   `projectRoots` without B. `projectFilter` is `""`, the spy counted one emission, and
   `filteredRuns` lists every remaining project. Store tier.
7. **Fallback: a reply leaves the project with no runs.** With B filtered, a reply in which
   B's ok entry lists no run gives `projectFilter` `""` and one emission. A reply in which
   B's entry **failed** keeps the filter, with no emission. Store tier.
8. **No fallback while the filter still holds.** With B filtered, a reply that changes A's
   runs and keeps B's runs, and a registry change that keeps B, emit nothing and keep B.
   Store tier.
9. **Reset on close.** On an active store with B filtered, `active = false` gives
   `projectFilter` `""` with no emission. Reopening leaves it `""`. Store tier.
10. **A project switch keeps the filter.** With B filtered, setting `project` to A, then to
    `""`, keeps B, emits nothing, and leaves `filteredRuns` unchanged. Store tier.
11. **App resets the cursor on a project-filter toggle.** In `tests/core/stores/tst_app_runs.qml`,
    next to `test_a_filter_change_puts_the_cursor_home`, set `cursorIndex = 3` and
    `scrollOnCursor = true`, then call `toggleProjectFilter("")`. `cursorIndex` becomes 0
    and `scrollOnCursor` becomes false. App tier: the wiring lives in `App.qml`, not in the
    store.

Regression: the existing filter tests (`tst_run_store.qml:2051-2097`), `tst_navigator.qml`,
`tst_shortcuts.qml` and `tst_runs_real_data.qml` must stay green. Single-project order is
unchanged. Verification is `bash tests/run.sh`, all green, including `tests/architecture`.

## Out of scope

- **UI story `63a11d2f`.** Project chips and their counts (4.3, which also decides how the
  "This project" chip behaves for a project with no runs, given §2 step 3), group headers
  and the flat list under a filter (4.2), the Panel's `onProjectFilterToggled` scroll-to-top
  (`ui/Panel.qml`), and the stub `filteredRuns` in `tests/ui/screens/tst_runs_screen.qml:44`.
- **A store property listing the project chips.** The UI derives them from `runs` /
  `Runs.groupByProject`.
- **3.4**: per-project alert arming and the global notify switch. **3.5**: control, resume
  settings and logs for any project's run.
- Any change to `core/domain/runs.js`, the backends, or the snapshot and watch request
  rules of 3.1 and 3.2.

---

# 3.3 RunStore: the project filter and the display order Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `RunStore` gains a project filter (`projectFilter`, `toggleProjectFilter`, `projectFilterToggled`) with its fallback and lifetime, plus `groups`, and `filteredRuns` becomes the grouped display order; App resets the cursor on a project-filter toggle.

**Architecture:** One binding pipeline in `core/stores/RunStore.qml`: `groups = Runs.groupByProject(Runs.filterByProject(Runs.searchRuns(Runs.filterRuns(runs, runFilter), searchQuery), projectFilter))` and `filteredRuns = Runs.displayOrder(groups)`. The fallback is one `onRunsChanged` handler (every path that changes the registry or the snapshot reassigns `runs`), and `stopLive` clears the filter silently. No change to `core/domain/runs.js`.

**Tech Stack:** QML (Qt 6, Quickshell), the `core/domain/runs.js` domain library, QtTest (`qmltestrunner`) driven by `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/3-3-runstore-the-58c3c3f4.md` (prepended above).

## Global Constraints

- `RunStore.qml` imports only QtQml, Quickshell, Quickshell.Io and `../domain`; it reads the registry only through `projectRoots` and never reaches into another store. `tests/architecture` must pass.
- Comments state the contract only, no narrative.
- No change to `core/domain/runs.js`, the backends, or the snapshot and watch request rules of 3.1 and 3.2.
- `projectFilter` is never persisted: no backend call reads or writes it.
- `toggleProjectFilter` never changes `runFilter`, `searchQuery`, `selectedRunId`, `project` or any request state, and launches no process.
- `projectFilterToggled()` is emitted exactly once per `toggleProjectFilter` call, and once per fallback; never by `stopLive`, `startLive` or a project switch.
- Out of scope: `ui/Panel.qml`, `ui/screens/*`, `tests/ui/screens/tst_runs_screen.qml:44`'s stub `filteredRuns`.
- Verification: `bash tests/run.sh`, all green, including `tests/architecture`.

## Review Focus

1. **Starting over with a project filtered** (`resetCursor`, a store change): `runs` is emptied, so `projectFilter` must read `""` with one emission — the old store's choice is not kept. Test in Task 3 (`test_starting_over_resets_the_project_filter`).
2. **An all-`AmMissing` reply with a project filtered**: `runs` is emptied, so `projectFilter` falls back to `""` with one emission. Test in Task 3 (`test_a_reply_that_leaves_the_project_without_runs_falls_back_to_all`).
3. **The registry emptied** (`projectRoots = []`, the `refresh()` empty-registry path): `projectFilter` is `""` with one emission and `filteredRuns` is `[]`. Test in Task 3 (`test_the_registry_dropping_the_filtered_root_falls_back_to_all`).
4. **The filtered project comes back after a fallback**: it does not bring its filter back; `projectFilter` stays `""` and the list lists every project. Test in Task 3 (same test as 3).
5. **A whole-envelope failure (`ok:false`) while filtered**: `runs` is not replaced, so the filter stays with no emission. Test in Task 3 (`test_a_failed_entry_or_envelope_keeps_the_project_filter`).

---

## File Structure

- Modify `core/stores/RunStore.qml` — the state (`projectFilter`, `projectFilterToggled`, `groups`, `filteredRuns`), `toggleProjectFilter`, `projectRootOf`, `isFilterable`, `keepProjectFilter` + `onRunsChanged`, and one line in `stopLive`.
- Modify `core/stores/App.qml` — `onProjectFilterToggled` on the composed `RunStore`.
- Modify `docs/architecture.md:89` — the Runs list sentence describes the new pipeline and the project filter.
- Test `tests/core/stores/tst_run_store.qml` — a new block `// ---- the project filter and the display order (3.3)` inserted right after `test_a_project_switch_keeps_the_filter` (currently ends at line 2095) and before `// ---- attempt logs (5.2)`.
- Test `tests/core/stores/tst_app_runs.qml` — one test after `test_a_filter_change_puts_the_cursor_home`.

## How to run the tests

`bash tests/run.sh <substring>` runs pytest, then every QML test whose path contains the substring, printing only `FAIL` lines and the `Totals` line per file, plus any `TypeError` / `ReferenceError` / `is not a function` line (which also fails the run). There is no per-function filter: read the `FAIL!  : StoresRunStore::<test name>` lines.

Fixture facts the tests rely on (from `tst_run_store.qml`): `rootA` = `"/home/u/my proj"` (name `"alpha"`), `rootB` = `"/home/u/b"` (`"beta"`), `rootC` = `"/home/u/c"` (`"proj"`); any other root registered via `rootEntry`/`registry` is named `"proj"`. `entry(id, status, live, root)` builds one snapshot entry; by `Runs.runState`: `"started"` + `live` true is running (Live chip), `"started"` + false is dead (attention), `"escalated"` is attention, `"stopped"` is parked. `allReply(projects)`, `okEntry(root, runs)`, `failEntry(root, type, message)`, `reply(proc, text, code)`, `ids(list)` (comma-joined ids; defined at line 2049, so it is in scope for the new block), `spyC` (a `SignalSpy` component), `makeWithRoots(roots)`, `activeRoots(roots)`.

---

### Task 1: `groups` and the display order

**Files:**
- Modify: `core/stores/RunStore.qml:62-70`
- Test: `tests/core/stores/tst_run_store.qml` (new block after line 2095)

**Interfaces:**
- Consumes: `Runs.groupByProject(runs)`, `Runs.displayOrder(groups)`, `Runs.filterByProject(runs, root)`, `Runs.filterRuns`, `Runs.searchRuns` (all existing in `core/domain/runs.js`).
- Produces: `store.projectFilter` (`property string`, default `""`), `store.groups` (`readonly property var`: `[{ project: { root, name }, runs, counts: { live, parked, attention } }]`), `store.filteredRuns` (`readonly property var` = `Runs.displayOrder(store.groups)`). Test helpers `tc.rootD` (`"/home/u/d"`), `projectEntries()`, `projectsStore(open)`, `groupText(store)`.

- [ ] **Step 1: Write the failing tests**

Insert into `tests/core/stores/tst_run_store.qml` directly after the closing `}` of `test_a_project_switch_keeps_the_filter` (before the blank line and `// ---- attempt logs (5.2)`):

```qml

  // ---- the project filter and the display order (3.3)

  readonly property string rootD: "/home/u/d"

  // The reply for rootA..rootD: A has only parked runs, B an escalated and a
  // parked one, C a live and a parked one, D none.
  function projectEntries() {
    return [okEntry(tc.rootA, [entry("a-park1", "stopped", false, tc.rootA), entry("a-park2", "stopped", false, tc.rootA)]),
            okEntry(tc.rootB, [entry("b-esc1", "escalated", false, tc.rootB), entry("b-park1", "stopped", false, tc.rootB)]),
            okEntry(tc.rootC, [entry("c-live1", "started", true, tc.rootC), entry("c-park1", "stopped", false, tc.rootC)]),
            okEntry(tc.rootD, [])]
  }

  // A store with rootA ("alpha"), rootB ("beta"), rootC ("proj") and rootD
  // ("proj") registered, the panel open when `open`, and projectEntries()
  // applied.
  function projectsStore(open) {
    var roots = [tc.rootA, tc.rootB, tc.rootC, tc.rootD]
    var store = open ? activeRoots(roots) : makeWithRoots(roots); if (!store) return null
    reply(store.snapshotRunner.current, allReply(projectEntries()), 0)
    return store
  }

  // Each group as "name:attention/live/parked", in order.
  function groupText(store) {
    return store.groups.map(function(g) {
      return g.project.name + ":" + g.counts.attention + "/" + g.counts.live + "/" + g.counts.parked
    }).join(",")
  }

  // 1
  function test_the_list_reads_project_by_project_in_display_order() {
    var store = projectsStore(false); if (!store) return
    compare(store.projectFilter, "")
    compare(ids(store.runs), "a-park1,a-park2,b-esc1,b-park1,c-live1,c-park1", "runs stay in registry order")
    compare(groupText(store), "beta:1/0/1,proj:0/1/1,alpha:0/0/2",
            "attention first, then live, then the rest; D has no runs and no group")
    compare(store.groups[0].project.root, tc.rootB)
    compare(store.groups[1].project.root, tc.rootC)
    compare(store.groups[2].project.root, tc.rootA)
    compare(ids(store.filteredRuns), "b-esc1,b-park1,c-live1,c-park1,a-park1,a-park2",
            "group by group, each group in am's order")
    verify(store.filteredRuns[0] === store.groups[0].runs[0], "the same objects")
  }

  // 2
  function test_display_order_of_groups_is_filtered_runs() {
    var store = projectsStore(false); if (!store) return
    store.runFilter = "parked"
    store.searchQuery = "park1"
    compare(ids(Runs.displayOrder(store.groups)), ids(store.filteredRuns))
    compare(groupText(store), "alpha:0/0/1,beta:0/0/1,proj:0/0/1", "groups count only the runs the chip and the search keep")
    compare(ids(store.filteredRuns), "a-park1,b-park1,c-park1")
    store.runFilter = "attention"
    store.searchQuery = ""
    compare(ids(Runs.displayOrder(store.groups)), ids(store.filteredRuns))
    compare(ids(store.filteredRuns), "b-esc1")
  }

  function test_no_runs_give_no_groups_and_an_empty_list() {
    var store = make(); if (!store) return
    compare(store.groups.length, 0)
    compare(store.filteredRuns.length, 0)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store.qml`
Expected: FAIL lines for `test_the_list_reads_project_by_project_in_display_order`, `test_display_order_of_groups_is_filtered_runs` and `test_no_runs_give_no_groups_and_an_empty_list` (`store.groups` is undefined: a `TypeError` on `.map` / `.length`, or `projectFilter` compares `undefined` to `""`).

- [ ] **Step 3: Write the implementation**

In `core/stores/RunStore.qml`, replace lines 62-70:

```qml
  // The Runs screen's chip ("" means All, else "attention" | "live" | "parked")
  // and search text. App binds searchQuery to the navigation store; the chip
  // survives a section switch and a project switch.
  property string runFilter: ""
  property string searchQuery: ""
  // The chip changed: a different list, so the cursor goes home (App's job).
  signal runFilterToggled()
  // The one filtered list: the screen's rows and the navigator's cursor list.
  readonly property var filteredRuns: Runs.searchRuns(Runs.filterRuns(store.runs, store.runFilter), store.searchQuery)
```

with:

```qml
  // The Runs screen's chip ("" means All, else "attention" | "live" | "parked")
  // and search text. App binds searchQuery to the navigation store; the chip
  // survives a section switch and a project switch.
  property string runFilter: ""
  property string searchQuery: ""
  // The chip changed: a different list, so the cursor goes home (App's job).
  signal runFilterToggled()
  // The Runs screen's project filter: "" is All projects, else a project root
  // as Runs.withProject tags it.
  property string projectFilter: ""
  // The runs past the chip, the search and the project filter, grouped by
  // project in display order (Runs.groupByProject).
  readonly property var groups: Runs.groupByProject(Runs.filterByProject(Runs.searchRuns(Runs.filterRuns(store.runs, store.runFilter), store.searchQuery), store.projectFilter))
  // The one filtered list: the screen's rows and the navigator's cursor list,
  // group by group (Runs.displayOrder of groups).
  readonly property var filteredRuns: Runs.displayOrder(store.groups)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store.qml`
Expected: no `FAIL` line; `Totals: N passed, 0 failed`. The 5.1 tests (`test_filtered_runs_follow_the_filter_and_the_search`, `test_toggle_run_filter_and_back_to_all`, `test_a_project_switch_keeps_the_filter`) still pass: one project is one group in input order.

Then run the screens that index `filteredRuns`: `bash tests/run.sh tests/ui`
Expected: no `FAIL` line in `tst_navigator.qml`, `tst_shortcuts.qml`, `tst_runs_real_data.qml`.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): the run list reads project by project in display order"
```

---

### Task 2: `toggleProjectFilter` and `projectFilterToggled`

**Files:**
- Modify: `core/stores/RunStore.qml` (the new property block from Task 1, and after `toggleRunFilter`, currently lines 278-282)
- Test: `tests/core/stores/tst_run_store.qml` (append to the 3.3 block)

**Interfaces:**
- Consumes: `store.projectFilter`, `store.groups`, `store.filteredRuns` (Task 1); `store.usableRoots()` (existing, `[{root, name}]`); `Runs.withProject(run, root, name)`.
- Produces: `signal projectFilterToggled()`; `function toggleProjectFilter(root)` (returns nothing); `function projectRootOf(root)` → string (`root` with trailing `/` removed, `"/"` for only slashes, `""` for `""` or a non-string); `function isFilterable(root)` → bool (a non-empty `root` equal to `projectRootOf` of some usable root and the `project.root` of some run in `runs`).

- [ ] **Step 1: Write the failing tests**

Append to the 3.3 block in `tests/core/stores/tst_run_store.qml` (after `test_no_runs_give_no_groups_and_an_empty_list`):

```qml

  // 3
  function test_chip_search_and_project_compose() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([
      okEntry(tc.rootA, [entry("a-live1", "started", true, tc.rootA), entry("a-esc2", "escalated", false, tc.rootA)]),
      okEntry(tc.rootB, [entry("b-live1", "started", true, tc.rootB), entry("b-esc1", "escalated", false, tc.rootB),
                         entry("b-esc2", "escalated", false, tc.rootB)])]), 0)
    store.toggleProjectFilter(tc.rootB)
    compare(store.projectFilter, tc.rootB)
    compare(ids(store.filteredRuns), "b-live1,b-esc1,b-esc2")
    compare(store.groups.length, 1)
    compare(store.groups[0].project.root, tc.rootB)
    store.runFilter = "attention"
    compare(ids(store.filteredRuns), "b-esc1,b-esc2")
    compare(store.groups.length, 1)
    store.searchQuery = "esc2"
    compare(ids(store.filteredRuns), "b-esc2", "A's esc2 is not listed")
    compare(store.groups.length, 1)
    compare(store.groups[0].project.root, tc.rootB)
    store.runFilter = ""
    store.searchQuery = ""
    compare(ids(store.filteredRuns), "b-live1,b-esc1,b-esc2")
    compare(store.projectFilter, tc.rootB)
  }

  // 4
  function test_a_chip_that_empties_the_filtered_project_keeps_the_filter() {
    var store = projectsStore(false); if (!store) return
    store.toggleProjectFilter(tc.rootB)
    store.runFilter = "live"
    compare(store.filteredRuns.length, 0, "B has no live run")
    compare(store.groups.length, 0)
    compare(store.projectFilter, tc.rootB, "judged against runs, not the chip's list")
    store.runFilter = ""
    store.searchQuery = "zzz"
    compare(store.filteredRuns.length, 0)
    compare(store.projectFilter, tc.rootB, "nor the search's")
    store.searchQuery = ""
    compare(ids(store.filteredRuns), "b-esc1,b-park1")
  }

  // 5
  function test_toggle_project_filter_and_its_signal() {
    var store = projectsStore(false); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "projectFilterToggled" })
    var request = store.snapshotRunner.current
    store.toggleProjectFilter(tc.rootB)
    compare(store.projectFilter, tc.rootB)
    compare(spy.count, 1)
    store.toggleProjectFilter(tc.rootC)
    compare(store.projectFilter, tc.rootC, "another project replaces the filter")
    compare(spy.count, 2)
    store.toggleProjectFilter(tc.rootC)
    compare(store.projectFilter, "", "the active project again is All")
    compare(spy.count, 3)
    store.toggleProjectFilter("")
    compare(store.projectFilter, "", "the All chip is All")
    compare(spy.count, 4, "emitted even when nothing changed")
    store.toggleProjectFilter(tc.rootB + "/")
    compare(store.projectFilter, tc.rootB, "a trailing / selects the project")
    compare(ids(store.filteredRuns), "b-esc1,b-park1")
    compare(spy.count, 5)
    store.toggleProjectFilter("")
    compare(spy.count, 6)
    var junk = [undefined, null, 42, {}, [tc.rootB]]
    for (var i = 0; i < junk.length; i++) {
      store.toggleProjectFilter(tc.rootB)
      compare(store.projectFilter, tc.rootB)
      store.toggleProjectFilter(junk[i])
      compare(store.projectFilter, "", "a non-string is All: " + i)
    }
    compare(spy.count, 6 + 2 * junk.length)
    store.toggleProjectFilter("/home/u/zz")
    compare(store.projectFilter, "", "an unregistered root is All")
    store.toggleProjectFilter(tc.rootD)
    compare(store.projectFilter, "", "a registered root with no runs is All")
    store.toggleProjectFilter("///")
    compare(store.projectFilter, "", "\"/\" is not registered")
    compare(spy.count, 6 + 2 * junk.length + 3, "one emission per call")
    compare(store.runFilter, "")
    compare(store.searchQuery, "")
    compare(store.project, "")
    compare(store.snapshotRunner.current, request, "no process is launched")
  }

  // Error paths: a registry entry with a trailing "/"
  function test_a_root_registered_with_a_trailing_slash_is_filtered_by_either_spelling() {
    var store = make(); if (!store) return
    store.projectRoots = [{ root: tc.rootB + "/", name: "beta" }, rootEntry(tc.rootA)]
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB + "/", [entry("b-esc1", "escalated", false, tc.rootB)]),
                                                  okEntry(tc.rootA, [entry("a-park1", "stopped", false, tc.rootA)])]), 0)
    compare(store.runs[0].project.root, tc.rootB, "Runs.withProject removes the trailing /")
    store.toggleProjectFilter(tc.rootB)
    compare(store.projectFilter, tc.rootB)
    compare(ids(store.filteredRuns), "b-esc1")
    store.toggleProjectFilter("")
    store.toggleProjectFilter(tc.rootB + "/")
    compare(store.projectFilter, tc.rootB)
    compare(ids(store.filteredRuns), "b-esc1")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store.qml`
Expected: FAIL lines for the four new tests, with `TypeError: Property 'toggleProjectFilter' of object ... is not a function` (and `SignalSpy` unable to find `projectFilterToggled` in `test_toggle_project_filter_and_its_signal`).

- [ ] **Step 3: Write the implementation**

In `core/stores/RunStore.qml`, in the Task 1 block, replace:

```qml
  // The Runs screen's project filter: "" is All projects, else a project root
  // as Runs.withProject tags it.
  property string projectFilter: ""
```

with:

```qml
  // The Runs screen's project filter: "" is All projects, else a filterable
  // root (isFilterable). Set by toggleProjectFilter; never persisted.
  property string projectFilter: ""
  // The project filter's list changed under the cursor: emitted once per
  // toggleProjectFilter call.
  signal projectFilterToggled()
```

Then, directly after the `toggleRunFilter` function:

```qml
  // A chip was chosen: the All chip, or the active one again, means All.
  function toggleRunFilter(id) {
    store.runFilter = id === "all" || id === store.runFilter ? "" : String(id || "")
    store.runFilterToggled()
  }
```

insert:

```qml

  // A project chip was chosen (projectRootOf(root)): "", or the active
  // project again, means All; a root that is not filterable means All.
  // Emits projectFilterToggled once, whether or not the filter changed.
  function toggleProjectFilter(root) {
    var want = store.projectRootOf(root)
    var next = want === "" || want === store.projectFilter ? "" : want
    store.projectFilter = store.isFilterable(next) ? next : ""
    store.projectFilterToggled()
  }

  // `root` as Runs.withProject tags it: every trailing "/" removed, "/" for a
  // root of only slashes; "" for "" and for anything that is not a string.
  function projectRootOf(root) {
    return Runs.withProject({}, root, "").project.root
  }

  // Whether the project filter may hold `root`: it is not "", it is
  // projectRootOf a usable root, and some run in `runs` has it as
  // project.root.
  function isFilterable(root) {
    if (typeof root !== "string" || root === "") return false
    var usable = store.usableRoots()
    var registered = false
    for (var i = 0; i < usable.length && !registered; i++) {
      if (store.projectRootOf(usable[i].root) === root) registered = true
    }
    if (!registered) return false
    var list = store.runs
    for (var j = 0; j < list.length; j++) {
      var run = list[j]
      var p = run !== null && typeof run === "object" ? run.project : null
      if (p !== null && typeof p === "object" && p.root === root) return true
    }
    return false
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store.qml`
Expected: no `FAIL` line; `Totals: N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): a project filter toggled by root, All for anything not filterable"
```

---

### Task 3: The fallback to All projects

**Files:**
- Modify: `core/stores/RunStore.qml` (after `isFilterable` from Task 2; the `projectFilter` / `projectFilterToggled` comments from Task 2)
- Test: `tests/core/stores/tst_run_store.qml` (append to the 3.3 block)

**Interfaces:**
- Consumes: `store.isFilterable(root)`, `store.toggleProjectFilter(root)`, `signal projectFilterToggled()` (Task 2); `store.resetCursor()`, `store.refresh()` (existing).
- Produces: `function keepProjectFilter()` (no return) and the `onRunsChanged: store.keepProjectFilter()` handler.

- [ ] **Step 1: Write the failing tests**

Append to the 3.3 block in `tests/core/stores/tst_run_store.qml`:

```qml

  // 6 and Review Focus 3, 4
  function test_the_registry_dropping_the_filtered_root_falls_back_to_all() {
    var store = projectsStore(false); if (!store) return
    store.toggleProjectFilter(tc.rootB)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "projectFilterToggled" })
    store.projectRoots = registry([tc.rootA, tc.rootC, tc.rootD])
    compare(store.projectFilter, "", "synchronous, by the time the assignment returns")
    compare(spy.count, 1)
    compare(ids(store.filteredRuns), "c-live1,c-park1,a-park1,a-park2", "every remaining project")
    store.projectRoots = registry([tc.rootA, tc.rootB, tc.rootC, tc.rootD])
    reply(store.snapshotRunner.current, allReply(projectEntries()), 0)
    compare(store.projectFilter, "", "the project coming back does not bring its filter back")
    compare(ids(store.filteredRuns), "b-esc1,b-park1,c-live1,c-park1,a-park1,a-park2")
    compare(spy.count, 1)

    var emptied = projectsStore(false); if (!emptied) return
    emptied.toggleProjectFilter(tc.rootB)
    var spy2 = createTemporaryObject(spyC, tc, { target: emptied, signalName: "projectFilterToggled" })
    emptied.projectRoots = []
    compare(emptied.projectFilter, "", "an empty registry empties runs")
    compare(spy2.count, 1)
    compare(emptied.filteredRuns.length, 0)
  }

  // 7 and Review Focus 2
  function test_a_reply_that_leaves_the_project_without_runs_falls_back_to_all() {
    var store = projectsStore(false); if (!store) return
    store.toggleProjectFilter(tc.rootB)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "projectFilterToggled" })
    store.refresh()
    var entries = projectEntries()
    entries[1] = okEntry(tc.rootB, [])
    reply(store.snapshotRunner.current, allReply(entries), 0)
    compare(store.projectFilter, "")
    compare(spy.count, 1)
    compare(ids(store.filteredRuns), "c-live1,c-park1,a-park1,a-park2")

    var missing = projectsStore(false); if (!missing) return
    missing.toggleProjectFilter(tc.rootB)
    var spy2 = createTemporaryObject(spyC, tc, { target: missing, signalName: "projectFilterToggled" })
    missing.refresh()
    reply(missing.snapshotRunner.current, allReply([tc.rootA, tc.rootB, tc.rootC, tc.rootD].map(function(r) {
      return tc.failEntry(r, "AmMissing", "am is not installed or not on PATH.")
    })), 0)
    compare(missing.amStatus, "missing")
    compare(missing.projectFilter, "", "am missing empties runs")
    compare(spy2.count, 1)
  }

  // 7 (failed entry) and Review Focus 5
  function test_a_failed_entry_or_envelope_keeps_the_project_filter() {
    var store = projectsStore(false); if (!store) return
    store.toggleProjectFilter(tc.rootB)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "projectFilterToggled" })
    store.refresh()
    var entries = projectEntries()
    entries[1] = failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")
    reply(store.snapshotRunner.current, allReply(entries), 0)
    compare(store.projectErrors[tc.rootB], "AmTimeout: am did not answer within 60 s.")
    compare(store.projectFilter, tc.rootB, "a failed entry keeps B's runs")
    compare(ids(store.filteredRuns), "b-esc1,b-park1")
    store.refresh()
    reply(store.snapshotRunner.current,
          JSON.stringify({ ok: false, error: { type: "HelperError", message: "boom" } }) + "\n", 1)
    compare(store.amStatus, "error")
    compare(store.projectFilter, tc.rootB, "a failed envelope keeps every run")
    compare(spy.count, 0)
  }

  // 8
  function test_no_fallback_while_the_filter_still_holds() {
    var store = projectsStore(false); if (!store) return
    store.toggleProjectFilter(tc.rootB)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "projectFilterToggled" })
    store.refresh()
    var entries = projectEntries()
    entries[0] = okEntry(tc.rootA, [entry("a-park3", "stopped", false, tc.rootA)])
    reply(store.snapshotRunner.current, allReply(entries), 0)
    compare(ids(store.runs), "a-park3,b-esc1,b-park1,c-live1,c-park1", "A's runs changed")
    compare(store.projectFilter, tc.rootB)
    store.projectRoots = registry([tc.rootB, tc.rootA, tc.rootC])
    compare(store.projectFilter, tc.rootB, "a registry change that keeps B")
    compare(ids(store.filteredRuns), "b-esc1,b-park1")
    compare(spy.count, 0)
  }

  // Review Focus 1
  function test_starting_over_resets_the_project_filter() {
    var store = projectsStore(true); if (!store) return
    store.toggleProjectFilter(tc.rootB)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "projectFilterToggled" })
    store.resetCursor()
    compare(store.runs.length, 0)
    compare(store.projectFilter, "", "the old store's choice is not kept")
    compare(spy.count, 1)
    reply(store.snapshotRunner.current, allReply(projectEntries()), 0)
    compare(store.projectFilter, "")
    compare(spy.count, 1)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store.qml`
Expected: FAIL lines for `test_the_registry_dropping_the_filtered_root_falls_back_to_all`, `test_a_reply_that_leaves_the_project_without_runs_falls_back_to_all` and `test_starting_over_resets_the_project_filter` (`projectFilter` is still `"/home/u/b"`, expected `""`). `test_a_failed_entry_or_envelope_keeps_the_project_filter` and `test_no_fallback_while_the_filter_still_holds` pass already: they pin that the fallback must not fire there.

- [ ] **Step 3: Write the implementation**

In `core/stores/RunStore.qml`, replace the Task 2 comments:

```qml
  // The Runs screen's project filter: "" is All projects, else a filterable
  // root (isFilterable). Set by toggleProjectFilter; never persisted.
  property string projectFilter: ""
  // The project filter's list changed under the cursor: emitted once per
  // toggleProjectFilter call.
  signal projectFilterToggled()
```

with:

```qml
  // The Runs screen's project filter: "" is All projects, else a filterable
  // root (isFilterable). Set by toggleProjectFilter; back to "" when it stops
  // being filterable (keepProjectFilter). Never persisted.
  property string projectFilter: ""
  // The project filter's list changed under the cursor: emitted once per
  // toggleProjectFilter call and once per fallback to All.
  signal projectFilterToggled()
```

Then, directly after the `isFilterable` function, insert:

```qml

  // `runs` changed (a reply, a registry change, emptying, starting over): a
  // project filter that is no longer filterable becomes "" and
  // projectFilterToggled is emitted once; otherwise nothing happens.
  function keepProjectFilter() {
    if (store.projectFilter === "" || store.isFilterable(store.projectFilter)) return
    store.projectFilter = ""
    store.projectFilterToggled()
  }

  onRunsChanged: store.keepProjectFilter()
```

(`registryChanged` always reassigns `runs` after `projectRoots` changes, and `refresh()` with an empty registry, `forgetLive` and both `applyProjects` paths that change the list assign `runs`, so one handler covers every path in spec §3.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store.qml`
Expected: no `FAIL` line; `Totals: N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): a filtered project that leaves the registry or has no runs falls back to All"
```

---

### Task 4: The filter's lifetime — reset on close, kept across a project switch

**Files:**
- Modify: `core/stores/RunStore.qml` (`stopLive`, currently lines 298-316; the `projectFilter` comment from Task 3)
- Modify: `docs/architecture.md:89`
- Test: `tests/core/stores/tst_run_store.qml` (append to the 3.3 block)

**Interfaces:**
- Consumes: `store.projectFilter`, `store.toggleProjectFilter(root)`, `signal projectFilterToggled()` (Tasks 1-3); `store.active` (existing; `onActiveChanged` calls `startLive` / `stopLive`).
- Produces: `stopLive()` additionally sets `projectFilter` to `""` without emitting.

- [ ] **Step 1: Write the failing tests**

Append to the 3.3 block in `tests/core/stores/tst_run_store.qml`:

```qml

  // 9
  function test_closing_the_panel_resets_the_project_filter_silently() {
    var store = projectsStore(true); if (!store) return
    store.toggleProjectFilter(tc.rootB)
    store.runFilter = "attention"
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "projectFilterToggled" })
    store.active = false
    compare(store.projectFilter, "")
    compare(spy.count, 0, "the list is not on screen")
    compare(store.runFilter, "attention", "nothing else in stopLive changes")
    compare(ids(store.runs), "a-park1,a-park2,b-esc1,b-park1,c-live1,c-park1", "the runs stay")
    store.active = true
    compare(store.projectFilter, "", "opening leaves it at All")
    compare(spy.count, 0)
  }

  // 10
  function test_a_project_switch_keeps_the_project_filter() {
    var store = projectsStore(false); if (!store) return
    store.toggleProjectFilter(tc.rootB)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "projectFilterToggled" })
    store.project = tc.rootA
    compare(store.projectFilter, tc.rootB)
    compare(ids(store.filteredRuns), "b-esc1,b-park1")
    store.project = ""
    compare(store.projectFilter, tc.rootB)
    compare(ids(store.filteredRuns), "b-esc1,b-park1")
    compare(spy.count, 0)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store.qml`
Expected: FAIL for `test_closing_the_panel_resets_the_project_filter_silently` (`Actual: /home/u/b`, `Expected: ""`). `test_a_project_switch_keeps_the_project_filter` already passes: `projectSwitched` never touches the filter, and this test pins that.

- [ ] **Step 3: Write the implementation**

In `core/stores/RunStore.qml`, replace the start of `stopLive`:

```qml
  // The panel closed: no process and no timer is left running, and no toast
  // or dispatch outlives the opening (a start in flight runs to its end). The
  // pending snapshot request is dropped; a snapshot in flight runs to its end
  // and is applied. The runs, the selection and amStatus stay for the next
  // opening.
  function stopLive() {
    snapshotState.pending = null
```

with:

```qml
  // The panel closed: no process and no timer is left running, and no toast
  // or dispatch outlives the opening (a start in flight runs to its end). The
  // pending snapshot request is dropped; a snapshot in flight runs to its end
  // and is applied. The project filter is back to All projects, with no
  // projectFilterToggled. The runs, the selection, the chip and amStatus stay
  // for the next opening.
  function stopLive() {
    store.projectFilter = ""
    snapshotState.pending = null
```

And replace the `projectFilter` comment from Task 3:

```qml
  // The Runs screen's project filter: "" is All projects, else a filterable
  // root (isFilterable). Set by toggleProjectFilter; back to "" when it stops
  // being filterable (keepProjectFilter). Never persisted.
  property string projectFilter: ""
```

with:

```qml
  // The Runs screen's project filter: "" is All projects, else a filterable
  // root (isFilterable). Set by toggleProjectFilter; back to "" when it stops
  // being filterable (keepProjectFilter) and when the panel closes. A project
  // switch keeps it. Never persisted.
  property string projectFilter: ""
```

In `docs/architecture.md`, replace line 89 (the bullet that begins `  The Runs list is \`filteredRuns\`, \`Runs.searchRuns(Runs.filterRuns(runs, runFilter), searchQuery)\``) with:

```markdown
  The Runs list is `filteredRuns`, `Runs.displayOrder(groups)`, where `groups` is `Runs.groupByProject(Runs.filterByProject(Runs.searchRuns(Runs.filterRuns(runs, runFilter), searchQuery), projectFilter))`: project by project (attention first, then live, then by name), each project's runs in am's order. `runFilter` is `""` (All) or `attention` / `live` / `parked`, set by `toggleRunFilter(id)` (the All chip, or the active chip again, means All), which emits `runFilterToggled()`; `App` binds `searchQuery` to the navigation store's. `projectFilter` is `""` (All projects) or a project root with runs in `runs`, set by `toggleProjectFilter(root)` (`""`, the active root again, or a root that is not registered or has no runs means All), which emits `projectFilterToggled()`; when the filtered root leaves the registry or loses its runs it falls back to `""` and emits once. On either signal App puts the cursor home. The chip and the project filter survive a section and a project switch; the project filter resets to All when the panel closes and is never persisted.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store.qml`
Expected: no `FAIL` line; `Totals: N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml docs/architecture.md
git commit -m "feat(run-store): the project filter resets when the panel closes and survives a project switch"
```

---

### Task 5: App puts the cursor home on a project-filter toggle

**Files:**
- Modify: `core/stores/App.qml:113-116`
- Test: `tests/core/stores/tst_app_runs.qml` (after `test_a_filter_change_puts_the_cursor_home`, the last test)

**Interfaces:**
- Consumes: `app.runs.toggleProjectFilter(root)` and `signal projectFilterToggled()` (Task 2); `app.nav.cursorIndex`, `app.nav.scrollOnCursor` (existing).
- Produces: `onProjectFilterToggled` handler on App's `RunStore`.

- [ ] **Step 1: Write the failing test**

In `tests/core/stores/tst_app_runs.qml`, after the closing `}` of `test_a_filter_change_puts_the_cursor_home` and before the file's final `}`, insert:

```qml

  // ---- the project filter (3.3)

  // 11
  function test_a_project_filter_toggle_puts_the_cursor_home() {
    var app = makeBare(); if (!app) return
    app.nav.cursorIndex = 3
    app.nav.scrollOnCursor = true
    app.runs.toggleProjectFilter("")
    compare(app.nav.cursorIndex, 0)
    compare(app.nav.scrollOnCursor, false)
  }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/run.sh tst_app_runs.qml`
Expected: `FAIL!  : StoresAppRuns::test_a_project_filter_toggle_puts_the_cursor_home()` with `Actual (): 3` / `Expected (): 0`.

- [ ] **Step 3: Write the implementation**

In `core/stores/App.qml`, replace:

```qml
    searchQuery: app.nav.searchQuery
    onRunFilterToggled: {
      app.nav.cursorIndex = 0
      app.nav.scrollOnCursor = false
    }
  }
```

with:

```qml
    searchQuery: app.nav.searchQuery
    onRunFilterToggled: {
      app.nav.cursorIndex = 0
      app.nav.scrollOnCursor = false
    }
    onProjectFilterToggled: {
      app.nav.cursorIndex = 0
      app.nav.scrollOnCursor = false
    }
  }
```

- [ ] **Step 4: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest passes (including `tests/architecture/test_layers.py`), and every QML file prints `Totals: N passed, 0 failed` with no `FAIL` line and no `TypeError` / `ReferenceError` line; exit status 0.

- [ ] **Step 5: Commit**

```bash
git add core/stores/App.qml tests/core/stores/tst_app_runs.qml
git commit -m "feat(app): a project-filter toggle puts the run cursor home"
```
<!-- task-pipeline: validated -->
