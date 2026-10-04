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
