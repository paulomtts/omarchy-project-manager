# `runs-history.py`: one page of a project's older runs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A read-only helper `core/backend/runs/runs-history.py ROOT --before ISO [--limit K] [--status S,...] [--since ISO]` that runs `am runs --repo-dir ROOT`, keeps the rows matching the status set and time window, pages the first K (default 10, at most 25), replaces each paged row's `status` with its `am status` data, and prints one JSON line `{"ok": true, "runs": [...], "more": bool}` or one failure line.

**Architecture:** One stdlib-only Python script shaped like `core/backend/runs/runs-snapshot.py` (`failure` / `parse_args` / `main` / `guarded`), reusing `common/am_runs.py` (`call_am`, `run_list`, `run_status`, `TERMINAL`, `AM_TIMEOUT`, `AmFailure`, `bad_output`) and `common/json_line.emit`. The ISO time parser `parse_time` moves from `start-run.py` into `common/am_runs.py` so both scripts share one copy. Tests: black-box subprocess runs against a fake `am` on a temp `PATH` (harness copied from `tests/core/backend/runs/test_runs_snapshot.py`), plus two in-process tests for the catch-all.

**Tech Stack:** Python 3.13 stdlib (`datetime`, `json`, `os`, `re`, `shutil`, `subprocess`, `sys`), pytest (run via `uv run --with pytest`, because the system `python3` has no pytest).

**Spec:** `docs/superpowers/specs/1-2-runs-history-py-one-e8f77799.md` (reproduced verbatim below, headings demoted one level).

---

## Spec (verbatim)

### 1.2 `runs-history.py`: one page of a project's older runs — design

Card: `e8f77799-0da0-48fd-8d5c-ba80748b48ef` (subtask of story `8aaf0cb6-3038-487c-b262-bfe02df3e39d`,
blocked by 1.1 `e1990cac`, `board-titles.py`, which is done).
Parent design: `docs/superpowers/specs/2026-10-05-run-history-titles-design.md` (cited below as
**parent**), section *History › Data* (lines 119–135), *Errors* (lines 194–204) and *Testing*
(lines 211–214).

#### Purpose

`RunHistoryStore` (a later card) needs the older finished runs of a project, a page at a time,
filtered by final state and age. This card delivers only the read-only helper that produces one
such page for ONE project root, and its tests.

#### The card overrides the parent

The parent (:121–135) describes a global keyset helper (`--before RUN`, `am runs --all-projects
--limit K --before RUN`, no client-side cap, a `cursor` field, `common/am_runs.py` not used). The
card replaces that interface. **Follow the card where they differ:**

| topic | parent | this card (binding) |
|---|---|---|
| scope | `--all-projects` | positional `ROOT`; `am runs --repo-dir ROOT` |
| page boundary | `--before RUN` (run id), passed to am | `--before ISO` (a time), applied here |
| limit | `K` passed to am as `--limit`, no client cap | default 10, capped at 25, applied here; am gets no `--limit` |
| output | `{ok, runs, more, cursor}` | `{ok, runs, more}`; no `cursor` |
| shared code | `common/am_runs.py` not used | reuse `common/am_runs.py`; no second copy |
| `am status` | `am status ID`, no `--repo-dir` (:128) | the card says `am status ID --repo-dir ROOT`; see C6 |

#### Inherited constraints

| # | constraint | source |
|---|---|---|
| C1 | Path: `core/backend/runs/runs-history.py ROOT --before ISO [--limit K] [--status S,...] [--since ISO]` | card |
| C2 | Runs `am runs --repo-dir ROOT` (am lists newest first) | card; parent :122–123 |
| C3 | Default `--status`: `done, escalated, stopped, cancelled, canceled` (both cancel spellings), matched exactly — this is `common.am_runs.TERMINAL` | card; parent :123–125; `core/backend/common/am_runs.py:15-18` |
| C4 | Keeps rows whose `started_at` is strictly before `--before` and, with `--since`, not before `--since` | card; parent :125 |
| C5 | Takes the first K kept rows, K default 10, at most 25 | card |
| C6 | Runs `am status ID` once per kept row, 60 s per call (`AM_TIMEOUT`). It is given **no** `--repo-dir`: the card's `--repo-dir ROOT` on `am status` contradicts the parent (:128, "no `--repo-dir`"), the shared `run_status` (`am_runs.py:3-4`, `:111-118`) and the snapshot test's `STATUS()` (`tests/core/backend/runs/test_runs_snapshot.py:58-60`). `run_status` is reused unchanged, so `test_runs_snapshot.py` stays unchanged and green as the card requires | parent :128; card |
| C7 | Prints `{"ok": true, "runs": [{<am runs row>, "status": <am status data>}], "more": bool}` — the run shape of the snapshot, so `Runs.normalizeRun` and Run detail work unchanged | card; parent :129–131 |
| C8 | Errors as `runs-snapshot.py`: `AmMissing`, `AmBadOutput`, `SchemaMismatch`, am's `ok:false` envelope unchanged, `HelperError`, `Usage` (exit 2) | card; parent :133–134; `core/backend/runs/runs-snapshot.py:19-33` |
| C9 | Reuse `common/am_runs.py`'s `call_am`, `run_list`, `run_status`, `TERMINAL`, `AM_TIMEOUT`, `AmFailure`, `bad_output`, and `common/json_line.emit`; no second copy of any of them. Move a helper into `common/` only when it is not already shared | card |
| C10 | Only `am` commands, as argv lists; am's database and on-disk layout are never read. It never writes | parent :56–57; `runs-snapshot.py:32-33` |
| C11 | `core/backend/**` imports only the stdlib and `core/backend/common`; a shared helper is defined once (`tests/architecture/test_layers.py:231-241`) | `docs/architecture.md`; card |
| C12 | Docstrings and comments state the contract only, no narrative | card |

#### Observable behavior

##### Output contract

Every run, on every path, writes **exactly one line** to stdout: one JSON object
(`common.json_line.emit`). Exit `0` success, `1` failure, `2` usage. The helper's own errors are
`{"ok": false, "error": {"type": <type>, "message": <non-empty sentence>}}`.

##### Argv grammar

`runs-history.py ROOT --before ISO [--limit K] [--status S,...] [--since ISO]`

- Exactly one positional, `ROOT`: non-empty, not starting with `-`. It may appear before, between
  or after the options.
- Each option is the flag followed by its value as the next argv item (`--before X`); the
  `--flag=value` form is not accepted. Each option at most once. A flag with no following item,
  or whose value is empty or starts with `-`, is a usage error.
- `--before` is required. `--before` and `--since` are ISO-8601 times as `datetime.fromisoformat`
  reads them (Python 3.11+: `2026-10-08T14:38:23Z`, `2026-10-08 14:38:23.739155+00:00`,
  `2026-10-08`). A time without an offset is UTC.
- `--limit K`: a decimal integer `>= 1` (digits only). A value above 25 is taken as 25 (not an
  error).
- `--status S,...`: split on `,`; every item non-empty (no `a,,b`, no trailing comma). Items are
  matched exactly against a row's `status`; an unknown name is allowed and matches nothing.
  Duplicates are harmless.
- Anything else (unknown flag, a second positional, a repeated option, a missing `--before`, an
  unparseable time, a bad `--limit`, an empty `--status` item) is **Usage**:
  `{"ok": false, "error": {"type": "Usage", "message": "usage: runs-history.py ROOT --before ISO [--limit K] [--status S,...] [--since ISO]"}}`,
  exit 2, and **am is not run** (not even looked up).
- `--since` at or after `--before` is valid and yields an empty page.

##### Decision order

1. **Usage** (above), exit 2.
2. **AmMissing** — `shutil.which("am")` is None: type `AmMissing`, message
   `"am is not installed."`, exit 1. No process started.
3. **List** — one `call_am(am, ["runs", "--repo-dir", ROOT], AM_TIMEOUT)`: exactly that argv, no
   `--limit`, no `--before`, no `--all-projects`. `ROOT` is passed as given (not resolved, not
   checked for existence: a bad root is am's `RepoDirError`, passed through).
   - am's `ok:false` envelope → re-emitted unchanged, exit 1, no `am status` call.
   - Not an envelope → `AmBadOutput` (from `call_am`), exit 1.
   - `run_list(data)` rejects the data (no `runs` list; a row without non-empty string `id` or
     string `status`) → `AmBadOutput`, exit 1.
   - Any row (kept or not) whose `started_at` is missing, not a string, or not parseable by the
     shared time parser → `AmBadOutput` (message names `am runs` and `started_at`, not the raw
     value), exit 1, no `am status` call. A `started_at` without an offset is UTC.
   - `as_of_seq` / `store_id` of the `am runs` data are neither required nor output.
4. **Filter**, in am's order (newest first, preserved; the helper never re-sorts): a row is kept
   when `status ∈ statuses` (the `--status` set, default `TERMINAL`) and
   `started_at < before` and (no `--since` or `started_at >= since`), comparing aware datetimes,
   never strings.
5. **Page** — the first `K` kept rows. `more` is `true` exactly when more than `K` rows were kept
   (`len(kept) > K`); it says nothing about rows beyond what `am runs` returned.
6. **Status fan-out** — for each paged row in order, one `run_status(am, id, AM_TIMEOUT)`
   (argv `["status", id]`, no `--repo-dir`). Its checks stand: data not an object → `AmBadOutput`;
   no non-negative integer `as_of_seq` → `SchemaMismatch`; am's `ok:false` → passed through. The
   first failing call stops the helper (exit 1); later rows are not asked and **no partial list
   is printed**. A row that was filtered out or beyond `K` is never asked.
7. **Success** — `{"ok": true, "runs": [...], "more": <bool>}`, exit 0, exactly those three keys.
   Each entry is a copy of the `am runs` row with every key and value verbatim except `status`,
   which is replaced by that run's `am status` data verbatim. An empty page is
   `{"ok": true, "runs": [], "more": false}` with no `am status` call.
8. **HelperError** — any other exception escaping `main` (an am that hangs past `AM_TIMEOUT`,
   `OSError` starting am, a bug), caught by `guarded(argv)` which re-raises `SystemExit`, as
   `runs-snapshot.py:80-89`: type `HelperError`, message `"The runs history failed: <reason>"`,
   exit 1, one line.

##### Side effects

The only processes started are `am runs` and the `am status` calls above, argv lists, stdin
`/dev/null` (from `call_am`). No file is created, changed or removed; am's store is not read.

#### Shared code

- `call_am`, `run_list`, `run_status`, `TERMINAL`, `AM_TIMEOUT`, `AmFailure`, `bad_output`:
  imported from `common.am_runs`, unchanged. `list_snapshot`/`select_runs` are **not** reused
  (fixed `--limit 200`, the snapshot cap, `as_of_seq`/`store_id`/`data_dir` in the output); the
  helper has its own short list → filter → page → status loop.
- **The ISO time parser already exists** as `parse_time(value)` in
  `core/backend/runs/start-run.py:182-194` (aware datetime; no offset is UTC; `None` when not a
  string or not parseable). A second copy is forbidden (C9), so it **moves** to
  `core/backend/common/am_runs.py` with the same name, signature, docstring and behavior;
  `start-run.py` imports it from there and keeps no local definition. `runs-history.py` uses it
  both for `--before`/`--since` (`None` → Usage) and for each row's `started_at`
  (`None` → AmBadOutput). `tests/core/backend/runs/test_start_run.py` stays unchanged and green.
- `failure(kind, message, code)`, `parse_args`, `main`, `guarded` are script-local, as in
  `runs-snapshot.py` and `board-titles.py` (`def failure(` is not on the architecture test's
  `DUPLICATED_PY` list; `def emit(` is, so `emit` is imported, never redefined).

#### Tests

##### `tests/core/backend/runs/test_runs_history.py` (new)

**Tier: subprocess (black-box CLI)** unless marked, because the contract is the process boundary
— argv to am, number and order of am calls, one stdout line, exit code — which only a real child
process with a fake `am` observes.

Harness: the fake-am harness of `tests/core/backend/runs/test_runs_snapshot.py:21-131`, copied
into this file (the `FAKE_AM` script that logs argv to `calls.log` and serves
`FAKE_AM_DIR/<runs|status-<id>>.out/.code`, unknown status → `UnknownRunError` exit 3; the
`world` fixture with a project dir named `my proj; echo x`; `env_for`; a `run()` that **asserts
exactly one stdout line on every call**). Test helpers are not production code and the snapshot
test file is not touched. Rows are built from a real row of `tests/fixtures/am/runs.json` with
test-local ids, statuses and `started_at` values, labelled `synthetic:`; status replies are
`tests/fixtures/am/status-done.json`'s envelope (it carries `as_of_seq`).

| # | test | proves |
|---|---|---|
| H1 | `test_runs_am_runs_with_repo_dir_only` | first logged argv is exactly `["runs", "--repo-dir", <proj>]` (the shell-hostile name intact); no `--limit`/`--before` (C2) |
| H2 | `test_before_is_strict` | rows at `before − 1µs`, exactly `before`, `before + 1s`: only the first is kept (C4) |
| H3 | `test_before_compares_times_not_strings` | `--before 2026-10-08T14:38:24Z` against `started_at` `2026-10-08 14:38:23.739155+00:00` (space form) and a row with `+02:00` offset that is earlier in UTC though later as a string: kept/dropped by instant |
| H4 | `test_naive_iso_is_utc` | `--before 2026-10-08T12:00:00` equals `…+00:00` in effect |
| H5 | `test_since_is_inclusive` | rows at `since − 1µs`, exactly `since`, after `since`: the first dropped, the other two kept |
| H6 | `test_default_status_is_terminal` | one row each of `started`, `done`, `escalated`, `stopped`, `cancelled`, `canceled`, plus `failed`: the five terminal ones kept in am's order, the others never asked (C3) |
| H7 | `test_status_filter` (parametrized) | `--status cancelled` keeps only `cancelled`; `--status canceled` only `canceled`; `--status cancelled,canceled` both; `--status done,escalated` those two; `--status nope` → empty page, no `am status` |
| H8 | `test_default_limit_is_10_and_more` | 12 kept rows → 10 runs (the 10 newest, in order), `more: true`; exactly 10 rows kept → `more: false` |
| H9 | `test_limit_caps_at_25` | 30 kept rows, `--limit 100` → 25 runs, `more: true`; `--limit 25` with exactly 25 kept → `more: false` |
| H10 | `test_limit_smaller_than_page` | `--limit 2` with 3 kept → 2 runs, `more: true` |
| H11 | `test_one_am_status_per_paged_row` | `calls.log` is exactly `am runs` then `["status", id]` once per returned run, in order, none with `--repo-dir`, none for filtered or beyond-K rows (C6) |
| H12 | `test_output_shape` | top-level keys exactly `ok, runs, more`; each entry equals the row with `status` replaced by the status data (deep equality) (C7) |
| H13 | `test_empty_page` | nothing kept → `{"ok": true, "runs": [], "more": false}`, exit 0, only the `am runs` call |
| H14 | `test_am_runs_envelope_passthrough` | `am runs` prints `RepoDirError` envelope, exit 2 → output equals it, exit 1, no status call (C8) |
| H15 | `test_am_status_envelope_passthrough_stops` | the second paged row's status is missing (fake → `UnknownRunError`) → output equals that envelope, exit 1, no third status call, no partial list |
| H16 | `test_am_runs_bad_output` (parametrized) | non-JSON; JSON list; object without `ok`; `data` without `runs`; a row without `id` → `AmBadOutput`, exit 1, no status call |
| H17 | `test_bad_started_at_is_bad_output` (parametrized) | a row (even one that the status filter would drop) with `started_at` missing / `null` / `"yesterday"` → `AmBadOutput`, exit 1, no status call |
| H18 | `test_status_without_as_of_seq_is_schema_mismatch` | status data lacking `as_of_seq` → `SchemaMismatch`, exit 1 |
| H19 | `test_am_missing` | `PATH` = an empty dir only → `AmMissing`, exit 1 (C8) |
| H20 | `test_usage` (parametrized) | no args; ROOT only (no `--before`); `--before` with no value; `--before notatime`; `--since notatime`; `--limit 0`; `--limit -1`; `--limit 2.5`; `--limit x`; `--status ""`; `--status a,,b`; `--status done,`; `--before=…`; repeated `--before`; two positionals; `""` as ROOT; `--bogus x` → `Usage`, exit 2, `calls.log` absent/empty |
| H21 | `test_option_order_is_free` | `--before X ROOT --limit 3` and `ROOT --limit 3 --before X` give the same output and am argv |
| H22 | `test_since_after_before_is_empty` | `--since` later than `--before` → empty page, exit 0 |
| H23 | `test_unexpected_exception_is_helper_error` — **tier: in-process unit** (module loaded with `importlib.util.spec_from_file_location`; `monkeypatch` its `call_am` to raise `RuntimeError("boom")`), because no external input makes the code raise | `guarded([...])` returns 1, one captured line, type `HelperError`, `boom` in the message |
| H24 | `test_timeout_is_helper_error` — **tier: in-process unit** (module's `AM_TIMEOUT` patched to a small value, fake am sleeps via `exec sleep`), because a real 60 s wait is unacceptable in the suite | `HelperError`, return 1, one line |

##### `tests/core/backend/common/test_am_runs.py` (extended)

**Tier: in-process unit**, because `parse_time` is a pure function now in the shared module.

| # | test | proves |
|---|---|---|
| P1 | `test_parse_time` (parametrized) | `Z`, `+00:00`, `+02:00`, space separator with microseconds, date only → the right aware UTC instant; no offset → UTC; `None`, `5`, `""`, `"yesterday"` → `None` |

##### Existing tiers that must stay green, unchanged

`tests/core/backend/runs/test_runs_snapshot.py`, `test_runs_snapshot_all.py`,
`tests/core/backend/runs/test_start_run.py` (proves the move kept `start-run.py`'s behavior),
`tests/architecture/` (layers; no duplicated helpers; icon glyph rules), and the full
`bash tests/run.sh`.

#### Out of scope

- `RunHistoryStore.qml`, `showOlder()`, dedupe against the snapshot, unregistered-project
  dropping, latest-wins (parent :153–172) — sibling cards.
- `filterRuns(…, "finished")`, `withinAge`, `historyStatuses`, `historyCursor` in
  `core/domain/runs.js` and every chip/UI surface, including **Show older** (parent :137–192).
- A `cursor` output field, an all-projects mode, passing `--before`/`--limit` to am (the card
  replaced them).
- Any change to `runs-snapshot.py`, `run_status`, `call_am`, `run_list`, `list_snapshot`, or to
  `am`/`brd`. The only change to `common/` is the `parse_time` move; the only change to
  `start-run.py` is importing it.
- Adding `def parse_time(` to the architecture test's `DUPLICATED_PY` list.
- Documenting the helper in `docs/architecture.md` or other docs — a later docs card.

#### Notes for the planner

- Implementation order that keeps every commit green: (1) move `parse_time` with P1 and the
  `start-run.py` import; (2) `runs-history.py` usage + `AmMissing` + list call; (3) filters and
  page; (4) status fan-out and error passthrough; (5) `HelperError`.
- Module docstring of `runs-history.py` states the full contract in the style of
  `runs-snapshot.py:1-34`: argv grammar, the am argv, filters, `more`'s definition, output shapes,
  error types, exit codes, "a list is never partial", and that `am status` gets no `--repo-dir`.

---

## Global Constraints

- Invocation: `core/backend/runs/runs-history.py ROOT --before ISO [--limit K] [--status S,...] [--since ISO]` (C1).
- The one list call is exactly `["runs", "--repo-dir", ROOT]` — no `--limit`, no `--before`, no `--all-projects` (C2).
- Default status set is `common.am_runs.TERMINAL` = `done, escalated, stopped, cancelled, canceled`, matched exactly (C3).
- Kept: `status ∈ statuses` and `started_at < before` and (no `--since` or `started_at >= since`), comparing aware datetimes, never strings (C4).
- K default `10`, values above `25` taken as `25` (C5).
- `am status ID` once per paged row via the shared `run_status` — **no `--repo-dir`** (C6).
- Success output: exactly `{"ok": true, "runs": [{<am runs row>, "status": <am status data>}], "more": bool}` (C7).
- Usage message, verbatim: `usage: runs-history.py ROOT --before ISO [--limit K] [--status S,...] [--since ISO]`; exit 2; am not run, not even looked up.
- AmMissing message, verbatim: `am is not installed.`; HelperError message: `The runs history failed: <reason>`.
- Exit `0` success, `1` failure, `2` usage; exactly one stdout line on every path (C8).
- Reuse `call_am`, `run_list`, `run_status`, `TERMINAL`, `AM_TIMEOUT`, `AmFailure`, `bad_output` from `common.am_runs`, `emit` from `common.json_line`; never redefine them. `parse_time` moves into `common/am_runs.py`; exactly one `def parse_time(` remains in the repo (C9).
- Only `am` commands, as argv lists; never read am's store; never write (C10).
- `core/backend/**` imports only the stdlib and `core/backend/common` (C11).
- Docstrings and comments state the contract only, no narrative (C12).
- `tests/core/backend/runs/test_runs_snapshot.py`, `test_runs_snapshot_all.py`, `test_start_run.py` and `tests/architecture/` are not edited and stay green.

## Review Focus

1. **`--limit` with non-ASCII digits** (`２`, `٣`): Python's `int()` accepts them, but the grammar is "digits only" — a person expects Usage, not a silently accepted limit. Pinned in Task 2 (`test_usage` cases `limit-fullwidth`, `limit-arabic-indic`).
2. **An absurdly long `--limit`** (5000 nines): `int()` refuses strings over 4300 digits with `ValueError`, which would surface as HelperError; a person expects it capped to 25 like any other large value. Pinned in Task 2 (`test_limit_caps_at_25`).
3. **A row whose `started_at` has no offset** (`2026-10-08T11:59:59`): the spec says it is UTC, but only `--before`'s naive form is in its test table; a naive row compared against an aware bound must neither crash (`TypeError`) nor be misplaced. Pinned in Task 2 (`test_naive_started_at_is_utc`).
4. **`--since` exactly equal to `--before`**: the spec calls it valid and empty; a person expects an empty page, not Usage. Pinned in Task 2 (`test_since_after_before_is_empty`).
5. **Duplicate `--status` items** (`done,done`): a person expects each run once, not twice. Pinned in Task 2 (`test_status_filter` case `duplicate`).

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `core/backend/common/am_runs.py` | Modify | gains `parse_time(value)` (moved, unchanged) and `import datetime` |
| `core/backend/runs/start-run.py` | Modify | imports `parse_time` from `common.am_runs`; local definition removed |
| `tests/core/backend/common/test_am_runs.py` | Modify | P1: `parse_time` unit tests |
| `core/backend/runs/runs-history.py` | Create (mode 755) | the helper |
| `tests/core/backend/runs/test_runs_history.py` | Create | H1–H24 plus the Review Focus cases |

Run every pytest command from the worktree root with `uv run --with pytest python3 -m pytest …` (the system `python3` has no pytest).

---

### Task 1: Move `parse_time` into `common/am_runs.py`

**Files:**
- Modify: `core/backend/common/am_runs.py:1-12` (docstring, imports) and append after `data_dir()` (ends line 63)
- Modify: `core/backend/runs/start-run.py:62` (import) and `:182-194` (delete definition)
- Test: `tests/core/backend/common/test_am_runs.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `common.am_runs.parse_time(value) -> datetime.datetime | None` — an aware datetime for an ISO-8601 string `datetime.fromisoformat` reads (no offset → UTC); `None` when `value` is not a string or does not parse.

- [ ] **Step 1: Write the failing test**

In `tests/core/backend/common/test_am_runs.py`, add `import datetime` to the import block so it reads:

```python
import copy
import datetime
import json
import os
import subprocess
import sys
import time
```

Then append at the end of the file:

```python
# --- parse_time ------------------------------------------------------------------

UTC = datetime.timezone.utc
AT = datetime.datetime(2026, 10, 8, 14, 38, 23, tzinfo=UTC)


@pytest.mark.parametrize("value, want", [
    ("2026-10-08T14:38:23Z", AT),
    ("2026-10-08T14:38:23+00:00", AT),
    ("2026-10-08T16:38:23+02:00", AT),
    ("2026-10-08 14:38:23.739155+00:00", AT.replace(microsecond=739155)),
    ("2026-10-08", datetime.datetime(2026, 10, 8, tzinfo=UTC)),
    ("2026-10-08T14:38:23", AT),
], ids=["z", "utc-offset", "plus-two", "space-micro", "date-only", "naive"])
def test_parse_time(value, want):
    got = am_runs.parse_time(value)
    assert got == want
    assert got.utcoffset() is not None


@pytest.mark.parametrize("value", [None, 5, "", "yesterday"],
                         ids=["none", "int", "empty", "words"])
def test_parse_time_rejects(value):
    assert am_runs.parse_time(value) is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/common/test_am_runs.py -q -k parse_time`
Expected: FAIL — `AttributeError: module 'common.am_runs' has no attribute 'parse_time'` (10 failures).

- [ ] **Step 3: Move the function**

In `core/backend/common/am_runs.py`, replace the module docstring and imports (lines 1–11):

```python
"""The am calls and the run snapshot shared by the run helpers.

Runs only `am runs <scope> --limit LIST_LIMIT` and `am status RUN` (never with
--repo-dir), as argv lists, each bounded by the caller's `timeout`; reads
nothing but am's stdout. Every failure is an AmFailure whose `payload` is the
one line to print, except subprocess.TimeoutExpired and OSError (am hangs or
cannot start), which propagate. Prints nothing and never exits.
"""
import json
import os
import subprocess
```

with:

```python
"""The am calls, the run snapshot and the time parser shared by the run helpers.

Runs only `am runs <scope> --limit LIST_LIMIT` and `am status RUN` (never with
--repo-dir), as argv lists, each bounded by the caller's `timeout`; reads
nothing but am's stdout. Every failure is an AmFailure whose `payload` is the
one line to print, except subprocess.TimeoutExpired and OSError (am hangs or
cannot start), which propagate. Prints nothing and never exits.
"""
import datetime
import json
import os
import subprocess
```

Then, directly after the `data_dir()` function (after its `return data` line), insert:

```python


def parse_time(value):
    """An ISO-8601 time (`Z` or an offset) as an aware datetime; no offset means UTC.
    None when it does not parse."""
    if not isinstance(value, str):
        return None
    try:
        when = datetime.datetime.fromisoformat(value)
    except ValueError:
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=datetime.timezone.utc)
    return when
```

In `core/backend/runs/start-run.py`, replace line 62:

```python
from common.json_line import emit  # noqa: E402
```

with:

```python
from common.am_runs import parse_time  # noqa: E402
from common.json_line import emit  # noqa: E402
```

and delete the local definition (old lines 182–194, plus one of the two blank lines that separated it from `matches`), i.e. remove exactly this block:

```python
def parse_time(value):
    """An ISO-8601 time (`Z` or an offset) as an aware datetime; no offset means UTC.
    None when it does not parse."""
    if not isinstance(value, str):
        return None
    try:
        when = datetime.datetime.fromisoformat(value)
    except ValueError:
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=datetime.timezone.utc)
    return when


```

Leave `import datetime` in `start-run.py`: it is still used by its clock function (line 162).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/common/test_am_runs.py tests/core/backend/runs/test_start_run.py tests/architecture -q`
Expected: PASS, no failures.

Run: `grep -rn "def parse_time(" core/`
Expected: exactly one line, `core/backend/common/am_runs.py:…:def parse_time(value):`.

- [ ] **Step 5: Commit**

```bash
git add core/backend/common/am_runs.py core/backend/runs/start-run.py tests/core/backend/common/test_am_runs.py
git commit -m "refactor(runs): move parse_time into common/am_runs.py"
```

---

### Task 2: `runs-history.py` — argv, the `am runs` call, filters and page

This task creates the helper with its final module docstring (the whole contract, including the status fan-out of Task 3 and the HelperError of Task 4). Paged entries are the `am runs` rows verbatim until Task 3; this task's tests assert only ids, `more`, exit codes, errors and the am argv, so they stay valid after Task 3.

**Files:**
- Create: `core/backend/runs/runs-history.py`
- Create: `tests/core/backend/runs/test_runs_history.py`

**Interfaces:**
- Consumes: `common.am_runs.parse_time` (Task 1); `call_am(am, args, timeout)`, `run_list(data)`, `bad_output(message)`, `AmFailure` (`.payload`), `TERMINAL`, `AM_TIMEOUT` from `common.am_runs`; `emit(payload, code=0)` from `common.json_line`.
- Produces (used by Tasks 3 and 4):
  - `parse_args(argv) -> dict | None` with keys `root: str`, `before: datetime`, `since: datetime | None`, `limit: int` (1–25), `statuses: frozenset[str]`.
  - `history(am, args) -> dict` — the success payload `{"ok": True, "runs": [...], "more": bool}`; raises `AmFailure`.
  - `main(argv) -> int`, `failure(kind, message, code=1) -> int`, module constants `USAGE`, `DEFAULT_LIMIT = 10`, `MAX_LIMIT = 25`, and module-global names `call_am`, `AM_TIMEOUT` (Task 4 monkeypatches them on the loaded module).
  - Test harness in `test_runs_history.py`: `world` fixture, `env_for`, `run`, `row`, `stamp`, `rows`, `status_data`, `set_runs`, `set_status`, `seed`, `set_raw`, `calls`, `ids`, `args_for`, `write_exec`, `LIST`, `STATUS`, `BEFORE`, `USAGE`, `UNKNOWN_RUN`, `REPO_DIR_ERROR`.

- [ ] **Step 1: Write the failing tests**

Create `tests/core/backend/runs/test_runs_history.py`:

```python
"""runs-history.py: one page of a project's older runs, one JSON line on every path.

Hermetic: a fake `am` lives on a temp PATH and serves, from FAKE_AM_DIR, rows and
status replies built from the committed captures in tests/fixtures/am/ (every
edited payload is labelled `synthetic:`), appending each call's argv to
calls.log; HOME and XDG_DATA_HOME are temp. The real `am` and real data are
never touched.
"""
import datetime
import json
import os
import stat
import subprocess
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "..")
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "runs-history.py")

# The fake am logs its argv, then prints FAKE_AM_DIR/<name>.out verbatim and exits
# with FAKE_AM_DIR/<name>.code (default 0), where <name> is "runs" or
# "status-<run id>". A status fixture that does not exist behaves like real am for
# an unknown run: an UnknownRunError envelope and exit 3.
FAKE_AM = '''#!/usr/bin/env python3
import json, os, sys
d = os.environ["FAKE_AM_DIR"]
args = sys.argv[1:]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(args) + "\\n")
name = "runs" if args[:1] == ["runs"] else "status-" + (args[1] if len(args) > 1 else "")
out = os.path.join(d, name + ".out")
if not os.path.exists(out):
    sys.stdout.write(json.dumps({"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}) + "\\n")
    sys.exit(3)
with open(out) as f:
    sys.stdout.write(f.read())
code = os.path.join(d, name + ".code")
sys.exit(int(open(code).read()) if os.path.exists(code) else 0)
'''

FIXTURES = os.path.join(ROOT, "tests", "fixtures", "am")
# synthetic: am error envelopes; no capture holds one.
UNKNOWN_RUN = {"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}
REPO_DIR_ERROR = {"error": {"message": "not a git repository", "type": "RepoDirError"}, "ok": False}
USAGE = "usage: runs-history.py ROOT --before ISO [--limit K] [--status S,...] [--since ISO]"
BEFORE = "2026-10-09T00:00:00Z"
TERMINAL = ["done", "escalated", "stopped", "cancelled", "canceled"]
NOON = datetime.datetime(2026, 10, 8, 12, tzinfo=datetime.timezone.utc)


def LIST(root):
    """The one `am runs` argv: the project filter alone, no --limit or --before."""
    return ["runs", "--repo-dir", root]


def STATUS(run_id):
    """The `am status` argv for one run: never a --repo-dir."""
    return ["status", run_id]


def fixture(name):
    """A fresh json.load of tests/fixtures/am/<name>, so an edit never reaches
    another call."""
    with open(os.path.join(FIXTURES, name)) as f:
        return json.load(f)


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am, its fixture dir, a temp HOME/XDG_DATA_HOME, and a
    project root whose name would break if it ever went through a shell."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "am", FAKE_AM)
    amdir = tmp_path / "am"
    amdir.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    proj = tmp_path / "my proj; echo x"
    proj.mkdir()
    return {"tmp": tmp_path, "bin": bindir, "am": amdir, "home": home,
            "data": tmp_path / "data", "proj": proj}


def env_for(world, drop=(), **extra):
    e = {
        "PATH": str(world["bin"]) + os.pathsep + "/usr/bin" + os.pathsep + "/bin",
        "HOME": str(world["home"]),
        "XDG_DATA_HOME": str(world["data"]),
        "FAKE_AM_DIR": str(world["am"]),
    }
    e.update(extra)
    for key in drop:
        e.pop(key, None)
    return e


def run(world, args, drop=(), **extra):
    """Run the helper with `args`; assert stdout is exactly one JSON line; return
    (exit, payload)."""
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True,
                       env=env_for(world, drop, **extra), timeout=60)
    lines = p.stdout.splitlines()
    assert len(lines) == 1, (p.stdout, p.stderr)
    return p.returncode, json.loads(lines[0])


def row(run_id, status, started_at):
    """synthetic: a test-local id, status and started_at set on a copy of the
    captured done row of `am runs`."""
    r = fixture("runs.json")["data"]["runs"][1]
    r["id"] = run_id
    r["status"] = status
    r["started_at"] = started_at
    return r


def stamp(i):
    """synthetic: the started_at of the i-th newest row, i minutes before noon UTC
    on 2026-10-08."""
    return (NOON - datetime.timedelta(minutes=i)).isoformat()


def rows(n, status="done"):
    """synthetic: n rows d0..d<n-1> of `status`, newest first."""
    return [row("d%d" % i, status, stamp(i)) for i in range(n)]


def status_data(run_id):
    """synthetic: the captured done `am status` data with run.id set to `run_id`."""
    data = fixture("status-done.json")["data"]
    data["run"]["id"] = run_id
    return data


def set_runs(world, runs):
    """`am runs` serves the captured envelope without `_note`, its runs replaced by
    `runs` (synthetic)."""
    envelope = {k: v for k, v in fixture("runs.json").items() if not k.startswith("_")}
    envelope["data"]["runs"] = runs
    (world["am"] / "runs.out").write_text(json.dumps(envelope) + "\n")


def set_status(world, run_id, data):
    (world["am"] / ("status-" + run_id + ".out")).write_text(
        json.dumps({"data": data, "ok": True}) + "\n")


def seed(world, runs):
    """`am runs` lists `runs`; `am status` answers for every one of them."""
    set_runs(world, runs)
    for r in runs:
        set_status(world, r["id"], status_data(r["id"]))


def set_raw(world, name, text, code=0):
    (world["am"] / (name + ".out")).write_text(text)
    (world["am"] / (name + ".code")).write_text(str(code))


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def ids(out):
    return [r["id"] for r in out["runs"]]


def args_for(world, *extra):
    """The project root, `--before BEFORE`, then `extra`."""
    return [str(world["proj"]), "--before", BEFORE, *extra]


# --- usage, am missing ---------------------------------------------------------

B = BEFORE


@pytest.mark.parametrize("args", [
    [],
    ["/root"],
    ["--before", B],
    ["/root", "--before"],
    ["/root", "--before", ""],
    ["/root", "--before", "-1"],
    ["/root", "--before", "notatime"],
    ["/root", "--before", B, "--since", "notatime"],
    ["/root", "--before", B, "--limit", "0"],
    ["/root", "--before", B, "--limit", "00"],
    ["/root", "--before", B, "--limit", "-1"],
    ["/root", "--before", B, "--limit", "2.5"],
    ["/root", "--before", B, "--limit", "x"],
    ["/root", "--before", B, "--limit", "２"],
    ["/root", "--before", B, "--limit", "٣"],
    ["/root", "--before", B, "--status", ""],
    ["/root", "--before", B, "--status", "a,,b"],
    ["/root", "--before", B, "--status", "done,"],
    ["/root", "--before", B, "--status", ",done"],
    ["/root", "--before=" + B],
    ["/root", "--before", B, "--before", B],
    ["/a", "/b", "--before", B],
    ["", "--before", B],
    ["/root", "--before", B, "--bogus", "x"],
    ["/root", "--before", B, "-h"],
], ids=[
    "none", "root-only", "no-root", "before-no-value", "before-empty", "before-dash",
    "before-bad", "since-bad", "limit-zero", "limit-zeros", "limit-negative",
    "limit-float", "limit-word", "limit-fullwidth", "limit-arabic-indic",
    "status-empty", "status-empty-item", "status-trailing-comma", "status-leading-comma",
    "before-equals", "before-twice", "two-roots", "empty-root", "unknown-flag", "help",
])
def test_usage(world, args):
    code, out = run(world, args)
    assert code == 2
    assert out == {"ok": False, "error": {"type": "Usage", "message": USAGE}}
    assert calls(world) == []


def test_usage_before_am_lookup(world):
    # Bad argv is Usage even when am is not installed: argv is checked first.
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, out = run(world, ["/root"], PATH=str(empty))
    assert code == 2
    assert out == {"ok": False, "error": {"type": "Usage", "message": USAGE}}


def test_am_missing(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, out = run(world, args_for(world), PATH=str(empty))
    assert code == 1
    assert out == {"ok": False, "error": {"type": "AmMissing", "message": "am is not installed."}}


# --- the am runs call ------------------------------------------------------------

def test_runs_am_runs_with_repo_dir_only(world):
    # The project dir is named "my proj; echo x": it must arrive as one argv element.
    seed(world, rows(1))
    code, _ = run(world, args_for(world, "--limit", "5", "--since", "2026-10-01T00:00:00Z"))
    assert code == 0
    assert calls(world)[0] == LIST(str(world["proj"]))


def test_option_order_is_free(world):
    seed(world, rows(5))
    root = str(world["proj"])
    first = run(world, ["--before", BEFORE, root, "--limit", "3"])
    first_calls = calls(world)
    (world["am"] / "calls.log").unlink()
    second = run(world, [root, "--limit", "3", "--before", BEFORE])
    assert first == second
    assert first_calls == calls(world)
    code, out = first
    assert code == 0
    assert ids(out) == ["d0", "d1", "d2"]
    assert out["more"] is True


def test_am_runs_envelope_passthrough(world):
    set_raw(world, "runs", json.dumps(REPO_DIR_ERROR) + "\n", code=2)
    code, out = run(world, args_for(world))
    assert code == 1
    assert out == REPO_DIR_ERROR
    assert calls(world) == [LIST(str(world["proj"]))]


@pytest.mark.parametrize("text", [
    "not json\n",
    "[]\n",
    "{}\n",
    json.dumps({"ok": True, "data": {"as_of_seq": 1}}) + "\n",
    json.dumps({"ok": True, "data": None}) + "\n",
    json.dumps({"ok": True, "data": {"runs": [
        {"status": "done", "started_at": "2026-10-08T11:00:00+00:00"}]}}) + "\n",
], ids=["non-json", "list", "no-ok", "no-runs", "data-null", "row-without-id"])
def test_am_runs_bad_output(world, text):
    # synthetic: am runs output no capture holds.
    set_raw(world, "runs", text)
    code, out = run(world, args_for(world))
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "AmBadOutput"
    assert calls(world) == [LIST(str(world["proj"]))]


DROP = object()


@pytest.mark.parametrize("started_at", [DROP, None, "yesterday", 5],
                         ids=["missing", "null", "words", "number"])
def test_bad_started_at_is_bad_output(world, started_at):
    # The bad row is `started`, so the status filter would drop it: it still fails.
    bad = row("s-started", "started", stamp(1))
    if started_at is DROP:
        del bad["started_at"]
    else:
        bad["started_at"] = started_at
    seed(world, [row("d0", "done", stamp(0)), bad])
    code, out = run(world, args_for(world))
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "AmBadOutput"
    message = out["error"]["message"]
    assert "am runs" in message and "started_at" in message
    assert "yesterday" not in message
    assert calls(world) == [LIST(str(world["proj"]))]


# --- the time window -------------------------------------------------------------

def test_before_is_strict(world):
    seed(world, [row("after", "done", "2026-10-09T00:00:01+00:00"),
                 row("equal", "done", "2026-10-09T00:00:00+00:00"),
                 row("just-before", "done", "2026-10-08T23:59:59.999999+00:00")])
    code, out = run(world, args_for(world))
    assert code == 0
    assert ids(out) == ["just-before"]


def test_before_compares_times_not_strings(world):
    # z is 15:00Z (later) but sorts first as a string; y is 14:00Z (earlier) but
    # sorts after --before as a string.
    seed(world, [row("z", "done", "2026-10-08T14:00:00-01:00"),
                 row("x", "done", "2026-10-08 14:38:23.739155+00:00"),
                 row("y", "done", "2026-10-08T16:00:00+02:00")])
    code, out = run(world, [str(world["proj"]), "--before", "2026-10-08T14:38:24Z"])
    assert code == 0
    assert ids(out) == ["x", "y"]


def test_naive_iso_is_utc(world):
    seed(world, [row("equal", "done", "2026-10-08T12:00:00+00:00"),
                 row("second-before", "done", "2026-10-08T11:59:59+00:00"),
                 row("plus-one", "done", "2026-10-08T12:30:00+01:00")])
    code, out = run(world, [str(world["proj"]), "--before", "2026-10-08T12:00:00"])
    assert code == 0
    assert ids(out) == ["second-before", "plus-one"]


def test_naive_started_at_is_utc(world):
    seed(world, [row("equal", "done", "2026-10-08T12:00:00"),
                 row("second-before", "done", "2026-10-08T11:59:59")])
    code, out = run(world, [str(world["proj"]), "--before", "2026-10-08T12:00:00+00:00"])
    assert code == 0
    assert ids(out) == ["second-before"]


def test_since_is_inclusive(world):
    seed(world, [row("after", "done", "2026-10-08T01:00:00+00:00"),
                 row("equal", "done", "2026-10-08T00:00:00+00:00"),
                 row("just-before", "done", "2026-10-07T23:59:59.999999+00:00")])
    code, out = run(world, args_for(world, "--since", "2026-10-08T00:00:00Z"))
    assert code == 0
    assert ids(out) == ["after", "equal"]


@pytest.mark.parametrize("since", ["2026-10-10T00:00:00Z", BEFORE], ids=["after", "equal"])
def test_since_after_before_is_empty(world, since):
    seed(world, rows(3))
    code, out = run(world, args_for(world, "--since", since))
    assert code == 0
    assert out == {"ok": True, "runs": [], "more": False}


# --- statuses --------------------------------------------------------------------

STATUSES = ["started", "done", "escalated", "stopped", "cancelled", "canceled"]


def test_default_status_is_terminal(world):
    statuses = STATUSES + ["failed"]
    seed(world, [row("s-" + s, s, stamp(i)) for i, s in enumerate(statuses)])
    code, out = run(world, args_for(world))
    assert code == 0
    assert ids(out) == ["s-" + s for s in TERMINAL]


@pytest.mark.parametrize("value, want", [
    ("cancelled", ["cancelled"]),
    ("canceled", ["canceled"]),
    ("cancelled,canceled", ["cancelled", "canceled"]),
    ("done,escalated", ["done", "escalated"]),
    ("started", ["started"]),
    ("done,done", ["done"]),
    ("nope", []),
], ids=["cancelled", "canceled", "both-spellings", "two", "non-terminal", "duplicate", "unknown"])
def test_status_filter(world, value, want):
    seed(world, [row("s-" + s, s, stamp(i)) for i, s in enumerate(STATUSES)])
    code, out = run(world, args_for(world, "--status", value))
    assert code == 0
    assert ids(out) == ["s-" + s for s in want]
    assert out["more"] is False


# --- page ------------------------------------------------------------------------

def test_default_limit_is_10_and_more(world):
    seed(world, rows(12))
    code, out = run(world, args_for(world))
    assert code == 0
    assert ids(out) == ["d%d" % i for i in range(10)]
    assert out["more"] is True
    seed(world, rows(10))
    code, out = run(world, args_for(world))
    assert code == 0
    assert ids(out) == ["d%d" % i for i in range(10)]
    assert out["more"] is False


def test_limit_caps_at_25(world):
    seed(world, rows(30))
    for limit in ["100", "9" * 5000]:
        code, out = run(world, args_for(world, "--limit", limit))
        assert code == 0
        assert ids(out) == ["d%d" % i for i in range(25)]
        assert out["more"] is True
    seed(world, rows(25))
    code, out = run(world, args_for(world, "--limit", "25"))
    assert code == 0
    assert len(out["runs"]) == 25
    assert out["more"] is False


def test_limit_smaller_than_page(world):
    seed(world, rows(3))
    code, out = run(world, args_for(world, "--limit", "2"))
    assert code == 0
    assert ids(out) == ["d0", "d1"]
    assert out["more"] is True


def test_kept_rows_only_count_toward_more(world):
    # Two kept rows and a dropped one with --limit 2: nothing kept is left over.
    seed(world, [row("d0", "done", stamp(0)), row("s0", "started", stamp(1)),
                 row("d1", "done", stamp(2))])
    code, out = run(world, args_for(world, "--limit", "2"))
    assert code == 0
    assert ids(out) == ["d0", "d1"]
    assert out["more"] is False


def test_empty_page(world):
    seed(world, rows(3, status="started"))
    code, out = run(world, args_for(world))
    assert code == 0
    assert out == {"ok": True, "runs": [], "more": False}
    assert calls(world) == [LIST(str(world["proj"]))]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_history.py -q`
Expected: every test FAILs — the script does not exist, so `python3 …/runs-history.py` prints nothing to stdout and `run()`'s `assert len(lines) == 1` fails.

- [ ] **Step 3: Write the implementation**

Create `core/backend/runs/runs-history.py`:

```python
#!/usr/bin/env python3
"""One page of a project's older runs, newest first.

    runs-history.py ROOT --before ISO [--limit K] [--status S,...] [--since ISO]

ROOT is the one positional (non-empty, not starting with -), anywhere among the
options. Each option is the flag then its value as the next argument (no
--flag=value), at most once; a value is non-empty and does not start with -.
--before is required. --before and --since are ISO-8601 times as
datetime.fromisoformat reads them; a time without an offset is UTC. K is a
decimal integer >= 1 (ASCII digits), taken as 25 when larger; default 10.
S,... is a comma-separated list of non-empty status names matched exactly;
default done, escalated, stopped, cancelled, canceled. Any other argv is a
Usage error (exit 2) and am is not run.

Runs `am runs --repo-dir ROOT` (no --limit, no --before), ROOT as given. Every
listed row needs a started_at that parses (else AmBadOutput). Kept, in am's
newest-first order: the rows whose status is in the set, started strictly
before --before and, with --since, not before --since; times compare as
instants. The page is the first K kept rows; `more` is true exactly when more
than K rows were kept among those am listed. Then `am status <id>` once per
paged row, in order, never with --repo-dir.

Prints exactly one JSON line on EVERY path:
{"ok": true, "runs": [{<am runs row>, "status": <am status data>}], "more": bool}
or {"ok": false, "error": {"type", "message"}} with type Usage (exit 2),
AmMissing, AmBadOutput, SchemaMismatch (am status data without a non-negative
integer as_of_seq: the plugin needs the newer am) or HelperError. An `ok:false`
envelope from am (RepoDirError, UnknownRunError, StoreBusyError, ...) is
re-emitted unchanged. Exit 0 ok, 1 failure, 2 usage. A failure stops at the
failing am call; a list is never partial. Only `am` commands are used, always
as argv lists; am's database and on-disk layout are never read; nothing is
written.
"""
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.am_runs import (  # noqa: E402
    AM_TIMEOUT, TERMINAL, AmFailure, bad_output, call_am, parse_time, run_list)
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-history.py ROOT --before ISO [--limit K] [--status S,...] [--since ISO]"
OPTIONS = ("--before", "--limit", "--since", "--status")
DEFAULT_LIMIT = 10
MAX_LIMIT = 25
DIGITS = re.compile(r"[0-9]+")


def failure(kind, message, code=1):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def parse_args(argv):
    """{"root", "before", "since", "limit", "statuses"} for the helper's argv
    (since None when not given; limit capped at MAX_LIMIT; statuses a frozenset,
    TERMINAL when not given); None for anything the grammar does not accept."""
    root, values, i = None, {}, 0
    while i < len(argv):
        arg = argv[i]
        if arg in OPTIONS:
            value = argv[i + 1] if i + 1 < len(argv) else ""
            if arg in values or not value or value.startswith("-"):
                return None
            values[arg] = value
            i += 2
        elif root is None and arg and not arg.startswith("-"):
            root = arg
            i += 1
        else:
            return None
    if root is None or "--before" not in values:
        return None
    before = parse_time(values["--before"])
    since = parse_time(values["--since"]) if "--since" in values else None
    if before is None or ("--since" in values and since is None):
        return None
    digits = values.get("--limit", str(DEFAULT_LIMIT))
    significant = digits.lstrip("0")
    if not DIGITS.fullmatch(digits) or not significant:
        return None
    limit = MAX_LIMIT if len(significant) > 2 else min(int(significant), MAX_LIMIT)
    statuses = values["--status"].split(",") if "--status" in values else TERMINAL
    if not all(statuses):
        return None
    return {"root": root, "before": before, "since": since, "limit": limit,
            "statuses": frozenset(statuses)}


def history(am, args):
    """The success line for `args` (from parse_args): one `am runs --repo-dir ROOT`,
    every row's started_at checked, then the kept rows in am's order, paged."""
    runs = run_list(call_am(am, ["runs", "--repo-dir", args["root"]], AM_TIMEOUT))
    kept = []
    for run in runs:
        when = parse_time(run.get("started_at"))
        if when is None:
            raise bad_output("am runs listed a run without a readable started_at.")
        if (run["status"] in args["statuses"] and when < args["before"]
                and (args["since"] is None or when >= args["since"])):
            kept.append(run)
    page = kept[:args["limit"]]
    return {"ok": True, "runs": page, "more": len(kept) > args["limit"]}


def main(argv):
    args = parse_args(argv)
    if args is None:
        return failure("Usage", USAGE, 2)
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    try:
        result = history(am, args)
    except AmFailure as e:
        return emit(e.payload, 1)
    return emit(result)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

Then make it executable:

Run: `chmod +x core/backend/runs/runs-history.py`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_history.py tests/architecture -q`
Expected: PASS, no failures.

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-history.py tests/core/backend/runs/test_runs_history.py
git commit -m "feat(runs): runs-history.py lists, filters and pages a project's older runs"
```

---

### Task 3: `runs-history.py` — the `am status` fan-out

**Files:**
- Modify: `core/backend/runs/runs-history.py` (the `common.am_runs` import and `history()`)
- Modify: `tests/core/backend/runs/test_runs_history.py` (append tests)

**Interfaces:**
- Consumes: `common.am_runs.run_status(am, run_id, timeout) -> dict` (argv `["status", run_id]`; raises `AmFailure` with AmBadOutput for non-object data, SchemaMismatch for missing/invalid `as_of_seq`, or am's `ok:false` envelope); the Task 2 harness (`seed`, `set_runs`, `set_status`, `status_data`, `rows`, `row`, `stamp`, `run`, `calls`, `args_for`, `LIST`, `STATUS`, `UNKNOWN_RUN`).
- Produces: `history(am, args)` whose `runs` entries are `{**row, "status": <am status data>}`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/core/backend/runs/test_runs_history.py`:

```python
# --- am status fan-out -------------------------------------------------------------

def expected(run, data):
    out = dict(run)
    out["status"] = data
    return out


def test_one_am_status_per_paged_row(world):
    root = str(world["proj"])
    seed(world, [row("s0", "started", stamp(0))]
         + [row("d%d" % i, "done", stamp(i + 1)) for i in range(4)])
    code, out = run(world, args_for(world, "--limit", "2"))
    assert code == 0
    made = calls(world)
    assert made == [LIST(root), STATUS("d0"), STATUS("d1")]
    assert not any("--repo-dir" in argv for argv in made[1:])


def test_output_shape(world):
    runs = rows(3)
    seed(world, runs)
    code, out = run(world, args_for(world))
    assert code == 0
    assert set(out) == {"ok", "runs", "more"}
    assert out == {"ok": True, "runs": [expected(r, status_data(r["id"])) for r in runs],
                   "more": False}


def test_am_status_envelope_passthrough_stops(world):
    # d1 has no status reply: the fake answers UnknownRunError, like real am.
    root = str(world["proj"])
    set_runs(world, rows(3))
    set_status(world, "d0", status_data("d0"))
    set_status(world, "d2", status_data("d2"))
    code, out = run(world, args_for(world))
    assert code == 1
    assert out == UNKNOWN_RUN
    assert calls(world) == [LIST(root), STATUS("d0"), STATUS("d1")]


def test_status_without_as_of_seq_is_schema_mismatch(world):
    root = str(world["proj"])
    set_runs(world, rows(2))
    # synthetic: the captured status data without its as_of_seq.
    data = status_data("d0")
    del data["as_of_seq"]
    set_status(world, "d0", data)
    set_status(world, "d1", status_data("d1"))
    code, out = run(world, args_for(world))
    assert code == 1
    assert out == {"ok": False, "error": {
        "type": "SchemaMismatch",
        "message": "am status d0 sent no non-negative integer as_of_seq; "
                   "the plugin needs the newer am."}}
    assert calls(world) == [LIST(root), STATUS("d0")]


def test_status_data_not_an_object_is_bad_output(world):
    root = str(world["proj"])
    set_runs(world, rows(2))
    # synthetic: an ok envelope whose data is null.
    set_status(world, "d0", None)
    code, out = run(world, args_for(world))
    assert code == 1
    assert out == {"ok": False, "error": {"type": "AmBadOutput",
                                          "message": "am status d0 data is not an object."}}
    assert calls(world) == [LIST(root), STATUS("d0")]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_history.py -q -k "am_status or output_shape or schema_mismatch or not_an_object"`
Expected: 5 FAIL — no `am status` call is made (`calls` holds only the `am runs` argv) and entries still carry the row's string `status`.

- [ ] **Step 3: Add the fan-out**

In `core/backend/runs/runs-history.py`, replace the import:

```python
from common.am_runs import (  # noqa: E402
    AM_TIMEOUT, TERMINAL, AmFailure, bad_output, call_am, parse_time, run_list)
```

with:

```python
from common.am_runs import (  # noqa: E402
    AM_TIMEOUT, TERMINAL, AmFailure, bad_output, call_am, parse_time, run_list, run_status)
```

and replace the end of `history()` and its docstring, so the whole function reads:

```python
def history(am, args):
    """The success line for `args` (from parse_args): one `am runs --repo-dir ROOT`,
    every row's started_at checked, then the kept rows in am's order, paged, each
    paged row's status replaced by its `am status` data."""
    runs = run_list(call_am(am, ["runs", "--repo-dir", args["root"]], AM_TIMEOUT))
    kept = []
    for run in runs:
        when = parse_time(run.get("started_at"))
        if when is None:
            raise bad_output("am runs listed a run without a readable started_at.")
        if (run["status"] in args["statuses"] and when < args["before"]
                and (args["since"] is None or when >= args["since"])):
            kept.append(run)
    page = [dict(run, status=run_status(am, run["id"], AM_TIMEOUT))
            for run in kept[:args["limit"]]]
    return {"ok": True, "runs": page, "more": len(kept) > args["limit"]}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_history.py -q`
Expected: PASS, no failures (Task 2's tests included).

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-history.py tests/core/backend/runs/test_runs_history.py
git commit -m "feat(runs): runs-history.py adds each paged run's am status"
```

---

### Task 4: `runs-history.py` — one HelperError line for anything unexpected

**Files:**
- Modify: `core/backend/runs/runs-history.py` (add `guarded`, change the `__main__` block)
- Modify: `tests/core/backend/runs/test_runs_history.py` (imports; append tests)

**Interfaces:**
- Consumes: Task 2's `main(argv)`, `failure(...)`, module globals `call_am` and `AM_TIMEOUT`; the harness (`world`, `env_for`, `run`, `args_for`, `write_exec`, `seed`, `rows`).
- Produces: `guarded(argv) -> int` — `main(argv)`, except that any exception other than `SystemExit` prints `{"ok": false, "error": {"type": "HelperError", "message": "The runs history failed: <str(e) or class name>"}}` and returns 1.

- [ ] **Step 1: Write the failing tests**

In `tests/core/backend/runs/test_runs_history.py`, change the import block to:

```python
import datetime
import importlib.util
import json
import os
import stat
import subprocess
import sys
import time

import pytest
```

Then append:

```python
# --- catch-all -------------------------------------------------------------------

def load_helper():
    """The script as a module (its name has a hyphen, so no plain import)."""
    spec = importlib.util.spec_from_file_location("runs_history", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def use_world(world, monkeypatch):
    for key, value in env_for(world).items():
        monkeypatch.setenv(key, value)


def one_line(capsys):
    lines = capsys.readouterr().out.splitlines()
    assert len(lines) == 1, lines
    return json.loads(lines[0])


def test_unexpected_exception_is_helper_error(world, monkeypatch, capsys):
    helper = load_helper()
    use_world(world, monkeypatch)

    def boom(*args):
        raise RuntimeError("boom")

    monkeypatch.setattr(helper, "call_am", boom)
    code = helper.guarded(args_for(world))
    assert code == 1
    assert one_line(capsys) == {"ok": False, "error": {
        "type": "HelperError", "message": "The runs history failed: boom"}}


def test_timeout_is_helper_error(world, monkeypatch, capsys):
    # An am that hangs is cut off after AM_TIMEOUT (shortened here from 60 s).
    write_exec(world["bin"] / "am", "#!/bin/sh\nexec sleep 10\n")
    helper = load_helper()
    monkeypatch.setattr(helper, "AM_TIMEOUT", 0.5)
    use_world(world, monkeypatch)
    start = time.monotonic()
    code = helper.guarded(args_for(world))
    assert time.monotonic() - start < 5
    assert code == 1
    out = one_line(capsys)
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The runs history failed: ")


def test_am_that_cannot_start_is_helper_error(world):
    # An am that cannot be executed at all: OSError from subprocess, still one line.
    write_exec(world["bin"] / "am", "#!/nonexistent/interpreter\n")
    code, out = run(world, args_for(world))
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The runs history failed: ")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_history.py -q -k "helper_error"`
Expected: 3 FAIL — the two in-process tests with `AttributeError: module 'runs_history' has no attribute 'guarded'`; the subprocess test because a traceback goes to stderr and stdout is empty (`assert len(lines) == 1`).

- [ ] **Step 3: Add `guarded`**

In `core/backend/runs/runs-history.py`, replace:

```python
if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

with:

```python
def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception (a timeout, an am that cannot start) - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The runs history failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_history.py -q`
Expected: PASS, no failures.

- [ ] **Step 5: Run the whole suite**

Run: `timeout 900 bash tests/run.sh`
Expected: pytest reports no failures (including `tests/core/backend/runs/test_runs_snapshot.py`, `test_runs_snapshot_all.py`, `test_start_run.py`, `tests/core/backend/common/test_am_runs.py` and `tests/architecture/`), every QML `Totals` line shows `0 failed`, and the script exits 0.

Run: `git diff main --stat -- tests/core/backend/runs/test_runs_snapshot.py tests/core/backend/runs/test_runs_snapshot_all.py tests/core/backend/runs/test_start_run.py tests/architecture core/backend/runs/runs-snapshot.py`
Expected: no output (none of those files changed).

- [ ] **Step 6: Commit**

```bash
git add core/backend/runs/runs-history.py tests/core/backend/runs/test_runs_history.py
git commit -m "feat(runs): runs-history.py reports any unexpected failure as one HelperError line"
```
<!-- task-pipeline: validated -->
