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
DEFAULTS = {"verify": [], "allowNoVerification": False, "notifyOnEscalation": False,
            "prefixHistory": [], "parallelism": 4, "confirmDispatch": True, "prefixByMilestone": {}}


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
    ({"prefixHistory": "m3", "confirmDispatch": False}, {**DEFAULTS, "confirmDispatch": False}),
    ({"prefixHistory": ["m3", 5], "confirmDispatch": False}, {**DEFAULTS, "confirmDispatch": False}),
    ({"prefixHistory": ["m3", ""], "confirmDispatch": False}, {**DEFAULTS, "confirmDispatch": False}),
    ({"prefixHistory": ["  "], "confirmDispatch": False}, {**DEFAULTS, "confirmDispatch": False}),
    ({"prefixHistory": None, "confirmDispatch": False}, {**DEFAULTS, "confirmDispatch": False}),
    ({"prefixHistory": ["m%d" % i for i in range(21)], "confirmDispatch": False},
     {**DEFAULTS, "confirmDispatch": False}),
    ({"parallelism": 0, "prefixHistory": ["m3"]}, {**DEFAULTS, "prefixHistory": ["m3"]}),
    ({"parallelism": -2, "prefixHistory": ["m3"]}, {**DEFAULTS, "prefixHistory": ["m3"]}),
    ({"parallelism": 1.5, "prefixHistory": ["m3"]}, {**DEFAULTS, "prefixHistory": ["m3"]}),
    ({"parallelism": 2.0, "prefixHistory": ["m3"]}, {**DEFAULTS, "prefixHistory": ["m3"]}),
    ({"parallelism": "4", "prefixHistory": ["m3"]}, {**DEFAULTS, "prefixHistory": ["m3"]}),
    ({"parallelism": True, "prefixHistory": ["m3"]}, {**DEFAULTS, "prefixHistory": ["m3"]}),
    ({"parallelism": None, "prefixHistory": ["m3"]}, {**DEFAULTS, "prefixHistory": ["m3"]}),
    ({"parallelism": [4], "prefixHistory": ["m3"]}, {**DEFAULTS, "prefixHistory": ["m3"]}),
    ({"confirmDispatch": 0, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"confirmDispatch": 1, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"confirmDispatch": "false", "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"confirmDispatch": None, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"verify": "x", "parallelism": 8, "confirmDispatch": False},
     {**DEFAULTS, "parallelism": 8, "confirmDispatch": False}),
    ({"prefixByMilestone": [], "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": "m", "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": None, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": {"": "p"}, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": {"  ": "p"}, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": {"m1": ""}, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": {"m1": "  "}, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": {"m1": 5}, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": {"m1": None}, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": {"m1": ["p"]}, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": {"m1": "p", "m2": ""}, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": {"m1": "p"}, "parallelism": 0},
     {**DEFAULTS, "prefixByMilestone": {"m1": "p"}}),
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
        0, {**DEFAULTS, "verify": ["make check"], "allowNoVerification": True, "notifyOnEscalation": False})


def test_get_run_settings_dispatch_defaults(env):
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0
    # JSON text, so a 1 cannot pass for true nor 4.0 for 4.
    assert json.dumps([result["prefixHistory"], result["parallelism"], result["confirmDispatch"]]) == '[[], 4, true]'


def test_get_run_settings_reads_a_2_2_entry(env):
    write_state(env, {"run_settings": {"/p": {"verify": ["a"], "allowNoVerification": True,
                                              "notifyOnEscalation": True}}})
    code, result = run(env, "get-run-settings", "/p")
    expected = {"verify": ["a"], "allowNoVerification": True, "notifyOnEscalation": True,
                "prefixHistory": [], "parallelism": 4, "confirmDispatch": True, "prefixByMilestone": {}}
    assert code == 0 and json.dumps(result, sort_keys=True) == json.dumps(expected, sort_keys=True)


def test_get_run_settings_accepts_a_history_of_exactly_twenty(env):
    twenty = ["m%d" % i for i in range(20)]
    write_state(env, {"run_settings": {"/p": {"prefixHistory": twenty}}})
    assert run(env, "get-run-settings", "/p") == (0, {**DEFAULTS, "prefixHistory": twenty})


def test_get_run_settings_with_every_field_damaged_is_defaults(env):
    write_state(env, {"run_settings": {"/p": {
        "verify": 1, "allowNoVerification": "x", "notifyOnEscalation": None,
        "prefixHistory": [None], "parallelism": True, "confirmDispatch": 0, "prefixByMilestone": {"m1": 5}}}})
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and json.dumps(result, sort_keys=True) == json.dumps(DEFAULTS, sort_keys=True)


def reject_token(token):
    raise ValueError("not strict JSON: %s" % token)


# A stored NaN, Infinity or float must not reach QML's JSON.parse: the output is
# parsed here with every non-standard constant and every float refused.
@pytest.mark.parametrize("stored", ["NaN", "Infinity", "-Infinity", "1e400", "2.0"])
def test_get_run_settings_output_is_strict_json(env, stored):
    write_state(env, '{"run_settings": {"/p": {"parallelism": %s}}}' % stored)
    proc = subprocess.run([sys.executable, SCRIPT, "get-run-settings", "/p"], env=env, capture_output=True, text=True)
    assert proc.returncode == 0
    result = json.loads(proc.stdout, parse_constant=reject_token, parse_float=reject_token)
    assert result == DEFAULTS


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
    assert run(env, "get-run-settings", "/p") == (0, {**DEFAULTS, **settings})


def test_set_run_settings_is_partial(env):
    assert run(env, "set-run-settings", "/p", '{"verify": ["a"]}') == (0, {"ok": True})
    assert run(env, "set-run-settings", "/p", '{"notifyOnEscalation": true}') == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p") == (
        0, {**DEFAULTS, "verify": ["a"], "allowNoVerification": False, "notifyOnEscalation": True})
    assert run(env, "set-run-settings", "/p", '{"verify": []}') == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p") == (
        0, {**DEFAULTS, "verify": [], "allowNoVerification": False, "notifyOnEscalation": True})


def test_set_run_settings_empty_object_is_accepted(env):
    assert run(env, "set-run-settings", "/p", "{}") == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p") == (0, DEFAULTS)
    assert json.loads(state_file(env).read_text())["run_settings"]["/p"] == {}


def test_run_settings_are_per_root(env):
    assert run(env, "set-run-settings", "/a", '{"verify": ["make a"], "notifyOnEscalation": true}')[0] == 0
    assert run(env, "set-run-settings", "/home/u/my proj", '{"verify": ["make b"], "allowNoVerification": true}')[0] == 0
    assert run(env, "get-run-settings", "/a") == (
        0, {**DEFAULTS, "verify": ["make a"], "allowNoVerification": False, "notifyOnEscalation": True})
    assert run(env, "get-run-settings", "/home/u/my proj") == (
        0, {**DEFAULTS, "verify": ["make b"], "allowNoVerification": True, "notifyOnEscalation": False})
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
    assert run(env, "get-run-settings", "/p") == (0, {**DEFAULTS, **stored})
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
               '{"notifyOnEscalation": 1}', '{"notifyOnEscalation": null}', '{"verify": ["a"], "bogus": 1}',
               pytest.param("[" * 100000, id="nested-past-the-recursion-limit"),
               '{"prefixHistory": "m3"}', '{"prefixHistory": {"m3": 1}}', '{"prefixHistory": [1]}',
               '{"prefixHistory": [""]}', '{"prefixHistory": ["  "]}', '{"prefixHistory": null}',
               '{"prefixHistory": ["\\t\\n"]}',
               pytest.param(json.dumps({"prefixHistory": ["m%d" % i for i in range(21)]}), id="prefix-history-of-21"),
               '{"parallelism": 0}', '{"parallelism": -1}', '{"parallelism": -0}', '{"parallelism": 1.5}',
               '{"parallelism": 2.0}', '{"parallelism": 4e0}', '{"parallelism": 1e400}', '{"parallelism": "4"}',
               '{"parallelism": true}', '{"parallelism": null}', '{"parallelism": NaN}', '{"parallelism": Infinity}',
               '{"parallelism": -Infinity}', '{"parallelism": [4]}',
               '{"confirmDispatch": 1}', '{"confirmDispatch": 0}', '{"confirmDispatch": "true"}',
               '{"confirmDispatch": null}',
               '{"parallelism": 2, "confirmDispatch": "yes"}',
               '{"prefixByMilestone": []}', '{"prefixByMilestone": "m"}', '{"prefixByMilestone": null}',
               '{"prefixByMilestone": 5}', '{"prefixByMilestone": true}',
               '{"prefixByMilestone": {"": "p"}}', '{"prefixByMilestone": {"  ": "p"}}',
               '{"prefixByMilestone": {"m1": ""}}', '{"prefixByMilestone": {"m1": "  "}}',
               '{"prefixByMilestone": {"m1": "\\t\\n"}}', '{"prefixByMilestone": {"m1": 5}}',
               '{"prefixByMilestone": {"m1": null}}', '{"prefixByMilestone": {"m1": true}}',
               '{"prefixByMilestone": {"m1": ["p"]}}', '{"prefixByMilestone": {"m1": {"x": "p"}}}',
               '{"parallelism": 2, "prefixByMilestone": {"m1": ""}}']


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


# --- dispatch settings -------------------------------------------------------------

def same_json(actual, expected):
    """JSON text equality: 1 is not true, 2.0 is not 2."""
    return json.dumps(actual, sort_keys=True) == json.dumps(expected, sort_keys=True)


def test_set_then_get_dispatch_settings_round_trips(env):
    settings = {"prefixHistory": ["m3", "m2"], "parallelism": 2, "confirmDispatch": False}
    assert run(env, "set-run-settings", "/p", json.dumps(settings)) == (0, {"ok": True})
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and same_json(result, {**DEFAULTS, **settings})


def test_set_dispatch_settings_is_partial(env):
    expected = dict(DEFAULTS)
    for update in ({"verify": ["a"], "notifyOnEscalation": True}, {"parallelism": 6}, {"confirmDispatch": False},
                   {"prefixHistory": ["m3"]}, {"verify": ["b"]}):
        assert run(env, "set-run-settings", "/p", json.dumps(update)) == (0, {"ok": True})
        expected.update(update)
        code, result = run(env, "get-run-settings", "/p")
        assert code == 0 and same_json(result, expected), update
    assert expected["parallelism"] == 6 and expected["confirmDispatch"] is False
    assert expected["prefixHistory"] == ["m3"]


def test_set_prefix_history_replaces_the_list(env):
    assert run(env, "set-run-settings", "/p", '{"prefixHistory": ["m1", "m2", "m3"]}') == (0, {"ok": True})
    assert run(env, "set-run-settings", "/p", '{"prefixHistory": ["m4"]}') == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["prefixHistory"] == ["m4"]
    assert run(env, "set-run-settings", "/p", '{"prefixHistory": []}') == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["prefixHistory"] == []


def test_set_prefix_history_keeps_strings_verbatim(env):
    history = ["  m3  ", "feat/x", "caf\u00e9", "m3", "m3"]
    assert run(env, "set-run-settings", "/p", json.dumps({"prefixHistory": history}, ensure_ascii=False)) == (
        0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["prefixHistory"] == history


def test_set_prefix_history_of_exactly_twenty_is_accepted(env):
    twenty = ["m%d" % i for i in range(20)]
    assert run(env, "set-run-settings", "/p", json.dumps({"prefixHistory": twenty})) == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["prefixHistory"] == twenty
    before = state_file(env).read_bytes()
    assert run(env, "set-run-settings", "/p", json.dumps({"prefixHistory": twenty + ["m20"]})) == (
        2, {"ok": False, "error": "prefixHistory must be a list of at most 20 non-empty strings."})
    assert state_file(env).read_bytes() == before
    assert [p.name for p in state_file(env).parent.iterdir()] == ["state.json"]


@pytest.mark.parametrize("value", [1, 1000])
def test_set_parallelism_has_no_upper_bound(env, value):
    assert run(env, "set-run-settings", "/p", json.dumps({"parallelism": value})) == (0, {"ok": True})
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and json.dumps(result["parallelism"]) == str(value)


@pytest.mark.parametrize("update, error", [
    ('{"prefixHistory": "m3"}', "prefixHistory must be a list of at most 20 non-empty strings."),
    ('{"parallelism": 0}', "parallelism must be a whole number of at least 1."),
    ('{"confirmDispatch": 1}', "confirmDispatch must be true or false."),
    ('{"prefixByMilestone": []}',
     "prefixByMilestone must be an object of non-empty strings keyed by non-empty milestone ids."),
])
def test_dispatch_setting_errors_are_exact_sentences(env, update, error):
    assert run(env, "set-run-settings", "/p", update) == (2, {"ok": False, "error": error})


def test_first_bad_key_in_input_order_is_reported(env):
    assert run(env, "set-run-settings", "/p", '{"parallelism": 0, "confirmDispatch": 1}') == (
        2, {"ok": False, "error": "parallelism must be a whole number of at least 1."})
    assert run(env, "set-run-settings", "/p", '{"confirmDispatch": 1, "parallelism": 0}') == (
        2, {"ok": False, "error": "confirmDispatch must be true or false."})


def test_set_dispatch_settings_preserves_other_keys(env):
    write_state(env, {"last_project": "/p",
                      "run_settings": {"/q": {"parallelism": 3},
                                       "/p": {"verify": ["old"], "future": 1, "parallelism": "x"}}})
    assert run(env, "set-run-settings", "/p", '{"confirmDispatch": false}') == (0, {"ok": True})
    assert json.loads(state_file(env).read_text()) == {
        "last_project": "/p",
        "run_settings": {"/q": {"parallelism": 3},
                         "/p": {"verify": ["old"], "future": 1, "parallelism": "x", "confirmDispatch": False}}}
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and same_json(result, {**DEFAULTS, "verify": ["old"], "confirmDispatch": False})


def test_dispatch_settings_are_per_root(env):
    assert run(env, "set-run-settings", "/a",
               '{"parallelism": 2, "confirmDispatch": false, "prefixHistory": ["a1"]}') == (0, {"ok": True})
    code, result = run(env, "get-run-settings", "/a")
    assert code == 0 and same_json(result, {**DEFAULTS, "parallelism": 2, "confirmDispatch": False,
                                            "prefixHistory": ["a1"]})
    for root in ("/b", "/a/"):
        code, result = run(env, "get-run-settings", root)
        assert code == 0 and same_json(result, DEFAULTS), root


def test_set_project_preserves_dispatch_settings(env):
    stored = {"prefixHistory": ["m3", "m2"], "parallelism": 3, "confirmDispatch": False}
    assert run(env, "set-run-settings", "/p", json.dumps(stored)) == (0, {"ok": True})
    assert run(env, "set-project", "/other") == (0, {"ok": True})
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and same_json(result, {**DEFAULTS, **stored})
    assert run(env, "get") == (0, {"last_project": "/other"})


def test_set_parallelism_huge_values(env):
    # Python refuses to parse an integer of more than 4300 digits: a clean refusal, no traceback.
    assert run(env, "set-run-settings", "/p", '{"parallelism": 1%s}' % ("0" * 5000)) == (
        2, {"ok": False, "error": "The run settings are not valid JSON."})
    assert not Path(env["XDG_STATE_HOME"]).exists()
    assert run(env, "set-run-settings", "/p", json.dumps({"parallelism": 10 ** 30})) == (0, {"ok": True})
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and json.dumps(result["parallelism"]) == str(10 ** 30)


# --- prefix by milestone -----------------------------------------------------------

BY_MILESTONE_REFUSAL = "prefixByMilestone must be an object of non-empty strings keyed by non-empty milestone ids."


def set_by_milestone(env, root, by_milestone):
    return run(env, "set-run-settings", root, json.dumps({"prefixByMilestone": by_milestone}, ensure_ascii=False))


def test_get_prefix_by_milestone_default_is_empty_object(env):
    code, result = run(env, "get-run-settings", "/p")
    # JSON text: {} must not read as [] or null.
    assert code == 0 and len(result) == 7 and json.dumps(result["prefixByMilestone"]) == "{}"


def test_set_then_get_prefix_by_milestone_round_trips(env):
    by_milestone = {"m1": "feat/m1", "8a3c0f12": "m2-"}
    assert set_by_milestone(env, "/p", by_milestone) == (0, {"ok": True})
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and same_json(result, {**DEFAULTS, "prefixByMilestone": by_milestone})


def test_set_prefix_by_milestone_keeps_strings_verbatim(env):
    by_milestone = {"  m1  ": "  feat/x  ", "café": "日本/", "a/b": "m3"}
    assert set_by_milestone(env, "/p", by_milestone) == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["prefixByMilestone"] == by_milestone


def test_prefix_by_milestone_has_no_size_cap(env):
    by_milestone = {"m%d" % i: "p%d" % i for i in range(50)}
    assert set_by_milestone(env, "/p", by_milestone) == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["prefixByMilestone"] == by_milestone


def test_prefix_by_milestone_duplicate_id_last_wins(env):
    assert run(env, "set-run-settings", "/p", '{"prefixByMilestone": {"m1": "a", "m1": "b"}}') == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["prefixByMilestone"] == {"m1": "b"}


def test_other_settings_keep_the_stored_map(env):
    assert set_by_milestone(env, "/p", {"m1": "a"}) == (0, {"ok": True})
    for update in ({"parallelism": 3}, {"prefixHistory": ["m9"]}):
        assert run(env, "set-run-settings", "/p", json.dumps(update)) == (0, {"ok": True})
        assert run(env, "get-run-settings", "/p")[1]["prefixByMilestone"] == {"m1": "a"}, update
    assert json.loads(state_file(env).read_text())["run_settings"]["/p"] == {
        "prefixByMilestone": {"m1": "a"}, "parallelism": 3, "prefixHistory": ["m9"]}


@pytest.mark.parametrize("update", ['{"prefixByMilestone": []}', '{"prefixByMilestone": {"m2": ""}}',
                                    '{"prefixByMilestone": {"": "p"}}', '{"prefixByMilestone": {"m2": 5}}',
                                    '{"parallelism": 2, "prefixByMilestone": {"m2": "  "}}'])
def test_prefix_by_milestone_refusal_is_exact_and_writes_nothing(env, update):
    write_state(env, {"run_settings": {"/p": {"prefixByMilestone": {"m1": "a"}}}})
    before = state_file(env).read_bytes()
    assert run(env, "set-run-settings", "/p", update) == (2, {"ok": False, "error": BY_MILESTONE_REFUSAL})
    assert state_file(env).read_bytes() == before
    assert [p.name for p in state_file(env).parent.iterdir()] == ["state.json"]


def test_prefix_by_milestone_first_bad_key_in_input_order_is_reported(env):
    assert run(env, "set-run-settings", "/p", '{"prefixByMilestone": [], "parallelism": 0}') == (
        2, {"ok": False, "error": BY_MILESTONE_REFUSAL})
    assert run(env, "set-run-settings", "/p", '{"parallelism": 0, "prefixByMilestone": []}') == (
        2, {"ok": False, "error": "parallelism must be a whole number of at least 1."})
    assert not Path(env["XDG_STATE_HOME"]).exists()


def test_prefix_by_milestone_is_per_root(env):
    assert set_by_milestone(env, "/a", {"m1": "a-"}) == (0, {"ok": True})
    assert run(env, "get-run-settings", "/a")[1]["prefixByMilestone"] == {"m1": "a-"}
    for root in ("/b", "/a/"):
        code, result = run(env, "get-run-settings", root)
        assert code == 0 and same_json(result, DEFAULTS), root


def test_set_project_preserves_prefix_by_milestone(env):
    assert set_by_milestone(env, "/p", {"m1": "a", "m2": "b"}) == (0, {"ok": True})
    assert run(env, "set-project", "/other") == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["prefixByMilestone"] == {"m1": "a", "m2": "b"}
    assert run(env, "get") == (0, {"last_project": "/other"})


def test_set_prefix_by_milestone_merges_per_milestone(env):
    def set_and_get(by_milestone):
        assert set_by_milestone(env, "/p", by_milestone) == (0, {"ok": True})
        return run(env, "get-run-settings", "/p")[1]["prefixByMilestone"]
    assert set_and_get({"m1": "a"}) == {"m1": "a"}
    assert set_and_get({"m2": "b"}) == {"m1": "a", "m2": "b"}
    assert set_and_get({"m1": "c"}) == {"m1": "c", "m2": "b"}
    assert set_and_get({}) == {"m1": "c", "m2": "b"}


def test_set_prefix_by_milestone_padded_ids_are_distinct(env):
    assert set_by_milestone(env, "/p", {"m1": "a"}) == (0, {"ok": True})
    assert set_by_milestone(env, "/p", {" m1": "b"}) == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["prefixByMilestone"] == {"m1": "a", " m1": "b"}


# A damaged stored map is replaced, not merged into: merging would leave a bad
# entry behind and the whole field would read {}.
@pytest.mark.parametrize("stored", [{"m1": "p", "m2": 5}, "x", [], {"": "p"}, None])
def test_set_prefix_by_milestone_replaces_a_damaged_stored_map(env, stored):
    write_state(env, {"run_settings": {"/p": {"verify": ["a"], "prefixByMilestone": stored}}})
    assert set_by_milestone(env, "/p", {"m3": "q"}) == (0, {"ok": True})
    assert json.loads(state_file(env).read_text())["run_settings"]["/p"] == {
        "verify": ["a"], "prefixByMilestone": {"m3": "q"}}
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and same_json(result, {**DEFAULTS, "verify": ["a"], "prefixByMilestone": {"m3": "q"}})


def test_set_empty_prefix_by_milestone_on_a_fresh_root(env):
    assert set_by_milestone(env, "/p", {}) == (0, {"ok": True})
    assert json.loads(state_file(env).read_text()) == {"run_settings": {"/p": {"prefixByMilestone": {}}}}
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and same_json(result, DEFAULTS)


def test_set_prefix_by_milestone_preserves_other_keys(env):
    write_state(env, {"last_project": "/p", "other": {"x": 1},
                      "run_settings": {"/q": {"prefixByMilestone": {"m1": "q-"}},
                                       "/p": {"verify": ["old"], "future": 1, "parallelism": "x",
                                              "prefixByMilestone": {"m1": "a"}}}})
    assert set_by_milestone(env, "/p", {"m2": "b"}) == (0, {"ok": True})
    assert json.loads(state_file(env).read_text()) == {
        "last_project": "/p", "other": {"x": 1},
        "run_settings": {"/q": {"prefixByMilestone": {"m1": "q-"}},
                         "/p": {"verify": ["old"], "future": 1, "parallelism": "x",
                                "prefixByMilestone": {"m1": "a", "m2": "b"}}}}
    assert [p.name for p in state_file(env).parent.iterdir()] == ["state.json"]


def test_set_prefix_by_milestone_merges_into_the_legacy_map(env):
    old = Path(env["XDG_STATE_HOME"]) / "brd-viewer" / "state.json"
    old.parent.mkdir(parents=True)
    old.write_text('{"run_settings": {"/p": {"prefixByMilestone": {"m1": "a"}}}}')
    assert set_by_milestone(env, "/p", {"m2": "b"}) == (0, {"ok": True})
    assert json.loads(state_file(env).read_text()) == {
        "run_settings": {"/p": {"prefixByMilestone": {"m1": "a", "m2": "b"}}}}
    assert old.read_text() == '{"run_settings": {"/p": {"prefixByMilestone": {"m1": "a"}}}}'
