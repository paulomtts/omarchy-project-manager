# 2.1 runs.js: run titles from a title map — design

Card `41e2402b-1c4b-48e3-8f3e-0d79c2fcf251`, a subtask of story `091a4b97`.
Parent design: `docs/superpowers/specs/2026-10-05-run-history-titles-design.md` (below,
"parent"). This card puts the parent's **Display** section (parent :96-108) into
`core/domain/runs.js`. It wires no caller and adds no store.

## Inherited constraints

- The titles come from a map `{id: title}` for each project. Callers pass the map for the
  run's project (`titlesByRoot[run.project.root]`). A missing map is `{}` (parent :102-103).
- `titlesFromCards(cardMap)` builds that map from a `Board.indexTree` card map
  (parent :98; `core/domain/board.js:12`).
- Run kinds and fallbacks are `milestone …<last 8>`, `story …<last 8>` and `card …<last 8>`.
  A run that names no milestone, story or card falls back to its short run id
  (parent :99-103).
- `runSubtitle(run)` is `Runs.shortId(run)` (parent :104; Goal at :48-50: "the short run id
  as secondary text").
- `cardTitle(id, run, titles)` returns the map's title, else the run's own story title. It
  returns `""` when it finds neither (parent :105-106).
- `searchRuns(runs, q, titlesByRoot)` also matches the title. `newAlerts(prev, next,
  titlesByRoot)` puts the title on each alert (parent :107-108).
- `am status` records no milestone or subtask title. Only `stories[].title` exists
  (parent :23-27).
- If brd no longer has a card id, the run shows the short id (parent Errors table :199).
- Tests go in `tests/core/domain/tst_runs.qml`, with fixtures from `tests/fixtures/am/`
  (parent :215-218).
- Layering follows `docs/architecture.md`, and `tests/architecture` must pass.
  `runs.js` stays an ES5 `.pragma library` that never throws. Comments state the contract
  only, with no narrative (card).

## Behaviour

### Run identity on the normalized run: `normalizeRun`

Today `normalizeRun` (`runs.js:45-148`) copies only `milestone_id` from the run's ids. The
`am runs` row already has `story_id` and `card_id`, and both are `null` in
`tests/fixtures/am/runs.json`. `am status`' `run` has `story_id` too. `runTitle` needs to
read both, so `normalizeRun` gains two output keys:

- `story_id`: the first non-empty string among `status.run.story_id` and `row.story_id`,
  else `""`.
- `card_id`: the first non-empty string among `status.run.card_id` and `row.card_id`,
  else `""`.

A non-string value, `null` included, counts as missing. Status wins over the row, as it
already does for `milestone_id`. The default run's key set
(`checkDefaults` in `tst_runs.qml:33-34`) becomes
`base_branch,branch_prefix,card_id,id,lease,milestone_id,project,repo_dir,requests,rows,started_at,status,story_id,tree,workflow`,
and both new keys default to `""`.

### Shared rules for titles

- A **usable title** is a string that is not empty after trimming. It is returned trimmed.
  Any other value (non-string, `""`, all spaces) is treated as no title.
- A **titles map** is used only when it is a plain object (not null and not an array).
  Anything else (`undefined`, `null`, a string, a number, an array) acts as `{}`.
- Every map lookup checks for an own property (`hasKey`, `runs.js:1358`). An id such as
  `constructor`, `__proto__`, `toString` or `hasOwnProperty` therefore finds a title only
  when the map holds that key itself. It never finds an `Object.prototype` member.
- An **id** (milestone, story or card) counts only when it is a non-empty string.
- `<last 8>` is the last 8 characters of the named id, or the whole id when it is shorter.
  The fallback is the kind word, one space, `…`, then those characters, for example
  `milestone …a4b5c6d7`.

### `titlesFromCards(cardMap)`

- Returns a new plain object. For each own enumerable key of `cardMap` whose value is a
  plain object with a usable `title`, it maps that key to the trimmed title.
- Cards without a usable title are skipped. A `cardMap` that is not a plain object gives
  `{}`.
- A key named `__proto__` or `constructor` becomes an ordinary own key of the result.
  The result's prototype is unchanged and nothing leaks into `Object.prototype`.
- The function never mutates `cardMap` and never throws.

### `runTitle(run, titles)`

The run's kind is decided in this order:

1. **Card run**: `card_id` is an id. Returns the map's title for `card_id`, else
   `card …<last 8 of card_id>`.
2. **Story run**: `story_id` is an id. Returns the map's title for `story_id`, else the
   usable `title` of the first object in `run.tree.stories` whose `card_id === story_id`,
   else `story …<last 8 of story_id>`.
3. **Milestone run**: `milestone_id` is an id. Returns the map's title for `milestone_id`,
   else `milestone …<last 8 of milestone_id>`.
4. Otherwise it returns `shortId(run)`. For a run that is not an object, or one whose id is
   not a string, that is `"…"`.

A card run never falls back to a story or milestone title, and a story run never falls
back to its milestone. The function works with `titles` omitted, so the five existing
single-argument callers (`RunsScreen.qml:506`, `CardDetailScreen.qml:261`,
`Panel.qml:840`, and the `searchRuns`/`newAlerts` internals) keep working unchanged.

**Visible change:** a milestone run with no titles used to show its raw `milestone_id`. It
now shows `milestone …<last 8>`.

### `runSubtitle(run)`

Returns exactly `shortId(run)` for any input.

### `cardTitle(id, run, titles)`

- If `id` is not an id, returns `""`.
- Otherwise returns the map's title for `id`, else the usable `title` of the first object
  in `run.tree.stories` whose `card_id === id`, else `""`.
- A garbage `run` (not an object, or with no tree) has no story titles.

Subtask titles come only from the map, since `am status` has none.

### `searchRuns(runs, q, titlesByRoot)`

- Behaves as today (`runs.js:618-630`). The haystack's title part is
  `runTitle(run, <the run's map>)`.
- The run's map is `titlesByRoot[runRoot(run)]`. It is used only when `titlesByRoot` is a
  plain object that holds that root as an own key and the value is a plain object.
  Otherwise the map is `{}`. A run whose `runRoot` is `""` always uses `{}`.
- With `titlesByRoot` omitted, every run's title is its fallback, so a query such as
  `milestone` matches every untitled milestone run. This is expected.

### `newAlerts(prevRuns, nextRuns, titlesByRoot)`

- Behaves as today (`runs.js:977-996`). Each alert's `title` is
  `runTitle(run, <the run's map>)`, with the map chosen by the same rule as in
  `searchRuns`.
- Omitting the argument gives fallback titles.

### Never throws

None of the five functions throws, and none mutates its inputs. That holds for any value
of any argument, including `undefined`, `null`, strings, numbers, arrays,
prototype-named ids, and maps holding non-string values.

## Tests (TDD: written first, seen failing)

All the new tests are QML `TestCase` functions in `tests/core/domain/tst_runs.qml`. That
is the **domain unit tier**: these are pure `.pragma library` functions with no store, no
process and no UI, and this file is where `runs.js` is tested. The existing helpers are
`mkRun`, `amRun`/`fixtureRuns`, `alRunning`/`alEscalated`/`alDead`, `checkAlert` and the
garbage-array loops.

1. `normalizeRun` story and card ids: taken from the row, taken from the status run, the
   status winning over the row, and `null`/number/`""` giving `""`. The fixture runs
   (`runs.json` rows have `null` for both) give `""`. `checkDefaults` gets the new key list.
2. `titlesFromCards`: a small `indexTree` map gives `{id: title}`, and nested cards are
   included because `indexTree` already flattens them. Cards with a missing, non-string,
   empty or all-space title are skipped, and titles come back trimmed. `undefined`,
   `null`, `"x"`, `5` and `[]` give `{}`. A map with keys `__proto__` and `constructor`
   gives own keys with those titles, and `({}).polluted`/`Object.prototype` are
   unchanged. The input is not mutated.
3. `runTitle` for each kind, with titles: a card run gives the card title, a story run the
   map's story title, and a milestone run the milestone title.
4. `runTitle` for each kind, without titles (map omitted, `{}`, `null`, `[]`, `"x"`): the
   results are `card …<8>`, `story …<8>` and `milestone …<8>`. An id shorter than 8
   characters is shown whole.
5. `runTitle` story run with no map entry: it uses the am status story title from
   `run.tree.stories`. A real fixture run (`status-started.json`, with its `story_id` set
   on the test copy) gives `Dispatch domain`. The map title wins over the am title. An
   unusable am title gives `story …<8>`.
6. `runTitle` precedence: a run with `card_id`, `story_id` and `milestone_id` all set is a
   card run, and a card run whose card has no title gives `card …`, not the story or
   milestone title. A run naming nothing gives `shortId(run)`. Garbage runs give `"…"`.
7. `runTitle` with prototype-named ids (`constructor`, `__proto__`, `toString`) as card,
   story and milestone ids: with `{}` the result is the fallback, never a function or
   `[object Object]`. With a map holding that key as an own property, the result is its
   title.
8. `runSubtitle` equals `shortId` for a normal run, a short id and the garbage inputs.
9. `cardTitle`: a title from the map, from the run's story title, and from the map when
   both exist (the map wins). An unknown id gives `""`, and so do a non-string or empty
   id, a garbage run and garbage titles. Prototype-named ids give `""` unless the map
   holds them as own keys.
10. `searchRuns` by title: given `titlesByRoot` keyed by `run.project.root` (built with
    `withProject`), a query for a title substring (case-insensitive) finds the run. A run of
    another root uses that root's map. A run whose root is missing from `titlesByRoot`,
    or has the value `null`, uses fallbacks. A root named `constructor` or `__proto__`
    is read safely. The existing id/phase/state matches still hold.
11. `newAlerts` titles: with `titlesByRoot` the alert title is the run's mapped title.
    Without it the title is the fallback (`milestone …<8>` for `mkRun`'s milestone `m1`,
    which is `milestone …m1`). Runs with no ids keep the short-id title.

Existing expectations that change because of the new milestone fallback. These are
**test-only edits in their current tiers**, and the production QML stays untouched:

- `tst_runs.qml`: `test_run_title` (around :1507-1513, `'4bf4fb2f'` becomes
  `'milestone …4bf4fb2f'`), the search test around :1729-1739, and the `newAlerts`
  `checkAlert` titles around :2394-2412 (`'m1'` becomes `'milestone …m1'`).
- Store tier, `tests/core/stores/tst_run_alerts_store.qml:149, :543, :703`: `"m-b1"` and
  `"m-b"` become `"milestone …m-b1"` and `"milestone …m-b"`. Line :148 compares against
  `Runs.newAlerts` directly and keeps passing.
- UI tier, `tests/ui/screens/tst_runs_screen.qml:253` (`runRowTitle0`, milestone `alpha`)
  and `tests/ui/tst_runs_flow.qml:408` (the cancel modal's detail `alpha`): both become
  `milestone …alpha`.
- The arbiter is `bash tests/run.sh`. Any other failing assertion whose expected value is
  a run's raw milestone id shown as a title is updated the same way. Nothing else changes.

Verification: `bash tests/run.sh` is green (pytest, including `tests/architecture`, then
every `tst_*.qml`).

## Out of scope

- Every caller passing a map. That means `RunStore.searchRuns`, `RunAlertsStore.newAlerts`,
  `RunsScreen` rows with `runSubtitle`, `Panel` cancel detail, `CardDetailScreen` RUNS
  rows, and Run detail's header and tree using `cardTitle`. These belong to sibling cards
  of this story or later stories.
- `core/stores/RunTitlesStore.qml` and `core/backend/boards/board-titles.py`
  (parent :63-94).
- The history work: `runs-history.py`, `filterRuns` finished, `withinAge`,
  `historyStatuses`, `historyCursor` and `RunHistoryStore` (parent :117-192).
- Any `am` or `brd` change, and any change to `board.js`.
