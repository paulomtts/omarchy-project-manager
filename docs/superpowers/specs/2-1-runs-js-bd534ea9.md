# 2.1 runs.js: normalizeRun reads am's nested tree and rows — design

Card `bd534ea9`, a subtask of story `21f9cd5a` ("Normalize real am status").
Parent spec: `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
(below: **parent**). Work breakdown item 2 (parent L324-326): this subtask is
"`normalizeRun` (with its red-then-green fixture tests in the same subtask)"
only. `rollup`, `runProgress`, `runTree`'s open attempt, `escalationReason` and
`glyphStateOf` are the story's later subtasks (2.2-2.4).

## Goal

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

## Inherited constraints

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

## Fixture facts this design relies on (checked 2026-10-05 against the committed files)

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

## Behavior

### Input

`raw = {row, status}`.

- `row` is one `am runs` entry without its `status` object: `id, workflow,
  repo_dir, base_branch, branch_prefix, status, started_at, milestone_id,
  card_id, lease, progress`.
- `status` is `am status` data: `{run, stories, rows, control, integrity}`.

Either part may be absent or garbage.

### Output: unchanged keys

The 12 top-level keys stay exactly the same: `base_branch, branch_prefix, id,
lease, milestone_id, repo_dir, requests, rows, started_at, status, tree,
workflow`. The rules for `id`, `repo_dir`, `milestone_id`, `status`,
`started_at`, `base_branch`, `branch_prefix`, `workflow`, `lease` and
`requests` do not change (row first or am status first, exactly as today).
`lease` keeps only its five keys.

### Output: `tree.stories`

There is one entry per **object** element of `status.stories`, in am's order,
synthetic stories (`integrate`, `bases`) included.

- Each entry is a deep copy of the am story's own keys.
- `subtasks` is replaced by an array of the `card_id` of every object element
  of the am story's `subtasks`, in order. Only string ids are kept.
- When am's `subtasks` is missing or is not an array, `subtasks` is `[]`.
- Non-object elements (null, strings, numbers, arrays) of `status.stories` are
  skipped.
- When `status.stories` is not an array, `tree.stories` is `[]`.

### Output: `tree.subtasks`

For each object story whose `card_id` is not `integrate` or `bases`, in story
order, take every object element of its `subtasks` array in order. Output a
deep copy of it with one added key: `story_id`, which is the story's `card_id`
when that is a string, else `""`.

- The phases and attempts inside are copies too, with every key am gave kept
  as given.
- Subtasks of `integrate` and `bases` are never included.
- Non-object subtask elements are skipped.
- A story with no array `subtasks` adds nothing.

### Output: `rows`

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

### Copies

No object or array in the output is one of am's. Changing any output story,
subtask, phase, attempt or row leaves `raw` unchanged, and changing `raw` after
the call leaves the output unchanged.

A key named `__proto__` that am's JSON carries as an own key never changes a
copy's prototype. The copy keeps it as an own key or drops it. Every copied
object's prototype stays `Object.prototype`.

### Never throws

Garbage gives the defaults, as today. `normalizeRun(undefined | null | "x" | 5 |
{} | [])` and every malformed part still produce the 12 keys, with `rows`,
`tree.stories` and `tree.subtasks` as empty arrays.

### Header comment (`core/domain/runs.js` lines 3-20)

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

### Downstream (read only here)

`defaultAttempt`, `currentPhase`, `cardRunState`, `runsTouching`, `runTree` and
`attemptStatus` are **not edited**. Over the new output they give the values in
the facts table and in parent L222-227. `_storyHas` already accepts id strings.

`rollup`, `runProgress`, `runTree`'s per-node open attempt and
`escalationReason` still have their old logic. This subtask does not assert
them on real data.

## Tests

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

### `tests/core/domain/tst_runs.qml`

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

#### Re-pointing `fullRaw` and the other existing tests

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

### `tests/core/stores/tst_run_store.qml`

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

### Unchanged and must stay green

`tests/ui/*` (normalized runs built by hand; parent L262-265), the backend
pytest suites, `tests/contract`, `tests/architecture`, and every other test in
both files.

## Out of scope

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

## For the planner

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
