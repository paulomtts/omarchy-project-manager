<!-- task-pipeline: validated -->
# 1.2 runs.js: card mapping, rollups, attention, error text (card 791537cf)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` ("Domain model", "Data sources", "Errors", "Testing"). Parent story 10d626dc "Run domain model". Blocked by 1.1 (797d9382, done).

## Starting point

In this worktree, 1.1 is on disk. `core/domain/runs.js` already has `normalizeRun(raw)` (returns `{id, repo_dir, milestone_id, status, lease, rows, tree:{stories, subtasks}}`) and `runState(run)` (returns `running | dead | parked | escalated | cancelled | done | unknown`). `tests/core/domain/tst_runs.qml` (TestCase "DomainRuns") covers both. The main checkout at `/home/mtts/Code/omarchy-project-manager` does not have these files, but this worktree does. 1.2 only adds code to the files. It does not change `normalizeRun`, `runState` or their existing tests.

## Scope

Add five pure functions to `core/domain/runs.js`, with tests in `tests/core/domain/tst_runs.qml`. Write the tests first.

Out of scope: RunStore and any other store, the backend helpers (`runs-snapshot.py`, `runs-watch.py`, `runs-logs.py`), UI components and screens, Navigator, Shortcuts, edits to `docs/architecture.md`, glyphs and colours, and the `stale` flag (that is a store concern).

Constraints: the file stays `.pragma library` and uses `var`/function style. No imports are needed. If any are added, they may only be `core/domain/*.js` via `.import`. No glyph literals. No function throws. Garbage input (null, non-array, non-object, missing fields) becomes a default result. Card ids are compared with `===` on strings, using linear scans, or prototype-less maps with `hasOwnProperty`. Ids such as `constructor`, `__proto__` and `toString` must behave like any other id.

## Shared rules

- Input `runs` is an array of normalised runs, i.e. the output of `normalizeRun`. A non-array is treated as `[]`.
- **Synthetic ids.** `integrate`, `bases`, and any id starting with `base-` never match a card. They are never counted in a rollup.
- **Touches.** A run touches card id C (non-empty, not synthetic) when C equals `run.milestone_id`, any `run.tree.stories[].card_id`, or any `run.tree.subtasks[].card_id`.
- **Non-terminal.** A run is non-terminal when its `runState` is `running` or `dead` (status `started`). This follows the spec's definition: a run is finished when its status is done, escalated, stopped or cancelled.
- **Newest.** `normalizeRun` drops `started_at`, so recency is not stored on the run. If both runs carry a string `started_at` (for example, the store copied it from the `am runs` row), the later ISO string is newer. Otherwise the earlier index in `runs` is newer, since the input is taken as newest-first. 1.2 must not change `normalizeRun` to add the field. Tests pin this rule.
- **Winning run for C.** Take the newest non-terminal run that touches C. If there is none, take the newest run that touches C and mark the result `dimmed`.

## Functions and observable behaviour

**`cardRunState(runs, cardId)`** returns `{state, runId, dimmed, phase, attempt}`.
- No run touches the card (this includes a synthetic or empty `cardId`): `{state:"none", runId:"", dimmed:false, phase:"", attempt:0}`.
- Otherwise, `state` comes from the winning run's `runState`:
  - `running`, `dead`, `parked` and `escalated` pass through.
  - `done`, `cancelled` and `unknown` become `none`.
  - `runId` is still set, and `dimmed` follows the winning-run rule.
- `phase` and `attempt` are filled only when C is a `tree.subtasks[].card_id` in the winning run:
  - `phase` is the `name` of the subtask's last entry in `phases`.
  - `attempt` is that phase's `attempts.length`. If the last attempt has a numeric `attempt`/`n` field, that value is used instead.
  - For stories and milestones, and whenever the shape is missing, `phase` is `""` and `attempt` is `0`. The tree shape is provisional, as in 1.1, and the tests pin it.
- The result never reads brd status.

**`rollup(runs, card)`** returns `{running, parked, escalated, done, pending, total}`, all integers.
- `card` is a brd card object, and its `id` is used.
- The rollup counts only am `rows` from the winning run for `card.id`. A row is counted only when it meets both conditions:
  - its `card_id` is a subtask in that run's `tree.subtasks` and is not synthetic;
  - when `card.id` is a story, it belongs to that story. Membership is either the row's subtask appearing in `tree.stories[k].subtasks`, where `tree.stories[k].card_id === card.id` and entries are id strings or `{card_id}`, or the subtask entry having `story_id === card.id`.
- When `card.id` is the run's `milestone_id`, every qualifying subtask row in the run is counted.
- When `card.id` is a subtask (it appears only in `tree.subtasks`, not as a story or the milestone), only rows whose `card_id === card.id` are counted. The story-membership check does not apply.
- A row is classified by its `status`:
  - `running`/`started` → running
  - `parked`/`stopped` → parked
  - `escalated`/`failed` → escalated
  - `done` → done
  - anything else → pending
- `total` is the sum of the five counts. When no run touches the card, or the card is garbage, every count is 0.
- The function never reads brd status and does not touch `Board.subtreeCounts`.

**`attention(runs)`** returns the runs whose `runState` is `escalated` or `dead`, in input order. The objects are the same ones that were passed in. A non-array returns `[]`.

**`escalationReason(run)`**
- The function walks `run.tree.subtasks[].phases[]` in order to find the first phase whose `status` is `failed`.
- It returns that phase's non-empty `detail`. If the phase has none, it uses the `detail` of the phase's last attempt that has one.
- If a failed phase exists but has no detail anywhere, the result is `"escalated at <phase name>"`.
- If there is no failed phase, the result is `"escalated at <phase>"`, where the phase comes from the last `rows[]` entry with a non-empty `phase`.
- If no phase can be found, or the input is garbage, the result is `"escalated"`.

**`errorText(error)`**
- Accepts either the full envelope `{ok:false, error:{type, message}}` or the bare `{type, message}`.
- The result is `"<type>: <message>"` when both are non-empty, otherwise whichever one is non-empty. If neither is, or the input is garbage, it is `"unknown error"`.
- An `ok:true` envelope returns `""`.
- Values are coerced with `String`. Each value is trimmed.

## Tests (all in `tests/core/domain/tst_runs.qml`, tier: pure domain QML TestCase per docs/architecture.md "Tests"; no store/UI/backend/contract tests)

All tests below go in `tst_runs.qml`.

| Test | What it checks |
|---|---|
| `test_card_maps_story_subtask_milestone` | A card matches through `stories[].card_id`, `subtasks[].card_id` and `milestone_id`. An unrelated id gives `none`. |
| `test_card_synthetic_ids_never_match` | `integrate`, `bases` and `base-x` give `none`, even when they are present in the tree, in rows or as `milestone_id`. |
| `test_card_newest_nonterminal_wins` | A card in an older `running` run and a newer `done` run resolves to the running run, with `dimmed` false. `dead` counts as non-terminal. |
| `test_card_all_terminal_newest_dimmed` | `parked`, `escalated`, `done` and `cancelled` cases each resolve to the newest run, with `dimmed` true and the state mapped (`done`/`cancelled` give `none` with `runId` set). |
| `test_card_newest_by_started_at_then_order` | `started_at` decides when both runs have it. Otherwise the earlier index wins. |
| `test_card_subtask_phase_attempt` | A subtask gets `phase` and `attempt`. A story or milestone gets `""` and `0`. Missing `phases`/`attempts` are tolerated. |
| `test_card_ignores_brd_status` | A `status` field on the card or brd side has no effect. |
| `test_card_proto_ids` | Card ids `__proto__`, `constructor` and `toString` match only when they are really present, and never throw. |
| `test_card_garbage` | Non-array runs, a null run inside the array, and a null or empty cardId all give the `none` default. |
| `test_rollup_milestone` | Counts are correct for every status bucket. `total` is their sum. Story and synthetic rows are excluded. |
| `test_rollup_story_membership` | Only the story's subtasks are counted, through both `stories[].subtasks` (strings and `{card_id}`) and `story_id`. |
| `test_rollup_uses_winning_run_only` | Rows from losing runs are not counted. |
| `test_rollup_subtask_card` | A subtask card counts only its own rows. |
| `test_rollup_rows_only_not_brd` | The card's brd status and children are ignored. An untouched card gets all zeros. Garbage input gets all zeros. |
| `test_attention` | Only `escalated` and `dead` runs are returned, in input order. `running`, `parked`, `done`, `cancelled` and `unknown` are excluded. Non-array input gives `[]`. |
| `test_escalation_reason_detail` | The failed phase's `detail` is returned. The attempt-level `detail` fallback works. |
| `test_escalation_reason_fallbacks` | The function returns `escalated at <failed phase>` when there is no detail, `escalated at <last row phase>` when no phase failed, and `escalated` when there is nothing or the input is garbage. |
| `test_error_text` | Covers the full envelope, a bare error, type only, message only, neither, the `ok:true` envelope giving `""`, and null, string and number input. |

Verification: `bash ./tests/run.sh` (filter: `bash tests/run.sh runs`). The existing 1.1 tests and the `tests/architecture/` suite must pass unchanged. There is no typecheck or lint step.

---

# runs.js card mapping, rollups, attention and error text Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `cardRunState`, `rollup`, `attention`, `escalationReason` and `errorText` to `core/domain/runs.js`, test-first, with every test in `tests/core/domain/tst_runs.qml`.

**Architecture:** All five are pure, never-throwing functions appended to the existing `.pragma library` module after `runState`. A small set of module-level private helpers (underscore-prefixed) is shared: id checks, linear `card_id` scans (no maps keyed by card id, so `__proto__`/`constructor` are ordinary ids), and one `_winningRun` that both `cardRunState` and `rollup` use so the "newest non-terminal, else newest and dimmed" rule exists in one place. `normalizeRun` and `runState` are reused unchanged.

**Tech Stack:** QML JavaScript (`.pragma library`, `var`/function style, Qt 6 V4 engine), QtTest `TestCase` run by `qmltestrunner` through `tests/run.sh`, pytest architecture tests (must pass unchanged).

**Spec:** `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-2-runs-js-card-791537cf/docs/superpowers/specs/task-1-2-runs-js-card-791537cf-design.md` (prepended above).

**Worktree / branch:** all paths below are relative to `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-2-runs-js-card-791537cf` on branch `mon/task-1-2-runs-js-card-791537cf`. The only prior code this plan relies on is 1.1's `normalizeRun` and `runState` in `core/domain/runs.js` (lines 1-69) and the existing 12 tests in `tests/core/domain/tst_runs.qml`, both verified on disk in this worktree. Nothing from any other subtask is assumed.

## Global Constraints

- `core/domain/runs.js` stays `.pragma library`, `var`/function style, no ES modules, no new imports (if one were ever needed: only `.import "x.js" as X` into `core/domain/` or `vendor/canvas/`; enforced by `tests/architecture/test_layers.py`).
- No glyph literals in `runs.js`.
- No function throws. Garbage input (null, non-array, non-object, missing fields) becomes the default result.
- Card ids are compared with `===` on strings by linear scan. Ids `constructor`, `__proto__`, `toString` behave like any other id.
- Synthetic ids `integrate`, `bases`, and anything starting with `base-` never match a card and are never counted.
- Do not change `normalizeRun`, `runState`, or the existing 1.1 tests. Do not add `started_at` to `normalizeRun`.
- Never read brd status. Do not touch `Board.subtreeCounts`, stores, UI, backend Python or `docs/architecture.md`.
- All new tests go in `tests/core/domain/tst_runs.qml` (TestCase `DomainRuns`), the pure-domain tier. No store, UI, backend or contract tests.
- Verification: `bash ./tests/run.sh` from the worktree root (filtered: `bash tests/run.sh runs`). No typecheck, no lint.

## Review Focus

1. Card ids that collide with `Object.prototype` names (`__proto__`, `constructor`, `toString`, `valueOf`, `hasOwnProperty`): a person expects them to match only when the run really mentions them, in both `cardRunState` and `rollup`. Pinned by `test_card_proto_ids` (Task 1) and the proto block in `test_rollup_subtask_card` (Task 2).
2. Only one of two runs carries `started_at`, or both carry the same value, or one carries a non-string: a person expects array order to decide, not a crash or a random pick. Pinned in `test_card_newest_by_started_at_then_order` (Task 1).
3. Error values that `String()` cannot convert (a prototype-less object as `type`) or numeric `type`/`message`: a person expects readable text and no exception reaching the footer. Pinned in `test_error_text` (Task 5).
4. A failed phase that has no `name` and no detail anywhere: the spec only says "no phase can be found" gives `escalated`; this plan pins that a nameless failed phase yields `"escalated"` rather than falling through to an unrelated row phase. Pinned in `test_escalation_reason_fallbacks` (Task 4).
5. Status strings with the wrong case (`RUNNING`, `Done`, `FAILED`) or non-string statuses in rows and phases: a person expects exact matching (they land in `pending` / are not treated as failed), never a guess. Pinned in `test_rollup_milestone` (Task 2) and `test_escalation_reason_fallbacks` (Task 4).

## File Structure

- Modify: `core/domain/runs.js` — append a "Card mapping, rollups, attention, error text (1.2)" section after `runState` (after current line 69). Responsibility of the file stays "run domain model".
- Modify: `tests/core/domain/tst_runs.qml` — append fixtures and new `test_*` functions immediately before the final `}` that closes `TestCase` (currently line 256, the last line). Existing content is untouched.

Every "insert before the closing brace" instruction below means: insert immediately before the last line of `tests/core/domain/tst_runs.qml`, which is the lone `}` closing `TestCase { name: "DomainRuns" ... }`.

---

### Task 1: Shared helpers and `cardRunState`

**Files:**
- Modify: `core/domain/runs.js` (append after line 69)
- Test: `tests/core/domain/tst_runs.qml` (insert before the closing brace)

**Interfaces:**
- Consumes: `runState(run)` (existing, returns `running|dead|parked|escalated|cancelled|done|unknown`).
- Produces (later tasks rely on these exact names):
  - `_isObject(v) -> bool` (non-null, non-array object)
  - `_arrayOr(v) -> Array`
  - `_stringOr(v) -> string` (strings pass, everything else `""`)
  - `_treeOf(run) -> object` (`run.tree` if an object, else `{}`)
  - `_isSynthetic(id) -> bool`, `_isCardId(id) -> bool` (non-empty string, not synthetic)
  - `_findByCardId(list, cardId) -> object|null` (linear scan on `card_id ===`)
  - `_winningRun(runs, cardId) -> {run, dimmed}|null`
  - `cardRunState(runs, cardId) -> {state, runId, dimmed, phase, attempt}`
  - Test fixtures in `tst_runs.qml`: `mkRun(id, status, live, opts)` where `live === null` means no lease and `opts` may carry `milestone_id` (default `"m1"`), `rows`, `tree`, `started_at`; `sampleTree()`; `checkNone(r, label)`.

- [ ] **Step 1: Write the failing tests**

Insert before the closing brace of `tests/core/domain/tst_runs.qml`:

```qml

  // ---- 1.2: card mapping ------------------------------------------------------------------

  // A normalised run (the shape normalizeRun returns), built directly. live === null means no lease.
  // opts: { milestone_id (default "m1"), rows, tree, started_at }
  function mkRun(id, status, live, opts) {
    var o = opts || {}
    return {
      id: id, repo_dir: "/r",
      milestone_id: o.milestone_id === undefined ? "m1" : o.milestone_id,
      status: status,
      lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
      rows: o.rows || [],
      tree: o.tree || { stories: [], subtasks: [] },
      started_at: o.started_at
    }
  }

  function sampleTree() {
    return {
      stories: [{ card_id: "s1", subtasks: ["t1", { card_id: "t2" }] }, { card_id: "s2", subtasks: [] }],
      subtasks: [
        { card_id: "t1", phases: [{ name: "spec", status: "done", attempts: [{}] },
                                  { name: "implement", status: "running", attempts: [{}, {}] }] },
        { card_id: "t2", phases: [] },
        { card_id: "t3", story_id: "s2", phases: [{ name: "plan", attempts: [] }] }
      ]
    }
  }

  function checkNone(r, label) {
    compare(Object.keys(r).sort().join(","), "attempt,dimmed,phase,runId,state", label)
    compare(r.state, "none", label)
    compare(r.runId, "", label)
    compare(r.dimmed, false, label)
    compare(r.phase, "", label)
    compare(r.attempt, 0, label)
  }

  function test_card_maps_story_subtask_milestone() {
    var runs = [mkRun("r1", "started", true, { tree: sampleTree() })]
    var s = Runs.cardRunState(runs, "s1")
    compare(s.state, "running", "story")
    compare(s.runId, "r1")
    compare(s.dimmed, false)
    compare(Runs.cardRunState(runs, "t3").state, "running", "subtask")
    compare(Runs.cardRunState(runs, "t3").runId, "r1", "subtask")
    compare(Runs.cardRunState(runs, "m1").state, "running", "milestone")
    checkNone(Runs.cardRunState(runs, "zzz"), "unrelated")

    // A card id that appears only in rows, or only as a subtask's story_id, does not touch the run.
    var rowsOnly = [mkRun("r2", "started", true, {
      rows: [{ card_id: "x9", status: "running" }],
      tree: { stories: [], subtasks: [{ card_id: "t9", story_id: "s9" }] }
    })]
    checkNone(Runs.cardRunState(rowsOnly, "x9"), "row only")
    checkNone(Runs.cardRunState(rowsOnly, "s9"), "story_id only")
  }

  function test_card_synthetic_ids_never_match() {
    var tree = {
      stories: [{ card_id: "integrate", subtasks: [] }, { card_id: "bases", subtasks: [] }],
      subtasks: [{ card_id: "base-x", phases: [] }, { card_id: "integrate", phases: [] }]
    }
    var runs = [
      mkRun("r1", "started", true, { tree: tree, milestone_id: "bases", rows: [{ card_id: "integrate", status: "running" }] }),
      mkRun("r2", "started", true, { milestone_id: "base-x" })
    ]
    var ids = ["integrate", "bases", "base-x", "base-"]
    for (var i = 0; i < ids.length; i++) checkNone(Runs.cardRunState(runs, ids[i]), ids[i])

    // Look-alikes are real cards.
    var lookalike = [mkRun("r3", "started", true, {
      tree: { stories: [], subtasks: [{ card_id: "basex" }, { card_id: "my-base-x" }, { card_id: "integrated" }] }
    })]
    compare(Runs.cardRunState(lookalike, "basex").state, "running", "basex")
    compare(Runs.cardRunState(lookalike, "my-base-x").state, "running", "my-base-x")
    compare(Runs.cardRunState(lookalike, "integrated").state, "running", "integrated")
  }

  function test_card_newest_nonterminal_wins() {
    // Input is newest-first: index 0 is the newest run.
    var s = Runs.cardRunState([mkRun("new", "done", null), mkRun("old", "started", true)], "m1")
    compare(s.state, "running")
    compare(s.runId, "old")
    compare(s.dimmed, false)

    s = Runs.cardRunState([mkRun("new", "escalated", null), mkRun("old", "started", false)], "m1")
    compare(s.state, "dead", "dead is non-terminal")
    compare(s.runId, "old")
    compare(s.dimmed, false)

    s = Runs.cardRunState([mkRun("p", "stopped", null), mkRun("d", "started", null)], "m1")
    compare(s.state, "dead", "parked is finished, a lease-less started run is not")
    compare(s.runId, "d")
    compare(s.dimmed, false)

    s = Runs.cardRunState([mkRun("a", "started", true), mkRun("b", "started", false)], "m1")
    compare(s.runId, "a", "two non-terminal: newest wins")
    compare(s.state, "running")
  }

  function test_card_all_terminal_newest_dimmed() {
    var cases = [["stopped", "parked"], ["escalated", "escalated"], ["done", "none"], ["cancelled", "none"]]
    for (var i = 0; i < cases.length; i++) {
      var runs = [mkRun("newest", cases[i][0], null), mkRun("older", "escalated", null), mkRun("oldest", "stopped", null)]
      var s = Runs.cardRunState(runs, "m1")
      compare(s.state, cases[i][1], cases[i][0])
      compare(s.runId, "newest", cases[i][0])
      compare(s.dimmed, true, cases[i][0])
    }
    // An unknown status is not non-terminal either.
    var u = Runs.cardRunState([mkRun("u", "weird", true), mkRun("e", "escalated", null)], "m1")
    compare(u.state, "none")
    compare(u.runId, "u")
    compare(u.dimmed, true)
  }

  function test_card_newest_by_started_at_then_order() {
    var a = mkRun("a", "done", null, { started_at: "2026-10-01T10:00:00Z" })
    var b = mkRun("b", "escalated", null, { started_at: "2026-10-03T10:00:00Z" })
    compare(Runs.cardRunState([a, b], "m1").runId, "b", "later started_at beats index")
    compare(Runs.cardRunState([b, a], "m1").runId, "b")

    var live = mkRun("live", "started", true, { started_at: "2026-09-01T00:00:00Z" })
    compare(Runs.cardRunState([b, live], "m1").runId, "live", "non-terminal beats a newer finished run")

    var l1 = mkRun("l1", "started", true, { started_at: "2026-10-01T00:00:00Z" })
    var l2 = mkRun("l2", "started", false, { started_at: "2026-10-02T00:00:00Z" })
    compare(Runs.cardRunState([l1, l2], "m1").runId, "l2", "started_at decides between non-terminal runs")

    var c = mkRun("c", "done", null)
    compare(Runs.cardRunState([c, b], "m1").runId, "c", "only one has started_at: index decides")
    compare(Runs.cardRunState([b, c], "m1").runId, "b", "only one has started_at: index decides")

    var d = mkRun("d", "done", null, { started_at: "2026-10-03T10:00:00Z" })
    compare(Runs.cardRunState([d, b], "m1").runId, "d", "equal started_at: index decides")

    var n = mkRun("n", "done", null, { started_at: 99999999999999 })
    compare(Runs.cardRunState([a, n], "m1").runId, "a", "non-string started_at is ignored")

    var e = mkRun("e", "done", null, { started_at: "" })
    compare(Runs.cardRunState([e, b], "m1").runId, "e", "empty started_at is ignored")
  }

  function test_card_subtask_phase_attempt() {
    var runs = [mkRun("r1", "started", true, { tree: sampleTree() })]
    var t1 = Runs.cardRunState(runs, "t1")
    compare(t1.phase, "implement")
    compare(t1.attempt, 2)
    var t2 = Runs.cardRunState(runs, "t2")
    compare(t2.phase, "", "empty phases")
    compare(t2.attempt, 0, "empty phases")
    var t3 = Runs.cardRunState(runs, "t3")
    compare(t3.phase, "plan")
    compare(t3.attempt, 0)
    var s1 = Runs.cardRunState(runs, "s1")
    compare(s1.phase, "", "story")
    compare(s1.attempt, 0, "story")
    var m1 = Runs.cardRunState(runs, "m1")
    compare(m1.phase, "", "milestone")
    compare(m1.attempt, 0, "milestone")

    var tree = { stories: [], subtasks: [
      { card_id: "a", phases: [{ name: "review", attempts: [{ attempt: 1 }, { attempt: 3 }] }] },
      { card_id: "b", phases: [{ name: "review", attempts: [{ n: 4 }] }] },
      { card_id: "c", phases: [{ name: "review", attempts: [{ attempt: "7" }] }] },
      { card_id: "d", phases: "x" },
      { card_id: "e" },
      { card_id: "f", phases: [null] },
      { card_id: "g", phases: [{ name: 5, attempts: "x" }] }
    ] }
    var r2 = [mkRun("r2", "started", true, { tree: tree })]
    var expected = [["a", "review", 3], ["b", "review", 4], ["c", "review", 1],
                    ["d", "", 0], ["e", "", 0], ["f", "", 0], ["g", "", 0]]
    for (var i = 0; i < expected.length; i++) {
      var r = Runs.cardRunState(r2, expected[i][0])
      compare(r.state, "running", expected[i][0])
      compare(r.phase, expected[i][1], expected[i][0])
      compare(r.attempt, expected[i][2], expected[i][0])
    }
  }

  function test_card_ignores_brd_status() {
    var runs = [mkRun("r1", "stopped", null, { tree: {
      stories: [{ card_id: "s1", status: "done" }],
      subtasks: [{ card_id: "t1", status: "done", phases: [] }]
    } })]
    compare(Runs.cardRunState(runs, "s1").state, "parked", "story status field ignored")
    compare(Runs.cardRunState(runs, "t1").state, "parked", "subtask status field ignored")
    // A brd card object is not a card id.
    checkNone(Runs.cardRunState(runs, { id: "s1", status: "in_progress" }), "card object as id")
  }

  function test_card_proto_ids() {
    var plain = [mkRun("r1", "started", true, { tree: sampleTree() })]
    var ids = ["__proto__", "constructor", "toString", "hasOwnProperty", "valueOf"]
    for (var i = 0; i < ids.length; i++) checkNone(Runs.cardRunState(plain, ids[i]), "absent " + ids[i])

    var tree = {
      stories: [{ card_id: "constructor", subtasks: ["toString"] }],
      subtasks: [{ card_id: "toString", phases: [{ name: "spec", attempts: [{}] }] }, { card_id: "__proto__", phases: [] }]
    }
    var real = [mkRun("r2", "stopped", null, { tree: tree, milestone_id: "valueOf" })]
    var present = ["__proto__", "constructor", "toString", "valueOf"]
    for (var j = 0; j < present.length; j++) {
      compare(Runs.cardRunState(real, present[j]).state, "parked", "present " + present[j])
      compare(Runs.cardRunState(real, present[j]).runId, "r2", "present " + present[j])
    }
    compare(Runs.cardRunState(real, "toString").phase, "spec")
    compare(Runs.cardRunState(real, "toString").attempt, 1)
    checkNone(Runs.cardRunState(real, "hasOwnProperty"), "still absent")
  }

  function test_card_garbage() {
    var good = mkRun("r1", "started", true, { tree: sampleTree() })
    var inputs = [undefined, null, "x", 5, {}, { length: 1, 0: good }]
    for (var i = 0; i < inputs.length; i++) checkNone(Runs.cardRunState(inputs[i], "m1"), "runs " + i)

    compare(Runs.cardRunState([null, "x", 5, [], good], "m1").runId, "r1", "junk entries skipped")

    var junk = [
      { id: "j", status: "started", lease: { live: true }, tree: "x", rows: 5 },
      { id: "k", status: "started", lease: { live: true }, milestone_id: "m1",
        tree: { stories: [null, 5, { card_id: null }], subtasks: "y" } }
    ]
    compare(Runs.cardRunState(junk, "m1").runId, "k")
    checkNone(Runs.cardRunState(junk, "j"), "run id is not a card id")

    var withBlank = [good, mkRun("blank", "started", true, { milestone_id: "" }),
                     Runs.normalizeRun({ row: { id: "z", status: "started" } })]
    var ids = [null, undefined, "", 0, 5, {}, []]
    for (var k = 0; k < ids.length; k++) checkNone(Runs.cardRunState(withBlank, ids[k]), "cardId " + k)
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-2-runs-js-card-791537cf && bash tests/run.sh runs`
Expected: pytest passes; under `== tests/core/domain/tst_runs.qml` the nine `test_card_*` functions print `FAIL!  : DomainRuns::test_card_...` with a `TypeError ... cardRunState ... is not a function` line, the 12 existing 1.1 tests still pass, and the script exits non-zero.

- [ ] **Step 3: Write the implementation**

Append to the end of `core/domain/runs.js` (after `runState`, current line 69):

```js

// ---- Card mapping, rollups, attention, error text (1.2) ----------------------------------
//
// Inputs are normalised runs (normalizeRun output), taken newest first. None of
// these functions reads brd status, and none throws: garbage becomes the
// default. Card ids are compared with === on strings by linear scan, so ids such
// as `__proto__` or `constructor` behave like any other id.

function _isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }
function _arrayOr(v) { return Array.isArray(v) ? v : [] }
function _stringOr(v) { return typeof v === "string" ? v : "" }
function _isFiniteNumber(v) { return typeof v === "number" && isFinite(v) }
function _treeOf(run) { return _isObject(run) && _isObject(run.tree) ? run.tree : {} }
function _lastOf(list) { var a = _arrayOr(list); return a.length > 0 ? a[a.length - 1] : null }

// `integrate`, `bases` and `base-*` are orchestrator bookkeeping ids, never cards.
function _isSynthetic(id) {
  return id === "integrate" || id === "bases" || (typeof id === "string" && id.indexOf("base-") === 0)
}

function _isCardId(id) { return typeof id === "string" && id !== "" && !_isSynthetic(id) }

function _findByCardId(list, cardId) {
  var items = _arrayOr(list)
  for (var i = 0; i < items.length; i++) {
    if (_isObject(items[i]) && items[i].card_id === cardId) return items[i]
  }
  return null
}

// A run touches a card through its milestone, a story or a subtask -- never through rows alone.
function _touches(run, cardId) {
  if (!_isObject(run)) return false
  if (run.milestone_id === cardId) return true
  var tree = _treeOf(run)
  return _findByCardId(tree.stories, cardId) !== null || _findByCardId(tree.subtasks, cardId) !== null
}

// Non-terminal = status `started` (live or dead). Everything else is finished or unknown.
function _isNonTerminal(run) {
  var s = runState(run)
  return s === "running" || s === "dead"
}

// Is run a (at index ai) newer than run b (at index bi)? A later started_at wins when both
// carry a distinct non-empty string; otherwise the earlier index (input is newest first).
function _isNewer(a, ai, b, bi) {
  var as = _stringOr(a.started_at), bs = _stringOr(b.started_at)
  if (as !== "" && bs !== "" && as !== bs) return as > bs
  return ai < bi
}

// The run that speaks for a card: newest non-terminal run touching it, else the newest run
// touching it (dimmed). null when nothing touches it or the id is not a real card id.
function _winningRun(runs, cardId) {
  if (!_isCardId(cardId)) return null
  var list = _arrayOr(runs)
  var best = null, bestIndex = -1, bestLive = false
  for (var i = 0; i < list.length; i++) {
    var run = list[i]
    if (!_touches(run, cardId)) continue
    var live = _isNonTerminal(run)
    if (best === null || (live && !bestLive) || (live === bestLive && _isNewer(run, i, best, bestIndex))) {
      best = run
      bestIndex = i
      bestLive = live
    }
  }
  return best === null ? null : { run: best, dimmed: !bestLive }
}

// The am run state of one card, separate from its brd status.
// state: running | dead | parked | escalated | none. phase/attempt only for a subtask card.
function cardRunState(runs, cardId) {
  var result = { state: "none", runId: "", dimmed: false, phase: "", attempt: 0 }
  var win = _winningRun(runs, cardId)
  if (win === null) return result
  var s = runState(win.run)
  result.state = s === "running" || s === "dead" || s === "parked" || s === "escalated" ? s : "none"
  result.runId = _stringOr(win.run.id)
  result.dimmed = win.dimmed
  var subtask = _findByCardId(_treeOf(win.run).subtasks, cardId)
  var phase = subtask === null ? null : _lastOf(subtask.phases)
  if (_isObject(phase)) {
    result.phase = _stringOr(phase.name)
    var attempts = _arrayOr(phase.attempts)
    result.attempt = attempts.length
    var last = _lastOf(attempts)
    if (_isObject(last)) {
      if (_isFiniteNumber(last.attempt)) result.attempt = last.attempt
      else if (_isFiniteNumber(last.n)) result.attempt = last.n
    }
  }
  return result
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-2-runs-js-card-791537cf && bash tests/run.sh runs`
Expected: pytest passes (including `tests/architecture/`); `tst_runs.qml` prints `Totals:` with 0 failed, no `FAIL!` lines, no `TypeError`/`ReferenceError` lines; exit status 0.

- [ ] **Step 5: Commit**

```bash
cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-2-runs-js-card-791537cf
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): cardRunState maps a card to its winning am run"
```

---

### Task 2: `rollup`

**Files:**
- Modify: `core/domain/runs.js` (append after `cardRunState`)
- Test: `tests/core/domain/tst_runs.qml` (insert before the closing brace)

**Interfaces:**
- Consumes (Task 1): `_isObject`, `_arrayOr`, `_treeOf`, `_isCardId`, `_findByCardId`, `_winningRun(runs, cardId) -> {run, dimmed}|null`; test fixture `mkRun(id, status, live, opts)`.
- Produces: `rollup(runs, card) -> {running, parked, escalated, done, pending, total}` (integers); test fixtures `rollupRun(id, status, live)` and `counts(r) -> "running,parked,escalated,done,pending,total"`.

- [ ] **Step 1: Write the failing tests**

Insert before the closing brace of `tests/core/domain/tst_runs.qml`:

```qml

  // ---- 1.2: rollups -----------------------------------------------------------------------

  // Milestone m1; story s1 owns t1 (string entry) and t2 ({card_id} entry); t3 belongs to s2
  // via story_id; t4 belongs to no story; "integrate" is a synthetic subtask.
  function rollupRun(id, status, live) {
    return mkRun(id, status, live, {
      tree: {
        stories: [{ card_id: "s1", subtasks: ["t1", { card_id: "t2" }] }, { card_id: "s2", subtasks: [] }],
        subtasks: [
          { card_id: "t1", phases: [] }, { card_id: "t2", phases: [] }, { card_id: "t3", story_id: "s2", phases: [] },
          { card_id: "t4", phases: [] }, { card_id: "integrate", phases: [] }
        ]
      },
      rows: [
        { card_id: "t1", status: "running" }, { card_id: "t1", status: "started" },
        { card_id: "t2", status: "parked" }, { card_id: "t2", status: "stopped" },
        { card_id: "t3", status: "escalated" }, { card_id: "t3", status: "failed" },
        { card_id: "t4", status: "done" },
        { card_id: "t4", status: "queued" }, { card_id: "t4" },
        { card_id: "s1", status: "running" },
        { card_id: "integrate", status: "running" },
        { card_id: "bases", status: "running" },
        { card_id: "zz", status: "running" },
        null, "x"
      ]
    })
  }

  function counts(r) {
    return [r.running, r.parked, r.escalated, r.done, r.pending, r.total].join(",")
  }

  function test_rollup_milestone() {
    var r = Runs.rollup([rollupRun("r1", "started", true)], { id: "m1" })
    compare(Object.keys(r).sort().join(","), "done,escalated,parked,pending,running,total")
    // story row s1, synthetic integrate/bases, unknown zz and junk rows are excluded
    compare(counts(r), "2,2,2,1,2,9")

    var odd = mkRun("r2", "started", true, {
      tree: { stories: [], subtasks: [{ card_id: "t1" }] },
      rows: [{ card_id: "t1", status: "RUNNING" }, { card_id: "t1", status: "Done" }, { card_id: "t1", status: 5 }]
    })
    compare(counts(Runs.rollup([odd], { id: "m1" })), "0,0,0,0,3,3", "status match is exact")
  }

  function test_rollup_story_membership() {
    var runs = [rollupRun("r1", "started", true)]
    compare(counts(Runs.rollup(runs, { id: "s1" })), "2,2,0,0,0,4", "string and {card_id} entries")
    compare(counts(Runs.rollup(runs, { id: "s2" })), "0,0,2,0,0,2", "story_id membership")
  }

  function test_rollup_uses_winning_run_only() {
    var winner = mkRun("live", "started", true, {
      tree: { stories: [], subtasks: [{ card_id: "t1" }] },
      rows: [{ card_id: "t1", status: "running" }]
    })
    var loser = mkRun("old", "done", null, {
      tree: { stories: [], subtasks: [{ card_id: "t1" }] },
      rows: [{ card_id: "t1", status: "done" }, { card_id: "t1", status: "done" }]
    })
    compare(counts(Runs.rollup([loser, winner], { id: "m1" })), "1,0,0,0,0,1", "milestone")
    compare(counts(Runs.rollup([loser, winner], { id: "t1" })), "1,0,0,0,0,1", "subtask")

    var older = mkRun("older", "escalated", null, {
      tree: { stories: [], subtasks: [{ card_id: "t1" }] },
      rows: [{ card_id: "t1", status: "escalated" }]
    })
    compare(counts(Runs.rollup([loser, older], { id: "m1" })), "0,0,0,2,0,2", "all finished: newest wins")
  }

  function test_rollup_subtask_card() {
    var runs = [rollupRun("r1", "started", true)]
    compare(counts(Runs.rollup(runs, { id: "t1" })), "2,0,0,0,0,2")
    compare(counts(Runs.rollup(runs, { id: "t4" })), "0,0,0,1,2,3")
    compare(counts(Runs.rollup(runs, { id: "integrate" })), "0,0,0,0,0,0", "synthetic card")

    var proto = mkRun("p", "started", true, {
      tree: { stories: [{ card_id: "__proto__", subtasks: ["constructor"] }],
              subtasks: [{ card_id: "constructor" }, { card_id: "toString" }] },
      rows: [{ card_id: "constructor", status: "done" }, { card_id: "toString", status: "running" }]
    })
    compare(counts(Runs.rollup([proto], { id: "constructor" })), "0,0,0,1,0,1", "constructor subtask")
    compare(counts(Runs.rollup([proto], { id: "__proto__" })), "0,0,0,1,0,1", "__proto__ story")
    compare(counts(Runs.rollup([proto], { id: "valueOf" })), "0,0,0,0,0,0", "absent valueOf")
  }

  function test_rollup_rows_only_not_brd() {
    var runs = [rollupRun("r1", "started", true)]
    var card = { id: "s1", status: "done", children: ["t1", "t2", "t9"], counts: { done: 9 } }
    compare(counts(Runs.rollup(runs, card)), "2,2,0,0,0,4", "brd status and children ignored")
    compare(counts(Runs.rollup(runs, { id: "s9", status: "in_progress" })), "0,0,0,0,0,0", "untouched card")

    var garbage = [[undefined, { id: "m1" }], [null, { id: "m1" }], ["x", { id: "m1" }], [runs, null],
                   [runs, "m1"], [runs, {}], [runs, { id: "" }], [runs, { id: 5 }], [runs, []]]
    for (var i = 0; i < garbage.length; i++) {
      compare(counts(Runs.rollup(garbage[i][0], garbage[i][1])), "0,0,0,0,0,0", "garbage " + i)
    }

    var junk = [{ id: "j", status: "started", lease: { live: true }, milestone_id: "m1",
                  tree: { stories: "x", subtasks: [null, 5] }, rows: [{ card_id: "t1", status: "running" }] }]
    compare(counts(Runs.rollup(junk, { id: "m1" })), "0,0,0,0,0,0", "junk tree")
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-2-runs-js-card-791537cf && bash tests/run.sh runs`
Expected: the five `test_rollup_*` functions print `FAIL!  : DomainRuns::test_rollup_...` with `TypeError ... rollup ... is not a function`; all Task 1 and 1.1 tests still pass; exit status non-zero.

- [ ] **Step 3: Write the implementation**

Append to the end of `core/domain/runs.js`:

```js

// Which am row status lands in which rollup bucket; anything else is pending.
function _bucketOf(status) {
  if (status === "running" || status === "started") return "running"
  if (status === "parked" || status === "stopped") return "parked"
  if (status === "escalated" || status === "failed") return "escalated"
  if (status === "done") return "done"
  return "pending"
}

// Does the story own this subtask? Via the subtask's story_id, or the story's own list
// (entries are id strings or {card_id}).
function _storyHas(story, subtask, storyId) {
  if (subtask.story_id === storyId) return true
  var entries = _arrayOr(story.subtasks)
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    if (e === subtask.card_id || (_isObject(e) && e.card_id === subtask.card_id)) return true
  }
  return false
}

// Run-progress counts for a brd card, from the winning run's am rows only (never brd status;
// Board.subtreeCounts is a separate thing). Only rows of real subtasks in that run count.
function rollup(runs, card) {
  var counts = { running: 0, parked: 0, escalated: 0, done: 0, pending: 0, total: 0 }
  if (!_isObject(card)) return counts
  var cardId = card.id
  var win = _winningRun(runs, cardId)
  if (win === null) return counts
  var run = win.run
  var tree = _treeOf(run)
  var isMilestone = run.milestone_id === cardId
  var story = isMilestone ? null : _findByCardId(tree.stories, cardId)
  var rows = _arrayOr(run.rows)
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (!_isObject(row) || !_isCardId(row.card_id)) continue
    var subtask = _findByCardId(tree.subtasks, row.card_id)
    if (subtask === null) continue
    if (!isMilestone) {
      var belongs = story !== null ? _storyHas(story, subtask, cardId) : row.card_id === cardId
      if (!belongs) continue
    }
    counts[_bucketOf(row.status)] += 1
    counts.total += 1
  }
  return counts
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-2-runs-js-card-791537cf && bash tests/run.sh runs`
Expected: `tst_runs.qml` `Totals:` with 0 failed, no `FAIL!`/`TypeError` lines; exit status 0.

- [ ] **Step 5: Commit**

```bash
cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-2-runs-js-card-791537cf
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): rollup counts a card's am rows from its winning run"
```

---

### Task 3: `attention`

**Files:**
- Modify: `core/domain/runs.js` (append after `rollup`)
- Test: `tests/core/domain/tst_runs.qml` (insert before the closing brace)

**Interfaces:**
- Consumes: `runState(run)` (1.1), `_arrayOr` (Task 1), fixture `mkRun` (Task 1).
- Produces: `attention(runs) -> Array` (same run objects, input order).

- [ ] **Step 1: Write the failing test**

Insert before the closing brace of `tests/core/domain/tst_runs.qml`:

```qml

  // ---- 1.2: attention ---------------------------------------------------------------------

  function test_attention() {
    var liveRun = mkRun("run", "started", true)
    var dead = mkRun("dead", "started", false)
    var noLease = mkRun("nl", "started", null)
    var parked = mkRun("p", "stopped", null)
    var esc = mkRun("e", "escalated", null)
    var done = mkRun("d", "done", null)
    var canc = mkRun("c", "cancelled", null)
    var unk = mkRun("u", "weird", true)
    var list = [liveRun, esc, parked, dead, done, canc, unk, noLease, null, "x"]
    var out = Runs.attention(list)
    compare(out.length, 3)
    compare(out[0] === esc, true, "same object, input order")
    compare(out[1] === dead, true)
    compare(out[2] === noLease, true)
    compare(list.length, 10, "input not modified")
    compare(Runs.attention([]).length, 0)

    var bad = [undefined, null, "x", 5, {}, { length: 1, 0: esc }]
    for (var i = 0; i < bad.length; i++) {
      var r = Runs.attention(bad[i])
      compare(Array.isArray(r), true, "garbage " + i)
      compare(r.length, 0, "garbage " + i)
    }
  }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-2-runs-js-card-791537cf && bash tests/run.sh runs`
Expected: `FAIL!  : DomainRuns::test_attention()` with `TypeError ... attention ... is not a function`; every other test passes; exit status non-zero.

- [ ] **Step 3: Write the implementation**

Append to the end of `core/domain/runs.js`:

```js

// Runs that need a human: escalated, or started with a dead lease. Same objects, input order.
function attention(runs) {
  var list = _arrayOr(runs)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var s = runState(list[i])
    if (s === "escalated" || s === "dead") out.push(list[i])
  }
  return out
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-2-runs-js-card-791537cf && bash tests/run.sh runs`
Expected: `tst_runs.qml` `Totals:` with 0 failed; exit status 0.

- [ ] **Step 5: Commit**

```bash
cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-2-runs-js-card-791537cf
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): attention lists escalated and dead runs"
```

---

### Task 4: `escalationReason`

**Files:**
- Modify: `core/domain/runs.js` (append after `attention`)
- Test: `tests/core/domain/tst_runs.qml` (insert before the closing brace)

**Interfaces:**
- Consumes (Task 1): `_isObject`, `_arrayOr`, `_treeOf`; fixture `mkRun`.
- Produces: `_textOf(v) -> string` (String-coerced and trimmed; `null`/`undefined` and values `String()` cannot convert give `""`; never throws; Task 5 reuses it), `escalationReason(run) -> string`.

Plan-level decision (Review Focus 4): a failed phase with no detail anywhere and no usable `name` returns `"escalated"`; it does not fall through to the row fallback.

- [ ] **Step 1: Write the failing tests**

Insert before the closing brace of `tests/core/domain/tst_runs.qml`:

```qml

  // ---- 1.2: escalation reason -------------------------------------------------------------

  function test_escalation_reason_detail() {
    var tree = { stories: [], subtasks: [
      { card_id: "t1", phases: [{ name: "spec", status: "done", detail: "fine" }] },
      { card_id: "t2", phases: [{ name: "plan", status: "done" },
                                { name: "implement", status: "failed", detail: "  tests red after 3 attempts  " }] },
      { card_id: "t3", phases: [{ name: "review", status: "failed", detail: "second failure" }] }
    ] }
    compare(Runs.escalationReason(mkRun("r", "escalated", null, { tree: tree })), "tests red after 3 attempts",
            "first failed phase, trimmed")

    var fromAttempt = { stories: [], subtasks: [{ card_id: "t1", phases: [{ name: "verify", status: "failed", detail: "  ",
      attempts: [{ detail: "first" }, { detail: "second" }, { detail: "" }, null] }] }] }
    compare(Runs.escalationReason(mkRun("r", "escalated", null, { tree: fromAttempt })), "second",
            "last attempt that has a detail")

    var numeric = { stories: [], subtasks: [{ card_id: "t1", phases: [{ name: "x", status: "failed", detail: 42 }] }] }
    compare(Runs.escalationReason(mkRun("r", "escalated", null, { tree: numeric })), "42", "detail coerced with String")
  }

  function test_escalation_reason_fallbacks() {
    var noDetail = mkRun("r", "escalated", null, {
      tree: { stories: [], subtasks: [{ card_id: "t1", phases: [{ name: "review", status: "failed",
                                                                  attempts: [{}, { detail: "" }] }] }] },
      rows: [{ card_id: "t1", phase: "other" }]
    })
    compare(Runs.escalationReason(noDetail), "escalated at review")

    var noFailed = mkRun("r", "escalated", null, {
      tree: { stories: [], subtasks: [{ card_id: "t1", phases: [{ name: "spec", status: "done" },
                                                                { name: "plan", status: "FAILED" }] }] },
      rows: [{ card_id: "t1", phase: "spec" }, { card_id: "t2", phase: "implement" },
             { card_id: "t3", phase: "" }, { card_id: "t4" }, null]
    })
    compare(Runs.escalationReason(noFailed), "escalated at implement", "last row phase; status match is exact")

    var nameless = mkRun("r", "escalated", null, {
      tree: { stories: [], subtasks: [{ card_id: "t1", phases: [{ status: "failed" }] }] },
      rows: [{ card_id: "t1", phase: "spec" }]
    })
    compare(Runs.escalationReason(nameless), "escalated", "nameless failed phase")

    compare(Runs.escalationReason(mkRun("r", "escalated", null)), "escalated", "nothing at all")

    var bad = [undefined, null, "x", 5, [], {}, { tree: "x", rows: "y" },
               { tree: { subtasks: [null, { phases: "x" }, { phases: [null, 5] }] }, rows: [null] }]
    for (var i = 0; i < bad.length; i++) compare(Runs.escalationReason(bad[i]), "escalated", "garbage " + i)
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-2-runs-js-card-791537cf && bash tests/run.sh runs`
Expected: both `test_escalation_reason_*` functions print `FAIL!` with `TypeError ... escalationReason ... is not a function`; every other test passes; exit status non-zero.

- [ ] **Step 3: Write the implementation**

Append to the end of `core/domain/runs.js`:

```js

// String(v), trimmed. null/undefined, and values String() cannot convert (e.g. a
// prototype-less object), become "".
function _textOf(v) {
  if (v === undefined || v === null) return ""
  try { return String(v).trim() } catch (e) { return "" }
}

// Why a run escalated: the first failed phase's detail (or its last attempt's detail),
// else "escalated at <phase>", else "escalated".
function escalationReason(run) {
  var subtasks = _arrayOr(_treeOf(run).subtasks)
  for (var i = 0; i < subtasks.length; i++) {
    var phases = _isObject(subtasks[i]) ? _arrayOr(subtasks[i].phases) : []
    for (var j = 0; j < phases.length; j++) {
      var phase = phases[j]
      if (!_isObject(phase) || phase.status !== "failed") continue
      var detail = _textOf(phase.detail)
      var attempts = _arrayOr(phase.attempts)
      for (var k = attempts.length - 1; detail === "" && k >= 0; k--) {
        if (_isObject(attempts[k])) detail = _textOf(attempts[k].detail)
      }
      if (detail !== "") return detail
      var name = _textOf(phase.name)
      return name !== "" ? "escalated at " + name : "escalated"
    }
  }
  var rows = _isObject(run) ? _arrayOr(run.rows) : []
  for (var r = rows.length - 1; r >= 0; r--) {
    var at = _isObject(rows[r]) ? _textOf(rows[r].phase) : ""
    if (at !== "") return "escalated at " + at
  }
  return "escalated"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-2-runs-js-card-791537cf && bash tests/run.sh runs`
Expected: `tst_runs.qml` `Totals:` with 0 failed; exit status 0.

- [ ] **Step 5: Commit**

```bash
cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-2-runs-js-card-791537cf
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): escalationReason explains why a run escalated"
```

---

### Task 5: `errorText` and full verification

**Files:**
- Modify: `core/domain/runs.js` (append after `escalationReason`)
- Test: `tests/core/domain/tst_runs.qml` (insert before the closing brace)

**Interfaces:**
- Consumes: `_isObject` (Task 1), `_textOf(v) -> string` (Task 4).
- Produces: `errorText(error) -> string`.

- [ ] **Step 1: Write the failing test**

Insert before the closing brace of `tests/core/domain/tst_runs.qml`:

```qml

  // ---- 1.2: error text --------------------------------------------------------------------

  function test_error_text() {
    compare(Runs.errorText({ ok: false, error: { type: "LeaseHeld", message: "run r1 is held by pid 42" } }),
            "LeaseHeld: run r1 is held by pid 42", "full envelope")
    compare(Runs.errorText({ type: "NotFound", message: "no such run" }), "NotFound: no such run", "bare error")
    compare(Runs.errorText({ ok: false, error: { type: "Timeout" } }), "Timeout", "type only")
    compare(Runs.errorText({ ok: false, error: { message: "boom" } }), "boom", "message only")
    compare(Runs.errorText({ ok: false, error: { type: "  ", message: "  boom  " } }), "boom", "blank type, trimmed")
    compare(Runs.errorText({ ok: false, error: { type: " Busy ", message: " try later " } }), "Busy: try later", "trimmed")
    compare(Runs.errorText({ ok: false, error: { type: 500, message: 7 } }), "500: 7", "coerced with String")
    compare(Runs.errorText({ ok: false, error: {} }), "unknown error", "neither")
    compare(Runs.errorText({ ok: false }), "unknown error", "no error key")
    compare(Runs.errorText({ ok: false, error: "x" }), "unknown error", "string error")
    compare(Runs.errorText({ ok: false, error: { type: null, message: undefined } }), "unknown error", "null fields")
    compare(Runs.errorText({ ok: true, data: {} }), "", "ok envelope")
    compare(Runs.errorText({ ok: true, error: { type: "X", message: "y" } }), "", "ok wins")

    var bad = [undefined, null, "boom", 5, true, []]
    for (var i = 0; i < bad.length; i++) compare(Runs.errorText(bad[i]), "unknown error", "garbage " + i)

    var weird = Object.create(null)
    compare(Runs.errorText({ ok: false, error: { type: weird, message: "m" } }), "m", "unconvertible type does not throw")
  }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-2-runs-js-card-791537cf && bash tests/run.sh runs`
Expected: `FAIL!  : DomainRuns::test_error_text()` with `TypeError ... errorText ... is not a function`; every other test passes; exit status non-zero.

- [ ] **Step 3: Write the implementation**

Append to the end of `core/domain/runs.js`:

```js

// Display text for an am error: the {ok:false, error:{type, message}} envelope or the bare
// {type, message}. "type: message", either alone, or "unknown error". ok:true gives "".
function errorText(error) {
  if (!_isObject(error)) return "unknown error"
  if (error.ok === true) return ""
  var e = _isObject(error.error) ? error.error : error
  var type = _textOf(e.type)
  var message = _textOf(e.message)
  if (type !== "" && message !== "") return type + ": " + message
  if (type !== "") return type
  if (message !== "") return message
  return "unknown error"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-2-runs-js-card-791537cf && bash tests/run.sh runs`
Expected: `tst_runs.qml` `Totals:` with 0 failed; exit status 0.

- [ ] **Step 5: Run the full suite**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-2-runs-js-card-791537cf && bash ./tests/run.sh`
Expected: pytest all pass (including `tests/architecture/test_layers.py` and `test_icon_glyphs.py`, unchanged); every `tst_*.qml` prints `Totals:` with 0 failed; no `FAIL!`, `TypeError`, `ReferenceError` or `is not a function` lines; exit status 0. If anything outside `tst_runs.qml` fails, stop and report it rather than editing other files.

- [ ] **Step 6: Commit**

```bash
cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-2-runs-js-card-791537cf
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): errorText turns an am error envelope into display text"
```

---

## Self-Review

**Spec coverage:**
- Shared rules (synthetic, touches, non-terminal, newest, winning run): `_isSynthetic`, `_touches`, `_isNonTerminal`, `_isNewer`, `_winningRun` in Task 1; tests `test_card_synthetic_ids_never_match`, `test_card_maps_story_subtask_milestone`, `test_card_newest_nonterminal_wins`, `test_card_all_terminal_newest_dimmed`, `test_card_newest_by_started_at_then_order`.
- `cardRunState` (state mapping, runId, dimmed, phase/attempt, no brd status): Task 1, all nine `test_card_*`.
- `rollup` (winning run, subtask rows only, story membership by list and `story_id`, milestone, subtask card, buckets, total, zeros): Task 2, five `test_rollup_*`.
- `attention`: Task 3, `test_attention`.
- `escalationReason` (failed phase detail, attempt fallback, `escalated at <phase>`, row phase, `escalated`): Task 4, two tests.
- `errorText` (envelope, bare, type/message only, neither, ok:true, coercion, trim, garbage): Task 5, `test_error_text`.
- All 18 spec test names appear, all in `tests/core/domain/tst_runs.qml`. Full-suite verification: Task 5 Step 5. No changes to `normalizeRun`/`runState`/existing tests; no imports; no glyphs.

**Placeholder scan:** no TBD/TODO/"similar to"; every code step has full code.

**Type consistency:** helper names (`_isObject`, `_arrayOr`, `_stringOr`, `_treeOf`, `_isCardId`, `_findByCardId`, `_winningRun`, `_textOf`) match between their defining task and later consumers; fixtures `mkRun`, `sampleTree`, `checkNone`, `rollupRun`, `counts` are defined before use; result keys `state, runId, dimmed, phase, attempt` and `running, parked, escalated, done, pending, total` match spec and tests.
