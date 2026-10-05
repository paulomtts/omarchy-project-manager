# 1.1 runs.js: dispatchPlan and dispatchDefaults (card 5eb7ec0c)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-dispatch-design.md` (S3):
"Non-goals" (lines 24-26), "Dispatch levels" (lines 30-37), "Flow" defaults
(lines 75-81), "Architecture" bullet 1 (lines 89-92) and the per-project
settings bullet (lines 113-117), "Testing" bullet 1 (lines 149-151). Parent
story 1c665cfd ("Dispatch domain"); sibling subtask 45cc9067 (1.2,
`validateDispatch` and `previewSummary`). No blockers.

## Starting point

`core/domain/runs.js` (`.pragma library`, 774 lines, no `.import` yet) ends with
the `// ---- Run alerts (S2 1.2) ----` section (`newAlerts`, runs.js:756-774).
Private helpers available for reuse: `_isObject`, `_arrayOr`, `_stringOr`,
`_isFiniteNumber` (runs.js:95-98) and `_textOf` (runs.js:258, trimmed `String`,
never throws).

`core/domain/board.js` already has `isFinishedStatus(status)` (board.js:186):
`done | merged | canceled | archived`, exactly the set the parent spec refuses
(lines 90-91). Board cards come from `brd tree`
(`{id, title, description, status, blocked_by, created_at, updated_at, children}`)
and `Board.indexTree()` (board.js:12) injects `parentId` (null for a root) and
`depth` (0 milestone, 1 story, 2 subtask) and returns `{cardMap}` (id -> card).

`dispatchPlan` and `dispatchDefaults` exist nowhere yet.

## Scope

Add two pure functions to `core/domain/runs.js` in a new section after
`newAlerts`, banner `// ---- Dispatch (S3 1.1) ----`, with tests in
`tests/core/domain/tst_runs.qml`. Tests first.

Constraints (from `docs/architecture.md` line 11, the domain layer may import
only other `core/domain` files with `.import "x.js" as X`; line 174, `runs.js`
is "pure JS, never throws"; and the conventions of the sibling runs.js specs,
e.g. `1-1-runs-js-controls-adff6c85.md` "Scope"):

- `var`/`function` style, no `const`/`let`/arrows, `_`-prefixed private
  helpers, one comment block above each function.
- `runs.js` gains exactly one import, `.import "board.js" as Board`, placed
  under `.pragma library`, and reuses `Board.isFinishedStatus`: the finished set
  is not copied. (`graph.js` already imports `board.js` the same way;
  `tests/architecture/test_layers.py` `violations_domain` allows it.)
- No function throws. Garbage input (`undefined`, `null`, numbers, strings other
  than `"board"`, `true`, `{}`, `[]`, `Object.create(null)`) gives the default
  result described below.
- Card ids are compared by `===` and looked up in `cardMap` only through
  `Object.prototype.hasOwnProperty.call(cardMap, id)`, so ids such as
  `__proto__`, `constructor` or `toString` behave like any absent id.
- Plain ASCII only in strings and comments (`tests/architecture/test_icon_glyphs.py`).
- Every returned object and array is fresh; inputs are never mutated.
- Existing functions and their tests are not changed.

### Departure from the parent signatures (deliberate, pinned here)

The parent spec writes `dispatchPlan(card)` and `dispatchDefaults(project, card)`
(line 89-91). A lone card cannot name its milestone's title (a story's
suggestion, line 37) or its milestone's stem (line 77-78), so both take an
optional last argument `cardMap` (the `{id: card}` map from `Board.indexTree`).
Calls with the parent's arity still work; they just cannot resolve ancestors.
The "whole board" entry (line 36), which has no card, is requested with the
string `"board"` in the card position.

### Out of scope

- `validateDispatch(form)` and `previewSummary(dryRunData)` (parent line 92):
  sibling card 45cc9067. Rejecting an empty prefix, an empty verify list without
  opt-out, or parallelism < 1 is that card's job, not this one's.
- Assembling the final `am run` argv (`--branch-prefix`, `--base`, `--verify`,
  `--parallel`, `--allow-no-verification`, `--dry-run`): store/backend cards.
- Finding the repo's default branch (`git symbolic-ref`, parent line 75-77):
  the backend; `dispatchDefaults` only receives it.
- Any new field in `viewer-state.py` (parallelism, prefix history, confirm
  setting; parent lines 113-117): story "Dispatch backend" (d3d879b9).
- `RunStore` dispatch state, `DispatchDialog.qml`, entry points, shortcuts:
  stories 3d877d1f and c56468c7.
- `docs/architecture.md`. Its runs.js sentence (line 174) says every input
  comes from `am`, never from a brd card; the dispatch functions read a brd card
  by the parent spec's design (line 89-91). Updating that sentence belongs to
  the S3 docs work, not this card. The new section's own comment block states
  the exception.
- No file outside `core/domain/runs.js` and `tests/core/domain/tst_runs.qml` is
  touched.

## Behaviour

### `dispatchPlan(card, cardMap)` -> plan

Always returns a fresh object with exactly the keys
`command, flags, level, offered, reason, suggest`:

| key | type | meaning |
|---|---|---|
| `offered` | boolean | the dialog may offer Start for this target |
| `level` | string | `"milestone"`, `"subtask"`, `"story"`, `"board"`, or `""` when unknown |
| `command` | string | `"milestone"`, `"card"`, `"board"` when offered, else `""` |
| `flags` | array of strings | the `am run` target argv when offered, else `[]` |
| `reason` | string | `""` when offered, else one of the sentences below |
| `suggest` | `null` or `{id, title}` | only for a story: its milestone |

Decision order (first match wins):

1. `card === "board"` (exact, case-sensitive, untrimmed) -> offered,
   level `"board"`, command `"board"`, flags `["--board"]`. `cardMap` is ignored.
2. `card` is not an object (`_isObject` false: garbage, any other string,
   arrays) or `card.id` is not a valid id -> refused, level `""`, reason
   **NO_CARD**. A valid id is a non-empty string that does not start with `-`
   (so it can never be read by `am` as a flag); it is used verbatim, not trimmed.
3. `card.depth` is not a non-negative integer number (missing, `-1`, `1.5`,
   `NaN`, `Infinity`, the string `"0"`) -> refused, level `""`, reason
   **UNKNOWN_LEVEL**.
4. level = `"milestone"` for depth 0, `"story"` for depth 1, `"subtask"` for
   depth >= 2 (same split as `Board.kindLabel`).
5. `Board.isFinishedStatus(card.status)` -> refused, that level, reason
   **FINISHED** for that status, `suggest` null. Status match is exact
   (`"Done"`, `" done"` are not finished). `blocked`, `todo`, `in_progress`,
   any other or missing status is not finished.
6. Story -> refused, level `"story"`, reason **STORY**, `suggest`:
   - `card.parentId` a non-empty string -> `{id: card.parentId, title}`, where
     `title` is `_textOf(cardMap[parentId].title)` when `cardMap` is an object
     that owns `parentId` as a key and that entry is an object, else `""`.
   - otherwise `null`.
   The suggestion is not checked for being dispatchable: the caller runs
   `dispatchPlan` on the suggested milestone card, which refuses a finished one.
7. Milestone -> offered, command `"milestone"`, flags `["--milestone", id]`.
8. Subtask -> offered, command `"card"`, flags `["--card", id]`.

Reason strings (exact, no trailing period):

| name | text |
|---|---|
| NO_CARD | `No card to dispatch` |
| UNKNOWN_LEVEL | `The card's level is unknown` |
| STORY | `A story is dispatched through its milestone` |
| FINISHED (done) | `The card is done` |
| FINISHED (merged) | `The card is merged` |
| FINISHED (canceled) | `The card is canceled` |
| FINISHED (archived) | `The card is archived` |

### `dispatchDefaults(project, card, cardMap)` -> form defaults

Always returns a fresh object with exactly the keys
`allowNoVerification, base, parallelism, prefix, verify`.

`project` is `{defaultBranch, settings}`; `settings` is the per-project run
settings object as `get-run-settings` returns it
(`{verify, allowNoVerification, notifyOnEscalation}` today, plus
`parallelism` once the backend card adds it). Any part may be missing or
garbage.

- **base**: `_textOf(project.defaultBranch)` when `project` is an object and
  `defaultBranch` is a string, else `""`. There is no `master`/`main` fallback
  here (parent line 75-77: the caller resolves it).
- **prefix**: the stem of the milestone card's title (rule below), else `""`.
  The milestone card is:
  - `card` itself when `card` is an object with `depth === 0`;
  - otherwise, when `card` is an object and `cardMap` an object, the card
    reached by following `parentId` through `cardMap` (own keys only) from
    `card` until a card whose `parentId` is `null`, `undefined` or `""`. A
    missing link, a non-object entry or a cycle (an id seen twice) means no
    milestone, so `""`. The walk trusts `parentId`, not `depth`: it ends at the
    first card with no parent, whatever its `depth` (so a card with no `parentId`
    and a missing or non-zero `depth` is its own milestone).
  - `card === "board"`, garbage, or no `cardMap` for a non-root card: `""`.
  A card's `status` plays no part in the defaults.
- **stem rule** (parent line 77-78 gives only `M3 Document runs` -> `m3`; the
  rest is pinned here, because real milestone titles such as
  `am run monitor (read-only)` carry no number): split `_textOf(title)` on
  whitespace; clean each token to lower case keeping only `[a-z0-9]`; drop
  tokens that clean to `""`. If the first cleaned token is letters followed by
  digits (`/^[a-z]+[0-9]+$/`), the stem is that token. Otherwise it is the first
  three cleaned tokens joined by `-`, cut to 24 characters, with any trailing
  `-` removed. No tokens -> `""`.
  Examples: `M3 Document runs` -> `m3`; `M3: Document` -> `m3`;
  `s12 Polish` -> `s12`; `am run monitor (read-only)` -> `am-run-monitor`;
  `Dispatching am runs from the panel` -> `dispatching-am-runs`;
  `Milestone 3` -> `milestone-3`; `Internationalization localization globalization`
  -> `internationalization-loc` (24 chars); `-- ** --` -> `""`.
- **verify** (parent line 78-81: last values used, empty when none stored): a
  fresh array of the elements of `settings.verify` that are strings with
  non-blank content after trimming, kept verbatim and in order. Anything else
  (no settings, `verify` not an array) -> `[]`.
- **allowNoVerification**: always `false`. The opt-out is an explicit checkbox
  the user ticks per dispatch (parent line 80-81); a stored value is not
  pre-ticked.
- **parallelism**: `settings.parallelism` when it is an integer number >= 1,
  else `4` (the value the parent's dialog sketch shows, line 58; no default is
  stored yet). No upper cap here.

## Tests

Tier for all: pure domain QML `TestCase` in `tests/core/domain/tst_runs.qml`
(`TestCase { name: "DomainRuns" }`, `Runs` = runs.js). Both functions are pure,
take plain JS values and need no store, UI or backend, so per
`docs/architecture.md` "Tests" (line 211) they belong with the other runs.js
domain tests, not in store or UI tiers. Build cards with a test-local helper
`mkCard(id, depth, status, parentId, title)` returning
`{id, depth, status, parentId, title}`; build maps by hand (or through
`Board.indexTree` only if the test imports board.js; plain literals suffice).

| test | proves |
|---|---|
| `test_dispatchPlan_shape` | for an offered, a refused and a garbage input: keys exactly `command,flags,level,offered,reason,suggest`; two calls return distinct objects and distinct `flags` arrays; mutating a result's `flags` does not change the next result |
| `test_dispatchPlan_milestone` | depth 0, status `todo`/`in_progress`/`blocked`/missing: offered, level `milestone`, command `milestone`, flags `["--milestone", id]`, reason `""`, suggest null |
| `test_dispatchPlan_subtask` | depth 2 and depth 3: offered, level `subtask`, command `card`, flags `["--card", id]` |
| `test_dispatchPlan_board` | `"board"`: offered, level `board`, command `board`, flags `["--board"]`; `"Board"`, `" board"`, `"board "` give NO_CARD |
| `test_dispatchPlan_story` | depth 1 with parentId `m1` and a cardMap holding `m1` titled `M3 Document runs`: not offered, level `story`, command `""`, flags `[]`, reason STORY, suggest `{id:"m1", title:"M3 Document runs"}`; without cardMap, or with cardMap missing `m1`, or with `m1` mapped to a non-object: suggest `{id:"m1", title:""}`; parentId null / `""` / 5: suggest null; suggest is a fresh object each call |
| `test_dispatchPlan_finished` | each of `done`, `merged`, `canceled`, `archived` at depth 0, 1 and 2: not offered, the level of its depth, its exact FINISHED sentence, flags `[]`, suggest null (a finished story gets no suggestion); `"Done"` and `" done"` at depth 0 are offered |
| `test_dispatchPlan_bad_id` | id missing, `""`, `5`, `null`, `{}`, `"-x"`, `"--board"`: NO_CARD, level `""`; an id with spaces inside (`"a b"`) is used verbatim |
| `test_dispatchPlan_unknown_level` | depth missing, `-1`, `1.5`, `NaN`, `Infinity`, `"0"`, `null`: UNKNOWN_LEVEL, level `""`, command `""` |
| `test_dispatchPlan_garbage` | `undefined`, `null`, `0`, `true`, `"x"`, `[]`, `{}`, `Object.create(null)` as card: no throw, NO_CARD; cardMap `null`, `"x"`, `[]`, `Object.create(null)` with a valid story: no throw |
| `test_dispatchPlan_proto_ids` | story whose parentId is `__proto__`, `constructor` or `toString` with a plain-object cardMap not owning it: suggest `{id: <that id>, title: ""}`, no throw |
| `test_dispatchDefaults_shape` | keys exactly `allowNoVerification,base,parallelism,prefix,verify` for a full input and for garbage; `verify` is a fresh array (mutating it leaves `settings.verify` and the next result unchanged) |
| `test_dispatchDefaults_base` | `"main"` -> `main`; `"  trunk \n"` -> `trunk`; missing, `null`, `5`, `{}` -> `""`; project garbage -> `""` |
| `test_dispatchDefaults_prefix_stem` | every example in the stem rule above, at depth 0 with no cardMap; title missing or `null` -> `""`; title `5` -> `5` (read through `_textOf`) |
| `test_dispatchDefaults_prefix_ancestor` | a story and a subtask under milestone `M3 Document runs` via cardMap -> `m3`; same with no cardMap -> `""`; broken chain (parent absent) -> `""`; a two-card parentId cycle -> `""` and no hang; `"board"` -> `""`; the card's own status (e.g. `done`) does not change the prefix |
| `test_dispatchDefaults_verify` | `["uv run pytest", "  ", "", 5, null, " make test "]` -> `["uv run pytest", " make test "]`; `verify` missing, `"x"`, `{}` -> `[]` |
| `test_dispatchDefaults_allow_no_verification` | `false` with settings `allowNoVerification: true`, with it absent, and with garbage project |
| `test_dispatchDefaults_parallelism` | `2` -> 2; `1` -> 1; missing, `0`, `-3`, `2.5`, `"3"`, `NaN`, `Infinity`, `null` -> 4 |
| `test_dispatchDefaults_garbage` | `undefined`, `null`, `0`, `"x"`, `[]`, `Object.create(null)` for project, card and cardMap in combination: no throw, `{allowNoVerification:false, base:"", parallelism:4, prefix:"", verify:[]}` |

The plan's verification is `bash tests/run.sh` green (pytest, including
`tests/architecture/test_layers.py` with the new `board.js` import and
`test_icon_glyphs.py`, then every QML test file); `bash tests/run.sh tst_runs`
is the fast loop.

---

# runs.js dispatchPlan and dispatchDefaults Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two pure, never-throwing functions to `core/domain/runs.js`: `dispatchPlan(card, cardMap)` (what the dispatch dialog may start for a brd card, the whole board, or nothing) and `dispatchDefaults(project, card, cardMap)` (the dispatch form's initial values).

**Architecture:** A new section `// ---- Dispatch (S3 1.1) ----` appended after `newAlerts` at the end of `core/domain/runs.js`, with private `_`-prefixed helpers. `runs.js` gains its first import, `.import "board.js" as Board`, to reuse `Board.isFinishedStatus`. Tests go at the end of `tests/core/domain/tst_runs.qml` (QML `TestCase` named `DomainRuns`).

**Tech Stack:** QML JavaScript library (`.pragma library`, ES5 style `var`/`function`), Qt Quick Test (`qmltestrunner`), pytest architecture checks, all driven by `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/1-1-runs-js-5eb7ec0c.md` (copied in full above this plan).

## Global Constraints

- Only `core/domain/runs.js` and `tests/core/domain/tst_runs.qml` are touched.
- `var`/`function` style, no `const`/`let`/arrows, `_`-prefixed private helpers, one comment block above each function.
- `runs.js` gains exactly one import, `.import "board.js" as Board`, placed directly under `.pragma library`; the finished set is not copied, `Board.isFinishedStatus` is reused.
- No function throws. Garbage input (`undefined`, `null`, numbers, strings other than `"board"`, `true`, `{}`, `[]`, `Object.create(null)`) gives the default result.
- Card ids are compared by `===` and looked up in `cardMap` only through `Object.prototype.hasOwnProperty.call(cardMap, id)`.
- Plain ASCII only in strings and comments (`tests/architecture/test_icon_glyphs.py`).
- Every returned object and array is fresh; inputs are never mutated.
- Existing functions and their tests are not changed.
- Reason strings, exact, no trailing period: `No card to dispatch`, `The card's level is unknown`, `A story is dispatched through its milestone`, `The card is done`, `The card is merged`, `The card is canceled`, `The card is archived`.
- `dispatchPlan` keys exactly `command, flags, level, offered, reason, suggest`; `dispatchDefaults` keys exactly `allowNoVerification, base, parallelism, prefix, verify`.
- Default parallelism `4`; `allowNoVerification` always `false`; no `master`/`main` fallback for `base`.
- Verification: `bash tests/run.sh` green; `bash tests/run.sh tst_runs` is the fast loop.

## Review Focus

1. **Inputs are never mutated** (card, cardMap, project, settings, settings.verify): a person reusing the brd tree and the settings object after opening the dialog expects them unchanged. Pinned by `test_dispatch_inputs_unchanged` (Task 2).
2. **A card whose `parentId` is its own id** (a self-cycle, the smallest corrupt board): `dispatchDefaults` must return prefix `""` without hanging the panel. Pinned in `test_dispatchDefaults_prefix_ancestor_edges` (Task 2).
3. **The 24-character cut landing right after a hyphen** (first word 23 characters long): the prefix must not end in `-`, or branch names read `xxx--card`. Pinned in `test_dispatchDefaults_prefix_stem_edges` (Task 2).
4. **A milestone title or a parent's title that `String()` cannot convert** (`Object.create(null)`), and non-ASCII titles (`Cafe` with accents): no throw; accented letters are dropped by the `[a-z0-9]` rule. Pinned in `test_dispatchPlan_odd_titles` (Task 1) and `test_dispatchDefaults_prefix_stem_edges` (Task 2).
5. **A depth-0 card that carries a stray `parentId`, and a chain ending at a parentless card whose depth is not 0**: the depth-0 card is its own milestone; the walk trusts `parentId`, not `depth`. Pinned in `test_dispatchDefaults_prefix_ancestor_edges` (Task 2).

## File Structure

- Modify `core/domain/runs.js`: line 1-2 gain the `board.js` import; a new section after `newAlerts` (current end of file, line 774) holds the dispatch constants, private helpers `_isDispatchId`, `_isWholeNumber`, `_ownCard`, `_offeredPlan`, `_refusedPlan`, `_milestoneOf`, `_stemOf`, and the public `dispatchPlan`, `dispatchDefaults`.
- Modify `tests/core/domain/tst_runs.qml`: append a section `// ---- S3 1.1: dispatch ----` before the final closing `}` of the `TestCase` (currently line 1609), with helpers `mkCard`, `checkPlan`, `checkDefaults5` and the tests.

---

### Task 1: `dispatchPlan(card, cardMap)`

**Files:**
- Modify: `core/domain/runs.js:1` (add import) and append after line 774
- Test: `tests/core/domain/tst_runs.qml` (append before the final `}` at line 1609)

**Interfaces:**
- Consumes: existing runs.js helpers `_isObject(v)`, `_isFiniteNumber(v)` (runs.js:95-98), `_textOf(v)` (runs.js:258); `Board.isFinishedStatus(status) -> bool` (board.js:186).
- Produces:
  - `dispatchPlan(card, cardMap) -> {command: string, flags: string[], level: string, offered: bool, reason: string, suggest: null | {id: string, title: string}}`
  - private helpers reused by Task 2: `_isWholeNumber(v) -> bool` (finite number with no fraction), `_ownCard(cardMap, id) -> object | null` (the entry when `cardMap` is an object that owns string key `id` and the entry is an object, else null).

- [ ] **Step 1: Write the failing tests**

In `tests/core/domain/tst_runs.qml`, the file ends with:

```qml
    compare(Runs.normalizeRun({ status: { control: "y" } }).requests.length, 0, "control not an object")
  }
}
```

Insert the following block between that `  }` and the final `}` (so it is still inside `TestCase { ... }`):

```qml

  // ---- S3 1.1: dispatch -------------------------------------------------------------------

  function mkCard(id, depth, status, parentId, title) {
    return { id: id, depth: depth, status: status, parentId: parentId, title: title }
  }

  // Asserts a dispatchPlan result field by field; suggest compared as JSON.
  function checkPlan(p, offered, level, command, flags, reason, suggest, label) {
    compare(Object.keys(p).sort().join(","), "command,flags,level,offered,reason,suggest", label + " keys")
    compare(p.offered, offered, label + " offered")
    compare(p.level, level, label + " level")
    compare(p.command, command, label + " command")
    compare(Array.isArray(p.flags), true, label + " flags is array")
    compare(JSON.stringify(p.flags), JSON.stringify(flags), label + " flags")
    compare(p.reason, reason, label + " reason")
    compare(JSON.stringify(p.suggest), JSON.stringify(suggest), label + " suggest")
  }

  function test_dispatchPlan_shape() {
    var inputs = [mkCard("m1", 0, "todo", null, "M3 Document runs"), mkCard("s1", 1, "todo", "m1", "S"), undefined]
    for (var i = 0; i < inputs.length; i++) {
      var a = Runs.dispatchPlan(inputs[i])
      var b = Runs.dispatchPlan(inputs[i])
      compare(Object.keys(a).sort().join(","), "command,flags,level,offered,reason,suggest", "keys " + i)
      verify(a !== b, "distinct objects " + i)
      verify(a.flags !== b.flags, "distinct flags arrays " + i)
    }
    var first = Runs.dispatchPlan(inputs[0])
    first.flags.push("--evil")
    first.flags[1] = "x"
    compare(JSON.stringify(Runs.dispatchPlan(inputs[0]).flags), JSON.stringify(["--milestone", "m1"]), "mutation does not leak")
    var board = Runs.dispatchPlan("board")
    board.flags.push("--evil")
    compare(JSON.stringify(Runs.dispatchPlan("board").flags), JSON.stringify(["--board"]), "board flags fresh")
  }

  function test_dispatchPlan_milestone() {
    var statuses = ["todo", "in_progress", "blocked", undefined]
    for (var i = 0; i < statuses.length; i++) {
      checkPlan(Runs.dispatchPlan(mkCard("m1", 0, statuses[i], null, "M3")),
                true, "milestone", "milestone", ["--milestone", "m1"], "", null, "status " + statuses[i])
    }
  }

  function test_dispatchPlan_subtask() {
    checkPlan(Runs.dispatchPlan(mkCard("c1", 2, "todo", "s1", "C")),
              true, "subtask", "card", ["--card", "c1"], "", null, "depth 2")
    checkPlan(Runs.dispatchPlan(mkCard("c2", 3, "in_progress", "c1", "D")),
              true, "subtask", "card", ["--card", "c2"], "", null, "depth 3")
  }

  function test_dispatchPlan_board() {
    checkPlan(Runs.dispatchPlan("board"), true, "board", "board", ["--board"], "", null, "board")
    checkPlan(Runs.dispatchPlan("board", { m1: mkCard("m1", 0, "todo", null, "M") }),
              true, "board", "board", ["--board"], "", null, "board ignores cardMap")
    var near = ["Board", " board", "board "]
    for (var i = 0; i < near.length; i++) {
      checkPlan(Runs.dispatchPlan(near[i]), false, "", "", [], "No card to dispatch", null, "near '" + near[i] + "'")
    }
  }

  function test_dispatchPlan_story() {
    var story = mkCard("s1", 1, "todo", "m1", "Story")
    var map = { m1: mkCard("m1", 0, "todo", null, "M3 Document runs"), s1: story }
    var reason = "A story is dispatched through its milestone"
    checkPlan(Runs.dispatchPlan(story, map), false, "story", "", [], reason,
              { id: "m1", title: "M3 Document runs" }, "with cardMap")
    checkPlan(Runs.dispatchPlan(story), false, "story", "", [], reason, { id: "m1", title: "" }, "no cardMap")
    checkPlan(Runs.dispatchPlan(story, { s1: story }), false, "story", "", [], reason,
              { id: "m1", title: "" }, "cardMap missing m1")
    checkPlan(Runs.dispatchPlan(story, { m1: "M3" }), false, "story", "", [], reason,
              { id: "m1", title: "" }, "m1 not an object")
    checkPlan(Runs.dispatchPlan(story, { m1: mkCard("m1", 0, "todo", null, "  M3 x \n") }), false, "story", "", [], reason,
              { id: "m1", title: "M3 x" }, "title trimmed")
    var parents = [null, "", 5]
    for (var i = 0; i < parents.length; i++) {
      checkPlan(Runs.dispatchPlan(mkCard("s1", 1, "todo", parents[i], "S"), map), false, "story", "", [], reason,
                null, "parentId " + parents[i])
    }
    var a = Runs.dispatchPlan(story, map)
    var b = Runs.dispatchPlan(story, map)
    verify(a.suggest !== b.suggest, "suggest is fresh")
    a.suggest.title = "x"
    compare(Runs.dispatchPlan(story, map).suggest.title, "M3 Document runs", "mutation does not leak")
    compare(map.m1.title, "M3 Document runs", "cardMap unchanged")
  }

  function test_dispatchPlan_finished() {
    var statuses = ["done", "merged", "canceled", "archived"]
    var levels = ["milestone", "story", "subtask"]
    var map = { m1: mkCard("m1", 0, "todo", null, "M3") }
    for (var i = 0; i < statuses.length; i++) {
      for (var d = 0; d < 3; d++) {
        checkPlan(Runs.dispatchPlan(mkCard("x1", d, statuses[i], "m1", "X"), map), false, levels[d], "", [],
                  "The card is " + statuses[i], null, statuses[i] + " depth " + d)
      }
    }
    compare(Runs.dispatchPlan(mkCard("s1", 1, "done", "m1", "S"), map).reason, "The card is done", "exact sentence")
    checkPlan(Runs.dispatchPlan(mkCard("m1", 0, "Done", null, "M")), true, "milestone", "milestone",
              ["--milestone", "m1"], "", null, "Done is not finished")
    checkPlan(Runs.dispatchPlan(mkCard("m1", 0, " done", null, "M")), true, "milestone", "milestone",
              ["--milestone", "m1"], "", null, "' done' is not finished")
  }

  function test_dispatchPlan_bad_id() {
    var ids = [undefined, "", 5, null, {}, "-x", "--board"]
    for (var i = 0; i < ids.length; i++) {
      checkPlan(Runs.dispatchPlan(mkCard(ids[i], 0, "todo", null, "M")), false, "", "", [],
                "No card to dispatch", null, "id " + i)
    }
    var noId = { depth: 0, status: "todo", parentId: null, title: "M" }
    checkPlan(Runs.dispatchPlan(noId), false, "", "", [], "No card to dispatch", null, "id missing")
    checkPlan(Runs.dispatchPlan(mkCard("a b", 2, "todo", "s1", "C")), true, "subtask", "card",
              ["--card", "a b"], "", null, "id used verbatim")
    checkPlan(Runs.dispatchPlan(mkCard(" m1 ", 0, "todo", null, "M")), true, "milestone", "milestone",
              ["--milestone", " m1 "], "", null, "id not trimmed")
  }

  function test_dispatchPlan_unknown_level() {
    var depths = [undefined, -1, 1.5, NaN, Infinity, "0", null]
    for (var i = 0; i < depths.length; i++) {
      checkPlan(Runs.dispatchPlan(mkCard("x1", depths[i], "todo", null, "X")), false, "", "", [],
                "The card's level is unknown", null, "depth " + depths[i])
    }
    var noDepth = { id: "x1", status: "todo" }
    checkPlan(Runs.dispatchPlan(noDepth), false, "", "", [], "The card's level is unknown", null, "depth missing")
    checkPlan(Runs.dispatchPlan(mkCard("x1", -1, "done", null, "X")), false, "", "", [],
              "The card's level is unknown", null, "level checked before status")
  }

  function test_dispatchPlan_garbage() {
    var cards = [undefined, null, 0, true, "x", [], {}, Object.create(null)]
    for (var i = 0; i < cards.length; i++) {
      checkPlan(Runs.dispatchPlan(cards[i]), false, "", "", [], "No card to dispatch", null, "card " + i)
    }
    checkPlan(Runs.dispatchPlan(), false, "", "", [], "No card to dispatch", null, "no arguments")
    var story = mkCard("s1", 1, "todo", "m1", "S")
    var maps = [null, "x", [], Object.create(null)]
    for (var j = 0; j < maps.length; j++) {
      checkPlan(Runs.dispatchPlan(story, maps[j]), false, "story", "", [],
                "A story is dispatched through its milestone", { id: "m1", title: "" }, "cardMap " + j)
    }
    var bare = Object.create(null)
    bare.m1 = mkCard("m1", 0, "todo", null, "M3 Document runs")
    compare(Runs.dispatchPlan(story, bare).suggest.title, "M3 Document runs", "prototype-less cardMap is read")
  }

  function test_dispatchPlan_proto_ids() {
    var ids = ["__proto__", "constructor", "toString"]
    for (var i = 0; i < ids.length; i++) {
      checkPlan(Runs.dispatchPlan(mkCard("s1", 1, "todo", ids[i], "S"), { m1: mkCard("m1", 0, "todo", null, "M") }),
                false, "story", "", [], "A story is dispatched through its milestone",
                { id: ids[i], title: "" }, "parentId " + ids[i])
    }
  }

  // Review Focus 4.
  function test_dispatchPlan_odd_titles() {
    var story = mkCard("s1", 1, "todo", "m1", "S")
    var bareTitle = mkCard("m1", 0, "todo", null, Object.create(null))
    checkPlan(Runs.dispatchPlan(story, { m1: bareTitle }), false, "story", "", [],
              "A story is dispatched through its milestone", { id: "m1", title: "" }, "unconvertible title")
    compare(Runs.dispatchPlan(story, { m1: mkCard("m1", 0, "todo", null, 7) }).suggest.title, "7", "number title")
    compare(Runs.dispatchPlan(story, { m1: mkCard("m1", 0, "todo", null, null) }).suggest.title, "", "null title")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_runs`
Expected: pytest passes, then under `== tests/core/domain/tst_runs.qml` lines such as `FAIL!  : DomainRuns::test_dispatchPlan_shape() ... TypeError: Property 'dispatchPlan' of object [object Object] is not a function`, and the script exits non-zero. All pre-existing `DomainRuns` tests still pass.

- [ ] **Step 3: Add the import**

`core/domain/runs.js` starts with:

```js
.pragma library

// Run domain model: one `am` orchestrator run, normalised from the CLI's
```

Change the first lines to:

```js
.pragma library
.import "board.js" as Board

// Run domain model: one `am` orchestrator run, normalised from the CLI's
```

- [ ] **Step 4: Write the implementation**

Append to the end of `core/domain/runs.js` (after the closing `}` of `newAlerts`, keeping one blank line, then a second blank line before the banner as the previous sections do):

```js


// ---- Dispatch (S3 1.1) -------------------------------------------------------------------
//
// What the dispatch dialog may start, and the form's starting values. Pure and
// never throwing, like the rest of this file. The one exception to "every input
// comes from am": these read a brd card as Board.indexTree() leaves it
// ({id, title, status, parentId, depth}) and its {id: card} cardMap. Ids are
// compared with === and looked up only as own keys of cardMap, so ids such as
// `__proto__` behave like any absent id.

var _DISPATCH_NO_CARD = "No card to dispatch"
var _DISPATCH_UNKNOWN_LEVEL = "The card's level is unknown"
var _DISPATCH_STORY = "A story is dispatched through its milestone"

// A card id am can take as a target: a non-empty string that cannot be read as a flag.
function _isDispatchId(id) { return typeof id === "string" && id !== "" && id.charAt(0) !== "-" }

// A finite number with no fractional part.
function _isWholeNumber(v) { return _isFiniteNumber(v) && Math.floor(v) === v }

// cardMap[id] when cardMap is an object that owns the string key id and the
// entry is an object, else null. Inherited keys never count.
function _ownCard(cardMap, id) {
  if (!_isObject(cardMap) || typeof id !== "string") return null
  if (!Object.prototype.hasOwnProperty.call(cardMap, id)) return null
  return _isObject(cardMap[id]) ? cardMap[id] : null
}

// A fresh plan the dialog may start.
function _offeredPlan(level, command, flags) {
  return { command: command, flags: flags, level: level, offered: true, reason: "", suggest: null }
}

// A fresh plan the dialog must refuse, with the sentence that says why.
function _refusedPlan(level, reason, suggest) {
  return { command: "", flags: [], level: level, offered: false, reason: reason, suggest: suggest }
}

// What the dispatch dialog may start for card. "board" is the whole board;
// otherwise card is a brd card: depth 0 milestone, 1 story, 2+ subtask. A
// finished card is refused; a story is refused with its milestone as the
// suggestion (title from cardMap when it owns the parent, else ""). Decision
// order and sentences are pinned in docs/superpowers/specs/1-1-runs-js-5eb7ec0c.md.
function dispatchPlan(card, cardMap) {
  if (card === "board") return _offeredPlan("board", "board", ["--board"])
  if (!_isObject(card) || !_isDispatchId(card.id)) return _refusedPlan("", _DISPATCH_NO_CARD, null)
  if (!_isWholeNumber(card.depth) || card.depth < 0) return _refusedPlan("", _DISPATCH_UNKNOWN_LEVEL, null)
  var level = card.depth === 0 ? "milestone" : (card.depth === 1 ? "story" : "subtask")
  if (Board.isFinishedStatus(card.status)) return _refusedPlan(level, "The card is " + card.status, null)
  if (level === "story") {
    var suggest = null
    if (typeof card.parentId === "string" && card.parentId !== "") {
      var parent = _ownCard(cardMap, card.parentId)
      suggest = { id: card.parentId, title: parent !== null ? _textOf(parent.title) : "" }
    }
    return _refusedPlan("story", _DISPATCH_STORY, suggest)
  }
  if (level === "milestone") return _offeredPlan("milestone", "milestone", ["--milestone", card.id])
  return _offeredPlan("subtask", "card", ["--card", card.id])
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_runs`
Expected: pytest green (including `tests/architecture/test_layers.py`, which accepts the `board.js` import, and `test_icon_glyphs.py`), `Totals: N passed, 0 failed` for `tst_runs.qml`, no `TypeError`/`ReferenceError` lines, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "runs.js: dispatchPlan says what the dispatch dialog may start (S3 1.1)"
```

---

### Task 2: `dispatchDefaults(project, card, cardMap)`

**Files:**
- Modify: `core/domain/runs.js` (append after `dispatchPlan`, the end of the file after Task 1)
- Test: `tests/core/domain/tst_runs.qml` (append after `test_dispatchPlan_odd_titles`, before the final `}`)

**Interfaces:**
- Consumes: from Task 1, `_isWholeNumber(v) -> bool` and `_ownCard(cardMap, id) -> object | null`; existing `_isObject`, `_arrayOr`, `_textOf`; the test helper `mkCard(id, depth, status, parentId, title)`.
- Produces: `dispatchDefaults(project, card, cardMap) -> {allowNoVerification: false, base: string, parallelism: number, prefix: string, verify: string[]}`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/domain/tst_runs.qml`, insert after the closing `  }` of `test_dispatchPlan_odd_titles` (still before the file's final `}`):

```qml

  function fullProject() {
    return { defaultBranch: "main",
             settings: { verify: ["uv run pytest", "bash tests/run.sh"], allowNoVerification: true,
                         notifyOnEscalation: true, parallelism: 2 } }
  }

  // Asserts all five dispatchDefaults fields; verify compared as JSON.
  function checkDefaults5(d, base, parallelism, prefix, verifyList, label) {
    compare(Object.keys(d).sort().join(","), "allowNoVerification,base,parallelism,prefix,verify", label + " keys")
    compare(d.allowNoVerification, false, label + " allowNoVerification")
    compare(d.base, base, label + " base")
    compare(d.parallelism, parallelism, label + " parallelism")
    compare(d.prefix, prefix, label + " prefix")
    compare(Array.isArray(d.verify), true, label + " verify is array")
    compare(JSON.stringify(d.verify), JSON.stringify(verifyList), label + " verify")
  }

  function prefixOf(title) {
    return Runs.dispatchDefaults({}, mkCard("m1", 0, "todo", null, title)).prefix
  }

  function test_dispatchDefaults_shape() {
    var project = fullProject()
    var m = mkCard("m1", 0, "todo", null, "M3 Document runs")
    checkDefaults5(Runs.dispatchDefaults(project, m), "main", 2, "m3", ["uv run pytest", "bash tests/run.sh"], "full")
    checkDefaults5(Runs.dispatchDefaults(undefined, undefined, undefined), "", 4, "", [], "garbage")
    var a = Runs.dispatchDefaults(project, m)
    var b = Runs.dispatchDefaults(project, m)
    verify(a !== b, "distinct objects")
    verify(a.verify !== b.verify, "distinct verify arrays")
    verify(a.verify !== project.settings.verify, "verify is not the settings array")
    a.verify.push("rm -rf /")
    a.verify[0] = "x"
    compare(JSON.stringify(project.settings.verify), JSON.stringify(["uv run pytest", "bash tests/run.sh"]), "settings.verify unchanged")
    compare(JSON.stringify(Runs.dispatchDefaults(project, m).verify), JSON.stringify(["uv run pytest", "bash tests/run.sh"]), "next result unchanged")
  }

  function test_dispatchDefaults_base() {
    compare(Runs.dispatchDefaults({ defaultBranch: "main" }).base, "main", "main")
    compare(Runs.dispatchDefaults({ defaultBranch: "  trunk \n" }).base, "trunk", "trimmed")
    var bad = [undefined, null, 5, {}]
    for (var i = 0; i < bad.length; i++) {
      compare(Runs.dispatchDefaults({ defaultBranch: bad[i] }).base, "", "defaultBranch " + i)
    }
    compare(Runs.dispatchDefaults({}).base, "", "defaultBranch missing")
    var projects = [undefined, null, 0, "main", [], Object.create(null)]
    for (var j = 0; j < projects.length; j++) {
      compare(Runs.dispatchDefaults(projects[j]).base, "", "project " + j)
    }
  }

  function test_dispatchDefaults_prefix_stem() {
    var cases = [
      ["M3 Document runs", "m3"],
      ["M3: Document", "m3"],
      ["s12 Polish", "s12"],
      ["am run monitor (read-only)", "am-run-monitor"],
      ["Dispatching am runs from the panel", "dispatching-am-runs"],
      ["Milestone 3", "milestone-3"],
      ["Internationalization localization globalization", "internationalization-loc"],
      ["-- ** --", ""]
    ]
    for (var i = 0; i < cases.length; i++) {
      compare(prefixOf(cases[i][0]), cases[i][1], "'" + cases[i][0] + "'")
    }
    compare(prefixOf(undefined), "", "title missing")
    compare(prefixOf(null), "", "title null")
    compare(prefixOf(5), "5", "title 5")
    compare(Runs.dispatchDefaults({}, { id: "m1", depth: 0 }).prefix, "", "no title key")
  }

  // Review Focus 3 and 4.
  function test_dispatchDefaults_prefix_stem_edges() {
    compare(prefixOf("abcdefghijklmnopqrstuvw xyz"), "abcdefghijklmnopqrstuvw", "cut after a hyphen drops the hyphen")
    compare(prefixOf("Caf\u00e9 d\u00e9j\u00e0 vu"), "caf-dj-vu", "non-ASCII letters are dropped")
    compare(prefixOf("   "), "", "blank title")
    compare(prefixOf("M3\tDocument\nruns"), "m3", "any whitespace splits")
    compare(prefixOf("3M Polish"), "3m-polish", "digits first is not a stem")
    compare(prefixOf(Object.create(null)), "", "unconvertible title")
  }

  function test_dispatchDefaults_prefix_ancestor() {
    var m = mkCard("m1", 0, "todo", null, "M3 Document runs")
    var s = mkCard("s1", 1, "todo", "m1", "Story")
    var c = mkCard("c1", 2, "todo", "s1", "Subtask")
    var map = { m1: m, s1: s, c1: c }
    compare(Runs.dispatchDefaults({}, s, map).prefix, "m3", "story")
    compare(Runs.dispatchDefaults({}, c, map).prefix, "m3", "subtask")
    compare(Runs.dispatchDefaults({}, s).prefix, "", "story without cardMap")
    compare(Runs.dispatchDefaults({}, c).prefix, "", "subtask without cardMap")
    compare(Runs.dispatchDefaults({}, c, { s1: s, c1: c }).prefix, "", "broken chain")
    var a = mkCard("a", 1, "todo", "b", "A")
    var b = mkCard("b", 1, "todo", "a", "B")
    compare(Runs.dispatchDefaults({}, a, { a: a, b: b }).prefix, "", "two-card cycle")
    compare(Runs.dispatchDefaults({}, "board", map).prefix, "", "board")
    compare(Runs.dispatchDefaults({}, mkCard("c1", 2, "done", "s1", "Subtask"), map).prefix, "m3", "own status ignored")
    compare(Runs.dispatchDefaults({}, mkCard("m1", 0, "archived", null, "M3 Document runs")).prefix, "m3", "finished milestone still gives a prefix")
  }

  // Review Focus 2 and 5.
  function test_dispatchDefaults_prefix_ancestor_edges() {
    var loop = mkCard("x", 1, "todo", "x", "M3 Self")
    compare(Runs.dispatchDefaults({}, loop, { x: loop }).prefix, "", "self cycle")
    var stray = mkCard("m1", 0, "todo", "zz", "M3 Document runs")
    compare(Runs.dispatchDefaults({}, stray).prefix, "m3", "depth 0 with a stray parentId is its own milestone")
    var top = mkCard("t", 1, "todo", null, "S7 Top")
    var child = mkCard("c", 2, "todo", "t", "C")
    compare(Runs.dispatchDefaults({}, child, { t: top, c: child }).prefix, "s7", "walk ends at the parentless card whatever its depth")
    compare(Runs.dispatchDefaults({}, mkCard("o", undefined, "todo", null, "S8 Orphan"), {}).prefix, "s8", "no parentId and no depth: own milestone")
    compare(Runs.dispatchDefaults({}, mkCard("o", 1, "todo", "", "S9 Orphan"), {}).prefix, "s9", "empty parentId ends the walk")
    compare(Runs.dispatchDefaults({}, mkCard("c", 2, "todo", "__proto__", "C"), {}).prefix, "", "__proto__ parent is absent")
    compare(Runs.dispatchDefaults({}, mkCard("c", 2, "todo", "toString", "C"), {}).prefix, "", "toString parent is absent")
    compare(Runs.dispatchDefaults({}, mkCard("c", 2, "todo", "m1", "C"), { m1: "M3" }).prefix, "", "non-object entry")
    compare(Runs.dispatchDefaults({}, mkCard("c", 2, "todo", 5, "C"), { "5": mkCard("5", 0, "todo", null, "M5 Five") }).prefix,
            "", "a non-string parentId is a missing link")
  }

  function test_dispatchDefaults_verify() {
    var project = { settings: { verify: ["uv run pytest", "  ", "", 5, null, " make test "] } }
    compare(JSON.stringify(Runs.dispatchDefaults(project).verify), JSON.stringify(["uv run pytest", " make test "]), "filtered, verbatim, in order")
    var bad = [undefined, "x", {}]
    for (var i = 0; i < bad.length; i++) {
      compare(JSON.stringify(Runs.dispatchDefaults({ settings: { verify: bad[i] } }).verify), "[]", "verify " + i)
    }
    compare(JSON.stringify(Runs.dispatchDefaults({ settings: {} }).verify), "[]", "verify missing")
    compare(JSON.stringify(Runs.dispatchDefaults({ settings: "x" }).verify), "[]", "settings garbage")
    compare(JSON.stringify(Runs.dispatchDefaults({}).verify), "[]", "no settings")
  }

  function test_dispatchDefaults_allow_no_verification() {
    compare(Runs.dispatchDefaults({ settings: { allowNoVerification: true } }).allowNoVerification, false, "stored true")
    compare(Runs.dispatchDefaults({ settings: {} }).allowNoVerification, false, "absent")
    compare(Runs.dispatchDefaults(null).allowNoVerification, false, "garbage project")
  }

  function test_dispatchDefaults_parallelism() {
    compare(Runs.dispatchDefaults({ settings: { parallelism: 2 } }).parallelism, 2, "2")
    compare(Runs.dispatchDefaults({ settings: { parallelism: 1 } }).parallelism, 1, "1")
    compare(Runs.dispatchDefaults({ settings: { parallelism: 64 } }).parallelism, 64, "no upper cap")
    var bad = [undefined, 0, -3, 2.5, "3", NaN, Infinity, null]
    for (var i = 0; i < bad.length; i++) {
      compare(Runs.dispatchDefaults({ settings: { parallelism: bad[i] } }).parallelism, 4, "parallelism " + bad[i])
    }
    compare(Runs.dispatchDefaults({ settings: {} }).parallelism, 4, "missing")
  }

  function test_dispatchDefaults_garbage() {
    var values = [undefined, null, 0, "x", [], Object.create(null)]
    for (var p = 0; p < values.length; p++) {
      for (var c = 0; c < values.length; c++) {
        for (var m = 0; m < values.length; m++) {
          checkDefaults5(Runs.dispatchDefaults(values[p], values[c], values[m]), "", 4, "", [], "p" + p + " c" + c + " m" + m)
        }
      }
    }
    checkDefaults5(Runs.dispatchDefaults(), "", 4, "", [], "no arguments")
  }

  // Review Focus 1.
  function test_dispatch_inputs_unchanged() {
    var project = fullProject()
    var m = mkCard("m1", 0, "todo", null, "M3 Document runs")
    var s = mkCard("s1", 1, "todo", "m1", "Story")
    var c = mkCard("c1", 2, "todo", "s1", "Subtask")
    var map = { m1: m, s1: s, c1: c }
    var before = JSON.stringify([project, map])
    Runs.dispatchDefaults(project, c, map)
    Runs.dispatchDefaults(project, s, map)
    Runs.dispatchPlan(s, map)
    Runs.dispatchPlan(c, map)
    compare(JSON.stringify([project, map]), before, "project and cardMap unchanged")
    compare(Object.keys(c).sort().join(","), "depth,id,parentId,status,title", "no key added to the card")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_runs`
Expected: the Task 1 `test_dispatchPlan_*` tests pass; the new tests report `FAIL!  : DomainRuns::test_dispatchDefaults_shape() ... TypeError: Property 'dispatchDefaults' of object [object Object] is not a function` (and likewise for the other `test_dispatchDefaults_*` tests and `test_dispatch_inputs_unchanged`); exit code non-zero.

- [ ] **Step 3: Write the implementation**

Append to the end of `core/domain/runs.js`, after the closing `}` of `dispatchPlan`:

```js

// The milestone card whose title names the branch prefix: card itself at depth
// 0, else the first card with no parentId (null, undefined or "") reached by
// following parentId through cardMap's own keys. The walk trusts parentId, not
// depth. A missing link, a non-string parentId, a non-object entry or a cycle
// (an id seen twice) gives null, as does no cardMap.
function _milestoneOf(card, cardMap) {
  if (!_isObject(card)) return null
  if (card.depth === 0) return card
  if (!_isObject(cardMap)) return null
  var seen = []
  var current = card
  while (true) {
    var parentId = current.parentId
    if (parentId === null || parentId === undefined || parentId === "") return current
    if (seen.indexOf(parentId) >= 0) return null
    seen.push(parentId)
    current = _ownCard(cardMap, parentId)
    if (current === null) return null
  }
}

// The branch-prefix stem of a milestone title: lower-case [a-z0-9] tokens; a
// first token like "m3" (letters then digits) is the stem, else the first three
// tokens joined by "-", cut to 24 characters, without a trailing "-".
function _stemOf(title) {
  var words = _textOf(title).split(/\s+/)
  var tokens = []
  for (var i = 0; i < words.length; i++) {
    var token = words[i].toLowerCase().replace(/[^a-z0-9]/g, "")
    if (token !== "") tokens.push(token)
  }
  if (tokens.length === 0) return ""
  if (/^[a-z]+[0-9]+$/.test(tokens[0])) return tokens[0]
  return tokens.slice(0, 3).join("-").slice(0, 24).replace(/-+$/, "")
}

// The dispatch form's starting values. project is {defaultBranch, settings}
// with settings as get-run-settings returns it; any part may be missing. base
// is the trimmed default branch (no fallback: the caller resolves it), prefix
// the stem of the card's milestone title, verify the stored non-blank commands
// verbatim, parallelism the stored whole number >= 1 else 4. The opt-out from
// verification is never pre-ticked.
function dispatchDefaults(project, card, cardMap) {
  var p = _isObject(project) ? project : {}
  var settings = _isObject(p.settings) ? p.settings : {}
  var milestone = _milestoneOf(card, cardMap)
  var stored = _arrayOr(settings.verify)
  var verify = []
  for (var i = 0; i < stored.length; i++) {
    if (typeof stored[i] === "string" && stored[i].trim() !== "") verify.push(stored[i])
  }
  var parallelism = settings.parallelism
  return {
    allowNoVerification: false,
    base: typeof p.defaultBranch === "string" ? _textOf(p.defaultBranch) : "",
    parallelism: _isWholeNumber(parallelism) && parallelism >= 1 ? parallelism : 4,
    prefix: milestone !== null ? _stemOf(milestone.title) : "",
    verify: verify
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_runs`
Expected: `Totals: N passed, 0 failed` for `tst_runs.qml`, no `TypeError`/`ReferenceError` lines, exit code 0.

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest green (including `tests/architecture/test_layers.py` and `tests/architecture/test_icon_glyphs.py`), every `== tests/...tst_*.qml` block shows `Totals: ... 0 failed`, no `TypeError`/`ReferenceError`/`is not a function` lines, exit code 0. In particular the store and UI QML tests that import `runs.js` (e.g. `RunStore`) still load with the new `board.js` import.

- [ ] **Step 6: Check the touched-file scope**

Run: `git status --porcelain`
Expected: only `core/domain/runs.js` and `tests/core/domain/tst_runs.qml` modified (the spec/plan docs may also appear untracked or modified; nothing else).

Run: `git diff -U0 core/domain/runs.js | grep '^-' | grep -v '^---'`
Expected: no output (no existing line of runs.js removed or changed).

- [ ] **Step 7: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "runs.js: dispatchDefaults gives the dispatch form's starting values (S3 1.1)"
```

---

## Self-Review

**Spec coverage.**
- Import `board.js` / reuse `isFinishedStatus`: Task 1 Step 3-4.
- `dispatchPlan` decision steps 1-8 and every reason sentence: Task 1 Step 4; tests `board`, `bad_id`, `unknown_level`, `finished`, `story`, `milestone`, `subtask`, `garbage`, `proto_ids`, `shape`.
- `dispatchDefaults` base / prefix (milestone resolution, walk, cycles, stem rule and all its examples) / verify / allowNoVerification / parallelism: Task 2 Step 3; tests for each field, plus `garbage` (all 216 combinations of the six garbage values) and `shape`.
- Freshness and non-mutation: `test_dispatchPlan_shape`, `test_dispatchPlan_story`, `test_dispatchDefaults_shape`, `test_dispatch_inputs_unchanged`.
- Own-key lookups for `__proto__`/`constructor`/`toString`: `_ownCard`, `test_dispatchPlan_proto_ids`, `test_dispatchDefaults_prefix_ancestor_edges`.
- ASCII-only and layer rules: Task 2 Step 5 runs the architecture tests. (The test file's `\u00e9` escapes are ASCII source text.)
- Existing code unchanged: Task 2 Step 6.
- Every test in the spec's table exists under the same name. Additional tests: `test_dispatchPlan_odd_titles`, `test_dispatchDefaults_prefix_stem_edges`, `test_dispatchDefaults_prefix_ancestor_edges`, `test_dispatch_inputs_unchanged` (Review Focus).

**Decisions pinned beyond the spec's text.** A non-string `parentId` in the `dispatchDefaults` walk is a missing link (the spec looks ids up only through `hasOwnProperty`, which would otherwise coerce `5` to `"5"`); pinned in `test_dispatchDefaults_prefix_ancestor_edges`. For `dispatchPlan`, a story's non-string `parentId` (e.g. `5`) gives `suggest` null, as the spec says. A depth of `-0` counts as 0 (milestone), since `-0 === 0`.

**Placeholder scan.** No TBD/TODO; every code step carries complete code.

**Type consistency.** `_isWholeNumber` and `_ownCard` are defined in Task 1 and used with the same signatures in Task 2; `mkCard(id, depth, status, parentId, title)` is defined in Task 1 and reused in Task 2; `checkDefaults5` is named to avoid colliding with the existing `checkDefaults` helper in `tst_runs.qml`.
<!-- task-pipeline: validated -->
