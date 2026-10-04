<!-- task-pipeline: validated -->
# 2.4 Contract test pinning am's JSON shapes (card b8067b26)

Parent story: 92b4d150 "Run backend helpers" (milestone 4bf4fb2f). Blocked by 2.3 (4e4ae17d), which is done. Narrows `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md`, Testing section: "tests/contract/test_am_shapes.py: runs the installed am against a throwaway XDG_DATA_HOME and pins the runs, status and watch shapes; skipped when am is absent".

## Scope

One new file: `tests/contract/test_am_shapes.py`. There is no production code. It checks that the installed `am` binary still prints the JSON shapes the `core/backend/runs/*` helpers parse. It mirrors `tests/contract/test_brd_shapes.py` in structure and style.

Out of scope:
- Anything under `core/backend/runs/` or `tests/core/backend/runs/`. Those belong to siblings 2.1 to 2.3, which use stub-am tests.
- `am logs`, `pause`, `resume`, `cancel`.
- am's SQLite. The plugin uses only documented am commands and journal schema 1.
- Edits to `docs/architecture.md`. One optional change is allowed: the "Tests" bullet that documents `python3 -m pytest tests/contract -q` may also mention am.

## Hermetic setup

- Module docstring: the test runs the installed am against a throwaway HOME, XDG_DATA_HOME and XDG_STATE_HOME under `tmp_path`, so the user's real runs are never read or written. The module is skipped when am is absent.
- `pytestmark = pytest.mark.skipif(shutil.which("am") is None, reason="am is not installed here")`.
- Fixture: start from `dict(os.environ)`, then set `HOME=tmp/home` (created with mkdir), `XDG_DATA_HOME=tmp/data` and `XDG_STATE_HOME=tmp/state`. It also provides a repo dir `R` under `tmp_path` and a `run(*args)` helper that calls `subprocess.run(["am", *args], env=env, capture_output=True, text=True)`. The helper returns the completed process, and each test asserts the exit code itself, because the error-path test expects rc 3.
- Journal fixture writer: writes `$XDG_DATA_HOME/agent-manager/runs/<run_id>/journal.jsonl` with one JSON object per line. Each line has the same shape as `store.JournalLine` dumps in `/home/mtts/Code/agent-manager/tests/test_cli.py` (`_write_watch_journal`, around lines 7941-7962). The test writes the JSON by hand and does not import am. Example line: `{"seq":1,"ts":"2026-10-02T12:00:00+00:00","run_id":"run-a","event":"phase_upsert","card":"c1","phase":"implement","attempt":1,"payload":{"status":"started"}}`.
- The test file must not define `emit`, `inside`, `write_atomic`, `split_frontmatter` or `frontmatter_of`. This is the architecture duplicate rule. `tests/architecture` must pass unchanged.

## Observable behavior pinned

1. `am runs --repo-dir R` with no data dir: rc 0. The parsed stdout equals `{"ok": true, "data": {"runs": []}}` exactly.
2. `am status nope --repo-dir R`: rc 3. The parsed stdout has `ok is False`, `error.type == "UnknownRunError"`, and a non-empty string `error.message`. The message text is not pinned because it embeds the repo path.
3. `am watch --all` against a hand-written journal of one or more lines: rc 0. stdout is `{"ok": true, "data": {"events": [...]}}`. Each event has exactly the key set `{attempt, card, event, payload, phase, run_id, seq, story, ts}`. `story` is `null` when absent from the source line. `ts` ends in `Z` (normalised from `+00:00`). `seq`, `run_id`, `event`, `card`, `phase`, `attempt` and `payload` round-trip the written values.
4. `am watch --all --follow` against the same journal is started with `Popen(stdout=PIPE, text=True)`.
   - Line 1 is the hello line. It parses to an object with `event == "watch"`, `schema == 1`, `am` a non-empty string (the version) and `runs_dir` a string.
   - Lines 2 onward are journal lines with the same key set and normalisation as in test 3.
   - The test reads only the number of lines it expects. Each read is bounded by a timeout (for example a reader thread or `select` with a deadline), so a silent am fails the test instead of hanging it.
   - The process is always terminated, and killed if it does not exit, in a `finally` block.

The plugin ignores unknown journal events and keys. The tests check that the keys above are present and correct; they do not reject extra keys, except in test 3's exact key-set check, which pins today's schema 1 line.

## Error paths

- am missing: the whole module is skipped.
- An am refusal in test 2 must be exit 3 with the error envelope. Any other rc fails the test, and the failure message includes stdout and stderr.
- A hung `--follow` fails on the timeout instead of blocking the suite.

## Test list

All tests belong in the contract tier, `tests/contract/test_am_shapes.py`. Per `docs/architecture.md` "Tests" and the run-monitor spec, contract tests own "the installed external CLI still speaks the JSON shape our parsers read". They use the real binary, a throwaway data dir, and skip when the binary is absent. None of them belong in `tests/core/backend/runs/`, which holds stub-am helper tests owned by the siblings.

- `test_runs_with_no_data_dir_is_an_empty_list` (contract)
- `test_status_of_an_unknown_run_refuses_with_exit_3_and_unknown_run_error` (contract)
- `test_watch_all_returns_the_events_envelope_with_journal_line_keys` (contract)
- `test_watch_all_follow_prints_a_hello_line_then_journal_lines` (contract)

## Note

Siblings 2.1 to 2.3 are marked done in brd. Their `core/backend/runs/` and `tests/core/backend/runs/` files exist in this worktree but not in the main checkout `/home/mtts/Code/omarchy-project-manager`, which has not merged them. This card does not depend on them because it calls `am` directly, and it must not edit them.

---

# am JSON-shape Contract Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `tests/contract/test_am_shapes.py`, which runs the installed `am` in a throwaway HOME/XDG environment and pins the JSON shapes of `am runs`, `am status` (refusal), `am watch --all` and `am watch --all --follow` that `core/backend/runs/*` parses.

**Architecture:** A single pytest module in the contract tier, built like `tests/contract/test_brd_shapes.py`: module-level `skipif` on `shutil.which("am")`, one `am` fixture that builds a hermetic env and returns a `SimpleNamespace(run, env, repo, data)`, hand-written schema 1 journals under `$XDG_DATA_HOME/agent-manager/runs/<run_id>/journal.jsonl`, and a thread-plus-queue reader with a deadline for the never-ending `--follow` stream. There is no production code: the "implementation" for each RED test is the test-side helper it needs (fixture, journal writer, bounded reader), and `am` itself is the system under contract.

**Tech Stack:** Python 3 stdlib (`json`, `os`, `shutil`, `subprocess`, `queue`, `threading`, `time`, `types.SimpleNamespace`), pytest, the installed `am` 0.1.0 at `/home/mtts/.local/bin/am`.

**Spec:** `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-2-4-contract-test-b8067b26/docs/superpowers/specs/task-2-4-contract-test-b8067b26-design.md` (prepended verbatim above).

**Working directory for every command:** `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-2-4-contract-test-b8067b26` (branch `mon/task-2-4-contract-test-b8067b26`). Do not assume any other subtask's code; this plan touches only `tests/contract/test_am_shapes.py` and, optionally, one bullet of `docs/architecture.md`.

**pytest invocation:** `python3 -m pytest ...`. If `python3 -c 'import pytest'` fails (uv-managed interpreter), use `uv run --with pytest python3 -m pytest ...` instead, exactly as `tests/run.sh` does.

## Global Constraints

- The only new file is `tests/contract/test_am_shapes.py`; nothing under `core/backend/runs/` or `tests/core/backend/runs/` is created or edited.
- Module skip: `pytestmark = pytest.mark.skipif(shutil.which("am") is None, reason="am is not installed here")`.
- Env: `dict(os.environ)` with `HOME=<tmp>/home` (mkdir'd), `XDG_DATA_HOME=<tmp>/data`, `XDG_STATE_HOME=<tmp>/state`. Never touch the real HOME or XDG dirs.
- Journal path: `$XDG_DATA_HOME/agent-manager/runs/<run_id>/journal.jsonl`, one JSON object per line, the `store.JournalLine` shape; am is never imported.
- Journal-line key set: `{attempt, card, event, payload, phase, run_id, seq, story, ts}`; `story` is null when absent; `ts` normalised from `+00:00` to `Z`.
- Hello line: `event == "watch"`, `schema == 1`, `am` non-empty string, `runs_dir` string.
- Refusal: exit 3 with `{"ok": false, "error": {"type": "UnknownRunError", "message": <non-empty str>}}`; the message text is not pinned.
- Do not define functions named `emit`, `inside`, `write_atomic`, `split_frontmatter` or `frontmatter_of` (`tests/architecture/test_layers.py` `DUPLICATED_PY`).
- No `am logs`, `pause`, `resume`, `cancel`; never read am's SQLite.
- Final verification: `bash ./tests/run.sh` passes.

## Review Focus

- A hung one-shot `am` command (e.g. `am runs` blocking on a lock) should fail the test, not hang the suite: `run()` passes `timeout=30` to `subprocess.run` (Task 1).
- `am watch --all --follow` that goes silent or exits early should fail with a message saying how many lines arrived, not block: the bounded `read_lines` reader (Task 3).
- The stream must read the throwaway data dir and not the user's real one: the hello line's `runs_dir` is pinned to `<tmp>/data/agent-manager/runs` (Task 3), and test 1 asserts the data dir does not exist before `am runs` runs (Task 1).
- A journal line that does carry a `story` must round-trip it, not only the null case: the fixture journal has a line with `"story": "s1"` (Task 2).
- More than one run under `--all` must come back ordered by `(run_id, seq)`: the fixture journal has two runs, `run-a` (two lines) and `run-b` (one line) (Tasks 2 and 3).

---

### Task 1: Hermetic `am` fixture, `am runs` empty shape, `am status` refusal shape

**Files:**
- Create: `tests/contract/test_am_shapes.py`
- Test: `tests/contract/test_am_shapes.py` (contract tier, beside `tests/contract/test_brd_shapes.py`)

**Interfaces:**
- Consumes: nothing.
- Produces: pytest fixture `am(tmp_path) -> SimpleNamespace` with attributes `run(*args: str) -> subprocess.CompletedProcess[str]`, `env: dict[str, str]`, `repo: str` (an existing dir `<tmp>/repo`), `data: pathlib.Path` (`<tmp>/data`, the `XDG_DATA_HOME`, not created). Module constant `AM_TIMEOUT = 30`.

- [ ] **Step 1: Write the failing tests (no fixture yet)**

Create `tests/contract/test_am_shapes.py` with exactly this content:

```python
"""The installed am still speaks the JSON shapes core/backend/runs/* parse.

Hermetic: am runs with its own HOME, XDG_DATA_HOME and XDG_STATE_HOME under
tmp_path (am keeps runs under $XDG_DATA_HOME/agent-manager/runs), so the
user's real runs are never read or written. Journals are hand-written in the
shape am's store.JournalLine dumps (journal schema 1); am is never imported and
its SQLite is never read. Skipped when am is absent.
"""
import json
import os
import shutil
import subprocess
from types import SimpleNamespace

import pytest

pytestmark = pytest.mark.skipif(shutil.which("am") is None, reason="am is not installed here")


def test_runs_with_no_data_dir_is_an_empty_list(am):
    assert not am.data.exists(), "precondition: no am data dir yet"
    proc = am.run("runs", "--repo-dir", am.repo)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert json.loads(proc.stdout) == {"ok": True, "data": {"runs": []}}


def test_status_of_an_unknown_run_refuses_with_exit_3_and_unknown_run_error(am):
    proc = am.run("status", "nope", "--repo-dir", am.repo)
    assert proc.returncode == 3, proc.stdout + proc.stderr
    payload = json.loads(proc.stdout)
    assert payload["ok"] is False, payload
    assert payload["error"]["type"] == "UnknownRunError", payload
    # The message embeds the repo path, so only its presence is pinned.
    message = payload["error"]["message"]
    assert isinstance(message, str) and message, payload
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m pytest tests/contract/test_am_shapes.py -v`
Expected: 2 ERROR, each with `fixture 'am' not found`.

- [ ] **Step 3: Add the hermetic fixture**

In `tests/contract/test_am_shapes.py`, insert this block directly after the `pytestmark = ...` line (before `def test_runs_with_no_data_dir_is_an_empty_list`), separated by two blank lines on each side:

```python
AM_TIMEOUT = 30


@pytest.fixture
def am(tmp_path):
    env = dict(os.environ)
    env.update({"HOME": str(tmp_path / "home"), "XDG_DATA_HOME": str(tmp_path / "data"),
                "XDG_STATE_HOME": str(tmp_path / "state")})
    (tmp_path / "home").mkdir()
    repo = tmp_path / "repo"
    repo.mkdir()

    def run(*args):
        # A hung am fails the test (TimeoutExpired) instead of hanging the suite.
        return subprocess.run(["am", *args], env=env, capture_output=True, text=True,
                              timeout=AM_TIMEOUT)

    return SimpleNamespace(run=run, env=env, repo=str(repo), data=tmp_path / "data")
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m pytest tests/contract/test_am_shapes.py -v`
Expected: `2 passed`.

- [ ] **Step 5: Verify the module skips when am is absent**

Run: `PATH=/usr/bin:/bin python3 -m pytest tests/contract/test_am_shapes.py -q -rs`
Expected: `2 skipped` with reason `am is not installed here`. (If `/usr/bin/python3` has no pytest, run `PATH=/usr/bin:/bin "$(command -v uv)" run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -rs` instead; same expectation.)

- [ ] **Step 6: Verify the architecture rules still pass**

Run: `python3 -m pytest tests/architecture -q`
Expected: all pass (no new failures).

- [ ] **Step 7: Commit**

```bash
git add tests/contract/test_am_shapes.py
git commit -m "test(contract): pin am runs and am status refusal JSON shapes"
```

---

### Task 2: `am watch --all` events envelope against hand-written journals

**Files:**
- Modify: `tests/contract/test_am_shapes.py` (append a test; add module-level constants and helpers after the `am` fixture)
- Test: `tests/contract/test_am_shapes.py`

**Interfaces:**
- Consumes: fixture `am` from Task 1 (`am.run`, `am.data`).
- Produces: `EVENT_KEYS: set[str]`; `JOURNALS: dict[str, list[dict]]` (run id to its journal lines); `write_journals(data_dir: pathlib.Path) -> None`; `expected_events() -> list[dict]` (lines as am re-emits them, ordered by `(run_id, seq)`). Task 3 uses all four.

- [ ] **Step 1: Write the failing test**

Append to the end of `tests/contract/test_am_shapes.py`:

```python


def test_watch_all_returns_the_events_envelope_with_journal_line_keys(am):
    write_journals(am.data)
    proc = am.run("watch", "--all")
    assert proc.returncode == 0, proc.stdout + proc.stderr
    payload = json.loads(proc.stdout)
    events = payload["data"]["events"]
    for event in events:
        # Exact key set: pins today's journal schema 1 line.
        assert set(event) == EVENT_KEYS, event
        assert event["ts"].endswith("Z"), event
    assert payload == {"ok": True, "data": {"events": expected_events()}}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m pytest tests/contract/test_am_shapes.py::test_watch_all_returns_the_events_envelope_with_journal_line_keys -v`
Expected: FAIL with `NameError: name 'write_journals' is not defined`.

- [ ] **Step 3: Add the journal constants and helpers**

In `tests/contract/test_am_shapes.py`, insert this block directly after the `am` fixture (after its `return SimpleNamespace(...)` line, before `def test_runs_with_no_data_dir_is_an_empty_list`), separated by two blank lines on each side:

```python
EVENT_KEYS = {"attempt", "card", "event", "payload", "phase", "run_id", "seq", "story", "ts"}

# One JSON object per journal line, the shape am's store.JournalLine dumps
# (journal schema 1; see _write_watch_journal in agent-manager's
# tests/test_cli.py). Two runs, listed out of order on purpose: am orders
# --all output by (run_id, seq). Only run-a seq 2 carries a story.
JOURNALS = {
    "run-b": [
        {"seq": 1, "ts": "2026-10-02T12:01:00+00:00", "run_id": "run-b", "event": "phase_upsert",
         "card": "c2", "phase": "review", "attempt": 2, "payload": {"status": "started", "n": 1}},
    ],
    "run-a": [
        {"seq": 1, "ts": "2026-10-02T12:00:00+00:00", "run_id": "run-a", "event": "phase_upsert",
         "card": "c1", "phase": "implement", "attempt": 1, "payload": {"status": "started"}},
        {"seq": 2, "ts": "2026-10-02T12:00:05+00:00", "run_id": "run-a", "event": "phase_upsert",
         "story": "s1", "card": "c1", "phase": "implement", "attempt": 1,
         "payload": {"status": "done", "n": 2}},
    ],
}


def write_journals(data_dir):
    """Write every JOURNALS run to $XDG_DATA_HOME/agent-manager/runs/<id>/journal.jsonl."""
    for run_id, lines in JOURNALS.items():
        run_dir = data_dir / "agent-manager" / "runs" / run_id
        run_dir.mkdir(parents=True, exist_ok=True)
        text = "".join(json.dumps(line, sort_keys=True) + "\n" for line in lines)
        (run_dir / "journal.jsonl").write_text(text, encoding="utf-8")


def expected_events():
    """The JOURNALS lines as am re-emits them: every key present, story null
    when absent, ts normalised from +00:00 to Z, ordered by (run_id, seq)."""
    events = []
    for run_id in sorted(JOURNALS):
        for line in sorted(JOURNALS[run_id], key=lambda entry: entry["seq"]):
            events.append({"story": None, **line, "ts": line["ts"].replace("+00:00", "Z")})
    return events
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `python3 -m pytest tests/contract/test_am_shapes.py -v`
Expected: `3 passed`.

- [ ] **Step 5: Commit**

```bash
git add tests/contract/test_am_shapes.py
git commit -m "test(contract): pin am watch --all events envelope and journal-line keys"
```

---

### Task 3: `am watch --all --follow` hello line then journal lines, timeout-bounded

**Files:**
- Modify: `tests/contract/test_am_shapes.py` (import block; add `FOLLOW_TIMEOUT` and `read_lines` after `expected_events`; append a test)
- Test: `tests/contract/test_am_shapes.py`

**Interfaces:**
- Consumes: fixture `am` (`am.env`, `am.data`) from Task 1; `EVENT_KEYS`, `write_journals(data_dir)`, `expected_events()` from Task 2.
- Produces: `FOLLOW_TIMEOUT = 10`; `read_lines(stream, count: int, timeout: float = FOLLOW_TIMEOUT) -> list[dict]` (the first `count` lines parsed as JSON, or `pytest.fail` at the deadline).

- [ ] **Step 1: Write the failing test**

Append to the end of `tests/contract/test_am_shapes.py`:

```python


def test_watch_all_follow_prints_a_hello_line_then_journal_lines(am):
    write_journals(am.data)
    expected = expected_events()
    with subprocess.Popen(["am", "watch", "--all", "--follow"], env=am.env,
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True) as proc:
        try:
            # --follow never exits on its own: read only the lines expected.
            hello, *events = read_lines(proc.stdout, 1 + len(expected))
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
    assert hello["event"] == "watch", hello
    assert hello["schema"] == 1, hello
    assert isinstance(hello["am"], str) and hello["am"], hello
    assert isinstance(hello["runs_dir"], str), hello
    # Hermetic: the stream reads the throwaway data dir, not the user's.
    assert hello["runs_dir"] == str(am.data / "agent-manager" / "runs"), hello
    for event in events:
        assert set(event) == EVENT_KEYS, event
        assert event["ts"].endswith("Z"), event
    assert events == expected
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m pytest tests/contract/test_am_shapes.py::test_watch_all_follow_prints_a_hello_line_then_journal_lines -v`
Expected: FAIL with `NameError: name 'read_lines' is not defined` (the `finally` still terminates the `am` process, so the run returns promptly).

- [ ] **Step 3: Add the imports**

In `tests/contract/test_am_shapes.py`, replace the import block

```python
import json
import os
import shutil
import subprocess
from types import SimpleNamespace
```

with

```python
import json
import os
import queue
import shutil
import subprocess
import threading
import time
from types import SimpleNamespace
```

- [ ] **Step 4: Add the bounded line reader**

In `tests/contract/test_am_shapes.py`, insert this block directly after the `expected_events` function (before `def test_runs_with_no_data_dir_is_an_empty_list`), separated by two blank lines on each side:

```python
FOLLOW_TIMEOUT = 10


def read_lines(stream, count, timeout=FOLLOW_TIMEOUT):
    """The first `count` lines of `stream`, parsed as JSON.

    A daemon thread pumps lines into a queue and every get is bounded by one
    shared deadline, so an am that goes silent or exits early fails the test
    with what it did print instead of hanging the suite.
    """
    lines = queue.Queue()

    def pump():
        try:
            for line in stream:
                lines.put(line)
        except (OSError, ValueError):
            return  # the pipe was closed under us once the test is done

    threading.Thread(target=pump, daemon=True).start()
    got = []
    deadline = time.monotonic() + timeout
    while len(got) < count:
        try:
            got.append(lines.get(timeout=max(deadline - time.monotonic(), 0.01)))
        except queue.Empty:
            pytest.fail(f"am printed {len(got)} of {count} lines within {timeout}s: {got!r}")
    return [json.loads(line) for line in got]
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `python3 -m pytest tests/contract/test_am_shapes.py -v`
Expected: `4 passed`, finishing in a few seconds.

- [ ] **Step 6: Verify the timeout bites instead of hanging**

Temporarily change `hello, *events = read_lines(proc.stdout, 1 + len(expected))` to `hello, *events = read_lines(proc.stdout, 2 + len(expected), timeout=2)` and run:

Run: `python3 -m pytest tests/contract/test_am_shapes.py::test_watch_all_follow_prints_a_hello_line_then_journal_lines -v`
Expected: FAIL within about 2 seconds with `am printed 4 of 5 lines within 2s`, and no leftover process (`pgrep -f "am watch --all --follow"` prints nothing). Then revert the line to exactly `hello, *events = read_lines(proc.stdout, 1 + len(expected))` and rerun the same command; expected PASS.

- [ ] **Step 7: Commit**

```bash
git add tests/contract/test_am_shapes.py
git commit -m "test(contract): pin am watch --follow hello line and streamed journal lines"
```

---

### Task 4: Document the am contract test and run full verification

**Files:**
- Modify: `docs/architecture.md:149-152` (the `python3 -m pytest tests/contract -q` bullet in "## Tests")

**Interfaces:**
- Consumes: the finished `tests/contract/test_am_shapes.py` from Tasks 1 to 3.
- Produces: nothing code-facing.

- [ ] **Step 1: Extend the contract-tests bullet**

In `docs/architecture.md`, replace

```markdown
- `python3 -m pytest tests/contract -q` - runs the installed `brd` in a throwaway
  project (its own `HOME`/`XDG_DATA_HOME`/`XDG_STATE_HOME` under a tmp dir, so no
  real board is read or written) and fails when brd's JSON shape drifts from what
  `core/domain/brd-extras.js` parses; skipped when `brd` is absent.
```

with

```markdown
- `python3 -m pytest tests/contract -q` - runs the installed `brd` in a throwaway
  project (its own `HOME`/`XDG_DATA_HOME`/`XDG_STATE_HOME` under a tmp dir, so no
  real board is read or written) and fails when brd's JSON shape drifts from what
  `core/domain/brd-extras.js` parses; skipped when `brd` is absent.
  `test_am_shapes.py` does the same for the installed `am`: hand-written schema 1
  journals under a throwaway `XDG_DATA_HOME`, pinning the `am runs`, `am status`
  and `am watch` (one-shot and `--follow`) shapes `core/backend/runs/*` parses;
  skipped when `am` is absent.
```

- [ ] **Step 2: Run the contract and architecture tiers**

Run: `python3 -m pytest tests/contract tests/architecture -q`
Expected: all pass (the brd contract tests pass or skip as before; the 4 am tests pass).

- [ ] **Step 3: Run the full verification**

Run: `bash ./tests/run.sh`
Expected: pytest reports no failures, every QML test prints `Totals` with 0 failed, and the script exits 0.

- [ ] **Step 4: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): mention the am contract test under Tests"
```
