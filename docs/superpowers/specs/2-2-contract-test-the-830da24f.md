# 2.2 Contract test: the `am watch RUN` shape — design

Card `830da24f`, a subtask of story `a22240f0` ("Events backend"). Parent spec:
`docs/superpowers/specs/2026-10-05-run-events-timeline-design.md` (below:
**parent**). Sibling, already landed: `4f30a6e0` (2.1,
`core/backend/runs/runs-events.py`, spec
`docs/superpowers/specs/2-1-runs-events-py-one-4f30a6e0.md`), which consumes the
shape this card pins.

## Goal

Extend `tests/contract/test_am_shapes.py` so the suite fails the day the
installed `am` stops speaking the shape `runs-events.py` and the Events pane
rely on: the one-shot `am watch RUN` envelope, its `--since SEQ` filter, the
journal-line keys, the payload keys of the five watched events, and the absence
of cost and token keys from attempt payloads.

The only file changed is `tests/contract/test_am_shapes.py`. No production code
changes.

## Card vs parent: which command

The parent names `am events RUN` with an envelope `{events, head}` (parent
L44-49, L172-174). The card names `am watch RUN` and `--since`, and the card
governs, as it did for 2.1 (2.1 spec, "Card vs parent: which command"). The
installed `am` (`am watch --help`): `am watch [OPTIONS] [RUN_ID]` prints one
run's events once as one envelope `{"ok": true, "data": {"events": [...]}}` (no
`head`), in gseq order; `--since SEQ` keeps events whose per-run `seq` is
greater than SEQ (default 0); no `--repo-dir` is needed (am resolves the run by
id). So this card pins `{ok, data: {events}}`, not `head`.

## Card vs file: how the journal is produced

The card says "hand-written journals as the existing tests do, with the payload
keys copied from a real journal.jsonl line of each kind". The existing tests do
not hand-write journal files: the module docstring
(`tests/contract/test_am_shapes.py:1-12`) states that events are seeded only
through am commands and that am's store is never read, and the parent forbids
reading am's files (parent L37). The existing pattern governs:

- The journal is the one the `seeded_run` fixture produces (a real story run on
  the scratch `story_board`, which escalates at its first agent phase because
  no agent CLI is on the PATH).
- "Copied from a real journal line of each kind" means: the expected payload
  key sets are module constants whose values were copied from what the
  installed am wrote for that seeded run, read through `am watch RUN` (read
  only). The values are listed under Behavior 3 below.

## Inherited constraints

| constraint | source |
|---|---|
| Hermetic: throwaway HOME, XDG_DATA_HOME, XDG_STATE_HOME under tmp_path; the user's runs are never read or written | card; `tests/contract/test_am_shapes.py:1-8, 31-44` |
| Skipped only when am is absent; with am present, missing brd or git fails, never skips | card; `test_am_shapes.py:10-12, 25, 102-107` |
| Each event is `{seq, gseq, ts, run_id, event, story, card, phase, attempt, payload}` | parent L48-53; `EVENT_KEYS` at `test_am_shapes.py:243` |
| The five watched events: `run_upsert`, `story_upsert`, `subtask_upsert`, `phase_upsert`, `attempt_upsert`; other kinds (`lease_*`, `control_*`, `claim_conflict`) are ignored | parent L53-54, L62; `WATCHED_EVENTS` at `test_am_shapes.py:247` |
| Payload keys of the five events recorded from the installed am | parent L172-174; card |
| No cost or token figures: an attempt carries `duration`, `exit_code`, `status`, the prompt/result/stdout paths and a `dispatch` | parent L33-35, L173-174 |
| `seq` is per run and is the `--since` cursor `runs-events.py` passes back | 2.1 spec; `core/backend/runs/runs-events.py:1-20` |
| An `ok: true` envelope has an object `data`, a list `data.events`, each event an object with an integer `seq` (what `runs-events.py` validates) | `core/backend/runs/runs-events.py:24-26` |
| am is never imported and its am.db is never read; only am commands | `test_am_shapes.py:4-8`; parent L37 |
| Docstrings and comments state the contract only, no narrative | card |
| `docs/architecture.md` layering; `tests/architecture` passes | card |
| `bash tests/run.sh` green; tests first | card |

## Behavior (what the new tests assert)

All new tests use the existing `am` and `seeded_run` fixtures and run am only
through `am.run(...)` (bounded by `AM_TIMEOUT`). A new helper
`watch_run_once(am, run_id, *extra)` sits next to `watch_all_once`: it runs
`am watch RUN_ID *extra`, asserts exit 0, `ok is True`, top-level keys exactly
`{"ok", "data"}` and data keys exactly `{"events"}`, and returns
`data["events"]`.

1. **Envelope.** `am watch RUN` for the seeded run:
   - passes `watch_run_once`'s envelope checks;
   - satisfies `assert_seeded_events(events, seeded_run, am.repo)` (every event
     has exactly `EVENT_KEYS`, `run_id` is the run, `ts` ends in `Z`, payload is
     a dict, `gseq` ints strictly increasing ending at the seeded head, `seq` is
     `1..n` contiguous, all five watched events present, story/attempt fields as
     already pinned there);
   - every `seq` is an `int` (type, not bool), which is what `runs-events.py`
     requires;
   - equals, element for element, the events of `am watch --all` whose `run_id`
     is the seeded run (same order).
2. **`--since SEQ`.** With `events` the full `am watch RUN` list (n events,
   n >= 2 is asserted):
   - `am watch RUN --since K` for K = 1 returns exactly `events[1:]`
     (the events with `seq > 1`), in the same order and unchanged;
   - `--since n-1` returns exactly `[events[-1]]`;
   - `--since 0` returns exactly `events`;
   - `--since n` (the last seq) returns `[]` with the same `{ok, data:{events}}`
     envelope and exit 0;
   - `--since` far beyond the head (n + 1000) returns `[]`, exit 0.
3. **Payload keys of the five events.** For every event of the seeded run whose
   `event` is one of the five, `set(payload)` equals exactly the constant for
   its kind (each occurrence, not only the first; a node recorded several times
   keeps the same key set). A new module constant `PAYLOAD_KEYS` maps each kind
   to its frozen key set, copied from the installed am:

   | event | payload keys |
   |---|---|
   | `run_upsert` | `base_branch, branch_prefix, config, id, milestone_id, repo_dir, started_at, status, workflow` |
   | `story_upsert` | `card_id, level, status, tip_branch, title` |
   | `subtask_upsert` | `base_branch, branch, card_id, status, worktree_path` |
   | `phase_upsert` | `detail, ended_at, kind, name, started_at, status` |
   | `attempt_upsert` | `dispatch, duration, exit_code, n, prompt_path, result_path, status, stdout_path` |

   `set(PAYLOAD_KEYS) == WATCHED_EVENTS` (the constant covers exactly the five).
   Events of other kinds in the journal (the seeded run has a
   `lease_acquired`, payload `{claims, host, pid, token}`) are not checked and
   do not fail the test. The assertion message names the event kind and shows
   the event, so drift points at the kind that changed.

   Exact equality is deliberate: the consumer ignores unknown keys (parent
   L62), but this is the place where a change in what am writes is noticed; an
   added key fails here and is fixed by updating `PAYLOAD_KEYS`.
4. **No cost or token keys on attempts.** For every `attempt_upsert` of the
   seeded run (at least one is asserted), no payload key, at the top level or
   inside a dict-valued payload entry (e.g. `dispatch`), contains `cost` or
   `token` case-insensitively. `lease_acquired`'s `token` is not an attempt
   payload and is out of this check.

## Error paths

- am absent: the module is skipped (existing `pytestmark`).
- am present, brd or git absent: `story_board` fails naming the tool (existing
  `require_tool`).
- am hangs: `subprocess.TimeoutExpired` after `AM_TIMEOUT` fails the test
  (existing `am.run`).
- am prints a non-JSON or refusal envelope for `am watch RUN`: `watch_run_once`
  fails with am's stdout and stderr in the message.

## Tests

All in `tests/contract/test_am_shapes.py`, tier **contract** (they exercise the
real installed `am` binary in a throwaway environment; a unit test with a stub
am cannot detect drift in am itself, and the stub-am behaviour of
`runs-events.py` is 2.1's backend tier).

| test | proves | tier, why |
|---|---|---|
| `test_watch_run_returns_the_events_envelope_with_journal_line_keys` | Behavior 1 | contract: the envelope and line keys are am's output |
| `test_watch_run_is_the_run_filtered_watch_all` | Behavior 1, last bullet | contract: two am commands must agree |
| `test_watch_run_since_keeps_only_events_with_a_greater_seq` | Behavior 2: K = 0, 1, n-1 | contract: `--since` semantics are am's |
| `test_watch_run_since_at_or_beyond_the_last_seq_is_an_empty_events_list` | Behavior 2: K = n, n + 1000 | contract: the "nothing new" reply `runs-events.py` turns into `last_seq` = SEQ |
| `test_watched_event_payloads_carry_the_recorded_keys` | Behavior 3 | contract: the payload keys as am writes them |
| `test_attempt_payloads_carry_no_cost_or_token_keys` | Behavior 4 | contract: parent non-goal L33-35 holds in am's output |

TDD note: am already behaves as pinned, so each test is first written with a
deliberately wrong expectation (e.g. a key removed from one `PAYLOAD_KEYS`
entry, `--since 1` expecting `events`), run to see it fail against the real am,
then corrected and run to see it pass.

Verification: `bash tests/run.sh` green (pytest over `tests/`, including
`tests/architecture`, then the QML tests).

## Out of scope

- Any change to `core/backend/runs/runs-events.py` or its backend tests (2.1).
- `am watch RUN` refusals (`UnknownRunError` exit 3, store busy): their
  passthrough is 2.1's stub-am tier; not asked by this card.
- `am events`, `head`, `--after-seq`, `--before-seq`, `--limit`, `--tail` on am
  (parent L44-49): not in the installed am's `watch` and not in the card.
- `--follow`, `--since-seq`, `--project`, `--all-projects` beyond what the
  existing tests already pin.
- Payload values (statuses, `detail` text, `exit_code`, durations): only key
  sets and the cost/token absence are pinned; values vary per run.
- The QML domain (`runEvents.js`), `RunStore`, `EventsPane` and UI tests
  (sibling cards of the parent).
- Hand-writing journal files or reading am's store (see "Card vs file").
