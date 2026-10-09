"""No ui/ or tests/ui/ caller reaches a member RunStore no longer owns through `.runs.`.

Each moved member is read, written, called and connected on the store that owns it:
`runControl` (RunControlStore), `runAlerts` (RunAlertsStore) or `runDispatch` (RunDispatchStore).
"""
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
CALLER_DIRS = ["ui", "tests/ui"]

# member -> the App handle that owns it
MOVED = {
    "pending": "runControl",
    "stillWaiting": "runControl",
    "stillWaitingText": "runControl",
    "lastControlError": "runControl",
    "lastControlErrorRunId": "runControl",
    "cancelRunId": "runControl",
    "cancelOpen": "runControl",
    "cancelText": "runControl",
    "cancelError": "runControl",
    "flashText": "runControl",
    "controlRunners": "runControl",
    "pendingTimer": "runControl",
    "flashTimer": "runControl",
    "notifyOnEscalation": "runControl",
    "notifySaved": "runControl",
    "notifyTouched": "runControl",
    "settingsLoadRunner": "runControl",
    "settingsSaveRunner": "runControl",
    "control": "runControl",
    "refusalOf": "runControl",
    "flash": "runControl",
    "openCancel": "runControl",
    "closeCancel": "runControl",
    "confirmCancel": "runControl",
    "setNotifyOnEscalation": "runControl",
    "runSettings": "runControl (runSettingsOf / applyRunSettings with app.runs.project)",
    "runSettingsRunner": "runControl (runSettingsLoadRunner)",
    "armedRoots": "runAlerts",
    "alertsArmed": "runAlerts",
    "toasts": "runAlerts",
    "toastMs": "runAlerts",
    "toastTimer": "runAlerts",
    "notifyRunners": "runAlerts",
    "raiseAlerts": "runAlerts",
    "expireToasts": "runAlerts",
    "dismissToast": "runAlerts",
    "dismissAllToasts": "runAlerts",
    "notify": "runAlerts",
    "dispatchState": "runDispatch",
    "dispatchTarget": "runDispatch",
    "dispatchTargetLabel": "runDispatch",
    "dispatchForm": "runDispatch",
    "dispatchPreview": "runDispatch",
    "dispatchError": "runDispatch",
    "dispatchErrorType": "runDispatch",
    "dispatchErrors": "runDispatch",
    "dispatchSuggest": "runDispatch",
    "dispatchRunId": "runDispatch",
    "dispatchMessage": "runDispatch",
    "dispatchLog": "runDispatch",
    "dispatchLogTail": "runDispatch",
    "dispatchExitCode": "runDispatch",
    "dispatchDefaultsRunner": "runDispatch",
    "dispatchPreviewRunner": "runDispatch",
    "dispatchDebounceTimer": "runDispatch",
    "dispatchStartRunners": "runDispatch",
    "dispatchStarted": "runDispatch",
    "openDispatch": "runDispatch",
    "closeDispatch": "runDispatch",
    "retargetToMilestone": "runDispatch",
    "setDispatchField": "runDispatch",
    "dispatchStart": "runDispatch",
    "checkDispatch": "runDispatch",
}

# Callers still on the RunStore shims; each migrating task removes its own paths, the last removes the set.
UNMIGRATED = {
    "ui/Panel.qml",
    "ui/Navigator.qml",
    "ui/Shortcuts.qml",
    "ui/screens/RunsScreen.qml",
    "ui/screens/RunDetailScreen.qml",
    "ui/screens/CardDetailScreen.qml",
    "tests/ui/screens/tst_runs_screen.qml",
    "tests/ui/screens/tst_run_detail_screen.qml",
    "tests/ui/screens/tst_card_detail_screen.qml",
    "tests/ui/tst_navigator.qml",
    "tests/ui/tst_shortcuts.qml",
    "tests/ui/tst_runs_flow.qml",
    "tests/ui/tst_dispatch_flow.qml",
    "tests/ui/tst_board_flow.qml",
    "tests/ui/tst_runs_real_data.qml",
}

MOVED_RE = re.compile(r"\.runs\.(" + "|".join(sorted(MOVED, key=len, reverse=True)) + r")\b")
CONNECTIONS_RE = re.compile(r"\bConnections\s*\{")
TARGET_RE = re.compile(r"^\s*target:\s*([\w.]+)\s*$", re.M)
HANDLER_RE = re.compile(r"\bfunction\s+(on[A-Z]\w*)\s*\(|^\s*(on[A-Z]\w*)\s*:", re.M)
RUNS_TARGET_RE = re.compile(r"(?:^|\.)runs$")


def rel(path):
    return path.relative_to(ROOT).as_posix()


def caller_files(*dirs, suffixes=(".qml", ".js")):
    return sorted(p for top in dirs for p in (ROOT / top).rglob("*") if p.suffix in suffixes)


def caller_params():
    return [pytest.param(p, id=rel(p), marks=pytest.mark.xfail(strict=True, reason="still on the RunStore shims"))
            if rel(p) in UNMIGRATED else pytest.param(p, id=rel(p)) for p in caller_files(*CALLER_DIRS)]


def moved_hits(text):
    """(line number, member) for every moved member `text` reaches through `.runs.`, comments included."""
    return [(n, m.group(1)) for n, line in enumerate(text.splitlines(), 1) for m in MOVED_RE.finditer(line)]


def connections_blocks(text):
    """The text of every `Connections {` block, from its opening brace to the matching closing one."""
    blocks = []
    for m in CONNECTIONS_RE.finditer(text):
        start = m.end() - 1
        depth = 0
        for i in range(start, len(text)):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    blocks.append(text[start:i + 1])
                    break
    return blocks


def moved_handlers(block):
    """The handlers of a Connections block whose target ends in `.runs` that belong to a moved member."""
    target = TARGET_RE.search(block)
    if not target or not RUNS_TARGET_RE.search(target.group(1)):
        return []
    wanted = set()
    for name in MOVED:
        wanted |= {"on" + name[0].upper() + name[1:], "on" + name[0].upper() + name[1:] + "Changed"}
    return [h for h in (a or b for a, b in HANDLER_RE.findall(block)) if h in wanted]


def test_the_guard_helpers_flag_and_accept_what_they_should():
    assert moved_hits("x: app.runs.cancelOpen\ny: appStores.runs.flash(t) // app.runs.toasts") == \
        [(1, "cancelOpen"), (2, "flash"), (2, "toasts")]
    assert moved_hits("app.runControl.cancelOpen; app.runs.runById(id); s.runs.controlCalls; "
                      "app.runs.amStatus; app.runs.flashTextual") == []
    qml = ("Connections {\n  target: appStores.runs\n  function onRunsChanged() { if (a) { b() } }\n"
           "  function onCancelOpenChanged() { f() }\n}\n"
           "Connections {\n  target: appStores.runControl\n  function onCancelOpenChanged() { f() }\n}\n"
           "Connections {\n  target: app.runs\n  onDispatchStarted: g()\n}\n")
    blocks = connections_blocks(qml)
    assert len(blocks) == 3
    assert [moved_handlers(b) for b in blocks] == [["onCancelOpenChanged"], [], ["onDispatchStarted"]]


def test_the_moved_set_is_not_empty_and_has_no_staying_member():
    assert {"cancelOpen", "toasts", "dispatchStarted"} <= set(MOVED)
    assert not {"runs", "runById", "amStatus", "selectedRunId", "project", "refresh"} & set(MOVED)
    assert set(MOVED.values()) <= {"runControl", "runAlerts", "runDispatch"} | {
        MOVED["runSettings"], MOVED["runSettingsRunner"]}


@pytest.mark.parametrize("path", caller_params())
def test_no_ui_file_reaches_a_moved_member_through_runs(path):
    hits = [f"{rel(path)}:{n} {member} -> {MOVED[member]}" for n, member in moved_hits(path.read_text())]
    assert hits == []


@pytest.mark.xfail(strict=True, reason="Panel still connects to the RunStore shims")
def test_no_ui_connections_on_runs_handles_a_moved_signal():
    found = [f"{rel(p)}: {h}" for p in caller_files("ui", suffixes=(".qml",))
             for block in connections_blocks(p.read_text()) for h in moved_handlers(block)]
    assert found == []
