# Runs screen: new run row, level badges and manual Close

Preview (private, illustrative): https://claude.ai/artifact/CbTNTLuKF5n2RCNwimt93m

## Problem

Escalated, paused and dead runs pile up on the Runs screen. `am cancel` refuses them (`NotRunningError` / `DeadRunError`), yet the row enables Cancel and shows "The run is not running". Nothing in the plugin calls `am reset`, the command that closes a run nobody drives. The row also cannot tell a milestone run from a story or subtask run.

## Goal

1. A new row layout with a level badge (MILESTONE / STORY / SUBTASK) and a state badge.
2. A **Close** action (`am reset`) for parked, escalated and dead runs, behind a confirm dialog.
3. Buttons that never show disabled: each state offers only what works.

## Non-goals and constraints

- **The top-level filters stay exactly as they are.** That means the project chip row (`runProjectChips`), the status chips (Needs attention / Live / Parked / Finished / All, with the store's `runFilterCounts`), and the Finished state row and age row. The "Needs attention / Live / Parked / Finished" bar in the preview is only a mock of the existing status chips. Do not add, remove, reorder or restyle any of them, and do not change their store properties or tests.
- Group headers (`RunGroupHeader`), "Show older", `projectErrorC` and cursor behaviour are unchanged.
- No bulk selection, no checkboxes, no "Close N selected".
- `RunDetailScreen` is out of scope. Reusing `RunControls` there must not regress; see "RunControls" below.
- Respect the layering in `docs/architecture.md`: `core/domain` is pure JS with no QML; `ui/screens/**` and `ui/components/**` import no `core/stores` and take `app` or props; `core/backend/**` is Python stdlib only (`tests/architecture/test_layers.py`).

## Row layout (`RunRow` in `ui/screens/RunsScreen.qml`)

```
 [id8] Title  [LEVEL] [STATE]                         x/y · phase · age
 why: escalation reason (escalated only, flush left, warn colour)
                                         [Close] [Relaunch]
```

- **Removed:** the state glyph (`RunGlyphs.glyphOf`), the caption id from `Runs.runSubtitle`, the separate `stateText` caption, and the "Open project" `ActionButton`.
- **Id:** the first 8 characters of the run's milestone UUID, shown raw, with no ellipsis. (Open question: the user may want the 12-character last group instead; see below.)
- **Meta (right-aligned):** `done/total · phase · age`, from `Runs.runProgress`, `Runs.currentPhase`, `Runs.runAgeText`. A parked run with no phase reads `0/11 · parked · 5d`; a dead run reads `dead - lease lost <age>` in the same slot (keep `stateText` for that text only).
- **Reason line:** `Runs.escalationReason`, escalated only, flush left (no indent), warn colour.
- **Buttons** still show only while the row has the cursor (`row.hasCursor`), as today.

### Level badge

New pure helper in `core/domain/runs.js`:

```js
// "subtask" | "story" | "milestone"
function runLevel(run)
```

- `workflow === "task"` (trimmed) gives `subtask`.
- Otherwise a non-empty `story_id` gives `story`.
- Otherwise `milestone`. Garbage input gives `milestone`; it never throws.

New component `ui/components/RunLevelBadge.qml`, text from the level in upper case. Same 4px-radius rectangle for all three, differing only in weight and tint:

| Level | Style | Light | Dark |
|---|---|---|---|
| MILESTONE | 2px border, tinted fill | `#2b3f9e` | `#aab8ff` |
| STORY | lighter tint, thinner border | `#4a67d6` | `#8196ee` |
| SUBTASK | 1px outline, no tint | `#7f93d9` | `#5d70b8` |

Add the three colours as theme tokens (`levelMilestone`, `levelStory`, `levelSubtask`) to `ui/theme`, with a dark variant. Amber is not used for levels.

### State badge

New component `ui/components/RunStateBadge.qml`, shown only for two states: RUNNING (accent-green tint) and ESCALATED (warn tint). Parked and dead runs have no state badge; the meta text says it. No spinner and no ⚠/⏸/⟳ glyphs. It sits right of the level badge. It may be built on `Badge.qml`; the level badge may not (that one is a pill, this is a rectangle).

## Buttons

All buttons are outlined with a 14% tint fill; none is solid. Labels are exact: `Cancel`, `Pause`, `Close`, `Relaunch`, `Resume`. No "Cancel run" and no ellipsis.

| Run state | Buttons, left to right |
|---|---|
| running | Cancel (red), Pause (amber) |
| parked | Close (orange), Resume (green) |
| escalated | Close (orange), Relaunch (green) |
| dead | Close (orange), Relaunch (green) |
| done / cancelled / unknown | none |

- **Resume appears only on a parked run.** Escalated and dead runs get Relaunch (a fresh run of the same work, today's `offersRelaunch` path) instead of Resume. There are no disabled buttons; a button that would be disabled is not rendered. This replaces the "reason line under disabled buttons" in `RunControls`.
- Colours: add `closeTone` (orange `#c4560a` light / `#ff9442` dark) and a `warn` tone to `ActionButton`'s `tone` values next to the existing `danger`; Resume and Relaunch use the accent tone.
- Cancel acts at once for a live run, as today (its typed "cancel" confirmation via `TypedConfirmDialog` is unchanged).

## Close (`am reset`)

### Backend: `core/backend/runs/run-control.py`

- `ACTIONS = ("pause", "resume", "cancel", "reset")`; update `USAGE` and the module docstring. `reset` takes no `--verify` / `--allow-no-verification` (same rule as pause and cancel), runs through `run_am` with the 60 s timeout, and prints am's envelope unchanged.
- Argv: `reset RUN --repo-dir REPO`.

### Domain: `core/domain/runs.js`

- `controls(run)` returns a fourth entry, `close`, a fresh `{enabled, reason}`: enabled for `dead`, `parked` and `escalated` (not in Integrate, as for cancel); disabled with a reason for `running` (`"A running run is cancelled, not closed"`), `done` (`_REASON_FINISHED`), `cancelled` (`"The run is already cancelled"`) and unknown.
- New helper `visibleActions(run)`: the ordered list of action names the row shows, per the table above. `RunControls` renders exactly that list, so "never show disabled" lives in one tested place.
- `_CONTROL_ERRORS` gains sentences for the errors `am reset` can return:
  - `RunIsLiveError` already exists, but its text mentions resume; give reset its own text via a per-action lookup or a second sentence ("Another am process is still driving this run. Pause it first.").
  - `NotResettableError`: "This run cannot be closed (it is finished or already cancelled)."

### Store: `core/stores/RunControlStore.qml`

- Accept `"reset"` in `control()`, `refusalOf()` and the `Unknown control` check; a reset is settled like pause/cancel when the run leaves the open states in the next snapshot. No pending "requested…" label other than `Close requested…`.
- `ControlFacts.pendingOf` documents the new value.
- No change to the cancel confirmation fields. Add a parallel `closeRunId` / `closeOpen` pair (with `closeAsk(runId)`, `closeCancel()`, `closeConfirm()`) that opens only when `refusalOf("reset", id)` is empty.

### Confirm dialog: `ui/components/CloseRunDialog.qml`

A `ModalCard` over a dimmed backdrop, no typed confirmation (Close is reversible by relaunching; nothing is deleted).

- Title: `Close "<run title>"?`
- Body: the run is recorded as cancelled; nothing is deleted and no branch is touched. If a card of this run is also open in another run, name that run id and say the card stays continuable there (from `am reset`'s `open_in` field in the reply; before the call, from `Runs` data if it already lists it, otherwise omit the sentence).
- Buttons: `Keep` (neutral) and `Close` (orange, `closeTone`). Escape and Keep dismiss.
- Mounted by `RunsScreen` next to the existing cancel dialog; the screen emits `closeRequested(runId)` the way it emits `cancelRequested`, and `Panel`/`App` wires it to the store, mirroring cancel.

### `RunsScreen.requestControl`

```qml
if (action === "cancel") screen.cancelRequested(id)
else if (action === "close") screen.closeRequested(id)
else screen.app.runControl.control(action, id)
```

## `RunControls.qml`

- Replace `resumable`, `pauseShown`, `resumeShown` and the `reasonText` logic with `Runs.visibleActions(run)`. Add Close and Relaunch buttons (`runControlClose`, `runControlRelaunch`); keep the existing `objectName`s for the rest.
- Relaunch emits `actionRequested("relaunch")`; the owner starts a fresh run (reuse the existing relaunch path that `offersRelaunch` feeds).
- `RunDetailScreen` also uses this component. Its buttons follow the same table. This is a behaviour change there (Resume disappears on escalated runs), so the detail screen's tests must be updated, but its layout is untouched.
- Drop the `reasonText` line; keep the caption "applies to the whole run", the waiting line and the control error line.

## Tests

- `tests/` QML + domain (`tst_runs_flow.qml`, `tst_runs_real_data.qml`, new `tst_run_level.qml` or similar):
  - `runLevel`: task, story, milestone, empty, garbage, `__proto__` ids.
  - `controls().close` for each state; `visibleActions` for each state, matching the table.
  - `controlError` for `NotResettableError` and the reset variant of `RunIsLiveError`.
  - Row: badges present per level and state; no glyph, no Open project; reason line flush left; Resume on parked only; no disabled button anywhere.
  - Close dialog: opens, Keep dismisses, Close calls `control("reset", id)` once, a refused reset keeps the dialog's error.
  - Filters untouched: the existing chip tests pass unmodified.
- Helper: new Python test for `run-control.py reset` (argv built, `--verify` rejected, envelope passthrough, Usage text).
- Architecture: `tests/architecture/test_layers.py` passes (new components import no store).
- `tests/run.sh` is green before and after.

## Notes

- `am events --escalations` is historical; it does not shrink after a reset. The Needs attention count comes from run state, so it drops.
- Closing is recorded as `canceled`, so the run moves from Needs attention to Finished; checkpoints are kept.
- Real data: omarchy-project-manager itself has 15 open runs (9 escalated, 4 stopped, 2 dead). They can be cleared from the new Close button once this ships; nothing has been reset yet.

## Open questions

1. Run id length: 8 characters (current) or the 12-character last UUID group? `am runs` does not return the latter per run, so it needs a store change.
2. Include `RunDetailScreen` in this change, or leave it on the old buttons? The shared `RunControls` makes leaving it out awkward; the spec above assumes it follows the new table.
