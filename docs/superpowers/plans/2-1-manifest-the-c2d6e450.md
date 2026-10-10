# 2.1 manifest: the service entry point (card c2d6e450)

Narrowed from `docs/superpowers/specs/2026-10-05-alerts-panel-closed-design.md` (below "the
parent"): fact 3, how the shell creates a `service` (lines 42-52); fact 5, `activation` is read
by nothing (lines 58-60); Decision, the manifest shape (lines 76-78); Architecture, the
`RunAlertsService.qml` bullet (lines 148-150) and the docs bullet (lines 163-164); Testing, the
`tst_run_alerts_service.qml` file name (line 202), the manifest test (line 208) and the live
check (line 210). Parent story bd7304ee ("Alerts service"). Not blocked.

This card lands the **shape only**: the manifest declares the service, the service file exists,
loads, and knows where the backend lives. It does nothing else.

## Starting point

- `manifest.json` (repo root): `"kinds": ["bar-widget"]`, `"entryPoints": {"barWidget":
  "ui/Panel.qml"}`, `"activation": "on-demand"`, plus `barWidget` metadata.
- `core/stores/RunAlertsService.qml` does not exist.
- `ui/Panel.qml:40-45` derives the plugin root from its own URL:
  `Qt.resolvedUrl("../").toString().replace(/^file:\/\//, "")`, and hands
  `pluginDir + "core/backend/"` to `App` as `backendDir`. Every store names that property
  `backendDir` with the comment `// <plugin>/core/backend/` (`RunAlertsStore.qml:21`).
- The shell (`/usr/share/omarchy/shell/shell.qml:892-942`, `ensureService`) loads
  `entryPoints.service` with `Qt.createComponent(url)` and `createObject(null)` for a
  third-party plugin (no parent), then sets `shell`, `manifest`, `omarchyPath`,
  `barWidgetRegistry`, `pluginRegistry` **only if the object declares them** (`"x" in inst`).
  `PluginRegistry.entryPointUrl` (`services/PluginRegistry.qml:118-133`) resolves the entry
  point against the plugin's source dir; `validateManifest` (lines 43-75) needs a non-empty
  `kinds` array and an `entryPoints` object. Precedent for a combined manifest:
  `/usr/share/omarchy/shell/plugins/services/media/manifest.json`.
- No pytest reads `manifest.json` today; `tests/ui/tst_plugin_dir.qml` only checks it exists.
- `tests/run.sh` runs pytest over `tests/`, then every `tests/**/tst_*.qml` with
  `qmltestrunner` (offscreen) against a temp mirror of the repo, failing on `TypeError`,
  `ReferenceError`, `non-existent`, `Unable to assign` and similar in the output.

## Constraints

- Layering (`docs/architecture.md:14`, enforced by `tests/architecture/test_layers.py`
  `violations_store`): a file in `core/stores/` imports only `QtQml`, `Quickshell`,
  `Quickshell.Io` and `../domain/*.js`. The parent restates this for this file (line 149).
  `RunAlertsService` is not a shell or Qt Controls type name, so the clash test is unaffected.
  `tests/architecture` must pass unchanged (no allowlist edits).
- Parent line 150: the service is **composed by the shell, not by `App.qml`**. `App.qml` and
  `ui/Panel.qml` are not touched.
- Parent line 150: it **derives `backendDir` from its own URL** (no one hands it in).
- Card: the root object is a non-visual `QtObject`. (A later card that needs child objects may
  change the root type to `Scope`; that is its call, not this card's.)
- Card: docstrings and comments state the contract only, no narrative. TDD: tests first.
- Verification: `bash tests/run.sh` green. Quick loop:
  `uv run --with pytest python3 -m pytest tests/test_manifest.py tests/architecture -q` and
  `bash tests/run.sh tst_run_alerts_service`.

## Behaviour

### The manifest

`manifest.json` after this card:

- `"kinds": ["bar-widget", "service"]` (exactly these two, in this order; parent line 77).
- `"entryPoints": {"barWidget": "ui/Panel.qml", "service": "core/stores/RunAlertsService.qml"}`
  (parent line 78).
- Every other key and value is unchanged: `schemaVersion` 1, `id`
  `paulomtts.omarchy-project-manager`, `name`, `version`, `author`, `license`, `description`,
  `activation` (read by nothing, parent lines 58-60; left as is), `barWidget`. No `keepLoaded`
  (parent lines 219-221 recommend leaving it off).
- The file stays valid JSON.

Observable effect in the shell: the plugin is enabled (it is in the bar layout), so
`_syncServices()` creates one `RunAlertsService` per shell, with no parent, alongside the bar
widgets; it is destroyed with the plugin.

### `core/stores/RunAlertsService.qml`

- Root type `QtObject` (from `QtQml`). Imports `QtQml` only; nothing it does needs more.
- Loads with no error and no warning, and instantiates with **no** properties set and **no**
  parent (`createObject(null)`, as the shell does) or with a test parent.
- Declares none of `shell`, `manifest`, `omarchyPath`, `barWidgetRegistry`,
  `pluginRegistry`, so the shell injects nothing into it. (Declaring one is a later card's
  decision.)
- `readonly property string backendDir`: the absolute filesystem path of the plugin's
  `core/backend/` directory, with a trailing `/` and no `file://` scheme, derived from the
  file's own URL. Since the file sits in `<plugin>/core/stores/`, that is
  `Qt.resolvedUrl("../backend/")` with the `file://` prefix stripped (equivalently
  `Qt.resolvedUrl("../../")` + `core/backend/`, the `ui/Panel.qml` idiom one level deeper).
  The value is the same string `ui/Panel.qml` hands `App` as `backendDir` for the same plugin
  directory. Being `readonly`, it cannot be assigned from outside.
- Nothing else: no `Process`, no `Timer`, no helper launched, no file read, no signal, no
  `console` output. Creating and destroying it has no side effect.
- Header comment (leading `//` block, like `RunAlertsStore.qml`): states the contract — the
  plugin's `service` entry point, created once by the shell (not by `App`), and what
  `backendDir` is. No history, no "TODO".

### Docs

- `docs/architecture.md:18-19`: the sentence "`ui/Panel.qml` is the manifest entry point"
  becomes: `ui/Panel.qml` is the manifest's `barWidget` entry point and
  `core/stores/RunAlertsService.qml` its `service` entry point (parent lines 163-164).
- `docs/architecture.md`, the `core/stores` list: one bullet
  `- `RunAlertsService.qml` …` saying it is the `service` entry point, created once per shell by
  the shell and the one store `App.qml` does not compose, and that it derives `backendDir` from
  its own URL. Place it after the `RunDispatchStore.qml` bullet (it must not sit between the
  four run-store bullets: `tests/architecture/test_run_store_docs.py` requires those in order,
  one each) and do not name `RunStore`, `app.runAlerts` or any token that test rejects.
- `README.md:284` (the layout block): add the line
  `                       entryPoints.service   -> core/stores/RunAlertsService.qml` under the
  `manifest.json` line (aligned with it). `test_the_readme_names_no_run_store` must still pass.

## Error paths

- A wrong `backendDir` (the folder the file sits in, `core/stores/`, or the plugin root without
  `core/backend/`) is the realistic bug; the store test checks the suffix **and** that a known
  helper exists under it in the mirrored tree.
- A manifest edit that breaks JSON or drops a key would disable the whole plugin in the shell;
  the manifest test parses the file and pins every unchanged key.
- An entry point path with a typo loads nothing at runtime and no other test notices; the
  manifest test checks both entry point files exist relative to the repo root.

## Tests

| # | test | file | tier | why this tier |
|---|---|---|---|---|
| 1 | `test_kinds_are_bar_widget_and_service` — `json.load(manifest.json)["kinds"] == ["bar-widget", "service"]` | `tests/test_manifest.py` (new; `REPO` derived as in `tests/test_install.py:10`) | pytest (unit, file read) | a static file's content; no QML needed |
| 2 | `test_entry_points` — `entryPoints == {"barWidget": "ui/Panel.qml", "service": "core/stores/RunAlertsService.qml"}` | `tests/test_manifest.py` | pytest | same |
| 3 | `test_every_entry_point_is_a_file_in_the_repo` — for each value in `entryPoints`: relative, no `..` segment, and `os.path.isfile(REPO/value)` | `tests/test_manifest.py` | pytest | the shell refuses a path outside the plugin dir (`entryPointUrl`) and silently loads nothing for a missing one |
| 4 | `test_other_keys_unchanged` — `schemaVersion == 1`, `id == "paulomtts.omarchy-project-manager"`, `activation == "on-demand"`, `barWidget.allowMultiple is False`, no `keepLoaded` key | `tests/test_manifest.py` | pytest | guards the rest of the manifest against the edit |
| 5 | `test_it_loads_and_instantiates_without_a_parent_or_properties` — `Qt.createComponent("../../../core/stores/RunAlertsService.qml")` is `Component.Ready`; `createObject(null)` is non-null; destroy it | `tests/core/stores/tst_run_alerts_service.qml` (new, the name the parent fixes at line 202) | QML store test (headless, qmltestrunner) | proves the file parses and builds exactly as `ensureService` builds it, with no shell |
| 6 | `test_backend_dir_is_the_absolute_core_backend_of_the_plugin` — instance `backendDir` starts with `/`, does not contain `file:`, ends with `/core/backend/`, and `runs/runs-alerts.py` exists under it (directory listing via `FolderListModel`, as `tests/ui/tst_plugin_dir.qml:24-41` does) | `tests/core/stores/tst_run_alerts_service.qml` | QML store test | only the QML engine resolves the file's own URL; existence catches an off-by-one directory |
| 7 | `test_the_shell_injects_nothing` — `"shell" in s`, `"manifest" in s`, `"omarchyPath" in s`, `"pluginRegistry" in s`, `"barWidgetRegistry" in s` are all false (no assignment to `backendDir` is attempted: a caught `TypeError` line would trip `tests/run.sh`'s output grep) | `tests/core/stores/tst_run_alerts_service.qml` | QML store test | pins the injection contract with the shell for this card |
| 8 | `tests/architecture` passes unchanged (layer allowlist covers the new store; README/doc tests still pass) | existing | pytest | enforced by the gate |
| 9 | Manual: `bash tests/live-check.sh` reports `live check ok` and `journalctl --user -t omarchy-shell --since -1min` has no `service plugin load failed for paulomtts.omarchy-project-manager` / `createObject returned null` line | — | live (real shell) | only the real shell exercises `ensureService`; needs a desktop session and the installed plugin to point at this tree. If unavailable in the agent environment, the card's result says so. |

`bash tests/run.sh` must be green with all of the above; its QML pass also fails on any
`TypeError`/`ReferenceError`/`non-existent` line, which covers a load warning from the new file.

## Out of scope

- Running `runs-alerts.py`, the `Process`, restart policy, `status`, `lastError`,
  `alertReceived` (card 2.2, f08d6600).
- Reading `get-global-settings`, the run snapshot, `notify.py` launches (card 2.3, 8a6996cc).
- `RunAlertsStore` dropping `notify.py` (card 2.4, e9513ddf).
- The persisted cursor, dismissal, `store_id` (later milestone cards).
- `ui/screens/RunsScreen.qml` switch label/caption; `install.sh` (already enables the plugin
  through the bar layout, parent line 51-52); `keepLoaded`; the `activation` key.
- Any change to `App.qml`, `ui/Panel.qml` or another store.

---

# 2.1 manifest: the service entry point — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Declare a `service` entry point in `manifest.json` and add `core/stores/RunAlertsService.qml`, a non-visual `QtObject` that loads with no parent and knows where `core/backend/` is, plus the docs that name it.

**Architecture:** The manifest gains `"service"` in `kinds` and `entryPoints.service`; the shell's `ensureService` then creates one `RunAlertsService` per shell with `createObject(null)`. The service derives `backendDir` from its own URL (`Qt.resolvedUrl("../backend/")`, `file://` stripped) and does nothing else. `App.qml` and `ui/Panel.qml` are not touched.

**Tech Stack:** QML (`QtQml` only in the store), Qt Test via `qmltestrunner` (`tests/run.sh`), pytest via `uv run --with pytest`.

**Spec:** `docs/superpowers/specs/2-1-manifest-the-c2d6e450.md` (prepended below).

## Global Constraints

- `core/stores/*.qml` imports only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain/*.js`; `RunAlertsService.qml` imports `QtQml` only.
- `tests/architecture` must pass unchanged (no allowlist edits).
- The service is composed by the shell, not by `App.qml`; `App.qml` and `ui/Panel.qml` are not touched, nor any other store.
- It derives `backendDir` from its own URL (no one hands it in); `readonly property string backendDir`.
- Root object is a non-visual `QtObject`.
- Declares none of `shell`, `manifest`, `omarchyPath`, `barWidgetRegistry`, `pluginRegistry`.
- No `Process`, no `Timer`, no helper, no file read, no signal, no `console` output.
- Docstrings and comments state the contract only, no narrative, no "TODO". TDD: tests first.
- `manifest.json`: `"kinds": ["bar-widget", "service"]`; `"entryPoints": {"barWidget": "ui/Panel.qml", "service": "core/stores/RunAlertsService.qml"}`; every other key unchanged; no `keepLoaded`; valid JSON.
- Verification: `bash tests/run.sh` green. Quick loop: `uv run --with pytest python3 -m pytest tests/test_manifest.py tests/architecture -q` and `bash tests/run.sh tst_run_alerts_service`.

## Review Focus

1. **Plugin disabled and re-enabled in one shell session** (the shell destroys the parentless service and later creates a new one): a second `createObject(null)` after `destroy()` must build cleanly with the same `backendDir`. Pinned by `test_it_can_be_created_again_after_it_was_destroyed` (Task 2).
2. **The service and the panel disagreeing on where the backend is** (e.g. one keeps a trailing slash or a `file://` the other strips, or a path with characters `Qt.resolvedUrl` encodes): the service's `backendDir` must be the exact string `ui/Panel.qml` hands `App`. Pinned by `test_backend_dir_is_what_the_panel_hands_app` (Task 2).
3. **A manifest edit that silently changes another key** (`name`, `description`, `barWidget.aliases`, …): the shell would show different metadata or refuse the plugin. Pinned by comparing every other key against its full literal value in `test_other_keys_unchanged` (Task 1).
4. **The `in`-operator check proving nothing** (if `"x" in obj` were always false on a QML object, test 7 would pass vacuously): a positive control `"backendDir" in s` is asserted beside the negatives in `test_the_shell_injects_nothing` (Task 2).
5. **An entry point written as a URL or with a Windows separator** (`file:///…`, `core\\stores\\…`): the shell resolves it against the plugin dir and finds nothing. `test_every_entry_point_is_a_file_in_the_repo` (Task 1) rejects absolute paths, `..` segments, a `:` scheme and backslashes before checking the file exists.

---

## File Structure

- Create `tests/test_manifest.py` — pytest, reads `manifest.json` and pins its shape.
- Modify `manifest.json` — `kinds` and `entryPoints` only.
- Create `core/stores/RunAlertsService.qml` — the service entry point: a `QtObject` with `backendDir`.
- Create `tests/core/stores/tst_run_alerts_service.qml` — QML store test (load, `backendDir`, injection contract).
- Modify `docs/architecture.md:18-19` and insert a bullet after line 93 (the `RunDispatchStore.qml` bullet).
- Modify `README.md:284` — layout block, one line under `manifest.json`.

Note on Task 1 ordering: `test_every_entry_point_is_a_file_in_the_repo` needs `core/stores/RunAlertsService.qml` to exist, which Task 2 creates. Task 1 therefore expects that one test to keep failing at its end (missing file) and Task 2 turns it green. Every other Task 1 test passes at the end of Task 1.

---

### Task 1: The manifest declares the service

**Files:**
- Create: `tests/test_manifest.py`
- Modify: `manifest.json:9-13`

**Interfaces:**
- Consumes: nothing.
- Produces: `manifest.json` with `entryPoints.service == "core/stores/RunAlertsService.qml"` (the file Task 2 creates).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_manifest.py`:

```python
"""manifest.json: the bar widget and the service entry point, every other key as shipped."""
import json
import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(REPO, "manifest.json")

UNCHANGED = {
    "schemaVersion": 1,
    "id": "paulomtts.omarchy-project-manager",
    "name": "Omarchy Project Manager",
    "version": "1.0.0",
    "author": "paulomtts",
    "license": "MIT",
    "description": "Per-project board, milestone graph, documents and Claude memories for brd projects, right from the bar.",
    "activation": "on-demand",
    "barWidget": {
        "displayName": "Project Manager",
        "description": "One bar icon and one panel: pick a project in the sidebar, then browse its board, milestone graph, documents or Claude memories.",
        "category": "Productivity",
        "aliases": ["project manager", "brd", "board", "memories"],
        "allowMultiple": False,
    },
}


def manifest():
    with open(MANIFEST) as f:
        return json.load(f)


def test_kinds_are_bar_widget_and_service():
    assert manifest()["kinds"] == ["bar-widget", "service"]


def test_entry_points():
    assert manifest()["entryPoints"] == {
        "barWidget": "ui/Panel.qml",
        "service": "core/stores/RunAlertsService.qml",
    }


def test_every_entry_point_is_a_file_in_the_repo():
    for kind, path in manifest()["entryPoints"].items():
        assert isinstance(path, str) and path, kind
        assert not os.path.isabs(path), (kind, path)
        assert ":" not in path and "\\" not in path, (kind, path)
        assert ".." not in path.split("/"), (kind, path)
        assert os.path.isfile(os.path.join(REPO, path)), (kind, path)


def test_other_keys_unchanged():
    m = manifest()
    assert m["schemaVersion"] == 1
    assert m["id"] == "paulomtts.omarchy-project-manager"
    assert m["activation"] == "on-demand"
    assert m["barWidget"]["allowMultiple"] is False
    assert "keepLoaded" not in m
    assert {k: v for k, v in m.items() if k not in ("kinds", "entryPoints")} == UNCHANGED
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/test_manifest.py -q`
Expected: 2 failed, 2 passed — FAIL `test_kinds_are_bar_widget_and_service` (`['bar-widget'] != ['bar-widget', 'service']`) and `test_entry_points` (no `service` key); PASS `test_every_entry_point_is_a_file_in_the_repo` (only `barWidget` is listed yet) and `test_other_keys_unchanged` (it pins the current file).

- [ ] **Step 3: Edit the manifest**

In `manifest.json`, replace

```json
  "kinds": ["bar-widget"],
  "activation": "on-demand",
  "entryPoints": {
    "barWidget": "ui/Panel.qml"
  },
```

with

```json
  "kinds": ["bar-widget", "service"],
  "activation": "on-demand",
  "entryPoints": {
    "barWidget": "ui/Panel.qml",
    "service": "core/stores/RunAlertsService.qml"
  },
```

Touch nothing else in the file.

- [ ] **Step 4: Run the tests**

Run: `uv run --with pytest python3 -m pytest tests/test_manifest.py -q`
Expected: `test_kinds_are_bar_widget_and_service`, `test_entry_points`, `test_other_keys_unchanged` PASS; `test_every_entry_point_is_a_file_in_the_repo` FAIL with `('service', 'core/stores/RunAlertsService.qml')` — the file does not exist until Task 2. That is the expected state at the end of this task.

Also run: `python3 -m json.tool manifest.json > /dev/null && echo json ok`
Expected: `json ok`

- [ ] **Step 5: Commit**

```bash
git add tests/test_manifest.py manifest.json
git commit -m "feat(alerts): manifest declares the service entry point core/stores/RunAlertsService.qml"
```

---

### Task 2: `RunAlertsService.qml` loads without a parent and knows `backendDir`

**Files:**
- Create: `tests/core/stores/tst_run_alerts_service.qml`
- Create: `core/stores/RunAlertsService.qml`

**Interfaces:**
- Consumes: `manifest.json` `entryPoints.service` (Task 1) names this file; `ui/Panel.qml`'s `app.backendDir` (existing: `pluginDir + "core/backend/"`).
- Produces: `core/stores/RunAlertsService.qml`, root `QtObject`, one member `readonly property string backendDir` — the absolute path of `<plugin>/core/backend/`, trailing `/`, no `file://`. Later cards (2.2, 2.3) add the process and settings to this file.

- [ ] **Step 1: Write the failing test**

Create `tests/core/stores/tst_run_alerts_service.qml`:

```qml
// tests/core/stores/tst_run_alerts_service.qml
// The service entry point: it builds as the shell's ensureService builds it
// (createObject(null), no properties), declares none of the properties the
// shell injects, and its backendDir is the plugin's real core/backend/.
import QtQuick
import QtTest
import Qt.labs.folderlistmodel

TestCase {
  id: tc
  name: "StoresRunAlertsService"
  when: windowShown
  width: 400; height: 400

  Component { id: hostC; Item { width: 400; height: 400 } }

  // A directory listing is the only filesystem read QML offers here.
  FolderListModel { id: folder; showDirs: true; showFiles: true; showDotAndDotDot: false }

  function fileExists(path) {
    var slash = path.lastIndexOf("/")
    var dir = path.substring(0, slash)
    var name = path.substring(slash + 1)
    folder.folder = "file://" + dir
    // The model loads asynchronously and still lists the previous folder (at
    // first, the working directory) for a while: poll until it lists entries
    // of `dir` itself or the budget runs out.
    for (var t = 0; t < 40; t++) {
      if (folder.status === FolderListModel.Ready && folder.count > 0
          && String(folder.get(0, "filePath")).indexOf(dir + "/") === 0) break
      tc.wait(20)
    }
    for (var i = 0; i < folder.count; i++)
      if (folder.get(i, "fileName") === name) return true
    return false
  }

  // Built exactly as the shell builds a third-party service: no parent, no properties.
  function make() {
    var comp = Qt.createComponent("../../../core/stores/RunAlertsService.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(null)
  }

  function test_it_loads_and_instantiates_without_a_parent_or_properties() {
    var comp = Qt.createComponent("../../../core/stores/RunAlertsService.qml")
    compare(comp.status, Component.Ready, comp.errorString())
    var s = comp.createObject(null)
    verify(s !== null, "createObject(null) returned null")
    s.destroy()
  }

  function test_it_can_be_created_again_after_it_was_destroyed() {
    var a = make(); if (!a) return
    var dir = a.backendDir
    a.destroy()
    wait(0)
    var b = make(); if (!b) return
    compare(b.backendDir, dir)
    b.destroy()
  }

  function test_backend_dir_is_the_absolute_core_backend_of_the_plugin() {
    var s = make(); if (!s) return
    var dir = s.backendDir
    s.destroy()
    verify(dir.indexOf("/") === 0, "not an absolute path: " + dir)
    verify(dir.indexOf("file:") === -1, "still a URL: " + dir)
    verify(dir.endsWith("/core/backend/"), dir)
    verify(fileExists(dir + "runs/runs-alerts.py"), "no runs/runs-alerts.py under " + dir)
  }

  function test_backend_dir_is_what_the_panel_hands_app() {
    var s = make(); if (!s) return
    var dir = s.backendDir
    s.destroy()
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var p = comp.createObject(host)
    verify(p !== null, "Panel did not build")
    compare(dir, p.app.backendDir)
  }

  function test_the_shell_injects_nothing() {
    var s = make(); if (!s) return
    verify("backendDir" in s, "the in-operator sees no declared property")
    verify(!("shell" in s), "declares shell")
    verify(!("manifest" in s), "declares manifest")
    verify(!("omarchyPath" in s), "declares omarchyPath")
    verify(!("pluginRegistry" in s), "declares pluginRegistry")
    verify(!("barWidgetRegistry" in s), "declares barWidgetRegistry")
    s.destroy()
  }
}
```

Do not add a test that assigns `backendDir`: the caught `TypeError` would be printed and `tests/run.sh` fails on any `TypeError` line.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/run.sh tst_run_alerts_service`
Expected: the pytest pass runs first and fails `test_every_entry_point_is_a_file_in_the_repo` (from Task 1), then the QML pass prints `FAIL!  : StoresRunAlertsService::test_it_loads_and_instantiates_without_a_parent_or_properties()` with an error mentioning `RunAlertsService.qml` (no such file), and the other functions FAIL the same way in `make()`. Exit status non-zero.

- [ ] **Step 3: Write the service**

Create `core/stores/RunAlertsService.qml`:

```qml
import QtQml

// The plugin's `service` entry point (manifest.json entryPoints.service). The
// shell creates one per shell, with no parent, while the plugin is enabled,
// and destroys it with the plugin; App does not compose it. `backendDir` is
// the absolute path of <plugin>/core/backend/, with a trailing "/" and no
// file:// scheme, derived from this file's own URL -- the same string
// ui/Panel.qml hands App as backendDir.
QtObject {
  id: service

  readonly property string backendDir: Qt.resolvedUrl("../backend/").toString().replace(/^file:\/\//, "")   // <plugin>/core/backend/
}
```

- [ ] **Step 4: Run the tests**

Run: `bash tests/run.sh tst_run_alerts_service`
Expected: pytest all pass (including `tests/test_manifest.py::test_every_entry_point_is_a_file_in_the_repo`); `== tests/core/stores/tst_run_alerts_service.qml` followed by `Totals: 7 passed, 0 failed` (5 test functions + initTestCase + cleanupTestCase), no `TypeError` / `ReferenceError` / `non-existent` line; exit status 0.

Run: `uv run --with pytest python3 -m pytest tests/test_manifest.py tests/architecture -q`
Expected: all pass (the layer allowlist accepts `import QtQml`; no clash: `RunAlertsService` is not a shell type name).

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunAlertsService.qml tests/core/stores/tst_run_alerts_service.qml
git commit -m "feat(alerts): RunAlertsService, the service entry point, derives backendDir from its own URL"
```

---

### Task 3: Docs name the service entry point

**Files:**
- Modify: `docs/architecture.md:18-19` and insert after line 93
- Modify: `README.md:284`
- Test: existing `tests/architecture/test_run_store_docs.py` (must pass unchanged)

**Interfaces:**
- Consumes: `core/stores/RunAlertsService.qml` and `backendDir` (Task 2); `manifest.json` `entryPoints` (Task 1).
- Produces: nothing code reads.

- [ ] **Step 1: Confirm the doc tests pass before the edit**

Run: `uv run --with pytest python3 -m pytest tests/architecture -q`
Expected: all pass. (No new test: the spec's test table has none for the docs; the existing doc tests are the guard that the edit breaks no rule — the four run-store bullets in order, no `RunStore`/`app.runAlerts`/shim token in README.)

- [ ] **Step 2: Edit the entry-point sentence in `docs/architecture.md`**

Replace lines 18-19:

```markdown
Repo root holds no `.qml`/`.js`/`.py` except `install.sh`. `ui/Panel.qml` is the
manifest entry point.
```

with:

```markdown
Repo root holds no `.qml`/`.js`/`.py` except `install.sh`. `ui/Panel.qml` is the
manifest's `barWidget` entry point and `core/stores/RunAlertsService.qml` its
`service` entry point.
```

- [ ] **Step 3: Add the store bullet in `docs/architecture.md`**

Directly after the line beginning `` - `RunDispatchStore.qml` the dispatch (S3 3.1) `` (the last line of the `core/stores` list, before the paragraph beginning `` Other `ui/` pieces: ``), insert this one line:

```markdown
- `RunAlertsService.qml` the manifest's `service` entry point: the shell creates one per shell, with no parent, while the plugin is enabled, and destroys it with the plugin; it is the one store `App.qml` does not compose. It derives `backendDir` (`<plugin>/core/backend/`, absolute, trailing `/`) from its own URL, the same string `ui/Panel.qml` hands `App`, and declares none of the properties the shell injects.
```

The line must not contain `RunStore`, `app.runAlerts`, `shim`, `controlStore`, `alertsStore` or `dispatchStore`.

- [ ] **Step 4: Edit the README layout block**

In `README.md`, replace the line

```
manifest.json          entryPoints.barWidget -> ui/Panel.qml
```

with the two lines

```
manifest.json          entryPoints.barWidget -> ui/Panel.qml
                       entryPoints.service   -> core/stores/RunAlertsService.qml
```

(23 spaces before `entryPoints.service`, so it lines up under `entryPoints.barWidget`; three spaces after `service` so both `->` align.)

- [ ] **Step 5: Run the doc tests and check the edits**

Run: `uv run --with pytest python3 -m pytest tests/architecture -q`
Expected: all pass.

Run: `grep -n "RunAlertsService" docs/architecture.md README.md`
Expected: three hits — `docs/architecture.md:19` (the entry-point sentence), `docs/architecture.md:95` (the new bullet, right after the `RunDispatchStore.qml` bullet) and `README.md:285`.

- [ ] **Step 6: Full gate**

Run: `bash tests/run.sh`
Expected: pytest all pass; every QML file prints `Totals: N passed, 0 failed`; no `TypeError`/`ReferenceError`/`non-existent`/`Unable to assign` line; exit status 0.

- [ ] **Step 7: Live check (manual; needs a desktop session)**

Run: `bash tests/live-check.sh` then `journalctl --user -t omarchy-shell --since -1min | grep -E "service plugin load failed for paulomtts.omarchy-project-manager|createObject returned null" || echo "no service load error"`
Expected: `live check ok` and `no service load error`. This needs a running omarchy shell whose installed plugin points at this tree; if that is not available in the agent environment, say so in the card's result instead of claiming it passed.

- [ ] **Step 8: Commit**

```bash
git add docs/architecture.md README.md
git commit -m "docs(alerts): RunAlertsService is the manifest's service entry point"
```
<!-- task-pipeline: validated -->
