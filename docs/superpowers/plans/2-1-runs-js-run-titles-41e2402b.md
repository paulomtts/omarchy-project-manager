# 2.1 runs.js: run titles from a title map — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `core/domain/runs.js` brd-backed run titles: `normalizeRun` keeps `story_id`/`card_id`, and `titlesFromCards`, `runTitle(run, titles)`, `runSubtitle`, `cardTitle`, `searchRuns(…, titlesByRoot)` and `newAlerts(…, titlesByRoot)` read a `{id: title}` map with kind fallbacks (`milestone …<8>`, `story …<8>`, `card …<8>`).

**Architecture:** Everything is pure ES5 in the existing `.pragma library` file `core/domain/runs.js`; no caller, store or UI file changes (only test expectations that the new milestone fallback changes). Map lookups go through the existing own-key `hasKey`, map choice per run through the existing `runRoot`. Tests are QML `TestCase` functions in `tests/core/domain/tst_runs.qml`.

**Tech Stack:** QML/JS (Qt 6 V4 engine, ES5 subset in `.pragma library`), QtTest via `qmltestrunner`, `bash tests/run.sh` (pytest + every `tst_*.qml`).

**Spec:** `docs/superpowers/specs/2-1-runs-js-run-titles-41e2402b.md` (prepended below). Parent design: `docs/superpowers/specs/2026-10-05-run-history-titles-design.md`.

## Global Constraints

- `runs.js` stays an ES5 `.pragma library` that never throws. Comments state the contract only, with no narrative.
- Layering follows `docs/architecture.md`, and `tests/architecture` must pass.
- Tests go in `tests/core/domain/tst_runs.qml`, with fixtures from `tests/fixtures/am/`.
- Run kinds and fallbacks are `milestone …<last 8>`, `story …<last 8>` and `card …<last 8>`. A run that names no milestone, story or card falls back to its short run id.
- `<last 8>` is the last 8 characters of the named id, or the whole id when it is shorter. The fallback is the kind word, one space, `…`, then those characters, for example `milestone …a4b5c6d7`.
- A **usable title** is a string that is not empty after trimming. It is returned trimmed.
- A **titles map** is used only when it is a plain object (not null and not an array). Anything else acts as `{}`.
- Every map lookup checks for an own property (`hasKey`, `runs.js:1358`).
- An **id** (milestone, story or card) counts only when it is a non-empty string.
- None of the five functions throws, and none mutates its inputs.
- Out of scope: every caller passing a map, `RunTitlesStore.qml`, `board-titles.py`, the history work, any `am`/`brd`/`board.js` change.
- Verification: `bash tests/run.sh` is green (pytest, including `tests/architecture`, then every `tst_*.qml`).

## Review Focus

1. **A map whose value for the id is not a string** (`5`, `{}`, `null`, `true`): a reasonable person expects the fallback (or the am story title), never `"5"` or `"[object Object]"`. Pinned in Task 3 (`test_run_title_unusable_map_values`) and Task 4 (`cardTitle` case).
2. **A story run whose map entry is all spaces but am has a story title**: the unusable map entry must fall through to the am title, not to `story …`. Pinned in Task 3 (`test_run_title_story_from_am_status`).
3. **Prototype-less objects** (`Object.create(null)`) as the run, the titles map or `titlesByRoot`: must work like plain objects and never throw on a missing `hasOwnProperty`. Pinned in Task 3 (`test_run_title_prototype_less`) and Task 5 (`test_search_runs_titles_by_root_garbage`).
4. **`titlesByRoot[root]` that is an array, string or number**: acts as `{}` (fallback titles), never indexes into the array/string. Pinned in Task 5 (`test_search_runs_titles_by_root_garbage`, `test_new_alerts_titles_by_root`).
5. **`am status` run `story_id: null` (what every capture has) next to a row `story_id`**: null counts as missing, so the row's id wins instead of the run getting `""` or `"null"`. Pinned in Task 1 (`test_normalize_story_and_card_ids`).

---

## Spec (prepended; headings demoted one level)

## 2.1 runs.js: run titles from a title map — design

Card `41e2402b-1c4b-48e3-8f3e-0d79c2fcf251`, a subtask of story `091a4b97`.
Parent design: `docs/superpowers/specs/2026-10-05-run-history-titles-design.md` (below,
"parent"). This card puts the parent's **Display** section (parent :96-108) into
`core/domain/runs.js`. It wires no caller and adds no store.

### Inherited constraints

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

### Behaviour

#### Run identity on the normalized run: `normalizeRun`

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

#### Shared rules for titles

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

#### `titlesFromCards(cardMap)`

- Returns a new plain object. For each own enumerable key of `cardMap` whose value is a
  plain object with a usable `title`, it maps that key to the trimmed title.
- Cards without a usable title are skipped. A `cardMap` that is not a plain object gives
  `{}`.
- A key named `__proto__` or `constructor` becomes an ordinary own key of the result.
  The result's prototype is unchanged and nothing leaks into `Object.prototype`.
- The function never mutates `cardMap` and never throws.

#### `runTitle(run, titles)`

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

#### `runSubtitle(run)`

Returns exactly `shortId(run)` for any input.

#### `cardTitle(id, run, titles)`

- If `id` is not an id, returns `""`.
- Otherwise returns the map's title for `id`, else the usable `title` of the first object
  in `run.tree.stories` whose `card_id === id`, else `""`.
- A garbage `run` (not an object, or with no tree) has no story titles.

Subtask titles come only from the map, since `am status` has none.

#### `searchRuns(runs, q, titlesByRoot)`

- Behaves as today (`runs.js:618-630`). The haystack's title part is
  `runTitle(run, <the run's map>)`.
- The run's map is `titlesByRoot[runRoot(run)]`. It is used only when `titlesByRoot` is a
  plain object that holds that root as an own key and the value is a plain object.
  Otherwise the map is `{}`. A run whose `runRoot` is `""` always uses `{}`.
- With `titlesByRoot` omitted, every run's title is its fallback, so a query such as
  `milestone` matches every untitled milestone run. This is expected.

#### `newAlerts(prevRuns, nextRuns, titlesByRoot)`

- Behaves as today (`runs.js:977-996`). Each alert's `title` is
  `runTitle(run, <the run's map>)`, with the map chosen by the same rule as in
  `searchRuns`.
- Omitting the argument gives fallback titles.

#### Never throws

None of the five functions throws, and none mutates its inputs. That holds for any value
of any argument, including `undefined`, `null`, strings, numbers, arrays,
prototype-named ids, and maps holding non-string values.

### Tests (TDD: written first, seen failing)

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

### Out of scope

- Every caller passing a map. That means `RunStore.searchRuns`, `RunAlertsStore.newAlerts`,
  `RunsScreen` rows with `runSubtitle`, `Panel` cancel detail, `CardDetailScreen` RUNS
  rows, and Run detail's header and tree using `cardTitle`. These belong to sibling cards
  of this story or later stories.
- `core/stores/RunTitlesStore.qml` and `core/backend/boards/board-titles.py`
  (parent :63-94).
- The history work: `runs-history.py`, `filterRuns` finished, `withinAge`,
  `historyStatuses`, `historyCursor` and `RunHistoryStore` (parent :117-192).
- Any `am` or `brd` change, and any change to `board.js`.

---

## File Structure

- Modify `core/domain/runs.js`:
  - header comment (lines 4-29) and `normalizeRun` (lines 45-148): two new output keys.
  - the "Runs screen (5.1)" section (lines 520-539): new private helpers, new `titlesFromCards`, `runSubtitle`, `cardTitle`, rewritten `runTitle`.
  - `searchRuns` (lines 616-630) and `newAlerts` (lines 971-1000): new third argument.
- Modify `tests/core/domain/tst_runs.qml`: `checkDefaults`, changed expectations, new tests appended at the end (just before the file's final closing `}`), new `board.js` import.
- Modify test expectations only: `tests/core/stores/tst_run_alerts_store.qml`, `tests/ui/screens/tst_runs_screen.qml`, `tests/ui/tst_runs_flow.qml`, `tests/ui/screens/tst_card_detail_screen.qml`.
- Modify `docs/architecture.md:181` (the `runs.js` paragraph) in Task 5.

How to run the domain tests: `timeout 600 bash tests/run.sh tst_runs.qml` (runs pytest first, ~2 minutes, then only `tst_runs.qml`). Failures print as lines starting `FAIL!  : DomainRuns::<test>()` followed by `   Loc:` lines; the last line is `Totals: N passed, M failed, …`. The script also fails on any `TypeError`/`ReferenceError`/`is not a function` in the output.

---

### Task 1: `normalizeRun` keeps `story_id` and `card_id`

**Files:**
- Modify: `core/domain/runs.js:4-29` (header comment), `core/domain/runs.js:45-148` (`normalizeRun`)
- Test: `tests/core/domain/tst_runs.qml:33-50` (`checkDefaults`), `:232` (`test_normalize_scalars_from_fixture` key list), new test appended at the end

**Interfaces:**
- Consumes: nothing new.
- Produces: every `Runs.normalizeRun(raw)` result has `story_id: string` and `card_id: string` (`""` when missing). Tasks 3-5 read `run.story_id` and `run.card_id`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/domain/tst_runs.qml`, replace the first line of `checkDefaults` (line 34):

```qml
    compare(Object.keys(r).sort().join(","), "base_branch,branch_prefix,id,lease,milestone_id,project,repo_dir,requests,rows,started_at,status,tree,workflow", label)
```

with:

```qml
    compare(Object.keys(r).sort().join(","), "base_branch,branch_prefix,card_id,id,lease,milestone_id,project,repo_dir,requests,rows,started_at,status,story_id,tree,workflow", label)
    compare(r.story_id, "", label)
    compare(r.card_id, "", label)
```

In `test_normalize_scalars_from_fixture`, replace its key-list line (line 232):

```qml
    compare(Object.keys(r).sort().join(","), "base_branch,branch_prefix,id,lease,milestone_id,project,repo_dir,requests,rows,started_at,status,tree,workflow")
```

with:

```qml
    compare(Object.keys(r).sort().join(","), "base_branch,branch_prefix,card_id,id,lease,milestone_id,project,repo_dir,requests,rows,started_at,status,story_id,tree,workflow")
```

Then append this test just before the file's final closing `}` (after `test_run_root_of_anything_else_is_empty`):

```qml

  // ---- history-and-titles 2.1: run titles ---------------------------------------------------

  function test_normalize_story_and_card_ids() {
    // synthetic: bare am runs rows and am status runs naming a story and a card
    var fromRow = Runs.normalizeRun({ row: { id: "r1", story_id: "s1", card_id: "c1" } })
    compare(fromRow.story_id, "s1", "story from the row")
    compare(fromRow.card_id, "c1", "card from the row")

    var fromStatus = Runs.normalizeRun({ status: { run: { id: "r2", story_id: "s2", card_id: "c2" } } })
    compare(fromStatus.story_id, "s2", "story from the am status run")
    compare(fromStatus.card_id, "c2", "card from the am status run")

    var both = Runs.normalizeRun({ row: { story_id: "s-row", card_id: "c-row" },
                                   status: { run: { story_id: "s-st", card_id: "c-st" } } })
    compare(both.story_id, "s-st", "the am status run wins over the row")
    compare(both.card_id, "c-st", "the am status run wins over the row (card)")

    var missing = [null, 5, "", true, {}, []]
    for (var i = 0; i < missing.length; i++) {
      var r = Runs.normalizeRun({ row: { story_id: "s-row", card_id: "c-row" },
                                  status: { run: { story_id: missing[i], card_id: missing[i] } } })
      compare(r.story_id, "s-row", "status story " + JSON.stringify(missing[i]) + " counts as missing")
      compare(r.card_id, "c-row", "status card " + JSON.stringify(missing[i]) + " counts as missing")
      var bare = Runs.normalizeRun({ row: { story_id: missing[i], card_id: missing[i] } })
      compare(bare.story_id, "", "row story " + JSON.stringify(missing[i]) + " gives empty")
      compare(bare.card_id, "", "row card " + JSON.stringify(missing[i]) + " gives empty")
    }

    // the captures: am status runs have story_id null, runs.json rows have null story and card ids
    var runs = fixtureRuns()
    for (var j = 0; j < runs.length; j++) {
      compare(runs[j].story_id, "", "fixture " + j + " story_id")
      compare(runs[j].card_id, "", "fixture " + j + " card_id")
    }

    // synthetic: the started capture's am status run story_id set; the row's stays null
    var raw = amRun("status-started.json")
    raw.status.run.story_id = "9f0f68fc-f231-4ef2-b646-00a7af925ea2"
    compare(Runs.normalizeRun(raw).story_id, "9f0f68fc-f231-4ef2-b646-00a7af925ea2", "capture with a story id")
    // synthetic: the row names the story, the am status run keeps its null
    var rowOnly = amRun("status-started.json")
    rowOnly.row.story_id = "row-story"
    compare(Runs.normalizeRun(rowOnly).story_id, "row-story", "a null am status story_id falls back to the row")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_runs.qml`
Expected: FAIL in `test_normalize_garbage` and `test_normalize_scalars_from_fixture` (key list lacks `card_id`/`story_id`; `r.story_id` is `undefined`, not `""`) and in `test_normalize_story_and_card_ids` (`undefined` vs `"s1"`).

- [ ] **Step 3: Implement**

In `core/domain/runs.js`, inside `normalizeRun`, after the line

```js
  function stringOr(v) { return typeof v === "string" ? v : "" }
```

add:

```js
  function firstId(a, b) { return typeof a === "string" && a !== "" ? a : stringOr(b) }
```

In the returned object, replace

```js
    milestone_id: firstText(run.milestone_id, row.milestone_id),
```

with

```js
    milestone_id: firstText(run.milestone_id, row.milestone_id),
    story_id: firstId(run.story_id, row.story_id),
    card_id: firstId(run.card_id, row.card_id),
```

Update the header comment. Replace

```js
//             { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at,
//               milestone_id, card_id, lease, progress, project: { id, repo_dir } }
```

with

```js
//             { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at,
//               milestone_id, story_id, card_id, lease, progress, project: { id, repo_dir } }
```

replace

```js
//               run: { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at },
```

with

```js
//               run: { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at,
//                      milestone_id, story_id, card_id },
```

and replace

```js
// workflow are the row's, else the am status run's; status and milestone_id are
// the am status run's, else the row's. `lease` keeps pid, host, heartbeat_at,
```

with

```js
// workflow are the row's, else the am status run's; status and milestone_id are
// the am status run's, else the row's. story_id and card_id are the am status
// run's when a non-empty string, else the row's when a string, else "".
// `lease` keeps pid, host, heartbeat_at,
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_runs.qml`
Expected: `Totals: … 0 failed`, no `FAIL` lines.

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): normalizeRun keeps the run's story_id and card_id"
```

---

### Task 2: `titlesFromCards(cardMap)`

**Files:**
- Modify: `core/domain/runs.js` — insert in the "Runs screen (5.1)" section, directly after `function _subtasksOf(run) { … }` (line 524)
- Test: `tests/core/domain/tst_runs.qml` — new import at the top, new test appended at the end

**Interfaces:**
- Consumes: `_isObject`, `_trimmedOr` (`runs.js:1118`, hoisted) from `runs.js`; `Board.indexTree(roots)` → `{ cardMap }` in the test only.
- Produces: `Runs.titlesFromCards(cardMap) -> object` — a new plain object `{id: trimmedTitle}`. Also the private helper `_usableTitle(v) -> string` (trimmed title or `""`), used by Tasks 3-4.

- [ ] **Step 1: Write the failing test**

At the top of `tests/core/domain/tst_runs.qml`, after the line `import "../../../core/domain/runs.js" as Runs`, add:

```qml
import "../../../core/domain/board.js" as Board
```

Append just before the file's final closing `}`:

```qml

  function test_titles_from_cards() {
    // synthetic: a brd tree as `brd tree` returns it, indexed by Board.indexTree
    var roots = [{ id: "m1", title: " Milestone one ", children: [
      { id: "s1", title: "Story one", children: [
        { id: "t1", title: "Subtask one", children: [] },
        { id: "t2", children: [] },
        { id: "t3", title: 7, children: [] },
        { id: "t4", title: "", children: [] },
        { id: "t5", title: "   ", children: [] }] }] }]
    var cardMap = Board.indexTree(roots).cardMap
    var before = JSON.stringify(cardMap)
    var titles = Runs.titlesFromCards(cardMap)
    compare(Object.keys(titles).sort().join(","), "m1,s1,t1", "nested cards included, untitled ones skipped")
    compare(titles.m1, "Milestone one", "trimmed")
    compare(titles.s1, "Story one")
    compare(titles.t1, "Subtask one")
    compare(JSON.stringify(cardMap), before, "the card map is not mutated")
    verify(Runs.titlesFromCards(cardMap) !== titles, "a new object on each call")

    // synthetic: non-object cards are skipped
    compare(JSON.stringify(Runs.titlesFromCards({ a: "x", b: null, c: [], d: 5, e: { title: "E" } })), '{"e":"E"}')

    var bad = [undefined, null, "x", 5, []]
    for (var i = 0; i < bad.length; i++)
      compare(JSON.stringify(Runs.titlesFromCards(bad[i])), "{}", "garbage " + i)
  }

  function test_titles_from_cards_prototype_keys() {
    // synthetic: JSON.parse makes __proto__ and constructor own keys of the card map
    var cardMap = JSON.parse('{"__proto__": {"title": "Proto card"}, "constructor": {"title": "Ctor card"}, "toString": {"id": "x"}}')
    var titles = Runs.titlesFromCards(cardMap)
    verify(Object.getPrototypeOf(titles) === Object.prototype, "the result's prototype is unchanged")
    compare(Object.keys(titles).sort().join(","), "__proto__,constructor", "own keys, toString skipped")
    compare(Object.prototype.hasOwnProperty.call(titles, "__proto__"), true, "__proto__ is an own key")
    compare(titles["__proto__"], "Proto card")
    compare(titles.constructor, "Ctor card")
    compare(({}).polluted, undefined, "nothing leaks into Object.prototype")
    compare(Object.prototype.title, undefined, "no title on Object.prototype")
    compare(typeof ({}).constructor, "function", "plain objects keep their constructor")

    var bare = Object.create(null)
    bare.c1 = { title: "Bare" }
    compare(JSON.stringify(Runs.titlesFromCards(bare)), '{"c1":"Bare"}', "a prototype-less card map")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_runs.qml`
Expected: FAIL / `TypeError: Property 'titlesFromCards' of object [object Object] is not a function`.

- [ ] **Step 3: Implement**

In `core/domain/runs.js`, directly after

```js
function _subtasksOf(run) { return _arrayOr(_treeOf(run).subtasks) }
```

insert:

```js

// v trimmed when it is a string that is not blank, else "".
function _usableTitle(v) { return _trimmedOr(v) }

// A new plain object mapping each own enumerable key of cardMap whose card is
// an object with a usable title to that title, trimmed (a Board.indexTree card
// map gives every card of the forest). Keys such as __proto__ become ordinary
// own keys; the result's prototype is Object.prototype. {} when cardMap is not
// a plain object. Never mutates, never throws.
function titlesFromCards(cardMap) {
  var out = {}
  if (!_isObject(cardMap)) return out
  var keys = Object.keys(cardMap)
  for (var i = 0; i < keys.length; i++) {
    var card = cardMap[keys[i]]
    var title = _isObject(card) ? _usableTitle(card.title) : ""
    if (title !== "") Object.defineProperty(out, keys[i], { value: title, enumerable: true, writable: true, configurable: true })
  }
  return out
}
```

(`_trimmedOr` is defined later in the file at the dispatch section; function declarations are hoisted in a `.pragma library`, as `runRoot`/`hasKey` already rely on.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_runs.qml`
Expected: `Totals: … 0 failed`, no `FAIL` lines.

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): titlesFromCards builds an {id: title} map from a brd card map"
```

---

### Task 3: `runTitle(run, titles)` with kind fallbacks

**Files:**
- Modify: `core/domain/runs.js:533-538` (`runTitle`) and insert helpers right above it
- Test: `tests/core/domain/tst_runs.qml:1507-1514` (`test_run_title`), the `checkAlert` lines 2398, 2408, 2418, 2422, 2464, 2468, 2562, 2583, new tests appended at the end
- Test (expectations only): `tests/core/stores/tst_run_alerts_store.qml:149, :543, :703`, `tests/ui/screens/tst_runs_screen.qml:253`, `tests/ui/tst_runs_flow.qml:408`, `tests/ui/screens/tst_card_detail_screen.qml:299`

**Interfaces:**
- Consumes: `run.story_id`, `run.card_id` (Task 1); `_usableTitle` (Task 2); `_isObject`, `_treeOf`, `_findByCardId`, `hasKey`, `shortId` from `runs.js`.
- Produces: `Runs.runTitle(run, titles) -> string` (titles optional). Private helpers used by Tasks 4-5: `_isTitleId(v) -> bool`, `_titlesOr(v) -> object`, `_mappedTitle(titles, id) -> string`, `_amStoryTitle(run, id) -> string`.

- [ ] **Step 1: Update the existing expectations (they must fail first)**

In `tests/core/domain/tst_runs.qml`, replace line 1508:

```qml
    compare(Runs.runTitle(mkRun("run-0000abcd1234", "started", true, { milestone_id: "4bf4fb2f" })), "4bf4fb2f")
```

with

```qml
    compare(Runs.runTitle(mkRun("run-0000abcd1234", "started", true, { milestone_id: "4bf4fb2f" })), "milestone …4bf4fb2f")
```

Replace each of these `checkAlert` lines (the title argument changes only):

```qml
    checkAlert(a[0], id, "m1", "escalated", "escalated at review", "with milestone")
    checkAlert(c[0], id, "m1", "escalated", "3 tests failed", "detail reason")
    checkAlert(a[0], "r1", "m1", "dead", "process died", "live false")
    checkAlert(b[0], "r1", "m1", "dead", "process died", "lease null")
    checkAlert(a[0], "r", "m1", "dead", "process died", "escalated -> dead")
    checkAlert(b[0], "r", "m1", "escalated", "escalated at review", "dead -> escalated")
    checkAlert(fromNormalised[0], "rz", "m9", "escalated", "escalated", "normalised run")
    checkAlert(z[0], "a", "m1", "escalated", "escalated at review", "after mutation")
```

with, respectively:

```qml
    checkAlert(a[0], id, "milestone …m1", "escalated", "escalated at review", "with milestone")
    checkAlert(c[0], id, "milestone …m1", "escalated", "3 tests failed", "detail reason")
    checkAlert(a[0], "r1", "milestone …m1", "dead", "process died", "live false")
    checkAlert(b[0], "r1", "milestone …m1", "dead", "process died", "lease null")
    checkAlert(a[0], "r", "milestone …m1", "dead", "process died", "escalated -> dead")
    checkAlert(b[0], "r", "milestone …m1", "escalated", "escalated at review", "dead -> escalated")
    checkAlert(fromNormalised[0], "rz", "milestone …m9", "escalated", "escalated", "normalised run")
    checkAlert(z[0], "a", "milestone …m1", "escalated", "escalated at review", "after mutation")
```

`test_search_runs` (lines 1727-1742) needs no edit: its titles become `milestone …alpha` … `milestone …epsilon`, and its queries (`GAMMA`, `esc-0`, `implem`, `parked`, `dead`, `zzz`, `beta`) match the same runs as before.

In `tests/core/stores/tst_run_alerts_store.qml`:
- line 149 `compare(a.toasts[0].title, "m-b1")` → `compare(a.toasts[0].title, "milestone …m-b1")`
- line 543 `compare(t.title, "m-b")` → `compare(t.title, "milestone …m-b")`
- line 703 `compare(alerts(store).toasts[0].title, "m-b1")` → `compare(alerts(store).toasts[0].title, "milestone …m-b1")`
- line 148 (`expected[0].title`) is unchanged.

In `tests/ui/screens/tst_runs_screen.qml` line 253:
`compare(H.find(s.screen, "runRowTitle0").text, "alpha")` → `compare(H.find(s.screen, "runRowTitle0").text, "milestone …alpha")`

In `tests/ui/tst_runs_flow.qml` line 408:
`compare(modal.detail, "alpha")` → `compare(modal.detail, "milestone …alpha")`

In `tests/ui/screens/tst_card_detail_screen.qml` line 299:
`compare(H.find(first, "cardRunTitle0").text, "m1")` → `compare(H.find(first, "cardRunTitle0").text, "milestone …m1")`

- [ ] **Step 2: Write the new failing tests**

Append just before the file's final closing `}` of `tests/core/domain/tst_runs.qml`:

```qml

  // A normalised run naming a card, story and/or milestone (mkRun, plus story_id/card_id).
  function idRun(id, milestoneId, storyId, cardId, stories) {
    var r = mkRun(id, "started", true, { milestone_id: milestoneId, tree: { stories: stories || [], subtasks: [] } })
    r.story_id = storyId
    r.card_id = cardId
    return r
  }

  function test_run_title_with_titles() {
    var titles = { "card-0000000c1": "Card title", "story-00000s1": "Story title", "mile-00000m1": "Milestone title" }
    compare(Runs.runTitle(idRun("r1", "mile-00000m1", "story-00000s1", "card-0000000c1"), titles), "Card title", "card run")
    compare(Runs.runTitle(idRun("r1", "mile-00000m1", "story-00000s1", ""), titles), "Story title", "story run")
    compare(Runs.runTitle(idRun("r1", "mile-00000m1", "", ""), titles), "Milestone title", "milestone run")
    compare(Runs.runTitle(idRun("r1", "mile-00000m1", "", ""), { "mile-00000m1": "  Padded  " }), "Padded", "trimmed")
  }

  function test_run_title_without_titles() {
    var card = idRun("r1", "mile-0123456789", "story-0123456789", "card-0123456789")
    var story = idRun("r1", "mile-0123456789", "story-0123456789", "")
    var milestone = idRun("r1", "mile-0123456789", "", "")
    var maps = [undefined, {}, null, [], "x", 5]
    for (var i = 0; i < maps.length; i++) {
      var label = "map " + JSON.stringify(maps[i])
      compare(Runs.runTitle(card, maps[i]), "card …23456789", label + " card")
      compare(Runs.runTitle(story, maps[i]), "story …23456789", label + " story")
      compare(Runs.runTitle(milestone, maps[i]), "milestone …23456789", label + " milestone")
    }
    compare(Runs.runTitle(card), "card …23456789", "titles omitted")
    compare(Runs.runTitle(idRun("r1", "", "", "c1")), "card …c1", "a short id is shown whole")
    compare(Runs.runTitle(idRun("r1", "", "s1", "")), "story …s1", "a short story id")
    compare(Runs.runTitle(idRun("r1", "m1", "", "")), "milestone …m1", "a short milestone id")
    compare(Runs.runTitle(idRun("r1", "12345678", "", "")), "milestone …12345678", "exactly 8 characters")
    // an array map holding the id as an index-like key is still no map
    var arr = []
    arr["m1"] = "From array"
    compare(Runs.runTitle(idRun("r1", "m1", "", ""), arr), "milestone …m1", "an array is no map")
  }

  function test_run_title_unusable_map_values() {
    var values = [5, {}, null, true, [], "", "   "]
    for (var i = 0; i < values.length; i++) {
      var label = "value " + JSON.stringify(values[i])
      compare(Runs.runTitle(idRun("r1", "", "", "c1"), { c1: values[i] }), "card …c1", label + " card")
      compare(Runs.runTitle(idRun("r1", "m1", "", ""), { m1: values[i] }), "milestone …m1", label + " milestone")
      compare(Runs.runTitle(idRun("r1", "", "s1", ""), { s1: values[i] }), "story …s1", label + " story")
    }
  }

  function test_run_title_story_from_am_status() {
    // synthetic: the started capture's am status run edited to name its first story
    var raw = amRun("status-started.json")
    raw.status.run.story_id = "9f0f68fc-f231-4ef2-b646-00a7af925ea2"
    var run = Runs.normalizeRun(raw)
    compare(Runs.runTitle(run), "Dispatch domain", "am status story title, titles omitted")
    compare(Runs.runTitle(run, {}), "Dispatch domain", "am status story title, empty map")
    compare(Runs.runTitle(run, { "9f0f68fc-f231-4ef2-b646-00a7af925ea2": "From brd" }), "From brd", "the map wins")
    compare(Runs.runTitle(run, { "9f0f68fc-f231-4ef2-b646-00a7af925ea2": "   " }), "Dispatch domain",
            "an unusable map title falls through to am's")
    compare(Runs.runTitle(Runs.normalizeRun(amRun("status-started.json"))), "milestone …ab5f860b",
            "the unedited capture is a milestone run")

    // synthetic: am story titles that are unusable, and stories that are not objects
    var bad = [undefined, null, 5, "", "   ", {}]
    for (var i = 0; i < bad.length; i++) {
      var r = idRun("r1", "m1", "story-0123456789", "", [null, "x", { card_id: "story-0123456789", title: bad[i] }])
      compare(Runs.runTitle(r), "story …23456789", "am title " + JSON.stringify(bad[i]))
    }
    var first = idRun("r1", "", "s1", "", [{ card_id: "s1", title: " First " }, { card_id: "s1", title: "Second" }])
    compare(Runs.runTitle(first), "First", "the first matching story, trimmed")
    var noTree = idRun("r1", "", "s1", "")
    noTree.tree = "x"
    compare(Runs.runTitle(noTree), "story …s1", "a garbage tree has no story titles")
  }

  function test_run_title_precedence() {
    var all = idRun("r1", "m1", "s1", "c1", [{ card_id: "s1", title: "Am story" }])
    var titles = { s1: "Story", m1: "Milestone" }
    compare(Runs.runTitle(all, titles), "card …c1", "a card run never falls back to its story or milestone")
    compare(Runs.runTitle(idRun("r1", "m1", "s1", "", []), { m1: "Milestone" }), "story …s1",
            "a story run never falls back to its milestone")
    compare(Runs.runTitle(idRun("run-0000abcd1234", "", "", ""), titles), "…abcd1234", "naming nothing gives the short id")
    compare(Runs.runTitle({ id: "r1", milestone_id: 5, story_id: 6, card_id: [] }, titles), "…r1", "non-string ids are no ids")
    var bad = [undefined, null, "x", 5, [], {}, { id: 7 }]
    for (var i = 0; i < bad.length; i++) compare(Runs.runTitle(bad[i], titles), "…", "garbage " + i)
  }

  function test_run_title_prototype_ids() {
    var names = ["constructor", "__proto__", "toString", "hasOwnProperty"]
    for (var i = 0; i < names.length; i++) {
      var n = names[i]
      var expected8 = n.slice(-8)
      compare(Runs.runTitle(idRun("r1", "", "", n), {}), "card …" + expected8, n + " card, empty map")
      compare(Runs.runTitle(idRun("r1", "", n, ""), {}), "story …" + expected8, n + " story, empty map")
      compare(Runs.runTitle(idRun("r1", n, "", ""), {}), "milestone …" + expected8, n + " milestone, empty map")
      compare(Runs.runTitle(idRun("r1", n, "", "")), "milestone …" + expected8, n + " milestone, no map")
      var own = JSON.parse('{"' + n + '": "Own ' + n + '"}')
      compare(Runs.runTitle(idRun("r1", "", "", n), own), "Own " + n, n + " card, own key")
      compare(Runs.runTitle(idRun("r1", "", n, ""), own), "Own " + n, n + " story, own key")
      compare(Runs.runTitle(idRun("r1", n, "", ""), own), "Own " + n, n + " milestone, own key")
    }
  }

  function test_run_title_prototype_less() {
    var titles = Object.create(null)
    titles.c1 = "Bare title"
    compare(Runs.runTitle(idRun("r1", "", "", "c1"), titles), "Bare title", "a prototype-less map")
    compare(Runs.runTitle(idRun("r1", "", "", "c2"), titles), "card …c2", "a prototype-less map without the id")
    var run = Object.create(null)
    run.id = "run-bare-0001"
    run.milestone_id = "m1"
    compare(Runs.runTitle(run, { m1: "Bare run" }), "Bare run", "a prototype-less run")
    compare(Runs.runTitle(run), "milestone …m1", "a prototype-less run, no map")
  }

  function test_run_title_pure() {
    var run = idRun("r1", "m1", "s1", "", [{ card_id: "s1", title: "Am" }])
    var titles = { s1: "Story" }
    var runJson = JSON.stringify(run), titlesJson = JSON.stringify(titles)
    Runs.runTitle(run, titles)
    Runs.runTitle(run)
    compare(JSON.stringify(run), runJson, "run unchanged")
    compare(JSON.stringify(titles), titlesJson, "titles unchanged")
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `timeout 900 bash tests/run.sh tst_run` (the filter `tst_run` selects `tst_runs.qml`, `tst_run_alerts_store.qml`, `tst_runs_screen.qml`, `tst_runs_flow.qml`) and then `timeout 600 bash tests/run.sh tst_card_detail_screen`.
Expected: FAIL in `test_run_title` (`'4bf4fb2f'` vs `'milestone …4bf4fb2f'`), the `newAlerts` tests (`'m1'` vs `'milestone …m1'`), every new `test_run_title_*` test, the three store assertions, the two runs UI assertions and the card-detail assertion.

- [ ] **Step 4: Implement**

In `core/domain/runs.js`, replace

```js
// The run's milestone, else its short id.
function runTitle(run) {
  var milestone = _isObject(run) ? _stringOr(run.milestone_id) : ""
  return milestone !== "" ? milestone : shortId(run)
}
```

with

```js
// A milestone, story or card id: a non-empty string.
function _isTitleId(v) { return typeof v === "string" && v !== "" }

// v when it is a plain object (a titles map), else {}.
function _titlesOr(v) { return _isObject(v) ? v : {} }

// The usable title titles holds for id as an own key, else "".
function _mappedTitle(titles, id) {
  var map = _titlesOr(titles)
  return hasKey(map, id) ? _usableTitle(map[id]) : ""
}

// The usable title of the first object in run.tree.stories whose card_id is id, else "".
function _amStoryTitle(run, id) {
  var story = _findByCardId(_treeOf(run).stories, id)
  return story === null ? "" : _usableTitle(story.title)
}

// "<kind> …" and the last 8 characters of id (all of a shorter one).
function _fallbackTitle(kind, id) { return kind + " …" + id.slice(-8) }

// The run's title from titles, its {id: title} map (any non-plain-object is {}):
// a card run (card_id an id) is the card's title, else "card …<8>"; else a
// story run is the story's title, else am's own story title, else "story …<8>";
// else a milestone run is the milestone's title, else "milestone …<8>"; else
// shortId(run). No kind falls back to another kind's title.
function runTitle(run, titles) {
  var r = _isObject(run) ? run : {}
  var title
  if (_isTitleId(r.card_id)) {
    title = _mappedTitle(titles, r.card_id)
    return title !== "" ? title : _fallbackTitle("card", r.card_id)
  }
  if (_isTitleId(r.story_id)) {
    title = _mappedTitle(titles, r.story_id)
    if (title === "") title = _amStoryTitle(run, r.story_id)
    return title !== "" ? title : _fallbackTitle("story", r.story_id)
  }
  if (_isTitleId(r.milestone_id)) {
    title = _mappedTitle(titles, r.milestone_id)
    return title !== "" ? title : _fallbackTitle("milestone", r.milestone_id)
  }
  return shortId(run)
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 900 bash tests/run.sh`
Expected: exit 0, every `Totals:` line with `0 failed`, no `FAIL` lines. If any other assertion fails because it expects a run's raw milestone id as a title (spec: "Any other failing assertion whose expected value is a run's raw milestone id shown as a title is updated the same way"), change that expected value to `"milestone …<last 8 of that id>"` and re-run; change nothing else.

- [ ] **Step 6: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml tests/core/stores/tst_run_alerts_store.qml tests/ui/screens/tst_runs_screen.qml tests/ui/tst_runs_flow.qml tests/ui/screens/tst_card_detail_screen.qml
git commit -m "feat(runs): runTitle reads a titles map and falls back to milestone/story/card …<8>"
```

---

### Task 4: `runSubtitle(run)` and `cardTitle(id, run, titles)`

**Files:**
- Modify: `core/domain/runs.js` — insert directly after `runTitle` (Task 3)
- Test: `tests/core/domain/tst_runs.qml` — new tests appended at the end

**Interfaces:**
- Consumes: `shortId`, `_isTitleId`, `_mappedTitle`, `_amStoryTitle` (Task 3); `idRun` test helper (Task 3).
- Produces: `Runs.runSubtitle(run) -> string` (== `shortId(run)`), `Runs.cardTitle(id, run, titles) -> string` (`""` when unknown).

- [ ] **Step 1: Write the failing tests**

Append just before the file's final closing `}` of `tests/core/domain/tst_runs.qml`:

```qml

  function test_run_subtitle() {
    var runs = [{ id: "run-20261003-abcdef12" }, { id: "abc" }, { id: "" }, idRun("r1", "m1", "s1", "c1"),
                undefined, null, "x", 5, [], {}, { id: 7 }, { id: null }]
    for (var i = 0; i < runs.length; i++)
      compare(Runs.runSubtitle(runs[i]), Runs.shortId(runs[i]), "input " + i)
    compare(Runs.runSubtitle({ id: "run-20261003-abcdef12" }), "…abcdef12")
  }

  function test_card_title() {
    var run = idRun("r1", "m1", "", "", [{ card_id: "s1", title: " Am story " }, { card_id: "s2", title: "Am two" }])
    compare(Runs.cardTitle("t1", run, { t1: "Subtask" }), "Subtask", "from the map")
    compare(Runs.cardTitle("s1", run, {}), "Am story", "from the run's story title, trimmed")
    compare(Runs.cardTitle("s1", run), "Am story", "titles omitted")
    compare(Runs.cardTitle("s2", run, { s2: "Brd two" }), "Brd two", "the map wins over am")
    compare(Runs.cardTitle("s2", run, { s2: "  " }), "Am two", "an unusable map title falls through to am's")
    compare(Runs.cardTitle("t9", run, { t1: "Subtask" }), "", "an unknown id")
    compare(Runs.cardTitle("t1", run, { t1: 5 }), "", "a non-string map title")
    compare(Runs.cardTitle("t1", run, { t1: {} }), "", "an object map title")

    var ids = [undefined, null, 5, "", [], {}]
    for (var i = 0; i < ids.length; i++)
      compare(Runs.cardTitle(ids[i], run, { "": "Empty", "5": "Five" }), "", "id " + JSON.stringify(ids[i]))

    var runs = [undefined, null, "x", 5, [], {}, { tree: "x" }, { tree: { stories: "x" } }]
    for (var j = 0; j < runs.length; j++) {
      compare(Runs.cardTitle("s1", runs[j], {}), "", "garbage run " + j)
      compare(Runs.cardTitle("t1", runs[j], { t1: "Subtask" }), "Subtask", "garbage run " + j + " with a map title")
    }

    var maps = [undefined, null, "x", 5, [], true]
    for (var k = 0; k < maps.length; k++) {
      compare(Runs.cardTitle("t1", run, maps[k]), "", "garbage titles " + k)
      compare(Runs.cardTitle("s1", run, maps[k]), "Am story", "garbage titles " + k + " keep am's")
    }
  }

  function test_card_title_prototype_ids() {
    var names = ["constructor", "__proto__", "toString", "hasOwnProperty"]
    var run = idRun("r1", "m1", "", "", [])
    for (var i = 0; i < names.length; i++) {
      var n = names[i]
      compare(Runs.cardTitle(n, run, {}), "", n + " with an empty map")
      compare(Runs.cardTitle(n, run), "", n + " with no map")
      compare(Runs.cardTitle(n, run, JSON.parse('{"' + n + '": "Own"}')), "Own", n + " as an own key")
      compare(Runs.cardTitle(n, idRun("r1", "", "", "", [{ card_id: n, title: "Am " + n }]), {}), "Am " + n,
              n + " as an am story id")
    }
  }

  function test_card_title_pure() {
    var run = idRun("r1", "m1", "", "", [{ card_id: "s1", title: "Am" }])
    var titles = { t1: "T" }
    var runJson = JSON.stringify(run), titlesJson = JSON.stringify(titles)
    Runs.cardTitle("s1", run, titles)
    Runs.cardTitle("t1", run, titles)
    compare(JSON.stringify(run), runJson, "run unchanged")
    compare(JSON.stringify(titles), titlesJson, "titles unchanged")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_runs.qml`
Expected: FAIL / `TypeError: Property 'runSubtitle' of object [object Object] is not a function` (and the same for `cardTitle`).

- [ ] **Step 3: Implement**

In `core/domain/runs.js`, directly after the closing `}` of `runTitle`, insert:

```js

// The run's secondary text: exactly shortId(run).
function runSubtitle(run) { return shortId(run) }

// The title of card id within run: titles' own usable title for id, else the
// usable title of the first object in run.tree.stories whose card_id is id,
// else "". "" when id is not a non-empty string. am has no subtask titles, so
// a subtask's title comes only from titles.
function cardTitle(id, run, titles) {
  if (!_isTitleId(id)) return ""
  var title = _mappedTitle(titles, id)
  return title !== "" ? title : _amStoryTitle(run, id)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_runs.qml`
Expected: `Totals: … 0 failed`, no `FAIL` lines.

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): runSubtitle and cardTitle"
```

---

### Task 5: `searchRuns` and `newAlerts` take `titlesByRoot`; architecture doc

**Files:**
- Modify: `core/domain/runs.js` — `searchRuns` (lines ~616-630, now shifted by Tasks 2-4), `newAlerts` (the "Run alerts" section)
- Modify: `docs/architecture.md:181`
- Test: `tests/core/domain/tst_runs.qml` — new tests appended at the end

**Interfaces:**
- Consumes: `runTitle(run, titles)` (Task 3), `_titlesOr` (Task 3), `runRoot`, `hasKey`, `_isObject` from `runs.js`; `Runs.withProject(run, root, name)` and test helpers `mkRun`, `alRunning`, `alEscalated`, `alDead`, `checkAlert`, `ids`, `alIds`, `idRun`.
- Produces: `Runs.searchRuns(runs, q, titlesByRoot) -> array`, `Runs.newAlerts(prevRuns, nextRuns, titlesByRoot) -> array` (third argument optional), private `_titlesFor(run, titlesByRoot) -> object`.

- [ ] **Step 1: Write the failing tests**

Append just before the file's final closing `}` of `tests/core/domain/tst_runs.qml`:

```qml

  // Runs of four projects: two share a milestone id under different roots; one
  // root is named after an Object.prototype member, one is __proto__.
  function titledRuns() {
    return [
      Runs.withProject(mkRun("run-a-000001", "started", true, { milestone_id: "ms-alpha-1" }), "/p/a", "A"),
      Runs.withProject(mkRun("run-b-000002", "escalated", null, { milestone_id: "ms-alpha-1" }), "/p/b", "B"),
      Runs.withProject(mkRun("run-c-000003", "stopped", null, { milestone_id: "ms-gamma" }), "/p/c", "C"),
      Runs.withProject(mkRun("run-d-000004", "stopped", null, { milestone_id: "ms-delta" }), "constructor", "D"),
      Runs.withProject(mkRun("run-e-000005", "stopped", null, { milestone_id: "ms-eps" }), "__proto__", "E"),
      mkRun("run-f-000006", "stopped", null, { milestone_id: "ms-zeta" })
    ]
  }

  function test_search_runs_by_title() {
    var list = titledRuns()
    var byRoot = { "/p/a": { "ms-alpha-1": "Release Train" }, "/p/b": { "ms-alpha-1": "Other Title" }, "/p/c": null }
    compare(ids(Runs.searchRuns(list, "release TRAIN", byRoot)), "run-a-000001", "a title substring, any case")
    compare(ids(Runs.searchRuns(list, "other title", byRoot)), "run-b-000002", "another root uses its own map")
    compare(ids(Runs.searchRuns(list, "milestone …ms-gamma", byRoot)), "run-c-000003", "a null root map gives fallbacks")
    compare(ids(Runs.searchRuns(list, "ms-delta", byRoot)), "run-d-000004", "a root absent from titlesByRoot gives fallbacks")
    compare(ids(Runs.searchRuns(list, "ms-zeta", byRoot)), "run-f-000006", "a run without a root gives fallbacks")
    compare(ids(Runs.searchRuns(list, "run-b", byRoot)), "run-b-000002", "the id still matches")
    compare(ids(Runs.searchRuns(list, "escalated", byRoot)), "run-b-000002", "the state still matches")
    compare(Runs.searchRuns(list, "", byRoot) === list, true, "an empty query returns the input itself")

    var protoRoots = JSON.parse('{"constructor": {"ms-delta": "Ctor Title"}, "__proto__": {"ms-eps": "Proto Title"}}')
    compare(ids(Runs.searchRuns(list, "ctor title", protoRoots)), "run-d-000004", "a root named constructor")
    compare(ids(Runs.searchRuns(list, "proto title", protoRoots)), "run-e-000005", "a root named __proto__")
    compare(ids(Runs.searchRuns(list, "ms-eps", {})), "run-e-000005", "an inherited __proto__ root is no map")

    compare(ids(Runs.searchRuns(list, "milestone")),
            "run-a-000001,run-b-000002,run-c-000003,run-d-000004,run-e-000005,run-f-000006",
            "titlesByRoot omitted: every untitled milestone run matches milestone")
  }

  function test_search_runs_titles_by_root_garbage() {
    var list = titledRuns()
    var outer = [undefined, null, "x", 5, [], true]
    for (var i = 0; i < outer.length; i++)
      compare(ids(Runs.searchRuns(list, "milestone …-alpha-1", outer[i])), "run-a-000001,run-b-000002", "titlesByRoot " + i)

    var inner = [[], "Release", 5, true]
    for (var j = 0; j < inner.length; j++)
      compare(ids(Runs.searchRuns(list, "milestone …-alpha-1", { "/p/a": inner[j] })), "run-a-000001,run-b-000002",
              "root map " + JSON.stringify(inner[j]) + " acts as {}")

    var bareRoots = Object.create(null)
    var bareMap = Object.create(null)
    bareMap["ms-alpha-1"] = "Bare Title"
    bareRoots["/p/a"] = bareMap
    compare(ids(Runs.searchRuns(list, "bare title", bareRoots)), "run-a-000001", "prototype-less maps")

    var emptyRoot = mkRun("run-g-000007", "stopped", null, { milestone_id: "ms-eta" })
    emptyRoot.project = { root: "", name: "" }
    compare(ids(Runs.searchRuns([emptyRoot], "milestone …ms-eta", { "": { "ms-eta": "Never" } })), "run-g-000007",
            "an empty root always uses {}")

    var byRoot = { "/p/a": { "ms-alpha-1": "Release Train" } }
    var listJson = JSON.stringify(list), rootsJson = JSON.stringify(byRoot)
    Runs.searchRuns(list, "release", byRoot)
    compare(JSON.stringify(list), listJson, "runs unchanged")
    compare(JSON.stringify(byRoot), rootsJson, "titlesByRoot unchanged")
  }

  function test_new_alerts_titles_by_root() {
    var noIds = mkRun("r3", "started", false, { milestone_id: "" })
    var prev = [Runs.withProject(alRunning("r1"), "/p/a", "A"), Runs.withProject(alRunning("r2"), "/p/b", "B"), alRunning("r3")]
    var next = [Runs.withProject(alEscalated("r1"), "/p/a", "A"), Runs.withProject(alDead("r2"), "/p/b", "B"), noIds]
    var byRoot = { "/p/a": { m1: "Alpha milestone" }, "/p/b": { other: "Unused" } }

    var a = Runs.newAlerts(prev, next, byRoot)
    compare(alIds(a), "r1,r2,r3")
    checkAlert(a[0], "r1", "Alpha milestone", "escalated", "escalated at review", "mapped title")
    checkAlert(a[1], "r2", "milestone …m1", "dead", "process died", "its root's map lacks the id")
    checkAlert(a[2], "r3", "…r3", "dead", "process died", "no ids keep the short-id title")

    var b = Runs.newAlerts(prev, next)
    checkAlert(b[0], "r1", "milestone …m1", "escalated", "escalated at review", "titlesByRoot omitted")
    checkAlert(b[2], "r3", "…r3", "dead", "process died", "titlesByRoot omitted, no ids")

    var garbage = [null, "x", 5, [], { "/p/a": [] }, { "/p/a": "Alpha" }, { "/p/a": null }]
    for (var i = 0; i < garbage.length; i++)
      compare(Runs.newAlerts(prev, next, garbage[i])[0].title, "milestone …m1", "garbage titlesByRoot " + i)

    var protoRoot = Runs.withProject(alEscalated("r4"), "constructor", "C")
    compare(Runs.newAlerts([], [protoRoot], {})[0].title, "milestone …m1", "a root named constructor, empty map")
    compare(Runs.newAlerts([], [protoRoot], JSON.parse('{"constructor": {"m1": "Ctor"}}'))[0].title, "Ctor",
            "a root named constructor, own key")

    var prevJson = JSON.stringify(prev), nextJson = JSON.stringify(next), rootsJson = JSON.stringify(byRoot)
    Runs.newAlerts(prev, next, byRoot)
    compare(JSON.stringify(prev), prevJson, "prevRuns unchanged")
    compare(JSON.stringify(next), nextJson, "nextRuns unchanged")
    compare(JSON.stringify(byRoot), rootsJson, "titlesByRoot unchanged")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_runs.qml`
Expected: FAIL in `test_search_runs_by_title` (`"release TRAIN"` finds nothing: the title is still the fallback), `test_search_runs_titles_by_root_garbage` (`"bare title"`), and `test_new_alerts_titles_by_root` (`'milestone …m1'` vs `'Alpha milestone'`).

- [ ] **Step 3: Implement `searchRuns`**

In `core/domain/runs.js`, replace

```js
// Case-insensitive substring match on the id, title, current phase and state
// name. An empty (or all-space) query returns the input itself.
function searchRuns(runs, q) {
```

with

```js
// The titles map of run's project: titlesByRoot's own entry for runRoot(run)
// when titlesByRoot is a plain object and that entry a plain object; {} for
// anything else, and always for a run whose root is "".
function _titlesFor(run, titlesByRoot) {
  var root = runRoot(run)
  if (root === "" || !_isObject(titlesByRoot) || !hasKey(titlesByRoot, root)) return {}
  return _titlesOr(titlesByRoot[root])
}

// Case-insensitive substring match on the id, title (runTitle with the run's
// map in titlesByRoot, see _titlesFor), current phase and state name. An empty
// (or all-space) query returns the input itself.
function searchRuns(runs, q, titlesByRoot) {
```

and inside `searchRuns` replace

```js
    var hay = [_stringOr(run.id), runTitle(run), currentPhase(run), runState(run)].join("\n").toLowerCase()
```

with

```js
    var hay = [_stringOr(run.id), runTitle(run, _titlesFor(run, titlesByRoot)), currentPhase(run), runState(run)].join("\n").toLowerCase()
```

- [ ] **Step 4: Implement `newAlerts`**

In `core/domain/runs.js`, replace

```js
// id; the first prevRuns occurrence of an id is its previous state. A dead
// run's reason is always "process died".
function newAlerts(prevRuns, nextRuns) {
```

with

```js
// id; the first prevRuns occurrence of an id is its previous state. A dead
// run's reason is always "process died". title is runTitle with the run's map
// in titlesByRoot (see _titlesFor); without one it is the fallback title.
function newAlerts(prevRuns, nextRuns, titlesByRoot) {
```

and inside `newAlerts` replace

```js
      title: runTitle(run),
```

with

```js
      title: runTitle(run, _titlesFor(run, titlesByRoot)),
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_runs.qml`
Expected: `Totals: … 0 failed`, no `FAIL` lines.

- [ ] **Step 6: Update `docs/architecture.md:181`**

In the `runs.js` paragraph, make these three exact substring replacements:

1. `` `status` and `milestone_id` the `am status` run; `` →
   `` `status` and `milestone_id` the `am status` run, `story_id` and `card_id` the `am status` run's non-empty string, else the row's, else `""`; ``
2. `` Filter and search: `runFilterCounts`, `filterRuns`, `searchRuns`. `` →
   `` Filter and search: `runFilterCounts`, `filterRuns`, `searchRuns(runs, q, titlesByRoot)` (also matches the run's title from `titlesByRoot[run.project.root]`). ``
3. `` Display text: `shortId`, `runTitle`, `` →
   `` Display text: `shortId`, `runTitle(run, titles)` (`titles` is one project's `{id: title}` map from `titlesFromCards(cardMap)`, the one brd input here: a card run is its card's title, else `card …<8>`; a story run its story's title, else am's story title, else `story …<8>`; a milestone run its milestone's title, else `milestone …<8>`; else the short id), `runSubtitle` (the short id), `cardTitle(id, run, titles)` (the map's title, else am's story title, else `""`), ``

Also in the `newAlerts` mention of `docs/architecture.md:92`, leave it as is (the store still calls `Runs.newAlerts(previousRuns, runs)`; wiring a map is a sibling card).

- [ ] **Step 7: Run the full suite**

Run: `timeout 900 bash tests/run.sh`
Expected: exit 0; pytest passes (including `tests/architecture`), every `Totals:` line has `0 failed`, no `FAIL`, `TypeError` or `ReferenceError` lines.

- [ ] **Step 8: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml docs/architecture.md
git commit -m "feat(runs): searchRuns and newAlerts read run titles from titlesByRoot"
```

---

## Self-Review

- **Spec coverage:** normalizeRun ids → Task 1; shared rules (usable title, plain-object map, own-key lookup, id, `<last 8>`) → `_usableTitle`/`_titlesOr`/`_mappedTitle`/`_isTitleId`/`_fallbackTitle` (Tasks 2-3); `titlesFromCards` → Task 2; `runTitle` kinds/order/no cross-kind fallback/visible change → Task 3; `runSubtitle`, `cardTitle` → Task 4; `searchRuns`, `newAlerts` map rule → Task 5; never-throws/no-mutation → garbage and `_pure` tests in Tasks 2-5; spec tests 1-11 → Tasks 1 (1), 2 (2), 3 (3-7), 4 (8-9), 5 (10-11); changed expectations in every tier → Task 3 Step 1; verification → Task 3 Step 5 and Task 5 Step 7.
- **Placeholders:** none; every code step has the code.
- **Type consistency:** `_isTitleId`, `_titlesOr`, `_mappedTitle`, `_amStoryTitle`, `_fallbackTitle` defined in Task 3, used in Tasks 4-5; `_usableTitle` defined in Task 2, used in Task 3; `_titlesFor` defined and used in Task 5; test helpers `idRun` (Task 3) and `titledRuns` (Task 5) used only after definition.
- **Review Focus:** each line has a named test in its owning task.
<!-- task-pipeline: validated -->
