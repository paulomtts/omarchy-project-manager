# 3.4 Real-data flow test of the run monitor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One new QML flow test, `tests/ui/tst_runs_real_data.qml`, feeds the real `Panel` a `runs-snapshot.py` reply built only from the captured am fixtures and pins what a person sees on the Runs list, Run detail (tree, default attempt, logs argv, output pane), the Graph's story node and a subtask's card detail.

**Architecture:** Test-only. The file mirrors `tests/ui/tst_runs_flow.qml`'s harness (`make()` builds `ui/Panel.qml`, disarms the export, snapshot and settings runners) but never assigns `p.app.runs.runs`: every run enters through `p.app.runs.refresh()` answered on `snapshotRunner.current` with `runs.json`'s two rows whose `status` key is replaced by `status-started.json` / `status-done.json` data (exactly what `core/backend/runs/runs-snapshot.py:108-117` does). Logs launches are answered with the unedited `logs-attempt.json`. No production file changes; a real failure is a defect report for an earlier subtask, not a fix here.

**Tech Stack:** QML (Qt 6, `QtQuick`, `QtTest`), run by `qmltestrunner` through `bash tests/run.sh [filter]`. `tests/run.sh` always runs the whole pytest suite first, then every `tst_*.qml` whose path contains the filter, with `-import tests/stubs` and `QML_XHR_ALLOW_FILE_READ=1` (needed by `tests/helpers/amFixtures.js`). A failing QML test prints `FAIL!  : ...` and a `Totals:` line with a non-zero failed count; any `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `is not a function` line in the output also fails the suite. For a quick single-file run without pytest: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_runs_real_data.qml` (from the repo root; prints the same `FAIL!`/`Totals` lines). Panel teardown prints `TypeError: Cannot read property 'width' of null` QWARN lines (`BoardScreen.qml:59`, `CardDetailScreen.qml:180`) in every Panel flow test; `tests/run.sh` deliberately ignores them (`grep -v "width' of null"`), so they are not a failure and need no fix here.

**Spec:** `docs/superpowers/specs/3-4-real-data-flow-test-c73f0325.md` (prepended below).

## Global Constraints

- Test inputs of am output come only from `tests/fixtures/am/`, loaded with `tests/helpers/amFixtures.js` `load(name)` (fresh parse per call). Never edit, add or copy a fixture file.
- A hand-written am payload only for a synthetic edge case, labelled with a `// synthetic:` comment; an edit is made on a fresh `F.load` copy and never changes the shape.
- Replacing a runs row's `status` key with the `am status` data is the helper's own transformation: no `synthetic:` label; a comment says it mirrors `runs-snapshot.py`.
- Board cards (brd input) are built with a local `card()` helper, same signature as `tests/ui/tst_graph_flow.qml:15`, using the fixture's real ids.
- No production change (`core/`, `ui/`, `core/backend/`), no change to any other test, no new component, no icon file, no glyph literal outside expected-text strings.
- Comments state the contract only, no narrative and no plan/task references.
- `bash tests/run.sh` green; the new file runs with no QML warning lines that `tests/run.sh` treats as failures.
- If an assertion fails for real (not the deliberate red check), STOP: report the failing assertion and the file:line of the production code responsible. Do not change production code and do not weaken the expected value.

## Review Focus

1. **A superseded logs fetch answering late** — the default attempt's launch is still in flight when a subtask row is activated; if that first process answers afterwards, a person expects the pane to keep the second attempt's text. Pinned in Task 2 (`test_a_subtask_row_fetches_its_attempt_and_the_pane_shows_the_captured_output`, the late `first` reply).
2. **The same capture arriving again (a poll)** while the output pane shows an attempt — a person expects the selection and text to stay and no new fetch (`logsLoading` false). Pinned in Task 2 (same test, the second `feedFixtures`).
3. **The started (live) run's default attempt** — the parent's acceptance value `299ec9c0… explore 1` is never opened in the spec's table; a person opening the running run expects its running attempt and the root-first argv. Pinned in Task 2 (`test_opening_the_started_run_fetches_its_running_attempt`).
4. **The sidebar attention count on real runs** — one live started run and one done run need no attention; a person expects an empty `navCountRuns`. Pinned in Task 1 (`test_the_runs_list_shows_progress_and_the_current_phase_of_real_runs`).
5. **A finished story of the started run on the Graph** — story `1c665cfd…` (2 done subtasks) should read `✔ 2` with no running segment, not borrow the run's running state. Pinned in Task 3 (`test_the_graph_story_node_shows_the_started_runs_rollup_and_rings_the_running_subtask`).

All expected values (including these five) were re-derived on 2026-10-05 by running `core/domain/runs.js` under node on the committed fixtures, and the complete file below was run once against this branch: 9 passed (7 tests + init/cleanup), 0 failed, no warning lines; changing `"3/8"` to `"0/0"` made exactly one test fail.

---

## Spec (prepended; headings demoted one level)

## 3.4 Real-data flow test of the run monitor — design

Card `c73f0325`, a subtask of story `44b929b5` ("Attempt output from real am
logs"), blocked by `27704601` (3.3, `RunStore` passes the project root, landed
as `f967196`). Parent spec:
`docs/superpowers/specs/2026-10-05-align-run-model-design.md` (below:
**parent**). Work breakdown item 3 (parent L327-328) ends with "a real-data
flow test of the whole chain": this subtask is that test, and nothing else.

### Goal

Every run test so far feeds the panel either hand-built normalized runs
(`tst_runs_flow.qml`'s `run()`, `treeRun()`) or hand-written snapshot entries
(`snapEntry()`, which still carries the guessed top-level `subtasks`, parent
L132). The defect this milestone fixes (parent L7-14) hid behind exactly that.
This subtask adds one QML flow test, `tests/ui/tst_runs_real_data.qml`, that
feeds the **real** `Panel` a `runs-snapshot.py` reply assembled only from the
captured am fixtures, and asserts what a person sees on the Runs list, Run
detail (tree, default attempt, logs argv, output pane), the Graph and a
subtask's card detail. It changes no production file. If a check fails
against the current branch, that is a defect report for the owning earlier
subtask, not licence to change production code here (see "Out of scope").

### Inherited constraints

| constraint | source |
|---|---|
| Test inputs of am output come from `tests/fixtures/am/`; QML loads them with `tests/helpers/amFixtures.js` `load(name)` (fresh parse per call, needs `QML_XHR_ALLOW_FILE_READ=1`, set by `tests/run.sh`) | parent L269-276; card |
| A hand-written am payload only for a synthetic edge case, labelled `synthetic:`; edits to a fixture are made on a fresh copy, labelled, never change the shape | parent L257-267 |
| A snapshot entry is the `am runs` row whose `status` the helper replaced with the `am status` data; the store normalizes it as `normalizeRun({row: <entry without status>, status: entry.status})` | parent L207-209; `core/backend/runs/runs-snapshot.py:108-117`; `core/stores/RunStore.qml` `rowOf` / `applySnapshot` |
| Acceptance numbers: started run 3/8, `explore`, default `299ec9c0… explore 1`; done run 10/10, `""`, default `22153f5f… review 1`; `runTree(status-done)` stories of 2, 3, 1, 4 subtasks, each node `done`, current `review.1`, 7 attempts | parent L205-226 |
| `cardRunState(runs, "299ec9c0…")` on the started run is `running`, phase `explore`, attempt 1 | parent L222-223 |
| `logTail(logs-attempt.json data)` is the 19 lines of `artifacts.stdout.text` (stderr `text` null: no lines), not truncated | parent L227-229 |
| `logs-attempt.json` is `am logs 20261004T204141Z-cb11063d adff6c85… --phase review --attempt 1` | parent L249 |
| `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT`; the store sends the open project's root first | parent L169-171; 3.3 spec "Behavior" 1 |
| Rollups count each real subtask once by its own status | parent L155-159 (decision 3) |
| `docs/architecture.md` layering; `tests/architecture` passes (no duplicated components, icon glyph rules) | card |
| Comments state the contract only, no narrative | card |
| Tests first; `bash tests/run.sh` green | card |

### The input

Built in the test, from fixtures only, exactly as `runs-snapshot.py` builds it:

- `runs = F.load("runs.json").data.runs` — two rows, in this order:
  `20261005T021400Z-837c4431` (started, lease live, milestone
  `837c4431-7a24-4531-96a8-881698ea8c5e`) and `20261004T204141Z-cb11063d`
  (done, lease null).
- `runs[0].status = F.load("status-started.json").data`;
  `runs[1].status = F.load("status-done.json").data`. Replacing the `status`
  key is the helper's own transformation, not a synthetic edit, so it carries
  no `synthetic:` label; a comment states that it mirrors `runs-snapshot.py`.
- The reply line is `JSON.stringify({ ok: true, runs: runs, data_dir: "/d" }) + "\n"`
  (the helper's envelope; `data_dir` is not read by the store), answered with
  exit 0 on `p.app.runs.snapshotRunner.current` after `p.app.runs.refresh()`.
- The logs reply is `JSON.stringify(F.load("logs-attempt.json")) + "\n"`,
  exit 0, **unedited**: the test asks for exactly the attempt it captures
  (below), so no `synthetic:` edit is needed.

Board cards for the Graph and card-detail checks are brd input, not am output
(the fixture rule does not cover them). They are built with a local `card()`
helper (same signature as `tests/ui/tst_graph_flow.qml:15`) using the
fixture's real ids: milestone `837c4431-…` (status `in_progress`) > stories
`1c665cfd-…`, `d3d879b9-…`, `3d877d1f-…`, `c56468c7-…` (statuses
`done`, `in_progress`, `todo`, `todo`), with story `d3d879b9-…`'s children
`a19ca446-…` (`done`), `299ec9c0-…` (`in_progress`), `fdb5feb1-…` (`todo`).
Full ids are copied from `status-started.json` (`data.stories[].card_id`,
`data.stories[1].subtasks[].card_id`). A comment states these are the brd
cards of the started run's milestone. None is `merged`, `canceled` or
`archived`, so no mark is hidden (`core/domain/board.js:73`).

### Harness

Mirrors `tests/ui/tst_runs_flow.qml`: `TestCase { when: windowShown; visible:
true; width: 900; height: 700 }`, imports `../helpers/find.js` as `H` and
`../helpers/amFixtures.js` as `F`. `make()` builds `../../ui/Panel.qml` in a
temporary host, sets `opened = true`, `projects.stateLoaded = true`,
`applyProjectsList([{ root_path: "/home/u/a", name: "alpha" }])`, disarms
`extras.exportProc` (`running = false`, `launchGuard = "stale"`),
`extrasLoading = false`, and cancels `runs.snapshotRunner` and
`runs.settingsLoadRunner`. Unlike `tst_runs_flow.qml`, `make()` does **not**
assign `p.app.runs.runs`: every run in this file enters through the snapshot
reply. Small local helpers only (`reply`, `snapshot`, `feedFixtures`,
`logsReply`, `card`, `argv`), no new component, no glyph literal outside
expected-text strings already produced by `runGlyphs.js`.

### Behavior the test pins

All on one panel per test function, project root `/home/u/a`.

1. **Runs list.** After the fixture snapshot and `showSection("runs")`:
   `runRow0` and `runRow1` exist, in snapshot order;
   `runRowProgress0.text === "3/8"`, `runRowProgress1.text === "10/10"`;
   `runRowPhase0.text === "explore"`; `runRowPhase1.text === ""` (and not
   visible).
2. **Run detail tree of the done run.** `openRun("20261004T204141Z-cb11063d")`:
   `runDetailView` visible; `runStory0`..`runStory3` exist and `runStory4`
   does not; subtask rows `runSubtask<s>_<t>` exist for `t < n` and not for
   `t = n`, with `n` = 2, 3, 1, 4 for `s` = 0..3. `runSubtaskLabel0_0.text`
   contains `adff6c85-ba42-4586-8066-b93e8ac877bb` and ends with
   `· review.1` (each node's current attempt, parent decision 4, L160-162).
3. **Default attempt on selection, argv with the root.** Right after
   `openRun`, with no click: `p.app.runs.selectedAttempt` is
   `{ card_id: "22153f5f-9632-4b5f-a7dd-664c39d89e5c", phase: "review",
   attempt: 1 }`; `logsRunner.current.command[1]` contains
   `core/backend/runs/runs-logs.py`; `command.slice(2).join("|")` is
   `"/home/u/a|20261004T204141Z-cb11063d|22153f5f-9632-4b5f-a7dd-664c39d89e5c|review|1"`.
4. **Output pane from the captured logs.** Activating `runSubtask0_0` (its
   `activated()` signal, the row's click path) selects
   `adff6c85-… review 1`; the new launch's argv tail is
   `"/home/u/a|20261004T204141Z-cb11063d|adff6c85-ba42-4586-8066-b93e8ac877bb|review|1"`.
   Answering it with the unedited `logs-attempt.json` reply gives
   `runOutputHeading.text === "Output · adff6c85-ba42-4586-8066-b93e8ac877bb review.1"`,
   `runOutputText.text` equal to the fixture's `data.artifacts.stdout.text`
   with its single trailing `"\n"` removed (19 lines; the expected value is
   read from a fresh `F.load`, not retyped), `runOutputError` not visible,
   `p.app.runs.logsTruncated === false`.
5. **Subtask mark and story rollup of the started run (Graph).** With the
   board cards above applied and the fixture snapshot fed,
   `showSection("graph")`, `graphViewChips.chosen("story")`, `wait(200)`: the
   story node `graphNoded3d879b9-cb74-41ca-9a37-63f477de9711` (the story
   delegate's `objectName` is `"graphNode" + id`) has a visible `runMark`
   whose `runBadge.text === "⟳ 1 ✔ 1"` and a visible `runRollupBar` with
   `runRollupRunning` `"⟳ 1"`, `runRollupDone` `"✔ 1"`,
   `runRollupPending` `"1 pending"`, and `runRollupParked` /
   `runRollupEscalated` not visible (rollup running 1, done 1, pending 1,
   total 3). Its pip `statusPip299ec9c0-b935-4c44-a7a0-982a104cbfe5` is
   `ringed`, and `statusPipa19ca446-…` and `statusPipfdb5feb1-…` are not
   (only the subtask am is on).
6. **Subtask card's run row.** `openCard("299ec9c0-b935-4c44-a7a0-982a104cbfe5")`:
   `cardRunsHeader` visible; `cardRunRow0` exists and `cardRunRow1` does not
   (only the started run touches it); `cardRunId0` is the started run's short
   id as `Runs.shortId` gives it on the Runs list (`runRowId0.text` of the
   same snapshot is the reference, read in the same test, not retyped);
   `cardRunPhase0.text === "explore"`.

Expected values in 1-6 were computed by running the branch's
`core/domain/runs.js` under node on the committed fixtures (2026-10-05) and
match the parent's acceptance values (L205-229). The planner should re-derive
any value it doubts the same way rather than from memory.

### Error paths and edge input

The test feeds no error replies: failures of snapshot and logs replies are
already covered by `tests/core/stores/tst_run_store.qml` and
`tst_runs_flow.qml`. Two real-data conditions are pinned because they are
where hand-written data lied:

- A finished run has no started phase and `current: null`; its default
  attempt still exists (behavior 3, the rows fallback, parent decision 4, L160-162).
- A selection change while the default fetch is still in flight: the second
  launch is the one answered (behavior 4); the first launch's process is never
  answered and the pane shows only the second attempt's text.

If `make()`'s disarming leaves any QML `TypeError` / `ReferenceError` /
`non-existent` / `Unable to assign` / `is not a function` line in the output,
`tests/run.sh` fails the suite; the test must run clean.

### Tests

One file, tier **QML UI flow** (`tests/ui/`, real `Panel`, `qmltestrunner`
via `bash tests/run.sh`, auto-discovered by `find -name 'tst_*.qml'`).
Why this tier: the observable is what the composed panel shows when the real
store, domain and screens consume real am output end to end; a store unit test
cannot see the screens, and a screen test with a stub app would skip the
store's `rowOf` / `normalizeRun` / `openDefaultAttempt` / `applyLogs` chain
that the card exists to cover. No helper process or am runs: runners are
answered through `outText` / `exited(0)` as in `tst_runs_flow.qml`.

`tests/ui/tst_runs_real_data.qml`, `name: "RunsRealData"`:

| test | pins |
|---|---|
| `test_the_runs_list_shows_progress_and_the_current_phase_of_real_runs` | behavior 1 |
| `test_run_detail_of_the_done_run_shows_its_stories_and_subtasks` | behavior 2 |
| `test_opening_the_done_run_fetches_its_default_attempt_under_the_project_root` | behavior 3 |
| `test_a_subtask_row_fetches_its_attempt_and_the_pane_shows_the_captured_output` | behavior 4 and the in-flight edge |
| `test_the_graph_story_node_shows_the_started_runs_rollup_and_rings_the_running_subtask` | behavior 5 |
| `test_the_running_subtasks_card_lists_the_started_run_at_its_phase` | behavior 6 |

TDD note: this subtask adds tests over landed code, so "red first" is
satisfied by confirming each test can fail — e.g. temporarily changing one
expected value (`"3/8"` → `"0/0"`) and seeing that test fail — then restoring
it. No production edit is made to obtain red. If a test fails for real, stop
and report the failing assertion with the file:line of the production code
responsible (it belongs to an earlier subtask's card).

Unchanged and still green: every other test, `tests/architecture` (no new
component, no icon file, no glyph outside expected strings), pytest.

Suite gate: `bash tests/run.sh` green (single file first:
`bash tests/run.sh runs_real_data`).

### Out of scope

- Any production change (`core/`, `ui/`, `core/backend/`): `logTail` (3.1),
  `runs-logs.py --repo-dir` (3.2) and `RunStore` passing the root (3.3) are
  done; normalization, rollups, `runTree`, `defaultAttempt` belong to work
  item 2 (parent L324-326).
- Rewriting `tst_runs_flow.qml`'s `snapEntry()` / `run()` / `treeRun()` or any
  other existing test.
- New fixtures, fixture edits, `tests/helpers/amFixtures.js`, the contract
  test (work item 1, parent L321-323).
- The escalated and integrate fixtures, cancel spellings, watch schemas, the
  footer (work item 4, parent L329-330); docs (work item 5, parent L331).
- The Board's subtask mark: the Board shows roots only
  (`ui/screens/BoardScreen.qml:97-98`, `core/stores/BoardStore.qml:131`), so a
  real subtask is never a Board card; its mark is checked on the Graph and the
  card detail instead.
- Integrate resolver attempts and deterministic-phase logs (parent "Not
  changed").

---

## File Structure

- Create: `tests/ui/tst_runs_real_data.qml` — the whole deliverable. One `TestCase` named `RunsRealData`, auto-discovered by `tests/run.sh` (`find tests -name 'tst_*.qml'`). Built up over three tasks: harness + Runs screens (Task 1), logs path (Task 2), board-backed screens (Task 3).
- No other file is created or modified.

Read before starting (do not modify): `tests/ui/tst_runs_flow.qml` (harness this mirrors), `tests/helpers/find.js` (`H.find` depth-first by `objectName`), `tests/helpers/amFixtures.js`, `tests/fixtures/am/{runs,status-started,status-done,logs-attempt}.json`, `core/stores/RunStore.qml` (`refresh`, `rowOf`, `applySnapshot`, `selectAttempt`, `logsAfterSnapshot`), `ui/screens/RunsScreen.qml:150-240`, `ui/screens/RunDetailScreen.qml:240-380`, `ui/screens/GraphScreen.qml:30-80`, `ui/components/GraphView.qml:545-660`, `ui/screens/CardDetailScreen.qml:165-280`.

Object names the tests read (all verified on this branch):
- Runs list: `runRow<i>`, `runRowId<i>`, `runRowProgress<i>`, `runRowPhase<i>` (`ui/screens/RunsScreen.qml:159,196,217,225`); sidebar `navCountRuns`.
- Run detail: `runDetailView`, `runStory<s>` (`RunDetailScreen.qml:331`), `runSubtask<s>_<t>` (a `UI.ListRow`, signal `activated()`, `:358`), `runSubtaskLabel<s>_<t>` (`:369`), `runOutputHeading` / `runOutputError` / `runOutputText` (`:253,287,299`).
- Graph: chip row `graphViewChips` (`ui/Panel.qml:462`, signal `chosen(string id)`), story node `"graphNode" + id` (`GraphView.qml:557`), inside it `runMark` > `runBadge`, `runRollupBar` > `runRollupRunning|Parked|Escalated|Done|Pending`, pips `"statusPip" + id` with property `ringed` (`ui/components/StatusPips.qml:61-63`).
- Card detail: `cardRunsHeader`, `cardRunRow<i>`, `cardRunId<i>`, `cardRunPhase<i>` (`CardDetailScreen.qml:169,235,252,266`).

---

## Task 1: Harness and the Runs screens on the captured snapshot

**Files:**
- Create: `tests/ui/tst_runs_real_data.qml`

**Interfaces:**
- Consumes: `tests/helpers/find.js` `find(item, name)`; `tests/helpers/amFixtures.js` `load(name)`; `p.app.runs.refresh()`, `p.app.runs.snapshotRunner.current` (stub `Process` with `outText` and `exited(code)`), `p.navigator.showSection(name)`, `p.navigator.openRun(id)`.
- Produces (used by Tasks 2 and 3, same file): properties `startedRun`, `doneRun`; functions `make()` → Panel or null, `reply(proc, text, code)`, `snapshot()` → string, `feedFixtures(p)`, `openDoneRun()` → Panel (on the done run's detail, default logs launch in flight) or null.

- [ ] **Step 1: Write the file with the harness and the first two tests**

Create `tests/ui/tst_runs_real_data.qml` with exactly:

```qml
// tests/ui/tst_runs_real_data.qml
// The run monitor fed only the captured am output in tests/fixtures/am/: the
// Runs list, Run detail (tree, default attempt, logs argv, output pane), the
// Graph's story mark and a subtask's card detail, on the real Panel.
import QtQuick
import QtTest
import "../helpers/find.js" as H
import "../helpers/amFixtures.js" as F

TestCase {
  id: tc
  name: "RunsRealData"
  when: windowShown
  visible: true
  width: 900; height: 700
  Component { id: hostC; Item { width: 900; height: 700 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })

  readonly property string startedRun: "20261005T021400Z-837c4431"
  readonly property string doneRun: "20261004T204141Z-cb11063d"

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([pA])
    // Selecting the project starts a `brd export`, a runs snapshot and a run
    // settings read that cannot run here: all three are disarmed so their late
    // replies change nothing.
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.extras.extrasLoading = false
    p.app.runs.snapshotRunner.cancel()
    p.app.runs.settingsLoadRunner.cancel()
    return p
  }

  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // The runs-snapshot.py reply for the captured runs: each `am runs` row with
  // its `status` replaced by that run's `am status` data, as the helper does.
  function snapshot() {
    var runs = F.load("runs.json").data.runs
    runs[0].status = F.load("status-started.json").data
    runs[1].status = F.load("status-done.json").data
    return JSON.stringify({ ok: true, runs: runs, data_dir: "/d" }) + "\n"
  }

  // The next snapshot of project A is the captured one.
  function feedFixtures(p) {
    p.app.runs.refresh()
    reply(p.app.runs.snapshotRunner.current, snapshot(), 0)
  }

  // The panel on the done run's detail view, its default attempt's logs in flight.
  function openDoneRun() {
    var p = make(); if (!p) return null
    feedFixtures(p)
    p.navigator.showSection("runs")
    p.navigator.openRun(doneRun)
    wait(50)
    return p
  }

  function test_the_runs_list_shows_progress_and_the_current_phase_of_real_runs() {
    var p = make(); if (!p) return
    feedFixtures(p)
    p.navigator.showSection("runs")
    wait(50)
    verify(H.find(p, "runRow0"), "the started run's row")
    verify(H.find(p, "runRow1"), "the done run's row")
    verify(!H.find(p, "runRow2"), "two runs only")
    compare(p.app.runs.filteredRuns[0].id, startedRun)
    compare(p.app.runs.filteredRuns[1].id, doneRun)
    compare(H.find(p, "runRowProgress0").text, "3/8")
    compare(H.find(p, "runRowProgress1").text, "10/10")
    compare(H.find(p, "runRowPhase0").text, "explore")
    compare(H.find(p, "runRowPhase1").text, "")
    compare(H.find(p, "runRowPhase1").visible, false)
    compare(String(H.find(p, "navCountRuns").text), "", "a live run and a done run need no attention")
  }

  function test_run_detail_of_the_done_run_shows_its_stories_and_subtasks() {
    var p = openDoneRun(); if (!p) return
    var view = H.find(p, "runDetailView")
    verify(view, "the Run detail screen is mounted")
    compare(view.visible, true)
    var sizes = [2, 3, 1, 4]
    for (var s = 0; s < sizes.length; s++) {
      verify(H.find(p, "runStory" + s), "story " + s)
      for (var t = 0; t < sizes[s]; t++) verify(H.find(p, "runSubtask" + s + "_" + t), "subtask " + s + "_" + t)
      verify(!H.find(p, "runSubtask" + s + "_" + sizes[s]), "story " + s + " has " + sizes[s] + " subtasks")
    }
    verify(!H.find(p, "runStory4"), "four stories")
    var label = String(H.find(p, "runSubtaskLabel0_0").text)
    verify(label.indexOf("adff6c85-ba42-4586-8066-b93e8ac877bb") >= 0, label)
    verify(label.endsWith("· review.1"), label)
  }
}
```

- [ ] **Step 2: Prove the tests can fail (red check)**

These tests cover landed code, so red is shown by breaking an expected value, not production code. In `test_the_runs_list_shows_progress_and_the_current_phase_of_real_runs` change `compare(H.find(p, "runRowProgress0").text, "3/8")` to `compare(H.find(p, "runRowProgress0").text, "0/0")`, and in `test_run_detail_of_the_done_run_shows_its_stories_and_subtasks` change `var sizes = [2, 3, 1, 4]` to `var sizes = [2, 3, 1, 5]`.

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_runs_real_data.qml 2>&1 | grep -E "^FAIL|Totals"`
Expected: two `FAIL!` lines, one per test (`Compared values are not the same` actual `3/8`; `subtask 3_4` verify failure), `Totals: 2 passed, 2 failed`.

- [ ] **Step 3: Restore the expected values**

Change `"0/0"` back to `"3/8"` and `[2, 3, 1, 5]` back to `[2, 3, 1, 4]`.

- [ ] **Step 4: Run the file and see it pass clean**

Run: `bash tests/run.sh runs_real_data`
Expected: pytest all passed, then `== tests/ui/tst_runs_real_data.qml` and `Totals: 4 passed, 0 failed, 0 skipped, 0 blacklisted` with no `TypeError`/`ReferenceError`/`non-existent`/`Unable to assign`/`is not a function` lines. If an assertion fails, stop and report it (Global Constraints).

- [ ] **Step 5: Commit**

```bash
git add tests/ui/tst_runs_real_data.qml
git commit -m "test(runs): Runs list and Run detail tree on the captured am snapshot"
```

---

## Task 2: Default attempt, logs argv and the output pane on captured logs

**Files:**
- Modify: `tests/ui/tst_runs_real_data.qml` (add two helpers after `feedFixtures`, three tests before the closing `}` of `TestCase`)

**Interfaces:**
- Consumes (Task 1): `make()`, `reply(proc, text, code)`, `feedFixtures(p)`, `openDoneRun()`, `startedRun`, `doneRun`; store: `p.app.runs.selectedAttempt` (`{card_id, phase, attempt}` or null), `p.app.runs.logsRunner.current` (stub `Process`, `command` array: `[interpreter, helperPath, project, run, card, phase, attempt]`), `p.app.runs.logsText`, `p.app.runs.logsLoading`, `p.app.runs.logsTruncated`.
- Produces: functions `logsReply()` → string, `argv(proc)` → string (used only in this file).

- [ ] **Step 1: Add the helpers**

In `tests/ui/tst_runs_real_data.qml`, directly after the `feedFixtures(p)` function (before the `// The panel on the done run's detail view…` comment), insert:

```qml
  // The captured `am logs` reply, unedited, as one JSON line.
  function logsReply() { return JSON.stringify(F.load("logs-attempt.json")) + "\n" }

  // The argv after the interpreter and the helper path, joined by "|".
  function argv(proc) { return proc.command.slice(2).join("|") }
```

- [ ] **Step 2: Add the three tests**

Directly before the final `}` that closes `TestCase` (after `test_run_detail_of_the_done_run_shows_its_stories_and_subtasks`), insert:

```qml
  // A finished run has no started phase; its default attempt is its newest row.
  function test_opening_the_done_run_fetches_its_default_attempt_under_the_project_root() {
    var p = openDoneRun(); if (!p) return
    compare(p.app.runs.selectedAttempt,
            { card_id: "22153f5f-9632-4b5f-a7dd-664c39d89e5c", phase: "review", attempt: 1 })
    var proc = p.app.runs.logsRunner.current
    verify(proc, "the default attempt's logs were asked for")
    verify(String(proc.command[1]).indexOf("core/backend/runs/runs-logs.py") > 0, String(proc.command[1]))
    compare(argv(proc), "/home/u/a|" + doneRun + "|22153f5f-9632-4b5f-a7dd-664c39d89e5c|review|1")
  }

  // The default fetch is still in flight when the row is activated: the second
  // launch is the one answered, and the pane shows only its attempt. A late
  // answer of the first launch and the same snapshot again change nothing.
  function test_a_subtask_row_fetches_its_attempt_and_the_pane_shows_the_captured_output() {
    var p = openDoneRun(); if (!p) return
    var first = p.app.runs.logsRunner.current
    verify(first, "the default fetch is in flight")
    H.find(p, "runSubtask0_0").activated()
    compare(p.app.runs.selectedAttempt,
            { card_id: "adff6c85-ba42-4586-8066-b93e8ac877bb", phase: "review", attempt: 1 })
    var proc = p.app.runs.logsRunner.current
    verify(proc && proc !== first, "a new launch for the new attempt")
    compare(argv(proc), "/home/u/a|" + doneRun + "|adff6c85-ba42-4586-8066-b93e8ac877bb|review|1")
    reply(proc, logsReply(), 0)
    wait(50)
    compare(H.find(p, "runOutputHeading").text, "Output · adff6c85-ba42-4586-8066-b93e8ac877bb review.1")
    var stdout = F.load("logs-attempt.json").data.artifacts.stdout.text
    compare(H.find(p, "runOutputText").text, stdout.slice(0, stdout.length - 1))
    compare(H.find(p, "runOutputError").visible, false)
    compare(p.app.runs.logsTruncated, false)
    var envelope = F.load("logs-attempt.json")
    // synthetic: the superseded launch answers late with text of its own.
    envelope.data.artifacts.stdout.text = "late\n"
    reply(first, JSON.stringify(envelope) + "\n", 0)
    compare(p.app.runs.logsText, stdout.slice(0, stdout.length - 1), "the superseded fetch changes nothing")
    feedFixtures(p)
    compare(p.app.runs.selectedAttempt,
            { card_id: "adff6c85-ba42-4586-8066-b93e8ac877bb", phase: "review", attempt: 1 })
    compare(p.app.runs.logsLoading, false, "the same capture again fetches nothing")
    compare(H.find(p, "runOutputText").text, stdout.slice(0, stdout.length - 1))
  }

  function test_opening_the_started_run_fetches_its_running_attempt() {
    var p = make(); if (!p) return
    feedFixtures(p)
    p.navigator.showSection("runs")
    p.navigator.openRun(startedRun)
    wait(50)
    compare(p.app.runs.selectedAttempt,
            { card_id: "299ec9c0-b935-4c44-a7a0-982a104cbfe5", phase: "explore", attempt: 1 })
    compare(argv(p.app.runs.logsRunner.current),
            "/home/u/a|" + startedRun + "|299ec9c0-b935-4c44-a7a0-982a104cbfe5|explore|1")
  }
```

Notes for the implementer: `runOutputText` shows `Runs.logTail(data, 200).text`, which drops the stdout's single trailing `"\n"` (19 lines, not truncated); the expected value is read from a fresh `F.load`, never retyped. `runSubtask0_0` is a `UI.ListRow`; calling its `activated()` signal is the click path (`RunDetailScreen.qml:363-366`).

- [ ] **Step 3: Prove the new tests can fail (red check)**

Temporarily change, in `test_opening_the_done_run_fetches_its_default_attempt_under_the_project_root`, `phase: "review", attempt: 1 })` to `phase: "review", attempt: 2 })`; in `test_a_subtask_row_fetches_its_attempt_and_the_pane_shows_the_captured_output`, `"Output · adff6c85-ba42-4586-8066-b93e8ac877bb review.1"` to `"Output · adff6c85-ba42-4586-8066-b93e8ac877bb review.2"`; and in `test_opening_the_started_run_fetches_its_running_attempt`, `"|299ec9c0-b935-4c44-a7a0-982a104cbfe5|explore|1"` to `"|299ec9c0-b935-4c44-a7a0-982a104cbfe5|explore|2"`.

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_runs_real_data.qml 2>&1 | grep -E "^FAIL|Totals"`
Expected: three `FAIL!` lines, one for each of the three new tests, `Totals: 4 passed, 3 failed`.

- [ ] **Step 4: Restore the expected values**

Change the three `2`s from Step 3 back to `1` (`attempt: 1 })`, `review.1"`, `|explore|1"`).

- [ ] **Step 5: Run the file and see it pass clean**

Run: `bash tests/run.sh runs_real_data`
Expected: `Totals: 7 passed, 0 failed, 0 skipped, 0 blacklisted`, no warning lines. If an assertion fails, stop and report it with the production file:line (Global Constraints).

- [ ] **Step 6: Commit**

```bash
git add tests/ui/tst_runs_real_data.qml
git commit -m "test(runs): default attempt, logs argv and output pane on captured am logs"
```

---

## Task 3: The Graph's story mark and the subtask card's run row

**Files:**
- Modify: `tests/ui/tst_runs_real_data.qml` (add card-id properties after `doneRun`, two helpers after `argv`, two tests before the closing `}`)

**Interfaces:**
- Consumes (Tasks 1-2): `make()`, `feedFixtures(p)`, `startedRun`; `p.app.board.applyTreeData(roots)`, `p.navigator.openCard(id)`, `p.app.nav.viewMode`.
- Produces: properties `milestone`, `storyDone`, `storyStarted`, `storyPending1`, `storyPending2`, `subDone`, `subRunning`, `subPending`; functions `card(id, status, children, blockedBy)` → brd card object, `boardCards()` → `[milestone card]`.

- [ ] **Step 1: Add the card ids**

Directly after `readonly property string doneRun: "20261004T204141Z-cb11063d"`, insert:

```qml
  readonly property string milestone: "837c4431-7a24-4531-96a8-881698ea8c5e"
  readonly property string storyDone: "1c665cfd-9a72-4a9d-a539-4c83f0f6ddc1"
  readonly property string storyStarted: "d3d879b9-cb74-41ca-9a37-63f477de9711"
  readonly property string storyPending1: "3d877d1f-e4f8-49c8-8910-7475c541bba2"
  readonly property string storyPending2: "c56468c7-ade1-4b28-9450-78e480149003"
  readonly property string subDone: "a19ca446-659e-4735-86ed-5a583c1730bf"
  readonly property string subRunning: "299ec9c0-b935-4c44-a7a0-982a104cbfe5"
  readonly property string subPending: "fdb5feb1-0907-40b2-9937-d9b4cc2875f0"
```

(Ids copied from `tests/fixtures/am/status-started.json`: `data.stories[].card_id` and `data.stories[1].subtasks[].card_id`; the milestone is `runs.json` `data.runs[0].milestone_id`.)

- [ ] **Step 2: Add the board helpers**

Directly after the `argv(proc)` function, insert:

```qml
  function card(id, status, children, blockedBy) {
    return { id: id, title: "T " + id, description: "", status: status, blocked_by: blockedBy || [],
             created_at: "", updated_at: "", children: children || [] }
  }

  // The brd cards of the started run's milestone.
  function boardCards() {
    return [card(milestone, "in_progress", [
      card(storyDone, "done"),
      card(storyStarted, "in_progress", [card(subDone, "done"), card(subRunning, "in_progress"), card(subPending, "todo")]),
      card(storyPending1, "todo"),
      card(storyPending2, "todo")])]
  }
```

- [ ] **Step 3: Add the two tests**

Directly before the final `}` that closes `TestCase` (after `test_opening_the_started_run_fetches_its_running_attempt`), insert:

```qml
  function test_the_graph_story_node_shows_the_started_runs_rollup_and_rings_the_running_subtask() {
    var p = make(); if (!p) return
    p.app.board.applyTreeData(boardCards())
    feedFixtures(p)
    p.navigator.showSection("graph")
    H.find(p, "graphViewChips").chosen("story")
    wait(200)
    var node = H.find(p, "graphNode" + storyStarted)
    verify(node, "the started story's node")
    var mark = H.find(node, "runMark")
    compare(mark.visible, true)
    compare(H.find(mark, "runBadge").text, "⟳ 1 ✔ 1")
    var bar = H.find(node, "runRollupBar")
    compare(bar.visible, true)
    compare(H.find(bar, "runRollupRunning").text, "⟳ 1")
    compare(H.find(bar, "runRollupDone").text, "✔ 1")
    compare(H.find(bar, "runRollupPending").text, "1 pending")
    compare(H.find(bar, "runRollupParked").visible, false)
    compare(H.find(bar, "runRollupEscalated").visible, false)
    compare(H.find(node, "statusPip" + subRunning).ringed, true)
    compare(H.find(node, "statusPip" + subDone).ringed, false)
    compare(H.find(node, "statusPip" + subPending).ringed, false)
    var done = H.find(p, "graphNode" + storyDone)
    verify(done, "the done story's node")
    compare(H.find(done, "runBadge").text, "✔ 2")
    compare(H.find(done, "runRollupRunning").visible, false)
    compare(H.find(done, "runRollupDone").text, "✔ 2")
  }

  function test_the_running_subtasks_card_lists_the_started_run_at_its_phase() {
    var p = make(); if (!p) return
    p.app.board.applyTreeData(boardCards())
    feedFixtures(p)
    p.navigator.showSection("runs")
    wait(50)
    var shortId = String(H.find(p, "runRowId0").text)
    verify(shortId !== "", "the Runs list names the started run")
    p.navigator.openCard(subRunning)
    wait(50)
    compare(p.app.nav.viewMode, "entry")
    compare(H.find(p, "cardRunsHeader").visible, true)
    verify(H.find(p, "cardRunRow0"), "the started run's row")
    verify(!H.find(p, "cardRunRow1"), "only the started run touches the card")
    compare(H.find(p, "cardRunId0").text, shortId)
    compare(H.find(p, "cardRunPhase0").text, "explore")
  }
```

Notes for the implementer: the glyph strings `⟳` and `✔` are the expected text `ui/components/runGlyphs.js` produces (running, done); they appear only inside expected strings, which `tests/architecture` allows. `runRowId0` is read in the same test as the reference for `Runs.shortId`; do not retype it. The Board shows roots only, so the subtask's mark is checked on the Graph and the card detail, not the Board.

- [ ] **Step 4: Prove the new tests can fail (red check)**

Temporarily change `compare(H.find(bar, "runRollupPending").text, "1 pending")` to `"2 pending"`, and `compare(H.find(p, "cardRunPhase0").text, "explore")` to `"spec"`.

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_runs_real_data.qml 2>&1 | grep -E "^FAIL|Totals"`
Expected: two `FAIL!` lines (the graph test and the card test), `Totals: 7 passed, 2 failed`.

- [ ] **Step 5: Restore the expected values**

Change `"2 pending"` back to `"1 pending"` and `"spec"` back to `"explore"`.

- [ ] **Step 6: Run the whole suite**

Run: `bash tests/run.sh`
Expected: pytest all passed (includes `tests/architecture`); every `== tests/...qml` block ends with `Totals: N passed, 0 failed`; `tests/ui/tst_runs_real_data.qml` shows `Totals: 9 passed, 0 failed, 0 skipped, 0 blacklisted`; exit status 0 (`echo $?` → `0`); no warning lines. If anything fails, stop and report it (Global Constraints).

- [ ] **Step 7: Confirm nothing outside the test file changed**

Run: `git status --short`
Expected: only `tests/ui/tst_runs_real_data.qml` modified (plus, if not yet committed by the workflow, the spec/plan docs). No `core/`, `ui/`, `tests/fixtures/` or `tests/helpers/` change.

- [ ] **Step 8: Commit**

```bash
git add tests/ui/tst_runs_real_data.qml
git commit -m "test(runs): Graph story mark and subtask card run row on the captured am snapshot"
```

---

## Self-Review

**Spec coverage.**
- Behavior 1 (Runs list, snapshot order, `3/8`, `10/10`, `explore`, empty/hidden phase) → Task 1, test 1.
- Behavior 2 (done run tree 2/3/1/4, `runStory4` absent, `runSubtaskLabel0_0` id and `· review.1`) → Task 1, test 2.
- Behavior 3 (default `22153f5f… review 1` with no click, `runs-logs.py` path, root-first argv) → Task 2, test 3.
- Behavior 4 (activation selects `adff6c85… review 1`, argv, unedited logs reply, heading, 19-line text from fresh `F.load`, no error, not truncated) and the in-flight edge (second launch answered) → Task 2, test 4.
- Behavior 5 (story node mark `⟳ 1 ✔ 1`, rollup segments, parked/escalated hidden, only `299ec9c0` ringed) → Task 3, test 5.
- Behavior 6 (card RUNS header, one row, short id equal to `runRowId0`, phase `explore`) → Task 3, test 6.
- Harness (no `p.app.runs.runs` assignment; disarming; helpers `reply`, `snapshot`, `feedFixtures`, `logsReply`, `card`, `argv`) → Tasks 1-3. Input built from fixtures only, `status` replacement commented as the helper's → Task 1 `snapshot()`.
- "Run clean" (no warning lines) → Task 1 Step 4, Task 2 Step 5, Task 3 Step 6.
- TDD note (red by changing an expected value, no production edit) → each task's red-check step.
- Out of scope respected: one test file; no production, fixture, helper or other-test change (Task 3 Step 7).

**Placeholder scan.** No TBD/TODO; every code step has full code; every insert names its exact anchor.

**Type consistency.** `make`, `reply`, `snapshot`, `feedFixtures`, `openDoneRun`, `logsReply`, `argv`, `card`, `boardCards` and the id properties are defined once and used with the same names and arities in later tasks. Test names match the spec's table, plus `test_opening_the_started_run_fetches_its_running_attempt` (Review Focus 3).

**Review Focus.** Five lines, each with an owning test: 1-2 in Task 2 test 4, 3 in Task 2's added test, 4 in Task 1 test 1, 5 in Task 3 test 5.

**Note on the synthetic edit.** Review Focus 1 uses one `// synthetic:`-labelled edit of a fresh `F.load("logs-attempt.json")` copy (the late reply's text). The spec's own Behavior 4 reply stays unedited; the edit only gives the superseded launch distinguishable text.
<!-- task-pipeline: validated -->
