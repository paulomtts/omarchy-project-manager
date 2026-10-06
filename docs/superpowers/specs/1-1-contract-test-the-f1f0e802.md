# 1.1 Contract test: the committed am fixtures and the installed am agree — design

Card `f1f0e802`, a subtask of story `6596351c` ("Real am fixtures and contract
tests"). Parent spec: `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
(below: **parent**). Work breakdown item 1 (parent L321-323): this subtask is
"the contract test over the committed fixtures" only.

## Goal

A pytest module, `tests/contract/test_am_fixtures.py`, pins the shapes of the
nine committed real-am captures in `tests/fixtures/am/` (parent "Fixtures",
L231-284), and, when the installed `am` has a run for this repo, checks that
`am` still prints those shapes. A one-line change to
`tests/contract/test_am_shapes.py` lets the live hello carry schema 1 or 2
(parent "Both spellings, both schemas", L286-289). The suite is green on the
current code; nothing outside `tests/contract/` changes.

## Inherited constraints

| constraint | source |
|---|---|
| Key sets per level, listed in "What real am prints" | parent L18-65 |
| No top-level `subtasks` in `am status` data | parent L20-21, L279 |
| Status vocabularies: run/story/subtask/phase `pending, started, done, failed, escalated, stopped, cancelled`; attempt `started, ok, schema_invalid, gate_failed, harness_error` | parent L37-39 |
| `canceled` accepted as the second spelling of `cancelled` | parent L288-289 |
| The nine fixture files and their sources; `_note` / `_am_runs_row` on the e2e captures | parent L239-249 |
| Readers ignore keys starting with `_` | parent L251 |
| Fixtures are never edited (in-test edits only on a fresh copy, labelled, shape unchanged) | parent L265-267; card |
| Python reads fixtures with `json.load` | parent L269 |
| Contract test scope; live check in the main checkout (parent of `git rev-parse --git-common-dir`), read-only, `--repo-dir` the only option passed, never writes | parent L276-284 |
| Hello schema 1 or 2 accepted | parent L296-297 |
| `bash tests/run.sh` green, `tests/architecture` green (no duplicated components; icon glyph rules) | card; `docs/architecture.md` |
| Docstrings and comments state the contract only, no narrative | card |

## Observable behavior

### A. Fixture contract (always runs; no `am` needed)

Every test reads files under `tests/fixtures/am/` with `json.load` and never
writes to that directory. "Key set" below means `{k for k in obj if not
k.startswith("_")}` and must be **equal** (not a subset) to the listed set.

1. **Presence.** Each of `runs.json`, `status-started.json`, `status-done.json`,
   `status-escalated.json`, `status-escalated-integrate.json`,
   `status-done-integrate.json`, `watch-events.json`, `watch-hello.json`,
   `logs-attempt.json` exists and parses as JSON. A missing or malformed file
   fails a test that names the file.
2. **Envelopes.** Every fixture except `watch-hello.json` has key set
   `{ok, data}` with `ok is True`.
3. **`am runs` rows** (`runs.json` `data.runs[]`, at least one row, and the
   `_am_runs_row` of each e2e capture): key set
   `{id, workflow, repo_dir, base_branch, branch_prefix, status, started_at,
   milestone_id, card_id, lease, progress}` (parent L50-53).
   - `lease` is null or has key set `{pid, host, heartbeat_at, accepting, live}`;
     at least one row in `runs.json` has a non-null lease (parent L241), so the
     lease key set is actually exercised.
   - `progress` key set `{stories, subtasks, current}`; `stories` and
     `subtasks` each `{done, total}`; `current` is null or `{card, phase,
     attempt}`; at least one `runs.json` row has a non-null `current`.
   - `status` is in the run vocabulary.
4. **`am status` data** (each of the five `status-*.json`):
   - `data` key set `{run, stories, rows, control, integrity}`; `"subtasks" not
     in data` is asserted explicitly as its own check (parent L21).
   - `run` key set `{id, workflow, repo_dir, base_branch, branch_prefix,
     status, started_at}` (no `milestone_id`, parent L23-24).
   - each `stories[]` item `{card_id, title, level, status, tip_branch,
     subtasks}`; each subtask `{card_id, branch, base_branch, status,
     worktree_path, phases}`; each phase `{name, kind, status, started_at,
     ended_at, detail, attempts}`; each attempt `{n, status, dispatch,
     exit_code, duration, prompt_path, result_path, stdout_path}` (parent
     L25-32). Every level is walked across every story, subtask and phase, not
     only the first item. Across the five fixtures together, at least one
     attempt is reached (so the attempt key set is exercised).
   - each `rows[]` item `{story, subtask, phase, attempt, state}` (parent L33).
   - `control` key set `{lease, requests, claims}`; `control.lease` is null or
     `{pid, host, heartbeat_at, accepting, live, acquired_at}` (parent L45-46);
     `status-started.json` has a non-null `control.lease`. `requests` and
     `claims` are lists. Request items are not key-pinned: no capture contains
     one (all five have `requests: []`).
   - `integrity` is present (part of the `data` key set) but its inner keys are
     not pinned: the parent spec does not list them.
5. **Vocabularies.** Over all five status fixtures: `run.status`, every
   story, subtask and phase `status` is in `{pending, started, done, failed,
   escalated, stopped, cancelled, canceled}`; every attempt `status` is in
   `{started, ok, schema_invalid, gate_failed, harness_error}`. `rows[].state`
   is not checked against one vocabulary (it mixes both, parent L35-36). Every
   `runs.json` row and `_am_runs_row` `status` is in the run vocabulary.
6. **`am logs` data** (`logs-attempt.json`): `data` key set `{run_id, story_id,
   card, phase, attempt, status, exit_code, artifacts}`; `artifacts` key set
   `{prompt, result, stdout, stderr}`; each artifact `{path, present, text}`;
   no `data.stdout` (implied by the exact key set; parent L55-58).
7. **Watch events** (`watch-events.json`): `data` key set `{events}`, at least
   one event; every event key set `{seq, ts, run_id, event, story, card,
   phase, attempt, payload}` (parent L64-65).
8. **Hello** (`watch-hello.json`): top-level key set (ignoring `_`)
   `{schema_1, schema_2}`; each hello key set `{event, schema, am, runs_dir}`;
   `schema_1["schema"] == 1`, `schema_2["schema"] == 2`, `event == "watch"` on
   both (parent L62, L248).
9. **`_note` placement.** `_note` is a key of exactly these files:
   `status-escalated.json`, `status-escalated-integrate.json`,
   `status-done-integrate.json`, `watch-events.json`, `watch-hello.json`; it is
   absent from `runs.json`, `status-started.json`, `status-done.json`,
   `logs-attempt.json`. `_am_runs_row` is a key of exactly the three e2e
   captures (parent L244-246).

### B. Live check (read-only; may skip)

1. **Main checkout.** `MAIN = Path(git rev-parse --path-format=absolute
   --git-common-dir).parent`, run from the repository the test file lives in.
2. **Skip, never fail, when:** `am` is not on `PATH`; `git` fails or is absent;
   `am runs --repo-dir MAIN` exits non-zero or prints no `data.runs` rows. Each
   skip reason names its cause.
3. **Commands.** Exactly `am runs --repo-dir MAIN` and `am status <id>
   --repo-dir MAIN`, where `<id>` is the row with the greatest `started_at`
   (newest). Each call has a timeout (30 s, as `test_am_shapes.py`'s
   `AM_TIMEOUT`); a timeout fails the test. No other option is passed, nothing
   is written, `HOME`/XDG are not overridden (it reads the user's real runs).
   A non-zero exit of `am status` for a listed run fails the test.
4. **Same key sets.** Every live `am runs` row, its non-null `lease`, its
   `progress` (and non-null `current`), and the live `am status` data at every
   level listed in A.4 (data, run, story, subtask, phase, attempt, row,
   control, non-null control lease) has the same key set as A.3/A.4 pin.
   - **Allowance: `story_id`.** The installed am already prints `story_id` on
     every `am runs` row and on `am status` `data.run` (verified 2026-10-05:
     12 and 8 keys). It belongs to story-level dispatch
     (`2026-10-05-dispatch-story-level-design.md` L64-67), postdates the
     fixtures, and the fixtures may not be edited. The live check accepts, at
     those two levels only, the pinned set or the pinned set plus `story_id`.
     Any other extra or missing key at any level fails, naming the level and
     the difference.
   - The live statuses are checked against the A.5 vocabularies.
5. The live check shares the expected key sets with part A (one definition per
   level in the module), so the fixtures and the installed am are compared
   against the same constants.

### C. `test_am_shapes.py` hello

`tests/contract/test_am_shapes.py:159` changes from `hello["schema"] == 1` to
`hello["schema"] in (1, 2)`. Nothing else in that file changes.

## Tests (the deliverable)

All live in `tests/contract/` (pytest tier "contract": they pin the external
`am` program's output and the captures of it, not plugin code; they run under
`python3 -m pytest tests` via `tests/run.sh`). No QML tier: nothing here is
QML. No unit tier: there is no plugin code under test.

| test | tier / why |
|---|---|
| `test_every_fixture_exists_and_parses` (parametrized over the nine names) | contract: A.1, a missing capture must fail by name |
| `test_envelopes_are_ok_data` | contract: A.2 |
| `test_runs_rows_key_sets` (runs.json rows + each `_am_runs_row`; lease, progress, current) | contract: A.3 |
| `test_status_data_has_no_top_level_subtasks` (parametrized over five) | contract: A.4, the bug the parent spec exists for |
| `test_status_key_sets_at_every_level` (parametrized over five) | contract: A.4 |
| `test_status_vocabularies` (parametrized over five; plus runs rows) | contract: A.5 |
| `test_logs_key_sets` | contract: A.6 |
| `test_watch_event_key_sets` | contract: A.7 |
| `test_hello_key_sets_and_schemas` | contract: A.8 |
| `test_note_is_on_exactly_the_annotated_captures` | contract: A.9 |
| `test_installed_am_prints_the_fixture_key_sets` | contract, live: B; skips per B.2 |
| `test_watch_all_follow_prints_a_hello_line_then_journal_lines` (existing, edited) | contract: C |

TDD order: each test is written and run before the next; on this codebase they
are green at once (they pin am, not plugin code, parent L321). To prove each
assertion bites, the implementer runs it once against a **mutated copy** of the
fixture made inside a throwaway check (e.g. an extra key, a `subtasks` key, a
status `bogus`) and sees it fail — never by editing a committed fixture — and
does not commit that check.

## Failure messages

Every key-set assertion reports the fixture file (or `live am runs` / `live am
status <id>`), the level (e.g. `stories[1].subtasks[0].phases[2]`), and the
missing and extra keys.

## Out of scope

- Editing any file in `tests/fixtures/am/` (never).
- `tests/helpers/amFixtures.js` and `QML_XHR_ALLOW_FILE_READ` in `tests/run.sh`
  (sibling: "the QML fixture loader").
- The helpers' fake am serving the fixtures (sibling).
- Any plugin code: `runs.js` (`normalizeRun`, `rollup`, `runProgress`,
  `escalationReason`, `glyphStateOf`), `runs-*.py`, `run-control.py`,
  `RunStore`, screens — parent work items 2-4.
- Pinning `integrity`'s inner keys, `control.requests[]` item keys, or
  `rows[].state` values.
- Adding `story_id` to any expected set or fixture beyond the live allowance.
- Docs (parent work item 5).

## Plan handoff notes

- One new file, one one-line edit. Key-set constants are module-level
  frozensets in `test_am_fixtures.py`; reuse nothing by copy from other test
  modules (architecture test forbids duplicated helpers). The `EVENT_KEYS`
  constant in `test_am_shapes.py` may be imported or restated; restating a
  data constant is not a duplicated helper, importing between test modules is
  avoided (no package `__init__` in `tests/contract`).
- A single walker helper yields `(where, obj)` pairs per level for a status
  `data`, used by both the fixture tests and the live test.
- Module docstring states the contract (what is pinned, where the live check
  runs, that it is read-only and skips), in the style of
  `test_am_shapes.py`'s docstring.
- Verification: `python3 -m pytest tests/contract -q`, then `bash tests/run.sh`.
