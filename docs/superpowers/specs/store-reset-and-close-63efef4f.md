# Store: reset control and Close dialog state

Card: `63efef4f` "Store reset and close-dialog state + tests", a subtask of story C (`19aa24c1`).

Parent design: `docs/superpowers/specs/runs-screen-row-redesign-design.md` (cited below as
**RR** with line numbers), section "Store: `core/stores/RunControlStore.qml`" (RR lines 95-99).
Sibling contract: `docs/superpowers/specs/write-contract-stubs-6f9f8639.md` (cited as **WS**),
which fixed the action vocabularies and the `controlError(error, action)` signature.

## Problem

`RunControlStore` knows three control actions (`pause`, `resume`, `cancel`). The new Close
button (RR lines 80-81) runs `am reset` through `run-control.py reset RUN --repo-dir REPO`
(RR line 85), behind a confirm dialog (RR lines 101-108) whose state belongs in the store, as
the cancel confirmation's does. Nothing in the store can start a reset, refuse one, or hold that
dialog's state.

## Goal

1. `control("reset", runId)` starts a reset the way it starts a pause or a cancel, and
   `refusalOf("reset", runId)` says why it would not.
2. A failed reset's sentence is computed with the action, so story B's reset-specific sentences
   reach the UI.
3. The store holds the Close dialog's state: which run it asks about, why the last confirm was
   refused, and the open / dismiss / confirm operations.

## Inherited constraints

- Vocabularies (WS lines 72-80 and `core/domain/runs.js` doc comment on `controls`, ~line 1189):
  the store says `pause`, `resume`, `cancel`, `reset`; the UI and `controls()` say `close`.
  **The store never accepts `close` as an action.** `controls(run).close` is the entry the store
  reads for `reset`.
- Reset is settled like pause and cancel (RR line 97).
- No change to the cancel confirmation fields or methods (RR line 99).
- The Close dialog opens only when `refusalOf("reset", id)` is empty (RR line 99).
- `ControlFacts.pendingOf` documents the new value (RR line 98).
- Layering (RR line 21): the store imports only `core/domain`; it reaches no other store.
- Store conventions (`core/stores/RunControlStore.qml` header comment, lines 8-29): maps are
  replaced, never changed in place (`Runs.copyMap`); every function has a leading comment block;
  `control.` is the self-id prefix.

## Deviation from RR: the dismiss method is `closeKeep()`, not `closeCancel()`

RR line 99 names the dismiss method `closeCancel()`. That name already exists on this store
(`RunControlStore.qml:324`): it closes the **cancel** dialog and is called from
`ui/Panel.qml:855` and `ui/Shortcuts.qml:48`. A second `closeCancel` in the same QML object
would replace or break it. The Close dialog's dismiss method is therefore **`closeKeep()`**,
after the dialog's `Keep` button (RR line 107). `closeAsk(runId)` and `closeConfirm()` keep
RR's names. Stories D (`CloseRunDialog`) and F (Panel / Shortcuts wiring) must call
`closeKeep()`. Nothing in the repository calls any of the new names yet.

## Behavior

### Actions: `refusalOf(action, runId)`

- `"reset"` joins `"pause"`, `"resume"` and `"cancel"` as a known action. Any other value,
  `"close"` included, still returns `"Unknown control"`.
- For `"reset"`, the checks run in today's order: run not in `runs` →
  `This run is no longer in the snapshot`; no `repo_dir` → `This run has no repository`; a
  request already pending → `A request for this run is pending`; otherwise
  `Runs.controls(run).close.reason`. The project-root check stays resume-only: a reset of a run
  with no `project.root` is not refused for that.
- An id such as `constructor` or `__proto__` is just an id (no inherited key counts as pending),
  as today.
- It still changes nothing and starts nothing.

Until story B (`042b0d8e`) lands, `controls(run).close` is the stub
`{enabled: false, reason: "The run's state is unknown"}` (WS lines 60-64), so every reset of a
run that passes the earlier checks is refused with that reason. After B, the reasons are WS's
table (WS lines 87-105). This card does not depend on which is in place.

### Starting: `control("reset", runId)`

- Returns `false` and starts nothing when `refusalOf("reset", runId)` is not `""`.
- Otherwise, exactly as a pause or cancel: dismisses the control error, records the request with
  the run's state as baseline, sets `pending[runId] = "reset"`, adds one runner to
  `controlRunners`, and launches `python3 <backendDir>runs/run-control.py reset RUN REPO`, `REPO`
  the run's `repo_dir`. No settings step, no `--verify`, no `--allow-no-verification`.
- Returns `true`.

### Replies and settling

- `controlReplied` passes the request's action as the second argument of `Runs.controlError`
  (today it passes one argument, `RunControlStore.qml:207`). This applies to every action, not
  only reset; pause, resume and cancel sentences are unchanged because `controlError` maps only
  `reset` differently (WS lines 74-80).
- An `ok: true` reply acknowledges the request and records `requested_at` as today. An
  `ok: false` reply clears the pending entry and sets `lastControlError` to
  `Runs.controlError(envelope, "reset")`, `lastControlErrorRunId` and `lastControlErrorType`.
  An unreadable reply gives `The run control gave no usable result (exit N).` Every applied reply
  emits `refreshRequested("all")` once.
- `settleAfterSnapshot` settles an acknowledged reset when the run is gone from `runs`, its
  state changed from the baseline, or its am request row (matched by `requested_at`, else the
  last row with `command === "reset"`) has a `handled_at`. This is the existing non-resume rule;
  no code change is expected there, only the comment's action list.
- The pending value is the string `"reset"`. The UI label for it (`Close requested…`, RR line 97)
  is `RunControls`' mapping, story D's work, not this card's.

### Close dialog state

New members, next to the cancel confirmation:

| Member | Kind | Meaning |
|---|---|---|
| `closeRunId` | `property string`, default `""` | the run the dialog asks about; `""` = closed |
| `closeOpen` | `readonly property bool` | `closeRunId !== ""` |
| `closeError` | `property string`, default `""` | why the last confirm was refused |
| `closeAsk(runId)` | function → bool | open the dialog for a run that can be closed now |
| `closeKeep()` | function | dismiss the dialog |
| `closeConfirm()` | function → bool | start the reset and close the dialog |

- **`closeAsk(runId)`**: when `refusalOf("reset", runId)` is not `""`, flashes that reason
  (`flash(reason)`, as `openCancel` does), leaves any open Close dialog unchanged, starts
  nothing, and returns `false`. Otherwise sets `closeError = ""`, `closeRunId = runId` (replacing
  any run the dialog was open for) and returns `true`. It starts no request.
- **`closeKeep()`**: sets `closeRunId = ""` and `closeError = ""`. Starts nothing; safe when
  already closed.
- **`closeConfirm()`**:
  - Dialog closed (`closeRunId === ""`): returns `false`, changes nothing.
  - `refusalOf("reset", closeRunId)` is not `""` (the run changed or vanished under the open
    dialog, or a request became pending): sets `closeError` to that reason, keeps the dialog
    open, starts nothing, returns `false`.
  - `control("reset", closeRunId)` returns `false`: sets `closeError` to
    `The run could not be closed`, keeps the dialog open, returns `false`. (Defensive; mirrors
    `confirmCancel`.)
  - Otherwise: one reset is started, then `closeKeep()`; returns `true`.
- No typed confirmation (RR line 103).
- The Close dialog and the cancel dialog are independent: opening, dismissing or confirming one
  never changes the other's fields.
- A project switch (a change of `project`) and a change of `runs` change none of the Close
  dialog fields, as for the cancel dialog. Only `closeConfirm` re-checks the run.

### Documentation

- `RunControlStore.qml` header comment (lines 8-10) and the comments on `control`, `refusalOf`
  and `settleAfterSnapshot` name `reset` and the Close dialog.
- `ui/components/runControlFacts.js` `pendingOf` comment: `("pause" | "resume" | "cancel" |
  "reset")`. The function is unchanged.
- `docs/architecture.md` line 93 (the single `RunControlStore.qml` bullet): `control` starts a
  `pause`, `resume`, `cancel` or `reset`; `refusalOf` accepts `reset` and reads
  `Runs.controls(run).close`; a sentence on the Close dialog (`closeRunId`, `closeOpen`,
  `closeError`, `closeAsk`, `closeKeep`, `closeConfirm`) with the rules above. It stays one
  top-level bullet (`tests/architecture/test_run_store_docs.py`).
- `tests/architecture/test_run_store_callers.py` `MOVED` map gains `closeRunId`, `closeOpen`,
  `closeError`, `closeAsk`, `closeKeep`, `closeConfirm` → `runControl`, so no `ui/` caller reaches
  them through `.runs.`. `tests/core/stores/tst_app_runs.qml`'s `movedToControl` list mirrors
  `MOVED` ("in the order of MOVED"); it gains the same six names, so the run store is also
  asserted not to keep them.

## Testing against the stub

Tests that need an **enabled** close (an open dialog, a started reset, its argv, its settling,
its error sentence) cannot pass while `controls().close` is the stub. They are written now and
guarded by a runtime probe in `tests/core/stores/tst_run_control_store.qml`:

```qml
// Story B (042b0d8e) enables controls().close for a parked run; until then
// the tests that need a reset to start skip themselves.
readonly property bool closeImplemented: Runs.controls(held(ctlEntry("probe", "stopped", false))).close.enabled === true
```

each guarded test starting with
`if (!closeImplemented) skip("controls().close not implemented yet (story B)")`. The probe turns
itself on when B lands; nobody has to flip a flag. Every other test below runs and passes now.
Tests must not hard-code the stub's reason: where a reason comes from `controls()`, they compare
with `Runs.controls(held(e)).close.reason` for the same entry, which is right before and after B.

`ctlEntry(id, "stopped", false)` is the parked run the existing tests use (e.g. line 743).

## Tests

All tests below live in `tests/core/stores/tst_run_control_store.qml` (tier: **store unit**,
QML `TestCase` under `qmltestrunner` with stubbed `Process` objects, run by `tests/run.sh`;
this is where the store's behavior is observable without a UI and where every existing control
and cancel-dialog test lives) unless stated otherwise. Numbering continues the file's `// N`
comments.

Run now (no guard):

1. **A bare store's Close dialog is closed.** `closeRunId === ""`, `closeOpen === false`,
   `closeError === ""` (extend `test_a_bare_control_store_has_nothing_pending_and_nothing_open`).
2. **`refusalOf("reset")` order and vocabulary.** Not in snapshot; `""` id; no `repo_dir`; a run
   with no project root is **not** refused for that (its result equals the `controls` reason);
   pending wins over the state's reason (start a pause on a running run, then
   `refusalOf("reset", id)` is `A request for this run is pending`); for running, parked, done
   and integrate runs the result equals `Runs.controls(held(e)).close.reason`; `refusalOf("close",
   id)` and `refusalOf("bogus", id)` are `Unknown control`; `control("close", id)` returns false;
   no runner started.
3. **`closeAsk` on a refused run flashes and opens nothing.** For an id not in the snapshot:
   returns false, `flashText` is `This run is no longer in the snapshot`, `closeOpen` false, no
   runner. For a running run: returns false and `flashText === refusalOf("reset", id)` (non-empty).
4. **A refused `closeAsk` leaves an open dialog alone.** Set `closeRunId = "r2"`,
   `closeError = "old"` directly; `closeAsk("nope")` → false; `closeRunId` still `"r2"`,
   `closeError` still `"old"`.
5. **`closeKeep` clears every field.** With `closeRunId` and `closeError` set, `closeKeep()`
   leaves both `""` and `closeOpen` false; a second `closeKeep()` is harmless; no runner.
6. **`closeConfirm` with the dialog closed does nothing.** Returns false, `closeError` stays
   `""`, no runner.
7. **A refused reset keeps the dialog's error (RR line 132).** Set `closeRunId` to a running
   run's id directly; `closeConfirm()` → false; `closeOpen` true; `closeError ===
   refusalOf("reset", id)`; no runner; `pending` unchanged.
8. **`closeConfirm` on a run gone from the snapshot.** `closeRunId = "gone"`; `closeConfirm()` →
   false, `closeError` `This run is no longer in the snapshot`, dialog open.
9. **The Close and cancel dialogs are independent.** Open cancel for a running run
   (`openCancel`), set `closeRunId`; `closeKeep()` leaves `cancelRunId` set; `closeCancel()`
   leaves `closeRunId` set.
10. **A project switch keeps the Close dialog.** With `closeRunId` and `closeError` set, change
    `project`; both unchanged.

Guarded by `closeImplemented`:

11. **`closeAsk` opens for a closable run.** Parked run: returns true, `closeRunId` the id,
    `closeError` cleared (it was set beforehand), `flashText` `""`, no runner started.
12. **`closeConfirm` starts one reset and closes.** After `closeAsk` on a parked run:
    `closeConfirm()` → true; exactly one runner; `pending[id] === "reset"`; `closeOpen` false;
    `closeError` `""`.
13. **The reset argv.** `control("reset", id)` on a parked run launches exactly
    `ctlCmd + "reset|<id>|" + rootA`: no `--verify`, no `--allow-no-verification`, no settings
    step; a parked run with no project root is not refused.
14. **A reset settles like a cancel.** After an `ok: true` reply: a snapshot with the same state
    and no request row keeps it pending; a snapshot whose run state changed settles it; in a
    second run, a snapshot with an am request row `command: "reset"` and a `handled_at` settles
    it; a run gone from the snapshot settles it.
15. **A failed reset's sentence is computed with the action.** An `ok: false` reply with type
    `RunIsLiveError`: `pending` cleared, `lastControlError === Runs.controlError(envelope,
    "reset")`, `lastControlErrorRunId` the id, `lastControlErrorType` `RunIsLiveError`, one
    `refreshRequested("all")`. Repeat with `NotResettableError`. (When B has landed this is the
    reset sentence, WS table / RR lines 92-93; this test pins that the store passes the action.)
16. **A reset of a changed run under the open dialog is refused.** `closeAsk` on a parked run,
    then `runs` replaced so it is running; `closeConfirm()` → false, `closeError` equals the
    new `refusalOf`, dialog open, no runner.
17. **A pending request refuses the confirm.** `closeAsk` on a parked run, then `control
    ("resume", id)` starts; `closeConfirm()` → false, `closeError` `A request for this run is
    pending`, only the resume's runner exists.

Other tiers:

18. `tests/ui/components/tst_run_control_facts.qml` `test_pending_of`: add
    `compare(Facts.pendingOf({ r1: "reset" }, r), "reset")` (tier: **UI helper unit**, the file
    that already pins `pendingOf`; proves the documented value passes through untouched).
19. `tests/architecture/test_run_store_callers.py` and `test_run_store_docs.py` pass with the
    new `MOVED` entries and the edited bullet (tier: **architecture**, Python under
    `tests/run.sh`; they are the guards on the store's documented surface).
20. Every existing test in `tst_run_control_store.qml`, `tst_run_row_contract.qml` and the rest
    of `bash tests/run.sh` passes unmodified; in particular the cancel dialog tests (3, 4 and the
    project-switch test) still call `closeCancel()` and still pass.

## Error paths summary

| Input | Result |
|---|---|
| `control("close", id)` / `refusalOf("close", id)` | `false` / `Unknown control` |
| reset of a run not in `runs`, with no `repo_dir`, or with a pending request | refused with today's sentences |
| reset of a run `controls().close` disables | refused with its reason |
| `closeAsk` refused | flash the reason, dialog unchanged, `false` |
| `closeConfirm` with dialog closed | `false`, nothing changes |
| `closeConfirm` refused | `closeError` = reason, dialog open, `false` |
| `control` fails inside `closeConfirm` | `closeError` = `The run could not be closed`, dialog open |
| am replies `ok: false` | pending cleared, `lastControlError = Runs.controlError(envelope, "reset")` |
| am reply unreadable | `The run control gave no usable result (exit N).` |

## Out of scope

- `run-control.py` `ACTIONS`, `USAGE` and its Python tests: story A (`cc7f1fd6`).
- `controls().close`, `visibleActions`, `runLevel`, the reset sentences in `controlError`:
  story B (`042b0d8e`). This card only reads them.
- `RunControls` buttons and the `Close requested…` label for pending `"reset"`, `RunLevelBadge`,
  `RunStateBadge`, `CloseRunDialog` (including the `open_in` sentence, RR line 106): story D
  (`7997c2cf`).
- Theme tokens and `ActionButton` tones: story E (`8c7324d3`).
- `RunsScreen.closeRequested`, `Panel` mounting and focus chain (`ui/Panel.qml:194`), the Escape
  chain (`ui/Shortcuts.qml:48, 56`), App wiring: story F (`8e2ec6be`). F must use `closeOpen` and
  `closeKeep()`.
- Any change to the cancel or Resume dialogs.
- Mutual exclusion between the Close and cancel dialogs (the UI shows one at a time; the store
  does not enforce it).
