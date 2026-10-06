# 3.2 runs-logs.py: takes the project root and passes --repo-dir — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `core/backend/runs/runs-logs.py` takes the project root as its first argument and runs `am logs RUN CARD --phase PHASE --attempt ATTEMPT --repo-dir ROOT`, so a logs fetch resolves the run from any cwd instead of failing with `UnknownRunError`.

**Architecture:** One helper changes: `USAGE`, the module docstring, `logs_argv` (gains a leading `root` parameter and appends `"--repo-dir", root`) and `main`'s argument count (`4` → `5`). `main` keeps calling `logs_argv(*argv)`, so the argument order `ROOT RUN CARD PHASE ATTEMPT` maps straight onto `logs_argv(root, run, card, phase, attempt)`. Everything after the argv (stdin `/dev/null`, 60 s timeout, envelope checks, `guarded`) is untouched. Tests in `tests/core/backend/runs/test_runs_logs.py` get a project dir named `my proj; echo x` in the `world` fixture (as `tests/core/backend/runs/test_runs_snapshot.py:73` does) and every default call carries it as the root. One sentence of `docs/architecture.md:199` is corrected.

**Tech Stack:** Python 3 (stdlib only: `json`, `os`, `shutil`, `subprocess`, `sys`), pytest. On this machine `python3` has no pytest, so run single test files with `uv run --with pytest python3 -m pytest <path> -q` (this is the same fallback `tests/run.sh` uses). The whole suite is `bash tests/run.sh` (pytest over `tests/`, then every `tst_*.qml` through `qmltestrunner`).

**Spec:** `docs/superpowers/specs/3-2-runs-logs-py-takes-f7473bf0.md` (prepended below, headings demoted one level; executors read both).

## Global Constraints

- Command line: `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT`, exactly five arguments.
- `USAGE = "usage: runs-logs.py <project_root> RUN CARD PHASE ATTEMPT"`; any other argument count prints exactly `{"ok": false, "error": {"type": "Usage", "message": "usage: runs-logs.py <project_root> RUN CARD PHASE ATTEMPT"}}` and exits 2; am is not looked up and not run.
- am's argv after the executable is exactly `["logs", RUN, CARD, "--phase", PHASE, "--attempt", ATTEMPT, "--repo-dir", ROOT]`: `--repo-dir` last, no `--pretty`, no other option.
- All five arguments reach am as single argv elements, unchanged. The helper does not check that `ROOT` exists or is a directory, does not normalise it, and does not `chdir` into it.
- Unchanged: am's stdin is `/dev/null`; `AM_TIMEOUT = 60`; am's envelope printed as one JSON line whatever am's exit code; `AmMissing`; `AmBadOutput` (message names `am logs` and am's exit code); `HelperError` ("The logs snapshot failed: …"); exit 0 on every path but Usage; exactly one JSON line on every path.
- The sentence "No --repo-dir is sent: am resolves the run by id." is removed from the module docstring; `logs_argv`'s docstring carries no "No --repo-dir" claim.
- `docs/architecture.md:199`: only the `runs-logs.py` sentence changes, to exactly `` `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` is a one-shot `am logs RUN CARD --phase P --attempt N --repo-dir R` passthrough: a 60 s timeout, exactly one JSON line. ``
- Not changed: `core/stores/RunStore.qml`, its QML tests, `runs-snapshot.py`, `runs-watch.py`, `run-control.py`, `README.md`, the rest of `docs/architecture.md`, the fixtures, the fake am in the test file.
- Every unit test builds am output from `tests/fixtures/am/` (`json.load`); a hand-written am payload only for a synthetic edge case, with a `synthetic:` comment.
- Docstrings and comments state the contract only, no narrative.
- `docs/architecture.md` layering holds and `tests/architecture` passes; `bash tests/run.sh` green at the end; tests first (red before green). Never `git stash`.

## Review Focus

1. A relative root such as `.` (or `../proj`): expected to reach am exactly as given, not made absolute — am resolves it against the helper's cwd, which is the caller's business. Pinned in Task 1 Step 2 (`test_root_reaches_am_unnormalised`, case `relative-dot`).
2. A root with a trailing slash (`/some/proj/`): expected verbatim, not stripped. Pinned in Task 1 Step 2 (`test_root_reaches_am_unnormalised`, case `trailing-slash`).
3. An empty-string root `""` with the four other arguments: expected five arguments, so not `Usage`; am gets `"--repo-dir", ""` and refuses it itself. Pinned in Task 1 Step 2 (`test_root_reaches_am_unnormalised`, case `empty`).
4. A root that begins with a dash (`-proj`): expected one argv element right after `--repo-dir`, never split or dropped. Pinned in Task 1 Step 2 (`test_root_reaches_am_unnormalised`, case `leading-dash`).
5. A root that exists but is a regular file, not a directory: expected the helper not to check it and am's refusal envelope passed through on one line with exit 0. Pinned in Task 1 Step 2 (`test_root_that_is_a_file_is_left_to_am`).

---

## Spec (prepended; headings demoted one level)

## 3.2 runs-logs.py: takes the project root and passes --repo-dir — design

Card `f7473bf0`, a subtask of story `44b929b5` ("Attempt output from real am
logs"), blocked by `d6a2e642` (3.1, `logTail`, landed as `eb63dbe`). Parent
spec: `docs/superpowers/specs/2026-10-05-align-run-model-design.md` (below:
**parent**). Work breakdown item 3 (parent L327-328) lists "`logTail`,
`runs-logs.py --repo-dir`, `RunStore` passing the root, and a real-data flow
test": this subtask is `runs-logs.py --repo-dir` only.

### Goal

`am logs` resolves a run against `--repo-dir`, which defaults to `.`; from any
other directory am refuses with `UnknownRunError` (parent L58-60). The helper
sends no `--repo-dir` today (`core/backend/runs/runs-logs.py:46-48`), so every
logs fetch from the panel is `UnknownRunError` (parent L112). After this
subtask the helper takes the project root as its first argument and passes it
to am as `--repo-dir`, so a fetch works from any cwd.

### Inherited constraints

| constraint | source |
|---|---|
| `am logs RUN CARD --phase P --attempt N --repo-dir R` is the command; `--repo-dir` defaults to `.`; without it, from any other directory, am refuses with `UnknownRunError` | parent L55-60 |
| The defect: `runs-logs.py:44-48` builds the `am logs` argv without `--repo-dir`; every logs fetch is `UnknownRunError` | parent L112 |
| Decision 7: `runs-logs.py` takes the project root first and passes `--repo-dir` | parent L169-171 |
| Work item 3 splits into `logTail`, `runs-logs.py --repo-dir`, `RunStore` passing the root, a real-data flow test | parent L327-328 |
| Every unit test of the `runs-*` helpers builds am output from `tests/fixtures/am/` (`json.load` in Python); a hand-written am payload only for a synthetic edge case, with a `synthetic:` comment | parent L257-267, L269, card |
| Usage becomes `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT`; am's argv is `logs RUN CARD --phase PHASE --attempt ATTEMPT --repo-dir ROOT`; everything else unchanged | card |
| Tests in `tests/core/backend/runs/test_runs_logs.py`: argv pinned; the old 4 args is `Usage` | card |
| `docs/architecture.md` layering; `tests/architecture` passes | card |
| Docstrings and comments state the contract only, no narrative | card |
| `bash tests/run.sh` green; tests first | card |

Model: `core/backend/runs/runs-snapshot.py` already takes `<project_root>`
(`USAGE` L29, `len(argv) != 1` L122) and passes it verbatim as `--repo-dir`
(L112, L129); its test pins this with a project dir named `my proj; echo x`
(`tests/core/backend/runs/test_runs_snapshot.py:73`, `:174`, `:358-366`).

### Behavior

Command line: `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT`, exactly
five arguments.

1. **Usage.** Any argument count other than five (zero, four — the old form —,
   six, …) prints exactly one line
   `{"ok": false, "error": {"type": "Usage", "message": "usage: runs-logs.py <project_root> RUN CARD PHASE ATTEMPT"}}`
   and exits 2. am is not looked up and not run.
2. **am's argv.** With five arguments `ROOT RUN CARD PHASE ATTEMPT`, am is run
   once with exactly
   `["logs", RUN, CARD, "--phase", PHASE, "--attempt", ATTEMPT, "--repo-dir", ROOT]`
   after the executable: `--repo-dir` last, no `--pretty`, no other option.
3. **Verbatim.** All five arguments reach am as single argv elements, unchanged:
   spaces, shell metacharacters (`;`, `$(…)`, `&`) and a leading dash are not
   interpreted, split or validated. The helper does not check that `ROOT`
   exists or is a directory, does not normalise it, and does not `chdir` into
   it; am refuses a bad root itself (its envelope is passed through, rule 4).
4. **Unchanged.** Everything after the argv is as today: am's stdin is
   `/dev/null`; 60 s timeout (`AM_TIMEOUT = 60`); am's envelope printed as one
   JSON line whatever am's exit code (`ok` decides); `AmMissing` when am is not
   on PATH; `AmBadOutput` (message names `am logs` and am's exit code) when
   stdout is not a JSON object with a boolean `ok`; `HelperError` ("The logs
   snapshot failed: …") on a timeout or an am that cannot start; exit 0 on
   every path but Usage; exactly one JSON line on every path.

#### Contract text

- Module docstring: the usage line is `runs-logs.py <project_root> RUN CARD
  PHASE ATTEMPT`; it runs `am logs RUN CARD --phase PHASE --attempt ATTEMPT
  --repo-dir ROOT`; the five arguments go to am verbatim. The sentence "No
  --repo-dir is sent: am resolves the run by id." is removed (it is false).
  The Usage bullet says "exactly five arguments".
- `USAGE = "usage: runs-logs.py <project_root> RUN CARD PHASE ATTEMPT"`.
- `logs_argv` takes the root and returns the argv of rule 2; its docstring
  states am's argv after the executable, with no "No --repo-dir" claim.
- `docs/architecture.md:199`: the `runs-logs.py` sentence becomes
  `` `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` is a one-shot `am logs RUN CARD --phase P --attempt N --repo-dir R` passthrough: a 60 s timeout, exactly one JSON line. ``
  (the false "no `--repo-dir` (am resolves the run by id)" clause goes; the
  rest of the paragraph is untouched). This keeps the architecture doc true
  for the code on this branch; the milestone's docs pass (parent L331) is not
  pre-empted.

### Tests

All in `tests/core/backend/runs/test_runs_logs.py`. Tier: pytest backend
helper, hermetic (fake `am` on a temp PATH serving `tests/fixtures/am/`, temp
HOME / XDG_DATA_HOME). Why this tier: the change is the helper's command line
and the argv it hands a subprocess; the fake am records argv in `calls.log`,
which is exactly the observable, and no QML, store or real am is involved.

Fixture setup: the `world` fixture gains `proj`, a temp directory named
`my proj; echo x` (as `test_runs_snapshot.py:73`), so every default call
carries a root that would break through a shell. The default argv becomes
`[str(world["proj"]), "r1", "c1", "implement", "2"]`; every caller of the old
module-level `ARGS` (`run()` default, the stdin test's `Popen`, the timeout
test's `guarded(...)`) uses it. am payloads keep coming from
`fixture("logs-attempt.json")` via `json.load`; existing `synthetic:` labels
stay. The fake am needs no change (it keys on the subcommand `logs`).

Changed tests (each fails against the current helper first):

- **`test_exact_am_argv`**: am called once with
  `["logs", "r1", "c1", "--phase", "implement", "--attempt", "2", "--repo-dir", <proj>]`;
  `"--pretty"` not in it. The old `"--repo-dir" not in made[0]` assertion is
  removed.
- **`test_args_reach_am_verbatim`**: root `str(world["tmp"] / "r$(id) & z")`
  (not created) plus the existing `["r 1; echo x", "c$(whoami)", "plan & review", "-1"]`; am gets
  `["logs", "r 1; echo x", "c$(whoami)", "--phase", "plan & review", "--attempt", "-1", "--repo-dir", <root>]`.
  Also shows the root is not checked for existence.
- **`test_missing_fixture_unknown_run`**: the recorded argv ends with
  `["--repo-dir", <proj>]` (full list as in `test_exact_am_argv`).
- **`test_usage_wrong_argc`** (parametrized): `[]` ("none"), the old four
  `["r1", "c1", "implement", "2"]` ("old-four"), the root plus three
  (`[proj, "r1", "c1", "implement"]`, "four-with-root"), and six
  (`[proj, "r1", "c1", "implement", "2", "extra"]`, "six") each exit 2 with
  exactly `{"ok": false, "error": {"type": "Usage", "message": "usage: runs-logs.py <project_root> RUN CARD PHASE ATTEMPT"}}`
  and `calls(world) == []`.

Unchanged tests, run with the new default argv and still green: capture
identity, ok passthrough, pretty-printed output to one line, refusal passthrough,
`ok` over exit code and stderr, large/unicode output, am ignores stdin,
non-JSON / non-object / no-`ok` → `AmBadOutput`, `AmMissing`, cannot start →
`HelperError`, timeout → `HelperError` (`AM_TIMEOUT == 60`).

Suite gate: `bash tests/run.sh` green, including `tests/architecture` (no new
component, no icon) and the QML store and flow tests, which stub `HelperRunner`
and so do not run the helper.

### Out of scope

- `core/stores/RunStore.qml` passing the project root to `logsRunner.run`
  (`:370` sends four arguments today), and the QML tests that pin that command
  (`tests/core/stores/tst_run_store.qml:17`, `tests/ui/tst_runs_flow.qml:221-222`):
  the "`RunStore` passing the root" subtask of this story (parent L327-328).
  Until it lands, a real panel fetch gets `Usage` instead of `UnknownRunError`;
  the QML tests stay green because they stub the runner.
- The real-data flow test of the whole chain: the same story's later subtask.
- `logTail` (3.1, done); `runs-snapshot.py`, `runs-watch.py`, `run-control.py`;
  cancel spellings and hello schemas (work item 4).
- ATTEMPT `0` / omitted `--attempt` (deterministic-phase logs; parent L316-317)
  and any validation of RUN, CARD, PHASE, ATTEMPT or ROOT by the helper.
- `README.md` and the rest of `docs/architecture.md` beyond the one sentence at
  `:199` (work item 5, parent L331).

---

## File Structure

| file | change | responsibility |
|---|---|---|
| `core/backend/runs/runs-logs.py` | Modify: docstring L1-24, `USAGE` L34, `logs_argv` L46-48, `main` L66 | The `am logs` passthrough; now takes the project root first and sends `--repo-dir` |
| `tests/core/backend/runs/test_runs_logs.py` | Modify: `ARGS` L46, `world` L70-81, `run` L97-104, tests at L143-161, L182-187, L236, L304-312, L343; add two tests | Hermetic tests of the helper's command line, argv and envelopes |
| `docs/architecture.md` | Modify: one sentence on L199 | Architecture doc stays true for the helper on this branch |

One task: the helper's command line, its tests and the doc sentence that describes it change together, and no part can be reviewed apart from the others.

## Task 1: `runs-logs.py` takes the project root and passes `--repo-dir`

**Files:**
- Modify: `core/backend/runs/runs-logs.py:1-24` (docstring), `:34` (`USAGE`), `:46-48` (`logs_argv`), `:66` (`main` argument count)
- Modify: `docs/architecture.md:199` (one sentence)
- Test: `tests/core/backend/runs/test_runs_logs.py`

**Interfaces:**
- Consumes: nothing from earlier tasks. Existing in the test file and unchanged: `fixture(name)`, `logs_data()`, `write_exec(path, text)`, `env_for(world, drop=(), **extra)`, `set_logs(world, envelope, code=0)`, `set_raw(world, text, code=0, stderr=None)`, `calls(world)`, `load_helper()`, `UNKNOWN_RUN`, `FAKE_AM` (keys on the subcommand `logs`; no change needed).
- Produces:
  - Command line `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` (the later "`RunStore` passing the root" subtask calls it with the root first).
  - `runs-logs.py` module: `USAGE = "usage: runs-logs.py <project_root> RUN CARD PHASE ATTEMPT"`; `logs_argv(root, run, card, phase, attempt) -> list[str]` returning `["logs", run, card, "--phase", phase, "--attempt", attempt, "--repo-dir", root]`; `AM_TIMEOUT = 60`, `main(argv)`, `guarded(argv)` keep their signatures.
  - Test file: `RUN_ARGS = ["r1", "c1", "implement", "2"]` (replaces `ARGS`), `default_args(world) -> list[str]` returning `[str(world["proj"]), *RUN_ARGS]`; `world["proj"]` is a created temp dir named `my proj; echo x`.

- [ ] **Step 1: Give the test world a project root and make it the default first argument**

In `tests/core/backend/runs/test_runs_logs.py`:

Replace line 46

```python
ARGS = ["r1", "c1", "implement", "2"]
```

with

```python
RUN_ARGS = ["r1", "c1", "implement", "2"]
```

Replace the whole `world` fixture (lines 70-81)

```python
@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am, its fixture dir, and a temp HOME/XDG_DATA_HOME."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "am", FAKE_AM)
    amdir = tmp_path / "am"
    amdir.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    return {"tmp": tmp_path, "bin": bindir, "am": amdir, "home": home,
            "data": tmp_path / "data"}
```

with

```python
@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am, its fixture dir, a temp HOME/XDG_DATA_HOME, and a
    project root whose name would break if it ever went through a shell."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "am", FAKE_AM)
    amdir = tmp_path / "am"
    amdir.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    proj = tmp_path / "my proj; echo x"
    proj.mkdir()
    return {"tmp": tmp_path, "bin": bindir, "am": amdir, "home": home,
            "data": tmp_path / "data", "proj": proj}


def default_args(world):
    """The helper's argv for one attempt of the world's project."""
    return [str(world["proj"]), *RUN_ARGS]
```

Replace the first line of `run`'s body (line 99)

```python
    argv = ARGS if args is None else args
```

with

```python
    argv = default_args(world) if args is None else args
```

In `test_am_does_not_inherit_stdin`, replace (line 236)

```python
    p = subprocess.Popen([sys.executable, SCRIPT, *ARGS], stdin=subprocess.PIPE,
```

with

```python
    p = subprocess.Popen([sys.executable, SCRIPT, *default_args(world)], stdin=subprocess.PIPE,
```

In `test_am_timeout_is_helper_error`, replace (line 343)

```python
    code = helper.guarded(list(ARGS))
```

with

```python
    code = helper.guarded(default_args(world))
```

Check no use of the old name is left:

Run: `grep -n "\bARGS\b" tests/core/backend/runs/test_runs_logs.py`
Expected: no output (exit 1).

- [ ] **Step 2: Rewrite the argv and usage tests, and add the root tests**

Still in `tests/core/backend/runs/test_runs_logs.py`.

Replace `test_exact_am_argv` and `test_args_reach_am_verbatim` (lines 143-161)

```python
def test_exact_am_argv(world):
    set_logs(world, {"ok": True, "data": logs_data()})
    code, _ = run(world)
    assert code == 0
    made = calls(world)
    assert made == [["logs", "r1", "c1", "--phase", "implement", "--attempt", "2"]]
    assert "--repo-dir" not in made[0]
    assert "--pretty" not in made[0]


def test_args_reach_am_verbatim(world):
    # Spaces, shell metacharacters and a leading dash must each arrive as one argv
    # element: no shell, no validation by the helper.
    args = ["r 1; echo x", "c$(whoami)", "plan & review", "-1"]
    set_logs(world, {"ok": True, "data": logs_data()})
    code, _ = run(world, args)
    assert code == 0
    assert calls(world) == [["logs", "r 1; echo x", "c$(whoami)",
                             "--phase", "plan & review", "--attempt", "-1"]]
```

with

```python
def test_exact_am_argv(world):
    # The project dir is named "my proj; echo x": it must arrive as one argv element.
    set_logs(world, {"ok": True, "data": logs_data()})
    code, _ = run(world)
    assert code == 0
    made = calls(world)
    assert made == [["logs", "r1", "c1", "--phase", "implement", "--attempt", "2",
                     "--repo-dir", str(world["proj"])]]
    assert "--pretty" not in made[0]


def test_args_reach_am_verbatim(world):
    # Spaces, shell metacharacters and a leading dash must each arrive as one argv
    # element: no shell, no validation by the helper. The root does not exist.
    root = str(world["tmp"] / "r$(id) & z")
    args = [root, "r 1; echo x", "c$(whoami)", "plan & review", "-1"]
    set_logs(world, {"ok": True, "data": logs_data()})
    code, _ = run(world, args)
    assert code == 0
    assert calls(world) == [["logs", "r 1; echo x", "c$(whoami)",
                             "--phase", "plan & review", "--attempt", "-1",
                             "--repo-dir", root]]


@pytest.mark.parametrize("root", [".", "/some/proj/", "", "-proj"],
                         ids=["relative-dot", "trailing-slash", "empty", "leading-dash"])
def test_root_reaches_am_unnormalised(world, root):
    # The root is neither resolved, stripped nor checked: am refuses a bad one itself.
    set_logs(world, {"ok": True, "data": logs_data()})
    code, _ = run(world, [root, *RUN_ARGS])
    assert code == 0
    assert calls(world) == [["logs", "r1", "c1", "--phase", "implement", "--attempt", "2",
                             "--repo-dir", root]]


def test_root_that_is_a_file_is_left_to_am(world):
    root = world["tmp"] / "not-a-dir"
    root.write_text("")
    # synthetic: am's refusal of a repo dir that is not a directory; no capture holds one.
    refusal = {"ok": False, "error": {"type": "UsageError",
                                      "message": "--repo-dir is not a directory"}}
    set_logs(world, refusal, code=3)
    code, out = run(world, [str(root), *RUN_ARGS])
    assert code == 0
    assert out == refusal
    assert calls(world) == [["logs", "r1", "c1", "--phase", "implement", "--attempt", "2",
                             "--repo-dir", str(root)]]
```

Replace `test_missing_fixture_unknown_run` (lines 182-187)

```python
def test_missing_fixture_unknown_run(world):
    # No logs.out: the fake am answers UnknownRunError with exit 3.
    code, out = run(world)
    assert code == 0
    assert out == UNKNOWN_RUN
    assert calls(world) == [["logs", "r1", "c1", "--phase", "implement", "--attempt", "2"]]
```

with

```python
def test_missing_fixture_unknown_run(world):
    # No logs.out: the fake am answers UnknownRunError with exit 3.
    code, out = run(world)
    assert code == 0
    assert out == UNKNOWN_RUN
    assert calls(world) == [["logs", "r1", "c1", "--phase", "implement", "--attempt", "2",
                             "--repo-dir", str(world["proj"])]]
```

Replace `test_usage_wrong_argc` (lines 304-312)

```python
@pytest.mark.parametrize("args", [["r1", "c1", "implement"],
                                  ["r1", "c1", "implement", "2", "extra"]],
                         ids=["three", "five"])
def test_usage_wrong_argc(world, args):
    code, out = run(world, args)
    assert code == 2
    assert out == {"ok": False, "error": {"type": "Usage",
                                          "message": "usage: runs-logs.py RUN CARD PHASE ATTEMPT"}}
    assert calls(world) == []
```

with

```python
@pytest.mark.parametrize("shape", ["none", "old-four", "four-with-root", "six"])
def test_usage_wrong_argc(world, shape):
    proj = str(world["proj"])
    args = {
        "none": [],
        "old-four": ["r1", "c1", "implement", "2"],
        "four-with-root": [proj, "r1", "c1", "implement"],
        "six": [proj, "r1", "c1", "implement", "2", "extra"],
    }[shape]
    code, out = run(world, args)
    assert code == 2
    assert out == {"ok": False, "error": {
        "type": "Usage",
        "message": "usage: runs-logs.py <project_root> RUN CARD PHASE ATTEMPT"}}
    assert calls(world) == []
```

(The parameter is a shape name, not the argv itself, because the root only exists once the `world` fixture has run.)

- [ ] **Step 3: Run the helper's tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_logs.py -q`
Expected: FAIL. The current helper accepts only four arguments, so every test that runs it with five (`default_args(world)` or `[root, *RUN_ARGS]`) gets `Usage` with exit 2 instead of exit 0 — e.g. `test_exact_am_argv` fails on `assert code == 0` (`assert 2 == 0`), `test_am_timeout_is_helper_error` fails on `assert code == 0`. `test_usage_wrong_argc[old-four]` fails because the old helper runs am (`calls(world)` is not `[]`); `[none]`, `[four-with-root]` and `[six]` fail on the old usage message. Only `test_logs_data_is_the_capture` passes.

- [ ] **Step 4: Make the helper take the root and pass `--repo-dir`**

In `core/backend/runs/runs-logs.py`:

Replace the module docstring (lines 1-24)

```python
#!/usr/bin/env python3
"""One attempt's output snapshot: an `am logs` passthrough.

    runs-logs.py RUN CARD PHASE ATTEMPT

Runs `am logs RUN CARD --phase PHASE --attempt ATTEMPT` as an argv list (no
shell, stdin /dev/null, 60 s timeout). No --repo-dir is sent: am resolves the
run by id. The four arguments go to am verbatim; am refuses bad ones itself.
```

(its first eight lines) with

```python
#!/usr/bin/env python3
"""One attempt's output snapshot: an `am logs` passthrough.

    runs-logs.py <project_root> RUN CARD PHASE ATTEMPT

Runs `am logs RUN CARD --phase PHASE --attempt ATTEMPT --repo-dir ROOT` as an
argv list (no shell, stdin /dev/null, 60 s timeout). The five arguments go to am
verbatim; am refuses bad ones itself.
```

and in the same docstring replace

```python
- {"ok": false, "error": {"type": "Usage", ...}} when not given exactly four
  arguments.
```

with

```python
- {"ok": false, "error": {"type": "Usage", ...}} when not given exactly five
  arguments.
```

Replace line 34

```python
USAGE = "usage: runs-logs.py RUN CARD PHASE ATTEMPT"
```

with

```python
USAGE = "usage: runs-logs.py <project_root> RUN CARD PHASE ATTEMPT"
```

Replace `logs_argv` (lines 46-48)

```python
def logs_argv(run, card, phase, attempt):
    """am's argv after the executable. No --repo-dir: am resolves the run by id."""
    return ["logs", run, card, "--phase", phase, "--attempt", attempt]
```

with

```python
def logs_argv(root, run, card, phase, attempt):
    """am's argv after the executable: the attempt, then --repo-dir ROOT."""
    return ["logs", run, card, "--phase", phase, "--attempt", attempt, "--repo-dir", root]
```

In `main`, replace line 66

```python
    if len(argv) != 4:
```

with

```python
    if len(argv) != 5:
```

The call `[am, *logs_argv(*argv)]` on line 71 stays as it is: `argv` is `ROOT RUN CARD PHASE ATTEMPT`, the order of `logs_argv`'s parameters.

Check no stale contract text is left:

Run: `grep -n "four\|No --repo-dir\|resolves the run by id" core/backend/runs/runs-logs.py`
Expected: no output (exit 1).

- [ ] **Step 5: Run the helper's tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_logs.py -q`
Expected: PASS, `33 passed` (26 before; `test_usage_wrong_argc` goes from 2 cases to 4, plus 4 `test_root_reaches_am_unnormalised` cases and `test_root_that_is_a_file_is_left_to_am`).

- [ ] **Step 6: Correct the `runs-logs.py` sentence in `docs/architecture.md`**

In `docs/architecture.md` line 199 (one long paragraph), replace exactly this sentence

```markdown
`runs-logs.py RUN CARD PHASE ATTEMPT` is a one-shot `am logs RUN CARD --phase P --attempt N` passthrough: no `--repo-dir` (am resolves the run by id), a 60 s timeout, exactly one JSON line.
```

with

```markdown
`runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` is a one-shot `am logs RUN CARD --phase P --attempt N --repo-dir R` passthrough: a 60 s timeout, exactly one JSON line.
```

Leave the rest of the paragraph and the file untouched.

Run: `grep -c "am resolves the run by id" docs/architecture.md; grep -c 'runs-logs.py <project_root> RUN CARD PHASE ATTEMPT' docs/architecture.md`
Expected: `0` then `1`.

- [ ] **Step 7: Run the whole suite**

Run: `bash tests/run.sh`
Expected: exit 0; pytest reports no failures (including `tests/architecture` and `tests/core/backend/runs/test_runs_logs.py`), and every `== tests/...tst_*.qml` block shows a `Totals:` line with `0 failed` and no `FAIL!` line. The QML store and flow tests stub `HelperRunner`, so they never run the helper and stay green.

- [ ] **Step 8: Commit**

```bash
git add core/backend/runs/runs-logs.py tests/core/backend/runs/test_runs_logs.py docs/architecture.md
git commit -m "feat(runs): runs-logs.py takes the project root and passes --repo-dir"
```

---

## Self-Review

**Spec coverage.**
- Behavior 1 (Usage on any count but five, exact line, exit 2, am not run): Step 4 (`len(argv) != 5`, `USAGE`), pinned by Step 2 `test_usage_wrong_argc` (none, old-four, four-with-root, six).
- Behavior 2 (am's exact argv, `--repo-dir` last, no `--pretty`): Step 4 `logs_argv`, pinned by `test_exact_am_argv` and `test_missing_fixture_unknown_run`.
- Behavior 3 (verbatim, no existence check, no normalising): pinned by `test_args_reach_am_verbatim` (shell metacharacters, nonexistent root), `test_root_reaches_am_unnormalised`, `test_root_that_is_a_file_is_left_to_am`. No `chdir` is added (Step 4 changes no other line).
- Behavior 4 (unchanged stdin, timeout, envelopes, exits): no code change; existing tests run with the new default argv (Step 1) and stay green in Step 5.
- Contract text (docstring, `USAGE`, `logs_argv` docstring, `docs/architecture.md:199`): Steps 4 and 6, each with a grep check.
- Tests section (world `proj` named `my proj; echo x`, default argv, callers of `ARGS` switched, fixtures via `json.load`, fake am unchanged): Steps 1-2.
- Suite gate: Step 7. Out of scope (RunStore, QML tests, other helpers, README): no step touches them.

**Placeholder scan.** No "TBD", "similar to", or prose-only code steps; every replacement shows the old and new text.

**Type consistency.** `RUN_ARGS`, `default_args(world)`, `world["proj"]` are defined in Step 1 and used with those names in Step 2; `logs_argv(root, run, card, phase, attempt)` matches `main`'s `logs_argv(*argv)` with argv `ROOT RUN CARD PHASE ATTEMPT`; the usage message is identical in `USAGE`, the test and Global Constraints.

**Review Focus.** Each of the five lines has its test in Step 2 (`test_root_reaches_am_unnormalised` four cases; `test_root_that_is_a_file_is_left_to_am`). All five fail against the current helper (five arguments → `Usage`), so they are red before Step 4.
<!-- task-pipeline: validated -->
