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


---

# Store reset control and Close dialog state Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `RunControlStore` can refuse, start and settle a `reset` (the UI's Close), passes the request's action to `Runs.controlError`, and holds the Close dialog's state (`closeRunId`, `closeOpen`, `closeError`, `closeAsk`, `closeKeep`, `closeConfirm`).

**Architecture:** `refusalOf` learns `"reset"` and reads `Runs.controls(run).close` for it; `control` needs no new branch (a reset takes the same `launchControl(runner, [])` path as pause and cancel); `controlReplied` passes `req.action` as `controlError`'s second argument. The Close dialog sits next to the cancel confirmation and mirrors `openCancel` / `closeCancel` / `confirmCancel` without the typed word. Tests that need an enabled close are guarded by a runtime probe (`closeImplemented`) and skip until story B lands.

**Tech Stack:** QML (Quickshell `Scope`, `QtQml`), JavaScript domain modules (`core/domain/runs.js`), QtTest `TestCase` under `qmltestrunner`, pytest architecture guards.

**Spec:** `docs/superpowers/specs/store-reset-and-close-63efef4f.md` (prepended above).

## Global Constraints

- The store says `pause`, `resume`, `cancel`, `reset`; the UI and `controls()` say `close`. **The store never accepts `close` as an action.** `controls(run).close` is the entry the store reads for `reset`.
- Reset is settled like pause and cancel (RR line 97).
- No change to the cancel confirmation fields or methods (RR line 99). `closeCancel()` keeps closing the **cancel** dialog.
- The Close dialog's dismiss method is **`closeKeep()`**, not `closeCancel()`.
- The Close dialog opens only when `refusalOf("reset", id)` is empty.
- The store imports only `core/domain`; it reaches no other store.
- Maps are replaced, never changed in place (`Runs.copyMap`); every function has a leading comment block; `control.` is the self-id prefix.
- Exact sentences: `Unknown control`, `This run is no longer in the snapshot`, `This run has no repository`, `A request for this run is pending`, `The run could not be closed`, `The run control gave no usable result (exit N).`
- Tests must not hard-code the stub's reason: compare with `Runs.controls(held(e)).close.reason` for the same entry.
- Guard probe, exactly: `readonly property bool closeImplemented: Runs.controls(held(ctlEntry("probe", "stopped", false))).close.enabled === true`; each guarded test starts with `if (!closeImplemented) skip("controls().close not implemented yet (story B)")`.
- `docs/architecture.md`'s `RunControlStore.qml` text stays one top-level bullet.
- Never use bare `git stash`. Never `pkill`/`killall`; stop a stuck test with `timeout`.

## How to run tests

- One QML test file, optionally one function (fast, seconds), from the worktree root:
  `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_control_store.qml [StoresRunControlStore::test_name ...]`
  The `TestCase` names are `StoresRunControlStore` (`tst_run_control_store.qml`), `StoresAppRuns` (`tst_app_runs.qml`), `RunControlFacts` (`tst_run_control_facts.qml`).
- Python architecture guards (`python3` has no pytest here; use uv):
  `timeout 300 uv run --with pytest python3 -m pytest tests/architecture/test_run_store_callers.py tests/architecture/test_run_store_docs.py -q`
- Everything (about 4 minutes; pytest then every QML file): `timeout 600 bash tests/run.sh`

Until story B (`042b0d8e`) lands, `controls(run).close` is disabled for every run, so every guarded test reports `SKIP` with `controls().close not implemented yet (story B)`. A `SKIP` is the expected result for them in every step below; it is not a failure. The unguarded tests carry the RED/GREEN cycle.

## Review Focus

1. **`closeAsk` with an id that is not a non-empty string** (`undefined`, `null`, `7`, `""`, e.g. a delegate whose model row went away): expected to flash `This run is no longer in the snapshot`, open nothing, return `false` — never throw. Pinned in Task 2, test 3.
2. **A double-click on the dialog's Close button** (`closeConfirm()` twice): the second call must find the dialog closed and start no second reset; a fresh `closeAsk` for the run is refused while the reset is pending. Pinned in Task 2, test 12.
3. **A run whose id is `constructor` (or another inherited key name)**: a reset of it is judged on its state, never refused as "pending". Pinned in Task 1, test 2.
4. **A control reply (any action) or a new run list landing while the Close dialog is open**: it must leave `closeRunId` and `closeError` alone; only `closeConfirm` re-checks. Pinned in Task 2, test 10.
5. **A reset reply that is not JSON** (helper crashed): pending cleared, `The run control gave no usable result (exit N).` on that run, one refresh. Pinned in Task 1, test 15.

---

### Task 1: `refusalOf` and `control` know `reset`; a failed reply's sentence gets the action

**Files:**
- Modify: `core/stores/RunControlStore.qml:8-10` (header comment), `:102-105` (comment on `control`), `:180-213` (`controlReplied`), `:247-250` (comment on `settleAfterSnapshot`), `:288-300` (`refusalOf`)
- Test: `tests/core/stores/tst_run_control_store.qml` (new section appended before the file's final `}`)

**Interfaces:**
- Consumes: `Runs.controls(run)` → `{pause, resume, cancel, close}`, each `{enabled, reason}` (`core/domain/runs.js:1198`); `Runs.controlError(error, action)` (`core/domain/runs.js:1271`).
- Produces: `refusalOf(action, runId)` accepts `"reset"` → `string`; `control("reset", runId)` → `bool`, launching `python3 <backendDir>runs/run-control.py reset RUN REPO`; `pending[runId] === "reset"` while in flight. Test helpers in `tst_run_control_store.qml` for Task 2: `closeImplemented` (bool property), `parked(id)` (snapshot entry), `closeReason(e)` (string), `resetAcked(store, id, requestedAt)`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_control_store.qml`, the file ends with:

```qml
    compare(controlOf(store).pending.r1, undefined, "the request is settled")
    compare(controlOf(store).controlRunners.length, 0)
  }
}
```

Replace those lines with (the first four lines are unchanged; the new section goes before the final `}`):

```qml
    compare(controlOf(store).pending.r1, undefined, "the request is settled")
    compare(controlOf(store).controlRunners.length, 0)
  }

  // ---- reset and the Close dialog (store-reset-and-close-63efef4f)

  // Story B (042b0d8e) enables controls().close for a parked run; until then
  // the tests that need a reset to start skip themselves.
  readonly property bool closeImplemented: Runs.controls(held(ctlEntry("probe", "stopped", false))).close.enabled === true

  // A parked run of project A: stopped, its process gone.
  function parked(id) { return ctlEntry(id, "stopped", false) }

  // The reason Runs.controls gives for closing the run built from entry `e`.
  function closeReason(e) { return Runs.controls(held(e)).close.reason }

  // A reset of `id` that am acknowledged; requestedAt "" leaves it out of the reply.
  function resetAcked(store, id, requestedAt) {
    compare(controlOf(store).control("reset", id), true)
    var data = { run_id: id, command: "reset" }
    if (requestedAt !== "") data.requested_at = requestedAt
    reply(controlOf(store).controlRunners[controlOf(store).controlRunners.length - 1].current, ctlOk(data), 0)
  }

  // 2 (and Review Focus 3)
  function test_refusal_of_reset_keeps_the_order_and_reads_controls_close() {
    var store = make(); if (!store) return
    compare(controlOf(store).refusalOf("reset", "r1"), "This run is no longer in the snapshot", "an empty snapshot")
    var noRepo = held(parked("r0"), tc.rootA)
    noRepo.repo_dir = ""
    var e1 = running("r1"), e2 = parked("r2"), e3 = integrate("r3"), e4 = ctlEntry("r4", "done", false)
    var e5 = running("r5"), e6 = parked("constructor")
    store.runs = [noRepo, held(e1, tc.rootA), held(e2), held(e3, tc.rootA), held(e4, tc.rootA),
                  held(e5, tc.rootA), held(e6, tc.rootA)]
    compare(controlOf(store).refusalOf("reset", "nope"), "This run is no longer in the snapshot")
    compare(controlOf(store).refusalOf("reset", ""), "This run is no longer in the snapshot", "an empty id")
    compare(controlOf(store).refusalOf("reset", 7), "This run is no longer in the snapshot", "an id that is not a string")
    compare(controlOf(store).refusalOf("reset", "r0"), "This run has no repository")
    compare(controlOf(store).refusalOf("reset", "r2"), tc.closeReason(e2), "a run with no project root is not refused for that")
    verify(controlOf(store).refusalOf("reset", "r2") !== "This run's project is not known")
    compare(controlOf(store).refusalOf("reset", "r1"), tc.closeReason(e1), "running")
    compare(controlOf(store).refusalOf("reset", "r3"), tc.closeReason(e3), "integrate")
    compare(controlOf(store).refusalOf("reset", "r4"), tc.closeReason(e4), "done")
    compare(controlOf(store).refusalOf("reset", "constructor"), tc.closeReason(e6), "an id like constructor is not pending")
    compare(controlOf(store).refusalOf("close", "r2"), "Unknown control", "close is the UI's word, never the store's")
    compare(controlOf(store).refusalOf("bogus", "r2"), "Unknown control")
    compare(controlOf(store).refusalOf("Reset", "r2"), "Unknown control", "actions are exact")
    compare(controlOf(store).control("close", "r2"), false)
    compare(controlOf(store).control("close", "r1"), false)
    compare(controlOf(store).controlRunners.length, 0, "refusalOf and a refused control start nothing")
    compare(Object.keys(controlOf(store).pending).length, 0)
    compare(controlOf(store).control("pause", "r5"), true)
    compare(controlOf(store).refusalOf("reset", "r5"), "A request for this run is pending", "pending wins over the state's reason")
    compare(controlOf(store).controlRunners.length, 1)
  }

  // 13
  function test_a_reset_launches_the_exact_argv() {
    if (!closeImplemented) skip("controls().close not implemented yet (story B)")
    var store = make(); if (!store) return
    store.runs = [held(parked("r1"), tc.rootA), held(parked("r2"))]
    compare(controlOf(store).control("reset", "r1"), true)
    compare(controlOf(store).pending.r1, "reset")
    var runner = controlOf(store).controlRunners[0]
    compare(runner.action, "reset")
    compare(runner.seq, 1, "one launch: no settings step")
    compare(argv(runner.current), tc.ctlCmd + "reset|r1|" + tc.rootA)
    compare(runner.current.command.length, 5, "no --verify, no --allow-no-verification")
    compare(controlOf(store).refusalOf("reset", "r2"), "", "a reset needs no project root")
    compare(controlOf(store).control("reset", "r2"), true)
    compare(argv(controlOf(store).controlRunners[1].current), tc.ctlCmd + "reset|r2|" + tc.rootA)
    compare(controlOf(store).controlRunners[1].seq, 1)
    compare(controlOf(store).controlRunners.length, 2)
  }

  // 14
  function test_a_reset_settles_like_a_cancel() {
    if (!closeImplemented) skip("controls().close not implemented yet (story B)")
    var store = ctlStore([parked("r1")]); if (!store) return
    resetAcked(store, "r1", "t1")
    compare(controlOf(store).pending.r1, "reset", "acknowledged, not settled")
    snapshot(store, [parked("r1")])
    compare(controlOf(store).pending.r1, "reset", "same state and no request row")
    snapshot(store, [running("r1")])
    compare(controlOf(store).pending.r1, undefined, "the state changed")

    var rows = ctlStore([parked("r1")]); if (!rows) return
    resetAcked(rows, "r1", "t1")
    snapshot(rows, [ctlEntry("r1", "stopped", false, "milestone", [amRequest("reset", "t1", "")])])
    compare(controlOf(rows).pending.r1, "reset", "not handled yet")
    snapshot(rows, [ctlEntry("r1", "stopped", false, "milestone", [amRequest("reset", "t1", "t1h")])])
    compare(controlOf(rows).pending.r1, undefined, "am handled the reset row")

    var last = ctlStore([parked("r1")]); if (!last) return
    resetAcked(last, "r1", "")
    snapshot(last, [ctlEntry("r1", "stopped", false, "milestone",
      [amRequest("reset", "t0", "t0h"), amRequest("pause", "t1", "t1h"), amRequest("reset", "t2", "")])])
    compare(controlOf(last).pending.r1, "reset", "the last reset row is not handled; a handled pause is another request")
    snapshot(last, [ctlEntry("r1", "stopped", false, "milestone", [amRequest("reset", "t2", "t2h")])])
    compare(controlOf(last).pending.r1, undefined)

    var gone = ctlStore([parked("r1"), running("r2")]); if (!gone) return
    resetAcked(gone, "r1", "t1")
    snapshot(gone, [running("r2")])
    compare(controlOf(gone).pending.r1, undefined, "the run left the snapshot")
  }

  // 15 (and Review Focus 5)
  function test_a_failed_reset_says_why_with_the_reset_sentence() {
    if (!closeImplemented) skip("controls().close not implemented yet (story B)")
    var store = ctlStore([parked("r1"), parked("r2"), parked("r3")]); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: controlOf(store), signalName: "refreshRequested" })
    var types = ["RunIsLiveError", "NotResettableError"]
    for (var i = 0; i < types.length; i++) {
      var id = "r" + (i + 1)
      compare(controlOf(store).control("reset", id), true)
      var text = ctlFail(types[i], "x")
      reply(controlOf(store).controlRunners[0].current, text, 0)
      compare(controlOf(store).pending[id], undefined, types[i] + ": the buttons come back")
      compare(controlOf(store).lastControlError, Runs.controlError(JSON.parse(text), "reset"), types[i])
      compare(controlOf(store).lastControlErrorRunId, id)
      compare(controlOf(store).lastControlErrorType, types[i])
      compare(spy.count, i + 1, "one refresh per applied reply")
      compare(spy.signalArguments[i][0], "all")
    }
    compare(controlOf(store).control("reset", "r3"), true)
    reply(controlOf(store).controlRunners[0].current, "Traceback (most recent call last):\nboom\n", 3)
    compare(controlOf(store).pending.r3, undefined)
    compare(controlOf(store).lastControlError, "The run control gave no usable result (exit 3).")
    compare(controlOf(store).lastControlErrorRunId, "r3")
    compare(controlOf(store).lastControlErrorType, "")
    compare(spy.count, 3)
    compare(controlOf(store).controlRunners.length, 0)
  }
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run:
```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_control_store.qml StoresRunControlStore::test_refusal_of_reset_keeps_the_order_and_reads_controls_close StoresRunControlStore::test_a_reset_launches_the_exact_argv StoresRunControlStore::test_a_reset_settles_like_a_cancel StoresRunControlStore::test_a_failed_reset_says_why_with_the_reset_sentence
```
Expected: `FAIL!  : ...test_refusal_of_reset_keeps_the_order_and_reads_controls_close() Compared values are not the same` with `Actual (): Unknown control` / `Expected (): This run is no longer in the snapshot`; the three guarded tests `SKIP` with `controls().close not implemented yet (story B)`. Totals: 0 passed (besides init/cleanup), 1 failed, 3 skipped.

- [ ] **Step 3: Make `refusalOf` accept `reset` and read `controls().close`**

In `core/stores/RunControlStore.qml`, replace:

```qml
  // "" when control(action, runId) would start a request; otherwise why not:
  // a run that is not in `runs`, then a run with no repo_dir, then a resume
  // (not of a task run) of a run with no project root, then a request already
  // pending for it, then the reason Runs.controls gives. Changes nothing.
  function refusalOf(action, runId) {
    if (action !== "pause" && action !== "resume" && action !== "cancel") return "Unknown control"
    var run = typeof runId !== "string" || runId === "" ? null : Runs.runById(control.runs, runId)
    if (run === null) return "This run is no longer in the snapshot"
    if (typeof run.repo_dir !== "string" || run.repo_dir === "") return "This run has no repository"
    if (action === "resume" && run.workflow !== "task" && Runs.runRoot(run) === "") return "This run's project is not known"
    if (Runs.hasKey(control.pending, runId)) return "A request for this run is pending"
    return Runs.controls(run)[action].reason
  }
```

with:

```qml
  // "" when control(action, runId) would start a request; otherwise why not:
  // a run that is not in `runs`, then a run with no repo_dir, then a resume
  // (not of a task run) of a run with no project root, then a request already
  // pending for it, then the reason Runs.controls gives -- for a reset, its
  // `close` entry. Actions are pause, resume, cancel and reset; "close" is
  // the UI's word for reset and is an unknown control here. Changes nothing.
  function refusalOf(action, runId) {
    if (action !== "pause" && action !== "resume" && action !== "cancel" && action !== "reset") return "Unknown control"
    var run = typeof runId !== "string" || runId === "" ? null : Runs.runById(control.runs, runId)
    if (run === null) return "This run is no longer in the snapshot"
    if (typeof run.repo_dir !== "string" || run.repo_dir === "") return "This run has no repository"
    if (action === "resume" && run.workflow !== "task" && Runs.runRoot(run) === "") return "This run's project is not known"
    if (Runs.hasKey(control.pending, runId)) return "A request for this run is pending"
    return Runs.controls(run)[action === "reset" ? "close" : action].reason
  }
```

`control()` needs no code change: a reset is not a resume, so it takes the `else` branch, `control.launchControl(runner, [])`, which runs `[runner.action, runner.runId, runner.repoDir]` = `reset RUN REPO`.

- [ ] **Step 4: Pass the request's action to `controlError`**

In `controlReplied`, replace:

```qml
      control.failControl(runner.runId, Runs.controlError(envelope), type)
```

with:

```qml
      control.failControl(runner.runId, Runs.controlError(envelope, req.action), type)
```

and replace its comment:

```qml
  // One run-control.py reply, whatever project is open. ok:true
  // means am has the request: pending stays until a snapshot settles it, and
  // the requested_at am gave it is remembered. Anything else ends it with a
  // sentence. Either way the runner goes, then refreshRequested("all"). A
  // reply for a request that is no longer the pending one changes nothing.
```

with:

```qml
  // One run-control.py reply, whatever project is open. ok:true
  // means am has the request: pending stays until a snapshot settles it, and
  // the requested_at am gave it is remembered. Anything else ends it with a
  // sentence (am's error through Runs.controlError with the request's action).
  // Either way the runner goes, then refreshRequested("all"). A reply for a
  // request that is no longer the pending one changes nothing.
```

- [ ] **Step 5: Name `reset` in the other comments**

Replace the header comment's first three lines:

```qml
// The run controls (S2 4.1), the cancel confirmation (S2 4.3) and the footer
// flash, for a run of any registered project. control(action, runId) starts a
// pause, resume or cancel of a run in `runs`, each on a HelperRunner of its
```

with:

```qml
// The run controls (S2 4.1), the cancel confirmation (S2 4.3), the Close
// dialog and the footer flash, for a run of any registered project.
// control(action, runId) starts a pause, resume, cancel or reset (the UI's
// Close) of a run in `runs`, each on a HelperRunner of its
```

Replace the comment on `control`:

```qml
  // Starts a pause, resume or cancel of one run in `runs`, of any project, and
  // returns whether it started: only when refusalOf(action, runId) is "".
  // The request acts on the run's repo_dir; a milestone resume reads the run
  // settings of the run's project.root. Confirming a cancel is the caller's job.
```

with:

```qml
  // Starts a pause, resume, cancel or reset of one run in `runs`, of any
  // project, and returns whether it started: only when refusalOf(action,
  // runId) is "". The request acts on the run's repo_dir; a milestone resume
  // reads the run settings of the run's project.root, and every other action
  // launches run-control at once with no extra argument. Confirming a cancel
  // or a reset is the caller's job.
```

Replace the comment on `settleAfterSnapshot`:

```qml
  // After every good snapshot: an acknowledged request is settled when its run
  // is gone from `runs`, when the run's state moved since the request started,
  // or (pause, cancel) when am marks its request handled. A request still in
  // flight is never settled by a snapshot: its buttons stay off until the reply.
```

with:

```qml
  // After every good snapshot: an acknowledged request is settled when its run
  // is gone from `runs`, when the run's state moved since the request started,
  // or (pause, cancel, reset) when am marks its request handled. A request
  // still in flight is never settled by a snapshot: its buttons stay off until
  // the reply.
```

- [ ] **Step 6: Run the whole store file to verify the new test passes and nothing else broke**

Run:
```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_control_store.qml 2>&1 | grep -E "^(FAIL|SKIP|Totals)|TypeError|ReferenceError"
```
Expected: no `FAIL` line, no `TypeError`/`ReferenceError`; three `SKIP` lines (`test_a_reset_launches_the_exact_argv`, `test_a_reset_settles_like_a_cancel`, `test_a_failed_reset_says_why_with_the_reset_sentence`); `Totals: 94 passed, 0 failed, 3 skipped` (93 before this task, which counts initTestCase and cleanupTestCase, plus `test_refusal_of_reset_keeps_the_order_and_reads_controls_close`).

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunControlStore.qml tests/core/stores/tst_run_control_store.qml
git commit -m "feat(runs): RunControlStore refuses, starts and settles a reset

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The Close dialog state (`closeRunId`, `closeOpen`, `closeError`, `closeAsk`, `closeKeep`, `closeConfirm`)

**Files:**
- Modify: `core/stores/RunControlStore.qml:48-53` (properties next to the cancel confirmation), after `confirmCancel` (`:333-347`, new functions)
- Modify: `tests/core/stores/tst_app_runs.qml:523-528` (`movedToControl`), `:564` (count)
- Test: `tests/core/stores/tst_run_control_store.qml` (C1 bare test at `:101-126`, header comment `:2-9`, the section Task 1 appended)

**Interfaces:**
- Consumes (Task 1): `refusalOf("reset", runId)` → `string`; `control("reset", runId)` → `bool`; test helpers `closeImplemented`, `parked(id)`, `closeReason(e)`; existing `flash(text)`, `ctlStore(entries)`, `snapshot(store, entries)`, `controlOf(store)`, `makeControl()`.
- Produces (for stories D and F): `property string closeRunId` (default `""`), `readonly property bool closeOpen` (`closeRunId !== ""`), `property string closeError` (default `""`), `function closeAsk(runId)` → `bool`, `function closeKeep()` → `undefined`, `function closeConfirm()` → `bool`.

- [ ] **Step 1: Write the failing tests**

(a) In `tests/core/stores/tst_run_control_store.qml`, test C1 `test_a_bare_control_store_has_nothing_pending_and_nothing_open`, replace:

```qml
    compare(c.cancelError, "")
    compare(c.flashText, "")
```

with:

```qml
    compare(c.cancelError, "")
    compare(c.closeRunId, "")
    compare(c.closeOpen, false)
    compare(c.closeError, "")
    compare(c.flashText, "")
```

(b) In the same file's header comment, replace:

```qml
// verify read and the Resume dialog, the still-waiting clock, the control error, the cancel
// confirmation, the footer flash, the notify switch and the run settings
```

with:

```qml
// verify read and the Resume dialog, the still-waiting clock, the control error, the cancel
// confirmation, the reset and the Close dialog, the footer flash, the notify switch and the run settings
```

(c) The file now ends with Task 1's last test:

```qml
    compare(spy.count, 3)
    compare(controlOf(store).controlRunners.length, 0)
  }
}
```

Replace those lines with:

```qml
    compare(spy.count, 3)
    compare(controlOf(store).controlRunners.length, 0)
  }

  // 3 (and Review Focus 1)
  function test_close_ask_on_a_refused_run_flashes_and_opens_nothing() {
    var store = ctlStore([running("r1")]); if (!store) return
    compare(controlOf(store).closeAsk("nope"), false)
    compare(controlOf(store).flashText, "This run is no longer in the snapshot")
    compare(controlOf(store).closeOpen, false)
    compare(controlOf(store).closeRunId, "")
    var bad = [undefined, null, 7, ""]
    for (var i = 0; i < bad.length; i++) {
      controlOf(store).flash("")
      compare(controlOf(store).closeAsk(bad[i]), false, String(bad[i]))
      compare(controlOf(store).flashText, "This run is no longer in the snapshot", String(bad[i]))
      compare(controlOf(store).closeOpen, false, String(bad[i]))
    }
    var reason = controlOf(store).refusalOf("reset", "r1")
    verify(reason !== "", "a running run cannot be closed")
    compare(controlOf(store).closeAsk("r1"), false)
    compare(controlOf(store).flashText, reason)
    compare(controlOf(store).closeOpen, false)
    compare(controlOf(store).closeError, "")
    compare(controlOf(store).controlRunners.length, 0)
    compare(Object.keys(controlOf(store).pending).length, 0)
  }

  // 4
  function test_a_refused_close_ask_leaves_an_open_dialog_alone() {
    var store = ctlStore([running("r1")]); if (!store) return
    controlOf(store).closeRunId = "r2"
    controlOf(store).closeError = "old"
    compare(controlOf(store).closeAsk("nope"), false)
    compare(controlOf(store).closeRunId, "r2")
    compare(controlOf(store).closeError, "old")
    compare(controlOf(store).closeOpen, true)
    compare(controlOf(store).closeAsk("r1"), false, "a running run")
    compare(controlOf(store).closeRunId, "r2")
    compare(controlOf(store).closeError, "old")
    compare(controlOf(store).controlRunners.length, 0)
  }

  // 5
  function test_close_keep_clears_every_field() {
    var store = ctlStore([running("r1")]); if (!store) return
    controlOf(store).closeRunId = "r1"
    controlOf(store).closeError = "old"
    compare(controlOf(store).closeOpen, true)
    controlOf(store).closeKeep()
    compare(controlOf(store).closeRunId, "")
    compare(controlOf(store).closeError, "")
    compare(controlOf(store).closeOpen, false)
    controlOf(store).closeKeep()
    compare(controlOf(store).closeRunId, "", "a second closeKeep is harmless")
    compare(controlOf(store).closeError, "")
    compare(controlOf(store).closeOpen, false)
    compare(controlOf(store).controlRunners.length, 0)
    compare(Object.keys(controlOf(store).pending).length, 0)
  }

  // 6
  function test_close_confirm_with_the_dialog_closed_does_nothing() {
    var store = ctlStore([running("r1")]); if (!store) return
    compare(controlOf(store).closeConfirm(), false)
    compare(controlOf(store).closeError, "")
    compare(controlOf(store).closeOpen, false)
    compare(controlOf(store).controlRunners.length, 0)
    compare(Object.keys(controlOf(store).pending).length, 0)
  }

  // 7
  function test_a_refused_reset_keeps_the_close_dialog_open_with_the_reason() {
    var store = ctlStore([running("r1")]); if (!store) return
    controlOf(store).closeRunId = "r1"
    var before = controlOf(store).pending
    var reason = controlOf(store).refusalOf("reset", "r1")
    verify(reason !== "", "a running run cannot be closed")
    compare(controlOf(store).closeConfirm(), false)
    compare(controlOf(store).closeOpen, true, "the dialog stays for the user to read why")
    compare(controlOf(store).closeRunId, "r1")
    compare(controlOf(store).closeError, reason)
    compare(controlOf(store).controlRunners.length, 0)
    verify(controlOf(store).pending === before, "pending unchanged")
  }

  // 8
  function test_close_confirm_on_a_run_gone_from_the_snapshot() {
    var store = ctlStore([running("r1")]); if (!store) return
    controlOf(store).closeRunId = "gone"
    compare(controlOf(store).closeConfirm(), false)
    compare(controlOf(store).closeError, "This run is no longer in the snapshot")
    compare(controlOf(store).closeOpen, true)
    compare(controlOf(store).closeRunId, "gone")
    compare(controlOf(store).controlRunners.length, 0)
  }

  // 9
  function test_the_close_and_cancel_dialogs_are_independent() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    compare(controlOf(store).openCancel("r1"), true)
    controlOf(store).cancelText = "can"
    controlOf(store).closeRunId = "r2"
    controlOf(store).closeError = "x"
    controlOf(store).closeKeep()
    compare(controlOf(store).cancelRunId, "r1", "closeKeep leaves the cancel dialog")
    compare(controlOf(store).cancelText, "can")
    compare(controlOf(store).cancelOpen, true)
    controlOf(store).closeRunId = "r2"
    controlOf(store).closeError = "x"
    compare(controlOf(store).closeConfirm(), false, "r2 is running: refused")
    compare(controlOf(store).cancelRunId, "r1", "a refused closeConfirm leaves the cancel dialog")
    compare(controlOf(store).cancelError, "")
    controlOf(store).closeCancel()
    compare(controlOf(store).cancelOpen, false)
    compare(controlOf(store).closeRunId, "r2", "closeCancel leaves the Close dialog")
    compare(controlOf(store).closeOpen, true)
    verify(controlOf(store).closeError !== "", "closeCancel leaves closeError")
    compare(controlOf(store).openCancel("r1"), true)
    compare(controlOf(store).closeRunId, "r2", "openCancel leaves the Close dialog")
  }

  // 10 (and Review Focus 4)
  function test_a_project_switch_a_new_run_list_and_a_control_reply_keep_the_close_dialog() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    controlOf(store).closeRunId = "r1"
    controlOf(store).closeError = "x"
    snapshot(store, [running("r2")])
    compare(controlOf(store).closeRunId, "r1", "a new run list without the run")
    compare(controlOf(store).closeError, "x")
    compare(controlOf(store).control("pause", "r2"), true)
    reply(controlOf(store).controlRunners[0].current, ctlFail("NotRunningError", "not running"), 0)
    compare(controlOf(store).lastControlErrorRunId, "r2")
    compare(controlOf(store).closeRunId, "r1", "a failed control reply")
    compare(controlOf(store).closeError, "x")
    store.project = rootB
    compare(controlOf(store).closeRunId, "r1", "a project switch")
    compare(controlOf(store).closeError, "x")
    store.project = ""
    compare(controlOf(store).closeRunId, "r1", "closing the project")
    compare(controlOf(store).closeError, "x")
    compare(controlOf(store).closeOpen, true)
  }

  // 11
  function test_close_ask_opens_for_a_closable_run() {
    if (!closeImplemented) skip("controls().close not implemented yet (story B)")
    var store = ctlStore([parked("r1"), parked("r2")]); if (!store) return
    controlOf(store).closeRunId = "r2"
    controlOf(store).closeError = "old"
    compare(controlOf(store).closeAsk("r1"), true)
    compare(controlOf(store).closeRunId, "r1", "replaces the run the dialog was open for")
    compare(controlOf(store).closeOpen, true)
    compare(controlOf(store).closeError, "", "cleared on opening")
    compare(controlOf(store).flashText, "")
    compare(controlOf(store).controlRunners.length, 0, "asking starts nothing")
    compare(Object.keys(controlOf(store).pending).length, 0)
  }

  // 12 (and Review Focus 2)
  function test_close_confirm_starts_one_reset_and_closes() {
    if (!closeImplemented) skip("controls().close not implemented yet (story B)")
    var store = ctlStore([parked("r1")]); if (!store) return
    compare(controlOf(store).closeAsk("r1"), true)
    compare(controlOf(store).closeConfirm(), true)
    compare(controlOf(store).controlRunners.length, 1)
    compare(argv(controlOf(store).controlRunners[0].current), tc.ctlCmd + "reset|r1|" + tc.rootA)
    compare(controlOf(store).pending.r1, "reset")
    compare(controlOf(store).closeOpen, false)
    compare(controlOf(store).closeRunId, "")
    compare(controlOf(store).closeError, "")
    compare(controlOf(store).closeConfirm(), false, "a second confirm finds the dialog closed")
    compare(controlOf(store).controlRunners.length, 1, "no second reset")
    compare(controlOf(store).closeAsk("r1"), false, "a pending reset refuses a new ask")
    compare(controlOf(store).flashText, "A request for this run is pending")
    compare(controlOf(store).closeOpen, false)
  }

  // 16
  function test_a_run_that_changed_under_the_open_close_dialog_refuses_the_confirm() {
    if (!closeImplemented) skip("controls().close not implemented yet (story B)")
    var store = ctlStore([parked("r1")]); if (!store) return
    compare(controlOf(store).closeAsk("r1"), true)
    snapshot(store, [running("r1")])
    var reason = controlOf(store).refusalOf("reset", "r1")
    verify(reason !== "", "a running run cannot be closed")
    compare(controlOf(store).closeConfirm(), false)
    compare(controlOf(store).closeError, reason)
    compare(controlOf(store).closeOpen, true)
    compare(controlOf(store).closeRunId, "r1")
    compare(controlOf(store).controlRunners.length, 0)
    compare(controlOf(store).pending.r1, undefined)
    snapshot(store, [])
    compare(controlOf(store).closeConfirm(), false)
    compare(controlOf(store).closeError, "This run is no longer in the snapshot")
    compare(controlOf(store).closeOpen, true)
    compare(controlOf(store).controlRunners.length, 0)
  }

  // 17
  function test_a_pending_request_refuses_the_close_confirm() {
    if (!closeImplemented) skip("controls().close not implemented yet (story B)")
    var store = ctlStore([parked("r1")]); if (!store) return
    compare(controlOf(store).closeAsk("r1"), true)
    compare(controlOf(store).control("resume", "r1"), true)
    compare(controlOf(store).closeConfirm(), false)
    compare(controlOf(store).closeError, "A request for this run is pending")
    compare(controlOf(store).closeOpen, true)
    compare(controlOf(store).controlRunners.length, 1, "only the resume's runner")
    compare(controlOf(store).controlRunners[0].action, "resume")
    compare(controlOf(store).pending.r1, "resume")
  }
}
```

(d) In `tests/core/stores/tst_app_runs.qml`, replace:

```qml
    "resumeAllowNoVerification", "resumeError", "resumeOpenFor", "resumeClose", "resumeConfirm", "resumeSaveRunner"]
```

with:

```qml
    "resumeAllowNoVerification", "resumeError", "resumeOpenFor", "resumeClose", "resumeConfirm", "resumeSaveRunner",
    "closeRunId", "closeOpen", "closeError", "closeAsk", "closeKeep", "closeConfirm"]
```

and replace:

```qml
    compare(names.length, 91, "88 moved members and 3 handles")
```

with:

```qml
    compare(names.length, 97, "94 moved members and 3 handles")
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run:
```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_control_store.qml 2>&1 | grep -E "^(FAIL|SKIP|Totals)|TypeError"
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_app_runs.qml StoresAppRuns::test_each_owner_answers_to_its_moved_members StoresAppRuns::test_the_run_store_has_none_of_the_moved_members 2>&1 | grep -E "^(FAIL|Totals)|Actual|Expected"
```
Expected: in the store file, `FAIL` for `test_a_bare_control_store_has_nothing_pending_and_nothing_open` (`closeRunId` is `undefined`) and for tests 3-10 (`TypeError: Property 'closeAsk' of object ... is not a function`, or `closeOpen` undefined); tests 11, 12, 16, 17 `SKIP`. In `tst_app_runs.qml`, `FAIL` for `test_each_owner_answers_to_its_moved_members` with `Actual (): closeRunId, closeOpen, closeError, closeAsk, closeKeep, closeConfirm`; `test_the_run_store_has_none_of_the_moved_members` passes.

- [ ] **Step 3: Add the Close dialog properties next to the cancel confirmation**

In `core/stores/RunControlStore.qml`, replace:

```qml
  property string cancelText: ""
  property string cancelError: ""
  // The footer flash: why a run key was refused. flashTimer clears it.
```

with:

```qml
  property string cancelText: ""
  property string cancelError: ""
  // The Close dialog (a reset, the UI's Close, asks first): the run it asks
  // about ("" = closed) and why the last confirm was refused. No typed word.
  // Independent of the cancel confirmation; a project switch or a new run
  // list changes neither.
  property string closeRunId: ""
  readonly property bool closeOpen: control.closeRunId !== ""
  property string closeError: ""
  // The footer flash: why a run key was refused. flashTimer clears it.
```

- [ ] **Step 4: Add `closeAsk`, `closeKeep` and `closeConfirm` after `confirmCancel`**

Replace:

```qml
    control.closeCancel()
    return true
  }

  // ---- resume dialog
```

with:

```qml
    control.closeCancel()
    return true
  }

  // Opens the Close dialog for a run that can be reset now, replacing any run
  // it was open for, and returns true; otherwise flashes why not, leaves any
  // dialog as it is and returns false. Starts no request.
  function closeAsk(runId) {
    var reason = control.refusalOf("reset", runId)
    if (reason !== "") {
      control.flash(reason)
      return false
    }
    control.closeError = ""
    control.closeRunId = runId
    return true
  }

  // Dismisses the Close dialog (its Keep button). Starts nothing; safe when
  // it is already closed. Not closeCancel, which closes the cancel dialog.
  function closeKeep() {
    control.closeRunId = ""
    control.closeError = ""
  }

  // The Close dialog's confirm. The run is checked again: one that changed or
  // vanished under the open dialog, or got a request pending, keeps it open
  // with the reason. A started reset closes it.
  function closeConfirm() {
    if (control.closeRunId === "") return false
    var reason = control.refusalOf("reset", control.closeRunId)
    if (reason !== "") {
      control.closeError = reason
      return false
    }
    if (!control.control("reset", control.closeRunId)) {
      control.closeError = "The run could not be closed"
      return false
    }
    control.closeKeep()
    return true
  }

  // ---- resume dialog
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_control_store.qml 2>&1 | grep -E "^(FAIL|SKIP|Totals)|TypeError|ReferenceError"
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_app_runs.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"
```
Expected: store file — no `FAIL`, no `TypeError`/`ReferenceError`, exactly 7 `SKIP` lines (Task 1's tests 13, 14, 15 and this task's 11, 12, 16, 17), `Totals: 102 passed, 0 failed, 7 skipped`. `tst_app_runs.qml` — `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add core/stores/RunControlStore.qml tests/core/stores/tst_run_control_store.qml tests/core/stores/tst_app_runs.qml
git commit -m "feat(runs): hold the Close dialog's state in RunControlStore

closeAsk, closeKeep and closeConfirm next to the cancel confirmation.
The dismiss method is closeKeep: closeCancel already closes the cancel dialog.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Documentation and the store-surface guards

**Files:**
- Modify: `ui/components/runControlFacts.js:16` (comment on `pendingOf`)
- Modify: `docs/architecture.md:93` (the `RunControlStore.qml` bullet)
- Modify: `tests/architecture/test_run_store_callers.py` (`MOVED`, after `"relaunchOpenFor": "runDispatch",`)
- Test: `tests/ui/components/tst_run_control_facts.qml:20-29` (`test_pending_of`), `tests/architecture/test_run_store_callers.py`, `tests/architecture/test_run_store_docs.py`

**Interfaces:**
- Consumes (Task 2): member names `closeRunId`, `closeOpen`, `closeError`, `closeAsk`, `closeKeep`, `closeConfirm` on `app.runControl`; Task 1's `reset` action and `controlError(envelope, action)` call.
- Produces: nothing new in code; the guards now forbid `ui/` from reaching the six names through `.runs.`.

These steps pin documented behavior; no production behavior changes, so the new assertions pass as soon as they are written. That is expected for this task: `pendingOf` already passes any string through, and `MOVED` is a guard on future callers.

- [ ] **Step 1: Pin `pendingOf("reset")`**

In `tests/ui/components/tst_run_control_facts.qml`, replace:

```qml
    compare(Facts.pendingOf({ r1: "pause" }, r), "pause")
    compare(Facts.pendingOf({ r2: "pause" }, r), "")
```

with:

```qml
    compare(Facts.pendingOf({ r1: "pause" }, r), "pause")
    compare(Facts.pendingOf({ r1: "reset" }, r), "reset", "a reset passes through as the store says it")
    compare(Facts.pendingOf({ r2: "pause" }, r), "")
```

In `ui/components/runControlFacts.js`, replace:

```js
// The action pending for the run ("pause" | "resume" | "cancel"), or "".
```

with:

```js
// The action pending for the run ("pause" | "resume" | "cancel" | "reset"), or "".
```

- [ ] **Step 2: Run it**

Run:
```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_run_control_facts.qml 2>&1 | grep -E "^(FAIL|Totals)"
```
Expected: `Totals: 7 passed, 0 failed, 0 skipped` (the same count as before: the new line is one more `compare` inside `test_pending_of`).

- [ ] **Step 3: Add the six names to `MOVED`**

In `tests/architecture/test_run_store_callers.py`, replace:

```python
    "relaunchOpenFor": "runDispatch",
}
```

with:

```python
    "relaunchOpenFor": "runDispatch",
    "closeRunId": "runControl",
    "closeOpen": "runControl",
    "closeError": "runControl",
    "closeAsk": "runControl",
    "closeKeep": "runControl",
    "closeConfirm": "runControl",
}
```

- [ ] **Step 4: Edit the `RunControlStore.qml` bullet in `docs/architecture.md` (line 93)**

Make these seven replacements inside the one bullet; each old string occurs exactly once in the file. Do not add a line break: the bullet stays one line.

1. Replace `` `control(action, runId)` starts a `pause`, `resume` or `cancel` of a run in `runs` and returns whether it did; ``
   with `` `control(action, runId)` starts a `pause`, `resume`, `cancel` or `reset` (the UI's Close; `close` itself is no store action) of a run in `runs` and returns whether it did; ``
2. Replace `Confirming a cancel is the caller's job.`
   with `Confirming a cancel or a reset is the caller's job.`
3. Replace ``Pause, cancel and a `--card` run's resume``
   with ``Pause, cancel, reset and a `--card` run's resume``
4. Replace `or (pause, cancel) its am request handled`
   with `or (pause, cancel, reset) its am request handled`
5. Replace ``sets `lastControlError` (the `Runs.controlError` sentence)``
   with ``sets `lastControlError` (the `Runs.controlError(envelope, action)` sentence, `action` the request's)``
6. Replace ``then the `Runs.controls` reason; `Unknown control` for another action);``
   with ``then the `Runs.controls` reason, its `close` entry for a `reset`; `Unknown control` for another action, `close` included);``
7. Replace `a project switch keeps the dialog and the flash.`
   with ``a project switch keeps the dialog and the flash. The Close dialog is the store's too: `closeRunId` (`""` = closed), `closeOpen` and `closeError`. `closeAsk(runId)` opens it only when `refusalOf("reset", runId)` is `""`, replacing any run it was open for and clearing `closeError`; otherwise it flashes the refusal, leaves the dialog as it is and returns false; it starts no request. `closeKeep()` closes it (the cancel dialog's `closeCancel()` is another method). `closeConfirm()` has no typed word: it checks `refusalOf("reset", …)` again -- a run that changed or vanished under the dialog, or got a request pending, keeps it open with `closeError` -- then calls `control("reset", …)` and closes it. The Close and cancel dialogs never change each other's fields, and a project switch or a new `runs` changes neither.``

- [ ] **Step 5: Run the architecture guards**

Run:
```bash
timeout 300 uv run --with pytest python3 -m pytest tests/architecture/test_run_store_callers.py tests/architecture/test_run_store_docs.py -q
grep -c '^- `RunControlStore.qml`' docs/architecture.md
```
Expected: all pass (`... passed`, 0 failed); the `grep -c` prints `1`.

- [ ] **Step 6: Run the whole suite**

Run: `timeout 600 bash tests/run.sh 2>&1 | grep -E "passed|failed|^FAIL|^== |TypeError|ReferenceError" | grep -vE "^== " ; echo "exit=${PIPESTATUS[0]}"`

Expected: pytest line `N passed` with no `failed`; every QML `Totals:` line has `0 failed`; no `FAIL`, `TypeError` or `ReferenceError`; `tst_run_control_store.qml` reports 7 skipped (or 0 once story B has landed); `exit=0`. In particular the existing cancel-dialog tests (`test_open_cancel_opens_only_for_a_cancellable_run`, `test_confirm_cancel_needs_the_word_then_starts_the_cancel_and_closes`, `test_a_project_switch_keeps_the_dialog_the_flash_the_control_error_and_the_requests`) still call `closeCancel()` and pass, and `tst_run_row_contract.qml` passes unmodified.

- [ ] **Step 7: Commit**

```bash
git add ui/components/runControlFacts.js tests/ui/components/tst_run_control_facts.qml tests/architecture/test_run_store_callers.py docs/architecture.md
git commit -m "docs(runs): document reset and the Close dialog on RunControlStore

pendingOf names reset; MOVED and the architecture bullet cover the six
Close dialog members.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Spec coverage check

| Spec item | Task |
|---|---|
| `refusalOf("reset")`, order, `close` → `Unknown control`, inherited ids | 1 (test 2) |
| `control("reset")` argv, no settings step, no verify flags | 1 (test 13) |
| `controlReplied` passes the action; ok / ok:false / unreadable replies; one refresh | 1 (step 4, test 15) |
| Settling like cancel (state change, request row by `requested_at` or last `reset` row, run gone) | 1 (test 14) |
| Close dialog members and their rules | 2 (tests 1, 3-12, 16, 17) |
| Close and cancel dialogs independent; project switch and new `runs` change nothing | 2 (tests 9, 10) |
| Header / `control` / `refusalOf` / `settleAfterSnapshot` comments | 1 (steps 3-5), 2 (step 3) |
| `pendingOf` comment and test 18 | 3 (step 1) |
| `docs/architecture.md` bullet, one top-level bullet | 3 (step 4-5) |
| `MOVED` and `movedToControl` | 3 (step 3), 2 (step 1d) |
| Existing tests pass unmodified (test 20) | 3 (step 6) |
| `The run could not be closed` (defensive; unreachable while `refusalOf` and `control` agree) | 2 (step 4, code only) |
<!-- task-pipeline: validated -->
