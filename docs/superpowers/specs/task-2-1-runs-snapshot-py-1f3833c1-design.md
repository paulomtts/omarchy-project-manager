# 2.1 runs-snapshot.py: list runs and their status (card 1f3833c1)

Parent story: 92b4d150 "Run backend helpers". Milestone design: `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` (the "monitor spec" below). This document narrows that design to one helper and its tests.

## Scope

In scope:
- `core/backend/runs/runs-snapshot.py`, a new file in a new directory.
- `tests/core/backend/runs/test_runs_snapshot.py`, a new file in a new directory.

Out of scope, because these belong to sibling cards or later stories: `runs-watch.py` (2.2), `runs-logs.py` (2.3), `tests/contract/test_am_shapes.py` (2.4), `core/domain/runs.js` and its `normalizeRun`, `RunStore.qml`, any UI or navigation, timers, polling, debounce, and the journal. This card adds no `docs/architecture.md` changes beyond, at most, one line that names the new `core/backend/runs/` directory.

## Constraints

- Imports are limited to the Python stdlib and `core/backend/common` (`docs/architecture.md` layering). Use the header idiom from `core/backend/documents/list-docs.py`: insert the parent directory into `sys.path`, then `from common.json_line import emit  # noqa: E402`. Add a docstring that gives the usage and the output shape.
- Do not redefine `emit`, `inside`, `write_atomic`, `split_frontmatter` or `frontmatter_of`. `tests/architecture/test_layers.py` and `tests/architecture/test_icon_glyphs.py` must pass unchanged.
- Use only `am` commands. Never read am's SQLite or its on-disk layout.
- Every subprocess call uses an argv list and never a shell. Resolve `am` with `shutil.which("am")`.
- The helper is a one-shot process. It has no timers, no polling and no loops waiting on am.

## Observable behaviour

Invocation: `runs-snapshot.py <project root>`. If the argument count is wrong, the helper prints `{ok:false, error:{type:"Usage", message:<usage>}}` and exits 2.

1. Run `am runs --repo-dir R`. On success, am returns `{"ok":true,"data":{"runs":[...]}}`. The runs are ordered newest first, and each summary has `id, workflow, repo_dir, base_branch, branch_prefix, status, started_at`.
2. Select runs from that list, keeping am's order:
   - every non-terminal run;
   - the first 10 terminal runs, which are the latest 10.
   - Terminal statuses are exactly `done`, `escalated`, `stopped` and `cancelled`, taken from the monitor spec's "Data sources" finished list. `stopped` counts as terminal even though the domain table also calls it "parked" or resumable. A test pins this.
   - Terminal runs after the tenth are left out of the output.
3. For each selected run, in order, run `am status <id> --repo-dir R` and take its `data` object.
4. Print one line: `{"ok":true, "runs":[{...summary fields..., "status":<am status data>}], "data_dir":<path>}` and exit 0.
   - The output follows the card's shape literally, so the `status` key holds the `am status` data object and replaces the summary's status string. The run's state can still be read from that object's run section.
   - The helper does no other normalisation.
5. No runs gives `{ok:true, runs:[], data_dir:...}`. This is an empty state, not an error.

`data_dir` decision (open in the card): the value is the `XDG_DATA_HOME` in effect. If `XDG_DATA_HOME` is set and absolute, use it. Otherwise use `~/.local/share`, mirroring `state_home()` in `run-setup-milestone.py`. Do not append an am subdirectory, because that would assume am's on-disk layout, which is a spec non-goal. am does not report this path itself (`am runs` returns only `{"runs":[]}`), so the helper derives it from the environment.

## Error paths

Every path prints exactly one JSON line, including unexpected failure. A `guarded(argv)` wrapper does this, matching `run-setup-milestone.py`.

| Case | Output | Exit |
|---|---|---|
| `am` is not on PATH | `{ok:false, error:{type:"AmMissing", message:...}}` | 1 |
| `am runs` or any `am status` returns an `ok:false` envelope, for example `{"error":{"message":...,"type":"UnknownRunError"},"ok":false}` with exit 3 | that envelope, re-emitted unchanged, with no `data_dir` added | 1 |
| am prints output that is not JSON or not a JSON object, or an `ok:true` envelope whose `data` lacks the expected shape (`data.runs` not a list, a run without `id`/`status`, or `am status` data not an object) | `{ok:false, error:{type:"AmBadOutput", message:...}}` | 1 |
| any other exception | `{ok:false, error:{type:"HelperError", message:<reason>}}` | 1 |

The `ok` field of the envelope decides success, not am's exit code: real `am runs` returns exit 0 with `ok:false` for a `RepoDirError`, and that is re-emitted like any other error envelope. A non-zero exit with no parseable envelope is `AmBadOutput`. Each am call has a generous timeout (60 s); expiry is `HelperError`. This is a bound on a one-shot call, not polling.

If any `am status` call fails, the whole snapshot fails. HelperRunner re-snapshots on the next change signal, so the helper does not merge partial results.

## Tests

All of these tests are Python helper behaviour. Under the test-placement rule (`docs/architecture.md` "How to add a helper script" and "Tests", plus the monitor spec's "Testing"), they belong in the pytest tier at `tests/core/backend/runs/test_runs_snapshot.py`.

They do not belong in `tests/contract/`: the real-`am` shape check is card 2.4. They do not belong in the QML tiers either, because this card has no JS, store or UI.

Harness:
- Each test builds a fake `am` executable in `tmp_path/bin`, following the fake-PATH pattern in `tests/core/backend/milestones/test_run_setup_milestone.py`: `PATH = bin + os.pathsep + "/usr/bin" + os.pathsep + "/bin"`. HOME and the XDG dirs are temporary.
- The fake `am` serves hand-written fixtures and appends its argv to a log file, so tests can assert which calls were made. The fixtures are `am runs` data, and `am status` data shaped as the monitor spec describes it: run, the story/subtask/phase/attempt tree, `rows`, `control.lease`, `requests` and `claims`.
- The fixtures and the stub are created inside the test. No files are added under `tests/stubs`.
- The helper is run with `sys.executable` and an argv list. The real `am` and real data are never touched.

Test list (all in the pytest tier, `tests/core/backend/runs/`):
1. `test_no_runs_is_empty_state`: `{ok:true, runs:[], data_dir}`, exit 0, and no `am status` calls.
2. `test_snapshot_shape`: each run keeps the summary fields, `status` equals that run's `am status` data, and stdout is exactly one JSON line.
3. `test_status_fanout_selection`: given non-terminal runs plus more than 10 terminal runs, every non-terminal run is included, only the latest 10 terminal runs are included, am's order is preserved, and the argv log shows exactly those `am status <id> --repo-dir R` calls.
4. `test_terminal_set_pinned`: `done`, `escalated`, `stopped` and `cancelled` are treated as terminal. In particular, `stopped` counts toward the cap of 10 and is not always included. `started` and other statuses are non-terminal.
5. `test_repo_dir_passed`: every am call carries `--repo-dir <project root>`.
6. `test_am_missing`: with a PATH that has no `am`, the output is `{ok:false, error:{type:"AmMissing"}}`.
7. `test_am_error_envelope_passthrough_runs` and `test_am_error_envelope_passthrough_status`: an `UnknownRunError` envelope with exit 3 is re-emitted unchanged, as one line.
8. `test_am_bad_output`: non-JSON output from the stub gives `AmBadOutput` on one line.
9. `test_data_dir`: an absolute `XDG_DATA_HOME` is reported as-is, and an unset or relative value falls back to `$HOME/.local/share`.
10. `test_usage`: no arguments gives `type:"Usage"` and exit 2.

Verification: run `bash ./tests/run.sh`. The suite passes, including the unchanged architecture tests.
