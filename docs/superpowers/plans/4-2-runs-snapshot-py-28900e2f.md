# 4.2 runs-snapshot.py: `canceled` is terminal: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `core/backend/runs/runs-snapshot.py` treats an `am runs` row whose status is exactly `canceled` as terminal, like `cancelled`, so it counts toward the cap of 10 terminal runs.

**Architecture:** One edit to one constant: `TERMINAL` gains `"canceled"`. The module docstring and the comment above `TERMINAL` name both spellings. `select_runs` already does an exact `in TERMINAL` set lookup, so case and whitespace variants stay non-terminal with no extra code. The output is unchanged: each entry's `status` is still `am status` data passed through verbatim.

**Tech Stack:** Python 3 (stdlib only), pytest, run as a subprocess against a fake `am` serving the captures in `tests/fixtures/am/`.

**Spec:** `docs/superpowers/specs/4-2-runs-snapshot-py-28900e2f.md`. The full text is copied below.

## Spec (verbatim)

> # 4.2 runs-snapshot.py: `canceled` is terminal (card 28900e2f)
>
> Narrowed from `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
> ("the parent" below): Decision 8 (line 172), "Both spellings, both schemas"
> (lines 286-292, the `runs-snapshot.py` bullet at line 292), the consumer table
> row for `runs-snapshot.py:33` (line 128), and "Not changed" (lines 312-313: the
> `am status` fan-out and the 10-terminal cap stay). Parent story 27d8a320, work
> breakdown item 4 (parent lines 329-330). Fixture rule: parent lines 257-267.
>
> This card is the `runs-snapshot.py` part of item 4 only. `runs.js` (card 4.1,
> already on this branch), `runs-watch.py` hello schemas, `RunStore.amSchema` /
> `amVersion` and the Runs footer are sibling cards.
>
> ## Starting point
>
> - A later `am` migration respells the run status `canceled` (parent line 288).
>   No captured fixture contains `cancelled` or `canceled`; `tests/fixtures/am/runs.json`
>   rows are `started` and `done` only (parent lines 37-38).
> - `core/backend/runs/runs-snapshot.py:33`:
>   `TERMINAL = frozenset({"done", "escalated", "stopped", "cancelled"})`.
>   A `canceled` run is therefore non-terminal: it is always selected and never
>   counts toward `TERMINAL_LIMIT` (10) (parent line 128).
> - The module docstring (lines 6-8) lists `(terminal: done, escalated, stopped,
>   cancelled)`.
> - Nothing else in `core/backend` reads `TERMINAL`.
> - `tests/core/backend/runs/test_runs_snapshot.py`:
>   - `test_terminal_set_pinned` (lines 342-356) is parametrized
>     `(status, kept)` over 12 runs of one status: `done/escalated/stopped/cancelled`
>     keep 10, `started/paused/something-new` keep 12. The comment above it labels
>     the non-captured statuses `synthetic:`; the comment inside says "Any status
>     outside the four is non-terminal".
>   - `row_for(run_id, status)` (lines 112-122) copies a real `am runs` row from
>     `runs.json` (or `status-escalated.json`'s `_am_runs_row`) and sets `id` and
>     `status`; `status_for` does the same on a captured `am status` envelope
>     (`status-done.json` for a status no capture has). Both are already labelled
>     `synthetic:` in their docstrings and are the only way rows are built.
> - `tests/contract/test_am_fixtures.py:66` already pins both spellings in the
>   status vocabulary. No change.
>
> ## Required behaviour
>
> 1. **Both spellings are terminal.** A run whose `am runs` `status` is exactly
>    `cancelled` or exactly `canceled` is terminal: it is selected only if it is
>    among the first 10 terminal runs in am's order, and it counts toward that cap
>    (parent line 292). The terminal set is exactly
>    `{done, escalated, stopped, cancelled, canceled}`.
> 2. **Exact match.** Any other status, including `Canceled`, `CANCELED`,
>    ` canceled` and `cancel`, stays non-terminal: always selected, never counted.
> 3. **Nothing else changes.** am's order is kept; every selected run still gets
>    one `am status <id> --repo-dir R` call; the output envelope, error types,
>    exit codes and the cap value (10) are unchanged (parent lines 312-313). Each
>    entry's `status` is still the `am status` data passed through unchanged, so
>    its `run.status` carries am's spelling verbatim (no rewriting).
> 4. **Docstring.** The module docstring's terminal list names both spellings:
>    `(terminal: done, escalated, stopped, cancelled, canceled)`. The comment
>    above `TERMINAL` states the contract only (no narrative about am's migration,
>    no card or plan references).
>
> ## Error paths
>
> - A mixed list (some `cancelled`, some `canceled`, some `done`) counts all of
>   them against the same single cap of 10; there is no per-spelling cap.
> - A status that is not a string or is missing is unchanged from today
>   (non-terminal). This card adds no handling for it.
>
> ## Tests (all in `tests/core/backend/runs/test_runs_snapshot.py`, pytest tier)
>
> Pytest tier because `runs-snapshot.py` is a Python helper run as a subprocess
> against the fake `am` that serves the captured fixtures (`world` fixture,
> `seed`, `run`, `calls`); every existing test of it lives here and runs through
> `bash tests/run.sh`. No QML or contract test can observe the selection.
>
> Inputs come from `tests/fixtures/am/` via `json.load` through the existing
> `row_for` / `status_for` helpers, which build labelled copies (parent lines
> 265-267). No new helper and no new fixture.
>
> Changed tests:
>
> 1. `test_terminal_set_pinned`: add `("canceled", 10)` to the terminal cases
>    and `("Canceled", 12)`, `(" canceled", 12)`, `("cancel", 12)` to the
>    non-terminal cases (behaviours 1, 2). Update the `synthetic:` comment above
>    it to name every status no capture has, now including `canceled`,
>    `Canceled`, ` canceled` and `cancel`; update the inside comment to
>    "Any status outside the five is non-terminal".
> 2. `test_status_fanout_selection`: the terminal-status cycle
>    `["escalated", "cancelled", "stopped"]` becomes
>    `["escalated", "cancelled", "canceled", "stopped"]` (with `i % 4`), so the
>    cap of 10 is proven over a list mixing both spellings (error path 1). The
>    expected ids and calls are unchanged: t1..t10 are kept, t11 and t12 dropped,
>    n1..n3 kept.
> 3. `test_fake_am_serves_the_captures`: add `"canceled"` to the `row_for`
>    status list, pinning that a `canceled` row keeps a real `am runs` row's 11
>    keys.
>
> New test:
>
> 4. `test_canceled_spelling_reported_verbatim`: `runs = [row_for("c1",
>    "canceled"), row_for("c2", "cancelled")]`, `seed(world, runs)`; exit 0 and
>    `out["runs"] == [expected(runs[0], status_for("c1", "canceled")),
>    expected(runs[1], status_for("c2", "cancelled"))]`, and
>    `[r["status"]["run"]["status"] for r in out["runs"]] == ["canceled",
>    "cancelled"]` (behaviour 3). Rows come from `row_for`/`status_for`, already
>    labelled `synthetic:`.
>
> Red first: the `canceled` case of test 1 fails on today's code (12 kept, not
> 10). Test 2 fails too (the `canceled` runs are not counted, so t11 and t12 are
> selected). Tests 3 and 4 and the non-terminal cases of test 1 pass already; they
> pin the exact match and the verbatim spelling.
>
> Verification: `bash tests/run.sh` green, including `tests/architecture`
> (unaffected: no component, layering or icon change).
>
> ## Out of scope
>
> - `core/domain/runs.js` (card 4.1, done), `runs-watch.py` hello schema 1/2,
>   `RunStore.amSchema` / `amVersion`, the Runs footer: sibling cards.
> - The cap value, the `am status` fan-out, the output envelope (parent lines
>   312-313).
> - A `canceled` fixture: none was captured; the labelled in-test edit stands
>   for it.
> - Docs (`docs/architecture.md`, README): work breakdown item 5.

## Global Constraints

- The terminal set is exactly `{done, escalated, stopped, cancelled, canceled}`; match is exact and case-sensitive.
- `TERMINAL_LIMIT` stays `10`; one cap shared by every terminal spelling, no per-spelling cap.
- am's order is kept; every selected run gets exactly one `am status <id> --repo-dir R` call.
- Output envelope, error types (`AmMissing`, `AmBadOutput`, `Usage`, `HelperError`), exit codes (0/1/2) unchanged.
- Each entry's `status` is the `am status` data passed through unchanged: `run.status` keeps am's spelling, no rewriting.
- Module docstring terminal list reads exactly `(terminal: done, escalated, stopped, cancelled, canceled)`.
- The comment above `TERMINAL` states the contract only: no narrative about am's migration, no card or plan references.
- No new helper and no new fixture in the tests: rows come from the existing `row_for` / `status_for`, already labelled `synthetic:`.
- All tests go in `tests/core/backend/runs/test_runs_snapshot.py` (pytest tier).
- Verification: `bash tests/run.sh` green, `tests/architecture` included.
- Not edited: `core/domain/runs.js`, `runs-watch.py`, `RunStore`, the Runs footer, docs, `tests/contract/test_am_fixtures.py`.

## Review Focus

1. An all-caps `CANCELED` status (a plausible respelling) must stay non-terminal: always selected, never counted. The spec names it in behaviour 2 but its test list omits it. Pinned in Task 1 by adding `("CANCELED", 12)` to `test_terminal_set_pinned`.
2. A trailing-space `canceled ` must stay non-terminal (exact match, no `strip()`). Pinned in Task 1 by adding `("canceled ", 12)` to `test_terminal_set_pinned`.
3. A `canceled` run beyond the 10th terminal run must be dropped and must get no `am status` call. Pinned in Task 1 by `test_status_fanout_selection`, which asserts the exact `calls(world)` list over a mix of both spellings.
4. The snapshot must not rewrite `canceled` to `cancelled` (or the reverse) in its output: the UI side (card 4.1) relies on seeing am's spelling. Pinned in Task 1 by `test_canceled_spelling_reported_verbatim`.
5. A non-string or missing status: the spec says "unchanged from today". Today `run_list` already rejects it as `AmBadOutput` (`test_am_bad_output[run-status-not-string]` and `[run-without-status]`), so "unchanged" means it is still rejected, not newly treated as non-terminal. No new test; the existing parametrized cases pin it and must stay green.

---

## How to run the tests

`python3` on this machine has no pytest; use uv's throwaway environment:

- One file: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_snapshot.py -q`
- One test: append `::test_name` (or `-k name`).
- Everything: `bash tests/run.sh` (pytest then every QML test; it falls back to `uv` by itself).

Baseline before this plan: `39 passed` for `test_runs_snapshot.py`.

## File Structure

- Modify `core/backend/runs/runs-snapshot.py`: module docstring (lines 6-8), the comment above `TERMINAL` and `TERMINAL` itself (lines 31-33).
- Modify `tests/core/backend/runs/test_runs_snapshot.py`: `test_fake_am_serves_the_captures` (line 300), `test_status_fanout_selection` (lines 322-339), `test_terminal_set_pinned` (lines 342-355); add `test_canceled_spelling_reported_verbatim` right after `test_terminal_set_pinned`.

One task: the change is one constant, and every test exercises that constant through the same subprocess.

---

### Task 1: `canceled` is terminal in the runs snapshot

**Files:**
- Modify: `core/backend/runs/runs-snapshot.py:6-8`, `:31-33`
- Test: `tests/core/backend/runs/test_runs_snapshot.py:281-356` (and a new test after line 356)

**Interfaces:**
- Consumes (existing test helpers in `test_runs_snapshot.py`, do not change them):
  - `world` pytest fixture: dict with `tmp`, `bin`, `am`, `home`, `data`, `proj`.
  - `row_for(run_id: str, status: str) -> dict`: a copy of a real `am runs` row (11 keys) with `id` and `status` set.
  - `status_for(run_id: str, status: str) -> dict`: a copy of captured `am status` data (`status-done.json` for a status with no capture) with `run.id` and `run.status` set.
  - `seed(world, runs: list)`: fake am lists `runs` and answers `am status` for each via `status_for`.
  - `run(world) -> (exit_code: int, payload: dict)`: runs the helper, asserts exactly one JSON line.
  - `calls(world) -> list[list[str]]`: the argv of every fake-am call.
  - `expected(run: dict, data: dict) -> dict`: `run` with `status` replaced by `data`.
- Produces: `runs-snapshot.py` module constant `TERMINAL = frozenset({"done", "escalated", "stopped", "cancelled", "canceled"})`. `TERMINAL_LIMIT` stays `10`.

- [ ] **Step 1: Extend `test_terminal_set_pinned` (failing for `canceled`)**

In `tests/core/backend/runs/test_runs_snapshot.py`, replace lines 342-355 (the comment, the decorator and the function) with:

```python
# synthetic: stopped, cancelled, canceled, Canceled, CANCELED, " canceled",
# "canceled ", cancel, paused and something-new are run statuses no capture has.
@pytest.mark.parametrize("status,kept", [
    ("done", 10), ("escalated", 10), ("stopped", 10), ("cancelled", 10),
    ("canceled", 10),
    ("started", 12), ("paused", 12), ("something-new", 12),
    ("Canceled", 12), ("CANCELED", 12), (" canceled", 12), ("canceled ", 12),
    ("cancel", 12),
])
def test_terminal_set_pinned(world, status, kept):
    # `stopped` is "parked" in the domain table but terminal here: it counts
    # toward the cap of 10. Any status outside the five is non-terminal.
    runs = [row_for("x%02d" % i, status) for i in range(12)]
    seed(world, runs)
    code, out = run(world)
    assert code == 0
    assert [r["id"] for r in out["runs"]] == ["x%02d" % i for i in range(kept)]
```

- [ ] **Step 2: Mix both spellings in `test_status_fanout_selection` (failing)**

Replace lines 328-329:

```python
            + [row_for("t%d" % i, ["escalated", "cancelled", "stopped"][i % 3])
               for i in range(6, 13)]
```

with:

```python
            + [row_for("t%d" % i, ["escalated", "cancelled", "canceled", "stopped"][i % 4])
               for i in range(6, 13)]
```

Leave the rest of the test unchanged: `want` stays `["n1", "t1", "t2", "t3", "t4", "t5", "n2", "t6", "t7", "t8", "t9", "t10", "n3"]` and the `calls(world)` assertion stays. (With `i % 4`, t6 and t10 are `canceled`, t9 is `cancelled`; the cap of 10 must count them all.)

- [ ] **Step 3: Pin a `canceled` row's shape in `test_fake_am_serves_the_captures`**

Replace line 300:

```python
    for status in ["started", "done", "escalated", "cancelled", "something-new"]:
```

with:

```python
    for status in ["started", "done", "escalated", "cancelled", "canceled", "something-new"]:
```

- [ ] **Step 4: Add `test_canceled_spelling_reported_verbatim`**

Insert right after `test_terminal_set_pinned` (before `def test_repo_dir_passed`), separated by two blank lines on each side:

```python
def test_canceled_spelling_reported_verbatim(world):
    # Both spellings pass through as am printed them: no rewriting either way.
    runs = [row_for("c1", "canceled"), row_for("c2", "cancelled")]
    seed(world, runs)
    code, out = run(world)
    assert code == 0
    assert out["runs"] == [expected(runs[0], status_for("c1", "canceled")),
                           expected(runs[1], status_for("c2", "cancelled"))]
    assert [r["status"]["run"]["status"] for r in out["runs"]] == ["canceled", "cancelled"]
```

- [ ] **Step 5: Run the tests to verify the right ones fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_snapshot.py -q`

Expected: exactly 2 failures, everything else passes (baseline 39 + 6 new parametrized cases + 1 new test = 46 collected):
- `test_terminal_set_pinned[canceled-10]`: `AssertionError` (12 ids returned, list of 10 expected).
- `test_status_fanout_selection`: `AssertionError` (ids include `t11` and `t12`; t6 and t10 are not counted).

`test_canceled_spelling_reported_verbatim`, `test_fake_am_serves_the_captures` and the non-terminal `Canceled`/`CANCELED`/` canceled`/`canceled `/`cancel` cases already pass. If any of them fails, stop: the test is wrong, not the code.

- [ ] **Step 6: Make `canceled` terminal**

In `core/backend/runs/runs-snapshot.py`, replace lines 6-8 of the module docstring:

```python
Runs `am runs --repo-dir R` (newest first), keeps am's order and selects every
non-terminal run plus the first 10 terminal ones (terminal: done, escalated,
stopped, cancelled), then runs `am status <id> --repo-dir R` for each selected
run.
```

with:

```python
Runs `am runs --repo-dir R` (newest first), keeps am's order and selects every
non-terminal run plus the first 10 terminal ones (terminal: done, escalated,
stopped, cancelled, canceled), then runs `am status <id> --repo-dir R` for each
selected run.
```

Replace lines 31-33:

```python
# The monitor spec's finished list. `stopped` is "parked" (resumable) in the domain
# table, but for the snapshot it is terminal and counts toward the cap.
TERMINAL = frozenset({"done", "escalated", "stopped", "cancelled"})
```

with:

```python
# The finished statuses, matched exactly. A cancelled run is terminal under either
# spelling, `cancelled` or `canceled`. `stopped` is "parked" (resumable) in the
# domain table, but for the snapshot it is terminal and counts toward the cap.
TERMINAL = frozenset({"done", "escalated", "stopped", "cancelled", "canceled"})
```

Do not touch `select_runs`, `TERMINAL_LIMIT` or anything else.

- [ ] **Step 7: Run the file to verify everything passes**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_snapshot.py -q`
Expected: `46 passed`.

- [ ] **Step 8: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest all passed (including `tests/architecture` and `tests/contract`), every QML file `Totals: N passed, 0 failed`, exit status 0. Check `echo $?` prints `0`.

- [ ] **Step 9: Commit**

```bash
git add core/backend/runs/runs-snapshot.py tests/core/backend/runs/test_runs_snapshot.py
git commit -m "feat(runs): runs-snapshot counts canceled as terminal"
```

---

## Self-review against the spec

- Behaviour 1 (both spellings terminal, one cap): Steps 1, 2, 6.
- Behaviour 2 (exact match: `Canceled`, `CANCELED`, ` canceled`, `cancel` non-terminal): Step 1 (plus `canceled `).
- Behaviour 3 (nothing else changes; verbatim spelling): Step 4; Step 2 keeps the `calls` assertion; Step 8 runs the unchanged error-path tests.
- Behaviour 4 (docstring and contract-only comment): Step 6.
- Error path 1 (mixed list, single cap): Step 2.
- Error path 2 (non-string/missing status unchanged): no code change; existing `test_am_bad_output` cases stay green in Steps 7-8 (see Review Focus 5).
- Tests 1-4 of the spec: Steps 1-4. Red first: Step 5. Verification: Step 8.
- Out of scope items untouched: Global Constraints last line.
<!-- task-pipeline: validated -->
