# 4.0.2 Fixtures: regenerate `tests/fixtures/am` from the new `am` and add `events.json` — design

Card: `b134b718` (subtask of story `0cf1ca04`, 4.0 Contract; blocked by 4.0.1 `f1b95771`, landed on
this branch as `4337424`/`804001f`). Parent design:
`docs/superpowers/specs/2026-10-06-am-snapshots-cursors-design.md` in the main checkout (untracked
there; cited below as **M4** with line numbers). Sibling spec already in this tree:
`docs/superpowers/specs/4-0-1-contract-test-the-f1b95771.md` (cited as **4.0.1**).

## Purpose

Every later M4 subtask (4.0.3 `normalizeRun`, 4.1.1 watch helper, 4.1.2 snapshot helper, 4.1.3
RunStore) builds its test inputs from `tests/fixtures/am/` (card: "Test inputs of am output come
from tests/fixtures/am/, never hand-written"). Today every capture is from am 0.1.0 and carries
none of `as_of_seq`, `store_id`, `project`, `story_id`, `gseq`, `head`, `cursor_reset`. This card
replaces them with captures of the installed am (agent-manager 0.2.0), adds `events.json` (an
`am events RUN` envelope with `head`), and tightens the fixture contract tests so the new keys are
pinned exactly (M4 §"Testing", lines 209-215; M4 §"Order and sizing", line 255; M4 line 269:
4.1.3 depends on these fixtures).

## Inherited constraints

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

## Observed shapes of the installed am (measured 2026-10-08)

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

## Behavior

### B1. The fixture set

`tests/fixtures/am/` holds exactly these ten files, each pretty-printed with sorted keys
(`json.dumps(obj, indent=1, sort_keys=True)` as today) and a trailing newline:

`runs.json`, `status-started.json`, `status-done.json`, `status-escalated.json`,
`status-escalated-integrate.json`, `status-done-integrate.json`, `watch-events.json`,
`watch-hello.json`, `logs-attempt.json`, `events.json` (new).

### B2. Provenance and edits

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

### B3. Capture scenario (what each capture must show)

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

### B4. Fixture contract (`tests/contract/test_am_fixtures.py`)

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

### B5. `watch-hello.json`

- `schema_2` is replaced by the real new-am capture (B3).
- `schema_1` keeps today's real am 0.1.0 capture unchanged: no am prints schema 1 any more, and
  it is the only real hello without `head`, which 4.1.1's SchemaMismatch test needs and
  `test_runs_watch.py:78-82` (`HELLO1`) and `tst_run_store.qml:468-470` (`helloLine("schema_1")`)
  read. Its note says so; it is the one capture not taken from 0.2.0, and the "names
  agent-manager 0.2.0" rule is satisfied by the file's single note covering both keys.

### B6. QML loader (`tests/helpers/tst_am_fixtures.qml`)

`amFixtures.js` needs no change (`load(name)` is generic). `tst_am_fixtures.qml`:

- `names` adds `"events.json"` (so `test_every_fixture_loads` covers it).
- A new test: `F.load("events.json")` has `ok === true`, `data.events` a non-empty array, and
  `typeof data.head === "number"`.
- `test_loads_real_content` and `test_underscore_keys_are_kept` keep passing (schema_2 schema 2,
  `_note` string).

### B7. Consumers

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

### B8. Docs

`docs/architecture.md:254-256`, the list of fixture files, adds `events.json` (an `am events RUN`
page with `head`). No other doc change (the run-monitor sections are 4.4.1).

## Error paths

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

## Tests

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

## Out of scope

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

## Risks for the planner

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
