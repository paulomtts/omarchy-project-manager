# 1.3 runs.js: dispatchTargets — design

Card: `d46d9a63` (subtask of story `66107096`, blocked by 1.2 `51a67305`, `dispatchProjects`).
Parent design: `docs/superpowers/specs/2026-10-05-dispatch-from-runs-design.md`, cited below as
"DFR l.N".

## Purpose

Step 2 of the Runs-screen dispatch dialog lists what can be dispatched in the picked project:
the whole board, then its milestones, stories and todo subtasks in tree order (DFR l.81-94).
This card adds the pure domain function that turns that project's indexed brd tree into those
rows:

```
Runs.dispatchTargets(roots, cardMap) -> [{key, level, card, label, depth}]
```

Nothing calls it yet. The store (`dispatchTargetRows`, `dispatchTargetPick(key)`,
DFR l.193, l.205-208) wires it in a later card.

## Inherited constraints

- Rows are `{key, level: board|milestone|story|subtask, card, label, depth}`, in tree order
  (DFR l.179-180; card).
- **Whole board** is first (DFR l.86; card).
- Then, in tree order, every milestone that is not finished, every story that is not finished
  and every subtask whose status is `todo` (DFR l.87-89; card).
- A finished card (`done`, `merged`, `canceled`, `archived`) is omitted, and so is any card
  `dispatchPlan` does not offer (DFR l.89-91; card). "Finished" is `Board.isFinishedStatus`
  (`core/domain/board.js:185-188`).
- A container whose children all drop out still shows itself if it is offered (DFR l.91).
- Every row's offer comes from `dispatchPlan`, so the two never disagree (DFR l.180-181; card).
- A project whose tree has no offered target shows only **Whole board** (DFR l.94; card:
  "empty tree gives only Whole board").
- Input is brd's tree (`board-tree.py ROOT` → `data`) indexed with `Board.indexTree`
  (`core/domain/board.js:12`), which sets `depth` and `parentId` in place and returns
  `{cardMap}` (DFR l.159-161). `dispatchTargets` receives the roots and that `cardMap`.
- Rows are indented by depth (DFR l.88), so each row carries `depth`.
- Never throws (card). This matches the dispatch section's contract, `core/domain/runs.js:1077-1084`
  ("Pure and never throwing ... Ids are ... looked up only as own keys of cardMap").
- Tests live in `tests/core/domain/tst_runs.qml` and cover: board first, tree order, depth,
  finished omitted, only todo subtasks, stories included, agreement with `dispatchPlan`, empty
  tree gives only Whole board (card; DFR l.245-247).
- `core/domain/runs.js` is `.pragma library` and imports only other `core/domain` files
  (`docs/architecture.md:11`); it already imports `board.js` as `Board` (`runs.js:2`).
  `tests/architecture` must pass. `bash tests/run.sh` is green. Tests come first. Docstrings and
  comments state the contract only, with no narrative (card).

## Behaviour

`dispatchTargets(roots, cardMap)` returns a new array of new row objects. It never mutates its
arguments and never throws.

### The Whole board row

The first row is always, exactly:

```
{ key: "board", level: "board", card: "board", label: "Whole board", depth: 0 }
```

`label` is `Runs.dispatchLabel("board")`; `level` is `Runs.dispatchPlan("board").level`. It is
present for every input, including garbage.

### The walk

- `roots` that is not an array is treated as `[]`.
- The forest is walked depth-first, pre-order: each root in array order, and under each card its
  `children` in array order, before the next sibling. This is the order `Board.indexTree` visits.
- A node that is not a plain object (null, a string, an array, a number) gives no row and has no
  children walked.
- A plain-object node's `children` is walked when it is an array; anything else counts as no
  children.
- Children are walked whether or not their parent gives a row. A finished milestone or story,
  or a container `dispatchPlan` refuses, does not hide its descendants: each descendant is judged
  on its own (consistent with `dispatchPlan`, which never reads ancestors).
- A node object reached a second time (the same object, e.g. a `children` cycle or a shared
  child) is skipped together with its subtree, so the walk always ends.
- The walk must not recurse on the JS call stack per tree level: a chain several thousand levels
  deep returns normally (no `RangeError`).

### Which cards give a row

For a plain-object node `card`, let `plan = Runs.dispatchPlan(card, cardMap)`. The card gives a
row when all of these hold:

1. `plan.offered === true`. This alone excludes finished cards, a non-dispatch id
   (`_isDispatchId`: non-empty string not starting with `-`) and a missing or non-whole or
   negative `depth`.
2. `plan.level` is `"milestone"` or `"story"`; or `plan.level` is `"subtask"` and
   `card.status === "todo"` exactly (so `in_progress`, `review`, `blocked`, a missing status, etc.
   give no row; DFR l.260-261 keeps relaunch out).
3. No earlier row has the same `card.id` (the first occurrence in walk order wins; keys stay
   unique). The later duplicate's children are still walked.

`level` comes from the card's own `depth` through `dispatchPlan` (0 milestone, 1 story, 2+
subtask), not from its position in `roots`. A card whose `depth` disagrees with its position is
judged by its `depth`, exactly as `dispatchPlan` judges it.

### Row fields

| field | value |
|---|---|
| `key` | `"card:" + card.id`. Never equal to `"board"`, even for a card whose id is `"board"`. |
| `level` | `plan.level` (`"milestone"`, `"story"` or `"subtask"`) |
| `card` | the node object itself (same reference, not a copy), so the store can hand it to the form |
| `label` | `Runs.dispatchLabel(card, cardMap)` (e.g. `Story "T" (milestone "M")`) |
| `depth` | `card.depth` |

Each row has exactly these five keys.

### `cardMap`

`cardMap` is passed through to `dispatchPlan` and `dispatchLabel` unchanged and is not read
otherwise. A missing or non-object `cardMap` (or one without the story's milestone) changes only
story labels, which fall back to `Story "T"` (`dispatchLabel`, `runs.js:1162-1176`); it never
removes a row.

## Tests (all in `tests/core/domain/tst_runs.qml`, `TestCase` "DomainRuns")

Tier: every test is a QML domain unit test. `dispatchTargets` is a pure `.pragma library`
function with no store, process or UI involved, so the domain test file the card names is the
lowest tier that exercises it. Inputs are synthetic and marked `// synthetic:` as the
neighbouring tests do. Trees are built as brd returns them (`{id, title, status, children}`) and
indexed with the real `Board.indexTree`, so the tests feed the function the same shape the store
will. This needs `import "../../../core/domain/board.js" as Board` at the top of `tst_runs.qml`
(the same import `tests/core/domain/tst_board.qml` uses). Add the block at the end of the file
under `// ---- dfr 1.3: dispatch targets ----...`, with two helpers there: `tnode(id, status,
children)` returning `{id, title: "T " + id, status, children}` and `targetKeys(rows)` joining
`rows[i].key` with `,`.

1. **`test_dispatch_targets_board_first`**: on a small indexed tree, row 0 is exactly the Whole
   board row above (keys sorted `card,depth,key,label,level`; each value compared). Every other
   row has exactly the keys `card,depth,key,label,level`.
2. **`test_dispatch_targets_tree_order_and_depth`**: two milestones, each with two stories, each
   story with two todo subtasks; keys come out in pre-order (`board, card:m1, card:s1,
   card:t1, card:t2, card:s2, ..., card:m2, ...`), each row's `depth` equals the card's
   indexed depth (0/1/2), `level` is `milestone`/`story`/`subtask` by depth, and `row.card`
   is the very node object (`===`). A depth-3 todo card is a `subtask` with depth 3.
3. **`test_dispatch_targets_finished_omitted`**: for each of `done`, `merged`, `canceled`,
   `archived`, a milestone, a story and a subtask with that status give no row. A finished
   milestone whose story is `todo` and whose subtask is `todo` still lists that story and that
   subtask (descendants are judged on their own). An unfinished story whose subtasks are all
   finished still lists itself (DFR l.91).
4. **`test_dispatch_targets_only_todo_subtasks`**: subtasks with status `in_progress`,
   `review`, `blocked`, `""`, missing and `"TODO"` give no row; `todo` does. Milestones and
   stories with `in_progress` or `blocked` are listed.
5. **`test_dispatch_targets_stories_included`**: a story row has `level: "story"`, `depth: 1`,
   and `label` equal to `Story "T s1" (milestone "T m1")`; with `cardMap` `undefined` the same
   story row is still present, with label `Story "T s1"`.
6. **`test_dispatch_targets_agree_with_dispatchPlan`**: over one mixed tree (every status above
   at every depth, plus a card with id `"-x"`, one with id `""`, one with id `5`, one with no
   `depth` because it was not indexed and is appended to a `children` array after indexing): for
   every non-board row, `Runs.dispatchPlan(row.card, cardMap)` has `offered === true` and
   `level === row.level`, and `row.label === Runs.dispatchLabel(row.card, cardMap)`; and for
   every card in `cardMap` with no row, either `dispatchPlan` refuses it or it is a subtask
   whose status is not `todo`. The `"-x"`, `""`, `5` and depth-less cards give no row.
7. **`test_dispatch_targets_empty_tree`**: `roots` of `[]`, `undefined`, `null`, `"x"`, `5`,
   `{}` each give exactly one row, the Whole board row; so does a tree whose every card is
   finished or a non-todo subtask.
8. **`test_dispatch_targets_garbage`**: no throw and the expected rows for: a root list mixing
   `null`, `"x"`, `[]`, `5` with one valid milestone (only that milestone listed); a node whose
   `children` is `"x"`, `{}` or `null` (node listed, no children); a `children` cycle (a story
   whose `children` contains its milestone) and a shared child (one subtask object in two
   stories' `children`) — each node listed once (`Board.indexTree` recurses forever on a
  cycle, so the cycle case sets `depth`/`parentId` by hand and links the cycle after;
  the shared-child case may use `indexTree`); two distinct nodes with the same id — only the
   first listed, its later twin's children still walked; a card with id `"board"` at depth 0
   gives key `"card:board"`, distinct from the Whole board row; `cardMap` of `null`, `"x"`, `[]`
   and one with a `__proto__` id entry changes no row's presence. `roots` and every node are
   unchanged (`JSON.stringify` of an acyclic input before and after).
9. **`test_dispatch_targets_deep_chain`**: a chain of 5000 cards `c0`..`c4999` (each the only
   child of the previous, all `todo`), depths set by `Board.indexTree`: the call returns, and
   the rows are the Whole board, `card:c0` (milestone), `card:c1` (story), then `card:c2`..
   `card:c4999` (subtasks) in order, 5001 rows in all. (`Board.indexTree` itself recurses; if it cannot index 5000 levels
   under qmltestrunner, set `depth`/`parentId` by hand in the test's loop instead.)
10. **`test_dispatch_targets_fresh`**: two calls on the same input return different arrays and
    different row objects; the Whole board row is a fresh object each call; `row.card` is still
    the input node.

## Error paths

None beyond the garbage rules above. The function never throws and always returns an array
whose first element is the Whole board row.

## Out of scope

- `dispatchProjects` (card 1.2, done) and `board-tree.py` (card 1.1, done).
- Every `RunStore` member: `dispatchTargetCardMap`, `dispatchTargetRows`,
  `dispatchTargetLoading`, `dispatchTargetRunner`, `dispatchTargetReplied`,
  `dispatchTargetPick(key)` (DFR l.193, l.204-208), including how `key` maps back to a card and
  calling `Board.indexTree` on the helper's reply.
- The filter field, "No target matches", "Reading the board…", indentation rendering and the
  row text the dialog shows (DFR l.92-93, l.235): `DispatchDialog.qml` and the store.
- Relaunching `in_progress` subtasks (DFR l.260-261).
- Changes to `dispatchPlan`, `dispatchLabel`, `Board.indexTree` or `Board.isFinishedStatus`.
- `docs/architecture.md` / README text for this function.

## Plan notes

- One task: write the tests above first, see them fail with `dispatchTargets` undefined
  (`TypeError: ... is not a function`, which `tests/run.sh` flags), then add the function.
- Files: `core/domain/runs.js`, `tests/core/domain/tst_runs.qml` only.
- Place `dispatchTargets` right after `dispatchLabel` in the `// ---- Dispatch (S3 1.1)` section
  of `core/domain/runs.js`, in the file's ES5 style (`var`, `function` declarations, `for`
  loops; no arrow functions, no `let`/`const`). Reuse `_isObject`, `_arrayOr`, `dispatchPlan`
  and `dispatchLabel`; do not re-implement the finished or level rules. Walk with an explicit
  stack (push children in reverse to keep pre-order) and a list of visited node objects
  (`indexOf`) for the cycle guard; track emitted ids in a second list for the duplicate rule.
- Docstring above the function in the style of `dispatchProjects` (`runs.js:499-517`): the row
  shape, the Whole board row, the walk order, the keep rule, the key rule, "Never mutates, never
  throws".
- Run one file with `bash tests/run.sh tst_runs`; run the full gate with `bash tests/run.sh`.

---

# 1.3 runs.js: dispatchTargets (card d46d9a63) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the pure domain function `Runs.dispatchTargets(roots, cardMap)` that turns one project's indexed brd tree into the dispatch dialog's step-2 rows `{key, level, card, label, depth}`: the Whole board first, then every offered milestone, story and todo subtask in tree order.

**Architecture:** One ES5 function in `core/domain/runs.js` (`.pragma library`), placed right after `dispatchLabel` in the `// ---- Dispatch (S3 1.1)` section. It walks the forest with an explicit stack (no recursion), guards cycles with a list of visited node objects, and asks `dispatchPlan` and `dispatchLabel` for every row's offer, level and text, so it never re-implements the finished or level rules. Tests are QML `TestCase` functions appended to `tests/core/domain/tst_runs.qml`.

**Tech Stack:** Qt 6 QML JavaScript (`.pragma library`, ES5 style: `var`, `function`, `for`), QtTest via `qmltestrunner`, driven by `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/1-3-runs-js-d46d9a63.md` (prepended above).

## Global Constraints

- Rows are exactly `{key, level, card, label, depth}`; row 0 is always `{ key: "board", level: "board", card: "board", label: "Whole board", depth: 0 }`.
- `key` is `"card:" + card.id` for every card row, never `"board"`.
- Every row's offer and level come from `dispatchPlan`; every label from `dispatchLabel`. Do not change `dispatchPlan`, `dispatchLabel`, `Board.indexTree` or `Board.isFinishedStatus`.
- A subtask row needs `card.status === "todo"` exactly.
- `core/domain/runs.js` is `.pragma library` and imports only other `core/domain` files (`docs/architecture.md:11`); `tests/architecture` must pass. It already imports `board.js` as `Board` (`runs.js:2`); add no import.
- ES5 style: `var`, `function` declarations, `for`/`while` loops; no arrow functions, no `let`/`const`. Reuse `_isObject`, `_arrayOr`, `dispatchPlan`, `dispatchLabel`; do not redefine them.
- No recursion on the JS call stack per tree level: a 5000-deep chain returns normally.
- Never throws, never mutates its arguments, always returns a new array of new row objects; `row.card` is the input node itself (same reference).
- Comments and docstrings state the contract only, with no narrative.
- Tests come first; `bash tests/run.sh` is green at the end.
- Only `core/domain/runs.js` and `tests/core/domain/tst_runs.qml` change.

## Review Focus

- A `children` cycle or a node shared by two parents (a hand-edited or buggy brd reply): the walk must end and list each node once, under its first parent — pinned in `test_dispatch_targets_garbage`.
- Two distinct cards with the same id: only the first gives a row, so keys stay unique for `dispatchTargetPick(key)`, while the twin's children are still offered — pinned in `test_dispatch_targets_garbage`.
- A card whose id is `"board"`: its key must be `"card:board"`, never colliding with the Whole board row's `"board"` — pinned in `test_dispatch_targets_garbage`.
- A very deep tree: `Board.indexTree` itself overflows the V4 stack on a 5000-deep chain (verified while writing this plan), so `dispatchTargets` must not add its own recursion — pinned in `test_dispatch_targets_deep_chain` (depths set by hand).
- A caller (the store or dialog) that edits a returned row: the next call must still give a pristine Whole board row, so no shared row constant — pinned in `test_dispatch_targets_fresh`.

---

## File structure

- Modify: `core/domain/runs.js` — add `dispatchTargets` (with its docstring) right after `dispatchLabel`, whose closing `}` is currently line 1179, just before the `// The branch-prefix stem of a milestone title` comment of `_stemOf`.
- Modify: `tests/core/domain/tst_runs.qml` — add `import "../../../core/domain/board.js" as Board` after the `runs.js` import (line 4), and append the `// ---- dfr 1.3: dispatch targets` block (three helpers and ten test functions) before the file's final closing `}` (currently line 4561, after `test_dispatch_projects_edges`).

## Running tests

- One file: `bash tests/run.sh domain/tst_runs` (pytest runs first, about two minutes, then only QML test paths containing `domain/tst_runs`). A `TypeError` / `is not a function` line in the output makes the script exit non-zero even if Totals look fine. Wrap long runs as `timeout 900 bash tests/run.sh ...`.
- Full gate: `bash tests/run.sh` (exit 0 required).

### Task 1: `Runs.dispatchTargets`

**Files:**
- Modify: `core/domain/runs.js:1179` (insert after `dispatchLabel`)
- Modify: `tests/core/domain/tst_runs.qml:4` (import) and `:4561` (append tests)

**Interfaces:**
- Consumes (already in `core/domain/runs.js`):
  - `dispatchPlan(card, cardMap) -> {command, flags, level, offered, reason, suggest}`; `dispatchPlan("board").level === "board"`; for a card it is refused (`offered: false`) when the card is not a plain object, its id is not a non-empty string or starts with `-`, its `depth` is not a whole number >= 0, or `Board.isFinishedStatus(card.status)`; otherwise `level` is `"milestone"` (depth 0), `"story"` (depth 1) or `"subtask"` (depth >= 2).
  - `dispatchLabel(card, cardMap) -> string`; `dispatchLabel("board") === "Whole board"`.
  - `_isObject(v) -> bool` (non-null, typeof object, not an array); `_arrayOr(v) -> array` (`v` if an array, else `[]`).
  - Tests only: `Board.indexTree(roots) -> {cardMap}` from `core/domain/board.js` (sets `depth` and `parentId` in place; recursive).
- Produces: `Runs.dispatchTargets(roots, cardMap) -> [{key: string, level: "board"|"milestone"|"story"|"subtask", card: "board"|object, label: string, depth: number}]`, consumed later by `RunStore` (`dispatchTargetRows`, `dispatchTargetPick(key)`), out of scope here.

- [ ] **Step 1: Import Board into the test file**

In `tests/core/domain/tst_runs.qml`, change the top imports from:

```qml
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs
import "../../helpers/amFixtures.js" as F
```

to:

```qml
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs
import "../../../core/domain/board.js" as Board
import "../../helpers/amFixtures.js" as F
```

- [ ] **Step 2: Write the failing tests**

In `tests/core/domain/tst_runs.qml`, insert this block after the closing `}` of `test_dispatch_projects_edges` and before the file's final `}` (the one that closes `TestCase`). Leave one blank line before the section comment. The file must still end with that single `}`.

```qml
  // ---- dfr 1.3: dispatch targets ----------------------------------------------------------

  // A card as brd tree returns it, before Board.indexTree.
  function tnode(id, status, children) {
    return { id: id, title: "T " + id, status: status, children: children }
  }

  function targetKeys(rows) {
    var out = []
    for (var i = 0; i < rows.length; i++) out.push(rows[i].key)
    return out.join(",")
  }

  function checkWholeBoard(row, label) {
    compare(Object.keys(row).sort().join(","), "card,depth,key,label,level", label + " keys")
    compare(row.key, "board", label + " key")
    compare(row.level, "board", label + " level")
    compare(row.card, "board", label + " card")
    compare(row.label, "Whole board", label + " label")
    compare(row.depth, 0, label + " depth")
  }

  function test_dispatch_targets_board_first() {
    // synthetic: one milestone with one story holding one todo subtask
    var roots = [tnode("m1", "todo", [tnode("s1", "todo", [tnode("t1", "todo")])])]
    var cardMap = Board.indexTree(roots).cardMap
    var rows = Runs.dispatchTargets(roots, cardMap)
    compare(rows.length, 4, "the Whole board and three cards")
    checkWholeBoard(rows[0], "row 0")
    for (var i = 1; i < rows.length; i++)
      compare(Object.keys(rows[i]).sort().join(","), "card,depth,key,label,level", "row " + i + " keys")
  }

  function test_dispatch_targets_tree_order_and_depth() {
    // synthetic: two milestones, each with two stories, each story with two todo subtasks;
    // t1 holds one todo card at depth 3
    var roots = [tnode("m1", "todo", [tnode("s1", "todo", [tnode("t1", "todo", [tnode("u1", "todo")]), tnode("t2", "todo")]),
                                      tnode("s2", "todo", [tnode("t3", "todo"), tnode("t4", "todo")])]),
                 tnode("m2", "todo", [tnode("s3", "todo", [tnode("t5", "todo"), tnode("t6", "todo")]),
                                      tnode("s4", "todo", [tnode("t7", "todo"), tnode("t8", "todo")])])]
    var cardMap = Board.indexTree(roots).cardMap
    var rows = Runs.dispatchTargets(roots, cardMap)
    compare(targetKeys(rows), "board,card:m1,card:s1,card:t1,card:u1,card:t2,card:s2,card:t3,card:t4,"
            + "card:m2,card:s3,card:t5,card:t6,card:s4,card:t7,card:t8", "pre-order")
    var levels = ["milestone", "story", "subtask", "subtask"]
    for (var i = 1; i < rows.length; i++) {
      var card = cardMap[rows[i].key.substring("card:".length)]
      verify(rows[i].card === card, rows[i].key + " carries the node itself")
      compare(rows[i].depth, card.depth, rows[i].key + " depth")
      compare(rows[i].level, levels[card.depth], rows[i].key + " level")
    }
    compare(rows[4].level, "subtask", "a depth-3 card is a subtask")
    compare(rows[4].depth, 3, "at depth 3")
  }

  function test_dispatch_targets_finished_omitted() {
    var finished = ["done", "merged", "canceled", "archived"]
    for (var f = 0; f < finished.length; f++) {
      var st = finished[f]
      // synthetic: a finished milestone over a todo story and subtask; a todo milestone over a
      // finished story with a todo subtask, and over a todo story whose only subtask is finished
      var roots = [tnode("m1", st, [tnode("s1", "todo", [tnode("t1", "todo")])]),
                   tnode("m2", "todo", [tnode("s2", st, [tnode("t2", "todo")]),
                                        tnode("s3", "todo", [tnode("t3", st)])])]
      var cardMap = Board.indexTree(roots).cardMap
      compare(targetKeys(Runs.dispatchTargets(roots, cardMap)), "board,card:s1,card:t1,card:m2,card:t2,card:s3", st)
    }
  }

  function test_dispatch_targets_only_todo_subtasks() {
    // synthetic: an in_progress milestone over a blocked story holding one subtask per status,
    // and an in_progress story; a blocked milestone
    var subtasks = [tnode("a", "in_progress"), tnode("b", "review"), tnode("c", "blocked"), tnode("d", ""),
                    { id: "e", title: "T e" }, tnode("f", "TODO"), tnode("g", "todo")]
    var roots = [tnode("m1", "in_progress", [tnode("s1", "blocked", subtasks), tnode("s2", "in_progress")]),
                 tnode("m2", "blocked")]
    var cardMap = Board.indexTree(roots).cardMap
    compare(targetKeys(Runs.dispatchTargets(roots, cardMap)), "board,card:m1,card:s1,card:g,card:s2,card:m2",
            "only the todo subtask; milestones and stories of any unfinished status")
  }

  function test_dispatch_targets_stories_included() {
    // synthetic: one milestone with one in_progress story
    var roots = [tnode("m1", "todo", [tnode("s1", "in_progress")])]
    var cardMap = Board.indexTree(roots).cardMap
    var rows = Runs.dispatchTargets(roots, cardMap)
    compare(targetKeys(rows), "board,card:m1,card:s1", "the story is listed")
    compare(rows[2].level, "story", "level")
    compare(rows[2].depth, 1, "depth")
    compare(rows[2].label, "Story \"T s1\" (milestone \"T m1\")", "label names its milestone")
    var bare = Runs.dispatchTargets(roots, undefined)
    compare(targetKeys(bare), "board,card:m1,card:s1", "still listed without a cardMap")
    compare(bare[2].label, "Story \"T s1\"", "label without its milestone")
  }

  function test_dispatch_targets_agree_with_dispatchPlan() {
    // synthetic: a milestone per status, a story per status under each, a subtask per status
    // under each story; under m0s0, cards with ids "-x", "" and 5, then one appended after
    // indexing, so it has no depth
    var statuses = ["todo", "in_progress", "review", "blocked", "", "TODO", undefined,
                    "done", "merged", "canceled", "archived"]
    var roots = []
    for (var i = 0; i < statuses.length; i++) {
      var stories = []
      for (var j = 0; j < statuses.length; j++) {
        var subtasks = []
        for (var k = 0; k < statuses.length; k++) subtasks.push(tnode("m" + i + "s" + j + "t" + k, statuses[k]))
        stories.push(tnode("m" + i + "s" + j, statuses[j], subtasks))
      }
      roots.push(tnode("m" + i, statuses[i], stories))
    }
    var odd = roots[0].children[0].children
    odd.push(tnode("-x", "todo"), tnode("", "todo"), tnode(5, "todo"))
    var cardMap = Board.indexTree(roots).cardMap
    odd.push(tnode("nodepth", "todo"))
    var rows = Runs.dispatchTargets(roots, cardMap)
    // 7 unfinished milestones, 11 * 7 unfinished stories, 121 todo subtasks
    compare(rows.length, 1 + 7 + 77 + 121, "row count")
    var rowed = {}
    for (var r = 1; r < rows.length; r++) {
      var plan = Runs.dispatchPlan(rows[r].card, cardMap)
      compare(plan.offered, true, rows[r].key + " offered")
      compare(plan.level, rows[r].level, rows[r].key + " level")
      compare(rows[r].label, Runs.dispatchLabel(rows[r].card, cardMap), rows[r].key + " label")
      rowed[rows[r].key] = true
    }
    var ids = Object.keys(cardMap)
    for (var c = 0; c < ids.length; c++) {
      var card = cardMap[ids[c]]
      if (rowed["card:" + card.id] === true) continue
      var p = Runs.dispatchPlan(card, cardMap)
      verify(!p.offered || (p.level === "subtask" && card.status !== "todo"),
             ids[c] + " has no row only when refused or a subtask that is not todo")
    }
    compare(rowed["card:-x"], undefined, "a flag-like id gives no row")
    compare(rowed["card:"], undefined, "an empty id gives no row")
    compare(rowed["card:5"], undefined, "a number id gives no row")
    compare(rowed["card:nodepth"], undefined, "a card without depth gives no row")
  }

  function test_dispatch_targets_empty_tree() {
    // synthetic: roots that hold no tree
    var empties = [[], undefined, null, "x", 5, {}]
    for (var e = 0; e < empties.length; e++) {
      var rows = Runs.dispatchTargets(empties[e], {})
      compare(rows.length, 1, "roots " + e + " gives one row")
      checkWholeBoard(rows[0], "roots " + e)
    }
    // synthetic: every card finished or a subtask that is not todo
    var roots = [tnode("m1", "done", [tnode("s1", "merged", [tnode("t1", "in_progress"), tnode("t2", "review")])]),
                 tnode("m2", "archived", [tnode("s2", "canceled")])]
    var cardMap = Board.indexTree(roots).cardMap
    var only = Runs.dispatchTargets(roots, cardMap)
    compare(only.length, 1, "no offered target gives one row")
    checkWholeBoard(only[0], "no offered target")
  }

  function test_dispatch_targets_garbage() {
    // synthetic: non-object roots around one milestone, depth set by hand
    var m = tnode("m1", "todo")
    m.depth = 0
    m.parentId = null
    var mixed = [null, "x", [], 5, m]
    var mixedBefore = JSON.stringify(mixed)
    compare(targetKeys(Runs.dispatchTargets(mixed, {})), "board,card:m1", "only the milestone")
    compare(JSON.stringify(mixed), mixedBefore, "mixed roots unchanged")

    // synthetic: children that are not an array
    var odd = [tnode("a", "todo", "x"), tnode("b", "todo", {}), tnode("c", "todo", null)]
    for (var o = 0; o < odd.length; o++) {
      odd[o].depth = 0
      odd[o].parentId = null
    }
    var oddBefore = JSON.stringify(odd)
    compare(targetKeys(Runs.dispatchTargets(odd, {})), "board,card:a,card:b,card:c", "each node listed, no children")
    compare(JSON.stringify(odd), oddBefore, "odd children unchanged")

    // synthetic: a story whose children hold its own milestone
    var cm = tnode("m1", "todo", [])
    var cs = tnode("s1", "todo", [cm])
    cm.depth = 0
    cm.parentId = null
    cs.depth = 1
    cs.parentId = "m1"
    cm.children.push(cs)
    compare(targetKeys(Runs.dispatchTargets([cm], { m1: cm, s1: cs })), "board,card:m1,card:s1", "a cycle lists each node once")

    // synthetic: one subtask object in two stories' children
    var shared = tnode("t1", "todo")
    var sharedRoots = [tnode("m1", "todo", [tnode("s1", "todo", [shared]), tnode("s2", "todo", [shared])])]
    var sharedMap = Board.indexTree(sharedRoots).cardMap
    var sharedBefore = JSON.stringify(sharedRoots)
    compare(targetKeys(Runs.dispatchTargets(sharedRoots, sharedMap)), "board,card:m1,card:s1,card:t1,card:s2",
            "a shared child is listed once, under its first parent")
    compare(JSON.stringify(sharedRoots), sharedBefore, "shared tree unchanged")

    // synthetic: two distinct stories with the same id
    var first = tnode("s1", "todo", [tnode("t1", "todo")])
    var twin = tnode("s1", "todo", [tnode("t2", "todo")])
    var twinRoots = [tnode("m1", "todo", [first, twin])]
    var twinMap = Board.indexTree(twinRoots).cardMap
    var twinRows = Runs.dispatchTargets(twinRoots, twinMap)
    compare(targetKeys(twinRows), "board,card:m1,card:s1,card:t1,card:t2", "the first twin only, the later twin's children walked")
    verify(twinRows[2].card === first, "the first twin's node")

    // synthetic: a milestone whose id is "board"
    var boardRoots = [tnode("board", "todo")]
    var boardRows = Runs.dispatchTargets(boardRoots, Board.indexTree(boardRoots).cardMap)
    compare(targetKeys(boardRows), "board,card:board", "a card id board is not the Whole board")
    compare(boardRows[1].level, "milestone", "it is a milestone")
    compare(boardRows[1].label, "Milestone \"T board\"", "with its own label")

    // synthetic: cardMaps that are not a plain map, and one owning a __proto__ entry
    var tree = [tnode("m1", "todo", [tnode("s1", "todo", [tnode("t1", "todo")])])]
    Board.indexTree(tree)
    var protoMap = {}
    Object.defineProperty(protoMap, "__proto__", { value: tnode("__proto__", "todo"), enumerable: true })
    var maps = [null, "x", [], protoMap]
    for (var p = 0; p < maps.length; p++)
      compare(targetKeys(Runs.dispatchTargets(tree, maps[p])), "board,card:m1,card:s1,card:t1", "cardMap " + p)
  }

  function test_dispatch_targets_deep_chain() {
    // synthetic: a chain of 5000 todo cards, each the only child of the previous; depth and
    // parentId set by hand, as Board.indexTree recurses past the call stack at this depth
    var chain = []
    var cardMap = {}
    for (var i = 0; i < 5000; i++) {
      var c = tnode("c" + i, "todo", [])
      c.depth = i
      c.parentId = i === 0 ? null : "c" + (i - 1)
      if (i > 0) chain[i - 1].children.push(c)
      chain.push(c)
      cardMap[c.id] = c
    }
    var roots = [chain[0]]
    var rows = Runs.dispatchTargets(roots, cardMap)
    compare(rows.length, 5001, "the Whole board and every card")
    checkWholeBoard(rows[0], "row 0")
    compare(rows[1].level, "milestone", "c0")
    compare(rows[2].level, "story", "c1")
    for (var r = 1; r < rows.length; r++) {
      compare(rows[r].key, "card:c" + (r - 1), "row " + r + " key")
      if (r >= 3) compare(rows[r].level, "subtask", "row " + r + " level")
    }
  }

  function test_dispatch_targets_fresh() {
    // synthetic: one milestone with one story
    var roots = [tnode("m1", "todo", [tnode("s1", "todo")])]
    var cardMap = Board.indexTree(roots).cardMap
    var a = Runs.dispatchTargets(roots, cardMap)
    var b = Runs.dispatchTargets(roots, cardMap)
    verify(a !== b, "a new array each call")
    compare(a.length, b.length, "same rows")
    for (var i = 0; i < a.length; i++) verify(a[i] !== b[i], "row " + i + " is a new object")
    verify(a[1].card === roots[0], "row 1 carries the milestone node")
    verify(b[2].card === roots[0].children[0], "row 2 carries the story node")
    a[0].label = "changed"
    checkWholeBoard(Runs.dispatchTargets(roots, cardMap)[0], "after a caller edits a row")
  }
```

Notes for the engineer:
- `checkWholeBoard` is shared by tests 1, 7, 9 and 10 so the Whole board row is pinned the same way everywhere.
- `test_dispatch_targets_deep_chain` sets `depth`, `parentId` and the `cardMap` by hand: `Board.indexTree` throws `Maximum call stack size exceeded` on a 5000-deep chain under qmltestrunner (verified). Do not switch it back to `indexTree`.
- The cycle case in `test_dispatch_targets_garbage` also sets depths by hand, because `Board.indexTree` never ends on a cycle. The shared-child and twin cases use `indexTree`, which handles them.
- `protoMap` uses `Object.defineProperty` so it really owns a `__proto__` key (an object literal `{ __proto__: ... }` would set the prototype instead).
- Expected count in `test_dispatch_targets_agree_with_dispatchPlan`: 11 statuses, 7 of them unfinished (`todo`, `in_progress`, `review`, `blocked`, `""`, `TODO`, missing). Milestones: 7. Stories: 11 milestones x 7 = 77 (a story under a finished milestone still counts). Subtasks: 121 stories x 1 `todo` each = 121. The four odd cards under `m0s0` give none. Total 1 + 7 + 77 + 121 = 206.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bash tests/run.sh domain/tst_runs`
Expected: exit non-zero; the ten `test_dispatch_targets_*` functions FAIL with `Uncaught exception: Property 'dispatchTargets' of object [object Object] is not a function`; every other test in the file still passes (`Totals: 209 passed, 10 failed`).

- [ ] **Step 4: Write the implementation**

In `core/domain/runs.js`, insert after the closing `}` of `dispatchLabel` (line 1179) and before the `// The branch-prefix stem of a milestone title` comment, with one blank line on each side:

```js
// The dispatch dialog's step-2 rows for one project's brd tree:
// { key, level, card, label, depth }. roots: brd tree's top-level cards after
// Board.indexTree; cardMap: its {id: card} map, passed to dispatchPlan and
// dispatchLabel and not read otherwise.
// Row 0 is always { key: "board", level: "board", card: "board", label:
// "Whole board", depth: 0 }. Then the forest depth-first, pre-order, roots and
// children in array order (non-array roots or children count as none). A node
// that is not a plain object gives no row and no children; a node object
// reached again is skipped with its subtree. A node gives a row when
// dispatchPlan offers it at level milestone or story, or at level subtask with
// status exactly "todo", and no earlier row has its id. Children are walked
// whether or not their parent gives a row.
// key "card:" + id; level the plan's level; card the node itself; label
// dispatchLabel(card, cardMap); depth the card's depth.
// Returns new rows in a new array. Never mutates, never throws.
function dispatchTargets(roots, cardMap) {
  var rows = [{ key: "board", level: dispatchPlan("board").level, card: "board", label: dispatchLabel("board"), depth: 0 }]
  var visited = []
  var ids = []
  var stack = _arrayOr(roots).slice().reverse()
  while (stack.length > 0) {
    var card = stack.pop()
    if (!_isObject(card) || visited.indexOf(card) >= 0) continue
    visited.push(card)
    var children = _arrayOr(card.children)
    for (var i = children.length - 1; i >= 0; i--) stack.push(children[i])
    var plan = dispatchPlan(card, cardMap)
    if (!plan.offered || (plan.level === "subtask" && card.status !== "todo")) continue
    if (ids.indexOf(card.id) >= 0) continue
    ids.push(card.id)
    rows.push({ key: "card:" + card.id, level: plan.level, card: card, label: dispatchLabel(card, cardMap), depth: card.depth })
  }
  return rows
}
```

How it meets the spec:
- The stack starts as a reversed copy of `roots`, and each node pushes its children in reverse, so popping gives pre-order with siblings in array order. `_arrayOr` turns non-array `roots` or `children` into `[]`; `.slice()` keeps `roots` itself untouched.
- `visited` holds node objects (compared with `===` through `indexOf`): a node reached a second time is skipped before its children are pushed, so cycles and shared children end.
- Children are pushed before the keep test, so a refused or finished parent never hides its descendants.
- `ids` holds the ids already given a row; a later twin is skipped, but its children were already pushed.
- The Whole board row is built inside the call, so every call returns a fresh object.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/run.sh domain/tst_runs`
Expected: `Totals: 219 passed, 0 failed` for `tests/core/domain/tst_runs.qml`, no `TypeError`/`ReferenceError`/`is not a function` lines, exit 0.

- [ ] **Step 6: Run the full gate**

Run: `bash tests/run.sh`
Expected: pytest all passed (including `tests/architecture`), every QML file `0 failed`, exit 0.

- [ ] **Step 7: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): dispatchTargets lists a project's dispatch targets in tree order"
```
<!-- task-pipeline: validated -->
