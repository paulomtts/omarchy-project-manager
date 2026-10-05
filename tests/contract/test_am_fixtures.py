"""The committed am captures in tests/fixtures/am keep the shapes real am prints,
and the installed am still prints them.

Fixture contract: every capture is read with json.load and never written. Each
level has one exact key set (keys starting with "_" are annotations and are
ignored); status values come from am's run and attempt vocabularies. am status
data has no top-level "subtasks".

Live check: in the main checkout (the parent of git's common dir), am runs and
am status of the newest run must print the same key sets, with "story_id"
allowed as the one extra key on a runs row and on the status run. Read-only:
only --repo-dir is passed and the user's real runs are read, never written.
Skipped when am or git is absent or the checkout has no runs.
"""
import json
import shutil
import subprocess
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
FIXTURES = HERE.parent / "fixtures" / "am"
AM_TIMEOUT = 30

FIXTURE_NAMES = (
    "runs.json", "status-started.json", "status-done.json", "status-escalated.json",
    "status-escalated-integrate.json", "status-done-integrate.json", "watch-events.json",
    "watch-hello.json", "logs-attempt.json",
)
STATUS_FIXTURES = (
    "status-started.json", "status-done.json", "status-escalated.json",
    "status-escalated-integrate.json", "status-done-integrate.json",
)
E2E_FIXTURES = ("status-escalated.json", "status-escalated-integrate.json", "status-done-integrate.json")
NOTED_FIXTURES = E2E_FIXTURES + ("watch-events.json", "watch-hello.json")

ENVELOPE_KEYS = frozenset({"ok", "data"})
RUN_ROW_KEYS = frozenset({"id", "workflow", "repo_dir", "base_branch", "branch_prefix", "status",
                          "started_at", "milestone_id", "card_id", "lease", "progress"})
RUN_LEASE_KEYS = frozenset({"pid", "host", "heartbeat_at", "accepting", "live"})
PROGRESS_KEYS = frozenset({"stories", "subtasks", "current"})
COUNT_KEYS = frozenset({"done", "total"})
CURRENT_KEYS = frozenset({"card", "phase", "attempt"})
STATUS_DATA_KEYS = frozenset({"run", "stories", "rows", "control", "integrity"})
STATUS_RUN_KEYS = frozenset({"id", "workflow", "repo_dir", "base_branch", "branch_prefix", "status",
                             "started_at"})
STORY_KEYS = frozenset({"card_id", "title", "level", "status", "tip_branch", "subtasks"})
SUBTASK_KEYS = frozenset({"card_id", "branch", "base_branch", "status", "worktree_path", "phases"})
PHASE_KEYS = frozenset({"name", "kind", "status", "started_at", "ended_at", "detail", "attempts"})
ATTEMPT_KEYS = frozenset({"n", "status", "dispatch", "exit_code", "duration", "prompt_path",
                          "result_path", "stdout_path"})
ROW_KEYS = frozenset({"story", "subtask", "phase", "attempt", "state"})
CONTROL_KEYS = frozenset({"lease", "requests", "claims"})
CONTROL_LEASE_KEYS = RUN_LEASE_KEYS | {"acquired_at"}
LOGS_KEYS = frozenset({"run_id", "story_id", "card", "phase", "attempt", "status", "exit_code",
                       "artifacts"})
ARTIFACTS_KEYS = frozenset({"prompt", "result", "stdout", "stderr"})
ARTIFACT_KEYS = frozenset({"path", "present", "text"})
WATCH_DATA_KEYS = frozenset({"events"})
EVENT_KEYS = frozenset({"seq", "ts", "run_id", "event", "story", "card", "phase", "attempt", "payload"})
HELLO_FILE_KEYS = frozenset({"schema_1", "schema_2"})
HELLO_KEYS = frozenset({"event", "schema", "am", "runs_dir"})

RUN_STATUSES = frozenset({"pending", "started", "done", "failed", "escalated", "stopped",
                          "cancelled", "canceled"})
ATTEMPT_STATUSES = frozenset({"started", "ok", "schema_invalid", "gate_failed", "harness_error"})

# The installed am prints story_id on these two levels only; the captures predate it.
LIVE_EXTRA = {RUN_ROW_KEYS: frozenset({"story_id"}), STATUS_RUN_KEYS: frozenset({"story_id"})}


def load(name):
    with open(FIXTURES / name, encoding="utf-8") as fh:
        return json.load(fh)


def key_set(obj):
    return {key for key in obj if not key.startswith("_")}


def assert_keys(source, where, obj, expected, extra_allowed=frozenset()):
    assert isinstance(obj, dict), f"{source} {where}: expected an object, got {obj!r}"
    keys = key_set(obj)
    if keys == expected or keys == expected | extra_allowed:
        return
    missing = sorted(expected - keys)
    extra = sorted(keys - expected)
    pytest.fail(f"{source} {where}: missing {missing}, extra {extra}")


def run_row_levels(where, row):
    """(where, obj, expected key set) for an am runs row and every object inside it."""
    yield where, row, RUN_ROW_KEYS
    if row.get("lease") is not None:
        yield f"{where}.lease", row["lease"], RUN_LEASE_KEYS
    progress = row.get("progress")
    yield f"{where}.progress", progress, PROGRESS_KEYS
    if isinstance(progress, dict):
        yield f"{where}.progress.stories", progress.get("stories"), COUNT_KEYS
        yield f"{where}.progress.subtasks", progress.get("subtasks"), COUNT_KEYS
        if progress.get("current") is not None:
            yield f"{where}.progress.current", progress["current"], CURRENT_KEYS


def check_runs_row(source, where, row, extra_allowed=None):
    """A row's key sets and status; extra_allowed maps an expected set to keys also accepted."""
    for level, obj, expected in run_row_levels(where, row):
        assert_keys(source, level, obj, expected, (extra_allowed or {}).get(expected, frozenset()))
    assert row["status"] in RUN_STATUSES, f"{source} {where}.status: {row['status']!r}"


def check_runs_rows(source, rows, extra_allowed=None):
    for i, row in enumerate(rows):
        check_runs_row(source, f"runs[{i}]", row, extra_allowed)


def runs_rows_of_fixtures():
    """(source, where, row) for every runs.json row and every e2e capture's _am_runs_row."""
    rows = [("runs.json", f"runs[{i}]", row) for i, row in enumerate(load("runs.json")["data"]["runs"])]
    return rows + [(name, "_am_runs_row", load(name)["_am_runs_row"]) for name in E2E_FIXTURES]


def status_levels(data):
    """(where, obj, expected key set) for am status data and every level inside it."""
    yield "data", data, STATUS_DATA_KEYS
    yield "data.run", data.get("run"), STATUS_RUN_KEYS
    for s, story in enumerate(data.get("stories") or []):
        yield f"stories[{s}]", story, STORY_KEYS
        for t, subtask in enumerate(story.get("subtasks") or []):
            yield f"stories[{s}].subtasks[{t}]", subtask, SUBTASK_KEYS
            for p, phase in enumerate(subtask.get("phases") or []):
                where = f"stories[{s}].subtasks[{t}].phases[{p}]"
                yield where, phase, PHASE_KEYS
                for a, attempt in enumerate(phase.get("attempts") or []):
                    yield f"{where}.attempts[{a}]", attempt, ATTEMPT_KEYS
    for r, row in enumerate(data.get("rows") or []):
        yield f"rows[{r}]", row, ROW_KEYS
    control = data.get("control")
    yield "control", control, CONTROL_KEYS
    if isinstance(control, dict) and control.get("lease") is not None:
        yield "control.lease", control["lease"], CONTROL_LEASE_KEYS


def status_statuses(data):
    """(where, status, vocabulary) for the run and every story, subtask, phase and attempt."""
    yield "data.run.status", data["run"]["status"], RUN_STATUSES
    for s, story in enumerate(data["stories"]):
        yield f"stories[{s}].status", story["status"], RUN_STATUSES
        for t, subtask in enumerate(story["subtasks"]):
            yield f"stories[{s}].subtasks[{t}].status", subtask["status"], RUN_STATUSES
            for p, phase in enumerate(subtask["phases"]):
                where = f"stories[{s}].subtasks[{t}].phases[{p}]"
                yield f"{where}.status", phase["status"], RUN_STATUSES
                for a, attempt in enumerate(phase["attempts"]):
                    yield f"{where}.attempts[{a}].status", attempt["status"], ATTEMPT_STATUSES


def check_status_data(source, data, extra_allowed=None):
    """Every level's key set and every status of am status data."""
    for where, obj, expected in status_levels(data):
        assert_keys(source, where, obj, expected, (extra_allowed or {}).get(expected, frozenset()))
    for where, status, vocabulary in status_statuses(data):
        assert status in vocabulary, f"{source} {where}: {status!r} not in {sorted(vocabulary)}"


@pytest.mark.parametrize("name", FIXTURE_NAMES)
def test_every_fixture_exists_and_parses(name):
    path = FIXTURES / name
    assert path.is_file(), f"{name}: missing from {FIXTURES}"
    try:
        load(name)
    except json.JSONDecodeError as err:
        pytest.fail(f"{name}: not JSON: {err}")


@pytest.mark.parametrize("name", [n for n in FIXTURE_NAMES if n != "watch-hello.json"])
def test_envelopes_are_ok_data(name):
    payload = load(name)
    assert_keys(name, "envelope", payload, ENVELOPE_KEYS)
    assert payload["ok"] is True, f"{name}: ok is {payload['ok']!r}"


def test_assert_keys_names_source_level_missing_and_extra():
    with pytest.raises(pytest.fail.Exception) as failure:
        assert_keys("x.json", "runs[0].progress", {"stories": 1, "extra": 2, "_note": 3}, PROGRESS_KEYS)
    assert str(failure.value) == "x.json runs[0].progress: missing ['current', 'subtasks'], extra ['extra']"
    with pytest.raises(AssertionError, match=r"x\.json runs\[0\]\.progress: expected an object, got None"):
        assert_keys("x.json", "runs[0].progress", None, PROGRESS_KEYS)


def test_runs_rows_key_sets():
    rows = load("runs.json")["data"]["runs"]
    assert rows, "runs.json: no data.runs rows"
    assert any(row["lease"] is not None for row in rows), "runs.json: no row has a lease"
    assert any(row["progress"]["current"] is not None for row in rows), \
        "runs.json: no row has a progress.current"
    for source, where, row in runs_rows_of_fixtures():
        check_runs_row(source, where, row)


def test_runs_row_statuses_are_in_the_run_vocabulary():
    for source, where, row in runs_rows_of_fixtures():
        assert row["status"] in RUN_STATUSES, f"{source} {where}.status: {row['status']!r}"


def test_runs_row_failures_name_the_fixture_and_the_row_once():
    row = dict(load("status-escalated.json")["_am_runs_row"], progress=None)
    with pytest.raises(AssertionError, match=r"^status-escalated\.json _am_runs_row\.progress: expected"):
        check_runs_row("status-escalated.json", "_am_runs_row", row)
    labels = [(source, where) for source, where, _ in runs_rows_of_fixtures()]
    assert labels[0] == ("runs.json", "runs[0]"), labels


@pytest.mark.parametrize("name", STATUS_FIXTURES)
def test_status_data_has_no_top_level_subtasks(name):
    assert "subtasks" not in load(name)["data"], f"{name}: data has a top-level subtasks"


@pytest.mark.parametrize("name", STATUS_FIXTURES)
def test_status_key_sets_at_every_level(name):
    data = load(name)["data"]
    for where, obj, expected in status_levels(data):
        assert_keys(name, where, obj, expected)
    assert isinstance(data["control"]["requests"], list), f"{name} control.requests: not a list"
    assert isinstance(data["control"]["claims"], list), f"{name} control.claims: not a list"


def test_status_fixtures_reach_attempts_and_a_control_lease():
    levels = [expected for name in STATUS_FIXTURES for _, _, expected in status_levels(load(name)["data"])]
    assert ATTEMPT_KEYS in levels, "no status fixture has an attempt"
    assert load("status-started.json")["data"]["control"]["lease"] is not None, \
        "status-started.json: control.lease is null"


@pytest.mark.parametrize("name", STATUS_FIXTURES)
def test_status_vocabularies(name):
    for where, status, vocabulary in status_statuses(load(name)["data"]):
        assert status in vocabulary, f"{name} {where}: {status!r} not in {sorted(vocabulary)}"


def test_logs_key_sets():
    data = load("logs-attempt.json")["data"]
    assert_keys("logs-attempt.json", "data", data, LOGS_KEYS)
    assert_keys("logs-attempt.json", "data.artifacts", data["artifacts"], ARTIFACTS_KEYS)
    for kind, artifact in data["artifacts"].items():
        assert_keys("logs-attempt.json", f"data.artifacts.{kind}", artifact, ARTIFACT_KEYS)


def test_watch_event_key_sets():
    data = load("watch-events.json")["data"]
    assert_keys("watch-events.json", "data", data, WATCH_DATA_KEYS)
    assert data["events"], "watch-events.json: no events"
    for i, event in enumerate(data["events"]):
        assert_keys("watch-events.json", f"events[{i}]", event, EVENT_KEYS)


def test_hello_key_sets_and_schemas():
    hellos = load("watch-hello.json")
    assert_keys("watch-hello.json", "top level", hellos, HELLO_FILE_KEYS)
    for key, schema in (("schema_1", 1), ("schema_2", 2)):
        hello = hellos[key]
        assert_keys("watch-hello.json", key, hello, HELLO_KEYS)
        assert hello["schema"] == schema, f"watch-hello.json {key}: schema {hello['schema']!r}"
        assert hello["event"] == "watch", f"watch-hello.json {key}: event {hello['event']!r}"


def test_note_is_on_exactly_the_annotated_captures():
    noted = sorted(name for name in FIXTURE_NAMES if "_note" in load(name))
    assert noted == sorted(NOTED_FIXTURES), noted
    with_row = sorted(name for name in FIXTURE_NAMES if "_am_runs_row" in load(name))
    assert with_row == sorted(E2E_FIXTURES), with_row


def git_main_checkout():
    """The main checkout's root, or None when git is absent or fails here."""
    try:
        proc = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                              cwd=HERE, capture_output=True, text=True, timeout=AM_TIMEOUT)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    return Path(proc.stdout.strip()).parent


def am_json(*args):
    # A hung am fails the test (TimeoutExpired) instead of hanging the suite.
    proc = subprocess.run(["am", *args], capture_output=True, text=True, timeout=AM_TIMEOUT)
    return proc.returncode, proc.stdout, proc.stderr


def test_installed_am_prints_the_fixture_key_sets():
    if shutil.which("am") is None:
        pytest.skip("am is not installed here")
    main = git_main_checkout()
    if main is None:
        pytest.skip("git could not name the main checkout")
    code, out, err = am_json("runs", "--repo-dir", str(main))
    if code != 0:
        pytest.skip(f"am runs --repo-dir {main} exited {code}: {err.strip()}")
    rows = json.loads(out).get("data", {}).get("runs") or []
    if not rows:
        pytest.skip(f"am has no runs for {main}")
    check_runs_rows("live am runs", rows, LIVE_EXTRA)
    newest = max(rows, key=lambda row: row["started_at"])
    code, out, err = am_json("status", newest["id"], "--repo-dir", str(main))
    assert code == 0, f"am status {newest['id']} exited {code}: {out}{err}"
    check_status_data(f"live am status {newest['id']}", json.loads(out)["data"], LIVE_EXTRA)


def test_live_allowance_is_story_id_on_the_runs_row_and_status_run_only():
    assert set(LIVE_EXTRA) == {RUN_ROW_KEYS, STATUS_RUN_KEYS}
    run = dict.fromkeys(STATUS_RUN_KEYS | {"story_id"})
    assert_keys("live", "data.run", run, STATUS_RUN_KEYS, LIVE_EXTRA[STATUS_RUN_KEYS])
    story = dict.fromkeys(STORY_KEYS | {"story_id"})
    with pytest.raises(pytest.fail.Exception, match=r"extra \['story_id'\]"):
        assert_keys("live", "stories[0]", story, STORY_KEYS, LIVE_EXTRA.get(STORY_KEYS, frozenset()))


def test_live_status_check_rejects_a_status_outside_the_vocabularies():
    data = load("status-done.json")["data"]
    data["run"]["story_id"] = "s"
    check_status_data("live", data, LIVE_EXTRA)
    data["stories"][0]["subtasks"][0]["phases"][1]["attempts"][0]["status"] = "done"
    attempt = r"stories\[0\]\.subtasks\[0\]\.phases\[1\]\.attempts\[0\]\.status"
    with pytest.raises(AssertionError, match=rf"^live {attempt}: 'done'"):
        check_status_data("live", data, LIVE_EXTRA)
    data["run"]["status"] = "bogus"
    with pytest.raises(AssertionError, match=r"^live data\.run\.status: 'bogus'"):
        check_status_data("live", data, LIVE_EXTRA)


def test_live_check_skips_when_am_is_not_on_path(monkeypatch, tmp_path):
    monkeypatch.setenv("PATH", str(tmp_path))
    with pytest.raises(pytest.skip.Exception, match="am is not installed here"):
        test_installed_am_prints_the_fixture_key_sets()


def test_live_check_reads_the_main_checkout_not_a_worktree():
    main = git_main_checkout()
    if main is None:
        pytest.skip("git could not name the main checkout")
    assert (main / ".git").is_dir(), f"{main}: not a main checkout (no .git directory)"

