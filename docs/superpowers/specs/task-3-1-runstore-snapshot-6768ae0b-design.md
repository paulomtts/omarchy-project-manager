# 3.1 RunStore: snapshot, selection, amStatus (card 6768ae0b)

Parent story 779eb1bf "RunStore", milestone 4bf4fb2f. This narrows `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` (Refresh model step 1, and the error table) to this one subtask. It is blocked by 92b4d150 (Run backend helpers), which is done.

## Scope

New files:
- `core/stores/RunStore.qml`: a `Scope`, shaped like `MilestoneStore.qml`.
- `tests/core/stores/tst_run_store.qml`: written first (TDD).

Imports allowed in the store: `QtQml`, `Quickshell`, `Quickshell.Io`, and `import "../domain/runs.js" as Runs`. Nothing else: no QtQuick*, `qs.*`, `ui/`, `vendor/`, sibling stores (never BoardStore), and no other directories.

Prerequisites: `core/domain/runs.js` (with `normalizeRun` and `errorText`) and `core/backend/runs/runs-snapshot.py` must exist in the tree being worked in. Both are present in this worktree. If they are missing, stop and report it. Do not recreate them here. The tests never execute the script.

Not touched: `core/stores/App.qml` and `docs/architecture.md` (both belong to 3.3), any UI, the repo root, and `tests/architecture`.

Out of scope:
- 3.2: the runs-watch Process, `active`, `watching`, the debounce, liveness, `stale`, setting `amStatus` to `schema` from the watch hello line, and the 5 s poll fallback.
- 3.3: composing the store into App.
- The attempt-logs HelperRunner.
- All 4.x and 5.x work.

## Public surface

| Property | Type | Meaning |
|---|---|---|
| `project` | string | Project root path. Set from outside. |
| `backendDir` | string | Ends with `/`, for example `/plugin/core/backend/`. |
| `runs` | var (array) | Runs normalized by `Runs.normalizeRun`. Starts as `[]`. |
| `selectedRunId` | string | Starts as `""`. |
| `amStatus` | string | One of `ok`, `missing`, `schema`, `error`. Starts as `ok`. |
| `lastError` | string | Starts as `""`. |
| `snapshotRunner` | HelperRunner child | Exposed so tests can reach `snapshotRunner.current`. The script is `backendDir + "runs/runs-snapshot.py"`. Its `guard` is bound to `project`. |
| `refresh()` | function | Starts a snapshot for the current project. |

## Observable behavior

- **refresh():** if `project` is empty, it does nothing. Otherwise it calls `snapshotRunner.run([project])`, so the argv is `["python3", backendDir + "runs/runs-snapshot.py", project]`. A newer refresh replaces an older one (HelperRunner's latest-wins behavior). A result is dropped if its guard no longer equals `project`.
- **On project change:**
  1. Set `runs` to `[]`, `selectedRunId` to `""` and `lastError` to `""`.
  2. Set `amStatus` to `ok`.
  3. If the new project is not empty, call `refresh()`.

  The panel-open trigger belongs to whoever composes the store (3.3), which calls `refresh()`.
- **Parsing `finished(stdout, exitCode, launchedGuard)`:** take the last non-empty line of stdout and parse it as JSON.
  - **`ok:true`:** each entry in `runs` holds the `am runs` summary fields plus a `status` field containing `am status` data. Map each entry with `Runs.normalizeRun({ row: <entry without its status key>, status: entry.status })`. Removing `status` from `row` is required, because the snapshot overwrote the summary's status string with the status object. Then set `runs` to the mapped list, `amStatus` to `ok` and `lastError` to `""`. A missing or empty `runs` array (no runs, or no data dir) is ok with `runs = []`, and is not an error. A `runs` value that is not an array counts as empty. Entries that are not objects are skipped, so the store never throws. The reply's `data_dir` field is ignored in 3.1: it is not stored or exposed (the footer that shows it belongs to the UI subtasks).
  - **`ok:false` with `error.type === "AmMissing"`:** set `amStatus` to `missing`, set `runs` to `[]` (the spec says the UI shows no badges in this state), and set `lastError` to `Runs.errorText(envelope)`.
  - **`ok:false` with any other type** (AmBadOutput, Usage, HelperError, or a re-emitted am error): keep the previous `runs`, set `amStatus` to `error`, and set `lastError` to `Runs.errorText(envelope)`.
  - **Unparseable or empty stdout, or a non-object result:** treat it like `ok:false`. Keep the previous `runs`, set `amStatus` to `error`, and set `lastError` to a non-empty message that includes the exit code. The store never throws.
- **Selection:** `selectedRunId` is plain state that the UI sets. A project switch clears it. A refresh within the same project leaves it unchanged.
- **The `schema` value:** it is declared in the enum, but no 3.1 path produces it. 3.2 sets it from the watch hello line.

## Tests

All tests below go in `tests/core/stores/tst_run_store.qml`. Store behavior belongs in headless store tests that drive stubbed Process objects and assert on properties, per docs/architecture.md "Tests".

Tests set `project` after creating the store, not through `createObject` properties, because the project-change handler does not fire for an initial value. Because the stub `Process` has no real lifecycle, a test that needs a late exit of an older process must capture `store.snapshotRunner.current` before the next `refresh()` or project switch.

The test creates the store directly with `Qt.createComponent("../../../core/stores/RunStore.qml")`, because App does not compose it until 3.3. It passes `backendDir: "/plugin/core/backend/"`. It fakes replies with `store.snapshotRunner.current.outText = '<json>'; store.snapshotRunner.current.exited(code)`.

1. **Defaults:** `runs` is `[]`, `selectedRunId` is `""`, `amStatus` is `ok`, `lastError` is `""`, and no process runs while there is no project.
2. **Setting `project` starts a snapshot:** the argv equals `["python3", "/plugin/core/backend/runs/runs-snapshot.py", "/home/u/my proj"]`. The path contains a space, and it is passed as one argument.
3. **An `ok:true` reply fills `runs` with normalized runs:**
   - `id`, `status` and `lease` come from the nested `status` data.
   - `status` is not `"[object Object]"`.
   - `amStatus` is `ok` and `lastError` is empty.
4. **`ok:true` with `runs: []`, or with `runs` absent:** `runs` is `[]` and `amStatus` is `ok`.
5. **Refresh sequencing:** two `refresh()` calls in a row, then a late exit of the first process. Only the second reply is applied.
6. **AmMissing:** `amStatus` is `missing`, `runs` is cleared, and `lastError` equals `"AmMissing: am is not installed."`.
7. **`ok:false` of another type after a good snapshot** (for example AmBadOutput, exit 1): the previous `runs` are kept, `amStatus` is `error`, and `lastError` equals `"AmBadOutput: <message>"`.
8. **Garbage stdout after a good snapshot:** the previous `runs` are kept, `amStatus` is `error`, `lastError` is non-empty, and there is no TypeError.
9. **A good reply after an error restores the ok state:** `amStatus` returns to `ok` and `lastError` returns to `""`.
10. **Project switch:**
    - Set project A, load runs, and set `selectedRunId`. Then switch to B.
    - Immediately after the switch: `runs` is `[]`, `selectedRunId` is `""`, and a new snapshot for B was launched.
    - A late exit from A's process changes nothing.
    - B's reply is applied.
11. **Clearing `project` to `""`:** `runs` and the selection are cleared, and no snapshot is launched.

Verification: `bash tests/run.sh run_store` while iterating, then the full `bash ./tests/run.sh`. The full run includes `tests/architecture`, which must stay green and needs no changes.
