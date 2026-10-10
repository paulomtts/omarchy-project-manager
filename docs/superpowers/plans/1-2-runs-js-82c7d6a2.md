# 1.2 runs.js: `groupByProject` and the display order — design

Card: `82c7d6a2` (subtask of story `df7e47e9`; blocked by `eaf95735`, the 1.1 `withProject` /
`filterByProject` work, committed on this branch as `a741121`). Parent design:
`docs/superpowers/specs/2026-10-05-runs-all-projects-design.md` (cited below as **S6** with line
numbers).

## Purpose

The global Runs screen shows every project's runs grouped under a header with live / parked /
needs-attention counts, groups ordered so the project that needs a human comes first, and one flat
list in display order that the screen, the cursor and the run keys all index (S6 lines 45-52).
This card adds the two pure `runs.js` functions that compute that: `groupByProject(runs)` and
`displayOrder(groups)`.

## Inherited constraints

- `core/domain/runs.js` gains `groupByProject(runs)`: "ordering above; flattening into display
  order" (S6 §"Architecture", lines 122-124). The flattening is a separate function,
  `displayOrder(groups)` (card).
- Group order: groups with a run that needs attention first, then groups with a live run, then the
  rest; ties by name, case-blind, then root path; a project with no runs is omitted (S6 lines
  45-48; card).
- Each group's header carries counts of live / parked / needs-attention runs (S6 lines 45-46).
- "Needs attention" is `Runs.attention` (escalated or dead); there is no `attentionAcross`
  (S6 lines 125-126; `docs/architecture.md` line 180, "`attention` (escalated or dead)").
- One list order: `RunStore.filteredRuns` is the list in display order, group by group, each group
  in am's order (= input order) (S6 lines 50-52). This card only provides the flattening; wiring it
  into `RunStore` is out of scope.
- Layering per `docs/architecture.md` (S6 line 111): `runs.js` stays pure `.pragma library`, never
  throws (`docs/architecture.md` line 180); no new `.import`; `tests/architecture` must pass (no
  duplicated components, icon glyph rules: plain ASCII in strings and comments).
- Doc comments state the contract only, no narrative; TDD, tests first; verification
  `bash tests/run.sh` green (card).
- Style of the 1.1 functions (`runs.js:347-391`): `var`/`function`, no `const`/`let`/arrows,
  `_`-prefixed private helpers, one contract comment above each public function, never mutate,
  never throw, tolerate non-array / non-object input. Reuse `_isObject`, `_arrayOr`, `_stringOr`
  (`runs.js:170-172`), `_trimSlashes` (`runs.js:348`), `runState` (`runs.js:150`).

## Observable behavior

### `Runs.groupByProject(runs)` -> array of groups

1. **Non-array or empty `runs`** gives a new empty array `[]`.
2. **Which entries count.** Only plain-object entries (`_isObject`) are grouped. Non-object
   entries (`null`, `undefined`, strings, numbers, arrays) are dropped and appear in no group.
3. **Group key.** An entry's key is `_trimSlashes(run.project.root)` when `run.project` is a plain
   object and `run.project.root` is a string; otherwise `""`. So `"/p/one"` and `"/p/one/"` share
   one group. Comparison is otherwise exact (case-sensitive, no path resolution).
4. **One group per key that has runs.** A group exists only for a key at least one entry has;
   there is never an empty group.
5. **Group shape.** Each group is a fresh object with exactly the keys `counts`, `project`, `runs`:
   - `project`: a fresh object with exactly the keys `root` and `name`. `root` is the key.
     `name` is the `project.name` of the first entry (input order) with that key when it is a
     string, else `""`. For the `""` key (the no-project group) `name` is always `""`.
   - `runs`: a new array of the same entry objects (`===`) with that key, in input order.
   - `counts`: a fresh object with exactly the keys `live`, `parked`, `attention`, each a
     non-negative integer: `live` = entries whose `runState` is `running`; `parked` = entries
     whose `runState` is `parked`; `attention` = entries whose `runState` is `escalated` or
     `dead` (exactly the entries `Runs.attention` returns). A dead run counts as attention, not
     live; `done`, `cancelled` and `unknown` count in none.
6. **Order of the project groups** (every group whose key is not `""`), by these rules in turn:
   1. rank: a group with `counts.attention > 0` first (rank 0), else one with `counts.live > 0`
      (rank 1), else the rest (rank 2);
   2. `project.name.toLowerCase()`, ascending by plain string comparison (`<`, code-unit order,
      not locale-sensitive);
   3. `project.root`, ascending by plain string comparison;
   4. first appearance in the input (only reachable when two keys tie on all of the above, which
      cannot happen since keys are distinct; stated so the order never depends on `Array.sort`
      stability).
7. **The no-project group is last.** When any entry has the `""` key, its group (`project`
   `{root: "", name: ""}`) is the last element, whatever its counts (even with an attention run).
8. **Pure.** The input array and its entries are unchanged (JSON-equal before and after; the
   array keeps its length and entries). Never throws, including for a prototype-less entry
   (`Object.create(null)`, grouped under `""`) and an entry whose `project` is garbage.

### `Runs.displayOrder(groups)` -> flat array of runs

9. **Flattening.** A new array: for each element of `groups` in order, the elements of its `runs`
   array in order, the same values (`===`). For the output of `groupByProject(runs)` it holds
   exactly the grouped entries of `runs`, each once.
10. **Garbage.** A non-array `groups` gives `[]`; `[]` gives `[]`. A group that is not a plain
    object, or whose `runs` is not an array, is skipped. Elements of a group's `runs` array are
    copied as they are (no filtering). Never mutates, never throws.

## Doc comments (contract)

Above each new function, contract only: input, the group shape `{project: {root, name}, runs,
counts: {live, parked, attention}}`, the key / name rule, the count definitions, the ordering
rules and the no-project-last rule, "same objects, input order", "never mutates, never throws".
Placement: directly after `filterByProject` (before `_textOf`, `runs.js:394`), in the same
section.

## Tests

All in `tests/core/domain/tst_runs.qml` (TestCase `DomainRuns`), appended after
`test_attention_across_projects` in a section `// ---- S6 1.2: grouping ----`. Tier: **QML unit
(qmltestrunner)** for every test, because both functions are pure `.pragma library` functions
with no I/O, and this file is where the `runs.js` contract is tested (`docs/architecture.md`
§"Tests", line 217 ff.); no store, UI or Python layer is involved. Inputs are normalised runs
(the functions take `normalizeRun` output, so per `docs/architecture.md` lines 259-266 they may be
built from `fixtureRuns()` and re-projected with `Runs.withProject`). Fixture indices: 0 running
(started, live lease), 1 done, 2 escalated, 3 done (integrate). A dead run is a `withProject` copy
of run 0 with `lease.live = false`; a parked run is a copy with `status = "stopped"`; both marked
`// synthetic:`, as `test_attention_across_projects` does.

| Test | Proves | Input |
|---|---|---|
| `test_group_by_project_order_by_rank` | rules 4, 6.1: projects `/p/c` "C" (done only), `/p/b` "B" (running), `/p/a` "A" (done) and `/p/z` "Z" (escalated) in mixed input order -> groups `Z`, `B`, `A`, `C` (attention, live, then by name); a group with a dead run ranks as attention; a group with both attention and live runs ranks as attention | `fixtureRuns()` + `withProject` + `// synthetic:` dead |
| `test_group_by_project_name_ties` | rules 6.2, 6.3: same rank, names `"beta"`, `"Alpha"`, `"alpha"` on roots `/r/2`, `/r/3`, `/r/1` -> `alpha` (`/r/1`), `Alpha` (`/r/3`), `beta`; names compared case-blind (`"Alpha"` before `"beta"`), equal lower-case names ordered by root | `withProject` on done runs |
| `test_group_by_project_counts` | rule 5 counts: one project holding running, dead, parked, escalated, done and cancelled (`// synthetic:` `status = "cancelled"`) runs -> `{live: 1, parked: 1, attention: 2}`; keys exactly `attention,live,parked`; a project of done runs only -> all zero | `fixtureRuns()` + `withProject` + `// synthetic:` |
| `test_group_by_project_shape` | rule 5: keys exactly `counts,project,runs`; `project` keys exactly `name,root`; `runs` entries are the same objects in input order; group `name` comes from the first run (a later run with another name on the same root does not change it); two calls give distinct group, `project`, `counts` and `runs` objects | `withProject` |
| `test_group_by_project_trailing_slash` | rule 3: a run with `project.root` `"/p/one/"` (set by hand, `// synthetic:`) and one with `"/p/one"` share one group whose root is `"/p/one"`; `"/P/one"` is a separate group | `withProject` + `// synthetic:` |
| `test_group_by_project_empty` | rules 1, 4: `[]`, `undefined`, `null`, `"x"`, `{}`, `{length: 1, 0: run}` -> `[]`, a new array each time; `[null, "x", 5, []]` -> `[]` (rule 2) | `// synthetic:` |
| `test_group_by_project_without_project` | rules 3, 5, 7: plain `normalizeRun` output (`project` `{id, repo_dir}`), `project: null`, `project` missing, `project: {root: 5}`, `withProject(run, 5, "x")` (root `""`) and `Object.create(null)` all land in ONE last group `{root: "", name: ""}`, in input order; that group stays last even when it holds the escalated run and the project groups hold none | `fixtureRuns()` + `// synthetic:` |
| `test_group_by_project_pure` | rule 8: input array length, entries (`===`) and `JSON.stringify` of each entry unchanged after the call; never throws on a mixed garbage list | `fixtureRuns()` + `withProject` |
| `test_display_order` | rule 9: `displayOrder(groupByProject(list))` for the list of `test_group_by_project_order_by_rank` is the runs of `Z`, then `B`, then `A`, then `C`, each group in input order, same objects; its length equals the number of object entries; the no-project group's runs come last | `fixtureRuns()` + `withProject` |
| `test_display_order_garbage` | rule 10: `[]`, `undefined`, `null`, `"x"`, `{}` -> `[]`; groups `null`, `5`, `{}`, `{runs: "x"}` skipped among good ones; the result is a new array (`!==` any group's `runs`) and the groups are unchanged | `// synthetic:` |

Existing tests stay green unchanged.

## Review focus (inputs the tests above do not all pin)

- Two registrations of one repository with different names: the group is named by the first run
  in input order (rule 5), matching S6 lines 136-137 and line 168.
- A group whose name is `""` (root `"/"` gives name `"/"` through `withProject`, but a hand-set
  `name: ""` is possible): sorts before named groups of its rank by rule 6.2.
- Non-ASCII names: ordered by `toLowerCase()` and code units, not locale; deterministic.

## Error paths

None surface: both functions never throw. Defaults: `[]` for non-array input (rules 1, 10),
non-object entries dropped (rule 2), runs with no usable project grouped under `""` (rule 3),
malformed groups skipped by `displayOrder` (rule 10).

## Out of scope

- `withProject`, `filterByProject`, `Runs.attention` (1.1, done; unchanged here).
- `RunStore.filteredRuns` using `displayOrder`, `RunStore.runsByProject`, `projectRoots` and
  registry filtering (S6 lines 127-139; story of `RunStore`). Note S6 line 135 groups
  `runsByProject` on `project.repo_dir`; this card groups normalised runs on `project.root` as set
  by `withProject`, and does not touch the store.
- Applying the status filters (Needs attention / Live / Parked / All) before grouping (S6 lines
  48-49): the caller filters with the existing `filterRuns`, then groups.
- Group headers, project filter chips, cursor wiring, `RunIndicator` (S6 lines 140-142; UI
  stories).
- `docs/architecture.md` wording for the new functions (docs card).
- No file outside `core/domain/runs.js` and `tests/core/domain/tst_runs.qml` is touched.

## Hand-off to the planner

One task is enough: one code file (`core/domain/runs.js`: `groupByProject` and `displayOrder`
after `filterByProject`, plus at most one private comparator / rank helper, `_`-prefixed) and one
test file (`tests/core/domain/tst_runs.qml`). Write the tests first, run
`bash tests/run.sh tst_runs` to see them fail on the missing functions, implement, then run the
full `bash tests/run.sh`. Plan in the writing-plans format of the brief.

---

# runs.js `groupByProject` and `displayOrder` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the pure `Runs.groupByProject(runs)` and `Runs.displayOrder(groups)` functions that group runs by registered project (with live / parked / attention counts, attention-first order, no-project group last) and flatten the groups into one display-order list.

**Architecture:** Two public functions and one private comparator `_compareGroups` in `core/domain/runs.js`, placed directly after `filterByProject` (before `_textOf`). They reuse `_isObject`, `_arrayOr`, `_stringOr`, `_trimSlashes` and `runState`. Tests are QML unit tests appended to `tests/core/domain/tst_runs.qml`.

**Tech Stack:** QML JavaScript (`.pragma library`, ES5 style: `var`/`function`), Qt Quick Test via `qmltestrunner`, driven by `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/1-2-runs-js-82c7d6a2.md` (prepended above).

## Global Constraints

- `runs.js` stays pure `.pragma library`; no new `.import`; never throws, never mutates its input.
- Style of the 1.1 functions: `var`/`function`, no `const`/`let`/arrows, `_`-prefixed private helpers, one contract comment above each public function.
- At most one private comparator / rank helper, `_`-prefixed.
- Plain ASCII in all new strings and comments (tests included: write non-ASCII test names as `\u` escapes).
- Doc comments state the contract only, no narrative.
- No file outside `core/domain/runs.js` and `tests/core/domain/tst_runs.qml` is touched.
- Verification: `bash tests/run.sh` green (it runs pytest, including `tests/architecture`, then every QML test).

## Review Focus

1. Two registrations of one repository root with different names: the group takes the name of the first run in input order -- pinned in `test_group_by_project_shape`.
2. A group whose name is `""` (hand-set `name: ""`, or a non-string name): sorts before named groups of its rank -- pinned in `test_group_by_project_name_ties` (and the non-string name becomes `""` in `test_group_by_project_shape`).
3. Non-ASCII names: ordered by `toLowerCase()` and code units, not locale, and the same order whatever the input order -- pinned in `test_group_by_project_name_ties`.
4. A project root of `"/"` (the filesystem root) is a real project group, not the no-project group -- pinned in `test_group_by_project_trailing_slash`.
5. The no-project group stays last even when it is the only group needing attention, and the project groups' order is unaffected by its position in the input -- pinned in `test_group_by_project_without_project`.

---

### Task 1: `groupByProject` and `displayOrder`

**Files:**
- Modify: `core/domain/runs.js` (insert after `filterByProject`, which ends at line 390, before the `// String(v), trimmed.` comment of `_textOf` at line 392)
- Test: `tests/core/domain/tst_runs.qml` (append after `test_attention_across_projects`, which ends at line 4084, before the closing `}` of the `TestCase` at line 4085)

**Interfaces:**
- Consumes (already in `runs.js`): `_isObject(v)`, `_arrayOr(v)`, `_stringOr(v)`, `_trimSlashes(path)`, `runState(run)` (returns `running | dead | parked | cancelled | escalated | done | unknown`), `withProject(run, root, name)`, `attention(runs)`, `normalizeRun(raw)`.
- Consumes (test file helpers): `amRun(name)`, `fixtureRuns()` (indices: 0 running, 1 done, 2 escalated, 3 done-integrate; each normalised run's `project` is `{ id, repo_dir }` with no `root`).
- Produces:
  - `Runs.groupByProject(runs)` -> `Array<{ project: { root: string, name: string }, runs: Array<run>, counts: { live: number, parked: number, attention: number } }>`
  - `Runs.displayOrder(groups)` -> `Array<run>`
  - private `_compareGroups(a, b)` -> negative / positive number (sort comparator over two project groups).

- [ ] **Step 1: Write the failing tests**

In `tests/core/domain/tst_runs.qml`, after the closing `}` of `test_attention_across_projects` (line 4084) and before the final `}` of the file, insert:

```qml

  // ---- S6 1.2: grouping -------------------------------------------------------------------

  // The `project.root` of every group, comma-joined.
  function groupRoots(groups) {
    var roots = []
    for (var i = 0; i < groups.length; i++) roots.push(groups[i].project.root)
    return roots.join(",")
  }

  function test_group_by_project_order_by_rank() {
    var runs = fixtureRuns()
    compare(Runs.runState(runs[0]), "running", "fixture 0 is running")
    compare(Runs.runState(runs[1]), "done", "fixture 1 is done")
    compare(Runs.runState(runs[2]), "escalated", "fixture 2 is escalated")
    compare(Runs.runState(runs[3]), "done", "fixture 3 is done")
    var c1 = Runs.withProject(runs[1], "/p/c", "C")
    var b1 = Runs.withProject(runs[0], "/p/b", "B")
    var a1 = Runs.withProject(runs[3], "/p/a", "A")
    var z1 = Runs.withProject(runs[2], "/p/z", "Z")
    var b2 = Runs.withProject(runs[1], "/p/b", "B")
    var groups = Runs.groupByProject([c1, b1, a1, z1, b2])
    compare(groups.length, 4, "one group per project, none empty")
    compare(groupRoots(groups), "/p/z,/p/b,/p/a,/p/c", "attention, then live, then by name")

    // synthetic: the started capture's lease marked dead
    var dead = Runs.withProject(runs[0], "/p/y", "Y")
    dead.lease.live = false
    compare(Runs.runState(dead), "dead", "the dead copy")
    compare(groupRoots(Runs.groupByProject([b1, dead, a1])), "/p/y,/p/b,/p/a", "a dead run ranks as attention")

    var mixedLive = Runs.withProject(runs[0], "/p/x", "X")
    var mixedEscalated = Runs.withProject(runs[2], "/p/x", "X")
    compare(groupRoots(Runs.groupByProject([b1, mixedLive, a1, mixedEscalated])), "/p/x,/p/b,/p/a",
            "attention and live together rank as attention")
  }

  function test_group_by_project_name_ties() {
    var runs = fixtureRuns()
    var beta = Runs.withProject(runs[1], "/r/2", "beta")
    var upperAlpha = Runs.withProject(runs[3], "/r/3", "Alpha")
    var alpha = Runs.withProject(runs[1], "/r/1", "alpha")
    var groups = Runs.groupByProject([beta, upperAlpha, alpha])
    compare(groupRoots(groups), "/r/1,/r/3,/r/2", "case-blind name, then root")
    compare(groups[0].project.name, "alpha", "first name")
    compare(groups[1].project.name, "Alpha", "second name")
    compare(groups[2].project.name, "beta", "third name")

    // synthetic: a name set by hand to "" sorts before the named groups of its rank
    var blank = Runs.withProject(runs[3], "/r/9", "x")
    blank.project.name = ""
    compare(groupRoots(Runs.groupByProject([beta, alpha, blank])), "/r/9,/r/1,/r/2", "an empty name first")

    // synthetic: non-ASCII names order by code unit after toLowerCase, whatever the input order
    var accented = Runs.withProject(runs[1], "/u/1", "\u00c9clair")
    var zeta = Runs.withProject(runs[1], "/u/2", "zeta")
    var plain = Runs.withProject(runs[1], "/u/3", "eclair")
    compare(groupRoots(Runs.groupByProject([accented, zeta, plain])), "/u/3,/u/2,/u/1", "code-unit order")
    compare(groupRoots(Runs.groupByProject([plain, zeta, accented])), "/u/3,/u/2,/u/1", "same order reversed")
  }

  function test_group_by_project_counts() {
    var runs = fixtureRuns()
    var running = Runs.withProject(runs[0], "/p/m", "M")
    // synthetic: the started capture's lease marked dead
    var dead = Runs.withProject(runs[0], "/p/m", "M")
    dead.lease.live = false
    // synthetic: a done capture marked stopped (parked) and cancelled
    var parked = Runs.withProject(runs[1], "/p/m", "M")
    parked.status = "stopped"
    var cancelled = Runs.withProject(runs[1], "/p/m", "M")
    cancelled.status = "cancelled"
    var escalated = Runs.withProject(runs[2], "/p/m", "M")
    var done = Runs.withProject(runs[3], "/p/m", "M")
    var otherDone = Runs.withProject(runs[1], "/p/n", "N")
    var otherIntegrate = Runs.withProject(runs[3], "/p/n", "N")
    // synthetic: a run whose status am never writes
    var unknown = { id: "u", status: "weird", project: { root: "/p/n", name: "N" } }
    compare(Runs.runState(unknown), "unknown", "the unknown run")

    var groups = Runs.groupByProject([running, dead, otherDone, parked, escalated, unknown, done, cancelled, otherIntegrate])
    compare(groupRoots(groups), "/p/m,/p/n", "two groups")
    var m = groups[0]
    compare(Object.keys(m.counts).sort().join(","), "attention,live,parked", "count keys")
    compare(m.counts.live, 1, "one running")
    compare(m.counts.parked, 1, "one parked")
    compare(m.counts.attention, 2, "dead and escalated")
    compare(m.counts.attention, Runs.attention(m.runs).length, "attention counts what Runs.attention returns")
    compare(m.runs.length, 6, "every run of /p/m")
    var n = groups[1]
    compare(n.runs.length, 3, "every run of /p/n")
    compare(n.counts.live, 0, "no live run")
    compare(n.counts.parked, 0, "no parked run")
    compare(n.counts.attention, 0, "no attention run")
  }

  function test_group_by_project_shape() {
    var runs = fixtureRuns()
    var first = Runs.withProject(runs[1], "/p/s", "First")
    var live = Runs.withProject(runs[0], "/p/t", "T")
    var second = Runs.withProject(runs[3], "/p/s/", "Second")
    var list = [first, live, second]
    var groups = Runs.groupByProject(list)
    compare(groupRoots(groups), "/p/t,/p/s", "the live group first")
    var s = groups[1]
    compare(Object.keys(s).sort().join(","), "counts,project,runs", "group keys")
    compare(Object.keys(s.project).sort().join(","), "name,root", "project keys")
    compare(s.project.root, "/p/s", "root")
    compare(s.project.name, "First", "the name of the first run")
    compare(s.runs.length, 2, "both runs of /p/s")
    verify(s.runs[0] === first, "same object, input order")
    verify(s.runs[1] === second, "same object, input order")
    verify(s.runs !== list, "a new runs array")
    verify(s.project !== first.project, "a new project object")

    var again = Runs.groupByProject(list)
    verify(again !== groups, "a new array per call")
    verify(again[1] !== s, "a new group per call")
    verify(again[1].project !== s.project, "a new project per call")
    verify(again[1].counts !== s.counts, "new counts per call")
    verify(again[1].runs !== s.runs, "new runs per call")

    // synthetic: the first run of a root names it with a non-string name
    var unnamed = { id: "q1", status: "done", project: { root: "/p/q", name: 5 } }
    var named = { id: "q2", status: "done", project: { root: "/p/q", name: "Q" } }
    var q = Runs.groupByProject([unnamed, named])
    compare(q.length, 1, "one group")
    compare(q[0].project.name, "", "a non-string first name is empty")
  }

  function test_group_by_project_trailing_slash() {
    var runs = fixtureRuns()
    var plain = Runs.withProject(runs[1], "/p/one", "One")
    // synthetic: a project root set by hand with its trailing slash
    var slashed = Runs.normalizeRun(amRun("status-done.json"))
    slashed.project = { root: "/p/one/", name: "One" }
    var upper = Runs.withProject(runs[3], "/P/one", "One")
    var groups = Runs.groupByProject([slashed, plain, upper])
    compare(groupRoots(groups), "/P/one,/p/one", "two groups, case-sensitive, ordered by root")
    compare(groups[1].runs.length, 2, "trailing slash shares the group")
    verify(groups[1].runs[0] === slashed, "same object, input order")
    verify(groups[1].runs[1] === plain, "same object, input order")

    // the filesystem root is a project of its own, not the no-project group
    var top = Runs.withProject(runs[1], "/", null)
    var rooted = Runs.groupByProject([top, { id: "loose", status: "done" }])
    compare(rooted.length, 2, "/ and the no-project group")
    compare(rooted[0].project.root, "/", "/ is a project group")
    compare(rooted[0].project.name, "/", "named /")
    compare(rooted[1].project.root, "", "the no-project group last")
  }

  function test_group_by_project_empty() {
    var run = Runs.withProject(Runs.normalizeRun(amRun("status-done.json")), "/p/one", "One")
    var empty = []
    // synthetic: runs that are not an array
    var bad = [empty, undefined, null, "x", 5, {}, { length: 1, 0: run }]
    for (var i = 0; i < bad.length; i++) {
      var out = Runs.groupByProject(bad[i])
      compare(Array.isArray(out), true, "runs " + i)
      compare(out.length, 0, "runs " + i)
    }
    verify(Runs.groupByProject(empty) !== empty, "a new array for []")
    verify(Runs.groupByProject(null) !== Runs.groupByProject(null), "a new array per call")
    // synthetic: entries that are not plain objects
    compare(Runs.groupByProject([null, undefined, "x", 5, true, []]).length, 0, "non-object entries dropped")
  }

  function test_group_by_project_without_project() {
    var runs = fixtureRuns()
    var plain = runs[1]
    var escalated = runs[2]
    compare(Object.keys(plain.project).sort().join(","), "id,repo_dir", "normalizeRun gives no root")
    // synthetic: projects without a string root, and a prototype-less entry
    var nullProject = { id: "n", status: "done", project: null }
    var noProject = { id: "m", status: "done" }
    var numRoot = { id: "num", status: "done", project: { root: 5 } }
    var blankRoot = Runs.withProject(runs[3], 5, "x")
    compare(blankRoot.project.root, "", "withProject with a non-string root gives root \"\"")
    var bare = Object.create(null)
    bare.id = "b"
    var a = Runs.withProject(runs[1], "/p/a", "A")
    var b = Runs.withProject(runs[0], "/p/b", "B")
    var list = [plain, a, nullProject, noProject, escalated, numRoot, b, blankRoot, bare]
    var groups = Runs.groupByProject(list)
    compare(groupRoots(groups), "/p/b,/p/a,", "the no-project group last, even with an attention run")
    var last = groups[2]
    compare(last.project.root, "", "no-project root")
    compare(last.project.name, "", "no-project name, never the name of a run")
    compare(last.counts.attention, 1, "it holds the escalated run")
    var expected = [plain, nullProject, noProject, escalated, numRoot, blankRoot, bare]
    compare(last.runs.length, expected.length, "every run without a project")
    for (var i = 0; i < expected.length; i++) verify(last.runs[i] === expected[i], "same object, input order " + i)

    // its position in the input does not move the project groups
    var reordered = Runs.groupByProject([escalated, b, plain, a])
    compare(groupRoots(reordered), "/p/b,/p/a,", "no-project first in the input, last in the groups")
  }

  function test_group_by_project_pure() {
    var runs = fixtureRuns()
    var a = Runs.withProject(runs[0], "/p/a", "A")
    var b = Runs.withProject(runs[2], "/p/b", "B")
    var c = Runs.withProject(runs[1], "/p/a/", "A")
    var bare = Object.create(null)
    bare.id = "bare"
    // synthetic: garbage entries and garbage projects
    var list = [a, null, b, "x", 5, [], { id: "s", project: "junk" }, { id: "arr", project: [1] },
                { id: "obj", project: { root: {}, name: {} } }, bare, undefined, c]
    var entries = list.slice()
    var before = []
    for (var i = 0; i < list.length; i++) before.push(JSON.stringify(list[i]))
    var groups = Runs.groupByProject(list)
    compare(groupRoots(groups), "/p/b,/p/a,", "attention, live, no-project")
    compare(list.length, entries.length, "input length unchanged")
    for (var j = 0; j < list.length; j++) {
      verify(list[j] === entries[j], "entry " + j + " is the same object")
      compare(JSON.stringify(list[j]), before[j], "entry " + j + " unchanged")
    }
  }

  function test_display_order() {
    var runs = fixtureRuns()
    var c1 = Runs.withProject(runs[1], "/p/c", "C")
    var b1 = Runs.withProject(runs[0], "/p/b", "B")
    var a1 = Runs.withProject(runs[3], "/p/a", "A")
    var z1 = Runs.withProject(runs[2], "/p/z", "Z")
    var b2 = Runs.withProject(runs[1], "/p/b", "B")
    var loose = runs[1]
    // synthetic: entries that are not runs
    var list = [c1, b1, null, a1, loose, z1, "x", b2]
    var flat = Runs.displayOrder(Runs.groupByProject(list))
    var expected = [z1, b1, b2, a1, c1, loose]
    compare(flat.length, expected.length, "every object entry once")
    for (var i = 0; i < expected.length; i++) verify(flat[i] === expected[i], "same object, display order " + i)
  }

  function test_display_order_garbage() {
    // synthetic: groups that are not an array
    var bad = [[], undefined, null, "x", 5, {}]
    for (var i = 0; i < bad.length; i++) {
      var out = Runs.displayOrder(bad[i])
      compare(Array.isArray(out), true, "groups " + i)
      compare(out.length, 0, "groups " + i)
    }
    // synthetic: malformed groups among good ones
    var r1 = { id: "r1" }, r2 = { id: "r2" }, r3 = { id: "r3" }
    var g1 = { runs: [r1, r2] }
    var g2 = { runs: [r3, null] }
    var groups = [null, g1, 5, {}, { runs: "x" }, [r1], g2]
    var before = JSON.stringify(groups)
    var flat = Runs.displayOrder(groups)
    compare(flat.length, 4, "the runs of the two good groups")
    verify(flat[0] === r1 && flat[1] === r2 && flat[2] === r3, "same objects, in order")
    compare(flat[3], null, "elements of runs copied as they are")
    verify(flat !== g1.runs && flat !== g2.runs, "a new array")
    compare(JSON.stringify(groups), before, "groups unchanged")
    compare(g1.runs.length, 2, "first group's runs unchanged")
    var single = Runs.displayOrder([g1])
    verify(single !== g1.runs, "a new array for a single group")
    compare(single.length, 2, "its runs")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_runs`
Expected: FAIL. The `== tests/core/domain/tst_runs.qml` block lists ten lines of the form `FAIL!  : qmltestrunner::DomainRuns::test_group_by_project_counts() Uncaught exception: Property 'groupByProject' of object [object Object] is not a function` (`'displayOrder'` for the two `test_display_order*` tests), and the script exits non-zero. Every pre-existing `DomainRuns` test still passes. (The `tst_runs` filter also runs `tests/ui/screens/tst_runs_screen.qml`, `tests/ui/tst_runs_flow.qml` and `tests/ui/tst_runs_real_data.qml`; those stay `0 failed`.)

- [ ] **Step 3: Write the minimal implementation**

In `core/domain/runs.js`, directly after the closing `}` of `filterByProject` (line 390) and before the blank line and the `// String(v), trimmed. null/undefined, and values String() cannot convert (e.g. a` comment of `_textOf`, insert:

```js

// Order of two project groups: a group with attention > 0 first, then one with
// live > 0, then the rest; then project.name lower-cased, then project.root,
// both by plain string comparison. Roots are distinct, so no two groups tie.
function _compareGroups(a, b) {
  function rank(g) { return g.counts.attention > 0 ? 0 : (g.counts.live > 0 ? 1 : 2) }
  var ra = rank(a), rb = rank(b)
  if (ra !== rb) return ra - rb
  var na = a.project.name.toLowerCase(), nb = b.project.name.toLowerCase()
  if (na !== nb) return na < nb ? -1 : 1
  if (a.project.root !== b.project.root) return a.project.root < b.project.root ? -1 : 1
  return 0
}

// The runs grouped by registered project, in display order. Entries that are
// not plain objects are dropped. Each group is
//   { project: { root, name }, runs, counts: { live, parked, attention } }
// root: the entry's `project.root` with every trailing "/" removed, else ""
// when `project` is not a plain object or its root is not a string; otherwise
// compared exactly. name: the `project.name` of the group's first entry when a
// string, else ""; always "" for root "". runs: the same objects, input order.
// counts, by runState: live = running; parked = parked; attention = escalated
// or dead (the runs `attention` returns). A group exists only for a root some
// entry has. Order: groups with attention > 0, then live > 0, then the rest;
// ties by name lower-cased, then root, by plain string comparison. The root ""
// group is last, whatever its counts. A `runs` that is not an array gives [].
// Never mutates, never throws.
function groupByProject(runs) {
  var list = _arrayOr(runs)
  var groups = []
  var loose = null
  for (var i = 0; i < list.length; i++) {
    var run = list[i]
    if (!_isObject(run)) continue
    var project = _isObject(run.project) ? run.project : {}
    var root = typeof project.root === "string" ? _trimSlashes(project.root) : ""
    var group = root === "" ? loose : null
    for (var g = 0; root !== "" && group === null && g < groups.length; g++) {
      if (groups[g].project.root === root) group = groups[g]
    }
    if (group === null) {
      group = { project: { root: root, name: root === "" ? "" : _stringOr(project.name) },
                runs: [], counts: { live: 0, parked: 0, attention: 0 } }
      if (root === "") loose = group
      else groups.push(group)
    }
    group.runs.push(run)
    var s = runState(run)
    if (s === "running") group.counts.live += 1
    else if (s === "parked") group.counts.parked += 1
    else if (s === "escalated" || s === "dead") group.counts.attention += 1
  }
  groups.sort(_compareGroups)
  if (loose !== null) groups.push(loose)
  return groups
}

// The runs of `groups` (groupByProject output) as one list: each group's `runs`
// in turn, the same values in order. A group that is not a plain object, or
// whose `runs` is not an array, is skipped; a `groups` that is not an array
// gives []. Returns a new array. Never mutates, never throws.
function displayOrder(groups) {
  var list = _arrayOr(groups)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var group = list[i]
    if (!_isObject(group) || !Array.isArray(group.runs)) continue
    for (var j = 0; j < group.runs.length; j++) out.push(group.runs[j])
  }
  return out
}
```

Notes for the implementer:
- `_isObject` is true for a prototype-less entry (`Object.create(null)`); its `project` reads as `undefined`, so it lands in the root `""` group. `runState` on it is `unknown`, so it counts nowhere.
- Groups are found by linear scan with `===` on the root string (no object used as a map), so a root such as `__proto__` behaves like any other.
- Never call `localeCompare`: names compare with `<` on `toLowerCase()` output.

- [ ] **Step 4: Run the QML tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_runs`
Expected: the `== tests/core/domain/tst_runs.qml` block shows `Totals: N passed, 0 failed, 0 skipped, ...` with no `FAIL!` and no `TypeError` / `ReferenceError` line; exit status 0.

- [ ] **Step 5: Run the full suite**

Run: `timeout 900 bash tests/run.sh`
Expected: pytest reports all passed (including `tests/architecture/test_layers.py` and `tests/architecture/test_icon_glyphs.py`), every QML block shows `0 failed`, no `TypeError`/`ReferenceError` lines, exit status 0. Confirm ASCII only in the change: `git diff -U0 | grep -nP '[^\x00-\x7F]'` prints nothing.

- [ ] **Step 6: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): groupByProject and displayOrder for the runs-across-projects list"
```
<!-- task-pipeline: validated -->
