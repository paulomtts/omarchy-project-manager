# 2.1 runs-logs.py: attempt 0 means am's newest — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `core/backend/runs/runs-logs.py` sends no `--attempt` to `am logs` when ATTEMPT is exactly the string `"0"`, so a deterministic step's newest output (which `am status` records no attempt for) becomes reachable.

**Architecture:** One function changes: `logs_argv(root, run, card, phase, attempt)` builds `["--attempt", attempt]` only when `attempt != "0"`, by string comparison (no integer parsing). `main`, `envelope_of`, `guarded`, `USAGE`, `AM_TIMEOUT` and every error path are untouched. The module docstring and `logs_argv`'s docstring are rewritten to state both forms. New integration tests go in `tests/core/backend/runs/test_runs_logs.py`, driving the real script as a subprocess against the file's existing fake `am`.

**Tech Stack:** Python 3 stdlib, pytest. On this machine `python3` has no pytest, so run one test file with `uv run --with pytest python3 -m pytest <path> -q` (the same fallback `tests/run.sh` uses). The whole suite is `bash tests/run.sh` (pytest over `tests/` including `tests/architecture`, then every `tst_*.qml` through `qmltestrunner`).

**Spec:** `docs/superpowers/specs/2-1-runs-logs-py-e69a6c2d.md` (prepended below, headings demoted one level; executors read both). Milestone design: `docs/superpowers/specs/2026-10-05-resume-recover-design.md`.

## Global Constraints

- Command line unchanged: `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT`, exactly five arguments; `USAGE = "usage: runs-logs.py <project_root> RUN CARD PHASE ATTEMPT"`.
- ATTEMPT exactly `"0"` → am's argv after the executable is exactly `["logs", RUN, CARD, "--phase", PHASE, "--repo-dir", ROOT]` (no `--attempt`, no `0`).
- Any other ATTEMPT (including `"00"`, `"-0"`, `" 0"`, `"+0"`, `"-1"`, `""`) → exactly `["logs", RUN, CARD, "--phase", PHASE, "--attempt", ATTEMPT, "--repo-dir", ROOT]`, ATTEMPT verbatim. The helper validates nothing.
- `am logs` keeps `--repo-dir`, always last.
- Unchanged: no shell, stdin `/dev/null`, `AM_TIMEOUT = 60`, exactly one JSON line on every path, envelope passthrough (`ok` decides, not the exit code), `AmMissing` / `AmBadOutput` / `HelperError` / `Usage` envelopes, exit 0 (2 for Usage only).
- Only documented `am` commands; am's database is never read.
- Docstrings state the contract only, no narrative; the one-line summary must not describe history.
- Not changed: `core/stores/RunStore.qml`, `core/domain/runs.js`, `run-control.py`, `docs/architecture.md`, `README.md`, fixtures, the fake am in the test file, every existing test.
- A hand-written am payload in a test carries a `# synthetic:` comment.
- `bash tests/run.sh` green at the end; tests first (red before green). Never `git stash`.

## Review Focus

1. ATTEMPT `"+0"` (an integer parser would read it as 0): expected verbatim as `"--attempt", "+0"`. Pinned in Task 1 Step 1 (`test_only_exact_zero_is_special`, case `plus-zero`).
2. ATTEMPT with trailing whitespace, `"0 "` or `"0\n"` (a `.strip()` would make it 0): expected verbatim. Pinned in Task 1 Step 1 (`test_only_exact_zero_is_special`, cases `trailing-space`, `trailing-newline`).
3. Attempt 0 for a phase other than `verify` (e.g. `implement`): the rule is per ATTEMPT, not per phase name, so no `--attempt` either. Pinned in Task 1 Step 1 (`test_attempt_zero_sends_no_attempt_flag`, parametrized over `verify` and `implement`).
4. Attempt 0 with the shell-hostile project dir `my proj; echo x`: the root must still arrive as one argv element right after `--repo-dir`. Pinned in Task 1 Step 1 (`test_attempt_zero_sends_no_attempt_flag` uses `world["proj"]`).
5. Attempt 0 with am printing non-JSON: still `AmBadOutput` naming `am logs` and the exit code, on one line, exit 0 — the shorter argv must not bypass the shape check. Pinned in Task 1 Step 1 (`test_attempt_zero_bad_output_is_am_bad_output`).

---

## Spec (prepended; headings demoted one level)

## 2.1 runs-logs.py: attempt 0 means am's newest (card e69a6c2d)

Parent: story d44f2afe. Milestone spec: `docs/superpowers/specs/2026-10-05-resume-recover-design.md`
(cited below as "design").

### Why

A failed deterministic step (for example `verify`) records no attempts in `am status`
(`attempts: []`), yet `am logs RUN CARD --phase verify` with no `--attempt` returns that
phase's newest recorded output (design, Problem, lines 48-56). Later subtasks select such a
step as "attempt 0" (design, Behaviour, lines 156-160; Architecture, line 245). This card
makes the helper translate attempt 0 into "no `--attempt`", so that output becomes reachable.

### Behaviour

`core/backend/runs/runs-logs.py <project_root> RUN CARD PHASE ATTEMPT`:

1. When `ATTEMPT` is exactly the string `0`, the helper runs
   `am logs RUN CARD --phase PHASE --repo-dir ROOT`, with no `--attempt` flag and no `0`
   anywhere in the argv (design, Architecture, lines 253-254).
2. Any other `ATTEMPT` value is passed verbatim, as today:
   `am logs RUN CARD --phase PHASE --attempt ATTEMPT --repo-dir ROOT`. Only the exact string
   `0` is special. `00`, `-0`, ` 0`, `+0`, `-1` and the empty string all go through
   unchanged, and am refuses them itself. The helper still validates nothing.
3. Everything else stays as it is (design, line 254: "Everything else unchanged (`am logs`
   keeps `--repo-dir`)"):
   - argument order;
   - `--repo-dir ROOT` last;
   - no shell, stdin `/dev/null`, 60 s timeout;
   - exactly one JSON line on every path;
   - envelope passthrough (`ok` decides, not the exit code);
   - the `AmMissing`, `AmBadOutput`, `HelperError` and `Usage` envelopes;
   - exit codes (0, or 2 for Usage);
   - the `USAGE` string (still five arguments).
4. With attempt 0, am's envelope is passed through unchanged, exactly as for any other
   attempt, and that includes an `ok: false` refusal when am has no output for the phase.
   Showing that error is the store's job (design, Errors table, line 294: "`am logs` has no
   output for the step → the pane's existing error line").

#### Docstrings (contract only, no narrative)

- Module docstring:
  - The usage line stays.
  - The command sentence states both forms. With ATTEMPT `0`, no `--attempt` is sent, so am
    returns the phase's newest recorded output; this is how a step's output is read, because
    steps record no attempts in `am status`. Any other ATTEMPT is sent verbatim with
    `--attempt`.
  - Replace "The five arguments go to am verbatim" with a sentence that stays true: the
    arguments reach am unvalidated, attempt `0` is the one exception, and am refuses bad
    arguments itself.
  - The rest of the docstring is unchanged.
- `logs_argv` docstring: states the same rule. It returns am's argv after the executable,
  with `--attempt ATTEMPT` omitted when ATTEMPT is `"0"`, then `--repo-dir ROOT`.
- The module's one-line summary ("One attempt's output snapshot") may say "one attempt's (or
  the phase's newest) output snapshot". It must not describe history.

### Tests

All new tests go in `tests/core/backend/runs/test_runs_logs.py`. They are integration tier:
the real script runs as a subprocess against the file's existing hermetic fake `am` on a temp
PATH. This is the tier the file already uses, and the behaviour under test is the argv that
actually reaches the `am` executable. Use the existing helpers: `world`, `run`, `set_logs`,
`calls`, `logs_data`, and `RUN_ARGS`. Write the tests first.

1. `test_attempt_zero_sends_no_attempt_flag`: args `[proj, "r1", "c1", "verify", "0"]`. The
   assertions:
   - `calls(world) == [["logs", "r1", "c1", "--phase", "verify", "--repo-dir", proj]]`;
   - `"--attempt"` is not in the argv;
   - the ok envelope comes out unchanged;
   - the exit code is 0.
2. `test_nonzero_attempt_is_sent_verbatim`: parametrized over `"2"` and `"1"`. The argv is
   the full form with `"--attempt", <value>`. `test_exact_am_argv` already covers `"2"`; this
   test pins the contrast with 0 next to it.
3. `test_only_exact_zero_is_special`: parametrized over `"00"`, `"-0"`, `" 0"` and `""`.
   Each value arrives as `"--attempt", <value>`, unchanged. This keeps the "exact string"
   rule: the helper does not parse integers.
4. `test_attempt_zero_refusal_passed_through`: attempt `0`, and the fake am returns a
   synthetic `ok: false` envelope (labelled `# synthetic:`; no capture holds one) with exit 3.
   The output is that envelope, with exit 0.

The existing tests stay unchanged and must still pass: every existing argv assertion uses
attempt `2` or `-1`.

Verification: `bash tests/run.sh` must be green. That covers pytest, including
`tests/architecture`, and the QML tests.

### Out of scope

- `core/stores/RunStore.qml`:
  - `selectAttempt` accepting attempt 0;
  - opening the stop report's attempt;
  - the `(newest)` heading.

  These belong to the store/selection sibling cards (design, lines 262-265 and 313-314).
- `core/domain/runs.js` `stopReport` producing `attempt: 0` (done in story 1).
- `run-control.py` dropping `--repo-dir` from `am status` (design, lines 255-256; another
  card).
- Any other change to `runs-logs.py`'s behaviour, its usage text or its error types.
- Docs outside the two docstrings (`docs/architecture.md` and the README belong to the docs
  card).

### Constraints inherited

- `am logs` keeps `--repo-dir` (design, line 254).
- Only documented `am` commands are used, and am's database is never read (the module
  docstring today; design, Architecture).
- `docs/architecture.md` layering: the helper stays in `core/backend/runs/`, and
  `tests/architecture` must pass.

---

## File Structure

- Modify: `core/backend/runs/runs-logs.py` — module docstring (lines 1-9) and `logs_argv` (lines 46-48). Nothing else in the file changes.
- Modify: `tests/core/backend/runs/test_runs_logs.py` — insert new tests between `test_exact_am_argv` (ends line 161) and `test_args_reach_am_verbatim` (line 164). No existing line changes.

One task: the change is a single function plus its docstrings; splitting tests from the code would leave a reviewer nothing to reject separately.

---

### Task 1: attempt 0 sends no `--attempt`

**Files:**
- Modify: `core/backend/runs/runs-logs.py:1-9` (module docstring), `core/backend/runs/runs-logs.py:46-48` (`logs_argv`)
- Test: `tests/core/backend/runs/test_runs_logs.py` (insert after line 161)

**Interfaces:**
- Consumes: the test file's existing helpers — `world` fixture (dict with `"proj"`, `"am"`, `"bin"`, `"tmp"`), `run(world, args=None, drop=(), **extra) -> (exit_code, payload)` (asserts exactly one stdout line), `set_logs(world, envelope, code=0)`, `set_raw(world, text, code=0, stderr=None)`, `calls(world) -> list[list[str]]`, `logs_data()`, `RUN_ARGS = ["r1", "c1", "implement", "2"]`.
- Produces: `logs_argv(root, run, card, phase, attempt) -> list[str]` — same signature as today; returns `["logs", run, card, "--phase", phase, "--repo-dir", root]` when `attempt == "0"`, else `["logs", run, card, "--phase", phase, "--attempt", attempt, "--repo-dir", root]`. Later cards (`RunStore.selectAttempt`) call the script with ATTEMPT `"0"` and rely on this.

- [ ] **Step 1: Write the tests**

In `tests/core/backend/runs/test_runs_logs.py`, find this exact text (the end of `test_exact_am_argv` and the start of the next test):

```python
    assert "--pretty" not in made[0]


def test_args_reach_am_verbatim(world):
```

and replace it with:

```python
    assert "--pretty" not in made[0]


# --- attempt 0: the phase's newest output ------------------------------------

@pytest.mark.parametrize("phase", ["verify", "implement"])
def test_attempt_zero_sends_no_attempt_flag(world, phase):
    # Attempt 0 means "no --attempt": am returns the phase's newest recorded output,
    # the only way to read a step, which records no attempts in `am status`.
    proj = str(world["proj"])
    envelope = {"ok": True, "data": logs_data()}
    set_logs(world, envelope)
    code, out = run(world, [proj, "r1", "c1", phase, "0"])
    assert code == 0
    assert out == envelope
    made = calls(world)
    assert made == [["logs", "r1", "c1", "--phase", phase, "--repo-dir", proj]]
    assert "--attempt" not in made[0]
    assert "0" not in made[0]


@pytest.mark.parametrize("attempt", ["2", "1"])
def test_nonzero_attempt_is_sent_verbatim(world, attempt):
    proj = str(world["proj"])
    set_logs(world, {"ok": True, "data": logs_data()})
    code, _ = run(world, [proj, "r1", "c1", "verify", attempt])
    assert code == 0
    assert calls(world) == [["logs", "r1", "c1", "--phase", "verify", "--attempt", attempt,
                             "--repo-dir", proj]]


@pytest.mark.parametrize("attempt", ["00", "-0", " 0", "", "+0", "0 ", "0\n"],
                         ids=["double-zero", "minus-zero", "leading-space", "empty",
                              "plus-zero", "trailing-space", "trailing-newline"])
def test_only_exact_zero_is_special(world, attempt):
    # Only the exact string "0" drops --attempt: the helper parses no integers and
    # strips nothing, so am refuses these itself.
    proj = str(world["proj"])
    set_logs(world, {"ok": True, "data": logs_data()})
    code, _ = run(world, [proj, "r1", "c1", "verify", attempt])
    assert code == 0
    assert calls(world) == [["logs", "r1", "c1", "--phase", "verify", "--attempt", attempt,
                             "--repo-dir", proj]]


def test_attempt_zero_refusal_passed_through(world):
    proj = str(world["proj"])
    # synthetic: am's refusal when the phase has no recorded output; no capture holds one.
    refusal = {"ok": False, "error": {"type": "NotFoundError",
                                      "message": "no output recorded for phase verify"}}
    set_logs(world, refusal, code=3)
    code, out = run(world, [proj, "r1", "c1", "verify", "0"])
    assert code == 0
    assert out == refusal
    assert calls(world) == [["logs", "r1", "c1", "--phase", "verify", "--repo-dir", proj]]


def test_attempt_zero_bad_output_is_am_bad_output(world):
    # synthetic: am output that is not JSON.
    set_raw(world, "not json\n", 1)
    code, out = run(world, [str(world["proj"]), "r1", "c1", "verify", "0"])
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "AmBadOutput"
    assert "am logs" in out["error"]["message"]
    assert "(exit 1)" in out["error"]["message"]


def test_args_reach_am_verbatim(world):
```

Note on `"0\n"`: a newline inside one argv element is legal for `subprocess` and the fake am records it via `json.dumps`, so `calls(world)` returns it intact.

- [ ] **Step 2: Run the new tests to verify the right ones fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_logs.py -q -k "attempt_zero or nonzero_attempt or only_exact_zero"`

Expected: exactly 3 FAILED — `test_attempt_zero_sends_no_attempt_flag[verify]`, `test_attempt_zero_sends_no_attempt_flag[implement]` and `test_attempt_zero_refusal_passed_through` — each on the `calls(world) == [...]` assertion, because today's argv still contains `"--attempt", "0"`. The other 10 selected tests PASS already: `test_nonzero_attempt_is_sent_verbatim` and `test_only_exact_zero_is_special` pin behaviour that must not change, and `test_attempt_zero_bad_output_is_am_bad_output` pins the error path for the new argv. (If any of those 10 fails now, stop: the test is wrong, not the helper.)

- [ ] **Step 3: Implement `logs_argv`**

In `core/backend/runs/runs-logs.py`, replace:

```python
def logs_argv(root, run, card, phase, attempt):
    """am's argv after the executable: the attempt, then --repo-dir ROOT."""
    return ["logs", run, card, "--phase", phase, "--attempt", attempt, "--repo-dir", root]
```

with:

```python
def logs_argv(root, run, card, phase, attempt):
    """am's argv after the executable: --attempt ATTEMPT, omitted when ATTEMPT is
    exactly "0" (am's newest output of the phase), then --repo-dir ROOT."""
    chosen = [] if attempt == "0" else ["--attempt", attempt]
    return ["logs", run, card, "--phase", phase, *chosen, "--repo-dir", root]
```

- [ ] **Step 4: Update the module docstring**

In the same file, replace lines 1-8:

```python
#!/usr/bin/env python3
"""One attempt's output snapshot: an `am logs` passthrough.

    runs-logs.py <project_root> RUN CARD PHASE ATTEMPT

Runs `am logs RUN CARD --phase PHASE --attempt ATTEMPT --repo-dir ROOT` as an
argv list (no shell, stdin /dev/null, 60 s timeout). The five arguments go to am
verbatim; am refuses bad ones itself.
```

with:

```python
#!/usr/bin/env python3
"""One attempt's (or the phase's newest) output snapshot: an `am logs` passthrough.

    runs-logs.py <project_root> RUN CARD PHASE ATTEMPT

Runs `am logs RUN CARD --phase PHASE --attempt ATTEMPT --repo-dir ROOT` as an
argv list (no shell, stdin /dev/null, 60 s timeout). With ATTEMPT `0` no
--attempt is sent (`am logs RUN CARD --phase PHASE --repo-dir ROOT`), so am
returns the phase's newest recorded output: this is how a step's output is read,
since steps record no attempts in `am status`. Any other ATTEMPT is sent verbatim
with --attempt. The arguments reach am unvalidated, attempt `0` being the one
exception; am refuses bad ones itself.
```

Everything from the blank line after that paragraph ("Prints exactly one JSON line on EVERY path:") to the closing `"""` stays exactly as it is.

- [ ] **Step 5: Run the whole test file to verify it passes**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_logs.py -q`

Expected: `46 passed` (the 33 existing tests, unchanged, plus 13 new: 2 + 2 + 7 + 1 + 1).

- [ ] **Step 6: Run the full suite**

Run: `timeout 600 bash tests/run.sh`

Expected: pytest reports no failures (including `tests/architecture`), every `== tests/...tst_*.qml` block prints a `Totals:` line with `0 failed`, no `TypeError`/`ReferenceError` lines, and the script exits 0 (`echo $?` → `0`).

- [ ] **Step 7: Commit**

```bash
git add core/backend/runs/runs-logs.py tests/core/backend/runs/test_runs_logs.py
git commit -m "feat(runs-logs): attempt 0 sends no --attempt, so am returns the phase's newest output"
```
<!-- task-pipeline: validated -->
