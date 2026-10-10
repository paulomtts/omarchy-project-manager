# 2.2 RunStore: a stopped run opens on its failed attempt (card eeaaa018)

Parent: story d44f2afe. Blocked by: e69a6c2d (2.1 `runs-logs.py`: attempt 0 means am's newest,
landed in `e09bd7e`). Milestone spec: `docs/superpowers/specs/2026-10-05-resume-recover-design.md`
(cited below as "design", by section and line).

## Why

When the user selects an escalated run, the output pane opens on `Runs.defaultAttempt`: the
newest attempt of the first `started` phase, else the last row's phase. An escalated run has no
`started` phase, so the pane shows whatever ran last, which is not necessarily what failed. A
failed deterministic step (`verify`) records no attempts at all, and the store refuses attempt 0,
so that step's output can't be reached (design, Problem, lines 48-56). The design fixes this
in the selection (design, Behaviour, "The failed output opens by itself", lines 156-160;
Architecture, RunStore selection, lines 262-265). With this card, a stopped run opens on the
attempt `Runs.stopReport(run).attempt` names. That attempt is `0` for a step, and
`runs-logs.py` already turns `0` into "no `--attempt`" (card e69a6c2d).

## Where the change lives

- `core/stores/RunStore.qml`, in the existing `// ---- attempt logs (5.2)` section (today
  `:750`). The change updates `selectAttempt` (`:772`), `openDefaultAttempt` (`:820`),
  `logsAfterSnapshot` (`:829`) and `onSelectedRunIdChanged` (`:841`) in place and adds one
  property next to the other `logs*` properties. The design says the stopped-run attempt
  choice "changes the selection" in place and gets no new section (design, intro, lines
  29-33). The design's line numbers (`:303-316`, `:306`, `:346-349`, `:355-364`) are stale.
  Use the ones here, and read the file before editing.
- `tests/core/stores/tst_run_store.qml`: one new block (see Tests).
- Nothing else. `core/domain/runs.js` already provides `stopReport` (`:1148`), `defaultAttempt`
  (`:828`), `runState` (`:154`) and `attemptStatus` (`:854`). `fetchLogs` already sends
  `String(sel.attempt)` as the last argument, so attempt 0 sends `"0"` with no change.

## Behaviour

### B1. `selectAttempt` accepts attempt 0

`selectAttempt(cardId, phase, attempt)` accepts any `attempt` that is a finite number `>= 0`.
Attempt `0` stands for "the phase's newest recorded output, am's choice" (design,
Architecture, line 245: "attempt 0: the phase records none"). The rest stays as it is:

- It still refuses (does nothing: no selection change, no launch) when:
  - no run is selected;
  - `cardId` or `phase` is not a non-empty string;
  - `attempt` is not a number (`"1"`, `null`, `undefined`), is not finite (`NaN`,
    `Infinity`), or is negative (`-1`).
- It still resets `logsText`, `logsTruncated`, `logsFetchedMs` and `logsError` only when
  the `(card_id, phase, attempt)` triple differs from the shown one. It still sets
  `selectedAttempt` and calls `fetchLogs()`.
- With attempt `0`, the logs launch's argv ends in `…|<run>|<card>|<phase>|0`.
- `logsStatus` for an attempt-0 selection is `""`, because `Runs.attemptStatus` returns `""`
  for attempt `<= 0`. So a snapshot never refetches an attempt-0 selection through the
  status rule (B3, rule 3). Refresh (`refreshLogs`) and a state move (B3, rule 2) still do.
  This is accepted: a step's output is fetched again by Refresh, and the design's Limits
  (line 331) already say it is am's newest.

`ui/screens/RunDetailScreen.qml` (`:364-365`, `:413`) only calls `selectAttempt` with
attempts `> 0`, because the screen guards `currentAttempt > 0` itself. Its behaviour doesn't
change.

### B2. The opening attempt of the selected run

`openDefaultAttempt()` keeps its name, because `docs/architecture.md:90` and the existing
tests use it. Its contract becomes "the selected run's opening attempt":

1. `run = runById(selectedRunId)`. `rep = Runs.stopReport(run)`.
2. If `rep` is not null and `rep.attempt` is not null, the target is `rep.attempt`
   (`{card_id, phase, attempt}`, where `attempt` may be `0`).
3. Otherwise, the target is `Runs.defaultAttempt(run)`, exactly as today. This covers:
   - a running or done run (`stopReport` is null);
   - a parked or cancelled run (`stopReport.attempt` is null);
   - an escalated run whose report names only a synthetic node (`attempt` null).
4. If there is a target, `selectAttempt(target.card_id, target.phase, target.attempt)`.
   If there is none, the current selection is left as it is.
5. Every call records `logsRunState = Runs.runState(run)` when `run` is in the snapshot
   (not null), and `""` when it is not. It records this whether or not a target was found.

The failed attempt is chosen from the `am status` snapshot (`store.runs`) only, never from
events (design, line 265).

### B3. When the opening attempt is chosen again

There is a new store property, `property string logsRunState: ""`. It holds the
`Runs.runState` of the selected run as of the last time its opening attempt was chosen, or
`""` when that run was not in the snapshot at that moment. `clearLogs()` sets it to `""`.

- **Selection** (`onSelectedRunIdChanged`): `clearLogs()`, then, for a non-empty id,
  `openDefaultAttempt()` (B2). It stays as today, except that B2 now records
  `logsRunState`.
- **After every applied ok snapshot** (`logsAfterSnapshot`, still called once from
  `applyProjects` after `store.runs` is replaced). The rules, applied in order:
  1. No selected run: nothing happens.
  2. The selected run is in the snapshot and `Runs.runState(run) !== logsRunState`: the
     state moved, so call `openDefaultAttempt()` (B2). It re-targets once and records the
     new state. Because of that, the next snapshot with the same state is not a move.
     This rule fires whether or not an attempt is selected, and it overrides an attempt the
     user picked. A state change is why the pane should show the new failure.
  3. Otherwise, when `selectedAttempt` is null: `openDefaultAttempt()`, as today. This is
     the run that had no attempt when it was selected.
  4. Otherwise: fetch again only when
     `Runs.attemptStatus(run, sel.card_id, sel.phase, sel.attempt) !== logsStatus`, as today.
- If the selected run is absent from a snapshot (`runById` null), rule 2 does not fire.
  `logsRunState` is not changed, so the run reappearing in the same state is not a move.
  Rules 3 and 4 behave as today: B2 finds no target for a missing run, so it selects
  nothing. Rule 4's `attemptStatus` on a null run is `""`, which differs from a non-empty
  `logsStatus`, so it calls `fetchLogs()`; that returns early without launching (no run, so
  no project root) and leaves `logsStatus` unchanged.
- A failed snapshot (no root answered) does not reach `logsAfterSnapshot` (`applyProjects`
  returns before it, `:1021-1025`). Nothing re-targets.

Consequences that the tests pin:

- A selected run that goes running → escalated moves its pane to the failed attempt on the
  first snapshot that shows `escalated`, with exactly one logs launch. Later snapshots in
  `escalated` launch nothing more, unless rule 4's status rule fires.
- When the re-target lands on the triple already shown (for example running → dead, both
  naming explore 1), `selectAttempt` keeps the text and launches one fetch.
- Escalated → running (resumed elsewhere): the stop report is null, so the pane moves to
  `Runs.defaultAttempt` once.
- An attempt the user picked survives every snapshot that does not move the run's state.

### Comments (contract only, no narrative)

Update the doc comments of these to state the rules above:

- `selectAttempt`: "a number 0 or above; 0 is the phase's newest output, am's choice".
- `openDefaultAttempt`: the stop report's attempt, else `defaultAttempt`, and it records
  `logsRunState`.
- `logsAfterSnapshot`: the state-move rule before the existing two.
- `onSelectedRunIdChanged`.
- The new property: one line.

The comments don't mention this card, history or the design.

## Errors and edge cases

| case | behaviour |
|---|---|
| escalated run, failed agent phase | opens that phase's newest attempt (`stopReport.attempt`) |
| escalated run, failed step with `attempts: []` | opens `{card, step, 0}`; argv ends in `\|0` |
| escalated run naming only a synthetic node | `defaultAttempt` (report attempt null) |
| parked or cancelled run | `defaultAttempt` (report attempt null) |
| dead run | `stopReport.attempt` (the in-flight phase's newest, `0` when it has none) |
| running or done run | `defaultAttempt`, unchanged |
| neither a report attempt nor a default | nothing selected, no launch (as today) |
| `am logs` has no output for the step | the pane's existing `logsError` line (design, line 294); no store change |
| `selectAttempt(…, -1)`, `NaN`, `"1"`, `Infinity` | refused, no launch |
| state moves while the user views another attempt | re-targets to the run's opening attempt, once |
| selected run missing from one snapshot | no re-target; its return in the same state is no move |
| failed snapshot | nothing re-targets |

## Tests

Tier: all of these are QML store tests in `tests/core/stores/tst_run_store.qml`, run by
`qmltestrunner` through `bash tests/run.sh`. The behaviour under test is the store's state
(`selectedAttempt`, `logsText`, `logsRunState`) and the argv the store hands its logs
`HelperRunner`. The file already drives that argv against fake runners (`logsRunner.current`,
`logsRunner.seq`). The domain functions (`stopReport`, `defaultAttempt`) have their own
tests in `tests/core/domain/tst_runs.qml`. `runs-logs.py`'s handling of `0` has its
integration test in `tests/core/backend/runs/test_runs_logs.py` (card e69a6c2d). So no
other tier is needed. The design asks for "each group in its own block" (design, Testing,
lines 311-314).

Write the tests first. Every test below fails on today's store, except test 3, which pins
behaviour that must not change.

### Block

Add a new block headed `  // ---- stopped run opens its failed attempt (2.2)`, placed right
after the `// ---- attempt logs (5.2)` block and before `  // ---- run controls (S2 4.1)`
(today `:2712`). It reuses the file's helpers: `makeWithProject`, `reply`, `okReply`,
`treeEntry`, `snapshot`, `argv`, `logsReply`, `rec`, `tc.logsCmd`, `tc.openCard`,
`tc.doneCard` and `tc.rootA`. It adds these helpers inside the block, each with a one-line
contract comment, and labels each fixture edit `// synthetic:`, as the file does:

- `escCard`: `"10e26d57-374c-48d3-bc45-09389b42cfac"`, the escalated subtask of
  `status-escalated.json`.
- `escEntry(id)`: `rec("escalated")` with `id`, `repo_dir` and `project.repo_dir` set to the
  test's run id and `tc.rootA`, and with `status.run.id = id`. Its stop report names
  `escCard|review|1`.
- `stepEntry(id)`: `treeEntry(id, "ok")` with these edits:
  - `status.run.status = "escalated"`;
  - the open subtask's (`stories[1].subtasks[1]`, `tc.openCard`) explore phase status set to
    `"done"`;
  - a phase `{name: "verify", kind: "deterministic", status: "failed", detail: "VerifyError:
    2 tests failed", attempts: []}` pushed onto that subtask's phases.

  Its stop report names `openCard|verify|0`, while `Runs.defaultAttempt` would give
  `openCard|explore|1` (the last row).
- `openOn(entry)`: a store on `rootA` whose first snapshot lists `entry`, with `entry.id`
  selected. It returns the store.

### Cases

1. `test_an_escalated_run_opens_its_failed_attempt`: `escEntry("r1")` with one more row
   appended (`// synthetic:` a later ok row, `{attempt: 1, phase: "implement", state: "ok",
   story: <the subtask's story>, subtask: escCard}`). This makes `Runs.defaultAttempt` differ
   from the report. Assert all of these:
   - the test's own guard, `Runs.defaultAttempt(store.runById("r1")).phase === "implement"`,
     which proves the case discriminates;
   - after `openOn`, `argv(logsRunner.current) === tc.logsCmd + "r1|" + escCard + "|review|1"`;
   - `selectedAttempt` is `{escCard, "review", 1}`;
   - `logsRunState === "escalated"`.
2. `test_a_failed_step_opens_attempt_0`: `openOn(stepEntry("r1"))`. Assert:
   - the argv is `tc.logsCmd + "r1|" + tc.openCard + "|verify|0"`, so it ends in `|0`;
   - `selectedAttempt.attempt === 0`, `selectedAttempt.phase === "verify"`;
   - `logsStatus === ""`;
   - `logsLoading === true`.

   Then reply `logsReply("2 tests failed\n")`. `logsText === "2 tests failed"`, which shows
   the attempt-0 fetch's reply is applied like any other.
3. `test_a_running_run_still_opens_its_default_attempt`: `openOn(treeEntry("r1",
   "started"))`. Assert:
   - `Runs.stopReport(store.runById("r1")) === null`;
   - the argv is `tc.logsCmd + "r1|" + tc.openCard + "|explore|1"`;
   - `logsRunState === "running"`.
4. `test_a_parked_run_opens_its_default_attempt`: `treeEntry("r1", "started")` with
   `status.run.status = "stopped"` (`// synthetic:`). Assert:
   - `Runs.stopReport(run).attempt === null`;
   - the argv ends in `|explore|1`;
   - `logsRunState === "parked"`.
5. `test_select_attempt_accepts_0_and_refuses_the_rest`: `openOn(treeEntry("r1",
   "started"))`, reply to the first logs fetch, and record `seq`. Then:
   - `selectAttempt(tc.doneCard, "spec", 0)`: `seq + 1`, the argv ends in
     `|doneCard|spec|0`, `logsText === ""` (another triple), `selectedAttempt.attempt === 0`.
   - Each of `-1`, `NaN`, `Infinity`, `"1"`, `null` with `(tc.doneCard, "spec", …)`: `seq`
     unchanged, and `selectedAttempt` still `{doneCard, spec, 0}`.
6. Change the existing `test_no_logs_launch_without_a_run_or_a_selection` (attempt-logs
   block, today `:2489`). This is the only existing assertion that contradicts B1.
   - Replace `store.selectAttempt(tc.doneCard, "spec", 0)` with
     `store.selectAttempt(tc.doneCard, "spec", -1)`, so the "not a real attempt" line still
     holds.
   - Its other refusals stay. At that point, `r2` (an `entry(...)` with no tree) is
     selected. `selectAttempt(tc.doneCard, "spec", 0)` on that run would now launch, which
     is correct, and the test doesn't assert it.
7. `test_a_state_move_to_escalated_retargets_once`: `openOn(treeEntry("r1", "started"))`,
   reply `logsReply("a\n")`, record `seq`. Then:
   - `snapshot(store, [stepEntry("r1")])`:
     - `seq + 1`;
     - the argv ends in `|openCard|verify|0`;
     - `logsText === ""` (a new triple starts empty);
     - `logsRunState === "escalated"`.
   - `snapshot(store, [stepEntry("r1")])` again: `seq + 1` unchanged ("only once").
   - `snapshot(store, [treeEntry("r1", "started")])` (resumed): `seq + 2`, the argv ends in
     `|openCard|explore|1`, and `logsRunState === "running"`.
8. `test_a_picked_attempt_survives_snapshots_that_keep_the_state`:
   `openOn(treeEntry("r1", "started"))`, then `selectAttempt(tc.doneCard, "spec", 1)`, reply,
   and record `seq`. Then:
   - `snapshot(store, [treeEntry("r1", "started")])`: `seq` unchanged, and `selectedAttempt`
     is still `doneCard|spec|1`.
   - `snapshot(store, [stepEntry("r1")])`: the state moved, so it re-targets to
     `openCard|verify|0` with `seq + 1`.
9. `test_a_missing_run_is_not_a_state_move`: `openOn(treeEntry("r1", "started"))`, reply,
   then `selectAttempt(tc.doneCard, "spec", 1)` and reply. Then:
   - `snapshot(store, [])`: `selectedAttempt` is still `doneCard|spec|1`, and
     `logsRunState === "running"`.
   - `snapshot(store, [treeEntry("r1", "started")])`: `selectedAttempt` is still
     `doneCard|spec|1` and the current argv ends in `|doneCard|spec|1`, so there was no
     re-target. Don't assert `seq` here: it is not what this case pins (the missing-run
     snapshot launches nothing, since `fetchLogs()` finds no project root; the return
     snapshot may refetch the same attempt through rule 4).
10. `test_a_failed_snapshot_does_not_retarget`: `openOn(treeEntry("r1", "started"))`, reply,
    and record `seq`. Then `store.refresh()` and reply the HelperError envelope (as
    `test_a_snapshot_that_changes_the_attempt_status_fetches_once` does). Assert `seq`
    unchanged and `logsRunState === "running"`.
11. `test_selecting_a_run_absent_from_the_snapshot_targets_when_it_appears`:
    `makeWithProject(rootA)`, a first snapshot with no runs, then `selectedRunId = "r1"`.
    Assert `logsRunState === ""` and no logs launch. Then `snapshot(store,
    [stepEntry("r1")])`: the argv ends in `|openCard|verify|0`.

The existing attempt-logs tests (`:2393-2711`) must all still pass unchanged, except case 6's
one-line edit. `test_a_snapshot_that_changes_the_attempt_status_fetches_once` in particular
still holds: `treeEntry(...,"ok")` keeps run state `running`, so rule 4 alone decides.

Verification: `bash tests/run.sh` green. That includes `tests/architecture` (no duplicated
components, icon glyph rules), which this change doesn't affect because it touches no UI.

## Out of scope

- `core/domain/runs.js`: `stopReport`, `defaultAttempt`, `attemptStatus` (story 1, done).
- `core/backend/runs/runs-logs.py` (card e69a6c2d, done).
- The `Output · <card> verify (newest)` heading and the Why-it-stopped block (design,
  Behaviour, lines 124-163): the UI cards (`StopReasonBlock`, `RunDetailScreen`).
- The resume dialog, `lastControlErrorType`, relaunch (design, Architecture, lines 266-277):
  sibling store cards.
- `docs/architecture.md:90`, which names `openDefaultAttempt` and the logs triggers, belongs
  to the milestone's docs card. Nothing in this card edits docs.
- Renaming `openDefaultAttempt`, moving the logs section, or splitting the store (the
  later "Split RunStore" spec).
- Refetching an attempt-0 selection on snapshots. `logsStatus` stays `""` for it (B1).

## Constraints inherited

- Stores import only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain`, never another
  store (`RunStore.qml:1-4`; `docs/architecture.md` layering).
- The selection reads only the `am status` snapshot, never events (design, line 265).
- `stopReport` reads only the normalized run, never brd status (design, Architecture,
  lines 248-249).
- Comments state the contract only (card).
- `bash tests/run.sh` green (card). TDD: tests first (card).

## Notes for the planner

- One task is enough: the store change and its test block go together. Tests 1-11, then the
  four store edits (B1, B2, B3 and the property), then the case-6 edit. A reviewer could not
  reject B2 while accepting B3, because B3's rule 2 calls B2.
- Review Focus candidates (each already has a case above): a step's attempt 0 reaching the
  argv (2); re-target only once per state (7); a user-picked attempt kept (8); a missing run
  not counted as a move (9); a failed snapshot (10).
