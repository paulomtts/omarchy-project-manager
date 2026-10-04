#!/usr/bin/env python3
"""Remembers which brd project the panel was last showing, and each project's
run settings.

    viewer-state.py get
    viewer-state.py set-project <root_path>
    viewer-state.py get-run-settings <root_path>
    viewer-state.py set-run-settings <root_path> <json>

State lives in ${XDG_STATE_HOME:-~/.local/state}/omarchy-project-manager/state.json
(reads fall back to the old brd-viewer/state.json until a new one is written). QML
cannot write files, hence this helper. Prints one JSON line. `get` and
`get-run-settings` never fail (a missing or corrupt file, or a damaged value, just
means the default); `set-project` and `set-run-settings` write atomically and keep
any other keys already in the file. Run settings live under "run_settings", keyed
by the root path verbatim: `set-run-settings` takes a JSON object with any of
verify (a list of non-empty strings), allowNoVerification and notifyOnEscalation
(booleans), validates it before writing anything, and changes only the keys given.
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.atomic_write import write_atomic  # noqa: E402
from common.json_line import emit  # noqa: E402



USAGE = ("usage: viewer-state.py get | set-project <root_path> | get-run-settings <root_path>"
         " | set-run-settings <root_path> <json>")
RUN_SETTINGS_DEFAULTS = {"verify": [], "allowNoVerification": False, "notifyOnEscalation": False}


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
        except (OSError, ValueError):
            return {}
        return data if isinstance(data, dict) else {}
    return {}


def cmd_get():
    last = load().get("last_project")
    return emit({"last_project": last if isinstance(last, str) and last else None}, 0)


def valid_verify(value):
    return isinstance(value, list) and all(isinstance(v, str) and v.strip() for v in value)


def run_settings_entry(data, root_path):
    settings = data.get("run_settings")
    entry = settings.get(root_path) if isinstance(settings, dict) else None
    return entry if isinstance(entry, dict) else {}


def cmd_get_run_settings(root_path):
    entry = run_settings_entry(load(), root_path)
    verify = entry.get("verify")
    result = {"verify": verify if valid_verify(verify) else []}
    for key in ("allowNoVerification", "notifyOnEscalation"):
        value = entry.get(key)
        result[key] = value if isinstance(value, bool) else RUN_SETTINGS_DEFAULTS[key]
    return emit(result, 0)


def parse_run_settings(text):
    """The update in `text` and None, or None and a sentence saying what is wrong."""
    try:
        update = json.loads(text)
    except (ValueError, RecursionError):
        return None, "The run settings are not valid JSON."
    if not isinstance(update, dict):
        return None, "The run settings must be a JSON object."
    for key, value in update.items():
        if key not in RUN_SETTINGS_DEFAULTS:
            return None, "Unknown run setting: %s." % key
        if key == "verify" and not valid_verify(value):
            return None, "verify must be a list of non-empty strings."
        if key != "verify" and not isinstance(value, bool):
            return None, "%s must be true or false." % key
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
    update, error = parse_run_settings(text)
    if update is None:
        return emit({"ok": False, "error": error}, 2)
    data = load()
    settings = data.get("run_settings")
    if not isinstance(settings, dict):
        settings = data["run_settings"] = {}
    entry = settings.get(root_path)
    if not isinstance(entry, dict):
        entry = settings[root_path] = {}
    entry.update(update)
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
    return emit({"ok": False, "error": USAGE}, 2)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
