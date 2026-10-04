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
