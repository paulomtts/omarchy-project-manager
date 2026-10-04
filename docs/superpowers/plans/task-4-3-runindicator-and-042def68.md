<!-- task-pipeline: validated -->
# 4.3 RunIndicator and sidebar attention count (card 042def68)

Parent story fa4592b2 "Run components". This card narrows the milestone design `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` ("On existing screens" and "Needs attention") to two presentational pieces. Base: this worktree builds on task-4-2 (4dc37e6), which already has `runGlyphs.js`, `RunBadge`, `RunRollupBar`, `Pulse` and `PhaseTimeline`.

## Scope

In scope:
- New `ui/components/RunIndicator.qml`, a toolbar strip that will later sit beside `MilestoneJobIndicator` (Panel.qml toolbar). It is presentation only.
- `ui/components/Sidebar.qml`: one new prop, `property int runsAttention: 0`, and the rendering of its count. The count renders through a derived string and an optional count slot on `NavRow`.
- The `docs/architecture.md` "Shared components" list gains a `RunIndicator` entry. The `Sidebar` sentence gains a note on `runsAttention`.
- UI tests, written first.

Out of scope: the Runs NavRow, Ctrl+6, Navigator registration, RunsScreen and RunDetailScreen (story 5.x). Also out of scope: wiring `RunIndicator` or `runsAttention` from `RunStore` into `Panel.qml` (a later integration card), RunBadge on cards, CardDetail's Runs section, run controls and dispatch. Nothing in this card imports `core/stores` or `core/domain/runs.js`.

## RunIndicator behaviour

Conventions follow `MilestoneJobIndicator`. The root is an `Item` with `objectName: "runIndicator"`, `import qs.Commons`, `property var theme: T.Theme {}`, spacing via `Style.space(n)`, and a leading comment that says "Presentation only".

Props are plain numbers from the owner: `running`, `parked` and `attention`. The owner computes `attention` as escalated plus dead, per `runs.attention()`, but the component does not know that. A negative or non-finite value counts as 0. Reuse the clamping rule of `runGlyphs.countOf` rather than writing a second one: import `"runGlyphs.js" as RunGlyphs` (as `RunRollupBar` does) and read each prop as `RunGlyphs.countOf({ n: value }, "n")`. Props are declared `property var` (not `int`) so NaN, undefined and strings reach that rule; a numeric string therefore counts as 0, like `countOf` says.

Rendering:
- There is one segment per non-zero count, in the order running, parked, attention. Each segment's text is the glyph immediately followed by the count, for example `⟳2 ⏸1 ‼1`.
- Glyphs come only from `runGlyphs.glyphOf`: `glyphOf("running")`, `glyphOf("parked")`, and `glyphOf("escalated")` for attention. No glyph literals are declared in RunIndicator. The design doc's illustrative `▶` resolves to the shared running glyph `⟳`, so a state reads the same everywhere.
- Segments are `ActionButton`s. The attention segment uses `tone: "danger"`, which is `theme.urgent`. The others use the normal tone. Every state carries its glyph, so colour is never the only signal. Do not use `#9b72cf`, `#d9534f` or `Board.statusColor`.
- The root is `visible` only while `running + parked + attention > 0`. A project with no runs, or with only finished runs, shows nothing. A zero-count segment is hidden.
- The indicator is static. It has no animation and does not use `Pulse`.
- It does not use the banned duplicated literals (`Qt.rgba(0, 0, 0, 0.55)`, `radius: height / 2`, `bordered: true`, `font.family:`, `CursorSurface {`).

Signal: `signal filterRequested(string filter)`. The filter vocabulary is the Runs screen chip set: `"attention"` (Needs attention), `"live"`, `"parked"` and `"all"`.
- Clicking the running segment emits `"live"`.
- Clicking the parked segment emits `"parked"`.
- Clicking the attention segment emits `"attention"`.
- `"all"` is part of the documented vocabulary for the future Runs screen, but no segment emits it.

Segment objectNames: `runIndicatorRunning`, `runIndicatorParked`, `runIndicatorAttention`.

## Sidebar attention count

- Add `property int runsAttention: 0`.
- Add `import "runGlyphs.js" as RunGlyphs` to `Sidebar.qml` (it lives in `ui/components`, next to it). Add `readonly property string runsAttentionText`. It is `RunGlyphs.glyphOf("escalated") + runsAttention` (for example `‼3`) when `runsAttention > 0`, and `""` otherwise. A negative value gives `""`.
- `NavRow` gains `property string countText: ""`. After the label, it shows a `ThemedText` with objectName `"navCount" + Section`, visible only when `countText !== ""` and coloured `theme.urgent`. None of the five existing rows sets it, so they render exactly as before.
- Card 5.1 adds the Runs row and binds it with `countText: sidebar.runsAttentionText`. This card adds no row and no shortcut.

## Error paths

- Counts that are 0, negative, NaN or undefined render nothing for that segment. If all counts are like that, the root is hidden.
- When no theme is passed, the default `T.Theme {}` is used.
- `tests/run.sh` must log no TypeError, ReferenceError, non-existent or "Unable to assign" errors.

## Tests (TDD: write these first)

Per the test-placement rule (tests mirror the source layer; `ui/components/X.qml` maps to `tests/ui/components/tst_x.qml`; Sidebar tests live flat in `tests/ui/tst_sidebar.qml`).

`tests/ui/components/tst_run_indicator.qml` (UI component tier; `import "../../helpers/find.js" as H`, `import "../../../ui/components" as UI`):
1. With all counts 0, the root is not visible.
2. With negative or garbage counts, the root is not visible.
3. With `running: 2, parked: 1, attention: 1`, it is visible. The segment texts are `glyphOf("running")+"2"`, `glyphOf("parked")+"1"` and `glyphOf("escalated")+"1"`, in that order (compare the segments' mapped x positions, since Row order is the visual order).
4. With only `parked: 1`, only the parked segment is visible.
5. Clicking the running, parked and attention segments emits `filterRequested` with `"live"`, `"parked"` and `"attention"` respectively (SignalSpy).
6. The attention segment's `foreground` (the `ActionButton` colour property) equals `theme.urgent`. The running and parked segments' `foreground` equals `theme.foreground`. Use a test theme where the two differ.
7. A standalone instance with no theme passed renders without errors.

`tests/ui/tst_sidebar.qml` (flat UI tier, where Sidebar tests already live):
8. `runsAttention` defaults to 0 and `runsAttentionText` is `""`.
9. Setting `runsAttention: 3` gives `runsAttentionText === glyphOf("escalated") + "3"`. Setting it back to 0 gives `""`.
10. No existing nav row (`navBoard` … `navIssues`) shows a visible `navCount*` text, so existing rows are unchanged.

Architecture tier (`tests/architecture/`), which must pass unchanged:
- `test_layers.py`: RunIndicator imports no store.
- The duplicate-literal check.
- `test_icon_glyphs.py`: the new code adds no private-use glyphs.

---

# RunIndicator and Sidebar Attention Count Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a presentation-only `RunIndicator` toolbar strip (`⟳2 ⏸1 ‼1`, click emits a Runs filter) and a `runsAttention` prop plus a `NavRow` count slot on `Sidebar`, both test-first.

**Architecture:** `RunIndicator.qml` is a prop-driven `Item` holding a `Row` of three `ActionButton` segments; every count is clamped through the existing `runGlyphs.countOf` and every glyph comes from `runGlyphs.glyphOf`, so there is no second glyph map and no second clamping rule. `Sidebar.qml` gains a derived `runsAttentionText` string and an optional `countText` slot on its inline `NavRow` component; no row sets it in this card, so existing rows are unchanged. Neither file imports `core/stores` or `core/domain`.

**Tech Stack:** QML (Qt 6, QtQuick), Quickshell `qs.Commons` / `qs.Ui`, `.pragma library` JS, QtTest via `qmltestrunner` (offscreen), pytest architecture checks, all driven by `tests/run.sh`.

**Spec:** `docs/superpowers/specs/task-4-3-runindicator-and-042def68-design.md` (prepended verbatim above).

**Working directory for every command:** `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-4-3-runindicator-and-042def68` (branch `mon/task-4-3-runindicator-and-042def68`, cut from `mon/task-4-2-phasetimeline-9d62f0f4`). The only prior-card code this plan relies on is what that base already contains: `ui/components/runGlyphs.js` (`glyphOf`, `countOf`), `ui/components/ActionButton.qml`, `ui/components/ThemedText.qml`, `ui/theme/Theme.qml`, `tests/helpers/find.js`.

**Note on inputs:** the orchestrator's spec summary for this card was truncated at 2000 characters (cut off mid-sentence at "T"), which suggests that upstream stage over-ran its brief. This plan was written from the full spec on disk, not from that summary.

## Global Constraints

- `ui/components` must not import `core/stores` (enforced by `tests/architecture/test_layers.py::test_layers_import_only_what_their_allowlist_permits`); this card imports neither `core/stores` nor `core/domain/runs.js`.
- No banned duplicated literals in new/changed code outside their allowlisted files: `Qt.rgba(0, 0, 0, 0.55)`, `radius: height / 2`, `bordered: true`, `font.family:`, `CursorSurface {` (Sidebar.qml's existing three `CursorSurface {` uses are already allowlisted; add no new one).
- Never use `#9b72cf`, `#d9534f` or `Board.statusColor` for run state; attention uses `theme.urgent` via `tone: "danger"`.
- No glyph literals in `RunIndicator.qml` or the Sidebar change: use `RunGlyphs.glyphOf("running" | "parked" | "escalated")` only. No Nerd Font private-use code points.
- No animation and no `Pulse` in `RunIndicator`.
- Segment text is glyph immediately followed by count, no space: `⟳2`, `⏸1`, `‼1`.
- Filter vocabulary: `"attention"`, `"live"`, `"parked"`, `"all"`; segments emit `"live"`, `"parked"`, `"attention"`; nothing emits `"all"`.
- objectNames: root `runIndicator`; segments `runIndicatorRunning`, `runIndicatorParked`, `runIndicatorAttention`; sidebar count `navCount<Section>` (e.g. `navCountBoard`).
- No Runs NavRow, no Ctrl+6, no Navigator registration, no Panel.qml wiring.
- `bash ./tests/run.sh` must pass and log no `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`.
- `docs/architecture.md` is updated in the same change as the new shared component.

## Review Focus

- Counts updated live by the owner (non-zero to all zero, then back) must hide and re-show the indicator without re-creating it; pinned by `test_live_count_changes_hide_and_show_it` in Task 1.
- A zero middle count (running and attention set, parked 0) must skip the parked segment and keep running before attention; pinned by `test_a_zero_middle_count_is_skipped_and_order_holds` in Task 1.
- An owner tearing down or explicitly passing `theme: null` must not raise TypeErrors; `ActionButton` falls back to its own Theme and attention still reads urgent; pinned by `test_a_null_theme_falls_back_without_errors` in Task 1.
- A negative `runsAttention` (stale or miscomputed by the owner) must render `""`, not `‼-2`; pinned by `test_runs_attention_text_follows_the_count` in Task 2.
- The `countText` slot must actually render after the label in `urgent` when a row is given a count (card 5.1 depends on it), not only stay hidden; pinned by `test_a_row_given_a_count_shows_it_after_its_label_in_urgent` in Task 2.

---

### Task 1: RunIndicator component

**Files:**
- Create: `tests/ui/components/tst_run_indicator.qml`
- Create: `ui/components/RunIndicator.qml`
- Modify: `docs/architecture.md:112-113` (Shared components list, after the `PhaseTimeline` entry)

**Interfaces:**
- Consumes: `ui/components/runGlyphs.js` — `glyphOf(state: string): string`, `countOf(counts: object, key: string): number` (0 for non-finite, negative, non-number). `ui/components/ActionButton.qml` — props `theme: var` (null falls back to own Theme), `tone: string` (`"danger"` -> `palette.urgent`), `text`, readable `foreground: color`, signal `clicked()`.
- Produces: `UI.RunIndicator` with `property var running`, `property var parked`, `property var attention` (all default 0), `property var theme` (default `T.Theme {}`), `readonly property real runningCount`, `readonly property real parkedCount`, `readonly property real attentionCount`, `signal filterRequested(string filter)`; children objectNames `runIndicatorRunning`, `runIndicatorParked`, `runIndicatorAttention`. Later integration cards bind the three counts from RunStore and route `filterRequested` to the Runs screen.

- [ ] **Step 1: Write the failing test**

Create `tests/ui/components/tst_run_indicator.qml`:

```qml
// tests/ui/components/tst_run_indicator.qml
// ui/components/RunIndicator.qml: the toolbar's run strip. One ActionButton
// segment per non-zero count (running, parked, attention), each the shared
// runGlyphs glyph immediately followed by the count; attention reads in
// `urgent`; a click asks for the matching Runs filter; nothing at all when
// every count is 0 or garbage.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/components/runGlyphs.js" as RG
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "RunIndicator"
  when: windowShown
  visible: true
  width: 400; height: 200

  // foreground and urgent differ, so a tint can only match the one it is meant to.
  T.Theme { id: testTheme; foreground: "#eeeeee"; dim: "#777777"; urgent: "#ff3300" }

  Component { id: indicatorC; UI.RunIndicator {} }
  SignalSpy { id: filters; signalName: "filterRequested" }

  function make(props) {
    var ind = createTemporaryObject(indicatorC, tc, props || {})
    filters.target = ind
    filters.clear()
    wait(30)
    return ind
  }
  function seg(ind, name) { return H.find(ind, name) }
  function click(item) { mouseClick(item, item.width / 2, item.height / 2) }
  function xOf(ind, item) { return item.mapToItem(ind, 0, 0).x }

  function test_no_counts_hides_the_indicator() {
    var ind = make({})
    compare(ind.objectName, "runIndicator")
    compare(ind.visible, false, "the defaults are all 0")
    compare(make({ running: 0, parked: 0, attention: 0 }).visible, false)
  }

  function test_garbage_counts_hide_the_indicator() {
    compare(make({ running: -1, parked: NaN, attention: "3" }).visible, false,
      "negative, NaN and a numeric string are all 0")
    compare(make({ running: undefined, parked: null, attention: Infinity }).visible, false,
      "undefined, null and Infinity are all 0")
    compare(make({ running: true, parked: -Infinity, attention: -5 }).visible, false)
  }

  function test_segments_read_glyph_then_count_in_order() {
    var ind = make({ running: 2, parked: 1, attention: 1, theme: testTheme })
    compare(ind.visible, true)
    var running = seg(ind, "runIndicatorRunning")
    var parked = seg(ind, "runIndicatorParked")
    var attention = seg(ind, "runIndicatorAttention")
    verify(running && parked && attention, "three segments")
    compare(running.visible, true)
    compare(parked.visible, true)
    compare(attention.visible, true)
    compare(String(running.text), RG.glyphOf("running") + "2")
    compare(String(parked.text), RG.glyphOf("parked") + "1")
    compare(String(attention.text), RG.glyphOf("escalated") + "1")
    compare(String(running.text), "⟳2", "the shared running glyph, no space")
    verify(xOf(ind, running) < xOf(ind, parked) && xOf(ind, parked) < xOf(ind, attention),
      "running, parked, attention in that order")
  }

  function test_only_the_parked_segment_shows_for_parked_only() {
    var ind = make({ parked: 1, theme: testTheme })
    compare(ind.visible, true)
    compare(seg(ind, "runIndicatorParked").visible, true)
    compare(String(seg(ind, "runIndicatorParked").text), RG.glyphOf("parked") + "1")
    compare(seg(ind, "runIndicatorRunning").visible, false, "a zero count is not shown")
    compare(seg(ind, "runIndicatorAttention").visible, false)
  }

  function test_a_zero_middle_count_is_skipped_and_order_holds() {
    var ind = make({ running: 1, parked: 0, attention: 4, theme: testTheme })
    compare(seg(ind, "runIndicatorParked").visible, false)
    var running = seg(ind, "runIndicatorRunning")
    var attention = seg(ind, "runIndicatorAttention")
    compare(String(attention.text), RG.glyphOf("escalated") + "4")
    verify(xOf(ind, running) < xOf(ind, attention), "running still leads attention")
  }

  function test_clicks_ask_for_the_matching_runs_filter() {
    var ind = make({ running: 2, parked: 1, attention: 1, theme: testTheme })
    click(seg(ind, "runIndicatorRunning"))
    click(seg(ind, "runIndicatorParked"))
    click(seg(ind, "runIndicatorAttention"))
    compare(filters.count, 3)
    compare(filters.signalArguments[0][0], "live")
    compare(filters.signalArguments[1][0], "parked")
    compare(filters.signalArguments[2][0], "attention")
  }

  function test_attention_reads_urgent_and_the_rest_foreground() {
    var ind = make({ running: 1, parked: 1, attention: 1, theme: testTheme })
    verify(Qt.colorEqual(seg(ind, "runIndicatorAttention").foreground, testTheme.urgent), "attention is urgent")
    verify(Qt.colorEqual(seg(ind, "runIndicatorRunning").foreground, testTheme.foreground), "running is foreground")
    verify(Qt.colorEqual(seg(ind, "runIndicatorParked").foreground, testTheme.foreground), "parked is foreground")
    var names = ["runIndicatorRunning", "runIndicatorParked", "runIndicatorAttention"]
    for (var i = 0; i < names.length; i++) {
      var c = seg(ind, names[i]).foreground
      verify(!Qt.colorEqual(c, "#9b72cf") && !Qt.colorEqual(c, "#d9534f"), names[i])
    }
  }

  function test_a_standalone_instance_uses_its_default_theme() {
    var ind = make({ running: 1, attention: 2 })
    verify(ind.theme, "falls back to its own Theme")
    compare(ind.visible, true)
    verify(Qt.colorEqual(seg(ind, "runIndicatorAttention").foreground, ind.theme.urgent))
    verify(Qt.colorEqual(seg(ind, "runIndicatorRunning").foreground, ind.theme.foreground))
  }

  function test_live_count_changes_hide_and_show_it() {
    var ind = make({ running: 2, theme: testTheme })
    compare(ind.visible, true)
    ind.running = 0
    wait(30)
    compare(ind.visible, false, "the last run finished: nothing to show")
    ind.attention = 1
    wait(30)
    compare(ind.visible, true)
    compare(seg(ind, "runIndicatorAttention").visible, true)
    compare(seg(ind, "runIndicatorRunning").visible, false)
  }

  function test_a_null_theme_falls_back_without_errors() {
    var own = make({ attention: 1 })
    var ind = make({ running: 1, attention: 1, theme: null })
    compare(ind.visible, true)
    verify(Qt.colorEqual(seg(ind, "runIndicatorAttention").foreground, own.theme.urgent),
      "ActionButton's own Theme still paints attention urgent")
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ./tests/run.sh tst_run_indicator`
Expected: the `== tests/ui/components/tst_run_indicator.qml` block reports a failure (qmltestrunner cannot create `UI.RunIndicator`: "RunIndicator is not a type"), and the script exits non-zero. Pytest runs first and passes.

- [ ] **Step 3: Write minimal implementation**

Create `ui/components/RunIndicator.qml`:

```qml
import QtQuick
import qs.Commons
import "runGlyphs.js" as RunGlyphs
import "../components" as UI
import "../theme" as T

// The toolbar's am run strip, beside MilestoneJobIndicator: one segment per
// non-zero count, each the shared run glyph immediately followed by the count
// (`⟳2 ⏸1 ‼1`), in the order running, parked, attention. Attention reads in
// `urgent`; every state keeps its glyph, so colour is never the only signal.
// Static: no animation.
//
// Presentation only: the owner computes the three counts (attention is
// escalated plus dead) and passes them in. Each is read through
// runGlyphs.countOf, so a negative, non-finite or non-number value is 0, and
// the whole strip hides when all three are 0 -- no runs, or only finished
// ones. A click asks for the matching Runs screen filter through
// `filterRequested(filter)`. The filter vocabulary is the Runs screen's chip
// set: "attention" (Needs attention), "live", "parked" and "all"; the running
// segment asks for "live", parked for "parked", attention for "attention",
// and no segment asks for "all".
Item {
  id: indicator
  objectName: "runIndicator"

  property var running: 0
  property var parked: 0
  property var attention: 0
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}

  readonly property real runningCount: RunGlyphs.countOf({ n: indicator.running }, "n")
  readonly property real parkedCount: RunGlyphs.countOf({ n: indicator.parked }, "n")
  readonly property real attentionCount: RunGlyphs.countOf({ n: indicator.attention }, "n")

  signal filterRequested(string filter)

  visible: indicator.runningCount + indicator.parkedCount + indicator.attentionCount > 0
  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)

    UI.ActionButton {
      objectName: "runIndicatorRunning"
      visible: indicator.runningCount > 0
      theme: indicator.theme
      text: RunGlyphs.glyphOf("running") + indicator.runningCount
      onClicked: indicator.filterRequested("live")
    }

    UI.ActionButton {
      objectName: "runIndicatorParked"
      visible: indicator.parkedCount > 0
      theme: indicator.theme
      text: RunGlyphs.glyphOf("parked") + indicator.parkedCount
      onClicked: indicator.filterRequested("parked")
    }

    UI.ActionButton {
      objectName: "runIndicatorAttention"
      visible: indicator.attentionCount > 0
      theme: indicator.theme
      text: RunGlyphs.glyphOf("escalated") + indicator.attentionCount
      tone: "danger"
      onClicked: indicator.filterRequested("attention")
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ./tests/run.sh tst_run_indicator`
Expected: `Totals: 12 passed, 0 failed` for `tst_run_indicator.qml` (10 test functions plus initTestCase/cleanupTestCase), no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` lines, exit 0. If a test fails, fix `RunIndicator.qml`, not the test.

- [ ] **Step 5: Document the component in the Shared components list**

In `docs/architecture.md`, replace the two lines

```
`PhaseTimeline` (one subtask's phases as a single static line such as `spec✔ → plan✔ → implement⟳ → verify· → review·`: done ✔, started ⟳ and failed ✖ from `runGlyphs.js`, pending a local ·; an unknown status shows the bare name, bad entries are skipped and missing or empty `phases` hide it; no colour-only state, no animation),
`Sidebar`, and the views
```

with

```
`PhaseTimeline` (one subtask's phases as a single static line such as `spec✔ → plan✔ → implement⟳ → verify· → review·`: done ✔, started ⟳ and failed ✖ from `runGlyphs.js`, pending a local ·; an unknown status shows the bare name, bad entries are skipped and missing or empty `phases` hide it; no colour-only state, no animation),
`RunIndicator` (the toolbar's run strip beside `MilestoneJobIndicator`: one `ActionButton` per non-zero `running` / `parked` / `attention` prop, written glyph-then-count with no space such as `⟳2 ⏸1 ‼1`, glyphs from `runGlyphs.js` and counts clamped by its `countOf`; attention in `urgent`; hidden when all three are 0; static, no animation; presentation only -- the owner computes the counts, and a click emits `filterRequested(filter)` with `"live"`, `"parked"` or `"attention"` from the Runs filter set `attention` / `live` / `parked` / `all`, `all` being emitted by no segment),
`Sidebar`, and the views
```

- [ ] **Step 6: Run the full suite**

Run: `bash ./tests/run.sh`
Expected: pytest passes (including `tests/architecture/test_layers.py` and `tests/architecture/test_icon_glyphs.py`, unchanged), every QML file reports `Totals: ... 0 failed`, no error lines, exit 0.

- [ ] **Step 7: Commit**

```bash
git add tests/ui/components/tst_run_indicator.qml ui/components/RunIndicator.qml docs/architecture.md
git commit -m "feat(ui): add RunIndicator toolbar strip with filterRequested signal"
```

---

### Task 2: Sidebar attention count prop and NavRow count slot

**Files:**
- Modify: `tests/ui/tst_sidebar.qml:1-3` (imports) and append after the last test function (currently ending at line 183)
- Modify: `ui/components/Sidebar.qml:1-6` (imports), `:22` (props), `:198-235` (`NavRow`)
- Modify: `docs/architecture.md:115-118` (the `Sidebar` nav-rows sentence)

**Interfaces:**
- Consumes: `ui/components/runGlyphs.js` — `glyphOf("escalated")` (returns `"‼"`). `UI.ThemedText` (`theme`, `text`, `color`).
- Produces: `Sidebar.runsAttention: int` (default 0), `Sidebar.runsAttentionText: string` (readonly; `glyphOf("escalated") + runsAttention` when > 0, else `""`), `NavRow.countText: string` (default `""`), child `ThemedText` objectName `"navCount" + Section` (e.g. `navCountBoard`, and `navCountRuns` once card 5.1 adds `NavRow { section: "runs"; countText: sidebar.runsAttentionText }`).

- [ ] **Step 1: Write the failing tests**

In `tests/ui/tst_sidebar.qml`, replace the import block

```qml
import QtQuick
import QtTest
import "../../ui/components"
```

with

```qml
import QtQuick
import QtTest
import "../../ui/components"
import "../../ui/components/runGlyphs.js" as RG
```

Then append these four tests at the end of the file, just before its final closing `}` of the `TestCase` (leave the existing last test, `test_the_sidebar_lists_issues_last_with_its_own_icon`, untouched: it uses a `\uf188` escape that must not be retyped as a raw glyph):

```qml
  function test_runs_attention_defaults_to_nothing() {
    var sb = make()
    compare(sb.runsAttention, 0)
    compare(sb.runsAttentionText, "")
  }

  function test_runs_attention_text_follows_the_count() {
    var sb = make()
    sb.runsAttention = 3
    compare(sb.runsAttentionText, RG.glyphOf("escalated") + "3")
    compare(sb.runsAttentionText, "‼3", "the shared escalated glyph, no space")
    sb.runsAttention = 0
    compare(sb.runsAttentionText, "")
    sb.runsAttention = -2
    compare(sb.runsAttentionText, "", "a negative count shows nothing")
  }

  function test_existing_rows_show_no_count() {
    var sb = make()
    sb.runsAttention = 5
    wait(20)
    var names = ["navCountBoard", "navCountGraph", "navCountDocuments", "navCountMemories", "navCountIssues"]
    for (var i = 0; i < names.length; i++) {
      var count = find(sb, names[i])
      verify(count, names[i] + " slot exists")
      compare(count.visible, false, names[i] + " stays hidden: no existing row sets countText")
    }
  }

  function test_a_row_given_a_count_shows_it_after_its_label_in_urgent() {
    var sb = make()
    var row = find(sb, "navBoard")
    row.countText = "‼2"
    wait(20)
    var count = find(sb, "navCountBoard")
    compare(count.visible, true)
    compare(String(count.text), "‼2")
    verify(Qt.colorEqual(count.color, sb.theme.urgent), "the count reads in urgent")
    verify(count.mapToItem(row, 0, 0).x > find(sb, "navIconBoard").mapToItem(row, 0, 0).x,
      "the count follows the icon and label")
    row.countText = ""
    wait(20)
    compare(count.visible, false)
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash ./tests/run.sh tst_sidebar.qml`
Expected: `tests/ui/tst_sidebar.qml` reports FAIL for `test_runs_attention_defaults_to_nothing` (actual `undefined`, expected `0`), `test_runs_attention_text_follows_the_count`, `test_existing_rows_show_no_count` ("navCountBoard slot exists" fails) and `test_a_row_given_a_count_shows_it_after_its_label_in_urgent`; the existing tests still pass; exit non-zero. (`tst_sidebar_nav.qml` does not match the filter `tst_sidebar.qml`.)

- [ ] **Step 3: Add the import and the props to Sidebar**

In `ui/components/Sidebar.qml`, replace

```qml
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../components" as UI
import "../theme" as T
```

with

```qml
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "runGlyphs.js" as RunGlyphs
import "../components" as UI
import "../theme" as T
```

Then replace

```qml
  property bool documentsEnabled: true
  // The one input for every colour and font: Panel passes its Theme down,
```

with

```qml
  property bool documentsEnabled: true
  // How many runs need attention (escalated plus dead), computed by the
  // owner. Rendered as `‼N` by runsAttentionText; card 5.1's Runs row binds
  // `countText: sidebar.runsAttentionText`. No row shows it yet.
  property int runsAttention: 0
  readonly property string runsAttentionText: sidebar.runsAttention > 0
    ? RunGlyphs.glyphOf("escalated") + sidebar.runsAttention : ""
  // The one input for every colour and font: Panel passes its Theme down,
```

- [ ] **Step 4: Add the count slot to NavRow**

In `ui/components/Sidebar.qml`, replace

```qml
  component NavRow: CursorSurface {
    id: navRow
    property string label: ""
    property string section: ""
    property string iconText: ""
```

with

```qml
  component NavRow: CursorSurface {
    id: navRow
    property string label: ""
    property string section: ""
    property string iconText: ""
    // An optional count after the label, such as the Runs row's `‼N`; "" (the
    // default) shows nothing, so a row that does not set it is unchanged.
    property string countText: ""
```

Then replace

```qml
      UI.ThemedText {
        id: navLabel
        theme: sidebar.theme
        text: navRow.label
        font.bold: navRow.current
      }
    }
```

with

```qml
      UI.ThemedText {
        id: navLabel
        theme: sidebar.theme
        text: navRow.label
        font.bold: navRow.current
      }

      UI.ThemedText {
        // navCountBoard, navCountGraph, ... -- hidden unless the row has a count.
        objectName: "navCount" + navRow.section.charAt(0).toUpperCase() + navRow.section.slice(1)
        theme: sidebar.theme
        anchors.verticalCenter: navLabel.verticalCenter
        visible: navRow.countText !== ""
        text: navRow.countText
        color: sidebar.theme.urgent
        font.bold: true
      }
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash ./tests/run.sh tst_sidebar`
Expected: both `tests/ui/tst_sidebar.qml` and `tests/ui/tst_sidebar_nav.qml` report `0 failed`, no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` lines, exit 0.

- [ ] **Step 6: Document the prop next to the Sidebar sentence**

In `docs/architecture.md`, replace

```
`Sidebar`'s five nav rows (Board, Graph, Documents, Memories, Issues) each lead with an
icon glyph drawn in the theme's font; `tests/architecture/test_icon_glyphs.py`
checks every glyph literal in `ui/` and `vendor/` against the installed Nerd
Fonts, because a glyph the font does not have renders as an empty box.
```

with

```
`Sidebar`'s five nav rows (Board, Graph, Documents, Memories, Issues) each lead with an
icon glyph drawn in the theme's font; `tests/architecture/test_icon_glyphs.py`
checks every glyph literal in `ui/` and `vendor/` against the installed Nerd
Fonts, because a glyph the font does not have renders as an empty box.
`Sidebar.runsAttention` (int, default 0; the owner's escalated-plus-dead run count) derives `runsAttentionText` (`‼N` from `runGlyphs.js` when N > 0, otherwise empty), and `NavRow.countText` draws such a count after a row's label in `urgent` as `navCount<Section>`; no current row sets it, and the Runs row (story 5.x) binds `countText: sidebar.runsAttentionText`.
```

- [ ] **Step 7: Run the full suite**

Run: `bash ./tests/run.sh`
Expected: pytest passes (architecture tier unchanged and green: no store import, no new `CursorSurface {` / `bordered: true` / `font.family:`, no private-use glyphs), every QML file reports `0 failed`, no error lines, exit 0.

- [ ] **Step 8: Commit**

```bash
git add tests/ui/tst_sidebar.qml ui/components/Sidebar.qml docs/architecture.md
git commit -m "feat(ui): add Sidebar runsAttention prop and NavRow count slot"
```
