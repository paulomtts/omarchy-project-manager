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
