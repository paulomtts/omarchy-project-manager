# 1.2 runEvents.js: foldEvents and filterRows (card de9d0a47) — design

Narrows `docs/superpowers/specs/2026-10-05-run-events-timeline-design.md` (S5, "parent"
below) to one subtask of story ca0c7263. The parent's Architecture section (lines 72-74)
names `mergeRows(rows, events, cap)` and `filterRows(rows, filter)` in
`core/domain/runEvents.js`; this card delivers both, under the card's name `foldEvents` for
the first (the later `2026-10-06-am-snapshots-cursors-design.md:125-126` also calls it
`foldEvents`: "a dedupe by `gseq` and a cap, not a state reducer"). Card 1.1 (6cb6a763,
`docs/superpowers/specs/1-1-runevents-js-6cb6a763.md`) already delivered `eventRow` and
`durationText`; this card appends to the same file and the same test file.

## Scope

In scope:

- `core/domain/runEvents.js`: two new public functions, `foldEvents(rows, events, cap)` and
  `filterRows(rows, filter)`, appended after `durationText`. Existing code is not changed.
- `tests/core/domain/tst_run_events.qml`: new `test_fold_*` and `test_filter_*` functions,
  written first (TDD). Existing tests are not changed.

Out of scope (sibling or later cards own it):

- `rowGlyph` (parent line 74) and any glyph character, the `urgent` token or `‼` for
  failures (parent lines 121-122): the UI's job.
- `RunStore.qml` events state: `events`, `eventsHasEarlier`, `eventsCursor` (highest `gseq`),
  `eventsOldestSeq`, `eventsStatus`, `eventsFilter`, `eventsError` (parent lines 82-89), the
  fetch sequencing (lines 94-105) and deciding what `dropped` means for `eventsHasEarlier`.
  The store computes `eventsCursor` from the raw `am events` page (which has `gseq`), not from
  rows, which carry no `gseq`.
- `core/backend/runs/runs-events.py`, `EventsPane.qml`, the filter chips, `RunDetailScreen.qml`
  wiring, the `am events` contract test (parent lines 77-90, 170-179).
- Building rows: `foldEvents` takes rows already built by `eventRow`; it does not call
  `eventRow` and takes no `titles` or `utcOffsetMinutes`.
- Any change to `eventRow`, `durationText` or the row shape.
- `docs/architecture.md` and README text for `runEvents.js`: the milestone's docs card.

## Inherited constraints

- Layering (`docs/architecture.md:11`; parent lines 69-70): `core/domain/*.js` holds only
  `.pragma library` and `.import "x.js" as X` of other `core/domain` files. No new import is
  needed; `tests/architecture/test_layers.py` must pass unchanged.
- No glyph characters in `core/domain` (`tests/architecture/test_icon_glyphs.py`); no
  duplicated helpers: reuse the file's private `_isObject`, `_has`, `_isFiniteNumber`.
- Pure and never throwing, like the rest of `core/domain` (`docs/architecture.md:180`); never
  mutates its input (card).
- Not a state reducer (parent line 73; non-goal "No event reducer", line 40): `foldEvents`
  never merges two rows into one, never derives a row's status from other rows; a duplicate
  seq is resolved by keeping one whole row.
- Cap 500, oldest dropped (parent line 82, Errors table line 161; card default `cap=500`).
- Failure statuses: `failed`, `escalated`, `gate_failed`, `schema_invalid`, `harness_error`
  (parent line 121; card).
- Filter names `All`, `Phases`, `Failures` (parent UI, line 130; card).
- Row shape from card 1.1 (parent lines 109-110):
  `{seq, time, level, label, status, glyph, duration, detail, card, phase, attempt}`, `level`
  one of `run|story|subtask|phase|attempt`.
- Comments and docstrings state the contract only, no narrative (card). ES5 `var`, private
  helpers `_`-prefixed.

## Dedupe key: `seq`, not `gseq`

The parent says dedupe by `gseq` (lines 73, 100); the card says by `seq`. Rows carry `seq`
only (card 1.1's row model has no `gseq`). The two are equivalent for this function: the
store holds one run's rows at a time (parent line 103), and within one run `seq` is unique and
in the same order as `gseq` (both strictly rise per recorded event; in
`tests/fixtures/am/events.json` seq 1..60 map to gseq 358..417). So `foldEvents` dedupes and
orders by `row.seq`. The card is the authority.

## Interface

```
foldEvents(rows, events, cap) -> { rows: row[], dropped: number }
filterRows(rows, filter) -> row[]
```

### foldEvents(rows, events, cap)

`rows` is the held timeline; `events` is a page of new rows (the output of `eventRow` for each
event of an `am events` page, which may contain `null` for ignored events). Both may be in any
order and may overlap.

1. An entry of `rows` or `events` counts when it is a non-array object whose `seq` is a finite
   number. Every other entry (`null`, `undefined`, a number, a string, an array, an object
   without a numeric `seq`) is skipped and not counted in `dropped`. A `rows` or `events` that
   is not an array is read as `[]`.
2. Dedupe by `seq`: `rows` are taken first, then `events`, each in array order; a later entry
   with the same `seq` replaces the earlier one. So a row in `events` wins over a held row with
   the same `seq`, and within one array the last one wins. The kept entry is the whole object;
   nothing is merged.
3. Order: ascending by `seq`, whatever the input order (so an earlier page folded in lands at
   the front, a later page at the back).
4. Cap: when more than `cap` unique rows remain, the lowest-`seq` rows are removed until `cap`
   remain; `dropped` is the number removed (`0` when within the cap).
   - `cap` missing (`undefined`) → `500`.
   - `cap` not a finite number (`null`, `"10"`, `NaN`, `Infinity`) or negative → `500`.
   - fractional → floored (`2.9` → `2`).
   - `0` → `rows: []`, `dropped` = every unique row.
5. The result's `rows` is a new array; neither `rows` nor `events` nor any entry is modified
   (entries are the same objects, not copies). Pushing to or sorting the returned array leaves
   both inputs unchanged.

### filterRows(rows, filter)

Returns a new array of the entries of `rows` that are non-array objects and match `filter`,
in their input order:

| `filter` | keeps |
|---|---|
| `"All"` | every object entry |
| `"Phases"` | `level` is `"phase"` or `"attempt"` |
| `"Failures"` | `status` is one of `failed`, `escalated`, `gate_failed`, `schema_invalid`, `harness_error` (any level: an escalated run, story or subtask counts) |
| anything else (`undefined`, `null`, `""`, `"phases"`, `"bogus"`, a number) | same as `"All"` |

Filter names are case-sensitive. `stopped`, `cancelled`, `canceled`, `pending` are not
failures. Membership checks use own keys only, so a status such as `"constructor"` or
`"toString"` is never a failure. A `rows` that is not an array → `[]`. The returned array is
always new (even for `"All"`); `rows` and its entries are not modified.

## Error paths

All return without throwing and without a qmltestrunner warning (`tests/run.sh` fails on
TypeError, ReferenceError and the like):

| input | result |
|---|---|
| `foldEvents()` / `foldEvents(null, null)` / `foldEvents("x", 5)` | `{rows: [], dropped: 0}` |
| `events` holding `null` (ignored events from `eventRow`), junk, objects without numeric `seq` | those entries skipped, not counted in `dropped` |
| duplicate `seq` across or within `rows` and `events` | one row per `seq`; last taken wins (events after rows) |
| `cap` `undefined`, `null`, `"10"`, `NaN`, `Infinity`, `-1` | cap 500 |
| `cap` `2.9` | cap 2 |
| `cap` `0` | `rows: []`, `dropped` = unique row count |
| `filterRows(null, "All")`, `filterRows("x")`, `filterRows(5, "Phases")` | `[]` |
| `rows` holding `null` or junk entries | skipped by every filter |
| unknown `filter` | same as `"All"` |
| row status `"constructor"` / `"toString"` under `"Failures"` | not kept |

## Tests

All new tests are **QML domain tests** in `tests/core/domain/tst_run_events.qml`: the tier for
pure `core/domain/*.js` (`docs/architecture.md` "Tests"; parent Testing lines 165-169 puts
`mergeRows` (here `foldEvents`) and `filterRows` there). They reuse the file's existing
`events()` and `titles()` helpers and add one helper, `fixtureRows()`: every non-null
`RE.eventRow(e, titles(), 0)` of `events()`, i.e. 59 rows with seq 2..60 (seq 1 is
`lease_acquired`, ignored). Of those, 28 are `phase` and 14 `attempt` rows (42 for
`Phases`), and none has a failure status. Failure rows and hand-built rows are copies of
fixture rows with `status`/`seq` edited, each marked `// synthetic:`
(`docs/architecture.md:255-268`).

The **architecture tier** (`tests/architecture/test_layers.py`, `test_icon_glyphs.py`) must
pass unchanged. No backend, store, contract or UI tests belong to this card.

| test (QML domain tier) | pins |
|---|---|
| `test_fold_append` | `foldEvents(first 30 fixture rows, last 29, 500)` → 59 rows, seqs 2..60 ascending, `dropped 0`; `foldEvents([], all)` equals the same seq list. |
| `test_fold_prepend` | `foldEvents(last 29, first 30)` → seqs 2..60 ascending (an earlier page lands at the front). |
| `test_fold_out_of_order` | `events` = the 59 rows reversed, and a shuffled order (fixed permutation in the test) → seqs 2..60 ascending; held rows out of order are also sorted. |
| `test_fold_dedupe` | folding overlapping pages (rows seq 2..40, events seq 30..60) → 59 rows, each seq once, `dropped 0`; folding the same page twice → 59 rows. |
| `test_fold_incoming_wins` | synthetic: held row seq 10 with `label "old"`, event row seq 10 with `label "new"` → the one row with seq 10 is the event's object (`label "new"`); two event rows with seq 10 → the later one; two held rows with seq 10 and no event → the later held one. |
| `test_fold_cap` | `foldEvents([], all 59, 10)` → seqs 51..60, `dropped 49`; `foldEvents(first 30, last 29, 59)` → 59 rows, `dropped 0`; cap 58 → seqs 3..60, `dropped 1`; duplicates are not counted (`foldEvents(all, all, 50)` → `dropped 9`). |
| `test_fold_cap_default_and_bad` | synthetic: 501 rows seq 1..501 (copies of one fixture row) with cap omitted, `undefined`, `null`, `"10"`, `NaN`, `Infinity`, `-1` → 500 rows seq 2..501, `dropped 1`; cap `2.9` on fixture rows → 2 rows (seq 59, 60), `dropped 57`; cap `0` → `rows []`, `dropped 59`. |
| `test_fold_bad_inputs` | `foldEvents()`, `(null, null)`, `("x", 5)`, `({}, {})` → `{rows: [], dropped: 0}` (both keys present, `rows` an array); `events` `[null, undefined, 5, "x", [], {}, {seq: "3"}, {seq: NaN}, one fixture row]` → just that row, `dropped 0`; the same junk in `rows` is skipped too; `RE.eventRow` output of all `events()` including the ignored `lease_acquired` (null) folds to 59 rows. |
| `test_fold_does_not_mutate` | `JSON.stringify` of `rows` and `events` (with overlap, out of order, over the cap) before and after are equal; the returned `rows` is not `===` either input; pushing to it leaves the inputs' lengths unchanged. |
| `test_filter_all` | `filterRows(fixtureRows(), "All")` → 59 rows, same order, a new array (`!==` input), entries the same objects. |
| `test_filter_phases` | `"Phases"` on the fixture rows → 42 rows, every `level` `phase` or `attempt`, input order kept; no run, story or subtask row. |
| `test_filter_failures` | synthetic copies of fixture rows with status `failed` (phase), `escalated` (run, story, subtask), `gate_failed`, `schema_invalid`, `harness_error` (attempts) plus `stopped`, `cancelled`, `canceled`, `pending`, `ok`, `done`, `started` → `"Failures"` keeps exactly the seven failure rows in input order; on the plain fixture rows → `[]`. |
| `test_filter_unknown` | `undefined`, `null`, `""`, `"phases"`, `"FAILURES"`, `"bogus"`, `5` → same rows as `"All"`. |
| `test_filter_bad_inputs` | `filterRows(null, "All")`, `(undefined)`, `("x", "Phases")`, `(5, "Failures")`, `({}, "All")` → `[]`; rows `[null, 5, "x", [], phase row]` → `"All"` and `"Phases"` give just the phase row; a row with status `"constructor"` or `"toString"` is not a failure. |
| `test_filter_does_not_mutate` | `JSON.stringify(rows)` before and after each of the three filters are equal; pushing to the result leaves `rows` unchanged. |

## Verification

- `bash tests/run.sh tst_run_events` while iterating (the filter still runs pytest).
- `bash tests/run.sh` green before the card is done: pytest including `tests/architecture`, then
  every QML test.

# runEvents.js `foldEvents` and `filterRows` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Append `foldEvents(rows, events, cap)` (dedupe by `seq`, sort ascending, cap 500 dropping the oldest) and `filterRows(rows, filter)` (`All` / `Phases` / `Failures`) to `core/domain/runEvents.js`.

**Architecture:** Two pure public functions appended after `durationText` in the existing `.pragma library` file, reusing its private `_isObject`, `_has` and `_isFiniteNumber`; two new private constants (`_DEFAULT_CAP`, `_FAILURES`) and one private predicate (`_isRow`) sit with them. No new import. Tests are QML domain tests in the existing `tests/core/domain/tst_run_events.qml`, built from `tests/fixtures/am/events.json` rows via `RE.eventRow`.

**Tech Stack:** QML JavaScript (ES5 style, `var`), Qt 6 `qmltestrunner` via `tests/run.sh`, pytest architecture tests.

**Spec:** `docs/superpowers/specs/1-2-runevents-js-de9d0a47.md` (prepended above this plan).

## Global Constraints

- `core/domain/runEvents.js` keeps exactly its current imports (`.pragma library`, `.import "runs.js" as Runs`); no new import (`tests/architecture/test_layers.py` must pass unchanged).
- No glyph characters in `core/domain` (`tests/architecture/test_icon_glyphs.py`).
- Reuse the file's private `_isObject`, `_has`, `_isFiniteNumber`; do not redefine them.
- Existing code in `runEvents.js` and existing tests in `tst_run_events.qml` are not changed; new code is appended.
- Pure and never throwing; never mutates `rows`, `events` or any entry; returned arrays are always new; entries are the same objects, not copies.
- Not a state reducer: a duplicate `seq` keeps one whole row (the last taken, `events` after `rows`); nothing is merged.
- Cap default `500`; `cap` not a finite number or negative → `500`; fractional → floored; oldest (lowest `seq`) dropped.
- Failure statuses: `failed`, `escalated`, `gate_failed`, `schema_invalid`, `harness_error`. Filter names `All`, `Phases`, `Failures`, case-sensitive; anything else → `All`.
- Comments state the contract only, no narrative. ES5 `var`; private helpers `_`-prefixed.
- Every hand-edited row in a test carries a `// synthetic:` comment.
- `bash tests/run.sh` must be green (pytest incl. `tests/architecture`, then every QML test) before the card is done.

## Review Focus

1. Junk entries (`null` rows from ignored events, objects without a numeric `seq`) must not count toward the cap or `dropped`, or the store would think earlier history was lost — pinned in Task 1 `test_fold_bad_inputs` (junk plus one row under cap 1 → that row, `dropped 0`).
2. Rows sort numerically by `seq`, not as strings (`9` before `10`, `99` before `100`) — pinned in Task 1 `test_fold_out_of_order` (seqs 2..60 cross 9/10) and `test_fold_cap_default_and_bad` (1..501 cross 99/100 and is checked element by element).
3. Folding an empty page into held rows already over the cap still trims them (a refetch with nothing new must not leave 600 rows) — pinned in Task 1 `test_fold_cap` (`foldEvents(all 59, [], 10)` → seqs 51..60, `dropped 49`).
4. `eventRow` gives `seq 0` to events without a seq; several such rows collapse to one (the last taken) at the front, never throwing — pinned in Task 1 `test_fold_incoming_wins`.
5. A `status` that is not a string but stringifies to a failure name (`["failed"]`) is not a failure, and inherited names (`"constructor"`, `"toString"`, `"__proto__"`, `"hasOwnProperty"`) never are — pinned in Task 2 `test_filter_bad_inputs`.

---

### Task 1: `foldEvents`

**Files:**
- Modify: `core/domain/runEvents.js` (append after `durationText`, the end of the file, currently line 109)
- Test: `tests/core/domain/tst_run_events.qml` (add helpers after `titles()`, add tests before the closing `}` of the `TestCase`)

**Interfaces:**
- Consumes: `RE.eventRow(event, titles, utcOffsetMinutes)` → row object `{seq, time, level, label, status, glyph, duration, detail, card, phase, attempt}` or `null` (card 1.1, already in the file). Test helpers already in the file: `events()` (fresh copy of `F.load("events.json").data.events`, 60 events, seq 1..60) and `titles()`.
- Produces: `foldEvents(rows, events, cap)` → `{ rows: row[], dropped: number }` (private `_DEFAULT_CAP`, `_isRow(v)` stay internal). Test helpers Task 2 relies on: `fixtureRows()` → array of 59 rows (seq 2..60, in that order: `fixtureRows()[i].seq === i + 2`), `copyRow(row)` → deep copy, `seqList(rows)` → `"2,3,..."` string, `seqRange(a, b)` → `"a,a+1,...,b"` string.

Fixture row indices used below (`fixtureRows()[i]`): `0` run (seq 2, `started`), `1` story (seq 3, `pending`), `2` subtask (seq 4, `pending`), `8` (seq 10), `17` phase (seq 19, `started`), `21` attempt (seq 23, `ok`).

- [ ] **Step 1: Add the test helpers**

In `tests/core/domain/tst_run_events.qml`, insert right after the closing `}` of `function titles() { ... }` (before `function test_duration_text()`):

```qml
  // Every non-null eventRow of events(): 59 rows, seq 2..60 in order.
  function fixtureRows() {
    var all = events()
    var out = []
    for (var i = 0; i < all.length; i++) {
      var r = RE.eventRow(all[i], titles(), 0)
      if (r !== null) out.push(r)
    }
    return out
  }

  // A deep copy of a row.
  function copyRow(row) { return JSON.parse(JSON.stringify(row)) }

  // The rows' seqs joined with ",".
  function seqList(rows) {
    var s = []
    for (var i = 0; i < rows.length; i++) s.push(rows[i].seq)
    return s.join(",")
  }

  // The integers a..b joined with ",".
  function seqRange(a, b) {
    var s = []
    for (var i = a; i <= b; i++) s.push(i)
    return s.join(",")
  }
```

- [ ] **Step 2: Write the failing `foldEvents` tests**

In the same file, insert before the final closing `}` of the `TestCase` (after `test_glyph_is_runs_mapping`):

```qml
  function test_fold_append() {
    var all = fixtureRows()
    compare(all.length, 59)
    var r = RE.foldEvents(all.slice(0, 30), all.slice(30), 500)
    compare(r.rows.length, 59)
    compare(seqList(r.rows), seqRange(2, 60))
    compare(r.dropped, 0)
    verify(r.rows[0] === all[0])
    verify(r.rows[58] === all[58])
    compare(seqList(RE.foldEvents([], fixtureRows(), 500).rows), seqRange(2, 60))
  }

  function test_fold_prepend() {
    var all = fixtureRows()
    var r = RE.foldEvents(all.slice(30), all.slice(0, 30), 500)
    compare(seqList(r.rows), seqRange(2, 60))
    compare(r.dropped, 0)
  }

  function test_fold_out_of_order() {
    var reversed = fixtureRows().reverse()
    compare(seqList(RE.foldEvents([], reversed, 500).rows), seqRange(2, 60))
    var all = fixtureRows()
    var shuffled = []
    for (var i = 0; i < all.length; i++) shuffled.push(all[(i * 7) % all.length])
    compare(seqList(RE.foldEvents([], shuffled, 500).rows), seqRange(2, 60))
    compare(seqList(RE.foldEvents(fixtureRows().reverse(), [], 500).rows), seqRange(2, 60))
    compare(seqList(RE.foldEvents(shuffled.slice(0, 30), shuffled.slice(30), 500).rows), seqRange(2, 60))
  }

  function test_fold_dedupe() {
    var all = fixtureRows()
    var r = RE.foldEvents(all.slice(0, 39), all.slice(28), 500)
    compare(all[38].seq, 40)
    compare(all[28].seq, 30)
    compare(r.rows.length, 59)
    compare(seqList(r.rows), seqRange(2, 60))
    compare(r.dropped, 0)
    var twice = RE.foldEvents(fixtureRows(), fixtureRows(), 500)
    compare(twice.rows.length, 59)
    compare(seqList(twice.rows), seqRange(2, 60))
    compare(twice.dropped, 0)
  }

  function test_fold_incoming_wins() {
    var base = fixtureRows()[8]
    compare(base.seq, 10)
    // synthetic: a held row and an incoming row with the same seq
    var held = copyRow(base)
    held.label = "old"
    var incoming = copyRow(base)
    incoming.label = "new"
    var r = RE.foldEvents([held], [incoming], 500)
    compare(r.rows.length, 1)
    verify(r.rows[0] === incoming)
    compare(r.rows[0].label, "new")
    compare(r.dropped, 0)
    // synthetic: two incoming rows with the same seq
    var first = copyRow(base)
    first.label = "first"
    var second = copyRow(base)
    second.label = "second"
    var e = RE.foldEvents([], [first, second], 500)
    compare(e.rows.length, 1)
    verify(e.rows[0] === second)
    // synthetic: two held rows with the same seq and no incoming row
    var h = RE.foldEvents([first, second], [], 500)
    compare(h.rows.length, 1)
    verify(h.rows[0] === second)
    // synthetic: two rows with seq 0 (eventRow's seq for an event without one)
    var zeroA = copyRow(base)
    zeroA.seq = 0
    var zeroB = copyRow(base)
    zeroB.seq = 0
    var z = RE.foldEvents(fixtureRows(), [zeroA, zeroB], 500)
    compare(z.rows.length, 60)
    verify(z.rows[0] === zeroB)
    compare(seqList(z.rows), "0," + seqRange(2, 60))
  }

  function test_fold_cap() {
    var all = fixtureRows()
    var ten = RE.foldEvents([], all, 10)
    compare(seqList(ten.rows), seqRange(51, 60))
    compare(ten.dropped, 49)
    var exact = RE.foldEvents(all.slice(0, 30), all.slice(30), 59)
    compare(exact.rows.length, 59)
    compare(exact.dropped, 0)
    var one = RE.foldEvents(all.slice(0, 30), all.slice(30), 58)
    compare(seqList(one.rows), seqRange(3, 60))
    compare(one.dropped, 1)
    var dup = RE.foldEvents(fixtureRows(), fixtureRows(), 50)
    compare(dup.rows.length, 50)
    compare(seqList(dup.rows), seqRange(11, 60))
    compare(dup.dropped, 9)
    var heldOnly = RE.foldEvents(fixtureRows(), [], 10)
    compare(seqList(heldOnly.rows), seqRange(51, 60))
    compare(heldOnly.dropped, 49)
  }

  function test_fold_cap_default_and_bad() {
    // synthetic: 501 copies of one fixture row with seq 1..501
    var proto = fixtureRows()[0]
    var big = []
    for (var i = 1; i <= 501; i++) {
      var row = copyRow(proto)
      row.seq = i
      big.push(row)
    }
    var caps = [undefined, null, "10", NaN, Infinity, -1]
    for (var c = 0; c < caps.length; c++) {
      var r = RE.foldEvents([], big, caps[c])
      compare(r.rows.length, 500, String(caps[c]))
      compare(r.dropped, 1, String(caps[c]))
      compare(seqList(r.rows), seqRange(2, 501), String(caps[c]))
    }
    var omitted = RE.foldEvents([], big)
    compare(omitted.rows.length, 500)
    compare(omitted.dropped, 1)
    compare(omitted.rows[0].seq, 2)
    compare(omitted.rows[499].seq, 501)
    var frac = RE.foldEvents([], fixtureRows(), 2.9)
    compare(seqList(frac.rows), "59,60")
    compare(frac.dropped, 57)
    var zero = RE.foldEvents([], fixtureRows(), 0)
    verify(Array.isArray(zero.rows))
    compare(zero.rows.length, 0)
    compare(zero.dropped, 59)
  }

  function test_fold_bad_inputs() {
    var empties = [RE.foldEvents(), RE.foldEvents(null, null), RE.foldEvents("x", 5), RE.foldEvents({}, {})]
    for (var i = 0; i < empties.length; i++) {
      compare(Object.keys(empties[i]).sort().join(","), "dropped,rows", "case " + i)
      verify(Array.isArray(empties[i].rows), "case " + i)
      compare(empties[i].rows.length, 0, "case " + i)
      compare(empties[i].dropped, 0, "case " + i)
    }
    var row = fixtureRows()[0]
    // synthetic: entries that are not rows
    var junk = [null, undefined, 5, "x", [], {}, { seq: "3" }, { seq: NaN }, { seq: Infinity }]
    var inEvents = RE.foldEvents([], junk.concat([row]), 500)
    compare(inEvents.rows.length, 1)
    verify(inEvents.rows[0] === row)
    compare(inEvents.dropped, 0)
    var inRows = RE.foldEvents(junk.concat([row]), [], 500)
    compare(inRows.rows.length, 1)
    verify(inRows.rows[0] === row)
    compare(inRows.dropped, 0)
    var capped = RE.foldEvents(junk, junk.concat([row]), 1)
    compare(capped.rows.length, 1)
    verify(capped.rows[0] === row)
    compare(capped.dropped, 0)
    var all = events()
    var mapped = []
    for (var j = 0; j < all.length; j++) mapped.push(RE.eventRow(all[j], titles(), 0))
    compare(mapped[0], null)
    var folded = RE.foldEvents([], mapped, 500)
    compare(folded.rows.length, 59)
    compare(seqList(folded.rows), seqRange(2, 60))
    compare(folded.dropped, 0)
  }

  function test_fold_does_not_mutate() {
    var all = fixtureRows()
    var rows = all.slice(20).reverse()
    var evs = all.slice(0, 40)
    var rowsBefore = JSON.stringify(rows)
    var evsBefore = JSON.stringify(evs)
    var r = RE.foldEvents(rows, evs, 10)
    compare(JSON.stringify(rows), rowsBefore)
    compare(JSON.stringify(evs), evsBefore)
    verify(r.rows !== rows)
    verify(r.rows !== evs)
    var rowsLength = rows.length
    var evsLength = evs.length
    r.rows.push({ seq: 999 })
    r.rows.sort(function (a, b) { return b.seq - a.seq })
    compare(rows.length, rowsLength)
    compare(evs.length, evsLength)
    compare(JSON.stringify(rows), rowsBefore)
    compare(JSON.stringify(evs), evsBefore)
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_events`
Expected: pytest passes; then `tst_run_events.qml` reports `FAIL!` on every `test_fold_*` with a `TypeError` naming `foldEvents` (not a function) (the script exits non-zero). The existing `test_*` functions still pass.

- [ ] **Step 4: Write the implementation**

Append to the end of `core/domain/runEvents.js` (after the closing `}` of `durationText`):

```js

var _DEFAULT_CAP = 500

function _isRow(v) { return _isObject(v) && _isFiniteNumber(v.seq) }

// Folds a page of rows (events) into the held rows: one row per seq, the last
// taken winning (rows first, then events, each in array order), ascending by
// seq, then the lowest seqs removed until at most cap remain. An entry counts
// only when it is a non-array object with a finite number seq; rows or events
// not an array read as []. cap: floored; 500 when missing, not a finite number
// or negative. Returns { rows, dropped }, dropped the count removed by the cap.
// Rows is a new array of the same entry objects; no input is modified.
function foldEvents(rows, events, cap) {
  var bySeq = {}
  var seqs = []
  var sources = [Array.isArray(rows) ? rows : [], Array.isArray(events) ? events : []]
  for (var s = 0; s < sources.length; s++) {
    for (var i = 0; i < sources[s].length; i++) {
      var row = sources[s][i]
      if (!_isRow(row)) continue
      var key = String(row.seq)
      if (!_has(bySeq, key)) seqs.push(row.seq)
      bySeq[key] = row
    }
  }
  seqs.sort(function (a, b) { return a - b })
  var limit = _isFiniteNumber(cap) && cap >= 0 ? Math.floor(cap) : _DEFAULT_CAP
  var dropped = Math.max(0, seqs.length - limit)
  var out = []
  for (var j = dropped; j < seqs.length; j++) out.push(bySeq[String(seqs[j])])
  return { rows: out, dropped: dropped }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_events`
Expected: pytest passes (including `tests/architecture`); `tst_run_events.qml` prints `Totals: N passed, 0 failed` with no `TypeError`/`ReferenceError` lines; exit status 0.

- [ ] **Step 6: Commit**

```bash
git add core/domain/runEvents.js tests/core/domain/tst_run_events.qml
git commit -m "feat(runEvents): foldEvents dedupes rows by seq, sorts and caps them"
```

---

### Task 2: `filterRows`

**Files:**
- Modify: `core/domain/runEvents.js` (append after `foldEvents`, the end of the file)
- Test: `tests/core/domain/tst_run_events.qml` (add tests before the closing `}` of the `TestCase`, after `test_fold_does_not_mutate`)

**Interfaces:**
- Consumes: from Task 1's test file: `fixtureRows()` (59 rows, `fixtureRows()[i].seq === i + 2`; 28 `phase` + 14 `attempt` rows; statuses only `started`, `pending`, `done`, `ok`), `copyRow(row)`, `seqList(rows)`. From the source file: private `_isObject(v)`, `_has(o, key)`.
- Produces: `filterRows(rows, filter)` → new array of the object entries of `rows` matching `filter` (`"All"`, `"Phases"`, `"Failures"`; anything else = `"All"`), in input order.

Fixture row indices used below (`fixtureRows()[i]`): `0` run, `1` story, `2` subtask, `17` phase, `21` attempt.

The spec names one new helper (`fixtureRows()`); this plan adds the small comparison helpers `copyRow`, `seqList`, `seqRange` (Task 1) and `withStatus` (Task 2) beside it so each assertion stays one line.

- [ ] **Step 1: Write the failing `filterRows` tests**

In `tests/core/domain/tst_run_events.qml`, insert before the final closing `}` of the `TestCase` (after `test_fold_does_not_mutate`):

```qml
  // synthetic: a copy of fixtureRows()[index] with its status edited.
  function withStatus(index, status) {
    var r = copyRow(fixtureRows()[index])
    r.status = status
    return r
  }

  function test_filter_all() {
    var rows = fixtureRows()
    var out = RE.filterRows(rows, "All")
    compare(out.length, 59)
    verify(out !== rows)
    for (var i = 0; i < rows.length; i++) verify(out[i] === rows[i], "row " + i)
  }

  function test_filter_phases() {
    var rows = fixtureRows()
    var out = RE.filterRows(rows, "Phases")
    compare(out.length, 42)
    var expected = []
    for (var i = 0; i < rows.length; i++)
      if (rows[i].level === "phase" || rows[i].level === "attempt") expected.push(rows[i])
    compare(expected.length, 42)
    for (var j = 0; j < out.length; j++) {
      verify(out[j] === expected[j], "row " + j)
      verify(out[j].level === "phase" || out[j].level === "attempt", "row " + j)
    }
  }

  function test_filter_failures() {
    // synthetic: fixture rows with failure statuses, interleaved with non-failures
    var failed = withStatus(17, "failed")
    var runEsc = withStatus(0, "escalated")
    var storyEsc = withStatus(1, "escalated")
    var subtaskEsc = withStatus(2, "escalated")
    var gate = withStatus(21, "gate_failed")
    var schema = withStatus(21, "schema_invalid")
    var harness = withStatus(21, "harness_error")
    var rows = [withStatus(0, "stopped"), failed, withStatus(2, "cancelled"), runEsc,
                withStatus(2, "canceled"), storyEsc, withStatus(1, "pending"), subtaskEsc,
                withStatus(21, "ok"), gate, withStatus(0, "done"), schema,
                withStatus(17, "started"), harness]
    var expected = [failed, runEsc, storyEsc, subtaskEsc, gate, schema, harness]
    var out = RE.filterRows(rows, "Failures")
    compare(out.length, 7)
    for (var i = 0; i < expected.length; i++) verify(out[i] === expected[i], "row " + i)
    compare(RE.filterRows(fixtureRows(), "Failures").length, 0)
  }

  function test_filter_unknown() {
    var rows = fixtureRows()
    var filters = [undefined, null, "", "phases", "FAILURES", "bogus", 5]
    for (var f = 0; f < filters.length; f++) {
      var out = RE.filterRows(rows, filters[f])
      compare(out.length, 59, String(filters[f]))
      for (var i = 0; i < rows.length; i++) verify(out[i] === rows[i], String(filters[f]) + " row " + i)
    }
    compare(RE.filterRows(rows).length, 59)
  }

  function test_filter_bad_inputs() {
    var notRows = [[null, "All"], [undefined, undefined], ["x", "Phases"], [5, "Failures"], [{}, "All"]]
    for (var i = 0; i < notRows.length; i++) {
      var out = RE.filterRows(notRows[i][0], notRows[i][1])
      verify(Array.isArray(out), "case " + i)
      compare(out.length, 0, "case " + i)
    }
    compare(RE.filterRows().length, 0)
    var phase = fixtureRows()[17]
    compare(phase.level, "phase")
    // synthetic: entries that are not rows
    var mixed = [null, 5, "x", [], phase]
    var all = RE.filterRows(mixed, "All")
    compare(all.length, 1)
    verify(all[0] === phase)
    var phases = RE.filterRows(mixed, "Phases")
    compare(phases.length, 1)
    verify(phases[0] === phase)
    compare(RE.filterRows(mixed, "Failures").length, 0)
    // synthetic: statuses naming inherited properties, and a non-string status
    var odd = ["constructor", "toString", "__proto__", "hasOwnProperty", ["failed"], null, 5]
    for (var j = 0; j < odd.length; j++)
      compare(RE.filterRows([withStatus(21, odd[j])], "Failures").length, 0, String(odd[j]))
  }

  function test_filter_does_not_mutate() {
    var rows = fixtureRows()
    // synthetic: one failure row among the fixture rows
    rows[21] = withStatus(21, "gate_failed")
    var before = JSON.stringify(rows)
    var filters = ["All", "Phases", "Failures"]
    for (var f = 0; f < filters.length; f++) {
      var out = RE.filterRows(rows, filters[f])
      compare(JSON.stringify(rows), before, filters[f])
      verify(out !== rows, filters[f])
      out.push({ seq: 999 })
      compare(rows.length, 59, filters[f])
      compare(JSON.stringify(rows), before, filters[f])
    }
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_events`
Expected: pytest passes; `tst_run_events.qml` reports `FAIL!` on every `test_filter_*` with a `TypeError` naming `filterRows` (not a function) (exit non-zero). Every `test_fold_*` and earlier test still passes.

- [ ] **Step 3: Write the implementation**

Append to the end of `core/domain/runEvents.js` (after the closing `}` of `foldEvents`):

```js

var _FAILURES = { failed: true, escalated: true, gate_failed: true, schema_invalid: true,
                  harness_error: true }

// The non-array object entries of rows matching filter, in input order, as a
// new array. "Phases": level phase or attempt. "Failures": status (a string)
// one of failed, escalated, gate_failed, schema_invalid, harness_error, at any
// level. "All" and any other filter: every object entry. [] when rows is not
// an array. No input is modified.
function filterRows(rows, filter) {
  if (!Array.isArray(rows)) return []
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (!_isObject(row)) continue
    if (filter === "Phases" && row.level !== "phase" && row.level !== "attempt") continue
    if (filter === "Failures" && !(typeof row.status === "string" && _has(_FAILURES, row.status))) continue
    out.push(row)
  }
  return out
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_events`
Expected: pytest passes; `tst_run_events.qml` prints `Totals: N passed, 0 failed` with no `TypeError`/`ReferenceError` lines; exit status 0.

- [ ] **Step 5: Run the whole suite**

Run: `bash tests/run.sh`
Expected: pytest passes (including `tests/architecture/test_layers.py` and `test_icon_glyphs.py`); every QML test file prints `Totals: ... 0 failed`; no `TypeError`/`ReferenceError` lines; exit status 0.

- [ ] **Step 6: Commit**

```bash
git add core/domain/runEvents.js tests/core/domain/tst_run_events.qml
git commit -m "feat(runEvents): filterRows keeps All, Phases or Failures rows"
```
<!-- task-pipeline: validated -->
