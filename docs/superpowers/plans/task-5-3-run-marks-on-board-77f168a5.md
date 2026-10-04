<!-- task-pipeline: validated -->
# 5.3 Run marks on Board, Graph and card detail (card 77f168a5)

Narrows `2026-10-03-am-run-monitor-design.md` § "On existing screens (additions only)" to one subtask. Parent: 8bb02694 "Runs screens and integration". Builds on the 5.2 worktree state (branch `mon/task-5-2-rundetailscreen-a3fe1e6a`, 51000ac). This worktree already holds that state. Paths below are relative to the worktree root.

## Scope

In scope:

1. **Board.** Each `BoardCard` in `ui/screens/BoardScreen.qml` that a run touches gets a `UI.RunBadge`. On a subtask (depth >= 2) the badge shows the glyph plus the current phase. On a milestone or story (depth 0/1) it shows `counts` from `Runs.rollup`. Milestone and story cards also get a `UI.RunRollupBar` under the title.
2. **Graph.** Story and milestone nodes in `ui/components/GraphView.qml` (milestoneDelegate, storyDelegate) get a `RunBadge` and a `RunRollupBar` under the node title. The story node's `StatusPips` rings the pip of each subtask whose run state is live `running`.
3. **StatusPips.** Add one new optional input, `ringedIds` (array of pip ids, default `[]`). A ringed pip gets a border on the existing pip Rectangle; this adds no new rectangle and no new `radius: height / 2`. With the default, the output is unchanged.
4. **Card detail.** `ui/screens/CardDetailScreen.qml` gets a **RUNS** `PanelSectionHeader` and one row per run that touches the card, newest first. Each row shows the state glyph, `Runs.runTitle` / `shortId`, `Runs.currentPhase` and `Runs.runAgeText`. Clicking a row calls `navigator.openRun(id)`. It reuses `UI.ListRow`, `ThemedText` and `RunBadge` and adds no new pill.
5. **Domain helper.** Add `Runs.runsTouching(runs, cardId)` to `core/domain/runs.js`. It is a public wrapper over `_touches` that returns the runs in input order and `[]` for a bad id or bad input. The file has no public helper that does this today.
6. **Return path.** Run detail opened from card detail goes Back to that card, not to the Runs list. This mirrors `issueReturnMode`:
   - Add `runReturnMode: "runs" | "entry"` on NavigationStore.
   - `openRun` takes an optional `from`. It sets `runReturnMode = from === "entry" ? "entry" : "runs"` on every call (so a Runs-list open always resets it). With `from === "entry"` it does not `pushReturn`.
   - `goBack` in `"run"` mode with `runReturnMode === "entry"` clears `selectedRunId`, restores `viewMode = "entry"` on the same `selectedCardId` (cursor 0, scroll top) and resets the mode to `"runs"`.
   - The existing Runs-list path is unchanged.

Out of scope: RunIndicator/toolbar, docs (5.4), RunsScreen/sidebar (5.1), RunDetailScreen body (5.2), `Board.subtreeCounts` and the existing "n/m done" text (both unchanged), and milestone group boxes in the story-mode graph. Keyboard cursor reach of the RUNS rows is also out: `board.detailLinkList` stays brd-only and RUNS rows are mouse-activated (`rowIndex: -1`). This is flagged as an open question below.

## Observable behaviour

- **Data flow and layers.** Screens read `app.runs.runs`, `app.runs.amStatus` and `app.runs.stale` via `app`. GraphScreen computes the marks and passes them to GraphView as new props, because GraphView has no `app`:
  - `runMarks`: map cardId → `cardRunState`.
  - `runRollups`: map cardId → `rollup`.
  - `runRinged`: array of subtask ids.

  No file under `ui/screens/**` or `ui/components/**` imports `core/stores`. Screens may import `core/domain/runs.js`.
- **Run state comes from am only.** Use `Runs.cardRunState(runs, card.id)` and `Runs.rollup(runs, card)`, never brd status.
  - A card with `state === "none"` and a zero rollup total shows no badge and no bar. `RunRollupBar` hides itself at `total === 0`.
  - `cardRunState().state` is only `running | dead | parked | escalated | none`; it is never `done` or `cancelled`. A subtask whose winning run is finished therefore shows no badge. Only parked/escalated runs are "dimmed" winners among subtasks (a parent in a finished run still gets a counts badge from `rollup`, whose `done` count is non-zero).
  - A `dimmed` winner renders the badge with reduced opacity and does not pulse (`active: false`). `RunBadge` binds its own `opacity` to its Pulse, so a screen must not assign `opacity` on the `RunBadge` itself; apply dimming (dimmed or `stale`) through an enclosing wrapper Item's `opacity` (as `RunsScreen` does for `stale`).
- **brd-status gate (visibility only).** Cards whose brd status is `merged` or `canceled` (or `archived`, if brd reports it) get no badge and no rollup bar on Board or Graph. `cardRunState` and `rollup` take no brd status (`(runs, cardId)` / `(runs, card)`), so the screen must apply this gate. It decides visibility only and is never used to derive a run state. The Card detail RUNS list is not gated, because it is history.
- **am missing / stale.**
  - With `amStatus === "missing"`: no badges, no bars, no rings, and no RUNS section.
  - With `stale === true`: marks are drawn dimmed.
  - In both cases the screens render normally otherwise.
- **Visual channel.**
  - States are shown with a glyph from `runGlyphs.js` plus the ring. Colour is never the only signal.
  - Escalated uses `theme.urgent`. Neither `#9b72cf` nor `#d9534f` is used.
  - There is no new animation loop. `RunBadge` uses its own Pulse, which runs only when the badge is visible and `active`. StatusPips' pulse is unchanged.
- **RUNS section.**
  - The header is hidden when no run touches the card.
  - Clicking a row whose run id has vanished does nothing, because `openRun` returns early.
  - Back from that Run detail lands on the same card.
  - While in Run detail opened from a card, `nav.section` is `"runs"` (sidebar and the first crumb read Runs); clicking that crumb calls `goBack()` and so also lands on the card. This is accepted, not changed here.
  - Back again from the card follows the card's original return (list or graph), which this card does not change.
- **Stable objectNames.**
  - Reused: `runBadge`, `runBadgeText`, `runRollupBar`, `runRollupRunning/Parked/Escalated/Done/Pending`.
  - New: `cardRunsHeader`, `cardRunRow<n>`, and `statusPip<id>` (unchanged) with a readable `ringed` property.

## Error paths

- Malformed or empty `runs`, a non-object card, or an unknown id: the helpers return `none` / zero / `[]`, and the screens draw nothing extra.
- A card that a run touches only through `rows` (not its tree) is not "touched", per `_touches`.
- A missing `ringedIds` or a non-array value is treated as `[]`.

## Tests (written first)

Placement follows docs/architecture.md "Tests": by layer, mirroring source paths.

| Test | File | Tier (per rule) |
|---|---|---|
| `runsTouching`: milestone/story/subtask match, rows-only does not match, input order kept, bad id/input → `[]` | tests/core/domain/tst_runs.qml (extend) | pure domain helper |
| StatusPips: default draws no ring; `ringedIds` rings only listed pips; existing pulse cases unchanged | tests/ui/components/tst_status_pips.qml (extend) | shared component |
| GraphView: `runMarks`/`runRollups`/`runRinged` props draw a badge and bar on story and milestone nodes; empty props draw none | tests/ui/tst_graph_view.qml (extend, at its existing location) | shared component test as it sits today |
| BoardScreen: subtask card shows glyph+phase; story/milestone card shows counts and bar; untouched card shows none; merged/canceled card shows none even when touched; dimmed winner dimmed and not pulsing; `amStatus: missing` hides all; `stale` dims | tests/ui/screens/tst_board_screen.qml (extend) | screen |
| GraphScreen: passes the run props to GraphView from `app.runs`; the gate and `missing` apply | tests/ui/screens/tst_graph_screen.qml (extend) | screen |
| CardDetailScreen: RUNS header and rows (state, phase, age) for touching runs; hidden when none or am missing; row click calls `navigator.openRun(id, "entry")` | tests/ui/screens/tst_card_detail_screen.qml (extend) | screen |
| Navigator: `openRun(id, "entry")` sets `runReturnMode`, skips `pushReturn`; `goBack` returns to the card; default path still restores the Runs list | tests/ui/tst_navigator.qml (extend) | cross-screen navigation (existing location) |
| Flow: board → card → run row → Run detail → Back lands on the card; badges on the board reflect the run | tests/ui/tst_board_flow.qml (extend) | cross-screen user flow |
| Flow: graph node shows badge, rollup and ringed pip for a running subtask | tests/ui/tst_graph_flow.qml (extend) | cross-screen user flow |
| Layer, duplicate and glyph rules still pass (no store import in screens/components, no second `radius: height / 2`, `bordered: true` or `CursorSurface {`, glyphs valid) | tests/architecture/test_layers.py, test_icon_glyphs.py (run, not changed) | architecture |

## Open questions / notes for the plan stage

- Keyboard reach of the RUNS rows would mean `Navigator.currentList()` appending run rows for `"entry"`, plus an `activateCursor` branch. That goes beyond "minimal", so it is deferred unless the plan stage finds it cheap.
- The upstream exploration summary was truncated at 8000 characters, mid-way through the test-placement rule. The rest of that rule was taken from docs/architecture.md and the existing tests tree, not guessed.
- The "skip merged/canceled/archived" rule came from the exploration findings, but it does not appear in `2026-10-03-am-run-monitor-design.md`. Confirm it before implementing. No `archived` status exists in core/.

---

# 5.3 Run marks on Board, Graph and card detail: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show each card's am run state on the Board cards, the Graph's milestone and story nodes (with a ring on the pip of a running subtask), and as a RUNS list on card detail whose rows open Run detail and come Back to the card.

**Architecture:** One new pure helper (`Runs.runsTouching`) in `core/domain/runs.js`. One new presentational component, `ui/components/RunMark.qml`: the dimming wrapper Item around `RunBadge` that the spec requires, shared by Board and Graph so the "glyph+phase vs counts vs glyph" choice is written once. `StatusPips` gains `ringedIds`, and `GraphView` gains `runMarks`/`runRollups`/`runRinged`/`runStale` props. Screens read `app.runs` and apply the brd-status visibility gate. `NavigationStore.runReturnMode` and `Navigator.openRun(id, from)` give the card return path.

**Tech Stack:** QML (Qt 6 / Quickshell), `.pragma library` JS domain modules, QtTest `TestCase` via `qmltestrunner`, pytest architecture tests. Everything runs through `bash tests/run.sh [substring-filter]` from the worktree root.

**Spec:** `docs/superpowers/specs/task-5-3-run-marks-on-board-77f168a5-design.md` (prepended verbatim above).

**Worktree / branch:** `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-3-run-marks-on-board-77f168a5`, branch `mon/task-5-3-run-marks-on-board-77f168a5`, cut from `mon/task-5-2-rundetailscreen-a3fe1e6a`. Run every command from the worktree root. Nothing from any other subtask beyond 5.1/5.2 exists here.

## Plan-stage decisions (read before Task 1)

1. **Board cards are always depth 0.** `BoardStore.boardColumn` lists `visibleBoardRoots` only, so the spec's "subtask (depth >= 2)" case never reaches the Board through depth alone. The plan treats a card as a subtask when `depth >= 2` OR when its winning run lists it as a subtask (`cardRunState().phase !== ""`). That decision comes only from am data. A root card that am runs as a subtask therefore shows glyph + phase. Every other root card shows counts, falling back to the run's glyph when it has no non-zero count.
2. **"Ring on the active pip".** `cardRunState(runs, subtaskId).state === "running"` is true for every subtask of a live run, including its pending ones. The plan rings a pip only when that state is `running` AND the subtask's own am rows put it in the running bucket (`Runs.rollup(runs, {id}).running > 0`). Both values come from am alone, never from brd.
3. **`RunMark.qml` (new shared component)** is the "enclosing wrapper Item" the spec requires for dimming. It is shared so that Board and Graph do not each carry a copy of the badge-mode logic. It gets its own component test at `tests/ui/components/tst_run_mark.qml`. 5.4 (docs) should list it next to `RunBadge` in docs/architecture.md.
4. **`GraphView.runStale`** is a fourth prop next to the spec's three. `stale` has to reach the nodes to dim them, and GraphView has no `app`.
5. **The brd-status gate** (merged/canceled/archived) is implemented as the spec states. The spec flagged it "confirm before implementing". The relayed user request ("Yes to all three, build the button") is taken as that confirmation, but it does not say which three questions it answers. The gate is one small function per screen (`BoardScreen.hidesRunMarks`, `GraphScreen.hidesRunMarks`), so it is cheap to drop if the user says otherwise.
6. **Keyboard reach of RUNS rows** stays deferred, as the spec says. The rows keep `index: -1`.
7. **Upstream truncation.** The orchestrator's spec summary and exploration findings both reached this stage truncated (at 2000 and 8000 characters). The plan works from the spec file on disk and from the source code, not from the missing text.

## Global Constraints

- `ui/screens/**` and `ui/components/**` never import `core/stores` (tests/architecture/test_layers.py `violations_screen`). They may import `core/domain/*.js`.
- No new copy of `radius: height / 2`, `bordered: true`, `font.family:`, `CursorSurface {` or `Qt.rgba(0, 0, 0, 0.55)` outside the allowlists in tests/architecture/test_layers.py `GUARDS`.
- No new QML type name may clash with a shell (`qs.Ui`) or QtQuick/Controls type. `RunMark` does not clash.
- Glyphs come only from `ui/components/runGlyphs.js`: ⟳ ⏸ ‼ ✖ ⊘ ✔ (plain BMP). No Nerd Font code points are added.
- Run state is never derived from brd status. brd status only gates visibility (merged/canceled/archived) on Board and Graph.
- Escalated reads in `theme.urgent`. `#9b72cf` and `#d9534f` are never used for run states.
- No second animation loop. Only `RunBadge`'s own Pulse and `StatusPips`' existing Pulse run.
- `RunBadge.opacity` is never assigned by an owner; dimming goes on a wrapper (`RunMark`, `ListRow`, `RunRollupBar`).
- `amStatus === "missing"`: no badge, no bar, no ring, no RUNS section. `stale`: marks dimmed (opacity 0.5) and not pulsing.
- `tests/run.sh` fails a QML file on any `TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function` in its output. Every new binding must be null-safe.

## Review Focus

Five inputs or failure modes the spec implies but does not test directly. Each one has a test in the task named after it.

1. **The card disappears from the board while its Run detail is open.** This can happen when a brd refresh drops the card while the run view shows. Back must not land on a blank card view; it should go on to the card's list. Covered in Task 8 by `test_back_from_a_card_run_whose_card_is_gone_returns_to_the_list`.
2. **A new run snapshot arrives while card detail is open.** The RUNS rows must follow it: the header hides when no run touches the card any more. Covered in Task 9 by `test_the_runs_section_follows_a_new_snapshot`.
3. **A live running card while the data is stale.** It must be dimmed and must not pulse, and it starts pulsing again once fresh. Covered in Task 4 (`test_stale_data_dims_and_stops_the_pulse`) and Task 7 (`test_stale_run_data_dims_the_marks`).
4. **Run props of the wrong shape, or inherited names, reaching GraphView** (`null`, a string, an array, a node id such as `constructor`). These must draw nothing and must not throw. Covered in Task 5 by `test_run_props_of_the_wrong_shape_draw_nothing`.
5. **A dead run (started, lease lost) on a subtask.** It must read ✖ with its phase and must not pulse. Covered in Task 4 by `test_a_dead_subtask_reads_dead_and_does_not_pulse`.

## File structure

| File | Change | Responsibility |
|---|---|---|
| `core/domain/runs.js` | modify | add `runsTouching(runs, cardId)` |
| `ui/components/StatusPips.qml` | modify | `ringedIds` input; per-pip `ringed` + border |
| `ui/components/RunMark.qml` | create | dimming wrapper + badge-mode choice around `RunBadge` |
| `ui/components/GraphView.qml` | modify | `runMarks`/`runRollups`/`runRinged`/`runStale` props; mark + bar on both node delegates; `ringedIds` on pips |
| `ui/screens/GraphScreen.qml` | modify | compute the run props from `app.runs` + the gate |
| `ui/screens/BoardScreen.qml` | modify | mark + bar on `BoardCard`; the gate |
| `core/stores/NavigationStore.qml` | modify | `runReturnMode` |
| `ui/Navigator.qml` | modify | `openRun(id, from)`, `restoreCardFromRun()`, `goBack` branch |
| `ui/screens/CardDetailScreen.qml` | modify | RUNS header + `CardRunRow` rows |
| `tests/core/domain/tst_runs.qml` | extend | `runsTouching` |
| `tests/ui/components/tst_status_pips.qml` | extend | ring |
| `tests/ui/components/tst_run_mark.qml` | create | RunMark |
| `tests/ui/tst_graph_view.qml` | extend | node marks/rings |
| `tests/ui/screens/tst_graph_screen.qml` | extend | wiring + gate |
| `tests/ui/screens/tst_board_screen.qml` | extend | card marks |
| `tests/core/stores/tst_navigation_store.qml` | extend | `runReturnMode` default |
| `tests/ui/tst_navigator.qml` | extend | return path |
| `tests/ui/screens/tst_card_detail_screen.qml` | extend | RUNS section |
| `tests/ui/tst_board_flow.qml` | extend | flow |
| `tests/ui/tst_graph_flow.qml` | extend | flow |

---

### Task 1: Flow tests first (RED, committed red)

The card asks for the UI flow tests to be written first. They stay red until Task 10 turns them green. They are committed now, so the order of the work is visible in the history.

**Files:**
- Modify: `tests/ui/tst_board_flow.qml`
- Modify: `tests/ui/tst_graph_flow.qml`

**Interfaces:**
- Consumes: nothing new; they call the API later tasks add: `RunMark` objectName `runMark`, `RunBadge` `runBadge`, `cardRunsHeader`, `cardRunRow0`, `GraphView.runRinged`, `statusPip<id>.ringed`, `nav.runReturnMode`.
- Produces: two red tests that Task 10 must turn green.

- [ ] **Step 1: Add the board flow test**

In `tests/ui/tst_board_flow.qml`, add the helper import under `import QtTest`:

```qml
import QtQuick
import QtTest
import "../helpers/find.js" as H
```

Then make the `TestCase` visible: add `visible: true` right after its `when: windowShown` line. Without it the whole Panel tree is not visible, so every `.visible` check below reads false (verified: the badge reads `⟳ 1` but `visible` is false all the way up to the TestCase). The existing tests in the file do not read `.visible`, so they are unaffected.

```qml
  when: windowShown
  visible: true
```

Then add these functions inside the `TestCase`, after `test_board_and_detail_flow` (before the final `}`):

```qml
  // ---- am run marks (5.3)

  // A normalised run (runs.js normalizeRun's shape), built directly.
  function mkRun(id, status, live, milestone, tree, rows) {
    return { id: id, repo_dir: "/x", milestone_id: milestone, status: status, started_at: "",
             base_branch: "", branch_prefix: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: rows || [], tree: tree || { stories: [], subtasks: [] } }
  }
  function allNamed(item, name, out) {
    out = out || []
    if (!item) return out
    if (item.objectName === name) out.push(item)
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) allNamed(kids[i], name, out)
    return out
  }
  // The text of every run badge actually on screen.
  function shownBadges(p) {
    return allNamed(p, "runBadge").filter(function(b) { return b.visible }).map(function(b) { return b.text })
  }

  function test_a_run_marks_the_board_and_its_card_row_opens_run_detail_and_comes_back() {
    var host = createTemporaryObject(hostC, testCase)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([{ root_path: "/x", name: "proj" }])
    // The export and the runs snapshot cannot run here: disarm them so their
    // late replies change nothing.
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.extras.extrasLoading = false
    p.app.runs.snapshotRunner.cancel()
    var t1 = card("t1", "Task1", "in_progress")
    var s1 = card("s1", "Story", "in_progress", [t1])
    var m1 = card("m1", "Milestone", "in_progress", [s1])
    var x1 = card("x1", "Ex", "done")
    p.app.board.applyTreeData([m1, x1])
    p.app.runs.runs = [mkRun("run-0000000000a1", "started", true, "m1",
      { stories: [{ card_id: "s1", subtasks: ["t1"] }],
        subtasks: [{ card_id: "t1", phases: [{ name: "implement", status: "started" }] }] },
      [{ card_id: "t1", status: "running" }])]
    wait(50)
    compare(shownBadges(p).join(","), "⟳ 1", "the milestone the run heads carries its counts, and nothing else does")

    p.navigator.openCard("m1")
    wait(50)
    compare(H.find(p, "cardRunsHeader").visible, true)
    var row = H.find(p, "cardRunRow0")
    verify(row, "the card lists the run")
    row.activated()
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000a1")
    compare(p.app.nav.runReturnMode, "entry")

    p.navigator.goBack()
    compare(p.app.nav.viewMode, "entry", "Back from that run lands on the card")
    compare(p.app.board.selectedCardId, "m1")
    p.navigator.goBack()
    compare(p.app.nav.viewMode, "board", "and Back again reaches the board")
  }
```

- [ ] **Step 2: Add the graph flow test**

In `tests/ui/tst_graph_flow.qml`, add the import under `import QtTest`:

```qml
import QtQuick
import QtTest
import "../helpers/find.js" as H
```

Then make the `TestCase` visible the same way (`visible: true` right after `when: windowShown`; the `.visible` checks below need it), and add these functions inside the `TestCase`, before the final `}`:

```qml
  // ---- am run marks (5.3)

  function mkRun(id, status, live, milestone, tree, rows) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: milestone, status: status, started_at: "",
             base_branch: "", branch_prefix: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: rows || [], tree: tree || { stories: [], subtasks: [] } }
  }

  function test_a_story_node_shows_the_run_badge_the_rollup_and_the_ringed_pip() {
    var p = make(); if (!p) return
    p.app.runs.snapshotRunner.cancel()
    p.app.board.applyTreeData([card("m1", "in_progress",
      [card("s1", "in_progress", [card("t1", "in_progress"), card("t2", "todo")])])])
    p.app.runs.runs = [mkRun("run-0000000000a1", "started", true, "m1",
      { stories: [{ card_id: "s1", subtasks: ["t1", "t2"] }],
        subtasks: [{ card_id: "t1", phases: [{ name: "implement", status: "started" }] },
                   { card_id: "t2", phases: [] }] },
      [{ card_id: "t1", status: "running" }, { card_id: "t2", status: "pending" }])]
    p.navigator.showSection("graph")
    find(p, "graphViewChips").chosen("story")
    wait(200)
    var gv = H.find(p, "graphView")
    compare(gv.runRinged.join(","), "t1", "only the subtask am is working on is ringed")
    var node = H.find(p, "graphNodes1")
    verify(node, "the story node is drawn")
    compare(H.find(node, "runMark").visible, true)
    compare(H.find(node, "runBadge").text, "⟳ 1")
    var bar = H.find(node, "runRollupBar")
    compare(bar.visible, true)
    compare(H.find(bar, "runRollupPending").text, "1 pending")
    compare(H.find(node, "statusPipt1").ringed, true)
    compare(H.find(node, "statusPipt2").ringed, false)
  }
```

- [ ] **Step 3: Run both and watch them fail**

Run: `bash tests/run.sh tst_board_flow` then `bash tests/run.sh tst_graph_flow`
Expected: both FAIL. Board flow: `FAIL!  : BoardFlow::test_a_run_marks_the_board_and_its_card_row_opens_run_detail_and_comes_back() Compared values are not the same` (actual `""`, expected `⟳ 1`). Graph flow: a `TypeError` on `gv.runRinged.join` (`runRinged` is undefined). `test_board_and_detail_flow` and the existing graph flow tests still PASS.

- [ ] **Step 4: Commit (red on purpose)**

```bash
git add tests/ui/tst_board_flow.qml tests/ui/tst_graph_flow.qml
git commit -m "test(5.3): flow tests for run marks on board, graph and card detail (red until the feature lands)"
```

---

### Task 2: `Runs.runsTouching` domain helper

**Files:**
- Modify: `core/domain/runs.js` (after `cardRunState`, which ends at line 167)
- Test: `tests/core/domain/tst_runs.qml` (append before the final `}` at line 1082)

**Interfaces:**
- Consumes: `_isCardId`, `_arrayOr`, `_touches` (runs.js:93, :82, :104).
- Produces: `Runs.runsTouching(runs, cardId) -> Array` returns the same run objects in input order, or `[]`.

- [ ] **Step 1: Write the failing test**

Append to `tests/core/domain/tst_runs.qml` before the closing `}` (the file already defines `mkRun`, `sampleTree` and `ids`):

```qml
  // ---- 5.3: the runs that touch one card (card detail's RUNS list) --------------------------

  function test_runs_touching() {
    var a = mkRun("ra", "started", true, { tree: sampleTree() })                 // m1; s1, s2; t1, t2, t3
    var b = mkRun("rb", "done", null, { milestone_id: "m2", rows: [{ card_id: "t1", status: "done" }] })
    var c = mkRun("rc", "stopped", null, { milestone_id: "m1" })
    var runs = [a, b, c]
    compare(ids(Runs.runsTouching(runs, "m1")), "ra,rc", "milestone, input order kept")
    compare(ids(Runs.runsTouching(runs, "s2")), "ra", "story")
    compare(ids(Runs.runsTouching(runs, "t3")), "ra", "subtask")
    compare(ids(Runs.runsTouching(runs, "m2")), "rb")
    compare(ids(Runs.runsTouching(runs, "t1")), "ra", "rb names t1 only in its rows: not a touch")
    verify(Runs.runsTouching(runs, "m1")[0] === a, "the same run objects, not copies")
    compare(Runs.runsTouching(runs, "zzz").length, 0, "unrelated")

    var badIds = ["", null, undefined, 5, {}, "integrate", "bases", "base-x"]
    for (var i = 0; i < badIds.length; i++)
      compare(Runs.runsTouching(runs, badIds[i]).length, 0, "bad id " + i)
    var badRuns = [undefined, null, "x", 5, {}, [null, 3, "s", []]]
    for (var j = 0; j < badRuns.length; j++)
      compare(Runs.runsTouching(badRuns[j], "m1").length, 0, "bad runs " + j)
  }
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash tests/run.sh tst_runs.qml`
Expected: FAIL in `DomainRuns::test_runs_touching()` with `TypeError: Property 'runsTouching' of object [object Object] is not a function`.

- [ ] **Step 3: Implement**

In `core/domain/runs.js`, insert directly after the closing `}` of `cardRunState` (line 167) and before the `// Which am row status lands in which rollup bucket` comment:

```js
// Every run that touches a card (through its milestone, a story or a subtask --
// never through rows alone), as the same objects in input order: am's order,
// newest first. [] for anything that is not a real card id, or for garbage runs.
function runsTouching(runs, cardId) {
  if (!_isCardId(cardId)) return []
  var list = _arrayOr(runs)
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (_touches(list[i], cardId)) out.push(list[i])
  }
  return out
}
```

- [ ] **Step 4: Run it and watch it pass**

Run: `bash tests/run.sh tst_runs.qml`
Expected: `Totals: N passed, 0 failed` for `tests/core/domain/tst_runs.qml`. pytest reports no failures.

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(5.3): Runs.runsTouching lists the runs that touch a card"
```

---

### Task 3: `StatusPips.ringedIds`

**Files:**
- Modify: `ui/components/StatusPips.qml:25` (after `property bool active: true`) and the pip delegate `:50-62`
- Test: `tests/ui/components/tst_status_pips.qml` (append before the final `}` at line 110)

**Interfaces:**
- Consumes: nothing new.
- Produces: `StatusPips.ringedIds: var` (default `[]`) and a `ringed: bool` on each pip delegate (`objectName: "statusPip" + id`). A ringed pip has `border.width === 2` and `border.color === palette.foreground`; an unringed pip has `border.width === 0`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/ui/components/tst_status_pips.qml` before the final `}`:

```qml
  // ---- 5.3: a ring on the pip of a subtask an am run is working on.

  function test_no_pip_is_ringed_by_default() {
    var pips = make([{ id: "t1", status: "done" }, { id: "t2", status: "in_progress" }])
    compare(pips.ringedIds.length, 0, "the input defaults to []")
    compare(H.find(pips, "statusPipt1").ringed, false)
    compare(H.find(pips, "statusPipt1").border.width, 0)
    compare(H.find(pips, "statusPipt2").border.width, 0, "the output is unchanged without it")
  }

  function test_ringed_ids_ring_only_the_listed_pips_with_the_pips_own_border() {
    var pips = make([{ id: "t1", status: "done" }, { id: "t2", status: "in_progress" }, { id: "t3", status: "todo" }])
    pips.ringedIds = ["t2", "zz"]
    wait(30)
    var t2 = H.find(pips, "statusPipt2")
    compare(t2.ringed, true)
    verify(t2.border.width > 0, "the ring is the pip's own border")
    verify(Qt.colorEqual(t2.border.color, pips.palette.foreground))
    compare(t2.radius, t2.height / 2, "still the same circle")
    compare(H.find(pips, "statusPipt1").ringed, false)
    compare(H.find(pips, "statusPipt1").border.width, 0)
    compare(H.find(pips, "statusPipt3").border.width, 0)
    compare(pips.pulsing, true, "the ring adds no animation of its own")
    pips.ringedIds = []
    wait(30)
    compare(H.find(pips, "statusPipt2").ringed, false)
    compare(H.find(pips, "statusPipt2").border.width, 0)
  }

  function test_a_ringed_ids_value_that_is_not_an_array_rings_nothing() {
    var pips = make([{ id: "t1", status: "in_progress" }])
    var bad = [null, undefined, "t1", 5, { t1: true }]
    for (var i = 0; i < bad.length; i++) {
      pips.ringedIds = bad[i]
      wait(10)
      compare(H.find(pips, "statusPipt1").ringed, false, "bad " + i)
      compare(H.find(pips, "statusPipt1").border.width, 0, "bad " + i)
    }
  }
```

- [ ] **Step 2: Run them and watch them fail**

Run: `bash tests/run.sh tst_status_pips`
Expected: FAIL. `pips.ringedIds` is undefined (`TypeError: Cannot read property 'length' of undefined`), and `.ringed` reads `undefined` instead of `false`.

- [ ] **Step 3: Implement**

In `ui/components/StatusPips.qml`, after `property bool active: true` (line 25) add:

```qml
  // Pip ids to ring: the subtasks an am run is working on right now (GraphView
  // hands them down from GraphScreen). The ring is the pip's own border, so a
  // run never reads by colour alone and no second circle is drawn. Anything but
  // an array rings nothing.
  property var ringedIds: []
  readonly property var ringedList: Array.isArray(pips.ringedIds) ? pips.ringedIds : []
```

In the pip delegate, replace:

```qml
      objectName: "statusPip" + (pip.modelData ? pip.modelData.id : "")
      width: Style.space(8)
      height: width
      radius: height / 2
```

with:

```qml
      readonly property bool ringed: !!pip.modelData && pips.ringedList.indexOf(pip.modelData.id) >= 0

      objectName: "statusPip" + (pip.modelData ? pip.modelData.id : "")
      width: Style.space(8)
      height: width
      radius: height / 2
      border.width: pip.ringed ? 2 : 0
      border.color: pips.palette ? pips.palette.foreground : Color.foreground
```

(`radius: height / 2` stays a single occurrence in the file, so the architecture guard still passes.)

- [ ] **Step 4: Run them and watch them pass**

Run: `bash tests/run.sh tst_status_pips`
Expected: all StatusPips tests PASS, the existing pulse tests included. pytest (architecture) PASS.

- [ ] **Step 5: Commit**

```bash
git add ui/components/StatusPips.qml tests/ui/components/tst_status_pips.qml
git commit -m "feat(5.3): StatusPips rings the pips listed in ringedIds"
```

---

### Task 4: `RunMark` component

**Files:**
- Create: `ui/components/RunMark.qml`
- Test: `tests/ui/components/tst_run_mark.qml` (create; sibling of `tst_run_badge.qml`)

**Interfaces:**
- Consumes: `RunBadge` (`state`, `phase`, `counts`, `active`, `theme`; objectName `runBadge`, text child `runBadgeText`; `pulsing`), `RunGlyphs.glyphOf`, `RunGlyphs.countsText` (ui/components/runGlyphs.js).
- Produces: `RunMark` (objectName `runMark`) with inputs `theme: var`, `runState: var` (a `Runs.cardRunState` object or null), `rollup: var` (a `Runs.rollup` object or null), `subtask: bool`, `stale: bool`, `active: bool` (default true). Readonly outputs: `stateName: string`, `dimmed: bool`, `showCounts: bool`, `shown: bool`. Its `visible` is `shown`, and its `opacity` is `dimmed ? 0.5 : 1`.

- [ ] **Step 1: Write the failing test**

Create `tests/ui/components/tst_run_mark.qml`:

```qml
// tests/ui/components/tst_run_mark.qml
// ui/components/RunMark.qml: one card's am run mark as the Board and the Graph
// draw it -- a RunBadge inside the wrapper that dims it. A subtask shows its
// glyph and phase; a milestone or story its non-zero counts, else its run's
// glyph; nothing at all for no run. A dimmed winner or stale data is drawn at
// half opacity by the wrapper and never pulses.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "RunMark"
  when: windowShown
  visible: true
  width: 400; height: 200

  T.Theme { id: testTheme; foreground: "#eeeeee"; dim: "#777777"; urgent: "#ff3300" }

  Component { id: markC; UI.RunMark {} }

  function make(props) {
    var p = props || {}
    p.theme = testTheme
    var mark = createTemporaryObject(markC, tc, p)
    wait(30)
    return mark
  }
  // A Runs.cardRunState-shaped object.
  function st(state, opts) {
    var o = opts || {}
    return { state: state, runId: "r1", dimmed: o.dimmed === true, phase: o.phase || "", attempt: 0 }
  }
  // A Runs.rollup-shaped object.
  function counts(c) {
    return { running: c.running || 0, parked: c.parked || 0, escalated: c.escalated || 0,
             done: c.done || 0, pending: c.pending || 0, total: c.total || 0 }
  }
  function textOf(mark) { return H.find(mark, "runBadgeText").text }

  function test_a_subtask_shows_its_glyph_and_phase_and_pulses_while_running() {
    var mark = make({ runState: st("running", { phase: "implement" }), rollup: counts({ running: 1, total: 1 }), subtask: true })
    compare(mark.objectName, "runMark")
    compare(mark.visible, true)
    compare(textOf(mark), "⟳ implement", "a subtask never shows counts")
    compare(mark.opacity, 1)
    compare(H.find(mark, "runBadge").pulsing, true)
  }

  function test_a_dead_subtask_reads_dead_and_does_not_pulse() {
    var mark = make({ runState: st("dead", { phase: "review" }), subtask: true })
    compare(textOf(mark), "✖ review")
    compare(H.find(mark, "runBadge").pulsing, false)
  }

  function test_a_parent_shows_its_counts_and_never_pulses() {
    var mark = make({ runState: st("running"), rollup: counts({ running: 2, parked: 1, pending: 3, total: 6 }) })
    compare(mark.showCounts, true)
    compare(textOf(mark), "⟳ 2 ⏸ 1")
    compare(H.find(mark, "runBadge").pulsing, false)
  }

  function test_a_parent_without_counts_shows_its_runs_glyph() {
    var mark = make({ runState: st("escalated"), rollup: counts({ pending: 2, total: 2 }) })
    compare(textOf(mark), "‼", "pending alone has no count glyph: the run's state speaks")
    verify(Qt.colorEqual(H.find(mark, "runBadge").tint, testTheme.urgent), "escalated reads in urgent")
    var running = make({ runState: st("running"), rollup: counts({}) })
    compare(textOf(running), "⟳")
  }

  function test_nothing_to_show_hides_the_mark() {
    compare(make({}).visible, false, "no run state and no rollup")
    compare(make({ runState: st("none"), rollup: counts({}) }).visible, false)
    compare(make({ runState: st("none"), rollup: counts({ done: 2, total: 2 }), subtask: true }).visible, false,
            "a subtask whose run finished shows nothing")
    var garbage = [null, undefined, "running", 5, [], { state: 7 }]
    for (var i = 0; i < garbage.length; i++)
      compare(make({ runState: garbage[i], rollup: garbage[i] }).visible, false, "garbage " + i)
  }

  function test_a_dimmed_winner_is_drawn_at_half_opacity_by_the_wrapper() {
    var mark = make({ runState: st("parked", { dimmed: true, phase: "plan" }), subtask: true })
    compare(textOf(mark), "⏸ plan")
    compare(mark.dimmed, true)
    compare(mark.opacity, 0.5)
    compare(H.find(mark, "runBadge").active, false)
    compare(H.find(mark, "runBadge").opacity, 1, "the badge's own opacity is left to its pulse")
  }

  function test_stale_data_dims_and_stops_the_pulse() {
    var mark = make({ runState: st("running", { phase: "implement" }), subtask: true, stale: true })
    compare(mark.opacity, 0.5)
    compare(H.find(mark, "runBadge").pulsing, false)
    mark.stale = false
    wait(30)
    compare(mark.opacity, 1)
    compare(H.find(mark, "runBadge").pulsing, true)
  }

  function test_the_owner_can_switch_the_pulse_off() {
    var mark = make({ runState: st("running"), subtask: true, active: false })
    compare(H.find(mark, "runBadge").pulsing, false)
  }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash tests/run.sh tst_run_mark`
Expected: FAIL. `UI.RunMark` is not a type (`RunMark is not a type`), and every test fails.

- [ ] **Step 3: Implement**

Create `ui/components/RunMark.qml`:

```qml
import QtQuick
import "runGlyphs.js" as RunGlyphs

// One card's am run mark, as the Board and the Graph draw it: a RunBadge inside
// the wrapper that dims it. Presentation only: the owner hands in what runs.js
// said -- `runState` (cardRunState) and `rollup` (rollup), or null for "no
// mark" (a merged or canceled card, am not installed) -- and never brd status.
// A subtask shows its glyph and phase; a milestone or story its non-zero
// counts, else its run's glyph. A dimmed winner (a finished run speaking for
// the card) or stale run data is drawn at half opacity and never pulses. The
// dimming is this wrapper's: RunBadge's own opacity follows its Pulse.
Item {
  id: mark
  objectName: "runMark"

  property var theme: null
  property var runState: null
  property var rollup: null
  // Glyph and phase rather than counts.
  property bool subtask: false
  property bool stale: false
  // The owner's own "this is on screen" verdict, ANDed into the pulse.
  property bool active: true

  readonly property bool hasRunState: mark.runState !== null && mark.runState !== undefined
    && typeof mark.runState === "object"
  readonly property string stateName: mark.hasRunState && typeof mark.runState.state === "string" ? mark.runState.state : ""
  readonly property bool dimmed: mark.stale || (mark.hasRunState && mark.runState.dimmed === true)
  readonly property bool showCounts: !mark.subtask && RunGlyphs.countsText(mark.rollup) !== ""
  readonly property bool shown: mark.showCounts || RunGlyphs.glyphOf(mark.stateName) !== ""

  visible: mark.shown
  implicitWidth: badge.width
  implicitHeight: badge.height
  width: implicitWidth
  height: implicitHeight
  opacity: mark.dimmed ? 0.5 : 1

  RunBadge {
    id: badge
    theme: mark.theme
    state: mark.showCounts ? "" : mark.stateName
    phase: !mark.showCounts && mark.subtask && mark.hasRunState && typeof mark.runState.phase === "string"
      ? mark.runState.phase : ""
    counts: mark.showCounts ? mark.rollup : null
    active: mark.active && !mark.dimmed
  }
}
```

- [ ] **Step 4: Run it and watch it pass**

Run: `bash tests/run.sh tst_run_mark`
Expected: the `tests/ui/components/tst_run_mark.qml` Totals line reports `0 failed`, with all 8 `RunMark::test_*` functions passing. pytest (architecture: no type clash, no guard hit) PASS.

- [ ] **Step 5: Commit**

```bash
git add ui/components/RunMark.qml tests/ui/components/tst_run_mark.qml
git commit -m "feat(5.3): RunMark, the dimming wrapper around RunBadge shared by Board and Graph"
```

---

### Task 5: GraphView run props, node marks and rings

**Files:**
- Modify: `ui/components/GraphView.qml`: props after `cursorId` (:30); milestone title (:463-470) and the end of the progress Item (:496-499); story title (:541-548), the `StatusPips` (:554-566) and the end of the pips Item (:576-579)
- Test: `tests/ui/tst_graph_view.qml` (append before the final `}` at line 401)

**Interfaces:**
- Consumes: `UI.RunMark` (Task 4), `UI.RunRollupBar` (`rollup`, `theme`), `StatusPips.ringedIds` (Task 3).
- Produces: `GraphView.runMarks: var` (map id → cardRunState, default `({})`), `runRollups: var` (map id → rollup, default `({})`), `runRinged: var` (array of ids, default `[]`), `runStale: bool` (default false), `runMarkOf(id)`, `runRollupOf(id)`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/ui/tst_graph_view.qml` before the final `}`:

```qml
  // ---- 5.3: am run marks, handed in by GraphScreen.

  function runMark(state, dimmed) { return { state: state, runId: "r1", dimmed: dimmed === true, phase: "", attempt: 0 } }

  function test_run_marks_draw_a_badge_and_a_rollup_bar_on_a_milestone_node() {
    var v = createTemporaryObject(viewC, tc)
    v.nodes = nodes
    v.edges = edges
    v.runMarks = { m1: runMark("running") }
    v.runRollups = { m1: { running: 1, parked: 0, escalated: 0, done: 1, pending: 2, total: 4 } }
    wait(100)
    var first = find(v, "graphNodem1")
    var mark = find(first, "runMark")
    verify(mark, "the node carries a run mark")
    compare(mark.visible, true)
    compare(find(first, "runBadge").text, "⟳ 1 ✔ 1")
    var bar = find(first, "runRollupBar")
    compare(bar.visible, true)
    compare(find(bar, "runRollupPending").text, "2 pending")
    compare(find(first, "graphNodeTitle").text, "First", "the title stays")
    compare(find(first, "graphNodeProgress").text, "1/2 done", "and so does the brd progress")
    var second = find(v, "graphNodem2")
    compare(find(second, "runMark").visible, false, "a node with no entry draws no mark")
    compare(find(second, "runRollupBar").visible, false)
  }

  function test_without_run_props_no_node_draws_a_run_mark() {
    var v = createTemporaryObject(viewC, tc)
    v.nodes = nodes
    v.edges = edges
    wait(100)
    compare(find(find(v, "graphNodem1"), "runMark").visible, false)
    compare(find(find(v, "graphNodem1"), "runRollupBar").visible, false)
    var s = story()
    compare(find(find(s, "graphNodes1"), "runMark").visible, false)
    compare(find(find(s, "graphNodes1"), "statusPipt2").ringed, false)
  }

  function test_run_marks_draw_on_story_nodes_and_ring_the_running_pip() {
    var v = story()
    v.runMarks = { s1: runMark("escalated", true) }
    v.runRollups = { s1: { running: 0, parked: 0, escalated: 1, done: 0, pending: 0, total: 1 } }
    v.runRinged = ["t2"]
    wait(50)
    var first = find(v, "graphNodes1")
    var mark = find(first, "runMark")
    compare(mark.visible, true)
    compare(find(first, "runBadge").text, "‼ 1")
    verify(mark.opacity < 1, "a dimmed winner is drawn dimmed")
    compare(find(first, "runRollupBar").visible, true)
    verify(find(first, "runRollupBar").opacity < 1, "and so is its bar")
    var pips = find(first, "graphNodePips")
    compare(find(pips, "statusPipt2").ringed, true)
    compare(find(pips, "statusPipt1").ringed, false)
    compare(find(find(v, "graphNodes2"), "runMark").visible, false)
  }

  function test_stale_run_data_dims_the_node_marks() {
    var v = createTemporaryObject(viewC, tc)
    v.nodes = nodes
    v.edges = edges
    v.runMarks = { m1: runMark("running") }
    wait(100)
    var mark = find(find(v, "graphNodem1"), "runMark")
    compare(mark.opacity, 1)
    compare(find(mark, "runBadge").text, "⟳")
    compare(find(mark, "runBadge").pulsing, true)
    v.runStale = true
    wait(30)
    compare(mark.opacity, 0.5)
    compare(find(mark, "runBadge").pulsing, false)
  }

  function test_run_props_of_the_wrong_shape_draw_nothing() {
    var v = story()
    var withOdd = storyNodes.map(function(n) { return Object.assign({}, n) })
    withOdd[1].id = "constructor"
    v.nodes = withOdd
    wait(50)
    var bad = [null, "s1", ["s1"], 5]
    for (var i = 0; i < bad.length; i++) {
      v.runMarks = bad[i]
      v.runRollups = bad[i]
      v.runRinged = bad[i]
      wait(20)
      compare(find(find(v, "graphNodes1"), "runMark").visible, false, "bad " + i)
      compare(find(find(v, "graphNodes1"), "statusPipt2").ringed, false, "bad " + i)
    }
    v.runMarks = ({})
    v.runRollups = ({})
    wait(20)
    compare(find(find(v, "graphNodeconstructor"), "runMark").visible, false, "an inherited name is not an entry")
    compare(find(find(v, "graphNodeconstructor"), "runRollupBar").visible, false)
  }
```

- [ ] **Step 2: Run them and watch them fail**

Run: `bash tests/run.sh tst_graph_view`
Expected: FAIL. The output has `Cannot assign to non-existent property "runMarks"` (and the same for `runRollups`, `runRinged` and `runStale`), and `find(first, "runMark")` is null. The existing GraphView tests PASS.

- [ ] **Step 3: Add the props and lookups**

In `ui/components/GraphView.qml`, after `property string cursorId: ""` (line 30) add:

```qml
  // ---- am run marks (5.3), handed in by GraphScreen, which reads the run
  // store: this view has no `app`. By card id -- runMarks: Runs.cardRunState,
  // runRollups: Runs.rollup -- plus the subtask pips to ring and whether the run
  // data is stale (drawn dimmed). A missing or inherited id draws nothing.
  property var runMarks: ({})
  property var runRollups: ({})
  property var runRinged: []
  property bool runStale: false

  function _ownValue(map, id) {
    return map !== null && map !== undefined && typeof map === "object" && !Array.isArray(map)
      && typeof id === "string" && id !== "" && Object.prototype.hasOwnProperty.call(map, id) ? map[id] : null
  }
  function runMarkOf(id) { return view._ownValue(view.runMarks, id) }
  function runRollupOf(id) { return view._ownValue(view.runRollups, id) }
```

- [ ] **Step 4: Milestone node: title row with the mark, bar under the progress**

In `milestoneDelegate`, replace:

```qml
        UI.ThemedText {
          objectName: "graphNodeTitle"
          theme: view.theme
          width: parent.width
          text: node.entry.title
          font.bold: true
          elide: Text.ElideRight
        }
```

with:

```qml
        Item {
          width: parent.width
          height: Math.max(nodeTitle.implicitHeight, nodeRunMark.shown ? nodeRunMark.height : 0)

          UI.ThemedText {
            id: nodeTitle
            objectName: "graphNodeTitle"
            theme: view.theme
            anchors.left: parent.left
            anchors.right: nodeRunMark.shown ? nodeRunMark.left : parent.right
            anchors.rightMargin: nodeRunMark.shown ? 6 : 0
            anchors.verticalCenter: parent.verticalCenter
            text: node.entry.title
            font.bold: true
            elide: Text.ElideRight
          }

          UI.RunMark {
            id: nodeRunMark
            theme: view.theme
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            runState: view.runMarkOf(node.entry.id)
            rollup: view.runRollupOf(node.entry.id)
            stale: view.runStale
            active: view.visible
          }
        }
```

Then replace:

```qml
            text: "\uF024 " + Graph.openIssueLabel(node.entry.openIssues || 0)
            color: Board.statusColor("blocked", view.theme.dim)
          }
        }
```

with:

```qml
            text: "\uF024 " + Graph.openIssueLabel(node.entry.openIssues || 0)
            color: Board.statusColor("blocked", view.theme.dim)
          }
        }

        // The milestone's am run rollup; hides itself without one.
        UI.RunRollupBar {
          theme: view.theme
          rollup: view.runRollupOf(node.entry.id)
          opacity: nodeRunMark.dimmed ? 0.5 : 1
        }
```

- [ ] **Step 5: Story node: title row, ring, bar**

In `storyDelegate`, replace:

```qml
        UI.ThemedText {
          objectName: "graphNodeTitle"
          theme: view.theme
          width: parent.width
          text: storyNode.entry.title
          font.bold: true
          elide: Text.ElideRight
        }
```

with:

```qml
        Item {
          width: parent.width
          height: Math.max(storyTitle.implicitHeight, storyRunMark.shown ? storyRunMark.height : 0)

          UI.ThemedText {
            id: storyTitle
            objectName: "graphNodeTitle"
            theme: view.theme
            anchors.left: parent.left
            anchors.right: storyRunMark.shown ? storyRunMark.left : parent.right
            anchors.rightMargin: storyRunMark.shown ? 6 : 0
            anchors.verticalCenter: parent.verticalCenter
            text: storyNode.entry.title
            font.bold: true
            elide: Text.ElideRight
          }

          UI.RunMark {
            id: storyRunMark
            theme: view.theme
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            runState: view.runMarkOf(storyNode.entry.id)
            rollup: view.runRollupOf(storyNode.entry.id)
            stale: view.runStale
            active: view.visible
          }
        }
```

In the same delegate's `UI.StatusPips`, replace:

```qml
            more: storyNode.entry.morePips || 0
```

with:

```qml
            more: storyNode.entry.morePips || 0
            // The subtasks an am run is working on right now.
            ringedIds: view.runRinged
```

Then replace:

```qml
            text: "\uF024 " + Graph.openIssueLabel(storyNode.entry.openIssues || 0)
            color: Board.statusColor("blocked", view.theme.dim)
          }
        }
```

with:

```qml
            text: "\uF024 " + Graph.openIssueLabel(storyNode.entry.openIssues || 0)
            color: Board.statusColor("blocked", view.theme.dim)
          }
        }

        // The story's am run rollup; hides itself without one.
        UI.RunRollupBar {
          theme: view.theme
          rollup: view.runRollupOf(storyNode.entry.id)
          opacity: storyRunMark.dimmed ? 0.5 : 1
        }
```

- [ ] **Step 6: Run the tests and watch them pass**

Run: `bash tests/run.sh tst_graph_view`
Expected: every GraphView test PASS (old and new), with no `TypeError` or `anchors` warning lines. Also run `bash tests/run.sh tst_graph_wheel` and expect PASS (same view).

- [ ] **Step 7: Commit**

```bash
git add ui/components/GraphView.qml tests/ui/tst_graph_view.qml
git commit -m "feat(5.3): GraphView draws run marks, rollup bars and ringed pips from new props"
```

---

### Task 6: GraphScreen feeds the run props

**Files:**
- Modify: `ui/screens/GraphScreen.qml` (imports :1-4, body before `UI.GraphView` :26, the GraphView block :26-37)
- Test: `tests/ui/screens/tst_graph_screen.qml` (append before the final `}` at line 192)

**Interfaces:**
- Consumes: `Runs.cardRunState`, `Runs.rollup` (core/domain/runs.js), `app.runs.runs`, `app.runs.amStatus`, `app.runs.stale`, `app.graph.currentNodes` (nodes carry `id`, `status`, and on story nodes `pips: [{id, status}]`), and the GraphView props from Task 5.
- Produces: `GraphScreen.hidesRunMarks(status) -> bool`, `GraphScreen.buildRunMarks(nodes, runs, amStatus) -> { marks, rollups, ringed }`, `GraphScreen.runMarkData`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/ui/screens/tst_graph_screen.qml` before the final `}`:

```qml
  // ---- 5.3: the am run marks the screen hands the view.

  function mkRun(id, status, live, milestone, tree, rows) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: milestone, status: status, started_at: "",
             base_branch: "", branch_prefix: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: rows || [], tree: tree || { stories: [], subtasks: [] } }
  }

  // m1 heads a live run working on t1 (t2 still pending); m2 is merged but a
  // live run still names it; m3 is untouched.
  function withRuns(s) {
    s.app.runs.snapshotRunner.cancel()
    s.app.board.applyTreeData([
      card("m1", "First", "in_progress", [card("s1", "Story one", "in_progress",
        [card("t1", "Sub one", "in_progress"), card("t2", "Sub two", "todo")])]),
      card("m2", "Second", "merged", [card("s2", "Story two", "merged")]),
      card("m3", "Third", "todo", [card("s3", "Story three", "todo")])])
    s.app.runs.runs = [
      mkRun("run-a1", "started", true, "m1",
        { stories: [{ card_id: "s1", subtasks: ["t1", "t2"] }],
          subtasks: [{ card_id: "t1", phases: [{ name: "implement", status: "started" }] },
                     { card_id: "t2", phases: [] }] },
        [{ card_id: "t1", status: "running" }, { card_id: "t2", status: "pending" }]),
      mkRun("run-b2", "started", true, "m2", { stories: [{ card_id: "s2", subtasks: [] }], subtasks: [] }, [])]
    return s
  }

  function test_the_graph_view_gets_the_run_marks_from_the_run_store() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.showSection("graph")
    wait(100)
    var gv = find(s, "graphView")
    compare(gv.runMarks.m1.state, "running")
    compare(gv.runMarks.m1.runId, "run-a1")
    compare(gv.runRollups.m1.running, 1)
    compare(gv.runRollups.m1.pending, 1)
    compare(gv.runRollups.m1.total, 2)
    compare(gv.runMarks.m3.state, "none", "an untouched node is passed as none")
    compare(gv.runRinged.length, 0, "milestone nodes carry no pips")
    var badge = find(find(s, "graphNodem1"), "runBadge")
    verify(badge && badge.visible, "the milestone node draws the badge")
    compare(badge.text, "⟳ 1")
    compare(gv.runStale, false)
    s.app.runs.stale = true
    compare(gv.runStale, true, "stale reaches the view")
  }

  function test_a_merged_node_gets_no_run_mark_even_when_a_run_touches_it() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.showSection("graph")
    wait(100)
    var gv = find(s, "graphView")
    compare(gv.runMarks.m2, undefined, "the brd-status gate decides visibility")
    compare(gv.runRollups.m2, undefined)
    compare(find(find(s, "graphNodem2"), "runMark").visible, false)
  }

  function test_the_story_view_rings_only_the_subtask_a_live_run_is_working_on() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.showSection("graph")
    s.app.graph.setGraphView("story")
    wait(100)
    var gv = find(s, "graphView")
    compare(gv.runRinged.join(","), "t1", "t2 is in the run but its own row is pending")
    var pips = find(find(s, "graphNodes1"), "graphNodePips")
    compare(find(pips, "statusPipt1").ringed, true)
    compare(find(pips, "statusPipt2").ringed, false)
    compare(gv.runMarks.s1.state, "running")
    compare(gv.runRollups.s1.total, 2)
    compare(gv.runMarks.s2, undefined, "a merged story is gated too")
  }

  function test_am_missing_passes_no_run_marks() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.showSection("graph")
    s.app.graph.setGraphView("story")
    s.app.runs.amStatus = "missing"
    wait(100)
    var gv = find(s, "graphView")
    compare(Object.keys(gv.runMarks).length, 0)
    compare(Object.keys(gv.runRollups).length, 0)
    compare(gv.runRinged.length, 0)
    verify(find(s, "graphNodes1"), "the graph still renders")
    compare(find(find(s, "graphNodes1"), "runMark").visible, false)
  }
```

- [ ] **Step 2: Run them and watch them fail**

Run: `bash tests/run.sh tst_graph_screen`
Expected: FAIL. `gv.runMarks.m1` is undefined (`TypeError: Cannot read property 'state' of undefined`), because the screen does not pass the props yet.

- [ ] **Step 3: Implement**

In `ui/screens/GraphScreen.qml`, add the domain import after `import qs.Commons`:

```qml
import QtQuick
import qs.Commons
import "../../core/domain/runs.js" as Runs
import "../components" as UI
import "../theme" as T
```

Before `UI.GraphView {` add:

```qml
  // ---- am run marks (5.3): computed here from the run store and handed to the
  // view, which has no `app`. A merged or canceled node (or archived, should
  // brd ever report it) gets none -- a visibility rule only, never a run state
  // -- and no node gets any while am is not installed. Maps by card id with no
  // prototype, so any card id is just a key.
  readonly property var runMarkData: graphScreen.buildRunMarks(graphScreen.app.graph.currentNodes,
                                                               graphScreen.app.runs.runs, graphScreen.app.runs.amStatus)

  function hidesRunMarks(status) {
    return status === "merged" || status === "canceled" || status === "archived"
  }

  // { marks: id -> Runs.cardRunState, rollups: id -> Runs.rollup, ringed: [pip id] }.
  // A pip is ringed when its run is live and running AND its own am row is in the
  // running bucket: the subtask am is working on now, not every subtask of the run.
  function buildRunMarks(nodes, runs, amStatus) {
    var marks = Object.create(null)
    var rollups = Object.create(null)
    var ringed = []
    var out = { marks: marks, rollups: rollups, ringed: ringed }
    if (amStatus === "missing" || !Array.isArray(nodes)) return out
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (!node || typeof node.id !== "string" || graphScreen.hidesRunMarks(node.status)) continue
      marks[node.id] = Runs.cardRunState(runs, node.id)
      rollups[node.id] = Runs.rollup(runs, { id: node.id })
      var pips = Array.isArray(node.pips) ? node.pips : []
      for (var j = 0; j < pips.length; j++) {
        var pip = pips[j]
        if (!pip || typeof pip.id !== "string" || graphScreen.hidesRunMarks(pip.status)) continue
        if (Runs.cardRunState(runs, pip.id).state === "running" && Runs.rollup(runs, { id: pip.id }).running > 0)
          ringed.push(pip.id)
      }
    }
    return out
  }
```

In the `UI.GraphView` block, after `theme: graphScreen.theme` add:

```qml
    runMarks: graphScreen.runMarkData.marks
    runRollups: graphScreen.runMarkData.rollups
    runRinged: graphScreen.runMarkData.ringed
    runStale: graphScreen.app.runs.stale
```

- [ ] **Step 4: Run them and watch them pass**

Run: `bash tests/run.sh tst_graph_screen`
Expected: every GraphScreen test PASS. pytest architecture PASS (the screen imports `core/domain/runs.js`, not `core/stores`).

- [ ] **Step 5: Commit**

```bash
git add ui/screens/GraphScreen.qml tests/ui/screens/tst_graph_screen.qml
git commit -m "feat(5.3): GraphScreen hands the view its run marks, rollups and rings"
```

---

### Task 7: Board cards show run marks

**Files:**
- Modify: `ui/screens/BoardScreen.qml` (imports :5, screen props after :23, Repeater delegate :60-69, `BoardCard` props :76-81 and title :106-111)
- Test: `tests/ui/screens/tst_board_screen.qml` (append before the final `}` at line 156)

**Interfaces:**
- Consumes: `UI.RunMark` (Task 4: `runState`, `rollup`, `subtask`, `stale`, `dimmed`), `UI.RunRollupBar`, `Runs.cardRunState`, `Runs.rollup`, `app.runs.runs/amStatus/stale`.
- Produces: `BoardScreen.amMissing: bool` and `BoardScreen.hidesRunMarks(card) -> bool`. New `BoardCard` props: `depth: int`, `runState: var`, `runRollup: var`, and `subtaskRun: bool` (readonly).

- [ ] **Step 1: Write the failing tests**

Append to `tests/ui/screens/tst_board_screen.qml` before the final `}`:

```qml
  // ---- 5.3: am run marks on the board's cards.

  // A normalised run (runs.js normalizeRun's shape), built directly. live === null: no lease.
  function mkRun(id, status, live, milestone, tree, rows) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: milestone, status: status, started_at: "",
             base_branch: "", branch_prefix: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: rows || [], tree: tree || { stories: [], subtasks: [] } }
  }

  // The roots and the runs that touch them:
  //   m1 milestone of a live run with one running subtask row -> counts + bar
  //   m2 a root am runs as a subtask, phase `review`          -> glyph + phase
  //   m3 touched by nothing                                    -> nothing
  //   m4 merged, yet the milestone of a live run               -> nothing (brd-status gate)
  //   m5 milestone of a parked run                             -> dimmed counts
  function withRuns() {
    var s = make(); if (!s) return null
    s.app.runs.snapshotRunner.cancel()
    s.app.board.applyTreeData([
      card("m1", "Milestone one", "in_progress", [card("s1", "Story", "in_progress", [card("t1", "Sub", "in_progress")])]),
      card("m2", "Solo task", "todo"),
      card("m3", "Untouched", "todo"),
      card("m4", "Merged one", "merged"),
      card("m5", "Parked one", "in_progress")])
    s.app.runs.runs = [
      mkRun("run-a1", "started", true, "m1",
        { stories: [{ card_id: "s1", subtasks: ["t1"] }],
          subtasks: [{ card_id: "t1", phases: [{ name: "implement", status: "started" }] }] },
        [{ card_id: "t1", status: "running" }]),
      mkRun("run-b2", "started", true, "mX",
        { stories: [], subtasks: [{ card_id: "m2", phases: [{ name: "review", status: "started" }] }] },
        [{ card_id: "m2", status: "running" }]),
      mkRun("run-c3", "started", true, "m4",
        { stories: [], subtasks: [{ card_id: "t4", phases: [] }] }, [{ card_id: "t4", status: "running" }]),
      mkRun("run-d4", "stopped", null, "m5",
        { stories: [], subtasks: [{ card_id: "t5", phases: [] }] }, [{ card_id: "t5", status: "stopped" }])]
    wait(50)
    return s
  }
  function cardTitled(s, title) { return cards(s).filter(function(c) { return c.title === title })[0] }
  function badgeText(c) { var b = H.find(c, "runBadgeText"); return b ? b.text : "" }

  function test_a_card_am_runs_as_a_subtask_shows_its_glyph_and_phase() {
    var s = withRuns(); if (!s) return
    var c = cardTitled(s, "Solo task")
    var mark = H.find(c, "runMark")
    verify(mark, "the card carries a run mark")
    compare(mark.visible, true)
    compare(badgeText(c), "⟳ review")
    compare(H.find(c, "runBadge").pulsing, true, "a live running subtask pulses")
    compare(H.find(c, "runRollupBar").visible, false, "a subtask has no rollup bar")
  }

  function test_a_milestone_card_shows_counts_and_a_rollup_bar() {
    var s = withRuns(); if (!s) return
    var c = cardTitled(s, "Milestone one")
    compare(H.find(c, "runMark").visible, true)
    compare(badgeText(c), "⟳ 1")
    compare(H.find(c, "runBadge").pulsing, false, "the counts form never pulses")
    compare(H.find(c, "runMark").opacity, 1)
    var bar = H.find(c, "runRollupBar")
    compare(bar.visible, true)
    compare(H.find(bar, "runRollupRunning").text, "⟳ 1")
  }

  function test_an_untouched_card_shows_no_run_mark() {
    var s = withRuns(); if (!s) return
    var c = cardTitled(s, "Untouched")
    compare(H.find(c, "runMark").visible, false)
    compare(H.find(c, "runRollupBar").visible, false)
  }

  function test_a_merged_or_canceled_card_shows_no_run_mark_even_when_a_run_touches_it() {
    var s = withRuns(); if (!s) return
    var c = cardTitled(s, "Merged one")
    verify(c, "the merged card is on the board")
    compare(H.find(c, "runMark").visible, false)
    compare(H.find(c, "runRollupBar").visible, false)
    s.app.board.applyTreeData([card("m4", "Merged one", "canceled")])
    wait(50)
    compare(H.find(cardTitled(s, "Merged one"), "runMark").visible, false, "canceled too")
    s.app.board.applyTreeData([card("m4", "Merged one", "in_progress")])
    wait(50)
    compare(H.find(cardTitled(s, "Merged one"), "runMark").visible, true,
            "the gate is visibility only: the same run shows once the card is live again")
  }

  function test_a_dimmed_winner_is_drawn_dimmed_and_does_not_pulse() {
    var s = withRuns(); if (!s) return
    var c = cardTitled(s, "Parked one")
    var mark = H.find(c, "runMark")
    compare(mark.visible, true)
    compare(badgeText(c), "⏸ 1")
    verify(mark.opacity < 1, "a finished run speaking for the card is dimmed")
    compare(H.find(c, "runBadge").active, false)
    compare(H.find(c, "runBadge").pulsing, false)
    verify(H.find(c, "runRollupBar").opacity < 1, "its rollup bar is dimmed with it")
  }

  function test_am_missing_hides_every_run_mark() {
    var s = withRuns(); if (!s) return
    s.app.runs.amStatus = "missing"
    wait(50)
    var all = cards(s)
    compare(all.length, 5)
    for (var i = 0; i < all.length; i++) {
      compare(H.find(all[i], "runMark").visible, false, all[i].title)
      compare(H.find(all[i], "runRollupBar").visible, false, all[i].title)
    }
    verify(texts(s).indexOf("Milestone one") >= 0, "the board still renders")
  }

  function test_stale_run_data_dims_the_marks() {
    var s = withRuns(); if (!s) return
    s.app.runs.stale = true
    wait(50)
    var solo = cardTitled(s, "Solo task")
    verify(H.find(solo, "runMark").opacity < 1)
    compare(H.find(solo, "runBadge").pulsing, false, "stale data does not pulse")
    verify(H.find(cardTitled(s, "Milestone one"), "runMark").opacity < 1)
    s.app.runs.stale = false
    wait(50)
    compare(H.find(solo, "runMark").opacity, 1)
    compare(H.find(solo, "runBadge").pulsing, true)
  }
```

- [ ] **Step 2: Run them and watch them fail**

Run: `bash tests/run.sh tst_board_screen`
Expected: FAIL. `verify(mark, "the card carries a run mark")` fails and `H.find(c, "runMark")` is null in every new test. The existing BoardScreen tests PASS.

- [ ] **Step 3: Screen-level props and the gate**

In `ui/screens/BoardScreen.qml`, add the domain import under the board import:

```qml
import "../../core/domain/board.js" as Board
import "../../core/domain/runs.js" as Runs
```

After `spacing: Style.space(10)` (line 23) add:

```qml
  // ---- am run marks (5.3): read from the run store through `app`, never from
  // brd status. A merged or canceled card (or archived, should brd ever report
  // it) draws none -- a visibility rule only -- and no card draws any while am
  // is not installed.
  readonly property bool amMissing: screen.app.runs.amStatus === "missing"

  function hidesRunMarks(card) {
    return screen.amMissing || !card || card.status === "merged" || card.status === "canceled" || card.status === "archived"
  }
```

- [ ] **Step 4: Feed each card**

In the inner `Repeater`'s `BoardCard`, replace:

```qml
          progress: Board.subtreeCounts(modelData)
          onActivated: screen.navigator.openCard(modelData.id)
```

with:

```qml
          progress: Board.subtreeCounts(modelData)
          depth: modelData.depth || 0
          runState: screen.hidesRunMarks(modelData) ? null : Runs.cardRunState(screen.app.runs.runs, modelData.id)
          runRollup: screen.hidesRunMarks(modelData) ? null : Runs.rollup(screen.app.runs.runs, { id: modelData.id })
          onActivated: screen.navigator.openCard(modelData.id)
```

- [ ] **Step 5: Draw the mark and the bar in `BoardCard`**

In `component BoardCard`, replace:

```qml
    property var progress: ({ done: 0, total: 0 })
    signal activated()
```

with:

```qml
    property var progress: ({ done: 0, total: 0 })
    property int depth: 0
    // Runs.cardRunState / Runs.rollup for this card, or null for no mark.
    property var runState: null
    property var runRollup: null
    // Glyph + phase rather than counts: a subtask by depth, or a card its
    // winning run lists as a subtask (the Board shows roots only).
    readonly property bool subtaskRun: boardCard.depth >= 2
      || (!!boardCard.runState && typeof boardCard.runState.phase === "string" && boardCard.runState.phase !== "")
    signal activated()
```

Then replace the title text:

```qml
      UI.ThemedText {
        theme: screen.theme
        Layout.fillWidth: true
        text: boardCard.title
        wrapMode: Text.WordWrap
      }
```

with:

```qml
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(6)

        UI.ThemedText {
          theme: screen.theme
          Layout.fillWidth: true
          text: boardCard.title
          wrapMode: Text.WordWrap
        }

        UI.RunMark {
          id: boardRunMark
          Layout.alignment: Qt.AlignTop | Qt.AlignRight
          theme: screen.theme
          runState: boardCard.runState
          rollup: boardCard.runRollup
          subtask: boardCard.subtaskRun
          stale: screen.app.runs.stale
        }
      }

      // A milestone's or story's am run rollup, under its title; hides itself
      // without one, and a subtask has none.
      UI.RunRollupBar {
        Layout.fillWidth: true
        theme: screen.theme
        rollup: boardCard.subtaskRun ? null : boardCard.runRollup
        opacity: boardRunMark.dimmed ? 0.5 : 1
      }
```

- [ ] **Step 6: Run the tests and watch them pass**

Run: `bash tests/run.sh tst_board_screen`
Expected: every BoardScreen test PASS, old and new. pytest architecture PASS (no new `bordered: true` or `CursorSurface {`, and BoardScreen imports no store).

- [ ] **Step 7: Commit**

```bash
git add ui/screens/BoardScreen.qml tests/ui/screens/tst_board_screen.qml
git commit -m "feat(5.3): board cards show their am run mark and rollup bar"
```

---

### Task 8: Run detail opened from a card comes back to the card

**Files:**
- Modify: `core/stores/NavigationStore.qml` (after `issueReturnMode` at :37)
- Modify: `ui/Navigator.qml` (`openRun` :327-340, new `restoreCardFromRun` after `restoreRunsList` :342-350, `goBack` :361)
- Test: `tests/core/stores/tst_navigation_store.qml` (append before the final `}` at :170)
- Test: `tests/ui/tst_navigator.qml` (append before the final `}` at :279)

**Interfaces:**
- Consumes: `nav.pushReturn`, `restoreListView`, `restoreRunsList`, `board.cardMap`, `board.selectedCardId`.
- Produces: `NavigationStore.runReturnMode: string` (`"runs"` by default, or `"entry"`), `Navigator.openRun(id, from)` where `from` is optional and `"entry"` means "opened from the card detail", and `Navigator.restoreCardFromRun()`.

- [ ] **Step 1: Write the failing store test**

Append to `tests/core/stores/tst_navigation_store.qml` before the final `}`:

```qml
  // An open run goes back to the Runs list unless a card's RUNS row opened it.
  function test_a_run_returns_to_the_runs_list_by_default() {
    var n = make(); if (!n) return
    compare(n.runReturnMode, "runs")
    n.runReturnMode = "entry"
    compare(n.runReturnMode, "entry")
  }
```

- [ ] **Step 2: Write the failing navigator tests**

Append to `tests/ui/tst_navigator.qml` before the final `}` (the file already has `card`, `runOf`, `crumbLabels`):

```qml
  // ---- Runs opened from a card (5.3)

  function cardRuns() {
    var n = make(); if (!n) return null
    n.app.runs.snapshotRunner.cancel()
    n.app.board.applyTreeData([card("m1", "Milestone", "todo"), card("m2", "Other", "todo")])
    n.app.runs.runs = [runOf("run-0000000000a1", "started", true, "m2")]
    wait(50)
    return n
  }

  function test_a_run_opened_from_a_card_comes_back_to_that_card() {
    var n = cardRuns(); if (!n) return
    n.app.nav.cursorIndex = 1
    tc.flick.contentY = 80
    n.openCard("m2")
    wait(0)
    compare(n.app.nav.viewMode, "entry")
    n.openRun("run-0000000000a1", "entry")
    wait(0)
    compare(n.app.nav.viewMode, "run")
    compare(n.app.runs.selectedRunId, "run-0000000000a1")
    compare(n.app.nav.runReturnMode, "entry")
    compare(n.app.nav.returnMode, "board", "the card's own way back is untouched")
    compare(n.app.nav.returnCursor, 1)
    compare(n.app.nav.returnScrollY, 80)
    compare(crumbLabels(n.crumbs), "Runs > …000000a1", "accepted: the run view still reads Runs")
    n.goBack()
    wait(0)
    compare(n.app.nav.viewMode, "entry")
    compare(n.app.board.selectedCardId, "m2")
    compare(n.app.runs.selectedRunId, "")
    compare(n.app.nav.runReturnMode, "runs")
    compare(n.app.nav.cursorIndex, 0)
    n.goBack()
    compare(n.app.nav.viewMode, "board", "Back from the card still reaches its list")
    compare(n.app.nav.cursorIndex, 1)
    wait(0)
    compare(tc.flick.contentY, 80)
  }

  function test_the_section_crumb_of_a_run_opened_from_a_card_also_lands_on_the_card() {
    var n = cardRuns(); if (!n) return
    n.openCard("m2")
    n.openRun("run-0000000000a1", "entry")
    n.activateCrumb(0)
    compare(n.app.nav.viewMode, "entry")
    compare(n.app.board.selectedCardId, "m2")
  }

  function test_a_plain_open_resets_the_return_to_the_runs_list() {
    var n = cardRuns(); if (!n) return
    n.openCard("m2")
    n.openRun("run-0000000000a1", "entry")
    compare(n.app.nav.runReturnMode, "entry")
    n.openRun("run-0000000000a1")
    compare(n.app.nav.runReturnMode, "runs", "every open says where Back goes")
    n.goBack()
    compare(n.app.nav.viewMode, "runs")
  }

  function test_back_from_a_card_run_whose_card_is_gone_returns_to_the_list() {
    var n = cardRuns(); if (!n) return
    n.openCard("m2")
    n.openRun("run-0000000000a1", "entry")
    n.app.board.applyTreeData([card("m1", "Milestone", "todo")])
    compare(n.app.nav.viewMode, "run", "the run view does not follow the board")
    n.goBack()
    compare(n.app.nav.viewMode, "board", "no blank card: Back goes on to the card's list")
    compare(n.app.nav.runReturnMode, "runs")
    compare(n.app.runs.selectedRunId, "")
  }

  function test_an_unknown_run_from_a_card_opens_nothing() {
    var n = cardRuns(); if (!n) return
    n.openCard("m1")
    var bad = ["", "gone", null, undefined, 5]
    for (var i = 0; i < bad.length; i++) {
      n.openRun(bad[i], "entry")
      compare(n.app.nav.viewMode, "entry", "id " + i)
      compare(n.app.nav.runReturnMode, "runs", "id " + i)
      compare(n.app.runs.selectedRunId, "", "id " + i)
    }
  }
```

- [ ] **Step 3: Run them and watch them fail**

Run: `bash tests/run.sh tst_navigation_store` then `bash tests/run.sh tst_navigator`
Expected: FAIL. The store test gets `runReturnMode` undefined where it expects `"runs"`. In the navigator tests `runReturnMode` is undefined, and `goBack` returns to `"runs"` where the test expects `"entry"`. The existing Runs navigator tests PASS.

- [ ] **Step 4: Implement the store property**

In `core/stores/NavigationStore.qml`, after `property string issueReturnMode: "issues"   // "issues" | "entry"` add:

```qml

  // Where an open run goes back to. A run reached from a card's RUNS row
  // returns to that card, and the single return slot above -- which holds the
  // card's own way back -- is left untouched, as for an issue.
  property string runReturnMode: "runs"   // "runs" | "entry"
```

- [ ] **Step 5: Implement the navigator**

In `ui/Navigator.qml`, replace the whole `openRun` function:

```qml
  function openRun(id) {
    if (typeof id !== "string" || id === "") return
    var runs = navi.app.runs.runs
    var found = false
    for (var i = 0; i < runs.length && !found; i++) found = !!runs[i] && runs[i].id === id
    if (!found) return
    navi.app.runs.selectedRunId = id
    navi.app.nav.pushReturn(navi.flick ? navi.flick.contentY : 0)
    navi.app.nav.viewMode = "run"
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = 0
    Qt.callLater(navi.actions.scrollToTop)
    navi.actions.focusForView()
  }
```

with:

```qml
  // `from` is "entry" when a card's RUNS row opens the run: the card stays open
  // behind it and its return slot must survive, so only the Runs list pushes
  // one. Every open says where Back goes, so a Runs-list open always resets it.
  function openRun(id, from) {
    if (typeof id !== "string" || id === "") return
    var runs = navi.app.runs.runs
    var found = false
    for (var i = 0; i < runs.length && !found; i++) found = !!runs[i] && runs[i].id === id
    if (!found) return
    var fromCard = from === "entry"
    navi.app.nav.runReturnMode = fromCard ? "entry" : "runs"
    navi.app.runs.selectedRunId = id
    if (!fromCard) navi.app.nav.pushReturn(navi.flick ? navi.flick.contentY : 0)
    navi.app.nav.viewMode = "run"
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = 0
    Qt.callLater(navi.actions.scrollToTop)
    navi.actions.focusForView()
  }
```

After the `restoreRunsList` function add:

```qml

  // Leaving a run that was opened from a card: back to that card, at its top.
  // The card's own return slot was never touched, so Back from the card still
  // reaches its list. A card the board dropped meanwhile cannot be shown, so
  // Back goes on to that list instead of a blank card.
  function restoreCardFromRun() {
    navi.app.runs.selectedRunId = ""
    navi.app.nav.runReturnMode = "runs"
    if (!navi.app.board.cardMap[navi.app.board.selectedCardId]) { navi.restoreListView(); return }
    navi.app.nav.viewMode = "entry"
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = 0
    Qt.callLater(navi.actions.scrollToTop)
    navi.actions.focusForView()
  }
```

In `goBack`, replace:

```qml
    if (navi.app.nav.viewMode === "run") { navi.restoreRunsList(); return }
```

with:

```qml
    if (navi.app.nav.viewMode === "run") {
      if (navi.app.nav.runReturnMode === "entry") navi.restoreCardFromRun()
      else navi.restoreRunsList()
      return
    }
```

- [ ] **Step 6: Run them and watch them pass**

Run: `bash tests/run.sh tst_navigation_store`, `bash tests/run.sh tst_navigator` and `bash tests/run.sh tst_runs_flow`
Expected: all PASS. The existing Runs-list return is unchanged (`test_enter_opens_a_run_and_back_restores_the_cursor_and_scroll` still passes).

- [ ] **Step 7: Commit**

```bash
git add core/stores/NavigationStore.qml ui/Navigator.qml tests/core/stores/tst_navigation_store.qml tests/ui/tst_navigator.qml
git commit -m "feat(5.3): a run opened from a card goes Back to that card (runReturnMode)"
```

---

### Task 9: RUNS section on card detail

**Files:**
- Modify: `ui/screens/CardDetailScreen.qml` (imports :5; props after `card` :27; header + Repeater before `UI.CommentList` :120-127; new `component CardRunRow` before `component DetailLink` :158)
- Test: `tests/ui/screens/tst_card_detail_screen.qml` (append before the final `}` at :244)

**Interfaces:**
- Consumes: `Runs.runsTouching` (Task 2), `Runs.runState`, `Runs.shortId`, `Runs.runTitle`, `Runs.currentPhase`, `Runs.runAgeText`, `UI.RunBadge`, `UI.ListRow`, and `navigator.openRun(id, "entry")` (Task 8).
- Produces: `CardDetailScreen.touchingRuns: var` and `nowMs: real`. New objectNames: `cardRunsHeader`, `cardRunRow<n>`, `cardRunId<n>`, `cardRunTitle<n>`, `cardRunPhase<n>`, `cardRunAge<n>`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/ui/screens/tst_card_detail_screen.qml` before the final `}`:

```qml
  // ---- RUNS (5.3)

  function mkRun(id, status, live, milestone, tree, startedAt) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: milestone, status: status, started_at: startedAt || "",
             base_branch: "", branch_prefix: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: [], tree: tree || { stories: [], subtasks: [] } }
  }
  function hoursAgo(h) { return new Date(Date.now() - h * 3600000).toISOString() }

  // am's order, newest first:
  //   …a1 live, milestone m1, story s1 with subtask t1 in `implement`, 2 h old
  //   …b2 escalated, milestone x1 only
  //   …c3 done, milestone m1, story s1, 30 h old
  function withRuns(s) {
    s.app.runs.snapshotRunner.cancel()
    s.app.runs.runs = [
      mkRun("run-0000000000a1", "started", true, "m1",
            { stories: [{ card_id: "s1", subtasks: ["t1"] }],
              subtasks: [{ card_id: "t1", phases: [{ name: "implement", status: "started" }] }] }, hoursAgo(2)),
      mkRun("run-0000000000b2", "escalated", null, "x1", null, hoursAgo(5)),
      mkRun("run-0000000000c3", "done", null, "m1",
            { stories: [{ card_id: "s1", subtasks: [] }], subtasks: [] }, hoursAgo(30))]
    return s
  }

  function test_the_runs_section_lists_the_runs_that_touch_the_card() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("s1")
    wait(50)
    var header = H.find(s, "cardRunsHeader")
    verify(header, "the RUNS header")
    compare(header.visible, true)
    compare(header.text, "RUNS")
    var first = H.find(s, "cardRunRow0")
    verify(first, "a row per touching run, newest first")
    compare(H.find(first, "runBadge").text, "⟳")
    compare(H.find(first, "cardRunId0").text, "…000000a1")
    compare(H.find(first, "cardRunTitle0").text, "m1")
    compare(H.find(first, "cardRunPhase0").text, "implement")
    compare(H.find(first, "cardRunAge0").text, "2h")
    var second = H.find(s, "cardRunRow1")
    verify(second, "the finished run is history and still listed")
    compare(H.find(second, "runBadge").text, "✔")
    compare(H.find(second, "cardRunId1").text, "…000000c3")
    compare(H.find(second, "cardRunPhase1").visible, false, "no phase is started")
    compare(H.find(second, "cardRunAge1").text, "1d")
    verify(!H.find(s, "cardRunRow2"), "the escalated run of x1 does not touch s1")
    compare(first.index, -1, "a RUNS row is not in the keyboard's link list")
  }

  function test_an_escalated_run_row_reads_urgent() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("x1")
    wait(50)
    var row = H.find(s, "cardRunRow0")
    verify(row)
    compare(H.find(row, "runBadge").text, "‼")
    verify(Qt.colorEqual(H.find(row, "runBadge").tint, s.theme.urgent))
    verify(!H.find(s, "cardRunRow1"))
  }

  function test_the_runs_section_follows_a_new_snapshot() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("s1")
    wait(50)
    compare(H.find(s, "cardRunsHeader").visible, true)
    s.app.runs.runs = [s.app.runs.runs[1]]
    wait(50)
    compare(H.find(s, "cardRunsHeader").visible, false, "no run touches s1 any more")
    compare(s.touchingRuns.length, 0)
    verify(texts(s).indexOf("Story one") >= 0, "the card itself still renders")
  }

  function test_the_runs_section_is_hidden_when_no_run_touches_the_card() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("t1")
    wait(50)
    compare(H.find(s, "cardRunsHeader").visible, true, "t1 is a subtask of the live run")
    s.app.board.applyTreeData([card("z1", "Lonely", "todo", "z desc")])
    s.navigator.openCard("z1")
    wait(50)
    compare(H.find(s, "cardRunsHeader").visible, false)
    verify(!H.find(s, "cardRunRow0"))
  }

  function test_the_runs_section_is_hidden_while_am_is_missing() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("s1")
    wait(50)
    s.app.runs.amStatus = "missing"
    wait(50)
    compare(H.find(s, "cardRunsHeader").visible, false)
    compare(s.touchingRuns.length, 0)
    verify(texts(s).indexOf("Story one") >= 0, "the card still renders")
  }

  function test_stale_run_data_dims_the_rows_and_stops_the_pulse() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("s1")
    wait(50)
    var row = H.find(s, "cardRunRow0")
    compare(row.opacity, 1)
    compare(H.find(row, "runBadge").pulsing, true)
    s.app.runs.stale = true
    wait(50)
    verify(row.opacity < 1)
    compare(H.find(row, "runBadge").pulsing, false)
  }

  function test_a_merged_card_still_lists_its_runs() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("m1", "Milestone one", "merged", "m desc")])
    withRuns(s)
    s.navigator.openCard("m1")
    wait(50)
    compare(H.find(s, "cardRunsHeader").visible, true, "history: the brd-status gate is the Board's and the Graph's only")
    compare(s.touchingRuns.length, 2)
  }

  function test_clicking_a_run_row_opens_run_detail_and_back_returns_to_the_card() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("s1")
    wait(50)
    mouseClick(H.find(s, "cardRunRow1"))
    compare(s.app.nav.viewMode, "run")
    compare(s.app.runs.selectedRunId, "run-0000000000c3")
    compare(s.app.nav.runReturnMode, "entry", "opened as openRun(id, \"entry\")")
    s.navigator.goBack()
    compare(s.app.nav.viewMode, "entry")
    compare(s.app.board.selectedCardId, "s1")
    compare(s.app.runs.selectedRunId, "")
  }
```

- [ ] **Step 2: Run them and watch them fail**

Run: `bash tests/run.sh tst_card_detail_screen`
Expected: FAIL. `verify(header, "the RUNS header")` fails (no `cardRunsHeader`), and `s.touchingRuns` is undefined. The existing card-detail tests PASS.

- [ ] **Step 3: Imports and the touching runs**

In `ui/screens/CardDetailScreen.qml`, add under the board import:

```qml
import "../../core/domain/board.js" as Board
import "../../core/domain/runs.js" as Runs
```

After `readonly property var card: detailCard.app.board.cardMap[detailCard.app.board.selectedCardId]` add:

```qml

  // The am runs that touch this card (5.3), in am's order: newest first. A
  // card's runs are its history, so a merged or canceled card still lists them;
  // nothing is listed while am is not installed.
  readonly property var touchingRuns: !detailCard.card || detailCard.app.runs.amStatus === "missing"
    ? [] : Runs.runsTouching(detailCard.app.runs.runs, detailCard.card.id)
  // Ages are read against the clock once per run snapshot: there is no timer.
  readonly property real nowMs: detailCard.touchingRuns ? Date.now() : 0
```

- [ ] **Step 4: The header and the rows**

Before the comment `// The card's comments, from the export the extras store holds.` insert:

```qml
  PanelSectionHeader {
    objectName: "cardRunsHeader"
    visible: detailCard.touchingRuns.length > 0
    text: "RUNS"
    foreground: detailCard.theme.foreground
    fontFamily: detailCard.theme.fontFamily
  }

  Repeater {
    model: detailCard.touchingRuns.length

    CardRunRow {
      width: parent.width
    }
  }

```

- [ ] **Step 5: The row component**

Directly before `  component DetailLink: UI.ListRow {` insert:

```qml
  // One run that touches the card: its state glyph, short id, title, current
  // phase and age. Mouse-activated only (`index` stays -1): the keyboard's link
  // list is the card's brd links. A click opens Run detail, whose Back comes
  // back here; a run that vanished meanwhile opens nothing.
  component CardRunRow: UI.ListRow {
    id: runRow
    // The model is a count, so this is the run's position in touchingRuns. The
    // run is read back by position because a Repeater's converted modelData copy
    // would lose the nested arrays the domain helpers read.
    required property int modelData
    readonly property var run: detailCard.touchingRuns[runRow.modelData] || null

    objectName: "cardRunRow" + runRow.modelData
    theme: detailCard.theme
    opacity: detailCard.app.runs.stale ? 0.5 : 1
    contentMargin: Style.space(6)
    onActivated: detailCard.navigator.openRun(runRow.run ? runRow.run.id : "", "entry")

    Row {
      width: parent.width
      spacing: Style.space(8)

      UI.RunBadge {
        theme: detailCard.theme
        state: Runs.runState(runRow.run)
        active: !detailCard.app.runs.stale
      }

      UI.ThemedText {
        objectName: "cardRunId" + runRow.modelData
        variant: "caption"
        theme: detailCard.theme
        text: Runs.shortId(runRow.run)
      }

      UI.ThemedText {
        objectName: "cardRunTitle" + runRow.modelData
        variant: "small"
        theme: detailCard.theme
        text: Runs.runTitle(runRow.run)
      }

      UI.ThemedText {
        objectName: "cardRunPhase" + runRow.modelData
        variant: "caption"
        theme: detailCard.theme
        visible: text !== ""
        text: Runs.currentPhase(runRow.run)
      }

      UI.ThemedText {
        objectName: "cardRunAge" + runRow.modelData
        variant: "caption"
        theme: detailCard.theme
        visible: text !== ""
        text: Runs.runAgeText(runRow.run, detailCard.nowMs)
      }
    }
  }

```

(`Badge` inside this file is the screen's own local pill component, which is why the row uses the qualified `UI.RunBadge`.)

- [ ] **Step 6: Run the tests and watch them pass**

Run: `bash tests/run.sh tst_card_detail_screen`
Expected: every CardDetailScreen test PASS, old and new, with no `TypeError` lines. pytest architecture PASS (`radius: height / 2` is still the screen's one documented copy).

- [ ] **Step 7: Commit**

```bash
git add ui/screens/CardDetailScreen.qml tests/ui/screens/tst_card_detail_screen.qml
git commit -m "feat(5.3): card detail lists the runs that touch the card; a row opens Run detail"
```

---

### Task 10: Flows green and full verification

**Files:**
- No source change is expected. If a flow still fails, the fix goes in the task that owns the failing code, and its tests must stay green.

**Interfaces:**
- Consumes: everything above.
- Produces: a green branch.

- [ ] **Step 1: Run the two flow tests written in Task 1**

Run: `bash tests/run.sh tst_board_flow` then `bash tests/run.sh tst_graph_flow`
Expected: both PASS, the Task 1 tests included.

- [ ] **Step 2: Run the architecture rules on their own**

Run: `python3 -m pytest tests/architecture -q` (or `uv run --with pytest python3 -m pytest tests/architecture -q` if pytest is missing)
Expected: all pass. That covers the layer rule (no `core/stores` import in `ui/screens/**` or `ui/components/**`), no new copy of a guarded pattern, no type-name clash for `RunMark`, and valid glyphs.

- [ ] **Step 3: Run the whole suite**

Run: `bash tests/run.sh`
Expected: pytest has no failures. Every QML file prints `Totals: … 0 failed`, there is no `FAIL!` line and no `TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function` line, and the script exits 0.

- [ ] **Step 4: Commit (only if Step 1-3 needed a fix)**

```bash
git add -A
git commit -m "test(5.3): run-mark flows green"
```

If nothing changed, there is nothing to commit. Task 1 already recorded the flow tests.
