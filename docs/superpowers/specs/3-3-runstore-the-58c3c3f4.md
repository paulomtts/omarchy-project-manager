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
