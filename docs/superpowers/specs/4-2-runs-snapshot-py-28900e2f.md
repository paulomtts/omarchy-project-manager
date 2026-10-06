# 4.2 runs-snapshot.py: `canceled` is terminal (card 28900e2f)

Narrowed from `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
("the parent" below): Decision 8 (line 172), "Both spellings, both schemas"
(lines 286-292, the `runs-snapshot.py` bullet at line 292), the consumer table
row for `runs-snapshot.py:33` (line 128), and "Not changed" (lines 312-313: the
`am status` fan-out and the 10-terminal cap stay). Parent story 27d8a320, work
breakdown item 4 (parent lines 329-330). Fixture rule: parent lines 257-267.

This card is the `runs-snapshot.py` part of item 4 only. `runs.js` (card 4.1,
already on this branch), `runs-watch.py` hello schemas, `RunStore.amSchema` /
`amVersion` and the Runs footer are sibling cards.

## Starting point

- A later `am` migration respells the run status `canceled` (parent line 288).
  No captured fixture contains `cancelled` or `canceled`; `tests/fixtures/am/runs.json`
  rows are `started` and `done` only (parent lines 37-38).
- `core/backend/runs/runs-snapshot.py:33`:
  `TERMINAL = frozenset({"done", "escalated", "stopped", "cancelled"})`.
  A `canceled` run is therefore non-terminal: it is always selected and never
  counts toward `TERMINAL_LIMIT` (10) (parent line 128).
- The module docstring (lines 6-8) lists `(terminal: done, escalated, stopped,
  cancelled)`.
- Nothing else in `core/backend` reads `TERMINAL`.
- `tests/core/backend/runs/test_runs_snapshot.py`:
  - `test_terminal_set_pinned` (lines 342-356) is parametrized
    `(status, kept)` over 12 runs of one status: `done/escalated/stopped/cancelled`
    keep 10, `started/paused/something-new` keep 12. The comment above it labels
    the non-captured statuses `synthetic:`; the comment inside says "Any status
    outside the four is non-terminal".
  - `row_for(run_id, status)` (lines 112-122) copies a real `am runs` row from
    `runs.json` (or `status-escalated.json`'s `_am_runs_row`) and sets `id` and
    `status`; `status_for` does the same on a captured `am status` envelope
    (`status-done.json` for a status no capture has). Both are already labelled
    `synthetic:` in their docstrings and are the only way rows are built.
- `tests/contract/test_am_fixtures.py:66` already pins both spellings in the
  status vocabulary. No change.

## Required behaviour

1. **Both spellings are terminal.** A run whose `am runs` `status` is exactly
   `cancelled` or exactly `canceled` is terminal: it is selected only if it is
   among the first 10 terminal runs in am's order, and it counts toward that cap
   (parent line 292). The terminal set is exactly
   `{done, escalated, stopped, cancelled, canceled}`.
2. **Exact match.** Any other status, including `Canceled`, `CANCELED`,
   ` canceled` and `cancel`, stays non-terminal: always selected, never counted.
3. **Nothing else changes.** am's order is kept; every selected run still gets
   one `am status <id> --repo-dir R` call; the output envelope, error types,
   exit codes and the cap value (10) are unchanged (parent lines 312-313). Each
   entry's `status` is still the `am status` data passed through unchanged, so
   its `run.status` carries am's spelling verbatim (no rewriting).
4. **Docstring.** The module docstring's terminal list names both spellings:
   `(terminal: done, escalated, stopped, cancelled, canceled)`. The comment
   above `TERMINAL` states the contract only (no narrative about am's migration,
   no card or plan references).

## Error paths

- A mixed list (some `cancelled`, some `canceled`, some `done`) counts all of
  them against the same single cap of 10; there is no per-spelling cap.
- A status that is not a string or is missing is unchanged from today
  (non-terminal). This card adds no handling for it.

## Tests (all in `tests/core/backend/runs/test_runs_snapshot.py`, pytest tier)

Pytest tier because `runs-snapshot.py` is a Python helper run as a subprocess
against the fake `am` that serves the captured fixtures (`world` fixture,
`seed`, `run`, `calls`); every existing test of it lives here and runs through
`bash tests/run.sh`. No QML or contract test can observe the selection.

Inputs come from `tests/fixtures/am/` via `json.load` through the existing
`row_for` / `status_for` helpers, which build labelled copies (parent lines
265-267). No new helper and no new fixture.

Changed tests:

1. `test_terminal_set_pinned`: add `("canceled", 10)` to the terminal cases
   and `("Canceled", 12)`, `(" canceled", 12)`, `("cancel", 12)` to the
   non-terminal cases (behaviours 1, 2). Update the `synthetic:` comment above
   it to name every status no capture has, now including `canceled`,
   `Canceled`, ` canceled` and `cancel`; update the inside comment to
   "Any status outside the five is non-terminal".
2. `test_status_fanout_selection`: the terminal-status cycle
   `["escalated", "cancelled", "stopped"]` becomes
   `["escalated", "cancelled", "canceled", "stopped"]` (with `i % 4`), so the
   cap of 10 is proven over a list mixing both spellings (error path 1). The
   expected ids and calls are unchanged: t1..t10 are kept, t11 and t12 dropped,
   n1..n3 kept.
3. `test_fake_am_serves_the_captures`: add `"canceled"` to the `row_for`
   status list, pinning that a `canceled` row keeps a real `am runs` row's 11
   keys.

New test:

4. `test_canceled_spelling_reported_verbatim`: `runs = [row_for("c1",
   "canceled"), row_for("c2", "cancelled")]`, `seed(world, runs)`; exit 0 and
   `out["runs"] == [expected(runs[0], status_for("c1", "canceled")),
   expected(runs[1], status_for("c2", "cancelled"))]`, and
   `[r["status"]["run"]["status"] for r in out["runs"]] == ["canceled",
   "cancelled"]` (behaviour 3). Rows come from `row_for`/`status_for`, already
   labelled `synthetic:`.

Red first: the `canceled` case of test 1 fails on today's code (12 kept, not
10). Test 2 fails too (the `canceled` runs are not counted, so t11 and t12 are
selected). Tests 3 and 4 and the non-terminal cases of test 1 pass already; they
pin the exact match and the verbatim spelling.

Verification: `bash tests/run.sh` green, including `tests/architecture`
(unaffected: no component, layering or icon change).

## Out of scope

- `core/domain/runs.js` (card 4.1, done), `runs-watch.py` hello schema 1/2,
  `RunStore.amSchema` / `amVersion`, the Runs footer: sibling cards.
- The cap value, the `am status` fan-out, the output envelope (parent lines
  312-313).
- A `canceled` fixture: none was captured; the labelled in-test edit stands
  for it.
- Docs (`docs/architecture.md`, README): work breakdown item 5.
