# 1.1 Contract test: the committed am fixtures and the installed am agree — design

Card `f1f0e802`, a subtask of story `6596351c` ("Real am fixtures and contract
tests"). Parent spec: `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
(below: **parent**). Work breakdown item 1 (parent L321-323): this subtask is
"the contract test over the committed fixtures" only.

## Goal

A pytest module, `tests/contract/test_am_fixtures.py`, pins the shapes of the
nine committed real-am captures in `tests/fixtures/am/` (parent "Fixtures",
L231-284), and, when the installed `am` has a run for this repo, checks that
`am` still prints those shapes. A one-line change to
`tests/contract/test_am_shapes.py` lets the live hello carry schema 1 or 2
(parent "Both spellings, both schemas", L286-289). The suite is green on the
current code; nothing outside `tests/contract/` changes.

## Inherited constraints

| constraint | source |
|---|---|
| Key sets per level, listed in "What real am prints" | parent L18-65 |
| No top-level `subtasks` in `am status` data | parent L20-21, L279 |
| Status vocabularies: run/story/subtask/phase `pending, started, done, failed, escalated, stopped, cancelled`; attempt `started, ok, schema_invalid, gate_failed, harness_error` | parent L37-39 |
| `canceled` accepted as the second spelling of `cancelled` | parent L288-289 |
| The nine fixture files and their sources; `_note` / `_am_runs_row` on the e2e captures | parent L239-249 |
| Readers ignore keys starting with `_` | parent L251 |
| Fixtures are never edited (in-test edits only on a fresh copy, labelled, shape unchanged) | parent L265-267; card |
| Python reads fixtures with `json.load` | parent L269 |
| Contract test scope; live check in the main checkout (parent of `git rev-parse --git-common-dir`), read-only, `--repo-dir` the only option passed, never writes | parent L276-284 |
| Hello schema 1 or 2 accepted | parent L296-297 |
| `bash tests/run.sh` green, `tests/architecture` green (no duplicated components; icon glyph rules) | card; `docs/architecture.md` |
| Docstrings and comments state the contract only, no narrative | card |

## Observable behavior

### A. Fixture contract (always runs; no `am` needed)

Every test reads files under `tests/fixtures/am/` with `json.load` and never
writes to that directory. "Key set" below means `{k for k in obj if not
k.startswith("_")}` and must be **equal** (not a subset) to the listed set.

1. **Presence.** Each of `runs.json`, `status-started.json`, `status-done.json`,
   `status-escalated.json`, `status-escalated-integrate.json`,
   `status-done-integrate.json`, `watch-events.json`, `watch-hello.json`,
   `logs-attempt.json` exists and parses as JSON. A missing or malformed file
   fails a test that names the file.
2. **Envelopes.** Every fixture except `watch-hello.json` has key set
   `{ok, data}` with `ok is True`.
3. **`am runs` rows** (`runs.json` `data.runs[]`, at least one row, and the
   `_am_runs_row` of each e2e capture): key set
   `{id, workflow, repo_dir, base_branch, branch_prefix, status, started_at,
   milestone_id, card_id, lease, progress}` (parent L50-53).
   - `lease` is null or has key set `{pid, host, heartbeat_at, accepting, live}`;
     at least one row in `runs.json` has a non-null lease (parent L241), so the
     lease key set is actually exercised.
   - `progress` key set `{stories, subtasks, current}`; `stories` and
     `subtasks` each `{done, total}`; `current` is null or `{card, phase,
     attempt}`; at least one `runs.json` row has a non-null `current`.
   - `status` is in the run vocabulary.
4. **`am status` data** (each of the five `status-*.json`):
   - `data` key set `{run, stories, rows, control, integrity}`; `"subtasks" not
     in data` is asserted explicitly as its own check (parent L21).
   - `run` key set `{id, workflow, repo_dir, base_branch, branch_prefix,
     status, started_at}` (no `milestone_id`, parent L23-24).
   - each `stories[]` item `{card_id, title, level, status, tip_branch,
     subtasks}`; each subtask `{card_id, branch, base_branch, status,
     worktree_path, phases}`; each phase `{name, kind, status, started_at,
     ended_at, detail, attempts}`; each attempt `{n, status, dispatch,
     exit_code, duration, prompt_path, result_path, stdout_path}` (parent
     L25-32). Every level is walked across every story, subtask and phase, not
     only the first item. Across the five fixtures together, at least one
     attempt is reached (so the attempt key set is exercised).
   - each `rows[]` item `{story, subtask, phase, attempt, state}` (parent L33).
   - `control` key set `{lease, requests, claims}`; `control.lease` is null or
     `{pid, host, heartbeat_at, accepting, live, acquired_at}` (parent L45-46);
     `status-started.json` has a non-null `control.lease`. `requests` and
     `claims` are lists. Request items are not key-pinned: no capture contains
     one (all five have `requests: []`).
   - `integrity` is present (part of the `data` key set) but its inner keys are
     not pinned: the parent spec does not list them.
5. **Vocabularies.** Over all five status fixtures: `run.status`, every
   story, subtask and phase `status` is in `{pending, started, done, failed,
   escalated, stopped, cancelled, canceled}`; every attempt `status` is in
   `{started, ok, schema_invalid, gate_failed, harness_error}`. `rows[].state`
   is not checked against one vocabulary (it mixes both, parent L35-36). Every
   `runs.json` row and `_am_runs_row` `status` is in the run vocabulary.
6. **`am logs` data** (`logs-attempt.json`): `data` key set `{run_id, story_id,
   card, phase, attempt, status, exit_code, artifacts}`; `artifacts` key set
   `{prompt, result, stdout, stderr}`; each artifact `{path, present, text}`;
   no `data.stdout` (implied by the exact key set; parent L55-58).
7. **Watch events** (`watch-events.json`): `data` key set `{events}`, at least
   one event; every event key set `{seq, ts, run_id, event, story, card,
   phase, attempt, payload}` (parent L64-65).
8. **Hello** (`watch-hello.json`): top-level key set (ignoring `_`)
   `{schema_1, schema_2}`; each hello key set `{event, schema, am, runs_dir}`;
   `schema_1["schema"] == 1`, `schema_2["schema"] == 2`, `event == "watch"` on
   both (parent L62, L248).
9. **`_note` placement.** `_note` is a key of exactly these files:
   `status-escalated.json`, `status-escalated-integrate.json`,
   `status-done-integrate.json`, `watch-events.json`, `watch-hello.json`; it is
   absent from `runs.json`, `status-started.json`, `status-done.json`,
   `logs-attempt.json`. `_am_runs_row` is a key of exactly the three e2e
   captures (parent L244-246).

### B. Live check (read-only; may skip)

1. **Main checkout.** `MAIN = Path(git rev-parse --path-format=absolute
   --git-common-dir).parent`, run from the repository the test file lives in.
2. **Skip, never fail, when:** `am` is not on `PATH`; `git` fails or is absent;
   `am runs --repo-dir MAIN` exits non-zero or prints no `data.runs` rows. Each
   skip reason names its cause.
3. **Commands.** Exactly `am runs --repo-dir MAIN` and `am status <id>
   --repo-dir MAIN`, where `<id>` is the row with the greatest `started_at`
   (newest). Each call has a timeout (30 s, as `test_am_shapes.py`'s
   `AM_TIMEOUT`); a timeout fails the test. No other option is passed, nothing
   is written, `HOME`/XDG are not overridden (it reads the user's real runs).
   A non-zero exit of `am status` for a listed run fails the test.
4. **Same key sets.** Every live `am runs` row, its non-null `lease`, its
   `progress` (and non-null `current`), and the live `am status` data at every
   level listed in A.4 (data, run, story, subtask, phase, attempt, row,
   control, non-null control lease) has the same key set as A.3/A.4 pin.
   - **Allowance: `story_id`.** The installed am already prints `story_id` on
     every `am runs` row and on `am status` `data.run` (verified 2026-10-05:
     12 and 8 keys). It belongs to story-level dispatch
     (`2026-10-05-dispatch-story-level-design.md` L64-67), postdates the
     fixtures, and the fixtures may not be edited. The live check accepts, at
     those two levels only, the pinned set or the pinned set plus `story_id`.
     Any other extra or missing key at any level fails, naming the level and
     the difference.
   - The live statuses are checked against the A.5 vocabularies.
5. The live check shares the expected key sets with part A (one definition per
   level in the module), so the fixtures and the installed am are compared
   against the same constants.

### C. `test_am_shapes.py` hello

`tests/contract/test_am_shapes.py:159` changes from `hello["schema"] == 1` to
`hello["schema"] in (1, 2)`. Nothing else in that file changes.

## Tests (the deliverable)

All live in `tests/contract/` (pytest tier "contract": they pin the external
`am` program's output and the captures of it, not plugin code; they run under
`python3 -m pytest tests` via `tests/run.sh`). No QML tier: nothing here is
QML. No unit tier: there is no plugin code under test.

| test | tier / why |
|---|---|
| `test_every_fixture_exists_and_parses` (parametrized over the nine names) | contract: A.1, a missing capture must fail by name |
| `test_envelopes_are_ok_data` | contract: A.2 |
| `test_runs_rows_key_sets` (runs.json rows + each `_am_runs_row`; lease, progress, current) | contract: A.3 |
| `test_status_data_has_no_top_level_subtasks` (parametrized over five) | contract: A.4, the bug the parent spec exists for |
| `test_status_key_sets_at_every_level` (parametrized over five) | contract: A.4 |
| `test_status_vocabularies` (parametrized over five; plus runs rows) | contract: A.5 |
| `test_logs_key_sets` | contract: A.6 |
| `test_watch_event_key_sets` | contract: A.7 |
| `test_hello_key_sets_and_schemas` | contract: A.8 |
| `test_note_is_on_exactly_the_annotated_captures` | contract: A.9 |
| `test_installed_am_prints_the_fixture_key_sets` | contract, live: B; skips per B.2 |
| `test_watch_all_follow_prints_a_hello_line_then_journal_lines` (existing, edited) | contract: C |

TDD order: each test is written and run before the next; on this codebase they
are green at once (they pin am, not plugin code, parent L321). To prove each
assertion bites, the implementer runs it once against a **mutated copy** of the
fixture made inside a throwaway check (e.g. an extra key, a `subtasks` key, a
status `bogus`) and sees it fail — never by editing a committed fixture — and
does not commit that check.

## Failure messages

Every key-set assertion reports the fixture file (or `live am runs` / `live am
status <id>`), the level (e.g. `stories[1].subtasks[0].phases[2]`), and the
missing and extra keys.

## Out of scope

- Editing any file in `tests/fixtures/am/` (never).
- `tests/helpers/amFixtures.js` and `QML_XHR_ALLOW_FILE_READ` in `tests/run.sh`
  (sibling: "the QML fixture loader").
- The helpers' fake am serving the fixtures (sibling).
- Any plugin code: `runs.js` (`normalizeRun`, `rollup`, `runProgress`,
  `escalationReason`, `glyphStateOf`), `runs-*.py`, `run-control.py`,
  `RunStore`, screens — parent work items 2-4.
- Pinning `integrity`'s inner keys, `control.requests[]` item keys, or
  `rows[].state` values.
- Adding `story_id` to any expected set or fixture beyond the live allowance.
- Docs (parent work item 5).

## Plan handoff notes

- One new file, one one-line edit. Key-set constants are module-level
  frozensets in `test_am_fixtures.py`; reuse nothing by copy from other test
  modules (architecture test forbids duplicated helpers). The `EVENT_KEYS`
  constant in `test_am_shapes.py` may be imported or restated; restating a
  data constant is not a duplicated helper, importing between test modules is
  avoided (no package `__init__` in `tests/contract`).
- A single walker helper yields `(where, obj)` pairs per level for a status
  `data`, used by both the fixture tests and the live test.
- Module docstring states the contract (what is pinned, where the live check
  runs, that it is read-only and skips), in the style of
  `test_am_shapes.py`'s docstring.
- Verification: `python3 -m pytest tests/contract -q`, then `bash tests/run.sh`.

---

# 1.1 Contract test: am fixtures and the installed am agree — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pytest module `tests/contract/test_am_fixtures.py` pins the key sets and status vocabularies of the nine committed am captures in `tests/fixtures/am/`, checks that the installed `am` still prints them for this repo's main checkout, and `tests/contract/test_am_shapes.py` accepts a hello of schema 1 or 2.

**Architecture:** One new test module. Module-level frozensets hold one expected key set per level; two walkers (`run_row_levels`, `status_levels`) yield `(where, obj, expected)` for every object at every level, and one assertion helper (`assert_keys`) compares key sets ignoring `_`-prefixed keys and reports source, level, missing and extra keys. The fixture tests and the live test share the same walkers and constants; the live test only adds the `story_id` allowance on two levels. A one-line edit in `test_am_shapes.py`.

**Tech Stack:** Python 3, pytest, `json`, `subprocess`; the external `am` CLI (agent-manager) and `git`.

**Spec:** `docs/superpowers/specs/1-1-contract-test-the-f1f0e802.md` (prepended above). Parent: `docs/superpowers/specs/2026-10-05-align-run-model-design.md`.

## Global Constraints

- Nothing outside `tests/contract/` changes. Only two files are touched: `tests/contract/test_am_fixtures.py` (new) and `tests/contract/test_am_shapes.py` (line 159 only).
- Never edit, rename, or write any file in `tests/fixtures/am/`. Fixtures are read with `json.load`.
- "Key set" = `{k for k in obj if not k.startswith("_")}`, compared for **equality** (not subset).
- Run/story/subtask/phase status vocabulary: `pending, started, done, failed, escalated, stopped, cancelled, canceled`. Attempt vocabulary: `started, ok, schema_invalid, gate_failed, harness_error`. `rows[].state` is not checked.
- Not pinned: `integrity` inner keys, `control.requests[]` item keys, `rows[].state` values.
- Live check: main checkout is `Path(git rev-parse --path-format=absolute --git-common-dir).parent`; only `am runs --repo-dir MAIN` and `am status <newest id> --repo-dir MAIN`; timeout 30 s per call (a timeout fails); no `HOME`/XDG override; never writes. Skip (never fail) when `am` is not on `PATH`, `git` fails/absent, `am runs` exits non-zero or has no rows; each skip names its cause. Non-zero `am status` for a listed run fails.
- Live allowance: `story_id` as the one extra key on an `am runs` row and on `am status` `data.run` only. Never add `story_id` to an expected set or a fixture.
- No imports between test modules (`tests/contract` has no `__init__.py`); do not define `emit`, `inside`, `write_atomic`, `split_frontmatter`, `frontmatter_of`.
- Docstrings and comments state the contract only, no narrative.
- Every key-set failure names the fixture file (or `live am runs` / `live am status <id>`), the level (e.g. `stories[1].subtasks[0].phases[2]`), and the missing and extra keys.
- Green gates: `python3 -m pytest tests/contract -q` and `bash tests/run.sh` (which includes `tests/architecture`).
- Bite checks (mutated copies) are throwaway scripts under `/tmp`; they are never committed.

**Running pytest here:** the system `python3` may have no pytest. If `python3 -m pytest` prints `No module named pytest`, use `uv run --with pytest python3 -m pytest ...` with the same arguments everywhere below.

## Review Focus

1. **A failure must be readable.** When a key set drifts, the message must say `<source> <level>: missing [...], extra [...]` — pinned by `test_assert_keys_names_source_level_missing_and_extra` (Task 1).
2. **A level that is `null` or not an object** (e.g. `progress: null` from a future am) must fail naming the level, not crash with `TypeError` — pinned by the same Task 1 test.
3. **`story_id` is accepted live on exactly two levels** (runs row, status run), and an extra `story_id` anywhere else still fails — pinned by `test_live_allowance_is_story_id_on_the_runs_row_and_status_run_only` (Task 5).
4. **A machine without `am`** (CI, a fresh clone) must skip the live check, never fail — pinned by `test_live_check_skips_when_am_is_not_on_path` (Task 5).
5. **Running from a linked worktree** (how this repo is developed) must still read the main checkout's runs, not the worktree's — pinned by `test_live_check_reads_the_main_checkout_not_a_worktree` (Task 5).

---

## File Structure

- Create `tests/contract/test_am_fixtures.py` — fixture contract + live check. Layout top to bottom: module docstring, imports, paths/name tuples, key-set constants, vocabularies, `LIVE_EXTRA`, helpers (`load`, `key_set`, `assert_keys`, then walkers/checkers added in Tasks 2–3), then tests in task order, then live helpers and live tests (Task 5).
- Modify `tests/contract/test_am_shapes.py:159` — hello schema 1 or 2.

Facts about the fixtures this plan relies on (verified 2026-10-05 against the committed files):
- `runs.json` has 2 rows: row 0 has a non-null `lease` and non-null `progress.current`; row 1 has both null.
- The three e2e captures (`status-escalated.json`, `status-escalated-integrate.json`, `status-done-integrate.json`) carry `_note` and `_am_runs_row`; `watch-events.json` and `watch-hello.json` carry `_note` only.
- `status-started.json` has a non-null `control.lease` (with `acquired_at`); the others have `control.lease: null`. All have `requests: []`.
- Not every phase has attempts (e.g. `status-done.json` `stories[0].subtasks[0].phases[0].attempts == []`); `phases[1]` does.
- The installed am (2026-10-05) prints `story_id` on runs rows and `data.run`, hello `schema` 1.

---

### Task 1: Module skeleton, key-set constants, `assert_keys`, presence and envelopes

**Files:**
- Create: `tests/contract/test_am_fixtures.py`
- Test: same file

**Interfaces:**
- Consumes: nothing.
- Produces (module-level, used by every later task):
  - Paths/tuples: `HERE: Path`, `FIXTURES: Path`, `AM_TIMEOUT = 30`, `FIXTURE_NAMES`, `STATUS_FIXTURES`, `E2E_FIXTURES`, `NOTED_FIXTURES` (tuples of str).
  - Key sets (frozenset): `ENVELOPE_KEYS, RUN_ROW_KEYS, RUN_LEASE_KEYS, PROGRESS_KEYS, COUNT_KEYS, CURRENT_KEYS, STATUS_DATA_KEYS, STATUS_RUN_KEYS, STORY_KEYS, SUBTASK_KEYS, PHASE_KEYS, ATTEMPT_KEYS, ROW_KEYS, CONTROL_KEYS, CONTROL_LEASE_KEYS, LOGS_KEYS, ARTIFACTS_KEYS, ARTIFACT_KEYS, WATCH_DATA_KEYS, EVENT_KEYS, HELLO_FILE_KEYS, HELLO_KEYS`.
  - Vocabularies (frozenset): `RUN_STATUSES`, `ATTEMPT_STATUSES`.
  - `LIVE_EXTRA: dict[frozenset, frozenset]` = `{RUN_ROW_KEYS: {"story_id"}, STATUS_RUN_KEYS: {"story_id"}}`.
  - `load(name: str) -> object` (json.load of `FIXTURES / name`).
  - `key_set(obj: dict) -> set[str]` (keys not starting with `_`).
  - `assert_keys(source: str, where: str, obj, expected: frozenset, extra_allowed: frozenset = frozenset()) -> None` — fails via `AssertionError` if `obj` is not a dict (`"<source> <where>: expected an object, got <repr>"`), else via `pytest.fail("<source> <where>: missing [sorted], extra [sorted]")` unless `key_set(obj)` equals `expected` or `expected | extra_allowed`.

- [ ] **Step 1: Write the module with constants, helpers, and the first tests**

Create `tests/contract/test_am_fixtures.py` with exactly:

```python
"""The committed am captures in tests/fixtures/am keep the shapes real am prints,
and the installed am still prints them.

Fixture contract: every capture is read with json.load and never written. Each
level has one exact key set (keys starting with "_" are annotations and are
ignored); status values come from am's run and attempt vocabularies. am status
data has no top-level "subtasks".

Live check: in the main checkout (the parent of git's common dir), am runs and
am status of the newest run must print the same key sets, with "story_id"
allowed as the one extra key on a runs row and on the status run. Read-only:
only --repo-dir is passed and the user's real runs are read, never written.
Skipped when am or git is absent or the checkout has no runs.
"""
import json
import shutil
import subprocess
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
FIXTURES = HERE.parent / "fixtures" / "am"
AM_TIMEOUT = 30

FIXTURE_NAMES = (
    "runs.json", "status-started.json", "status-done.json", "status-escalated.json",
    "status-escalated-integrate.json", "status-done-integrate.json", "watch-events.json",
    "watch-hello.json", "logs-attempt.json",
)
STATUS_FIXTURES = (
    "status-started.json", "status-done.json", "status-escalated.json",
    "status-escalated-integrate.json", "status-done-integrate.json",
)
E2E_FIXTURES = ("status-escalated.json", "status-escalated-integrate.json", "status-done-integrate.json")
NOTED_FIXTURES = E2E_FIXTURES + ("watch-events.json", "watch-hello.json")

ENVELOPE_KEYS = frozenset({"ok", "data"})
RUN_ROW_KEYS = frozenset({"id", "workflow", "repo_dir", "base_branch", "branch_prefix", "status",
                          "started_at", "milestone_id", "card_id", "lease", "progress"})
RUN_LEASE_KEYS = frozenset({"pid", "host", "heartbeat_at", "accepting", "live"})
PROGRESS_KEYS = frozenset({"stories", "subtasks", "current"})
COUNT_KEYS = frozenset({"done", "total"})
CURRENT_KEYS = frozenset({"card", "phase", "attempt"})
STATUS_DATA_KEYS = frozenset({"run", "stories", "rows", "control", "integrity"})
STATUS_RUN_KEYS = frozenset({"id", "workflow", "repo_dir", "base_branch", "branch_prefix", "status",
                             "started_at"})
STORY_KEYS = frozenset({"card_id", "title", "level", "status", "tip_branch", "subtasks"})
SUBTASK_KEYS = frozenset({"card_id", "branch", "base_branch", "status", "worktree_path", "phases"})
PHASE_KEYS = frozenset({"name", "kind", "status", "started_at", "ended_at", "detail", "attempts"})
ATTEMPT_KEYS = frozenset({"n", "status", "dispatch", "exit_code", "duration", "prompt_path",
                          "result_path", "stdout_path"})
ROW_KEYS = frozenset({"story", "subtask", "phase", "attempt", "state"})
CONTROL_KEYS = frozenset({"lease", "requests", "claims"})
CONTROL_LEASE_KEYS = RUN_LEASE_KEYS | {"acquired_at"}
LOGS_KEYS = frozenset({"run_id", "story_id", "card", "phase", "attempt", "status", "exit_code",
                       "artifacts"})
ARTIFACTS_KEYS = frozenset({"prompt", "result", "stdout", "stderr"})
ARTIFACT_KEYS = frozenset({"path", "present", "text"})
WATCH_DATA_KEYS = frozenset({"events"})
EVENT_KEYS = frozenset({"seq", "ts", "run_id", "event", "story", "card", "phase", "attempt", "payload"})
HELLO_FILE_KEYS = frozenset({"schema_1", "schema_2"})
HELLO_KEYS = frozenset({"event", "schema", "am", "runs_dir"})

RUN_STATUSES = frozenset({"pending", "started", "done", "failed", "escalated", "stopped",
                          "cancelled", "canceled"})
ATTEMPT_STATUSES = frozenset({"started", "ok", "schema_invalid", "gate_failed", "harness_error"})

# The installed am prints story_id on these two levels only; the captures predate it.
LIVE_EXTRA = {RUN_ROW_KEYS: frozenset({"story_id"}), STATUS_RUN_KEYS: frozenset({"story_id"})}


def load(name):
    with open(FIXTURES / name, encoding="utf-8") as fh:
        return json.load(fh)


def key_set(obj):
    return {key for key in obj if not key.startswith("_")}


def assert_keys(source, where, obj, expected, extra_allowed=frozenset()):
    assert isinstance(obj, dict), f"{source} {where}: expected an object, got {obj!r}"
    keys = key_set(obj)
    if keys == expected or keys == expected | extra_allowed:
        return
    missing = sorted(expected - keys)
    extra = sorted(keys - expected)
    pytest.fail(f"{source} {where}: missing {missing}, extra {extra}")


@pytest.mark.parametrize("name", FIXTURE_NAMES)
def test_every_fixture_exists_and_parses(name):
    path = FIXTURES / name
    assert path.is_file(), f"{name}: missing from {FIXTURES}"
    try:
        load(name)
    except json.JSONDecodeError as err:
        pytest.fail(f"{name}: not JSON: {err}")


@pytest.mark.parametrize("name", [n for n in FIXTURE_NAMES if n != "watch-hello.json"])
def test_envelopes_are_ok_data(name):
    payload = load(name)
    assert_keys(name, "envelope", payload, ENVELOPE_KEYS)
    assert payload["ok"] is True, f"{name}: ok is {payload['ok']!r}"


def test_assert_keys_names_source_level_missing_and_extra():
    with pytest.raises(pytest.fail.Exception) as failure:
        assert_keys("x.json", "runs[0].progress", {"stories": 1, "extra": 2, "_note": 3}, PROGRESS_KEYS)
    assert str(failure.value) == "x.json runs[0].progress: missing ['current', 'subtasks'], extra ['extra']"
    with pytest.raises(AssertionError, match=r"x\.json runs\[0\]\.progress: expected an object, got None"):
        assert_keys("x.json", "runs[0].progress", None, PROGRESS_KEYS)
```

Note: `shutil` and `subprocess` are imported now and used in Task 5; that is intentional so the import block is written once.

- [ ] **Step 2: Run the tests**

Run: `python3 -m pytest tests/contract/test_am_fixtures.py -q`
Expected: `18 passed` (9 presence + 8 envelopes + 1 message test). These pin am's output, which already matches, so they are green at once; Step 3 proves they bite.

- [ ] **Step 3: Prove the presence and envelope checks bite (throwaway, not committed)**

Write `/tmp/bite_task1.py`:

```python
import importlib.util, json, pathlib, shutil, sys, tempfile
import pytest

spec = importlib.util.spec_from_file_location("m", "tests/contract/test_am_fixtures.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def bites(label, fn):
    try:
        fn()
    except (AssertionError, pytest.fail.Exception) as err:
        print("BITES", label, "->", str(err).splitlines()[0][:140])
        return
    print("MISSED", label)
    sys.exit(1)

tmp = pathlib.Path(tempfile.mkdtemp())
shutil.copytree(m.FIXTURES, tmp / "am")
m.FIXTURES = tmp / "am"
(tmp / "am" / "runs.json").unlink()
bites("missing runs.json", lambda: m.test_every_fixture_exists_and_parses("runs.json"))
(tmp / "am" / "logs-attempt.json").write_text("{not json", encoding="utf-8")
bites("malformed logs-attempt.json", lambda: m.test_every_fixture_exists_and_parses("logs-attempt.json"))
payload = json.loads((tmp / "am" / "status-done.json").read_text())
payload["ok"] = False
(tmp / "am" / "status-done.json").write_text(json.dumps(payload))
bites("ok false", lambda: m.test_envelopes_are_ok_data("status-done.json"))
payload["ok"] = True
payload["extra"] = 1
(tmp / "am" / "status-done.json").write_text(json.dumps(payload))
bites("extra envelope key", lambda: m.test_envelopes_are_ok_data("status-done.json"))
shutil.rmtree(tmp)
```

Run: `python3 /tmp/bite_task1.py` (or `uv run --with pytest python3 /tmp/bite_task1.py`) from the repo root.
Expected: four `BITES` lines, exit 0. Then `rm /tmp/bite_task1.py`. Confirm `git status --short tests/fixtures` prints nothing.

- [ ] **Step 4: Commit**

```bash
git add tests/contract/test_am_fixtures.py
git commit -m "test(contract): pin am fixture presence, envelopes and key-set failure messages"
```

---

### Task 2: `am runs` rows (A.3) and their statuses (A.5)

**Files:**
- Modify: `tests/contract/test_am_fixtures.py` (helpers inserted directly above `@pytest.mark.parametrize("name", FIXTURE_NAMES)`; tests appended at the end of the file)

**Interfaces:**
- Consumes: `RUN_ROW_KEYS, RUN_LEASE_KEYS, PROGRESS_KEYS, COUNT_KEYS, CURRENT_KEYS, RUN_STATUSES, E2E_FIXTURES, load, assert_keys` (Task 1).
- Produces:
  - `run_row_levels(where: str, row: dict) -> Iterator[tuple[str, object, frozenset]]` — yields the row, its non-null `lease`, `progress`, `progress.stories`, `progress.subtasks`, non-null `progress.current`.
  - `check_runs_rows(source: str, rows: list[dict], extra_allowed: dict[frozenset, frozenset] | None = None) -> None` — key sets of every level of every row (where `runs[i]` is the level prefix) plus `row["status"] in RUN_STATUSES`. Task 5 calls it with `LIVE_EXTRA`.
  - `runs_rows_of_fixtures() -> list[tuple[str, dict]]` — `("runs.json runs[i]", row)` for each runs.json row, then `("<e2e name> _am_runs_row", row)` for each of `E2E_FIXTURES`.

- [ ] **Step 1: Add the helpers**

Insert directly above the line `@pytest.mark.parametrize("name", FIXTURE_NAMES)`:

```python
def run_row_levels(where, row):
    """(where, obj, expected key set) for an am runs row and every object inside it."""
    yield where, row, RUN_ROW_KEYS
    if row.get("lease") is not None:
        yield f"{where}.lease", row["lease"], RUN_LEASE_KEYS
    progress = row.get("progress")
    yield f"{where}.progress", progress, PROGRESS_KEYS
    if isinstance(progress, dict):
        yield f"{where}.progress.stories", progress.get("stories"), COUNT_KEYS
        yield f"{where}.progress.subtasks", progress.get("subtasks"), COUNT_KEYS
        if progress.get("current") is not None:
            yield f"{where}.progress.current", progress["current"], CURRENT_KEYS


def check_runs_rows(source, rows, extra_allowed=None):
    """Every row's key sets and status; extra_allowed maps an expected set to keys also accepted."""
    for i, row in enumerate(rows):
        for where, obj, expected in run_row_levels(f"runs[{i}]", row):
            assert_keys(source, where, obj, expected, (extra_allowed or {}).get(expected, frozenset()))
        assert row["status"] in RUN_STATUSES, f"{source} runs[{i}].status: {row['status']!r}"


def runs_rows_of_fixtures():
    rows = [(f"runs.json runs[{i}]", row) for i, row in enumerate(load("runs.json")["data"]["runs"])]
    return rows + [(f"{name} _am_runs_row", load(name)["_am_runs_row"]) for name in E2E_FIXTURES]
```

- [ ] **Step 2: Append the tests**

Append at the end of the file:

```python


def test_runs_rows_key_sets():
    rows = load("runs.json")["data"]["runs"]
    assert rows, "runs.json: no data.runs rows"
    assert any(row["lease"] is not None for row in rows), "runs.json: no row has a lease"
    assert any(row["progress"]["current"] is not None for row in rows), \
        "runs.json: no row has a progress.current"
    for source, row in runs_rows_of_fixtures():
        check_runs_rows(source, [row])


def test_runs_row_statuses_are_in_the_run_vocabulary():
    for source, row in runs_rows_of_fixtures():
        assert row["status"] in RUN_STATUSES, f"{source}.status: {row['status']!r}"
```

- [ ] **Step 3: Run the tests**

Run: `python3 -m pytest tests/contract/test_am_fixtures.py -q`
Expected: `20 passed`.

- [ ] **Step 4: Prove the runs checks bite (throwaway, not committed)**

Write `/tmp/bite_task2.py`:

```python
import copy, importlib.util, sys
import pytest

spec = importlib.util.spec_from_file_location("m", "tests/contract/test_am_fixtures.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def bites(label, fn):
    try:
        fn()
    except (AssertionError, pytest.fail.Exception) as err:
        print("BITES", label, "->", str(err).splitlines()[0][:140])
        return
    print("MISSED", label)
    sys.exit(1)

fresh = lambda: copy.deepcopy(m.load("runs.json")["data"]["runs"])
r = fresh(); r[0]["extra"] = 1
bites("extra row key", lambda: m.check_runs_rows("mutated", r))
r = fresh(); r[0]["lease"]["x"] = 1
bites("extra lease key", lambda: m.check_runs_rows("mutated", r))
r = fresh(); del r[1]["progress"]["current"]
bites("missing progress.current", lambda: m.check_runs_rows("mutated", r))
r = fresh(); r[0]["progress"]["current"]["n"] = 1
bites("extra current key", lambda: m.check_runs_rows("mutated", r))
r = fresh(); r[0]["progress"]["stories"] = None
bites("null progress.stories", lambda: m.check_runs_rows("mutated", r))
r = fresh(); r[0]["status"] = "bogus"
bites("bogus status", lambda: m.check_runs_rows("mutated", r))
r = fresh(); r[0]["story_id"] = "x"
bites("story_id without allowance", lambda: m.check_runs_rows("mutated", r))
r = fresh(); r[0]["_anything"] = 1
m.check_runs_rows("mutated", r)
print("ACCEPTS _-prefixed key")
```

Run: `python3 /tmp/bite_task2.py` from the repo root.
Expected: seven `BITES` lines, then `ACCEPTS _-prefixed key`, exit 0. Then `rm /tmp/bite_task2.py`.

- [ ] **Step 5: Commit**

```bash
git add tests/contract/test_am_fixtures.py
git commit -m "test(contract): pin am runs row key sets, lease, progress and status"
```

---

### Task 3: `am status` data — no top-level subtasks, every level's key set, vocabularies (A.4, A.5)

**Files:**
- Modify: `tests/contract/test_am_fixtures.py` (helpers inserted directly above `@pytest.mark.parametrize("name", FIXTURE_NAMES)`, i.e. below `runs_rows_of_fixtures`; tests appended at the end)

**Interfaces:**
- Consumes: `STATUS_DATA_KEYS, STATUS_RUN_KEYS, STORY_KEYS, SUBTASK_KEYS, PHASE_KEYS, ATTEMPT_KEYS, ROW_KEYS, CONTROL_KEYS, CONTROL_LEASE_KEYS, RUN_STATUSES, ATTEMPT_STATUSES, STATUS_FIXTURES, load, assert_keys` (Task 1).
- Produces:
  - `status_levels(data: dict) -> Iterator[tuple[str, object, frozenset]]` — levels named `data`, `data.run`, `stories[s]`, `stories[s].subtasks[t]`, `stories[s].subtasks[t].phases[p]`, `...phases[p].attempts[a]`, `rows[r]`, `control`, `control.lease` (when non-null). Walks every item at every level.
  - `status_statuses(data: dict) -> Iterator[tuple[str, str, frozenset]]` — `(where, status, vocabulary)` for run, every story, subtask, phase (`RUN_STATUSES`) and attempt (`ATTEMPT_STATUSES`).
  - `check_status_data(source: str, data: dict, extra_allowed: dict[frozenset, frozenset] | None = None) -> None` — all `status_levels` key sets plus all `status_statuses` membership. Task 5 calls it with `LIVE_EXTRA`.

- [ ] **Step 1: Add the helpers**

Insert directly above the line `@pytest.mark.parametrize("name", FIXTURE_NAMES)`:

```python
def status_levels(data):
    """(where, obj, expected key set) for am status data and every level inside it."""
    yield "data", data, STATUS_DATA_KEYS
    yield "data.run", data.get("run"), STATUS_RUN_KEYS
    for s, story in enumerate(data.get("stories") or []):
        yield f"stories[{s}]", story, STORY_KEYS
        for t, subtask in enumerate(story.get("subtasks") or []):
            yield f"stories[{s}].subtasks[{t}]", subtask, SUBTASK_KEYS
            for p, phase in enumerate(subtask.get("phases") or []):
                where = f"stories[{s}].subtasks[{t}].phases[{p}]"
                yield where, phase, PHASE_KEYS
                for a, attempt in enumerate(phase.get("attempts") or []):
                    yield f"{where}.attempts[{a}]", attempt, ATTEMPT_KEYS
    for r, row in enumerate(data.get("rows") or []):
        yield f"rows[{r}]", row, ROW_KEYS
    control = data.get("control")
    yield "control", control, CONTROL_KEYS
    if isinstance(control, dict) and control.get("lease") is not None:
        yield "control.lease", control["lease"], CONTROL_LEASE_KEYS


def status_statuses(data):
    """(where, status, vocabulary) for the run and every story, subtask, phase and attempt."""
    yield "data.run.status", data["run"]["status"], RUN_STATUSES
    for s, story in enumerate(data["stories"]):
        yield f"stories[{s}].status", story["status"], RUN_STATUSES
        for t, subtask in enumerate(story["subtasks"]):
            yield f"stories[{s}].subtasks[{t}].status", subtask["status"], RUN_STATUSES
            for p, phase in enumerate(subtask["phases"]):
                where = f"stories[{s}].subtasks[{t}].phases[{p}]"
                yield f"{where}.status", phase["status"], RUN_STATUSES
                for a, attempt in enumerate(phase["attempts"]):
                    yield f"{where}.attempts[{a}].status", attempt["status"], ATTEMPT_STATUSES


def check_status_data(source, data, extra_allowed=None):
    """Every level's key set and every status of am status data."""
    for where, obj, expected in status_levels(data):
        assert_keys(source, where, obj, expected, (extra_allowed or {}).get(expected, frozenset()))
    for where, status, vocabulary in status_statuses(data):
        assert status in vocabulary, f"{source} {where}: {status!r} not in {sorted(vocabulary)}"
```

- [ ] **Step 2: Append the tests**

Append at the end of the file:

```python


@pytest.mark.parametrize("name", STATUS_FIXTURES)
def test_status_data_has_no_top_level_subtasks(name):
    assert "subtasks" not in load(name)["data"], f"{name}: data has a top-level subtasks"


@pytest.mark.parametrize("name", STATUS_FIXTURES)
def test_status_key_sets_at_every_level(name):
    data = load(name)["data"]
    for where, obj, expected in status_levels(data):
        assert_keys(name, where, obj, expected)
    assert isinstance(data["control"]["requests"], list), f"{name} control.requests: not a list"
    assert isinstance(data["control"]["claims"], list), f"{name} control.claims: not a list"


def test_status_fixtures_reach_attempts_and_a_control_lease():
    levels = [expected for name in STATUS_FIXTURES for _, _, expected in status_levels(load(name)["data"])]
    assert ATTEMPT_KEYS in levels, "no status fixture has an attempt"
    assert load("status-started.json")["data"]["control"]["lease"] is not None, \
        "status-started.json: control.lease is null"


@pytest.mark.parametrize("name", STATUS_FIXTURES)
def test_status_vocabularies(name):
    for where, status, vocabulary in status_statuses(load(name)["data"]):
        assert status in vocabulary, f"{name} {where}: {status!r} not in {sorted(vocabulary)}"
```

- [ ] **Step 3: Run the tests**

Run: `python3 -m pytest tests/contract/test_am_fixtures.py -q`
Expected: `36 passed` (20 + 5 + 5 + 1 + 5).

- [ ] **Step 4: Prove the status checks bite (throwaway, not committed)**

Write `/tmp/bite_task3.py`:

```python
import copy, importlib.util, sys
import pytest

spec = importlib.util.spec_from_file_location("m", "tests/contract/test_am_fixtures.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def bites(label, fn):
    try:
        fn()
    except (AssertionError, pytest.fail.Exception) as err:
        print("BITES", label, "->", str(err).splitlines()[0][:140])
        return
    print("MISSED", label)
    sys.exit(1)

fresh = lambda name="status-done.json": copy.deepcopy(m.load(name)["data"])
first_attempt = lambda d: next(ph["attempts"][0] for st in d["stories"] for sub in st["subtasks"]
                               for ph in sub["phases"] if ph["attempts"])
d = fresh(); d["subtasks"] = []
bites("top-level subtasks", lambda: m.check_status_data("mutated", d))
d = fresh(); d["run"]["milestone_id"] = "x"
bites("milestone_id on run", lambda: m.check_status_data("mutated", d))
d = fresh(); d["stories"][-1]["extra"] = 1
bites("extra key on last story", lambda: m.check_status_data("mutated", d))
d = fresh(); d["stories"][1]["subtasks"][0]["phases"][2]["bogus"] = 1
bites("extra phase key", lambda: m.check_status_data("mutated", d))
d = fresh(); del first_attempt(d)["stdout_path"]
bites("missing attempt key", lambda: m.check_status_data("mutated", d))
d = fresh(); d["rows"][-1]["extra"] = 1
bites("extra row key", lambda: m.check_status_data("mutated", d))
d = fresh("status-started.json"); d["control"]["lease"].pop("acquired_at")
bites("control lease without acquired_at", lambda: m.check_status_data("mutated", d))
d = fresh(); d["run"]["status"] = "bogus"
bites("run status bogus", lambda: m.check_status_data("mutated", d))
d = fresh(); d["stories"][0]["subtasks"][0]["phases"][0]["status"] = "ok"
bites("attempt word as phase status", lambda: m.check_status_data("mutated", d))
d = fresh(); first_attempt(d)["status"] = "done"
bites("phase word as attempt status", lambda: m.check_status_data("mutated", d))
d = fresh(); d["run"]["status"] = "canceled"
m.check_status_data("mutated", d)
print("ACCEPTS canceled")
d = fresh(); d["integrity"]["new_inner_key"] = 1
m.check_status_data("mutated", d)
print("ACCEPTS integrity inner keys")
```

Run: `python3 /tmp/bite_task3.py` from the repo root.
Expected: ten `BITES` lines, then `ACCEPTS canceled` and `ACCEPTS integrity inner keys`, exit 0. Then `rm /tmp/bite_task3.py`.

- [ ] **Step 5: Commit**

```bash
git add tests/contract/test_am_fixtures.py
git commit -m "test(contract): pin am status key sets at every level and status vocabularies"
```

---

### Task 4: `am logs`, watch events, hello, and `_note` placement (A.6–A.9)

**Files:**
- Modify: `tests/contract/test_am_fixtures.py` (tests appended at the end)

**Interfaces:**
- Consumes: `LOGS_KEYS, ARTIFACTS_KEYS, ARTIFACT_KEYS, WATCH_DATA_KEYS, EVENT_KEYS, HELLO_FILE_KEYS, HELLO_KEYS, FIXTURE_NAMES, NOTED_FIXTURES, E2E_FIXTURES, load, assert_keys` (Task 1).
- Produces: tests only.

- [ ] **Step 1: Append the tests**

Append at the end of the file:

```python


def test_logs_key_sets():
    data = load("logs-attempt.json")["data"]
    assert_keys("logs-attempt.json", "data", data, LOGS_KEYS)
    assert_keys("logs-attempt.json", "data.artifacts", data["artifacts"], ARTIFACTS_KEYS)
    for kind, artifact in data["artifacts"].items():
        assert_keys("logs-attempt.json", f"data.artifacts.{kind}", artifact, ARTIFACT_KEYS)


def test_watch_event_key_sets():
    data = load("watch-events.json")["data"]
    assert_keys("watch-events.json", "data", data, WATCH_DATA_KEYS)
    assert data["events"], "watch-events.json: no events"
    for i, event in enumerate(data["events"]):
        assert_keys("watch-events.json", f"events[{i}]", event, EVENT_KEYS)


def test_hello_key_sets_and_schemas():
    hellos = load("watch-hello.json")
    assert_keys("watch-hello.json", "top level", hellos, HELLO_FILE_KEYS)
    for key, schema in (("schema_1", 1), ("schema_2", 2)):
        hello = hellos[key]
        assert_keys("watch-hello.json", key, hello, HELLO_KEYS)
        assert hello["schema"] == schema, f"watch-hello.json {key}: schema {hello['schema']!r}"
        assert hello["event"] == "watch", f"watch-hello.json {key}: event {hello['event']!r}"


def test_note_is_on_exactly_the_annotated_captures():
    noted = sorted(name for name in FIXTURE_NAMES if "_note" in load(name))
    assert noted == sorted(NOTED_FIXTURES), noted
    with_row = sorted(name for name in FIXTURE_NAMES if "_am_runs_row" in load(name))
    assert with_row == sorted(E2E_FIXTURES), with_row
```

- [ ] **Step 2: Run the tests**

Run: `python3 -m pytest tests/contract/test_am_fixtures.py -q`
Expected: `40 passed`.

- [ ] **Step 3: Prove these checks bite (throwaway, not committed)**

Write `/tmp/bite_task4.py`:

```python
import importlib.util, json, pathlib, shutil, sys, tempfile
import pytest

spec = importlib.util.spec_from_file_location("m", "tests/contract/test_am_fixtures.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def bites(label, fn):
    try:
        fn()
    except (AssertionError, pytest.fail.Exception) as err:
        print("BITES", label, "->", str(err).splitlines()[0][:140])
        return
    print("MISSED", label)
    sys.exit(1)

tmp = pathlib.Path(tempfile.mkdtemp())
shutil.copytree(m.FIXTURES, tmp / "am")
m.FIXTURES = tmp / "am"

def mutate(name, change):
    path = tmp / "am" / name
    original = path.read_text()
    payload = json.loads(original)
    change(payload)
    path.write_text(json.dumps(payload))
    return lambda: path.write_text(original)

restore = mutate("logs-attempt.json", lambda p: p["data"].__setitem__("stdout", "x"))
bites("data.stdout on logs", m.test_logs_key_sets); restore()
restore = mutate("logs-attempt.json", lambda p: p["data"]["artifacts"]["stderr"].pop("present"))
bites("artifact missing present", m.test_logs_key_sets); restore()
restore = mutate("watch-events.json", lambda p: p["data"]["events"][-1].pop("story"))
bites("last event missing story", m.test_watch_event_key_sets); restore()
restore = mutate("watch-events.json", lambda p: p["data"].__setitem__("events", []))
bites("no events", m.test_watch_event_key_sets); restore()
restore = mutate("watch-hello.json", lambda p: p["schema_2"].__setitem__("schema", 1))
bites("schema_2 says 1", m.test_hello_key_sets_and_schemas); restore()
restore = mutate("watch-hello.json", lambda p: p.__setitem__("schema_3", {}))
bites("extra hello", m.test_hello_key_sets_and_schemas); restore()
restore = mutate("runs.json", lambda p: p.__setitem__("_note", "x"))
bites("_note on runs.json", m.test_note_is_on_exactly_the_annotated_captures); restore()
restore = mutate("watch-events.json", lambda p: p.pop("_note"))
bites("_note gone from watch-events.json", m.test_note_is_on_exactly_the_annotated_captures); restore()
shutil.rmtree(tmp)
```

Run: `python3 /tmp/bite_task4.py` from the repo root.
Expected: eight `BITES` lines, exit 0. Then `rm /tmp/bite_task4.py`. Confirm `git status --short tests/fixtures` prints nothing.

- [ ] **Step 4: Commit**

```bash
git add tests/contract/test_am_fixtures.py
git commit -m "test(contract): pin am logs, watch event and hello key sets and _note placement"
```

---

### Task 5: Live check against the installed am (B)

**Files:**
- Modify: `tests/contract/test_am_fixtures.py` (appended at the end)

**Interfaces:**
- Consumes: `HERE, AM_TIMEOUT, LIVE_EXTRA, RUN_ROW_KEYS, STATUS_RUN_KEYS, STORY_KEYS, assert_keys` (Task 1); `check_runs_rows` (Task 2); `check_status_data` (Task 3).
- Produces:
  - `git_main_checkout() -> Path | None` — parent of `git rev-parse --path-format=absolute --git-common-dir` run with `cwd=HERE`; `None` when git is absent, times out, exits non-zero or prints nothing.
  - `am_json(*args: str) -> tuple[int, str, str]` — `(returncode, stdout, stderr)` of `am *args`, timeout `AM_TIMEOUT` (a `subprocess.TimeoutExpired` propagates and fails the test). Inherits the real environment.
  - `test_installed_am_prints_the_fixture_key_sets()`.

- [ ] **Step 1: Write the Review Focus tests first (they fail: names undefined)**

Append at the end of the file:

```python


def test_live_allowance_is_story_id_on_the_runs_row_and_status_run_only():
    assert set(LIVE_EXTRA) == {RUN_ROW_KEYS, STATUS_RUN_KEYS}
    run = dict.fromkeys(STATUS_RUN_KEYS | {"story_id"})
    assert_keys("live", "data.run", run, STATUS_RUN_KEYS, LIVE_EXTRA[STATUS_RUN_KEYS])
    story = dict.fromkeys(STORY_KEYS | {"story_id"})
    with pytest.raises(pytest.fail.Exception, match=r"extra \['story_id'\]"):
        assert_keys("live", "stories[0]", story, STORY_KEYS, LIVE_EXTRA.get(STORY_KEYS, frozenset()))


def test_live_check_skips_when_am_is_not_on_path(monkeypatch, tmp_path):
    monkeypatch.setenv("PATH", str(tmp_path))
    with pytest.raises(pytest.skip.Exception, match="am is not installed here"):
        test_installed_am_prints_the_fixture_key_sets()


def test_live_check_reads_the_main_checkout_not_a_worktree():
    main = git_main_checkout()
    if main is None:
        pytest.skip("git could not name the main checkout")
    assert (main / ".git").is_dir(), f"{main}: not a main checkout (no .git directory)"
```

- [ ] **Step 2: Run them to see them fail**

Run: `python3 -m pytest tests/contract/test_am_fixtures.py -q -k "live"`
Expected: `test_live_allowance_...` PASSES (it only uses Task 1 names); the other two FAIL with `NameError: name 'test_installed_am_prints_the_fixture_key_sets' is not defined` and `NameError: name 'git_main_checkout' is not defined`.

- [ ] **Step 3: Implement the live check**

Insert directly above `def test_live_allowance_is_story_id_on_the_runs_row_and_status_run_only():` (keep two blank lines between top-level definitions):

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
    newest = max(rows, key=lambda row: row["started_at"])
    code, out, err = am_json("status", newest["id"], "--repo-dir", str(main))
    assert code == 0, f"am status {newest['id']} exited {code}: {out}{err}"
    check_status_data(f"live am status {newest['id']}", json.loads(out)["data"], LIVE_EXTRA)
```

- [ ] **Step 4: Run the module**

Run: `python3 -m pytest tests/contract/test_am_fixtures.py -q -rs`
Expected: `44 passed` on a machine with am and runs for this repo (the `-rs` summary shows no skips); on a machine without am or without runs, `43 passed, 1 skipped` with the skip reason naming the cause (`am is not installed here`, `git could not name the main checkout`, `am runs --repo-dir ... exited N: ...`, or `am has no runs for ...`). A failure in `test_installed_am_prints_the_fixture_key_sets` names `live am runs` or `live am status <id>`, the level, and the missing/extra keys — if it fails, report the message; do not change any expected set or fixture to make it pass.

- [ ] **Step 5: Confirm the live check is read-only**

Run: `grep -nE '"am"|am_json\(' tests/contract/test_am_fixtures.py`
Expected: only `am_json("runs", "--repo-dir", str(main))`, `am_json("status", newest["id"], "--repo-dir", str(main))`, the `def am_json` line and `subprocess.run(["am", *args], ...)` — no other am subcommand, no option other than `--repo-dir`, no `env=`.

- [ ] **Step 6: Commit**

```bash
git add tests/contract/test_am_fixtures.py
git commit -m "test(contract): check the installed am prints the fixture key sets for the main checkout"
```

---

### Task 6: Hello schema 1 or 2 in `test_am_shapes.py` (C) and full verification

**Files:**
- Modify: `tests/contract/test_am_shapes.py:159`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: nothing.

- [ ] **Step 1: Make the edit**

In `tests/contract/test_am_shapes.py`, line 159, replace:

```python
    assert hello["schema"] == 1, hello
```

with:

```python
    assert hello["schema"] in (1, 2), hello
```

Nothing else in that file changes. (The installed am prints schema 1 today, so there is no red step: the change widens an assertion that already passes. Confirm it still bites: temporarily change `(1, 2)` to `(2,)`, run Step 2, see `test_watch_all_follow_prints_a_hello_line_then_journal_lines` FAIL with `AssertionError: {'event': 'watch', 'schema': 1, ...}`, then restore `(1, 2)`.)

- [ ] **Step 2: Run the contract tier**

Run: `python3 -m pytest tests/contract -q -rs`
Expected: `55 passed` with am installed (`44` in `test_am_fixtures.py` + `11` in the two existing modules); without am, the am/brd-dependent tests skip and nothing fails.

- [ ] **Step 3: Confirm the diff is scoped**

Run: `git diff --stat main -- . ':!docs'` and `git status --short`
Expected: only `tests/contract/test_am_fixtures.py` and `tests/contract/test_am_shapes.py` changed; `git diff main -- tests/contract/test_am_shapes.py` shows exactly the one-line change; nothing under `tests/fixtures/` appears.

- [ ] **Step 4: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest line ends `passed` with no failures (includes `tests/architecture`), every QML `Totals` line shows `0 failed`, exit status 0.

- [ ] **Step 5: Commit**

```bash
git add tests/contract/test_am_shapes.py
git commit -m "test(contract): accept an am watch hello of schema 1 or 2"
```

---

## Self-review against the spec

| spec item | task |
|---|---|
| A.1 presence/parse, named failure | Task 1 `test_every_fixture_exists_and_parses` (+ bite: missing, malformed) |
| A.2 envelopes `{ok, data}`, `ok is True`, hello excluded | Task 1 `test_envelopes_are_ok_data` |
| A.3 runs rows, lease, progress, current, non-null lease/current exist, status vocab, `_am_runs_row` | Task 2 `test_runs_rows_key_sets` |
| A.4 no top-level subtasks (own check) | Task 3 `test_status_data_has_no_top_level_subtasks` |
| A.4 every level walked; attempt reached; control lease non-null in started; requests/claims lists; integrity unpinned; requests items unpinned | Task 3 `test_status_key_sets_at_every_level`, `test_status_fixtures_reach_attempts_and_a_control_lease` |
| A.5 vocabularies (status fixtures + runs rows), `canceled` accepted, `rows[].state` unchecked | Task 3 `test_status_vocabularies`; Task 2 `test_runs_row_statuses_are_in_the_run_vocabulary` |
| A.6 logs | Task 4 `test_logs_key_sets` |
| A.7 watch events | Task 4 `test_watch_event_key_sets` |
| A.8 hello | Task 4 `test_hello_key_sets_and_schemas` |
| A.9 `_note` / `_am_runs_row` placement | Task 4 `test_note_is_on_exactly_the_annotated_captures` |
| B.1 main checkout via git common dir | Task 5 `git_main_checkout`, `test_live_check_reads_the_main_checkout_not_a_worktree` |
| B.2 skips with named causes | Task 5 `test_installed_am_prints_the_fixture_key_sets`, `test_live_check_skips_when_am_is_not_on_path` |
| B.3 exact commands, newest by `started_at`, 30 s timeout fails, no env override, non-zero status fails | Task 5 `am_json`, Step 5 grep |
| B.4 same key sets + `story_id` allowance on two levels only; live statuses vs vocabularies | Task 5 via `check_runs_rows`/`check_status_data` with `LIVE_EXTRA`; `test_live_allowance_is_story_id_on_the_runs_row_and_status_run_only` |
| B.5 one definition per level shared | Task 1 constants; Tasks 2–3 walkers used by Task 5 |
| C hello `in (1, 2)` | Task 6 |
| Failure messages (source, level, missing, extra) | Task 1 `assert_keys`, `test_assert_keys_names_source_level_missing_and_extra` |
| Bite checks on mutated copies, not committed, fixtures never edited | Steps "Prove ... bite" in Tasks 1–4, all under `/tmp` |
| `bash tests/run.sh` + architecture green | Task 6 Step 4 |

Every code block above was assembled and run against the committed fixtures and the installed am on 2026-10-05 before writing this plan: 44 tests in `test_am_fixtures.py` pass (live check not skipped), the contract tier is 55 passed, and the mutation checks print `BITES` for every mutation.
<!-- task-pipeline: validated -->
