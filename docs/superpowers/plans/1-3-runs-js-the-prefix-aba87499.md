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


---

# 1.3 runs.js: the prefix default from runs, then the milestone-keyed map — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `dispatchDefaults(project, card, cardMap, runs)` computes the default branch prefix from, in order, the newest run of the card's milestone, `settings.prefixByMilestone`, `settings.prefixHistory`, and the milestone's stem.

**Architecture:** One pure function in `core/domain/runs.js` (a `.pragma library` QML-JS module) changes, with three small helpers next to it. Task 1 adds the history step (step 3) in front of the stem and updates the 16 store-test lines whose fixture history (`["old"]`) now names the form's prefix. Task 2 adds the `runs` argument and steps 1 (newest matching run) and 2 (milestone-keyed map), and rewrites the doc comment to state the four-step order.

**Tech Stack:** QML JavaScript (ES5, `.pragma library`), QtTest via `qmltestrunner`, `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/1-3-runs-js-the-prefix-aba87499.md` (prepended above).

## Global Constraints

- `runs.js` is `.pragma library`, pure, never throws, garbage in gives defaults, own-key lookups only, ids compared with `===`, ES5 (`var`, `function`, no `let`/`const`/arrow functions), 2-space indent, no semicolons.
- Comments and docstrings state the contract only, no narrative (no "now", "used to", "no longer", "new").
- `dispatchDefaults` result keeps exactly the five keys `allowNoVerification, base, parallelism, prefix, verify`; only `prefix` changes behaviour.
- Prefix order: (1) `branch_prefix` of the newest run whose `milestone_id === K`; (2) `settings.prefixByMilestone`'s own entry for `K`; (3) first non-blank string of `settings.prefixHistory`; (4) `_stemOf(M.title)`. Every taken value is trimmed. `M === null` → `""`. `K` is the milestone's id, never the story's or subtask's; steps 1-2 only when `K` is a non-empty string.
- "Newest" uses the existing `_isNewer(a, ai, b, bi)`: later `started_at` when both are distinct non-empty strings, else the lower index.
- A `runs` that is not an array is `[]`.
- No production file other than `core/domain/runs.js` changes. In `tests/core/stores/tst_run_store.qml` only the 16 lines listed in Task 1 change.
- `bash tests/run.sh` is green at the end of each task (it includes `tests/architecture`).

## Review Focus

1. A matching run whose `started_at` is not a string (a number, `null`) next to one with a string stamp — a person expects the lower index to win, never a throw or a numeric comparison. Pinned in `test_dispatchDefaults_prefix_runs_newest` (Task 2).
2. A run in any state (`started` with a dead lease, `done`, `escalated`, `canceled`, `stopped`) — a person expects its prefix used all the same. Pinned in `test_dispatchDefaults_prefix_runs_matching` (Task 2).
3. A run `milestone_id` or map key that differs from the milestone id only by case or surrounding whitespace (`" m1"`, `"m1 "`, `"M1"`) — a person expects no match. Pinned in `test_dispatchDefaults_prefix_runs_matching` and `test_dispatchDefaults_prefix_map` (Task 2).
4. A `runs` that is array-like but not an array (`{0: run, length: 1}`, the shape a QML list can take) or a sparse array — a person expects `[]` for the first and holes skipped for the second, never a throw. Pinned in `test_dispatchDefaults_prefix_runs_matching` (Task 2).
5. A milestone whose id is `__proto__` with a map that owns that key (as `JSON.parse` builds it) — a person expects its own entry; a plain `{}` map must not match through the prototype. Pinned in `test_dispatchDefaults_prefix_map` (Task 2). Verified on this machine: in Qt 6's V4, `JSON.parse('{"__proto__": "own-p"}')` owns `__proto__` and reads back `"own-p"`.

## How to run the tests

`bash tests/run.sh <filter>` runs all pytest tiers, then only the `tst_*.qml` files whose path contains `<filter>`. It prints `FAIL!` lines with their `Loc:` and a `Totals:` line per QML file, and exits non-zero on any failure. With no filter it runs everything. The pytest tiers take about two minutes before any QML runs; pass a generous timeout.

---

### Task 1: The prefix history before the stem

**Files:**
- Modify: `core/domain/runs.js:952-975` (doc comment and `prefix:` line of `dispatchDefaults`; two helpers and `_defaultPrefix` inserted between `_stemOf` (ends line 950) and the doc comment)
- Test: `tests/core/domain/tst_runs.qml` (new block inserted after `test_dispatch_inputs_unchanged`, which ends at line 2804, before the `// ---- S3 1.2: dispatch form and preview` line at 2806)
- Test: `tests/core/stores/tst_run_store.qml` lines 2653, 2723, 2758, 2838, 2865, 2923, 2927, 2950, 3006, 3024, 3041, 3051, 3094, 3123, 3206, 3373

**Interfaces:**
- Consumes: `_arrayOr(v)`, `_isObject(v)`, `_stemOf(title)`, `_milestoneOf(card, cardMap)` — all already in `runs.js`; test helpers `mkCard(id, depth, status, parentId, title)` (`tst_runs.qml:2457`), `checkDefaults5`, `fullProject` (already in `tst_runs.qml`).
- Produces (in `runs.js`): `_trimmedOr(v)` → `v.trim()` when `v` is a string, else `""`; `_historyPrefix(history)` → first non-blank string entry of an array, trimmed, else `""`; `_defaultPrefix(milestone, settings)` → `""` when `milestone === null`, else history prefix, else `_stemOf(milestone.title)`. Task 2 extends `_defaultPrefix` with a third parameter `runs`.
- Produces (in `tst_runs.qml`): `mkRun(milestoneId, prefix, startedAt)` → `{milestone_id, branch_prefix, started_at}`; `prefixCards()` → `{m, s, c, map}`; `prefixWith(settings, card, map, runs)` → the `prefix` of `Runs.dispatchDefaults({settings: settings}, card, map, runs)`.

- [ ] **Step 1: Write the failing domain tests**

In `tests/core/domain/tst_runs.qml`, insert this block right after the closing `}` of `test_dispatch_inputs_unchanged` (line 2804) and before the blank line and `// ---- S3 1.2: dispatch form and preview` comment:

```qml

  // ---- 1.3: the prefix default --------------------------------------------------------------

  function mkRun(milestoneId, prefix, startedAt) {
    return { milestone_id: milestoneId, branch_prefix: prefix, started_at: startedAt }
  }

  // Milestone m1 "M3 Document runs" (stem m3), its story s1, the story's subtask c1, and their map.
  function prefixCards() {
    var m = mkCard("m1", 0, "todo", null, "M3 Document runs")
    var s = mkCard("s1", 1, "todo", "m1", "Story")
    var c = mkCard("c1", 2, "todo", "s1", "Subtask")
    return { m: m, s: s, c: c, map: { m1: m, s1: s, c1: c } }
  }

  // The prefix dispatchDefaults gives card with these settings and runs.
  function prefixWith(settings, card, map, runs) {
    return Runs.dispatchDefaults({ settings: settings }, card, map, runs).prefix
  }

  function test_dispatchDefaults_prefix_history() {
    var f = prefixCards()
    var cards = [f.m, f.s, f.c]
    for (var i = 0; i < cards.length; i++) {
      var id = cards[i].id
      compare(prefixWith({ prefixHistory: ["", "  ", 5, null, "hist-p", "older"] }, cards[i], f.map), "hist-p",
              id + ": the first non-blank string entry")
      var stems = [[], "hist-p", { 0: "x" }, ["", "  ", 5, null], null, undefined]
      for (var j = 0; j < stems.length; j++) {
        compare(prefixWith({ prefixHistory: stems[j] }, cards[i], f.map), "m3", id + ": history " + j + " falls to the stem")
      }
    }
    compare(prefixWith({}, f.s, f.map), "m3", "no history key")
    compare(prefixWith({ prefixHistory: ["hist-p"] }, mkCard("m9", 0, "todo", null, "-- **"), {}), "hist-p",
            "the history before an empty stem")
    compare(prefixWith({}, mkCard("m9", 0, "todo", null, "-- **"), {}), "", "an empty stem stays empty")
    compare(Runs.dispatchDefaults({ settings: "x" }, f.s, f.map).prefix, "m3", "settings garbage")
  }

  function test_dispatchDefaults_prefix_no_milestone() {
    var f = prefixCards()
    var settings = { prefixHistory: ["hist-p"] }
    compare(prefixWith(settings, "board", f.map), "", "board")
    compare(prefixWith(settings, f.s, undefined), "", "story without cardMap")
    compare(prefixWith(settings, f.c, { s1: f.s, c1: f.c }), "", "broken chain")
    var a = mkCard("a", 1, "todo", "b", "A")
    var b = mkCard("b", 1, "todo", "a", "B")
    compare(prefixWith(settings, a, { a: a, b: b }), "", "two-card cycle")
    compare(prefixWith(settings, null, f.map), "", "no card")
    var noId = { depth: 0, status: "todo", parentId: null, title: "M3 Document runs" }
    compare(prefixWith(settings, noId, {}), "hist-p", "a milestone without an id takes the history")
    compare(prefixWith({ prefixHistory: [] }, noId, {}), "m3", "then the stem")
  }

  function test_dispatchDefaults_prefix_trimmed() {
    var f = prefixCards()
    compare(prefixWith({ prefixHistory: ["\thist-p "] }, f.s, f.map), "hist-p", "history")
    compare(prefixWith({ prefixHistory: [" my hist-p\n"] }, f.s, f.map), "my hist-p", "inner whitespace kept")
  }
```

- [ ] **Step 2: Run the domain tests to verify they fail**

Run: `bash tests/run.sh tst_runs`
Expected: FAIL. `test_dispatchDefaults_prefix_history` fails with `Compared values are not the same` (actual `m3`, expected `hist-p`); `test_dispatchDefaults_prefix_no_milestone` fails at "a milestone without an id takes the history"; `test_dispatchDefaults_prefix_trimmed` fails at "history". Every other test passes.

- [ ] **Step 3: Update the store tests whose fixture history names the prefix**

`tests/core/stores/tst_run_store.qml`'s `dispatchSettings()` (`:2512-2515`) stores `prefixHistory: ["old"]`, and `dispatchStore()` loads it, so the form's prefix becomes `"old"` instead of the stem `"m3"`. Change exactly these 16 lines and nothing else in the file (verified: with the Task 1 implementation in place these are all the lines that fail, and with them changed the file is green, 191 passed):

Line 2653 — replace:
```qml
    compare(store.dispatchForm.prefix, "m3", "the story's milestone names the prefix")
```
with:
```qml
    compare(store.dispatchForm.prefix, "old", "the history's first prefix names the story's prefix")
```

Line 2723 — replace:
```qml
  property string previewArgs: "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3|--max-concurrent|4|--verify|uv run pytest"
```
with:
```qml
  property string previewArgs: "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest"
```

Line 2758 — replace:
```qml
      compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--branch-prefix|m3|--max-concurrent|4|--verify|uv run pytest",
```
with:
```qml
      compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest",
```

Line 2838 — replace:
```qml
    compare(store.dispatchForm.prefix, "m3", "the stem of the subtask's milestone")
```
with:
```qml
    compare(store.dispatchForm.prefix, "old", "the history's first prefix names the subtask's prefix")
```

Line 2865 — replace:
```qml
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|develop|--branch-prefix|m3|--max-concurrent|4|--verify|uv run pytest")
```
with:
```qml
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|develop|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest")
```

Line 2923 — replace:
```qml
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3|--max-concurrent|4|--allow-no-verification")
```
with:
```qml
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--allow-no-verification")
```

Line 2927 — replace:
```qml
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3|--max-concurrent|4|--verify|-x make check|--verify|uv run pytest|--allow-no-verification")
```
with:
```qml
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|-x make check|--verify|uv run pytest|--allow-no-verification")
```

Line 2950 — replace:
```qml
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3|--max-concurrent|4|--allow-no-verification")
```
with:
```qml
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--allow-no-verification")
```

Line 3006 — replace:
```qml
    compare(store.dispatchForm.prefix, "m3", "the other fields are kept")
```
with:
```qml
    compare(store.dispatchForm.prefix, "old", "the other fields are kept")
```

Line 3024 — replace:
```qml
    compare(store.dispatchForm.prefix, "m3", "nothing changed")
```
with:
```qml
    compare(store.dispatchForm.prefix, "old", "nothing changed")
```

Line 3041 — replace:
```qml
  property string savedJson: '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["m3","old"],"parallelism":4}'
```
with:
```qml
  property string savedJson: '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["old"],"parallelism":4}'
```

Line 3051 — replace:
```qml
    compare(argv(proc), tc.startCmd + "/home/u/my proj|card|t1|--base-branch|main|--branch-prefix|m3|--max-concurrent|4|--verify|uv run pytest")
```
with:
```qml
    compare(argv(proc), tc.startCmd + "/home/u/my proj|card|t1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest")
```

Line 3094 — replace:
```qml
    compare(store.dispatchForm.prefix, "m3")
```
with:
```qml
    compare(store.dispatchForm.prefix, "old")
```

Line 3123 — replace:
```qml
    compare(store.runSettings.prefixHistory.join(","), "m3,old")
```
with:
```qml
    compare(store.runSettings.prefixHistory.join(","), "old")
```

Line 3206 — replace:
```qml
    compare(store.dispatchForm.prefix, "m3", "the form stays for another try")
```
with:
```qml
    compare(store.dispatchForm.prefix, "old", "the form stays for another try")
```

Line 3373 — replace:
```qml
    compare(argv(procB), tc.startCmd + "/home/u/b|milestone|m1|--base-branch|main|--branch-prefix|m3|--max-concurrent|4|--verify|uv run pytest")
```
with:
```qml
    compare(argv(procB), tc.startCmd + "/home/u/b|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest")
```

Do not touch line 2621 (`dispatchStore`'s own check after it reloads `prefixHistory: []`: still `"m3"`), line 3165 (`test_prefix_history_dedups_and_caps_at_20` types `"  m3 "` itself), or any other line. Line numbers are those of the file before this step; none of the replacements adds or removes a line.

- [ ] **Step 4: Run the store tests to verify the new expectations fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL, 15 tests (e.g. `test_open_story_is_offered_with_the_story_flag() the history's first prefix names the story's prefix`), because `runs.js` still gives the stem `m3`.

- [ ] **Step 5: Implement the history step in `core/domain/runs.js`**

Insert after the closing `}` of `_stemOf` (line 950) and before the blank line above `// The dispatch form's starting values.`:

```js

// v trimmed when it is a string, else "".
function _trimmedOr(v) { return typeof v === "string" ? v.trim() : "" }

// The first entry of history that is a non-blank string, trimmed; "" when
// history is not an array or has none.
function _historyPrefix(history) {
  var list = _arrayOr(history)
  for (var i = 0; i < list.length; i++) {
    var prefix = _trimmedOr(list[i])
    if (prefix !== "") return prefix
  }
  return ""
}

// The prefix default for milestone (a card, or null when the card's milestone
// is unknown): "" for null; else the first non-blank prefix of
// settings.prefixHistory, else the stem of milestone's title.
function _defaultPrefix(milestone, settings) {
  if (milestone === null) return ""
  var fromHistory = _historyPrefix(settings.prefixHistory)
  return fromHistory !== "" ? fromHistory : _stemOf(milestone.title)
}
```

Replace the doc comment and `prefix:` line of `dispatchDefaults`. The comment becomes:

```js
// The dispatch form's starting values. project is {defaultBranch, settings}
// with settings as get-run-settings returns it; any part may be missing. base
// is the trimmed default branch (no fallback: the caller resolves it). prefix
// is "" when the card's milestone is unknown, else the first non-blank entry of
// settings.prefixHistory, trimmed, else the stem of the milestone's title.
// verify is the stored non-blank commands verbatim, parallelism the stored
// whole number >= 1 else 4. The opt-out from verification is never pre-ticked.
```

and in the returned object replace:

```js
    prefix: milestone !== null ? _stemOf(milestone.title) : "",
```

with:

```js
    prefix: _defaultPrefix(milestone, settings),
```

- [ ] **Step 6: Run the full suite to verify everything passes**

Run: `bash tests/run.sh`
Expected: exit 0; every `Totals:` line shows `0 failed`; no `TypeError`/`ReferenceError` lines. If a `tests/ui/` or other store assertion fails because a form prefix reads `"old"` where it expected `"m3"`, give it the same treatment (expectation to `"old"`, message naming the history), re-run, and list the test in the commit body. (A probe run before this plan found none outside the 16 lines above.)

- [ ] **Step 7: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): dispatchDefaults takes the prefix history before the stem"
```

---

### Task 2: The newest run of the milestone, then the milestone-keyed map

**Files:**
- Modify: `core/domain/runs.js` (the Task 1 `_defaultPrefix` and the `dispatchDefaults` doc comment, signature and `prefix:` line; two helpers inserted before `_defaultPrefix`)
- Test: `tests/core/domain/tst_runs.qml` (the Task 1 `1.3` block: replace `test_dispatchDefaults_prefix_no_milestone` and `test_dispatchDefaults_prefix_trimmed`, add five tests)

**Interfaces:**
- Consumes: from Task 1, `_trimmedOr(v)`, `_historyPrefix(history)`, `_defaultPrefix(milestone, settings)`; test helpers `mkRun`, `prefixCards`, `prefixWith`. Already in `runs.js`: `_isObject(v)`, `_arrayOr(v)`, `_isNewer(a, ai, b, bi)`, `_stemOf(title)`.
- Produces: `dispatchDefaults(project, card, cardMap, runs)`; `_runPrefix(runs, key)` → trimmed `branch_prefix` of the newest run with `milestone_id === key` and a non-blank string prefix, else `""`; `_mapPrefix(map, key)` → `map`'s own entry for `key` trimmed when `map` is an object and the entry a string, else `""`; `_defaultPrefix(milestone, settings, runs)`. Sibling card 2.1 (`5cf6e2f1`) passes `store.runs` as `runs` from `RunStore.openDispatch`.

- [ ] **Step 1: Write the failing domain tests**

In `tests/core/domain/tst_runs.qml`, inside the `1.3` block added by Task 1, replace the whole of `test_dispatchDefaults_prefix_no_milestone` and `test_dispatchDefaults_prefix_trimmed` with the following (the block's helpers and `test_dispatchDefaults_prefix_history` stay as they are):

```qml
  function test_dispatchDefaults_prefix_order() {
    var f = prefixCards()
    var cards = [f.m, f.s, f.c]
    var runs = [mkRun("m1", "run-p", "2026-10-06T10:00:00Z")]
    for (var i = 0; i < cards.length; i++) {
      var id = cards[i].id
      compare(prefixWith({ prefixByMilestone: { m1: "map-p" }, prefixHistory: ["hist-p"] }, cards[i], f.map, runs), "run-p",
              id + ": the run first")
      compare(prefixWith({ prefixByMilestone: { m1: "map-p" }, prefixHistory: ["hist-p"] }, cards[i], f.map, []), "map-p",
              id + ": then the map")
      compare(prefixWith({ prefixByMilestone: {}, prefixHistory: ["hist-p"] }, cards[i], f.map, []), "hist-p",
              id + ": then the history")
      compare(prefixWith({ prefixByMilestone: {}, prefixHistory: [] }, cards[i], f.map, []), "m3", id + ": then the stem")
    }
    compare(Runs.dispatchDefaults({ settings: "x" }, f.s, f.map, runs).prefix, "run-p", "a run needs no settings")
  }

  // Review Focus 1.
  function test_dispatchDefaults_prefix_runs_newest() {
    var f = prefixCards()
    var settings = { prefixByMilestone: { m1: "map-p" }, prefixHistory: ["hist-p"] }
    var older = mkRun("m1", "older-p", "2026-10-05T10:00:00Z")
    var newer = mkRun("m1", "newer-p", "2026-10-06T10:00:00Z")
    compare(prefixWith(settings, f.s, f.map, [newer, older]), "newer-p", "newest first")
    compare(prefixWith(settings, f.s, f.map, [older, newer]), "newer-p", "a later started_at wins over the index")
    var stamps = [["2026-10-06T10:00:00Z", "2026-10-06T10:00:00Z"], [undefined, "2026-10-06T10:00:00Z"],
                  ["2026-10-06T10:00:00Z", undefined], [undefined, undefined], ["", "2026-10-06T10:00:00Z"],
                  ["", ""], [5, "2026-10-06T10:00:00Z"], [null, "2026-10-06T10:00:00Z"]]
    for (var i = 0; i < stamps.length; i++) {
      var runs = [mkRun("m1", "first-p", stamps[i][0]), mkRun("m1", "second-p", stamps[i][1])]
      compare(prefixWith(settings, f.s, f.map, runs), "first-p", "stamps " + i + ": the lower index wins")
    }
    var bare = { milestone_id: "m1", branch_prefix: "first-p" }
    compare(prefixWith(settings, f.s, f.map, [bare, newer]), "first-p", "no started_at key: the lower index wins")
    var blanks = ["", "  ", null, 5, undefined]
    for (var j = 0; j < blanks.length; j++) {
      compare(prefixWith(settings, f.s, f.map, [mkRun("m1", blanks[j], "2026-10-07T10:00:00Z"), older]), "older-p",
              "a newer run with prefix " + j + " is skipped")
      compare(prefixWith(settings, f.s, f.map, [older, mkRun("m1", blanks[j], "2026-10-07T10:00:00Z")]), "older-p",
              "a later-stamped run with prefix " + j + " is skipped")
      compare(prefixWith(settings, f.s, f.map, [mkRun("m1", blanks[j], "2026-10-07T10:00:00Z")]), "map-p",
              "the only run, with prefix " + j + ", falls to the map")
    }
  }

  // Review Focus 2, 3 and 4.
  function test_dispatchDefaults_prefix_runs_matching() {
    var f = prefixCards()
    var settings = { prefixByMilestone: { m1: "map-p" }, prefixHistory: ["hist-p"] }
    var mine = mkRun("m1", "run-p", "2026-10-05T10:00:00Z")
    compare(prefixWith(settings, f.m, f.map, [mkRun("m2", "other-p", "2026-10-07T10:00:00Z"), mine]), "run-p",
            "another milestone's newer run is ignored")
    compare(prefixWith(settings, f.s, f.map, [mkRun("s1", "story-p", "2026-10-07T10:00:00Z")]), "map-p",
            "a run keyed by the story's own id is ignored")
    compare(prefixWith(settings, f.c, f.map, [mkRun("c1", "card-p", "2026-10-07T10:00:00Z")]), "map-p",
            "a run keyed by the subtask's own id is ignored")
    var ids = [5, null, undefined, ["m1"], { id: "m1" }, " m1", "m1 ", "M1"]
    for (var i = 0; i < ids.length; i++) {
      compare(prefixWith(settings, f.s, f.map, [mkRun(ids[i], "bad-p", "2026-10-07T10:00:00Z")]), "map-p",
              "milestone_id " + i + " never matches")
    }
    compare(prefixWith(settings, f.s, f.map, [null, "x", [], 5, Object.create(null), mine]), "run-p", "garbage entries are skipped")
    var lists = [undefined, null, {}, "m1", 5, { 0: mine, length: 1 }]
    for (var j = 0; j < lists.length; j++) {
      compare(prefixWith(settings, f.s, f.map, lists[j]), "map-p", "runs " + j + " is []")
    }
    var sparse = []
    sparse[3] = mine
    compare(prefixWith(settings, f.s, f.map, sparse), "run-p", "holes are skipped")
    compare(prefixWith(settings, f.s, f.map, [{ milestone_id: "m1", branch_prefix: Object.create(null) }]), "map-p",
            "an unconvertible branch_prefix is skipped")
    var states = [{ status: "started", lease: { live: false } }, { status: "started", lease: { live: true } },
                  { status: "done" }, { status: "escalated" }, { status: "canceled" }, { status: "stopped" }, { status: "" }]
    for (var k = 0; k < states.length; k++) {
      var run = mkRun("m1", "state-p", "2026-10-06T10:00:00Z")
      run.status = states[k].status
      run.lease = states[k].lease
      compare(prefixWith(settings, f.s, f.map, [run]), "state-p", "a run in state " + k + " still names the prefix")
    }
  }

  // Review Focus 3 and 5.
  function test_dispatchDefaults_prefix_map() {
    var f = prefixCards()
    var hist = ["hist-p"]
    compare(prefixWith({ prefixByMilestone: { m2: "other-p" }, prefixHistory: hist }, f.s, f.map, []), "hist-p",
            "another milestone's entry is ignored")
    compare(prefixWith({ prefixByMilestone: { s1: "story-p" }, prefixHistory: hist }, f.s, f.map, []), "hist-p",
            "an entry for the story's own id is ignored")
    compare(prefixWith({ prefixByMilestone: { " m1": "a", "m1 ": "b", M1: "c" }, prefixHistory: hist }, f.s, f.map, []), "hist-p",
            "near-miss keys are ignored")
    var values = ["", "   ", 5, null, ["p"], undefined]
    for (var i = 0; i < values.length; i++) {
      compare(prefixWith({ prefixByMilestone: { m1: values[i] }, prefixHistory: hist }, f.s, f.map, []), "hist-p",
              "value " + i + " falls through")
    }
    var maps = [null, [], "m1", 5, undefined]
    for (var j = 0; j < maps.length; j++) {
      compare(prefixWith({ prefixByMilestone: maps[j], prefixHistory: hist }, f.s, f.map, []), "hist-p", "map " + j + " is skipped")
    }
    compare(prefixWith({ prefixByMilestone: Object.create({ m1: "inh" }), prefixHistory: hist }, f.s, f.map, []), "hist-p",
            "an inherited entry does not match")
    var protoIds = ["constructor", "toString", "__proto__", "hasOwnProperty"]
    for (var k = 0; k < protoIds.length; k++) {
      var m = mkCard(protoIds[k], 0, "todo", null, "M3 Document runs")
      compare(prefixWith({ prefixByMilestone: {}, prefixHistory: hist }, m, {}, []), "hist-p",
              "milestone id " + protoIds[k] + " with a plain map")
    }
    var bare = Object.create(null)
    bare.m1 = "bare-p"
    compare(prefixWith({ prefixByMilestone: bare, prefixHistory: hist }, f.s, f.map, []), "bare-p", "a prototype-less map")
    var own = JSON.parse('{"__proto__": "own-p"}')
    compare(prefixWith({ prefixByMilestone: own, prefixHistory: hist }, mkCard("__proto__", 0, "todo", null, "M3 X"), {}, []),
            "own-p", "an own __proto__ entry matches")
  }

  function test_dispatchDefaults_prefix_trimmed() {
    var f = prefixCards()
    compare(prefixWith({}, f.s, f.map, [mkRun("m1", "  run-p \n", "2026-10-06T10:00:00Z")]), "run-p", "run")
    compare(prefixWith({ prefixByMilestone: { m1: " map-p " } }, f.s, f.map, []), "map-p", "map")
    compare(prefixWith({ prefixHistory: ["\thist-p "] }, f.s, f.map, []), "hist-p", "history")
    compare(prefixWith({ prefixByMilestone: { m1: " my map-p\n" } }, f.s, f.map, []), "my map-p", "inner whitespace kept")
  }

  function test_dispatchDefaults_prefix_no_milestone() {
    var f = prefixCards()
    var settings = { prefixByMilestone: { m1: "map-p", "": "blank-key-p" }, prefixHistory: ["hist-p"] }
    var runs = [mkRun("m1", "run-p", "2026-10-06T10:00:00Z"), mkRun("", "blank-run-p", "2026-10-07T10:00:00Z"),
                mkRun(undefined, "none-run-p", "2026-10-08T10:00:00Z")]
    compare(prefixWith(settings, "board", f.map, runs), "", "board")
    compare(prefixWith(settings, f.s, undefined, runs), "", "story without cardMap")
    compare(prefixWith(settings, f.c, { s1: f.s, c1: f.c }, runs), "", "broken chain")
    var a = mkCard("a", 1, "todo", "b", "A")
    var b = mkCard("b", 1, "todo", "a", "B")
    compare(prefixWith(settings, a, { a: a, b: b }, runs), "", "two-card cycle")
    compare(prefixWith(settings, null, f.map, runs), "", "no card")
    var noId = { depth: 0, status: "todo", parentId: null, title: "M3 Document runs" }
    var blankId = mkCard("", 0, "todo", null, "M3 Document runs")
    var numberId = mkCard(5, 0, "todo", null, "M3 Document runs")
    var keyless = [noId, blankId, numberId]
    var noHistory = { prefixByMilestone: settings.prefixByMilestone, prefixHistory: [] }
    for (var i = 0; i < keyless.length; i++) {
      compare(prefixWith(settings, keyless[i], {}, runs), "hist-p", "milestone " + i + " without a usable id skips run and map")
      compare(prefixWith(noHistory, keyless[i], {}, runs), "m3", "milestone " + i + ": then the stem")
    }
  }

  function test_dispatchDefaults_prefix_pure() {
    var f = prefixCards()
    var project = fullProject()
    project.settings.prefixByMilestone = { m1: "map-p", m2: "other-p" }
    project.settings.prefixHistory = ["hist-p", "older"]
    var runs = [mkRun("m2", "other-p", "2026-10-07T10:00:00Z"), mkRun("m1", "  run-p ", "2026-10-06T10:00:00Z")]
    var before = JSON.stringify([runs, project, f.map])
    var a = Runs.dispatchDefaults(project, f.c, f.map, runs)
    var b = Runs.dispatchDefaults(project, f.c, f.map, runs)
    compare(JSON.stringify([runs, project, f.map]), before, "runs, settings and cardMap unchanged")
    verify(a !== b, "distinct objects")
    verify(a.verify !== b.verify, "distinct verify arrays")
    checkDefaults5(a, "main", 2, "run-p", ["uv run pytest", "bash tests/run.sh"], "with runs")
    checkDefaults5(Runs.dispatchDefaults(project, f.c, f.map), "main", 2, "map-p", ["uv run pytest", "bash tests/run.sh"],
                   "without runs")
    var values = [undefined, null, 0, "x", [], Object.create(null), [null], [Object.create(null)]]
    for (var i = 0; i < values.length; i++) {
      checkDefaults5(Runs.dispatchDefaults(values[i], values[i], values[i], values[i]), "", 4, "", [], "garbage " + i)
    }
  }
```

- [ ] **Step 2: Run the domain tests to verify they fail**

Run: `bash tests/run.sh tst_runs`
Expected: FAIL. `test_dispatchDefaults_prefix_order` fails at `m1: the run first` (actual `hist-p`); `test_dispatchDefaults_prefix_runs_newest`, `test_dispatchDefaults_prefix_runs_matching`, `test_dispatchDefaults_prefix_map`, `test_dispatchDefaults_prefix_trimmed` and `test_dispatchDefaults_prefix_pure` fail with `Compared values are not the same` (actual `hist-p` or `m3`). `test_dispatchDefaults_prefix_no_milestone` and `test_dispatchDefaults_prefix_history` may already pass; every pre-existing test passes.

- [ ] **Step 3: Implement steps 1 and 2 in `core/domain/runs.js`**

Insert right before the `_defaultPrefix` comment added in Task 1:

```js
// The trimmed branch_prefix of the newest run in runs (newest first, see
// _isNewer) whose milestone_id is key and whose branch_prefix is a non-blank
// string; "" when runs is not an array or has none.
function _runPrefix(runs, key) {
  var list = _arrayOr(runs)
  var newest = -1
  for (var i = 0; i < list.length; i++) {
    var run = list[i]
    if (!_isObject(run) || run.milestone_id !== key || _trimmedOr(run.branch_prefix) === "") continue
    if (newest < 0 || _isNewer(run, i, list[newest], newest)) newest = i
  }
  return newest < 0 ? "" : _trimmedOr(list[newest].branch_prefix)
}

// map's own entry for key, trimmed, when map is an object and the entry a
// string; else "". Inherited keys never count.
function _mapPrefix(map, key) {
  if (!_isObject(map) || !Object.prototype.hasOwnProperty.call(map, key)) return ""
  return _trimmedOr(map[key])
}
```

Replace the whole Task 1 `_defaultPrefix` (comment and function) with:

```js
// The prefix default for milestone (a card, or null when the card's milestone
// is unknown): "" for null; else the first non-blank of, in order, the newest
// run of the milestone (_runPrefix), settings.prefixByMilestone's own entry for
// the milestone's id (both only when that id is a non-empty string), the first
// prefix of settings.prefixHistory, and the stem of milestone's title.
function _defaultPrefix(milestone, settings, runs) {
  if (milestone === null) return ""
  var key = milestone.id
  if (typeof key === "string" && key !== "") {
    var fromRun = _runPrefix(runs, key)
    if (fromRun !== "") return fromRun
    var fromMap = _mapPrefix(settings.prefixByMilestone, key)
    if (fromMap !== "") return fromMap
  }
  var fromHistory = _historyPrefix(settings.prefixHistory)
  return fromHistory !== "" ? fromHistory : _stemOf(milestone.title)
}
```

Replace the `dispatchDefaults` doc comment and signature:

```js
// The dispatch form's starting values. project is {defaultBranch, settings}
// with settings as get-run-settings returns it; runs is the Runs snapshot
// (normalizeRun output, newest first), [] when not an array; any part may be
// missing. base is the trimmed default branch (no fallback: the caller
// resolves it). prefix is "" when the card's milestone is unknown, else the
// first non-blank, trimmed, of: the branch_prefix of the newest run whose
// milestone_id is the milestone's id; settings.prefixByMilestone's own entry
// for that id; the first entry of settings.prefixHistory; the stem of the
// milestone's title. verify is the stored non-blank commands verbatim,
// parallelism the stored whole number >= 1 else 4. The opt-out from
// verification is never pre-ticked.
function dispatchDefaults(project, card, cardMap, runs) {
```

and in the returned object replace:

```js
    prefix: _defaultPrefix(milestone, settings),
```

with:

```js
    prefix: _defaultPrefix(milestone, settings, runs),
```

- [ ] **Step 4: Run the full suite to verify everything passes**

Run: `bash tests/run.sh`
Expected: exit 0; every `Totals:` line shows `0 failed`; no `TypeError`/`ReferenceError` lines. `git diff --stat HEAD` lists only `core/domain/runs.js` and `tests/core/domain/tst_runs.qml`.

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): dispatchDefaults takes the prefix from the milestone's newest run, then prefixByMilestone"
```

---

## Self-review (planner)

**Spec coverage.**
- Signature with `runs`, non-array → `[]`: Task 2 Step 3; tests `runs_matching` (lists), `pure` (garbage 4-arg).
- `M` and `K` (milestone's id, not the card's): `order` (m1/s1/c1), `runs_matching` and `map` (story/subtask own ids ignored), `no_milestone` (keyless milestones).
- Step 1 newest matching run, `_isNewer`, blank prefixes skipped, status ignored: `runs_newest`, `runs_matching`.
- Step 2 own-key map, prototype-less map, inherited keys, malformed map: `map`.
- Step 3 history: Task 1 `history`; non-string/blank skipped, non-array skipped.
- Step 4 stem, may be `""`: Task 1 `history` (empty stem).
- Trimmed values: `trimmed` (run, map, history).
- `M === null` → `""`; keyless `M` → history then stem: `no_milestone`.
- Invariants (pure, never throws, five keys, other fields unaffected): `pure`; existing `test_dispatchDefaults_*` unchanged.
- Doc comment states the contract: Task 2 Step 3.
- Store-test fallout: Task 1 Step 3. The spec listed six lines (`:2653, :2838, :3006, :3024, :3094, :3206`); a probe run with the history step in place showed ten more on the same cause (argv strings carrying `--branch-prefix|m3`, `previewArgs`, `savedJson`, and the saved history `"m3,old"`). The spec's "same treatment" clause covers them; all 16 are listed verbatim. `tests/ui/` stays green in that probe.

**Placeholder scan.** No TBD/TODO; every code step carries its code.

**Type consistency.** `_trimmedOr`, `_historyPrefix`, `_runPrefix(runs, key)`, `_mapPrefix(map, key)`, `_defaultPrefix(milestone, settings[, runs])` are defined before use; Task 2 replaces Task 1's `_defaultPrefix` and its call site together. Test helpers `mkRun`, `prefixCards`, `prefixWith` are defined in Task 1 and reused unchanged in Task 2.

**Review Focus.** All five lines have a pinning test in Task 2.
<!-- task-pipeline: validated -->
