# 2.5 runs.js: escalationReason falls back to a failed row only — design

Card `aedf81f2`, a subtask of story `21f9cd5a` ("Normalize real am status"),
blocked by `c7cfa719` (2.4, `runTree`'s open attempt, committed at `65d85cd`).
Parent spec: `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
(below: **parent**). Work breakdown item 2 (parent L324-326) lists
"`normalizeRun` …, then `rollup`, `runProgress`, `runTree`'s open attempt,
`escalationReason`, `glyphStateOf`": this subtask is `escalationReason` only
(`core/domain/runs.js:334-359`).

## Goal

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

## Inherited constraints

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

## Fixture facts this design relies on (checked 2026-10-05)

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

## Behavior

### Unchanged: the tree branch

The first object phase whose `status` is exactly `"failed"`, scanning
`tree.subtasks[].phases[]` in order, still decides first: its trimmed `detail`,
else its last attempt's non-empty trimmed `detail`, else `escalated at <name>`
(trimmed name), else `escalated` (`runs.js:336-352`, unchanged).

### Changed: the row fallback

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

### Error paths

Never throws. `run` not an object, `rows` not an array, row elements that are
not objects, a `tree` that is not an object or has non-array `subtasks` /
`phases`: all reach `escalated` (or the row fallback, for a bad tree with good
rows), as today. The failure-status set is a module-level constant and looked up
with own-key / `===` comparison only, so a row status such as `"__proto__"`,
`"constructor"` or `"toString"` does not match.

### Consumers

No UI or store code changes. `RunsScreen.qml:256` and `RunDetailScreen.qml:214`
render the new string; `newAlerts` (`runs.js:842`) puts it in an escalated
alert's `reason`, which `RunStore` shows in `RunToast` and passes to
`notify.py`. `glyphStateOf` is not reused: it maps `escalated` to its own glyph
state and is changed by sibling card 2.6.

### Contract comment

The comment above `escalationReason` (`runs.js:334-335`) states the rule as a
contract: the first failed phase's detail (or its last attempt's detail), else
`escalated at <that phase>`; with no failed phase, `escalated at <phase>` of
the last row whose status is `failed`, `escalated`, `gate_failed`,
`schema_invalid` or `harness_error`; else `escalated`. No narrative.

## Tests

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

## Out of scope

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

## Plan handoff

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
