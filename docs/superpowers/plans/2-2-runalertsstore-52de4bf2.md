# 2.2 RunAlertsStore: toasts, arming and desktop notification — design

Card: `52de4bf2` (subtask of story `a886bade`, blocked by 2.1 `373f6537`, which is done).
Parent design: `docs/superpowers/specs/2026-10-05-split-runstore-design.md`, cited below as
"P l.N". Line numbers into `core/stores/RunStore.qml` are from the file as it is at the start
of this card (2002 lines, commit `e414b74`). Appendix A's line numbers (P l.168) are from an
older 2038-line file and are not used here.

## Purpose

This is a pure refactor. The alerts concern leaves `RunStore` for a new store,
`core/stores/RunAlertsStore.qml`, which App composes as `app.runAlerts` (P l.56). That concern
is the per-project arming, the toast queue, the toast expiry and the `notify.py` desktop
notification. `RunStore` tells it about each project's snapshot reply through a new signal,
`snapshotReplied(root, outcome, previousRuns, runs)` (P l.76, l.81-91). App routes that signal
in one handler. `RunStore` keeps stateless shims under the old names (P l.122-127), so `ui/`
and `tests/ui/` do not change. Nothing a user can see or a helper can receive changes: the same
toasts appear at the same moments, in the same order and with the same keys and text, and the
same `notify.py` argv launches.

## Inherited constraints

- Every member lands in exactly one store. Nothing is duplicated, and nothing is dropped unless
  no code or test reads it (P l.61-67).
- No duplicated helpers. Shared logic is imported from `core/domain/` (`Runs.newAlerts`,
  `Runs.hasKey`, `Runs.copyMap`), and the new store keeps no private copy (P l.68-71).
- Inputs come from App. `RunAlertsStore` gets `backendDir`, `active` and `notifyOnEscalation`
  (P l.78), plus `projectRoots`, which A.3 adds for the registry prune (P l.432). The
  `notifyOnEscalation` source is `app.runs.notifyOnEscalation` until 3.2 moves the switch to
  `RunControlStore` (card text; P l.78 names the post-3.2 source).
- A store never imports or names a sibling. The one exception is the shim handle (P l.46-50).
- `snapshotReplied` is emitted after the reply's own state is applied. `outcome` is `ok`,
  `missing` (AmMissing) or `failed`, and `previousRuns` are that project's runs before the reply
  (P l.81-84). App handles it in ONE handler, and that handler replaces the direct
  `raiseAlerts` call and the AmMissing disarm (P l.85-88). The handler's
  `runControl.settleAfterSnapshot()` half does not exist yet (see Out of scope).
- `forgetLive`'s disarm is routed as outcome `missing` (P l.431). The registry prune is
  `RunAlertsStore`'s own reaction to `projectRoots` (P l.432). The open and close resets are
  `RunAlertsStore`'s own reaction to `active` (P l.433, l.435; rule 4, P l.92-97).
  `toastTimer` keeps its `running:` condition, bound to the new store's own `active`
  (P l.96-97).
- `raiseAlerts` reads `notifyOnEscalation` through the App binding (P l.438).
- Shims: a property is a read-only binding through a handle (`property var alertsStore: null`,
  set by App). A function is a one-line forward that returns the target's result. A shim
  property notifies like the original. Shims hold no state and no logic, and the comment above
  them says only "Moved to RunAlertsStore; removed by the last story" (P l.122-127).
- Tests move with their members. Only construction and the wiring of inputs change, never an
  expectation. A test that crosses two concerns is pinned at App level (P l.98-104,
  l.160-162).
- `tests/architecture` stays green (P l.105-106).
- No behaviour change, no renamed public member, no new helper argv, no change to which process
  starts when, and no UI change (P l.146-150).
- From the card:
  - `bash tests/run.sh` is green;
  - TDD: tests first;
  - docstrings and comments state the contract only, with no narrative;
  - `tests/ui` passes untouched.

## The members that move

Every row below leaves `RunStore.qml` and lands in `RunAlertsStore.qml`:

| member | RunStore.qml today | in RunAlertsStore |
|---|---|---|
| alerts comment block | 141-149 | rewritten as the store's contract comment |
| `armedRoots` | 150 | `property var armedRoots: ({})` |
| `alertsArmed` | 151 | readonly, `Object.keys(armedRoots).length > 0` |
| `toasts` | 152 | `property var toasts: []` |
| `toastMs` | 153 | `property int toastMs: 8000` |
| `toastTimer` alias | 211 | `readonly property alias toastTimer: toastTimer` |
| `notifyRunners` alias | 215 | `readonly property alias notifyRunners: notifyState.runners` |
| `alertsOf` | 1028-1052 (with its comment) | split: the owner filter and registry order stay in `RunStore`'s emission, and the per-root `newAlerts` comparison goes into `snapshotReplied` (below). No member keeps the name, and no code or test outside `RunStore.qml` calls it. |
| `raiseAlerts` | 1313-1325 | unchanged body |
| `expireToasts` | 1327-1331 | unchanged body |
| `dismissToast` | 1333-1337 | unchanged body |
| `dismissAllToasts` | 1339-1341 | unchanged body |
| `notify` | 1346-1350 | unchanged body |
| `dropNotifyRunner` | 1352-1355 | unchanged body |
| `toastTimer` Timer | 1859-1866 | same `objectName`, `interval`, `repeat`, `onTriggered`; `running: alerts.active && alerts.toasts.length > 0` |
| `toastState` | 1907-1910 | unchanged (`nextKey`) |
| `notifyState` | 1913-1916 | unchanged (`runners`) |
| `notifyC` | 1953-1964 | unchanged (`backendDir + "runs/notify.py"`, guard `""`) |

These stay in `RunStore` and are out of scope here: `notifyOnEscalation`, `notifySaved`,
`notifyTouched` (159-161), `setNotifyOnEscalation`, `applyRunSettings`, `notifySaveReplied`,
`settingsLoadRunner` and `settingsSaveRunner`. They go to `RunControlStore` in 3.x (P l.55).

## Behaviour: `RunAlertsStore`

### Inputs (bound by App)

| property | type | App binds | default |
|---|---|---|---|
| `backendDir` | string | `app.backendDir` | `""` |
| `active` | bool | `app.panelOpen` | `false` |
| `notifyOnEscalation` | bool | `app.runs.notifyOnEscalation` | `false` |
| `projectRoots` | var | `app.runs.projectRoots` | `[]` |

### `snapshotReplied(root, outcome, previousRuns, runs)`

This is the one entry point for snapshot results. It is called once per project reply.

- **`ok`, panel closed** (`active` false): nothing changes. No toast, no notification, and
  `armedRoots` is not replaced.
- **`ok`, panel open, `root` not armed**: no toast. `armedRoots` is replaced by a copy plus
  `root`. The root's first good entry after an opening, a start-over, an AmMissing spell or a
  return to the registry only arms it.
- **`ok`, panel open, `root` armed**: the alerts are `Runs.newAlerts(previousRuns, runs)`, in
  the order of `runs`. Each alert's `project` is `run.project.name` of the run in `runs` with
  that id. `raiseAlerts(alerts)` raises them, and then `armedRoots` is replaced by a copy (with
  `root`, already present).
- `previousRuns` that is not an array counts as `[]`. `runs` that is not an array raises
  nothing, and `ok` while open still arms.
- **`missing`**: `armedRoots` becomes `{}`, which disarms every root and not only `root`. The
  toasts stay.
- **`failed`**, or any other outcome: nothing changes, and `armedRoots` keeps its identity.

### Lifecycle

- `active` becomes true: `armedRoots = {}`.
- `active` becomes false: `armedRoots = {}` and `toasts = []`. A snapshot reply that lands
  after the panel closed raises nothing and arms nothing, because `ok` while closed is a no-op.
- `projectRoots` changes: every armed root that no entry of `projectRoots` names (`entry.root
  === root`) is dropped. `armedRoots` is replaced only when at least one root went, and no
  toast is touched. An armed root is always a usable root, because `RunStore` only emits for
  usable roots. Usability depends only on the root string. So "still named by an entry" is the
  same test as `RunStore.usableRoots()` for these roots, and no copy of `usableRoots` is needed.

### Unchanged from RunStore

Everything below behaves exactly as `RunStore` does today:

- `raiseAlerts`: one toast per alert, newest last. A run's older toast goes first, then the
  oldest beyond three. `key` only grows. It does not check `active`, and `tests/ui/
  tst_shortcuts.qml:643` calls it with the panel in any state. With `notifyOnEscalation` on,
  each alert also runs `notify.py TITLE REASON`.
- `expireToasts(nowMs)`, `dismissToast(key)`, `dismissAllToasts()`.
- `notify(alert)`: one `HelperRunner` per notification, guard `""`. Its reply is unread, and
  the runner is dropped when it exits.
- `toastTimer`: 250 ms and repeating, it runs only while `active` and a toast shows.

## Behaviour: `RunStore`

### `signal snapshotReplied(var root, var outcome, var previousRuns, var runs)`

`applyProjects` emits it as its last action on each path that matched an entry. The emissions
for one reply go in **registry order** (`usableRoots()` order), one per usable root that has a
matched entry, whatever order the reply lists them in:

| path in `applyProjects` | emissions | `previousRuns` | `runs` |
|---|---|---|---|
| some matched entry ok | `ok` for each ok root, `failed` for each failed root | `runsByProject[root]` before the reply, `[]` when it had none | for `ok`: the root's runs in the new `runsByProject[root]` that the merged list attributes to it (`merged.owner[id] === root`), in that list's order. For `failed`: `[]` |
| every matched entry failed (`!anyOk`) | `failed` for each matched root | as above | `[]` |
| every matched entry AmMissing | `missing` for each matched root | the root's runs before the reply | `[]` |
| no matched entry (no usable result, or every launched root gone) | none | | |
| `ok: false` envelope or unreadable reply (paths that never reach `applyProjects` entries) | none | | |

Each emission comes after the reply's state is applied: `runs`, `runsByProject`,
`projectErrors`, `appliedSeq`, `asOfSeq`, `amStatus` and `lastError`. On the ok path it also
comes after `settleAfterSnapshot()`, `logsAfterSnapshot()`, the `stale` and stale-clock update
and the watch start or restart. This matches where `raiseAlerts` and the arming sit today
(1021-1024). The emission happens whether or not `store.active` is true, because
`RunAlertsStore` gates on its own `active`.

`forgetLive()` (588-595), on the `resetCursor` path, emits `missing` once for every usable
root, in registry order, after its own state is cleared. `previousRuns` is that root's runs
before the clear, and `runs` is `[]`.

### Lines removed from `RunStore`

`startLive` loses `armedRoots = {}` (363). `stopLive` loses `armedRoots = {}` and `toasts = []`
(386-387). `forgetLive` loses `armedRoots = {}` (594). `registryChanged` loses the `armed`
bookkeeping (735, 739, 744). `applyProjects` loses the AmMissing disarm (956), the `alerts`
computation (992) and the raise-and-arm block (1021-1024). The doc comments above
`startLive`, `stopLive`, `forgetLive`, `registryChanged` and `applyProjects` drop their alerts
clauses and say instead which `snapshotReplied` is emitted.

### Shims

The shims sit under one comment, `// Moved to RunAlertsStore; removed by the last story`:

| name | shim | without a handle |
|---|---|---|
| `alertsStore` | `property var alertsStore: null` (the handle App sets) | — |
| `armedRoots` | `readonly property var` through the handle | `({})` |
| `alertsArmed` | `readonly property bool` | `false` |
| `toasts` | `readonly property var` | `[]` |
| `toastMs` | `readonly property int` | `0` |
| `toastTimer` | `readonly property var` (the Timer) | `null` |
| `notifyRunners` | `readonly property var` | `[]` |
| `raiseAlerts(a)`, `expireToasts(n)`, `dismissToast(k)`, `dismissAllToasts()`, `notify(a)` | one-line forward returning the target's result | returns `undefined`, does nothing |

A shim with no handle must not throw. `tests/run.sh` fails a file whose output holds
`TypeError`, so every shim checks `store.alertsStore` first. The shim properties are
bindings, so `toastsChanged` and the others fire whenever the alerts store's value changes.
`Panel.qml:781` (`toasts: appStores.runs.toasts`) and `Shortcuts.qml:45, 126` read them.
`alertsOf` and `dropNotifyRunner` get no shim, because nothing outside `RunStore.qml` calls
them (checked with grep across `ui/` and `tests/`).

## Behaviour: `App`

```qml
readonly property RunAlertsStore runAlerts: RunAlertsStore {
  backendDir: app.backendDir
  active: app.panelOpen
  notifyOnEscalation: app.runs.notifyOnEscalation
  projectRoots: app.runs.projectRoots
}
```

`app.runs` gains `alertsStore: app.runAlerts` and one handler:
`onSnapshotReplied: function(root, outcome, previousRuns, runs) {
app.runAlerts.snapshotReplied(root, outcome, previousRuns, runs) }`. The comment above
`runAlerts` states the contract: what App hands it and that the snapshot reply is routed
here.

## Equivalence argument (for the reviewer)

- **Raise timing.** Today's alerts are computed before the runs are replaced (992) and raised
  after the good-snapshot tail (1021). The new `ok` emission carries the same comparison
  inputs: the root's runs before the reply, against its owned runs after the reply, with
  arming checked before any root of this reply is armed. One root's arming never affects
  another root's check, so raising and arming per root in registry order gives the same toasts
  in the same order as today's single `alertsOf` loop.
- **No double alerts.** `alertsOf`'s `raised` set kept one alert per run id per reply. The
  owner filter makes a run id appear in exactly one root's `runs`, and `newAlerts` already
  dedups within one list. So no run alerts twice.
- **Project name.** `alertsOf` derived the name with `Runs.withProject({}, root, name)`. Every
  run in `runs` already carries `Runs.withProject(run, root, name).project`, through
  `taggedByProject`, so `run.project.name` is the same string.
- **Arming identity.** Today `armedRoots` is replaced once per good reply while open. Now it is
  replaced once per ok root of that reply. The final value is the same. No test compares
  identity across an ok reply (the identity checks are at `tst_run_store.qml` 3587, 3590,
  3612 and 3643, all across non-ok events).

## Tests

TDD: each test below is written first and fails before its code exists. All QML tests run
through `bash tests/run.sh` (qmltestrunner, offscreen, stubs from `tests/stubs`). There are
four test files and four tiers:

- **store unit**: `tests/core/stores/tst_run_alerts_store.qml`, a new file named
  `StoresRunAlertsStore`;
- **RunStore unit**: `tests/core/stores/tst_run_store.qml`;
- **App wiring**: `tests/core/stores/tst_app_runs.qml`;
- **UI and architecture**: `tests/ui/**` (untouched) and `pytest tests`.

### Harness used by both store test files

`wireAlerts(store)` creates a `RunAlertsStore` (`Qt.createComponent("../../../core/stores/
RunAlertsStore.qml")`, parent `tc`) and wires it the way App does:

- `backendDir` copied;
- `active`, `notifyOnEscalation` and `projectRoots` as `Qt.binding`s to the RunStore's own;
- `store.alertsStore = alerts`;
- `store.snapshotReplied.connect(alerts.snapshotReplied)`.

The harness also records the pair, and `alerts(store)` returns the paired alerts store. The
lookup is the harness's own record, not the shim handle, so it survives the shims' removal.

- `tst_run_store.qml`'s `make()` calls `wireAlerts`. Every test that stays there is unchanged
  and still reads alerts members through the shims.
- `tst_run_alerts_store.qml` has the same `make()` and copies of the helpers its moved tests
  use (`rootEntry`, `registry`, `activeRoots`, `makeWithProject`, `activeStore`, `reply`,
  `entry`, `allReply`, `okEntry`, `failEntry`, `okReply`, `missing` replies, `snapshot`,
  `ctlEntry`, `running`, `dead`, `escalated`, `argv`, `nudge`, `fire`, `toastIds`,
  `armedKeys`, `armedStore`, `notifyCmd`).

### Moved tests (store unit tier: they move whole, with every expectation kept)

These leave `tst_run_store.qml` and land in `tst_run_alerts_store.qml` under the same names. In
the moved bodies, only one thing changes: each read, write or call of an alerts member
(`armedRoots`, `alertsArmed`, `toasts`, `toastMs`, `toastTimer`, `notifyRunners`,
`raiseAlerts`, `expireToasts`, `dismissToast`, `dismissAllToasts`, `notify`) goes to
`alerts(store)` instead of `store`. That includes the helpers `toastIds`, `armedKeys` and
`armedStore`. Writing `toastMs` needs this, because the shim is read-only. Snapshots are still
driven through the RunStore's stubbed processes, because the behaviour under test is a real
reply turning into a toast.

- `test_a_nudge_refresh_that_escalates_a_run_raises_one_toast` (1026)
- the whole `// ---- alerts: the toasts (S2 4.4)` block, 3278-3646:
  - `test_no_toast_while_the_panel_is_closed`
  - `test_a_run_that_turns_escalated_raises_one_toast`
  - `test_a_run_still_escalated_raises_nothing_again`
  - `test_closing_empties_the_toasts_and_reopening_raises_nothing_at_first`
  - `test_a_snapshot_landing_after_the_panel_closed_raises_nothing_and_does_not_arm`
  - `test_am_missing_disarms_and_a_failed_snapshot_does_not`
  - `test_five_alerts_in_one_snapshot_leave_the_last_three_toasts`
  - `test_a_run_that_alerts_again_replaces_its_own_toast`
  - `test_toasts_expire_and_the_timer_runs_only_while_open_with_toasts`
  - `test_dismiss_removes_one_toast_by_key_and_dismiss_all_empties`
  - `test_a_project_switch_keeps_the_toasts_and_the_alerts_armed`
  - `test_an_escalation_in_another_project_raises_one_toast_with_its_project`
  - `test_a_project_that_first_fails_or_joins_later_only_arms_on_its_first_good_entry`
  - `test_a_failing_project_raises_nothing_and_stays_armed`
  - `test_an_am_missing_spell_disarms_every_project`
  - `test_a_run_listed_under_two_roots_alerts_once_under_the_first`
  - `test_a_run_listed_under_two_roots_alerts_only_from_its_owners_entry`
  - `test_a_partial_or_failed_reply_leaves_the_other_roots_arming_alone`
  - `test_a_project_switch_keeps_the_toasts_and_every_projects_arming`
  - `test_a_reply_while_the_panel_is_closed_raises_nothing_and_arms_nothing`
  - `test_a_root_that_leaves_the_registry_loses_its_arming`
- `test_with_the_setting_on_each_alert_launches_its_own_notification` (3743)
- `test_no_notification_while_the_panel_is_closed` (3783)

The helpers that only these tests use (`toastIds`, `armedKeys`, `armedStore`, `notifyCmd`)
move too. `escalated` stays in `tst_run_store.qml`, because
`test_a_project_switch_leaves_the_run_list_and_the_live_state_alone` (404) uses it, and a
copy goes to the new file.

### Tests that stay in `tst_run_store.qml` unchanged (RunStore unit tier)

These tests mainly pin RunStore behaviour and also read an alerts member through the shims.
They stay byte-identical and pass through `make()`'s wiring:

- 228 `test_a_failing_root_keeps_its_runs_and_says_why`
- 259 `test_when_no_root_answers_…`
- 282 `test_am_missing_in_every_entry_empties_everything`
- 363 `test_a_registry_change_…`
- 395 `test_a_project_switch_leaves_the_run_list_and_the_live_state_alone`
- 454 `test_with_no_project_open_…`
- 757 `test_starting_over_…`
- 901 `test_a_partial_reply_keeps_the_other_roots_as_they_were`
- 1087 `test_a_partial_reply_that_is_am_missing_empties_every_root`
- 3793 `test_the_switch_saves_globally_and_a_failed_save_puts_it_back`
- 5299 `test_a_busy_root_…`
- 5704, 5736, 5835, 5851 (the cursor reset and store-id hello tests)

These double as end-to-end pins of the shims and of the `missing` emission on `forgetLive`.

**The one changed expectation.** `test_logs_add_no_timer_and_none_runs_while_idle` (2629)
lists the RunStore's own Timer children. `toastTimer` is no longer one of them, so the
expected string becomes
`"debounceTimer,dispatchDebounceTimer,flashTimer,livenessTimer,pendingTimer,pollTimer,staleTimer"`.
The timer did not disappear. It moved, and new test S2 pins it on the new store.

### New tests: store unit tier (`tst_run_alerts_store.qml`, `RunAlertsStore` built alone)

These pin the new interface directly, with no RunStore involved. The store is created with
`backendDir: "/plugin/core/backend/"` and driven by calling `snapshotReplied`, setting
`active` and setting `projectRoots`. Runs are built with `Runs.withProject(Runs.normalizeRun
(...), root, name)` from `amFixtures` or the file's `entry` helper.

- S1 `test_a_bare_alerts_store_is_disarmed_and_empty`: `armedRoots` is `{}`, `alertsArmed` is
  false, `toasts` is `[]`, `toastMs` is 8000 and `notifyRunners` is `[]`; `toastTimer.objectName`
  is `"toastTimer"` with interval 250 and not running.
- S2 `test_the_toast_timer_is_the_stores_only_timer`: the Timer children are exactly
  `"toastTimer"`.
- S3 `test_an_ok_reply_while_closed_changes_nothing`: the same `armedRoots` object
  (`verify(===)`) and no toasts, even with an escalated run against `[]`.
- S4 `test_the_first_ok_reply_of_a_root_while_open_only_arms_it`: `armedRoots` is
  `{root: true}`, with no toasts and no notify runner.
- S5 `test_an_armed_roots_ok_reply_raises_new_alerts_with_the_projects_name`: an escalated
  run and a dead run against running ones give two toasts in `runs` order, with `project` from
  `run.project.name`, `title` and `reason` as `Runs.newAlerts` gives them, and increasing
  keys. `armedRoots` is a new object that still holds the root.
- S6 `test_a_run_with_no_project_name_toasts_with_an_empty_project`: a run with no `project`
  gives a toast with `project: ""`.
- S7 `test_a_failed_reply_and_an_unknown_outcome_change_nothing`: the same `armedRoots`
  object and the same `toasts` object.
- S8 `test_missing_disarms_every_root_and_keeps_the_toasts`: with A and B armed and one toast,
  `missing` for A gives `armedRoots` `{}`, the toast stays, and the next `ok` for B only
  arms.
- S9 `test_non_array_previous_runs_count_as_empty_and_non_array_runs_raise_nothing`: armed,
  `previousRuns` `undefined` with an escalated run raises one toast, and `runs` `null` raises
  nothing but the root stays armed.
- S10 `test_opening_disarms_and_closing_disarms_and_empties_the_toasts`.
- S11 `test_a_root_no_registry_entry_names_loses_its_arming`: A and B armed. `projectRoots`
  without B drops B. A change that removes no armed root keeps the same `armedRoots` object.
  A duplicate entry for A keeps A.
- S12 `test_notifications_follow_the_switch`: with the switch on, an armed escalation launches
  `python3|/plugin/core/backend/runs/notify.py|<title>|<reason>` with launch guard `""`, and the
  runner goes when its process exits. With the switch off, it launches nothing.

### New tests: RunStore unit tier (`tst_run_store.qml`, `snapshotReplied` spy)

Each test uses `spyC` on `store.snapshotReplied`. Where a test needs to read the state at
emission time, it connects a recorder function that copies `store.amStatus`,
`ids(store.runs)` and the arguments.

- R1 `test_an_ok_reply_emits_ok_per_root_in_registry_order`: a reply listing B's entry before
  A's gives two emissions, A then B, with `previousRuns` the roots' earlier lists and `runs`
  their new lists. At emission, `store.runs` is already the merged new list and `amStatus` is
  `"ok"`.
- R2 `test_a_root_with_no_entry_emits_nothing_and_a_failed_entry_emits_failed`: an ok A plus a
  failed C gives `ok` for A and `failed` for C with `runs` `[]`. B, with no entry, gives no
  emission.
- R3 `test_a_run_listed_under_two_roots_is_in_its_owners_runs_only`: B's `runs` lacks the run
  A owns.
- R4 `test_every_entry_failed_emits_failed_after_the_error_is_set`: at emission, `amStatus` is
  `"error"` and `lastError` is the first sentence.
- R5 `test_am_missing_emits_missing_per_matched_root_after_the_runs_are_emptied`: at emission,
  `store.runs` is empty and `amStatus` is `"missing"`.
- R6 `test_a_reply_with_no_usable_result_emits_nothing`: covers no matched entry, every
  launched root gone, an `ok: false` envelope, and garbage.
- R7 `test_a_reply_while_closed_still_emits`: an `ok` emission even with `active` false.
- R8 `test_a_cursor_reset_emits_missing_for_every_usable_root`: `forgetLive` through a
  `cursorReset` hello gives `missing` for A, then B, with `runs` `[]`.
- R9 `test_without_an_alerts_store_the_shims_are_empty_and_inert`: a RunStore made without
  `wireAlerts` reads `armedRoots` `{}`, `alertsArmed` false, `toasts` `[]`, `toastMs` 0,
  `toastTimer` null and `notifyRunners` `[]`. `raiseAlerts([...])`, `expireToasts(0)`,
  `dismissToast(1)`, `dismissAllToasts()` and `notify({...})` return without error, and no
  `TypeError` is printed.
- R10 `test_the_shims_follow_the_alerts_store_and_notify`: with `wireAlerts`, `store.toasts`
  is the alerts store's `toasts` (`===`), and a `toastsChanged` spy on the RunStore fires when
  `alerts(store).raiseAlerts(...)` runs.

### New tests: App wiring tier (`tst_app_runs.qml`)

The existing tests at 329, 338, 436, 449 and 463 stay unchanged (they pass through the
shims). Added:

- A1 `test_app_composes_run_alerts_wired_to_the_run_store`: `app.runAlerts` exists,
  `app.runs.alertsStore === app.runAlerts`, `backendDir` follows App, `active` follows
  `panelOpen`, `notifyOnEscalation` follows `app.runs.notifyOnEscalation`, and `projectRoots`
  is `app.runs.projectRoots`.
- A2 `test_a_snapshot_through_app_toasts_on_run_alerts`: the 329 scenario, asserting on
  `app.runAlerts.toasts` and `app.runAlerts.alertsArmed`. It also checks
  `app.runs.toasts === app.runAlerts.toasts`.
- A3 `test_am_missing_through_app_disarms_run_alerts`: the 338 scenario, on
  `app.runAlerts.alertsArmed`.
- A4 `test_closing_the_panel_through_app_empties_run_alerts`: the 436 scenario, on
  `app.runAlerts.toasts` and `alertsArmed`.

### UI and architecture tiers

- `tests/ui/**` is unedited and passes. That proves the shims for `Panel`, `Shortcuts`,
  `tst_runs_flow.qml` (toasts, `notifyRunners`) and `tst_shortcuts.qml:643`
  (`raiseAlerts`).
- `pytest tests` passes, which includes `tests/architecture`. `RunAlertsStore.qml` imports
  only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain/runs.js`, and its name clashes
  with no shell or Controls type.

## Docs

`docs/architecture.md` is updated to match the contract:

- The `RunStore.qml` paragraph (83-91) loses the alerts description. It says instead that
  `RunStore` emits `snapshotReplied` and keeps shims.
- A new `RunAlertsStore.qml` bullet holds the alerts text that moved: arming, toasts, expiry,
  notify, `active` and `projectRoots` reactions, and its inputs.
- The refresh-model line (171) names `RunAlertsStore`'s `toastTimer`.

## Out of scope

- `notifyOnEscalation` / `notifySaved` / `notifyTouched`, the settings runners, and moving the
  switch's source binding. These belong to 3.x `RunControlStore` (P l.55). 3.2 rebinds
  `runAlerts.notifyOnEscalation`.
- Routing `settleAfterSnapshot()` through the App handler. It stays a direct call inside
  `applyProjects`, in today's position, until `RunControlStore` exists (P l.85, l.427).
- The persisted `gseq` alert cursor (P l.56, l.421). It belongs to the "Alerts while the panel
  is closed" milestone.
- Moving `ui/` or `tests/ui/` callers to `app.runAlerts`, and deleting the shims and the
  handle. That is the last story (P l.128-130).
- `RunControlStore`, `RunDispatchStore` and their shims (sibling cards).
- Any change to `Runs.newAlerts`, `HelperRunner` or `notify.py`.

## Handoff to the planner

### File structure

- Create `core/stores/RunAlertsStore.qml`: a `Scope` with the inputs, state, functions,
  `toastTimer`, `toastState`, `notifyState` and `notifyC` above. It imports `QtQml`,
  `Quickshell`, `Quickshell.Io` and `"../domain/runs.js" as Runs`.
- Modify `core/stores/RunStore.qml`: add the signal and its emissions, remove the moved
  members and couplings, and add the shims.
- Modify `core/stores/App.qml`: add `runAlerts`, the handle and the handler.
- Create `tests/core/stores/tst_run_alerts_store.qml`.
- Modify `tests/core/stores/tst_run_store.qml`: add `wireAlerts` and `alerts`, move the tests
  out, add R1-R10, and update the timer list.
- Modify `tests/core/stores/tst_app_runs.qml`: add A1-A4.
- Modify `docs/architecture.md`.

### Suggested task order

Each task ends green on `bash tests/run.sh`:

1. `RunAlertsStore.qml` with S1-S12, built alone. RunStore is untouched, so the two stores
   briefly run in parallel. Only tests construct the new store, and nothing is wired yet.
2. `RunStore.snapshotReplied` emissions with R1-R8. The old alerts code still runs alongside,
   so the emissions are additive.
3. The cut-over, which a reviewer must see as one change:
   - add `wireAlerts` to `tst_run_store`;
   - move the tests to the new file;
   - delete the RunStore alerts members and couplings;
   - add the shims with R9-R10;
   - update the timer-list expectation;
   - add App's `runAlerts`, handle and handler with A1-A4.
4. `docs/architecture.md`.

### Review Focus candidates

- A shim reading through a null handle prints `TypeError` and fails `tests/run.sh` even
  though the asserts pass.
- The order of emissions when a reply lists roots out of registry order. Toast order and
  notify order must follow registry order.
- `previousRuns` must be captured before `store.runsByProject = byProject`. Capturing it after
  replays nothing and hides every alert.
- The panel closes while a snapshot is in flight. The reply lands, the emission fires, and
  RunAlertsStore must neither raise nor arm.
- The registry prune and the snapshot after a registry change. A root that returns must only
  re-arm on its first ok entry (`tst_app_runs.qml` 463).

---

# 2.2 RunAlertsStore: Toasts, Arming and Desktop Notification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the run alerts (arming, toast queue, toast expiry, `notify.py` notification) out of `core/stores/RunStore.qml` into a new `core/stores/RunAlertsStore.qml` composed by App as `app.runAlerts`, fed by a new `RunStore.snapshotReplied` signal, with stateless shims left on `RunStore` so `ui/` and `tests/ui/` do not change.

**Architecture:** `RunAlertsStore` is a `Scope` with four inputs bound by App (`backendDir`, `active`, `notifyOnEscalation`, `projectRoots`) and one entry point, `snapshotReplied(root, outcome, previousRuns, runs)`. `RunStore` emits `snapshotReplied` once per matched usable root, in registry order, after a reply's state is applied (and `missing` for every usable root on a start-over); App routes that signal in one handler. `RunStore` keeps read-only property shims and one-line function forwards through a `property var alertsStore: null` handle.

**Tech Stack:** QML (Qt 6, Quickshell `Scope`, `HelperRunner`), the pure JS domain `core/domain/runs.js` (`Runs.newAlerts`, `Runs.runById`, `Runs.hasKey`, `Runs.copyMap`), QtTest via `qmltestrunner` driven by `bash tests/run.sh` (offscreen, stubs from `tests/stubs`), pytest for `tests/architecture`.

**Spec:** `docs/superpowers/specs/2-2-runalertsstore-52de4bf2.md` (prepended above).

## Global Constraints

- Pure refactor: no behaviour change, no renamed public member, no new helper argv, no change to which process starts when, no UI change.
- Every member lands in exactly one store; nothing duplicated; nothing dropped unless no code or test reads it.
- No duplicated helpers: shared logic comes from `core/domain/` (`Runs.newAlerts`, `Runs.hasKey`, `Runs.copyMap`, `Runs.runById`); the new store keeps no private copy.
- `core/stores/RunAlertsStore.qml` imports only `QtQml`, `Quickshell`, `Quickshell.Io` and `"../domain/runs.js" as Runs`.
- A store never imports or names a sibling; the one exception is the shim handle `property var alertsStore: null`, set by App.
- Shims: a property is a read-only binding through the handle; a function is a one-line forward that returns the target's result; the comment above them says only `// Moved to RunAlertsStore; removed by the last story`. A shim with no handle must not throw.
- `snapshotReplied` is emitted after the reply's own state is applied; `outcome` is `ok`, `missing` or `failed`.
- Tests move with their members; only construction and the wiring of inputs change, never an expectation.
- `tests/ui/**` is not edited and passes; `tests/architecture` stays green; `bash tests/run.sh` is green.
- TDD: tests first. Docstrings and comments state the contract only, with no narrative.

## Review Focus

- **A shim read through a null handle.** A RunStore with no `alertsStore` must read `{}` / `false` / `[]` / `0` / `null` and its function shims must return `undefined` without printing `TypeError` (`tests/run.sh` fails a file whose output holds one). Pinned by R9 in Task 3.
- **A reply that lists roots out of registry order.** Toasts and notifications must follow registry order, and a run listed under two roots alerts once, under its owner. Pinned by R1 (Task 2) and the moved `test_a_run_listed_under_two_roots_alerts_once_under_the_first` (Task 3).
- **`previousRuns` captured after the runs are replaced.** That would compare the new list with itself and hide every alert. Pinned by R1's `previous` checks (Task 2) and every moved toast test (Task 3).
- **The panel closes while a snapshot is in flight.** The reply lands and is emitted; `RunAlertsStore` must neither raise nor arm. Pinned by S3 and S10 (Task 1), R7 (Task 2) and the moved `test_a_snapshot_landing_after_the_panel_closed_raises_nothing_and_does_not_arm` (Task 3).
- **The registry prune and a root that returns.** A root that leaves loses its arming at once and re-arms only on its first ok entry after it returns; a change that drops no armed root keeps the same `armedRoots` object. Pinned by S11 (Task 1), the moved `test_a_root_that_leaves_the_registry_loses_its_arming` (Task 3) and the unchanged `tst_app_runs.qml` `test_a_project_leaving_the_registry_through_app_loses_its_arming`.

---

## File Structure

- Create `core/stores/RunAlertsStore.qml` — the alerts concern: inputs, arming, toasts, expiry timer, notify runners. (Task 1)
- Create `tests/core/stores/tst_run_alerts_store.qml` — test case `StoresRunAlertsStore`: S1-S12 on the bare store (Task 1), then the moved tests driven through a wired RunStore (Task 3).
- Modify `core/stores/RunStore.qml` — add `snapshotReplied` and its emissions (Task 2); remove the alerts members and couplings and add the shims (Task 3).
- Modify `tests/core/stores/tst_run_store.qml` — R1-R8 (Task 2); `wireAlerts`/`alerts` harness, R9-R10, the moved tests removed, the timer-list expectation (Task 3).
- Modify `core/stores/App.qml` — `runAlerts`, the handle and the handler (Task 3).
- Modify `tests/core/stores/tst_app_runs.qml` — A1-A4 (Task 3).
- Modify `docs/architecture.md` (Task 4).

How to run tests: `bash tests/run.sh <substring>` runs pytest and then every QML test whose path contains `<substring>`; a QML file passes when its `Totals:` line shows `0 failed` and the script prints no `TypeError`/`ReferenceError` line. The script's exit status is non-zero on any failure. Run from the worktree root.

---

### Task 1: `RunAlertsStore.qml`, built alone, with S1-S12

**Files:**
- Create: `core/stores/RunAlertsStore.qml`
- Create: `tests/core/stores/tst_run_alerts_store.qml`

**Interfaces:**
- Consumes: `Runs.newAlerts(prevRuns, nextRuns)`, `Runs.runById(runs, id)`, `Runs.hasKey(map, key)`, `Runs.copyMap(map)` from `core/domain/runs.js`; `HelperRunner` (same directory: `script`, `guard`, `run(args)`, `current`, signal `finished`).
- Produces (used by Tasks 3 and 4):
  - inputs: `property string backendDir: ""`, `property bool active: false`, `property bool notifyOnEscalation: false`, `property var projectRoots: []`
  - state: `property var armedRoots: ({})`, `readonly property bool alertsArmed`, `property var toasts: []`, `property int toastMs: 8000`
  - `readonly property alias toastTimer` (Timer, `objectName: "toastTimer"`), `readonly property alias notifyRunners` (array of HelperRunner)
  - `function snapshotReplied(root, outcome, previousRuns, runs)` → undefined
  - `function raiseAlerts(alerts)`, `function expireToasts(nowMs)`, `function dismissToast(key)`, `function dismissAllToasts()`, `function notify(alert)`, `function dropNotifyRunner(runner)`, `function pruneArmed()`

- [ ] **Step 1: Write the failing tests**

Create `tests/core/stores/tst_run_alerts_store.qml` with exactly this content:

```qml
// tests/core/stores/tst_run_alerts_store.qml
// The run alerts store: per-project arming, the toast queue, the toast expiry
// and the notify.py desktop notification. Built alone and driven through
// snapshotReplied, active and projectRoots; and, through a RunStore wired to
// it the way App wires them, a real snapshot reply turning into a toast.
// Stubbed Process objects stand in for every helper.
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs

TestCase {
  id: tc
  name: "StoresRunAlertsStore"

  property string rootA: "/home/u/my proj"
  property string rootB: "/home/u/b"
  property string rootC: "/home/u/c"
  property string notifyCmd: "python3|/plugin/core/backend/runs/notify.py|"

  // A RunAlertsStore built alone, with nothing bound.
  function makeAlerts() {
    var comp = Qt.createComponent("../../../core/stores/RunAlertsStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }

  // A root's registry entry: rootA is "alpha", rootB "beta", any other "proj".
  function rootEntry(root) {
    return { root: root, name: root === tc.rootA ? "alpha" : root === tc.rootB ? "beta" : "proj" }
  }

  // The registry of `roots`, in that order, as App hands it over.
  function registry(roots) {
    return roots.map(function(r) { return tc.rootEntry(r) })
  }

  // A run of `root` (rootA when omitted) as the run store hands it over:
  // normalized and tagged with its project, am status `runStatus`, its lease
  // live or not.
  function runOf(id, runStatus, live, root) {
    var r = root || tc.rootA
    var raw = {
      row: { id: id, repo_dir: r },
      status: {
        run: { id: id, milestone_id: "m-" + id, status: runStatus },
        rows: [], stories: [], subtasks: [],
        control: { lease: { pid: 42, host: "h", heartbeat_at: "2026-10-01T00:00:05Z", accepting: true, live: live } }
      }
    }
    return Runs.withProject(Runs.normalizeRun(raw), r, tc.rootEntry(r).name)
  }
  function runningRun(id, root) { return runOf(id, "started", true, root) }
  function deadRun(id, root) { return runOf(id, "started", false, root) }
  function escalatedRun(id, root) { return runOf(id, "escalated", false, root) }

  // An open alerts store with each of `roots` armed by an ok reply, nothing raised.
  function armedAlerts(roots) {
    var a = makeAlerts(); if (!a) return null
    a.active = true
    for (var i = 0; i < roots.length; i++) a.snapshotReplied(roots[i], "ok", [], [])
    compare(armedKeysOf(a), roots.slice().sort().join(","), "every root's first ok reply arms it")
    compare(a.toasts.length, 0, "and raises nothing")
    return a
  }

  // The armed roots of alerts store `a`, sorted, comma-joined.
  function armedKeysOf(a) { return Object.keys(a.armedRoots).sort().join(",") }

  // The run ids of alerts store `a`'s toasts, oldest first, comma-joined.
  function toastIdsOf(a) { return a.toasts.map(function(t) { return t.id }).join(",") }

  // A process's argv, joined with "|".
  function argv(proc) { return proc.command.join("|") }

  // A stubbed process's reply: its stdout, then its exit code.
  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // ---- the store alone (split-runstore 2.2)

  // S1
  function test_a_bare_alerts_store_is_disarmed_and_empty() {
    var a = makeAlerts(); if (!a) return
    compare(JSON.stringify(a.armedRoots), "{}")
    compare(a.alertsArmed, false)
    compare(JSON.stringify(a.toasts), "[]")
    compare(a.toastMs, 8000)
    compare(a.notifyRunners.length, 0)
    compare(a.active, false)
    compare(a.notifyOnEscalation, false)
    compare(a.projectRoots.length, 0)
    compare(a.toastTimer.objectName, "toastTimer")
    compare(a.toastTimer.interval, 250)
    compare(a.toastTimer.repeat, true)
    compare(a.toastTimer.running, false)
  }

  // S2
  function test_the_toast_timer_is_the_stores_only_timer() {
    var a = makeAlerts(); if (!a) return
    var timers = []
    for (var i = 0; i < a.data.length; i++) {
      var o = a.data[i]
      if (o && typeof o.interval === "number" && typeof o.repeat === "boolean") timers.push(o.objectName)
    }
    compare(timers.join(","), "toastTimer")
  }

  // S3
  function test_an_ok_reply_while_closed_changes_nothing() {
    var a = makeAlerts(); if (!a) return
    a.notifyOnEscalation = true
    var armed = a.armedRoots
    var toasts = a.toasts
    a.snapshotReplied(tc.rootA, "ok", [], [escalatedRun("a1")])
    verify(a.armedRoots === armed, "armedRoots is not replaced")
    verify(a.toasts === toasts, "no toast")
    compare(a.alertsArmed, false)
    compare(a.notifyRunners.length, 0, "no notification")
  }

  // S4
  function test_the_first_ok_reply_of_a_root_while_open_only_arms_it() {
    var a = makeAlerts(); if (!a) return
    a.active = true
    a.notifyOnEscalation = true
    a.snapshotReplied(tc.rootA, "ok", [], [escalatedRun("a1"), deadRun("a2")])
    compare(armedKeysOf(a), tc.rootA)
    compare(a.armedRoots[tc.rootA], true)
    compare(a.alertsArmed, true)
    compare(a.toasts.length, 0, "history is never replayed")
    compare(a.notifyRunners.length, 0)
  }

  // S5
  function test_an_armed_roots_ok_reply_raises_new_alerts_with_the_projects_name() {
    var a = armedAlerts([tc.rootB]); if (!a) return
    var armed = a.armedRoots
    var prev = [runningRun("b1", tc.rootB), runningRun("b2", tc.rootB), runningRun("b3", tc.rootB)]
    var next = [escalatedRun("b1", tc.rootB), runningRun("b2", tc.rootB), deadRun("b3", tc.rootB)]
    var expected = Runs.newAlerts(prev, next)
    var before = Date.now()
    a.snapshotReplied(tc.rootB, "ok", prev, next)
    compare(toastIdsOf(a), "b1,b3", "in the order of runs")
    compare(a.toasts[0].project, "beta", "run.project.name")
    compare(a.toasts[0].title, expected[0].title)
    compare(a.toasts[0].title, "m-b1")
    compare(a.toasts[0].state, "escalated")
    compare(a.toasts[0].reason, expected[0].reason)
    compare(a.toasts[1].project, "beta")
    compare(a.toasts[1].state, "dead")
    compare(a.toasts[1].reason, "process died")
    verify(a.toasts[0].key < a.toasts[1].key, "keys only grow")
    verify(a.toasts[0].expiresMs >= before + 8000 && a.toasts[0].expiresMs <= Date.now() + 8000, "8 s from now")
    verify(a.armedRoots !== armed, "armedRoots is replaced")
    compare(armedKeysOf(a), tc.rootB, "and still holds the root")
    compare(a.notifyRunners.length, 0, "the switch is off")
  }

  // S6
  function test_a_run_with_no_project_name_toasts_with_an_empty_project() {
    var a = armedAlerts([tc.rootA]); if (!a) return
    // synthetic: a run the run store never hands over, with no project.
    var bare = Runs.normalizeRun({ row: { id: "x1" }, status: { run: { id: "x1", milestone_id: "m-x1", status: "escalated" } } })
    compare(bare.project, null)
    a.snapshotReplied(tc.rootA, "ok", [], [bare])
    compare(toastIdsOf(a), "x1")
    compare(a.toasts[0].project, "")
  }

  // S7
  function test_a_failed_reply_and_an_unknown_outcome_change_nothing() {
    var a = armedAlerts([tc.rootA]); if (!a) return
    a.snapshotReplied(tc.rootA, "ok", [runningRun("a1")], [escalatedRun("a1")])
    compare(toastIdsOf(a), "a1")
    var armed = a.armedRoots
    var toasts = a.toasts
    var outcomes = ["failed", "error", "", "OK", undefined, null]
    for (var i = 0; i < outcomes.length; i++) {
      var label = "outcome " + String(outcomes[i])
      a.snapshotReplied(tc.rootA, outcomes[i], [runningRun("a2")], [escalatedRun("a2")])
      a.snapshotReplied(tc.rootB, outcomes[i], [], [])
      verify(a.armedRoots === armed, label + ": the arming")
      verify(a.toasts === toasts, label + ": the toasts")
    }
  }

  // S8
  function test_missing_disarms_every_root_and_keeps_the_toasts() {
    var a = armedAlerts([tc.rootA, tc.rootB]); if (!a) return
    a.snapshotReplied(tc.rootA, "ok", [runningRun("a1")], [escalatedRun("a1")])
    compare(toastIdsOf(a), "a1")
    a.snapshotReplied(tc.rootA, "missing", [escalatedRun("a1")], [])
    compare(JSON.stringify(a.armedRoots), "{}", "every root, not only A")
    compare(a.alertsArmed, false)
    compare(toastIdsOf(a), "a1", "the toasts stay")
    a.snapshotReplied(tc.rootB, "ok", [], [escalatedRun("b1", tc.rootB)])
    compare(toastIdsOf(a), "a1", "B's next ok reply only arms")
    compare(armedKeysOf(a), tc.rootB)
  }

  // S9
  function test_non_array_previous_runs_count_as_empty_and_non_array_runs_raise_nothing() {
    var a = armedAlerts([tc.rootA]); if (!a) return
    a.snapshotReplied(tc.rootA, "ok", undefined, [escalatedRun("a1")])
    compare(toastIdsOf(a), "a1", "undefined previousRuns is []")
    a.snapshotReplied(tc.rootA, "ok", null, [escalatedRun("a1"), escalatedRun("a2")])
    compare(toastIdsOf(a), "a1,a2", "null previousRuns is [] too: a1 raises again and replaces its own toast")
    a.snapshotReplied(tc.rootB, "ok", [], null)
    compare(armedKeysOf(a), [tc.rootA, tc.rootB].sort().join(","), "non-array runs still arm")
    a.snapshotReplied(tc.rootA, "ok", [], null)
    a.snapshotReplied(tc.rootA, "ok", [], "garbage")
    compare(toastIdsOf(a), "a1,a2", "and raise nothing")
    compare(armedKeysOf(a), [tc.rootA, tc.rootB].sort().join(","))
  }

  // S10
  function test_opening_disarms_and_closing_disarms_and_empties_the_toasts() {
    var a = armedAlerts([tc.rootA]); if (!a) return
    a.snapshotReplied(tc.rootA, "ok", [], [escalatedRun("a1")])
    compare(a.toasts.length, 1)
    compare(a.toastTimer.running, true, "open with a toast: the timer runs")
    a.active = false
    compare(JSON.stringify(a.armedRoots), "{}", "closing disarms")
    compare(a.toasts.length, 0, "and empties the toasts")
    compare(a.toastTimer.running, false)
    a.snapshotReplied(tc.rootA, "ok", [], [escalatedRun("a2")])
    compare(a.alertsArmed, false, "a reply after closing arms nothing")
    compare(a.toasts.length, 0, "and raises nothing")
    a.raiseAlerts([{ id: "z", title: "t", state: "escalated", reason: "r" }])
    compare(toastIdsOf(a), "z", "raiseAlerts itself does not check active")
    compare(a.toastTimer.running, false, "closed: no timer")
    // synthetic: an arming left in place while closed.
    a.armedRoots = ({ "/home/u/c": true })
    a.active = true
    compare(JSON.stringify(a.armedRoots), "{}", "opening disarms")
    compare(toastIdsOf(a), "z", "opening empties no toast")
    compare(a.toastTimer.running, true)
    a.snapshotReplied(tc.rootA, "ok", [], [escalatedRun("a1")])
    compare(toastIdsOf(a), "z", "the first ok reply after opening only arms")
    compare(armedKeysOf(a), tc.rootA)
  }

  // S11
  function test_a_root_no_registry_entry_names_loses_its_arming() {
    var a = makeAlerts(); if (!a) return
    a.projectRoots = registry([tc.rootA, tc.rootB])
    a.active = true
    a.snapshotReplied(tc.rootA, "ok", [], [])
    a.snapshotReplied(tc.rootB, "ok", [], [])
    a.raiseAlerts([{ id: "t1", title: "t", state: "escalated", reason: "r", project: "beta" }])
    var toasts = a.toasts
    a.projectRoots = registry([tc.rootA, tc.rootC])
    compare(armedKeysOf(a), tc.rootA, "no entry names B: its arming goes")
    verify(a.toasts === toasts, "no toast is touched")
    var armed = a.armedRoots
    // synthetic: entries the run store would skip, around A renamed.
    a.projectRoots = [{ root: tc.rootA, name: "renamed" }, rootEntry(tc.rootC), null, "x", { name: "none" }]
    verify(a.armedRoots === armed, "no armed root went: the map is not replaced")
    a.projectRoots = [rootEntry(tc.rootA), rootEntry(tc.rootA)]
    verify(a.armedRoots === armed, "a duplicate entry keeps A")
    a.projectRoots = []
    compare(armedKeysOf(a), "", "an empty registry arms nothing")
    a.snapshotReplied(tc.rootA, "ok", [], [])
    compare(armedKeysOf(a), tc.rootA)
    // synthetic: no registry at all.
    a.projectRoots = null
    compare(armedKeysOf(a), "", "a registry that is not a list names no root")
    verify(a.toasts === toasts, "and still touches no toast")
  }

  // S12
  function test_notifications_follow_the_switch() {
    var a = armedAlerts([tc.rootA]); if (!a) return
    a.notifyOnEscalation = true
    a.snapshotReplied(tc.rootA, "ok", [runningRun("a1")], [escalatedRun("a1")])
    compare(a.notifyRunners.length, 1, "one runner per alert")
    var proc = a.notifyRunners[0].current
    compare(argv(proc), tc.notifyCmd + "m-a1|escalated")
    compare(proc.command.length, 4)
    compare(proc.launchGuard, "", "guard \"\"")
    compare(proc.running, true)
    reply(proc, JSON.stringify({ ok: true, sent: true }) + "\n", 0)
    compare(a.notifyRunners.length, 0, "the runner goes when its process exits")
    a.notifyOnEscalation = false
    a.snapshotReplied(tc.rootA, "ok", [escalatedRun("a1")], [escalatedRun("a1"), deadRun("a2")])
    compare(toastIdsOf(a), "a1,a2")
    compare(a.notifyRunners.length, 0, "the switch is off: toasts only")
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_alerts_store`
Expected: FAIL — every test fails at `makeAlerts()` with a component error naming `RunAlertsStore.qml` (the file does not exist); the script exits non-zero.

- [ ] **Step 3: Write the store**

Create `core/stores/RunAlertsStore.qml` with exactly this content:

```qml
import QtQml
import Quickshell
import Quickshell.Io
import "../domain/runs.js" as Runs

// The run alerts (S2 4.4): a toast for every run of any registered project
// that newly needs a human while the panel is open and, with
// notifyOnEscalation on, a notify.py desktop notification for it. Its one
// entry point for snapshot results is snapshotReplied, called once per
// project reply. `armedRoots` is {root: true} of every root whose runs may be
// compared against, and is replaced, never changed in place: a root's first
// ok reply after an opening, a `missing` reply or its return to the registry
// only arms it, so history is never replayed. `alertsArmed`: some root is
// armed. `toasts` is {key, id, title, state, reason, project, expiresMs},
// oldest first, at most 3, and is replaced, never changed in place; `project`
// is the name of the run's project. The backend directory, the panel-open
// flag, the notify switch and the registry are handed to it from outside --
// it never reaches for another store. App composes it as `app.runAlerts` and
// routes the run store's snapshotReplied here.
Scope {
  id: alerts

  property string backendDir: ""            // <plugin>/core/backend/
  property bool active: false               // App binds this to "panel open" (app.panelOpen)
  property bool notifyOnEscalation: false   // "Notify on escalation"; App binds it to the switch
  property var projectRoots: []             // [{root, name}], the registry in its order; App binds it

  property var armedRoots: ({})
  readonly property bool alertsArmed: Object.keys(alerts.armedRoots).length > 0
  property var toasts: []
  property int toastMs: 8000

  readonly property alias toastTimer: toastTimer
  readonly property alias notifyRunners: notifyState.runners    // in-flight notify.py launches, oldest first

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
  // oldest beyond three. With the setting on, each alert also notifies.
  // It does not check `active`.
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
      if (alerts.notifyOnEscalation) alerts.notify(a)
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

  // One notify.py launch for an alert, on a runner of its own so two never
  // stop each other. The reply is not read: a failed or skipped notification
  // changes nothing here.
  function notify(alert) {
    var runner = notifyC.createObject(alerts)
    notifyState.runners = notifyState.runners.concat([runner])
    runner.run([String(alert.title), String(alert.reason)])
  }

  function dropNotifyRunner(runner) {
    notifyState.runners = notifyState.runners.filter(function(r) { return r !== runner })
    runner.destroy()
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

  // The notify.py runners in flight; kept apart so consumers cannot write it.
  QtObject {
    id: notifyState
    property var runners: []
  }

  // One HelperRunner per notification. Guard "": a project switch does not
  // stop a notification already launched. It goes when its process exits.
  Component {
    id: notifyC

    HelperRunner {
      id: nr
      script: alerts.backendDir + "runs/notify.py"
      guard: ""
      onFinished: alerts.dropNotifyRunner(nr)
    }
  }
}
```

(The only differences from `RunStore`'s bodies: `store.` becomes `alerts.`, and `raiseAlerts`'s parameter is `items` because a parameter named `alerts` would shadow the store's id. The parameter name is not part of the public contract; the shim in Task 3 forwards positionally.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_alerts_store`
Expected: PASS — the `Totals:` line for `tests/core/stores/tst_run_alerts_store.qml` shows `0 failed` with all 12 tests run, no `TypeError` line, pytest green, exit status 0.

- [ ] **Step 5: Run the architecture tests**

Run: `python3 -m pytest tests/architecture -q` (or `uv run --with pytest python3 -m pytest tests/architecture -q` when python3 has no pytest)
Expected: PASS — `RunAlertsStore.qml` imports only the allowed modules and its name clashes with no shell or Controls type.

- [ ] **Step 6: Commit**

```bash
git add core/stores/RunAlertsStore.qml tests/core/stores/tst_run_alerts_store.qml
git commit -m "feat(alerts): RunAlertsStore with arming, toasts and notify, built alone"
```

---

### Task 2: `RunStore.snapshotReplied` emissions (R1-R8)

The old alerts code in `RunStore` stays and still runs; the emissions are additive and nothing is connected to them yet.

**Files:**
- Modify: `core/stores/RunStore.qml` (header comment lines 1-37; signals near line 197-200; `forgetLive` 584-595; `applyProjects` 893-1026; new helpers after `alertsOf`, before `// ---- run controls (S2 4.1)`)
- Test: `tests/core/stores/tst_run_store.qml` (append a section before the final `}` of the file)

**Interfaces:**
- Consumes: nothing new.
- Produces (used by Task 3):
  - `signal snapshotReplied(var root, var outcome, var previousRuns, var runs)` on `RunStore`
  - `function emitReplied(usable, outcomes, prev, after)` and `function ownedRuns(list, owner, root)` on `RunStore` (internal)
  - test helper `recordReplies(store)` in `tst_run_store.qml` → array of `{root, outcome, previous, runs, status, all, error}` (`previous`, `runs`, `all` are comma-joined id strings)

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_store.qml`, insert this block immediately before the file's last line (the closing `}` of the TestCase, right after `test_a_store_hello_..`'s closing `  }` — the current last test ends with `    compare(store.runs.length, 2)\n  }`):

```qml

  // ---- snapshotReplied (split-runstore 2.2)

  // Every snapshotReplied of `store` from now on, as {root, outcome,
  // previous, runs, status, all, error}: the arguments (previousRuns and runs
  // as ids) and the store's amStatus, ids(runs) and lastError at emission.
  function recordReplies(store) {
    var out = []
    store.snapshotReplied.connect(function(root, outcome, previousRuns, runs) {
      out.push({ root: root, outcome: outcome, previous: ids(previousRuns), runs: ids(runs),
                 status: store.amStatus, all: ids(store.runs), error: store.lastError })
    })
    return out
  }

  // R1
  function test_an_ok_reply_emits_ok_per_root_in_registry_order() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                                                  okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)])]), 0)
    var seen = recordReplies(store)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "snapshotReplied" })
    store.refresh()
    // B's entry first: the registry's order decides, not the reply's.
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB), entry("b2", "started", true, tc.rootB)]),
                                                  okEntry(tc.rootA, [entry("a2", "started", true)])]), 0)
    compare(spy.count, 2)
    compare(seen.length, 2)
    compare(seen[0].root, tc.rootA, "A first, in registry order")
    compare(seen[0].outcome, "ok")
    compare(seen[0].previous, "a1", "the root's runs before the reply")
    compare(seen[0].runs, "a2", "and after it")
    compare(seen[1].root, tc.rootB)
    compare(seen[1].outcome, "ok")
    compare(seen[1].previous, "b1")
    compare(seen[1].runs, "b1,b2")
    compare(seen[0].all, "a2,b1,b2", "emitted after the merged runs are applied")
    compare(seen[0].status, "ok")
    compare(seen[0].error, "")
    compare(spy.signalArguments[0][2][0].project.name, "alpha", "previousRuns are the tagged runs")
    compare(spy.signalArguments[1][3][1].project.name, "beta", "and so are runs")
  }

  // R2
  function test_a_root_with_no_entry_emits_nothing_and_a_failed_entry_emits_failed() {
    var store = makeWithRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return
    var seen = recordReplies(store)
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootC, "AmTimeout", "am did not answer within 60 s."),
                                                  okEntry(tc.rootA, [entry("a1", "done", false)])]), 0)
    compare(seen.length, 2, "B, with no entry, emits nothing")
    compare(seen[0].root, tc.rootA)
    compare(seen[0].outcome, "ok")
    compare(seen[0].previous, "", "a root with no runs before: []")
    compare(seen[0].runs, "a1")
    compare(seen[1].root, tc.rootC)
    compare(seen[1].outcome, "failed")
    compare(seen[1].previous, "")
    compare(seen[1].runs, "", "a failed root's runs are []")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmTimeout", "am did not answer within 60 s."),
                                                  okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])]), 0)
    compare(seen.length, 4)
    compare(seen[2].root, tc.rootA)
    compare(seen[2].outcome, "failed")
    compare(seen[2].previous, "a1", "a failed root's runs before the reply")
    compare(seen[2].runs, "")
    compare(seen[3].root, tc.rootC)
    compare(seen[3].outcome, "ok")
    compare(seen[3].runs, "c1")
  }

  // R3
  function test_a_run_listed_under_two_roots_is_in_its_owners_runs_only() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    var seen = recordReplies(store)
    // synthetic: x under both roots, and a run without an id under B.
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("x", "done", false)]),
                                                  okEntry(tc.rootB, [entry("x", "done", false, tc.rootB), entry("b1", "done", false, tc.rootB),
                                                                     entry("", "done", false, tc.rootB)])]), 0)
    compare(seen.length, 2)
    compare(seen[0].runs, "x", "A owns x")
    compare(seen[1].runs, "b1", "B's runs lack x, and a run without an id is no root's")
    compare(ids(store.runsByProject[tc.rootB]), "x,b1,", "B's own list keeps all three")
  }

  // R4
  function test_every_entry_failed_emits_failed_after_the_error_is_set() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]), okEntry(tc.rootB, [])]), 0)
    var seen = recordReplies(store)
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s."),
                                                  failEntry(tc.rootA, "HelperError", "boom")]), 0)
    compare(seen.length, 2)
    compare(seen[0].root, tc.rootA)
    compare(seen[0].outcome, "failed")
    compare(seen[0].previous, "a1")
    compare(seen[0].runs, "")
    compare(seen[1].root, tc.rootB)
    compare(seen[1].outcome, "failed")
    compare(seen[0].status, "error", "amStatus is set before the emission")
    compare(seen[0].error, "AmTimeout: am did not answer within 60 s.", "lastError is the first failed entry's sentence")
    compare(seen[0].all, "a1", "the runs stay")
  }

  // R5
  function test_am_missing_emits_missing_per_matched_root_after_the_runs_are_emptied() {
    var store = makeWithRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                                                  okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)]),
                                                  okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])]), 0)
    var seen = recordReplies(store)
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootB, "AmMissing", "am is not installed."),
                                                  failEntry(tc.rootA, "AmMissing", "am is not installed.")]), 0)
    compare(seen.length, 2, "C, with no entry, emits nothing")
    compare(seen[0].root, tc.rootA, "registry order")
    compare(seen[0].outcome, "missing")
    compare(seen[0].previous, "a1", "the root's runs before the reply")
    compare(seen[0].runs, "")
    compare(seen[0].all, "", "emitted after the runs are emptied")
    compare(seen[0].status, "missing")
    compare(seen[1].root, tc.rootB)
    compare(seen[1].outcome, "missing")
    compare(seen[1].previous, "b1")
  }

  // R6
  function test_a_reply_with_no_usable_result_emits_nothing() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "snapshotReplied" })
    // synthetic: entries for no registered root.
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)]), null, "x"]), 0)
    compare(store.amStatus, "error", "no matched entry")
    compare(spy.count, 0)
    store.refresh()
    reply(store.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "Usage", message: "usage" } }) + "\n", 2)
    compare(spy.count, 0, "an ok: false envelope")
    store.refresh()
    reply(store.snapshotRunner.current, "garbage\n", 1)
    compare(spy.count, 0, "garbage")
    store.refresh()
    var gone = store.snapshotRunner.current
    store.projectRoots = registry([tc.rootC])
    reply(gone, allReply([okEntry(tc.rootA, [entry("a1", "done", false)])]), 0)
    compare(spy.count, 0, "every launched root gone")
  }

  // R7
  function test_a_reply_while_closed_still_emits() {
    var store = makeWithRoots([tc.rootA]); if (!store) return
    compare(store.active, false)
    var seen = recordReplies(store)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "escalated", false)])]), 0)
    compare(seen.length, 1)
    compare(seen[0].outcome, "ok")
    compare(seen[0].runs, "a1")
  }

  // R8
  function test_a_cursor_reset_emits_missing_for_every_usable_root() {
    var store = threeRoots(); if (!store) return
    var seen = recordReplies(store)
    sendLine(store.watchProc, resetHello(true))
    compare(seen.length, 3)
    var roots = [tc.rootA, tc.rootB, tc.rootC]
    var before = ["a1", "b1", "c1"]
    for (var i = 0; i < 3; i++) {
      compare(seen[i].root, roots[i], "registry order")
      compare(seen[i].outcome, "missing")
      compare(seen[i].previous, before[i], "the root's runs before the reset")
      compare(seen[i].runs, "")
      compare(seen[i].all, "", "emitted after the runs are cleared")
    }
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL — the eight new tests fail (`recordReplies` throws `TypeError: Cannot call method 'connect' of undefined`, and the spies report the signal `snapshotReplied` is not found); every other test still passes. The script exits non-zero.

- [ ] **Step 3: Add the signal**

In `core/stores/RunStore.qml`, find:

```qml
  // A debounce window's nudged run ids, each once, in first-nudge order,
  // known to the store or not. Never for a snapshot the store started itself.
  // (`runs` already owns the runsChanged name.)
  signal runsNudged(var ids)
```

and replace it with:

```qml
  // A debounce window's nudged run ids, each once, in first-nudge order,
  // known to the store or not. Never for a snapshot the store started itself.
  // (`runs` already owns the runsChanged name.)
  signal runsNudged(var ids)
  // One project's list snapshot reply, once its state is applied: per usable
  // root with a matched entry, in registry order, whether or not `active`.
  // `outcome` is "ok", "failed" or "missing" (AmMissing, and a start-over);
  // `previousRuns` are the root's runs before the reply ([] when it had none);
  // `runs` are, for "ok", the root's runs that the merged `runs` lists under
  // it, else [].
  signal snapshotReplied(var root, var outcome, var previousRuns, var runs)
```

In the header comment at the top of the file, find:

```qml
// Dispatch (openDispatch .. dispatchStart) previews a run with
// dispatch-preview.py and starts it with start-run.py, one HelperRunner per
// Start.
```

and replace it with:

```qml
// Dispatch (openDispatch .. dispatchStart) previews a run with
// dispatch-preview.py and starts it with start-run.py, one HelperRunner per
// Start. Each applied list snapshot reply is announced per project
// (snapshotReplied).
```

- [ ] **Step 4: Add the emission helpers**

In `core/stores/RunStore.qml`, find the line `  // ---- run controls (S2 4.1)` (it follows the end of `alertsOf`) and insert immediately before it:

```qml
  // snapshotReplied for each root of `usable` that `outcomes` ({root:
  // outcome}) names, in registry order: previousRuns is prev[root] ([] when it
  // had none), runs is after[root] ([] when it has none).
  function emitReplied(usable, outcomes, prev, after) {
    for (var i = 0; i < usable.length; i++) {
      var root = usable[i].root
      if (!Runs.hasKey(outcomes, root)) continue
      store.snapshotReplied(root, outcomes[root], Runs.hasKey(prev, root) ? prev[root] : [],
                            Runs.hasKey(after, root) ? after[root] : [])
    }
  }

  // The runs of `list`, in its order, that `owner` (mergedRuns' {id: root})
  // attributes to `root`; a run without an owned id is no root's.
  function ownedRuns(list, owner, root) {
    return list.filter(function(run) {
      return run !== null && typeof run === "object" && Runs.hasKey(owner, run.id) && owner[run.id] === root
    })
  }

```

- [ ] **Step 5: Emit from `applyProjects`**

In `core/stores/RunStore.qml`, replace the whole `applyProjects` function — from the line `  function applyProjects(entries, exitCode, launched) {` through its closing `  }` (the line before the blank line and `  // One list reply's alerts, in registry order, then each root's order: for`) — with:

```qml
  function applyProjects(entries, exitCode, launched) {
    var usable = store.usableRoots()
    var names = {}
    for (var u = 0; u < usable.length; u++) names[usable[u].root] = usable[u].name
    var matched = []
    var seen = {}
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (e === null || typeof e !== "object" || Array.isArray(e)) continue
      if (typeof e.root !== "string" || !Runs.hasKey(names, e.root) || Runs.hasKey(seen, e.root)) continue
      seen[e.root] = true
      matched.push(e)
    }
    if (matched.length === 0) {
      var gone = true
      var roots = Array.isArray(launched) ? launched : []
      for (var g = 0; g < roots.length; g++) {
        if (Runs.hasKey(names, roots[g])) gone = false
      }
      if (gone && roots.length > 0) return
      store.amStatus = "error"
      store.lastError = "The runs snapshot gave no usable result (exit " + exitCode + ")."
      return
    }
    var missing = true
    for (var m = 0; m < matched.length; m++) {
      var err = matched[m].error
      var type = err !== null && typeof err === "object" ? err.type : ""
      if (matched[m].ok === true || type !== "AmMissing") missing = false
    }
    var prev = store.runsByProject
    var outcomes = {}
    if (missing) {
      store.runs = []
      store.runsByProject = {}
      store.projectErrors = {}
      store.appliedSeq = {}
      store.asOfSeq = 0
      store.amStatus = "missing"
      store.lastError = Runs.errorText(matched[0].error)
      // Every root is disarmed: comparing its next good entry against []
      // would alert every escalated run again.
      store.armedRoots = {}
      for (var mr = 0; mr < matched.length; mr++) outcomes[matched[mr].root] = "missing"
      store.emitReplied(usable, outcomes, prev, {})
      return
    }
    var byProject = Runs.copyMap(store.runsByProject)
    var errors = Runs.copyMap(store.projectErrors)
    var anyOk = false
    var okRoots = {}
    var firstError = ""
    for (var k = 0; k < matched.length; k++) {
      var entry = matched[k]
      var root = entry.root
      if (entry.ok === true) {
        anyOk = true
        okRoots[root] = true
        outcomes[root] = "ok"
        var list = Array.isArray(entry.runs) ? entry.runs : []
        var out = []
        for (var r = 0; r < list.length; r++) {
          var item = list[r]
          if (item === null || typeof item !== "object" || Array.isArray(item)) continue
          out.push(Runs.withProject(Runs.normalizeRun({ row: store.rowOf(item), status: item.status }), root, names[root]))
        }
        byProject[root] = out
        delete errors[root]
      } else {
        outcomes[root] = "failed"
        if (!Runs.hasKey(byProject, root)) byProject[root] = []
        errors[root] = Runs.errorText(entry.error)
        if (firstError === "") firstError = errors[root]
      }
    }
    byProject = store.taggedByProject(byProject, usable)
    var merged = store.mergedRuns(byProject, usable)
    var applied = {}
    var ids = Object.keys(merged.owner)
    for (var d = 0; d < ids.length; d++) applied[ids[d]] = 0
    var after = {}
    for (var o in okRoots) after[o] = store.ownedRuns(byProject[o], merged.owner, o)
    // Compared before the runs are replaced; raised below only while open.
    var alerts = store.active ? store.alertsOf(prev, byProject, merged.owner, okRoots, usable) : []
    store.runsByProject = byProject
    store.projectErrors = errors
    store.asOfSeq = 0
    store.appliedSeq = applied
    store.runs = merged.runs
    if (!anyOk) {
      store.amStatus = "error"
      store.lastError = firstError
      store.emitReplied(usable, outcomes, prev, after)
      return
    }
    store.settleAfterSnapshot()
    store.logsAfterSnapshot()
    if (pollTimer.running && store.watchSchemaError !== "") {
      // The watch's schema banner outlives the polling snapshots.
      store.amStatus = "schema"
      store.lastError = store.watchSchemaError
    } else {
      store.amStatus = "ok"
      store.lastError = ""
    }
    store.stale = false
    if (store.active) {
      staleTimer.restart()
      if (!store.watchTried) store.startWatch()
      else if (store.watching && !store.sameRoots(watchState.roots, store.watchableRoots())) {
        store.stopWatch()
        store.startWatch()
      }
      store.raiseAlerts(alerts)
      var armed = Runs.copyMap(store.armedRoots)
      for (var ok in okRoots) armed[ok] = true
      store.armedRoots = armed
    }
    store.emitReplied(usable, outcomes, prev, after)
  }
```

(Compared with today: `var prev = store.runsByProject` moved up above the AmMissing branch, so both branches read the runs before the reply; `outcomes` is filled per matched root; `after` holds each ok root's owned runs; three `store.emitReplied(...)` calls end the three paths that matched an entry.)

Then append to the doc comment directly above `applyProjects` — find its last two lines:

```qml
  // `stale` stay as they are. A failed entry, a root with no entry and a
  // closed panel never change armedRoots.
```

and replace them with:

```qml
  // `stale` stay as they are. A failed entry, a root with no entry and a
  // closed panel never change armedRoots. Last, once the state is applied,
  // each root with a matched entry gets snapshotReplied in registry order
  // (emitReplied): "missing" for each in an AmMissing reply, else "ok" for an
  // ok entry, with the runs the merged list attributes to it (ownedRuns), and
  // "failed" for any other, with [].
```

- [ ] **Step 6: Emit from `forgetLive`**

In `core/stores/RunStore.qml`, find:

```qml
  // The live state of the store last seen is forgotten: the cursor, the
  // nudges and their debounce, the runs and every root's list of them, and
  // the alerts (the next list snapshot only arms). Selection, logs, controls
  // and dispatch stay.
  function forgetLive() {
    store.watchCursor = 0
    store.nudges = {}
    debounceTimer.stop()
    store.runs = []
    store.runsByProject = {}
    store.armedRoots = {}
  }
```

and replace it with:

```qml
  // The live state of the store last seen is forgotten: the cursor, the
  // nudges and their debounce, the runs and every root's list of them, and
  // the alerts (the next list snapshot only arms). Then snapshotReplied(root,
  // "missing", previousRuns, []) for every usable root, in registry order.
  // Selection, logs, controls and dispatch stay.
  function forgetLive() {
    var prev = store.runsByProject
    store.watchCursor = 0
    store.nudges = {}
    debounceTimer.stop()
    store.runs = []
    store.runsByProject = {}
    store.armedRoots = {}
    var usable = store.usableRoots()
    var outcomes = {}
    for (var i = 0; i < usable.length; i++) outcomes[usable[i].root] = "missing"
    store.emitReplied(usable, outcomes, prev, {})
  }
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: PASS — `tests/core/stores/tst_run_store.qml` shows `0 failed` (312 tests: 304 existing + 8 new, plus init/cleanup), no `TypeError` line, exit status 0.

- [ ] **Step 8: Run the whole suite**

Run: `bash tests/run.sh`
Expected: PASS — pytest green and every QML file `0 failed`, exit status 0 (nothing is wired to the signal yet, so no other file changes behaviour).

- [ ] **Step 9: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): RunStore emits snapshotReplied per project reply"
```

---

### Task 3: The cut-over — alerts move to `RunAlertsStore`, shims on `RunStore`, App wiring

One change a reviewer sees whole: the tests move, the RunStore alerts members and couplings go, the shims arrive, and App composes and routes.

**Files:**
- Modify: `tests/core/stores/tst_run_store.qml` (header comment, `make()` lines 33-37, the moved tests and helpers, the timer list at ~2629, R9-R10 appended to the 2.2 section)
- Modify: `tests/core/stores/tst_run_alerts_store.qml` (append the wired-RunStore section before the final `}`)
- Modify: `tests/core/stores/tst_app_runs.qml` (header comment; A1-A4 appended before the final `}`)
- Modify: `core/stores/RunStore.qml`
- Modify: `core/stores/App.qml`

**Interfaces:**
- Consumes: Task 1's `RunAlertsStore` members; Task 2's `snapshotReplied`, `emitReplied`, `ownedRuns`.
- Produces (read by `ui/`, `tests/ui/` and the last story):
  - `RunStore.alertsStore` (`property var`, default `null`)
  - read-only shims on `RunStore`: `armedRoots` (var, `({})` without handle), `alertsArmed` (bool, `false`), `toasts` (var, `[]`), `toastMs` (int, `0`), `toastTimer` (var, `null`), `notifyRunners` (var, `[]`)
  - function shims on `RunStore`: `raiseAlerts(alerts)`, `expireToasts(nowMs)`, `dismissToast(key)`, `dismissAllToasts()`, `notify(alert)` — each returns the target's result, or `undefined` without a handle
  - `App.runAlerts` (`readonly property RunAlertsStore`)
  - test helpers in both store test files: `wireAlerts(store)` → RunAlertsStore, `alerts(store)` → RunAlertsStore | null

- [ ] **Step 1: Wire the RunStore tests and write R9-R10**

In `tests/core/stores/tst_run_store.qml`:

(a) Find the header comment's last lines:

```qml
// project switch leaves alone. Built directly and driven through stubbed
// Process objects.
```

and replace them with:

```qml
// project switch leaves alone, and the snapshotReplied it emits. Built
// directly, wired to a RunAlertsStore the way App wires app.runAlerts, and
// driven through stubbed Process objects. The alerts themselves are tested in
// tst_run_alerts_store.qml.
```

(b) Find:

```qml
  function make() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }
```

and replace it with:

```qml
  // A RunStore wired to its own RunAlertsStore (wireAlerts).
  function make() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var store = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    wireAlerts(store)
    return store
  }

  // Every {store, alerts} pair wireAlerts made.
  property var alertsPairs: []

  // A RunAlertsStore wired to `store` the way App wires app.runAlerts:
  // backendDir copied; active, notifyOnEscalation and projectRoots bound to
  // the run store's own; store.alertsStore set; snapshotReplied routed to it.
  function wireAlerts(store) {
    var comp = Qt.createComponent("../../../core/stores/RunAlertsStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var a = comp.createObject(tc, { backendDir: store.backendDir })
    a.active = Qt.binding(function() { return store.active })
    a.notifyOnEscalation = Qt.binding(function() { return store.notifyOnEscalation })
    a.projectRoots = Qt.binding(function() { return store.projectRoots })
    store.alertsStore = a
    store.snapshotReplied.connect(a.snapshotReplied)
    tc.alertsPairs = tc.alertsPairs.concat([{ store: store, alerts: a }])
    return a
  }

  // The RunAlertsStore wireAlerts paired with `store`; null when none.
  function alerts(store) {
    for (var i = 0; i < tc.alertsPairs.length; i++) {
      if (tc.alertsPairs[i].store === store) return tc.alertsPairs[i].alerts
    }
    return null
  }
```

(c) In `test_logs_add_no_timer_and_none_runs_while_idle`, find:

```qml
    compare(timers.sort().join(","), "debounceTimer,dispatchDebounceTimer,flashTimer,livenessTimer,pendingTimer,pollTimer,staleTimer,toastTimer", "the logs add no timer")
```

and replace it with:

```qml
    compare(timers.sort().join(","), "debounceTimer,dispatchDebounceTimer,flashTimer,livenessTimer,pendingTimer,pollTimer,staleTimer", "the logs add no timer")
```

(d) Append these two tests at the end of the `// ---- snapshotReplied (split-runstore 2.2)` section, i.e. immediately before the file's final `}` (after `test_a_cursor_reset_emits_missing_for_every_usable_root`):

```qml

  // R9
  function test_without_an_alerts_store_the_shims_are_empty_and_inert() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var store = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    compare(store.alertsStore, null)
    compare(JSON.stringify(store.armedRoots), "{}")
    compare(store.alertsArmed, false)
    compare(JSON.stringify(store.toasts), "[]")
    compare(store.toastMs, 0)
    compare(store.toastTimer, null)
    compare(JSON.stringify(store.notifyRunners), "[]")
    compare(store.raiseAlerts([{ id: "a", title: "t", state: "escalated", reason: "r", project: "p" }]), undefined)
    compare(store.expireToasts(0), undefined)
    compare(store.dismissToast(1), undefined)
    compare(store.dismissAllToasts(), undefined)
    compare(store.notify({ title: "t", reason: "r" }), undefined)
    compare(store.toasts.length, 0, "nothing was raised")
  }

  // R10
  function test_the_shims_follow_the_alerts_store_and_notify() {
    var store = make(); if (!store) return
    var a = alerts(store)
    verify(store.alertsStore === a, "the handle is the paired alerts store")
    verify(store.toasts === a.toasts)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "toastsChanged" })
    a.raiseAlerts([{ id: "r1", title: "m-r1", state: "escalated", reason: "escalated", project: "alpha" }])
    compare(spy.count, 1, "the shim notifies like the original")
    verify(store.toasts === a.toasts)
    compare(store.toasts[0].id, "r1")
    compare(store.alertsArmed, false)
    a.armedRoots = ({ "/home/u/x": true })
    compare(store.alertsArmed, true)
    compare(JSON.stringify(store.armedRoots), JSON.stringify({ "/home/u/x": true }))
    compare(store.toastMs, 8000)
    verify(store.toastTimer === a.toastTimer)
    verify(store.notifyRunners === a.notifyRunners)
    store.dismissAllToasts()
    compare(a.toasts.length, 0, "a forward reaches the alerts store")
    compare(spy.count, 2)
  }
```

- [ ] **Step 2: Write the App wiring tests (A1-A4)**

In `tests/core/stores/tst_app_runs.qml`:

(a) Find the header comment's last lines:

```qml
// panel-open flag -- and the couplings between the run monitor's concerns,
// driven through App. The store's own behaviour is tested in tst_run_store.qml.
```

and replace them with:

```qml
// panel-open flag -- and the couplings between the run monitor's concerns,
// driven through App, including `app.runAlerts`, which App feeds with the run
// store's snapshotReplied. The stores' own behaviour is tested in
// tst_run_store.qml and tst_run_alerts_store.qml.
```

(b) Insert immediately before the file's final `}` (after `test_a_project_leaving_the_registry_through_app_loses_its_arming`):

```qml

  // ---- app.runAlerts (split-runstore 2.2)

  // A1
  function test_app_composes_run_alerts_wired_to_the_run_store() {
    var app = makeBare(); if (!app) return
    verify(app.runAlerts, "App composes the alerts store")
    verify(app.runs.alertsStore === app.runAlerts, "the run store's shim handle")
    compare(app.runAlerts.backendDir, "/plugin/core/backend/")
    app.backendDir = "/other/"
    compare(app.runAlerts.backendDir, "/other/", "backendDir follows App")
    compare(app.runAlerts.active, false)
    app.panelOpen = true
    compare(app.runAlerts.active, true, "active follows panelOpen")
    app.panelOpen = false
    compare(app.runAlerts.active, false)
    compare(app.runAlerts.notifyOnEscalation, false)
    app.runs.notifyOnEscalation = true
    compare(app.runAlerts.notifyOnEscalation, true, "the switch follows the run store's")
    app.projects.applyStoredState('{"last_project": null}', 0)
    app.projects.applyProjectsList([pA, pB])
    compare(app.runAlerts.projectRoots.length, 2)
    verify(app.runAlerts.projectRoots === app.runs.projectRoots, "the run store's registry")
  }

  // A2
  function test_a_snapshot_through_app_toasts_on_run_alerts() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runAlerts.toasts.length, 0, "the first snapshots only arm")
    compare(app.runAlerts.alertsArmed, true)
    snapshot(app, listReply([escalatedIn("r1")], []))
    compare(app.runAlerts.toasts.length, 1)
    compare(app.runAlerts.toasts[0].id, "r1")
    compare(app.runAlerts.toasts[0].project, "alpha")
    verify(app.runs.toasts === app.runAlerts.toasts, "the run store's shim reads the same list")
  }

  // A3
  function test_am_missing_through_app_disarms_run_alerts() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runAlerts.alertsArmed, true)
    snapshot(app, missingReply())
    compare(app.runAlerts.alertsArmed, false)
    snapshot(app, listReply([escalatedIn("r1")], []))
    compare(app.runAlerts.toasts.length, 0, "the first good snapshot after am came back only arms")
    compare(app.runAlerts.alertsArmed, true)
  }

  // A4
  function test_closing_the_panel_through_app_empties_run_alerts() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    snapshot(app, listReply([escalatedIn("r1")], []))
    compare(app.runAlerts.toasts.length, 1)
    app.panelOpen = false
    compare(app.runAlerts.toasts.length, 0)
    compare(app.runAlerts.alertsArmed, false)
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store; bash tests/run.sh tst_app_runs`
Expected: FAIL — in `tst_run_store.qml`, `wireAlerts` assigns `alertsStore`, which `RunStore` does not have yet, so tests built through `make()` fail or the run prints a `TypeError` line, and R9 fails on `toastMs` (8000, not 0); in `tst_app_runs.qml`, A1-A4 fail because `app.runAlerts` is undefined. Both runs exit non-zero.

- [ ] **Step 4: Move the alerts tests into `tst_run_alerts_store.qml`**

In `tests/core/stores/tst_run_alerts_store.qml`, insert this block immediately before the file's final `}` (after `test_notifications_follow_the_switch`). Each moved body is byte-identical to its `tst_run_store.qml` original except that every read, write or call of `armedRoots`, `alertsArmed`, `toasts`, `toastMs`, `toastTimer`, `notifyRunners`, `raiseAlerts`, `expireToasts`, `dismissToast`, `dismissAllToasts` or `notify` on a run store goes through `alerts(<store>)`:

```qml

  // ---- through a RunStore wired the way App wires app.runAlerts

  // A RunStore wired to its own RunAlertsStore (wireAlerts).
  function make() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var store = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    wireAlerts(store)
    return store
  }

  // Every {store, alerts} pair wireAlerts made.
  property var alertsPairs: []

  // A RunAlertsStore wired to `store` the way App wires app.runAlerts:
  // backendDir copied; active, notifyOnEscalation and projectRoots bound to
  // the run store's own; store.alertsStore set; snapshotReplied routed to it.
  function wireAlerts(store) {
    var comp = Qt.createComponent("../../../core/stores/RunAlertsStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var a = comp.createObject(tc, { backendDir: store.backendDir })
    a.active = Qt.binding(function() { return store.active })
    a.notifyOnEscalation = Qt.binding(function() { return store.notifyOnEscalation })
    a.projectRoots = Qt.binding(function() { return store.projectRoots })
    store.alertsStore = a
    store.snapshotReplied.connect(a.snapshotReplied)
    tc.alertsPairs = tc.alertsPairs.concat([{ store: store, alerts: a }])
    return a
  }

  // The RunAlertsStore wireAlerts paired with `store`; null when none.
  function alerts(store) {
    for (var i = 0; i < tc.alertsPairs.length; i++) {
      if (tc.alertsPairs[i].store === store) return tc.alertsPairs[i].alerts
    }
    return null
  }

  // A store with `roots` registered and no project open: the snapshot of
  // every root is in flight.
  function makeWithRoots(roots) {
    var store = make(); if (!store) return null
    store.projectRoots = registry(roots)
    return store
  }

  // An active store (the panel is open) with `roots` registered and no
  // project open: the snapshot of every root is in flight.
  function activeRoots(roots) {
    var store = make(); if (!store) return null
    store.active = true
    store.projectRoots = registry(roots)
    return store
  }

  // A store with one registered project, `root`, open: its first snapshot (of
  // that root alone) is in flight.
  function makeWithProject(root) {
    var store = make(); if (!store) return null
    store.projectRoots = [rootEntry(root)]
    store.project = root
    return store
  }

  // An active store (the panel is open) with project `root` registered and
  // open: its first snapshot is in flight.
  function activeStore(root) {
    var store = make(); if (!store) return null
    store.active = true
    store.projectRoots = [rootEntry(root)]
    store.project = root
    return store
  }

  // One snapshot entry: an `am runs` summary whose `status` string the helper
  // has replaced with the `am status` data. Its repo_dir is `root`, else rootA.
  function entry(id, runStatus, live, root) {
    var run = { id: id, milestone_id: "m-" + id }
    if (runStatus !== "") run.status = runStatus
    return {
      id: id, workflow: "orchestrator", repo_dir: root || tc.rootA, started_at: "2026-10-01T00:00:00Z",
      status: {
        run: run,
        rows: [],
        stories: [],
        subtasks: [],
        control: { lease: { pid: 42, host: "h", heartbeat_at: "2026-10-01T00:00:05Z", accepting: true, live: live } }
      }
    }
  }

  // runs-snapshot-all.py's reply line: {"ok": true, "projects": projects, "data_dir"}.
  function allReply(projects) {
    return JSON.stringify({ ok: true, projects: projects, data_dir: "/home/u/.local/share" }) + "\n"
  }

  // One root's entry that answered, listing `runs`.
  function okEntry(root, runs) { return { root: root, ok: true, runs: runs } }

  // One root's entry that failed with {type, message}.
  function failEntry(root, type, message) {
    return { root: root, ok: false, error: { type: type, message: message } }
  }

  // A reply where every root answered: rootA's entry, then one per other
  // root the entries' repo_dir names, in first-seen order, each listing the
  // entries with that repo_dir. The store ignores a root it has not registered.
  function okReply(entries) {
    var order = [tc.rootA]
    var byRoot = {}
    byRoot[tc.rootA] = []
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      var root = e !== null && typeof e === "object" && typeof e.repo_dir === "string" ? e.repo_dir : tc.rootA
      if (!byRoot.hasOwnProperty(root)) {
        byRoot[root] = []
        order.push(root)
      }
      byRoot[root].push(e)
    }
    return allReply(order.map(function(r) { return tc.okEntry(r, byRoot[r]) }))
  }

  // The next snapshot of project A lists `entries`.
  function snapshot(store, entries) {
    store.refresh()
    reply(store.snapshotRunner.current, okReply(entries), 0)
  }

  // entry() for the control tests: the run's workflow ("milestone" unless
  // given), its am control requests, and whether its lease accepts requests.
  function ctlEntry(id, runStatus, live, workflow, requests, accepting) {
    var e = entry(id, runStatus, live)
    e.workflow = workflow || "milestone"
    e.status.control.requests = requests || []
    if (accepting === false) e.status.control.lease.accepting = false
    return e
  }

  function running(id) { return ctlEntry(id, "started", true) }

  function dead(id) { return ctlEntry(id, "started", false) }

  function ids(list) { return list.map(function(r) { return r.id }).join(",") }

  // One stdout line of a watch: an object is sent as its JSON, a string as is.
  function sendLine(proc, value) {
    proc.stdout.read(typeof value === "string" ? value : JSON.stringify(value))
  }

  // synthetic: one runs-watch.py changed line, {"changed": [{run, seq}, ...]},
  // for pairs [run, seq, run, seq, ...].
  function nudge(store, pairs) {
    var list = []
    for (var i = 0; i < pairs.length; i += 2) list.push({ run: pairs[i], seq: pairs[i + 1] })
    sendLine(store.watchProc, { changed: list })
  }

  // A timer firing on its own: a one-shot timer has stopped by the time its
  // triggered() is emitted.
  function fire(timer) {
    if (!timer.repeat) timer.stop()
    timer.triggered()
  }

  // An active store with A, B and C registered and no project open, whose
  // first snapshot listed a1 under A, b1 under B and c1 under C (all done):
  // its watch runs and nothing is in flight.
  function threeRoots() {
    var store = activeRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return null
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                                                  okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)]),
                                                  okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])]), 0)
    verify(store.watchProc, "the watch was started")
    return store
  }
  function escalated(id) { return entry(id, "escalated", false) }

  function toastIds(store) { return alerts(store).toasts.map(function(t) { return t.id }).join(",") }

  // The armed roots of `store`, sorted, comma-joined.
  function armedKeys(store) { return Object.keys(alerts(store).armedRoots).sort().join(",") }

  function bothRoots() { return [tc.rootA, tc.rootB].sort().join(",") }

  // The next list reply of `store`: a snapshot of every root, answered with `projects`.
  function answer(store, projects) {
    store.refresh()
    reply(store.snapshotRunner.current, allReply(projects), 0)
  }

  // An active store with A and B registered and no project open, whose first
  // reply listed `aRuns` under A and `bRuns` under B: both are armed, nothing raised.
  function armedTwo(aRuns, bRuns) {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return null
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, aRuns), okEntry(tc.rootB, bRuns)]), 0)
    compare(armedKeys(store), bothRoots(), "the first reply arms both")
    compare(alerts(store).alertsArmed, true)
    compare(alerts(store).toasts.length, 0, "and raises nothing")
    return store
  }

  // An active store on project A whose first snapshot listed `entries`: that
  // snapshot only armed the alerts.
  function armedStore(entries) {
    var store = activeStore(rootA); if (!store) return null
    reply(store.snapshotRunner.current, okReply(entries), 0)
    compare(alerts(store).alertsArmed, true, "the first good snapshot while open arms the alerts")
    compare(alerts(store).toasts.length, 0, "and raises nothing")
    return store
  }

  // Kept behaviour: a refresh that escalates a run raises one toast.
  function test_a_nudge_refresh_that_escalates_a_run_raises_one_toast() {
    var store = threeRoots(); if (!store) return
    nudge(store, ["b1", 5])
    fire(store.debounceTimer)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [entry("b1", "escalated", false, tc.rootB)])]), 0)
    compare(alerts(store).toasts.length, 1)
    compare(alerts(store).toasts[0].id, "b1")
    compare(alerts(store).toasts[0].state, "escalated")
    nudge(store, ["b1", 6])
    fire(store.debounceTimer)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [entry("b1", "escalated", false, tc.rootB)])]), 0)
    compare(alerts(store).toasts.length, 1, "still escalated: no second toast")
  }
  // ---- alerts: the toasts (S2 4.4)

  // 1
  function test_no_toast_while_the_panel_is_closed() {
    var store = makeWithProject(rootA); if (!store) return
    compare(alerts(store).alertsArmed, false)
    compare(alerts(store).toasts.length, 0)
    reply(store.snapshotRunner.current, okReply([running("a")]), 0)
    snapshot(store, [escalated("a")])
    compare(alerts(store).toasts.length, 0)
    compare(alerts(store).alertsArmed, false, "a closed panel never arms")
  }

  // 2
  function test_a_run_that_turns_escalated_raises_one_toast() {
    var store = activeStore(rootA); if (!store) return
    compare(alerts(store).toastMs, 8000)
    reply(store.snapshotRunner.current, okReply([escalated("a"), running("b")]), 0)
    compare(alerts(store).toasts.length, 0, "the first snapshot after opening never replays history")
    compare(alerts(store).alertsArmed, true)
    var before = Date.now()
    snapshot(store, [escalated("a"), escalated("b")])
    compare(alerts(store).toasts.length, 1)
    var t = alerts(store).toasts[0]
    compare(t.id, "b")
    compare(t.title, "m-b")
    compare(t.state, "escalated")
    compare(t.reason, Runs.escalationReason(store.runById("b")))
    compare(t.reason, "escalated")
    compare(typeof t.key, "number")
    verify(t.expiresMs >= before + 8000 && t.expiresMs <= Date.now() + 8000, "it expires 8 s from now")
  }

  // 3
  function test_a_run_still_escalated_raises_nothing_again() {
    var store = armedStore([running("a")]); if (!store) return
    snapshot(store, [escalated("a")])
    compare(alerts(store).toasts.length, 1)
    var key = alerts(store).toasts[0].key
    snapshot(store, [escalated("a")])
    compare(alerts(store).toasts.length, 1)
    compare(alerts(store).toasts[0].key, key, "the same toast, not a new one")
  }

  // 4 (Review focus: reopening never replays history)
  function test_closing_empties_the_toasts_and_reopening_raises_nothing_at_first() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    snapshot(store, [escalated("a"), running("b")])
    compare(alerts(store).toasts.length, 1)
    store.active = false
    compare(alerts(store).toasts.length, 0, "a toast never outlives the panel opening")
    compare(alerts(store).alertsArmed, false)
    store.active = true
    compare(alerts(store).alertsArmed, false)
    reply(store.snapshotRunner.current, okReply([escalated("a"), dead("b")]), 0)
    compare(alerts(store).toasts.length, 0, "b died while the panel was closed: not replayed")
    compare(alerts(store).alertsArmed, true)
    snapshot(store, [escalated("a"), dead("b"), escalated("c")])
    compare(toastIds(store), "c")
  }

  // Review Focus 1 (D3)
  function test_a_snapshot_landing_after_the_panel_closed_raises_nothing_and_does_not_arm() {
    var store = armedStore([running("a")]); if (!store) return
    store.refresh()
    var late = store.snapshotRunner.current
    store.active = false
    reply(late, okReply([escalated("a")]), 0)
    compare(store.runs[0].status, "escalated", "the snapshot itself is still applied")
    compare(alerts(store).toasts.length, 0)
    compare(alerts(store).alertsArmed, false)
  }

  // 5
  function test_am_missing_disarms_and_a_failed_snapshot_does_not() {
    var store = armedStore([running("a")]); if (!store) return
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmMissing", "am is not installed")]), 0)
    compare(store.runs.length, 0)
    compare(alerts(store).alertsArmed, false)
    snapshot(store, [escalated("a")])
    compare(alerts(store).toasts.length, 0, "the first good snapshot after am came back raises nothing")
    compare(alerts(store).alertsArmed, true)
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "b", "the one after that compares normally")

    var other = armedStore([running("x")]); if (!other) return
    other.refresh()
    reply(other.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "HelperError", message: "boom" } }) + "\n", 1)
    compare(alerts(other).alertsArmed, true, "a failed snapshot keeps the baseline")
    other.refresh()
    reply(other.snapshotRunner.current, "garbage\n", 1)
    compare(alerts(other).alertsArmed, true)
    snapshot(other, [escalated("x")])
    compare(toastIds(other), "x")
  }

  // 6
  function test_five_alerts_in_one_snapshot_leave_the_last_three_toasts() {
    var store = armedStore([]); if (!store) return
    snapshot(store, [escalated("r1"), escalated("r2"), dead("r3"), escalated("r4"), dead("r5")])
    compare(toastIds(store), "r3,r4,r5")
    verify(alerts(store).toasts[0].key < alerts(store).toasts[1].key && alerts(store).toasts[1].key < alerts(store).toasts[2].key, "keys only grow")
    compare(alerts(store).toasts[0].state, "dead")
    compare(alerts(store).toasts[0].reason, "process died")
  }

  // 7
  function test_a_run_that_alerts_again_replaces_its_own_toast() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "a,b")
    var oldKey = alerts(store).toasts[0].key
    snapshot(store, [dead("a"), escalated("b")])
    compare(toastIds(store), "b,a", "a's old toast went and its new one is the newest")
    compare(alerts(store).toasts[1].state, "dead")
    compare(alerts(store).toasts[1].reason, "process died")
    verify(alerts(store).toasts[1].key > oldKey, "a new key")
  }

  // 8
  function test_toasts_expire_and_the_timer_runs_only_while_open_with_toasts() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    var timer = alerts(store).toastTimer
    compare(timer.objectName, "toastTimer")
    compare(timer.interval, 250)
    compare(timer.repeat, true)
    compare(timer.running, false, "no toast: no timer")
    snapshot(store, [escalated("a"), running("b")])
    compare(timer.running, true)
    var aExpires = alerts(store).toasts[0].expiresMs
    alerts(store).toastMs = 60000
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "a,b")
    alerts(store).expireToasts(aExpires - 1)
    compare(toastIds(store), "a,b", "not yet")
    alerts(store).expireToasts(aExpires)
    compare(toastIds(store), "b", "expiresMs <= now goes")
    alerts(store).dismissAllToasts()
    compare(timer.running, false, "nothing left: no timer")
    alerts(store).toastMs = 50
    snapshot(store, [escalated("a"), dead("b")])
    compare(alerts(store).toasts.length, 1)
    tryVerify(function() { return alerts(store).toasts.length === 0 }, 2000, "the timer dropped the expired toast")
    compare(timer.running, false)
  }

  // 9 (and Review Focus 2)
  function test_dismiss_removes_one_toast_by_key_and_dismiss_all_empties() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    snapshot(store, [escalated("a"), escalated("b")])
    var keyA = alerts(store).toasts[0].key
    alerts(store).dismissToast(-12345)
    compare(toastIds(store), "a,b", "an unknown key changes nothing")
    alerts(store).dismissToast(keyA)
    compare(toastIds(store), "b")
    snapshot(store, [dead("a"), escalated("b")])
    compare(toastIds(store), "b,a")
    alerts(store).dismissToast(keyA)
    compare(toastIds(store), "b,a", "a's stale key leaves its newer toast")
    alerts(store).dismissAllToasts()
    compare(alerts(store).toasts.length, 0)
  }

  // 10 (the toast half; Task 2 pins the setting half)
  function test_a_project_switch_keeps_the_toasts_and_the_alerts_armed() {
    var store = armedStore([running("a")]); if (!store) return
    snapshot(store, [escalated("a")])
    compare(alerts(store).toasts.length, 1)
    store.project = rootB
    compare(alerts(store).toasts.length, 1)
    compare(alerts(store).alertsArmed, true)
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "a,b", "the next snapshot compares as before")
  }
  // ---- alerts across projects (3.4)

  // 1
  function test_an_escalation_in_another_project_raises_one_toast_with_its_project() {
    var store = armedTwo([running("a1")], [running("b1")]); if (!store) return
    compare(store.project, "")
    store.notifyOnEscalation = true
    answer(store, [okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1")])])
    compare(toastIds(store), "b1")
    compare(alerts(store).toasts[0].project, "beta")
    compare(alerts(store).toasts[0].title, "m-b1")
    compare(alerts(store).toasts[0].state, "escalated")
    compare(alerts(store).notifyRunners.length, 1, "one notification")
    compare(argv(alerts(store).notifyRunners[0].current), tc.notifyCmd + "m-b1|escalated", "its text does not change")
  }

  // 2
  function test_a_project_that_first_fails_or_joins_later_only_arms_on_its_first_good_entry() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")]),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(armedKeys(store), tc.rootA, "only A answered")
    answer(store, [okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1"), dead("b2")])])
    compare(alerts(store).toasts.length, 0, "B's first good entry only arms")
    compare(armedKeys(store), bothRoots())
    answer(store, [okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1"), dead("b2"), escalated("b3")])])
    compare(toastIds(store), "b3", "the entry after that compares normally")
    compare(alerts(store).toasts[0].project, "beta")
    store.projectRoots = registry([tc.rootA, tc.rootB, tc.rootC])
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")]),
                                                  okEntry(tc.rootB, [escalated("b1"), dead("b2"), escalated("b3")]),
                                                  okEntry(tc.rootC, [escalated("c1")])]), 0)
    compare(toastIds(store), "b3", "a project added later: its first entry raises nothing")
    compare(armedKeys(store), [tc.rootA, tc.rootB, tc.rootC].sort().join(","), "and arms it")
  }

  // 3
  function test_a_failing_project_raises_nothing_and_stays_armed() {
    var store = armedTwo([running("a1")], [running("b1"), escalated("b2")]); if (!store) return
    answer(store, [okEntry(tc.rootA, [running("a1")]), failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")])
    compare(alerts(store).toasts.length, 0, "a failed entry raises nothing")
    compare(ids(store.runsByProject[tc.rootB]), "b1,b2", "B keeps its runs")
    compare(armedKeys(store), bothRoots(), "and stays armed")
    answer(store, [okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1"), escalated("b2")])])
    compare(toastIds(store), "b1", "the recovery compares against the kept runs: b2 is not replayed")
    compare(alerts(store).toasts[0].project, "beta")
  }

  // 4
  function test_an_am_missing_spell_disarms_every_project() {
    var store = armedTwo([running("a1")], [running("b1")]); if (!store) return
    answer(store, [failEntry(tc.rootA, "AmMissing", "am is not installed."), failEntry(tc.rootB, "AmMissing", "am is not installed.")])
    compare(armedKeys(store), "")
    compare(alerts(store).alertsArmed, false)
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), okEntry(tc.rootB, [escalated("b1")])])
    compare(alerts(store).toasts.length, 0, "the next good reply only arms")
    compare(armedKeys(store), bothRoots())
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), failEntry(tc.rootB, "AmMissing", "am is not installed.")])
    compare(store.amStatus, "ok", "AmMissing beside an ok entry is no spell")
    compare(ids(store.runsByProject[tc.rootB]), "b1", "B keeps its runs")
    compare(armedKeys(store), bothRoots(), "and its armed state")
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), okEntry(tc.rootB, [escalated("b1"), dead("b2")])])
    compare(toastIds(store), "b2")
  }

  // 5 and Review Focus 4
  function test_a_run_listed_under_two_roots_alerts_once_under_the_first() {
    var store = armedTwo([running("x")], [running("x")]); if (!store) return
    store.notifyOnEscalation = true
    // B's entry first: the registry's order decides, not the reply's.
    answer(store, [okEntry(tc.rootB, [escalated("x")]), okEntry(tc.rootA, [escalated("x")])])
    compare(toastIds(store), "x")
    compare(alerts(store).toasts[0].project, "alpha")
    compare(alerts(store).notifyRunners.length, 1, "one notification")
    store.projectRoots = registry([tc.rootB, tc.rootA])
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [escalated("x")]), okEntry(tc.rootB, [escalated("x")])]), 0)
    compare(store.runs[0].project.root, tc.rootB, "B owns x now")
    compare(alerts(store).toasts.length, 1, "a new owner replays nothing")
    compare(alerts(store).notifyRunners.length, 1)
  }

  // 5: the owner decides, even when only the other root answers
  function test_a_run_listed_under_two_roots_alerts_only_from_its_owners_entry() {
    var store = armedTwo([running("x")], [running("x")]); if (!store) return
    answer(store, [failEntry(tc.rootA, "AmTimeout", "am did not answer within 60 s."), okEntry(tc.rootB, [escalated("x")])])
    compare(store.runs[0].project.root, tc.rootA, "A still owns x")
    compare(alerts(store).toasts.length, 0, "B's entry never alerts a run A owns")
    answer(store, [okEntry(tc.rootA, [escalated("x")]), okEntry(tc.rootB, [escalated("x")])])
    compare(toastIds(store), "x", "A's own entry does")
    compare(alerts(store).toasts[0].project, "alpha")
  }

  // Review Focus 1, 2 and 3
  function test_a_partial_or_failed_reply_leaves_the_other_roots_arming_alone() {
    // synthetic: a run without an id under B.
    var store = armedTwo([running("a1")], [running("b1"), entry("", "started", true)]); if (!store) return
    var armed = alerts(store).armedRoots
    store.refresh()
    reply(store.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "Usage", message: "usage" } }) + "\n", 2)
    verify(alerts(store).armedRoots === armed, "a whole-call failure leaves the arming alone")
    store.refresh()
    reply(store.snapshotRunner.current, "garbage\n", 1)
    verify(alerts(store).armedRoots === armed, "so does garbage")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [escalated("b1"), entry("", "escalated", false)])]), 0)
    compare(toastIds(store), "b1", "a run without an id never alerts")
    compare(alerts(store).toasts[0].project, "beta")
    compare(armedKeys(store), bothRoots(), "A, with no entry, stays armed")
    compare(ids(store.runsByProject[tc.rootA]), "a1")
  }

  // 7
  function test_a_project_switch_keeps_the_toasts_and_every_projects_arming() {
    var store = armedTwo([running("a1")], [running("b1")]); if (!store) return
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), okEntry(tc.rootB, [running("b1")])])
    compare(toastIds(store), "a1")
    compare(alerts(store).toasts[0].project, "alpha")
    var toasts = alerts(store).toasts
    var armed = alerts(store).armedRoots
    var targets = [tc.rootA, ""]
    for (var i = 0; i < targets.length; i++) {
      var label = "project " + JSON.stringify(targets[i])
      store.project = targets[i]
      verify(alerts(store).toasts === toasts, label + ": the toasts")
      verify(alerts(store).armedRoots === armed, label + ": the arming")
    }
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), okEntry(tc.rootB, [escalated("b1")])])
    compare(toastIds(store), "a1,b1", "the next escalation still alerts")
    compare(alerts(store).toasts[1].project, "beta")
  }

  // the closed panel (spec §2)
  function test_a_reply_while_the_panel_is_closed_raises_nothing_and_arms_nothing() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [running("b1")])]), 0)
    compare(armedKeys(store), "", "a closed panel never arms")
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), okEntry(tc.rootB, [escalated("b1")])])
    compare(alerts(store).toasts.length, 0)
    compare(armedKeys(store), "")
    compare(ids(store.runs), "a1,b1", "the runs are still applied")
  }

  // 6
  function test_a_root_that_leaves_the_registry_loses_its_arming() {
    var store = armedTwo([running("a1")], [running("b1")]); if (!store) return
    store.projectRoots = registry([tc.rootA])
    compare(armedKeys(store), tc.rootA, "B left: its arming goes at once")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")])]), 0)
    store.projectRoots = registry([tc.rootA, tc.rootB])
    compare(armedKeys(store), tc.rootA, "coming back does not re-arm")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1")])]), 0)
    compare(alerts(store).toasts.length, 0, "its next good entry only arms")
    compare(armedKeys(store), bothRoots())
    var armed = alerts(store).armedRoots
    store.projectRoots = [{ root: tc.rootA, name: "renamed" }, rootEntry(tc.rootB)]
    verify(alerts(store).armedRoots === armed, "no root went: the map is not replaced")
    store.projectRoots = []
    compare(armedKeys(store), "", "an empty registry arms nothing")
  }
  // ---- alerts: the desktop notifications (S2 4.4)

  // 12
  function test_with_the_setting_on_each_alert_launches_its_own_notification() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    compare(alerts(store).notifyRunners.length, 0)
    store.notifyOnEscalation = true
    snapshot(store, [escalated("a"), dead("b")])
    compare(alerts(store).notifyRunners.length, 2, "one runner per alert")
    var first = alerts(store).notifyRunners[0].current, second = alerts(store).notifyRunners[1].current
    compare(argv(first), tc.notifyCmd + "m-a|escalated")
    compare(argv(second), tc.notifyCmd + "m-b|process died")
    compare(first.running, true, "the second launch did not stop the first")
    compare(second.running, true)
    compare(first.launchGuard, "")
    reply(first, JSON.stringify({ ok: true, sent: true }) + "\n", 0)
    compare(alerts(store).notifyRunners.length, 1)
    reply(second, "garbage\n", 1)
    compare(alerts(store).notifyRunners.length, 0, "a failed notification goes too")
    compare(toastIds(store), "a,b", "the replies change nothing else")
    compare(store.flashText, "")

    snapshot(store, [escalated("a"), dead("b"), escalated("c")])
    compare(alerts(store).notifyRunners.length, 1)
    var proc = alerts(store).notifyRunners[0].current
    store.project = rootB
    compare(proc.running, true, "a project switch does not stop a launched notification")
    reply(proc, JSON.stringify({ ok: true, sent: true }) + "\n", 0)
    compare(alerts(store).notifyRunners.length, 0)

    var off = armedStore([running("a")]); if (!off) return
    snapshot(off, [escalated("a")])
    compare(alerts(off).toasts.length, 1)
    compare(alerts(off).notifyRunners.length, 0, "setting off: toasts only")

    var five = armedStore([]); if (!five) return
    five.notifyOnEscalation = true
    snapshot(five, [escalated("r1"), escalated("r2"), dead("r3"), escalated("r4"), dead("r5")])
    compare(alerts(five).toasts.length, 3)
    compare(alerts(five).notifyRunners.length, 5, "every alert notifies, even those whose toast was capped away")
  }

  // 1 (the notification half)
  function test_no_notification_while_the_panel_is_closed() {
    var store = makeWithProject(rootA); if (!store) return
    store.notifyOnEscalation = true
    reply(store.snapshotRunner.current, okReply([running("a")]), 0)
    snapshot(store, [escalated("a")])
    compare(alerts(store).notifyRunners.length, 0)
    compare(alerts(store).toasts.length, 0)
  }
```

(The file must end with the TestCase's closing `}` on its own line after `test_no_notification_while_the_panel_is_closed`.)

- [ ] **Step 5: Remove the moved tests from `tst_run_store.qml`**

Save this script as `/tmp/remove_alerts_tests.py` (outside the repository; do not commit it) and run it from the worktree root with `python3 /tmp/remove_alerts_tests.py`:

```python
# Removes the alerts tests and their own helpers from tst_run_store.qml.
SRC = "tests/core/stores/tst_run_store.qml"
MOVED = [
    "test_a_nudge_refresh_that_escalates_a_run_raises_one_toast",
    "armedStore",
    "test_no_toast_while_the_panel_is_closed",
    "test_a_run_that_turns_escalated_raises_one_toast",
    "test_a_run_still_escalated_raises_nothing_again",
    "test_closing_empties_the_toasts_and_reopening_raises_nothing_at_first",
    "test_a_snapshot_landing_after_the_panel_closed_raises_nothing_and_does_not_arm",
    "test_am_missing_disarms_and_a_failed_snapshot_does_not",
    "test_five_alerts_in_one_snapshot_leave_the_last_three_toasts",
    "test_a_run_that_alerts_again_replaces_its_own_toast",
    "test_toasts_expire_and_the_timer_runs_only_while_open_with_toasts",
    "test_dismiss_removes_one_toast_by_key_and_dismiss_all_empties",
    "test_a_project_switch_keeps_the_toasts_and_the_alerts_armed",
    "armedKeys",
    "bothRoots",
    "answer",
    "armedTwo",
    "test_an_escalation_in_another_project_raises_one_toast_with_its_project",
    "test_a_project_that_first_fails_or_joins_later_only_arms_on_its_first_good_entry",
    "test_a_failing_project_raises_nothing_and_stays_armed",
    "test_an_am_missing_spell_disarms_every_project",
    "test_a_run_listed_under_two_roots_alerts_once_under_the_first",
    "test_a_run_listed_under_two_roots_alerts_only_from_its_owners_entry",
    "test_a_partial_or_failed_reply_leaves_the_other_roots_arming_alone",
    "test_a_project_switch_keeps_the_toasts_and_every_projects_arming",
    "test_a_reply_while_the_panel_is_closed_raises_nothing_and_arms_nothing",
    "test_a_root_that_leaves_the_registry_loses_its_arming",
    "test_with_the_setting_on_each_alert_launches_its_own_notification",
    "test_no_notification_while_the_panel_is_closed",
]
LINES = [
    "  // ---- alerts across projects (3.4)",
    '  property string notifyCmd: "python3|/plugin/core/backend/runs/notify.py|"',
]
HEADER = "  // ---- alerts: the toasts (S2 4.4)"
NEW_HEADER = "  // ---- alerts (S2 4.4): the helpers the tests above share; the alerts tests are in tst_run_alerts_store.qml"


def block(lines, name):
    """(start, end) of `  function name(` with the comment lines right above it; end exclusive."""
    idx = [i for i, l in enumerate(lines) if l.startswith("  function " + name + "(")]
    assert len(idx) == 1, (name, idx)
    i = idx[0]
    start = i
    while start > 0 and lines[start - 1].startswith("  //") and not lines[start - 1].startswith("  // ----"):
        start -= 1
    if lines[i].rstrip().endswith("}") and lines[i].count("{") == lines[i].count("}"):
        return start, i + 1
    end = i + 1
    while lines[end] != "  }":
        end += 1
    return start, end + 1


def cut(lines, start, end):
    if end < len(lines) and lines[end] == "":
        end += 1
    del lines[start:end]


lines = open(SRC).read().split("\n")
for name in MOVED:
    cut(lines, *block(lines, name))
for exact in LINES:
    i = lines.index(exact)
    cut(lines, i, i + 1)
lines[lines.index(HEADER)] = NEW_HEADER
open(SRC, "w").write("\n".join(lines))
```

It deletes the 24 moved tests and the helpers only they use (`armedStore`, `armedKeys`, `bothRoots`, `answer`, `armedTwo`, the `notifyCmd` property and the `// ---- alerts across projects (3.4)` header), and keeps `escalated` and `toastIds`, which `test_a_project_switch_leaves_the_run_list_and_the_live_state_alone` and `test_a_partial_reply_keeps_the_other_roots_as_they_were` still use. Check the result:

Run: `grep -c "function test_" tests/core/stores/tst_run_store.qml`
Expected: `290` (304 before this card, + 8 from Task 2, + 2 from Step 1, − 24 moved).

Run: `grep -n "armedStore\|armedKeys\|bothRoots\|armedTwo\|notifyCmd\|answer(" tests/core/stores/tst_run_store.qml`
Expected: no output.

- [ ] **Step 6: Replace RunStore's alerts members with the shims**

In `core/stores/RunStore.qml`:

(a) Find:

```qml
  // Alerts (S2 4.4): a toast for every run of any registered project that
  // newly needs a human while the panel is open. `armedRoots` is {root: true}
  // of every usable root whose runs may be compared against, and is replaced,
  // never changed in place: a root's first good entry after an opening, a
  // store change, an am-missing spell or its return to the registry only arms
  // it, so history is never replayed. `alertsArmed`: some root is armed.
  // `toasts` is {key, id, title, state, reason, project, expiresMs}, oldest
  // first, at most 3, and is replaced, never changed in place; `project` is
  // the name of the run's project.
  property var armedRoots: ({})
  readonly property bool alertsArmed: Object.keys(store.armedRoots).length > 0
  property var toasts: []
  property int toastMs: 8000
```

and replace it with:

```qml
  // Moved to RunAlertsStore; removed by the last story
  property var alertsStore: null
  readonly property var armedRoots: store.alertsStore ? store.alertsStore.armedRoots : ({})
  readonly property bool alertsArmed: store.alertsStore ? store.alertsStore.alertsArmed : false
  readonly property var toasts: store.alertsStore ? store.alertsStore.toasts : []
  readonly property int toastMs: store.alertsStore ? store.alertsStore.toastMs : 0
  readonly property var toastTimer: store.alertsStore ? store.alertsStore.toastTimer : null
  readonly property var notifyRunners: store.alertsStore ? store.alertsStore.notifyRunners : []
  function raiseAlerts(alerts) { return store.alertsStore ? store.alertsStore.raiseAlerts(alerts) : undefined }
  function expireToasts(nowMs) { return store.alertsStore ? store.alertsStore.expireToasts(nowMs) : undefined }
  function dismissToast(key) { return store.alertsStore ? store.alertsStore.dismissToast(key) : undefined }
  function dismissAllToasts() { return store.alertsStore ? store.alertsStore.dismissAllToasts() : undefined }
  function notify(alert) { return store.alertsStore ? store.alertsStore.notify(alert) : undefined }
```

(b) Delete these two lines from the alias block (the shims above replace them):

```qml
  readonly property alias toastTimer: toastTimer
```

```qml
  readonly property alias notifyRunners: notifyState.runners    // in-flight notify.py launches, oldest first
```

(c) Find:

```qml
  // The panel opened: fetch now and read the notify switch (get-global-settings;
  // notifyTouched is cleared first unless a save is in flight); the first good
  // snapshot starts the watch and arms every root that answers in it, and the
  // stale clock counts from now.
  function startLive() {
    store.watchTried = false
    store.armedRoots = {}
    if (!settingsSaveRunner.busy) store.notifyTouched = false
```

and replace it with:

```qml
  // The panel opened: fetch now and read the notify switch (get-global-settings;
  // notifyTouched is cleared first unless a save is in flight); the first good
  // snapshot starts the watch, and the stale clock counts from now.
  function startLive() {
    store.watchTried = false
    if (!settingsSaveRunner.busy) store.notifyTouched = false
```

(d) Find:

```qml
  // The panel closed: no process and no timer is left running, and no toast
  // or dispatch outlives the opening (a start in flight runs to its end). The
```

and replace it with:

```qml
  // The panel closed: no process and no timer is left running, and no
  // dispatch outlives the opening (a start in flight runs to its end). The
```

Then find:

```qml
    store.watchWarning = ""
    store.armedRoots = {}
    store.toasts = []
    // A start in flight refuses and lands normally.
```

and replace it with:

```qml
    store.watchWarning = ""
    // A start in flight refuses and lands normally.
```

(e) Find (Task 2's version of `forgetLive`):

```qml
  // The live state of the store last seen is forgotten: the cursor, the
  // nudges and their debounce, the runs and every root's list of them, and
  // the alerts (the next list snapshot only arms). Then snapshotReplied(root,
  // "missing", previousRuns, []) for every usable root, in registry order.
  // Selection, logs, controls and dispatch stay.
  function forgetLive() {
    var prev = store.runsByProject
    store.watchCursor = 0
    store.nudges = {}
    debounceTimer.stop()
    store.runs = []
    store.runsByProject = {}
    store.armedRoots = {}
    var usable = store.usableRoots()
```

and replace it with:

```qml
  // The live state of the store last seen is forgotten: the cursor, the
  // nudges and their debounce, the runs and every root's list of them. Then
  // snapshotReplied(root, "missing", previousRuns, []) for every usable root,
  // in registry order. Selection, logs, controls and dispatch stay.
  function forgetLive() {
    var prev = store.runsByProject
    store.watchCursor = 0
    store.nudges = {}
    debounceTimer.stop()
    store.runs = []
    store.runsByProject = {}
    var usable = store.usableRoots()
```

(f) Find:

```qml
  // controlRunners), the control error, the cancel dialog, the footer flash,
  // the alerts, the toasts and the notify switch belong to every registered
  // project and stay, and no snapshot is launched. Reset: the run settings
```

and replace it with:

```qml
  // controlRunners), the control error, the cancel dialog, the footer flash
  // and the notify switch belong to every registered project and stay, and
  // no snapshot is launched. Reset: the run settings
```

(g) Find:

```qml
  // The registry changed. First the roots no longer usable lose their runs,
  // their errors and their arming (armedRoots is replaced only when a root
  // went), and `runs` is merged again in the new order with the new names;
  // no alert is raised. Then every usable root is snapshotted.
  function registryChanged() {
    var usable = store.usableRoots()
    var errors = {}
    var armed = {}
    for (var i = 0; i < usable.length; i++) {
      var root = usable[i].root
      if (Runs.hasKey(store.projectErrors, root)) errors[root] = store.projectErrors[root]
      if (Runs.hasKey(store.armedRoots, root)) armed[root] = true
    }
    var byProject = store.taggedByProject(store.runsByProject, usable)
    store.runsByProject = byProject
    store.projectErrors = errors
    if (Object.keys(armed).length !== Object.keys(store.armedRoots).length) store.armedRoots = armed
    store.runs = store.mergedRuns(byProject, usable).runs
    store.refresh()
  }
```

and replace it with:

```qml
  // The registry changed. First the roots no longer usable lose their runs
  // and their errors, and `runs` is merged again in the new order with the
  // new names; no snapshotReplied is emitted. Then every usable root is
  // snapshotted.
  function registryChanged() {
    var usable = store.usableRoots()
    var errors = {}
    for (var i = 0; i < usable.length; i++) {
      var root = usable[i].root
      if (Runs.hasKey(store.projectErrors, root)) errors[root] = store.projectErrors[root]
    }
    var byProject = store.taggedByProject(store.runsByProject, usable)
    store.runsByProject = byProject
    store.projectErrors = errors
    store.runs = store.mergedRuns(byProject, usable).runs
    store.refresh()
  }
```

(h) Replace the whole doc comment above `applyProjects` — from `  // A list reply's entries, {root, ok, runs | error}, matched to the usable` through the line just above `  function applyProjects(entries, exitCode, launched) {` — with:

```qml
  // A list reply's entries, {root, ok, runs | error}, matched to the usable
  // roots by exact root: the first entry of a root counts, any other entry is
  // ignored. No matched entry at all is a reply with no usable result --
  // unless none of the roots it was launched for (`launched`) is usable any
  // more, when it changes nothing; neither emits snapshotReplied. Every
  // matched entry AmMissing: the runs, runsByProject, projectErrors and the
  // coverage are emptied and amStatus is "missing". Otherwise an ok entry
  // replaces its root's runs and clears its error (entries that are not
  // objects are skipped); a failed one keeps its root's runs ([] when it had
  // none) and records Runs.errorText of its error; a usable root with no
  // entry keeps both. `runs` is merged again, and asOfSeq is 0 and appliedSeq
  // {id: 0} for every run in it. With an entry ok, everything after a good
  // snapshot follows, and while active a running watch whose roots are no
  // longer the usable "/" roots is started again. With none, amStatus is
  // "error" with the first failed entry's sentence, and `stale` stays as it
  // is. Last, once the state is applied, each root with a matched entry gets
  // snapshotReplied in registry order (emitReplied): "missing" for each in an
  // AmMissing reply, else "ok" for an ok entry, with the runs the merged list
  // attributes to it (ownedRuns), and "failed" for any other, with [].
```

(i) Inside `applyProjects`, delete these three lines (the AmMissing disarm):

```qml
      // Every root is disarmed: comparing its next good entry against []
      // would alert every escalated run again.
      store.armedRoots = {}
```

delete these two lines (the alerts computation):

```qml
    // Compared before the runs are replaced; raised below only while open.
    var alerts = store.active ? store.alertsOf(prev, byProject, merged.owner, okRoots, usable) : []
```

and delete these four lines (the raise-and-arm block, at the end of `if (store.active) { ... }`):

```qml
      store.raiseAlerts(alerts)
      var armed = Runs.copyMap(store.armedRoots)
      for (var ok in okRoots) armed[ok] = true
      store.armedRoots = armed
```

(j) Delete `alertsOf` with its comment — this whole block and the blank line after it:

```qml
  // One list reply's alerts, in registry order, then each root's order: for
  // every armed root in okRoots, Runs.newAlerts of its runs before the reply
  // (prev; [] when it had none) against the runs of byProject it owns in the
  // merged list (owner), each with `project`, the name Runs.withProject gives
  // that root. A run id is raised at most once.
  function alertsOf(prev, byProject, owner, okRoots, usable) {
    var out = []
    var raised = {}
    for (var i = 0; i < usable.length; i++) {
      var root = usable[i].root
      if (!Runs.hasKey(okRoots, root) || !Runs.hasKey(store.armedRoots, root)) continue
      var mine = byProject[root].filter(function(run) {
        return run !== null && typeof run === "object" && Runs.hasKey(owner, run.id) && owner[run.id] === root
      })
      var name = Runs.withProject({}, root, usable[i].name).project.name
      var found = Runs.newAlerts(Runs.hasKey(prev, root) ? prev[root] : [], mine)
      for (var j = 0; j < found.length; j++) {
        if (Runs.hasKey(raised, found[j].id)) continue
        raised[found[j].id] = true
        found[j].project = name
        out.push(found[j])
      }
    }
    return out
  }
```

(k) Find the alerts section, from its header through `dropNotifyRunner`:

```qml
  // ---- alerts (S2 4.4)

  // One toast per alert, newest last: a run's older toast goes first, then the
  // oldest beyond three. With the setting on, each alert also notifies.
  // Called from applySnapshot only while active.
  function raiseAlerts(alerts) {
    var list = Array.isArray(alerts) ? alerts : []
    for (var i = 0; i < list.length; i++) {
      var a = list[i]
      toastState.nextKey += 1
      var next = store.toasts.filter(function(t) { return t.id !== a.id })
      next.push({ key: toastState.nextKey, id: a.id, title: a.title, state: a.state, reason: a.reason,
                  project: typeof a.project === "string" ? a.project : "", expiresMs: Date.now() + store.toastMs })
      while (next.length > 3) next.shift()
      store.toasts = next
      if (store.notifyOnEscalation) store.notify(a)
    }
  }

  // Drops every toast whose time is up at nowMs (the timer passes Date.now()).
  function expireToasts(nowMs) {
    var next = store.toasts.filter(function(t) { return t.expiresMs > nowMs })
    if (next.length !== store.toasts.length) store.toasts = next
  }

  // The toast with this key goes; an unknown key changes nothing.
  function dismissToast(key) {
    var next = store.toasts.filter(function(t) { return t.key !== key })
    if (next.length !== store.toasts.length) store.toasts = next
  }

  function dismissAllToasts() {
    if (store.toasts.length > 0) store.toasts = []
  }

  // One notify.py launch for an alert, on a runner of its own so two never
  // stop each other. The reply is not read: a failed or skipped notification
  // changes nothing here.
  function notify(alert) {
    var runner = notifyC.createObject(store)
    notifyState.runners = notifyState.runners.concat([runner])
    runner.run([String(alert.title), String(alert.reason)])
  }

  function dropNotifyRunner(runner) {
    notifyState.runners = notifyState.runners.filter(function(r) { return r !== runner })
    runner.destroy()
  }

```

and replace it with:

```qml
  // ---- the notify switch (S2 4.4)

```

(l) Delete the toast timer (and the blank line after it):

```qml
  // Only while the panel is open and a toast shows: no timer while idle.
  Timer {
    id: toastTimer
    objectName: "toastTimer"
    interval: 250
    repeat: true
    running: store.active && store.toasts.length > 0
    onTriggered: store.expireToasts(Date.now())
  }
```

(m) Delete the toast and notify bookkeeping (and the blank line after each):

```qml
  // The toast keys only grow, so a stale Dismiss never removes a newer toast.
  QtObject {
    id: toastState
    property int nextKey: 0
  }

  // The notify.py runners in flight; kept apart so consumers cannot write it.
  QtObject {
    id: notifyState
    property var runners: []
  }
```

(n) Delete the notify runner component (and the blank line after it):

```qml
  // One HelperRunner per notification. Guard "": a project switch does not
  // stop a notification already launched. It goes when its process exits.
  Component {
    id: notifyC

    HelperRunner {
      id: nr
      script: store.backendDir + "runs/notify.py"
      guard: ""
      onFinished: store.dropNotifyRunner(nr)
    }
  }
```

Check nothing alerts-shaped is left outside the shims:

Run: `grep -n "toastState\|notifyState\|notifyC\|alertsOf\|dropNotifyRunner\|store.armedRoots = \|store.toasts = " core/stores/RunStore.qml`
Expected: no output.

- [ ] **Step 7: Compose and route in App**

In `core/stores/App.qml`, find:

```qml
  // The run store never imports the project or board store: App hands it the
  // registry's roots and names in registry order, the selected project's root
  // path (never the project object) and the panel-open flag that starts and
  // stops its watch.
  readonly property RunStore runs: RunStore {
    backendDir: app.backendDir
    projectRoots: app.projects.projects.map(function(p) { return { root: p.root_path, name: p.name } })
    project: app.projects.selectedProject ? app.projects.selectedProject.root_path : ""
    active: app.panelOpen
    searchQuery: app.nav.searchQuery
    onRunFilterToggled: {
      app.nav.cursorIndex = 0
      app.nav.scrollOnCursor = false
    }
    onProjectFilterToggled: {
      app.nav.cursorIndex = 0
      app.nav.scrollOnCursor = false
    }
  }
```

and replace it with:

```qml
  // The run store never imports the project or board store: App hands it the
  // registry's roots and names in registry order, the selected project's root
  // path (never the project object), the panel-open flag that starts and
  // stops its watch, and the alerts store its shims read (alertsStore).
  readonly property RunStore runs: RunStore {
    backendDir: app.backendDir
    projectRoots: app.projects.projects.map(function(p) { return { root: p.root_path, name: p.name } })
    project: app.projects.selectedProject ? app.projects.selectedProject.root_path : ""
    active: app.panelOpen
    searchQuery: app.nav.searchQuery
    alertsStore: app.runAlerts
    onRunFilterToggled: {
      app.nav.cursorIndex = 0
      app.nav.scrollOnCursor = false
    }
    onProjectFilterToggled: {
      app.nav.cursorIndex = 0
      app.nav.scrollOnCursor = false
    }
    onSnapshotReplied: function(root, outcome, previousRuns, runs) {
      app.runAlerts.snapshotReplied(root, outcome, previousRuns, runs)
    }
  }

  // The run alerts never import the run store: App hands them the backend
  // directory, the panel-open flag, the notify switch and the registry, and
  // routes every project's snapshot reply (runs.snapshotReplied) here.
  readonly property RunAlertsStore runAlerts: RunAlertsStore {
    backendDir: app.backendDir
    active: app.panelOpen
    notifyOnEscalation: app.runs.notifyOnEscalation
    projectRoots: app.runs.projectRoots
  }
```

- [ ] **Step 8: Run the three store test files**

Run: `bash tests/run.sh core/stores/tst_run`
Expected: PASS — `tst_run_alerts_store.qml` (12 + 24 = 36 tests) and `tst_run_store.qml` (290 tests) each show `0 failed`, no `TypeError` line.

Run: `bash tests/run.sh tst_app_runs`
Expected: PASS — `0 failed`, including A1-A4 and every earlier test unchanged.

- [ ] **Step 9: Run the whole suite**

Run: `bash tests/run.sh`
Expected: PASS — pytest (including `tests/architecture`) green, every QML file `0 failed`, no `TypeError`/`ReferenceError` line, exit status 0. `tests/ui/**` passes with no edit.

Run: `git status --short tests/ui ui`
Expected: no output (nothing under `ui/` or `tests/ui/` changed).

- [ ] **Step 10: Commit**

```bash
git add core/stores/RunStore.qml core/stores/App.qml tests/core/stores/tst_run_store.qml tests/core/stores/tst_run_alerts_store.qml tests/core/stores/tst_app_runs.qml
git commit -m "refactor(runs): alerts move to RunAlertsStore, RunStore keeps shims, App routes snapshotReplied"
```

---

### Task 4: `docs/architecture.md`

**Files:**
- Modify: `docs/architecture.md` (the `RunStore.qml` bullet, lines 83-92; a new `RunAlertsStore.qml` bullet after it; the refresh-model paragraph, line 171)

**Interfaces:**
- Consumes: the contract of Tasks 1-3 (names only).
- Produces: nothing code reads.

- [ ] **Step 1: Apply the edit**

Save this script as `/tmp/arch_docs.py` (outside the repository; do not commit it) and run it from the worktree root with `python3 /tmp/arch_docs.py`. Every replaced sentence is asserted to occur exactly once, so a drifted file fails loudly instead of being half-edited:

```python
# docs/architecture.md: the alerts text moves from the RunStore bullet to a new RunAlertsStore bullet.
PATH = "docs/architecture.md"
text = open(PATH).read()

ALERTS_OLD = (
    "Alerts (S2 4.4): while `active`, every good list snapshot compares each armed root's ok entry with that root's runs before it through `Runs.newAlerts` (only the runs the root owns in the merged `runs`, so a run listed under two roots alerts once, under the first), and each run of any registered project that newly turned escalated or dead gets a toast in `toasts` (`{key, id, title, state, reason, project, expiresMs}`, `project` the project's name, oldest first, at most 3, one per run; `key` only grows, so a stale Dismiss never removes a newer toast). "
    "`armedRoots` (`{root: true}`, replaced, never changed in place) holds the roots whose runs may be compared against, and `alertsArmed` says some root is: a root's first ok entry after an opening, a start-over, an `AmMissing` spell (every matched entry `AmMissing`, which disarms every root), the project's first registration or its return to the registry only arms it, so reopening the panel never replays history and a project registered later is armed by the first snapshot that lists it; a failed entry leaves its root's arming alone, a root that leaves the registry loses it, a project switch neither disarms nor empties `toasts`, and a snapshot that lands after the panel closed raises nothing and arms nothing. "
    "A toast lasts `toastMs` (8000); `toastTimer` (250 ms, only while the panel is open and a toast shows) drops expired ones through `expireToasts(nowMs)`, and `dismissToast(key)` / `dismissAllToasts()` remove them. "
    "Closing the panel empties `toasts`. "
)
ALERTS_NEW = (
    "Alerts (S2 4.4) are `RunAlertsStore`'s. `RunStore` reports each project's applied list snapshot reply as `snapshotReplied(root, outcome, previousRuns, runs)`, which App routes there, and keeps `armedRoots`, `alertsArmed`, `toasts`, `toastMs`, `toastTimer`, `notifyRunners`, `raiseAlerts`, `expireToasts`, `dismissToast`, `dismissAllToasts` and `notify` as read-only shims through `alertsStore` (the handle App sets; without one they are empty and do nothing) until the last story of the split removes them. "
)

REPLACEMENTS = [
    ("Opening the panel (`startLive`) clears `armedRoots`, reads the notify switch, starts the stale clock and refreshes every root.",
     "Opening the panel (`startLive`) reads the notify switch, starts the stale clock and refreshes every root."),
    ("clears `stale`, `watchWarning`, `armedRoots` and `toasts`, and closes the dispatch unless a start is in flight;",
     "clears `stale` and `watchWarning`, and closes the dispatch unless a start is in flight;"),
    ("drops the runs, errors and arming of every root that left, merges `runs` again in the new order with the new names, raises no alert, then refreshes every root.",
     "drops the runs and errors of every root that left, merges `runs` again in the new order with the new names, emits no `snapshotReplied`, then refreshes every root."),
    ("forgets `watchCursor`, `nudges`, `runs`, `runsByProject` and `armedRoots`, and refreshes every root.",
     "forgets `watchCursor`, `nudges`, `runs` and `runsByProject`, emits `snapshotReplied(root, \"missing\", previousRuns, [])` for every usable root in registry order, and refreshes every root."),
    ("`appliedSeq` are emptied and every root is disarmed, so no run marks show)",
     "`appliedSeq` are emptied, so no run marks show)"),
    ("Only a reply with an ok entry settles controls and refreshes logs and, while `active`, starts a watch, restarts the stale clock and arms roots.",
     "Only a reply with an ok entry settles controls and refreshes logs and, while `active`, starts a watch and restarts the stale clock. "
     "Once a reply's state is applied, each usable root with a matched entry gets `snapshotReplied(root, outcome, previousRuns, runs)`, in registry order whatever the reply's order and whether or not `active`: `outcome` is `missing` for each root of an `AmMissing` reply, else `ok` (with `runs` the root's runs that the merged `runs` lists under it) or `failed` (with `runs` `[]`); `previousRuns` is the root's runs before the reply (`[]` when it had none). A reply with no matched entry, an `ok: false` envelope and unreadable output emit nothing."),
    (ALERTS_OLD, ALERTS_NEW),
    ("With it on, every raised alert also runs `notify.py TITLE REASON` on a `HelperRunner` of its own (`notifyRunners`; dropped when it exits, its reply unread, not stopped by a project switch).",
     "`RunAlertsStore` reads it through App."),
    ("the fallback poll, the toast expiry (`toastTimer`, only while a toast shows) and the dispatch debounce (`dispatchDebounceTimer`, only while a form change waits to be checked; closing the panel closes the dispatch unless a start is in flight) run only while the panel is open (`active`);",
     "the fallback poll and the dispatch debounce (`dispatchDebounceTimer`, only while a form change waits to be checked; closing the panel closes the dispatch unless a start is in flight), and `RunAlertsStore`'s toast expiry (`toastTimer`, only while a toast shows), run only while the panel is open (`active`);"),
]

BULLET_AFTER = "put the dispatch back to `idle`.\n"
BULLET = (
    "- `RunAlertsStore.qml` the run toasts, their arming and the desktop notification, for every registered project. It never reaches for another store: `App` composes it as `app.runAlerts` and hands it `backendDir`, `active` (App's `panelOpen`), `notifyOnEscalation` (`app.runs.notifyOnEscalation`) and `projectRoots` (`app.runs.projectRoots`), and routes every `app.runs.snapshotReplied(root, outcome, previousRuns, runs)` to its `snapshotReplied`, its one entry point for snapshot results. "
    "An `ok` reply while `active` for an armed root raises `Runs.newAlerts(previousRuns, runs)` (a non-array `previousRuns` counts as `[]`; a non-array `runs` raises nothing), in the order of `runs`, each with `project` the `project.name` of its run (`\"\"` when it has none), and then arms the root; for a root not armed it only arms it, so a root's first ok reply after an opening, a `missing` reply or its return to the registry never replays history. `missing` disarms every root and keeps the toasts; `failed`, any other outcome and an `ok` reply while closed change nothing, so a snapshot that lands after the panel closed raises nothing and arms nothing. "
    "`armedRoots` (`{root: true}`, replaced, never changed in place) holds the roots whose runs may be compared against, and `alertsArmed` says some root is. Opening the panel disarms every root; closing it disarms every root and empties `toasts`; a `projectRoots` change drops the arming of every root no entry names (`armedRoots` is replaced only when a root went) and touches no toast; a project switch changes nothing here. "
    "`raiseAlerts(alerts)` gives each alert a toast in `toasts` (`{key, id, title, state, reason, project, expiresMs}`, oldest first, at most 3, one per run: a run's older toast goes first, then the oldest beyond three; `key` only grows, so a stale Dismiss never removes a newer toast) whatever `active` is. A toast lasts `toastMs` (8000); `toastTimer` (250 ms, only while `active` and a toast shows) drops expired ones through `expireToasts(nowMs)`, and `dismissToast(key)` / `dismissAllToasts()` remove them. "
    "With `notifyOnEscalation` on, every raised alert also runs `notify.py TITLE REASON` on a `HelperRunner` of its own (`notifyRunners`; guard `\"\"`, dropped when it exits, its reply unread, not stopped by a project switch).\n"
)

for old, new in REPLACEMENTS:
    assert text.count(old) == 1, old[:80]
    text = text.replace(old, new)
assert text.count(BULLET_AFTER) == 1
text = text.replace(BULLET_AFTER, BULLET_AFTER + BULLET)
open(PATH, "w").write(text)
```

- [ ] **Step 2: Verify the docs match the code**

Run: `grep -n "RunAlertsStore" docs/architecture.md | cut -c1-80`
Expected: the `RunStore.qml` bullet (the "Alerts (S2 4.4) are `RunAlertsStore`'s" sentence and "`RunAlertsStore` reads it through App"), the new `- \`RunAlertsStore.qml\`` bullet right after the `RunStore.qml` bullet, and the refresh-model line.

Run: `grep -n "clears \`armedRoots\`\|raises no alert\|and arms roots" docs/architecture.md`
Expected: no output.

Run: `bash tests/run.sh`
Expected: PASS — exit status 0 (docs change nothing the tests read; this is the card's final gate).

- [ ] **Step 3: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): RunAlertsStore and RunStore.snapshotReplied"
```
<!-- task-pipeline: validated -->
