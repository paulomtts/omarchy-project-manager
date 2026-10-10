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

---

# 3.2 Docs: alerts while the panel is closed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `docs/architecture.md` and `README.md` describe background alerts as built (one `RunAlertsService` per shell, panel open or closed, nothing replayed), pinned by one new pytest file.

**Architecture:** Docs-only change. A new architecture-tier test, `tests/architecture/test_alerts_docs.py`, reads the two documents and asserts what each bullet/paragraph must and must not say, reusing `bullet()`, `DOC` and `README` from `tests/architecture/test_run_store_docs.py`. Each task writes its tests first, watches them fail, then edits the document with exact string replacements.

**Tech Stack:** Markdown, pytest (run through `uv run --with pytest` because the system `python3` has no pytest), `tests/run.sh` (pytest plus the QML suite).

**Spec:** `docs/superpowers/specs/3-2-docs-alerts-while-c00f3e3d.md` (reproduced above).

## Global Constraints

- Docs only: change no QML, JS, Python, `manifest.json`, or existing test. Do not edit `docs/superpowers/specs/2026-10-05-alerts-panel-closed-design.md`.
- The code wins over the parent spec. Never write a persisted `gseq` cursor, catch-up, `--since-seq`, `am events`, `store_id`/`cursor_reset`, or a `{"cursor": N}` line into the alert text.
- `docs/architecture.md`: keep the section order and the one-long-line-per-bullet/paragraph style. Extend existing text; never add a second bullet for a store. `RunAlertsService.qml` stays one top-level bullet, after `RunDispatchStore.qml`.
- README.md must name none of `README_TOKENS`: `RunStore`, `RunControlStore`, `RunAlertsStore`, `RunDispatchStore`, `app.runs`, `app.runControl`, `app.runAlerts`, `app.runDispatch`, `shim`.
- Switch label `Desktop notifications`, caption `From the background, panel open or closed`; the setting is still `notifyOnEscalation`; the flash string `Notify on escalation could not be saved` stays verbatim.
- Log location: `journalctl --user -t omarchy-shell`. Retry delay: `300 s`. Poll: every `60 s`, each read bounded by `60 s`; idle wake every `1 s`.
- Never run `pkill`/`killall`; bound long commands with `timeout`.

## Review Focus

1. Copying the stale parent spec's cursor/catch-up into the alert docs -- a reader would expect missed escalations to be notified after a restart; they are not. Pinned by `test_alert_docs_name_no_cursor` and `test_readme_background_alerts` (`not replayed`), Task 2; `test_service_bullet_says_no_replay`, Task 1.
2. Renaming the switch and losing the real failed-save flash string `Notify on escalation could not be saved` or the `notifyOnEscalation` setting name from the `RunControlStore` bullet. Pinned in `test_runs_screen_names_switch`, Task 1.
3. Adding the service exception to "Refresh model" by rewriting its opening "no timers while idle" claim for the panel stores. Pinned in `test_refresh_model_names_service_exception` (the paragraph still starts `Refresh model: no timers while idle.`), Task 1.
4. A second `RunAlertsService.qml` bullet, or breaking the store-bullet order, while extending the bullet. Pinned by `bullet()`'s exactly-one assertion in every Task 1 test plus the existing `tests/architecture/test_run_store_docs.py::test_each_run_store_has_one_bullet_in_order` (guard, unedited).
5. README naming an internal store (`RunAlertsStore`, `app.runAlerts`, ...) while describing the toasts/service split. Pinned by the existing `tests/architecture/test_run_store_docs.py::test_the_readme_names_no_run_store` (guard, unedited), run in Task 2 Step 6.

## File Structure

- Create: `tests/architecture/test_alerts_docs.py` -- the one test file pinning both documents (Task 1 creates it with the architecture.md tests; Task 2 appends the README tests).
- Modify: `docs/architecture.md` -- line 92 (`RunControlStore.qml` bullet), 93 (`RunAlertsStore.qml` bullet), 95 (`RunAlertsService.qml` bullet), 168 (run screens paragraph), 174 (`Refresh model:` paragraph), 199 (`` `core/backend/runs/` `` paragraph).
- Modify: `README.md` -- line 154 (Runs feature bullet), 235 (helper sentence), 259 (Install `am` requirements).

Both files are one-long-line-per-paragraph; edit with exact `old_string` -> `new_string` replacements (each `old_string` below was checked to occur exactly once).

---

### Task 1: docs/architecture.md describes the service as built

**Files:**
- Create: `tests/architecture/test_alerts_docs.py`
- Modify: `docs/architecture.md:92,93,95,168,174,199`

**Interfaces:**
- Consumes: from `tests/architecture/test_run_store_docs.py` (importable by module name because pytest puts `tests/architecture/` on `sys.path`, as `test_run_store_docs.py` itself does with `from test_run_store_callers import ...`): `DOC` (`Path` to `docs/architecture.md`), `README` (`Path` to `README.md`), `bullet(name, text=None) -> (int, str)` (1-based line and text of the one top-level ``- `name` `` bullet; asserts there is exactly one).
- Produces: `tests/architecture/test_alerts_docs.py` with module-level `line_starting(prefix) -> str` (the one line of `docs/architecture.md` starting with `prefix`), used again by nothing outside this file; Task 2 appends tests to the same file and reuses its imports.

- [ ] **Step 1: Write the failing tests**

Create `tests/architecture/test_alerts_docs.py` with exactly:

```python
"""docs/architecture.md and README.md describe background alerts as built.

The shell creates one `RunAlertsService` per shell, panel open or closed, while the bar widget and every
`App` store run once per monitor. The service follows `am watch --all --follow --from-now` and persists
nothing, so nothing is replayed. The docs must say so and must not repeat the parent spec's cursor and
catch-up, which were never built.
"""
import re

from test_run_store_docs import DOC, README, bullet


def line_starting(prefix):
    """The one line of docs/architecture.md that starts with `prefix`."""
    lines = [line for line in DOC.read_text().splitlines() if line.startswith(prefix)]
    assert len(lines) == 1, f"{len(lines)} lines start with {prefix!r}, want 1"
    return lines[0]


def test_service_bullet_names_monitor_and_once():
    line, text = bullet("RunAlertsService.qml")
    assert "per monitor" in text, f"docs/architecture.md:{line}"
    assert "once per shell" in text, f"docs/architecture.md:{line}"


def test_service_bullet_names_journal():
    line, text = bullet("RunAlertsService.qml")
    assert "journalctl --user -t omarchy-shell" in text, f"docs/architecture.md:{line}"


def test_service_bullet_says_no_replay():
    line, text = bullet("RunAlertsService.qml")
    assert re.search(r"not replayed|no replay|never notified", text, re.I), f"docs/architecture.md:{line}"


def test_alerts_store_bullet_toasts_only():
    line, text = bullet("RunAlertsStore.qml")
    assert "toasts only" in text, f"docs/architecture.md:{line}"
    assert "`RunAlertsService`" in text, f"docs/architecture.md:{line}"


def test_runs_screen_names_switch():
    text = DOC.read_text()
    assert "Desktop notifications" in text
    assert "From the background, panel open or closed" in text
    assert "also raises a desktop notification" not in text
    assert "reads `Notify on escalation`" not in text
    # the failed-save flash is real (RunControlStore.qml) and stays quoted
    assert "Notify on escalation could not be saved" in text
    line, control = bullet("RunControlStore.qml")
    assert "Desktop notifications" in control, f"docs/architecture.md:{line}"
    assert "`notifyOnEscalation`" in control, f"docs/architecture.md:{line}"


def test_refresh_model_names_service_exception():
    text = line_starting("Refresh model:")
    # the panel's stores keep their claim; the service is the exception
    assert text.startswith("Refresh model: no timers while idle.")
    for needle in ["`RunAlertsService`", "--from-now", "60 s", "every 1 s", "`retryTimer`"]:
        assert needle in text, needle


def test_backend_paragraph_exit_contract():
    text = line_starting("`core/backend/runs/`")
    assert "`runs-alerts.py`" in text
    alerts = text[text.index("`runs-alerts.py`"):]
    for needle in ["`Usage`", "exit 2", "`SchemaMismatch`", "`CorruptJournal`", "`HelperError`",
                   "`AmMissing`", "SIGTERM", "60 s", "nothing is replayed"]:
        assert needle in alerts, needle
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture/test_alerts_docs.py -v`
Expected: 7 FAILED, all with `AssertionError` on content (not `ImportError`): `test_service_bullet_names_monitor_and_once` (`per monitor`), `test_service_bullet_names_journal`, `test_service_bullet_says_no_replay`, `test_alerts_store_bullet_toasts_only` (`toasts only`), `test_runs_screen_names_switch` (`Desktop notifications`), `test_refresh_model_names_service_exception` (`` `RunAlertsService` ``), `test_backend_paragraph_exit_contract` (`` `Usage` ``).

- [ ] **Step 3: Edit the `RunControlStore.qml` bullet (docs/architecture.md:92)**

Replace

```
the footer flash and the "Notify on escalation" switch (S2 4.4)
```

with

```
the footer flash and the Desktop notifications switch (S2 4.4), the viewer-wide `notifyOnEscalation` setting
```

Then replace

```
"Notify on escalation" is viewer-wide and off until read:
```

with

```
The Desktop notifications switch (`notifyOnEscalation`) is viewer-wide and off until read:
```

Leave `flashes `Notify on escalation could not be saved`` in the same bullet untouched.

- [ ] **Step 4: Edit the `RunAlertsStore.qml` bullet (docs/architecture.md:93)**

Replace

```
and `dismissToast(key)` / `dismissAllToasts()` remove them.
```

with

```
and `dismissToast(key)` / `dismissAllToasts()` remove them. It raises toasts only: it launches no `notify.py` and no helper, and desktop notifications are `RunAlertsService`'s.
```

- [ ] **Step 5: Edit the `RunAlertsService.qml` bullet (docs/architecture.md:95)**

Replace

```
it is the one store `App.qml` does not compose.
```

with

```
it is the one store `App.qml` does not compose. The bar widget, and with it `Panel`, `App` and every `App` store, runs once per monitor, while the service runs once per shell, panel open or closed, so one alert gives one desktop notification however many monitors there are.
```

Then replace

```
which stops it until the shell creates the service again; exit 0 is not relaunched, and each failure is one `console.warn` line.
```

with

```
which stops it until the shell creates the service again (a plugin reload or a shell restart); exit 0 is not relaunched, and each failure is one `console.warn` line, `RunAlertsService: <error> -- stopped` or `RunAlertsService: <error> -- retrying in 300 s`, which the user journal holds under `journalctl --user -t omarchy-shell`.
```

Then replace

```
its reply unread) -- so two alerts never stop each other.
```

with

```
its reply unread) -- so two alerts never stop each other. Nothing is replayed: the watch is `--from-now` and nothing is persisted, so a recreated service (shell start, plugin hot reload, `omarchy-restart-shell`) or a relaunched helper alerts only on transitions it sees after it starts, and a run that escalated or died while it was down is never notified; a run the seed finds started with a live lease that dies later does alert.
```

- [ ] **Step 6: Edit the run screens paragraph (docs/architecture.md:168)**

Replace

```
Directly above the footer a `ToggleSwitch` reads `Notify on escalation` (`app.runControl.notifyOnEscalation`, changed through `setNotifyOnEscalation`), shown also while am is missing and with no project open: it is `RunControlStore`'s viewer-wide switch (`viewer-state.py get-global-settings` / `set-global-settings`), and with it on every run toast also raises a desktop notification.
```

with

```
Directly above the footer a `ToggleSwitch` (`app.runControl.notifyOnEscalation`, changed through `setNotifyOnEscalation`) is labelled `Desktop notifications`, with the caption `From the background, panel open or closed` under the label, right of the toggle, shown also while am is missing and with no project open: it is `RunControlStore`'s viewer-wide switch (`viewer-state.py get-global-settings` / `set-global-settings`), and with it on the background service (`RunAlertsService`) raises a desktop notification for each alert, panel open or closed, while the panel raises toasts only.
```

- [ ] **Step 7: Edit the `Refresh model:` paragraph (docs/architecture.md:174)**

Replace

```
and `Pulse` animates a run badge only while it is running, visible and `active`.
```

with

```
and `Pulse` animates a run badge only while it is running, visible and `active`. `RunAlertsService` is the exception: for the life of the shell, panel open or closed, it keeps one `runs-alerts.py` and its `am watch --all --follow --from-now` running; the helper wakes every 1 s, reads `am runs --repo-dir R` every 60 s (each read bounded by 60 s) for the roots holding a run tracked as started, and reads nothing while no run is; the service's `retryTimer` runs only while `waiting`. Closing the panel does not stop it; toasts and every panel timer stay panel-only.
```

- [ ] **Step 8: Edit the `` `core/backend/runs/` `` paragraph (docs/architecture.md:199)**

Replace

```
`runs-alerts.py` takes no argument and is long-lived: it follows `am watch --all --follow --from-now`, reads `am runs --repo-dir R` once per registered root at start and every 60 s for the roots holding a started run (none while no run is started), and prints `{"alert": {run_id, root, project, state}}` with `state` `escalated` or `dead`.
```

with

```
`runs-alerts.py` takes no argument (any argument is `Usage`, exit 2, and neither am nor brd is run) and is long-lived: it reads the `brd projects` registry, seeds by reading `am runs --repo-dir R` once per registered root, then follows `am watch --all --follow --from-now`, re-reads `am runs --repo-dir R` every 60 s for the roots holding a run tracked as started (none while no run is), each read bounded by 60 s, and prints one flushed `{"alert": {run_id, root, project, state}}` line per alert, `state` `escalated` (a `run_upsert` into escalated from any other status) or `dead` (an armed started run later read with a lease that is not live). It ends with an `{ok: false, error}` line and exit 1 -- `SchemaMismatch` (a hello whose `schema` is not the integer 1 or 2), `CorruptJournal` (am exited 3), `HelperError` or `AmMissing`, or am's own refusal envelope re-emitted unchanged -- and with exit 0 when am exits 0, on SIGINT or SIGTERM, or when its stdout closes. It persists nothing, so nothing is replayed after it restarts.
```

- [ ] **Step 9: Run the new tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture/test_alerts_docs.py -v`
Expected: 7 passed.

- [ ] **Step 10: Run the guard tests**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture tests/test_manifest.py -q`
Expected: all passed (`test_run_store_docs.py`'s bullet order, App wiring, no-shim and README-token tests stay green).

- [ ] **Step 11: Commit**

```bash
git add tests/architecture/test_alerts_docs.py docs/architecture.md
git commit -m "docs(alerts): architecture.md describes RunAlertsService once per shell, its journal lines and that nothing is replayed"
```

---

### Task 2: README.md describes background alerts in user terms

**Files:**
- Modify: `tests/architecture/test_alerts_docs.py` (append)
- Modify: `README.md:154,235,259`

**Interfaces:**
- Consumes: `README`, `bullet` and `re`, already imported at the top of `tests/architecture/test_alerts_docs.py` by Task 1 (`from test_run_store_docs import DOC, README, bullet`; `import re`).
- Produces: nothing later tasks use.

- [ ] **Step 1: Write the failing tests**

Append to the end of `tests/architecture/test_alerts_docs.py`:

```python


# The parent spec's cursor and catch-up were never built: no alert text may name them.
STALE_RE = re.compile(r"--since-seq|am events|store_id|gseq")
CURSOR_RE = re.compile(r"\bcursor\b(?!-)")
# README's legitimate uses of the word: the cursor-agent CLI and the list's keyboard cursor.
README_CURSOR_OK = ["cursor-agent", "the row under the cursor", "the board list's cursor card"]


def test_readme_background_alerts():
    text = README.read_text()
    for needle in ["Desktop notifications", "From the background, panel open or closed",
                   "journalctl --user -t omarchy-shell", "runs-alerts.py",
                   "am watch --all --follow --from-now", "300 s", "not replayed"]:
        assert needle in text, needle
    for banned in ["Nothing polls while the panel is closed", "also raises a desktop notification",
                   "--since-seq", "gseq", "am events"]:
        assert banned not in text, banned


def test_alert_docs_name_no_cursor():
    _, service = bullet("RunAlertsService.qml")
    readme = README.read_text()
    for ok in README_CURSOR_OK:
        readme = readme.replace(ok, "")
    hits = {name: STALE_RE.findall(text) + CURSOR_RE.findall(text)
            for name, text in [("RunAlertsService.qml bullet", service), ("README.md", readme)]}
    assert hits == {"RunAlertsService.qml bullet": [], "README.md": []}
```

Note: `test_alert_docs_name_no_cursor` is a guard -- it passes before and after this task. Do not apply it to the whole of `docs/architecture.md`, which legitimately names `--since-seq`, `am events`, `store_id`/`storeId`, `gseq` and `{"cursor": C}` for `runs-watch.py`/`runs-snapshot.py`. README.md already says "cursor" three times legitimately (`cursor-agent` at line 103, "the row under the cursor" at line 154, "the board list's cursor card" at line 155); the allow-list removes exactly those phrases, so a plain word ban would wrongly fail.

- [ ] **Step 2: Run the tests to verify the README test fails**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture/test_alerts_docs.py -v`
Expected: `test_readme_background_alerts` FAILED with `AssertionError: Desktop notifications`; `test_alert_docs_name_no_cursor` and the 7 Task 1 tests PASSED.

- [ ] **Step 3: Edit the Runs feature bullet (README.md:154)**

Replace

```
**Notify on escalation**, under the Runs list, is one switch for the whole viewer: with it on, each such toast also raises a desktop notification. Nothing polls while the panel is closed.
```

with

```
**Desktop notifications** (captioned "From the background, panel open or closed"), under the Runs list, is one switch for the whole viewer: with it on, a background service the shell runs once raises one desktop notification for each run of a registered project that escalates or dies, panel open or closed, on one monitor or several; the panel's toasts appear only while it is open. Alerts are not replayed: a run that escalates or dies while the shell is down or restarting is not notified. While a run is started, the service reads `am runs` for its project once a minute; otherwise it only follows `am`'s event stream.
```

- [ ] **Step 4: Edit the helper sentence (README.md:235)**

Replace

```
For the run monitor it runs only `am` (`am runs --repo-dir R` for each registered project, `am status`, `am watch --all-projects --follow` and `am logs`) through the helpers in `core/backend/runs/` (`runs/runs-snapshot-all.py`, `runs/runs-watch.py`, `runs/runs-logs.py`), and never reads am's SQLite database.
```

with

```
For the run monitor it runs only `am` (`am runs --repo-dir R` for each registered project, `am status`, `am watch --all-projects --follow`, `am watch --all --follow --from-now` and `am logs`), plus `brd projects` and `notify-send` for the background alerts, through the helpers in `core/backend/runs/` (`runs/runs-snapshot-all.py`, `runs/runs-snapshot.py`, `runs/runs-watch.py`, `runs/runs-logs.py`, `runs/runs-alerts.py`, `runs/notify.py`), and never reads am's SQLite database.
```

- [ ] **Step 5: Edit the Install `am` requirements (README.md:259)**

Replace

```
Starting runs from the panel needs an `am` whose `am run` supports `--story`: `am run --help` must list it.
```

with

```
Desktop notifications come from a background service the shell runs whether or not the panel is open, and it needs `am` too: with `am` missing it retries every 300 s and notifies nothing; with an `am` whose watch hello schema is not 1 or 2, or a store it cannot read (a corrupt journal), it stops until the plugin reloads or the shell restarts. Each failure is one line in `journalctl --user -t omarchy-shell`. Starting runs from the panel needs an `am` whose `am run` supports `--story`: `am run --help` must list it.
```

- [ ] **Step 6: Run the new tests and the README guard**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture/test_alerts_docs.py tests/architecture/test_run_store_docs.py -v`
Expected: all passed, including `test_readme_background_alerts`, `test_alert_docs_name_no_cursor` and `test_the_readme_names_no_run_store`.

- [ ] **Step 7: Run the whole suite**

Run: `timeout 600 bash tests/run.sh`
Expected: pytest reports all passed and every QML test file prints `Totals: ... 0 failed`; exit status 0.

- [ ] **Step 8: Commit**

```bash
git add tests/architecture/test_alerts_docs.py README.md
git commit -m "docs(alerts): README describes Desktop notifications from the background, its failure modes and that nothing is replayed"
```
<!-- task-pipeline: validated -->
