# `board-titles.py`: one project's card titles — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A read-only helper `core/backend/boards/board-titles.py ROOT` that runs `brd tree` in ROOT and prints one JSON line `{"ok": true, "titles": {id: title}}` covering every card at any depth, or one failure line.

**Architecture:** One stdlib-only Python script modeled on `core/backend/runs/runs-snapshot.py`: `parse_args` → ROOT check → a single `subprocess.run(["brd", "tree"], cwd=ROOT, stdin=DEVNULL, timeout=TIMEOUT_SECONDS)` → envelope handling → a pure, iterative `flatten_titles(data)`; `guarded(argv)` turns any unexpected exception into a `HelperError` line. Output goes only through `common.json_line.emit`. Tests are black-box subprocess runs against a fake POSIX-`sh` `brd` on a temp `PATH`, modeled on `tests/core/backend/boards/test_archive_milestones.py`, plus two in-process tests.

**Tech Stack:** Python 3.13 stdlib (`json`, `os`, `subprocess`, `sys`), pytest (via `uv run --with pytest`), POSIX `sh` fake.

**Spec:** `docs/superpowers/specs/1-1-board-titles-py-one-e1990cac.md` (reproduced verbatim below, headings demoted one level).

---

## Spec (verbatim)

### 1.1 `board-titles.py`: one project's card titles — design

Card: `e1990cac-d30c-461f-bb30-cb26c1485bb5` (subtask of story `8aaf0cb6-3038-487c-b262-bfe02df3e39d`).
Parent design: `docs/superpowers/specs/2026-10-05-run-history-titles-design.md` (cited below as
**parent**), section *Titles › Lookup* (lines 63–74) and *Testing* (lines 208–210).

#### Purpose

`RunTitlesStore` (a later card) needs `{card id: title}` for projects that are not open in the
plugin. This card delivers only the read-only helper that produces that map for ONE project
root, plus its tests.

#### Inherited constraints

| # | constraint | source |
|---|---|---|
| C1 | Path and invocation: `core/backend/boards/board-titles.py ROOT` | parent :67–68 |
| C2 | Runs `brd tree` as an argv list, `cwd=ROOT`, stdin `/dev/null`, 30 s timeout — the same command and working-directory rule as `BoardStore` (`["brd", "tree"]`, `workingDirectory` = project root) | parent :68–70, :35–38; `core/stores/BoardStore.qml:220-223` |
| C3 | Prints ONE JSON line `{"ok": true, "titles": {id: title}}` covering every card at any depth; descriptions dropped | parent :70–71 |
| C4 | Failures: brd's own `ok:false` envelope unchanged (e.g. `ProjectNotFoundError`), `BrdMissing`, `BrdBadOutput`, `RootMissing` (ROOT is not a directory), `HelperError`, `Usage` (exit 2); exit 0 otherwise | parent :71–74 |
| C5 | It never writes | parent :74 |
| C6 | No reading of brd's database; only the `brd` command | parent :56–57 |
| C7 | `core/backend/**` imports only the Python stdlib and `core/backend/common` | `docs/architecture.md:12`, enforced by `tests/architecture/test_layers.py` |
| C8 | Tests: fake `brd`; argv and `cwd`, nested cards flattened, descriptions dropped, envelope passthrough, missing brd, missing root, bad output, one line on every path | parent :208–210 |
| C9 | Docstrings and comments state the contract only, no narrative | card description |

#### Observable behavior

##### Invocation

`board-titles.py ROOT` — exactly one argument, non-empty, not starting with `-`.

##### Output contract

Every run of the helper, on every path, writes **exactly one line** to stdout: a JSON object
followed by a newline (`common.json_line.emit`). Nothing else goes to stdout. Exit codes:
`0` success, `1` failure, `2` usage.

Error shape (the helper's own errors):
`{"ok": false, "error": {"type": <type>, "message": <non-empty human sentence>}}`.

##### Decision order

1. **Usage** — argv is not exactly one argument, or the argument is empty or starts with `-`:
   `{"ok": false, "error": {"type": "Usage", "message": "usage: board-titles.py ROOT"}}`,
   exit 2. `brd` is not run.
2. **RootMissing** — `ROOT` is not an existing directory (does not exist, or is a file):
   type `RootMissing`, message names the path, exit 1. `brd` is not run.
3. **Run brd** — exactly one subprocess: argv `["brd", "tree"]`, `cwd=ROOT`,
   `stdin=/dev/null`, stdout/stderr captured as text, timeout 30 s (a module constant
   `TIMEOUT_SECONDS = 30`). brd is looked up on `PATH`.
   - brd not found on `PATH` → type `BrdMissing`, message "brd is not installed." (or
     equivalent sentence), exit 1.
   - brd does not finish within `TIMEOUT_SECONDS` → type `HelperError`, message says brd tree
     timed out, exit 1.
4. **brd's envelope passthrough** — stdout parses as a JSON object whose `ok` is exactly
   `false`: that object is re-emitted unchanged (equal as a JSON value; serialized on one line),
   exit 1, **regardless of brd's exit code**. Example: from a directory with no brd project, brd
   prints `{"ok":false,"error":{"type":"ProjectNotFoundError",...}}` and the helper prints the
   same object.
5. **BrdBadOutput** (exit 1, message is a sentence, never the raw output) when any of:
   - stdout is not valid JSON, or is JSON but not an object;
   - the object's `ok` is not exactly `true` (missing, `"true"`, `1`, …) and not `false`;
   - `ok` is `true` but brd's exit code is non-zero;
   - `data` is missing or not a list;
   - any card, at any depth, is not an object; its `id` is not a non-empty string; its `title`
     is not a string; or its `children` is present, not `null`, and not a list.
6. **Success** — `{"ok": true, "titles": {id: title, ...}}`, exit 0:
   - Every card of `data` and of every card's `children`, recursively, at any depth,
     contributes exactly one entry `id → title`. A card with `children` absent, `null`, or `[]`
     is a leaf.
   - `titles` values are the titles verbatim (non-ASCII preserved through JSON).
   - Nothing else of a card appears anywhere in the output: no `description`, `status`,
     `blocked_by`, `blockers`, `created_at`, `updated_at`, `children`.
   - The top-level object has exactly the keys `ok` and `titles`.
   - An empty board (`data: []`) gives `{"ok": true, "titles": {}}`.
   - brd ids are unique; should one repeat, the entry visited last in pre-order
     (parent before its children, siblings in list order) wins.
7. **HelperError** — any other exception escaping `main` (caught by a `guarded(argv)`
   wrapper that re-raises `SystemExit`, as `core/backend/runs/runs-snapshot.py:80-89` does):
   type `HelperError`, message `"The board titles lookup failed: <reason>"`, exit 1. One line
   still printed.

##### Side effects

- The only process started is the single `brd tree`. No `brd` write command, no file
  created, modified or removed anywhere (ROOT included). brd's database is never opened (C6).
- The helper does not read its own stdin; brd's stdin is `/dev/null`, so data piped into the
  helper never reaches brd.

#### Tests

All new tests live in `tests/core/backend/boards/test_board_titles.py`, modeled on
`tests/core/backend/boards/test_archive_milestones.py`.

Fixture `box`: a temp `bin/` holding an executable fake `brd` (POSIX `sh`) on
`PATH=<bindir>:/usr/bin:/bin` (the fake needs the external `cat` and `sleep`, which a
`<bindir>`-only PATH would not find; `<bindir>` first so the fake shadows any real `brd`; the
helper is run with `sys.executable`), a project directory whose
name contains a space (`my project`), and env vars the fake reads:
- `CALLS`: the fake appends `brd $* (cwd=$(pwd))` per invocation;
- `STDIN_LOG`: the fake `cat`s its stdin into this file;
- `BRD_OUT`: path of a file whose contents the fake prints to stdout;
- `BRD_EXIT`: the fake's exit code (default 0).
- `BRD_SLEEP` (T15 only): seconds the fake sleeps before printing, via `exec sleep` so the
  kill on timeout reaches the sleeper and does not leave it holding the stdout pipe open.

`run(box, *args, stdin_text=None)` runs `[sys.executable, SCRIPT, *args]` and **asserts
`len(stdout.splitlines()) == 1` on every call**, returning `(code, parsed_json)`.

**Tier: subprocess (black-box CLI) tests**, because the contract under test is the helper's
process boundary — argv, cwd, stdin, stdout line count, exit code — which only a real child
process with a fake `brd` observes. Exceptions are marked.

| # | test | proves |
|---|---|---|
| T1 | `test_runs_brd_tree_once_in_root` | calls log is exactly `["brd tree (cwd=<project.resolve()>)"]` (C2; path with a space) |
| T2 | `test_brd_stdin_is_dev_null` | helper run with piped stdin `"LEAK\n"`; `STDIN_LOG` is empty afterwards (C2) |
| T3 | `test_flattens_nested_cards_at_any_depth` | milestone → story → subtask → sub-subtask (4 levels) plus a second root card and a card with `children: null` all appear; output `== {"ok": True, "titles": {...}}` exactly, exit 0 (C3) |
| T4 | `test_drops_descriptions_and_every_other_field` | cards carry description/status/blocked_by/blockers/created_at/updated_at; output equals the exact `{ok, titles}` object and the raw stdout contains no description text (C3) |
| T5 | `test_empty_board_gives_empty_titles` | `data: []` → `{"ok": True, "titles": {}}`, exit 0 |
| T6 | `test_non_ascii_titles_round_trip` | title `"Café — 日本"` arrives verbatim |
| T7 | `test_brd_envelope_is_passed_through_unchanged` | fake prints a `ProjectNotFoundError` envelope with exit 1 → output equals it, exit 1 (C4) |
| T8 | `test_brd_envelope_passthrough_ignores_brd_exit_code` | same envelope with `BRD_EXIT=0` → still passed through, exit 1 |
| T9 | `test_brd_missing` | `PATH` = an empty directory only (no system dirs) → `BrdMissing`, exit 1 (C4) |
| T10 | `test_bad_output` (parametrized) | non-JSON text; empty stdout; JSON list; object without `ok`; `ok: "true"`; `ok: true` with `data` missing; `data` an object; a card that is a string; a card with no `id`; `id: 5`; `id: ""`; `title: null`; `children: {}` nested two levels down → each `BrdBadOutput`, exit 1 (C4) |
| T11 | `test_ok_envelope_with_nonzero_exit_is_bad_output` | valid `ok:true` data, `BRD_EXIT=3` → `BrdBadOutput`, exit 1 |
| T12 | `test_root_missing` (parametrized) | nonexistent path; a regular file → `RootMissing`, exit 1, calls log empty (C4) |
| T13 | `test_usage` (parametrized) | no args; two args; `""`; `"--help"` → `Usage`, exit 2, calls log empty (C4) |
| T14 | `test_never_writes` | after a successful run, the set of files under the temp root (project dir included) is unchanged except the fake's own logs, and the calls log has only `brd tree` (C5) |
| T15 | `test_timeout_is_helper_error` — **tier: in-process unit** (module loaded with `importlib.util.spec_from_file_location`, `TIMEOUT_SECONDS` patched to a small value, fake brd `sleep`s, stdout captured with `capsys`), because a real 30 s wait is unacceptable in the suite | `HelperError`, return code 1, exactly one captured line |
| T16 | `test_unexpected_exception_is_helper_error` — **tier: in-process unit** (same loading; `monkeypatch` the module's subprocess call to raise `RuntimeError("boom")`), because no deterministic external input makes valid-looking code raise | `guarded([...])` returns 1 and prints exactly one line with type `HelperError` and `boom` in the message |

Every subprocess test asserts the one-line rule through `run()`; T15/T16 assert it on
captured output. Together they cover each exit path: success, passthrough, `BrdMissing`,
`BrdBadOutput`, `RootMissing`, `Usage`, `HelperError` (C8).

**Existing tier that must stay green:** `tests/architecture/` (layer allowlists: the helper
imports only stdlib and `common`; no duplicated components; icon glyph rules), and the full
`bash tests/run.sh` (pytest + QML tests).

#### Out of scope

- `RunTitlesStore.qml`, its queue, cache, invalidation, `titleStatus` (parent :76–94) — sibling
  cards.
- `Runs.titlesFromCards`, `runTitle`, `cardTitle`, search and alert titles in
  `core/domain/runs.js` (parent :96–108) and every UI surface (parent :110–115).
- Run history (`runs-history.py`, `RunHistoryStore`, chips) (parent :117–192).
- Documenting the helper in `docs/architecture.md` or other docs — a later docs card.
- Any change to `BoardStore.qml`, `brd`, `am`, or `common/` (only `common.json_line.emit` is
  reused; no new shared module).
- Caching, retries, or reading any project other than ROOT.

#### Handoff to the planner

**File map**
- Create: `core/backend/boards/board-titles.py` — the helper (shebang `#!/usr/bin/env python3`,
  executable bit (mode 100755, like `runs-snapshot.py`), contract-only module docstring stating the
  invocation, output, error types and exit codes; `sys.path.insert` + `from common.json_line
  import emit  # noqa: E402`; `USAGE`, `TIMEOUT_SECONDS = 30`, `failure(kind, message,
  code=1)`, `parse_args(argv) -> str | None`, a pure `flatten_titles(data) -> dict | None`
  (None ⇒ bad shape), `main(argv) -> int`, `guarded(argv) -> int`, `sys.exit(guarded(sys.argv[1:]))`).
- Create: `tests/core/backend/boards/test_board_titles.py` — T1–T16.

**Suggested tasks** (each ends green on `bash tests/run.sh`):
1. Usage + RootMissing + the `brd tree` call (argv, cwd, stdin, BrdMissing) + success
   flattening + one-line `run()` helper — T1–T6, T9, T12–T14.
2. Envelope passthrough and BrdBadOutput validation — T7, T8, T10, T11.
3. `guarded` catch-all and timeout — T15, T16.

Strict TDD: each test written and seen failing before the code that passes it.
Verification: `bash /home/mtts/.local/state/agent-manager/verify/vfy-opm.sh` (runs
`bash tests/run.sh`). No linter or type checker is configured.

---

## Global Constraints

- Path and invocation: `core/backend/boards/board-titles.py ROOT` — exactly one argument, non-empty, not starting with `-`.
- Runs `brd tree` as an argv list `["brd", "tree"]`, `cwd=ROOT`, stdin `/dev/null`, timeout `TIMEOUT_SECONDS = 30` (module constant); brd is looked up on `PATH`.
- Every path prints **exactly one line** to stdout: one JSON object, via `common.json_line.emit`. Nothing else goes to stdout.
- Exit codes: `0` success, `1` failure, `2` usage.
- Success: `{"ok": true, "titles": {id: title}}` — top-level keys exactly `ok` and `titles`; every card at any depth; no `description`, `status`, `blocked_by`, `blockers`, `created_at`, `updated_at`, `children` anywhere.
- Own errors: `{"ok": false, "error": {"type": <type>, "message": <non-empty human sentence>}}`; types `Usage` (message `"usage: board-titles.py ROOT"`, exit 2), `RootMissing`, `BrdMissing`, `BrdBadOutput`, `HelperError` (message `"The board titles lookup failed: <reason>"`).
- brd's own `ok:false` envelope is re-emitted unchanged, exit 1, regardless of brd's exit code.
- It never writes; only the one `brd tree` process is started; brd's database is never read.
- `core/backend/**` imports only the Python stdlib and `core/backend/common` (enforced by `tests/architecture/test_layers.py`). `emit` must not be redefined (the architecture test `test_shared_python_helpers_are_defined_once` fails on a second `def emit(`).
- Docstrings and comments state the contract only, no narrative.
- The script is executable (git mode 100755), shebang `#!/usr/bin/env python3`.
- Verification gate: `bash /home/mtts/.local/state/agent-manager/verify/vfy-opm.sh` (runs `bash tests/run.sh`: pytest + QML tests). No linter or type checker.

**Running one test file:** the system `python3` has no pytest, so use
`uv run --with pytest python3 -m pytest tests/core/backend/boards/test_board_titles.py -q`
(add `-k <name>` to narrow it). Run every command from the repository root (the worktree).

## Review Focus

1. **The helper's own stdin is an open pipe that never sends EOF** (Quickshell `Process` may hold it open) — brd must get EOF at once from `/dev/null` and the helper must finish, not hang. Test: `test_brd_does_not_block_on_the_helpers_open_stdin` (Task 1).
2. **brd writes warnings to stderr while succeeding** — stderr is ignored; stdout still carries exactly the one success line. Test: `test_brd_stderr_is_ignored` (Task 1).
3. **ROOT given as a relative path** — resolved against the helper's working directory, brd runs in that directory. Test: `test_relative_root_is_resolved_against_the_helpers_cwd` (Task 1).
4. **A repeated id, and an empty-string title** — the last entry in pre-order wins; `""` is a valid title, not bad output. Tests: `test_repeated_id_keeps_the_last_in_pre_order` (Task 1), `test_empty_title_is_kept` (Task 2).
5. **`brd` on PATH but not executable** (broken install) — the exec fails with `PermissionError`, which is not `BrdMissing`; it must still give exactly one `HelperError` line, exit 1, never a traceback with an empty stdout. Test: `test_unexecutable_brd_is_helper_error` (Task 3).

---

## File Structure

- Create: `core/backend/boards/board-titles.py` — the helper. One responsibility: run `brd tree` in ROOT and print the `{id: title}` map (or the failure) as one JSON line. Pure `flatten_titles(data)` holds the card-walk; `main(argv)` holds argv/ROOT checks, the brd call and envelope handling; `guarded(argv)` is the catch-all.
- Create: `tests/core/backend/boards/test_board_titles.py` — every test (T1–T16 plus the Review Focus tests), black-box via subprocess against a fake `brd`, except the marked in-process ones.

No other file changes.

---

### Task 1: The helper — Usage, RootMissing, the `brd tree` call, BrdMissing, success flattening

**Files:**
- Create: `core/backend/boards/board-titles.py`
- Create: `tests/core/backend/boards/test_board_titles.py`

**Interfaces:**
- Consumes: `common.json_line.emit(payload, code=0) -> int` (prints `json.dumps(payload)` and a newline, returns `code`) from `core/backend/common/json_line.py`.
- Produces (later tasks rely on these exact names):
  - module constants `USAGE = "usage: board-titles.py ROOT"`, `TIMEOUT_SECONDS = 30`
  - `failure(kind: str, message: str, code: int = 1) -> int`
  - `parse_args(argv: list[str]) -> str | None`
  - `flatten_titles(data) -> dict | None` (Task 1: never None; Task 2 adds the None ⇒ bad shape rule)
  - `main(argv: list[str]) -> int` (argv excludes the program name)
  - test helpers in the test file: fixture `box`, `invoke(box, *args, stdin_text=None, extra_env=None, cwd=None) -> subprocess.CompletedProcess`, `run(box, *args, stdin_text=None, extra_env=None, cwd=None) -> tuple[int, dict]`, `calls(box) -> list[str]`, `set_out(box, payload)`, `files_under(path) -> dict[str, bytes]`, constants `SCRIPT`, `FAKE_BRD`.

- [ ] **Step 1: Write the failing tests**

Create `tests/core/backend/boards/test_board_titles.py` with exactly this content:

```python
"""board-titles.py against a fake `brd` on PATH: one `brd tree` in ROOT, one
JSON line on every path, {id: title} for every card at any depth."""
import json
import os
import stat
import subprocess
import sys

import pytest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "core", "backend", "boards", "board-titles.py")

# Logs its argv and cwd to $CALLS, copies its stdin to $STDIN_LOG, then (unless
# $BRD_SLEEP is set, when it becomes `sleep $BRD_SLEEP`) prints $BRD_OUT and
# exits ${BRD_EXIT:-0}.
FAKE_BRD = """#!/bin/sh
echo "brd $* (cwd=$(pwd))" >> "$CALLS"
cat > "$STDIN_LOG"
if [ -n "$BRD_SLEEP" ]; then exec sleep "$BRD_SLEEP"; fi
cat "$BRD_OUT"
exit "${BRD_EXIT:-0}"
"""

EMPTY_BOARD = {"ok": True, "data": []}


@pytest.fixture
def box(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    brd = bindir / "brd"
    brd.write_text(FAKE_BRD)
    brd.chmod(brd.stat().st_mode | stat.S_IEXEC)
    project = tmp_path / "my project"
    project.mkdir()
    calls_log = tmp_path / "calls.log"
    calls_log.write_text("")
    stdin_log = tmp_path / "stdin.log"
    stdin_log.write_text("")
    brd_out = tmp_path / "brd.out"
    box = {
        "env": {"PATH": "%s:/usr/bin:/bin" % bindir, "CALLS": str(calls_log),
                "STDIN_LOG": str(stdin_log), "BRD_OUT": str(brd_out)},
        "bin": bindir, "project": project, "calls": calls_log, "stdin": stdin_log,
        "out": brd_out, "tmp": tmp_path,
    }
    set_out(box, EMPTY_BOARD)
    return box


def set_out(box, payload):
    """What the fake brd prints: a str verbatim, anything else as JSON."""
    text = payload if isinstance(payload, str) else json.dumps(payload, ensure_ascii=False) + "\n"
    box["out"].write_text(text, encoding="utf-8")


def invoke(box, *args, stdin_text=None, extra_env=None, cwd=None):
    """Runs the helper; asserts it printed exactly one line."""
    env = dict(box["env"], **(extra_env or {}))
    feed = {"input": stdin_text} if stdin_text is not None else {"stdin": subprocess.DEVNULL}
    proc = subprocess.run([sys.executable, SCRIPT, *args], env=env, cwd=cwd, capture_output=True,
                          text=True, encoding="utf-8", timeout=60, **feed)
    assert len(proc.stdout.splitlines()) == 1, (proc.stdout, proc.stderr)
    return proc


def run(box, *args, stdin_text=None, extra_env=None, cwd=None):
    proc = invoke(box, *args, stdin_text=stdin_text, extra_env=extra_env, cwd=cwd)
    return proc.returncode, json.loads(proc.stdout)


def calls(box):
    return box["calls"].read_text().splitlines()


def files_under(path):
    """{relative path: bytes} for every file below `path`."""
    found = {}
    for dirpath, _dirs, names in os.walk(path):
        for name in names:
            full = os.path.join(dirpath, name)
            with open(full, "rb") as f:
                found[os.path.relpath(full, path)] = f.read()
    return found


def test_runs_brd_tree_once_in_root(box):
    code, out = run(box, str(box["project"]))
    assert code == 0
    assert out == {"ok": True, "titles": {}}
    assert calls(box) == ["brd tree (cwd=%s)" % box["project"].resolve()]


def test_brd_stdin_is_dev_null(box):
    code, out = run(box, str(box["project"]), stdin_text="LEAK\n")
    assert code == 0
    assert box["stdin"].read_text() == ""


def test_brd_does_not_block_on_the_helpers_open_stdin(box):
    # The helper's stdin is a pipe that never sends EOF; brd reads its own stdin
    # to the end, so it finishes only if that stdin is /dev/null.
    p = subprocess.Popen([sys.executable, SCRIPT, str(box["project"])], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=box["env"])
    try:
        code = p.wait(timeout=15)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait()
        pytest.fail("brd blocked reading the helper's stdin")
    finally:
        p.stdin.close()
    lines = p.stdout.read().splitlines()
    p.stdout.close()
    p.stderr.close()
    assert code == 0
    assert [json.loads(line) for line in lines] == [{"ok": True, "titles": {}}]


def test_flattens_nested_cards_at_any_depth(box):
    set_out(box, {"ok": True, "data": [
        {"id": "m1", "title": "Milestone one", "children": [
            {"id": "s1", "title": "Story one", "children": [
                {"id": "t1", "title": "Subtask one", "children": [
                    {"id": "x1", "title": "Sub-subtask one", "children": []},
                ]},
            ]},
        ]},
        {"id": "m2", "title": "Milestone two", "children": None},
        {"id": "m3", "title": "Milestone three"},
    ]})
    code, out = run(box, str(box["project"]))
    assert code == 0
    assert out == {"ok": True, "titles": {
        "m1": "Milestone one", "s1": "Story one", "t1": "Subtask one",
        "x1": "Sub-subtask one", "m2": "Milestone two", "m3": "Milestone three",
    }}


def test_drops_descriptions_and_every_other_field(box):
    def card(card_id, title, children):
        return {"id": card_id, "title": title, "description": "SECRET DESCRIPTION " + card_id,
                "status": "todo", "blocked_by": ["zz"], "blockers": ["yy"],
                "created_at": "2026-10-01T00:00:00Z", "updated_at": "2026-10-02T00:00:00Z",
                "children": children}
    set_out(box, {"ok": True, "data": [card("m1", "Milestone", [card("s1", "Story", [])])]})
    proc = invoke(box, str(box["project"]))
    assert proc.returncode == 0
    assert json.loads(proc.stdout) == {"ok": True, "titles": {"m1": "Milestone", "s1": "Story"}}
    for gone in ("SECRET", "description", "status", "blocked_by", "blockers",
                 "created_at", "updated_at", "children", "todo", "2026-10-0"):
        assert gone not in proc.stdout


def test_empty_board_gives_empty_titles(box):
    set_out(box, {"ok": True, "data": []})
    code, out = run(box, str(box["project"]))
    assert code == 0
    assert out == {"ok": True, "titles": {}}


def test_non_ascii_titles_round_trip(box):
    set_out(box, {"ok": True, "data": [{"id": "m1", "title": "Café — 日本", "children": []}]})
    code, out = run(box, str(box["project"]))
    assert code == 0
    assert out == {"ok": True, "titles": {"m1": "Café — 日本"}}


def test_repeated_id_keeps_the_last_in_pre_order(box):
    # Pre-order: m1, its child d, then m2, then m2's child d -- the last d wins.
    set_out(box, {"ok": True, "data": [
        {"id": "m1", "title": "First", "children": [{"id": "d", "title": "under m1", "children": []}]},
        {"id": "m2", "title": "Second", "children": [{"id": "d", "title": "under m2", "children": []}]},
    ]})
    code, out = run(box, str(box["project"]))
    assert code == 0
    assert out["titles"]["d"] == "under m2"


def test_brd_stderr_is_ignored(box):
    set_out(box, {"ok": True, "data": [{"id": "m1", "title": "One", "children": []}]})
    noisy = box["bin"] / "brd"
    noisy.write_text(FAKE_BRD.replace("#!/bin/sh\n", "#!/bin/sh\necho 'warning: something' >&2\n"))
    code, out = run(box, str(box["project"]))
    assert code == 0
    assert out == {"ok": True, "titles": {"m1": "One"}}


def test_relative_root_is_resolved_against_the_helpers_cwd(box):
    code, out = run(box, "my project", cwd=str(box["tmp"]))
    assert code == 0
    assert out == {"ok": True, "titles": {}}
    assert calls(box) == ["brd tree (cwd=%s)" % box["project"].resolve()]


def test_brd_missing(box):
    empty = box["tmp"] / "empty"
    empty.mkdir()
    code, out = run(box, str(box["project"]), extra_env={"PATH": str(empty)})
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "BrdMissing"
    assert out["error"]["message"]


@pytest.mark.parametrize("which", ["nonexistent", "regular file"])
def test_root_missing(box, which):
    root = box["tmp"] / "nope"
    if which == "regular file":
        root.write_text("not a directory")
    code, out = run(box, str(root))
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "RootMissing"
    assert str(root) in out["error"]["message"]
    assert calls(box) == []


@pytest.mark.parametrize("args", [[], ["a", "b"], [""], ["--help"]], ids=["none", "two", "empty", "dash"])
def test_usage(box, args):
    code, out = run(box, *args)
    assert code == 2
    assert out == {"ok": False, "error": {"type": "Usage", "message": "usage: board-titles.py ROOT"}}
    assert calls(box) == []


def test_never_writes(box):
    (box["project"] / "README").write_text("keep me")
    set_out(box, {"ok": True, "data": [{"id": "m1", "title": "One", "children": []}]})
    before = files_under(box["tmp"])
    code, out = run(box, str(box["project"]))
    assert code == 0
    after = files_under(box["tmp"])
    logs = {"calls.log", "stdin.log"}
    assert set(after) == set(before)
    assert {k: v for k, v in after.items() if k not in logs} == {k: v for k, v in before.items() if k not in logs}
    assert calls(box) == ["brd tree (cwd=%s)" % box["project"].resolve()]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/boards/test_board_titles.py -q`
Expected: every test FAILS — the script does not exist, so Python prints `can't open file ... board-titles.py` to stderr and stdout is empty, tripping `assert len(proc.stdout.splitlines()) == 1` (and `test_brd_does_not_block_on_the_helpers_open_stdin` fails on `code == 0`).

- [ ] **Step 3: Write the minimal implementation**

Create `core/backend/boards/board-titles.py` with exactly this content:

```python
#!/usr/bin/env python3
"""One project's card titles, from `brd tree`.

    board-titles.py ROOT

ROOT is non-empty and does not start with -; any other argv is a Usage error
(exit 2) and brd is not run. ROOT must be an existing directory, else
RootMissing and brd is not run. Runs `brd tree` once, as an argv list, with
cwd ROOT, stdin /dev/null and a TIMEOUT_SECONDS bound. Never writes; brd's
database is never read.

Prints exactly one JSON line on EVERY path:
{"ok": true, "titles": {<card id>: <title>}} for every card at any depth,
or {"ok": false, "error": {"type", "message"}} with type Usage, RootMissing or
BrdMissing. Exit 0 ok, 1 failure, 2 usage.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: board-titles.py ROOT"
TIMEOUT_SECONDS = 30


def failure(kind, message, code=1):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def parse_args(argv):
    """ROOT when argv is exactly one non-empty argument not starting with -;
    None otherwise."""
    if len(argv) == 1 and argv[0] and not argv[0].startswith("-"):
        return argv[0]
    return None


def flatten_titles(data):
    """{id: title} for every card in `data` and, recursively, in its
    `children`; a repeated id keeps the entry visited last in pre-order."""
    titles = {}
    stack = list(reversed(data))
    while stack:
        card = stack.pop()
        titles[card["id"]] = card["title"]
        stack.extend(reversed(card.get("children") or []))
    return titles


def main(argv):
    root = parse_args(argv)
    if root is None:
        return failure("Usage", USAGE, 2)
    if not os.path.isdir(root):
        return failure("RootMissing", "The project directory does not exist: " + root)
    try:
        proc = subprocess.run(["brd", "tree"], cwd=root, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, encoding="utf-8",
                              timeout=TIMEOUT_SECONDS)
    except FileNotFoundError:
        return failure("BrdMissing", "brd is not installed.")
    envelope = json.loads(proc.stdout)
    return emit({"ok": True, "titles": flatten_titles(envelope["data"])})


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

Then make it executable:

Run: `chmod +x core/backend/boards/board-titles.py`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/boards/test_board_titles.py -q`
Expected: all PASS.

- [ ] **Step 5: Run the full gate**

Run: `bash /home/mtts/.local/state/agent-manager/verify/vfy-opm.sh`
Expected: pytest reports no failures (including `tests/architecture/`), and no QML test prints `FAIL`; exit 0.

- [ ] **Step 6: Commit**

```bash
git add core/backend/boards/board-titles.py tests/core/backend/boards/test_board_titles.py
git ls-files -s core/backend/boards/board-titles.py   # must show mode 100755
git commit -m "feat(boards): board-titles.py prints one project's card titles"
```

---

### Task 2: brd's envelope passthrough and BrdBadOutput validation

**Files:**
- Modify: `core/backend/boards/board-titles.py` (module docstring, `flatten_titles`, the end of `main`)
- Test: `tests/core/backend/boards/test_board_titles.py` (append)

**Interfaces:**
- Consumes (from Task 1): `failure(kind, message, code=1) -> int`, `emit`, `main(argv) -> int`; test helpers `box`, `set_out(box, payload)`, `invoke(...)`, `run(...) -> (int, dict)`, `calls(box)`, `EMPTY_BOARD`.
- Produces: `flatten_titles(data) -> dict | None` — `None` when `data` is not a list, or any card at any depth is not an object, has an `id` that is not a non-empty string, a `title` that is not a string, or `children` present, not `null`, and not a list.

- [ ] **Step 1: Write the failing tests**

Append to `tests/core/backend/boards/test_board_titles.py`:

```python
NOT_FOUND = {"ok": False, "error": {"type": "ProjectNotFoundError",
                                    "message": "no registered project at or above /x; run `brd init` there"}}


def test_brd_envelope_is_passed_through_unchanged(box):
    set_out(box, NOT_FOUND)
    code, out = run(box, str(box["project"]), extra_env={"BRD_EXIT": "1"})
    assert code == 1
    assert out == NOT_FOUND


def test_brd_envelope_passthrough_ignores_brd_exit_code(box):
    set_out(box, NOT_FOUND)
    code, out = run(box, str(box["project"]), extra_env={"BRD_EXIT": "0"})
    assert code == 1
    assert out == NOT_FOUND


BAD_OUTPUTS = {
    "not json": "garbage <<>> output\n",
    "empty stdout": "",
    "json list": "[1, 2]\n",
    "json null": "null\n",
    "no ok": {"data": []},
    "ok string true": {"ok": "true", "data": []},
    "ok one": {"ok": 1, "data": []},
    "data missing": {"ok": True},
    "data object": {"ok": True, "data": {}},
    "card is a string": {"ok": True, "data": ["m1"]},
    "card without id": {"ok": True, "data": [{"title": "No id", "children": []}]},
    "id is a number": {"ok": True, "data": [{"id": 5, "title": "Five", "children": []}]},
    "id empty": {"ok": True, "data": [{"id": "", "title": "Blank", "children": []}]},
    "title null": {"ok": True, "data": [{"id": "m1", "title": None, "children": []}]},
    "title missing": {"ok": True, "data": [{"id": "m1", "children": []}]},
    "children object two levels down": {"ok": True, "data": [
        {"id": "m1", "title": "M", "children": [
            {"id": "s1", "title": "S", "children": [
                {"id": "t1", "title": "T", "children": {}},
            ]},
        ]},
    ]},
}


@pytest.mark.parametrize("name", list(BAD_OUTPUTS))
def test_bad_output(box, name):
    set_out(box, BAD_OUTPUTS[name])
    code, out = run(box, str(box["project"]))
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "BrdBadOutput"
    assert out["error"]["message"]
    assert "garbage" not in out["error"]["message"]
    assert "titles" not in out


def test_ok_envelope_with_nonzero_exit_is_bad_output(box):
    set_out(box, {"ok": True, "data": [{"id": "m1", "title": "One", "children": []}]})
    code, out = run(box, str(box["project"]), extra_env={"BRD_EXIT": "3"})
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "BrdBadOutput"
    assert out["error"]["message"]


def test_empty_title_is_kept(box):
    set_out(box, {"ok": True, "data": [{"id": "m1", "title": "", "children": []}]})
    code, out = run(box, str(box["project"]))
    assert code == 0
    assert out == {"ok": True, "titles": {"m1": ""}}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/boards/test_board_titles.py -q -k "envelope or bad_output or empty_title"`
Expected: every new test FAILS except `test_empty_title_is_kept`, which already passes (it is a guard that the validation added next must not reject `""`). The failures are of two kinds: a traceback with empty stdout (`json.loads` / `envelope["data"]` / `card["id"]` raising — caught by the one-line assertion in `invoke`), or exit 0 with a success line where `code == 1` was expected (`ok: "true"`, `ok: 1`, no `ok`, `data: {}`, `id: 5`, `id: ""`, `title: null`, `children: {}`, nonzero exit with `ok: true`).

- [ ] **Step 3: Write the implementation**

In `core/backend/boards/board-titles.py`, replace the whole `flatten_titles` function with:

```python
def flatten_titles(data):
    """{id: title} for every card in `data` and, recursively, in its
    `children`; a repeated id keeps the entry visited last in pre-order.
    None when `data` is not a list or any card is not an object with a
    non-empty string id, a string title, and children absent, null or a list."""
    if not isinstance(data, list):
        return None
    titles = {}
    stack = list(reversed(data))
    while stack:
        card = stack.pop()
        if not isinstance(card, dict):
            return None
        card_id, title, children = card.get("id"), card.get("title"), card.get("children")
        if not (isinstance(card_id, str) and card_id) or not isinstance(title, str):
            return None
        if children is None:
            children = []
        if not isinstance(children, list):
            return None
        titles[card_id] = title
        stack.extend(reversed(children))
    return titles
```

In `main`, replace these two lines:

```python
    envelope = json.loads(proc.stdout)
    return emit({"ok": True, "titles": flatten_titles(envelope["data"])})
```

with:

```python
    try:
        envelope = json.loads(proc.stdout)
    except ValueError:
        return failure("BrdBadOutput", "brd tree did not print JSON (exit %d)." % proc.returncode)
    if not isinstance(envelope, dict):
        return failure("BrdBadOutput", "brd tree printed JSON that is not an object.")
    if envelope.get("ok") is False:
        return emit(envelope, 1)
    if envelope.get("ok") is not True:
        return failure("BrdBadOutput", "brd tree printed an envelope whose ok is neither true nor false.")
    if proc.returncode != 0:
        return failure("BrdBadOutput", "brd tree reported ok but exited with code %d." % proc.returncode)
    titles = flatten_titles(envelope.get("data"))
    if titles is None:
        return failure("BrdBadOutput", "brd tree printed cards that are not in the expected shape.")
    return emit({"ok": True, "titles": titles})
```

In the module docstring, replace:

```
or {"ok": false, "error": {"type", "message"}} with type Usage, RootMissing or
BrdMissing. Exit 0 ok, 1 failure, 2 usage.
```

with:

```
or brd's own ok:false envelope unchanged, whatever brd's exit code,
or {"ok": false, "error": {"type", "message"}} with type Usage, RootMissing,
BrdMissing or BrdBadOutput (stdout not a JSON object; ok neither true nor
false; ok true with a non-zero exit; data not a list; a card at any depth not
an object, its id not a non-empty string, its title not a string, or its
children present, not null and not a list). Exit 0 ok, 1 failure, 2 usage.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/boards/test_board_titles.py -q`
Expected: all PASS (Task 1's tests included).

- [ ] **Step 5: Run the full gate**

Run: `bash /home/mtts/.local/state/agent-manager/verify/vfy-opm.sh`
Expected: no pytest failures, no QML `FAIL`; exit 0.

- [ ] **Step 6: Commit**

```bash
git add core/backend/boards/board-titles.py tests/core/backend/boards/test_board_titles.py
git commit -m "feat(boards): board-titles.py passes brd envelopes through and rejects bad output"
```

---

### Task 3: `guarded` catch-all — timeout and any unexpected exception give one HelperError line

**Files:**
- Modify: `core/backend/boards/board-titles.py` (module docstring; add `guarded`; the `__main__` line)
- Test: `tests/core/backend/boards/test_board_titles.py` (append; add `import importlib.util` at the top)

**Interfaces:**
- Consumes (from Tasks 1–2): `failure`, `main(argv) -> int`, `TIMEOUT_SECONDS` (read by `main` at call time, so patching the module attribute shortens the timeout); test helpers `box`, `run`, `SCRIPT`.
- Produces: `guarded(argv: list[str]) -> int` — returns `main(argv)`; re-raises `SystemExit`; any other exception (including `subprocess.TimeoutExpired` from brd running past `TIMEOUT_SECONDS`, and `PermissionError`) becomes `failure("HelperError", "The board titles lookup failed: " + reason)` where `reason` is `str(e)` or, when empty, the exception's class name. The script entry point becomes `sys.exit(guarded(sys.argv[1:]))`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/backend/boards/test_board_titles.py`, change the import block at the top from:

```python
import json
import os
```

to:

```python
import importlib.util
import json
import os
```

Then append:

```python
def load_helper():
    """The script as a module (its name has a hyphen, so no plain import)."""
    spec = importlib.util.spec_from_file_location("board_titles", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def one_line(capsys):
    lines = capsys.readouterr().out.splitlines()
    assert len(lines) == 1, lines
    return json.loads(lines[0])


def test_timeout_is_helper_error(box, monkeypatch, capsys):
    # In-process: a brd that runs past TIMEOUT_SECONDS (shortened here so the
    # test does not wait the real 30 s) is cut off and reported as HelperError.
    helper = load_helper()
    monkeypatch.setattr(helper, "TIMEOUT_SECONDS", 0.5)
    for key, value in dict(box["env"], BRD_SLEEP="10").items():
        monkeypatch.setenv(key, value)
    code = helper.guarded([str(box["project"])])
    out = one_line(capsys)
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The board titles lookup failed: ")
    assert "timed out" in out["error"]["message"]


def test_unexpected_exception_is_helper_error(box, monkeypatch, capsys):
    # In-process: no external input makes valid code raise, so the brd call is
    # replaced with one that does.
    helper = load_helper()

    def boom(*args, **kwargs):
        raise RuntimeError("boom")

    monkeypatch.setattr(helper.subprocess, "run", boom)
    code = helper.guarded([str(box["project"])])
    out = one_line(capsys)
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"] == "The board titles lookup failed: boom"


def test_unexecutable_brd_is_helper_error(box):
    brd = box["bin"] / "brd"
    brd.chmod(0o644)
    code, out = run(box, str(box["project"]), extra_env={"PATH": str(box["bin"])})
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The board titles lookup failed: ")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/boards/test_board_titles.py -q -k "helper_error"`
Expected: all three FAIL — the two in-process tests with `AttributeError: module 'board_titles' has no attribute 'guarded'`; `test_unexecutable_brd_is_helper_error` because the uncaught `PermissionError` leaves stdout empty, tripping the one-line assertion in `invoke`.

- [ ] **Step 3: Write the implementation**

In `core/backend/boards/board-titles.py`, add this function directly above the `if __name__ == "__main__":` line:

```python
def guarded(argv):
    """main(argv), except that any exception but SystemExit - a brd tree past
    TIMEOUT_SECONDS, a brd that cannot start - is a HelperError line."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The board titles lookup failed: " + reason)
```

Replace the entry point:

```python
if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

with:

```python
if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
```

In the module docstring, replace:

```
or {"ok": false, "error": {"type", "message"}} with type Usage, RootMissing,
BrdMissing or BrdBadOutput (stdout not a JSON object; ok neither true nor
```

with:

```
or {"ok": false, "error": {"type", "message"}} with type Usage, RootMissing,
BrdMissing, HelperError (brd tree timed out, or any other unexpected
failure) or BrdBadOutput (stdout not a JSON object; ok neither true nor
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/boards/test_board_titles.py -q`
Expected: all PASS. `test_timeout_is_helper_error` takes about half a second (the fake `exec`s `sleep`, so the kill on timeout ends it and the pipe closes).

- [ ] **Step 5: Run the full gate**

Run: `bash /home/mtts/.local/state/agent-manager/verify/vfy-opm.sh`
Expected: no pytest failures, no QML `FAIL`; exit 0.

- [ ] **Step 6: Commit**

```bash
git add core/backend/boards/board-titles.py tests/core/backend/boards/test_board_titles.py
git commit -m "feat(boards): board-titles.py reports a timeout or any crash as one HelperError line"
```

---

## Spec coverage check

| spec item | task / test |
|---|---|
| C1 path, invocation | Task 1 (file, `parse_args`) |
| C2 argv, cwd, stdin, timeout | T1, T2, Review Focus 1/3 (Task 1); T15 (Task 3) |
| C3 one line, all depths, descriptions dropped | T3, T4, T5, T6 (Task 1); one-line assertion in `invoke` on every subprocess test |
| C4 passthrough, BrdMissing, BrdBadOutput, RootMissing, HelperError, Usage | T7, T8, T10, T11 (Task 2); T9, T12, T13 (Task 1); T15, T16 (Task 3) |
| C5 never writes | T14 (Task 1) |
| C6 only the brd command | T1/T14 calls log; implementation never opens a database |
| C7 stdlib + `common` only | imports `json, os, subprocess, sys, common.json_line`; `tests/architecture/` in each gate run |
| C8 test list | T1–T16 all present |
| C9 contract-only docstrings | docstrings in every task |
| Decision order 1–7 | `main` order: Usage → RootMissing → brd run → passthrough → BrdBadOutput → success; `guarded` → HelperError |
| Duplicate id: last in pre-order wins | `test_repeated_id_keeps_the_last_in_pre_order` (Task 1) |
<!-- task-pipeline: validated -->
