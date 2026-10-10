# 3.2 Docs: alerts while the panel is closed (card c00f3e3d)

Parent: story 2bf08513. Milestone spec: `docs/superpowers/specs/2026-10-05-alerts-panel-closed-design.md` (cited below as "parent", by line). Blocked by 3.1 (3c50899d, the RunsScreen switch), committed as 53bf731 and 0b9f52c.

## Scope

Docs only. Edit `docs/architecture.md` and `README.md` so they describe background alerts **as built**, and add one pytest file that pins what they must and must not say. Change no QML, JS, Python, manifest, or existing test. Do not edit the parent spec, even where it is stale.

**The code wins over the parent spec.** Before writing a sentence, read the file it is about: `manifest.json`, `core/backend/runs/runs-alerts.py` (the module docstring, lines 2-62, is the helper's contract), `core/stores/RunAlertsService.qml`, `core/stores/RunAlertsStore.qml`, `core/domain/runs.js` `alertNotification` (line 997-1008), `ui/screens/RunsScreen.qml` (lines 335, 342).

### Parent-spec text the docs must NOT repeat (not built)

Parent L101-127 and L134-145 describe a persisted `gseq` cursor, catch-up after a restart, `am watch --all-projects --follow --since-seq`, `am events --escalations --after-seq`, `store_id` / `cursor_reset` handling, a `{"cursor": N}` line, a `gseq` field in alert lines, and dismissal advancing a cursor. None of this exists in the code. `runs-alerts.py` takes no argument and follows `am watch --all --follow --from-now`. Parent L186 ("resumes from the persisted cursor; escalations during the gap are notified once") is false for the built code. The docs must say the opposite: nothing is replayed.

## Facts the docs must state (verified in code)

1. **Manifest** (parent L76-78): `manifest.json` `kinds` is `["bar-widget", "service"]`. `entryPoints.barWidget` is `ui/Panel.qml` and `entryPoints.service` is `core/stores/RunAlertsService.qml`. `docs/architecture.md` L18-20 already says this. Keep it.
2. **Who creates the service** (parent L42-47, L148-150, L163-164): the shell creates one `RunAlertsService` per shell, with no parent, while the plugin is enabled, and destroys it with the plugin. It is the one store `App.qml` does not compose.
3. **Instance counts** (parent fact 2, L38-41): the bar widget, and with it `Panel` → `App` → every `App` store, runs once **per monitor**. The service runs **once** per shell. So one alert gives one desktop notification whatever the number of monitors and whether the panel is open (parent L80-82, L188).
4. **Helper contract** (`runs-alerts.py` docstring):
   - It takes no argument. Any argument is a `Usage` error, exit 2.
   - It reads the `brd projects` registry and seeds by running `am runs --repo-dir R` once per registered root.
   - It then follows `am watch --all --follow --from-now`.
   - It prints one flushed line `{"alert": {"run_id", "root", "project", "state"}}`, with `state` `escalated` (a `run_upsert` into escalated from any other status) or `dead` (an armed started run later read with a lease that is not live).
   - Failure envelopes exit 1: `SchemaMismatch` (hello schema not integer 1 or 2), `CorruptJournal` (am exited 3), `HelperError`, `AmMissing`.
   - It exits 0 on am exit 0, SIGINT, SIGTERM or a closed stdout.
5. **The 60 s lease poll and idle cost** (parent L166-171; code `POLL_EVERY = 60`, `IDLE_POLL = 1.0`):
   - While at least one run is tracked as started, the helper re-reads `am runs --repo-dir R` for the roots holding one, every 60 s, each read bounded by 60 s.
   - With no run tracked it reads nothing.
   - The helper's loop wakes every 1 s while idle.
   - Running for the life of the shell, panel open or closed: one `am watch` process plus the Python helper. Toasts and every panel timer stay panel-only.
6. **No replay**: the watch is `--from-now` and nothing is persisted. A service (re)creation (shell start, plugin hot reload, `omarchy-restart-shell`, parent fact 4 L53-57) or a helper relaunch alerts only on transitions it sees after it starts. A run that escalated or died while it was down is never notified. `dead` detection does re-arm from the seed: a run seeded with a live lease that dies later does alert.
7. **Restart policy** (`RunAlertsService.helperExited`; parent L154-156):
   - A non-zero exit is relaunched after 300 s (`retryTimer`, `status` `waiting`).
   - A `SchemaMismatch` or `CorruptJournal` envelope stops it (`stopped`) until the shell creates the service again (plugin reload or shell restart).
   - Exit 0 is not relaunched.
8. **Where failures are logged** (parent L157-158; verified on this machine: the shell's output is tagged `omarchy-shell` in the user journal): each failure is one `console.warn` line, `RunAlertsService: <error> -- stopped` or `... -- retrying in 300 s`, readable with `journalctl --user -t omarchy-shell`.
9. **Per-alert pipeline** (already in architecture.md L95; keep it): `viewer-state.py get-global-settings` (dropped unless `notifyOnEscalation` is exactly `true`, read at each alert), then one `runs-snapshot.py <root>`, then `notify.py TITLE BODY` from `Runs.alertNotification`.
10. **The panel raises toasts only** (parent L128-130): `RunAlertsStore` raises toasts while the panel is open and launches no `notify.py` and no helper. Desktop notifications are the service's.
11. **The switch** (RunsScreen L335/L342): the label is `Desktop notifications` and the caption is `From the background, panel open or closed`. It is still `RunControlStore`'s viewer-wide `notifyOnEscalation` setting. The failed-save flash string `Notify on escalation could not be saved` is real (`RunControlStore.qml:365`) and stays where architecture.md quotes it.

## Required edits

### docs/architecture.md

Keep the section order and the one-long-line-per-bullet/paragraph style. Extend existing text; never add a second bullet for a store.

- **L92 `RunControlStore` bullet**: where it names the switch `"Notify on escalation" switch (S2 4.4)`, name it the Desktop notifications switch. It must still name `notifyOnEscalation`. Keep the flash string verbatim.
- **L93 `RunAlertsStore` bullet**: add one sentence saying it raises toasts only and that desktop notifications are `RunAlertsService`'s.
- **L95 `RunAlertsService` bullet** (stays a single top-level ``- `RunAlertsService.qml` `` bullet, after `RunDispatchStore`). Add:
  - the bar widget, and every `App` store with it, runs once per monitor, while the service runs once per shell, so one alert is one notification;
  - the failure `console.warn` lines go to `journalctl --user -t omarchy-shell`;
  - a stop holds until a plugin reload or shell restart;
  - no replay: a recreated service or relaunched helper does not notify what happened while it was down.
- **L168 `RunsScreen` paragraph**: the toggle reads `Desktop notifications` with the caption `From the background, panel open or closed`, still `app.runControl.notifyOnEscalation`. Replace "with it on every run toast also raises a desktop notification" with: with it on, the background service raises a desktop notification for each alert, panel open or closed, while the panel raises toasts only.
- **L174 "Refresh model" paragraph**: keep "no timers while idle" for the panel's stores. Add that `RunAlertsService` is the exception. For the life of the shell it keeps one `runs-alerts.py` and its `am watch --all --follow --from-now` running. The helper wakes every 1 s and reads `am runs --repo-dir R` every 60 s only while a run is tracked as started, and reads nothing otherwise. Its `retryTimer` runs only while `waiting`. Closing the panel does not stop it.
- **L199 `core/backend/runs/` paragraph** (already describes `runs-alerts.py`): add the exit contract: no-argument/`Usage` exit 2; the four exit-1 envelope types; exit 0 on am exit 0 / SIGINT / SIGTERM / closed stdout; the 60 s read bound; no persisted cursor, so nothing is replayed.

### README.md

README must name none of `README_TOKENS` (`tests/architecture/test_run_store_docs.py`): no `RunStore`, `RunControlStore`, `RunAlertsStore`, `RunDispatchStore`, `app.runs…`, or `shim`. Describe the behaviour in user terms.

- **L154 Runs feature bullet**:
  - Replace "**Notify on escalation**, under the Runs list, is one switch for the whole viewer: with it on, each such toast also raises a desktop notification. Nothing polls while the panel is closed." with the following. **Desktop notifications** (caption "From the background, panel open or closed") is one viewer-wide switch. With it on, a background service the shell runs once raises one desktop notification per run that escalates or dies, panel open or closed, on one monitor or several. The panel's toasts appear only while it is open.
  - Add that alerts are not replayed: what escalates or dies while the shell is down or restarting is not notified.
  - Add that while a run is started, the service reads `am runs` for its project once a minute.
- **L235 helper sentence**: add `am watch --all --follow --from-now` to the `am` commands and `runs/runs-alerts.py` and `runs/notify.py` to the helpers.
- **L259 Install / am requirements**: add the background-alert failure modes:
  - `am` missing: retried every 300 s, nothing notified;
  - an `am` whose watch hello schema is not 1 or 2, or a store it cannot read: stopped until the plugin reloads or the shell restarts;
  - each failure is one line in `journalctl --user -t omarchy-shell`.

## Tests (TDD: write first, watch fail, then edit docs)

One new file: `tests/architecture/test_alerts_docs.py`. **Tier:** pytest architecture tier, as `tests/architecture/test_run_store_docs.py`. **Why:** the deliverable is document text, which only a file-reading test can pin; no QML or helper behaviour changes, so no QML or backend test applies. Reuse `ROOT` the way `test_run_store_docs.py` does, and use its `bullet(name)` helper to scope assertions to one bullet.

Tests (each fails on the current docs, except where marked guard):

1. `test_service_bullet_names_monitor_and_once`: the `RunAlertsService.qml` bullet says "per monitor" and "once".
2. `test_service_bullet_names_journal`: the `RunAlertsService.qml` bullet contains `journalctl --user -t omarchy-shell`.
3. `test_service_bullet_says_no_replay`: the `RunAlertsService.qml` bullet contains a no-replay statement: it matches `/not replayed|no replay|never notified/i`.
4. `test_alerts_store_bullet_toasts_only`: the `RunAlertsStore.qml` bullet says toasts only and names `RunAlertsService` as the owner of desktop notifications.
5. `test_runs_screen_names_switch`: architecture.md contains `Desktop notifications` and `From the background, panel open or closed`, and does not contain `also raises a desktop notification` or a ``reads `Notify on escalation` `` toggle label.
6. `test_refresh_model_names_service_exception`: the paragraph starting `Refresh model:` names `RunAlertsService`, `--from-now` and `60 s`.
7. `test_backend_paragraph_exit_contract`: the paragraph starting `` `core/backend/runs/` `` names `runs-alerts.py`, each of `SchemaMismatch`, `CorruptJournal`, `HelperError`, `AmMissing`, and `Usage`.
8. `test_readme_background_alerts`: README.md contains `Desktop notifications`, `journalctl --user -t omarchy-shell`, `runs-alerts.py`, `am watch --all --follow --from-now`, `300 s`. It does not contain `Nothing polls while the panel is closed` or `also raises a desktop notification`. It does not contain `--since-seq`, `gseq` or `am events`.
9. `test_alert_docs_name_no_cursor`: guards against copying the stale parent spec. The `RunAlertsService.qml` bullet and README.md contain none of `--since-seq`, `am events`, `store_id`, `gseq` or the word `cursor` (match `\bcursor\b(?!-)`: README.md L103 legitimately lists the `cursor-agent` CLI, so a plain substring ban would fail on the current README). Do not apply this check to the whole of architecture.md. That file already uses `--since-seq`, `am events`, `store_id`/`storeId` and `gseq` legitimately for other helpers (as of this writing: 1, 1, 3/4 and 4 hits), so a file-wide ban would be wrong.
10. Guard (existing, must stay green, not edited): `tests/architecture/test_run_store_docs.py` (store bullet order and wiring, README tokens), `test_layers.py`, `test_icon_glyphs.py` (it scans only `ui/` and `vendor/` `.qml`, so `‼`/`✖` in docs are unaffected), `tests/test_manifest.py`.

Verification: `bash tests/run.sh` green.

## Out of scope

- Any code, manifest, or QML/JS/Python test change.
- Editing the stale parent spec (`2026-10-05-alerts-panel-closed-design.md`).
- Documenting a cursor, catch-up, `keepLoaded`, click-to-open actions, or surfacing service state in the panel (parent Open L212-227; not built).
- Sibling cards: 3.1 (RunsScreen switch, done), 2.x (service and store code), 1.x (helper).
