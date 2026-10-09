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

---

# runs.js `withProject` and `filterByProject` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Runs.withProject(run, root, name)` and `Runs.filterByProject(runs, root)` to `core/domain/runs.js`, and pin by test that `Runs.attention` already works over runs of several projects.

**Architecture:** Two pure functions in the `.pragma library` module `core/domain/runs.js`, placed right after `attention`, plus two private top-level helpers: `_copyOf` (the JSON-like deep copy `normalizeRun` already uses, hoisted out of it so both share one copy rule) and `_trimSlashes` (the trailing-slash rule shared by both new functions). No I/O, no store or UI change. Tests live in `tests/core/domain/tst_runs.qml` (TestCase `DomainRuns`), run by `qmltestrunner` through `tests/run.sh`.

**Tech Stack:** QML JavaScript (`.pragma library`, ES5 style: `var`/`function`, no `let`/`const`/arrows), Qt Quick Test (`qmltestrunner`), `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/1-1-runs-js-withproject-eaf95735.md` (reproduced in full above this plan).

## Global Constraints

- `core/domain/runs.js` stays a pure `.pragma library` module, no I/O; `tests/architecture` must pass.
- Style: `var`/`function` only, `_`-prefixed private helpers, one contract-only comment block above each function (inputs, the `{root, name}` shape, trailing-slash and name-fallback rules, "returns a copy / same objects, input order", "never mutates, never throws"). No narrative comments.
- No `attentionAcross` function; `Runs.attention(runs)` is not changed.
- `normalizeRun` behavior and its `project` `{id, repo_dir}` shape and tests do not change.
- Fixtures are the existing recordings in `tests/fixtures/am/` (am 0.2.0), never hand-shaped; every hand-made edge case is marked `// synthetic:`.
- Verification: `bash tests/run.sh` green. TDD: tests first.
- Out of scope: `groupByProject`, `RunStore.qml`, `App.qml`, backend helpers, UI.

## Review Focus

1. **Re-projecting an already projected run** (a store calls `withProject` again when the registry renames a project): the new `{root, name}` wins wholesale and the earlier result is untouched. Pinned in `test_with_project_is_a_copy`.
2. **An own `__proto__` key in am's JSON** (`JSON.parse` creates it as an own key): it is dropped from the copy at every depth, the copy's prototype is `Object.prototype`, and nothing behind it is read. Pinned in `test_with_project_garbage`.
3. **A project registered at the filesystem root `/`** (or as `//`): `withProject` gives root and name `"/"`, and `filterByProject(runs, "/")` keeps exactly those runs, not every run. Pinned in `test_filter_by_project_trailing_slash`.
4. **A display name that itself contains `/`** (e.g. `"team/app"`): a given name is kept verbatim after trimming, never cut to its last segment. Pinned in `test_with_project_name_fallback`.
5. **A relative or bare root** (`"proj"`, no slash at all): kept as given, and the name fallback is the whole string. Pinned in `test_with_project_name_fallback`.

---

### Task 1: `withProject`, `filterByProject`, and attention across projects

**Files:**
- Modify: `core/domain/runs.js` — hoist `copyOf` out of `normalizeRun` (lines 54-67, call sites at lines 117 and 121) into a top-level `_copyOf`; add `_trimSlashes`, `withProject`, `filterByProject` right after `attention` (which ends at line 344).
- Test: `tests/core/domain/tst_runs.qml` — new section appended at the end of the `TestCase`, after `test_dispatchLabel_titles_and_status` and before the file's final closing `}`.

**Interfaces:**
- Consumes (already in `core/domain/runs.js`): `_isObject(v)` (line 186: non-null, `typeof "object"`, not an array — true for `Object.create(null)`), `_arrayOr(v)` (line 187: `v` if an array, else a new `[]`), `normalizeRun(raw)`, `runState(run)`, `attention(runs)`. In the test file: `amRun(name)` (line 15), `fixtureRuns()` (line 28: normalised `[started, done, escalated, done-integrate]`), `hasOwn(o, key)` (line 392).
- Produces:
  - `Runs.withProject(run, root, name)` → `run` itself when `run` is not a plain object; else a deep copy of `run` whose `project` is `{ root: string, name: string }` (exactly those two keys).
  - `Runs.filterByProject(runs, root)` → a new array: all entries for `root` `null`/`undefined`/`""`; the entries whose `project.root` matches (trailing slashes ignored) for a non-empty string `root`; `[]` otherwise.
  - Private: `_copyOf(v)`, `_trimSlashes(path)` → string.

Fixture facts the tests rely on (checked): every recorded run's `project.repo_dir` is `/home/user/Code/omarchy-project-manager`; `fixtureRuns()[0]` (started) has a live lease (`runState` `running`), 4 stories, 8 real subtasks, 44 rows and an empty `requests`; `[1]` is `done`, `[2]` is `escalated`, `[3]` is `done`.

- [ ] **Step 1: Write the failing tests**

Append this section to `tests/core/domain/tst_runs.qml`, inside the `TestCase`, directly after the closing `}` of `function test_dispatchLabel_titles_and_status()` and before the file's last line `}`:

```qml

  // ---- S6 1.1: the run's registered project -----------------------------------------------

  function test_with_project_from_fixture() {
    var runs = fixtureRuns()
    for (var i = 0; i < runs.length; i++) {
      var run = runs[i]
      var label = "fixture " + i
      compare(run.project.repo_dir, "/home/user/Code/omarchy-project-manager", label + " repo_dir")
      var out = Runs.withProject(run, run.project.repo_dir, "omarchy-project-manager")
      compare(Object.keys(out.project).sort().join(","), "name,root", label + " project keys")
      compare(out.project.root, "/home/user/Code/omarchy-project-manager", label + " root")
      compare(out.project.name, "omarchy-project-manager", label + " name")
      compare(Object.keys(out).sort().join(","), Object.keys(run).sort().join(","), label + " keys")
      var keys = Object.keys(run)
      for (var k = 0; k < keys.length; k++) {
        if (keys[k] === "project") continue
        compare(JSON.stringify(out[keys[k]]), JSON.stringify(run[keys[k]]), label + " " + keys[k])
      }
    }
  }

  function test_with_project_is_a_copy() {
    var run = Runs.normalizeRun(amRun("status-started.json"))
    var before = JSON.stringify(run)
    var out = Runs.withProject(run, "/p/one", "One")
    compare(JSON.stringify(run), before, "input unchanged by the call")
    verify(out !== run, "a new run")
    verify(out.tree !== run.tree, "a new tree")
    verify(out.tree.stories !== run.tree.stories, "new stories")
    verify(out.tree.stories[0] !== run.tree.stories[0], "a new story")
    verify(out.tree.subtasks[0] !== run.tree.subtasks[0], "a new subtask")
    verify(out.rows !== run.rows, "new rows")
    verify(out.lease !== run.lease, "a new lease")
    verify(out.requests !== run.requests, "new requests")

    out.tree.stories[0].title = "changed"
    out.tree.stories[0].subtasks.push("x")
    out.tree.subtasks[0].phases = []
    out.rows[0].status = "changed"
    out.rows.push({})
    out.lease.live = false
    out.requests.push({ command: "pause" })
    out.project.root = "/elsewhere"
    compare(JSON.stringify(run), before, "input unchanged by mutating the result")
    compare(run.project.repo_dir, "/home/user/Code/omarchy-project-manager", "input project kept")

    // re-projecting a projected run: the new project wins, the first result is untouched
    var again = Runs.withProject(out, "/p/two/", null)
    compare(Object.keys(again.project).sort().join(","), "name,root", "re-projected keys")
    compare(again.project.root, "/p/two", "re-projected root")
    compare(again.project.name, "two", "re-projected name")
    compare(out.project.root, "/elsewhere", "first result unchanged")
  }

  function test_with_project_trailing_slash() {
    var run = Runs.normalizeRun(amRun("status-done.json"))
    // synthetic: roots with trailing slashes, only slashes, empty, padded and unresolved
    var cases = [["/a/b/", "/a/b"], ["/a/b///", "/a/b"], ["/a/b", "/a/b"], ["/", "/"], ["//", "/"], ["", ""],
                 [" /a/b ", " /a/b "], ["/a/b/ ", "/a/b/ "], ["/A/./b/../c/", "/A/./b/../c"], ["~/x/", "~/x"]]
    for (var i = 0; i < cases.length; i++) {
      compare(Runs.withProject(run, cases[i][0], "N").project.root, cases[i][1], JSON.stringify(cases[i][0]))
    }
  }

  function test_with_project_name_fallback() {
    var run = Runs.normalizeRun(amRun("status-done.json"))
    // synthetic: names that are missing, null, blank or not a string
    var blanks = [["undefined", undefined], ["null", null], ["empty", ""], ["spaces", "   "], ["tab", "\t"],
                  ["number", 42], ["object", {}], ["array", ["x"]], ["boolean", true]]
    for (var i = 0; i < blanks.length; i++) {
      compare(Runs.withProject(run, "/a/proj/", blanks[i][1]).project.name, "proj", blanks[i][0])
    }
    compare(Runs.withProject(run, "/a/proj/").project.name, "proj", "name argument omitted")
    compare(Runs.withProject(run, "/", null).project.name, "/", "root /")
    compare(Runs.withProject(run, "//", "").project.name, "/", "root //")
    compare(Runs.withProject(run, "", null).project.name, "", "root empty")
    compare(Runs.withProject(run, 5, null).project.name, "", "root not a string")
    compare(Runs.withProject(run, "proj", null).project.name, "proj", "a relative root is its own name")
    compare(Runs.withProject(run, "proj", null).project.root, "proj", "a relative root is kept")
    compare(Runs.withProject(run, "/home/user/Code/omarchy-project-manager", null).project.name,
            "omarchy-project-manager", "the fixture root")
    compare(Runs.withProject(run, "/a/proj", "  My Proj  ").project.name, "My Proj", "a given name is trimmed")
    compare(Runs.withProject(run, "/a/proj", "team/app").project.name, "team/app", "a given name is kept verbatim")
    compare(Runs.withProject(run, "/a/proj", "Proj").project.name, "Proj", "case kept")
  }

  function test_with_project_garbage() {
    var run = Runs.normalizeRun(amRun("status-done.json"))
    // synthetic: values that are not a run are returned as is
    var notRuns = [undefined, null, "x", 5, true, [], [run]]
    for (var i = 0; i < notRuns.length; i++) {
      verify(Runs.withProject(notRuns[i], "/p", "P") === notRuns[i], "not a run " + i)
    }

    // synthetic: roots that are not a string
    var badRoots = [undefined, null, 5, true, {}, [], ["/p"]]
    for (var j = 0; j < badRoots.length; j++) {
      var p = Runs.withProject(run, badRoots[j], "P").project
      compare(p.root, "", "root " + j)
      compare(p.name, "P", "name with root " + j)
    }

    // synthetic: a prototype-less run and an empty run
    var bare = Object.create(null)
    bare.id = "b1"
    var fromBare = Runs.withProject(bare, "/p/x", null)
    compare(fromBare.id, "b1", "prototype-less id")
    compare(fromBare.project.root, "/p/x", "prototype-less root")
    compare(fromBare.project.name, "x", "prototype-less name")
    verify(Object.getPrototypeOf(fromBare) === Object.prototype, "the copy has Object.prototype")
    var fromEmpty = Runs.withProject({}, "/p/y", "Y")
    compare(Object.keys(fromEmpty).join(","), "project", "an empty run gains only project")
    compare(fromEmpty.project.root, "/p/y", "empty run root")
    compare(fromEmpty.project.name, "Y", "empty run name")

    // synthetic: whatever project the run held is replaced
    var olds = [null, "x", 5, [], { id: 1, repo_dir: "/old" }, { root: "/old", name: "Old", extra: 1 }]
    for (var k = 0; k < olds.length; k++) {
      var g = Runs.withProject({ id: "g", project: olds[k] }, "/new", null).project
      compare(Object.keys(g).sort().join(","), "name,root", "old project " + k + " keys")
      compare(g.root, "/new", "old project " + k + " root")
      compare(g.name, "new", "old project " + k + " name")
    }
    var missing = Runs.withProject({ id: "m" }, "/new", "New")
    compare(missing.project.root, "/new", "no project before")

    // synthetic: own __proto__ keys, which no capture contains
    var poisoned = JSON.parse('{"id": "p1", "__proto__": {"polluted": true}, "tree": {"__proto__": {"x": 1}, "stories": []}}')
    verify(hasOwn(poisoned, "__proto__"), "the input carries an own __proto__ key")
    var clean = Runs.withProject(poisoned, "/p", "P")
    compare(hasOwn(clean, "__proto__"), false, "top-level __proto__ dropped")
    compare(hasOwn(clean.tree, "__proto__"), false, "nested __proto__ dropped")
    verify(Object.getPrototypeOf(clean) === Object.prototype, "top-level prototype")
    verify(Object.getPrototypeOf(clean.tree) === Object.prototype, "nested prototype")
    compare(clean.polluted, undefined, "nothing read through __proto__")
    compare(clean.tree.x, undefined, "nothing read through a nested __proto__")
    compare(clean.id, "p1", "other keys kept")
    compare(clean.tree.stories.length, 0, "nested keys kept")
  }

  function test_filter_by_project() {
    var runs = fixtureRuns()
    var a = Runs.withProject(runs[0], "/p/one", "One")
    var b = Runs.withProject(runs[1], "/p/two", "Two")
    var c = Runs.withProject(runs[2], "/p/one", "One")
    var d = Runs.withProject(runs[3], "/p/one/", null)
    var list = [a, b, c, d]
    var before = JSON.stringify(list)
    var out = Runs.filterByProject(list, "/p/one")
    verify(out !== list, "a new array")
    compare(out.length, 3, "three runs of /p/one")
    verify(out[0] === a, "same object, input order")
    verify(out[1] === c, "same object, input order")
    verify(out[2] === d, "same object, input order")
    var two = Runs.filterByProject(list, "/p/two")
    compare(two.length, 1, "one run of /p/two")
    verify(two[0] === b, "same object")
    compare(Runs.filterByProject(list, "/p/three").length, 0, "no run of /p/three")
    compare(list.length, 4, "input length unchanged")
    verify(list[0] === a && list[1] === b && list[2] === c && list[3] === d, "input order unchanged")
    compare(JSON.stringify(list), before, "input entries unchanged")
  }

  function test_filter_by_project_no_root_keeps_all() {
    var runs = fixtureRuns()
    // synthetic: entries that are not runs, and a run with no project
    var list = [runs[0], null, "x", Runs.withProject(runs[1], "/p/one", "One"), { id: "bare" }, 5, runs[2]]
    var roots = [["null", null], ["undefined", undefined], ["empty", ""]]
    for (var i = 0; i < roots.length; i++) {
      var out = Runs.filterByProject(list, roots[i][1])
      verify(out !== list, roots[i][0] + ": a new array")
      compare(out.length, list.length, roots[i][0] + ": every entry")
      for (var j = 0; j < list.length; j++) verify(out[j] === list[j], roots[i][0] + ": entry " + j)
    }
    var omitted = Runs.filterByProject(list)
    compare(omitted.length, list.length, "root omitted")
    verify(omitted !== list, "root omitted: a new array")
    var empty = []
    var fromEmpty = Runs.filterByProject(empty, null)
    compare(fromEmpty.length, 0, "an empty list")
    verify(fromEmpty !== empty, "an empty list: a new array")
  }

  function test_filter_by_project_trailing_slash() {
    var runs = fixtureRuns()
    var one = Runs.withProject(runs[0], "/p/one", "One")
    // synthetic: a project root set by hand with its trailing slash
    var slashed = Runs.normalizeRun(amRun("status-done.json"))
    slashed.project = { root: "/p/one/", name: "One" }
    var list = [one, slashed]
    var roots = ["/p/one", "/p/one/", "/p/one//"]
    for (var i = 0; i < roots.length; i++) {
      var out = Runs.filterByProject(list, roots[i])
      compare(out.length, 2, roots[i])
      verify(out[0] === one, roots[i] + ": first")
      verify(out[1] === slashed, roots[i] + ": second")
    }
    compare(Runs.filterByProject(list, "/P/one").length, 0, "case-sensitive")
    compare(Runs.filterByProject(list, "/p/on").length, 0, "no prefix match")
    compare(Runs.filterByProject(list, "/p").length, 0, "no parent match")
    compare(Runs.filterByProject(list, "/p/one/sub").length, 0, "no child match")
    compare(Runs.filterByProject(list, " /p/one").length, 0, "no trimming")
    compare(Runs.filterByProject(list, "/p/./one").length, 0, "no path resolution")

    // the filesystem root is a project of its own, not a match-all
    var top = Runs.withProject(runs[1], "/", null)
    // synthetic: a project root of only slashes, set by hand
    var topSlashed = { id: "t", project: { root: "//", name: "/" } }
    var rooted = Runs.filterByProject([one, top, topSlashed], "/")
    compare(rooted.length, 2, "root /")
    verify(rooted[0] === top, "root /: first")
    verify(rooted[1] === topSlashed, "root /: second")
    var doubled = Runs.filterByProject([one, top], "//")
    compare(doubled.length, 1, "root //")
    verify(doubled[0] === top, "root //: the / project")
  }

  function test_filter_by_project_without_project() {
    var root = "/home/user/Code/omarchy-project-manager"
    var runs = fixtureRuns()
    compare(runs[1].project.repo_dir, root, "the normalizeRun project names the root as repo_dir")
    var kept = Runs.withProject(runs[0], root, null)
    // synthetic: projects without a string root, and entries that are not runs
    var list = [runs[1], { id: "n", project: null }, { id: "m" }, { id: "s", project: "x" },
                { id: "num", project: { root: 5 } }, { id: "arr", project: [root] },
                { id: "rd", project: { repo_dir: root } }, null, "x", 5, kept, [kept]]
    var out = Runs.filterByProject(list, root)
    compare(out.length, 1, "only the projected run")
    verify(out[0] === kept, "same object")
  }

  function test_filter_by_project_garbage() {
    var run = Runs.withProject(Runs.normalizeRun(amRun("status-done.json")), "/p/one", "One")
    // synthetic: runs that are not an array
    var badRuns = [undefined, null, "x", 5, true, {}, { length: 1, 0: run }]
    for (var i = 0; i < badRuns.length; i++) {
      var withRoot = Runs.filterByProject(badRuns[i], "/p/one")
      compare(Array.isArray(withRoot), true, "runs " + i + " with a root")
      compare(withRoot.length, 0, "runs " + i + " with a root")
      var noRoot = Runs.filterByProject(badRuns[i], null)
      compare(Array.isArray(noRoot), true, "runs " + i + " without a root")
      compare(noRoot.length, 0, "runs " + i + " without a root")
    }
    // synthetic: roots that are neither a string nor null/undefined
    var list = [run]
    var badRoots = [5, 0, true, false, NaN, {}, [], ["/p/one"], { root: "/p/one" }]
    for (var j = 0; j < badRoots.length; j++) {
      var out = Runs.filterByProject(list, badRoots[j])
      compare(Array.isArray(out), true, "root " + j)
      compare(out.length, 0, "root " + j)
    }
    compare(list.length, 1, "input unchanged")
    verify(list[0] === run, "input entry unchanged")
  }

  function test_attention_across_projects() {
    var runs = fixtureRuns()
    var running = Runs.withProject(runs[0], "/p/a", "A")
    var escalated = Runs.withProject(runs[2], "/p/a", "A")
    var done = Runs.withProject(runs[1], "/p/b", "B")
    var dead = Runs.withProject(runs[0], "/p/b", "B")
    // synthetic: the started capture's lease marked dead
    dead.lease.live = false
    compare(Runs.runState(running), "running", "the started capture is running")
    compare(Runs.runState(dead), "dead", "its dead copy")
    var list = [running, escalated, done, dead]
    var out = Runs.attention(list)
    compare(out.length, 2, "one run of each project")
    verify(out[0] === escalated, "same object, input order")
    verify(out[1] === dead, "same object, input order")
    compare(list.length, 4, "input not modified")

    var onlyB = Runs.attention(Runs.filterByProject(list, "/p/b"))
    compare(onlyB.length, 1, "attention of one project")
    verify(onlyB[0] === dead, "the dead run of /p/b")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh domain/tst_runs.qml` (the script always runs the whole pytest suite first, about 2 minutes, before the filtered QML file)
Expected: exit status 1. pytest passes first; then under `== tests/core/domain/tst_runs.qml` the output shows `FAIL!` lines for the ten new `withProject`/`filterByProject` tests with a `TypeError` naming `withProject` or `filterByProject` as not a function (`test_attention_across_projects` fails too, on its `withProject` calls), and the `Totals` line reports 11 failed. Every pre-existing test still passes.

- [ ] **Step 3: Hoist the deep copy out of `normalizeRun`**

In `core/domain/runs.js`, delete the nested helper inside `normalizeRun` (currently lines 54-67):

```js
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
```

and change its two call sites in the stories loop from

```js
      var copied = copyOf(subtask)
```
```js
    var storyCopy = copyOf(story)
```

to

```js
      var copied = _copyOf(subtask)
```
```js
    var storyCopy = _copyOf(story)
```

Then add the top-level helper directly after the private helper `_lastOf` (the line `function _lastOf(list) { var a = _arrayOr(list); return a.length > 0 ? a[a.length - 1] : null }`):

```js
// A JSON-like deep copy of arrays and objects. An own `__proto__` key is
// dropped, so every copied object's prototype is Object.prototype.
function _copyOf(v) {
  if (Array.isArray(v)) {
    var list = []
    for (var a = 0; a < v.length; a++) list.push(_copyOf(v[a]))
    return list
  }
  if (!_isObject(v)) return v
  var out = {}
  var keys = Object.keys(v)
  for (var k = 0; k < keys.length; k++) {
    if (keys[k] !== "__proto__") out[keys[k]] = _copyOf(v[keys[k]])
  }
  return out
}
```

(`normalizeRun`'s nested `isObject` and the top-level `_isObject` are the same test, so the copy rule is unchanged.)

- [ ] **Step 4: Add `withProject` and `filterByProject`**

In `core/domain/runs.js`, directly after the closing `}` of `function attention(runs)` and before the comment `// String(v), trimmed. null/undefined, and values String() cannot convert (e.g. a`, insert:

```js

// `path` with every trailing "/" removed; a path of only slashes is "/". A
// non-string is "".
function _trimSlashes(path) {
  if (typeof path !== "string") return ""
  var end = path.length
  while (end > 0 && path.charAt(end - 1) === "/") end--
  if (end === 0) return path === "" ? "" : "/"
  return path.substring(0, end)
}

// A copy of `run` whose `project` is { root, name }, the registered project it
// belongs to; whatever `project` it held before is dropped. root: `root` with
// every trailing "/" removed ("/" for a root of only slashes), else "" when not
// a string; nothing else is normalised. name: `name` trimmed when that is
// non-empty, else root's last "/"-separated segment ("/" for "/", "" for "").
// The copy is deep and JSON-like (an own `__proto__` key is dropped). A `run`
// that is not a plain object is returned as is. Never mutates, never throws.
function withProject(run, root, name) {
  if (!_isObject(run)) return run
  var out = _copyOf(run)
  var r = _trimSlashes(root)
  var n = typeof name === "string" ? name.trim() : ""
  if (n === "") n = r === "/" ? "/" : r.substring(r.lastIndexOf("/") + 1)
  out.project = { root: r, name: n }
  return out
}

// The runs of the project at `root`: the entries whose `project.root` is a
// string equal to `root`, both compared with trailing "/" removed and otherwise
// exactly. A `root` of null, undefined or "" keeps every entry. Any other
// non-string `root`, or a `runs` that is not an array, gives []. Returns a new
// array of the same objects, input order. Never mutates, never throws.
function filterByProject(runs, root) {
  var list = _arrayOr(runs)
  if (root === null || root === undefined || root === "") return list.slice()
  if (typeof root !== "string") return []
  var want = _trimSlashes(root)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var run = list[i]
    if (_isObject(run) && _isObject(run.project) && typeof run.project.root === "string" &&
        _trimSlashes(run.project.root) === want) out.push(run)
  }
  return out
}
```

- [ ] **Step 5: Run the runs tests to verify they pass**

Run: `timeout 600 bash tests/run.sh domain/tst_runs.qml` (the script always runs the whole pytest suite first, about 2 minutes, before the filtered QML file)
Expected: exit status 0; under `== tests/core/domain/tst_runs.qml` no `FAIL!` line and no `TypeError`/`ReferenceError`, and `Totals: N passed, 0 failed` (191 at the time of writing: 180 before + 11). The existing `test_normalize_project_*`, the `__proto__` copy tests around line 368, and `test_attention` pass unchanged.

- [ ] **Step 6: Run the full suite**

Run: `timeout 900 bash tests/run.sh`
Expected: exit status 0; pytest (including `tests/architecture`) all pass, and every `Totals:` line reports `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): withProject and filterByProject for runs across projects"
```

<!-- task-pipeline: validated -->
