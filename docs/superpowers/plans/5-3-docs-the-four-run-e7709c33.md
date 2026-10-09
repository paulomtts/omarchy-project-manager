# 5.3 Docs: the four run stores Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `docs/architecture.md` describes `RunStore`, `RunControlStore`, `RunAlertsStore` and `RunDispatchStore` as `core/stores/App.qml` composes them, with no shim, no sibling handle and no member reached through a store that does not own it. A new pytest file pins this.

**Architecture:** Task 1 adds `tests/architecture/test_run_store_docs.py`. It reads the four App property blocks out of `App.qml` (handle, bound inputs, routed signals) and checks each store's top-level bullet in the doc against them. It also checks the whole doc for shim words and moved members, and checks that `README.md` names no store. It reuses `MOVED`, `ROOT` and `moved_hits` from `test_run_store_callers.py`. Task 2 rewrites the `core/stores/` list: the `RunStore.qml` bullet gains its handle, inputs and snapshot-reply order, the shim paragraph goes, and the dispatch paragraph becomes a top-level `RunDispatchStore.qml` bullet. Task 3 fixes the UI paragraphs (`DispatchDialog`, the run screens, Panel's dispatch). Each doc edit is a Python script of exact `old → new` swaps, and every anchor must match exactly once.

**Tech Stack:** Markdown, pytest (plain Python reading repo files), QML read as text only. `bash tests/run.sh` runs pytest over `tests/` and then every `tst_*.qml`. If `python3` has no pytest, use `uv run --with pytest python3 -m pytest …`, which is the fallback `tests/run.sh` uses too.

**Spec:** `docs/superpowers/specs/5-3-docs-the-four-run-e7709c33.md` (copied verbatim at the end of this plan, every heading demoted one level).

## Global Constraints

- Owners and App properties: `RunStore` = `app.runs`, `RunControlStore` = `app.runControl`, `RunAlertsStore` = `app.runAlerts`, `RunDispatchStore` = `app.runDispatch` (P l.52-57).
- A store never imports or names a sibling, and wiring is explicit App properties and App-level handlers (P l.46-47).
- One App handler for `snapshotReplied`: `settleAfterSnapshot()` on `ok`, then `runAlerts.snapshotReplied(…)` (P l.85-86).
- The shims and handles are gone after the last story (P l.128-130).
- The document is the only deliverable. No `.qml`, `.js` or `.py` file changes outside `tests/architecture/test_run_store_docs.py`. `README.md` does not change.
- `docs/architecture.md` `:84-90` and the bodies of `:93`, `:94` and of the dispatch text from `:92` stay as they are, apart from the listed edits.
- State only what the code does. Docstrings and comments state the contract only.
- `tests/architecture` stays green (`test_layers.py`, `test_icon_glyphs.py`, `test_run_store_callers.py`).
- Verification: `bash tests/run.sh` green. Repo wrapper: `bash /home/mtts/.local/state/agent-manager/verify/vfy-opm.sh`.
- Never run `pkill`, `killall` or a pattern `kill`. Wrap long runs in `timeout`.

## Review Focus

1. **A bullet that swallows the next paragraph or loses its own continuation.** `bullet()` must keep `RunStore.qml`'s indented lines `:84-90` (they carry `searchQuery`, `runFilterToggled()`, `projectFilterToggled()` and `snapshotReplied(`) and stop at the unindented `Other \`ui/\` pieces` paragraph after the new `RunDispatchStore.qml` bullet. Task 1's helper test covers continuation lines, blank lines and the stop. Task 3 Step 4 checks that the full architecture suite is green.
2. **A name prefix counted as the name.** `` `runsByProject` `` must not count as `runs`, `` `app.runControl.flash` `` must not count as `flash`, and a heading `` - `A.qmlx` `` must not count as `A.qml`. Task 1's helper test pins all three.
3. **An App property block read too widely or too narrowly.** Handler bodies (6-space lines, `function(…)` handlers, multi-line `on…: {` blocks) must not leak into the inputs, and the brace match must stop at the block's own `}`. Task 1's two-store fragment pins it, and the real App blocks give `RunStore` 5 inputs and 3 signals.
4. **A moved member reached on `RunStore` by name instead of by path.** Covers `RunStore.retargetToMilestone` and ``RunStore's `dispatchState` ``, which `moved_hits` (`.runs.` only) misses. Task 1's `RUN_STORE_MEMBER_RE` covers both forms, and Task 3 removes both.
5. **Panel close and the dispatch.** The doc must not say the dispatch survives a panel close (`RunDispatchStore.qml:45` closes it unless `starting`). Test 9 pins the old sentence's absence, and Task 3's replacement states the `active` reaction.

## Execution notes

- Save each script in this plan to `/tmp/5-3/<name>.py`, outside the repo, so `tests/run.sh`'s tar copy never sees it. Run it from the worktree root as `python3 /tmp/5-3/<name>.py .`. A script fails with an `AssertionError` if an anchor does not match exactly once. If that happens, stop and read the line: the anchors are copied from commit `d326d03`.
- Every script and test in this plan was run against `d326d03` in a scratch copy. The counts and results below come from that run.
- Do not commit the scripts.

## File map

| file | change | task |
|---|---|---|
| `tests/architecture/test_run_store_docs.py` | create: helpers `bullet`, `app_wiring`, `mentions`, `doc_hits`, and 11 tests (17 cases after parametrization) | 1 |
| `docs/architecture.md` `:83`, `:91`, `:92`, after `:94` | the `RunStore.qml` bullet, the shim paragraph deleted, the `RunDispatchStore.qml` bullet | 2 |
| `docs/architecture.md` `:155`, `:167`, `:169` (`:154`, `:166`, `:168` after Task 2) | `DispatchDialog`, the run screens, Panel's dispatch | 3 |

---

### Task 1: The doc test names every drift

**Files:**
- Create: `tests/architecture/test_run_store_docs.py`
- Read (no change): `tests/architecture/test_run_store_callers.py` (`ROOT`, `MOVED`, `moved_hits`), `core/stores/App.qml:106-174`, `docs/architecture.md`, `README.md`

**Interfaces:**
- Consumes: `test_run_store_callers.ROOT` (repo root `Path`), `MOVED` (`{member: owner handle}`), `moved_hits(text) -> [(line, member)]`. pytest's default import mode puts `tests/architecture/` on `sys.path` (there is no `__init__.py`), so `from test_run_store_callers import …` resolves.
- Produces: `bullet(name, text=None) -> (int line, str body)`, which raises `AssertionError` unless exactly one line starts with `` - `name` ``. `app_wiring(store_type, text=None) -> (str handle, list props, list signals)`, which raises `AssertionError` when App composes no such store. `mentions(name, text) -> bool`. `doc_hits(pattern, text) -> ["<line>: <match>"]`. Tasks 2 and 3 only run these tests.

At `d326d03`, App's blocks give:

| store | handle | inputs | routed signals |
|---|---|---|---|
| `RunStore` | `runs` | `backendDir`, `projectRoots`, `project`, `active`, `searchQuery` | `runFilterToggled`, `projectFilterToggled`, `snapshotReplied` |
| `RunControlStore` | `runControl` | `backendDir`, `project`, `active`, `runs` | `refreshRequested`, `runSettingsSaveFailed` |
| `RunAlertsStore` | `runAlerts` | `backendDir`, `active`, `notifyOnEscalation`, `projectRoots` | — |
| `RunDispatchStore` | `runDispatch` | `backendDir`, `project`, `active`, `runs`, `runSettings` | `refreshRequested`, `noticeRequested`, `runSettingsWanted`, `runSettingsSaveRequested` |

- [ ] **Step 1: Write the test file**

Create `tests/architecture/test_run_store_docs.py` with exactly this content:

```python
"""docs/architecture.md describes the four run stores as App composes them; README.md names none.

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
STORES = ["RunStore", "RunControlStore", "RunAlertsStore", "RunDispatchStore"]

SHIM_RE = re.compile(r"\b(shim\w*|controlStore|alertsStore|dispatchStore)\b")
RUN_STORE_MEMBER_RE = re.compile(
    r"\bRunStore(?:\.|'s `)(" + "|".join(sorted(MOVED, key=len, reverse=True)) + r")\b")
README_TOKENS = ["RunStore", "RunControlStore", "RunAlertsStore", "RunDispatchStore",
                 "app.runs", "app.runControl", "app.runAlerts", "app.runDispatch", "shim"]


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
```

- [ ] **Step 2: Run it and see the drifts fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture/test_run_store_docs.py -q`
Expected: `10 failed, 7 passed`. The failures:

- `test_each_run_store_has_one_bullet_in_order`: `0 top-level - \`RunDispatchStore.qml\` bullets, want 1`
- `test_each_bullet_names_its_app_handle[RunStore]`: `docs/architecture.md:83 RunStore.qml names no \`app.runs\``
- `test_each_bullet_names_its_app_handle[RunDispatchStore]` and `test_each_bullet_names_every_input_and_routed_signal_app_wires[RunDispatchStore]`: the missing bullet
- `test_the_snapshot_reply_settles_control_before_alerts`: `(83, -1, -1)`
- `test_run_store_bullet_names_no_member_it_does_not_own`: 63 items, the first `pending -> runControl`
- `test_the_doc_names_no_shim_or_handle`: 10 hits, the first `83: shims`
- `test_the_doc_reaches_no_moved_member_through_the_run_store`: 6 hits, the first `167: .runs.notifyOnEscalation -> runControl`
- `test_the_dispatch_bullet_says_panel_connects_dispatch_started`: the missing bullet
- `test_the_doc_does_not_say_closing_the_panel_keeps_a_dispatch`: `[169]`

The 7 that pass are the helper test, the README guard and the handle and wiring cases for `RunControlStore` and `RunAlertsStore`. If the helper test fails, fix the helper, not the test.

- [ ] **Step 3: Check the rest of the architecture tier still passes**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture -q --ignore=tests/architecture/test_run_store_docs.py`
Expected: all pass. The new file adds no QML and no glyph, so `test_layers.py` and `test_icon_glyphs.py` do not change.

- [ ] **Step 4: Commit**

The docs commit is red on purpose here, because the test is written first and Tasks 2 and 3 turn it green. If the branch rule requires a green commit, fold this commit into Task 2's instead.

```bash
git add tests/architecture/test_run_store_docs.py
git commit -m "test(docs): the architecture doc names each run store's App handle, inputs and routes, and no shim"
```

---

### Task 2: The `core/stores/` list has one bullet per run store

**Files:**
- Modify: `docs/architecture.md:83` (the `RunStore.qml` bullet), `:91` (deleted), `:92` (moved after `:94` as the `RunDispatchStore.qml` bullet)
- Test: `tests/architecture/test_run_store_docs.py`

**Interfaces:**
- Consumes: Task 1's tests.
- Produces: the bullets are `RunStore.qml` at `:83`, its continuation `:84-90`, `RunControlStore.qml` at `:91`, `RunAlertsStore.qml` at `:92` and `RunDispatchStore.qml` at `:93`. Everything after shifts up one line, so Task 3's targets sit at `:154`, `:166` and `:168`.

What changes, quoted from the code at `d326d03` (`core/stores/App.qml:106-174`, `ui/Panel.qml:107-113`):

- `:83`: "`App` hands it `projectRoots`" becomes "`App` composes it as `app.runs` and hands it `projectRoots`". The inputs gain `searchQuery` (`app.nav.searchQuery`), followed by the routed signals, the snapshot-reply order, and the settle sentence moved out of `:91`. "`project` is read only by the run settings shims" becomes "the store itself reads no `project`; App hands `app.runs.project` to `RunControlStore` and `RunDispatchStore`".
- `:91`, the shim paragraph, is deleted. Its one surviving fact ("A snapshot settles requests only through App's `snapshotReplied` route; `RunStore` never settles one itself.") now sits in `:83`.
- `:92`: the opening sentence up to "It launches no `viewer-state.py`." is replaced by the new bullet's opening. The rest of the paragraph, from `` `openDispatch(card, cardMap)` `` to "except while `starting`.", is kept byte for byte. The line moves to just after the `RunAlertsStore.qml` bullet.

- [ ] **Step 1: Confirm the RED state for this task's tests**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture/test_run_store_docs.py -q`
Expected: `10 failed, 7 passed`, as in Task 1 Step 2.

- [ ] **Step 2: Save the edit script**

Save this as `/tmp/5-3/stores_list.py`:

```python
"""5.3 Task 2: the core/stores/ list of docs/architecture.md gets one bullet per run store."""
import sys
from pathlib import Path

doc = Path(sys.argv[1]) / "docs" / "architecture.md"
text = doc.read_text()


def swap(text, old, new):
    assert text.count(old) == 1, f"{text.count(old)} matches for {old[:60]!r}"
    return text.replace(old, new)


# 1. the RunStore.qml bullet: its App handle, every input and routed signal, the snapshot reply order
text = swap(text,
    "It never reaches for another store: `App` hands it `projectRoots` (`[{root, name}]`",
    "It never reaches for another store: `App` composes it as `app.runs` and hands it `projectRoots` (`[{root, name}]`")
text = swap(text,
    "`backendDir` and `active` (App's `panelOpen`, which the panel binds to its `opened`). `usableRoots()`",
    "`backendDir`, `active` (App's `panelOpen`, which the panel binds to its `opened`) and `searchQuery` "
    "(`app.nav.searchQuery`). App routes its `runFilterToggled()` and `projectFilterToggled()` to putting the "
    "cursor home (`app.nav.cursorIndex = 0`, `app.nav.scrollOnCursor = false`). Its one "
    "`snapshotReplied(root, outcome, previousRuns, runs)` handler calls `app.runControl.settleAfterSnapshot()` "
    "when the outcome is `ok`, and only then `app.runAlerts.snapshotReplied(root, outcome, previousRuns, runs)`. "
    "A snapshot settles requests only through App's `snapshotReplied` route; `RunStore` never settles one "
    "itself. App routes its `runsNudged(ids)` nowhere. `usableRoots()`")
text = swap(text,
    "A project switch leaves the run list alone: `project` is read only by the run settings shims.",
    "A project switch leaves the run list alone: the store itself reads no `project`; App hands "
    "`app.runs.project` to `RunControlStore` and `RunDispatchStore`.")

lines = text.split("\n")

# 3. the shim paragraph goes
shim = [i for i, line in enumerate(lines) if line.startswith("  Run controls, the cancel confirmation, the footer flash")]
assert len(shim) == 1, shim
del lines[shim[0]]

# 4. the dispatch paragraph becomes a top-level RunDispatchStore.qml bullet after RunAlertsStore.qml
old_open = ("  Dispatch (S3 3.1) is `RunDispatchStore`'s (`app.runDispatch`). App hands it `backendDir`, `project`, "
            "`active`, `runs` and `runSettings` (`app.runControl.runSettingsOf(project)`), and routes "
            "`refreshRequested` to the run store, `noticeRequested` to `app.runControl.flash`, `runSettingsWanted` / "
            "`runSettingsSaveRequested` to `app.runControl.loadRunSettings` / `saveRunSettings`, and run control's "
            "`runSettingsSaveFailed` back to `dispatchSaveFailed`. It launches no `viewer-state.py`.")
new_open = ("- `RunDispatchStore.qml` the dispatch (S3 3.1), for the open project. It never reaches for another "
            "store: `App` composes it as `app.runDispatch` and hands it `backendDir`, `project` (`app.runs.project`), "
            "`active` (App's `panelOpen`), `runs` (`app.runs.runs`) and `runSettings` "
            "(`app.runControl.runSettingsOf(app.runs.project)`), and routes its `refreshRequested(roots)` to the run "
            "store (`\"all\"` to `refresh()`, a list of roots to `requestSnapshot(roots)`), its "
            "`noticeRequested(text)` to `app.runControl.flash(text)`, its `runSettingsWanted(root)` / "
            "`runSettingsSaveRequested(root, patch)` to `app.runControl.loadRunSettings(root)` / "
            "`saveRunSettings(root, patch)`, and run control's `runSettingsSaveFailed(root, patch)` back to "
            "`dispatchSaveFailed(root, patch)`. App does not route `dispatchStarted(runId)`: Panel connects to it "
            "on `appStores.runDispatch`, closes the dispatch and calls `navi.openStartedRun(runId)`. It launches no "
            "`viewer-state.py`.")
dispatch = [i for i, line in enumerate(lines) if line.startswith(old_open)]
assert len(dispatch) == 1, dispatch
moved = new_open + lines.pop(dispatch[0])[len(old_open):]
alerts = [i for i, line in enumerate(lines) if line.startswith("- `RunAlertsStore.qml` ")]
assert len(alerts) == 1, alerts
lines.insert(alerts[0] + 1, moved)

doc.write_text("\n".join(lines))
print("stores list: 3 sentences swapped, shim paragraph deleted, dispatch bullet at line", alerts[0] + 2)
```

- [ ] **Step 3: Run the script**

Run: `python3 /tmp/5-3/stores_list.py .`
Expected output: `stores list: 3 sentences swapped, shim paragraph deleted, dispatch bullet at line 93`

- [ ] **Step 4: Run the doc tests and check that only the UI drifts remain**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture/test_run_store_docs.py -q`
Expected: `3 failed, 14 passed`. The three failures belong to Task 3:
- `test_the_doc_names_no_shim_or_handle`: `['166: shims']`
- `test_the_doc_reaches_no_moved_member_through_the_run_store`: 6 hits: four `.runs.` paths and `RunStore.retargetToMilestone` on `166` / `168`, and `154: RunStore's \`dispatchState`
- `test_the_doc_does_not_say_closing_the_panel_keeps_a_dispatch`: `[168]`

Tests 1-5 and 8 (order, handles, inputs and signals, snapshot order, no moved member in `RunStore.qml`, `dispatchStarted` and Panel) now pass.

- [ ] **Step 5: Read the result**

Run: `awk 'NR>=82 && NR<=95 {print NR": "substr($0,1,70)}' docs/architecture.md`
Expected: `83: - \`RunStore.qml\` …`, `84`-`90` indented, `91: - \`RunControlStore.qml\` …`, `92: - \`RunAlertsStore.qml\` …`, `93: - \`RunDispatchStore.qml\` the dispatch (S3 3.1), for the open project. …`, `94:` blank, `95: Other \`ui/\` pieces: …`. Then run `git diff --stat docs/architecture.md`. Expect one file changed and no other file touched.

- [ ] **Step 6: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(runs): one core/stores bullet per run store, each naming its App handle, inputs and routes; the shim paragraph goes"
```

---

### Task 3: The UI paragraphs name each member's owner

**Files:**
- Modify: `docs/architecture.md:154` (`DispatchDialog`, was `:155`), `:166` (the run screens, was `:167`), `:168` (Panel owns the dispatch, was `:169`)
- Test: `tests/architecture/test_run_store_docs.py`

**Interfaces:**
- Consumes: Task 2's doc layout. The anchors are matched by text, not by line number, so they work whatever the line numbers are.
- Produces: the finished document.

The handles each UI file reads at `d326d03`: `BoardScreen.qml` and `GraphScreen.qml` read `app.runs`. `RunsScreen.qml`, `RunDetailScreen.qml`, `CardDetailScreen.qml` and `Navigator.qml` read `app.runs` and `app.runControl`. `Panel.qml` and `Shortcuts.qml` read all four. Panel calls `appStores.runAlerts.dismissToast(key)` at `ui/Panel.qml:788`. `RunDispatchStore.qml:45` closes the dispatch when `active` turns false, and `:148-152` refuse while `starting`.

- [ ] **Step 1: Confirm the RED state**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture/test_run_store_docs.py -q`
Expected: `3 failed, 14 passed`, as in Task 2 Step 4.

- [ ] **Step 2: Save the edit script**

Save this as `/tmp/5-3/ui_paragraphs.py`:

```python
"""5.3 Task 3: the UI paragraphs of docs/architecture.md name the store each member lives on."""
import sys
from pathlib import Path

doc = Path(sys.argv[1]) / "docs" / "architecture.md"
text = doc.read_text()


def swap(text, old, new):
    assert text.count(old) == 1, f"{text.count(old)} matches for {old[:60]!r}"
    return text.replace(old, new)


# 6. DispatchDialog
text = swap(text, "the owner passes RunStore's `dispatchState`", "the owner passes RunDispatchStore's `dispatchState`")

# 7. the run screens paragraph
text = swap(text,
    "The run screens read `app.runs` and never import `core/stores`.",
    "The run screens read `app.runs` and `app.runControl` (`BoardScreen` and `GraphScreen` only `app.runs`) and "
    "never import `core/stores`.")
text = swap(text,
    "(`app.runs.notifyOnEscalation`, changed through `setNotifyOnEscalation`)",
    "(`app.runControl.notifyOnEscalation`, changed through `setNotifyOnEscalation`)")
text = swap(text,
    "it is `RunControlStore`'s viewer-wide switch, read through the `app.runs` shims (`viewer-state.py",
    "it is `RunControlStore`'s viewer-wide switch (`viewer-state.py")
text = swap(text,
    "Pause and Resume call `app.runs.control(action, id)`;",
    "Pause and Resume call `app.runControl.control(action, id)`;")
text = swap(text,
    "Panel answers every `cancelRequested` with `app.runs.openCancel(runId)`:",
    "Panel answers every `cancelRequested` with `app.runControl.openCancel(runId)`:")
text = swap(text, "Dismiss calls `dismissToast(key)`;", "Dismiss calls `app.runAlerts.dismissToast(key)`;")

# 8. Panel owns the dispatch
text = swap(text, "`RunStore.retargetToMilestone()`", "`RunDispatchStore.retargetToMilestone()`")
text = swap(text, "and call `app.runs.openDispatch`;", "and call `app.runDispatch.openDispatch`;")
text = swap(text,
    "and drop the chip row -- closing the panel does not: the store keeps an open dispatch, and the dialog and "
    "its chips are still there when the panel reopens; a chip",
    "and drop the chip row; closing the panel closes the dispatch too (`RunDispatchStore`'s own `active` "
    "reaction), except while starting; a chip")

doc.write_text(text)
print("ui paragraphs: 10 sentences swapped")
```

- [ ] **Step 3: Run the script**

Run: `python3 /tmp/5-3/ui_paragraphs.py .`
Expected output: `ui paragraphs: 10 sentences swapped`

- [ ] **Step 4: Run the architecture tier**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture -q`
Expected: `149 passed` (17 of them in `test_run_store_docs.py`).

- [ ] **Step 5: Check that nothing outside the doc and the test changed**

Run: `git diff --stat d326d03 -- . ':!docs/superpowers'`
Expected: exactly `docs/architecture.md` and `tests/architecture/test_run_store_docs.py`. Then run `grep -n 'RunStore\|app\.runs\|shim' README.md` and expect no output.

- [ ] **Step 6: Run the full suite**

Run: `timeout 1200 bash tests/run.sh`, then `timeout 1200 bash /home/mtts/.local/state/agent-manager/verify/vfy-opm.sh`
Expected: pytest all pass, every QML `Totals` line shows `0 failed`, no `TypeError` / `ReferenceError` line, and exit status 0.

- [ ] **Step 7: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(runs): the run screens, the dispatch dialog and Panel's dispatch name the store each member lives on"
```

---

## Self-review against the spec

- **Purpose, bullets 1-3**: Task 2 (one bullet per store, in order, with handle, inputs and routes; the snapshot order stated once in `RunStore.qml`'s bullet) and Task 3 (the UI paragraphs).
- **Required changes 1-5**: Task 2's `stores_list.py` (1 handle, `searchQuery`, `project` sentence and routes; 2 untouched; 3 shim paragraph deleted and settle fact kept; 4 dispatch bullet promoted with `dispatchStarted` connected by Panel; 5 untouched, and all `:93` / `:94` tests pass unchanged).
- **Required changes 6-8**: Task 3's `ui_paragraphs.py` (6 `DispatchDialog`; 7 handles read, `notifyOnEscalation`, shims phrase, `control`, `openCancel`, `dismissToast`; 8 `openDispatch`, `retargetToMilestone`, the panel close sentence).
- **9 and README**: not edited. Test 10 guards the README.
- **Tests 1-11**: all in Task 1's file under the spec's names. Tests 2 and 3 are parametrized over the four stores. Test 11 covers continuation and blank lines, the unindented stop, a missing and a duplicated bullet, and a two-store App fragment with a multi-line `on…: {` and a `function(…)` handler. It reuses `MOVED`, `ROOT` and `moved_hits` by import.
- **Red before green**: verified in a scratch copy at `d326d03`: 10 failed / 7 passed → 3 / 14 after Task 2 → 0 / 17 after Task 3. `tests/architecture` gives 149 passed.
- **Placeholders**: none. Every script and the test file are given in full.
- **Names**: `bullet`, `app_wiring`, `mentions`, `doc_hits`, `STORES`, `SHIM_RE`, `RUN_STORE_MEMBER_RE` and `README_TOKENS` are defined once in Task 1 and used only there.

## The spec (verbatim)

## 5.3 Docs: the four run stores — design

Card: `e7709c33` ("5.3 Docs: the four run stores"). It is a subtask of story `97aa329f` "Retire the
RunStore shims". It is blocked by 5.2 `173b82e2` ("RunStore shims removed"), which has landed on
this branch (`d326d03`). The parent design is
`docs/superpowers/specs/2026-10-05-split-runstore-design.md`, cited below as "P l.N". Line numbers
into `docs/`, `core/`, `ui/` and `tests/` come from this card's start (`d326d03`).

### Purpose

After 5.2, `RunStore` holds no shim and App sets no handle (P l.128-130). `docs/architecture.md`
still describes the shims and still sends the run screens through `app.runs` for members that
`RunControlStore` and `RunDispatchStore` own. This card makes the document say what the code does:

- One top-level bullet per run store in the `core/stores/` list: `RunStore.qml`,
  `RunControlStore.qml`, `RunAlertsStore.qml`, `RunDispatchStore.qml`, in that order. Each says what
  the store owns, which App property composes it (`app.runs`, `app.runControl`, `app.runAlerts`,
  `app.runDispatch`; P l.52-57), what App hands it and which of its signals App routes where
  (P l.72-79).
- The ordering on a snapshot reply is stated once and correctly: App's one `onSnapshotReplied`
  handler calls `app.runControl.settleAfterSnapshot()` when the outcome is `ok`, and only then
  `app.runAlerts.snapshotReplied(…)` (P l.85-86; `core/stores/App.qml:121-124`).
- The UI paragraphs name the store each member really lives on.

The document is the only deliverable. No `.qml`, `.js` or `.py` file outside `tests/architecture/`
changes. A user of the plugin sees nothing different.

### What the code does today (the facts the doc must state)

Read from the files at `d326d03`. The plan's implementer re-reads them before writing, and writes
nothing the files do not show.

#### `app.runs` — `RunStore` (`core/stores/App.qml:106-125`)

- App hands it `backendDir`, `projectRoots` (`app.projects.projects` mapped to `{root: root_path,
  name}`, registry order), `project` (the selected project's `root_path`, `""` when none),
  `active` (`app.panelOpen`) and `searchQuery` (`app.nav.searchQuery`).
- App routes `runFilterToggled` and `projectFilterToggled` to putting the cursor home
  (`app.nav.cursorIndex = 0`, `app.nav.scrollOnCursor = false`) and `snapshotReplied(root, outcome,
  previousRuns, runs)` as above. `runsNudged(ids)` is declared (`core/stores/RunStore.qml:121`) and
  App routes it nowhere.
- `RunStore` reads `project` nowhere (`grep -n 'store\.project\b\|onProjectChanged'
  core/stores/RunStore.qml` is empty). App passes `app.runs.project` on to run control and the
  dispatch. So the sentence at `docs/architecture.md:83` "`project` is read only by the run settings
  shims" becomes: the store itself reads no `project`, and a project switch leaves the run list
  alone; App hands `app.runs.project` to `RunControlStore` and `RunDispatchStore`.
- It owns the registry roots, the snapshots, the nudges and the watch, the start-over, `amSchema` /
  `amVersion` and the timers, the reply matching and `snapshotReplied`, the list filters and the
  logs. These are today's paragraphs at `docs/architecture.md:84-90`, and they stay as they are.
- It owns no control, alerts or dispatch member, and no `controlStore` / `alertsStore` /
  `dispatchStore` handle. 5.2's App test pins that.

#### `app.runControl` — `RunControlStore` (`core/stores/App.qml:132-142`)

- It gets `backendDir`, `project` (`app.runs.project`), `active` (`app.panelOpen`) and `runs`
  (`app.runs.runs`).
- `refreshRequested(roots)` goes to `app.runs.refresh()` for `"all"`, else to
  `app.runs.requestSnapshot(roots)`.
- `runSettingsSaveFailed(root, patch)` goes to `app.runDispatch.dispatchSaveFailed(root, patch)`.
- The current bullet at `docs/architecture.md:93` already says all of this and how the snapshot
  settles requests. It keeps its text, except where this spec's tests need a change.

#### `app.runAlerts` — `RunAlertsStore` (`core/stores/App.qml:148-153`)

- It gets `backendDir`, `active`, `notifyOnEscalation` (`app.runControl.notifyOnEscalation`) and
  `projectRoots` (`app.runs.projectRoots`). App routes none of its signals. Its one input from a
  snapshot is the `snapshotReplied` call in `RunStore`'s handler.
- The current bullet at `docs/architecture.md:94` already says this, and it stays.

#### `app.runDispatch` — `RunDispatchStore` (`core/stores/App.qml:161-174`)

- It gets `backendDir`, `project` (`app.runs.project`), `active` (`app.panelOpen`), `runs`
  (`app.runs.runs`) and `runSettings` (`app.runControl.runSettingsOf(app.runs.project)`).
- `refreshRequested(roots)` goes to `app.runs.refresh()` / `requestSnapshot(roots)`,
  `noticeRequested(text)` to `app.runControl.flash(text)`, `runSettingsWanted(root)` to
  `app.runControl.loadRunSettings(root)` and `runSettingsSaveRequested(root, patch)` to
  `app.runControl.saveRunSettings(root, patch)`.
- App does not route `dispatchStarted(runId)`. Panel connects to it on `appStores.runDispatch`
  (`ui/Panel.qml:107-113`): it calls `closeDispatch()`, then `navi.openStartedRun(runId)`.
- Its lifecycle: `onActiveChanged` closes the dispatch when `active` turns false
  (`core/stores/RunDispatchStore.qml:45`). `closeDispatch()` refuses while `starting`
  (`RunDispatchStore.qml:148-152`). `onProjectChanged` resets the dispatch and, when the new project
  is not `""`, emits `runSettingsWanted` (`:49-52`). `tests/core/stores/tst_run_dispatch_store.qml:227-240`
  pins it.
- Today's paragraph at `docs/architecture.md:92` describes the whole dispatch correctly. It becomes a
  top-level `- \`RunDispatchStore.qml\`` bullet after `RunAlertsStore.qml`, opening the same way the
  other two new stores' bullets open ("It never reaches for another store: `App` composes it as
  `app.runDispatch` and hands it …").

#### The UI (`ui/`)

Which handle each file reads (`grep -o 'app\(Stores\)\?\.\(runs\|runControl\|runAlerts\|runDispatch\)\b'`):

| file | handles |
|---|---|
| `ui/screens/BoardScreen.qml`, `GraphScreen.qml` | `app.runs` |
| `ui/screens/RunsScreen.qml`, `RunDetailScreen.qml`, `CardDetailScreen.qml`, `ui/Navigator.qml` | `app.runs`, `app.runControl` |
| `ui/Panel.qml`, `ui/Shortcuts.qml` | all four |

The member paths at `d326d03`: `control`, `openCancel`, `confirmCancel`, `closeCancel`,
`cancel*`, `flash` / `flashText`, `stillWaiting*`, `lastControlError*`, `pending`, `refusalOf`,
`notifyOnEscalation` / `setNotifyOnEscalation` are read on `runControl`. `toasts`,
`dismissToast` and `dismissAllToasts` are read on `runAlerts`. `dispatch*`, `openDispatch`,
`closeDispatch`, `setDispatchField`, `dispatchStart` and `retargetToMilestone` are read on
`runDispatch`. `tests/architecture/test_run_store_callers.py` enforces this for `ui/` and `tests/ui/`.

### Required document changes (observable result)

`docs/architecture.md`:

1. **`:83` (`RunStore.qml` bullet).** Name `app.runs` as the App property that composes it. Keep
   the inputs it lists, and add `searchQuery` (`app.nav.searchQuery`) to them. Replace "`project` is read only by the run settings shims" with the
   fact above. Name the signals App routes: `runFilterToggled` / `projectFilterToggled` put the cursor
   home, and `snapshotReplied` goes to run control's `settleAfterSnapshot()` on `ok`, then to
   `app.runAlerts.snapshotReplied`, in that order.
2. **`:84-90`.** Unchanged.
3. **`:91` (the shim paragraph).** Delete it. Keep one fact it carries and move it into the
   `RunStore.qml` bullet: "A snapshot settles requests only through App's `snapshotReplied` route;
   `RunStore` never settles one itself."
4. **`:92` (Dispatch).** Promote it to a top-level `- \`RunDispatchStore.qml\`` bullet placed after
   the `RunAlertsStore.qml` bullet. It opens with what App hands it and routes (above), and
   `dispatchStarted(runId)` is said to be connected by Panel, not App. The rest of the text stays.
5. **`:93`, `:94`.** Keep them. Change only what a test below fails on.
6. **`:155` (`DispatchDialog`).** "the owner passes RunStore's `dispatchState` …" becomes
   "RunDispatchStore's".
7. **`:167` (the run screens paragraph).**
   - "The run screens read `app.runs`" becomes the handles they read: `app.runs` and
     `app.runControl` (see the UI table).
   - "`app.runs.notifyOnEscalation`" becomes `app.runControl.notifyOnEscalation`, and "read through
     the `app.runs` shims" is deleted.
   - "`app.runs.control(action, id)`" becomes `app.runControl.control(action, id)`.
   - "`app.runs.openCancel(runId)`" becomes `app.runControl.openCancel(runId)`.
   - Name `RunToast`'s Dismiss as `app.runAlerts.dismissToast(key)`. Panel calls it at
     `ui/Panel.qml:788`.
8. **`:169` (Panel owns the dispatch).**
   - "`app.runs.openDispatch`" becomes `app.runDispatch.openDispatch`.
   - "`RunStore.retargetToMilestone()`" becomes `RunDispatchStore.retargetToMilestone()`.
   - "closing the panel does not: the store keeps an open dispatch, and the dialog and its chips are
     still there when the panel reopens" contradicts the code and `:92` / `:173`. It becomes: closing
     the panel closes the dispatch too (`RunDispatchStore`'s own `active` reaction), except while
     starting.
9. **`:173`, `:198`, `:263`.** Correct already (they name `RunStore` for the watch, the debounce and
   the list snapshot). No change.

`README.md`: it names no store and no `app.runs` path (`grep -n 'RunStore\|app\.runs' README.md` is
empty), and its Runs and Dispatch bullets (`:154-155`) describe behaviour only. No change. The test
below pins that it stays store-free.

### Error paths

This is a document, so it has no runtime error path. The failure that matters is drift: the
document naming a member on a store that does not own it, naming a removed shim or handle, or
missing an input App binds. Every test below fails on one of those drifts, and the message names
the line and the token.

### Tests

All in one new file, `tests/architecture/test_run_store_docs.py`. **Tier: `tests/architecture`
(pytest, plain Python reading repo files).** The claims are static facts about two repo files and
`core/stores/App.qml`. That tier already holds the run-store caller guard
(`test_run_store_callers.py`), runs in `bash tests/run.sh`'s pytest step, and needs no QML engine.
A QML test cannot read Markdown, and no other tier checks documents. Each test is written first and
fails against `d326d03`'s document. The README test is the exception: it is a guard, and it passes
from the start.

Helpers (in the test file):

- `bullet(name)`: the text of the top-level `- \`<name>\`` bullet of `docs/architecture.md`, from
  its line through every following line that is blank or starts with whitespace, stopping at the
  next line that starts with neither (the next bullet or paragraph). It fails when the bullet is
  missing or appears twice.
- `app_wiring(store_type)`: from `core/stores/App.qml`, the `readonly property <Type> <handle>:
  <Type> {` block (brace-matched). It returns `(handle, bound property names, routed signal
  names)`. A property is a `^\s{4}(\w+):` line that is not `on…`. A signal is an `on<Name>:`
  handler lowercased at its first letter (`onSnapshotReplied` → `snapshotReplied`). It reuses
  `test_run_store_callers.MOVED` / `moved_hits` by import instead of copying them (rule 2 spirit,
  P l.68-71; "no duplicated components").

Tests:

1. `test_each_run_store_has_one_bullet_in_order`: the four bullets exist exactly once, in the order
   `RunStore.qml`, `RunControlStore.qml`, `RunAlertsStore.qml`, `RunDispatchStore.qml`. It fails today
   because there is no `RunDispatchStore.qml` bullet.
2. `test_each_bullet_names_its_app_handle`: `RunStore.qml`'s bullet contains `` `app.runs` `` and
   the others contain `` `app.runControl` ``, `` `app.runAlerts` `` and `` `app.runDispatch` ``
   respectively. The handle is taken from `app_wiring`, not hard-coded. It fails today on `RunStore`
   and `RunDispatchStore`.
3. `test_each_bullet_names_every_input_and_routed_signal_app_wires`: for each store, every bound
   property name and routed signal name from `app_wiring` appears backticked in its bullet
   (`` `name` `` or `` `name(`` …). It fails today on the missing dispatch bullet. `RunStore`'s
   bullet runs through its indented continuation paragraphs `:84-90`, so the names they carry
   count.
4. `test_the_snapshot_reply_settles_control_before_alerts`: `RunStore.qml`'s bullet contains
   `settleAfterSnapshot()` and `app.runAlerts.snapshotReplied`, the first before the second. It fails
   today because `:83-91` names neither in that bullet.
5. `test_run_store_bullet_names_no_member_it_does_not_own`: no `MOVED` member appears backticked as a
   whole token (`` `member` `` or `` `member(`` …) in `RunStore.qml`'s bullet. It fails today on the
   shim lists at `:91`.
6. `test_the_doc_names_no_shim_or_handle`: `docs/architecture.md` contains none of `shim`,
   `controlStore`, `alertsStore`, `dispatchStore` (case-sensitive words). It fails today on `:83`,
   `:91` and `:167`.
7. `test_the_doc_reaches_no_moved_member_through_the_run_store`: `moved_hits(doc)` is empty, and no
   `RunStore.<moved>` or ``RunStore's `<moved>` `` appears. It fails today on `:167`
   (`app.runs.control`, `openCancel`, `notifyOnEscalation`), `:169` (`app.runs.openDispatch`,
   `RunStore.retargetToMilestone`) and `:155` (``RunStore's `dispatchState` ``).
8. `test_the_dispatch_bullet_says_panel_connects_dispatch_started`: `RunDispatchStore.qml`'s bullet
   contains `dispatchStarted` and `Panel`. It fails today because the bullet is missing.
9. `test_the_doc_does_not_say_closing_the_panel_keeps_a_dispatch`: `docs/architecture.md` does not
   contain `the store keeps an open dispatch`. It fails today on `:169`.
10. `test_the_readme_names_no_run_store`: `README.md` contains none of `RunStore`, `RunControlStore`,
    `RunAlertsStore`, `RunDispatchStore`, `app.runs`, `app.runControl`, `app.runAlerts`,
    `app.runDispatch`, `shim`. It passes today, and it keeps the README store-free.
11. `test_the_doc_helpers_flag_and_accept_what_they_should`: a unit test of `bullet()` and
    `app_wiring()` on inline strings. It covers a bullet with indented continuation and blank lines,
    a following unindented paragraph that ends the bullet, a missing bullet and a duplicated one (both
    raise), and a two-store App fragment with a multi-line `on…: {` handler and a `function(…)`
    handler. This follows the pattern of
    `test_run_store_callers.py::test_the_guard_helpers_flag_and_accept_what_they_should`.

Verification: `bash tests/run.sh` is green. The repo wrapper is
`bash /home/mtts/.local/state/agent-manager/verify/vfy-opm.sh`. `tests/architecture/test_layers.py`
and `test_icon_glyphs.py` stay green: the new test file adds no QML and no glyph.

### Inherited constraints

| constraint | source |
|---|---|
| Owners and App properties: `RunStore` = `app.runs`, `RunControlStore` = `app.runControl`, `RunAlertsStore` = `app.runAlerts`, `RunDispatchStore` = `app.runDispatch` | P l.52-57 |
| A store never imports or names a sibling, and wiring is explicit App properties and App-level handlers | P l.46-47 |
| Inputs and routed signals per store | P l.72-79 (the code at `d326d03` governs where it differs: `RunStore` has no `titles`, its nudge signal is `runsNudged`, and `RunDispatchStore` has `active` and no `cardMap` / `projectRoots`) |
| One App handler for `snapshotReplied`: `settleAfterSnapshot()` on `ok`, then `runAlerts.snapshotReplied(…)` | P l.85-86 |
| The shims and handles are gone after the last story | P l.128-130 |
| No behaviour change and no UI change apart from the callers' paths | P l.146-148 |
| `tests/architecture` stays green | P l.105-106 |
| Card: state only what the code does; follow `docs/architecture.md` layering; docstrings and comments state the contract only | card description |

### Out of scope

- Any `.qml`, `.js` or `.py` change outside `tests/architecture/test_run_store_docs.py`. 5.1 owns the
  callers and 5.2 owns the shims. Both have landed.
- Rewriting the store paragraphs that are already correct (`:84-90`, the bodies of `:93` and `:94`,
  and the dispatch body of `:92`), apart from the edits listed above.
- The parent spec's own text, including its stale "Migration (shims)" section and Appendix A. It is
  a design record, not the architecture doc.
- `README.md` prose, which has nothing to change (see above).
- Sibling story work: the members P l.407-416 lists as not present, the later milestones of
  P l.132-142, and `RunStore`'s `runsNudged` having no App route. The doc states that App routes it
  nowhere and does not propose a route.

### Hand-off to the planner

Follow the writing-plans format in this brief. Suggested tasks:

1. **Task 1** writes `tests/architecture/test_run_store_docs.py` with the helpers and their unit
   test (11), then runs it and expects 1-9 to fail and 10-11 to pass.
2. **Task 2** edits the `core/stores/` list of `docs/architecture.md` (changes 1-5) until tests 1-6
   and 8 pass.
3. **Task 3** edits `:155`, `:167` and `:169` (changes 6-8) until 7 and 9 pass, then runs
   `bash tests/run.sh`.

The plan's code blocks show the full test file and the exact replacement sentences, quoted from the
code facts above.
<!-- task-pipeline: validated -->
