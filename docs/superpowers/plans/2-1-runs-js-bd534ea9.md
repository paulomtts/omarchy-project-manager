# 2.1 runs.js: normalizeRun reads am's nested tree and rows — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Runs.normalizeRun` turns a real `am status` payload (nested `stories[].subtasks[]`, rows `{story, subtask, phase, attempt, state}`) into the flat normalized run (`tree.stories[]` with id-list `subtasks`, `tree.subtasks[]` carrying `story_id`, renamed `rows[]` without Integrate resolver rows), proven by tests built from the committed captures in `tests/fixtures/am/`.

**Architecture:** One code change: `normalizeRun` in `core/domain/runs.js` gains a JSON-like, `__proto__`-safe deep copy and builds `tree.stories`, `tree.subtasks` and `rows` from am's real shape; its header comment states the real contract. Every downstream helper (`defaultAttempt`, `currentPhase`, `cardRunState`, `runsTouching`, `runTree`, `attemptStatus`) is left untouched and is asserted over the new output. The QML unit tests in `tests/core/domain/tst_runs.qml` and `tests/core/stores/tst_run_store.qml` load the captures through `tests/helpers/amFixtures.js` (`F.load(name)`, a fresh parse per call) instead of hand-writing the guessed shape.

**Tech Stack:** Qt 6 QML / V4 JavaScript (`.pragma library`), QtTest via `qmltestrunner`, driven by `bash tests/run.sh [path-substring]` (pytest runs first, then every matching `tst_*.qml`).

**Spec:** `docs/superpowers/specs/2-1-runs-js-bd534ea9.md` (prepended below, headings demoted one level; executors read both).

## Global Constraints

- One code file changes: `core/domain/runs.js` (`normalizeRun` and its header comment, lines 3-70 today). Two test files change: `tests/core/domain/tst_runs.qml`, `tests/core/stores/tst_run_store.qml`. Nothing else.
- `core/domain/runs.js` stays `.pragma library`; no new `.import` (it keeps exactly `.import "board.js" as Board`). No UI or store imports.
- `docs/architecture.md` layering holds; `tests/architecture` must pass.
- Docstrings and comments state the contract only, with no narrative.
- am test inputs come only from `tests/fixtures/am/` (via `F.load` / `amRun`), unless they are labelled `synthetic:` in a comment naming what they stand for. An edit to a capture is made on a fresh copy, is labelled, and never changes the shape. Hand-built normalized runs (`mkRun`, `sampleTree`, `detailRun`, …) stay as they are.
- `normalizeRun` keeps am's spelling of `status`. The 12 top-level output keys stay exactly `base_branch, branch_prefix, id, lease, milestone_id, repo_dir, requests, rows, started_at, status, tree, workflow`; `lease` keeps only `pid, host, heartbeat_at, accepting, live`.
- `defaultAttempt`, `currentPhase`, `cardRunState`, `runsTouching`, `runTree`, `attemptStatus`, `rollup`, `runProgress`, `escalationReason`, `glyphStateOf` are **not edited**. `rollup` / `runProgress` / `runTree` node `currentPhase`/`currentAttempt` / `escalationReason` are **not asserted** on real data.
- `RunStore.qml`, every screen, `tests/ui/*`, the fixtures and the backend are not touched.
- `bash tests/run.sh` is green at the end of every task (pytest, `tests/contract`, `tests/architecture`, every QML test).
- Never `git stash`; commit at the end of each task as written.
- No QML test function name may end in `_data`: QtTest takes such a function as the data provider of another test and never runs it (checked: it is silently skipped). The spec's test 9, `test_normalize_proto_key_is_data`, is therefore named `test_normalize_own_proto_key_never_sets_prototype` here. Its content is the spec's.

## Review Focus

1. An own `__proto__` key in am's JSON (story, subtask or phase): a naive `out[key] = …` copy would set the copy's prototype and leak `x`. Expected: every copy's prototype is `Object.prototype`, `copy.x` is `undefined`, nothing throws. Pinned in Task 1 by `test_normalize_own_proto_key_never_sets_prototype`.
2. A story whose `subtasks` is missing or not an array, and non-object elements in `stories` / `subtasks` / `rows`: expected `subtasks: []` on that story, garbage elements skipped, never a throw. Pinned in Task 1 by `test_normalize_tree_garbage`.
3. An Integrate resolver row that is the last row (its `subtask` is a real story id): if kept, `defaultAttempt`'s rows fallback opens `b429248c… resolve 1` instead of `5d5114f9… review 1`. Pinned in Task 1 by `test_normalize_integrate_story_kept_resolver_dropped` and `test_fixture_current_phase_and_default_attempt`.
4. Mutation through the output (a screen editing a run) or of the input after the call (the next snapshot): expected no shared object or array in either direction. Pinned in Task 1 by `test_normalize_copies_never_am_objects`.
5. A `bases` story with `base-*` subtasks and rows: expected the story kept with its id list, its subtask not in `tree.subtasks`, its `base-*` rows kept (only rows whose subtask is a real card id are dropped). Pinned in Task 1 by `test_normalize_base_rows_kept`.

---

## Spec (prepended; headings demoted one level)

## 2.1 runs.js: normalizeRun reads am's nested tree and rows — design

Card `bd534ea9`, a subtask of story `21f9cd5a` ("Normalize real am status").
Parent spec: `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
(below: **parent**). Work breakdown item 2 (parent L324-326): this subtask is
"`normalizeRun` (with its red-then-green fixture tests in the same subtask)"
only. `rollup`, `runProgress`, `runTree`'s open attempt, `escalationReason` and
`glyphStateOf` are the story's later subtasks (2.2-2.4).

### Goal

`Runs.normalizeRun` turns a real `am status` payload into the parent's "Target
normalized run" (parent L182-203). Today it reads a top-level `subtasks` that am
never prints and passes am's rows through without renaming them, so on every
real run `tree.subtasks` is `[]` and no row has a `card_id` (parent L93). After
this subtask:

- `tree.stories` holds every am story, synthetic ones included. Each one is a
  copy of am's fields, and its `subtasks` is the list of its subtasks' card ids.
- `tree.subtasks` holds the subtasks of the non-synthetic stories, flattened in
  am's order. Each one is a deep copy that also carries `story_id`.
- `rows` holds am's rows, renamed to `{story_id, card_id, phase, attempt,
  status}`. Rows of Integrate resolvers are dropped.

The tests that prove it are built from the committed captures in
`tests/fixtures/am/`. They fail on today's code first. The RunStore tests that
hand-wrote the guessed shape are moved onto the same captures.

### Inherited constraints

| constraint | source |
|---|---|
| `am status` data has exactly `run, stories, rows, control, integrity`. There is no top-level `subtasks` | parent L20-21 |
| `run` has `id, workflow, repo_dir, base_branch, branch_prefix, status, started_at` and no `milestone_id`. Only `am runs` carries `milestone_id` | parent L23-24, L203 |
| A story is `card_id, title, level, status, tip_branch, subtasks[]`. Each subtask is an object `card_id, branch, base_branch, status, worktree_path, phases[]` | parent L25-27 |
| A phase is `name, kind, status, started_at, ended_at, detail, attempts[]`. A pending subtask has `phases: []`. An attempt's number is `n` | parent L28-32 |
| `rows[]` is `story, subtask, phase, attempt, state`, one row per attempt (`attempt: null` for a phase without attempts), in tree order | parent L33-36 |
| Synthetic stories: `integrate` holds one resolver subtask per conflicting story, and **its `card_id` is that real story's id**. `bases` holds `base-<story id>` subtasks | parent L40-44 |
| Decision 1: keep the flat normalized shape (`tree.stories[]`, `tree.subtasks[]`, `rows[]` keyed by `card_id`). Each subtask carries its story id | parent L143-147 |
| Decision 2: a subtask under `integrate` or `bases` is not put in `tree.subtasks`. Rows under a synthetic story whose subtask id is a real card id are dropped. `base-*` rows are kept. Synthetic stories stay in `tree.stories` | parent L148-154 |
| Decision 3 (first half): rows stay per attempt | parent L155 |
| Target output shape: the top-level keys and their types are unchanged. `tree.stories[].subtasks` is a list of id strings. `tree.subtasks[].story_id` is **new**. `rows` are renamed, with resolver rows dropped | parent L184-200 |
| "Copies, never am's objects. Anything missing or malformed becomes its default, as today. `milestone_id` keeps coming from the `am runs` row" | parent L202-203 |
| Acceptance numbers (stories / subtasks / rows, currentPhase, defaultAttempt) per fixture | parent L211-217 |
| `cardRunState(…"299ec9c0…")` on the started run is `running`, `explore`, 1. On the escalated run `eb8b1851…` is `escalated`, dimmed, `review`, 1. `runTree` of `status-done.json` has stories of 2, 3, 1, 4 subtasks. `runTree` of `status-done-integrate.json` has one synthetic `Integrate`, status `done`, and no `Other` group | parent L222-227 |
| Rule: every unit test of code that reads am output (`normalizeRun`, `RunStore`'s snapshot and logs handling) builds its input from the fixtures. A hand-written am payload is only allowed for a synthetic edge case, labelled `synthetic:`. A test edit to a fixture is made on a fresh copy, labelled, and never changes the shape. Tests of code past `normalizeRun` may keep building normalized runs by hand | parent L257-267 |
| QML loads fixtures with `tests/helpers/amFixtures.js` `load(name)`, which returns a fresh parse | parent L269-274 |
| `normalizeRun` keeps am's spelling of `status` | parent L294 |
| Not changed: the normalized shape's existing keys and their meaning. `rows` keeps per-attempt granularity | parent L308-309 |
| `docs/architecture.md` layering. `tests/architecture` must pass. `core/domain/*.js` stays `.pragma library` with no UI or store imports | card |
| Docstrings and comments state the contract only, with no narrative | card |
| `bash tests/run.sh` is green | card |

### Fixture facts this design relies on (checked 2026-10-05 against the committed files)

Each run is `normalizeRun({row: <its am runs row without "status">, status:
F.load(<fixture>).data})`. The row of `status-started.json` is `runs.json`
`data.runs[0]`. The row of `status-done.json` is `data.runs[1]`. The e2e
fixtures carry theirs in `_am_runs_row`.

| fixture | run id | am stories (subtasks each) | am rows | normalized stories / subtasks / rows |
|---|---|---|---|---|
| `status-started.json` | `20261005T021400Z-837c4431` | 4 (2, 3, 1, 2) | 44 | 4 / 8 / 44 |
| `status-done.json` | `20261004T204141Z-cb11063d` | 4 (2, 3, 1, 4) | 140 | 4 / 10 / 140 |
| `status-escalated.json` | `20261005T032543Z-bcc4e411` | 3 (2, 1, 1) | 40 | 3 / 4 / 40 |
| `status-done-integrate.json` | `20261005T033004Z-2f6878ac` | 3 (1, 1, and `integrate` with 1) | 30 | 3 / 2 / 28 |

- `status-started.json`
  - Its runs row: `workflow` `milestone`, `base_branch` `main`, `branch_prefix`
    `dsp`, `started_at` `2026-10-05 02:14:00.590972+00:00`, `milestone_id`
    `837c4431-7a24-4531-96a8-881698ea8c5e`.
  - `control.lease`: `pid` 3736962, `host` `mtts-desktop`, `heartbeat_at`
    `2026-10-05T03:30:22.281942+00:00`, `live` true, `accepting` true. It also
    has `acquired_at`, which normalizeRun does not keep. `control.requests` is
    `[]`.
  - `rows[0]` is `{story 1c665cfd-9a72-4a9d-a539-4c83f0f6ddc1, subtask
    5eb7ec0c-9bb1-41cd-a0ca-506b4ab4f4ff, phase worktree, attempt null, state
    done}`.
  - The open subtask `299ec9c0-b935-4c44-a7a0-982a104cbfe5` is
    `stories[1].subtasks[1]`, under story
    `d3d879b9-cb74-41ca-9a37-63f477de9711`. It is `tree.subtasks[3]` after
    flattening. Its phases are `worktree` (done, no attempts) and `explore`
    (started, `attempts[0]` = `{n: 1, status: "started"}`).
  - `5eb7ec0c…` is done. Its phase `spec` has attempt `{n: 1, status: "ok"}`.
- `status-done.json`
  - The last subtask is `22153f5f-9632-4b5f-a7dd-664c39d89e5c`, under story
    `f03629a7-5912-4b36-82b2-12f3b567294a`.
  - The last am row is `mark_done`, `attempt: null`.
- `status-escalated.json`: subtask `eb8b1851-8245-45c3-9a29-d1fcefaad0b9`
  (story `3f5aadb9…`) is `escalated`. Its last phase is `review`, attempt 1
  `gate_failed`. The run's lease is null.
- `status-done-integrate.json`
  - `stories[2]` is `{card_id: "integrate", title: "Integrate", status:
    "done"}`. Its one subtask's `card_id` is
    `b429248c-c69e-4df5-8f7d-52776253ea14`, which is also the id of real story
    `stories[1]`.
  - Two rows have `story: "integrate"`: `resolve` attempt 1 `ok`, and `verify`
    attempt null `done`. They are the last two rows.
  - Without the drop, the rows fallback of `defaultAttempt` would return
    `b429248c… resolve 1` instead of `5d5114f9… review 1`.
- No capture contains a `bases` story or a `base-*` row. Keeping `base-*` rows
  can only be shown on a labelled synthetic edit.
- A node prototype of this design on the committed fixtures gives every number
  in the table above, together with these values, all under the **current**
  downstream helpers:

| fixture | `currentPhase` | `defaultAttempt` | `runTree` stories (synthetic) |
|---|---|---|---|
| started | `explore` | `299ec9c0… explore 1` | 2, 3, 1, 2 (none) |
| done | `""` | `22153f5f… review 1` | 2, 3, 1, 4 (none) |
| escalated | `""` | `eb8b1851… review 1` | 2, 1, 1 (none) |
| done-integrate | `""` | `5d5114f9… review 1` | 1, 1 (one `Integrate`, `done`), no `Other` |

  Today's code gives `defaultAttempt` null and `tree.subtasks` 0 on all four.

### Behavior

#### Input

`raw = {row, status}`.

- `row` is one `am runs` entry without its `status` object: `id, workflow,
  repo_dir, base_branch, branch_prefix, status, started_at, milestone_id,
  card_id, lease, progress`.
- `status` is `am status` data: `{run, stories, rows, control, integrity}`.

Either part may be absent or garbage.

#### Output: unchanged keys

The 12 top-level keys stay exactly the same: `base_branch, branch_prefix, id,
lease, milestone_id, repo_dir, requests, rows, started_at, status, tree,
workflow`. The rules for `id`, `repo_dir`, `milestone_id`, `status`,
`started_at`, `base_branch`, `branch_prefix`, `workflow`, `lease` and
`requests` do not change (row first or am status first, exactly as today).
`lease` keeps only its five keys.

#### Output: `tree.stories`

There is one entry per **object** element of `status.stories`, in am's order,
synthetic stories (`integrate`, `bases`) included.

- Each entry is a deep copy of the am story's own keys.
- `subtasks` is replaced by an array of the `card_id` of every object element
  of the am story's `subtasks`, in order. Only string ids are kept.
- When am's `subtasks` is missing or is not an array, `subtasks` is `[]`.
- Non-object elements (null, strings, numbers, arrays) of `status.stories` are
  skipped.
- When `status.stories` is not an array, `tree.stories` is `[]`.

#### Output: `tree.subtasks`

For each object story whose `card_id` is not `integrate` or `bases`, in story
order, take every object element of its `subtasks` array in order. Output a
deep copy of it with one added key: `story_id`, which is the story's `card_id`
when that is a string, else `""`.

- The phases and attempts inside are copies too, with every key am gave kept
  as given.
- Subtasks of `integrate` and `bases` are never included.
- Non-object subtask elements are skipped.
- A story with no array `subtasks` adds nothing.

#### Output: `rows`

There is one entry per object element of `status.rows`, in am's order:

```
{ story_id: <row.story>, card_id: <row.subtask>, phase: <row.phase>,
  attempt: <row.attempt>, status: <row.state> }
```

- `story_id`, `card_id`, `phase` and `status` are am's value when it is a
  string, else `""`.
- `attempt` is am's value when it is a finite number, else `null`. am's own
  `null` stays `null`.
- No other keys are kept.
- **Dropped:** a row whose `story` is `integrate` or `bases` **and** whose
  `subtask` is a real card id (a non-empty string that is not `integrate`,
  `bases` or `base-*`). These are the Integrate resolvers.
- **Kept:** rows under a synthetic story whose subtask is synthetic
  (`base-*`).
- Non-object elements are skipped.
- When `status.rows` is not an array, `rows` is `[]`.

#### Copies

No object or array in the output is one of am's. Changing any output story,
subtask, phase, attempt or row leaves `raw` unchanged, and changing `raw` after
the call leaves the output unchanged.

A key named `__proto__` that am's JSON carries as an own key never changes a
copy's prototype. The copy keeps it as an own key or drops it. Every copied
object's prototype stays `Object.prototype`.

#### Never throws

Garbage gives the defaults, as today. `normalizeRun(undefined | null | "x" | 5 |
{} | [])` and every malformed part still produce the 12 keys, with `rows`,
`tree.stories` and `tree.subtasks` as empty arrays.

#### Header comment (`core/domain/runs.js` lines 3-20)

Replace the provisional text with the real input shape and the output rules
above, contract only. Content:

- The input: an `am runs` row (fields as listed above) and `am status` data
  (`run`, `stories[{card_id, title, level, status, tip_branch,
  subtasks[{card_id, branch, base_branch, status, worktree_path,
  phases[{name, kind, status, started_at, ended_at, detail, attempts[{n,
  status, …}]}]}]}]`, `rows[{story, subtask, phase, attempt, state}]`,
  `control{lease, requests, claims}`, `integrity`).
- The source of each scalar.
- The `tree` and `rows` rules: ids-only story subtasks, `story_id`, synthetic
  stories out of `tree.subtasks`, resolver rows dropped, renamed row keys.
- "copies, never throws".

Drop "provisional until the runs-snapshot helper exists".

#### Downstream (read only here)

`defaultAttempt`, `currentPhase`, `cardRunState`, `runsTouching`, `runTree` and
`attemptStatus` are **not edited**. Over the new output they give the values in
the facts table and in parent L222-227. `_storyHas` already accepts id strings.

`rollup`, `runProgress`, `runTree`'s per-node open attempt and
`escalationReason` still have their old logic. This subtask does not assert
them on real data.

### Tests

All tests below are QML unit tests (`qmltestrunner` through `tests/run.sh`).
`normalizeRun` is a pure `.pragma library` function, and RunStore's snapshot
handling is a QML object driven through stubbed `Process` objects. Both already
live in this tier: `tests/core/domain/tst_runs.qml` (TestCase `DomainRuns`) and
`tests/core/stores/tst_run_store.qml` (`StoresRunStore`).

Both files add `import "../../helpers/amFixtures.js" as F`. A helper in
`tst_runs.qml`, `amRun(name)`, returns the raw input for a fixture:

- the row is a fresh copy of the matching `runs.json` entry (by
  `data.run.id`) or the fixture's `_am_runs_row`, with `status` deleted;
- the status is `F.load(name).data`.

Red first: every test marked **(red)** fails on today's `normalizeRun`, because
of `tree.subtasks.length` 0, rows without `card_id`, or `defaultAttempt` null.

#### `tests/core/domain/tst_runs.qml`

1. **`test_normalize_fixture_counts`** (red). For each of the four fixtures,
   check `tree.stories` / `tree.subtasks` / `rows` lengths: 4/8/44, 4/10/140,
   3/4/40, 3/2/28.
2. **`test_normalize_scalars_from_fixture`**. This replaces
   `test_normalize_full`'s scalar half, over `status-started.json`:
   - the 12-key set;
   - `id` `20261005T021400Z-837c4431`, `milestone_id`
     `837c4431-7a24-4531-96a8-881698ea8c5e` (from the row), `status`
     `started`, `workflow` `milestone`, `base_branch` `main`, `branch_prefix`
     `dsp`, `started_at` `2026-10-05 02:14:00.590972+00:00`;
   - the lease's 5 keys and their values;
   - `requests` is `[]`.
3. **`test_normalize_stories_are_id_lists`** (red). Over `status-started.json`:
   - `tree.stories[1].card_id` is `d3d879b9…`. Its `subtasks` is exactly
     `["a19ca446-659e-4735-86ed-5a583c1730bf",
     "299ec9c0-b935-4c44-a7a0-982a104cbfe5",
     "fdb5feb1-0907-40b2-9937-d9b4cc2875f0"]`, every element a string.
   - `title`, `level`, `status` and `tip_branch` equal am's.
   - The key set is am's (`card_id, level, status, subtasks, tip_branch,
     title`).
4. **`test_normalize_subtasks_flatten_with_story_id`** (red). Over
   `status-started.json`:
   - `tree.subtasks` card ids in order equal am's flattened order;
   - each `story_id` equals its am story's id;
   - `tree.subtasks[3].card_id` is `299ec9c0…` and its `story_id` is
     `d3d879b9…`;
   - its key set is am's six keys plus `story_id`;
   - `phases[1].name` is `explore` and `phases[1].attempts[0].n` is 1.
5. **`test_normalize_rows_renamed`** (red). Over `status-started.json`:
   - `rows[0]` key set is `attempt,card_id,phase,status,story_id`;
   - `rows[0]` values are `1c665cfd…`, `5eb7ec0c…`, `worktree`, `null`,
     `done`;
   - `rows[43]` is `d3d879b9…`, `299ec9c0…`, `explore`, `1`, `started`.
6. **`test_normalize_integrate_story_kept_resolver_dropped`** (red). Over
   `status-done-integrate.json`:
   - `tree.stories[2]` is `integrate`, with `subtasks`
     `["b429248c-c69e-4df5-8f7d-52776253ea14"]` and `status` `done`;
   - no `tree.subtasks` entry has `story_id` `integrate`, and none has card id
     `b429248c…`;
   - `rows.length` is 28 and no row has `story_id` `integrate`.
7. **`test_normalize_base_rows_kept`** (red). This is a synthetic edit,
   labelled `synthetic: a bases story, which no capture contains`. On a fresh
   `status-done-integrate.json`, add a `bases` story with one `base-<story id>`
   subtask (am's subtask key set, `phases: []`), plus one am row `{story:
   "bases", subtask: "base-…", phase: "verify", attempt: null, state:
   "done"}`. Then:
   - the `bases` story is in `tree.stories` with the id list;
   - the `base-…` subtask is not in `tree.subtasks`;
   - the row is kept with `story_id` `bases`;
   - the two `integrate` resolver rows are still dropped.
8. **`test_normalize_copies_never_am_objects`** (red today because rows and
   stories are am's own arrays). Over `status-started.json`, after
   normalizing:
   - mutate the output's `tree.stories[1].title`, `tree.subtasks[3].phases[1]
     .attempts[0].status`, `rows[0].phase` and `tree.stories[1].subtasks[0]`;
   - assert the input object (kept in a variable) is unchanged;
   - also check `!==` identity for `tree.subtasks[3].phases` against the
     input's `stories[1].subtasks[1].phases`.
9. **`test_normalize_proto_key_is_data`**. This is a synthetic edit labelled
   `synthetic: an own __proto__ key, which no capture contains`. Set a story,
   a subtask and a phase built with `JSON.parse('{"__proto__": {"x": 1}, …}')`
   in a fresh `status-started.json`. Then:
   - each copy's prototype is `Object.prototype`;
   - `copy.x` is `undefined`;
   - nothing throws.
10. **`test_normalize_tree_garbage`**. This extends today's
    `test_normalize_missing_rows_tree`, labelled `synthetic:`. On a fresh
    `status-started.json`:
    - `stories` set to `[null, 5, "s", [], {card_id: "s9"}, {card_id: "s8",
      subtasks: "x"}, {card_id: "s7", subtasks: [null, 3, {card_id: 4},
      {card_id: "t7"}]}]`;
    - `rows` set to `[null, "r", 7, {}, {story: 1, subtask: "t7", phase: [],
      attempt: "2", state: {}}]`.

    Assert:
    - stories `s9`, `s8` and `s7` are kept, with `subtasks` `[]`, `[]` and
      `["t7"]`;
    - `tree.subtasks` has the two objects of `s7` (`{card_id: 4}` and `t7`),
      both with `story_id` `s7`;
    - rows give two entries: `{}` becomes all `""` with `attempt` `null`, and
      the last becomes `story_id ""`, `card_id "t7"`, `phase ""`, `attempt
      null`, `status ""`.

    Keep today's non-array `rows`, `stories` and `subtasks` cases. A top-level
    `status.subtasks` is ignored whatever its value.
11. **`test_normalize_garbage`**. This stays as it is (`checkDefaults` keeps the
    12 keys), with a `synthetic:` label.
12. **`test_fixture_current_phase_and_default_attempt`** (red for
    `defaultAttempt`). Over the four fixtures:
    - `currentPhase`: `explore`, `""`, `""`, `""`;
    - `defaultAttempt`: `{299ec9c0…, explore, 1}`, `{22153f5f…, review, 1}`,
      `{eb8b1851…, review, 1}`, `{5d5114f9…, review, 1}`.
13. **`test_fixture_card_run_state_and_runs_touching`** (red). Normalize the
    four fixtures into `runs` (started first, then done, escalated,
    done-integrate). Then:
    - `cardRunState(runs, "299ec9c0…")` is `{state: running, dimmed: false,
      phase: explore, attempt: 1}`, with `runId` the started run's id;
    - `cardRunState(runs, "eb8b1851…")` is `{state: escalated, dimmed: true,
      phase: review, attempt: 1}`;
    - `runsTouching(runs, "299ec9c0…")` is exactly the started run;
    - `runsTouching(runs, "5d5114f9…")` is exactly the done-integrate run;
    - `runsTouching(runs, "b429248c…")` is exactly the done-integrate run,
      through its real story, length 1.
14. **`test_fixture_run_tree_grouping`** (red). Check these `runTree` results:
    - `status-done.json`: four story groups whose `card_id`s are am's story ids
      in order, with 2, 3, 1 and 4 subtasks; `synthetic` is `[]`; no `other`
      group; each subtask node's `card_id` in am's order.
    - `status-done-integrate.json`: two story groups of 1 each; `synthetic` is
      exactly `[{id: "integrate", label: "Integrate", status: "done"}]`; no
      group has `other: true`.

    Do **not** assert node `currentPhase` / `currentAttempt` (2.3), `rollup` or
    `runProgress` (2.2).

##### Re-pointing `fullRaw` and the other existing tests

Delete `fullRaw()`. Each former user takes its input from `amRun(...)` and
keeps its meaning:

| test | change |
|---|---|
| `test_normalize_full` (L50-70) | Replaced by tests 2-5 |
| `test_normalize_status_prefers_am_status`, `test_normalize_missing_lease`, `test_normalize_lease_live_strict`, `test_state_running`, `test_state_dead_not_live`, `test_state_dead_missing_lease`, `test_normalize_workflow`, `test_normalize_requests`, `test_normalize_requests_garbage` | Start from `amRun("status-started.json")`. Every edit is a labelled edit on that fresh copy (for example `synthetic: a request, which no capture contains`). Expected values that came from `fullRaw` are re-pointed to the fixture's: `orchestrator` becomes `milestone`, `r1` becomes the run id |
| `test_normalize_keeps_started_at` (L704) | First line expects `2026-10-05 02:14:00.590972+00:00` |
| `test_normalize_branch_fields` (L862) | Expects `main` / `dsp` |

Small inline inputs that are not am captures stay as they are, each with a
`synthetic:` label naming what it stands for. Examples are `{row: {id: 7}}`,
the `raw(lease)` helper at L1220, and the `newAlerts` input at L1507.

Hand-built normalized runs (`mkRun`, `sampleTree`, …) stay (parent L262-265).

Replace the file header comment at L6-10 with one line: normalizeRun's input is
built from `tests/fixtures/am/` via `amRun`.

#### `tests/core/stores/tst_run_store.qml`

These RunStore tests move onto fixture data and keep their meaning. Add
`readonly property string openCard: "299ec9c0-b935-4c44-a7a0-982a104cbfe5"`
and `readonly property string doneCard:
"5eb7ec0c-9bb1-41cd-a0ca-506b4ab4f4ff"`.

- **`treeEntry(id, status)`** (L915-921) returns a snapshot entry:
  - a fresh copy of `runs.json` `data.runs[0]`, with `id` and `repo_dir` set to
    the test's values (`id`, `rootA`);
  - its `status` is a fresh `F.load("status-started.json").data`, with
    `run.id` set to `id`;
  - the open attempt `stories[1].subtasks[1].phases[1].attempts[0].status` is
    set to `status`.

  The comment says: test-local run id and repo dir; the open attempt's status
  is the test's. Callers pass `started` or `ok` (am attempt vocabulary).
  `"done"` becomes `"ok"`.
- `opened(status)`: unchanged apart from the default `"started"`.
- Every `r1|t1|implement|2` becomes `r1|<openCard>|explore|1`. Every
  `selectedAttempt` `t1` / `implement` / `2` becomes `openCard` / `explore` /
  `1`.
- Every `selectAttempt("t1", "spec", 1)` becomes `selectAttempt(tc.doneCard,
  "spec", 1)`, with argv `r1|<doneCard>|spec|1` and `logsStatus` `ok` (was
  `done`).
- The invalid-argument calls in `test_no_logs_launch_without_project_run_or_selection`
  use `tc.doneCard` for the card.
- **L1087-1088.** `r2` is a fresh copy of `runs.json` `data.runs[1]`, with `id`
  `r2` and `repo_dir` `rootA`. Its `status` is a fresh
  `F.load("status-done.json").data` with `run.id` `r2`. The expected default
  attempt becomes `22153f5f-9632-4b5f-a7dd-664c39d89e5c` / `review` / `1` and
  the argv `r2|22153f5f…|review|1`.
- **`test_a_snapshot_that_changes_the_attempt_status_fetches_once`:**
  `treeEntry("r1", "done")` becomes `treeEntry("r1", "ok")`. The message reads
  "started -> ok". `logsStatus` is `ok`.
- **L1180 `bare`:** `treeEntry("r1", "started")` with every subtask's `phases`
  set to `[]` and `status.rows` set to `[]`. The label says: `synthetic: the
  run before any attempt exists; shape kept`. Both edits are needed:
  otherwise `defaultAttempt`'s first-started-phase branch or its rows fallback
  finds the done subtasks' attempts. The second snapshot is
  `treeEntry("r1", "started")`. Expected: `selectedAttempt.attempt` 1, argv
  `r1|<openCard>|explore|1`.
- The comment above `treeEntry` is rewritten to say what the entry is (the
  started capture; open attempt `299ec9c0…` explore 1; a done earlier attempt
  `5eb7ec0c…` spec 1).

#### Unchanged and must stay green

`tests/ui/*` (normalized runs built by hand; parent L262-265), the backend
pytest suites, `tests/contract`, `tests/architecture`, and every other test in
both files.

### Out of scope

- `rollup`, `runProgress` (2.2). `runTree`'s per-node open attempt (decision
  4). `escalationReason` (decision 5). `glyphStateOf` (decision 6). This
  includes asserting any of these on real data, and `status-escalated-integrate.json`'s
  escalation reason.
- `logTail`, `logsReply`'s `data.stdout` strings (L925), `runs-logs.py
  --repo-dir`, `RunStore` passing the root, and `tests/ui/tst_runs_flow.qml:185`
  / `:201` (story 3).
- The `canceled` spelling and hello schema 2 (story 4).
- `RunStore.qml` and every screen. `entry()`'s guessed `subtasks: []` key at
  `tst_run_store.qml:49`, which the new normalizeRun ignores harmlessly, and
  the other store tests built on `entry()`.
- Docs (story 5).
- Showing Integrate resolver attempts (parent L316-317).

### For the planner

- One code file changes: `core/domain/runs.js` (`normalizeRun` and its header
  comment). Two test files change.
- `normalizeRun` may call the file-level `_isSynthetic` and `_isCardId`. They
  are hoisted function declarations defined below it.
- The deep copy must be JSON-like (arrays and plain objects, recursive). It
  must be safe for an own `__proto__` key: `Object.keys` plus
  `Object.defineProperty`, or skip that key.
- Suggested tasks:
  1. The fixture tests in `tst_runs.qml`, red then green, with the
     `normalizeRun` rewrite and header comment.
  2. Re-point `fullRaw` users.
  3. Move `tst_run_store.qml` onto fixture data.
- Global constraints to copy:
  - `.pragma library`, no new imports in `runs.js`;
  - comments state the contract only;
  - am test inputs come only from `tests/fixtures/am/`, unless they are
    labelled `synthetic:`;
  - `bash tests/run.sh` green.
- `bash tests/run.sh tst_runs` and `bash tests/run.sh tst_run_store` run a
  subset (pytest still runs first).
- Review Focus candidates:
  - an own `__proto__` key (test 9);
  - a story whose `subtasks` is not an array (test 10);
  - a resolver row that is the last row (test 6 via `defaultAttempt` in test
    12);
  - mutation through the output (test 8);
  - a `bases` story (test 7).

---

## File Structure

| file | change | responsibility |
|---|---|---|
| `core/domain/runs.js` | Modify lines 3-70 (header comment + `normalizeRun`) | am `runs` row + `am status` data -> normalized run |
| `tests/core/domain/tst_runs.qml` | Modify | `normalizeRun` unit tests from the captures (`amRun`), plus downstream helpers over the new output |
| `tests/core/stores/tst_run_store.qml` | Modify (`treeEntry` and the attempt-logs tests, about L911-1190) | RunStore's attempt-logs behaviour fed by the started / done captures |

Task order: Task 1 changes `normalizeRun` and moves the RunStore attempt-logs tests onto the captures in the same commit, because those tests hand-write the old guessed shape (top-level `subtasks`) and would go red the moment `normalizeRun` stops reading it. Task 2 re-points the remaining `fullRaw()` users (tests that already pass on the new code) and labels the synthetic inputs.

Running tests: `bash tests/run.sh <substring>` runs pytest, then each `tst_*.qml` whose path contains the substring, and prints only `FAIL…`, `Totals…` and `   Loc…` lines plus any `TypeError` / `ReferenceError` line. Exit status 1 means something failed.

---

### Task 1: normalizeRun reads am's nested tree and rows

**Files:**
- Modify: `core/domain/runs.js:3-70`
- Test: `tests/core/domain/tst_runs.qml` (import at L4; new helper after `fullRaw` at L30; delete `test_normalize_full` L50-71; replace `test_normalize_missing_rows_tree` L160-182; new tests after `test_normalize_garbage`)
- Test: `tests/core/stores/tst_run_store.qml` (import at L8; properties after L16; `treeEntry` L913-921; attempt-logs tests L950-1190)

**Interfaces:**
- Consumes: `F.load(name)` from `tests/helpers/amFixtures.js` (fresh `JSON.parse` of `tests/fixtures/am/<name>` per call; throws on a missing file). File-level `_isCardId(id)` in `runs.js` (hoisted; true for a non-empty string that is not `integrate`, `bases` or `base-*`). Existing test helpers in `tst_runs.qml`: `at(d)` (L1040: `"null"` or `card_id + "/" + phase + "/" + attempt`) and `cardIds(list)` (L968: the `card_id`s joined with `,`).
- Produces: `Runs.normalizeRun(raw)` -> `{ id, repo_dir, milestone_id, status, started_at, base_branch, branch_prefix, workflow, lease, requests, rows: [{story_id, card_id, phase, attempt, status}], tree: { stories: [{…am story keys, subtasks: [string]}], subtasks: [{…am subtask keys, story_id}] } }`. In `tst_runs.qml`: `amRun(name)` -> `{ row, status }` (fresh), and `fixtureRuns()` -> the four normalized captures `[started, done, escalated, done-integrate]`. In `tst_run_store.qml`: `tc.openCard`, `tc.doneCard`, and `treeEntry(id, status)` built from the started capture.

- [ ] **Step 1: Import the fixture loader and add `amRun` in `tst_runs.qml`**

In `tests/core/domain/tst_runs.qml`, after line 4 (`import "../../../core/domain/runs.js" as Runs`) add:

```qml
import "../../helpers/amFixtures.js" as F
```

Directly after the closing `}` of `fullRaw()` (line 30), add:

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

  // The four captures, normalized, in this order: started, done, escalated,
  // done-integrate.
  function fixtureRuns() {
    return [Runs.normalizeRun(amRun("status-started.json")), Runs.normalizeRun(amRun("status-done.json")),
            Runs.normalizeRun(amRun("status-escalated.json")), Runs.normalizeRun(amRun("status-done-integrate.json"))]
  }
```

- [ ] **Step 2: Delete `test_normalize_full`**

Delete the whole function `test_normalize_full()` (lines 50-71, from `  function test_normalize_full() {` through its closing `  }` and the blank line after it). Its scalar half moves to `test_normalize_scalars_from_fixture` and its tree half to tests 3-5 below.

- [ ] **Step 3: Replace `test_normalize_missing_rows_tree` with `test_normalize_tree_garbage`**

Replace the whole function `test_normalize_missing_rows_tree()` (lines 160-182 before Step 2's deletion) with:

```qml
  function test_normalize_tree_garbage() {
    // synthetic: am status with only a run
    var bare = Runs.normalizeRun({ status: { run: { status: "started" } } })
    compare(Array.isArray(bare.rows), true)
    compare(bare.rows.length, 0)
    compare(bare.tree.stories.length, 0)
    compare(bare.tree.subtasks.length, 0)

    // synthetic: rows, stories and a top-level subtasks that are not arrays
    var raw = amRun("status-started.json")
    raw.status.rows = { a: 1 }
    raw.status.stories = {}
    raw.status.subtasks = "x"
    var r = Runs.normalizeRun(raw)
    compare(Array.isArray(r.rows), true)
    compare(r.rows.length, 0)
    compare(Array.isArray(r.tree.stories), true)
    compare(r.tree.stories.length, 0)
    compare(Array.isArray(r.tree.subtasks), true)
    compare(r.tree.subtasks.length, 0)

    // synthetic: rows as a string
    var strRows = amRun("status-started.json")
    strRows.status.rows = "x"
    compare(Runs.normalizeRun(strRows).rows.length, 0)

    // synthetic: a top-level subtasks list, which am never prints
    var topLevel = amRun("status-started.json")
    topLevel.status.subtasks = [{ card_id: "zz", phases: [] }]
    var t = Runs.normalizeRun(topLevel)
    compare(t.tree.subtasks.length, 8, "a top-level subtasks is ignored")
    for (var i = 0; i < t.tree.subtasks.length; i++) verify(t.tree.subtasks[i].card_id !== "zz", "no zz at " + i)

    // synthetic: garbage elements in place of the capture's stories and rows
    var junk = amRun("status-started.json")
    junk.status.stories = [null, 5, "s", [], { card_id: "s9" }, { card_id: "s8", subtasks: "x" },
                           { card_id: "s7", subtasks: [null, 3, { card_id: 4 }, { card_id: "t7" }] }]
    junk.status.rows = [null, "r", 7, {}, { story: 1, subtask: "t7", phase: [], attempt: "2", state: {} }]
    var g = Runs.normalizeRun(junk)
    compare(cardIds(g.tree.stories), "s9,s8,s7", "only object stories are kept")
    compare(JSON.stringify(g.tree.stories[0].subtasks), "[]", "missing subtasks")
    compare(JSON.stringify(g.tree.stories[1].subtasks), "[]", "subtasks not an array")
    compare(JSON.stringify(g.tree.stories[2].subtasks), "[\"t7\"]", "only string ids of object subtasks")
    compare(g.tree.subtasks.length, 2, "the two object subtasks of s7")
    compare(g.tree.subtasks[0].card_id, 4)
    compare(g.tree.subtasks[0].story_id, "s7")
    compare(g.tree.subtasks[1].card_id, "t7")
    compare(g.tree.subtasks[1].story_id, "s7")
    compare(g.rows.length, 2, "only object rows are kept")
    compare(JSON.stringify(g.rows[0]), JSON.stringify({ story_id: "", card_id: "", phase: "", attempt: null, status: "" }))
    compare(JSON.stringify(g.rows[1]), JSON.stringify({ story_id: "", card_id: "t7", phase: "", attempt: null, status: "" }))
  }
```

- [ ] **Step 4: Add the capture tests after `test_normalize_garbage`**

Directly after the closing `}` of `test_normalize_garbage()` add:

```qml

  // ---- 2.1: normalizeRun over the am captures ----------------------------------------------

  function test_normalize_fixture_counts() {
    var expected = [
      ["status-started.json", 4, 8, 44],
      ["status-done.json", 4, 10, 140],
      ["status-escalated.json", 3, 4, 40],
      ["status-done-integrate.json", 3, 2, 28]
    ]
    for (var i = 0; i < expected.length; i++) {
      var r = Runs.normalizeRun(amRun(expected[i][0]))
      compare(r.tree.stories.length, expected[i][1], expected[i][0] + " stories")
      compare(r.tree.subtasks.length, expected[i][2], expected[i][0] + " subtasks")
      compare(r.rows.length, expected[i][3], expected[i][0] + " rows")
    }
  }

  function test_normalize_scalars_from_fixture() {
    var r = Runs.normalizeRun(amRun("status-started.json"))
    compare(Object.keys(r).sort().join(","), "base_branch,branch_prefix,id,lease,milestone_id,repo_dir,requests,rows,started_at,status,tree,workflow")
    compare(r.id, "20261005T021400Z-837c4431")
    compare(r.repo_dir, "/home/user/Code/omarchy-project-manager")
    compare(r.milestone_id, "837c4431-7a24-4531-96a8-881698ea8c5e", "only the am runs row carries it")
    compare(r.status, "started")
    compare(r.workflow, "milestone")
    compare(r.base_branch, "main")
    compare(r.branch_prefix, "dsp")
    compare(r.started_at, "2026-10-05 02:14:00.590972+00:00")
    compare(Object.keys(r.lease).sort().join(","), "accepting,heartbeat_at,host,live,pid", "acquired_at is not kept")
    compare(r.lease.pid, 3736962)
    compare(r.lease.host, "mtts-desktop")
    compare(r.lease.heartbeat_at, "2026-10-05T03:30:22.281942+00:00")
    compare(r.lease.accepting, true)
    compare(r.lease.live, true)
    compare(Array.isArray(r.requests), true)
    compare(r.requests.length, 0)
  }

  function test_normalize_stories_are_id_lists() {
    var raw = amRun("status-started.json")
    var am = raw.status.stories[1]
    var s = Runs.normalizeRun(raw).tree.stories[1]
    compare(s.card_id, "d3d879b9-cb74-41ca-9a37-63f477de9711")
    compare(JSON.stringify(s.subtasks), JSON.stringify(["a19ca446-659e-4735-86ed-5a583c1730bf",
                                                        "299ec9c0-b935-4c44-a7a0-982a104cbfe5",
                                                        "fdb5feb1-0907-40b2-9937-d9b4cc2875f0"]))
    for (var i = 0; i < s.subtasks.length; i++) compare(typeof s.subtasks[i], "string", "id " + i)
    compare(s.title, am.title)
    compare(s.level, am.level)
    compare(s.status, am.status)
    compare(s.tip_branch, am.tip_branch)
    compare(Object.keys(s).sort().join(","), "card_id,level,status,subtasks,tip_branch,title")
  }

  function test_normalize_subtasks_flatten_with_story_id() {
    var raw = amRun("status-started.json")
    var r = Runs.normalizeRun(raw)
    var ids = [], storyIds = []
    for (var i = 0; i < raw.status.stories.length; i++) {
      var story = raw.status.stories[i]
      for (var j = 0; j < story.subtasks.length; j++) {
        ids.push(story.subtasks[j].card_id)
        storyIds.push(story.card_id)
      }
    }
    compare(cardIds(r.tree.subtasks), ids.join(","), "am's flattened order")
    for (var k = 0; k < r.tree.subtasks.length; k++) compare(r.tree.subtasks[k].story_id, storyIds[k], "story_id " + k)
    var open = r.tree.subtasks[3]
    compare(open.card_id, "299ec9c0-b935-4c44-a7a0-982a104cbfe5")
    compare(open.story_id, "d3d879b9-cb74-41ca-9a37-63f477de9711")
    compare(Object.keys(open).sort().join(","), "base_branch,branch,card_id,phases,status,story_id,worktree_path")
    compare(open.phases[1].name, "explore")
    compare(open.phases[1].attempts[0].n, 1)
  }

  function test_normalize_rows_renamed() {
    var r = Runs.normalizeRun(amRun("status-started.json"))
    compare(Object.keys(r.rows[0]).sort().join(","), "attempt,card_id,phase,status,story_id")
    compare(r.rows[0].story_id, "1c665cfd-9a72-4a9d-a539-4c83f0f6ddc1")
    compare(r.rows[0].card_id, "5eb7ec0c-9bb1-41cd-a0ca-506b4ab4f4ff")
    compare(r.rows[0].phase, "worktree")
    compare(r.rows[0].attempt, null)
    compare(r.rows[0].status, "done")
    compare(r.rows[43].story_id, "d3d879b9-cb74-41ca-9a37-63f477de9711")
    compare(r.rows[43].card_id, "299ec9c0-b935-4c44-a7a0-982a104cbfe5")
    compare(r.rows[43].phase, "explore")
    compare(r.rows[43].attempt, 1)
    compare(r.rows[43].status, "started")
  }

  function test_normalize_integrate_story_kept_resolver_dropped() {
    var r = Runs.normalizeRun(amRun("status-done-integrate.json"))
    var integrate = r.tree.stories[2]
    compare(integrate.card_id, "integrate")
    compare(JSON.stringify(integrate.subtasks), JSON.stringify(["b429248c-c69e-4df5-8f7d-52776253ea14"]))
    compare(integrate.status, "done")
    for (var i = 0; i < r.tree.subtasks.length; i++) {
      verify(r.tree.subtasks[i].story_id !== "integrate", "no subtask of integrate at " + i)
      verify(r.tree.subtasks[i].card_id !== "b429248c-c69e-4df5-8f7d-52776253ea14", "no resolver subtask at " + i)
    }
    compare(r.rows.length, 28, "the two resolver rows are dropped")
    for (var j = 0; j < r.rows.length; j++) verify(r.rows[j].story_id !== "integrate", "no integrate row at " + j)
  }

  function test_normalize_base_rows_kept() {
    // synthetic: a bases story, which no capture contains
    var raw = amRun("status-done-integrate.json")
    var baseId = "base-2f88f774-d2b6-4c8d-adc1-6ac9eb978017"
    raw.status.stories.push({ card_id: "bases", title: "Bases", level: 0, status: "done", tip_branch: "m3-bases",
                              subtasks: [{ card_id: baseId, branch: "m3-" + baseId, base_branch: "main", status: "done",
                                           worktree_path: "/tmp/m3-bases", phases: [] }] })
    raw.status.rows.push({ story: "bases", subtask: baseId, phase: "verify", attempt: null, state: "done" })
    var r = Runs.normalizeRun(raw)
    compare(r.tree.stories.length, 4)
    compare(r.tree.stories[3].card_id, "bases")
    compare(JSON.stringify(r.tree.stories[3].subtasks), JSON.stringify([baseId]))
    compare(r.tree.subtasks.length, 2, "the base subtask is not a tree subtask")
    for (var i = 0; i < r.tree.subtasks.length; i++) verify(r.tree.subtasks[i].card_id !== baseId, "no base subtask at " + i)
    compare(r.rows.length, 29, "28 real rows and the base row")
    var last = r.rows[28]
    compare(last.story_id, "bases")
    compare(last.card_id, baseId)
    compare(last.phase, "verify")
    compare(last.attempt, null)
    compare(last.status, "done")
    for (var j = 0; j < r.rows.length; j++) verify(r.rows[j].story_id !== "integrate", "resolver rows still dropped at " + j)
  }

  function test_normalize_copies_never_am_objects() {
    var raw = amRun("status-started.json")
    var before = JSON.stringify(raw)
    var r = Runs.normalizeRun(raw)
    verify(r.tree.stories[1] !== raw.status.stories[1], "story is a copy")
    verify(r.tree.subtasks[3] !== raw.status.stories[1].subtasks[1], "subtask is a copy")
    verify(r.tree.subtasks[3].phases !== raw.status.stories[1].subtasks[1].phases, "phases are a copy")
    verify(r.tree.subtasks[3].phases[1].attempts[0] !== raw.status.stories[1].subtasks[1].phases[1].attempts[0],
           "attempt is a copy")
    verify(r.rows[0] !== raw.status.rows[0], "row is a copy")
    r.tree.stories[1].title = "changed"
    r.tree.subtasks[3].phases[1].attempts[0].status = "changed"
    r.rows[0].phase = "changed"
    r.tree.stories[1].subtasks[0] = "changed"
    compare(JSON.stringify(raw), before, "changing the output leaves the input unchanged")

    var later = amRun("status-started.json")
    var out = Runs.normalizeRun(later)
    var outBefore = JSON.stringify(out)
    later.status.stories[1].title = "later"
    later.status.stories[1].subtasks[1].phases[1].attempts[0].status = "later"
    later.status.stories[1].subtasks.push({ card_id: "later" })
    later.status.rows[0].phase = "later"
    compare(JSON.stringify(out), outBefore, "changing the input after the call leaves the output unchanged")
  }

  function test_normalize_own_proto_key_never_sets_prototype() {
    // synthetic: an own __proto__ key, which no capture contains
    function withProto(o) { return JSON.parse('{"__proto__": {"x": 1}, ' + JSON.stringify(o).slice(1)) }
    var raw = amRun("status-started.json")
    var amStory = raw.status.stories[1]
    var phase = withProto(amStory.subtasks[1].phases[1])
    var subtask = withProto(amStory.subtasks[1])
    subtask.phases[1] = phase
    var story = withProto(amStory)
    story.subtasks[1] = subtask
    raw.status.stories[1] = story
    verify(Object.prototype.hasOwnProperty.call(story, "__proto__"), "the input carries an own __proto__ key")

    var r = Runs.normalizeRun(raw)
    var copies = [["story", r.tree.stories[1]], ["subtask", r.tree.subtasks[3]], ["phase", r.tree.subtasks[3].phases[1]]]
    for (var i = 0; i < copies.length; i++) {
      compare(Object.getPrototypeOf(copies[i][1]) === Object.prototype, true, copies[i][0] + " prototype")
      compare(copies[i][1].x, undefined, copies[i][0] + " x")
    }
    compare(r.tree.subtasks[3].card_id, "299ec9c0-b935-4c44-a7a0-982a104cbfe5", "the rest is copied")
    compare(r.tree.subtasks[3].phases[1].name, "explore")
  }

  function test_fixture_current_phase_and_default_attempt() {
    var expected = [
      ["explore", "299ec9c0-b935-4c44-a7a0-982a104cbfe5/explore/1"],
      ["", "22153f5f-9632-4b5f-a7dd-664c39d89e5c/review/1"],
      ["", "eb8b1851-8245-45c3-9a29-d1fcefaad0b9/review/1"],
      ["", "5d5114f9-8d86-4712-95f3-87dd9d56feef/review/1"]
    ]
    var runs = fixtureRuns()
    for (var i = 0; i < runs.length; i++) {
      compare(Runs.currentPhase(runs[i]), expected[i][0], "currentPhase " + runs[i].id)
      compare(at(Runs.defaultAttempt(runs[i])), expected[i][1], "defaultAttempt " + runs[i].id)
    }
  }

  function test_fixture_card_run_state_and_runs_touching() {
    var runs = fixtureRuns()
    var open = Runs.cardRunState(runs, "299ec9c0-b935-4c44-a7a0-982a104cbfe5")
    compare(open.state, "running")
    compare(open.runId, "20261005T021400Z-837c4431")
    compare(open.dimmed, false)
    compare(open.phase, "explore")
    compare(open.attempt, 1)
    var escalated = Runs.cardRunState(runs, "eb8b1851-8245-45c3-9a29-d1fcefaad0b9")
    compare(escalated.state, "escalated")
    compare(escalated.runId, "20261005T032543Z-bcc4e411")
    compare(escalated.dimmed, true)
    compare(escalated.phase, "review")
    compare(escalated.attempt, 1)

    var touchingOpen = Runs.runsTouching(runs, "299ec9c0-b935-4c44-a7a0-982a104cbfe5")
    compare(touchingOpen.length, 1)
    verify(touchingOpen[0] === runs[0], "the started run")
    var touchingReal = Runs.runsTouching(runs, "5d5114f9-8d86-4712-95f3-87dd9d56feef")
    compare(touchingReal.length, 1)
    verify(touchingReal[0] === runs[3], "the done-integrate run")
    var touchingStory = Runs.runsTouching(runs, "b429248c-c69e-4df5-8f7d-52776253ea14")
    compare(touchingStory.length, 1, "through its real story only")
    verify(touchingStory[0] === runs[3], "the done-integrate run, through its real story")
  }

  function test_fixture_run_tree_grouping() {
    var done = amRun("status-done.json")
    var t = Runs.runTree(Runs.normalizeRun(done))
    var sizes = [2, 3, 1, 4]
    compare(t.stories.length, 4)
    compare(JSON.stringify(t.synthetic), "[]")
    for (var i = 0; i < t.stories.length; i++) {
      var am = done.status.stories[i]
      compare(t.stories[i].card_id, am.card_id, "story " + i)
      compare(t.stories[i].other, false, "story " + i + " is not Other")
      compare(t.stories[i].subtasks.length, sizes[i], "story " + i + " size")
      for (var j = 0; j < t.stories[i].subtasks.length; j++)
        compare(t.stories[i].subtasks[j].card_id, am.subtasks[j].card_id, "story " + i + " subtask " + j)
    }

    var it = Runs.runTree(Runs.normalizeRun(amRun("status-done-integrate.json")))
    compare(it.stories.length, 2)
    compare(it.stories[0].subtasks.length, 1)
    compare(it.stories[1].subtasks.length, 1)
    compare(JSON.stringify(it.synthetic), JSON.stringify([{ id: "integrate", label: "Integrate", status: "done" }]))
    for (var k = 0; k < it.stories.length; k++) compare(it.stories[k].other, false, "no Other group " + k)
  }
```

- [ ] **Step 5: Run the domain tests to see them fail**

Run: `bash tests/run.sh domain/tst_runs`
Expected: exit 1, with `FAIL!  : qmltestrunner::DomainRuns::…` lines for `test_normalize_fixture_counts`, `test_normalize_stories_are_id_lists`, `test_normalize_subtasks_flatten_with_story_id`, `test_normalize_rows_renamed`, `test_normalize_integrate_story_kept_resolver_dropped`, `test_normalize_base_rows_kept`, `test_normalize_copies_never_am_objects`, `test_normalize_own_proto_key_never_sets_prototype`, `test_normalize_tree_garbage`, `test_fixture_current_phase_and_default_attempt`, `test_fixture_card_run_state_and_runs_touching` and `test_fixture_run_tree_grouping` (today's code leaves `tree.subtasks` empty and passes am's rows and stories through, so some of these also print a `TypeError`). `test_normalize_scalars_from_fixture` passes: the scalars were already right. If `F.load` throws `amFixtures: cannot load …`, the import path in Step 1 is wrong — fix it before going on.

- [ ] **Step 6: Move the RunStore attempt-logs tests onto the started capture**

In `tests/core/stores/tst_run_store.qml`:

(a) After line 8 (`import "../../../core/domain/runs.js" as Runs`) add:

```qml
import "../../helpers/amFixtures.js" as F
```

(b) After line 16 (`  property string logsCmd: "python3|/plugin/core/backend/runs/runs-logs.py|"`) add:

```qml
  // The started capture's open subtask (explore attempt 1 is started) and a
  // done subtask of it (spec attempt 1 is ok).
  readonly property string openCard: "299ec9c0-b935-4c44-a7a0-982a104cbfe5"
  readonly property string doneCard: "5eb7ec0c-9bb1-41cd-a0ca-506b4ab4f4ff"
```

(c) Replace the comment and body of `treeEntry` (today lines 913-921):

```qml
  // A snapshot entry whose run has story s1 with subtask t1: spec is done,
  // implement is started and on its second attempt, whose status is `status`.
  function treeEntry(id, status) {
    var e = entry(id, "started", true)
    e.status.stories = [{ card_id: "s1", subtasks: ["t1"] }]
    e.status.subtasks = [{ card_id: "t1", phases: [
      { name: "spec", status: "done", attempts: [{ n: 1, status: "done" }] },
      { name: "implement", status: "started", attempts: [{ n: 1, status: "failed" }, { n: 2, status: status }] }] }]
    return e
  }
```

with:

```qml
  // A snapshot entry of the started capture: runs.json's first `am runs` row
  // whose `status` is status-started.json's `am status` data. Its open attempt
  // is openCard explore 1 and doneCard spec 1 is an earlier, ok attempt. The
  // run id and repo dir are the test's; so is the open attempt's status, in
  // am's attempt vocabulary (started, ok).
  function treeEntry(id, status) {
    var e = F.load("runs.json").data.runs[0]
    e.id = id
    e.repo_dir = tc.rootA
    e.status = F.load("status-started.json").data
    e.status.run.id = id
    e.status.stories[1].subtasks[1].phases[1].attempts[0].status = status
    return e
  }
```

(d) In `test_selecting_a_run_fetches_its_default_attempt`, replace:

```qml
    compare(argv(proc), tc.logsCmd + "r1|t1|implement|2")
    compare(proc.launchGuard, "/home/u/my proj", "guarded by the project")
    compare(store.selectedAttempt.card_id, "t1")
    compare(store.selectedAttempt.phase, "implement")
    compare(store.selectedAttempt.attempt, 2)
```

with:

```qml
    compare(argv(proc), tc.logsCmd + "r1|" + tc.openCard + "|explore|1")
    compare(proc.launchGuard, "/home/u/my proj", "guarded by the project")
    compare(store.selectedAttempt.card_id, tc.openCard)
    compare(store.selectedAttempt.phase, "explore")
    compare(store.selectedAttempt.attempt, 1)
```

(e) In `test_select_attempt_and_refresh_launch_the_exact_argv`, replace:

```qml
    store.selectAttempt("t1", "spec", 1)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|t1|spec|1")
    compare(store.logsStatus, "done")
```

with:

```qml
    store.selectAttempt(tc.doneCard, "spec", 1)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|" + tc.doneCard + "|spec|1")
    compare(store.logsStatus, "ok")
```

and, at the end of the same test, replace:

```qml
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|t1|spec|1")
  }
```

with:

```qml
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|" + tc.doneCard + "|spec|1")
  }
```

(f) In `test_no_logs_launch_without_project_run_or_selection`, replace `bare.selectAttempt("t1", "spec", 1)` with `bare.selectAttempt(tc.doneCard, "spec", 1)`, replace the next `store.selectAttempt("t1", "spec", 1)` (after the first `reply`) with `store.selectAttempt(tc.doneCard, "spec", 1)`, and replace the four invalid-argument calls:

```qml
    store.selectAttempt("t1", "spec", 0)
    store.selectAttempt("t1", "", 1)
    store.selectAttempt("", "spec", 1)
    store.selectAttempt("t1", "spec", "1")
```

with:

```qml
    store.selectAttempt(tc.doneCard, "spec", 0)
    store.selectAttempt(tc.doneCard, "", 1)
    store.selectAttempt("", "spec", 1)
    store.selectAttempt(tc.doneCard, "spec", "1")
```

(`entry("r2", "started", true)` in this test stays: it is the run with no attempt.)

(g) In `test_only_the_latest_logs_fetch_is_applied`, replace `store.selectAttempt("t1", "spec", 1)` with `store.selectAttempt(tc.doneCard, "spec", 1)` and `reply(first, logsReply("implement text\n"), 0)` with `reply(first, logsReply("explore text\n"), 0)`.

(h) In `test_selecting_another_attempt_clears_the_old_text_but_refresh_keeps_it`, replace `store.selectAttempt("t1", "spec", 1)` with `store.selectAttempt(tc.doneCard, "spec", 1)`.

(i) In `test_changing_the_selected_run_resets_to_its_default_attempt`, replace:

```qml
    var r2 = treeEntry("r2", "started")
    r2.status.stories = [{ card_id: "s9", subtasks: ["t9"] }]
    r2.status.subtasks = [{ card_id: "t9", phases: [{ name: "review", status: "started", attempts: [{ n: 3, status: "started" }] }] }]
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started"), r2]), 0)
    store.selectedRunId = "r1"
    reply(store.logsRunner.current, logsReply("r1 text\n"), 0)
    store.selectAttempt("t1", "spec", 1)
    store.selectedRunId = "r2"
    compare(store.selectedAttempt.card_id, "t9")
    compare(store.selectedAttempt.phase, "review")
    compare(store.selectedAttempt.attempt, 3)
    compare(store.logsText, "")
    compare(store.logsFetchedMs, 0)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r2|t9|review|3")
```

with:

```qml
    // r2 is the done capture: runs.json's second row with status-done.json's
    // `am status`, under the test's run id and repo dir.
    var r2 = F.load("runs.json").data.runs[1]
    r2.id = "r2"
    r2.repo_dir = tc.rootA
    r2.status = F.load("status-done.json").data
    r2.status.run.id = "r2"
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started"), r2]), 0)
    store.selectedRunId = "r1"
    reply(store.logsRunner.current, logsReply("r1 text\n"), 0)
    store.selectAttempt(tc.doneCard, "spec", 1)
    store.selectedRunId = "r2"
    compare(store.selectedAttempt.card_id, "22153f5f-9632-4b5f-a7dd-664c39d89e5c")
    compare(store.selectedAttempt.phase, "review")
    compare(store.selectedAttempt.attempt, 1)
    compare(store.logsText, "")
    compare(store.logsFetchedMs, 0)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r2|22153f5f-9632-4b5f-a7dd-664c39d89e5c|review|1")
```

(j) In `test_a_snapshot_that_changes_the_attempt_status_fetches_once`, replace:

```qml
    snapshot(store, [treeEntry("r1", "done")])
    compare(store.logsRunner.seq, seq + 1, "started -> done fetches the logs again")
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|t1|implement|2")
    compare(store.logsStatus, "done")
    compare(store.logsText, "a", "the text stays until the new reply")
    snapshot(store, [treeEntry("r1", "done")])
```

with:

```qml
    snapshot(store, [treeEntry("r1", "ok")])
    compare(store.logsRunner.seq, seq + 1, "started -> ok fetches the logs again")
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|" + tc.openCard + "|explore|1")
    compare(store.logsStatus, "ok")
    compare(store.logsText, "a", "the text stays until the new reply")
    snapshot(store, [treeEntry("r1", "ok")])
```

(k) In `test_a_snapshot_without_a_selected_run_fetches_no_logs`, replace `snapshot(store, [treeEntry("r1", "done")])` with `snapshot(store, [treeEntry("r1", "ok")])`.

(l) In `test_a_run_opened_before_its_first_attempt_picks_one_when_it_appears`, replace:

```qml
    var bare = treeEntry("r1", "started")
    bare.status.subtasks[0].phases = []
```

with:

```qml
    // synthetic: the run before any attempt exists; shape kept
    var bare = treeEntry("r1", "started")
    var stories = bare.status.stories
    for (var i = 0; i < stories.length; i++) {
      for (var j = 0; j < stories[i].subtasks.length; j++) stories[i].subtasks[j].phases = []
    }
    bare.status.rows = []
```

and at the end of the same test replace:

```qml
    compare(store.selectedAttempt.attempt, 2)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|t1|implement|2")
```

with:

```qml
    compare(store.selectedAttempt.attempt, 1)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|" + tc.openCard + "|explore|1")
```

After this step, `grep -n '"t1"\|implement|2\|t9' tests/core/stores/tst_run_store.qml` must show no line inside the attempt-logs section (L911-1190); hits from L1240 on (`requested_at: "t1"`, dispatch cards) are other tests and stay.

- [ ] **Step 7: Run the store tests to see them fail**

Run: `bash tests/run.sh stores/tst_run_store`
Expected: exit 1, with `FAIL!` lines in the attempt-logs tests, e.g. `test_selecting_a_run_fetches_its_default_attempt` (today's `normalizeRun` leaves `tree.subtasks` empty, so `defaultAttempt` is null and nothing is selected) and `test_select_attempt_and_refresh_launch_the_exact_argv` (`logsStatus` is `""`, not `ok`). No `amFixtures: cannot load` message.

- [ ] **Step 8: Rewrite `normalizeRun` and its header comment**

In `core/domain/runs.js`, replace lines 4-70 (from `// Run domain model: one \`am\` orchestrator run, normalised from the CLI's` through the closing `}` of `normalizeRun`) with:

```js
// Run domain model: one `am` orchestrator run, normalised from the CLI's
// output.
//
// Input of normalizeRun:
//   raw = {
//     row:    one `am runs` entry without its `status`:
//             { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at,
//               milestone_id, card_id, lease, progress }
//     status: `am status` data, may be absent:
//             { run: { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at },
//               stories: [{ card_id, title, level, status, tip_branch,
//                           subtasks: [{ card_id, branch, base_branch, status, worktree_path,
//                                        phases: [{ name, kind, status, started_at, ended_at, detail,
//                                                   attempts: [{ n, status, ... }] }] }] }],
//               rows: [{ story, subtask, phase, attempt, state }],
//               control: { lease: { pid, host, heartbeat_at, accepting, live, ... },
//                          requests: [{ command, requested_at, handled_at }], claims },
//               integrity }
//   }
// Output scalars: id, repo_dir, started_at, base_branch, branch_prefix and
// workflow are the row's, else the am status run's; status and milestone_id are
// the am status run's, else the row's. `lease` keeps pid, host, heartbeat_at,
// accepting and live. `requests` are am's control requests in the order made;
// handled_at "" means the run has not acted on it yet.
// tree.stories: every object story in am's order, the synthetic `integrate` and
// `bases` included; its `subtasks` is the card_id strings of its subtasks.
// tree.subtasks: the subtasks of every other story, flattened in am's order,
// each with `story_id`, its story's card_id.
// rows: { story_id, card_id, phase, attempt, status } from am's story, subtask,
// phase, attempt and state, in am's order. A row under `integrate` or `bases`
// whose subtask is a real card id (an Integrate resolver) is dropped.
//
// The status always comes from `am`, never from a brd card. The output holds
// copies, never am's objects. Never throws: anything missing or malformed
// becomes its default, and a missing lease means the run is not live.
function normalizeRun(raw) {
  function isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }
  function objectOr(v) { return isObject(v) ? v : {} }
  function arrayOr(v) { return Array.isArray(v) ? v : [] }
  function text(v) { return v === undefined || v === null ? "" : String(v) }
  function firstText(a, b) { var s = text(a); return s !== "" ? s : text(b) }
  function asGiven(v) { return v === undefined || v === null ? "" : v }
  function stringOr(v) { return typeof v === "string" ? v : "" }
  function isSyntheticStory(id) { return id === "integrate" || id === "bases" }
  // A JSON-like deep copy of arrays and objects. An own `__proto__` key is
  // dropped, so every copied object's prototype is Object.prototype.
  function copyOf(v) {
    if (Array.isArray(v)) {
      var list = []
      for (var a = 0; a < v.length; a++) list.push(copyOf(v[a]))
      return list
    }
    if (!isObject(v)) return v
    var out = {}
    var keys = Object.keys(v)
    for (var k = 0; k < keys.length; k++) {
      if (keys[k] !== "__proto__") out[keys[k]] = copyOf(v[keys[k]])
    }
    return out
  }

  var r = objectOr(raw)
  var row = objectOr(r.row)
  var st = objectOr(r.status)
  var run = objectOr(st.run)
  var control = objectOr(st.control)

  var lease = null
  if (isObject(control.lease)) {
    var l = control.lease
    lease = {
      pid: asGiven(l.pid),
      host: asGiven(l.host),
      heartbeat_at: asGiven(l.heartbeat_at),
      accepting: l.accepting === true,
      live: l.live === true
    }
  }

  var requests = []
  var rawRequests = arrayOr(control.requests)
  for (var i = 0; i < rawRequests.length; i++) {
    var q = rawRequests[i]
    if (!isObject(q)) continue
    requests.push({ command: text(q.command), requested_at: text(q.requested_at), handled_at: text(q.handled_at) })
  }

  var stories = [], subtasks = []
  var amStories = arrayOr(st.stories)
  for (var s = 0; s < amStories.length; s++) {
    var story = amStories[s]
    if (!isObject(story)) continue
    var real = !isSyntheticStory(story.card_id)
    var ids = []
    var amSubtasks = arrayOr(story.subtasks)
    for (var t = 0; t < amSubtasks.length; t++) {
      var subtask = amSubtasks[t]
      if (!isObject(subtask)) continue
      if (typeof subtask.card_id === "string") ids.push(subtask.card_id)
      if (!real) continue
      var copied = copyOf(subtask)
      copied.story_id = stringOr(story.card_id)
      subtasks.push(copied)
    }
    var storyCopy = copyOf(story)
    storyCopy.subtasks = ids
    stories.push(storyCopy)
  }

  var rows = []
  var amRows = arrayOr(st.rows)
  for (var w = 0; w < amRows.length; w++) {
    var amRow = amRows[w]
    if (!isObject(amRow)) continue
    if (isSyntheticStory(amRow.story) && _isCardId(amRow.subtask)) continue
    rows.push({
      story_id: stringOr(amRow.story),
      card_id: stringOr(amRow.subtask),
      phase: stringOr(amRow.phase),
      attempt: typeof amRow.attempt === "number" && isFinite(amRow.attempt) ? amRow.attempt : null,
      status: stringOr(amRow.state)
    })
  }

  return {
    id: firstText(row.id, run.id),
    repo_dir: firstText(row.repo_dir, run.repo_dir),
    milestone_id: firstText(run.milestone_id, row.milestone_id),
    status: firstText(run.status, row.status),
    started_at: firstText(row.started_at, run.started_at),
    base_branch: firstText(row.base_branch, run.base_branch),
    branch_prefix: firstText(row.branch_prefix, run.branch_prefix),
    workflow: firstText(row.workflow, run.workflow),
    lease: lease,
    requests: requests,
    rows: rows,
    tree: { stories: stories, subtasks: subtasks }
  }
}
```

Lines 1-2 (`.pragma library`, `.import "board.js" as Board`) stay exactly as they are. `_isCardId` is the file-level function declared further down (hoisted). The scalar, lease and requests code is unchanged.

- [ ] **Step 9: Run both test files to see them pass**

Run: `bash tests/run.sh domain/tst_runs`
Expected: exit 0; the `DomainRuns` line reads `Totals: N passed, 0 failed, …` with no `FAIL` and no `TypeError` line.

Run: `bash tests/run.sh stores/tst_run_store`
Expected: exit 0; `StoresRunStore` `Totals: … 0 failed`.

If `test_fixture_current_phase_and_default_attempt` fails on done-integrate with `b429248c-…/resolve/1`, the resolver-row drop in Step 8 is not applied. If a `test_normalize_own_proto_key_never_sets_prototype` prototype check fails, `copyOf` is assigning the `__proto__` key.

- [ ] **Step 10: Run the whole suite**

Run: `bash tests/run.sh`
Expected: exit 0 — pytest green (including `tests/architecture` and `tests/contract`), every `tst_*.qml` `0 failed`, no `TypeError` / `ReferenceError` line.

- [ ] **Step 11: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): normalizeRun reads am's nested tree and renamed rows

tree.stories keeps every am story with its subtasks as an id list,
tree.subtasks flattens the real stories' subtasks with story_id, and rows
are renamed to {story_id, card_id, phase, attempt, status} without the
Integrate resolver rows. All as copies. The domain and RunStore
attempt-logs tests are built from tests/fixtures/am/.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Re-point the remaining `fullRaw()` users onto the started capture

**Files:**
- Modify: `tests/core/domain/tst_runs.qml` (header L6-11; `fullRaw` L15-30; the tests listed below; `synthetic:` labels on small inline inputs)

**Interfaces:**
- Consumes: `amRun(name)` from Task 1 (fresh `{ row, status }` for a capture; the row has no `status` key). `Runs.normalizeRun` as rewritten in Task 1.
- Produces: no `fullRaw` anywhere in the file. No production code changes.

These tests already pass on Task 1's code; each step swaps the input for the capture and must leave them passing. The run after each edit is the check that the meaning is kept.

- [ ] **Step 1: Replace the file header and delete `fullRaw`**

Replace lines 6-11:

```qml
// Input shape for Runs.normalizeRun (provisional until the runs-snapshot helper exists):
//   raw = {
//     row:    { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at }  // one `am runs` row
//     status: { run: {...}, rows: [...], stories: [...], subtasks: [...],
//               control: { lease: { pid, host, heartbeat_at, accepting, live } }, ... }  // `am status` data, may be absent
//   }
```

with:

```qml
// normalizeRun's input is built from tests/fixtures/am/ via amRun.
```

Then delete the whole `function fullRaw() { … }` (from `  function fullRaw() {` through its closing `  }` and the blank line after it). Every remaining caller is re-pointed in Steps 2-5 below; do all of them before running.

- [ ] **Step 2: Re-point the status, lease and state tests**

Replace `test_normalize_status_prefers_am_status` with:

```qml
  function test_normalize_status_prefers_am_status() {
    // synthetic: the row's and am status's run statuses edited to disagree
    var raw = amRun("status-started.json")
    raw.row.status = "stopped"
    raw.status.run.status = "done"
    compare(Runs.normalizeRun(raw).status, "done")

    // synthetic: a bare am runs row
    compare(Runs.normalizeRun({ row: { id: "r1", status: "stopped" } }).status, "stopped")

    // synthetic: am status without its run
    var noRun = amRun("status-started.json")
    noRun.row.status = "escalated"
    delete noRun.status.run
    compare(Runs.normalizeRun(noRun).status, "escalated")

    // synthetic: an empty am status run status. It is not fresher detail: fall back to the row.
    var blank = amRun("status-started.json")
    blank.row.status = "stopped"
    blank.status.run.status = ""
    compare(Runs.normalizeRun(blank).status, "stopped")
  }
```

Replace `test_normalize_missing_lease` with:

```qml
  function test_normalize_missing_lease() {
    // synthetic: am status without control
    var noControl = amRun("status-started.json")
    delete noControl.status.control
    compare(Runs.normalizeRun(noControl).lease, null, "no control")

    // synthetic: the capture's control replaced by each malformed shape
    var cases = [
      { label: "empty control", control: {} },
      { label: "null control", control: null },
      { label: "null lease", control: { lease: null } },
      { label: "string lease", control: { lease: "yes" } },
      { label: "array lease", control: { lease: [] } }
    ]
    for (var i = 0; i < cases.length; i++) {
      var raw = amRun("status-started.json")
      raw.status.control = cases[i].control
      compare(Runs.normalizeRun(raw).lease, null, cases[i].label)
    }

    // synthetic: a bare am runs row
    compare(Runs.normalizeRun({ row: { id: "r1", status: "started" } }).lease, null, "no status at all")
  }
```

Replace `test_normalize_lease_live_strict` with:

```qml
  function test_normalize_lease_live_strict() {
    // synthetic: the capture's lease replaced by empty, null, string and numeric values
    var empty = amRun("status-started.json")
    empty.status.control.lease = {}
    var e = Runs.normalizeRun(empty).lease
    compare(e.live, false)
    compare(e.accepting, false)
    compare(e.pid, "")
    compare(e.host, "")
    compare(e.heartbeat_at, "")

    var nulls = amRun("status-started.json")
    nulls.status.control.lease = { pid: null, host: null, heartbeat_at: null, live: null, accepting: null }
    var n = Runs.normalizeRun(nulls).lease
    compare(n.pid, "", "null pid")
    compare(n.host, "", "null host")
    compare(n.heartbeat_at, "", "null heartbeat_at")
    compare(n.live, false, "null live")
    compare(n.accepting, false, "null accepting")

    var stringy = amRun("status-started.json")
    stringy.status.control.lease = { live: "true", accepting: "true" }
    compare(Runs.normalizeRun(stringy).lease.live, false)
    compare(Runs.normalizeRun(stringy).lease.accepting, false)

    var numeric = amRun("status-started.json")
    numeric.status.control.lease = { live: 1, accepting: 1 }
    compare(Runs.normalizeRun(numeric).lease.live, false)
    compare(Runs.normalizeRun(numeric).lease.accepting, false)
  }
```

Replace `test_state_running` with:

```qml
  function test_state_running() {
    compare(Runs.runState({ status: "started", lease: { live: true } }), "running")
    compare(Runs.runState(Runs.normalizeRun(amRun("status-started.json"))), "running")
  }
```

In `test_state_dead_not_live`, replace:

```qml
    var raw = fullRaw()
    raw.status.control.lease.live = false
    compare(Runs.runState(Runs.normalizeRun(raw)), "dead")

    // A sloppy "true" string is not liveness.
    var stringy = fullRaw()
    stringy.status.control.lease.live = "true"
```

with:

```qml
    // synthetic: the capture's lease edited to not live
    var raw = amRun("status-started.json")
    raw.status.control.lease.live = false
    compare(Runs.runState(Runs.normalizeRun(raw)), "dead")

    // synthetic: the capture's lease live as a string. A sloppy "true" string is not liveness.
    var stringy = amRun("status-started.json")
    stringy.status.control.lease.live = "true"
```

In `test_state_dead_missing_lease`, replace:

```qml
    compare(Runs.runState(Runs.normalizeRun({ row: { id: "r1", status: "started" } })), "dead")

    var noLease = fullRaw()
    delete noLease.status.control
```

with:

```qml
    // synthetic: a bare am runs row
    compare(Runs.runState(Runs.normalizeRun({ row: { id: "r1", status: "started" } })), "dead")

    // synthetic: am status without control
    var noLease = amRun("status-started.json")
    delete noLease.status.control
```

- [ ] **Step 3: Re-point `started_at`, branch fields and workflow**

In `test_normalize_keeps_started_at`, replace:

```qml
    compare(Runs.normalizeRun(fullRaw()).started_at, "2026-10-03T10:00:00Z", "from the am runs row")
    compare(Runs.normalizeRun({ status: { run: { started_at: "2026-10-01T00:00:00Z" } } }).started_at,
```

with:

```qml
    compare(Runs.normalizeRun(amRun("status-started.json")).started_at, "2026-10-05 02:14:00.590972+00:00",
            "from the am runs row")
    // synthetic: bare am status runs and rows, one field each
    compare(Runs.normalizeRun({ status: { run: { started_at: "2026-10-01T00:00:00Z" } } }).started_at,
```

In `test_normalize_branch_fields`, replace:

```qml
    var r = Runs.normalizeRun(fullRaw())
    compare(r.base_branch, "main")
    compare(r.branch_prefix, "mon/")
    var fromRun = Runs.normalizeRun({ status: { run: { base_branch: "master", branch_prefix: "m3" } } })
```

with:

```qml
    var r = Runs.normalizeRun(amRun("status-started.json"))
    compare(r.base_branch, "main")
    compare(r.branch_prefix, "dsp")
    // synthetic: bare am status runs and rows, branch fields only
    var fromRun = Runs.normalizeRun({ status: { run: { base_branch: "master", branch_prefix: "m3" } } })
```

Replace `test_normalize_workflow` with:

```qml
  function test_normalize_workflow() {
    compare(Runs.normalizeRun(amRun("status-started.json")).workflow, "milestone", "from the am runs row")
    // synthetic: the capture's row and run workflows edited to each combination
    var raw = amRun("status-started.json")
    delete raw.row.workflow
    raw.status.run.workflow = "task"
    compare(Runs.normalizeRun(raw).workflow, "task", "falls back to the am status run")
    raw.row.workflow = "milestone"
    compare(Runs.normalizeRun(raw).workflow, "milestone", "the row wins")
    raw.row.workflow = ""
    compare(Runs.normalizeRun(raw).workflow, "task", "an empty row value falls back")
    delete raw.row.workflow
    delete raw.status.run.workflow
    compare(Runs.normalizeRun(raw).workflow, "", "neither gives empty")
    // synthetic: null workflows, and garbage
    compare(Runs.normalizeRun({ row: { workflow: null }, status: { run: { workflow: null } } }).workflow, "", "nulls")
    compare(Runs.normalizeRun(undefined).workflow, "", "garbage")
  }
```

- [ ] **Step 4: Re-point the requests tests**

Replace `test_normalize_requests` with:

```qml
  function test_normalize_requests() {
    // synthetic: three requests, which no capture contains
    var raw = amRun("status-started.json")
    raw.status.control.requests = [
      { command: "pause", requested_at: "2026-10-03T10:00:00Z", handled_at: "2026-10-03T10:00:05Z" },
      { command: "resume", requested_at: "2026-10-03T11:00:00Z", handled_at: null },
      { command: "cancel", requested_at: "2026-10-03T12:00:00Z" }
    ]
    var r = Runs.normalizeRun(raw)
    compare(Array.isArray(r.requests), true)
    compare(r.requests.length, 3)
    compare(Object.keys(r.requests[0]).sort().join(","), "command,handled_at,requested_at")
    compare(r.requests[0].command, "pause")
    compare(r.requests[0].requested_at, "2026-10-03T10:00:00Z")
    compare(r.requests[0].handled_at, "2026-10-03T10:00:05Z")
    compare(r.requests[1].command, "resume", "order is kept")
    compare(r.requests[1].handled_at, "", "null means not handled")
    compare(r.requests[2].command, "cancel")
    compare(r.requests[2].handled_at, "", "missing means not handled")
    r.requests[0].command = "x"
    compare(raw.status.control.requests[0].command, "pause", "the elements are fresh objects")
    compare(Runs.normalizeRun(amRun("status-started.json")).requests.length, 0, "the capture's requests are []")
  }
```

Replace `test_normalize_requests_garbage` (keep the `// Review Focus 4.` comment above it) with:

```qml
  function test_normalize_requests_garbage() {
    // synthetic: garbage request elements in place of the capture's []
    var raw = amRun("status-started.json")
    raw.status.control.requests = [null, "pause", 7, ["pause"], true,
                                   { command: 5, requested_at: true, handled_at: { a: 1 } }, {}]
    var r = Runs.normalizeRun(raw)
    compare(r.requests.length, 2, "non-object elements are skipped")
    compare(r.requests[0].command, "5")
    compare(r.requests[0].requested_at, "true")
    compare(r.requests[0].handled_at, "[object Object]")
    compare(r.requests[1].command, "")
    compare(r.requests[1].requested_at, "")
    compare(r.requests[1].handled_at, "")

    // synthetic: am status without control
    var noControl = amRun("status-started.json")
    delete noControl.status.control
    compare(Runs.normalizeRun(noControl).requests.length, 0, "no control")
    // synthetic: requests that are not a list
    var values = ["x", { a: 1 }, null, 5]
    for (var i = 0; i < values.length; i++) {
      var bad = amRun("status-started.json")
      bad.status.control.requests = values[i]
      var out = Runs.normalizeRun(bad)
      compare(Array.isArray(out.requests), true, "requests " + i)
      compare(out.requests.length, 0, "requests " + i)
    }
    // synthetic: control that is not an object
    compare(Runs.normalizeRun({ status: { control: "y" } }).requests.length, 0, "control not an object")
  }
```

- [ ] **Step 5: Label the remaining small inline inputs**

Add exactly these comment lines (no code change):

- In `test_normalize_ids_fallback_and_coercion`, as its first line: `    // synthetic: bare am runs rows and am status runs, one or two fields each`
- In `test_normalize_garbage`, as its first line: `    // synthetic: garbage in place of a run`
- In `test_card_garbage`, on the line directly above `    var withBlank = [good, mkRun("blank", "started", true, { milestone_id: "" }),`: `    // synthetic: a bare am runs row among hand-built normalized runs`
- In `test_controls_unknown_and_garbage`, on the line directly above `    var runs = [ctlRun("", true, true), …`: `    // synthetic: normalizeRun(undefined) stands for garbage am output`
- In `test_controls_from_normalized`, on the line directly above `    function raw(lease) {`: `    // synthetic: am status with only a run and a lease`
- In `test_new_alerts_garbage`, on the line directly above `    compare(Runs.newAlerts([], [Runs.normalizeRun(undefined)]).length, 0, "normalised garbage")`: `    // synthetic: garbage, and a bare am runs row with an escalated am status run`

- [ ] **Step 6: Check nothing still uses `fullRaw` and no hand-written am payload is unlabelled**

Run: `grep -n "fullRaw\|provisional" tests/core/domain/tst_runs.qml core/domain/runs.js`
Expected: no output.

Run: `grep -n "normalizeRun(" tests/core/domain/tst_runs.qml`
Expected: every hit either takes `amRun(...)` / a variable built from `amRun(...)`, or sits under a `// synthetic:` comment in the same test (check by eye against Steps 2-5 and Task 1).

- [ ] **Step 7: Run the domain tests**

Run: `bash tests/run.sh domain/tst_runs`
Expected: exit 0; `DomainRuns` `Totals: … 0 failed`, no `TypeError` / `ReferenceError` (a `ReferenceError: fullRaw is not defined` means Step 1's deletion left a caller).

- [ ] **Step 8: Run the whole suite**

Run: `bash tests/run.sh`
Expected: exit 0 — pytest green, every `tst_*.qml` `0 failed`.

- [ ] **Step 9: Commit**

```bash
git add tests/core/domain/tst_runs.qml
git commit -m "test(runs): build normalizeRun's remaining inputs from the am captures

fullRaw's guessed shape is gone: the status, lease, state, started_at,
branch, workflow and requests tests start from status-started.json, and
every hand-written input is labelled synthetic:.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
<!-- task-pipeline: validated -->
