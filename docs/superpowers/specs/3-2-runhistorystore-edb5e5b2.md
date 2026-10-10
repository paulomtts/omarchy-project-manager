# 3.2 RunHistoryStore: older runs a page at a time — design

Card `edb5e5b2-f3c1-476d-9285-0f5709ee5793`, a subtask of story `b477c51f` (History and
titles stores). Parent design: `docs/superpowers/specs/2026-10-05-run-history-titles-design.md`
(below, "parent"). This card adds `core/stores/RunHistoryStore.qml`, composes it in `App.qml`
as `app.runHistory`, and documents it. It turns the parent's **Store** section
(parent :153-172) into a store. No screen and no other store reads it yet.

## Where the card overrides the parent

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

## Inherited constraints

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

## Behaviour

### Inputs

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

### Terms

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

### State

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

### `showOlder(root)`

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

### A reply

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

### The snapshot changes

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

### Pages are dropped

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

### Never

- History is never compared for alerts: the store has no signal, and App routes nothing from
  it.
- History is never refetched by the watch or by a snapshot: only `showOlder` launches the
  helper.
- The store never fetches while inactive, never fetches a root that is not a snapshot root,
  never has two fetches in flight for one root, and never writes.

### App wiring

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

### Docs

`docs/architecture.md` gains one top-level bullet, `` - `RunHistoryStore.qml` … ``, right
after the `RunTitlesStore.qml` bullet (`docs/architecture.md:94`). It names:

- `app.runHistory`;
- every bound input, each backticked: `backendDir`, `active`, `snapshotByProject`,
  `runFilter`;
- the unbound inputs `finishedState` and `finishedAge` and their defaults;
- `historyByProject` and its entry shape;
- `showOlder(` and the rules above (cursor, argv, latest wins per root, reply, overflow,
  drops, never), in one paragraph.

## Tests (TDD: written first, seen failing)

### `tests/core/stores/tst_run_history_store.qml` (new)

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

### `tests/core/stores/tst_app_runs.qml`

Tier: App composition test, the existing home of App's run-store wiring. Its header comment's
list of composed stores gains `app.runHistory` and `tst_run_history_store.qml`.

11. **runHistory exists and is wired.** `make()` gives `app.runHistory` with:
    - `backendDir` `/plugin/core/backend/`;
    - `snapshotByProject` equal to `app.runs.runsByProject`, before and after an ok snapshot
      reply;
    - `runFilter` following `app.runs.runFilter`;
    - `active` following `app.panelOpen`;
    - `finishedState` `""` and `finishedAge` `"all"`.

### `tests/architecture/test_run_store_docs.py`

Tier: architecture doc test. It pins every run store's App wiring to its docs bullet.

12. `STORES` gains `"RunHistoryStore"` after `"RunTitlesStore"`, and the module docstring
    says "six". The existing parametrized tests then require the new bullet:
    - in order;
    - naming `` `app.runHistory` ``;
    - naming every input App binds.

    `README_TOKENS` gains `"RunHistoryStore"` and `"app.runHistory"`.

### Unchanged and still green

`tests/architecture/test_layers.py` (store imports, duplication guards),
`test_icon_glyphs.py` (no glyphs) and the whole `bash tests/run.sh`. `tests/run.sh` fails on
any `TypeError`, `ReferenceError`, `Unable to assign` or `is not a function` line, so the
store must emit none of them.

## Accepted

- The history store builds its row with a small store-local copy of `RunStore.rowOf`
  (`RunStore.qml:762-768`), because a store may not reference another store. Moving it to
  `runs.js` would touch `RunStore`, which is outside this card.
- A project renamed in the registry keeps its old `project.name` on rows already in history
  until they are dropped. The next page and moved runs take the current name.

## Out of scope

- Merging history into `RunStore.filteredRuns`, the display order, `finishedState` and
  `finishedAge` on `RunStore`, and binding them here: card 3.3.
- Titled alerts and any `RunAlertsStore` change: card 3.4. `RunTitlesStore` gets no history
  runs.
- Any UI: **Show older**, `Loading older runs…`, the error line, the Finished chip rows.
- `runs-history.py` (1.2) and the `runs.js` functions (`historyStatuses`, `historyCursor`,
  `withinAge`): they exist and are used as they are.
- Passing `--limit`, persistence, any `am` or `brd` change.
