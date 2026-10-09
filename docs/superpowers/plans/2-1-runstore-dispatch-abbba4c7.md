# 2.1 RunStore dispatch: dispatchRoot drives every dispatch launch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `RunStore` gets `dispatchRoot`, the project root a dispatch is for, and every dispatch launch (defaults, preview, settings read, start, settings save) carries it instead of `project`; card entry points set `dispatchRoot = project`, so card dispatch is unchanged.

**Architecture:** All changes live in S3's delimited dispatch section of `core/stores/RunStore.qml` (functions from `// ---- dispatch (S3 3.1)`, the dispatch runners, `dispatchBook`, `dispatchStartC`). `openDispatch` becomes a thin card entry over a new public `dispatchOpenFor`. When `dispatchRoot !== project`, the dispatch reads that root's run settings on a new `dispatchSettingsRunner` into a new `dispatchRunSettings`, and a one-function switch (`dispatchSettingsSource()`) decides which settings object the dispatch reads and merges into. A `started` reply asks `requestSnapshot([dispatchRoot])` instead of `refresh()`.

**Tech Stack:** QML (Qt 6, Quickshell), the `runs.js` domain library (unchanged), QtTest store tests run by `qmltestrunner` with the stub `Process` in `tests/stubs`, the `bash tests/run.sh` gate (pytest + every QML test).

**Spec:** `docs/superpowers/specs/2-1-runstore-dispatch-abbba4c7.md` (prepended below, headings demoted one level; executors read both).

## Global Constraints

- Every member this card adds is prefixed `dispatch*` and lives inside S3's dispatch section of `core/stores/RunStore.qml` (functions between `// ---- dispatch (S3 3.1)` and the first runner below it; the dispatch runners; `dispatchBook`; `dispatchStartC`).
- Every dispatch launch (defaults, preview, start) and every run-settings launch the dispatch makes (`get-run-settings` read, `set-run-settings` save including `prefixByMilestone`) carries `dispatchRoot`, never `project`.
- A card entry (`openDispatch`) sets `dispatchRoot = project`. Card dispatch is unchanged: every existing dispatch test passes, the only existing-test edit being the one listed in Task 2.
- The prefix default reads `Runs.filterByProject(store.runs, dispatchRoot)`, never `store.runs` whole — for the card entry too.
- `started` calls `store.requestSnapshot([store.dispatchRoot])`, never `store.refresh()`; the `dispatchStartReplied` contract comment says so.
- A start in flight completes for its `madeFor`; when it is not `isHereStart`, no state change, no merge into either settings object, no `dispatchStarted`, no flash — but `set-run-settings madeFor …` is still written.
- `runSettingsRunner`, `projectSwitched`'s read of the open project's `runSettings`, and the control-request settings reads are not changed.
- No change to `core/domain/runs.js`, `ui/`, or any backend helper. No new `tst_runs.qml` or `tests/ui` test.
- Docstrings and comments state the contract only, with no narrative.
- Gate: `bash tests/run.sh` green (pytest incl. `tests/architecture`, then every QML test, no `TypeError`/`ReferenceError` lines).

## Review Focus

1. **B's settings reply lands after the dialog was closed, or reopened by a card entry on A.** Expect it dropped: the form stays A's (`old`, `uv run pytest`), `dispatchRunSettings` stays `{}`. Pinned in Task 2, `test_dispatch_settings_reply_keeps_user_edits_and_unreadable_is_empty` (the `late` and `reopened` cases).
2. **The user edits prefix and parallelism while B's settings read is pending.** Expect both edits kept, verify taken from B. Pinned in Task 2, same test (the `edited` case).
3. **B's settings reply is a traceback, a JSON array or empty.** Expect `dispatchRunSettings` `{}`, the form keeps the `{}` defaults, and the check still runs (here: refused on verify). Pinned in Task 2, same test (the unreadable loop).
4. **`dispatchRoot` is set to `project` and opened through `dispatchOpenFor` directly.** Expect the card-entry behaviour: no settings read, `runSettings` used, preview at once on the defaults reply. Pinned in Task 2, `test_dispatch_card_entry_launches_no_settings_read`.
5. **A dispatch for B starts, is closed, and B is opened again.** Expect B's settings read afresh (the merged `dispatchRunSettings` does not outlive the close). Pinned in Task 3, `test_dispatch_start_for_other_root_argv_save_and_refresh` (its tail).

## Decisions the spec leaves to the plan

- **Panel close and `dispatchRoot`.** `stopLive()` closes the dispatch through `closeDispatch()` (`RunStore.qml:387`), so a panel close that succeeds sets `dispatchRoot = ""`, matching the property's contract ("`""` while no dispatch has been opened since the last close"). `resetDispatch()` itself never touches `dispatchRoot`.
- **The touched-field record.** `dispatchBook.baseTouched` becomes `dispatchBook.touched`, a `{field name: true}` map of the fields `setDispatchField` set since the opening. The defaults reply reads `touched.base`; the settings reply reads `touched.prefix/verify/parallelism`.
- **Existing tests whose snapshot expectation changes.** None. Every existing dispatch test registers only `rootA` (`makeWithProject`/`activeStore`), so `requestSnapshot([rootA])` launches the same `snapCmd|rootA` as `refresh()` did (`test_start_ok_with_run_id_emits_and_saves`), and the tests asserting no snapshot (`test_start_result_belongs_to_its_project`, `test_retarget_from_a_blocked_start`) see none. `test_panel_close_closes_dispatch_but_not_a_start` and `test_start_in_other_project_does_not_stop_the_first` assert nothing about snapshots.
- **The one existing test that changes.** `test_story_prefix_reads_the_snapshot_then_the_keyed_map` sets `store.runs` with no `project` field. Filtering by root drops those runs, so its runs gain `project: { root: tc.rootA, name: "alpha" }` (Task 2, Step 1). Its assertions are unchanged.

---

## Spec (prepended, headings demoted one level)

## 2.1 RunStore dispatch: dispatchRoot drives every dispatch launch — design

Card: `abbba4c7` (subtask of story `8200b9d4`).
Parent design: `docs/superpowers/specs/2026-10-05-dispatch-from-runs-design.md`, cited below as
"DFR l.N". S3's store contract is `docs/architecture.md:92` ("Dispatch (S3 3.1)"), cited as
"ARCH l.92".

### Purpose

The Runs-screen dispatch (DFR l.21-25) dispatches for a project that need not be the open one.
Today every launch in S3's dispatch section (`core/stores/RunStore.qml:1434-1768`) carries
`store.project`. This card adds `dispatchRoot`, the project the dialog is for, and makes every
dispatch launch carry it instead. Card entry points set `dispatchRoot = project`, so card
dispatch behaves exactly as today. Nothing in the UI sets a different root yet: the project and
target steps (`dispatchStep`, `dispatchProjectPick`, `dispatchTargetPick`, DFR l.193) are a
later card. This card gives them one store entry, `dispatchOpenFor(card, cardMap)`, to open the
form for `dispatchRoot`.

### Inherited constraints

- `dispatchRoot` lives in S3's dispatch section, beside the form (DFR l.190-192). The members
  this card adds are prefixed `dispatch*`. They stay inside S3's delimited section
  (`// ---- dispatch (S3 3.1)`) so "Split RunStore" can lift it out whole (DFR l.185-188).
- Every dispatch launch (defaults, preview, start) and every run-settings launch the dispatch
  section makes (S3's `get-run-settings` read and `set-run-settings` save, S7's
  `prefixByMilestone` save) carries `dispatchRoot`, never `project` (DFR l.195-198; card).
- A card entry point sets `dispatchRoot = project` (DFR l.198; card). Card dispatch is
  unchanged (DFR l.29-30; card).
- The prefix default reads the runs whose `project.root` is the root, `Runs.filterByProject`
  (DFR l.99-101; card). The verify set, parallelism and the prefix map/history come from that
  root's run settings, and a start writes that root's run settings, never the open project's
  (DFR l.100-102, l.36-37).
- A launch in flight completes for the root it was started for, and its result names that root
  (DFR l.212-214; card).
- **Refresh on `started` — the card overrides the parent.** The card says: "started asks S6's
  per-root refresh for dispatchRoot only". DFR l.108-109 and l.214-215 (retargeted to the new
  `am`, DFR l.3-4) say one global refresh. The per-root path still exists
  (`requestSnapshot(roots)`, `RunStore.qml:246-264`, which the watch nudges and the liveness
  tick use). This card follows the card: `started` calls `requestSnapshot([dispatchRoot])`.
  The plan must state this choice in the `dispatchStartReplied` contract comment. A later card
  can collapse it to `refresh()` if the parent's rule wins.
- Layering per `docs/architecture.md`, and `tests/architecture` must pass. `bash tests/run.sh`
  must be green. Tests come first. Docstrings and comments state the contract only, with no
  narrative (card).

### Behaviour

#### `dispatchRoot`

`property string dispatchRoot: ""` is declared beside `dispatchState`/`dispatchForm`
(`RunStore.qml:173-186`) with a one-line contract comment: "the project root the dispatch is
for; every dispatch launch carries it; "" while no dispatch has been opened since the last
close or project switch".

- `resetDispatch()` does **not** change `dispatchRoot`. Opening a dispatch calls it first and
  must keep the root the opener just chose.
- `closeDispatch()`, when it succeeds, resets the dispatch and then sets `dispatchRoot = ""`.
  When it is refused (while `starting`), nothing changes.
- `projectSwitched()` resets the dispatch and sets `dispatchRoot = ""`. A dispatch opened from
  a card belongs to the project that was open. Keeping a Runs-opened dialog through a project
  switch is the later card's guard (DFR l.209-212) and is out of scope here.
- Closing the panel already goes through the dispatch reset (ARCH l.92). It leaves
  `dispatchRoot` as `resetDispatch` does. Nothing reads it while idle.

#### Entry points

- **`openDispatch(card, cardMap)`** is the card entry and keeps its contract (ARCH l.92). It
  refuses (returns false, changes nothing) when `project === ""` or while `starting`. Otherwise
  it sets `dispatchRoot = project` and returns `dispatchOpenFor(card, cardMap)`.
- **`dispatchOpenFor(card, cardMap)`** is new. It opens the form for the current
  `dispatchRoot` and does what `openDispatch` does today, with `project` replaced as listed
  below. It refuses (returns false, changes nothing) when `dispatchRoot === ""` or while
  `starting`. It is public, because the later `dispatchTargetPick` calls it and the store tests
  use it to dispatch for a root other than `project`.
- **`retargetToMilestone()`** reopens through `dispatchOpenFor` instead of `openDispatch`. It
  keeps `dispatchRoot`, so a blocked story in root B retargets to its milestone in root B. For
  a card entry, `dispatchRoot === project`, so behaviour is unchanged.

#### The dispatch's run settings

The dispatch's settings source is `runSettings` when `dispatchRoot === project`. Otherwise it is
a new property, `dispatchRunSettings`:

`property var dispatchRunSettings: ({})` holds dispatchRoot's `get-run-settings` object as read
by the dispatch, when `dispatchRoot !== project`. It is `{}` until its reply, when the reply is
unreadable, and after every reset. While it is in use, `runSettings` (the open project's) is
neither read nor written by the dispatch.

- **Same root (card entry).** No new launch. Defaults, history and the post-start merge use
  `runSettings` exactly as today (`RunStore.qml:1494`, `:1674`, `:1720-1727`).
  `dispatchRunSettings` stays `{}`.
- **Other root.** `dispatchOpenFor` launches `viewer-state.py get-run-settings <dispatchRoot>`
  on a new `HelperRunner`, `dispatchSettingsRunner` (latest wins, `guard: store.dispatchRoot`).
  It is exposed as `readonly property alias dispatchSettingsRunner` beside the other dispatch
  aliases. The read is launched together with the `--defaults` lookup. A target that is
  refused at once (`!plan.offered`) launches neither, as today.
  - The form opens at once from `Runs.dispatchDefaults` with `{}` settings, so `dispatchForm`
    is never null while `previewing`.
  - The form is not checked while the settings read is pending. `checkDispatch` waits for both
    the defaults lookup and the settings read. Whichever replies last triggers the check.
  - The settings reply sets `dispatchRunSettings` (an unreadable reply gives `{}`). It then
    recomputes `prefix`, `verify` and `parallelism` from
    `Runs.dispatchDefaults({defaultBranch: "", settings: dispatchRunSettings}, card, cardMap,
    filteredRuns)`. A field the user set through `setDispatchField` since the opening keeps the
    user's value. `base` and `allowNoVerification` are never touched by this reply. The reply
    is ignored unless the store is `previewing` with the settings read still pending, the same
    rule `dispatchDefaultsReplied` follows (`RunStore.qml:1566`).
  - `resetDispatch()` cancels `dispatchSettingsRunner`, clears the pending flag and the
    touched-field record, and sets `dispatchRunSettings = {}`.
- **History and save.** `dispatchStart()` takes the stored `prefixHistory` from the settings
  source. On a successful start that is this dispatch's, the saved values are merged into the
  settings source (`prefixByMilestone` per milestone id, as today), so `runSettings` changes
  only when `dispatchRoot === project`.

#### Launches (argv)

`B` is `dispatchRoot`. Every argv below differs from today only in `B`, where today it is
`project`.

| launch | argv (after `python3 <script>`) | runner, guard |
|---|---|---|
| defaults | `--defaults B` | `dispatchDefaultsRunner`, guard `store.dispatchRoot` (was `store.project`) |
| preview | `B TARGET [--base-branch X] --branch-prefix P --max-concurrent N [--verify C]... [--allow-no-verification]` | `dispatchPreviewRunner`, guard `store.dispatchRoot` (was `store.project`) |
| start | `B TARGET …same options` | its own `dispatchStartC` runner, guard `""`, `madeFor: B` |
| settings save | `set-run-settings B <savedJson>` | the same start runner (it already uses `madeFor`) |
| settings read (other root only) | `get-run-settings B` | `dispatchSettingsRunner`, guard `store.dispatchRoot` |

The prefix default passes `Runs.filterByProject(store.runs, B)` to `Runs.dispatchDefaults`,
not `store.runs`. This applies to the card entry too: since S6, `runs` merges every project, so
a run of another project with the same milestone id must not supply the prefix.

#### Launch guard and the result

- `isHereStart(runner)` is `runner.madeFor === store.dispatchRoot && dispatchBook.startRunner
  === runner`. Its comment names `dispatchRoot`.
- A start in flight completes for `madeFor`. If the dispatch was reset meanwhile (project
  switch, panel close after it left `starting`), the reply is not here. The state stays as it
  is, nothing is merged into either settings object, and `dispatchStarted` is not emitted.
  `set-run-settings madeFor …` is still written, as today. A save failure flashes only while
  `isHereStart` holds.
- On a successful start that is here: state `started`, `dispatchRunId`/`dispatchMessage` set,
  merge into the settings source, then `store.requestSnapshot([store.dispatchRoot])` replaces
  `store.refresh()`, then `dispatchStarted(id or null)`. `requestSnapshot` already folds into
  the pending request while a snapshot is in flight, and `launchSnapshot` drops a root that is
  not usable. That rule is unchanged: a root that left the registry gets no snapshot.
- The `dispatchStarted` signal comment reads "A start for `dispatchRoot` went: …".

#### Docs and comments

- `RunStore.qml` header (`:12-14`, `:32-34`): `project` decides the run settings. The dispatch
  is for `dispatchRoot`, which a card entry sets to `project`.
- `docs/architecture.md:92` (the Dispatch (S3 3.1) paragraph) gets the same facts:
  `dispatchRoot`, `dispatchOpenFor`, `dispatchRunSettings`/`dispatchSettingsRunner`,
  `ROOT` = `dispatchRoot` in every argv, the prefix runs filtered to the root, and `started`
  requesting a snapshot of `[dispatchRoot]`.

### Errors and edge cases

| case | behaviour |
|---|---|
| `dispatchOpenFor` with `dispatchRoot === ""` | false, nothing changes, nothing launched |
| `dispatchOpenFor` while `starting` | false, nothing changes |
| `openDispatch` with no project | false, `dispatchRoot` unchanged (stays `""`) |
| settings read for B unreadable / exit ≠ 0 | `dispatchRunSettings = {}`, form keeps the `{}` defaults, the check runs |
| settings or defaults reply after `dispatchRoot` changed | dropped by the runner guard |
| settings reply after the user edited prefix | prefix keeps the user's value; verify/parallelism take B's |
| start for B in flight, then project switch | not here: no state change, no merge, no signal, `set-run-settings B` still written, no flash |
| `started` while a snapshot is in flight | `[B]` joins the pending request (union, or stays `"all"`) |
| B not in the registry (`projectRoots`) | `started` launches no snapshot |

### Tests

Every test is in tier **QML store tests**, `tests/core/stores/tst_run_store.qml`, inside its
dispatch block (`// ---- dispatch (S3 3.1)`, from `:3880`). The behaviour is store state and
helper argv, which only the store harness (fake `Process`, `reply`, `argv`) observes. Domain
functions are unchanged, so no `tst_runs.qml` test is added. The UI is unchanged, so no
`tests/ui` test is added. New tests go after the existing dispatch tests and before the next
`// ----` header, so the split can move the block whole. A helper `otherRootStore()` gives
`projectRoots = [rootA, rootB]`, `project = rootA` with A's `runSettings` read, and
`dispatchRoot = rootB`.

New tests:

1. **`test_dispatch_root_starts_empty_and_card_entry_sets_project`**: fresh store `""`;
   `openDispatch` with no project refused and still `""`; with project A it is A after the
   opening; `closeDispatch()` gives `""`; a project switch gives `""`.
2. **`test_dispatch_open_for_refuses_without_a_root_or_while_starting`**: `dispatchOpenFor` with
   `""` returns false, idle, no runner current; while `starting` returns false, state stays.
3. **`test_dispatch_open_for_other_root_argv`**: `otherRootStore`, `dispatchOpenFor(m1)`.
   Defaults argv `--defaults|/home/u/b`; settings argv `viewerCmd + get-run-settings|/home/u/b`;
   `runSettingsRunner` not relaunched. After the defaults reply only, no preview yet (settings
   pending). After the settings reply (`{verify:["make test"], parallelism: 2, prefixHistory:
   ["bpre"]}`), the form has B's verify/parallelism/prefix and the preview argv starts
   `previewCmd + /home/u/b|milestone|m1|…`.
4. **`test_dispatch_settings_reply_keeps_user_edits_and_unreadable_is_empty`**: the prefix is
   edited before the settings reply, and that prefix is kept while verify takes B's. A separate
   run with an unreadable reply gives `dispatchRunSettings` `{}`, the form keeps the `{}`
   defaults, and the check runs.
5. **`test_dispatch_prefix_default_reads_only_the_roots_runs`**: `runs` holds a run of A and a
   run of B for milestone `m1` with different branch prefixes. Opening for B takes B's prefix,
   and a card entry (root A) takes A's.
6. **`test_dispatch_start_for_other_root_argv_save_and_refresh`**: ready for B, start. The
   start argv begins `startCmd + /home/u/b|`, and `madeFor` is B. After an ok reply: `started`,
   `dispatchStarted` emitted, snapshot argv `snapCmd|/home/u/b` only (A not listed),
   `set-run-settings|/home/u/b|…`, `dispatchRunSettings.prefixHistory[0]` is the sent prefix,
   and `runSettings` (A's) is unchanged.
7. **`test_dispatch_story_start_for_other_root_saves_prefix_by_milestone_for_it`**: a story
   start for B. The saved JSON carries `prefixByMilestone {m1: prefix}`, it is written with
   `set-run-settings|/home/u/b`, it is merged into `dispatchRunSettings`, and not into
   `runSettings`.
8. **`test_dispatch_start_in_flight_completes_for_its_root_after_a_switch`**: start for B, then
   `project = rootB`, so `dispatchRoot` is `""` and the store is idle. The ok reply is not
   here: idle, no signal, no snapshot, no merge. `set-run-settings|/home/u/b|…` is still
   written, and a failing save does not flash.
9. **`test_dispatch_retarget_keeps_the_root`**: story `s1` for B, preview refused with
   `StoryBlockedError`, `retargetToMilestone()`. `dispatchRoot` is still B and the new
   defaults argv is `--defaults|/home/u/b`.
10. **`test_dispatch_card_entry_launches_no_settings_read`**: card entry on A.
    `dispatchSettingsRunner.current` is unset, `dispatchRunSettings` is `{}`, and the form
    reads A's `runSettings` (prefix `old`, verify `uv run pytest`) as today.

Existing tests that change (only their snapshot expectation, because `started` now requests
`[dispatchRoot]`): any that registers more than one root and asserts the global argv after
`started` gets `snapCmd|<dispatchRoot>`. Those that register only A
(`tst_run_store.qml:4479-4509` and its siblings) keep `snapCmd|rootA`. While a snapshot is in
flight, the expectation is `pendingSnapshot` = `[rootA]` instead of `"all"`. The plan must list
each changed assertion. Every other existing dispatch test (card entry) must pass unchanged.
That is the "card entry unchanged" proof.

### Out of scope

- `dispatchStep`, `dispatchOpenFromRuns`, `dispatchBack`, the project probe, the target tree
  runner, `dispatchProjectPick`, `dispatchTargetPick`, and the guard that keeps a Runs-opened
  dialog through a project switch (DFR l.193, l.200-212): later cards in this story.
- DispatchDialog, RunsScreen, Shortcuts, Panel (DFR l.219-226).
- `start-run.py` run-id discovery (DFR l.163-172) and `board-tree.py`.
- Any change to `runSettingsRunner` / `projectSwitched`'s read of the open project's
  `runSettings`, and to control-request settings reads.

---

## File Structure

| file | change | responsibility |
|---|---|---|
| `core/stores/RunStore.qml` | modify | `dispatchRoot`, `dispatchRunSettings`, `dispatchSettingsRunner`, `dispatchOpenFor`, `dispatchSettingsSource`, `dispatchDefaultsFor`, `dispatchSettingsReplied`; every dispatch launch carries `dispatchRoot`; header and contract comments |
| `tests/core/stores/tst_run_store.qml` | modify | 11 new store tests under a new `// ---- dispatch: dispatchRoot (2.1 RunStore dispatch)` header placed after `test_a_late_blocked_start_reply_changes_nothing` and before `// ---- list snapshots`; one existing test's runs gain a `project` |
| `docs/architecture.md` | modify | line 92, the Dispatch (S3 3.1) paragraph |

Commands used throughout (run from the worktree root):

- One or more store tests:
  `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::<test_a> StoresRunStore::<test_b>`
- The whole store file: the same command with no `StoresRunStore::…` arguments. It ends with `Totals: N passed, 0 failed, …`. Before this plan N is 304.
- The full gate: `timeout 900 bash tests/run.sh` (about 2-3 minutes; pytest first, then every QML file).

Test helpers that already exist in `tests/core/stores/tst_run_store.qml` and are used below: `make()`, `registry(roots)`, `reply(proc, text, code)`, `argv(proc)`, `fire(timer)`, `okReply(entries)`, `allReply(projects)`, `okEntry(root, runs)`, `ctlFail(type, message)`, `dispatchSettings()` (A's settings: verify `uv run pytest`, prefixHistory `["old"]`, parallelism 4, confirmDispatch true), `dispatchCards()` (`m1` "M3 Document runs", its story `s1`, subtask `t1`, done milestone `d1`), `dispatchStore()` (project A registered alone, its settings read; its first snapshot in flight), `checkDispatchIdle(store, label)`, `defaultsOk(branch)`, `previewOk(data)`, `dispatchDryRun()`, `storyDryRun()`, `startOk(runId, message)`, `readyStore()` (A, milestone m1 ready), `spyC`, and the properties `tc.rootA` (`/home/u/my proj`), `tc.rootB` (`/home/u/b`), `tc.previewCmd`, `tc.startCmd`, `tc.viewerCmd`, `tc.snapCmd`, `tc.previewArgs`, `tc.blockedMessage`.

---

### Task 1: `dispatchRoot` and the entry points

**Files:**
- Modify: `core/stores/RunStore.qml:166-173` (dispatch property block), `:649-662` (`projectSwitched`), `:1468-1509` (`openDispatch`, `closeDispatch`), `:1576-1592` (`checkDispatch`), `:1594-1600` (`dispatchPreviewReplied` comment), `:1818-1833` (the defaults and preview runners)
- Test: `tests/core/stores/tst_run_store.qml` (new header and tests after `test_a_late_blocked_start_reply_changes_nothing`, before `  // ---- list snapshots`, currently line 5243)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `property string dispatchRoot` (writable; tests assign it directly).
  - `function dispatchOpenFor(card, cardMap) -> bool` — opens the dispatch for the current `dispatchRoot`; refuses (`false`, nothing changes) when `dispatchRoot === ""` or `dispatchState === "starting"`.
  - `function openDispatch(card, cardMap) -> bool` — refuses when `project === ""` or while `starting`; else `dispatchRoot = project`, returns `dispatchOpenFor(card, cardMap)`.
  - `closeDispatch()` sets `dispatchRoot = ""` when it succeeds; `projectSwitched()` sets `dispatchRoot = ""`.
  - `dispatchDefaultsRunner` and `dispatchPreviewRunner` are guarded by `store.dispatchRoot`; their argv carry `dispatchRoot`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_store.qml`, find the end of `test_a_late_blocked_start_reply_changes_nothing` (the line `    compare(back.dispatchTargetLabel, 'Milestone "M3 Document runs"')` followed by `  }`), and insert after that closing `  }` and before the blank line + `  // ---- list snapshots`:

```qml

  // ---- dispatch: dispatchRoot (2.1 RunStore dispatch)

  // 2.1 RunStore dispatch test 1
  function test_dispatch_root_starts_empty_and_card_entry_sets_project() {
    var fresh = make(); if (!fresh) return
    compare(fresh.dispatchRoot, "", "fresh")
    var cards = dispatchCards()
    compare(fresh.openDispatch(cards.m1, cards), false, "no project")
    compare(fresh.dispatchRoot, "", "a refused card entry sets no root")

    var store = dispatchStore(); if (!store) return
    compare(store.dispatchRoot, "", "opening a project opens no dispatch")
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchRoot, tc.rootA, "a card entry dispatches for the open project")
    compare(store.closeDispatch(), true)
    compare(store.dispatchRoot, "", "closed")
    checkDispatchIdle(store, "closed")
    compare(store.openDispatch(cards.m1, cards), true)
    store.project = tc.rootB
    compare(store.dispatchRoot, "", "a project switch forgets the root")
    checkDispatchIdle(store, "switched")

    var starting = readyStore(); if (!starting) return
    compare(starting.dispatchStart(), true)
    compare(starting.closeDispatch(), false)
    compare(starting.dispatchRoot, tc.rootA, "a refused close keeps the root")
    compare(starting.openDispatch(cards.t1, cards), false)
    compare(starting.dispatchRoot, tc.rootA, "a refused card entry keeps the root")
  }

  // 2.1 RunStore dispatch test 2
  function test_dispatch_open_for_refuses_without_a_root_or_while_starting() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.dispatchOpenFor(cards.m1, cards), false, "no root")
    checkDispatchIdle(store, "no root")
    verify(!store.dispatchDefaultsRunner.current, "nothing launched")

    var starting = readyStore(); if (!starting) return
    starting.dispatchStart()
    compare(starting.dispatchOpenFor(cards.t1, cards), false, "starting")
    compare(starting.dispatchState, "starting")
    compare(starting.dispatchTarget.level, "milestone")
    compare(starting.dispatchRoot, tc.rootA)
  }

  // 2.1 RunStore dispatch: the defaults lookup and a refused target for another root
  function test_dispatch_open_for_launches_for_the_root() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.dispatchRoot = tc.rootB
    compare(store.dispatchOpenFor(cards.m1, cards), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchRoot, tc.rootB, "the opening keeps the root")
    compare(store.project, tc.rootA)
    var lookup = store.dispatchDefaultsRunner.current
    verify(lookup, "the default branch is looked up")
    compare(argv(lookup), tc.previewCmd + "--defaults|/home/u/b")
    compare(lookup.launchGuard, "/home/u/b")
    compare(store.dispatchPreviewRunner.guard, "/home/u/b")

    var refused = dispatchStore(); if (!refused) return
    refused.dispatchRoot = tc.rootB
    compare(refused.dispatchOpenFor(cards.d1, cards), false)
    compare(refused.dispatchState, "refused")
    compare(refused.dispatchErrorType, "Target")
    compare(refused.dispatchRoot, tc.rootB)
    verify(!refused.dispatchDefaultsRunner.current, "a refused target launches nothing")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_dispatch_root_starts_empty_and_card_entry_sets_project StoresRunStore::test_dispatch_open_for_refuses_without_a_root_or_while_starting StoresRunStore::test_dispatch_open_for_launches_for_the_root`
Expected: 3 FAIL — the first with `Compared values are not the same` (`undefined` vs `""` for `dispatchRoot`), the other two with `TypeError: Property 'dispatchOpenFor' of object … is not a function`.

- [ ] **Step 3: Add `dispatchRoot` beside `dispatchState`**

In `core/stores/RunStore.qml` replace:

```qml
  // Dispatch (S3 3.1): starting an am run. The UI opens it for a target
  // (openDispatch), edits the form (setDispatchField) and presses Start
  // (dispatchStart); the store checks the form, previews it with
  // dispatch-preview.py and starts it with start-run.py. `dispatchState` is
  // idle | previewing | ready | refused | starting | started | failed. Every
  // object here is replaced, never changed in place.
  property string dispatchState: "idle"
```

with:

```qml
  // Dispatch (S3 3.1): starting an am run for dispatchRoot. The UI opens it
  // for a target (openDispatch for a card of the open project,
  // dispatchOpenFor for the current dispatchRoot), edits the form
  // (setDispatchField) and presses Start (dispatchStart); the store checks
  // the form, previews it with dispatch-preview.py and starts it with
  // start-run.py. `dispatchState` is idle | previewing | ready | refused |
  // starting | started | failed. Every object here is replaced, never
  // changed in place.
  property string dispatchState: "idle"
  // The project root the dispatch is for; every dispatch launch carries it;
  // "" while no dispatch has been opened since the last close or project switch.
  property string dispatchRoot: ""
```

- [ ] **Step 4: A project switch forgets the root**

Replace:

```qml
  // project and stay, and no snapshot is launched. Reset: the run settings
  // (loaded for the new project on runSettingsRunner) and the dispatch.
  function projectSwitched() {
    store.runSettings = {}
    // The dispatch is the old project's, even mid-start: a start already
    // launched still runs, and its reply is no longer this dispatch's.
    store.resetDispatch()
    runSettingsRunner.guard = store.project
```

with:

```qml
  // project and stay, and no snapshot is launched. Reset: the run settings
  // (loaded for the new project on runSettingsRunner), the dispatch and
  // dispatchRoot ("").
  function projectSwitched() {
    store.runSettings = {}
    // The dispatch is the old project's, even mid-start: a start already
    // launched still runs, and its reply is no longer this dispatch's.
    store.resetDispatch()
    store.dispatchRoot = ""
    runSettingsRunner.guard = store.project
```

- [ ] **Step 5: Split `openDispatch` into the card entry and `dispatchOpenFor`; `closeDispatch` clears the root**

Replace the whole block from `  // Opens the dispatch for a brd card (as Board.indexTree() leaves it) or` through the end of `closeDispatch()`:

```qml
  // Opens the dispatch for a brd card (as Board.indexTree() leaves it) or
  // "board", with its {id: card} map, and returns whether it may be started.
  // Refused (false, nothing changes) without a project or while a start is in
  // flight. Every opening sets dispatchTargetLabel and records cardMap and
  // cardMap's entry for the target's milestone (Runs.dispatchMilestone), or
  // null. A target dispatchPlan does not offer is `refused` at once; any
  // other starts from dispatchDefaults with this project's runSettings and
  // the Runs snapshot, and looks up the default branch before anything is
  // checked.
  function openDispatch(card, cardMap) {
    if (store.project === "" || store.dispatchState === "starting") return false
    store.resetDispatch()
    var plan = Runs.dispatchPlan(card, cardMap)
    var milestone = Runs.dispatchMilestone(card, cardMap)
    var isMap = cardMap !== null && typeof cardMap === "object"
    dispatchBook.cardMap = cardMap
    dispatchBook.milestone = milestone !== null && isMap && store.hasKey(cardMap, milestone.id) ? cardMap[milestone.id] : null
    store.dispatchTarget = plan
    store.dispatchTargetLabel = Runs.dispatchLabel(card, cardMap)
    if (!plan.offered) {
      store.dispatchState = "refused"
      store.dispatchError = plan.reason
      store.dispatchErrorType = "Target"
      return false
    }
    var d = Runs.dispatchDefaults({ defaultBranch: "", settings: store.runSettings }, card, cardMap, store.runs)
    store.dispatchForm = { base: d.base, prefix: d.prefix, verify: d.verify, parallelism: d.parallelism,
                           allowNoVerification: d.allowNoVerification }
    store.dispatchState = "previewing"
    dispatchBook.defaultsPending = true
    dispatchDefaultsRunner.run(["--defaults", store.project])
    return true
  }

  // Back to idle. Refused while a start is in flight: its outcome must land in
  // a dialog that still shows what was started.
  function closeDispatch() {
    if (store.dispatchState === "starting") return false
    store.resetDispatch()
    return true
  }
```

with:

```qml
  // The card entry: opens the dispatch for the open project (dispatchRoot =
  // project) and returns dispatchOpenFor's result. Refused (false, nothing
  // changes) without a project or while a start is in flight.
  function openDispatch(card, cardMap) {
    if (store.project === "" || store.dispatchState === "starting") return false
    store.dispatchRoot = store.project
    return store.dispatchOpenFor(card, cardMap)
  }

  // Opens the dispatch for dispatchRoot on a brd card (as Board.indexTree()
  // leaves it) or "board", with its {id: card} map, and returns whether it
  // may be started. Refused (false, nothing changes) without a dispatchRoot
  // or while a start is in flight. Every opening sets dispatchTargetLabel
  // and records cardMap and cardMap's entry for the target's milestone
  // (Runs.dispatchMilestone), or null. A target dispatchPlan does not offer
  // is `refused` at once and launches nothing; any other starts from
  // dispatchDefaults with runSettings and the Runs snapshot, and looks up
  // dispatchRoot's default branch before anything is checked.
  function dispatchOpenFor(card, cardMap) {
    if (store.dispatchRoot === "" || store.dispatchState === "starting") return false
    store.resetDispatch()
    var plan = Runs.dispatchPlan(card, cardMap)
    var milestone = Runs.dispatchMilestone(card, cardMap)
    var isMap = cardMap !== null && typeof cardMap === "object"
    dispatchBook.cardMap = cardMap
    dispatchBook.milestone = milestone !== null && isMap && store.hasKey(cardMap, milestone.id) ? cardMap[milestone.id] : null
    store.dispatchTarget = plan
    store.dispatchTargetLabel = Runs.dispatchLabel(card, cardMap)
    if (!plan.offered) {
      store.dispatchState = "refused"
      store.dispatchError = plan.reason
      store.dispatchErrorType = "Target"
      return false
    }
    var d = Runs.dispatchDefaults({ defaultBranch: "", settings: store.runSettings }, card, cardMap, store.runs)
    store.dispatchForm = { base: d.base, prefix: d.prefix, verify: d.verify, parallelism: d.parallelism,
                           allowNoVerification: d.allowNoVerification }
    store.dispatchState = "previewing"
    dispatchBook.defaultsPending = true
    dispatchDefaultsRunner.run(["--defaults", store.dispatchRoot])
    return true
  }

  // Back to idle, and dispatchRoot back to "". Refused (false, nothing
  // changes) while a start is in flight: its outcome must land in a dialog
  // that still shows what was started.
  function closeDispatch() {
    if (store.dispatchState === "starting") return false
    store.resetDispatch()
    store.dispatchRoot = ""
    return true
  }
```

(`settings: store.runSettings` and `store.runs` stay for now; Task 2 replaces them.)

- [ ] **Step 6: The preview carries `dispatchRoot`**

In `checkDispatch()` replace:

```qml
    dispatchPreviewRunner.run([store.project].concat(store.dispatchTargetArgs(), store.dispatchOptionArgs()))
```

with:

```qml
    dispatchPreviewRunner.run([store.dispatchRoot].concat(store.dispatchTargetArgs(), store.dispatchOptionArgs()))
```

and in the comment above `dispatchPreviewReplied` replace:

```qml
  // The newest preview's reply for this project and these values (a form
```

with:

```qml
  // The newest preview's reply for this dispatchRoot and these values (a form
```

- [ ] **Step 7: The defaults and preview runners are guarded by `dispatchRoot`**

Replace:

```qml
  // dispatch-preview.py --defaults, once per opening. Guarded by the project:
  // a reply for a project the user has left is dropped.
  HelperRunner {
    id: dispatchDefaultsRunner
    script: store.backendDir + "runs/dispatch-preview.py"
    guard: store.project
    onFinished: function(stdout, exitCode) { store.dispatchDefaultsReplied(stdout) }
  }

  // The dispatch preview; latest wins, and every form change cancels it.
  HelperRunner {
    id: dispatchPreviewRunner
    script: store.backendDir + "runs/dispatch-preview.py"
    guard: store.project
    onFinished: function(stdout, exitCode) { store.dispatchPreviewReplied(stdout) }
  }
```

with:

```qml
  // dispatch-preview.py --defaults, once per opening. Guarded by
  // dispatchRoot: a reply for a root the dispatch has left is dropped.
  HelperRunner {
    id: dispatchDefaultsRunner
    script: store.backendDir + "runs/dispatch-preview.py"
    guard: store.dispatchRoot
    onFinished: function(stdout, exitCode) { store.dispatchDefaultsReplied(stdout) }
  }

  // The dispatch preview; latest wins, and every form change cancels it.
  // Guarded by dispatchRoot.
  HelperRunner {
    id: dispatchPreviewRunner
    script: store.backendDir + "runs/dispatch-preview.py"
    guard: store.dispatchRoot
    onFinished: function(stdout, exitCode) { store.dispatchPreviewReplied(stdout) }
  }
```

- [ ] **Step 8: Run the new tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_dispatch_root_starts_empty_and_card_entry_sets_project StoresRunStore::test_dispatch_open_for_refuses_without_a_root_or_while_starting StoresRunStore::test_dispatch_open_for_launches_for_the_root`
Expected: 3 PASS (plus initTestCase/cleanupTestCase), `0 failed`.

- [ ] **Step 9: Run the whole store file (card entry unchanged)**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: `Totals: 307 passed, 0 failed, …` and no `FAIL`/`TypeError`/`ReferenceError` lines.

- [ ] **Step 10: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): dispatchRoot is the root every dispatch opening and preview carries"
```

---

### Task 2: Another root's run settings and runs drive its form

**Files:**
- Modify: `core/stores/RunStore.qml` — the dispatch property block (after `dispatchRoot`), the alias block (after `dispatchPreviewRunner`'s alias, `:215`), `resetDispatch` (`:1447-1468`), `dispatchOpenFor` (from Task 1), `retargetToMilestone` (`:1518-1526`), `dispatchDefaultsReplied` (`:1560-1572`), `checkDispatch` (`:1574-1592`), `setDispatchField` (`:1623-1642`), the runners (after `dispatchPreviewRunner`), `dispatchBook` (`:1955-1969`)
- Test: `tests/core/stores/tst_run_store.qml` — `test_story_prefix_reads_the_snapshot_then_the_keyed_map` (`:4819-4837`), and new tests appended after Task 1's tests (before `  // ---- list snapshots`)

**Interfaces:**
- Consumes (Task 1): `dispatchRoot`, `dispatchOpenFor(card, cardMap) -> bool`, `openDispatch`, `closeDispatch` clearing `dispatchRoot`.
- Produces:
  - `property var dispatchRunSettings` — `{}` until its reply, when unreadable, after every reset.
  - `readonly property alias dispatchSettingsRunner` — the `HelperRunner` running `viewer-state.py get-run-settings <dispatchRoot>`, guard `store.dispatchRoot`.
  - `function dispatchSettingsSource() -> object` — `runSettings` when `dispatchRoot === project`, else `dispatchRunSettings`. Task 3 reads and merges through it.
  - `function dispatchDefaultsFor(settings) -> {base, prefix, verify, parallelism, allowNoVerification}` — `Runs.dispatchDefaults` for the opened card with `settings` and `Runs.filterByProject(store.runs, store.dispatchRoot)`.
  - `function dispatchSettingsReplied(stdout)`.
  - `dispatchBook.card`, `dispatchBook.touched` (`{field: true}`), `dispatchBook.settingsPending`; `dispatchBook.baseTouched` is removed.
  - Test helpers used by Task 3: `otherRootStore()`, `bSettings()`, `readyForB(store)`, `tc.bPreviewArgs`.

- [ ] **Step 1: Give the existing prefix test's runs their project**

`test_story_prefix_reads_the_snapshot_then_the_keyed_map` sets runs with no `project`; once the prefix reads only the root's runs, they must name root A. Replace:

```qml
    store.runs = [{ id: "r-old", milestone_id: "m1", branch_prefix: "m3-old", started_at: "2026-10-01T00:00:00Z" },
                  { id: "r-live", milestone_id: "m1", branch_prefix: " m3-live ", started_at: "2026-10-06T00:00:00Z" },
                  { id: "r-other", milestone_id: "m2", branch_prefix: "m2-x", started_at: "2026-10-07T00:00:00Z" }]
```

with:

```qml
    var a = { root: tc.rootA, name: "alpha" }
    store.runs = [{ id: "r-old", milestone_id: "m1", branch_prefix: "m3-old", started_at: "2026-10-01T00:00:00Z", project: a },
                  { id: "r-live", milestone_id: "m1", branch_prefix: " m3-live ", started_at: "2026-10-06T00:00:00Z", project: a },
                  { id: "r-other", milestone_id: "m2", branch_prefix: "m2-x", started_at: "2026-10-07T00:00:00Z", project: a }]
```

- [ ] **Step 2: Write the failing tests**

Append after `test_dispatch_open_for_launches_for_the_root` (Task 1), still before `  // ---- list snapshots`:

```qml

  // Projects A and B registered (their snapshot in flight), A open with its
  // settings read (dispatchSettings), and the dispatch's root set to B.
  function otherRootStore() {
    var store = make(); if (!store) return null
    store.projectRoots = registry([tc.rootA, tc.rootB])
    store.project = tc.rootA
    reply(store.runSettingsRunner.current, dispatchSettings(), 0)
    store.dispatchRoot = tc.rootB
    return store
  }

  // B's get-run-settings: differs from A's in every value the form reads.
  function bSettings() {
    return JSON.stringify({ verify: ["make test"], parallelism: 2, prefixHistory: ["bpre", "bold"], confirmDispatch: false }) + "\n"
  }

  property string bPreviewArgs: "/home/u/b|milestone|m1|--base-branch|main|--branch-prefix|bpre|--max-concurrent|2|--verify|make test"

  // Opens milestone m1 for the store's dispatchRoot (B) and lands the
  // defaults (main), B's settings (bSettings) and the preview: Start is allowed.
  function readyForB(store) {
    var cards = dispatchCards()
    store.dispatchOpenFor(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchSettingsRunner.current, bSettings(), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
  }

  // 2.1 RunStore dispatch test 3
  function test_dispatch_open_for_other_root_argv() {
    var store = otherRootStore(); if (!store) return
    var aLoad = store.runSettingsRunner.current
    var cards = dispatchCards()
    compare(store.dispatchOpenFor(cards.m1, cards), true)
    compare(store.dispatchState, "previewing")
    var lookup = store.dispatchDefaultsRunner.current
    compare(argv(lookup), tc.previewCmd + "--defaults|/home/u/b")
    var read = store.dispatchSettingsRunner.current
    verify(read, "B's run settings are read")
    compare(argv(read), tc.viewerCmd + "get-run-settings|/home/u/b")
    compare(read.command.length, 4)
    compare(read.launchGuard, "/home/u/b")
    verify(store.runSettingsRunner.current === aLoad, "A's run settings are not read again")
    compare(Object.keys(store.dispatchRunSettings).length, 0, "{} until the reply")
    compare(store.dispatchForm.verify.length, 0, "the form opens from {} settings")
    compare(store.dispatchForm.parallelism, 4)
    compare(store.dispatchForm.prefix, "m3", "the milestone's stem")
    reply(lookup, defaultsOk("main"), 0)
    compare(store.dispatchForm.base, "main")
    compare(store.dispatchState, "previewing")
    verify(!store.dispatchPreviewRunner.current, "no preview while B's settings are pending")
    reply(read, bSettings(), 0)
    compare(store.dispatchRunSettings.prefixHistory[0], "bpre")
    compare(store.dispatchRunSettings.confirmDispatch, false, "the object is kept as it was read")
    compare(store.dispatchForm.verify.join(","), "make test")
    compare(store.dispatchForm.parallelism, 2)
    compare(store.dispatchForm.prefix, "bpre")
    compare(store.dispatchForm.base, "main", "base is not touched by the settings reply")
    compare(store.dispatchForm.allowNoVerification, false)
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "the last reply checks the form")
    compare(argv(proc), tc.previewCmd + tc.bPreviewArgs)
    compare(proc.launchGuard, "/home/u/b")
    compare(store.runSettings.prefixHistory[0], "old", "A's settings are untouched")
    compare(store.runSettings.verify[0], "uv run pytest")

    var settingsFirst = otherRootStore(); if (!settingsFirst) return
    settingsFirst.dispatchOpenFor(cards.m1, cards)
    reply(settingsFirst.dispatchSettingsRunner.current, bSettings(), 0)
    verify(!settingsFirst.dispatchPreviewRunner.current, "no preview while the defaults are pending")
    reply(settingsFirst.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(argv(settingsFirst.dispatchPreviewRunner.current), tc.previewCmd + tc.bPreviewArgs, "whichever replies last checks")

    var refused = otherRootStore(); if (!refused) return
    compare(refused.dispatchOpenFor(cards.d1, cards), false)
    verify(!refused.dispatchDefaultsRunner.current, "a refused target: no defaults lookup")
    verify(!refused.dispatchSettingsRunner.current, "a refused target: no settings read")
  }

  // 2.1 RunStore dispatch test 4 + Review Focus 1, 2 and 3
  function test_dispatch_settings_reply_keeps_user_edits_and_unreadable_is_empty() {
    var cards = dispatchCards()
    var edited = otherRootStore(); if (!edited) return
    edited.dispatchOpenFor(cards.m1, cards)
    compare(edited.setDispatchField("prefix", "mine"), true)
    compare(edited.setDispatchField("parallelism", 3), true)
    reply(edited.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    fire(edited.dispatchDebounceTimer)
    verify(!edited.dispatchPreviewRunner.current, "the debounced check waits for B's settings")
    reply(edited.dispatchSettingsRunner.current, bSettings(), 0)
    compare(edited.dispatchForm.prefix, "mine", "the user's prefix is kept")
    compare(edited.dispatchForm.parallelism, 3, "the user's parallelism is kept")
    compare(edited.dispatchForm.verify.join(","), "make test", "verify takes B's")
    compare(argv(edited.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/b|milestone|m1|--base-branch|main|--branch-prefix|mine|--max-concurrent|3|--verify|make test")

    var replies = ["Traceback: boom\n", "[1, 2]\n", ""]
    for (var i = 0; i < replies.length; i++) {
      var bad = otherRootStore(); if (!bad) return
      bad.dispatchOpenFor(cards.m1, cards)
      reply(bad.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
      reply(bad.dispatchSettingsRunner.current, replies[i], 1)
      compare(Object.keys(bad.dispatchRunSettings).length, 0, "reply " + i + ": unreadable is {}")
      compare(bad.dispatchForm.prefix, "m3", "reply " + i + ": the {} defaults stay")
      compare(bad.dispatchForm.parallelism, 4, "reply " + i)
      compare(bad.dispatchForm.verify.length, 0, "reply " + i)
      compare(bad.dispatchState, "refused", "reply " + i + ": the check ran")
      compare(bad.dispatchErrors[0].field, "verify", "reply " + i)
    }

    var late = otherRootStore(); if (!late) return
    late.dispatchOpenFor(cards.m1, cards)
    var lateRead = late.dispatchSettingsRunner.current
    compare(late.closeDispatch(), true)
    reply(lateRead, bSettings(), 0)
    checkDispatchIdle(late, "a settings reply after the close")
    compare(Object.keys(late.dispatchRunSettings).length, 0, "nothing kept after the close")

    var reopened = otherRootStore(); if (!reopened) return
    reopened.dispatchOpenFor(cards.m1, cards)
    var bRead = reopened.dispatchSettingsRunner.current
    compare(reopened.openDispatch(cards.m1, cards), true)
    compare(reopened.dispatchRoot, tc.rootA)
    reply(bRead, bSettings(), 0)
    compare(Object.keys(reopened.dispatchRunSettings).length, 0, "B's late reply is dropped")
    compare(reopened.dispatchForm.prefix, "old", "A's form stays")
    compare(reopened.dispatchForm.verify.join(","), "uv run pytest")
    compare(reopened.dispatchForm.parallelism, 4)
  }

  // 2.1 RunStore dispatch test 5
  function test_dispatch_prefix_default_reads_only_the_roots_runs() {
    var store = otherRootStore(); if (!store) return
    var cards = dispatchCards()
    var a = { root: tc.rootA, name: "alpha" }
    var b = { root: tc.rootB, name: "beta" }
    store.runs = [{ id: "r-a", milestone_id: "m1", branch_prefix: "a-pre", started_at: "2026-10-07T00:00:00Z", project: a },
                  { id: "r-b", milestone_id: "m1", branch_prefix: "b-pre", started_at: "2026-10-06T00:00:00Z", project: b }]
    store.dispatchOpenFor(cards.s1, cards)
    compare(store.dispatchForm.prefix, "b-pre", "A's newer run of m1 does not supply B's prefix")
    reply(store.dispatchSettingsRunner.current, bSettings(), 0)
    compare(store.dispatchForm.prefix, "b-pre", "B's run still beats B's history")

    compare(store.closeDispatch(), true)
    store.runs = [{ id: "r-a", milestone_id: "m1", branch_prefix: "a-pre", started_at: "2026-10-06T00:00:00Z", project: a },
                  { id: "r-b", milestone_id: "m1", branch_prefix: "b-pre", started_at: "2026-10-07T00:00:00Z", project: b }]
    compare(store.openDispatch(cards.s1, cards), true)
    compare(store.dispatchRoot, tc.rootA)
    compare(store.dispatchForm.prefix, "a-pre", "a card entry reads only the open project's runs")
  }

  // 2.1 RunStore dispatch test 9
  function test_dispatch_retarget_keeps_the_root() {
    var store = otherRootStore(); if (!store) return
    var cards = dispatchCards()
    store.dispatchOpenFor(cards.s1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchSettingsRunner.current, bSettings(), 0)
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/b|story|s1|--base-branch|main|--branch-prefix|bpre|--max-concurrent|2|--verify|make test")
    reply(store.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    compare(store.dispatchState, "refused")
    compare(JSON.stringify(store.dispatchSuggest), '{"id":"m1","title":"M3 Document runs"}')
    var storyRead = store.dispatchSettingsRunner.current
    compare(store.retargetToMilestone(), true)
    compare(store.dispatchRoot, tc.rootB, "the retarget keeps the root")
    compare(store.dispatchTarget.level, "milestone")
    compare(argv(store.dispatchDefaultsRunner.current), tc.previewCmd + "--defaults|/home/u/b")
    verify(store.dispatchSettingsRunner.current !== storyRead, "B's settings are read afresh")
    compare(argv(store.dispatchSettingsRunner.current), tc.viewerCmd + "get-run-settings|/home/u/b")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchSettingsRunner.current, bSettings(), 0)
    compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.bPreviewArgs, "B's milestone is previewed")
  }

  // 2.1 RunStore dispatch test 10 + Review Focus 4
  function test_dispatch_card_entry_launches_no_settings_read() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    verify(!store.dispatchSettingsRunner.current, "the open project's runSettings are used")
    compare(Object.keys(store.dispatchRunSettings).length, 0)
    compare(store.dispatchForm.prefix, "old")
    compare(store.dispatchForm.verify.join(","), "uv run pytest")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.previewArgs, "previewed on the defaults reply")

    var both = otherRootStore(); if (!both) return
    compare(both.openDispatch(cards.m1, cards), true)
    compare(both.dispatchRoot, tc.rootA, "the card entry replaces a root set before")
    verify(!both.dispatchSettingsRunner.current, "no settings read for the open project")

    var same = dispatchStore(); if (!same) return
    same.dispatchRoot = tc.rootA
    compare(same.dispatchOpenFor(cards.m1, cards), true)
    verify(!same.dispatchSettingsRunner.current, "dispatchOpenFor on the open project reads no settings")
    compare(same.dispatchForm.verify.join(","), "uv run pytest")
    reply(same.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(argv(same.dispatchPreviewRunner.current), tc.previewCmd + tc.previewArgs)
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_dispatch_open_for_other_root_argv StoresRunStore::test_dispatch_settings_reply_keeps_user_edits_and_unreadable_is_empty StoresRunStore::test_dispatch_prefix_default_reads_only_the_roots_runs StoresRunStore::test_dispatch_retarget_keeps_the_root StoresRunStore::test_dispatch_card_entry_launches_no_settings_read StoresRunStore::test_story_prefix_reads_the_snapshot_then_the_keyed_map`
Expected: the five new tests FAIL — `test_dispatch_prefix_default_reads_only_the_roots_runs` with `A's newer run of m1 does not supply B's prefix` (`a-pre` vs `b-pre`), `test_dispatch_settings_reply_keeps_user_edits_and_unreadable_is_empty` with `'the debounced check waits for B's settings' returned FALSE`, the other three with `Uncaught exception: Cannot read property 'current' of undefined` (no `dispatchSettingsRunner`). `test_story_prefix_reads_the_snapshot_then_the_keyed_map` PASSES (Step 1 changes no assertion).

- [ ] **Step 4: Add `dispatchRunSettings` and the runner alias**

In `core/stores/RunStore.qml`, directly after the `dispatchRoot` property added in Task 1:

```qml
  property string dispatchRoot: ""
```

insert:

```qml
  // dispatchRoot's get-run-settings object as the dispatch read it, while
  // dispatchRoot is not `project`: {} until its reply, when the reply is
  // unreadable, and after every reset.
  property var dispatchRunSettings: ({})
```

Then replace:

```qml
  readonly property alias dispatchPreviewRunner: dispatchPreviewRunner
```

with:

```qml
  readonly property alias dispatchPreviewRunner: dispatchPreviewRunner
  readonly property alias dispatchSettingsRunner: dispatchSettingsRunner
```

- [ ] **Step 5: `resetDispatch` drops the settings read and the touched fields**

Replace the whole `resetDispatch` with its comment:

```qml
  // Every dispatch field back to its "none" value; runSettings stays. The
  // pending check, the preview and the defaults lookup are dropped; a start
  // already launched runs on, but its reply is no longer this dispatch's.
  function resetDispatch() {
    dispatchDebounceTimer.stop()
    dispatchPreviewRunner.cancel()
    dispatchDefaultsRunner.cancel()
    dispatchBook.startRunner = null
    dispatchBook.baseTouched = false
    dispatchBook.defaultsPending = false
    dispatchBook.cardMap = null
    dispatchBook.milestone = null
```

with:

```qml
  // Every dispatch field back to its "none" value and dispatchRunSettings
  // {}; runSettings and dispatchRoot stay. The pending check, the preview,
  // the defaults lookup and the settings read are dropped; a start already
  // launched runs on, but its reply is no longer this dispatch's.
  function resetDispatch() {
    dispatchDebounceTimer.stop()
    dispatchPreviewRunner.cancel()
    dispatchDefaultsRunner.cancel()
    dispatchSettingsRunner.cancel()
    dispatchBook.startRunner = null
    dispatchBook.touched = {}
    dispatchBook.defaultsPending = false
    dispatchBook.settingsPending = false
    dispatchBook.card = null
    dispatchBook.cardMap = null
    dispatchBook.milestone = null
    store.dispatchRunSettings = {}
```

(The rest of `resetDispatch`, from `    store.dispatchState = "idle"` to its closing brace, is unchanged.)

- [ ] **Step 6: `dispatchOpenFor` reads the root's settings and runs**

Replace the whole `dispatchOpenFor` from Task 1 (its comment through its closing brace) with:

```qml
  // The run settings the dispatch reads and, after a start, merges into:
  // runSettings when dispatchRoot is the open project, else
  // dispatchRunSettings.
  function dispatchSettingsSource() {
    return store.dispatchRoot === store.project ? store.runSettings : store.dispatchRunSettings
  }

  // Runs.dispatchDefaults for the opened card with `settings` (a
  // get-run-settings object), read against dispatchRoot's runs only.
  function dispatchDefaultsFor(settings) {
    return Runs.dispatchDefaults({ defaultBranch: "", settings: settings }, dispatchBook.card, dispatchBook.cardMap,
                                 Runs.filterByProject(store.runs, store.dispatchRoot))
  }

  // Opens the dispatch for dispatchRoot on a brd card (as Board.indexTree()
  // leaves it) or "board", with its {id: card} map, and returns whether it
  // may be started. Refused (false, nothing changes) without a dispatchRoot
  // or while a start is in flight. Every opening sets dispatchTargetLabel
  // and records the card, cardMap and cardMap's entry for the target's
  // milestone (Runs.dispatchMilestone), or null. A target dispatchPlan does
  // not offer is `refused` at once and launches nothing; any other starts
  // from dispatchDefaultsFor(dispatchSettingsSource()) and looks up
  // dispatchRoot's default branch. When dispatchRoot is not `project`,
  // dispatchRoot's run settings are read too (dispatchSettingsRunner).
  // Nothing is checked before every launched lookup has replied.
  function dispatchOpenFor(card, cardMap) {
    if (store.dispatchRoot === "" || store.dispatchState === "starting") return false
    store.resetDispatch()
    var plan = Runs.dispatchPlan(card, cardMap)
    var milestone = Runs.dispatchMilestone(card, cardMap)
    var isMap = cardMap !== null && typeof cardMap === "object"
    dispatchBook.card = card
    dispatchBook.cardMap = cardMap
    dispatchBook.milestone = milestone !== null && isMap && store.hasKey(cardMap, milestone.id) ? cardMap[milestone.id] : null
    store.dispatchTarget = plan
    store.dispatchTargetLabel = Runs.dispatchLabel(card, cardMap)
    if (!plan.offered) {
      store.dispatchState = "refused"
      store.dispatchError = plan.reason
      store.dispatchErrorType = "Target"
      return false
    }
    var d = store.dispatchDefaultsFor(store.dispatchSettingsSource())
    store.dispatchForm = { base: d.base, prefix: d.prefix, verify: d.verify, parallelism: d.parallelism,
                           allowNoVerification: d.allowNoVerification }
    store.dispatchState = "previewing"
    dispatchBook.defaultsPending = true
    dispatchBook.settingsPending = store.dispatchRoot !== store.project
    dispatchDefaultsRunner.run(["--defaults", store.dispatchRoot])
    if (dispatchBook.settingsPending) dispatchSettingsRunner.run(["get-run-settings", store.dispatchRoot])
    return true
  }
```

- [ ] **Step 7: The retarget keeps the root**

Replace:

```qml
  // From a blocked story's refusal (`refused` with a dispatchSuggest), opens
  // the dispatch afresh on the milestone card and cardMap recorded at the
  // story's opening and returns openDispatch's result. Refused (false,
  // nothing changes) in any other state or refusal.
  function retargetToMilestone() {
    if (store.dispatchState !== "refused" || store.dispatchSuggest === null) return false
    return store.openDispatch(dispatchBook.milestone, dispatchBook.cardMap)
  }
```

with:

```qml
  // From a blocked story's refusal (`refused` with a dispatchSuggest), opens
  // the dispatch afresh for the same dispatchRoot on the milestone card and
  // cardMap recorded at the story's opening and returns dispatchOpenFor's
  // result. Refused (false, nothing changes) in any other state or refusal.
  function retargetToMilestone() {
    if (store.dispatchState !== "refused" || store.dispatchSuggest === null) return false
    return store.dispatchOpenFor(dispatchBook.milestone, dispatchBook.cardMap)
  }
```

- [ ] **Step 8: The defaults reply reads the touched record; the settings reply; the check waits for both**

Replace:

```qml
    if (branch !== "" && !dispatchBook.baseTouched) store.dispatchForm = store.withField(store.dispatchForm, "base", branch)
    store.checkDispatch()
  }

  // The form is checked: an invalid one is refused and launches nothing, a
  // subtask is ready (am has no dry run for one card), a milestone, a story
  // or the board is previewed. Waits for the defaults lookup, whose reply checks.
  function checkDispatch() {
    if (dispatchBook.defaultsPending || store.dispatchState !== "previewing") return
```

with:

```qml
    if (branch !== "" && !store.hasKey(dispatchBook.touched, "base")) store.dispatchForm = store.withField(store.dispatchForm, "base", branch)
    store.checkDispatch()
  }

  // dispatchRoot's get-run-settings reply, while dispatchRoot is not
  // `project`: the bare object becomes dispatchRunSettings ({} when
  // unreadable); prefix, verify and parallelism are taken from
  // dispatchDefaultsFor with it, except a field the user set since the
  // opening; base and allowNoVerification stay. Then the form is checked.
  // Dropped unless previewing with the read still pending.
  function dispatchSettingsReplied(stdout) {
    if (!dispatchBook.settingsPending || store.dispatchState !== "previewing") return
    dispatchBook.settingsPending = false
    var parsed = store.parseEnvelope(stdout)
    var settings = parsed !== null ? parsed : {}
    store.dispatchRunSettings = settings
    var d = store.dispatchDefaultsFor(settings)
    var form = store.dispatchForm
    var fields = ["prefix", "verify", "parallelism"]
    for (var i = 0; i < fields.length; i++) {
      if (!store.hasKey(dispatchBook.touched, fields[i])) form = store.withField(form, fields[i], d[fields[i]])
    }
    store.dispatchForm = form
    store.checkDispatch()
  }

  // The form is checked: an invalid one is refused and launches nothing, a
  // subtask is ready (am has no dry run for one card), a milestone, a story
  // or the board is previewed. Waits for the defaults lookup and the
  // settings read; whichever replies last checks.
  function checkDispatch() {
    if (dispatchBook.defaultsPending || dispatchBook.settingsPending || store.dispatchState !== "previewing") return
```

Also in the comment of `dispatchDefaultsReplied`, nothing else changes (it already says "unless the user set base since the opening").

- [ ] **Step 9: `setDispatchField` records every touched field**

In `setDispatchField` replace:

```qml
    if (name === "base") dispatchBook.baseTouched = true
```

with:

```qml
    var touched = store.copyMap(dispatchBook.touched)
    touched[name] = true
    dispatchBook.touched = touched
```

- [ ] **Step 10: The settings runner**

Directly after the `dispatchPreviewRunner` `HelperRunner { … }` block (Task 1, Step 7) insert:

```qml

  // viewer-state.py get-run-settings for dispatchRoot, once per opening, only
  // while dispatchRoot is not `project`; latest wins. Guarded by
  // dispatchRoot: a reply for a root the dispatch has left is dropped.
  HelperRunner {
    id: dispatchSettingsRunner
    script: store.backendDir + "projects/viewer-state.py"
    guard: store.dispatchRoot
    onFinished: function(stdout, exitCode) { store.dispatchSettingsReplied(stdout) }
  }
```

- [ ] **Step 11: `dispatchBook` holds the card, the touched record and the settings flag**

Replace:

```qml
  // The dispatch's own bookkeeping; kept apart so consumers cannot write it.
  // `startRunner` is the runner that put the store into `starting`, forgotten
  // by an idle reset (and so by a project switch); `baseTouched` says the user
  // set base since the opening; `defaultsPending` that the --defaults lookup
  // has not replied yet; `cardMap` and `milestone` are the opening's card map
  // and its entry for the target's milestone card (null when unknown).
  QtObject {
    id: dispatchBook
    property var runners: []
    property var startRunner: null
    property bool baseTouched: false
    property bool defaultsPending: false
    property var cardMap: null
    property var milestone: null
  }
```

with:

```qml
  // The dispatch's own bookkeeping; kept apart so consumers cannot write it.
  // `startRunner` is the runner that put the store into `starting`, forgotten
  // by an idle reset (and so by a project switch); `touched` is {field: true}
  // for each form field the user set since the opening; `defaultsPending`
  // says the --defaults lookup has not replied yet, `settingsPending` that
  // dispatchRoot's get-run-settings read has not; `card`, `cardMap` and
  // `milestone` are the opening's card, card map and its entry for the
  // target's milestone card (null when unknown).
  QtObject {
    id: dispatchBook
    property var runners: []
    property var startRunner: null
    property var touched: ({})
    property bool defaultsPending: false
    property bool settingsPending: false
    property var card: null
    property var cardMap: null
    property var milestone: null
  }
```

- [ ] **Step 12: Check no `baseTouched` is left**

Run: `grep -n "baseTouched" core/stores/RunStore.qml`
Expected: no output.

- [ ] **Step 13: Run the new tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_dispatch_open_for_other_root_argv StoresRunStore::test_dispatch_settings_reply_keeps_user_edits_and_unreadable_is_empty StoresRunStore::test_dispatch_prefix_default_reads_only_the_roots_runs StoresRunStore::test_dispatch_retarget_keeps_the_root StoresRunStore::test_dispatch_card_entry_launches_no_settings_read StoresRunStore::test_story_prefix_reads_the_snapshot_then_the_keyed_map`
Expected: 6 PASS, `0 failed`.

- [ ] **Step 14: Run the whole store file**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: `Totals: 312 passed, 0 failed, …`, no other lines.

- [ ] **Step 15: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): a dispatch for another root reads that root's run settings and runs"
```

---

### Task 3: A start for `dispatchRoot`: argv, save, merge, snapshot, and the docs

**Files:**
- Modify: `core/stores/RunStore.qml` — header comment (`:11-14`, `:32-34`), the `dispatchStarted` signal comment (`:187-189`), `dispatchStart` (`:1662-1693`), `isHereStart` (`:1695-1700`), `dispatchStartReplied` (`:1702-1750`), the `dispatchStartC` component (`:2003-2019`)
- Modify: `docs/architecture.md:92`
- Test: `tests/core/stores/tst_run_store.qml` — new tests appended after Task 2's tests (before `  // ---- list snapshots`)

**Interfaces:**
- Consumes (Task 2): `dispatchSettingsSource() -> object`, `dispatchRunSettings`, `dispatchSettingsRunner`; test helpers `otherRootStore()`, `bSettings()`, `readyForB(store)`, `tc.bPreviewArgs`. (Task 1): `dispatchRoot`.
- Produces: `dispatchStart()` launches `start-run.py <dispatchRoot> …` on a runner with `madeFor: dispatchRoot`; `isHereStart(runner)` compares `madeFor` with `dispatchRoot`; a here `ok` merges into `dispatchSettingsSource()`'s object and calls `requestSnapshot([dispatchRoot])`.

- [ ] **Step 1: Write the failing tests**

Append after `test_dispatch_card_entry_launches_no_settings_read` (Task 2), still before `  // ---- list snapshots`:

```qml

  // otherRootStore() with A's and B's first snapshot landed (none in
  // flight) and milestone m1 ready for B (readyForB).
  function otherReadyStore() {
    var store = otherRootStore(); if (!store) return null
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    readyForB(store)
    return store
  }

  property string bSavedJson: '{"verify":["make test"],"allowNoVerification":false,"prefixHistory":["bpre","bold"],"parallelism":2,"prefixByMilestone":{"m1":"bpre"}}'

  // 2.1 RunStore dispatch test 6 + Review Focus 5
  function test_dispatch_start_for_other_root_argv_save_and_refresh() {
    var store = otherReadyStore(); if (!store) return
    compare(store.dispatchState, "ready")
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    var aBefore = JSON.stringify(store.runSettings)
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(runner.madeFor, "/home/u/b")
    compare(argv(runner.current), tc.startCmd + tc.bPreviewArgs)
    compare(runner.savedJson, tc.bSavedJson, "B's history follows the prefix sent")
    var seq = store.snapshotRunner.seq
    reply(runner.current, startOk("r-b", ""), 0)
    compare(store.dispatchState, "started")
    compare(store.dispatchRunId, "r-b")
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], "r-b")
    compare(store.snapshotRunner.seq, seq + 1, "one snapshot is asked for")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootB, "of B only")
    compare(argv(runner.current), tc.viewerCmd + "set-run-settings|/home/u/b|" + tc.bSavedJson)
    compare(store.dispatchRunSettings.prefixHistory.join(","), "bpre,bold")
    compare(store.dispatchRunSettings.prefixByMilestone.m1, "bpre")
    compare(store.dispatchRunSettings.confirmDispatch, false, "B's other keys are kept")
    compare(JSON.stringify(store.runSettings), aBefore, "A's settings are untouched")
    reply(runner.current, JSON.stringify({ ok: true }) + "\n", 0)
    compare(store.dispatchStartRunners.length, 0)
    compare(store.flashText, "")

    compare(store.closeDispatch(), true)
    compare(Object.keys(store.dispatchRunSettings).length, 0, "the merge does not outlive the close")
    store.dispatchRoot = tc.rootB
    var cards = dispatchCards()
    compare(store.dispatchOpenFor(cards.m1, cards), true)
    compare(argv(store.dispatchSettingsRunner.current), tc.viewerCmd + "get-run-settings|/home/u/b", "B is read afresh")

    var busy = otherReadyStore(); if (!busy) return
    busy.refresh()
    verify(busy.snapshotRunner.busy, "a snapshot of every root is in flight")
    busy.dispatchStart()
    reply(busy.dispatchStartRunners[0].current, startOk("r-b", ""), 0)
    compare(busy.dispatchState, "started")
    compare(busy.pendingSnapshot.join("|"), tc.rootB, "B joins the pending request")

    var lone = dispatchStore(); if (!lone) return
    reply(lone.snapshotRunner.current, okReply([]), 0)
    lone.dispatchRoot = tc.rootB
    readyForB(lone)
    compare(lone.dispatchState, "ready")
    lone.dispatchStart()
    var loneSeq = lone.snapshotRunner.seq
    reply(lone.dispatchStartRunners[0].current, startOk("r-b", ""), 0)
    compare(lone.dispatchState, "started")
    compare(lone.snapshotRunner.seq, loneSeq, "B is not registered: no snapshot")
  }

  // 2.1 RunStore dispatch test 7
  function test_dispatch_story_start_for_other_root_saves_prefix_by_milestone_for_it() {
    var store = otherRootStore(); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    var cards = dispatchCards()
    store.dispatchOpenFor(cards.s1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchSettingsRunner.current, JSON.stringify({ verify: ["make test"], parallelism: 2, prefixHistory: ["bpre"],
                                                                 prefixByMilestone: { m9: "b9" } }) + "\n", 0)
    reply(store.dispatchPreviewRunner.current, previewOk(storyDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(argv(runner.current), tc.startCmd + "/home/u/b|story|s1|--base-branch|main|--branch-prefix|bpre|--max-concurrent|2|--verify|make test")
    reply(runner.current, startOk("r-s", ""), 0)
    compare(store.dispatchState, "started")
    compare(argv(runner.current), tc.viewerCmd + "set-run-settings|/home/u/b|" +
            '{"verify":["make test"],"allowNoVerification":false,"prefixHistory":["bpre"],"parallelism":2,"prefixByMilestone":{"m1":"bpre"}}')
    var map = store.dispatchRunSettings.prefixByMilestone
    compare(Object.keys(map).sort().join(","), "m1,m9", "merged into B's settings")
    compare(map.m9, "b9", "B's stored entry is kept")
    compare(map.m1, "bpre")
    compare(store.runSettings.prefixByMilestone, undefined, "nothing keyed into A's settings")
  }

  // 2.1 RunStore dispatch test 8
  function test_dispatch_start_in_flight_completes_for_its_root_after_a_switch() {
    var store = otherReadyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    var proc = runner.current
    store.project = tc.rootB
    compare(store.dispatchRoot, "", "the switch forgets the root")
    checkDispatchIdle(store, "after the switch")
    compare(proc.running, true, "the start is not stopped")
    var seq = store.snapshotRunner.seq
    reply(proc, startOk("r-b", ""), 0)
    checkDispatchIdle(store, "after B's start landed")
    compare(spy.count, 0, "no signal")
    compare(store.snapshotRunner.seq, seq, "no snapshot")
    compare(Object.keys(store.dispatchRunSettings).length, 0, "nothing merged into dispatchRunSettings")
    compare(Object.keys(store.runSettings).length, 0, "nothing merged into runSettings")
    compare(argv(runner.current), tc.viewerCmd + "set-run-settings|/home/u/b|" + tc.bSavedJson, "still written for B")
    reply(runner.current, "garbage\n", 1)
    compare(store.flashText, "", "a save failure that is not here does not flash")
    compare(store.dispatchStartRunners.length, 0)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_dispatch_start_for_other_root_argv_save_and_refresh StoresRunStore::test_dispatch_story_start_for_other_root_saves_prefix_by_milestone_for_it StoresRunStore::test_dispatch_start_in_flight_completes_for_its_root_after_a_switch`
Expected: 3 FAIL — `test_dispatch_start_for_other_root_argv_save_and_refresh` and `test_dispatch_story_start_for_other_root_saves_prefix_by_milestone_for_it` with `Compared values are not the same` (the start runner's `madeFor` / argv still name `/home/u/my proj`), `test_dispatch_start_in_flight_completes_for_its_root_after_a_switch` with `still written for B`.

- [ ] **Step 3: `dispatchStart` launches for `dispatchRoot` from the dispatch's settings**

Replace:

```qml
  // Start: only from ready. start-run.py runs on a HelperRunner of its own
  // (guard "", madeFor this project), which no preview, project switch or
  // other Start stops. The settings a successful start saves are fixed now,
  // from this project's runSettings: the non-blank verify commands sent, the
  // opt-out, the prefix sent followed by the stored history without it (at
  // most 20), the parallelism and, for a story or milestone whose milestone
  // card is known, prefixByMilestone {<milestone id>: prefix sent}.
  function dispatchStart() {
    if (store.dispatchState !== "ready") return false
    var form = store.dispatchForm
    var prefix = form.prefix.trim()
    var history = [prefix]
    var stored = Array.isArray(store.runSettings.prefixHistory) ? store.runSettings.prefixHistory : []
```

with:

```qml
  // Start: only from ready. start-run.py <dispatchRoot> runs on a
  // HelperRunner of its own (guard "", madeFor dispatchRoot), which no
  // preview, project switch or other Start stops. The settings a successful
  // start saves are fixed now, from dispatchSettingsSource(): the non-blank
  // verify commands sent, the opt-out, the prefix sent followed by the
  // stored history without it (at most 20), the parallelism and, for a story
  // or milestone whose milestone card is known, prefixByMilestone
  // {<milestone id>: prefix sent}.
  function dispatchStart() {
    if (store.dispatchState !== "ready") return false
    var form = store.dispatchForm
    var prefix = form.prefix.trim()
    var history = [prefix]
    var source = store.dispatchSettingsSource()
    var stored = Array.isArray(source.prefixHistory) ? source.prefixHistory : []
```

and, further down in the same function, replace:

```qml
    var runner = dispatchStartC.createObject(store, { madeFor: store.project, savedJson: JSON.stringify(saved) })
    dispatchBook.runners = dispatchBook.runners.concat([runner])
    dispatchBook.startRunner = runner
    store.dispatchState = "starting"
    runner.run([store.project].concat(store.dispatchTargetArgs(), store.dispatchOptionArgs()))
```

with:

```qml
    var runner = dispatchStartC.createObject(store, { madeFor: store.dispatchRoot, savedJson: JSON.stringify(saved) })
    dispatchBook.runners = dispatchBook.runners.concat([runner])
    dispatchBook.startRunner = runner
    store.dispatchState = "starting"
    runner.run([store.dispatchRoot].concat(store.dispatchTargetArgs(), store.dispatchOptionArgs()))
```

- [ ] **Step 4: `isHereStart` compares with `dispatchRoot`**

Replace:

```qml
  // A start runner's reply is this dispatch's: it was made in the current
  // project and is the runner that put the store into `starting` (an idle
  // reset, and so a project switch, forgets it).
  function isHereStart(runner) {
    return runner.madeFor === store.project && dispatchBook.startRunner === runner
  }
```

with:

```qml
  // A start runner's reply is this dispatch's: it was made for the current
  // dispatchRoot and is the runner that put the store into `starting` (an
  // idle reset, and so a project switch, forgets it).
  function isHereStart(runner) {
    return runner.madeFor === store.dispatchRoot && dispatchBook.startRunner === runner
  }
```

- [ ] **Step 5: A here `ok` merges into the dispatch's settings and snapshots `[dispatchRoot]`**

Replace:

```qml
  // start-run.py's reply. When it is this dispatch's: ok gives `started`,
  // the run id and message, the saved values in runSettings (prefixByMilestone
  // merged per milestone id), a re-snapshot and dispatchStarted(id or null);
  // a StoryBlockedError gives `refused` with am's message, no log fields and
  // the blockedSuggest() milestone; anything else gives `failed` with what
  // the helper said. After any successful start, wherever it was made, the
  // same runner writes the saved values for the project it was made in.
```

with:

```qml
  // start-run.py's reply. When it is this dispatch's: ok gives `started`,
  // the run id and message, the saved values merged into
  // dispatchSettingsSource()'s object (runSettings only when dispatchRoot is
  // `project`; prefixByMilestone merged per milestone id), a snapshot of
  // [dispatchRoot] only -- requestSnapshot([dispatchRoot]), never refresh()
  // -- and dispatchStarted(id or null); a StoryBlockedError gives `refused`
  // with am's message, no log fields and the blockedSuggest() milestone;
  // anything else gives `failed` with what the helper said. After any
  // successful start, wherever it was made, the same runner writes the saved
  // values for the root it was made for (madeFor).
```

Then, in the same function, replace:

```qml
        var settings = store.copyMap(store.runSettings)
        // Parsed from the JSON that is written: a var property hands back a
        // list Runs.dispatchDefaults does not take for an array.
        var saved = JSON.parse(runner.savedJson)
        for (var key in saved) {
          settings[key] = key === "prefixByMilestone" ? store.mergedPrefixes(settings.prefixByMilestone, saved[key]) : saved[key]
        }
        store.runSettings = settings
        store.dispatchState = "started"
        store.refresh()
```

with:

```qml
        var settings = store.copyMap(store.dispatchSettingsSource())
        // Parsed from the JSON that is written: a var property hands back a
        // list Runs.dispatchDefaults does not take for an array.
        var saved = JSON.parse(runner.savedJson)
        for (var key in saved) {
          settings[key] = key === "prefixByMilestone" ? store.mergedPrefixes(settings.prefixByMilestone, saved[key]) : saved[key]
        }
        if (store.dispatchRoot === store.project) store.runSettings = settings
        else store.dispatchRunSettings = settings
        store.dispatchState = "started"
        store.requestSnapshot([store.dispatchRoot])
```

- [ ] **Step 6: The signal and the start component's comments**

Replace:

```qml
  // A start for the current project went: the run id, or null while am does
  // not list it yet.
  signal dispatchStarted(var runId)
```

with:

```qml
  // A start for `dispatchRoot` went: the run id, or null while am does not
  // list it yet.
  signal dispatchStarted(var runId)
```

and replace:

```qml
  // One HelperRunner per Start. Guard "": start-run.py may take ~20 s, and
  // neither a preview, a project switch nor a Start in another project may
  // stop it. After a successful start the same runner writes the settings
  // for `madeFor`; it goes when that write replies, or at once after a
  // failed start.
  Component {
    id: dispatchStartC

    HelperRunner {
      id: sr
      property string madeFor: ""     // the project the start was made in
```

with:

```qml
  // One HelperRunner per Start. Guard "": start-run.py may take ~20 s, and
  // neither a preview, a project switch nor a Start for another root may
  // stop it. After a successful start the same runner writes the settings
  // for `madeFor`; it goes when that write replies, or at once after a
  // failed start.
  Component {
    id: dispatchStartC

    HelperRunner {
      id: sr
      property string madeFor: ""     // the dispatchRoot the start was made for
```

- [ ] **Step 7: The file header**

Replace:

```qml
// order, a run id listed once, under the first root that lists it. A project
// switch leaves the run list alone: `project`, the open project, decides only
// the run settings and the dispatch; the run controls and the attempt logs
// act on each run's own repo_dir and project root. Plus the selected run, the
```

with:

```qml
// order, a run id listed once, under the first root that lists it. A project
// switch leaves the run list alone: `project`, the open project, decides only
// the run settings; the dispatch is for `dispatchRoot`, which a card entry
// sets to `project`; the run controls and the attempt logs act on each run's
// own repo_dir and project root. Plus the selected run, the
```

and replace:

```qml
// Dispatch (openDispatch .. dispatchStart) previews a run with
// dispatch-preview.py and starts it with start-run.py, one HelperRunner per
// Start.
```

with:

```qml
// Dispatch (openDispatch, dispatchOpenFor .. dispatchStart) previews a run
// for dispatchRoot with dispatch-preview.py and starts it with start-run.py,
// one HelperRunner per Start.
```

- [ ] **Step 8: Check no dispatch launch still carries `project`**

Run: `sed -n '/---- dispatch (S3 3.1)/,$p' core/stores/RunStore.qml | grep -n "store.project"`
Expected: only these five lines, each a card-entry or same-root test — `if (store.project === "" || store.dispatchState === "starting") return false`, `store.dispatchRoot = store.project`, `return store.dispatchRoot === store.project ? …`, and `if (store.dispatchRoot === store.project) store.runSettings = settings`, plus `dispatchBook.settingsPending = store.dispatchRoot !== store.project`. No `.run([store.project` and no `guard: store.project` / `madeFor: store.project`.

- [ ] **Step 9: Run the new tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_dispatch_start_for_other_root_argv_save_and_refresh StoresRunStore::test_dispatch_story_start_for_other_root_saves_prefix_by_milestone_for_it StoresRunStore::test_dispatch_start_in_flight_completes_for_its_root_after_a_switch`
Expected: 3 PASS, `0 failed`.

- [ ] **Step 10: `docs/architecture.md` line 92 (the Dispatch (S3 3.1) paragraph)**

Make these eight exact replacements in that one paragraph (each old text occurs once):

1. Old: ``Dispatch (S3 3.1): the store also starts am runs. `openDispatch(card, cardMap)` takes a brd card as `Board.indexTree()` leaves it (or `"board"`) and its `{id: card}` map; it refuses without a project or while a start is in flight.``
   New: ``Dispatch (S3 3.1): the store also starts am runs, each for `dispatchRoot`, the project root every dispatch launch carries as `ROOT` (`""` while no dispatch has been opened since the last close or project switch). `openDispatch(card, cardMap)`, the card entry, takes a brd card as `Board.indexTree()` leaves it (or `"board"`) and its `{id: card}` map; it refuses without a project or while a start is in flight, else sets `dispatchRoot` to `project` and returns `dispatchOpenFor(card, cardMap)`, which opens the dispatch for the current `dispatchRoot` and refuses when it is `""` or while a start is in flight.``
2. Old: ``starts from `Runs.dispatchDefaults` with `runSettings` -- the open project's whole `get-run-settings` reply, read on `runSettingsRunner` by every project switch (guarded by the new project) and never read for the notify switch, `{}` until it lands and after a project switch -- and the Runs snapshot `runs` (the prefix is``
   New: ``starts from `Runs.dispatchDefaults` with the dispatch's run settings -- `runSettings` when `dispatchRoot` is `project` (the open project's whole `get-run-settings` reply, read on `runSettingsRunner` by every project switch (guarded by the new project) and never read for the notify switch, `{}` until it lands and after a project switch), else `dispatchRunSettings`, `dispatchRoot`'s `get-run-settings` read once per opening on `dispatchSettingsRunner` (guarded by `dispatchRoot`; `{}` until it lands, when it is unreadable and after every reset), whose reply re-derives `prefix`, `verify` and `parallelism` except a field the user set -- and the runs of `dispatchRoot` only (`Runs.filterByProject`) (the prefix is``
3. Old: ``The form is checked with `Runs.validateDispatch` when that lookup replies``
   New: ``The form is checked with `Runs.validateDispatch` when the last of that lookup and the settings read replies``
4. Old: ``(`dispatchStartRunners`, guard `""`, `madeFor` the project)``
   New: ``(`dispatchStartRunners`, guard `""`, `madeFor` `dispatchRoot`)``
5. Old: ``A successful start for the dispatch still open in its project sets `started`, `dispatchRunId` (`""` while am does not list the run yet) and `dispatchMessage`, re-snapshots and emits``
   New: ``A successful start for the dispatch still open for its root sets `started`, `dispatchRunId` (`""` while am does not list the run yet) and `dispatchMessage`, requests a snapshot of `[dispatchRoot]` only and emits``
6. Old: ``writes `set-run-settings` for the project it was made in``
   New: ``writes `set-run-settings` for the root it was made for``
7. Old: ``the store's own `runSettings` merging it per milestone id at once``
   New: ``the dispatch's run settings (`runSettings` or `dispatchRunSettings`) merging it per milestone id at once``
8. Old: ``put the dispatch back to `idle`.``
   New: ``put the dispatch back to `idle` and `dispatchRoot` back to `""`.``

Then run: `grep -c "dispatchRoot" docs/architecture.md`
Expected: a count of at least 8.

- [ ] **Step 11: Run the full gate**

Run: `timeout 900 bash tests/run.sh 2>&1 | tail -60`
Expected: pytest `… passed` with no failures (including `tests/architecture`), every `== tests/…qml` line followed by a `Totals: … 0 failed …` line, `tests/core/stores/tst_run_store.qml` at `Totals: 315 passed, 0 failed`, no `FAIL`, `TypeError` or `ReferenceError` lines, and exit status 0 (`echo $?` → `0`).

- [ ] **Step 12: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml docs/architecture.md
git commit -m "feat(runs): a dispatch start runs, saves and refreshes for dispatchRoot"
```
<!-- task-pipeline: validated -->
