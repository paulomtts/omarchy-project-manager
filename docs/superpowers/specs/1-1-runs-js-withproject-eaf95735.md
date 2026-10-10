# 1.1 runs.js: `withProject` and `filterByProject` — design

Card: `eaf95735` (subtask of story `df7e47e9`). Parent design:
`docs/superpowers/specs/2026-10-05-runs-all-projects-design.md` (cited below as **S6** with line
numbers).

## Purpose

The global Runs destination lists runs of every registered project, so a run has to carry which
registered project it belongs to (root and display name), and the list has to be narrowed to one
project for the project filter. This card adds the two pure `runs.js` functions that do that, and
pins by test that `Runs.attention` already works over a list spanning projects (S6 lines 122-126).

## Inherited constraints

- `core/domain/runs.js` gains `withProject(run, root, name)` (root and name resolved by the caller
  from the row's `project.repo_dir` and the registry) and `filterByProject(runs, root)`
  (S6 §"Architecture", lines 122-124).
- There is no `attentionAcross`: `Runs.attention(runs)` already works over a list that spans
  projects (S6 lines 125-126; card).
- The run model reads the real `am status` shape; `Runs.normalizeRun` of a real payload must give a
  populated tree, else stop and escalate (S6 §"Preconditions", lines 13-16; card). Checked during
  exploration: `tests/fixtures/am/status-{started,done,escalated}.json` (am 0.2.0) normalise to
  populated trees and are already exercised by `fixtureRuns()` (`tst_runs.qml:28-31`). No escalation.
- Fixtures are recorded from the installed `am`, never hand-shaped (S6 line 17; card). The existing
  recordings in `tests/fixtures/am/` are used; a synthetic edge case is marked `// synthetic:` as
  the rest of `tst_runs.qml` does.
- Layering per `docs/architecture.md` (S6 line 111): `runs.js` stays a pure `.pragma library`
  module, no I/O; `tests/architecture` must pass.
- Doc comments state the contract only, no narrative (card).
- Verification: `bash tests/run.sh` green; TDD, tests first (card).

## Observable behavior

### `Runs.withProject(run, root, name)`

1. **Non-run input is returned as is.** When `run` is not a plain object (`undefined`, `null`, a
   string, number, boolean, or an array), the function returns `run` itself, unchanged.
2. **Copy with `project` replaced.** For a plain-object `run`, the result is a new object that is a
   deep, JSON-like copy of `run` (arrays and plain objects copied recursively; an own `__proto__`
   key dropped, the same rule as `normalizeRun`'s copies) in which `project` is replaced by a new
   object with exactly the keys `root` and `name`. Every other key of `run` is present with a
   JSON-equal value. Whatever `run.project` held before (the `normalizeRun` shape `{id, repo_dir}`,
   `null`, garbage, or absent) is not consulted and does not survive.
3. **Never mutates, never shares.** The input `run` is JSON-equal before and after the call;
   mutating the result (including nested `tree`, `rows`, `lease`, `requests`) never changes the
   input, and `result !== run`, `result.tree !== run.tree`.
4. **`root`.** When `root` is a string, `project.root` is `root` with every trailing `/` removed;
   a root made only of slashes (`"/"`, `"//"`) becomes `"/"`. No other normalisation (no trimming,
   no case change, no `.`/`..`/`~` resolution). When `root` is not a string, `project.root` is `""`.
5. **`name`.** When `name` is a string that is non-empty after trimming, `project.name` is that
   string trimmed. Otherwise (missing, `null`, blank, not a string) it is the last `/`-separated
   segment of `project.root`; for `project.root` `"/"` it is `"/"`, and for `""` it is `""`.
6. **Never throws** for any combination of arguments, including a prototype-less `run`
   (`Object.create(null)`).

### `Runs.filterByProject(runs, root)`

7. **Non-array `runs`** gives a new empty array.
8. **No root keeps all.** When `root` is `null`, `undefined` or `""`, the result is a new array
   holding every entry of `runs`, the same values in input order (`result !== runs`).
9. **A root keeps that project's runs.** When `root` is a non-empty string, the result is a new
   array of the entries of `runs` (same objects, input order) that are plain objects whose
   `project` is a plain object with a string `root` equal to `root` — both sides compared after
   the trailing-slash rule of rule 4. Comparison is exact otherwise (case-sensitive, no path
   resolution).
10. **No project never matches.** With a non-empty root, an entry with no `project`, a `null` or
    non-object `project`, a `project` without a string `root` (in particular the plain
    `normalizeRun` shape `{id, repo_dir}`), or a non-object entry, is never kept.
11. **Other root types match nothing.** A `root` that is neither a string nor `null`/`undefined`
    (number, boolean, object, array) gives a new empty array.
12. **Pure:** the input array and its entries are unchanged; never throws.

### `Runs.attention` across projects (unchanged code)

13. `Runs.attention(list)` over runs of two projects returns every run that needs attention from
    both projects, the same objects in input order. No code change; a test pins it.

## Doc comments (contract)

Above each new function, contract only: inputs, the `{root, name}` shape, the trailing-slash and
name-fallback rules, "returns a copy / same objects, input order", "never mutates, never throws".

## Tests

All in `tests/core/domain/tst_runs.qml` (TestCase `DomainRuns`), in a new section
`// ---- S6 1.1: project ----`. Tier: **QML unit (qmltestrunner)** for every test — both functions
are pure `.pragma library` functions with no I/O, and this file is where the `runs.js` contract is
tested; no store, UI or Python layer is involved. Happy paths use `fixtureRuns()` /
`amRun(name)` over the recorded fixtures (`project.repo_dir` is
`/home/user/Code/omarchy-project-manager` in all of them); edge cases are marked `// synthetic:`.

| Test | Proves | Input |
|---|---|---|
| `test_with_project_from_fixture` | rules 2, 4, 5: each fixture run, given `run.project.repo_dir` as root and `"omarchy-project-manager"` as name, gets `project` JSON-equal `{root: "/home/user/Code/omarchy-project-manager", name: "omarchy-project-manager"}` with exactly keys `name,root`; every other key JSON-equal to the input's | `fixtureRuns()` |
| `test_with_project_is_a_copy` | rule 3: input JSON unchanged after the call; `result !== run`, `result.tree !== run.tree`; mutating `result.tree.stories[0]`, `result.rows`, `result.lease` leaves the input unchanged | `status-started.json` |
| `test_with_project_trailing_slash` | rule 4: `"/a/b/"`, `"/a/b///"` → `"/a/b"`; `"/"`, `"//"` → `"/"`; `""` → `""`; `" /a/b "` kept as given | `// synthetic:` roots on a fixture run |
| `test_with_project_name_fallback` | rule 5: name missing / `null` / `""` / `"   "` / `42` → last segment (`"/a/proj/"` → `"proj"`); `"/"` → `"/"`; `""` → `""`; `"  My Proj  "` → `"My Proj"` | `// synthetic:` |
| `test_with_project_garbage` | rules 1, 4, 6: `undefined`, `null`, `"x"`, `5`, `true`, `[]`, `[run]` returned as is (`===`); non-string roots (`undefined`, `null`, `5`, `{}`, `[]`) → `root: ""`; `Object.create(null)` run and `{}` run do not throw and get `project` `{root, name}`; a run whose `project` is garbage gets the new shape | `// synthetic:` |
| `test_filter_by_project` | rules 9, 12: two fixture runs re-projected to `/p/one` and `/p/two` plus two more on `/p/one`; filtering by `/p/one` keeps those three, same objects, input order; input array unchanged | `fixtureRuns()` + `withProject` |
| `test_filter_by_project_no_root_keeps_all` | rule 8: `null`, `undefined`, `""` → new array, same entries (garbage entries included), `result !== runs` | `fixtureRuns()` + `// synthetic:` entries |
| `test_filter_by_project_trailing_slash` | rule 9: root `"/p/one/"` matches project root `"/p/one"`, and a run whose `project.root` is `"/p/one/"` (set by hand, `// synthetic:`) matches root `"/p/one"`; `"/P/one"` and `"/p/on"` match nothing | `withProject` + `// synthetic:` |
| `test_filter_by_project_without_project` | rule 10: plain `normalizeRun` output (`project` `{id, repo_dir}`), `project: null`, `project` missing, `project: "x"`, `project: {root: 5}`, `null`/`"x"` entries never kept for root `/home/user/Code/omarchy-project-manager` | `fixtureRuns()` + `// synthetic:` |
| `test_filter_by_project_garbage` | rules 7, 11, 12: `runs` `undefined`/`null`/`"x"`/`{}`/`{length: 1, 0: run}` → `[]`; root `5`/`true`/`{}`/`[]` → `[]`; never throws | `// synthetic:` |
| `test_attention_across_projects` | rule 13: escalated fixture run on project A, started fixture run with `lease.live` set false (`// synthetic:`, dead) on project B, the running started run and the done run on either → `attention` returns the escalated and the dead run, same objects, input order | `fixtureRuns()` + `withProject` |

Existing tests stay green unchanged, notably the `normalizeRun` `project` tests
(`tst_runs.qml:402-440`, exact keys `id,repo_dir`) and `test_attention` (`tst_runs.qml:1290`).

## Error paths

None surface: both functions never throw. Defaults: non-run input returned as is (rule 1),
`root` `""` for a non-string root (rule 4), name from the root's last segment (rule 5), `[]` for
non-array runs or a non-string root (rules 7, 11).

## Out of scope

- `groupByProject(runs)` and display-order flattening (S6 line 124; sibling subtask).
- Any change to `normalizeRun` behavior or to its `project` `{id, repo_dir}` shape and tests.
- `RunStore.qml` (`projectRoots`, registry filtering, `runsByProject`), `App.qml`, backend helpers,
  UI chips/headers/indicators (S6 lines 127-142; other stories).
- An `attentionAcross` function (S6 lines 125-126).
- Recording new fixtures: the existing am 0.2.0 recordings cover this card.

## Hand-off to the planner

One task is enough: one code file (`core/domain/runs.js`: two exported functions after
`attention`, plus a private top-level deep-copy helper with `normalizeRun`'s copy rule, and a
private trailing-slash helper shared by both functions) and one test file
(`tests/core/domain/tst_runs.qml`). Write the tests first, run `bash tests/run.sh tst_runs` to see
them fail on the missing functions, implement, then run the full `bash tests/run.sh`. Plan in the
writing-plans format of the brief.
