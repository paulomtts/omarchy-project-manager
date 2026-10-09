# 1.3 `runs-logs.py`: read from the run's repository — spec

Card `bf24c52b-3540-439a-8028-eeb02a275980`, subtask of story `85b0f971-5e0f-488e-a8e5-a71e3663f314`
(Live run output), blocked by card `5a56adf9` (1.2, `runs-logs-follow.py`, done). Parent design:
`docs/superpowers/specs/2026-10-05-live-output-design.md` (below: **LO**).

## Purpose

The one-shot snapshot helper `core/backend/runs/runs-logs.py` must answer for the run's own
repository from any working directory, and must be able to ask for a step (a phase with no
attempts). The store's only caller, `RunStore.fetchLogs`, must hand it the run's `repo_dir`, the
directory am resolves the run against.

## Starting point (already on this branch)

- `runs-logs.py` already takes the repository first (`<project_root> RUN CARD PHASE ATTEMPT`,
  exactly five arguments, `core/backend/runs/runs-logs.py:34,65-67`) and already sends
  `--repo-dir ROOT` (`:46-48`). LO lines 133-135: "If the Align milestone already passes the
  repository, its argument order is kept and only the step rule is added." So the argument order,
  the argument count, `USAGE` and every error path stay exactly as they are. (LO line 30's claim
  that `runs-logs.py` sends no `--repo-dir` is stale.)
- `RunStore.fetchLogs` (`core/stores/RunStore.qml:817-830`) launches
  `[runRoot(run), RUN, CARD, PHASE, String(attempt)]`, where `runRoot` is the run's
  `project.root` (the registry root whose snapshot entry listed it, `:786-791`), and launches
  nothing when that root is `""`. That is not the directory am resolves the run against: a run
  started in a worktree or another checkout has a `repo_dir` different from its project root
  (the store's own control requests already use `run.repo_dir`, `:1298-1313`, `:1488-1495`).

## Inherited constraints

| constraint | source |
|---|---|
| `am logs` resolves the run against `--repo-dir`, default `.`; from any other cwd it answers `UnknownRunError`. | LO lines 28-31; card |
| `runs-logs.py` takes REPO first and passes `--repo-dir`; ATTEMPT `0` omits `--attempt` (a step). If the repository is already passed, its argument order is kept and only the step rule is added. | LO lines 133-135 |
| `am logs RUN CARD --phase P` with no `--attempt` answers a step (am picks its latest `<phase>.N`). | LO lines 32-38 |
| A run started in another repository: `--repo-dir` is that run's `repo_dir`. | LO line 226; LO line 172 (the follow store uses `run.repo_dir` too) |
| Tests: `test_runs_logs.py`: REPO and the step rule. | LO line 244 |
| One JSON line on every path; exit 0 except `Usage` (2); argv lists, no shell; only the documented `am logs` command. | `runs-logs.py:10-23` (unchanged) |
| `core/backend` uses the stdlib and `core/backend/common` only; no duplicated helpers (`tests/architecture`). | `docs/architecture.md`; `tests/architecture/test_layers.py` |
| Docstrings and comments state the contract only, no narrative; `bash tests/run.sh` green; TDD (tests first). | card description |

## Behaviour

### B1. The step rule (`runs-logs.py`)

- ATTEMPT exactly the string `0` → am's argv is
  `["logs", RUN, CARD, "--phase", PHASE, "--repo-dir", REPO]`: no `--attempt` and no value for it.
- Any other ATTEMPT (including `-1`, `00`, `""`, `abc`, ` 0`) → unchanged:
  `["logs", RUN, CARD, "--phase", PHASE, "--attempt", ATTEMPT, "--repo-dir", REPO]`, ATTEMPT
  verbatim. The helper does not parse or validate ATTEMPT (its docstring: "am refuses bad ones
  itself"); only the literal `0` is special.
- The reply handling is unchanged: am's envelope passes through whatever ATTEMPT was, including
  am's refusal for a step that records no log (`UnknownAttemptError`, LO lines 37-38).

### B2. The repository decides, not the cwd (`runs-logs.py`)

- `--repo-dir REPO` is always the last pair of am's argv, REPO byte-for-byte as given (already
  true; kept).
- The helper never changes directory and never relies on its cwd: run from a directory that is
  not REPO, it sends the same argv and prints am's envelope.

### B3. Docstring (`runs-logs.py`)

- The synopsis stays `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` (it is the `USAGE`
  text the tests assert verbatim, `tests/core/backend/runs/test_runs_logs.py` ~l.356); the first
  argument is the repository am resolves the run against.
- The am command line reads
  `am logs RUN CARD --phase PHASE [--attempt ATTEMPT] --repo-dir ROOT`, plus the sentence
  "ATTEMPT 0 omits --attempt (a step: am picks its latest)." The `logs_argv` docstring states the
  same rule. Contract only, no history.

### B4. The caller passes the run's `repo_dir` (`RunStore.fetchLogs`)

- The first argument after the script is the selected run's `repo_dir` (as normalized by
  `Runs.normalizeRun`: the row's `repo_dir`, else `am status`'s), byte-for-byte, one argv element.
  The run's `project.root` is no longer used by `fetchLogs`.
- Nothing launches (no runner call, `logsLoading` stays false, `logsStatus` untouched) when the
  selected run has no `repo_dir` (not a string, or `""`). A run with a `repo_dir` but no project
  root now launches (am needs the repository, not the registry root) — the same rule as the
  store's control requests ("with or without a project").
- Everything else in `fetchLogs` is unchanged: five arguments after `python3` and the script,
  `String(sel.attempt)` as ATTEMPT, `logsStatus` set from `Runs.attemptStatus`, no launch guard.
- The comment above `fetchLogs` says "the selected run's repo_dir first" and "Nothing launches
  for a run not in the snapshot or one with no repo_dir".
- `runRoot` stays: other code uses it.

### B5. Docs (`docs/architecture.md`)

- l.90 (`logsRunner`): "`runs-logs.py` with the selected run's `repo_dir` first …; nothing
  launches for a selected run with no `repo_dir`".
- l.201: "`runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` is a one-shot
  `am logs RUN CARD --phase P [--attempt N] --repo-dir R` passthrough (ATTEMPT 0 omits
  `--attempt`): …".

## Error paths

No new error type. `Usage` (not exactly five arguments, exit 2), `AmMissing`, `AmBadOutput`,
`HelperError` and am's own envelope (e.g. `UnknownRunError`, `UnknownAttemptError`) are exactly
as today. In the store, a run with no `repo_dir` is a silent no-launch, as a run with no project
root was before.

## Tests

### pytest — `tests/core/backend/runs/test_runs_logs.py` (tier: hermetic unit/integration of the helper process with the existing fake `am` on a temp PATH; the behaviour is the argv am receives, which only the fake's `calls.log` observes)

Existing tests stay green unchanged (`test_exact_am_argv`, `test_args_reach_am_verbatim` with
`-1`, `test_root_reaches_am_unnormalised`, `test_root_that_is_a_file_is_left_to_am`,
`test_missing_fixture_unknown_run`, the `USAGE` text assert).

1. `test_attempt_0_omits_attempt` — args `[proj, "r1", "c1", "verify", "0"]`, ok envelope →
   exit 0, the envelope passed through, `calls == [["logs","r1","c1","--phase","verify",
   "--repo-dir", proj]]`, and `"--attempt" not in` the call.
2. `test_only_the_literal_0_is_a_step` (parametrized over `"00"`, `" 0"`, `""`) — each reaches am
   as `--attempt <value>` verbatim, `--repo-dir` last. Pins B1's "only the literal `0`" so a
   future int-parse does not silently fold `00` into a step.
3. `test_a_step_refusal_passes_through` — ATTEMPT `0`, am answers
   `{"ok": false, "error": {"type": "UnknownAttemptError", "message": "phase 'worktree' has no
   recorded attempt yet"}}` (synthetic, labelled) with exit 3 → exit 0, that envelope unchanged.
4. `test_a_cwd_outside_the_repo_still_reaches_it` — `run()` gains an optional `cwd` keyword
   (default: unchanged behaviour); the helper runs with `cwd` = a fresh temp dir that is not
   `proj`; the fake am for this test is the standard one plus a check that refuses
   (`UnknownRunError`, exit 3) unless its argv's `--repo-dir` value equals `proj`. Expect exit 0,
   the ok envelope, and the call carrying `--repo-dir proj`. Run once with attempt `2` and once
   with `0`.

### QML — `tests/core/stores/tst_run_store.qml` (tier: store unit test with the stubbed `HelperRunner`; the behaviour is the argv the store launches)

5. `test_logs_argv_leads_with_the_runs_repo_dir` (replaces
   `test_logs_argv_leads_with_the_runs_project_root`) — a run of rootB whose `repo_dir` is
   `bRepo` (`bWork`, `/home/u/b-work`) is selected → `command[2] == "/home/u/b-work"`, never
   `/home/u/b`; seven elements.
6. `test_logs_argv_keeps_an_odd_repo_dir_verbatim` (rename of
   `test_logs_argv_keeps_an_odd_root_verbatim`; the fixture already sets `repo_dir` to the odd
   path) — `command[2]` equals it byte-for-byte.
7. `test_no_logs_for_a_selected_run_without_a_repo_dir` (replaces
   `test_no_logs_for_a_selected_run_without_a_project_root`) — `repo_dir: ""` → no
   `logsRunner.current`, `logsLoading` false; and a held run with a `repo_dir` but no project root
   does launch with that `repo_dir`.
8. `test_logs_of_another_projects_run_load_with_no_project_open` — its expected argv uses the run's
   `repo_dir`; with `treeEntry(..., rootB)` that is `/home/u/b`, so it stays as is. Existing
   asserts using `tc.logsCmd` (rootA) and `tc.capRoot` stay green because those fixtures'
   `repo_dir` equals their root; no other edit is needed there.

UI tests (`tests/ui/tst_runs_flow.qml`, `tst_runs_real_data.qml`) assert only the script path and
need no change. `tests/architecture` must pass. Gate: `bash tests/run.sh`.

## Out of scope

- `runs-logs-follow.py` (card 1.2, done) and its tests.
- Selecting a step in the store or UI: `selectAttempt` keeps rejecting `attempt <= 0`, so the
  store never sends ATTEMPT `0` from this card (step rows, `defaultAttempt` on a step,
  `tst_run_store.qml` "selecting a step" belong to the domain/store cards, LO lines 240-248).
- `RunOutputStore`, `core/domain/logStream.js`, the follow pane and any UI change.
- `tests/contract/test_am_shapes.py` and the am fixtures.
- Renaming the `<project_root>` synopsis or `USAGE` text.
- Changing `runRoot` or any other user of a run's project root.

## Handoff to the planner

Follow the `writing-plans` format. Suggested tasks (each with its own test cycle):

1. `runs-logs.py` step rule + cwd independence: tests 1-4, then `logs_argv` and the docstring
   (B1-B3), then the l.201 sentence of `docs/architecture.md`.
2. `RunStore.fetchLogs` uses `repo_dir`: tests 5-8, then `fetchLogs` and its comment (B4), then
   the l.90 sentence of `docs/architecture.md`.

Review Focus candidates: ATTEMPT `00`/` 0` staying verbatim; a run whose `repo_dir` differs from
its project root; a run with `repo_dir` but no project root; a `repo_dir` with spaces or shell
metacharacters; the helper launched from `/` or `$HOME`.
