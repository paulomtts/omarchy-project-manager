# 2.2 start-run.py: detached launcher (card 299ec9c0)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-dispatch-design.md` (S3):
"Dispatch levels" (lines 30-37), "Architecture" bullets 3-4 (lines 95-107),
"Safety" (lines 130-132), "Errors" rows 3-6 (lines 142-145) and "Testing"
bullet 3 (lines 154-156). Parent story d3d879b9. Blocked by 2.1 (a19ca446,
`dispatch-preview.py`), which is already on this branch (commits
8ff9d37..18e8b52) and is not touched.

## Starting point

- `core/backend/runs/` holds `dispatch-preview.py`, `notify.py`,
  `run-control.py`, `runs-logs.py`, `runs-snapshot.py`, `runs-watch.py`.
  `start-run.py` and `tests/core/backend/runs/test_start_run.py` do not exist.
- `core/backend/milestones/run-setup-milestone.py` is the convention to follow
  for the spawn (parent spec lines 95-98): `state_home()` (lines 107-114:
  `XDG_STATE_HOME` only when absolute, else `~/.local/state`), `log_path()`
  (lines 117-124: `makedirs(0o700)` + `chmod 0o700`, sanitized project
  basename, UTC stamp), and the spawn (lines 161-168:
  `os.open(log, O_WRONLY|O_CREAT|O_APPEND, 0o600)`, `os.fchmod(fd, 0o600)`,
  `Popen(argv, cwd=root, stdin=DEVNULL, stdout=fd, stderr=STDOUT,
  start_new_session=True)`, `os.close(fd)`). Unlike it, this helper never
  waits on, signals or kills the child (parent spec lines 99-100).
- `core/backend/runs/dispatch-preview.py` is the nearest sibling for the
  command line, `am` lookup and output style: `shutil.which("am")`, a local
  `failure(kind, message, code=0)`, `TAIL_LINES = 20` / `TAIL_CHARS = 2000`,
  `guarded()` with a `HelperError` catch-all, `Usage` exit 2, exit 0 on every
  other path, a docstring stating the output contract.
- `emit(payload, code=0)` is imported from `core/backend/common/json_line.py`
  after `sys.path.insert(0, <backend dir>)`, never redefined
  (`tests/architecture/test_layers.py:234`; `docs/architecture.md` lines
  191-197). Backend code imports only the stdlib and `core/backend/common`
  (`docs/architecture.md` lines 7-13). `state_home()`/`log_path()` are copied
  locally (not on the guarded list), as `runs-snapshot.py` copies `data_dir()`.
- `core/domain/runs.js` `dispatchPlan` (lines 820-836) produces the three am
  targets this helper accepts: `--milestone ID`, `--card ID`, `--board`.
- Real `am` facts (`am run --help`, `am runs --help`):
  - `am run` takes `--card | --milestone | --board`, `--repo-dir`,
    `--base-branch`, `--branch-prefix` (required with `--card` and
    `--milestone`; optional with `--board`, where each milestone's prefix
    becomes its stem or `<prefix>-<stem>`), `--max-concurrent`, `--verify`
    (repeatable, verbatim, ordered), `--allow-no-verification`, `--dry-run`,
    `--detach`, `--pretty`. It prints its JSON envelope only when it finishes
    (parent spec lines 101-102); a refusal is
    `{"ok": false, "error": {"type", "message"}}` with a non-zero exit.
  - `am runs --repo-dir R` prints `{"ok": true, "data": {"runs": [row, ...]}}`,
    newest first; a row has `id, workflow, repo_dir, base_branch,
    branch_prefix, status, started_at` (`core/domain/runs.js:8`), with
    `started_at` an ISO-8601 UTC string such as `2026-10-01T12:00:00Z`.

## Scope

One new helper, `core/backend/runs/start-run.py`, and its pytest file,
`tests/core/backend/runs/test_start_run.py`. Tests first.

### Out of scope

- `RunStore.qml` dispatch state (`starting → started | failed`),
  `dispatchStart()`, the Run-detail navigation signal, the toast "Started —
  waiting for the run to appear", the project-switch guard (parent spec lines
  108-112, 144-145): the RunStore card(s).
- Per-project dispatch settings in `viewer-state.py` (parent spec lines
  113-117): sibling card 2.3.
- `dispatch-preview.py` (2.1) and every other existing helper and test:
  unchanged. `start-run.py` does not import `dispatch-preview.py`.
- `DispatchDialog.qml`, the Dispatch button, key `d`, `tests/ui/` flows.
- `tests/contract/test_am_shapes.py` (parent spec lines 159-160): the contract
  card.
- `docs/architecture.md`'s `core/backend/runs/` paragraph: S3's docs card.
- S4 item 2 (am printing the run id at launch): this helper polls instead.
- am's own `--detach`: never sent; the helper detaches `am run` itself.

### Decision: one line after the poll, not one at spawn

Parent spec line 99 says the launcher "returns immediately after spawn" with
`{ok, pid, log, started_at}`; lines 101-107 say it then polls for up to 20 s.
The card resolves this: the helper prints **one** JSON line, at the end of the
poll (run found, process exited, or window over). "Returns immediately" means
it never waits for `am run` to finish and never kills it; the `am run`
process outlives the helper, the panel and the shell (parent spec line 100).

## Behaviour

### Command line

```
start-run.py ROOT milestone ID [OPTIONS]
start-run.py ROOT card ID [OPTIONS]
start-run.py ROOT board [OPTIONS]
```

OPTIONS, in any order, exactly as `dispatch-preview.py` accepts them:

| option | value | repeat |
|---|---|---|
| `--base-branch B` | next argument, verbatim | at most once |
| `--branch-prefix P` | next argument, verbatim | at most once |
| `--max-concurrent N` | next argument, verbatim (not checked as a number) | at most once |
| `--verify CMD` | next argument, verbatim (spaces, metacharacters, leading `-` allowed) | any number, order kept |
| `--allow-no-verification` | none | at most once |

- ROOT must be non-empty and must not start with `-`; ID must be non-empty.
  Nothing else is checked: a missing milestone, a missing `--branch-prefix`
  or missing verification are am's refusals, which surface as an early exit.
- Any other shape (no arguments, unknown target word, `milestone`/`card`
  without ID, extra positional, unknown option including `--dry-run`,
  `--detach`, `--pretty`, a valued option last, a once-only option twice,
  empty or `-`-leading ROOT, empty ID) is `Usage`:
  `{"ok": false, "error": {"type": "Usage", "message": USAGE}}`, exit 2,
  nothing spawned, no log created, am not called. USAGE is exactly:

  `usage: start-run.py ROOT (milestone ID | card ID | board) [--base-branch B] [--branch-prefix P] [--max-concurrent N] [--verify CMD]... [--allow-no-verification]`

### am argv

A list after the `am` executable, never a shell, in a fixed order whatever
order the options came in: `run`, the target (`--milestone ID`, `--card ID`
or `--board`), `--repo-dir ROOT`, then `--base-branch`, `--branch-prefix`,
`--max-concurrent`, every `--verify` pair in order, `--allow-no-verification`.
Options not given are not sent. `--dry-run`, `--detach` and `--pretty` are
never sent.

| call | am argv |
|---|---|
| `/p milestone m1 --branch-prefix m3` | `["run", "--milestone", "m1", "--repo-dir", "/p", "--branch-prefix", "m3"]` |
| `/p card c9 --branch-prefix m3` | `["run", "--card", "c9", "--repo-dir", "/p", "--branch-prefix", "m3"]` |
| `/p board` | `["run", "--board", "--repo-dir", "/p"]` |
| `/p milestone m1 --verify "uv run pytest" --max-concurrent 2 --branch-prefix m3 --base-branch main --verify "-x" --allow-no-verification` | `["run", "--milestone", "m1", "--repo-dir", "/p", "--base-branch", "main", "--branch-prefix", "m3", "--max-concurrent", "2", "--verify", "uv run pytest", "--verify", "-x", "--allow-no-verification"]` |

### Spawn

In this order, after the arguments are valid:

1. `am` not on `PATH` → `AmMissing` (below). No log is created.
2. The log: directory `<state_home>/omarchy-project-manager/am-runs/`, created
   with mode `0700` and `chmod`ed to `0700` even if it existed. `state_home` is
   `XDG_STATE_HOME` when it is an absolute path, else `~/.local/state` (a
   relative or empty value is ignored). File name
   `<YYYYMMDDTHHMMSSZ>-<project>-<8 lowercase hex>.log`: UTC stamp, `project`
   = basename of `abspath(ROOT)` with every character outside `[A-Za-z0-9._-]`
   replaced by `_` (`project` if that is empty), and 8 random hex digits so two
   launches in the same second never share a file. Opened `O_WRONLY | O_CREAT |
   O_EXCL`, mode `0600`, then `fchmod 0600` (a umask cannot widen or narrow
   it). The reported `log` is an absolute path.
3. `started_at` = the current UTC time **floored to the whole second**, taken
   just before the spawn, formatted `YYYY-MM-DDTHH:MM:SSZ`. Flooring makes a
   run that am stamps within the same second (am's `started_at` has
   one-second precision) count as "at or after spawn".
4. `Popen([am, *argv], cwd=ROOT, stdin=DEVNULL, stdout=<log fd>,
   stderr=STDOUT, start_new_session=True)`, with the helper's environment
   unchanged (am finds its data through the inherited `HOME`/`XDG_DATA_HOME`).
   The helper closes its copy of the log fd right after `Popen` and keeps no
   pipe to the child. The child is in its own session and process group, so a
   signal to the helper's group (HelperRunner's SIGTERM, the panel closing)
   does not reach it.
5. `Popen` raises `OSError` (ROOT does not exist or is not a directory, am
   cannot be executed) → `SpawnFailed` (below). The helper appends one line,
   `start-run: could not start am: <error text>`, to the log first, so the
   reported log is not empty.

The helper never calls `wait()`, `kill()`, `terminate()`, `killpg` or
`send_signal` on the child. It only uses `Popen.poll()`.

### Finding the run id

After a successful spawn the helper loops until `POLL_WINDOW = 20` seconds
(monotonic clock, from the spawn) have passed, sleeping `POLL_INTERVAL = 0.5`
seconds between ticks. Both are module constants (tests shorten them). Each
tick, in this order:

1. Run `am runs --repo-dir ROOT` (argv list, `stdin=DEVNULL`, captured
   output, `RUNS_TIMEOUT = 5` s). If it prints an envelope
   `{"ok": true, "data": {"runs": [...]}}`, look for a **matching** row:
   - the row is an object whose `id` is a non-empty string;
   - its `started_at` parses as ISO-8601 (`Z` or an offset; a value without
     an offset is UTC) and is ≥ the spawn's `started_at`;
   - prefix rule:
     - `milestone`/`card` with `--branch-prefix P`: the row's `branch_prefix`
       equals `P`;
     - `board` with `--branch-prefix P`: the row's `branch_prefix` equals `P`
       or starts with `P-` (am derives `<prefix>-<stem>` per milestone);
     - no `--branch-prefix` given (board; or a milestone/card am will refuse):
       any `branch_prefix`.

   If several rows match, the one with the **earliest** `started_at` wins (on
   a tie, the one listed last, i.e. oldest in am's newest-first order): it is
   the run this launch started first. A match ends the loop with **Started**,
   even if the child has since exited (the run exists; Run detail shows how it
   ended).
   Anything else from `am runs` — non-zero exit with no envelope, `ok: false`,
   bad JSON, a missing or non-list `runs`, a timeout, an `OSError` — is
   ignored for this tick; it never fails the launch.
2. If no row matched and `Popen.poll()` is not `None`, the child has exited:
   **Early exit**.
3. Otherwise sleep and tick again. One last tick runs at or after the deadline
   before giving up, so a run that appears in the final interval is found.

When the window ends with no match and the child still running: **Not
visible yet**. The worst-case wall time is about `POLL_WINDOW + RUNS_TIMEOUT`.

### Output: exactly one JSON line on every path

Every success and post-spawn failure line carries `pid` (int), `log`
(absolute path) and `started_at` (the spawn time string above).

1. **Started** — `{"ok": true, "pid": P, "log": L, "started_at": S,
   "run_id": ID, "message": ""}`, exit 0.
2. **Not visible yet** — `{"ok": true, "pid": P, "log": L, "started_at": S,
   "run_id": null, "message": "started, run not visible yet"}`, exit 0. The
   child is left running.
3. **Early exit** — `{"ok": false, "error": E, "pid": P, "log": L,
   "started_at": S, "exit_code": C, "log_tail": T}`, exit 0. `exit_code` is
   the child's return code (0 included: an am that finishes at once without a
   visible run is still reported here). `log_tail` is the log's content
   (decoded as UTF-8 with replacement) with trailing whitespace stripped, its
   last `TAIL_LINES = 20` lines, of those the last `TAIL_CHARS = 2000`
   characters (`""` for an empty log). `E`:
   - if the log's last non-empty line parses as a JSON object with
     `"ok": false` and an object `error`, that `error` object unchanged (so a
     `ClaimedError`, `MilestoneNotFoundError` or missing-verification refusal
     reaches the dialog with its own type and message; parent spec lines
     128-129, 143);
   - otherwise `{"type": "AmExited", "message": "am run exited C before its
     run appeared."}`.
4. **SpawnFailed** — `{"ok": false, "error": {"type": "SpawnFailed",
   "message": "Could not start am run: <error text>"}, "log": L}`, exit 0
   (parent spec line 142).
5. **AmMissing** — `{"ok": false, "error": {"type": "AmMissing", "message":
   "am is not installed."}}`, exit 0.
6. **HelperError** — anything unexpected before or during the spawn (the log
   directory cannot be created, any raised exception) →
   `{"ok": false, "error": {"type": "HelperError", "message": "The launch
   failed: <reason>"}}`, exit 0; `<reason>` is the exception text, else its
   class name. If an exception is raised after a successful spawn (during
   polling), the line still says `HelperError` but also carries `pid`, `log`
   and `started_at`, so the store can tell the run may be going.
7. **Usage** — above, exit 2.

`SystemExit` is re-raised as in `dispatch-preview.py`. A SIGTERM/SIGKILL to the
helper during polling ends it without a line; the child keeps running and the
Runs screen finds it through S1's watch (parent spec lines 105-106, 130-132).

## Tests (all in `tests/core/backend/runs/test_start_run.py`)

Tier: **backend pytest** with a stub `am` (parent spec lines 154-156;
`docs/architecture.md` "How to add → A helper script": pytest under
`tests/core/backend/<domain>/`). Right tier because the contract is argv in,
a detached process, a log file and one JSON line out; no Qt is involved, and
the real `am` cannot be made to refuse, crash or delay on demand (and must
never start a real run). Plain pytest functions, no classes, modelled on
`test_dispatch_preview.py` and `test_run_control.py`.

Fixture world: a temp `PATH` (`tmpbin:/usr/bin:/bin`) holding a fake `am`,
temp `HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` and `FAKE_AM_DIR`, and a temp
project dir as ROOT. The fake `am`:
- appends its argv as JSON to `calls.log`;
- `run`: writes its pid to `run.pid`, its session id to `run.sid`, its cwd to
  `run.cwd`; prints `run.out` to stdout and `run.err` to stderr if present;
  then, if `run.rows` is present, writes `runs.json` from it (so the run
  "appears" after spawn); sleeps `run.sleep` seconds (default 0); writes the
  marker file `run.done`; exits with `run.code` (default 0);
- `runs`: prints `runs.out` verbatim if present, else
  `{"ok": true, "data": {"runs": <runs.json or []>}}`, exits `runs.code`
  (default 0).
Every `run.sleep` is bounded (≤ 5 s) and each test that leaves a child running
kills its process group in teardown (`os.killpg(sid, SIGKILL)` by the recorded
pid), so no fake outlives the test. In-process tests load the module with
`importlib` (dashed file name) and shorten `POLL_WINDOW`/`POLL_INTERVAL` with
`monkeypatch`; subprocess tests run `sys.executable SCRIPT` and assert stdout
is exactly one JSON line and the exit code.

Argv:
1. `test_milestone_argv` — exact argv, no `--dry-run`/`--detach`/`--pretty`.
2. `test_card_argv` — `card c9 --branch-prefix m3`: `--card c9`.
3. `test_board_argv` — `--board`, no `--milestone`.
4. `test_options_forwarded_in_fixed_order` — the fourth table row.
5. `test_verify_values_verbatim` — spaces, `;`, `$HOME`, leading `-`, empty
   string arrive as single unaltered elements.

Detached spawn:
6. `test_child_runs_in_its_own_session` — `run.sid` differs from the helper's
   `os.getsid(0)` and equals the child's pid (session leader); `run.cwd` is
   ROOT.
7. `test_child_stdin_is_devnull` — the fake records `os.readlink("/proc/self/fd/0")`
   == `/dev/null`.
8. `test_child_survives_the_helper_group_being_killed` — a driver process
   (own session) runs `guarded` with a matching row served at once, prints its
   line, then sleeps; the test reads the line, `killpg`s the driver's group
   with SIGKILL, and the fake (`run.sleep` 2) still writes `run.done`.
9. `test_helper_returns_while_child_runs` — subprocess run, fake sleeps 5 s
   and serves a matching row: the helper exits in well under 5 s with
   **Started**, and `run.done` does not exist yet when it returns.
10. `test_helper_never_signals_child` — read the module source: no
    `.wait(`, `.kill(`, `.terminate(`, `killpg`, `send_signal` (a guard for
    "never waits or kills", parent spec line 100).

Run-id discovery:
11. `test_finds_run_by_prefix_and_start_time` — rows: an older run with the
    same prefix, a newer run with another prefix, a newer run with the same
    prefix → that run's id, `message: ""`, `pid` equals `run.pid`.
12. `test_started_at_same_second_counts` — the row's `started_at` is the
    helper's own floored `started_at` string → found.
13. `test_started_at_with_offset_parsed` — `+00:00` and a naive value both
    compare as UTC; an unparseable `started_at` row is skipped.
14. `test_board_prefix_rule` — board with `--branch-prefix x`: `x-m3`
    matches, `xy-m3` does not; board with no prefix matches any prefix.
15. `test_earliest_matching_run_wins` — two matching rows: the earlier
    `started_at` wins.
16. `test_runs_errors_are_retried` — `runs` fails (exit 1, no envelope) for
    the first ticks, then serves the row (fake switches on a call counter):
    found; no failure line.
17. `test_run_found_even_if_child_exited` — child exits 0 at once but the row
    is there: **Started**, not early exit.
18. `test_not_visible_yet` — window shortened, `runs` always empty, child
    sleeping: `ok: true`, `run_id: null`, `message:
    "started, run not visible yet"`, child still alive afterwards.

Early exit:
19. `test_early_exit_with_am_refusal` — `run.out` holds a `ClaimedError`
    envelope, exit 3: `error` is that object unchanged, `exit_code: 3`,
    `log_tail` contains the envelope line.
20. `test_early_exit_without_envelope` — 30 lines on stderr, exit 2:
    `AmExited` with `exit_code: 2`, `log_tail` the last 20 lines; a 5000-char
    line cut to its last 2000.
21. `test_early_exit_zero` — exit 0, no row: `AmExited`, `exit_code: 0`.
22. `test_early_exit_empty_log` — nothing printed, exit 1: `log_tail: ""`.

Log:
23. `test_log_placement_and_modes` — log under
    `$XDG_STATE_HOME/omarchy-project-manager/am-runs/`, dir mode `0700` (also
    when it pre-existed as `0755`), file mode `0600` under a `0o000` and a
    `0o077` umask; name matches `^\d{8}T\d{6}Z-<project>-[0-9a-f]{8}\.log$`;
    child stdout and stderr both land in it.
24. `test_relative_xdg_state_home_ignored` — `XDG_STATE_HOME=rel`: log under
    `$HOME/.local/state/...`, nothing created under the cwd.
25. `test_project_name_sanitized` — ROOT basename `my proj;x` → `my_proj_x`.
26. `test_two_launches_get_two_logs` — two launches in the same second: two
    distinct files.

Errors:
27. `test_am_missing` — no `am` on `PATH`: `AmMissing`, no log dir created.
28. `test_spawn_failed_bad_root` — ROOT does not exist: `SpawnFailed` with
    `log` set, the file exists, mode `0600`, and holds the
    `start-run: could not start am:` line; `calls.log` empty.
29. `test_unexpected_error_is_helper_error` — log dir creation made to fail
    (`XDG_STATE_HOME` points under a regular file): `HelperError` starting
    `The launch failed: `.
30. `test_usage_shapes` — parametrized, each exit 2, exact USAGE, empty
    `calls.log`, no log dir: `[]`, `["/p"]`, `["/p", "story", "x"]`,
    `["/p", "milestone"]`, `["/p", "card", ""]`, `["", "board"]`,
    `["-p", "board"]`, `["/p", "board", "extra"]`,
    `["/p", "milestone", "m1", "--dry-run"]`, `["/p", "board", "--detach"]`,
    `["/p", "board", "--verify"]`,
    `["/p", "board", "--base-branch", "a", "--base-branch", "b"]`.

Architecture: `tests/architecture` stays green (no second `def emit(` etc.;
only stdlib and `common` imported).

## Hand-off notes for the planner

- Follow the writing-plans format; two or three tasks (parse + argv + spawn +
  log with tests 1-10 and 23-30; discovery with 11-18; early exit with 19-22),
  each red→green→commit.
- Local functions modelled on the siblings: `failure`, `parse`, `run_argv`,
  `state_home`, `log_path`, `spawn`, `matches(row, target, prefix, since)`,
  `find_run`, `log_tail`, `early_exit`, `main`, `guarded`. Do not import
  `dispatch-preview.py`; do not move anything to `common`; do not redefine
  `emit`.
- Module constants: `POLL_WINDOW = 20`, `POLL_INTERVAL = 0.5`,
  `RUNS_TIMEOUT = 5`, `TAIL_LINES = 20`, `TAIL_CHARS = 2000`, `LOG_DIR_NAME =
  "am-runs"`.
- Verification: `uv run --with pytest python3 -m pytest
  tests/core/backend/runs/test_start_run.py tests/architecture -q` while
  iterating; `bash tests/run.sh` green at the end.

---

# start-run.py Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A backend helper, `core/backend/runs/start-run.py`, that starts `am run` detached (own session, log file, never waited on or killed), finds the id of the run it started by polling `am runs`, and prints exactly one JSON line describing the outcome.

**Architecture:** One stdlib-only script modelled on `dispatch-preview.py` (command line, `failure`, `guarded`) and `run-setup-milestone.py` (`state_home`, `log_path`, the detached `Popen`). After the spawn a polling loop checks `Popen.poll()` and `am runs --repo-dir ROOT` every `POLL_INTERVAL` s for at most `POLL_WINDOW` s and picks one of: Started, Not visible yet, Early exit. Tests are backend pytest with a fake `am` on a temp `PATH`; in-process tests load the dashed module with `importlib` and shorten the poll constants.

**Tech Stack:** Python 3 stdlib (`subprocess`, `os`, `datetime`, `secrets`), pytest (run through `uv run --with pytest`).

**Spec:** `docs/superpowers/specs/2-2-start-run-py-299ec9c0.md` (prepended above; the plan argues from it).

## Global Constraints

- Backend code imports only the stdlib and `core/backend/common`; `emit` is imported from `common.json_line` after `sys.path.insert(0, <backend dir>)`, never redefined (no `def emit(` anywhere in `core/`).
- `start-run.py` does not import `dispatch-preview.py`; nothing moves to `common`; no other existing file changes.
- USAGE is exactly: `usage: start-run.py ROOT (milestone ID | card ID | board) [--base-branch B] [--branch-prefix P] [--max-concurrent N] [--verify CMD]... [--allow-no-verification]`
- Module constants: `POLL_WINDOW = 20`, `POLL_INTERVAL = 0.5`, `RUNS_TIMEOUT = 5`, `TAIL_LINES = 20`, `TAIL_CHARS = 2000`, `LOG_DIR_NAME = "am-runs"`.
- `--dry-run`, `--detach` and `--pretty` are never sent to am; argv is a list, never a shell.
- The module source never contains `.wait(`, `.kill(`, `.terminate(`, `killpg` or `send_signal` (not even in comments or the docstring); the child is only ever `poll()`ed.
- Log dir `<state_home>/omarchy-project-manager/am-runs/` mode `0700` (chmod even if it existed); log file `O_WRONLY | O_CREAT | O_EXCL`, `0600`, then `fchmod 0600`; name `<YYYYMMDDTHHMMSSZ>-<project>-<8 lowercase hex>.log`.
- `started_at` = UTC now floored to the second, `YYYY-MM-DDTHH:MM:SSZ`.
- Exactly one JSON line on every path; exit 0 on every path except Usage (exit 2).
- The script file is executable (mode `100755`, like its siblings).
- Verification: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_start_run.py tests/architecture -q` while iterating; `bash tests/run.sh` green at the end.

## Review Focus

1. **am exits while `am runs` is being queried, its row already written** — a person expects "Started" with the run id, not an "am exited" error. The tick reads `poll()` *before* the query (a deliberate refinement of the spec's tick order: an exit observed before the query means the row, if any, was already written). Test: `test_child_exiting_during_query_is_not_early_exit` (Task 3).
2. **`am runs` prints junk, `ok: false`, a non-list `runs`, or rows that are not objects / lack a string id / lack `started_at`** — expected: ignored, the launch goes on to "not visible yet", no crash and no HelperError. Test: `test_runs_bad_output_ignored` (Task 3).
3. **An unexpected exception after the spawn** — expected: a HelperError line that still carries `pid`, `log` and `started_at`, and the child is left running. Test: `test_error_after_spawn_carries_the_launch` (Task 1).
4. **ROOT given with a trailing slash** — expected: the log is named after the directory (`my_proj_x`), not the `project` fallback. Test: folded into `test_project_name_sanitized` (Task 1).
5. **am's refusal envelope followed by blank lines, or a last line that looks like JSON but is not a refusal** — expected: the refusal still reaches the dialog unchanged; a non-refusal falls back to `AmExited`. Tests: `test_early_exit_with_am_refusal` (trailing `"\n\n"`) and `test_last_line_not_a_refusal` (Task 2).

## File Structure

- Create `core/backend/runs/start-run.py` — the helper: command line, am argv, log, detached spawn, poll loop, one output line.
- Create `tests/core/backend/runs/test_start_run.py` — all tests, with the fake `am` and fixture world.

Tasks:
1. Launch: command line, argv, log, detached spawn, errors, and a poll loop that only watches the child (outcomes Not visible yet / bare Early exit). Tests 1-7, 10, 18, 23-30, Review Focus 3-4.
2. Early-exit report: am's refusal passthrough and `log_tail`. Tests 19-22, Review Focus 5.
3. Run-id discovery: `am runs` polling, `matches`, `find_run`. Tests 8, 9, 11-17, Review Focus 1-2.

---

### Task 1: Launch — command line, log, detached spawn, errors

**Files:**
- Create: `core/backend/runs/start-run.py`
- Create: `tests/core/backend/runs/test_start_run.py`

**Interfaces:**
- Consumes: `emit(payload, code=0)` from `core/backend/common/json_line.py` (prints `json.dumps(payload)`, returns `code`).
- Produces (later tasks rely on these exact names):
  - constants `USAGE`, `VALUED`, `TARGETS`, `POLL_WINDOW`, `POLL_INTERVAL`, `RUNS_TIMEOUT`, `TAIL_LINES`, `TAIL_CHARS`, `LOG_DIR_NAME`, `STAMP`, `NOT_VISIBLE`;
  - `failure(kind, message, code=0, **extra) -> int`;
  - `parse(argv) -> (root, target, ident, options) | None` (`target` in `"milestone" | "card" | "board"`, `ident` None for board, `options["--verify"]` a list, VALUED flags → str, `"--allow-no-verification"` → True);
  - `run_argv(root, target, ident, options) -> list[str]`;
  - `state_home() -> str`, `log_path(root) -> str` (absolute, directory created);
  - `utc_now() -> datetime` (aware UTC; tests monkeypatch it);
  - `class SpawnError(Exception)`, `spawn(am, argv, root, log) -> (Popen, datetime started)`;
  - `early_exit(proc, launch) -> int` (Task 2 replaces its body);
  - `watch(proc, launch, deadline) -> int` (Task 3 replaces it with `watch(proc, am, root, target, prefix, launch, started, deadline)`);
  - `main(argv, launch) -> int` (`launch` is a dict filled with `pid`, `log`, `started_at` right after the spawn);
  - `guarded(argv) -> int`.
  - Test helpers in the test file: `world` fixture (keys `tmp, bin, am, home, data, state, project`), `env_for`, `run`, `calls`, `run_calls`, `load_helper`, `use_world`, `fast_helper`, `one_line`, `wait_for`, `read_pid`, `CLAIMED`, `USAGE_LINE`.

- [ ] **Step 1: Write the failing tests**

Create `tests/core/backend/runs/test_start_run.py`:

```python
"""start-run.py: `am run` detached, the run id it started found through `am runs`,
one JSON line on every path.

Hermetic: a fake `am` lives on a temp PATH and is driven by fixture files in
FAKE_AM_DIR, appending each call's argv to calls.log; HOME, XDG_DATA_HOME and
XDG_STATE_HOME are temp. The real `am` and real data are never touched, and no
fake outlives its test (the world fixture SIGKILLs a still-running fake's group).
"""
import datetime
import importlib.util
import json
import os
import re
import select
import signal
import stat
import subprocess
import sys
import time

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "..")
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "start-run.py")

# The fake am logs its argv to calls.log, then:
# - `run`: writes run.pid, run.sid (its session id), run.cwd and run.stdin (what
#   fd 0 points at); copies run.out to stdout and run.err to stderr (flushed at
#   once, so they are in the log while it sleeps); if run.rows exists, writes it
#   to runs.json with every "NOW" replaced by its own UTC time to the second (so
#   the run "appears" after the spawn); sleeps run.sleep seconds (default 0);
#   writes run.done; exits run.code (default 0).
# - `runs`: counts its calls in runs.count; while the count is <= runs.fail
#   (default 0) it fails like a locked database (stderr, exit 1, no envelope);
#   else prints runs.out verbatim if present, otherwise
#   {"ok": true, "data": {"runs": <runs.json or []>}}, and exits runs.code.
# Every fixture file it writes is replaced atomically, so a reader never sees half.
FAKE_AM = '''#!/usr/bin/env python3
import datetime, json, os, sys, time
d = os.environ["FAKE_AM_DIR"]
args = sys.argv[1:]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(args) + "\\n")


def path(name):
    return os.path.join(d, name)


def read(name, default=None):
    if not os.path.exists(path(name)):
        return default
    with open(path(name)) as f:
        return f.read()


def write(name, text):
    with open(path(name + ".tmp"), "w") as f:
        f.write(text)
    os.replace(path(name + ".tmp"), path(name))


if args[:1] == ["run"]:
    write("run.pid", str(os.getpid()))
    write("run.sid", str(os.getsid(0)))
    write("run.cwd", os.getcwd())
    write("run.stdin", os.readlink("/proc/self/fd/0"))
    if os.path.exists(path("run.out")):
        with open(path("run.out"), "rb") as f:
            sys.stdout.buffer.write(f.read())
    if os.path.exists(path("run.err")):
        with open(path("run.err"), "rb") as f:
            sys.stderr.buffer.write(f.read())
    sys.stdout.flush()
    sys.stderr.flush()
    rows = read("run.rows")
    if rows is not None:
        now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        write("runs.json", rows.replace("NOW", now))
    time.sleep(float(read("run.sleep", "0")))
    write("run.done", "")
    sys.exit(int(read("run.code", "0")))
if args[:1] == ["runs"]:
    count = int(read("runs.count", "0")) + 1
    write("runs.count", str(count))
    if count <= int(read("runs.fail", "0")):
        sys.stderr.write("am runs: database is locked\\n")
        sys.exit(1)
    out = read("runs.out")
    if out is None:
        out = json.dumps({"ok": True, "data": {"runs": json.loads(read("runs.json", "[]"))}}) + "\\n"
    sys.stdout.write(out)
    sys.exit(int(read("runs.code", "0")))
sys.exit(2)
'''

USAGE_LINE = {"ok": False, "error": {"type": "Usage", "message":
              "usage: start-run.py ROOT (milestone ID | card ID | board) [--base-branch B]"
              " [--branch-prefix P] [--max-concurrent N] [--verify CMD]..."
              " [--allow-no-verification]"}}
CLAIMED = {"ok": False, "error": {"type": "ClaimedError",
                                  "message": "card c1 is claimed by run r9"}}
STARTED_AT_RE = r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$"


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am, its fixture dir, temp HOME/XDG dirs and a project dir."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "am", FAKE_AM)
    amdir = tmp_path / "am"
    amdir.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    project = tmp_path / "proj"
    project.mkdir()
    yield {"tmp": tmp_path, "bin": bindir, "am": amdir, "home": home,
           "data": tmp_path / "data", "state": tmp_path / "state", "project": project}
    pid_file = amdir / "run.pid"
    if pid_file.exists() and not (amdir / "run.done").exists():
        try:
            # The fake is a session leader, so its pid is its process group id.
            os.killpg(int(pid_file.read_text()), signal.SIGKILL)
        except (ProcessLookupError, PermissionError, ValueError):
            pass


def env_for(world, **extra):
    e = {
        "PATH": str(world["bin"]) + os.pathsep + "/usr/bin" + os.pathsep + "/bin",
        "HOME": str(world["home"]),
        "XDG_DATA_HOME": str(world["data"]),
        "XDG_STATE_HOME": str(world["state"]),
        "FAKE_AM_DIR": str(world["am"]),
    }
    e.update(extra)
    return e


def run(world, args, **extra):
    """Run the helper; assert stdout is exactly one JSON line; return (exit, payload)."""
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True,
                       env=env_for(world, **extra), timeout=60)
    lines = p.stdout.splitlines()
    assert len(lines) == 1, (p.stdout, p.stderr)
    return p.returncode, json.loads(lines[0])


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def run_calls(world):
    return [c for c in calls(world) if c[:1] == ["run"]]


def load_helper():
    """The script as a module (its name has a hyphen, so no plain import)."""
    spec = importlib.util.spec_from_file_location("start_run", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def use_world(world, monkeypatch):
    for key, value in env_for(world).items():
        monkeypatch.setenv(key, value)


def fast_helper(monkeypatch, world, window=5, interval=0.05):
    """The module, in the world's environment, with a short poll window and interval."""
    helper = load_helper()
    monkeypatch.setattr(helper, "POLL_WINDOW", window)
    monkeypatch.setattr(helper, "POLL_INTERVAL", interval)
    use_world(world, monkeypatch)
    return helper


def one_line(capsys):
    lines = capsys.readouterr().out.splitlines()
    assert len(lines) == 1, lines
    return json.loads(lines[0])


def wait_for(path, timeout=10):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if path.exists():
            return True
        time.sleep(0.05)
    return path.exists()


def read_pid(world):
    assert wait_for(world["am"] / "run.pid")
    return int((world["am"] / "run.pid").read_text())


# --- am argv -----------------------------------------------------------------

def test_milestone_argv(world):
    root = str(world["project"])
    code, _ = run(world, [root, "milestone", "m1", "--branch-prefix", "m3"])
    assert code == 0
    made = run_calls(world)
    assert made == [["run", "--milestone", "m1", "--repo-dir", root, "--branch-prefix", "m3"]]
    for never in ("--dry-run", "--detach", "--pretty"):
        assert never not in made[0]


def test_card_argv(world):
    root = str(world["project"])
    code, _ = run(world, [root, "card", "c9", "--branch-prefix", "m3"])
    assert code == 0
    assert run_calls(world) == [["run", "--card", "c9", "--repo-dir", root, "--branch-prefix", "m3"]]


def test_board_argv(world):
    root = str(world["project"])
    code, _ = run(world, [root, "board"])
    assert code == 0
    made = run_calls(world)
    assert made == [["run", "--board", "--repo-dir", root]]
    assert "--milestone" not in made[0]


def test_options_forwarded_in_fixed_order(world):
    root = str(world["project"])
    code, _ = run(world, [root, "milestone", "m1",
                          "--verify", "uv run pytest", "--max-concurrent", "2",
                          "--branch-prefix", "m3", "--base-branch", "main",
                          "--verify", "-x", "--allow-no-verification"])
    assert code == 0
    assert run_calls(world) == [["run", "--milestone", "m1", "--repo-dir", root,
                                 "--base-branch", "main", "--branch-prefix", "m3",
                                 "--max-concurrent", "2",
                                 "--verify", "uv run pytest", "--verify", "-x",
                                 "--allow-no-verification"]]


def test_verify_values_verbatim(world):
    # Spaces, shell metacharacters, a leading dash and an empty string each arrive
    # as one unaltered argv element: no shell, no validation by the helper.
    root = str(world["project"])
    values = ["uv run pytest -q", "make test; echo done", "echo $HOME", "-x", ""]
    args = [root, "board"]
    for v in values:
        args += ["--verify", v]
    code, _ = run(world, args)
    assert code == 0
    expected = ["run", "--board", "--repo-dir", root]
    for v in values:
        expected += ["--verify", v]
    assert run_calls(world) == [expected]


# --- detached spawn -------------------------------------------------------------

def test_child_runs_in_its_own_session(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world, window=0.3)
    (world["am"] / "run.sleep").write_text("5")
    assert helper.guarded([str(world["project"]), "board"]) == 0
    out = one_line(capsys)
    pid = read_pid(world)
    assert out["pid"] == pid
    assert wait_for(world["am"] / "run.stdin")
    sid = int((world["am"] / "run.sid").read_text())
    assert sid == pid
    assert sid != os.getsid(0)
    assert (os.path.realpath((world["am"] / "run.cwd").read_text())
            == os.path.realpath(world["project"]))


def test_child_stdin_is_devnull(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world, window=0.3)
    (world["am"] / "run.sleep").write_text("5")
    assert helper.guarded([str(world["project"]), "board"]) == 0
    one_line(capsys)
    assert wait_for(world["am"] / "run.stdin")
    assert (world["am"] / "run.stdin").read_text() == "/dev/null"


def test_helper_never_signals_child():
    # A guard for "never waits on or kills am run": the child outlives the helper.
    with open(SCRIPT) as f:
        source = f.read()
    for token in (".wait(", ".kill(", ".terminate(", "killpg", "send_signal"):
        assert token not in source, token


def test_not_visible_yet(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world, window=0.3)
    (world["am"] / "run.sleep").write_text("5")
    assert helper.guarded([str(world["project"]), "milestone", "m1", "--branch-prefix", "m3"]) == 0
    out = one_line(capsys)
    pid = read_pid(world)
    assert out == {"ok": True, "pid": pid, "log": out["log"], "started_at": out["started_at"],
                   "run_id": None, "message": "started, run not visible yet"}
    assert re.match(STARTED_AT_RE, out["started_at"])
    os.kill(pid, 0)  # still alive: raises ProcessLookupError otherwise
    assert not (world["am"] / "run.done").exists()


def test_error_after_spawn_carries_the_launch(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world)

    def boom(proc, launch):
        raise RuntimeError("boom")

    monkeypatch.setattr(helper, "early_exit", boom)
    assert helper.guarded([str(world["project"]), "board"]) == 0
    out = one_line(capsys)
    assert out["ok"] is False
    assert out["error"] == {"type": "HelperError", "message": "The launch failed: boom"}
    assert out["pid"] == read_pid(world)
    assert os.path.exists(out["log"])
    assert re.match(STARTED_AT_RE, out["started_at"])


# --- log -------------------------------------------------------------------------

def test_log_placement_and_modes(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world)
    logs = world["state"] / "omarchy-project-manager" / "am-runs"
    logs.mkdir(parents=True)
    logs.chmod(0o755)
    (world["am"] / "run.out").write_text("to stdout\n")
    (world["am"] / "run.err").write_text("to stderr\n")
    for mask in (0o000, 0o077):
        old = os.umask(mask)
        try:
            assert helper.guarded([str(world["project"]), "board"]) == 0
        finally:
            os.umask(old)
        out = one_line(capsys)
        assert out["ok"] is False  # am exited at once: an early exit, so its output is all in
        log = out["log"]
        assert os.path.isabs(log)
        assert os.path.dirname(log) == str(logs)
        assert stat.S_IMODE(os.stat(logs).st_mode) == 0o700
        assert stat.S_IMODE(os.stat(log).st_mode) == 0o600
        assert re.match(r"^\d{8}T\d{6}Z-proj-[0-9a-f]{8}\.log$", os.path.basename(log))
        with open(log) as f:
            text = f.read()
        assert "to stdout" in text
        assert "to stderr" in text


def test_relative_xdg_state_home_ignored(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world)
    cwd = world["tmp"] / "cwd"
    cwd.mkdir()
    monkeypatch.chdir(cwd)
    monkeypatch.setenv("XDG_STATE_HOME", "rel")
    assert helper.guarded([str(world["project"]), "board"]) == 0
    log = one_line(capsys)["log"]
    assert os.path.dirname(log) == str(world["home"] / ".local" / "state"
                                       / "omarchy-project-manager" / "am-runs")
    assert list(cwd.iterdir()) == []


def test_project_name_sanitized(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world)
    odd = world["tmp"] / "my proj;x"
    odd.mkdir()
    # A trailing slash still names the log after the directory, not "project".
    assert helper.guarded([str(odd) + "/", "board"]) == 0
    name = os.path.basename(one_line(capsys)["log"])
    assert re.match(r"^\d{8}T\d{6}Z-my_proj_x-[0-9a-f]{8}\.log$", name), name


def test_two_launches_get_two_logs(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world)
    fixed = time.gmtime(1790000000)
    monkeypatch.setattr(helper.time, "gmtime", lambda *a: fixed)  # same second, twice
    paths = []
    for _ in range(2):
        assert helper.guarded([str(world["project"]), "board"]) == 0
        paths.append(one_line(capsys)["log"])
    assert paths[0] != paths[1]
    assert os.path.basename(paths[0])[:16] == os.path.basename(paths[1])[:16]
    assert all(os.path.exists(p) for p in paths)


# --- errors ------------------------------------------------------------------------

def test_am_missing(world):
    empty = world["tmp"] / "empty"
    empty.mkdir()
    code, out = run(world, [str(world["project"]), "board"], PATH=str(empty))
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmMissing", "message": "am is not installed."}}
    assert not (world["state"] / "omarchy-project-manager").exists()


def test_spawn_failed_bad_root(world):
    code, out = run(world, [str(world["tmp"] / "missing"), "board"])
    assert code == 0
    assert set(out) == {"ok", "error", "log"}
    assert out["ok"] is False
    assert out["error"]["type"] == "SpawnFailed"
    assert out["error"]["message"].startswith("Could not start am run: ")
    assert stat.S_IMODE(os.stat(out["log"]).st_mode) == 0o600
    with open(out["log"]) as f:
        assert f.read().startswith("start-run: could not start am: ")
    assert calls(world) == []


def test_unexpected_error_is_helper_error(world):
    blocker = world["tmp"] / "afile"
    blocker.write_text("")
    code, out = run(world, [str(world["project"]), "board"],
                    XDG_STATE_HOME=str(blocker / "state"))
    assert code == 0
    assert set(out) == {"ok", "error"}
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The launch failed: ")
    assert calls(world) == []


@pytest.mark.parametrize("args", [
    [],
    ["/p"],
    ["/p", "story", "x"],
    ["/p", "milestone"],
    ["/p", "card", ""],
    ["", "board"],
    ["-p", "board"],
    ["/p", "board", "extra"],
    ["/p", "milestone", "m1", "--dry-run"],
    ["/p", "board", "--detach"],
    ["/p", "board", "--pretty"],
    ["/p", "board", "--verify"],
    ["/p", "board", "--base-branch", "a", "--base-branch", "b"],
    ["/p", "board", "--allow-no-verification", "--allow-no-verification"],
])
def test_usage_shapes(world, args):
    code, out = run(world, args)
    assert code == 2
    assert out == USAGE_LINE
    assert calls(world) == []
    assert not (world["state"] / "omarchy-project-manager").exists()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_start_run.py -q`
Expected: FAIL — every test except `test_helper_never_signals_child` errors or fails because `core/backend/runs/start-run.py` does not exist (`FileNotFoundError` in `load_helper`/`open`, or the subprocess prints nothing so `len(lines) == 1` fails). `test_helper_never_signals_child` errors with `FileNotFoundError` too.

- [ ] **Step 3: Write the implementation**

Create `core/backend/runs/start-run.py`. The docstring already states the full contract that Tasks 2 and 3 complete (refusal passthrough, `log_tail`, run discovery); keep it verbatim. It must not contain any of the tokens `test_helper_never_signals_child` forbids.

```python
#!/usr/bin/env python3
"""Start a dispatch: `am run`, detached, and the id of the run it started.

    start-run.py ROOT (milestone ID | card ID | board) [--base-branch B] [--branch-prefix P]
                 [--max-concurrent N] [--verify CMD]... [--allow-no-verification]

Spawns `am run (--milestone ID | --card ID | --board) --repo-dir ROOT`, then the
options given in a fixed order (--base-branch, --branch-prefix, --max-concurrent,
every --verify pair in the order given, --allow-no-verification), as an argv list
(no shell). Every value is the next argument verbatim, even if it starts with `-`;
am refuses bad ones itself. --dry-run, --detach and --pretty are never sent.

The child runs in ROOT, in its own session (so a signal to the helper's process
group never reaches it), stdin /dev/null, stdout and stderr in a fresh log,
<state>/omarchy-project-manager/am-runs/<UTC stamp>-<project>-<8 hex>.log (dir
0700, file 0600), <state> being XDG_STATE_HOME when absolute, else
~/.local/state. am prints its envelope only when the run ends, so the helper
never blocks on it, signals it or ends it: the run outlives the helper, the
panel and the shell. The helper only polls whether it has exited.

For up to POLL_WINDOW seconds after the spawn it asks `am runs --repo-dir ROOT`
every POLL_INTERVAL seconds for the run this launch started: a row with an id,
started at or after the spawn (to the second), whose branch_prefix is the one
given (for the board, also `<prefix>-<stem>`; any, when none was given); the
earliest such row wins. A failing `am runs` is retried on the next tick.

Prints exactly one JSON line on EVERY path; pid, log and started_at are the
child's pid, the absolute log path and the spawn time (YYYY-MM-DDTHH:MM:SSZ):
- {"ok": true, "pid", "log", "started_at", "run_id": ID, "message": ""} when the
  run was found (even if am has exited since);
- {"ok": true, "pid", "log", "started_at", "run_id": null, "message": "started,
  run not visible yet"} when the window ended with am still running;
- {"ok": false, "error", "pid", "log", "started_at", "exit_code", "log_tail"}
  when am exited before its run appeared: the error is am's own refusal (the
  log's last non-empty line, if an {"ok": false, "error": {...}} envelope),
  else {"type": "AmExited", ...}; log_tail is the end of the log;
- {"ok": false, "error": {"type": "SpawnFailed", ...}, "log"} when am could not
  be started (ROOT missing, am not executable); the log says why;
- {"ok": false, "error": {"type": "AmMissing", ...}} when am is not on PATH;
- {"ok": false, "error": {"type": "HelperError", ...}} on any unexpected
  failure, with pid, log and started_at too if it came after the spawn;
- {"ok": false, "error": {"type": "Usage", ...}} for any other command line.
Exit 0 whenever a line was printed, refusals and errors included; exit 2 for
Usage only.
"""
import datetime
import os
import re
import secrets
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = ("usage: start-run.py ROOT (milestone ID | card ID | board) [--base-branch B]"
         " [--branch-prefix P] [--max-concurrent N] [--verify CMD]..."
         " [--allow-no-verification]")
VALUED = ("--base-branch", "--branch-prefix", "--max-concurrent")
TARGETS = ("milestone", "card")
POLL_WINDOW = 20
POLL_INTERVAL = 0.5
RUNS_TIMEOUT = 5
TAIL_LINES = 20
TAIL_CHARS = 2000
LOG_DIR_NAME = "am-runs"
STAMP = "%Y-%m-%dT%H:%M:%SZ"
NOT_VISIBLE = "started, run not visible yet"


class SpawnError(Exception):
    """am could not be started; the message is the OS error's text."""


def failure(kind, message, code=0, **extra):
    return emit({"ok": False, "error": {"type": kind, "message": message}, **extra}, code)


def good_root(root):
    return bool(root) and not root.startswith("-")


def parse(argv):
    """(root, target, id, options) for a command line USAGE allows, else None.

    target is "milestone", "card" or "board"; id is None for the board. options
    always maps "--verify" to the list of commands in the order given, maps each
    given VALUED flag to its value and "--allow-no-verification" to True when
    given; a once-only flag given twice is a usage error."""
    if len(argv) < 2 or not good_root(argv[0]):
        return None
    root, target, rest = argv[0], argv[1], argv[2:]
    if target in TARGETS:
        if not rest or not rest[0]:
            return None
        ident, rest = rest[0], rest[1:]
    elif target == "board":
        ident = None
    else:
        return None
    options = {"--verify": []}
    while rest:
        flag = rest[0]
        if flag == "--verify" and len(rest) > 1:
            options["--verify"].append(rest[1])
            rest = rest[2:]
        elif flag in VALUED and len(rest) > 1 and flag not in options:
            options[flag] = rest[1]
            rest = rest[2:]
        elif flag == "--allow-no-verification" and flag not in options:
            options[flag] = True
            rest = rest[1:]
        else:
            return None
    return root, target, ident, options


def run_argv(root, target, ident, options):
    """am's argv after the executable, in a fixed order whatever order the options came in."""
    argv = ["run", "--board"] if target == "board" else ["run", "--" + target, ident]
    argv += ["--repo-dir", root]
    for flag in VALUED:
        if flag in options:
            argv += [flag, options[flag]]
    for cmd in options["--verify"]:
        argv += ["--verify", cmd]
    if "--allow-no-verification" in options:
        argv.append("--allow-no-verification")
    return argv


def state_home():
    """XDG_STATE_HOME, but only when it is absolute; a relative value is ignored so
    the log tree never lands under whatever the working directory happens to be."""
    state = os.environ.get("XDG_STATE_HOME") or ""
    if not os.path.isabs(state):
        return os.path.join(os.path.expanduser("~"), ".local", "state")
    return state


def log_path(root):
    """A fresh log path for this launch; the random suffix keeps two launches in the
    same second apart. Creates the (private) directory."""
    directory = os.path.join(state_home(), "omarchy-project-manager", LOG_DIR_NAME)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    os.chmod(directory, 0o700)
    project = re.sub(r"[^A-Za-z0-9._-]", "_", os.path.basename(os.path.abspath(root))) or "project"
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    name = stamp + "-" + project + "-" + secrets.token_hex(4) + ".log"
    return os.path.abspath(os.path.join(directory, name))


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc)


def spawn(am, argv, root, log):
    """(proc, started) of the detached `am run`. started is the UTC time just before
    the spawn, floored to the second as am stamps its runs, so a run am stamps in
    the same second still counts as started at or after it."""
    fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.fchmod(fd, 0o600)
        started = utc_now().replace(microsecond=0)
        try:
            proc = subprocess.Popen([am, *argv], cwd=root, stdin=subprocess.DEVNULL, stdout=fd,
                                    stderr=subprocess.STDOUT, start_new_session=True)
        except OSError as e:
            os.write(fd, ("start-run: could not start am: " + str(e) + "\n").encode("utf-8", "replace"))
            raise SpawnError(str(e)) from e
        return proc, started
    finally:
        os.close(fd)


def early_exit(proc, launch):
    """am exited before its run appeared."""
    code = proc.returncode
    return emit({"ok": False, "error": {"type": "AmExited", "message":
                 "am run exited " + str(code) + " before its run appeared."},
                 **launch, "exit_code": code})


def watch(proc, launch, deadline):
    """Tick every POLL_INTERVAL until am exits or the window ends; one last tick
    runs at or after the deadline."""
    while True:
        last = time.monotonic() >= deadline
        if proc.poll() is not None:
            return early_exit(proc, launch)
        if last:
            return emit({"ok": True, **launch, "run_id": None, "message": NOT_VISIBLE})
        time.sleep(POLL_INTERVAL)


def main(argv, launch):
    parsed = parse(argv)
    if parsed is None:
        return failure("Usage", USAGE, 2)
    root, target, ident, options = parsed
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    log = log_path(root)
    try:
        proc, started = spawn(am, run_argv(root, target, ident, options), root, log)
    except SpawnError as e:
        return failure("SpawnFailed", "Could not start am run: " + str(e), log=log)
    deadline = time.monotonic() + POLL_WINDOW
    launch.update({"pid": proc.pid, "log": log, "started_at": started.strftime(STAMP)})
    return watch(proc, launch, deadline)


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception - may end without one. After the spawn the line also
    carries pid, log and started_at: the run may be going."""
    launch = {}
    try:
        return main(argv, launch)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The launch failed: " + reason, **launch)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
```

Then make it executable:

```bash
chmod 755 core/backend/runs/start-run.py
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_start_run.py tests/architecture -q`
Expected: PASS (all tests; `tests/architecture` stays green — no second `def emit(`).

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/start-run.py tests/core/backend/runs/test_start_run.py
git commit -m "start-run.py: am run detached in its own session with a private log, one JSON line on every path (S3 2.2)"
```

---

### Task 2: Early-exit report — am's refusal and the log tail

**Files:**
- Modify: `core/backend/runs/start-run.py` (replace `early_exit`; add `read_log`, `log_tail`, `refusal_of`; add `import json`)
- Modify: `tests/core/backend/runs/test_start_run.py` (append an `# --- early exit` section)

**Interfaces:**
- Consumes: from Task 1 — `early_exit(proc, launch)` is called by `watch` with `launch = {"pid", "log", "started_at"}`; `TAIL_LINES`, `TAIL_CHARS`, `emit`; test helpers `world`, `run`, `read_pid`, `load_helper`, `CLAIMED`.
- Produces: `read_log(path) -> str` (UTF-8 with replacement), `log_tail(text) -> str`, `refusal_of(text) -> dict | None`, and `early_exit(proc, launch) -> int` printing `{"ok": false, "error", "pid", "log", "started_at", "exit_code", "log_tail"}`. Task 3's `watch` keeps calling `early_exit(proc, launch)` unchanged.

- [ ] **Step 1: Write the failing tests**

Append to `tests/core/backend/runs/test_start_run.py`:

```python


# --- early exit ------------------------------------------------------------------

EARLY_KEYS = {"ok", "error", "pid", "log", "started_at", "exit_code", "log_tail"}


def test_early_exit_with_am_refusal(world):
    # Trailing blank lines after the envelope: the last NON-EMPTY line decides.
    (world["am"] / "run.out").write_text(json.dumps(CLAIMED) + "\n\n")
    (world["am"] / "run.code").write_text("3")
    code, out = run(world, [str(world["project"]), "milestone", "m1", "--branch-prefix", "m3"])
    assert code == 0
    assert set(out) == EARLY_KEYS
    assert out["ok"] is False
    assert out["error"] == CLAIMED["error"]
    assert out["exit_code"] == 3
    assert json.dumps(CLAIMED) in out["log_tail"]
    assert out["pid"] == read_pid(world)


def test_early_exit_without_envelope(world):
    lines = ["line %d" % i for i in range(1, 31)]
    (world["am"] / "run.err").write_text("\n".join(lines) + "\n")
    (world["am"] / "run.code").write_text("2")
    code, out = run(world, [str(world["project"]), "board"])
    assert code == 0
    assert set(out) == EARLY_KEYS
    assert out["error"] == {"type": "AmExited",
                            "message": "am run exited 2 before its run appeared."}
    assert out["exit_code"] == 2
    assert out["log_tail"] == "\n".join(lines[-20:])
    # One 5000-character line is cut to its last 2000 characters.
    assert load_helper().log_tail("x" * 3000 + "y" * 2000 + "\n") == "y" * 2000


def test_last_line_not_a_refusal(world):
    # JSON, ok false, but the error is not an object: not am's refusal shape.
    (world["am"] / "run.out").write_text(json.dumps({"ok": False, "error": "text"}) + "\n")
    (world["am"] / "run.code").write_text("4")
    code, out = run(world, [str(world["project"]), "board"])
    assert code == 0
    assert out["error"] == {"type": "AmExited",
                            "message": "am run exited 4 before its run appeared."}
    assert out["exit_code"] == 4


def test_early_exit_zero(world):
    # An am that finishes at once without a visible run is still an early exit.
    code, out = run(world, [str(world["project"]), "board"])
    assert code == 0
    assert set(out) == EARLY_KEYS
    assert out["ok"] is False
    assert out["error"] == {"type": "AmExited",
                            "message": "am run exited 0 before its run appeared."}
    assert out["exit_code"] == 0


def test_early_exit_empty_log(world):
    (world["am"] / "run.code").write_text("1")
    code, out = run(world, [str(world["project"]), "board"])
    assert code == 0
    assert out["exit_code"] == 1
    assert out["log_tail"] == ""
    assert out["error"]["type"] == "AmExited"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_start_run.py -q -k "early_exit or not_a_refusal"`
Expected: FAIL — `test_early_exit_with_am_refusal`, `test_early_exit_without_envelope`, `test_early_exit_zero` and `test_early_exit_empty_log` fail on `set(out) == EARLY_KEYS` (no `log_tail`) or `KeyError: 'log_tail'`; `test_early_exit_with_am_refusal` also because the error is `AmExited`, not `ClaimedError`. `test_last_line_not_a_refusal` may already pass (Task 1 always says `AmExited`); it pins the fallback for the refusal parsing added here.

- [ ] **Step 3: Write the implementation**

In `core/backend/runs/start-run.py`, add `import json` to the imports so they read:

```python
import datetime
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time
```

Replace the whole Task 1 `early_exit` function with:

```python
def read_log(path):
    with open(path, "rb") as f:
        return f.read().decode("utf-8", "replace")


def log_tail(text):
    """The end of the log, where am's refusal or a crash names its cause: at most
    TAIL_LINES lines, and of those at most TAIL_CHARS characters."""
    lines = text.rstrip().splitlines()[-TAIL_LINES:]
    return "\n".join(lines)[-TAIL_CHARS:]


def refusal_of(text):
    """am's own error object when the log's last non-empty line is its refusal
    envelope ({"ok": false, "error": {...}}), else None."""
    lines = [line for line in text.splitlines() if line.strip()]
    if not lines:
        return None
    try:
        envelope = json.loads(lines[-1])
    except ValueError:
        return None
    if (isinstance(envelope, dict) and envelope.get("ok") is False
            and isinstance(envelope.get("error"), dict)):
        return envelope["error"]
    return None


def early_exit(proc, launch):
    """am exited before its run appeared: its refusal if it printed one (a
    ClaimedError, a missing milestone, missing verification), else AmExited."""
    code = proc.returncode
    text = read_log(launch["log"])
    error = refusal_of(text) or {"type": "AmExited", "message":
                                 "am run exited " + str(code) + " before its run appeared."}
    return emit({"ok": False, "error": error, **launch, "exit_code": code,
                 "log_tail": log_tail(text)})
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_start_run.py tests/architecture -q`
Expected: PASS (all tests, Task 1's included).

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/start-run.py tests/core/backend/runs/test_start_run.py
git commit -m "start-run.py: an early exit passes am's refusal through with the log's tail (S3 2.2)"
```

---

### Task 3: Run-id discovery through `am runs`

**Files:**
- Modify: `core/backend/runs/start-run.py` (add `list_runs`, `parse_time`, `matches`, `find_run`; replace `watch`; change the last line of `main`)
- Modify: `tests/core/backend/runs/test_start_run.py` (append a `# --- run-id discovery` section)

**Interfaces:**
- Consumes: from Task 1 — `utc_now()`, `spawn`, `main(argv, launch)`, `NOT_VISIBLE`, `POLL_INTERVAL`, `RUNS_TIMEOUT`, `emit`; from Task 2 — `early_exit(proc, launch)`; test helpers `world`, `run`, `calls`, `fast_helper`, `one_line`, `wait_for`, `read_pid`, `load_helper`, `env_for`, `SCRIPT`.
- Produces:
  - `list_runs(am, root) -> list` (the `runs` list of a good envelope, else `[]`; never raises for am's failures);
  - `parse_time(value) -> datetime | None` (aware; naive values are UTC);
  - `matches(row, target, prefix, since) -> bool` (`since` an aware datetime, `prefix` a str or None);
  - `find_run(rows, target, prefix, since) -> str | None`;
  - `watch(proc, am, root, target, prefix, launch, started, deadline) -> int`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/core/backend/runs/test_start_run.py`:

```python


# --- run-id discovery ----------------------------------------------------------------

NOON = datetime.datetime(2026, 10, 5, 12, 0, 0, 700000, tzinfo=datetime.timezone.utc)
SINCE = datetime.datetime(2026, 10, 5, 12, 0, 0, tzinfo=datetime.timezone.utc)


def row(run_id, started_at, prefix="m3"):
    return {"id": run_id, "workflow": "orchestrator", "repo_dir": "/p", "base_branch": "main",
            "branch_prefix": prefix, "status": "running", "started_at": started_at}


def serve_rows(world, rows):
    """The fake `am run` publishes these rows once it starts ("NOW" = its start second)."""
    (world["am"] / "run.rows").write_text(json.dumps(rows))


def seed_runs(world, rows):
    """`am runs` serves these rows from the start."""
    (world["am"] / "runs.json").write_text(json.dumps(rows))


def at_noon(helper, monkeypatch):
    """The helper's clock reads NOON, so its started_at is 2026-10-05T12:00:00Z."""
    monkeypatch.setattr(helper, "utc_now", lambda: NOON)


def test_finds_run_by_prefix_and_start_time(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world)
    at_noon(helper, monkeypatch)
    seed_runs(world, [row("other", "2026-10-05T12:00:05Z", prefix="m9"),
                      row("mine", "2026-10-05T12:00:03Z"),
                      row("old", "2026-10-05T11:59:00Z")])
    (world["am"] / "run.sleep").write_text("2")
    root = str(world["project"])
    assert helper.guarded([root, "milestone", "m1", "--branch-prefix", "m3"]) == 0
    out = one_line(capsys)
    assert out == {"ok": True, "pid": read_pid(world), "log": out["log"],
                   "started_at": "2026-10-05T12:00:00Z", "run_id": "mine", "message": ""}
    assert ["runs", "--repo-dir", root] in calls(world)


def test_started_at_same_second_counts(world, monkeypatch, capsys):
    # The helper's clock is 12:00:00.7, am stamps 12:00:00: same second, so found.
    helper = fast_helper(monkeypatch, world)
    at_noon(helper, monkeypatch)
    seed_runs(world, [row("same", "2026-10-05T12:00:00Z"),
                      row("before", "2026-10-05T11:59:59Z")])
    (world["am"] / "run.sleep").write_text("2")
    assert helper.guarded([str(world["project"]), "milestone", "m1", "--branch-prefix", "m3"]) == 0
    assert one_line(capsys)["run_id"] == "same"


def test_started_at_with_offset_parsed():
    helper = load_helper()
    assert helper.find_run([row("a", "2026-10-05T12:00:01+00:00")], "milestone", "m3", SINCE) == "a"
    assert helper.find_run([row("b", "2026-10-05T12:00:01")], "milestone", "m3", SINCE) == "b"
    # 13:59:59+02:00 is 11:59:59Z: before the spawn, so the offset is applied, not dropped.
    assert helper.find_run([row("c", "2026-10-05T13:59:59+02:00")], "milestone", "m3", SINCE) is None
    assert helper.find_run([row("d", "yesterday")], "milestone", "m3", SINCE) is None
    assert helper.find_run([row("e", 12345)], "milestone", "m3", SINCE) is None


def test_board_prefix_rule():
    helper = load_helper()
    when = "2026-10-05T12:00:01Z"
    assert helper.find_run([row("r", when, prefix="x-m3")], "board", "x", SINCE) == "r"
    assert helper.find_run([row("r", when, prefix="x")], "board", "x", SINCE) == "r"
    assert helper.find_run([row("r", when, prefix="xy-m3")], "board", "x", SINCE) is None
    # Only the board derives <prefix>-<stem>; a milestone's prefix must be equal.
    assert helper.find_run([row("r", when, prefix="x-m3")], "milestone", "x", SINCE) is None
    # A row without a branch_prefix never matches a given prefix.
    assert helper.find_run([row("r", when, prefix=None)], "board", "x", SINCE) is None
    # No --branch-prefix given: any prefix, even none.
    assert helper.find_run([row("r", when, prefix="anything")], "board", None, SINCE) == "r"
    assert helper.find_run([row("r", when, prefix=None)], "board", None, SINCE) == "r"


def test_earliest_matching_run_wins():
    helper = load_helper()
    # am lists newest first.
    rows = [row("later", "2026-10-05T12:00:09Z"), row("earlier", "2026-10-05T12:00:02Z")]
    assert helper.find_run(rows, "milestone", "m3", SINCE) == "earlier"
    tie = [row("listed-first", "2026-10-05T12:00:02Z"), row("listed-last", "2026-10-05T12:00:02Z")]
    assert helper.find_run(tie, "milestone", "m3", SINCE) == "listed-last"


def test_malformed_rows_skipped():
    helper = load_helper()
    when = "2026-10-05T12:00:01Z"
    rows = [None, "r", 5, [], {"id": "", "started_at": when}, {"id": 7, "started_at": when},
            {"started_at": when}, {"id": "no-time"}]
    assert helper.find_run(rows, "board", None, SINCE) is None


def test_runs_errors_are_retried(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world)
    at_noon(helper, monkeypatch)
    seed_runs(world, [row("mine", "2026-10-05T12:00:03Z")])
    (world["am"] / "runs.fail").write_text("3")
    (world["am"] / "run.sleep").write_text("3")
    assert helper.guarded([str(world["project"]), "milestone", "m1", "--branch-prefix", "m3"]) == 0
    out = one_line(capsys)
    assert out["ok"] is True
    assert out["run_id"] == "mine"
    assert int((world["am"] / "runs.count").read_text()) >= 4


@pytest.mark.parametrize("runs_out", [
    "not json\n",
    json.dumps({"ok": False, "error": {"type": "X", "message": "y"}}) + "\n",
    json.dumps({"ok": True}) + "\n",
    json.dumps({"ok": True, "data": []}) + "\n",
    json.dumps({"ok": True, "data": {"runs": {}}}) + "\n",
    json.dumps({"ok": True, "data": {"runs": [None, "x", {"id": ""},
                                              {"id": 5, "started_at": "2099-01-01T00:00:00Z"},
                                              {"id": "r", "branch_prefix": "x"}]}}) + "\n",
    "[]\n",
])
def test_runs_bad_output_ignored(world, monkeypatch, capsys, runs_out):
    helper = fast_helper(monkeypatch, world, window=0.3)
    (world["am"] / "runs.out").write_text(runs_out)
    (world["am"] / "run.sleep").write_text("5")
    assert helper.guarded([str(world["project"]), "board"]) == 0
    out = one_line(capsys)
    assert out["ok"] is True
    assert out["run_id"] is None
    assert out["message"] == "started, run not visible yet"


def test_run_found_even_if_child_exited(world):
    serve_rows(world, [row("r-new", "NOW")])
    code, out = run(world, [str(world["project"]), "milestone", "m1", "--branch-prefix", "m3"])
    assert code == 0
    assert out["ok"] is True
    assert out["run_id"] == "r-new"
    assert out["message"] == ""


def test_child_exiting_during_query_is_not_early_exit(world, monkeypatch, capsys):
    # am exits while the first `am runs` is in flight; that query does not show the
    # row yet. The exit was not seen before the query, so the next tick looks again
    # and finds the run instead of reporting an early exit.
    helper = fast_helper(monkeypatch, world)
    serve_rows(world, [row("r-new", "NOW")])
    (world["am"] / "run.sleep").write_text("0.3")  # still running at the first tick
    real = helper.list_runs
    seen = []

    def lagging(am, root):
        seen.append(True)
        if len(seen) == 1:
            assert wait_for(world["am"] / "run.done")
            time.sleep(0.3)  # let the fake finish exiting
            return []
        return real(am, root)

    monkeypatch.setattr(helper, "list_runs", lagging)
    assert helper.guarded([str(world["project"]), "milestone", "m1", "--branch-prefix", "m3"]) == 0
    out = one_line(capsys)
    assert out["ok"] is True
    assert out["run_id"] == "r-new"


def test_helper_returns_while_child_runs(world):
    serve_rows(world, [row("r-new", "NOW")])
    (world["am"] / "run.sleep").write_text("5")
    began = time.monotonic()
    code, out = run(world, [str(world["project"]), "milestone", "m1", "--branch-prefix", "m3"])
    assert time.monotonic() - began < 4
    assert code == 0
    assert out["ok"] is True
    assert out["run_id"] == "r-new"
    assert out["message"] == ""
    assert not (world["am"] / "run.done").exists()


def test_child_survives_the_helper_group_being_killed(world, tmp_path):
    # HelperRunner stopping the helper, or the panel closing, signals the helper's
    # process group. am runs in its own session, so it must survive.
    serve_rows(world, [row("r-new", "NOW")])
    (world["am"] / "run.sleep").write_text("2")
    driver = tmp_path / "driver.py"
    driver.write_text(
        "import importlib.util, sys, time\n"
        "spec = importlib.util.spec_from_file_location('start_run', %r)\n"
        "m = importlib.util.module_from_spec(spec)\n"
        "spec.loader.exec_module(m)\n"
        "m.POLL_INTERVAL = 0.05\n"
        "m.guarded([%r, 'milestone', 'm1', '--branch-prefix', 'm3'])\n"
        "sys.stdout.flush()\n"
        "time.sleep(30)\n" % (SCRIPT, str(world["project"])))
    p = subprocess.Popen([sys.executable, str(driver)], stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, env=env_for(world),
                         start_new_session=True)
    try:
        ready, _, _ = select.select([p.stdout], [], [], 15)
        assert ready, "the helper printed nothing"
        assert json.loads(p.stdout.readline())["run_id"] == "r-new"
        assert not (world["am"] / "run.done").exists()
    finally:
        os.killpg(p.pid, signal.SIGKILL)
        p.wait()
        p.stdout.close()
    assert wait_for(world["am"] / "run.done")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_start_run.py -q`
Expected: FAIL — the unit tests fail with `AttributeError: module 'start_run' has no attribute 'find_run'`; `test_child_exiting_during_query_is_not_early_exit` fails at `monkeypatch.setattr(helper, "list_runs", ...)` (`AttributeError`); the launch tests (`test_finds_run_by_prefix_and_start_time`, `test_started_at_same_second_counts`, `test_runs_errors_are_retried`, `test_run_found_even_if_child_exited`, `test_helper_returns_while_child_runs`, `test_child_survives_the_helper_group_being_killed`) fail because `run_id` is `None` or the line is an early exit. `test_runs_bad_output_ignored` passes already (nothing reads `am runs` yet); it pins that the new reader tolerates every bad shape. Task 1 and 2 tests still pass.

- [ ] **Step 3: Write the implementation**

In `core/backend/runs/start-run.py`, add these functions directly after `utc_now()`:

```python
def list_runs(am, root):
    """The rows of `am runs --repo-dir ROOT`, or [] when it gives none this tick
    (a failure, a timeout, bad JSON, a refusal): the next tick asks again."""
    try:
        proc = subprocess.run([am, "runs", "--repo-dir", root], capture_output=True,
                              encoding="utf-8", errors="replace", stdin=subprocess.DEVNULL,
                              timeout=RUNS_TIMEOUT)
        envelope = json.loads(proc.stdout)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return []
    if not isinstance(envelope, dict) or envelope.get("ok") is not True:
        return []
    data = envelope.get("data")
    runs = data.get("runs") if isinstance(data, dict) else None
    return runs if isinstance(runs, list) else []


def parse_time(value):
    """An ISO-8601 time (`Z` or an offset) as an aware datetime; no offset means UTC.
    None when it does not parse."""
    if not isinstance(value, str):
        return None
    try:
        when = datetime.datetime.fromisoformat(value)
    except ValueError:
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=datetime.timezone.utc)
    return when


def matches(row, target, prefix, since):
    """Whether an `am runs` row can be the run this launch started: it has an id,
    started at or after `since`, and carries the prefix given (the board's runs may
    carry `<prefix>-<stem>`); with no prefix given, any."""
    if not isinstance(row, dict) or not isinstance(row.get("id"), str) or not row["id"]:
        return False
    when = parse_time(row.get("started_at"))
    if when is None or when < since:
        return False
    if prefix is None:
        return True
    got = row.get("branch_prefix")
    if not isinstance(got, str):
        return False
    return got == prefix or (target == "board" and got.startswith(prefix + "-"))


def find_run(rows, target, prefix, since):
    """The id of the earliest matching row (on a tie, the one listed last: the
    oldest in am's newest-first order), else None."""
    best = None
    for row in rows:
        if matches(row, target, prefix, since):
            when = parse_time(row["started_at"])
            if best is None or when <= best[0]:
                best = (when, row["id"])
    return best[1] if best else None
```

Replace the whole Task 1 `watch` function with:

```python
def watch(proc, am, root, target, prefix, launch, started, deadline):
    """Tick every POLL_INTERVAL until the run appears, am exits or the window ends;
    one last tick runs at or after the deadline. Whether am has exited is read
    before `am runs` is asked: an exit seen first means its row, if any, was
    already written, so an exit during the query is never taken for an early exit."""
    while True:
        last = time.monotonic() >= deadline
        exited = proc.poll() is not None
        run_id = find_run(list_runs(am, root), target, prefix, started)
        if run_id is not None:
            return emit({"ok": True, **launch, "run_id": run_id, "message": ""})
        if exited:
            return early_exit(proc, launch)
        if last:
            return emit({"ok": True, **launch, "run_id": None, "message": NOT_VISIBLE})
        time.sleep(POLL_INTERVAL)
```

In `main`, replace its last line

```python
    return watch(proc, launch, deadline)
```

with

```python
    return watch(proc, am, root, target, options.get("--branch-prefix"), launch, started, deadline)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_start_run.py tests/architecture -q`
Expected: PASS (all tests in the file, Tasks 1-2 included, and the architecture tests).

Then the whole suite: `bash tests/run.sh`
Expected: pytest reports no failures and every QML test file prints `Totals` with 0 failed; exit status 0.

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/start-run.py tests/core/backend/runs/test_start_run.py
git commit -m "start-run.py: polls am runs for the run it started, by prefix and start time (S3 2.2)"
```

---

## Self-Review

**Spec coverage:**
- Command line, USAGE, Usage shapes → Task 1 (`parse`, `test_usage_shapes`, plus `--pretty` and a doubled `--allow-no-verification`).
- am argv fixed order, never `--dry-run/--detach/--pretty` → Task 1 (`run_argv`, tests 1-5).
- Spawn steps 1-5 (AmMissing before log, log dir/file modes, floored `started_at`, `Popen` detached, SpawnFailed with the log line) → Task 1 (tests 6, 7, 23-29).
- Never waits/kills, only `poll()` → Task 1 (test 10) and the module source.
- Finding the run id (tick, prefix rule, earliest wins, tie → listed last, `am runs` failures ignored, last tick at/after deadline) → Task 3 (tests 11-17, `test_malformed_rows_skipped`, `test_runs_bad_output_ignored`).
- Outputs 1-7 → Started (Task 3), Not visible yet (Task 1, test 18), Early exit (Task 1 bare, Task 2 full: tests 19-22), SpawnFailed / AmMissing / HelperError incl. after spawn / Usage (Task 1).
- Detached survival → Task 3 tests 8-9 (they need a found run to print Started).
- Architecture stays green → every task's Step 4 runs `tests/architecture`.
- Deliberate refinement: the tick reads `poll()` before querying `am runs` (spec lists the query first). It only changes the outcome when am exits during the query, where it prevents a false early exit; documented in `watch`'s docstring and pinned by Review Focus 1.

**Placeholder scan:** no TBD/TODO; every code step carries full code.

**Type consistency:** `early_exit(proc, launch)` same in Tasks 1-3 and in the monkeypatched `boom`; `watch` signature changes once (Task 3) together with its only caller in `main`; `find_run(rows, target, prefix, since)` / `matches(row, target, prefix, since)` / `list_runs(am, root)` match their uses in tests; `launch` keys `pid`, `log`, `started_at` everywhere.

**Review Focus:** all five lines have tests in their owning tasks (Task 1: error after spawn, trailing-slash ROOT; Task 2: refusal with trailing blank lines, non-refusal last line; Task 3: exit during the query, bad `am runs` output).
<!-- task-pipeline: validated -->
