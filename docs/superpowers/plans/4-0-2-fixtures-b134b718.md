# 4.0.2 Fixtures: regenerate `tests/fixtures/am` from the new `am` and add `events.json` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every capture in `tests/fixtures/am/` with a capture of the installed am (agent-manager 0.2.0) taken on a scratch store, add `events.json`, pin the new keys exactly in `tests/contract/test_am_fixtures.py`, and retarget the consumer tests' captured literals so `bash tests/run.sh` is green.

**Architecture:** Four throwaway scripts under `/tmp/am-capture/` (never committed) do the work: `capture.py` drives five real `am run --milestone` runs on one scratch store with agent-manager's fake `claude` and saves each am command's raw stdout; `finalize.py` rewrites the scratch root to `/home/user`, truncates `watch-events.json`, adds `_note`/`_am_runs_row` and writes the ten fixtures; `check_fixtures.py` asserts the spec's per-capture structure (B3) and that no real path leaked; `retarget.py` pairs each old capture with the new one path by path (the boards reproduce the old captures' exact structure) and rewrites every old captured id, branch, path, timestamp, host and pid in the consumer tests with the value playing the same role. The contract test is tightened first and fails against the old captures.

**Tech Stack:** Python 3 (stdlib only for the scripts), pytest (run as `uv run --with pytest python3 -m pytest ...`; the system `python3` has no pytest), QML/qmltestrunner (`/usr/lib/qt6/bin/qmltestrunner`), the installed `am` (agent-manager 0.2.0), `brd`, `git`.

**Spec:** `docs/superpowers/specs/4-0-2-fixtures-b134b718.md` (reproduced in full in the "Spec" section below).

## Global Constraints

- am is called only as argv lists; nothing reads `am.db`, journals or the data-dir layout, the capture included.
- Captures come from a throwaway store: `HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` under `/tmp/am-capture/scratch/home`; never `~/.local/share/agent-manager`, never the real brd board. `am migrate` is never run.
- Every fixture is `json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n"`: the format of today's files (measured: every committed fixture round-trips with `indent=2`, `logs-attempt.json` only with `ensure_ascii=False` because it holds non-ASCII text; the spec's "`indent=1` as today" means "as today").
- Allowed edits to am's stdout, and only these: the scratch root rewritten to `/home/user`; `watch-events.json` truncated to a prefix; `_note` on every file and `_am_runs_row` on the three e2e status captures.
- Every `_note` names `agent-manager 0.2.0`, the exact am command, the scenario, the capture date and every edit applied. `watch-hello.json`'s `schema_1` stays the historical am 0.1.0 capture and its note says so.
- No file under `core/` or `ui/` changes; `tests/contract/test_am_shapes.py` is not edited (if a capture contradicts it, stop and report).
- Synthetic edge cases are labelled `synthetic:`; docstrings and comments state the contract only.
- The four scripts live in `/tmp/am-capture/` and are never committed.
- Never `pkill`/`killall`; the scripts only signal processes they started, through their own `Popen` handles.
- `bash tests/run.sh` green, including `tests/architecture`.

## Review Focus

1. A capture that takes longer than the fake's 20 s hold (`RENDEZVOUS_TIMEOUT = 20.0`, `fake_claude.py:272`) → the held explore attempt ends `harness_error` and `status-started.json` no longer shows a live attempt; `check_fixtures.py` (Task 1 Step 10) fails on `explore ... attempts[0].status` instead of committing a wrong capture.
2. A real or scratch path leaking into a committed fixture (`/tmp/...`, `/home/<you>/...`) → `check_fixtures.py` (Task 1 Step 10) fails naming the file and the path.
3. Capturing on a machine whose hostname or `am` pid differ from the old capture's (`mtts-desktop`, `3736962`) → `retarget.py` maps the `lease.host` and `lease.pid` values too, so `tst_runs.qml`'s lease scalars follow the capture (Task 1 Step 13; the mapping printout lists them).
4. Consumers that compare a whole fixture to what a fake am served, now that every fixture has a `_note` and `runs.json` data has `as_of_seq`/`store_id` → the two whole-envelope comparisons are narrowed to am's envelope (Task 1 Step 15) and pinned by `test_logs_data_is_the_capture` and `test_fake_am_serves_the_captures`.
5. The 4.0.1 stub helpers silently modelling the new am once `schema_2` gains `head`/`cursor_reset`/`store_id` → `stub_runs_data`/`stub_hello` pop them and `test_stubs_model_an_older_am` (Task 1 Step 2) pins that.

---

## Spec

### 4.0.2 Fixtures: regenerate `tests/fixtures/am` from the new `am` and add `events.json` — design

Card: `b134b718` (subtask of story `0cf1ca04`, 4.0 Contract; blocked by 4.0.1 `f1b95771`, landed on
this branch as `4337424`/`804001f`). Parent design:
`docs/superpowers/specs/2026-10-06-am-snapshots-cursors-design.md` in the main checkout (untracked
there; cited below as **M4** with line numbers). Sibling spec already in this tree:
`docs/superpowers/specs/4-0-1-contract-test-the-f1b95771.md` (cited as **4.0.1**).

### Purpose

Every later M4 subtask (4.0.3 `normalizeRun`, 4.1.1 watch helper, 4.1.2 snapshot helper, 4.1.3
RunStore) builds its test inputs from `tests/fixtures/am/` (card: "Test inputs of am output come
from tests/fixtures/am/, never hand-written"). Today every capture is from am 0.1.0 and carries
none of `as_of_seq`, `store_id`, `project`, `story_id`, `gseq`, `head`, `cursor_reset`. This card
replaces them with captures of the installed am (agent-manager 0.2.0), adds `events.json` (an
`am events RUN` envelope with `head`), and tightens the fixture contract tests so the new keys are
pinned exactly (M4 §"Testing", lines 209-215; M4 §"Order and sizing", line 255; M4 line 269:
4.1.3 depends on these fixtures).

### Inherited constraints

- am is called only as argv lists; nothing reads `am.db`, journals or the data-dir layout
  (M4 §"Non-goals", lines 58-59). This includes the capture procedure.
- Fixtures are recorded from a throwaway data dir with the fake harness and a scratch repo, never
  from the migrated real data, so no real paths or prompts enter the repo (M4 §"Dev safety",
  lines 190-191). `am migrate` is never run against `~/.local/share/agent-manager` (M4
  §"Decisions", line 276: migrate is explicit).
- Fixture notes name the am version and how the capture was made (M4 line 214; card).
- Key-set changes: `project` on a runs row, `as_of_seq` on `runs` and `status`, `gseq` on a watch
  line, `head` and `cursor_reset` on the hello (M4 lines 212-214), plus `store_id` on the hello
  (M4 §"Decisions", lines 273-275; card).
- The hello stays at schema 2 with additive `head`, `gseq`, `cursor_reset`, `store_id` (M4 lines
  273-275). A hello without `head` is the old am (M4 §"Errors", line 198).
- `am events RUN` envelope has `head` (M4 §"Design" table, line 75).
- `am logs` consumption unchanged (M4 line 63): `logs-attempt.json` is re-captured but its key
  set does not change.
- Existing tests that consume the fixtures stay green; adjust only what the regeneration forces
  (card).
- Synthetic edge cases are labelled `synthetic:`; docstrings and comments state the contract only
  (card).
- `bash tests/run.sh` green, including `tests/architecture` (card; `docs/architecture.md`
  layering).

### Observed shapes of the installed am (measured 2026-10-08)

Measured by the spec author on a scratch store (`HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` under a
fresh temp dir; PATH holding only `am`, `brd`, `git`; one story run that escalates at explore
because no agent CLI is reachable). The planner must re-measure on the real capture; these are the
expected exact key sets:

| output | level | key set |
|---|---|---|
| `am runs` | `data` | `as_of_seq`, `runs`, `store_id` |
| `am runs` | row | today's 11 keys + `project`, `story_id` |
| `am runs` | `row.project` | `id`, `repo_dir` |
| `am status RUN` | `data` | `run`, `stories`, `rows`, `control`, `integrity` + `as_of_seq`, `store_id`, `warnings` |
| `am status RUN` | `data.run` | today's 7 keys + `story_id` |
| `am status RUN` | stories / subtasks / phases / rows / control | unchanged |
| `am events RUN` | `data` | `events`, `head` |
| `am events RUN`, `am watch RUN` | event | today's 9 keys + `gseq` |
| `am watch RUN` | `data` | `events` (no `head`) |
| `am watch --all --follow` | hello | `am`, `cursor_reset`, `event`, `head`, `runs_dir`, `schema`, `store_id` |

Facts that the notes and tests must reflect:

- `uv tool list` reports `agent-manager v0.2.0`; the hello's `am` field prints `"0.1.0"`
  (`agent_manager/__init__.py` still says `0.1.0`). Captures keep the printed value; notes say
  "agent-manager 0.2.0 (its hello reports am 0.1.0)".
- `data.warnings` on status is a list of strings (observed:
  `["isolation: none (bwrap and unshare are unavailable): agents can signal the engine"]`).
- `story_id` is present on every runs row and on the status run, `null` for a milestone run.
- The new journal has event kinds the old one lacked (`lease_acquired` is a run's first line, and
  `control_*`, `lease_*`, `claim_conflict` exist, M4 lines 80-81). `run_upsert` is no longer the
  first line of a run.
- `head` / `as_of_seq` are machine-wide (store-wide) and small on a scratch store.

### Behavior

#### B1. The fixture set

`tests/fixtures/am/` holds exactly these ten files, each pretty-printed with sorted keys
(`json.dumps(obj, indent=1, sort_keys=True)` as today) and a trailing newline:

`runs.json`, `status-started.json`, `status-done.json`, `status-escalated.json`,
`status-escalated-integrate.json`, `status-done-integrate.json`, `watch-events.json`,
`watch-hello.json`, `logs-attempt.json`, `events.json` (new).

#### B2. Provenance and edits

- Every value comes from the stdout of one am command run on the capture store. Allowed edits,
  and only these: (a) the scratch root is rewritten so paths read `/home/user/...`;
  (b) `watch-events.json` is truncated to a prefix of its events (as today); (c) the `_note` key,
  and `_am_runs_row` on the three captures that carry it, are added. Nothing else is edited.
- Every one of the ten files has a top-level `_note` string (today only five do). Each note
  names `agent-manager 0.2.0`, the exact am command printed, the scenario it came from (fake
  harness, scratch repo, which run), the capture date, and every edit from the list above that was
  applied. `watch-hello.json`'s note also says `schema_1` is the historical am 0.1.0 capture (B5).
- `status-escalated.json`, `status-escalated-integrate.json` and `status-done-integrate.json`
  keep `_am_runs_row`: that run's row from `am runs` taken in the same capture session.

#### B3. Capture scenario (what each capture must show)

The captures replace values that many consumer tests pin (run ids, card ids, row indexes, rollup
counts). To keep each consumer assertion's intent available, the capture store must reproduce the
structure the old captures had. The capture store is a scratch dir: `HOME=<root>/home`,
`XDG_DATA_HOME=<root>/home/.local/share`, `XDG_STATE_HOME=<root>/home/.local/state`; the scratch
repo is `<root>/home/Code/omarchy-project-manager` on branch `main` with a brd board; the agent
CLI is the fake harness from `~/Code/agent-manager/tests/e2e/fake_claude.py` copied as `claude`
onto PATH (wiring per `~/Code/agent-manager/tests/e2e/conftest.py`: `fake_claude_bin`,
`FAKE_REVIEW_FAIL_MARKER`, `FAKE_HOLD_DIR_ENV`/`FAKE_CLAUDE_HOLD_PHASE`, `FAKE_RESOLVER_ENV`;
scenarios per `test_milestone_run.py:86` and `test_integrate.py:209,296`). Rewriting `<root>/home`
to `/home/user` then yields the same path shapes as the old captures (`/home/user/Code/...`,
`/home/user/.local/share/agent-manager/runs`). All five run scenarios use one store, so
`store_id` is the same in every capture and `head` increases across them in capture order.

| file | command | required structure |
|---|---|---|
| `runs.json` | `am runs --repo-dir <repo>` taken while the started run is held | ≥ 2 rows; row 0 `status: "started"`, `workflow: "milestone"`, a non-null `lease` with `live: true`, a non-null `progress.current`; row 1 `status: "done"`, `lease: null`, `progress.current: null`; row 0's id is `status-started.json`'s `data.run.id`, row 1's id is `status-done.json`'s |
| `status-started.json` | `am status <started run>` while held | milestone run with ≥ 2 real stories; ≥ 1 subtask `done`, exactly 1 subtask `started` with phase `explore` attempt 1 `started` (the hold), ≥ 1 subtask pending; `control.lease` non-null; reaches attempts |
| `status-done.json` | `am status <done run>` | milestone run, ≥ 2 stories all done, every subtask done; `stories[0].subtasks[0].phases[1].attempts[0]` exists |
| `status-escalated.json` | `am status <run>` | a milestone run stopped by a review failure (`FAKE_REVIEW_FAIL_MARKER`): one subtask escalated at review, ≥ 1 done, ≥ 1 pending |
| `status-escalated-integrate.json` | `am status <run>` | a milestone run escalated at Integrate (`test_integrate.py:296` scenario); carries the synthetic `integrate` story |
| `status-done-integrate.json` | `am status <run>` | a milestone run done through an Integrate with a resolver (`test_integrate.py:248` scenario); carries the resolver's synthetic story with a real card id |
| `logs-attempt.json` | `am logs <done run> <card> --phase review` | `status: "ok"`, `exit_code: 0`; `prompt`, `result`, `stdout` present with text, `stderr` absent |
| `watch-events.json` | `am watch <done run>` (no `--follow`), truncated | first event's `run_id` is the done run; the kept prefix contains at least one each of `run_upsert`, `story_upsert`, `subtask_upsert`, `phase_upsert`, `attempt_upsert`; every `run_upsert` payload has `repo_dir` |
| `events.json` | `am events <done run> --limit 60` | unedited page: `data.events` non-empty, `data.head` an int ≥ the last event's `gseq`; events in strictly increasing `gseq` |
| `watch-hello.json` `schema_2` | first line of `am watch --all --follow --from-now` | the new hello: `schema: 2`, `head` an int, `cursor_reset: false`, `store_id` a string |

`--limit 60` is a real page, so `events.json` needs no truncation edit.

#### B4. Fixture contract (`tests/contract/test_am_fixtures.py`)

Key sets (keys starting `_` ignored, as today):

- `RUN_ROW_KEYS` gains `project` and `story_id`; a new check pins every row's `project` to
  exactly `PROJECT_KEYS` (`id`, `repo_dir`), on `runs.json` rows and on every `_am_runs_row`.
- `RUNS_DATA_KEYS = {as_of_seq, runs, store_id}` is checked on `runs.json` `data` (no data-level
  check exists today). `as_of_seq` is a non-negative int (not a bool); `store_id` a non-empty
  string.
- `STATUS_DATA_KEYS` gains `as_of_seq`, `store_id`, `warnings`; `as_of_seq` non-negative int,
  `store_id` non-empty string, `warnings` a list of strings, on every status fixture.
- `STATUS_RUN_KEYS` gains `story_id`.
- `EVENT_KEYS` gains `gseq`; on both `watch-events.json` and `events.json`, every `gseq` is an int
  and the sequence is strictly increasing.
- `EVENTS_DATA_KEYS = {events, head}` on `events.json`; `head` non-negative int ≥ the last
  event's `gseq`. `WATCH_DATA_KEYS` stays `{events}`.
- Hello: `HELLO_KEYS = {am, cursor_reset, event, head, runs_dir, schema, store_id}` for
  `schema_2` (`schema == 2`, `head` non-negative int, `cursor_reset` a bool, `store_id` a
  non-empty string); `HELLO_V1_KEYS = {am, event, runs_dir, schema}` for `schema_1`
  (`schema == 1`, no `head`). `HELLO_FILE_KEYS` stays `{schema_1, schema_2}`.
- Unchanged: stories, subtasks, phases, attempts, rows, control, lease, progress, logs key sets
  and the run/attempt status vocabularies.

Lists and cross-capture rules:

- `FIXTURE_NAMES` adds `events.json`; it goes through `test_every_fixture_exists_and_parses` and
  `test_envelopes_are_ok_data`.
- `NOTED_FIXTURES` becomes all of `FIXTURE_NAMES`; a test asserts every `_note` is a string
  containing `agent-manager 0.2.0`. `_am_runs_row` stays on exactly `E2E_FIXTURES`.
- One store: every `store_id` in `runs.json`, the status fixtures and the `schema_2` hello is the
  same string.
- `runs.json` row 0 / row 1 ids equal `status-started.json` / `status-done.json` `data.run.id`
  (the pairing `tst_runs_real_data.qml:60-62` relies on).
- `LIVE_EXTRA` shrinks to empty or is removed: the live check (from 4.0.1) compares live output to
  the capture key sets exactly. `test_live_allowance_is_on_the_runs_row_status_run_and_status_data_only`
  and the `LIVE_EXTRA` uses in `test_live_status_check_rejects_a_status_outside_the_vocabularies`
  are rewritten to the exact-match contract (a live row missing `project` or with an unknown key
  fails naming it). The module docstring's live-check paragraph is updated to match.
- The 4.0.1 stub helpers `stub_runs_data` / `stub_hello` keep producing an old-am payload: they
  pop `as_of_seq` (and `store_id`) from runs data and `head`, `cursor_reset`, `store_id` from the
  hello, so every 4.0.1 stub test keeps its meaning and stays green. The "missing as_of_seq /
  head" messages are unchanged.

#### B5. `watch-hello.json`

- `schema_2` is replaced by the real new-am capture (B3).
- `schema_1` keeps today's real am 0.1.0 capture unchanged: no am prints schema 1 any more, and
  it is the only real hello without `head`, which 4.1.1's SchemaMismatch test needs and
  `test_runs_watch.py:78-82` (`HELLO1`) and `tst_run_store.qml:468-470` (`helloLine("schema_1")`)
  read. Its note says so; it is the one capture not taken from 0.2.0, and the "names
  agent-manager 0.2.0" rule is satisfied by the file's single note covering both keys.

#### B6. QML loader (`tests/helpers/tst_am_fixtures.qml`)

`amFixtures.js` needs no change (`load(name)` is generic). `tst_am_fixtures.qml`:

- `names` adds `"events.json"` (so `test_every_fixture_loads` covers it).
- A new test: `F.load("events.json")` has `ok === true`, `data.events` a non-empty array, and
  `typeof data.head === "number"`.
- `test_loads_real_content` and `test_underscore_keys_are_kept` keep passing (schema_2 schema 2,
  `_note` string).

#### B7. Consumers

Tests that read the fixtures and assert captured values change only those values:

- `tests/core/domain/tst_runs.qml` (≈ 18 literal ids, row indexes, rollup count strings,
  lease scalars), `tests/ui/tst_runs_real_data.qml` (`startedRun`, `doneRun`, `milestone`,
  `subRunning`, lines 20-28, 187-189), `tests/core/stores/tst_run_store.qml` (`openCard`, line 20),
  `tests/ui/screens/tst_run_detail_screen.qml:128`, `tests/ui/tst_runs_flow.qml:205`,
  `tests/core/backend/runs/test_runs_watch.py`, `test_runs_snapshot.py`, `test_runs_logs.py`.
- Rule: a literal copied from an old capture is replaced by the corresponding value of the new
  capture (the run, card, row or count playing the same role in the B3 structure). Each assertion
  keeps its subject and intent; no assertion is deleted or weakened, and no behaviour test changes
  its input source. A comment describing the old capture (e.g. "subtask with 14 rows") is updated
  to the new fact.
- `test_runs_watch.py`: `HELLO1`/`HELLO2` still build `{"hello": {"schema", "am"}}` from the
  capture; `HELLO2["am"]` stays `"0.1.0"` because that is what the new am prints. `upsert()`'s
  docstring ("the first line of the run") is corrected: `run_upsert` is no longer first.
  `WATCHED` stays "the first captured event's `run_id`". The `other()` helper's "an event no
  capture has" cases keep using event names absent from the new capture.
- No file under `core/` or `ui/` changes. If a consumer fails because plugin code mishandles a
  new key (not a changed value), that is out of scope: stop and report it (it belongs to 4.0.3 or
  4.1.x).

#### B8. Docs

`docs/architecture.md:254-256`, the list of fixture files, adds `events.json` (an `am events RUN`
page with `head`). No other doc change (the run-monitor sections are 4.4.1).

### Error paths

| case | behaviour |
|---|---|
| a fixture misses a new key (e.g. a runs row without `project`) | the contract test fails naming the file, the level (`runs[0]`) and `missing ['project']` (existing `assert_keys` message) |
| a fixture has an unknown key | fails naming it under `extra` |
| `events.json` absent or not JSON | `test_every_fixture_exists_and_parses[events.json]` fails naming it; QML `F.load` throws naming it |
| `head` < last `gseq`, or `gseq` not strictly increasing | fails naming the file and the offending values |
| two captures carry different `store_id` | fails naming both files |
| a note lacks `agent-manager 0.2.0` | fails naming the file |
| live am lacks a capture key or prints an unknown one | live check fails naming the level and key (no allowance after B4) |
| live am absent | live check skips (unchanged) |

### Tests

| test | tier | why that tier |
|---|---|---|
| `test_am_fixtures.py`: `RUN_ROW_KEYS` with `project`/`story_id`, `project` exact keys on every row and `_am_runs_row` | contract (pytest, `tests/contract`) | pins the recorded am shape; no plugin code involved |
| `test_am_fixtures.py`: `runs.json` data key set and `as_of_seq`/`store_id` types | contract | same |
| `test_am_fixtures.py`: status data keys incl. `as_of_seq`, `store_id`, `warnings` and types; status run `story_id` | contract | same |
| `test_am_fixtures.py`: `EVENT_KEYS` with `gseq` on both event fixtures; strictly increasing `gseq` | contract | same |
| `test_am_fixtures.py`: `events.json` data `{events, head}`, `head ≥` last `gseq` | contract | same |
| `test_am_fixtures.py`: hello `schema_2` new key set and types; `schema_1` old key set, no `head` | contract | same |
| `test_am_fixtures.py`: every fixture has a `_note` naming `agent-manager 0.2.0`; `_am_runs_row` only on the three | contract | provenance is part of the fixture contract (card) |
| `test_am_fixtures.py`: one `store_id` across captures; runs rows 0/1 pair with status-started/done | contract | cross-file invariants consumers rely on |
| `test_am_fixtures.py`: `events.json` in parse and ok-envelope parametrized tests | contract | same |
| `test_am_fixtures.py`: live check exact match (no `LIVE_EXTRA`), rewritten allowance tests; 4.0.1 stub tests unchanged and green | contract | the live check is the gate that the installed am still matches the captures |
| `tst_am_fixtures.qml`: `events.json` in `names`; loads with a numeric `head` | QML unit (qmltestrunner, `tests/helpers`) | the loader is QML-side; the card names it |
| consumer suites (`tst_runs.qml`, `tst_run_store.qml`, `tst_runs_real_data.qml`, `tst_runs_flow.qml`, `tst_run_detail_screen.qml`, `tests/core/backend/runs/*`) green with literals retargeted | their existing tiers | regression: proves the new captures carry every structure the plugin tests need |
| `tests/architecture` green | architecture | card rule |

TDD order: change the contract key sets and add the new contract and QML tests first, run them
against the old captures (they fail: missing `project`, `as_of_seq`, `gseq`, `head`, no
`events.json`, notes), then capture and write the new fixtures, then retarget consumer literals
until `bash tests/run.sh` is green.

### Out of scope

- `tests/contract/test_am_shapes.py`: it already pins the new key sets against the installed am
  (`d62fb65`); this card changes only `test_am_fixtures.py` (the card's mention of
  `test_am_shapes.py` is satisfied by that earlier commit; do not edit it unless the regenerated
  captures contradict it, in which case stop and report).

- Any change under `core/` or `ui/`: `normalizeRun` tolerating `project` is 4.0.3; the watch
  helper reading `head`/`gseq` is 4.1.1; `runs-snapshot.py` forwarding `as_of_seq` is 4.1.2;
  RunStore nudges 4.1.3; `store_id` reset 4.1.4 (M4 lines 256-260).
- A committed capture script; the notes carry the method.
- Captures of `am runs --all-projects`, `am events --escalations`, `--tail`, `--before-seq`,
  `am logs --follow`: no current consumer reads them; the 4.1.x cards add their own captures if
  they need them.
- The spec retarget docs PR (4.2) and the dropped 4.3 behaviour cards (M4 lines 245-250).
- Run-monitor docs beyond the one fixture-list line (4.4.1).
- Fixing the stale `__version__` in agent-manager.

### Risks for the planner

- The started-run capture needs a run still in flight: hold the fake harness at `explore`
  (`FAKE_CLAUDE_HOLD_DIR`, `FAKE_CLAUDE_HOLD_PHASE=explore`), take `am runs` and
  `am status <started run>` while held, then release or `am cancel` it. Capture `runs.json` while
  the done run already exists so the order is started (newest) then done.
- `am runs` lists newest first, and `runs.json` must have the started run as row 0 and the done
  run as row 1 (B3). Launch order on the one store is therefore: the three E2E runs (escalated,
  escalated-integrate, done-integrate) first, then the done run, then the held started run last;
  `status-*` and `watch`/`events`/`logs` captures of the earlier runs can be taken at any time
  (they address a run id). If a scenario needs its own repo state, reset the scratch repo between
  launches; never launch an E2E run after the done run.
- After path rewriting, grep the ten files for the scratch root and for any `/home/<real user>`
  or `/tmp/` path; there must be none.
- `status-done.json` today is 180 KB from a 10-subtask milestone; the new one may be much
  smaller. `tst_runs.qml` assertions about row counts take the new values (B7 rule).

---

## File Structure

Committed (all under the worktree root):

- Modify: `tests/contract/test_am_fixtures.py` — the fixture contract: new key sets (`project`, `story_id`, `as_of_seq`, `store_id`, `warnings`, `gseq`, `head`, `cursor_reset`), `events.json`, notes on every capture, one `store_id`, run pairing, exact live check (no `LIVE_EXTRA`), 4.0.1 stubs still an older am.
- Modify: `tests/helpers/tst_am_fixtures.qml` — `events.json` in `names`, a load test with a numeric `head`.
- Replace: `tests/fixtures/am/{runs,status-started,status-done,status-escalated,status-escalated-integrate,status-done-integrate,watch-events,watch-hello,logs-attempt}.json`.
- Create: `tests/fixtures/am/events.json`.
- Modify (captured literals retargeted by `retarget.py`): `tests/core/domain/tst_runs.qml`, `tests/ui/tst_runs_real_data.qml`, `tests/core/stores/tst_run_store.qml`, `tests/ui/screens/tst_run_detail_screen.qml`.
- Modify (hand edits the regeneration forces): `tests/core/domain/tst_runs.qml` (log tail of the real attempt, two comments), `tests/core/stores/tst_run_store.qml` (log line count), `tests/core/backend/runs/test_runs_logs.py`, `tests/core/backend/runs/test_runs_snapshot.py`, `tests/core/backend/runs/test_runs_watch.py` (docstring).
- Modify: `docs/architecture.md` — the fixture list names `events.json`.

Throwaway (never committed, `/tmp/am-capture/`): `capture.py`, `finalize.py`, `check_fixtures.py`, `retarget.py`, `contract.diff`, `old-fixtures/`, `scratch/`, `raw/`.

The work is one task: the tightened contract only passes on the new captures, and the new captures only leave the suite green once the consumer literals are retargeted, so every intermediate state is red and a single commit carries it.

Why the consumer retarget is mechanical: the capture boards reproduce the old captures' structure exactly (measured on two trial captures, 2026-10-08): `status-started` 4 stories of 2/3/1/2 subtasks, 44 rows, 10 claims, the 4th subtask held at explore attempt 1; `status-done` 4 stories of 2/3/1/4 subtasks, 140 rows; `status-escalated` 3 stories, 40 rows, b1 failed at review; `status-escalated-integrate` 2 stories, 28 rows; `status-done-integrate` 2 stories plus `integrate`, 30 rows; `runs.json` 2 rows with progress 1/4 stories 3/8 subtasks and 4/4, 10/10; the logs capture is `status-done` `stories[0].subtasks[0]` review attempt 1, as before; story titles and branch prefixes (`dsp`, `ctl`, `m3`) are the old ones. So a value at a JSON path of an old capture plays the same role as the value at that path of the new one, and every count, index and title the consumers assert stays true. What does change by value: run ids, card ids, milestone ids, branches, worktree paths, timestamps, the lease host and pid — `retarget.py` maps exactly those. What changes by fact: the fake harness prints one stdout line (`fake-claude ok phase=review`, `fake_claude.py:962`) where the old real attempt printed 19, and a runs row has 13 keys, not 11; Step 15 retargets those by hand.

---

### Task 1: Regenerate the am captures under a tightened contract

**Files:**
- Modify: `tests/contract/test_am_fixtures.py`
- Modify: `tests/helpers/tst_am_fixtures.qml`
- Replace: `tests/fixtures/am/*.json` (9 files); Create: `tests/fixtures/am/events.json`
- Modify: `tests/core/domain/tst_runs.qml`, `tests/ui/tst_runs_real_data.qml`, `tests/core/stores/tst_run_store.qml`, `tests/ui/screens/tst_run_detail_screen.qml`, `tests/core/backend/runs/test_runs_logs.py`, `tests/core/backend/runs/test_runs_snapshot.py`, `tests/core/backend/runs/test_runs_watch.py`
- Modify: `docs/architecture.md:254-256`

**Interfaces:**
- Consumes: the installed `am` (agent-manager 0.2.0) and `brd` on PATH; `~/Code/agent-manager/tests/e2e/fake_claude.py` and `~/Code/agent-manager/tests/e2e/test_integrate.py` (its `CHECK_SOURCE`); `tests/helpers/amFixtures.js` `load(name)` (unchanged).
- Produces (for 4.0.3, 4.1.x): the ten fixtures with the keys pinned by `test_am_fixtures.py`: `runs.json` `data` = `{as_of_seq, runs, store_id}`, rows with `project` `{id, repo_dir}` and `story_id`; status `data` with `as_of_seq`, `store_id`, `warnings` and `data.run.story_id`; events with `gseq`; `events.json` `data` = `{events, head}`; `watch-hello.json` `schema_2` = `{am, cursor_reset, event, head, runs_dir, schema, store_id}`, `schema_1` = `{am, event, runs_dir, schema}`. Contract helpers in `test_am_fixtures.py`: `check_count(where, value)`, `check_store_id(where, value)`, `check_gseqs(source, events)`, `RUNS_DATA_KEYS`, `EVENTS_DATA_KEYS`, `HELLO_V1_KEYS`, `NOTE_AM`.

- [ ] **Step 1: Check the prerequisites**

Run:

```bash
uv tool list | grep agent-manager
ls ~/Code/agent-manager/tests/e2e/fake_claude.py ~/Code/agent-manager/tests/e2e/test_integrate.py
which am brd git /usr/bin/python3
git status --short
```

Expected: `agent-manager v0.2.0`; both e2e files listed; four paths; `git status` shows nothing but the spec and plan under `docs/superpowers/` (or nothing). If the version is not 0.2.0, stop and report.

- [ ] **Step 2: Tighten the fixture contract (write the failing tests)**

Create `/tmp/am-capture/contract.diff` with exactly this content (the diff applies to `tests/contract/test_am_fixtures.py` at `804001f`):

```diff
--- a/tests/contract/test_am_fixtures.py
+++ b/tests/contract/test_am_fixtures.py
@@ -4,16 +4,16 @@
 Fixture contract: every capture is read with json.load and never written. Each
 level has one exact key set (keys starting with "_" are annotations and are
 ignored); status values come from am's run and attempt vocabularies. am status
-data has no top-level "subtasks".
+data has no top-level "subtasks". Every capture carries a "_note" naming
+agent-manager 0.2.0; the captures share one store_id; an event's gseq strictly
+increases and an am events page's head is at least its last gseq.
 
 Live check: am runs with HOME, XDG_DATA_HOME and XDG_STATE_HOME under a scratch
 dir, never the user's data dir. am runs data must carry "as_of_seq" and the
 first line of am watch --all --follow (the hello) must carry "head", each a
 non-negative int; a missing one fails naming the key and "the plugin needs the
-newer am". Rows present, and am status of the newest, must print the capture
-key sets, with the keys the captures predate allowed as extras: "story_id" and
-"project" (exactly "id" and "repo_dir") on a runs row, "story_id" on the status
-run, and "as_of_seq", "store_id" and "warnings" on the status data. Skipped only
+newer am". Rows present, and am status of the newest, must print exactly the
+capture key sets: a missing or an unknown key fails naming it. Skipped only
 when am is absent.
 """
 import json
@@ -35,25 +35,29 @@
 FIXTURE_NAMES = (
     "runs.json", "status-started.json", "status-done.json", "status-escalated.json",
     "status-escalated-integrate.json", "status-done-integrate.json", "watch-events.json",
-    "watch-hello.json", "logs-attempt.json",
+    "watch-hello.json", "logs-attempt.json", "events.json",
 )
 STATUS_FIXTURES = (
     "status-started.json", "status-done.json", "status-escalated.json",
     "status-escalated-integrate.json", "status-done-integrate.json",
 )
 E2E_FIXTURES = ("status-escalated.json", "status-escalated-integrate.json", "status-done-integrate.json")
-NOTED_FIXTURES = E2E_FIXTURES + ("watch-events.json", "watch-hello.json")
+NOTED_FIXTURES = FIXTURE_NAMES
+NOTE_AM = "agent-manager 0.2.0"
 
 ENVELOPE_KEYS = frozenset({"ok", "data"})
+RUNS_DATA_KEYS = frozenset({"as_of_seq", "runs", "store_id"})
 RUN_ROW_KEYS = frozenset({"id", "workflow", "repo_dir", "base_branch", "branch_prefix", "status",
-                          "started_at", "milestone_id", "card_id", "lease", "progress"})
+                          "started_at", "milestone_id", "card_id", "lease", "progress", "project",
+                          "story_id"})
 RUN_LEASE_KEYS = frozenset({"pid", "host", "heartbeat_at", "accepting", "live"})
 PROGRESS_KEYS = frozenset({"stories", "subtasks", "current"})
 COUNT_KEYS = frozenset({"done", "total"})
 CURRENT_KEYS = frozenset({"card", "phase", "attempt"})
-STATUS_DATA_KEYS = frozenset({"run", "stories", "rows", "control", "integrity"})
+STATUS_DATA_KEYS = frozenset({"run", "stories", "rows", "control", "integrity", "as_of_seq",
+                              "store_id", "warnings"})
 STATUS_RUN_KEYS = frozenset({"id", "workflow", "repo_dir", "base_branch", "branch_prefix", "status",
-                             "started_at"})
+                             "started_at", "story_id"})
 STORY_KEYS = frozenset({"card_id", "title", "level", "status", "tip_branch", "subtasks"})
 SUBTASK_KEYS = frozenset({"card_id", "branch", "base_branch", "status", "worktree_path", "phases"})
 PHASE_KEYS = frozenset({"name", "kind", "status", "started_at", "ended_at", "detail", "attempts"})
@@ -67,9 +71,12 @@
 ARTIFACTS_KEYS = frozenset({"prompt", "result", "stdout", "stderr"})
 ARTIFACT_KEYS = frozenset({"path", "present", "text"})
 WATCH_DATA_KEYS = frozenset({"events"})
-EVENT_KEYS = frozenset({"seq", "ts", "run_id", "event", "story", "card", "phase", "attempt", "payload"})
+EVENTS_DATA_KEYS = frozenset({"events", "head"})
+EVENT_KEYS = frozenset({"seq", "ts", "run_id", "event", "story", "card", "phase", "attempt", "payload",
+                        "gseq"})
 HELLO_FILE_KEYS = frozenset({"schema_1", "schema_2"})
-HELLO_KEYS = frozenset({"event", "schema", "am", "runs_dir"})
+HELLO_KEYS = frozenset({"am", "cursor_reset", "event", "head", "runs_dir", "schema", "store_id"})
+HELLO_V1_KEYS = frozenset({"am", "event", "runs_dir", "schema"})
 
 RUN_STATUSES = frozenset({"pending", "started", "done", "failed", "escalated", "stopped",
                           "cancelled", "canceled"})
@@ -77,11 +84,6 @@
 
 PROJECT_KEYS = frozenset({"id", "repo_dir"})
 
-# The installed am prints these extra keys on these three levels only; the captures predate them.
-LIVE_EXTRA = {RUN_ROW_KEYS: frozenset({"story_id", "project"}),
-              STATUS_RUN_KEYS: frozenset({"story_id"}),
-              STATUS_DATA_KEYS: frozenset({"as_of_seq", "store_id", "warnings"})}
-
 
 def load(name):
     with open(FIXTURES / name, encoding="utf-8") as fh:
@@ -92,10 +94,10 @@
     return {key for key in obj if not key.startswith("_")}
 
 
-def assert_keys(source, where, obj, expected, extra_allowed=frozenset()):
+def assert_keys(source, where, obj, expected):
     assert isinstance(obj, dict), f"{source} {where}: expected an object, got {obj!r}"
     keys = key_set(obj)
-    if keys == expected or keys == expected | extra_allowed:
+    if keys == expected:
         return
     missing = sorted(expected - keys)
     extra = sorted(keys - expected)
@@ -105,6 +107,7 @@
 def run_row_levels(where, row):
     """(where, obj, expected key set) for an am runs row and every object inside it."""
     yield where, row, RUN_ROW_KEYS
+    yield f"{where}.project", row.get("project"), PROJECT_KEYS
     if row.get("lease") is not None:
         yield f"{where}.lease", row["lease"], RUN_LEASE_KEYS
     progress = row.get("progress")
@@ -116,16 +119,16 @@
             yield f"{where}.progress.current", progress["current"], CURRENT_KEYS
 
 
-def check_runs_row(source, where, row, extra_allowed=None):
-    """A row's key sets and status; extra_allowed maps an expected set to keys also accepted."""
+def check_runs_row(source, where, row):
+    """A row's key sets, its project's included, and its status."""
     for level, obj, expected in run_row_levels(where, row):
-        assert_keys(source, level, obj, expected, (extra_allowed or {}).get(expected, frozenset()))
+        assert_keys(source, level, obj, expected)
     assert row["status"] in RUN_STATUSES, f"{source} {where}.status: {row['status']!r}"
 
 
-def check_runs_rows(source, rows, extra_allowed=None):
+def check_runs_rows(source, rows):
     for i, row in enumerate(rows):
-        check_runs_row(source, f"runs[{i}]", row, extra_allowed)
+        check_runs_row(source, f"runs[{i}]", row)
 
 
 def runs_rows_of_fixtures():
@@ -169,14 +172,38 @@
                     yield f"{where}.attempts[{a}].status", attempt["status"], ATTEMPT_STATUSES
 
 
-def check_status_data(source, data, extra_allowed=None):
+def check_status_data(source, data):
     """Every level's key set and every status of am status data."""
     for where, obj, expected in status_levels(data):
-        assert_keys(source, where, obj, expected, (extra_allowed or {}).get(expected, frozenset()))
+        assert_keys(source, where, obj, expected)
     for where, status, vocabulary in status_statuses(data):
         assert status in vocabulary, f"{source} {where}: {status!r} not in {sorted(vocabulary)}"
 
 
+def check_count(where, value):
+    """value is a non-negative int; a bool is not."""
+    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
+        pytest.fail(f"{where}: {value!r}")
+
+
+def check_store_id(where, value):
+    """value is a non-empty string."""
+    if not isinstance(value, str) or not value:
+        pytest.fail(f"{where}: {value!r}")
+
+
+def check_gseqs(source, events):
+    """Every event's gseq is an int and each is greater than the one before."""
+    previous = None
+    for i, event in enumerate(events):
+        gseq = event["gseq"]
+        if isinstance(gseq, bool) or not isinstance(gseq, int):
+            pytest.fail(f"{source} events[{i}].gseq: {gseq!r}")
+        if previous is not None and gseq <= previous:
+            pytest.fail(f"{source} events[{i}].gseq: {gseq} after {previous}")
+        previous = gseq
+
+
 @pytest.mark.parametrize("name", FIXTURE_NAMES)
 def test_every_fixture_exists_and_parses(name):
     path = FIXTURES / name
@@ -212,6 +239,34 @@
         check_runs_row(source, where, row)
 
 
+def test_runs_data_key_set_and_scalars():
+    data = load("runs.json")["data"]
+    assert_keys("runs.json", "data", data, RUNS_DATA_KEYS)
+    check_count("runs.json data.as_of_seq", data["as_of_seq"])
+    check_store_id("runs.json data.store_id", data["store_id"])
+
+
+def test_runs_row_project_failures_name_the_level():
+    # synthetic: a capture row with project dropped, then with an unknown project key
+    row = load("runs.json")["data"]["runs"][0]
+    del row["project"]
+    with pytest.raises(pytest.fail.Exception) as failure:
+        check_runs_row("runs.json", "runs[0]", row)
+    assert str(failure.value) == "runs.json runs[0]: missing ['project'], extra []"
+    row = load("runs.json")["data"]["runs"][0]
+    row["project"]["name"] = "x"
+    with pytest.raises(pytest.fail.Exception) as failure:
+        check_runs_row("runs.json", "runs[0]", row)
+    assert str(failure.value) == "runs.json runs[0].project: missing [], extra ['name']"
+
+
+def test_runs_rows_pair_with_the_started_and_done_captures():
+    rows = load("runs.json")["data"]["runs"]
+    assert len(rows) >= 2, f"runs.json: {len(rows)} rows"
+    assert rows[0]["id"] == load("status-started.json")["data"]["run"]["id"], rows[0]["id"]
+    assert rows[1]["id"] == load("status-done.json")["data"]["run"]["id"], rows[1]["id"]
+
+
 def test_runs_row_statuses_are_in_the_run_vocabulary():
     for source, where, row in runs_rows_of_fixtures():
         assert row["status"] in RUN_STATUSES, f"{source} {where}.status: {row['status']!r}"
@@ -239,6 +294,17 @@
     assert isinstance(data["control"]["claims"], list), f"{name} control.claims: not a list"
 
 
+@pytest.mark.parametrize("name", STATUS_FIXTURES)
+def test_status_data_scalars(name):
+    data = load(name)["data"]
+    check_count(f"{name} data.as_of_seq", data["as_of_seq"])
+    check_store_id(f"{name} data.store_id", data["store_id"])
+    warnings = data["warnings"]
+    assert isinstance(warnings, list), f"{name} data.warnings: {warnings!r}"
+    for i, warning in enumerate(warnings):
+        assert isinstance(warning, str), f"{name} data.warnings[{i}]: {warning!r}"
+
+
 def test_status_fixtures_reach_attempts_and_a_control_lease():
     levels = [expected for name in STATUS_FIXTURES for _, _, expected in status_levels(load(name)["data"])]
     assert ATTEMPT_KEYS in levels, "no status fixture has an attempt"
@@ -266,25 +332,65 @@
     assert data["events"], "watch-events.json: no events"
     for i, event in enumerate(data["events"]):
         assert_keys("watch-events.json", f"events[{i}]", event, EVENT_KEYS)
+    check_gseqs("watch-events.json", data["events"])
+
+
+def test_events_page_key_sets_and_head():
+    data = load("events.json")["data"]
+    assert_keys("events.json", "data", data, EVENTS_DATA_KEYS)
+    assert data["events"], "events.json: no events"
+    for i, event in enumerate(data["events"]):
+        assert_keys("events.json", f"events[{i}]", event, EVENT_KEYS)
+    check_gseqs("events.json", data["events"])
+    check_count("events.json data.head", data["head"])
+    last = data["events"][-1]["gseq"]
+    assert data["head"] >= last, f"events.json data.head: {data['head']} below the last gseq {last}"
+
+
+def test_check_gseqs_names_the_file_and_the_values():
+    # synthetic: gseqs that repeat, then one that is not an int
+    with pytest.raises(pytest.fail.Exception) as failure:
+        check_gseqs("x.json", [{"gseq": 3}, {"gseq": 3}])
+    assert str(failure.value) == "x.json events[1].gseq: 3 after 3"
+    with pytest.raises(pytest.fail.Exception) as failure:
+        check_gseqs("x.json", [{"gseq": True}])
+    assert str(failure.value) == "x.json events[0].gseq: True"
 
 
 def test_hello_key_sets_and_schemas():
     hellos = load("watch-hello.json")
     assert_keys("watch-hello.json", "top level", hellos, HELLO_FILE_KEYS)
-    for key, schema in (("schema_1", 1), ("schema_2", 2)):
+    for key, schema, expected in (("schema_1", 1, HELLO_V1_KEYS), ("schema_2", 2, HELLO_KEYS)):
         hello = hellos[key]
-        assert_keys("watch-hello.json", key, hello, HELLO_KEYS)
+        assert_keys("watch-hello.json", key, hello, expected)
         assert hello["schema"] == schema, f"watch-hello.json {key}: schema {hello['schema']!r}"
         assert hello["event"] == "watch", f"watch-hello.json {key}: event {hello['event']!r}"
+    hello = hellos["schema_2"]
+    check_count("watch-hello.json schema_2.head", hello["head"])
+    assert isinstance(hello["cursor_reset"], bool), \
+        f"watch-hello.json schema_2.cursor_reset: {hello['cursor_reset']!r}"
+    check_store_id("watch-hello.json schema_2.store_id", hello["store_id"])
 
 
-def test_note_is_on_exactly_the_annotated_captures():
-    noted = sorted(name for name in FIXTURE_NAMES if "_note" in load(name))
-    assert noted == sorted(NOTED_FIXTURES), noted
+def test_note_is_on_every_capture_and_names_the_am():
+    for name in FIXTURE_NAMES:
+        note = load(name).get("_note")
+        assert isinstance(note, str), f"{name}: _note is {note!r}"
+        assert NOTE_AM in note, f"{name}: _note does not name {NOTE_AM}"
+    assert NOTED_FIXTURES == FIXTURE_NAMES
     with_row = sorted(name for name in FIXTURE_NAMES if "_am_runs_row" in load(name))
     assert with_row == sorted(E2E_FIXTURES), with_row
 
 
+def test_captures_share_one_store_id():
+    seen = {"runs.json": load("runs.json")["data"]["store_id"],
+            "watch-hello.json schema_2": load("watch-hello.json")["schema_2"]["store_id"]}
+    seen.update((name, load(name)["data"]["store_id"]) for name in STATUS_FIXTURES)
+    (first, store_id), *rest = seen.items()
+    for name, other in rest:
+        assert other == store_id, f"store_id {other!r} in {name}, {store_id!r} in {first}"
+
+
 def am_json(env, *args):
     # A hung am fails the test (TimeoutExpired) instead of hanging the suite.
     proc = subprocess.run(["am", *args], env=env, capture_output=True, text=True, timeout=AM_TIMEOUT)
@@ -338,8 +444,8 @@
 
 def live_check(env, repo_dir):
     """am run with `env` prints am runs data carrying as_of_seq and an am watch hello carrying
-    head; rows present match the capture key sets with the LIVE_EXTRA allowances, and so does
-    am status of the newest row."""
+    head; rows present match the capture key sets exactly, and so does am status of the
+    newest row."""
     code, out, err = am_json(env, "runs", "--repo-dir", str(repo_dir))
     if code != 0:
         pytest.fail(f"live am runs exited {code}: {out}{err}")
@@ -351,14 +457,12 @@
         pytest.fail(f"live am runs: no data object in {out!r}")
     require_count("live am runs data", data, "as_of_seq")
     rows = data.get("runs") or []
-    check_runs_rows("live am runs", rows, LIVE_EXTRA)
-    for i, row in enumerate(rows):
-        assert_keys("live am runs", f"runs[{i}].project", row["project"], PROJECT_KEYS)
+    check_runs_rows("live am runs", rows)
     if rows:
         newest = max(rows, key=lambda row: row["started_at"])
         code, out, err = am_json(env, "status", newest["id"], "--repo-dir", str(repo_dir))
         assert code == 0, f"am status {newest['id']} exited {code}: {out}{err}"
-        check_status_data(f"live am status {newest['id']}", json.loads(out)["data"], LIVE_EXTRA)
+        check_status_data(f"live am status {newest['id']}", json.loads(out)["data"])
     hello = watch_hello(env)
     if hello.get("event") != "watch":
         pytest.fail(f"live am watch hello: event {hello.get('event')!r}")
@@ -371,30 +475,41 @@
     live_check(*scratch_env(tmp_path))
 
 
-def test_live_allowance_is_on_the_runs_row_status_run_and_status_data_only():
-    assert set(LIVE_EXTRA) == {RUN_ROW_KEYS, STATUS_RUN_KEYS, STATUS_DATA_KEYS}
-    run = dict.fromkeys(STATUS_RUN_KEYS | {"story_id"})
-    assert_keys("live", "data.run", run, STATUS_RUN_KEYS, LIVE_EXTRA[STATUS_RUN_KEYS])
-    # The extras come as a set: a runs row with story_id but no project fails.
-    row = dict.fromkeys(RUN_ROW_KEYS | {"story_id"})
-    with pytest.raises(pytest.fail.Exception, match=r"missing \[\], extra \['story_id'\]"):
-        assert_keys("live", "runs[0]", row, RUN_ROW_KEYS, LIVE_EXTRA[RUN_ROW_KEYS])
-    story = dict.fromkeys(STORY_KEYS | {"story_id"})
-    with pytest.raises(pytest.fail.Exception, match=r"extra \['story_id'\]"):
-        assert_keys("live", "stories[0]", story, STORY_KEYS, LIVE_EXTRA.get(STORY_KEYS, frozenset()))
+def test_live_rows_and_status_must_match_the_capture_key_sets_exactly():
+    # synthetic: a capture row with project dropped, then with an unknown key added
+    row = load("runs.json")["data"]["runs"][0]
+    del row["project"]
+    with pytest.raises(pytest.fail.Exception) as failure:
+        check_runs_rows("live am runs", [row])
+    assert str(failure.value) == "live am runs runs[0]: missing ['project'], extra []"
+    row = load("runs.json")["data"]["runs"][0]
+    row["future_key"] = 1
+    with pytest.raises(pytest.fail.Exception) as failure:
+        check_runs_rows("live am runs", [row])
+    assert str(failure.value) == "live am runs runs[0]: missing [], extra ['future_key']"
+    # synthetic: capture status data with story_id dropped from the run, then warnings dropped
+    data = load("status-done.json")["data"]
+    del data["run"]["story_id"]
+    with pytest.raises(pytest.fail.Exception) as failure:
+        check_status_data("live", data)
+    assert str(failure.value) == "live data.run: missing ['story_id'], extra []"
+    data = load("status-done.json")["data"]
+    del data["warnings"]
+    with pytest.raises(pytest.fail.Exception) as failure:
+        check_status_data("live", data)
+    assert str(failure.value) == "live data: missing ['warnings'], extra []"
 
 
 def test_live_status_check_rejects_a_status_outside_the_vocabularies():
     data = load("status-done.json")["data"]
-    data["run"]["story_id"] = "s"
-    check_status_data("live", data, LIVE_EXTRA)
+    check_status_data("live", data)
     data["stories"][0]["subtasks"][0]["phases"][1]["attempts"][0]["status"] = "done"
     attempt = r"stories\[0\]\.subtasks\[0\]\.phases\[1\]\.attempts\[0\]\.status"
     with pytest.raises(AssertionError, match=rf"^live {attempt}: 'done'"):
-        check_status_data("live", data, LIVE_EXTRA)
+        check_status_data("live", data)
     data["run"]["status"] = "bogus"
     with pytest.raises(AssertionError, match=r"^live data\.run\.status: 'bogus'"):
-        check_status_data("live", data, LIVE_EXTRA)
+        check_status_data("live", data)
 
 
 def test_live_check_skips_when_am_is_not_on_path(monkeypatch, tmp_path):
@@ -404,23 +519,33 @@
 
 
 def stub_runs_data(**extra):
-    """runs.json's data with no rows and no as_of_seq, updated with `extra`."""
+    """runs.json's data with no rows, no as_of_seq and no store_id (an older am's), updated
+    with `extra`."""
     data = load("runs.json")["data"]
     data.pop("as_of_seq", None)
+    data.pop("store_id", None)
     data["runs"] = []
     data.update(extra)
     return data
 
 
 def stub_hello(**extra):
-    """watch-hello.json's schema_2 hello without "_" keys and without head, updated with `extra`."""
+    """watch-hello.json's schema_2 hello without "_" keys and without head, cursor_reset and
+    store_id (an older am's), updated with `extra`."""
     hello = {key: value for key, value in load("watch-hello.json")["schema_2"].items()
              if not key.startswith("_")}
-    hello.pop("head", None)
+    for key in ("head", "cursor_reset", "store_id"):
+        hello.pop(key, None)
     hello.update(extra)
     return hello
 
 
+def test_stubs_model_an_older_am():
+    assert not {"as_of_seq", "store_id"} & set(stub_runs_data())
+    assert not {"head", "cursor_reset", "store_id"} & set(stub_hello())
+    assert stub_hello()["schema"] == 2
+
+
 def stub_am(tmp_path, runs_data, hello_line, runs_exit=0):
     """(env, repo_dir) of scratch_env with an executable am first on PATH.
 
```

Then apply it from the worktree root:

```bash
mkdir -p /tmp/am-capture
git apply /tmp/am-capture/contract.diff
```

Expected: no output. What it changes, for the reviewer: the module docstring; `FIXTURE_NAMES` gains `events.json`; `NOTED_FIXTURES = FIXTURE_NAMES` and `NOTE_AM`; `RUNS_DATA_KEYS`, `EVENTS_DATA_KEYS`, `HELLO_V1_KEYS` added; `RUN_ROW_KEYS` + `project`, `story_id`; `STATUS_DATA_KEYS` + `as_of_seq`, `store_id`, `warnings`; `STATUS_RUN_KEYS` + `story_id`; `EVENT_KEYS` + `gseq`; `HELLO_KEYS` is the new hello; `LIVE_EXTRA` and every `extra_allowed` parameter removed; `run_row_levels` yields the row's `project` against `PROJECT_KEYS` (so `runs.json` rows, every `_am_runs_row` and live rows all check it); helpers `check_count`, `check_store_id`, `check_gseqs`; new tests `test_runs_data_key_set_and_scalars`, `test_runs_row_project_failures_name_the_level`, `test_runs_rows_pair_with_the_started_and_done_captures`, `test_status_data_scalars`, `test_events_page_key_sets_and_head`, `test_check_gseqs_names_the_file_and_the_values`, `test_note_is_on_every_capture_and_names_the_am` (replaces `test_note_is_on_exactly_the_annotated_captures`), `test_captures_share_one_store_id`, `test_live_rows_and_status_must_match_the_capture_key_sets_exactly` (replaces `test_live_allowance_is_on_the_runs_row_status_run_and_status_data_only`), `test_stubs_model_an_older_am`; `test_hello_key_sets_and_schemas` checks `schema_1` against `HELLO_V1_KEYS` and `schema_2` against `HELLO_KEYS` with `head`/`cursor_reset`/`store_id` types; `stub_runs_data` also pops `store_id`, `stub_hello` also pops `cursor_reset` and `store_id`. The 4.0.1 stub tests and their messages are unchanged.

- [ ] **Step 3: Add `events.json` to the QML loader test (write the failing test)**

In `tests/helpers/tst_am_fixtures.qml`, replace:

```qml
    "watch-hello.json", "logs-attempt.json"
  ]
```

with:

```qml
    "watch-hello.json", "logs-attempt.json", "events.json"
  ]
```

and replace:

```qml
  function test_underscore_keys_are_kept() {
```

with:

```qml
  function test_events_page_loads_with_its_head() {
    var page = F.load("events.json")
    compare(page.ok, true)
    verify(Array.isArray(page.data.events), "events.json data.events is an array")
    verify(page.data.events.length > 0, "events.json data.events is empty")
    compare(typeof page.data.head, "number")
  }

  function test_underscore_keys_are_kept() {
```

- [ ] **Step 4: Run the new tests against the old captures to verify they fail**

Run:

```bash
uv run --with pytest python3 -m pytest -q tests/contract/test_am_fixtures.py 2>&1 | tail -25
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/helpers/tst_am_fixtures.qml 2>&1 | grep -E "^FAIL|Totals"
```

Expected: `23 failed, 46 passed`, the failures being `test_every_fixture_exists_and_parses[events.json]`, `test_envelopes_are_ok_data[events.json]`, `test_runs_rows_key_sets`, `test_runs_data_key_set_and_scalars`, `test_runs_row_project_failures_name_the_level`, `test_runs_row_failures_name_the_fixture_and_the_row_once`, `test_status_key_sets_at_every_level[...]` ×5, `test_status_data_scalars[...]` ×5, `test_watch_event_key_sets`, `test_events_page_key_sets_and_head`, `test_hello_key_sets_and_schemas`, `test_note_is_on_every_capture_and_names_the_am`, `test_captures_share_one_store_id`, `test_live_rows_and_status_must_match_the_capture_key_sets_exactly`, `test_live_status_check_rejects_a_status_outside_the_vocabularies`. Every 4.0.1 stub test passes. QML: `FAIL!  : ...test_events_page_loads_with_its_head() Uncaught exception: amFixtures: cannot load events.json: not readable`, the same for `test_every_fixture_loads`, `Totals: 11 passed, 2 failed`.

- [ ] **Step 5: Keep a copy of the old captures**

`retarget.py` (Step 13) pairs them with the new ones.

```bash
rm -rf /tmp/am-capture/old-fixtures
mkdir -p /tmp/am-capture/old-fixtures
cp tests/fixtures/am/*.json /tmp/am-capture/old-fixtures/
ls /tmp/am-capture/old-fixtures
```

Expected: the nine old fixture names.

- [ ] **Step 6: Write the capture script**

Create `/tmp/am-capture/capture.py` with exactly:

```python
"""Record the raw am output behind tests/fixtures/am/ on a scratch store.

Usage: python3 capture.py <empty scratch root> <raw out dir>

HOME, XDG_DATA_HOME and XDG_STATE_HOME all point under <scratch root>/home, so
neither ~/.local/share/agent-manager nor the real brd board is read or written.
PATH is <scratch root>/home/.local/bin (am, brd and git symlinked, agent-manager's
fake claude copied as `claude`) then /usr/bin. am is only ever called as argv.
Five milestone runs on one store, in this order: escalated, escalated at
Integrate, done through Integrate with a resolver, done, started (held).
"""
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

E2E = Path.home() / "Code" / "agent-manager" / "tests" / "e2e"
ROOT = Path(sys.argv[1]).resolve()
RAW = Path(sys.argv[2]).resolve()
HOME = ROOT / "home"
BIN = HOME / ".local" / "bin"
HOLD = HOME / ".cache" / "fake-claude-hold"
REPO = HOME / "Code" / "omarchy-project-manager"
VERIFY = "git rev-parse --verify HEAD"
CALC = "def add(a, b):\n    return a + b\n"
TEST_CALC = "from calc import add\n\n\ndef test_add():\n    assert add(2, 3) == 5\n"
RENAMED_CALC = "def plus(a, b):\n    return a + b\n"
RENAMED_TEST = "from calc import plus\n\n\ndef test_plus():\n    assert plus(2, 3) == 5\n"
EXTRA_TEST = "from calc import add\n\n\ndef test_add_negative():\n    assert add(-1, 1) == 0\n"
CHECK = (E2E / "test_integrate.py").read_text().split("CHECK_SOURCE = '''", 1)[1].split("'''", 1)[0]
CHECK_COMMAND = "/usr/bin/python3 -B check.py"

if ROOT.exists() and any(ROOT.iterdir()):
    raise SystemExit(f"{ROOT} must be empty")
BIN.mkdir(parents=True)
HOLD.mkdir(parents=True)
RAW.mkdir(parents=True)
for tool in ("am", "brd", "git"):
    (BIN / tool).symlink_to(shutil.which(tool))
(BIN / "claude").write_text("#!/usr/bin/python3\n" + (E2E / "fake_claude.py").read_text())
(BIN / "claude").chmod(0o755)
ENV = {"HOME": str(HOME), "XDG_DATA_HOME": str(HOME / ".local" / "share"),
       "XDG_STATE_HOME": str(HOME / ".local" / "state"), "PATH": f"{BIN}:/usr/bin",
       "LANG": "C.UTF-8"}


def sh(*argv, env=None):
    proc = subprocess.run(list(argv), cwd=REPO, env=env or ENV, capture_output=True, text=True,
                          timeout=600)
    if proc.returncode != 0:
        raise SystemExit(f"{argv} exited {proc.returncode}\n{proc.stdout}\n{proc.stderr}")
    return proc.stdout


def am_run(milestone, prefix, verify=VERIFY):
    """`am run --milestone` in the foreground: (exit code, envelope data)."""
    proc = subprocess.run(["am", "run", "--milestone", milestone, "--repo-dir", str(REPO),
                           "--base-branch", "main", "--branch-prefix", prefix, "--verify", verify],
                          cwd=REPO, env=ENV, capture_output=True, text=True, timeout=600)
    return proc.returncode, json.loads(proc.stdout)["data"]


def card(title, parent=None, blocked_by=()):
    argv = ["brd", "add", "--title", title]
    if parent:
        argv += ["--parent", parent]
    for blocker in blocked_by:
        argv += ["--blocked-by", blocker]
    return json.loads(sh(*argv))["data"]["id"]


def chained(title, stories):
    """A milestone whose stories block each other in order, and whose subtasks
    block each other in order inside a story. Returns (milestone, subtask ids)."""
    milestone, previous, subtasks = card(title), None, []
    for story_title, subtask_titles in stories:
        story = card(story_title, milestone, [previous] if previous else [])
        last = None
        for subtask_title in subtask_titles:
            last = card(subtask_title, story, [last] if last else [])
            subtasks.append(last)
        previous = story
    return milestone, subtasks


def branches(milestone, prefix):
    """{subtask id: branch} from `am run --milestone --dry-run`."""
    data = json.loads(sh("am", "run", "--milestone", milestone, "--repo-dir", str(REPO),
                         "--base-branch", "main", "--branch-prefix", prefix, "--dry-run"))["data"]
    return {t["id"]: t["branch"] for level in data["levels"] for story in level["stories"]
            for t in story["subtasks"]}


def seed(files, message):
    for name, text in files.items():
        (REPO / name).write_text(text)
    sh("git", "add", "-A")
    sh("git", "commit", "-m", message)


def short(card_id):
    return card_id.replace("-", "")[:8].lower()


# The scratch repo: git on main plus a brd board, as agent-manager's e2e conftest builds it.
REPO.mkdir(parents=True)
sh("git", "init", "-b", "main", str(REPO))
sh("git", "config", "user.email", "tests@example.com")
sh("git", "config", "user.name", "agent-manager tests")
sh("git", "config", "commit.gpgsign", "false")
(REPO / "README.md").write_text("base\n")
sh("git", "add", "README.md")
sh("git", "commit", "-m", "base")
sh("brd", "init", "--name", "omarchy-project-manager")
sh("git", "add", "-A")
sh("git", "commit", "--allow-empty", "-m", "brd init")
(REPO / ".git" / "info").mkdir(exist_ok=True)
(REPO / ".git" / "info" / "attributes").write_text("IMPLEMENTATION.md merge=union\n")
review_marker = REPO / ".git" / "fake-claude-review-fail"
edits_marker = REPO / ".git" / "fake-claude-implement-edits"
ids = {}

# 1. escalated (test_milestone_run.py:86, first launch): b1's review fails.
m = card("Milestone 3: run a milestone under a fake claude")
a = card("Story A: the first level", m)
b = card("Story B: blocked by story A", m, [a])
c = card("Story C: blocked by story B", m, [b])
a1 = card("a1: first subtask of story A", a)
card("a2: second subtask of story A", a, [a1])
b1 = card("b1: only subtask of story B", b)
card("c1: only subtask of story C", c)
review_marker.write_text(branches(m, "m3")[b1] + "\n")
code, data = am_run(m, "m3")
review_marker.unlink()
assert data.get("escalated") is True and data.get("failed_phase") == "review", data
ids["escalated"] = data["run_id"]

# 2. escalated at Integrate (test_integrate.py:296): A and B green alone, red together.
m = card("Milestone 5: integrate under a fake claude")
a = card("Story A: one side of the merge", m)
b = card("Story B: the other side of the merge", m)
a1 = card("a1: only subtask of story A", a)
b1 = card("b1: only subtask of story B", b)
seed({"calc.py": CALC, "test_calc.py": TEST_CALC, "check.py": CHECK}, "seed the calc suite")
br = branches(m, "m4")
edits_marker.write_text(json.dumps({br[a1]: {"calc.py": RENAMED_CALC, "test_calc.py": RENAMED_TEST},
                                    br[b1]: {"test_calc_extra.py": EXTRA_TEST}}))
code, data = am_run(m, "m4", verify=CHECK_COMMAND)
edits_marker.unlink()
assert data.get("escalated") is True and data.get("phase") == "integrate", data
ids["escalated-integrate"] = data["run_id"]

# 3. done through Integrate with a resolver (test_integrate.py:248): A and B rewrite one line.
m = card("Milestone 5: integrate under a fake claude, resolved")
a = card("Story A: one side of the merge", m)
b = card("Story B: the other side of the merge", m)
a1 = card("a1: only subtask of story A", a)
b1 = card("b1: only subtask of story B", b)
seed({"shared.txt": "the line both stories rewrite\n"}, "seed the shared line")
br = branches(m, "m3")
edits_marker.write_text(json.dumps({br[a1]: {"shared.txt": "story A rewrote this line\n"},
                                    br[b1]: {"shared.txt": "story B rewrote this line\n"}}))
code, data = am_run(m, "m3")
edits_marker.unlink()
assert code == 0 and data["integrated"]["resolved"] == [b], data
ids["done-integrate"] = data["run_id"]

# 4. done: four chained stories of 2, 3, 1 and 4 subtasks.
m, _ = chained("Milestone 2: run control", [
    ("Control domain", ["1.1 runs.js control", "1.2 runs.js newAlerts"]),
    ("Control backend", ["2.1 run-control.py", "2.2 runs-watch.py", "2.3 notify.py"]),
    ("Generalise TypedConfirmDialog", ["3.1 TypedConfirmDialog"]),
    ("Control store and UI", ["4.1 RunStore control", "4.2 RunDetail controls", "4.3 Alerts store",
                              "4.4 Alerts RunToast and notify"]),
])
code, data = am_run(m, "ctl")
assert code == 0 and data["done"] is True, data
ids["done"] = data["run_id"]

# 5. started: four chained stories of 2, 3, 1 and 2 subtasks; the fake holds the
# fourth subtask's explore (the first three are released before they start). The
# fake gives up a hold after 20 s, so every held capture is taken at once.
m, subtasks = chained("Milestone 3: dispatch", [
    ("Dispatch domain", ["1.1 runs.js dispatch", "1.2 runs.js"]),
    ("Dispatch backend", ["2.1 run-dispatch.py", "2.2 dispatch-check.py", "2.3 viewer-state.py"]),
    ("Dispatch store", ["3.1 RunStore dispatch"]),
    ("Dispatch UI", ["4.1 Dispatch dialog", "4.2 Dispatch entry"]),
])
for released in subtasks[:3]:
    (HOLD / f"{short(released)}.release").write_text("")
held = subtasks[3]
hold_env = dict(ENV, FAKE_CLAUDE_HOLD_DIR=str(HOLD), FAKE_CLAUDE_HOLD_PHASE="explore")
started = subprocess.Popen(["am", "run", "--milestone", m, "--repo-dir", str(REPO), "--base-branch",
                            "main", "--branch-prefix", "dsp", "--verify", VERIFY], cwd=REPO,
                           env=hold_env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
deadline = time.monotonic() + 600
while not (HOLD / f"{short(held)}.held").exists():
    assert started.poll() is None, "the started run exited before its hold"
    assert time.monotonic() < deadline, "no hold within 600 s"
    time.sleep(0.05)
time.sleep(1)
(RAW / "runs.json").write_text(sh("am", "runs", "--repo-dir", str(REPO), "--limit", "2"))
(RAW / "runs-all.json").write_text(sh("am", "runs", "--repo-dir", str(REPO)))
ids["started"] = json.loads((RAW / "runs.json").read_text())["data"]["runs"][0]["id"]
(RAW / "status-started.json").write_text(sh("am", "status", ids["started"], "--repo-dir", str(REPO)))
sh("am", "cancel", ids["started"], "--repo-dir", str(REPO))
(HOLD / f"{short(held)}.release").write_text("")
started.communicate(timeout=600)

# The rest address a finished run by id.
for key in ("done", "escalated", "escalated-integrate", "done-integrate"):
    (RAW / f"status-{key}.json").write_text(sh("am", "status", ids[key], "--repo-dir", str(REPO)))
done = json.loads((RAW / "status-done.json").read_text())["data"]
logs_card = done["stories"][0]["subtasks"][0]["card_id"]
(RAW / "logs-attempt.json").write_text(
    sh("am", "logs", ids["done"], logs_card, "--phase", "review", "--repo-dir", str(REPO)))
(RAW / "watch-events.json").write_text(sh("am", "watch", ids["done"]))
(RAW / "events.json").write_text(sh("am", "events", ids["done"], "--limit", "60"))
with subprocess.Popen(["am", "watch", "--all", "--follow", "--from-now"], cwd=REPO, env=ENV,
                      stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True) as watch:
    hello = watch.stdout.readline()
    watch.terminate()
    watch.wait(timeout=10)
(RAW / "watch-hello.json").write_text(hello)
(RAW / "ids.json").write_text(json.dumps(ids, indent=2) + "\n")
print(json.dumps(ids, indent=2))
```

Scenario notes for the reviewer: the escalated run is `test_milestone_run.py:86`'s board and review-fail marker; the escalated-at-Integrate run is `test_integrate.py:296`'s seeded calc suite, implement-edits marker and `check.py` verify; the done-through-Integrate run is `test_integrate.py:248`'s same-line conflict, resolved by the fake's default resolver; the union attribute is the e2e conftest's. Branch names come from `am run --milestone --dry-run`, never computed. Launch order is escalated, escalated-integrate, done-integrate, done, started, so `am runs --limit 2` lists the held started run then the done run. The escalated-at-Integrate run uses prefix `m4` so its `m4-integrate` branch does not collide with the resolved run's `m3-integrate`.

- [ ] **Step 7: Run the capture**

```bash
rm -rf /tmp/am-capture/scratch /tmp/am-capture/raw
timeout 900 python3 /tmp/am-capture/capture.py /tmp/am-capture/scratch /tmp/am-capture/raw
ls /tmp/am-capture/raw
```

Expected (about a minute): a JSON object of five run ids keyed `escalated`, `escalated-integrate`, `done-integrate`, `done`, `started`; `raw/` holds `events.json`, `ids.json`, `logs-attempt.json`, `runs-all.json`, `runs.json`, the five `status-*.json`, `watch-events.json`, `watch-hello.json`. A `SystemExit`/`AssertionError` names the failing command or scenario: fix the cause and rerun from the `rm -rf` (the script refuses a non-empty scratch root).

- [ ] **Step 8: Write the finalize script**

Create `/tmp/am-capture/finalize.py` with exactly:

```python
"""Turn capture.py's raw stdout files into tests/fixtures/am/*.json.

Usage: python3 finalize.py <scratch root> <raw dir> <fixtures dir>
Edits, and only these: <scratch root>/home -> /home/user in every value;
watch-events.json truncated to its first KEEP events; _note on every file;
_am_runs_row on the three e2e status captures. watch-hello.json's schema_1
is copied unchanged from the committed file.
"""
import datetime
import json
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
RAW = Path(sys.argv[2]).resolve()
FIXTURES = Path(sys.argv[3]).resolve()
SCRATCH_HOME = str(ROOT / "home")
REPO = "/home/user/Code/omarchy-project-manager"
KEEP = 60
TODAY = datetime.date.today().isoformat()
AM = "agent-manager 0.2.0 (its hello reports am 0.1.0)"
SCENE = ("a scratch store (HOME, XDG_DATA_HOME and XDG_STATE_HOME under a fresh dir), a scratch "
         "git repo with a brd board at " + REPO + ", and agent-manager's "
         "tests/e2e/fake_claude.py first on PATH as claude")
PATHS = "Only the scratch root is rewritten so paths read /home/user/..."


def raw(name):
    text = (RAW / name).read_text(encoding="utf-8")
    return json.loads(text.replace(SCRATCH_HOME, "/home/user"))


def save(name, obj):
    (FIXTURES / name).write_text(json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
                                      encoding="utf-8")


def noted(obj, note):
    return {"_note": note, **obj}


ids = json.loads((RAW / "ids.json").read_text(encoding="utf-8"))
all_rows = {row["id"]: row for row in raw("runs-all.json")["data"]["runs"]}
logs_card = raw("logs-attempt.json")["data"]["card"]
done_status = raw("status-done.json")
first_subtask = done_status["data"]["stories"][0]["subtasks"][0]["card_id"]
assert logs_card == first_subtask, (logs_card, first_subtask)

SCENARIOS = {
    "started": "a milestone of four chained stories (2, 3, 1 and 2 subtasks) held by the fake at "
               "explore of its fourth subtask (FAKE_CLAUDE_HOLD_DIR, FAKE_CLAUDE_HOLD_PHASE=explore), "
               "then cancelled",
    "done": "a milestone of four chained stories (2, 3, 1 and 4 subtasks) run to done",
    "escalated": "agent-manager's tests/e2e/test_milestone_run.py::"
                 "test_a_review_failure_stops_the_milestone_and_a_relaunch_finishes_it board, first "
                 "launch: b1's review fails (fake-claude-review-fail marker)",
    "escalated-integrate": "agent-manager's tests/e2e/test_integrate.py::"
                           "test_a_clean_merge_that_breaks_the_suite_escalates_at_integrate board: "
                           "escalated at the final Integrate verification",
    "done-integrate": "agent-manager's tests/e2e/test_integrate.py::"
                      "test_a_same_line_conflict_is_resolved_verified_and_left_on_the_integration_branch "
                      "board: done through an Integrate whose resolver subtask's card_id is story B's id",
}


def note(command, scenario, extra=""):
    return (f"Captured {TODAY} from {AM}: the stdout of `{command}` on {SCENE}; {scenario}. "
            f"{PATHS}{extra}")


runs = raw("runs.json")
save("runs.json", noted(runs, note(
    f"am runs --repo-dir {REPO} --limit 2",
    "taken while the started run was held, after the done run finished: row 0 is the started run "
    "(" + SCENARIOS["started"] + "), row 1 the done run (" + SCENARIOS["done"] + ")",
    "; nothing else edited.")))

for key in ("started", "done", "escalated", "escalated-integrate", "done-integrate"):
    status = raw(f"status-{key}.json")
    extra = "; nothing else edited."
    if key in ("escalated", "escalated-integrate", "done-integrate"):
        status["_am_runs_row"] = all_rows[ids[key]]
        extra = ("; `_am_runs_row` is this run's row from `am runs --repo-dir " + REPO +
                 "` taken in the same capture session. Nothing else edited.")
    when = " while held" if key == "started" else ""
    save(f"status-{key}.json", noted(status, note(
        f"am status {ids[key]} --repo-dir {REPO}", SCENARIOS[key] + when, extra)))

logs = raw("logs-attempt.json")
save("logs-attempt.json", noted(logs, note(
    f"am logs {ids['done']} {logs_card} --phase review --repo-dir {REPO}",
    "the done run's stories[0].subtasks[0] review attempt (" + SCENARIOS["done"] + ")",
    "; nothing else edited.")))

watch = raw("watch-events.json")
total = len(watch["data"]["events"])
watch["data"]["events"] = watch["data"]["events"][:KEEP]
save("watch-events.json", noted(watch, note(
    f"am watch {ids['done']}", "the done run (" + SCENARIOS["done"] + ")",
    f"; truncated to its first {KEEP} of {total} events. Nothing else edited.")))

events = raw("events.json")
save("events.json", noted(events, note(
    f"am events {ids['done']} --limit 60", "the done run (" + SCENARIOS["done"] + ")",
    "; one unedited page. Nothing else edited.")))

hello_v2 = json.loads((RAW / "watch-hello.json").read_text(encoding="utf-8")
                      .replace(SCRATCH_HOME, "/home/user"))
old = json.loads((FIXTURES / "watch-hello.json").read_text(encoding="utf-8"))
save("watch-hello.json", {
    "_note": ("schema_2 is " + note(
        "am watch --all --follow --from-now", "its first line, the hello",
        "; nothing else edited.") +
        " schema_1 is the historical am 0.1.0 capture, kept unchanged: the real first line of "
        "`am watch 20261004T204141Z-cb11063d --follow --from-now` (am 0.1.0, before head); no am "
        "prints schema 1 any more."),
    "schema_1": old["schema_1"],
    "schema_2": hello_v2,
})
print(json.dumps(ids, indent=2))
```

- [ ] **Step 9: Write the ten fixtures**

```bash
python3 /tmp/am-capture/finalize.py /tmp/am-capture/scratch /tmp/am-capture/raw tests/fixtures/am
ls tests/fixtures/am
git status --short tests/fixtures/am
```

Expected: the run ids printed again; ten files listed; `git status` shows the nine fixtures modified and `?? tests/fixtures/am/events.json`.

- [ ] **Step 10: Write and run the structure check**

Create `/tmp/am-capture/check_fixtures.py` with exactly:

```python
"""B3's per-capture structure, checked on tests/fixtures/am/ after finalize.py.

Usage: python3 check_fixtures.py <fixtures dir> <scratch root>
"""
import getpass
import json
import sys
from pathlib import Path

FIX, ROOT = Path(sys.argv[1]), str(Path(sys.argv[2]).resolve())


def load(name):
    return json.loads((FIX / name).read_text(encoding="utf-8"))


def subtasks(data):
    return [t for s in data["stories"] for t in s["subtasks"]]


for name in sorted(p.name for p in FIX.glob("*.json")):
    text = (FIX / name).read_text(encoding="utf-8")
    for bad in (ROOT, "/tmp/", f"/home/{getpass.getuser()}"):
        assert bad not in text, f"{name} contains {bad}"

rows = load("runs.json")["data"]["runs"]
assert len(rows) == 2, len(rows)
assert rows[0]["status"] == "started" and rows[0]["workflow"] == "milestone", rows[0]
assert rows[0]["lease"] and rows[0]["lease"]["live"] is True and rows[0]["progress"]["current"], rows[0]
assert rows[1]["status"] == "done" and rows[1]["lease"] is None, rows[1]
assert rows[1]["progress"]["current"] is None, rows[1]

started = load("status-started.json")["data"]
assert len(started["stories"]) >= 2 and started["control"]["lease"] is not None
states = [t["status"] for t in subtasks(started)]
assert states.count("started") == 1 and "done" in states and "pending" in states, states
(open_subtask,) = [t for t in subtasks(started) if t["status"] == "started"]
explore = open_subtask["phases"][1]
assert (explore["name"], explore["status"], explore["attempts"][0]["n"],
        explore["attempts"][0]["status"]) == ("explore", "started", 1, "started"), explore

done = load("status-done.json")["data"]
assert done["run"]["status"] == "done" and len(done["stories"]) >= 2
assert {s["status"] for s in done["stories"]} == {"done"}
assert {t["status"] for t in subtasks(done)} == {"done"}
assert done["stories"][0]["subtasks"][0]["phases"][1]["attempts"][0]

escalated = load("status-escalated.json")["data"]
states = [t["status"] for t in subtasks(escalated)]
assert states.count("escalated") == 1 and "done" in states and "pending" in states, states
(stuck,) = [t for t in subtasks(escalated) if t["status"] == "escalated"]
assert stuck["phases"][-1]["name"] == "review" and stuck["phases"][-1]["status"] == "failed"

assert load("status-escalated-integrate.json")["data"]["run"]["status"] == "escalated"
resolved = load("status-done-integrate.json")["data"]
(integrate,) = [s for s in resolved["stories"] if s["card_id"] == "integrate"]
story_ids = {s["card_id"] for s in resolved["stories"]}
assert integrate["subtasks"][0]["card_id"] in story_ids, integrate

logs = load("logs-attempt.json")["data"]
assert (logs["status"], logs["exit_code"], logs["phase"]) == ("ok", 0, "review"), logs
for kind in ("prompt", "result", "stdout"):
    assert logs["artifacts"][kind]["present"] and logs["artifacts"][kind]["text"], kind
assert logs["artifacts"]["stderr"]["present"] is False, logs["artifacts"]["stderr"]

events = load("watch-events.json")["data"]["events"]
assert events[0]["run_id"] == rows[1]["id"], events[0]["run_id"]
kinds = {e["event"] for e in events}
for kind in ("run_upsert", "story_upsert", "subtask_upsert", "phase_upsert", "attempt_upsert"):
    assert kind in kinds, kind
assert all("repo_dir" in e["payload"] for e in events if e["event"] == "run_upsert")

hello = load("watch-hello.json")["schema_2"]
assert hello["schema"] == 2 and hello["cursor_reset"] is False, hello
print("B3 structure ok")
```

Run:

```bash
python3 /tmp/am-capture/check_fixtures.py tests/fixtures/am /tmp/am-capture/scratch
```

Expected: `B3 structure ok`. An `AssertionError` means the capture does not show the structure B3 requires (for example the hold timed out because the held captures took over 20 s, or a path leaked): rerun Steps 7 and 9, never edit a fixture by hand.

- [ ] **Step 11: Run the contract and loader tests to verify they pass**

```bash
uv run --with pytest python3 -m pytest -q tests/contract 2>&1 | tail -3
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/helpers/tst_am_fixtures.qml 2>&1 | grep -E "^FAIL|Totals"
```

Expected: `88 passed` (all of `tests/contract`, including the live check on a scratch store and `test_am_shapes.py`); QML `Totals: 13 passed, 0 failed`. If `test_am_shapes.py` fails, stop and report (out of scope).

- [ ] **Step 12: Run the consumer tests to see what the regeneration broke**

```bash
uv run --with pytest python3 -m pytest -q tests/core/backend/runs 2>&1 | grep -E "^FAILED|passed|failed"
for t in tests/core/domain/tst_runs.qml tests/ui/tst_runs_real_data.qml tests/core/stores/tst_run_store.qml tests/ui/screens/tst_run_detail_screen.qml tests/ui/tst_runs_flow.qml; do echo "== $t"; QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input "$t" 2>&1 | grep -E "^FAIL|Totals"; done
```

Expected: pytest fails `test_runs_logs.py::test_logs_data_is_the_capture` and `test_runs_snapshot.py::test_fake_am_serves_the_captures`; the QML suites fail on the old captured literals (`tst_runs.qml`, `tst_runs_real_data.qml`, `tst_run_store.qml`, `tst_run_detail_screen.qml`). Any failure whose message is about plugin code mishandling a new key (a `TypeError` in `core/`, a key that is not a changed value) is out of scope: stop and report it.

- [ ] **Step 13: Write the retarget script and retarget the captured literals**

Create `/tmp/am-capture/retarget.py` with exactly:

```python
"""Map every captured literal of the old fixtures to the value playing the same
role in the new ones, and rewrite the consumer tests with it.

Usage: python3 retarget.py <old fixtures dir> <new fixtures dir> [--apply FILE...]
Without --apply it prints the mapping. The old and new captures have the same
structure (same stories, subtasks, phases, rows in the same order), so a value
at one JSON path in an old capture plays the same role as the value at that
path in the new capture.
"""
import json
import re
import sys
from pathlib import Path

OLD, NEW = Path(sys.argv[1]), Path(sys.argv[2])
PAIRED = ("runs.json", "status-started.json", "status-done.json", "status-escalated.json",
          "status-escalated-integrate.json", "status-done-integrate.json", "logs-attempt.json")
# Identifier-like values only: run ids, card ids, branches, worktree paths, timestamps.
ID = re.compile(r"^(\d{8}T\d{6}Z-[0-9a-f]{8}"
                r"|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
                r"|[a-z0-9]+/task-[a-z0-9-]+-[0-9a-f]{8}"
                r"|/home/user/\S+"
                r"|\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}\.\d+\+00:00)$")


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def walk(old, new, where, out):
    if isinstance(old, dict) and isinstance(new, dict):
        for key in old.keys() & new.keys():
            if not key.startswith("_") or key == "_am_runs_row":
                walk(old[key], new[key], f"{where}.{key}", out)
    elif isinstance(old, list) and isinstance(new, list):
        if len(old) != len(new):
            raise SystemExit(f"{where}: {len(old)} old items, {len(new)} new: structures differ")
        for i, (o, n) in enumerate(zip(old, new)):
            walk(o, n, f"{where}[{i}]", out)
    elif isinstance(old, str) and isinstance(new, str) and old != new and ID.match(old):
        out.setdefault(old, set()).add(new)
    elif where.endswith(".host") and isinstance(old, str) and old != new:
        out.setdefault(old, set()).add(new)
    elif where.endswith(".pid") and isinstance(old, int) and old != new:
        out.setdefault(str(old), set()).add(str(new))


mapping = {}
for name in PAIRED:
    old, new = load(OLD / name), load(NEW / name)
    if name == "logs-attempt.json":
        old, new = old["data"], new["data"]
        old.pop("artifacts"), new.pop("artifacts")
    walk(old, new, name, mapping)
clashes = {k: v for k, v in mapping.items() if len(v) > 1}
if clashes:
    raise SystemExit(f"one old value maps to several new ones: {clashes}")
mapping = {k: v.pop() for k, v in mapping.items()}

if "--apply" not in sys.argv:
    for old in sorted(mapping):
        print(f"{old} -> {mapping[old]}")
    sys.exit(0)

files = sys.argv[sys.argv.index("--apply") + 1:]
pattern = re.compile("|".join(re.escape(k) for k in sorted(mapping, key=len, reverse=True)))
for name in files:
    path = Path(name)
    text = path.read_text(encoding="utf-8")
    new_text, count = pattern.subn(lambda m: mapping[m.group(0)], text)
    path.write_text(new_text, encoding="utf-8")
    print(f"{name}: {count} replacements")
```

Print the mapping and read it:

```bash
python3 /tmp/am-capture/retarget.py /tmp/am-capture/old-fixtures tests/fixtures/am | grep -v '^/home/user\|^2026-' | head -80
```

Expected: no `structures differ` or `several new ones` error; lines such as `20261005T021400Z-837c4431 -> <new started run id>`, `299ec9c0-b935-4c44-a7a0-982a104cbfe5 -> <new held subtask id>`, `dsp/task-2-2-start-run-py-299ec9c0 -> dsp/task-2-2-dispatch-check-py-<short>`, `3736962 -> <new pid>` (and `mtts-desktop -> <host>` only if the host differs). Then apply it:

```bash
python3 /tmp/am-capture/retarget.py /tmp/am-capture/old-fixtures tests/fixtures/am --apply \
  tests/core/domain/tst_runs.qml tests/ui/tst_runs_real_data.qml tests/core/stores/tst_run_store.qml \
  tests/ui/screens/tst_run_detail_screen.qml tests/ui/tst_runs_flow.qml \
  tests/core/backend/runs/test_runs_watch.py tests/core/backend/runs/test_runs_snapshot.py \
  tests/core/backend/runs/test_runs_logs.py
```

Expected: `tst_runs.qml: 62 replacements`, `tst_runs_real_data.qml: 19 replacements`, `tst_run_store.qml: 4 replacements`, `tst_run_detail_screen.qml: 1 replacements`, and 0 for the other four (they read the captures by name).

- [ ] **Step 14: Run the consumers again to see the facts that changed**

```bash
uv run --with pytest python3 -m pytest -q tests/core/backend/runs 2>&1 | grep -E "^FAILED|passed|failed"
for t in tests/core/domain/tst_runs.qml tests/ui/tst_runs_real_data.qml tests/core/stores/tst_run_store.qml tests/ui/screens/tst_run_detail_screen.qml tests/ui/tst_runs_flow.qml; do echo "== $t"; QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input "$t" 2>&1 | grep -E "^FAIL|^   (Actual|Expected)|Totals"; done
```

Expected: pytest still fails the same two tests; QML fails exactly `DomainRuns::test_log_tail_of_a_real_attempt()` (Actual 1, Expected 19) and `StoresRunStore::test_a_real_logs_reply_shows_the_attempts_output()` (Actual 1, Expected 19); every other suite `0 failed`.

- [ ] **Step 15: Retarget the changed facts by hand**

These are the values the regeneration changed by fact, not by id: the new attempt's stdout is the fake's one line `fake-claude ok phase=review\n` (19 real lines before), a runs row has 13 keys (11 before), and every capture now carries a `_note` and `runs.json` data carries `as_of_seq`/`store_id`.

In `tests/core/domain/tst_runs.qml`, replace:

```qml
    var lines = tail.text.split("\n")
    compare(lines.length, 19)
    verify(lines[0].indexOf("Permission allow rule") === 0, lines[0])
    compare(lines[18], "| plan_hash | `e8f781ba` |")
    compare(tail.truncated, false)
    verify(tail.text.indexOf("# Reviewer") < 0, "the prompt artifact is not shown")

    var ten = Runs.logTail(F.load("logs-attempt.json").data, 10)
    compare(ten.text, lines.slice(9).join("\n"), "the last 10 of the 19 lines")
    compare(ten.truncated, true)
  }
```

with:

```qml
    var lines = tail.text.split("\n")
    compare(lines.length, 1)
    compare(lines[0], "fake-claude ok phase=review")
    compare(tail.truncated, false)
    verify(tail.text.indexOf("# Reviewer") < 0, "the prompt artifact is not shown")

    // The capture's stdout is one line: a tail of exactly that many lines is all of it.
    var one = Runs.logTail(F.load("logs-attempt.json").data, 1)
    compare(one.text, lines[0], "the last 1 of the 1 line")
    compare(one.truncated, false)
  }
```

(Truncation of a long real-shaped stdout stays pinned by `test_log_tail`'s synthetic `numbered(5000)` and `numbered(300)` cases in the same file; the fake harness cannot print more than one line.)

In the same file replace `  // fixture's text (stdout: 19 lines, stderr: null).` with `  // fixture's text (stdout: 1 line, stderr: null).` and `  // The capture's stdout text as its 19 lines.` with `  // The capture's stdout text as its lines (it has 1).`

In `tests/core/stores/tst_run_store.qml`, replace:

```qml
    compare(store.logsText.split("\n").length, 19)
```

with:

```qml
    compare(store.logsText.split("\n").length, 1)
```

In `tests/core/backend/runs/test_runs_logs.py`, replace:

```python
    assert {"ok": True, "data": logs_data()} == fixture("logs-attempt.json")
```

with:

```python
    # The capture's top-level `_note` is an annotation, not part of am's envelope.
    assert {"ok": True, "data": logs_data()} == \
        {k: v for k, v in fixture("logs-attempt.json").items() if not k.startswith("_")}
```

In `tests/core/backend/runs/test_runs_snapshot.py`, replace:

```python
    assert json.loads((world["am"] / "runs.out").read_text()) == fixture("runs.json")
```

with:

```python
    # set_runs serves the captured rows; the capture's data-level as_of_seq and
    # store_id and its `_note` are not part of what it serves.
    assert json.loads((world["am"] / "runs.out").read_text()) == \
        {"data": {"runs": fixture("runs.json")["data"]["runs"]}, "ok": True}
```

and replace:

```python
    # Every row_for row, capture status or not, has a real am runs row's 11 keys.
    keys = set(runs[0])
    assert len(keys) == 11
```

with:

```python
    # Every row_for row, capture status or not, has a real am runs row's 13 keys.
    keys = set(runs[0])
    assert len(keys) == 13
```

In `tests/core/backend/runs/test_runs_watch.py`, replace:

```python
    """The captured run_upsert, the first line of the run, carrying its repo_dir."""
```

with:

```python
    """The captured run_upsert, carrying its repo_dir (not the run's first line:
    lease_acquired comes before it)."""
```

`set_runs`, `row_for`, `status_for`, `ev`, `other`, `hello`, `HELLO1`/`HELLO2` and `WATCHED` are not edited: every input still comes from the captures (`HELLO2["am"]` stays `"0.1.0"`, which the new am prints; `other()`'s `future_upsert` is absent from the new capture too).

- [ ] **Step 16: Run the consumers to verify they pass**

```bash
uv run --with pytest python3 -m pytest -q tests/core/backend/runs 2>&1 | tail -1
for t in tests/core/domain/tst_runs.qml tests/ui/tst_runs_real_data.qml tests/core/stores/tst_run_store.qml tests/ui/screens/tst_run_detail_screen.qml tests/ui/tst_runs_flow.qml tests/helpers/tst_am_fixtures.qml; do echo "== $t"; QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input "$t" 2>&1 | grep -E "^FAIL|Totals"; done
```

Expected: pytest all passed; every QML suite `0 failed`.

- [ ] **Step 17: Check no old captured literal is left in a consumer**

```bash
grep -rnE '20261004T204141Z|20261005T0[0-9]{5}Z|837c4431|cb11063d|299ec9c0|22153f5f|5eb7ec0c|adff6c85|eb8b1851|b429248c|5d5114f9|3736962' tests --include=*.qml --include=*.py --include=*.js
```

Expected: no output. (The one intended mention, `20261004T204141Z-cb11063d` in `watch-hello.json`'s note about `schema_1`, is a `.json` file and not searched.)

- [ ] **Step 18: Name `events.json` in the architecture doc**

In `docs/architecture.md`, replace:

```markdown
- `tests/fixtures/am/` holds real captured am payloads: `runs.json`, five
  `status-*.json`, `watch-events.json`, `watch-hello.json` and
  `logs-attempt.json`; keys starting with `_` are annotations readers ignore.
```

with:

```markdown
- `tests/fixtures/am/` holds real captured am payloads: `runs.json`, five
  `status-*.json`, `watch-events.json`, `watch-hello.json`,
  `logs-attempt.json` and `events.json` (an `am events RUN` page with `head`);
  keys starting with `_` are annotations readers ignore.
```

- [ ] **Step 19: Run the whole suite**

```bash
timeout 1200 bash tests/run.sh 2>&1 | grep -vE '^== |Totals: +[0-9]+ passed, 0 failed|^\.+' | tail -20; echo "exit ${PIPESTATUS[0]}"
```

Expected: `992 passed` from pytest (the count after this task), no `FAIL` line, `exit 0`.

- [ ] **Step 20: Confirm the real stores were not touched**

```bash
brd projects 2>&1 | grep -c am-capture
am runs --all-projects 2>/dev/null | grep -c am-capture
```

Expected: `0` and `0`.

- [ ] **Step 21: Commit**

```bash
git add tests/fixtures/am tests/contract/test_am_fixtures.py tests/helpers/tst_am_fixtures.qml \
  tests/core/domain/tst_runs.qml tests/ui/tst_runs_real_data.qml tests/core/stores/tst_run_store.qml \
  tests/ui/screens/tst_run_detail_screen.qml tests/core/backend/runs/test_runs_logs.py \
  tests/core/backend/runs/test_runs_snapshot.py tests/core/backend/runs/test_runs_watch.py \
  docs/architecture.md
git status --short
git commit -m "test(fixtures): regenerate the am captures from agent-manager 0.2.0 and add events.json"
```

Expected: `git status` before the commit lists only those paths as staged (plus the untracked spec/plan if the workflow has not committed them); nothing under `core/` or `ui/`; `/tmp/am-capture/` is outside the worktree.

---

## Self-Review (against the spec)

1. **Spec coverage.** B1 (ten files, format): Steps 9, 11 (`test_every_fixture_exists_and_parses` covers all ten). B2 (provenance, notes, `_am_runs_row`): `finalize.py` writes notes naming `agent-manager 0.2.0 (its hello reports am 0.1.0)`, the command, scenario, date and edits; `test_note_is_on_every_capture_and_names_the_am`. B3 (scenario and per-capture structure, one store, launch order, hold): `capture.py`, `check_fixtures.py` (Step 10), `test_runs_rows_pair_with_the_started_and_done_captures`, `test_captures_share_one_store_id`. B4 (every key set, type and cross-file rule, `LIVE_EXTRA` removed, live exact match, stubs keep an old am): Step 2's diff. B5 (`schema_1` kept, `schema_2` real): `finalize.py`, `test_hello_key_sets_and_schemas`. B6 (QML loader): Step 3. B7 (consumers, same subjects, no input source change, `upsert` docstring, `HELLO2` stays `0.1.0`, stop on plugin mishandling): Steps 12-16. B8 (docs line): Step 18. Error paths: missing key / unknown key / project / gseq / head / store_id / note messages are pinned by `test_assert_keys_names_source_level_missing_and_extra`, `test_runs_row_project_failures_name_the_level`, `test_check_gseqs_names_the_file_and_the_values`, `test_events_page_key_sets_and_head`, `test_captures_share_one_store_id`, `test_note_is_on_every_capture_and_names_the_am`, `test_live_rows_and_status_must_match_the_capture_key_sets_exactly`; live am absent still skips (`test_live_check_skips_when_am_is_not_on_path`, unchanged). Out-of-scope items untouched (`test_am_shapes.py`, `core/`, `ui/`, no committed script).
2. **Placeholder scan.** Every script, diff and edit is given in full; no TBD.
3. **Type consistency.** `check_count`, `check_store_id`, `check_gseqs`, `check_runs_row(source, where, row)`, `check_runs_rows(source, rows)`, `check_status_data(source, data)`, `assert_keys(source, where, obj, expected)` are used with these signatures everywhere in the diff; no caller passes `extra_allowed` or `LIVE_EXTRA` (both removed).
4. **Deviation flagged.** B7 says no assertion is weakened. The fake harness prints exactly one stdout line, so `test_log_tail_of_a_real_attempt`'s "last 10 of the 19 lines, truncated" cannot hold on any capture this spec allows; Step 15 keeps the subject (logTail over the real capture: text, line count, first line, not truncated, prompt not shown) and replaces the truncation half with the exact-length boundary on the real capture, while truncation itself stays pinned by the synthetic cases in `test_log_tail`. The reviewer should confirm this is acceptable.
5. **Validation.** The whole procedure (capture → finalize → check → retarget → hand edits → `bash tests/run.sh`) was run twice by the planner on scratch copies of this worktree on 2026-10-08: the capture took 38-48 s, `check_fixtures.py` passed, retarget found no clash, and the full suite finished `992 passed`, every QML suite `0 failed`, `exit 0`; the tightened contract failed 23 tests on the old captures.
<!-- task-pipeline: validated -->
