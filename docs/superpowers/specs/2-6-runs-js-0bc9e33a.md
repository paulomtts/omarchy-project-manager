# 2.6 runs.js: glyphStateOf draws am's attempt outcomes — design

Card `0bc9e33a`, a subtask of story `21f9cd5a` ("Normalize real am status"),
blocked by `aedf81f2` (2.5, `escalationReason`, committed at `17b0d8a` /
`6ba1ddf`). Parent spec: `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
(below: **parent**). Work breakdown item 2 (parent L324-326) ends with
"`escalationReason`, `glyphStateOf`": this subtask is `glyphStateOf` only
(`core/domain/runs.js:536-548`).

## Goal

In Run detail, an attempt row of a real am run shows a glyph, and a failed
attempt is drawn urgent. Real am records attempt outcomes as `started, ok,
schema_invalid, gate_failed, harness_error` (parent L38-39), and an attempt
row's `state` is that outcome (parent L33-36). Today `glyphStateOf` knows none
of `ok`, `gate_failed`, `schema_invalid`, `harness_error` and returns `""`
(parent L85, L102), so `RunDetailScreen` draws such an attempt with no glyph
and in the foreground colour, even the `gate_failed` attempt that escalated
the run (parent L120). After this subtask `ok` draws as `done` and the three
failure outcomes draw as `dead` (urgent).

## Inherited constraints

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

## Fixture facts this design relies on (checked 2026-10-05)

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

## Behavior

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

### Consumers

No QML change. `RunDetailScreen.glyphOf` (`RunDetailScreen.qml:87`) draws the
new glyphs and `isUrgent` (`:90`, `escalated` or `dead`) colours the three
failure outcomes with `theme.urgent`; an attempt row's label is
`"<marker><glyph> <phase>.<n> <status>"` (`attemptText`, `:111-115`) coloured by
`isUrgent(attempt.status)` (`:421`). Story, subtask and synthetic rows also go
through `glyphOf`, but their statuses are never attempt outcomes, so they are
unaffected. `PhaseTimeline` keeps its own mapping (parent "Not changed").

### Contract comment

The comment above `glyphStateOf` (`runs.js:536-539`) states the contract: the
`runGlyphs.js` state an am story, subtask, phase, attempt or row status is
drawn with — `started` is running, `failed` and the attempt failures
`gate_failed`, `schema_invalid`, `harness_error` are dead, the attempt outcome
`ok` is done; `""` for anything else. No narrative.

## Tests

### 1. `tests/core/domain/tst_runs.qml` (TestCase `DomainRuns`)

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

### 2. `tests/ui/screens/tst_run_detail_screen.qml` (TestCase `RunDetailScreen`)

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

## Review focus (inputs the tests above might miss)

- An attempt status with different case or whitespace (`"OK"`, `"Gate_Failed"`)
  must give `""`, not a glyph — pinned in the table test.
- `canceled` must stay `""` in this card; mapping it is item 4's job.
- Prototype-named strings (`"constructor"`, `"__proto__"`) must not match if
  the implementation uses a lookup object — pinned in the table test.
- A story or subtask whose status is `done` / `failed` must render exactly as
  before (existing screen tests stay green unchanged).
- `started` attempts keep the running glyph (existing `implement.2 started`
  screen assertion stays green).

## Out of scope

- `canceled` spelling in `glyphStateOf` / `runState` (item 4, parent L289-294).
- `PhaseTimeline`'s own glyph mapping, `RunBadge`, `RunRollupBar`,
  `runGlyphs.js` (parent "Not changed").
- Any change to `RunDetailScreen.qml`, `normalizeRun`, `runTree`,
  `escalationReason` (2.5), `logTail` (item 3), docs (item 5).

## Files

- Modify: `core/domain/runs.js` (`glyphStateOf` and its comment only).
- Modify: `tests/core/domain/tst_runs.qml`.
- Modify: `tests/ui/screens/tst_run_detail_screen.qml`.

Verification: `bash tests/run.sh` green (pytest incl. `tests/architecture`, then
every `tst_*.qml`).
