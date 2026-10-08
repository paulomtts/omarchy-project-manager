# 4.0.3 runs.js: `normalizeRun` tolerates `project` and the new keys Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Runs.normalizeRun` keeps the `am runs` row's `project` as `{ id, repo_dir }` (or `null`) on the run model, and tests pin that `as_of_seq`, `store_id`, unknown keys and event/cursor inputs never reach the model.

**Architecture:** One pure `.pragma library` function changes: `normalizeRun` in `core/domain/runs.js` builds a fresh `project` object from `raw.row.project` with its existing `isObject`/`text` helpers and returns it as a 13th output key; its doc comment states the new contract. Every other key of the input keeps being ignored, as today. All tests are QML unit tests in `tests/core/domain/tst_runs.qml`, built from the am 0.2.0 captures in `tests/fixtures/am/`.

**Tech Stack:** QML/JS (`.pragma library`), QtTest via `qmltestrunner` (`/usr/lib/qt6/bin/qmltestrunner`), driven by `bash tests/run.sh [filter]` (which first runs the whole pytest suite, then every `tst_*.qml` whose path contains the filter).

**Spec:** `docs/superpowers/specs/4-0-3-runs-js-dc017a5e.md` (reproduced in full in the "Spec" section below).

## Global Constraints

- `runs.js` never folds events into state; nothing is removed from `runs.js`.
- `normalizeRun` accepts `project`; `as_of_seq` is read by the store, not kept on the run model; unknown keys keep being ignored.
- `Runs.newAlerts` and every other `runs.js` function stay unchanged.
- No new run state computed in the plugin; `am` owns state.
- Test inputs of am output come from `tests/fixtures/am/`, never hand-written; a synthetic edge case is labelled `synthetic:` in a comment.
- Docstrings and comments state the contract only, no narrative.
- A domain `.js` stays pure (`.pragma library`, no I/O); `tests/architecture` must pass.
- Verification: `bash tests/run.sh` green.
- Output key set of `normalizeRun` becomes exactly `base_branch,branch_prefix,id,lease,milestone_id,project,repo_dir,requests,rows,started_at,status,tree,workflow` (13 keys).

## Review Focus

1. **A project id of `0`, a negative or a fractional number** — falsy but finite; a person expects it kept as given, not turned into `null` by a truthiness check. Pinned in `test_normalize_project_coercion` (Task 1, Step 1).
2. **A bare `am runs` row with no `am status` yet** (RunStore normalizes rows before their status arrives) — the project must already be on the model. Pinned in `test_normalize_project_from_fixture` (runs.json rows alone) (Task 1, Step 1).
3. **A project object carrying an own `__proto__` key** — the output project must have `Object.prototype` as its prototype and only `id`/`repo_dir`, never values smuggled through the prototype. Pinned in `test_normalize_project_own_proto_key` (Task 1, Step 1).
4. **`project.repo_dir` empty while the run's `repo_dir` is set** — the run's `repo_dir` must not be blanked and `project.repo_dir` must not be filled from it. Pinned in `test_normalize_project_independent_of_repo_dir` (Task 1, Step 1).
5. **The am runs envelope's `as_of_seq`/`store_id` leaking onto the model through the row** — a caller that merges envelope keys into the row must still get the same model. Pinned in `test_normalize_as_of_seq_not_kept` (Task 1, Step 1).

---

## Spec

(Copy of `docs/superpowers/specs/4-0-3-runs-js-dc017a5e.md`, headings demoted two levels.)

### 4.0.3 runs.js: `normalizeRun` tolerates `project` and the new keys — design

Card: `dc017a5e` (subtask of story `0cf1ca04`, 4.0 Contract; blocked by 4.0.2 `b134b718`, whose
regenerated fixtures are on this branch as `eb5b4db`). Parent design:
`docs/superpowers/specs/2026-10-06-am-snapshots-cursors-design.md` in the main checkout (untracked
there; cited below as **M4** with line numbers). Sibling spec in this tree:
`docs/superpowers/specs/4-0-2-fixtures-b134b718.md` (cited as **4.0.2**).

#### Purpose

`am` 0.2.0 adds keys to its snapshots: every `am runs` row carries `project: {id, repo_dir}`, and
both the `am runs` and `am status` envelopes carry `as_of_seq` and `store_id` (fixtures
`tests/fixtures/am/runs.json`, `status-*.json`). `Runs.normalizeRun` (`core/domain/runs.js:39-147`)
already ignores every key it does not read. This card makes it keep the run's `project` on the run
model, and pins by test that `as_of_seq`, `store_id` and any other new or unknown key stay off the
model and that `normalizeRun` takes no event input (M4 §"`RunStore` and `runs.js`", lines 111-113;
M4 §"Testing", line 216; M4 §"Order and sizing", line 256).

#### Inherited constraints

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

#### Observable behavior

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

#### Doc comment (contract)

The comment above `normalizeRun` (`core/domain/runs.js:7-37`) is updated to state, contract only:

- the row's input shape gains `project: { id, repo_dir }`, and `status` gains `as_of_seq` and
  `store_id`;
- `project` is the row's `{ id, repo_dir }` (id a finite number else null, repo_dir text), null
  when the row has no project object;
- `as_of_seq` and `store_id` are not kept (the store reads them); keys it does not read are
  ignored; it takes no events.

#### Tests

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

#### Error paths

`normalizeRun` has none that surface: per its existing contract it never throws and every
malformed input becomes its default. The new defaults are `project: null` (rule 4) and, inside a
present project, `id: null` / `repo_dir: ""` (rule 3).

#### Out of scope

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

#### Hand-off to the planner

One task is enough: a single file of code (`core/domain/runs.js`: doc comment + the `project`
output built with the existing `isObject`/`text` helpers inside `normalizeRun`) and one test file
(`tests/core/domain/tst_runs.qml`). Write the new and updated tests first, run
`bash tests/run.sh tst_runs` to see them fail on the missing `project` key, implement, then run
the full `bash tests/run.sh`. Plan in the writing-plans format of the brief.

---

## File Structure

- Modify: `core/domain/runs.js:4-147` — the doc comment above `normalizeRun` (lines 4-37) and the `project` output inside `normalizeRun` (built after the lease block, lines 71-81; returned at lines 134-147).
- Modify: `tests/core/domain/tst_runs.qml` — `checkDefaults` (lines 33-49), `test_normalize_scalars_from_fixture` (line 231), and a new block of tests inserted after `test_normalize_own_proto_key_never_sets_prototype` (ends at line 387, before `test_fixture_current_phase_and_default_attempt` at line 389).

Baseline before you start: `bash tests/run.sh domain/tst_runs` prints `Totals: 169 passed, 0 failed` for `tests/core/domain/tst_runs.qml`.

---

### Task 1: `normalizeRun` keeps the row's `project`; new keys and events stay off the model

**Files:**
- Modify: `core/domain/runs.js:4-36` (doc comment), `core/domain/runs.js:71-81` (after the lease block), `core/domain/runs.js:134-147` (return object)
- Test: `tests/core/domain/tst_runs.qml:33-49`, `tests/core/domain/tst_runs.qml:231`, new tests after line 387

**Interfaces:**
- Consumes: `Runs.normalizeRun(raw)` with `raw = { row, status }`; the test helpers `amRun(name)` (`tst_runs.qml:15-25`, returns `{ row, status }` built fresh from a fixture) and `F.load(name)` (`tests/helpers/amFixtures.js`, a fresh parse of `tests/fixtures/am/<name>`).
- Produces: the run model gains `project: { id: number|null, repo_dir: string } | null`. Later cards (4.1.3/4.1.4 `RunStore`) read `run.project.repo_dir`; `as_of_seq` is never on the model.

- [ ] **Step 1: Update the two key lists and write the failing tests**

In `tests/core/domain/tst_runs.qml`, replace the first line of `checkDefaults` and add a `project` check. The function becomes:

```qml
  function checkDefaults(r, label) {
    compare(Object.keys(r).sort().join(","), "base_branch,branch_prefix,id,lease,milestone_id,project,repo_dir,requests,rows,started_at,status,tree,workflow", label)
    compare(r.started_at, "", label)
    compare(r.id, "", label)
    compare(r.repo_dir, "", label)
    compare(r.milestone_id, "", label)
    compare(r.status, "", label)
    compare(r.base_branch, "", label)
    compare(r.branch_prefix, "", label)
    compare(r.lease, null, label)
    compare(r.project, null, label)
    compare(Array.isArray(r.rows), true, label)
    compare(r.rows.length, 0, label)
    compare(Array.isArray(r.tree.stories), true, label)
    compare(r.tree.stories.length, 0, label)
    compare(Array.isArray(r.tree.subtasks), true, label)
    compare(r.tree.subtasks.length, 0, label)
  }
```

In `test_normalize_scalars_from_fixture`, replace the key-list line

```qml
    compare(Object.keys(r).sort().join(","), "base_branch,branch_prefix,id,lease,milestone_id,repo_dir,requests,rows,started_at,status,tree,workflow")
```

with

```qml
    compare(Object.keys(r).sort().join(","), "base_branch,branch_prefix,id,lease,milestone_id,project,repo_dir,requests,rows,started_at,status,tree,workflow")
```

Then insert this block right after the closing `}` of `test_normalize_own_proto_key_never_sets_prototype` (and before `function test_fixture_current_phase_and_default_attempt()`), keeping one blank line between functions:

```qml
  // ---- 4.0.3: the run's project and am 0.2.0's new keys ------------------------------------

  function hasOwn(o, key) { return Object.prototype.hasOwnProperty.call(o, key) }

  // The project normalizeRun gives for the status-started.json run whose row's
  // project is replaced by `project`.
  function projectOf(project) {
    var raw = amRun("status-started.json")
    raw.row.project = project
    return Runs.normalizeRun(raw).project
  }

  function test_normalize_project_from_fixture() {
    var names = ["status-started.json", "status-done.json", "status-escalated.json", "status-done-integrate.json"]
    for (var i = 0; i < names.length; i++) {
      var raw = amRun(names[i])
      verify(!hasOwn(raw.status.run, "project"), names[i] + ": the am status run has no project")
      var p = Runs.normalizeRun(raw).project
      compare(Object.keys(p).sort().join(","), "id,repo_dir", names[i] + " keys")
      compare(p.id, 1, names[i] + " id")
      compare(p.repo_dir, "/home/user/Code/omarchy-project-manager", names[i] + " repo_dir")
    }

    // the am runs rows alone, before any am status
    var rows = F.load("runs.json").data.runs
    for (var j = 0; j < rows.length; j++) {
      var bare = Runs.normalizeRun({ row: rows[j] }).project
      compare(JSON.stringify(bare), JSON.stringify({ id: 1, repo_dir: "/home/user/Code/omarchy-project-manager" }), "row " + j + " alone")
    }
  }

  function test_normalize_project_absent() {
    var missing = amRun("status-started.json")
    verify(hasOwn(missing.row, "project"), "the capture's row carries a project")
    // synthetic: the row's project deleted
    delete missing.row.project
    compare(Runs.normalizeRun(missing).project, null, "missing")

    // synthetic: the row's project replaced by each non-object
    var cases = [["null", null], ["string", "/home/user/Code/omarchy-project-manager"], ["number", 1],
                 ["array", [1, "/home/user/Code/omarchy-project-manager"]], ["true", true], ["false", false]]
    for (var i = 0; i < cases.length; i++) compare(projectOf(cases[i][1]), null, cases[i][0])
  }

  function test_normalize_project_coercion() {
    // synthetic: the row's project with each id that is not a finite number
    var badIds = [["string", "1"], ["null", null], ["NaN", NaN], ["Infinity", Infinity], ["-Infinity", -Infinity],
                  ["object", {}], ["array", [1]], ["boolean", true]]
    for (var i = 0; i < badIds.length; i++) {
      compare(projectOf({ id: badIds[i][1], repo_dir: "/p" }).id, null, "id " + badIds[i][0])
    }
    compare(projectOf({ repo_dir: "/p" }).id, null, "id missing")

    // synthetic: finite ids, falsy and fractional included, are kept as given
    var goodIds = [0, -3, 1.5, 2]
    for (var j = 0; j < goodIds.length; j++) compare(projectOf({ id: goodIds[j], repo_dir: "/p" }).id, goodIds[j], "id " + goodIds[j])

    // synthetic: repo_dir as text
    compare(projectOf({ id: 1 }).repo_dir, "", "repo_dir missing")
    compare(projectOf({ id: 1, repo_dir: null }).repo_dir, "", "repo_dir null")
    compare(projectOf({ id: 1, repo_dir: 42 }).repo_dir, "42", "repo_dir number")
    compare(projectOf({ id: 1, repo_dir: true }).repo_dir, "true", "repo_dir boolean")
    compare(projectOf({ id: 1, repo_dir: "" }).repo_dir, "", "repo_dir empty")

    // synthetic: extra keys inside the project are dropped
    var extra = projectOf({ id: 1, repo_dir: "/p", name: "x", root_path: "/r", story_id: "s" })
    compare(Object.keys(extra).sort().join(","), "id,repo_dir")
    compare(extra.id, 1)
    compare(extra.repo_dir, "/p")
  }

  function test_normalize_project_ignores_status() {
    // synthetic: a project only on the am status run and on am status itself
    var raw = amRun("status-started.json")
    delete raw.row.project
    raw.status.run.project = { id: 2, repo_dir: "/from/run" }
    raw.status.project = { id: 3, repo_dir: "/from/status" }
    compare(Runs.normalizeRun(raw).project, null, "am status never supplies the project")

    // synthetic: a project on the row, the am status run and am status
    var both = amRun("status-started.json")
    both.status.run.project = { id: 2, repo_dir: "/from/run" }
    both.status.project = { id: 3, repo_dir: "/from/status" }
    var p = Runs.normalizeRun(both).project
    compare(p.id, 1, "the row's id wins")
    compare(p.repo_dir, "/home/user/Code/omarchy-project-manager", "the row's repo_dir wins")
  }

  function test_normalize_project_independent_of_repo_dir() {
    // synthetic: the row's repo_dir and its project's repo_dir edited to differ
    var differ = amRun("status-started.json")
    differ.row.repo_dir = "/row/dir"
    differ.row.project.repo_dir = "/project/dir"
    var d = Runs.normalizeRun(differ)
    compare(d.repo_dir, "/row/dir")
    compare(d.project.repo_dir, "/project/dir")

    // synthetic: the row's and the am status run's repo_dir blanked
    var blank = amRun("status-started.json")
    blank.row.repo_dir = ""
    blank.status.run.repo_dir = ""
    var b = Runs.normalizeRun(blank)
    compare(b.repo_dir, "", "project.repo_dir is never the run's fallback")
    compare(b.project.repo_dir, "/home/user/Code/omarchy-project-manager")

    // synthetic: the project's repo_dir blanked
    var emptyProject = amRun("status-started.json")
    emptyProject.row.project.repo_dir = ""
    var e = Runs.normalizeRun(emptyProject)
    compare(e.project.repo_dir, "", "the run's repo_dir never fills the project's")
    compare(e.repo_dir, "/home/user/Code/omarchy-project-manager")
  }

  function test_normalize_project_is_a_copy() {
    var raw = amRun("status-started.json")
    var before = JSON.stringify(raw)
    var r = Runs.normalizeRun(raw)
    verify(r.project !== raw.row.project, "project is a copy")
    r.project.id = 99
    r.project.repo_dir = "changed"
    r.project.extra = 1
    compare(JSON.stringify(raw), before, "changing the output leaves the input unchanged")

    var later = amRun("status-started.json")
    var out = Runs.normalizeRun(later)
    var outBefore = JSON.stringify(out)
    later.row.project.id = 42
    later.row.project.repo_dir = "later"
    later.row.project.extra = 1
    compare(JSON.stringify(out), outBefore, "changing the input after the call leaves the output unchanged")
  }

  function test_normalize_project_own_proto_key() {
    // synthetic: an own __proto__ key inside the row's project, which no capture contains
    var p = projectOf(JSON.parse('{"__proto__": {"id": 5, "repo_dir": "/evil"}, "id": 1, "repo_dir": "/p"}'))
    compare(Object.getPrototypeOf(p) === Object.prototype, true, "prototype")
    compare(Object.keys(p).sort().join(","), "id,repo_dir")
    compare(p.id, 1)
    compare(p.repo_dir, "/p")

    var only = projectOf(JSON.parse('{"__proto__": {"id": 5, "repo_dir": "/evil"}}'))
    compare(only.id, null, "an id behind __proto__ is not read")
    compare(only.repo_dir, "", "a repo_dir behind __proto__ is not read")
  }

  function test_normalize_as_of_seq_not_kept() {
    var raw = amRun("status-started.json")
    compare(raw.status.as_of_seq, 989, "the am status capture carries as_of_seq")
    compare(raw.status.store_id, "91b9e8afc25044c385859292bfabfde7", "the am status capture carries store_id")
    var plain = Runs.normalizeRun(raw)
    var keys = Object.keys(plain)
    compare(keys.indexOf("as_of_seq"), -1, "as_of_seq from am status")
    compare(keys.indexOf("store_id"), -1, "store_id from am status")

    // synthetic: the am runs envelope's as_of_seq and store_id placed on the row
    var envelope = F.load("runs.json").data
    compare(envelope.as_of_seq, 989, "the am runs capture carries as_of_seq")
    compare(envelope.store_id, "91b9e8afc25044c385859292bfabfde7", "the am runs capture carries store_id")
    var onRow = amRun("status-started.json")
    onRow.row.as_of_seq = envelope.as_of_seq
    onRow.row.store_id = envelope.store_id
    var r = Runs.normalizeRun(onRow)
    compare(Object.keys(r).indexOf("as_of_seq"), -1, "as_of_seq from the row")
    compare(Object.keys(r).indexOf("store_id"), -1, "store_id from the row")
    compare(JSON.stringify(r), JSON.stringify(plain), "the row's as_of_seq and store_id change nothing")
  }

  function test_normalize_unknown_keys_ignored() {
    var plain = Runs.normalizeRun(amRun("status-started.json"))

    // synthetic: keys normalizeRun does not read, on raw, the row, am status and the am status run
    var raw = amRun("status-started.json")
    raw.extra = { a: 1 }
    raw.row.future_key = "x"
    raw.status.future_key = [1]
    raw.status.run.future_key = { b: 2 }
    compare(JSON.stringify(Runs.normalizeRun(raw)), JSON.stringify(plain), "unknown keys change nothing")

    var fixture = amRun("status-started.json")
    var keys = Object.keys(plain)
    var rowKeys = ["story_id", "card_id", "progress"]
    for (var i = 0; i < rowKeys.length; i++) {
      verify(hasOwn(fixture.row, rowKeys[i]), "the capture's row carries " + rowKeys[i])
      compare(keys.indexOf(rowKeys[i]), -1, "row " + rowKeys[i] + " is not kept")
    }
    var statusKeys = ["warnings", "integrity"]
    for (var j = 0; j < statusKeys.length; j++) {
      verify(hasOwn(fixture.status, statusKeys[j]), "the capture's am status carries " + statusKeys[j])
      compare(keys.indexOf(statusKeys[j]), -1, "am status " + statusKeys[j] + " is not kept")
    }
  }

  function test_normalize_takes_no_events() {
    var plain = JSON.stringify(Runs.normalizeRun(amRun("status-started.json")))
    var log = F.load("events.json").data
    verify(log.events.length > 0, "the events capture has events")

    // synthetic: events.json's events and cursors placed on raw and on am status
    var raw = amRun("status-started.json")
    var targets = [raw, raw.status]
    for (var i = 0; i < targets.length; i++) {
      targets[i].events = log.events
      targets[i].gseq = log.events[log.events.length - 1].gseq
      targets[i].seq = log.events[0].seq
      targets[i].head = log.head
      targets[i].cursor_reset = true
    }
    compare(JSON.stringify(Runs.normalizeRun(raw)), plain, "events and cursors change nothing")
  }

  function test_normalize_project_garbage_never_throws() {
    // synthetic: a project whose id and repo_dir are the wrong types
    compare(JSON.stringify(projectOf({ id: {}, repo_dir: [] })), JSON.stringify({ id: null, repo_dir: "" }), "wrong types")

    // synthetic: a project with no prototype
    compare(JSON.stringify(projectOf(Object.create(null))), JSON.stringify({ id: null, repo_dir: "" }), "no prototype")
  }
```

- [ ] **Step 2: Run the runs domain tests to verify they fail**

Run: `bash tests/run.sh domain/tst_runs`
Expected: the pytest part passes; then `== tests/core/domain/tst_runs.qml` prints `FAIL!` lines, among them `test_normalize_garbage` (the `checkDefaults` key list lacks `project`; `r.project` is `undefined`, not `null`), `test_normalize_scalars_from_fixture` (key list), and the new `test_normalize_project_*` tests (e.g. `TypeError: Cannot read property 'sort' of undefined` style failures or `Actual (): undefined`). The three tests that pin current behaviour — `test_normalize_as_of_seq_not_kept`, `test_normalize_unknown_keys_ignored`, `test_normalize_takes_no_events` — already pass (they pin that nothing changes). The script exits non-zero.

- [ ] **Step 3: Implement `project` in `normalizeRun`**

In `core/domain/runs.js`, right after the lease block (the `if (isObject(control.lease)) { ... }` that ends before `var requests = []`), add:

```js
  var project = null
  if (isObject(row.project)) {
    var p = row.project
    project = {
      id: typeof p.id === "number" && isFinite(p.id) ? p.id : null,
      repo_dir: text(p.repo_dir)
    }
  }
```

In the returned object, add `project: project,` after `lease: lease,` so it reads:

```js
  return {
    id: firstText(row.id, run.id),
    repo_dir: firstText(row.repo_dir, run.repo_dir),
    milestone_id: firstText(run.milestone_id, row.milestone_id),
    status: firstText(run.status, row.status),
    started_at: firstText(row.started_at, run.started_at),
    base_branch: firstText(row.base_branch, run.base_branch),
    branch_prefix: firstText(row.branch_prefix, run.branch_prefix),
    workflow: firstText(row.workflow, run.workflow),
    lease: lease,
    project: project,
    requests: requests,
    rows: rows,
    tree: { stories: stories, subtasks: subtasks }
  }
```

Then replace the doc comment's input block and add the output lines. Lines 7-22 of `core/domain/runs.js` (from `// Input of normalizeRun:` through `//   }`) become:

```js
// Input of normalizeRun:
//   raw = {
//     row:    one `am runs` entry without its `status`:
//             { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at,
//               milestone_id, card_id, lease, progress, project: { id, repo_dir } }
//     status: `am status` data, may be absent:
//             { as_of_seq, store_id,
//               run: { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at },
//               stories: [{ card_id, title, level, status, tip_branch,
//                           subtasks: [{ card_id, branch, base_branch, status, worktree_path,
//                                        phases: [{ name, kind, status, started_at, ended_at, detail,
//                                                   attempts: [{ n, status, ... }] }] }] }],
//               rows: [{ story, subtask, phase, attempt, state }],
//               control: { lease: { pid, host, heartbeat_at, accepting, live, ... },
//                          requests: [{ command, requested_at, handled_at }], claims },
//               integrity }
//   }
```

and, between the `requests` sentence (ending `handled_at "" means the run has not acted on it yet.`) and the `tree.stories:` line, insert:

```js
// `project` is the row's { id, repo_dir }: id a finite number else null,
// repo_dir text. It is null when the row has no project object; am status
// never supplies it, and the run's repo_dir is independent of it.
```

and replace the closing paragraph

```js
// The status always comes from `am`, never from a brd card. The output holds
// copies, never am's objects. Never throws: anything missing or malformed
// becomes its default, and a missing lease means the run is not live.
```

with

```js
// as_of_seq and store_id are not kept: the store reads them. Keys not named
// here are ignored. Only `row` and `status` are read; it takes no events.
// The status always comes from `am`, never from a brd card. The output holds
// copies, never am's objects. Never throws: anything missing or malformed
// becomes its default, and a missing lease means the run is not live.
```

- [ ] **Step 4: Run the runs domain tests to verify they pass**

Run: `bash tests/run.sh domain/tst_runs`
Expected: `== tests/core/domain/tst_runs.qml` then `Totals: 180 passed, 0 failed, 0 skipped, 0 blacklisted` (169 before plus the 11 new tests), no `FAIL` and no `TypeError`/`ReferenceError` lines; exit code 0.

- [ ] **Step 5: Run the whole suite**

Run: `bash tests/run.sh`
Expected: pytest reports all passed (including `tests/architecture` and `tests/contract`), every `tst_*.qml` prints `Totals: N passed, 0 failed`, among them `tests/core/stores/tst_run_store.qml` and `tests/ui/screens/tst_run_detail_screen.qml`; no `TypeError`/`ReferenceError` line; exit code 0.

- [ ] **Step 6: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): keep the am runs row's project on the run model

normalizeRun returns project { id, repo_dir } from the am runs row, null
without one; tests pin that as_of_seq, store_id, unknown keys and events
never reach the model."
```
<!-- task-pipeline: validated -->
