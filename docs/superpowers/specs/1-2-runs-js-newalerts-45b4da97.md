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
