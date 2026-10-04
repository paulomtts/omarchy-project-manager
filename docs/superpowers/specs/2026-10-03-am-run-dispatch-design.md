# Dispatching am runs from the panel (S3) — design

Status: proposed. Depends on `2026-10-03-am-run-monitor-design.md` (S1) and
`2026-10-03-am-run-controls-design.md` (S2, for the verify store and the
run-control conventions).

## Problem

Starting implementation means leaving the panel, remembering the right
`am run … --branch-prefix … --verify …` incantation, and keeping a terminal open.
The user already looks at the card they want built; the panel should start the run.

## Goal

From a card (or the Runs screen) the user starts an `am` run at the level they
choose, sees exactly what it will do before it starts, and ends up on that run's
detail screen. The run keeps going if the panel closes.

## Non-goals

- No editing of the plan. The preview is `am run --dry-run`; to change the plan
  the user changes the board.
- No scheduling, queues or retries. One click starts one `am run`.
- No per-story dispatch: `am run` takes `--board`, `--milestone` or `--card`
  (one subtask). A story is dispatched through its milestone, or subtask by
  subtask.
- The plugin does not manage `am`'s own lifecycle (leases, claims, resume
  takeover): that is `am`'s, and S2 covers control.

## Dispatch levels

| entry card | command | preview |
|---|---|---|
| a root card (milestone) | `am run --milestone <id>` | `am run --milestone <id> --dry-run` |
| a subtask | `am run --card <id>` | none from `am` (dry-run covers milestone and board only): the dialog shows the card, its story, and its `blocked_by` status |
| Runs screen, "whole board" | `am run --board` | `am run --board --dry-run` |
| a story | not offered; the dialog offers its milestone and says so | |

`--board` is in `am run --help` but not in the README. Verify its plan payload
and what its `run_upsert` records as `milestone_id` when writing the plan; S1's
card mapping must still hold (see S4, item 5).

## Flow

```
 entry A: card detail     entry B: board key `d`     entry C: Runs screen
┌──────────────────┐     ┌──────────────────┐       ┌──────────────────┐
│ M3 Document runs │     │ ▌M3 Document …   │       │ Runs [▶ Start]   │
│ Runs: none yet   │     │  cursor on card  │       │                  │
│ [ ▶ Dispatch ]   │     │  press  d        │       │ pick target      │
└────────┬─────────┘     └────────┬─────────┘       └────────┬─────────┘
         └────────────────────────┼──────────────────────────┘
                                  ▼
         ┌─ Dispatch ──────────────────────────────────────────────┐
         │ Target   Milestone "Document milestone runs"            │
         │ Base     [ main ▾ ]         Prefix  [ m3 ]              │
         │ Verify   [ uv run pytest ] [+]   [ ] run without any    │
         │ Parallel [ 4 ] stories at once                          │
         │─────────────────────────────────────────────────────────│
         │ Preview  (am run --dry-run)                             │
         │   2 levels · 5 subtasks · 3 stories already done        │
         │   Integrate → m3-integrate                              │
         │ ⚠ This starts agents and spends tokens.                 │
         │                          [ Cancel ]  [ ▶ Start run ]    │
         └─────────────────────────────────────────────────────────┘
                                  │ Start
                                  ▼
   detached `am run` → run id found → Run detail (S1) for that run
```

- Preview re-runs (debounced 400 ms) whenever base, prefix, verify or parallelism
  changes. **Start is disabled until the latest preview succeeded.** A refusal
  (`ClaimedError`, dependency cycle, ambiguous or unknown milestone, missing
  verification) is shown inline, verbatim from `error.message`.
- Defaults: base = the repo's current default branch (`git symbolic-ref
  refs/remotes/origin/HEAD`, falling back to the current branch), because
  `am`'s own default is `master`, which is wrong for repos on `main`. Prefix =
  the milestone card's short stem (`m3`), editable. Verify and parallelism =
  last values used for this project, from the per-project store below.
- Verification is required by `am`. The dialog starts empty if there is no stored
  set; the opt-out is an explicit checkbox that passes `--allow-no-verification`.
- The cost warning is always shown. A per-viewer setting "Confirm dispatches" is
  on by default; turning it off removes only the extra confirm click, never the
  preview or the warning. (If the user wants a hard read-only mode, that is a
  separate setting, see Open questions.)

## Architecture

- `core/domain/runs.js` gains `dispatchPlan(card)` (which command and flags a card
  maps to, or why it can't be dispatched: a card whose brd status is `done`,
  `merged`, `canceled` or `archived` is refused with that reason), `dispatchDefaults(project, card)`,
  `validateDispatch(form)` and `previewSummary(dryRunData)`.
- `core/backend/runs/dispatch-preview.py` — runs the `--dry-run` command and prints
  its envelope as one JSON line. Latest run wins via `HelperRunner`.
- `core/backend/runs/start-run.py` — the detached launcher. It follows
  `core/backend/milestones/run-setup-milestone.py`'s conventions (own session via
  `start_new_session`, project root as cwd, stdin devnull, output to a private log
  under `~/.local/state/omarchy-project-manager/am-runs/`) but returns
  immediately after spawn with `{"ok":true,"pid":…,"log":…,"started_at":…}` and
  never waits or kills. The process outlives the panel and the shell by design.
- **Finding the run id.** `am run` prints its report only when it finishes, so the
  run id is not known at launch (S4 item 2 fixes this). Until then `start-run.py`
  polls `am runs --repo-dir R` for up to 20 s for a run with `started_at` ≥ spawn
  time and the same `branch_prefix`, and emits `{"run_id":…}`; if none appears it
  reports "started, run not visible yet", and the Runs screen picks it up through
  S1's watch. If the process exits early, the helper returns its log tail and
  exit code instead, which is how late refusals surface.
- `RunStore.qml` gains `dispatch` state `idle → previewing → ready | refused →
  starting → started | failed`, the form, and a `dispatchStart()` that calls
  `start-run.py`. Store-to-store wiring stays in `App.qml` (store must not import
  siblings): on `started` the navigation push to Run detail is a signal the
  `Navigator` handles.
- **Per-project dispatch settings** (prefix history, parallelism, confirm
  setting) extend the per-project run settings that the controls milestone (S2,
  subtask 2.2) adds to `viewer-state.py` (`get-run-settings` /
  `set-run-settings`, which already hold the verify commands that S2's Resume
  reads). S3 adds fields to that store; it does not create a second one.
- UI: `ui/components/DispatchDialog.qml` (built on `ModalCard`, `ActionButton`,
  `Chip`; the verify list is a small repeater, no new shared component unless a
  second user appears), a **Dispatch** button in `CardDetailScreen` and the
  Runs toolbar, key `d` in `Shortcuts.qml` (board list and card detail).

## Safety

- Nothing starts without a successful preview (milestone/board) or an explicit
  confirm (subtask).
- The dialog never edits git or the board; `am` does, and only after Start.
- A run that cannot start because another run holds the card or branch
  (`ClaimedError`) is shown as a refusal with the other run's id, linking to it.
- Closing the panel after Start does nothing to the run. Closing it before the
  launcher returns (a second or two) cannot orphan anything: `start-run.py`
  completes the spawn regardless, and the run shows up on the next open.
- Because dispatch spends money and spawns agents, the dialog is the only place a
  run can start; there is no key that starts one without it.

## Errors

| case | behaviour |
|---|---|
| `am` missing | Dispatch button disabled with the S1 `missing` message |
| preview refusal | inline, Start disabled |
| `start-run.py` spawn failure (no exec, bad cwd) | inline error with the log path |
| `am run` exits within the poll window with a refusal | inline, with exit code and last 20 log lines |
| run id not found in 20 s | dialog closes, toast "Started — waiting for the run to appear", Runs screen refreshes |
| project switched mid-start | the launch completes for the project it was started in; the result is recorded against that project |

## Testing

- `tst_runs.qml`: `dispatchPlan` per card level (milestone, subtask, story,
  board, already-done cards), defaults, validation (empty prefix, no verify and
  no opt-out), `previewSummary` on recorded `--dry-run` payloads.
- `tst_run_store.qml`: dispatch state machine incl. debounced re-preview, latest
  preview wins, Start disabled until ready, project-switch guard.
- Backend pytest with a stub `am`: preview passthrough, spawn is detached (new
  session, survives the helper), run-id discovery by `started_at` + prefix,
  early-exit reporting, log placement and permissions (0600).
- `tests/ui/` flows: open from each entry point, edit verify, refusal inline,
  Start navigates to Run detail.
- `tests/contract/test_am_shapes.py` gains the `--dry-run` payload (milestone and
  board) and the `run` refusal types.
- A manual verification step in the plan: dispatch a trivial fixture milestone
  on a scratch repo with `am`'s fake harness, never a real one, in CI-free form.

## Open questions

- Do you want a separate hard **read-only mode** (no dispatch, no control; monitor
  only)? Assumed no for now; it would be one setting that hides the buttons.
- `--board` dispatch: confirm it should be exposed at all, since it drives every
  open milestone. Assumed yes, behind the same preview and the strongest warning
  text ("N milestones, M subtasks").
