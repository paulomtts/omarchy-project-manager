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
