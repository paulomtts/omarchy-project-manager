# 3.4 RunStore: alerts across projects and the global notify setting — design

Card `7159b939` (subtask of story `fee6bfab` "Global runs store"), blocked by 3.3
(`58c3c3f4`, landed: `docs/superpowers/specs/3-3-runstore-the-58c3c3f4.md`, cited as
**3.3:§**). 3.1 is `docs/superpowers/specs/3-1-runstore-the-d6d38ee2.md` (**3.1:§**). The parent
design is `docs/superpowers/specs/2026-10-05-runs-all-projects-design.md`, cited as **S6:line**.

3.3 hands this card exactly this work: "**3.4**: per-project alert arming and the global notify
switch" (3.3 "Out of scope").

All the code is in `core/stores/RunStore.qml`. The tests are in
`tests/core/stores/tst_run_store.qml`, plus a one-line change to four UI test setups (§6).

## Inherited constraints

- **Alerts are global and name the project (S6:69-71).** The escalation toasts and the
  desktop notification cover every registered project, and an alert names its project.
- **Arming (S6:79-82, S6:172).** The first good snapshot only arms. It never alerts its
  history. A project registered later is armed by the first snapshot that lists it. A failed
  snapshot keeps the previous runs and the armed state. "The first snapshot fails" means
  alerts start with the first good snapshot, and that snapshot only arms.
- **One viewer-wide notify switch (S6:73-78).** It moves to `viewer-state.py
  get-global-settings` / `set-global-settings`. The per-project `notifyOnEscalation` value
  is no longer read or written. The switch works with no project open. On the first read,
  with nothing stored, `get-global-settings` answers true when any project's stored value
  is true. The backend already does this (`core/backend/projects/viewer-state.py:29-31,
  138-146`); this card does not change it.
- **A project switch no longer resets alerts or toasts (S6:133-134).** `project` keeps its
  meaning, the open project's root (S6:130-132).
- **Dispatch stays project-bound (S6:83-85).** It starts from the open project's
  `runSettings` (`docs/architecture.md:92`). See "Where the card is ambiguous" (3).
- **Layering (S6:111; `docs/architecture.md`).** `RunStore.qml` imports only QtQml,
  Quickshell, Quickshell.Io and `../domain`. `tests/architecture` must pass.
- **Comments state the contract only, no narrative** (card).

## Where the card is ambiguous, and the reading this spec fixes

1. **"The first after its AmMissing/failed spell only arms it" versus "a failed snapshot
   keeps its previous runs and armed state."** Both hold under this rule. A failed entry
   for a root never changes that root's armed state. A root that was never armed (its first
   snapshot failed) stays unarmed, so its first good entry only arms (S6:172). A root that
   was armed stays armed. Its recovery is then compared against the runs it kept, so a run
   escalated before the failure and still escalated after it raises nothing. An **AmMissing
   spell** is the reply where every matched entry is AmMissing (3.1, today's `missing`
   branch). It empties the runs and disarms **every** root. An AmMissing entry next to an
   entry that answered, or next to an entry that failed another way, is a failed entry
   like any other.
2. **Which project a duplicated run alerts under.** One repository can be registered under
   two roots. Its runs then show once in `runs`, under the first root (3.1 merge). An alert
   is raised at most once per run id per reply. It is credited to the root that owns the run
   in the merged `runs`. The toast's `project` is that root's name.
3. **"Remove the per-project settings read from projectSwitched."** This spec reads it as
   "the switch no longer comes from the per-project read". `runSettings`, the
   `get-run-settings` object that dispatch starts from (`RunStore.qml:1447, 1627, 1673`;
   `docs/architecture.md:92`), still has to load for the open project. Without it, every
   dispatch would lose its stored verify set, prefix history and parallelism. That would
   regress S3, and S6:83 keeps S3 unchanged. So:
   - `settingsLoadRunner` becomes the **global** load: `get-global-settings`, launched when
     the panel opens, with no guard. That is what the card names.
   - The per-project read moves to a new runner, **`runSettingsRunner`**. It runs
     `get-run-settings <project>`, is launched by `projectSwitched()` exactly as today
     (guarded by the new project, nothing launched for `""`), and fills **only**
     `runSettings`. Its reply never touches `notifyOnEscalation`, `notifySaved` or
     `notifyTouched`.

   The reviewer should check this reading. The literal one (no `get-run-settings` on a
   switch at all) breaks about 15 dispatch store tests and `tst_dispatch_flow.qml`.
4. **When `notifyTouched` resets.** Today it means "the user changed the switch since this
   project's load was launched". It now means **"since this opening's load was
   launched"**. `startLive()` clears it just before it launches the global load, unless a
   save is in flight (`settingsSaveRunner.busy`). In that case it stays true, so a load
   that might read the file before the save lands cannot undo the user's choice.

## What the store must do

### 1. Arming state

| member | kind | contract |
|---|---|---|
| `armedRoots` | `property var`, default `({})` | `{root: true}` for every usable root whose alerts are armed. It is replaced, never mutated (`copyMap`). Keys are registry roots exactly as `usableRoots()` gives them. |
| `alertsArmed` | `readonly property bool` (was a writable `bool`) | `Object.keys(armedRoots).length > 0`. It is kept so existing assertions and `docs/architecture.md:86` still read. |

Every write that used to set `alertsArmed = false` sets `armedRoots = {}` instead:
`startLive`, `stopLive`, `forgetLive` (starting over, which includes the store-id change)
and the AmMissing spell in `applyProjects`. Nothing sets `alertsArmed` directly any more.

`registryChanged()` keeps only the keys of `armedRoots` that are still usable roots. It
replaces the map only when a key goes. A root that leaves the registry and comes back is
unarmed: its next good entry only arms.

### 2. Applying a list reply (`applyProjects`)

The runs, `runsByProject`, `projectErrors`, `amStatus` and coverage rules of 3.1 / 3.2 do
not change. Only the alert computation changes. For a reply that is not an AmMissing spell
and has at least one matched entry:

1. `prev` is `store.runsByProject` as it was **before** this reply. Read it before the
   replacement.
2. For each matched entry, in **usable (registry) order**, not reply order:
   - **ok entry for root `r`:**
     - If the store is active and `armedRoots[r]` is true, the candidates are
       `Runs.newAlerts(prev[r] or [], next[r])`. `next[r]` is the new tagged list of `r`,
       kept only where the run is owned by `r` in the merged list (`merged.owner[id] === r`).
       An alert whose run id was already raised earlier in this reply is skipped. Each kept
       alert gets `project` = the name `r` carries in `runs` (`run.project.name` of the
       merged run, which is `Runs.withProject`'s name for `r`).
     - If the store is active, `r` is armed after this reply (`armedRoots[r] = true`),
       whether or not it alerted.
     - If the store is not active, nothing is raised and `armedRoots` does not change.
       A closed panel never arms (today's test at `tst_run_store.qml:3309-3317`).
   - **failed entry for root `r`** (any error type, AmMissing included, when the reply is
     not a spell): no alert, and `armedRoots[r]` does not change.
   - **usable root with no entry** (a partial refresh of 3.2): nothing changes for it.
3. If no entry is ok (the `!anyOk` branch, `amStatus` "error"): nothing is raised and
   `armedRoots` does not change. Today the alerts are computed before that branch but only
   raised after it, so this behaves the same.
4. While active, `raiseAlerts(alerts)` runs at the same point as today, after the runs are
   replaced and the watch is handled. `alerts` is the list from step 2 in registry order,
   then each root's order. `armedRoots` is then replaced by the new map.

Consequences the tests pin:

- An escalation in project B while A is unchanged raises exactly one toast, with
  `project` "beta".
- A project whose first entry fails, or that is added to the registry later, is unarmed.
  Its first good entry raises nothing, even when it lists escalated or dead runs. The entry
  after that compares normally.
- A failed entry for an armed project raises nothing and keeps the project armed. The
  recovery entry compares against the runs kept through the failure.
- An AmMissing spell disarms every project. The next good reply only arms every project
  that answers in it.

### 3. Toasts (`raiseAlerts`)

A toast is `{key, id, title, state, reason, project, expiresMs}`. `project` is the alert's
project name, a string (`""` only if a run somehow has no `project`, which `withProject`
never produces). The cap of three, replacing a run's older toast, expiry and dismissal do
not change. `Runs.newAlerts` (`core/domain/runs.js:977-1000`) does not change. The store
attaches `project`.

- Closing the panel (`stopLive`) still sets `toasts = []`.
- A project switch does **not** touch `toasts` or `armedRoots`. That is already true; a
  test pins it.
- With the switch on, every raised alert, including one whose toast the cap pushed out,
  runs `notify.py` with `[title, reason]` on a runner of its own, exactly as today
  (`RunStore.qml:1339-1343`). The notification text does not change. Adding the project to
  it is not in the card.

The doc comment of `ui/components/RunToast.qml:14` lists the new shape
(`{key, id, title, state, reason, project, expiresMs}`). Only that comment changes in that
file. Rendering the project belongs to the UI story.

### 4. The global notify switch

| member | contract |
|---|---|
| `notifyOnEscalation` | The switch. It reads false until the first global load reply or the user's first change. It is viewer-wide: a project switch never changes it. |
| `notifySaved` | The last value read from or written to `get-global-settings` / `set-global-settings`. |
| `notifyTouched` | The user changed the switch since this opening's load was launched (ambiguity 4). |
| `settingsLoadRunner` | `viewer-state.py get-global-settings`. Guard `""`, never set. Launched by `startLive()`, once per opening. |
| `settingsSaveRunner` | `viewer-state.py set-global-settings <json>`. Latest wins. **No guard** (the `guard: store.project` binding is removed). |

- **Load.** `startLive()` sets `notifyTouched = false` unless `settingsSaveRunner.busy`.
  It then runs `settingsLoadRunner.run(["get-global-settings"])`, which is 3 argv elements
  with `python3` and the script. It does this with or without a project and with or without
  a registry. The reply (`applyGlobalSettings(stdout, exitCode)`) does nothing when
  `notifyTouched` is true. Otherwise `on` = the parsed object's `notifyOnEscalation === true`,
  and both `notifyOnEscalation` and `notifySaved` become `on`. An unreadable reply, or a
  value that is not the boolean `true`, gives false. That is today's rule, applied to the
  new reply. A load reply that lands after the panel closed is still applied.
- **Save.** `setNotifyOnEscalation(on)` **always** works and returns `true`, with no
  project check. It sets `notifyOnEscalation = !!on` and `notifyTouched = true`, records the
  sent value, and runs `settingsSaveRunner.run(["set-global-settings",
  JSON.stringify({ notifyOnEscalation: value })])`, which is 4 argv elements. The reply
  (`notifySaveReplied`, unchanged): `{"ok": true}` sets `notifySaved` to the sent value.
  Anything else puts `notifyOnEscalation` back to `notifySaved` and flashes `Notify on
  escalation could not be saved`. A project switch between the launch and the reply does
  not drop the reply.
- **A project switch** never changes `notifyOnEscalation`, `notifySaved`, `notifyTouched` or
  either notify runner. It launches no global load.
- **`get-run-settings` never sets the switch.** A stored per-project `notifyOnEscalation`
  stays inside `runSettings` as it was read, and the store ignores it.

### 5. `runSettings` (ambiguity 3)

`runSettingsRunner`, a `HelperRunner` on `projects/viewer-state.py`, takes over today's
`settingsLoadRunner` role for `runSettings` only:

- `projectSwitched()` keeps `runSettings = {}`. It then sets `runSettingsRunner.guard =
  store.project` and, when the project is not `""`, runs `["get-run-settings",
  store.project]`. This is the same timing and guard rule as today
  (`RunStore.qml:655-656, 1741-1752`).
- The reply sets `runSettings` to the parsed object, or `{}` when it is unreadable, and
  nothing else (the `runSettings` half of today's `applyRunSettings`). A reply for a
  project the user has left is dropped by the guard.
- Dispatch reads `runSettings` exactly as before.

`projectSwitched()` otherwise keeps `resetDispatch`, `dismissControlError`, `closeCancel` and
`flash("")`. Those belong to 3.5. Its comment is updated to the new contract.

### 6. UI test setups

`tests/ui/tst_runs_flow.qml:44`, `tst_runs_real_data.qml:49`, `tst_dispatch_flow.qml:69` and
`tst_board_flow.qml:151` cancel `settingsLoadRunner` after selecting a project, so its late
reply cannot change anything. Each one also cancels `runSettingsRunner` the same way. No
other UI or App change is needed: `RunsScreen.qml:126-127` already binds the switch to
`notifyOnEscalation` / `setNotifyOnEscalation`, and showing it with no project open is the
UI story's work.

### 7. Docs

`docs/architecture.md` states the RunStore contract. Its alert and settings sentences
(line 86 "`runs` and `alertsArmed`"; the dispatch paragraph's "`runSettings` -- the current
project's whole `get-run-settings` reply") are updated to say: per-root arming
(`armedRoots`), the toast's `project`, the global switch through
`get-global-settings` / `set-global-settings` loaded on each opening, and `runSettings`
loaded by `runSettingsRunner` on a project switch. The same paragraph's "Closing the panel and a
project switch empty `toasts`", "a first good list snapshot after ... a project switch ... only
arms" and "Notify on escalation is per project" sentences, and the `toasts` shape
`{key, id, title, state, reason, expiresMs}`, are corrected to match: only closing the panel
empties `toasts`, a project switch neither disarms nor empties, and the shape gains `project`.

## Error paths

| input | behaviour |
|---|---|
| global load reply `Traceback…` (exit 1), `{}`, `{"notifyOnEscalation": "yes"}` | switch and `notifySaved` false (unless touched) |
| global load reply after `setNotifyOnEscalation` in the same opening | ignored |
| panel reopened while a save is in flight | `notifyTouched` stays true; the new load reply is ignored; the save reply settles `notifySaved` |
| save reply `{"ok": false, …}` or garbage | rolls back to `notifySaved` and flashes `Notify on escalation could not be saved` |
| save reply after a project switch | applied as if no switch happened |
| `setNotifyOnEscalation` with no project and no registry | flips, launches `set-global-settings`, returns true |
| a reply with A ok and B failed, B armed and escalated before | no toast; B stays armed |
| first reply: A ok, B failed; next reply: B ok listing an escalated run | first: A armed, B not; next: no toast, B now armed |
| a run id listed by roots A and B (one repository) turns escalated | one toast, `project` A's name |
| every matched entry AmMissing | runs emptied; `armedRoots` `{}` |
| an AmMissing entry for B beside an ok entry for A | B counts as a failed entry: runs and armed state kept |
| a reply that lands while the panel is closed | runs applied; no toast; `armedRoots` unchanged (it is `{}` after a close) |
| registry drops B, then adds it back | B is unarmed; its next good entry only arms |

## Tests

All store tests are **store tier** (`tests/core/stores/tst_run_store.qml`). The behaviour is
the store's own reply-driven state machine, driven by stubbed `Process` replies with no UI.
That is the only tier that can reach `armedRoots`, the runner argv and guards, and the toast
objects. The tests use the existing helpers: `activeRoots`, `makeWithRoots`, `make`,
`makeWithProject`, `activeStore`, `armedStore`, `allReply`, `okEntry`, `failEntry`, `entry`
(with its `root` argument), `escalated`, `running`, `dead`, `snapshot`, `reply`, `argv`,
`toastIds`, `tc.viewerCmd` and `tc.notifyCmd`, with `rootA` "alpha" and `rootB` "beta".

New, in a `// ---- alerts across projects (3.4)` block next to the S2 4.4 alert block:

1. **An escalation in another project raises one toast with its project.** Register A and B
   with no project open. The first reply lists a running run in each and arms both
   (`armedRoots` has both keys, no toast). The next reply has B's run escalated and A
   unchanged: exactly one toast, `id` B's run, `project` "beta". With the switch on, exactly
   one `notify.py` launch, argv `tc.notifyCmd + "m-<id>|escalated"`.
2. **Per-project arming with a late project.** Register A and B. The first reply has A ok
   and B failed (`AmTimeout`): `armedRoots` is `{A}`. The next reply has B ok listing an
   escalated and a dead run: no toast, and B is now armed. The one after that has a new
   escalated run in B: one toast, `project` "beta". In the same test, reassign
   `projectRoots` to add `rootC`. Its first entry, listing an escalated run, raises nothing
   and arms C.
3. **A failing project does not alert and keeps its armed state.** Register A and B, both
   armed, with B's run running. A reply with B failed and A ok raises nothing, keeps B's
   runs and keeps B in `armedRoots`. A recovery reply with B's run escalated raises one toast
   with "beta". A recovery that only repeats a run escalated before the failure raises
   nothing.
4. **An AmMissing spell disarms every project.** Both armed, then an all-AmMissing reply:
   `armedRoots` is `{}`. The next good reply listing escalated runs in both raises nothing
   and arms both. An AmMissing entry for B beside an ok A is a failed entry: B keeps its
   runs and its armed state.
5. **A duplicated run alerts once, under its first root.** Register A and B, and give both
   entries the same run id. Turning it escalated in both raises one toast, `project`
   "alpha".
6. **The registry drops a root's arming.** Arm A and B, then reassign `projectRoots` to A
   only: `armedRoots` is `{A}`. Add B back: its next entry listing an escalated run raises
   nothing.
7. **A project switch keeps the toasts and the arming.** Arm A and B and raise a toast. Set
   `project` to A, then to `""`: `toasts` and `armedRoots` are unchanged, and the next
   escalation still alerts. This extends the existing
   `test_a_project_switch_keeps_the_toasts_and_the_alerts_armed`.
8. **The global switch loads on opening, with no project.** `make()` then `active = true`:
   `settingsLoadRunner.current` argv is `tc.viewerCmd + "get-global-settings"`,
   `command.length` is 3 and `launchGuard` is `""`. Reply `{"notifyOnEscalation": true}`:
   switch and `notifySaved` are true. Garbage or `"yes"` gives false. Close and reopen: one
   new load is launched. An inactive store (`make()` alone) launches no load. Setting
   `project` launches no global load and leaves the switch as it is.
9. **Save and rollback with no project.** On `make()`, `setNotifyOnEscalation(true)` returns
   true and flips at once. Save argv is `tc.viewerCmd + 'set-global-settings|{"notifyOnEscalation":true}'`,
   `command.length` is 4 and `launchGuard` is `""`. `{"ok": true}` sets `notifySaved`. A
   later `false` save answered `{"ok": false}` rolls back to true and flashes. Garbage does
   the same.
10. **A save reply survives a project switch.** Launch a save, set `project` to B, then
    reply `{"ok": false}`: the rollback and the flash happen.
11. **A late load after a touch is ignored, and an in-flight save survives a reopening.**
    Open, `setNotifyOnEscalation(true)`, then reply the load with false: the switch is still
    true. Then launch a save, close and reopen before it replies: `notifyTouched` is still
    true, and the new load's reply with false is ignored.
12. **`runSettings` loads per project and never sets the switch.** `makeWithProject(rootA)`:
    `runSettingsRunner.current` argv is `tc.viewerCmd + "get-run-settings|/home/u/my proj"`
    and `launchGuard` is rootA. Reply `dispatchSettings()` with `notifyOnEscalation: true`:
    `runSettings` holds it, and `notifyOnEscalation` and `notifySaved` stay false. A project
    switch resets `runSettings` to `{}` and loads B. A late reply for A is dropped. A switch
    to `""` loads nothing.

Existing tests rewritten for the changed contract:

- `test_a_project_switch_leaves_the_run_list_and_the_live_state_alone`
  (`tst_run_store.qml:395-440`): the load it expects at 438-439 is
  `runSettingsRunner` / `get-run-settings`.
- The setting block at `tst_run_store.qml:3492-3651`: tests 10, 11 and 13 and "Review
  Focus 3" move to the global argv and `runSettingsRunner` as in new tests 8-12.
  `test_a_save_reply_for_a_project_the_user_left_changes_nothing` becomes new test 10 with
  the opposite outcome. `test_without_a_project_the_switch_does_nothing` becomes "without a
  project the switch works" (new test 9).
- Every dispatch and resume test that replies to `settingsLoadRunner` for `runSettings`
  (`tst_run_store.qml:3668-3690, 3707, 3753, 3784, 4304, 4324, 4492-4605, 4840, 4898,
  5005`) replies to `runSettingsRunner` instead. Their assertions do not change.
- `test_run_settings_kept_even_after_notify_touched` keeps its name: `runSettings` is kept
  whole, and the switch keeps the user's value.

Regression: the S2 4.4 toast tests (`tst_run_store.qml:3300-3470`), the 3.1 failing-root
and AmMissing tests (`:227-300`) and the 3.2 nudge alert test (`:1026`) pass with only the
`alertsArmed` → derived change. `tests/ui/*` pass with the extra `runSettingsRunner.cancel()`.
Verification is `bash tests/run.sh`, all green, including `tests/architecture`.

## Out of scope

- **UI story `63a11d2f`:** rendering the project name on `RunToast`, the switch on the Runs
  screen with no project open (and the `RunsScreen.qml:118` "the project's" comment),
  `RunIndicator` mounting, and `tests/ui` checks of cross-project toasts.
- **3.5:** control, resume settings (`get-run-settings` of `run.project.root`), logs,
  removing the remaining guards and the `projectSwitched()` resets of the cancel dialog,
  control error and flash.
- The project in the desktop notification text, persisted alert cursors while the panel is
  closed (S6:81-82, the alerts spec), any change to `core/domain/runs.js`, the backends,
  `viewer-state.py`, or the snapshot and watch request rules of 3.1 and 3.2.

---

# 3.4 RunStore: alerts across projects and the global notify setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `RunStore` arms its alerts per registered root (`armedRoots`), credits every toast to its project, reads and writes one viewer-wide "Notify on escalation" switch through `get-global-settings` / `set-global-settings`, and moves the per-project `get-run-settings` read to its own `runSettingsRunner`.

**Architecture:** All behaviour lives in `core/stores/RunStore.qml`. `applyProjects` keeps `prev = runsByProject` from before the reply and, while active, asks a new `alertsOf(prev, byProject, owner, okRoots, usable)` for the alerts of every armed root that answered ok, then arms every root that answered ok. `registryChanged` trims `armedRoots` to the usable roots. `settingsLoadRunner` becomes the unguarded global load launched by `startLive()`; a new `runSettingsRunner` takes the old per-project read for `runSettings` only; `settingsSaveRunner` loses its guard and writes `set-global-settings`. No change to `core/domain/runs.js` or any backend.

**Tech Stack:** QML (Qt 6, Quickshell), the `core/domain/runs.js` domain library, QtTest (`qmltestrunner`) driven by `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/3-4-runstore-alerts-7159b939.md` (prepended above).

## Global Constraints

- `RunStore.qml` imports only QtQml, Quickshell, Quickshell.Io and `../domain`. `tests/architecture` must pass.
- Comments state the contract only, no narrative.
- No change to `core/domain/runs.js` (`Runs.newAlerts` included), the backends, `viewer-state.py`, or the snapshot and watch request rules of 3.1 and 3.2.
- The desktop notification text stays `[title, reason]`; the project is **not** added to it.
- A toast is `{key, id, title, state, reason, project, expiresMs}`; the cap of three, replacement, expiry and dismissal do not change.
- `alertsArmed` stays, as `readonly property bool alertsArmed: Object.keys(store.armedRoots).length > 0`; nothing assigns it.
- `settingsLoadRunner` argv is `["python3", <viewer-state.py>, "get-global-settings"]` (3 elements), guard `""`; `settingsSaveRunner` argv is `["python3", <viewer-state.py>, "set-global-settings", JSON.stringify({ notifyOnEscalation: value })]` (4 elements), no guard; `runSettingsRunner` argv is `["python3", <viewer-state.py>, "get-run-settings", <project>]`, guard set by `projectSwitched()` to the new project.
- The failed-save flash text is exactly `Notify on escalation could not be saved`.
- A project switch never changes `toasts`, `armedRoots`, `notifyOnEscalation`, `notifySaved`, `notifyTouched` or either notify runner.
- Out of scope (do not touch): rendering the project on `RunToast` (only its doc comment changes), the switch's UI with no project open, `RunsScreen.qml`, control / resume settings / logs (3.5).

## Review Focus

1. **A partial refresh (one root's entry only) while every root is armed** — the roots with no entry keep their arming, and the answering root alerts with its own name. Test in Task 1 (`test_a_partial_or_failed_reply_leaves_the_other_roots_arming_alone`).
2. **A whole-call failure (`ok:false` envelope) or garbage while armed** — `armedRoots` is not replaced (same object), so bindings see no change and nothing is disarmed. Test in Task 1 (same test as 1).
3. **A run with no id that is escalated in an armed root** — it never alerts and never breaks the reply. Test in Task 1 (same test as 1).
4. **The registry reordered so a run listed under two roots changes owner** — the new owner compares against its own previous list, so an already-escalated run is not replayed. Test in Task 1 (`test_a_run_listed_under_two_roots_alerts_once_under_the_first`).
5. **A global load reply from an earlier opening that lands after a reopening** — it is dropped (latest wins), so it cannot overwrite the newer read. Test in Task 3 (`test_the_global_switch_loads_on_each_opening_with_no_project`).

---

## File Structure

- Modify `core/stores/RunStore.qml` — `armedRoots` / derived `alertsArmed`; `alertsOf`; arming in `applyProjects`; trimming in `registryChanged`; `project` on toasts in `raiseAlerts`; `settingsLoadRunner` → global load in `startLive`; new `runSettingsRunner` + alias; `applyGlobalSettings` / `applyRunSettings`; `projectSwitched` stops touching the switch; `setNotifyOnEscalation` writes `set-global-settings` with no guard.
- Modify `ui/components/RunToast.qml:14` — the doc comment's toast shape only.
- Modify `docs/architecture.md` — line 86 (`alertsArmed` → `armedRoots`), the Alerts paragraph and the dispatch paragraph's `runSettings` clause.
- Test `tests/core/stores/tst_run_store.qml` — a new `// ---- alerts across projects (3.4)` block, the setting block rewritten, `settingsLoadRunner.current` → `runSettingsRunner.current` everywhere the old per-project read was replied to.
- Test `tests/ui/tst_runs_flow.qml:44`, `tests/ui/tst_runs_real_data.qml:49`, `tests/ui/tst_dispatch_flow.qml:69`, `tests/ui/tst_board_flow.qml:151` — one extra `runSettingsRunner.cancel()` line each.

## How to run the tests

`bash tests/run.sh <substring>` runs pytest, then every QML test whose path contains the substring, printing only `FAIL` lines and the `Totals` line per file, plus any `TypeError` / `ReferenceError` / `is not a function` line (which also fails the run). There is no per-function filter: read the `FAIL!  : StoresRunStore::<test name>` lines. Wrap long runs in `timeout`, e.g. `timeout 600 bash tests/run.sh tst_run_store`.

Fixture facts the tests rely on (all already in `tst_run_store.qml`): `rootA` = `"/home/u/my proj"` (name `"alpha"`), `rootB` = `"/home/u/b"` (`"beta"`), `rootC` = `"/home/u/c"` (`"proj"`). `entry(id, status, live, root)` builds one snapshot entry whose `milestone_id` is `"m-" + id` (so its toast title is `"m-<id>"`); `running(id)` is a running run, `dead(id)` a dead one (reason `"process died"`), `escalated(id)` an escalated one (reason `"escalated"`). `allReply(projects)`, `okEntry(root, runs)`, `failEntry(root, type, message)`, `reply(proc, text, code)`, `argv(proc)` (command joined by `|`), `ids(list)`, `toastIds(store)`, `registry(roots)`, `rootEntry(root)`, `make()`, `makeWithProject(root)`, `activeRoots(roots)`, `activeStore(root)`, `armedStore(entries)`, `dispatchSettings()`, `runSettings(notify)`, `tc.viewerCmd` = `"python3|/plugin/core/backend/projects/viewer-state.py|"`, `tc.notifyCmd` = `"python3|/plugin/core/backend/runs/notify.py|"`. `HelperRunner` (`core/stores/HelperRunner.qml`): `run(args)` stops the previous Process and creates a new one with `launchSeq` and `launchGuard`; a reply is applied only when its `launchSeq` is the newest and its `launchGuard` equals the runner's current `guard`; `cancel()` drops the in-flight one.

---

### Task 1: Per-root arming and the toast's project

**Files:**
- Modify: `core/stores/RunStore.qml:139-145` (alert state), `:350-355` (`startLive`), `:373` (`stopLive`), `:581` (`forgetLive`), `:893-1021` (`applyProjects` comment and body), `:1306-1318` (`raiseAlerts`)
- Modify: `ui/components/RunToast.qml:14`
- Test: `tests/core/stores/tst_run_store.qml` — new block inserted right after `test_a_project_switch_keeps_the_toasts_and_the_alerts_armed` (ends just before `// ---- alerts: the setting and the desktop notifications (S2 4.4)`, currently line 3482)

**Interfaces:**
- Consumes: `Runs.newAlerts(prevRuns, nextRuns)` → `[{id, title, state, reason}]`; `Runs.withProject(run, root, name)` → copy with `project: {root, name}`; `store.mergedRuns(byProject, usable)` → `{runs, owner}`; `store.hasKey(map, key)`; `store.copyMap(map)`.
- Produces: `property var armedRoots` (`{root: true}`, replaced never mutated); `readonly property bool alertsArmed`; `function alertsOf(prev, byProject, owner, okRoots, usable)` → alert list with `project` strings; toasts carry `project` (string). Test helpers `armedTwo(aRuns, bRuns)`, `armedKeys(store)`, `bothRoots()`, `answer(store, projects)` (used by Task 2).

- [ ] **Step 1: Write the failing tests**

Insert this block in `tests/core/stores/tst_run_store.qml` immediately before the line `  // ---- alerts: the setting and the desktop notifications (S2 4.4)`:

```qml
  // ---- alerts across projects (3.4)

  // The armed roots of `store`, sorted, comma-joined.
  function armedKeys(store) { return Object.keys(store.armedRoots).sort().join(",") }
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
    compare(store.alertsArmed, true)
    compare(store.toasts.length, 0, "and raises nothing")
    return store
  }

  // 1
  function test_an_escalation_in_another_project_raises_one_toast_with_its_project() {
    var store = armedTwo([running("a1")], [running("b1")]); if (!store) return
    compare(store.project, "")
    store.notifyOnEscalation = true
    answer(store, [okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1")])])
    compare(toastIds(store), "b1")
    compare(store.toasts[0].project, "beta")
    compare(store.toasts[0].title, "m-b1")
    compare(store.toasts[0].state, "escalated")
    compare(store.notifyRunners.length, 1, "one notification")
    compare(argv(store.notifyRunners[0].current), tc.notifyCmd + "m-b1|escalated", "its text does not change")
  }

  // 2
  function test_a_project_that_first_fails_or_joins_later_only_arms_on_its_first_good_entry() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")]),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(armedKeys(store), tc.rootA, "only A answered")
    answer(store, [okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1"), dead("b2")])])
    compare(store.toasts.length, 0, "B's first good entry only arms")
    compare(armedKeys(store), bothRoots())
    answer(store, [okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1"), dead("b2"), escalated("b3")])])
    compare(toastIds(store), "b3", "the entry after that compares normally")
    compare(store.toasts[0].project, "beta")
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
    compare(store.toasts.length, 0, "a failed entry raises nothing")
    compare(ids(store.runsByProject[tc.rootB]), "b1,b2", "B keeps its runs")
    compare(armedKeys(store), bothRoots(), "and stays armed")
    answer(store, [okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1"), escalated("b2")])])
    compare(toastIds(store), "b1", "the recovery compares against the kept runs: b2 is not replayed")
    compare(store.toasts[0].project, "beta")
  }

  // 4
  function test_an_am_missing_spell_disarms_every_project() {
    var store = armedTwo([running("a1")], [running("b1")]); if (!store) return
    answer(store, [failEntry(tc.rootA, "AmMissing", "am is not installed."), failEntry(tc.rootB, "AmMissing", "am is not installed.")])
    compare(armedKeys(store), "")
    compare(store.alertsArmed, false)
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), okEntry(tc.rootB, [escalated("b1")])])
    compare(store.toasts.length, 0, "the next good reply only arms")
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
    compare(store.toasts[0].project, "alpha")
    compare(store.notifyRunners.length, 1, "one notification")
    store.projectRoots = registry([tc.rootB, tc.rootA])
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [escalated("x")]), okEntry(tc.rootB, [escalated("x")])]), 0)
    compare(store.runs[0].project.root, tc.rootB, "B owns x now")
    compare(store.toasts.length, 1, "a new owner replays nothing")
    compare(store.notifyRunners.length, 1)
  }

  // Review Focus 1, 2 and 3
  function test_a_partial_or_failed_reply_leaves_the_other_roots_arming_alone() {
    // synthetic: a run without an id under B.
    var store = armedTwo([running("a1")], [running("b1"), entry("", "started", true)]); if (!store) return
    var armed = store.armedRoots
    store.refresh()
    reply(store.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "Usage", message: "usage" } }) + "\n", 2)
    verify(store.armedRoots === armed, "a whole-call failure leaves the arming alone")
    store.refresh()
    reply(store.snapshotRunner.current, "garbage\n", 1)
    verify(store.armedRoots === armed, "so does garbage")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [escalated("b1"), entry("", "escalated", false)])]), 0)
    compare(toastIds(store), "b1", "a run without an id never alerts")
    compare(store.toasts[0].project, "beta")
    compare(armedKeys(store), bothRoots(), "A, with no entry, stays armed")
    compare(ids(store.runsByProject[tc.rootA]), "a1")
  }

  // 7
  function test_a_project_switch_keeps_the_toasts_and_every_projects_arming() {
    var store = armedTwo([running("a1")], [running("b1")]); if (!store) return
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), okEntry(tc.rootB, [running("b1")])])
    compare(toastIds(store), "a1")
    compare(store.toasts[0].project, "alpha")
    var toasts = store.toasts
    var armed = store.armedRoots
    var targets = [tc.rootA, ""]
    for (var i = 0; i < targets.length; i++) {
      var label = "project " + JSON.stringify(targets[i])
      store.project = targets[i]
      verify(store.toasts === toasts, label + ": the toasts")
      verify(store.armedRoots === armed, label + ": the arming")
    }
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), okEntry(tc.rootB, [escalated("b1")])])
    compare(toastIds(store), "a1,b1", "the next escalation still alerts")
    compare(store.toasts[1].project, "beta")
  }

  // the closed panel (spec §2)
  function test_a_reply_while_the_panel_is_closed_raises_nothing_and_arms_nothing() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [running("b1")])]), 0)
    compare(armedKeys(store), "", "a closed panel never arms")
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), okEntry(tc.rootB, [escalated("b1")])])
    compare(store.toasts.length, 0)
    compare(armedKeys(store), "")
    compare(ids(store.runs), "a1,b1", "the runs are still applied")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_run_store`
Expected: FAIL lines for every new test above (`armedKeys` reads `Object.keys(undefined)` → `TypeError: Cannot convert undefined or null to object`, and `toasts[0].project` is `undefined`). Pre-existing tests still pass.

- [ ] **Step 3: Replace the alert state**

In `core/stores/RunStore.qml`, replace:

```qml
  // Alerts (S2 4.4): a toast for every run that newly needs a human while the
  // panel is open. `alertsArmed` says the current `runs` may be compared
  // against: the first good snapshot after an opening, a store change or an
  // am-missing spell only arms, so history is never replayed. `toasts` is
  // {key, id, title, state, reason, expiresMs}, oldest first, at most 3, and
  // is replaced, never changed in place.
  property bool alertsArmed: false
```

with:

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
```

- [ ] **Step 4: Every disarm empties `armedRoots`**

Run: `sed -i 's/store\.alertsArmed = false/store.armedRoots = {}/' core/stores/RunStore.qml`

This changes exactly four lines: `startLive`, `stopLive`, `forgetLive` and the AmMissing branch of `applyProjects`. Check with `grep -n "alertsArmed\|armedRoots = {}" core/stores/RunStore.qml`: four `armedRoots = {}` lines, plus the new property line and the two `alertsArmed` uses in `applyProjects` (`store.alertsArmed ? store.runs : null` and `store.alertsArmed = true`, both replaced in Step 6).

In the AmMissing branch, also replace the comment lines:

```qml
      // Comparing the next good snapshot against [] would alert every
      // escalated run again.
      store.armedRoots = {}
```

with:

```qml
      // Every root is disarmed: comparing its next good entry against []
      // would alert every escalated run again.
      store.armedRoots = {}
```

And replace `startLive`'s two comment lines so they read:

```qml
  // The panel opened: fetch now; the first good snapshot starts the watch and
  // arms every root that answers in it, and the stale clock counts from now.
```

- [ ] **Step 5: Add `alertsOf`**

Insert immediately before the line `  // ---- run controls (S2 4.1)` in `core/stores/RunStore.qml`:

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
      if (!store.hasKey(okRoots, root) || !store.hasKey(store.armedRoots, root)) continue
      var mine = byProject[root].filter(function(run) {
        return run !== null && typeof run === "object" && store.hasKey(owner, run.id) && owner[run.id] === root
      })
      var name = Runs.withProject({}, root, usable[i].name).project.name
      var found = Runs.newAlerts(store.hasKey(prev, root) ? prev[root] : [], mine)
      for (var j = 0; j < found.length; j++) {
        if (store.hasKey(raised, found[j].id)) continue
        raised[found[j].id] = true
        found[j].project = name
        out.push(found[j])
      }
    }
    return out
  }

```

- [ ] **Step 6: Arm per root in `applyProjects`**

In `applyProjects`, replace:

```qml
    var byProject = store.copyMap(store.runsByProject)
    var errors = store.copyMap(store.projectErrors)
    var anyOk = false
    var firstError = ""
```

with:

```qml
    var prev = store.runsByProject
    var byProject = store.copyMap(store.runsByProject)
    var errors = store.copyMap(store.projectErrors)
    var anyOk = false
    var okRoots = {}
    var firstError = ""
```

Replace:

```qml
      if (entry.ok === true) {
        anyOk = true
```

with:

```qml
      if (entry.ok === true) {
        anyOk = true
        okRoots[root] = true
```

Replace:

```qml
    // Compared before the runs are replaced; raised below only while open.
    var alerts = Runs.newAlerts(store.alertsArmed ? store.runs : null, merged.runs)
```

with:

```qml
    // Compared before the runs are replaced; raised below only while open.
    var alerts = store.active ? store.alertsOf(prev, byProject, merged.owner, okRoots, usable) : []
```

Replace:

```qml
      store.raiseAlerts(alerts)
      store.alertsArmed = true
    }
  }
```

with:

```qml
      store.raiseAlerts(alerts)
      var armed = store.copyMap(store.armedRoots)
      for (var ok in okRoots) armed[ok] = true
      store.armedRoots = armed
    }
  }
```

In the comment above `applyProjects`, replace `coverage are emptied and amStatus is "missing", disarming the alerts.` with `coverage are emptied and amStatus is "missing", and every root is disarmed.` and replace the last two comment lines:

```qml
  // again. With none, amStatus is "error" with the first failed entry's
  // sentence, and the alerts and `stale` stay as they are.
```

with:

```qml
  // again, the alerts of every armed root with an ok entry are raised
  // (alertsOf) and every root with an ok entry is armed. With none, amStatus
  // is "error" with the first failed entry's sentence, and armedRoots and
  // `stale` stay as they are. A failed entry, a root with no entry and a
  // closed panel never change armedRoots.
```

- [ ] **Step 7: The toast carries its project**

In `raiseAlerts`, replace:

```qml
      next.push({ key: toastState.nextKey, id: a.id, title: a.title, state: a.state, reason: a.reason,
                  expiresMs: Date.now() + store.toastMs })
```

with:

```qml
      next.push({ key: toastState.nextKey, id: a.id, title: a.title, state: a.state, reason: a.reason,
                  project: typeof a.project === "string" ? a.project : "", expiresMs: Date.now() + store.toastMs })
```

In `ui/components/RunToast.qml`, replace `// RunStore.toasts ({key, id, title, state, reason, expiresMs}, oldest first)` with `// RunStore.toasts ({key, id, title, state, reason, project, expiresMs}, oldest first)`. Nothing else in that file changes.

- [ ] **Step 8: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_run_store`
Expected: `Totals: N passed, 0 failed` for `tst_run_store.qml`, no `TypeError` lines. The S2 4.4 toast tests, the 3.1 failing-root / AmMissing tests and the 3.2 nudge alert test pass unchanged.

Then: `timeout 900 bash tests/run.sh`
Expected: every file `0 failed`, exit 0 (includes `tests/architecture` and `tests/ui`).

- [ ] **Step 9: Commit**

```bash
git add core/stores/RunStore.qml ui/components/RunToast.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): alerts are armed per project root and every toast names its project"
```

---

### Task 2: A root that leaves the registry loses its arming

**Files:**
- Modify: `core/stores/RunStore.qml` — `registryChanged()` and its comment (currently `:721-738`)
- Test: `tests/core/stores/tst_run_store.qml` — append to the `// ---- alerts across projects (3.4)` block, after `test_a_reply_while_the_panel_is_closed_raises_nothing_and_arms_nothing`

**Interfaces:**
- Consumes: `armedRoots` (Task 1), test helpers `armedTwo`, `armedKeys`, `bothRoots` (Task 1), `store.usableRoots()` → `[{root, name}]`.
- Produces: `registryChanged()` replaces `armedRoots` with the still-usable armed keys only when one went.

- [ ] **Step 1: Write the failing test**

Append to the 3.4 block:

```qml
  // 6
  function test_a_root_that_leaves_the_registry_loses_its_arming() {
    var store = armedTwo([running("a1")], [running("b1")]); if (!store) return
    store.projectRoots = registry([tc.rootA])
    compare(armedKeys(store), tc.rootA, "B left: its arming goes at once")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")])]), 0)
    store.projectRoots = registry([tc.rootA, tc.rootB])
    compare(armedKeys(store), tc.rootA, "coming back does not re-arm")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1")])]), 0)
    compare(store.toasts.length, 0, "its next good entry only arms")
    compare(armedKeys(store), bothRoots())
    var armed = store.armedRoots
    store.projectRoots = [{ root: tc.rootA, name: "renamed" }, rootEntry(tc.rootB)]
    verify(store.armedRoots === armed, "no root went: the map is not replaced")
    store.projectRoots = []
    compare(armedKeys(store), "", "an empty registry arms nothing")
  }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash tests/run.sh tst_run_store`
Expected: `FAIL!  : StoresRunStore::test_a_root_that_leaves_the_registry_loses_its_arming() ... B left: its arming goes at once` (actual still lists both roots).

- [ ] **Step 3: Trim `armedRoots` in `registryChanged`**

Replace the whole `registryChanged` function and its comment:

```qml
  // The registry changed. First the roots no longer usable lose their runs
  // and their errors, and `runs` is merged again in the new order with the
  // new names; no alert is raised. Then every usable root is snapshotted.
  function registryChanged() {
    var usable = store.usableRoots()
    var errors = {}
    for (var i = 0; i < usable.length; i++) {
      var root = usable[i].root
      if (store.hasKey(store.projectErrors, root)) errors[root] = store.projectErrors[root]
    }
    var byProject = store.taggedByProject(store.runsByProject, usable)
    store.runsByProject = byProject
    store.projectErrors = errors
    store.runs = store.mergedRuns(byProject, usable).runs
    store.refresh()
  }
```

with:

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
      if (store.hasKey(store.projectErrors, root)) errors[root] = store.projectErrors[root]
      if (store.hasKey(store.armedRoots, root)) armed[root] = true
    }
    var byProject = store.taggedByProject(store.runsByProject, usable)
    store.runsByProject = byProject
    store.projectErrors = errors
    if (Object.keys(armed).length !== Object.keys(store.armedRoots).length) store.armedRoots = armed
    store.runs = store.mergedRuns(byProject, usable).runs
    store.refresh()
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_run_store`
Expected: `0 failed` for `tst_run_store.qml`, no `TypeError` lines.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): a root that leaves the registry loses its alert arming"
```

---

### Task 3: The global load on opening and `runSettingsRunner` per project

**Files:**
- Modify: `core/stores/RunStore.qml` — the notify / `runSettings` property comments (`:146-158`), the alias block (`:204`), `startLive()`, `projectSwitched()` (`:637-657`), `applyRunSettings` (`:1362-1373`), the `settingsLoadRunner` `HelperRunner` (`:1745-1752`)
- Modify: `tests/ui/tst_runs_flow.qml:44`, `tests/ui/tst_runs_real_data.qml:49`, `tests/ui/tst_dispatch_flow.qml:69`, `tests/ui/tst_board_flow.qml:151`
- Test: `tests/core/stores/tst_run_store.qml` — the setting block (`// ---- alerts: the setting and the desktop notifications (S2 4.4)`), every `settingsLoadRunner.current` reply

**Interfaces:**
- Consumes: `store.parseEnvelope(text)` → object or `null`; `HelperRunner.run(args)`, `.guard`, `.seq`, `.current`, `.cancel()`.
- Produces: `readonly property alias runSettingsRunner`; `function applyGlobalSettings(stdout, exitCode)`; `function applyRunSettings(stdout, exitCode)` (sets only `runSettings`); `startLive()` launches `settingsLoadRunner.run(["get-global-settings"])` and clears `notifyTouched`. Task 4 changes that clear to `if (!settingsSaveRunner.busy)`.

- [ ] **Step 1: Move every per-project settings reply to `runSettingsRunner`**

Run: `sed -i 's/settingsLoadRunner\.current/runSettingsRunner.current/g' tests/core/stores/tst_run_store.qml`

This moves `test_a_project_switch_leaves_the_run_list_and_the_live_state_alone`'s final assertion (`argv(store.runSettingsRunner.current) ... "get-run-settings|" + tc.rootB`), `test_run_settings_kept_even_after_notify_touched`, `test_run_settings_follow_the_project` and every dispatch / resume test reply to the new runner. Their assertions do not change.

- [ ] **Step 2: Rewrite the load tests of the setting block**

In `tests/core/stores/tst_run_store.qml`, delete these three functions together with the comment line above each (`// 10 (the setting half)`, `// 11`, `// Review Focus 3`): `test_a_project_switch_resets_the_switch_and_loads_the_new_projects_setting`, `test_the_load_reply_sets_the_switch_and_a_garbled_one_leaves_it_off`, `test_a_late_load_reply_for_the_old_project_is_dropped`. In their place (right after `function runSettings(notify) { ... }`) insert:

```qml
  // 8 and Review Focus 5
  function test_the_global_switch_loads_on_each_opening_with_no_project() {
    var idle = make(); if (!idle) return
    verify(!idle.settingsLoadRunner.current, "a closed panel loads nothing")
    idle.project = tc.rootA
    verify(!idle.settingsLoadRunner.current, "a project switch launches no global load")

    var store = make(); if (!store) return
    store.active = true
    var load = store.settingsLoadRunner.current
    verify(load, "opening the panel loads the switch, with no project and no registry")
    compare(argv(load), tc.viewerCmd + "get-global-settings")
    compare(load.command.length, 3)
    compare(load.launchGuard, "")
    reply(load, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(store.notifyOnEscalation, true)
    compare(store.notifySaved, true)
    store.project = tc.rootB
    compare(store.notifyOnEscalation, true, "a project switch leaves the switch alone")
    compare(store.notifySaved, true)
    compare(store.notifyTouched, false)
    var seq = store.settingsLoadRunner.seq
    store.project = ""
    compare(store.settingsLoadRunner.seq, seq, "and launches no global load")
    store.active = false
    store.active = true
    compare(store.settingsLoadRunner.seq, seq + 1, "each opening loads once")
    reply(store.settingsLoadRunner.current, "Traceback: boom\n", 1)
    compare(store.notifyOnEscalation, false, "an unreadable reply leaves it off")
    compare(store.notifySaved, false)
    store.active = false
    store.active = true
    reply(store.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: "yes" }) + "\n", 0)
    compare(store.notifyOnEscalation, false, "only a real true turns it on")
    store.active = false
    store.active = true
    reply(store.settingsLoadRunner.current, "{}\n", 0)
    compare(store.notifyOnEscalation, false)
    store.active = false
    store.active = true
    var late = store.settingsLoadRunner.current
    store.active = false
    reply(late, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(store.notifyOnEscalation, true, "a reply after the panel closed still lands")
    store.active = true
    var older = store.settingsLoadRunner.current
    store.active = false
    store.active = true
    reply(older, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(store.notifyOnEscalation, true, "an earlier opening's reply is dropped")
    reply(store.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(store.notifyOnEscalation, false, "the newest opening's reply lands")
  }

  // 12
  function test_run_settings_load_per_project_and_never_set_the_switch() {
    var store = makeWithProject(rootA); if (!store) return
    var loadA = store.runSettingsRunner.current
    verify(loadA, "selecting a project loads its run settings")
    compare(argv(loadA), tc.viewerCmd + "get-run-settings|/home/u/my proj")
    compare(loadA.command.length, 4)
    compare(loadA.launchGuard, "/home/u/my proj")
    verify(!store.settingsLoadRunner.current, "and no global load")
    reply(loadA, runSettings(true), 0)
    compare(store.runSettings.notifyOnEscalation, true, "the object is kept as it was read")
    compare(store.notifyOnEscalation, false, "a stored per-project value is never the switch")
    compare(store.notifySaved, false)
    store.project = rootB
    compare(Object.keys(store.runSettings).length, 0, "a project switch forgets A's settings")
    var loadB = store.runSettingsRunner.current
    verify(loadB !== loadA, "a new load")
    compare(argv(loadB), tc.viewerCmd + "get-run-settings|/home/u/b")
    compare(loadB.launchGuard, "/home/u/b", "the launch is guarded by the NEW project")
    var seq = store.runSettingsRunner.seq
    store.project = ""
    compare(store.runSettingsRunner.seq, seq, "no project: nothing is loaded")
    compare(store.runSettingsRunner.guard, "")

    var other = makeWithProject(rootA); if (!other) return
    var lateA = other.runSettingsRunner.current
    other.project = rootB
    reply(lateA, dispatchSettings(), 0)
    compare(Object.keys(other.runSettings).length, 0, "a late reply for A is dropped")
    compare(other.notifyOnEscalation, false)
  }
```

Then replace the function `test_a_load_reply_after_the_user_toggled_is_ignored` (keep its `// 14` comment line) with:

```qml
  function test_a_load_reply_after_the_user_toggled_is_ignored() {
    var store = makeWithProject(rootA); if (!store) return
    store.active = true
    var load = store.settingsLoadRunner.current
    compare(argv(load), tc.viewerCmd + "get-global-settings")
    store.setNotifyOnEscalation(true)
    reply(load, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(store.notifyOnEscalation, true)
    compare(store.notifyTouched, true)
  }
```

- [ ] **Step 3: The UI setups cancel the new runner too**

In each of `tests/ui/tst_runs_flow.qml`, `tests/ui/tst_runs_real_data.qml`, `tests/ui/tst_dispatch_flow.qml` and `tests/ui/tst_board_flow.qml`, directly after the line `    p.app.runs.settingsLoadRunner.cancel()` add:

```qml
    p.app.runs.runSettingsRunner.cancel()
```

(one line per file; in `tst_runs_flow.qml` and `tst_runs_real_data.qml` it sits right before `p.app.runs.runs = [...]` / `return p`; in the other two right before `p.app.runs.runSettings = { verify: ["uv run pytest"] }`).

- [ ] **Step 4: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_run_store`
Expected: FAIL / `TypeError: Cannot read property 'current' of undefined` for every test that reads `runSettingsRunner`, and `test_the_global_switch_loads_on_each_opening_with_no_project` fails at `a project switch launches no global load`.

- [ ] **Step 5: Split the settings runners in `RunStore.qml`**

Replace the notify / `runSettings` property block:

```qml
  // "Notify on escalation", per project and off by default: the switch's
  // value, the last value read from or written to viewer-state.py, and
  // whether the user changed it since the project was selected (a late load
  // reply then changes nothing).
  property bool notifyOnEscalation: false
  property bool notifySaved: false
  property bool notifyTouched: false
  // The current project's last get-run-settings object, as it was read: {}
  // until its reply, when the reply is unreadable, and after a project switch.
  // The dispatch form starts from it.
  property var runSettings: ({})
```

with:

```qml
  // "Notify on escalation", viewer-wide and off until read: the switch's
  // value, the last value read from or written to viewer-state.py's global
  // settings, and whether the user changed it since this opening's load was
  // launched (a late load reply then changes nothing). A project switch
  // never changes them.
  property bool notifyOnEscalation: false
  property bool notifySaved: false
  property bool notifyTouched: false
  // The open project's last get-run-settings object (runSettingsRunner), as
  // it was read: {} until its reply, when the reply is unreadable, and after
  // a project switch. The dispatch form starts from it; its
  // notifyOnEscalation is never read.
  property var runSettings: ({})
```

After the line `  readonly property alias settingsSaveRunner: settingsSaveRunner` add:

```qml
  readonly property alias runSettingsRunner: runSettingsRunner
```

Replace `startLive()` and its comment with:

```qml
  // The panel opened: fetch now and read the notify switch (get-global-settings,
  // notifyTouched cleared first); the first good snapshot starts the watch and
  // arms every root that answers in it, and the stale clock counts from now.
  function startLive() {
    store.watchTried = false
    store.armedRoots = {}
    store.notifyTouched = false
    settingsLoadRunner.run(["get-global-settings"])
    store.restartStale()
    store.refresh()
  }
```

Replace `projectSwitched()` and its comment with:

```qml
  // Another project was opened, or none. The run list, the selection, the
  // logs, the watch, the coverage, the requests, the alerts, the toasts and
  // the notify switch belong to every registered project and stay, and no
  // snapshot is launched. Reset: the run settings (loaded for the new project
  // on runSettingsRunner), the dispatch, the cancel dialog, the control error
  // and the footer flash.
  function projectSwitched() {
    store.runSettings = {}
    // The dispatch is the old project's, even mid-start: a start already
    // launched still runs, and its reply is no longer this dispatch's.
    store.resetDispatch()
    store.dismissControlError()
    store.closeCancel()
    store.flash("")
    runSettingsRunner.guard = store.project
    if (store.project !== "") runSettingsRunner.run(["get-run-settings", store.project])
  }
```

Replace `applyRunSettings` and its comment:

```qml
  // get-run-settings: one bare object, kept whole as runSettings ({} when
  // unreadable) on every reply. Only a real true turns the switch on; an
  // unreadable reply leaves it off. Too late for the switch once the user
  // changed it.
  function applyRunSettings(stdout, exitCode) {
    var settings = store.parseEnvelope(stdout)
    store.runSettings = settings !== null ? settings : {}
    if (store.notifyTouched) return
    var on = settings !== null && settings.notifyOnEscalation === true
    store.notifyOnEscalation = on
    store.notifySaved = on
  }
```

with:

```qml
  // get-global-settings: only a real true turns the switch on; an unreadable
  // reply leaves it off. Too late once the user changed the switch in this
  // opening.
  function applyGlobalSettings(stdout, exitCode) {
    if (store.notifyTouched) return
    var settings = store.parseEnvelope(stdout)
    var on = settings !== null && settings.notifyOnEscalation === true
    store.notifyOnEscalation = on
    store.notifySaved = on
  }

  // get-run-settings: one bare object, kept whole as runSettings ({} when
  // unreadable) on every reply. Never touches the notify switch.
  function applyRunSettings(stdout, exitCode) {
    var settings = store.parseEnvelope(stdout)
    store.runSettings = settings !== null ? settings : {}
  }
```

Replace the `settingsLoadRunner` runner:

```qml
  // get-run-settings on a project switch. Its guard is set by projectSwitched()
  // itself rather than bound to `project`: projectSwitched() runs from
  // onProjectChanged, before a binding here is sure to have followed the
  // project, and this launch must carry the NEW project.
  HelperRunner {
    id: settingsLoadRunner
    script: store.backendDir + "projects/viewer-state.py"
    onFinished: function(stdout, exitCode) { store.applyRunSettings(stdout, exitCode) }
  }
```

with:

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
  // set by projectSwitched() itself rather than bound to `project`:
  // projectSwitched() runs from onProjectChanged, before a binding here is
  // sure to have followed the project, and this launch must carry the NEW
  // project.
  HelperRunner {
    id: runSettingsRunner
    script: store.backendDir + "projects/viewer-state.py"
    onFinished: function(stdout, exitCode) { store.applyRunSettings(stdout, exitCode) }
  }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_run_store`
Expected: `0 failed` for `tst_run_store.qml`, no `TypeError` lines. (`test_the_switch_saves_at_once_and_a_failed_save_puts_it_back`, `test_a_save_reply_for_a_project_the_user_left_changes_nothing` and `test_without_a_project_the_switch_does_nothing` still pass: the save side is unchanged until Task 4.)

Then: `timeout 900 bash tests/run.sh`
Expected: every file `0 failed`, exit 0.

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml tests/ui/tst_runs_flow.qml tests/ui/tst_runs_real_data.qml tests/ui/tst_dispatch_flow.qml tests/ui/tst_board_flow.qml
git commit -m "feat(run-store): the notify switch loads from the global settings on each opening; runSettings has its own runner"
```

---

### Task 4: The global save, with no project, and the docs

**Files:**
- Modify: `core/stores/RunStore.qml` — `startLive()` (the `notifyTouched` line), `setNotifyOnEscalation` (`:1349-1360`), `notifySaveReplied`'s comment, the `settingsSaveRunner` `HelperRunner`
- Modify: `docs/architecture.md` — line 86 and the Alerts / dispatch sentences
- Test: `tests/core/stores/tst_run_store.qml` — the setting block's save tests

**Interfaces:**
- Consumes: `settingsSaveRunner.busy`, `.sent`; `store.notifySaveReplied(stdout, exitCode, sent)` (unchanged body); `store.flash(text)`.
- Produces: `setNotifyOnEscalation(on)` → always `true`, launches `["set-global-settings", JSON.stringify({ notifyOnEscalation: value })]`.

- [ ] **Step 1: Rewrite the save tests**

In `tests/core/stores/tst_run_store.qml`, replace the function `test_the_switch_saves_at_once_and_a_failed_save_puts_it_back` (keep its `// 13` comment line) with:

```qml
  function test_the_switch_saves_globally_and_a_failed_save_puts_it_back() {
    var store = make(); if (!store) return
    compare(store.notifyOnEscalation, false)
    compare(store.notifySaved, false)
    compare(store.notifyTouched, false)
    compare(store.notifyRunners.length, 0)
    compare(store.setNotifyOnEscalation(true), true, "no project and no registry: it still works")
    compare(store.notifyOnEscalation, true, "the switch flips at once")
    compare(store.notifyTouched, true)
    var save = store.settingsSaveRunner.current
    verify(save, "a save was launched")
    compare(save.command.length, 4)
    compare(argv(save), tc.viewerCmd + 'set-global-settings|{"notifyOnEscalation":true}')
    compare(save.launchGuard, "")
    verify(!store.settingsLoadRunner.current, "a closed panel loads nothing")
    reply(save, JSON.stringify({ ok: true }) + "\n", 0)
    compare(store.notifySaved, true)
    compare(store.flashText, "")
    compare(store.setNotifyOnEscalation(false), true)
    compare(store.notifyOnEscalation, false)
    compare(argv(store.settingsSaveRunner.current), tc.viewerCmd + 'set-global-settings|{"notifyOnEscalation":false}')
    reply(store.settingsSaveRunner.current, JSON.stringify({ ok: false, error: "x" }) + "\n", 1)
    compare(store.notifyOnEscalation, true, "back to the value last saved")
    compare(store.notifySaved, true)
    compare(store.flashText, "Notify on escalation could not be saved")
    store.flash("")
    store.setNotifyOnEscalation(false)
    reply(store.settingsSaveRunner.current, "garbage\n", 1)
    compare(store.notifyOnEscalation, true, "an unreadable reply is a failure too")
    compare(store.flashText, "Notify on escalation could not be saved")
  }
```

Replace the function `test_a_save_reply_for_a_project_the_user_left_changes_nothing` and its `// Review Focus 4` comment line with:

```qml
  // 10
  function test_a_save_reply_survives_a_project_switch() {
    var store = makeWithProject(rootA); if (!store) return
    store.setNotifyOnEscalation(true)
    var save = store.settingsSaveRunner.current
    store.project = rootB
    compare(store.notifyOnEscalation, true, "the switch is viewer-wide")
    compare(store.notifyTouched, true)
    reply(save, JSON.stringify({ ok: false, error: "x" }) + "\n", 1)
    compare(store.notifyOnEscalation, false, "rolled back to the value last saved")
    compare(store.notifySaved, false)
    compare(store.flashText, "Notify on escalation could not be saved")
    store.flash("")
    store.setNotifyOnEscalation(true)
    var second = store.settingsSaveRunner.current
    store.project = ""
    reply(second, JSON.stringify({ ok: true }) + "\n", 0)
    compare(store.notifySaved, true, "an ok reply after a switch is applied")
    compare(store.notifyOnEscalation, true)
  }

  // 11
  function test_a_save_in_flight_survives_a_reopening() {
    var store = make(); if (!store) return
    store.active = true
    reply(store.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    store.setNotifyOnEscalation(true)
    var save = store.settingsSaveRunner.current
    store.active = false
    store.active = true
    compare(store.notifyTouched, true, "a save is in flight: the touch stays")
    reply(store.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(store.notifyOnEscalation, true, "the new load cannot undo the user's choice")
    reply(save, JSON.stringify({ ok: true }) + "\n", 0)
    compare(store.notifySaved, true, "the save reply settles notifySaved")
    store.active = false
    store.active = true
    compare(store.notifyTouched, false, "no save in flight: the next opening reads again")
    reply(store.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(store.notifyOnEscalation, false)
    compare(store.notifySaved, false)
  }
```

Delete the function `test_without_a_project_the_switch_does_nothing` and its `// 15` comment line (its contract is reversed and covered by `test_the_switch_saves_globally_and_a_failed_save_puts_it_back`).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_run_store`
Expected: FAIL for `test_the_switch_saves_globally_and_a_failed_save_puts_it_back` (`setNotifyOnEscalation` returns `false` with no project), `test_a_save_reply_survives_a_project_switch` (`the switch is viewer-wide` passes since Task 3, then the guard drops the reply, so `rolled back to the value last saved` fails) and `test_a_save_in_flight_survives_a_reopening` (`setNotifyOnEscalation` refused with no project, `the new load cannot undo the user's choice` fails).

- [ ] **Step 3: The save goes global**

Replace `startLive()` and its comment (as Task 3 left them) with:

```qml
  // The panel opened: fetch now and read the notify switch (get-global-settings;
  // notifyTouched is cleared first unless a save is in flight); the first good
  // snapshot starts the watch and arms every root that answers in it, and the
  // stale clock counts from now.
  function startLive() {
    store.watchTried = false
    store.armedRoots = {}
    if (!settingsSaveRunner.busy) store.notifyTouched = false
    settingsLoadRunner.run(["get-global-settings"])
    store.restartStale()
    store.refresh()
  }
```

Replace `setNotifyOnEscalation` and its comment:

```qml
  // The switch changed: shown at once, written in the background. Refused
  // (false, nothing changes) without a project.
  function setNotifyOnEscalation(on) {
    if (store.project === "") return false
    var value = !!on
    store.notifyOnEscalation = value
    store.notifyTouched = true
    settingsSaveRunner.sent = value
    settingsSaveRunner.run(["set-run-settings", store.project, JSON.stringify({ notifyOnEscalation: value })])
    return true
  }
```

with:

```qml
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
```

In the comment above `notifySaveReplied`, replace `// set-run-settings: {"ok": true} means` with `// set-global-settings: {"ok": true} means`.

Replace the `settingsSaveRunner` runner:

```qml
  // set-run-settings on a change of the switch; latest wins. Bound to the
  // project like the logs: it is launched by a click, long after the binding
  // followed the project. `sent` is the value the latest launch writes.
  HelperRunner {
    id: settingsSaveRunner
    property bool sent: false
    script: store.backendDir + "projects/viewer-state.py"
    guard: store.project
    onFinished: function(stdout, exitCode) { store.notifySaveReplied(stdout, exitCode, settingsSaveRunner.sent) }
  }
```

with:

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

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_run_store`
Expected: `0 failed` for `tst_run_store.qml`, no `TypeError` lines.

- [ ] **Step 5: Update `docs/architecture.md`**

Make these exact replacements (each old text occurs once; use the Edit tool):

1. In the "Starting over" sentence (line 86): replace `` the run reads in flight, `runs` and `alertsArmed`, then takes one list snapshot`` with `` the run reads in flight, `runs` and `armedRoots`, then takes one list snapshot``.

2. In the Alerts paragraph, replace:

```
Alerts (S2 4.4): while `active`, every good list snapshot and every applied run read is compared with the runs before it through `Runs.newAlerts`, and each run that newly turned escalated or dead gets a toast in `toasts` (`{key, id, title, state, reason, expiresMs}`, oldest first, at most 3, one per run; `key` only grows, so a stale Dismiss never removes a newer toast). `alertsArmed` says the current `runs` may be compared against: the first good list snapshot after an opening, a project switch, a start-over or an `AmMissing` reply only arms, so reopening the panel never replays history, and a snapshot that lands after the panel closed raises nothing.
```

with:

```
Alerts (S2 4.4): while `active`, every good list snapshot compares each armed root's ok entry with that root's runs before it through `Runs.newAlerts` (only the runs the root owns in the merged `runs`, so a run listed under two roots alerts once, under the first), and each run of any registered project that newly turned escalated or dead gets a toast in `toasts` (`{key, id, title, state, reason, project, expiresMs}`, `project` the project's name, oldest first, at most 3, one per run; `key` only grows, so a stale Dismiss never removes a newer toast). `armedRoots` (`{root: true}`, replaced, never changed in place) holds the roots whose runs may be compared against, and `alertsArmed` says some root is: a root's first ok entry after an opening, a start-over, an `AmMissing` spell (every matched entry `AmMissing`, which disarms every root) or its return to the registry only arms it, so reopening the panel never replays history; a failed entry leaves its root's arming alone, a root that leaves the registry loses it, a project switch neither disarms nor empties `toasts`, and a snapshot that lands after the panel closed raises nothing and arms nothing.
```

3. Replace `Closing the panel and a project switch empty `toasts`.` with `Closing the panel empties `toasts`.`

4. Replace:

```
"Notify on escalation" is per project and off by default: a project switch resets `notifyOnEscalation` and reads `viewer-state.py get-run-settings` on `settingsLoadRunner` (its guard is set by `projectSwitched()` itself, so the launch carries the new project); `setNotifyOnEscalation(on)` flips it at once and writes `set-run-settings ROOT {"notifyOnEscalation": …}` on `settingsSaveRunner` (latest wins); a failed save puts the switch back to `notifySaved` and flashes `Notify on escalation could not be saved`, and a load reply that lands after the user changed the switch (`notifyTouched`) is ignored.
```

with:

```
"Notify on escalation" is viewer-wide and off until read: each opening clears `notifyTouched` (unless a save is in flight) and reads `viewer-state.py get-global-settings` on `settingsLoadRunner` (no guard, latest wins; a reply after the panel closed still lands; only a real `true` turns it on); `setNotifyOnEscalation(on)` works with or without a project, flips it at once and writes `set-global-settings {"notifyOnEscalation": …}` on `settingsSaveRunner` (latest wins, no guard, so a project switch never drops its reply); a failed save puts the switch back to `notifySaved` and flashes `Notify on escalation could not be saved`, a load reply that lands after the user changed the switch in this opening (`notifyTouched`) is ignored, and a project switch never changes the switch.
```

5. In the dispatch paragraph, replace `` `runSettings` -- the current project's whole `get-run-settings` reply, `{}` until it lands and after a project switch --`` with `` `runSettings` -- the open project's whole `get-run-settings` reply, read on `runSettingsRunner` by every project switch (guarded by the new project) and never read for the notify switch, `{}` until it lands and after a project switch --``.

Check: `grep -n "alertsArmed\|per project and off\|project switch empty\|set-run-settings ROOT" docs/architecture.md` prints only the `alertsArmed says some root is` occurrence inside the new Alerts text.

- [ ] **Step 6: Full verification**

Run: `timeout 900 bash tests/run.sh`
Expected: pytest passes, every QML file prints `0 failed`, no `TypeError` / `ReferenceError` lines, exit status 0 (includes `tests/architecture`, `tests/ui/tst_runs_flow.qml` test 29 which saves the switch with a project open).

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml docs/architecture.md
git commit -m "feat(run-store): the notify switch saves to the global settings with or without a project"
```

---

## Self-review against the spec

- §1 arming state (`armedRoots`, derived `alertsArmed`, disarms in `startLive` / `stopLive` / `forgetLive` / AmMissing): Task 1 Steps 3-4. `registryChanged` trimming: Task 2.
- §2 `applyProjects` (prev before replacement, registry order, owner filter, once per id, project name, active-only arming, failed / missing entries unchanged, `!anyOk` unchanged): Task 1 Steps 5-6; tests 1-5, 7 and Review Focus 1-4 in Task 1, closed-panel test in Task 1.
- §3 toasts with `project`, `stopLive` empties, project switch keeps, notification text unchanged, RunToast comment: Task 1 Step 7; tests 1, 5, 7.
- §4 global switch load (Task 3) and save (Task 4); tests 8-11.
- §5 `runSettingsRunner`: Task 3; test 12; dispatch tests moved by the Task 3 Step 1 `sed`.
- §6 UI setups: Task 3 Step 3.
- §7 docs: Task 4 Step 5.
- Error paths table: global garbage / `{}` / `"yes"` (Task 3 test 8); load after touch (Task 3); reopen with save in flight (Task 4 test 11); save failure / garbage (Task 4 test 9); save reply after switch (Task 4 test 10); no project no registry (Task 4 test 9); A ok B failed armed (Task 1 test 3); first reply A ok B failed (Task 1 test 2); duplicate run (Task 1 test 5); all AmMissing and AmMissing beside ok (Task 1 test 4); reply while closed (Task 1); registry drop and re-add (Task 2 test 6).
<!-- task-pipeline: validated -->
