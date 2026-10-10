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
