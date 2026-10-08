# Contract test: the installed `am` has `as_of_seq` and `head` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `tests/contract/test_am_fixtures.py`'s live check run the installed `am` on a scratch store and fail, naming the key and "the plugin needs the newer am", when `am runs` data lacks `as_of_seq` or the `am watch --all --follow` hello lacks `head`.

**Architecture:** One module-level function `live_check(env, repo_dir)` performs the whole live check (runs → rows/status → watch hello). `scratch_env(tmp_path, path=None)` builds the hermetic environment used by both the real live test and stub-`am` unit tests. Stub tests drive `live_check` against an executable `/bin/sh` `am` written into `tmp_path/bin`, whose outputs are derived from `tests/fixtures/am/*.json`.

**Tech Stack:** Python 3, pytest, `subprocess`, POSIX `/bin/sh`. pytest is not installed in the system `python3`; run it as `uv run --with pytest python3 -m pytest ...` (exactly what `tests/run.sh` falls back to).

**Spec:** `docs/superpowers/specs/4-0-1-contract-test-the-f1b95771.md` (reproduced in full in the "Spec" section below).

## Global Constraints

- Only one file changes: `tests/contract/test_am_fixtures.py`. No plugin code, no fixture, no QML, and `tests/contract/test_am_shapes.py` is unchanged (only imported from).
- `am` is called only as argv lists; nothing reads `am.db`, journals or the data-dir layout.
- The live check runs against a scratch data dir (`HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` under `tmp_path`), never the user's real runs.
- The capability check keys on the presence of `head` / `as_of_seq`, not on the hello's schema number.
- Missing-capability messages are exactly `live am runs data: no as_of_seq: the plugin needs the newer am` and `live am watch hello: no head: the plugin needs the newer am`.
- Test inputs of `am` output come from `tests/fixtures/am/`, never hand-written; a synthetic edge case is labelled `synthetic:`.
- Docstrings and comments state the contract only, no narrative.
- The only skip of the live test is `am is not installed here` (when `shutil.which("am") is None`).
- `LIVE_EXTRA` list is unchanged.
- `bash tests/run.sh` green, including `tests/architecture`.

## Review Focus

1. `as_of_seq: null` in the runs data → fails on the type rule `live am runs data.as_of_seq: None` (not the "missing" message, not a crash). Pinned in Task 1 (`test_live_check_fails_on_a_null_as_of_seq`).
2. `head: true` (a bool, which Python treats as an int) → fails `live am watch hello.head: True`. Pinned in Task 2 (`test_live_check_rejects_a_bool_head`).
3. `am watch` prints a first line that is not JSON → fails naming `live am watch hello`, not a raw `JSONDecodeError` traceback. Pinned in Task 2 (`test_live_check_fails_naming_the_hello_when_it_is_not_json`).
4. A hello whose `event` is not `"watch"` → fails `live am watch hello: event <repr>`. Pinned in Task 2 (`test_live_check_fails_when_the_first_watch_line_is_not_the_hello`).
5. A schema 1 hello that has `head` plus unknown extra keys, and runs data with unknown extra keys → accepted. Pinned in Task 2 (`test_live_check_accepts_a_schema_1_hello_with_head_and_unknown_keys`).

---

## Spec

### 4.0.1 Contract test: the installed `am` has `as_of_seq` and `head` — design

Card: `f1b95771` (subtask of story `0cf1ca04`, 4.0 Contract). Parent design:
`docs/superpowers/specs/2026-10-06-am-snapshots-cursors-design.md` in the main checkout (untracked
there; cited below as **M4**). It changes one file: `tests/contract/test_am_fixtures.py`. No plugin
code, no fixture, no QML changes.

### Purpose

M4's precondition gate (M4 §"Order and sizing", line 254: "contract test that fails naming the
missing capability when `am` lacks `as_of_seq` / `head` (skips only when `am` is absent)"; M4
§"Testing", lines 214-215). Every later M4 subtask reads `as_of_seq` from snapshots and `head` from
the watch hello; this test makes an old `am` on the PATH fail the suite loudly instead of letting
those subtasks build against a capability that is not there.

### Inherited constraints

- `am` is called only as argv lists; nothing reads `am.db`, journals or the data-dir layout
  (M4 §"Non-goals", lines 58-59).
- The live check runs against a scratch data dir, never the user's real runs (M4 §"Dev safety",
  lines 187-189; card).
- A hello without `head` and a `runs` without `as_of_seq` mean "the plugin needs the newer am"
  (M4 §"Errors", line 198; M4 §"Design" hello rule, lines 92-94).
- The hello stays at schema 2 with additive `head`, `gseq`, `cursor_reset`, `store_id`
  (M4 §"Decisions", lines 273-275): the check keys on the presence of `head`, not on the schema
  number (M4 open question 5, lines 293-294).
- Test inputs of `am` output come from `tests/fixtures/am/`, never hand-written; a synthetic edge
  case is labelled `synthetic:` (card).
- Docstrings and comments state the contract only, no narrative (card).
- `bash tests/run.sh` green, including `tests/architecture` (card).

### Observed behavior of the installed `am` (2026-10-08)

Measured by the spec author with `HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` pointing into a fresh
temp dir (`~/.local/bin/am`):

1. `am runs --repo-dir <empty dir>` exits 0 and prints
   `{"data":{"as_of_seq":0,"runs":[],"store_id":null},"ok":true}` (also pinned in
   `tests/contract/test_am_shapes.py:77-82`).
2. `am watch --all --follow` prints, within ~0.2 s, one hello line
   `{"am":"0.1.0","cursor_reset":false,"event":"watch","head":0,"runs_dir":"<scratch>/data/agent-manager/runs","schema":2,"store_id":null}`
   and then blocks waiting for events until terminated (exit -15 on SIGTERM).
3. Neither call creates the scratch data dir.

So a fresh scratch store needs no seeded run for either capability check.

### Required behavior

### The live check

A module-level function `live_check(env, repo_dir)` performs the whole live check; the live test
calls it with a scratch environment. `env` is the full environment passed to every `am`
subprocess; `repo_dir` is the directory passed as `--repo-dir`.

In order:

1. **`am runs` has `as_of_seq`.** Runs `["am", "runs", "--repo-dir", repo_dir]` with `env`,
   timeout `AM_TIMEOUT`.
   - Non-zero exit → fails: `live am runs exited <code>: <stdout><stderr>`.
   - stdout not JSON, or no `data` object → fails naming `live am runs`.
   - `data` has no `as_of_seq` key → fails with exactly
     `live am runs data: no as_of_seq: the plugin needs the newer am`.
   - `as_of_seq` present but not a non-negative `int` (a `bool` is not an int here) → fails
     `live am runs data.as_of_seq: <repr>`.
2. **Rows and status, when there are rows.** For each row in `data.runs`: the existing
   `check_runs_rows("live am runs", rows, LIVE_EXTRA)` and `project` key-set checks; then
   `am status <newest id> --repo-dir repo_dir` with `env` and `check_status_data(...)`, exactly as
   today. A store with no rows checks nothing here and **does not skip**. (A fresh scratch store
   has no rows; seeded-run key sets are pinned by `test_am_shapes.py`.)
3. **The `am watch` hello has `head`.** Starts `["am", "watch", "--all", "--follow"]` with `env`
   (stdout piped, text mode), reads exactly one line bounded by `FOLLOW_TIMEOUT` (a hung or
   silent `am` fails with what it printed, never hangs the suite), then terminates the process
   (kill after a bounded wait) in a `finally`.
   - No line within the timeout → fails (the `read_lines` message:
     `am printed 0 of 1 lines within <t>s: []`).
   - First line not a JSON object → fails naming `live am watch hello`.
   - The object has `"event" != "watch"` → fails `live am watch hello: event <repr>`.
   - No `head` key → fails with exactly
     `live am watch hello: no head: the plugin needs the newer am`.
   - `head` present but not a non-negative `int` → fails `live am watch hello.head: <repr>`.

Failures use `pytest.fail` (or `assert` with the same message); messages follow the module's
`<source> <where>: ...` form. Every failure message for a missing capability contains the
capability's key name (`as_of_seq` or `head`) and `the plugin needs the newer am`.

### The live test

`test_installed_am_prints_the_fixture_key_sets(tmp_path)` (name kept):

- Skips with `am is not installed here` when `shutil.which("am") is None` — the **only** skip.
- Otherwise builds the scratch environment: a copy of `os.environ` with `HOME`,
  `XDG_DATA_HOME`, `XDG_STATE_HOME` set to `tmp_path/"home"`, `tmp_path/"data"`,
  `tmp_path/"state"` (the `am` fixture of `test_am_shapes.py:30-36`), `tmp_path/"home"` and
  `tmp_path/"repo"` created; then calls `live_check(env, tmp_path/"repo")`.
- It no longer resolves the main checkout and never passes the user's real environment's data
  dir: `git_main_checkout()` and `test_live_check_reads_the_main_checkout_not_a_worktree` are
  removed (git is no longer needed, so git's absence no longer skips).
- The skips "git could not name the main checkout", "am runs exited N" and "am has no runs" are
  gone: a non-zero `am runs` fails.

`am_json` takes the environment: `am_json(env, *args)` passes `env=env` to `subprocess.run`.

### Module docstring

The "Live check" paragraph (lines 9-15) is rewritten to state the new contract: the check runs
`am` under a scratch `HOME`/`XDG_DATA_HOME`/`XDG_STATE_HOME`, never the user's data dir; `am runs`
data must carry `as_of_seq` and the `am watch --all --follow` hello must carry `head`, else it
fails naming the missing key and "the plugin needs the newer am"; rows present are checked against
the capture key sets with the `LIVE_EXTRA` allowances (unchanged list); skipped only when `am` is
absent. Contract wording only.

### Tests (all pytest, `tests/contract/test_am_fixtures.py`)

The stub tests use a **stub `am`**: an executable `/bin/sh` script written into `tmp_path/"bin"`
(mode `0o755`), put first on the env's `PATH` (keeping the rest of `PATH` so `/bin/sh` and `sleep`
resolve). `am runs` makes it `cat` a JSON file; `am watch` makes it `cat` a hello file and then
`exec sleep 30` (the PID being terminated is then the sleeper itself, mirroring a real `am` that
blocks). On every call the stub writes `$XDG_DATA_HOME` to `tmp_path/"seen-xdg"` and appends its first argument (`runs` or `watch`) as a line to `tmp_path/"calls"`. Its JSON files
are derived from the fixtures with `json.dump`, never hand-written:

- runs output = `load("runs.json")` (its `data` has only `runs`: the missing case removes nothing; `pop("as_of_seq", None)` is harmless) with `data["as_of_seq"]` set to `0` for the present case
  (`synthetic: as_of_seq added`), and `data["runs"] = []` so step 2 has nothing to check;
- hello output = `load("watch-hello.json")["schema_2"]` (which has no `head`: the missing case removes nothing) with `head` set to `0` for the present case
  (`synthetic: head added`), `_`-prefixed keys dropped.

These are unit tests of the live check's failure paths; they are in the pytest contract tier
because the live check lives there and they run `live_check` as a subprocess consumer exactly as
the real check does. None needs the real `am`; none is skipped when `am` is absent.

| # | test | tier / why | proves |
|---|---|---|---|
| 1 | `test_live_check_fails_naming_as_of_seq_when_am_runs_lacks_it` | pytest contract: drives `live_check` against a stub `am` process | stub runs without `as_of_seq` → `pytest.fail.Exception` whose message is `live am runs data: no as_of_seq: the plugin needs the newer am`; `calls` holds no `watch` line (order) |
| 2 | `test_live_check_fails_naming_head_when_the_watch_hello_lacks_it` | same | stub runs with `as_of_seq` (synthetic), hello without `head` → fails with `live am watch hello: no head: the plugin needs the newer am`; the stub's sleeper is terminated (the test returns well under the stub's 30 s sleep) |
| 3 | `test_live_check_passes_when_am_has_as_of_seq_and_head` | same | stub with both (synthetic) → `live_check` returns without failing; guards against a check that fails everything |
| 4 | `test_live_check_runs_am_under_the_scratch_data_dir` | same | after the live test's env builder + `live_check` on the stub, `seen-xdg` holds `tmp_path/"data"` and not the caller's `XDG_DATA_HOME` / `~/.local/share` |
| 5 | `test_live_check_fails_when_am_runs_exits_non_zero` | same | stub `runs` exits 3 → fails with `live am runs exited 3` (not a skip) |
| 6 | `test_live_check_skips_when_am_is_not_on_path` (existing, kept) | pytest contract | `PATH=tmp_path` (no `am`) → the live test raises `pytest.skip.Exception` matching `am is not installed here`; adapt the call to pass `tmp_path` |
| 7 | `test_installed_am_prints_the_fixture_key_sets` (existing, rewritten) | pytest contract, live | the real installed `am` on a scratch store passes `live_check`; skips only when `am` is absent |

To let test 4 reuse the env builder, the scratch env is built by a helper
`scratch_env(tmp_path, path=None)` (returns `(env, repo_dir)`; `path` overrides `PATH`), used by
the live test and the stub tests.

The bounded one-line read reuses `read_lines` and `FOLLOW_TIMEOUT` from `test_am_shapes.py`
(`from test_am_shapes import FOLLOW_TIMEOUT, read_lines`; pytest's default prepend import mode puts
`tests/contract` on `sys.path`), so the deadline rule has one definition.

### Errors and edge cases the check must not mishandle

- `am` hangs before printing the hello → bounded failure, process terminated, no hang.
- `am watch` exits immediately (old `am` refusing `--all`) → fails with the lines it printed
  (none), not a JSON error trace.
- `as_of_seq: null` or `head: null` → fails on the type rule, naming the key path.
- Extra unknown keys in the runs data or hello → accepted (unknown keys are ignored, M4 line 80).
- A hello at schema 1 that has `head` → accepted (presence of `head` is the rule).

### Out of scope

- Regenerating or re-pinning `tests/fixtures/am/*.json`, `HELLO_KEYS`, `EVENT_KEYS`, adding
  `events.json` (sibling 4.0.2). The committed fixture keys are not changed here; the QML tier
  (`tests/helpers/amFixtures.js`, `tst_am_fixtures.qml`) reads them unchanged.
- `normalizeRun` and `tst_runs.qml` (4.0.3).
- `runs-watch.py` `SchemaMismatch` on a hello without `head` (4.1.1), `runs-snapshot.py` (4.1.2),
  `RunStore` (4.1.3, 4.1.4).
- `tests/contract/test_am_shapes.py` (unchanged; only imported from).
- Story 4.2 (spec retargets docs PR) and the 4.3 behaviour cards (Global Runs, timeline, alert
  cursor, start-run discovery).
- Any check of `store_id`, `cursor_reset` or `gseq` (not this card's capabilities).

### Verification

`bash tests/run.sh` green (pytest `tests -q`, including `tests/architecture`, then every
`tst_*.qml`). The live test (7) runs, not skips, on this machine because `am` is installed.

---

## File Structure

- Modify: `tests/contract/test_am_fixtures.py`
  - Module docstring (lines 1-16): "Live check" paragraph rewritten (Task 2).
  - Imports (lines 17-22): add `os`, `shlex`, `time` (Task 1) and `from test_am_shapes import FOLLOW_TIMEOUT, read_lines` (Task 2).
  - Lines 281-317 (`git_main_checkout`, `am_json`, `test_installed_am_prints_the_fixture_key_sets`): replaced by `am_json(env, *args)`, `scratch_env`, `require_count`, `live_check`, the rewritten live test, and the stub helpers + stub tests (Task 1), then `watch_hello` (Task 2).
  - Lines 346-356 (`test_live_check_skips_when_am_is_not_on_path`, `test_live_check_reads_the_main_checkout_not_a_worktree`): the first adapted to pass `tmp_path`, the second removed (Task 1).

---

### Task 1: Scratch-store live check with the `as_of_seq` capability

**Files:**
- Modify: `tests/contract/test_am_fixtures.py:17-22` (imports)
- Modify: `tests/contract/test_am_fixtures.py:281-317` (live check block)
- Modify: `tests/contract/test_am_fixtures.py:346-356` (skip test, main-checkout test)
- Test: `tests/contract/test_am_fixtures.py`

**Interfaces:**
- Consumes (existing in the same file): `load(name)`, `assert_keys(...)`, `check_runs_rows(source, rows, extra_allowed)`, `check_status_data(source, data, extra_allowed)`, `LIVE_EXTRA`, `PROJECT_KEYS`, `AM_TIMEOUT`.
- Produces:
  - `am_json(env: dict, *args: str) -> tuple[int, str, str]` — `(returncode, stdout, stderr)` of `["am", *args]` run with `env`.
  - `scratch_env(tmp_path: Path, path: str | None = None) -> tuple[dict, Path]` — `(env, repo_dir)`.
  - `require_count(where: str, obj: dict, key: str) -> None` — fails unless `obj[key]` is a non-negative non-bool `int`.
  - `live_check(env: dict, repo_dir: Path) -> None`.
  - Test helpers `stub_runs_data(**extra) -> dict`, `stub_hello(**extra) -> dict`, `stub_am(tmp_path, runs_data: dict, hello_line: str, runs_exit: int = 0) -> tuple[dict, Path]`.

- [ ] **Step 1: Write the failing tests and stub helpers**

In `tests/contract/test_am_fixtures.py`, replace the import block (lines 17-22):

```python
import json
import shutil
import subprocess
from pathlib import Path

import pytest
```

with:

```python
import json
import os
import shlex
import shutil
import subprocess
import time
from pathlib import Path

import pytest
```

Delete `test_live_check_reads_the_main_checkout_not_a_worktree` (lines 352-356):

```python
def test_live_check_reads_the_main_checkout_not_a_worktree():
    main = git_main_checkout()
    if main is None:
        pytest.skip("git could not name the main checkout")
    assert (main / ".git").is_dir(), f"{main}: not a main checkout (no .git directory)"
```

Replace `test_live_check_skips_when_am_is_not_on_path` (lines 346-349):

```python
def test_live_check_skips_when_am_is_not_on_path(monkeypatch, tmp_path):
    monkeypatch.setenv("PATH", str(tmp_path))
    with pytest.raises(pytest.skip.Exception, match="am is not installed here"):
        test_installed_am_prints_the_fixture_key_sets()
```

with:

```python
def test_live_check_skips_when_am_is_not_on_path(monkeypatch, tmp_path):
    monkeypatch.setenv("PATH", str(tmp_path))
    with pytest.raises(pytest.skip.Exception, match="am is not installed here"):
        test_installed_am_prints_the_fixture_key_sets(tmp_path)
```

Then append to the end of the file:

```python
def stub_runs_data(**extra):
    """runs.json's data with no rows and no as_of_seq, updated with `extra`."""
    data = load("runs.json")["data"]
    data.pop("as_of_seq", None)
    data["runs"] = []
    data.update(extra)
    return data


def stub_hello(**extra):
    """watch-hello.json's schema_2 hello without "_" keys and without head, updated with `extra`."""
    hello = {key: value for key, value in load("watch-hello.json")["schema_2"].items()
             if not key.startswith("_")}
    hello.pop("head", None)
    hello.update(extra)
    return hello


def stub_am(tmp_path, runs_data, hello_line, runs_exit=0):
    """(env, repo_dir) of scratch_env with an executable am first on PATH.

    The stub am: `am runs` prints {"ok": true, "data": runs_data} and exits runs_exit;
    `am watch` prints hello_line and then execs `sleep 30`. Every call writes
    $XDG_DATA_HOME to tmp_path/seen-xdg and appends its first argument to tmp_path/calls.
    """
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    runs_out = tmp_path / "runs-out.json"
    with open(runs_out, "w", encoding="utf-8") as fh:
        json.dump({"ok": True, "data": runs_data}, fh)
    hello_out = tmp_path / "hello-out.json"
    hello_out.write_text(hello_line + "\n", encoding="utf-8")
    seen, calls = shlex.quote(str(tmp_path / "seen-xdg")), shlex.quote(str(tmp_path / "calls"))
    script = (
        "#!/bin/sh\n"
        f'printf "%s\\n" "$XDG_DATA_HOME" > {seen}\n'
        f'printf "%s\\n" "$1" >> {calls}\n'
        'case "$1" in\n'
        f"  runs) cat {shlex.quote(str(runs_out))}; exit {runs_exit} ;;\n"
        f"  watch) cat {shlex.quote(str(hello_out))}; exec sleep 30 ;;\n"
        "esac\n"
        "exit 2\n"
    )
    am = bin_dir / "am"
    am.write_text(script, encoding="utf-8")
    am.chmod(0o755)
    return scratch_env(tmp_path, path=f"{bin_dir}{os.pathsep}{os.environ.get('PATH', '')}")


def test_live_check_fails_naming_as_of_seq_when_am_runs_lacks_it(tmp_path):
    env, repo_dir = stub_am(tmp_path, stub_runs_data(), json.dumps(stub_hello(head=0)))
    with pytest.raises(pytest.fail.Exception) as failure:
        live_check(env, repo_dir)
    assert str(failure.value) == "live am runs data: no as_of_seq: the plugin needs the newer am"
    assert (tmp_path / "calls").read_text(encoding="utf-8").splitlines() == ["runs"]


def test_live_check_fails_on_a_null_as_of_seq(tmp_path):
    # synthetic: as_of_seq added as null
    env, repo_dir = stub_am(tmp_path, stub_runs_data(as_of_seq=None), json.dumps(stub_hello(head=0)))
    with pytest.raises(pytest.fail.Exception) as failure:
        live_check(env, repo_dir)
    assert str(failure.value) == "live am runs data.as_of_seq: None"


def test_live_check_runs_am_under_the_scratch_data_dir(monkeypatch, tmp_path):
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "caller-data"))
    real_data_home = os.path.expanduser("~/.local/share")
    # synthetic: as_of_seq added; synthetic: head added
    env, repo_dir = stub_am(tmp_path, stub_runs_data(as_of_seq=0), json.dumps(stub_hello(head=0)))
    live_check(env, repo_dir)
    seen = (tmp_path / "seen-xdg").read_text(encoding="utf-8").strip()
    assert seen == str(tmp_path / "data"), seen
    assert seen not in (str(tmp_path / "caller-data"), real_data_home), seen


def test_live_check_fails_when_am_runs_exits_non_zero(tmp_path):
    # synthetic: as_of_seq added; synthetic: head added
    env, repo_dir = stub_am(tmp_path, stub_runs_data(as_of_seq=0), json.dumps(stub_hello(head=0)),
                            runs_exit=3)
    with pytest.raises(pytest.fail.Exception, match=r"^live am runs exited 3: "):
        live_check(env, repo_dir)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_fixtures.py -q -k "live_check"`
Expected: FAIL — `test_live_check_fails_naming_as_of_seq_when_am_runs_lacks_it`, `test_live_check_fails_on_a_null_as_of_seq`, `test_live_check_runs_am_under_the_scratch_data_dir`, `test_live_check_fails_when_am_runs_exits_non_zero` fail with `NameError: name 'scratch_env' is not defined`; `test_live_check_skips_when_am_is_not_on_path` fails with `TypeError: test_installed_am_prints_the_fixture_key_sets() takes 0 positional arguments but 1 was given`.

- [ ] **Step 3: Write the implementation**

Replace lines 281-317 of `tests/contract/test_am_fixtures.py` — this exact block:

```python
def git_main_checkout():
    """The main checkout's root, or None when git is absent or fails here."""
    try:
        proc = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                              cwd=HERE, capture_output=True, text=True, timeout=AM_TIMEOUT)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    return Path(proc.stdout.strip()).parent


def am_json(*args):
    # A hung am fails the test (TimeoutExpired) instead of hanging the suite.
    proc = subprocess.run(["am", *args], capture_output=True, text=True, timeout=AM_TIMEOUT)
    return proc.returncode, proc.stdout, proc.stderr


def test_installed_am_prints_the_fixture_key_sets():
    if shutil.which("am") is None:
        pytest.skip("am is not installed here")
    main = git_main_checkout()
    if main is None:
        pytest.skip("git could not name the main checkout")
    code, out, err = am_json("runs", "--repo-dir", str(main))
    if code != 0:
        pytest.skip(f"am runs --repo-dir {main} exited {code}: {err.strip()}")
    rows = json.loads(out).get("data", {}).get("runs") or []
    if not rows:
        pytest.skip(f"am has no runs for {main}")
    check_runs_rows("live am runs", rows, LIVE_EXTRA)
    for i, row in enumerate(rows):
        assert_keys("live am runs", f"runs[{i}].project", row["project"], PROJECT_KEYS)
    newest = max(rows, key=lambda row: row["started_at"])
    code, out, err = am_json("status", newest["id"], "--repo-dir", str(main))
    assert code == 0, f"am status {newest['id']} exited {code}: {out}{err}"
    check_status_data(f"live am status {newest['id']}", json.loads(out)["data"], LIVE_EXTRA)
```

with:

```python
def am_json(env, *args):
    # A hung am fails the test (TimeoutExpired) instead of hanging the suite.
    proc = subprocess.run(["am", *args], env=env, capture_output=True, text=True, timeout=AM_TIMEOUT)
    return proc.returncode, proc.stdout, proc.stderr


def scratch_env(tmp_path, path=None):
    """(env, repo_dir): os.environ with HOME, XDG_DATA_HOME and XDG_STATE_HOME under tmp_path
    and PATH replaced by `path` when given; tmp_path/home and repo_dir exist."""
    env = dict(os.environ)
    env.update({"HOME": str(tmp_path / "home"), "XDG_DATA_HOME": str(tmp_path / "data"),
                "XDG_STATE_HOME": str(tmp_path / "state")})
    if path is not None:
        env["PATH"] = path
    (tmp_path / "home").mkdir(exist_ok=True)
    repo_dir = tmp_path / "repo"
    repo_dir.mkdir(exist_ok=True)
    return env, repo_dir


def require_count(where, obj, key):
    """obj[key] is a non-negative int (a bool is not); a missing key means the plugin needs the newer am."""
    if key not in obj:
        pytest.fail(f"{where}: no {key}: the plugin needs the newer am")
    value = obj[key]
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        pytest.fail(f"{where}.{key}: {value!r}")


def live_check(env, repo_dir):
    """am run with `env` prints am runs data carrying as_of_seq; rows present match the capture
    key sets with the LIVE_EXTRA allowances, and so does am status of the newest row."""
    code, out, err = am_json(env, "runs", "--repo-dir", str(repo_dir))
    if code != 0:
        pytest.fail(f"live am runs exited {code}: {out}{err}")
    try:
        data = json.loads(out).get("data")
    except (json.JSONDecodeError, AttributeError):
        data = None
    if not isinstance(data, dict):
        pytest.fail(f"live am runs: no data object in {out!r}")
    require_count("live am runs data", data, "as_of_seq")
    rows = data.get("runs") or []
    check_runs_rows("live am runs", rows, LIVE_EXTRA)
    for i, row in enumerate(rows):
        assert_keys("live am runs", f"runs[{i}].project", row["project"], PROJECT_KEYS)
    if rows:
        newest = max(rows, key=lambda row: row["started_at"])
        code, out, err = am_json(env, "status", newest["id"], "--repo-dir", str(repo_dir))
        assert code == 0, f"am status {newest['id']} exited {code}: {out}{err}"
        check_status_data(f"live am status {newest['id']}", json.loads(out)["data"], LIVE_EXTRA)


def test_installed_am_prints_the_fixture_key_sets(tmp_path):
    if shutil.which("am") is None:
        pytest.skip("am is not installed here")
    live_check(*scratch_env(tmp_path))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_fixtures.py -q -rs`
Expected: all PASS, no `SKIPPED` line in the `-rs` summary (on this machine `am` is installed, so `test_installed_am_prints_the_fixture_key_sets` runs). Also confirm `grep -n "git_main_checkout\|HERE" tests/contract/test_am_fixtures.py` prints only the `HERE = ...` and `FIXTURES = HERE.parent ...` lines (no `git_main_checkout`).

- [ ] **Step 5: Commit**

```bash
git add tests/contract/test_am_fixtures.py
git commit -m "test(contract): run the live am check on a scratch store and require as_of_seq"
```

---

### Task 2: The `am watch` hello must carry `head`; docstring

**Files:**
- Modify: `tests/contract/test_am_fixtures.py:1-16` (module docstring)
- Modify: `tests/contract/test_am_fixtures.py` imports (add `from test_am_shapes import ...`)
- Modify: `tests/contract/test_am_fixtures.py` `live_check` (from Task 1) — add the watch step; add `watch_hello`
- Test: `tests/contract/test_am_fixtures.py`

**Interfaces:**
- Consumes: from Task 1 — `require_count(where, obj, key)`, `live_check(env, repo_dir)`, `scratch_env(tmp_path, path=None)`, `stub_runs_data(**extra)`, `stub_hello(**extra)`, `stub_am(tmp_path, runs_data, hello_line, runs_exit=0) -> (env, repo_dir)`. From `tests/contract/test_am_shapes.py` (unchanged) — `FOLLOW_TIMEOUT = 10` and `read_lines(stream, count, timeout=FOLLOW_TIMEOUT) -> list` (parses each line with `json.loads`, `pytest.fail("am printed N of M lines within Ts: [...]")` on the deadline).
- Produces: `watch_hello(env: dict) -> dict` — the first line of `am watch --all --follow` under `env`, the process terminated afterwards.

- [ ] **Step 1: Write the failing tests**

Append to the end of `tests/contract/test_am_fixtures.py`:

```python
def test_live_check_fails_naming_head_when_the_watch_hello_lacks_it(tmp_path):
    # synthetic: as_of_seq added
    env, repo_dir = stub_am(tmp_path, stub_runs_data(as_of_seq=0), json.dumps(stub_hello()))
    started = time.monotonic()
    with pytest.raises(pytest.fail.Exception) as failure:
        live_check(env, repo_dir)
    assert str(failure.value) == "live am watch hello: no head: the plugin needs the newer am"
    # The stub sleeps 30 s after the hello: returning sooner means it was terminated.
    assert time.monotonic() - started < 20
    assert (tmp_path / "calls").read_text(encoding="utf-8").splitlines() == ["runs", "watch"]


def test_live_check_passes_when_am_has_as_of_seq_and_head(tmp_path):
    # synthetic: as_of_seq added; synthetic: head added
    env, repo_dir = stub_am(tmp_path, stub_runs_data(as_of_seq=0), json.dumps(stub_hello(head=0)))
    live_check(env, repo_dir)
    assert (tmp_path / "calls").read_text(encoding="utf-8").splitlines() == ["runs", "watch"]


def test_live_check_rejects_a_bool_head(tmp_path):
    # synthetic: as_of_seq added; synthetic: head added as a bool
    env, repo_dir = stub_am(tmp_path, stub_runs_data(as_of_seq=0), json.dumps(stub_hello(head=True)))
    with pytest.raises(pytest.fail.Exception) as failure:
        live_check(env, repo_dir)
    assert str(failure.value) == "live am watch hello.head: True"


def test_live_check_fails_naming_the_hello_when_it_is_not_json(tmp_path):
    # synthetic: as_of_seq added; synthetic: a first watch line that is not JSON
    env, repo_dir = stub_am(tmp_path, stub_runs_data(as_of_seq=0), "synthetic: not json")
    with pytest.raises(pytest.fail.Exception, match=r"^live am watch hello: not JSON"):
        live_check(env, repo_dir)


def test_live_check_fails_when_the_first_watch_line_is_not_the_hello(tmp_path):
    # synthetic: as_of_seq added; synthetic: head added, event changed
    hello = stub_hello(head=0, event="run_upsert")
    env, repo_dir = stub_am(tmp_path, stub_runs_data(as_of_seq=0), json.dumps(hello))
    with pytest.raises(pytest.fail.Exception) as failure:
        live_check(env, repo_dir)
    assert str(failure.value) == "live am watch hello: event 'run_upsert'"


def test_live_check_accepts_a_schema_1_hello_with_head_and_unknown_keys(tmp_path):
    # synthetic: as_of_seq and an unknown key added; synthetic: head and an unknown key added, schema 1
    runs_data = stub_runs_data(as_of_seq=7, future_key=1)
    hello = stub_hello(head=7, schema=1, future_key=1)
    env, repo_dir = stub_am(tmp_path, runs_data, json.dumps(hello))
    live_check(env, repo_dir)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_fixtures.py -q -k "head or hello or passes_when"`
Expected: FAIL — `test_live_check_fails_naming_head_when_the_watch_hello_lacks_it`, `test_live_check_rejects_a_bool_head`, `test_live_check_fails_naming_the_hello_when_it_is_not_json`, `test_live_check_fails_when_the_first_watch_line_is_not_the_hello` fail with `Failed: DID NOT RAISE`; `test_live_check_passes_when_am_has_as_of_seq_and_head` fails because `calls` is `['runs']`, not `['runs', 'watch']`. (`test_live_check_accepts_a_schema_1_hello_with_head_and_unknown_keys` passes already; it guards Step 3.)

- [ ] **Step 3: Write the implementation**

In the import block, after `import pytest`, add a blank line and the import so it reads:

```python
import pytest

from test_am_shapes import FOLLOW_TIMEOUT, read_lines
```

Insert `watch_hello` directly above `def live_check(env, repo_dir):`:

```python
def watch_hello(env):
    """The first line `am watch --all --follow` prints with `env`, as an object; am is
    terminated afterwards. A silent or hung am fails within FOLLOW_TIMEOUT."""
    with subprocess.Popen(["am", "watch", "--all", "--follow"], env=env,
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True) as proc:
        try:
            try:
                (hello,) = read_lines(proc.stdout, 1, FOLLOW_TIMEOUT)
            except json.JSONDecodeError as err:
                pytest.fail(f"live am watch hello: not JSON: {err}")
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
    if not isinstance(hello, dict):
        pytest.fail(f"live am watch hello: expected an object, got {hello!r}")
    return hello
```

Replace `live_check` (from Task 1) — this exact function:

```python
def live_check(env, repo_dir):
    """am run with `env` prints am runs data carrying as_of_seq; rows present match the capture
    key sets with the LIVE_EXTRA allowances, and so does am status of the newest row."""
    code, out, err = am_json(env, "runs", "--repo-dir", str(repo_dir))
    if code != 0:
        pytest.fail(f"live am runs exited {code}: {out}{err}")
    try:
        data = json.loads(out).get("data")
    except (json.JSONDecodeError, AttributeError):
        data = None
    if not isinstance(data, dict):
        pytest.fail(f"live am runs: no data object in {out!r}")
    require_count("live am runs data", data, "as_of_seq")
    rows = data.get("runs") or []
    check_runs_rows("live am runs", rows, LIVE_EXTRA)
    for i, row in enumerate(rows):
        assert_keys("live am runs", f"runs[{i}].project", row["project"], PROJECT_KEYS)
    if rows:
        newest = max(rows, key=lambda row: row["started_at"])
        code, out, err = am_json(env, "status", newest["id"], "--repo-dir", str(repo_dir))
        assert code == 0, f"am status {newest['id']} exited {code}: {out}{err}"
        check_status_data(f"live am status {newest['id']}", json.loads(out)["data"], LIVE_EXTRA)
```

with:

```python
def live_check(env, repo_dir):
    """am run with `env` prints am runs data carrying as_of_seq and an am watch hello carrying
    head; rows present match the capture key sets with the LIVE_EXTRA allowances, and so does
    am status of the newest row."""
    code, out, err = am_json(env, "runs", "--repo-dir", str(repo_dir))
    if code != 0:
        pytest.fail(f"live am runs exited {code}: {out}{err}")
    try:
        data = json.loads(out).get("data")
    except (json.JSONDecodeError, AttributeError):
        data = None
    if not isinstance(data, dict):
        pytest.fail(f"live am runs: no data object in {out!r}")
    require_count("live am runs data", data, "as_of_seq")
    rows = data.get("runs") or []
    check_runs_rows("live am runs", rows, LIVE_EXTRA)
    for i, row in enumerate(rows):
        assert_keys("live am runs", f"runs[{i}].project", row["project"], PROJECT_KEYS)
    if rows:
        newest = max(rows, key=lambda row: row["started_at"])
        code, out, err = am_json(env, "status", newest["id"], "--repo-dir", str(repo_dir))
        assert code == 0, f"am status {newest['id']} exited {code}: {out}{err}"
        check_status_data(f"live am status {newest['id']}", json.loads(out)["data"], LIVE_EXTRA)
    hello = watch_hello(env)
    if hello.get("event") != "watch":
        pytest.fail(f"live am watch hello: event {hello.get('event')!r}")
    require_count("live am watch hello", hello, "head")
```

Replace the module docstring's "Live check" paragraph (lines 9-15):

```
Live check: in the main checkout (the parent of git's common dir), am runs and
am status of the newest run must print the same key sets, with the keys the
captures predate allowed as extras: "story_id" and "project" (exactly "id" and
"repo_dir") on a runs row, "story_id" on the status run, and "as_of_seq",
"store_id" and "warnings" on the status data. Read-only:
only --repo-dir is passed and the user's real runs are read, never written.
Skipped when am or git is absent or the checkout has no runs.
```

with:

```
Live check: am runs with HOME, XDG_DATA_HOME and XDG_STATE_HOME under a scratch
dir, never the user's data dir. am runs data must carry "as_of_seq" and the
first line of am watch --all --follow (the hello) must carry "head", each a
non-negative int; a missing one fails naming the key and "the plugin needs the
newer am". Rows present, and am status of the newest, must print the capture
key sets, with the keys the captures predate allowed as extras: "story_id" and
"project" (exactly "id" and "repo_dir") on a runs row, "story_id" on the status
run, and "as_of_seq", "store_id" and "warnings" on the status data. Skipped only
when am is absent.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_fixtures.py -q -rs`
Expected: all PASS, no `SKIPPED` line; the whole file finishes in well under 30 s (no stub sleeper is waited out).

Then the full gate:

Run: `bash tests/run.sh`
Expected: pytest `tests -q` all pass (including `tests/architecture` and `tests/contract/test_am_shapes.py`), and every `tst_*.qml` prints a `Totals` line with `0 failed`; exit status 0.

- [ ] **Step 5: Commit**

```bash
git add tests/contract/test_am_fixtures.py
git commit -m "test(contract): fail the live am check when the watch hello lacks head"
```

---

## Self-Review (against the spec)

- Live check step 1 (`as_of_seq`, exit code, non-JSON/no data, type rule incl. bool): Task 1 `live_check` + `require_count`; tests 1, 5, null-as_of_seq. Bool rule shared by `require_count`, pinned via `head=True` in Task 2.
- Step 2 (rows/status unchanged, empty store does not skip): Task 1 `live_check`; live test on scratch store.
- Step 3 (watch hello, bounded read via `read_lines`/`FOLLOW_TIMEOUT`, terminate/kill in `finally`, event, `head`, type): Task 2 `watch_hello` + `live_check`; tests 2, 3, bool head, non-JSON, event.
- Live test: only skip, scratch env via `scratch_env`, `git_main_checkout` and main-checkout test removed: Task 1.
- `am_json(env, *args)`: Task 1.
- Docstring: Task 2.
- Stub design (sh script, `0o755`, PATH prefix, `seen-xdg`, `calls`, `exec sleep 30`, fixture-derived JSON with `synthetic:` labels): Task 1 `stub_am`/`stub_runs_data`/`stub_hello`.
- Tests table 1-7: 1, 4, 5, 6, 7 in Task 1; 2, 3 in Task 2.
- Edge cases: hang → `read_lines` deadline; null → type rule (Task 1 test); extra keys and schema 1 with head → Task 2 test. Immediate-exit `am watch` uses the same `read_lines` deadline path (10 s; not given its own test to keep the suite fast).
- Out of scope respected: fixtures, `HELLO_KEYS`, `test_am_shapes.py` untouched.
<!-- task-pipeline: validated -->
