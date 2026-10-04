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
