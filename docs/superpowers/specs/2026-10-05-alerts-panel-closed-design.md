# Alerts while the panel is closed — design

Status: proposed. Builds on the controls spec (`2026-10-03-am-run-controls-design.md`, S2:
toasts, `notify.py`, `Runs.newAlerts`) and global runs
(`2026-10-05-runs-all-projects-design.md`, S6: one viewer-wide notify switch in
`viewer-state.py get-global-settings` / `set-global-settings`, per-project arming). Written
against the stores as the "Split RunStore" milestone leaves them (`RunStore`,
`RunControlStore`, `RunAlertsStore`, `RunDispatchStore`); `am` test data comes from the
fixtures under `tests/fixtures/am/` recorded by "Align the run model with real am".

## Problem

Alerts only work while the panel is open. `RunStore.stopLive()` stops the watch, the
debounce, the poll and the stale timer when `active` goes false
(`core/stores/RunStore.qml:151-163`), alerts are raised only while `active`
(`RunStore.qml:455-460`), and the S2 spec says so itself ("desktop alerts fire only while
it is open", Open questions). A run that escalates while the panel is closed — the usual
case, a run takes hours — tells nobody. A hub whose escalation alert dies when you close
the panel is not a hub.

## How the plugin lives in the shell (verified on this machine)

The shell is `quickshell -n -p /usr/share/omarchy/shell` (launched by
`omarchy-launch-shell`; `~/.local/share/omarchy` links to `/usr/share/omarchy`).

1. **The bar widget, and everything in it, runs while the panel is closed.** Each monitor
   gets its own bar (`plugins/bar/Bar.qml:1196-1205`, `Variants { model:
   Quickshell.screens … BarPanel }`), and each bar loads the widget eagerly as soon as the
   registry has it (`Bar.qml:1850-1858`, `Loader { active: slot.registered … }`). Closing
   the panel destroys nothing: `Ui/Panel.qml:24-25` `open()` / `close()` only flip
   `panelController.open`, and `Ui/KeyboardPanel.qml:81` only hides the window
   (`visible: open || card.opacity > 0 || popoutSwitching`). So `Core.App` in
   `ui/Panel.qml:45` and every store, `Process` and `Timer` in it keep running; they idle
   today only because of the `panelOpen: root.opened` gate.
2. **There is one widget instance PER MONITOR** (possibly a placeholder more for a center
   placement, `Bar.qml:739-740`). Only one instance has `opened` true, which is why today's
   alerts are not duplicated. Running the watch in the widget while closed would raise one
   desktop notification per monitor.
3. **The shell has a non-visual plugin kind: `service`.** `shell.qml:268-274` ("Generic
   loader for any enabled plugin that declares kind "service""), `ensureService()`
   (`shell.qml:892-942`) creates it ONCE with `Qt.createComponent(url)` /
   `createObject(null)` (no visual parent) and injects `shell` and `manifest` when the
   object declares them; `_syncServices()` (`shell.qml:944-1000`) creates it for every
   enabled plugin whose `kinds` contain `service` and destroys it when the plugin is
   disabled or removed. A plugin may combine kinds: `omarchy.media` is
   `["service", "bar-widget"]` with `entryPoints.service` and `entryPoints.barWidget`
   (`plugins/services/media/manifest.json`). A third-party plugin is enabled when its entry
   is placed in the bar layout (`services/PluginRegistry.qml:150-163`), which `install.sh`
   does (`omarchy plugin enable`).
4. **Lifetime of a service.** Created at shell start (and on a plugin rescan); destroyed on
   plugin hot reload (`reloadPlugins`, triggered by `omarchy-shell shell rescanPlugins` and
   by the inotify watcher on `~/.config/omarchy/plugins`) unless the manifest has
   `keepLoaded: true` (`shell.qml:1015-1041`). `omarchy-restart-shell` kills and relaunches
   the whole quickshell process, so all plugin state is lost.
5. **The manifest's `"activation": "on-demand"` is read by nothing.** No shell code reads
   `activation`; `PluginRegistry.validateManifest` requires only `id, name, version, kinds,
   entryPoints` (`PluginRegistry.qml:52`).
6. **The shell is the notification daemon.** `omarchy.notifications` declares a
   `NotificationServer` (`plugins/notifications/Service.qml:975`); no mako/dunst runs.
   `notify-send` from a plugin process reaches the shell's own notifications, so a watcher
   outside the shell gains nothing while the shell is down.
7. **Idle cost of the signal.** `am watch --all --follow --from-now` measured here: about
   46 MB RSS and no measurable CPU over 18 s with two runs writing. Its hello line is
   `{"am":"0.1.0","event":"watch","runs_dir":…,"schema":1}`. Every `run_upsert` journal
   line carries the whole run (`status`, `repo_dir`, `id`, …), so an escalation is visible
   in the journal itself. A process that dies writes nothing: `dead` (a `started` run whose
   lease is not live) is only visible through `am runs` / `am status` (`lease.live`).

## Decision

**The plugin declares a `service` and the service owns desktop notifications, panel open or
closed.** `manifest.json` gets `"kinds": ["bar-widget", "service"]` and
`"entryPoints": {"barWidget": "ui/Panel.qml", "service": "core/stores/RunAlertsService.qml"}`.
The shell creates one instance; it runs one small helper that turns the global journal into
alert lines, and calls `notify.py`. The panel keeps its toasts (they need the panel) and
stops sending desktop notifications itself, so an alert is notified exactly once whatever
the number of monitors and whether the panel is open.

No external process is needed (see Open for the rejected alternative).

## Behaviour

- **What alerts:** a run of a REGISTERED project (`brd projects`) that turns `escalated`
  (seen in the journal) or `dead` (seen by the lease poll), the same two transitions as
  `Runs.newAlerts`. One notification per run and state; a run that is resumed and escalates
  again alerts again.
- **What it says:** title `‼ <run title> escalated · <project>` or `✖ <run title> died ·
  <project>`, body the reason (`Runs.escalationReason`, `process died` for a dead run),
  from ONE snapshot of that run's project taken when the alert line arrives
  (`runs-snapshot.py <root>`, not a fan-out). If that snapshot fails the notification still
  goes out with the short run id and `escalated` / `process died`.
- **The switch:** the viewer-wide notify switch (S6, `get-global-settings`
  `notifyOnEscalation`) decides. The service reads it when an alert arrives, so a change in
  the panel takes effect at the next alert with no messaging between the panel and the
  service. Off means the alert is dropped.
- **No replay:** the helper follows the journal with `--from-now`, so a shell start, a
  restart or a plugin reload never notifies history. A run that escalated while the shell
  was down is not notified (the panel's Needs attention still shows it).
- **Arming:** the helper reads `am runs --repo-dir R` once per registered root at start, to
  know which runs are live; only transitions observed after that are alerts. A root whose
  read fails is learned from the journal alone (its runs can still escalate; a dead run is
  noticed once a later poll succeeds).
- **Dead detection:** while the helper knows of at least one `started` run, it re-reads
  `am runs --repo-dir R` every 60 s for the roots that have one; a `started` run whose
  lease is not live alerts `dead` once. With no started run it polls nothing.
- **The panel:** `RunAlertsStore` keeps raising toasts while the panel is open (S2/S6,
  unchanged) but no longer runs `notify.py`. The Runs screen's switch reads `Desktop
  notifications` with the caption `From the background, panel open or closed`.

## Architecture

- `core/backend/runs/runs-alerts.py` (long-lived, no arguments): reads the registry with
  `brd projects` (again whenever an alert candidate names a root it does not know, so a
  newly registered project needs no restart), seeds from `am runs` per root, follows `am
  watch --all --follow --from-now`, accepts a hello schema of 1 or 2, keeps per run its last
  status and `repo_dir` from `run_upsert` (`cancelled` and `canceled` both terminal), and
  prints one JSON line per alert, flushed at once:
  `{"alert": {"run_id", "root", "project", "state": "escalated"|"dead"}}`. It ends with an
  `AmMissing`, `SchemaMismatch`, `CorruptJournal` or `HelperError` envelope (exit 1), exit 0
  when stopped (SIGTERM). Only documented `am` and `brd` commands, as argv lists.
- `core/domain/runs.js`: `alertNotification(run, state, project, runId)` → `{title, body}`:
  the wording above from a normalized run (or null run: the short id fallback).
- `core/stores/RunAlertsService.qml`: the service entry point, a store like the others
  (only `QtQml`, `Quickshell`, `Quickshell.Io`, `../domain`), but composed by the shell, not
  by `App.qml`. It derives `backendDir` from its own URL. It runs `runs-alerts.py` as a plain
  `Process`; on an alert line it reads `get-global-settings`, and when on takes the
  project snapshot and runs `notify.py` (one `HelperRunner` per launch, as `notifyRunners`
  today). Restart policy: the helper exiting with `AmMissing` or `HelperError` is relaunched
  after 300 s; `SchemaMismatch` and `CorruptJournal` stop it until the service is created
  again; a SIGTERM exit is not relaunched. `status` (`watching` | `waiting` | `stopped`) and
  `lastError` are properties, and each failure is one `console.warn` line in the shell
  journal (`journalctl --user -t omarchy-shell`).
- `core/stores/RunAlertsStore.qml`: drops the `notify.py` path; toasts unchanged.
- `ui/screens/RunsScreen.qml`: the switch label and caption.
- `docs/architecture.md` documents the second entry point and that it is the one store not
  composed by `App.qml`; `tests/architecture` keeps passing (the file is an ordinary store).

## Resource use when idle

One `am watch --follow` (about 46 MB) plus the Python helper, both blocked on reads; no
timer runs while no run is started; one `am runs` per root with a started run per minute
while runs are live. The panel's own watch (only while open) is unchanged, so while the
panel is open two watches run.

## Failure modes

| case | behaviour |
|---|---|
| `am` not installed | `AmMissing`; retried every 300 s; nothing notified |
| journal schema not 1 or 2 | `SchemaMismatch`; stopped until the shell or plugin reloads; one journal warning |
| corrupt journal | `CorruptJournal`; stopped as above |
| `brd` missing or failing | no registered root is known; nothing alerts; retried at the next candidate |
| snapshot of the project fails | notification with the short id and the bare state |
| `notify-send` missing | `notify.py` reports `sent: false`; nothing else |
| plugin hot reload / shell restart | the service is destroyed and created again; no replay |
| the bar widget is removed (plugin disabled) | the shell destroys the service with it |
| several monitors | one service, one notification |

## Testing

- `tests/core/backend/runs/test_runs_alerts.py` with fake `am` and `brd`: hello schema 1 and
  2 accepted, 3 refused; backlog never alerts (`--from-now` in argv); `run_upsert` to
  escalated alerts once, again after a `started`; unregistered root ignored; a root learned
  after a registry change; seed plus poll finds a dead run once; no poll with no started
  run (fake clock); both cancel spellings terminal; every failure envelope; SIGTERM exit 0.
- `tests/core/domain/tst_runs.qml`: `alertNotification` for escalated and dead, with and
  without a run, the project name, the reason from `status-escalated.json`.
- `tests/core/stores/tst_run_alerts_service.qml`: an alert line with the switch off sends
  nothing; on, one snapshot of that root then one `notify.py`; snapshot failure falls back;
  restart policy per envelope type; SIGTERM not relaunched.
- `tests/core/stores/tst_run_alerts_store.qml`: an alert raises a toast and no `notify.py`.
- `tests/test_install.py` (or a manifest test): `kinds` and both entry points exist as files.
- `tests/ui/screens/tst_runs_screen.qml`: the switch label and caption.
- Manual: `bash tests/live-check.sh` shows no load error for the service entry.

## Open

- **Service versus an external watcher.** Rejected alternative: a script started by
  `install.sh` as a systemd user unit running the same helper. It would survive a shell
  restart, but the shell IS the notification daemon (fact 6), so it would notify into
  nothing while the shell is down, and it adds a unit to install, update and remove.
  Recommendation: the `service` kind.
- **`keepLoaded`.** With it, the service survives plugin hot reloads (fewer restarts of the
  watch while developing the plugin). Recommendation: leave it off; a reload is rare and
  costs nothing but a re-seed.
- **Surfacing the service's state in the panel.** The bar widget could read the service
  through the shell facade (`shell.qml:386-389`, `pluginServiceFor`) to show "background
  alerts stopped: <why>" in the Runs footer. Recommendation: a follow-up once the facade
  call is confirmed from a third-party widget; the journal warning covers it until then.
- **Click to open.** A notification action that opens the panel on the run needs
  `notify-send --action` and a process that waits for the answer. Not in this milestone.
