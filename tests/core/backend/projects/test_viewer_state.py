"""viewer-state.py in a throwaway XDG_STATE_HOME: the real state file is never touched."""
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "core", "backend", "projects", "viewer-state.py")


@pytest.fixture
def env(tmp_path):
    return {"HOME": str(tmp_path / "home"), "XDG_STATE_HOME": str(tmp_path / "state"),
            "PATH": os.environ.get("PATH", "")}


def state_file(env):
    return Path(env["XDG_STATE_HOME"]) / "omarchy-project-manager" / "state.json"


def run(env, *args):
    proc = subprocess.run([sys.executable, SCRIPT, *args], env=env, capture_output=True, text=True)
    out = proc.stdout.strip().splitlines()
    return proc.returncode, (json.loads(out[-1]) if out else None)


def test_get_with_no_file_is_null(env):
    assert run(env, "get") == (0, {"last_project": None})


@pytest.mark.parametrize("content", ["", "not json", "[1, 2]", '"text"', '{"last_project": 5}', '{"last_project": ""}'])
def test_get_treats_bad_content_as_null(env, content):
    state_file(env).parent.mkdir(parents=True)
    state_file(env).write_text(content)
    assert run(env, "get") == (0, {"last_project": None})


def test_set_then_get_round_trips(env):
    assert run(env, "set-project", "/home/u/my proj") == (0, {"ok": True})
    assert run(env, "get") == (0, {"last_project": "/home/u/my proj"})


def test_set_replaces_the_previous_project(env):
    run(env, "set-project", "/a")
    run(env, "set-project", "/b")
    assert run(env, "get")[1] == {"last_project": "/b"}


def test_set_preserves_other_keys(env):
    state_file(env).parent.mkdir(parents=True)
    state_file(env).write_text(json.dumps({"other": {"x": 1}, "last_project": "/old"}))
    run(env, "set-project", "/new")
    data = json.loads(state_file(env).read_text())
    assert data == {"other": {"x": 1}, "last_project": "/new"}


def test_set_leaves_no_temp_files_behind(env):
    run(env, "set-project", "/a")
    assert [p.name for p in state_file(env).parent.iterdir()] == ["state.json"]


def test_defaults_to_dot_local_state_under_home(env):
    del env["XDG_STATE_HOME"]
    run(env, "set-project", "/a")
    assert (Path(env["HOME"]) / ".local" / "state" / "omarchy-project-manager" / "state.json").is_file()


@pytest.mark.skipif(os.geteuid() == 0, reason="root ignores directory permissions")
def test_unwritable_directory_fails_cleanly(env):
    d = state_file(env).parent
    d.mkdir(parents=True)
    d.chmod(0o500)
    try:
        code, result = run(env, "set-project", "/a")
    finally:
        d.chmod(0o700)
    assert code == 1 and result["ok"] is False and result["error"]


@pytest.mark.parametrize("args", [(), ("set-project",), ("set-project", ""), ("bogus",)])
def test_bad_usage_is_rejected(env, args):
    code, result = run(env, *args)
    assert code == 2 and result["ok"] is False


def test_get_falls_back_to_the_state_left_by_the_old_brd_viewer_name(env):
    old = Path(env["XDG_STATE_HOME"]) / "brd-viewer" / "state.json"
    old.parent.mkdir(parents=True)
    old.write_text('{"last_project": "/home/u/old"}')
    assert run(env, "get") == (0, {"last_project": "/home/u/old"})
    assert run(env, "set-project", "/home/u/new")[0] == 0
    assert run(env, "get") == (0, {"last_project": "/home/u/new"})
    assert json.loads(old.read_text())["last_project"] == "/home/u/old"
    assert state_file(env).is_file()


def test_the_new_state_file_wins_over_the_old_one(env):
    old = Path(env["XDG_STATE_HOME"]) / "brd-viewer" / "state.json"
    old.parent.mkdir(parents=True)
    old.write_text('{"last_project": "/home/u/old"}')
    state_file(env).parent.mkdir(parents=True)
    state_file(env).write_text('{"last_project": "/home/u/new"}')
    assert run(env, "get") == (0, {"last_project": "/home/u/new"})


def test_a_newly_created_state_file_is_private(env):
    run(env, "set-project", "/home/u/proj")
    assert (state_file(env).stat().st_mode & 0o777) == 0o600


# --- run settings ----------------------------------------------------------------

USAGE = ("usage: viewer-state.py get | set-project <root_path> | get-run-settings <root_path>"
         " | set-run-settings <root_path> <json>")
DEFAULTS = {"verify": [], "allowNoVerification": False, "notifyOnEscalation": False}


def write_state(env, content):
    """Writes the state file: a str verbatim, anything else as JSON."""
    state_file(env).parent.mkdir(parents=True, exist_ok=True)
    state_file(env).write_text(content if isinstance(content, str) else json.dumps(content))


def test_get_run_settings_with_no_file_is_defaults(env):
    assert run(env, "get-run-settings", "/p") == (0, DEFAULTS)


def test_get_run_settings_writes_nothing(env):
    run(env, "get-run-settings", "/p")
    assert not Path(env["XDG_STATE_HOME"]).exists()


@pytest.mark.parametrize("content", ["", "not json", "[1]", '{"run_settings": 5}', '{"run_settings": {"/p": "x"}}',
                                     '{"run_settings": {"/other": {"notifyOnEscalation": true}}}'])
def test_get_run_settings_treats_bad_files_as_defaults(env, content):
    write_state(env, content)
    assert run(env, "get-run-settings", "/p") == (0, DEFAULTS)


# Compared as JSON text: in Python 1 == True and 0 == False, so a dict compare
# would not notice a stored 1 or 0 leaking through as a "boolean".
@pytest.mark.parametrize("entry, expected", [
    ({"verify": "pytest", "notifyOnEscalation": True}, {**DEFAULTS, "notifyOnEscalation": True}),
    ({"verify": ["a", 5], "notifyOnEscalation": True}, {**DEFAULTS, "notifyOnEscalation": True}),
    ({"verify": ["a", ""], "notifyOnEscalation": True}, {**DEFAULTS, "notifyOnEscalation": True}),
    ({"verify": ["  "], "notifyOnEscalation": True}, {**DEFAULTS, "notifyOnEscalation": True}),
    ({"verify": None, "notifyOnEscalation": True}, {**DEFAULTS, "notifyOnEscalation": True}),
    ({"allowNoVerification": 1, "verify": ["a"]}, {**DEFAULTS, "verify": ["a"]}),
    ({"allowNoVerification": "true", "verify": ["a"]}, {**DEFAULTS, "verify": ["a"]}),
    ({"allowNoVerification": None, "verify": ["a"]}, {**DEFAULTS, "verify": ["a"]}),
    ({"notifyOnEscalation": 0, "allowNoVerification": True}, {**DEFAULTS, "allowNoVerification": True}),
    ({"notifyOnEscalation": "yes", "allowNoVerification": True}, {**DEFAULTS, "allowNoVerification": True}),
])
def test_get_run_settings_coerces_each_bad_field_independently(env, entry, expected):
    write_state(env, {"run_settings": {"/p": entry}})
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and json.dumps(result, sort_keys=True) == json.dumps(expected, sort_keys=True)


def test_get_run_settings_returns_only_known_keys(env):
    write_state(env, {"run_settings": {"/p": {"verify": ["a"], "future": 1}}})
    assert run(env, "get-run-settings", "/p") == (0, {**DEFAULTS, "verify": ["a"]})


def test_get_run_settings_reads_the_legacy_file(env):
    old = Path(env["XDG_STATE_HOME"]) / "brd-viewer" / "state.json"
    old.parent.mkdir(parents=True)
    old.write_text(json.dumps({"run_settings": {"/p": {"verify": ["make check"], "allowNoVerification": True}}}))
    assert run(env, "get-run-settings", "/p") == (
        0, {"verify": ["make check"], "allowNoVerification": True, "notifyOnEscalation": False})


@pytest.mark.parametrize("args", [
    ("get-run-settings",), ("get-run-settings", ""), ("get-run-settings", "/p", "x"),
    ("set-run-settings",), ("set-run-settings", "/p"), ("set-run-settings", "", "{}"),
    ("set-run-settings", "/p", "{}", "x"),
])
def test_run_settings_bad_usage_is_rejected(env, args):
    assert run(env, *args) == (2, {"ok": False, "error": USAGE})
    assert not Path(env["XDG_STATE_HOME"]).exists()


def test_set_then_get_run_settings_round_trips(env):
    settings = {"verify": ["uv run pytest", "npm test -- --ci"], "allowNoVerification": True, "notifyOnEscalation": True}
    assert run(env, "set-run-settings", "/p", json.dumps(settings)) == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p") == (0, settings)


def test_set_run_settings_is_partial(env):
    assert run(env, "set-run-settings", "/p", '{"verify": ["a"]}') == (0, {"ok": True})
    assert run(env, "set-run-settings", "/p", '{"notifyOnEscalation": true}') == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p") == (
        0, {"verify": ["a"], "allowNoVerification": False, "notifyOnEscalation": True})
    assert run(env, "set-run-settings", "/p", '{"verify": []}') == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p") == (
        0, {"verify": [], "allowNoVerification": False, "notifyOnEscalation": True})


def test_set_run_settings_empty_object_is_accepted(env):
    assert run(env, "set-run-settings", "/p", "{}") == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p") == (0, DEFAULTS)
    assert json.loads(state_file(env).read_text())["run_settings"]["/p"] == {}


def test_run_settings_are_per_root(env):
    assert run(env, "set-run-settings", "/a", '{"verify": ["make a"], "notifyOnEscalation": true}')[0] == 0
    assert run(env, "set-run-settings", "/home/u/my proj", '{"verify": ["make b"], "allowNoVerification": true}')[0] == 0
    assert run(env, "get-run-settings", "/a") == (
        0, {"verify": ["make a"], "allowNoVerification": False, "notifyOnEscalation": True})
    assert run(env, "get-run-settings", "/home/u/my proj") == (
        0, {"verify": ["make b"], "allowNoVerification": True, "notifyOnEscalation": False})
    assert run(env, "get-run-settings", "/c") == (0, DEFAULTS)
    assert run(env, "get-run-settings", "/a/") == (0, DEFAULTS)


def test_set_run_settings_preserves_other_keys(env):
    write_state(env, {"last_project": "/p", "other": {"x": 1},
                      "run_settings": {"/q": {"verify": ["q"]}, "/p": {"verify": ["old"], "future": 1}}})
    assert run(env, "set-run-settings", "/p", '{"notifyOnEscalation": true}') == (0, {"ok": True})
    assert json.loads(state_file(env).read_text()) == {
        "last_project": "/p", "other": {"x": 1},
        "run_settings": {"/q": {"verify": ["q"]},
                         "/p": {"verify": ["old"], "future": 1, "notifyOnEscalation": True}}}


def test_set_project_preserves_run_settings(env):
    stored = {"verify": ["a"], "allowNoVerification": False, "notifyOnEscalation": True}
    assert run(env, "set-run-settings", "/p", json.dumps(stored)) == (0, {"ok": True})
    assert run(env, "set-project", "/p") == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p") == (0, stored)
    assert run(env, "get") == (0, {"last_project": "/p"})
    assert run(env, "set-run-settings", "/p", '{"allowNoVerification": true}') == (0, {"ok": True})
    assert run(env, "get") == (0, {"last_project": "/p"})


def test_set_run_settings_keeps_strings_verbatim(env):
    verify = ["  uv run pytest  ", "make a; make b", "echo $(x) && true", "make a; make b",
              "pytest -k 'caf\u00e9'", 'say "hi" \u65e5\u672c']
    assert run(env, "set-run-settings", "/p", json.dumps({"verify": verify}, ensure_ascii=False)) == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["verify"] == verify


BAD_UPDATES = ["", "{", "[]", '"x"', "null", "5", '{"allow_no_verification": true}', '{"verify": "pytest"}',
               '{"verify": [1]}', '{"verify": [""]}', '{"verify": ["  "]}', '{"allowNoVerification": "true"}',
               '{"notifyOnEscalation": 1}', '{"notifyOnEscalation": null}', '{"verify": ["a"], "bogus": 1}']


@pytest.mark.parametrize("update", BAD_UPDATES)
def test_set_run_settings_rejects_bad_json(env, update):
    code, result = run(env, "set-run-settings", "/p", update)
    assert code == 2 and result["ok"] is False and result["error"]
    assert not Path(env["XDG_STATE_HOME"]).exists()


@pytest.mark.parametrize("update", BAD_UPDATES)
def test_set_run_settings_rejection_leaves_the_file_untouched(env, update):
    write_state(env, {"last_project": "/p", "run_settings": {"/p": {"verify": ["a"]}}})
    before = state_file(env).read_bytes()
    code, result = run(env, "set-run-settings", "/p", update)
    assert code == 2 and result["ok"] is False and result["error"]
    assert state_file(env).read_bytes() == before
    assert [p.name for p in state_file(env).parent.iterdir()] == ["state.json"]


def test_unknown_key_error_names_the_key(env):
    code, result = run(env, "set-run-settings", "/p", '{"verfy": []}')
    assert code == 2 and "verfy" in result["error"]


def test_set_run_settings_leaves_no_temp_files_behind(env):
    run(env, "set-run-settings", "/p", '{"verify": ["a"]}')
    assert [p.name for p in state_file(env).parent.iterdir()] == ["state.json"]


def test_new_state_file_from_run_settings_is_private(env):
    run(env, "set-run-settings", "/p", "{}")
    assert (state_file(env).stat().st_mode & 0o777) == 0o600


@pytest.mark.skipif(os.geteuid() == 0, reason="root ignores directory permissions")
def test_set_run_settings_unwritable_directory_fails_cleanly(env):
    d = state_file(env).parent
    d.mkdir(parents=True)
    d.chmod(0o500)
    try:
        code, result = run(env, "set-run-settings", "/p", '{"verify": ["a"]}')
    finally:
        d.chmod(0o700)
    assert code == 1 and result["ok"] is False and result["error"]


def test_set_run_settings_carries_legacy_state_forward(env):
    old = Path(env["XDG_STATE_HOME"]) / "brd-viewer" / "state.json"
    old.parent.mkdir(parents=True)
    old.write_text('{"last_project": "/home/u/old"}')
    assert run(env, "set-run-settings", "/p", '{"verify": ["a"]}') == (0, {"ok": True})
    assert json.loads(state_file(env).read_text()) == {
        "last_project": "/home/u/old", "run_settings": {"/p": {"verify": ["a"]}}}
    assert old.read_text() == '{"last_project": "/home/u/old"}'


def test_set_run_settings_replaces_a_corrupt_file(env):
    write_state(env, "not json")
    assert run(env, "set-run-settings", "/p", '{"notifyOnEscalation": true}') == (0, {"ok": True})
    assert json.loads(state_file(env).read_text()) == {"run_settings": {"/p": {"notifyOnEscalation": True}}}


@pytest.mark.parametrize("stored", [5, "x", [], None, {"/p": "x"}, {"/p": ["a"]}, {"/p": None}])
def test_set_run_settings_repairs_a_damaged_settings_shape(env, stored):
    write_state(env, {"last_project": "/p", "run_settings": stored})
    assert run(env, "set-run-settings", "/p", '{"verify": ["a"]}') == (0, {"ok": True})
    data = json.loads(state_file(env).read_text())
    assert data["last_project"] == "/p" and data["run_settings"]["/p"] == {"verify": ["a"]}
    assert run(env, "get-run-settings", "/p") == (0, {**DEFAULTS, "verify": ["a"]})


def test_set_run_settings_keeps_damaged_stored_fields_it_was_not_given(env):
    write_state(env, {"run_settings": {"/p": {"verify": ["a", 5]}}})
    assert run(env, "set-run-settings", "/p", '{"notifyOnEscalation": true}') == (0, {"ok": True})
    assert json.loads(state_file(env).read_text())["run_settings"]["/p"] == {
        "verify": ["a", 5], "notifyOnEscalation": True}
    assert run(env, "get-run-settings", "/p") == (0, {**DEFAULTS, "notifyOnEscalation": True})


@pytest.mark.parametrize("root", ["-p", "--help", "/home/u/caf\u00e9"])
def test_run_settings_root_is_any_non_empty_string(env, root):
    assert run(env, "set-run-settings", root, '{"verify": ["a"]}') == (0, {"ok": True})
    assert run(env, "get-run-settings", root) == (0, {**DEFAULTS, "verify": ["a"]})
