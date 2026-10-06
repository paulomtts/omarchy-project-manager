# 3.3 RunStore: passes the project root to runs-logs.py — design

Card `27704601`, a subtask of story `44b929b5` ("Attempt output from real am
logs"), blocked by `f7473bf0` (3.2, `runs-logs.py --repo-dir`, landed as
`df512f0`). Parent spec:
`docs/superpowers/specs/2026-10-05-align-run-model-design.md` (below:
**parent**). Work breakdown item 3 (parent L327-328) lists "`logTail`,
`runs-logs.py --repo-dir`, `RunStore` passing the root, and a real-data flow
test": this subtask is "`RunStore` passing the root" only.

## Goal

Since 3.2, `runs-logs.py` takes exactly five arguments,
`<project_root> RUN CARD PHASE ATTEMPT`, and answers any other count with a
`Usage` envelope (exit 2). `RunStore.fetchLogs` still launches it with four
(`core/stores/RunStore.qml:370`; the card's `:330` is stale), so every logs
fetch from the panel is `Usage` on this branch, and was `UnknownRunError`
before 3.2 (parent L112). After this subtask the store sends the open
project's root first, so the helper passes it to am as `--repo-dir` and a
fetch resolves the run.

## Inherited constraints

| constraint | source |
|---|---|
| `am logs RUN CARD --phase P --attempt N --repo-dir R`; `--repo-dir` defaults to `.`; without it, from any other directory, am refuses with `UnknownRunError` | parent L55-60 |
| The defect: `RunStore.qml:330` (now `:370`) + `runs-logs.py:44-48` send no `--repo-dir`; every logs fetch is `UnknownRunError` | parent L112 |
| Decision 7: `runs-logs.py` takes the project root first and passes `--repo-dir` | parent L169-171 |
| Work item 3 splits into `logTail`, `runs-logs.py --repo-dir`, `RunStore` passing the root, a real-data flow test | parent L327-328 |
| `logsRunner.run` gets `[project, run, card, phase, String(attempt)]`; tests in `tests/core/stores/tst_run_store.qml` pin the argv | card |
| The helper's command line is `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` | `docs/architecture.md:199` (3.2) |
| `docs/architecture.md` layering; `tests/architecture` passes (no duplicated components, icon glyph rules) | card |
| Docstrings and comments state the contract only, no narrative | card |
| `bash tests/run.sh` green; tests first | card |

Model: the other runners already lead with the project root —
`snapshotRunner.run([store.project])` (`RunStore.qml:162`), the control and
dispatch runners (`:576`, `:1009`, `:1078`).

## Behavior

1. **The argv.** Every logs launch (`fetchLogs`, reached from selecting a run,
   `selectAttempt`, `refreshLogs`, and a snapshot that moves the selected
   attempt's status) runs the helper with exactly
   `[store.project, store.selectedRunId, sel.card_id, sel.phase, String(sel.attempt)]`
   after `python3 <backendDir>runs/runs-logs.py`: five arguments, project root
   first.
2. **The current project.** The root is the store's `project` at launch time.
   After a project switch, the next logs launch carries the new root; nothing
   launched for the old project is re-sent.
3. **Verbatim.** The root is one argv element, unchanged: a root containing a
   space (`/home/u/my proj`) is not split, quoted or normalised by the store.
4. **Unchanged.** Everything else about `fetchLogs` stays: no launch when
   `project`, `selectedRunId` or `selectedAttempt` is empty (the early return
   already guarantees a non-empty root); `logsStatus` and `logsLoading` set as
   today; the runner's launch guard is still the project; replies, latest-wins,
   project-switch clearing and late-reply dropping behave as today.

No production comment changes are required; if the `fetchLogs` comment is
touched it states the contract only ("One runs-logs.py launch for the current
project and selection, …").

## Tests

All QML, run by `qmltestrunner` via `bash tests/run.sh`, with `HelperRunner`
stubbed by `Process` objects whose `command` is inspected. Tier: QML store
unit (`tests/core/stores/`) for the argv contract, because the observable is
exactly the command list the store hands its runner and no helper or am runs;
QML UI flow (`tests/ui/`) for one pin, because the composed `App` wires the
project from `ProjectStore`, which the store test cannot see.

`tests/core/stores/tst_run_store.qml`:

- **`logsCmd` (L17)** becomes
  `"python3|/plugin/core/backend/runs/runs-logs.py|" + rootA + "|"`
  (`rootA = "/home/u/my proj"`, L15; the space is the not-split check, rule 3).
  Every existing pin built on it — L971, L983, L990, L1130, L1193, L1224 — runs
  under `rootA` (`opened()` / `makeWithProject(rootA)`), so each now asserts
  five arguments with the root first and fails against the current store
  (rule 1). No other edit to those tests.
- **New `test_logs_argv_leads_with_the_current_project_root`**: open `r1`
  under `rootA` (`opened()`); `argv(store.logsRunner.current)` equals
  `"python3|/plugin/core/backend/runs/runs-logs.py|/home/u/my proj|r1|" + openCard + "|explore|1"`
  and `logsRunner.current.command[2] === "/home/u/my proj"` (one element,
  rule 3); then `store.project = rootB`, reply to B's snapshot with
  `okReply([treeEntry("r1", "started")])`, `store.selectedRunId = "r1"`;
  the new launch's `command[2]` is `"/home/u/b"` and its argv is
  `"python3|/plugin/core/backend/runs/runs-logs.py|/home/u/b|r1|" + openCard + "|explore|1"`
  (rule 2). (Uses only helpers already in the file: `opened`, `reply`,
  `okReply`, `treeEntry`, `argv`.)

`tests/ui/tst_runs_flow.qml`:

- **L222** becomes
  `compare(proc.command.slice(2).join("|"), "/home/u/a|run-0000000000e5|t1|implement|2")`
  (`pA.root_path` is `/home/u/a`, L19). Fails against the current store.

Unchanged and still green: `tests/core/backend/runs/test_runs_logs.py`
(updated by 3.2), every other store and flow test, `tests/architecture` (no
new component, no icon).

Suite gate: `bash tests/run.sh` green.

## Out of scope

- `core/backend/runs/runs-logs.py` and its pytest (3.2, done).
- `logTail` / `runs.js` (3.1, done).
- The real-data flow test of the whole chain (`tests/ui/tst_runs_real_data.qml`
  and its fixtures): the story's later subtask (parent L327-328).
- `docs/architecture.md`: L199 already documents
  `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` and L94 lists no
  arguments; README and docs pass belong to work item 5 (parent L331).
- The stale "App composes the store only in 3.3" header comment in
  `tst_run_store.qml` (L4-5) — not part of this contract.
- Cancel spellings, watch schemas, `runs-snapshot.py`, `runs-watch.py`,
  `run-control.py` (work item 4); ATTEMPT `0` / deterministic-phase logs.
