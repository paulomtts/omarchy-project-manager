# 1.3 Runs helper tests: the fake am serves the real fixtures — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The pytest suites of `runs-snapshot.py`, `runs-logs.py` and `runs-watch.py` feed their fake `am` the committed captures in `tests/fixtures/am/` (loaded with `json.load`) instead of hand-written S1-shaped payloads, with every non-capture payload labelled `synthetic:`.

**Architecture:** Each of the three test files gets its own `FIXTURES` path and a non-caching `fixture(name)` loader (no shared module; the files are self-contained by convention). The hand-written payload builders (`summary`/`status_data`, `LOGS_DATA`, `ev`/`upsert`/`hello`) are replaced by builders that return fresh copies of captures, with labelled shape-keeping edits. One new test per file pins the migration itself. Helper code (`core/backend/runs/*.py`) is not touched.

**Tech Stack:** Python 3, pytest (via `python3 -m pytest`, or `uv run --with pytest python3 -m pytest` when pytest is not installed), subprocess tests with a fake `am` on a temp PATH.

**Spec:** `docs/superpowers/specs/1-3-runs-helper-tests-7d0b07fe.md` (prepended below, verbatim in substance; executors read both).

## Global Constraints

- Tests only. No change to helper code (`core/backend/runs/*.py`). The three files stay green on current code.
- Only three files change: `tests/core/backend/runs/test_runs_snapshot.py`, `tests/core/backend/runs/test_runs_logs.py`, `tests/core/backend/runs/test_runs_watch.py`. No fixture edits, no shared Python helper module.
- Python reads the fixtures with `json.load`. `fixture(name)` returns a fresh load on every call (no cache).
- Readers ignore keys starting with `_`: served envelopes drop top-level `_` keys.
- A hand-written am payload is allowed only for a synthetic edge case (garbage, a missing key, a value no capture contains) and carries a `synthetic:` comment saying what it stands for. An edit to a capture is made on a fresh copy, is labelled, and never changes the shape.
- Every test keeps its name, its parametrization ids and its assertions' meaning. No test is deleted, skipped or xfailed. Literal expected values change only where the input id or payload changed.
- Not changed here: the 10-terminal cap and `TERMINAL` of `runs-snapshot.py`, the hello schema check of `runs-watch.py`, `runs-logs.py`'s argv (`--repo-dir` still asserted absent).
- Docstrings and comments state the contract only, with no narrative. The words "hand-written fixtures" leave the module docstrings.
- Verification: `python3 -m pytest tests/core/backend/runs -q` goes from 278 passed to 281 passed; `bash tests/run.sh` is green, including `tests/architecture` and `tests/contract`.

## Review Focus

1. `row_for` with a status no capture has (`cancelled`, `stopped`, `paused`, `something-new`) must still return a row with all 11 real `am runs` keys — otherwise the key-set check in `test_snapshot_shape` means nothing for synthetic rows. Pinned in Task 1 by `test_fake_am_serves_the_captures` (loops `row_for` over capture and non-capture statuses and checks the key set).
2. `fixture()` must not cache: `test_large_output_not_trimmed` mutates its copy, and a cache would leak that edit into later tests. Pinned in Task 2 by `test_logs_data_is_the_capture` (mutate one copy, the next one is still the capture).
3. Watch `changed()` sorts the ids inside a line. Wherever `WATCHED` (`20261004T204141Z-cb11063d`) and a test-local id share a line, compare to `sorted([WATCHED, "r2"])`, never a hand-ordered list. Done in Task 3 in `test_missing_or_unparseable_ts_is_kept` and `test_debounce_batches_and_dedupes`.
4. The captured `run_upsert` names the real repo dir (`/home/user/Code/omarchy-project-manager`), never the temp `proj`, so an unedited `upsert()` is only ever a `WATCHED` line, kept because `WATCHED` is on argv. Adoption tests use `other(..., repo_dir=…)` only. Pinned in Task 3 by `test_lines_are_capture_copies` (`upsert()["line"]["run_id"] == WATCHED`).
5. Debounce timing tests now print real ~1 KB lines. The bounds (`<= int(elapsed / 0.25) + 1`, `< 5 s`) must stay green as they are. If a debounce test fails on timing, stop and report it — do NOT loosen the bounds. Exercised by the three existing debounce tests in Task 3.

---

## Spec (prepended, verbatim; headings demoted one level)

## 1.3 Runs helper tests: the fake am serves the real fixtures — design

Card `7d0b07fe`, a subtask of story `6596351c` ("Real am fixtures and contract
tests"), blocked by `9f7e9956` (1.2, the QML fixture loader). Parent spec:
`docs/superpowers/specs/2026-10-05-align-run-model-design.md` (below:
**parent**). Work breakdown item 1 (parent L321-323): this subtask is "the
helpers' fake am serving the fixtures" only.

### Goal

The pytest suites of the three read-only runs helpers stop feeding their fake
`am` hand-written payloads in the guessed S1 shape (parent L133). Each fake am
serves the committed captures in `tests/fixtures/am/` instead, loaded with
`json.load`. Any payload that no capture contains is built on a fresh copy of a
capture, or is plain garbage, and carries a `synthetic:` comment. Each existing
test keeps its name and its meaning. The three files stay green on the
helpers as they are today. No file outside the three test files changes.

### Inherited constraints

| constraint | source |
|---|---|
| `tests/core/backend/runs/test_runs_snapshot.py:102-106` and `test_runs_logs.py:47-53` are hand-written am payloads that hid the defect | parent L133 |
| Captures live in `tests/fixtures/am/`: `runs.json`, `status-{started,done,escalated,escalated-integrate,done-integrate}.json`, `watch-events.json`, `watch-hello.json`, `logs-attempt.json` | parent L233-249 |
| Readers ignore keys starting with `_` | parent L251 |
| Every unit test of code that reads am output (incl. "the `runs-*` helpers") builds its input from these fixtures. A hand-written am payload is allowed only for a synthetic edge case (garbage, a missing key, a value no capture contains) and carries a `synthetic:` comment saying what it stands for | parent L257-262 |
| An edit to a fixture inside a test (a status set to `canceled`, a `ts` stamped `NOW`) is made on a fresh copy, is labelled, and never changes the shape | parent L265-267 |
| Python reads the fixtures with `json.load` | parent L269 |
| `am runs` rows carry the seven identity fields plus `milestone_id`, `card_id`, `lease`, `progress` | parent L50-53 |
| `am logs` data is `run_id, story_id, card, phase, attempt, status, exit_code, artifacts`; each artifact is `{path, present, text}`. There is no `data.stdout` | parent L55-58 |
| The `am watch --follow` hello is `{"event":"watch","schema":1,"am":"0.1.0","runs_dir":…}`; journal lines are `seq, ts, run_id, event, story, card, phase, attempt, payload` | parent L62-65 |
| `runs-watch.py` reads only `run_id`, `event`, `ts` and a `run_upsert`'s `payload.repo_dir` | parent L299-300 |
| Not changed here: the 10-terminal cap and the `TERMINAL` set of `runs-snapshot.py`, the hello schema check of `runs-watch.py`, `runs-logs.py`'s argv (no `--repo-dir` yet) | parent L312-313; L319-330 (items 3, 4 are later subtasks) |
| Tests only. No change to helper code (`core/backend/runs/*.py`). The three files stay green on current code | card |
| Docstrings and comments state the contract only, with no narrative | card |
| `bash tests/run.sh` is green, including `tests/architecture` | card |

### Fixture facts this design relies on (checked 2026-10-05)

- `runs.json`: `data.runs` has two rows, newest first:
  `20261005T021400Z-837c4431` (`started`, lease live) and
  `20261004T204141Z-cb11063d` (`done`, lease null). Each row has 11 keys: the
  seven identity fields plus `milestone_id`, `card_id`, `lease`, `progress`.
- `status-started.json`'s `data.run` is `837c4431…` `started`.
  `status-done.json`'s is `cb11063d…` `done`. `status-escalated.json`'s is
  `20261005T032543Z-bcc4e411` `escalated`, and its `_am_runs_row` is that run's
  real `am runs` row. Only the three e2e status fixtures carry `_` keys, and only
  at the top level (`_am_runs_row`, `_note`). No fixture has a nested `_` key.
- `logs-attempt.json`: `data.run_id` is `cb11063d…`, `card` is `adff6c85…`,
  `phase` is `review`, `attempt` is `1`, `status` is `ok`.
  `artifacts.stdout.text` has 19 lines, and `artifacts.stderr` is
  `{present: false, text: null}`. No top-level `_` keys.
- `watch-events.json`: `data.events` holds 60 events, all of run
  `20261004T204141Z-cb11063d`. It contains `run_upsert` (1, seq 1, with
  `payload.repo_dir` `/home/user/Code/omarchy-project-manager`),
  `story_upsert`, `subtask_upsert`, `phase_upsert` and `attempt_upsert`. Each
  `ts` is ISO with a `Z` suffix.
- `watch-hello.json`: `schema_1` is the real hello, and `schema_2` is a derived
  copy with `schema: 2`.

### Behavior: what each file must do after the change

#### Shared rules (all three files)

- Each file defines `FIXTURES = os.path.join(ROOT, "tests", "fixtures", "am")`
  and a loader `fixture(name)`. The loader returns a fresh `json.load` of
  `FIXTURES/<name>` on every call, so an edit never leaks into another test.
  This follows the files' own convention: each one is self-contained and
  repeats `write_exec` / `env_for`. Do not add a shared Python helper module.
- Whatever reaches the fake am's stdout as a payload is one of these:
  - (a) a capture, loaded unchanged, with top-level `_` keys dropped;
  - (b) a fresh copy of a capture with labelled edits that keep its shape. The
    edits allowed are a value no capture contains, a test-local id, or a
    PAST/NOW `ts` marker;
  - (c) synthetic text or envelopes, labelled `synthetic:` with what each one
    stands for. These cover garbage, error envelopes, empty lists, and stderr
    text.
- The label sits on the helper function that makes the edit, or on the
  parametrize list or statement that holds the synthetic value. One comment per
  group is enough. It names what the value stands for, for example
  `# synthetic: a run status no capture has`.
- Module docstrings (line 3 in snapshot/logs, lines 3-9 in watch) state that the
  fake am serves the committed captures in `tests/fixtures/am/`. They also say
  that payloads outside the captures are labelled `synthetic:`. The words
  "hand-written fixtures" go.
- Every test keeps its name, its parametrization ids and its assertions'
  meaning. Literal expected values change only where the input id or payload
  changed. No test is deleted, skipped or xfailed.

#### `tests/core/backend/runs/test_runs_snapshot.py`

- `status_data()` (L97-112) and `summary()` (L91-94) go. In their place:
  - `runs_rows()`: `fixture("runs.json")["data"]["runs"]`.
  - `status_envelope(name)`: `fixture(name)` with top-level keys starting with
    `_` dropped.
  - `row_for(run_id, status)`: a fresh copy of a real `am runs` row with `id`
    and `status` set. The base row is picked by status:
    - `started` → runs.json row 0;
    - `done` → runs.json row 1;
    - `escalated` → `status-escalated.json`'s `_am_runs_row`;
    - any other status → runs.json row 1.

    Labelled `synthetic:`: the test-local id, and for other statuses a value
    no capture contains.
  - `status_for(run_id, status)`: the matching status envelope's `data`
    (`status-started` / `status-done` / `status-escalated`, `status-done` for
    the rest), on a fresh copy, with `data.run.id` and `data.run.status` set.
    It is labelled the same way.
- `set_runs(world, runs)` keeps writing `{"data": {"runs": runs}, "ok": True}`.
  `set_status(world, run_id, data)` writes `{"data": data, "ok": True}`.
  `seed(world, runs)` writes `status_for(r["id"], r["status"])` for every row.
- The fake am script (L24-39), `set_raw`, `calls`, `expected` and `run` are
  unchanged.

| test | input after the change | assertion meaning kept |
|---|---|---|
| `test_snapshot_shape` | `runs_rows()` unchanged, with `status-started` / `status-done` envelopes (`_` dropped) served for their ids | output == each row with `status` replaced by that run's status data, in am's order; each entry's key set equals its am runs row's key set (the helper adds and drops no key); `status` is a dict. `SUMMARY_FIELDS` is replaced by the row's own key set (real rows have 11 keys, parent L50-53) and is deleted if unused |
| `test_status_fanout_selection` | `row_for` with the same ids/statuses as today (`n1`, `t1..t12`, `n2`, `n3`) | the same `want` list and the same exact call sequence |
| `test_terminal_set_pinned` | `row_for("x%02d" % i, status)` for the same 7 parametrized statuses | the same `kept` counts. `stopped`, `cancelled`, `paused` and `something-new` are labelled synthetic |
| `test_repo_dir_passed` | `seed(world, runs_rows())` | 3 calls, each ending `--repo-dir <proj>` |
| `test_am_error_envelope_passthrough_status` | `set_runs(runs_rows())`; status served for row 0's id only | `UNKNOWN_RUN` re-emitted; the last call is `["status", <row 1 id>, "--repo-dir", proj]` |
| `test_am_bad_output` (status cases) | `set_runs(runs_rows())`, then `set_raw("status-" + <row 0 id>, …)` | AmBadOutput, exit 1 |
| `test_am_bad_output` (runs cases), `test_am_error_envelope_passthrough_runs` | unchanged strings / envelopes, labelled `synthetic:` (garbage, malformed `am runs` data, error envelopes) | unchanged |
| `test_no_runs_is_empty_state`, `test_data_dir`, `test_am_does_not_inherit_stdin` | `[]` / `{'runs': []}`, labelled `synthetic: am runs of a project with no runs` | unchanged |
| `UNKNOWN_RUN`, `REPO_DIR_ERROR` | unchanged, labelled synthetic (no capture of an error envelope) | — |

#### `tests/core/backend/runs/test_runs_logs.py`

- `LOGS_DATA` (L47-54) goes. `logs_data()` returns
  `fixture("logs-attempt.json")["data"]`, a fresh copy on every call. Each test
  that used `LOGS_DATA` builds its envelope as `{"ok": True, "data":
  logs_data()}`. The capture is `{"data", "ok"}` with no `_` keys, so this
  equals the capture.
- `ARGS` (L45) and the asserted argv literals stay as they are. They are helper
  argv, not am output, and `runs-logs.py` does not inspect `data`. `--repo-dir`
  is still asserted absent, because adding it is subtask 3 (parent L327-328).

| test | input after the change | assertion meaning kept |
|---|---|---|
| `test_ok_envelope_passed_through`, `test_exact_am_argv`, `test_args_reach_am_verbatim`, `test_pretty_printed_am_output_becomes_one_line`, `test_ok_wins_over_am_exit_code_and_stderr` | the `logs-attempt.json` envelope | `data` passed through unchanged; same argv |
| `test_large_output_not_trimmed` | `logs_data()` with `artifacts.stdout.text` set to the 5000-line `big` (labelled `synthetic: an attempt output longer than any capture`) | `out["data"]["artifacts"]["stdout"]["text"] == big`, and it has 5000 lines |
| `test_control_and_unicode_text_round_trips` | `logs_data()` with `artifacts.stdout.text` and `artifacts.stderr.text` set to the control/unicode text (labelled synthetic) | `out == envelope` |
| `test_am_does_not_inherit_stdin` | the inline am reads stdin, then prints `FAKE_AM_DIR/logs.out`, which `set_logs` filled with the capture envelope | exit 0, one line, equal to the capture envelope |
| `test_refusal_passed_through_exit_0`, `test_missing_fixture_unknown_run`, the bad-output parametrizations, `UNKNOWN_RUN` | unchanged, labelled synthetic (refusals, garbage) | unchanged |

#### `tests/core/backend/runs/test_runs_watch.py`

- `WATCHED = <watch-events.json events[0]["run_id"]>`
  (`20261004T204141Z-cb11063d`). `run_helper` and `start_helper` default argv
  becomes `[proj, WATCHED]`. Every assertion that names `"r1"` as the watched
  run names `WATCHED` instead. The literals in `test_refusal_exit_3_*` and
  `test_exit_3_*` are synthetic am text, not ids from a line, so they stay as
  they are.
- `hello(schema=1)` returns `{"line": fixture("watch-hello.json")["schema_1"]}`.
  `hello(2)` returns the capture's `schema_2` unchanged. `"1"` and `MISSING` are
  edits of a `schema_1` copy, labelled synthetic.
- `ev(event="phase_upsert", ts="NOW")` returns a fresh copy of the first event
  in `watch-events.json` whose `event` equals the argument. Its `ts` is replaced
  by the marker, and that is the only edit, labelled
  `# edited copy: ts is the fake am's PAST/NOW marker`. `upsert(ts="NOW")` is
  `ev("run_upsert", ts)`.
- Lines that need what the single-run capture does not have are built by
  `other(run_id, event="phase_upsert", ts="NOW", **edits)`. It returns a copy of
  `ev(event, ts)` with `run_id` set to a test-local id and the given edits
  applied, labelled `synthetic:`. Other run ids: `r2`, `r7`, `r8`, `r9`, `n1`,
  `n2`. Allowed edits:
  - `ts` absent, or `"yesterday-ish"`;
  - `run_id` absent;
  - an unknown `event` (`future_upsert`);
  - extra top-level / payload keys;
  - for `run_upsert`: `payload.id` and `payload.repo_dir`.

  A line for `WATCHED` that needs such an edit (ts absent, extra keys) uses
  the same mechanism and the same label.
- The fake am script (L25-60) is unchanged.

| test | lines after the change | assertion meaning kept |
|---|---|---|
| `test_clean_exit_zero` | `hello()` | no lines; argv `["watch","--all","--follow"]` |
| `test_drops_hello_and_backlog` | `ev(ts="PAST")`, `ev("subtask_upsert", ts="PAST")` for WATCHED; `other("r2")`; argv `[proj, WATCHED, "r2"]` | `[["r2"]]` |
| `test_live_event_for_watched_run_emits_changed` | `ev()` | `lines == [{"changed": [WATCHED]}]` |
| `test_filters_unwatched_runs` | `other("r9")`, `other("r8","attempt_upsert")`, `other("r7","run_upsert", repo_dir="/somewhere/else")`, `ev()` | `[[WATCHED]]` |
| `test_ignores_unknown_events_and_keys` | raw garbage; `other("r2","future_upsert")`; a copy with `run_id` removed; a WATCHED copy with `payload.shiny` and `brand_new_key` added | `[[WATCHED]]`, no Traceback |
| `test_missing_or_unparseable_ts_is_kept` | WATCHED copy without `ts`; `other("r2", ts="yesterday-ish")` | `[sorted([WATCHED, "r2"])]` |
| debounce tests (3) | `ev()` / `other("r2")` / `other("r2", "attempt_upsert")` / `ev("subtask_upsert")` in the same sequences, each line for the same run as today (the `r2` attempt line stays an `r2` line) | same groupings, same timing bounds |
| `test_new_run_upsert_in_project_is_adopted` | `other("n1","run_upsert", repo_dir=<form>)`, `other("n2","run_upsert", repo_dir="/somewhere/else")`, `other("n2")`, `other("n1")` | `[["n1"], ["n1"]]` for all 3 forms |
| `test_schema_mismatch` | `hello(2)` (capture `schema_2`), `hello("1")`, `hello(MISSING)`, then `ev()` | SchemaMismatch, under 5 s, am gone. The current helper rejects schema 2; subtask 4 changes that test |
| `test_exit_3_corrupt_journal`, `test_other_exit_is_helper_error` | `hello()`, `ev()`; stderr text synthetic | first line `{"changed": [WATCHED]}`, then the error |
| refusal tests (2) | envelopes unchanged, labelled synthetic | unchanged |
| signal / closed-stdout tests | `hello()`, `ev()` | first line `{"changed": [WATCHED]}` (signal); exit 0, am gone |

### Error paths

This subtask changes no runtime error path. The error-path tests it keeps
continue to prove these behaviors on current code:

- snapshot: Usage, AmMissing, HelperError (an unstartable am, a timeout), an
  `ok:false` passthrough for runs and status, and 14 AmBadOutput shapes;
- logs: refusal passthrough, UnknownRun, AmBadOutput (non-JSON / non-object /
  no boolean ok), AmMissing, Usage, HelperError;
- watch: SchemaMismatch, CorruptJournal (from the exit code and from a
  refusal), HelperError, a refusal re-emitted, and signal / closed-stdout
  stops.

A fixture that cannot be read makes `fixture()` raise
(`FileNotFoundError` / `JSONDecodeError`) in the test that loads it. The
contract test already pins that every capture is present
(`tests/contract/test_am_fixtures.py`).

### Tests (all in the pytest tier)

All three files are subprocess tests of the helper scripts. They run under
`python3 -m pytest` with a fake `am` on a temp PATH, which is the tier these
helpers are already tested in. This subtask adds no QML test and no contract
test. Python helpers are not reachable from qmltestrunner, and the contract
tier pins am, not plugin code (parent L321).

No new behavior is added, so the red step of TDD shows up as a failing test
whenever an input migration breaks an assertion. Migrate one file per task,
and run that file after each helper function is replaced.

New assertions, one per file, that pin the migration itself (pytest tier,
same file):

1. `test_runs_snapshot.py::test_fake_am_serves_the_captures`: after
   `seed(world, runs_rows())`, `runs.out` parses to `fixture("runs.json")`.
   Each `status-<id>.out` parses to its capture with `_` keys dropped. For
   `status-escalated.json` (through `row_for(..., "escalated")` /
   `status_for`), no top-level key of the served envelope starts with `_`.
   This pins that the fake serves captures and that the `_` drop works.
2. `test_runs_logs.py::test_logs_data_is_the_capture`: `logs_data()` equals
   `fixture("logs-attempt.json")["data"]`. Mutating one returned copy does not
   change the next one.
3. `test_runs_watch.py::test_lines_are_capture_copies`: for every event name
   `ev()` is called with, `ev(e, "NOW")["line"]` equals the first capture event
   of that name in every key except `ts`, and its `ts` is `"NOW"`. `hello()`
   equals the capture's `schema_1`.

### Out of scope

- Any change to `core/backend/runs/*.py`, including:
  - `TERMINAL` with `canceled`, and the hello schema 2 acceptance: subtask 4
    (parent L329-330);
  - `--repo-dir` in `runs-logs.py`: subtask 3 (parent L327-328).
- The other helpers' tests with hand-written fakes: `test_dispatch_preview.py`,
  `test_run_control.py`, `test_notify.py`, `test_start_run.py`.
- QML tests (`tst_runs.qml`, `tst_run_store.qml`, `tst_runs_flow.qml`) and
  `tests/helpers/amFixtures.js`, which is 1.2 and already landed.
- The contract tests (1.1) and the fixtures themselves, which are never
  edited.
- A shared Python fixture module.

### Review focus for the planner

1. `row_for` with a status that has no matching capture must still give a row
   with all 11 keys. Otherwise `test_snapshot_shape`'s key-set check loses its
   meaning for synthetic rows.
2. `fixture()` must not cache. Two calls must give independent objects,
   because `test_large_output_not_trimmed` edits its copy.
3. Watch `changed()` sorts. Wherever WATCHED and a test-local id share a line,
   compare to `sorted([...])`, not to a hand-ordered list.
4. The fixture's `run_upsert` names the real repo dir, not the temp `proj`. An
   unedited `upsert()` of WATCHED must not be adopted: WATCHED is on argv, so
   it is kept for that reason alone. Adoption tests use `other(...,
   repo_dir=…)` only.
5. Debounce timing tests now print longer lines (real payloads, about 1 KB).
   The bounds (`<= elapsed/0.25 + 1`, `< 5 s`) must stay green. If they don't,
   report it rather than loosen them.

### Verification

- `python3 -m pytest tests/core/backend/runs -q` (where pytest is not installed, `uv run --with pytest python3 -m pytest …`, as `tests/run.sh` does): green. The baseline is 278
  passed; after the change it is 281, with the three new assertions.
- `bash tests/run.sh`: green, including `tests/architecture` and
  `tests/contract`.
- `git diff --stat main...` touches only the three test files (plus this spec
  and its plan).

---

## File Structure

| file | responsibility after the change |
|---|---|
| `tests/core/backend/runs/test_runs_snapshot.py` | `fixture`, `runs_rows`, `status_envelope`, `row_for`, `status_for` replace `summary`/`status_data`/`SUMMARY_FIELDS`; `set_status(world, run_id, data)` |
| `tests/core/backend/runs/test_runs_logs.py` | `fixture`, `logs_data` replace `LOGS_DATA`; the stdin test's inline am serves `logs.out` |
| `tests/core/backend/runs/test_runs_watch.py` | `fixture`, `WATCHED`, `hello`, `ev`, `upsert`, `other` replace the hand-built lines; default argv `[proj, WATCHED]` |

Tasks are independent (one file each) and can be done in any order.

---

### Task 1: `test_runs_snapshot.py` serves the `am runs` / `am status` captures

**Files:**
- Modify: `tests/core/backend/runs/test_runs_snapshot.py` (docstring L1-6, constants L41-43, builders L91-129, tests L150-377)
- Test: same file

**Interfaces:**
- Consumes: `tests/fixtures/am/runs.json`, `status-started.json`, `status-done.json`, `status-escalated.json` (read only).
- Produces (file-local, used only in this file):
  - `FIXTURES: str` — `<repo>/tests/fixtures/am`
  - `fixture(name: str) -> object` — fresh `json.load`
  - `runs_rows() -> list[dict]` — `runs.json` `data.runs`
  - `status_envelope(name: str) -> dict` — capture minus top-level `_` keys
  - `row_for(run_id: str, status: str) -> dict` — 11-key `am runs` row copy
  - `status_for(run_id: str, status: str) -> dict` — `am status` `data` copy
  - `set_status(world, run_id: str, data: dict) -> None` (signature changes: `data` is now required, no `status` arg)

- [ ] **Step 1: Write the failing test**

Insert this test in `tests/core/backend/runs/test_runs_snapshot.py` directly after the `# --- shape and fan-out ---` banner line (current L258), before `def test_snapshot_shape`:

```python
def test_fake_am_serves_the_captures(world):
    runs = runs_rows()
    seed(world, runs)
    assert json.loads((world["am"] / "runs.out").read_text()) == fixture("runs.json")
    for row, name in zip(runs, ["status-started.json", "status-done.json"]):
        served = json.loads((world["am"] / ("status-" + row["id"] + ".out")).read_text())
        assert served == status_envelope(name)
    # status-escalated.json carries top-level `_` keys; the served envelope does not.
    assert any(k.startswith("_") for k in fixture("status-escalated.json"))
    assert set(status_envelope("status-escalated.json")) == {"data", "ok"}
    set_status(world, "e1", status_for("e1", "escalated"))
    served = json.loads((world["am"] / "status-e1.out").read_text())
    assert not any(k.startswith("_") for k in served)
    want = status_envelope("status-escalated.json")
    want["data"]["run"]["id"] = "e1"
    assert served == want
    # Every row_for row, capture status or not, has a real am runs row's 11 keys.
    keys = set(runs[0])
    assert len(keys) == 11
    for status in ["started", "done", "escalated", "cancelled", "something-new"]:
        row = row_for("e1", status)
        assert set(row) == keys
        assert (row["id"], row["status"]) == ("e1", status)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_snapshot.py::test_fake_am_serves_the_captures -q`
(if `python3 -c 'import pytest'` fails, prefix with `uv run --with pytest` instead: `uv run --with pytest python3 -m pytest …`)
Expected: FAIL with `NameError: name 'runs_rows' is not defined`.

- [ ] **Step 3: Replace the module docstring**

Replace L1-6 with:

```python
"""runs-snapshot.py: am runs + am status fan-out, one JSON line on every path.

Hermetic: a fake `am` lives on a temp PATH and serves, from FAKE_AM_DIR, the
committed captures in tests/fixtures/am/ (a payload no capture holds is labelled
`synthetic:`), appending each call's argv to calls.log; HOME and XDG_DATA_HOME
are temp. The real `am` and real data are never touched.
"""
```

- [ ] **Step 4: Replace the constants and add the loader**

Replace L41-43 (`UNKNOWN_RUN`, `REPO_DIR_ERROR`, `SUMMARY_FIELDS`) with:

```python
FIXTURES = os.path.join(ROOT, "tests", "fixtures", "am")
# synthetic: am error envelopes; no capture holds one.
UNKNOWN_RUN = {"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}
REPO_DIR_ERROR = {"error": {"message": "not a git repository", "type": "RepoDirError"}, "ok": False}
STATUS_CAPTURES = {"started": "status-started.json", "done": "status-done.json",
                   "escalated": "status-escalated.json"}


def fixture(name):
    """A fresh json.load of tests/fixtures/am/<name>, so an edit never reaches
    another call."""
    with open(os.path.join(FIXTURES, name)) as f:
        return json.load(f)
```

`SUMMARY_FIELDS` is deleted (its only use, in `test_snapshot_shape`, is replaced in Step 6).

- [ ] **Step 5: Replace the payload builders**

Replace L91-129 (`summary`, `status_data`, `set_runs`, `set_status`, `seed`) with:

```python
def runs_rows():
    """The captured `am runs` rows, newest first: a started run, then a done one."""
    return fixture("runs.json")["data"]["runs"]


def status_envelope(name):
    """A captured `am status` envelope without its top-level `_` keys."""
    return {k: v for k, v in fixture(name).items() if not k.startswith("_")}


def row_for(run_id, status):
    """synthetic: a test-local run id, and for a status other than started, done
    or escalated a value no capture has, set on a copy of a real `am runs` row
    (the started row, the escalated run's row, or else the done row)."""
    if status == "escalated":
        row = fixture("status-escalated.json")["_am_runs_row"]
    else:
        row = runs_rows()[0 if status == "started" else 1]
    row["id"] = run_id
    row["status"] = status
    return row


def status_for(run_id, status):
    """synthetic: the same edits as row_for, set on a copy of the matching
    captured `am status` data (status-done for a status no capture has)."""
    data = status_envelope(STATUS_CAPTURES.get(status, "status-done.json"))["data"]
    data["run"]["id"] = run_id
    data["run"]["status"] = status
    return data


def set_runs(world, runs):
    (world["am"] / "runs.out").write_text(json.dumps({"data": {"runs": runs}, "ok": True}) + "\n")


def set_status(world, run_id, data):
    (world["am"] / ("status-" + run_id + ".out")).write_text(
        json.dumps({"data": data, "ok": True}) + "\n")


def seed(world, runs):
    """`am runs` lists `runs`; `am status` answers for every one of them."""
    set_runs(world, runs)
    for r in runs:
        set_status(world, r["id"], status_for(r["id"], r["status"]))
```

(`set_raw`, `calls`, `expected`, `run`, `FAKE_AM` stay as they are.)

- [ ] **Step 6: Migrate the tests that used the old builders**

In `test_no_runs_is_empty_state` (L150), add the label on the line above `set_runs(world, [])`:

```python
def test_no_runs_is_empty_state(world):
    # synthetic: am runs of a project with no runs.
    set_runs(world, [])
```

In `test_data_dir` (L178-180):

```python
def test_data_dir(world, case):
    # synthetic: am runs of a project with no runs.
    set_runs(world, [])
```

In `test_am_does_not_inherit_stdin` (L237-239):

```python
    # synthetic: am runs of a project with no runs.
    write_exec(world["bin"] / "am",
               "#!/usr/bin/env python3\nimport json, sys\nsys.stdin.read()\n"
               "print(json.dumps({'ok': True, 'data': {'runs': []}}))\n")
```

Replace `test_snapshot_shape` (L260-274) with:

```python
def test_snapshot_shape(world):
    runs = runs_rows()
    seed(world, runs)
    code, out = run(world)  # run() asserts stdout is exactly one JSON line
    assert code == 0
    assert out == {
        "ok": True,
        "runs": [expected(runs[0], status_envelope("status-started.json")["data"]),
                 expected(runs[1], status_envelope("status-done.json")["data"])],
        "data_dir": str(world["data"]),
    }
    for entry, row in zip(out["runs"], runs):
        assert set(entry) == set(row)
        assert isinstance(entry["status"], dict)
```

Replace the `runs = (...)` block of `test_status_fanout_selection` (L280-285) with:

```python
    runs = ([row_for("n1", "started")]
            + [row_for("t%d" % i, "done") for i in range(1, 6)]
            + [row_for("n2", "started")]
            + [row_for("t%d" % i, ["escalated", "cancelled", "stopped"][i % 3])
               for i in range(6, 13)]
            + [row_for("n3", "started")])
```

Replace `test_terminal_set_pinned`'s decorator and its `runs =` line (L297-304) with:

```python
# synthetic: stopped, cancelled, paused and something-new are run statuses no
# capture has.
@pytest.mark.parametrize("status,kept", [
    ("done", 10), ("escalated", 10), ("stopped", 10), ("cancelled", 10),
    ("started", 12), ("paused", 12), ("something-new", 12),
])
def test_terminal_set_pinned(world, status, kept):
    # `stopped` is "parked" in the domain table but terminal here: it counts
    # toward the cap of 10. Any status outside the four is non-terminal.
    runs = [row_for("x%02d" % i, status) for i in range(12)]
```

In `test_repo_dir_passed` (L313) replace the `seed(...)` line with:

```python
    seed(world, runs_rows())
```

Replace `test_am_error_envelope_passthrough_status` (L336-345) with:

```python
def test_am_error_envelope_passthrough_status(world):
    # The second run has no status fixture, so the fake am answers UnknownRunError,
    # exit 3. The whole snapshot fails; no partial result is printed.
    runs = runs_rows()
    set_runs(world, runs)
    set_status(world, runs[0]["id"], status_for(runs[0]["id"], runs[0]["status"]))
    code, out = run(world)
    assert code == 1
    assert out == UNKNOWN_RUN
    assert "data_dir" not in out
    assert calls(world)[-1] == ["status", runs[1]["id"], "--repo-dir", str(world["proj"])]
```

Label the `test_am_bad_output` parametrize list and migrate its status branch (L348-372):

```python
# synthetic: garbage and malformed `am runs` / `am status` output.
@pytest.mark.parametrize("target,text,exit_code", [
```

(the list body and `ids=` are unchanged) and the function body's `else:` branch becomes:

```python
    else:
        runs = runs_rows()
        set_runs(world, runs)
        set_raw(world, "status-" + runs[0]["id"], text, exit_code)
```

`test_am_error_envelope_passthrough_runs` (L324-333) is unchanged: its inputs `UNKNOWN_RUN` / `REPO_DIR_ERROR` are labelled at their definition.

- [ ] **Step 7: Run the file to verify it passes**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_snapshot.py -q`
Expected: PASS, every test in the file (one more than before).
Then: `grep -n "summary(\|status_data\|SUMMARY_FIELDS\|hand-written" tests/core/backend/runs/test_runs_snapshot.py`
Expected: no output.

- [ ] **Step 8: Commit**

```bash
git add tests/core/backend/runs/test_runs_snapshot.py
git commit -m "test(runs-snapshot): serve the committed am captures from the fake am"
```

---

### Task 2: `test_runs_logs.py` serves the `am logs` capture

**Files:**
- Modify: `tests/core/backend/runs/test_runs_logs.py` (docstring L1-6, constants L45-54, tests L118-261)
- Test: same file

**Interfaces:**
- Consumes: `tests/fixtures/am/logs-attempt.json` (read only).
- Produces (file-local):
  - `FIXTURES: str`, `fixture(name: str) -> object` — fresh `json.load`
  - `logs_data() -> dict` — `logs-attempt.json` `data`, fresh copy

- [ ] **Step 1: Write the failing test**

Insert in `tests/core/backend/runs/test_runs_logs.py` directly after the `# --- passthrough ---` banner (current L116), before `def test_ok_envelope_passed_through`:

```python
def test_logs_data_is_the_capture():
    assert logs_data() == fixture("logs-attempt.json")["data"]
    assert {"ok": True, "data": logs_data()} == fixture("logs-attempt.json")
    # Each call is a fresh copy: an edit to one never reaches the next.
    first = logs_data()
    first["artifacts"]["stdout"]["text"] = "edited"
    assert logs_data() == fixture("logs-attempt.json")["data"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_logs.py::test_logs_data_is_the_capture -q`
Expected: FAIL with `NameError: name 'logs_data' is not defined`.

- [ ] **Step 3: Replace the module docstring**

Replace L1-6 with:

```python
"""runs-logs.py: an `am logs` passthrough for one attempt, one JSON line on every path.

Hermetic: a fake `am` lives on a temp PATH and serves, from FAKE_AM_DIR, the
committed captures in tests/fixtures/am/ (a payload no capture holds is labelled
`synthetic:`), appending each call's argv to calls.log; HOME and XDG_DATA_HOME
are temp. The real `am` and real data are never touched.
"""
```

- [ ] **Step 4: Replace `LOGS_DATA` with the loader**

Replace L45-54 (`ARGS`, `UNKNOWN_RUN`, the comment and `LOGS_DATA`) with:

```python
ARGS = ["r1", "c1", "implement", "2"]
FIXTURES = os.path.join(ROOT, "tests", "fixtures", "am")
# synthetic: am's error envelope for an unknown run; no capture holds one.
UNKNOWN_RUN = {"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}


def fixture(name):
    """A fresh json.load of tests/fixtures/am/<name>, so an edit never reaches
    another call."""
    with open(os.path.join(FIXTURES, name)) as f:
        return json.load(f)


def logs_data():
    """The captured `am logs` data of one attempt. Opaque to the helper: it must
    pass whatever `data` am prints through untouched."""
    return fixture("logs-attempt.json")["data"]
```

- [ ] **Step 5: Migrate the tests**

Replace each `LOGS_DATA` envelope with `logs_data()`:

`test_ok_envelope_passed_through`:

```python
def test_ok_envelope_passed_through(world):
    envelope = {"ok": True, "data": logs_data()}
    set_logs(world, envelope)
    code, out = run(world)  # run() asserts stdout is exactly one JSON line
    assert code == 0
    assert out == envelope
```

`test_exact_am_argv` first line:

```python
    set_logs(world, {"ok": True, "data": logs_data()})
```

`test_args_reach_am_verbatim` `set_logs` line:

```python
    set_logs(world, {"ok": True, "data": logs_data()})
```

`test_pretty_printed_am_output_becomes_one_line` first line:

```python
    envelope = {"ok": True, "data": logs_data()}
```

`test_refusal_passed_through_exit_0`, label above `refusal =`:

```python
    # synthetic: an am refusal envelope; no capture holds one.
    refusal = {"ok": False, "error": {"type": "UsageError",
                                      "message": "--attempt must be an integer"}}
```

`test_ok_wins_over_am_exit_code_and_stderr` `envelope =` line:

```python
    envelope = {"ok": True, "data": logs_data()}
    # synthetic: am stderr noise.
    set_raw(world, json.dumps(envelope) + "\n", code=3, stderr="warning: noisy\nmore noise\n")
```

Replace `test_large_output_not_trimmed`:

```python
def test_large_output_not_trimmed(world):
    # Whole-file snapshot: tail-limiting is the store's job, not this helper's.
    # synthetic: an attempt output longer than any capture.
    big = "".join("line %d of captured output\n" % i for i in range(5000))
    data = logs_data()
    data["artifacts"]["stdout"]["text"] = big
    envelope = {"ok": True, "data": data}
    set_logs(world, envelope)
    code, out = run(world)
    assert code == 0
    assert out["data"]["artifacts"]["stdout"]["text"] == big
    assert len(out["data"]["artifacts"]["stdout"]["text"].splitlines()) == 5000
```

Replace `test_control_and_unicode_text_round_trips`:

```python
def test_control_and_unicode_text_round_trips(world):
    # synthetic: control and non-ASCII text in an attempt's stdout and stderr.
    text = "a\nb\r\n\x1b[31mred\x1b[0m\tcafé ✓ 日本\n"
    data = logs_data()
    data["artifacts"]["stdout"]["text"] = text
    data["artifacts"]["stderr"]["text"] = text
    envelope = {"ok": True, "data": data}
    set_logs(world, envelope)
    code, out = run(world)  # still exactly one line
    assert code == 0
    assert out == envelope
```

Replace `test_am_does_not_inherit_stdin`:

```python
def test_am_does_not_inherit_stdin(world):
    # The helper's stdin is an open pipe that never sends EOF. An am that reads
    # stdin must get EOF at once (stdin is /dev/null), not block on that pipe.
    envelope = {"ok": True, "data": logs_data()}
    set_logs(world, envelope)
    write_exec(world["bin"] / "am",
               "#!/usr/bin/env python3\nimport os, sys\nsys.stdin.read()\n"
               "sys.stdout.write(open(os.path.join(os.environ['FAKE_AM_DIR'], 'logs.out')).read())\n")
    p = subprocess.Popen([sys.executable, SCRIPT, *ARGS], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                         env=env_for(world))
    try:
        code = p.wait(timeout=15)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait()
        pytest.fail("am blocked reading the helper's stdin")
    finally:
        p.stdin.close()
    lines = p.stdout.read().splitlines()
    p.stdout.close()
    p.stderr.close()
    assert code == 0
    assert len(lines) == 1
    assert json.loads(lines[0]) == envelope
```

Label the two bad-output parametrize lists (bodies and ids unchanged):

```python
# synthetic: am output that is not JSON.
@pytest.mark.parametrize("text,exit_code", [
```

```python
# synthetic: am JSON that is not an object or has no boolean ok.
@pytest.mark.parametrize("text", [
```

- [ ] **Step 6: Run the file to verify it passes**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_logs.py -q`
Expected: PASS, every test in the file (one more than before).
Then: `grep -n "LOGS_DATA\|hand-written\|\[\"stdout\"\] ==" tests/core/backend/runs/test_runs_logs.py`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add tests/core/backend/runs/test_runs_logs.py
git commit -m "test(runs-logs): serve the committed am logs capture from the fake am"
```

---

### Task 3: `test_runs_watch.py` replays the `am watch` captures

**Files:**
- Modify: `tests/core/backend/runs/test_runs_watch.py` (docstring L1-10, `MISSING` L62, builders L98-122, `run_helper` L138-144, tests L166-429, `start_helper` L369-373)
- Test: same file

**Interfaces:**
- Consumes: `tests/fixtures/am/watch-events.json`, `watch-hello.json` (read only).
- Produces (file-local):
  - `FIXTURES: str`, `fixture(name: str) -> object` — fresh `json.load`
  - `WATCHED: str` — `watch-events.json` `data.events[0]["run_id"]` (`20261004T204141Z-cb11063d`)
  - `hello(schema=1) -> {"line": dict}`
  - `ev(event: str = "phase_upsert", ts: str = "NOW") -> {"line": dict}`
  - `upsert(ts: str = "NOW") -> {"line": dict}`
  - `other(run_id, event="phase_upsert", ts="NOW", repo_dir=None, payload_keys=None, **extra) -> {"line": dict}`; `run_id=MISSING` / `ts=MISSING` drop the key.
  - `run_helper` / `start_helper` default argv `[str(world["proj"]), WATCHED]`.

- [ ] **Step 1: Write the failing test**

Insert in `tests/core/backend/runs/test_runs_watch.py` directly before the `# --- usage, am missing, clean exit ---` banner (current L164):

```python
# --- the lines are capture copies -----------------------------------------------

def test_lines_are_capture_copies():
    events = fixture("watch-events.json")["data"]["events"]
    for name in ["run_upsert", "subtask_upsert", "phase_upsert", "attempt_upsert"]:
        first = next(e for e in events if e["event"] == name)
        line = ev(name, "NOW")["line"]
        assert set(line) == set(first)
        assert line["ts"] == "NOW"
        assert {k: v for k, v in line.items() if k != "ts"} == \
            {k: v for k, v in first.items() if k != "ts"}
    # An unedited run_upsert is a WATCHED line: it is kept for argv, never adopted.
    assert upsert()["line"] == ev("run_upsert")["line"]
    assert upsert()["line"]["run_id"] == WATCHED
    assert hello() == {"line": fixture("watch-hello.json")["schema_1"]}
    assert hello(2) == {"line": fixture("watch-hello.json")["schema_2"]}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_watch.py::test_lines_are_capture_copies -q`
Expected: FAIL with `NameError: name 'fixture' is not defined`.

- [ ] **Step 3: Replace the module docstring**

Replace L1-10 with:

```python
"""runs-watch.py: `am watch --all --follow` turned into debounced change signals.

Hermetic: a fake `am` on a temp PATH replays FAKE_AM_DIR/script.json: a list of
steps (a JSON line, raw text, or a sleep), then a chosen stderr text and exit
code. The JSON lines are copies of the committed captures in tests/fixtures/am/;
a line no capture holds is labelled `synthetic:`. A step line's "ts" of "PAST"
(an hour ago) or "NOW" is stamped at the moment the fake am prints it, so PAST
is backlog and NOW is live for the helper, which records its start time before
spawning am. The fake am logs its argv to calls.log and its pid to pid. HOME and
XDG_* are temp. The real `am` and real data are never touched.
"""
```

- [ ] **Step 4: Add the loader and `WATCHED`**

Replace L62 (`MISSING = object()`) with:

```python
MISSING = object()
FIXTURES = os.path.join(ROOT, "tests", "fixtures", "am")


def fixture(name):
    """A fresh json.load of tests/fixtures/am/<name>, so an edit never reaches
    another call."""
    with open(os.path.join(FIXTURES, name)) as f:
        return json.load(f)


# The run of every captured journal line.
WATCHED = fixture("watch-events.json")["data"]["events"][0]["run_id"]
```

- [ ] **Step 5: Replace the line builders**

Replace L98-122 (`hello`, `ev`, `upsert`) with:

```python
def hello(schema=1):
    """The --follow hello: the captured schema_1 line, or the capture's derived
    schema_2 line for schema=2. synthetic: any other schema value is set on a
    schema_1 copy; MISSING leaves the key out."""
    lines = fixture("watch-hello.json")
    if type(schema) is int and schema in (1, 2):
        return {"line": lines["schema_%d" % schema]}
    line = lines["schema_1"]
    if schema is MISSING:
        del line["schema"]
    else:
        line["schema"] = schema
    return {"line": line}


def ev(event="phase_upsert", ts="NOW"):
    """The first captured journal line whose event is `event` (a WATCHED line).
    edited copy: ts is the fake am's PAST/NOW marker."""
    line = next(e for e in fixture("watch-events.json")["data"]["events"]
                if e["event"] == event)
    line["ts"] = ts
    return {"line": line}


def upsert(ts="NOW"):
    """The captured run_upsert, the first line of the run, carrying its repo_dir."""
    return ev("run_upsert", ts)


def other(run_id, event="phase_upsert", ts="NOW", repo_dir=None, payload_keys=None,
          **extra):
    """synthetic: a line the single-run capture has no copy of, built on a copy of
    ev(event): run_id set to the given id (MISSING drops it); an event no capture
    has laid on a phase_upsert copy; ts set to any value (MISSING drops it);
    repo_dir sets a run_upsert's payload.id and payload.repo_dir; payload_keys
    and extra add keys to the payload and the top level."""
    captured = {e["event"] for e in fixture("watch-events.json")["data"]["events"]}
    step = ev(event if event in captured else "phase_upsert")
    line = step["line"]
    line["event"] = event
    if run_id is MISSING:
        del line["run_id"]
    else:
        line["run_id"] = run_id
    if ts is MISSING:
        del line["ts"]
    else:
        line["ts"] = ts
    if repo_dir is not None:
        line["payload"]["id"] = run_id
        line["payload"]["repo_dir"] = repo_dir
    line["payload"].update(payload_keys or {})
    line.update(extra)
    return step
```

- [ ] **Step 6: Change the default argv**

In `run_helper` (L138-141) replace the docstring's first line and the `argv` line:

```python
def run_helper(world, args=None, timeout=30, **extra):
    """Run the helper until it exits (default argv: project root, run id WATCHED).
    Every stdout line must be JSON. Returns (exit code, parsed lines, stderr)."""
    argv = [str(world["proj"]), WATCHED] if args is None else args
```

In `start_helper` (L369-370):

```python
def start_helper(world, args=None):
    argv = [str(world["proj"]), WATCHED] if args is None else args
```

- [ ] **Step 7: Migrate the backlog / filter / unknown-input tests**

Replace `test_drops_hello_and_backlog` (L200-207):

```python
def test_drops_hello_and_backlog(world):
    # WATCHED's lines were written an hour before the helper started: backlog,
    # dropped. r2's line is live and proves the helper is reading at all.
    set_script(world, [hello(), ev(ts="PAST"), ev("subtask_upsert", ts="PAST"),
                       other("r2")])
    code, lines, _ = run_helper(world, [str(world["proj"]), WATCHED, "r2"])
    assert code == 0
    assert changed(lines) == [["r2"]]
```

Replace `test_live_event_for_watched_run_emits_changed` (L210-215):

```python
def test_live_event_for_watched_run_emits_changed(world):
    set_script(world, [hello(), ev()])
    code, lines, _ = run_helper(world)
    assert code == 0
    # Exactly this object: run ids only, no event contents.
    assert lines == [{"changed": [WATCHED]}]
```

Replace `test_filters_unwatched_runs` (L218-225):

```python
def test_filters_unwatched_runs(world):
    # WATCHED's live line is the positive control: the helper is reading, and
    # only the unwatched runs are dropped.
    set_script(world, [hello(), other("r9"), other("r8", "attempt_upsert"),
                       other("r7", "run_upsert", repo_dir="/somewhere/else"), ev()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert changed(lines) == [[WATCHED]]
```

Replace `test_ignores_unknown_events_and_keys` (L228-242):

```python
def test_ignores_unknown_events_and_keys(world):
    set_script(world, [
        hello(),
        raw("not json"),                               # synthetic: garbage lines
        raw("[1, 2]"),
        raw(""),
        other("r2", "future_upsert"),                  # unknown event: ignored
        other(MISSING),                                # no run_id: ignored
        other(WATCHED, payload_keys={"shiny": {"new": 1}},
              brand_new_key=[1, 2, 3]),                # extra keys: kept
    ])
    code, lines, err = run_helper(world, [str(world["proj"]), WATCHED, "r2"])
    assert code == 0
    assert "Traceback" not in err
    assert changed(lines) == [[WATCHED]]
```

Replace `test_missing_or_unparseable_ts_is_kept` (L245-250):

```python
def test_missing_or_unparseable_ts_is_kept(world):
    # Not provably backlog, so kept.
    set_script(world, [hello(), other(WATCHED, ts=MISSING), other("r2", ts="yesterday-ish")])
    code, lines, _ = run_helper(world, [str(world["proj"]), WATCHED, "r2"])
    assert code == 0
    assert changed(lines) == [sorted([WATCHED, "r2"])]
```

- [ ] **Step 8: Migrate the debounce and adoption tests**

Replace `test_debounce_batches_and_dedupes` (L255-260):

```python
def test_debounce_batches_and_dedupes(world):
    set_script(world, [hello(), ev(), other("r2"), ev(), other("r2", "attempt_upsert"),
                       ev("subtask_upsert"), pause(0.6)])
    code, lines, _ = run_helper(world, [str(world["proj"]), WATCHED, "r2"])
    assert code == 0
    assert changed(lines) == [sorted([WATCHED, "r2"])]
```

Replace `test_debounce_separate_windows` (L263-267):

```python
def test_debounce_separate_windows(world):
    set_script(world, [hello(), ev(), pause(0.6), ev(), pause(0.6)])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert changed(lines) == [[WATCHED], [WATCHED]]
```

In `test_debounce_continuous_stream_is_rate_limited` (L273-282) change the step and the per-line check only (timing bounds unchanged):

```python
    steps = [hello()]
    for _ in range(20):
        steps += [ev(), pause(0.05)]
```

```python
    assert all(ids == [WATCHED] for ids in got)
```

Replace the `set_script(...)` call in `test_new_run_upsert_in_project_is_adopted` (L293-301):

```python
    set_script(world, [
        hello(),
        other("n1", "run_upsert", repo_dir=repo_dir),          # this project: adopted and signalled
        other("n2", "run_upsert", repo_dir="/somewhere/else"),  # other repo: ignored
        other("n2"),                                            # still not watched
        pause(0.6),
        other("n1"),                                            # adopted: kept from now on
        pause(0.6),
    ])
```

(its `run_helper(world, [root])` call and `assert changed(lines) == [["n1"], ["n1"]]` are unchanged).

- [ ] **Step 9: Migrate the error-path and stopping tests**

`test_schema_mismatch` (L309-312): decorator unchanged; replace the `set_script` line:

```python
    set_script(world, [hello(schema), ev(), pause(8)])
```

`test_exit_3_corrupt_journal` (L324-333):

```python
def test_exit_3_corrupt_journal(world):
    # synthetic: am's stderr text for a corrupt journal.
    set_script(world, [hello(), ev()], exit=3,
               stderr="am watch: journal line 4 of run r1 is not JSON\n")
    code, lines, _ = run_helper(world)
    assert code != 0
    assert len(lines) == 2, lines
    assert lines[0] == {"changed": [WATCHED]}  # the pending batch is flushed first
    assert lines[1]["ok"] is False
    assert lines[1]["error"]["type"] == "CorruptJournal"
    assert "journal line 4 of run r1 is not JSON" in lines[1]["error"]["message"]
```

`test_other_exit_is_helper_error` (L336-344):

```python
def test_other_exit_is_helper_error(world):
    # synthetic: am's stderr text for a crash.
    set_script(world, [hello(), ev()], exit=1, stderr="boom\n")
    code, lines, _ = run_helper(world)
    assert code != 0
    assert len(lines) == 2, lines
    assert lines[0] == {"changed": [WATCHED]}
    assert lines[1]["ok"] is False
    assert lines[1]["error"]["type"] == "HelperError"
    assert "boom" in lines[1]["error"]["message"]
```

Label the two refusal envelopes (bodies unchanged):

```python
def test_refusal_exit_3_is_corrupt_journal(world):
    # synthetic: an am refusal envelope; no capture holds one.
    envelope = {"error": {"message": "run r1: journal line 2 is not JSON",
```

```python
def test_refusal_other_exit_is_reemitted(world):
    # synthetic: an am refusal envelope; no capture holds one.
    envelope = {"error": {"message": "something else", "type": "OddError"}, "ok": False}
```

`test_signal_stops_am_and_exits_zero` (L395-399):

```python
    set_script(world, [hello(), ev(), pause(30)])
    p = start_helper(world)
    try:
        first = p.stdout.readline()  # sync point: am is running, helper is streaming
        assert json.loads(first) == {"changed": [WATCHED]}
```

`test_closed_stdout_exits_zero` (L415):

```python
    set_script(world, [hello(), ev(), pause(0.6), ev(), pause(30)])
```

- [ ] **Step 10: Run the file to verify it passes**

Run: `python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q`
Expected: PASS, every test in the file (one more than before).
If a debounce test fails on its timing bound: do not loosen it; stop and report the failure (Review Focus 5).
Then: `grep -nE '"r1"|ev\("r[0-9]|upsert\("|hand-written' tests/core/backend/runs/test_runs_watch.py`
Expected: no output (the synthetic texts mention `run r1` unquoted, and `ev("run_upsert")` does not match `ev("r[0-9]`).

- [ ] **Step 11: Commit**

```bash
git add tests/core/backend/runs/test_runs_watch.py
git commit -m "test(runs-watch): replay the committed am watch captures from the fake am"
```

---

### Task 4: Full verification (no code change)

- [ ] **Step 1: Run the runs tier**

Run: `python3 -m pytest tests/core/backend/runs -q`
Expected: `281 passed`.

- [ ] **Step 2: Run the whole suite**

Run: `bash tests/run.sh`
Expected: pytest all green (including `tests/architecture` and `tests/contract`), every QML test `Totals: … 0 failed`, exit 0.

- [ ] **Step 3: Check the diff touches only the three test files**

Run: `git diff --stat main... -- . ':!docs/superpowers'`
Expected: exactly `tests/core/backend/runs/test_runs_snapshot.py`, `test_runs_logs.py`, `test_runs_watch.py`.
Run: `git status --porcelain tests/fixtures core`
Expected: no output.

No commit in this task (nothing changed).
<!-- task-pipeline: validated -->
