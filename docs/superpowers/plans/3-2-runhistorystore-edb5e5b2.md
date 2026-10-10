# 3.2 RunHistoryStore: older runs a page at a time — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `core/stores/RunHistoryStore.qml`, a store that fetches each snapshot root's older runs a page at a time with `runs-history.py`, keeps them in `historyByProject`, folds window overflow and resumed runs on every snapshot change, and drops pages on a query change, the panel closing or a root leaving; compose it in `App.qml` as `app.runHistory` and document it.

**Architecture:** A `Scope` store with plain inputs App binds (`backendDir`, `active`, `snapshotByProject`, `runFilter`) plus two unbound inputs (`finishedState`, `finishedAge`). One replaced-never-mutated state map `historyByProject` (`{root: {runs, more, loading, error}}`). One `HelperRunner` per root, created lazily from an inline `Component` on that root's first launch and kept in a private `QtObject` (`historyState.runners`); `runnerFor(root)` is the test seam. Each runner gives latest-wins per root for free (`HelperRunner.run` supersedes, `cancel()` drops); roots page independently. `showOlder` launches, `replied` applies a page, `snapshotChanged` folds overflow and resumes, `queryChanged`/`dropAll` drop pages.

**Tech Stack:** QML (QtQml, Quickshell, Quickshell.Io), the pure JS libraries `core/domain/runs.js` and `core/domain/results.js`, QtTest (`qmltestrunner`) with stubbed `Process` objects (`tests/stubs/Quickshell/Io/Process.qml`), pytest for the architecture/doc tests.

**Spec:** `docs/superpowers/specs/3-2-runhistorystore-edb5e5b2.md` (reproduced verbatim in the "Spec" section below; parent design `docs/superpowers/specs/2026-10-05-run-history-titles-design.md`).

## Global Constraints

- The store's root object is a `Scope`.
- Store imports only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain/*.js` (`tests/architecture/test_layers.py`).
- Its inputs are plain properties that App binds; it never reaches for another store.
- Helpers run through `HelperRunner`; each runner's `script` is `backendDir + "runs/runs-history.py"`.
- `historyByProject` is replaced, never changed in place; each entry is a new object whenever it changes.
- A root is always used exactly as the `snapshotByProject` key, in argv and in `historyByProject`; the run root (for `Runs.historyCursor`) is `Runs.withProject({}, R, "").project.root`.
- Terminal run: `Runs.runState(run)` is `parked`, `done`, `escalated` or `cancelled`.
- No `--limit` is passed. Argv order: `ROOT --before CURSOR --status S1,S2,... [--since ISO]`.
- Input defaults: `backendDir` `""`, `active` `false`, `snapshotByProject` `{}`, `runFilter` `""`, `finishedState` `""`, `finishedAge` `"all"`.
- Docstrings and comments state the contract only, no narrative.
- `bash tests/run.sh` green, including `tests/architecture`; no `TypeError`, `ReferenceError`, `Unable to assign` or `is not a function` line in QML output.
- The store has no signal; App routes nothing from it.

## Review Focus

- A snapshot root key with a trailing `/` (`"/home/u/a/"`): argv and `historyByProject` use the key exactly as given, while the cursor is still found through the trimmed run root; `"/home/u/a"` without the slash is not a snapshot root. Test: Task 1 `test_a_root_with_a_trailing_slash_is_used_as_given`.
- A page whose `runs` array holds `null`, a string, an array, or the same id twice: the non-objects are skipped, the id is added once, the rest land. Test: Task 2 `test_a_page_skips_entries_that_are_not_objects_and_repeated_ids`.
- An ok page with no `more` key, or `more` that is truthy but not `true` (`"yes"`): `more` is `false`, so the UI never offers a page that does not exist. Test: Task 2 `test_more_is_true_only_when_the_page_says_so`.
- `showOlder` right after a drop: the entry starts over (`runs` `[]`) and the cursor comes from the snapshot only, never from the dropped pages. Test: Task 4 `test_show_older_after_a_drop_starts_over_from_the_snapshot`.
- A snapshot change that leaves a root's history unchanged (an unrelated root moves, a live run leaves): `historyByProject` is not reassigned, so bound UI does not churn. Test: Task 3 `test_a_terminal_run_leaving_the_snapshot_moves_into_history` (SignalSpy on `historyByProjectChanged`).

---

## Spec

The spec this plan implements, verbatim from `docs/superpowers/specs/3-2-runhistorystore-edb5e5b2.md`:

### 3.2 RunHistoryStore: older runs a page at a time — design

Card `edb5e5b2-f3c1-476d-9285-0f5709ee5793`, a subtask of story `b477c51f` (History and
titles stores). Parent design: `docs/superpowers/specs/2026-10-05-run-history-titles-design.md`
(below, "parent"). This card adds `core/stores/RunHistoryStore.qml`, composes it in `App.qml`
as `app.runHistory`, and documents it. It turns the parent's **Store** section
(parent :153-172) into a store. No screen and no other store reads it yet.

#### Where the card overrides the parent

The parent describes one global keyset: `am runs --all-projects`, a run-id `cursor`, flat
`historyRuns` (parent :121-135, :155-161). That is stale. The helper that shipped (card 1.2,
`core/backend/runs/runs-history.py` header) and this card are **per project**:

- the helper takes `ROOT --before ISO [--limit K] [--status S,...] [--since ISO]`;
- `--before` is a `started_at` time, not a run id, and the reply carries no `cursor`;
- `Runs.historyCursor(runs, root)` (`core/domain/runs.js:771-791`) gives the time;
- the state is `historyByProject {root: {runs, more, loading, error}}` (card);
- "rows of unregistered projects dropped" (parent :160-161, :221) has no meaning here: a page
  is only ever fetched for a root the snapshot covers.

Everything below follows the card and the shipped helper wherever they differ from the parent.

#### Inherited constraints

- App hands the store `backendDir`, `active`, the snapshot and the filter values
  (parent :155; card: `backendDir`, `active`, `snapshotByProject` = `RunStore.runsByProject`,
  `runFilter`, `finishedState`, `finishedAge`).
- `showOlder` fetches one page with `--before` from the cursor and the filter's `--status`
  and `--since`; latest wins. Rows the snapshot already lists are dropped: the snapshot wins
  (parent :159-161; card).
- A terminal run that leaves the snapshot window while history is loaded moves into the
  history list, so the list never gains a hole (parent :162-164; card).
- A changed state or age filter drops every loaded page, because they were fetched under the
  old filter. The panel closing drops them all. The project filter keeps them
  (parent :165-167; card).
- History runs are never compared by `RunAlertsStore`, and the watch's changed ids never
  refetch history; a resumed history run shows up in the snapshot, which wins
  (parent :170-172; card).
- A failed page shows its error and the loaded rows stay (parent Errors :200). A filter change
  during a page drops the reply and clears the pages (parent Errors :202).
- `--status` is `Runs.historyStatuses(filter, finishedState)` (parent :148-150;
  `runs.js:754-768`). Age is `started_at`: `today` is since local midnight, `week` is the last
  7×24 h, anything else is all time (parent :143-146; `Runs.withinAge`, `runs.js:719-735`).
- The helper prints one JSON line, `{"ok": true, "runs": [{<am runs row>, "status": <am status
  data>}], "more": bool}` or `{"ok": false, "error": {type, message}}`; exit 0 ok, 1 failure,
  2 usage. ROOT must be non-empty and must not start with `-`; every value must be non-empty
  and must not start with `-` (`runs-history.py` header).
- A run is built the way the snapshot builds one:
  `Runs.withProject(Runs.normalizeRun({row: <entry without its status key>, status:
  entry.status}), root, name)` (`core/stores/RunStore.qml:871`, `rowOf` at :759-768).
- Store conventions (`docs/architecture.md` stores section; `tests/architecture/test_layers.py`):
  - the root is a `Scope`;
  - it imports only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain/*.js`;
  - its inputs are plain properties that App binds, and it never reaches for another store;
  - helpers run through `HelperRunner`;
  - its maps are replaced, never changed in place.
- Docstrings and comments state the contract only, no narrative. TDD, tests first.
  `bash tests/run.sh` green, including `tests/architecture` (card).

#### Behaviour

##### Inputs

| property | type | default | App binds it to (this card) |
|---|---|---|---|
| `backendDir` | string | `""` | `app.backendDir` |
| `active` | bool | `false` | `app.panelOpen` |
| `snapshotByProject` | `{root: [run]}` | `{}` | `app.runs.runsByProject` |
| `runFilter` | string | `""` | `app.runs.runFilter` |
| `finishedState` | string | `""` | not bound here (see below) |
| `finishedAge` | string | `"all"` | not bound here (see below) |

`finishedState` and `finishedAge` do not exist on any store yet. Card 3.3 adds them to
`RunStore` as session state, and binds them here then. In this card they are plain inputs
with the defaults above: `""` means every finished state, and `"all"` means all time.

##### Terms

- **Snapshot root.** An own key of `snapshotByProject`. `RunStore` cuts that map to the usable
  registry roots on every registry change (`RunStore.qml:631-647`) and empties it when the
  panel closes or `am` is missing. So its keys are the store's view of the registry, and no
  `projectRoots` input is needed. A root is always used exactly as that key, in argv and in
  `historyByProject`.
- **Run root of R.** `Runs.withProject({}, R, "").project.root`: R with its trailing `/`
  removed, which is what `run.project.root` holds.
- **Terminal run.** A run whose `Runs.runState` is `parked`, `done`, `escalated` or
  `cancelled`. This is the same set `Runs.historyCursor` considers.
- **The query.** `Runs.historyStatuses(runFilter, finishedState)` together with
  `finishedAge`.

##### State

- `historyByProject`: `{root: {runs, more, loading, error}}`. Replaced, never changed in
  place; each entry is a new object whenever it changes.
  - `runs`: the root's history runs, built like snapshot runs, newest first;
  - `more`: the last ok page's `more` (`false` before the first reply);
  - `loading`: `true` while a page for this root is in flight;
  - `error`: `""`, or the error sentence of the last failed page.
- A root **has history** when it has an entry. The entry exists from that root's first
  launched `showOlder` until the root's pages are dropped.
- `runnerFor(root)`: the `HelperRunner` that serves `root`, or `null` when there is none. It
  is the test seam. Each runner's `script` is `backendDir + "runs/runs-history.py"`.
- Internal, not part of the contract: the previous `snapshotByProject` value, and the last
  query.

##### `showOlder(root)`

1. It does nothing at all unless all of these hold:
   - `active` is true;
   - `root` is a snapshot root;
   - the status list of the query is not empty (`runFilter` `"live"` gives `[]`);
   - the cursor is not `""`.
2. **Cursor.** `Runs.historyCursor(S ++ H, runRoot)`, where S is `snapshotByProject[root]`,
   H is the root's history runs (`[]` with no entry) and runRoot is the run root of `root`.
   Pages chain: the next `--before` is the oldest terminal run of the root listed so far.
3. **Argv**, in this order:
   `ROOT --before CURSOR --status S1,S2,... [--since ISO]`.
   No `--limit` is passed, so the helper's default of 10 applies.
4. **`--since`** is computed from `finishedAge` when the call is made:
   - `"today"`: the local midnight that starts the current day, as `Date.toISOString()`;
   - `"week"`: now minus 7×24 h, as `Date.toISOString()`;
   - anything else: no `--since`.
5. The root's entry becomes `{runs: <kept>, more: <kept>, loading: true, error: ""}`, or
   `{runs: [], more: false, loading: true, error: ""}` when there was none.
6. **Latest wins per root.** A call for a root whose page is in flight cancels that fetch and
   launches the new one. The old reply, if it ever arrives, changes nothing. A fetch for
   another root is never cancelled: roots page independently, and several can be in flight.

##### A reply

The reply belongs to the root and the launch it came from. A reply from a cancelled or
superseded launch, or for a root without an entry, changes nothing.

- **ok.** The process exited 0, `Results.parseEnvelope(stdout)` is an object with
  `ok === true`, and its `runs` is an array.
  - Each element that is a plain object becomes a run:
    `Runs.withProject(Runs.normalizeRun({row: <element without its status key>, status:
    element.status}), root, name)`. `name` is `project.name` of the root's first snapshot run,
    else of its first history run, else `""`.
  - A run whose id the root's current snapshot lists is dropped, and so is one whose id the
    root's history already holds.
  - The rest are appended to `runs`, in the helper's order.
  - `more` becomes `env.more === true`, `loading` false and `error` `""`.
- **error.** Anything else: a non-zero exit, an `ok:false` envelope, unparsable output, or an
  ok envelope without a `runs` array.
  - `runs` and `more` stay as they were;
  - `loading` becomes false;
  - `error` becomes `Runs.errorText(env)` when `env` is an object with `ok !== true`, else
    `Runs.errorText(null)` (`"unknown error"`).
  - Nothing else happens: no signal and no toast.

##### The snapshot changes

Whenever `snapshotByProject` changes, the store compares it with the previous value, in this
order:

1. **A removed root.** For every root that was a snapshot root and no longer is, its entry is
   dropped and its fetch in flight is cancelled.
2. **Window overflow.** For every root that is a snapshot root in both values and has history,
   every terminal run of the previous list whose id the new list does not hold moves into
   history. Those runs are put in front of the existing history runs, in their previous
   snapshot order, and an id history already holds is not added twice. A non-terminal run that
   leaves is not moved. A root without history moves nothing.
3. **Snapshot wins.** For every root with history, a history run whose id the root's current
   snapshot lists is removed (a resumed run).
4. An entry is replaced only when its runs actually changed.

A snapshot change never launches a fetch.

##### Pages are dropped

"Dropped" means: the entry goes from `historyByProject`, and the root's fetch in flight is
cancelled, so its reply changes nothing.

- **The query changes.** When `runFilter`, `finishedState` or `finishedAge` changes and the
  new query differs from the last one (a different status list or a different `finishedAge`),
  every root's pages are dropped. A change that leaves the query the same drops nothing. For
  example, `finishedState` under the All chip gives the same status list. A changed
  `finishedState` under Finished, and every `finishedAge` change, always differ. This follows
  the parent's reason (pages "fetched under the old filter", parent :165-166). It also covers a
  chip change: the next cursor runs over the loaded runs, so pages fetched for another status
  list would make a later page skip rows.
- **The panel closes.** `active` turning false drops every root's pages.
- **A root is removed** from `snapshotByProject` (see above).

##### Never

- History is never compared for alerts: the store has no signal, and App routes nothing from
  it.
- History is never refetched by the watch or by a snapshot: only `showOlder` launches the
  helper.
- The store never fetches while inactive, never fetches a root that is not a snapshot root,
  never has two fetches in flight for one root, and never writes.

##### App wiring

`App.qml` adds this block after `runTitles`:

```qml
readonly property RunHistoryStore runHistory: RunHistoryStore {
  backendDir: app.backendDir
  active: app.panelOpen
  snapshotByProject: app.runs.runsByProject
  runFilter: app.runs.runFilter
}
```

Above it goes a comment in the style of its neighbours. It says the store never imports the
run store, lists what App hands it, and says App routes no signal from it.

##### Docs

`docs/architecture.md` gains one top-level bullet, `` - `RunHistoryStore.qml` … ``, right
after the `RunTitlesStore.qml` bullet (`docs/architecture.md:94`). It names:

- `app.runHistory`;
- every bound input, each backticked: `backendDir`, `active`, `snapshotByProject`,
  `runFilter`;
- the unbound inputs `finishedState` and `finishedAge` and their defaults;
- `historyByProject` and its entry shape;
- `showOlder(` and the rules above (cursor, argv, latest wins per root, reply, overflow,
  drops, never), in one paragraph.

#### Tests (TDD: written first, seen failing)

##### `tests/core/stores/tst_run_history_store.qml` (new)

Tier: QML store unit test. This is where `HelperRunner` processes are stubbed and a store's
reactions to its inputs are driven, as in `tst_run_titles_store.qml`.

How the tests are built:

- the store is built alone with
  `Qt.createComponent("../../../core/stores/RunHistoryStore.qml")` and
  `createObject(tc, {backendDir: "/plugin/core/backend/"})`, then `active` is set true;
- runs are built with `Runs.withProject(Runs.normalizeRun({row: {id, repo_dir, started_at,
  status}, status: {run: {id, status}, rows: [], stories: [], subtasks: []}}), root, "proj")`.
  A `runOf(id, root, status, startedAt)` helper does this. A terminal status is `done`,
  `stopped` and so on; a live one is `started` with no lease;
- a helper entry for a reply is `{id, repo_dir, started_at, status: {run: {...}, ...}}`;
- replies go through the stubbed process: `proc.outText = …; proc.exited(code)` on
  `s.runnerFor(root).current`;
- argv is `current.command.join("|")`, which begins
  `python3|/plugin/core/backend/runs/runs-history.py|<root>|--before|…`.

The roots are rootA `/home/u/a` and rootB `/home/u/b`. The base snapshot for rootA is
`a1` (`started`, 2026-10-05T10:00:00Z), `a2` (`done`, 2026-10-04T00:00:00Z) and
`a3` (`stopped`, 2026-10-03T00:00:00Z).

1. **argv per filter.**
   - With `runFilter` `""` and `finishedAge` `"all"`, `showOlder(rootA)` runs
     `…|/home/u/a|--before|2026-10-03T00:00:00Z|--status|done,escalated,stopped,cancelled,canceled`,
     with no `--since` and no `--limit`.
   - The status list follows the filter: `"parked"` gives `stopped`; `"attention"` gives
     `escalated`; `"finished"` with `finishedState` `"cancelled"` gives `cancelled,canceled`;
     `"finished"` with `""` gives `done,escalated,cancelled,canceled`.
   - `"live"` launches nothing and creates no entry.
   - `finishedAge` `"week"`: the value after `--since` parses to a time between
     `t0 − 7 d` and `t1 − 7 d`, where t0 and t1 are `Date.now()` before and after the call.
   - `"today"`: it equals the `toISOString()` of local midnight, computed in the test before
     or after the call.
   - `entry.loading` is true after the launch.
2. **no-op cases.** Nothing launches and no entry is created when:
   - the store is inactive;
   - the root is not a key of `snapshotByProject`;
   - the root has no terminal run (snapshot only `a1`).
3. **dedupe against the snapshot.** A reply listing `a2` (already in the snapshot), `h1` and
   `h2` gives history `runs` ids `[h1, h2]`, each with `project.root` `/home/u/a`, `loading`
   false and `error` `""`. Each history run's `status` is the normalized am status, not
   `[object Object]`.
4. **pages chain, more and exhausted.**
   - The first reply has `more: true`, and `entry.more` is true.
   - A second `showOlder(rootA)` uses `--before` = the oldest `started_at` among the snapshot
     and history runs (h2's).
   - Its reply, `h3` plus a duplicate `h2`, with `more: false`, appends only `h3`, and
     `entry.more` is false.
5. **error keeps rows.** After an ok page, each of these replies leaves `runs` and `more`
   unchanged, sets `loading` false and sets `error`:
   - `{"ok":false,"error":{"type":"AmMissing","message":"am is not installed."}}` with exit
     1, which gives `"AmMissing: am is not installed."`;
   - exit 0 with `not json`, which gives `"unknown error"`;
   - exit 0 with `{"ok":true,"runs":{}}`, which gives `"unknown error"`.

   A following ok page clears `error`.
6. **window overflow moves the run.**
   - rootA has history `[h1]`.
   - A new snapshot for rootA drops `a3` (terminal) and adds `a0`. History becomes
     `[a3, h1]`.
   - Another snapshot that drops the live `a1` moves nothing.
   - With rootB having no history, a terminal run leaving rootB's snapshot creates no rootB
     entry.
7. **snapshot wins on resume.** rootA has history `[h1, h2]`. A snapshot that now lists `h1`
   (resumed) leaves history `[h2]`.
8. **a snapshot change never fetches.** Setting `snapshotByProject` to new values, with and
   without history, launches no `runs-history.py`.
9. **each drop trigger.** Start each case with entries for rootA and rootB, rootA's page in
   flight.
   - `finishedAge` changes from `"all"` to `"week"`: both entries are gone.
   - `runFilter` `"finished"` and `finishedState` changes from `""` to `"done"`: both are
     gone.
   - `runFilter` changes from `""` to `"parked"`: both are gone.
   - `finishedState` changes while `runFilter` is `""`: nothing is dropped.
   - `active` turns false: both are gone.
   - `snapshotByProject` loses rootB: only rootB's entry is gone.

   In every case, the dropped root's old process replying afterwards creates no entry.
10. **stale reply dropped, latest wins per root.**
    - `showOlder(rootA)` twice. A reply on the first process changes nothing, and `loading`
      stays true. The second process's reply applies.
    - `showOlder(rootA)` then `showOlder(rootB)`: both stay in flight, and each reply lands
      on its own root.

##### `tests/core/stores/tst_app_runs.qml`

Tier: App composition test, the existing home of App's run-store wiring. Its header comment's
list of composed stores gains `app.runHistory` and `tst_run_history_store.qml`.

11. **runHistory exists and is wired.** `make()` gives `app.runHistory` with:
    - `backendDir` `/plugin/core/backend/`;
    - `snapshotByProject` equal to `app.runs.runsByProject`, before and after an ok snapshot
      reply;
    - `runFilter` following `app.runs.runFilter`;
    - `active` following `app.panelOpen`;
    - `finishedState` `""` and `finishedAge` `"all"`.

##### `tests/architecture/test_run_store_docs.py`

Tier: architecture doc test. It pins every run store's App wiring to its docs bullet.

12. `STORES` gains `"RunHistoryStore"` after `"RunTitlesStore"`, and the module docstring
    says "six". The existing parametrized tests then require the new bullet:
    - in order;
    - naming `` `app.runHistory` ``;
    - naming every input App binds.

    `README_TOKENS` gains `"RunHistoryStore"` and `"app.runHistory"`.

##### Unchanged and still green

`tests/architecture/test_layers.py` (store imports, duplication guards),
`test_icon_glyphs.py` (no glyphs) and the whole `bash tests/run.sh`. `tests/run.sh` fails on
any `TypeError`, `ReferenceError`, `Unable to assign` or `is not a function` line, so the
store must emit none of them.

#### Accepted

- The history store builds its row with a small store-local copy of `RunStore.rowOf`
  (`RunStore.qml:762-768`), because a store may not reference another store. Moving it to
  `runs.js` would touch `RunStore`, which is outside this card.
- A project renamed in the registry keeps its old `project.name` on rows already in history
  until they are dropped. The next page and moved runs take the current name.

#### Out of scope

- Merging history into `RunStore.filteredRuns`, the display order, `finishedState` and
  `finishedAge` on `RunStore`, and binding them here: card 3.3.
- Titled alerts and any `RunAlertsStore` change: card 3.4. `RunTitlesStore` gets no history
  runs.
- Any UI: **Show older**, `Loading older runs…`, the error line, the Finished chip rows.
- `runs-history.py` (1.2) and the `runs.js` functions (`historyStatuses`, `historyCursor`,
  `withinAge`): they exist and are used as they are.
- Passing `--limit`, persistence, any `am` or `brd` change.

---

## File Structure

- Create `core/stores/RunHistoryStore.qml` — the store (Tasks 1–4 build it up).
- Create `tests/core/stores/tst_run_history_store.qml` — the store's QML unit tests (Tasks 1–4).
- Modify `core/stores/App.qml` — compose `app.runHistory` after the `runTitles` block (Task 5).
- Modify `tests/core/stores/tst_app_runs.qml` — header comment and one wiring test (Task 5).
- Modify `tests/architecture/test_run_store_docs.py` — docstring, `STORES`, `README_TOKENS` (Task 5).
- Modify `docs/architecture.md` — one `RunHistoryStore.qml` bullet right after the `RunTitlesStore.qml` bullet (line 94) (Task 5).

## How to run the tests

- One QML test file: `bash tests/run.sh tst_run_history_store` (the argument filters QML test paths by substring; the script always runs the whole pytest suite first). A QML test fails when the output shows a `FAIL!` line, or any `TypeError` / `ReferenceError` / `Unable to assign` / `is not a function` line; the script then exits non-zero. Read the `Totals:` line.
- The App test: `bash tests/run.sh tst_app_runs`.
- pytest alone: `python3 -m pytest tests/architecture/test_run_store_docs.py -q`; if `python3` has no pytest, use `uv run --with pytest python3 -m pytest tests/architecture/test_run_store_docs.py -q`.
- Everything: `bash tests/run.sh`.
- Wrap any run you fear may hang in `timeout 600`.

Facts the engineer needs:

- `tests/stubs/Quickshell/Io/Process.qml` stubs `Process`: setting `running` does nothing. A test answers a launch by setting `proc.outText` and calling `proc.exited(code)`, which makes `HelperRunner` emit `finished(stdout, exitCode, guard)` synchronously.
- `HelperRunner` (`core/stores/HelperRunner.qml`): `run(args)` stops the previous process, bumps `seq`, sets `busy` true and creates a new process `current` with `command = ["python3", script].concat(args)`. `cancel()` bumps `seq` and sets `busy` false, so a cancelled or superseded process's later `exited()` emits nothing. `busy` is true exactly while the latest launch is in flight. `current` is `null` before the first `run()`.
- `tests/stubs/Quickshell/Scope.qml` is an `Item`, so a `Component` and a `QtObject` can be children of the store.
- `Runs.historyStatuses(filter, finishedState)` (`core/domain/runs.js:760`): `"live"` → `[]`; `"parked"` → `["stopped"]`; `"attention"` → `["escalated"]`; `"finished"` → `["done"]` / `["escalated"]` / `["cancelled","canceled"]` for those states, else `["done","escalated","cancelled","canceled"]`; anything else → `["done","escalated","stopped","cancelled","canceled"]`.
- `Runs.historyCursor(runs, root)` (`runs.js:777`): the `started_at` of the oldest terminal run whose `project.root === root`; `""` when none.
- `Runs.runState(run)`: `started` with a live lease → `running`, `started` otherwise → `dead`, `stopped` → `parked`, `cancelled`/`canceled` → `cancelled`, `done`/`escalated` as is.
- `Runs.withProject(run, root, name)` copies `run` and sets `project = {root: <root without trailing "/">, name}`. `Runs.normalizeRun({row, status})` reads `status` from `status.run.status` first, then `row.status` — which is why a helper entry's `status` key (the am status object) must be removed from the row (`rowOf`).
- `Runs.errorText(env)`: `"type: message"` for `{ok:false, error:{type, message}}`; `"unknown error"` for `null`.
- `Results.parseEnvelope(text)`: the last non-empty line parsed as a JSON object, else `null`.
- `Runs.hasKey(map, key)` is an own-property check (false for null); `Runs.copyMap(map)` is a shallow copy.

---

### Task 1: The store skeleton and `showOlder`'s launch

**Files:**
- Create: `core/stores/RunHistoryStore.qml`
- Create: `tests/core/stores/tst_run_history_store.qml`

**Interfaces:**
- Consumes: `HelperRunner` (`core/stores/HelperRunner.qml`); `Runs.hasKey`, `Runs.copyMap`, `Runs.withProject`, `Runs.historyStatuses`, `Runs.historyCursor`.
- Produces (later tasks rely on these exact names):
  - inputs `backendDir: string`, `active: bool`, `snapshotByProject: var`, `runFilter: string`, `finishedState: string`, `finishedAge: string`;
  - state `historyByProject: var` (`{root: {runs: [run], more: bool, loading: bool, error: string}}`);
  - `showOlder(root: string): void`;
  - `runnerFor(root: string): HelperRunner | null`;
  - internal helpers `isSnapshotRoot(root): bool`, `snapshotOf(root): [run]`, `historyOf(root): [run]`, `runRootOf(root): string`, `sinceOf(nowMs: number): string`, `setEntry(root, entry): void`, `makeRunner(root): HelperRunner`;
  - private `QtObject { id: historyState; property var runners: ({}) }`;
  - `Component { id: runnerC; HelperRunner { ... } }`.
  - Test helpers in `tst_run_history_store.qml` used by Tasks 2–4: `makeHistory()`, `runOf(id, root, status, startedAt)`, `baseA()`, `baseB()`, `snap(aRuns, bRuns)`, `openHistory(byProject)`, `entryOf(id, root, status, startedAt)`, `h1()`, `h2()`, `h3()`, `hb1()`, `hb2()`, `pageOk(entries, more)`, `reply(proc, text, code)`, `answer(s, root, text, code)`, `page(s, root, entries, more)`, `argv(proc)`, `sinceArg(proc)`, `idsOf(s, root)`, `inFlight(s)`, and `spyC`.

- [ ] **Step 1: Write the failing tests**

Create `tests/core/stores/tst_run_history_store.qml` with exactly this content:

```qml
// tests/core/stores/tst_run_history_store.qml
// The run history store: showOlder's runs-history.py page per snapshot root
// (argv per chip and age, the no-op cases), its reply (dedupe against the
// snapshot and the history, the cursor chaining pages, `more`, errors that
// keep the rows, latest wins per root), window overflow and snapshot-wins
// on a snapshot change, and every trigger that drops the pages. Built alone
// and driven through its inputs; stubbed Process objects stand in for
// runs-history.py.
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs

TestCase {
  id: tc
  name: "StoresRunHistoryStore"

  Component { id: spyC; SignalSpy {} }

  property string rootA: "/home/u/a"
  property string rootB: "/home/u/b"
  property string historyCmd: "python3|/plugin/core/backend/runs/runs-history.py|"
  property string allStatuses: "done,escalated,stopped,cancelled,canceled"

  // A RunHistoryStore built alone, closed, with an empty snapshot.
  function makeHistory() {
    var comp = Qt.createComponent("../../../core/stores/RunHistoryStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }

  // Run `id` of `root` as the run store hands it over: am status `status`
  // (a "started" run has no lease, so it is not terminal), started at
  // `startedAt`, tagged with project "proj".
  function runOf(id, root, status, startedAt) {
    var raw = {
      row: { id: id, repo_dir: root, started_at: startedAt, status: status },
      status: { run: { id: id, status: status }, rows: [], stories: [], subtasks: [] }
    }
    return Runs.withProject(Runs.normalizeRun(raw), root, "proj")
  }

  // rootA's base snapshot: a1 live, a2 done, a3 parked (the oldest terminal).
  function baseA() {
    return [runOf("a1", tc.rootA, "started", "2026-10-05T10:00:00Z"),
            runOf("a2", tc.rootA, "done", "2026-10-04T00:00:00Z"),
            runOf("a3", tc.rootA, "stopped", "2026-10-03T00:00:00Z")]
  }

  // rootB's base snapshot: b1 done.
  function baseB() { return [runOf("b1", tc.rootB, "done", "2026-10-02T00:00:00Z")] }

  // A snapshotByProject value: rootA lists aRuns, rootB lists bRuns; a null list leaves its root out.
  function snap(aRuns, bRuns) {
    var out = {}
    if (aRuns !== null) out[tc.rootA] = aRuns
    if (bRuns !== null) out[tc.rootB] = bRuns
    return out
  }

  // A store with the snapshot `byProject`, then opened.
  function openHistory(byProject) {
    var s = makeHistory(); if (!s) return null
    s.snapshotByProject = byProject
    s.active = true
    return s
  }

  // One runs-history.py entry: an am runs row whose `status` is the am status object.
  function entryOf(id, root, status, startedAt) {
    return { id: id, repo_dir: root, started_at: startedAt,
             status: { run: { id: id, status: status }, rows: [], stories: [], subtasks: [] } }
  }

  function h1() { return entryOf("h1", tc.rootA, "done", "2026-10-02T00:00:00Z") }
  function h2() { return entryOf("h2", tc.rootA, "stopped", "2026-10-01T00:00:00Z") }
  function h3() { return entryOf("h3", tc.rootA, "done", "2026-09-30T00:00:00Z") }
  function hb1() { return entryOf("hb1", tc.rootB, "done", "2026-10-01T00:00:00Z") }
  function hb2() { return entryOf("hb2", tc.rootB, "done", "2026-09-30T00:00:00Z") }

  // runs-history.py's ok reply; no `more` key when `more` is undefined.
  function pageOk(entries, more) { return JSON.stringify({ ok: true, runs: entries, more: more }) + "\n" }

  // A stubbed process's reply: its stdout, then its exit code.
  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // root's latest launch answered with `text` and exit code `code`.
  function answer(s, root, text, code) { reply(s.runnerFor(root).current, text, code) }

  // showOlder(root), answered with an ok page of `entries` and `more`.
  function page(s, root, entries, more) {
    s.showOlder(root)
    answer(s, root, pageOk(entries, more), 0)
  }

  // A process's argv, joined with "|".
  function argv(proc) { return proc.command.join("|") }

  // The value after --since in a process's argv; "" when there is none.
  function sinceArg(proc) {
    var i = proc.command.indexOf("--since")
    return i < 0 ? "" : proc.command[i + 1]
  }

  // The ids of root's history runs, comma-joined.
  function idsOf(s, root) { return s.historyByProject[root].runs.map(function(r) { return r.id }).join(",") }

  // Store `s` (snapshot snap(baseA(), baseB())) with a first page for each
  // root (rootA [h1], rootB [hb1]) and a second page in flight for each.
  // Returns the two processes in flight.
  function inFlight(s) {
    page(s, tc.rootA, [h1()], true)
    page(s, tc.rootB, [hb1()], true)
    s.showOlder(tc.rootA)
    s.showOlder(tc.rootB)
    return { a: s.runnerFor(tc.rootA).current, b: s.runnerFor(tc.rootB).current }
  }

  // ---- showOlder launches

  function test_show_older_runs_the_helper_with_the_cursor_and_every_terminal_status() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    compare(s.runnerFor(tc.rootA), null, "no runner before the first showOlder")
    s.showOlder(tc.rootA)
    var cmd = argv(s.runnerFor(tc.rootA).current)
    compare(cmd, tc.historyCmd + tc.rootA + "|--before|2026-10-03T00:00:00Z|--status|" + tc.allStatuses)
    verify(cmd.indexOf("--since") < 0, "no --since under all time")
    verify(cmd.indexOf("--limit") < 0, "no --limit")
    var e = s.historyByProject[tc.rootA]
    compare(JSON.stringify(e.runs), "[]")
    compare(e.more, false)
    compare(e.loading, true)
    compare(e.error, "")
    compare(Runs.hasKey(s.historyByProject, tc.rootB), false, "only the root asked for has an entry")
    compare(s.runnerFor(tc.rootB), null)
  }

  function test_the_status_list_follows_the_chip_and_the_finished_state() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    var head = tc.historyCmd + tc.rootA + "|--before|2026-10-03T00:00:00Z|--status|"
    s.runFilter = "parked"
    s.showOlder(tc.rootA)
    compare(argv(s.runnerFor(tc.rootA).current), head + "stopped")
    s.runFilter = "attention"
    s.showOlder(tc.rootA)
    compare(argv(s.runnerFor(tc.rootA).current), head + "escalated")
    s.runFilter = "finished"
    s.finishedState = "cancelled"
    s.showOlder(tc.rootA)
    compare(argv(s.runnerFor(tc.rootA).current), head + "cancelled,canceled")
    s.finishedState = ""
    s.showOlder(tc.rootA)
    compare(argv(s.runnerFor(tc.rootA).current), head + "done,escalated,cancelled,canceled")
  }

  function test_the_live_chip_launches_nothing() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    s.runFilter = "live"
    s.showOlder(tc.rootA)
    compare(s.runnerFor(tc.rootA), null, "a live run is never terminal: no page")
    compare(Runs.hasKey(s.historyByProject, tc.rootA), false)
  }

  function test_since_is_a_week_back_under_week() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    s.finishedAge = "week"
    var t0 = Date.now()
    s.showOlder(tc.rootA)
    var t1 = Date.now()
    var since = Date.parse(sinceArg(s.runnerFor(tc.rootA).current))
    var week = 7 * 24 * 3600 * 1000
    verify(since >= t0 - week && since <= t1 - week, "since " + since + " not in [" + (t0 - week) + ", " + (t1 - week) + "]")
    verify(argv(s.runnerFor(tc.rootA).current).indexOf("|--status|" + tc.allStatuses + "|--since|") > 0, "--since comes last")
  }

  function test_since_is_local_midnight_under_today() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    s.finishedAge = "today"
    var m0 = new Date(); m0.setHours(0, 0, 0, 0)
    s.showOlder(tc.rootA)
    var m1 = new Date(); m1.setHours(0, 0, 0, 0)
    var since = sinceArg(s.runnerFor(tc.rootA).current)
    verify(since === m0.toISOString() || since === m1.toISOString(), since)
  }

  // ---- showOlder does nothing

  function test_an_inactive_store_launches_nothing() {
    var s = makeHistory(); if (!s) return
    s.snapshotByProject = snap(baseA(), null)
    s.showOlder(tc.rootA)
    compare(s.runnerFor(tc.rootA), null)
    compare(Runs.hasKey(s.historyByProject, tc.rootA), false)
  }

  function test_a_root_the_snapshot_lacks_launches_nothing() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    s.showOlder(tc.rootB)
    compare(s.runnerFor(tc.rootB), null)
    compare(Runs.hasKey(s.historyByProject, tc.rootB), false)
  }

  function test_a_root_with_no_terminal_run_launches_nothing() {
    var s = openHistory(snap([baseA()[0]], null)); if (!s) return
    s.showOlder(tc.rootA)
    compare(s.runnerFor(tc.rootA), null, "no cursor: no page")
    compare(Runs.hasKey(s.historyByProject, tc.rootA), false)
  }

  function test_a_root_with_a_trailing_slash_is_used_as_given() {
    var key = tc.rootA + "/"
    var byProject = {}
    byProject[key] = baseA()
    var s = openHistory(byProject); if (!s) return
    s.showOlder(tc.rootA)
    compare(s.runnerFor(tc.rootA), null, "the root without its slash is not a snapshot root")
    s.showOlder(key)
    compare(argv(s.runnerFor(key).current), tc.historyCmd + key + "|--before|2026-10-03T00:00:00Z|--status|" + tc.allStatuses)
    compare(s.historyByProject[key].loading, true)
    compare(Runs.hasKey(s.historyByProject, tc.rootA), false)
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_history_store`
Expected: FAIL — every test fails in `makeHistory()` with the component error `No such file or directory` (RunHistoryStore.qml does not exist yet).

- [ ] **Step 3: Write the store**

Create `core/stores/RunHistoryStore.qml` with exactly this content (the header states the whole contract; Tasks 2–4 complete the parts it names that this task does not build yet):

```qml
import QtQml
import Quickshell
import Quickshell.Io
import "../domain/results.js" as Results
import "../domain/runs.js" as Runs

// The older runs: each snapshot root's history, a page at a time.
// `historyByProject` is {root: {runs, more, loading, error}}, keyed by the
// root exactly as `snapshotByProject` keys it, replaced, never changed in
// place, each entry a new object whenever it changes; a root has an entry
// from its first launched showOlder until its pages are dropped.
// showOlder(root) runs runs-history.py ROOT --before CURSOR --status
// S1,S2,... [--since ISO] on runnerFor(root), only while `active`, for a
// root `snapshotByProject` has, with a non-empty
// Runs.historyStatuses(runFilter, finishedState) and a non-empty cursor:
// Runs.historyCursor over the root's snapshot and history runs. --since is
// local midnight for finishedAge "today", now minus 7 days for "week", and
// absent otherwise. Latest wins per root; roots page independently. An ok
// page appends its runs, built like the snapshot's, minus every id the
// root's snapshot or history lists, and sets `more`; any other reply keeps
// `runs` and `more` and sets `error`. A snapshot change drops the pages of
// every root it removes, moves a terminal run that leaves the snapshot of a
// root with history to the front of that history, and takes out of the
// history every run the snapshot lists; it never fetches. A changed query
// (status list or finishedAge) and the panel closing drop every root's
// pages. Dropping cancels the root's fetch in flight. No signal: history is
// never compared for alerts. The backend directory, the panel-open flag,
// the snapshot and the filter values are handed to it from outside -- it
// never reaches for another store. App composes it as `app.runHistory`.
Scope {
  id: history

  property string backendDir: ""        // <plugin>/core/backend/
  property bool active: false           // App binds this to "panel open" (app.panelOpen)
  property var snapshotByProject: ({})  // {root: [run]}, the run store's runsByProject; App binds it
  property string runFilter: ""         // the Runs chip; App binds the run store's runFilter
  property string finishedState: ""     // "done" | "escalated" | "cancelled"; anything else is every finished state
  property string finishedAge: "all"    // "today" | "week"; anything else is all time

  property var historyByProject: ({})   // {root: {runs, more, loading, error}}

  // The HelperRunner that serves `root`; null when there is none.
  function runnerFor(root) {
    return Runs.hasKey(historyState.runners, root) ? historyState.runners[root] : null
  }

  // Whether `root` is an own key of snapshotByProject.
  function isSnapshotRoot(root) {
    return typeof root === "string" && Runs.hasKey(history.snapshotByProject, root)
  }

  // The snapshot root's run list; [] for any other root or a list that is not an array.
  function snapshotOf(root) {
    var list = history.isSnapshotRoot(root) ? history.snapshotByProject[root] : null
    return Array.isArray(list) ? list : []
  }

  // The root's history runs; [] when it has no entry.
  function historyOf(root) {
    return Runs.hasKey(history.historyByProject, root) ? history.historyByProject[root].runs : []
  }

  // `root` as run.project.root holds it: its trailing "/" removed.
  function runRootOf(root) {
    return Runs.withProject({}, root, "").project.root
  }

  // The --since value of finishedAge at `nowMs`: local midnight for "today",
  // nowMs minus 7 days for "week", both as toISOString(); "" otherwise.
  function sinceOf(nowMs) {
    if (history.finishedAge === "week") return new Date(nowMs - 7 * 24 * 3600 * 1000).toISOString()
    if (history.finishedAge !== "today") return ""
    var midnight = new Date(nowMs)
    midnight.setHours(0, 0, 0, 0)
    return midnight.toISOString()
  }

  // historyByProject with root's entry replaced by `entry`.
  function setEntry(root, entry) {
    var map = Runs.copyMap(history.historyByProject)
    map[root] = entry
    history.historyByProject = map
  }

  // A new runner for `root`, kept as runnerFor(root).
  function makeRunner(root) {
    var runner = runnerC.createObject(history)
    var runners = Runs.copyMap(historyState.runners)
    runners[root] = runner
    historyState.runners = runners
    return runner
  }

  // Fetches one older page of `root` (see the header). The root's entry
  // keeps its runs and `more`, and becomes loading with no error; a fetch of
  // this root still in flight is superseded.
  function showOlder(root) {
    if (!history.active || !history.isSnapshotRoot(root)) return
    var statuses = Runs.historyStatuses(history.runFilter, history.finishedState)
    if (statuses.length === 0) return
    var cursor = Runs.historyCursor(history.snapshotOf(root).concat(history.historyOf(root)), history.runRootOf(root))
    if (cursor === "") return
    var args = [root, "--before", cursor, "--status", statuses.join(",")]
    var since = history.sinceOf(Date.now())
    if (since !== "") args.push("--since", since)
    var entry = Runs.hasKey(history.historyByProject, root) ? history.historyByProject[root] : { runs: [], more: false }
    history.setEntry(root, { runs: entry.runs, more: entry.more, loading: true, error: "" })
    var runner = history.runnerFor(root)
    if (runner === null) runner = history.makeRunner(root)
    runner.run(args)
  }

  // Bookkeeping kept apart so consumers cannot write it.
  QtObject {
    id: historyState
    property var runners: ({})   // {root: HelperRunner}, made on each root's first launch
  }

  // One runs-history.py runner per root. Guard "": the store cancels a
  // fetch that must not land.
  Component {
    id: runnerC
    HelperRunner {
      script: history.backendDir + "runs/runs-history.py"
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_history_store`
Expected: PASS — `Totals: 11 passed, 0 failed` (9 tests plus `initTestCase`/`cleanupTestCase`), no `TypeError`/`ReferenceError` lines, exit 0. The pytest part (`tests/architecture/test_layers.py` included) passes too.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunHistoryStore.qml tests/core/stores/tst_run_history_store.qml
git commit -m "feat(runs): RunHistoryStore.showOlder fetches a root's older page from its cursor"
```

---

### Task 2: A page's reply: dedupe, `more`, errors, latest wins per root

**Files:**
- Modify: `core/stores/RunHistoryStore.qml` (`makeRunner`; add `rowOf`, `nameOf`, `idsOf`, `replied` after `showOlder`)
- Modify: `tests/core/stores/tst_run_history_store.qml` (append a `---- a page's reply` section before the final `}`)

**Interfaces:**
- Consumes: Task 1's `historyByProject`, `showOlder`, `runnerFor`, `snapshotOf`, `historyOf`, `setEntry`, `makeRunner`, `runnerC`, `historyState.runners`; `Results.parseEnvelope`, `Runs.errorText`, `Runs.normalizeRun`, `Runs.withProject`.
- Produces: `replied(root: string, stdout: string, exitCode: int): void`; `rowOf(entry): object`; `nameOf(root): string`; `idsOf(list: [run]): [id]` (Task 3 uses `idsOf`).

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_history_store.qml`, insert before the file's final closing `}`:

```qml

  // ---- a page's reply

  function test_an_ok_page_drops_the_ids_the_snapshot_lists() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    page(s, tc.rootA, [entryOf("a2", tc.rootA, "done", "2026-10-04T00:00:00Z"), h1(), h2()], true)
    var e = s.historyByProject[tc.rootA]
    compare(idsOf(s, tc.rootA), "h1,h2", "a2 is in the snapshot: the snapshot wins")
    compare(e.loading, false)
    compare(e.error, "")
    compare(e.runs[0].project.root, tc.rootA)
    compare(e.runs[0].project.name, "proj", "the name of the root's first snapshot run")
    compare(e.runs[0].status, "done", "the am status, normalized, not [object Object]")
    compare(e.runs[1].status, "stopped")
    compare(e.runs[0].started_at, "2026-10-02T00:00:00Z")
  }

  function test_pages_chain_from_the_oldest_run_listed_so_far() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    page(s, tc.rootA, [h1(), h2()], true)
    compare(s.historyByProject[tc.rootA].more, true)
    s.showOlder(tc.rootA)
    compare(argv(s.runnerFor(tc.rootA).current),
            tc.historyCmd + tc.rootA + "|--before|2026-10-01T00:00:00Z|--status|" + tc.allStatuses,
            "h2 is the oldest terminal run of the snapshot and the history")
    compare(idsOf(s, tc.rootA), "h1,h2", "a launch keeps the loaded runs")
    compare(s.historyByProject[tc.rootA].more, true, "and `more`")
    compare(s.historyByProject[tc.rootA].loading, true)
    answer(s, tc.rootA, pageOk([h2(), h3()], false), 0)
    compare(idsOf(s, tc.rootA), "h1,h2,h3", "the repeated h2 is not added twice")
    compare(s.historyByProject[tc.rootA].more, false, "exhausted")
    compare(s.historyByProject[tc.rootA].loading, false)
  }

  function test_a_failed_page_keeps_the_rows_and_shows_its_error() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    page(s, tc.rootA, [h1()], true)
    var replies = [
      [JSON.stringify({ ok: false, error: { type: "AmMissing", message: "am is not installed." } }) + "\n", 1, "AmMissing: am is not installed."],
      ["not json\n", 0, "unknown error"],
      [JSON.stringify({ ok: true, runs: {} }) + "\n", 0, "unknown error"],
      ["", 2, "unknown error"]
    ]
    for (var i = 0; i < replies.length; i++) {
      s.showOlder(tc.rootA)
      compare(s.historyByProject[tc.rootA].error, "", "a launch clears the error, case " + i)
      answer(s, tc.rootA, replies[i][0], replies[i][1])
      var e = s.historyByProject[tc.rootA]
      compare(idsOf(s, tc.rootA), "h1", "the rows stay, case " + i)
      compare(e.more, true, "`more` stays, case " + i)
      compare(e.loading, false, "case " + i)
      compare(e.error, replies[i][2], "case " + i)
    }
    page(s, tc.rootA, [h2()], false)
    compare(s.historyByProject[tc.rootA].error, "", "an ok page clears the error")
    compare(idsOf(s, tc.rootA), "h1,h2")
  }

  function test_a_page_skips_entries_that_are_not_objects_and_repeated_ids() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    page(s, tc.rootA, [null, "h9", [h3()], h1(), h1(), h2()], false)
    compare(idsOf(s, tc.rootA), "h1,h2")
    compare(s.historyByProject[tc.rootA].error, "")
  }

  function test_more_is_true_only_when_the_page_says_so() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    page(s, tc.rootA, [h1()], undefined)
    compare(s.historyByProject[tc.rootA].more, false, "no `more` key")
    page(s, tc.rootA, [h2()], "yes")
    compare(s.historyByProject[tc.rootA].more, false, "a `more` that is not true")
    page(s, tc.rootA, [h3()], true)
    compare(s.historyByProject[tc.rootA].more, true)
  }

  function test_a_second_show_older_supersedes_the_page_in_flight() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    s.showOlder(tc.rootA)
    var first = s.runnerFor(tc.rootA).current
    s.showOlder(tc.rootA)
    var second = s.runnerFor(tc.rootA).current
    verify(first !== second, "a new process")
    reply(first, pageOk([h1()], true), 0)
    compare(idsOf(s, tc.rootA), "", "the superseded reply changes nothing")
    compare(s.historyByProject[tc.rootA].loading, true)
    reply(second, pageOk([h2()], false), 0)
    compare(idsOf(s, tc.rootA), "h2")
    compare(s.historyByProject[tc.rootA].loading, false)
  }

  function test_roots_page_independently() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    s.showOlder(tc.rootA)
    s.showOlder(tc.rootB)
    compare(s.runnerFor(tc.rootA).busy, true, "rootA's page is not cancelled by rootB's")
    compare(s.runnerFor(tc.rootB).busy, true)
    compare(argv(s.runnerFor(tc.rootB).current), tc.historyCmd + tc.rootB + "|--before|2026-10-02T00:00:00Z|--status|" + tc.allStatuses)
    answer(s, tc.rootB, pageOk([hb1()], false), 0)
    compare(idsOf(s, tc.rootB), "hb1")
    compare(s.historyByProject[tc.rootA].loading, true)
    answer(s, tc.rootA, pageOk([h1()], true), 0)
    compare(idsOf(s, tc.rootA), "h1")
    compare(idsOf(s, tc.rootB), "hb1")
    compare(s.historyByProject[tc.rootB].runs[0].project.root, tc.rootB)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_history_store`
Expected: FAIL — the seven new tests fail (`idsOf` gives `""` where `"h1,h2"` etc. is expected, `loading` stays `true`): no runner is connected to a reply handler yet. Task 1's tests still pass.

- [ ] **Step 3: Implement the reply**

In `core/stores/RunHistoryStore.qml`, replace `makeRunner`:

```qml
  // A new runner for `root`, kept as runnerFor(root).
  function makeRunner(root) {
    var runner = runnerC.createObject(history)
    var runners = Runs.copyMap(historyState.runners)
    runners[root] = runner
    historyState.runners = runners
    return runner
  }
```

with:

```qml
  // A new runner for `root`, kept as runnerFor(root); its replies go to
  // replied(root, ..).
  function makeRunner(root) {
    var runner = runnerC.createObject(history)
    runner.finished.connect(function(stdout, exitCode) { history.replied(root, stdout, exitCode) })
    var runners = Runs.copyMap(historyState.runners)
    runners[root] = runner
    historyState.runners = runners
    return runner
  }
```

Then insert, right after the closing `}` of `showOlder` and before the `// Bookkeeping kept apart` comment:

```qml

  // The `am runs` summary without its `status` key: the helper replaced the
  // summary's status string with the `am status` object, which normalizeRun
  // must never read as the row's status ("[object Object]").
  function rowOf(entry) {
    var row = {}
    for (var key in entry) {
      if (key !== "status" && Runs.hasKey(entry, key)) row[key] = entry[key]
    }
    return row
  }

  // project.name of the root's first snapshot run, else of its first history
  // run; "" when neither has a string one.
  function nameOf(root) {
    var list = history.snapshotOf(root).concat(history.historyOf(root))
    var run = list.length > 0 ? list[0] : null
    var p = run !== null && typeof run === "object" ? run.project : null
    return p !== null && typeof p === "object" && typeof p.name === "string" ? p.name : ""
  }

  // The id of each run of `list`, in order (undefined for a run that is not an object).
  function idsOf(list) {
    return list.map(function(run) { return run !== null && typeof run === "object" ? run.id : undefined })
  }

  // The reply to root's latest launch; a root without an entry changes
  // nothing. Exit 0 with an {"ok": true, "runs": [...]} envelope: each plain
  // object entry becomes a run built like the snapshot's, the ones whose id
  // the root's snapshot or history already lists are dropped, the rest are
  // appended in the helper's order, `more` becomes env.more === true and the
  // error clears. Anything else keeps `runs` and `more` and sets `error` to
  // Runs.errorText of an ok:false envelope, else "unknown error". Either way
  // `loading` becomes false.
  function replied(root, stdout, exitCode) {
    if (!Runs.hasKey(history.historyByProject, root)) return
    var entry = history.historyByProject[root]
    var env = Results.parseEnvelope(stdout)
    if (exitCode !== 0 || env === null || env.ok !== true || !Array.isArray(env.runs)) {
      var error = env !== null && env.ok !== true ? Runs.errorText(env) : Runs.errorText(null)
      history.setEntry(root, { runs: entry.runs, more: entry.more, loading: false, error: error })
      return
    }
    var name = history.nameOf(root)
    var seen = history.idsOf(history.snapshotOf(root).concat(entry.runs))
    var runs = entry.runs.slice()
    for (var i = 0; i < env.runs.length; i++) {
      var item = env.runs[i]
      if (item === null || typeof item !== "object" || Array.isArray(item)) continue
      var run = Runs.withProject(Runs.normalizeRun({ row: history.rowOf(item), status: item.status }), root, name)
      if (seen.indexOf(run.id) >= 0) continue
      seen.push(run.id)
      runs.push(run)
    }
    history.setEntry(root, { runs: runs, more: env.more === true, loading: false, error: "" })
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_history_store`
Expected: PASS — `Totals: 18 passed, 0 failed`, no `TypeError`/`ReferenceError` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunHistoryStore.qml tests/core/stores/tst_run_history_store.qml
git commit -m "feat(runs): RunHistoryStore appends a page's new runs, keeps its rows on an error"
```

---

### Task 3: Snapshot changes: removed roots, window overflow, snapshot wins

**Files:**
- Modify: `core/stores/RunHistoryStore.qml` (add `onSnapshotByProjectChanged`, `Component.onCompleted`, `isTerminal`, `sameRuns`, `cancelRunner`, `snapshotChanged`; add `previous` to `historyState`)
- Modify: `tests/core/stores/tst_run_history_store.qml` (append a `---- snapshot changes` section before the final `}`)

**Interfaces:**
- Consumes: Task 1's `isSnapshotRoot`, `snapshotOf`, `runnerFor`, `historyState`; Task 2's `idsOf`, `replied`; `Runs.runState`.
- Produces: `snapshotChanged(): void`; `cancelRunner(root: string): void` (Task 4 uses it); `isTerminal(run): bool`; `sameRuns(a: [run], b: [run]): bool`; `historyState.previous`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_history_store.qml`, insert before the file's final closing `}`:

```qml

  // ---- snapshot changes

  function test_a_terminal_run_leaving_the_snapshot_moves_into_history() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    page(s, tc.rootA, [h1()], true)
    var spy = spyC.createObject(tc, { target: s, signalName: "historyByProjectChanged" })
    var a0 = runOf("a0", tc.rootA, "started", "2026-10-06T00:00:00Z")
    var base = baseA()
    s.snapshotByProject = snap([a0, base[0], base[1]], baseB())
    compare(idsOf(s, tc.rootA), "a3,h1", "a3 left the window: it moves to the front")
    var e = s.historyByProject[tc.rootA]
    compare(e.runs[0].status, "stopped")
    compare(e.runs[0].project.root, tc.rootA)
    compare(e.more, true, "`more` is kept")
    compare(e.loading, false)
    compare(e.error, "")
    compare(spy.count, 1)
    s.snapshotByProject = snap([a0, base[1]], baseB())
    compare(idsOf(s, tc.rootA), "a3,h1", "the live a1 leaving moves nothing")
    compare(spy.count, 1, "an entry whose runs did not change is not replaced")
    s.snapshotByProject = snap([a0, base[1]], [])
    compare(Runs.hasKey(s.historyByProject, tc.rootB), false, "rootB has no history: b1 leaving creates no entry")
    compare(spy.count, 1)
  }

  function test_overflow_keeps_the_previous_snapshot_order() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    page(s, tc.rootA, [h1()], true)
    var base = baseA()
    s.snapshotByProject = snap([base[0]], null)
    compare(idsOf(s, tc.rootA), "a2,a3,h1", "a2 and a3 in their snapshot order, in front")
    s.snapshotByProject = snap([base[0], runOf("h1", tc.rootA, "done", "2026-10-02T00:00:00Z")], null)
    s.snapshotByProject = snap([base[0]], null)
    compare(idsOf(s, tc.rootA), "h1,a2,a3", "h1 came back and left again: moved once, to the front")
  }

  function test_a_history_run_the_snapshot_lists_again_leaves_the_history() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    page(s, tc.rootA, [h1(), h2()], true)
    s.snapshotByProject = snap(baseA().concat([runOf("h1", tc.rootA, "started", "2026-10-02T00:00:00Z")]), null)
    compare(idsOf(s, tc.rootA), "h2", "h1 was resumed: the snapshot wins")
  }

  function test_a_snapshot_change_never_fetches() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    s.snapshotByProject = snap(baseA().slice(1), baseB())
    compare(s.runnerFor(tc.rootA), null, "no history: no runs-history.py")
    page(s, tc.rootA, [h1()], true)
    var runner = s.runnerFor(tc.rootA)
    var seq = runner.seq
    s.snapshotByProject = snap(baseA().slice(0, 2), [])
    s.snapshotByProject = snap(baseA(), baseB())
    compare(runner.seq, seq, "with history: still no launch")
    compare(runner.busy, false)
    compare(s.runnerFor(tc.rootB), null)
  }

  function test_a_root_leaving_the_snapshot_loses_its_pages() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    var procs = inFlight(s)
    s.snapshotByProject = snap(baseA(), null)
    compare(Runs.hasKey(s.historyByProject, tc.rootB), false, "rootB left: its entry is gone")
    compare(s.runnerFor(tc.rootB).busy, false, "and its fetch is cancelled")
    compare(s.historyByProject[tc.rootA].loading, true, "rootA keeps its entry and its page in flight")
    reply(procs.b, pageOk([hb2()], false), 0)
    compare(Runs.hasKey(s.historyByProject, tc.rootB), false, "rootB's old reply creates no entry")
    reply(procs.a, pageOk([h2()], false), 0)
    compare(idsOf(s, tc.rootA), "h1,h2", "rootA's reply still lands")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_history_store`
Expected: FAIL — `test_a_terminal_run_leaving_the_snapshot_moves_into_history`, `test_overflow_keeps_the_previous_snapshot_order`, `test_a_history_run_the_snapshot_lists_again_leaves_the_history` and `test_a_root_leaving_the_snapshot_loses_its_pages` fail (history is unchanged by a snapshot change). `test_a_snapshot_change_never_fetches` already passes: it guards the code this task adds.

- [ ] **Step 3: Implement the snapshot handling**

In `core/stores/RunHistoryStore.qml`, replace

```qml
  property var historyByProject: ({})   // {root: {runs, more, loading, error}}

```

with

```qml
  property var historyByProject: ({})   // {root: {runs, more, loading, error}}

  onSnapshotByProjectChanged: history.snapshotChanged()
  Component.onCompleted: historyState.previous = history.snapshotByProject

```

Insert, right after the closing `}` of `replied` and before the `// Bookkeeping kept apart` comment:

```qml

  // Whether `run` is terminal: parked, done, escalated or cancelled.
  function isTerminal(run) {
    var state = Runs.runState(run)
    return state === "parked" || state === "done" || state === "escalated" || state === "cancelled"
  }

  // Whether `a` and `b` hold the same runs, in the same order.
  function sameRuns(a, b) {
    if (a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) return false
    }
    return true
  }

  // Cancels root's fetch in flight, if any, so its reply changes nothing.
  function cancelRunner(root) {
    var runner = history.runnerFor(root)
    if (runner !== null && runner.busy) runner.cancel()
  }

  // snapshotByProject changed. A root with history the new value lacks loses
  // its entry and its fetch in flight. For every other root with history,
  // the terminal runs of its previous snapshot list that the new list lacks
  // move to the front of its history, in their previous order, an id the
  // history holds not added twice; then every history run the new list
  // holds leaves. An entry is replaced only when its runs changed. Never
  // fetches.
  function snapshotChanged() {
    var previous = historyState.previous
    historyState.previous = history.snapshotByProject
    var roots = Object.keys(history.historyByProject)
    var map = Runs.copyMap(history.historyByProject)
    var changed = false
    for (var r = 0; r < roots.length; r++) {
      var root = roots[r]
      if (!history.isSnapshotRoot(root)) {
        history.cancelRunner(root)
        delete map[root]
        changed = true
        continue
      }
      var entry = map[root]
      var now = history.idsOf(history.snapshotOf(root))
      var before = Runs.hasKey(previous, root) && Array.isArray(previous[root]) ? previous[root] : []
      var held = history.idsOf(entry.runs)
      var moved = []
      for (var i = 0; i < before.length; i++) {
        var run = before[i]
        if (!history.isTerminal(run) || now.indexOf(run.id) >= 0 || held.indexOf(run.id) >= 0) continue
        held.push(run.id)
        moved.push(run)
      }
      var runs = moved.concat(entry.runs).filter(function(kept) { return now.indexOf(kept.id) < 0 })
      if (history.sameRuns(runs, entry.runs)) continue
      map[root] = { runs: runs, more: entry.more, loading: entry.loading, error: entry.error }
      changed = true
    }
    if (changed) history.historyByProject = map
  }
```

Replace

```qml
  QtObject {
    id: historyState
    property var runners: ({})   // {root: HelperRunner}, made on each root's first launch
  }
```

with

```qml
  QtObject {
    id: historyState
    property var runners: ({})    // {root: HelperRunner}, made on each root's first launch
    property var previous: ({})   // the snapshotByProject value the last change left
  }
```

Note on `test_overflow_keeps_the_previous_snapshot_order`: when the snapshot lists `h1` again, `h1` leaves the history (snapshot wins); when it leaves the snapshot once more, it is terminal and moves to the front — so the history reads `h1,a2,a3`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_history_store`
Expected: PASS — `Totals: 23 passed, 0 failed`, no `TypeError`/`ReferenceError` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunHistoryStore.qml tests/core/stores/tst_run_history_store.qml
git commit -m "feat(runs): RunHistoryStore folds window overflow and resumed runs on a snapshot change"
```

---

### Task 4: Pages are dropped on a query change and on the panel closing

**Files:**
- Modify: `core/stores/RunHistoryStore.qml` (add the `active`/filter change handlers, extend `Component.onCompleted`, add `queryKey`, `queryChanged`, `dropAll`; add `query` to `historyState`)
- Modify: `tests/core/stores/tst_run_history_store.qml` (append a `---- dropped pages` section before the final `}`)

**Interfaces:**
- Consumes: Task 1's `historyByProject`, `historyState.runners`, `showOlder`; Task 3's `cancelRunner`; `Runs.historyStatuses`.
- Produces: `queryKey(): string`; `queryChanged(): void`; `dropAll(): void`; `historyState.query`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_history_store.qml`, insert before the file's final closing `}`:

```qml

  // ---- dropped pages

  // The processes `procs` (from inFlight) reply after their roots were
  // dropped: no entry comes back.
  function lateRepliesLandNowhere(s, procs) {
    reply(procs.a, pageOk([h2()], false), 0)
    reply(procs.b, pageOk([hb2()], false), 0)
    compare(JSON.stringify(Object.keys(s.historyByProject)), "[]", "the dropped roots' old replies create no entry")
  }

  function test_a_changed_age_drops_every_root() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    var procs = inFlight(s)
    s.finishedAge = "week"
    compare(JSON.stringify(Object.keys(s.historyByProject)), "[]")
    compare(s.runnerFor(tc.rootA).busy, false, "rootA's fetch is cancelled")
    compare(s.runnerFor(tc.rootB).busy, false)
    lateRepliesLandNowhere(s, procs)
  }

  function test_a_changed_finished_state_under_finished_drops_every_root() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    s.runFilter = "finished"
    var procs = inFlight(s)
    s.finishedState = "done"
    compare(JSON.stringify(Object.keys(s.historyByProject)), "[]")
    lateRepliesLandNowhere(s, procs)
  }

  function test_a_changed_chip_drops_every_root() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    var procs = inFlight(s)
    s.runFilter = "parked"
    compare(JSON.stringify(Object.keys(s.historyByProject)), "[]")
    lateRepliesLandNowhere(s, procs)
  }

  function test_a_finished_state_change_under_all_drops_nothing() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    var procs = inFlight(s)
    s.finishedState = "done"
    compare(idsOf(s, tc.rootA), "h1", "the All chip's status list did not change")
    compare(idsOf(s, tc.rootB), "hb1")
    compare(s.historyByProject[tc.rootA].loading, true)
    reply(procs.a, pageOk([h2()], false), 0)
    compare(idsOf(s, tc.rootA), "h1,h2", "the page in flight still lands")
  }

  function test_closing_the_panel_drops_every_root() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    var procs = inFlight(s)
    s.active = false
    compare(JSON.stringify(Object.keys(s.historyByProject)), "[]")
    lateRepliesLandNowhere(s, procs)
  }

  function test_show_older_after_a_drop_starts_over_from_the_snapshot() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    page(s, tc.rootA, [h1(), h2()], true)
    s.finishedAge = "week"
    s.showOlder(tc.rootA)
    var cmd = argv(s.runnerFor(tc.rootA).current)
    compare(cmd.indexOf(tc.historyCmd + tc.rootA + "|--before|2026-10-03T00:00:00Z|--status|" + tc.allStatuses + "|--since|"), 0,
            "the cursor comes from the snapshot alone: " + cmd)
    compare(JSON.stringify(s.historyByProject[tc.rootA].runs), "[]")
    compare(s.historyByProject[tc.rootA].more, false)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_history_store`
Expected: FAIL — `test_a_changed_age_drops_every_root`, `test_a_changed_finished_state_under_finished_drops_every_root`, `test_a_changed_chip_drops_every_root`, `test_closing_the_panel_drops_every_root` and `test_show_older_after_a_drop_starts_over_from_the_snapshot` fail (the entries survive). `test_a_finished_state_change_under_all_drops_nothing` already passes: it guards the code this task adds.

- [ ] **Step 3: Implement the drops**

In `core/stores/RunHistoryStore.qml`, replace

```qml
  onSnapshotByProjectChanged: history.snapshotChanged()
  Component.onCompleted: historyState.previous = history.snapshotByProject
```

with

```qml
  onActiveChanged: if (!history.active) history.dropAll()
  onSnapshotByProjectChanged: history.snapshotChanged()
  onRunFilterChanged: history.queryChanged()
  onFinishedStateChanged: history.queryChanged()
  onFinishedAgeChanged: history.queryChanged()
  Component.onCompleted: {
    historyState.previous = history.snapshotByProject
    historyState.query = history.queryKey()
  }
```

Insert, right after the closing `}` of `snapshotChanged` and before the `// Bookkeeping kept apart` comment:

```qml

  // The query the loaded pages were fetched under: the status list and finishedAge.
  function queryKey() {
    return Runs.historyStatuses(history.runFilter, history.finishedState).join(",") + "|" + history.finishedAge
  }

  // runFilter, finishedState or finishedAge changed: when the query differs
  // from the last one, every root's pages are dropped.
  function queryChanged() {
    var key = history.queryKey()
    if (key === historyState.query) return
    historyState.query = key
    history.dropAll()
  }

  // Every root's entry goes and every fetch in flight is cancelled.
  function dropAll() {
    var roots = Object.keys(historyState.runners)
    for (var i = 0; i < roots.length; i++) history.cancelRunner(roots[i])
    if (Object.keys(history.historyByProject).length > 0) history.historyByProject = {}
  }
```

Replace

```qml
    property var runners: ({})    // {root: HelperRunner}, made on each root's first launch
    property var previous: ({})   // the snapshotByProject value the last change left
```

with

```qml
    property var runners: ({})    // {root: HelperRunner}, made on each root's first launch
    property var previous: ({})   // the snapshotByProject value the last change left
    property string query: ""     // queryKey() of the loaded pages
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_history_store`
Expected: PASS — `Totals: 29 passed, 0 failed`, no `TypeError`/`ReferenceError` lines, exit 0. Task 1's `test_the_status_list_follows_the_chip_and_the_finished_state` still passes: each chip change drops the entry and the next `showOlder` relaunches.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunHistoryStore.qml tests/core/stores/tst_run_history_store.qml
git commit -m "feat(runs): RunHistoryStore drops every page on a query change and on closing"
```

---

### Task 5: Compose `app.runHistory` in App and document it

**Files:**
- Modify: `tests/architecture/test_run_store_docs.py` (docstring line 1, `STORES` line 19, `README_TOKENS` lines 24–25)
- Modify: `tests/core/stores/tst_app_runs.qml` (header comment lines 13–17; append one test before the final `}`)
- Modify: `core/stores/App.qml` (new block after the `runTitles` block, which ends at line 165)
- Modify: `docs/architecture.md` (new bullet right after line 94, the `RunTitlesStore.qml` bullet)

**Interfaces:**
- Consumes: `RunHistoryStore` (Tasks 1–4); `app.backendDir`, `app.panelOpen`, `app.runs.runsByProject`, `app.runs.runFilter`, `app.runs.toggleRunFilter(id)`.
- Produces: `app.runHistory` (a `RunHistoryStore`), for card 3.3 (binds `finishedState`/`finishedAge`, merges `historyByProject` into the list) and the UI (`showOlder`).

- [ ] **Step 1: Write the failing tests**

(a) In `tests/architecture/test_run_store_docs.py`, replace line 1

```python
"""docs/architecture.md describes the five run stores as App composes them; README.md names none.
```

with

```python
"""docs/architecture.md describes the six run stores as App composes them; README.md names none.
```

replace

```python
STORES = ["RunStore", "RunControlStore", "RunAlertsStore", "RunDispatchStore", "RunTitlesStore"]
```

with

```python
STORES = ["RunStore", "RunControlStore", "RunAlertsStore", "RunDispatchStore", "RunTitlesStore", "RunHistoryStore"]
```

and replace

```python
README_TOKENS = ["RunStore", "RunControlStore", "RunAlertsStore", "RunDispatchStore", "RunTitlesStore",
                 "app.runs", "app.runControl", "app.runAlerts", "app.runDispatch", "app.runTitles", "shim"]
```

with

```python
README_TOKENS = ["RunStore", "RunControlStore", "RunAlertsStore", "RunDispatchStore", "RunTitlesStore",
                 "RunHistoryStore", "app.runs", "app.runControl", "app.runAlerts", "app.runDispatch",
                 "app.runTitles", "app.runHistory", "shim"]
```

(b) In `tests/core/stores/tst_app_runs.qml`, replace the header lines

```qml
// `app.runTitles`, which App feeds with the registry, the open project's root
// and card map, the run list and the panel-open flag. The stores' own
// behaviour is tested in tst_run_store.qml, tst_run_alerts_store.qml,
// tst_run_control_store.qml, tst_run_dispatch_store.qml and
// tst_run_titles_store.qml.
```

with

```qml
// `app.runTitles`, which App feeds with the registry, the open project's root
// and card map, the run list and the panel-open flag, and `app.runHistory`,
// which App feeds with the backend dir, the panel-open flag, the run store's
// per-project snapshot and its chip. The stores' own behaviour is tested in
// tst_run_store.qml, tst_run_alerts_store.qml, tst_run_control_store.qml,
// tst_run_dispatch_store.qml, tst_run_titles_store.qml and
// tst_run_history_store.qml.
```

and insert before the file's final closing `}`:

```qml

  function test_app_composes_run_history_wired_to_the_run_store() {
    var app = make(); if (!app) return
    verify(app.runHistory, "App composes the history store as app.runHistory")
    compare(app.runHistory.backendDir, "/plugin/core/backend/")
    compare(JSON.stringify(app.runHistory.snapshotByProject), JSON.stringify(app.runs.runsByProject))
    compare(app.runHistory.finishedState, "", "not bound yet: every finished state")
    compare(app.runHistory.finishedAge, "all", "not bound yet: all time")
    compare(app.runHistory.active, false)
    app.panelOpen = true
    compare(app.runHistory.active, true, "active follows app.panelOpen")
    var text = listReply([runningIn("r1")], [])
    reply(app.runs.snapshotRunner.current, text, 0)
    reply(app.runs.snapshotRunner.current, text, 0)
    compare(app.runs.runsByProject[tc.pA.root_path].length, 1)
    compare(JSON.stringify(app.runHistory.snapshotByProject), JSON.stringify(app.runs.runsByProject),
            "snapshotByProject follows app.runs.runsByProject after an ok snapshot reply")
    app.runs.toggleRunFilter("parked")
    compare(app.runHistory.runFilter, "parked", "runFilter follows app.runs.runFilter")
    app.runs.toggleRunFilter("all")
    compare(app.runHistory.runFilter, "")
    app.panelOpen = false
    compare(app.runHistory.active, false)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m pytest tests/architecture/test_run_store_docs.py -q` (or `uv run --with pytest python3 -m pytest tests/architecture/test_run_store_docs.py -q`)
Expected: FAIL — `test_each_run_store_has_one_bullet_in_order`, `test_each_bullet_names_its_app_handle[RunHistoryStore]` and `test_each_bullet_names_every_input_and_routed_signal_app_wires[RunHistoryStore]` fail with `AssertionError: 0 top-level - \`RunHistoryStore.qml\` bullets, want 1` / `App composes no RunHistoryStore`.

Run: `bash tests/run.sh tst_app_runs`
Expected: FAIL — pytest fails as above, and `test_app_composes_run_history_wired_to_the_run_store` fails at `verify(app.runHistory, ...)`.

- [ ] **Step 3: Compose the store in App**

In `core/stores/App.qml`, insert right after the `runTitles` block (after its closing `  }` and before the blank line and the `// The dispatch never imports the run store or run control` comment):

```qml

  // The run history never imports the run store: App hands it the backend
  // directory, the panel-open flag, the run store's per-project snapshot and
  // its chip. App routes no signal from it.
  readonly property RunHistoryStore runHistory: RunHistoryStore {
    backendDir: app.backendDir
    active: app.panelOpen
    snapshotByProject: app.runs.runsByProject
    runFilter: app.runs.runFilter
  }
```

- [ ] **Step 4: Document the store**

In `docs/architecture.md`, insert a new line right after line 94 (the line that starts `` - `RunTitlesStore.qml` the run titles``) and before the blank line that follows it:

```markdown
- `RunHistoryStore.qml` the older runs: each snapshot root's history, fetched a page at a time on demand. It never reaches for another store: `App` composes it as `app.runHistory` and hands it `backendDir`, `active` (App's `panelOpen`), `snapshotByProject` (`app.runs.runsByProject`) and `runFilter` (`app.runs.runFilter`); its inputs `finishedState` (default `""`, every finished state) and `finishedAge` (default `"all"`, all time) are not bound yet. App routes no signal from it. Its state is `historyByProject` (`{root: {runs, more, loading, error}}`), keyed by the root exactly as `snapshotByProject` keys it and replaced, never changed in place; a root has an entry from its first launched page until its pages are dropped. `showOlder(root)` runs `runs-history.py ROOT --before CURSOR --status S1,S2,... [--since ISO]` on that root's own `HelperRunner` (`runnerFor(root)`), and only while `active`, for a root `snapshotByProject` has, with a non-empty status list (`Runs.historyStatuses(runFilter, finishedState)`; the `live` chip has none) and a cursor (`Runs.historyCursor` over the root's snapshot and history runs: the oldest terminal `started_at`, so pages chain). `--since` is local midnight for `today` and now minus 7 days for `week`, absent otherwise; no `--limit` is passed. Latest wins per root, and roots page independently. An ok page appends its runs, built like the snapshot's, minus every id the root's snapshot or history already lists, and sets `more`; any other reply keeps `runs` and `more`, clears `loading` and sets `error` (`Runs.errorText`), with no toast. On a snapshot change a root that leaves loses its pages, a terminal run that leaves the snapshot of a root with history moves to the front of that history, and a history run the snapshot lists again (a resumed run) leaves the history; a snapshot change never fetches. A changed query (status list or `finishedAge`) and the panel closing drop every root's pages; the project filter keeps them. Dropping cancels the root's fetch in flight. History is never compared for alerts and never refetched by the watch.
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `python3 -m pytest tests/architecture/test_run_store_docs.py -q`
Expected: PASS — every test, including the three `RunHistoryStore` cases and `test_the_readme_names_no_run_store`.

Run: `bash tests/run.sh tst_app_runs`
Expected: PASS — `test_app_composes_run_history_wired_to_the_run_store` passes, no `TypeError`/`ReferenceError`/`Unable to assign` lines, exit 0.

- [ ] **Step 6: Run the whole suite**

Run: `timeout 900 bash tests/run.sh`
Expected: exit 0 — pytest all green (`tests/architecture/test_layers.py`, `test_icon_glyphs.py`, `test_run_store_docs.py` included) and every QML file's `Totals:` line with `0 failed`, no `TypeError`, `ReferenceError`, `Unable to assign` or `is not a function` line.

- [ ] **Step 7: Commit**

```bash
git add core/stores/App.qml docs/architecture.md tests/core/stores/tst_app_runs.qml tests/architecture/test_run_store_docs.py
git commit -m "feat(runs): App composes RunHistoryStore as app.runHistory; document it"
```

---

## Spec coverage check

| Spec item | Task |
|---|---|
| Inputs and defaults (`backendDir`, `active`, `snapshotByProject`, `runFilter`, `finishedState` `""`, `finishedAge` `"all"`) | 1 (declared), 5 (App binds four; test checks the two defaults) |
| Terms: snapshot root used exactly as key; run root; terminal run; the query | 1 (`isSnapshotRoot`, `runRootOf`, trailing-slash test), 3 (`isTerminal`), 4 (`queryKey`) |
| State `historyByProject`, replaced, new entry object per change; `runnerFor`; runner script | 1 (`setEntry`, `runnerFor`, `runnerC`), 3 (`sameRuns`, spy test) |
| `showOlder` preconditions (active, snapshot root, non-empty status list, cursor) | 1 (four no-op tests) |
| Cursor over S ++ H with the run root; pages chain | 1, 2 (`test_pages_chain_from_the_oldest_run_listed_so_far`) |
| Argv order, no `--limit`; `--since` today/week/none | 1 |
| Entry on launch keeps runs/more, loading true, error "" | 1, 2 (chain and error tests) |
| Latest wins per root; roots independent | 2 (supersede and independent tests) |
| Reply ok: plain objects only, row without `status`, `withProject(.., root, name)`, name rule, dedupe vs snapshot and history, append order, `more === true` | 2 |
| Reply error: non-zero exit, ok:false, unparsable, no `runs` array; rows/more kept; errorText rule; no signal | 2 |
| Reply from cancelled/superseded launch or root without entry changes nothing | 2 (supersede), 3 (removed root), 4 (`lateRepliesLandNowhere`) |
| Snapshot change: removed root dropped and cancelled | 3 |
| Window overflow: terminal only, previous order, front, no id twice, root without history moves nothing | 3 |
| Snapshot wins (resumed run) | 3 |
| Entry replaced only when runs changed; snapshot change never fetches | 3 |
| Query change drops (status list or age differs); same query drops nothing | 4 |
| Panel close drops | 4 |
| Never: no signal, only `showOlder` fetches, never inactive/non-snapshot root/two per root, never writes | 1, 3, 4 (structure: no `signal`, one runner per root, read-only helper) |
| App wiring block and comment | 5 |
| Docs bullet after `RunTitlesStore.qml`; `test_run_store_docs.py` `STORES` six, `README_TOKENS` | 5 |
| `tst_app_runs.qml` header and wiring test | 5 |
| Whole suite green, no `TypeError` etc. | every task's run step, 5 Step 6 |
<!-- task-pipeline: validated -->
