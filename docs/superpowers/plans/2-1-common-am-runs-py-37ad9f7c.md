# 2.1 `common/am_runs.py`: the per-project snapshot, moved — design

Card `37ad9f7c`, a subtask of story `d1d142ee` ("Global runs backend"). Parent
spec: `docs/superpowers/specs/2026-10-05-runs-all-projects-design.md` (below:
**parent**). Layering: `docs/architecture.md` (below: **arch**).

## Goal

The am-calling and snapshot-building code of `core/backend/runs/runs-snapshot.py`
moves into a new shared module, `core/backend/common/am_runs.py`, and the script
imports it back. The script's CLI contract and output do not change by one byte,
and its test file `tests/core/backend/runs/test_runs_snapshot.py` is not edited
and stays green. The module is what sibling 2.2 (`runs-snapshot-all.py`) will
call per project root.

## Starting state (verified 2026-10-08, branch head `ed6e6df`)

- `runs-snapshot.py` already treats both `cancelled` and `canceled` as terminal
  (`TERMINAL`, line 50; docstring line 14), and the fake-am tests already pin
  it: `test_terminal_set_pinned` (`cancelled` and `canceled` keep 10 of 12;
  `Canceled`, `CANCELED`, `" canceled"`, `"canceled "`, `cancel` keep 12),
  `test_canceled_spelling_reported_verbatim`, and the mixed rows of
  `test_status_fanout_selection` (`test_runs_snapshot.py` L407-458).
- The card's "ONE behaviour change" is therefore already shipped. This subtask
  makes **no** behaviour change. It must not alter the terminal set, and must
  not add a second fake-am test that repeats L434-458. The card's "new test" is
  met by the module-level tests below (T6, T7), which pin the set on
  `common.am_runs` itself, where 2.2 will read it.
- `core/backend/common/am_runs.py` does not exist. Nothing else in `core/`
  references `call_am`, `AmFailure`, `run_list` or `select_runs`.

## Inherited constraints

| constraint | source |
|---|---|
| `runs-snapshot.py` runs `am runs --all-projects --limit N`, then `am status RUN` per selected run (every non-terminal run plus the newest K terminal ones), forwards `as_of_seq`; `<project_root>` is an optional filter | parent L114-117 |
| Its terminal-status set accepts `cancelled` and `canceled` | parent L117-118 |
| The snapshot keeps the same selection rule wherever it is used | parent L105-107 |
| `core/backend` imports only the stdlib and `core/backend/common` | arch L12 |
| A helper script is `core/backend/<domain>/name.py`, one JSON line on stdout, `sys.path` insert of its parent for `common`, no duplicated helpers | arch L213-215 |
| A second copy of `emit` / `inside` / `write_atomic` / `split_frontmatter` / `frontmatter_of` fails the architecture test | arch L197-201; `tests/architecture/test_layers.py:234-241` |
| `runs-snapshot.py`'s contract: three modes, exactly one JSON line on every path, error types `Usage` (exit 2), `AmMissing`, `AmBadOutput`, `SchemaMismatch`, `HelperError`, am's `ok:false` envelope re-emitted unchanged, never partial, 60 s per am call, only `am` argv lists | arch L195; `runs-snapshot.py` L1-33 |
| Delete the moved code from `runs-snapshot.py`; do not copy it | card |
| `bash tests/run.sh` green; `tests/architecture` green | card |
| Docstrings and comments state the contract only, no narrative | card |
| TDD: tests first | card |

## Behaviour

### What moves to `core/backend/common/am_runs.py`

Moved verbatim (code, docstrings and the comment above `TERMINAL`), then
deleted from the script:

| name | contract (unchanged) |
|---|---|
| `AM_TIMEOUT = 60` | seconds per am call, the default a caller passes |
| `LIST_LIMIT = 200` | the `--limit` of every `am runs` call |
| `TERMINAL` | `frozenset({"done", "escalated", "stopped", "cancelled", "canceled"})`, matched exactly |
| `TERMINAL_LIMIT = 10` | terminal runs kept per list |
| `class AmFailure(Exception)` | `.payload` is the one envelope dict to emit |
| `bad_output(message)` | `AmFailure` with `{"ok": false, "error": {"type": "AmBadOutput", "message": message}}` |
| `schema_mismatch(what)` | `AmFailure` with type `SchemaMismatch`, message `what + " sent no non-negative integer as_of_seq; the plugin needs the newer am."` |
| `as_of_seq(data, what)` | `data["as_of_seq"]` when it is a non-negative `int` (not `bool`), else raises `schema_mismatch(what)` |
| `store_id(data)` | `data["store_id"]` when a `str`, else `""` |
| `data_dir()` | `XDG_DATA_HOME` when absolute, else `~/.local/share` |
| `call_am(am, args, timeout)` | runs `[am, *args]` (stdin `DEVNULL`, captured text, `timeout` seconds); returns the envelope's `data`; `ok:false` envelope raised as `AmFailure(envelope)`; non-JSON, non-object, or no boolean `ok: true` raise `bad_output` with today's messages; `subprocess.TimeoutExpired` and `OSError` propagate |
| `run_list(data)` | `data["runs"]` checked: a list of objects each with a non-empty string `id` and a string `status`; else `bad_output` with today's messages |
| `select_runs(runs)` | every run whose `status` is not in `TERMINAL`, plus the first `TERMINAL_LIMIT` that are, in input order; returns a new list, input unchanged |
| `run_status(am, run_id, timeout)` | `am status RUN` data (never `--repo-dir`); not an object → `bad_output("am status RUN data is not an object.")`; no valid `as_of_seq` → `SchemaMismatch` naming `am status RUN` |
| `list_snapshot(am, scope, timeout)` | `am runs <scope> --limit LIST_LIMIT`, `run_list` and `as_of_seq` checked before any status call, then `run_status` per `select_runs` row; returns `{"ok": true, "as_of_seq", "store_id", "runs": [row with status replaced], "data_dir"}` |
| `single_snapshot(am, run_id, timeout)` | `{"ok": true, "run", "as_of_seq", "store_id", "status", "data_dir"}` from `run_status` alone |

The only signature change is the `timeout` parameter on `call_am`, `run_status`,
`list_snapshot` and `single_snapshot`: required, positional or keyword, no
default. Each call passes it down unchanged, so one value bounds every am call
of one snapshot. A required argument means no caller can silently get a
timeout it did not choose (2.2 passes its own).

The module docstring states the module's contract in a few lines: the am
commands it runs, that it reads nothing but `am` output, and that every
failure is an `AmFailure` whose payload is the line to print, except a timeout
or an am that cannot start, which propagate for the caller's catch-all. It
imports only the stdlib (`json`, `os`, `subprocess`). It prints nothing and
never calls `emit` or `sys.exit`.

### What stays in `runs-snapshot.py`

The module docstring (L1-33, unchanged), the `sys.path` insert and
`from common.json_line import emit`, `USAGE`, `failure()`, `parse_args`,
`main`, `guarded` and the `__main__` guard. It imports from `common.am_runs`
exactly the names it uses (`AM_TIMEOUT`, `AmFailure`, `list_snapshot`,
`single_snapshot`), and `main` passes the script's own module-level
`AM_TIMEOUT`, read when `main` runs, as `timeout`.

That last point keeps `test_am_timeout_is_helper_error`
(`test_runs_snapshot.py` L294-306) green without editing it: the test loads the
script as module `runs_snapshot` and does
`monkeypatch.setattr(helper, "AM_TIMEOUT", 0.5)`. The patched name is the
script's own binding (imported from `common.am_runs`), and `main` must read
that binding, not `am_runs.AM_TIMEOUT`, so the 10 s fake am is cut off at
0.5 s and reported as `HelperError`. Reading `am_runs.AM_TIMEOUT` instead would
make the test fail with `AmBadOutput` after 10 s.

### Observable behaviour of the script

Identical to today for every argv, environment and am output: same stdout
line (same key order, same messages), same exit code, same am argv in the
same order. No new key, no new error type.

## Errors and edge cases

| input | behaviour (all as today) |
|---|---|
| am hangs past `timeout` | `TimeoutExpired` leaves `am_runs`; the script's `guarded` prints `HelperError` "The runs snapshot failed: ..." |
| am cannot start | `OSError` leaves `am_runs`; `HelperError` |
| am prints non-JSON / a non-object / an object without `ok` | `AmBadOutput`, message naming `am runs` or `am status` |
| am prints `ok:false` | that envelope, unchanged, exit 1 |
| `as_of_seq` missing, negative, `true`, `1.0`, `"1"` | `SchemaMismatch` |
| a status in any case or whitespace other than the five exact strings | non-terminal (kept, does not count toward 10) |
| `select_runs([])` | `[]` |

## Out of scope

- Sibling 2.2 `runs-snapshot-all.py` (several roots, thread pool,
  `RootMissing`, per-project entries), 2.3 `runs-watch.py` several roots,
  2.4 `viewer-state.py` global settings.
- The other scripts' own `AM_TIMEOUT = 60` (`run-control.py`, `runs-logs.py`,
  `dispatch-preview.py`) stay as they are.
- Any change to the terminal set, the limits, messages or output shape.
- Editing `tests/core/backend/runs/test_runs_snapshot.py`.
- The parent's L113 sentence "No `core/backend/common/am_runs.py` and no
  `runs-snapshot-all.py`" contradicts this card and 2.2 (the card wins). This
  subtask does not edit the parent spec; it is flagged for the milestone's
  docs card.

## Docs

`docs/architecture.md` L181-182, the `core/backend/common` list, gains
`am_runs` (the am calls and snapshot shared by the run helpers). No other doc
changes.

## Tests

New file `tests/core/backend/common/test_am_runs.py`, laid out like
`tests/core/backend/common/test_json_line.py` (`sys.path` insert of
`core/backend`, `from common import am_runs`). Tests that run am use a fake
`am` script written to `tmp_path` and passed as the `am` argument (an absolute
path; no `PATH` change needed). All are **unit** tier: they exercise one
module's functions in-process with a fake executable, which is the fastest
level that reaches each contract; the end-to-end CLI tier is already covered
by the unchanged `test_runs_snapshot.py`.

| id | test | what it pins |
|---|---|---|
| T1 | `test_call_am_returns_data_of_an_ok_envelope` | fake am prints `{"ok": true, "data": {...}}`; returns `data`; the fake records its argv and it is exactly `args` |
| T2 | `test_call_am_raises_the_refusal_unchanged` | `ok:false` envelope → `AmFailure` whose `payload` equals the envelope |
| T3 | `test_call_am_bad_output` (parametrized: non-JSON, `[]`, `{}`, `{"ok": "yes"}`) | `AmFailure` with type `AmBadOutput` and today's messages (`am runs did not print JSON (exit N).`, `... printed JSON that is not an object.`, `... printed an object without an ok field.`) |
| T4 | `test_call_am_honours_timeout` | fake am sleeps 10 s, `timeout=0.5` → `subprocess.TimeoutExpired` within ~1 s |
| T5 | `test_as_of_seq_accepts_only_non_negative_ints` (parametrized: `0`, `7` pass; missing, `-1`, `True`, `1.0`, `"1"` fail) | `SchemaMismatch` message `"<what> sent no non-negative integer as_of_seq; the plugin needs the newer am."` |
| T6 | `test_terminal_set_is_the_five_exact_statuses` | `am_runs.TERMINAL == {"done", "escalated", "stopped", "cancelled", "canceled"}` |
| T7 | `test_select_runs_caps_terminal_under_either_cancel_spelling` (parametrized over `cancelled`, `canceled` → 10 kept of 12; `Canceled`, `" canceled"`, `started` → 12) | the cap and both spellings at the module, plus that non-terminal rows interleaved after the cap are still kept, order preserved, input list not mutated |
| T8 | `test_run_list_rejects_malformed_rows` (parametrized: no `runs`, `runs` not a list, a row without `id`, empty `id`, non-string `status`) | `AmBadOutput` |
| T9 | `test_list_snapshot_checks_the_list_before_any_status_call` | fake am: `am runs` data without `as_of_seq` → `SchemaMismatch` and the fake's call log holds only the `runs` call |
| T10 | `test_list_snapshot_passes_scope_and_limit` | scope `["--repo-dir", "/r"]` → first call is `runs --repo-dir /r --limit 200`, then `status <id>` per selected row; result keys and `data_dir` as the contract |
| T11 | `test_store_id_and_data_dir` | `store_id` non-string → `""`; `data_dir` with relative / empty / absolute `XDG_DATA_HOME` (monkeypatched env) |

Regression gates, unchanged files:

- `tests/core/backend/runs/test_runs_snapshot.py` (integration tier: the
  script as a subprocess against a fake `am` on `PATH`, plus
  `test_am_timeout_is_helper_error` in-process) — proves the CLI contract and
  output are identical. `git diff --stat` must show it untouched.
- `tests/architecture` — proves no duplicated helper and the layering.

TDD order: T1-T11 are written first and fail on import (`common.am_runs` does
not exist); the module is then created by moving the code, the script is cut
down to import it, and all three suites pass.

Verification: `bash tests/run.sh` green. Fast loop:
`python3 -m pytest tests/core/backend/common tests/core/backend/runs/test_runs_snapshot.py tests/architecture -q`.

## Planner notes

- One task is the right size: the module, its tests, the script cut-down and
  the one-line doc edit change together, and no part can be approved while
  another is rejected (the script cannot import a module that does not exist;
  a module without the cut-down is a duplicate).
- Check after the move that `grep -n "def call_am\|def select_runs\|TERMINAL = " core/backend/runs/runs-snapshot.py`
  prints nothing.
- Review focus candidates: the `AM_TIMEOUT` binding (read the script's name at
  call time), the `timeout` reaching every am call of one snapshot including
  each `am status`, key order of the output dicts, and the module not printing
  or exiting.

---

# 2.1 `common/am_runs.py` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the am-calling and snapshot-building code of `core/backend/runs/runs-snapshot.py` into a new shared module `core/backend/common/am_runs.py`, with an explicit `timeout` parameter, and have the script import it back with byte-identical CLI behaviour.

**Architecture:** `am_runs.py` holds the constants, `AmFailure`, the envelope checks and the three snapshot builders, verbatim apart from a required `timeout` argument threaded through `call_am` → `run_status` → `list_snapshot` / `single_snapshot`. The script keeps its docstring, argv parsing, `main`, `guarded` and `failure`, imports four names from `common.am_runs`, and passes its own module-level `AM_TIMEOUT` (read at call time) as `timeout`.

**Tech Stack:** Python 3 stdlib only (`json`, `os`, `subprocess`); pytest (run via `uv run --with pytest` because the machine's `python3` has no pytest).

**Spec:** `docs/superpowers/specs/2-1-common-am-runs-py-37ad9f7c.md` (also prepended above).

## Global Constraints

- `core/backend` imports only the stdlib and `core/backend/common`.
- `am_runs.py` imports only `json`, `os`, `subprocess`; it prints nothing and never calls `emit` or `sys.exit`.
- `TERMINAL = frozenset({"done", "escalated", "stopped", "cancelled", "canceled"})`, matched exactly; `TERMINAL_LIMIT = 10`; `LIST_LIMIT = 200`; `AM_TIMEOUT = 60`.
- `timeout` on `call_am`, `run_status`, `list_snapshot`, `single_snapshot` is required, no default.
- Delete the moved code from `runs-snapshot.py`; do not copy it. No second copy of `emit` / `inside` / `write_atomic` / `split_frontmatter` / `frontmatter_of`.
- `tests/core/backend/runs/test_runs_snapshot.py` is not edited (`git diff --stat` must not list it).
- The script's stdout line, key order, messages, exit codes and am argv order are unchanged for every input. No new key, no new error type.
- Docstrings and comments state the contract only, no narrative.
- Never use `pkill`/`killall`/pattern `kill`; bound slow runs with `timeout`.
- `bash tests/run.sh` green; `tests/architecture` green.

## Review Focus

1. The `timeout` must bound every `am status` call of a list snapshot, not only `am runs` — a hanging `am status` must raise `TimeoutExpired` within the caller's timeout (test: `test_list_snapshot_bounds_each_status_call_by_timeout`).
2. `main` must read the script's own `AM_TIMEOUT` binding at call time so the monkeypatch in `test_am_timeout_is_helper_error` still cuts a 10 s am off at 0.5 s (pinned by that unchanged test; Step 6 runs it).
3. `single_snapshot`'s output keys and order (`ok, run, as_of_seq, store_id, status, data_dir`) must survive the move (test: `test_single_snapshot_shape_and_key_order`).
4. `run_status` on `am status` data that is not an object must be `AmBadOutput` "am status RUN data is not an object." (test: `test_run_status_rejects_non_object_data`).
5. The module must print nothing on success or failure — a stray print would add a second stdout line to the script (test: `capsys` assertions in `test_list_snapshot_passes_scope_and_limit` and `test_list_snapshot_checks_the_list_before_any_status_call`).

---

### Task 1: `common/am_runs.py`, its tests, the script cut-down and the doc line

**Files:**
- Create: `core/backend/common/am_runs.py`
- Create: `tests/core/backend/common/test_am_runs.py`
- Modify: `core/backend/runs/runs-snapshot.py:35-177` (imports and the moved block), `:194-206` (`main`)
- Modify: `docs/architecture.md:181-182`
- Regression (unchanged): `tests/core/backend/runs/test_runs_snapshot.py`, `tests/architecture/`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces (for sibling 2.2 `runs-snapshot-all.py`), module `common.am_runs`:
  - `AM_TIMEOUT: int = 60`, `LIST_LIMIT: int = 200`, `TERMINAL: frozenset[str]`, `TERMINAL_LIMIT: int = 10`
  - `class AmFailure(Exception)` with `.payload: dict`
  - `bad_output(message: str) -> AmFailure`, `schema_mismatch(what: str) -> AmFailure`
  - `as_of_seq(data: dict, what: str) -> int`, `store_id(data: dict) -> str`, `data_dir() -> str`
  - `call_am(am: str, args: list[str], timeout: float) -> object`
  - `run_list(data: object) -> list[dict]`, `select_runs(runs: list[dict]) -> list[dict]`
  - `run_status(am: str, run_id: str, timeout: float) -> dict`
  - `list_snapshot(am: str, scope: list[str], timeout: float) -> dict`
  - `single_snapshot(am: str, run_id: str, timeout: float) -> dict`

- [ ] **Step 1: Write the failing tests**

Create `tests/core/backend/common/test_am_runs.py` with exactly this content:

```python
"""common.am_runs: the am calls and the snapshot, against a fake am in tmp_path.

The fake am logs each argv as a JSON line to calls.log beside it, prints the
reply for its call ("runs" or "status-<id>"; "" when none) and exits with the
given code. The real am is never run.
"""
import copy
import json
import os
import subprocess
import sys
import time

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), *[".."] * 4, "core", "backend"))
from common import am_runs  # noqa: E402

FAKE_AM = '''#!/usr/bin/env python3
import json, os, sys
here = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]
with open(os.path.join(here, "calls.log"), "a") as f:
    f.write(json.dumps(args) + "\\n")
replies = json.loads(%r)
name = "runs" if args[:1] == ["runs"] else "status-" + (args[1] if len(args) > 1 else "")
sys.stdout.write(replies.get(name, ""))
sys.exit(%d)
'''

# An am that sleeps 10 s on `am status`, and answers `am runs` at once with one
# started run r1.
SLOW_STATUS_AM = '''#!/usr/bin/env python3
import json, sys, time
if sys.argv[1:2] == ["status"]:
    time.sleep(10)
sys.stdout.write(json.dumps({"ok": True, "data": {"as_of_seq": 1, "store_id": "s",
                 "runs": [{"id": "r1", "status": "started"}]}}))
'''

NEWER_AM = " sent no non-negative integer as_of_seq; the plugin needs the newer am."


def write_exec(path, text):
    path.write_text(text)
    path.chmod(0o755)
    return str(path)


def fake_am(tmp_path, replies, code=0):
    """The fake am at tmp_path/am; `replies` maps "runs" / "status-<id>" to stdout text."""
    return write_exec(tmp_path / "am", FAKE_AM % (json.dumps(replies), code))


def ok(data):
    return json.dumps({"ok": True, "data": data})


def calls(tmp_path):
    log = tmp_path / "calls.log"
    if not log.exists():
        return []
    return [json.loads(line) for line in log.read_text().splitlines()]


def error_of(excinfo):
    return excinfo.value.payload["error"]


# --- call_am ------------------------------------------------------------------

def test_call_am_returns_data_of_an_ok_envelope(tmp_path):
    am = fake_am(tmp_path, {"runs": ok({"runs": [], "as_of_seq": 3})})
    args = ["runs", "--all-projects", "--limit", "200"]
    assert am_runs.call_am(am, args, 5) == {"runs": [], "as_of_seq": 3}
    assert calls(tmp_path) == [args]


def test_call_am_raises_the_refusal_unchanged(tmp_path):
    envelope = {"error": {"message": "store busy", "type": "StoreBusyError"}, "ok": False}
    am = fake_am(tmp_path, {"runs": json.dumps(envelope)}, code=3)
    with pytest.raises(am_runs.AmFailure) as excinfo:
        am_runs.call_am(am, ["runs", "--all-projects"], 5)
    assert excinfo.value.payload == envelope


@pytest.mark.parametrize("stdout, message", [
    ("not json", "am runs did not print JSON (exit 3)."),
    ("[]", "am runs printed JSON that is not an object."),
    ("{}", "am runs printed an object without an ok field."),
    ('{"ok": "yes"}', "am runs printed an object without an ok field."),
], ids=["non-json", "array", "no-ok", "ok-not-bool"])
def test_call_am_bad_output(tmp_path, stdout, message):
    am = fake_am(tmp_path, {"runs": stdout}, code=3)
    with pytest.raises(am_runs.AmFailure) as excinfo:
        am_runs.call_am(am, ["runs"], 5)
    assert excinfo.value.payload == {"ok": False, "error": {"type": "AmBadOutput", "message": message}}


def test_call_am_honours_timeout(tmp_path):
    am = write_exec(tmp_path / "am", "#!/usr/bin/env python3\nimport time\ntime.sleep(10)\n")
    start = time.monotonic()
    with pytest.raises(subprocess.TimeoutExpired):
        am_runs.call_am(am, ["runs"], 0.5)
    assert time.monotonic() - start < 5


# --- as_of_seq, store_id, data_dir ---------------------------------------------

@pytest.mark.parametrize("seq", [0, 7])
def test_as_of_seq_accepts_non_negative_ints(seq):
    assert am_runs.as_of_seq({"as_of_seq": seq}, "am runs") == seq


DROP = object()


@pytest.mark.parametrize("seq", [DROP, -1, True, 1.0, "1"],
                         ids=["missing", "negative", "bool", "float", "string"])
def test_as_of_seq_accepts_only_non_negative_ints(seq):
    data = {} if seq is DROP else {"as_of_seq": seq}
    with pytest.raises(am_runs.AmFailure) as excinfo:
        am_runs.as_of_seq(data, "am status r1")
    assert excinfo.value.payload == {"ok": False, "error": {
        "type": "SchemaMismatch", "message": "am status r1" + NEWER_AM}}


def test_store_id_and_data_dir(tmp_path, monkeypatch):
    assert am_runs.store_id({"store_id": "s1"}) == "s1"
    assert am_runs.store_id({"store_id": 7}) == ""
    assert am_runs.store_id({}) == ""
    monkeypatch.setenv("HOME", str(tmp_path))
    fallback = os.path.join(str(tmp_path), ".local", "share")
    monkeypatch.setenv("XDG_DATA_HOME", "relative/data")
    assert am_runs.data_dir() == fallback
    monkeypatch.setenv("XDG_DATA_HOME", "")
    assert am_runs.data_dir() == fallback
    monkeypatch.delenv("XDG_DATA_HOME")
    assert am_runs.data_dir() == fallback
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    assert am_runs.data_dir() == str(tmp_path / "data")


# --- TERMINAL, select_runs, run_list -------------------------------------------

def test_terminal_set_is_the_five_exact_statuses():
    assert am_runs.TERMINAL == {"done", "escalated", "stopped", "cancelled", "canceled"}
    assert isinstance(am_runs.TERMINAL, frozenset)
    assert am_runs.TERMINAL_LIMIT == 10
    assert am_runs.LIST_LIMIT == 200
    assert am_runs.AM_TIMEOUT == 60


@pytest.mark.parametrize("status, kept", [
    ("cancelled", 10), ("canceled", 10),
    ("Canceled", 12), (" canceled", 12), ("started", 12),
])
def test_select_runs_caps_terminal_under_either_cancel_spelling(status, kept):
    runs = [{"id": "t%d" % i, "status": status} for i in range(12)]
    runs.insert(3, {"id": "early", "status": "started"})
    runs.append({"id": "late", "status": "started"})
    before = copy.deepcopy(runs)
    picked = am_runs.select_runs(runs)
    expected = ["t0", "t1", "t2", "early"] + ["t%d" % i for i in range(3, kept)] + ["late"]
    assert [run["id"] for run in picked] == expected
    assert runs == before
    assert picked is not runs


def test_select_runs_of_nothing_is_nothing():
    assert am_runs.select_runs([]) == []


@pytest.mark.parametrize("data, message", [
    ({}, "am runs data has no runs list."),
    (None, "am runs data has no runs list."),
    ({"runs": {}}, "am runs data has no runs list."),
    ({"runs": [{"status": "done"}]}, "am runs listed a run without an id or status."),
    ({"runs": [{"id": "", "status": "done"}]}, "am runs listed a run without an id or status."),
    ({"runs": [{"id": "r1", "status": 3}]}, "am runs listed a run without an id or status."),
    ({"runs": ["r1"]}, "am runs listed a run without an id or status."),
], ids=["no-runs", "not-object", "runs-not-list", "no-id", "empty-id", "status-not-str", "row-not-object"])
def test_run_list_rejects_malformed_rows(data, message):
    with pytest.raises(am_runs.AmFailure) as excinfo:
        am_runs.run_list(data)
    assert error_of(excinfo) == {"type": "AmBadOutput", "message": message}


# --- run_status, list_snapshot, single_snapshot ---------------------------------

def test_run_status_rejects_non_object_data(tmp_path):
    am = fake_am(tmp_path, {"status-r1": ok([1, 2])})
    with pytest.raises(am_runs.AmFailure) as excinfo:
        am_runs.run_status(am, "r1", 5)
    assert error_of(excinfo) == {"type": "AmBadOutput", "message": "am status r1 data is not an object."}
    assert calls(tmp_path) == [["status", "r1"]]


def test_run_status_without_as_of_seq_is_schema_mismatch(tmp_path):
    am = fake_am(tmp_path, {"status-r1": ok({"run": {"id": "r1"}})})
    with pytest.raises(am_runs.AmFailure) as excinfo:
        am_runs.run_status(am, "r1", 5)
    assert error_of(excinfo) == {"type": "SchemaMismatch", "message": "am status r1" + NEWER_AM}


def test_list_snapshot_checks_the_list_before_any_status_call(tmp_path, capsys):
    am = fake_am(tmp_path, {"runs": ok({"runs": [{"id": "r1", "status": "started"}]}),
                            "status-r1": ok({"as_of_seq": 1})})
    with pytest.raises(am_runs.AmFailure) as excinfo:
        am_runs.list_snapshot(am, ["--all-projects"], 5)
    assert error_of(excinfo) == {"type": "SchemaMismatch", "message": "am runs" + NEWER_AM}
    assert calls(tmp_path) == [["runs", "--all-projects", "--limit", "200"]]
    assert capsys.readouterr().out == ""


def test_list_snapshot_passes_scope_and_limit(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    r1 = {"as_of_seq": 6, "store_id": "s1", "run": {"id": "r1", "status": "started"}}
    r2 = {"as_of_seq": 7, "store_id": "s1", "run": {"id": "r2", "status": "done"}}
    am = fake_am(tmp_path, {
        "runs": ok({"as_of_seq": 5, "store_id": "s1", "runs": [
            {"id": "r1", "status": "started", "repo_dir": "/r"},
            {"id": "r2", "status": "done", "repo_dir": "/r"}]}),
        "status-r1": ok(r1), "status-r2": ok(r2)})
    result = am_runs.list_snapshot(am, ["--repo-dir", "/r"], 5)
    assert calls(tmp_path) == [["runs", "--repo-dir", "/r", "--limit", "200"],
                               ["status", "r1"], ["status", "r2"]]
    assert list(result) == ["ok", "as_of_seq", "store_id", "runs", "data_dir"]
    assert result == {"ok": True, "as_of_seq": 5, "store_id": "s1", "runs": [
        {"id": "r1", "status": r1, "repo_dir": "/r"},
        {"id": "r2", "status": r2, "repo_dir": "/r"}], "data_dir": str(tmp_path / "data")}
    assert capsys.readouterr().out == ""


def test_list_snapshot_bounds_each_status_call_by_timeout(tmp_path):
    am = write_exec(tmp_path / "am", SLOW_STATUS_AM)
    start = time.monotonic()
    with pytest.raises(subprocess.TimeoutExpired):
        am_runs.list_snapshot(am, ["--all-projects"], 0.5)
    assert time.monotonic() - start < 5


def test_single_snapshot_shape_and_key_order(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    status = {"as_of_seq": 9, "store_id": 4, "run": {"id": "r1", "status": "canceled"}}
    am = fake_am(tmp_path, {"status-r1": ok(status)})
    result = am_runs.single_snapshot(am, "r1", 5)
    assert calls(tmp_path) == [["status", "r1"]]
    assert list(result) == ["ok", "run", "as_of_seq", "store_id", "status", "data_dir"]
    assert result == {"ok": True, "run": "r1", "as_of_seq": 9, "store_id": "",
                      "status": status, "data_dir": str(tmp_path / "data")}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/common/test_am_runs.py -q`
Expected: collection ERROR, `ModuleNotFoundError: No module named 'common.am_runs'` (or `ImportError: cannot import name 'am_runs' from 'common'`).

- [ ] **Step 3: Create the module by moving the code**

Create `core/backend/common/am_runs.py` with exactly this content (the bodies are those of `runs-snapshot.py` L45-177, with `timeout` threaded through):

```python
"""The am calls and the run snapshot shared by the run helpers.

Runs only `am runs <scope> --limit LIST_LIMIT` and `am status RUN` (never with
--repo-dir), as argv lists, each bounded by the caller's `timeout`; reads
nothing but am's stdout. Every failure is an AmFailure whose `payload` is the
one line to print, except subprocess.TimeoutExpired and OSError (am hangs or
cannot start), which propagate. Prints nothing and never exits.
"""
import json
import os
import subprocess

AM_TIMEOUT = 60
LIST_LIMIT = 200
# The finished statuses, matched exactly. A cancelled run is terminal under either
# spelling, `cancelled` or `canceled`. `stopped` is "parked" (resumable) in the
# domain table, but for the snapshot it is terminal and counts toward the cap.
TERMINAL = frozenset({"done", "escalated", "stopped", "cancelled", "canceled"})
TERMINAL_LIMIT = 10


class AmFailure(Exception):
    """An am call that gave no usable data; `payload` is the one line to emit."""

    def __init__(self, payload):
        super().__init__("am call failed")
        self.payload = payload


def bad_output(message):
    return AmFailure({"ok": False, "error": {"type": "AmBadOutput", "message": message}})


def schema_mismatch(what):
    return AmFailure({"ok": False, "error": {
        "type": "SchemaMismatch",
        "message": what + " sent no non-negative integer as_of_seq; "
                          "the plugin needs the newer am."}})


def as_of_seq(data, what):
    """`data`'s as_of_seq, a non-negative JSON integer (not a bool, float or
    string); else SchemaMismatch, naming the am command `what`."""
    seq = data.get("as_of_seq")
    if not (type(seq) is int and seq >= 0):
        raise schema_mismatch(what)
    return seq


def store_id(data):
    """`data`'s store_id when a string, else ""."""
    store = data.get("store_id")
    return store if isinstance(store, str) else ""


def data_dir():
    """XDG_DATA_HOME, but only when it is absolute (like `state_home()` in
    run-setup-milestone.py); otherwise ~/.local/share. No am subdirectory: that
    would assume am's on-disk layout."""
    data = os.environ.get("XDG_DATA_HOME") or ""
    if not os.path.isabs(data):
        return os.path.join(os.path.expanduser("~"), ".local", "share")
    return data


def call_am(am, args, timeout):
    """Run one am command (at most `timeout` seconds) and return its envelope's
    `data`. The envelope's `ok` decides, not the exit code: an `ok:false`
    envelope is raised as-is (to be re-emitted unchanged); anything that is not
    an envelope is AmBadOutput."""
    proc = subprocess.run([am, *args], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=timeout)
    what = "am " + args[0]
    try:
        envelope = json.loads(proc.stdout)
    except ValueError:
        raise bad_output(what + " did not print JSON (exit " + str(proc.returncode) + ").")
    if not isinstance(envelope, dict):
        raise bad_output(what + " printed JSON that is not an object.")
    if envelope.get("ok") is False:
        raise AmFailure(envelope)
    if envelope.get("ok") is not True:
        raise bad_output(what + " printed an object without an ok field.")
    return envelope.get("data")


def run_list(data):
    """`am runs` data's run list, checked: a list of objects with string id/status."""
    runs = data.get("runs") if isinstance(data, dict) else None
    if not isinstance(runs, list):
        raise bad_output("am runs data has no runs list.")
    for run in runs:
        if not (isinstance(run, dict) and isinstance(run.get("id"), str) and run["id"]
                and isinstance(run.get("status"), str)):
            raise bad_output("am runs listed a run without an id or status.")
    return runs


def select_runs(runs):
    """Every non-terminal run plus the first TERMINAL_LIMIT terminal ones, in am's
    (newest-first) order."""
    picked, terminal = [], 0
    for run in runs:
        if run["status"] in TERMINAL:
            if terminal >= TERMINAL_LIMIT:
                continue
            terminal += 1
        picked.append(run)
    return picked


def run_status(am, run_id, timeout):
    """`am status RUN` data (never with --repo-dir), checked: an object
    (else AmBadOutput) with an as_of_seq (else SchemaMismatch)."""
    status = call_am(am, ["status", run_id], timeout)
    if not isinstance(status, dict):
        raise bad_output("am status " + run_id + " data is not an object.")
    as_of_seq(status, "am status " + run_id)
    return status


def list_snapshot(am, scope, timeout):
    """`am runs <scope> --limit LIST_LIMIT`, checked before any status call, then
    each selected run's row with `status` replaced by its `am status` data; every
    am call gets `timeout`."""
    data = call_am(am, ["runs", *scope, "--limit", str(LIST_LIMIT)], timeout)
    runs = run_list(data)
    seq = as_of_seq(data, "am runs")
    out = []
    for run in select_runs(runs):
        entry = dict(run)
        entry["status"] = run_status(am, run["id"], timeout)
        out.append(entry)
    return {"ok": True, "as_of_seq": seq, "store_id": store_id(data), "runs": out,
            "data_dir": data_dir()}


def single_snapshot(am, run_id, timeout):
    """`am status RUN` alone: the run id as given, its status data verbatim and
    that data's as_of_seq and store_id."""
    status = run_status(am, run_id, timeout)
    return {"ok": True, "run": run_id, "as_of_seq": status["as_of_seq"],
            "store_id": store_id(status), "status": status, "data_dir": data_dir()}
```

- [ ] **Step 4: Run the module tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/common/test_am_runs.py -q`
Expected: all PASS (35 passed with the parametrizations).

- [ ] **Step 5: Cut the script down to import the module**

In `core/backend/runs/runs-snapshot.py`, replace lines 35-177 (from `import json` through the end of `single_snapshot`) with exactly:

```python
import os
import shutil
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.am_runs import AM_TIMEOUT, AmFailure, list_snapshot, single_snapshot  # noqa: E402
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-snapshot.py [<project_root> | --run RUN]"


def failure(kind, message, code=1):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)
```

Then, in `main`, replace the line

```python
        result = list_snapshot(am, arg) if kind == "list" else single_snapshot(am, arg)
```

with

```python
        result = (list_snapshot(am, arg, AM_TIMEOUT) if kind == "list"
                  else single_snapshot(am, arg, AM_TIMEOUT))
```

`AM_TIMEOUT` here is the script's own module global, looked up when `main` runs, so `monkeypatch.setattr(helper, "AM_TIMEOUT", 0.5)` in the unchanged script test takes effect. Do not write `am_runs.AM_TIMEOUT`. The docstring (L1-33), `parse_args`, `guarded` and the `__main__` guard are untouched. The file after the edit reads, from L35 on:

```python
import os
import shutil
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.am_runs import AM_TIMEOUT, AmFailure, list_snapshot, single_snapshot  # noqa: E402
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-snapshot.py [<project_root> | --run RUN]"


def failure(kind, message, code=1):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def parse_args(argv):
    """("list", the `am runs` scope arguments) or ("run", RUN) for the helper's
    argv: --all-projects for none, --repo-dir R for one <project_root>, RUN for
    `--run RUN` (R and RUN non-empty, not starting with -); None for anything
    else."""
    if not argv:
        return "list", ["--all-projects"]
    if len(argv) == 1 and argv[0] and not argv[0].startswith("-"):
        return "list", ["--repo-dir", argv[0]]
    if len(argv) == 2 and argv[0] == "--run" and argv[1] and not argv[1].startswith("-"):
        return "run", argv[1]
    return None


def main(argv):
    mode = parse_args(argv)
    if mode is None:
        return failure("Usage", USAGE, 2)
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    kind, arg = mode
    try:
        result = (list_snapshot(am, arg, AM_TIMEOUT) if kind == "list"
                  else single_snapshot(am, arg, AM_TIMEOUT))
    except AmFailure as e:
        return emit(e.payload, 1)
    return emit(result)


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception (a timeout, an am that cannot start) - may end without one."""
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

- [ ] **Step 6: Run the fast loop and check nothing was copied**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/common tests/core/backend/runs/test_runs_snapshot.py tests/architecture -q`
Expected: all PASS, including `test_am_timeout_is_helper_error` (finishes in about 0.5 s, not 10 s).

Run: `grep -n "def call_am\|def select_runs\|TERMINAL = \|LIST_LIMIT\|def data_dir\|import json\|import subprocess" core/backend/runs/runs-snapshot.py`
Expected: no output.

Run: `git diff --stat -- tests/core/backend/runs/test_runs_snapshot.py`
Expected: no output.

- [ ] **Step 7: Add `am_runs` to the architecture doc's common list**

In `docs/architecture.md`, replace lines 181-182

```
Python: `core/backend/common`
(`json_line`, `safe_paths`, `atomic_write`, `frontmatter`).
```

with

```
Python: `core/backend/common`
(`json_line`, `safe_paths`, `atomic_write`, `frontmatter`, and `am_runs`, the
am calls and snapshot shared by the run helpers).
```

- [ ] **Step 8: Run the full suite**

Run: `timeout 600 bash tests/run.sh`
Expected: pytest all passed, every QML `Totals` line with `0 failed`, exit 0.

- [ ] **Step 9: Commit**

```bash
git add core/backend/common/am_runs.py tests/core/backend/common/test_am_runs.py core/backend/runs/runs-snapshot.py docs/architecture.md
git commit -m "refactor(runs): move the am calls and snapshot into common/am_runs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
<!-- task-pipeline: validated -->
