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

---

# 2.2 Contract test: the `am watch RUN` shape Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `tests/contract/test_am_shapes.py` so the suite fails the day the installed `am` stops printing the `am watch RUN [--since SEQ]` envelope, journal-line keys and watched-event payload keys that `core/backend/runs/runs-events.py` relies on, or starts putting cost/token keys on attempts.

**Architecture:** Test-only change in one file. A helper `watch_run_once(am, run_id, *extra)` reads one run's events through the real `am` in the existing hermetic fixtures (`am`, `story_board`, `seeded_run`); pure helpers `assert_payload_keys(events)` and `cost_or_token_keys(payload)` carry the key checks so they can be pinned on synthetic input before they are pointed at am's output.

**Tech Stack:** Python 3, pytest, the installed `am`, `brd` and `git` binaries.

**Spec:** `docs/superpowers/specs/2-2-contract-test-the-830da24f.md` (prepended above).

## Global Constraints

- The only file changed is `tests/contract/test_am_shapes.py`. No production code changes.
- Hermetic: throwaway HOME, XDG_DATA_HOME, XDG_STATE_HOME under tmp_path; the user's runs are never read or written (use the existing `am` fixture; never call `subprocess.run(["am", ...])` with the ambient env).
- Skipped only when am is absent (existing `pytestmark`); with am present, missing brd or git fails, never skips.
- am is never imported and its am.db is never read; only am commands, through `am.run(...)` (bounded by `AM_TIMEOUT`).
- No hand-written journal files: events come from the `seeded_run` fixture.
- Each event is `{seq, gseq, ts, run_id, event, story, card, phase, attempt, payload}` (`EVENT_KEYS`).
- The five watched events: `run_upsert`, `story_upsert`, `subtask_upsert`, `phase_upsert`, `attempt_upsert` (`WATCHED_EVENTS`); other kinds (`lease_*`, `control_*`, `claim_conflict`) are not checked.
- Docstrings and comments state the contract only, no narrative.
- `docs/architecture.md` layering; `tests/architecture` passes.
- `bash tests/run.sh` green; tests first.

## Running the tests

`python3` on this machine may have no pytest. Run pytest as `tests/run.sh` does:

```bash
uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q
```

(If `python3 -c 'import pytest'` succeeds, `python3 -m pytest ...` works as well.) Wrap long runs in `timeout 300`. Never use `pkill`/`killall`.

Ground truth, recorded from the installed am for the `seeded_run` fixture (16 events): seq 1 `lease_acquired` (payload `{claims, host, pid, token}`), then `run_upsert`, `story_upsert`, `subtask_upsert`×3, `story_upsert`, `phase_upsert`×3, `attempt_upsert` (seq 11, payload `dispatch` is a dict with `cwd, harness, model, prompt_path, result_path, role, timeout`), `phase_upsert`, `subtask_upsert`×2, `story_upsert`, `run_upsert` (seq 16). `--since 0|1|15|16|1016` returned seqs `1..16`, `2..16`, `[16]`, `[]`, `[]`, all exit 0 with `{ok, data:{events}}`.

## Review Focus

1. `am watch RUN` refuses (exit 3, `{"ok": false, "error": ...}`) or prints non-JSON at exit 0 — the test must fail with am's stdout and stderr in the message, not with a bare `JSONDecodeError`/`KeyError`. Pinned in Task 1 by `test_watch_run_once_fails_with_ams_output_on_a_refusal` and `test_watch_run_once_fails_with_ams_output_when_it_prints_no_json` (fake am).
2. A cost or token key nested inside a dict-valued attempt entry (e.g. `dispatch.input_tokens`) or in another case (`Cost`) — must be found, or Behavior 4 is vacuous. Pinned in Task 3 by `test_cost_or_token_keys_finds_top_level_and_nested_keys_in_any_case`.
3. Payload drift on one kind — the failure must name the kind and show the event. Pinned in Task 3 by `test_assert_payload_keys_names_the_kind_that_drifted`.
4. Non-watched kinds in the journal (`lease_acquired` with a `token` key) — must not fail the payload-key or cost/token checks. Pinned in Task 3 by `test_assert_payload_keys_ignores_other_kinds` and by the attempt filter in `test_attempt_payloads_carry_no_cost_or_token_keys` (the real seeded journal holds a `lease_acquired`).
5. `seq` arriving as a bool or a float that compares equal to an int (`True == 1`, `1.0 == 1`) — `runs-events.py` requires an int; `assert_seeded_events`'s `range` comparison would accept it. Pinned in Task 1 by the `type(event["seq"]) is int` check in `test_watch_run_returns_the_events_envelope_with_journal_line_keys`.

---

### Task 1: `watch_run_once` and the `am watch RUN` envelope

**Files:**
- Modify: `tests/contract/test_am_shapes.py` — insert `watch_run_once` after `watch_all_once` (currently lines 294-301); append the new tests at the end of the file (after line 333).
- Test: `tests/contract/test_am_shapes.py`

**Interfaces:**
- Consumes (existing in the file): fixtures `am` (`am.run(*args) -> subprocess.CompletedProcess`, `am.repo: str`), `seeded_run` (`.id: str`, `.story: str`, `.head: int`, `.store_id`); `assert_seeded_events(events, run, repo)`; `watch_all_once(am) -> list[dict]`; imports `json`, `subprocess`, `pytest`, `SimpleNamespace`.
- Produces: `watch_run_once(am, run_id: str, *extra: str) -> list[dict]` — runs `am watch RUN_ID *extra`, fails with am's stdout and stderr in the message unless exit 0 and the envelope is exactly `{"ok": True, "data": {"events": [...]}}`; returns `data["events"]`. Also `fake_am(returncode: int, stdout: str, stderr: str = "") -> SimpleNamespace` (a stand-in whose `.run(*args)` returns a `CompletedProcess`) for helper tests.

- [ ] **Step 1: Write the failing tests**

Append to the end of `tests/contract/test_am_shapes.py`:

```python
def fake_am(returncode, stdout, stderr=""):
    """A stand-in for the am fixture whose every run returns this output."""
    def run(*args):
        return subprocess.CompletedProcess(["am", *args], returncode, stdout, stderr)

    return SimpleNamespace(run=run)


def test_watch_run_once_fails_with_ams_output_on_a_refusal():
    refusal = json.dumps({"ok": False, "error": {"type": "UnknownRunError", "message": "no run r1"}})
    with pytest.raises(AssertionError, match="UnknownRunError.*boom"):
        watch_run_once(fake_am(3, refusal, "boom"), "r1")


def test_watch_run_once_fails_with_ams_output_when_it_prints_no_json():
    with pytest.raises(pytest.fail.Exception, match="not json.*traceback"):
        watch_run_once(fake_am(0, "not json", "traceback"), "r1")


def test_watch_run_returns_the_events_envelope_with_journal_line_keys(am, seeded_run):
    events = watch_run_once(am, seeded_run.id)
    assert_seeded_events(events, seeded_run, am.repo)
    # runs-events.py takes seq as the --since cursor: an int, never a bool or float.
    assert all(type(event["seq"]) is int for event in events), events


def test_watch_run_is_the_run_filtered_watch_all(am, seeded_run):
    expected = [event for event in watch_all_once(am) if event["run_id"] == seeded_run.id]
    assert watch_run_once(am, seeded_run.id) == expected
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "watch_run"`
Expected: 4 FAILED, each with `NameError: name 'watch_run_once' is not defined`.

- [ ] **Step 3: Write the helper**

In `tests/contract/test_am_shapes.py`, directly after `watch_all_once` (which ends with `return payload["data"]["events"]`) and before `test_watch_all_returns_the_events_envelope_with_journal_line_keys`, insert:

```python
def watch_run_once(am, run_id, *extra):
    """The events of `am watch RUN_ID *extra`, which must exit 0 with exactly
    {"ok": true, "data": {"events": [...]}}; otherwise the test fails with
    am's stdout and stderr."""
    proc = am.run("watch", run_id, *extra)
    output = f"stdout={proc.stdout!r} stderr={proc.stderr!r}"
    assert proc.returncode == 0, output
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"am watch {run_id} printed no JSON envelope: {output}")
    assert isinstance(payload, dict) and payload.get("ok") is True, output
    assert set(payload) == {"ok", "data"}, output
    assert isinstance(payload["data"], dict) and set(payload["data"]) == {"events"}, output
    assert isinstance(payload["data"]["events"], list), output
    return payload["data"]["events"]
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "watch_run"`
Expected: 4 passed.

- [ ] **Step 5: See the envelope test fail against the real am on a wrong expectation, then restore**

Temporarily change the last line of `test_watch_run_returns_the_events_envelope_with_journal_line_keys` to:

```python
    assert all(type(event["seq"]) is str for event in events), events
```

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "test_watch_run_returns_the_events_envelope"`
Expected: 1 FAILED with an `AssertionError` showing the events list.

Restore the line to:

```python
    assert all(type(event["seq"]) is int for event in events), events
```

Run the same command. Expected: 1 passed.

- [ ] **Step 6: Run the whole contract file**

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q`
Expected: all passed (15 tests: the 11 existing plus 4 new).

- [ ] **Step 7: Commit**

```bash
git add tests/contract/test_am_shapes.py
git commit -m "test(contract): am watch RUN prints the run's events as one {ok, data:{events}} envelope"
```

---

### Task 2: `am watch RUN --since SEQ`

**Files:**
- Modify: `tests/contract/test_am_shapes.py` — append two tests at the end of the file.
- Test: `tests/contract/test_am_shapes.py`

**Interfaces:**
- Consumes: `watch_run_once(am, run_id: str, *extra: str) -> list[dict]` (Task 1); fixtures `am`, `seeded_run`.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the tests with one deliberately wrong expectation each**

Append to the end of `tests/contract/test_am_shapes.py`. The `--since 1` line in the first test and the `--since last` line in the second are deliberately wrong (they are corrected in Step 3):

```python
def test_watch_run_since_keeps_only_events_with_a_greater_seq(am, seeded_run):
    events = watch_run_once(am, seeded_run.id)
    assert len(events) >= 2, events
    last = events[-1]["seq"]
    assert watch_run_once(am, seeded_run.id, "--since", "0") == events
    assert watch_run_once(am, seeded_run.id, "--since", "1") == events
    assert watch_run_once(am, seeded_run.id, "--since", str(last - 1)) == [events[-1]]


def test_watch_run_since_at_or_beyond_the_last_seq_is_an_empty_events_list(am, seeded_run):
    events = watch_run_once(am, seeded_run.id)
    last = events[-1]["seq"]
    assert watch_run_once(am, seeded_run.id, "--since", str(last)) == [events[-1]]
    assert watch_run_once(am, seeded_run.id, "--since", str(last + 1000)) == []
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "watch_run_since"`
Expected: 2 FAILED — the first on the `--since 1` assertion (am returned the events from seq 2 on), the second on the `--since last` assertion (am returned `[]`).

- [ ] **Step 3: Correct the expectations**

The two tests become exactly:

```python
def test_watch_run_since_keeps_only_events_with_a_greater_seq(am, seeded_run):
    events = watch_run_once(am, seeded_run.id)
    assert len(events) >= 2, events
    last = events[-1]["seq"]
    assert watch_run_once(am, seeded_run.id, "--since", "0") == events
    assert watch_run_once(am, seeded_run.id, "--since", "1") == events[1:]
    assert watch_run_once(am, seeded_run.id, "--since", str(last - 1)) == [events[-1]]


def test_watch_run_since_at_or_beyond_the_last_seq_is_an_empty_events_list(am, seeded_run):
    """The "nothing new" reply runs-events.py turns into last_seq = SEQ."""
    events = watch_run_once(am, seeded_run.id)
    last = events[-1]["seq"]
    assert watch_run_once(am, seeded_run.id, "--since", str(last)) == []
    assert watch_run_once(am, seeded_run.id, "--since", str(last + 1000)) == []
```

(`seq` is `1..n` contiguous — `assert_seeded_events` pins that in Task 1's envelope test — so `events[1:]` is exactly the events with `seq > 1`, and `last` is n.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "watch_run_since"`
Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
git add tests/contract/test_am_shapes.py
git commit -m "test(contract): am watch RUN --since SEQ keeps only events with a greater seq"
```

---

### Task 3: watched-event payload keys and no cost or token keys on attempts

**Files:**
- Modify: `tests/contract/test_am_shapes.py` — add `PAYLOAD_KEYS` directly after `WATCHED_EVENTS` (currently line 248); add `assert_payload_keys` and `cost_or_token_keys` directly after `watch_run_once` (Task 1); append the tests at the end of the file.
- Test: `tests/contract/test_am_shapes.py`

**Interfaces:**
- Consumes: `watch_run_once(am, run_id: str, *extra: str) -> list[dict]` (Task 1); `WATCHED_EVENTS: set[str]` (existing); fixtures `am`, `seeded_run`.
- Produces: `PAYLOAD_KEYS: dict[str, set[str]]`; `assert_payload_keys(events: list[dict]) -> None` (raises `AssertionError` naming the kind); `cost_or_token_keys(payload: dict) -> list[str]`.

- [ ] **Step 1: Write the failing tests**

Append to the end of `tests/contract/test_am_shapes.py`:

```python
def test_payload_keys_cover_exactly_the_watched_events():
    assert set(PAYLOAD_KEYS) == WATCHED_EVENTS


def test_assert_payload_keys_names_the_kind_that_drifted():
    drifted = {"event": "attempt_upsert", "payload": dict.fromkeys(
        PAYLOAD_KEYS["attempt_upsert"] | {"cost_usd"})}
    with pytest.raises(AssertionError, match="attempt_upsert payload keys drifted.*cost_usd"):
        assert_payload_keys([drifted])


def test_assert_payload_keys_ignores_other_kinds():
    lease = {"event": "lease_acquired",
             "payload": {"claims": [], "host": "h", "pid": 1, "token": "t"}}
    assert_payload_keys([lease])


def test_cost_or_token_keys_finds_top_level_and_nested_keys_in_any_case():
    payload = {"duration": 1.0, "Cost": 0.2,
               "dispatch": {"model": "sonnet", "input_tokens": 3}}
    assert cost_or_token_keys(payload) == ["Cost", "input_tokens"]


def test_cost_or_token_keys_of_an_attempt_without_them_is_empty():
    payload = {"duration": 1.0, "exit_code": 0, "status": "failed",
               "prompt_path": "p", "result_path": "r", "stdout_path": "s", "n": 1,
               "dispatch": {"harness": "claude", "model": "sonnet", "timeout": 1800.0}}
    assert cost_or_token_keys(payload) == []


def test_watched_event_payloads_carry_the_recorded_keys(am, seeded_run):
    events = watch_run_once(am, seeded_run.id)
    assert WATCHED_EVENTS <= {event["event"] for event in events}, events
    assert_payload_keys(events)


def test_attempt_payloads_carry_no_cost_or_token_keys(am, seeded_run):
    attempts = [event for event in watch_run_once(am, seeded_run.id)
                if event["event"] == "attempt_upsert"]
    assert attempts, "the seeded run recorded no attempt_upsert"
    for event in attempts:
        assert cost_or_token_keys(event["payload"]) == [], event
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "payload_keys or recorded_keys or cost_or_token or attempt_payloads"`
Expected: 7 FAILED, with `NameError` for `PAYLOAD_KEYS`, `assert_payload_keys` or `cost_or_token_keys`.

- [ ] **Step 3: Add the constant**

In `tests/contract/test_am_shapes.py`, directly after the line
`WATCHED_EVENTS = {"run_upsert", "story_upsert", "subtask_upsert", "phase_upsert", "attempt_upsert"}`, insert:

```python
# The payload keys of each watched event as the installed am writes them, every
# time it records that event. An attempt carries no cost or token figure.
PAYLOAD_KEYS = {
    "run_upsert": {"base_branch", "branch_prefix", "config", "id", "milestone_id", "repo_dir",
                   "started_at", "status", "workflow"},
    "story_upsert": {"card_id", "level", "status", "tip_branch", "title"},
    "subtask_upsert": {"base_branch", "branch", "card_id", "status", "worktree_path"},
    "phase_upsert": {"detail", "ended_at", "kind", "name", "started_at", "status"},
    "attempt_upsert": {"dispatch", "duration", "exit_code", "n", "prompt_path", "result_path",
                       "status", "stdout_path"},
}
```

- [ ] **Step 4: Add the two helpers**

Directly after `watch_run_once` (Task 1), insert:

```python
def assert_payload_keys(events):
    """Every watched event's payload has exactly its PAYLOAD_KEYS; events of
    other kinds are not checked."""
    for event in events:
        expected = PAYLOAD_KEYS.get(event["event"])
        if expected is not None:
            assert set(event["payload"]) == expected, \
                f"{event['event']} payload keys drifted: {sorted(event['payload'])} in {event}"


def cost_or_token_keys(payload):
    """The keys of `payload`, and of its dict values, naming a cost or a token
    (case-insensitive)."""
    keys = list(payload)
    for value in payload.values():
        if isinstance(value, dict):
            keys.extend(value)
    return [key for key in keys if "cost" in key.lower() or "token" in key.lower()]
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "payload_keys or recorded_keys or cost_or_token or attempt_payloads"`
Expected: 7 passed.

- [ ] **Step 6: See the payload test fail against the real am on a wrong expectation, then restore**

Temporarily remove `"dispatch", ` from the `"attempt_upsert"` entry of `PAYLOAD_KEYS`, so it reads:

```python
    "attempt_upsert": {"duration", "exit_code", "n", "prompt_path", "result_path",
                       "status", "stdout_path"},
```

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "test_watched_event_payloads_carry_the_recorded_keys"`
Expected: 1 FAILED with `AssertionError: attempt_upsert payload keys drifted: [...'dispatch'...]`.

Restore the entry to:

```python
    "attempt_upsert": {"dispatch", "duration", "exit_code", "n", "prompt_path", "result_path",
                       "status", "stdout_path"},
```

Run the same command. Expected: 1 passed.

- [ ] **Step 7: Run the full suite**

Run: `timeout 600 bash tests/run.sh`
Expected: pytest reports all passed (including `tests/contract` and `tests/architecture`), every QML `Totals` line shows 0 failed, exit status 0.

- [ ] **Step 8: Commit**

```bash
git add tests/contract/test_am_shapes.py
git commit -m "test(contract): watched-event payload keys as am writes them; no cost or token on attempts"
```

---

## Spec coverage (self-review)

| spec item | task |
|---|---|
| `watch_run_once` helper, envelope checks, am's output on failure | Task 1 Steps 1-4 |
| Behavior 1: envelope, `assert_seeded_events`, `seq` int type | Task 1 `test_watch_run_returns_the_events_envelope_with_journal_line_keys` |
| Behavior 1: equals run-filtered `am watch --all` | Task 1 `test_watch_run_is_the_run_filtered_watch_all` |
| Behavior 2: `--since` 0, 1, n-1; n >= 2 asserted | Task 2 `test_watch_run_since_keeps_only_events_with_a_greater_seq` |
| Behavior 2: `--since` n and n+1000 → `[]`, exit 0, same envelope | Task 2 `test_watch_run_since_at_or_beyond_the_last_seq_is_an_empty_events_list` (envelope and exit 0 via `watch_run_once`) |
| Behavior 3: `PAYLOAD_KEYS`, every occurrence, exact equality, message names kind, other kinds ignored, `set(PAYLOAD_KEYS) == WATCHED_EVENTS` | Task 3 |
| Behavior 4: no cost/token key top-level or in dict values, case-insensitive, at least one attempt | Task 3 |
| Error paths: am absent / brd-git absent / hang | existing `pytestmark`, `require_tool`, `AM_TIMEOUT` (unchanged) |
| Error path: refusal or non-JSON → fail with stdout and stderr | Task 1 fake-am tests |
| TDD note: wrong expectation against real am first | Task 1 Step 5, Task 2 Steps 1-3, Task 3 Step 6 |
| Verification: `bash tests/run.sh` green | Task 3 Step 7 |
<!-- task-pipeline: validated -->
