# 1.2 runs.js: newAlerts (card 45b4da97)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-controls-design.md` (S2):
"Alerts" (lines 109-136, chiefly 111-113 and 135-136) and "Testing" bullet 1
(lines 150-152). Parent story 7ad84a64. Blocked by adff6c85 (1.1 `controls` /
`controlError`), which is already on this branch (commits 0515d01, ccf5090).

## Starting point

`core/domain/runs.js` (`.pragma library`, 705 lines) already has everything the
alert decision needs, all pure and never throwing:

- `runState(run)` (runs.js:62-72) — `running | dead | parked | escalated |
  cancelled | done | unknown`; garbage gives `unknown`.
- `attention(runs)` (runs.js:232-241) — the escalated-or-dead selection this
  card's "needs a human" rule matches.
- `escalationReason(run)` (runs.js:251-275) — failed phase detail, else
  `"escalated at <phase>"`, else `"escalated"`.
- `runTitle(run)` (runs.js:305-308) — milestone id, else `shortId(run)`.
- Private helpers `_isObject`, `_arrayOr`, `_stringOr` (runs.js:81-83).

`newAlerts` does not exist anywhere yet. The file ends with the
`// ---- Run controls (S2 1.1) ----` section (runs.js:625-705).

## Scope

Add one pure function, `newAlerts(prevRuns, nextRuns)`, to `core/domain/runs.js`
in a new section appended at the end of the file (banner
`// ---- Run alerts (S2 1.2) ----`), with tests in
`tests/core/domain/tst_runs.qml`. Tests first.

Constraints (inherited from `docs/architecture.md` line 157, "`runs.js`, the am
run model: pure JS, never throws, and every input comes from `am`", and the
style of the 1.x runs.js cards):

- `var`/`function` style, no ES6 `const`/`let`/arrows, `_`-prefixed private
  helpers, one comment block above each function. No imports. No glyph literals:
  all text is plain ASCII, so `tests/architecture/test_icon_glyphs.py` is
  unaffected. `tests/architecture/test_layers.py` (domain imports only domain,
  no Qt) is unaffected.
- Never throws. Garbage input becomes the defaults described below.
- Run ids are compared with `===` on strings by linear scan, never by property
  lookup on a plain object, so ids such as `__proto__`, `constructor` or
  `toString` behave like any other id (same rule as runs.js:74-79).
- Inputs are never mutated. Existing functions and their tests are not changed.

### Out of scope

Owned by sibling cards: keeping the previous snapshot and calling `newAlerts`
(`RunStore`), resetting it to `null` on panel open or project switch (store),
`ui/components/RunToast.qml` (8 s timeout, stack of 3, Esc, Open), the
`RunIndicator` / sidebar count updates, the "Notify on escalation" setting in
`viewer-state.py`, `core/backend/runs/notify.py`, UI flow tests, and edits to
`docs/architecture.md`. No file under `ui/`, `core/stores/` or `core/backend/`
is touched. The toast's leading glyph (`‼`, spec line 116) is UI and not part of
any string this function returns.

## Behaviour

### `newAlerts(prevRuns, nextRuns)` → array of alerts

`prevRuns` and `nextRuns` are two consecutive snapshots: arrays of normalised
runs (the `normalizeRun` shape), as `RunStore` holds them.

**Alert shape.** Each alert is a fresh plain object with exactly the keys
`id`, `title`, `state`, `reason`, all strings:

| key | value |
|---|---|
| `id` | the run's `id` (the full id, not the short one) |
| `title` | `runTitle(run)` of the run in `nextRuns` |
| `state` | `"escalated"` or `"dead"` — the state the run entered |
| `reason` | escalated: `escalationReason(run)` of the run in `nextRuns`; dead: the exact text `process died` |

`state` is included beyond the card's id/title/reason so the toast can tell the
two cases apart without calling `runState` again; it costs nothing and is
pinned by the shape test.

**The rule (spec lines 111-113).** A run in `nextRuns` raises one alert when
`runState(nextRun)` is `escalated` or `dead` **and** differs from the state of
the run with the same id in `prevRuns`. Consequences, each pinned by a test:

1. **No previous snapshot.** When `prevRuns` is not an array (`null`, which is
   the store's "first snapshot after open", or `undefined`, or any garbage),
   the result is `[]` whatever `nextRuns` holds. Reopening never replays history.
2. **Already in that state.** escalated → escalated and dead → dead raise none
   (spec line 152, "none for a run already escalated").
3. **Entering.** running, parked, cancelled, done or unknown → escalated or dead
   raises one alert.
4. **Switching between the two.** escalated → dead and dead → escalated each
   raise one alert: the run entered a different needs-a-human state, with a
   different reason.
5. **Absent from the previous snapshot.** A run whose id is not in a
   `prevRuns` array (including `prevRuns = []`) counts as not having been
   escalated or dead, so a newly listed run that is already escalated or dead
   raises one alert. Only a non-array `prevRuns` suppresses alerts wholesale.
   (An empty array means "the panel saw zero runs", which is a real snapshot.)
6. **One alert per transition (spec line 152).** Calling again with the same
   snapshot as both arguments (`newAlerts(next, next)`) gives `[]`; a run that
   leaves and re-enters (escalated → running → escalated over three snapshots)
   alerts on each entry.
7. **Leaving is silent.** escalated or dead → anything else, and a run that
   disappears from `nextRuns`, raise nothing.

**Ids and duplicates.**

- A run is matched across snapshots by `id`, which must be a non-empty string.
  A run in `nextRuns` whose id is not a non-empty string never alerts (it
  cannot be told apart from another one, and garbage normalises to id `""`).
- If `nextRuns` holds the same id more than once, at most one alert is raised
  for that id, from its first qualifying occurrence (the first occurrence whose
  state is escalated or dead and differs from the previous state).
- If `prevRuns` holds the same id more than once, the first occurrence is the
  previous state (snapshots are newest first, as everywhere in runs.js).

**Order.** Alerts follow the order of their runs in `nextRuns`.

**Garbage.** `nextRuns` that is not an array gives `[]`. Entries of either
array that are not objects (`null`, numbers, strings, arrays) are skipped: in
`prevRuns` they match no id; in `nextRuns` they raise nothing. A
prototype-less object entry does not throw. Neither array nor any run in it is
mutated, and every call returns a new array of new alert objects.

## Tests

Tier for all: pure domain QML `TestCase` in `tests/core/domain/tst_runs.qml`
(`TestCase { name: "DomainRuns" }`, `Runs` = runs.js), per `docs/architecture.md`
"Tests" (line 194) and the parent spec's Testing bullet (lines 150-152): the
function is pure and needs no store, UI or backend, so a store or UI test would
only add setup. Build runs with the existing `mkRun(id, status, live, opts)`
helper (tst_runs.qml:265): running = `mkRun(id, "started", true)`, dead =
`mkRun(id, "started", false)` or `mkRun(id, "started", null)`, parked =
`"stopped"`, escalated = `"escalated"`. Escalated runs that need a specific
reason pass `opts.tree` with a failed phase (e.g. `{stories: [], subtasks:
[{card_id: "t1", phases: [{name: "review", status: "failed"}]}]}` →
`"escalated at review"`).

| test | proves |
|---|---|
| `test_new_alerts_first_snapshot` | `prevRuns` `null`, `undefined`, `5`, `"x"`, `{}` with a `nextRuns` holding an escalated and a dead run: `[]` each time (rule 1) |
| `test_new_alerts_entering_escalated` | running → escalated gives exactly one alert; keys exactly `id,reason,state,title`; `id` the full id, `title` `"m1"`, `state` `"escalated"`, `reason` `"escalated at review"` from the tree; with `milestone_id: ""` the title is the short id `"…"+last 8` (rule 3) |
| `test_new_alerts_entering_dead` | running → dead (live false) and parked → dead (lease null) each give one alert with `state` `"dead"`, `reason` `"process died"` (rule 3) |
| `test_new_alerts_from_each_state` | from parked, cancelled, done and unknown (status `"weird"`) into escalated: one alert each; into parked, running, cancelled or done from running: none (rules 3, 7) |
| `test_new_alerts_already_in_state` | escalated → escalated and dead → dead: `[]`, including when the reason text changed between snapshots (rule 2) |
| `test_new_alerts_switch_between` | escalated → dead gives one `dead` alert; dead → escalated gives one `escalated` alert (rule 4) |
| `test_new_alerts_one_per_transition` | `newAlerts(next, next)` is `[]`; across snapshots s0 running, s1 escalated, s2 escalated, s3 running, s4 escalated the calls (s0,s1)…(s3,s4) give 1, 0, 0, 1 alerts (rule 6) |
| `test_new_alerts_absent_and_vanished` | `prevRuns = []` with an escalated next run: one alert; a run present in prev and absent from next: nothing; a mix of three runs (one entering, one already escalated, one running) gives only the entering one, in `nextRuns` order when two enter (rule 5, order) |
| `test_new_alerts_ids` | ids `__proto__`, `constructor`, `toString` match their own previous entry like any id (already escalated → none; entering → one); a next run with id `""`, a number or missing never alerts; duplicate id in next gives one alert; duplicate id in prev uses the first occurrence (first escalated, second running → no alert) |
| `test_new_alerts_garbage` | `nextRuns` `null`, `undefined`, `5`, `"x"`, `{}`: `[]`; arrays with `null`, `5`, `"x"`, `[]` and a prototype-less object among real runs: real runs still alert, garbage skipped, no throw; `Runs.normalizeRun(undefined)` in next raises nothing |
| `test_new_alerts_fresh_and_pure` | two calls return distinct arrays and distinct alert objects; mutating a returned alert does not change the next call's result; `JSON.stringify` of both input arrays is unchanged after the call |

Verification: `bash tests/run.sh` green (filter while iterating:
`bash tests/run.sh tst_runs`). Existing `tst_runs.qml` tests and the
`tests/architecture/` suite (layering, no duplicated components, icon glyph
rules) pass unchanged. There is no typecheck or lint step.

## Hand-off to the planner

**Files:**
- Modify: `core/domain/runs.js` (append the `Run alerts (S2 1.2)` section at the
  end of the file, after `controlError`)
- Test: `tests/core/domain/tst_runs.qml` (add `test_new_alerts_*` before the
  closing brace, after the `test_control_error_*` tests)

**Interfaces consumed** (existing, unchanged): `runState(run) -> string`,
`escalationReason(run) -> string`, `runTitle(run) -> string`, `_isObject`,
`_arrayOr`.

**Interface produced** (consumed later by the RunStore / RunToast / notify cards):
- `newAlerts(prevRuns, nextRuns) -> [{id: string, title: string, state: "escalated"|"dead", reason: string}]`

This is one function with one test cycle; plan it as a single task (tests,
fail, implement, pass, commit), or two at most if the planner splits the
transition rule from the id/garbage hardening. Do not split it per test.

## Review focus (inputs the tests above must not let slip)

1. `prevRuns = []` versus `prevRuns = null` — the empty array is a real
   snapshot and must alert on an already escalated run; only non-arrays
   suppress.
2. Escalated → dead (or back) — must alert once, not be treated as "already
   needs attention" just because `attention()` would list it both times.
3. Run id `__proto__` / `constructor` — a lookup object keyed by id would
   misreport the previous state; matching must be a linear `===` scan.
4. Duplicate ids within one snapshot — at most one alert per id per call.
5. A dead run whose `escalationReason` would say `"escalated"` — dead runs must
   use `process died`, never the escalation text.

---

# runs.js newAlerts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `newAlerts(prevRuns, nextRuns)` to `core/domain/runs.js`, test-first, with every test in `tests/core/domain/tst_runs.qml`.

**Architecture:** One pure, never-throwing function appended to the existing `.pragma library` module in a new `// ---- Run alerts (S2 1.2) ----` section after `controlError` (the current end of the file). It walks `nextRuns` in order, keeps object runs with a non-empty string id whose `runState` is `escalated` or `dead`, looks up the previous state by a linear `===` scan of `prevRuns` (first occurrence wins, `""` when absent), skips runs whose state did not change and ids already alerted in this call, and builds a fresh `{id, title, state, reason}` per alert from the existing `runTitle` and `escalationReason`. A non-array `prevRuns` or `nextRuns` returns `[]` before any of that.

**Tech Stack:** QML JavaScript (`.pragma library`, `var`/function style, Qt 6 V4 engine), QtTest `TestCase` run by `qmltestrunner` through `tests/run.sh`, pytest architecture tests (must pass unchanged).

**Spec:** `docs/superpowers/specs/1-2-runs-js-newalerts-45b4da97.md` (prepended above). Parent design: `docs/superpowers/specs/2026-10-03-am-run-controls-design.md` (S2), "Alerts" lines 109-136.

**Worktree / branch:** all paths are relative to `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/ctl/task-1-2-runs-js-newalerts-45b4da97`, branch `ctl/task-1-2-runs-js-newalerts-45b4da97`. Run every command from that directory.

## Global Constraints

- `core/domain/runs.js` stays `.pragma library`; `var`/`function` style, no ES6 `const`/`let`/arrows, `_`-prefixed private helpers, one comment block above each function. No imports.
- No glyph literals in `runs.js`: all text it adds is plain ASCII (`tests/architecture/test_icon_glyphs.py` must stay green). The test file already compares against `"…"` (see `test_run_title`), and the new tests do the same.
- Never throws. Garbage input becomes `[]` or is skipped as described in the spec.
- Run ids are compared with `===` on strings by linear scan, never by property lookup on a plain object (`__proto__`, `constructor`, `toString` behave like any other id).
- Inputs are never mutated; every call returns a new array of new alert objects.
- Existing functions and their tests are not changed. No file under `ui/`, `core/stores/` or `core/backend/` is touched; `docs/architecture.md` is not edited.
- Alert shape: exactly the keys `id`, `title`, `state`, `reason`, all strings; `state` is `"escalated"` or `"dead"`; a dead alert's reason is exactly `process died`.
- Verification: `bash tests/run.sh` green (filter while iterating: `bash tests/run.sh tst_runs`; the filter also matches `tests/ui/screens/tst_runs_screen.qml` and `tests/ui/tst_runs_flow.qml`, which must stay green). No typecheck, no lint.

## Review Focus

1. `prevRuns = []` versus `prevRuns = null` — the empty array is a real snapshot and must alert on an already escalated or dead run; only non-arrays suppress. Pinned by `test_new_alerts_first_snapshot` and `test_new_alerts_absent_and_vanished`.
2. Escalated → dead and dead → escalated — one alert each, with the new state and its own reason, even though `attention()` lists the run both times. Pinned by `test_new_alerts_switch_between`.
3. Run ids `__proto__`, `constructor`, `toString` — an id-keyed lookup object would misreport the previous state (assigning to `__proto__` is ignored, `constructor` reads a function); the already-escalated case must stay silent. Pinned by `test_new_alerts_ids`.
4. The same id twice in one snapshot (in `nextRuns` or in `prevRuns`) — at most one alert per id per call; the first `prevRuns` occurrence is the previous state. Pinned by `test_new_alerts_ids`.
5. A dead run whose tree has a failed phase — reason must be `process died`, never `escalated at review`. Pinned by `test_new_alerts_entering_dead` and `test_new_alerts_switch_between`.

## File Structure

- Modify: `core/domain/runs.js` — append a `// ---- Run alerts (S2 1.2) ----` section after `controlError` (currently lines 694-705, the end of the file): `_REASON_DEAD`, `_isRunId`, `_previousState`, `_hasAlert`, `newAlerts`.
- Modify: `tests/core/domain/tst_runs.qml` — insert helpers and eleven `test_new_alerts_*` functions immediately before the final line of the file, the lone `}` closing `TestCase { name: "DomainRuns" ... }` (currently line 1302, right after `test_control_error_fallback`). Existing content, including `mkRun` (line 267), is untouched.

The spec allows one task or two; this is one function with one test cycle, so it is one task.

---

### Task 1: `newAlerts(prevRuns, nextRuns)`

**Files:**
- Modify: `core/domain/runs.js` (append after line 705, end of file)
- Test: `tests/core/domain/tst_runs.qml` (insert before the final `}`)

**Interfaces:**
- Consumes (existing, unchanged): `runState(run)` → `"running" | "dead" | "parked" | "escalated" | "cancelled" | "done" | "unknown"`; `escalationReason(run)` → string; `runTitle(run)` → milestone id, else `shortId(run)` (`"…"` + last 8 chars of the id); `_isObject(v)` → bool (true for non-null, non-array objects, including prototype-less ones). Test helper `mkRun(id, status, live, opts)`: `live === null` means `lease: null`, otherwise `lease = {pid:1, host:"h", heartbeat_at:"", accepting:true, live:live}`; `opts.milestone_id` defaults to `"m1"`; `opts.tree` defaults to `{stories: [], subtasks: []}`.
- Produces: `newAlerts(prevRuns, nextRuns) -> [{id: string, title: string, state: "escalated"|"dead", reason: string}]`.

- [ ] **Step 1: Write the failing tests**

Insert immediately before the final `}` of `tests/core/domain/tst_runs.qml` (i.e. after the closing `  }` of `test_control_error_fallback`):

```qml

  // ---- S2 1.2: run alerts ------------------------------------------------------------------

  // A tree whose subtask t1 failed review: escalationReason gives "escalated at review".
  function alTree() {
    return { stories: [], subtasks: [{ card_id: "t1", phases: [{ name: "review", status: "failed" }] }] }
  }
  function alRunning(id) { return mkRun(id, "started", true) }
  function alDead(id) { return mkRun(id, "started", false) }
  function alEscalated(id) { return mkRun(id, "escalated", null, { tree: alTree() }) }

  // The alerts' ids (or states), comma-joined, in order.
  function alIds(alerts) {
    var out = []
    for (var i = 0; i < alerts.length; i++) out.push(alerts[i].id)
    return out.join(",")
  }
  function alStates(alerts) {
    var out = []
    for (var i = 0; i < alerts.length; i++) out.push(alerts[i].state)
    return out.join(",")
  }

  function checkAlert(a, id, title, state, reason, label) {
    compare(Object.keys(a).sort().join(","), "id,reason,state,title", label + " keys")
    compare(a.id, id, label + " id")
    compare(a.title, title, label + " title")
    compare(a.state, state, label + " state")
    compare(a.reason, reason, label + " reason")
  }

  function test_new_alerts_first_snapshot() {
    var next = [alEscalated("r1"), alDead("r2")]
    var prevs = [null, undefined, 5, "x", {}, Object.create(null), true]
    for (var i = 0; i < prevs.length; i++) {
      var a = Runs.newAlerts(prevs[i], next)
      compare(Array.isArray(a), true, "an array for prev " + i)
      compare(a.length, 0, "no alerts for prev " + i)
    }
    compare(Runs.newAlerts(null, []).length, 0, "null prev, empty next")
  }

  function test_new_alerts_entering_escalated() {
    var id = "run-20261004-0123456789abcdef"
    var a = Runs.newAlerts([alRunning(id)], [mkRun(id, "escalated", null, { tree: alTree() })])
    compare(a.length, 1, "one alert")
    checkAlert(a[0], id, "m1", "escalated", "escalated at review", "with milestone")

    var b = Runs.newAlerts([alRunning(id)], [mkRun(id, "escalated", null, { milestone_id: "", tree: alTree() })])
    compare(b.length, 1, "one alert without a milestone")
    checkAlert(b[0], id, "…89abcdef", "escalated", "escalated at review", "short id title")

    var detailTree = { stories: [], subtasks: [{ card_id: "t1",
                       phases: [{ name: "review", status: "failed", detail: "3 tests failed" }] }] }
    var c = Runs.newAlerts([alRunning(id)], [mkRun(id, "escalated", true, { tree: detailTree })])
    compare(c.length, 1, "one alert with a detail")
    checkAlert(c[0], id, "m1", "escalated", "3 tests failed", "detail reason")

    var d = Runs.newAlerts([alRunning(id)], [mkRun(id, "escalated", null)])
    compare(d.length, 1, "one alert with no tree")
    compare(d[0].reason, "escalated", "bare escalated reason")
  }

  function test_new_alerts_entering_dead() {
    var a = Runs.newAlerts([alRunning("r1")], [mkRun("r1", "started", false)])
    compare(a.length, 1, "running -> dead (live false)")
    checkAlert(a[0], "r1", "m1", "dead", "process died", "live false")

    var b = Runs.newAlerts([mkRun("r1", "stopped", null)], [mkRun("r1", "started", null)])
    compare(b.length, 1, "parked -> dead (lease null)")
    checkAlert(b[0], "r1", "m1", "dead", "process died", "lease null")

    var c = Runs.newAlerts([alRunning("r1")], [mkRun("r1", "started", false, { tree: alTree() })])
    compare(c.length, 1, "dead with a failed phase")
    compare(c[0].reason, "process died", "never the escalation text")
  }

  function test_new_alerts_from_each_state() {
    var froms = [["parked", mkRun("r", "stopped", null)], ["cancelled", mkRun("r", "cancelled", null)],
                 ["done", mkRun("r", "done", null)], ["unknown", mkRun("r", "weird", true)],
                 ["running", alRunning("r")]]
    for (var i = 0; i < froms.length; i++) {
      var e = Runs.newAlerts([froms[i][1]], [alEscalated("r")])
      compare(e.length, 1, froms[i][0] + " -> escalated")
      compare(e[0].state, "escalated", froms[i][0] + " -> escalated state")
      var d = Runs.newAlerts([froms[i][1]], [alDead("r")])
      compare(d.length, 1, froms[i][0] + " -> dead")
      compare(d[0].state, "dead", froms[i][0] + " -> dead state")
    }

    var quiet = [["parked", mkRun("r", "stopped", null)], ["running", alRunning("r")],
                 ["cancelled", mkRun("r", "cancelled", null)], ["done", mkRun("r", "done", null)],
                 ["unknown", mkRun("r", "weird", true)]]
    for (var j = 0; j < quiet.length; j++) {
      compare(Runs.newAlerts([alRunning("r")], [quiet[j][1]]).length, 0, "running -> " + quiet[j][0])
      compare(Runs.newAlerts([alEscalated("r")], [quiet[j][1]]).length, 0, "escalated -> " + quiet[j][0])
      compare(Runs.newAlerts([alDead("r")], [quiet[j][1]]).length, 0, "dead -> " + quiet[j][0])
    }
  }

  function test_new_alerts_already_in_state() {
    compare(Runs.newAlerts([alEscalated("r")], [alEscalated("r")]).length, 0, "escalated -> escalated")
    compare(Runs.newAlerts([mkRun("r", "escalated", null)], [alEscalated("r")]).length, 0,
            "escalated -> escalated with a new reason")
    compare(Runs.newAlerts([alDead("r")], [alDead("r")]).length, 0, "dead -> dead")
    compare(Runs.newAlerts([mkRun("r", "started", false)], [mkRun("r", "started", null)]).length, 0,
            "dead (live false) -> dead (lease null)")
  }

  function test_new_alerts_switch_between() {
    var a = Runs.newAlerts([alEscalated("r")], [mkRun("r", "started", false, { tree: alTree() })])
    compare(a.length, 1, "escalated -> dead")
    checkAlert(a[0], "r", "m1", "dead", "process died", "escalated -> dead")

    var b = Runs.newAlerts([alDead("r")], [alEscalated("r")])
    compare(b.length, 1, "dead -> escalated")
    checkAlert(b[0], "r", "m1", "escalated", "escalated at review", "dead -> escalated")
  }

  function test_new_alerts_one_per_transition() {
    var next = [alEscalated("a"), alDead("b"), alRunning("c")]
    compare(Runs.newAlerts(next, next).length, 0, "same snapshot twice")

    var snaps = [[alRunning("r")], [alEscalated("r")], [alEscalated("r")], [alRunning("r")], [alEscalated("r")]]
    var expected = [1, 0, 0, 1]
    for (var i = 0; i < expected.length; i++)
      compare(Runs.newAlerts(snaps[i], snaps[i + 1]).length, expected[i], "s" + i + " -> s" + (i + 1))
  }

  function test_new_alerts_absent_and_vanished() {
    var e = Runs.newAlerts([], [alEscalated("r")])
    compare(e.length, 1, "empty prev, escalated next")
    compare(e[0].state, "escalated", "empty prev state")
    var d = Runs.newAlerts([], [alDead("r")])
    compare(d.length, 1, "empty prev, dead next")
    compare(d[0].state, "dead", "empty prev dead state")
    compare(alIds(Runs.newAlerts([alRunning("other")], [alEscalated("r")])), "r", "id not in prev")

    compare(Runs.newAlerts([alEscalated("r")], []).length, 0, "vanished escalated run")
    compare(Runs.newAlerts([alEscalated("r"), alDead("d")], [alRunning("x")]).length, 0, "vanished runs")

    var mix = Runs.newAlerts([alRunning("a"), alEscalated("b"), alRunning("c")],
                             [alEscalated("a"), alEscalated("b"), alRunning("c")])
    compare(alIds(mix), "a", "only the entering run")

    var two = Runs.newAlerts([alRunning("a"), alRunning("b"), alRunning("c")],
                             [alDead("c"), alRunning("b"), alEscalated("a")])
    compare(alIds(two), "c,a", "nextRuns order")
    compare(alStates(two), "dead,escalated", "states in nextRuns order")
  }

  function test_new_alerts_ids() {
    var names = ["__proto__", "constructor", "toString"]
    for (var i = 0; i < names.length; i++) {
      var n = names[i]
      compare(Runs.newAlerts([alEscalated(n)], [alEscalated(n)]).length, 0, n + " already escalated")
      compare(Runs.newAlerts([alDead(n)], [alDead(n)]).length, 0, n + " already dead")
      var entering = Runs.newAlerts([alRunning(n)], [alEscalated(n)])
      compare(entering.length, 1, n + " entering")
      compare(entering[0].id, n, n + " id")
      compare(alIds(Runs.newAlerts([alEscalated("other")], [alEscalated(n)])), n, n + " absent from prev")
    }

    compare(Runs.newAlerts([], [mkRun("", "escalated", null)]).length, 0, "empty id")
    compare(Runs.newAlerts([], [mkRun(5, "escalated", null)]).length, 0, "number id")
    compare(Runs.newAlerts([], [mkRun(null, "started", false)]).length, 0, "null id")
    var noId = alEscalated("x")
    delete noId.id
    compare(Runs.newAlerts([], [noId]).length, 0, "missing id")

    var dup = Runs.newAlerts([], [alEscalated("r"), alEscalated("r")])
    compare(dup.length, 1, "duplicate id in next")
    var firstQualifying = Runs.newAlerts([], [alRunning("r"), alEscalated("r"), alDead("r")])
    compare(firstQualifying.length, 1, "one alert for three occurrences")
    compare(firstQualifying[0].state, "escalated", "from the first qualifying occurrence")

    compare(Runs.newAlerts([alEscalated("r"), alRunning("r")], [alEscalated("r")]).length, 0,
            "duplicate id in prev: first occurrence (escalated) wins")
    compare(Runs.newAlerts([alRunning("r"), alEscalated("r")], [alEscalated("r")]).length, 1,
            "duplicate id in prev: first occurrence (running) wins")
  }

  function test_new_alerts_garbage() {
    var nexts = [null, undefined, 5, "x", {}, Object.create(null), true]
    for (var i = 0; i < nexts.length; i++) {
      var a = Runs.newAlerts([], nexts[i])
      compare(Array.isArray(a), true, "an array for next " + i)
      compare(a.length, 0, "no alerts for next " + i)
    }

    var bare = Object.create(null)
    var prev = [null, 5, "x", [], bare, alRunning("a"), undefined]
    var next = [null, alEscalated("a"), 5, "x", [], bare, alDead("b"), undefined]
    var mixed = Runs.newAlerts(prev, next)
    compare(alIds(mixed), "a,b", "real runs alert, garbage skipped")
    compare(alStates(mixed), "escalated,dead", "garbage skipped, states")

    var np = Object.create(null)
    np.id = "np"
    np.status = "escalated"
    var fromBare = Runs.newAlerts([bare], [np])
    compare(fromBare.length, 1, "a prototype-less run with an id alerts")
    checkAlert(fromBare[0], "np", "…np", "escalated", "escalated", "prototype-less run")

    compare(Runs.newAlerts([], [Runs.normalizeRun(undefined)]).length, 0, "normalised garbage")
    var normalised = Runs.normalizeRun({ row: { id: "rz", status: "started" },
                                         status: { run: { milestone_id: "m9", status: "escalated" } } })
    var fromNormalised = Runs.newAlerts([], [normalised])
    compare(fromNormalised.length, 1, "a normalised escalated run")
    checkAlert(fromNormalised[0], "rz", "m9", "escalated", "escalated", "normalised run")
  }

  function test_new_alerts_fresh_and_pure() {
    var prev = [alRunning("a"), alEscalated("b")]
    var next = [alEscalated("a"), alEscalated("b"), alDead("c")]
    var prevJson = JSON.stringify(prev)
    var nextJson = JSON.stringify(next)

    var x = Runs.newAlerts(prev, next)
    var y = Runs.newAlerts(prev, next)
    compare(alIds(x), "a,c", "first call")
    verify(x !== y, "distinct arrays")
    verify(x[0] !== y[0], "distinct alert objects")
    verify(x[1] !== y[1], "distinct alert objects (second)")

    x[0].title = "changed"
    x[0].reason = "changed"
    x.push({ id: "junk" })
    var z = Runs.newAlerts(prev, next)
    compare(alIds(z), "a,c", "mutating a result does not change the next one")
    checkAlert(z[0], "a", "m1", "escalated", "escalated at review", "after mutation")

    compare(JSON.stringify(prev), prevJson, "prevRuns unchanged")
    compare(JSON.stringify(next), nextJson, "nextRuns unchanged")
    compare(prev.length, 2, "prevRuns length")
    compare(next.length, 3, "nextRuns length")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_runs`
Expected: pytest passes; under `== tests/core/domain/tst_runs.qml` the eleven `test_new_alerts_*` functions print `FAIL!  : qmltestrunner::DomainRuns::test_new_alerts_...() ... Property 'newAlerts' of object [object Object] is not a function` (Totals: 61 passed, 11 failed); every existing test still passes; `tst_runs_screen.qml` and `tst_runs_flow.qml` still print 0 failed; the script exits non-zero (the `is not a function` lines are echoed by the script's error grep). If any test fails for another reason (a syntax error in the inserted QML makes the whole file fail to load, with no `Totals: 61 passed`), fix the test code before going on.

- [ ] **Step 3: Write the implementation**

Append to the end of `core/domain/runs.js` (after the closing `}` of `controlError`):

```js

// ---- Run alerts (S2 1.2) -----------------------------------------------------------------
//
// Which runs newly need a human between two snapshots, for the toast and the
// desktop notification. Pure and never throwing, like the rest of this file.
// Keeping the previous snapshot (and resetting it to null) is the store's job.

var _REASON_DEAD = "process died"

// A run id a run can be matched by: a non-empty string.
function _isRunId(id) { return typeof id === "string" && id !== "" }

// runState of the first object run in list with this id, or "" when there is
// none. Linear === scan, so ids such as `__proto__` match like any other id.
function _previousState(list, id) {
  for (var i = 0; i < list.length; i++) {
    if (_isObject(list[i]) && list[i].id === id) return runState(list[i])
  }
  return ""
}

// Has an alert for this id already been raised in this call?
function _hasAlert(alerts, id) {
  for (var i = 0; i < alerts.length; i++) {
    if (alerts[i].id === id) return true
  }
  return false
}

// One fresh {id, title, state, reason} for each run in nextRuns, in its order,
// that is now escalated or dead and was not in that same state in prevRuns (a
// run absent from prevRuns was neither). A non-array prevRuns -- null is the
// store's "no previous snapshot" -- or nextRuns gives []. At most one alert per
// id; the first prevRuns occurrence of an id is its previous state. A dead
// run's reason is always "process died".
function newAlerts(prevRuns, nextRuns) {
  if (!Array.isArray(prevRuns) || !Array.isArray(nextRuns)) return []
  var out = []
  for (var i = 0; i < nextRuns.length; i++) {
    var run = nextRuns[i]
    if (!_isObject(run) || !_isRunId(run.id)) continue
    var state = runState(run)
    if (state !== "escalated" && state !== "dead") continue
    if (_previousState(prevRuns, run.id) === state) continue
    if (_hasAlert(out, run.id)) continue
    out.push({
      id: run.id,
      title: runTitle(run),
      state: state,
      reason: state === "dead" ? _REASON_DEAD : escalationReason(run)
    })
  }
  return out
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_runs`
Expected: pytest passes (including `tests/architecture/`); `tst_runs.qml` prints `Totals: 72 passed, 0 failed`, no `FAIL!` lines, no `TypeError`/`ReferenceError` lines; `tst_runs_screen.qml` and `tst_runs_flow.qml` print 0 failed; exit status 0.

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest passes (including `tests/architecture/test_layers.py` and `tests/architecture/test_icon_glyphs.py`); every `tst_*.qml` prints `Totals:` with 0 failed; no `FAIL!`, `TypeError` or `ReferenceError` lines; exit status 0.

- [ ] **Step 6: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): newAlerts says which runs newly need a human between two snapshots (card 45b4da97)"
```

---

## Self-Review

- **Spec coverage:** alert shape and exact keys (`checkAlert` in every shape-bearing test); rule 1 non-array prev (`test_new_alerts_first_snapshot`); rule 2 already in state, incl. changed reason (`test_new_alerts_already_in_state`); rule 3 entering from running, parked, cancelled, done, unknown (`test_new_alerts_entering_escalated`, `_entering_dead`, `_from_each_state`); rule 4 switching (`test_new_alerts_switch_between`); rule 5 absent / `[]` prev (`test_new_alerts_absent_and_vanished`); rule 6 one per transition and re-entry (`test_new_alerts_one_per_transition`); rule 7 leaving and vanishing silent (`_from_each_state`, `_absent_and_vanished`); ids, bad ids, duplicates in next and prev (`test_new_alerts_ids`); order (`_absent_and_vanished`, `_garbage`); garbage arrays, entries, prototype-less objects, normalised garbage (`test_new_alerts_garbage`); fresh results and no mutation (`test_new_alerts_fresh_and_pure`). Title as milestone else short id, reason from the tree / detail / bare (`_entering_escalated`). Section banner and placement after `controlError`: Step 3. Verification `bash tests/run.sh`: Step 5.
- **Placeholder scan:** none; every code step carries the full code.
- **Type consistency:** `newAlerts`, `_REASON_DEAD`, `_isRunId`, `_previousState`, `_hasAlert`, and test helpers `alTree`, `alRunning`, `alDead`, `alEscalated`, `alIds`, `alStates`, `checkAlert` are named identically wherever used; none clashes with an existing name in either file.
- **Review Focus:** all five lines are pinned by named tests in Task 1.
<!-- task-pipeline: validated -->
