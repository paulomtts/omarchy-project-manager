# 2.1 RunStore dispatch: dispatchRoot drives every dispatch launch — design

Card: `abbba4c7` (subtask of story `8200b9d4`).
Parent design: `docs/superpowers/specs/2026-10-05-dispatch-from-runs-design.md`, cited below as
"DFR l.N". S3's store contract is `docs/architecture.md:92` ("Dispatch (S3 3.1)"), cited as
"ARCH l.92".

## Purpose

The Runs-screen dispatch (DFR l.21-25) dispatches for a project that need not be the open one.
Today every launch in S3's dispatch section (`core/stores/RunStore.qml:1434-1768`) carries
`store.project`. This card adds `dispatchRoot`, the project the dialog is for, and makes every
dispatch launch carry it instead. Card entry points set `dispatchRoot = project`, so card
dispatch behaves exactly as today. Nothing in the UI sets a different root yet: the project and
target steps (`dispatchStep`, `dispatchProjectPick`, `dispatchTargetPick`, DFR l.193) are a
later card. This card gives them one store entry, `dispatchOpenFor(card, cardMap)`, to open the
form for `dispatchRoot`.

## Inherited constraints

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

## Behaviour

### `dispatchRoot`

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

### Entry points

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

### The dispatch's run settings

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

### Launches (argv)

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

### Launch guard and the result

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

### Docs and comments

- `RunStore.qml` header (`:12-14`, `:32-34`): `project` decides the run settings. The dispatch
  is for `dispatchRoot`, which a card entry sets to `project`.
- `docs/architecture.md:92` (the Dispatch (S3 3.1) paragraph) gets the same facts:
  `dispatchRoot`, `dispatchOpenFor`, `dispatchRunSettings`/`dispatchSettingsRunner`,
  `ROOT` = `dispatchRoot` in every argv, the prefix runs filtered to the root, and `started`
  requesting a snapshot of `[dispatchRoot]`.

## Errors and edge cases

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

## Tests

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

## Out of scope

- `dispatchStep`, `dispatchOpenFromRuns`, `dispatchBack`, the project probe, the target tree
  runner, `dispatchProjectPick`, `dispatchTargetPick`, and the guard that keeps a Runs-opened
  dialog through a project switch (DFR l.193, l.200-212): later cards in this story.
- DispatchDialog, RunsScreen, Shortcuts, Panel (DFR l.219-226).
- `start-run.py` run-id discovery (DFR l.163-172) and `board-tree.py`.
- Any change to `runSettingsRunner` / `projectSwitched`'s read of the open project's
  `runSettings`, and to control-request settings reads.
