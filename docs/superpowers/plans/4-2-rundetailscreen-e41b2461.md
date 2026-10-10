# 4.2 RunDetailScreen: titles for any project — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run detail reads as the run's work for a run of any registered project: the header shows the run's title then its short id in `dim`, and every story and subtask line shows its title from the run's own project's titles map, else its short card id; dimming still reads the open board only.

**Architecture:** `RunDetailScreen` gains one readonly property, `titles: Runs.titlesOfRun(screen.run, app.runTitles ? app.runTitles.titlesByRoot : null)`, and feeds it to the existing `Runs.runTitle` (header) and `Runs.cardTitle` (tree). The header row gets a dim `runDetailId` (`Runs.runSubtitle`) and an eliding title. A tree line becomes a small inline `CardLine` component (a lead — glyph and name — that elides, and a tail — status and phase — that stays on the row) whose `text` property is the whole line, so tests still read one string. `isClosed` keeps reading `app.board.cardMap`. No domain or store change.

**Tech Stack:** QML (Qt 6, `QtQuick`, `QtTest`), the pure JS domain module `core/domain/runs.js`, run by `qmltestrunner`. The gate is `bash tests/run.sh` (pytest incl. `tests/architecture`, then every `tst_*.qml`; any `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `anchors on an item` / `is not a function` line fails it, except the known `width' of null` teardown lines). It takes about 5 minutes; run it with `timeout 900`. For a quick single-file or single-test run, from the repo root:

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input <file.qml> [<TestCaseName>::<test_function>] 2>&1 | grep -E "^(PASS|FAIL)|^   Loc|Totals|TypeError|ReferenceError|is not a function|non-existent|Unable to assign" | grep -v "width' of null"
```

The `TestCase` names are `RunDetailScreen` (`tests/ui/screens/tst_run_detail_screen.qml`), `RunsFlow` (`tests/ui/tst_runs_flow.qml`) and `RunsRealData` (`tests/ui/tst_runs_real_data.qml`). Below, "Run the quick command on X" means that command with `-input X` and the named function(s); with no function named, the whole file.

**Spec:** `docs/superpowers/specs/4-2-rundetailscreen-e41b2461.md` (prepended below).

## Global Constraints

- The screen's one map for the shown run is `Runs.titlesOfRun(screen.run, screen.app.runTitles ? screen.app.runTitles.titlesByRoot : null)`, a readonly property; an `app` with no `runTitles` gives `{}`, and nothing throws.
- The header reads `Runs.runTitle(run, titles)` (no `Run ` prefix), then `Runs.runSubtitle(run)` in `theme.dim`, then the state.
- A card's name is `Runs.cardTitle(card_id, run, titles)`, else `"…"` plus the id's last 8 characters (all of a shorter id). The full card id never appears on a story or subtask line. Titles never come from `app.board.cardMap`.
- `isClosed(id)` reads `app.board.cardMap` only; the titles map never affects opacity.
- Unchanged: `runDetailState`, `runDetailMeta`, `runDetailReason`, the controls, the flash line, the `Other` story label, the `runSynthetic*` rows, the attempt rows, the output heading (`Output · <card id> <phase>.<n>`).
- No change to `core/domain/runs.js`, `RunTitlesStore`, `App.qml`, `Panel.qml`, `RunsScreen`, `CardDetailScreen`, `PhaseTimeline`; no Events pane is created (spec B4).
- Screens receive `app` / `navigator` and never import `core/stores` (`docs/architecture.md:168`); shared components are reused, not copied (`tests/architecture/test_layers.py`); glyphs come only from `ui/components/runGlyphs.js` (`tests/architecture/test_icon_glyphs.py`).
- Comments state the contract only — no narrative, no plan/task/card references.
- Write every test first and watch it fail. `bash tests/run.sh` green at the end.

## Review Focus

1. **A very long run or card title** must elide and never push the short id, the state, a card's status or its phase off the row. Pinned in Task 1 (`test_a_long_run_title_never_pushes_the_short_id_or_the_state_off_the_row`) and Task 2 (`test_a_long_card_title_never_pushes_the_status_or_phase_off_the_row`) — this is why a tree line becomes `CardLine` (lead elides, tail stays) rather than one eliding `Text`, which would cut the status off first.
2. **A card id `"__proto__"` or `"constructor"`**: no prototype title, its short id (`…_proto__`, `…structor`). Pinned in Task 2 (`test_a_prototype_key_id_is_no_title`).
3. **`titlesByRoot` replaced while an attempt is selected**: the selection, the timeline, the attempt rows and the output pane stay as they were; only the names change. Pinned in Task 2 (`test_a_new_map_keeps_the_selected_attempt_and_its_output`).
4. **A run with no project root** while `titlesByRoot` has entries (even one keyed `""`): no map is used. Pinned in Task 2 (`test_a_run_with_no_project_uses_no_map`).
5. **`app.runTitles` arriving after the screen exists** (null first, then set): titles appear. Pinned in Task 2 (`test_titles_arriving_after_the_screen_are_read`).

Every code and test snippet below was applied to a scratch copy of this branch on 2026-10-10 and run: `tst_run_detail_screen.qml` 39 passed, `tst_runs_flow.qml` 40 passed, `tst_runs_real_data.qml` 9 passed, all with no warning lines; with the new tests against the unchanged screen, 15 of them failed as expected. Task 1 alone (its fixture, header tests and header code, before Task 2) was also run: 29 passed in the screen file, 40 in the flow, 9 in real data. The full `bash tests/run.sh` on the finished scratch copy exited 0 (pytest 1565 passed; all 96 QML files 0 failed; no warning line besides `width' of null`). Colours are compared as `String(color)`: `Qt.colorEqual` reports false for two equal `Qt.darker` colours here (`theme.dim` is one).

**Fixture note (deviation from the spec's wording, same intent):** the spec's fixture puts `runTitles` on `appC` as a plain JS object. A plain object's sub-property assignment notifies nothing, so "assign a whole new `titlesByRoot`" would not re-evaluate the screen. The plan's stub is instead a `QtObject` with a `titlesByRoot` property (`titlesC`), exactly as `RunTitlesStore` exposes it, created in `make()` and passed as `app.runTitles`; tests assign `s.titles.titlesByRoot = {…}`. Its default `titlesByRoot` is the spec's open-project map.

---

## Spec (prepended; headings demoted one level)

## 4.2 RunDetailScreen: titles for any project — design

Card: `e41b2461` (subtask of story `5e9efb63`, blocked by 4.1 `65be1a15`). Parent design:
`docs/superpowers/specs/2026-10-05-run-history-titles-design.md`, cited below as "P l.N".

### Purpose

Run detail reads as the run's work for a run of **any** registered project, not only the open
one. Its header names the run by its title, with the short run id beside it in `dim`, and its
story > subtask tree names every card by its title from the run's **own** project's titles map;
a card with no known title shows its short card id instead (P l.48-50, l.105-106, l.112-113).
Which cards are dimmed as closed by brd does not change: that still reads the open project's
board only (P l.59).

### What already exists (not touched by this card)

- `Runs.titlesOfRun(run, titlesByRoot)` (`core/domain/runs.js:794`): the run's project map,
  `{}` for a non-object `titlesByRoot`, a missing or non-object entry, or a run whose
  `project.root` is `""` or absent. Never throws.
- `Runs.runTitle(run, titles)` (`runs.js:585`) and `Runs.runSubtitle(run)` (`runs.js:605`,
  exactly `Runs.shortId(run)`, `"…"` plus the run id's last 8 characters).
- `Runs.cardTitle(id, run, titles)` (`runs.js:611`): the map's own usable title for `id`, else
  the usable `title` of the first `run.tree.stories` entry whose `card_id` is `id`, else `""`
  (always `""` for a non-string or empty `id`). am records no subtask titles, so a subtask's
  title comes from the map only.
- `app.runTitles` (`RunTitlesStore`): `titlesByRoot` (`{root: {id: title}}`, the open project's
  entry mirrored from `app.board.cardMap`). `RunsScreen`, `CardDetailScreen` and `Panel`
  already read it as `Runs.titlesOfRun(run, app.runTitles.titlesByRoot)` (4.1).
- `ui/screens/RunDetailScreen.qml` today: `cardOf(id)` (l.69-73) reads `app.board.cardMap`;
  `titleOf(id)` (l.75-78) and `isClosed(id)` (l.81-84) both go through it; `cardLine(id,
  status)` (l.94-103) prints `<glyph> <full id> <title> · <status>`; the header
  `runDetailTitle` (l.183-187) is `"Run " + Runs.shortId(run)`.

### Inherited constraints

- Callers pass the run's project map; a missing map is `{}` (P l.102-103).
- Run detail's header and tree show titles; ids only as the fallback (P l.112-113).
- `cardTitle` `""` means the tree shows the **short card id** (P l.105-106); a card id brd no
  longer has shows the short id (P l.199).
- No brd status is shown for another project's cards (P l.59).
- UI test: Run detail titles for a project that is not open (P l.226).
- `docs/architecture.md:168`: screens receive `app` / `navigator` and never import
  `core/stores`; shared components are reused, not copied
  (`tests/architecture/test_layers.py`); glyphs come only from `ui/components/runGlyphs.js`
  (`tests/architecture/test_icon_glyphs.py`). Docstrings and comments state the contract only,
  no narrative.

### Behavior

Throughout, `titles` is the screen's one map for the shown run:
`Runs.titlesOfRun(screen.run, screen.app.runTitles ? screen.app.runTitles.titlesByRoot : null)`
— a readonly property, so every text below re-evaluates when `titlesByRoot` or the run changes.
An `app` with no `runTitles` (null or absent) gives `{}`; nothing throws.

#### B1. Header

1. `runDetailTitle` (variant `heading`, unchanged) reads `Runs.runTitle(screen.run, titles)`:
   e.g. `Runs monitor` for a milestone run whose milestone is in the map, `milestone …M3` when
   it is not. The literal `Run ` prefix is gone.
2. A new `UI.ThemedText` `runDetailId`, variant `caption`, colour `screen.theme.dim`, reads
   `Runs.runSubtitle(screen.run)` (e.g. `…19efcddc`). It sits in the header row after
   `runDetailTitle` and before `runDetailState`.
3. The title elides on the right and takes the width the id and the state leave, so neither the
   short id nor the state is pushed off the row by a long title.
4. `runDetailState`, `runDetailMeta`, `runDetailReason`, the controls and the flash line are
   unchanged.

#### B2. Tree card lines

1. A story row (`runStory<i>`, when not `other`) and a subtask label (`runSubtaskLabel<i>_<j>`)
   read `<glyph> <name> · <status>`, then for a subtask ` · <phase>` as today. Each part is
   left out when empty, exactly as today (no glyph for an unknown status; no ` · <status>` for
   `""`).
2. `<name>` is `Runs.cardTitle(card_id, screen.run, titles)` when that is not `""`, else the
   short card id: `"…"` followed by the id's last 8 characters (all of a shorter id, e.g.
   `…t9`). The full card id no longer appears on these lines.
3. The title source is never `app.board.cardMap`: a run of the open project gets its titles
   through its map (which the store mirrors from the board); a run of any other project gets
   its own project's titles, even when the open board has a card with the same id and another
   title.
4. A story absent from the map but titled by am (`run.tree.stories[].title`) shows am's title.
5. The `Other` story row (`other: true`) keeps its label; the bookkeeping rows (`runSynthetic*`:
   Integrate / Bases / Base), the attempt rows and the output heading (`Output · <card id>
   <phase>.<n>`) are unchanged.

#### B3. Dimming

1. `isClosed(id)` keeps reading `app.board.cardMap` only: a story or subtask row is at opacity
   `0.5` when the open board holds that id with a status `Board.isClosedStatus` reports closed,
   `1` otherwise — the same rule and the same rows as today.
2. The titles map never affects opacity: a card titled from another project's map that the open
   board does not hold is at opacity `1`.

#### B4. The Events pane `titles` input

The card and P l.113 name an "Events pane `titles` input". No such pane or input exists in this
codebase (`RunDetailScreen.qml` has no events pane; `ui/components/PhaseTimeline.qml` takes
only `phases`; no QML type under `ui/` declares a `titles` property). There is nothing to wire;
this card adds no Events pane. If one is added later, it receives the same `titles` map.

#### B5. Contract text

- The screen's header comment says titles come from the run's own project map in
  `app.runTitles` (header: run title, then short id in dim; tree: card title, else the short
  card id) and that brd's board only dims the cards it has closed.
- `docs/architecture.md:168`: the parenthetical lists `RunDetailScreen` among the screens that
  also read `app.runTitles`; the `RunDetailScreen` sentence says the header shows the run's
  title (`runTitle` with `titlesOfRun(run, app.runTitles.titlesByRoot)`) and the short id in
  `dim`, and each story and subtask shows `cardTitle` with that map, else its short card id;
  closed cards are dimmed from the open project's board only.
- `README.md:154` (the Run detail sentence): "Enter or a click opens **Run detail**: the run's
  title with its short id dimmed, state, …; the story > subtask > phase > attempt tree, each
  card named by its title on the run's own project's board, else the last 8 characters of its
  id (…)".

### Error paths

| case | behaviour |
|---|---|
| `app.runTitles` null or absent | `titles` is `{}`: header `runTitle` fallback, tree short ids; no throw, no warning |
| `titlesByRoot` not an object, or the run's entry missing / not an object | same as above |
| a run with no `project` (root `""`) | no map is ever used, even if `titlesByRoot` has an entry for the open root |
| a card id in no map and not an am story | short card id |
| an id shorter than 8 characters | `…` plus the whole id |
| a malformed tree (non-string card ids) | rows render as today; a non-string id gives no title (`cardTitle` is `""`) and its line is built from whatever `runTree` hands over; no throw |
| `app.board` null or no `cardMap` | no row is dimmed; titles unaffected |

### Tests

Write every test first and watch it fail. Gate: `bash tests/run.sh` (includes
`tests/architecture`).

All new and changed tests are in **`tests/ui/screens/tst_run_detail_screen.qml`** — tier: screen
unit test with the bespoke stub app, because what is under test is the screen's bindings to
`app.runTitles` and `app.board`, and the stub lets each test set the map and the board
directly. Fixture changes:

- `appC` gains `property var runTitles: ({ titlesByRoot: { "/home/u/a": { s1: "Runs screens",
  t1: "RunDetailScreen", t2: "Old work", s2: "Dropped story", t3: "Shelved" } } })` — the open
  project's map, as the store mirrors it from the board. `board.cardMap` is unchanged.
- `run(id, status, live, opts)` gains `project: { root: o.root === undefined ? "/home/u/a" :
  o.root, name: "p" }` (`o.root === ""` gives a run with no project root).

New tests:

- T1 `test_the_header_reads_the_runs_title_then_its_short_id_in_dim`: with
  `titlesByRoot["/home/u/a"].M3 = "Runs monitor"` (assign a whole new `titlesByRoot`):
  `runDetailTitle` is `Runs monitor`; `runDetailId` is `…19efcddc`, colour `theme.dim`, its `x`
  greater than the title's; `runDetailState` still `<running glyph> running`. Without `M3` in
  the map the title is `milestone …M3`.
- T2 `test_a_run_of_another_project_titles_its_tree_from_its_own_map`: a run with
  `root: "/home/u/b"` and the `detailTree()` ids; `titlesByRoot` `{"/home/u/a": {s1: "Alpha
  story", …}, "/home/u/b": {M3: "Beta milestone", s1: "Beta story", t1: "Beta sub", t2: "Beta
  old", s2: "Beta dropped", t3: "Beta shelved"}}`: header `Beta milestone`; `runStory0` is
  `<running glyph> Beta story · started`; `runSubtaskLabel0_0` is `<running glyph> Beta sub ·
  started · implement.2` — never the board's `Runs screens` / `RunDetailScreen`.
- T3 `test_cards_of_a_project_that_is_not_open_and_not_on_the_board`: a run with root
  `/home/u/b` and a tree whose ids the board lacks — story `s-beta-00000001` (status
  `started`, subtasks `["t-beta-00000002"]`) and subtask `t-beta-00000002` (status `started`,
  no phases) — and map `{"/home/u/b": {"s-beta-00000001": "Beta story", "t-beta-00000002":
  "Beta sub"}}`: `runStory0` is `<running glyph> Beta story · started`, `runSubtaskLabel0_0`
  is `<running glyph> Beta sub · started`; both rows are at opacity `1`.
- T4 `test_a_card_without_a_title_shows_its_short_id`: the T3 run with no `/home/u/b` entry in
  `titlesByRoot`: `runStory0` is `<running glyph> …00000001 · started` and
  `runSubtaskLabel0_0` is `<running glyph> …00000002 · started`. The same run with
  `title: "am story"` on its raw `tree.stories[0]`: `runStory0` is `<running glyph> am story ·
  started` (the subtask stays `…00000002`). Then `s.app.runTitles = null`: the rows still read
  `…00000001` / `…00000002`, the header `milestone …M3`, and no error is raised. (`…t9` for a
  short id is pinned by the malformed-run test below.)
- T5 `test_titles_follow_the_map`: start with no map for `/home/u/b` (short ids), assign a
  `titlesByRoot` with that project's titles: the header and tree re-title with no other input.
- T6 `test_a_run_with_no_project_uses_no_map`: `root: ""` with `titlesByRoot` holding the open
  root's titles: short ids and the `milestone …M3` header.
- T7 `test_dimming_reads_the_open_board_only`: the open project's run (`detail()`): the existing
  opacities (t2, s2, t3 at `0.5`; s1, t1 at `1`) hold; then a run of `/home/u/b` whose map
  titles `t2` as `Beta open` while the open board has `t2` merged: the row reads `Beta open`
  and stays at `0.5` (the board's dimming is unchanged, B3.1), and a `/home/u/b` id the board
  lacks stays at `1`.

Existing tests whose expectations change (same tier and file unless noted):

- `test_the_header_names_the_run_its_state_and_its_branches` (l.151): `runDetailTitle` is
  `milestone …M3`, plus `runDetailId` `…19efcddc`.
- `test_story_and_subtask_rows_carry_glyph_title_status_and_phase` (l.183): ids drop out where
  a title exists: `<running glyph> Runs screens · started`, `<running glyph> RunDetailScreen ·
  started · implement.2`, `<done glyph> Old work · done · spec.1`, `<cancelled glyph> Dropped
  story · cancelled`, `Shelved`.
- `test_terminal_brd_cards_are_dimmed_not_hidden` (l.192): expectations unchanged.
- `test_a_malformed_run_renders_without_throwing` (l.363): `runSubtaskLabel0_0` is `…t9`.
- `tests/ui/tst_runs_flow.qml:263` — tier: Panel integration, unchanged harness:
  `runDetailTitle` becomes the run's `runTitle` (the plan reads the fixture's milestone to
  write the exact string) and a new assertion `runDetailId` is `…000000e5`.
- `tests/ui/tst_runs_real_data.qml:135-137` — tier: real-data integration: the label contains
  `…b5ba34f8` (the short form of `7442d674-…-cd27b5ba34f8`), or that subtask's title if the
  harness's open-project map holds it; it still ends with `· review.1`.

### Review focus

- A very long card or run title must elide, never hide the status, phase, short id or state.
- An id `"__proto__"` or `"constructor"` in the tree: no prototype title, short id shown
  (`cardTitle` uses own keys; the short-id helper must not read the map).
- `titlesByRoot` replaced while an attempt is selected: the selection, the timeline and the
  output pane stay as they were.
- A run of another project sharing an id with an open-board card: the title comes from the
  run's map; the dimming from the board (accepted: P l.59 and the card keep dimming on the open
  board only; ids are UUIDs, so a real collision is not expected).
- `app.runTitles` arriving after the screen is created (null first, then set): titles appear.

### Out of scope

- Any change to `core/domain/runs.js`, `RunTitlesStore`, `App.qml`, `Panel.qml`, `RunsScreen`,
  `CardDetailScreen` (4.1 and earlier cards own them).
- Creating an Events pane or adding a `titles` input to `PhaseTimeline` (B4).
- Showing another project's brd status, or dimming another project's closed cards.
- The output heading's card id, the bookkeeping rows, the attempt rows, history, filters and
  Show older.

---

## File Structure

- Modify `ui/screens/RunDetailScreen.qml` — the only code file. Gains `titles`, `nameOf`, `leadOf`, `tailOf`, the header's `runDetailId`, and the inline `CardLine` component; loses `titleOf` and `cardLine`. `cardOf` / `isClosed` stay (dimming).
- Modify `tests/ui/screens/tst_run_detail_screen.qml` — the stub app gains a `runTitles` stub (`titlesC`); `run()` gains `project`; new and changed tests.
- Modify `tests/ui/tst_runs_flow.qml` (one header assertion) and `tests/ui/tst_runs_real_data.qml` (one label assertion).
- Modify `docs/architecture.md` and `README.md` (one sentence each).

---

### Task 1: The header reads the run's title, then its short id in dim

**Files:**
- Modify: `ui/screens/RunDetailScreen.qml` (property block after l.35; header `Row` l.178-196)
- Test: `tests/ui/screens/tst_run_detail_screen.qml` (header comment l.1-8, components l.67-82, `make` l.84-101, `run` l.109-118, header tests l.151-157)
- Test: `tests/ui/tst_runs_flow.qml:263`

**Interfaces:**
- Consumes: `Runs.titlesOfRun(run, titlesByRoot)` → `{id: title}` (never throws, `{}` for anything unusable); `Runs.runTitle(run, titles)` → string; `Runs.runSubtitle(run)` → `"…" + last 8 of run.id`.
- Produces: `RunDetailScreen.titles` (readonly `var`, the shown run's map) — Task 2 reads it as `screen.titles`. Test fixture: `make()` returns `{ app, runs, control, titles, nav, screen }` where `titles` is the stub `QtObject` with `property var titlesByRoot`; `run(id, status, live, opts)` honours `opts.root` (`undefined` → `"/home/u/a"`, `""` → no root). Objects: `runDetailTitle`, `runDetailId`, `runDetailState`.

- [ ] **Step 1: Give the test stub app a `runTitles` and runs a project**

In `tests/ui/screens/tst_run_detail_screen.qml`, replace the end of the file's header comment:

```qml
// reads (with a recorder for control), and a board whose cardMap lends titles
// and brd statuses.
```

with:

```qml
// reads (with a recorder for control), one carrying RunTitlesStore's
// titlesByRoot (the open project's map, as the store mirrors it from the
// board), and a board whose cardMap lends brd statuses.
```

Replace:

```qml
  Component {
    id: appC
    QtObject {
      property var nav: null
      property var runs: null
      property var runControl: null
```

with:

```qml
  Component {
    id: titlesC
    QtObject {
      property var titlesByRoot: ({ "/home/u/a": { s1: "Runs screens", t1: "RunDetailScreen", t2: "Old work",
                                                   s2: "Dropped story", t3: "Shelved" } })
    }
  }

  Component {
    id: appC
    QtObject {
      property var nav: null
      property var runs: null
      property var runControl: null
      property var runTitles: null
```

In `make()`, replace:

```qml
    var app = appC.createObject(host, { nav: nav, runs: runs, runControl: control })
```

with:

```qml
    var titles = titlesC.createObject(host)
    var app = appC.createObject(host, { nav: nav, runs: runs, runControl: control, runTitles: titles })
```

and replace:

```qml
    return { app: app, runs: runs, control: control, nav: nav, screen: screen }
```

with:

```qml
    return { app: app, runs: runs, control: control, titles: titles, nav: nav, screen: screen }
```

Replace the head of `run()`:

```qml
  // A normalised run, as RunStore holds them. live === null means no lease.
  function run(id, status, live, opts) {
    var o = opts || {}
    return { id: id, repo_dir: "/home/u/a", milestone_id: o.milestone === undefined ? "M3" : o.milestone,
```

with:

```qml
  // A normalised run, as RunStore holds them. live === null means no lease;
  // opts.root is its project's root ("/home/u/a" unless given, "" for none).
  function run(id, status, live, opts) {
    var o = opts || {}
    return { id: id, repo_dir: "/home/u/a", project: { root: o.root === undefined ? "/home/u/a" : o.root, name: "p" },
             milestone_id: o.milestone === undefined ? "M3" : o.milestone,
```

(The rest of `run()` — `base_branch` onward — is unchanged.)

- [ ] **Step 2: Write the failing header tests**

In `test_the_header_names_the_run_its_state_and_its_branches`, replace:

```qml
    compare(H.find(s.screen, "runDetailTitle").text, "Run …19efcddc")
```

with:

```qml
    compare(H.find(s.screen, "runDetailTitle").text, "milestone …M3")
    compare(H.find(s.screen, "runDetailId").text, "…19efcddc")
```

Directly after that test (before `function test_a_dead_lease_and_no_lease() {`), add:

```qml
  function test_the_header_reads_the_runs_title_then_its_short_id_in_dim() {
    var s = make(detail()); if (!s) return
    var title = H.find(s.screen, "runDetailTitle")
    var id = H.find(s.screen, "runDetailId")
    var state = H.find(s.screen, "runDetailState")
    compare(title.text, "milestone …M3", "M3 is not in the map")
    s.titles.titlesByRoot = { "/home/u/a": { M3: "Runs monitor" } }
    compare(title.text, "Runs monitor")
    compare(id.text, "…19efcddc")
    compare(String(id.color), String(s.screen.theme.dim))
    compare(state.text, RG.glyphOf("running") + " running")
    verify(id.x > title.x, "the short id follows the title")
    verify(state.x > id.x, "the state follows the short id")
  }

  // A title of any length elides; the short id and the state stay on the row.
  function test_a_long_run_title_never_pushes_the_short_id_or_the_state_off_the_row() {
    var s = make(detail()); if (!s) return
    var long = "Long"
    for (var i = 0; i < 40; i++) long += " a very long run title"
    s.titles.titlesByRoot = { "/home/u/a": { M3: long } }
    var title = H.find(s.screen, "runDetailTitle")
    compare(title.text, long)
    compare(title.elide, Text.ElideRight)
    verify(title.width < title.implicitWidth, "the title is elided")
    var names = ["runDetailId", "runDetailState"]
    for (var j = 0; j < names.length; j++) {
      var t = H.find(s.screen, names[j])
      var right = t.mapToItem(s.screen, 0, 0).x + t.width
      verify(right <= s.screen.width, names[j] + " stays on the row: right edge " + right + " of " + s.screen.width)
    }
  }
```

(The long title starts with a word and never ends in a space: `runTitle` trims a title, so a trailing space would make `title.text` differ from `long`.)

In `tests/ui/tst_runs_flow.qml`, in `test_opening_a_run_shows_it_and_fetches_its_default_attempt`, replace:

```qml
    compare(H.find(p, "runDetailTitle").text, "Run …000000e5")
```

with:

```qml
    compare(H.find(p, "runDetailTitle").text, "milestone …alpha", "the open board has no card alpha")
    compare(H.find(p, "runDetailId").text, "…000000e5")
```

(`treeRun` is a milestone run of milestone `alpha` in `/home/u/a`, and the flow's board holds no card `alpha`, so `runTitle` falls back to `milestone …alpha`.)

- [ ] **Step 3: Run the tests to verify they fail**

Run the quick command on `tests/ui/screens/tst_run_detail_screen.qml` with `RunDetailScreen::test_the_header_names_the_run_its_state_and_its_branches RunDetailScreen::test_the_header_reads_the_runs_title_then_its_short_id_in_dim RunDetailScreen::test_a_long_run_title_never_pushes_the_short_id_or_the_state_off_the_row`, then on `tests/ui/tst_runs_flow.qml` with `RunsFlow::test_opening_a_run_shows_it_and_fetches_its_default_attempt`.
Expected: all four FAIL with `Compared values are not the same` (the title is still `Run …19efcddc` / `Run …000000e5`).

- [ ] **Step 4: Add the screen's titles map**

In `ui/screens/RunDetailScreen.qml`, replace:

```qml
  readonly property string runState: Runs.runState(screen.run)
```

with:

```qml
  readonly property string runState: Runs.runState(screen.run)
  // The run's project titles map (titlesOfRun); {} without app.runTitles.
  readonly property var titles: Runs.titlesOfRun(screen.run, screen.app.runTitles ? screen.app.runTitles.titlesByRoot : null)
```

- [ ] **Step 5: Title, short id and state in the header row**

Replace:

```qml
      UI.ThemedText {
        objectName: "runDetailTitle"
        variant: "heading"
        theme: screen.theme
        text: "Run " + Runs.shortId(screen.run)
      }

      UI.ThemedText {
        objectName: "runDetailState"
```

with:

```qml
      // Takes the width the others leave and elides, so they stay on the row.
      UI.ThemedText {
        objectName: "runDetailTitle"
        variant: "heading"
        theme: screen.theme
        width: Math.max(0, Math.min(implicitWidth, parent.width - detailId.width - detailState.width - parent.spacing * 2))
        text: Runs.runTitle(screen.run, screen.titles)
        elide: Text.ElideRight
      }

      UI.ThemedText {
        id: detailId
        objectName: "runDetailId"
        variant: "caption"
        theme: screen.theme
        text: Runs.runSubtitle(screen.run)
        color: screen.theme.dim
      }

      UI.ThemedText {
        id: detailState
        objectName: "runDetailState"
```

(The rest of `runDetailState` — its `variant`, `theme`, `text`, `color` — is unchanged.)

- [ ] **Step 6: Run the tests to verify they pass**

Run the quick command on `tests/ui/screens/tst_run_detail_screen.qml` (whole file) and on `tests/ui/tst_runs_flow.qml` (whole file).
Expected: `Totals: … 0 failed` for both, and no `TypeError` / `ReferenceError` / `Unable to assign` line.

- [ ] **Step 7: Commit**

```bash
git add ui/screens/RunDetailScreen.qml tests/ui/screens/tst_run_detail_screen.qml tests/ui/tst_runs_flow.qml
git commit -m "feat(runs): Run detail's header reads the run's title from its own project's map, then its short id in dim"
```

---

### Task 2: Tree lines name each card from the run's own map, else its short id

**Files:**
- Modify: `ui/screens/RunDetailScreen.qml` (header comment l.10-18; `cardOf` / `titleOf` l.69-79; `cardLine` l.94-104; `StoryBlock`'s `runStory` text l.330-338; `SubtaskBlock`'s `runSubtaskLabel` text l.368-379; new `CardLine` component before `component AttemptRow`)
- Test: `tests/ui/screens/tst_run_detail_screen.qml` (tree tests l.183-201, malformed test l.364-372, new tests before `test_the_timeline_and_attempts_show_under_the_selected_subtask_only`)
- Test: `tests/ui/tst_runs_real_data.qml:135-137`

**Interfaces:**
- Consumes: `screen.titles` (Task 1); `Runs.cardTitle(id, run, titles)` → the map's own usable title, else am's story title, else `""` (always `""` for a non-string or empty id); `make()` / `run(…, { root })` / `s.titles.titlesByRoot` from Task 1's fixture.
- Produces: `RunDetailScreen.nameOf(id)` → string; `leadOf(id, status)` → `"<glyph> <name>"`; `tailOf(status, phase)` → `"<status> · <phase>"` (empty parts left out); inline `component CardLine: Row` with `property string lead`, `property string tail`, `property color color`, `readonly property string text` (`lead + " · " + tail`, or whichever one is non-empty), and child texts `<objectName>Lead` / `<objectName>Tail`. `runStory<i>` and `runSubtaskLabel<i>_<j>` are `CardLine`s; their `text`, `color`, `opacity` and `visible` read as before.

- [ ] **Step 1: Update the existing tree expectations**

In `test_story_and_subtask_rows_carry_glyph_title_status_and_phase`, replace its five `compare` lines with:

```qml
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " Runs screens · started")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " RunDetailScreen · started · implement.2")
    compare(H.find(s.screen, "runSubtaskLabel0_1").text, RG.glyphOf("done") + " Old work · done · spec.1")
    compare(H.find(s.screen, "runStory1").text, RG.glyphOf("cancelled") + " Dropped story · cancelled")
    compare(H.find(s.screen, "runSubtaskLabel1_0").text, "Shelved", "no status, no phase: just the card")
```

In `test_a_malformed_run_renders_without_throwing`, replace:

```qml
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, "t9")
```

with:

```qml
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, "…t9", "an id shorter than 8 is shown whole")
```

`test_terminal_brd_cards_are_dimmed_not_hidden` stays as it is.

- [ ] **Step 2: Write the failing new tree tests**

Insert this block directly before `function test_the_timeline_and_attempts_show_under_the_selected_subtask_only() {`:

```qml
  // A run of /home/u/b with the open board's ids.
  function betaDetail() { return [run("run-20261004-19efcddc", "started", true, { root: "/home/u/b", tree: detailTree() })] }

  // A run of /home/u/b whose ids the open board lacks; storyTitle is am's
  // own title of the story, when given.
  function betaOnly(storyTitle) {
    var story = { card_id: "s-beta-00000001", status: "started", subtasks: ["t-beta-00000002"] }
    if (storyTitle !== undefined) story.title = storyTitle
    return [run("run-20261004-19efcddc", "started", true, { root: "/home/u/b", tree: {
      stories: [story], subtasks: [{ card_id: "t-beta-00000002", status: "started", phases: [] }] } })]
  }

  function test_a_run_of_another_project_titles_its_tree_from_its_own_map() {
    var s = make(betaDetail()); if (!s) return
    s.titles.titlesByRoot = {
      "/home/u/a": { M3: "Alpha milestone", s1: "Alpha story", t1: "Alpha sub" },
      "/home/u/b": { M3: "Beta milestone", s1: "Beta story", t1: "Beta sub", t2: "Beta old", s2: "Beta dropped", t3: "Beta shelved" } }
    compare(H.find(s.screen, "runDetailTitle").text, "Beta milestone")
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " Beta story · started")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " Beta sub · started · implement.2")
    compare(H.find(s.screen, "runSubtaskLabel1_0").text, "Beta shelved")
  }

  function test_cards_of_a_project_that_is_not_open_and_not_on_the_board() {
    var s = make(betaOnly()); if (!s) return
    s.titles.titlesByRoot = { "/home/u/b": { "s-beta-00000001": "Beta story", "t-beta-00000002": "Beta sub" } }
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " Beta story · started")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " Beta sub · started")
    compare(H.find(s.screen, "runStory0").opacity, 1)
    compare(H.find(s.screen, "runSubtask0_0").opacity, 1)
  }

  function test_a_card_without_a_title_shows_its_short_id() {
    var s = make(betaOnly()); if (!s) return
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " …00000001 · started")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " …00000002 · started")
    s.runs.runs = betaOnly("am story")
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " am story · started", "am's own story title")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " …00000002 · started", "am has no subtask titles")
    s.runs.runs = betaOnly()
    s.app.runTitles = null
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " …00000001 · started")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " …00000002 · started")
    compare(H.find(s.screen, "runDetailTitle").text, "milestone …M3")
  }

  function test_titles_follow_the_map() {
    var s = make(betaOnly()); if (!s) return
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " …00000001 · started")
    s.titles.titlesByRoot = { "/home/u/b": { M3: "Beta milestone", "s-beta-00000001": "Beta story", "t-beta-00000002": "Beta sub" } }
    compare(H.find(s.screen, "runDetailTitle").text, "Beta milestone")
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " Beta story · started")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " Beta sub · started")
  }

  // app.runTitles set after the screen exists is read.
  function test_titles_arriving_after_the_screen_are_read() {
    var s = make(betaOnly()); if (!s) return
    var store = s.app.runTitles
    s.app.runTitles = null
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " …00000001 · started")
    store.titlesByRoot = { "/home/u/b": { "s-beta-00000001": "Beta story" } }
    s.app.runTitles = store
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " Beta story · started")
  }

  function test_a_run_with_no_project_uses_no_map() {
    var s = make([run("run-20261004-19efcddc", "started", true, { root: "", tree: detailTree() })]); if (!s) return
    s.titles.titlesByRoot = { "/home/u/a": { M3: "Alpha milestone", s1: "Runs screens", t1: "RunDetailScreen" }, "": { s1: "Rootless" } }
    compare(H.find(s.screen, "runDetailTitle").text, "milestone …M3")
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " …s1 · started")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " …t1 · started · implement.2")
  }

  function test_dimming_reads_the_open_board_only() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runSubtask0_1").opacity, 0.5)
    compare(H.find(s.screen, "runStory1").opacity, 0.5)
    compare(H.find(s.screen, "runSubtask1_0").opacity, 0.5)
    compare(H.find(s.screen, "runStory0").opacity, 1)
    compare(H.find(s.screen, "runSubtask0_0").opacity, 1)
    var tree = detailTree()
    tree.stories[0].subtasks.push("t-beta-00000002")
    tree.subtasks.push({ card_id: "t-beta-00000002", status: "started", phases: [] })
    s.runs.runs = [run("run-20261004-19efcddc", "started", true, { root: "/home/u/b", tree: tree })]
    s.titles.titlesByRoot = { "/home/u/b": { t2: "Beta open", "t-beta-00000002": "Beta sub" } }
    compare(H.find(s.screen, "runSubtaskLabel0_1").text, RG.glyphOf("done") + " Beta open · done · spec.1")
    compare(H.find(s.screen, "runSubtask0_1").opacity, 0.5, "the open board has t2 merged")
    compare(H.find(s.screen, "runSubtaskLabel0_2").text, RG.glyphOf("running") + " Beta sub · started")
    compare(H.find(s.screen, "runSubtask0_2").opacity, 1, "an id the board lacks is never dimmed")
  }

  // A card title of any length elides; the status and phase stay on the row.
  function test_a_long_card_title_never_pushes_the_status_or_phase_off_the_row() {
    var s = make(detail()); if (!s) return
    var long = "Long"
    for (var i = 0; i < 40; i++) long += " a very long card title"
    s.titles.titlesByRoot = { "/home/u/a": { s1: long, t1: long } }
    var rows = [["runStory0", "started"], ["runSubtaskLabel0_0", "started · implement.2"]]
    for (var j = 0; j < rows.length; j++) {
      var line = H.find(s.screen, rows[j][0])
      compare(line.text, RG.glyphOf("running") + " " + long + " · " + rows[j][1])
      var lead = H.find(s.screen, rows[j][0] + "Lead")
      verify(lead.width < lead.implicitWidth, rows[j][0] + "'s title is elided")
      var tail = H.find(s.screen, rows[j][0] + "Tail")
      compare(tail.text, "· " + rows[j][1])
      var right = tail.mapToItem(line, 0, 0).x + tail.width
      verify(right <= line.width, rows[j][0] + "'s status stays on the row: right edge " + right + " of " + line.width)
    }
  }

  // Own keys only: an id named like a prototype member has no title.
  function test_a_prototype_key_id_is_no_title() {
    var tree = { stories: [{ card_id: "__proto__", status: "started", subtasks: ["constructor"] }],
                 subtasks: [{ card_id: "constructor", status: "started", phases: [] }] }
    var s = make([run("run-20261004-19efcddc", "started", true, { tree: tree })]); if (!s) return
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " …_proto__ · started")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " …structor · started")
  }

  // A new map renames; the selected attempt, its timeline and output stay.
  function test_a_new_map_keeps_the_selected_attempt_and_its_output() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsText = "3 passed"
    s.runs.logsFetchedMs = Date.now() - 14000
    s.titles.titlesByRoot = { "/home/u/a": { t1: "Renamed" } }
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " Renamed · started · implement.2")
    compare(s.runs.selectedAttempt, sel("t1", "implement", 2))
    compare(H.find(s.screen, "runTimeline0_0").visible, true)
    compare(H.find(s.screen, "runAttemptLabel0_0_2").text, "› " + RG.glyphOf("running") + " implement.2 started")
    compare(H.find(s.screen, "runOutputHeading").text, "Output · t1 implement.2")
    compare(H.find(s.screen, "runOutputText").text, "3 passed")
  }

```

In `tests/ui/tst_runs_real_data.qml`, in `test_run_detail_of_the_done_run_shows_its_stories_and_subtasks`, replace:

```qml
    verify(label.indexOf("7442d674-e0d4-4048-96ee-cd27b5ba34f8") >= 0, label)
```

with:

```qml
    compare(label.indexOf("7442d674-e0d4-4048-96ee-cd27b5ba34f8"), -1, "never the full id: " + label)
    verify(label.indexOf("…b5ba34f8") >= 0, "no board titles it: its short id: " + label)
```

(That harness applies no board, so the open project's map has no entry for the subtask and am records no subtask titles: the label is `✔ …b5ba34f8 · done · review.1`. The following `verify(label.endsWith("· review.1"), label)` line stays.)

- [ ] **Step 3: Run the tests to verify they fail**

Run the quick command on `tests/ui/screens/tst_run_detail_screen.qml` (whole file), then on `tests/ui/tst_runs_real_data.qml` with `RunsRealData::test_run_detail_of_the_done_run_shows_its_stories_and_subtasks`.
Expected in the screen file: FAIL for `test_story_and_subtask_rows_carry_glyph_title_status_and_phase`, `test_a_malformed_run_renders_without_throwing`, `test_a_run_of_another_project_titles_its_tree_from_its_own_map`, `test_cards_of_a_project_that_is_not_open_and_not_on_the_board`, `test_a_card_without_a_title_shows_its_short_id`, `test_titles_follow_the_map`, `test_titles_arriving_after_the_screen_are_read`, `test_a_run_with_no_project_uses_no_map`, `test_dimming_reads_the_open_board_only`, `test_a_long_card_title_never_pushes_the_status_or_phase_off_the_row`, `test_a_prototype_key_id_is_no_title`, `test_a_new_map_keeps_the_selected_attempt_and_its_output` (lines still carry the full id and the board's title); every other test PASS. The real-data test FAILs on `never the full id`.

- [ ] **Step 4: Name a card from the run's map, else its short id**

In `ui/screens/RunDetailScreen.qml`, replace:

```qml
  // The brd card behind an id, or null. Own keys only, so "__proto__" is no card.
  function cardOf(id) {
    var map = screen.app.board ? screen.app.board.cardMap : null
    if (!map || typeof id !== "string" || id === "") return null
    return Object.prototype.hasOwnProperty.call(map, id) ? map[id] : null
  }

  function titleOf(id) {
    var card = screen.cardOf(id)
    return card && typeof card.title === "string" ? card.title : ""
  }
```

with:

```qml
  // The brd card behind an id on the open board, or null. Own keys only, so
  // "__proto__" is no card.
  function cardOf(id) {
    var map = screen.app.board ? screen.app.board.cardMap : null
    if (!map || typeof id !== "string" || id === "") return null
    return Object.prototype.hasOwnProperty.call(map, id) ? map[id] : null
  }

  // The card's title in the run's map (cardTitle), else "…" and the id's last
  // 8 characters (all of a shorter one); "" for a non-string or empty id.
  function nameOf(id) {
    var title = Runs.cardTitle(id, screen.run, screen.titles)
    if (title !== "") return title
    return typeof id === "string" && id !== "" ? "…" + id.slice(-8) : ""
  }
```

Replace the whole `cardLine` function:

```qml
  // "<glyph> <id> <title> · <status>", each part only when it has something.
  function cardLine(id, status) {
    var parts = []
    var glyph = screen.glyphOf(status)
    if (glyph !== "") parts.push(glyph)
    parts.push(id)
    var title = screen.titleOf(id)
    if (title !== "") parts.push(title)
    var line = parts.join(" ")
    return status !== "" ? line + " · " + status : line
  }
```

with:

```qml
  // "<glyph> <name>", each part only when it has something.
  function leadOf(id, status) {
    var parts = []
    var glyph = screen.glyphOf(status)
    if (glyph !== "") parts.push(glyph)
    var name = screen.nameOf(id)
    if (name !== "") parts.push(name)
    return parts.join(" ")
  }

  // "<status> · <phase>", each part only when it has something.
  function tailOf(status, phase) {
    var parts = []
    if (status !== "") parts.push(status)
    if (phase !== "") parts.push(phase)
    return parts.join(" · ")
  }
```

- [ ] **Step 5: A card line whose title elides and whose status stays**

Insert directly before `  component AttemptRow: UI.ListRow {`:

```qml
  // A card's line, `text` "<lead> · <tail>" (just the one that is not ""):
  // the lead elides so the tail stays on the row.
  component CardLine: Row {
    id: cardLine
    property string lead: ""
    property string tail: ""
    property color color: screen.theme.foreground
    readonly property string text: cardLine.lead === "" || cardLine.tail === ""
      ? cardLine.lead + cardLine.tail : cardLine.lead + " · " + cardLine.tail

    spacing: Style.space(4)

    UI.ThemedText {
      objectName: cardLine.objectName + "Lead"
      theme: screen.theme
      width: Math.max(0, Math.min(implicitWidth, cardLine.width - (lineTail.visible ? lineTail.width + cardLine.spacing : 0)))
      text: cardLine.lead
      color: cardLine.color
      elide: Text.ElideRight
    }

    UI.ThemedText {
      id: lineTail
      objectName: cardLine.objectName + "Tail"
      theme: screen.theme
      visible: cardLine.tail !== ""
      text: cardLine.lead !== "" ? "· " + cardLine.tail : cardLine.tail
      color: cardLine.color
    }
  }

```

In `component StoryBlock`, replace:

```qml
    UI.ThemedText {
      objectName: "runStory" + storyBlock.index
      theme: screen.theme
      width: parent.width
      opacity: !storyBlock.story.other && screen.isClosed(storyBlock.story.card_id) ? 0.5 : 1
      text: storyBlock.story.other ? storyBlock.story.label : screen.cardLine(storyBlock.story.card_id, storyBlock.story.status)
      color: screen.isUrgent(storyBlock.story.status) ? screen.theme.urgent : screen.theme.foreground
      elide: Text.ElideRight
    }
```

with:

```qml
    CardLine {
      objectName: "runStory" + storyBlock.index
      width: parent.width
      opacity: !storyBlock.story.other && screen.isClosed(storyBlock.story.card_id) ? 0.5 : 1
      lead: storyBlock.story.other ? storyBlock.story.label : screen.leadOf(storyBlock.story.card_id, storyBlock.story.status)
      tail: storyBlock.story.other ? "" : screen.tailOf(storyBlock.story.status, "")
      color: screen.isUrgent(storyBlock.story.status) ? screen.theme.urgent : screen.theme.foreground
    }
```

In `component SubtaskBlock`, replace:

```qml
      UI.ThemedText {
        objectName: "runSubtaskLabel" + subBlock.key
        theme: screen.theme
        width: parent.width
        text: {
          var line = screen.cardLine(subBlock.subtask.card_id, subBlock.subtask.status)
          var phase = screen.phaseText(subBlock.subtask)
          return phase !== "" ? line + " · " + phase : line
        }
        color: screen.isUrgent(subBlock.subtask.status) ? screen.theme.urgent : screen.theme.foreground
        elide: Text.ElideRight
      }
```

with:

```qml
      CardLine {
        objectName: "runSubtaskLabel" + subBlock.key
        width: parent.width
        lead: screen.leadOf(subBlock.subtask.card_id, subBlock.subtask.status)
        tail: screen.tailOf(subBlock.subtask.status, screen.phaseText(subBlock.subtask))
        color: screen.isUrgent(subBlock.subtask.status) ? screen.theme.urgent : screen.theme.foreground
      }
```

Check: `grep -n "cardLine(\|titleOf" ui/screens/RunDetailScreen.qml` prints nothing.

- [ ] **Step 6: State the screen's title contract in its header comment**

Replace:

```qml
// never presented as a live tail. Run state always comes from am (the run
// store), never from a brd status; brd's board only lends titles and dims the
// cards it has closed. It reads the run store and asks it to show another
// attempt or fetch again; it owns no state of its own. Ages are read against
// the clock when a logs reply lands or a snapshot replaces the runs: no timer.
```

with:

```qml
// never presented as a live tail. Run state always comes from am (the run
// store), never from a brd status. Titles come from the run's own project map
// in app.runTitles: the header reads the run's title, then its short id in
// dim; each tree card its title, else its short card id. brd's board only dims
// the cards it has closed. It reads the run store and asks it to show another
// attempt or fetch again; it owns no state of its own. Ages are read against
// the clock when a logs reply lands or a snapshot replaces the runs: no timer.
```

- [ ] **Step 7: Run the tests to verify they pass**

Run the quick command on `tests/ui/screens/tst_run_detail_screen.qml`, `tests/ui/tst_runs_real_data.qml` and `tests/ui/tst_runs_flow.qml` (whole files).
Expected: `Totals: 39 passed, 0 failed` (screen), `9 passed, 0 failed` (real data), `40 passed, 0 failed` (flow); no `TypeError` / `ReferenceError` / `Unable to assign` / `non-existent` line.

- [ ] **Step 8: Commit**

```bash
git add ui/screens/RunDetailScreen.qml tests/ui/screens/tst_run_detail_screen.qml tests/ui/tst_runs_real_data.qml
git commit -m "feat(runs): Run detail names each card from its run's own project's map, else its short id"
```

---

### Task 3: The architecture doc and the README describe titled Run detail

**Files:**
- Modify: `docs/architecture.md:168`
- Modify: `README.md:154`

**Interfaces:**
- Consumes: the behaviour shipped in Tasks 1-2 (no code).
- Produces: nothing code reads.

No test pins prose; the gate in Step 3 checks nothing else broke (`tests/architecture` reads `docs/architecture.md`).

- [ ] **Step 1: `docs/architecture.md:168`**

That line is one long paragraph; make two in-place replacements in it. Replace:

```
`RunsScreen` and `CardDetailScreen` also `app.runTitles`
```

with:

```
`RunsScreen`, `RunDetailScreen` and `CardDetailScreen` also `app.runTitles`
```

and replace:

```
`ui/screens/RunDetailScreen.qml` (view mode `run`) shows the header (state, milestone, branch prefix, base, lease), the `runTree` story > subtask > phase > attempt tree plus the Integrate / Bases / Base rows (cards brd has closed are dimmed, never hidden),
```

with:

```
`ui/screens/RunDetailScreen.qml` (view mode `run`) shows the header (the run's title, `runTitle` with `titlesOfRun(run, app.runTitles.titlesByRoot)`, then the short id in `dim`; state, milestone, branch prefix, base, lease), the `runTree` story > subtask > phase > attempt tree plus the Integrate / Bases / Base rows (each story and subtask named by `cardTitle` with that map, else its short card id, `…` and the id's last 8 characters; cards the open project's board has closed are dimmed, never hidden -- another project's cards are never dimmed),
```

Check: `grep -c "RunDetailScreen\` and \`CardDetailScreen\` also" docs/architecture.md` prints `1`.

- [ ] **Step 2: `README.md:154`**

In the **Runs** bullet, replace:

```
Enter or a click opens **Run detail**: state, milestone, branch prefix, base and lease; the story > subtask > phase > attempt tree (plus the orchestrator's own Integrate / Bases / Base rows);
```

with:

```
Enter or a click opens **Run detail**: the run's title with its short id dimmed, state, milestone, branch prefix, base and lease; the story > subtask > phase > attempt tree, each card named by its title on the run's own project's board, else the last 8 characters of its id (`…<8>`), plus the orchestrator's own Integrate / Bases / Base rows;
```

(The rest of the sentence — `and an output pane holding one attempt's …` — is unchanged.)

- [ ] **Step 3: Run the full gate**

Run: `timeout 900 bash tests/run.sh`
Expected: exit status 0; pytest `… passed` with no failures; every `Totals:` line `0 failed`; no warning line other than `width' of null`.

- [ ] **Step 4: Commit**

```bash
git add docs/architecture.md README.md
git commit -m "docs(runs): Run detail reads the run's title and each card's title from its own project's map"
```
<!-- task-pipeline: validated -->
