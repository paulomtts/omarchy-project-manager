# 2.1 `common/am_runs.py`: the per-project snapshot, moved — design

Card `37ad9f7c`, a subtask of story `d1d142ee` ("Global runs backend"). Parent
spec: `docs/superpowers/specs/2026-10-05-runs-all-projects-design.md` (below:
**parent**). Layering: `docs/architecture.md` (below: **arch**).

## Goal

The am-calling and snapshot-building code of `core/backend/runs/runs-snapshot.py`
moves into a new shared module, `core/backend/common/am_runs.py`, and the script
imports it back. The script's CLI contract and output do not change by one byte,
and its test file `tests/core/backend/runs/test_runs_snapshot.py` is not edited
and stays green. The module is what sibling 2.2 (`runs-snapshot-all.py`) will
call per project root.

## Starting state (verified 2026-10-08, branch head `ed6e6df`)

- `runs-snapshot.py` already treats both `cancelled` and `canceled` as terminal
  (`TERMINAL`, line 50; docstring line 14), and the fake-am tests already pin
  it: `test_terminal_set_pinned` (`cancelled` and `canceled` keep 10 of 12;
  `Canceled`, `CANCELED`, `" canceled"`, `"canceled "`, `cancel` keep 12),
  `test_canceled_spelling_reported_verbatim`, and the mixed rows of
  `test_status_fanout_selection` (`test_runs_snapshot.py` L407-458).
- The card's "ONE behaviour change" is therefore already shipped. This subtask
  makes **no** behaviour change. It must not alter the terminal set, and must
  not add a second fake-am test that repeats L434-458. The card's "new test" is
  met by the module-level tests below (T6, T7), which pin the set on
  `common.am_runs` itself, where 2.2 will read it.
- `core/backend/common/am_runs.py` does not exist. Nothing else in `core/`
  references `call_am`, `AmFailure`, `run_list` or `select_runs`.

## Inherited constraints

| constraint | source |
|---|---|
| `runs-snapshot.py` runs `am runs --all-projects --limit N`, then `am status RUN` per selected run (every non-terminal run plus the newest K terminal ones), forwards `as_of_seq`; `<project_root>` is an optional filter | parent L114-117 |
| Its terminal-status set accepts `cancelled` and `canceled` | parent L117-118 |
| The snapshot keeps the same selection rule wherever it is used | parent L105-107 |
| `core/backend` imports only the stdlib and `core/backend/common` | arch L12 |
| A helper script is `core/backend/<domain>/name.py`, one JSON line on stdout, `sys.path` insert of its parent for `common`, no duplicated helpers | arch L213-215 |
| A second copy of `emit` / `inside` / `write_atomic` / `split_frontmatter` / `frontmatter_of` fails the architecture test | arch L197-201; `tests/architecture/test_layers.py:234-241` |
| `runs-snapshot.py`'s contract: three modes, exactly one JSON line on every path, error types `Usage` (exit 2), `AmMissing`, `AmBadOutput`, `SchemaMismatch`, `HelperError`, am's `ok:false` envelope re-emitted unchanged, never partial, 60 s per am call, only `am` argv lists | arch L195; `runs-snapshot.py` L1-33 |
| Delete the moved code from `runs-snapshot.py`; do not copy it | card |
| `bash tests/run.sh` green; `tests/architecture` green | card |
| Docstrings and comments state the contract only, no narrative | card |
| TDD: tests first | card |

## Behaviour

### What moves to `core/backend/common/am_runs.py`

Moved verbatim (code, docstrings and the comment above `TERMINAL`), then
deleted from the script:

| name | contract (unchanged) |
|---|---|
| `AM_TIMEOUT = 60` | seconds per am call, the default a caller passes |
| `LIST_LIMIT = 200` | the `--limit` of every `am runs` call |
| `TERMINAL` | `frozenset({"done", "escalated", "stopped", "cancelled", "canceled"})`, matched exactly |
| `TERMINAL_LIMIT = 10` | terminal runs kept per list |
| `class AmFailure(Exception)` | `.payload` is the one envelope dict to emit |
| `bad_output(message)` | `AmFailure` with `{"ok": false, "error": {"type": "AmBadOutput", "message": message}}` |
| `schema_mismatch(what)` | `AmFailure` with type `SchemaMismatch`, message `what + " sent no non-negative integer as_of_seq; the plugin needs the newer am."` |
| `as_of_seq(data, what)` | `data["as_of_seq"]` when it is a non-negative `int` (not `bool`), else raises `schema_mismatch(what)` |
| `store_id(data)` | `data["store_id"]` when a `str`, else `""` |
| `data_dir()` | `XDG_DATA_HOME` when absolute, else `~/.local/share` |
| `call_am(am, args, timeout)` | runs `[am, *args]` (stdin `DEVNULL`, captured text, `timeout` seconds); returns the envelope's `data`; `ok:false` envelope raised as `AmFailure(envelope)`; non-JSON, non-object, or no boolean `ok: true` raise `bad_output` with today's messages; `subprocess.TimeoutExpired` and `OSError` propagate |
| `run_list(data)` | `data["runs"]` checked: a list of objects each with a non-empty string `id` and a string `status`; else `bad_output` with today's messages |
| `select_runs(runs)` | every run whose `status` is not in `TERMINAL`, plus the first `TERMINAL_LIMIT` that are, in input order; returns a new list, input unchanged |
| `run_status(am, run_id, timeout)` | `am status RUN` data (never `--repo-dir`); not an object → `bad_output("am status RUN data is not an object.")`; no valid `as_of_seq` → `SchemaMismatch` naming `am status RUN` |
| `list_snapshot(am, scope, timeout)` | `am runs <scope> --limit LIST_LIMIT`, `run_list` and `as_of_seq` checked before any status call, then `run_status` per `select_runs` row; returns `{"ok": true, "as_of_seq", "store_id", "runs": [row with status replaced], "data_dir"}` |
| `single_snapshot(am, run_id, timeout)` | `{"ok": true, "run", "as_of_seq", "store_id", "status", "data_dir"}` from `run_status` alone |

The only signature change is the `timeout` parameter on `call_am`, `run_status`,
`list_snapshot` and `single_snapshot`: required, positional or keyword, no
default. Each call passes it down unchanged, so one value bounds every am call
of one snapshot. A required argument means no caller can silently get a
timeout it did not choose (2.2 passes its own).

The module docstring states the module's contract in a few lines: the am
commands it runs, that it reads nothing but `am` output, and that every
failure is an `AmFailure` whose payload is the line to print, except a timeout
or an am that cannot start, which propagate for the caller's catch-all. It
imports only the stdlib (`json`, `os`, `subprocess`). It prints nothing and
never calls `emit` or `sys.exit`.

### What stays in `runs-snapshot.py`

The module docstring (L1-33, unchanged), the `sys.path` insert and
`from common.json_line import emit`, `USAGE`, `failure()`, `parse_args`,
`main`, `guarded` and the `__main__` guard. It imports from `common.am_runs`
exactly the names it uses (`AM_TIMEOUT`, `AmFailure`, `list_snapshot`,
`single_snapshot`), and `main` passes the script's own module-level
`AM_TIMEOUT`, read when `main` runs, as `timeout`.

That last point keeps `test_am_timeout_is_helper_error`
(`test_runs_snapshot.py` L294-306) green without editing it: the test loads the
script as module `runs_snapshot` and does
`monkeypatch.setattr(helper, "AM_TIMEOUT", 0.5)`. The patched name is the
script's own binding (imported from `common.am_runs`), and `main` must read
that binding, not `am_runs.AM_TIMEOUT`, so the 10 s fake am is cut off at
0.5 s and reported as `HelperError`. Reading `am_runs.AM_TIMEOUT` instead would
make the test fail with `AmBadOutput` after 10 s.

### Observable behaviour of the script

Identical to today for every argv, environment and am output: same stdout
line (same key order, same messages), same exit code, same am argv in the
same order. No new key, no new error type.

## Errors and edge cases

| input | behaviour (all as today) |
|---|---|
| am hangs past `timeout` | `TimeoutExpired` leaves `am_runs`; the script's `guarded` prints `HelperError` "The runs snapshot failed: ..." |
| am cannot start | `OSError` leaves `am_runs`; `HelperError` |
| am prints non-JSON / a non-object / an object without `ok` | `AmBadOutput`, message naming `am runs` or `am status` |
| am prints `ok:false` | that envelope, unchanged, exit 1 |
| `as_of_seq` missing, negative, `true`, `1.0`, `"1"` | `SchemaMismatch` |
| a status in any case or whitespace other than the five exact strings | non-terminal (kept, does not count toward 10) |
| `select_runs([])` | `[]` |

## Out of scope

- Sibling 2.2 `runs-snapshot-all.py` (several roots, thread pool,
  `RootMissing`, per-project entries), 2.3 `runs-watch.py` several roots,
  2.4 `viewer-state.py` global settings.
- The other scripts' own `AM_TIMEOUT = 60` (`run-control.py`, `runs-logs.py`,
  `dispatch-preview.py`) stay as they are.
- Any change to the terminal set, the limits, messages or output shape.
- Editing `tests/core/backend/runs/test_runs_snapshot.py`.
- The parent's L113 sentence "No `core/backend/common/am_runs.py` and no
  `runs-snapshot-all.py`" contradicts this card and 2.2 (the card wins). This
  subtask does not edit the parent spec; it is flagged for the milestone's
  docs card.

## Docs

`docs/architecture.md` L181-182, the `core/backend/common` list, gains
`am_runs` (the am calls and snapshot shared by the run helpers). No other doc
changes.

## Tests

New file `tests/core/backend/common/test_am_runs.py`, laid out like
`tests/core/backend/common/test_json_line.py` (`sys.path` insert of
`core/backend`, `from common import am_runs`). Tests that run am use a fake
`am` script written to `tmp_path` and passed as the `am` argument (an absolute
path; no `PATH` change needed). All are **unit** tier: they exercise one
module's functions in-process with a fake executable, which is the fastest
level that reaches each contract; the end-to-end CLI tier is already covered
by the unchanged `test_runs_snapshot.py`.

| id | test | what it pins |
|---|---|---|
| T1 | `test_call_am_returns_data_of_an_ok_envelope` | fake am prints `{"ok": true, "data": {...}}`; returns `data`; the fake records its argv and it is exactly `args` |
| T2 | `test_call_am_raises_the_refusal_unchanged` | `ok:false` envelope → `AmFailure` whose `payload` equals the envelope |
| T3 | `test_call_am_bad_output` (parametrized: non-JSON, `[]`, `{}`, `{"ok": "yes"}`) | `AmFailure` with type `AmBadOutput` and today's messages (`am runs did not print JSON (exit N).`, `... printed JSON that is not an object.`, `... printed an object without an ok field.`) |
| T4 | `test_call_am_honours_timeout` | fake am sleeps 10 s, `timeout=0.5` → `subprocess.TimeoutExpired` within ~1 s |
| T5 | `test_as_of_seq_accepts_only_non_negative_ints` (parametrized: `0`, `7` pass; missing, `-1`, `True`, `1.0`, `"1"` fail) | `SchemaMismatch` message `"<what> sent no non-negative integer as_of_seq; the plugin needs the newer am."` |
| T6 | `test_terminal_set_is_the_five_exact_statuses` | `am_runs.TERMINAL == {"done", "escalated", "stopped", "cancelled", "canceled"}` |
| T7 | `test_select_runs_caps_terminal_under_either_cancel_spelling` (parametrized over `cancelled`, `canceled` → 10 kept of 12; `Canceled`, `" canceled"`, `started` → 12) | the cap and both spellings at the module, plus that non-terminal rows interleaved after the cap are still kept, order preserved, input list not mutated |
| T8 | `test_run_list_rejects_malformed_rows` (parametrized: no `runs`, `runs` not a list, a row without `id`, empty `id`, non-string `status`) | `AmBadOutput` |
| T9 | `test_list_snapshot_checks_the_list_before_any_status_call` | fake am: `am runs` data without `as_of_seq` → `SchemaMismatch` and the fake's call log holds only the `runs` call |
| T10 | `test_list_snapshot_passes_scope_and_limit` | scope `["--repo-dir", "/r"]` → first call is `runs --repo-dir /r --limit 200`, then `status <id>` per selected row; result keys and `data_dir` as the contract |
| T11 | `test_store_id_and_data_dir` | `store_id` non-string → `""`; `data_dir` with relative / empty / absolute `XDG_DATA_HOME` (monkeypatched env) |

Regression gates, unchanged files:

- `tests/core/backend/runs/test_runs_snapshot.py` (integration tier: the
  script as a subprocess against a fake `am` on `PATH`, plus
  `test_am_timeout_is_helper_error` in-process) — proves the CLI contract and
  output are identical. `git diff --stat` must show it untouched.
- `tests/architecture` — proves no duplicated helper and the layering.

TDD order: T1-T11 are written first and fail on import (`common.am_runs` does
not exist); the module is then created by moving the code, the script is cut
down to import it, and all three suites pass.

Verification: `bash tests/run.sh` green. Fast loop:
`python3 -m pytest tests/core/backend/common tests/core/backend/runs/test_runs_snapshot.py tests/architecture -q`.

## Planner notes

- One task is the right size: the module, its tests, the script cut-down and
  the one-line doc edit change together, and no part can be approved while
  another is rejected (the script cannot import a module that does not exist;
  a module without the cut-down is a duplicate).
- Check after the move that `grep -n "def call_am\|def select_runs\|TERMINAL = " core/backend/runs/runs-snapshot.py`
  prints nothing.
- Review focus candidates: the `AM_TIMEOUT` binding (read the script's name at
  call time), the `timeout` reaching every am call of one snapshot including
  each `am status`, key order of the output dicts, and the module not printing
  or exiting.
