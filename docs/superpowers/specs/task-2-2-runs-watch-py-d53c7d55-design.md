# Task 2.2: runs-watch.py, change signals only (card d53c7d55)

Parent story: 92b4d150 "Run backend helpers". Milestone design: `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` (runs-watch.py description, Refresh model, Errors table, Testing). Blocked by 2.1 (done). Its files (`core/backend/runs/runs-snapshot.py`, `tests/core/backend/runs/test_runs_snapshot.py`) are present in this tree; both directories already exist. Do not modify them. Mirror runs-snapshot.py's conventions (argv-list `am`, `AmMissing` via `shutil.which`, `HelperError` type, failure lines through `emit`).

## Scope

In scope:
- `core/backend/runs/runs-watch.py` (new)
- `tests/core/backend/runs/test_runs_watch.py` (new)

Out of scope: `runs-snapshot.py` (2.1), `runs-logs.py` (2.3), `tests/contract/test_am_shapes.py` (2.4), RunStore.qml, runs.js, any UI, and any `docs/architecture.md` edits.

## Conventions

- Shebang `#!/usr/bin/env python3`. Add a module docstring that states the usage and the output lines.
- Imports are limited to the stdlib plus `core/backend/common`. Reach `common` through `sys.path.insert(0, <parent dir>)`, following `core/backend/documents/list-docs.py`. Every line printed to stdout goes through `from common.json_line import emit`. `emit` does not flush, so call `sys.stdout.flush()` after every `emit` (stdout is a pipe and block-buffered). Do not write a local copy of `emit`, `inside`, `write_atomic`, `split_frontmatter` or `frontmatter_of`, because `tests/architecture/test_layers.py` must still pass unchanged.
- Use only the `am` command and its schema-1 journal contract. Never read am's SQLite or on-disk layout.
- Start `am` with an argv list (`["am", "watch", "--all", "--follow"]`), not through a shell. Resolve `am` from PATH.

## Interface

`runs-watch.py <project-root> [run-id ...]`

This matches 2.1's `<project root>` first-argument convention. With zero run ids the helper is still valid: it watches only for new runs in this project. The helper is long-lived and writes one JSON line per output event to stdout, flushing after each line.

## Observable behavior

1. **Start time.** Record the helper's own start time in UTC before spawning `am`.
2. **Hello line.** The first stream line is `{"am":..,"event":"watch","runs_dir":..,"schema":1}`. Drop it. If `schema != 1`, emit `{"ok":false,"error":{"type":"SchemaMismatch","message":...}}`, terminate `am`, and exit non-zero.
3. **Backlog drop.** Parse each journal line's `ts` (ISO 8601 UTC) and drop the line when `ts` is earlier than the start time. A missing or unparseable `ts` is not provably backlog, so keep the line. Keep this check in one small, clearly named function or block so it can be deleted when `am watch --from-now` lands (S4).
4. **Filter.** Keep a journal line only if one of these holds:
   - its `run_id` is in the watched set, which starts as the argv run ids; or
   - it is a `run_upsert` whose `payload.repo_dir` equals the project root. Compare normalized absolute paths. That run_id is added to the watched set from then on.
   
   Ignore unknown `event` values, extra payload keys and lines that are not JSON. Do not crash on any of them.
5. **Debounce.** Collect the run ids of kept events into a de-duplicated batch. Trailing-edge window: the first kept event into an empty batch starts a 250 ms timer, and when it expires emit exactly one `{"changed":["<run-id>",...]}` line and clear the batch (the next kept event starts a new window). Never emit more than one `changed` line per 250 ms, and never emit an empty one. Emit only run ids, never event contents. Ordering within the list is not part of the contract.
6. **Clean end.** When `am` exits 0 (Ctrl-C or a closed pipe), flush any pending batch and exit 0. On SIGINT, SIGTERM or a broken stdout pipe, terminate the `am` child and exit 0 without a traceback.

## Error paths

| Condition | Output | Exit |
|---|---|---|
| `am` prints a refusal envelope (a line with an `"ok"` key) before the stream | emit `{"ok":false,"error":{"type":"CorruptJournal",...}}` if `am` exits 3 (message from the envelope's error), otherwise re-emit the envelope unchanged, as 2.1 does | non-zero |
| `am` exits 3 mid-stream (stderr `am watch: <msg>`) | flush the pending batch, then emit `{"ok":false,"error":{"type":"CorruptJournal","message":<stderr msg>}}` | non-zero |
| hello `schema != 1` | `{"ok":false,"error":{"type":"SchemaMismatch",...}}` | non-zero |
| `am` exits with any code other than 0 or 3 mid-stream | flush the pending batch, then `{"ok":false,"error":{"type":"HelperError","message":<stderr or exit code>}}` | non-zero |
| `am` not on PATH (optional, mirrors 2.1) | `{"ok":false,"error":{"type":"AmMissing",...}}` | non-zero |

Falling back to polling after a watcher failure is the store's job, not this helper's.

## Tests (TDD: write these first)

All tests live in `tests/core/backend/runs/test_runs_watch.py`, the **backend pytest tier** (`tests/core/backend/<domain>/`, run by the pytest step of `bash tests/run.sh`). This follows the architecture.md "Tests" rule and the spec's Testing section ("stub `am` with recorded fixtures … backlog dropping in `runs-watch.py`, project filtering"). None of these tests go in the contract, architecture, ui or QML tiers.

The tests are hermetic and follow `tests/core/backend/milestones/test_run_setup_milestone.py`. A fake `am` Python script is written to a temp dir, and that dir is prepended to PATH. HOME and XDG_* are pointed at temp. The helper is run with `subprocess` and `sys.executable`, using a path computed from `__file__`. The fake `am` prints a hello line, then fixture journal lines with `ts` set relative to now (past means backlog, future or now means live), then exits with a configurable code and stderr message.

1. `test_drops_hello_and_backlog`: past-`ts` events for a watched run produce no `changed` output.
2. `test_live_event_for_watched_run_emits_changed`: a live event for an argv run id produces `{"changed":[id]}`.
3. `test_filters_unwatched_runs`: live events for other run ids produce no output.
4. `test_new_run_upsert_in_project_is_adopted`: a live `run_upsert` whose `payload.repo_dir` equals the root emits that id, and a later event for that id is also kept. A `run_upsert` for a different repo_dir is ignored.
5. `test_ignores_unknown_events_and_keys`: unknown `event` values and extra payload keys do not crash the helper.
6. `test_schema_mismatch`: a hello line with `schema: 2` produces `SchemaMismatch` and a non-zero exit.
7. `test_exit_3_corrupt_journal`: the fake `am` exits 3 with `am watch: ...` on stderr. Output is `CorruptJournal` with a non-zero exit.
8. `test_debounce_batches_and_dedupes`: a burst of events for two run ids, including repeats, sent within one window yields a single `changed` line containing each id once.
9. `test_debounce_separate_windows`: two events separated by more than 250 ms (the fake `am` sleeps between them) yield two `changed` lines.
10. `test_clean_exit_zero`: when the fake `am` exits 0, the helper exits 0.

Optional, only if AmMissing is implemented: 11. `test_am_missing`, which runs with PATH set to an empty temp dir and expects `AmMissing`.

`bash tests/run.sh` must pass, and `tests/architecture` must pass unchanged.
