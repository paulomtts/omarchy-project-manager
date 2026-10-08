#!/usr/bin/env python3
"""Remembers which brd project the panel was last showing, each project's run
settings, and the viewer-wide global settings.

    viewer-state.py get
    viewer-state.py set-project <root_path>
    viewer-state.py get-run-settings <root_path>
    viewer-state.py set-run-settings <root_path> <json>
    viewer-state.py get-global-settings
    viewer-state.py set-global-settings <json>

State lives in ${XDG_STATE_HOME:-~/.local/state}/omarchy-project-manager/state.json
(reads fall back to the old brd-viewer/state.json until a new one is written). QML
cannot write files, hence this helper. Prints one JSON line. `get`,
`get-run-settings` and `get-global-settings` never fail (a missing or corrupt file,
or a damaged value, just means the default); `set-project`, `set-run-settings` and
`set-global-settings` write atomically and keep any other keys already in the file.
Run settings live under "run_settings", keyed by the root path verbatim. There are
seven, each read on its own:
verify (a list of non-empty strings, default []), allowNoVerification and
notifyOnEscalation (booleans, default false), prefixHistory (a list of at most 20
non-empty strings, most recent first, default []), parallelism (a whole number
>= 1, default 4), confirmDispatch (a boolean, default true) and prefixByMilestone
(an object mapping each milestone id to a non-empty prefix string, default {}).
`set-run-settings` takes a JSON object with any of them, validates every key
before writing anything, and changes only the keys given; a list given replaces
the stored list wholesale, and a prefixByMilestone given is merged into the
stored map per milestone id (a stored map that is not valid is replaced).
Global settings live under "global_settings". There is one, notifyOnEscalation,
a boolean; when no boolean is stored, `get-global-settings` answers true when any
project's stored run-settings notifyOnEscalation is true, else false.
`set-global-settings` takes a JSON object, validates every key before writing
anything, and changes only the keys given, keeping any other keys under
"global_settings".
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.atomic_write import write_atomic  # noqa: E402
from common.json_line import emit  # noqa: E402



USAGE = ("usage: viewer-state.py get | set-project <root_path> | get-run-settings <root_path>"
         " | set-run-settings <root_path> <json> | get-global-settings | set-global-settings <json>")
PREFIX_HISTORY_CAP = 20
RUN_SETTINGS_DEFAULTS = {"verify": [], "allowNoVerification": False, "notifyOnEscalation": False,
                         "prefixHistory": [], "parallelism": 4, "confirmDispatch": True,
                         "prefixByMilestone": {}}


def state_base():
    return os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")


def state_path():
    return os.path.join(state_base(), "omarchy-project-manager", "state.json")


def legacy_state_path():
    return os.path.join(state_base(), "brd-viewer", "state.json")


def load():
    for path in (state_path(), legacy_state_path()):
        if not os.path.exists(path):
            continue
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, ValueError, RecursionError):
            return {}
        return data if isinstance(data, dict) else {}
    return {}


def cmd_get():
    last = load().get("last_project")
    return emit({"last_project": last if isinstance(last, str) and last else None}, 0)


def valid_verify(value):
    return isinstance(value, list) and all(isinstance(v, str) and v.strip() for v in value)


def valid_prefix_history(value):
    return valid_verify(value) and len(value) <= PREFIX_HISTORY_CAP


def valid_parallelism(value):
    # type(), not isinstance(): True is an int, and 2.0, NaN and Infinity are floats.
    return type(value) is int and value >= 1


def valid_boolean(value):
    return isinstance(value, bool)


def valid_prefix_by_milestone(value):
    return isinstance(value, dict) and all(
        key.strip() and isinstance(prefix, str) and prefix.strip() for key, prefix in value.items())


RUN_SETTINGS_VALID = {"verify": valid_verify, "allowNoVerification": valid_boolean,
                      "notifyOnEscalation": valid_boolean, "prefixHistory": valid_prefix_history,
                      "parallelism": valid_parallelism, "confirmDispatch": valid_boolean,
                      "prefixByMilestone": valid_prefix_by_milestone}
RUN_SETTINGS_REFUSALS = {
    "verify": "verify must be a list of non-empty strings.",
    "allowNoVerification": "allowNoVerification must be true or false.",
    "notifyOnEscalation": "notifyOnEscalation must be true or false.",
    "prefixHistory": "prefixHistory must be a list of at most %d non-empty strings." % PREFIX_HISTORY_CAP,
    "parallelism": "parallelism must be a whole number of at least 1.",
    "confirmDispatch": "confirmDispatch must be true or false.",
    "prefixByMilestone": "prefixByMilestone must be an object of non-empty strings keyed by non-empty milestone ids.",
}
GLOBAL_SETTINGS_VALID = {"notifyOnEscalation": valid_boolean}
GLOBAL_SETTINGS_REFUSALS = {"notifyOnEscalation": RUN_SETTINGS_REFUSALS["notifyOnEscalation"]}


def run_settings_entry(data, root_path):
    settings = data.get("run_settings")
    entry = settings.get(root_path) if isinstance(settings, dict) else None
    return entry if isinstance(entry, dict) else {}


def cmd_get_run_settings(root_path):
    entry = run_settings_entry(load(), root_path)
    result = {}
    for key, default in RUN_SETTINGS_DEFAULTS.items():
        value = entry.get(key)
        result[key] = value if RUN_SETTINGS_VALID[key](value) else default
    return emit(result, 0)


def cmd_get_global_settings():
    data = load()
    stored = data.get("global_settings")
    value = stored.get("notifyOnEscalation") if isinstance(stored, dict) else None
    if not valid_boolean(value):
        settings = data.get("run_settings")
        entries = settings.values() if isinstance(settings, dict) else ()
        value = any(isinstance(entry, dict) and entry.get("notifyOnEscalation") is True for entry in entries)
    return emit({"notifyOnEscalation": value}, 0)


def parse_settings(text, noun, valid, refusals):
    """The update in `text` and None, or None and a sentence saying what is wrong.
    `noun` names one setting ("run setting"); `valid` and `refusals` map each allowed
    key to its check and to the sentence refusing a value that fails it."""
    try:
        update = json.loads(text)
    except (ValueError, RecursionError):
        return None, "The %ss are not valid JSON." % noun
    if not isinstance(update, dict):
        return None, "The %ss must be a JSON object." % noun
    for key, value in update.items():
        if key not in valid:
            return None, "Unknown %s: %s." % (noun, key)
        if not valid[key](value):
            return None, refusals[key]
    return update, None


def save(data):
    path = state_path()
    directory = os.path.dirname(path)
    try:
        os.makedirs(directory, exist_ok=True)
        write_atomic(path, json.dumps(data).encode("utf-8"), mode=0o600)
    except OSError as e:
        return emit({"ok": False, "error": str(e)}, 1)
    return emit({"ok": True}, 0)


def cmd_set_project(root_path):
    data = load()
    data["last_project"] = root_path
    return save(data)


def cmd_set_run_settings(root_path, text):
    update, error = parse_settings(text, "run setting", RUN_SETTINGS_VALID, RUN_SETTINGS_REFUSALS)
    if update is None:
        return emit({"ok": False, "error": error}, 2)
    data = load()
    settings = data.get("run_settings")
    if not isinstance(settings, dict):
        settings = data["run_settings"] = {}
    entry = settings.get(root_path)
    if not isinstance(entry, dict):
        entry = settings[root_path] = {}
    if "prefixByMilestone" in update:
        stored = entry.get("prefixByMilestone")
        merged = dict(stored) if valid_prefix_by_milestone(stored) else {}
        merged.update(update["prefixByMilestone"])
        update["prefixByMilestone"] = merged
    entry.update(update)
    return save(data)


def cmd_set_global_settings(text):
    update, error = parse_settings(text, "global setting", GLOBAL_SETTINGS_VALID, GLOBAL_SETTINGS_REFUSALS)
    if update is None:
        return emit({"ok": False, "error": error}, 2)
    data = load()
    settings = data.get("global_settings")
    if not isinstance(settings, dict):
        settings = data["global_settings"] = {}
    settings.update(update)
    return save(data)


def main(argv):
    if argv[:1] == ["get"] and len(argv) == 1:
        return cmd_get()
    if argv[:1] == ["set-project"] and len(argv) == 2 and argv[1]:
        return cmd_set_project(argv[1])
    if argv[:1] == ["get-run-settings"] and len(argv) == 2 and argv[1]:
        return cmd_get_run_settings(argv[1])
    if argv[:1] == ["set-run-settings"] and len(argv) == 3 and argv[1]:
        return cmd_set_run_settings(argv[1], argv[2])
    if argv == ["get-global-settings"]:
        return cmd_get_global_settings()
    if argv[:1] == ["set-global-settings"] and len(argv) == 2:
        return cmd_set_global_settings(argv[1])
    return emit({"ok": False, "error": USAGE}, 2)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
