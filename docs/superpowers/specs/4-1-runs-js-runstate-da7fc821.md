# 4.1 runs.js: runState and glyphStateOf read `canceled` as `cancelled` (card da7fc821)

Narrowed from `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
("the parent" below): Decision 8 (line 172), "Both spellings, both schemas"
(lines 286-294), the consumer table rows for `glyphStateOf` (line 102),
`runState` / `controls` (line 109), and the observed symptom (line 85). Parent
story 27d8a320, work breakdown item 4 (parent lines 329-330). Fixture rule:
parent lines 257-267.

This card is the `runs.js` half of item 4 only. `runs-snapshot.py`, `runs-watch.py`,
`RunStore.amSchema` / `amVersion` and the Runs footer are sibling cards.

## Starting point

- A later `am` migration respells the run status `canceled` (parent line 288).
  No captured fixture contains it; every capture spells `cancelled` or another
  status (parent line 38).
- `core/domain/runs.js` `runState` (lines 140-159) returns the status itself for
  `escalated`, `cancelled`, `done` (line 157). `canceled` falls through to
  `unknown` (parent line 85, 109).
- `glyphStateOf` (lines 538-552) maps `cancelled` to `cancelled` (line 549);
  `canceled` gives `""` (no glyph). Its one consumer is
  `ui/screens/RunDetailScreen.qml:87`, `:90`.
- `controls` (lines 749-775) and `newAlerts` (lines 839-862) read the state only
  through `runState`; the parent lists both as "fine as they are" (parent lines
  138-139). They need no edit; this card proves they follow.
- `normalizeRun` already copies am's `status` verbatim
  (`test_normalize_status_prefers_am_status`, `tests/core/domain/tst_runs.qml`
  line 51). No edit.
- `tests/core/domain/tst_runs.qml` line 1642 currently pins
  `["canceled", ""]` for `glyphStateOf`. That expectation flips: it is the
  deliberate behaviour change of this card.
- `canceled` in `core/domain/board.js` and `core/stores/BoardStore.qml` is a brd
  card status, unrelated. Untouched.

## Required behaviour

1. **runState.** For a run object whose `status` is `cancelled` or `canceled`,
   `runState` returns `"cancelled"`, whatever its `lease` (live, not live, null,
   absent). The returned name is always the plugin's state name `cancelled`
   (the `runGlyphs.js` key), never `canceled` (parent lines 291-292). Every
   other status maps exactly as today; in particular `Canceled`, `CANCELED`,
   ` canceled` and `cancel` stay `unknown` (exact, case-sensitive match).
2. **glyphStateOf.** `glyphStateOf("cancelled")` and `glyphStateOf("canceled")`
   both return `"cancelled"` (parent line 293). Every other input maps exactly as
   today; `Canceled` and ` canceled` still give `""`.
3. **normalizeRun keeps am's spelling.** A normalized run's `status` is
   `canceled` when am says `canceled` and `cancelled` when am says `cancelled`
   (parent line 294). No rewriting of the spelling anywhere in the normalized
   shape.
4. **controls follows.** For a normalized run in either spelling: pause
   disabled with `The run has finished`, resume disabled with
   `A cancelled run cannot be resumed`, cancel disabled with
   `The run is already cancelled`. Same strings as today for `cancelled`.
5. **newAlerts follows.** A run in either spelling raises no alert, whether it
   is absent from `prevRuns` or was running in it. Cancelled is neither
   escalated nor dead.
6. Both functions stay pure and never throw. Doc comments above `runState` and
   `glyphStateOf` state the two spellings as part of the contract; no narrative
   (no "am renamed…", no card or plan references).

## Error paths

- Non-string or garbage `status` (`undefined`, `null`, `5`, `"constructor"`,
  `"__proto__"`): unchanged results (`unknown` / `""`).
- A `canceled` run with a live lease is still `cancelled`, not `running`: only
  `started` consults the lease.

## Tests (all in `tests/core/domain/tst_runs.qml`, QML tier)

QML tier because `runs.js` is QML JavaScript imported by the plugin and every
existing test of it runs under `qmltestrunner` through `bash tests/run.sh`; no
other tier can import it.

Inputs come from `tests/fixtures/am/` through the existing `amRun(name)` helper
(fresh `F.load` copy per call). For each spelling the test builds
`raw = amRun("status-done.json")`, sets `raw.status.run.status = spelling`
(a labelled edit on a fresh copy, parent lines 265-267: comment
`// status-done.json copy, run.status set to <spelling>`), then
`run = Runs.normalizeRun(raw)`. Every `compare` message names the spelling.
`status-done.json` has `control.lease` null, so no Integrate reason interferes.

New tests:

1. `test_fixture_cancel_spellings_run_state` — for `cancelled` and `canceled`:
   `run.status === spelling` (behaviour 3) and `Runs.runState(run) === "cancelled"`
   (behaviour 1).
2. `test_fixture_cancel_spellings_controls` — for both spellings:
   `checkControls(Runs.controls(run), ctlFinished, ctlResumeCancelled,
   ctlCancelCancelled, spelling)` (behaviour 4).
3. `test_fixture_cancel_spellings_new_alerts` — for both spellings:
   `Runs.newAlerts([], [run]).length === 0` (absent from prev) and
   `Runs.newAlerts([prev], [run]).length === 0` where `prev` is a second
   normalized `status-done.json` copy whose `status` is then set to `started`
   and `lease` to `{pid: 1, host: "h", heartbeat_at: "", accepting: true,
   live: true}` on the normalized run (allowed past `normalizeRun`, parent
   lines 262-265), labelled `// synthetic: the same run while it was running`;
   its `runState` is asserted `running` first (behaviour 5).

Changed tests:

4. `test_glyph_state_of` (line 1636): `["canceled", ""]` becomes
   `["canceled", "cancelled"]`; add `["Canceled", ""]` and `[" canceled", ""]`
   (behaviour 2). These are function-argument strings, not am payloads; the
   existing case list already mixes such inputs.
5. `test_state_terminal_and_parked` (line 566): add `["canceled", "cancelled"]`
   to the table so the four lease variants are covered for the new spelling.
   This test builds normalized runs by hand, which the parent allows past
   `normalizeRun` (parent lines 262-265).
6. `test_state_unknown`: add `"Canceled"`, `"CANCELED"`, `" canceled"`,
   `"cancel"` to the unknown list (behaviour 1, exact match).

Red first: tests 1, 2, 4 and 5 fail on the current code in their `canceled`
cases (test 1 gives `unknown`; test 2 gives the unknown reasons; test 4 gives
`""`; test 5 gives `unknown`). Tests 3 and 6 and the `cancelled` cases pass
already; they pin that the follow-on behaviour and the exact match hold.

Verification: `bash tests/run.sh` green, including `tests/architecture`
(unaffected: no component or icon change).

## Out of scope

- `core/backend/runs/runs-snapshot.py` `TERMINAL` (parent line 128, 292), `runs-watch.py`
  hello schemas, `RunStore.amSchema` / `amVersion`, the Runs footer: sibling
  cards of this story.
- `RunBadge`, rollups, `runGlyphs.js`: follow from `runState` / `glyphStateOf`
  (parent line 293), no edit.
- brd card `canceled` in `board.js` / `BoardStore.qml`.
- Adding a fixture with a `canceled` status: none was captured; the in-test
  edit above stands for it.
- Docs (`docs/architecture.md`, README): work breakdown item 5.
