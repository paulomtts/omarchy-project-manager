# 2.2 `runs-snapshot-all.py`: one snapshot for several project roots — design

Card `835eb103`, a subtask of story `d1d142ee` ("Global runs backend"), blocked
by 2.1 (`37ad9f7c`, `common/am_runs.py`, landed at `69b4bcc`). Parent spec:
`docs/superpowers/specs/2026-10-05-runs-all-projects-design.md` (below:
**parent**). Layering: `docs/architecture.md` (below: **arch**). Sibling
contract this script mirrors: `core/backend/runs/runs-snapshot.py` (below:
**single**).

## Goal

A new helper, `core/backend/runs/runs-snapshot-all.py <root> [<root> ...]`,
prints exactly one JSON line with one per-project snapshot for each root, in
argv order. Each project's snapshot is `common.am_runs.list_snapshot` with
scope `["--repo-dir", root]`. Up to 4 roots run at once. One project's failure
is that project's entry and never fails the others. No caller uses the script
yet (`RunStore.qml` calls only `runs-snapshot.py` and `runs-watch.py`). The
deliverable is the script, its tests, and one sentence in arch.

## Preconditions (checked 2026-10-08, head `69b4bcc`)

- **Real `am` data reaches the run model.** The card says to stop if
  `Runs.normalizeRun` of a recorded real `am status` payload gives an empty
  tree (parent L13-16). It does not give one. `tests/fixtures/am/status-started.json`,
  `status-done.json` and `status-escalated.json` are recorded `am status` data
  with populated `stories[].subtasks[]` and `rows[]`. `tests/core/domain/tst_runs.qml`
  already normalizes them through `amRun()` and asserts non-empty subtask
  trees (around L225). No escalation is needed.
- `core/backend/common/am_runs.py` exists and provides `AM_TIMEOUT = 60`,
  `AmFailure` (`.payload` is the `ok:false` envelope), `data_dir()` and
  `list_snapshot(am, scope, timeout)`. `subprocess.TimeoutExpired` and
  `OSError` propagate out of `list_snapshot` (`am_runs.py` L1-8). This script
  must catch them **per root**.
- Neither `core/backend/runs/runs-snapshot-all.py` nor
  `tests/core/backend/runs/test_runs_snapshot_all.py` exists.

## Inherited constraints

| constraint | source |
|---|---|
| `core/backend/**` imports only the stdlib and `core/backend/common` (`concurrent.futures` is stdlib) | arch L12 |
| A helper script is `core/backend/<domain>/name.py`: one JSON line on stdout, a `sys.path` insert of its parent for `common`, tests under `tests/core/backend/<domain>/` | arch L214-216 |
| No second `def emit(` (nor `inside`, `write_atomic`, `split_frontmatter`, `frontmatter_of`); use `common.json_line.emit` | `tests/architecture/test_layers.py` L231-241 |
| Only documented `am` commands, as argv lists; am's database and on-disk layout are never read | arch L196; single L31-32 |
| `am status` never gets `--repo-dir` | `am_runs.py` L3, single L18 |
| Each project uses the same run selection (every non-terminal run plus the first 10 terminal ones of `--limit 200`) | parent L105-107; `am_runs.select_runs` |
| `data_dir` is `XDG_DATA_HOME` when absolute, else `~/.local/share` | single L26-27; `am_runs.data_dir` |
| Root argv rule: non-empty and not starting with `-`, else `Usage` (exit 2) and am is not run | single L10-11, `parse_args` L36-47 |
| Prints exactly one JSON line on every path, even on an unexpected exception | single `guarded` L68-78 |
| `ok:false` envelopes from am are carried unchanged (here: as the entry's `error`) | single L29-30 |
| Fixtures are recorded from the installed `am`, never hand-shaped | parent L17; card |
| Up to 4 roots at a time (a thread pool); 60 s per am call; argv lists only, never a shell | card |
| Docstrings and comments state the contract only; TDD, tests first; `bash tests/run.sh` green including `tests/architecture` | card |

Known contradictions, resolved here:

- Parent L113 says "No `core/backend/common/am_runs.py` and no
  `runs-snapshot-all.py`". The card and story come later and say otherwise,
  and the card wins. This subtask does not edit the parent spec; 2.1 already
  flagged this for the milestone's docs card.
- The card says to record `am status RUN --repo-dir .`. The shared code never
  passes `--repo-dir` to `am status`, and the arch contract forbids it. The
  helper follows the code. The existing recordings in `tests/fixtures/am/`
  are enough, so no new recording is needed (see Tests).

## Behaviour

### CLI

```
runs-snapshot-all.py <root> [<root> ...]
```

- Each `<root>` must be non-empty and must not start with `-`. With no
  roots, or with any root that breaks this rule, the script prints
  `{"ok": false, "error": {"type": "Usage", "message": USAGE}}` and exits 2.
  `USAGE` is `"usage: runs-snapshot-all.py <root> [<root> ...]"`. Argv is
  checked before `am` is looked up, so this is `Usage` even when `am` is
  missing, and no am command runs.
- A root is used exactly as given: as the entry's `root` string and as the
  `--repo-dir` argument. It is not normalized, resolved or deduplicated.
  A repeated root gets its own entry, and its own am calls, for each time it
  appears.

### Success line (exit 0)

```
{"ok": true, "projects": [<entry>, ...], "data_dir": D}
```

- `projects` has one entry per argv root, **in argv order**, whatever order
  the roots finish in.
- `D` is `common.am_runs.data_dir()`.
- Key order is exactly `ok`, `projects`, `data_dir`.
- The top level is `ok: true` and the exit is 0 whenever this line prints,
  even when every entry failed.

Entry shapes. Key order is as written. `runs` and `error` never appear
together.

| case | entry |
|---|---|
| project snapshot succeeded | `{"root": R, "ok": true, "runs": <list_snapshot(...)["runs"]>}`: each selected `am runs` row with `status` replaced by its `am status` data, in am's order. An empty project gives `"runs": []`. |
| `R` is not a directory (`os.path.isdir` false: missing, vanished, a file, a dangling symlink) | `{"root": R, "ok": false, "error": {"type": "RootMissing", "message": R + " is not a directory."}}`. No am call has this root. |
| `am` is not on `PATH` | every entry is `{"root": R, "ok": false, "error": {"type": "AmMissing", "message": "am is not installed."}}`, a missing root included. No am call. |
| am refused (`AmFailure` from an `ok:false` envelope: `RepoDirError`, `StoreBusyError`, `UnknownRunError`, ...) | `{"root": R, "ok": false, "error": <the envelope's "error" value, unchanged>}` |
| `AmBadOutput` / `SchemaMismatch` from `am_runs` | `{"root": R, "ok": false, "error": <that AmFailure's payload["error"]>}`, with the message exactly as `am_runs` builds it |
| an am call of this root ran longer than the timeout (`subprocess.TimeoutExpired`) | `{"root": R, "ok": false, "error": {"type": "AmTimeout", "message": "am did not answer within " + str(timeout) + " s."}}`. With the default timeout the message is `am did not answer within 60 s.` |
| any other exception while snapshotting this root (`OSError` when am cannot start, or anything unexpected) | `{"root": R, "ok": false, "error": {"type": "HelperError", "message": "The runs snapshot failed: " + (str(e) or e.__class__.__name__)}}` |

The per-project `as_of_seq` and `store_id` from `list_snapshot` are **not**
in the entry, because the card fixes the entry shape as `{root, ok, runs?, error?}`.
A failed project is never partial: if any of its am calls fails, its entry
has no `runs`, the same rule as single L31.

### Concurrency and timeouts

- The roots go through a `concurrent.futures.ThreadPoolExecutor` with
  `max_workers` = the module constant `WORKERS = 4`. At most 4 roots have am
  calls in flight at any moment. Within one root the calls stay sequential
  (`am runs`, then each `am status`), exactly as `list_snapshot` makes them.
- Every am call gets `timeout` seconds. `main` reads `timeout` from the
  script's own module-level name `AM_TIMEOUT` (imported from `common.am_runs`,
  value 60) **when `main` runs**, so a test can `monkeypatch.setattr(helper,
  "AM_TIMEOUT", 0.5)`, the same pattern as single's
  `test_am_timeout_is_helper_error`. The script reads no environment variable
  for the timeout.
- A timed-out am child is killed by `subprocess.run` (in `call_am`). The
  worker then reports `AmTimeout` for that root and moves on, and the other
  roots carry on.
- The `RootMissing` check runs inside the per-root task, before any am call.
  The `AmMissing` check (`shutil.which("am")`) runs once, before the pool
  starts. When it fails, no pool runs and every entry is `AmMissing`.

### Exceptions and the catch-all

- Per root: the worker catches `AmFailure`, `subprocess.TimeoutExpired` and
  every other `Exception`, and turns each into that root's entry as in the
  table. It never re-raises, so one root's failure can't cancel or fail
  another root.
- Top level: `guarded(argv)` wraps `main(argv)` like single does. It re-raises
  `SystemExit`. Any other `BaseException` that escapes (a bug, or
  `KeyboardInterrupt`) prints
  `{"ok": false, "error": {"type": "HelperError", "message": "The runs snapshot failed: " + reason}}`
  and exits 1. This is the only path that gives exit 1.

### Exit codes

| code | when |
|---|---|
| 0 | the success line printed (any mix of ok and failed entries, `AmMissing` included) |
| 1 | top-level `HelperError` only |
| 2 | `Usage` |

### Script structure (for the planner; the observable contract is above)

- The module docstring states the CLI, the output shapes, the error types,
  the exit codes, the 4-root bound and the 60 s per call, in the style of
  single L1-33.
- `sys.path.insert(0, <dirname>/..)`; `from common.am_runs import AM_TIMEOUT,
  AmFailure, data_dir, list_snapshot`; `from common.json_line import emit`.
- Names: `USAGE`, `WORKERS = 4`, `failure(kind, message, code)`
  (same shape as single's), `parse_args(argv) -> list[str] | None`,
  `entry_error(root, kind, message) -> dict`, `project_entry(am, root, timeout) -> dict`
  (never raises `Exception`), `main(argv) -> int`, `guarded(argv) -> int`,
  and the `__main__` guard `sys.exit(guarded(sys.argv[1:]))`.
- The script imports nothing from `runs-snapshot.py`. It has no `def emit(`.

## Errors and edge cases

| input | behaviour |
|---|---|
| no argv | `Usage`, exit 2, no am call |
| `""`, `-x`, `--all-projects`, `--run R` among the roots | `Usage`, exit 2, no am call (even with valid roots beside it) |
| bad argv and `am` missing | `Usage`, exit 2 |
| `am` missing, valid roots | exit 0; every entry `AmMissing`, in argv order |
| a root deleted between argv and the run | `RootMissing` for that root; the rest are unaffected |
| a root that is a regular file | `RootMissing` |
| a root whose name has spaces or shell metacharacters (`my proj; echo x`) | passed as one argv element; no shell |
| one root's `am runs` refuses (`RepoDirError`) | that entry carries the refusal's `error`; the other entries are `ok: true` |
| one root's `am status` fails after its `am runs` succeeded | that entry is `ok: false` with no `runs`; no other root changes |
| one root's am hangs | that entry is `AmTimeout` after `timeout` s; the others finish and report normally |
| more than 4 roots | at most 4 snapshot at once; all are reported in argv order |
| an empty project | `{"root": R, "ok": true, "runs": []}` |
| the same root twice | two entries, both snapshotted |
| every root fails | exit 0, top level `ok: true`, every entry `ok: false` |
| am cannot start (non-executable interpreter) | per-root `HelperError` entries, exit 0 |
| the helper's stdin is a pipe that never closes | am gets `/dev/null` (already in `call_am`); no hang |

## Out of scope

- 2.1 (`common/am_runs.py`): no change to it, its tests, the terminal set,
  the limits or its messages.
- 2.3 (`runs-watch.py` over several roots) and 2.4 (`viewer-state.py` global
  settings).
- Any caller: `RunStore.qml`, `App.qml` and the UI do not call the script
  in this subtask.
- `runs-snapshot.py` and `tests/core/backend/runs/test_runs_snapshot.py`
  stay unchanged.
- Editing the parent spec (the L113 contradiction is for the docs card).
- Recording new fixtures, and editing files under `tests/fixtures/am/`.

## Docs

`docs/architecture.md` L196, the `core/backend/runs/` paragraph, gains one
sentence after the `runs-snapshot.py` description. It says that
`runs-snapshot-all.py <root> [<root> ...]` prints
`{ok: true, projects: [{root, ok, runs | error}], data_dir}` in argv order,
using `common/am_runs`. It runs up to 4 roots at once, gives 60 s per am
call, and reports a per-root error (`RootMissing`, `AmMissing`, `AmTimeout`,
`HelperError`, or am's or `am_runs`' own error) in that root's entry only.
`Usage` (exit 2) applies to no roots or a root that is empty or starts with
`-`. No other doc changes.

## Tests

New file `tests/core/backend/runs/test_runs_snapshot_all.py`. It is
**integration tier**: the script runs as a subprocess against a fake `am`
on a temp `PATH`, with temp `HOME` and `XDG_DATA_HOME`, the same harness as
`test_runs_snapshot.py`. The deliverable *is* a CLI contract (argv in, one
stdout line and an exit code out, am argv observed), and only a subprocess
run proves the one-line, exit-code and argv-list properties. Two tests (T8,
T13) load the script in-process through `importlib.util` and call
`guarded`. This is the cheapest way to shorten `AM_TIMEOUT` without an
environment variable in the contract, and it is the pattern single's
timeout test uses. They stay in the same file and tier. No unit tier is
added: `list_snapshot` and its pieces are already unit-tested in
`tests/core/backend/common/test_am_runs.py`.

**Fake am.** The file is self-contained. Copy the helpers it needs
(`fixture`, `write_exec`, `env_for`, `calls`); do not import from
`test_runs_snapshot.py`. The fake logs each call's argv as one JSON line to
`FAKE_AM_DIR/calls.log`, opened in append mode. It looks up its reply by
`<name>`: `runs-<basename of the --repo-dir value>` for `am runs`, and
`status-<run id>` for `am status`. `am status` has no root, so run ids are
unique across the projects of a test. The reply files are:

- `<name>.out`, printed verbatim;
- `<name>.code`, the exit code (default 0);
- `<name>.sleep`, seconds to sleep before answering (default 0).

A missing `status-<id>.out` answers like real am for an unknown run (the
`UnknownRunError` envelope, exit 3; synthetic). While a call runs, the fake
also writes `start <monotonic>` and `end <monotonic>` lines, one each, to
`FAKE_AM_DIR/spans.log` in append mode, for the concurrency test. Each
project root is a temp directory with a distinct basename.

**Fixtures.** Rows and status data come from the recorded captures:
`runs.json` (`am runs`), `status-started.json`, `status-done.json` and
`status-escalated.json`. The only edits are the existing synthetic
conventions of `test_runs_snapshot.py`: a test-local run `id` (and the
matching `run.id` in its status data) set on a copy of a captured row, so
that two projects never share an id, and an `ok:false` envelope or an
empty run list where a test needs one. Every edit is marked with a
`# synthetic:` comment. No payload is written from scratch except the error
envelopes, which no capture holds, and they are labelled `synthetic:` as
they are today.

| id | test | what it pins |
|---|---|---|
| T1 | `test_success_shape_and_argv` | two roots, each with the captured started and done rows (ids made unique). Exit 0. The output equals `{"ok": true, "projects": [{"root": A, "ok": true, "runs": [row+status, ...]}, {"root": B, ...}], "data_dir": XDG_DATA_HOME}` exactly, including key order (compare `list(out)` and each entry's keys). The call log holds `["runs", "--repo-dir", A, "--limit", "200"]` and `["runs", "--repo-dir", B, "--limit", "200"]`, plus `["status", id]` per row and no `--repo-dir` on any status call. Entries carry no `as_of_seq` or `store_id`. |
| T2 | `test_partial_failure` (parametrized: A's `am runs` gives a synthetic `RepoDirError` envelope at exit 2; A's `am runs` is non-JSON → `AmBadOutput`; A's status data has no `as_of_seq` → `SchemaMismatch`) | A's entry is `{"root": A, "ok": false, "error": <expected error>}`, with no `runs` key. For the refusal, `error` equals the envelope's `error` unchanged. B's entry is `ok: true` with its runs. Exit 0. |
| T3 | `test_empty_project` | root A's `am runs` is the captured envelope with `runs: []` (synthetic). The entry is `{"root": A, "ok": true, "runs": []}` and the only call is A's `runs` call. |
| T4 | `test_vanished_root` (parametrized: a deleted directory, a regular file, a path that never existed) | that entry is `{"root": R, "ok": false, "error": {"type": "RootMissing", "message": R + " is not a directory."}}`. No call in the log has R. The neighbouring good root is `ok: true`. Exit 0. |
| T5 | `test_argv_order_not_finish_order` | three roots, where the first root's `am runs` sleeps 1 s and the last answers at once. `[p["root"] for p in out["projects"]]` equals argv. |
| T6 | `test_concurrency_bound` | 6 roots, each `am runs` sleeping 1 s with an empty run list. From `spans.log`, the maximum number of overlapping `[start, end]` intervals is ≤ 4 (the bound) and ≥ 2 (roots really run in parallel). All 6 entries are `ok: true`, in argv order. |
| T7 | `test_repeated_root` | `A A` gives two equal `ok: true` entries and two `runs --repo-dir A` calls. |
| T8 | `test_per_root_timeout` (in-process) | `monkeypatch.setattr(helper, "AM_TIMEOUT", 0.5)`. Root A's `am runs` sleeps 10 s and root B answers at once. `helper.guarded([A, B])` returns 0 and prints one line. A is `{"root": A, "ok": false, "error": {"type": "AmTimeout", "message": "am did not answer within 0.5 s."}}`, B is `ok: true`, and the call returns in < 5 s. |
| T9 | `test_am_missing_in_every_entry` | `PATH` without am, roots `[A, missing]`. Exit 0. The output is `{"ok": true, "projects": [<AmMissing entry for A>, <AmMissing entry for missing>], "data_dir": D}`. |
| T10 | `test_usage` (parametrized: `[]`, `[""]`, `["-x"]`, `["--all-projects"]`, `["--run", "R"]`, `[A, "-x"]`, `[A, ""]`) | exit 2, `{"ok": false, "error": {"type": "Usage", "message": USAGE}}`, and the call log is empty. |
| T11 | `test_usage_before_am_lookup` | `[]` with no am on `PATH` gives `Usage`, exit 2. |
| T12 | `test_unexpected_failure_is_per_root_helper_error` | am is `#!/nonexistent/interpreter`; roots `[A, B]`. Exit 0, and both entries are `ok: false` with `error.type == "HelperError"` and a message starting `The runs snapshot failed: `. |
| T13 | `test_top_level_catch_all` (in-process) | `monkeypatch.setattr(helper, "data_dir", <raises RuntimeError("boom")>)`. `guarded([A])` returns 1 and prints exactly one line, `{"ok": false, "error": {"type": "HelperError", "message": "The runs snapshot failed: boom"}}`. |
| T14 | `test_root_is_one_argv_element` | root `my proj; echo x` (an existing directory) gives a `["runs", "--repo-dir", "<that path>", "--limit", "200"]` call, and the entry is `ok: true`. |
| T15 | `test_am_does_not_inherit_stdin` | the helper's stdin is a pipe that never closes, and am reads stdin. The helper ends within 15 s with exit 0 (copy of single's test, with one root). |
| T16 | `test_data_dir` (parametrized: absolute, unset, relative, empty `XDG_DATA_HOME`) | `out["data_dir"]` is the absolute value, or else `$HOME/.local/share`. |

Regression gates, with these files unchanged:
`tests/core/backend/runs/test_runs_snapshot.py`,
`tests/core/backend/common/test_am_runs.py` and `tests/architecture`
(layering, no second `def emit(`).

TDD order: write T1-T16 first. Each fails because the script does not
exist (the subprocess exits non-zero with no stdout line). Then write the
script, then the arch sentence.

Verification: `bash tests/run.sh` green. Fast loop:
`timeout 300 python3 -m pytest tests/core/backend/runs tests/core/backend/common tests/architecture -q`.

## Planner notes

- Two tasks are a reasonable split. A reviewer could reject the Usage /
  AmMissing / RootMissing paths while approving the thread pool, or the
  other way round:
  1. The script skeleton with argv, `AmMissing`, `RootMissing`, the
     success shape and the per-root error mapping (T1-T4, T7, T9-T12,
     T14-T16).
  2. The thread pool, argv order under concurrency, the timeout and the
     top-level catch-all (T5, T6, T8, T13), plus the arch sentence.

  Task 1 may run roots sequentially. Task 2 swaps in the pool without
  changing any task-1 test.
- Review focus candidates:
  - `main` reads the script's own `AM_TIMEOUT` at call time; a default
    argument bound at definition would break T8.
  - The pool keeps argv order (`executor.map`, or futures collected in
    submission order), not `as_completed` order.
  - The worker catches `TimeoutExpired` before the generic `Exception`.
  - `AmMissing` is decided once, before the pool, and covers missing roots
    too.
  - No `shell=True` anywhere.
  - The entry key order is `root`, `ok`, then `runs` or `error`.
- The fake's `spans.log` timestamps must come from one clock shared by
  every process. `time.monotonic()` is system-wide on Linux
  (`CLOCK_MONOTONIC`); `time.time()` also works. Write each line with a
  single `write` call in append mode, so the lines from concurrent fakes do
  not interleave.
