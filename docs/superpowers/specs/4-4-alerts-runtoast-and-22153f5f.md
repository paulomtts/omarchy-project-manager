# 4.4 Alerts: RunToast and the desktop notification setting (card 22153f5f)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-controls-design.md` (S2,
"the parent" below): "Alerts" (lines 109-136), "Testing" (line 160, "toast Open
navigates"), "Open questions" (lines 165-167). Parent story f03629a7 ("Control
store and UI"). Blocked by 4.3 (b4bc1521, spec
`4-3-cancel-confirmation-b4bc1521.md`), which is done on this branch.

This card makes an alert visible: a toast in the panel for every run that newly
needs a human, and, when the user turned it on for the project, a desktop
notification. The alert decision itself (`Runs.newAlerts`) and the two backend
helpers it needs already exist; this card wires them up.

## Starting point

- `core/domain/runs.js` `newAlerts(prevRuns, nextRuns)` (line 756) →
  `[{id, title, state, reason}]`, one per run in `nextRuns` (in its order) that
  is now `escalated` or `dead` and was not in that same state in `prevRuns`. A
  non-array `prevRuns` (the store's `null`, "no previous snapshot") gives `[]`.
  `title` is `Runs.runTitle(run)` (the milestone, else the short id, never
  `""`); `reason` is `escalationReason(run)` for an escalated run (never `""`)
  and `"process died"` for a dead one. Tested in `tests/core/domain/tst_runs.qml`
  lines 1337-1450. Keeping the previous snapshot, and resetting it to `null`, is
  the store's job (comment at line 726).
- `core/backend/runs/notify.py TITLE BODY` runs `notify-send -- TITLE BODY` and
  prints one JSON line on every path; `{"ok": true, "sent": false}` when
  `notify-send` is not on PATH (parent line 121-122, "does nothing if
  notify-send is missing", is therefore already true). It reads no settings:
  "whether to alert at all is the caller's call". Tested in
  `tests/core/backend/runs/test_notify.py`.
- `core/backend/projects/viewer-state.py`:
  - `get-run-settings ROOT` prints one bare object (not an envelope)
    `{"verify": [...], "allowNoVerification": bool, "notifyOnEscalation": bool}`;
    `notifyOnEscalation` defaults to `false` (`RUN_SETTINGS_DEFAULTS`, line 32);
    it never fails.
  - `set-run-settings ROOT JSON` merges a partial object into the project's
    entry and prints `{"ok": true}` (exit 0), or `{"ok": false, "error": "…"}`
    (exit 1 on a write error, exit 2 on a bad update).
  - Settings are **per project root**, so "Notify on escalation" is a
    per-project setting (parent line 119-120, "the plugin's per-viewer state").
- `core/stores/RunStore.qml`:
  - `applySnapshot(stdout, exitCode)` (line 395): an `ok:true` envelope builds
    `out` and assigns `store.runs = out` (line 405); an `AmMissing` envelope
    sets `runs = []` (line 428); any other failure keeps `runs`.
  - `active` (App binds it to `app.panelOpen`, `App.qml` line 109);
    `startLive()` (line 123) on activation, `stopLive()` (line 131) on close,
    `projectSwitched()` (line 228) on every project change (hung off the
    snapshot runner's guard, line 716).
  - Pattern to follow: `checkWaiting(nowMs)` + `pendingTimer` (lines 637, 770:
    a function that takes the clock, and a timer that runs only while `active`
    and there is something to time); `controlC` (line 812: one `HelperRunner`
    per request, dropped when it finishes); `flash(text)` (line 662).
  - `HelperRunner` (`core/stores/HelperRunner.qml`) is latest-wins: `run()`
    stops the previous launch. Two notifications through one runner would kill
    each other, hence one runner per notification (D5).
- `ui/Navigator.qml` `openRun(id, from)` (line 330) refuses an id that is not in
  `app.runs.runs`. With `from` other than `"entry"` it pushes a return slot from
  the *current* cursor and scroll and sets `runReturnMode` `"runs"`, so Back
  goes through `restoreRunsList()`. `showSection(name)` (line 168) refuses
  while a modal is open and resets the search.
- `ui/Shortcuts.qml`:
  - `closeRequested()` (line 39) is the Escape chain for the key catcher (views
    `run`, `entry`, `document`, `memory`, `issue`, …): modals, then the
    dropdown, then Back, else close the panel.
  - `handleSearchKey(event)` (line 95): Escape in the search field (the focus
    on Board, Runs and the other lists) clears a non-empty search, else closes
    the panel. It does not go through `closeRequested()`.
  - The ORDER of guards in this file is load bearing (header, lines 7-9).
- `ui/Panel.qml`: the dialogs are mounted after the screen column (lines
  600-703); `ModalCard` (the base of every dialog) has `z: 100`. Panel is one
  of the three `ui/` files allowed to touch the stores (docs/architecture.md
  line 15).
- `ui/components/runGlyphs.js`: `glyphOf("escalated")` is `‼`,
  `glyphOf("dead")` is `✖` — plain BMP characters, not Nerd Font code points,
  so `tests/architecture/test_icon_glyphs.py` has nothing to check for them.
- `ToggleSwitch` (shell `qs.Ui`; stub `tests/stubs/qs/Ui/ToggleSwitch.qml`:
  `checked`, `signal toggled()`) is used as in `vendor/canvas/CanvasControls.qml`
  line 41: `checked` bound, `onToggled` flips the value in the owner.
- There is no settings screen anywhere in the panel.

## Scope

In scope:

- `core/stores/RunStore.qml`: the alert baseline, the toast list and its
  expiry, the notify launches, and the "Notify on escalation" setting's load
  and save (D1-D6).
- `ui/components/RunToast.qml` (new): renders the toast stack, emits Open and
  Dismiss (D7).
- `ui/Panel.qml`: mounts `RunToast` bottom right and wires Open / Dismiss (D8).
- `ui/Shortcuts.qml`: Escape dismisses the toasts (D9).
- `ui/screens/RunsScreen.qml`: the "Notify on escalation" switch (D10).
- `docs/architecture.md`: the `RunStore` paragraph (line 95), the components
  list (lines ~143-145: add `RunToast`), the `Shortcuts.qml` sentence (lines
  97-103), the run screens paragraph (line 157: the switch), and the refresh
  model (line 161: the toast timer runs only while open).
- Tests listed under "Tests".

### Out of scope

- An always-on watcher, or any alert while the panel is closed: parent Open
  question (lines 165-167) is answered "enough" by the parent and stays so.
  Alerts are raised only while `active`.
- Any change to `runs.js` (`newAlerts` is done and tested), `notify.py`,
  `viewer-state.py` or any other backend file. No backend test changes.
- The toolbar `RunIndicator` and the Sidebar Runs count (parent line 115-116):
  S1's, already updating from `runs`; mounting `RunIndicator` is not this card.
- A settings screen, or the verify set's UI (parent line 168-170: decided in S3).
- Pausing a toast's 8 s while hovered, toast animations, sounds.
- Notifying on anything but a raised alert (no "run done" notification).
- Card 4.1-4.3 behaviour (controls, pending, cancel dialog, run keys, flash)
  is unchanged.

## Decisions

- **D1. `RunStore` owns the alerts.** It already owns every snapshot and the
  panel-open flag, and the parent says keeping the previous snapshot is the
  store's job. No new store, no change to `App.qml`. The UI only renders
  `toasts` and calls the store's functions.
- **D2. The baseline is "armed", not a copy.** A new bool `alertsArmed`
  (false by default) says whether the current `runs` may be compared against.
  In `applySnapshot`'s `ok:true` branch, before `runs` is replaced:
  `alerts = Runs.newAlerts(store.alertsArmed ? store.runs : null, out)`; after,
  `alertsArmed = true` — only while `active`. It is set false by `startLive()`
  (each opening), `stopLive()`, `projectSwitched()` and the `AmMissing` branch
  (which empties `runs`: comparing the next good snapshot against `[]` would
  alert every escalated run again). An `ok:false` or unreadable snapshot keeps
  `runs` and leaves `alertsArmed` as it is. So: the first good snapshot after
  an opening, a project switch or an am-missing spell raises nothing (parent
  lines 111-113, "reopening never replays history").
- **D3. Alerts are raised only while `active`.** A snapshot that lands after
  the panel closed (a launch already in flight runs to its end,
  docs/architecture.md line 161) raises no toast and no notification, and does
  not arm. Parent lines 122-123: desktop alerts fire only while it is open.
- **D4. The toast list.** `toasts` is an array, oldest first, of
  `{key, id, title, state, reason, expiresMs}`; `key` is an int from a counter
  that only grows (a run that alerts again later gets a new key, so a stale
  Dismiss cannot remove the newer toast). Every raised alert appends one toast
  with `expiresMs = Date.now() + toastMs` (`toastMs`, default `8000`, parent
  line 116). An alert for a run that already has a toast removes that toast
  first (one toast per run). Then, while there are more than 3, the oldest is
  dropped (parent line 117, "stack to 3"). The array is replaced, never
  changed in place.
  `expireToasts(nowMs)` drops every toast with `expiresMs <= nowMs`.
  `toastTimer` (interval 250, repeat) runs only while `active` and `toasts` is
  not empty and calls `expireToasts(Date.now())` — no timer while idle
  (docs/architecture.md line 161). `stopLive()` and `projectSwitched()` empty
  `toasts`: a toast never outlives the panel opening or the project it is
  about.
- **D5. A notification per alert, on its own runner.** When an alert is raised
  and `notifyOnEscalation` is true, the store launches
  `python3 <backendDir>runs/notify.py <title> <reason>` (the alert's `title`
  and `reason`, verbatim, parent line 120-121) on a fresh `HelperRunner` from a
  `notifyC` component, listed in `notifyRunners` (readonly alias, oldest first)
  and dropped (removed and destroyed) when its process exits. The reply is not
  read: a failed or skipped notification changes nothing in the panel. Both
  escalated and dead alerts notify: both mean "a run needs you" (parent line
  14-15), and `reason` (`process died`) says which. The runner's `guard` is
  `""`: a project switch does not stop a notification already launched.
- **D6. The setting: `notifyOnEscalation`, per project, off by default.**
  - Load: `projectSwitched()` sets `notifyOnEscalation = false`,
    `notifySaved = false`, `notifyTouched = false`, and, when `project` is not
    `""`, runs `settingsLoadRunner` (a `HelperRunner` guarded by the project,
    script `<backendDir>projects/viewer-state.py`) with
    `["get-run-settings", project]`. The reply is a bare object;
    `notifyOnEscalation` becomes `obj.notifyOnEscalation === true` and
    `notifySaved` the same. An unreadable reply leaves both false (off is the
    default). A reply that arrives after the user already changed the switch in
    this project (`notifyTouched`) is ignored.
  - Save: `setNotifyOnEscalation(on)` → bool. No project → returns false,
    changes nothing. Otherwise sets `notifyOnEscalation = !!on` at once,
    `notifyTouched = true`, and runs `settingsSaveRunner` (a `HelperRunner`
    guarded by the project, same script, latest wins) with
    `["set-run-settings", project, JSON.stringify({notifyOnEscalation: !!on})]`,
    returns true. A reply `{"ok": true}` sets `notifySaved` to the value that
    was sent. Anything else (`ok:false`, unreadable) sets `notifyOnEscalation`
    back to `notifySaved` and flashes `"Notify on escalation could not be saved"`
    (4.3's `flash`, shown in the Runs footer). A reply for a project the user
    has left is dropped by the runner's guard.
- **D7. `RunToast` is presentation only.** `ui/components/RunToast.qml`, a
  `Column` (spacing `Style.space(6)`), may not import `core/stores`
  (docs/architecture.md line 15). Props: `toasts` (the store's array), `theme`.
  Signals: `openRequested(int key, string runId)`, `dismissRequested(int key)`.
  One card per toast, oldest at the top, newest at the bottom (closest to the
  corner), width `Style.space(320)`:
  - objectName `runToast<i>` (i = position in `toasts`), a `Rectangle` in the
    theme's surface colour with a 1 px border in `theme.urgent` and rounded
    corners (not `radius: height / 2`, not `Qt.rgba(0, 0, 0, 0.55)`: both are
    guarded patterns in `tests/architecture/test_layers.py` line 246);
  - `runToastHeading<i>`: `RunGlyphs.glyphOf(state) + " Run needs you"` in
    `theme.urgent` (parent mock line 128);
  - `runToastLine<i>`: `title + " escalated"` or `title + " died"`;
  - `runToastReason<i>`: `reason`, caption variant, word-wrapped; hidden when
    `reason` is `""`;
  - two `ActionButton`s right-aligned, `runToastOpen<i>` "Open" and
    `runToastDismiss<i>` "Dismiss" (parent mock line 131), emitting
    `openRequested(key, id)` and `dismissRequested(key)`.
  All text through `ThemedText`. No glyph literal in the file (the glyph comes
  from `runGlyphs.js`). Empty `toasts` → no cards, height 0, `visible` false.
  An entry that is not an object, or whose `state` has no glyph, renders with
  an empty glyph and still offers Dismiss; it never throws.
- **D8. Panel mounts it bottom right, under the modals.** One `RunToast`,
  `objectName: "runToast"`, anchored to the right and bottom of the panel's
  content with `Style.space(12)` margins, `z: 50` (above the screens, below
  `ModalCard`'s `z: 100`: an open dialog's backdrop covers the toasts and takes
  their clicks), `toasts: appStores.runs.toasts`.
  - `onDismissRequested`: `appStores.runs.dismissToast(key)`.
  - `onOpenRequested`: `appStores.runs.dismissToast(key)`, then
    `navi.showSection("runs")` and `navi.openRun(runId, "runs")`. Going
    through the Runs section first makes Back from the opened run land on the
    Runs list with a fresh cursor, whichever view the toast was clicked on
    (`openRun` pushes its return slot from the *current* cursor). A run that
    has left the snapshot since the toast was raised: `openRun` refuses
    silently (it returns nothing, and `Navigator` is not changed by this card),
    so the handler checks `appStores.runs.runById(runId) === null` itself, after
    `showSection("runs")`; when true it skips `openRun` and calls
    `appStores.runs.flash("This run is no longer in the snapshot")` (4.3's
    wording, D2 there), and the view is the Runs list.
  - `ModalCard`'s `z: 100` only outranks `RunToast` when both share a parent, so
    `RunToast` is a sibling of the dialogs, inside the same `panel` content item.
- **D9. Escape dismisses all toasts before anything else that is not a modal.**
  `dismissAllToasts()` empties `toasts`. In `closeRequested()` it is inserted
  after `runs.cancelOpen` and before `nav.dropdownOpen`: an open modal still
  closes first (it holds the focus), and an Escape with toasts showing never
  goes Back or closes the panel. In `handleSearchKey`'s Escape branch it is
  checked first: with toasts showing, Escape dismisses them and neither clears
  the search nor closes the panel. A toast is not a modal: `modalOpen()` is not
  changed, so toasts never block the Ctrl chords or the run keys.
- **D10. The switch lives on the Runs screen.** There is no settings screen,
  and the Runs screen is where runs are watched. A `Row`
  (`objectName: "runsNotifyRow"`) directly above `runsFooter`: a
  `ToggleSwitch` (`objectName: "runsNotifyToggle"`,
  `checked: app.runs.notifyOnEscalation`,
  `onToggled: app.runs.setNotifyOnEscalation(!app.runs.notifyOnEscalation)`)
  and a caption `ThemedText` (`objectName: "runsNotifyLabel"`) reading
  `Notify on escalation`. Visible whenever the Runs screen is (also while am is
  missing: the setting is the project's, not am's). `RunsScreen.qml` gains
  `import qs.Ui` (allowed for `ui/screens`, as `BoardScreen.qml` does).

## Behaviour

### `RunStore` (`core/stores/RunStore.qml`)

New state:

| name | type | meaning |
|---|---|---|
| `alertsArmed` | bool, `false` | `runs` may be compared against (D2) |
| `toasts` | array, `[]` | `{key, id, title, state, reason, expiresMs}`, oldest first, at most 3 (D4) |
| `toastMs` | int, `8000` | how long a toast shows |
| `notifyOnEscalation` | bool, `false` | the switch's value for this project (D6) |
| `notifySaved` | bool, `false` | the last value read from or written to `viewer-state.py` |
| `notifyTouched` | bool, `false` | the user changed the switch since the project was selected |
| `toastTimer` | readonly alias | the 250 ms expiry timer |
| `settingsLoadRunner` | readonly alias | `get-run-settings` on a project switch |
| `settingsSaveRunner` | readonly alias | `set-run-settings` on a change |
| `notifyRunners` | readonly alias | in-flight `notify.py` runners, oldest first |

New functions:

- `raiseAlerts(alerts)`: for each alert, D4's append (replacing that run's
  toast, then capping at 3) and, when `notifyOnEscalation`, D5's launch.
  Called from `applySnapshot` only while `active`.
- `expireToasts(nowMs)`, `dismissToast(key)` (removes the toast with that key;
  unknown key → nothing), `dismissAllToasts()`.
- `setNotifyOnEscalation(on)` → bool (D6).
- `applyRunSettings(stdout, exitCode)`, `notifySaveReplied(stdout, exitCode, sent)`
  — the two settings replies (D6).

Changed:

- `applySnapshot` `ok:true`: compute `Runs.newAlerts(armed ? runs : null, out)`
  before `runs = out`; after the existing work, when `active`: `raiseAlerts`,
  then `alertsArmed = true`. `AmMissing`: also `alertsArmed = false`.
- `startLive()`: `alertsArmed = false` (before its refresh).
- `stopLive()`: `alertsArmed = false`, `toasts = []`.
- `projectSwitched()`: `alertsArmed = false`, `toasts = []`, D6's reset and
  load.

### `RunToast` (`ui/components/RunToast.qml`, new) — D7.

### Panel (`ui/Panel.qml`) — D8.

### Shortcuts (`ui/Shortcuts.qml`) — D9.

- `closeRequested()`: `… : keys.app.runs.cancelOpen ? keys.app.runs.closeCancel() : keys.app.runs.toasts.length > 0 ? keys.app.runs.dismissAllToasts() : (keys.app.nav.dropdownOpen ? …`
  — nothing else moves.
- `handleSearchKey`: Escape with `app.runs.toasts.length > 0` →
  `dismissAllToasts()`, accepted; otherwise as today.

### Runs screen (`ui/screens/RunsScreen.qml`) — D10.

## Error paths and edge cases

| case | behaviour |
|---|---|
| first good snapshot after opening the panel, with runs already escalated or dead | no toast, no notification (D2) |
| first good snapshot after a project switch | none (D2) |
| AmMissing, then a good snapshot with an escalated run | none; the snapshot after that compares normally (D2) |
| an `ok:false` / garbled snapshot between two good ones | the good ones are compared; nothing raised by the failure |
| a run escalated in both snapshots | no new toast (`newAlerts`) |
| a run goes running → escalated | one toast; with the setting on, one `notify.py` launch `[…notify.py, title, reason]` |
| running → dead | toast reads `✖ Run needs you` / `<title> died` / `process died` |
| five runs alert in one snapshot | the last three (in snapshot order) show; five notifications |
| a run with a toast alerts again (e.g. dead → escalated) | its old toast goes, the new one is appended |
| 8 s pass | the toast is gone (`expireToasts`) |
| Dismiss on one toast | only that one goes |
| Escape with toasts, no modal | all toasts go; the view stays and the panel stays open (both key paths) |
| Escape with toasts and the cancel dialog open | the dialog closes; the toasts stay |
| Ctrl+6 / `p` with toasts showing | work as without toasts |
| Open on a toast, from any view | toast dismissed, view `run` on that run; Back → Runs list |
| Open on a toast whose run left the snapshot | toast dismissed, view `runs`, flash `This run is no longer in the snapshot` |
| an open dialog | covers the toasts; clicks hit the backdrop |
| panel closed with toasts showing | toasts emptied; reopening shows none |
| a snapshot landing after the panel closed | nothing raised, not armed (D3) |
| setting off (default) | toasts only; no `notify.py` |
| `notify-send` missing / failing | nothing in the panel changes (`notify.py` handles it; reply unread) |
| toggling the switch | value flips at once; one `set-run-settings ROOT {"notifyOnEscalation":true}` |
| the save fails | switch back to the last saved value; flash `Notify on escalation could not be saved` |
| toggling before the load reply lands | the late load reply is ignored |
| project switch | switch reads `false` until that project's `get-run-settings` reply; the old project's save reply is dropped |
| no project | `setNotifyOnEscalation` returns false, launches nothing |

## Tests

All run under `bash tests/run.sh` (pytest + qmltestrunner with
`tests/stubs`). TDD: each appears failing before its code. Snapshots are fed
with `applySnapshot(JSON.stringify({ok: true, runs: [...]}), 0)` as the
existing tests do.

**Store tier — `tests/core/stores/tst_run_store.qml` (appended).** The alert
and setting rules without any UI: each rule is one small, fast test against
the stub `Process`, and runner argv can be read directly.
1. Not active: two snapshots, running then escalated → `toasts` empty, no
   notify runner, `alertsArmed` false.
2. Active: first snapshot with an escalated run → no toast; second snapshot
   with another run turned escalated → one toast with that run's `id`,
   `title`, `state` `"escalated"`, its `escalationReason`, and
   `expiresMs` ≈ now + 8000.
3. A third identical snapshot → still one toast (no repeat).
4. Re-arming: after `stopLive()`/`startLive()` (active false then true), the
   first snapshot raises nothing even though a run turned dead meanwhile;
   `toasts` was emptied by the close.
5. AmMissing between two good snapshots → the good snapshot after it raises
   nothing; an `ok:false` `HelperError` between two good snapshots does not
   stop the second from raising.
6. Five runs turning escalated in one snapshot → three toasts, the last three
   ids in snapshot order; keys strictly increasing.
7. A run with a toast that turns dead → one toast for it, `state` `"dead"`,
   reason `process died`, a new key.
8. `expireToasts(t)` drops only toasts with `expiresMs <= t`; `toastTimer`
   is running only while active with toasts (false after `dismissAllToasts()`);
   with `toastMs = 50` a toast is gone after `wait(400)`.
9. `dismissToast(key)` removes that toast only; an unknown key changes
   nothing; `dismissAllToasts()` empties.
10. Project switch empties `toasts`, resets `alertsArmed`, sets
    `notifyOnEscalation` false and launches `settingsLoadRunner` with
    `python3|…/projects/viewer-state.py|get-run-settings|<root>`.
11. Load reply `{"verify":[],"allowNoVerification":false,"notifyOnEscalation":true}`
    → `notifyOnEscalation` true; a garbled reply → false.
12. Setting on: an alert launches one `notifyRunners` entry with argv
    `python3|…/runs/notify.py|<title>|<reason>`; two alerts in one snapshot →
    two runners; a runner's reply removes it from `notifyRunners`. Setting
    off → no runner.
13. `setNotifyOnEscalation(true)` → true, value true at once,
    `settingsSaveRunner` argv
    `python3|…/projects/viewer-state.py|set-run-settings|<root>|{"notifyOnEscalation":true}`;
    reply `{"ok":true}` → `notifySaved` true. A reply
    `{"ok":false,"error":"x"}` → value back to the saved value, `flashText`
    `Notify on escalation could not be saved`.
14. `setNotifyOnEscalation(true)` before the load reply, then a load reply with
    `notifyOnEscalation: false` → value stays true.
15. No project → `setNotifyOnEscalation(true)` returns false, no save launch.

**Component tier — `tests/ui/components/tst_run_toast.qml` (new, following
`tst_run_controls.qml`).** What a toast looks like and emits, with plain
props; no store.
16. Empty `toasts` → no `runToast0`, component not visible.
17. One escalated toast → `runToastHeading0` text `‼ Run needs you`,
    `runToastLine0` `M3 escalated`, `runToastReason0` the reason; a dead one →
    `✖ Run needs you`, `… died`.
18. Three toasts → `runToast0..2` in array order; `runToast3` absent.
19. Clicking `runToastOpen1` emits `openRequested(key1, id1)`; clicking
    `runToastDismiss0` emits `dismissRequested(key0)` (SignalSpy).
20. A non-object entry and an entry with `state: "bogus"` render without
    throwing and still have a Dismiss button.

**Shortcuts tier — `tests/ui/tst_shortcuts.qml` (appended).** The Escape order
on the real App + Navigator, without rendering.
21. Toasts present on view `run`: `closeRequested()` empties them and
    `viewMode` stays `run`; a second call goes back as before.
22. Toasts present with the cancel dialog open: `closeRequested()` closes the
    dialog only; the toasts stay.
23. Toasts present on view `runs` with search text `"x"`: `handleSearchKey`
    with Escape empties the toasts, the search stays `"x"`, the panel's
    `close` action is not called; a second Escape clears the search.
24. Toasts present: `handleGlobalKey(Ctrl+6)` still switches to Runs and
    `modalOpen()` is false.

**Screen tier — `tests/ui/screens/tst_runs_screen.qml` (appended).**
25. `runsNotifyToggle` is checked iff `app.runs.notifyOnEscalation`;
    `runsNotifyLabel` reads `Notify on escalation`; emitting the switch's
    `toggled()` calls `setNotifyOnEscalation(true)` once on the plain app
    object; the row shows while am is missing.

**Flow tier — `tests/ui/tst_runs_flow.qml` (appended after the file's last
test).** The whole Panel, because only here store, toast, navigation and keys
meet (parent line 160, "toast Open navigates"). `make()` also cancels
`p.app.runs.settingsLoadRunner`.
26. Toast Open navigates: on view `board`, feed a baseline snapshot then one
    where `run-0000000000a1` is escalated → `runToast0` visible, bottom right
    of the panel (its right and bottom edges within the panel's content);
    click `runToastOpen0` → `viewMode` `run`, `selectedRunId` that run,
    `toasts` empty; Escape (key catcher) → Runs list.
27. Escape through the real key path on the Runs list: focus in the empty
    search field, `keyClick(Qt.Key_Escape)` with a toast showing → toast gone,
    panel still open, view `runs`.
28. Dismiss: two toasts, click `runToastDismiss0` → one left, the other run's.
29. With the setting on (`p.app.runs.setNotifyOnEscalation(true)`, save reply
    `{"ok":true}`), an escalation launches one notify runner whose argv ends
    with the run's title and reason; with it off, none.
30. Open on a toast after a snapshot removed its run → toast gone, view
    `runs`, `runsFooter` shows `This run is no longer in the snapshot`.

**Architecture tier — `tests/architecture` (unchanged, must stay green).**
`RunToast` must not import `core/stores`, must carry no glyph literal and none
of the guarded visual patterns; no local type named like a shell type.

## Review focus (for the planner)

- Reopening the panel, switching project or recovering from am missing must
  never replay old escalations (tests 4, 5, 10): the easiest regression is
  arming once and never disarming.
- Escape with toasts showing on the Runs list or Board must not close the
  panel (test 23, 27): the search field's Escape does not go through
  `closeRequested()`.
- Two notifications in one snapshot must both launch (test 12): one shared
  latest-wins runner would silently kill the first.
- A late `get-run-settings` reply must not undo a toggle (test 14), and a
  failed save must not leave the switch claiming a value that was never stored
  (test 13).
- Existing store and flow tests that count launches or processes after a
  project switch now also see `settingsLoadRunner`: adjust their setup (cancel
  it, as `make()` does with the snapshot runner), not their assertions.
