<!-- task-pipeline: validated -->
# 4.1 RunBadge and RunRollupBar (card 80cb429b)

Parent story fa4592b2 "Run components". Milestone design: `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` (run-state table around lines 118-131, rollup at 134-136, UI at 170-171). This spec narrows that design to two presentational components.

## Scope

In scope:

- `ui/components/RunBadge.qml`: a run-state badge with an optional phase text (subtask use) or parent counts (milestone/story use).
- `ui/components/RunRollupBar.qml`: a row of rollup counts shown under a milestone or story title.
- Their component tests, which are written first (TDD).
- Add both names to the "Shared components" list in `docs/architecture.md`.

Out of scope, because sibling or other cards own it: `core/domain/runs.js` (runState, cardRunState, rollup, attention), `RunStore`, `PhaseTimeline.qml` (4.2), `RunIndicator.qml` and the Sidebar `‼N` count (4.3), RunsScreen, RunDetailScreen, the CardDetail Runs section, placing badges on board cards, Navigator/Shortcuts, and user docs. Neither component computes run state or rollups. Both only receive props.

## Constraints

- Layering. These are props-only components. They never import `core/stores`. The allowed imports are QtQuick, `qs.Commons`, `"../theme" as T`, and (optionally) `core/domain/*.js`. They must not call `Board.statusColor`, and they must not use `#9b72cf` or `#d9534f`.
- Component pattern, as in `Badge.qml` and `StatusPips.qml`: `property var theme: null`, `readonly property var palette: <id>.theme || <id>Theme`, a fallback `T.Theme {}`, every `palette` read guarded, spacing through `Style.space()`, text through `ThemedText` with `variant: "caption"`, and an `objectName` on every testable part.
- No duplicates of patterns that are already shared. The pill/ring reuses `Badge`. Do not add a new `radius: height / 2`, `bordered: true`, `font.family:`, `Qt.rgba(0,0,0,0.55)` or `CursorSurface {`. `tests/architecture/` must pass unchanged, with no new allowlist entry.
- State is never shown by colour alone. Every state has its own glyph, drawn inside a ring (the Badge pill).
- Escalated is tinted with `palette.urgent`. Every other state uses the theme's neutral tokens (`foreground` or `dim`).
- Glyphs are the BMP characters ⟳ ⏸ ‼ ✖ ⊘ ✔. No private-use or Nerd Font code points are added, so `test_icon_glyphs.py` stays green.
- Animation. The running ring pulses only while `state === "running"` and the item is visible. It reuses the StatusPips pulse (the `pulse` SequentialAnimation that drives `pulseOpacity`). RunBadge must not declare a second animation. The plan decides how the pulse is shared, but StatusPips' behaviour and its tests must stay unchanged.

## Observable behaviour

### RunBadge

Props:

- `theme`
- `state`: string. This is Item's own built-in string property, used as plain text (as `MilestoneJobIndicator` does; verified that assigning an unknown name such as `"bogus"` raises no error), so it is not redeclared. One of `running`, `parked`, `escalated`, `dead`, `cancelled`, `done`, or anything else.
- `phase`: string, default `""`.
- `counts`: a rollup-shaped object or `null`.
- `active`: bool, default true. It is ANDed into the pulse, as in StatusPips.

Readonly properties:

- `glyph`
- `pulsing`

Glyph per state:

| state | glyph |
| --- | --- |
| running | ⟳ |
| parked | ⏸ |
| escalated | ‼ |
| dead | ✖ |
| cancelled | ⊘ |
| done | ✔ |

Behaviour:

- **State badge:** shows the glyph for `state` inside the ring.
- **Phase:** when `phase` is non-empty, it is shown after the glyph in caption text (subtask use).
- **Counts:** when `counts` is set, the badge shows the non-zero `running`, `parked`, `escalated` and `done` entries, in that order, as `glyph N` pairs separated by spaces (for example `⟳ 2 ⏸ 1`). Zero entries are omitted (parent use).
- **Counts take precedence:** when `counts` is set, it replaces the single-state glyph, and `phase` is ignored. The badge is invisible when `counts` is set but every one of those four entries is 0. When `counts` is null, `state` and `phase` apply.
- **Escalated:** the badge tint is `palette.urgent`. Of the other states, `done` and `cancelled` use `palette.dim`; `running`, `parked`, `dead` and the counts form use `palette.foreground`.
- **objectNames:** the pill's text is exposed with `textObjectName: "runBadgeText"`, and the root has `objectName: "runBadge"`. Tests read the text from `runBadgeText` and the tint from the root's `tint`.
- **Running:** `pulsing` is true only when the state is `running`, the badge is visible, and `active` is true. It is false for every other state and when the badge is hidden.

### RunRollupBar

Props:

- `theme`
- `rollup`: `{running, parked, escalated, done, pending, total}` or `null`.

Behaviour:

- It shows one caption segment per non-zero count. Each segment has its own `objectName`: `runRollupRunning`, `runRollupParked`, `runRollupEscalated`, `runRollupDone` and `runRollupPending`. A segment's `text` is `glyph N` (or `N pending`), and its `color` is the tint, so tests read both off the segment. A zero count is not shown (`visible: false`) rather than missing from the tree.
- The `running`, `parked`, `escalated` and `done` segments use the same glyphs as RunBadge.
- The `pending` segment reads `N pending`.
- The `escalated` segment is tinted `palette.urgent`.
- It is invisible when `rollup` is null or `total` is 0.

## Error paths

- An unknown, empty or `"none"` `state`, with no `counts`, gives an invisible RunBadge and no console error. The test runner fails on TypeError, ReferenceError or "Unable to assign".
- Missing fields in `counts` or `rollup` are treated as 0.
- A null `theme`, or a theme torn down during destruction, falls back to the component's own `T.Theme` without errors.
- Switching `state` from `running` to anything else, or hiding the badge, stops the pulse and leaves the opacity at 1.

## Tests (written first)

All of the tests below are component tests. They go in **tests/ui/components/** under the placement rule in `docs/architecture.md` ("How to add" / "Tests"): one `tst_<component>.qml` per `ui/components` file. They follow the pattern of `tst_status_pips.qml`: `when: windowShown`, `createTemporaryObject`, and `H.find`. Run-state derivation tests are not part of this card. They belong in `tests/core/domain/tst_runs.qml` under another card.

`tests/ui/components/tst_run_badge.qml` (tier: tests/ui/components):

- `test_running`: glyph ⟳ is shown, and `pulsing` is true while visible.
- `test_running_hidden`: the badge is set to `visible: false` (or `active: false`), so `pulsing` is false.
- `test_parked`: glyph ⏸, and `pulsing` is false.
- `test_escalated`: glyph ‼, and the tint equals the theme's `urgent`.
- `test_dead`: glyph ✖.
- `test_cancelled`: glyph ⊘.
- `test_done`: glyph ✔.
- `test_unknown_state_hidden`: the badge is invisible for `""`, `"none"` and `"bogus"`.
- `test_phase_text`: the phase is shown beside the glyph.
- `test_parent_counts`: counts `{running:2, parked:1, escalated:0, done:0}` render as `⟳ 2 ⏸ 1`; all-zero counts hide the badge.
- `test_no_forbidden_colours`: no state's tint equals `#9b72cf` or `#d9534f`.

`tests/ui/components/tst_run_rollup_bar.qml` (tier: tests/ui/components):

- `test_segments`: each non-zero count shows a segment with the correct glyph and number, and zero counts are not visible.
- `test_pending_segment`: shows `N pending`.
- `test_escalated_urgent`: the escalated segment is tinted with `urgent`.
- `test_empty_hidden`: the bar is invisible for a `null` rollup and for `total: 0`.
- `test_partial_rollup`: missing fields cause no console error.

`tests/architecture/` (tier: architecture): no new test. The existing layer, duplicate and glyph tests must pass unchanged with the new files in place.

---

# RunBadge and RunRollupBar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two props-only QML components, `RunBadge` (an am run state as a glyph in a Badge ring, with optional phase text or parent counts) and `RunRollupBar` (a milestone/story's run rollup as caption segments). The running badge pulses by reusing the StatusPips pulse, which is first extracted into a shared `Pulse` component.

**Architecture:** The StatusPips `SequentialAnimation` moves, unchanged in timing, into `ui/components/Pulse.qml`. That is a SequentialAnimation root exposing `level` (1 at rest, fading to 0.3 and back while running, reset to 1 when it stops). StatusPips binds `pulseOpacity` to it, and RunBadge binds its `opacity` to its own `Pulse` instance, so the animation is defined once. `RunBadge` derives from `Badge`, which gives it the pill ring, the caption text, `theme`/`palette` and the fallback `T.Theme`, so no `radius: height / 2` is added. The glyph table and the count reading live once in `ui/components/runGlyphs.js` (`.pragma library`), which both new components import, so the glyphs are never written twice.

**Tech Stack:** QML (Qt 6 QtQuick), QtTest via `qmltestrunner`, pytest architecture tests, run by `bash ./tests/run.sh`.

**Spec:** `docs/superpowers/specs/task-4-1-runbadge-and-80cb429b-design.md` (prepended verbatim above). The orchestrator's summary of the spec reached the planner truncated at 2000 characters. This plan was written from the full spec file on disk, not from that summary.

**Worktree / branch:** `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-4-1-runbadge-and-80cb429b` on `mon/task-4-1-runbadge-and-80cb429b`. Run every command from that directory. The plan relies only on what already exists on this branch: `ui/components/Badge.qml`, `StatusPips.qml`, `ThemedText.qml`, `ui/theme/Theme.qml`, `tests/helpers/find.js`, `tests/run.sh`. It does not depend on PhaseTimeline, RunIndicator or any 4.x sibling code.

## Global Constraints

- Props only: no file added or changed here imports `core/stores`. Allowed imports are `QtQuick`, `qs.Commons`, `"../theme" as T`, and sibling files in `ui/components`.
- Never call `Board.statusColor` and never write `#9b72cf` or `#d9534f` in the new components.
- Escalated is tinted `palette.urgent`. `done` and `cancelled` use `palette.dim`. `running`, `parked`, `dead` and the counts form use `palette.foreground`.
- Glyphs are exactly: running `⟳`, parked `⏸`, escalated `‼`, dead `✖`, cancelled `⊘`, done `✔`. No private-use code points.
- No new `radius: height / 2`, `bordered: true`, `font.family:`, `Qt.rgba(0, 0, 0, 0.55)` or `CursorSurface {`. `tests/architecture/` is unchanged and gets no new allowlist entry.
- One animation: the only `SequentialAnimation`/`NumberAnimation` is in `Pulse.qml`. StatusPips' observable behaviour and `tests/ui/components/tst_status_pips.qml` stay unchanged.
- objectNames: `runBadge` (RunBadge root) and `runBadgeText` (its text); `runRollupBar` (bar root); `runRollupRunning`, `runRollupParked`, `runRollupEscalated`, `runRollupDone` and `runRollupPending` (segments).
- Component tests live in `tests/ui/components/tst_<component>.qml` (one per `ui/components` file), in the `tst_status_pips.qml` style: `when: windowShown`, `createTemporaryObject`, `H.find`.
- Verification: `bash ./tests/run.sh` (it fails on TypeError, ReferenceError, "non-existent", "Unable to assign", "anchors on an item" and "is not a function" in any QML test's output).

## Review Focus

- A theme that is null or torn down during destruction. Expect a fallback to the component's own `T.Theme` with no TypeError. Pinned in Task 2 `test_escalated` (no theme passed, tint equals `badge.palette.urgent`) and Task 3 `test_escalated_urgent` (no theme passed).
- An ancestor hidden, not the badge itself (a board card inside a hidden screen). Expect the pulse to stop and opacity to return to 1. Pinned in Task 2 `test_running_hidden` (host Item hidden, like `tst_status_pips.qml`).
- A state that leaves `running` while still visible (the run parks). Expect the pulse to stop and opacity to return to 1. Pinned in Task 2 `test_running_hidden`.
- Garbage count values: negative numbers, strings, a non-object `counts`/`rollup`. Expect them treated as 0, with no console error. Pinned in Task 2 `test_parent_counts` and Task 3 `test_partial_rollup`.
- `counts` set together with `state: "running"` and a `phase`. Expect counts to win, the phase to be ignored, and no pulse (the counts form has no single running ring). Pinned in Task 2 `test_parent_counts`.

Design decision recorded here for the reviewer: the spec lists `core/domain/*.js` as the optional script import, but the glyph table is presentation, and `core/domain/runs.js` belongs to another card and would pull a domain-tier test into this card. So the table goes in a sibling `ui/components/runGlyphs.js`. `test_layers.py` applies the same no-`core/stores` rule to `.js` under `ui/components`, and `.pragma library` passes it. `test_icon_glyphs.py` scans only `.qml` and only private-use code points. Both new components' tests pin every glyph, so the table needs no test of its own.

---

### Task 1: Extract the StatusPips pulse into a shared `Pulse`

**Files:**
- Create: `ui/components/Pulse.qml`
- Modify: `ui/components/StatusPips.qml:32-48` (the `pulsing` / `pulseOpacity` properties and the `SequentialAnimation` block)
- Modify: `docs/architecture.md:99-101` (Shared components list)
- Test: `tests/ui/components/tst_pulse.qml` (new); `tests/ui/components/tst_status_pips.qml` (unchanged, must still pass)

**Interfaces:**
- Consumes: nothing new.
- Produces: QML type `Pulse` in `ui/components` (root `SequentialAnimation`). Its API is `running: bool` (set by the owner, the inherited Animation property) and `level: real` (1 at rest, between 0.3 and 1 while running, reset to 1 when `running` becomes false). Used unqualified as `Pulse { id: pulse; running: <expr> }` from any file in `ui/components`.

- [ ] **Step 1: Write the failing test**

Create `tests/ui/components/tst_pulse.qml`:

```qml
// tests/ui/components/tst_pulse.qml
// ui/components/Pulse.qml: the one fade the panel animates with. `level` rests
// at 1, swings between 0.3 and 1 while running, and is put back to 1 the
// moment it stops, so nothing driven by it is ever left faded.
import QtQuick
import QtTest
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "Pulse"
  when: windowShown
  visible: true
  width: 200; height: 100

  Component { id: pulseC; UI.Pulse {} }

  function test_level_rests_at_one_until_the_owner_starts_it() {
    var pulse = createTemporaryObject(pulseC, tc)
    compare(pulse.running, false, "nothing runs unless the owner says so")
    compare(pulse.level, 1)
    compare(pulse.loops, -1, "loops forever (Animation.Infinite reads -1; the enum constant does not compare equal in qmltestrunner)")
  }

  function test_level_fades_while_running_and_is_put_back_when_it_stops() {
    var pulse = createTemporaryObject(pulseC, tc)
    pulse.running = true
    wait(120)
    verify(pulse.level < 1, "it fades")
    verify(pulse.level >= 0.3, "never below 0.3")
    pulse.running = false
    wait(30)
    compare(pulse.level, 1, "a stopped pulse leaves nothing faded")
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ./tests/run.sh tst_pulse`
Expected: FAIL. The `== tests/ui/components/tst_pulse.qml` block reports `Pulse is not a type` (or a `FAIL!` line from the Component failing to load), and the script exits non-zero.

- [ ] **Step 3: Write minimal implementation**

Create `ui/components/Pulse.qml`:

```qml
import QtQuick

// The one fade the panel animates with: `level` swings 1 -> 0.3 -> 1 for as
// long as the owner keeps `running` true, and is put back to 1 the moment it
// stops, so whatever follows it is never left faded. The owner decides when
// it runs (on screen AND something to show), so an idle view animates nothing.
// StatusPips' in-progress pips and RunBadge's running ring both follow it;
// write no second animation, bind to `level`.
SequentialAnimation {
  id: pulse

  property real level: 1

  loops: Animation.Infinite
  NumberAnimation { target: pulse; property: "level"; from: 1; to: 0.3; duration: 800; easing.type: Easing.InOutSine }
  NumberAnimation { target: pulse; property: "level"; from: 0.3; to: 1; duration: 800; easing.type: Easing.InOutSine }
  onRunningChanged: if (!running) pulse.level = 1
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ./tests/run.sh tst_pulse`
Expected: PASS. `Totals: 4 passed, 0 failed` (2 tests plus initTestCase/cleanupTestCase), no TypeError/ReferenceError lines, exit 0.

- [ ] **Step 5: Point StatusPips at the shared Pulse**

In `ui/components/StatusPips.qml`, replace lines 32-48:

```qml
  readonly property bool pulsing: pulse.running

  // What an in-progress pip's opacity follows. 1 whenever nothing is running,
  // so a stopped animation never leaves a pip faded.
  property real pulseOpacity: 1

  spacing: Style.space(4)
  visible: (pips.model || []).length > 0 || pips.more > 0

  SequentialAnimation {
    id: pulse
    running: pips.active && pips.visible && pips.hasInProgress
    loops: Animation.Infinite
    NumberAnimation { target: pips; property: "pulseOpacity"; from: 1; to: 0.3; duration: 800; easing.type: Easing.InOutSine }
    NumberAnimation { target: pips; property: "pulseOpacity"; from: 0.3; to: 1; duration: 800; easing.type: Easing.InOutSine }
    onRunningChanged: if (!running) pips.pulseOpacity = 1
  }
```

with:

```qml
  readonly property bool pulsing: pulse.running

  // What an in-progress pip's opacity follows: the shared Pulse's level, which
  // is 1 whenever nothing is running, so a stopped animation never leaves a
  // pip faded.
  readonly property real pulseOpacity: pulse.level

  spacing: Style.space(4)
  visible: (pips.model || []).length > 0 || pips.more > 0

  Pulse {
    id: pulse
    running: pips.active && pips.visible && pips.hasInProgress
  }
```

(`pulseOpacity` had no writer other than the removed animation; `grep -rn pulseOpacity ui core` shows only StatusPips.qml.)

- [ ] **Step 6: Run the StatusPips and Pulse tests to verify StatusPips is unchanged**

Run: `bash ./tests/run.sh tst_status_pips && bash ./tests/run.sh tst_pulse`
Expected: both PASS, with `tst_status_pips.qml` showing `Totals: 8 passed, 0 failed` (6 tests plus init/cleanup), no console errors, exit 0. The pytest run at the head of each invocation also passes, including `tests/architecture`.

- [ ] **Step 7: Name Pulse in the Shared components list**

In `docs/architecture.md`, replace:

```
visible AND holds an in-progress pip, so an idle graph animates nothing),
`Sidebar`, and the views
```

with:

```
visible AND holds an in-progress pip, so an idle graph animates nothing),
`Pulse` (that one fade, shared: `level` swings 1 -> 0.3 -> 1 while the owner
keeps `running` true and is back at 1 the moment it stops; `StatusPips` and
`RunBadge` bind their opacity to it instead of declaring a second animation),
`Sidebar`, and the views
```

- [ ] **Step 8: Commit**

```bash
git add ui/components/Pulse.qml ui/components/StatusPips.qml tests/ui/components/tst_pulse.qml docs/architecture.md
git commit -m "refactor: extract the StatusPips pulse into a shared Pulse component"
```

---

### Task 2: RunBadge

**Files:**
- Create: `ui/components/runGlyphs.js`
- Create: `ui/components/RunBadge.qml`
- Modify: `docs/architecture.md` (Shared components list, the `Pulse` entry added in Task 1)
- Test: `tests/ui/components/tst_run_badge.qml` (new)

**Interfaces:**
- Consumes: `Pulse` from Task 1 (`running`, `level`). `Badge` (existing: `theme`, `palette`, `text`, `tint`, `textObjectName`; radius/fill/ThemedText caption and the fallback `T.Theme { id: badgeTheme }`).
- Produces:
  - `ui/components/runGlyphs.js` (`.pragma library`):
    - `glyphOf(state: string) -> string`: the glyph, or `""` for anything unknown.
    - `countOf(counts: any, key: string) -> number`: a positive number or 0; non-objects, missing fields, negatives and non-numbers give 0.
    - `countsText(counts: any) -> string`: non-zero running/parked/escalated/done as `"glyph N"` joined by `" "`, or `""`.
  - QML type `RunBadge` (root `Badge`, `objectName: "runBadge"`, text objectName `runBadgeText`). Props: `theme: var`, `state: string` (Item's own), `phase: string = ""`, `counts: var = null`, `active: bool = true`. Readonly: `glyph: string`, `hasCounts: bool`, `pulsing: bool`. Inherited readable: `tint: color`, `palette: var`, `text: string`.

- [ ] **Step 1: Write the failing test**

Create `tests/ui/components/tst_run_badge.qml`:

```qml
// tests/ui/components/tst_run_badge.qml
// ui/components/RunBadge.qml: an am run's state as a glyph inside a Badge ring
// (never colour alone), with a subtask's phase beside it or a parent's
// non-zero counts instead of it. Escalated reads in `urgent`; only a visible,
// active running badge pulses, through the shared Pulse.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "RunBadge"
  when: windowShown
  visible: true
  width: 400; height: 200

  // Three distinct tokens, so a tint can only match the one it is meant to.
  T.Theme { id: testTheme; foreground: "#eeeeee"; dim: "#777777"; urgent: "#ff3300" }

  Component { id: badgeC; UI.RunBadge {} }
  Component { id: hostC; Item { width: 200; height: 60 } }

  function make(props) {
    var badge = createTemporaryObject(badgeC, tc, props)
    wait(30)
    return badge
  }

  function textOf(badge) { return H.find(badge, "runBadgeText").text }

  function test_running() {
    var badge = make({ theme: testTheme, state: "running" })
    compare(badge.objectName, "runBadge")
    compare(badge.glyph, "⟳")
    compare(textOf(badge), "⟳")
    compare(badge.visible, true)
    verify(badge.radius > 0, "the glyph sits in the Badge ring")
    verify(Qt.colorEqual(badge.tint, testTheme.foreground))
    compare(badge.pulsing, true, "a visible running badge pulses")
    wait(120)
    verify(badge.opacity < 1, "the ring fades")
  }

  function test_running_hidden() {
    var off = make({ theme: testTheme, state: "running", active: false })
    compare(off.pulsing, false, "the owner can switch the pulse off")
    compare(off.opacity, 1)
    off.active = true
    wait(30)
    compare(off.pulsing, true)

    var host = createTemporaryObject(hostC, tc)
    var badge = badgeC.createObject(host, { theme: testTheme, state: "running" })
    wait(30)
    compare(badge.pulsing, true)
    wait(120)
    verify(badge.opacity < 1)
    host.visible = false
    wait(60)
    compare(badge.pulsing, false, "an invisible ancestor runs nothing")
    compare(badge.opacity, 1, "and leaves the ring unfaded")
    host.visible = true
    wait(30)
    compare(badge.pulsing, true, "showing it again restarts the pulse")

    wait(120)
    badge.state = "parked"
    wait(30)
    compare(badge.pulsing, false, "leaving running stops the pulse")
    compare(badge.opacity, 1)
    badge.destroy()
  }

  function test_parked() {
    var badge = make({ theme: testTheme, state: "parked" })
    compare(badge.glyph, "⏸")
    compare(textOf(badge), "⏸")
    compare(badge.pulsing, false)
    compare(badge.opacity, 1)
    verify(Qt.colorEqual(badge.tint, testTheme.foreground))
  }

  function test_escalated() {
    var badge = make({ theme: testTheme, state: "escalated" })
    compare(badge.glyph, "‼")
    compare(textOf(badge), "‼")
    compare(badge.pulsing, false)
    verify(Qt.colorEqual(badge.tint, testTheme.urgent), "escalated reads in urgent")
    verify(Qt.colorEqual(H.find(badge, "runBadgeText").color, testTheme.urgent))

    // No theme handed down: the badge's own fallback Theme, still urgent.
    var own = make({ state: "escalated" })
    verify(own.palette, "falls back to its own Theme")
    verify(Qt.colorEqual(own.tint, own.palette.urgent))
  }

  function test_dead() {
    var badge = make({ theme: testTheme, state: "dead" })
    compare(badge.glyph, "✖")
    compare(textOf(badge), "✖")
    compare(badge.pulsing, false)
    verify(Qt.colorEqual(badge.tint, testTheme.foreground))
  }

  function test_cancelled() {
    var badge = make({ theme: testTheme, state: "cancelled" })
    compare(badge.glyph, "⊘")
    compare(textOf(badge), "⊘")
    verify(Qt.colorEqual(badge.tint, testTheme.dim))
  }

  function test_done() {
    var badge = make({ theme: testTheme, state: "done" })
    compare(badge.glyph, "✔")
    compare(textOf(badge), "✔")
    verify(Qt.colorEqual(badge.tint, testTheme.dim))
  }

  function test_unknown_state_hidden() {
    var names = ["", "none", "bogus", "constructor"]
    for (var i = 0; i < names.length; i++) {
      var badge = make({ theme: testTheme, state: names[i] })
      compare(badge.glyph, "", names[i])
      compare(badge.visible, false, "no badge for '" + names[i] + "'")
      compare(badge.pulsing, false)
    }
  }

  function test_phase_text() {
    var badge = make({ theme: testTheme, state: "running", phase: "implement" })
    compare(textOf(badge), "⟳ implement")
    badge.phase = ""
    wait(30)
    compare(textOf(badge), "⟳", "no phase, just the glyph")
    var parked = make({ theme: testTheme, state: "parked", phase: "plan" })
    compare(textOf(parked), "⏸ plan")
  }

  function test_parent_counts() {
    var badge = make({ theme: testTheme, counts: { running: 2, parked: 1, escalated: 0, done: 0 } })
    compare(textOf(badge), "⟳ 2 ⏸ 1")
    compare(badge.visible, true)
    verify(Qt.colorEqual(badge.tint, testTheme.foreground), "the counts form is neutral")

    badge.counts = { running: 0, parked: 0, escalated: 3, done: 4 }
    wait(30)
    compare(textOf(badge), "‼ 3 ✔ 4")

    // Counts win over the single state: no phase, and no single running ring to pulse.
    var both = make({ theme: testTheme, state: "running", phase: "plan", counts: { running: 1 } })
    compare(textOf(both), "⟳ 1")
    compare(both.pulsing, false)

    // Missing and garbage entries count as 0.
    var odd = make({ theme: testTheme, counts: { running: -1, parked: "x", done: 2 } })
    compare(textOf(odd), "✔ 2")

    var zero = make({ theme: testTheme, counts: { running: 0, parked: 0, escalated: 0, done: 0 } })
    compare(zero.visible, false, "all-zero counts show nothing")
    var empty = make({ theme: testTheme, counts: {} })
    compare(empty.visible, false)
  }

  function test_no_forbidden_colours() {
    var states = ["running", "parked", "escalated", "dead", "cancelled", "done"]
    for (var i = 0; i < states.length; i++) {
      var badge = make({ state: states[i] })
      verify(!Qt.colorEqual(badge.tint, "#9b72cf"), states[i] + " is not the merged colour")
      verify(!Qt.colorEqual(badge.tint, "#d9534f"), states[i] + " is not the canceled colour")
    }
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ./tests/run.sh tst_run_badge`
Expected: FAIL. The `== tests/ui/components/tst_run_badge.qml` block reports `RunBadge is not a type`, and the script exits non-zero.

- [ ] **Step 3: Write the shared glyph table**

Create `ui/components/runGlyphs.js`:

```js
.pragma library

// The one glyph per am run state, shared by RunBadge and RunRollupBar so a
// state reads the same everywhere. Plain BMP characters, never a Nerd Font
// code point. State is never shown by colour alone: every state has its glyph.
var GLYPHS = {
  running: "⟳",
  parked: "⏸",
  escalated: "‼",
  dead: "✖",
  cancelled: "⊘",
  done: "✔"
}

// The order a parent's counts are read in.
var COUNT_ORDER = ["running", "parked", "escalated", "done"]

// The glyph for a run state; "" for anything else ("", "none", "bogus", and
// inherited names such as "constructor").
function glyphOf(state) {
  return typeof state === "string" && Object.prototype.hasOwnProperty.call(GLYPHS, state) ? GLYPHS[state] : ""
}

// One count of a rollup-shaped object. A missing field, a non-object, a
// negative or a non-number is 0.
function countOf(counts, key) {
  if (counts === null || typeof counts !== "object") return 0
  var n = Number(counts[key])
  return n > 0 ? n : 0
}

// A parent's non-zero counts as "glyph N" pairs, e.g. "⟳ 2 ⏸ 1"; "" when none.
function countsText(counts) {
  var parts = []
  for (var i = 0; i < COUNT_ORDER.length; i++) {
    var n = countOf(counts, COUNT_ORDER[i])
    if (n > 0) parts.push(GLYPHS[COUNT_ORDER[i]] + " " + n)
  }
  return parts.join(" ")
}
```

- [ ] **Step 4: Write RunBadge**

Create `ui/components/RunBadge.qml`:

```qml
import QtQuick
import qs.Commons
import "runGlyphs.js" as RunGlyphs

// An am run's state as a glyph inside a ring: the Badge pill, so the ring,
// the caption text, `theme`/`palette` and the fallback Theme are Badge's own.
// Presentation only: `state` (Item's own string property, used as plain text)
// is running | parked | escalated | dead | cancelled | done, and anything else
// shows nothing. A subtask passes its `phase`; a parent passes `counts`
// ({running, parked, escalated, done}), which replace the single glyph.
//
// Escalated reads in `urgent`; never Board.statusColor. A running badge fades
// with the shared Pulse, and only while it is visible and `active`.
Badge {
  id: runBadge
  objectName: "runBadge"
  textObjectName: "runBadgeText"

  property string phase: ""
  // Rollup-shaped counts for a milestone/story, or null for a single run state.
  property var counts: null
  // The owner's own "this is on screen" verdict, ANDed into the pulse.
  property bool active: true

  readonly property bool hasCounts: runBadge.counts !== null && typeof runBadge.counts === "object"
  readonly property string glyph: RunGlyphs.glyphOf(runBadge.state)
  readonly property bool pulsing: pulse.running

  text: runBadge.hasCounts ? RunGlyphs.countsText(runBadge.counts)
    : runBadge.glyph === "" ? ""
    : runBadge.phase !== "" ? runBadge.glyph + " " + runBadge.phase
    : runBadge.glyph
  tint: !runBadge.palette ? Color.foreground
    : runBadge.hasCounts ? runBadge.palette.foreground
    : runBadge.state === "escalated" ? runBadge.palette.urgent
    : (runBadge.state === "done" || runBadge.state === "cancelled") ? runBadge.palette.dim
    : runBadge.palette.foreground
  visible: runBadge.text !== ""
  opacity: pulse.level

  Pulse {
    id: pulse
    running: runBadge.active && runBadge.visible && !runBadge.hasCounts && runBadge.state === "running"
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash ./tests/run.sh tst_run_badge`
Expected: PASS. `Totals: 13 passed, 0 failed` (11 tests plus init/cleanup), no TypeError/ReferenceError/"Unable to assign" lines, exit 0. The leading pytest run (including `tests/architecture/test_layers.py` and `test_icon_glyphs.py`) passes unchanged.

- [ ] **Step 6: Name RunBadge in the Shared components list**

In `docs/architecture.md`, replace:

```
`RunBadge` bind their opacity to it instead of declaring a second animation),
`Sidebar`, and the views
```

with:

```
`RunBadge` bind their opacity to it instead of declaring a second animation),
`RunBadge` (an am run state as a glyph in a `Badge` ring -- running ⟳, parked
⏸, escalated ‼, dead ✖, cancelled ⊘, done ✔, from `runGlyphs.js` -- with a
subtask's phase beside it, or a parent's non-zero counts such as `⟳ 2 ⏸ 1`
instead; escalated in `urgent`, never `Board.statusColor`; it pulses only
while running, visible and `active`),
`Sidebar`, and the views
```

- [ ] **Step 7: Commit**

```bash
git add ui/components/runGlyphs.js ui/components/RunBadge.qml tests/ui/components/tst_run_badge.qml docs/architecture.md
git commit -m "feat: add RunBadge, an am run state as a glyph in a Badge ring"
```

---

### Task 3: RunRollupBar, then the full suite

**Files:**
- Create: `ui/components/RunRollupBar.qml`
- Modify: `docs/architecture.md` (Shared components list, after the `RunBadge` entry from Task 2)
- Test: `tests/ui/components/tst_run_rollup_bar.qml` (new)

**Interfaces:**
- Consumes: `ui/components/runGlyphs.js` from Task 2 (`glyphOf(state) -> string`, `countOf(counts, key) -> number`). `ThemedText` (existing: `theme`, `variant`, `color`, `text`).
- Produces: QML type `RunRollupBar` (root `Row`, `objectName: "runRollupBar"`). Props: `theme: var = null`, `rollup: var = null`. Readonly: `palette: var`. Segment children (ThemedText) have objectNames `runRollupRunning`, `runRollupParked`, `runRollupEscalated`, `runRollupDone` and `runRollupPending`, each with `text`, `color`, `visible` and a readonly `amount: int`.

- [ ] **Step 1: Write the failing test**

Create `tests/ui/components/tst_run_rollup_bar.qml`:

```qml
// tests/ui/components/tst_run_rollup_bar.qml
// ui/components/RunRollupBar.qml: a milestone/story's run rollup under its
// title, one caption segment per non-zero count (the RunBadge glyphs, then
// "N pending"), escalated in `urgent`, and nothing at all for an empty rollup.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "RunRollupBar"
  when: windowShown
  visible: true
  width: 400; height: 200

  T.Theme { id: testTheme; foreground: "#eeeeee"; dim: "#777777"; urgent: "#ff3300" }

  Component { id: barC; UI.RunRollupBar {} }

  function make(rollup, theme) {
    var bar = createTemporaryObject(barC, tc, { theme: theme || null, rollup: rollup })
    wait(30)
    return bar
  }

  function seg(bar, name) { return H.find(bar, name) }

  function test_segments() {
    var bar = make({ running: 2, parked: 1, escalated: 0, done: 3, pending: 0, total: 6 }, testTheme)
    compare(bar.objectName, "runRollupBar")
    compare(bar.visible, true)
    var running = seg(bar, "runRollupRunning")
    var parked = seg(bar, "runRollupParked")
    var done = seg(bar, "runRollupDone")
    verify(running && parked && done)
    compare(running.visible, true)
    compare(running.text, "⟳ 2")
    compare(parked.visible, true)
    compare(parked.text, "⏸ 1")
    compare(done.visible, true)
    compare(done.text, "✔ 3")
    compare(seg(bar, "runRollupEscalated").visible, false, "a zero count is not shown")
    compare(seg(bar, "runRollupPending").visible, false)
    verify(running.x < parked.x && parked.x < done.x, "running, parked, ..., done in that order")
  }

  function test_pending_segment() {
    var bar = make({ running: 1, pending: 4, total: 5 }, testTheme)
    var pending = seg(bar, "runRollupPending")
    compare(pending.visible, true)
    compare(pending.text, "4 pending")
    verify(seg(bar, "runRollupRunning").x < pending.x, "pending comes last")
  }

  function test_escalated_urgent() {
    var bar = make({ escalated: 2, total: 2 }, testTheme)
    var escalated = seg(bar, "runRollupEscalated")
    compare(escalated.visible, true)
    compare(escalated.text, "‼ 2")
    verify(Qt.colorEqual(escalated.color, testTheme.urgent))

    // No theme handed down: the bar's own fallback Theme, still urgent.
    var own = make({ escalated: 1, total: 1 })
    verify(own.palette, "falls back to its own Theme")
    var e = seg(own, "runRollupEscalated")
    verify(Qt.colorEqual(e.color, own.palette.urgent))
    var names = ["runRollupRunning", "runRollupParked", "runRollupEscalated", "runRollupDone", "runRollupPending"]
    for (var i = 0; i < names.length; i++) {
      var c = seg(own, names[i]).color
      verify(!Qt.colorEqual(c, "#9b72cf") && !Qt.colorEqual(c, "#d9534f"), names[i])
    }
  }

  function test_empty_hidden() {
    compare(make(null).visible, false, "no rollup, no bar")
    compare(make({ running: 0, parked: 0, escalated: 0, done: 0, pending: 0, total: 0 }).visible, false)
    var bar = make({ running: 1, total: 1 })
    compare(bar.visible, true)
    bar.rollup = null
    wait(30)
    compare(bar.visible, false, "clearing the rollup hides it")
  }

  function test_partial_rollup() {
    var bar = make({ running: 1, total: 1 }, testTheme)
    compare(bar.visible, true)
    compare(seg(bar, "runRollupRunning").text, "⟳ 1")
    compare(seg(bar, "runRollupParked").visible, false, "a missing field is 0")
    compare(seg(bar, "runRollupEscalated").visible, false)
    compare(seg(bar, "runRollupDone").visible, false)
    compare(seg(bar, "runRollupPending").visible, false)
    compare(make({}).visible, false, "no total: nothing to show")
    compare(make("garbage").visible, false, "a non-object is empty")
    compare(make({ running: -2, parked: "x", total: 3 }, testTheme).visible, true)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ./tests/run.sh tst_run_rollup_bar`
Expected: FAIL. The `== tests/ui/components/tst_run_rollup_bar.qml` block reports `RunRollupBar is not a type`, and the script exits non-zero.

- [ ] **Step 3: Write minimal implementation**

Create `ui/components/RunRollupBar.qml`:

```qml
import QtQuick
import qs.Commons
import "runGlyphs.js" as RunGlyphs
import "../theme" as T

// A milestone's or story's am run rollup, under its title: one caption
// segment per non-zero count, in the RunBadge glyphs (running, parked,
// escalated, done) and then "N pending". Presentation only: `rollup` is
// {running, parked, escalated, done, pending, total} or null, computed
// elsewhere (runs.js `rollup`); a missing field is 0, and a null or empty
// rollup hides the whole bar. Escalated reads in `urgent`.
Row {
  id: bar
  objectName: "runRollupBar"

  // The owner's Theme, or none: `palette` then falls back to the bar's own.
  // Tearing a view down nulls it while the bindings still run once, so every
  // read of `palette` is guarded.
  property var theme: null
  property var rollup: null

  readonly property var palette: bar.theme || barTheme

  spacing: Style.space(8)
  visible: RunGlyphs.countOf(bar.rollup, "total") > 0

  Repeater {
    model: [
      { key: "running", name: "runRollupRunning" },
      { key: "parked", name: "runRollupParked" },
      { key: "escalated", name: "runRollupEscalated" },
      { key: "done", name: "runRollupDone" },
      { key: "pending", name: "runRollupPending" }
    ]

    delegate: ThemedText {
      id: segment
      required property var modelData

      readonly property int amount: RunGlyphs.countOf(bar.rollup, segment.modelData.key)

      objectName: segment.modelData.name
      variant: "caption"
      theme: bar.palette
      visible: segment.amount > 0
      text: segment.modelData.key === "pending"
        ? segment.amount + " pending"
        : RunGlyphs.glyphOf(segment.modelData.key) + " " + segment.amount
      color: !bar.palette ? Color.foreground
        : segment.modelData.key === "escalated" ? bar.palette.urgent
        : (segment.modelData.key === "running" || segment.modelData.key === "parked") ? bar.palette.foreground
        : bar.palette.dim
    }
  }

  T.Theme { id: barTheme }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ./tests/run.sh tst_run_rollup_bar`
Expected: PASS. `Totals: 7 passed, 0 failed` (5 tests plus init/cleanup), no TypeError/ReferenceError/"Unable to assign" lines, exit 0.

- [ ] **Step 5: Name RunRollupBar in the Shared components list**

In `docs/architecture.md`, replace:

```
while running, visible and `active`),
`Sidebar`, and the views
```

with:

```
while running, visible and `active`),
`RunRollupBar` (a milestone's or story's run rollup under its title: one
caption segment per non-zero count in the same glyphs, then `N pending`;
escalated in `urgent`; hidden when the rollup is null or its total is 0),
`Sidebar`, and the views
```

- [ ] **Step 6: Run the full verification suite**

Run: `bash ./tests/run.sh`
Expected: pytest passes (with `tests/architecture/test_layers.py` and `test_icon_glyphs.py` unchanged and green), then every `tst_*.qml` prints `Totals: N passed, 0 failed`, with no TypeError, ReferenceError, "non-existent", "Unable to assign", "anchors on an item" or "is not a function" lines, and exit code 0. Check that `tst_status_pips.qml`, `tst_badge.qml`, `tst_pulse.qml`, `tst_run_badge.qml` and `tst_run_rollup_bar.qml` all appear and pass.

- [ ] **Step 7: Commit**

```bash
git add ui/components/RunRollupBar.qml tests/ui/components/tst_run_rollup_bar.qml docs/architecture.md
git commit -m "feat: add RunRollupBar, a run rollup as caption segments"
```
