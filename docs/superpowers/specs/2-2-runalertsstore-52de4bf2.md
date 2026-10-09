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
