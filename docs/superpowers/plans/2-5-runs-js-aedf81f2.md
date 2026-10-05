# 2.5 runs.js: escalationReason falls back to a failed row only — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When no tree phase is `failed`, `escalationReason` names the phase of the last row whose status is a failure (`failed`, `escalated`, `gate_failed`, `schema_invalid`, `harness_error`), else returns `escalated` — never a phase that went fine, such as `mark_done`.

**Architecture:** One function changes in `core/domain/runs.js`: the row fallback of `escalationReason` (lines 353-357 today) skips rows whose `status` is not in a new module-level array `_FAILURE_STATUSES` (matched with `indexOf`, i.e. `===`), and the contract comment above it (lines 334-335) is restated. The tree branch (lines 336-352) is untouched. `tests/core/domain/tst_runs.qml` gains a fixture helper and two real-data tests, and the `noFailed` case of `test_escalation_reason_fallbacks` is replaced by `synthetic:` cases.

**Tech Stack:** Qt 6 QML / V4 JavaScript (`.pragma library`), QtTest via `qmltestrunner`, driven by `bash tests/run.sh [path-substring]` (pytest runs first, then every `tst_*.qml` whose path contains the substring; `core/domain/tst_runs` matches only `tests/core/domain/tst_runs.qml`).

**Spec:** `docs/superpowers/specs/2-5-runs-js-aedf81f2.md` (prepended below, headings demoted one level; executors read both).

## Global Constraints

- Code: only `escalationReason`'s row fallback, the comment above `escalationReason`, and one new module-level constant `_FAILURE_STATUSES` change in `core/domain/runs.js`. The tree branch (first object phase with `status === "failed"`, its trimmed `detail`, else its last attempt's non-empty trimmed `detail`, else `escalated at <trimmed name>`, else `escalated`) is **not edited**. `normalizeRun`, `rollup`, `runProgress`, `runTree`, `glyphStateOf`, `newAlerts`, `_textOf` are **not edited**.
- Failure statuses, exactly: `failed`, `escalated`, `gate_failed`, `schema_invalid`, `harness_error`. Case-sensitive, no trimming: `"FAILED"`, `" failed"`, `"dead"`, `"ok"`, `"done"`, `null`, numbers never match. Lookup is `===` only (`Array.prototype.indexOf`), so `"__proto__"`, `"constructor"`, `"toString"` never match.
- Row fallback: reached only when no tree phase is `failed`; scan `run.rows` from last to first; the first row met that is an object, has a failure status, and has `_textOf(row.phase) !== ""` gives `"escalated at " + _textOf(row.phase)`; a failure row with an empty/missing phase is passed over; none gives `"escalated"`.
- Never throws. `core/domain/runs.js` stays `.pragma library` with exactly `.import "board.js" as Board`; `docs/architecture.md` layering holds and `tests/architecture` passes.
- Docstrings and comments state the contract only, no narrative.
- Tests asserting behaviour on real data normalize a capture via `amRun(name)` (`tests/helpers/amFixtures.js` `F.load`, fresh parse per call). Hand-built normalized runs (`mkRun`) are allowed past `normalizeRun`; a hand-written input for a case no capture contains is labelled `// synthetic:`.
- Not changed: the normalized shape and its keys; `rows` granularity; `RunsScreen.qml`, `RunDetailScreen.qml`, `RunStore.qml`, `RunToast`, `notify.py`; the fixtures; `docs/architecture.md`; the existing alert tests (`tst_runs.qml` "S2 1.2: run alerts" section) — edit one only if it fails because it depended on the old row fallback.
- No QML test function name may end in `_data` (QtTest treats it as a data provider and never runs it).
- `bash tests/run.sh` green at the end; tests first (red before green). Never `git stash`.

## Review Focus

1. A failure row followed by later `done`/`ok` rows (the real shape: `review` `gate_failed`, then `mark_done` `done`): a person expects `escalated at <the failed phase>`, not the later finished phase. Pinned in Task 1 by `test_escalation_reason_fallbacks` (one run per failure status, each followed by `verify` `done` and `mark_done` `ok`) and the two-failure-row case.
2. An Integrate-level escalation with no failure anywhere (`status-escalated-integrate.json`, last row `mark_done` `done`): expected plain `escalated`, both in the reason and in the alert/notification. Pinned in Task 1 by `test_fixture_escalation_reason` and `test_fixture_new_alerts_escalation_reason`.
3. The last failure row has an empty / whitespace / missing phase, and an earlier failure row has one: expected `escalated at <the earlier phase>`; non-object rows (`null`, `5`) are skipped, never a throw. Pinned in Task 1 by the "no usable phase" case of `test_escalation_reason_fallbacks`.
4. A status differing only by case or whitespace (`"FAILED"`, `" failed"`), am's non-failure spellings (`dead`, `stopped`, `cancelled`), `null`, a number, or an `Object.prototype` key (`"__proto__"`, `"constructor"`, `"toString"`): expected never to count as a failure, giving `escalated`. Pinned in Task 1 by the "no failure status" case of `test_escalation_reason_fallbacks`.
5. A run with a failed tree phase *and* failure rows elsewhere: expected the tree phase still wins (its detail, or `escalated at <that phase>`). Pinned in Task 1 by `test_fixture_escalation_reason` (`status-escalated.json`) and the synthetic "tree wins over rows" case in `test_escalation_reason_fallbacks`.

---

## Spec (prepended; headings demoted one level)

## 2.5 runs.js: escalationReason falls back to a failed row only — design

Card `aedf81f2`, a subtask of story `21f9cd5a` ("Normalize real am status"),
blocked by `c7cfa719` (2.4, `runTree`'s open attempt, committed at `65d85cd`).
Parent spec: `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
(below: **parent**). Work breakdown item 2 (parent L324-326) lists
"`normalizeRun` …, then `rollup`, `runProgress`, `runTree`'s open attempt,
`escalationReason`, `glyphStateOf`": this subtask is `escalationReason` only
(`core/domain/runs.js:334-359`).

### Goal

The reason shown for an escalated run (Runs list row, Run detail header, alert
toast and desktop notification) names a failure, never a phase that went fine.
Today, when no tree phase is `failed`, `escalationReason` returns
`escalated at <phase>` for the **last row with a phase, whatever its status**.
Real am ends a subtask with deterministic phases whose rows are `done`, and an
escalation at the final Integrate verification has no failed phase in the tree
at all (parent L42-44), so `status-escalated-integrate.json` reads
`escalated at mark_done` (parent L98) — a phase that succeeded. After this
subtask the row fallback names the phase of the last row whose status is a
failure, and with none the reason is `escalated`.

### Inherited constraints

| constraint | source |
|---|---|
| Decision 5: after the failed phase's detail, `escalationReason` names the phase of the last row whose status is `failed`, `escalated`, `gate_failed`, `schema_invalid` or `harness_error`; none gives `escalated` | parent L163-166 |
| Consumer table: `escalationReason`'s fallback takes the LAST row's phase whatever its state; "escalated at mark_done" for an Integrate escalation | parent L98 |
| Rows are one per attempt; `state` is the attempt's status on an attempt row, the phase's status otherwise; status vocabularies (run/story/subtask/phase: `pending, started, done, failed, escalated, stopped, cancelled`; attempt: `started, ok, schema_invalid, gate_failed, harness_error`) | parent L33-39 |
| A run escalating at the final Integrate verification has no failed phase in the tree | parent L42-44 |
| Acceptance: `escalationReason` of `status-escalated.json` is its review phase's `detail` (`phase 'review' gate 'review_blockers_gate' failed: …`), of `status-escalated-integrate.json` is `escalated` | parent L219-221 |
| Consumers: `RunsScreen.qml:256`, `RunDetailScreen.qml:214`, `newAlerts` | parent L117, L121, L138 |
| Tests of `runs.js` helpers past `normalizeRun` may build normalized runs by hand; a test asserting behaviour on real data normalizes a fixture; a hand-written input for a case no capture contains is labelled `synthetic:` | parent L257-267, card |
| QML loads fixtures with `tests/helpers/amFixtures.js` `load(name)` (fresh parse each call) | parent L269-274 |
| Not changed: the normalized shape and its keys; `rows` keeps per-attempt granularity; screen layouts | parent L306-317 |
| Open question, not answered here: an Integrate-level escalation carries no reason in `am status`; the reason stays `escalated` until am records one | parent L338-339 |
| `docs/architecture.md` layering (`core/domain/*.js` is pure JS, never throws); `tests/architecture` passes | card |
| Docstrings and comments state the contract only, no narrative | card |
| `bash tests/run.sh` green; tests first | card |

### Fixture facts this design relies on (checked 2026-10-05)

`normalizeRun` already turns each am row into `{story_id, card_id, phase,
attempt, status}` with `status` = am's `state` (`runs.js:119-126`); this subtask
reads `rows[].status` and `rows[].phase` of the normalized run.

- `status-escalated.json` (run `20261005T032543Z-bcc4e411`, 40 rows): one tree
  phase is `failed` — subtask `eb8b1851…`, `review`, `detail` = `phase 'review'
  gate 'review_blockers_gate' failed: blocked=review, detail=review left 1
  unresolved blocker(s): the review-fail marker names
  m3/task-b1-only-subtask-of-eb8b1851`. Its only row not `done`/`ok` is the last
  one: `review`, attempt 1, `gate_failed`. Reason under both old and new rules:
  that detail (the tree branch wins first).
- `status-escalated-integrate.json` (run `20261005T032958Z-5a2d70ff`, 28 rows):
  no tree phase is `failed`; no row has a failure status; the last row is
  `mark_done`, attempt `null`, `done`. Old rule: `escalated at mark_done`. New
  rule: `escalated`.

So the integrate assertions fail on today's code; the `status-escalated.json`
assertions pass on it and pin that the change keeps the detail first.

### Behavior

#### Unchanged: the tree branch

The first object phase whose `status` is exactly `"failed"`, scanning
`tree.subtasks[].phases[]` in order, still decides first: its trimmed `detail`,
else its last attempt's non-empty trimmed `detail`, else `escalated at <name>`
(trimmed name), else `escalated` (`runs.js:336-352`, unchanged).

#### Changed: the row fallback

Reached only when no tree phase is `failed`. Scan `run.rows` from the last
element back to the first. The reason is `escalated at <phase>` for the first
row met (i.e. the **last** by position) that

1. is an object,
2. has a `status` that is exactly one of the strings `failed`, `escalated`,
   `gate_failed`, `schema_invalid`, `harness_error` (case-sensitive, no
   trimming: `"FAILED"`, `" failed"`, `"dead"`, `"ok"`, `"done"`, `null`, a
   number never match), and
3. has a phase that is non-empty after trimming (`_textOf(row.phase)`, as
   today); a failure row with an empty or missing phase is passed over and the
   scan continues to earlier rows.

No such row: `escalated`.

A failure row followed by later non-failure rows (e.g. `review` `gate_failed`,
then `mark_done` `done`) gives `escalated at review`.

#### Error paths

Never throws. `run` not an object, `rows` not an array, row elements that are
not objects, a `tree` that is not an object or has non-array `subtasks` /
`phases`: all reach `escalated` (or the row fallback, for a bad tree with good
rows), as today. The failure-status set is a module-level constant and looked up
with own-key / `===` comparison only, so a row status such as `"__proto__"`,
`"constructor"` or `"toString"` does not match.

#### Consumers

No UI or store code changes. `RunsScreen.qml:256` and `RunDetailScreen.qml:214`
render the new string; `newAlerts` (`runs.js:842`) puts it in an escalated
alert's `reason`, which `RunStore` shows in `RunToast` and passes to
`notify.py`. `glyphStateOf` is not reused: it maps `escalated` to its own glyph
state and is changed by sibling card 2.6.

#### Contract comment

The comment above `escalationReason` (`runs.js:334-335`) states the rule as a
contract: the first failed phase's detail (or its last attempt's detail), else
`escalated at <that phase>`; with no failed phase, `escalated at <phase>` of
the last row whose status is `failed`, `escalated`, `gate_failed`,
`schema_invalid` or `harness_error`; else `escalated`. No narrative.

### Tests

All in `tests/core/domain/tst_runs.qml` (TestCase `DomainRuns`; tier: QML unit,
run by `tests/run.sh` under `qmltestrunner`). Why this tier: `escalationReason`
and `newAlerts` are pure domain JS; the existing `escalationReason` and alert
tests live here, fixtures load through `amFixtures.js` / the file's
`amRun(name)` (`tst_runs.qml:14-24`), and no UI or process boundary is
involved. No Python test: no Python code reads this rule.

1. **`test_fixture_escalation_reason`** (real data; the integrate half fails
   first). `Runs.escalationReason(Runs.normalizeRun(amRun("status-escalated.json")))`
   equals the full review detail string above (copy it verbatim from the
   fixture into the test, or read it from the fixture's
   `data.stories[*].subtasks[*].phases[*]` with `name === "review"` and
   `status === "failed"` — the assertion is equality with that detail).
   `Runs.escalationReason(Runs.normalizeRun(amRun("status-escalated-integrate.json")))`
   equals `"escalated"`.
2. **`test_fixture_new_alerts_escalation_reason`** (real data through
   `newAlerts`; the integrate half fails first). For each of the two fixtures:
   `next` = the normalized fixture run; `prev` = `[mkRun(next.id, "started",
   true)]` (`// synthetic: the same run one snapshot earlier, while it was
   running — no capture holds both`). `Runs.newAlerts(prev, [next])` has length
   1, `state` `escalated`, `id` `next.id`, and `reason` equal to that fixture's
   expected reason from test 1 (review detail; `escalated`).
3. **`test_escalation_reason_fallbacks`** (existing, `tst_runs.qml:1066-1093`;
   hand-built normalized runs via `mkRun`, allowed past `normalizeRun` by
   parent L262-265). Keep `noDetail`, `nameless`, "nothing at all" and the
   garbage list unchanged (they must still pass). Replace the `noFailed` case,
   whose rows carry no `status` and expect `escalated at implement` under the
   old rule, with cases labelled `// synthetic:` (same tree with no exactly
   `failed` phase, `plan` `FAILED`):
   - each status of the five, one run per status: rows `[{card_id: "t1", phase:
     "spec", status: "done"}, {card_id: "t2", phase: "implement", status: S},
     {card_id: "t3", phase: "verify", status: "done"}, {card_id: "t4", phase:
     "mark_done", status: "ok"}]` → `escalated at implement` (a later
     non-failure row does not win);
   - two failure rows: `[{phase: "spec", status: "failed"}, {phase: "review",
     status: "harness_error"}, {phase: "mark_done", status: "done"}]` →
     `escalated at review` (the last failure row);
   - a last failure row with no usable phase: `[{phase: "spec", status:
     "gate_failed"}, {phase: "  ", status: "failed"}, {status: "escalated"},
     null, 5]` → `escalated at spec`;
   - no failure status: rows with statuses `done`, `ok`, `started`, `pending`,
     `stopped`, `cancelled`, `FAILED`, `" failed"`, `"dead"`, `null`, `1`,
     `"__proto__"`, `"toString"`, and one row with no `status` key, all with
     non-empty phases → `escalated`;
   - rows not an array (`"x"`, `{}`) with no failed phase → `escalated`.
4. **Existing alert tests** (`tst_runs.qml:1871-2100`): `alTree()` is a failed
   `review` phase without detail, so their `escalated at review` comes from the
   tree branch and must still pass unchanged; `d` (no tree, no rows) stays
   `escalated`. Edit nothing there unless a run shows a failure caused by the
   old row fallback.

`tests/ui/screens/*` need no edit (no test there asserts an `escalated at`
string; checked with grep). Run them anyway as part of the full suite.

Verification: `bash tests/run.sh` green (pytest architecture/contract/install,
then every QML suite); `bash tests/run.sh tst_runs` for the inner loop.

### Out of scope

- The tree branch of `escalationReason` (first failed phase, its detail, its
  attempts' details, `escalated at <name>`): unchanged.
- `glyphStateOf` and attempt-outcome glyphs (2.6); `logTail`,
  `runs-logs.py --repo-dir`, `RunStore` (story 3); cancel spellings and watch
  schemas (story 4); docs including `docs/architecture.md` (story 5).
- `normalizeRun`, `rollup`, `runProgress`, `runTree` (2.1-2.4, done).
- A reason for Integrate-level escalations (needs am to record one; parent
  L338-339); `newAlerts`' dead reason `process died`.
- `RunsScreen.qml`, `RunDetailScreen.qml`, `RunStore.qml`, `RunToast`,
  `notify.py`: no code change.

### Plan handoff

The plan follows the writing-plans format with one task: tests 1-3 red where
stated (integrate halves of 1 and 2; the new synthetic cases of 3), the
`escalationReason` row-fallback change with its module-level failure-status set
and contract comment, `bash tests/run.sh tst_runs` green, full suite green,
commit. Review Focus candidates: a failure row followed by `done` rows (the
real Integrate shape); a failure row with an empty phase after an earlier
failure row with a phase; a status differing only by case or whitespace; a
status equal to an `Object.prototype` key (`__proto__`, `toString`); a run with
a failed tree phase *and* failure rows (the tree detail must still win —
`status-escalated.json` is exactly this).

---

## File Structure

- Modify: `core/domain/runs.js` — the comment above `escalationReason` (lines 334-335 today), a new constant `_FAILURE_STATUSES` placed directly above that comment, and the row loop at the end of `escalationReason` (lines 353-357 today). Nothing else in the file.
- Modify: `tests/core/domain/tst_runs.qml` — in the `// ---- 1.2: escalation reason ----` section (lines 1045-1093 today): replace the `noFailed` case in `test_escalation_reason_fallbacks` (lines 1074-1080), add the synthetic cases there, and add the helper `escalatedFixtures()` plus `test_fixture_escalation_reason` and `test_fixture_new_alerts_escalation_reason` right after `test_escalation_reason_fallbacks` (before the `// ---- 1.2: error text ----` line).

One task: the rule, its constant, its comment and its tests change together, and a reviewer cannot meaningfully approve one without the other.

### Task 1: `escalationReason` falls back to the last failure row only

**Files:**
- Modify: `core/domain/runs.js:334-358`
- Test: `tests/core/domain/tst_runs.qml:1066-1093` (and new functions inserted after line 1093)

**Interfaces:**
- Consumes (existing, unchanged, all in `core/domain/runs.js`): `_isObject(v) -> bool`, `_arrayOr(v) -> Array`, `_textOf(v) -> string` (String(v) trimmed; `""` for null/undefined), `_treeOf(run) -> {stories, subtasks}`, `newAlerts(prevRuns, nextRuns) -> [{id, title, state, reason}]`, `normalizeRun(raw) -> run` (rows are `{story_id, card_id, phase, attempt, status}`). In the test file: `amRun(name)` (line 14), `mkRun(id, status, live, opts)` (line 600; `opts.rows` is used as given when truthy, `opts.tree` likewise), `Runs` import alias.
- Produces: `escalationReason(run) -> string` with the new row fallback; module-level `var _FAILURE_STATUSES = ["failed", "escalated", "gate_failed", "schema_invalid", "harness_error"]` (private, `_` prefix; no other function uses it in this task). Test helper `escalatedFixtures() -> [[fixtureName, expectedReason], ...]`.

- [ ] **Step 1: Write the real-data failing tests**

In `tests/core/domain/tst_runs.qml`, find the end of `test_escalation_reason_fallbacks` — the lines

```qml
    var bad = [undefined, null, "x", 5, [], {}, { tree: "x", rows: "y" },
               { tree: { subtasks: [null, { phases: "x" }, { phases: [null, 5] }] }, rows: [null] }]
    for (var i = 0; i < bad.length; i++) compare(Runs.escalationReason(bad[i]), "escalated", "garbage " + i)
  }
```

and insert directly after that closing `}` (and before the blank line and `  // ---- 1.2: error text ----...` line):

```qml

  // The two escalated captures and the reason each escalated with: status-escalated.json's
  // failed review phase's detail, and plain "escalated" for the Integrate escalation, whose
  // tree has no failed phase and whose rows have no failure status.
  function escalatedFixtures() {
    return [
      ["status-escalated.json", "phase 'review' gate 'review_blockers_gate' failed: blocked=review, detail=review left 1 unresolved blocker(s): the review-fail marker names m3/task-b1-only-subtask-of-eb8b1851"],
      ["status-escalated-integrate.json", "escalated"]
    ]
  }

  function test_fixture_escalation_reason() {
    var integrate = Runs.normalizeRun(amRun("status-escalated-integrate.json"))
    var last = integrate.rows[integrate.rows.length - 1]
    compare(last.phase + ":" + last.status, "mark_done:done", "the Integrate capture ends on a finished row")

    var cases = escalatedFixtures()
    for (var i = 0; i < cases.length; i++)
      compare(Runs.escalationReason(Runs.normalizeRun(amRun(cases[i][0]))), cases[i][1], cases[i][0])
  }

  function test_fixture_new_alerts_escalation_reason() {
    var cases = escalatedFixtures()
    for (var i = 0; i < cases.length; i++) {
      var next = Runs.normalizeRun(amRun(cases[i][0]))
      verify(next.id !== "", cases[i][0] + " has a run id")
      // synthetic: the same run one snapshot earlier, while it was running -- no capture holds both
      var prev = [mkRun(next.id, "started", true)]
      var a = Runs.newAlerts(prev, [next])
      compare(a.length, 1, cases[i][0] + " one alert")
      compare(a[0].state, "escalated", cases[i][0] + " state")
      compare(a[0].id, next.id, cases[i][0] + " id")
      compare(a[0].reason, cases[i][1], cases[i][0] + " reason")
    }
  }
```

- [ ] **Step 2: Run them to verify the Integrate halves fail**

Run: `bash tests/run.sh core/domain/tst_runs`
Expected: pytest passes; in the `== tests/core/domain/tst_runs.qml` block, exactly two `FAIL!` lines (QtTest's exact wording may differ; what matters is which function and message fail, and the Actual/Expected values):
- `test_fixture_escalation_reason()` with message `status-escalated-integrate.json` (Actual `escalated at mark_done`, Expected `escalated`);
- `test_fixture_new_alerts_escalation_reason()` with message `status-escalated-integrate.json reason` (same values).

The `status-escalated.json` compares and the `mark_done:done` precondition pass before failing on the Integrate case. If the precondition compare fails instead, stop: the fixture is not what the spec describes.

- [ ] **Step 3: Replace the `noFailed` case with the synthetic row-fallback cases**

In `test_escalation_reason_fallbacks`, replace exactly these lines:

```qml
    var noFailed = mkRun("r", "escalated", null, {
      tree: { stories: [], subtasks: [{ card_id: "t1", phases: [{ name: "spec", status: "done" },
                                                                { name: "plan", status: "FAILED" }] }] },
      rows: [{ card_id: "t1", phase: "spec" }, { card_id: "t2", phase: "implement" },
             { card_id: "t3", phase: "" }, { card_id: "t4" }, null]
    })
    compare(Runs.escalationReason(noFailed), "escalated at implement", "last row phase; status match is exact")
```

with:

```qml
    // synthetic: a tree with no phase whose status is exactly "failed", fresh per call
    function noFailedTree() {
      return { stories: [], subtasks: [{ card_id: "t1", phases: [{ name: "spec", status: "done" },
                                                                 { name: "plan", status: "FAILED" }] }] }
    }

    var failures = ["failed", "escalated", "gate_failed", "schema_invalid", "harness_error"]
    for (var f = 0; f < failures.length; f++) {
      // synthetic: one failure row followed by finished rows
      var oneFailure = mkRun("r", "escalated", null, { tree: noFailedTree(), rows: [
        { card_id: "t1", phase: "spec", status: "done" },
        { card_id: "t2", phase: "implement", status: failures[f] },
        { card_id: "t3", phase: "verify", status: "done" },
        { card_id: "t4", phase: "mark_done", status: "ok" }] })
      compare(Runs.escalationReason(oneFailure), "escalated at implement",
              failures[f] + ": the failure row, not a later finished row")
    }

    // synthetic: two failure rows, then a finished row
    var twoFailures = mkRun("r", "escalated", null, { tree: noFailedTree(), rows: [
      { phase: "spec", status: "failed" }, { phase: "review", status: "harness_error" },
      { phase: "mark_done", status: "done" }] })
    compare(Runs.escalationReason(twoFailures), "escalated at review", "the last failure row")

    // synthetic: the later failure rows have no usable phase
    var noPhase = mkRun("r", "escalated", null, { tree: noFailedTree(), rows: [
      { phase: "spec", status: "gate_failed" }, { phase: "  ", status: "failed" }, { status: "escalated" }, null, 5] })
    compare(Runs.escalationReason(noPhase), "escalated at spec", "a failure row without a phase is passed over")

    // synthetic: statuses that are not failures, every row with a phase
    var others = ["done", "ok", "started", "pending", "stopped", "cancelled", "FAILED", " failed", "dead",
                  null, 1, "__proto__", "constructor", "toString"]
    var otherRows = []
    for (var o = 0; o < others.length; o++) otherRows.push({ card_id: "t" + o, phase: "p" + o, status: others[o] })
    otherRows.push({ card_id: "tx", phase: "px" })
    compare(Runs.escalationReason(mkRun("r", "escalated", null, { tree: noFailedTree(), rows: otherRows })),
            "escalated", "no failure status; status match is exact")

    // synthetic: rows that are not an array
    var notArrays = ["x", {}]
    for (var n = 0; n < notArrays.length; n++)
      compare(Runs.escalationReason(mkRun("r", "escalated", null, { tree: noFailedTree(), rows: notArrays[n] })),
              "escalated", "rows not an array " + n)

    // synthetic: a failed tree phase and a failure row in another phase
    var both = mkRun("r", "escalated", null, {
      tree: { stories: [], subtasks: [{ card_id: "t1", phases: [{ name: "review", status: "failed" }] }] },
      rows: [{ card_id: "t1", phase: "implement", status: "gate_failed" }]
    })
    compare(Runs.escalationReason(both), "escalated at review", "the failed tree phase wins over rows")
```

Leave `noDetail`, `nameless`, "nothing at all" and the `bad` garbage list exactly as they are. (The `bad` loop declares `var i`; the new code uses `f`, `o`, `n`, so no name clashes.)

- [ ] **Step 4: Run them to verify the new synthetic cases fail**

Run: `bash tests/run.sh core/domain/tst_runs`
Expected: three `FAIL!` lines in the `tst_runs.qml` block — the two from Step 2, plus
`test_escalation_reason_fallbacks()` with message `failed: the failure row, not a later finished row` (Actual `escalated at mark_done`, Expected `escalated at implement`). QtTest stops a test function at its first failed compare, so only this first failure of the function shows.

- [ ] **Step 5: Implement the row fallback**

In `core/domain/runs.js`, replace exactly:

```js
// Why a run escalated: the first failed phase's detail (or its last attempt's detail),
// else "escalated at <phase>", else "escalated".
function escalationReason(run) {
```

with:

```js
// Row statuses that mean a phase or attempt failed.
var _FAILURE_STATUSES = ["failed", "escalated", "gate_failed", "schema_invalid", "harness_error"]

// Why a run escalated: the first failed phase's detail (or its last attempt's detail),
// else "escalated at <that phase>". With no failed phase, "escalated at <phase>" of the
// last row whose status is failed, escalated, gate_failed, schema_invalid or
// harness_error and whose phase is not empty; else "escalated".
function escalationReason(run) {
```

and, further down in the same function, replace exactly:

```js
  for (var r = rows.length - 1; r >= 0; r--) {
    var at = _isObject(rows[r]) ? _textOf(rows[r].phase) : ""
    if (at !== "") return "escalated at " + at
  }
  return "escalated"
}
```

with:

```js
  for (var r = rows.length - 1; r >= 0; r--) {
    var row = rows[r]
    if (!_isObject(row) || _FAILURE_STATUSES.indexOf(row.status) < 0) continue
    var at = _textOf(row.phase)
    if (at !== "") return "escalated at " + at
  }
  return "escalated"
}
```

`indexOf` compares with `===`, so `null`, numbers, `"FAILED"`, `" failed"` and `Object.prototype` key names never match.

- [ ] **Step 6: Run the suite file to verify it passes**

Run: `bash tests/run.sh core/domain/tst_runs`
Expected: exit code 0; the `tst_runs.qml` block prints `Totals: … 0 failed` with no `FAIL!` lines and no `TypeError` / `ReferenceError` / `is not a function` lines. The alert tests (`test_new_alerts_*`) pass unchanged: `alTree()` has a failed `review` phase, so their `escalated at review` comes from the tree branch; `d` (no tree, no rows) stays `escalated`.

If any existing test outside the escalation-reason section fails, read its assertion: edit it only if it expected `escalated at <phase>` from a row without a failure status (the old fallback); otherwise the implementation is wrong — fix the implementation, not the test.

- [ ] **Step 7: Run the full suite**

Run: `bash tests/run.sh`
Expected: exit code 0; pytest (including `tests/architecture`) passes; every `== tests/...tst_*.qml` block prints `Totals: … 0 failed` and no `TypeError` / `ReferenceError` / `is not a function` lines. `tests/ui/screens/*` need no edit (none asserts an `escalated at` string).

- [ ] **Step 8: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): an escalation reason names a failed row, never a finished one

With no failed tree phase, escalationReason names the phase of the last
row whose status is failed, escalated, gate_failed, schema_invalid or
harness_error, else plain escalated, so an Integrate escalation no
longer reads 'escalated at mark_done'."
```

(Add another file to `git add` only if Step 6 or Step 7 required an edit to it, per the rule in Step 6.)

## Self-Review

- **Spec coverage:** Behavior "Unchanged: the tree branch" — not edited (Step 5 touches only the comment and the row loop), pinned by existing `test_escalation_reason_detail`, `noDetail`, `nameless`, and the new `both` case. "Changed: the row fallback" — Step 5; rules 1-3, the scan order, "a failure row followed by later non-failure rows" — Step 3 cases. "Error paths" — `bad` list (unchanged), `notArrays`, `null`/`5` rows in `noPhase`, `Object.prototype` names in `others`. "Consumers" — `test_fixture_new_alerts_escalation_reason`; no UI edits. "Contract comment" — Step 5. Tests 1-4 of the spec — Steps 1, 1, 3, 6 respectively. Verification — Steps 6-7.
- **Placeholder scan:** none; every code step carries the full code.
- **Type consistency:** `escalatedFixtures()` returns `[name, reason]` pairs used identically in both fixture tests; `_FAILURE_STATUSES` is defined and used only in Step 5; `mkRun(id, status, live, opts)` matches its definition at `tst_runs.qml:600`.
- **Review Focus:** each of the five lines names the Task 1 test that pins it.
<!-- task-pipeline: validated -->
