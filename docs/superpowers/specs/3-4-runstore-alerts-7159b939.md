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
