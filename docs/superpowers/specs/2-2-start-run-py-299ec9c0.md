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
