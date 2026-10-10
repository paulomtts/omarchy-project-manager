# 1.1 `board-titles.py`: one project's card titles — design

Card: `e1990cac-d30c-461f-bb30-cb26c1485bb5` (subtask of story `8aaf0cb6-3038-487c-b262-bfe02df3e39d`).
Parent design: `docs/superpowers/specs/2026-10-05-run-history-titles-design.md` (cited below as
**parent**), section *Titles › Lookup* (lines 63–74) and *Testing* (lines 208–210).

## Purpose

`RunTitlesStore` (a later card) needs `{card id: title}` for projects that are not open in the
plugin. This card delivers only the read-only helper that produces that map for ONE project
root, plus its tests.

## Inherited constraints

| # | constraint | source |
|---|---|---|
| C1 | Path and invocation: `core/backend/boards/board-titles.py ROOT` | parent :67–68 |
| C2 | Runs `brd tree` as an argv list, `cwd=ROOT`, stdin `/dev/null`, 30 s timeout — the same command and working-directory rule as `BoardStore` (`["brd", "tree"]`, `workingDirectory` = project root) | parent :68–70, :35–38; `core/stores/BoardStore.qml:220-223` |
| C3 | Prints ONE JSON line `{"ok": true, "titles": {id: title}}` covering every card at any depth; descriptions dropped | parent :70–71 |
| C4 | Failures: brd's own `ok:false` envelope unchanged (e.g. `ProjectNotFoundError`), `BrdMissing`, `BrdBadOutput`, `RootMissing` (ROOT is not a directory), `HelperError`, `Usage` (exit 2); exit 0 otherwise | parent :71–74 |
| C5 | It never writes | parent :74 |
| C6 | No reading of brd's database; only the `brd` command | parent :56–57 |
| C7 | `core/backend/**` imports only the Python stdlib and `core/backend/common` | `docs/architecture.md:12`, enforced by `tests/architecture/test_layers.py` |
| C8 | Tests: fake `brd`; argv and `cwd`, nested cards flattened, descriptions dropped, envelope passthrough, missing brd, missing root, bad output, one line on every path | parent :208–210 |
| C9 | Docstrings and comments state the contract only, no narrative | card description |

## Observable behavior

### Invocation

`board-titles.py ROOT` — exactly one argument, non-empty, not starting with `-`.

### Output contract

Every run of the helper, on every path, writes **exactly one line** to stdout: a JSON object
followed by a newline (`common.json_line.emit`). Nothing else goes to stdout. Exit codes:
`0` success, `1` failure, `2` usage.

Error shape (the helper's own errors):
`{"ok": false, "error": {"type": <type>, "message": <non-empty human sentence>}}`.

### Decision order

1. **Usage** — argv is not exactly one argument, or the argument is empty or starts with `-`:
   `{"ok": false, "error": {"type": "Usage", "message": "usage: board-titles.py ROOT"}}`,
   exit 2. `brd` is not run.
2. **RootMissing** — `ROOT` is not an existing directory (does not exist, or is a file):
   type `RootMissing`, message names the path, exit 1. `brd` is not run.
3. **Run brd** — exactly one subprocess: argv `["brd", "tree"]`, `cwd=ROOT`,
   `stdin=/dev/null`, stdout/stderr captured as text, timeout 30 s (a module constant
   `TIMEOUT_SECONDS = 30`). brd is looked up on `PATH`.
   - brd not found on `PATH` → type `BrdMissing`, message "brd is not installed." (or
     equivalent sentence), exit 1.
   - brd does not finish within `TIMEOUT_SECONDS` → type `HelperError`, message says brd tree
     timed out, exit 1.
4. **brd's envelope passthrough** — stdout parses as a JSON object whose `ok` is exactly
   `false`: that object is re-emitted unchanged (equal as a JSON value; serialized on one line),
   exit 1, **regardless of brd's exit code**. Example: from a directory with no brd project, brd
   prints `{"ok":false,"error":{"type":"ProjectNotFoundError",...}}` and the helper prints the
   same object.
5. **BrdBadOutput** (exit 1, message is a sentence, never the raw output) when any of:
   - stdout is not valid JSON, or is JSON but not an object;
   - the object's `ok` is not exactly `true` (missing, `"true"`, `1`, …) and not `false`;
   - `ok` is `true` but brd's exit code is non-zero;
   - `data` is missing or not a list;
   - any card, at any depth, is not an object; its `id` is not a non-empty string; its `title`
     is not a string; or its `children` is present, not `null`, and not a list.
6. **Success** — `{"ok": true, "titles": {id: title, ...}}`, exit 0:
   - Every card of `data` and of every card's `children`, recursively, at any depth,
     contributes exactly one entry `id → title`. A card with `children` absent, `null`, or `[]`
     is a leaf.
   - `titles` values are the titles verbatim (non-ASCII preserved through JSON).
   - Nothing else of a card appears anywhere in the output: no `description`, `status`,
     `blocked_by`, `blockers`, `created_at`, `updated_at`, `children`.
   - The top-level object has exactly the keys `ok` and `titles`.
   - An empty board (`data: []`) gives `{"ok": true, "titles": {}}`.
   - brd ids are unique; should one repeat, the entry visited last in pre-order
     (parent before its children, siblings in list order) wins.
7. **HelperError** — any other exception escaping `main` (caught by a `guarded(argv)`
   wrapper that re-raises `SystemExit`, as `core/backend/runs/runs-snapshot.py:80-89` does):
   type `HelperError`, message `"The board titles lookup failed: <reason>"`, exit 1. One line
   still printed.

### Side effects

- The only process started is the single `brd tree`. No `brd` write command, no file
  created, modified or removed anywhere (ROOT included). brd's database is never opened (C6).
- The helper does not read its own stdin; brd's stdin is `/dev/null`, so data piped into the
  helper never reaches brd.

## Tests

All new tests live in `tests/core/backend/boards/test_board_titles.py`, modeled on
`tests/core/backend/boards/test_archive_milestones.py`.

Fixture `box`: a temp `bin/` holding an executable fake `brd` (POSIX `sh`) on
`PATH=<bindir>:/usr/bin:/bin` (the fake needs the external `cat` and `sleep`, which a
`<bindir>`-only PATH would not find; `<bindir>` first so the fake shadows any real `brd`; the
helper is run with `sys.executable`), a project directory whose
name contains a space (`my project`), and env vars the fake reads:
- `CALLS`: the fake appends `brd $* (cwd=$(pwd))` per invocation;
- `STDIN_LOG`: the fake `cat`s its stdin into this file;
- `BRD_OUT`: path of a file whose contents the fake prints to stdout;
- `BRD_EXIT`: the fake's exit code (default 0).
- `BRD_SLEEP` (T15 only): seconds the fake sleeps before printing, via `exec sleep` so the
  kill on timeout reaches the sleeper and does not leave it holding the stdout pipe open.

`run(box, *args, stdin_text=None)` runs `[sys.executable, SCRIPT, *args]` and **asserts
`len(stdout.splitlines()) == 1` on every call**, returning `(code, parsed_json)`.

**Tier: subprocess (black-box CLI) tests**, because the contract under test is the helper's
process boundary — argv, cwd, stdin, stdout line count, exit code — which only a real child
process with a fake `brd` observes. Exceptions are marked.

| # | test | proves |
|---|---|---|
| T1 | `test_runs_brd_tree_once_in_root` | calls log is exactly `["brd tree (cwd=<project.resolve()>)"]` (C2; path with a space) |
| T2 | `test_brd_stdin_is_dev_null` | helper run with piped stdin `"LEAK\n"`; `STDIN_LOG` is empty afterwards (C2) |
| T3 | `test_flattens_nested_cards_at_any_depth` | milestone → story → subtask → sub-subtask (4 levels) plus a second root card and a card with `children: null` all appear; output `== {"ok": True, "titles": {...}}` exactly, exit 0 (C3) |
| T4 | `test_drops_descriptions_and_every_other_field` | cards carry description/status/blocked_by/blockers/created_at/updated_at; output equals the exact `{ok, titles}` object and the raw stdout contains no description text (C3) |
| T5 | `test_empty_board_gives_empty_titles` | `data: []` → `{"ok": True, "titles": {}}`, exit 0 |
| T6 | `test_non_ascii_titles_round_trip` | title `"Café — 日本"` arrives verbatim |
| T7 | `test_brd_envelope_is_passed_through_unchanged` | fake prints a `ProjectNotFoundError` envelope with exit 1 → output equals it, exit 1 (C4) |
| T8 | `test_brd_envelope_passthrough_ignores_brd_exit_code` | same envelope with `BRD_EXIT=0` → still passed through, exit 1 |
| T9 | `test_brd_missing` | `PATH` = an empty directory only (no system dirs) → `BrdMissing`, exit 1 (C4) |
| T10 | `test_bad_output` (parametrized) | non-JSON text; empty stdout; JSON list; object without `ok`; `ok: "true"`; `ok: true` with `data` missing; `data` an object; a card that is a string; a card with no `id`; `id: 5`; `id: ""`; `title: null`; `children: {}` nested two levels down → each `BrdBadOutput`, exit 1 (C4) |
| T11 | `test_ok_envelope_with_nonzero_exit_is_bad_output` | valid `ok:true` data, `BRD_EXIT=3` → `BrdBadOutput`, exit 1 |
| T12 | `test_root_missing` (parametrized) | nonexistent path; a regular file → `RootMissing`, exit 1, calls log empty (C4) |
| T13 | `test_usage` (parametrized) | no args; two args; `""`; `"--help"` → `Usage`, exit 2, calls log empty (C4) |
| T14 | `test_never_writes` | after a successful run, the set of files under the temp root (project dir included) is unchanged except the fake's own logs, and the calls log has only `brd tree` (C5) |
| T15 | `test_timeout_is_helper_error` — **tier: in-process unit** (module loaded with `importlib.util.spec_from_file_location`, `TIMEOUT_SECONDS` patched to a small value, fake brd `sleep`s, stdout captured with `capsys`), because a real 30 s wait is unacceptable in the suite | `HelperError`, return code 1, exactly one captured line |
| T16 | `test_unexpected_exception_is_helper_error` — **tier: in-process unit** (same loading; `monkeypatch` the module's subprocess call to raise `RuntimeError("boom")`), because no deterministic external input makes valid-looking code raise | `guarded([...])` returns 1 and prints exactly one line with type `HelperError` and `boom` in the message |

Every subprocess test asserts the one-line rule through `run()`; T15/T16 assert it on
captured output. Together they cover each exit path: success, passthrough, `BrdMissing`,
`BrdBadOutput`, `RootMissing`, `Usage`, `HelperError` (C8).

**Existing tier that must stay green:** `tests/architecture/` (layer allowlists: the helper
imports only stdlib and `common`; no duplicated components; icon glyph rules), and the full
`bash tests/run.sh` (pytest + QML tests).

## Out of scope

- `RunTitlesStore.qml`, its queue, cache, invalidation, `titleStatus` (parent :76–94) — sibling
  cards.
- `Runs.titlesFromCards`, `runTitle`, `cardTitle`, search and alert titles in
  `core/domain/runs.js` (parent :96–108) and every UI surface (parent :110–115).
- Run history (`runs-history.py`, `RunHistoryStore`, chips) (parent :117–192).
- Documenting the helper in `docs/architecture.md` or other docs — a later docs card.
- Any change to `BoardStore.qml`, `brd`, `am`, or `common/` (only `common.json_line.emit` is
  reused; no new shared module).
- Caching, retries, or reading any project other than ROOT.

## Handoff to the planner

**File map**
- Create: `core/backend/boards/board-titles.py` — the helper (shebang `#!/usr/bin/env python3`,
  executable bit (mode 100755, like `runs-snapshot.py`), contract-only module docstring stating the
  invocation, output, error types and exit codes; `sys.path.insert` + `from common.json_line
  import emit  # noqa: E402`; `USAGE`, `TIMEOUT_SECONDS = 30`, `failure(kind, message,
  code=1)`, `parse_args(argv) -> str | None`, a pure `flatten_titles(data) -> dict | None`
  (None ⇒ bad shape), `main(argv) -> int`, `guarded(argv) -> int`, `sys.exit(guarded(sys.argv[1:]))`).
- Create: `tests/core/backend/boards/test_board_titles.py` — T1–T16.

**Suggested tasks** (each ends green on `bash tests/run.sh`):
1. Usage + RootMissing + the `brd tree` call (argv, cwd, stdin, BrdMissing) + success
   flattening + one-line `run()` helper — T1–T6, T9, T12–T14.
2. Envelope passthrough and BrdBadOutput validation — T7, T8, T10, T11.
3. `guarded` catch-all and timeout — T15, T16.

Strict TDD: each test written and seen failing before the code that passes it.
Verification: `bash /home/mtts/.local/state/agent-manager/verify/vfy-opm.sh` (runs
`bash tests/run.sh`). No linter or type checker is configured.
