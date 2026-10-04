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
