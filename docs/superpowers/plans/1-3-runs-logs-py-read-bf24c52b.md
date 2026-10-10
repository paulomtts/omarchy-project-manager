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

---

# 1.3 `runs-logs.py`: read from the run's repository Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `runs-logs.py` sends a step (ATTEMPT `0` → no `--attempt`) and answers from the run's repository whatever its cwd, and `RunStore.fetchLogs` hands it the selected run's `repo_dir` instead of its project root.

**Architecture:** One small change in `logs_argv` (the literal string `"0"` drops the `--attempt` pair) plus docstrings; one small change in `RunStore.fetchLogs` (read `run.repo_dir`, skip when it is not a non-empty string). Tests drive both: pytest with the existing fake `am` on a temp PATH (it records argv in `calls.log`), and the QML store test with the stubbed `HelperRunner` (it records `command`).

**Tech Stack:** Python 3 stdlib, pytest (run through `uv run --with pytest` — the system `python3` has no pytest), QML / QtTest via `qmltestrunner`, the repo gate `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/1-3-runs-logs-py-read-bf24c52b.md` (reproduced above).

## Global Constraints

- `runs-logs.py` keeps exactly five arguments `<project_root> RUN CARD PHASE ATTEMPT`; `USAGE` stays `"usage: runs-logs.py <project_root> RUN CARD PHASE ATTEMPT"` verbatim.
- One JSON line on every path; exit 0 except `Usage` (2); argv lists, no shell; only the documented `am logs` command.
- `--repo-dir REPO` is always the last pair of am's argv, REPO byte-for-byte as given.
- Only the literal ATTEMPT string `0` is a step; every other ATTEMPT (`-1`, `00`, `""`, `abc`, ` 0`) reaches am verbatim as `--attempt <value>`.
- `core/backend` uses the stdlib and `core/backend/common` only; no duplicated helpers (`tests/architecture`).
- Docstrings and comments state the contract only, no narrative/history.
- TDD: tests first. Gate: `bash tests/run.sh` green.
- `runRoot` in `RunStore.qml` stays (other code uses it); `selectAttempt` keeps rejecting `attempt <= 0`.
- Out of scope: `runs-logs-follow.py`, `RunOutputStore`, `logStream.js`, UI, `tests/contract/test_am_shapes.py`, am fixtures, renaming the synopsis.

## Review Focus

1. ATTEMPT `00`, ` 0` or `""` — a reasonable person expects these to reach am verbatim as `--attempt <value>` (am refuses them), never folded into a step. → Task 1, `test_only_the_literal_0_is_a_step`.
2. A run whose `repo_dir` differs from its project root (a worktree) — logs must be read from `repo_dir`, never the registry root. → Task 2, `test_logs_argv_leads_with_the_runs_repo_dir`.
3. A run with a `repo_dir` but no project root — logs still load. → Task 2, `test_no_logs_for_a_selected_run_without_a_repo_dir` (second half).
4. A `repo_dir` with spaces or shell metacharacters — one argv element, byte-for-byte, both in the store and to am. → Task 2, `test_logs_argv_keeps_an_odd_repo_dir_verbatim`; Task 1, the world's project dir is `my proj; echo x` in every new test.
5. The helper launched from `/` or another directory that is not the repository — same argv, am's envelope. → Task 1, `test_a_cwd_outside_the_repo_still_reaches_it` (parametrized over a temp dir and `/`).

## File map

- Modify: `core/backend/runs/runs-logs.py` — module docstring (l.2-8), `logs_argv` (l.46-48).
- Modify: `tests/core/backend/runs/test_runs_logs.py` — `run()` gains `cwd` (l.105-112); a repo-checking fake am; four new tests.
- Modify: `core/stores/RunStore.qml` — `fetchLogs` and the comment above it (l.817-830).
- Modify: `tests/core/stores/tst_run_store.qml` — tests at l.2689-2711 (two renames/rewrites) and l.5645-5654 (one rewrite).
- Modify: `docs/architecture.md` — l.90 (`logsRunner` sentence) and l.201 (`runs-logs.py` sentence).

---

### Task 1: `runs-logs.py` — the step rule and cwd independence

**Files:**
- Modify: `core/backend/runs/runs-logs.py:2-8,46-48`
- Test: `tests/core/backend/runs/test_runs_logs.py`
- Modify: `docs/architecture.md:201`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `logs_argv(root, run, card, phase, attempt) -> list[str]` — `["logs", run, card, "--phase", phase, "--repo-dir", root]` when `attempt == "0"`, else `["logs", run, card, "--phase", phase, "--attempt", attempt, "--repo-dir", root]`. The CLI contract (`runs-logs.py REPO RUN CARD PHASE ATTEMPT`) that Task 2's store launches is unchanged.

- [ ] **Step 1: Give `run()` a `cwd` keyword**

In `tests/core/backend/runs/test_runs_logs.py`, replace the `run` helper (l.105-112):

```python
def run(world, args=None, drop=(), **extra):
    """Run the helper; assert stdout is exactly one JSON line; return (exit, payload)."""
    argv = default_args(world) if args is None else args
    p = subprocess.run([sys.executable, SCRIPT, *argv], capture_output=True, text=True,
                       env=env_for(world, drop, **extra), timeout=60)
    lines = p.stdout.splitlines()
    assert len(lines) == 1, (p.stdout, p.stderr)
    return p.returncode, json.loads(lines[0])
```

with:

```python
def run(world, args=None, drop=(), cwd=None, **extra):
    """Run the helper (in `cwd` when given); assert stdout is exactly one JSON line;
    return (exit, payload)."""
    argv = default_args(world) if args is None else args
    p = subprocess.run([sys.executable, SCRIPT, *argv], capture_output=True, text=True,
                       env=env_for(world, drop, **extra), cwd=cwd, timeout=60)
    lines = p.stdout.splitlines()
    assert len(lines) == 1, (p.stdout, p.stderr)
    return p.returncode, json.loads(lines[0])
```

- [ ] **Step 2: Add the repo-checking fake am**

Directly below the `UNKNOWN_RUN = ...` line (l.49), add:

```python
# The fake am, plus real am's resolution rule: it answers UnknownRunError (exit 3)
# unless the value after --repo-dir is FAKE_AM_REPO. It still logs every call.
REPO_CHECK = '''repo = args[args.index("--repo-dir") + 1] if "--repo-dir" in args[:-1] else None
if repo != os.environ["FAKE_AM_REPO"]:
    sys.stdout.write(json.dumps({"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}) + "\\n")
    sys.exit(3)
'''
REPO_CHECKING_AM = FAKE_AM.replace('name = "logs"', REPO_CHECK + 'name = "logs"', 1)
assert REPO_CHECKING_AM != FAKE_AM
```

- [ ] **Step 3: Write the failing tests**

Append a new section at the end of the `# --- passthrough ---` block, i.e. directly before the line `# --- bad output, am missing, usage, catch-all ---------------------------------` (l.294):

```python
# --- a step, and the repository decides -----------------------------------------

def test_attempt_0_omits_attempt(world):
    envelope = {"ok": True, "data": logs_data()}
    set_logs(world, envelope)
    proj = str(world["proj"])
    code, out = run(world, [proj, "r1", "c1", "verify", "0"])
    assert code == 0
    assert out == envelope
    made = calls(world)
    assert made == [["logs", "r1", "c1", "--phase", "verify", "--repo-dir", proj]]
    assert "--attempt" not in made[0]


@pytest.mark.parametrize("attempt", ["00", " 0", ""], ids=["double-zero", "space-zero", "empty"])
def test_only_the_literal_0_is_a_step(world, attempt):
    # The helper never parses ATTEMPT: anything but the string "0" goes to am as is.
    set_logs(world, {"ok": True, "data": logs_data()})
    proj = str(world["proj"])
    code, _ = run(world, [proj, "r1", "c1", "verify", attempt])
    assert code == 0
    assert calls(world) == [["logs", "r1", "c1", "--phase", "verify", "--attempt", attempt,
                             "--repo-dir", proj]]


def test_a_step_refusal_passes_through(world):
    # synthetic: am's refusal of a step that records no log yet; no capture holds one.
    refusal = {"ok": False, "error": {"type": "UnknownAttemptError",
                                      "message": "phase 'worktree' has no recorded attempt yet"}}
    set_logs(world, refusal, code=3)
    proj = str(world["proj"])
    code, out = run(world, [proj, "r1", "c1", "worktree", "0"])
    assert code == 0
    assert out == refusal
    assert calls(world) == [["logs", "r1", "c1", "--phase", "worktree", "--repo-dir", proj]]


@pytest.mark.parametrize("attempt", ["2", "0"], ids=["attempt", "step"])
@pytest.mark.parametrize("where", ["elsewhere", "root"])
def test_a_cwd_outside_the_repo_still_reaches_it(world, attempt, where):
    # am resolves the run against --repo-dir only; the helper's cwd never matters.
    write_exec(world["bin"] / "am", REPO_CHECKING_AM)
    envelope = {"ok": True, "data": logs_data()}
    set_logs(world, envelope)
    proj = str(world["proj"])
    if where == "elsewhere":
        cwd = world["tmp"] / "elsewhere"
        cwd.mkdir()
    else:
        cwd = "/"
    assert str(cwd) != proj
    code, out = run(world, [proj, "r1", "c1", "implement", attempt], cwd=str(cwd),
                    FAKE_AM_REPO=proj)
    assert code == 0
    assert out == envelope
    made = calls(world)
    assert len(made) == 1
    assert made[0][-2:] == ["--repo-dir", proj]
    assert ("--attempt" in made[0]) == (attempt != "0")


def test_the_repo_checking_am_refuses_another_repo(world):
    # The check above is real: a --repo-dir other than FAKE_AM_REPO is an unknown run.
    write_exec(world["bin"] / "am", REPO_CHECKING_AM)
    set_logs(world, {"ok": True, "data": logs_data()})
    code, out = run(world, FAKE_AM_REPO=str(world["tmp"] / "other"))
    assert code == 0
    assert out == UNKNOWN_RUN
```

- [ ] **Step 4: Run the new tests to verify the right ones fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_logs.py -q -k "attempt_0 or literal_0 or step_refusal or cwd_outside or repo_checking"`

Expected: FAIL for `test_attempt_0_omits_attempt`, `test_a_step_refusal_passes_through` and the two `step` cases of `test_a_cwd_outside_the_repo_still_reaches_it` (am still receives `--attempt 0`, e.g. `assert [['logs', 'r1', 'c1', '--phase', 'verify', '--attempt', '0', ...]] == [[...]]`). PASS for the three `test_only_the_literal_0_is_a_step` cases, the two `attempt` cases of the cwd test and `test_the_repo_checking_am_refuses_another_repo` — these pin behaviour that is already right and must stay right.

- [ ] **Step 5: Implement the step rule**

In `core/backend/runs/runs-logs.py`, replace `logs_argv` (l.46-48):

```python
def logs_argv(root, run, card, phase, attempt):
    """am's argv after the executable: the attempt, then --repo-dir ROOT."""
    return ["logs", run, card, "--phase", phase, "--attempt", attempt, "--repo-dir", root]
```

with:

```python
def logs_argv(root, run, card, phase, attempt):
    """am's argv after the executable: the attempt, then --repo-dir ROOT. ATTEMPT
    exactly "0" omits --attempt (a step: am picks its latest); any other ATTEMPT
    goes to am verbatim."""
    which = [] if attempt == "0" else ["--attempt", attempt]
    return ["logs", run, card, "--phase", phase, *which, "--repo-dir", root]
```

- [ ] **Step 6: Update the module docstring**

In the same file, replace l.2-8:

```python
"""One attempt's output snapshot: an `am logs` passthrough.

    runs-logs.py <project_root> RUN CARD PHASE ATTEMPT

Runs `am logs RUN CARD --phase PHASE --attempt ATTEMPT --repo-dir ROOT` as an
argv list (no shell, stdin /dev/null, 60 s timeout). The five arguments go to am
verbatim; am refuses bad ones itself.
```

with:

```python
"""One attempt's output snapshot: an `am logs` passthrough.

    runs-logs.py <project_root> RUN CARD PHASE ATTEMPT

The first argument is the repository am resolves the run against; the helper's
cwd never matters. Runs
`am logs RUN CARD --phase PHASE [--attempt ATTEMPT] --repo-dir ROOT` as an argv
list (no shell, stdin /dev/null, 60 s timeout). ATTEMPT 0 omits --attempt (a
step: am picks its latest). The arguments go to am verbatim; am refuses bad
ones itself.
```

(`USAGE` on l.34 is not touched.)

- [ ] **Step 7: Run the whole helper test file**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_logs.py -q`
Expected: all PASS (the existing `test_exact_am_argv`, `test_args_reach_am_verbatim`, `test_root_reaches_am_unnormalised`, `test_root_that_is_a_file_is_left_to_am`, `test_missing_fixture_unknown_run`, `test_usage_wrong_argc` unchanged and green).

- [ ] **Step 8: Update `docs/architecture.md` l.201**

In the long `core/backend/runs/` paragraph (l.201), replace exactly:

```
`runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` is a one-shot `am logs RUN CARD --phase P --attempt N --repo-dir R` passthrough: a 60 s timeout, exactly one JSON line.
```

with:

```
`runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` is a one-shot `am logs RUN CARD --phase P [--attempt N] --repo-dir R` passthrough (ATTEMPT 0 omits `--attempt`): a 60 s timeout, exactly one JSON line.
```

- [ ] **Step 9: Run the architecture tests**

Run: `uv run --with pytest python3 -m pytest tests/architecture -q`
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add core/backend/runs/runs-logs.py tests/core/backend/runs/test_runs_logs.py docs/architecture.md
git commit -m "feat(runs): runs-logs.py asks for a step with ATTEMPT 0 and reads from --repo-dir whatever its cwd"
```

---

### Task 2: `RunStore.fetchLogs` passes the run's `repo_dir`

**Files:**
- Modify: `core/stores/RunStore.qml:817-830`
- Test: `tests/core/stores/tst_run_store.qml:2689-2711,5645-5654`
- Modify: `docs/architecture.md:90`

**Interfaces:**
- Consumes: the CLI `runs-logs.py REPO RUN CARD PHASE ATTEMPT` from Task 1 (REPO is am's `--repo-dir`). From the test file: `opened()`, `makeWithProject(root)`, `crossStore(open, aRuns, bRuns)`, `bWork(e)` (sets `e.repo_dir = tc.bRepo`, `"/home/u/b-work"`), `held(e, root)` (normalized run, no project root unless `root` given), `treeEntry(id, status, root)` (row `repo_dir` = `root || rootA`), `argv(proc)` (`proc.command.join("|")`), `tc.openCard`, `tc.rootA` (`"/home/u/my proj"`), `tc.rootB` (`"/home/u/b"`).
- Produces: `fetchLogs()` launches `logsRunner.run([run.repo_dir, selectedRunId, card_id, phase, String(attempt)])`; nothing when `run` is null or `run.repo_dir` is not a non-empty string.

- [ ] **Step 1: Rewrite the two argv tests (tests 5 and 6)**

In `tests/core/stores/tst_run_store.qml`, replace l.2689-2711 — from the comment `// The logs launch: python3, the script, then the project root and the` through the closing `}` of `test_logs_argv_keeps_an_odd_root_verbatim` — with:

```qml
  // The logs launch: python3, the script, then the run's repo_dir and the
  // attempt, five arguments; the repository is the selected run's repo_dir,
  // one element, never its project root.
  function test_logs_argv_leads_with_the_runs_repo_dir() {
    var store = crossStore("", [], [bWork(treeEntry("rb", "started", rootB))]); if (!store) return
    compare(store.runById("rb").project.root, "/home/u/b", "the run is rootB's")
    store.selectedRunId = "rb"
    var proc = store.logsRunner.current
    verify(proc, "the default attempt's logs were asked for")
    compare(argv(proc), "python3|/plugin/core/backend/runs/runs-logs.py|/home/u/b-work|rb|" + tc.openCard + "|explore|1")
    compare(proc.command.length, 7, "five arguments after python3 and the script")
    compare(proc.command[2], "/home/u/b-work", "the run's repo_dir")
    verify(proc.command.indexOf("/home/u/b") < 0, "never the project root")
  }

  // The run's repo_dir reaches the runner byte-for-byte.
  function test_logs_argv_keeps_an_odd_repo_dir_verbatim() {
    var odd = "/home/u/o'dd; $x"
    var store = makeWithProject(odd); if (!store) return
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started", odd)]), 0)
    compare(store.runById("r1").repo_dir, odd)
    store.selectedRunId = "r1"
    var proc = store.logsRunner.current
    verify(proc, "the default attempt's logs were asked for")
    compare(proc.command.length, 7)
    compare(proc.command[2], odd, "not split, quoted, trimmed or normalised")
    compare(proc.command[3], "r1")
  }
```

- [ ] **Step 2: Rewrite the no-launch test (test 7)**

Replace l.5645-5654 — from `  // 10` through the closing `}` of `test_no_logs_for_a_selected_run_without_a_project_root` — with:

```qml
  // 10
  function test_no_logs_for_a_selected_run_without_a_repo_dir() {
    var bad = ["", null, 7]
    for (var i = 0; i < bad.length; i++) {
      var label = "repo_dir " + JSON.stringify(bad[i])
      var store = make(); if (!store) return
      var run = held(treeEntry("r1", "started"), rootA)
      run.repo_dir = bad[i]
      store.runs = [run]
      store.selectedRunId = "r1"
      verify(store.selectedAttempt !== null, label + ": the default attempt is selected")
      verify(!store.logsRunner.current, label + ": no logs launch")
      compare(store.logsLoading, false, label)
      compare(store.logsStatus, "", label + ": untouched")
    }
    var noRoot = make(); if (!noRoot) return
    noRoot.runs = [held(treeEntry("r2", "started"))]
    compare(noRoot.runs[0].project.root, undefined, "normalizeRun's project has no root")
    noRoot.selectedRunId = "r2"
    var proc = noRoot.logsRunner.current
    verify(proc, "a run with a repo_dir but no project root launches")
    compare(argv(proc), "python3|/plugin/core/backend/runs/runs-logs.py|/home/u/my proj|r2|" + tc.openCard + "|explore|1")
    compare(noRoot.logsLoading, true)
  }
```

(`logsStatus` defaults to `""`, `core/stores/RunStore.qml:122`.)

Test 8 (`test_logs_of_another_projects_run_load_with_no_project_open`, l.5617-5626) is not edited: its run's `repo_dir` is `/home/u/b`, so its expected argv already holds.

- [ ] **Step 3: Run the store tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: the `== tests/core/stores/tst_run_store.qml` block prints `FAIL!` lines for `test_logs_argv_leads_with_the_runs_repo_dir` (actual `.../runs-logs.py|/home/u/b|rb|...`) and `test_no_logs_for_a_selected_run_without_a_repo_dir` (first a launch for `repo_dir ""`, since the run has a project root). `test_logs_argv_keeps_an_odd_repo_dir_verbatim` passes already (its root and `repo_dir` are the same string). The script exits non-zero.

- [ ] **Step 4: Implement `fetchLogs` on `repo_dir`**

In `core/stores/RunStore.qml`, replace l.817-830:

```qml
  // One runs-logs.py launch for the selected attempt, the selected run's
  // project root first, remembering the status it was launched for (a
  // snapshot that changes it fetches again). Nothing launches for a run not
  // in the snapshot or one with no project root.
  function fetchLogs() {
    var sel = store.selectedAttempt
    if (store.selectedRunId === "" || !sel) return
    var run = store.runById(store.selectedRunId)
    var root = store.runRoot(run)
    if (root === "") return
    store.logsStatus = Runs.attemptStatus(run, sel.card_id, sel.phase, sel.attempt)
    store.logsLoading = true
    logsRunner.run([root, store.selectedRunId, sel.card_id, sel.phase, String(sel.attempt)])
  }
```

with:

```qml
  // One runs-logs.py launch for the selected attempt, the selected run's
  // repo_dir first, remembering the status it was launched for (a snapshot
  // that changes it fetches again). Nothing launches for a run not in the
  // snapshot or one with no repo_dir.
  function fetchLogs() {
    var sel = store.selectedAttempt
    if (store.selectedRunId === "" || !sel) return
    var run = store.runById(store.selectedRunId)
    if (run === null || typeof run.repo_dir !== "string" || run.repo_dir === "") return
    store.logsStatus = Runs.attemptStatus(run, sel.card_id, sel.phase, sel.attempt)
    store.logsLoading = true
    logsRunner.run([run.repo_dir, store.selectedRunId, sel.card_id, sel.phase, String(sel.attempt)])
  }
```

(`runRoot` above it stays as is.)

- [ ] **Step 5: Run the store tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: pytest green; `tests/core/stores/tst_run_store.qml` prints `Totals: N passed, 0 failed` with no `FAIL!` line, and no `TypeError`/`ReferenceError` line. The existing `tc.logsCmd` (rootA) and `tc.capRoot` asserts stay green because those fixtures' `repo_dir` equals their root.

- [ ] **Step 6: Update `docs/architecture.md` l.90**

Replace exactly:

```
`logsRunner` (`runs-logs.py` with the selected run's project root first, then the run, card, phase and attempt; no guard, so a reply is applied whatever project is open; nothing launches for a selected run with no project root)
```

with:

```
`logsRunner` (`runs-logs.py` with the selected run's `repo_dir` first, then the run, card, phase and attempt; no guard, so a reply is applied whatever project is open; nothing launches for a selected run with no `repo_dir`)
```

- [ ] **Step 7: Run the full gate**

Run: `bash tests/run.sh; echo "exit=$?"`
Expected: pytest all pass; every `tst_*.qml` block reports `0 failed` with no error lines (`tests/ui/tst_runs_flow.qml` and `tst_runs_real_data.qml` assert only the script path and are unaffected); `exit=0`.

- [ ] **Step 8: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml docs/architecture.md
git commit -m "feat(runs): RunStore.fetchLogs hands runs-logs.py the run's repo_dir"
```
<!-- task-pipeline: validated -->
