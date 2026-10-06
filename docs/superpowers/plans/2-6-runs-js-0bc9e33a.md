# 2.6 runs.js: glyphStateOf draws am's attempt outcomes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `glyphStateOf` maps am's attempt outcome `ok` to `done` and `gate_failed`, `schema_invalid`, `harness_error` to `dead`, so a real am attempt row in Run detail shows a glyph and a failed attempt is drawn urgent.

**Architecture:** One function changes in `core/domain/runs.js`: `glyphStateOf` (lines 536-548 today) gains `ok` on its `done` line and the three failure outcomes on its `dead` line, and its contract comment (lines 536-538) is restated. Matching stays `===` on the exact string, so case/whitespace variants and `Object.prototype` names never match. No QML change: `RunDetailScreen.glyphOf` / `isUrgent` already consume `glyphStateOf`. Tests: the existing table test and a new real-data test in `tests/core/domain/tst_runs.qml`, and a new real-data screen test in `tests/ui/screens/tst_run_detail_screen.qml`.

**Tech Stack:** Qt 6 QML / V4 JavaScript (`.pragma library`), QtTest via `qmltestrunner`, driven by `bash tests/run.sh [path-substring]` (pytest runs first, then every `tst_*.qml` whose path contains the substring; `core/domain/tst_runs` matches only `tests/core/domain/tst_runs.qml`, `tst_run_detail_screen` only `tests/ui/screens/tst_run_detail_screen.qml`).

**Spec:** `docs/superpowers/specs/2-6-runs-js-0bc9e33a.md` (prepended below, headings demoted one level; executors read both).

## Global Constraints

- Code: only `glyphStateOf` and the comment above it change in `core/domain/runs.js`. `normalizeRun`, `runTree`, `escalationReason`, `logTail`, every other function: **not edited**.
- Mapping, exact strings, case-sensitive, no trimming: `started`, `running` → `running`; `stopped`, `parked` → `parked`; `escalated` → `escalated`; `failed`, `dead`, `gate_failed`, `schema_invalid`, `harness_error` → `dead`; `cancelled` → `cancelled`; `done`, `ok` → `done`; anything else (`pending`, `""`, `"OK"`, `" ok"`, `"canceled"`, `undefined`, `null`, a number, `"constructor"`, `"__proto__"`) → `""`.
- `canceled` stays `""` (work breakdown item 4, not this card).
- Never throws. `core/domain/runs.js` stays `.pragma library` with exactly `.import "board.js" as Board`; `docs/architecture.md` layering holds and `tests/architecture` passes.
- Not changed: `ui/components/runGlyphs.js` state names; `PhaseTimeline`, `RunBadge`, `RunRollupBar`; `ui/screens/RunDetailScreen.qml`; screen layouts; the normalized shape; the fixtures; docs.
- Tests asserting behaviour on real data normalize a capture via `amRun(name)` (`tests/helpers/amFixtures.js` `F.load`, fresh parse per call; needs `QML_XHR_ALLOW_FILE_READ=1`, set by `tests/run.sh`). A hand-written input for a value no capture contains carries a `// synthetic:` comment.
- Docstrings and comments state the contract only, no narrative.
- No QML test function name may end in `_data` (QtTest treats it as a data provider).
- `bash tests/run.sh` green at the end; tests first (red before green). Never `git stash`.

## Review Focus

1. An attempt status differing only by case or whitespace (`"OK"`, `" ok"`, `"Gate_Failed"`): expected `""` (no glyph), not `done`/`dead`. Pinned in Task 1 Step 1 by the extended `test_glyph_state_of` table.
2. `canceled` (one `l`): expected still `""` in this card; mapping it is item 4's job. Pinned in Task 1 Step 1 (`["canceled", ""]`).
3. Prototype-named strings (`"constructor"`, `"__proto__"`): expected `""`, even if someone later rewrites the function as a lookup object. Pinned in Task 1 Step 1.
4. A future am outcome appearing in a capture (e.g. a new `*_failed`): expected the real-data test to fail loudly, naming the status, rather than silently drawing no glyph. Pinned in Task 1 Step 2 (`test_fixture_glyph_state_of_attempt_outcomes` fails on any collected status missing from its table).
5. Story/subtask rows with `done`/`failed` and `started` attempts: expected to render exactly as before. Pinned by the existing screen tests (`test_the_timeline_and_attempts_show_under_the_selected_subtask_only`, `test_failed_and_escalated_tree_rows_are_drawn_urgent`) staying green unchanged in Task 1 Step 8, plus the `ok` row assertion (foreground, not urgent) in Task 1 Step 3.

---

## Spec (prepended; headings demoted one level)

## 2.6 runs.js: glyphStateOf draws am's attempt outcomes — design

Card `0bc9e33a`, a subtask of story `21f9cd5a` ("Normalize real am status"),
blocked by `aedf81f2` (2.5, `escalationReason`, committed at `17b0d8a` /
`6ba1ddf`). Parent spec: `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
(below: **parent**). Work breakdown item 2 (parent L324-326) ends with
"`escalationReason`, `glyphStateOf`": this subtask is `glyphStateOf` only
(`core/domain/runs.js:536-548`).

### Goal

In Run detail, an attempt row of a real am run shows a glyph, and a failed
attempt is drawn urgent. Real am records attempt outcomes as `started, ok,
schema_invalid, gate_failed, harness_error` (parent L38-39), and an attempt
row's `state` is that outcome (parent L33-36). Today `glyphStateOf` knows none
of `ok`, `gate_failed`, `schema_invalid`, `harness_error` and returns `""`
(parent L85, L102), so `RunDetailScreen` draws such an attempt with no glyph
and in the foreground colour, even the `gate_failed` attempt that escalated
the run (parent L120). After this subtask `ok` draws as `done` and the three
failure outcomes draw as `dead` (urgent).

### Inherited constraints

| constraint | source |
|---|---|
| Decision 6: `glyphStateOf`: `ok` is `done`; `gate_failed`, `schema_invalid`, `harness_error` are `dead` | parent L167-168 |
| Attempt status vocabulary: `started, ok, schema_invalid, gate_failed, harness_error`; run/story/subtask/phase: `pending, started, done, failed, escalated, stopped, cancelled` | parent L37-39 |
| Rows are one per attempt; an attempt row's `state` is the attempt's status | parent L33-36 |
| Consumer table: `glyphStateOf` lacks attempt outcomes → attempt rows have no glyph, failures not urgent; `RunDetailScreen.qml:87`, `:90` consume it | parent L102, L120 |
| `canceled` → `cancelled` in `glyphStateOf` belongs to work breakdown item 4 ("Both cancel spellings"), not this card | parent L289-294, L327-328 |
| Not changed: `runGlyphs.js` state names; `PhaseTimeline`, `RunBadge`, `RunRollupBar`; screen layouts; the normalized shape | parent L306-317 |
| Unit tests of code reading am output build inputs from `tests/fixtures/am/`; a hand-written input for a value no capture contains carries a `synthetic:` comment; tests past `normalizeRun` may build normalized runs by hand, but a test asserting behaviour on real data normalizes a fixture | parent L257-267, card |
| QML loads fixtures with `tests/helpers/amFixtures.js` `load(name)` (fresh parse per call; needs `QML_XHR_ALLOW_FILE_READ=1`, set by `tests/run.sh`) | parent L269-274 |
| `docs/architecture.md` layering (`core/domain/*.js` pure JS, never throws); `tests/architecture` passes (no duplicated components; glyphs only through `runGlyphs.js`) | card |
| Docstrings and comments state the contract only, no narrative | card |
| `bash tests/run.sh` green; tests first | card |

### Fixture facts this design relies on (checked 2026-10-05)

Normalized with `Runs.normalizeRun` (the `amRun(name)` recipe of
`tests/core/domain/tst_runs.qml:14-24`):

- `status-escalated.json` (run `20261005T032543Z-bcc4e411`, `escalated`):
  statuses seen on `tree.subtasks[].phases[].attempts[].status` are `ok` and
  `gate_failed` (one); on `rows[].status`, `done`, `ok`, `gate_failed`. The
  `gate_failed` attempt is subtask `eb8b1851-8245-45c3-9a29-d1fcefaad0b9`
  (story `3f5aadb9-67b1-49b9-aec5-fb0bf81e46f9`), phase `review`, attempt 1.
  In `Runs.runTree` of that run it is story index 1, subtask index 0, attempt
  index 6, and that subtask's `currentPhase`/`currentAttempt` are `review`/`1`.
  So with the selection `{card_id: "eb8b1851-…", phase: "review", attempt: 1}`
  the screen's attempt label is objectName `runAttemptLabel1_0_6`.
- `status-done.json`: attempt statuses `ok` only; row statuses `done`, `ok`.
- No capture contains `schema_invalid` or `harness_error`.

### Behavior

`glyphStateOf(status)` returns a `runGlyphs.js` state name:

| status (exact string, case-sensitive, no trimming) | result |
|---|---|
| `started`, `running` | `running` (unchanged) |
| `stopped`, `parked` | `parked` (unchanged) |
| `escalated` | `escalated` (unchanged) |
| `failed`, `dead`, **`gate_failed`, `schema_invalid`, `harness_error`** | `dead` |
| `cancelled` | `cancelled` (unchanged) |
| `done`, **`ok`** | `done` |
| anything else (`pending`, `""`, `"OK"`, `" ok"`, `"canceled"`, `undefined`, `null`, a number, `"constructor"`, `"__proto__"`) | `""` (no glyph) |

Bold rows are new; every other mapping is unchanged. `canceled` still gives
`""` here (sibling work, item 4). Never throws.

#### Consumers

No QML change. `RunDetailScreen.glyphOf` (`RunDetailScreen.qml:87`) draws the
new glyphs and `isUrgent` (`:90`, `escalated` or `dead`) colours the three
failure outcomes with `theme.urgent`; an attempt row's label is
`"<marker><glyph> <phase>.<n> <status>"` (`attemptText`, `:111-115`) coloured by
`isUrgent(attempt.status)` (`:421`). Story, subtask and synthetic rows also go
through `glyphOf`, but their statuses are never attempt outcomes, so they are
unaffected. `PhaseTimeline` keeps its own mapping (parent "Not changed").

#### Contract comment

The comment above `glyphStateOf` (`runs.js:536-539`) states the contract: the
`runGlyphs.js` state an am story, subtask, phase, attempt or row status is
drawn with — `started` is running, `failed` and the attempt failures
`gate_failed`, `schema_invalid`, `harness_error` are dead, the attempt outcome
`ok` is done; `""` for anything else. No narrative.

### Tests

#### 1. `tests/core/domain/tst_runs.qml` (TestCase `DomainRuns`)

Tier: QML unit under `qmltestrunner` via `tests/run.sh`. Why: `glyphStateOf`
is pure domain JS; its existing table test lives here, and fixtures load
through `amFixtures.js` / the file's `amRun(name)`. No UI or process boundary.

- **`test_glyph_state_of`** (existing, `tst_runs.qml:1565-1570`): keep every
  existing case; add `["ok", "done"]`, `["gate_failed", "dead"]`, and, each
  with a `// synthetic:` comment saying no capture contains it,
  `["schema_invalid", "dead"]`, `["harness_error", "dead"]`. Add negative
  cases `["OK", ""]`, `[" ok", ""]`, `["canceled", ""]` (the last pins that
  the cancel spelling stays sibling work), `["__proto__", ""]`.
- **`test_fixture_glyph_state_of_attempt_outcomes`** (new; real data, fails
  first). For each of `status-escalated.json` and `status-done.json`,
  normalize `amRun(name)` and collect every `status` of
  `tree.subtasks[].phases[].attempts[]` and of `rows[]`. Every collected
  status maps per the expected table `{ok: "done", done: "done", gate_failed:
  "dead", failed: "dead", escalated: "escalated", started: "running",
  pending: ""}`; a collected status missing from that table fails the test
  (message names it), so a new am outcome cannot slip by unmapped. Non-vacuity:
  assert the escalated walk saw `gate_failed` and `ok`, and the done walk saw
  `ok`.

#### 2. `tests/ui/screens/tst_run_detail_screen.qml` (TestCase `RunDetailScreen`)

Tier: QML UI under `qmltestrunner`. Why: the observable outcome — glyph and
urgent colour on an attempt row — is rendered by `RunDetailScreen`; only a
screen test proves the domain change reaches it.

- Add imports `../../helpers/amFixtures.js` as `F` and
  `../../../core/domain/runs.js` as `Runs`, and a helper `amRun(name)`
  identical to `tst_runs.qml:14-24` (a test helper, not a component; the
  architecture check covers components).
- **`test_a_gate_failed_attempt_of_real_am_shows_the_dead_glyph_in_urgent`**
  (new; real data, fails first): `run = Runs.normalizeRun(amRun("status-escalated.json"))`;
  `s = make([run], run.id, sel("eb8b1851-8245-45c3-9a29-d1fcefaad0b9", "review", 1))`.
  Find the indices from `Runs.runTree(run)` (the story/subtask/attempt whose
  card is that id, phase `review`, attempt 1) rather than hard-coding them,
  and assert they are `1_0_6` once so a fixture change is loud. The label
  `runAttemptLabel1_0_6`: text equals
  `"› " + RG.glyphOf("dead") + " review.1 gate_failed"` and
  `Qt.colorEqual(label.color, s.screen.theme.urgent)` is true. In the same
  test, an `ok` attempt of that subtask (index 0) has text starting
  `"  " + RG.glyphOf("done") + " "` and is not urgent
  (`Qt.colorEqual(color, s.screen.theme.foreground)`).

No Python test: no Python code reads this mapping.

### Review focus (inputs the tests above might miss)

- An attempt status with different case or whitespace (`"OK"`, `"Gate_Failed"`)
  must give `""`, not a glyph — pinned in the table test.
- `canceled` must stay `""` in this card; mapping it is item 4's job.
- Prototype-named strings (`"constructor"`, `"__proto__"`) must not match if
  the implementation uses a lookup object — pinned in the table test.
- A story or subtask whose status is `done` / `failed` must render exactly as
  before (existing screen tests stay green unchanged).
- `started` attempts keep the running glyph (existing `implement.2 started`
  screen assertion stays green).

### Out of scope

- `canceled` spelling in `glyphStateOf` / `runState` (item 4, parent L289-294).
- `PhaseTimeline`'s own glyph mapping, `RunBadge`, `RunRollupBar`,
  `runGlyphs.js` (parent "Not changed").
- Any change to `RunDetailScreen.qml`, `normalizeRun`, `runTree`,
  `escalationReason` (2.5), `logTail` (item 3), docs (item 5).

### Files

- Modify: `core/domain/runs.js` (`glyphStateOf` and its comment only).
- Modify: `tests/core/domain/tst_runs.qml`.
- Modify: `tests/ui/screens/tst_run_detail_screen.qml`.

Verification: `bash tests/run.sh` green (pytest incl. `tests/architecture`, then
every `tst_*.qml`).

---

## File Structure

- Modify: `core/domain/runs.js:536-548` — `glyphStateOf` and its comment.
- Modify: `tests/core/domain/tst_runs.qml:1565-1570` — extend `test_glyph_state_of`; add `test_fixture_glyph_state_of_attempt_outcomes` right after it.
- Modify: `tests/ui/screens/tst_run_detail_screen.qml` — two imports (after line 10), an `amRun(name)` helper (after `sel`, line 121), and one new test (after `test_failed_and_escalated_tree_rows_are_drawn_urgent`, which ends at line 235).

One task: the change is one function, and its screen test only goes red while that function is unchanged, so all three tests are written red first, then the one implementation makes them green.

### Task 1: `glyphStateOf` maps `ok` to done and the attempt failures to dead

**Files:**
- Modify: `core/domain/runs.js:536-548`
- Test: `tests/core/domain/tst_runs.qml:1565-1570`
- Test: `tests/ui/screens/tst_run_detail_screen.qml`

**Interfaces:**
- Consumes: `Runs.normalizeRun(raw)`, `Runs.runTree(run)` (returns `{ stories: [{ card_id, label, status, other, subtasks: [{ card_id, status, phases, attempts: [{ phase, attempt, status }], currentPhase, currentAttempt }] }], synthetic }`), `F.load(name)`, `RG.glyphOf(state)`, the screen test's existing `make(list, selectedId, attempt)`, `sel(card, phase, n)`, `H.find(root, objectName)`.
- Produces: `glyphStateOf(status) -> string` — one of `"running"`, `"parked"`, `"escalated"`, `"dead"`, `"cancelled"`, `"done"`, `""`. Signature unchanged.

- [ ] **Step 1: Extend the table test**

In `tests/core/domain/tst_runs.qml`, replace the whole of `test_glyph_state_of` (lines 1565-1570):

```qml
  function test_glyph_state_of() {
    var cases = [["started", "running"], ["running", "running"], ["stopped", "parked"], ["parked", "parked"],
                 ["escalated", "escalated"], ["failed", "dead"], ["dead", "dead"], ["cancelled", "cancelled"],
                 ["done", "done"], ["pending", ""], ["", ""], [undefined, ""], [null, ""], [5, ""], ["constructor", ""]]
    for (var i = 0; i < cases.length; i++) compare(Runs.glyphStateOf(cases[i][0]), cases[i][1], String(cases[i][0]))
  }
```

with:

```qml
  function test_glyph_state_of() {
    var cases = [["started", "running"], ["running", "running"], ["stopped", "parked"], ["parked", "parked"],
                 ["escalated", "escalated"], ["failed", "dead"], ["dead", "dead"], ["cancelled", "cancelled"],
                 ["done", "done"], ["pending", ""], ["", ""], [undefined, ""], [null, ""], [5, ""], ["constructor", ""],
                 ["ok", "done"], ["gate_failed", "dead"],
                 // synthetic: no capture contains schema_invalid or harness_error.
                 ["schema_invalid", "dead"], ["harness_error", "dead"],
                 ["OK", ""], [" ok", ""], ["Gate_Failed", ""], ["canceled", ""], ["__proto__", ""]]
    for (var i = 0; i < cases.length; i++) compare(Runs.glyphStateOf(cases[i][0]), cases[i][1], String(cases[i][0]))
  }
```

- [ ] **Step 2: Add the real-data domain test**

Directly after `test_glyph_state_of` (before `function test_run_tree()`), add:

```qml
  // Every attempt and row status of a real capture maps per `expected`; a
  // status missing from it fails, naming the status.
  function test_fixture_glyph_state_of_attempt_outcomes() {
    var expected = { ok: "done", done: "done", gate_failed: "dead", failed: "dead", escalated: "escalated",
                     started: "running", pending: "" }
    function walk(name) {
      var r = Runs.normalizeRun(amRun(name))
      var seen = []
      for (var i = 0; i < r.tree.subtasks.length; i++) {
        var phases = r.tree.subtasks[i].phases || []
        for (var j = 0; j < phases.length; j++) {
          var tries = phases[j].attempts || []
          for (var k = 0; k < tries.length; k++) seen.push(tries[k].status)
        }
      }
      for (var w = 0; w < r.rows.length; w++) seen.push(r.rows[w].status)
      for (var s = 0; s < seen.length; s++) {
        var st = seen[s]
        verify(typeof st === "string" && Object.prototype.hasOwnProperty.call(expected, st),
               name + ": status " + String(st) + " has no expected glyph state")
        compare(Runs.glyphStateOf(st), expected[st], name + ": " + st)
      }
      return seen
    }
    var escalated = walk("status-escalated.json")
    verify(escalated.indexOf("gate_failed") >= 0, "status-escalated.json has a gate_failed status")
    verify(escalated.indexOf("ok") >= 0, "status-escalated.json has an ok status")
    verify(walk("status-done.json").indexOf("ok") >= 0, "status-done.json has an ok status")
  }
```

(`amRun` is the existing helper at `tst_runs.qml:14-24`.)

- [ ] **Step 3: Add the real-data screen test**

In `tests/ui/screens/tst_run_detail_screen.qml`:

(a) After the line `import "../../../ui/components/runGlyphs.js" as RG` (line 10) add:

```qml
import "../../helpers/amFixtures.js" as F
import "../../../core/domain/runs.js" as Runs
```

(b) After `function sel(card, phase, n) { return { card_id: card, phase: phase, attempt: n } }` (line 121) add:

```qml

  // One am run as RunStore hands it to normalizeRun, fresh on every call: the
  // fixture's `am runs` row (runs.json's entry with the same run id, else the
  // fixture's own _am_runs_row) without `status`, and the fixture's `am status`
  // data.
  function amRun(name) {
    var fixture = F.load(name)
    var runs = F.load("runs.json").data.runs
    var row = fixture._am_runs_row
    for (var i = 0; i < runs.length; i++) {
      if (runs[i].id === fixture.data.run.id) row = runs[i]
    }
    delete row.status
    return { row: row, status: fixture.data }
  }
```

(c) After `test_failed_and_escalated_tree_rows_are_drawn_urgent` (its closing `}` is line 235 before the edits above; place the new function right after it, before the `// Review Focus 3.` comment) add:

```qml

  // Real am: review.1 of eb8b1851 is the gate_failed attempt that escalated
  // status-escalated.json; explore.1 of the same subtask is ok.
  function test_a_gate_failed_attempt_of_real_am_shows_the_dead_glyph_in_urgent() {
    var run = Runs.normalizeRun(amRun("status-escalated.json"))
    var card = "eb8b1851-8245-45c3-9a29-d1fcefaad0b9"
    var key = ""
    var stories = Runs.runTree(run).stories
    for (var si = 0; si < stories.length; si++) {
      for (var ti = 0; ti < stories[si].subtasks.length; ti++) {
        var t = stories[si].subtasks[ti]
        if (t.card_id !== card) continue
        for (var ai = 0; ai < t.attempts.length; ai++) {
          if (t.attempts[ai].phase === "review" && t.attempts[ai].attempt === 1) key = si + "_" + ti + "_" + ai
        }
      }
    }
    compare(key, "1_0_6", "where the capture puts review.1 of " + card)
    var s = make([run], run.id, sel(card, "review", 1)); if (!s) return
    var failed = H.find(s.screen, "runAttemptLabel" + key)
    compare(failed.text, "› " + RG.glyphOf("dead") + " review.1 gate_failed")
    verify(Qt.colorEqual(failed.color, s.screen.theme.urgent), "a gate_failed attempt is urgent")
    var ok = H.find(s.screen, "runAttemptLabel1_0_0")
    compare(ok.text, "  " + RG.glyphOf("done") + " explore.1 ok")
    verify(Qt.colorEqual(ok.color, s.screen.theme.foreground), "an ok attempt is not urgent")
  }
```

- [ ] **Step 4: Run the domain tests to verify they fail**

Run: `bash tests/run.sh core/domain/tst_runs`
Expected: `FAIL!  : DomainRuns::test_glyph_state_of() ok` (actual `""`, expected `"done"`) and `FAIL!  : DomainRuns::test_fixture_glyph_state_of_attempt_outcomes() status-escalated.json: ok` (or the `gate_failed` message). Every other `DomainRuns` test passes. Exit status non-zero.

- [ ] **Step 5: Run the screen test to verify it fails**

Run: `bash tests/run.sh tst_run_detail_screen`
Expected: `FAIL!  : RunDetailScreen::test_a_gate_failed_attempt_of_real_am_shows_the_dead_glyph_in_urgent()` on the `compare(failed.text, …)` line — actual `"› review.1 gate_failed"` (no glyph). The `compare(key, "1_0_6", …)` line must NOT be the failure; if it is, stop: the fixture no longer matches the spec's facts. Every other `RunDetailScreen` test passes.

- [ ] **Step 6: Implement**

In `core/domain/runs.js`, replace lines 536-548:

```js
// The run-state name (a runGlyphs.js key) an am story, subtask, phase, attempt
// or row status is drawn with -- the mapping PhaseTimeline uses (started is
// running, failed is dead). "" for anything else, which shows no glyph.
function glyphStateOf(status) {
  if (status === "started" || status === "running") return "running"
  if (status === "stopped" || status === "parked") return "parked"
  if (status === "escalated") return "escalated"
  if (status === "failed" || status === "dead") return "dead"
  if (status === "cancelled") return "cancelled"
  if (status === "done") return "done"
  return ""
}
```

with:

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
  if (status === "done" || status === "ok") return "done"
  return ""
}
```

- [ ] **Step 7: Run the targeted tests to verify they pass**

Run: `bash tests/run.sh core/domain/tst_runs && bash tests/run.sh tst_run_detail_screen`
Expected: both print `Totals: N passed, 0 failed, …` and exit 0.

- [ ] **Step 8: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest passes (including `tests/architecture`), every `tst_*.qml` prints `0 failed`, no `TypeError`/`ReferenceError` lines, exit 0. Existing screen tests (`test_the_timeline_and_attempts_show_under_the_selected_subtask_only`, `test_failed_and_escalated_tree_rows_are_drawn_urgent`, `test_an_unnumbered_attempt_is_listed_but_not_clickable`) pass unchanged.

- [ ] **Step 9: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml tests/ui/screens/tst_run_detail_screen.qml
git commit -m "feat(runs): glyphStateOf draws am's attempt outcomes"
```

---

## Self-Review

- **Spec coverage:** Behavior table → Step 6 + Step 1. Contract comment → Step 6. `test_glyph_state_of` additions (incl. `synthetic:` comment, `OK`, ` ok`, `canceled`, `__proto__`) → Step 1. `test_fixture_glyph_state_of_attempt_outcomes` with the spec's table, unmapped-status failure and non-vacuity → Step 2. Screen test with imports, `amRun`, indices found from `runTree` and asserted `1_0_6`, dead glyph + urgent, ok row done glyph + foreground → Step 3. No QML/`runGlyphs.js` change → Global Constraints. Full suite → Step 8.
- **Fixture facts re-checked** (2026-10-05, normalizing with the `amRun` recipe): `status-escalated.json` attempts `ok`, `gate_failed`; rows `done`, `ok`, `gate_failed`; subtask `eb8b1851…` at story 1, subtask 0, attempts `0:explore.1:ok … 6:review.1:gate_failed`, current `review`/`1`. `status-done.json` attempts `ok`; rows `done`, `ok`.
- **Placeholders:** none. **Types:** `glyphStateOf` signature unchanged; `runTree` field names (`stories[].subtasks[].attempts[].phase/attempt/status`, `card_id`) match `core/domain/runs.js:596-670`.
<!-- task-pipeline: validated -->
