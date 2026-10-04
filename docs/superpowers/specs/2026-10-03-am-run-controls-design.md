# am run controls and alerts (S2) — design

Status: proposed. Depends on `2026-10-03-am-run-monitor-design.md` (S1: `RunStore`,
`runs.js`, Runs screen, Run detail, `RunIndicator`). Does not depend on S3.

## Problem

S1 shows that a run is escalated, dead or parked, but the user must then switch to
a terminal to pause, resume or cancel it, and nothing tells them an escalation
happened while they were looking at something else.

## Goal

From the panel the user can pause, resume or cancel a run, including one started
in a terminal, and is told, inside the panel and optionally on the desktop, when a
run starts needing them.

## Non-goals

- No starting runs (S3).
- No per-story or per-subtask control: `am` pauses and cancels whole runs only.
  Cards inside a run show the run's controls, labelled "applies to the whole run".
- No `retry`, `--wait` or Integrate stop: `am` has none, and the plugin does not
  emulate them.
- The plugin never sends signals to `am` processes. Control is only
  `am pause|cancel|resume`, which is durable (written to the run's control table)
  and works from any process.

## Control actions

| action | command | offered when | confirmation |
|---|---|---|---|
| Pause | `am pause RUN --repo-dir R` | state `running` and `control.lease.accepting` | none; non-destructive, idempotent |
| Resume | `am resume RUN --repo-dir R [--verify …]` | state `parked`, `escalated` or `dead` | none; milestone runs show the verify set about to be reused |
| Cancel | `am cancel RUN --repo-dir R` | state `running`, `parked`, `escalated`, `dead`, and `accepting` | typed confirmation; cancel is final, a cancelled run cannot be resumed, and cards keep their status |

Facts from am's contract that shape the UI:

- Pause and cancel return at once and take effect at the next phase boundary
  (polled about once a second); a phase in flight is never interrupted. The UI
  therefore has a visible **requested** state, not just a result.
- Both are idempotent: a repeat returns `already_requested`. Buttons still
  disable while a request is outstanding, to avoid double fires.
- During Integrate `control.lease.accepting` is false and `am` refuses with
  `NotAcceptingError`. Gate on it: the buttons are disabled with the reason
  "Integrate is running; it cannot be paused or cancelled".
- Resume takes over only a **dead** lease. A live lease is refused
  (`RunIsLiveError`); a cancelled run is refused (`NotResumableError`).
- The verify suite is not recorded on a run. A milestone Resume must pass
  `--verify` again, so the plugin stores the last verify set per project and
  shows it in the confirm step; if none is stored, Resume opens the same verify
  fields as the S3 dispatch dialog (or an explicit "no verification" opt-out).
  A `--card` run's resume ignores `--verify`.

## Architecture

- `core/domain/runs.js` gains `controls(run)` → `{pause, resume, cancel}` each
  `{enabled, reason}`, and `controlError(error)` mapping `error.type`
  (`UnknownRunError`, `NotRunningError`, `DeadRunError`, `NotAcceptingError`,
  `RunIsLiveError`, `NotResumableError`, `ClaimedError`, `LockTimeoutError`) to
  one short sentence; the raw message stays one click away.
- `core/backend/runs/run-control.py <pause|resume|cancel> RUN REPO [--verify …]`
  runs the `am` command, prints its envelope as one JSON line, and exits 0 even on
  a refusal so the store can read the error type (same pattern as other helpers).
- `RunStore.qml` gains `control(action, runId)`, `pending{runId: action}` and
  `lastError`. After a control call it re-snapshots immediately and keeps
  `pending` until `am status` shows the request handled (`requests[].handled_at`)
  or the run's state changes. A request that is still unhandled after 30 s shows
  "still waiting — the run may be between phases or dead".
- `TypedConfirmDialog` is written for project delete (it validates with
  `Projects.isDeleteConfirmed`). Generalise it: a `confirmWord` property
  (default keeps today's behaviour) and `Projects.isDeleteConfirmed` stays for
  its caller. Cancel asks for the word `cancel`. This is the only change to an
  existing component; its tests are extended, not rewritten.
- `ui/components/RunControls.qml` renders the three buttons from `controls(run)`
  (icon + label, `ActionButton`), used by Runs rows, Run detail and
  `CardDetailScreen`'s Runs section.

## UI

```
 Runs row, hover or selected
┌────────────────────────────────────────────────────────────────────┐
│ ⟳ …19efcddc  M3 Document runs   3/8   implement @ #252   12m       │
│                                            [⏸ Pause]  [⊘ Cancel]   │
└────────────────────────────────────────────────────────────────────┘

 After Pause
│ ⟳ …19efcddc  M3 Document runs   3/8   pausing — parks at next phase │
│                                            [⏸ Pause requested…]     │

 Cancel confirmation (TypedConfirmDialog)
┌ Cancel run …19efcddc? ─────────────────────────────────┐
│ Cancel is final. The run cannot be resumed, only       │
│ relaunched; cards keep their current status.           │
│ A phase in flight finishes first.                      │
│ Type  cancel  to confirm: [            ]               │
│                          [ Keep running ] [ Cancel run ]│
└────────────────────────────────────────────────────────┘
```

Keyboard on the Runs screen and Run detail: `p` pause, `r` resume, `c` open the
cancel dialog; `Shortcuts.qml` forwards them to `RunStore.control`. Disabled
actions ignore the key and flash their reason in the footer.

On a story or subtask card the buttons read "Pause run", "Cancel run" and carry
the caption "applies to the whole run".

## Alerts

An **alert** is raised when a run enters `escalated` or `dead` (compared against
the previous snapshot; the first snapshot after the panel opens raises none, so
reopening never replays history).

1. **In panel (always on):** the toolbar `RunIndicator` and the sidebar Runs
   count (S1) update; a toast appears in the panel for 8 s, "‼ #251 escalated at
   review — [Open]", and Open navigates to Run detail. Toasts stack to 3 and are
   dismissed by Esc.
2. **Desktop (off by default):** a setting "Notify on escalation" in the plugin's
   per-viewer state (`viewer-state.py`). When on, `core/backend/runs/notify.py`
   calls `notify-send` with the run's title and reason, and does nothing if
   `notify-send` is missing. Because the plugin only watches while the panel is
   open, desktop alerts fire only while it is open; see Open questions.

```
 toast (bottom right of panel)
┌──────────────────────────────────────────┐
│ ‼ Run needs you                          │
│ #251 escalated at review                 │
│ "verify failed twice: 3 tests red"       │
│                       [ Open ] [ Dismiss ]│
└──────────────────────────────────────────┘
```

Toast rendering is a new `ui/components/RunToast.qml`; the alert decision is
pure (`runs.js` `newAlerts(prev, next)`) and tested without UI.

## Errors

| case | behaviour |
|---|---|
| refusal envelope (`ok:false`) | inline under the row: `controlError(error)`; buttons re-enable |
| `am` exits non-zero without an envelope | "am failed to run" + stderr tail on expand |
| request outstanding > 30 s | message above; offers Resume if the lease is dead |
| run vanished (`UnknownRunError`) | drop the row on the next snapshot, show the error once |
| project switch with a request in flight | the request still completes in `am`; the store's guard is the project the request was for, so the result is not shown against the new project |

## Testing

- `tst_runs.qml`: `controls()` for every state × `accepting`, `controlError`
  table, `newAlerts` (no alert on first snapshot, one alert per transition,
  none for a run already escalated).
- `tst_run_store.qml`: `pending` lifecycle, 30 s timeout, re-snapshot after
  control, project-switch guard.
- Backend pytest with a stub `am`: each action's argv, each refusal type,
  no-envelope failure, `notify.py` with and without `notify-send`.
- Extended `TypedConfirmDialog` tests: default word unchanged for project delete,
  `cancel` word for runs.
- `tests/ui/` flows: pause → requested → parked; cancel with wrong then right
  word; Integrate disables both; toast Open navigates.
- `tests/contract/test_am_shapes.py` gains the control envelopes and error types.

## Open questions

- Desktop alerts only fire while the panel is open. Is that enough, or does the
  plugin need an always-on watcher (a second, tiny process owned by the shell)?
  This spec assumes enough, and adds nothing always-on.
- Where is the verify set stored per project — alongside the remembered project
  in `viewer-state.py`, or a new file? S3 and this spec must use the same one;
  decided in S3.
