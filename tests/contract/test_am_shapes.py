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

Finished-run tests add to that PATH the stub claude (stub_claude.py, run by
this interpreter) and verify-ok, so story S1 runs to done; they fail, never
skip, when it does not. Their am logs --follow captures, with the scratch root
rewritten to /home/user, equal tests/fixtures/am/logs-follow-agent.jsonl,
logs-follow-step.jsonl and logs-follow-refusal.json; with AM_RECORD_FIXTURES=1
the captures are written there instead.
"""
import json
import os
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path
from types import SimpleNamespace

import pytest

import stub_claude

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


FIXTURES = Path(__file__).resolve().parent.parent / "fixtures" / "am"
RECORD_ENV = "AM_RECORD_FIXTURES"
SCRATCH_HOME = "/home/user"


def normalize(value, root):
    """`value` with `root` replaced by /home/user in every string, keys untouched."""
    if isinstance(value, str):
        return value.replace(str(root), SCRATCH_HOME)
    if isinstance(value, dict):
        return {key: normalize(item, root) for key, item in value.items()}
    if isinstance(value, list):
        return [normalize(item, root) for item in value]
    return value


def test_normalize_rewrites_only_the_scratch_root():
    root = "/tmp/pytest-of-u/pytest-7/test_x0"
    value = {f"{root}/key": [f"{root}/data/a.log", {"text": f"see {root}/b"}],
             "offset": 12, "status": "ok", "other": "/tmp/pytest-of-u/elsewhere"}
    assert normalize(value, root) == {
        f"{root}/key": ["/home/user/data/a.log", {"text": "see /home/user/b"}],
        "offset": 12, "status": "ok", "other": "/tmp/pytest-of-u/elsewhere"}


def recorded_fixture(name, text):
    """The committed tests/fixtures/am/`name`. With AM_RECORD_FIXTURES=1, `text` is written
    there first; with it unset, a missing file fails naming the file and the variable."""
    path = FIXTURES / name
    if os.environ.get(RECORD_ENV) == "1":
        path.write_text(text, encoding="utf-8")
    if not path.is_file():
        pytest.fail(f"{path} is missing: record it with {RECORD_ENV}=1")
    return path.read_text(encoding="utf-8")


def test_recorded_fixture_fails_naming_the_file_and_the_variable(monkeypatch, tmp_path):
    monkeypatch.setattr(sys.modules[__name__], "FIXTURES", tmp_path)
    monkeypatch.delenv(RECORD_ENV, raising=False)
    with pytest.raises(pytest.fail.Exception,
                       match=r"logs-follow-x\.jsonl is missing.*AM_RECORD_FIXTURES=1"):
        recorded_fixture("logs-follow-x.jsonl", "{}\n")


def test_recorded_fixture_writes_the_capture_when_recording(monkeypatch, tmp_path):
    monkeypatch.setattr(sys.modules[__name__], "FIXTURES", tmp_path)
    monkeypatch.setenv(RECORD_ENV, "1")
    assert recorded_fixture("logs-follow-x.jsonl", "{}\n") == "{}\n"
    assert (tmp_path / "logs-follow-x.jsonl").read_text() == "{}\n"


LOGS_HELLO_KEYS = {"event", "offset", "path", "schema"}
CHUNK_KEYS = {"offset", "text"}
END_KEYS = {"event", "status"}
END_STATUSES = {"ok", "schema_invalid", "gate_failed", "harness_error"}


def json_lines(stdout):
    """Each stdout line of am parsed as one JSON object; fails naming a line that is not."""
    lines = []
    for index, raw in enumerate(stdout.splitlines()):
        try:
            line = json.loads(raw)
        except json.JSONDecodeError:
            pytest.fail(f"line {index} is not JSON: {raw!r}")
        if not isinstance(line, dict):
            pytest.fail(f"line {index} is not a JSON object: {raw!r}")
        lines.append(line)
    return lines


def follow_stream_text(lines, path_prefix, path_suffix):
    """The joined chunk text of one whole `am logs --follow` stream.

    The stream is a hello `{event: "logs", offset, path, schema}` whose path starts with
    `path_prefix` and ends with `path_suffix`, one or more contiguous `{offset, text}`
    chunks from the hello's offset, and an `{event: "end", status}` line. No line has an
    `ok` key. A line that breaks this fails naming its index and its keys.
    """
    def drift(index, why):
        pytest.fail(f"line {index} {why}: keys {sorted(lines[index])} in {lines[index]!r}")

    if len(lines) < 3:
        pytest.fail(f"a stream is a hello, one or more chunks and an end; got {lines!r}")
    for index, line in enumerate(lines):
        if "ok" in line:
            drift(index, "has an ok key")
    hello, chunks, end = lines[0], lines[1:-1], lines[-1]
    if set(hello) != LOGS_HELLO_KEYS or hello["event"] != "logs":
        drift(0, "is not a logs hello")
    if type(hello["offset"]) is not int or hello["schema"] not in (1, 2):
        drift(0, "has a bad offset or schema")
    path = hello["path"]
    if not (isinstance(path, str) and path.startswith(path_prefix) and path.endswith(path_suffix)):
        drift(0, f"has a path outside {path_prefix}...{path_suffix}")
    offset = hello["offset"]
    for index, chunk in enumerate(chunks, start=1):
        if set(chunk) != CHUNK_KEYS or not isinstance(chunk["text"], str):
            drift(index, "is not a chunk")
        if type(chunk["offset"]) is not int or chunk["offset"] != offset:
            drift(index, f"does not start at byte {offset}")
        offset += len(chunk["text"].encode("utf-8"))
    if set(end) != END_KEYS or end["event"] != "end" or end["status"] not in END_STATUSES:
        drift(len(lines) - 1, "is not an end line")
    return "".join(chunk["text"] for chunk in chunks)


STREAM = [{"event": "logs", "offset": 0, "path": "/d/runs/r/c/review.1/stdout.log", "schema": 1},
          {"offset": 0, "text": "é\n"}, {"offset": 3, "text": "b\n"},
          {"event": "end", "status": "ok"}]


def test_follow_stream_text_joins_contiguous_chunks_counting_utf8_bytes():
    assert follow_stream_text(STREAM, "/d/runs/", "/c/review.1/stdout.log") == "é\nb\n"


@pytest.mark.parametrize("index, line, message", [
    (0, {**STREAM[0], "am": "0.2.0"}, r"line 0 is not a logs hello: keys \['am', 'event'"),
    (2, {"offset": 4, "text": "b\n"}, r"line 2 does not start at byte 3: keys \['offset', 'text'\]"),
    (3, {"event": "end"}, r"line 3 is not an end line: keys \['event'\]"),
    (3, {"event": "end", "status": "ok", "ok": True},
     r"line 3 has an ok key: keys \['event', 'ok', 'status'\]"),
])
def test_follow_stream_checker_names_the_line_that_drifted(index, line, message):
    drifted = [*STREAM[:index], line, *STREAM[index + 1:]]
    with pytest.raises(pytest.fail.Exception, match=message):
        follow_stream_text(drifted, "/d/runs/", "/c/review.1/stdout.log")


def test_follow_stream_checker_fails_on_a_stream_with_no_chunk():
    with pytest.raises(pytest.fail.Exception, match="one or more chunks"):
        follow_stream_text([STREAM[0], STREAM[-1]], "/d/runs/", "/c/review.1/stdout.log")


def test_json_lines_names_a_line_that_is_not_a_json_object():
    with pytest.raises(pytest.fail.Exception, match=r"line 1 is not a JSON object: '\[1\]'"):
        json_lines('{"a": 1}\n[1]\n')


STUB_CLAUDE = Path(__file__).resolve().parent / "stub_claude.py"


def test_stub_claude_refuses_a_field_the_schema_lacks():
    with pytest.raises(stub_claude.StubError, match="no field 'summary'.*'synopsis'"):
        stub_claude.override({"synopsis": ""}, summary="x")


def test_stub_claude_zero_payload_follows_refs_and_nullable_fields():
    schema = {"$defs": {"V": {"properties": {"lint": {"type": "array"},
                                              "typecheck": {"type": "string"}}}},
              "properties": {"verification": {"$ref": "#/$defs/V"},
                             "reason": {"anyOf": [{"type": "string"}, {"type": "null"}]},
                             "refused": {"type": "boolean"}, "n": {"type": "integer"}}}
    assert stub_claude.zero_payload(schema) == {
        "verification": {"lint": [], "typecheck": ""}, "reason": None, "refused": False, "n": 0}


def test_stub_claude_exits_1_naming_a_phase_it_has_no_behaviour_for(tmp_path):
    result = tmp_path / "result.json"
    brief = tmp_path / "prompt.txt"
    brief.write_text("# phase: resolve\n# role: resolver\n\n## Result contract\n"
                     "When you are done, write your result as valid JSON to exactly this path:\n\n"
                     f"{result}\n\n```json\n{{\"properties\": {{}}}}\n```\n", encoding="utf-8")
    proc = subprocess.run([sys.executable, str(STUB_CLAUDE), "-p",
                           f"Read {brief} and follow the instructions in it exactly. Go."],
                          cwd=tmp_path, capture_output=True, text=True, timeout=AM_TIMEOUT)
    assert proc.returncode == 1, proc.stdout + proc.stderr
    assert "stub claude: no behaviour for phase 'resolve'" in proc.stderr, proc.stderr
    assert proc.stdout == "" and not result.exists()


def stub_executable(path, body):
    """`body` as an executable at `path`, run by this interpreter."""
    path.write_text(f"#!{os.path.realpath(sys.executable)}\n{body}", encoding="utf-8")
    path.chmod(0o755)


@pytest.fixture
def finished_run(am, story_board, tmp_path):
    """Story S1 run to done through the real am: the bin dir also holds the stub `claude`
    and `verify-ok` (prints `verified`, exits 0), the run's only verify command."""
    bin_dir = tmp_path / "bin"
    stub_executable(bin_dir / "claude", STUB_CLAUDE.read_text(encoding="utf-8"))
    stub_executable(bin_dir / "verify-ok", 'print("verified")\n')
    proc = am.run("run", "--story", story_board.s1, "--branch-prefix", "p", "--verify",
                  "verify-ok", "--repo-dir", am.repo)
    output = f"stdout={proc.stdout!r} stderr={proc.stderr!r}"
    if proc.returncode != 0:
        pytest.fail(f"am run of story S1 exited {proc.returncode}: {output}")
    runs = am.run("runs", "--repo-dir", am.repo)
    rows = json.loads(runs.stdout)["data"]["runs"] if runs.returncode == 0 else None
    if not rows or len(rows) != 1 or rows[0]["status"] != "done":
        pytest.fail(f"am run of story S1 did not finish as one done run: runs={runs.stdout!r} "
                    f"{output}")
    return SimpleNamespace(id=rows[0]["id"], card=story_board.s1_subtasks[0], root=tmp_path)


def phases_of(am, run, card):
    """`am status RUN`'s phases of subtask `card`, by name."""
    proc = am.run("status", run.id, "--repo-dir", am.repo)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    subtasks = [subtask for story in json.loads(proc.stdout)["data"]["stories"]
                for subtask in story["subtasks"] if subtask["card_id"] == card]
    assert len(subtasks) == 1, proc.stdout
    return {phase["name"]: phase for phase in subtasks[0]["phases"]}


def test_finished_run_reaches_verify_and_is_done(am, finished_run):
    phases = phases_of(am, finished_run, finished_run.card)
    assert [(attempt["n"], attempt["status"]) for attempt in phases["review"]["attempts"]] \
        == [(1, "ok")], phases["review"]
    assert phases["verify"]["status"] == "done", phases["verify"]
    assert phases["verify"]["attempts"] == [], phases["verify"]
    assert phases["worktree"]["attempts"] == [], phases["worktree"]


def follow(am, run, card, *selector):
    """`am logs RUN CARD *selector --follow` on a terminal attempt, which exits by itself."""
    return am.run("logs", run.id, card, *selector, "--follow", "--repo-dir", am.repo)


def jsonl(lines):
    """`lines` as one compact JSON object per line, each ending in a newline."""
    return "".join(json.dumps(line, separators=(",", ":"), ensure_ascii=False) + "\n"
                   for line in lines)


def hello_shape(hello, phase):
    """`hello` with its path replaced by whether it reads
    /home/user/data/agent-manager/runs/<run>/<card>/<phase>.1/stdout.log."""
    shape = re.compile(rf"{SCRATCH_HOME}/data/agent-manager/runs/[^/]+/[^/]+/"
                       rf"{re.escape(phase)}\.1/stdout\.log")
    return {**hello, "path": bool(shape.fullmatch(str(hello.get("path"))))}


def assert_stream_matches_fixture(lines, name, phase):
    """The normalized stream `lines` equals tests/fixtures/am/`name` line for line; the
    hello's path is compared by shape only."""
    fixture = [json.loads(line) for line in recorded_fixture(name, jsonl(lines)).splitlines()]
    assert hello_shape(lines[0], phase)["path"] is True, lines[0]
    assert [hello_shape(fixture[0], phase), *fixture[1:]] == \
        [hello_shape(lines[0], phase), *lines[1:]], (name, fixture, lines)


def test_hello_shape_accepts_only_a_normalized_attempt_log_path():
    hello = {"event": "logs", "offset": 0, "schema": 1,
             "path": "/home/user/data/agent-manager/runs/r1/c1/review.1/stdout.log"}
    assert hello_shape(hello, "review") == {**hello, "path": True}
    assert hello_shape(hello, "verify")["path"] is False
    assert hello_shape({**hello, "path": "/tmp/x/data/agent-manager/runs/r1/c1/review.1/stdout.log"},
                       "review")["path"] is False


def test_logs_follow_of_an_agent_attempt_prints_hello_chunks_and_end(am, finished_run):
    proc = follow(am, finished_run, finished_run.card, "--phase", "review", "--attempt", "1")
    assert proc.returncode == 0, proc.stdout + proc.stderr
    lines = json_lines(proc.stdout)
    text = follow_stream_text(lines, f"{am.data}/agent-manager/runs/",
                              f"/{finished_run.card}/review.1/stdout.log")
    assert text == "stub claude ok phase=review\n", lines
    assert lines[-1]["status"] == "ok", lines[-1]
    assert_stream_matches_fixture(normalize(lines, finished_run.root),
                                  "logs-follow-agent.jsonl", "review")
