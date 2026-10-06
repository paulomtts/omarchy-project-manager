# 3.4 Real-data flow test of the run monitor — design

Card `c73f0325`, a subtask of story `44b929b5` ("Attempt output from real am
logs"), blocked by `27704601` (3.3, `RunStore` passes the project root, landed
as `f967196`). Parent spec:
`docs/superpowers/specs/2026-10-05-align-run-model-design.md` (below:
**parent**). Work breakdown item 3 (parent L327-328) ends with "a real-data
flow test of the whole chain": this subtask is that test, and nothing else.

## Goal

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

## Inherited constraints

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

## The input

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

## Harness

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

## Behavior the test pins

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

## Error paths and edge input

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

## Tests

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

## Out of scope

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
