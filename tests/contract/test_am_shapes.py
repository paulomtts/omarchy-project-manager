"""The installed am still speaks the JSON shapes core/backend/runs/* parse.

Hermetic: am runs with its own HOME, XDG_DATA_HOME and XDG_STATE_HOME under
tmp_path (am keeps runs under $XDG_DATA_HOME/agent-manager/runs), so the
user's real runs are never read or written. Journals are hand-written in the
shape am's store.JournalLine dumps (journal schema 1); am is never imported and
its SQLite is never read. Skipped when am is absent.

Story tests build a real git repo and brd board under tmp_path and run am with
a PATH holding only am, brd and git, so no agent CLI is reachable. When am is
present they fail, never skip, if am run lacks --story or brd or git is absent.
"""
import json
import os
import queue
import shutil
import subprocess
import threading
import time
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


FOLLOW_TIMEOUT = 10


def read_lines(stream, count, timeout=FOLLOW_TIMEOUT):
    """The first `count` lines of `stream`, parsed as JSON.

    A daemon thread pumps lines into a queue and every get is bounded by one
    shared deadline, so an am that goes silent or exits early fails the test
    with what it did print instead of hanging the suite.
    """
    lines = queue.Queue()

    def pump():
        try:
            for line in stream:
                lines.put(line)
        except (OSError, ValueError):
            return  # the pipe was closed under us once the test is done

    threading.Thread(target=pump, daemon=True).start()
    got = []
    deadline = time.monotonic() + timeout
    while len(got) < count:
        try:
            got.append(lines.get(timeout=max(deadline - time.monotonic(), 0.01)))
        except queue.Empty:
            pytest.fail(f"am printed {len(got)} of {count} lines within {timeout}s: {got!r}")
    return [json.loads(line) for line in got]


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


def test_watch_all_follow_prints_a_hello_line_then_journal_lines(am):
    write_journals(am.data)
    expected = expected_events()
    with subprocess.Popen(["am", "watch", "--all", "--follow"], env=am.env,
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True) as proc:
        try:
            # --follow never exits on its own: read only the lines expected.
            hello, *events = read_lines(proc.stdout, 1 + len(expected))
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
    assert hello["event"] == "watch", hello
    assert hello["schema"] in (1, 2), hello
    assert isinstance(hello["am"], str) and hello["am"], hello
    assert isinstance(hello["runs_dir"], str), hello
    # Hermetic: the stream reads the throwaway data dir, not the user's.
    assert hello["runs_dir"] == str(am.data / "agent-manager" / "runs"), hello
    for event in events:
        assert set(event) == EVENT_KEYS, event
        assert event["ts"].endswith("Z"), event
    assert events == expected


STORY_DATA_KEYS = {"already_done", "integrate", "levels", "max_concurrent"}
RUN_ROW_KEYS = {"id", "story_id", "milestone_id", "branch_prefix", "started_at"}


def require_tool(name):
    """The resolved path of `name` on the PATH; fails the test when it is absent."""
    path = shutil.which(name)
    if path is None:
        pytest.fail(f"{name} is not on the PATH: the story tests need am, brd and git")
    return os.path.realpath(path)


@pytest.fixture
def story_board(am, tmp_path):
    """A git repo on master and a brd board in am.repo: milestone M holding
    story S1 and story S2 (blocked by S1), two subtasks each. am.env's PATH is
    only a dir of am, brd and git, and it carries no GIT_* variable."""
    tools = {name: require_tool(name) for name in ("am", "brd", "git")}
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    for name, path in tools.items():
        (bin_dir / name).symlink_to(path)
    am.env["PATH"] = str(bin_dir)
    for key in [key for key in am.env if key.startswith("GIT_")]:
        del am.env[key]

    def git(*args):
        proc = subprocess.run(["git", "-c", "user.name=tester", "-c", "user.email=tester@example.com",
                               *args], cwd=am.repo, env=am.env, capture_output=True, text=True)
        assert proc.returncode == 0, proc.stdout + proc.stderr

    git("init", "-b", "master")
    git("commit", "--allow-empty", "-m", "init")

    brd_env = {**am.env, "BRD_AUTHOR": "tester"}

    def brd(*args):
        proc = subprocess.run(["brd", *args], cwd=am.repo, env=brd_env, capture_output=True,
                              text=True)
        assert proc.returncode == 0, proc.stdout + proc.stderr
        payload = json.loads(proc.stdout.strip().splitlines()[-1])
        assert payload["ok"] is True, payload
        return payload["data"]

    brd("init", "--name", "contract")
    milestone = brd("add", "--title", "Milestone M")["id"]
    s1 = brd("add", "--title", "Story A", "--parent", milestone)["id"]
    s2 = brd("add", "--title", "Story B", "--parent", milestone, "--blocked-by", s1)["id"]
    s1_subtasks = [brd("add", "--title", f"Subtask A{n}", "--parent", s1)["id"] for n in (1, 2)]
    for n in (1, 2):
        brd("add", "--title", f"Subtask B{n}", "--parent", s2)
    return SimpleNamespace(milestone=milestone, s1=s1, s2=s2, s1_subtasks=s1_subtasks)


def test_run_help_lists_the_story_option(am):
    proc = am.run("run", "--help")
    assert proc.returncode == 0, proc.stdout + proc.stderr
    if "--story" not in proc.stdout:
        pytest.fail("the installed am has no --story option on am run "
                    "(reinstall agent-manager: uv tool install --reinstall)")


def test_require_tool_fails_naming_the_missing_tool(monkeypatch):
    monkeypatch.setattr(shutil, "which", lambda name: None)
    with pytest.raises(pytest.fail.Exception, match="brd is not on the PATH"):
        require_tool("brd")


def test_story_board_reaches_only_am_brd_and_git_and_its_own_repo(am, story_board, tmp_path):
    assert am.env["PATH"] == str(tmp_path / "bin")
    assert sorted(os.listdir(tmp_path / "bin")) == ["am", "brd", "git"]
    assert not [key for key in am.env if key.startswith("GIT_")], am.env
    proc = subprocess.run(["git", "rev-parse", "--show-toplevel", "--abbrev-ref", "HEAD"],
                          cwd=am.repo, env=am.env, capture_output=True, text=True)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert proc.stdout.split() == [os.path.realpath(am.repo), "master"], proc.stdout


def assert_story_blocked(proc, blocker):
    """Exit 3 with a StoryBlockedError envelope whose message names `blocker`."""
    assert proc.returncode == 3, proc.stdout + proc.stderr
    payload = json.loads(proc.stdout)
    assert payload["ok"] is False, payload
    assert payload["error"]["type"] == "StoryBlockedError", payload
    message = payload["error"]["message"]
    assert isinstance(message, str) and blocker in message, payload


def test_story_dry_run_previews_one_level_with_no_integrate(am, story_board):
    proc = am.run("run", "--story", story_board.s1, "--branch-prefix", "p", "--dry-run",
                  "--repo-dir", am.repo)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    payload = json.loads(proc.stdout)
    assert payload["ok"] is True, payload
    data = payload["data"]
    assert set(data) == STORY_DATA_KEYS, payload
    assert data["already_done"] == [], payload
    assert data["integrate"] is None, payload
    [level] = data["levels"]
    [story] = level["stories"]
    assert story["story"] == story_board.s1, payload
    first, second = story["subtasks"]
    assert {first["id"], second["id"]} == set(story_board.s1_subtasks), payload
    assert first["base"] == "master", payload
    assert second["base"] == first["branch"], payload


def test_blocked_story_is_refused_at_dry_run_with_story_blocked_error(am, story_board):
    proc = am.run("run", "--story", story_board.s2, "--branch-prefix", "p", "--dry-run",
                  "--repo-dir", am.repo)
    assert_story_blocked(proc, story_board.s1)


def test_blocked_story_is_refused_at_a_detached_start_and_nothing_is_recorded(am, story_board):
    """Both the dry-run and the detached start refuse a blocked story; the
    refused start records no run."""
    proc = am.run("run", "--story", story_board.s2, "--branch-prefix", "p", "--detach",
                  "--allow-no-verification", "--repo-dir", am.repo)
    assert_story_blocked(proc, story_board.s1)
    runs = am.run("runs", "--repo-dir", am.repo)
    assert runs.returncode == 0, runs.stdout + runs.stderr
    assert json.loads(runs.stdout) == {"ok": True, "data": {"runs": []}}


def test_a_story_run_row_carries_story_id(am, story_board):
    # No agent CLI is on the PATH: the run is recorded, then escalates at its first phase.
    am.run("run", "--story", story_board.s1, "--branch-prefix", "p", "--allow-no-verification",
           "--repo-dir", am.repo)
    proc = am.run("runs", "--repo-dir", am.repo)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    [row] = json.loads(proc.stdout)["data"]["runs"]
    assert RUN_ROW_KEYS <= set(row), row
    assert row["story_id"] == story_board.s1, row
    assert row["milestone_id"] == story_board.milestone, row
    assert row["branch_prefix"] == "p", row
    assert isinstance(row["started_at"], str) and row["started_at"], row
    if "project" in row:
        assert isinstance(row["project"], dict), row
        assert {"id", "repo_dir"} <= set(row["project"]), row
