# 3.2 RunControlStore: the notify switch — design

Card: `e546c85f` ("RunControlStore: run and global settings"), a subtask of story `1159cc4e`
"Extract RunControlStore". Its sibling 3.1 (`b15b3cd3`) is done. Parent design:
`docs/superpowers/specs/2026-10-05-split-runstore-design.md`, cited below as "P l.N". Line numbers
into `core/stores/RunStore.qml` (1619 lines), `core/stores/RunControlStore.qml` (349 lines),
`core/stores/App.qml` and the test files are from the files at the start of this card (commit
`d487cb9`). Appendix A's line numbers (P l.168) come from an older 2038-line file and are not
used here.

## Purpose

This is a pure refactor. The "Notify on escalation" switch moves out of `RunStore` and into
`RunControlStore` (`app.runControl`). That covers its three properties, its setter, its global
load and save through `viewer-state.py get-global-settings` / `set-global-settings`, their
replies, the failure flash, and the opening's load. App then binds `runAlerts.notifyOnEscalation`
to `app.runControl.notifyOnEscalation` (P l.55, l.78, A.3 P l.438). `RunStore` keeps stateless
shims under the old names (P l.122-127), so `ui/` and `tests/ui/` do not change.

Nothing a user can see or a helper can receive changes. The same argv launches at the same
moments, the same values land, and the same sentence flashes.

## Scope: what this card moves and what it leaves

The card names the notify switch: "`notifyOnEscalation`, `notifySaved`, `notifyTouched`,
`setNotifyOnEscalation`, the load/save runners and replies, S6's get-global-settings /
set-global-settings and their failure flash". Appendix A also maps the per-project run settings
to `RunControlStore`: `runSettings` (P l.234), `runSettingsRunner` (P l.268, 384) and
`applyRunSettings` (P l.359). Those are **not** moved here:

- `runSettings` is read and written by the dispatch code that is still in `RunStore`
  (`openDispatch` 1160, `dispatchStart` 1340, `dispatchStartReplied` 1386-1393). Moving it now
  would need a writable cross-store path that P l.79 replaces with signals.
- Sibling card 4.2 ("Dispatch run settings through RunControlStore") owns that move. It turns
  `runSettings` into a per-root map behind `loadRunSettings(root)` / `saveRunSettings(root,
  patch)`, routed from `RunDispatchStore` by App.

So `runSettings`, `runSettingsRunner`, `applyRunSettings`, `projectSwitched` and
`onProjectChanged` stay in `RunStore`, unchanged in body. That includes the
`runSettingsRunner` guard handling (RunStore.qml 671-680).

Out of scope, named explicitly:

- the run-settings members above (card 4.2);
- `RunDispatchStore`, `noticeRequested` and the dispatch's `store.flash("Dispatch settings could
  not be saved")` (1425), which keeps going through the `flash` shim (cards 4.1 and 4.2);
- moving any `ui/` or `tests/ui/` caller to `app.runControl`, and deleting shims (cards 5.1 and
  5.2);
- rewriting `docs/architecture.md` into one paragraph per store (card 5.3). This card only edits
  the sentences that would otherwise become false (see "Docs").

## Inherited constraints

- Every member lands in exactly one store. Nothing is duplicated, and nothing is dropped unless
  no code or test reads it (P l.61-67).
- No duplicated helpers. The replies are read with `Results.parseEnvelope` from
  `core/domain/results.js`, which `RunControlStore` already imports (P l.68-71).
- Inputs come from App. `RunControlStore` keeps exactly its inputs `backendDir`, `project`,
  `active` and `runs`. The switch needs no new input (P l.77). `RunAlertsStore`'s
  `notifyOnEscalation` is bound to `app.runControl.notifyOnEscalation` (P l.78, A.3 P l.438).
- The notify save failure's flash stays inside `RunControlStore`, because the flash already
  lives there (P l.89-91). It is a direct `control.flash(...)` call, not a signal.
- Lifecycle stays per store. `startLive`'s two switch lines become `RunControlStore`'s own
  `active` reaction (P l.92-97, A.3 P l.434). A project switch never changes the switch.
- A store never imports or names a sibling. The one exception is the shim handle
  `RunStore.controlStore`, which 3.1 already added (P l.46-50).
- Shims (P l.122-127):
  - A property shim is a read-only binding through the handle, and it notifies like the
    original.
  - A function shim is a one-line forward that returns the target's result.
  - Shims hold no state and no logic.
  - The only comment above them is the existing `// Moved to RunControlStore; removed by the
    last story`.
- Tests move with their members. Only construction and the wiring of inputs change, never an
  expectation. A test that crosses two concerns is pinned at App level (P l.98-104, l.160-162).
- `tests/architecture` stays green (P l.105-106).
- No behaviour change, no renamed public member, no new helper argv, no change to which process
  starts when, and no UI change (P l.146-150).
- From the card:
  - `bash tests/run.sh` is green;
  - TDD: tests first;
  - docstrings and comments state the contract only, with no narrative;
  - `tests/ui` passes untouched.

## The members that move

Every row leaves `RunStore.qml` and lands in `RunControlStore.qml` with its body unchanged,
except that `store.` becomes `control.` (the new store's root id).

| member | RunStore.qml today | Appendix A row |
|---|---|---|
| switch comment block | 170-173 | into the store's contract comment |
| `notifyOnEscalation` (`property bool`, `false`) | 174 | P l.231 |
| `notifySaved` (`property bool`, `false`) | 175 | P l.232 |
| `notifyTouched` (`property bool`, `false`) | 176 | P l.233 |
| `settingsLoadRunner` alias | 230 | P l.266 |
| `settingsSaveRunner` alias | 231 | P l.267 |
| `startLive`'s two switch lines (`if (!settingsSaveRunner.busy) store.notifyTouched = false`, `settingsLoadRunner.run(["get-global-settings"])`) | 379-380 | A.3 P l.434 |
| `// ---- the notify switch (S2 4.4)` section header | 1057 | kept as a section header |
| `setNotifyOnEscalation(on)` | 1059-1068 | P l.357 |
| `applyGlobalSettings(stdout, exitCode)` | 1070-1079 | P l.358 |
| `notifySaveReplied(stdout, exitCode, sent)` | 1088-1098 | P l.360; `store.flash(...)` → `control.flash(...)` |
| `settingsLoadRunner` HelperRunner | 1455-1462 | P l.383 |
| `settingsSaveRunner` HelperRunner (`property bool sent`) | 1475-1483 | P l.385 |

What stays in `RunStore`:

- `startLive` keeps `watchTried = false`, `restartStale()` and `refresh()`. Its comment drops
  "and read the notify switch (get-global-settings; notifyTouched is cleared first unless a
  save is in flight)".
- The `runSettings` comment (177-180) keeps "its notifyOnEscalation is never read". That
  sentence is about the run settings object.
- The `projectSwitched` comment (668-670) keeps listing "the notify switch" among what a switch
  leaves alone. That stays true, because the switch is no longer touched from `RunStore` at all.
  The planner may drop the phrase instead, but must not claim `projectSwitched` resets it.

## Behaviour: `RunControlStore`

### Unchanged from RunStore

Everything below behaves exactly as `RunStore` does today:

- **The defaults.** `notifyOnEscalation`, `notifySaved` and `notifyTouched` are all `false`
  until read.
- **Opening.** When `active` turns true, the store clears `notifyTouched` unless
  `settingsSaveRunner.busy`, then runs `settingsLoadRunner.run(["get-global-settings"])`
  (argv `python3 <backendDir>projects/viewer-state.py get-global-settings`, three elements,
  `launchGuard` `""`). Each opening loads exactly once. Closing the panel (`active` turning
  false) launches nothing and changes nothing on the switch. A store created already active
  loads nothing until `active` next turns true, which is today's `onActiveChanged` semantics.
- **The load reply** (`applyGlobalSettings`):
  - It is ignored while `notifyTouched` is true.
  - Otherwise `notifyOnEscalation` and `notifySaved` become `true` only when the reply parses
    and its `notifyOnEscalation === true`. Anything else gives `false`: an unreadable reply,
    `"yes"`, a missing key, or `{}`.
  - The runner has no guard and the latest launch wins. A reply that lands after the panel
    closed is still applied. An older opening's reply, superseded by a newer launch, is
    dropped by `HelperRunner`.
- **`setNotifyOnEscalation(on)`** works with or without a project and with the panel open or
  closed, and returns `true`. It does these steps:
  1. sets `notifyOnEscalation = !!on` and `notifyTouched = true`;
  2. sets `settingsSaveRunner.sent = !!on`;
  3. runs `set-global-settings` with `JSON.stringify({ notifyOnEscalation: !!on })` (four argv
     elements, `launchGuard` `""`, latest wins).
- **The save reply** (`notifySaveReplied`):
  - `{"ok": true}` sets `notifySaved = sent`.
  - Anything else puts `notifyOnEscalation` back to `notifySaved` and calls
    `control.flash("Notify on escalation could not be saved")`. That covers `ok: false`, an
    unreadable reply and garbage. The flash sets this store's `flashText` and restarts its
    `flashTimer`.
- **A project change** (`project` input) changes nothing on the switch and launches nothing on
  either settings runner.

### Contract comment

The file's header comment (RunControlStore.qml 7-19) gains one sentence, stating only the
contract. For example: "The 'Notify on escalation' switch is viewer-wide: each opening reads it
(get-global-settings) and setNotifyOnEscalation writes it (set-global-settings); a failed save
puts it back and flashes." The sentence "A project switch changes nothing here." stays true. The
moved members keep their comments from `RunStore` (170-173, 1059-1060, 1070-1072, 1088-1089,
1455-1457, 1475-1477), with `startLive` replaced by "each opening" where it is named.

## Behaviour: `RunStore`

### Removed

All the rows in the table above. `startLive` no longer touches the switch or the settings load
runner. `RunStore` launches no `get-global-settings` and no `set-global-settings` of its own.

### Shims

These are added under the existing `// Moved to RunControlStore; removed by the last story`
block (RunStore.qml 120-154). They are all read-only, and every one checks
`store.controlStore` first, so a store with no handle never throws (`tests/run.sh` fails a file
whose output contains `TypeError`).

| name | shim | without a handle |
|---|---|---|
| `notifyOnEscalation` | `readonly property bool` through the handle | `false` |
| `notifySaved` | `readonly property bool` | `false` |
| `notifyTouched` | `readonly property bool` | `false` |
| `settingsLoadRunner` | `readonly property var` (the HelperRunner) | `null` |
| `settingsSaveRunner` | `readonly property var` (the HelperRunner) | `null` |
| `setNotifyOnEscalation(on)` | a one-line forward returning the target's result | returns `undefined`, does nothing |

`applyGlobalSettings` and `notifySaveReplied` get **no shim**. No code or test outside
`RunStore.qml` and the moved tests calls them. Before deleting, the planner greps `ui/`,
`tests/ui/`, `tst_app_runs.qml`, `tst_run_alerts_store.qml` and the tests that stay in
`tst_run_store.qml`. Any hit gets a forward shim instead.

**Why every shim can be read-only.** Unlike 3.1's `cancelText` / `cancelRunId`, nothing in
`ui/` or `tests/ui/` writes these names on a real `RunStore`:

- `ui/screens/RunsScreen.qml:322-323` reads `notifyOnEscalation` and calls
  `setNotifyOnEscalation`.
- `tests/ui/screens/tst_runs_screen.qml:998-1000` writes `notifyOnEscalation` on its own stub
  `runs` object, not on `RunStore`.
- The `tests/ui` flows only read the members or call `settingsLoadRunner.cancel()`:
  - `tst_runs_flow.qml:54, 691-693, 701-702, 824-828, 860, 908`;
  - `tst_dispatch_flow.qml:69`;
  - `tst_board_flow.qml:151`;
  - `tst_runs_real_data.qml:49`.

  These run against App, which always sets the handle.

The only writers on a real `RunStore` are in `tests/core/stores`. Their input wiring changes
(see "Test wiring changes").

## Behaviour: `App`

`app.runAlerts`'s binding `notifyOnEscalation: app.runs.notifyOnEscalation` (App.qml 151)
becomes `notifyOnEscalation: app.runControl.notifyOnEscalation`.

Two comments change to match:

- The `runAlerts` comment (App.qml 145-147) names the switch's new owner.
- The `runControl` comment (App.qml 131-134) is otherwise unchanged. No new input and no new
  route are needed: `active: app.panelOpen` already drives the opening's load.

## Equivalence argument (for the reviewer)

- **Same launches.** Today an opening runs `startLive`: clear `notifyTouched` (unless busy),
  load, `restartStale`, `refresh`. Now `RunStore.startLive` does `restartStale` and `refresh`,
  and `RunControlStore`'s own `active` reaction does the clear and the load. Both stores bind
  `active` to `app.panelOpen`, so one opening still launches exactly one `get-global-settings`
  and one snapshot.
  - The relative order of those two launches may change. They run on separate runners and
    neither reads the other's state, so no observable value depends on it.
  - No test asserts a cross-runner launch order. The planner confirms this by grepping for a
    shared launch log in `tests/stubs`; there is none at this commit.
- **The busy check** reads the same `settingsSaveRunner`. It is now the control store's, which is
  also the one `setNotifyOnEscalation` launches on.
- **The flash** lands on the same `flashText` / `flashTimer`. Today `store.flash` already
  forwards to the control store through 3.1's shim.
- **The alerts input** follows the same value. The `RunStore` shim and `app.runControl` read
  one property, so binding `runAlerts` straight to the owner gives identical values and change
  notifications.

## Tests

TDD: each new or changed test is written first and fails before its code exists. Everything runs
through `bash tests/run.sh` (qmltestrunner, offscreen, stubs from `tests/stubs`). A single file
runs with `bash tests/run.sh tst_run_control_store`. The tiers:

- **store unit**: `tests/core/stores/tst_run_control_store.qml`. It pins the switch's behaviour on
  the store that owns it. It uses the bare-store builder (`makeControl`) and the "through a
  RunStore wired the way App wires app.runControl" harness (`make`, `makeWithProject`,
  `controlOf`), both already there.
- **RunStore unit**: `tests/core/stores/tst_run_store.qml`. It pins the shims, and that the
  tests mixing run settings with the switch still pass through them.
- **alerts store unit**: `tests/core/stores/tst_run_alerts_store.qml`. Only its input wiring
  changes.
- **App wiring**: `tests/core/stores/tst_app_runs.qml`. It pins the new App binding and the
  card's "switch on → an alert launches notify.py" route.
- **UI and architecture**: `tests/ui/**` (untouched) and `pytest tests` (architecture,
  contract, install).

### Moved tests (store unit tier: whole, every expectation kept)

These five leave `tst_run_store.qml` and land in `tst_run_control_store.qml` under the same
names, in a new `// ---- the notify switch (S2 4.4)` section. They keep their numbered comments
(`// 8 and Review Focus 5`, `// 13`, `// 10`, `// 11`, `// 14`).

| test | tst_run_store.qml today |
|---|---|
| `test_the_global_switch_loads_on_each_opening_with_no_project` | 2798-2850 |
| `test_the_switch_saves_globally_and_a_failed_save_puts_it_back` | 2884-2915 |
| `test_a_save_reply_survives_a_project_switch` | 2917-2936 |
| `test_a_save_in_flight_survives_a_reopening` | 2938-2957 |
| `test_a_load_reply_after_the_user_toggled_is_ignored` | 2959-2969 |

Only one thing changes in the moved bodies: each read, write or call of a moved member, or of
3.1's `flash` / `flashText`, goes to `controlOf(x)` instead of the RunStore `x`. The moved
members are `notifyOnEscalation`, `notifySaved`, `notifyTouched`, `setNotifyOnEscalation`,
`settingsLoadRunner` and `settingsSaveRunner`. Construction stays (`make()`,
`makeWithProject(rootA)`), and so do `x.project = …` and `x.active = …` on the RunStore, which
reach the control store through the harness bindings. This keeps the opening and the project
switch going through the same wiring App uses.

The one non-moved read in these bodies is `store.notifyRunners.length` (2890), an alerts shim.
It stays on `store`. The control-store harness wires no alerts store, so the shim reads `[]` and
the expectation `0` holds unchanged.

`tst_run_control_store.qml` gains `property string viewerCmd:
"python3|/plugin/core/backend/projects/viewer-state.py|"`, copied from `tst_run_store.qml:2792`.
The `runSettings(notify)` helper (2794-2796) stays in `tst_run_store.qml`, because only the
tests that stay there use it. The file's header comment adds "the notify switch" to what it
covers.

### Tests that stay in `tst_run_store.qml`, unchanged

These two cross the run settings, which stay in `RunStore` until 4.2, and the switch. They pass
untouched through the shims, because `make()` wires a control store:

- `test_run_settings_load_per_project_and_never_set_the_switch` (2852-2882);
- `test_run_settings_kept_even_after_notify_touched` (2983-2996).

`test_settings_write_failure_flashes` (3745), which reads `notifyOnEscalation` and
`settingsSaveRunner` through the shims (3756-3757), also stays unchanged.

### New tests

**Store unit (`tst_run_control_store.qml`, bare store, section "the store alone"):**

- **C-N1 `test_a_bare_control_store_has_the_switch_off_and_untouched`**: `makeControl()` gives
  `notifyOnEscalation`, `notifySaved` and `notifyTouched` all `false`, and `settingsLoadRunner`
  and `settingsSaveRunner` exist with no `current`. Tier: store unit, because it pins the
  defaults on the owner with nothing bound.
- **C-N2 `test_the_stores_own_active_loads_the_switch_and_closing_launches_nothing`**:
  1. Build with `makeControl()` and set `c.active = true`. Exactly one `get-global-settings`
     launches.
  2. Set `c.active = false`. `settingsLoadRunner.seq` is unchanged.
  3. Set `c.project = "/x"`. Still no launch on either runner.
  4. Set `c.active = true` again. One more launch.

  Tier: store unit, because it proves the lifecycle is the store's own reaction (P l.92-97)
  without any `RunStore`.
- **C-N3 `test_a_failed_save_flashes_on_this_store`**: on a bare store,
  `setNotifyOnEscalation(true)` returns `true`, then an `ok: false` reply gives `flashText`
  `Notify on escalation could not be saved` and `flashTimer.running` true. Tier: store unit,
  because it pins that the flash stays inside the store (P l.89-91) with no RunStore present.

**RunStore unit (`tst_run_store.qml`, section "the run control shims"):**

- **R1, extended** (`test_without_a_control_store_the_shims_are_empty_and_inert`, 5090):
  - `notifyOnEscalation`, `notifySaved` and `notifyTouched` are `false`;
  - `settingsLoadRunner` and `settingsSaveRunner` are `null`;
  - `setNotifyOnEscalation(true)` returns `undefined` and leaves `notifyOnEscalation` `false`.

  Tier: RunStore unit, because the shims live there.
- **R2, extended** (`test_the_shims_follow_the_control_store_and_notify`, 5123):
  - `store.settingsLoadRunner === c.settingsLoadRunner` and
    `store.settingsSaveRunner === c.settingsSaveRunner`;
  - a `SignalSpy` on `store`'s `notifyOnEscalationChanged` counts 1 after
    `c.setNotifyOnEscalation(true)`;
  - `store.notifyOnEscalation` and `store.notifyTouched` are `true`;
  - after an ok save reply, `store.notifySaved` is `true`;
  - `store.setNotifyOnEscalation(false)` returns `true` and sets `c.notifyOnEscalation` to
    `false`, which shows that the forward reaches the control store.

  Tier: RunStore unit.
- **R4 `test_opening_the_run_store_alone_reads_no_switch`**:
  1. Build a RunStore with no control handle.
  2. Set `active = true`. No `TypeError` occurs.
  3. `settingsLoadRunner` is still `null`, and the snapshot still launches (`snapshotRunner`
     has a `current`).

  Tier: RunStore unit, because it pins that `startLive` no longer touches the switch.

**App wiring (`tst_app_runs.qml`):**

- **A1, changed** (`test_app_composes_run_alerts_wired_to_the_run_store`, 494-497): line 496
  `app.runs.notifyOnEscalation = true` becomes `app.runControl.setNotifyOnEscalation(true)`, and
  the message becomes "the switch follows run control's". The shim is now read-only, so the old
  write would throw a `TypeError`. This is a wiring change, and the expectation (`true`) is
  kept.
- **K-N1 `test_the_alerts_switch_is_run_controls`**:
  1. `makeBare()`;
  2. `verify` that `app.runAlerts.notifyOnEscalation` follows `app.runControl.notifyOnEscalation`
     through a load reply (`app.panelOpen = true`, reply `{"notifyOnEscalation": true}` on
     `app.runControl.settingsLoadRunner.current`);
  3. `app.runs.settingsLoadRunner === app.runControl.settingsLoadRunner`;
  4. `app.runs.notifyOnEscalation` is `true` too.

  Tier: App wiring, because only App binds the alerts input to the control store.
- **K-N2 `test_with_run_controls_switch_on_an_escalation_launches_notify`** (the card's pin):
  1. Build with `openApp([runningIn("r1")], [])`.
  2. Reply `{"notifyOnEscalation": true}` on `app.runControl.settingsLoadRunner.current`.
  3. A snapshot turns `r1` escalated. `app.runAlerts.notifyRunners.length` is 1, with argv
     `tc.notifyCmd + "m-r1|escalated"`.
  4. Then `app.runControl.setNotifyOnEscalation(false)` and an ok save reply. A second
     escalation (`r2`, added running first) launches no new notify runner.

  Tier: App wiring, because it crosses Control → Alerts (A.3 P l.438).
- **Unchanged and still passing through the shims**: the existing
  `test_opening_the_panel_through_app_reads_the_notify_switch` (427) and
  `test_an_escalation_through_app_notifies_only_with_the_switch_on` (453).

### Test wiring changes (input wiring only, no expectation changes)

- **`tst_run_store.qml` `wireAlerts` (83-90).** The alerts input is bound the way App now binds
  it: `a.notifyOnEscalation = Qt.binding(function() { var c = controlOf(store); return c ? c.notifyOnEscalation : false })`.
  `make()` already calls `wireControl` before `wireAlerts`. The comment above `wireAlerts` says
  "notifyOnEscalation bound to the paired control store's".
- **`tst_run_alerts_store.qml`.** Its RunStores have no control handle, so the read-only
  `notifyOnEscalation` shim reads `false`, and a write to it throws.
  - `wireAlerts` (309-321) drops the `a.notifyOnEscalation` binding (316), and its comment drops
    `notifyOnEscalation`.
  - The five writes `store.notifyOnEscalation = true` / `five.notifyOnEscalation = true` (701,
    763, 860, 890, 899) become `alerts(store).notifyOnEscalation = true` /
    `alerts(five).notifyOnEscalation = true`.

  That drives the alerts store's own input directly, the way its bare-store tests (114, 128,
  277, 287) already do. Every expectation is kept.

### Gate

`bash tests/run.sh` is green: pytest (including `tests/architecture`), then every qmltestrunner
file, with no `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign` or `is not a
function` in the output. `git diff --stat -- ui tests/ui` is empty.

## Docs

Only the sentences this card makes false are edited. The full rewrite is card 5.3.

- **`docs/architecture.md:84`.** "Opening the panel (`startLive`) reads the notify switch,
  starts the stale clock and refreshes every root." becomes "… starts the stale clock and
  refreshes every root."
- **`docs/architecture.md:91`.**
  - Add `notifyOnEscalation`, `notifySaved`, `notifyTouched`, `settingsLoadRunner`,
    `settingsSaveRunner` and `setNotifyOnEscalation` to the list of read-only shims through
    `controlStore`.
  - Move the "Notify on escalation" sentences (from "'Notify on escalation' is viewer-wide" to
    "`RunAlertsStore` reads it through App.") into the `RunControlStore` bullet (93), with
    "each opening" meaning the store's own `active` turning true.
- **`docs/architecture.md:93`.** Add the switch to what `RunControlStore` owns, and say that App
  binds `runAlerts.notifyOnEscalation` to it.
- **`docs/architecture.md:94`.** `notifyOnEscalation` (`app.runs.notifyOnEscalation`) becomes
  (`app.runControl.notifyOnEscalation`).
- **`docs/architecture.md:167`.** "it is RunStore's one viewer-wide switch" becomes "it is
  `RunControlStore`'s viewer-wide switch, read through the `app.runs` shims". `RunsScreen` still
  reads `app.runs.notifyOnEscalation`.

## Review Focus (for the planner)

These are the failure modes the moved tests do not obviously exercise. Each line names the
condition and the expected behaviour. The planner adds the test to the owning task.

1. **A RunStore with no control handle opens** (`tst_run_alerts_store.qml`, many
   `tst_run_store.qml` builders before wiring, R4). Expected: no `TypeError`, the snapshot
   launches, and the switch shims read `false` / `null`.
2. **A save in flight across a reopening.** The busy check must read the control store's own
   `settingsSaveRunner`, not a shim. Expected: `notifyTouched` survives the reopening, and the
   new load cannot undo the user's choice. The moved
   `test_a_save_in_flight_survives_a_reopening` pins this, so it must run against the control
   store through `controlOf`.
3. **A failed save while a cancel or refusal flash is showing.** Expected: the flash text is
   replaced and `flashTimer` restarts, because it is the same `flash()`. C-N3 pins the timer
   restart.
4. **The alerts store bound to a shim instead of the owner.** Expected: App and both test
   harnesses bind `runAlerts.notifyOnEscalation` to the control store. A binding to the shim
   gives the same values, so no test can tell the two apart. The plan's verification step
   greps `core/stores/App.qml` for `notifyOnEscalation: app.runControl.notifyOnEscalation` and
   for the absence of `notifyOnEscalation: app.runs.`.
5. **A leftover load in `startLive`.** If `startLive` keeps a load line, it can no longer
   compile against a removed id, or, rewritten through the shim, it launches a second
   `get-global-settings` per opening. Expected: one load per opening. The moved test 8 checks
   `seq + 1` per reopening on the control store's runner through a wired RunStore, which
   catches a second launch. R4 pins that a RunStore with no handle opens without touching any
   settings runner.

## Hand-off to the planner

Suggested tasks, each with its own test cycle:

1. **`RunControlStore` owns the switch.**
   - Files: `core/stores/RunControlStore.qml` and `tests/core/stores/tst_run_control_store.qml`.
   - Add the members in the table above, plus `onActiveChanged`. The store gains the switch
     while `RunStore` still has its own copy. That is temporary, and it is safe because nothing
     binds to the new members yet.
   - Tests first: C-N1, C-N2, C-N3, and the five moved tests copied in with the `controlOf`
     redirects. Do not delete them from `tst_run_store.qml` yet.
2. **`RunStore` shims, App rebinding and the wiring changes, in one commit.**
   - Files: `core/stores/RunStore.qml`, `core/stores/App.qml`,
     `tests/core/stores/tst_run_store.qml` (delete the five moved tests, R1/R2 extended, R4,
     `wireAlerts`), `tests/core/stores/tst_run_alerts_store.qml` (wiring), and
     `tests/core/stores/tst_app_runs.qml` (A1 changed, K-N1, K-N2).
   - Remove the RunStore members, add the shims, rebind App.
   - Grep for the no-shim functions before deleting them.
   - Run the full gate, and confirm that `ui/` and `tests/ui/` are untouched.
3. **Docs.** The `docs/architecture.md` edits above and the RunControlStore / RunStore header
   comments. Contract only, no narrative.

The member interfaces later tasks rely on, exactly:

- `RunControlStore.notifyOnEscalation: bool`, `notifySaved: bool`, `notifyTouched: bool`;
- `readonly property alias settingsLoadRunner`, `readonly property alias settingsSaveRunner`
  (HelperRunner, the latter with `property bool sent`);
- `function setNotifyOnEscalation(on) -> true`;
- `function applyGlobalSettings(stdout, exitCode)`;
- `function notifySaveReplied(stdout, exitCode, sent)`.
