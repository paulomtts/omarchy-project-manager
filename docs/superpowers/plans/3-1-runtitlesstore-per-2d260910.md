# 3.1 RunTitlesStore: per-project title maps — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `core/stores/RunTitlesStore.qml`, a store holding each registered project's `{id: title}` map (the open project's mirrored from its board, every other project with runs fetched one at a time with `board-titles.py`), compose it in `App.qml` as `app.runTitles`, and document it.

**Architecture:** A `Scope` store with plain input properties App binds (`backendDir`, `active`, `projectRoots`, `openRoot`, `openCardMap`, `runs`), two replaced-never-mutated state maps (`titlesByRoot`, `titleStatus`), a FIFO `titleQueue`, a `fetchingRoot`, and one `HelperRunner` (`titlesRunner`). A single `needCheck()` decides which roots to queue; `launchNext()` starts at most one fetch while `active`; `replied()` applies a reply as `ok` or `unreachable`. Internal bookkeeping (stale marks, already-asked ids, the mirrored root) lives in a private `QtObject`.

**Tech Stack:** QML (QtQml, Quickshell, Quickshell.Io), the pure JS libraries `core/domain/runs.js` and `core/domain/results.js`, QtTest (`qmltestrunner`) with stubbed `Process` objects (`tests/stubs/Quickshell/Io/Process.qml`), pytest for the architecture/doc tests.

**Spec:** `docs/superpowers/specs/3-1-runtitlesstore-per-2d260910.md` (reproduced verbatim in the "Spec" section below; parent design `docs/superpowers/specs/2026-10-05-run-history-titles-design.md`).

## Global Constraints

- The store's root object is a `Scope`.
- Store imports only `QtQml`, `Quickshell`, `Quickshell.Io` and `core/domain/*.js` (`tests/architecture/test_layers.py` `STORE_MODULES`).
- Its inputs are plain properties that App binds; it never reaches for another store.
- `titlesByRoot` and `titleStatus` are replaced, never changed in place.
- Every root key is the root string with its trailing `/` removed, the way `Runs.withProject` removes it (`"/"` stays `"/"`).
- A registered root is a `projectRoots` entry's `root` that is a non-empty string not starting with `-`; each counts once.
- The helper is `python3 <backendDir>boards/board-titles.py ROOT`; no store-side timer (the helper's own 30 s timeout is the only timeout).
- Unreachable: no toast, no banner, no `urgent` text, no signal.
- Docstrings and comments state the contract only, with no narrative.
- `bash tests/run.sh` must be green, including `tests/architecture`.
- `README.md` does not name the store.
- `board-titles.py` and the `runs.js` title functions are used as they are; do not change them.

## Review Focus

1. **The previous open root becomes an ordinary root.** When the open project switches from A to B while A has runs, A's mirrored map goes and A is fetched with `board-titles.py` as any other root. Test: `test_the_previous_open_root_is_fetched_once_it_is_needed` (Task 3).
2. **One root listed twice in the registry** (e.g. `/home/u/a/` and `/home/u/a`) is one key and is fetched once. Test: `test_a_registry_root_with_a_trailing_slash_is_keyed_and_fetched_without_it` (Task 2).
3. **A titles map with non-string values** (`5`, `null`, nested objects) keeps only its string titles; the reply is still `ok`. Test: `test_an_ok_reply_keeps_only_its_string_titles` (Task 2).
4. **`refreshTitles()` while a root is in flight and another queued** queues neither twice and does not relaunch the one in flight. Test: `test_refresh_titles_queues_no_root_twice` (Task 5).
5. **The real run store's runs key to the registry.** Through App, a run of a non-open registered project (its `project.root` set by `RunStore`) makes `board-titles.py` launch for exactly that root. Test: `test_app_fetches_titles_for_another_project_with_runs` (Task 6). Also: a run with no `project` at all is ignored without error (`test_unregistered_and_unusable_roots_are_never_fetched`, Task 2).

---

## Spec

The spec this plan implements, verbatim from `docs/superpowers/specs/3-1-runtitlesstore-per-2d260910.md`:

### 3.1 RunTitlesStore: per-project title maps — design

Card `2d260910-3155-43a0-8c11-fe7d12756cdb`, a subtask of story `b477c51f` (History and
titles stores). Parent design: `docs/superpowers/specs/2026-10-05-run-history-titles-design.md`
(below, "parent"). This card adds `core/stores/RunTitlesStore.qml`, composes it in `App.qml`
as `app.runTitles`, and documents it. It puts the parent's **Cache and invalidation** section
(parent :76-94) into a store. No screen reads the store yet.

#### Inherited constraints

- App hands the store `projectRoots`, `openRoot` (the open project's root, `""` when none),
  `openCardMap` (`BoardStore.cardMap`), `active`, `backendDir` and the run list
  (parent :78-79).
- State: `titlesByRoot` (`{root: {id: title}}`) and `titleStatus`
  (`{root: "loading" | "ok" | "unreachable"}`). The open root is mirrored from `openCardMap`
  through `Runs.titlesFromCards` (parent :79-81; `core/domain/runs.js:540`).
- The store has one `HelperRunner`. It fetches one root at a time, from a queue that holds
  each root at most once (parent :83).
- A root is fetched in four cases (parent :84-88):
  - a listed run of that project needs a title and the root has no entry;
  - a run names a milestone, story, card or subtask id that is missing from an `ok` map. This
    happens at most once, so an id brd does not have never loops. Errors table: "asked once
    per fetch" (parent :199);
  - the panel opens. Every cached root is marked stale and is refetched the next time it is
    needed;
  - `refreshTitles()` is called.
- The open project's map follows its board, and the store never runs the helper for it
  (parent :65-66, :89). A registry change drops the maps of removed roots (parent :89-90).
- **Unreachable** covers `ProjectNotFoundError`, a missing brd, a vanished root and a timeout.
  The root's status becomes `unreachable` and its runs fall back to ids. The root is not asked
  again until `refreshTitles()`, the panel reopening or a registry change. There is no toast,
  no banner and no `urgent` text (parent :91-94, Errors :198).
- A project with no runs causes no title fetch (parent Errors :204).
- The helper is `core/backend/boards/board-titles.py ROOT`. It prints one JSON line:
  `{"ok": true, "titles": {id: title}}`, or an `ok:false` envelope with exit 1, or exit 2 on a
  usage error. It enforces its own 30 s timeout, which it reports as `HelperError`
  (parent :67-74; header of `board-titles.py`).
- Callers look up `titlesByRoot[run.project.root]` (parent :102-103). `run.project.root` is
  the registry root with trailing `/` removed (`Runs.withProject`, `runs.js:369-377`).
- Tests (parent :219-221):
  - `tests/core/stores/tst_run_titles_store.qml` covers the open project from `openCardMap`,
    one root at a time, the missing-id refetch once, unreachable staying quiet, Refresh, panel
    reopen and registry change;
  - the wiring test goes in `tests/core/stores/tst_app_runs.qml` (card).
- Store conventions (`docs/architecture.md` stores section; `tests/architecture/test_layers.py`
  `STORE_MODULES`):
  - the root is a `Scope`;
  - it imports only `QtQml`, `Quickshell`, `Quickshell.Io` and `core/domain/*.js`;
  - its inputs are plain properties that App binds, and it never reaches for another store;
  - its maps are replaced, never changed in place.
- Docstrings and comments state the contract only, with no narrative. `bash tests/run.sh` must
  be green, including `tests/architecture` (card).

#### Behaviour

##### Inputs

| property | type | App binds it to |
|---|---|---|
| `backendDir` | string | `app.backendDir` |
| `active` | bool | `app.panelOpen` |
| `projectRoots` | `[{root, name}]` | `app.runs.projectRoots` |
| `openRoot` | string | `app.runs.project` |
| `openCardMap` | object | `app.board.cardMap` |
| `runs` | normalized runs | `app.runs.runs` |

##### Roots

- **Root key.** A root string with its trailing `/` removed, the way `Runs.withProject`
  removes it (`"/"` stays `"/"`). Every key of `titlesByRoot` and `titleStatus`, and every
  root the store compares, is in this form.
- **Registered root.** The key of a `projectRoots` entry whose `root` is a non-empty string
  that does not start with `-`. This is the same usable rule as `RunStore.usableRoots()`, and
  `board-titles.py` refuses any other root with `Usage`. Each root counts once.
- **The open root.** `openRoot` as a key. It is `""` when `openRoot` is `""` or not a string.
- **A run's root.** `run.project.root` as a key. A run without one belongs to no root.
- **Fetchable root.** A registered root, other than the open root, that is the root of at
  least one entry of `runs`.

##### Ids a run names

A run names these ids. Each counts only when it is a non-empty string:

- `milestone_id`, `story_id` and `card_id`;
- the `card_id` of each entry of `run.tree.stories`, except `"integrate"` and `"bases"`;
- the `card_id` of each entry of `run.tree.subtasks`.

An id is **missing** from a map when the map has no own key for it (`Runs.hasKey`).

##### State

- `titlesByRoot`: `{root: {id: title}}`. Replaced, never changed in place.
- `titleStatus`: `{root: "loading" | "ok" | "unreachable"}`. Replaced, never changed in place.
  A root that has no key here has **no entry**.
- `titleQueue`: the roots that wait to be fetched, oldest first. It never holds the root in
  flight.
- `fetchingRoot`: the root whose fetch is in flight, `""` when none is.
- `titlesRunner` (read-only alias): the store's one `HelperRunner`. Its `script` is
  `backendDir + "boards/board-titles.py"`.

These are internal and are not part of the contract beyond what follows: a per-root **stale**
mark, and the per-root set of ids **already asked about**.

##### The open project

- While the open root is not `""`, `titlesByRoot[openRoot]` is
  `Runs.titlesFromCards(openCardMap)` and `titleStatus[openRoot]` is `"ok"`. Both are
  recomputed whenever `openRoot` or `openCardMap` changes.
- The open root is never queued and never fetched.
- When a root becomes the open root:
  - it leaves `titleQueue`;
  - if its fetch is in flight, that fetch is cancelled and the next queued root launches;
  - a reply for the open root is dropped.
- When the open root changes from A to another value, A's mirrored entry (map and status) is
  removed. A is then an ordinary root. It is fetched the next time it is needed.
- A board reply that has not landed yet means a project switch briefly shows the previous
  board's map under the new root. Titles are looked up by id, so this costs only fallbacks
  until `BoardStore.cardMap` lands. Accepted.

##### When a root is queued

A **need check** goes over the registered roots in registry order. It appends to `titleQueue`
each fetchable root R that is not already queued and not in flight, when one of these holds:

1. R has no entry.
2. R's status is `"ok"` and R is marked stale.
3. R's status is `"ok"`, and some run of R names an id that is missing from
   `titlesByRoot[R]` and is not in R's already-asked set. Every such id is added to the
   already-asked set when R is queued for this reason.

A root whose status is `"unreachable"` or `"loading"` is never queued by a need check.
Queueing R sets `titleStatus[R]` to `"loading"`. R's map, if it has one, stays in
`titlesByRoot` until R's reply lands.

The need check runs when any of these happens:

- `runs` changes;
- `projectRoots` changes;
- `openRoot` changes;
- `active` turns true;
- a fetch reply is applied;
- `refreshTitles()` is called.

##### Launching

- A fetch launches only while `active` is true, `fetchingRoot` is `""` and `titleQueue` is
  not empty.
- The launch takes the head of the queue as `fetchingRoot` and runs
  `python3 <backendDir>boards/board-titles.py ROOT`, with `ROOT` the root key.
- While `active` is false, queued roots stay queued and nothing launches. A fetch already in
  flight still lands and is applied.

##### A reply

The reply belongs to `fetchingRoot`. Applying it clears `fetchingRoot`, then launches the next
queued root, then runs a need check.

- **ok.** The process exited 0, `Results.parseEnvelope(stdout)` is an object with `ok === true`,
  and its `titles` is a plain object.
  - `titlesByRoot[R]` becomes a new map holding each own key of `titles` whose value is a
    string;
  - `titleStatus[R]` becomes `"ok"`;
  - R's stale mark is cleared;
  - R's already-asked set is kept, so an id the new map still lacks is not asked about again.
- **unreachable.** Anything else: a non-zero exit, an `ok:false` envelope of any type,
  unparsable output, or `titles` that is not a plain object.
  - `titleStatus[R]` becomes `"unreachable"`;
  - R's map is removed from `titlesByRoot`, so its runs fall back to ids;
  - nothing else happens: no signal, no toast, no error text.
- A reply for a root that has left the registry, or that has become the open root, is
  dropped. Its fetch was cancelled, see below.

##### Invalidation

- **Panel opens** (`active` turns true):
  - every root whose status is `"ok"`, except the open root, is marked stale;
  - every `"unreachable"` status is removed, so that root has no entry;
  - every already-asked set is emptied;
  - a need check runs, and the queue launches.
- **Panel closes.** Nothing is dropped. The maps stay cached for the next opening.
- **`refreshTitles()`** does what an opening does: stale marks, unreachable cleared,
  already-asked sets emptied, then a need check. A root already queued or in flight is not
  queued twice.
- **Registry change** (`projectRoots` changes):
  - for every root that is no longer registered and is not the open root, its
    `titlesByRoot` and `titleStatus` entries, stale mark and already-asked set are dropped,
    and it leaves `titleQueue`;
  - if such a root's fetch is in flight, that fetch is cancelled (`titlesRunner.cancel()`)
    and the next queued root launches;
  - every `"unreachable"` status is removed;
  - a need check runs.
- **Runs change.** The store drops nothing. A root whose runs all went keeps its entry, and
  is simply not fetched again until it is needed.

##### Never

- The store never fetches the open root, a root that is not registered, or a root with no run
  in `runs`.
- It never has two fetches in flight, and never queues a root twice.
- It never writes, never shows an error, and never reaches for another store.

##### App wiring

`App.qml` adds this block after `runAlerts`:

```qml
readonly property RunTitlesStore runTitles: RunTitlesStore {
  backendDir: app.backendDir
  active: app.panelOpen
  projectRoots: app.runs.projectRoots
  openRoot: app.runs.project
  openCardMap: app.board.cardMap
  runs: app.runs.runs
}
```

It sits under a comment in the style of its neighbours, saying the store never imports the
run or board store and listing what App hands it. App routes no signal from it.

##### Docs

`docs/architecture.md` gains one top-level bullet, `` - `RunTitlesStore.qml` … ``, after the
`RunDispatchStore.qml` bullet. It names:

- `app.runTitles`;
- every bound input, each backticked: `backendDir`, `active`, `projectRoots`, `openRoot`,
  `openCardMap`, `runs`;
- the states, `titlesByRoot` and `titleStatus`;
- `refreshTitles()`;
- the fetch rules above, in one paragraph.

`README.md` does not name the store.

#### Tests (TDD: written first, seen failing)

##### `tests/core/stores/tst_run_titles_store.qml`

Tier: QML store unit test. This is where `HelperRunner` processes are stubbed and a store's
own reactions to its inputs are driven, as in `tst_run_alerts_store.qml` and
`tst_run_control_store.qml`.

How the tests are built:

- the store is built alone with
  `Qt.createComponent("../../../core/stores/RunTitlesStore.qml")` and
  `createObject(tc, {backendDir: "/plugin/core/backend/"})`;
- runs are made with `Runs.withProject(Runs.normalizeRun(...), root, name)`;
- replies go through the stubbed process: `proc.outText = …; proc.exited(code)` on
  `s.titlesRunner.current`;
- argv is checked as `current.command.join("|")`, which is
  `python3|/plugin/core/backend/boards/board-titles.py|<root>`.

The roots are rootA `/home/u/a`, rootB `/home/u/b` and rootC `/home/u/c`.

1. **open project mirrors openCardMap.**
   - Set `openRoot` to rootA and `openCardMap` to `{c1: {title: " One "}}`. Then
     `titlesByRoot[rootA]` deep-equals `{c1: "One"}` and `titleStatus[rootA]` is `"ok"`.
   - With an active store and rootA runs, the runner never launches.
   - A change of `openCardMap` updates the map.
   - With `openRoot` set to `""`, rootA's entry is gone.
2. **becoming the open root cancels its fetch.**
   - Start active with no open root and runs of rootA and rootB, so rootA is in flight and
     rootB is queued.
   - Set `openRoot` to rootA. rootA's fetch is cancelled, rootB launches, and rootA's entry
     is the `openCardMap` mirror.
   - A late reply on rootA's old process changes nothing.
   - A queued root that becomes the open root leaves `titleQueue`.
3. **fetch on need, one at a time, registry order.**
   - Make it active, with runs of rootB then rootA in `runs`, the registry `[A, B, C]` and no
     open root. The first launch is rootA, `titleQueue` is `[rootB]`, both statuses are
     `"loading"` and rootC is absent.
   - An ok reply for rootA stores its map and launches rootB.
4. **de-dupe.** Changing `runs` to a new array while rootA is in flight and rootB is queued
   adds no second rootA or rootB, and `titleQueue` stays `[rootB]`.
5. **no fetch for a project without runs.** With a registry of `[A, B]` and runs only of rootA,
   rootB never launches and has no entry.
6. **unregistered roots and bad roots are ignored.**
   - A run whose root is not in `projectRoots` is never fetched.
   - A registry entry `{root: "-x"}` or `{root: ""}` with runs is never fetched.
   - A root given with a trailing `/` in `projectRoots` is keyed and fetched without it.
7. **nothing launches while closed.**
   - With `active` false and runs present, the runner never launches.
   - Turning `active` true launches the first queued root.
   - A reply that lands after `active` turned false is still applied.
8. **missing-id refetch once.**
   - rootA's map is `ok` without `s9`, and a run of rootA arrives naming `s9` as a
     `tree.subtasks` card id. One more fetch of rootA launches.
   - Its reply still lacks `s9`, and no third fetch follows, even after `runs` is set again.
   - A run naming a new id `s10` triggers exactly one more fetch.
   - Synthetic story ids `integrate` and `bases` never trigger a refetch.
9. **unreachable stays quiet.** For each of these replies, `titleStatus[rootA]` is
   `"unreachable"`, the store has no map for rootA, and a new `runs` value launches nothing for
   rootA:
   - `{"ok":false,"error":{"type":"ProjectNotFoundError",…}}` with exit 1;
   - an exit 1 with empty stdout;
   - exit 0 with `not json`;
   - exit 0 with `{"ok":true,"titles":[]}`.

   The next queued root still launches. Unreachable does not stall the queue.
10. **refreshTitles.** After rootA is `ok` and rootB is `unreachable`, `refreshTitles()`
    queues both, in registry order, and the stale `ok` map of rootA stays in `titlesByRoot`
    while it loads.
11. **panel reopen.**
    - With rootA `ok` and rootB `unreachable`, close then open the panel. Both are fetched
      again.
    - A reopen with no runs of rootA fetches nothing for rootA, but rootA's map stays.
12. **registry change.**
    - Removing rootB from `projectRoots` drops `titlesByRoot[rootB]` and
      `titleStatus[rootB]` and removes it from the queue.
    - If rootB is in flight, it is cancelled and the next root launches.
    - An unreachable rootC with runs that is still registered is fetched again.

##### `tests/core/stores/tst_app_runs.qml`

Tier: App composition test, the existing home for App's run-store wiring (card). The header
comment's list of composed stores gains `app.runTitles` and `tst_run_titles_store.qml`.

13. **runTitles exists and is wired.**
    - `make()` gives `app.runTitles` with these values:
      - `backendDir` is `/plugin/core/backend/`;
      - `projectRoots` equals `app.runs.projectRoots`;
      - `openRoot` is pA's root;
      - `openCardMap` is `app.board.cardMap`;
      - `runs` is `app.runs.runs`;
      - `active` follows `app.panelOpen`.
    - After `app.board.applyTreeData([{id: "c1", title: "One", …}])`,
      `app.runTitles.titlesByRoot[pA root].c1` is `"One"`.
    - With the panel open and an ok snapshot listing a pA run, no `board-titles.py` launches
      (pA is open).

##### `tests/architecture/test_run_store_docs.py`

Tier: architecture doc test. It pins every run store's App wiring to its docs bullet.

14. `STORES` gains `"RunTitlesStore"` after `"RunDispatchStore"`, and the module docstring
    says "five". The existing parametrized tests then require the new bullet:
    - in order;
    - naming `` `app.runTitles` ``;
    - naming every input App binds.

    `README_TOKENS` gains `"RunTitlesStore"` and `"app.runTitles"`.

##### Unchanged and still green

These suites need no change and must pass:

- `tests/architecture/test_layers.py` (store imports, no duplicated components);
- `test_icon_glyphs.py` (the store shows no glyph);
- the whole `bash tests/run.sh`.

#### Out of scope

- Any reader of `titlesByRoot` or `titleStatus`: the Runs rows, Run detail, the Events pane's
  `titles`, `searchRuns` / `newAlerts` callers, the `titles unavailable` caption, and the
  footer's **Refresh titles** button. These belong to the UI cards.
- Titled alerts (3.4 RunAlertsStore).
- History runs and their titles. 3.2 RunHistoryStore and 3.3, which bring history rows into
  RunStore's list, decide whether App hands history rows here too.
- `board-titles.py` itself (1.1) and the `runs.js` title functions (2.1). Both exist and are
  used as they are.
- A store-side timer. The helper's own 30 s timeout is the only timeout.
- Any brd/am change, persistence, or reading of either database.

---

## File Structure

- Create `core/stores/RunTitlesStore.qml` — the store (Tasks 1–5 build it up).
- Create `tests/core/stores/tst_run_titles_store.qml` — the store's QML unit tests (Tasks 1–5).
- Modify `core/stores/App.qml` — compose `app.runTitles` after `runAlerts` (Task 6).
- Modify `tests/core/stores/tst_app_runs.qml` — header comment and two wiring tests (Task 6).
- Modify `tests/architecture/test_run_store_docs.py` — `STORES`, docstring, `README_TOKENS` (Task 6).
- Modify `docs/architecture.md` — one `RunTitlesStore.qml` bullet after the `RunDispatchStore.qml` bullet (Task 6).

## How to run the tests

- One QML test file: `bash tests/run.sh tst_run_titles_store` (the argument filters QML test paths by substring; the script always runs the whole pytest suite first). A QML test fails when the output shows a `FAIL!` line, or any `TypeError` / `ReferenceError` / `Unable to assign` / `is not a function` line; the script then exits non-zero. Read the `Totals:` line.
- pytest alone: `python3 -m pytest tests/architecture/test_run_store_docs.py -q`; if `python3` has no pytest, use `uv run --with pytest python3 -m pytest tests/architecture/test_run_store_docs.py -q`.
- Everything: `bash tests/run.sh`.

Facts the engineer needs:

- `tests/stubs/Quickshell/Io/Process.qml` stubs `Process`: setting `running` does nothing. A test answers a launch by setting `proc.outText` and calling `proc.exited(code)`, which makes `HelperRunner` emit `finished(stdout, exitCode, guard)` synchronously — so the store's next launch has already happened when `exited()` returns.
- `HelperRunner.run(args)` creates a new process (`current`), `command` = `["python3", script].concat(args)`. `HelperRunner.cancel()` bumps `seq`, so the cancelled process's later `exited()` is ignored. `current` is `null` until the first `run()`.
- `Runs.withProject(run, root, name)` sets `run.project = {root, name}` with every trailing `/` removed from `root`. `Runs.normalizeRun(raw)` gives `milestone_id`, `story_id`, `card_id`, `tree.stories` (each with `card_id`; the synthetic `integrate` and `bases` included) and `tree.subtasks` (subtasks of real stories only, each with `card_id`).
- `Runs.titlesFromCards(cardMap)` gives `{id: trimmed title}`; `Runs.hasKey(map, key)` is an own-property check; `Runs.copyMap(map)` a shallow copy; `Runs.runRoot(run)` is `run.project.root` or `""`; `Results.parseEnvelope(text)` parses the last line as a JSON object, else `null`.

---

### Task 1: The store skeleton and the open project's mirrored map

**Files:**
- Create: `core/stores/RunTitlesStore.qml`
- Test: `tests/core/stores/tst_run_titles_store.qml`

**Interfaces:**
- Consumes: `Runs.titlesFromCards(cardMap)`, `Runs.copyMap(map)`, `Runs.hasKey(map, key)` from `core/domain/runs.js`; `HelperRunner` from `core/stores/HelperRunner.qml`.
- Produces: `RunTitlesStore` with properties `backendDir: string`, `active: bool`, `projectRoots: var`, `openRoot: string`, `openCardMap: var`, `runs: var`, `titlesByRoot: var`, `titleStatus: var`, `titleQueue: var` (array of root keys), `fetchingRoot: string`, `readonly titlesRunner` (alias of the `HelperRunner`); functions `rootKey(path) -> string`, `openKey() -> string`, `mirrorOpen()`, `openRootMoved()`; private `titlesState.mirrored: string`.

- [ ] **Step 1: Write the failing test**

Create `tests/core/stores/tst_run_titles_store.qml`:

```qml
// tests/core/stores/tst_run_titles_store.qml
// The run titles store: the open project's map mirrored from its card map,
// the one-at-a-time board-titles.py fetches of every other registered
// project with runs, the missing-id refetch, unreachable roots, Refresh, the
// panel reopening and registry changes. Built alone and driven through its
// inputs; stubbed Process objects stand in for board-titles.py.
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs

TestCase {
  id: tc
  name: "StoresRunTitlesStore"

  property string rootA: "/home/u/a"
  property string rootB: "/home/u/b"
  property string rootC: "/home/u/c"
  property string titlesCmd: "python3|/plugin/core/backend/boards/board-titles.py|"

  // A RunTitlesStore built alone, closed, with nothing bound.
  function makeTitles() {
    var comp = Qt.createComponent("../../../core/stores/RunTitlesStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }

  // The registry of `roots`, in that order, as App hands it over.
  function registry(roots) {
    return roots.map(function(r) { return { root: r, name: "proj" } })
  }

  // Run `id` of `root` as the run store hands it over: normalized, tagged
  // with its project, of milestone m1, with am's `stories` ([] when omitted).
  function runOf(id, root, stories) {
    var raw = {
      row: { id: id, repo_dir: root },
      status: { run: { id: id, milestone_id: "m1", status: "started" }, rows: [], stories: stories || [], subtasks: [] }
    }
    return Runs.withProject(Runs.normalizeRun(raw), root, "proj")
  }

  // A store with the registry `roots`, the run list `runList` and no open
  // project, then opened.
  function openTitles(roots, runList) {
    var s = makeTitles(); if (!s) return null
    s.projectRoots = registry(roots)
    s.runs = runList
    s.active = true
    return s
  }

  // board-titles.py's ok reply carrying `map`.
  function titlesOk(map) { return JSON.stringify({ ok: true, titles: map }) + "\n" }

  // The titles of every id a plain runOf run names.
  function plain() { return { m1: "Milestone one" } }

  // A stubbed process's reply: its stdout, then its exit code.
  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // The fetch in flight answered with `text` and exit code `code`.
  function answer(s, text, code) { reply(s.titlesRunner.current, text, code) }

  // A process's argv, joined with "|".
  function argv(proc) { return proc.command.join("|") }

  // Store `s`'s queue, comma-joined.
  function queueOf(s) { return s.titleQueue.join(",") }

  // ---- the open project

  function test_the_open_project_mirrors_its_card_map() {
    var s = makeTitles(); if (!s) return
    s.openRoot = tc.rootA
    s.openCardMap = { c1: { title: " One " } }
    compare(JSON.stringify(s.titlesByRoot[tc.rootA]), JSON.stringify({ c1: "One" }))
    compare(s.titleStatus[tc.rootA], "ok")
    s.openCardMap = { c1: { title: "One" }, c2: { title: "Two" } }
    compare(JSON.stringify(s.titlesByRoot[tc.rootA]), JSON.stringify({ c1: "One", c2: "Two" }), "a new card map updates the map")
    s.openRoot = ""
    compare(Runs.hasKey(s.titlesByRoot, tc.rootA), false, "no open project: rootA's mirrored map is gone")
    compare(Runs.hasKey(s.titleStatus, tc.rootA), false, "and so is its status")
  }

  function test_an_open_root_with_a_trailing_slash_is_keyed_without_it() {
    var s = makeTitles(); if (!s) return
    s.openRoot = tc.rootA + "/"
    s.openCardMap = { c1: { title: "One" } }
    compare(s.titlesByRoot[tc.rootA].c1, "One")
    compare(Runs.hasKey(s.titlesByRoot, tc.rootA + "/"), false)
  }

  function test_the_open_project_is_never_fetched() {
    var s = makeTitles(); if (!s) return
    s.openRoot = tc.rootA
    s.openCardMap = { m1: { title: "Milestone one" } }
    s.projectRoots = registry([tc.rootA])
    s.runs = [runOf("r1", tc.rootA, [{ card_id: "s9", subtasks: [] }])]
    s.active = true
    compare(s.titlesRunner.current, null, "no board-titles.py for the open project, even for an id its board lacks")
    compare(queueOf(s), "")
    compare(s.fetchingRoot, "")
    compare(s.titleStatus[tc.rootA], "ok")
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh tst_run_titles_store`
Expected: FAIL — every test fails in `makeTitles()` because `RunTitlesStore.qml` does not exist (`FAIL!` lines naming `test_the_open_project_mirrors_its_card_map` etc.).

- [ ] **Step 3: Write minimal implementation**

Create `core/stores/RunTitlesStore.qml`:

```qml
import QtQml
import Quickshell
import Quickshell.Io
import "../domain/results.js" as Results
import "../domain/runs.js" as Runs

// The run titles: each registered project's {id: title} map, for the run
// screens to show titles in place of ids. `titlesByRoot` is
// {root: {id: title}} and `titleStatus` {root: "loading" | "ok" |
// "unreachable"}; both are replaced, never changed in place, and keyed by
// the root with its trailing "/" removed. The open project's map is
// Runs.titlesFromCards(openCardMap), its status "ok", and it is never
// fetched. Every other registered root with a run in `runs` is fetched with
// board-titles.py ROOT on `titlesRunner`, one root at a time from
// `titleQueue` (oldest first, each root once, never the root in flight,
// `fetchingRoot`) and only while `active`: when it has no entry, when its ok
// map is stale (each opening and refreshTitles() mark every ok map stale),
// or when a run names a milestone, story or card id its ok map lacks and
// that was not already asked about since the last opening or
// refreshTitles(). A queued root is "loading" and keeps its map until the
// reply. A reply that is not an ok titles object makes the root
// "unreachable" and drops its map; it is not asked again until
// refreshTitles(), the next opening or a registry change. A root that leaves
// the registry loses its entry. The backend directory, the panel-open flag,
// the registry, the open project's root and card map and the run list are
// handed to it from outside -- it never reaches for another store. App
// composes it as `app.runTitles`.
Scope {
  id: titles

  property string backendDir: ""     // <plugin>/core/backend/
  property bool active: false        // App binds this to "panel open" (app.panelOpen)
  property var projectRoots: []      // [{root, name}], the registry in its order; App binds it
  property string openRoot: ""       // the open project's root path; "" when none is open
  property var openCardMap: ({})     // the open project's {id: card}; App binds the board's cardMap
  property var runs: []              // the run store's merged run list; App binds it

  property var titlesByRoot: ({})
  property var titleStatus: ({})
  property var titleQueue: []        // the roots waiting to be fetched, oldest first
  property string fetchingRoot: ""   // the root whose fetch is in flight; "" when none is

  readonly property alias titlesRunner: titlesRunner

  onOpenRootChanged: titles.openRootMoved()
  onOpenCardMapChanged: titles.mirrorOpen()
  Component.onCompleted: titles.openRootMoved()

  // `path` with every trailing "/" removed ("/" for a path of only slashes);
  // "" when it is not a string.
  function rootKey(path) {
    if (typeof path !== "string") return ""
    var end = path.length
    while (end > 0 && path.charAt(end - 1) === "/") end--
    if (end === 0) return path === "" ? "" : "/"
    return path.substring(0, end)
  }

  // The open project's root as a key; "" when none is open.
  function openKey() { return titles.rootKey(titles.openRoot) }

  // The open project's map becomes Runs.titlesFromCards(openCardMap) and its
  // status "ok"; nothing while no project is open.
  function mirrorOpen() {
    var open = titles.openKey()
    if (open === "") return
    var maps = Runs.copyMap(titles.titlesByRoot)
    var status = Runs.copyMap(titles.titleStatus)
    maps[open] = Runs.titlesFromCards(titles.openCardMap)
    status[open] = "ok"
    titles.titlesByRoot = maps
    titles.titleStatus = status
  }

  // The open root moved: the previous one's mirrored map and status go, and
  // the new one's map mirrors openCardMap.
  function openRootMoved() {
    var open = titles.openKey()
    var prev = titlesState.mirrored
    if (prev !== "" && prev !== open) {
      var maps = Runs.copyMap(titles.titlesByRoot)
      var status = Runs.copyMap(titles.titleStatus)
      delete maps[prev]
      delete status[prev]
      titles.titlesByRoot = maps
      titles.titleStatus = status
    }
    titlesState.mirrored = open
    titles.mirrorOpen()
  }

  // Bookkeeping kept apart so consumers cannot write it.
  QtObject {
    id: titlesState
    property string mirrored: ""   // the root whose map mirrors openCardMap; "" when none
  }

  // The one board-titles.py runner. Guard "": the store tracks the root in
  // flight itself and cancels a fetch that must not land.
  HelperRunner {
    id: titlesRunner
    script: titles.backendDir + "boards/board-titles.py"
    guard: ""
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run.sh tst_run_titles_store`
Expected: `Totals: 5 passed, 0 failed` for `StoresRunTitlesStore` (3 tests + initTestCase/cleanupTestCase), no `FAIL!`, no `TypeError`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunTitlesStore.qml tests/core/stores/tst_run_titles_store.qml
git commit -m "feat(runs): RunTitlesStore mirrors the open project's titles from its card map"
```

---

### Task 2: Fetch on need, one root at a time; ok and unreachable replies

**Files:**
- Modify: `core/stores/RunTitlesStore.qml`
- Test: `tests/core/stores/tst_run_titles_store.qml`

**Interfaces:**
- Consumes: Task 1's `rootKey`, `openKey`, `titlesState`, `titlesRunner`; `Runs.runRoot(run)`, `Results.parseEnvelope(text)`.
- Produces: `registeredRoots() -> [rootKey]` (registry order, each once), `runsByRoot() -> {root: [run]}`, `needCheck()`, `launchNext()`, `replied(stdout: string, exitCode: int)`, `stringTitles(map) -> {id: string}`. Task 4 and Task 5 replace `needCheck()`; Task 5 replaces the `onActiveChanged` and `onProjectRootsChanged` handlers added here.

- [ ] **Step 1: Write the failing tests**

Append inside the `TestCase` of `tests/core/stores/tst_run_titles_store.qml`, before its closing `}`:

```qml
  // ---- fetching on need

  function test_fetches_each_root_with_runs_one_at_a_time_in_registry_order() {
    var s = openTitles([tc.rootA, tc.rootB, tc.rootC], [runOf("rb", tc.rootB), runOf("ra", tc.rootA)])
    if (!s) return
    compare(argv(s.titlesRunner.current), tc.titlesCmd + tc.rootA, "registry order, not run order")
    compare(s.fetchingRoot, tc.rootA)
    compare(queueOf(s), tc.rootB, "the root in flight is not in the queue")
    compare(s.titleStatus[tc.rootA], "loading")
    compare(s.titleStatus[tc.rootB], "loading")
    compare(Runs.hasKey(s.titleStatus, tc.rootC), false, "a root with no runs has no entry")
    answer(s, titlesOk(plain()), 0)
    compare(JSON.stringify(s.titlesByRoot[tc.rootA]), JSON.stringify(plain()))
    compare(s.titleStatus[tc.rootA], "ok")
    compare(argv(s.titlesRunner.current), tc.titlesCmd + tc.rootB, "the next queued root launches")
    compare(s.fetchingRoot, tc.rootB)
    compare(queueOf(s), "")
    answer(s, titlesOk(plain()), 0)
    compare(s.titleStatus[tc.rootB], "ok")
    compare(s.fetchingRoot, "", "nothing left to fetch")
    compare(s.titlesRunner.busy, false)
  }

  function test_an_ok_reply_keeps_only_its_string_titles() {
    var s = openTitles([tc.rootA], [runOf("ra", tc.rootA)]); if (!s) return
    answer(s, titlesOk({ m1: "Milestone one", n: 5, o: null, p: { x: "y" } }), 0)
    compare(JSON.stringify(s.titlesByRoot[tc.rootA]), JSON.stringify({ m1: "Milestone one" }))
    compare(s.titleStatus[tc.rootA], "ok")
  }

  function test_a_new_run_list_queues_no_root_twice() {
    var s = openTitles([tc.rootA, tc.rootB], [runOf("ra", tc.rootA), runOf("rb", tc.rootB)]); if (!s) return
    var first = s.titlesRunner.current
    s.runs = [runOf("ra", tc.rootA), runOf("rb", tc.rootB), runOf("rb2", tc.rootB)]
    verify(s.titlesRunner.current === first, "the fetch in flight is not relaunched")
    compare(s.fetchingRoot, tc.rootA)
    compare(queueOf(s), tc.rootB)
  }

  function test_a_project_without_runs_is_never_fetched() {
    var s = openTitles([tc.rootA, tc.rootB], [runOf("ra", tc.rootA)]); if (!s) return
    compare(queueOf(s), "")
    answer(s, titlesOk(plain()), 0)
    compare(s.fetchingRoot, "")
    compare(Runs.hasKey(s.titleStatus, tc.rootB), false)
    compare(Runs.hasKey(s.titlesByRoot, tc.rootB), false)
  }

  function test_unregistered_and_unusable_roots_are_never_fetched() {
    var s = makeTitles(); if (!s) return
    s.projectRoots = [{ root: "-x", name: "dash" }, { root: "", name: "empty" }, { root: tc.rootB, name: "b" }]
    var noProject = Runs.normalizeRun({ row: { id: "rn" }, status: { run: { id: "rn", milestone_id: "m1" } } })
    s.runs = [runOf("rx", "-x"), runOf("re", ""), runOf("ra", tc.rootA), noProject]
    s.active = true
    compare(s.titlesRunner.current, null, "no run of a registered, usable root: nothing launches")
    compare(queueOf(s), "")
    compare(JSON.stringify(s.titleStatus), "{}")
  }

  function test_a_registry_root_with_a_trailing_slash_is_keyed_and_fetched_without_it() {
    var s = makeTitles(); if (!s) return
    s.projectRoots = [{ root: tc.rootA + "/", name: "a" }, { root: tc.rootA, name: "a again" }]
    s.runs = [runOf("ra", tc.rootA + "/")]
    s.active = true
    compare(argv(s.titlesRunner.current), tc.titlesCmd + tc.rootA)
    compare(queueOf(s), "", "two entries of one root fetch it once")
    answer(s, titlesOk(plain()), 0)
    compare(s.titleStatus[tc.rootA], "ok")
    compare(Runs.hasKey(s.titleStatus, tc.rootA + "/"), false)
    compare(s.fetchingRoot, "")
  }

  function test_nothing_launches_while_closed() {
    var s = makeTitles(); if (!s) return
    s.projectRoots = registry([tc.rootA, tc.rootB])
    s.runs = [runOf("ra", tc.rootA), runOf("rb", tc.rootB)]
    compare(s.titlesRunner.current, null, "closed: nothing launches")
    compare(queueOf(s), tc.rootA + "," + tc.rootB, "the roots wait in the queue")
    s.active = true
    compare(argv(s.titlesRunner.current), tc.titlesCmd + tc.rootA, "opening launches the first queued root")
    var proc = s.titlesRunner.current
    s.active = false
    reply(proc, titlesOk(plain()), 0)
    compare(s.titleStatus[tc.rootA], "ok", "a reply that lands after closing is applied")
    compare(s.fetchingRoot, "", "closed: rootB does not launch")
    compare(s.titlesRunner.busy, false)
    compare(queueOf(s), tc.rootB)
  }

  function test_an_unreachable_root_stays_quiet() {
    var bad = [
      [JSON.stringify({ ok: false, error: { type: "ProjectNotFoundError", message: "no project" } }) + "\n", 1],
      ["", 1],
      ["not json\n", 0],
      [JSON.stringify({ ok: true, titles: [] }) + "\n", 0]
    ]
    for (var i = 0; i < bad.length; i++) {
      var s = openTitles([tc.rootA, tc.rootB], [runOf("ra", tc.rootA), runOf("rb", tc.rootB)]); if (!s) return
      answer(s, bad[i][0], bad[i][1])
      compare(s.titleStatus[tc.rootA], "unreachable", "reply " + i)
      compare(Runs.hasKey(s.titlesByRoot, tc.rootA), false, "reply " + i + ": rootA's runs fall back to ids")
      compare(argv(s.titlesRunner.current), tc.titlesCmd + tc.rootB, "reply " + i + ": the queue goes on")
      answer(s, titlesOk(plain()), 0)
      s.runs = [runOf("ra", tc.rootA), runOf("ra2", tc.rootA), runOf("rb", tc.rootB)]
      compare(s.fetchingRoot, "", "reply " + i + ": a new run list asks nothing of rootA")
      compare(queueOf(s), "")
      compare(s.titleStatus[tc.rootA], "unreachable")
    }
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run.sh tst_run_titles_store`
Expected: FAIL — the new tests fail (e.g. `test_fetches_each_root_with_runs_one_at_a_time_in_registry_order` with a `TypeError` reading `command` of `null`, since nothing launches); Task 1's three tests still pass.

- [ ] **Step 3: Write minimal implementation**

In `core/stores/RunTitlesStore.qml`, replace the handler block

```qml
  onOpenRootChanged: titles.openRootMoved()
  onOpenCardMapChanged: titles.mirrorOpen()
  Component.onCompleted: titles.openRootMoved()
```

with

```qml
  onActiveChanged: if (titles.active) titles.needCheck()
  onProjectRootsChanged: titles.needCheck()
  onOpenRootChanged: titles.openRootMoved()
  onOpenCardMapChanged: titles.mirrorOpen()
  onRunsChanged: titles.needCheck()
  Component.onCompleted: titles.openRootMoved()
```

Then add these functions after `openKey()`:

```qml
  // The usable roots of projectRoots as keys, in registry order, each once:
  // an entry's root must be a non-empty string that does not start with "-".
  function registeredRoots() {
    var list = titles.projectRoots
    var n = list !== null && typeof list === "object" && typeof list.length === "number" ? list.length : 0
    var out = []
    for (var i = 0; i < n; i++) {
      var p = list[i]
      if (p === null || typeof p !== "object" || Array.isArray(p)) continue
      if (typeof p.root !== "string" || p.root === "" || p.root.charAt(0) === "-") continue
      var key = titles.rootKey(p.root)
      if (out.indexOf(key) < 0) out.push(key)
    }
    return out
  }

  // {root: [run, ...]} of the runs in `runs`, keyed by run.project.root as a
  // key; a run with no root belongs to none.
  function runsByRoot() {
    var list = Array.isArray(titles.runs) ? titles.runs : []
    var out = {}
    for (var i = 0; i < list.length; i++) {
      var key = titles.rootKey(Runs.runRoot(list[i]))
      if (key === "") continue
      if (!Runs.hasKey(out, key)) out[key] = []
      out[key].push(list[i])
    }
    return out
  }

  // Queues, in registry order, every registered root other than the open
  // one that has a run in `runs`, is neither queued nor in flight, and has
  // no entry. A queued root's status becomes "loading". Then the queue
  // launches.
  function needCheck() {
    var open = titles.openKey()
    var roots = titles.registeredRoots()
    var byRoot = titles.runsByRoot()
    var queue = titles.titleQueue.slice()
    var status = Runs.copyMap(titles.titleStatus)
    var queued = false
    for (var i = 0; i < roots.length; i++) {
      var root = roots[i]
      if (root === open || !Runs.hasKey(byRoot, root)) continue
      if (root === titles.fetchingRoot || queue.indexOf(root) >= 0) continue
      if (Runs.hasKey(status, root)) continue
      queue.push(root)
      status[root] = "loading"
      queued = true
    }
    if (queued) {
      titles.titleQueue = queue
      titles.titleStatus = status
    }
    titles.launchNext()
  }

  // Launches the head of the queue as fetchingRoot: only while active and
  // nothing is in flight.
  function launchNext() {
    if (!titles.active || titles.fetchingRoot !== "" || titles.titleQueue.length === 0) return
    var queue = titles.titleQueue.slice()
    var root = queue.shift()
    titles.titleQueue = queue
    titles.fetchingRoot = root
    titlesRunner.run([root])
  }

  // fetchingRoot's reply. Exit 0 with an {"ok": true, "titles": {...}}
  // envelope: its string titles become the root's map, its status "ok" and
  // its stale mark goes. Anything else: its status becomes "unreachable" and
  // its map goes. A root that has left the registry or become the open root
  // changes nothing. Then the queue launches and the roots are checked again.
  function replied(stdout, exitCode) {
    var root = titles.fetchingRoot
    titles.fetchingRoot = ""
    if (root !== "" && root !== titles.openKey() && titles.registeredRoots().indexOf(root) >= 0) {
      var env = exitCode === 0 ? Results.parseEnvelope(stdout) : null
      var got = env !== null && env.ok === true ? env.titles : null
      var maps = Runs.copyMap(titles.titlesByRoot)
      var status = Runs.copyMap(titles.titleStatus)
      if (got !== null && typeof got === "object" && !Array.isArray(got)) {
        maps[root] = titles.stringTitles(got)
        status[root] = "ok"
      } else {
        delete maps[root]
        status[root] = "unreachable"
      }
      titles.titlesByRoot = maps
      titles.titleStatus = status
    }
    titles.launchNext()
    titles.needCheck()
  }

  // A new map of each own key of `map` whose value is a string.
  function stringTitles(map) {
    var out = {}
    var keys = Object.keys(map)
    for (var i = 0; i < keys.length; i++) {
      var v = map[keys[i]]
      if (typeof v === "string") Object.defineProperty(out, keys[i], { value: v, enumerable: true, writable: true, configurable: true })
    }
    return out
  }
```

Finally give the `HelperRunner` its reply handler — replace

```qml
  HelperRunner {
    id: titlesRunner
    script: titles.backendDir + "boards/board-titles.py"
    guard: ""
  }
```

with

```qml
  HelperRunner {
    id: titlesRunner
    script: titles.backendDir + "boards/board-titles.py"
    guard: ""
    onFinished: function(stdout, exitCode) { titles.replied(stdout, exitCode) }
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh tst_run_titles_store`
Expected: every `StoresRunTitlesStore` test passes (`Totals: 13 passed, 0 failed`), no `TypeError`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunTitlesStore.qml tests/core/stores/tst_run_titles_store.qml
git commit -m "feat(runs): RunTitlesStore fetches each project's titles one root at a time"
```

---

### Task 3: A root becoming the open root leaves the queue and its fetch is cancelled

**Files:**
- Modify: `core/stores/RunTitlesStore.qml` (`openRootMoved()`)
- Test: `tests/core/stores/tst_run_titles_store.qml`

**Interfaces:**
- Consumes: Task 2's `needCheck()`, `launchNext()`, `titlesRunner.cancel()`.
- Produces: the final `openRootMoved()`.

- [ ] **Step 1: Write the failing tests**

Append inside the `TestCase`, before its closing `}`:

```qml
  // ---- the open root moving

  function test_becoming_the_open_root_cancels_its_fetch() {
    var s = openTitles([tc.rootA, tc.rootB], [runOf("ra", tc.rootA), runOf("rb", tc.rootB)]); if (!s) return
    var procA = s.titlesRunner.current
    compare(argv(procA), tc.titlesCmd + tc.rootA)
    compare(queueOf(s), tc.rootB)
    s.openCardMap = { c1: { title: "One" } }
    s.openRoot = tc.rootA
    compare(argv(s.titlesRunner.current), tc.titlesCmd + tc.rootB, "rootA's fetch is cancelled and rootB launches")
    compare(s.fetchingRoot, tc.rootB)
    compare(queueOf(s), "")
    compare(JSON.stringify(s.titlesByRoot[tc.rootA]), JSON.stringify({ c1: "One" }), "rootA's map is the card map's")
    compare(s.titleStatus[tc.rootA], "ok")
    reply(procA, titlesOk({ m1: "late" }), 0)
    compare(JSON.stringify(s.titlesByRoot[tc.rootA]), JSON.stringify({ c1: "One" }), "a late reply on rootA's old fetch changes nothing")
    compare(s.titleStatus[tc.rootA], "ok")
    compare(s.fetchingRoot, tc.rootB)
  }

  function test_a_queued_root_that_becomes_the_open_root_leaves_the_queue() {
    var s = openTitles([tc.rootA, tc.rootB, tc.rootC],
                       [runOf("ra", tc.rootA), runOf("rb", tc.rootB), runOf("rc", tc.rootC)]); if (!s) return
    compare(queueOf(s), tc.rootB + "," + tc.rootC)
    s.openRoot = tc.rootC
    compare(queueOf(s), tc.rootB)
    compare(s.fetchingRoot, tc.rootA, "the fetch in flight goes on")
    compare(s.titleStatus[tc.rootC], "ok", "rootC's status is its mirror's")
  }

  function test_the_previous_open_root_is_fetched_once_it_is_needed() {
    var s = makeTitles(); if (!s) return
    s.openRoot = tc.rootA
    s.openCardMap = { m1: { title: "Milestone one" } }
    s.projectRoots = registry([tc.rootA])
    s.runs = [runOf("ra", tc.rootA)]
    s.active = true
    compare(s.titlesRunner.current, null)
    s.openRoot = tc.rootB
    compare(Runs.hasKey(s.titlesByRoot, tc.rootA), false, "rootA's mirrored map is gone")
    compare(s.titleStatus[tc.rootA], "loading", "rootA is an ordinary root now")
    compare(argv(s.titlesRunner.current), tc.titlesCmd + tc.rootA)
    answer(s, titlesOk(plain()), 0)
    compare(JSON.stringify(s.titlesByRoot[tc.rootA]), JSON.stringify(plain()))
    compare(s.titleStatus[tc.rootA], "ok")
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run.sh tst_run_titles_store`
Expected: FAIL — `test_becoming_the_open_root_cancels_its_fetch` (rootA's process is still `current`), `test_a_queued_root_that_becomes_the_open_root_leaves_the_queue` (queue still holds rootC) and `test_the_previous_open_root_is_fetched_once_it_is_needed` (rootA has no status, nothing launches).

- [ ] **Step 3: Write minimal implementation**

In `core/stores/RunTitlesStore.qml`, replace the whole `openRootMoved()` function and its comment with:

```qml
  // The open root moved: the previous one's mirrored map and status go (it
  // is an ordinary root from now on); the new one leaves the queue, its
  // fetch in flight is cancelled and its map mirrors openCardMap. Then the
  // queue launches and the roots are checked again.
  function openRootMoved() {
    var open = titles.openKey()
    var prev = titlesState.mirrored
    if (prev !== "" && prev !== open) {
      var maps = Runs.copyMap(titles.titlesByRoot)
      var status = Runs.copyMap(titles.titleStatus)
      delete maps[prev]
      delete status[prev]
      titles.titlesByRoot = maps
      titles.titleStatus = status
    }
    titlesState.mirrored = open
    if (open !== "") {
      if (titles.titleQueue.indexOf(open) >= 0) titles.titleQueue = titles.titleQueue.filter(function(r) { return r !== open })
      if (titles.fetchingRoot === open) {
        titlesRunner.cancel()
        titles.fetchingRoot = ""
      }
      titles.mirrorOpen()
    }
    titles.launchNext()
    titles.needCheck()
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh tst_run_titles_store`
Expected: every `StoresRunTitlesStore` test passes (`Totals: 16 passed, 0 failed`), exit 0.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunTitlesStore.qml tests/core/stores/tst_run_titles_store.qml
git commit -m "feat(runs): RunTitlesStore never fetches the open root and refetches the one it left"
```

---

### Task 4: A missing id is asked about once

**Files:**
- Modify: `core/stores/RunTitlesStore.qml` (`needCheck()`, `titlesState`, new `namedIds`, `missingIds`)
- Test: `tests/core/stores/tst_run_titles_store.qml`

**Interfaces:**
- Consumes: Task 2's `runsByRoot()`, `registeredRoots()`, `launchNext()`.
- Produces: `namedIds(run) -> [string]`, `missingIds(rootRuns, map, asked) -> [string]`, private `titlesState.asked: {root: {id: true}}`. Task 5 empties `titlesState.asked` and replaces `needCheck()` again.

- [ ] **Step 1: Write the failing tests**

Append inside the `TestCase`, before its closing `}`:

```qml
  // ---- missing ids

  function test_a_missing_id_is_asked_about_once() {
    var s = openTitles([tc.rootA], [runOf("r1", tc.rootA)]); if (!s) return
    var known = { m1: "Milestone one", st1: "Story one" }
    answer(s, titlesOk(known), 0)
    compare(s.fetchingRoot, "")
    var withS9 = runOf("r2", tc.rootA, [{ card_id: "st1", subtasks: [{ card_id: "s9" }] }])
    s.runs = [runOf("r1", tc.rootA), withS9]
    compare(s.fetchingRoot, tc.rootA, "s9 is missing from rootA's ok map: one more fetch")
    compare(argv(s.titlesRunner.current), tc.titlesCmd + tc.rootA)
    compare(s.titleStatus[tc.rootA], "loading")
    compare(JSON.stringify(s.titlesByRoot[tc.rootA]), JSON.stringify(known), "the map stays while it loads")
    answer(s, titlesOk(known), 0)
    compare(s.titleStatus[tc.rootA], "ok")
    compare(s.fetchingRoot, "", "the reply still lacks s9: no third fetch")
    s.runs = [runOf("r1", tc.rootA), withS9]
    compare(s.fetchingRoot, "", "nor after the run list is set again")
    var withS10 = runOf("r3", tc.rootA, [{ card_id: "st1", subtasks: [{ card_id: "s10" }] }])
    s.runs = [runOf("r1", tc.rootA), withS9, withS10]
    compare(s.fetchingRoot, tc.rootA, "a new missing id s10 asks once more")
    answer(s, titlesOk(known), 0)
    compare(s.fetchingRoot, "")
    compare(s.titleStatus[tc.rootA], "ok")
  }

  function test_a_runs_own_card_id_counts() {
    var s = openTitles([tc.rootA], [runOf("r1", tc.rootA)]); if (!s) return
    answer(s, titlesOk(plain()), 0)
    var task = runOf("r2", tc.rootA)
    task.card_id = "t7"
    s.runs = [runOf("r1", tc.rootA), task]
    compare(s.fetchingRoot, tc.rootA, "t7 is missing: one more fetch")
  }

  function test_the_synthetic_stories_never_ask_for_a_refetch() {
    var s = openTitles([tc.rootA], [runOf("r1", tc.rootA)]); if (!s) return
    answer(s, titlesOk(plain()), 0)
    s.runs = [runOf("r1", tc.rootA, [{ card_id: "integrate", subtasks: [{ card_id: "x1" }] },
                                     { card_id: "bases", subtasks: [] }])]
    compare(s.fetchingRoot, "", "integrate and bases are not ids brd knows")
    compare(s.titleStatus[tc.rootA], "ok")
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run.sh tst_run_titles_store`
Expected: FAIL — `test_a_missing_id_is_asked_about_once` ("s9 is missing from rootA's ok map: one more fetch": actual `""`) and `test_a_runs_own_card_id_counts`. `test_the_synthetic_stories_never_ask_for_a_refetch` already passes (nothing refetches yet) and must keep passing after Step 3.

- [ ] **Step 3: Write minimal implementation**

In `core/stores/RunTitlesStore.qml`, add after `runsByRoot()`:

```qml
  // The milestone, story and card ids `run` names, each a non-empty string:
  // milestone_id, story_id, card_id, the card_id of each tree story but
  // "integrate" and "bases", and the card_id of each tree subtask.
  function namedIds(run) {
    var out = []
    function add(id) { if (typeof id === "string" && id !== "") out.push(id) }
    if (run === null || typeof run !== "object") return out
    add(run.milestone_id)
    add(run.story_id)
    add(run.card_id)
    var tree = run.tree !== null && typeof run.tree === "object" ? run.tree : {}
    var stories = Array.isArray(tree.stories) ? tree.stories : []
    for (var i = 0; i < stories.length; i++) {
      var story = stories[i]
      if (story !== null && typeof story === "object" && story.card_id !== "integrate" && story.card_id !== "bases") add(story.card_id)
    }
    var subtasks = Array.isArray(tree.subtasks) ? tree.subtasks : []
    for (var j = 0; j < subtasks.length; j++) {
      var subtask = subtasks[j]
      if (subtask !== null && typeof subtask === "object") add(subtask.card_id)
    }
    return out
  }

  // The ids the runs `rootRuns` name that `map` has no own key for and
  // `asked` ({id: true}) does not hold, each once.
  function missingIds(rootRuns, map, asked) {
    var out = []
    for (var i = 0; i < rootRuns.length; i++) {
      var ids = titles.namedIds(rootRuns[i])
      for (var j = 0; j < ids.length; j++) {
        var id = ids[j]
        if (!Runs.hasKey(map, id) && !Runs.hasKey(asked, id) && out.indexOf(id) < 0) out.push(id)
      }
    }
    return out
  }
```

Replace the whole `needCheck()` function and its comment with:

```qml
  // Queues, in registry order, every registered root other than the open
  // one that has a run in `runs`, is neither queued nor in flight, and has
  // no entry, or an ok map that lacks an id one of its runs names and that
  // was not asked about yet (those ids are then marked asked). A queued
  // root's status becomes "loading"; its map stays until the reply. Then
  // the queue launches.
  function needCheck() {
    var open = titles.openKey()
    var roots = titles.registeredRoots()
    var byRoot = titles.runsByRoot()
    var queue = titles.titleQueue.slice()
    var status = Runs.copyMap(titles.titleStatus)
    var asked = Runs.copyMap(titlesState.asked)
    var queued = false
    for (var i = 0; i < roots.length; i++) {
      var root = roots[i]
      if (root === open || !Runs.hasKey(byRoot, root)) continue
      if (root === titles.fetchingRoot || queue.indexOf(root) >= 0) continue
      var want = false
      if (!Runs.hasKey(status, root)) {
        want = true
      } else if (status[root] === "ok") {
        var map = Runs.hasKey(titles.titlesByRoot, root) ? titles.titlesByRoot[root] : {}
        var mine = Runs.hasKey(asked, root) ? asked[root] : {}
        var missing = titles.missingIds(byRoot[root], map, mine)
        if (missing.length > 0) {
          want = true
          var next = Runs.copyMap(mine)
          for (var j = 0; j < missing.length; j++) next[missing[j]] = true
          asked[root] = next
        }
      }
      if (!want) continue
      queue.push(root)
      status[root] = "loading"
      queued = true
    }
    if (queued) {
      titles.titleQueue = queue
      titles.titleStatus = status
      titlesState.asked = asked
    }
    titles.launchNext()
  }
```

Replace the `titlesState` object with:

```qml
  // Bookkeeping kept apart so consumers cannot write it.
  QtObject {
    id: titlesState
    property string mirrored: ""   // the root whose map mirrors openCardMap; "" when none
    property var asked: ({})       // {root: {id: true}}: missing ids already asked about
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh tst_run_titles_store`
Expected: every `StoresRunTitlesStore` test passes (`Totals: 19 passed, 0 failed`), exit 0.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunTitlesStore.qml tests/core/stores/tst_run_titles_store.qml
git commit -m "feat(runs): RunTitlesStore refetches a root once for an id its map lacks"
```

---

### Task 5: Invalidation — refreshTitles(), the panel reopening and registry changes

**Files:**
- Modify: `core/stores/RunTitlesStore.qml` (handlers, `needCheck()`, `replied()`, `titlesState`, new `keptOf`, `refreshTitles`, `registryChanged`)
- Test: `tests/core/stores/tst_run_titles_store.qml`

**Interfaces:**
- Consumes: everything above.
- Produces: public `refreshTitles()` (the footer's future **Refresh titles** button calls it); `registryChanged()`; `keptOf(map, keep) -> map`; private `titlesState.stale: {root: true}`.

- [ ] **Step 1: Write the failing tests**

Append inside the `TestCase`, before its closing `}`:

```qml
  // ---- invalidation

  // An open store with runs of rootA and rootB: rootA ok, rootB unreachable,
  // nothing in flight.
  function okAndUnreachable() {
    var s = openTitles([tc.rootA, tc.rootB], [runOf("ra", tc.rootA), runOf("rb", tc.rootB)]); if (!s) return null
    answer(s, titlesOk(plain()), 0)
    answer(s, "", 1)
    compare(s.titleStatus[tc.rootA], "ok")
    compare(s.titleStatus[tc.rootB], "unreachable")
    compare(s.fetchingRoot, "")
    return s
  }

  function test_refresh_titles_fetches_every_root_again_in_registry_order() {
    var s = okAndUnreachable(); if (!s) return
    s.refreshTitles()
    compare(argv(s.titlesRunner.current), tc.titlesCmd + tc.rootA)
    compare(s.fetchingRoot, tc.rootA)
    compare(queueOf(s), tc.rootB)
    compare(s.titleStatus[tc.rootA], "loading")
    compare(s.titleStatus[tc.rootB], "loading")
    compare(JSON.stringify(s.titlesByRoot[tc.rootA]), JSON.stringify(plain()), "rootA's stale map stays while it loads")
    answer(s, titlesOk(plain()), 0)
    compare(s.titleStatus[tc.rootA], "ok")
    compare(s.fetchingRoot, tc.rootB)
    answer(s, titlesOk(plain()), 0)
    compare(s.titleStatus[tc.rootB], "ok")
    compare(s.fetchingRoot, "", "a fresh ok map is not stale")
  }

  function test_refresh_titles_queues_no_root_twice() {
    var s = openTitles([tc.rootA, tc.rootB], [runOf("ra", tc.rootA), runOf("rb", tc.rootB)]); if (!s) return
    var first = s.titlesRunner.current
    s.refreshTitles()
    verify(s.titlesRunner.current === first, "the fetch in flight is not relaunched")
    compare(s.fetchingRoot, tc.rootA)
    compare(queueOf(s), tc.rootB)
  }

  function test_reopening_the_panel_fetches_every_root_again() {
    var s = okAndUnreachable(); if (!s) return
    s.active = false
    compare(s.fetchingRoot, "")
    compare(s.titleStatus[tc.rootA], "ok", "closing drops nothing")
    compare(JSON.stringify(s.titlesByRoot[tc.rootA]), JSON.stringify(plain()))
    s.active = true
    compare(argv(s.titlesRunner.current), tc.titlesCmd + tc.rootA)
    compare(s.fetchingRoot, tc.rootA)
    compare(queueOf(s), tc.rootB)
  }

  function test_a_reopening_fetches_nothing_for_a_root_without_runs() {
    var s = okAndUnreachable(); if (!s) return
    s.active = false
    s.runs = [runOf("rb", tc.rootB)]
    s.active = true
    compare(s.fetchingRoot, tc.rootB, "only rootB, which still has runs")
    compare(argv(s.titlesRunner.current), tc.titlesCmd + tc.rootB)
    compare(queueOf(s), "")
    compare(s.titleStatus[tc.rootA], "ok")
    compare(JSON.stringify(s.titlesByRoot[tc.rootA]), JSON.stringify(plain()), "rootA's map stays")
  }

  function test_a_reopening_refetches_a_root_with_a_missing_id_once() {
    var s = openTitles([tc.rootA], [runOf("r1", tc.rootA, [{ card_id: "st1", subtasks: [{ card_id: "s9" }] }])]); if (!s) return
    var known = { m1: "Milestone one", st1: "Story one" }
    answer(s, titlesOk(known), 0)
    compare(s.fetchingRoot, tc.rootA, "s9 is missing: one more fetch")
    answer(s, titlesOk(known), 0)
    compare(s.fetchingRoot, "")
    s.active = false
    s.active = true
    compare(s.fetchingRoot, tc.rootA, "the opening fetches rootA again")
    answer(s, titlesOk(known), 0)
    compare(s.titleStatus[tc.rootA], "ok")
    compare(s.fetchingRoot, "", "that fetch asked about s9: no loop")
  }

  function test_a_root_that_leaves_the_registry_loses_its_titles() {
    var s = openTitles([tc.rootA, tc.rootB, tc.rootC],
                       [runOf("ra", tc.rootA), runOf("rb", tc.rootB), runOf("rc", tc.rootC)]); if (!s) return
    answer(s, titlesOk(plain()), 0)
    answer(s, titlesOk(plain()), 0)
    answer(s, titlesOk(plain()), 0)
    compare(s.fetchingRoot, "")
    s.projectRoots = registry([tc.rootA, tc.rootC])
    compare(Runs.hasKey(s.titlesByRoot, tc.rootB), false)
    compare(Runs.hasKey(s.titleStatus, tc.rootB), false)
    compare(s.titleStatus[tc.rootA], "ok")
    compare(s.titleStatus[tc.rootC], "ok")
    compare(s.fetchingRoot, "", "the roots still registered are not fetched again")
  }

  function test_a_queued_root_that_leaves_the_registry_leaves_the_queue() {
    var s = openTitles([tc.rootA, tc.rootB, tc.rootC],
                       [runOf("ra", tc.rootA), runOf("rb", tc.rootB), runOf("rc", tc.rootC)]); if (!s) return
    compare(queueOf(s), tc.rootB + "," + tc.rootC)
    s.projectRoots = registry([tc.rootA, tc.rootC])
    compare(queueOf(s), tc.rootC)
    compare(Runs.hasKey(s.titleStatus, tc.rootB), false)
    compare(s.fetchingRoot, tc.rootA)
  }

  function test_a_root_in_flight_that_leaves_the_registry_is_cancelled() {
    var s = openTitles([tc.rootA, tc.rootB, tc.rootC],
                       [runOf("ra", tc.rootA), runOf("rb", tc.rootB), runOf("rc", tc.rootC)]); if (!s) return
    answer(s, titlesOk(plain()), 0)
    var procB = s.titlesRunner.current
    compare(argv(procB), tc.titlesCmd + tc.rootB)
    s.projectRoots = registry([tc.rootA, tc.rootC])
    compare(argv(s.titlesRunner.current), tc.titlesCmd + tc.rootC, "rootB's fetch is cancelled and rootC launches")
    compare(s.fetchingRoot, tc.rootC)
    compare(queueOf(s), "")
    reply(procB, titlesOk(plain()), 0)
    compare(Runs.hasKey(s.titlesByRoot, tc.rootB), false, "a late reply on rootB's old fetch changes nothing")
    compare(Runs.hasKey(s.titleStatus, tc.rootB), false)
    compare(s.fetchingRoot, tc.rootC)
  }

  function test_a_registry_change_asks_an_unreachable_root_again() {
    var s = openTitles([tc.rootA, tc.rootB, tc.rootC], [runOf("ra", tc.rootA), runOf("rc", tc.rootC)]); if (!s) return
    answer(s, titlesOk(plain()), 0)
    answer(s, "", 1)
    compare(s.titleStatus[tc.rootC], "unreachable")
    compare(s.fetchingRoot, "")
    s.projectRoots = registry([tc.rootA, tc.rootC])
    compare(argv(s.titlesRunner.current), tc.titlesCmd + tc.rootC, "rootC is still registered: asked again")
    compare(s.titleStatus[tc.rootC], "loading")
    compare(s.titleStatus[tc.rootA], "ok")
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run.sh tst_run_titles_store`
Expected: FAIL — the refresh tests with `TypeError: Property 'refreshTitles' of object ... is not a function`; `test_reopening_the_panel_fetches_every_root_again`, `test_a_reopening_fetches_nothing_for_a_root_without_runs`, `test_a_reopening_refetches_a_root_with_a_missing_id_once` (nothing is fetched on reopening); the four registry tests (rootB keeps its entry; rootC is not asked again).

- [ ] **Step 3: Write minimal implementation**

In `core/stores/RunTitlesStore.qml`:

(a) Replace the handler block

```qml
  onActiveChanged: if (titles.active) titles.needCheck()
  onProjectRootsChanged: titles.needCheck()
```

with

```qml
  onActiveChanged: if (titles.active) titles.refreshTitles()
  onProjectRootsChanged: titles.registryChanged()
```

(b) Add, right after the handler block (before `rootKey`):

```qml
  // Starts over the way each opening does: every ok map but the open
  // project's is marked stale, every "unreachable" status goes and every
  // missing id may be asked about again; then the roots are checked. A root
  // already queued or in flight is not queued twice.
  function refreshTitles() {
    var open = titles.openKey()
    var stale = Runs.copyMap(titlesState.stale)
    for (var root in titles.titleStatus) {
      if (Runs.hasKey(titles.titleStatus, root) && titles.titleStatus[root] === "ok" && root !== open) stale[root] = true
    }
    titlesState.stale = stale
    titles.titleStatus = titles.keptOf(titles.titleStatus, function(root, st) { return st !== "unreachable" })
    titlesState.asked = {}
    titles.needCheck()
  }

  // The registry changed: every root it no longer names, unless it is the
  // open root, loses its map, status, stale mark and asked ids and leaves
  // the queue, and its fetch in flight is cancelled; every "unreachable"
  // status goes. Then the queue launches and the roots are checked again.
  function registryChanged() {
    var roots = titles.registeredRoots()
    var open = titles.openKey()
    function kept(root) { return root === open || roots.indexOf(root) >= 0 }
    titles.titlesByRoot = titles.keptOf(titles.titlesByRoot, function(root) { return kept(root) })
    titles.titleStatus = titles.keptOf(titles.titleStatus, function(root, st) { return kept(root) && st !== "unreachable" })
    titlesState.stale = titles.keptOf(titlesState.stale, function(root) { return kept(root) })
    titlesState.asked = titles.keptOf(titlesState.asked, function(root) { return kept(root) })
    var queue = titles.titleQueue.filter(function(root) { return kept(root) })
    if (queue.length !== titles.titleQueue.length) titles.titleQueue = queue
    if (titles.fetchingRoot !== "" && !kept(titles.fetchingRoot)) {
      titlesRunner.cancel()
      titles.fetchingRoot = ""
    }
    titles.launchNext()
    titles.needCheck()
  }

  // A new map of the own keys of `map` for which keep(key, value) is true.
  function keptOf(map, keep) {
    var out = {}
    for (var key in map) {
      if (Runs.hasKey(map, key) && keep(key, map[key])) out[key] = map[key]
    }
    return out
  }
```

(c) Replace the whole `needCheck()` function and its comment with the final version:

```qml
  // Queues, in registry order, every registered root other than the open
  // one that has a run in `runs`, is neither queued nor in flight, and has
  // no entry, or an ok map that is stale or lacks an id one of its runs
  // names and that was not asked about yet (those ids are then marked
  // asked). A queued root's status becomes "loading"; its map stays until
  // the reply. Then the queue launches.
  function needCheck() {
    var open = titles.openKey()
    var roots = titles.registeredRoots()
    var byRoot = titles.runsByRoot()
    var queue = titles.titleQueue.slice()
    var status = Runs.copyMap(titles.titleStatus)
    var asked = Runs.copyMap(titlesState.asked)
    var queued = false
    for (var i = 0; i < roots.length; i++) {
      var root = roots[i]
      if (root === open || !Runs.hasKey(byRoot, root)) continue
      if (root === titles.fetchingRoot || queue.indexOf(root) >= 0) continue
      var want = false
      if (!Runs.hasKey(status, root)) {
        want = true
      } else if (status[root] === "ok") {
        if (Runs.hasKey(titlesState.stale, root)) want = true
        var map = Runs.hasKey(titles.titlesByRoot, root) ? titles.titlesByRoot[root] : {}
        var mine = Runs.hasKey(asked, root) ? asked[root] : {}
        var missing = titles.missingIds(byRoot[root], map, mine)
        if (missing.length > 0) {
          want = true
          var next = Runs.copyMap(mine)
          for (var j = 0; j < missing.length; j++) next[missing[j]] = true
          asked[root] = next
        }
      }
      if (!want) continue
      queue.push(root)
      status[root] = "loading"
      queued = true
    }
    if (queued) {
      titles.titleQueue = queue
      titles.titleStatus = status
      titlesState.asked = asked
    }
    titles.launchNext()
  }
```

(d) In `replied()`, clear the stale mark on an ok reply — replace

```qml
      if (got !== null && typeof got === "object" && !Array.isArray(got)) {
        maps[root] = titles.stringTitles(got)
        status[root] = "ok"
      } else {
```

with

```qml
      if (got !== null && typeof got === "object" && !Array.isArray(got)) {
        maps[root] = titles.stringTitles(got)
        status[root] = "ok"
        if (Runs.hasKey(titlesState.stale, root)) titlesState.stale = titles.keptOf(titlesState.stale, function(key) { return key !== root })
      } else {
```

(e) Replace the `titlesState` object with the final version:

```qml
  // Bookkeeping kept apart so consumers cannot write it.
  QtObject {
    id: titlesState
    property string mirrored: ""   // the root whose map mirrors openCardMap; "" when none
    property var asked: ({})       // {root: {id: true}}: missing ids already asked about since the last opening
    property var stale: ({})       // {root: true}: ok maps to fetch again the next time they are needed
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh tst_run_titles_store`
Expected: every `StoresRunTitlesStore` test passes (`Totals: 28 passed, 0 failed`), no `TypeError`, exit 0. In particular the Task 2 tests `test_fetches_each_root_with_runs_one_at_a_time_in_registry_order` and `test_nothing_launches_while_closed` still pass: opening keeps `"loading"` statuses and an already-queued root is not queued twice.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunTitlesStore.qml tests/core/stores/tst_run_titles_store.qml
git commit -m "feat(runs): RunTitlesStore refetches on refreshTitles, reopening and registry changes"
```

---

### Task 6: Compose `app.runTitles` in App and document it

**Files:**
- Modify: `core/stores/App.qml` (after the `runAlerts` block, before the `runDispatch` comment)
- Modify: `tests/core/stores/tst_app_runs.qml` (header comment lines 1–14; append two tests)
- Modify: `tests/architecture/test_run_store_docs.py` (docstring line 1, `STORES`, `README_TOKENS`)
- Modify: `docs/architecture.md` (new bullet after line 93, the `RunDispatchStore.qml` bullet)

**Interfaces:**
- Consumes: `RunTitlesStore` (Tasks 1–5); `app.backendDir`, `app.panelOpen`, `app.runs.projectRoots`, `app.runs.project`, `app.board.cardMap`, `app.runs.runs`.
- Produces: `app.runTitles` (a `RunTitlesStore`) for the UI cards that will read `titlesByRoot` / `titleStatus` and call `refreshTitles()`.

- [ ] **Step 1: Write the failing tests**

(a) In `tests/architecture/test_run_store_docs.py`, change line 1 from

```python
"""docs/architecture.md describes the four run stores as App composes them; README.md names none.
```

to

```python
"""docs/architecture.md describes the five run stores as App composes them; README.md names none.
```

and replace

```python
STORES = ["RunStore", "RunControlStore", "RunAlertsStore", "RunDispatchStore"]
```

with

```python
STORES = ["RunStore", "RunControlStore", "RunAlertsStore", "RunDispatchStore", "RunTitlesStore"]
```

and replace

```python
README_TOKENS = ["RunStore", "RunControlStore", "RunAlertsStore", "RunDispatchStore",
                 "app.runs", "app.runControl", "app.runAlerts", "app.runDispatch", "shim"]
```

with

```python
README_TOKENS = ["RunStore", "RunControlStore", "RunAlertsStore", "RunDispatchStore", "RunTitlesStore",
                 "app.runs", "app.runControl", "app.runAlerts", "app.runDispatch", "app.runTitles", "shim"]
```

(b) In `tests/core/stores/tst_app_runs.qml`, replace the header comment's last lines

```qml
// as it routes run control's runSettingsSaveFailed back to the dispatch. The
// stores' own behaviour is tested in
// tst_run_store.qml, tst_run_alerts_store.qml, tst_run_control_store.qml and
// tst_run_dispatch_store.qml.
```

with

```qml
// as it routes run control's runSettingsSaveFailed back to the dispatch, and
// `app.runTitles`, which App feeds with the registry, the open project's root
// and card map, the run list and the panel-open flag. The stores' own
// behaviour is tested in tst_run_store.qml, tst_run_alerts_store.qml,
// tst_run_control_store.qml, tst_run_dispatch_store.qml and
// tst_run_titles_store.qml.
```

Then append inside the `TestCase`, before its closing `}`:

```qml
  // ---- the run titles

  function test_app_composes_run_titles_wired_to_the_run_store_and_board() {
    var app = make(); if (!app) return
    verify(app.runTitles, "App composes the titles store as app.runTitles")
    compare(app.runTitles.backendDir, "/plugin/core/backend/")
    compare(JSON.stringify(app.runTitles.projectRoots), JSON.stringify(app.runs.projectRoots))
    compare(app.runTitles.openRoot, tc.pA.root_path)
    compare(app.runTitles.active, false)
    app.panelOpen = true
    compare(app.runTitles.active, true, "active follows app.panelOpen")
    app.board.applyTreeData([{ id: "c1", title: "One", status: "todo", children: [] }])
    compare(JSON.stringify(app.runTitles.openCardMap), JSON.stringify(app.board.cardMap))
    compare(app.runTitles.titlesByRoot[tc.pA.root_path].c1, "One")
    compare(app.runTitles.titleStatus[tc.pA.root_path], "ok")
  }

  function test_app_runs_no_board_titles_for_the_open_project() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runs.runs.length, 1)
    compare(JSON.stringify(app.runTitles.runs), JSON.stringify(app.runs.runs))
    compare(app.runTitles.titlesRunner.current, null, "pA is open and pB has no runs: no board-titles.py")
    compare(app.runTitles.titleStatus[tc.pA.root_path], "ok")
  }

  function test_app_fetches_titles_for_another_project_with_runs() {
    var app = openApp([runningIn("r1")], [runningIn("r2", tc.pB.root_path)]); if (!app) return
    compare(argv(app.runTitles.titlesRunner.current),
            "python3|/plugin/core/backend/boards/board-titles.py|" + tc.pB.root_path)
    compare(app.runTitles.fetchingRoot, tc.pB.root_path)
    compare(app.runTitles.titleStatus[tc.pB.root_path], "loading")
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest tests/architecture/test_run_store_docs.py -q` (or the `uv run --with pytest …` form)
Expected: FAIL — `test_each_run_store_has_one_bullet_in_order` (`0 top-level - \`RunTitlesStore.qml\` bullets, want 1`), and the `[RunTitlesStore]` cases of `test_each_bullet_names_its_app_handle` / `test_each_bullet_names_every_input_and_routed_signal_app_wires` (`App composes no RunTitlesStore`).

Run: `bash tests/run.sh tst_app_runs`
Expected: FAIL — the three new `StoresAppRuns` tests fail (`app.runTitles` is undefined: `verify` fails / `TypeError`). (The script exits non-zero already in its pytest phase; read the QML section too.)

- [ ] **Step 3: Write minimal implementation**

(a) In `core/stores/App.qml`, insert after the closing `}` of the `runAlerts` block (the block ending with `projectRoots: app.runs.projectRoots` / `  }`) and before the comment `// The dispatch never imports the run store or run control: …`:

```qml

  // The run titles never import the run or board store: App hands them the
  // backend directory, the panel-open flag, the registry, the open project's
  // root and card map and the run list. App routes no signal from them.
  readonly property RunTitlesStore runTitles: RunTitlesStore {
    backendDir: app.backendDir
    active: app.panelOpen
    projectRoots: app.runs.projectRoots
    openRoot: app.runs.project
    openCardMap: app.board.cardMap
    runs: app.runs.runs
  }
```

(b) In `docs/architecture.md`, insert this single line directly after the `- \`RunDispatchStore.qml\` …` bullet (line 93) and before the blank line that precedes `Other \`ui/\` pieces:`:

```markdown
- `RunTitlesStore.qml` the run titles: each registered project's `{id: title}` map, for every project with runs. It never reaches for another store: `App` composes it as `app.runTitles` and hands it `backendDir`, `active` (App's `panelOpen`), `projectRoots` (`app.runs.projectRoots`), `openRoot` (`app.runs.project`), `openCardMap` (`app.board.cardMap`) and `runs` (`app.runs.runs`); App routes no signal from it. Its states are `titlesByRoot` (`{root: {id: title}}`) and `titleStatus` (`{root: "loading" | "ok" | "unreachable"}`), keyed by the root with its trailing `/` removed and replaced, never changed in place; callers look up `titlesByRoot[run.project.root]`. The open project's map is `Runs.titlesFromCards(openCardMap)` with status `ok` and is never fetched: a root that becomes the open root leaves the queue and its fetch is cancelled, and the root the open project left loses its mirrored entry and is fetched like any other the next time it is needed. Every other registered root with a run in `runs` is fetched with `board-titles.py ROOT` on the store's one `HelperRunner` (`titlesRunner`), one root at a time from `titleQueue` (registry order, each root at most once, never the root in flight, `fetchingRoot`) and only while `active` -- a fetch in flight still lands after closing --, when the root has no entry, when its `ok` map is stale (each opening and `refreshTitles()` mark every `ok` map stale, clear every `unreachable` status and let every missing id be asked about again), or when a run names a milestone, story or card id its `ok` map lacks that was not already asked about. A queued root is `loading` and keeps its map until the reply. A reply other than an ok `titles` object -- `ProjectNotFoundError`, a missing brd, a vanished root, the helper's own 30 s timeout, unparsable output -- makes the root `unreachable` and drops its map, with no toast, banner or error text; it is not asked again until `refreshTitles()`, the next opening or a registry change. A registry change drops every removed root's entry, takes it off the queue, cancels its fetch and clears every `unreachable` status. Closing the panel and a run list change drop nothing.
```

Do not touch `README.md`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tests/architecture/test_run_store_docs.py -q`
Expected: all pass.

Run: `bash tests/run.sh`
Expected: pytest all green (including `tests/architecture/test_layers.py`, `test_icon_glyphs.py`, `test_run_store_docs.py`, `test_run_store_callers.py`); every QML file's `Totals:` shows `0 failed`, `StoresAppRuns` includes the three new tests passing, `StoresRunTitlesStore` 28 passed; no `TypeError`/`ReferenceError`/`Unable to assign`/`is not a function` lines; exit status 0.

- [ ] **Step 5: Commit**

```bash
git add core/stores/App.qml tests/core/stores/tst_app_runs.qml tests/architecture/test_run_store_docs.py docs/architecture.md
git commit -m "feat(runs): App composes RunTitlesStore as app.runTitles; document it"
```

---

## Spec coverage check

| Spec item | Task |
|---|---|
| Inputs table, `titlesRunner` alias, script path | 1, 2 |
| Root key / registered root / fetchable root | 1 (`rootKey`), 2 (`registeredRoots`, `runsByRoot`, `needCheck`) |
| Ids a run names, `Runs.hasKey` missing | 4 |
| State `titlesByRoot` / `titleStatus` / `titleQueue` / `fetchingRoot`, replaced never mutated | 1–5 |
| The open project mirror, never queued/fetched, cancel on becoming open, old open root removed | 1, 3 |
| Need check reasons 1, 2, 3; triggers (runs, projectRoots, openRoot, active, reply, refresh) | 2, 3, 4, 5 |
| Launching only while active; in-flight reply applied after closing | 2 |
| Reply ok / unreachable (4 shapes), unreachable not stalling the queue | 2 |
| Invalidation: panel opens, closes, `refreshTitles()`, registry change, runs change | 5 |
| Never: two in flight, queued twice | 2, 5 |
| App wiring after `runAlerts`, comment, no routed signal | 6 |
| Docs bullet after `RunDispatchStore.qml`; README untouched | 6 |
| Tests 1–12 (`tst_run_titles_store.qml`), 13 (`tst_app_runs.qml`), 14 (`test_run_store_docs.py`) | 1–6 |
<!-- task-pipeline: validated -->
