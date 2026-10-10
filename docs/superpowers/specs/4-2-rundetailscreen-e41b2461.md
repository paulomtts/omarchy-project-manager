# 4.2 RunDetailScreen: titles for any project — design

Card: `e41b2461` (subtask of story `5e9efb63`, blocked by 4.1 `65be1a15`). Parent design:
`docs/superpowers/specs/2026-10-05-run-history-titles-design.md`, cited below as "P l.N".

## Purpose

Run detail reads as the run's work for a run of **any** registered project, not only the open
one. Its header names the run by its title, with the short run id beside it in `dim`, and its
story > subtask tree names every card by its title from the run's **own** project's titles map;
a card with no known title shows its short card id instead (P l.48-50, l.105-106, l.112-113).
Which cards are dimmed as closed by brd does not change: that still reads the open project's
board only (P l.59).

## What already exists (not touched by this card)

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

## Inherited constraints

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

## Behavior

Throughout, `titles` is the screen's one map for the shown run:
`Runs.titlesOfRun(screen.run, screen.app.runTitles ? screen.app.runTitles.titlesByRoot : null)`
— a readonly property, so every text below re-evaluates when `titlesByRoot` or the run changes.
An `app` with no `runTitles` (null or absent) gives `{}`; nothing throws.

### B1. Header

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

### B2. Tree card lines

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

### B3. Dimming

1. `isClosed(id)` keeps reading `app.board.cardMap` only: a story or subtask row is at opacity
   `0.5` when the open board holds that id with a status `Board.isClosedStatus` reports closed,
   `1` otherwise — the same rule and the same rows as today.
2. The titles map never affects opacity: a card titled from another project's map that the open
   board does not hold is at opacity `1`.

### B4. The Events pane `titles` input

The card and P l.113 name an "Events pane `titles` input". No such pane or input exists in this
codebase (`RunDetailScreen.qml` has no events pane; `ui/components/PhaseTimeline.qml` takes
only `phases`; no QML type under `ui/` declares a `titles` property). There is nothing to wire;
this card adds no Events pane. If one is added later, it receives the same `titles` map.

### B5. Contract text

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

## Error paths

| case | behaviour |
|---|---|
| `app.runTitles` null or absent | `titles` is `{}`: header `runTitle` fallback, tree short ids; no throw, no warning |
| `titlesByRoot` not an object, or the run's entry missing / not an object | same as above |
| a run with no `project` (root `""`) | no map is ever used, even if `titlesByRoot` has an entry for the open root |
| a card id in no map and not an am story | short card id |
| an id shorter than 8 characters | `…` plus the whole id |
| a malformed tree (non-string card ids) | rows render as today; a non-string id gives no title (`cardTitle` is `""`) and its line is built from whatever `runTree` hands over; no throw |
| `app.board` null or no `cardMap` | no row is dimmed; titles unaffected |

## Tests

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

## Review focus

- A very long card or run title must elide, never hide the status, phase, short id or state.
- An id `"__proto__"` or `"constructor"` in the tree: no prototype title, short id shown
  (`cardTitle` uses own keys; the short-id helper must not read the map).
- `titlesByRoot` replaced while an attempt is selected: the selection, the timeline and the
  output pane stay as they were.
- A run of another project sharing an id with an open-board card: the title comes from the
  run's map; the dimming from the board (accepted: P l.59 and the card keep dimming on the open
  board only; ids are UUIDs, so a real collision is not expected).
- `app.runTitles` arriving after the screen is created (null first, then set): titles appear.

## Out of scope

- Any change to `core/domain/runs.js`, `RunTitlesStore`, `App.qml`, `Panel.qml`, `RunsScreen`,
  `CardDetailScreen` (4.1 and earlier cards own them).
- Creating an Events pane or adding a `titles` input to `PhaseTimeline` (B4).
- Showing another project's brd status, or dimming another project's closed cards.
- The output heading's card id, the bookkeeping rows, the attempt rows, history, filters and
  Show older.
