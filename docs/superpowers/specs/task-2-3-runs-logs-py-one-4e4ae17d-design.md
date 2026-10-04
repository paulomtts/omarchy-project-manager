# Task 2.3: runs-logs.py, one attempt's output snapshot (card 4e4ae17d)

Parent story: 92b4d150 "Run backend helpers". Milestone design: `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` (Data sources table row "attempt output | `am logs RUN CARD --phase P --attempt N` | whole-file snapshot", the helper list entry "`runs-logs.py` — `am logs` passthrough for one attempt", Errors table, Testing). Blocked by 2.2 (done). The files from 2.1 and 2.2 (`core/backend/runs/runs-snapshot.py`, `runs-watch.py`, `tests/core/backend/runs/test_runs_snapshot.py`, `test_runs_watch.py`) are already present in this worktree, so both directories exist. Do not modify those files. Mirror runs-snapshot.py's conventions: an argv-list `am`, `AmMissing` via `shutil.which`, `AmBadOutput` for non-envelope output, a `guarded()` catch-all that emits `HelperError`, and every line printed through `emit`.

## Scope

In scope:
- `core/backend/runs/runs-logs.py` (new)
- `tests/core/backend/runs/test_runs_logs.py` (new)

Out of scope: runs-snapshot.py (2.1), runs-watch.py (2.2), `tests/contract/test_am_shapes.py` (2.4, which does not pin `logs`), RunStore.qml, runs.js, any UI, and the 200-line tail limit, which belongs to the store/UI. Also out of scope: any `docs/architecture.md` edit, which is left to the story.

## Conventions

- Shebang `#!/usr/bin/env python3`. Write a module docstring that gives the argv and every output path and exit code.
- Use the stdlib plus `core/backend/common` only. Add `sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))`, then `from common.json_line import emit  # noqa: E402`. Do not write a local copy of `emit`, `inside`, `write_atomic`, `split_frontmatter` or `frontmatter_of`. `tests/architecture/test_layers.py` must pass unchanged.
- Use only the documented `am logs` command. Never read am's SQLite, its on-disk layout or brd.
- Start `am` as an argv list with no shell: `subprocess.run([am, "logs", RUN, CARD, "--phase", PHASE, "--attempt", ATTEMPT], capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=60)`. Here `am` is the path that `shutil.which("am")` returns.

## Interface

`runs-logs.py RUN CARD PHASE ATTEMPT`

This takes exactly four positional args. They are passed to am verbatim as strings. The helper does not validate them, so am's own refusal, for example for a non-integer attempt or an unknown run, flows through as a passthrough. The helper is one-shot and prints exactly one JSON line on every path.

Flagged decision: the card gives no project root, so the helper sends no `--repo-dir` and relies on am resolving the run by id. If the store later needs `--repo-dir`, that is a change to this card's interface and must be agreed, not added silently.

## Observable behavior

1. When am prints a JSON object with `"ok": true`, the helper re-emits am's envelope unchanged as one compact JSON line (`{"ok":true,"data":...}`) and exits 0. The helper does not inspect or reshape `data` and does not trim it. The whole-file snapshot is passed through.
2. When am prints a JSON object with `"ok": false` (a refusal, typically am exit 3), the helper re-emits that envelope unchanged and exits 0. The exit code is decided by the envelope's `ok`, not by am's exit code.
3. Every path that prints a line exits 0, including the error lines below. The only exception is the usage error.

## Error paths

| Condition | Output line | Exit |
|---|---|---|
| argv count is not 4 | `{"ok":false,"error":{"type":"Usage","message":"usage: runs-logs.py RUN CARD PHASE ATTEMPT"}}` | 2 (matches siblings; the card's "exit 0 even on refusal" covers am refusals, not caller misuse) |
| `am` not on PATH | `{"ok":false,"error":{"type":"AmMissing","message":...}}` | 0 |
| am stdout is not JSON, is JSON but not an object, or is an object without a boolean `ok` | `{"ok":false,"error":{"type":"AmBadOutput","message":...}}` (message names `am logs` and its exit code where useful) | 0 |
| am returns `ok:false` | am's envelope, unchanged | 0 |
| any unexpected exception (timeout, am cannot start, and so on) | `{"ok":false,"error":{"type":"HelperError","message":...}}` from `guarded()` | 0 |

## Tests (TDD: write these first)

Every test below goes in `tests/core/backend/runs/test_runs_logs.py`. That file is in the backend pytest tier (`tests/core/backend/<domain>/`), as set by the "How to add / A helper script" and "Tests" sections of docs/architecture.md and by the milestone spec's Testing section (a stub `am` on PATH with recorded fixtures). None of these tests belong in `tests/contract/`, which pins the real am and is 2.4's tier. None belong in `tests/architecture/`, `tests/ui/` or the QML tiers either. The tests never call the real `am`.

The tests are hermetic and follow `test_runs_snapshot.py`. A fake `am` Python script is written to `tmp_path/bin` and put first on PATH. HOME and XDG_DATA_HOME point at temp dirs. The stub logs its argv to `calls.log`, prints `FAKE_AM_DIR/<name>.out`, and exits with `<name>.code`. Give it a `logs` branch keyed on the subcommand. For a missing fixture, the stub returns an `UnknownRunError` envelope with exit 3. The helper runs through `subprocess` with `sys.executable`, using a path computed from `__file__`. Every test asserts that stdout is exactly one JSON line.

1. `test_ok_envelope_passed_through`: a fixture `{"ok":true,"data":{prompt,result,stdout,stderr...}}` is printed back as an equal object on one line, with exit 0.
2. `test_exact_am_argv`: `calls.log` shows exactly `logs RUN CARD --phase PHASE --attempt ATTEMPT`, with no `--repo-dir` and no `--pretty`.
3. `test_pretty_printed_am_output_becomes_one_line`: multi-line JSON from the stub comes out as a single line.
4. `test_refusal_passed_through_exit_0`: the stub prints an `ok:false` envelope and exits 3. The helper prints that envelope unchanged and exits 0.
5. `test_missing_fixture_unknown_run`: the stub's default `UnknownRunError` envelope with exit 3 is passed through, with exit 0.
6. `test_non_json_output_is_am_bad_output`: the stub prints plain text. The output type is `AmBadOutput`, with exit 0.
7. `test_non_object_or_no_ok_is_am_bad_output`: a JSON list, and an object without `ok`, each give `AmBadOutput` with exit 0.
8. `test_am_missing`: PATH is set to an empty temp dir. The output is `AmMissing`, with exit 0.
9. `test_usage_wrong_argc`: 3 args and 5 args each give `Usage` with exit 2, and `am` is never called (no `calls.log` entry).
10. `test_am_cannot_start_is_helper_error`: the stub `am` on PATH is executable but cannot be started (for example a shebang naming a nonexistent interpreter, so `subprocess.run` raises `OSError`), giving a `HelperError` line with exit 0. A merely non-executable file would not do: `shutil.which` skips it and the result would be `AmMissing`. This proves `guarded()` covers the case.

`bash tests/run.sh` must pass. `tests/architecture` must pass unchanged.
