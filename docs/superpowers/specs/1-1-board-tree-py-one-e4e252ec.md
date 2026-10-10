# 1.1 board-tree.py: one project's brd tree by root — design

Card: `e4e252ec` (subtask of story `66107096`). Parent design:
`docs/superpowers/specs/2026-10-05-dispatch-from-runs-design.md`, cited below as "DFR l.N".

## Purpose

The Runs-screen dispatch dialog has to read the board of a project that may not be the open
one. `BoardStore` can read only the open project's tree (DFR l.139-144). This card adds a
read-only backend helper, `core/backend/boards/board-tree.py`, with two modes:

- `board-tree.py ROOT` returns one project's `brd tree` as one JSON line.
- `board-tree.py --probe ROOT [ROOT ...]` gives a fast, brd-free reachability check for many
  roots.

Nothing calls the helper yet. The store wiring belongs to a later card.

## Inherited constraints

- `board-tree.py ROOT` runs `brd tree` with `cwd=ROOT`, as an argv list, with stdin from
  devnull and a 20 s timeout, and prints one JSON line (DFR l.148-149).
- Success is `{"ok": true, "data": [...]}`, which is brd's tree unchanged (DFR l.149-150).
- Failure is `{"ok": false, "error": {"type", "message"}}`. The type is one of `RootMissing`,
  `BrdMissing`, `BrdFailed` (brd's own error message, for example `ProjectNotFoundError`),
  `BrdBadOutput` or `HelperError` (DFR l.150-152).
- `--probe ROOT [ROOT ...]` never runs brd. It prints
  `{"ok": true, "projects": [{"root", "ok", "reason"?}]}` in argv order. A root is ok when it
  is a directory holding `.brd` (DFR l.153-156).
- Both modes use `common.json_line.emit` and exit 0 whenever a line was printed (DFR l.158).
- Only documented brd commands are used, and brd's database is never read (DFR l.158-159).
- Follow `core/backend/boards/archive-milestones.py`'s conventions (DFR l.145-146; card).
- Tests go in `tests/core/backend/boards/test_board_tree.py` with a fake `brd` on PATH. They
  cover: the cwd is ROOT, passthrough, each error type, the timeout, probe ok and not ok in
  argv order, and that the probe never runs brd (DFR l.242-244; card).
- Layering per `docs/architecture.md`, and `tests/architecture` must pass. `emit` is defined
  once repo-wide (`tests/architecture/test_layers.py:231`), so it is imported and never
  redefined. `core/backend/` holds no `.qml`/`.js` (`test_layers.py:223`).
- Verification is `bash tests/run.sh` green. Tests come first (TDD). Docstrings and comments
  state the contract only, with no narrative (card).

## Behaviour

### Invocation and output

- Every invocation prints exactly one line on stdout: a compact JSON object made by
  `emit(payload, 0)`. It then exits 0. Nothing else is written to stdout. stderr is not part
  of the contract.
- The argv forms are:
  - `board-tree.py ROOT`: tree mode. There is exactly one positional argument, and it does not
    start with `-`.
  - `board-tree.py --probe [ROOT ...]`: probe mode. `--probe` must be the first argument.
    Every argument after it is a root taken verbatim, including one that starts with `-`.
  - Anything else is a usage error: no arguments, two or more roots without `--probe`, or a
    single argument that starts with `-` other than `--probe` (such as `--help`). It prints
    `{"ok": false, "error": {"type": "HelperError", "message": "usage: board-tree.py ROOT | board-tree.py --probe ROOT [ROOT ...]"}}`
    and runs nothing.

### Tree mode (`board-tree.py ROOT`)

The checks run in this order:

1. **RootMissing.** If `os.path.isdir(ROOT)` is false (missing, a file, or `""`), the helper
   prints `{"type": "RootMissing", "message": "project directory not found: ROOT"}`
   (ROOT verbatim). brd is not run.
2. **Run.** Otherwise it runs `subprocess.run(["brd", "tree"], cwd=ROOT,
   stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=TIMEOUT_SECONDS)` with
   module constant `TIMEOUT_SECONDS = 20`. brd is found on `PATH`. Only `brd tree` is ever run,
   once.
3. **BrdMissing.** On `FileNotFoundError`, the message is `"brd was not found on PATH"`.
4. **Timeout.** On `subprocess.TimeoutExpired`, the type is **`BrdFailed`** and the message
   is `"brd tree timed out after 20 s"`. The number is `TIMEOUT_SECONDS`, formatted with
   `%g`. `subprocess.run` kills the child, so the helper still prints its line promptly. The
   parent spec does not name a type for this case. `BrdFailed` is chosen because brd ran and
   did not answer, and the dialog treats every non-ok tree read the same way (DFR l.234).
5. **Parse.** stdout is parsed with `json.loads`. If that fails, the payload is `None`.
6. **Success.** If the exit code is 0 and the payload is a dict with `ok is True` and a list
   `data`, the helper prints the payload as parsed. The result equals brd's JSON value: the
   same keys, the same key order and every extra top-level key brd sent. It is re-serialized
   onto one line. Pretty-printed or multi-line brd output is accepted. Non-ASCII may come out
   `\u`-escaped, and that is still the same JSON value.
7. **BrdFailed (brd said no).** If the payload is a dict whose `error` is a dict with a
   non-empty `message`, the message is that string verbatim. This holds whatever the exit
   code is. Example: in a directory brd does not know, the message is
   `"no registered project at or above /tmp; run \`brd init\` there"` (type
   `ProjectNotFoundError` on brd's side, exit 1).
8. **BrdFailed (other non-zero exit).** If the exit code is not 0 and step 7 did not apply,
   the message is stderr stripped. If that is empty, it is stdout stripped. If that is also
   empty, it is `"brd tree exited with N"`.
9. **BrdBadOutput.** If the exit code is 0 and none of the above applied (stdout not JSON, not
   an object, `ok` not `true`, or `data` missing or not a list), the message is
   `"brd tree returned unexpected output"`.
10. **HelperError (unexpected).** Any other exception escaping the steps above (for example
    `PermissionError` when ROOT cannot be entered) is caught at the top level. It prints
    `{"type": "HelperError", "message": str(exc) or exc class name}`. No traceback goes to
    stdout.

A failure line is always exactly `{"ok": false, "error": {"type": T, "message": M}}`, where
`M` is a non-empty string.

### Probe mode (`board-tree.py --probe ROOT ...`)

- It never runs brd or any other process, and it reads no file contents. It only stats paths.
- Output: `{"ok": true, "projects": [...]}`. There is one entry per argv root, in argv order.
  Duplicates are repeated rather than merged. `--probe` with no roots gives `"projects": []`.
- Each entry, checked in order:
  - `{"root": R, "ok": false, "reason": "not a directory"}` when `os.path.isdir(R)` is false.
  - `{"root": R, "ok": false, "reason": "no .brd marker"}` when
    `os.path.exists(os.path.join(R, ".brd"))` is false. The marker may be a file or a
    directory.
  - `{"root": R, "ok": true}` otherwise, with no `reason` key.
- `root` is the argv string verbatim, never normalized, so the caller can match rows by key.

## Open issue for the reviewer: the `.brd` marker does not exist on this machine

The probe rule above (card and DFR l.72-73, l.154-155) assumes that every brd project has a
`.brd` marker in its root. On 2026-10-09, none of the 8 roots from `brd projects` on this
machine has a `.brd` entry. All of them are directories. The repo's own `.gitignore` lists
`.brd` (commit `a200565`), so older brd versions apparently wrote it. Current brd resolves
the project from its registry by path ("no registered project at or above …"). As specified,
the probe would therefore report every real project as `"no .brd marker"`, and step 1 of the
dialog would disable all of them.

This card implements the specified contract, because it is the card's and the parent spec's
explicit rule, and all tests use temporary directories with a `.brd` they create. Before the
store card wires `--probe` into step 1, someone has to decide whether the marker rule should
change, for example to "is a directory" only, with a failed tree read as the real check
(DFR l.74-75 already handles that path). Changing it is out of scope here. It is
a one-line change to the probe's second check and its test.

## Out of scope

- Wiring into `RunStore` (`dispatchProjectRunner`, `dispatchTargetRunner`), `HelperRunner`
  registration, and `docs/architecture.md:112` (sibling store card).
- `Runs.dispatchProjects` / `dispatchTargets` in `core/domain/runs.js` (sibling domain card).
- Indexing the tree (`Board.indexTree`), filtering targets, and any UI.
- `start-run.py` run-id discovery (DFR l.163-172).
- Any other brd command, reading brd's database, or caching.

## Files

- Create `core/backend/boards/board-tree.py` (executable, `#!/usr/bin/env python3`). Its
  module docstring states both argv forms, the output shapes, the error types and exit 0. The
  layout follows `archive-milestones.py`: `sys.path.insert(0, <dir>/..)`, then
  `from common.json_line import emit  # noqa: E402`, `TIMEOUT_SECONDS = 20`, a
  `main(argv) -> int` that returns `emit(..., 0)`, and `sys.exit(main(sys.argv))`.
  Suggested internal split: `tree(root) -> dict`, `probe(roots) -> dict`, and
  `failure(type, message) -> dict`, with `main` holding the usage check and the top-level
  `except Exception`.
- Create `tests/core/backend/boards/test_board_tree.py`.
- No other file changes.

## Tests

All of these tests are in the backend pytest tier, in `tests/core/backend/boards/test_board_tree.py`.
The helper is a standalone process whose contract is argv, cwd, PATH, stdout and exit code,
so it is tested end to end as a subprocess, the same way `test_archive_milestones.py` is.
The exception is the timeout test, which runs in-process (see T6).

Fixture: as in `test_archive_milestones.py`. A fake `brd` shell script goes in
`tmp_path/bin`. It is made executable and is the only thing on `PATH`
(`env = {"PATH": bindir, "CALLS": log, ...}`). It appends `brd $* (cwd=$(pwd))` to `$CALLS`,
then behaves according to env vars: `FAKE_OUT` (printed to stdout), `FAKE_ERR` (stderr),
`FAKE_EXIT` (exit code, default 0) and `FAKE_SLEEP` (seconds to sleep first). The sleep must
be `exec sleep "$FAKE_SLEEP"`. Without `exec`, the killed `sh` leaves an orphan `sleep`
holding the stdout pipe open, and `subprocess.run`'s post-kill `communicate()` waits for it. The project is
`tmp_path/"my project"` (with a space), which contains `.brd/`. `run(box, *args)` returns
`(returncode, json of the last stdout line)` and also asserts that stdout has exactly one
line.

| # | test | asserts |
|---|---|---|
| T1 | tree runs `brd tree` once in ROOT | exit 0; calls log == `["brd tree (cwd=<project resolved>)"]` |
| T2 | tree passes brd's payload through | fake prints `{"ok": true, "data": [{"id": "a", "children": [], "title": "é"}], "extra": 1}`; output == that value exactly (incl. `extra`) |
| T3 | pretty-printed brd output still passes through as one line | fake prints multi-line JSON; one stdout line, equal value |
| T4 | stdin is devnull | the helper is run with `input="leak\n"`; the fake does `read l; echo "stdin=$l" >> $CALLS`; the log shows `stdin=` (empty) |
| T5 | RootMissing for a missing path, a file and `""` (parametrized) | `error.type == "RootMissing"`, message contains ROOT; calls log empty |
| T6 | timeout gives BrdFailed and kills brd | in-process: load the module with `importlib.util.spec_from_file_location`, `monkeypatch.setattr(mod, "TIMEOUT_SECONDS", 0.5)`, `monkeypatch.setenv("PATH", bindir)`, fake sleeps 30; `mod.main([...])` returns 0 within a few seconds; captured line has type `BrdFailed` and message `"brd tree timed out after 0.5 s"`. Plus `mod.TIMEOUT_SECONDS == 20` checked separately. |
| T7 | BrdMissing | PATH is an empty dir; type `BrdMissing`, message `"brd was not found on PATH"` |
| T8 | BrdFailed carries brd's own message | fake prints the real ProjectNotFoundError line and exits 1; message == brd's `error.message` verbatim |
| T9 | BrdFailed falls back to stderr, then stdout, then exit code (parametrized) | non-JSON stderr only / non-JSON stdout only / nothing, exit 3; messages stderr text / stdout text / `"brd tree exited with 3"` |
| T10 | BrdBadOutput (parametrized) | exit 0 with: `not json`, `[]`, `{"ok": false}`, `{"ok": true}`, `{"ok": true, "data": {}}`; type `BrdBadOutput` |
| T11 | HelperError on usage (parametrized) | no args, two roots, `--help`; type `HelperError`, message starts `usage:`; exit 0; calls log empty |
| T12 | HelperError on an unexpected exception | ROOT is a dir with mode 000, so entering it raises `PermissionError`; type `HelperError`, exit 0, one line. Skipped when running as root (`os.geteuid() == 0`). |
| T13 | every printed line exits 0 | covered by asserting `code == 0` in T1-T12 and T14-T16 |
| T14 | probe in argv order with reasons | roots: ok project, missing path, a file, a dir without `.brd`, a dir with a `.brd` *file*, the ok project again; `projects` == exact list in that order with reasons `not a directory` / `not a directory` / `no .brd marker`, ok entries without a `reason` key, duplicate repeated |
| T15 | probe never runs brd | PATH holds the fake brd; after a probe of several roots the calls log is empty. Also with PATH empty, the probe still prints `ok: true` |
| T16 | probe with no roots | `{"ok": true, "projects": []}` |
| T17 | probe takes a `-`-leading root verbatim | `--probe -x` gives `[{"root": "-x", "ok": false, "reason": "not a directory"}]` |

`tests/architecture` needs no new test. It must still pass. In particular, the helper never
defines `emit`.

## Review focus (failure modes the tests above pin)

1. A ROOT with spaces or non-ASCII must reach brd as the cwd intact (T1 uses "my project", T2
   uses non-ASCII data).
2. brd waiting on stdin would hang the dialog until the timeout (T4).
3. A helper crash must still produce one parseable line, or the store gets nothing (T11, T12).
4. A probe that shells out would make opening the dialog slow on a large registry (T15).
5. Probe rows must keep the caller's exact strings and order, because the store matches them
   to `projectRoots` (T14, T17).

## Verification

`bash tests/run.sh` is green: pytest, including `tests/architecture`, and the QML suites,
which are untouched.
