# 1.3 runs.js: the prefix default from runs, then the milestone-keyed map — design

Card: `aba87499` (subtask of story `5c0430d9` "Story dispatch logic and backend", milestone
`5d48ef7a` "Dispatch at story level"). Blocked by `a2a74eda` (1.2, done: `dispatchPlan` offers a
story, `previewSummary` story variant).

Parent design: `docs/superpowers/specs/2026-10-05-dispatch-story-level-design.md` (below, "the
parent spec"). Previous pin of the function changed here: `docs/superpowers/specs/1-1-runs-js-5eb7ec0c.md`
(S3 `dispatchDefaults`). Everything that pin fixes and this spec does not change (`base`,
`verify`, `parallelism`, `allowNoVerification`, the milestone walk, the stem rule, the five-key
result) stays as pinned.

## Goal

`dispatchDefaults` in `core/domain/runs.js` takes a fourth argument, `runs`, and computes the
default branch prefix from four sources in a fixed order, so a story dispatched from the panel
starts with the prefix its milestone's other stories already use — including a milestone run
started from a terminal. The same default serves the milestone level (and the subtask level,
which resolves to the same milestone).

## Inherited constraints

| constraint | source |
|---|---|
| Prefix default order: (1) `branch_prefix` of the newest run in the Runs snapshot whose `milestone_id` is the card's milestone; (2) the last prefix used for that milestone through the panel, from the per-project run settings keyed by milestone id; (3) S3's prefix history; (4) the milestone's short stem. It is editable. The same default serves the milestone level. | parent spec, Behaviour (story), "Prefix", lines 49-54 |
| `dispatchDefaults` gains the `runs` argument and the prefix order above | parent spec, Architecture, lines 80-81 |
| The milestone-keyed map is `prefixByMilestone`, next to the existing prefix history in the run settings; S3's history stays for the fallback | parent spec, Architecture, lines 85-86 |
| `tst_runs.qml` covers the four-step prefix default | parent spec, Testing, lines 97-98 |
| A story run's row carries the parent milestone's id as `milestone_id` | parent spec, Behaviour (story), "Launch", lines 70-72 |
| `runs.js` is `.pragma library`, pure, never throws, garbage in gives defaults, own-key lookups only, ids compared with `===`, ES5 (`var`, `function`, no `let`/`const`/arrows) | `core/domain/runs.js:863-870` (Dispatch section header), `:163-168` (rollups header) |
| Result keeps exactly the five keys `allowNoVerification, base, parallelism, prefix, verify` | `1-1-runs-js-5eb7ec0c.md`; pinned by `checkDefaults5`, `tests/core/domain/tst_runs.qml:2638-2646` |
| Layering per `docs/architecture.md`; `tests/architecture` stays green (no new component) | card description |
| Comments and docstrings state the contract only, no narrative | card description |
| TDD: tests first; `bash tests/run.sh` green | card description |

## Behaviour

### Signature

`dispatchDefaults(project, card, cardMap, runs)`.

- `runs` is a list of runs as `Runs.normalizeRun` returns them (`RunStore.runs`), each with at
  least `milestone_id`, `branch_prefix`, `started_at` (`core/domain/runs.js:126-135`). Order is
  taken as newest first, the convention of every other function over runs in this file.
- A `runs` that is not an array (missing, `null`, an object, a string, a number) is treated as
  `[]`. Every existing call with three or fewer arguments therefore behaves exactly as before
  whenever the settings carry no `prefixByMilestone` and no `prefixHistory`.
- `settings` is `project.settings` as today (an object, else `{}`).

### The milestone and its key

- `M` = the card's milestone, found exactly as today (`_milestoneOf(card, cardMap)`,
  `core/domain/runs.js:916-933`): the card itself at depth 0, else the parentless ancestor
  reached through `cardMap`'s own keys; `null` for `"board"`, a missing `cardMap` on a story or
  subtask, a broken chain, a cycle, or a non-object card.
- `K` = `M.id` when `M` is non-null and `M.id` is a non-empty string; otherwise there is no key.
  `K` is the **milestone's** id, never the story's or subtask's own id.

### The order

The prefix is the first of these that yields a value. Every value taken is returned trimmed
(leading and trailing whitespace removed).

1. **Newest matching run** (only when `K` exists). Candidates are the entries of `runs` that are
   objects (not `null`, not arrays) with `milestone_id === K` and a `branch_prefix` that is a
   string whose trimmed value is not empty. Among candidates the newest wins by the rule already
   used for card mapping (`_isNewer`, `core/domain/runs.js:206-212`): a later `started_at` wins
   when both carry distinct non-empty strings; otherwise the lower index wins. A run that matches
   the milestone but has a blank or non-string `branch_prefix` is not a candidate: an older
   matching run with a prefix still wins over the map. Run status (running, finished, failed,
   canceled, dead) does not matter.
2. **Milestone-keyed map** (only when `K` exists). `settings.prefixByMilestone` when it is an
   object (not an array, not `null`) that **owns** the key `K` (`hasOwnProperty`, as `_ownCard`
   does), and the value is a string whose trimmed value is not empty. Inherited keys
   (`constructor`, `toString`, `__proto__` when not own) never match. A prototype-less map
   (`Object.create(null)`) works. A missing or malformed map is skipped silently.
3. **Prefix history** (only when `M` is non-null). The first entry of `settings.prefixHistory`
   (most recent first, as `RunStore.dispatchStart` writes it, `core/stores/RunStore.qml:1084-1097`)
   that is a string whose trimmed value is not empty. Non-string and blank entries before it are
   skipped. A non-array history is skipped.
4. **Stem** (only when `M` is non-null). `_stemOf(M.title)`, unchanged
   (`core/domain/runs.js:935-950`); may be `""`.

When `M` is `null`, the prefix is `""` whatever `runs` and settings hold. Rationale: the history
holds prefixes of other milestones; a card whose milestone cannot be identified must not inherit
one. This keeps today's results for `"board"`, broken chains, cycles and stories without a
`cardMap` (`tst_runs.qml:2711-2740`). When `M` exists but has no usable id, steps 1 and 2 are
skipped and steps 3 then 4 apply.

### Invariants

- Pure: `runs`, its entries, `settings`, `settings.prefixByMilestone`, `settings.prefixHistory`
  and `cardMap` are never mutated; each call returns a fresh object.
- Never throws, for any value of any argument.
- Result keys are still exactly the five; only `prefix` changes behaviour. `base`, `verify`,
  `parallelism`, `allowNoVerification` are unaffected by `runs` and by the new settings field.
- The doc comment above `dispatchDefaults` (`core/domain/runs.js:951-957`) states the new
  argument and the four-step order as a contract; no narrative.

## Tests

All in `tests/core/domain/tst_runs.qml`, tier **QML unit** (qmltestrunner via
`bash tests/run.sh tst_runs`). Why this tier: `dispatchDefaults` is a pure `.pragma library`
function with no I/O, and this file is where every other `runs.js` function and the existing
`dispatchDefaults` tests live; no store, backend or UI is involved. Use the existing helpers
`mkCard(id, depth, status, parentId, title)` (`:2457`) and `checkDefaults5` (`:2638`); add a small
`mkRun(milestoneId, prefix, startedAt)` helper returning `{milestone_id, branch_prefix, started_at}`.

Fixture: milestone `m1` "M3 Document runs" (stem `m3`), story `s1` under it, subtask `c1` under
the story, `map = {m1, s1, c1}`; a second milestone `m2`.

1. **`test_dispatchDefaults_prefix_order`** — with a matching run (`"run-p"`), a map entry
   (`{m1: "map-p"}`), a history (`["hist-p"]`) all present, the prefix is `run-p`; drop the run →
   `map-p`; drop the map entry → `hist-p`; drop the history → `m3`. Asserted for the milestone card
   `m1`, the story `s1` and the subtask `c1` (both with `map`).
2. **`test_dispatchDefaults_prefix_runs_newest`** — two `m1` runs: later `started_at` wins in
   either list order; equal `started_at`, or one/both missing or empty, → lower index wins; a
   newer `m1` run with `branch_prefix` `""`, `"  "`, `null`, `5` is skipped and the older `m1` run's
   prefix is used; when the only `m1` run has a blank prefix the map entry is used.
3. **`test_dispatchDefaults_prefix_runs_matching`** — a newer run of `m2` is ignored for `m1`; a
   run whose `milestone_id` is the story's own id `s1` is ignored when dispatching `s1` (key is the
   milestone); a run with non-string `milestone_id` never matches; garbage entries (`null`,
   `"x"`, `[]`, `5`) in `runs` are skipped; `runs` of `undefined`, `null`, `{}`, `"m1"`, `5` behave
   as `[]` (falls to the map).
4. **`test_dispatchDefaults_prefix_map`** — the entry for `m2` is ignored for `m1`; values `""`,
   `"   "`, `5`, `null`, `["p"]` fall through to history; `prefixByMilestone` of `null`, `[]`,
   `"m1"`, `5` is skipped; a map whose prototype provides `m1` (`Object.create({m1: "inh"})`)
   does not match; a milestone with id `"constructor"` / `"toString"` and a plain `{}` map falls
   through; an `Object.create(null)` map owning `m1` matches.
5. **`test_dispatchDefaults_prefix_history`** — `["", "  ", 5, null, "hist-p", "older"]` → `hist-p`;
   `[]`, a non-array (`"hist-p"`, `{0: "x"}`) and all-blank histories fall to the stem.
6. **`test_dispatchDefaults_prefix_trimmed`** — `"  run-p \n"` from a run, `" map-p "` from the
   map and `"\thist-p "` from the history each come back trimmed.
7. **`test_dispatchDefaults_prefix_no_milestone`** — with a matching run, map entry and history
   all present: `"board"`, a story without `cardMap`, a broken chain and a two-card cycle give
   `""`; a depth-0 milestone with `id` missing or `""` skips run and map (even a run whose
   `milestone_id` is `""` and a map with key `""`) and takes the history, then the stem when the
   history is empty.
8. **`test_dispatchDefaults_prefix_pure`** — `JSON.stringify` of `runs`, `settings` and `cardMap`
   is unchanged after the call; two calls return distinct objects; `checkDefaults5` passes with
   `runs` given (the other four fields equal those of the same call without `runs`).

All existing `test_dispatchDefaults_*` tests stay unchanged and green (none of them sets
`prefixHistory`).

### Existing store tests whose expectation changes

Until now `dispatchDefaults` ignored `settings.prefixHistory`; step 3 reads it, and
`RunStore.openDispatch` already passes `store.runSettings`. `tests/core/stores/tst_run_store.qml`
loads `dispatchSettings()` (`prefixHistory: ["old"]`, `:2512-2515`) through `dispatchStore()`, and
asserts the stem `"m3"` for the form prefix: `:2653`, `:2838`, `:3006`, `:3024`, `:3094`, `:3206`
(the `:2621` test loads `prefixHistory: []` and is unaffected). With step 3 these forms start
with `"old"` (no run is passed and no map exists). This subtask updates exactly those
expectations to `"old"` (messages adjusted to say the history's first prefix names it), and
changes nothing else in that file; the sibling store card `5cf6e2f1` owns the new store
behaviour. Any other `tst_run_store.qml` / `tests/ui/` assertion that `bash tests/run.sh` shows
failing for the same reason gets the same treatment; the Tests list above is not otherwise
extended. `tests/ui/tst_dispatch_flow.qml` reads the prefix only after typing it, so it is
not expected to change.

Verification: `bash tests/run.sh` (pytest, then every `tst_*.qml`, including `tests/architecture`).

## Out of scope

- **`RunStore.openDispatch` passing `store.runs`** (`core/stores/RunStore.qml:950`) and saving the
  sent prefix into `prefixByMilestone` after a start: sibling card `5cf6e2f1` "2.1 RunStore
  dispatch: the story target, the retarget and the keyed prefix". Until it lands, the feature is
  not live in the app; that is expected for this subtask.
- **`prefixByMilestone` in `viewer-state.py`** (storage, validation, merge per key, USAGE text):
  sibling card `02ca6d9d` "1.5 viewer-state.py: prefixByMilestone". This spec only reads the field
  when present.
- **`--story` argv and story run-id discovery** in `dispatch-preview.py` / `start-run.py`: sibling
  card `65fb51cf` "1.4".
- Dialog, entry points and docs: cards `2b0955bc`, `c6a09c52`, `4c3d419e`.
- Any change to `base`, `verify`, `parallelism`, `allowNoVerification`, the milestone walk or the
  stem rule; any new key in the result; any change to `dispatchPlan`, `previewSummary` or
  `validateDispatch`.

## Risks for the planner (Review Focus candidates)

- A newest matching run with a blank prefix must not shadow an older matching run with one.
- Story runs carry the **milestone's** id as `milestone_id`; keying on the card's own id would
  silently never match for a story.
- Map lookups must use own keys only; `{}` has `constructor`, which would otherwise return a
  function (non-string) — still skipped, but `toString`/`__proto__` cases must be pinned.
- A brand-new milestone with no run and no map entry gets the last history prefix (another
  milestone's), not its stem: this is what the parent spec's order says (lines 52-54) and is
  deliberate here; the field is editable.
- `runs` passed as a QML `var` list may not be a JS array (see the note at
  `core/stores/RunStore.qml:1130-1131`); `Array.isArray` false means `[]`, which is safe but
  makes the feature silently inert — the store card (2.1) must pass a real array.
