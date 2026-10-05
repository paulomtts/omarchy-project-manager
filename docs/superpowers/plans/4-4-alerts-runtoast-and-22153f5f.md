# 4.4 Alerts: RunToast and the desktop notification setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While the panel is open, every run that newly turns escalated or dead shows a toast (bottom right, Open / Dismiss, 8 s, at most 3) and, when the project's "Notify on escalation" switch on the Runs screen is on, a desktop notification.

**Architecture:** `RunStore` (`app.runs`) owns everything: an armed/disarmed alert baseline compared through the existing `Runs.newAlerts`, the `toasts` list and its `toastTimer`, one `HelperRunner` per `notify.py` launch, and the per-project setting loaded and saved through `viewer-state.py`. A new presentation-only `RunToast` renders `toasts`; `Panel` mounts it under the dialogs and wires Open (through the Runs section, then `openRun`) and Dismiss; `Shortcuts` lets Escape dismiss the toasts after any modal; `RunsScreen` carries the switch.

**Tech Stack:** QML (Qt 6 / Quickshell), JavaScript domain modules, QtTest via `qmltestrunner` with `tests/stubs`, run by `bash tests/run.sh [filter]` (pytest runs first; then every `tst_*.qml` whose path contains the filter).

**Spec:** `docs/superpowers/specs/4-4-alerts-runtoast-and-22153f5f.md` (copied verbatim below, headings demoted one level).

---

## The spec (verbatim)

## 4.4 Alerts: RunToast and the desktop notification setting (card 22153f5f)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-controls-design.md` (S2,
"the parent" below): "Alerts" (lines 109-136), "Testing" (line 160, "toast Open
navigates"), "Open questions" (lines 165-167). Parent story f03629a7 ("Control
store and UI"). Blocked by 4.3 (b4bc1521, spec
`4-3-cancel-confirmation-b4bc1521.md`), which is done on this branch.

This card makes an alert visible: a toast in the panel for every run that newly
needs a human, and, when the user turned it on for the project, a desktop
notification. The alert decision itself (`Runs.newAlerts`) and the two backend
helpers it needs already exist; this card wires them up.

### Starting point

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

### Scope

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

#### Out of scope

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

### Decisions

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

### Behaviour

#### `RunStore` (`core/stores/RunStore.qml`)

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

#### `RunToast` (`ui/components/RunToast.qml`, new) — D7.

#### Panel (`ui/Panel.qml`) — D8.

#### Shortcuts (`ui/Shortcuts.qml`) — D9.

- `closeRequested()`: `… : keys.app.runs.cancelOpen ? keys.app.runs.closeCancel() : keys.app.runs.toasts.length > 0 ? keys.app.runs.dismissAllToasts() : (keys.app.nav.dropdownOpen ? …`
  — nothing else moves.
- `handleSearchKey`: Escape with `app.runs.toasts.length > 0` →
  `dismissAllToasts()`, accepted; otherwise as today.

#### Runs screen (`ui/screens/RunsScreen.qml`) — D10.

### Error paths and edge cases

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

### Tests

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

### Review focus (for the planner)

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

---

## Global Constraints

- No change to `core/domain/runs.js`, `core/stores/App.qml`, `core/stores/HelperRunner.qml`, `ui/Navigator.qml`, or anything under `core/backend/` (`notify.py`, `viewer-state.py` included). No backend test changes.
- `ui/components/RunToast.qml` imports no `core/stores`, carries no glyph literal (the glyph comes from `runGlyphs.js`), and none of the guarded patterns in `tests/architecture/test_layers.py` (`radius: height / 2`, `Qt.rgba(0, 0, 0, 0.55)`, `bordered: true`, `font.family:`). `tests/architecture` stays green.
- Exact strings: `Run needs you` (heading is `RunGlyphs.glyphOf(state) + " Run needs you"`), `<title> escalated`, `<title> died`, `Open`, `Dismiss`, `Notify on escalation`, `Notify on escalation could not be saved`, `This run is no longer in the snapshot`.
- Numbers: `toastMs` default `8000`; `toastTimer` interval `250`, repeat; at most `3` toasts; `RunToast` width `Style.space(320)`, spacing `Style.space(6)`; Panel margins `Style.space(12)`, `z: 50`.
- Argv: `python3 <backendDir>runs/notify.py <title> <reason>`; `python3 <backendDir>projects/viewer-state.py get-run-settings <root>`; `python3 <backendDir>projects/viewer-state.py set-run-settings <root> {"notifyOnEscalation":true|false}`.
- Alerts (toasts and notifications) are raised only while `active` (the panel is open). The first good snapshot after an opening, a project switch or an `AmMissing` reply only arms.
- The ORDER of the guards in `ui/Shortcuts.qml` is load bearing: insert, never reorder. `modalOpen()` is not changed.
- New tests are appended at the end of their files. The Runs screen test stub gains `notifyOnEscalation`, `notifyCalls` and `setNotifyOnEscalation`. The store's timer-inventory test gains `toastTimer` (the one existing assertion this card changes, because the inventory is exactly what it pins). Other existing tests that now also see `settingsLoadRunner` get their setup adjusted (cancel it), never their assertions.
- Commit messages follow the repo's style: `feat(runs): … (card 22153f5f)` / `test(runs): … (card 22153f5f)`.

## Review Focus

1. **A snapshot that was already in flight lands after the panel closed** with a run that turned escalated: it is applied, but raises no toast and does not arm (D3), so the next opening's first snapshot still only arms. Pinned in Task 1, `test_a_snapshot_landing_after_the_panel_closed_raises_nothing_and_does_not_arm`.
2. **A stale Dismiss after the same run alerted again** (Dismiss the escalated toast, the run dies, the old key is sent again): the newer toast stays — keys only grow. Pinned in Task 1, test 9.
3. **The old project's `get-run-settings` reply lands after a switch to another project**: it is dropped; B's switch never shows A's setting. Pinned in Task 2, `test_a_late_load_reply_for_the_old_project_is_dropped`.
4. **A `set-run-settings` reply (failed) lands after the user left that project**: no revert, no flash about A in B. Pinned in Task 2, `test_a_save_reply_for_a_project_the_user_left_changes_nothing`.
5. **Escape on a list view whose chain ends in closing the panel (Board) with toasts showing, through `closeRequested()`**: the toasts go, the panel stays open; the next Escape closes it. Pinned in Task 4, `test_escape_on_the_board_dismisses_the_toasts_and_keeps_the_panel_open`.

---

## File map

| file | change | responsibility |
|---|---|---|
| `core/stores/RunStore.qml` | modify | alert baseline (`alertsArmed`), `toasts` and their expiry, notify runners, the per-project `notifyOnEscalation` load and save |
| `ui/components/RunToast.qml` | create | the toast stack: renders `toasts`, emits Open / Dismiss |
| `ui/Shortcuts.qml` | modify | Escape dismisses the toasts (key catcher chain and search field) |
| `ui/screens/RunsScreen.qml` | modify | the `Notify on escalation` switch above the footer |
| `ui/Panel.qml` | modify | mounts `RunToast` bottom right, wires Open / Dismiss |
| `docs/architecture.md` | modify | `RunStore` paragraph, refresh model, components list, `Shortcuts.qml`, run screens paragraph |
| `tests/core/stores/tst_run_store.qml` | modify inventory + append | tests 1-15 and Review Focus 1-4 |
| `tests/ui/components/tst_run_toast.qml` | create | tests 16-20 |
| `tests/ui/tst_shortcuts.qml` | append | tests 21-24 and Review Focus 5 |
| `tests/ui/screens/tst_runs_screen.qml` | stub + append | test 25 |
| `tests/ui/tst_runs_flow.qml` | `make()` + append | tests 26-30 |

How to read test output: `bash tests/run.sh <filter>` runs pytest first, then every `tst_*.qml` whose path contains the filter, printing `== tests/...` per file, any `FAIL!  : <Case>::<test>` lines with a `   Loc:` line, then `Totals: N passed, M failed, …`. Lines containing `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item` or `is not a function` are echoed and make the script exit 1 — treat them as failures.

Test fixtures you will meet in `tests/core/stores/tst_run_store.qml` (all already defined in the file): `make()`, `makeWithProject(root)`, `activeStore(root)` (active, then project set: its first snapshot is in flight), `reply(proc, text, code)` (fakes a process exit), `entry(id, runStatus, live)` (a snapshot entry whose title is `"m-" + id` and, with no rows or subtasks, whose escalation reason is `"escalated"`), `okReply(entries)`, `snapshot(store, entries)` (refresh + reply), `argv(proc)` (`command.join("|")`), `running(id)` (started, live lease), `dead(id)` (started, lease not live), `rootA` = `"/home/u/my proj"`, `rootB` = `"/home/u/b"`. The stub `Process` never runs anything: a launched process sits there until a test calls `reply` on it.

---

### Task 1: `RunStore` — the alert baseline and the toast list

**Files:**
- Modify: `core/stores/RunStore.qml` (state after `flashText` at line 79; alias after `flashTimer` at line 91; `startLive` lines 123-127; `stopLive` lines 131-138; `projectSwitched` lines 228-250; `applySnapshot` lines 395-437; a new `---- alerts` section after `confirmCancel` (line 705); a `Timer` after `flashTimer` (line 786); a `QtObject` after `controlState` (line 804))
- Modify: `docs/architecture.md:95` (RunStore paragraph) and `:161` (refresh model)
- Test: `tests/core/stores/tst_run_store.qml` (line 1137, the timer inventory; append before the file's final `}`)

**Interfaces:**
- Consumes: `Runs.newAlerts(prevRuns, nextRuns)` → `[{id, title, state, reason}]` (exists in `core/domain/runs.js`).
- Produces (Tasks 2, 4, 6 rely on these):
  - `alertsArmed: bool` (default `false`)
  - `toasts: var` — array of `{key: int, id: string, title: string, state: "escalated"|"dead", reason: string, expiresMs: number}`, oldest first, ≤ 3, always replaced
  - `toastMs: int` (default `8000`)
  - `readonly property alias toastTimer` (objectName `"toastTimer"`)
  - `raiseAlerts(alerts)` — appends a toast per alert (Task 2 adds the notify launch inside its loop)
  - `expireToasts(nowMs)`, `dismissToast(key)`, `dismissAllToasts()`

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_store.qml`, line 1137, replace

```qml
    compare(timers.sort().join(","), "debounceTimer,flashTimer,livenessTimer,pendingTimer,pollTimer,staleTimer", "the logs add no timer")
```

with

```qml
    compare(timers.sort().join(","), "debounceTimer,flashTimer,livenessTimer,pendingTimer,pollTimer,staleTimer,toastTimer", "the logs add no timer")
```

Then append inside the `TestCase`, after `test_a_project_switch_closes_the_dialog_and_clears_the_flash` (before the file's last `}`):

```qml

  // ---- alerts: the toasts (S2 4.4)

  function escalated(id) { return entry(id, "escalated", false) }
  function toastIds(store) { return store.toasts.map(function(t) { return t.id }).join(",") }

  // An active store on project A whose first snapshot listed `entries`: that
  // snapshot only armed the alerts.
  function armedStore(entries) {
    var store = activeStore(rootA); if (!store) return null
    reply(store.snapshotRunner.current, okReply(entries), 0)
    compare(store.alertsArmed, true, "the first good snapshot while open arms the alerts")
    compare(store.toasts.length, 0, "and raises nothing")
    return store
  }

  // 1
  function test_no_toast_while_the_panel_is_closed() {
    var store = makeWithProject(rootA); if (!store) return
    compare(store.alertsArmed, false)
    compare(store.toasts.length, 0)
    reply(store.snapshotRunner.current, okReply([running("a")]), 0)
    snapshot(store, [escalated("a")])
    compare(store.toasts.length, 0)
    compare(store.alertsArmed, false, "a closed panel never arms")
  }

  // 2
  function test_a_run_that_turns_escalated_raises_one_toast() {
    var store = activeStore(rootA); if (!store) return
    compare(store.toastMs, 8000)
    reply(store.snapshotRunner.current, okReply([escalated("a"), running("b")]), 0)
    compare(store.toasts.length, 0, "the first snapshot after opening never replays history")
    compare(store.alertsArmed, true)
    var before = Date.now()
    snapshot(store, [escalated("a"), escalated("b")])
    compare(store.toasts.length, 1)
    var t = store.toasts[0]
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
    compare(store.toasts.length, 1)
    var key = store.toasts[0].key
    snapshot(store, [escalated("a")])
    compare(store.toasts.length, 1)
    compare(store.toasts[0].key, key, "the same toast, not a new one")
  }

  // 4 (Review focus: reopening never replays history)
  function test_closing_empties_the_toasts_and_reopening_raises_nothing_at_first() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    snapshot(store, [escalated("a"), running("b")])
    compare(store.toasts.length, 1)
    store.active = false
    compare(store.toasts.length, 0, "a toast never outlives the panel opening")
    compare(store.alertsArmed, false)
    store.active = true
    compare(store.alertsArmed, false)
    reply(store.snapshotRunner.current, okReply([escalated("a"), dead("b")]), 0)
    compare(store.toasts.length, 0, "b died while the panel was closed: not replayed")
    compare(store.alertsArmed, true)
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
    compare(store.toasts.length, 0)
    compare(store.alertsArmed, false)
  }

  // 5
  function test_am_missing_disarms_and_a_failed_snapshot_does_not() {
    var store = armedStore([running("a")]); if (!store) return
    store.refresh()
    reply(store.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "AmMissing", message: "am is not installed" } }) + "\n", 1)
    compare(store.runs.length, 0)
    compare(store.alertsArmed, false)
    snapshot(store, [escalated("a")])
    compare(store.toasts.length, 0, "the first good snapshot after am came back raises nothing")
    compare(store.alertsArmed, true)
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "b", "the one after that compares normally")

    var other = armedStore([running("x")]); if (!other) return
    other.refresh()
    reply(other.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "HelperError", message: "boom" } }) + "\n", 1)
    compare(other.alertsArmed, true, "a failed snapshot keeps the baseline")
    other.refresh()
    reply(other.snapshotRunner.current, "garbage\n", 1)
    compare(other.alertsArmed, true)
    snapshot(other, [escalated("x")])
    compare(toastIds(other), "x")
  }

  // 6
  function test_five_alerts_in_one_snapshot_leave_the_last_three_toasts() {
    var store = armedStore([]); if (!store) return
    snapshot(store, [escalated("r1"), escalated("r2"), dead("r3"), escalated("r4"), dead("r5")])
    compare(toastIds(store), "r3,r4,r5")
    verify(store.toasts[0].key < store.toasts[1].key && store.toasts[1].key < store.toasts[2].key, "keys only grow")
    compare(store.toasts[0].state, "dead")
    compare(store.toasts[0].reason, "process died")
  }

  // 7
  function test_a_run_that_alerts_again_replaces_its_own_toast() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "a,b")
    var oldKey = store.toasts[0].key
    snapshot(store, [dead("a"), escalated("b")])
    compare(toastIds(store), "b,a", "a's old toast went and its new one is the newest")
    compare(store.toasts[1].state, "dead")
    compare(store.toasts[1].reason, "process died")
    verify(store.toasts[1].key > oldKey, "a new key")
  }

  // 8
  function test_toasts_expire_and_the_timer_runs_only_while_open_with_toasts() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    var timer = store.toastTimer
    compare(timer.objectName, "toastTimer")
    compare(timer.interval, 250)
    compare(timer.repeat, true)
    compare(timer.running, false, "no toast: no timer")
    snapshot(store, [escalated("a"), running("b")])
    compare(timer.running, true)
    var aExpires = store.toasts[0].expiresMs
    store.toastMs = 60000
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "a,b")
    store.expireToasts(aExpires - 1)
    compare(toastIds(store), "a,b", "not yet")
    store.expireToasts(aExpires)
    compare(toastIds(store), "b", "expiresMs <= now goes")
    store.dismissAllToasts()
    compare(timer.running, false, "nothing left: no timer")
    store.toastMs = 50
    snapshot(store, [escalated("a"), dead("b")])
    compare(store.toasts.length, 1)
    tryVerify(function() { return store.toasts.length === 0 }, 2000, "the timer dropped the expired toast")
    compare(timer.running, false)
  }

  // 9 (and Review Focus 2)
  function test_dismiss_removes_one_toast_by_key_and_dismiss_all_empties() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    snapshot(store, [escalated("a"), escalated("b")])
    var keyA = store.toasts[0].key
    store.dismissToast(-12345)
    compare(toastIds(store), "a,b", "an unknown key changes nothing")
    store.dismissToast(keyA)
    compare(toastIds(store), "b")
    snapshot(store, [dead("a"), escalated("b")])
    compare(toastIds(store), "b,a")
    store.dismissToast(keyA)
    compare(toastIds(store), "b,a", "a's stale key leaves its newer toast")
    store.dismissAllToasts()
    compare(store.toasts.length, 0)
  }

  // 10 (the toast half; Task 2 pins the setting half)
  function test_a_project_switch_empties_the_toasts_and_disarms() {
    var store = armedStore([running("a")]); if (!store) return
    snapshot(store, [escalated("a")])
    compare(store.toasts.length, 1)
    store.project = rootB
    compare(store.toasts.length, 0)
    compare(store.alertsArmed, false)
    reply(store.snapshotRunner.current, okReply([escalated("z")]), 0)
    compare(store.toasts.length, 0, "B's first snapshot raises nothing")
    compare(store.alertsArmed, true)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL — `test_logs_add_no_timer_and_none_runs_while_idle` (no `toastTimer` yet), and every new test fails (e.g. `TypeError: Cannot read property 'length' of undefined` for `store.toasts`). The script exits 1.

- [ ] **Step 3: Write the implementation**

In `core/stores/RunStore.qml`:

(a) After `property string flashText: ""` (line 79) add:

```qml

  // Alerts (S2 4.4): a toast for every run that newly needs a human while the
  // panel is open. `alertsArmed` says the current `runs` may be compared
  // against: the first good snapshot after an opening, a project switch or an
  // am-missing spell only arms, so history is never replayed. `toasts` is
  // {key, id, title, state, reason, expiresMs}, oldest first, at most 3, and
  // is replaced, never changed in place.
  property bool alertsArmed: false
  property var toasts: []
  property int toastMs: 8000
```

(b) After `readonly property alias flashTimer: flashTimer` (line 91) add:

```qml
  readonly property alias toastTimer: toastTimer
```

(c) Replace `startLive()` (lines 121-127) with:

```qml
  // The panel opened: fetch now; the first good snapshot starts the watch and
  // arms the alerts, and the stale clock counts from now.
  function startLive() {
    store.watchTried = false
    store.alertsArmed = false
    store.restartStale()
    store.refresh()
  }
```

(d) Replace `stopLive()` (lines 129-138) with:

```qml
  // The panel closed: no process and no timer is left running, and no toast
  // outlives the opening. The runs, the selection and amStatus stay for the
  // next opening.
  function stopLive() {
    store.stopWatch()
    debounceTimer.stop()
    store.stopPoll()
    staleTimer.stop()
    store.stale = false
    store.watchWarning = ""
    store.alertsArmed = false
    store.toasts = []
  }
```

(e) In `projectSwitched()`, replace

```qml
    store.closeCancel()
    store.flash("")
    if (store.project !== "") store.refresh()
  }
```

with

```qml
    store.closeCancel()
    store.flash("")
    store.alertsArmed = false
    store.toasts = []
    if (store.project !== "") store.refresh()
  }
```

(f) In `applySnapshot`, replace

```qml
      store.runs = out
      store.settleAfterSnapshot()
```

with

```qml
      // Compared before the runs are replaced; raised below only while open.
      var alerts = Runs.newAlerts(store.alertsArmed ? store.runs : null, out)
      store.runs = out
      store.settleAfterSnapshot()
```

and replace

```qml
      if (store.active) {
        staleTimer.restart()
        if (!store.watchTried) store.startWatch()
      }
      return
```

with

```qml
      if (store.active) {
        staleTimer.restart()
        if (!store.watchTried) store.startWatch()
        store.raiseAlerts(alerts)
        store.alertsArmed = true
      }
      return
```

and in the `AmMissing` branch replace

```qml
      if (type === "AmMissing") {
        store.runs = []
        store.amStatus = "missing"
```

with

```qml
      if (type === "AmMissing") {
        store.runs = []
        store.amStatus = "missing"
        // Comparing the next good snapshot against [] would alert every
        // escalated run again.
        store.alertsArmed = false
```

(g) After `confirmCancel()` (ends line 705), before the `// The guard is the project root, …` comment, add:

```qml

  // ---- alerts (S2 4.4)

  // One toast per alert, newest last: a run's older toast goes first, then the
  // oldest beyond three. Called from applySnapshot only while active.
  function raiseAlerts(alerts) {
    var list = Array.isArray(alerts) ? alerts : []
    for (var i = 0; i < list.length; i++) {
      var a = list[i]
      toastState.nextKey += 1
      var next = store.toasts.filter(function(t) { return t.id !== a.id })
      next.push({ key: toastState.nextKey, id: a.id, title: a.title, state: a.state, reason: a.reason,
                  expiresMs: Date.now() + store.toastMs })
      while (next.length > 3) next.shift()
      store.toasts = next
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
```

(h) After the `flashTimer` `Timer { … }` block (ends line 786) add:

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

(i) After the `controlState` `QtObject { … }` block (ends line 804) add:

```qml

  // The toast keys only grow, so a stale Dismiss never removes a newer toast.
  QtObject {
    id: toastState
    property int nextKey: 0
  }
```

(j) In `docs/architecture.md`, in the RunStore paragraph (line 95), replace

```
a project switch closes the dialog and clears the flash.
```

with

```
a project switch closes the dialog and clears the flash. Alerts (S2 4.4): while `active`, every good snapshot is compared with the one before it through `Runs.newAlerts`, and each run that newly turned escalated or dead gets a toast in `toasts` (`{key, id, title, state, reason, expiresMs}`, oldest first, at most 3, one per run; `key` only grows, so a stale Dismiss never removes a newer toast). `alertsArmed` says the current `runs` may be compared against: the first good snapshot after an opening, a project switch or an `AmMissing` reply only arms, so reopening the panel never replays history, and a snapshot that lands after the panel closed raises nothing. A toast lasts `toastMs` (8000); `toastTimer` (250 ms, only while the panel is open and a toast shows) drops expired ones through `expireToasts(nowMs)`, and `dismissToast(key)` / `dismissAllToasts()` remove them. Closing the panel and a project switch empty `toasts`.
```

and in the refresh model (line 161) replace

```
the liveness re-read (only while a run is running) and the fallback poll run only while the panel is open (`active`)
```

with

```
the liveness re-read (only while a run is running), the fallback poll and the toast expiry (`toastTimer`, only while a toast shows) run only while the panel is open (`active`)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: PASS — `Totals:` with `0 failed`, no error lines.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml docs/architecture.md
git commit -m "feat(runs): RunStore raises a toast for each run that newly needs a human while the panel is open, never replaying history (card 22153f5f)"
```

---

### Task 2: `RunStore` — the Notify on escalation setting and the desktop notifications

**Files:**
- Modify: `core/stores/RunStore.qml` (state after Task 1's `toastMs`; aliases after Task 1's `toastTimer` alias; `projectSwitched`; `raiseAlerts` from Task 1; new functions after `dismissAllToasts`; two `HelperRunner`s after `logsRunner` (line ~729); a `QtObject` after Task 1's `toastState`; a `Component` after `controlC` (line ~826))
- Modify: `docs/architecture.md:95` (RunStore paragraph, after Task 1's sentence)
- Test: `tests/core/stores/tst_run_store.qml` (append before the file's final `}`)

**Interfaces:**
- Consumes: Task 1's `raiseAlerts(alerts)`, `toasts`, `armedStore(entries)`, `escalated(id)`; `flash(text)` (4.3); `parseEnvelope(text)` (returns the last line's JSON object or `null`).
- Produces (Tasks 5, 6 rely on these):
  - `notifyOnEscalation: bool` (default `false`), `notifySaved: bool`, `notifyTouched: bool`
  - `setNotifyOnEscalation(on)` → `bool`
  - `applyRunSettings(stdout, exitCode)`, `notifySaveReplied(stdout, exitCode, sent)`
  - `readonly property alias settingsLoadRunner`, `settingsSaveRunner` (each a `HelperRunner`; `.current` is its `Process`), `notifyRunners` (array of `HelperRunner`, oldest first)

- [ ] **Step 1: Write the failing tests**

Append inside the `TestCase` of `tests/core/stores/tst_run_store.qml`, after Task 1's `test_a_project_switch_empties_the_toasts_and_disarms`:

```qml

  // ---- alerts: the setting and the desktop notifications (S2 4.4)

  property string notifyCmd: "python3|/plugin/core/backend/runs/notify.py|"
  property string viewerCmd: "python3|/plugin/core/backend/projects/viewer-state.py|"

  function runSettings(notify) {
    return JSON.stringify({ verify: [], allowNoVerification: false, notifyOnEscalation: notify }) + "\n"
  }

  // 10 (the setting half)
  function test_a_project_switch_resets_the_switch_and_loads_the_new_projects_setting() {
    var store = makeWithProject(rootA); if (!store) return
    var loadA = store.settingsLoadRunner.current
    verify(loadA, "selecting a project loads its run settings")
    compare(argv(loadA), tc.viewerCmd + "get-run-settings|/home/u/my proj")
    compare(loadA.command.length, 4)
    compare(loadA.launchGuard, "/home/u/my proj")
    reply(loadA, runSettings(true), 0)
    compare(store.notifyOnEscalation, true)
    store.project = rootB
    compare(store.notifyOnEscalation, false, "off until B's own reply")
    compare(store.notifySaved, false)
    compare(store.notifyTouched, false)
    var loadB = store.settingsLoadRunner.current
    verify(loadB !== loadA, "a new load")
    compare(argv(loadB), tc.viewerCmd + "get-run-settings|/home/u/b")
    compare(loadB.launchGuard, "/home/u/b", "the launch is guarded by the NEW project")
    var seq = store.settingsLoadRunner.seq
    store.project = ""
    compare(store.settingsLoadRunner.seq, seq, "no project: nothing is loaded")
    compare(store.settingsLoadRunner.guard, "")
  }

  // 11
  function test_the_load_reply_sets_the_switch_and_a_garbled_one_leaves_it_off() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.settingsLoadRunner.current, runSettings(true), 0)
    compare(store.notifyOnEscalation, true)
    compare(store.notifySaved, true)
    var other = makeWithProject(rootA); if (!other) return
    reply(other.settingsLoadRunner.current, "Traceback: boom\n", 1)
    compare(other.notifyOnEscalation, false)
    compare(other.notifySaved, false)
    var third = makeWithProject(rootA); if (!third) return
    reply(third.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: "yes" }) + "\n", 0)
    compare(third.notifyOnEscalation, false, "only a real true turns it on")
  }

  // Review Focus 3
  function test_a_late_load_reply_for_the_old_project_is_dropped() {
    var store = makeWithProject(rootA); if (!store) return
    var loadA = store.settingsLoadRunner.current
    store.project = rootB
    reply(loadA, runSettings(true), 0)
    compare(store.notifyOnEscalation, false, "A's setting never shows in B")
    compare(store.notifySaved, false)
  }

  // 12
  function test_with_the_setting_on_each_alert_launches_its_own_notification() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    compare(store.notifyRunners.length, 0)
    store.notifyOnEscalation = true
    snapshot(store, [escalated("a"), dead("b")])
    compare(store.notifyRunners.length, 2, "one runner per alert")
    var first = store.notifyRunners[0].current, second = store.notifyRunners[1].current
    compare(argv(first), tc.notifyCmd + "m-a|escalated")
    compare(argv(second), tc.notifyCmd + "m-b|process died")
    compare(first.running, true, "the second launch did not stop the first")
    compare(second.running, true)
    compare(first.launchGuard, "")
    reply(first, JSON.stringify({ ok: true, sent: true }) + "\n", 0)
    compare(store.notifyRunners.length, 1)
    reply(second, "garbage\n", 1)
    compare(store.notifyRunners.length, 0, "a failed notification goes too")
    compare(toastIds(store), "a,b", "the replies change nothing else")
    compare(store.flashText, "")

    snapshot(store, [escalated("a"), dead("b"), escalated("c")])
    compare(store.notifyRunners.length, 1)
    var proc = store.notifyRunners[0].current
    store.project = rootB
    compare(proc.running, true, "a project switch does not stop a launched notification")
    reply(proc, JSON.stringify({ ok: true, sent: true }) + "\n", 0)
    compare(store.notifyRunners.length, 0)

    var off = armedStore([running("a")]); if (!off) return
    snapshot(off, [escalated("a")])
    compare(off.toasts.length, 1)
    compare(off.notifyRunners.length, 0, "setting off: toasts only")

    var five = armedStore([]); if (!five) return
    five.notifyOnEscalation = true
    snapshot(five, [escalated("r1"), escalated("r2"), dead("r3"), escalated("r4"), dead("r5")])
    compare(five.toasts.length, 3)
    compare(five.notifyRunners.length, 5, "every alert notifies, even those whose toast was capped away")
  }

  // 1 (the notification half)
  function test_no_notification_while_the_panel_is_closed() {
    var store = makeWithProject(rootA); if (!store) return
    store.notifyOnEscalation = true
    reply(store.snapshotRunner.current, okReply([running("a")]), 0)
    snapshot(store, [escalated("a")])
    compare(store.notifyRunners.length, 0)
    compare(store.toasts.length, 0)
  }

  // 13
  function test_the_switch_saves_at_once_and_a_failed_save_puts_it_back() {
    var store = makeWithProject(rootA); if (!store) return
    compare(store.setNotifyOnEscalation(true), true)
    compare(store.notifyOnEscalation, true, "the switch flips at once")
    compare(store.notifyTouched, true)
    var save = store.settingsSaveRunner.current
    verify(save, "a save was launched")
    compare(save.command.length, 5)
    compare(argv(save), tc.viewerCmd + 'set-run-settings|/home/u/my proj|{"notifyOnEscalation":true}')
    compare(save.launchGuard, "/home/u/my proj")
    reply(save, JSON.stringify({ ok: true }) + "\n", 0)
    compare(store.notifySaved, true)
    compare(store.flashText, "")
    compare(store.setNotifyOnEscalation(false), true)
    compare(store.notifyOnEscalation, false)
    compare(argv(store.settingsSaveRunner.current), tc.viewerCmd + 'set-run-settings|/home/u/my proj|{"notifyOnEscalation":false}')
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

  // Review Focus 4
  function test_a_save_reply_for_a_project_the_user_left_changes_nothing() {
    var store = makeWithProject(rootA); if (!store) return
    store.setNotifyOnEscalation(true)
    var save = store.settingsSaveRunner.current
    store.project = rootB
    reply(save, JSON.stringify({ ok: false, error: "x" }) + "\n", 1)
    compare(store.notifyOnEscalation, false)
    compare(store.notifySaved, false)
    compare(store.flashText, "", "no flash about A in B")
  }

  // 14
  function test_a_load_reply_after_the_user_toggled_is_ignored() {
    var store = makeWithProject(rootA); if (!store) return
    var load = store.settingsLoadRunner.current
    store.setNotifyOnEscalation(true)
    reply(load, runSettings(false), 0)
    compare(store.notifyOnEscalation, true)
  }

  // 15
  function test_without_a_project_the_switch_does_nothing() {
    var store = make(); if (!store) return
    compare(store.notifyOnEscalation, false)
    compare(store.notifySaved, false)
    compare(store.notifyTouched, false)
    compare(store.notifyRunners.length, 0)
    compare(store.setNotifyOnEscalation(true), false)
    compare(store.notifyOnEscalation, false)
    compare(store.notifyTouched, false)
    verify(!store.settingsSaveRunner.current, "nothing was launched")
    verify(!store.settingsLoadRunner.current, "nothing was loaded")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL — the new tests fail with `TypeError` on `store.settingsLoadRunner.current` / `store.notifyRunners.length` / `store.setNotifyOnEscalation`; Task 1's tests still pass.

- [ ] **Step 3: Write the implementation**

In `core/stores/RunStore.qml`:

(a) After Task 1's `property int toastMs: 8000` add:

```qml
  // "Notify on escalation", per project and off by default: the switch's
  // value, the last value read from or written to viewer-state.py, and
  // whether the user changed it since the project was selected (a late load
  // reply then changes nothing).
  property bool notifyOnEscalation: false
  property bool notifySaved: false
  property bool notifyTouched: false
```

(b) After Task 1's `readonly property alias toastTimer: toastTimer` add:

```qml
  readonly property alias settingsLoadRunner: settingsLoadRunner
  readonly property alias settingsSaveRunner: settingsSaveRunner
  readonly property alias notifyRunners: notifyState.runners    // in-flight notify.py launches, oldest first
```

(c) In `projectSwitched()`, replace (Task 1's version)

```qml
    store.alertsArmed = false
    store.toasts = []
    if (store.project !== "") store.refresh()
  }
```

with

```qml
    store.alertsArmed = false
    store.toasts = []
    // The switch reads off until this project's own reply. Notifications
    // already launched still run.
    store.notifyOnEscalation = false
    store.notifySaved = false
    store.notifyTouched = false
    settingsLoadRunner.guard = store.project
    if (store.project !== "") {
      store.refresh()
      settingsLoadRunner.run(["get-run-settings", store.project])
    }
  }
```

(d) In Task 1's `raiseAlerts`, replace

```qml
      while (next.length > 3) next.shift()
      store.toasts = next
    }
  }
```

with

```qml
      while (next.length > 3) next.shift()
      store.toasts = next
      if (store.notifyOnEscalation) store.notify(a)
    }
  }
```

and change the comment above `raiseAlerts` to:

```qml
  // One toast per alert, newest last: a run's older toast goes first, then the
  // oldest beyond three. With the setting on, each alert also notifies.
  // Called from applySnapshot only while active.
```

(e) After Task 1's `dismissAllToasts()` add:

```qml

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

  // get-run-settings: one bare object. Only a real true turns the switch on;
  // an unreadable reply leaves it off. Too late once the user changed it.
  function applyRunSettings(stdout, exitCode) {
    if (store.notifyTouched) return
    var settings = store.parseEnvelope(stdout)
    var on = settings !== null && settings.notifyOnEscalation === true
    store.notifyOnEscalation = on
    store.notifySaved = on
  }

  // set-run-settings: {"ok": true} means `sent` is stored; anything else puts
  // the switch back to what is stored and says so.
  function notifySaveReplied(stdout, exitCode, sent) {
    var reply = store.parseEnvelope(stdout)
    if (reply !== null && reply.ok === true) {
      store.notifySaved = sent
      return
    }
    store.notifyOnEscalation = store.notifySaved
    store.flash("Notify on escalation could not be saved")
  }
```

(f) After the `logsRunner` `HelperRunner { … }` block add:

```qml

  // get-run-settings on a project switch. Its guard is set by projectSwitched()
  // itself rather than bound to `project`: projectSwitched() runs from the
  // snapshot runner's guard change, before a binding here is sure to have
  // followed the project, and this launch must carry the NEW project.
  HelperRunner {
    id: settingsLoadRunner
    script: store.backendDir + "projects/viewer-state.py"
    onFinished: function(stdout, exitCode) { store.applyRunSettings(stdout, exitCode) }
  }

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

(g) After Task 1's `toastState` `QtObject { … }` add:

```qml

  // The notify.py runners in flight; kept apart so consumers cannot write it.
  QtObject {
    id: notifyState
    property var runners: []
  }
```

(h) After the `controlC` `Component { … }` block add:

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

(i) In `docs/architecture.md` line 95, replace (Task 1's sentence end)

```
Closing the panel and a project switch empty `toasts`.
```

with

```
Closing the panel and a project switch empty `toasts`. "Notify on escalation" is per project and off by default: a project switch resets `notifyOnEscalation` and reads `viewer-state.py get-run-settings` on `settingsLoadRunner` (its guard is set by `projectSwitched()` itself, so the launch carries the new project); `setNotifyOnEscalation(on)` flips it at once and writes `set-run-settings ROOT {"notifyOnEscalation": …}` on `settingsSaveRunner` (latest wins); a failed save puts the switch back to `notifySaved` and flashes `Notify on escalation could not be saved`, and a load reply that lands after the user changed the switch (`notifyTouched`) is ignored. With it on, every raised alert also runs `notify.py TITLE REASON` on a `HelperRunner` of its own (`notifyRunners`; dropped when it exits, its reply unread, not stopped by a project switch).
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: PASS — `Totals:` with `0 failed`, no error lines.

Then run the other suites that create a `RunStore` through `App`, to confirm the extra `get-run-settings` launch on project selection disturbs nothing:

Run: `bash tests/run.sh tests/ui`
Expected: PASS — every file `0 failed`, no error lines. If an existing test fails only because it now sees the `settingsLoadRunner` launch, cancel that runner in its setup (`<app>.runs.settingsLoadRunner.cancel()`), next to where it already cancels the snapshot runner; do not change its assertions.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml docs/architecture.md
git commit -m "feat(runs): RunStore keeps the per-project Notify on escalation setting and sends a desktop notification per alert on its own runner (card 22153f5f)"
```

---

### Task 3: `RunToast` component

**Files:**
- Create: `ui/components/RunToast.qml`
- Modify: `docs/architecture.md` (components list, after the `RunControls` entry, line ~144)
- Test: `tests/ui/components/tst_run_toast.qml` (create)

**Interfaces:**
- Consumes: the toast shape from Task 1 (`{key, id, title, state, reason, expiresMs}`); `RunGlyphs.glyphOf(state)` from `ui/components/runGlyphs.js`; `UI.ThemedText`, `UI.ActionButton`; `T.Theme` (`urgent`, `foreground`, …).
- Produces (Task 6 mounts it): `RunToast { toasts: var; theme: var }`, signals `openRequested(int key, string runId)` and `dismissRequested(int key)`. Item names `runToast<i>`, `runToastHeading<i>`, `runToastLine<i>`, `runToastReason<i>`, `runToastOpen<i>`, `runToastDismiss<i>` (i = position in `toasts`). A non-object entry, or one without a numeric `key`, emits key `-1`.

- [ ] **Step 1: Write the failing test**

Create `tests/ui/components/tst_run_toast.qml`:

```qml
// tests/ui/components/tst_run_toast.qml
// ui/components/RunToast.qml on its own, with plain toast objects and no
// store: what each card shows, the order of the stack, the two signals, and
// bad entries.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/components/runGlyphs.js" as RG
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "RunToast"
  when: windowShown
  visible: true
  width: 400; height: 500

  T.Theme { id: tcTheme; foreground: "#00ff00"; urgent: "#ff0000" }

  Component { id: toastC; UI.RunToast { theme: tcTheme } }
  SignalSpy { id: openSpy; signalName: "openRequested" }
  SignalSpy { id: dismissSpy; signalName: "dismissRequested" }

  // One RunStore toast.
  function toast(key, id, title, state, reason) {
    return { key: key, id: id, title: title, state: state, reason: reason, expiresMs: Date.now() + 8000 }
  }

  function make(list) {
    var c = createTemporaryObject(toastC, tc, { toasts: list })
    openSpy.target = c
    openSpy.clear()
    dismissSpy.target = c
    dismissSpy.clear()
    wait(20)
    return c
  }

  function part(c, name, i) { return H.find(c, name + i) }

  // Two clicks inside the double-click interval make the second a double-click.
  function tap(item) {
    wait(450)
    mouseClick(item)
  }

  // 16
  function test_no_toasts_no_cards() {
    var c = make([])
    compare(part(c, "runToast", 0), null)
    compare(c.visible, false)
    compare(c.height, 0)
  }

  // 17
  function test_an_escalated_and_a_dead_toast_read_as_the_mock() {
    var c = make([toast(1, "run-a", "M3", "escalated", "tests red after 3 attempts"),
                  toast(2, "run-b", "M4", "dead", "process died"),
                  toast(3, "run-c", "M5", "escalated", "")])
    compare(c.visible, true)
    compare(c.width, 320)
    compare(part(c, "runToastHeading", 0).text, "‼ Run needs you")
    compare(part(c, "runToastHeading", 0).text, RG.glyphOf("escalated") + " Run needs you")
    compare(String(part(c, "runToastHeading", 0).color), String(tcTheme.urgent))
    compare(part(c, "runToastLine", 0).text, "M3 escalated")
    compare(part(c, "runToastReason", 0).text, "tests red after 3 attempts")
    compare(part(c, "runToastReason", 0).visible, true)
    compare(String(part(c, "runToast", 0).border.color), String(tcTheme.urgent))
    compare(part(c, "runToastOpen", 0).text, "Open")
    compare(part(c, "runToastDismiss", 0).text, "Dismiss")
    compare(part(c, "runToastHeading", 1).text, "✖ Run needs you")
    compare(part(c, "runToastLine", 1).text, "M4 died")
    compare(part(c, "runToastReason", 1).text, "process died")
    compare(part(c, "runToastReason", 2).visible, false, "an empty reason hides its line")
  }

  // 18
  function test_three_toasts_stack_oldest_at_the_top() {
    var c = make([toast(1, "run-a", "A", "escalated", "r"), toast(2, "run-b", "B", "escalated", "r"),
                  toast(3, "run-c", "C", "dead", "process died")])
    compare(part(c, "runToastLine", 0).text, "A escalated")
    compare(part(c, "runToastLine", 1).text, "B escalated")
    compare(part(c, "runToastLine", 2).text, "C died")
    compare(part(c, "runToast", 3), null)
    verify(part(c, "runToast", 0).y < part(c, "runToast", 1).y, "oldest at the top")
    verify(part(c, "runToast", 1).y < part(c, "runToast", 2).y, "newest at the bottom")
    c.toasts = [toast(3, "run-c", "C", "dead", "process died")]
    wait(20)
    compare(part(c, "runToastLine", 0).text, "C died", "a new array re-renders")
    compare(part(c, "runToast", 1), null)
  }

  // 19
  function test_open_and_dismiss_emit_the_toasts_key_and_run() {
    var c = make([toast(7, "run-a", "A", "escalated", "r"), toast(9, "run-b", "B", "dead", "process died")])
    tap(part(c, "runToastOpen", 1))
    compare(openSpy.count, 1)
    compare(openSpy.signalArguments[0][0], 9)
    compare(openSpy.signalArguments[0][1], "run-b")
    compare(dismissSpy.count, 0, "Open does not dismiss by itself: the owner does")
    tap(part(c, "runToastDismiss", 0))
    compare(dismissSpy.count, 1)
    compare(dismissSpy.signalArguments[0][0], 7)
    compare(openSpy.count, 1)
  }

  // 20
  function test_bad_entries_render_without_throwing_and_keep_dismiss() {
    var c = make(["oops", toast(4, "run-x", "X", "bogus", "")])
    compare(part(c, "runToastHeading", 0).text, " Run needs you", "no glyph for a non-object")
    compare(part(c, "runToastLine", 0).text, " escalated")
    compare(part(c, "runToastReason", 0).visible, false)
    compare(part(c, "runToastDismiss", 0).visible, true)
    compare(part(c, "runToastHeading", 1).text, " Run needs you", "a state with no glyph")
    compare(part(c, "runToastLine", 1).text, "X escalated")
    tap(part(c, "runToastDismiss", 0))
    compare(dismissSpy.count, 1)
    compare(dismissSpy.signalArguments[0][0], -1, "an entry with no key dismisses key -1")
    var d = make(null)
    compare(d.visible, false)
    compare(part(d, "runToast", 0), null)
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/run.sh tst_run_toast`
Expected: FAIL — the file does not load (`RunToast is not a type`), so the run reports an error/`FAIL` for `RunToast` and exits 1.

- [ ] **Step 3: Write the implementation**

Create `ui/components/RunToast.qml`:

```qml
import QtQuick
import qs.Commons
import "runGlyphs.js" as RunGlyphs
import "../components" as UI
import "../theme" as T

// The run toasts: one card per run that newly needs a human, oldest at the
// top and newest at the bottom, closest to the corner the owner puts it in.
// Each card reads `‼ Run needs you` (or `✖` for a dead run, from runGlyphs.js)
// in `urgent`, `<title> escalated` or `<title> died`, the reason, and Open /
// Dismiss.
//
// Presentation only, like RunControls: it imports no store. The owner passes
// RunStore.toasts ({key, id, title, state, reason, expiresMs}, oldest first)
// and handles openRequested(key, runId) and dismissRequested(key); Open does
// not dismiss by itself. A bad entry still renders and still offers Dismiss
// (key -1). With no toasts it is hidden and 0 tall.
Column {
  id: stack

  property var theme: T.Theme {}
  property var toasts: []

  signal openRequested(int key, string runId)
  signal dismissRequested(int key)

  // Not Array.isArray: a list handed in through createObject's property map
  // (the component test) arrives as a QML list, for which Array.isArray is
  // false although length and indexing work, so every toast would vanish.
  readonly property int count: stack.toasts && typeof stack.toasts === "object" && typeof stack.toasts.length === "number"
    ? stack.toasts.length : 0

  // The entry at index, read back out of `toasts` (a Repeater would hand the
  // delegate a converted copy); {} when it is not an object.
  function entryOf(index) {
    var t = index >= 0 && index < stack.count ? stack.toasts[index] : null
    return t !== null && t !== undefined && typeof t === "object" ? t : {}
  }

  function textOf(value) { return typeof value === "string" ? value : "" }

  function keyOf(entry) { return typeof entry.key === "number" ? entry.key : -1 }

  function lineOf(entry) {
    return stack.textOf(entry.title) + (entry.state === "dead" ? " died" : " escalated")
  }

  width: Style.space(320)
  spacing: Style.space(6)
  visible: stack.count > 0

  Repeater {
    model: stack.count

    delegate: Rectangle {
      id: card
      required property int index
      readonly property var entry: stack.entryOf(card.index)

      objectName: "runToast" + card.index
      width: stack.width
      height: body.implicitHeight + Style.space(20)
      radius: Style.space(8)
      color: Color.popups.background
      border.width: 1
      border.color: stack.theme.urgent

      // Takes the clicks between the buttons, so none reaches what is under it.
      MouseArea { anchors.fill: parent }

      Column {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(10)
        spacing: Style.space(4)

        UI.ThemedText {
          objectName: "runToastHeading" + card.index
          theme: stack.theme
          width: parent.width
          text: RunGlyphs.glyphOf(card.entry.state) + " Run needs you"
          color: stack.theme.urgent
          font.bold: true
          elide: Text.ElideRight
        }

        UI.ThemedText {
          objectName: "runToastLine" + card.index
          theme: stack.theme
          width: parent.width
          text: stack.lineOf(card.entry)
          elide: Text.ElideRight
        }

        UI.ThemedText {
          objectName: "runToastReason" + card.index
          variant: "caption"
          theme: stack.theme
          width: parent.width
          visible: text !== ""
          text: stack.textOf(card.entry.reason)
          wrapMode: Text.WordWrap
        }

        Row {
          x: parent.width - width
          spacing: Style.space(6)

          UI.ActionButton {
            objectName: "runToastOpen" + card.index
            theme: stack.theme
            text: "Open"
            onClicked: stack.openRequested(stack.keyOf(card.entry), stack.textOf(card.entry.id))
          }

          UI.ActionButton {
            objectName: "runToastDismiss" + card.index
            theme: stack.theme
            text: "Dismiss"
            onClicked: stack.dismissRequested(stack.keyOf(card.entry))
          }
        }
      }
    }
  }
}
```

In `docs/architecture.md`, in the components list, replace

```
`runControlFacts.js` reads `pending`, `stillWaiting` and the control error for one run with own-key checks, for the owners),
```

with

```
`runControlFacts.js` reads `pending`, `stillWaiting` and the control error for one run with own-key checks, for the owners),
`RunToast` (the run toasts, oldest at the top: per toast `‼ Run needs you` or `✖ Run needs you` in `urgent` from `runGlyphs.js`, `<title> escalated` or `<title> died`, the reason, and Open / Dismiss `ActionButton`s; presentation only -- the owner passes `toasts` and handles `openRequested(key, runId)` and `dismissRequested(key)`, Open does not dismiss by itself; empty, it is hidden and 0 tall),
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_toast`
Expected: PASS — `Totals:` with `0 failed`, no error lines. (pytest runs first in the same command, which includes `tests/architecture`: it must stay green — no store import, no glyph literal, no guarded pattern in the new file.)

- [ ] **Step 5: Commit**

```bash
git add ui/components/RunToast.qml tests/ui/components/tst_run_toast.qml docs/architecture.md
git commit -m "feat(runs): RunToast shows each run that needs you with Open and Dismiss (card 22153f5f)"
```

---

### Task 4: `Shortcuts` — Escape dismisses the toasts

**Files:**
- Modify: `ui/Shortcuts.qml:38-41` (`closeRequested`) and `:95-101` (`handleSearchKey`'s Escape branch)
- Modify: `docs/architecture.md` (the `Shortcuts.qml` sentence, lines ~97-103)
- Test: `tests/ui/tst_shortcuts.qml` (append before the file's final `}`)

**Interfaces:**
- Consumes: Task 1's `app.runs.toasts`, `app.runs.raiseAlerts(alerts)`, `app.runs.dismissAllToasts()`. Test fixtures already in the file: `inRunKeys()` (Runs list of project A, rows `run-0000000000a1` running and `run-0000000000b2` parked, cursor 0), `plain(key)`, `ctrl(key)`, `tc.calls` (records `"close"` when the panel is asked to close).
- Produces: nothing new; `modalOpen()` unchanged.

- [ ] **Step 1: Write the failing tests**

Append inside the `TestCase` of `tests/ui/tst_shortcuts.qml`, after `test_without_a_project_the_run_keys_are_left_alone`:

```qml

  // ---- run toasts (S2 4.4)

  function alertOf(id) { return { id: id, title: "m", state: "escalated", reason: "escalated" } }

  // 21
  function test_escape_dismisses_the_toasts_before_going_back_from_a_run() {
    var s = inRunKeys(); if (!s) return
    s.navigator.openRun("run-0000000000a1")
    compare(s.app.nav.viewMode, "run")
    s.app.runs.raiseAlerts([alertOf("run-0000000000a1"), alertOf("run-0000000000b2")])
    compare(s.app.runs.toasts.length, 2)
    s.closeRequested()
    compare(s.app.runs.toasts.length, 0)
    compare(s.app.nav.viewMode, "run", "that Escape went to the toasts")
    s.closeRequested()
    compare(s.app.nav.viewMode, "runs", "the next one goes back as before")
    compare(tc.calls.indexOf("close"), -1)
  }

  // Review Focus 5
  function test_escape_on_the_board_dismisses_the_toasts_and_keeps_the_panel_open() {
    var s = inRunKeys(); if (!s) return
    s.navigator.showSection("board")
    s.app.runs.raiseAlerts([alertOf("run-0000000000a1")])
    s.closeRequested()
    compare(s.app.runs.toasts.length, 0)
    compare(tc.calls.indexOf("close"), -1, "the panel stays open")
    compare(s.app.nav.viewMode, "board")
    s.closeRequested()
    verify(tc.calls.indexOf("close") !== -1, "with no toast left Escape closes the panel as before")
  }

  // 22
  function test_the_cancel_dialog_closes_before_the_toasts() {
    var s = inRunKeys(); if (!s) return
    s.app.runs.raiseAlerts([alertOf("run-0000000000b2")])
    compare(s.app.runs.openCancel("run-0000000000a1"), true)
    s.closeRequested()
    compare(s.app.runs.cancelOpen, false)
    compare(s.app.runs.toasts.length, 1, "the toasts stay")
    s.closeRequested()
    compare(s.app.runs.toasts.length, 0)
    compare(s.app.nav.viewMode, "runs")
    compare(tc.calls.indexOf("close"), -1)
  }

  // 23
  function test_escape_in_the_search_field_dismisses_the_toasts_first() {
    var s = inRunKeys(); if (!s) return
    s.app.nav.searchQuery = "x"
    s.app.runs.raiseAlerts([alertOf("run-0000000000a1")])
    var e = plain(Qt.Key_Escape)
    s.handleSearchKey(e)
    compare(e.accepted, true)
    compare(s.app.runs.toasts.length, 0)
    compare(s.app.nav.searchQuery, "x", "the search is kept")
    compare(tc.calls.indexOf("close"), -1)
    s.handleSearchKey(plain(Qt.Key_Escape))
    compare(s.app.nav.searchQuery, "", "the next Escape clears the search")
    compare(tc.calls.indexOf("close"), -1)
    s.app.runs.raiseAlerts([alertOf("run-0000000000a1")])
    var e2 = plain(Qt.Key_Escape)
    s.handleSearchKey(e2)
    compare(e2.accepted, true)
    compare(s.app.runs.toasts.length, 0)
    compare(tc.calls.indexOf("close"), -1, "an empty search with toasts showing does not close the panel")
  }

  // 24
  function test_toasts_are_not_a_modal() {
    var s = inRunKeys(); if (!s) return
    s.navigator.showSection("board")
    s.app.runs.raiseAlerts([alertOf("run-0000000000a1")])
    compare(s.modalOpen(), false)
    compare(s.handleGlobalKey(ctrl(Qt.Key_6)), true)
    compare(s.app.nav.viewMode, "runs")
    s.app.nav.cursorIndex = 0
    compare(s.handleRunKey(plain(Qt.Key_P)), true)
    compare(s.app.runs.pending["run-0000000000a1"], "pause")
    compare(s.app.runs.toasts.length, 1, "the keys leave the toasts alone")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_shortcuts`
Expected: FAIL — `test_escape_dismisses_the_toasts_before_going_back_from_a_run` (toasts still 2, view went back), `test_escape_on_the_board_…` (`close` called), `test_the_cancel_dialog_closes_before_the_toasts` (second Escape leaves the toast), `test_escape_in_the_search_field_dismisses_the_toasts_first` (search cleared instead). `test_toasts_are_not_a_modal` already passes.

- [ ] **Step 3: Write the implementation**

In `ui/Shortcuts.qml`, replace

```qml
  // Escape (and the key catcher's close gesture): innermost thing first.
  function closeRequested() {
    keys.app.deleter.deleteTarget ? keys.app.deleter.cancelDelete() : keys.app.board.archiveOpen ? keys.app.board.cancelArchive() : keys.app.memories.memoryDeleteOpen ? keys.app.memories.cancelMemoryDelete() : keys.app.memories.newMemoryOpen ? keys.app.memories.cancelNewMemory() : keys.app.milestones.dialogOpen ? keys.app.milestones.cancelDialog() : keys.app.runs.cancelOpen ? keys.app.runs.closeCancel() : (keys.app.nav.dropdownOpen ? keys.navigator.closeDropdown() : ((keys.app.nav.viewMode === "entry" || keys.app.nav.viewMode === "document" || keys.app.nav.viewMode === "memory" || keys.app.nav.viewMode === "issue" || keys.app.nav.viewMode === "run") ? keys.navigator.goBack() : keys.actions.close()))
  }
```

with

```qml
  // Escape (and the key catcher's close gesture): innermost thing first. The
  // run toasts come right after the modals: they are not a modal, but an
  // Escape with toasts showing never goes Back or closes the panel.
  function closeRequested() {
    keys.app.deleter.deleteTarget ? keys.app.deleter.cancelDelete() : keys.app.board.archiveOpen ? keys.app.board.cancelArchive() : keys.app.memories.memoryDeleteOpen ? keys.app.memories.cancelMemoryDelete() : keys.app.memories.newMemoryOpen ? keys.app.memories.cancelNewMemory() : keys.app.milestones.dialogOpen ? keys.app.milestones.cancelDialog() : keys.app.runs.cancelOpen ? keys.app.runs.closeCancel() : keys.app.runs.toasts.length > 0 ? keys.app.runs.dismissAllToasts() : (keys.app.nav.dropdownOpen ? keys.navigator.closeDropdown() : ((keys.app.nav.viewMode === "entry" || keys.app.nav.viewMode === "document" || keys.app.nav.viewMode === "memory" || keys.app.nav.viewMode === "issue" || keys.app.nav.viewMode === "run") ? keys.navigator.goBack() : keys.actions.close()))
  }
```

and replace

```qml
  function handleSearchKey(event) {
    if (event.key === Qt.Key_Escape) {
      if (keys.app.nav.searchQuery !== "") { keys.app.nav.searchQuery = "" }
      else keys.actions.close()
```

with

```qml
  // The search field's keys. Its Escape does not go through closeRequested():
  // the run toasts go first, then a non-empty search, then the panel.
  function handleSearchKey(event) {
    if (event.key === Qt.Key_Escape) {
      if (keys.app.runs.toasts.length > 0) keys.app.runs.dismissAllToasts()
      else if (keys.app.nav.searchQuery !== "") { keys.app.nav.searchQuery = "" }
      else keys.actions.close()
```

In `docs/architecture.md` (the `Shortcuts.qml` sentence), replace

```
chords and the run keys obey, and Escape closes the cancel confirmation before
the dropdown), `theme/Theme.qml` (colours and fonts from the shell).
```

with

```
chords and the run keys obey, and Escape closes the cancel confirmation, then
dismisses the run toasts, before the dropdown; in the search field Escape
dismisses the toasts before it clears the search or closes the panel -- a toast
is not a modal, so it never blocks the chords or the run keys),
`theme/Theme.qml` (colours and fonts from the shell).
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_shortcuts`
Expected: PASS — `Totals:` with `0 failed`, no error lines.

- [ ] **Step 5: Commit**

```bash
git add ui/Shortcuts.qml tests/ui/tst_shortcuts.qml docs/architecture.md
git commit -m "feat(runs): Escape dismisses the run toasts after any modal and before going back, clearing the search or closing the panel (card 22153f5f)"
```

---

### Task 5: Runs screen — the Notify on escalation switch

**Files:**
- Modify: `ui/screens/RunsScreen.qml:1-7` (imports) and between `FilterableList` (ends line 114) and `runsFooter` (line 116)
- Modify: `docs/architecture.md:157` (run screens paragraph)
- Test: `tests/ui/screens/tst_runs_screen.qml` (stub at lines 44-52; append before the file's final `}`)

**Interfaces:**
- Consumes: Task 2's `app.runs.notifyOnEscalation` and `app.runs.setNotifyOnEscalation(on)`; `ToggleSwitch` from `qs.Ui` (`checked`, `signal toggled()`; stub `tests/stubs/qs/Ui/ToggleSwitch.qml`).
- Produces: items `runsNotifyRow` (Row), `runsNotifyToggle` (ToggleSwitch), `runsNotifyLabel` (ThemedText).

- [ ] **Step 1: Write the failing test**

In `tests/ui/screens/tst_runs_screen.qml`, inside the `runsC` stub `QtObject`, replace

```qml
      property var controlCalls: []
      function control(action, id) {
        rs.controlCalls = rs.controlCalls.concat([action + "|" + id])
        return true
      }
    }
  }
```

with

```qml
      property var controlCalls: []
      function control(action, id) {
        rs.controlCalls = rs.controlCalls.concat([action + "|" + id])
        return true
      }
      // The Notify on escalation switch (S2 4.4). `setNotifyOnEscalation`
      // only records.
      property bool notifyOnEscalation: false
      property var notifyCalls: []
      function setNotifyOnEscalation(on) {
        rs.notifyCalls = rs.notifyCalls.concat([on])
        return true
      }
    }
  }
```

Then append inside the `TestCase`, after `test_a_flash_takes_the_footer_and_then_gives_it_back`:

```qml

  // ---- the Notify on escalation switch (S2 4.4)

  // 25
  function test_the_notify_switch_reads_and_asks_the_store() {
    var s = make(sample()); if (!s) return
    var row = H.find(s.screen, "runsNotifyRow")
    var toggle = H.find(s.screen, "runsNotifyToggle")
    verify(row, "the switch row")
    verify(toggle, "the switch")
    compare(H.find(s.screen, "runsNotifyLabel").text, "Notify on escalation")
    compare(toggle.checked, false)
    s.runs.notifyOnEscalation = true
    compare(toggle.checked, true)
    s.runs.notifyOnEscalation = false
    compare(toggle.checked, false)
    toggle.toggled()
    compare(s.runs.notifyCalls.join(","), "true", "asked once, for the flipped value")
    compare(toggle.checked, false, "the store decides; this stub did not flip it")
    compare(row.visible, true)
    verify(row.y < H.find(s.screen, "runsFooter").y, "above the footer")
    s.runs.amStatus = "missing"
    wait(20)
    compare(row.visible, true, "the setting is the project's, not am's")
  }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/run.sh tst_runs_screen`
Expected: FAIL — `test_the_notify_switch_reads_and_asks_the_store` (`the switch row` — `runsNotifyRow` not found). The other tests still pass.

- [ ] **Step 3: Write the implementation**

In `ui/screens/RunsScreen.qml`, replace

```qml
import QtQuick
import qs.Commons
import "../../core/domain/runs.js" as Runs
```

with

```qml
import QtQuick
import qs.Commons
import qs.Ui
import "../../core/domain/runs.js" as Runs
```

and replace

```qml
  // The watch line, or why the last run key was refused while that flash
  // lasts; a flash shows even where the footer is otherwise hidden.
  UI.ThemedText {
    objectName: "runsFooter"
```

with

```qml
  // The project's Notify on escalation setting: a desktop notification for
  // every run toast. Shown even while am is missing -- it is the project's.
  Row {
    objectName: "runsNotifyRow"
    spacing: Style.space(8)

    ToggleSwitch {
      objectName: "runsNotifyToggle"
      anchors.verticalCenter: parent.verticalCenter
      checked: screen.app.runs.notifyOnEscalation
      onToggled: screen.app.runs.setNotifyOnEscalation(!screen.app.runs.notifyOnEscalation)
    }

    UI.ThemedText {
      objectName: "runsNotifyLabel"
      anchors.verticalCenter: parent.verticalCenter
      variant: "caption"
      theme: screen.theme
      text: "Notify on escalation"
    }
  }

  // The watch line, or why the last run key was refused while that flash
  // lasts; a flash shows even where the footer is otherwise hidden.
  UI.ThemedText {
    objectName: "runsFooter"
```

In `docs/architecture.md` (run screens paragraph, line 157), replace

```
With am missing the list shows `am is not installed or not on PATH`.
```

with

```
With am missing the list shows `am is not installed or not on PATH`. Directly above the footer a `ToggleSwitch` reads `Notify on escalation` (`app.runs.notifyOnEscalation`, changed through `setNotifyOnEscalation`), shown also while am is missing: the setting is the project's.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_runs_screen`
Expected: PASS — `Totals:` with `0 failed`, no error lines (in particular no `Unable to assign` from the switch's binding).

- [ ] **Step 5: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml docs/architecture.md
git commit -m "feat(runs): the Runs screen carries the project's Notify on escalation switch above its footer (card 22153f5f)"
```

---

### Task 6: Panel — mount `RunToast`, Open and Dismiss

**Files:**
- Modify: `ui/Panel.qml` (a function after `displayPath` at line ~221; the `RunToast` before the `// Delete confirmation: …` comment at line ~600)
- Modify: `docs/architecture.md:157` (run screens paragraph)
- Test: `tests/ui/tst_runs_flow.qml` (`make()` lines 26-47; append before the file's final `}`)

**Interfaces:**
- Consumes: Task 3's `RunToast` (`toasts`, `theme`, `openRequested(key, runId)`, `dismissRequested(key)`); Task 1's `appStores.runs.toasts`, `dismissToast(key)`; Task 2's `settingsLoadRunner`, `settingsSaveRunner`, `setNotifyOnEscalation`, `notifyRunners`, `notifySaved`; `navi.showSection(name)`, `navi.openRun(id, from)`, `appStores.runs.runById(id)`, `appStores.runs.flash(text)`.
- Produces: `Panel.openToastRun(key, runId)`; the item `runToast` (the mounted `RunToast`).

- [ ] **Step 1: Write the failing tests**

In `tests/ui/tst_runs_flow.qml`, in `make()`, replace

```qml
    // Selecting the project starts a `brd export` and a runs snapshot that
    // cannot run here: both are disarmed so their late replies change nothing.
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.extras.extrasLoading = false
    p.app.runs.snapshotRunner.cancel()
```

with

```qml
    // Selecting the project starts a `brd export`, a runs snapshot and a run
    // settings read that cannot run here: all three are disarmed so their late
    // replies change nothing.
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.extras.extrasLoading = false
    p.app.runs.snapshotRunner.cancel()
    p.app.runs.settingsLoadRunner.cancel()
```

Then append inside the `TestCase`, after `test_a_cards_runs_row_cancel_opens_the_same_dialog_and_keep_running_closes_it`:

```qml

  // ---- run toasts (S2 4.4)

  // The next snapshot of project A lists `entries`.
  function feed(p, entries) {
    p.app.runs.refresh()
    reply(p.app.runs.snapshotRunner.current, snapOk(entries), 0)
  }

  // On `view`: a baseline snapshot (it only arms the alerts), then one where
  // beta (b2) has escalated -- one toast.
  function withToast(view) {
    var p = make(); if (!p) return null
    p.navigator.showSection(view)
    feed(p, [snapEntry("run-0000000000a1", "started", true, "alpha"), snapEntry("run-0000000000b2", "started", true, "beta")])
    compare(p.app.runs.toasts.length, 0, "the baseline raises nothing")
    feed(p, [snapEntry("run-0000000000a1", "started", true, "alpha"), snapEntry("run-0000000000b2", "escalated", null, "beta")])
    compare(p.app.runs.toasts.length, 1)
    wait(50)
    return p
  }

  // 26 (parent line 160: toast Open navigates)
  function test_toast_open_navigates_to_the_run_and_back_goes_to_the_runs_list() {
    var p = withToast("board"); if (!p) return
    compare(p.app.nav.viewMode, "board")
    var toast = H.find(p, "runToast0")
    verify(toast, "the toast card")
    compare(toast.visible, true)
    compare(H.find(p, "runToastLine0").text, "beta escalated")
    var kc = H.find(p, "keyCatcher")
    var pt = toast.mapToItem(kc, 0, 0)
    verify(pt.x + toast.width <= kc.width && pt.x + toast.width >= kc.width - 40, "against the right edge")
    verify(pt.y + toast.height <= kc.height && pt.y + toast.height >= kc.height - 40, "against the bottom edge")
    mouseClick(H.find(p, "runToastOpen0"))
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000b2")
    compare(p.app.runs.toasts.length, 0, "Open dismisses its toast")
    p.shortcuts.closeRequested()
    compare(p.app.nav.viewMode, "runs", "Back lands on the Runs list")
    compare(p.opened, true)
  }

  // 27 (Review focus: the search field's Escape does not go through closeRequested)
  function test_escape_in_the_empty_runs_search_dismisses_the_toast_and_keeps_the_panel_open() {
    var p = withToast("runs"); if (!p) return
    var field = H.find(p, "searchField")
    field.forceActiveFocus()
    compare(field.text, "")
    keyClick(Qt.Key_Escape)
    compare(p.app.runs.toasts.length, 0)
    compare(p.opened, true, "the panel stays open")
    compare(p.app.nav.viewMode, "runs")
  }

  // 28
  function test_dismiss_removes_only_that_toast() {
    var p = withToast("runs"); if (!p) return
    feed(p, [snapEntry("run-0000000000a1", "started", false, "alpha"), snapEntry("run-0000000000b2", "escalated", null, "beta")])
    compare(p.app.runs.toasts.length, 2)
    wait(50)
    mouseClick(H.find(p, "runToastDismiss0"))
    compare(p.app.runs.toasts.length, 1)
    compare(p.app.runs.toasts[0].id, "run-0000000000a1")
    wait(50)
    compare(H.find(p, "runToastLine0").text, "alpha died")
  }

  // 29
  function test_with_the_setting_on_an_escalation_also_notifies() {
    var p = make(); if (!p) return
    compare(p.app.runs.setNotifyOnEscalation(true), true)
    reply(p.app.runs.settingsSaveRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
    compare(p.app.runs.notifySaved, true)
    feed(p, [snapEntry("run-0000000000b2", "started", true, "beta")])
    feed(p, [snapEntry("run-0000000000b2", "escalated", null, "beta")])
    compare(p.app.runs.notifyRunners.length, 1)
    var cmd = p.app.runs.notifyRunners[0].current.command
    compare(cmd[1], p.pluginDir + "core/backend/runs/notify.py")
    compare(cmd[cmd.length - 2], "beta")
    compare(cmd[cmd.length - 1], "escalated")
    p.app.runs.setNotifyOnEscalation(false)
    reply(p.app.runs.settingsSaveRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
    feed(p, [snapEntry("run-0000000000b2", "escalated", null, "beta"), snapEntry("run-0000000000c3", "escalated", null, "gamma")])
    compare(p.app.runs.toasts.length, 2)
    compare(p.app.runs.notifyRunners.length, 1, "off: no new launch")
  }

  // 30
  function test_open_on_a_toast_whose_run_left_the_snapshot_flashes_why() {
    var p = withToast("board"); if (!p) return
    feed(p, [snapEntry("run-0000000000a1", "started", true, "alpha")])
    compare(p.app.runs.toasts.length, 1, "the toast outlives its run's row")
    wait(50)
    mouseClick(H.find(p, "runToastOpen0"))
    compare(p.app.runs.toasts.length, 0)
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.runs.selectedRunId, "")
    compare(H.find(p, "runsFooter").text, "This run is no longer in the snapshot")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_runs_flow`
Expected: FAIL — tests 26, 28 and 30 fail (`the toast card`, or a `TypeError` on `null`: there is no `runToast0` in the panel yet). Tests 27 and 29 already pass: they pin Task 2's and Task 4's behaviour through the whole panel and stay as guards. The existing tests still pass.

- [ ] **Step 3: Write the implementation**

In `ui/Panel.qml`, after

```qml
  function displayPath(path) {
    return String(path || "").replace(/^\/home\/[^\/]+/, "~")
  }
```

add

```qml

  // A toast's Open: the toast goes, then the run opens from the Runs list, so
  // Back lands there whichever view the toast was clicked on (openRun keeps
  // the cursor it is opened from). A run that has left the snapshot cannot
  // open -- openRun would refuse silently -- so the list says why instead.
  function openToastRun(key, runId) {
    appStores.runs.dismissToast(key)
    navi.showSection("runs")
    if (appStores.runs.runById(runId) === null) {
      appStores.runs.flash("This run is no longer in the snapshot")
      return
    }
    navi.openRun(runId, "runs")
  }
```

and replace

```qml
      // Delete confirmation: the shared typed-word modal, driven by the store.
      TypedConfirmDialog {
        id: deleteModal
```

with

```qml
      // The run toasts (S2 4.4), bottom right over the screens. A sibling of
      // the dialogs below, so their z: 100 outranks this z: 50: an open
      // dialog's backdrop covers the toasts and takes their clicks.
      RunToast {
        id: runToast
        objectName: "runToast"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(12)
        z: 50
        theme: panelTheme
        toasts: appStores.runs.toasts
        onDismissRequested: function(key) { appStores.runs.dismissToast(key) }
        onOpenRequested: function(key, runId) { root.openToastRun(key, runId) }
      }

      // Delete confirmation: the shared typed-word modal, driven by the store.
      TypedConfirmDialog {
        id: deleteModal
```

In `docs/architecture.md` (run screens paragraph, line 157), replace

```
or in Run detail's `runDetailFlash` line, the last line of the run's body.
```

with

```
or in Run detail's `runDetailFlash` line, the last line of the run's body. Panel mounts one `RunToast` (`runToast`) at the bottom right of its content, `z: 50` -- above the screens, below the dialogs, whose backdrop covers it: Dismiss calls `dismissToast(key)`; Open dismisses the toast, shows the Runs section and opens the run from there, so Back lands on the Runs list -- or, for a run that has left the snapshot, stays on the list and flashes `This run is no longer in the snapshot`.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_runs_flow`
Expected: PASS — `Totals:` with `0 failed`, no error lines.

- [ ] **Step 5: Run the whole suite**

Run: `bash tests/run.sh`
Expected: pytest passes (including `tests/architecture`), every QML file reports `0 failed`, no error lines, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add ui/Panel.qml tests/ui/tst_runs_flow.qml docs/architecture.md
git commit -m "feat(runs): the panel shows the run toasts bottom right; Open goes to the run through the Runs list, Dismiss drops one (card 22153f5f)"
```

---

## Self-review against the spec

**Spec coverage.**
- D1 (RunStore owns alerts, no App change): Tasks 1-2; App untouched.
- D2 (armed baseline; disarm on `startLive`, `stopLive`, `projectSwitched`, AmMissing; failures keep it): Task 1 (c)(d)(e)(f); tests 2, 4, 5, 10.
- D3 (raise only while active; late snapshot does not arm): Task 1 (f); test 1, Review Focus 1; notification half in Task 2.
- D4 (toast shape, growing key, one per run, cap 3, replaced arrays, `expireToasts`, `toastTimer` 250 ms only while active with toasts, emptied on close and switch): Task 1; tests 2, 6, 7, 8, 9, 10.
- D5 (notify per alert on its own runner, argv, reply unread, guard `""`, both escalated and dead): Task 2 (d)(e)(h); test 12 and the closed-panel test.
- D6 (load on switch, `notifyTouched`, save with revert + flash, guards): Task 2; tests 10, 11, 13, 14, 15, Review Focus 3, 4. The load runner's guard is set imperatively in `projectSwitched()` (documented in the code) so the launch carries the new project — test 10 pins `launchGuard`.
- D7 (RunToast presentation, names, texts, colours, bad entries): Task 3; tests 16-20.
- D8 (Panel mount bottom right, z 50 sibling of dialogs, Open/Dismiss, vanished run flash): Task 6; tests 26, 28, 30.
- D9 (Escape order in both key paths; `modalOpen` unchanged): Task 4; tests 21-24, Review Focus 5; flow test 27.
- D10 (switch above footer, visible while am missing, `import qs.Ui`): Task 5; test 25.
- Docs (RunStore paragraph, components list, Shortcuts sentence, run screens paragraph, refresh model): Tasks 1-6 step 3.
- Spec "Review focus" bullet 5 (existing tests now see `settingsLoadRunner`): Task 2 Step 4 runs `tests/ui` and says how to adjust; Task 6 adds the cancel to the flow `make()`; the store's timer inventory is updated in Task 1.

**Placeholder scan.** No TBD/TODO; every code step carries the code.

**Type consistency.** `toasts`, `toastMs`, `alertsArmed`, `toastTimer`, `raiseAlerts`, `expireToasts`, `dismissToast`, `dismissAllToasts`, `notifyOnEscalation`, `notifySaved`, `notifyTouched`, `setNotifyOnEscalation`, `applyRunSettings`, `notifySaveReplied`, `settingsLoadRunner`, `settingsSaveRunner`, `notifyRunners`, `openRequested(int key, string runId)`, `dismissRequested(int key)`, `openToastRun(key, runId)` — same names in every task that uses them.
<!-- task-pipeline: validated -->
