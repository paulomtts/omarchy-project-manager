# 2.4 RunAlertsStore: toasts only (card e9513ddf)

Narrowed from `docs/superpowers/specs/2026-10-05-alerts-panel-closed-design.md` (below "the
parent"): Behaviour, "The panel" (lines 128-130: `RunAlertsStore` keeps raising toasts while
the panel is open, unchanged, but no longer runs `notify.py`); Architecture, the
`RunAlertsStore.qml` bullet (lines 158-160: "drops the `notify.py` path; toasts unchanged");
Testing, the `tst_run_alerts_store.qml` item (line 206: "an alert raises a toast and no
`notify.py`"). Parent story bd7304ee ("Alerts service"). Blocked by 8a6996cc (2.3, done:
`RunAlertsService` now owns the `notify.py` path, one `HelperRunner` per launch).

This card makes **`RunAlertsStore` a toast store only**: no alert it raises launches anything.

## Starting point

- `core/stores/RunAlertsStore.qml` (172 lines). Inputs: `backendDir` (l.23), `active` (l.24),
  `notifyOnEscalation` (l.25), `projectRoots` (l.26). Notify path: `readonly property alias
  notifyRunners: notifyState.runners` (l.34); in `raiseAlerts` the line
  `if (alerts.notifyOnEscalation) alerts.notify(a)` (l.104); `notify(alert)` and
  `dropNotifyRunner(runner)` (l.124-136); the `notifyState` `QtObject` (l.154-158); the
  `notifyC` Component with its `HelperRunner { script: backendDir + "runs/notify.py"; guard: "" }`
  (l.160-171). `backendDir` and `notifyOnEscalation` are read nowhere else in the store.
  Header comment l.6-19 and the `raiseAlerts` comment l.91-93 describe the notification.
- `core/stores/App.qml` l.144-152: composes `runAlerts` with `backendDir: app.backendDir`,
  `active: app.panelOpen`, `notifyOnEscalation: app.runControl.notifyOnEscalation`,
  `projectRoots: app.runs.projectRoots`; the comment above it (l.144-147) names the backend
  directory and the notify switch as hand-ins.
- The notify switch itself lives on `RunControlStore` (`notifyOnEscalation`, load on opening,
  `setNotifyOnEscalation`, `settingsLoadRunner` / `settingsSaveRunner`). It is untouched.
- `core/stores/RunAlertsService.qml` reads the setting itself (`get-global-settings`) and runs
  `notify.py`; untouched.
- Test stubs: `Process` spawns nothing (`tests/stubs/Quickshell/Io/Process.qml`); a
  `HelperRunner`'s process is played with `argv(proc)` / `reply(proc, text, code)`
  (`tests/core/stores/tst_run_alerts_store.qml` l.73-79). Test runner: `bash tests/run.sh
  [path-substring]` (pytest, incl. `tests/architecture`, then each `tst_*.qml` offscreen).

## Constraints

- Layering per `docs/architecture.md`: a store imports only `QtQml`, `Quickshell`,
  `Quickshell.Io` and `../domain`; `tests/architecture` must pass (no duplicated components,
  icon glyph rules, `test_layers.py`, `test_run_store_callers.py`, `test_run_store_docs.py`).
- Comments and docstrings state the contract only, no history or narrative (card).
- TDD: the tests below are written and seen failing before the store changes (card).
- Toast behaviour is unchanged: arming, `snapshotReplied`, `pruneArmed`, `raiseAlerts`'
  toast queue (one per run, at most 3, `key` only grows), `toastMs` 8000, `toastTimer`
  (250 ms, only while `active` and a toast shows), `expireToasts`, `dismissToast`,
  `dismissAllToasts`, open/close disarming (parent l.128-129, "unchanged").
- The notify switch's load/save stays on `RunControlStore` (card).
- Gate: `bash tests/run.sh` green.

## Decision: the store's notify-only inputs go with the path

After the path goes, `notifyOnEscalation` and `backendDir` are inputs nothing in the store
reads. The card removes "the notify.py path and its runners"; an input that only fed that path
is part of it, and keeping it would leave a documented contract ("App hands it the switch")
that does nothing. So:

- `RunAlertsStore` drops `notifyOnEscalation` and `backendDir`; `App` drops those two bindings.
- `RunControlStore.notifyOnEscalation` (the switch) is unchanged and still loads and saves.

Consequence for the card's test line ("with the switch on"): the store alone has no switch to
turn on any more. The switch-on case is pinned where the switch still exists: through `App`
with `app.runControl.notifyOnEscalation` true (`tst_app_runs.qml`), and in the store's own file
through the store wired the way `App` wires it, asserting it answers to no switch.

## Behaviour

### Public surface of `RunAlertsStore` after the change

- Inputs: `active`, `projectRoots`. Nothing else is handed in.
- State: `armedRoots`, `alertsArmed`, `toasts`, `toastMs`, `toastTimer`.
- Functions: `snapshotReplied(root, outcome, previousRuns, runs)`, `pruneArmed()`,
  `raiseAlerts(items)`, `expireToasts(nowMs)`, `dismissToast(key)`, `dismissAllToasts()`.
- Gone (each reads as `undefined` on the store): `notifyRunners`, `notify`,
  `dropNotifyRunner`, `notifyOnEscalation`, `backendDir`.
- The store declares no `Component` and creates no `HelperRunner` or `Process`: its `data`
  holds no object with a `script` or `command` property and no `Component`.
- `toastTimer` remains the store's only timer.

### Raising

- `raiseAlerts(items)` gives each alert its toast exactly as before and launches nothing, for
  any number of alerts (including more than three, whose earliest toasts are capped away).
- An `ok` reply for an armed root while `active` raises its `Runs.newAlerts` as toasts and
  launches nothing; while closed it raises nothing and launches nothing (unchanged).

### App

- `app.runAlerts` is composed with `active: app.panelOpen` and
  `projectRoots: app.runs.projectRoots` only. Its comment names the panel-open flag and the
  registry as the hand-ins and the routing of `runs.snapshotReplied`.
- With `app.runControl.notifyOnEscalation` true or false, an escalation reaching `app.runAlerts`
  through a snapshot raises a toast and `app.runAlerts` launches no `notify.py`.
- Toggling `app.runControl.setNotifyOnEscalation(...)` still loads and saves as today
  (`tst_runs_flow.qml` test at l.819 and `tst_app_runs.qml` A8's load half unchanged).

### Docs

- `core/stores/RunAlertsStore.qml` header: the toasts, arming and the inputs `active` and
  `projectRoots`; no mention of `notify.py`, the notify switch or the backend directory.
  `raiseAlerts` comment: drop "With the setting on, each alert also notifies."
- `docs/architecture.md` l.93 (`RunAlertsStore.qml` paragraph): "the run toasts and their
  arming" (not "and the desktop notification"); `App` hands it `active` and `projectRoots`
  only; delete the final sentence about `notifyOnEscalation` / `notify.py` / `notifyRunners`.
  Search the rest of `docs/architecture.md` for `runAlerts.notifyOnEscalation`,
  `notifyRunners` and "binds app.runAlerts" and remove any claim that `App` hands the switch to
  the alerts store. l.168 (the Runs screen's switch wording) is not touched.

## Tests

All QML tests run through `bash tests/run.sh`; the architecture test through the same script's
pytest pass.

### `tests/core/stores/tst_run_alerts_store.qml` (store tier: the store's own contract)

- Header comment l.1-6: drop "and the notify.py desktop notification"; drop the
  `notifyCmd` property (l.18) and `backendDir` from `makeAlerts()` and `wireAlerts()` (they set
  a property that no longer exists; `wireAlerts`' comment drops "backendDir copied" and
  "notifyOnEscalation is left to each test").
- S1 `test_a_bare_alerts_store_is_disarmed_and_empty`: replace the `notifyRunners` and
  `notifyOnEscalation` asserts with `typeof a.notifyRunners`, `a.notify`,
  `a.dropNotifyRunner`, `a.notifyOnEscalation`, `a.backendDir` all `"undefined"`. Everything
  else in S1 unchanged.
- New, beside S2: `test_the_store_declares_no_helper_process` — no entry of `a.data` has a
  `script` or `command` property or is a `Component` (`typeof o.createObject === "function"`).
  Store tier because it pins the store's own declarations.
- Drop the `notifyOnEscalation = true` lines and the `notifyRunners` asserts from
  `test_an_ok_reply_while_closed_changes_nothing` (l.112-122),
  `test_the_first_ok_reply_of_a_root_while_open_only_arms_it` (l.125-135) and
  `test_an_armed_roots_ok_reply_raises_new_alerts_with_the_projects_name` (l.159); their
  toast and arming asserts stay as they are.
- S12 `test_notifications_follow_the_switch` (l.275-291) is replaced by
  `test_an_alert_raises_a_toast_and_launches_nothing`: an armed store, a run that turns
  escalated and one that dies in one reply → `toastIdsOf(a)` is the two ids, the store still
  declares no helper process (same check as above), and `a.notify` is undefined. Store tier:
  this is the card's named test.
- Through-RunStore tests: in `test_an_escalation_in_another_project_raises_one_toast_with_its_project`
  (l.696-707) and `test_a_run_listed_under_two_roots_alerts_once_under_the_first`
  (l.759-772) drop the `notifyOnEscalation` assignment and the `notifyRunners` asserts; toast
  asserts unchanged.
- The "alerts: the desktop notifications (S2 4.4)" section (l.853-900):
  `test_with_the_setting_on_each_alert_launches_its_own_notification` becomes
  `test_every_alert_toasts_and_none_launches_a_notification`: two alerts in one snapshot →
  toasts `a,b`; five alerts in one snapshot → three toasts (the last three); in both, the
  alerts store declares no helper process. `test_no_notification_while_the_panel_is_closed`
  becomes `test_no_toast_while_the_panel_is_closed_and_nothing_launched` (no
  `notifyOnEscalation`; toasts empty). Section heading becomes "alerts: toasts only (S2 4.4)".
- Every other toast test in the file is unchanged.

### `tests/core/stores/tst_app_runs.qml` (App tier: the wiring between App, run control and alerts)

- Drop `notifyCmd` (l.194-195) if nothing else uses it.
- `test_an_escalation_through_app_notifies_only_with_the_switch_on` (l.464-476) becomes
  `test_an_escalation_through_app_toasts_with_the_switch_off_or_on`: switch off → one toast;
  switch loaded on (`settingsLoadRunner` reply `{notifyOnEscalation: true}`) → second
  escalation gives two toasts; `typeof app.runAlerts.notifyRunners === "undefined"` and
  `app.runAlerts` declares no helper process throughout. This is the card's "switch on" case.
- `movedToAlerts` (l.502-503): drop `"notifyRunners"` and `"notify"`;
  `test_the_run_store_has_none_of_the_moved_members` count becomes 64 ("61 moved members and 3
  handles").
- A1 `test_app_composes_run_alerts_wired_to_the_run_store` (l.537-555): drop the
  `backendDir` and `notifyOnEscalation` asserts and the `app.backendDir = "/other/"` step;
  add `typeof app.runAlerts.backendDir` and `typeof app.runAlerts.notifyOnEscalation` are
  `"undefined"`. `active` and `projectRoots` asserts unchanged.
- A8 `test_the_alerts_switch_is_run_controls` (l.698-709): drop the
  `app.runAlerts.notifyOnEscalation` line; the run-control load asserts stay.
- A9 `test_with_run_controls_switch_on_an_escalation_launches_notify` (l.711-729) becomes
  `test_with_run_controls_switch_on_an_escalation_only_toasts`: switch loaded on, escalation →
  one toast and no helper process on `app.runAlerts`; switch saved off, second escalation →
  two toasts, still none.

### `tests/ui/tst_runs_flow.qml` (UI flow tier: the switch in the real screen)

- 29 `test_with_the_setting_on_an_escalation_also_notifies` (l.688-706) becomes
  `test_with_the_setting_on_an_escalation_only_toasts`: switch saved on → escalation shows one
  toast, `typeof p.app.runAlerts.notifyRunners === "undefined"`; switch saved off → two toasts.

### `tests/architecture/test_run_store_callers.py` (architecture tier: the moved-members map)

- Drop `"notifyRunners": "runAlerts"` (l.48) and `"notify": "runAlerts"` (l.58) from `MOVED`;
  they name members no owner has. The other checks in that file are unchanged and pass.

## Error paths

None new: the store had no error path on the notify side (replies were unread). An object that
still assigns `notifyOnEscalation` or `backendDir` on `RunAlertsStore` would fail to load, so
every such binding (`App.qml`, `makeAlerts`, `wireAlerts`) is removed in the same change.

## Out of scope

- `core/backend/runs/notify.py`, `core/stores/RunAlertsService.qml` (card 2.3) and the shell
  composition of the service.
- `RunControlStore`'s switch, its load/save and its flash text.
- The Runs screen switch label and caption ("Desktop notifications" / "From the background,
  panel open or closed", parent l.129-130, l.162) and `tst_runs_screen.qml`: a sibling card.
- `docs/architecture.md` l.168 (switch wording) and the second-entry-point paragraph (parent
  l.163-164): sibling cards.
- Toast dismissal advancing the persisted cursor (parent l.159-160, milestone 4).

## For the planner

One task is enough: the test edits across the four test files, seen failing (the new
`undefined` asserts fail while the members exist), then the store, `App.qml` and the docs
change together, since removing a property breaks every binding to it at once. Run
`bash tests/run.sh` for the full gate at the end.

---

# 2.4 RunAlertsStore: toasts only Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `RunAlertsStore` raises toasts only: it drops the `notify.py` path, its runners and the two inputs that only fed it (`notifyOnEscalation`, `backendDir`), and `App` stops binding them.

**Architecture:** One task. The tests in four files are rewritten first and seen failing (the new `typeof ... === "undefined"` asserts and the "declares no helper process" check fail while the `notify` members and the `notifyC` `Component` exist). Then the store, `App.qml`'s `runAlerts` block and `docs/architecture.md` change together, because removing a property breaks every binding to it at once.

**Tech Stack:** QML (Qt 6, Quickshell `Scope`), QtTest via `qmltestrunner` (offscreen, stubbed `Process`), pytest architecture tests; all run by `bash tests/run.sh [path-substring]`.

**Spec:** `docs/superpowers/specs/2-4-runalertsstore-e9513ddf.md` (prepended above).

## Global Constraints

- Layering per `docs/architecture.md`: a store imports only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain`; `tests/architecture` must pass (no duplicated components, icon glyph rules, `test_layers.py`, `test_run_store_callers.py`, `test_run_store_docs.py`).
- Comments and docstrings state the contract only, no history or narrative.
- TDD: the tests are written and seen failing before the store changes.
- Toast behaviour is unchanged: arming, `snapshotReplied`, `pruneArmed`, `raiseAlerts`' toast queue (one per run, at most 3, `key` only grows), `toastMs` 8000, `toastTimer` (250 ms, only while `active` and a toast shows), `expireToasts`, `dismissToast`, `dismissAllToasts`, open/close disarming.
- The notify switch's load/save stays on `RunControlStore` (`notifyOnEscalation`, `setNotifyOnEscalation`, `settingsLoadRunner`, `settingsSaveRunner`): untouched.
- Out of scope, do not edit: `core/backend/runs/notify.py`, `core/stores/RunAlertsService.qml`, `core/stores/RunControlStore.qml`, `ui/`, `tests/ui/screens/tst_runs_screen.qml`, `docs/architecture.md` line 168 (the Runs screen switch wording) and the `RunAlertsService.qml` bullet (line 95).
- Gate: `bash tests/run.sh` green.

## Review Focus

1. More than three alerts in one reply: the earliest toasts are capped away and still nothing is launched for any of the five -- pinned in `test_every_alert_toasts_and_none_launches_a_notification` (five-alert half).
2. The switch on in `RunControlStore` (loaded or saved on) while an escalation arrives through `App`: a toast, no `notify.py` from `app.runAlerts` -- pinned in `tst_app_runs.qml` (`test_an_escalation_through_app_toasts_with_the_switch_off_or_on`, A9) and `tst_runs_flow.qml` 29.
3. A leftover binding to a removed property (`App.qml`, `makeAlerts`, `wireAlerts`) makes the object fail to load; `tests/run.sh` flags `non-existent` / `Unable to assign` lines -- pinned by every `tst_app_runs.qml` test (App must load) and A1's new `typeof ... "undefined"` asserts.
4. `raiseAlerts` called directly (not through a snapshot) launches nothing -- pinned in `test_an_alert_raises_a_toast_and_launches_nothing` (its last half).
5. A closed panel with alerts arriving: no toast and nothing launched -- pinned in `test_no_toast_while_the_panel_is_closed_and_nothing_launched`.

---

### Task 1: RunAlertsStore drops the notify.py path

**Files:**
- Modify: `tests/core/stores/tst_run_alerts_store.qml` (header l.1-6, `notifyCmd` l.18, `makeAlerts` l.21-25, `argv` l.72-73, S1 l.83-98, new test after S2 l.109, S3 l.111-122, S4 l.124-135, S5 l.159, S12 l.274-291, `wireAlerts` l.308-320, l.699 + l.705-706, l.761 + l.766 + l.771, section l.852-901)
- Modify: `tests/core/stores/tst_app_runs.qml` (`notifyCmd` l.194-195, l.464-476, l.502-503, `answered` l.511-515, l.517-520, A1 l.537-555, A8 l.698-709, A9 l.711-729)
- Modify: `tests/ui/tst_runs_flow.qml` (test 29, l.687-706)
- Modify: `tests/architecture/test_run_store_callers.py` (`MOVED`, l.48 and l.53)
- Modify: `core/stores/RunAlertsStore.qml` (whole file)
- Modify: `core/stores/App.qml` (l.144-152)
- Modify: `docs/architecture.md` (l.92 one sentence, l.93)

**Interfaces:**
- Consumes: nothing from other tasks. Existing test helpers used unchanged: in `tst_run_alerts_store.qml` `makeAlerts()`, `armedAlerts(roots)`, `runningRun/deadRun/escalatedRun(id, root)`, `toastIdsOf(a)`, `armedStore(entries)`, `snapshot(store, entries)`, `alerts(store)`, `toastIds(store)`, `makeWithProject(root)`, `running(id)`, `dead(id)`, `escalated(id)`, `okReply(entries)`, `reply(proc, text, code)`; in `tst_app_runs.qml` `openApp(aRuns, bRuns)`, `snapshot(app, text)`, `listReply(aRuns, bRuns)`, `runningIn(id)`, `escalatedIn(id)`, `reply`, `argv`, `makeBare()`; in `tst_runs_flow.qml` `make()`, `feed(p, entries)`, `snapEntry(id, status, live, projectName)`, `reply`.
- Produces: `RunAlertsStore` public surface: inputs `active`, `projectRoots`; state `armedRoots`, `alertsArmed`, `toasts`, `toastMs`, `toastTimer`; functions `snapshotReplied(root, outcome, previousRuns, runs)`, `pruneArmed()`, `raiseAlerts(items)`, `expireToasts(nowMs)`, `dismissToast(key)`, `dismissAllToasts()`. Gone: `notifyRunners`, `notify`, `dropNotifyRunner`, `notifyOnEscalation`, `backendDir`. New test helper `helpersOf(a)` (returns an array of strings, one per entry of `a.data` that has a `script` or `command` property or is a `Component`), defined separately in `tst_run_alerts_store.qml` and `tst_app_runs.qml`.

#### Part A: the store tier tests (`tests/core/stores/tst_run_alerts_store.qml`)

- [ ] **Step 1: Header comment, `notifyCmd`, `makeAlerts`**

Replace lines 1-6:

```qml
// tests/core/stores/tst_run_alerts_store.qml
// The run alerts store: per-project arming, the toast queue, the toast expiry
// and the notify.py desktop notification. Built alone and driven through
// snapshotReplied, active and projectRoots; and, through a RunStore wired to
// it the way App wires them, a real snapshot reply turning into a toast.
// Stubbed Process objects stand in for every helper.
```

with:

```qml
// tests/core/stores/tst_run_alerts_store.qml
// The run alerts store: per-project arming, the toast queue and the toast
// expiry; it launches no helper. Built alone and driven through
// snapshotReplied, active and projectRoots; and, through a RunStore wired to
// it the way App wires them, a real snapshot reply turning into a toast.
// Stubbed Process objects stand in for every helper.
```

Delete line 18 entirely:

```qml
  property string notifyCmd: "python3|/plugin/core/backend/runs/notify.py|"
```

In `makeAlerts()` replace

```qml
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }

  // A root's registry entry: rootA is "alpha", rootB "beta", any other "proj".
```

with

```qml
    return comp.createObject(tc)
  }

  // A root's registry entry: rootA is "alpha", rootB "beta", any other "proj".
```

- [ ] **Step 2: Replace the `argv` helper with `helpersOf`**

`argv` is used only by the notify asserts this task deletes. Replace

```qml
  // A process's argv, joined with "|".
  function argv(proc) { return proc.command.join("|") }
```

with

```qml
  // The entries of alerts store `a`'s data that could launch a helper: an
  // object with a `script` or `command` property, or a Component.
  function helpersOf(a) {
    var found = []
    for (var i = 0; i < a.data.length; i++) {
      var o = a.data[i]
      if (o && (typeof o.script !== "undefined" || typeof o.command !== "undefined" || typeof o.createObject === "function"))
        found.push(String(o))
    }
    return found
  }
```

(`reply(proc, text, code)` right below stays; the RunStore tests use it.)

- [ ] **Step 3: S1 asserts the notify members are gone**

In `test_a_bare_alerts_store_is_disarmed_and_empty` replace

```qml
    compare(a.toastMs, 8000)
    compare(a.notifyRunners.length, 0)
    compare(a.active, false)
    compare(a.notifyOnEscalation, false)
    compare(a.projectRoots.length, 0)
```

with

```qml
    compare(a.toastMs, 8000)
    compare(typeof a.notifyRunners, "undefined")
    compare(typeof a.notify, "undefined")
    compare(typeof a.dropNotifyRunner, "undefined")
    compare(typeof a.notifyOnEscalation, "undefined")
    compare(typeof a.backendDir, "undefined")
    compare(a.active, false)
    compare(a.projectRoots.length, 0)
```

- [ ] **Step 4: New test beside S2**

Directly after the closing `}` of `test_the_toast_timer_is_the_stores_only_timer` (S2), insert:

```qml

  // S2b
  function test_the_store_declares_no_helper_process() {
    var a = makeAlerts(); if (!a) return
    compare(helpersOf(a).join(","), "", "no runner, process or Component")
  }
```

- [ ] **Step 5: S3, S4, S5 lose the switch and the runner asserts**

S3 `test_an_ok_reply_while_closed_changes_nothing` becomes:

```qml
  // S3
  function test_an_ok_reply_while_closed_changes_nothing() {
    var a = makeAlerts(); if (!a) return
    var armed = a.armedRoots
    var toasts = a.toasts
    a.snapshotReplied(tc.rootA, "ok", [], [escalatedRun("a1")])
    verify(a.armedRoots === armed, "armedRoots is not replaced")
    verify(a.toasts === toasts, "no toast")
    compare(a.alertsArmed, false)
  }
```

S4 `test_the_first_ok_reply_of_a_root_while_open_only_arms_it` becomes:

```qml
  // S4
  function test_the_first_ok_reply_of_a_root_while_open_only_arms_it() {
    var a = makeAlerts(); if (!a) return
    a.active = true
    a.snapshotReplied(tc.rootA, "ok", [], [escalatedRun("a1"), deadRun("a2")])
    compare(armedKeysOf(a), tc.rootA)
    compare(a.armedRoots[tc.rootA], true)
    compare(a.alertsArmed, true)
    compare(a.toasts.length, 0, "history is never replayed")
  }
```

In S5 `test_an_armed_roots_ok_reply_raises_new_alerts_with_the_projects_name` delete the last line of the function body:

```qml
    compare(a.notifyRunners.length, 0, "the switch is off")
```

- [ ] **Step 6: S12 becomes the card's named test**

Replace the whole of S12 (from `  // S12` through the closing `  }` of `test_notifications_follow_the_switch`) with:

```qml
  // S12
  function test_an_alert_raises_a_toast_and_launches_nothing() {
    var a = armedAlerts([tc.rootA]); if (!a) return
    a.snapshotReplied(tc.rootA, "ok", [runningRun("a1"), runningRun("a2")], [escalatedRun("a1"), deadRun("a2")])
    compare(toastIdsOf(a), "a1,a2")
    compare(a.toasts[0].state, "escalated")
    compare(a.toasts[1].state, "dead")
    compare(helpersOf(a).join(","), "", "no helper process")
    compare(typeof a.notify, "undefined")
    a.raiseAlerts([{ id: "z", title: "t", state: "escalated", reason: "r" }])
    compare(toastIdsOf(a), "a1,a2,z")
    compare(helpersOf(a).join(","), "", "raiseAlerts launches nothing either")
  }
```

- [ ] **Step 7: `wireAlerts` stops copying `backendDir`**

Replace

```qml
  // A RunAlertsStore wired to `store` the way App wires app.runAlerts:
  // backendDir copied; active and projectRoots bound to the run store's own;
  // snapshotReplied routed to it. notifyOnEscalation is left to each test.
  function wireAlerts(store) {
    var comp = Qt.createComponent("../../../core/stores/RunAlertsStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var a = comp.createObject(tc, { backendDir: store.backendDir })
```

with

```qml
  // A RunAlertsStore wired to `store` the way App wires app.runAlerts:
  // active and projectRoots bound to the run store's own; snapshotReplied
  // routed to it.
  function wireAlerts(store) {
    var comp = Qt.createComponent("../../../core/stores/RunAlertsStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var a = comp.createObject(tc)
```

(`make()` keeps `{ backendDir: "/plugin/core/backend/" }` on the RunStore: that is the run store's own input.)

- [ ] **Step 8: The two through-RunStore tests lose the switch**

`test_an_escalation_in_another_project_raises_one_toast_with_its_project` becomes:

```qml
  // 1
  function test_an_escalation_in_another_project_raises_one_toast_with_its_project() {
    var store = armedTwo([running("a1")], [running("b1")]); if (!store) return
    compare(store.project, "")
    answer(store, [okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1")])])
    compare(toastIds(store), "b1")
    compare(alerts(store).toasts[0].project, "beta")
    compare(alerts(store).toasts[0].title, "m-b1")
    compare(alerts(store).toasts[0].state, "escalated")
  }
```

`test_a_run_listed_under_two_roots_alerts_once_under_the_first` becomes:

```qml
  // 5 and Review Focus 4
  function test_a_run_listed_under_two_roots_alerts_once_under_the_first() {
    var store = armedTwo([running("x")], [running("x")]); if (!store) return
    // B's entry first: the registry's order decides, not the reply's.
    answer(store, [okEntry(tc.rootB, [escalated("x")]), okEntry(tc.rootA, [escalated("x")])])
    compare(toastIds(store), "x")
    compare(alerts(store).toasts[0].project, "alpha")
    store.projectRoots = registry([tc.rootB, tc.rootA])
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [escalated("x")]), okEntry(tc.rootB, [escalated("x")])]), 0)
    compare(store.runs[0].project.root, tc.rootB, "B owns x now")
    compare(alerts(store).toasts.length, 1, "a new owner replays nothing")
  }
```

- [ ] **Step 9: The notifications section becomes "toasts only"**

Replace everything from `  // ---- alerts: the desktop notifications (S2 4.4)` through the closing `  }` of `test_no_notification_while_the_panel_is_closed` (the file's last function; keep the final `}` of the `TestCase`) with:

```qml
  // ---- alerts: toasts only (S2 4.4)

  // 12
  function test_every_alert_toasts_and_none_launches_a_notification() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    snapshot(store, [escalated("a"), dead("b")])
    compare(toastIds(store), "a,b")
    compare(helpersOf(alerts(store)).join(","), "", "no helper for two alerts")

    var five = armedStore([]); if (!five) return
    snapshot(five, [escalated("r1"), escalated("r2"), dead("r3"), escalated("r4"), dead("r5")])
    compare(toastIds(five), "r3,r4,r5", "the last three")
    compare(helpersOf(alerts(five)).join(","), "", "nor for five, those whose toast was capped away included")
  }

  // 1 (the launch half)
  function test_no_toast_while_the_panel_is_closed_and_nothing_launched() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([running("a")]), 0)
    snapshot(store, [escalated("a")])
    compare(alerts(store).toasts.length, 0)
    compare(helpersOf(alerts(store)).join(","), "")
  }
```

- [ ] **Step 10: No reference to the removed members is left in the file**

Run: `grep -n "notifyRunners\|notifyOnEscalation\|notifyCmd\|backendDir\|argv(" tests/core/stores/tst_run_alerts_store.qml`
Expected: only the `typeof` lines from Step 3 (`notifyRunners`, `notifyOnEscalation`, `backendDir`) and the RunStore's own `{ backendDir: "/plugin/core/backend/" }` in `make()`. Nothing else.

#### Part B: the App tier tests (`tests/core/stores/tst_app_runs.qml`)

- [ ] **Step 11: Drop `notifyCmd`**

Delete these two lines (l.194-195):

```qml
  // The argv prefix of a notify.py command.
  property string notifyCmd: "python3|/plugin/core/backend/runs/notify.py|"
```

- [ ] **Step 12: The escalation-through-App test toasts with the switch off or on**

Replace the whole of `test_an_escalation_through_app_notifies_only_with_the_switch_on` with:

```qml
  function test_an_escalation_through_app_toasts_with_the_switch_off_or_on() {
    var app = openApp([runningIn("r1"), runningIn("r2")], []); if (!app) return
    compare(app.runControl.notifyOnEscalation, false)
    snapshot(app, listReply([escalatedIn("r1"), runningIn("r2")], []))
    compare(app.runAlerts.toasts.length, 1)
    compare(typeof app.runAlerts.notifyRunners, "undefined")
    compare(helpersOf(app.runAlerts).join(","), "", "the switch is off: a toast only")
    reply(app.runControl.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(app.runControl.notifyOnEscalation, true)
    snapshot(app, listReply([escalatedIn("r1"), escalatedIn("r2")], []))
    compare(app.runAlerts.toasts.length, 2)
    compare(typeof app.runAlerts.notifyRunners, "undefined")
    compare(helpersOf(app.runAlerts).join(","), "", "the switch is on: still a toast only")
  }
```

- [ ] **Step 13: The moved-members list and count**

Replace

```qml
  property var movedToAlerts: ["armedRoots", "alertsArmed", "toasts", "toastMs", "toastTimer", "notifyRunners",
    "raiseAlerts", "expireToasts", "dismissToast", "dismissAllToasts", "notify"]
```

with

```qml
  property var movedToAlerts: ["armedRoots", "alertsArmed", "toasts", "toastMs", "toastTimer",
    "raiseAlerts", "expireToasts", "dismissToast", "dismissAllToasts"]
```

and in `test_the_run_store_has_none_of_the_moved_members` replace

```qml
    compare(names.length, 66, "63 moved members and 3 handles")
```

with

```qml
    compare(names.length, 64, "61 moved members and 3 handles")
```

- [ ] **Step 14: Add `helpersOf` next to `answered`**

Directly after the closing `}` of `function answered(obj, names, present)`, insert:

```qml

  // The entries of store `obj`'s data that could launch a helper: an object
  // with a `script` or `command` property, or a Component.
  function helpersOf(obj) {
    var found = []
    for (var i = 0; i < obj.data.length; i++) {
      var o = obj.data[i]
      if (o && (typeof o.script !== "undefined" || typeof o.command !== "undefined" || typeof o.createObject === "function"))
        found.push(String(o))
    }
    return found
  }
```

(QML functions in a `TestCase` are hoisted, so Step 12's use above this definition works.)

- [ ] **Step 15: A1 asserts the inputs App no longer hands over**

Replace the whole of `test_app_composes_run_alerts_wired_to_the_run_store` with:

```qml
  // A1
  function test_app_composes_run_alerts_wired_to_the_run_store() {
    var app = makeBare(); if (!app) return
    verify(app.runAlerts, "App composes the alerts store")
    compare(typeof app.runAlerts.backendDir, "undefined", "App hands it no backend directory")
    compare(typeof app.runAlerts.notifyOnEscalation, "undefined", "nor the notify switch")
    compare(app.runAlerts.active, false)
    app.panelOpen = true
    compare(app.runAlerts.active, true, "active follows panelOpen")
    app.panelOpen = false
    compare(app.runAlerts.active, false)
    app.projects.applyStoredState('{"last_project": null}', 0)
    app.projects.applyProjectsList([pA, pB])
    compare(app.runAlerts.projectRoots.length, 2)
    verify(app.runAlerts.projectRoots === app.runs.projectRoots, "the run store's registry")
  }
```

- [ ] **Step 16: A8 keeps only the run-control load**

Replace the whole of `test_the_alerts_switch_is_run_controls` with:

```qml
  // A8
  function test_the_alerts_switch_is_run_controls() {
    var app = makeBare(); if (!app) return
    app.panelOpen = true
    var load = app.runControl.settingsLoadRunner.current
    verify(load, "the opening loads the switch on run control")
    compare(argv(load), tc.viewerCmd + "get-global-settings")
    reply(load, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(app.runControl.notifyOnEscalation, true)
  }
```

- [ ] **Step 17: A9 becomes "only toasts"**

Replace the whole of `test_with_run_controls_switch_on_an_escalation_launches_notify` with:

```qml
  // A9
  function test_with_run_controls_switch_on_an_escalation_only_toasts() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    reply(app.runControl.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(app.runControl.notifyOnEscalation, true)
    snapshot(app, listReply([escalatedIn("r1")], []))
    compare(app.runAlerts.toasts.length, 1)
    compare(helpersOf(app.runAlerts).join(","), "", "the switch is on: a toast only")
    compare(app.runControl.setNotifyOnEscalation(false), true)
    reply(app.runControl.settingsSaveRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
    compare(app.runControl.notifyOnEscalation, false)
    snapshot(app, listReply([escalatedIn("r1"), runningIn("r2")], []))
    snapshot(app, listReply([escalatedIn("r1"), escalatedIn("r2")], []))
    compare(app.runAlerts.toasts.length, 2, "r2's escalation is raised")
    compare(helpersOf(app.runAlerts).join(","), "", "the switch is off: a toast only")
    compare(typeof app.runAlerts.notifyRunners, "undefined")
  }
```

- [ ] **Step 18: No reference to the removed members is left in the file**

Run: `grep -n "notifyRunners\|notifyCmd\|runAlerts.notifyOnEscalation\|runAlerts.backendDir" tests/core/stores/tst_app_runs.qml`
Expected: only `typeof` lines (Steps 12, 15, 17).

#### Part C: the UI flow test and the architecture map

- [ ] **Step 19: `tests/ui/tst_runs_flow.qml` test 29**

Replace the whole of `test_with_the_setting_on_an_escalation_also_notifies` (from `  // 29` through its closing `  }`) with:

```qml
  // 29
  function test_with_the_setting_on_an_escalation_only_toasts() {
    var p = make(); if (!p) return
    compare(p.app.runControl.setNotifyOnEscalation(true), true)
    reply(p.app.runControl.settingsSaveRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
    compare(p.app.runControl.notifySaved, true)
    feed(p, [snapEntry("run-0000000000b2", "started", true, "beta")])
    feed(p, [snapEntry("run-0000000000b2", "escalated", null, "beta")])
    compare(p.app.runAlerts.toasts.length, 1)
    compare(typeof p.app.runAlerts.notifyRunners, "undefined", "the alerts store launches no notification")
    p.app.runControl.setNotifyOnEscalation(false)
    reply(p.app.runControl.settingsSaveRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
    feed(p, [snapEntry("run-0000000000b2", "escalated", null, "beta"), snapEntry("run-0000000000c3", "escalated", null, "gamma")])
    compare(p.app.runAlerts.toasts.length, 2)
  }
```

- [ ] **Step 20: `tests/architecture/test_run_store_callers.py` drops the two members**

In `MOVED`, delete the line

```python
    "notifyRunners": "runAlerts",
```

and the line

```python
    "notify": "runAlerts",
```

Leave every other entry (including `"notifyOnEscalation": "runControl"`) as it is.

- [ ] **Step 21: Run the changed tests and see them fail (RED)**

Run each, from the worktree root:

```bash
bash tests/run.sh tst_run_alerts_store
bash tests/run.sh tst_app_runs
bash tests/run.sh tst_runs_flow
```

Expected (each script exits non-zero; the pytest pass at the start is green):
- `tst_run_alerts_store.qml`: FAIL in `test_a_bare_alerts_store_is_disarmed_and_empty` (`typeof a.notifyRunners` is `"object"`), `test_the_store_declares_no_helper_process` and `test_every_alert_toasts_and_none_launches_a_notification` and `test_no_toast_while_the_panel_is_closed_and_nothing_launched` (actual is `QQmlComponent(0x...)`), `test_an_alert_raises_a_toast_and_launches_nothing` (same). Every other test in the file passes.
- `tst_app_runs.qml`: FAIL in `test_an_escalation_through_app_toasts_with_the_switch_off_or_on`, `test_app_composes_run_alerts_wired_to_the_run_store`, `test_with_run_controls_switch_on_an_escalation_only_toasts` (all on a `typeof ... "undefined"` or `helpersOf` compare). `test_the_run_store_has_none_of_the_moved_members` (count 64) and `test_each_owner_answers_to_its_moved_members` pass both now and after the change: the lists only shrank.
- `tst_runs_flow.qml`: FAIL in `test_with_the_setting_on_an_escalation_only_toasts` (`typeof ... notifyRunners` is `"object"`).

If any of these named tests passes here, stop: the test does not pin the change.

#### Part D: the store, App and the docs (GREEN)

- [ ] **Step 22: Rewrite `core/stores/RunAlertsStore.qml`**

Replace the whole file with:

```qml
import QtQml
import Quickshell
import Quickshell.Io
import "../domain/runs.js" as Runs

// The run alerts (S2 4.4): a toast for every run of any registered project
// that newly needs a human while the panel is open. Its one entry point for
// snapshot results is snapshotReplied, called once per project reply.
// `armedRoots` is {root: true} of every root whose runs may be compared
// against, and is replaced, never changed in place: a root's first ok reply
// after an opening, a `missing` reply or its return to the registry only arms
// it, so history is never replayed. `alertsArmed`: some root is armed.
// `toasts` is {key, id, title, state, reason, project, expiresMs}, oldest
// first, at most 3, and is replaced, never changed in place; `project` is the
// name of the run's project. The panel-open flag (`active`) and the registry
// (`projectRoots`) are handed to it from outside -- it never reaches for
// another store and launches no helper. App composes it as `app.runAlerts`
// and routes the run store's snapshotReplied here.
Scope {
  id: alerts

  property bool active: false               // App binds this to "panel open" (app.panelOpen)
  property var projectRoots: []             // [{root, name}], the registry in its order; App binds it

  property var armedRoots: ({})
  readonly property bool alertsArmed: Object.keys(alerts.armedRoots).length > 0
  property var toasts: []
  property int toastMs: 8000

  readonly property alias toastTimer: toastTimer

  // Opening disarms every root; closing disarms every root and empties the toasts.
  onActiveChanged: {
    alerts.armedRoots = {}
    if (!alerts.active) alerts.toasts = []
  }

  onProjectRootsChanged: alerts.pruneArmed()

  // One project's snapshot reply. "ok" while active: when `root` is armed,
  // Runs.newAlerts(previousRuns, runs) is raised (a non-array previousRuns
  // counts as []), each alert with `project` the project.name of its run in
  // `runs` ("" when it has none); then `root` is armed. "missing" disarms
  // every root and keeps the toasts. "ok" while closed, "failed" and any other
  // outcome change nothing.
  function snapshotReplied(root, outcome, previousRuns, runs) {
    if (outcome === "missing") {
      alerts.armedRoots = {}
      return
    }
    if (outcome !== "ok" || !alerts.active) return
    if (Runs.hasKey(alerts.armedRoots, root)) {
      var found = Runs.newAlerts(Array.isArray(previousRuns) ? previousRuns : [], runs)
      for (var i = 0; i < found.length; i++) {
        var run = Runs.runById(runs, found[i].id)
        var project = run !== null && run.project !== null && typeof run.project === "object" ? run.project.name : ""
        found[i].project = typeof project === "string" ? project : ""
      }
      alerts.raiseAlerts(found)
    }
    var armed = Runs.copyMap(alerts.armedRoots)
    armed[root] = true
    alerts.armedRoots = armed
  }

  // The registry changed: every armed root that no entry of projectRoots
  // names (entry.root === root) loses its arming. armedRoots is replaced only
  // when a root went; no toast is touched.
  function pruneArmed() {
    var list = alerts.projectRoots
    var n = list !== null && typeof list === "object" && typeof list.length === "number" ? list.length : 0
    var named = {}
    for (var i = 0; i < n; i++) {
      var p = list[i]
      if (p !== null && typeof p === "object" && typeof p.root === "string") named[p.root] = true
    }
    var armed = {}
    var went = false
    for (var root in alerts.armedRoots) {
      if (!Runs.hasKey(alerts.armedRoots, root)) continue
      if (Runs.hasKey(named, root)) armed[root] = true
      else went = true
    }
    if (went) alerts.armedRoots = armed
  }

  // One toast per alert, newest last: a run's older toast goes first, then the
  // oldest beyond three. It does not check `active`.
  function raiseAlerts(items) {
    var list = Array.isArray(items) ? items : []
    for (var i = 0; i < list.length; i++) {
      var a = list[i]
      toastState.nextKey += 1
      var next = alerts.toasts.filter(function(t) { return t.id !== a.id })
      next.push({ key: toastState.nextKey, id: a.id, title: a.title, state: a.state, reason: a.reason,
                  project: typeof a.project === "string" ? a.project : "", expiresMs: Date.now() + alerts.toastMs })
      while (next.length > 3) next.shift()
      alerts.toasts = next
    }
  }

  // Drops every toast whose time is up at nowMs (the timer passes Date.now()).
  function expireToasts(nowMs) {
    var next = alerts.toasts.filter(function(t) { return t.expiresMs > nowMs })
    if (next.length !== alerts.toasts.length) alerts.toasts = next
  }

  // The toast with this key goes; an unknown key changes nothing.
  function dismissToast(key) {
    var next = alerts.toasts.filter(function(t) { return t.key !== key })
    if (next.length !== alerts.toasts.length) alerts.toasts = next
  }

  function dismissAllToasts() {
    if (alerts.toasts.length > 0) alerts.toasts = []
  }

  // Only while the panel is open and a toast shows: no timer while idle.
  Timer {
    id: toastTimer
    objectName: "toastTimer"
    interval: 250
    repeat: true
    running: alerts.active && alerts.toasts.length > 0
    onTriggered: alerts.expireToasts(Date.now())
  }

  // The toast keys only grow, so a stale Dismiss never removes a newer toast.
  QtObject {
    id: toastState
    property int nextKey: 0
  }
}
```

Everything from `snapshotReplied` to `toastState` is byte-for-byte the old code except: the `notifyOnEscalation`/`backendDir` properties, the `notifyRunners` alias, the `if (alerts.notifyOnEscalation) alerts.notify(a)` line, `notify`, `dropNotifyRunner`, `notifyState` and `notifyC` are gone, and the two comments are rewritten.

- [ ] **Step 23: `core/stores/App.qml` drops the two bindings**

Replace

```qml
  // The run alerts never import the run store: App hands them the backend
  // directory, the panel-open flag, run control's notify switch and the
  // registry, and routes every project's snapshot reply (runs.snapshotReplied)
  // here.
  readonly property RunAlertsStore runAlerts: RunAlertsStore {
    backendDir: app.backendDir
    active: app.panelOpen
    notifyOnEscalation: app.runControl.notifyOnEscalation
    projectRoots: app.runs.projectRoots
  }
```

with

```qml
  // The run alerts never import the run store: App hands them the panel-open
  // flag and the registry, and routes every project's snapshot reply
  // (runs.snapshotReplied) here.
  readonly property RunAlertsStore runAlerts: RunAlertsStore {
    active: app.panelOpen
    projectRoots: app.runs.projectRoots
  }
```

Then check nothing else in App binds the removed inputs:

Run: `grep -n "runAlerts\." core/stores/App.qml`
Expected: only `app.runAlerts.snapshotReplied(...)` routing (no `notifyOnEscalation`, no `backendDir`).

- [ ] **Step 24: `docs/architecture.md` line 92 (the `RunControlStore.qml` bullet)**

Delete exactly this sentence (with its leading space) from line 92:

```
 App binds `app.runAlerts.notifyOnEscalation` to it.
```

so that `... and a project switch never changes the switch. Each project's run settings are here too: ...` reads on directly.

- [ ] **Step 25: `docs/architecture.md` line 93 (the `RunAlertsStore.qml` bullet)**

Three substring edits on line 93:

1. Replace
```
- `RunAlertsStore.qml` the run toasts, their arming and the desktop notification, for every registered project.
```
with
```
- `RunAlertsStore.qml` the run toasts and their arming, for every registered project.
```

2. Replace
```
`App` composes it as `app.runAlerts` and hands it `backendDir`, `active` (App's `panelOpen`), `notifyOnEscalation` (`app.runControl.notifyOnEscalation`) and `projectRoots` (`app.runs.projectRoots`), and routes
```
with
```
`App` composes it as `app.runAlerts` and hands it `active` (App's `panelOpen`) and `projectRoots` (`app.runs.projectRoots`) only, and routes
```

3. Delete the final sentence of line 93 (with its leading space):
```
 With `notifyOnEscalation` on, every raised alert also runs `notify.py TITLE REASON` on a `HelperRunner` of its own (`notifyRunners`; guard `""`, dropped when it exits, its reply unread, not stopped by a project switch).
```
so the line ends with `` `dismissToast(key)` / `dismissAllToasts()` remove them.``

Then check:

Run: `grep -n "runAlerts.notifyOnEscalation\|binds app.runAlerts\|hands it .backendDir., .active" docs/architecture.md; sed -n 93p docs/architecture.md | grep -c "notify"`
Expected: no lines from the first grep; `0` from the second. (Line 95, the `RunAlertsService.qml` bullet, and line 168 still mention `notifyRunners` / notifications: they are out of scope and stay.)

- [ ] **Step 26: Run the changed tests and see them pass (GREEN)**

```bash
bash tests/run.sh tst_run_alerts_store
bash tests/run.sh tst_app_runs
bash tests/run.sh tst_runs_flow
```

Expected: each prints `Totals: N passed, 0 failed` for its file, no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` line, and exits 0. The pytest pass at the start (including `tests/architecture/test_run_store_callers.py` and `test_run_store_docs.py`) is green.

- [ ] **Step 27: Full gate**

Run: `bash tests/run.sh`
Expected: pytest all pass; every `tst_*.qml` prints `0 failed`; exit status 0. In particular `tests/core/stores/tst_run_alerts_service.qml` (whose `notifyRunners` is the service's own) and `tests/core/stores/tst_run_control_store.qml` are unchanged and green.

- [ ] **Step 28: Commit**

```bash
git add core/stores/RunAlertsStore.qml core/stores/App.qml docs/architecture.md \
  tests/core/stores/tst_run_alerts_store.qml tests/core/stores/tst_app_runs.qml \
  tests/ui/tst_runs_flow.qml tests/architecture/test_run_store_callers.py
git commit -m "feat(alerts): RunAlertsStore raises toasts only and launches no notify.py"
```

---

## Self-review against the spec

- Public surface (inputs `active`, `projectRoots`; gone members read `undefined`; no `Component`/`script`/`command` in `data`; `toastTimer` the only timer): Steps 3, 4, 22; S2 unchanged.
- Raising launches nothing for any count, ok-while-active and ok-while-closed: Steps 6, 9, 5 (S3).
- App composition and comment: Steps 15, 23. Switch off or on through App toasts and launches nothing: Steps 12, 17, 19. Switch load/save unchanged: A8 (Step 16) keeps the load half; `tst_runs_flow.qml` l.819 test untouched.
- Docs: store header and `raiseAlerts` comment (Step 22); architecture l.93 and the l.92 claim (Steps 24, 25); l.168 untouched.
- Tests per file: `tst_run_alerts_store.qml` Steps 1-10; `tst_app_runs.qml` Steps 11-18 (`notifyCmd` dropped, count 64, A1/A8/A9); `tst_runs_flow.qml` Step 19; `test_run_store_callers.py` Step 20.
- `argv` in `tst_run_alerts_store.qml` is removed because its only callers were the deleted notify asserts; `tst_app_runs.qml` keeps its `argv` (used by snapshot and viewer-state asserts).
<!-- task-pipeline: validated -->
