# 2.2 runs.js: the finished-run filters — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `core/domain/runs.js` the History filters: a `finished` chip in `filterRuns`/`runFilterCounts`, plus the pure functions `withinAge`, `filterFinished`, `historyStatuses` and `historyCursor(runs, root)`.

**Architecture:** Everything is pure ES5 in the existing `.pragma library` file `core/domain/runs.js`, placed right after `filterRuns`. No caller, store, UI or backend file changes. "Finished" reuses the existing `runState`; the cursor reuses the existing `runRoot`. Tests are QML `TestCase` functions in `tests/core/domain/tst_runs.qml`, built on the existing `mkRun`, `screenRuns`, `ids` and `cancelledRun` helpers.

**Tech Stack:** QML/JS (Qt 6 V4 engine, ES5 subset in `.pragma library`), QtTest via `qmltestrunner`, `bash tests/run.sh` (pytest + every `tst_*.qml`).

**Spec:** `docs/superpowers/specs/2-2-runs-js-the-227b4c50.md` (prepended below). Parent design: `docs/superpowers/specs/2026-10-05-run-history-titles-design.md`.

## Global Constraints

- `runs.js` stays an ES5 `.pragma library` whose functions never throw: garbage in, default out. Docstrings and comments state the contract only, with no narrative.
- Private helpers take the `_` prefix and sit above their first user.
- Layering follows `docs/architecture.md`, and `tests/architecture` must pass.
- Tests go in `tests/core/domain/tst_runs.qml`.
- Chips are Needs attention / Live / Parked / **Finished** / All. `filterRuns(runs, "finished")` keeps `done`, `escalated`, `cancelled` and `canceled`.
- A **finished** run is one whose `runState` is `done`, `escalated` or `cancelled`. A **terminal** run (history cursor only) is a finished or `parked` run.
- The **start instant** is `Date.parse(run.started_at)`, only for an object run with a non-empty string `started_at` that parses to a finite number. Instants are compared as numbers, never as strings.
- `utcOffsetMinutes` is minutes **east of UTC** (`-180` for UTC−3); a non-finite value is taken as `0`.
- Today means since local midnight, `floor((nowMs + off·60000) / 86400000) · 86400000 − off·60000`, inclusive. 7 days means `start ≥ nowMs − 7·86400000`, inclusive. No upper bound.
- The age and finished-state filters never hide a run that is not finished.
- The five history statuses are `done, escalated, stopped, cancelled, canceled`.
- `historyCursor(runs, root)` returns the oldest terminal run's `started_at` string verbatim for that root (card overrides parent's run-id cursor).
- Out of scope: every caller and UI (RunsScreen chips, RunStore properties), `RunHistoryStore.qml`, `runs-history.py`, `am_runs.py`, titles work, any `am`/`brd` change.
- Verification: `bash tests/run.sh` is green (pytest, including `tests/architecture`, then every `tst_*.qml`).

## Review Focus

1. **am's space-and-offset timestamps (`"2026-10-03 10:00:00+00:00"`) mixed with `T`/`Z` and `+05:00` forms**: a reasonable person expects the cursor to pick the truly oldest run, not the smallest string. Pinned in Task 5 (`test_history_cursor_per_root`) and Task 2 (`test_within_age_today_at_fixed_offsets`, am format case).
2. **Time zones more than 12 h east (UTC+13) or west of UTC**: "Today" must start at the local midnight, which may be on the next or previous UTC day. Pinned in Task 2 (`+600`, `+780`, `-180` cases) and Task 3 (`test_filter_finished_state_and_age`, `+780`).
3. **No clock or no offset available (`NaN`, `undefined`)**: nothing is hidden for lack of a clock, and a missing offset acts as UTC. Pinned in Task 2 (`test_within_age_week_and_defaults`, offset loop) and Task 3 (`test_filter_finished_garbage`, `test_filter_finished_never_hides_unfinished` clocks).
4. **A run list holding junk entries (`null`, `5`, `[]`) beside real runs**: junk is "not finished", so `filterFinished` keeps it rather than throwing, and the cursor skips it. Pinned in Task 3 (`test_filter_finished_garbage`) and Task 5 (`test_history_cursor_garbage`).
5. **Prototype-named ids (`"constructor"`, `"__proto__"`) as filter, state, age or root**: treated like any unknown string, never as a hit on an object property. Pinned in Task 2, Task 3, Task 4 (`test_history_statuses`) and Task 5 (`test_history_cursor_garbage`).

## Spec (prepended; headings demoted one level)

## 2.2 runs.js: the finished-run filters — design

Card `227b4c50-7e62-42cf-adb8-7757ac65fe17`, a subtask of story `091a4b97`. It is blocked by
2.1 (`41e2402b`, run titles), which has already landed on this branch.
Parent design: `docs/superpowers/specs/2026-10-05-run-history-titles-design.md` (called
"parent" below). This card puts the parent's **History › Filters** section (parent :137-151)
into `core/domain/runs.js`. It adds pure functions and one chip, and it wires no caller.

### Inherited constraints

- Chips are Needs attention / Live / Parked / **Finished** / All.
  `filterRuns(runs, "finished")` keeps `done`, `escalated`, `cancelled` and `canceled`
  (parent :139-140).
- The finished-state row is **All finished / Done / Escalated / Cancelled**
  (`finishedState`) (parent :141-142).
- The age row is **Today / 7 days / All time** (`finishedAge`, default All time). Age is
  measured from `started_at`. Today means since local midnight. 7 days means the last
  7×24 h (parent :143-145).
- `withinAge(run, age, nowMs, utcOffsetMinutes)` is pure, and its tests pass fixed offsets
  (parent :146).
- The age and finished-state filters never hide a run that is not finished (live, parked
  or dead) (parent :147).
- `historyStatuses(filter, finishedState)` gives the `--status` list for one page. All gives
  all five statuses, Parked gives `stopped`, Needs attention gives `escalated` and
  Finished gives the chip's states (parent :148-150). The five terminal-for-the-cap
  statuses are `done, escalated, stopped, cancelled, canceled` (parent :124-125;
  `core/backend/common/am_runs.py:19` `TERMINAL`).
- **The card overrides the parent here.** The parent's `historyCursor(runs)` returns a run
  id (parent :150-151). The card asks for `historyCursor(runs, root)`, which returns the
  **oldest `started_at`** of the listed terminal runs of that root. The card wins because
  the helper this branch actually ships takes `runs-history.py ROOT --before ISO`, a time
  per project (`core/backend/runs/runs-history.py:4`, `:9-10`, `:16-20`). The helper keeps
  rows started *strictly* before `--before`, so passing the oldest listed run's own
  `started_at` never lists that run again.
- Tests go in `tests/core/domain/tst_runs.qml` (parent :215-218, "`filterRuns` finished,
  `withinAge` at fixed offsets around midnight, `historyStatuses`, `historyCursor`,
  non-finished runs never hidden").
- Layering follows `docs/architecture.md`, and `tests/architecture` must pass. `runs.js`
  stays an ES5 `.pragma library` whose functions never throw: garbage in, default out.
  Docstrings and comments state the contract only, with no narrative (card).

### Shared definitions

- **State** is `runState(run)` (`runs.js:156`). It already maps both `cancelled` and
  `canceled` to `cancelled`, `stopped` to `parked`, and `started` to `running` or `dead`
  depending on the lease.
- A **finished** run is one whose state is `done`, `escalated` or `cancelled`. Every other
  run is **not finished**: `running`, `dead`, `parked`, and `unknown` (including runs that
  are not objects).
- A **terminal** run (for the history cursor only) is a finished run or a `parked` run.
  These are the statuses in the helper's default `TERMINAL` set.
- The **start instant** of a run is `Date.parse(run.started_at)`. It exists only when the
  run is an object, `started_at` is a non-empty string, and the parse gives a finite number.
  The V4 engine parses am's format. `"2026-10-08 14:38:23.739155+00:00"` (with a space,
  microseconds and an offset) parses to the same instant as its `T` form; this was checked
  with Qt 6.11's `qmltestrunner`. Instants are compared as numbers, never as strings.
- `utcOffsetMinutes` is the local offset **east of UTC** in minutes: `-180` for UTC−3 and
  `+60` for UTC+1. Callers pass `-new Date().getTimezoneOffset()`. If it is not a finite
  number, it is taken as `0`.

### Behaviour

#### `filterRuns(runs, "finished")` and `runFilterCounts`

- `filterRuns(runs, "finished")` returns the finished runs as the same objects, in input
  order. All other chip ids behave as they do today (`runs.js:686-692`). An unknown id
  still means every run.
- `runFilterCounts(runs)` gains a `finished` key, which is the length of that list. Its key
  set becomes `all, attention, finished, live, parked`. Garbage input gives `0` for every
  key. Callers that read only named keys (`RunStore.qml:79`, `RunsScreen.qml:45`,
  `Panel.qml:258`, `tst_panel_toolbar.qml:401`) are unaffected.

#### `withinAge(run, age, nowMs, utcOffsetMinutes)` → boolean

- If `age` is anything other than `"today"` or `"week"` (`"all"`, `""`, `undefined`,
  `"constructor"`, a number…), the result is `true`.
- If `nowMs` is not a finite number, the result is `true`. Without a clock there is no
  window to apply, so nothing is hidden for lack of one.
- If the run has no start instant (garbage run, missing, empty or unparsable `started_at`),
  the result is `false` for `"today"` and `"week"`.
- `"today"`: local midnight is computed as
  `floor((nowMs + off·60000) / 86400000) · 86400000 − off·60000`. The result is `true`
  when start ≥ local midnight. The boundary is inclusive.
- `"week"`: `true` when start ≥ `nowMs − 7·86400000`. The boundary is inclusive.
- There is no upper bound. A start later than `nowMs` (clock skew) counts as within.
- The function does not look at the run's state.

#### `filterFinished(runs, finishedState, finishedAge, nowMs, utcOffsetMinutes)` → array

- It returns the same objects in input order. If `runs` is not an array, the result is `[]`.
- Every run that is not finished is **always kept**, whatever the state, age, clock or
  offset.
- A finished run is kept when both of these hold:
  - **State match.** `finishedState` is `"done"`, `"escalated"` or `"cancelled"` and
    equals the run's state, so `"cancelled"` covers both spellings. Any other value
    (`"all"`, `""`, unknown, or a non-string) matches every finished run.
  - **Age match.** `withinAge(run, finishedAge, nowMs, utcOffsetMinutes)` is true.
- The function does not mutate its inputs and never throws.

#### `historyStatuses(filter, finishedState)` → array of strings

Each call returns a new array:

| filter | finishedState | result |
|---|---|---|
| `"all"`, or any unknown or non-string id | — | `["done","escalated","stopped","cancelled","canceled"]` |
| `"parked"` | — | `["stopped"]` |
| `"attention"` | — | `["escalated"]` |
| `"live"` | — | `[]` (a live run is never terminal, so there is no history to page) |
| `"finished"` | `"done"` | `["done"]` |
| `"finished"` | `"escalated"` | `["escalated"]` |
| `"finished"` | `"cancelled"` | `["cancelled","canceled"]` |
| `"finished"` | `"all"`, unknown, or non-string | `["done","escalated","cancelled","canceled"]` |

An unknown filter maps to the All list, which matches `filterRuns`' rule that an unknown id
is All. The `"live"` → `[]` row is a decision this spec makes because the parent does not
cover it. A caller seeing `[]` should not offer Show older.

#### `historyCursor(runs, root)` → string

- If `root` is not a non-empty string, or `runs` is not an array, the result is `""`.
- The candidates are the runs whose `runRoot(run) === root` (`runs.js:1440`), that are
  terminal, and that have a start instant.
- The result is the `started_at` string, returned exactly as given, of the candidate with
  the smallest start instant. When several candidates tie, the first in input order wins.
  With no candidate, the result is `""`.
- Running, dead and unknown runs, runs of other roots, and runs with an unparsable
  `started_at` are ignored.
- The function never throws.

#### Never throws

None of the four new functions, and neither of the two changed ones, throws or mutates its
inputs, for any value of any argument. That includes `undefined`, `null`, strings, numbers,
arrays, `{}`, prototype-named ids such as `constructor` and `__proto__`, and runs whose
`project` or `started_at` are garbage.

### Tests (TDD: written first, seen failing)

All of these tests are QML `TestCase` functions in `tests/core/domain/tst_runs.qml`. That is
the **domain unit tier**. The functions are pure `.pragma library` code with no store,
process or UI, and this file is where `runs.js` is tested. Use the existing helpers:
`mkRun(id, status, live, opts)` (:874; set `started_at` through `opts`, and add
`run.project = { root: "/r" }` on the returned object), `screenRuns()` (:1690), `ids()`
(:1701), `cancelSpellings()`/`cancelledRun()`, and the garbage-array loop pattern. Use a
fixed clock: `now = Date.parse("2026-10-04T12:00:00Z")`.

1. **The finished filter.** `filterRuns(screenRuns(), "finished")` gives `run-esc-00002`
   and `run-done-0005`. A list holding both cancel spellings, a parked run, a dead run and
   an unknown-status run keeps only the finished ones, as the same objects, in input order.
   Garbage lists give `[]`.
2. **The finished count.** `test_run_filter_counts` gets the new key list
   `all,attention,finished,live,parked` and values `attention,live,parked,finished,all`
   = `2,1,1,2,5`. Garbage gives all zeros. `test_fixture_cancel_spellings_filters_and_search`
   (:843) asserts `finished === 1` for each spelling, and its comment changes to say the
   run sits in Finished and All. These are test-only edits in their current tier.
3. **State chips.** For `filterFinished` with age `"all"`: `"done"` keeps only done,
   `"escalated"` keeps only escalated, and `"cancelled"` keeps both the `cancelled` and the
   `canceled` run (the real fixture runs from `cancelledRun()`). `"all"`, `""`, `"bogus"`,
   `undefined` and `"constructor"` keep every finished run.
4. **`withinAge` around local midnight, at fixed offsets.**
   - Offset `0`: `2026-10-04T00:00:00Z` is within today, and `2026-10-03T23:59:59Z` is not.
   - Offset `-180`: local midnight is `2026-10-04T03:00:00Z`, so `03:00:00Z` is within
     and `02:59:59Z` is not.
   - Offset `+600`: local midnight is `2026-10-03T14:00:00Z` (the previous UTC day).
   - Offset `+780`: local midnight is `2026-10-04T11:00:00Z` (the next local day).
   - With now exactly at local midnight (`now = 2026-10-04T03:00:00Z`, offset `-180`),
     `03:00:00Z` is within and `02:59:59.999Z` is not.
   - am's format with an offset, `"2026-10-04 00:00:00-03:00"`, is the same instant as
     `03:00Z` and gives the same results.
   - A non-finite offset (`undefined`, `NaN`, `"x"`) behaves as `0`.
5. **`withinAge` at the 7-day edge.** `2026-09-27T12:00:00Z` is within the week and
   `2026-09-27T11:59:59Z` is not. A future start is within. Age `"all"`, `""`, `"bogus"`
   and `undefined` give `true` even with no `started_at`. A non-finite clock gives `true`.
   A missing, empty, unparsable or non-string `started_at`, and garbage runs, give `false`
   under `"today"` and `"week"`.
6. **Live, parked and dead are never hidden.** Use a running, a dead, a parked and an
   unknown-status run, each with an old `started_at` (and one with none), together with
   finished runs. For every state chip × age × offset combination, including a non-finite
   clock, all four non-finished runs survive `filterFinished`. Only finished runs are ever
   dropped.
7. **`historyStatuses` per filter.** Every row of the table above, joined with `,` and
   compared. Two calls return different array objects. Garbage filters give the All list.
8. **`historyCursor` per root and empty.**
   - Two roots, mixed states and out-of-order `started_at` values (am's space format and
     `T`/`Z` forms mixed, plus differing offsets, so that string order would be wrong): each
     root gets its own oldest terminal `started_at`, returned verbatim.
   - A parked run can be the cursor.
   - Running and dead runs older than every terminal run are ignored.
   - Runs with an unparsable `started_at` are ignored.
   - On a tie, the first in input order wins.
   - A root with no terminal runs, an unknown root, `""`, a non-string root, `[]` and
     garbage `runs` all give `""`.
   - Runs with no `project`, or a non-object `project`, are never matched.
9. **Never throws.** For each new function, a garbage loop over
   `[undefined, null, "x", 5, [], {}]` in every argument position returns the default
   (`[]`, `true` or `false` as specified above, `""`, or the All list) without throwing. The
   input arrays compare unchanged (`ids()` before and after).

Verification: `bash tests/run.sh` is green. That runs pytest (including
`tests/architecture`) and then every `tst_*.qml` offscreen.

### For the planner

Files:

- Modify `core/domain/runs.js`:
  - add `"finished"` to `filterRuns` and `runFilterCounts` (:667-692);
  - add `withinAge`, `filterFinished`, `historyStatuses` and `historyCursor` next to them;
  - private helpers take the `_` prefix and sit above their first user.
- Modify `tests/core/domain/tst_runs.qml`: the new test functions, plus the two
  existing-test edits in item 2.

Suggested tasks, each with its own red-green cycle and commit:

1. The finished chip and its count (tests 1–2).
2. `withinAge` (tests 4–5).
3. `filterFinished` (tests 3, 6).
4. `historyStatuses` (test 7).
5. `historyCursor` (test 8).

Test 9's garbage loops go in each function's task.

### Out of scope

- Every caller and every piece of UI: the Finished chip in `RunsScreen`, the finished-state
  and age chip rows, `RunStore`'s `runFilter`/`finishedState`/`finishedAge` properties, and
  passing `-getTimezoneOffset()`. These belong to sibling cards and later stories.
- `core/stores/RunHistoryStore.qml`, Show older, `cursor` paging past the first page, and
  any change to `core/backend/runs/runs-history.py` or `common/am_runs.py`
  (parent :119-192).
- The titles work (2.1, done) and `RunTitlesStore`/`board-titles.py`.
- The parent's open questions (parent :228-233): `stopped` stays out of Finished, and age
  stays on `started_at`.
- Any `am` or `brd` change.

---

## Running tests

One test function, fast (about 0.3 s), from the worktree root:

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml DomainRuns::test_name
```

List several `DomainRuns::test_x DomainRuns::test_y` to run several. A call to a function `runs.js` does not define yet fails with `TypeError: Property 'withinAge' of object [object Object] is not a function` (or similar); that counts as the expected RED.

The full suite: `bash tests/run.sh`.

## File Structure

- Modify `core/domain/runs.js`: in the block that holds `_withState`, `runFilterCounts` and `filterRuns` (currently lines 667-692), add `_FINISHED_STATES`, `_isFinishedState`, `_finishedOf` (Task 1), then after `filterRuns` add `_DAY_MS`, `_startMs`, `withinAge` (Task 2), `filterFinished` (Task 3), `_HISTORY_ALL`, `historyStatuses` (Task 4), `historyCursor` (Task 5). All of it sits before `function _titlesFor(`.
- Modify `tests/core/domain/tst_runs.qml`: edit `test_fixture_cancel_spellings_filters_and_search` (:841-855) and `test_run_filter_counts` (:1703-1712); insert every new helper and test function directly above the line `  // ---- Run detail (5.2)` (currently :1745), each task's block after the previous task's.

---

### Task 1: The finished chip and its count

**Files:**
- Modify: `core/domain/runs.js:667-692`
- Test: `tests/core/domain/tst_runs.qml:841-855`, `:1703-1712`, and new functions above `  // ---- Run detail (5.2)`

**Interfaces:**
- Consumes: `runState(run)` (`runs.js:156`), `_arrayOr`, `attention`, `_withState` (existing).
- Produces: `_isFinishedState(state) → boolean` (true for `"done"`, `"escalated"`, `"cancelled"`), `_finishedOf(list) → array`; `filterRuns(runs, "finished")`; `runFilterCounts(runs).finished`. Tests: `rootedRun(id, status, live, root, startedAt)` helper (used by Task 5).

- [ ] **Step 1: Write the failing tests**

In `tests/core/domain/tst_runs.qml`, replace `test_fixture_cancel_spellings_filters_and_search` (the comment above it included) with:

```qml
  // A cancelled run in either spelling is found by its state name and sits in
  // the `finished` and `all` chips only.
  function test_fixture_cancel_spellings_filters_and_search() {
    var spellings = cancelSpellings()
    for (var i = 0; i < spellings.length; i++) {
      var run = cancelledRun(spellings[i])
      var counts = Runs.runFilterCounts([run])
      compare([counts.attention, counts.live, counts.parked, counts.finished, counts.all].join(","), "0,0,0,1,1",
              spellings[i] + ": chip counts")
      compare(Runs.searchRuns([run], "cancelled").length, 1, spellings[i] + ": found by its state name")
      compare(Runs.searchRuns([run], "unknown").length, 0, spellings[i] + ": not unknown")
    }
  }
```

Replace `test_run_filter_counts` with:

```qml
  function test_run_filter_counts() {
    var c = Runs.runFilterCounts(screenRuns())
    compare(Object.keys(c).sort().join(","), "all,attention,finished,live,parked")
    compare([c.attention, c.live, c.parked, c.finished, c.all].join(","), "2,1,1,2,5")
    var bad = [undefined, null, "x", 5, {}]
    for (var i = 0; i < bad.length; i++) {
      var b = Runs.runFilterCounts(bad[i])
      compare([b.attention, b.live, b.parked, b.finished, b.all].join(","), "0,0,0,0,0", "garbage " + i)
    }
  }
```

Insert directly above the line `  // ---- Run detail (5.2)`:

```qml
  // ---- History filters (2.2) -------------------------------------------------------------

  // mkRun with started_at and a `project` of { root: root }.
  function rootedRun(id, status, live, root, startedAt) {
    var run = mkRun(id, status, live, { started_at: startedAt })
    run.project = { root: root }
    return run
  }

  // One run per state, both cancel spellings, input order mixed.
  function finishedMix() {
    return [
      mkRun("c-cancelled", "cancelled", null),
      mkRun("p-parked", "stopped", null),
      mkRun("d-done", "done", null),
      mkRun("x-dead", "started", false),
      mkRun("c-canceled", "canceled", null),
      mkRun("u-unknown", "weird", null),
      mkRun("l-live", "started", true),
      mkRun("e-escalated", "escalated", null)
    ]
  }

  function test_filter_runs_finished() {
    compare(ids(Runs.filterRuns(screenRuns(), "finished")), "run-esc-00002,run-done-0005")
    var list = finishedMix()
    var before = ids(list)
    var kept = Runs.filterRuns(list, "finished")
    compare(ids(kept), "c-cancelled,d-done,c-canceled,e-escalated", "finished states only, input order")
    compare(kept[0] === list[0] && kept[3] === list[7], true, "the same objects")
    compare(Runs.runFilterCounts(list).finished, 4, "the count is the list's length")
    compare(ids(list), before, "input unchanged")
    var junk = Runs.filterRuns([null, 5, "x", {}, [], list[2]], "finished")
    compare(junk.length === 1 && junk[0] === list[2], true, "junk entries are not finished")
    var bad = [undefined, null, "x", 5, [], {}]
    for (var i = 0; i < bad.length; i++) compare(Runs.filterRuns(bad[i], "finished").length, 0, "garbage " + i)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml DomainRuns::test_run_filter_counts DomainRuns::test_fixture_cancel_spellings_filters_and_search DomainRuns::test_filter_runs_finished`
Expected: all three FAIL — key list `all,attention,live,parked`, counts `2,1,1,,5` / `0,0,0,,1`, and `filterRuns(…, "finished")` returning every run.

- [ ] **Step 3: Write the minimal implementation**

In `core/domain/runs.js`, replace the block from `function _withState(list, state) {` through the end of `filterRuns` with:

```js
function _withState(list, state) {
  var out = []
  for (var i = 0; i < list.length; i++) if (runState(list[i]) === state) out.push(list[i])
  return out
}

var _FINISHED_STATES = ["done", "escalated", "cancelled"]

// Whether `state`, a runState value, is finished: done, escalated or cancelled.
function _isFinishedState(state) { return _FINISHED_STATES.indexOf(state) >= 0 }

// The finished runs of the array `list`, same objects in input order.
function _finishedOf(list) {
  var out = []
  for (var i = 0; i < list.length; i++) if (_isFinishedState(runState(list[i]))) out.push(list[i])
  return out
}

// The chip counts, over every run (the search never narrows them).
function runFilterCounts(runs) {
  var list = _arrayOr(runs)
  return {
    attention: attention(list).length,
    live: _withState(list, "running").length,
    parked: _withState(list, "parked").length,
    finished: _finishedOf(list).length,
    all: list.length
  }
}

// One chip's runs, same objects in input order. `finished` is every done,
// escalated or cancelled run (either spelling). `all`, "" or any unknown id is
// every run.
function filterRuns(runs, id) {
  var list = _arrayOr(runs)
  if (id === "attention") return attention(list)
  if (id === "live") return _withState(list, "running")
  if (id === "parked") return _withState(list, "parked")
  if (id === "finished") return _finishedOf(list)
  return list
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml`
Expected: `Totals: N passed, 0 failed` (the whole file, so `test_filter_runs` and the rest stay green).

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): a finished chip in filterRuns and runFilterCounts"
```

---

### Task 2: `withinAge`

**Files:**
- Modify: `core/domain/runs.js` (insert after `filterRuns`, before `function _titlesFor(`)
- Test: `tests/core/domain/tst_runs.qml` (append after Task 1's block, above `  // ---- Run detail (5.2)`)

**Interfaces:**
- Consumes: `_isObject`, `_isFiniteNumber` (existing, `runs.js:176`, `:179`).
- Produces: `_DAY_MS` (86400000), `_startMs(run) → number` (the start instant, `NaN` when there is none; Task 5 uses it), `withinAge(run, age, nowMs, utcOffsetMinutes) → boolean` (Task 3 uses it).

- [ ] **Step 1: Write the failing tests**

Append above `  // ---- Run detail (5.2)` in `tests/core/domain/tst_runs.qml`:

```qml
  // A done run started at startedAt (undefined: no started_at).
  function startedRun(startedAt) { return mkRun("s", "done", null, { started_at: startedAt }) }

  // "a,b": withinAge "today" for a run started at `inside`, then at `outside`.
  function todayPair(inside, outside, now, offset) {
    return [Runs.withinAge(startedRun(inside), "today", now, offset),
            Runs.withinAge(startedRun(outside), "today", now, offset)].join(",")
  }

  function test_within_age_today_at_fixed_offsets() {
    var now = Date.parse("2026-10-04T12:00:00Z")
    compare(todayPair("2026-10-04T00:00:00Z", "2026-10-03T23:59:59Z", now, 0), "true,false", "UTC")
    compare(todayPair("2026-10-04T03:00:00Z", "2026-10-04T02:59:59Z", now, -180), "true,false", "UTC-3")
    compare(todayPair("2026-10-03T14:00:00Z", "2026-10-03T13:59:59Z", now, 600), "true,false",
            "UTC+10: the previous UTC day")
    compare(todayPair("2026-10-04T11:00:00Z", "2026-10-04T10:59:59Z", now, 780), "true,false",
            "UTC+13: the next local day")
    var atMidnight = Date.parse("2026-10-04T03:00:00Z")
    compare(todayPair("2026-10-04T03:00:00Z", "2026-10-04T02:59:59.999Z", atMidnight, -180), "true,false",
            "now exactly at local midnight")
    compare(todayPair("2026-10-04 00:00:00-03:00", "2026-10-03 23:59:59-03:00", now, -180), "true,false",
            "am's format with an offset")
    var badOffsets = [undefined, NaN, "x", null, Infinity, {}, "-180"]
    for (var i = 0; i < badOffsets.length; i++)
      compare(todayPair("2026-10-04T00:00:00Z", "2026-10-03T23:59:59Z", now, badOffsets[i]), "true,false",
              "non-finite offset " + i + " is 0")
    var run = startedRun("2026-10-04T03:00:00Z")
    var json = JSON.stringify(run)
    Runs.withinAge(run, "today", now, -180)
    compare(JSON.stringify(run), json, "the run is unchanged")
  }

  function test_within_age_week_and_defaults() {
    var now = Date.parse("2026-10-04T12:00:00Z")
    compare(Runs.withinAge(startedRun("2026-09-27T12:00:00Z"), "week", now, 0), true, "exactly 7 days")
    compare(Runs.withinAge(startedRun("2026-09-27T11:59:59Z"), "week", now, 0), false, "a second over")
    compare(Runs.withinAge(startedRun("2026-09-27 12:00:00+00:00"), "week", now, 600), true,
            "the offset never moves the week")
    compare(Runs.withinAge(startedRun("2026-10-05T12:00:00Z"), "week", now, 0), true, "a future start, week")
    compare(Runs.withinAge(startedRun("2026-10-05T12:00:00Z"), "today", now, 0), true, "a future start, today")
    compare(Runs.withinAge(mkRun("l", "started", true, { started_at: "2020-01-01T00:00:00Z" }), "week", now, 0),
            false, "the run's state is not consulted")
    var anyAge = ["all", "", "bogus", undefined, null, 5, "constructor", "__proto__", "Today"]
    for (var i = 0; i < anyAge.length; i++) {
      compare(Runs.withinAge(startedRun(undefined), anyAge[i], now, 0), true, "age " + i + " with no started_at")
      compare(Runs.withinAge(startedRun("2020-01-01T00:00:00Z"), anyAge[i], now, 0), true, "age " + i + " with an old start")
    }
    var badNow = [undefined, null, "x", NaN, Infinity, -Infinity, {}, []]
    for (var j = 0; j < badNow.length; j++) {
      compare(Runs.withinAge(startedRun("2020-01-01T00:00:00Z"), "today", badNow[j], 0), true, "no clock, today " + j)
      compare(Runs.withinAge(startedRun(undefined), "week", badNow[j], 0), true, "no clock, week " + j)
    }
    var noStart = [startedRun(undefined), startedRun(""), startedRun("not a date"), startedRun(5),
                   startedRun(null), startedRun({}), undefined, null, "x", 5, [], {}]
    for (var k = 0; k < noStart.length; k++) {
      compare(Runs.withinAge(noStart[k], "today", now, 0), false, "no start instant, today " + k)
      compare(Runs.withinAge(noStart[k], "week", now, 0), false, "no start instant, week " + k)
    }
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml DomainRuns::test_within_age_today_at_fixed_offsets DomainRuns::test_within_age_week_and_defaults`
Expected: both FAIL with a TypeError: `withinAge` is not a function.

- [ ] **Step 3: Write the minimal implementation**

In `core/domain/runs.js`, insert directly after the closing `}` of `filterRuns` (and before the comment above `function _titlesFor(`):

```js

var _DAY_MS = 86400000

// Date.parse(run.started_at) when `run` is an object whose `started_at` is a
// non-empty string that parses to a finite number; NaN otherwise.
function _startMs(run) {
  if (!_isObject(run) || typeof run.started_at !== "string" || run.started_at === "") return NaN
  var t = Date.parse(run.started_at)
  return isFinite(t) ? t : NaN
}

// Whether `run` started within `age` of `nowMs`. "today": at or after local
// midnight, for a local offset of `utcOffsetMinutes` east of UTC (0 when not a
// finite number). "week": at or after nowMs - 7 days. No upper bound. Any other
// age, or a `nowMs` that is not a finite number, is true. A run with no start
// instant (see _startMs) is false under "today" and "week". The run's state is
// not consulted. Never mutates, never throws.
function withinAge(run, age, nowMs, utcOffsetMinutes) {
  if (age !== "today" && age !== "week") return true
  if (!_isFiniteNumber(nowMs)) return true
  var start = _startMs(run)
  if (!isFinite(start)) return false
  if (age === "week") return start >= nowMs - 7 * _DAY_MS
  var off = (_isFiniteNumber(utcOffsetMinutes) ? utcOffsetMinutes : 0) * 60000
  return start >= Math.floor((nowMs + off) / _DAY_MS) * _DAY_MS - off
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml`
Expected: `Totals: N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): withinAge measures a run's start against today or the last 7 days"
```

---

### Task 3: `filterFinished`

**Files:**
- Modify: `core/domain/runs.js` (insert after `withinAge`)
- Test: `tests/core/domain/tst_runs.qml` (append after Task 2's block, above `  // ---- Run detail (5.2)`)

**Interfaces:**
- Consumes: `_arrayOr`, `runState`, `_isFinishedState(state)` (Task 1), `withinAge(run, age, nowMs, utcOffsetMinutes)` (Task 2). Tests use `mkRun`, `ids`, `cancelledRun` (existing).
- Produces: `filterFinished(runs, finishedState, finishedAge, nowMs, utcOffsetMinutes) → array`.

- [ ] **Step 1: Write the failing tests**

Append above `  // ---- Run detail (5.2)` in `tests/core/domain/tst_runs.qml`:

```qml
  function stateList(list) { return list.map(function(r) { return r.status }).join(",") }

  // The ids of the runs in list whose state is not finished.
  function unfinishedIds(list) {
    var out = []
    for (var i = 0; i < list.length; i++)
      if (["done", "escalated", "cancelled"].indexOf(Runs.runState(list[i])) < 0) out.push(list[i].id)
    return out.join(",")
  }

  function test_filter_finished_state_chips() {
    var now = Date.parse("2026-10-04T12:00:00Z")
    var list = [mkRun("d", "done", null), mkRun("e", "escalated", null), cancelledRun("cancelled"),
                cancelledRun("canceled"), mkRun("p", "stopped", null)]
    compare(stateList(Runs.filterFinished(list, "done", "all", now, 0)), "done,stopped")
    compare(stateList(Runs.filterFinished(list, "escalated", "all", now, 0)), "escalated,stopped")
    compare(stateList(Runs.filterFinished(list, "cancelled", "all", now, 0)), "cancelled,canceled,stopped",
            "cancelled covers both spellings")
    var anyState = ["all", "", "bogus", undefined, "constructor", "__proto__", "canceled", null, 5]
    for (var i = 0; i < anyState.length; i++)
      compare(stateList(Runs.filterFinished(list, anyState[i], "all", now, 0)),
              "done,escalated,cancelled,canceled,stopped", "state " + i + " keeps every finished run")
    var kept = Runs.filterFinished(list, "cancelled", "all", now, 0)
    compare(kept[0] === list[2] && kept[1] === list[3] && kept[2] === list[4], true, "the same objects")
  }

  function test_filter_finished_state_and_age() {
    var now = Date.parse("2026-10-04T12:00:00Z")
    var list = [mkRun("done-new", "done", null, { started_at: "2026-10-04 09:00:00+00:00" }),
                mkRun("done-old", "done", null, { started_at: "2026-09-01T00:00:00Z" }),
                mkRun("esc-new", "escalated", null, { started_at: "2026-10-04T10:00:00Z" }),
                mkRun("done-none", "done", null)]
    compare(ids(Runs.filterFinished(list, "done", "week", now, 0)), "done-new", "state and age must both hold")
    compare(ids(Runs.filterFinished(list, "all", "today", now, 0)), "done-new,esc-new", "today, UTC")
    compare(ids(Runs.filterFinished(list, "all", "today", now, 780)), "",
            "UTC+13: both started before local midnight")
    compare(ids(Runs.filterFinished(list, "all", "all", now, 0)), "done-new,done-old,esc-new,done-none",
            "All time keeps a run with no started_at")
  }

  function test_filter_finished_never_hides_unfinished() {
    var now = Date.parse("2026-10-04T12:00:00Z")
    var old = "2020-01-01T00:00:00Z"
    var list = [mkRun("live", "started", true, { started_at: old }),
                mkRun("old-done", "done", null, { started_at: old }),
                mkRun("dead", "started", false, { started_at: old }),
                mkRun("old-esc", "escalated", null, { started_at: old }),
                mkRun("parked", "stopped", null, { started_at: old }),
                mkRun("old-canc", "canceled", null, { started_at: old }),
                mkRun("unknown", "weird", null),
                mkRun("new-done", "done", null, { started_at: "2026-10-04T11:00:00Z" })]
    var before = JSON.stringify(list)
    var states = ["all", "done", "escalated", "cancelled", "", "bogus", undefined, "constructor"]
    var ages = ["all", "today", "week", "", "bogus", undefined]
    var offsets = [0, -180, 600, 780, undefined, NaN]
    var clocks = [now, NaN, undefined]
    for (var s = 0; s < states.length; s++)
      for (var a = 0; a < ages.length; a++)
        for (var o = 0; o < offsets.length; o++)
          for (var c = 0; c < clocks.length; c++)
            compare(unfinishedIds(Runs.filterFinished(list, states[s], ages[a], clocks[c], offsets[o])),
                    "live,dead,parked,unknown", "state " + s + " age " + a + " offset " + o + " clock " + c)
    compare(ids(Runs.filterFinished(list, "all", "today", now, 0)), "live,dead,parked,unknown,new-done",
            "only finished runs are dropped")
    compare(JSON.stringify(list), before, "input unchanged")
  }

  function test_filter_finished_garbage() {
    var now = Date.parse("2026-10-04T12:00:00Z")
    var list = [mkRun("d", "done", null, { started_at: "2026-10-04T11:00:00Z" }), mkRun("p", "stopped", null)]
    var before = ids(list)
    var bad = [undefined, null, "x", 5, [], {}]
    for (var i = 0; i < bad.length; i++) {
      compare(Runs.filterFinished(bad[i], "all", "all", now, 0).length, 0, "runs " + i)
      compare(ids(Runs.filterFinished(list, bad[i], "today", now, 0)), "d,p", "finishedState " + i)
      compare(ids(Runs.filterFinished(list, "done", bad[i], now, 0)), "d,p", "finishedAge " + i)
      compare(ids(Runs.filterFinished(list, "done", "today", bad[i], 0)), "d,p", "nowMs " + i)
      compare(ids(Runs.filterFinished(list, "done", "today", now, bad[i])), "d,p", "utcOffsetMinutes " + i)
    }
    var junk = [undefined, null, "x", 5, [], {}]
    compare(Runs.filterFinished(junk, "done", "today", now, 0).length, junk.length,
            "junk entries are not finished, so they are kept")
    compare(ids(list), before, "input unchanged")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml DomainRuns::test_filter_finished_state_chips DomainRuns::test_filter_finished_state_and_age DomainRuns::test_filter_finished_never_hides_unfinished DomainRuns::test_filter_finished_garbage`
Expected: all four FAIL with a TypeError: `filterFinished` is not a function.

- [ ] **Step 3: Write the minimal implementation**

In `core/domain/runs.js`, insert directly after the closing `}` of `withinAge`:

```js

// The runs to list under the Finished chip's state and age rows, same objects
// in input order; [] when `runs` is not an array. A run that is not finished
// (running, dead, parked or unknown) is always kept. A finished run is kept
// when its state equals `finishedState` ("done", "escalated" or "cancelled",
// which covers both spellings; any other value matches every finished run) and
// withinAge(run, finishedAge, nowMs, utcOffsetMinutes) is true. Never mutates,
// never throws.
function filterFinished(runs, finishedState, finishedAge, nowMs, utcOffsetMinutes) {
  var list = _arrayOr(runs)
  var anyState = finishedState !== "done" && finishedState !== "escalated" && finishedState !== "cancelled"
  var out = []
  for (var i = 0; i < list.length; i++) {
    var state = runState(list[i])
    if (!_isFinishedState(state)) out.push(list[i])
    else if ((anyState || state === finishedState) && withinAge(list[i], finishedAge, nowMs, utcOffsetMinutes)) out.push(list[i])
  }
  return out
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml`
Expected: `Totals: N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): filterFinished narrows finished runs by state and age, never hiding the rest"
```

---

### Task 4: `historyStatuses`

**Files:**
- Modify: `core/domain/runs.js` (insert after `filterFinished`)
- Test: `tests/core/domain/tst_runs.qml` (append after Task 3's block, above `  // ---- Run detail (5.2)`)

**Interfaces:**
- Consumes: nothing new.
- Produces: `historyStatuses(filter, finishedState) → array of strings`, a new array per call.

- [ ] **Step 1: Write the failing test**

Append above `  // ---- Run detail (5.2)` in `tests/core/domain/tst_runs.qml`:

```qml
  function test_history_statuses() {
    var all = "done,escalated,stopped,cancelled,canceled"
    var finishedAll = "done,escalated,cancelled,canceled"
    compare(Runs.historyStatuses("all").join(","), all)
    compare(Runs.historyStatuses("parked").join(","), "stopped")
    compare(Runs.historyStatuses("attention").join(","), "escalated")
    compare(Runs.historyStatuses("live").length, 0, "a live run is never terminal")
    compare(Runs.historyStatuses("finished", "done").join(","), "done")
    compare(Runs.historyStatuses("finished", "escalated").join(","), "escalated")
    compare(Runs.historyStatuses("finished", "cancelled").join(","), "cancelled,canceled")
    var anyState = ["all", "", "bogus", "canceled", undefined, null, 5, [], {}, "constructor"]
    for (var i = 0; i < anyState.length; i++)
      compare(Runs.historyStatuses("finished", anyState[i]).join(","), finishedAll, "finishedState " + i)
    var badFilter = ["", "bogus", "Finished", undefined, null, "x", 5, [], {}, "constructor", "__proto__"]
    for (var j = 0; j < badFilter.length; j++)
      compare(Runs.historyStatuses(badFilter[j], "done").join(","), all, "filter " + j + " is All")
    compare(Runs.historyStatuses("parked", "done").join(","), "stopped", "finishedState only matters to finished")
    var a = Runs.historyStatuses("all"), b = Runs.historyStatuses("all")
    compare(a === b, false, "a new array per call")
    a.push("x")
    compare(Runs.historyStatuses("all").join(","), all, "a caller's change never leaks")
  }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml DomainRuns::test_history_statuses`
Expected: FAIL with a TypeError: `historyStatuses` is not a function.

- [ ] **Step 3: Write the minimal implementation**

In `core/domain/runs.js`, insert directly after the closing `}` of `filterFinished`:

```js

// The `--status` list for one history page of a chip, a new array per call.
// "live" is [] (a live run is never terminal); "parked" is ["stopped"];
// "attention" is ["escalated"]; "finished" is the statuses of `finishedState`
// ("done", "escalated", or "cancelled" with both spellings; any other value is
// all four finished statuses). "all" and any other `filter` is all five
// terminal statuses.
function historyStatuses(filter, finishedState) {
  if (filter === "live") return []
  if (filter === "parked") return ["stopped"]
  if (filter === "attention") return ["escalated"]
  if (filter !== "finished") return ["done", "escalated", "stopped", "cancelled", "canceled"]
  if (finishedState === "done") return ["done"]
  if (finishedState === "escalated") return ["escalated"]
  if (finishedState === "cancelled") return ["cancelled", "canceled"]
  return ["done", "escalated", "cancelled", "canceled"]
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml`
Expected: `Totals: N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): historyStatuses gives a chip's --status list for one history page"
```

---

### Task 5: `historyCursor`

**Files:**
- Modify: `core/domain/runs.js` (insert after `historyStatuses`)
- Test: `tests/core/domain/tst_runs.qml` (append after Task 4's block, above `  // ---- Run detail (5.2)`)

**Interfaces:**
- Consumes: `runRoot(run)` (`runs.js`, near the end of the file, "Store helpers"; function declarations hoist), `runState`, `_isFinishedState(state)` (Task 1), `_startMs(run)` (Task 2). Tests use `rootedRun(id, status, live, root, startedAt)` (Task 1), `mkRun`, `ids`.
- Produces: `historyCursor(runs, root) → string`.

- [ ] **Step 1: Write the failing tests**

Append above `  // ---- Run detail (5.2)` in `tests/core/domain/tst_runs.qml`:

```qml
  function test_history_cursor_per_root() {
    var list = [
      rootedRun("a-live", "started", true, "/a", "2026-09-01T00:00:00Z"),
      rootedRun("b-canc", "canceled", null, "/b", "2026-10-03T02:00:00Z"),
      rootedRun("a-done", "done", null, "/a", "2026-10-03 10:00:00+00:00"),
      rootedRun("a-dead", "started", false, "/a", "2026-09-02 00:00:00+00:00"),
      rootedRun("b-live", "started", true, "/b", "2026-01-01T00:00:00Z"),
      rootedRun("a-esc", "escalated", null, "/a", "2026-10-03T12:00:00+05:00"),
      rootedRun("a-bad", "cancelled", null, "/a", "not a date"),
      rootedRun("b-park", "stopped", null, "/b", "2026-10-02 23:00:00-02:00"),
      rootedRun("a-unk", "weird", null, "/a", "2026-08-01T00:00:00Z")
    ]
    var before = JSON.stringify(list)
    compare(Runs.historyCursor(list, "/a"), "2026-10-03T12:00:00+05:00",
            "the oldest instant (07:00Z), not the smallest string; running, dead, unknown and unparsable ignored")
    compare(Runs.historyCursor(list, "/b"), "2026-10-02 23:00:00-02:00", "a parked run can be the cursor")
    compare(JSON.stringify(list), before, "input unchanged")
  }

  function test_history_cursor_ties_and_empty() {
    var tie = [rootedRun("t1", "done", null, "/a", "2026-10-03T10:00:00Z"),
               rootedRun("t2", "escalated", null, "/a", "2026-10-03 10:00:00+00:00"),
               rootedRun("t3", "stopped", null, "/a", "2026-10-03 07:00:00-03:00")]
    compare(Runs.historyCursor(tie, "/a"), "2026-10-03T10:00:00Z", "a tie goes to the first in input order")
    compare(Runs.historyCursor(tie.slice(1), "/a"), "2026-10-03 10:00:00+00:00", "verbatim, am's format")
    var unfinished = [rootedRun("l", "started", true, "/a", "2026-10-01T00:00:00Z"),
                      rootedRun("d", "started", false, "/a", "2026-10-01T00:00:00Z"),
                      rootedRun("u", "weird", null, "/a", "2026-10-01T00:00:00Z")]
    compare(Runs.historyCursor(unfinished, "/a"), "", "no terminal run")
    compare(Runs.historyCursor(tie, "/zzz"), "", "an unknown root")
    compare(Runs.historyCursor(tie, "/a/"), "", "roots compare exactly")
    compare(Runs.historyCursor([], "/a"), "", "no runs")
    compare(Runs.historyCursor([mkRun("n", "done", null, { started_at: "2026-10-01T00:00:00Z" })], "/a"), "",
            "a run with no project")
    var odd = ["x", 5, null, [], { root: 5 }, { name: "/a" }]
    for (var k = 0; k < odd.length; k++) {
      var r = mkRun("o", "done", null, { started_at: "2026-10-01T00:00:00Z" })
      r.project = odd[k]
      compare(Runs.historyCursor([r], "/a"), "", "project " + k + " never matches")
    }
    var badStart = [undefined, "", "not a date", 5, null, {}]
    for (var m = 0; m < badStart.length; m++)
      compare(Runs.historyCursor([rootedRun("s", "done", null, "/a", badStart[m])], "/a"), "", "started_at " + m)
  }

  function test_history_cursor_garbage() {
    var list = [rootedRun("a", "done", null, "/a", "2026-10-03T10:00:00Z")]
    var bad = [undefined, null, "x", 5, [], {}]
    for (var i = 0; i < bad.length; i++) {
      compare(Runs.historyCursor(bad[i], "/a"), "", "runs " + i)
      compare(Runs.historyCursor(list, bad[i]), "", "root " + i)
    }
    compare(Runs.historyCursor(list, ""), "", "an empty root")
    compare(Runs.historyCursor([undefined, null, "x", 5, [], {}, list[0]], "/a"), "2026-10-03T10:00:00Z",
            "junk entries are skipped")
    compare(Runs.historyCursor([rootedRun("c", "done", null, "constructor", "2026-10-03T10:00:00Z")], "constructor"),
            "2026-10-03T10:00:00Z", "a root named constructor")
    compare(Runs.historyCursor(list, "__proto__"), "", "a root named __proto__")
    compare(ids(list), "a", "input unchanged")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml DomainRuns::test_history_cursor_per_root DomainRuns::test_history_cursor_ties_and_empty DomainRuns::test_history_cursor_garbage`
Expected: all three FAIL with a TypeError: `historyCursor` is not a function.

- [ ] **Step 3: Write the minimal implementation**

In `core/domain/runs.js`, insert directly after the closing `}` of `historyStatuses`:

```js

// The `--before` time for the next history page of the project at `root`: the
// `started_at` string, exactly as given, of the run with the smallest start
// instant (see _startMs) among the terminal runs (finished or parked) whose
// runRoot(run) === root; the first in input order on a tie. "" when there is
// no such run, `root` is not a non-empty string or `runs` is not an array.
// Never mutates, never throws.
function historyCursor(runs, root) {
  if (typeof root !== "string" || root === "" || !Array.isArray(runs)) return ""
  var best = "", bestMs = NaN
  for (var i = 0; i < runs.length; i++) {
    var run = runs[i]
    if (runRoot(run) !== root) continue
    var state = runState(run)
    if (state !== "parked" && !_isFinishedState(state)) continue
    var t = _startMs(run)
    if (isFinite(t) && (isNaN(bestMs) || t < bestMs)) { best = run.started_at; bestMs = t }
  }
  return best
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml`
Expected: `Totals: N passed, 0 failed`.

- [ ] **Step 5: Run the full verification**

Run: `bash tests/run.sh`
Expected: pytest passes (including `tests/architecture`), every `== tests/…/tst_*.qml` block prints `Totals: … 0 failed`, no `TypeError`/`ReferenceError` lines, exit status 0.

- [ ] **Step 6: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): historyCursor gives a root's oldest terminal started_at for --before"
```

---

## Self-review against the spec

- `filterRuns(…, "finished")` and `runFilterCounts.finished` → Task 1 (spec tests 1–2, both existing-test edits).
- `withinAge` every rule (age gate, clock gate, no start instant, today formula inclusive, week inclusive, no upper bound, state not consulted, offset fallback) → Task 2 (spec tests 4–5).
- `filterFinished` state match, age match, unfinished always kept, garbage → Task 3 (spec tests 3, 6).
- `historyStatuses` every table row, new array per call, unknown filter → All, `live` → `[]` → Task 4 (spec test 7).
- `historyCursor` per root, parked cursor, running/dead/unknown ignored, unparsable ignored, tie, verbatim, empty cases, garbage project → Task 5 (spec test 8).
- Never throws / never mutates (spec test 9) → garbage loops and before/after checks in Tasks 1, 2, 3, 4 (fresh arrays), 5.
- Full `bash tests/run.sh` → Task 5 Step 5.
<!-- task-pipeline: validated -->
