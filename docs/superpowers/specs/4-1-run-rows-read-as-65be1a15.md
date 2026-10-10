# 4.1 Run rows read as titles — design

Card: `65be1a15` (subtask of story `5e9efb63`). Parent design:
`docs/superpowers/specs/2026-10-05-run-history-titles-design.md`, cited below as "P l.N".

## Purpose

Wherever a run is listed by the Runs screen, the card RUNS rows and the cancel dialog, it reads
as its work: the run's title from **its own project's** titles map (the open project and every
other registered project alike), with the short run id beside it in `dim` (P l.48-50, l.112-115).
A project whose board cannot be read says so quietly in its group header (P l.91-94, l.183,
l.198), and the Runs footer gains **Refresh titles** (P l.88, l.191).

## What already exists (not touched by this card)

- `Runs.runTitle(run, titles)` and `Runs.runSubtitle(run)` (`core/domain/runs.js:585-605`).
  `titles` is ONE project's `{id: title}` map; any non-plain-object is `{}`, giving the fallback
  `milestone …<8>` / `story …<8>` / `card …<8>`, or the short id when the run names nothing.
  `runSubtitle(run) === Runs.shortId(run)` (P l.99-104).
- `Runs.runRoot(run)` (`runs.js:1537`) and the private `_titlesFor(run, titlesByRoot)`
  (`runs.js:794`): the run's project map, `{}` for a missing or non-object map and for a run
  whose root is `""`. `searchRuns` and `newAlerts` use it.
- `app.runTitles` (`RunTitlesStore`, `core/stores/App.qml:171`): `titlesByRoot`
  (`{root: {id: title}}`), `titleStatus` (`{root: "loading" | "ok" | "unreachable"}`), both keyed
  by the root with its trailing `/` removed, which is exactly `run.project.root` from
  `Runs.withProject`; and `refreshTitles()` (`core/stores/RunTitlesStore.qml:7-26, :56`). The
  open project's map mirrors `app.board.cardMap`.

## Inherited constraints

- Callers pass the run's project map, `titlesByRoot[run.project.root]`; a missing map is `{}`
  (P l.102-103).
- Rows show the title, then the short id in `dim` (P l.112).
- An unreachable project: ids, no toast, no banner, no `urgent` text; its group header carries a
  dim `titles unavailable` caption (P l.91-94, l.183, l.198).
- **Refresh titles** in the Runs footer calls `refreshTitles()` (P l.88, l.191).
- The cancel dialog's detail and the card RUNS rows show the title (P l.114-115).
- UI tests: titled rows with the short id, `titles unavailable`, Refresh titles (P l.224-226).
- `docs/architecture.md` layering: screens receive `app` / `navigator` and never import
  `core/stores` (`docs/architecture.md:168`); shared components are reused, not copied
  (`tests/architecture/test_layers.py:298`); glyphs come only from `ui/components/runGlyphs.js`
  (`tests/architecture/test_icon_glyphs.py`). Comments state the contract only, no narrative.

## Behavior

### B1. One public lookup for a run's project map (`core/domain/runs.js`)

`Runs.titlesOfRun(run, titlesByRoot)` is public, with exactly `_titlesFor`'s contract: the own
entry of `titlesByRoot` for `runRoot(run)` when `titlesByRoot` is a plain object and that entry
a plain object; `{}` otherwise, and always for a run whose root is `""`. It never throws.
`searchRuns` and `newAlerts` keep their behavior (they may call it in place of `_titlesFor`, or
`_titlesFor` may be renamed to it). The three UI sites below use it, so none of them repeats the
lookup.

### B2. Runs rows (`ui/screens/RunsScreen.qml`)

1. Row `i`'s first line is, left to right: the state glyph (`runRowGlyph<i>`, unchanged), the
   title (`runRowTitle<i>`), then the subtitle (`runRowId<i>`).
2. `runRowTitle<i>.text` is
   `Runs.runTitle(run, Runs.titlesOfRun(run, screen.app.runTitles.titlesByRoot))`. It elides on
   the right and takes the width the glyph and the subtitle leave.
3. `runRowId<i>.text` is `Runs.runSubtitle(run)` (the short id, e.g. `…live0001`), variant
   `caption`, colour `screen.theme.dim`. Its text is never elided away by the title.
4. The title follows the map: assigning a new `titlesByRoot` re-titles the rows with no other
   input.
5. A run of a project with no map, an empty map or a map lacking the run's ids shows the
   fallback (`milestone …<8>`, etc.). A run with no project (root `""`) never uses any map.
6. Every other part of the row (progress, phase, age, state line, reason, controls, Open
   project) is unchanged.

### B3. `titles unavailable` in a group header (`RunsScreen.qml`)

1. Each header entry from `entriesOf` carries a scalar boolean `titlesUnavailable`: true when
   `app.runTitles.titleStatus` (a plain object) has an own entry for the group's root, by
   `rootKey`, equal to `"unreachable"`. This applies to both kinds of header (a group with runs
   and a registry root with an error and no runs). `entries` re-evaluates when `titleStatus`
   changes.
2. `RunGroupHeader` shows a `UI.ThemedText` `runGroupTitles<g>`, variant `caption`, colour
   `screen.theme.dim` (never `urgent`), text exactly `titles unavailable`, visible only when its
   entry's `titlesUnavailable` is true. It sits in the header's name row, after the counts; the
   name's width leaves room for it.
3. `"loading"`, `"ok"`, no entry, or a `titleStatus` that is not an object: no caption.
4. Under a project filter the list is flat with no header, so no caption shows (no other place
   carries it).

### B4. Refresh titles (`RunsScreen.qml`)

A `UI.ActionButton` `runsRefreshTitles`, text `Refresh titles`, in the footer area (beside the
Notify on escalation row or directly above `runsFooter`). Each click calls
`screen.app.runTitles.refreshTitles()` once and does nothing else. It is visible whenever the
footer is, i.e. hidden while am is missing (no title fetches then, P l.203).

### B5. Card RUNS rows (`ui/screens/CardDetailScreen.qml`)

`CardRunRow` reads, left to right: badge, `cardRunTitle<i>`
(`Runs.runTitle(run, Runs.titlesOfRun(run, detailCard.app.runTitles.titlesByRoot))`, variant
`small`), `cardRunId<i>` (`Runs.runSubtitle(run)`, variant `caption`, colour `theme.dim`), then
phase and age unchanged. Runs with no project keep the fallback (`milestone …m1` in the existing
test).

### B6. Cancel dialog detail (`ui/Panel.qml`)

`runCancelModal.detail` is `Runs.runTitle(run, Runs.titlesOfRun(run,
appStores.runTitles.titlesByRoot))` for `run = appStores.runs.runById(cancelRunId)`, `""` when
that run is not listed. The message (`Cancel run …<8>? …`) is unchanged.

### B7. Docs

- `docs/architecture.md:168`: the run screens also read `app.runTitles`; a Runs row is glyph,
  title (`runTitle` with the run's project map via `titlesOfRun`), the short id in `dim`, …; a
  group header adds the dim `titles unavailable` caption when the project's `titleStatus` is
  `unreachable`; the footer area has `Refresh titles` (`refreshTitles()`); the card RUNS row and
  the cancel dialog's detail read the titled form.
- `docs/architecture.md:183` (runs.js paragraph): name `titlesOfRun`.
- `README.md:142` (card RUNS: "title, then short id") and `README.md:154` (Runs rows: the title
  is the milestone's / story's / card's title from that project's board, short id beside it;
  `titles unavailable`; **Refresh titles**). Replace "title (its milestone id)".
- The RunsScreen and CardDetailScreen header comments list the new row order, the caption and
  the button.

## Error paths

- `app.runTitles.titlesByRoot` or `titleStatus` null, not an object, or holding a non-object
  entry: fallback titles and no caption; nothing throws and no warning text appears.
- A run whose `project` is missing: fallback title, short id subtitle.
- `refreshTitles()` is fire-and-forget; the button shows no state of its own.

## Tests

Write every test first and watch it fail. Gate: `bash tests/run.sh` (includes
`tests/architecture`).

**Domain unit (`tests/core/domain/tst_runs.qml`)** — tier: pure JS domain test, because
`titlesOfRun` is a new public domain function:

- T1 `test_titles_of_run_is_the_runs_project_map`: a run tagged `/home/u/a` with
  `{"/home/u/a": {m: "M"}, "/home/u/b": {m: "Other"}}` gives `{m: "M"}`; the same map for a run
  tagged `/home/u/b` gives `{m: "Other"}`; an untagged run, a missing root, `null`, `"x"` and a
  non-object entry give `{}`.

**Screen unit (`tests/ui/screens/tst_runs_screen.qml`)** — tier: screen test with the bespoke
mock app, because the screen's bindings to `app.runTitles` are what is under test. Add to the
`appC` mock a `runTitles` QtObject (`titlesByRoot: ({})`, `titleStatus: ({})`,
`refreshCalls: 0`, `refreshTitles()` incrementing it) and pass it in `make()`:

- T2 `test_a_row_reads_its_title_then_its_short_id_in_dim`: `twoProjects()` with
  `titlesByRoot = {"/home/u/b": {zeta: "Ship zeta"}}`; row 2 (`run-b-live0003`) title
  `Ship zeta`, `runRowId2` `…live0003`, its colour `theme.dim`, and its x greater than the
  title's x.
- T3 `test_the_open_and_another_project_title_from_their_own_maps`: runs of `/home/u/a` (open)
  and `/home/u/b` both with `milestone_id` `m1`; maps `{"/home/u/a": {m1: "Alpha M"},
  "/home/u/b": {m1: "Beta M"}}`; each row shows its own project's title and its own short id.
- T4 `test_without_a_map_the_row_falls_back`: no map → `milestone …zeta`; a map for the other
  root only → still the fallback; replacing `titlesByRoot` re-titles the row.
- T5 `test_an_unreachable_project_header_says_titles_unavailable`: `twoProjects()` with
  `titleStatus = {"/home/u/b": "unreachable", "/home/u/a": "ok"}`; beta's header caption visible
  with text `titles unavailable`, colour `theme.dim`, not `urgent`; alpha's hidden; `"loading"`
  hides it; under a project filter no `runGroupTitles*` is visible.
- T6 `test_refresh_titles_calls_the_store`: click `runsRefreshTitles` (via `tap`) →
  `refreshCalls === 1`; text `Refresh titles`; hidden while `amStatus === "missing"`.
- Update `test_a_row_shows_short_id_title_progress_phase_and_age` only if the reorder breaks
  it; its expected texts (`…live0001`, `milestone …alpha`) stay.

**Screen unit (`tests/ui/screens/tst_card_detail_screen.qml`)** — tier: screen test on the real
App, because it is the existing harness for RUNS rows:

- T7 `test_a_runs_row_reads_its_projects_title_then_its_short_id`: `withRuns(s)` with the
  runs tagged `Runs.withProject(r, "/home/u/b", "beta")` (or a project not open) and
  `s.app.runTitles.titlesRunner.cancel()` then `s.app.runTitles.titlesByRoot =
  {"/home/u/b": {m1: "Shipped M1"}}`; open `s1`; `cardRunTitle0` is `Shipped M1`, `cardRunId0`
  is `…000000a1` in `theme.dim`, to the title's right. The existing untagged test keeps
  `milestone …m1`.

**Panel flow (`tests/ui/tst_runs_flow.qml`)** — tier: real Panel integration, because the
dialog's `detail` binding lives in Panel:

- T8 `test_the_cancel_dialog_detail_is_the_runs_title`: `make()`, then
  `p.app.board.applyTreeData([{id: "alpha", title: "Alpha work", status: "todo", description:
  "", blocked_by: [], children: []}])` so the open project's map titles milestone `alpha`
  (if the open-root mirror does not fire in this harness, cancel `titlesRunner` and assign
  `titlesByRoot` directly); open the cancel dialog on run `…a1` as the existing cancel test
  does; the dialog's detail Text reads `Alpha work`. A run of another project (via `makeTwo()`
  and a direct `titlesByRoot` for `/home/u/b`) reads its own project's title.

`tests/ui/tst_runs_real_data.qml:230-238` (runRowId0 vs cardRunId0 text) keeps passing: both
remain `Runs.runSubtitle`.

## Review focus (inputs no test above pins; the plan should add tests where cheap)

- A root key mismatch (a registry root with a trailing `/`) for the caption: compare via
  `rootKey`, as `entriesOf` does for errors.
- A very long title must not push the short id off the row.
- `titleStatus` changing while the cursor is on a row must not move the cursor (headers are not
  cursor targets; `entries` rebuilding must not change `filteredRuns` indexes).

## Out of scope

- `RunDetailScreen` header/tree titles and the Events pane `titles` input (sibling card).
- Toasts and desktop notifications (done by 3.4), search (done by the domain card).
- Any change to `RunTitlesStore`, `App.qml` composition, `runTitle` / `runSubtitle` semantics,
  history, filters, Show older, the Finished chips.
- A caption for an unreachable project under a project filter.
