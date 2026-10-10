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
