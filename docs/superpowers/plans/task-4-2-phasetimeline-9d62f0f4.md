<!-- task-pipeline: validated -->
# 4.2 PhaseTimeline (card 9d62f0f4) — design

Narrows `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` (S1, read-only run monitor; glyph table at lines 142-157, Run detail timeline row at lines 195-212) to one subtask. Parent story fa4592b2 "Run components". Built on branch `mon/task-4-2-phasetimeline-9d62f0f4`, which already carries 4.1's `Pulse.qml`, `runGlyphs.js`, `RunBadge.qml`, `RunRollupBar.qml` (main f10da0e has none of these).

## Scope

In scope:

- New `ui/components/PhaseTimeline.qml`: renders one subtask's phases as a single line, e.g. `spec✔ → plan✔ → implement⟳ → verify· → review·`.
- New `tests/ui/components/tst_phase_timeline.qml`, written first (TDD).
- `docs/architecture.md`: add a `PhaseTimeline` entry to the shared-components list, one line in the same style as the `Pulse` / `RunBadge` / `RunRollupBar` entries (around lines 98-112).

Out of scope (sibling or later cards own it): `RunBadge` / `RunRollupBar` / `Pulse` (4.1), `RunIndicator.qml` and the Sidebar `‼N` attention count (4.3), the Runs sidebar row (5.1), RunsScreen / RunDetailScreen and wiring the timeline under the selected subtask, any store (`RunStore`), `core/domain/runs.js`, backend code. PhaseTimeline computes no run state; it only receives props. `runGlyphs.js` is read, not changed.

## Interface

- `property var phases: []` — array of `{ name, status }` entries in display order, as found at `run.tree.subtasks[].phases[]`. Names come from the array; the component hardcodes no phase list.
- `property var theme: null` — palette, falling back to `T.Theme` from `../theme` exactly as `StatusPips` does.
- Root `objectName: "phaseTimeline"`; the single `ThemedText` line has `objectName: "phaseTimelineText"`.
- The root is an `Item` (sized to the `ThemedText` child via `implicitWidth`/`implicitHeight`), not a `Text`, so it can expose `readonly property string text` (the rendered line, bound to the child's `text`) without clashing with a Text's own `text`. The child `ThemedText` receives the resolved palette as its `theme`, and `elide`/`wrapMode` are left at defaults (one line, no wrapping requirement).

## Observable behavior

- Each valid entry renders as `name` immediately followed by its status glyph; entries are joined with ` → `.
- Glyph mapping, taken from `runGlyphs.js` where a run-state glyph exists so a state reads the same everywhere: `done` → `✔` (`GLYPHS.done`), `started` → `⟳` (`GLYPHS.running`), `failed` → `✖` (`GLYPHS.dead`), `pending` → `·` (U+00B7, local constant; no run-state equivalent). All are plain BMP characters, never Nerd Font / private-use code points, so `tests/architecture/test_icon_glyphs.py` passes unchanged.
- Status matching is exact (case-sensitive, string only), consistent with `runs.js`. An entry with a valid name but an unknown, missing, or non-string status renders the bare name with no glyph (never a guessed glyph).
- State is shown by glyph, never colour alone. The whole line uses the palette's `foreground`; no per-phase colour is required. If any emphasis is added for `failed`, it uses the theme `urgent` token only; never `#9b72cf`, `#d9534f`, or `Board.statusColor`.
- Static: no animation. `started` is conveyed by `⟳` alone; the component declares no `Animation`/`Timer` and does not use `Pulse`.
- `visible` is false when the rendered line is empty.

## Error paths

All must render nothing (or skip the bad entry) without any qmltestrunner warning that `tests/run.sh` treats as failure (TypeError, ReferenceError, "non-existent", "Unable to assign", "is not a function"):

- `phases` is `null`, `undefined`, a string, a number, or a plain object → empty line, not visible.
- Empty array → empty line, not visible.
- Entries that are `null`, non-objects, or whose `name` is not a non-empty string → skipped; the remaining entries still render and join correctly.
- Status names that are inherited object keys (`"constructor"`, `"toString"`, `"__proto__"`) → no glyph (guard with `Object.prototype.hasOwnProperty.call`, as `runGlyphs.js` does).
- Missing `theme` → falls back to `T.Theme`, no warning.

## Constraints

- Layering (`docs/architecture.md:15`): no import of `core/stores`; may import `qs.Commons`, QtQuick, `../theme`, and sibling `runGlyphs.js`. Name `PhaseTimeline` clashes with no `qs.Ui` or QtQuick/Controls type.
- All text through `ThemedText`; no second `font.family:`. None of the guarded duplicated patterns (`radius: height / 2`, `bordered: true`, `Qt.rgba(0, 0, 0, 0.55)`, `CursorSurface {`) per `tests/architecture/test_layers.py` `test_no_second_copy_of_shared_visual_patterns`. `Badge` is not used (a timeline is a line of text, not a pill).
- `tests/architecture` must pass unchanged.

## Tests

Tier placement per `docs/architecture.md` "How to add" / "Tests" (lines 132-152) and the S1 spec Testing section (lines 233-247): a shared component gets a QML UI component test at `tests/ui/components/tst_<snake_name>.qml`. All tests below are therefore **UI component tests** in `tests/ui/components/tst_phase_timeline.qml` (TestCase `when: windowShown`, `import "../../helpers/find.js" as H`, `import "../../../ui/components" as UI`, `import "../../../ui/theme" as T`, `createTemporaryObject` + `wait(30)`, style of `tst_status_pips.qml` / `tst_run_badge.qml`). The existing **architecture tier** (`tests/architecture/test_layers.py`, `test_icon_glyphs.py`) must pass unchanged; no new architecture, store, domain, contract, or backend tests.

| Test (UI component tier) | Pins |
|---|---|
| `test_full_timeline` | `[spec done, plan done, implement started, verify pending, review pending]` renders exactly `spec✔ → plan✔ → implement⟳ → verify· → review·`; visible. |
| `test_failed_glyph` | A `failed` phase renders `name✖`, and the glyph equals `runGlyphs.js` `GLYPHS.dead`. |
| `test_glyphs_match_run_glyphs` | `done` uses `GLYPHS.done` and `started` uses `GLYPHS.running`. |
| `test_names_from_array` | Arbitrary names (e.g. `alpha`, `beta`) render as given; one entry renders with no arrow. |
| `test_empty_and_bad_phases` | `[]`, `null`, `undefined`, `"x"`, `5`, `{}` → empty text, not visible, no warnings. |
| `test_bad_entries_skipped` | `[null, 5, {status:"done"}, {name:7,status:"done"}, {name:"plan",status:"done"}]` renders `plan✔`. |
| `test_unknown_status` | `RUNNING`, `"Done"`, missing status, numeric status, `"constructor"` → bare name, no glyph. |
| `test_updates_on_change` | Reassigning `phases` re-renders the line. |
| `test_theme_fallback` | No `theme` set → renders with the fallback Theme, no warnings. |
| `test_static` | No pulse: opacity stays 1 with a `started` phase. |

---

# 4.2 PhaseTimeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shared, static, props-only `PhaseTimeline` QML component that renders one subtask's phases as `spec✔ → plan✔ → implement⟳ → verify· → review·`, with UI component tests written first and a shared-components entry in `docs/architecture.md`.

**Architecture:** `ui/components/PhaseTimeline.qml` is an `Item` wrapping one `ThemedText`; a pure JS function on the root (`lineOf(phases)`) builds the line from the `phases` prop, taking `done`/`started`/`failed` glyphs from the existing `ui/components/runGlyphs.js` (`GLYPHS.done`, `GLYPHS.running`, `GLYPHS.dead`) and a local `·` for `pending`. Theme falls back to its own `T.Theme` like `StatusPips`/`RunRollupBar`. No animation, no store import, no `Badge`.

**Tech Stack:** QML (Qt 6 QtQuick), QtTest via `qmltestrunner` driven by `bash ./tests/run.sh`, pytest architecture tests (unchanged).

**Spec:** `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-4-2-phasetimeline-9d62f0f4/docs/superpowers/specs/task-4-2-phasetimeline-9d62f0f4-design.md` (copied verbatim above).

**Working directory for every command:** `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-4-2-phasetimeline-9d62f0f4` (branch `mon/task-4-2-phasetimeline-9d62f0f4`, cut from `mon/task-4-1-runbadge-and-80cb429b`). Nothing from any other subtask (4.3 `RunIndicator`, 5.x screens, `RunStore`) exists on this branch and none of it is needed.

## Global Constraints

- `ui/components/**` must not import `core/stores` (`docs/architecture.md:15`); PhaseTimeline imports only `QtQuick`, `"runGlyphs.js"`, `"../theme"`.
- All text through `ThemedText`; no `font.family:` in `PhaseTimeline.qml`.
- None of `radius: height / 2`, `bordered: true`, `Qt.rgba(0, 0, 0, 0.55)`, `CursorSurface {` in `PhaseTimeline.qml`.
- `Badge` is not used.
- Glyphs: `done` → `✔` (`GLYPHS.done`), `started` → `⟳` (`GLYPHS.running`), `failed` → `✖` (`GLYPHS.dead`), `pending` → `·` (U+00B7, local). Plain BMP only, never private-use code points.
- Separator is exactly ` → ` (space, U+2192, space); name and glyph are adjacent with no space.
- Status matching exact, case-sensitive, string only, guarded with `Object.prototype.hasOwnProperty.call`.
- Line colour is the palette's `foreground`; never `#9b72cf`, `#d9534f`, or `Board.statusColor`.
- Static: no `Animation`, `Timer`, or `Pulse`.
- `visible` is false when the rendered line is empty.
- Root `objectName: "phaseTimeline"`, text child `objectName: "phaseTimelineText"`.
- `runGlyphs.js`, `RunBadge.qml`, `RunRollupBar.qml`, `Pulse.qml`, `StatusPips.qml`, and everything under `tests/architecture` stay unchanged.
- No qmltestrunner output matching `TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function` (`tests/run.sh` line 31 fails on it).

## Review Focus

- A phase entry whose `name` is the empty string `""` is skipped, so you never get a bare glyph or a doubled ` →  → `. Pinned in Task 2 `test_bad_entries_skipped`.
- An `undefined` entry or a hole in the array (e.g. `[undefined, {name:"plan",status:"done"}]`) is skipped without a TypeError. Pinned in Task 2 `test_bad_entries_skipped`.
- A status that matches an inherited `Object.prototype` key (`"toString"`, `"__proto__"`, `"hasOwnProperty"`) shows the bare name, never a function's source text. Pinned in Task 2 `test_unknown_status`.
- A phase name containing markup such as `<b>x</b>` renders literally, not as rich text, because `Text`'s default `AutoText` would interpret it. Pinned in Task 2 `test_name_is_plain_text`.
- When the owner's `theme` is nulled at runtime (view teardown), the line falls back to its own Theme and keeps rendering without a TypeError. Pinned in Task 2 `test_theme_reset_to_null`.

---

## File Structure

- Create `ui/components/PhaseTimeline.qml`: the component (root `Item`, one `ThemedText`, a fallback `T.Theme`, a pure `lineOf(phases)` function).
- Create `tests/ui/components/tst_phase_timeline.qml`: every PhaseTimeline UI component test (the tier and directory convention of the sibling `tst_run_badge.qml` / `tst_run_rollup_bar.qml` / `tst_status_pips.qml`).
- Modify `docs/architecture.md:109-112`: add the `PhaseTimeline` entry right after the `RunRollupBar` entry in the shared-components list.

---

### Task 1: PhaseTimeline renders a line of valid phases

**Files:**
- Create: `tests/ui/components/tst_phase_timeline.qml`
- Create: `ui/components/PhaseTimeline.qml`

**Interfaces:**
- Consumes: `ui/components/runGlyphs.js` `GLYPHS` (`GLYPHS.done === "✔"`, `GLYPHS.running === "⟳"`, `GLYPHS.dead === "✖"`); `ui/components/ThemedText.qml` (`property var theme`, `variant`, colour = `palette.foreground` for the default `body` variant); `ui/theme` `Theme` (`foreground`, `dim`, `urgent`).
- Produces: `PhaseTimeline` with `property var phases` (default `[]`), `property var theme` (default `null`), `readonly property var palette` (`theme || own T.Theme`), `readonly property string text` (the rendered line), `function lineOf(phases)` returning a string; root `objectName "phaseTimeline"`, child `ThemedText` `objectName "phaseTimelineText"`. Task 2 hardens `lineOf` without renaming anything.

- [ ] **Step 1: Write the failing tests**

Create `tests/ui/components/tst_phase_timeline.qml`:

```qml
// tests/ui/components/tst_phase_timeline.qml
// ui/components/PhaseTimeline.qml: one subtask's phases as a single static
// line, `name` + glyph joined by " → " (done ✔, started ⟳, failed ✖ from
// runGlyphs.js, pending ·). Never colour alone, never animated, and nothing at
// all for missing, empty or garbage phases.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/components/runGlyphs.js" as RG
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "PhaseTimeline"
  when: windowShown
  visible: true
  width: 600; height: 200

  // Three distinct tokens, so a tint can only match the one it is meant to.
  T.Theme { id: testTheme; foreground: "#eeeeee"; dim: "#777777"; urgent: "#ff3300" }

  Component { id: timelineC; UI.PhaseTimeline {} }

  function make(props) {
    var timeline = createTemporaryObject(timelineC, tc, props || {})
    wait(30)
    return timeline
  }

  function lineOf(timeline) { return H.find(timeline, "phaseTimelineText").text }

  function test_full_timeline() {
    var timeline = make({ theme: testTheme, phases: [
      { name: "spec", status: "done" },
      { name: "plan", status: "done" },
      { name: "implement", status: "started" },
      { name: "verify", status: "pending" },
      { name: "review", status: "pending" }
    ] })
    compare(timeline.objectName, "phaseTimeline")
    compare(lineOf(timeline), "spec✔ → plan✔ → implement⟳ → verify· → review·")
    compare(timeline.text, "spec✔ → plan✔ → implement⟳ → verify· → review·")
    compare(timeline.visible, true)
    verify(timeline.implicitWidth > 0, "sized to its line")
    verify(timeline.implicitHeight > 0)
  }

  function test_failed_glyph() {
    var timeline = make({ theme: testTheme, phases: [{ name: "verify", status: "failed" }] })
    compare(lineOf(timeline), "verify✖")
    compare(lineOf(timeline), "verify" + RG.GLYPHS.dead, "failed reads as the run-state dead glyph")
  }

  function test_glyphs_match_run_glyphs() {
    var timeline = make({ theme: testTheme, phases: [
      { name: "a", status: "done" },
      { name: "b", status: "started" }
    ] })
    compare(lineOf(timeline), "a" + RG.GLYPHS.done + " → b" + RG.GLYPHS.running)
  }

  function test_names_from_array() {
    var timeline = make({ theme: testTheme, phases: [
      { name: "alpha", status: "done" },
      { name: "beta", status: "pending" }
    ] })
    compare(lineOf(timeline), "alpha✔ → beta·")

    var one = make({ theme: testTheme, phases: [{ name: "solo", status: "started" }] })
    compare(lineOf(one), "solo⟳", "one entry, no arrow")
  }

  function test_updates_on_change() {
    var timeline = make({ theme: testTheme, phases: [{ name: "spec", status: "started" }] })
    compare(lineOf(timeline), "spec⟳")
    timeline.phases = [{ name: "spec", status: "done" }, { name: "plan", status: "started" }]
    wait(30)
    compare(lineOf(timeline), "spec✔ → plan⟳")
    timeline.phases = []
    wait(30)
    compare(lineOf(timeline), "")
    compare(timeline.visible, false, "an emptied timeline hides")
  }

  function test_theme_fallback() {
    var themed = make({ theme: testTheme, phases: [{ name: "spec", status: "done" }] })
    verify(Qt.colorEqual(H.find(themed, "phaseTimelineText").color, testTheme.foreground),
           "the line reads in the owner's foreground")

    var own = make({ phases: [{ name: "spec", status: "done" }] })
    verify(own.palette, "falls back to its own Theme")
    compare(lineOf(own), "spec✔")
    verify(Qt.colorEqual(H.find(own, "phaseTimelineText").color, own.palette.foreground))

    var states = ["done", "started", "failed", "pending"]
    for (var i = 0; i < states.length; i++) {
      var t = make({ phases: [{ name: "p", status: states[i] }] })
      var c = H.find(t, "phaseTimelineText").color
      verify(!Qt.colorEqual(c, "#9b72cf"), states[i] + " is not the merged colour")
      verify(!Qt.colorEqual(c, "#d9534f"), states[i] + " is not the canceled colour")
    }
  }

  function test_static() {
    var timeline = make({ theme: testTheme, phases: [
      { name: "spec", status: "done" },
      { name: "implement", status: "started" }
    ] })
    wait(120)
    compare(timeline.opacity, 1, "no pulse on the timeline")
    compare(H.find(timeline, "phaseTimelineText").opacity, 1, "no pulse on the line")
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash ./tests/run.sh tst_phase_timeline`
Expected: the `== tests/ui/components/tst_phase_timeline.qml` block fails to load (qmltestrunner reports `PhaseTimeline is not a type`), and the script exits non-zero.

- [ ] **Step 3: Write the minimal implementation**

Create `ui/components/PhaseTimeline.qml`:

```qml
import QtQuick
import "runGlyphs.js" as RunGlyphs
import "../theme" as T

// One subtask's phases as a single static line, e.g.
// `spec✔ → plan✔ → implement⟳ → verify· → review·`. Presentation only:
// `phases` is [{ name, status }] in display order (run.tree.subtasks[].phases[]),
// status started | done | failed | pending. done, started and failed borrow
// the run-state glyphs from runGlyphs.js (done, running, dead) so a state
// reads the same everywhere; pending has no run-state twin and is a local ·.
// State is the glyph, never colour; nothing animates.
Item {
  id: timeline
  objectName: "phaseTimeline"

  property var phases: []
  // The owner's Theme, or none: `palette` then falls back to the line's own.
  property var theme: null

  readonly property var palette: timeline.theme || timelineTheme
  readonly property string text: timeline.lineOf(timeline.phases)

  // The rendered line for a phases array.
  function lineOf(phases) {
    var glyphs = {
      done: RunGlyphs.GLYPHS.done,
      started: RunGlyphs.GLYPHS.running,
      failed: RunGlyphs.GLYPHS.dead,
      pending: "·"
    }
    var parts = []
    for (var i = 0; i < phases.length; i++)
      parts.push(phases[i].name + (glyphs[phases[i].status] || ""))
    return parts.join(" → ")
  }

  implicitWidth: line.implicitWidth
  implicitHeight: line.implicitHeight
  visible: timeline.text !== ""

  ThemedText {
    id: line
    objectName: "phaseTimelineText"
    theme: timeline.palette
    text: timeline.text
  }

  T.Theme { id: timelineTheme }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash ./tests/run.sh tst_phase_timeline`
Expected: pytest passes (including `tests/architecture`), then `== tests/ui/components/tst_phase_timeline.qml` prints `Totals: 9 passed, 0 failed` (7 tests plus initTestCase/cleanupTestCase), no `TypeError`/`ReferenceError` lines, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add tests/ui/components/tst_phase_timeline.qml ui/components/PhaseTimeline.qml
git commit -m "feat(ui): PhaseTimeline renders a subtask's phases as one glyph line"
```

---

### Task 2: PhaseTimeline survives bad input, plus the architecture doc entry

**Files:**
- Modify: `tests/ui/components/tst_phase_timeline.qml` (append test functions before the closing `}` of `TestCase`)
- Modify: `ui/components/PhaseTimeline.qml` (replace `lineOf`, add `textFormat`)
- Modify: `docs/architecture.md:109-112`

**Interfaces:**
- Consumes: Task 1's `PhaseTimeline` (`phases`, `theme`, `palette`, `text`, `lineOf(phases)`, objectNames `phaseTimeline` / `phaseTimelineText`) and the test file's `make(props)` / `lineOf(timeline)` helpers and `testTheme`.
- Produces: the same interface, now total over any input: `lineOf(anything)` returns a string and never throws; the child `ThemedText` has `textFormat: Text.PlainText`.

- [ ] **Step 1: Write the failing tests**

In `tests/ui/components/tst_phase_timeline.qml`, insert these functions immediately after `test_static()` (before the final `}` that closes `TestCase`):

```qml
  function test_empty_and_bad_phases() {
    var bad = [[], null, undefined, "x", 5, {}]
    var labels = ["[]", "null", "undefined", "\"x\"", "5", "{}"]
    for (var i = 0; i < bad.length; i++) {
      var timeline = make({ theme: testTheme })
      timeline.phases = bad[i]
      wait(30)
      compare(timeline.text, "", labels[i] + " renders nothing")
      compare(lineOf(timeline), "", labels[i])
      compare(timeline.visible, false, labels[i] + " hides the timeline")
    }
  }

  function test_bad_entries_skipped() {
    var timeline = make({ theme: testTheme })
    timeline.phases = [null, 5, { status: "done" }, { name: 7, status: "done" },
                       { name: "plan", status: "done" }]
    wait(30)
    compare(lineOf(timeline), "plan✔", "only the valid entry renders")

    // Empty names, undefined entries and holes are skipped too; extra fields are ignored.
    var sparse = [undefined, { name: "", status: "done" }, "spec",
                  { name: "spec", status: "done", started_at: "2026-10-04T10:00:00Z" }]
    sparse[5] = { name: "verify", status: "pending" }
    timeline.phases = sparse
    wait(30)
    compare(lineOf(timeline), "spec✔ → verify·", "no empty segment, no doubled arrow")
    compare(timeline.visible, true)
  }

  function test_unknown_status() {
    var statuses = ["RUNNING", "Done", undefined, 3, "constructor", "toString", "__proto__", "hasOwnProperty"]
    for (var i = 0; i < statuses.length; i++) {
      var entry = { name: "plan" }
      if (statuses[i] !== undefined) entry.status = statuses[i]
      var timeline = make({ theme: testTheme })
      timeline.phases = [entry]
      wait(30)
      compare(lineOf(timeline), "plan", "status " + String(statuses[i]) + " shows the bare name")
      compare(timeline.visible, true)
    }
  }

  function test_name_is_plain_text() {
    var timeline = make({ theme: testTheme, phases: [{ name: "<b>x</b>", status: "done" }] })
    var line = H.find(timeline, "phaseTimelineText")
    compare(line.textFormat, Text.PlainText, "a name is never read as markup")
    compare(line.text, "<b>x</b>✔")
  }

  function test_theme_reset_to_null() {
    var timeline = make({ theme: testTheme, phases: [{ name: "spec", status: "done" }] })
    timeline.theme = null
    wait(30)
    verify(timeline.palette, "falls back to its own Theme when the owner's goes away")
    compare(lineOf(timeline), "spec✔")
    verify(Qt.colorEqual(H.find(timeline, "phaseTimelineText").color, timeline.palette.foreground))
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash ./tests/run.sh tst_phase_timeline`
Expected: exit non-zero. `test_empty_and_bad_phases` makes the `text` binding throw `TypeError` (reading `length` of null/undefined), which `run.sh` prints and treats as failure even though its compares may pass (a throwing binding leaves the old empty text); `test_bad_entries_skipped` FAILs on `plan✔` with the same `TypeError` lines (reading `name` of null); `test_unknown_status` FAILs on `constructor` (the line becomes `plan` followed by a function's source); `test_name_is_plain_text` FAILs on `textFormat`. `test_theme_reset_to_null` may already pass (it pins existing behaviour). The Task 1 tests still pass.

- [ ] **Step 3: Write the implementation**

In `ui/components/PhaseTimeline.qml`, replace the whole `lineOf` function (the `// The rendered line for a phases array.` comment through its closing `}`) with:

```qml
  // The glyph for a phase status; "" for anything but an exact, own key
  // (so "Done", 3 and inherited names such as "constructor" show no glyph).
  function glyphOf(status) {
    var glyphs = {
      done: RunGlyphs.GLYPHS.done,
      started: RunGlyphs.GLYPHS.running,
      failed: RunGlyphs.GLYPHS.dead,
      pending: "·"
    }
    return typeof status === "string" && Object.prototype.hasOwnProperty.call(glyphs, status) ? glyphs[status] : ""
  }

  // The rendered line for a phases array. Anything but an array-like object
  // is no line at all; an entry that is not an object with a non-empty string
  // `name` (null, a number, a hole, "", 7) is skipped.
  function lineOf(phases) {
    if (phases === null || typeof phases !== "object" || typeof phases.length !== "number") return ""
    var parts = []
    for (var i = 0; i < phases.length; i++) {
      var entry = phases[i]
      if (entry === null || entry === undefined || typeof entry !== "object") continue
      if (typeof entry.name !== "string" || entry.name === "") continue
      parts.push(entry.name + timeline.glyphOf(entry.status))
    }
    return parts.join(" → ")
  }
```

Then in the same file, change the `ThemedText` block to read:

```qml
  ThemedText {
    id: line
    objectName: "phaseTimelineText"
    theme: timeline.palette
    textFormat: Text.PlainText
    text: timeline.text
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash ./tests/run.sh tst_phase_timeline`
Expected: pytest passes, `== tests/ui/components/tst_phase_timeline.qml` prints `Totals: 14 passed, 0 failed` (12 tests plus initTestCase/cleanupTestCase), no `TypeError`/`ReferenceError`/`is not a function` lines, exit code 0.

- [ ] **Step 5: Add the shared-components entry to `docs/architecture.md`**

In `docs/architecture.md`, replace:

```markdown
`RunRollupBar` (a milestone's or story's run rollup under its title: one
caption segment per non-zero count in the same glyphs, then `N pending`;
escalated in `urgent`; hidden when the rollup is null or its total is 0),
`Sidebar`, and the views
```

with:

```markdown
`RunRollupBar` (a milestone's or story's run rollup under its title: one
caption segment per non-zero count in the same glyphs, then `N pending`;
escalated in `urgent`; hidden when the rollup is null or its total is 0),
`PhaseTimeline` (one subtask's phases as a single static line such as `spec✔ → plan✔ → implement⟳ → verify· → review·`: done ✔, started ⟳ and failed ✖ from `runGlyphs.js`, pending a local ·; an unknown status shows the bare name, bad entries are skipped and missing or empty `phases` hide it; no colour-only state, no animation),
`Sidebar`, and the views
```

- [ ] **Step 6: Run the full verification**

Run: `bash ./tests/run.sh`
Expected: pytest all pass (the `tests/architecture` suite unchanged: no layer, guard, name-clash or icon-glyph failure), every `tst_*.qml` block reports `0 failed`, no `TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function` lines, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add tests/ui/components/tst_phase_timeline.qml ui/components/PhaseTimeline.qml docs/architecture.md
git commit -m "feat(ui): PhaseTimeline skips bad phases and entries; document it"
```
