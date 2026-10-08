# 4.0.3 runs.js: `normalizeRun` tolerates `project` and the new keys — design

Card: `dc017a5e` (subtask of story `0cf1ca04`, 4.0 Contract; blocked by 4.0.2 `b134b718`, whose
regenerated fixtures are on this branch as `eb5b4db`). Parent design:
`docs/superpowers/specs/2026-10-06-am-snapshots-cursors-design.md` in the main checkout (untracked
there; cited below as **M4** with line numbers). Sibling spec in this tree:
`docs/superpowers/specs/4-0-2-fixtures-b134b718.md` (cited as **4.0.2**).

## Purpose

`am` 0.2.0 adds keys to its snapshots: every `am runs` row carries `project: {id, repo_dir}`, and
both the `am runs` and `am status` envelopes carry `as_of_seq` and `store_id` (fixtures
`tests/fixtures/am/runs.json`, `status-*.json`). `Runs.normalizeRun` (`core/domain/runs.js:39-147`)
already ignores every key it does not read. This card makes it keep the run's `project` on the run
model, and pins by test that `as_of_seq`, `store_id` and any other new or unknown key stay off the
model and that `normalizeRun` takes no event input (M4 §"`RunStore` and `runs.js`", lines 111-113;
M4 §"Testing", line 216; M4 §"Order and sizing", line 256).

## Inherited constraints

- `runs.js` never folds events into state; a watch line is a nudge handled by the store
  (M4 §"Goal", lines 45-47). Nothing is removed from `runs.js`: it has no fold (M4 lines 111-113,
  174-175).
- `normalizeRun` accepts `project`; `as_of_seq` is read by the store, not kept on the run model;
  unknown keys keep being ignored (M4 lines 111-112).
- `Runs.newAlerts` stays as the snapshot diff (M4 line 113; `core/domain/runs.js:842`). Untouched.
- Unknown event kinds and keys are ignored (M4 §"Design" rules, lines 79-81).
- No new run state computed in the plugin; `am` owns state (M4 §"Non-goals", line 60).
- Test inputs of am output come from `tests/fixtures/am/`, never hand-written; a synthetic edge
  case is labelled `synthetic:` (card; 4.0.2 §"Inherited constraints").
- Docstrings and comments state the contract only, no narrative (card).
- `docs/architecture.md` layering: a domain `.js` stays pure (`.pragma library`, no I/O);
  `tests/architecture` must pass (card).
- Verification: `bash tests/run.sh` green (card).

## Observable behavior

`Runs.normalizeRun(raw)` with `raw = { row, status }` as today.

1. **New output key `project`.** The output gains exactly one key, `project`; its key set becomes
   `base_branch, branch_prefix, id, lease, milestone_id, project, repo_dir, requests, rows,
   started_at, status, tree, workflow` (13 keys). No other output key, and no existing value,
   changes.
2. **Source.** `project` comes from the `am runs` row only (`raw.row.project`). The `am status`
   run has no `project` key in am 0.2.0 (fixtures `status-*.json` `data.run`), and a `project` on
   `raw.status.run` or on `raw.status` is ignored.
3. **Present.** When `raw.row.project` is a plain object (not null, not an array), `project` is a
   new object with exactly the keys `id` and `repo_dir`:
   - `id`: the given value when it is a finite number, else `null` (missing, string, NaN,
     Infinity, object all give `null`).
   - `repo_dir`: the given value as text, the same rule as the other scalars (`undefined`/`null`
     give `""`, anything else is `String(v)`).
   - Any other key inside `raw.row.project` is dropped.
   - The object is a copy: changing the output's `project` never changes the input and vice versa.
4. **Absent.** When `raw.row.project` is missing, `null`, or not a plain object (string, number,
   array, boolean), `project` is `null` — the same convention as a missing `lease`. This is also
   the value for every garbage input that `checkDefaults` covers today (`undefined`, `null`, a
   string, a number, `{}`, `[]`, non-object row/status).
5. **`project.repo_dir` is independent of the run's `repo_dir`.** The top-level `repo_dir` keeps its
   existing rule (row's, else the am status run's); `project.repo_dir` is never used as a fallback
   for it, and it is never used to fill `project.repo_dir`.
6. **`as_of_seq` and `store_id` are not on the model.** Neither the envelope's `as_of_seq`/
   `store_id` (passed as keys of `raw.status`, which is `am status` `data`) nor such keys on the
   row appear anywhere in the output's top level.
7. **Unknown keys are ignored.** Any key on `raw`, `raw.row`, `raw.status` or `raw.status.run`
   that `normalizeRun` does not read (e.g. the row's `story_id`, `card_id`, `progress`; the status
   `warnings`, `integrity`) leaves the output's key set and every top-level value unchanged.
   (Story and subtask objects inside `tree` keep being deep copies of am's objects, as today.)
8. **No event input.** `normalizeRun` reads only `raw.row` and `raw.status`. Extra keys holding
   events or cursors — `raw.events` (the `events.json` `data.events` array), `raw.gseq`,
   `raw.seq`, `raw.head`, `raw.cursor_reset`, and the same keys on `raw.status` — change nothing:
   the output is JSON-equal to the output without them.
9. **Never throws**, as today: a getter-free malformed `project` (e.g. `{ id: {}, repo_dir: [] }`)
   gives `{ id: null, repo_dir: "" }`-style defaults per rule 3, never an exception.

## Doc comment (contract)

The comment above `normalizeRun` (`core/domain/runs.js:7-37`) is updated to state, contract only:

- the row's input shape gains `project: { id, repo_dir }`, and `status` gains `as_of_seq` and
  `store_id`;
- `project` is the row's `{ id, repo_dir }` (id a finite number else null, repo_dir text), null
  when the row has no project object;
- `as_of_seq` and `store_id` are not kept (the store reads them); keys it does not read are
  ignored; it takes no events.

## Tests

All in `tests/core/domain/tst_runs.qml` (TestCase `DomainRuns`), using the existing `amRun(name)`
helper (`tst_runs.qml:13-24`) over `tests/fixtures/am/`. Tier: **QML unit (qmltestrunner)** for
every test — `normalizeRun` is a pure `.pragma library` function with no I/O, and this file is
where its contract is already tested; no store, UI or Python layer is involved.

Updated (forced by rule 1):

- `checkDefaults` (`tst_runs.qml:33-49`): key list gains `project`; add `compare(r.project, null,
  label)`. This covers rule 4 for every garbage input in `test_normalize_garbage`.
- `test_normalize_scalars_from_fixture` (`tst_runs.qml:229-248`): key list gains `project`.

New:

| Test | Proves | Input |
|---|---|---|
| `test_normalize_project_from_fixture` | rules 2, 3: each fixture run's `project` is `{id: 1, repo_dir: "/home/user/Code/omarchy-project-manager"}`, exactly keys `id,repo_dir` | `status-started.json`, `status-done.json` (rows from `runs.json`), `status-escalated.json`, `status-done-integrate.json` (rows from `_am_runs_row`) |
| `test_normalize_project_absent` | rule 4: row without `project`, with `project: null`, a string, a number, an array → `null` | fixture row with `project` deleted / replaced (`synthetic:`) |
| `test_normalize_project_coercion` | rule 3: non-number/NaN/Infinity `id` → `null`; missing/null `repo_dir` → `""`; numeric `repo_dir` → text; extra keys inside `project` dropped | fixture row's `project` edited (`synthetic:`) |
| `test_normalize_project_ignores_status` | rule 2: a `project` on `raw.status.run` or `raw.status` with the row's project deleted gives `null`; with the row's project present, the row's wins | fixture edited (`synthetic:`) |
| `test_normalize_project_independent_of_repo_dir` | rule 5: row `repo_dir` and `project.repo_dir` edited to differ — each output keeps its own; row/run `repo_dir` blanked → top `repo_dir` `""` while `project.repo_dir` is unchanged | fixture edited (`synthetic:`) |
| `test_normalize_project_is_a_copy` | rule 3 copy: mutating output `project` leaves input JSON unchanged, and mutating input after the call leaves output unchanged; `r.project !== raw.row.project` | `status-started.json` |
| `test_normalize_as_of_seq_not_kept` | rule 6: the fixture's `raw.status.as_of_seq`/`store_id` are present in the input (asserted, so the test cannot pass vacuously) and absent from `Object.keys(output)`; adding `as_of_seq`/`store_id` to the row (`synthetic:`) also leaves them absent | `status-started.json`, `runs.json` envelope values |
| `test_normalize_unknown_keys_ignored` | rule 7: output with `synthetic:` extra keys (`raw.extra`, `raw.row.future_key`, `raw.status.future_key`, `raw.status.run.future_key`) is JSON-equal to the output without them; the fixture row's own `story_id`, `card_id`, `progress` are not top-level output keys | `status-started.json` |
| `test_normalize_takes_no_events` | rule 8: adding `raw.events` = `events.json` `data.events`, `raw.gseq`/`seq`/`head`/`cursor_reset` and the same on `raw.status` (`synthetic:` placement of fixture values) gives output JSON-equal to without them | `status-started.json`, `events.json` |
| `test_normalize_project_garbage_never_throws` | rule 9: `project: { id: {}, repo_dir: [] }`, `project: Object.create(null)` → no exception, defaults per rule 3 | `synthetic:` |

Existing tests must stay green unchanged except the two key lists above, including
`test_normalize_copies_never_am_objects`, `test_normalize_own_proto_key_never_sets_prototype`,
`tst_run_store.qml`, `tst_run_detail_screen.qml`, `tests/architecture`, `tests/contract`.

## Error paths

`normalizeRun` has none that surface: per its existing contract it never throws and every
malformed input becomes its default. The new defaults are `project: null` (rule 4) and, inside a
present project, `id: null` / `repo_dir: ""` (rule 3).

## Out of scope

- `core/stores/RunStore.qml`: reading `as_of_seq`, `appliedSeq`, grouping or filtering by
  `project.repo_dir`, nudges, `cursorReset` — 4.1.3 / 4.1.4 (M4 lines 101-110, 269).
- `runs-snapshot.py` (`--all-projects`, forwarding `as_of_seq`) — 4.1.2; `runs-watch.py` — 4.1.1.
- Keeping `story_id` or any other new row key on the model; a `project` from `am status` (am
  0.2.0 has none).
- `Runs.newAlerts` and every other `runs.js` function: unchanged.
- Fixture edits (done by 4.0.2) and contract tests (4.0.1).
- The spec retarget story 4.2 and the 4.3 behaviour cards (Global Runs, timeline, alert cursor,
  start-run discovery) (card).
- UI display of the project.

## Hand-off to the planner

One task is enough: a single file of code (`core/domain/runs.js`: doc comment + the `project`
output built with the existing `isObject`/`text` helpers inside `normalizeRun`) and one test file
(`tests/core/domain/tst_runs.qml`). Write the new and updated tests first, run
`bash tests/run.sh tst_runs` to see them fail on the missing `project` key, implement, then run
the full `bash tests/run.sh`. Plan in the writing-plans format of the brief.
