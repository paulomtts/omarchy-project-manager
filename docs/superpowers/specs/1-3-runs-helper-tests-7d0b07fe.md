# 1.3 Runs helper tests: the fake am serves the real fixtures — design

Card `7d0b07fe`, a subtask of story `6596351c` ("Real am fixtures and contract
tests"), blocked by `9f7e9956` (1.2, the QML fixture loader). Parent spec:
`docs/superpowers/specs/2026-10-05-align-run-model-design.md` (below:
**parent**). Work breakdown item 1 (parent L321-323): this subtask is "the
helpers' fake am serving the fixtures" only.

## Goal

The pytest suites of the three read-only runs helpers stop feeding their fake
`am` hand-written payloads in the guessed S1 shape (parent L133). Each fake am
serves the committed captures in `tests/fixtures/am/` instead, loaded with
`json.load`. Any payload that no capture contains is built on a fresh copy of a
capture, or is plain garbage, and carries a `synthetic:` comment. Each existing
test keeps its name and its meaning. The three files stay green on the
helpers as they are today. No file outside the three test files changes.

## Inherited constraints

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

## Fixture facts this design relies on (checked 2026-10-05)

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

## Behavior: what each file must do after the change

### Shared rules (all three files)

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

### `tests/core/backend/runs/test_runs_snapshot.py`

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

### `tests/core/backend/runs/test_runs_logs.py`

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

### `tests/core/backend/runs/test_runs_watch.py`

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

## Error paths

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

## Tests (all in the pytest tier)

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

## Out of scope

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

## Review focus for the planner

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

## Verification

- `python3 -m pytest tests/core/backend/runs -q` (where pytest is not installed, `uv run --with pytest python3 -m pytest …`, as `tests/run.sh` does): green. The baseline is 278
  passed; after the change it is 281, with the three new assertions.
- `bash tests/run.sh`: green, including `tests/architecture` and
  `tests/contract`.
- `git diff --stat main...` touches only the three test files (plus this spec
  and its plan).
