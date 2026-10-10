# 4.1 Run rows read as titles — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every place the panel lists a run — the Runs screen rows, a card's RUNS rows and the cancel dialog — reads as the run's title from its own project's titles map with the short id dim beside it; an unreachable project's group header says `titles unavailable`; the Runs footer area gains **Refresh titles**.

**Architecture:** One public domain lookup, `Runs.titlesOfRun(run, titlesByRoot)` (the existing private `_titlesFor`, renamed and made public), gives a run its own project's `{id: title}` map. `RunsScreen`, `CardDetailScreen` and `Panel` feed that map to the existing `Runs.runTitle` and show `Runs.runSubtitle` (the short id) after the title in `theme.dim`. `RunsScreen` also reads `app.runTitles.titleStatus` for a per-header caption and calls `app.runTitles.refreshTitles()` from a new button. No store changes.

**Tech Stack:** QML (Qt 6, `QtQuick`, `QtTest`), pure JS domain module `core/domain/runs.js`, run by `qmltestrunner`. The gate is `bash tests/run.sh` (pytest incl. `tests/architecture`, then every `tst_*.qml`; any `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `anchors on an item` / `is not a function` line fails it, except the known `width' of null` teardown lines). For a quick single-file or single-test run, from the repo root:

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input <file.qml> [<TestCaseName>::<test_function>] 2>&1 | grep -E "^(PASS|FAIL)|^   Loc|Totals|TypeError|ReferenceError|is not a function|non-existent"
```

The `TestCase` names are `DomainRuns` (`tests/core/domain/tst_runs.qml`), `RunsScreen` (`tests/ui/screens/tst_runs_screen.qml`), `CardDetailScreen` (`tests/ui/screens/tst_card_detail_screen.qml`) and `RunsFlow` (`tests/ui/tst_runs_flow.qml`). Below, "Run the quick command on X" means that command with `-input X` and the named function.

**Spec:** `docs/superpowers/specs/4-1-run-rows-read-as-65be1a15.md` (prepended below).

## Global Constraints

- Callers pass the run's project map, `titlesByRoot[run.project.root]`, through `Runs.titlesOfRun`; a missing map is `{}`. No UI site repeats the lookup.
- Rows show the title, then the short id (`Runs.runSubtitle`) in `dim`.
- An unreachable project: ids, no toast, no banner, no `urgent` text; its group header carries a dim caption whose text is exactly `titles unavailable`.
- **Refresh titles** (text exactly `Refresh titles`) calls `app.runTitles.refreshTitles()` once per click and does nothing else.
- Screens receive `app` / `navigator` and never import `core/stores` (`docs/architecture.md:168`); shared components are reused, not copied (`tests/architecture/test_layers.py:298`); glyphs come only from `ui/components/runGlyphs.js` (`tests/architecture/test_icon_glyphs.py`).
- Comments state the contract only — no narrative, no plan/task/card references.
- No change to `RunTitlesStore`, `App.qml`, `runTitle` / `runSubtitle` semantics, `RunDetailScreen`, toasts, search, history, filters.
- Write every test first and watch it fail. `bash tests/run.sh` green at the end.

## Review Focus

1. **A very long title** must not push the short id off the row: the title elides, the id stays fully on the row. Pinned in Task 2 (`test_a_long_title_never_pushes_the_short_id_off_the_row`).
2. **A `titleStatus` key with a trailing `/`** (`"/home/u/b/"`) must still caption project `/home/u/b`, as `projectErrors` already does via `rootKey`. Pinned in Task 3 (`test_titles_unavailable_matches_the_root_by_its_key_and_ignores_garbage`).
3. **`titleStatus` changing while the cursor is on a row** must not move the cursor or change which run it marks (headers are not cursor targets). Pinned in Task 3 (`test_a_title_status_change_keeps_the_cursor_on_its_run`).
4. **Garbage `titlesByRoot` / `titleStatus`** (null, a string, an array, a non-object entry, a status that is not exactly `"unreachable"`): fallback titles, no caption, nothing throws. Pinned in Task 2 (`test_without_a_map_the_row_falls_back`) and Task 3 (`test_titles_unavailable_matches_the_root_by_its_key_and_ignores_garbage`).
5. **A long project name beside the caption**, and **a failed project with no runs** (the error-only header): the caption stays on the header row and shows on that header kind too. Pinned in Task 3 (`test_a_long_project_name_leaves_room_for_the_caption`, `test_an_error_only_header_also_says_titles_unavailable`).

Every code and test snippet below was applied to a scratch copy of this branch on 2026-10-10 and run: every new test passed, `tst_runs.qml`, `tst_runs_screen.qml`, `tst_card_detail_screen.qml`, `tst_runs_flow.qml` and `tst_runs_real_data.qml` showed 0 failed with no warning lines, and `tests/architecture` passed (153). Colours are compared as `String(color)`: `Qt.colorEqual` reports false for two equal `Qt.darker` colours here.

---

## Spec (prepended; headings demoted one level)

## 4.1 Run rows read as titles — design

Card: `65be1a15` (subtask of story `5e9efb63`). Parent design:
`docs/superpowers/specs/2026-10-05-run-history-titles-design.md`, cited below as "P l.N".

### Purpose

Wherever a run is listed by the Runs screen, the card RUNS rows and the cancel dialog, it reads
as its work: the run's title from **its own project's** titles map (the open project and every
other registered project alike), with the short run id beside it in `dim` (P l.48-50, l.112-115).
A project whose board cannot be read says so quietly in its group header (P l.91-94, l.183,
l.198), and the Runs footer gains **Refresh titles** (P l.88, l.191).

### What already exists (not touched by this card)

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

### Inherited constraints

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

### Behavior

#### B1. One public lookup for a run's project map (`core/domain/runs.js`)

`Runs.titlesOfRun(run, titlesByRoot)` is public, with exactly `_titlesFor`'s contract: the own
entry of `titlesByRoot` for `runRoot(run)` when `titlesByRoot` is a plain object and that entry
a plain object; `{}` otherwise, and always for a run whose root is `""`. It never throws.
`searchRuns` and `newAlerts` keep their behavior (they may call it in place of `_titlesFor`, or
`_titlesFor` may be renamed to it). The three UI sites below use it, so none of them repeats the
lookup.

#### B2. Runs rows (`ui/screens/RunsScreen.qml`)

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

#### B3. `titles unavailable` in a group header (`RunsScreen.qml`)

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

#### B4. Refresh titles (`RunsScreen.qml`)

A `UI.ActionButton` `runsRefreshTitles`, text `Refresh titles`, in the footer area (beside the
Notify on escalation row or directly above `runsFooter`). Each click calls
`screen.app.runTitles.refreshTitles()` once and does nothing else. It is visible whenever the
footer is, i.e. hidden while am is missing (no title fetches then, P l.203).

#### B5. Card RUNS rows (`ui/screens/CardDetailScreen.qml`)

`CardRunRow` reads, left to right: badge, `cardRunTitle<i>`
(`Runs.runTitle(run, Runs.titlesOfRun(run, detailCard.app.runTitles.titlesByRoot))`, variant
`small`), `cardRunId<i>` (`Runs.runSubtitle(run)`, variant `caption`, colour `theme.dim`), then
phase and age unchanged. Runs with no project keep the fallback (`milestone …m1` in the existing
test).

#### B6. Cancel dialog detail (`ui/Panel.qml`)

`runCancelModal.detail` is `Runs.runTitle(run, Runs.titlesOfRun(run,
appStores.runTitles.titlesByRoot))` for `run = appStores.runs.runById(cancelRunId)`, `""` when
that run is not listed. The message (`Cancel run …<8>? …`) is unchanged.

#### B7. Docs

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

### Error paths

- `app.runTitles.titlesByRoot` or `titleStatus` null, not an object, or holding a non-object
  entry: fallback titles and no caption; nothing throws and no warning text appears.
- A run whose `project` is missing: fallback title, short id subtitle.
- `refreshTitles()` is fire-and-forget; the button shows no state of its own.

### Tests

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

### Review focus (inputs no test above pins; the plan should add tests where cheap)

- A root key mismatch (a registry root with a trailing `/`) for the caption: compare via
  `rootKey`, as `entriesOf` does for errors.
- A very long title must not push the short id off the row.
- `titleStatus` changing while the cursor is on a row must not move the cursor (headers are not
  cursor targets; `entries` rebuilding must not change `filteredRuns` indexes).

### Out of scope

- `RunDetailScreen` header/tree titles and the Events pane `titles` input (sibling card).
- Toasts and desktop notifications (done by 3.4), search (done by the domain card).
- Any change to `RunTitlesStore`, `App.qml` composition, `runTitle` / `runSubtitle` semantics,
  history, filters, Show older, the Finished chips.
- A caption for an unreachable project under a project filter.

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `core/domain/runs.js` | Modify `:791-798` (`_titlesFor` → public `titlesOfRun`), `:801`, `:811`, `:1162`, `:1175` | The one lookup of a run's project titles map |
| `tests/core/domain/tst_runs.qml` | Append one test before the final `}` | Pins `titlesOfRun` |
| `ui/screens/RunsScreen.qml` | Header comment `:10-26`; `entries` `:60-61`; new `titlesUnavailableOf`; `entriesOf` `:182-225`; `RunEntry` header `:370-375`; `RunGroupHeader` `:398-449`; `RunRow` first `Row` `:480-509`; `runsNotifyRow` `:313-333` | Titled rows, the header caption, Refresh titles |
| `tests/ui/screens/tst_runs_screen.qml` | New `titlesC` stub, `appC` gains `runTitles`, `make()` passes and returns it; new tests | Screen tests |
| `ui/screens/CardDetailScreen.qml` | `CardRunRow` comment `:220-225` and first `Row` `:240-263` | Titled RUNS rows |
| `tests/ui/screens/tst_card_detail_screen.qml` | Import `runs.js`; one new test | Card RUNS test |
| `ui/Panel.qml` | `runCancelModal` `:831-849` | Titled cancel detail |
| `tests/ui/tst_runs_flow.qml` | Two new tests | Panel flow |
| `docs/architecture.md` | `:168`, `:183` | Layering doc |
| `README.md` | `:142`, `:154` | User doc |

All edits below are exact string replacements: find the **old** text (it occurs once) and replace it with the **new** text.

---

### Task 1: `Runs.titlesOfRun` — the public lookup of a run's project map

**Files:**
- Modify: `core/domain/runs.js:791-798, 801, 811, 1162, 1175`
- Modify: `docs/architecture.md:183`
- Test: `tests/core/domain/tst_runs.qml` (append before the file's last `}`)

**Interfaces:**
- Consumes: `runRoot(run)`, `hasKey(map, key)`, `_isObject(v)`, `_titlesOr(v)` (all existing in `runs.js`); the test file's `mkRun(id, status, live, opts)` (`tst_runs.qml:874`).
- Produces: `Runs.titlesOfRun(run, titlesByRoot) -> object` — `titlesByRoot[runRoot(run)]` (an own key) when `titlesByRoot` is a plain object and that entry a plain object; `{}` otherwise and always for root `""`. Never throws. Tasks 2, 5 and 6 call it.

- [ ] **Step 1: Write the failing test**

Append to `tests/core/domain/tst_runs.qml`, just before its final closing `}` (after `test_new_alerts_titles_by_root`):

```qml

  function test_titles_of_run_is_the_runs_project_map() {
    var a = Runs.withProject(mkRun("run-a-000001", "started", true, {}), "/home/u/a", "A")
    var b = Runs.withProject(mkRun("run-b-000002", "started", true, {}), "/home/u/b", "B")
    var byRoot = { "/home/u/a": { m: "M" }, "/home/u/b": { m: "Other" } }
    compare(JSON.stringify(Runs.titlesOfRun(a, byRoot)), '{"m":"M"}', "the run's own project map")
    compare(JSON.stringify(Runs.titlesOfRun(b, byRoot)), '{"m":"Other"}', "another run, its own map")
    compare(JSON.stringify(Runs.titlesOfRun(mkRun("run-c-000003", "started", true, {}), byRoot)), "{}", "an untagged run")
    var c = Runs.withProject(mkRun("run-c-000003", "started", true, {}), "/home/u/c", "C")
    compare(JSON.stringify(Runs.titlesOfRun(c, byRoot)), "{}", "a root absent from titlesByRoot")

    var outer = [undefined, null, "x", 5, [], true]
    for (var i = 0; i < outer.length; i++)
      compare(JSON.stringify(Runs.titlesOfRun(a, outer[i])), "{}", "titlesByRoot " + i)
    var inner = [null, "M", 5, [], true]
    for (var j = 0; j < inner.length; j++)
      compare(JSON.stringify(Runs.titlesOfRun(a, { "/home/u/a": inner[j] })), "{}", "a non-object entry " + j)

    var emptyRoot = mkRun("run-g-000007", "stopped", null, {})
    emptyRoot.project = { root: "", name: "" }
    compare(JSON.stringify(Runs.titlesOfRun(emptyRoot, { "": { m1: "Never" } })), "{}", "root \"\" never uses a map")
    compare(JSON.stringify(Runs.titlesOfRun(null, byRoot)), "{}", "a null run")
    compare(JSON.stringify(Runs.titlesOfRun("x", byRoot)), "{}", "a string run")
    var ctor = Runs.withProject(mkRun("run-d-000004", "stopped", null, {}), "constructor", "D")
    compare(JSON.stringify(Runs.titlesOfRun(ctor, {})), "{}", "an inherited key is no map")

    var rootsJson = JSON.stringify(byRoot)
    Runs.titlesOfRun(a, byRoot)
    compare(JSON.stringify(byRoot), rootsJson, "titlesByRoot unchanged")
  }
```

- [ ] **Step 2: Run test to verify it fails**

Run the quick command on `tests/core/domain/tst_runs.qml` with `DomainRuns::test_titles_of_run_is_the_runs_project_map`.
Expected: `FAIL!  : ...test_titles_of_run_is_the_runs_project_map() TypeError: Property 'titlesOfRun' of object [object Object] is not a function` (or similar "is not a function").

- [ ] **Step 3: Rename `_titlesFor` to the public `titlesOfRun`**

In `core/domain/runs.js` replace

```js
// The titles map of run's project: titlesByRoot's own entry for runRoot(run)
// when titlesByRoot is a plain object and that entry a plain object; {} for
// anything else, and always for a run whose root is "".
function _titlesFor(run, titlesByRoot) {
```

with

```js
// The titles map of run's project: titlesByRoot's own entry for runRoot(run)
// when titlesByRoot is a plain object and that entry a plain object; {} for
// anything else, and always for a run whose root is "". Never throws.
function titlesOfRun(run, titlesByRoot) {
```

Replace `// map in titlesByRoot, see _titlesFor), current phase and state name. An empty` with `// map in titlesByRoot, see titlesOfRun), current phase and state name. An empty`.

Replace `    var hay = [_stringOr(run.id), runTitle(run, _titlesFor(run, titlesByRoot)), currentPhase(run), runState(run)].join("\n").toLowerCase()` with `    var hay = [_stringOr(run.id), runTitle(run, titlesOfRun(run, titlesByRoot)), currentPhase(run), runState(run)].join("\n").toLowerCase()`.

Replace `// in titlesByRoot (see _titlesFor); without one it is the fallback title.` with `// in titlesByRoot (see titlesOfRun); without one it is the fallback title.`

Replace `      title: runTitle(run, _titlesFor(run, titlesByRoot)),` with `      title: runTitle(run, titlesOfRun(run, titlesByRoot)),`

Then `grep -n "_titlesFor" core/domain/runs.js` must print nothing.

- [ ] **Step 4: Document it in `docs/architecture.md:183`**

Replace

```
`searchRuns(runs, q, titlesByRoot)` (also matches the run's title from `titlesByRoot[run.project.root]`).
```

with

```
`searchRuns(runs, q, titlesByRoot)` (also matches the run's title from `titlesByRoot[run.project.root]`); `titlesOfRun(run, titlesByRoot)` is that lookup: the run's own project map when `titlesByRoot` and its entry are plain objects, else `{}`, always `{}` for a run with no project -- `searchRuns`, `newAlerts` and the run screens read a run's titles through it.
```

- [ ] **Step 5: Run the tests to verify they pass**

Run the quick command on `tests/core/domain/tst_runs.qml` (whole file, no function name).
Expected: `Totals: N passed, 0 failed` — the new test and the existing `test_search_runs_by_title`, `test_search_runs_titles_by_root_garbage`, `test_new_alerts_titles_by_root` all PASS.

- [ ] **Step 6: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml docs/architecture.md
git commit -m "feat(runs): titlesOfRun is the public lookup of a run's project titles map"
```

---

### Task 2: Runs rows read glyph, title, then the short id in dim

**Files:**
- Modify: `ui/screens/RunsScreen.qml:10-26` (header comment), `:480-509` (the row's first `Row`)
- Modify: `docs/architecture.md:168`, `README.md:154`
- Test: `tests/ui/screens/tst_runs_screen.qml`

**Interfaces:**
- Consumes: `Runs.titlesOfRun(run, titlesByRoot)` (Task 1); `Runs.runTitle(run, titles)`, `Runs.runSubtitle(run)` (existing); `app.runTitles.titlesByRoot` (`{root: {id: title}}`).
- Produces: in `tst_runs_screen.qml`, a `titlesC` stub with `titlesByRoot`, `titleStatus`, `refreshCalls`, `refreshTitles()`; `make()` returns `{ ..., titles }`. Tasks 3 and 4 use `s.titles`. In `RunsScreen`, object names `runRowTitle<i>` and `runRowId<i>` keep their names; order is glyph, title, id.

- [ ] **Step 1: Add the run titles stub to the screen test harness**

In `tests/ui/screens/tst_runs_screen.qml`, insert this component directly before `  Component {\n    id: appC`:

```qml
  // The run titles store's surface: the {root: {id: title}} maps, the
  // {root: status} statuses and refreshTitles(), which only counts.
  Component {
    id: titlesC
    QtObject {
      id: ts
      property var titlesByRoot: ({})
      property var titleStatus: ({})
      property int refreshCalls: 0
      function refreshTitles() { ts.refreshCalls += 1 }
    }
  }

```

In `appC`, replace

```qml
      property var runControl: null
```

with

```qml
      property var runControl: null
      property var runTitles: null
```

In `make(list)`, replace

```js
    var control = controlC.createObject(host)
    var app = appC.createObject(host, { nav: nav, runs: runs, runControl: control })
```

with

```js
    var control = controlC.createObject(host)
    var titles = titlesC.createObject(host)
    var app = appC.createObject(host, { nav: nav, runs: runs, runControl: control, runTitles: titles })
```

and replace

```js
    return { app: app, runs: runs, control: control, nav: nav, navi: navi, screen: screen }
```

with

```js
    return { app: app, runs: runs, control: control, titles: titles, nav: nav, navi: navi, screen: screen }
```

In the file's header comment replace `// apart, the RunControlStore properties the screen reads (the real store's` with `// apart, the RunControlStore and RunTitlesStore properties the screen reads (the real store's`.

- [ ] **Step 2: Write the failing tests**

Insert directly after `test_a_row_shows_short_id_title_progress_phase_and_age` (which ends with `compare(H.find(s.screen, "runRowState0").visible, false)\n  }`):

```qml

  // ---- titles (4.1)

  // twoProjects(): row 2 is beta's run-b-live0003, milestone zeta.
  function test_a_row_reads_its_title_then_its_short_id_in_dim() {
    var s = make(twoProjects()); if (!s) return
    s.titles.titlesByRoot = { "/home/u/b": { zeta: "Ship zeta" } }
    wait(20)
    var glyph = H.find(s.screen, "runRowGlyph2")
    var title = H.find(s.screen, "runRowTitle2")
    var id = H.find(s.screen, "runRowId2")
    compare(title.text, "Ship zeta")
    compare(id.text, "…live0003")
    compare(id.visible, true)
    compare(String(id.color), String(s.screen.theme.dim), "the short id is dim")
    verify(glyph.x < title.x, "the glyph comes first")
    verify(title.x < id.x, "the short id follows the title")
  }

  function test_the_open_and_another_project_title_from_their_own_maps() {
    var s = make([tagged(run("run-a-live0001", "started", true, { milestone: "m1" }), "/home/u/a", "alpha"),
                  tagged(run("run-b-live0002", "started", true, { milestone: "m1" }), "/home/u/b", "beta")]); if (!s) return
    s.runs.project = "/home/u/a"
    s.titles.titlesByRoot = { "/home/u/a": { m1: "Alpha M" }, "/home/u/b": { m1: "Beta M" } }
    wait(20)
    compare(H.find(s.screen, "runRowTitle0").text, "Alpha M", "the open project's run")
    compare(H.find(s.screen, "runRowId0").text, "…live0001")
    compare(H.find(s.screen, "runRowTitle1").text, "Beta M", "another project's run, from its own map")
    compare(H.find(s.screen, "runRowId1").text, "…live0002")
  }

  function test_without_a_map_the_row_falls_back() {
    var s = make(twoProjects()); if (!s) return
    compare(H.find(s.screen, "runRowTitle2").text, "milestone …zeta", "no map at all")
    s.titles.titlesByRoot = { "/home/u/a": { zeta: "Wrong project" } }
    compare(H.find(s.screen, "runRowTitle2").text, "milestone …zeta", "only another root's map")
    s.titles.titlesByRoot = { "/home/u/b": { zeta: "Ship zeta" } }
    compare(H.find(s.screen, "runRowTitle2").text, "Ship zeta", "a new titlesByRoot re-titles the row")
    var garbage = [{ "/home/u/b": {} }, null, "x", [], { "/home/u/b": null }, { "/home/u/b": "Ship zeta" }]
    for (var i = 0; i < garbage.length; i++) {
      s.titles.titlesByRoot = garbage[i]
      compare(H.find(s.screen, "runRowTitle2").text, "milestone …zeta", "garbage " + i)
      compare(H.find(s.screen, "runRowId2").text, "…live0003", "garbage " + i + " keeps the id")
    }
    s.runs.runs = [run("run-x-none0009", "started", true, { milestone: "zeta" })]
    s.titles.titlesByRoot = { "": { zeta: "Never" } }
    wait(20)
    compare(H.find(s.screen, "runRowTitle0").text, "milestone …zeta", "a run with no project uses no map")
  }

  // Review Focus 1.
  function test_a_long_title_never_pushes_the_short_id_off_the_row() {
    var s = make(twoProjects()); if (!s) return
    var long = ""
    for (var i = 0; i < 40; i++) long += "a very long run title "
    s.titles.titlesByRoot = { "/home/u/b": { zeta: long } }
    wait(20)
    var title = H.find(s.screen, "runRowTitle2")
    var id = H.find(s.screen, "runRowId2")
    compare(title.elide, Text.ElideRight)
    verify(title.width < title.implicitWidth, "the title is elided")
    compare(id.text, "…live0003")
    var right = id.mapToItem(s.screen, 0, 0).x + id.width
    verify(right <= s.screen.width, "the short id stays on the row: right edge " + right)
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run the quick command on `tests/ui/screens/tst_runs_screen.qml` with each of `RunsScreen::test_a_row_reads_its_title_then_its_short_id_in_dim`, `RunsScreen::test_the_open_and_another_project_title_from_their_own_maps`, `RunsScreen::test_without_a_map_the_row_falls_back`, `RunsScreen::test_a_long_title_never_pushes_the_short_id_off_the_row`.
Expected: all four FAIL — `Actual (): milestone …zeta` / `Expected (): Ship zeta` (and `milestone …m1` vs `Alpha M`; `the title is elided` for the long title). `test_without_a_map_the_row_falls_back` fails at `a new titlesByRoot re-titles the row`.

- [ ] **Step 4: Reorder the row and title it from the run's project map**

In `ui/screens/RunsScreen.qml` replace the row's first `Row` (the block from `      UI.ThemedText {\n        id: rowId` through the title's closing brace):

```qml
      UI.ThemedText {
        id: rowId
        objectName: "runRowId" + row.index
        variant: "caption"
        theme: screen.theme
        text: Runs.shortId(row.run)
      }

      UI.ThemedText {
        objectName: "runRowTitle" + row.index
        theme: screen.theme
        width: Math.max(0, parent.width - (rowGlyph.visible ? rowGlyph.width + parent.spacing : 0)
          - rowId.width - parent.spacing)
        text: Runs.runTitle(row.run)
        elide: Text.ElideRight
      }
```

with

```qml
      UI.ThemedText {
        objectName: "runRowTitle" + row.index
        theme: screen.theme
        width: Math.max(0, parent.width - (rowGlyph.visible ? rowGlyph.width + parent.spacing : 0)
          - rowId.width - parent.spacing)
        text: Runs.runTitle(row.run, Runs.titlesOfRun(row.run, screen.app.runTitles.titlesByRoot))
        elide: Text.ElideRight
      }

      UI.ThemedText {
        id: rowId
        objectName: "runRowId" + row.index
        variant: "caption"
        theme: screen.theme
        text: Runs.runSubtitle(row.run)
        color: screen.theme.dim
      }
```

In the file's header comment replace

```
// project's snapshot error), flat with no header under a project filter. Each
// run is one row (state glyph, short id, title, done/total, current phase,
// age) whose index is its position in the store's filteredRuns, the one list
```

with

```
// project's snapshot error), flat with no header under a project filter. Each
// run is one row (state glyph; title, from the run's own project's map in
// app.runTitles; short id in dim; done/total, current phase, age) whose index
// is its position in the store's filteredRuns, the one list
```

and replace

```
// reads the run store and the project registry and asks the navigator to open
// a run, choose a project or move the cursor; it owns no state of its own.
```

with

```
// reads the run store, the run titles and the project registry and asks the
// navigator to open a run, choose a project or move the cursor; it owns no
// state of its own.
```

- [ ] **Step 5: Run the tests to verify they pass**

Run the quick command on `tests/ui/screens/tst_runs_screen.qml` (whole file).
Expected: `Totals: N passed, 0 failed`, no `TypeError`/`ReferenceError` lines. `test_a_row_shows_short_id_title_progress_phase_and_age` (`…live0001`, `milestone …alpha`), `test_malformed_runs_render_without_throwing` and the tap on `runRowTitle2` near the end of the file still PASS.

- [ ] **Step 6: Update the docs**

In `docs/architecture.md:168` replace

```
The run screens read `app.runs` and `app.runControl` (`BoardScreen` and `GraphScreen` only `app.runs`) and never import `core/stores`.
```

with

```
The run screens read `app.runs` and `app.runControl` (`BoardScreen` and `GraphScreen` only `app.runs`; `RunsScreen` also `app.runTitles`) and never import `core/stores`.
```

and replace

```
Each run is one row (state glyph, short id, title, done/total, current phase, age;
```

with

```
Each run is one row (state glyph; title, `runTitle` with the run's own project map `titlesOfRun(run, app.runTitles.titlesByRoot)`; the short id, `runSubtitle`, in `dim`; done/total, current phase, age;
```

In `README.md:154` replace

```
Each row shows the run's state glyph, short id, title (its milestone id), done/total subtasks, current phase and age;
```

with

```
Each row shows the run's state glyph and its title -- the title of the run's milestone, story or card on that project's own board, else the kind and the id's last 8 characters (`milestone …<8>`) -- with the short id dimmed after it, then done/total subtasks, current phase and age;
```

- [ ] **Step 7: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml docs/architecture.md README.md
git commit -m "feat(runs): a Runs row reads its title from its own project's map, then its short id in dim"
```

---

### Task 3: `titles unavailable` in an unreachable project's group header

**Files:**
- Modify: `ui/screens/RunsScreen.qml` — header comment `:10-12`, `entries` `:60-61`, new function `titlesUnavailableOf` (after `projectError`), `entriesOf` `:182-225`, `RunEntry`'s `headerC` `:370-375`, `RunGroupHeader` `:398-449`
- Modify: `docs/architecture.md:168`, `README.md:154`
- Test: `tests/ui/screens/tst_runs_screen.qml`

**Interfaces:**
- Consumes: `s.titles.titleStatus` (Task 2's stub); `screen.rootKey(path)` (existing).
- Produces: `screen.titlesUnavailableOf(status, root) -> bool`; `entriesOf(groups, runs, roots, errors, filter, status)` (new 6th parameter); header entries carry scalar `titlesUnavailable: bool`; `RunGroupHeader.titlesUnavailable` (bool); object name `runGroupTitles<g>`.

- [ ] **Step 1: Write the failing tests**

In `tests/ui/screens/tst_runs_screen.qml`, insert directly after `test_a_long_title_never_pushes_the_short_id_off_the_row` (Task 2):

```qml

  // twoProjects(): alpha's header is runGroup0, beta's runGroup1.
  function test_an_unreachable_project_header_says_titles_unavailable() {
    var s = make(twoProjects()); if (!s) return
    s.titles.titleStatus = { "/home/u/b": "unreachable", "/home/u/a": "ok" }
    wait(20)
    var beta = H.find(s.screen, "runGroupTitles1")
    verify(beta, "beta's header has the caption")
    compare(beta.visible, true)
    compare(beta.text, "titles unavailable")
    compare(String(beta.color), String(s.screen.theme.dim), "dim")
    verify(String(beta.color) !== String(s.screen.theme.urgent), "never urgent")
    verify(H.find(s.screen, "runGroupCounts1").x < beta.x, "after the counts")
    compare(H.find(s.screen, "runGroupName1").text, "beta")
    compare(H.find(s.screen, "runGroupTitles0").visible, false, "alpha's titles are ok")
    compare(H.find(s.screen, "runRowId2").text, "…live0003", "beta's run keeps its id")
    s.titles.titleStatus = { "/home/u/b": "loading" }
    wait(20)
    compare(H.find(s.screen, "runGroupTitles1").visible, false, "loading")
    s.titles.titleStatus = { "/home/u/b": "unreachable" }
    s.runs.projectFilter = "/home/u/b"
    wait(20)
    compare(H.find(s.screen, "runGroup0"), null, "flat under a project filter")
    compare(H.find(s.screen, "runGroupTitles0"), null, "no caption under a project filter")
  }

  // Review Focus 2 and 4.
  function test_titles_unavailable_matches_the_root_by_its_key_and_ignores_garbage() {
    var s = make(twoProjects()); if (!s) return
    s.titles.titleStatus = { "/home/u/b/": "unreachable" }
    wait(20)
    compare(H.find(s.screen, "runGroupTitles1").visible, true, "a trailing / on the key")
    s.titles.titleStatus = { "/home/u/b//": "unreachable" }
    wait(20)
    compare(H.find(s.screen, "runGroupTitles1").visible, true, "several trailing /")
    var none = [{ "/home/u": "unreachable" }, {}, null, "x", 5, [], { "/home/u/b": 1 },
                { "/home/u/b": "Unreachable" }, { "/home/u/b": "ok" }]
    for (var i = 0; i < none.length; i++) {
      s.titles.titleStatus = none[i]
      wait(20)
      compare(H.find(s.screen, "runGroupTitles1").visible, false, "no caption for status " + i)
      compare(H.find(s.screen, "runGroupTitles0").visible, false, "nor on alpha for status " + i)
    }
  }

  // Review Focus 5.
  function test_an_error_only_header_also_says_titles_unavailable() {
    var s = make([tagged(run("run-a-live0001", "started", true, {}), "/home/u/a", "alpha")]); if (!s) return
    s.runs.projectRoots = [{ root: "/home/u/a", name: "alpha" }, { root: "/home/u/b", name: "beta" }]
    s.runs.projectErrors = { "/home/u/b": "AmFailed: boom" }
    s.titles.titleStatus = { "/home/u/b": "unreachable" }
    wait(20)
    compare(H.find(s.screen, "runGroupName1").text, "beta")
    compare(H.find(s.screen, "runGroupTitles1").visible, true)
    compare(H.find(s.screen, "runGroupError1").text, "AmFailed: boom", "the error still shows")
    compare(H.find(s.screen, "runGroupTitles0").visible, false)
  }

  // Review Focus 5.
  function test_a_long_project_name_leaves_room_for_the_caption() {
    var name = ""
    for (var i = 0; i < 30; i++) name += "longname"
    var s = make([tagged(run("run-b-live0003", "started", true, { milestone: "zeta" }), "/home/u/b", name)]); if (!s) return
    s.titles.titleStatus = { "/home/u/b": "unreachable" }
    wait(20)
    var nameText = H.find(s.screen, "runGroupName0")
    var caption = H.find(s.screen, "runGroupTitles0")
    compare(caption.visible, true)
    verify(nameText.width < nameText.implicitWidth, "the name elides")
    var right = caption.mapToItem(s.screen, 0, 0).x + caption.width
    verify(right <= s.screen.width, "the caption stays on the header: right edge " + right)
  }

  // Review Focus 3. The headers are rebuilt; the cursor and its run are not.
  function test_a_title_status_change_keeps_the_cursor_on_its_run() {
    var s = make(twoProjects()); if (!s) return
    s.nav.cursorIndex = 2
    wait(20)
    s.titles.titleStatus = { "/home/u/b": "unreachable" }
    wait(20)
    compare(s.nav.cursorIndex, 2)
    compare(s.runs.filteredRuns[2].id, "run-b-live0003")
    compare(H.find(s.screen, "runRow2").hasCursor, true)
    s.titles.titleStatus = {}
    wait(20)
    compare(s.nav.cursorIndex, 2)
    compare(H.find(s.screen, "runRow2").hasCursor, true)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the quick command on `tests/ui/screens/tst_runs_screen.qml` with each new function name.
Expected: the first four FAIL (`beta's header has the caption` / `TypeError: Cannot read property 'visible' of null`, since no `runGroupTitles*` item exists). `test_a_title_status_change_keeps_the_cursor_on_its_run` may already PASS: it pins behaviour the change must keep.

- [ ] **Step 3: Feed `titleStatus` into the entries and add the lookup**

In `ui/screens/RunsScreen.qml` replace

```qml
  readonly property var entries: screen.entriesOf(screen.app.runs.groups, screen.app.runs.filteredRuns,
    screen.app.runs.projectRoots, screen.app.runs.projectErrors, screen.app.runs.projectFilter)
```

with

```qml
  readonly property var entries: screen.entriesOf(screen.app.runs.groups, screen.app.runs.filteredRuns,
    screen.app.runs.projectRoots, screen.app.runs.projectErrors, screen.app.runs.projectFilter,
    screen.app.runTitles.titleStatus)
```

Insert directly after the `projectError` function (after its closing `  }`):

```qml

  // Whether `status` ({root: "loading" | "ok" | "unreachable"}) holds
  // "unreachable" for `root`, keys and root compared by rootKey; false when
  // `root` is "" or `status` is not an object.
  function titlesUnavailableOf(status, root) {
    var want = screen.rootKey(root)
    if (want === "" || status === null || typeof status !== "object") return false
    var keys = Object.keys(status)
    for (var k = 0; k < keys.length; k++) {
      if (screen.rootKey(keys[k]) === want && status[keys[k]] === "unreachable") return true
    }
    return false
  }
```

Replace the `entriesOf` comment and function (from `  // The list's entries, scalar values only` through the function's closing `  }`):

```qml
  // The list's entries, scalar values only (a Repeater converts nested ones):
  // { kind: "header", g, name, counts, error }, { kind: "run", i } with i the
  // run's index in `runs` (filteredRuns, which is displayOrder of `groups`),
  // and { kind: "projectError", text }.
  // Under a project filter: the filtered project's error when it has one,
  // then every run, flat. Otherwise each group of `groups` in turn: a header
  // unless its root is "", then its runs; then, for each root of the registry
  // `roots` (in order, once) with an error and no group, a header with no
  // counts and no runs. g counts the headers from 0; name is the project's
  // name, else its root; error is projectError's.
  function entriesOf(groups, runs, roots, errors, filter) {
```

with

```qml
  // The list's entries, scalar values only (a Repeater converts nested ones):
  // { kind: "header", g, name, counts, error, titlesUnavailable },
  // { kind: "run", i } with i the run's index in `runs` (filteredRuns, which
  // is displayOrder of `groups`), and { kind: "projectError", text }.
  // Under a project filter: the filtered project's error when it has one,
  // then every run, flat. Otherwise each group of `groups` in turn: a header
  // unless its root is "", then its runs; then, for each root of the registry
  // `roots` (in order, once) with an error and no group, a header with no
  // counts and no runs. g counts the headers from 0; name is the project's
  // name, else its root; error is projectError's; titlesUnavailable is
  // titlesUnavailableOf `status` ({root: title status}) for its root.
  function entriesOf(groups, runs, roots, errors, filter, status) {
```

and, inside it, replace

```js
        out.push({ kind: "header", g: g++, name: group.project.name !== "" ? group.project.name : root,
                   counts: screen.countsText(group.counts), error: screen.projectError(errors, root) })
```

with

```js
        out.push({ kind: "header", g: g++, name: group.project.name !== "" ? group.project.name : root,
                   counts: screen.countsText(group.counts), error: screen.projectError(errors, root),
                   titlesUnavailable: screen.titlesUnavailableOf(status, root) })
```

and replace

```js
      out.push({ kind: "header", g: g++, name: typeof project.name === "string" && project.name !== "" ? project.name : key,
                 counts: "", error: error })
```

with

```js
      out.push({ kind: "header", g: g++, name: typeof project.name === "string" && project.name !== "" ? project.name : key,
                 counts: "", error: error, titlesUnavailable: screen.titlesUnavailableOf(status, key) })
```

- [ ] **Step 4: Draw the caption in the header**

In `RunEntry`'s `headerC`, replace

```qml
        error: typeof entry.fact.error === "string" ? entry.fact.error : ""
      }
```

with

```qml
        error: typeof entry.fact.error === "string" ? entry.fact.error : ""
        titlesUnavailable: entry.fact.titlesUnavailable === true
      }
```

Replace the `RunGroupHeader` comment and its start through the end of its name `Row` (from `  // A project's header: its name, its counts and, when its snapshot failed,` through the `groupCounts` text's closing `    }` that ends the `Row`):

```qml
  // A project's header: its name, its counts and, when its snapshot failed,
  // the error. Not a row: no cursor, no hover, no click.
  component RunGroupHeader: Column {
    id: header
    property int g: 0
    property string name: ""
    property string counts: ""
    property string error: ""
    readonly property real innerWidth: Math.max(0, header.width - header.leftPadding - header.rightPadding)

    objectName: "runGroup" + header.g
    width: screen.width
    leftPadding: Style.space(10)
    rightPadding: Style.space(10)
    topPadding: Style.space(4)
    spacing: Style.space(2)

    Row {
      width: header.innerWidth
      spacing: Style.space(8)

      UI.ThemedText {
        objectName: "runGroupName" + header.g
        theme: screen.theme
        font.bold: true
        width: Math.max(0, Math.min(implicitWidth,
          parent.width - (groupCounts.visible ? groupCounts.width + parent.spacing : 0)))
        text: header.name
        elide: Text.ElideRight
      }

      UI.ThemedText {
        id: groupCounts
        objectName: "runGroupCounts" + header.g
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: header.counts
      }
    }
```

with

```qml
  // A project's header: its name, its counts, a dim `titles unavailable` while
  // its titles cannot be read and, when its snapshot failed, the error. Not a
  // row: no cursor, no hover, no click.
  component RunGroupHeader: Column {
    id: header
    property int g: 0
    property string name: ""
    property string counts: ""
    property string error: ""
    property bool titlesUnavailable: false
    readonly property real innerWidth: Math.max(0, header.width - header.leftPadding - header.rightPadding)

    objectName: "runGroup" + header.g
    width: screen.width
    leftPadding: Style.space(10)
    rightPadding: Style.space(10)
    topPadding: Style.space(4)
    spacing: Style.space(2)

    Row {
      width: header.innerWidth
      spacing: Style.space(8)

      UI.ThemedText {
        objectName: "runGroupName" + header.g
        theme: screen.theme
        font.bold: true
        width: Math.max(0, Math.min(implicitWidth,
          parent.width - (groupCounts.visible ? groupCounts.width + parent.spacing : 0)
            - (groupTitles.visible ? groupTitles.width + parent.spacing : 0)))
        text: header.name
        elide: Text.ElideRight
      }

      UI.ThemedText {
        id: groupCounts
        objectName: "runGroupCounts" + header.g
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: header.counts
      }

      UI.ThemedText {
        id: groupTitles
        objectName: "runGroupTitles" + header.g
        variant: "caption"
        theme: screen.theme
        visible: header.titlesUnavailable
        text: "titles unavailable"
        color: screen.theme.dim
      }
    }
```

In the file's header comment replace

```
// project's snapshot error), flat with no header under a project filter. Each
```

with

```
// project's snapshot error; a dim `titles unavailable` while its titles
// cannot be read), flat with no header under a project filter. Each
```

- [ ] **Step 5: Run the tests to verify they pass**

Run the quick command on `tests/ui/screens/tst_runs_screen.qml` (whole file).
Expected: `Totals: N passed, 0 failed`, no `TypeError`/`ReferenceError` lines; the existing header tests (`test_each_project_gets_a_header_with_its_name_and_counts`, `test_a_failed_project_with_nothing_listed_still_shows_its_error`, `test_hovering_a_header_moves_no_cursor_...`) still PASS.

- [ ] **Step 6: Update the docs**

In `docs/architecture.md:168` replace

```
; and its `projectErrors` sentence, a failed root with no runs getting a header of its own)
```

with

```
; its `projectErrors` sentence, a failed root with no runs getting a header of its own; and, after the counts, a dim `titles unavailable` while `app.runTitles.titleStatus` holds `unreachable` for its root, roots compared without trailing `/`)
```

In `README.md:154` replace

```
shows why under its header and keeps the runs it had; the other projects are unaffected.
```

with

```
shows why under its header and keeps the runs it had; the other projects are unaffected. A project whose board cannot be read for titles says `titles unavailable`, dimmed, in its header, and its runs keep their ids.
```

- [ ] **Step 7: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml docs/architecture.md README.md
git commit -m "feat(runs): an unreachable project's Runs header says titles unavailable, dimmed"
```

---

### Task 4: **Refresh titles** beside Notify on escalation

**Files:**
- Modify: `ui/screens/RunsScreen.qml` — header comment, `runsNotifyRow` `:313-333`
- Modify: `docs/architecture.md:168`, `README.md:154`
- Test: `tests/ui/screens/tst_runs_screen.qml`

**Interfaces:**
- Consumes: `s.titles.refreshCalls` / `refreshTitles()` (Task 2's stub); `screen.amMissing` (existing); `UI.ActionButton` (`ui/components/ActionButton.qml`: `theme`, `text`, `clicked()`).
- Produces: object name `runsRefreshTitles`.

- [ ] **Step 1: Write the failing test**

In `tests/ui/screens/tst_runs_screen.qml`, insert directly after `test_the_footer_says_whether_the_runs_are_watched` (ends with `compare(footer.visible, true)\n  }`):

```qml

  function test_refresh_titles_calls_the_store() {
    var s = make(sample()); if (!s) return
    var button = H.find(s.screen, "runsRefreshTitles")
    verify(button, "the Refresh titles button")
    compare(button.visible, true)
    compare(button.text, "Refresh titles")
    tap(button)
    compare(s.titles.refreshCalls, 1)
    compare(s.navi.opened, "", "it opens no run")
    compare(s.nav.viewMode, "runs")
    compare(s.control.notifyCalls.length, 0, "it is not the notify switch")
    tap(button)
    compare(s.titles.refreshCalls, 2, "once per click")
    s.runs.amStatus = "missing"
    wait(20)
    compare(H.find(s.screen, "runsRefreshTitles").visible, false, "hidden while am is missing")
    compare(H.find(s.screen, "runsNotifyRow").visible, true, "the notify switch still shows")
  }
```

- [ ] **Step 2: Run the test to verify it fails**

Run the quick command on `tests/ui/screens/tst_runs_screen.qml` with `RunsScreen::test_refresh_titles_calls_the_store`.
Expected: FAIL with `the Refresh titles button` (no such item).

- [ ] **Step 3: Add the button**

In `ui/screens/RunsScreen.qml` replace

```qml
  // The global Notify on escalation setting: a desktop notification for
  // every run toast. Shown with or without a project, and while am is missing.
  Row {
```

with

```qml
  // The global Notify on escalation setting: a desktop notification for
  // every run toast. Shown with or without a project, and while am is missing.
  // Beside it, while am is present, Refresh titles asks the run titles to
  // read every project's titles again.
  Row {
```

and replace

```qml
      text: "Notify on escalation"
    }
  }
```

with

```qml
      text: "Notify on escalation"
    }

    UI.ActionButton {
      objectName: "runsRefreshTitles"
      anchors.verticalCenter: parent.verticalCenter
      theme: screen.theme
      visible: !screen.amMissing
      text: "Refresh titles"
      onClicked: screen.app.runTitles.refreshTitles()
    }
  }
```

In the file's header comment replace

```
// navigator to open a run, choose a project or move the cursor; it owns no
// state of its own.
```

with

```
// navigator to open a run, choose a project or move the cursor, and the run
// titles to read every project's titles again; it owns no state of its own.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the quick command on `tests/ui/screens/tst_runs_screen.qml` (whole file).
Expected: `Totals: N passed, 0 failed`; `test_missing_am_is_one_message_with_no_chips_or_rows` and `test_the_screen_is_hidden_outside_its_section` still PASS.

- [ ] **Step 5: Update the docs**

In `docs/architecture.md:168` replace

```
and with it on every run toast also raises a desktop notification. `ui/screens/RunDetailScreen.qml`
```

with

```
and with it on every run toast also raises a desktop notification. Beside it a `Refresh titles` button (`runsRefreshTitles`), hidden while am is missing, calls `app.runTitles.refreshTitles()` and nothing else. `ui/screens/RunDetailScreen.qml`
```

In `README.md:154` replace

```
**Notify on escalation**, under the Runs list, is one switch for the whole viewer: with it on, each such toast also raises a desktop notification.
```

with

```
**Notify on escalation**, under the Runs list, is one switch for the whole viewer: with it on, each such toast also raises a desktop notification. **Refresh titles**, beside it, reads every project's run titles again.
```

- [ ] **Step 6: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml docs/architecture.md README.md
git commit -m "feat(runs): Refresh titles beside Notify on escalation asks for every project's titles again"
```

---

### Task 5: A card's RUNS rows read badge, title, then the short id in dim

**Files:**
- Modify: `ui/screens/CardDetailScreen.qml:220-225` (`CardRunRow` comment), `:240-263` (its first `Row`)
- Modify: `docs/architecture.md:168`, `README.md:142`
- Test: `tests/ui/screens/tst_card_detail_screen.qml`

**Interfaces:**
- Consumes: `Runs.titlesOfRun` (Task 1); `app.runTitles.titlesByRoot` and `app.runTitles.titlesRunner` (real `RunTitlesStore`); the test file's `make()`, `withRuns(s)` (`:274`).
- Produces: `cardRunTitle<i>` before `cardRunId<i>` in each RUNS row.

- [ ] **Step 1: Write the failing test**

In `tests/ui/screens/tst_card_detail_screen.qml` replace

```qml
import "../../helpers/find.js" as H
```

with

```qml
import "../../helpers/find.js" as H
import "../../../core/domain/runs.js" as Runs
```

Insert directly after `test_the_runs_section_lists_the_runs_that_touch_the_card` (ends with `compare(first.index, -1, "a RUNS row is not in the keyboard's link list")\n  }`):

```qml

  // withRuns()' runs, tagged with a project that is not the open one.
  function test_a_runs_row_reads_its_projects_title_then_its_short_id() {
    var s = make(); if (!s) return
    withRuns(s)
    s.app.runs.runs = s.app.runs.runs.map(function(r) { return Runs.withProject(r, "/home/u/b", "beta") })
    s.app.runTitles.titlesRunner.cancel()
    s.app.runTitles.titlesByRoot = { "/home/u/b": { m1: "Shipped M1" } }
    s.navigator.openCard("s1")
    wait(50)
    var title = H.find(s, "cardRunTitle0")
    var id = H.find(s, "cardRunId0")
    compare(title.text, "Shipped M1")
    compare(id.text, "…000000a1")
    compare(String(id.color), String(s.theme.dim), "the short id is dim")
    verify(title.x < id.x, "the short id follows the title")
    compare(H.find(s, "cardRunTitle1").text, "Shipped M1", "the done run of m1 too")
    compare(H.find(s, "cardRunPhase0").text, "implement", "the phase is unchanged")
    s.app.runTitles.titlesByRoot = { "/home/u/a": { m1: "Wrong project" } }
    compare(H.find(s, "cardRunTitle0").text, "milestone …m1", "another project's map is not the run's")
  }
```

- [ ] **Step 2: Run the test to verify it fails**

Run the quick command on `tests/ui/screens/tst_card_detail_screen.qml` with `CardDetailScreen::test_a_runs_row_reads_its_projects_title_then_its_short_id`.
Expected: FAIL — `Actual (): milestone …m1` / `Expected (): Shipped M1`.

- [ ] **Step 3: Reorder the row and title it**

In `ui/screens/CardDetailScreen.qml` replace

```qml
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
```

with

```qml
      UI.ThemedText {
        objectName: "cardRunTitle" + runRow.modelData
        variant: "small"
        theme: detailCard.theme
        text: Runs.runTitle(runRow.run, Runs.titlesOfRun(runRow.run, detailCard.app.runTitles.titlesByRoot))
      }

      UI.ThemedText {
        objectName: "cardRunId" + runRow.modelData
        variant: "caption"
        theme: detailCard.theme
        text: Runs.runSubtitle(runRow.run)
        color: detailCard.theme.dim
      }
```

Replace the `CardRunRow` comment line

```
  // One run that touches the card: its state glyph, short id, title, current
  // phase and age, and its RunControls under them. Mouse-activated only
```

with

```
  // One run that touches the card: its state glyph; its title, from the run's
  // own project's map in app.runTitles; its short id in dim; current phase and
  // age; and its RunControls under them. Mouse-activated only
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the quick command on `tests/ui/screens/tst_card_detail_screen.qml` (whole file).
Expected: `Totals: N passed, 0 failed`; `test_the_runs_section_lists_the_runs_that_touch_the_card` (untagged runs: `…000000a1`, `milestone …m1`) still PASSES. Then run the quick command on `tests/ui/tst_runs_real_data.qml` (whole file): still `0 failed` (its `runRowId0` vs `cardRunId0` check compares two `Runs.runSubtitle` texts).

- [ ] **Step 5: Update the docs**

In `docs/architecture.md:168` replace

```
(`BoardScreen` and `GraphScreen` only `app.runs`; `RunsScreen` also `app.runTitles`)
```

with

```
(`BoardScreen` and `GraphScreen` only `app.runs`; `RunsScreen` and `CardDetailScreen` also `app.runTitles`)
```

and replace

```
every run `runsTouching` the card, newest first, with glyph, short id, title, phase and age, dimmed while stale.
```

with

```
every run `runsTouching` the card, newest first, with glyph, title (`runTitle` with `titlesOfRun(run, app.runTitles.titlesByRoot)`), the short id in `dim`, phase and age, dimmed while stale.
```

In `README.md:142` replace

```
(newest first: state glyph, short id, title, phase, age)
```

with

```
(newest first: state glyph, title from the run's own project's board, short id dimmed after it, phase, age)
```

- [ ] **Step 6: Commit**

```bash
git add ui/screens/CardDetailScreen.qml tests/ui/screens/tst_card_detail_screen.qml docs/architecture.md README.md
git commit -m "feat(runs): a card's RUNS row reads its run's title, then its short id in dim"
```

---

### Task 6: The cancel dialog's detail is the run's title; full gate

**Files:**
- Modify: `ui/Panel.qml:831-849` (`runCancelModal`)
- Modify: `docs/architecture.md:168`
- Test: `tests/ui/tst_runs_flow.qml`

**Interfaces:**
- Consumes: `Runs.titlesOfRun` (Task 1); `appStores.runs.runById(id)`, `appStores.runControl.cancelRunId`, `appStores.runTitles.titlesByRoot` (existing); in the test, `make()`, `makeTwo()` (`:891`), `cancelModal(p)` (`:379`), `p.app.runControl.openCancel(id)` / `closeCancel()`, `p.app.board.applyTreeData(roots)`, `Runs.copyMap`.
- Produces: `runCancelModal.cancelRun` (the listed run or `null`); `runCancelModal.detail` is its title.

- [ ] **Step 1: Write the failing tests**

In `tests/ui/tst_runs_flow.qml`, insert directly after `test_cancel_asks_for_the_typed_word_then_cancels_and_gives_the_focus_back` (the test that has `compare(modal.detail, "milestone …alpha")`; insert after its closing `  }`):

```qml

  // make(): the open project is /home/u/a, whose map mirrors its board.
  function test_the_cancel_dialog_detail_is_the_runs_title() {
    var p = make(); if (!p) return
    p.app.board.applyTreeData([{ id: "alpha", title: "Alpha work", status: "todo", description: "",
                                 blocked_by: [], children: [] }])
    compare(p.app.runTitles.titlesByRoot["/home/u/a"].alpha, "Alpha work", "the open project's map")
    compare(p.app.runControl.openCancel("run-0000000000a1"), true)
    wait(50)
    var modal = cancelModal(p)
    compare(modal.visible, true)
    compare(modal.detail, "Alpha work")
    compare(modal.message, "Cancel run …000000a1? Cancel is final. The run cannot be resumed, only relaunched; cards keep their current status. A phase in flight finishes first.")
    p.app.runControl.closeCancel()
  }

  // makeTwo(): run-0000000000f6 is beta's (/home/u/b), milestone zeta.
  function test_the_cancel_dialog_detail_of_another_projects_run_reads_its_own_map() {
    var p = makeTwo(); if (!p) return
    p.app.runTitles.titlesRunner.cancel()
    var maps = Runs.copyMap(p.app.runTitles.titlesByRoot)
    maps["/home/u/a"] = { zeta: "Alpha zeta" }
    maps["/home/u/b"] = { zeta: "Beta zeta" }
    p.app.runTitles.titlesByRoot = maps
    compare(p.app.runControl.openCancel("run-0000000000f6"), true)
    wait(50)
    compare(cancelModal(p).detail, "Beta zeta")
    p.app.runControl.closeCancel()
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the quick command on `tests/ui/tst_runs_flow.qml` with `RunsFlow::test_the_cancel_dialog_detail_is_the_runs_title` and `RunsFlow::test_the_cancel_dialog_detail_of_another_projects_run_reads_its_own_map`.
Expected: both FAIL — `Actual (): milestone …alpha` / `Expected (): Alpha work`, and `milestone …zeta` / `Beta zeta`.

- [ ] **Step 3: Title the detail from the run's project map**

In `ui/Panel.qml` replace

```qml
        id: runCancelModal
        objectName: "runCancelModal"
```

with

```qml
        id: runCancelModal
        objectName: "runCancelModal"
        // The run the dialog asks about; null when it is not listed.
        readonly property var cancelRun: appStores.runs.runById(appStores.runControl.cancelRunId)
```

and replace

```qml
        detail: appStores.runs.runById(appStores.runControl.cancelRunId) ? Runs.runTitle(appStores.runs.runById(appStores.runControl.cancelRunId)) : ""
```

with

```qml
        detail: runCancelModal.cancelRun
          ? Runs.runTitle(runCancelModal.cancelRun, Runs.titlesOfRun(runCancelModal.cancelRun, appStores.runTitles.titlesByRoot))
          : ""
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the quick command on `tests/ui/tst_runs_flow.qml` (whole file).
Expected: `Totals: N passed, 0 failed`; `test_cancel_asks_for_the_typed_word_then_cancels_and_gives_the_focus_back` (no board card `alpha`, so `milestone …alpha`) still PASSES. `width' of null` QWARN lines at teardown are known and ignored.

- [ ] **Step 5: Update the docs**

In `docs/architecture.md:168` replace

```
and reads `Keep running` / `Cancel run`;
```

with

```
and reads `Keep running` / `Cancel run`, its detail line the run's title (`runTitle` with `titlesOfRun(run, app.runTitles.titlesByRoot)`);
```

- [ ] **Step 6: Run the whole gate**

Run: `bash tests/run.sh`
Expected: pytest all passed (including `tests/architecture`), then every QML file prints `Totals: N passed, 0 failed`, no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `anchors on an item` / `is not a function` line, exit status 0 (`echo $?` prints `0`). Also `grep -rn "_titlesFor" core ui` prints nothing.

- [ ] **Step 7: Commit**

```bash
git add ui/Panel.qml tests/ui/tst_runs_flow.qml docs/architecture.md
git commit -m "feat(runs): the cancel dialog's detail is the run's title from its own project's map"
```
<!-- task-pipeline: validated -->
