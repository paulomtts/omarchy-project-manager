"""docs/architecture.md describes the five run stores as App composes them; README.md names none.

Each run store has one top-level bullet in the `core/stores/` list that names the App property composing
it, every input App binds on it and every signal App routes from it. No line names a shim, a sibling
handle, or a member `RunStore` no longer owns.
"""
import re

import pytest

from test_run_store_callers import MOVED, ROOT, moved_hits

DOC = ROOT / "docs" / "architecture.md"
README = ROOT / "README.md"
APP = ROOT / "core" / "stores" / "App.qml"

# bullet order in the core/stores/ list
STORES = ["RunStore", "RunControlStore", "RunAlertsStore", "RunDispatchStore", "RunTitlesStore"]

SHIM_RE = re.compile(r"\b(shim\w*|controlStore|alertsStore|dispatchStore)\b")
RUN_STORE_MEMBER_RE = re.compile(
    r"\bRunStore(?:\.|'s `)(" + "|".join(sorted(MOVED, key=len, reverse=True)) + r")\b")
README_TOKENS = ["RunStore", "RunControlStore", "RunAlertsStore", "RunDispatchStore", "RunTitlesStore",
                 "app.runs", "app.runControl", "app.runAlerts", "app.runDispatch", "app.runTitles", "shim"]


def bullet(name, text=None):
    """(1-based line, text) of the one top-level "- `name`" bullet, through its indented and blank lines."""
    lines = (DOC.read_text() if text is None else text).splitlines()
    head = f"- `{name}`"
    starts = [i for i, line in enumerate(lines) if line.startswith(head)]
    assert len(starts) == 1, f"{len(starts)} top-level {head} bullets, want 1"
    body = [lines[starts[0]]]
    for line in lines[starts[0] + 1:]:
        if line.strip() and not line[0].isspace():
            break
        body.append(line)
    while not body[-1].strip():
        body.pop()
    return starts[0] + 1, "\n".join(body)


def app_wiring(store_type, text=None):
    """(App handle, bound property names, routed signal names) of App's `<store_type>` property block."""
    text = APP.read_text() if text is None else text
    m = re.search(rf"readonly property {store_type} (\w+): {store_type} \{{", text)
    assert m, f"App composes no {store_type}"
    start = m.end() - 1
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                break
    names = re.findall(r"^ {4}(\w+):", text[start:i + 1], re.M)
    handlers = [n for n in names if re.match(r"on[A-Z]", n)]
    props = [n for n in names if n not in handlers]
    return m.group(1), props, [h[2].lower() + h[3:] for h in handlers]


def mentions(name, text):
    """Whether `text` names `name` backticked as a whole token: `name` or `name(...`."""
    return re.search("`" + re.escape(name) + "[`(]", text) is not None


def doc_hits(pattern, text):
    return [f"{n}: {m.group(0)}" for n, line in enumerate(text.splitlines(), 1) for m in pattern.finditer(line)]


def test_the_doc_helpers_flag_and_accept_what_they_should():
    md = ("intro\n- `A.qml` first line\n  cont `x`\n\n  more\n\nNext paragraph\n"
          "- `A.qmlx` other\n- `B.qml` b\n- `B.qml` again\n")
    assert bullet("A.qml", md) == (2, "- `A.qml` first line\n  cont `x`\n\n  more")
    assert bullet("A.qmlx", md) == (8, "- `A.qmlx` other")
    with pytest.raises(AssertionError):
        bullet("C.qml", md)
    with pytest.raises(AssertionError):
        bullet("B.qml", md)
    app = ("Item {\n  id: app\n"
           "  readonly property FooStore foo: FooStore {\n"
           "    backendDir: app.backendDir\n    active: app.panelOpen\n"
           "    onToggled: {\n      app.nav.cursorIndex = 0\n      app.nav.scrollOnCursor = false\n    }\n"
           "    onReplied: function(root, outcome) {\n      if (outcome === \"ok\") app.bar.settle()\n    }\n"
           "  }\n"
           "  readonly property BarStore bar: BarStore {\n    runs: app.foo.runs\n"
           "    onNoticeRequested: function(text) { app.foo.flash(text) }\n  }\n}\n")
    assert app_wiring("FooStore", app) == ("foo", ["backendDir", "active"], ["toggled", "replied"])
    assert app_wiring("BarStore", app) == ("bar", ["runs"], ["noticeRequested"])
    with pytest.raises(AssertionError):
        app_wiring("BazStore", app)
    assert mentions("runs", "the `runs` list") and mentions("flash", "`flash(text)`")
    assert not mentions("runs", "`runsByProject`") and not mentions("flash", "`app.runControl.flash`")


def test_each_run_store_has_one_bullet_in_order():
    lines = [bullet(f"{store}.qml")[0] for store in STORES]
    assert lines == sorted(lines), dict(zip(STORES, lines))


@pytest.mark.parametrize("store", STORES)
def test_each_bullet_names_its_app_handle(store):
    handle = app_wiring(store)[0]
    line, text = bullet(f"{store}.qml")
    assert f"`app.{handle}`" in text, f"docs/architecture.md:{line} {store}.qml names no `app.{handle}`"


@pytest.mark.parametrize("store", STORES)
def test_each_bullet_names_every_input_and_routed_signal_app_wires(store):
    _, props, signals = app_wiring(store)
    line, text = bullet(f"{store}.qml")
    missing = [name for name in props + signals if not mentions(name, text)]
    assert missing == [], f"docs/architecture.md:{line} {store}.qml"


def test_the_snapshot_reply_settles_control_before_alerts():
    line, text = bullet("RunStore.qml")
    settle = text.find("settleAfterSnapshot()")
    alerts = text.find("app.runAlerts.snapshotReplied")
    assert settle != -1 and alerts != -1 and settle < alerts, (line, settle, alerts)


def test_run_store_bullet_names_no_member_it_does_not_own():
    line, text = bullet("RunStore.qml")
    owned = [f"{m} -> {MOVED[m]}" for m in MOVED if mentions(m, text)]
    assert owned == [], f"docs/architecture.md:{line} RunStore.qml"


def test_the_doc_names_no_shim_or_handle():
    assert doc_hits(SHIM_RE, DOC.read_text()) == []


def test_the_doc_reaches_no_moved_member_through_the_run_store():
    text = DOC.read_text()
    hits = [f"{n}: .runs.{m} -> {MOVED[m]}" for n, m in moved_hits(text)] + doc_hits(RUN_STORE_MEMBER_RE, text)
    assert hits == []


def test_the_dispatch_bullet_says_panel_connects_dispatch_started():
    line, text = bullet("RunDispatchStore.qml")
    assert "dispatchStarted" in text and "Panel" in text, f"docs/architecture.md:{line}"


def test_the_doc_does_not_say_closing_the_panel_keeps_a_dispatch():
    hits = [n for n, line in enumerate(DOC.read_text().splitlines(), 1) if "the store keeps an open dispatch" in line]
    assert hits == []


def test_the_readme_names_no_run_store():
    hits = [f"{n}: {token}" for n, line in enumerate(README.read_text().splitlines(), 1)
            for token in README_TOKENS if token in line]
    assert hits == []
