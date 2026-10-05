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
