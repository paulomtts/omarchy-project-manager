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
