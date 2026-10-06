# 4.1 runs.js reads `canceled` as `cancelled`: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `runState` and `glyphStateOf` in `core/domain/runs.js` treat am's `canceled` run status exactly like `cancelled`, returning the plugin state name `"cancelled"`, while `normalizeRun` keeps am's spelling.

**Architecture:** Two one-line edits in one pure QML-JavaScript file (`core/domain/runs.js`): `runState` adds an exact `canceled` match that returns `"cancelled"`, and `glyphStateOf` does the same. Their doc comments state both spellings. Every consumer (`controls`, `newAlerts`, `searchRuns`, `runFilterCounts`, `cardRunState`, `RunBadge`, `RunDetailScreen`) reads state only through these two functions, so the tests show they follow and none of them is edited.

**Tech Stack:** QML JavaScript (`.pragma library`), Qt 6 `QtTest` `TestCase` run by `qmltestrunner` through `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/4-1-runs-js-runstate-da7fc821.md`. The full text is copied below.

## Spec (verbatim)

> # 4.1 runs.js: runState and glyphStateOf read `canceled` as `cancelled` (card da7fc821)
>
> Narrowed from `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
> ("the parent" below): Decision 8 (line 172), "Both spellings, both schemas"
> (lines 286-294), the consumer table rows for `glyphStateOf` (line 102),
> `runState` / `controls` (line 109), and the observed symptom (line 85). Parent
> story 27d8a320, work breakdown item 4 (parent lines 329-330). Fixture rule:
> parent lines 257-267.
>
> This card is the `runs.js` half of item 4 only. `runs-snapshot.py`, `runs-watch.py`,
> `RunStore.amSchema` / `amVersion` and the Runs footer are sibling cards.
>
> ## Starting point
>
> - A later `am` migration respells the run status `canceled` (parent line 288).
>   No captured fixture contains it; every capture spells `cancelled` or another
>   status (parent line 38).
> - `core/domain/runs.js` `runState` (lines 140-159) returns the status itself for
>   `escalated`, `cancelled`, `done` (line 157). `canceled` falls through to
>   `unknown` (parent line 85, 109).
> - `glyphStateOf` (lines 538-552) maps `cancelled` to `cancelled` (line 549);
>   `canceled` gives `""` (no glyph). Its one consumer is
>   `ui/screens/RunDetailScreen.qml:87`, `:90`.
> - `controls` (lines 749-775) and `newAlerts` (lines 839-862) read the state only
>   through `runState`; the parent lists both as "fine as they are" (parent lines
>   138-139). They need no edit; this card proves they follow.
> - `normalizeRun` already copies am's `status` verbatim
>   (`test_normalize_status_prefers_am_status`, `tests/core/domain/tst_runs.qml`
>   line 51). No edit.
> - `tests/core/domain/tst_runs.qml` line 1642 currently pins
>   `["canceled", ""]` for `glyphStateOf`. That expectation flips: it is the
>   deliberate behaviour change of this card.
> - `canceled` in `core/domain/board.js` and `core/stores/BoardStore.qml` is a brd
>   card status, unrelated. Untouched.
>
> ## Required behaviour
>
> 1. **runState.** For a run object whose `status` is `cancelled` or `canceled`,
>    `runState` returns `"cancelled"`, whatever its `lease` (live, not live, null,
>    absent). The returned name is always the plugin's state name `cancelled`
>    (the `runGlyphs.js` key), never `canceled` (parent lines 291-292). Every
>    other status maps exactly as today; in particular `Canceled`, `CANCELED`,
>    ` canceled` and `cancel` stay `unknown` (exact, case-sensitive match).
> 2. **glyphStateOf.** `glyphStateOf("cancelled")` and `glyphStateOf("canceled")`
>    both return `"cancelled"` (parent line 293). Every other input maps exactly as
>    today; `Canceled` and ` canceled` still give `""`.
> 3. **normalizeRun keeps am's spelling.** A normalized run's `status` is
>    `canceled` when am says `canceled` and `cancelled` when am says `cancelled`
>    (parent line 294). No rewriting of the spelling anywhere in the normalized
>    shape.
> 4. **controls follows.** For a normalized run in either spelling: pause
>    disabled with `The run has finished`, resume disabled with
>    `A cancelled run cannot be resumed`, cancel disabled with
>    `The run is already cancelled`. Same strings as today for `cancelled`.
> 5. **newAlerts follows.** A run in either spelling raises no alert, whether it
>    is absent from `prevRuns` or was running in it. Cancelled is neither
>    escalated nor dead.
> 6. Both functions stay pure and never throw. Doc comments above `runState` and
>    `glyphStateOf` state the two spellings as part of the contract; no narrative
>    (no "am renamed…", no card or plan references).
>
> ## Error paths
>
> - Non-string or garbage `status` (`undefined`, `null`, `5`, `"constructor"`,
>   `"__proto__"`): unchanged results (`unknown` / `""`).
> - A `canceled` run with a live lease is still `cancelled`, not `running`: only
>   `started` consults the lease.
>
> ## Tests (all in `tests/core/domain/tst_runs.qml`, QML tier)
>
> QML tier because `runs.js` is QML JavaScript imported by the plugin and every
> existing test of it runs under `qmltestrunner` through `bash tests/run.sh`; no
> other tier can import it.
>
> Inputs come from `tests/fixtures/am/` through the existing `amRun(name)` helper
> (fresh `F.load` copy per call). For each spelling the test builds
> `raw = amRun("status-done.json")`, sets `raw.status.run.status = spelling`
> (a labelled edit on a fresh copy, parent lines 265-267: comment
> `// status-done.json copy, run.status set to <spelling>`), then
> `run = Runs.normalizeRun(raw)`. Every `compare` message names the spelling.
> `status-done.json` has `control.lease` null, so no Integrate reason interferes.
>
> New tests:
>
> 1. `test_fixture_cancel_spellings_run_state` — for `cancelled` and `canceled`:
>    `run.status === spelling` (behaviour 3) and `Runs.runState(run) === "cancelled"`
>    (behaviour 1).
> 2. `test_fixture_cancel_spellings_controls` — for both spellings:
>    `checkControls(Runs.controls(run), ctlFinished, ctlResumeCancelled,
>    ctlCancelCancelled, spelling)` (behaviour 4).
> 3. `test_fixture_cancel_spellings_new_alerts` — for both spellings:
>    `Runs.newAlerts([], [run]).length === 0` (absent from prev) and
>    `Runs.newAlerts([prev], [run]).length === 0` where `prev` is a second
>    normalized `status-done.json` copy whose `status` is then set to `started`
>    and `lease` to `{pid: 1, host: "h", heartbeat_at: "", accepting: true,
>    live: true}` on the normalized run (allowed past `normalizeRun`, parent
>    lines 262-265), labelled `// synthetic: the same run while it was running`;
>    its `runState` is asserted `running` first (behaviour 5).
>
> Changed tests:
>
> 4. `test_glyph_state_of` (line 1636): `["canceled", ""]` becomes
>    `["canceled", "cancelled"]`; add `["Canceled", ""]` and `[" canceled", ""]`
>    (behaviour 2). These are function-argument strings, not am payloads; the
>    existing case list already mixes such inputs.
> 5. `test_state_terminal_and_parked` (line 566): add `["canceled", "cancelled"]`
>    to the table so the four lease variants are covered for the new spelling.
>    This test builds normalized runs by hand, which the parent allows past
>    `normalizeRun` (parent lines 262-265).
> 6. `test_state_unknown`: add `"Canceled"`, `"CANCELED"`, `" canceled"`,
>    `"cancel"` to the unknown list (behaviour 1, exact match).
>
> Red first: tests 1, 2, 4 and 5 fail on the current code in their `canceled`
> cases (test 1 gives `unknown`; test 2 gives the unknown reasons; test 4 gives
> `""`; test 5 gives `unknown`). Tests 3 and 6 and the `cancelled` cases pass
> already; they pin that the follow-on behaviour and the exact match hold.
>
> Verification: `bash tests/run.sh` green, including `tests/architecture`
> (unaffected: no component or icon change).
>
> ## Out of scope
>
> - `core/backend/runs/runs-snapshot.py` `TERMINAL` (parent line 128, 292), `runs-watch.py`
>   hello schemas, `RunStore.amSchema` / `amVersion`, the Runs footer: sibling
>   cards of this story.
> - `RunBadge`, rollups, `runGlyphs.js`: follow from `runState` / `glyphStateOf`
>   (parent line 293), no edit.
> - brd card `canceled` in `board.js` / `BoardStore.qml`.
> - Adding a fixture with a `canceled` status: none was captured; the in-test
>   edit above stands for it.
> - Docs (`docs/architecture.md`, README): work breakdown item 5.

## Global Constraints

- Match is exact and case-sensitive: only `cancelled` and `canceled` are cancelled; `Canceled`, `CANCELED`, ` canceled`, `cancel` stay `unknown` / `""`.
- The returned state name is always `"cancelled"` (the `ui/components/runGlyphs.js` key), never `"canceled"`.
- `normalizeRun` is not edited: a normalized run's `status` keeps am's spelling.
- `runState` and `glyphStateOf` stay pure and never throw.
- Doc comments above `runState` and `glyphStateOf` state the two spellings as part of the contract, with no narrative (no "am renamed…", no card or plan references).
- `controls`, `newAlerts`, `RunBadge`, rollups, `runGlyphs.js`, `core/domain/board.js`, `core/stores/BoardStore.qml`, `core/backend/runs/*.py`, `RunStore`, the Runs footer and docs are not edited.
- No new fixture file: a `canceled` am run is a labelled edit on a fresh `amRun("status-done.json")` copy, commented `// status-done.json copy, run.status set to <spelling>`.
- All tests go in `tests/core/domain/tst_runs.qml` (QML tier). Every `compare` message names the spelling.
- Verification: `bash tests/run.sh` green, `tests/architecture` included.

## Review Focus

1. A `canceled` run with a live lease and `accepting: false` (Integrate) must still get the finished controls (pause/resume/cancel disabled with the cancelled reasons), not the Integrate reason. Pinned in Task 1 by running `test_controls_finished_states` over both spellings.
2. Typing `cancelled` in the Runs search must find a `canceled` run (`searchRuns` matches on `runState`), and typing `unknown` must not. Pinned in Task 1 by `test_fixture_cancel_spellings_filters_and_search`.
3. A `canceled` run must not be counted in the Attention, Live or Parked chips, only in All. Pinned in Task 1 by the same test.
4. Statuses that are prototype keys or not strings (`"constructor"`, `"__proto__"`, `5`, `null`) must stay `unknown` in `runState`. Pinned in Task 1 by extending `test_state_unknown`.
5. A newer `canceled` run must never outrank an older running run for a card's run mark. Alone, it leaves the card with state `none`, dimmed. Pinned in Task 1 by `test_card_run_state_cancel_spellings`.

---

## How to run the tests

There is one command: `bash tests/run.sh core/domain/tst_runs`. It runs the whole pytest suite first (about 80 s, 838 passed), then only `tests/core/domain/tst_runs.qml` under `qmltestrunner`. The baseline before this plan is `Totals: 142 passed, 0 failed`. A failing QML test prints a line like
`FAIL!  : qmltestrunner::DomainRuns::test_name() '<message>' returned FALSE. ...` or
`FAIL!  : qmltestrunner::DomainRuns::test_name() Compared values are not the same`, followed by `Actual` / `Expected` and a `Loc:` line.
A QML `TestCase` function stops at its first failing `compare`. So each test below reports only its first failure.

## File Structure

- Modify `core/domain/runs.js`:
  - `runState` (doc comment lines 144-148, body line 157). Task 1.
  - `glyphStateOf` (doc comment lines 539-542, body line 549). Task 2.
- Modify `tests/core/domain/tst_runs.qml`:
  - Task 1 edits `test_state_terminal_and_parked` (line 566), `test_state_unknown` (line 583) and `test_controls_finished_states` (line 1932). It adds helpers and new tests after `test_state_unknown`, after `test_controls_finished_states`, and after `test_fixture_new_alerts_escalation_reason`.
  - Task 2 edits `test_glyph_state_of` (line 1636).

---

### Task 1: `runState` reads `canceled` as `cancelled`, and its consumers follow

**Files:**
- Modify: `core/domain/runs.js:144-158`
- Test: `tests/core/domain/tst_runs.qml` (lines 566-595, 1932-1944, and new tests after lines 595, 1944 and 1172)

**Interfaces:**
- Consumes: the existing test helpers in `tst_runs.qml`:
  - `amRun(name)`: a fresh `{row, status}`.
  - `mkRun(id, status, live, opts)`: a hand-built normalized run. `live === null` means no lease. Its `milestone_id` defaults to `"m1"`.
  - `ctlRun(status, live, accepting)`.
  - `checkControls(c, pause, resume, cancel, label)`.
  - The reason properties `ctlFinished`, `ctlResumeCancelled`, `ctlCancelCancelled`.
- Consumes from `runs.js`: `normalizeRun(raw)`, `runState(run)`, `controls(run)`, `newAlerts(prevRuns, nextRuns)`, `runFilterCounts(runs)` → `{attention, live, parked, all}`, `searchRuns(runs, q)`, `cardRunState(runs, cardId)` → `{state, runId, dimmed, phase, attempt}`.
- Produces (test helpers, used only inside this task):
  - `cancelSpellings()` → `["cancelled", "canceled"]`.
  - `cancelledRun(spelling)` → the normalized `status-done.json` run with `status === spelling`.
- Produces (behaviour): `runState({status: "canceled", ...})` returns `"cancelled"` for any lease.

- [ ] **Step 1: Add `canceled` to the terminal-state table**

In `tests/core/domain/tst_runs.qml`, in `test_state_terminal_and_parked`, replace:

```qml
      ["cancelled", "cancelled"],
      ["done", "done"]
```

with:

```qml
      ["cancelled", "cancelled"],
      ["canceled", "cancelled"],
      ["done", "done"]
```

- [ ] **Step 2: Extend the unknown list with case and spacing variants and with prototype-key and non-string statuses**

In `test_state_unknown`, replace:

```qml
    var statuses = ["weird", "", "stale", "STARTED", "Done", "running", "dead"]
```

with:

```qml
    var statuses = ["weird", "", "stale", "STARTED", "Done", "running", "dead",
                    "Canceled", "CANCELED", " canceled", "cancel", "constructor", "__proto__", 5, null]
```

(The loop's label `"status " + statuses[i]` already handles `5` and `null`.)

- [ ] **Step 3: Add the spelling helpers and the fixture tests for `runState`, chips, search and card mapping**

Right after the closing `  }` of `test_state_unknown`, the function that ends with:

```qml
    compare(Runs.runState(Runs.normalizeRun(undefined)), "unknown", "normalised garbage")
  }
```

and before `  // ---- 1.2: card mapping ---`, insert:

```qml

  // The two spellings am gives a cancelled run.
  function cancelSpellings() { return ["cancelled", "canceled"] }

  // The status-done.json run, normalized, with am's run status set to spelling.
  // Its control.lease is null, so no Integrate reason interferes.
  function cancelledRun(spelling) {
    // status-done.json copy, run.status set to spelling (cancelled or canceled)
    var raw = amRun("status-done.json")
    raw.status.run.status = spelling
    return Runs.normalizeRun(raw)
  }

  function test_fixture_cancel_spellings_run_state() {
    var spellings = cancelSpellings()
    for (var i = 0; i < spellings.length; i++) {
      var run = cancelledRun(spellings[i])
      compare(run.status, spellings[i], spellings[i] + ": normalizeRun keeps am's spelling")
      compare(Runs.runState(run), "cancelled", spellings[i] + ": runState")
    }
  }

  // A cancelled run in either spelling is found by its state name and sits in
  // no chip but `all`.
  function test_fixture_cancel_spellings_filters_and_search() {
    var spellings = cancelSpellings()
    for (var i = 0; i < spellings.length; i++) {
      var run = cancelledRun(spellings[i])
      var counts = Runs.runFilterCounts([run])
      compare([counts.attention, counts.live, counts.parked, counts.all].join(","), "0,0,0,1",
              spellings[i] + ": chip counts")
      compare(Runs.searchRuns([run], "cancelled").length, 1, spellings[i] + ": found by its state name")
      compare(Runs.searchRuns([run], "unknown").length, 0, spellings[i] + ": not unknown")
    }
  }

  // A newer cancelled run, in either spelling, never outranks an older running
  // run for a card; alone, it leaves the card with no run state, dimmed.
  function test_card_run_state_cancel_spellings() {
    var spellings = cancelSpellings()
    for (var i = 0; i < spellings.length; i++) {
      var cancelled = mkRun("rx", spellings[i], null, { started_at: "2026-10-05 10:00:00+00:00" })
      var running = mkRun("rr", "started", true, { started_at: "2026-10-04 10:00:00+00:00" })
      var both = Runs.cardRunState([cancelled, running], "m1")
      compare(both.state + "/" + both.runId + "/" + both.dimmed, "running/rr/false",
              spellings[i] + ": beside an older running run")
      var alone = Runs.cardRunState([cancelled], "m1")
      compare(alone.state + "/" + alone.runId + "/" + alone.dimmed, "none/rx/true", spellings[i] + ": alone")
    }
  }
```

(The search haystack is the run id `20261004T204141Z-cb11063d`, the title `…cb11063d`, the empty current phase and the state name. Only the state name can match `cancelled` or `unknown`.)

- [ ] **Step 4: Run the finished-state controls over both spellings**

In `test_controls_finished_states`, replace:

```qml
      compare(Runs.runState(ctlRun("cancelled", live, accepting)), "cancelled", "fixture " + label)
      checkControls(Runs.controls(ctlRun("cancelled", live, accepting)),
                    ctlFinished, ctlResumeCancelled, ctlCancelCancelled, "cancelled, " + label)
```

with:

```qml
      var cancels = ["cancelled", "canceled"]
      for (var j = 0; j < cancels.length; j++) {
        compare(Runs.runState(ctlRun(cancels[j], live, accepting)), "cancelled", cancels[j] + " fixture " + label)
        checkControls(Runs.controls(ctlRun(cancels[j], live, accepting)),
                      ctlFinished, ctlResumeCancelled, ctlCancelCancelled, cancels[j] + ", " + label)
      }
```

- [ ] **Step 5: Add the fixture controls test**

Directly after the closing `  }` of `test_controls_finished_states`, before `  function test_controls_unknown_and_garbage() {`, insert:

```qml

  function test_fixture_cancel_spellings_controls() {
    var spellings = cancelSpellings()
    for (var i = 0; i < spellings.length; i++) {
      checkControls(Runs.controls(cancelledRun(spellings[i])), ctlFinished, ctlResumeCancelled, ctlCancelCancelled,
                    spellings[i])
    }
  }
```

- [ ] **Step 6: Add the fixture alerts test**

After the closing `  }` of `test_fixture_new_alerts_escalation_reason`, before the line `  // ---- 1.2: error text ---`, insert:

```qml

  // Cancelled, in either spelling, is neither escalated nor dead: no alert,
  // whether the run is new or was running one snapshot earlier.
  function test_fixture_cancel_spellings_new_alerts() {
    var spellings = cancelSpellings()
    for (var i = 0; i < spellings.length; i++) {
      var run = cancelledRun(spellings[i])
      compare(Runs.newAlerts([], [run]).length, 0, spellings[i] + ": absent from prevRuns")

      // synthetic: the same run while it was running
      var prev = Runs.normalizeRun(amRun("status-done.json"))
      prev.status = "started"
      prev.lease = { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: true }
      compare(Runs.runState(prev), "running", spellings[i] + ": prev is running")
      compare(prev.id, run.id, spellings[i] + ": prev is the same run")
      compare(Runs.newAlerts([prev], [run]).length, 0, spellings[i] + ": was running")
    }
  }
```

- [ ] **Step 7: Run the tests to verify they fail**

Run: `bash tests/run.sh core/domain/tst_runs`
Expected: pytest passes. Then `Totals: 142 passed, 5 failed`. The five failing functions, all on their `canceled` case:
- `test_state_terminal_and_parked`: `canceled live lease`, Actual `unknown`, Expected `cancelled`.
- `test_fixture_cancel_spellings_run_state`: `canceled: runState`, Actual `unknown`.
- `test_fixture_cancel_spellings_filters_and_search`: `canceled: found by its state name`, Actual `0`, Expected `1`.
- `test_controls_finished_states`: `canceled fixture accepting`, Actual `unknown`.
- `test_fixture_cancel_spellings_controls`: `canceled pause reason`, Actual `The run's state is unknown`.

`test_state_unknown`, `test_card_run_state_cancel_spellings` and `test_fixture_cancel_spellings_new_alerts` already pass. They pin that the exact match and the follow-on behaviour hold.

- [ ] **Step 8: Write the minimal implementation**

In `core/domain/runs.js`, replace the doc comment and body of `runState`:

```js
// The one state shown for a normalised run. The lease matters only while the
// run says `started`: a started run whose lease is missing or not live is
// dead. Anything else -- an unknown or empty status, or no run at all -- is
// `unknown`, which is neither running nor finished. `stale` is a card state,
// never a run state.
function runState(run) {
  if (run === null || typeof run !== "object") return "unknown"
  var status = run.status
  if (status === "started") {
    var lease = run.lease
    return lease !== null && typeof lease === "object" && lease.live === true ? "running" : "dead"
  }
  if (status === "stopped") return "parked"
  if (status === "escalated" || status === "cancelled" || status === "done") return status
  return "unknown"
}
```

with:

```js
// The one state shown for a normalised run. The lease matters only while the
// run says `started`: a started run whose lease is missing or not live is
// dead. Both `cancelled` and `canceled` are `cancelled`, whatever the lease.
// Anything else -- an unknown or empty status, or no run at all -- is
// `unknown`, which is neither running nor finished. `stale` is a card state,
// never a run state.
function runState(run) {
  if (run === null || typeof run !== "object") return "unknown"
  var status = run.status
  if (status === "started") {
    var lease = run.lease
    return lease !== null && typeof lease === "object" && lease.live === true ? "running" : "dead"
  }
  if (status === "stopped") return "parked"
  if (status === "cancelled" || status === "canceled") return "cancelled"
  if (status === "escalated" || status === "done") return status
  return "unknown"
}
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `bash tests/run.sh core/domain/tst_runs`
Expected: pytest passes. Then `Totals: 147 passed, 0 failed, 0 skipped, 0 blacklisted`.

- [ ] **Step 10: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): runState reads canceled as cancelled"
```

---

### Task 2: `glyphStateOf` draws `canceled` as `cancelled`

**Files:**
- Modify: `core/domain/runs.js:539-552`
- Test: `tests/core/domain/tst_runs.qml` (`test_glyph_state_of`, line 1636 before Task 1, about 70 lines later after Task 1's inserts)

**Interfaces:**
- Consumes: `Runs.glyphStateOf(status)` → a `runGlyphs.js` key or `""`.
- Produces: `glyphStateOf("canceled") === "cancelled"`. Its one consumer, `ui/screens/RunDetailScreen.qml:87`, `:90`, needs no edit.

- [ ] **Step 1: Flip the `canceled` expectation and add the variants**

In `tests/core/domain/tst_runs.qml`, in `test_glyph_state_of`, replace:

```qml
                 ["OK", ""], [" ok", ""], ["Gate_Failed", ""], ["canceled", ""], ["__proto__", ""]]
```

with:

```qml
                 ["OK", ""], [" ok", ""], ["Gate_Failed", ""], ["canceled", "cancelled"], ["Canceled", ""],
                 [" canceled", ""], ["__proto__", ""]]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/run.sh core/domain/tst_runs`
Expected: `Totals: 146 passed, 1 failed`. The failure is `test_glyph_state_of` with message `canceled`, Actual `""` (shown as empty), Expected `cancelled`.

- [ ] **Step 3: Write the minimal implementation**

In `core/domain/runs.js`, replace:

```js
// The run-state name (a runGlyphs.js key) an am story, subtask, phase, attempt
// or row status is drawn with: started is running; failed and the attempt
// failures gate_failed, schema_invalid, harness_error are dead; the attempt
// outcome ok is done. "" for anything else, which shows no glyph.
function glyphStateOf(status) {
  if (status === "started" || status === "running") return "running"
  if (status === "stopped" || status === "parked") return "parked"
  if (status === "escalated") return "escalated"
  if (status === "failed" || status === "dead" || status === "gate_failed" ||
      status === "schema_invalid" || status === "harness_error") return "dead"
  if (status === "cancelled") return "cancelled"
```

with:

```js
// The run-state name (a runGlyphs.js key) an am story, subtask, phase, attempt
// or row status is drawn with: started is running; failed and the attempt
// failures gate_failed, schema_invalid, harness_error are dead; both cancelled
// and canceled are cancelled; the attempt outcome ok is done. "" for anything
// else, which shows no glyph.
function glyphStateOf(status) {
  if (status === "started" || status === "running") return "running"
  if (status === "stopped" || status === "parked") return "parked"
  if (status === "escalated") return "escalated"
  if (status === "failed" || status === "dead" || status === "gate_failed" ||
      status === "schema_invalid" || status === "harness_error") return "dead"
  if (status === "cancelled" || status === "canceled") return "cancelled"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/run.sh core/domain/tst_runs`
Expected: `Totals: 147 passed, 0 failed, 0 skipped, 0 blacklisted`.

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: exit status 0. pytest shows `838 passed`. Every `== tests/...` QML file, `tests/architecture` included, prints `Totals: N passed, 0 failed`, and no `TypeError` / `ReferenceError` lines appear.

- [ ] **Step 6: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): glyphStateOf draws canceled as cancelled"
```
<!-- task-pipeline: validated -->
