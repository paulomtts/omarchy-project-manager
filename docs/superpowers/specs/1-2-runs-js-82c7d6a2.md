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
