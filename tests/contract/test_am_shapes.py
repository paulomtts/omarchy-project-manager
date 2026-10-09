"""The installed am still speaks the JSON shapes core/backend/runs/* parse.

Hermetic: am runs with its own HOME, XDG_DATA_HOME and XDG_STATE_HOME under
tmp_path (am keeps its store under $XDG_DATA_HOME/agent-manager), so the
user's real runs are never read or written. Events are seeded only through am
commands: a real story run on a scratch board, which escalates at its first
agent phase because no agent CLI is reachable. am is never imported and its
am.db is never read. Skipped when am is absent.

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
    assert json.loads(proc.stdout) == {"ok": True,
                                       "data": {"as_of_seq": 0, "runs": [], "store_id": None}}


def test_status_of_an_unknown_run_refuses_with_exit_3_and_unknown_run_error(am):
    proc = am.run("status", "nope", "--repo-dir", am.repo)
    assert proc.returncode == 3, proc.stdout + proc.stderr
    payload = json.loads(proc.stdout)
    assert payload["ok"] is False, payload
    assert payload["error"]["type"] == "UnknownRunError", payload
    # The message embeds the repo path, so only its presence is pinned.
    message = payload["error"]["message"]
    assert isinstance(message, str) and message, payload


RUNS_DATA_KEYS = {"as_of_seq", "runs", "store_id"}
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
    payload = json.loads(runs.stdout)
    assert payload["ok"] is True, payload
    assert set(payload["data"]) == RUNS_DATA_KEYS, payload
    # No run row and no event: the store's head is still 0.
    assert payload["data"]["runs"] == [], payload
    assert payload["data"]["as_of_seq"] == 0, payload


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


# A journal line (schema 2) as am watch prints it: the line plus its global gseq.
EVENT_KEYS = {"attempt", "card", "event", "gseq", "payload", "phase", "run_id", "seq", "story", "ts"}
HELLO_KEYS = {"am", "cursor_reset", "event", "head", "runs_dir", "schema", "store_id"}
# The events core/backend/runs/runs-watch.py acts on (its EVENTS); a run that
# reaches an attempt records every one of them.
WATCHED_EVENTS = {"run_upsert", "story_upsert", "subtask_upsert", "phase_upsert", "attempt_upsert"}

# The payload keys of each watched event as the installed am writes them, every
# time it records that event. An attempt carries no cost or token figure.
PAYLOAD_KEYS = {
    "run_upsert": {"base_branch", "branch_prefix", "config", "id", "milestone_id", "repo_dir",
                   "started_at", "status", "workflow"},
    "story_upsert": {"card_id", "level", "status", "tip_branch", "title"},
    "subtask_upsert": {"base_branch", "branch", "card_id", "status", "worktree_path"},
    "phase_upsert": {"detail", "ended_at", "kind", "name", "started_at", "status"},
    "attempt_upsert": {"dispatch", "duration", "exit_code", "n", "prompt_path", "result_path",
                       "status", "stdout_path"},
}


@pytest.fixture
def seeded_run(am, story_board):
    """One real run of story S1, seeded through am alone: no agent CLI is on
    the PATH, so it is recorded and escalates at its first agent phase."""
    am.run("run", "--story", story_board.s1, "--branch-prefix", "p", "--allow-no-verification",
           "--repo-dir", am.repo)
    proc = am.run("runs", "--repo-dir", am.repo)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    data = json.loads(proc.stdout)["data"]
    [row] = data["runs"]
    assert row["status"] == "escalated", row
    return SimpleNamespace(id=row["id"], story=story_board.s1, head=data["as_of_seq"],
                           store_id=data["store_id"])


def assert_seeded_events(events, run, repo):
    """`events` are the seeded run's whole journal in gseq order, each with the
    exact schema 2 key set, ending at the head am runs reported."""
    assert events, "am watch printed no events for the seeded run"
    for event in events:
        assert set(event) == EVENT_KEYS, event
        assert event["run_id"] == run.id, event
        assert event["ts"].endswith("Z"), event
        assert isinstance(event["payload"], dict), event
    gseqs = [event["gseq"] for event in events]
    assert all(type(gseq) is int for gseq in gseqs), gseqs
    assert gseqs == sorted(set(gseqs)), gseqs
    assert gseqs[-1] == run.head, (gseqs, run.head)
    assert [event["seq"] for event in events] == list(range(1, len(events) + 1)), events
    assert WATCHED_EVENTS <= {event["event"] for event in events}, events
    run_upserts = [event for event in events if event["event"] == "run_upsert"]
    for event in run_upserts:
        assert event["story"] is None, event
        # runs-watch.py adopts a run by its run_upsert payload.repo_dir.
        assert os.path.realpath(event["payload"]["repo_dir"]) == os.path.realpath(repo), event
    assert run_upserts[-1]["payload"]["status"] == "escalated", run_upserts[-1]
    for event in events:
        if event["event"] in WATCHED_EVENTS - {"run_upsert"}:
            assert event["story"] == run.story, event
        if event["event"] == "attempt_upsert":
            assert type(event["attempt"]) is int, event


def watch_all_once(am):
    proc = am.run("watch", "--all")
    assert proc.returncode == 0, proc.stdout + proc.stderr
    payload = json.loads(proc.stdout)
    assert payload["ok"] is True, payload
    assert set(payload) == {"ok", "data"}, payload
    assert set(payload["data"]) == {"events"}, payload
    return payload["data"]["events"]


def watch_run_once(am, run_id, *extra):
    """The events of `am watch RUN_ID *extra`, which must exit 0 with exactly
    {"ok": true, "data": {"events": [...]}}; otherwise the test fails with
    am's stdout and stderr."""
    proc = am.run("watch", run_id, *extra)
    output = f"stdout={proc.stdout!r} stderr={proc.stderr!r}"
    assert proc.returncode == 0, output
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"am watch {run_id} printed no JSON envelope: {output}")
    assert isinstance(payload, dict) and payload.get("ok") is True, output
    assert set(payload) == {"ok", "data"}, output
    assert isinstance(payload["data"], dict) and set(payload["data"]) == {"events"}, output
    assert isinstance(payload["data"]["events"], list), output
    return payload["data"]["events"]


def assert_payload_keys(events):
    """Every watched event's payload has exactly its PAYLOAD_KEYS; events of
    other kinds are not checked."""
    for event in events:
        expected = PAYLOAD_KEYS.get(event["event"])
        if expected is not None:
            assert set(event["payload"]) == expected, \
                f"{event['event']} payload keys drifted: {sorted(event['payload'])} in {event}"


def cost_or_token_keys(payload):
    """The keys of `payload`, and of its dict values, naming a cost or a token
    (case-insensitive)."""
    keys = list(payload)
    for value in payload.values():
        if isinstance(value, dict):
            keys.extend(value)
    return [key for key in keys if "cost" in key.lower() or "token" in key.lower()]


def test_watch_all_returns_the_events_envelope_with_journal_line_keys(am, seeded_run):
    assert_seeded_events(watch_all_once(am), seeded_run, am.repo)


def test_watch_all_follow_prints_a_hello_line_then_journal_lines(am, seeded_run):
    expected = watch_all_once(am)
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
    assert set(hello) == HELLO_KEYS, hello
    assert hello["event"] == "watch", hello
    assert hello["schema"] in (1, 2), hello
    assert isinstance(hello["am"], str) and hello["am"], hello
    # Hermetic: the stream reads the throwaway data dir, not the user's.
    assert hello["runs_dir"] == str(am.data / "agent-manager" / "runs"), hello
    assert hello["head"] == seeded_run.head, hello
    assert hello["cursor_reset"] is False, hello
    assert isinstance(hello["store_id"], str) and hello["store_id"] == seeded_run.store_id, hello
    # The backlog replays the same events the one-shot envelope holds.
    assert events == expected
    assert_seeded_events(events, seeded_run, am.repo)


def fake_am(returncode, stdout, stderr=""):
    """A stand-in for the am fixture whose every run returns this output."""
    def run(*args):
        return subprocess.CompletedProcess(["am", *args], returncode, stdout, stderr)

    return SimpleNamespace(run=run)


def test_watch_run_once_fails_with_ams_output_on_a_refusal():
    refusal = json.dumps({"ok": False, "error": {"type": "UnknownRunError", "message": "no run r1"}})
    with pytest.raises(AssertionError, match="UnknownRunError.*boom"):
        watch_run_once(fake_am(3, refusal, "boom"), "r1")


def test_watch_run_once_fails_with_ams_output_when_it_prints_no_json():
    with pytest.raises(pytest.fail.Exception, match="not json.*traceback"):
        watch_run_once(fake_am(0, "not json", "traceback"), "r1")


def test_watch_run_returns_the_events_envelope_with_journal_line_keys(am, seeded_run):
    events = watch_run_once(am, seeded_run.id)
    assert_seeded_events(events, seeded_run, am.repo)
    # runs-events.py takes seq as the --since cursor: an int, never a bool or float.
    assert all(type(event["seq"]) is int for event in events), events


def test_watch_run_is_the_run_filtered_watch_all(am, seeded_run):
    expected = [event for event in watch_all_once(am) if event["run_id"] == seeded_run.id]
    assert watch_run_once(am, seeded_run.id) == expected


def test_watch_run_since_keeps_only_events_with_a_greater_seq(am, seeded_run):
    events = watch_run_once(am, seeded_run.id)
    assert len(events) >= 2, events
    last = events[-1]["seq"]
    assert watch_run_once(am, seeded_run.id, "--since", "0") == events
    assert watch_run_once(am, seeded_run.id, "--since", "1") == events[1:]
    assert watch_run_once(am, seeded_run.id, "--since", str(last - 1)) == [events[-1]]


def test_watch_run_since_at_or_beyond_the_last_seq_is_an_empty_events_list(am, seeded_run):
    """The "nothing new" reply runs-events.py turns into last_seq = SEQ."""
    events = watch_run_once(am, seeded_run.id)
    last = events[-1]["seq"]
    assert watch_run_once(am, seeded_run.id, "--since", str(last)) == []
    assert watch_run_once(am, seeded_run.id, "--since", str(last + 1000)) == []


def test_payload_keys_cover_exactly_the_watched_events():
    assert set(PAYLOAD_KEYS) == WATCHED_EVENTS


def test_assert_payload_keys_names_the_kind_that_drifted():
    drifted = {"event": "attempt_upsert", "payload": dict.fromkeys(
        PAYLOAD_KEYS["attempt_upsert"] | {"cost_usd"})}
    with pytest.raises(AssertionError, match="attempt_upsert payload keys drifted.*cost_usd"):
        assert_payload_keys([drifted])


def test_assert_payload_keys_ignores_other_kinds():
    lease = {"event": "lease_acquired",
             "payload": {"claims": [], "host": "h", "pid": 1, "token": "t"}}
    assert_payload_keys([lease])


def test_cost_or_token_keys_finds_top_level_and_nested_keys_in_any_case():
    payload = {"duration": 1.0, "Cost": 0.2,
               "dispatch": {"model": "sonnet", "input_tokens": 3}}
    assert cost_or_token_keys(payload) == ["Cost", "input_tokens"]


def test_cost_or_token_keys_of_an_attempt_without_them_is_empty():
    payload = {"duration": 1.0, "exit_code": 0, "status": "failed",
               "prompt_path": "p", "result_path": "r", "stdout_path": "s", "n": 1,
               "dispatch": {"harness": "claude", "model": "sonnet", "timeout": 1800.0}}
    assert cost_or_token_keys(payload) == []


def test_watched_event_payloads_carry_the_recorded_keys(am, seeded_run):
    events = watch_run_once(am, seeded_run.id)
    assert WATCHED_EVENTS <= {event["event"] for event in events}, events
    assert_payload_keys(events)


def test_attempt_payloads_carry_no_cost_or_token_keys(am, seeded_run):
    attempts = [event for event in watch_run_once(am, seeded_run.id)
                if event["event"] == "attempt_upsert"]
    assert attempts, "the seeded run recorded no attempt_upsert"
    for event in attempts:
        assert cost_or_token_keys(event["payload"]) == [], event


def missing_logs_follow_options(help_text):
    """The options `am logs --follow` readers need that `help_text` does not name, in the
    order --follow, --since-offset."""
    return [option for option in ("--follow", "--since-offset") if option not in help_text]


def test_missing_logs_follow_options_names_each_missing_option():
    assert missing_logs_follow_options("--follow ... --since-offset BYTES") == []
    assert missing_logs_follow_options("--phase --attempt") == ["--follow", "--since-offset"]
    assert missing_logs_follow_options("--follow") == ["--since-offset"]


def test_logs_help_lists_the_follow_options(am):
    proc = am.run("logs", "--help")
    assert proc.returncode == 0, proc.stdout + proc.stderr
    missing = missing_logs_follow_options(proc.stdout)
    if missing:
        pytest.fail(f"the installed am logs has no {', '.join(missing)} option "
                    "(reinstall agent-manager: uv tool install --reinstall)")
