# 3.1 RunTitlesStore: per-project title maps — design

Card `2d260910-3155-43a0-8c11-fe7d12756cdb`, a subtask of story `b477c51f` (History and
titles stores). Parent design: `docs/superpowers/specs/2026-10-05-run-history-titles-design.md`
(below, "parent"). This card adds `core/stores/RunTitlesStore.qml`, composes it in `App.qml`
as `app.runTitles`, and documents it. It puts the parent's **Cache and invalidation** section
(parent :76-94) into a store. No screen reads the store yet.

## Inherited constraints

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

## Behaviour

### Inputs

| property | type | App binds it to |
|---|---|---|
| `backendDir` | string | `app.backendDir` |
| `active` | bool | `app.panelOpen` |
| `projectRoots` | `[{root, name}]` | `app.runs.projectRoots` |
| `openRoot` | string | `app.runs.project` |
| `openCardMap` | object | `app.board.cardMap` |
| `runs` | normalized runs | `app.runs.runs` |

### Roots

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

### Ids a run names

A run names these ids. Each counts only when it is a non-empty string:

- `milestone_id`, `story_id` and `card_id`;
- the `card_id` of each entry of `run.tree.stories`, except `"integrate"` and `"bases"`;
- the `card_id` of each entry of `run.tree.subtasks`.

An id is **missing** from a map when the map has no own key for it (`Runs.hasKey`).

### State

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

### The open project

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

### When a root is queued

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

### Launching

- A fetch launches only while `active` is true, `fetchingRoot` is `""` and `titleQueue` is
  not empty.
- The launch takes the head of the queue as `fetchingRoot` and runs
  `python3 <backendDir>boards/board-titles.py ROOT`, with `ROOT` the root key.
- While `active` is false, queued roots stay queued and nothing launches. A fetch already in
  flight still lands and is applied.

### A reply

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

### Invalidation

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

### Never

- The store never fetches the open root, a root that is not registered, or a root with no run
  in `runs`.
- It never has two fetches in flight, and never queues a root twice.
- It never writes, never shows an error, and never reaches for another store.

### App wiring

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

### Docs

`docs/architecture.md` gains one top-level bullet, `` - `RunTitlesStore.qml` … ``, after the
`RunDispatchStore.qml` bullet. It names:

- `app.runTitles`;
- every bound input, each backticked: `backendDir`, `active`, `projectRoots`, `openRoot`,
  `openCardMap`, `runs`;
- the states, `titlesByRoot` and `titleStatus`;
- `refreshTitles()`;
- the fetch rules above, in one paragraph.

`README.md` does not name the store.

## Tests (TDD: written first, seen failing)

### `tests/core/stores/tst_run_titles_store.qml`

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

### `tests/core/stores/tst_app_runs.qml`

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

### `tests/architecture/test_run_store_docs.py`

Tier: architecture doc test. It pins every run store's App wiring to its docs bullet.

14. `STORES` gains `"RunTitlesStore"` after `"RunDispatchStore"`, and the module docstring
    says "five". The existing parametrized tests then require the new bullet:
    - in order;
    - naming `` `app.runTitles` ``;
    - naming every input App binds.

    `README_TOKENS` gains `"RunTitlesStore"` and `"app.runTitles"`.

### Unchanged and still green

These suites need no change and must pass:

- `tests/architecture/test_layers.py` (store imports, no duplicated components);
- `test_icon_glyphs.py` (the store shows no glyph);
- the whole `bash tests/run.sh`.

## Out of scope

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
