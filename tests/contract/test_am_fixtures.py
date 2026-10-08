"""The committed am captures in tests/fixtures/am keep the shapes real am prints,
and the installed am still prints them.

Fixture contract: every capture is read with json.load and never written. Each
level has one exact key set (keys starting with "_" are annotations and are
ignored); status values come from am's run and attempt vocabularies. am status
data has no top-level "subtasks". Every capture carries a "_note" naming
agent-manager 0.2.0; the captures share one store_id; an event's gseq strictly
increases and an am events page's head is at least its last gseq.

Live check: am runs with HOME, XDG_DATA_HOME and XDG_STATE_HOME under a scratch
dir, never the user's data dir. am runs data must carry "as_of_seq" and the
first line of am watch --all --follow (the hello) must carry "head", each a
non-negative int; a missing one fails naming the key and "the plugin needs the
newer am". Rows present, and am status of the newest, must print exactly the
capture key sets: a missing or an unknown key fails naming it. Skipped only
when am is absent.
"""
import json
import os
import shlex
import shutil
import subprocess
import time
from pathlib import Path

import pytest

from test_am_shapes import FOLLOW_TIMEOUT, read_lines

HERE = Path(__file__).resolve().parent
FIXTURES = HERE.parent / "fixtures" / "am"
AM_TIMEOUT = 30

FIXTURE_NAMES = (
    "runs.json", "status-started.json", "status-done.json", "status-escalated.json",
    "status-escalated-integrate.json", "status-done-integrate.json", "watch-events.json",
    "watch-hello.json", "logs-attempt.json", "events.json",
)
STATUS_FIXTURES = (
    "status-started.json", "status-done.json", "status-escalated.json",
    "status-escalated-integrate.json", "status-done-integrate.json",
)
E2E_FIXTURES = ("status-escalated.json", "status-escalated-integrate.json", "status-done-integrate.json")
NOTED_FIXTURES = FIXTURE_NAMES
NOTE_AM = "agent-manager 0.2.0"

ENVELOPE_KEYS = frozenset({"ok", "data"})
RUNS_DATA_KEYS = frozenset({"as_of_seq", "runs", "store_id"})
RUN_ROW_KEYS = frozenset({"id", "workflow", "repo_dir", "base_branch", "branch_prefix", "status",
                          "started_at", "milestone_id", "card_id", "lease", "progress", "project",
                          "story_id"})
RUN_LEASE_KEYS = frozenset({"pid", "host", "heartbeat_at", "accepting", "live"})
PROGRESS_KEYS = frozenset({"stories", "subtasks", "current"})
COUNT_KEYS = frozenset({"done", "total"})
CURRENT_KEYS = frozenset({"card", "phase", "attempt"})
STATUS_DATA_KEYS = frozenset({"run", "stories", "rows", "control", "integrity", "as_of_seq",
                              "store_id", "warnings"})
STATUS_RUN_KEYS = frozenset({"id", "workflow", "repo_dir", "base_branch", "branch_prefix", "status",
                             "started_at", "story_id"})
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
EVENTS_DATA_KEYS = frozenset({"events", "head"})
EVENT_KEYS = frozenset({"seq", "ts", "run_id", "event", "story", "card", "phase", "attempt", "payload",
                        "gseq"})
HELLO_FILE_KEYS = frozenset({"schema_1", "schema_2"})
HELLO_KEYS = frozenset({"am", "cursor_reset", "event", "head", "runs_dir", "schema", "store_id"})
HELLO_V1_KEYS = frozenset({"am", "event", "runs_dir", "schema"})

RUN_STATUSES = frozenset({"pending", "started", "done", "failed", "escalated", "stopped",
                          "cancelled", "canceled"})
ATTEMPT_STATUSES = frozenset({"started", "ok", "schema_invalid", "gate_failed", "harness_error"})

PROJECT_KEYS = frozenset({"id", "repo_dir"})


def load(name):
    with open(FIXTURES / name, encoding="utf-8") as fh:
        return json.load(fh)


def key_set(obj):
    return {key for key in obj if not key.startswith("_")}


def assert_keys(source, where, obj, expected):
    assert isinstance(obj, dict), f"{source} {where}: expected an object, got {obj!r}"
    keys = key_set(obj)
    if keys == expected:
        return
    missing = sorted(expected - keys)
    extra = sorted(keys - expected)
    pytest.fail(f"{source} {where}: missing {missing}, extra {extra}")


def run_row_levels(where, row):
    """(where, obj, expected key set) for an am runs row and every object inside it."""
    yield where, row, RUN_ROW_KEYS
    yield f"{where}.project", row.get("project"), PROJECT_KEYS
    if row.get("lease") is not None:
        yield f"{where}.lease", row["lease"], RUN_LEASE_KEYS
    progress = row.get("progress")
    yield f"{where}.progress", progress, PROGRESS_KEYS
    if isinstance(progress, dict):
        yield f"{where}.progress.stories", progress.get("stories"), COUNT_KEYS
        yield f"{where}.progress.subtasks", progress.get("subtasks"), COUNT_KEYS
        if progress.get("current") is not None:
            yield f"{where}.progress.current", progress["current"], CURRENT_KEYS


def check_runs_row(source, where, row):
    """A row's key sets, its project's included, and its status."""
    for level, obj, expected in run_row_levels(where, row):
        assert_keys(source, level, obj, expected)
    assert row["status"] in RUN_STATUSES, f"{source} {where}.status: {row['status']!r}"


def check_runs_rows(source, rows):
    for i, row in enumerate(rows):
        check_runs_row(source, f"runs[{i}]", row)


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


def check_status_data(source, data):
    """Every level's key set and every status of am status data."""
    for where, obj, expected in status_levels(data):
        assert_keys(source, where, obj, expected)
    for where, status, vocabulary in status_statuses(data):
        assert status in vocabulary, f"{source} {where}: {status!r} not in {sorted(vocabulary)}"


def check_count(where, value):
    """value is a non-negative int; a bool is not."""
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        pytest.fail(f"{where}: {value!r}")


def check_store_id(where, value):
    """value is a non-empty string."""
    if not isinstance(value, str) or not value:
        pytest.fail(f"{where}: {value!r}")


def check_gseqs(source, events):
    """Every event's gseq is an int and each is greater than the one before."""
    previous = None
    for i, event in enumerate(events):
        gseq = event["gseq"]
        if isinstance(gseq, bool) or not isinstance(gseq, int):
            pytest.fail(f"{source} events[{i}].gseq: {gseq!r}")
        if previous is not None and gseq <= previous:
            pytest.fail(f"{source} events[{i}].gseq: {gseq} after {previous}")
        previous = gseq


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


def test_runs_data_key_set_and_scalars():
    data = load("runs.json")["data"]
    assert_keys("runs.json", "data", data, RUNS_DATA_KEYS)
    check_count("runs.json data.as_of_seq", data["as_of_seq"])
    check_store_id("runs.json data.store_id", data["store_id"])


def test_runs_row_project_failures_name_the_level():
    # synthetic: a capture row with project dropped, then with an unknown project key
    row = load("runs.json")["data"]["runs"][0]
    del row["project"]
    with pytest.raises(pytest.fail.Exception) as failure:
        check_runs_row("runs.json", "runs[0]", row)
    assert str(failure.value) == "runs.json runs[0]: missing ['project'], extra []"
    row = load("runs.json")["data"]["runs"][0]
    row["project"]["name"] = "x"
    with pytest.raises(pytest.fail.Exception) as failure:
        check_runs_row("runs.json", "runs[0]", row)
    assert str(failure.value) == "runs.json runs[0].project: missing [], extra ['name']"


def test_runs_rows_pair_with_the_started_and_done_captures():
    rows = load("runs.json")["data"]["runs"]
    assert len(rows) >= 2, f"runs.json: {len(rows)} rows"
    assert rows[0]["id"] == load("status-started.json")["data"]["run"]["id"], rows[0]["id"]
    assert rows[1]["id"] == load("status-done.json")["data"]["run"]["id"], rows[1]["id"]


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


@pytest.mark.parametrize("name", STATUS_FIXTURES)
def test_status_data_scalars(name):
    data = load(name)["data"]
    check_count(f"{name} data.as_of_seq", data["as_of_seq"])
    check_store_id(f"{name} data.store_id", data["store_id"])
    warnings = data["warnings"]
    assert isinstance(warnings, list), f"{name} data.warnings: {warnings!r}"
    for i, warning in enumerate(warnings):
        assert isinstance(warning, str), f"{name} data.warnings[{i}]: {warning!r}"


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
    check_gseqs("watch-events.json", data["events"])


def test_events_page_key_sets_and_head():
    data = load("events.json")["data"]
    assert_keys("events.json", "data", data, EVENTS_DATA_KEYS)
    assert data["events"], "events.json: no events"
    for i, event in enumerate(data["events"]):
        assert_keys("events.json", f"events[{i}]", event, EVENT_KEYS)
    check_gseqs("events.json", data["events"])
    check_count("events.json data.head", data["head"])
    last = data["events"][-1]["gseq"]
    assert data["head"] >= last, f"events.json data.head: {data['head']} below the last gseq {last}"


def test_check_gseqs_names_the_file_and_the_values():
    # synthetic: gseqs that repeat, then one that is not an int
    with pytest.raises(pytest.fail.Exception) as failure:
        check_gseqs("x.json", [{"gseq": 3}, {"gseq": 3}])
    assert str(failure.value) == "x.json events[1].gseq: 3 after 3"
    with pytest.raises(pytest.fail.Exception) as failure:
        check_gseqs("x.json", [{"gseq": True}])
    assert str(failure.value) == "x.json events[0].gseq: True"


def test_hello_key_sets_and_schemas():
    hellos = load("watch-hello.json")
    assert_keys("watch-hello.json", "top level", hellos, HELLO_FILE_KEYS)
    for key, schema, expected in (("schema_1", 1, HELLO_V1_KEYS), ("schema_2", 2, HELLO_KEYS)):
        hello = hellos[key]
        assert_keys("watch-hello.json", key, hello, expected)
        assert hello["schema"] == schema, f"watch-hello.json {key}: schema {hello['schema']!r}"
        assert hello["event"] == "watch", f"watch-hello.json {key}: event {hello['event']!r}"
    hello = hellos["schema_2"]
    check_count("watch-hello.json schema_2.head", hello["head"])
    assert isinstance(hello["cursor_reset"], bool), \
        f"watch-hello.json schema_2.cursor_reset: {hello['cursor_reset']!r}"
    check_store_id("watch-hello.json schema_2.store_id", hello["store_id"])


def test_note_is_on_every_capture_and_names_the_am():
    for name in FIXTURE_NAMES:
        note = load(name).get("_note")
        assert isinstance(note, str), f"{name}: _note is {note!r}"
        assert NOTE_AM in note, f"{name}: _note does not name {NOTE_AM}"
    assert NOTED_FIXTURES == FIXTURE_NAMES
    with_row = sorted(name for name in FIXTURE_NAMES if "_am_runs_row" in load(name))
    assert with_row == sorted(E2E_FIXTURES), with_row


def test_captures_share_one_store_id():
    seen = {"runs.json": load("runs.json")["data"]["store_id"],
            "watch-hello.json schema_2": load("watch-hello.json")["schema_2"]["store_id"]}
    seen.update((name, load(name)["data"]["store_id"]) for name in STATUS_FIXTURES)
    (first, store_id), *rest = seen.items()
    for name, other in rest:
        assert other == store_id, f"store_id {other!r} in {name}, {store_id!r} in {first}"


def am_json(env, *args):
    # A hung am fails the test (TimeoutExpired) instead of hanging the suite.
    proc = subprocess.run(["am", *args], env=env, capture_output=True, text=True, timeout=AM_TIMEOUT)
    return proc.returncode, proc.stdout, proc.stderr


def scratch_env(tmp_path, path=None):
    """(env, repo_dir): os.environ with HOME, XDG_DATA_HOME and XDG_STATE_HOME under tmp_path
    and PATH replaced by `path` when given; tmp_path/home and repo_dir exist."""
    env = dict(os.environ)
    env.update({"HOME": str(tmp_path / "home"), "XDG_DATA_HOME": str(tmp_path / "data"),
                "XDG_STATE_HOME": str(tmp_path / "state")})
    if path is not None:
        env["PATH"] = path
    (tmp_path / "home").mkdir(exist_ok=True)
    repo_dir = tmp_path / "repo"
    repo_dir.mkdir(exist_ok=True)
    return env, repo_dir


def require_count(where, obj, key):
    """obj[key] is a non-negative int (a bool is not); a missing key means the plugin needs the newer am."""
    if key not in obj:
        pytest.fail(f"{where}: no {key}: the plugin needs the newer am")
    value = obj[key]
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        pytest.fail(f"{where}.{key}: {value!r}")


def watch_hello(env):
    """The first line `am watch --all --follow` prints with `env`, as an object; am is
    terminated afterwards. A silent or hung am fails within FOLLOW_TIMEOUT."""
    with subprocess.Popen(["am", "watch", "--all", "--follow"], env=env,
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True) as proc:
        try:
            try:
                (hello,) = read_lines(proc.stdout, 1, FOLLOW_TIMEOUT)
            except json.JSONDecodeError as err:
                pytest.fail(f"live am watch hello: not JSON: {err}")
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
    if not isinstance(hello, dict):
        pytest.fail(f"live am watch hello: expected an object, got {hello!r}")
    return hello


def live_check(env, repo_dir):
    """am run with `env` prints am runs data carrying as_of_seq and an am watch hello carrying
    head; rows present match the capture key sets exactly, and so does am status of the
    newest row."""
    code, out, err = am_json(env, "runs", "--repo-dir", str(repo_dir))
    if code != 0:
        pytest.fail(f"live am runs exited {code}: {out}{err}")
    try:
        data = json.loads(out).get("data")
    except (json.JSONDecodeError, AttributeError):
        data = None
    if not isinstance(data, dict):
        pytest.fail(f"live am runs: no data object in {out!r}")
    require_count("live am runs data", data, "as_of_seq")
    rows = data.get("runs") or []
    check_runs_rows("live am runs", rows)
    if rows:
        newest = max(rows, key=lambda row: row["started_at"])
        code, out, err = am_json(env, "status", newest["id"], "--repo-dir", str(repo_dir))
        assert code == 0, f"am status {newest['id']} exited {code}: {out}{err}"
        check_status_data(f"live am status {newest['id']}", json.loads(out)["data"])
    hello = watch_hello(env)
    if hello.get("event") != "watch":
        pytest.fail(f"live am watch hello: event {hello.get('event')!r}")
    require_count("live am watch hello", hello, "head")


def test_installed_am_prints_the_fixture_key_sets(tmp_path):
    if shutil.which("am") is None:
        pytest.skip("am is not installed here")
    live_check(*scratch_env(tmp_path))


def test_live_rows_and_status_must_match_the_capture_key_sets_exactly():
    # synthetic: a capture row with project dropped, then with an unknown key added
    row = load("runs.json")["data"]["runs"][0]
    del row["project"]
    with pytest.raises(pytest.fail.Exception) as failure:
        check_runs_rows("live am runs", [row])
    assert str(failure.value) == "live am runs runs[0]: missing ['project'], extra []"
    row = load("runs.json")["data"]["runs"][0]
    row["future_key"] = 1
    with pytest.raises(pytest.fail.Exception) as failure:
        check_runs_rows("live am runs", [row])
    assert str(failure.value) == "live am runs runs[0]: missing [], extra ['future_key']"
    # synthetic: capture status data with story_id dropped from the run, then warnings dropped
    data = load("status-done.json")["data"]
    del data["run"]["story_id"]
    with pytest.raises(pytest.fail.Exception) as failure:
        check_status_data("live", data)
    assert str(failure.value) == "live data.run: missing ['story_id'], extra []"
    data = load("status-done.json")["data"]
    del data["warnings"]
    with pytest.raises(pytest.fail.Exception) as failure:
        check_status_data("live", data)
    assert str(failure.value) == "live data: missing ['warnings'], extra []"


def test_live_status_check_rejects_a_status_outside_the_vocabularies():
    data = load("status-done.json")["data"]
    check_status_data("live", data)
    data["stories"][0]["subtasks"][0]["phases"][1]["attempts"][0]["status"] = "done"
    attempt = r"stories\[0\]\.subtasks\[0\]\.phases\[1\]\.attempts\[0\]\.status"
    with pytest.raises(AssertionError, match=rf"^live {attempt}: 'done'"):
        check_status_data("live", data)
    data["run"]["status"] = "bogus"
    with pytest.raises(AssertionError, match=r"^live data\.run\.status: 'bogus'"):
        check_status_data("live", data)


def test_live_check_skips_when_am_is_not_on_path(monkeypatch, tmp_path):
    monkeypatch.setenv("PATH", str(tmp_path))
    with pytest.raises(pytest.skip.Exception, match="am is not installed here"):
        test_installed_am_prints_the_fixture_key_sets(tmp_path)


def stub_runs_data(**extra):
    """runs.json's data with no rows, no as_of_seq and no store_id (an older am's), updated
    with `extra`."""
    data = load("runs.json")["data"]
    data.pop("as_of_seq", None)
    data.pop("store_id", None)
    data["runs"] = []
    data.update(extra)
    return data


def stub_hello(**extra):
    """watch-hello.json's schema_2 hello without "_" keys and without head, cursor_reset and
    store_id (an older am's), updated with `extra`."""
    hello = {key: value for key, value in load("watch-hello.json")["schema_2"].items()
             if not key.startswith("_")}
    for key in ("head", "cursor_reset", "store_id"):
        hello.pop(key, None)
    hello.update(extra)
    return hello


def test_stubs_model_an_older_am():
    assert not {"as_of_seq", "store_id"} & set(stub_runs_data())
    assert not {"head", "cursor_reset", "store_id"} & set(stub_hello())
    assert stub_hello()["schema"] == 2


def stub_am(tmp_path, runs_data, hello_line, runs_exit=0):
    """(env, repo_dir) of scratch_env with an executable am first on PATH.

    The stub am: `am runs` prints {"ok": true, "data": runs_data} and exits runs_exit;
    `am watch` prints hello_line and then execs `sleep 30`. Every call writes
    $XDG_DATA_HOME to tmp_path/seen-xdg and appends its first argument to tmp_path/calls.
    """
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    runs_out = tmp_path / "runs-out.json"
    with open(runs_out, "w", encoding="utf-8") as fh:
        json.dump({"ok": True, "data": runs_data}, fh)
    hello_out = tmp_path / "hello-out.json"
    hello_out.write_text(hello_line + "\n", encoding="utf-8")
    seen, calls = shlex.quote(str(tmp_path / "seen-xdg")), shlex.quote(str(tmp_path / "calls"))
    script = (
        "#!/bin/sh\n"
        f'printf "%s\\n" "$XDG_DATA_HOME" > {seen}\n'
        f'printf "%s\\n" "$1" >> {calls}\n'
        'case "$1" in\n'
        f"  runs) cat {shlex.quote(str(runs_out))}; exit {runs_exit} ;;\n"
        f"  watch) cat {shlex.quote(str(hello_out))}; exec sleep 30 ;;\n"
        "esac\n"
        "exit 2\n"
    )
    am = bin_dir / "am"
    am.write_text(script, encoding="utf-8")
    am.chmod(0o755)
    return scratch_env(tmp_path, path=f"{bin_dir}{os.pathsep}{os.environ.get('PATH', '')}")


def test_live_check_fails_naming_as_of_seq_when_am_runs_lacks_it(tmp_path):
    env, repo_dir = stub_am(tmp_path, stub_runs_data(), json.dumps(stub_hello(head=0)))
    with pytest.raises(pytest.fail.Exception) as failure:
        live_check(env, repo_dir)
    assert str(failure.value) == "live am runs data: no as_of_seq: the plugin needs the newer am"
    assert (tmp_path / "calls").read_text(encoding="utf-8").splitlines() == ["runs"]


def test_live_check_fails_on_a_null_as_of_seq(tmp_path):
    # synthetic: as_of_seq added as null
    env, repo_dir = stub_am(tmp_path, stub_runs_data(as_of_seq=None), json.dumps(stub_hello(head=0)))
    with pytest.raises(pytest.fail.Exception) as failure:
        live_check(env, repo_dir)
    assert str(failure.value) == "live am runs data.as_of_seq: None"


def test_live_check_runs_am_under_the_scratch_data_dir(monkeypatch, tmp_path):
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "caller-data"))
    real_data_home = os.path.expanduser("~/.local/share")
    # synthetic: as_of_seq added; synthetic: head added
    env, repo_dir = stub_am(tmp_path, stub_runs_data(as_of_seq=0), json.dumps(stub_hello(head=0)))
    live_check(env, repo_dir)
    seen = (tmp_path / "seen-xdg").read_text(encoding="utf-8").strip()
    assert seen == str(tmp_path / "data"), seen
    assert seen not in (str(tmp_path / "caller-data"), real_data_home), seen


def test_live_check_fails_when_am_runs_exits_non_zero(tmp_path):
    # synthetic: as_of_seq added; synthetic: head added
    env, repo_dir = stub_am(tmp_path, stub_runs_data(as_of_seq=0), json.dumps(stub_hello(head=0)),
                            runs_exit=3)
    with pytest.raises(pytest.fail.Exception, match=r"^live am runs exited 3: "):
        live_check(env, repo_dir)


def test_live_check_fails_naming_head_when_the_watch_hello_lacks_it(tmp_path):
    # synthetic: as_of_seq added
    env, repo_dir = stub_am(tmp_path, stub_runs_data(as_of_seq=0), json.dumps(stub_hello()))
    started = time.monotonic()
    with pytest.raises(pytest.fail.Exception) as failure:
        live_check(env, repo_dir)
    assert str(failure.value) == "live am watch hello: no head: the plugin needs the newer am"
    # The stub sleeps 30 s after the hello: returning sooner means it was terminated.
    assert time.monotonic() - started < 20
    assert (tmp_path / "calls").read_text(encoding="utf-8").splitlines() == ["runs", "watch"]


def test_live_check_passes_when_am_has_as_of_seq_and_head(tmp_path):
    # synthetic: as_of_seq added; synthetic: head added
    env, repo_dir = stub_am(tmp_path, stub_runs_data(as_of_seq=0), json.dumps(stub_hello(head=0)))
    live_check(env, repo_dir)
    assert (tmp_path / "calls").read_text(encoding="utf-8").splitlines() == ["runs", "watch"]


def test_live_check_rejects_a_bool_head(tmp_path):
    # synthetic: as_of_seq added; synthetic: head added as a bool
    env, repo_dir = stub_am(tmp_path, stub_runs_data(as_of_seq=0), json.dumps(stub_hello(head=True)))
    with pytest.raises(pytest.fail.Exception) as failure:
        live_check(env, repo_dir)
    assert str(failure.value) == "live am watch hello.head: True"


def test_live_check_fails_naming_the_hello_when_it_is_not_json(tmp_path):
    # synthetic: as_of_seq added; synthetic: a first watch line that is not JSON
    env, repo_dir = stub_am(tmp_path, stub_runs_data(as_of_seq=0), "synthetic: not json")
    with pytest.raises(pytest.fail.Exception, match=r"^live am watch hello: not JSON"):
        live_check(env, repo_dir)


def test_live_check_fails_when_the_first_watch_line_is_not_the_hello(tmp_path):
    # synthetic: as_of_seq added; synthetic: head added, event changed
    hello = stub_hello(head=0, event="run_upsert")
    env, repo_dir = stub_am(tmp_path, stub_runs_data(as_of_seq=0), json.dumps(hello))
    with pytest.raises(pytest.fail.Exception) as failure:
        live_check(env, repo_dir)
    assert str(failure.value) == "live am watch hello: event 'run_upsert'"


def test_live_check_accepts_a_schema_1_hello_with_head_and_unknown_keys(tmp_path):
    # synthetic: as_of_seq and an unknown key added; synthetic: head and an unknown key added, schema 1
    runs_data = stub_runs_data(as_of_seq=7, future_key=1)
    hello = stub_hello(head=7, schema=1, future_key=1)
    env, repo_dir = stub_am(tmp_path, runs_data, json.dumps(hello))
    live_check(env, repo_dir)
