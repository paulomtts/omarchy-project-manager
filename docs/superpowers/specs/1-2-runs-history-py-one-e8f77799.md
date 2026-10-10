# 1.2 `runs-history.py`: one page of a project's older runs — design

Card: `e8f77799-0da0-48fd-8d5c-ba80748b48ef` (subtask of story `8aaf0cb6-3038-487c-b262-bfe02df3e39d`,
blocked by 1.1 `e1990cac`, `board-titles.py`, which is done).
Parent design: `docs/superpowers/specs/2026-10-05-run-history-titles-design.md` (cited below as
**parent**), section *History › Data* (lines 119–135), *Errors* (lines 194–204) and *Testing*
(lines 211–214).

## Purpose

`RunHistoryStore` (a later card) needs the older finished runs of a project, a page at a time,
filtered by final state and age. This card delivers only the read-only helper that produces one
such page for ONE project root, and its tests.

## The card overrides the parent

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

## Inherited constraints

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

## Observable behavior

### Output contract

Every run, on every path, writes **exactly one line** to stdout: one JSON object
(`common.json_line.emit`). Exit `0` success, `1` failure, `2` usage. The helper's own errors are
`{"ok": false, "error": {"type": <type>, "message": <non-empty sentence>}}`.

### Argv grammar

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

### Decision order

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

### Side effects

The only processes started are `am runs` and the `am status` calls above, argv lists, stdin
`/dev/null` (from `call_am`). No file is created, changed or removed; am's store is not read.

## Shared code

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

## Tests

### `tests/core/backend/runs/test_runs_history.py` (new)

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

### `tests/core/backend/common/test_am_runs.py` (extended)

**Tier: in-process unit**, because `parse_time` is a pure function now in the shared module.

| # | test | proves |
|---|---|---|
| P1 | `test_parse_time` (parametrized) | `Z`, `+00:00`, `+02:00`, space separator with microseconds, date only → the right aware UTC instant; no offset → UTC; `None`, `5`, `""`, `"yesterday"` → `None` |

### Existing tiers that must stay green, unchanged

`tests/core/backend/runs/test_runs_snapshot.py`, `test_runs_snapshot_all.py`,
`tests/core/backend/runs/test_start_run.py` (proves the move kept `start-run.py`'s behavior),
`tests/architecture/` (layers; no duplicated helpers; icon glyph rules), and the full
`bash tests/run.sh`.

## Out of scope

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

## Notes for the planner

- Implementation order that keeps every commit green: (1) move `parse_time` with P1 and the
  `start-run.py` import; (2) `runs-history.py` usage + `AmMissing` + list call; (3) filters and
  page; (4) status fan-out and error passthrough; (5) `HelperError`.
- Module docstring of `runs-history.py` states the full contract in the style of
  `runs-snapshot.py:1-34`: argv grammar, the am argv, filters, `more`'s definition, output shapes,
  error types, exit codes, "a list is never partial", and that `am status` gets no `--repo-dir`.
