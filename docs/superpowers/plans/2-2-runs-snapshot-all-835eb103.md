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

---

# 2.2 `runs-snapshot-all.py` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new helper `core/backend/runs/runs-snapshot-all.py <root> [<root> ...]` that prints one JSON line holding one per-project run snapshot per root, in argv order, up to 4 roots at a time, with each root's failure confined to its own entry.

**Architecture:** The script is a thin CLI over `common.am_runs.list_snapshot(am, ["--repo-dir", root], timeout)`. A per-root function `project_entry` turns every outcome (success, missing directory, am refusal, bad output, timeout, any other exception) into that root's entry and never raises. `main` validates argv, checks for `am` once, maps `project_entry` over the roots through a `ThreadPoolExecutor(max_workers=4)` (`pool.map` keeps argv order), and emits `{"ok": true, "projects": [...], "data_dir": D}`; `guarded` is the top-level one-line catch-all.

**Tech Stack:** Python 3 stdlib only (`concurrent.futures`, `subprocess`, `shutil`, `os`), `core/backend/common/am_runs.py`, `core/backend/common/json_line.py`; pytest (integration tier: subprocess runs against a fake `am` on a temp `PATH`).

**Spec:** `docs/superpowers/specs/2-2-runs-snapshot-all-835eb103.md` (reproduced in full above this plan).

## Global Constraints

- `core/backend/**` imports only the stdlib and `core/backend/common`.
- One JSON line on stdout on every path; use `common.json_line.emit`. No `def emit(` (nor `def inside(`, `def write_atomic(`, `def split_frontmatter(`, `def frontmatter_of(`) anywhere in the new script **or the new test file** — `tests/architecture/test_layers.py` scans every `.py` file.
- Only documented `am` commands, as argv lists; never `shell=True`; never read am's database or on-disk layout.
- `am status` never gets `--repo-dir` (guaranteed by `list_snapshot`; do not call am yourself).
- `USAGE = "usage: runs-snapshot-all.py <root> [<root> ...]"`; `WORKERS = 4`; 60 s per am call via `AM_TIMEOUT` imported from `common.am_runs`, read from the script's own module global when `main` runs.
- Exit 0 whenever the `projects` line prints (even all entries failed / `AmMissing`); exit 1 only for the top-level `HelperError`; exit 2 for `Usage`.
- Entry key order: `root`, `ok`, then `runs` or `error`. Top-level key order: `ok`, `projects`, `data_dir`. No `as_of_seq` / `store_id` in entries.
- Fixtures come only from `tests/fixtures/am/` (never edited, nothing new recorded); every edit to a captured payload is marked `# synthetic:`.
- Do not modify `core/backend/common/am_runs.py`, `core/backend/runs/runs-snapshot.py`, `tests/core/backend/runs/test_runs_snapshot.py`, `tests/core/backend/common/test_am_runs.py`, or anything under `tests/fixtures/am/`.
- Docstrings and comments state the contract only.

**Running pytest:** the system `python3` may have no pytest. Use
`timeout 300 uv run --with pytest python3 -m pytest ...` (this is what `tests/run.sh` falls back to). If `python3 -c 'import pytest'` succeeds, `timeout 300 python3 -m pytest ...` is equivalent.

## Review Focus

1. **An am `ok:false` envelope with no `error` key** (e.g. `{"ok": false}`) — the person expects that root's entry to be `{"root": R, "ok": false, "error": null}` and every other root reported normally, not a top-level `HelperError` from a `KeyError` inside the except clause. Pinned by `test_refusal_without_error_key` (Task 1); the code uses `e.payload.get("error")`.
2. **A root whose name contains a newline** — stdout must still be exactly one line (json escapes it) and the entry `ok: true`. Pinned by `test_root_with_newline_stays_one_line` (Task 1).
3. **A root with a trailing slash** (`/path/proj-a/`) — used exactly as given: the entry's `root` and the `--repo-dir` argument keep the slash; nothing normalizes it. Pinned by `test_root_used_as_given` (Task 1).
4. **A dangling symlink as a root** — `RootMissing`, no am call for it. Pinned by the `dangling-symlink` case of `test_vanished_root` (Task 1).
5. **A timeout on an `am status` call after that root's `am runs` succeeded** — the root is `AmTimeout` with no partial `runs`, the other roots are unaffected. Pinned by `test_status_timeout_is_per_root` (Task 2).

Also re-check in review: `main` reads `AM_TIMEOUT` at call time (no default argument); argv order from `pool.map`, never `as_completed`; `subprocess.TimeoutExpired` caught before the generic `Exception`; `AmMissing` decided once before the pool and covering missing roots; no `shell=True`.

## File Structure

- Create `core/backend/runs/runs-snapshot-all.py` — the CLI: argv check, `am` lookup, per-root entries, pool, one JSON line.
- Create `tests/core/backend/runs/test_runs_snapshot_all.py` — self-contained integration tests with their own fake `am` (keyed per project root), call log and span log.
- Modify `docs/architecture.md` (the `core/backend/runs/` paragraph, one sentence after the `runs-snapshot.py` description).

---

### Task 1: The script with sequential roots: argv, `AmMissing`, `RootMissing`, success shape, per-root errors, top-level catch-all

**Files:**
- Create: `tests/core/backend/runs/test_runs_snapshot_all.py`
- Create: `core/backend/runs/runs-snapshot-all.py`

**Interfaces:**
- Consumes (from `core/backend/common/am_runs.py`, unchanged): `AM_TIMEOUT: int = 60`; `class AmFailure(Exception)` with `.payload: dict` (an `{"ok": False, "error": ...}` envelope); `data_dir() -> str`; `list_snapshot(am: str, scope: list[str], timeout: float) -> dict` returning `{"ok", "as_of_seq", "store_id", "runs", "data_dir"}` and raising `AmFailure`, `subprocess.TimeoutExpired` or `OSError`. From `core/backend/common/json_line.py`: `emit(payload: dict, code: int = 0) -> int`.
- Produces (Task 2 relies on these names): in the script, `USAGE: str`, `failure(kind, message, code=1) -> int`, `parse_args(argv: list[str]) -> list[str] | None`, `entry_error(root: str, kind: str, message: str) -> dict`, `project_entry(am: str, root: str, timeout: float) -> dict`, `main(argv: list[str]) -> int`, `guarded(argv: list[str]) -> int`. In the test file, the helpers `fixture`, `write_exec`, `world` (fixture), `project`, `env_for`, `run`, `row_for`, `status_for`, `set_runs`, `set_status`, `seed`, `set_raw`, `set_sleep`, `calls`, `expected`, `ok_entry`, `load_helper`, `in_process`, and the constants `FILTER`, `STATUS`, `USAGE`, `FIXTURES`.

- [ ] **Step 1: Write the failing tests**

Create `tests/core/backend/runs/test_runs_snapshot_all.py` with exactly this content:

```python
"""runs-snapshot-all.py: one per-project snapshot per root, one JSON line on every path.

Hermetic: a fake `am` lives on a temp PATH and serves, from FAKE_AM_DIR, the
committed captures in tests/fixtures/am/ (a payload no capture holds is labelled
`synthetic:`), appending each call's argv to calls.log and its start/end times to
spans.log; HOME and XDG_DATA_HOME are temp. The real `am` and real data are never
touched.
"""
import importlib.util
import json
import os
import stat
import subprocess
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "..")
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "runs-snapshot-all.py")

# The fake am logs its argv to calls.log and "start <t>" / "end <t>" (one shared
# monotonic clock) to spans.log, each line in one append-mode write. Its reply is
# keyed by <name>: "runs-<basename of the --repo-dir value>" for `am runs`, and
# "status-<run id>" for `am status`. It sleeps FAKE_AM_DIR/<name>.sleep seconds
# (default 0), prints FAKE_AM_DIR/<name>.out verbatim and exits with
# FAKE_AM_DIR/<name>.code (default 0). A reply that does not exist behaves like
# real am for an unknown run: an UnknownRunError envelope and exit 3.
FAKE_AM = '''#!/usr/bin/env python3
import json, os, sys, time
d = os.environ["FAKE_AM_DIR"]
args = sys.argv[1:]


def log(name, line):
    with open(os.path.join(d, name), "a") as f:
        f.write(line)


log("calls.log", json.dumps(args) + "\\n")
log("spans.log", "start %r\\n" % time.monotonic())
if args[:1] == ["runs"] and "--repo-dir" in args:
    name = "runs-" + os.path.basename(os.path.normpath(args[args.index("--repo-dir") + 1]))
else:
    name = "status-" + (args[1] if len(args) > 1 else "")
sleep = os.path.join(d, name + ".sleep")
if os.path.exists(sleep):
    time.sleep(float(open(sleep).read()))
out = os.path.join(d, name + ".out")
if os.path.exists(out):
    text = open(out).read()
    code_file = os.path.join(d, name + ".code")
    code = int(open(code_file).read()) if os.path.exists(code_file) else 0
else:
    text = json.dumps({"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}) + "\\n"
    code = 3
log("spans.log", "end %r\\n" % time.monotonic())
sys.stdout.write(text)
sys.exit(code)
'''

FIXTURES = os.path.join(ROOT, "tests", "fixtures", "am")
# synthetic: am error envelope; no capture holds one.
REPO_DIR_ERROR = {"error": {"message": "not a git repository", "type": "RepoDirError"}, "ok": False}
STATUS_CAPTURES = {"started": "status-started.json", "done": "status-done.json",
                   "escalated": "status-escalated.json"}
USAGE = "usage: runs-snapshot-all.py <root> [<root> ...]"
A = object()  # stands for project A's path in parametrized argv


def FILTER(root):
    """The `am runs` argv for one project root."""
    return ["runs", "--repo-dir", root, "--limit", "200"]


def STATUS(run_id):
    """The `am status` argv for one run: never a --repo-dir."""
    return ["status", run_id]


def fixture(name):
    """A fresh json.load of tests/fixtures/am/<name>, so an edit never reaches
    another call."""
    with open(os.path.join(FIXTURES, name)) as f:
        return json.load(f)


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am, its reply dir, and a temp HOME/XDG_DATA_HOME."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "am", FAKE_AM)
    amdir = tmp_path / "am"
    amdir.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    return {"tmp": tmp_path, "bin": bindir, "am": amdir, "home": home,
            "data": tmp_path / "data"}


def project(world, name):
    """A project root directory named `name` (its basename keys the fake's reply)."""
    path = world["tmp"] / "projects" / name
    path.mkdir(parents=True)
    return str(path)


def env_for(world, drop=(), **extra):
    e = {
        "PATH": str(world["bin"]) + os.pathsep + "/usr/bin" + os.pathsep + "/bin",
        "HOME": str(world["home"]),
        "XDG_DATA_HOME": str(world["data"]),
        "FAKE_AM_DIR": str(world["am"]),
    }
    e.update(extra)
    for key in drop:
        e.pop(key, None)
    return e


def empty_path(world):
    """A PATH holding no am."""
    empty = world["tmp"] / "empty-bin"
    empty.mkdir(exist_ok=True)
    return str(empty)


def run(world, args, drop=(), **extra):
    """Run the helper; assert stdout is exactly one JSON line; return (exit, payload)."""
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True,
                       env=env_for(world, drop, **extra), timeout=60)
    lines = p.stdout.splitlines()
    assert len(lines) == 1, (p.stdout, p.stderr)
    return p.returncode, json.loads(lines[0])


def runs_rows():
    """The captured `am runs` rows, newest first: a started run, then a done one."""
    return fixture("runs.json")["data"]["runs"]


def status_envelope(name):
    """A captured `am status` envelope without its top-level `_` keys."""
    return {k: v for k, v in fixture(name).items() if not k.startswith("_")}


def row_for(run_id, status):
    """synthetic: a test-local run id set on a copy of a real `am runs` row (the
    started row, or else the done row)."""
    row = runs_rows()[0 if status == "started" else 1]
    row["id"] = run_id
    return row


def status_for(run_id, status):
    """synthetic: the same run id set on a copy of the matching captured
    `am status` data."""
    data = status_envelope(STATUS_CAPTURES[status])["data"]
    data["run"]["id"] = run_id
    return data


def set_runs(world, root, runs):
    """`am runs --repo-dir root` serves the captured envelope without `_note`, its
    runs replaced by `runs` (synthetic: whenever runs is not the captured list)."""
    envelope = {k: v for k, v in fixture("runs.json").items() if not k.startswith("_")}
    envelope["data"]["runs"] = runs
    name = "runs-" + os.path.basename(os.path.normpath(root))
    (world["am"] / (name + ".out")).write_text(json.dumps(envelope) + "\n")


def set_status(world, run_id, data):
    (world["am"] / ("status-" + run_id + ".out")).write_text(
        json.dumps({"data": data, "ok": True}) + "\n")


def seed(world, root, run_id):
    """`am runs --repo-dir root` lists one started run `run_id` (synthetic: the
    captured started row and status data with a test-local id); returns the
    entry runs the helper must report for it."""
    row = row_for(run_id, "started")
    set_runs(world, root, [row])
    set_status(world, run_id, status_for(run_id, "started"))
    return [expected(row, status_for(run_id, "started"))]


def set_raw(world, name, text, code=0):
    (world["am"] / (name + ".out")).write_text(text)
    (world["am"] / (name + ".code")).write_text(str(code))


def set_sleep(world, name, seconds):
    (world["am"] / (name + ".sleep")).write_text(str(seconds))


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def expected(run, data):
    out = dict(run)
    out["status"] = data
    return out


def ok_entry(root, runs):
    return {"root": root, "ok": True, "runs": runs}


def load_helper():
    """The script as a module (its name has a hyphen, so no plain import)."""
    spec = importlib.util.spec_from_file_location("runs_snapshot_all", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def in_process(world, monkeypatch):
    """The helper module, with this world's environment set on the test process."""
    helper = load_helper()
    for key, value in env_for(world).items():
        monkeypatch.setenv(key, value)
    return helper


# --- success shape ----------------------------------------------------------------

def test_success_shape_and_argv(world):
    a, b = project(world, "proj-a"), project(world, "proj-b")
    a_rows = [row_for("a1", "started"), row_for("a2", "done")]
    b_rows = [row_for("b1", "started"), row_for("b2", "done")]
    set_runs(world, a, a_rows)
    set_runs(world, b, b_rows)
    for r, kind in [(a_rows[0], "started"), (a_rows[1], "done"),
                    (b_rows[0], "started"), (b_rows[1], "done")]:
        set_status(world, r["id"], status_for(r["id"], kind))
    code, out = run(world, [a, b])
    assert code == 0
    assert out == {"ok": True, "projects": [
        ok_entry(a, [expected(a_rows[0], status_for("a1", "started")),
                     expected(a_rows[1], status_for("a2", "done"))]),
        ok_entry(b, [expected(b_rows[0], status_for("b1", "started")),
                     expected(b_rows[1], status_for("b2", "done"))]),
    ], "data_dir": str(world["data"])}
    assert list(out) == ["ok", "projects", "data_dir"]
    assert [list(p) for p in out["projects"]] == [["root", "ok", "runs"]] * 2
    assert sorted(calls(world)) == sorted([FILTER(a), FILTER(b), STATUS("a1"), STATUS("a2"),
                                           STATUS("b1"), STATUS("b2")])
    assert not any("--repo-dir" in c for c in calls(world) if c[0] == "status")


def test_empty_project(world):
    a = project(world, "proj-a")
    # synthetic: the captured am runs data with an empty run list.
    set_runs(world, a, [])
    code, out = run(world, [a])
    assert code == 0
    assert out["projects"] == [{"root": a, "ok": True, "runs": []}]
    assert calls(world) == [FILTER(a)]


# --- per-root failures ------------------------------------------------------------

@pytest.mark.parametrize("case", ["refused", "bad-output", "schema"])
def test_partial_failure(world, case):
    a, b = project(world, "proj-a"), project(world, "proj-b")
    b_row = row_for("b1", "started")
    set_runs(world, b, [b_row])
    set_status(world, "b1", status_for("b1", "started"))
    if case == "refused":
        set_raw(world, "runs-proj-a", json.dumps(REPO_DIR_ERROR) + "\n", 2)
        want = REPO_DIR_ERROR["error"]
    elif case == "bad-output":
        set_raw(world, "runs-proj-a", "not json\n", 0)
        want = {"type": "AmBadOutput", "message": "am runs did not print JSON (exit 0)."}
    else:
        set_runs(world, a, [row_for("a1", "started")])
        # synthetic: the captured status data without its as_of_seq.
        data = status_for("a1", "started")
        data.pop("as_of_seq")
        set_status(world, "a1", data)
        want = {"type": "SchemaMismatch",
                "message": "am status a1 sent no non-negative integer as_of_seq; "
                           "the plugin needs the newer am."}
    code, out = run(world, [a, b])
    assert code == 0
    assert out["ok"] is True
    assert out["projects"][0] == {"root": a, "ok": False, "error": want}
    assert list(out["projects"][0]) == ["root", "ok", "error"]
    assert out["projects"][1] == ok_entry(b, [expected(b_row, status_for("b1", "started"))])


def test_refusal_without_error_key(world):
    a, b = project(world, "proj-a"), project(world, "proj-b")
    # synthetic: an ok:false envelope with no error key.
    set_raw(world, "runs-proj-a", json.dumps({"ok": False}) + "\n", 1)
    set_runs(world, b, [])
    code, out = run(world, [a, b])
    assert code == 0
    assert out["projects"] == [{"root": a, "ok": False, "error": None}, ok_entry(b, [])]


@pytest.mark.parametrize("case", ["deleted", "file", "never-existed", "dangling-symlink"])
def test_vanished_root(world, case):
    b = project(world, "proj-b")
    set_runs(world, b, [])
    gone = world["tmp"] / "gone"
    if case == "deleted":
        gone.mkdir()
        gone.rmdir()
    elif case == "file":
        gone.write_text("not a directory\n")
    elif case == "dangling-symlink":
        gone.symlink_to(world["tmp"] / "nowhere")
    r = str(gone)
    code, out = run(world, [r, b])
    assert code == 0
    assert out["projects"] == [
        {"root": r, "ok": False, "error": {"type": "RootMissing", "message": r + " is not a directory."}},
        ok_entry(b, []),
    ]
    assert not any(r in c for c in calls(world))


def test_unexpected_failure_is_per_root_helper_error(world):
    # An am that cannot be executed at all: subprocess raises OSError for each root.
    a, b = project(world, "proj-a"), project(world, "proj-b")
    write_exec(world["bin"] / "am", "#!/nonexistent/interpreter\n")
    code, out = run(world, [a, b])
    assert code == 0
    assert out["ok"] is True
    assert [p["root"] for p in out["projects"]] == [a, b]
    for p in out["projects"]:
        assert p["ok"] is False
        assert "runs" not in p
        assert p["error"]["type"] == "HelperError"
        assert p["error"]["message"].startswith("The runs snapshot failed: ")


# --- roots as given ---------------------------------------------------------------

def test_repeated_root(world):
    a = project(world, "proj-a")
    row = row_for("a1", "started")
    set_runs(world, a, [row])
    set_status(world, "a1", status_for("a1", "started"))
    code, out = run(world, [a, a])
    assert code == 0
    entry = ok_entry(a, [expected(row, status_for("a1", "started"))])
    assert out["projects"] == [entry, entry]
    assert calls(world).count(FILTER(a)) == 2
    assert calls(world).count(STATUS("a1")) == 2


def test_root_is_one_argv_element(world):
    proj = project(world, "my proj; echo x")
    # synthetic: the captured am runs data with an empty run list.
    set_runs(world, proj, [])
    code, out = run(world, [proj])
    assert code == 0
    assert out["projects"] == [ok_entry(proj, [])]
    assert calls(world) == [FILTER(proj)]


def test_root_used_as_given(world):
    a = project(world, "proj-a") + "/"
    set_runs(world, a, [])
    code, out = run(world, [a])
    assert code == 0
    assert out["projects"] == [ok_entry(a, [])]
    assert calls(world) == [FILTER(a)]


def test_root_with_newline_stays_one_line(world):
    a = project(world, "line\nbreak")
    set_runs(world, a, [])
    code, out = run(world, [a])  # run() asserts exactly one stdout line
    assert code == 0
    assert out["projects"] == [ok_entry(a, [])]


# --- usage, am missing, data_dir ---------------------------------------------------

@pytest.mark.parametrize("args", [
    [], [""], ["-x"], ["--all-projects"], ["--run", "R"], [A, "-x"], [A, ""],
], ids=["none", "empty", "dash-x", "all-projects", "run", "root-then-dash", "root-then-empty"])
def test_usage(world, args):
    a = project(world, "proj-a")
    set_runs(world, a, [])
    code, out = run(world, [a if x is A else x for x in args])
    assert code == 2
    assert out == {"ok": False, "error": {"type": "Usage", "message": USAGE}}
    assert calls(world) == []


def test_usage_before_am_lookup(world):
    code, out = run(world, [], PATH=empty_path(world))
    assert code == 2
    assert out == {"ok": False, "error": {"type": "Usage", "message": USAGE}}


def test_am_missing_in_every_entry(world):
    a = project(world, "proj-a")
    missing = str(world["tmp"] / "never")
    code, out = run(world, [a, missing], PATH=empty_path(world))
    am_missing = {"type": "AmMissing", "message": "am is not installed."}
    assert code == 0
    assert out == {"ok": True, "projects": [
        {"root": a, "ok": False, "error": am_missing},
        {"root": missing, "ok": False, "error": am_missing},
    ], "data_dir": str(world["data"])}


@pytest.mark.parametrize("case", ["absolute", "unset", "relative", "empty"])
def test_data_dir(world, case):
    a = project(world, "proj-a")
    # synthetic: the captured am runs data with an empty run list.
    set_runs(world, a, [])
    fallback = str(world["home"] / ".local" / "share")
    if case == "absolute":
        code, out = run(world, [a])
        want = str(world["data"])
    elif case == "unset":
        code, out = run(world, [a], drop=("XDG_DATA_HOME",))
        want = fallback
    elif case == "relative":
        code, out = run(world, [a], XDG_DATA_HOME="rel/data")
        want = fallback
    else:
        code, out = run(world, [a], XDG_DATA_HOME="")
        want = fallback
    assert code == 0
    assert out["data_dir"] == want


# --- catch-all and stdin ------------------------------------------------------------

def test_top_level_catch_all(world, monkeypatch, capsys):
    a = project(world, "proj-a")
    set_runs(world, a, [])
    helper = in_process(world, monkeypatch)

    def boom():
        raise RuntimeError("boom")

    monkeypatch.setattr(helper, "data_dir", boom)
    code = helper.guarded([a])
    lines = capsys.readouterr().out.splitlines()
    assert code == 1
    assert [json.loads(line) for line in lines] == [
        {"ok": False, "error": {"type": "HelperError", "message": "The runs snapshot failed: boom"}}]


def test_am_does_not_inherit_stdin(world):
    # The helper's stdin is an open pipe that never sends EOF. An am that reads
    # stdin must get EOF at once (stdin is /dev/null), not block on that pipe.
    a = project(world, "proj-a")
    runs_data = fixture("runs.json")["data"]
    # synthetic: the captured am runs data with an empty run list.
    write_exec(world["bin"] / "am",
               "#!/usr/bin/env python3\nimport json, sys\nsys.stdin.read()\n"
               "print(json.dumps({'ok': True, 'data': {'as_of_seq': %d, 'runs': [], "
               "'store_id': %r}}))\n" % (runs_data["as_of_seq"], runs_data["store_id"]))
    p = subprocess.Popen([sys.executable, SCRIPT, a], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                         env=env_for(world))
    try:
        code = p.wait(timeout=15)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait()
        pytest.fail("am blocked reading the helper's stdin")
    finally:
        p.stdin.close()
    lines = p.stdout.read().splitlines()
    p.stdout.close()
    p.stderr.close()
    assert code == 0
    assert [json.loads(line) for line in lines] == [
        {"ok": True, "projects": [ok_entry(a, [])], "data_dir": str(world["data"])}]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_snapshot_all.py -q`
Expected: every test FAILS — the subprocess tests with `AssertionError` from `run()` (no stdout line; stderr says `can't open file .../runs-snapshot-all.py`), `test_am_does_not_inherit_stdin` with exit code 2 and no lines, and the in-process `test_top_level_catch_all` with `FileNotFoundError` from `load_helper`.

- [ ] **Step 3: Write the script (roots run one after another)**

Create `core/backend/runs/runs-snapshot-all.py` with exactly this content:

```python
#!/usr/bin/env python3
"""Snapshot am runs for several project roots.

    runs-snapshot-all.py <root> [<root> ...]

Each <root> is non-empty and does not start with -. No roots, or any root that
breaks this rule, is a Usage error (exit 2) and am is not run. A root is used
exactly as given, as its entry's `root` and as the --repo-dir value; a repeated
root is snapshotted once per time it appears.

For each root: `am runs --repo-dir <root> --limit 200`, then `am status <id>`
(never with --repo-dir) for every non-terminal run and the first 10 terminal ones
(terminal: done, escalated, stopped, cancelled, canceled), in am's (newest-first)
order. Up to 4 roots run at once; each am call gets 60 s.

Prints exactly one JSON line on EVERY path:
{"ok": true, "projects": [<entry>, ...], "data_dir": D}
with one entry per root, in argv order, either
{"root": R, "ok": true, "runs": [{<am runs row>, "status": <am status data>}]}
or {"root": R, "ok": false, "error": E}, where E is am's own `ok:false`
envelope's error unchanged (StoreBusyError, RepoDirError, ...) or
{"type", "message"} with type RootMissing (R is not a directory; am is not run
for it), AmMissing (then in every entry), AmTimeout, AmBadOutput,
SchemaMismatch or HelperError. A failed root has no runs; it never changes
another root's entry. D is XDG_DATA_HOME when absolute, else ~/.local/share.
Otherwise {"ok": false, "error": {"type", "message"}} with type Usage (exit 2)
or HelperError (exit 1). Exit 0 whenever the projects line prints. Only `am`
commands are used, always as argv lists; am's database and on-disk layout are
never read.
"""
import os
import shutil
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.am_runs import AM_TIMEOUT, AmFailure, data_dir, list_snapshot  # noqa: E402
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-snapshot-all.py <root> [<root> ...]"


def failure(kind, message, code=1):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def parse_args(argv):
    """The roots, as given, when there is at least one and each is non-empty and
    does not start with -; None otherwise."""
    if not argv or any(not root or root.startswith("-") for root in argv):
        return None
    return list(argv)


def entry_error(root, kind, message):
    return {"root": root, "ok": False, "error": {"type": kind, "message": message}}


def project_entry(am, root, timeout):
    """`root`'s entry. Never raises an Exception: every failure is the entry's error."""
    if not os.path.isdir(root):
        return entry_error(root, "RootMissing", root + " is not a directory.")
    try:
        snapshot = list_snapshot(am, ["--repo-dir", root], timeout)
    except AmFailure as e:
        return {"root": root, "ok": False, "error": e.payload.get("error")}
    except Exception as e:  # noqa: BLE001 - one root's failure is its own entry
        reason = str(e) or e.__class__.__name__
        return entry_error(root, "HelperError", "The runs snapshot failed: " + reason)
    return {"root": root, "ok": True, "runs": snapshot["runs"]}


def main(argv):
    roots = parse_args(argv)
    if roots is None:
        return failure("Usage", USAGE, 2)
    am = shutil.which("am")
    if am is None:
        projects = [entry_error(root, "AmMissing", "am is not installed.") for root in roots]
    else:
        timeout = AM_TIMEOUT
        projects = [project_entry(am, root, timeout) for root in roots]
    return emit({"ok": True, "projects": projects, "data_dir": data_dir()})


def guarded(argv):
    """The caller parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The runs snapshot failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
```

Make it executable like its siblings: `chmod +x core/backend/runs/runs-snapshot-all.py` (check with `ls -l core/backend/runs/runs-snapshot.py`; match its mode).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_snapshot_all.py -q`
Expected: all PASS (30 tests).

Then the regression gates:
Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs tests/core/backend/common tests/architecture -q`
Expected: all PASS (in particular `test_shared_python_helpers_are_defined_once` and `test_layers_import_only_what_their_allowlist_permits`).

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-snapshot-all.py tests/core/backend/runs/test_runs_snapshot_all.py
git commit -m "feat(runs): runs-snapshot-all.py, one snapshot per project root"
```

---

### Task 2: Up to 4 roots at once, argv order, per-root `AmTimeout`, and the arch sentence

**Files:**
- Modify: `core/backend/runs/runs-snapshot-all.py` (imports, `WORKERS`, `project_entry`, `main`)
- Modify: `tests/core/backend/runs/test_runs_snapshot_all.py` (append tests)
- Modify: `docs/architecture.md` (the `core/backend/runs/` paragraph)

**Interfaces:**
- Consumes (from Task 1): the script's `project_entry(am, root, timeout) -> dict`, `entry_error(root, kind, message) -> dict`, `main(argv) -> int`, `guarded(argv) -> int`, module global `AM_TIMEOUT`; the test file's `world`, `project`, `run`, `set_runs`, `set_sleep`, `seed`, `ok_entry`, `calls`, `FILTER`, `in_process`.
- Produces: module constant `WORKERS = 4`; `project_entry` additionally maps `subprocess.TimeoutExpired` to `AmTimeout`; `main` runs `project_entry` through `ThreadPoolExecutor(max_workers=WORKERS).map`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/core/backend/runs/test_runs_snapshot_all.py`:

```python


# --- concurrency and timeouts -------------------------------------------------------

def max_overlap(world):
    """The most am calls in flight at once, from spans.log (an end at the same
    instant as a start counts as finished first)."""
    events = []
    for line in (world["am"] / "spans.log").read_text().splitlines():
        kind, t = line.split()
        events.append((float(t), 0 if kind == "end" else 1))
    depth = peak = 0
    for _, starts in sorted(events):
        depth += 1 if starts else -1
        peak = max(peak, depth)
    return peak


def test_argv_order_not_finish_order(world):
    roots = [project(world, "proj-" + n) for n in "abc"]
    for root in roots:
        # synthetic: the captured am runs data with an empty run list.
        set_runs(world, root, [])
    set_sleep(world, "runs-proj-a", 1)
    code, out = run(world, roots)
    assert code == 0
    assert [p["root"] for p in out["projects"]] == roots


def test_concurrency_bound(world):
    roots = [project(world, "proj-" + str(i)) for i in range(6)]
    for root in roots:
        # synthetic: the captured am runs data with an empty run list.
        set_runs(world, root, [])
        set_sleep(world, "runs-" + os.path.basename(root), 1)
    code, out = run(world, roots)
    assert code == 0
    assert out["projects"] == [ok_entry(root, []) for root in roots]
    assert 2 <= max_overlap(world) <= 4


def test_per_root_timeout(world, monkeypatch, capsys):
    import time
    a, b = project(world, "proj-a"), project(world, "proj-b")
    set_runs(world, a, [])
    set_sleep(world, "runs-proj-a", 10)
    set_runs(world, b, [])
    helper = in_process(world, monkeypatch)
    monkeypatch.setattr(helper, "AM_TIMEOUT", 0.5)
    started = time.monotonic()
    code = helper.guarded([a, b])
    elapsed = time.monotonic() - started
    lines = capsys.readouterr().out.splitlines()
    assert code == 0
    assert len(lines) == 1, lines
    out = json.loads(lines[0])
    assert out["projects"] == [
        {"root": a, "ok": False,
         "error": {"type": "AmTimeout", "message": "am did not answer within 0.5 s."}},
        ok_entry(b, []),
    ]
    assert elapsed < 5


def test_status_timeout_is_per_root(world, monkeypatch, capsys):
    a, b = project(world, "proj-a"), project(world, "proj-b")
    seed(world, a, "a1")
    set_sleep(world, "status-a1", 10)
    b_runs = seed(world, b, "b1")
    helper = in_process(world, monkeypatch)
    monkeypatch.setattr(helper, "AM_TIMEOUT", 0.5)
    code = helper.guarded([a, b])
    lines = capsys.readouterr().out.splitlines()
    assert code == 0
    assert len(lines) == 1, lines
    out = json.loads(lines[0])
    assert out["projects"] == [
        {"root": a, "ok": False,
         "error": {"type": "AmTimeout", "message": "am did not answer within 0.5 s."}},
        ok_entry(b, b_runs),
    ]
    assert FILTER(a) in calls(world)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_snapshot_all.py -q -k "argv_order or concurrency or timeout"`
Expected:
- `test_concurrency_bound` FAILS: `assert 2 <= 1` (roots run one after another).
- `test_per_root_timeout` and `test_status_timeout_is_per_root` FAIL: A's error is `{"type": "HelperError", "message": "The runs snapshot failed: Command '[...]' timed out after 0.5 seconds"}`, not `AmTimeout`.
- `test_argv_order_not_finish_order` PASSES already (sequential order is argv order); it is the guard that the pool keeps argv order.

- [ ] **Step 3: Add the pool and the timeout mapping**

In `core/backend/runs/runs-snapshot-all.py`, replace the imports block

```python
import os
import shutil
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
```

with

```python
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
```

Replace

```python
USAGE = "usage: runs-snapshot-all.py <root> [<root> ...]"
```

with

```python
USAGE = "usage: runs-snapshot-all.py <root> [<root> ...]"
WORKERS = 4
```

Replace

```python
    except AmFailure as e:
        return {"root": root, "ok": False, "error": e.payload.get("error")}
    except Exception as e:  # noqa: BLE001 - one root's failure is its own entry
```

with

```python
    except AmFailure as e:
        return {"root": root, "ok": False, "error": e.payload.get("error")}
    except subprocess.TimeoutExpired:
        return entry_error(root, "AmTimeout", "am did not answer within " + str(timeout) + " s.")
    except Exception as e:  # noqa: BLE001 - one root's failure is its own entry
```

Replace

```python
        timeout = AM_TIMEOUT
        projects = [project_entry(am, root, timeout) for root in roots]
```

with

```python
        timeout = AM_TIMEOUT
        with ThreadPoolExecutor(max_workers=WORKERS) as pool:
            projects = list(pool.map(lambda root: project_entry(am, root, timeout), roots))
```

(`pool.map` yields results in argv order regardless of finish order. `timeout` is read from the module global when `main` runs, so `monkeypatch.setattr(helper, "AM_TIMEOUT", ...)` takes effect.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_snapshot_all.py -q`
Expected: all PASS (34 tests).

- [ ] **Step 5: Add the arch sentence**

In `docs/architecture.md`, in the `core/backend/runs/` paragraph, replace

```
A failure stops at the failing am call, so a list is never partial; each am call gets 60 s. `runs-watch.py [--since-seq N]`
```

with

```
A failure stops at the failing am call, so a list is never partial; each am call gets 60 s. `runs-snapshot-all.py <root> [<root> ...]` prints `{ok: true, projects: [{root, ok, runs | error}], data_dir}` with one entry per root in argv order, each built by `common/am_runs` like the one-project mode; it runs up to 4 roots at once, gives each am call 60 s, and reports a root's failure (`RootMissing`, `AmMissing`, `AmTimeout`, `HelperError`, or am's or `am_runs`' own error) in that root's entry only; no roots, or a root that is empty or starts with `-`, is `Usage` (exit 2). `runs-watch.py [--since-seq N]`
```

- [ ] **Step 6: Run the full verification**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs tests/core/backend/common tests/architecture -q`
Expected: all PASS.

Run: `timeout 600 bash tests/run.sh`
Expected: pytest all pass, every QML test `Totals: ... 0 failed`, exit status 0.

- [ ] **Step 7: Commit**

```bash
git add core/backend/runs/runs-snapshot-all.py tests/core/backend/runs/test_runs_snapshot_all.py docs/architecture.md
git commit -m "feat(runs): snapshot up to 4 roots at once with a per-root timeout"
```
<!-- task-pipeline: validated -->
