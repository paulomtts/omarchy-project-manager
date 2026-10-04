"""The installed am still speaks the JSON shapes core/backend/runs/* parse.

Hermetic: am runs with its own HOME, XDG_DATA_HOME and XDG_STATE_HOME under
tmp_path (am keeps runs under $XDG_DATA_HOME/agent-manager/runs), so the
user's real runs are never read or written. Journals are hand-written in the
shape am's store.JournalLine dumps (journal schema 1); am is never imported and
its SQLite is never read. Skipped when am is absent.
"""
import json
import os
import shutil
import subprocess
from types import SimpleNamespace

import pytest

pytestmark = pytest.mark.skipif(shutil.which("am") is None, reason="am is not installed here")

AM_TIMEOUT = 30


@pytest.fixture
def am(tmp_path):
    env = dict(os.environ)
    env.update({"HOME": str(tmp_path / "home"), "XDG_DATA_HOME": str(tmp_path / "data"),
                "XDG_STATE_HOME": str(tmp_path / "state")})
    (tmp_path / "home").mkdir()
    repo = tmp_path / "repo"
    repo.mkdir()

    def run(*args):
        # A hung am fails the test (TimeoutExpired) instead of hanging the suite.
        return subprocess.run(["am", *args], env=env, capture_output=True, text=True,
                              timeout=AM_TIMEOUT)

    return SimpleNamespace(run=run, env=env, repo=str(repo), data=tmp_path / "data")


EVENT_KEYS = {"attempt", "card", "event", "payload", "phase", "run_id", "seq", "story", "ts"}

# One JSON object per journal line, the shape am's store.JournalLine dumps
# (journal schema 1; see _write_watch_journal in agent-manager's
# tests/test_cli.py). Two runs, listed out of order on purpose: am orders
# --all output by (run_id, seq). Only run-a seq 2 carries a story.
JOURNALS = {
    "run-b": [
        {"seq": 1, "ts": "2026-10-02T12:01:00+00:00", "run_id": "run-b", "event": "phase_upsert",
         "card": "c2", "phase": "review", "attempt": 2, "payload": {"status": "started", "n": 1}},
    ],
    "run-a": [
        {"seq": 1, "ts": "2026-10-02T12:00:00+00:00", "run_id": "run-a", "event": "phase_upsert",
         "card": "c1", "phase": "implement", "attempt": 1, "payload": {"status": "started"}},
        {"seq": 2, "ts": "2026-10-02T12:00:05+00:00", "run_id": "run-a", "event": "phase_upsert",
         "story": "s1", "card": "c1", "phase": "implement", "attempt": 1,
         "payload": {"status": "done", "n": 2}},
    ],
}


def write_journals(data_dir):
    """Write every JOURNALS run to $XDG_DATA_HOME/agent-manager/runs/<id>/journal.jsonl."""
    for run_id, lines in JOURNALS.items():
        run_dir = data_dir / "agent-manager" / "runs" / run_id
        run_dir.mkdir(parents=True, exist_ok=True)
        text = "".join(json.dumps(line, sort_keys=True) + "\n" for line in lines)
        (run_dir / "journal.jsonl").write_text(text, encoding="utf-8")


def expected_events():
    """The JOURNALS lines as am re-emits them: every key present, story null
    when absent, ts normalised from +00:00 to Z, ordered by (run_id, seq)."""
    events = []
    for run_id in sorted(JOURNALS):
        for line in sorted(JOURNALS[run_id], key=lambda entry: entry["seq"]):
            events.append({"story": None, **line, "ts": line["ts"].replace("+00:00", "Z")})
    return events


def test_runs_with_no_data_dir_is_an_empty_list(am):
    assert not am.data.exists(), "precondition: no am data dir yet"
    proc = am.run("runs", "--repo-dir", am.repo)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert json.loads(proc.stdout) == {"ok": True, "data": {"runs": []}}


def test_status_of_an_unknown_run_refuses_with_exit_3_and_unknown_run_error(am):
    proc = am.run("status", "nope", "--repo-dir", am.repo)
    assert proc.returncode == 3, proc.stdout + proc.stderr
    payload = json.loads(proc.stdout)
    assert payload["ok"] is False, payload
    assert payload["error"]["type"] == "UnknownRunError", payload
    # The message embeds the repo path, so only its presence is pinned.
    message = payload["error"]["message"]
    assert isinstance(message, str) and message, payload


def test_watch_all_returns_the_events_envelope_with_journal_line_keys(am):
    write_journals(am.data)
    proc = am.run("watch", "--all")
    assert proc.returncode == 0, proc.stdout + proc.stderr
    payload = json.loads(proc.stdout)
    events = payload["data"]["events"]
    for event in events:
        # Exact key set: pins today's journal schema 1 line.
        assert set(event) == EVENT_KEYS, event
        assert event["ts"].endswith("Z"), event
    assert payload == {"ok": True, "data": {"events": expected_events()}}
