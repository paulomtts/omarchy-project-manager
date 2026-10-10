# 2.2 runs.js: the finished-run filters — design

Card `227b4c50-7e62-42cf-adb8-7757ac65fe17`, a subtask of story `091a4b97`. It is blocked by
2.1 (`41e2402b`, run titles), which has already landed on this branch.
Parent design: `docs/superpowers/specs/2026-10-05-run-history-titles-design.md` (called
"parent" below). This card puts the parent's **History › Filters** section (parent :137-151)
into `core/domain/runs.js`. It adds pure functions and one chip, and it wires no caller.

## Inherited constraints

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

## Shared definitions

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

## Behaviour

### `filterRuns(runs, "finished")` and `runFilterCounts`

- `filterRuns(runs, "finished")` returns the finished runs as the same objects, in input
  order. All other chip ids behave as they do today (`runs.js:686-692`). An unknown id
  still means every run.
- `runFilterCounts(runs)` gains a `finished` key, which is the length of that list. Its key
  set becomes `all, attention, finished, live, parked`. Garbage input gives `0` for every
  key. Callers that read only named keys (`RunStore.qml:79`, `RunsScreen.qml:45`,
  `Panel.qml:258`, `tst_panel_toolbar.qml:401`) are unaffected.

### `withinAge(run, age, nowMs, utcOffsetMinutes)` → boolean

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

### `filterFinished(runs, finishedState, finishedAge, nowMs, utcOffsetMinutes)` → array

- It returns the same objects in input order. If `runs` is not an array, the result is `[]`.
- Every run that is not finished is **always kept**, whatever the state, age, clock or
  offset.
- A finished run is kept when both of these hold:
  - **State match.** `finishedState` is `"done"`, `"escalated"` or `"cancelled"` and
    equals the run's state, so `"cancelled"` covers both spellings. Any other value
    (`"all"`, `""`, unknown, or a non-string) matches every finished run.
  - **Age match.** `withinAge(run, finishedAge, nowMs, utcOffsetMinutes)` is true.
- The function does not mutate its inputs and never throws.

### `historyStatuses(filter, finishedState)` → array of strings

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

### `historyCursor(runs, root)` → string

- If `root` is not a non-empty string, or `runs` is not an array, the result is `""`.
- The candidates are the runs whose `runRoot(run) === root` (`runs.js:1440`), that are
  terminal, and that have a start instant.
- The result is the `started_at` string, returned exactly as given, of the candidate with
  the smallest start instant. When several candidates tie, the first in input order wins.
  With no candidate, the result is `""`.
- Running, dead and unknown runs, runs of other roots, and runs with an unparsable
  `started_at` are ignored.
- The function never throws.

### Never throws

None of the four new functions, and neither of the two changed ones, throws or mutates its
inputs, for any value of any argument. That includes `undefined`, `null`, strings, numbers,
arrays, `{}`, prototype-named ids such as `constructor` and `__proto__`, and runs whose
`project` or `started_at` are garbage.

## Tests (TDD: written first, seen failing)

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

## For the planner

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

## Out of scope

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
