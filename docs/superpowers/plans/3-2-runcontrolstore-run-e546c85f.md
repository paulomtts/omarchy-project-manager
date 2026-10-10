# 3.2 RunControlStore: the notify switch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the "Notify on escalation" switch (its three properties, setter, global load/save runners, replies and failure flash) from `RunStore` into `RunControlStore`, leave read-only shims on `RunStore`, and bind `app.runAlerts.notifyOnEscalation` to `app.runControl.notifyOnEscalation`, with no behaviour change.

**Architecture:** `RunControlStore` (`app.runControl`) gains the switch members verbatim (`store.` → `control.`) plus its own `onActiveChanged` that does the two lines `RunStore.startLive` used to do. `RunStore` loses those members and gains stateless shims through its existing `controlStore` handle. App rebinds the alerts input to the owner. Tests move with the members; only construction and input wiring change.

**Tech Stack:** QML (Qt 6, Quickshell), qmltestrunner with stubs in `tests/stubs`, pytest (architecture tests). Everything runs through `bash tests/run.sh [filter]`.

**Spec:** `docs/superpowers/specs/3-2-runcontrolstore-run-e546c85f.md` (reproduced verbatim right below, before the tasks).

## Global Constraints

- Pure refactor: no behaviour change, no renamed public member, no new helper argv, no change to which process starts when, no UI change.
- Every member lands in exactly one store; nothing duplicated, nothing dropped unless no code or test reads it. (Task 1 leaves a temporary duplicate that Task 2 removes in the same branch.)
- No duplicated helpers: replies are read with `Results.parseEnvelope` from `core/domain/results.js`.
- `RunControlStore` keeps exactly its inputs `backendDir`, `project`, `active` and `runs`; no new input.
- The notify save failure's flash is a direct `control.flash("Notify on escalation could not be saved")` call, not a signal.
- A store never imports or names a sibling; the only exception is the existing `RunStore.controlStore` handle.
- Shims: read-only bindings through the handle (notify like the original), one-line function forwards returning the target's result, no state, no logic, under the existing `// Moved to RunControlStore; removed by the last story` comment only.
- Every shim checks `store.controlStore` first (`tests/run.sh` fails a file whose output contains `TypeError`).
- `applyGlobalSettings` and `notifySaveReplied` get no shim.
- Tests move with their members; only construction and input wiring change, never an expectation.
- `ui/` and `tests/ui/` are untouched: `git diff --stat d487cb9 -- ui tests/ui` is empty.
- Docstrings and comments state the contract only, with no narrative.
- Gate: `bash tests/run.sh` green — pytest (incl. `tests/architecture`), then every qmltestrunner file, with no `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign` or `is not a function` in the output.
- Out of scope: `runSettings`, `runSettingsRunner`, `applyRunSettings`, `projectSwitched`, `onProjectChanged` (card 4.2); dispatch and `RunDispatchStore` (4.1/4.2); moving `ui/` callers or deleting shims (5.1/5.2); rewriting `docs/architecture.md` wholesale (5.3).

## Review Focus

1. **A RunStore with no control handle opens** (`tst_run_alerts_store.qml`, R1, the new R5): no `TypeError`, the snapshot still launches, the switch shims read `false` / `null` → R1 extended and R5 in Task 2.
2. **A save in flight across a reopening**: the busy check must read the control store's own `settingsSaveRunner`; `notifyTouched` survives and the new load cannot undo the user's choice → moved test 11 (`test_a_save_in_flight_survives_a_reopening`) in Task 1, run through `controlOf`.
3. **A failed save while another flash is showing**: the flash text is replaced and `flashTimer` runs, because it is the same `flash()` → C11 in Task 1 flashes first, then fails a save.
4. **The alerts store bound to a shim instead of the owner**: indistinguishable by value, so Task 2 Step 13 greps `core/stores/App.qml` for `notifyOnEscalation: app.runControl.notifyOnEscalation` and the absence of `notifyOnEscalation: app.runs.`; both test harnesses bind to the control store / alerts store directly.
5. **A leftover load in `startLive`**: would compile-fail or launch a second `get-global-settings` per opening → moved test 8 checks `seq + 1` per reopening on the control store's runner (Task 1), R5 pins a handle-less RunStore opens with no settings runner (Task 2), and Task 2 Step 13 greps `RunStore.qml` for `get-global-settings`.

---

## Spec (verbatim)

> # 3.2 RunControlStore: the notify switch — design
>
> Card: `e546c85f` ("RunControlStore: run and global settings"), a subtask of story `1159cc4e`
> "Extract RunControlStore". Its sibling 3.1 (`b15b3cd3`) is done. Parent design:
> `docs/superpowers/specs/2026-10-05-split-runstore-design.md`, cited below as "P l.N". Line numbers
> into `core/stores/RunStore.qml` (1619 lines), `core/stores/RunControlStore.qml` (349 lines),
> `core/stores/App.qml` and the test files are from the files at the start of this card (commit
> `d487cb9`). Appendix A's line numbers (P l.168) come from an older 2038-line file and are not
> used here.
>
> ## Purpose
>
> This is a pure refactor. The "Notify on escalation" switch moves out of `RunStore` and into
> `RunControlStore` (`app.runControl`). That covers its three properties, its setter, its global
> load and save through `viewer-state.py get-global-settings` / `set-global-settings`, their
> replies, the failure flash, and the opening's load. App then binds `runAlerts.notifyOnEscalation`
> to `app.runControl.notifyOnEscalation` (P l.55, l.78, A.3 P l.438). `RunStore` keeps stateless
> shims under the old names (P l.122-127), so `ui/` and `tests/ui/` do not change.
>
> Nothing a user can see or a helper can receive changes. The same argv launches at the same
> moments, the same values land, and the same sentence flashes.
>
> ## Scope: what this card moves and what it leaves
>
> The card names the notify switch: "`notifyOnEscalation`, `notifySaved`, `notifyTouched`,
> `setNotifyOnEscalation`, the load/save runners and replies, S6's get-global-settings /
> set-global-settings and their failure flash". Appendix A also maps the per-project run settings
> to `RunControlStore`: `runSettings` (P l.234), `runSettingsRunner` (P l.268, 384) and
> `applyRunSettings` (P l.359). Those are **not** moved here:
>
> - `runSettings` is read and written by the dispatch code that is still in `RunStore`
>   (`openDispatch` 1160, `dispatchStart` 1340, `dispatchStartReplied` 1386-1393). Moving it now
>   would need a writable cross-store path that P l.79 replaces with signals.
> - Sibling card 4.2 ("Dispatch run settings through RunControlStore") owns that move. It turns
>   `runSettings` into a per-root map behind `loadRunSettings(root)` / `saveRunSettings(root,
>   patch)`, routed from `RunDispatchStore` by App.
>
> So `runSettings`, `runSettingsRunner`, `applyRunSettings`, `projectSwitched` and
> `onProjectChanged` stay in `RunStore`, unchanged in body. That includes the
> `runSettingsRunner` guard handling (RunStore.qml 671-680).
>
> Out of scope, named explicitly:
>
> - the run-settings members above (card 4.2);
> - `RunDispatchStore`, `noticeRequested` and the dispatch's `store.flash("Dispatch settings could
>   not be saved")` (1425), which keeps going through the `flash` shim (cards 4.1 and 4.2);
> - moving any `ui/` or `tests/ui/` caller to `app.runControl`, and deleting shims (cards 5.1 and
>   5.2);
> - rewriting `docs/architecture.md` into one paragraph per store (card 5.3). This card only edits
>   the sentences that would otherwise become false (see "Docs").
>
> ## Inherited constraints
>
> - Every member lands in exactly one store. Nothing is duplicated, and nothing is dropped unless
>   no code or test reads it (P l.61-67).
> - No duplicated helpers. The replies are read with `Results.parseEnvelope` from
>   `core/domain/results.js`, which `RunControlStore` already imports (P l.68-71).
> - Inputs come from App. `RunControlStore` keeps exactly its inputs `backendDir`, `project`,
>   `active` and `runs`. The switch needs no new input (P l.77). `RunAlertsStore`'s
>   `notifyOnEscalation` is bound to `app.runControl.notifyOnEscalation` (P l.78, A.3 P l.438).
> - The notify save failure's flash stays inside `RunControlStore`, because the flash already
>   lives there (P l.89-91). It is a direct `control.flash(...)` call, not a signal.
> - Lifecycle stays per store. `startLive`'s two switch lines become `RunControlStore`'s own
>   `active` reaction (P l.92-97, A.3 P l.434). A project switch never changes the switch.
> - A store never imports or names a sibling. The one exception is the shim handle
>   `RunStore.controlStore`, which 3.1 already added (P l.46-50).
> - Shims (P l.122-127):
>   - A property shim is a read-only binding through the handle, and it notifies like the
>     original.
>   - A function shim is a one-line forward that returns the target's result.
>   - Shims hold no state and no logic.
>   - The only comment above them is the existing `// Moved to RunControlStore; removed by the
>     last story`.
> - Tests move with their members. Only construction and the wiring of inputs change, never an
>   expectation. A test that crosses two concerns is pinned at App level (P l.98-104, l.160-162).
> - `tests/architecture` stays green (P l.105-106).
> - No behaviour change, no renamed public member, no new helper argv, no change to which process
>   starts when, and no UI change (P l.146-150).
> - From the card:
>   - `bash tests/run.sh` is green;
>   - TDD: tests first;
>   - docstrings and comments state the contract only, with no narrative;
>   - `tests/ui` passes untouched.
>
> ## The members that move
>
> Every row leaves `RunStore.qml` and lands in `RunControlStore.qml` with its body unchanged,
> except that `store.` becomes `control.` (the new store's root id).
>
> | member | RunStore.qml today | Appendix A row |
> |---|---|---|
> | switch comment block | 170-173 | into the store's contract comment |
> | `notifyOnEscalation` (`property bool`, `false`) | 174 | P l.231 |
> | `notifySaved` (`property bool`, `false`) | 175 | P l.232 |
> | `notifyTouched` (`property bool`, `false`) | 176 | P l.233 |
> | `settingsLoadRunner` alias | 230 | P l.266 |
> | `settingsSaveRunner` alias | 231 | P l.267 |
> | `startLive`'s two switch lines (`if (!settingsSaveRunner.busy) store.notifyTouched = false`, `settingsLoadRunner.run(["get-global-settings"])`) | 379-380 | A.3 P l.434 |
> | `// ---- the notify switch (S2 4.4)` section header | 1057 | kept as a section header |
> | `setNotifyOnEscalation(on)` | 1059-1068 | P l.357 |
> | `applyGlobalSettings(stdout, exitCode)` | 1070-1079 | P l.358 |
> | `notifySaveReplied(stdout, exitCode, sent)` | 1088-1098 | P l.360; `store.flash(...)` → `control.flash(...)` |
> | `settingsLoadRunner` HelperRunner | 1455-1462 | P l.383 |
> | `settingsSaveRunner` HelperRunner (`property bool sent`) | 1475-1483 | P l.385 |
>
> What stays in `RunStore`:
>
> - `startLive` keeps `watchTried = false`, `restartStale()` and `refresh()`. Its comment drops
>   "and read the notify switch (get-global-settings; notifyTouched is cleared first unless a
>   save is in flight)".
> - The `runSettings` comment (177-180) keeps "its notifyOnEscalation is never read". That
>   sentence is about the run settings object.
> - The `projectSwitched` comment (668-670) keeps listing "the notify switch" among what a switch
>   leaves alone. That stays true, because the switch is no longer touched from `RunStore` at all.
>   The planner may drop the phrase instead, but must not claim `projectSwitched` resets it.
>
> ## Behaviour: `RunControlStore`
>
> ### Unchanged from RunStore
>
> Everything below behaves exactly as `RunStore` does today:
>
> - **The defaults.** `notifyOnEscalation`, `notifySaved` and `notifyTouched` are all `false`
>   until read.
> - **Opening.** When `active` turns true, the store clears `notifyTouched` unless
>   `settingsSaveRunner.busy`, then runs `settingsLoadRunner.run(["get-global-settings"])`
>   (argv `python3 <backendDir>projects/viewer-state.py get-global-settings`, three elements,
>   `launchGuard` `""`). Each opening loads exactly once. Closing the panel (`active` turning
>   false) launches nothing and changes nothing on the switch. A store created already active
>   loads nothing until `active` next turns true, which is today's `onActiveChanged` semantics.
> - **The load reply** (`applyGlobalSettings`):
>   - It is ignored while `notifyTouched` is true.
>   - Otherwise `notifyOnEscalation` and `notifySaved` become `true` only when the reply parses
>     and its `notifyOnEscalation === true`. Anything else gives `false`: an unreadable reply,
>     `"yes"`, a missing key, or `{}`.
>   - The runner has no guard and the latest launch wins. A reply that lands after the panel
>     closed is still applied. An older opening's reply, superseded by a newer launch, is
>     dropped by `HelperRunner`.
> - **`setNotifyOnEscalation(on)`** works with or without a project and with the panel open or
>   closed, and returns `true`. It does these steps:
>   1. sets `notifyOnEscalation = !!on` and `notifyTouched = true`;
>   2. sets `settingsSaveRunner.sent = !!on`;
>   3. runs `set-global-settings` with `JSON.stringify({ notifyOnEscalation: !!on })` (four argv
>      elements, `launchGuard` `""`, latest wins).
> - **The save reply** (`notifySaveReplied`):
>   - `{"ok": true}` sets `notifySaved = sent`.
>   - Anything else puts `notifyOnEscalation` back to `notifySaved` and calls
>     `control.flash("Notify on escalation could not be saved")`. That covers `ok: false`, an
>     unreadable reply and garbage. The flash sets this store's `flashText` and restarts its
>     `flashTimer`.
> - **A project change** (`project` input) changes nothing on the switch and launches nothing on
>   either settings runner.
>
> ### Contract comment
>
> The file's header comment (RunControlStore.qml 7-19) gains one sentence, stating only the
> contract. For example: "The 'Notify on escalation' switch is viewer-wide: each opening reads it
> (get-global-settings) and setNotifyOnEscalation writes it (set-global-settings); a failed save
> puts it back and flashes." The sentence "A project switch changes nothing here." stays true. The
> moved members keep their comments from `RunStore` (170-173, 1059-1060, 1070-1072, 1088-1089,
> 1455-1457, 1475-1477), with `startLive` replaced by "each opening" where it is named.
>
> ## Behaviour: `RunStore`
>
> ### Removed
>
> All the rows in the table above. `startLive` no longer touches the switch or the settings load
> runner. `RunStore` launches no `get-global-settings` and no `set-global-settings` of its own.
>
> ### Shims
>
> These are added under the existing `// Moved to RunControlStore; removed by the last story`
> block (RunStore.qml 120-154). They are all read-only, and every one checks
> `store.controlStore` first, so a store with no handle never throws (`tests/run.sh` fails a file
> whose output contains `TypeError`).
>
> | name | shim | without a handle |
> |---|---|---|
> | `notifyOnEscalation` | `readonly property bool` through the handle | `false` |
> | `notifySaved` | `readonly property bool` | `false` |
> | `notifyTouched` | `readonly property bool` | `false` |
> | `settingsLoadRunner` | `readonly property var` (the HelperRunner) | `null` |
> | `settingsSaveRunner` | `readonly property var` (the HelperRunner) | `null` |
> | `setNotifyOnEscalation(on)` | a one-line forward returning the target's result | returns `undefined`, does nothing |
>
> `applyGlobalSettings` and `notifySaveReplied` get **no shim**. No code or test outside
> `RunStore.qml` and the moved tests calls them. Before deleting, the planner greps `ui/`,
> `tests/ui/`, `tst_app_runs.qml`, `tst_run_alerts_store.qml` and the tests that stay in
> `tst_run_store.qml`. Any hit gets a forward shim instead.
>
> **Why every shim can be read-only.** Unlike 3.1's `cancelText` / `cancelRunId`, nothing in
> `ui/` or `tests/ui/` writes these names on a real `RunStore`:
>
> - `ui/screens/RunsScreen.qml:322-323` reads `notifyOnEscalation` and calls
>   `setNotifyOnEscalation`.
> - `tests/ui/screens/tst_runs_screen.qml:998-1000` writes `notifyOnEscalation` on its own stub
>   `runs` object, not on `RunStore`.
> - The `tests/ui` flows only read the members or call `settingsLoadRunner.cancel()`:
>   - `tst_runs_flow.qml:54, 691-693, 701-702, 824-828, 860, 908`;
>   - `tst_dispatch_flow.qml:69`;
>   - `tst_board_flow.qml:151`;
>   - `tst_runs_real_data.qml:49`.
>
>   These run against App, which always sets the handle.
>
> The only writers on a real `RunStore` are in `tests/core/stores`. Their input wiring changes
> (see "Test wiring changes").
>
> ## Behaviour: `App`
>
> `app.runAlerts`'s binding `notifyOnEscalation: app.runs.notifyOnEscalation` (App.qml 151)
> becomes `notifyOnEscalation: app.runControl.notifyOnEscalation`.
>
> Two comments change to match:
>
> - The `runAlerts` comment (App.qml 145-147) names the switch's new owner.
> - The `runControl` comment (App.qml 131-134) is otherwise unchanged. No new input and no new
>   route are needed: `active: app.panelOpen` already drives the opening's load.
>
> ## Equivalence argument (for the reviewer)
>
> - **Same launches.** Today an opening runs `startLive`: clear `notifyTouched` (unless busy),
>   load, `restartStale`, `refresh`. Now `RunStore.startLive` does `restartStale` and `refresh`,
>   and `RunControlStore`'s own `active` reaction does the clear and the load. Both stores bind
>   `active` to `app.panelOpen`, so one opening still launches exactly one `get-global-settings`
>   and one snapshot.
>   - The relative order of those two launches may change. They run on separate runners and
>     neither reads the other's state, so no observable value depends on it.
>   - No test asserts a cross-runner launch order. The planner confirms this by grepping for a
>     shared launch log in `tests/stubs`; there is none at this commit.
> - **The busy check** reads the same `settingsSaveRunner`. It is now the control store's, which is
>   also the one `setNotifyOnEscalation` launches on.
> - **The flash** lands on the same `flashText` / `flashTimer`. Today `store.flash` already
>   forwards to the control store through 3.1's shim.
> - **The alerts input** follows the same value. The `RunStore` shim and `app.runControl` read
>   one property, so binding `runAlerts` straight to the owner gives identical values and change
>   notifications.
>
> ## Tests
>
> TDD: each new or changed test is written first and fails before its code exists. Everything runs
> through `bash tests/run.sh` (qmltestrunner, offscreen, stubs from `tests/stubs`). A single file
> runs with `bash tests/run.sh tst_run_control_store`. The tiers:
>
> - **store unit**: `tests/core/stores/tst_run_control_store.qml`. It pins the switch's behaviour on
>   the store that owns it. It uses the bare-store builder (`makeControl`) and the "through a
>   RunStore wired the way App wires app.runControl" harness (`make`, `makeWithProject`,
>   `controlOf`), both already there.
> - **RunStore unit**: `tests/core/stores/tst_run_store.qml`. It pins the shims, and that the
>   tests mixing run settings with the switch still pass through them.
> - **alerts store unit**: `tests/core/stores/tst_run_alerts_store.qml`. Only its input wiring
>   changes.
> - **App wiring**: `tests/core/stores/tst_app_runs.qml`. It pins the new App binding and the
>   card's "switch on → an alert launches notify.py" route.
> - **UI and architecture**: `tests/ui/**` (untouched) and `pytest tests` (architecture,
>   contract, install).
>
> ### Moved tests (store unit tier: whole, every expectation kept)
>
> These five leave `tst_run_store.qml` and land in `tst_run_control_store.qml` under the same
> names, in a new `// ---- the notify switch (S2 4.4)` section. They keep their numbered comments
> (`// 8 and Review Focus 5`, `// 13`, `// 10`, `// 11`, `// 14`).
>
> | test | tst_run_store.qml today |
> |---|---|
> | `test_the_global_switch_loads_on_each_opening_with_no_project` | 2798-2850 |
> | `test_the_switch_saves_globally_and_a_failed_save_puts_it_back` | 2884-2915 |
> | `test_a_save_reply_survives_a_project_switch` | 2917-2936 |
> | `test_a_save_in_flight_survives_a_reopening` | 2938-2957 |
> | `test_a_load_reply_after_the_user_toggled_is_ignored` | 2959-2969 |
>
> Only one thing changes in the moved bodies: each read, write or call of a moved member, or of
> 3.1's `flash` / `flashText`, goes to `controlOf(x)` instead of the RunStore `x`. The moved
> members are `notifyOnEscalation`, `notifySaved`, `notifyTouched`, `setNotifyOnEscalation`,
> `settingsLoadRunner` and `settingsSaveRunner`. Construction stays (`make()`,
> `makeWithProject(rootA)`), and so do `x.project = …` and `x.active = …` on the RunStore, which
> reach the control store through the harness bindings. This keeps the opening and the project
> switch going through the same wiring App uses.
>
> The one non-moved read in these bodies is `store.notifyRunners.length` (2890), an alerts shim.
> It stays on `store`. The control-store harness wires no alerts store, so the shim reads `[]` and
> the expectation `0` holds unchanged.
>
> `tst_run_control_store.qml` gains `property string viewerCmd:
> "python3|/plugin/core/backend/projects/viewer-state.py|"`, copied from `tst_run_store.qml:2792`.
> The `runSettings(notify)` helper (2794-2796) stays in `tst_run_store.qml`, because only the
> tests that stay there use it. The file's header comment adds "the notify switch" to what it
> covers.
>
> ### Tests that stay in `tst_run_store.qml`, unchanged
>
> These two cross the run settings, which stay in `RunStore` until 4.2, and the switch. They pass
> untouched through the shims, because `make()` wires a control store:
>
> - `test_run_settings_load_per_project_and_never_set_the_switch` (2852-2882);
> - `test_run_settings_kept_even_after_notify_touched` (2983-2996).
>
> `test_settings_write_failure_flashes` (3745), which reads `notifyOnEscalation` and
> `settingsSaveRunner` through the shims (3756-3757), also stays unchanged.
>
> ### New tests
>
> **Store unit (`tst_run_control_store.qml`, bare store, section "the store alone"):**
>
> - **C-N1 `test_a_bare_control_store_has_the_switch_off_and_untouched`**: `makeControl()` gives
>   `notifyOnEscalation`, `notifySaved` and `notifyTouched` all `false`, and `settingsLoadRunner`
>   and `settingsSaveRunner` exist with no `current`. Tier: store unit, because it pins the
>   defaults on the owner with nothing bound.
> - **C-N2 `test_the_stores_own_active_loads_the_switch_and_closing_launches_nothing`**:
>   1. Build with `makeControl()` and set `c.active = true`. Exactly one `get-global-settings`
>      launches.
>   2. Set `c.active = false`. `settingsLoadRunner.seq` is unchanged.
>   3. Set `c.project = "/x"`. Still no launch on either runner.
>   4. Set `c.active = true` again. One more launch.
>
>   Tier: store unit, because it proves the lifecycle is the store's own reaction (P l.92-97)
>   without any `RunStore`.
> - **C-N3 `test_a_failed_save_flashes_on_this_store`**: on a bare store,
>   `setNotifyOnEscalation(true)` returns `true`, then an `ok: false` reply gives `flashText`
>   `Notify on escalation could not be saved` and `flashTimer.running` true. Tier: store unit,
>   because it pins that the flash stays inside the store (P l.89-91) with no RunStore present.
>
> **RunStore unit (`tst_run_store.qml`, section "the run control shims"):**
>
> - **R1, extended** (`test_without_a_control_store_the_shims_are_empty_and_inert`, 5090):
>   - `notifyOnEscalation`, `notifySaved` and `notifyTouched` are `false`;
>   - `settingsLoadRunner` and `settingsSaveRunner` are `null`;
>   - `setNotifyOnEscalation(true)` returns `undefined` and leaves `notifyOnEscalation` `false`.
>
>   Tier: RunStore unit, because the shims live there.
> - **R2, extended** (`test_the_shims_follow_the_control_store_and_notify`, 5123):
>   - `store.settingsLoadRunner === c.settingsLoadRunner` and
>     `store.settingsSaveRunner === c.settingsSaveRunner`;
>   - a `SignalSpy` on `store`'s `notifyOnEscalationChanged` counts 1 after
>     `c.setNotifyOnEscalation(true)`;
>   - `store.notifyOnEscalation` and `store.notifyTouched` are `true`;
>   - after an ok save reply, `store.notifySaved` is `true`;
>   - `store.setNotifyOnEscalation(false)` returns `true` and sets `c.notifyOnEscalation` to
>     `false`, which shows that the forward reaches the control store.
>
>   Tier: RunStore unit.
> - **R4 `test_opening_the_run_store_alone_reads_no_switch`**:
>   1. Build a RunStore with no control handle.
>   2. Set `active = true`. No `TypeError` occurs.
>   3. `settingsLoadRunner` is still `null`, and the snapshot still launches (`snapshotRunner`
>      has a `current`).
>
>   Tier: RunStore unit, because it pins that `startLive` no longer touches the switch.
>
> **App wiring (`tst_app_runs.qml`):**
>
> - **A1, changed** (`test_app_composes_run_alerts_wired_to_the_run_store`, 494-497): line 496
>   `app.runs.notifyOnEscalation = true` becomes `app.runControl.setNotifyOnEscalation(true)`, and
>   the message becomes "the switch follows run control's". The shim is now read-only, so the old
>   write would throw a `TypeError`. This is a wiring change, and the expectation (`true`) is
>   kept.
> - **K-N1 `test_the_alerts_switch_is_run_controls`**:
>   1. `makeBare()`;
>   2. `verify` that `app.runAlerts.notifyOnEscalation` follows `app.runControl.notifyOnEscalation`
>      through a load reply (`app.panelOpen = true`, reply `{"notifyOnEscalation": true}` on
>      `app.runControl.settingsLoadRunner.current`);
>   3. `app.runs.settingsLoadRunner === app.runControl.settingsLoadRunner`;
>   4. `app.runs.notifyOnEscalation` is `true` too.
>
>   Tier: App wiring, because only App binds the alerts input to the control store.
> - **K-N2 `test_with_run_controls_switch_on_an_escalation_launches_notify`** (the card's pin):
>   1. Build with `openApp([runningIn("r1")], [])`.
>   2. Reply `{"notifyOnEscalation": true}` on `app.runControl.settingsLoadRunner.current`.
>   3. A snapshot turns `r1` escalated. `app.runAlerts.notifyRunners.length` is 1, with argv
>      `tc.notifyCmd + "m-r1|escalated"`.
>   4. Then `app.runControl.setNotifyOnEscalation(false)` and an ok save reply. A second
>      escalation (`r2`, added running first) launches no new notify runner.
>
>   Tier: App wiring, because it crosses Control → Alerts (A.3 P l.438).
> - **Unchanged and still passing through the shims**: the existing
>   `test_opening_the_panel_through_app_reads_the_notify_switch` (427) and
>   `test_an_escalation_through_app_notifies_only_with_the_switch_on` (453).
>
> ### Test wiring changes (input wiring only, no expectation changes)
>
> - **`tst_run_store.qml` `wireAlerts` (83-90).** The alerts input is bound the way App now binds
>   it: `a.notifyOnEscalation = Qt.binding(function() { var c = controlOf(store); return c ? c.notifyOnEscalation : false })`.
>   `make()` already calls `wireControl` before `wireAlerts`. The comment above `wireAlerts` says
>   "notifyOnEscalation bound to the paired control store's".
> - **`tst_run_alerts_store.qml`.** Its RunStores have no control handle, so the read-only
>   `notifyOnEscalation` shim reads `false`, and a write to it throws.
>   - `wireAlerts` (309-321) drops the `a.notifyOnEscalation` binding (316), and its comment drops
>     `notifyOnEscalation`.
>   - The five writes `store.notifyOnEscalation = true` / `five.notifyOnEscalation = true` (701,
>     763, 860, 890, 899) become `alerts(store).notifyOnEscalation = true` /
>     `alerts(five).notifyOnEscalation = true`.
>
>   That drives the alerts store's own input directly, the way its bare-store tests (114, 128,
>   277, 287) already do. Every expectation is kept.
>
> ### Gate
>
> `bash tests/run.sh` is green: pytest (including `tests/architecture`), then every qmltestrunner
> file, with no `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign` or `is not a
> function` in the output. `git diff --stat -- ui tests/ui` is empty.
>
> ## Docs
>
> Only the sentences this card makes false are edited. The full rewrite is card 5.3.
>
> - **`docs/architecture.md:84`.** "Opening the panel (`startLive`) reads the notify switch,
>   starts the stale clock and refreshes every root." becomes "… starts the stale clock and
>   refreshes every root."
> - **`docs/architecture.md:91`.**
>   - Add `notifyOnEscalation`, `notifySaved`, `notifyTouched`, `settingsLoadRunner`,
>     `settingsSaveRunner` and `setNotifyOnEscalation` to the list of read-only shims through
>     `controlStore`.
>   - Move the "Notify on escalation" sentences (from "'Notify on escalation' is viewer-wide" to
>     "`RunAlertsStore` reads it through App.") into the `RunControlStore` bullet (93), with
>     "each opening" meaning the store's own `active` turning true.
> - **`docs/architecture.md:93`.** Add the switch to what `RunControlStore` owns, and say that App
>   binds `runAlerts.notifyOnEscalation` to it.
> - **`docs/architecture.md:94`.** `notifyOnEscalation` (`app.runs.notifyOnEscalation`) becomes
>   (`app.runControl.notifyOnEscalation`).
> - **`docs/architecture.md:167`.** "it is RunStore's one viewer-wide switch" becomes "it is
>   `RunControlStore`'s viewer-wide switch, read through the `app.runs` shims". `RunsScreen` still
>   reads `app.runs.notifyOnEscalation`.
>
> ## Review Focus (for the planner)
>
> These are the failure modes the moved tests do not obviously exercise. Each line names the
> condition and the expected behaviour. The planner adds the test to the owning task.
>
> 1. **A RunStore with no control handle opens** (`tst_run_alerts_store.qml`, many
>    `tst_run_store.qml` builders before wiring, R4). Expected: no `TypeError`, the snapshot
>    launches, and the switch shims read `false` / `null`.
> 2. **A save in flight across a reopening.** The busy check must read the control store's own
>    `settingsSaveRunner`, not a shim. Expected: `notifyTouched` survives the reopening, and the
>    new load cannot undo the user's choice. The moved
>    `test_a_save_in_flight_survives_a_reopening` pins this, so it must run against the control
>    store through `controlOf`.
> 3. **A failed save while a cancel or refusal flash is showing.** Expected: the flash text is
>    replaced and `flashTimer` restarts, because it is the same `flash()`. C-N3 pins the timer
>    restart.
> 4. **The alerts store bound to a shim instead of the owner.** Expected: App and both test
>    harnesses bind `runAlerts.notifyOnEscalation` to the control store. A binding to the shim
>    gives the same values, so no test can tell the two apart. The plan's verification step
>    greps `core/stores/App.qml` for `notifyOnEscalation: app.runControl.notifyOnEscalation` and
>    for the absence of `notifyOnEscalation: app.runs.`.
> 5. **A leftover load in `startLive`.** If `startLive` keeps a load line, it can no longer
>    compile against a removed id, or, rewritten through the shim, it launches a second
>    `get-global-settings` per opening. Expected: one load per opening. The moved test 8 checks
>    `seq + 1` per reopening on the control store's runner through a wired RunStore, which
>    catches a second launch. R4 pins that a RunStore with no handle opens without touching any
>    settings runner.
>
> ## Hand-off to the planner
>
> Suggested tasks, each with its own test cycle:
>
> 1. **`RunControlStore` owns the switch.**
>    - Files: `core/stores/RunControlStore.qml` and `tests/core/stores/tst_run_control_store.qml`.
>    - Add the members in the table above, plus `onActiveChanged`. The store gains the switch
>      while `RunStore` still has its own copy. That is temporary, and it is safe because nothing
>      binds to the new members yet.
>    - Tests first: C-N1, C-N2, C-N3, and the five moved tests copied in with the `controlOf`
>      redirects. Do not delete them from `tst_run_store.qml` yet.
> 2. **`RunStore` shims, App rebinding and the wiring changes, in one commit.**
>    - Files: `core/stores/RunStore.qml`, `core/stores/App.qml`,
>      `tests/core/stores/tst_run_store.qml` (delete the five moved tests, R1/R2 extended, R4,
>      `wireAlerts`), `tests/core/stores/tst_run_alerts_store.qml` (wiring), and
>      `tests/core/stores/tst_app_runs.qml` (A1 changed, K-N1, K-N2).
>    - Remove the RunStore members, add the shims, rebind App.
>    - Grep for the no-shim functions before deleting them.
>    - Run the full gate, and confirm that `ui/` and `tests/ui/` are untouched.
> 3. **Docs.** The `docs/architecture.md` edits above and the RunControlStore / RunStore header
>    comments. Contract only, no narrative.
>
> The member interfaces later tasks rely on, exactly:
>
> - `RunControlStore.notifyOnEscalation: bool`, `notifySaved: bool`, `notifyTouched: bool`;
> - `readonly property alias settingsLoadRunner`, `readonly property alias settingsSaveRunner`
>   (HelperRunner, the latter with `property bool sent`);
> - `function setNotifyOnEscalation(on) -> true`;
> - `function applyGlobalSettings(stdout, exitCode)`;
> - `function notifySaveReplied(stdout, exitCode, sent)`.

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `core/stores/RunControlStore.qml` | Modify | Owns the notify switch: 3 properties, 2 runner aliases, `onActiveChanged`, `setNotifyOnEscalation`, `applyGlobalSettings`, `notifySaveReplied`, 2 HelperRunners; header gains one contract sentence |
| `core/stores/RunStore.qml` | Modify | Loses the switch members and `startLive`'s two switch lines; gains 5 property shims + 1 function shim |
| `core/stores/App.qml` | Modify | `runAlerts.notifyOnEscalation` bound to `app.runControl.notifyOnEscalation`; `runAlerts` comment names the owner |
| `tests/core/stores/tst_run_control_store.qml` | Modify | `viewerCmd`; C9–C11 bare-store tests; the five moved tests in a new section |
| `tests/core/stores/tst_run_store.qml` | Modify | Five moved tests deleted; `wireAlerts` binds to the control store; R1/R2 extended; R5 added; header comment |
| `tests/core/stores/tst_run_alerts_store.qml` | Modify | `wireAlerts` drops the switch binding; five writes go to the alerts store |
| `tests/core/stores/tst_app_runs.qml` | Modify | Run-alerts A1 rewired; A8 and A9 (the spec's K-N1, K-N2) |
| `docs/architecture.md` | Modify | Lines 84, 91, 93, 94, 167: only the sentences that become false |

Naming note: the spec calls the new RunStore test "R4", but `tst_run_store.qml` already has an `// R4` (`test_a_snapshot_settles_nothing_without_the_route`), so the new one is commented `// R5`. The spec's C-N1..C-N3 continue the control file's C1..C8 as C9..C11; K-N1/K-N2 continue the runControl section's A1..A7 as A8/A9.

---

### Task 1: `RunControlStore` owns the notify switch

**Files:**
- Modify: `core/stores/RunControlStore.qml` (header 7-19; properties after 44; aliases after 48; new section after `confirmCancel` ending at 298; runners after the `flashTimer` Timer ending at 318)
- Test: `tests/core/stores/tst_run_control_store.qml` (header 1-7; properties 18-21; after C8 ending at 261; end of file 1115)

**Interfaces:**
- Consumes: existing `control.flash(text)`, `control.active`, `control.backendDir`, `Results.parseEnvelope`, `HelperRunner` (`run(args)`, `busy`, `seq`, `current`, `guard`, signal `finished(stdout, exitCode, launchedGuard)`); test harness `makeControl()`, `make()`, `makeWithProject(root)`, `controlOf(store)`, `reply(proc, text, code)`, `argv(proc)`.
- Produces (Task 2 relies on these exact names):
  - `RunControlStore.notifyOnEscalation: bool` (default `false`), `notifySaved: bool` (`false`), `notifyTouched: bool` (`false`);
  - `readonly property alias settingsLoadRunner` (HelperRunner), `readonly property alias settingsSaveRunner` (HelperRunner with `property bool sent`);
  - `function setNotifyOnEscalation(on)` → `true`;
  - `function applyGlobalSettings(stdout, exitCode)`;
  - `function notifySaveReplied(stdout, exitCode, sent)`.

Note: after this task `RunStore` still has its own copy of the switch. Nothing binds to the new members yet, and stub `Process` objects never exit by themselves, so the second (control store's) load App launches on an opening is inert. Task 2 removes the duplicate.

- [ ] **Step 1: Add `viewerCmd` and the header line to the control store test file**

In `tests/core/stores/tst_run_control_store.qml`, replace the header lines 2-7:

```qml
// The run controls store: control requests and their settling, the resume
// verify read, the still-waiting clock, the control error, the cancel
// confirmation and the footer flash. Built alone and driven through its
// `runs` input and settleAfterSnapshot(); and, through a RunStore wired to it
// the way App wires them, a real snapshot reply settling a real request.
// Stubbed Process objects stand in for every helper.
```

with:

```qml
// The run controls store: control requests and their settling, the resume
// verify read, the still-waiting clock, the control error, the cancel
// confirmation, the footer flash and the notify switch. Built alone and
// driven through its `runs` and `active` inputs and settleAfterSnapshot();
// and, through a RunStore wired to it the way App wires them, a real
// snapshot reply settling a real request and each opening reading the switch.
// Stubbed Process objects stand in for every helper.
```

Then after the line `  property string settingsCmd: "python3|/plugin/core/backend/projects/viewer-state.py|get-run-settings|/home/u/my proj"` add:

```qml
  property string viewerCmd: "python3|/plugin/core/backend/projects/viewer-state.py|"
```

- [ ] **Step 2: Write the three bare-store tests (C9–C11)**

In `tests/core/stores/tst_run_control_store.qml`, find the end of C8 and the next section header:

```qml
    compare(c.controlRunners.length, 1)
    compare(c.controlRunners[0].seq, seq, "nothing launched")
  }

  // ---- through a RunStore wired the way App wires app.runControl
```

Replace with:

```qml
    compare(c.controlRunners.length, 1)
    compare(c.controlRunners[0].seq, seq, "nothing launched")
  }

  // C9
  function test_a_bare_control_store_has_the_switch_off_and_untouched() {
    var c = makeControl(); if (!c) return
    compare(c.notifyOnEscalation, false)
    compare(c.notifySaved, false)
    compare(c.notifyTouched, false)
    verify(c.settingsLoadRunner, "the load runner exists")
    verify(c.settingsSaveRunner, "the save runner exists")
    verify(!c.settingsLoadRunner.current, "nothing is loaded")
    verify(!c.settingsSaveRunner.current, "nothing is saved")
    compare(c.settingsSaveRunner.sent, false)
  }

  // C10 and Review Focus 5
  function test_the_stores_own_active_loads_the_switch_and_closing_launches_nothing() {
    var c = makeControl(); if (!c) return
    c.active = true
    var load = c.settingsLoadRunner.current
    verify(load, "the opening loads the switch")
    compare(argv(load), tc.viewerCmd + "get-global-settings")
    compare(load.command.length, 3)
    compare(load.launchGuard, "")
    var seq = c.settingsLoadRunner.seq
    c.active = false
    compare(c.settingsLoadRunner.seq, seq, "closing launches nothing")
    c.project = "/x"
    compare(c.settingsLoadRunner.seq, seq, "a project change launches no load")
    verify(!c.settingsSaveRunner.current, "and no save")
    c.active = true
    compare(c.settingsLoadRunner.seq, seq + 1, "each opening loads once")
  }

  // C11 and Review Focus 3
  function test_a_failed_save_flashes_on_this_store() {
    var c = makeControl(); if (!c) return
    c.flash("The run has finished")
    compare(c.setNotifyOnEscalation(true), true)
    compare(c.notifyOnEscalation, true)
    var save = c.settingsSaveRunner.current
    compare(argv(save), tc.viewerCmd + 'set-global-settings|{"notifyOnEscalation":true}')
    compare(save.command.length, 4)
    compare(save.launchGuard, "")
    reply(save, JSON.stringify({ ok: false, error: "x" }) + "\n", 1)
    compare(c.notifyOnEscalation, false, "back to the value last saved")
    compare(c.flashText, "Notify on escalation could not be saved", "it replaces the flash showing")
    compare(c.flashTimer.running, true)
  }

  // ---- through a RunStore wired the way App wires app.runControl
```

- [ ] **Step 3: Copy the five moved tests into a new section**

In `tests/core/stores/tst_run_control_store.qml`, the file ends with:

```qml
    compare(argv(controlOf(store).controlRunners[0].current), tc.ctlCmd + "cancel|b1|/home/u/b-work")
    compare(controlOf(store).cancelOpen, false)
  }
}
```

Replace with the following (the five tests are `tst_run_store.qml` 2798-2850 and 2884-2970 with every read, write or call of a moved member, `flash` or `flashText` sent to `controlOf(x)`; `x.project`, `x.active` and `store.notifyRunners` stay on the RunStore). Do **not** delete them from `tst_run_store.qml` yet — Task 2 does that.

```qml
    compare(argv(controlOf(store).controlRunners[0].current), tc.ctlCmd + "cancel|b1|/home/u/b-work")
    compare(controlOf(store).cancelOpen, false)
  }

  // ---- the notify switch (S2 4.4)

  // 8 and Review Focus 5
  function test_the_global_switch_loads_on_each_opening_with_no_project() {
    var idle = make(); if (!idle) return
    verify(!controlOf(idle).settingsLoadRunner.current, "a closed panel loads nothing")
    idle.project = tc.rootA
    verify(!controlOf(idle).settingsLoadRunner.current, "a project switch launches no global load")

    var store = make(); if (!store) return
    store.active = true
    var load = controlOf(store).settingsLoadRunner.current
    verify(load, "opening the panel loads the switch, with no project and no registry")
    compare(argv(load), tc.viewerCmd + "get-global-settings")
    compare(load.command.length, 3)
    compare(load.launchGuard, "")
    reply(load, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(controlOf(store).notifyOnEscalation, true)
    compare(controlOf(store).notifySaved, true)
    store.project = tc.rootB
    compare(controlOf(store).notifyOnEscalation, true, "a project switch leaves the switch alone")
    compare(controlOf(store).notifySaved, true)
    compare(controlOf(store).notifyTouched, false)
    var seq = controlOf(store).settingsLoadRunner.seq
    store.project = ""
    compare(controlOf(store).settingsLoadRunner.seq, seq, "and launches no global load")
    store.active = false
    store.active = true
    compare(controlOf(store).settingsLoadRunner.seq, seq + 1, "each opening loads once")
    reply(controlOf(store).settingsLoadRunner.current, "Traceback: boom\n", 1)
    compare(controlOf(store).notifyOnEscalation, false, "an unreadable reply leaves it off")
    compare(controlOf(store).notifySaved, false)
    store.active = false
    store.active = true
    reply(controlOf(store).settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: "yes" }) + "\n", 0)
    compare(controlOf(store).notifyOnEscalation, false, "only a real true turns it on")
    store.active = false
    store.active = true
    reply(controlOf(store).settingsLoadRunner.current, "{}\n", 0)
    compare(controlOf(store).notifyOnEscalation, false)
    store.active = false
    store.active = true
    var late = controlOf(store).settingsLoadRunner.current
    store.active = false
    reply(late, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(controlOf(store).notifyOnEscalation, true, "a reply after the panel closed still lands")
    store.active = true
    var older = controlOf(store).settingsLoadRunner.current
    store.active = false
    store.active = true
    reply(older, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(controlOf(store).notifyOnEscalation, true, "an earlier opening's reply is dropped")
    reply(controlOf(store).settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(controlOf(store).notifyOnEscalation, false, "the newest opening's reply lands")
  }

  // 13
  function test_the_switch_saves_globally_and_a_failed_save_puts_it_back() {
    var store = make(); if (!store) return
    compare(controlOf(store).notifyOnEscalation, false)
    compare(controlOf(store).notifySaved, false)
    compare(controlOf(store).notifyTouched, false)
    compare(store.notifyRunners.length, 0)
    compare(controlOf(store).setNotifyOnEscalation(true), true, "no project and no registry: it still works")
    compare(controlOf(store).notifyOnEscalation, true, "the switch flips at once")
    compare(controlOf(store).notifyTouched, true)
    var save = controlOf(store).settingsSaveRunner.current
    verify(save, "a save was launched")
    compare(save.command.length, 4)
    compare(argv(save), tc.viewerCmd + 'set-global-settings|{"notifyOnEscalation":true}')
    compare(save.launchGuard, "")
    verify(!controlOf(store).settingsLoadRunner.current, "a closed panel loads nothing")
    reply(save, JSON.stringify({ ok: true }) + "\n", 0)
    compare(controlOf(store).notifySaved, true)
    compare(controlOf(store).flashText, "")
    compare(controlOf(store).setNotifyOnEscalation(false), true)
    compare(controlOf(store).notifyOnEscalation, false)
    compare(argv(controlOf(store).settingsSaveRunner.current), tc.viewerCmd + 'set-global-settings|{"notifyOnEscalation":false}')
    reply(controlOf(store).settingsSaveRunner.current, JSON.stringify({ ok: false, error: "x" }) + "\n", 1)
    compare(controlOf(store).notifyOnEscalation, true, "back to the value last saved")
    compare(controlOf(store).notifySaved, true)
    compare(controlOf(store).flashText, "Notify on escalation could not be saved")
    controlOf(store).flash("")
    controlOf(store).setNotifyOnEscalation(false)
    reply(controlOf(store).settingsSaveRunner.current, "garbage\n", 1)
    compare(controlOf(store).notifyOnEscalation, true, "an unreadable reply is a failure too")
    compare(controlOf(store).flashText, "Notify on escalation could not be saved")
  }

  // 10
  function test_a_save_reply_survives_a_project_switch() {
    var store = makeWithProject(rootA); if (!store) return
    controlOf(store).setNotifyOnEscalation(true)
    var save = controlOf(store).settingsSaveRunner.current
    store.project = rootB
    compare(controlOf(store).notifyOnEscalation, true, "the switch is viewer-wide")
    compare(controlOf(store).notifyTouched, true)
    reply(save, JSON.stringify({ ok: false, error: "x" }) + "\n", 1)
    compare(controlOf(store).notifyOnEscalation, false, "rolled back to the value last saved")
    compare(controlOf(store).notifySaved, false)
    compare(controlOf(store).flashText, "Notify on escalation could not be saved")
    controlOf(store).flash("")
    controlOf(store).setNotifyOnEscalation(true)
    var second = controlOf(store).settingsSaveRunner.current
    store.project = ""
    reply(second, JSON.stringify({ ok: true }) + "\n", 0)
    compare(controlOf(store).notifySaved, true, "an ok reply after a switch is applied")
    compare(controlOf(store).notifyOnEscalation, true)
  }

  // 11
  function test_a_save_in_flight_survives_a_reopening() {
    var store = make(); if (!store) return
    store.active = true
    reply(controlOf(store).settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    controlOf(store).setNotifyOnEscalation(true)
    var save = controlOf(store).settingsSaveRunner.current
    store.active = false
    store.active = true
    compare(controlOf(store).notifyTouched, true, "a save is in flight: the touch stays")
    reply(controlOf(store).settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(controlOf(store).notifyOnEscalation, true, "the new load cannot undo the user's choice")
    reply(save, JSON.stringify({ ok: true }) + "\n", 0)
    compare(controlOf(store).notifySaved, true, "the save reply settles notifySaved")
    store.active = false
    store.active = true
    compare(controlOf(store).notifyTouched, false, "no save in flight: the next opening reads again")
    reply(controlOf(store).settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(controlOf(store).notifyOnEscalation, false)
    compare(controlOf(store).notifySaved, false)
  }

  // 14
  function test_a_load_reply_after_the_user_toggled_is_ignored() {
    var store = makeWithProject(rootA); if (!store) return
    store.active = true
    var load = controlOf(store).settingsLoadRunner.current
    compare(argv(load), tc.viewerCmd + "get-global-settings")
    controlOf(store).setNotifyOnEscalation(true)
    reply(load, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(controlOf(store).notifyOnEscalation, true)
    compare(controlOf(store).notifyTouched, true)
  }
}
```

- [ ] **Step 4: Run the control store tests to verify they fail**

Run: `bash tests/run.sh tst_run_control_store`
Expected: FAIL. `FAIL!` lines for `test_a_bare_control_store_has_the_switch_off_and_untouched`, `test_the_stores_own_active_loads_the_switch_and_closing_launches_nothing`, `test_a_failed_save_flashes_on_this_store` and the five moved tests (`TypeError: Cannot read property 'current' of undefined` / `... is not a function` / `compare` of `undefined`), and the script exits non-zero.

- [ ] **Step 5: Add the contract sentence to the `RunControlStore` header**

In `core/stores/RunControlStore.qml` replace:

```qml
// store. App composes it as `app.runControl`, calls settleAfterSnapshot() on
// each ok snapshotReplied of the run store, and routes refreshRequested
// there. A project switch changes nothing here.
```

with:

```qml
// store. App composes it as `app.runControl`, calls settleAfterSnapshot() on
// each ok snapshotReplied of the run store, and routes refreshRequested
// there. The "Notify on escalation" switch is viewer-wide: each opening reads
// it (get-global-settings) and setNotifyOnEscalation writes it
// (set-global-settings); a failed save puts it back and flashes. A project
// switch changes nothing here.
```

- [ ] **Step 6: Add the switch properties and runner aliases**

In `core/stores/RunControlStore.qml` replace:

```qml
  // The footer flash: why a run key was refused. flashTimer clears it.
  property string flashText: ""

  readonly property alias controlRunners: controlState.runners  // in-flight control requests, oldest first
  readonly property alias pendingTimer: pendingTimer
  readonly property alias flashTimer: flashTimer
```

with:

```qml
  // The footer flash: why a run key was refused. flashTimer clears it.
  property string flashText: ""
  // "Notify on escalation", viewer-wide and off until read: the switch's
  // value, the last value read from or written to viewer-state.py's global
  // settings, and whether the user changed it since this opening's load was
  // launched (a late load reply then changes nothing). A project switch
  // never changes them.
  property bool notifyOnEscalation: false
  property bool notifySaved: false
  property bool notifyTouched: false

  readonly property alias controlRunners: controlState.runners  // in-flight control requests, oldest first
  readonly property alias pendingTimer: pendingTimer
  readonly property alias flashTimer: flashTimer
  readonly property alias settingsLoadRunner: settingsLoadRunner
  readonly property alias settingsSaveRunner: settingsSaveRunner
```

- [ ] **Step 7: Add the opening's load, the setter and the two replies**

In `core/stores/RunControlStore.qml` replace:

```qml
    control.closeCancel()
    return true
  }

  // Only while the panel is open and a control request is pending: closing the
```

with:

```qml
    control.closeCancel()
    return true
  }

  // ---- the notify switch (S2 4.4)

  // Each opening (`active` turning true) reads the switch: notifyTouched is
  // cleared first unless a save is in flight. Closing launches nothing.
  onActiveChanged: {
    if (!control.active) return
    if (!settingsSaveRunner.busy) control.notifyTouched = false
    settingsLoadRunner.run(["get-global-settings"])
  }

  // The switch changed: shown at once, written to the global settings in the
  // background. Always works, with or without a project, and returns true.
  function setNotifyOnEscalation(on) {
    var value = !!on
    control.notifyOnEscalation = value
    control.notifyTouched = true
    settingsSaveRunner.sent = value
    settingsSaveRunner.run(["set-global-settings", JSON.stringify({ notifyOnEscalation: value })])
    return true
  }

  // get-global-settings: only a real true turns the switch on; an unreadable
  // reply leaves it off. Too late once the user changed the switch in this
  // opening.
  function applyGlobalSettings(stdout, exitCode) {
    if (control.notifyTouched) return
    var settings = Results.parseEnvelope(stdout)
    var on = settings !== null && settings.notifyOnEscalation === true
    control.notifyOnEscalation = on
    control.notifySaved = on
  }

  // set-global-settings: {"ok": true} means `sent` is stored; anything else puts
  // the switch back to what is stored and says so.
  function notifySaveReplied(stdout, exitCode, sent) {
    var reply = Results.parseEnvelope(stdout)
    if (reply !== null && reply.ok === true) {
      control.notifySaved = sent
      return
    }
    control.notifyOnEscalation = control.notifySaved
    control.flash("Notify on escalation could not be saved")
  }

  // Only while the panel is open and a control request is pending: closing the
```

- [ ] **Step 8: Add the two settings runners**

In `core/stores/RunControlStore.qml` replace:

```qml
    onTriggered: control.flashText = ""
  }

  // The control requests' own state; kept apart so consumers cannot write it.
```

with:

```qml
    onTriggered: control.flashText = ""
  }

  // get-global-settings, once per opening; latest wins. No guard: the switch
  // is viewer-wide, and a reply that lands after the panel closed is still
  // applied.
  HelperRunner {
    id: settingsLoadRunner
    script: control.backendDir + "projects/viewer-state.py"
    onFinished: function(stdout, exitCode) { control.applyGlobalSettings(stdout, exitCode) }
  }

  // set-global-settings on a change of the switch; latest wins. No guard: a
  // project switch never drops its reply. `sent` is the value the latest
  // launch writes.
  HelperRunner {
    id: settingsSaveRunner
    property bool sent: false
    script: control.backendDir + "projects/viewer-state.py"
    onFinished: function(stdout, exitCode) { control.notifySaveReplied(stdout, exitCode, settingsSaveRunner.sent) }
  }

  // The control requests' own state; kept apart so consumers cannot write it.
```

- [ ] **Step 9: Run the control store tests to verify they pass**

Run: `bash tests/run.sh tst_run_control_store`
Expected: pytest passes, then `== tests/core/stores/tst_run_control_store.qml` with `Totals: N passed, 0 failed` and no `FAIL!`, `TypeError` or `ReferenceError` line; exit code 0. (C2 `test_the_pending_and_flash_timers_are_the_stores_only_timers` must still pass: HelperRunner has no `interval`.)

- [ ] **Step 10: Run the full suite**

Run: `bash tests/run.sh`
Expected: exit code 0, every `Totals:` line with `0 failed`, no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `is not a function` lines.

- [ ] **Step 11: Commit**

```bash
git add core/stores/RunControlStore.qml tests/core/stores/tst_run_control_store.qml
git commit -m "feat(runs): RunControlStore owns the notify switch, loaded on its own opening, built alone"
```

---

### Task 2: `RunStore` shims, App rebinding and the test wiring

**Files:**
- Modify: `core/stores/RunStore.qml` (shims after 148 and 154; delete 169-176, 230-231, `startLive` 374-383, 1057-1079, 1087-1098, 1455-1462, 1475-1483)
- Modify: `core/stores/App.qml:145-152`
- Test: `tests/core/stores/tst_run_store.qml` (header 1-9; `wireAlerts` 81-96; delete 2798-2851 and 2884-2971; R1 ~5090; R2 ~5123; end of file)
- Test: `tests/core/stores/tst_run_alerts_store.qml` (308-321; 701, 763, 860, 890, 899)
- Test: `tests/core/stores/tst_app_runs.qml` (494-497; end of file)

**Interfaces:**
- Consumes (from Task 1): `RunControlStore.notifyOnEscalation`, `notifySaved`, `notifyTouched`, `settingsLoadRunner`, `settingsSaveRunner` (with `sent`), `setNotifyOnEscalation(on)` → `true`.
- Produces: `RunStore` read-only shims `notifyOnEscalation: bool` (`false` without a handle), `notifySaved: bool` (`false`), `notifyTouched: bool` (`false`), `settingsLoadRunner: var` (`null`), `settingsSaveRunner: var` (`null`), `setNotifyOnEscalation(on)` → the control store's result, `undefined` without a handle. `app.runAlerts.notifyOnEscalation` is bound to `app.runControl.notifyOnEscalation`.

- [ ] **Step 1: Confirm the no-shim functions have no outside callers and no shared launch log exists**

Run:
```bash
grep -rn "applyGlobalSettings\|notifySaveReplied" ui tests/ui tests/core/stores/tst_app_runs.qml tests/core/stores/tst_run_alerts_store.qml tests/core/stores/tst_run_store.qml
grep -rln "launchLog\|launchOrder" tests/stubs
```
Expected: both print nothing (exit status 1). If the first prints a hit, add a one-line forward shim for that function next to `setNotifyOnEscalation`'s in Step 9, in the same form: `function applyGlobalSettings(stdout, exitCode) { return store.controlStore ? store.controlStore.applyGlobalSettings(stdout, exitCode) : undefined }`.

- [ ] **Step 2: Delete the five moved tests from `tst_run_store.qml`**

Lines 2798-2851 are test 8 (`// 8 and Review Focus 5` through its closing `}` and the blank line after it); 2884-2971 are tests 13, 10, 11 and 14 (from `// 13` through test 14's closing `}` and the blank line after it). One sed pass uses the original numbering:

```bash
sed -n '2798p;2851p;2852p;2884p;2970p;2972p' tests/core/stores/tst_run_store.qml
```
Expected exactly:
```
  // 8 and Review Focus 5

  // 12
  // 13
  }
  // ---- dispatch (S3 3.1)
```
(line 2851 is empty). Then:

```bash
sed -i -e '2884,2971d' -e '2798,2851d' tests/core/stores/tst_run_store.qml
grep -n "test_the_global_switch_loads_on_each_opening_with_no_project\|test_the_switch_saves_globally\|test_a_save_reply_survives_a_project_switch\|test_a_save_in_flight_survives_a_reopening\|test_a_load_reply_after_the_user_toggled_is_ignored" tests/core/stores/tst_run_store.qml
```
Expected: the grep prints nothing. `runSettings(notify)` and `viewerCmd` stay (used by test 12).

- [ ] **Step 3: Bind the alerts input to the control store in `tst_run_store.qml`**

Replace:

```qml
  // A RunAlertsStore wired to `store` the way App wires app.runAlerts:
  // backendDir copied; active, notifyOnEscalation and projectRoots bound to
  // the run store's own; store.alertsStore set; snapshotReplied routed to it.
  function wireAlerts(store) {
    var comp = Qt.createComponent("../../../core/stores/RunAlertsStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var a = comp.createObject(tc, { backendDir: store.backendDir })
    a.active = Qt.binding(function() { return store.active })
    a.notifyOnEscalation = Qt.binding(function() { return store.notifyOnEscalation })
```

with:

```qml
  // A RunAlertsStore wired to `store` the way App wires app.runAlerts:
  // backendDir copied; active and projectRoots bound to the run store's own,
  // notifyOnEscalation bound to the paired control store's; store.alertsStore
  // set; snapshotReplied routed to it.
  function wireAlerts(store) {
    var comp = Qt.createComponent("../../../core/stores/RunAlertsStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var a = comp.createObject(tc, { backendDir: store.backendDir })
    a.active = Qt.binding(function() { return store.active })
    a.notifyOnEscalation = Qt.binding(function() { var c = controlOf(store); return c ? c.notifyOnEscalation : false })
```

And in the file header replace:

```qml
// objects. The run controls are tested in tst_run_control_store.qml, the
// alerts in tst_run_alerts_store.qml.
```

with:

```qml
// objects. The run controls and the notify switch are tested in
// tst_run_control_store.qml, the alerts in tst_run_alerts_store.qml.
```

- [ ] **Step 4: Extend R1 (no handle) in `tst_run_store.qml`**

Replace:

```qml
    compare(store.cancelOpen, false)
    compare(store.flashText, "")
  }

  // R2
```

with:

```qml
    compare(store.cancelOpen, false)
    compare(store.flashText, "")
    compare(store.notifyOnEscalation, false)
    compare(store.notifySaved, false)
    compare(store.notifyTouched, false)
    compare(store.settingsLoadRunner, null)
    compare(store.settingsSaveRunner, null)
    compare(store.setNotifyOnEscalation(true), undefined)
    compare(store.notifyOnEscalation, false, "a forward with no handle does nothing")
  }

  // R2
```

- [ ] **Step 5: Extend R2 (follow and notify) in `tst_run_store.qml`**

Replace:

```qml
    store.closeCancel()
    compare(c.cancelOpen, false, "a forward reaches the control store")
    compare(openSpy.count, 2)
  }
```

with:

```qml
    store.closeCancel()
    compare(c.cancelOpen, false, "a forward reaches the control store")
    compare(openSpy.count, 2)
    verify(store.settingsLoadRunner === c.settingsLoadRunner)
    verify(store.settingsSaveRunner === c.settingsSaveRunner)
    var notifySpy = createTemporaryObject(spyC, tc, { target: store, signalName: "notifyOnEscalationChanged" })
    compare(c.setNotifyOnEscalation(true), true)
    compare(notifySpy.count, 1, "the switch shim notifies like the original")
    compare(store.notifyOnEscalation, true)
    compare(store.notifyTouched, true)
    reply(c.settingsSaveRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
    compare(store.notifySaved, true)
    compare(store.setNotifyOnEscalation(false), true, "the forward returns the target's result")
    compare(c.notifyOnEscalation, false, "and reaches the control store")
  }
```

- [ ] **Step 6: Add R5 (a handle-less RunStore opens and reads no switch) at the end of `tst_run_store.qml`**

Replace the file's last lines:

```qml
    compare(c.pending.r1, "pause", "the run store no longer settles requests itself")
    compare(store.pending.r1, "pause")
  }
}
```

with:

```qml
    compare(c.pending.r1, "pause", "the run store no longer settles requests itself")
    compare(store.pending.r1, "pause")
  }

  // R5 and Review Focus 1, 5
  function test_opening_the_run_store_alone_reads_no_switch() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var store = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    store.projectRoots = [rootEntry(rootA)]
    reply(store.snapshotRunner.current, okReply([running("r1")]), 0)
    var seq = store.snapshotRunner.seq
    store.active = true
    compare(store.settingsLoadRunner, null, "no handle: no switch to read")
    compare(store.settingsSaveRunner, null)
    compare(store.notifyOnEscalation, false)
    compare(store.snapshotRunner.seq, seq + 1, "the opening still snapshots")
    verify(store.snapshotRunner.current)
  }
}
```

- [ ] **Step 7: Rewire `tst_run_alerts_store.qml`**

Check the six target lines first:

```bash
sed -n '316p;701p;763p;860p;890p;899p' tests/core/stores/tst_run_alerts_store.qml
```
Expected exactly:
```
    a.notifyOnEscalation = Qt.binding(function() { return store.notifyOnEscalation })
    store.notifyOnEscalation = true
    store.notifyOnEscalation = true
    store.notifyOnEscalation = true
    five.notifyOnEscalation = true
    store.notifyOnEscalation = true
```
Then, in one pass on the original numbering:

```bash
sed -i \
  -e '701s/store\.notifyOnEscalation = true/alerts(store).notifyOnEscalation = true/' \
  -e '763s/store\.notifyOnEscalation = true/alerts(store).notifyOnEscalation = true/' \
  -e '860s/store\.notifyOnEscalation = true/alerts(store).notifyOnEscalation = true/' \
  -e '890s/five\.notifyOnEscalation = true/alerts(five).notifyOnEscalation = true/' \
  -e '899s/store\.notifyOnEscalation = true/alerts(store).notifyOnEscalation = true/' \
  -e '316d' \
  tests/core/stores/tst_run_alerts_store.qml
grep -n "notifyOnEscalation" tests/core/stores/tst_run_alerts_store.qml
```
Expected grep: only lines with `a.notifyOnEscalation` (92, 114, 128, 277, 287), the comment at 309, and the five `alerts(store).` / `alerts(five).` writes; no `store.notifyOnEscalation` and no `Qt.binding(... notifyOnEscalation`.

Then replace the `wireAlerts` comment:

```qml
  // A RunAlertsStore wired to `store` the way App wires app.runAlerts:
  // backendDir copied; active, notifyOnEscalation and projectRoots bound to
  // the run store's own; store.alertsStore set; snapshotReplied routed to it.
```

with:

```qml
  // A RunAlertsStore wired to `store` the way App wires app.runAlerts:
  // backendDir copied; active and projectRoots bound to the run store's own;
  // store.alertsStore set; snapshotReplied routed to it. notifyOnEscalation is
  // left to each test.
```

- [ ] **Step 8: Rewire run-alerts A1 and add A8, A9 in `tst_app_runs.qml`**

Replace:

```qml
    app.runs.notifyOnEscalation = true
    compare(app.runAlerts.notifyOnEscalation, true, "the switch follows the run store's")
```

with:

```qml
    app.runControl.setNotifyOnEscalation(true)
    compare(app.runAlerts.notifyOnEscalation, true, "the switch follows run control's")
```

Then replace the file's last lines:

```qml
    compare(app.runs.amStatus, "ok")
    compare(app.runControl.pending.b1, undefined, "settled on pB's ok emission")
  }
}
```

with:

```qml
    compare(app.runs.amStatus, "ok")
    compare(app.runControl.pending.b1, undefined, "settled on pB's ok emission")
  }

  // ---- the notify switch on app.runControl (split-runstore 3.2)

  // A8
  function test_the_alerts_switch_is_run_controls() {
    var app = makeBare(); if (!app) return
    app.panelOpen = true
    var load = app.runControl.settingsLoadRunner.current
    verify(load, "the opening loads the switch on run control")
    compare(argv(load), tc.viewerCmd + "get-global-settings")
    reply(load, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(app.runControl.notifyOnEscalation, true)
    compare(app.runAlerts.notifyOnEscalation, true, "the alerts input follows run control's")
    verify(app.runs.settingsLoadRunner === app.runControl.settingsLoadRunner, "the run store's shim")
    compare(app.runs.notifyOnEscalation, true)
  }

  // A9
  function test_with_run_controls_switch_on_an_escalation_launches_notify() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    reply(app.runControl.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(app.runAlerts.notifyOnEscalation, true)
    snapshot(app, listReply([escalatedIn("r1")], []))
    compare(app.runAlerts.toasts.length, 1)
    compare(app.runAlerts.notifyRunners.length, 1, "the switch is on: a notification")
    compare(argv(app.runAlerts.notifyRunners[0].current), tc.notifyCmd + "m-r1|escalated")
    reply(app.runAlerts.notifyRunners[0].current, JSON.stringify({ ok: true, sent: true }) + "\n", 0)
    compare(app.runAlerts.notifyRunners.length, 0)
    compare(app.runControl.setNotifyOnEscalation(false), true)
    reply(app.runControl.settingsSaveRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
    compare(app.runAlerts.notifyOnEscalation, false)
    snapshot(app, listReply([escalatedIn("r1"), runningIn("r2")], []))
    snapshot(app, listReply([escalatedIn("r1"), escalatedIn("r2")], []))
    compare(app.runAlerts.toasts.length, 2, "r2's escalation is raised")
    compare(app.runAlerts.notifyRunners.length, 0, "the switch is off: a toast only")
  }
}
```

- [ ] **Step 9: Run the changed test files to verify they fail**

Run: `bash tests/run.sh tests/core/stores/tst_` 
Expected: non-zero exit. `FAIL!` for `test_without_a_control_store_the_shims_are_empty_and_inert` (`settingsLoadRunner` is not null), `test_the_shims_follow_the_control_store_and_notify` (`store.settingsLoadRunner === c.settingsLoadRunner` false), `test_opening_the_run_store_alone_reads_no_switch`, `test_app_composes_run_alerts_wired_to_the_run_store`, `test_the_alerts_switch_is_run_controls` and `test_with_run_controls_switch_on_an_escalation_launches_notify`. Every other test in `tst_run_store.qml`, `tst_run_alerts_store.qml` and `tst_run_control_store.qml` passes.

- [ ] **Step 10: Add the shims to `RunStore.qml`**

In `core/stores/RunStore.qml` replace:

```qml
  readonly property var flashTimer: store.controlStore ? store.controlStore.flashTimer : null
```

with:

```qml
  readonly property var flashTimer: store.controlStore ? store.controlStore.flashTimer : null
  readonly property bool notifyOnEscalation: store.controlStore ? store.controlStore.notifyOnEscalation : false
  readonly property bool notifySaved: store.controlStore ? store.controlStore.notifySaved : false
  readonly property bool notifyTouched: store.controlStore ? store.controlStore.notifyTouched : false
  readonly property var settingsLoadRunner: store.controlStore ? store.controlStore.settingsLoadRunner : null
  readonly property var settingsSaveRunner: store.controlStore ? store.controlStore.settingsSaveRunner : null
```

and replace:

```qml
  function confirmCancel() { return store.controlStore ? store.controlStore.confirmCancel() : undefined }
```

with:

```qml
  function confirmCancel() { return store.controlStore ? store.controlStore.confirmCancel() : undefined }
  function setNotifyOnEscalation(on) { return store.controlStore ? store.controlStore.setNotifyOnEscalation(on) : undefined }
```

- [ ] **Step 11: Remove the switch members from `RunStore.qml`**

Make each replacement below in `core/stores/RunStore.qml`.

(a) Properties — replace:

```qml
  function notify(alert) { return store.alertsStore ? store.alertsStore.notify(alert) : undefined }
  // "Notify on escalation", viewer-wide and off until read: the switch's
  // value, the last value read from or written to viewer-state.py's global
  // settings, and whether the user changed it since this opening's load was
  // launched (a late load reply then changes nothing). A project switch
  // never changes them.
  property bool notifyOnEscalation: false
  property bool notifySaved: false
  property bool notifyTouched: false
  // The open project's last get-run-settings object (runSettingsRunner), as
```

with:

```qml
  function notify(alert) { return store.alertsStore ? store.alertsStore.notify(alert) : undefined }
  // The open project's last get-run-settings object (runSettingsRunner), as
```

(b) Aliases — replace:

```qml
  readonly property alias logsRunner: logsRunner
  readonly property alias settingsLoadRunner: settingsLoadRunner
  readonly property alias settingsSaveRunner: settingsSaveRunner
  readonly property alias runSettingsRunner: runSettingsRunner
```

with:

```qml
  readonly property alias logsRunner: logsRunner
  readonly property alias runSettingsRunner: runSettingsRunner
```

(c) `startLive` — replace:

```qml
  // The panel opened: fetch now and read the notify switch (get-global-settings;
  // notifyTouched is cleared first unless a save is in flight); the first good
  // snapshot starts the watch, and the stale clock counts from now.
  function startLive() {
    store.watchTried = false
    if (!settingsSaveRunner.busy) store.notifyTouched = false
    settingsLoadRunner.run(["get-global-settings"])
    store.restartStale()
    store.refresh()
  }
```

with:

```qml
  // The panel opened: fetch now; the first good snapshot starts the watch,
  // and the stale clock counts from now.
  function startLive() {
    store.watchTried = false
    store.restartStale()
    store.refresh()
  }
```

(d) The setter and the load reply — replace:

```qml
  // ---- the notify switch (S2 4.4)

  // The switch changed: shown at once, written to the global settings in the
  // background. Always works, with or without a project, and returns true.
  function setNotifyOnEscalation(on) {
    var value = !!on
    store.notifyOnEscalation = value
    store.notifyTouched = true
    settingsSaveRunner.sent = value
    settingsSaveRunner.run(["set-global-settings", JSON.stringify({ notifyOnEscalation: value })])
    return true
  }

  // get-global-settings: only a real true turns the switch on; an unreadable
  // reply leaves it off. Too late once the user changed the switch in this
  // opening.
  function applyGlobalSettings(stdout, exitCode) {
    if (store.notifyTouched) return
    var settings = Results.parseEnvelope(stdout)
    var on = settings !== null && settings.notifyOnEscalation === true
    store.notifyOnEscalation = on
    store.notifySaved = on
  }

  // get-run-settings: one bare object, kept whole as runSettings ({} when
```

with:

```qml
  // get-run-settings: one bare object, kept whole as runSettings ({} when
```

(e) The save reply — replace:

```qml
    store.runSettings = settings !== null ? settings : {}
  }

  // set-global-settings: {"ok": true} means `sent` is stored; anything else puts
  // the switch back to what is stored and says so.
  function notifySaveReplied(stdout, exitCode, sent) {
    var reply = Results.parseEnvelope(stdout)
    if (reply !== null && reply.ok === true) {
      store.notifySaved = sent
      return
    }
    store.notifyOnEscalation = store.notifySaved
    store.flash("Notify on escalation could not be saved")
  }

  // ---- dispatch (S3 3.1)
```

with:

```qml
    store.runSettings = settings !== null ? settings : {}
  }

  // ---- dispatch (S3 3.1)
```

(f) The load runner — replace:

```qml
  // get-global-settings, once per opening (startLive); latest wins. No guard:
  // the switch is viewer-wide, and a reply that lands after the panel closed
  // is still applied.
  HelperRunner {
    id: settingsLoadRunner
    script: store.backendDir + "projects/viewer-state.py"
    onFinished: function(stdout, exitCode) { store.applyGlobalSettings(stdout, exitCode) }
  }

  // get-run-settings on a project switch, for runSettings only. Its guard is
```

with:

```qml
  // get-run-settings on a project switch, for runSettings only. Its guard is
```

(g) The save runner — replace:

```qml
  // set-global-settings on a change of the switch; latest wins. No guard: a
  // project switch never drops its reply. `sent` is the value the latest
  // launch writes.
  HelperRunner {
    id: settingsSaveRunner
    property bool sent: false
    script: store.backendDir + "projects/viewer-state.py"
    onFinished: function(stdout, exitCode) { store.notifySaveReplied(stdout, exitCode, settingsSaveRunner.sent) }
  }

```

with nothing (delete the block including its trailing blank line, so the `runSettingsRunner` block is followed directly by the blank line and the `// dispatch-preview.py --defaults, once per opening.` comment).

Leave the `runSettings` comment ("its notifyOnEscalation is never read") and the `projectSwitched` comment ("... and the notify switch belong to every registered project and stay ...") unchanged: both stay true.

- [ ] **Step 12: Rebind the alerts input in `App.qml`**

In `core/stores/App.qml` replace:

```qml
  // The run alerts never import the run store: App hands them the backend
  // directory, the panel-open flag, the notify switch and the registry, and
  // routes every project's snapshot reply (runs.snapshotReplied) here.
  readonly property RunAlertsStore runAlerts: RunAlertsStore {
    backendDir: app.backendDir
    active: app.panelOpen
    notifyOnEscalation: app.runs.notifyOnEscalation
```

with:

```qml
  // The run alerts never import the run store: App hands them the backend
  // directory, the panel-open flag, run control's notify switch and the
  // registry, and routes every project's snapshot reply (runs.snapshotReplied)
  // here.
  readonly property RunAlertsStore runAlerts: RunAlertsStore {
    backendDir: app.backendDir
    active: app.panelOpen
    notifyOnEscalation: app.runControl.notifyOnEscalation
```

- [ ] **Step 13: Verify the structural invariants (Review Focus 4, 5)**

Run:
```bash
grep -c "notifyOnEscalation: app.runControl.notifyOnEscalation" core/stores/App.qml
grep -n "notifyOnEscalation: app.runs\." core/stores/App.qml
grep -n "get-global-settings\|set-global-settings\|applyGlobalSettings\|notifySaveReplied\|id: settings" core/stores/RunStore.qml
grep -n "notifyOnEscalation\|notifySaved\|notifyTouched\|settingsLoadRunner\|settingsSaveRunner" core/stores/RunStore.qml
```
Expected: first prints `1`; second prints nothing; third prints nothing; fourth prints only the five shim property lines added in Step 10 and the `runSettings` comment line `// notifyOnEscalation is never read.` (the `setNotifyOnEscalation` forward does not match: grep is case-sensitive).

- [ ] **Step 14: Run the full gate**

Run: `bash tests/run.sh; echo "exit=$?"`
Expected: `exit=0`; every `Totals:` line ends `0 failed`; no `FAIL!`, `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign` or `is not a function` line. The `tests/ui` files (`tst_runs_flow`, `tst_dispatch_flow`, `tst_board_flow`, `tst_runs_real_data`, `tst_runs_screen`) pass through the shims.

Then run: `git diff --stat d487cb9 -- ui tests/ui`
Expected: empty output.

- [ ] **Step 15: Commit**

```bash
git add core/stores/RunStore.qml core/stores/App.qml tests/core/stores/tst_run_store.qml tests/core/stores/tst_run_alerts_store.qml tests/core/stores/tst_app_runs.qml
git commit -m "refactor(runs): the notify switch moves to RunControlStore, RunStore keeps shims, App binds runAlerts to it"
```

---

### Task 3: Docs — only the sentences this card makes false

**Files:**
- Modify: `docs/architecture.md` lines 84, 91, 93, 94, 167

**Interfaces:**
- Consumes: the members and wiring of Tasks 1-2.
- Produces: nothing code relies on.

There is no automated test for prose; the "test" is a grep that fails before the edit and passes after.

- [ ] **Step 1: Write the check and see it fail**

Run:
```bash
grep -c "Opening the panel (\`startLive\`) reads the notify switch\|RunStore's one viewer-wide switch\|(\`app.runs.notifyOnEscalation\`) and \`projectRoots\`" docs/architecture.md
grep -c "App binds \`app.runAlerts.notifyOnEscalation\` to it" docs/architecture.md
```
Expected: first prints `3` (lines 84, 94, 167 each match once); second prints `0`.

- [ ] **Step 2: Apply the edits**

Run this script from the repo root (it asserts each anchor occurs exactly once, so a drifted line fails loudly instead of editing the wrong text):

```bash
python3 - <<'EOF'
p = "docs/architecture.md"
s = open(p).read()

def sub(old, new):
    global s
    assert s.count(old) == 1, (s.count(old), old[:60])
    s = s.replace(old, new)

# line 84
sub("Opening the panel (`startLive`) reads the notify switch, starts the stale clock and refreshes every root.",
    "Opening the panel (`startLive`) starts the stale clock and refreshes every root.")

# line 91: who owns what, and the shim list
sub("Run controls, the cancel confirmation and the footer flash (S2 4.1, 4.3) are `RunControlStore`'s.",
    "Run controls, the cancel confirmation, the footer flash and the notify switch (S2 4.1, 4.3, 4.4) are `RunControlStore`'s.")
sub("`openCancel`, `closeCancel` and `confirmCancel` as shims through `controlStore`",
    "`openCancel`, `closeCancel`, `confirmCancel`, `notifyOnEscalation`, `notifySaved`, `notifyTouched`, `settingsLoadRunner`, `settingsSaveRunner` and `setNotifyOnEscalation` as shims through `controlStore`")

# line 91: the switch sentences leave RunStore's bullet
start = s.index(' "Notify on escalation" is viewer-wide and off until read:')
end_marker = "`RunAlertsStore` reads it through App."
end = s.index(end_marker, start) + len(end_marker)
assert "\n" not in s[start:end]
s = s[:start] + s[end:]

# line 93: RunControlStore owns the switch
sub("- `RunControlStore.qml` the run controls (S2 4.1), the cancel confirmation (S2 4.3) and the footer flash, for a run of any registered project.",
    "- `RunControlStore.qml` the run controls (S2 4.1), the cancel confirmation (S2 4.3), the footer flash and the \"Notify on escalation\" switch (S2 4.4), for a run of any registered project.")
sub("`flash(text)` sets `flashText`, which `flashTimer` clears 3 s later; a project switch keeps the dialog and the flash.",
    "`flash(text)` sets `flashText`, which `flashTimer` clears 3 s later; a project switch keeps the dialog and the flash. "
    "\"Notify on escalation\" is viewer-wide and off until read: each opening (`active` turning true) clears `notifyTouched` (unless a save is in flight) and reads `viewer-state.py get-global-settings` on `settingsLoadRunner` (no guard, latest wins; a reply after the panel closed still lands; only a real `true` turns it on), and closing launches nothing; "
    "`setNotifyOnEscalation(on)` works with or without a project, flips it at once and writes `set-global-settings {\"notifyOnEscalation\": …}` on `settingsSaveRunner` (latest wins, no guard, so a project switch never drops its reply); "
    "a failed save puts the switch back to `notifySaved` and flashes `Notify on escalation could not be saved`, a load reply that lands after the user changed the switch in this opening (`notifyTouched`) is ignored, and a project switch never changes the switch. "
    "App binds `app.runAlerts.notifyOnEscalation` to it.")

# line 94
sub("`notifyOnEscalation` (`app.runs.notifyOnEscalation`)",
    "`notifyOnEscalation` (`app.runControl.notifyOnEscalation`)")

# line 167
sub("it is RunStore's one viewer-wide switch",
    "it is `RunControlStore`'s viewer-wide switch, read through the `app.runs` shims")

open(p, "w").write(s)
EOF
```

- [ ] **Step 3: Run the check again and see it pass**

Run:
```bash
grep -c "Opening the panel (\`startLive\`) reads the notify switch\|RunStore's one viewer-wide switch\|(\`app.runs.notifyOnEscalation\`) and \`projectRoots\`" docs/architecture.md
grep -c "App binds \`app.runAlerts.notifyOnEscalation\` to it" docs/architecture.md
grep -c '"Notify on escalation" is viewer-wide' docs/architecture.md
git diff --stat -- docs/architecture.md
```
Expected: `0`, `1`, `1`, and `docs/architecture.md | 10 +++++-----` (5 lines changed: 84, 91, 93, 94, 167).

- [ ] **Step 4: Run the full gate once more**

Run: `bash tests/run.sh; echo "exit=$?"`
Expected: `exit=0`, no `FAIL!` and none of the error strings listed in Global Constraints.

- [ ] **Step 5: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): the notify switch is RunControlStore's, RunStore keeps shims"
```

---

## Self-review against the spec

- **Members table** → Task 1 Steps 6-8 add every row to `RunControlStore`; Task 2 Step 11 (a)-(g) removes every row from `RunStore`, including `startLive`'s two lines and the section header.
- **What stays in `RunStore`** (`startLive`'s three lines, the `runSettings` and `projectSwitched` comments, all run-settings members) → Task 2 Step 11 (c) and the closing note of Step 11.
- **Behaviour: opening / closing / project change / load reply / setter / save reply** → moved tests 8, 13, 10, 11, 14 and C9-C11 (Task 1).
- **Contract comment** → Task 1 Step 5; member comments copied in Steps 6-8 with `startLive` replaced by "each opening".
- **Shims table and no-handle values** → Task 2 Step 10; pinned by R1 extended, R2 extended, R5.
- **No shim for `applyGlobalSettings` / `notifySaveReplied`** → Task 2 Step 1 grep.
- **App binding and comment** → Task 2 Step 12; pinned by run-alerts A1 (rewired), A8, A9; grep in Step 13.
- **Equivalence: no shared launch log** → Task 2 Step 1 grep of `tests/stubs`.
- **Moved tests** (names, numbered comments, `controlOf` redirect, `store.notifyRunners` kept, `viewerCmd`, header comment) → Task 1 Steps 1, 3; deletion Task 2 Step 2; `runSettings(notify)` stays.
- **Tests that stay unchanged** (12, 35, 30, App 427 and 453) → untouched; pass through the shims in Task 2 Step 14.
- **Wiring changes** (`tst_run_store` `wireAlerts`, `tst_run_alerts_store` binding + five writes) → Task 2 Steps 3, 7.
- **Gate** (`bash tests/run.sh`, `git diff --stat -- ui tests/ui` empty) → Task 2 Step 14, Task 3 Step 4.
- **Docs** (84, 91, 93, 94, 167) → Task 3.
- **Review Focus 1-5** → each has a test or grep in the owning task, listed at the top.
- **Type consistency**: `settingsLoadRunner` / `settingsSaveRunner` / `sent` / `setNotifyOnEscalation(on)` / `notifySaveReplied(stdout, exitCode, sent)` spelled identically in Tasks 1 and 2 and in the docs.
<!-- task-pipeline: validated -->
