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
