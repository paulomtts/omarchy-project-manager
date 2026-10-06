# 3.3 RunStore: passes the project root to runs-logs.py — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `RunStore.fetchLogs` launches `runs-logs.py` with the open project's root as its first argument (`[project, run, card, phase, attempt]`), matching the helper's five-argument command line from 3.2, so a logs fetch from the panel resolves the run instead of failing with `Usage`.

**Architecture:** One production line changes: `core/stores/RunStore.qml:370`, `logsRunner.run([...])` gains `store.project` first, and the comment above `fetchLogs` (`:363-364`) says "for the current project and selection". Every logs launch (select a run, `selectAttempt`, `refreshLogs`, a snapshot that moves the attempt's status) goes through `fetchLogs`, so that one line covers all of them. Tests: `tests/core/stores/tst_run_store.qml`'s `logsCmd` prefix gains `rootA` (so the six existing argv pins now assert the root), three new store tests pin the root-first argv, the current-project rule across switches, and a verbatim odd root; `tests/ui/tst_runs_flow.qml:222` pins the composed panel's argv with `/home/u/a` first.

**Tech Stack:** QML (Qt 6, `QtQuick`, `QtTest`), run by `qmltestrunner` through `bash tests/run.sh [filter]`. `tests/run.sh` always runs the whole pytest suite first (falls back to `uv run --with pytest` when `python3` has no pytest), then every `tst_*.qml` whose path contains the filter, mirrored into a temp dir with `-import tests/stubs` (the `HelperRunner` there is real; `Process` is a stub whose `command` the tests read). A QML test failure prints `FAIL!  : ...` lines and a `Totals:` line with a non-zero failed count; the script exits 1.

**Spec:** `docs/superpowers/specs/3-3-runstore-passes-the-27704601.md` (prepended below, headings demoted one level; executors read both).

## Global Constraints

- The helper's command line is `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` (`docs/architecture.md:199`): exactly five arguments after the script.
- `logsRunner.run` gets exactly `[store.project, store.selectedRunId, sel.card_id, sel.phase, String(sel.attempt)]`; the full process command is `["python3", "<backendDir>runs/runs-logs.py", project, run, card, phase, attempt]` (7 elements).
- The root is `store.project` read at launch time, one argv element, unchanged: not split, quoted, trimmed or normalised.
- Unchanged: `fetchLogs`'s early return when `project`, `selectedRunId` or `selectedAttempt` is empty; `logsStatus` / `logsLoading`; `logsRunner`'s `guard: store.project`; replies, latest-wins, project-switch clearing, late-reply dropping.
- Not changed: `core/backend/runs/runs-logs.py`, `tests/core/backend/runs/test_runs_logs.py`, `core/domain/runs.js`, `docs/architecture.md`, `README.md`, the stale "App composes the store only in 3.3" header comment of `tst_run_store.qml` (L4-5), the fixtures, any other runner.
- Docstrings and comments state the contract only, no narrative. If the `fetchLogs` comment changes, it reads "One runs-logs.py launch for the current project and selection, …".
- `docs/architecture.md` layering holds and `tests/architecture` passes (no new component, no icon); `bash tests/run.sh` green at the end; tests first (red before green). Never `git stash`.

## Review Focus

1. **Refresh after a project switch:** a Refresh (or `selectAttempt`) under project B must carry B's root, never a root remembered from A's first launch. Pinned in Task 1 Step 1 (`test_every_logs_launch_after_a_switch_carries_the_new_root`, the `refreshLogs` and `selectAttempt` checks).
2. **A snapshot-driven refetch after a switch:** a status move (started → ok) seen in B's snapshot fetches with B's root. Pinned in Task 1 Step 1 (same test, the `snapshot(store, [treeEntry("r1", "ok")])` check).
3. **Switching back A → B → A:** the next launch under A carries A's root again (the root follows `project`, it is not "the first" or "the last other" one). Pinned in Task 1 Step 1 (same test, final block).
4. **A root with shell-significant characters and a trailing slash** (`/home/u/o'dd; $x/`): reaches the runner as one element, byte-for-byte, the command still 7 elements long. Pinned in Task 1 Step 1 (`test_logs_argv_keeps_an_odd_root_verbatim`).
5. **Nothing of A's is re-sent after a switch:** after the switch and B's snapshot no logs process is launched (the runner's current process is still A's, stopped) until a run is selected under B, and that launch is B's. Pinned in Task 1 Step 1 (`test_logs_argv_leads_with_the_current_project_root`, the `compare(store.logsRunner.current, procA, …)` check). Note: `HelperRunner.cancel()` also bumps `seq`, so `seq` deltas around a selection change are 2, not 1 — do not pin launches by `seq` there.

---

## Spec (prepended; headings demoted one level)

## 3.3 RunStore: passes the project root to runs-logs.py — design

Card `27704601`, a subtask of story `44b929b5` ("Attempt output from real am
logs"), blocked by `f7473bf0` (3.2, `runs-logs.py --repo-dir`, landed as
`df512f0`). Parent spec:
`docs/superpowers/specs/2026-10-05-align-run-model-design.md` (below:
**parent**). Work breakdown item 3 (parent L327-328) lists "`logTail`,
`runs-logs.py --repo-dir`, `RunStore` passing the root, and a real-data flow
test": this subtask is "`RunStore` passing the root" only.

### Goal

Since 3.2, `runs-logs.py` takes exactly five arguments,
`<project_root> RUN CARD PHASE ATTEMPT`, and answers any other count with a
`Usage` envelope (exit 2). `RunStore.fetchLogs` still launches it with four
(`core/stores/RunStore.qml:370`; the card's `:330` is stale), so every logs
fetch from the panel is `Usage` on this branch, and was `UnknownRunError`
before 3.2 (parent L112). After this subtask the store sends the open
project's root first, so the helper passes it to am as `--repo-dir` and a
fetch resolves the run.

### Inherited constraints

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

### Behavior

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

### Tests

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

### Out of scope

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

---

## File Structure

| file | change | responsibility |
|---|---|---|
| `core/stores/RunStore.qml` | modify `:363-370` (`fetchLogs` and its comment) | the logs launch's argv leads with `store.project` |
| `tests/core/stores/tst_run_store.qml` | modify `:17` (`logsCmd`); add three tests before `// ---- run controls (S2 4.1)` (`:1227`) | the store's argv contract |
| `tests/ui/tst_runs_flow.qml` | modify `:222` | the composed panel sends the selected project's root |

One task: the production line and its pins change together, and a reviewer could not approve the store change without the test that pins it, nor the reverse.

## Task 1: `RunStore.fetchLogs` passes the project root first

**Files:**
- Modify: `core/stores/RunStore.qml:363-370`
- Test: `tests/core/stores/tst_run_store.qml:17` and new tests inserted before line 1227 (`  // ---- run controls (S2 4.1)`)
- Test: `tests/ui/tst_runs_flow.qml:222`

**Interfaces:**
- Consumes: `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` (3.2, `df512f0`); `HelperRunner.run(args)` launches `["python3", script].concat(args)` with `launchGuard = guard`; test helpers already in `tst_run_store.qml`: `make()`, `makeWithProject(root)`, `reply(proc, text, code)`, `okReply(entries)`, `treeEntry(id, status)`, `logsReply(stdout, stderr)`, `argv(proc)` (joins `proc.command` with `|`), `opened(status)` (project `rootA`, r1 selected, its default attempt `openCard`/`explore`/`1` in flight), `snapshot(store, entries)` (refresh + ok reply); properties `rootA = "/home/u/my proj"`, `rootB = "/home/u/b"`, `openCard`, `doneCard`.
- Produces: nothing new for later tasks. The observable contract is `store.logsRunner.current.command` = `["python3", "/plugin/core/backend/runs/runs-logs.py", <project>, <run>, <card>, <phase>, <attempt>]`.

- [ ] **Step 1: Write the failing tests**

1a. In `tests/core/stores/tst_run_store.qml`, change line 17 from

```qml
  property string logsCmd: "python3|/plugin/core/backend/runs/runs-logs.py|"
```

to

```qml
  property string logsCmd: "python3|/plugin/core/backend/runs/runs-logs.py|" + rootA + "|"
```

This makes the six existing pins (`:971`, `:983`, `:990`, `:1130`, `:1193`, `:1224`, all under `rootA` via `opened()` / `makeWithProject(rootA)`) assert five arguments with the root first. Do not edit those tests.

1b. In the same file, insert these three tests immediately before the line `  // ---- run controls (S2 4.1)` (currently line 1227, right after the closing `}` of `test_a_run_opened_before_its_first_attempt_picks_one_when_it_appears`), with one blank line on either side:

```qml
  // The logs launch: python3, the script, then the project root and the
  // attempt, five arguments; the root is the current project's, one element.
  function test_logs_argv_leads_with_the_current_project_root() {
    var store = opened(); if (!store) return
    var procA = store.logsRunner.current
    compare(argv(procA), "python3|/plugin/core/backend/runs/runs-logs.py|/home/u/my proj|r1|" + tc.openCard + "|explore|1")
    compare(procA.command.length, 7, "five arguments after python3 and the script")
    compare(procA.command[2], "/home/u/my proj", "the root with a space is one argument")
    store.project = rootB
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started")]), 0)
    compare(store.logsRunner.current, procA, "nothing is launched after the switch until a run is selected")
    compare(procA.running, false, "A's fetch is stopped, not re-sent")
    store.selectedRunId = "r1"
    var procB = store.logsRunner.current
    verify(procB !== procA)
    compare(procB.command[2], "/home/u/b")
    compare(argv(procB), "python3|/plugin/core/backend/runs/runs-logs.py|/home/u/b|r1|" + tc.openCard + "|explore|1")
  }

  // Review Focus 1-3: Refresh, selectAttempt and a snapshot's refetch under B
  // carry B's root; back on A, A's root again.
  function test_every_logs_launch_after_a_switch_carries_the_new_root() {
    var bCmd = "python3|/plugin/core/backend/runs/runs-logs.py|/home/u/b|"
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("a\n"), 0)
    store.project = rootB
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started")]), 0)
    store.selectedRunId = "r1"
    reply(store.logsRunner.current, logsReply("b\n"), 0)
    store.refreshLogs()
    compare(argv(store.logsRunner.current), bCmd + "r1|" + tc.openCard + "|explore|1", "Refresh")
    store.selectAttempt(tc.doneCard, "spec", 1)
    compare(argv(store.logsRunner.current), bCmd + "r1|" + tc.doneCard + "|spec|1", "selectAttempt")
    store.selectAttempt(tc.openCard, "explore", 1)
    reply(store.logsRunner.current, logsReply("b\n"), 0)
    var seq = store.logsRunner.seq
    snapshot(store, [treeEntry("r1", "ok")])
    compare(store.logsRunner.seq, seq + 1, "started -> ok fetches again")
    compare(argv(store.logsRunner.current), bCmd + "r1|" + tc.openCard + "|explore|1", "the snapshot's refetch")
    store.project = rootA
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started")]), 0)
    store.selectedRunId = "r1"
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|" + tc.openCard + "|explore|1", "back on A")
  }

  // Review Focus 4: the root reaches the runner byte-for-byte.
  function test_logs_argv_keeps_an_odd_root_verbatim() {
    var odd = "/home/u/o'dd; $x/"
    var store = makeWithProject(odd); if (!store) return
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started")]), 0)
    store.selectedRunId = "r1"
    var proc = store.logsRunner.current
    verify(proc, "the default attempt's logs were asked for")
    compare(proc.command.length, 7)
    compare(proc.command[2], odd, "not split, quoted, trimmed or normalised")
    compare(proc.command[3], "r1")
  }
```

1c. In `tests/ui/tst_runs_flow.qml`, change line 222 from

```qml
    compare(proc.command.slice(2).join("|"), "run-0000000000e5|t1|implement|2")
```

to

```qml
    compare(proc.command.slice(2).join("|"), "/home/u/a|run-0000000000e5|t1|implement|2")
```

(`pA.root_path` is `/home/u/a`, line 19.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: pytest passes, then `== tests/core/stores/tst_run_store.qml` prints `FAIL!` lines for `test_selecting_a_run_fetches_its_default_attempt`, `test_select_attempt_and_refresh_launch_the_exact_argv`, `test_changing_the_selected_run_resets_to_its_default_attempt`, `test_a_snapshot_that_changes_the_attempt_status_fetches_once`, `test_a_run_opened_before_its_first_attempt_picks_one_when_it_appears`, `test_logs_argv_leads_with_the_current_project_root`, `test_every_logs_launch_after_a_switch_carries_the_new_root` and `test_logs_argv_keeps_an_odd_root_verbatim` — each an argv mismatch (actual has no root, e.g. `python3|/plugin/core/backend/runs/runs-logs.py|r1|…`) or `command.length` 6 vs 7. No `TypeError` / `ReferenceError` lines (those would mean a typo in the new tests, not the missing root). Exit 1.

Run: `bash tests/run.sh tst_runs_flow`
Expected: `FAIL!  : RunsFlow::test_opening_a_run_shows_it_and_fetches_its_default_attempt()` with actual `run-0000000000e5|t1|implement|2`, expected `/home/u/a|run-0000000000e5|t1|implement|2`. Exit 1.

- [ ] **Step 3: Write the minimal implementation**

In `core/stores/RunStore.qml`, replace lines 363-371:

```qml
  // One runs-logs.py launch for the current selection, remembering the status
  // it was launched for (a snapshot that changes it fetches again).
  function fetchLogs() {
    var sel = store.selectedAttempt
    if (store.project === "" || store.selectedRunId === "" || !sel) return
    store.logsStatus = Runs.attemptStatus(store.runById(store.selectedRunId), sel.card_id, sel.phase, sel.attempt)
    store.logsLoading = true
    logsRunner.run([store.selectedRunId, sel.card_id, sel.phase, String(sel.attempt)])
  }
```

with

```qml
  // One runs-logs.py launch for the current project and selection, the
  // project root first, remembering the status it was launched for (a
  // snapshot that changes it fetches again).
  function fetchLogs() {
    var sel = store.selectedAttempt
    if (store.project === "" || store.selectedRunId === "" || !sel) return
    store.logsStatus = Runs.attemptStatus(store.runById(store.selectedRunId), sel.card_id, sel.phase, sel.attempt)
    store.logsLoading = true
    logsRunner.run([store.project, store.selectedRunId, sel.card_id, sel.phase, String(sel.attempt)])
  }
```

Nothing else in the file changes (not the `logsRunner` block at `:1163-1172`, not the header comment).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: `Totals: N passed, 0 failed, …` for `tst_run_store.qml`, no `TypeError`/`ReferenceError` lines, exit 0.

Run: `bash tests/run.sh tst_runs_flow`
Expected: `Totals: … 0 failed …` for `tests/ui/tst_runs_flow.qml`, exit 0.

- [ ] **Step 5: Run the whole suite**

Run: `bash tests/run.sh`
Expected: pytest all pass (including `tests/core/backend/runs/test_runs_logs.py` and `tests/architecture`), every `tst_*.qml` prints `Totals: … 0 failed …`, no `TypeError`/`ReferenceError`/`non-existent` lines, exit 0.

Also confirm the diff touches only the three files:

Run: `git status --short`
Expected: ` M core/stores/RunStore.qml`, ` M tests/core/stores/tst_run_store.qml`, ` M tests/ui/tst_runs_flow.qml` (plus the untracked spec/plan docs, which are not yours to commit).

- [ ] **Step 6: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml tests/ui/tst_runs_flow.qml
git commit -m "feat(runs): RunStore passes the project root to runs-logs.py"
```

---

## Self-Review

1. **Spec coverage.** Behavior 1 (argv, every launch path): Step 3's one line in `fetchLogs`, pinned by the six existing pins via `logsCmd` (select a run, `selectAttempt`, `refreshLogs`, run change, snapshot refetch, first-attempt pick) and the new `test_logs_argv_leads_with_the_current_project_root`. Behavior 2 (current project): the new test's B half and `test_every_logs_launch_after_a_switch_carries_the_new_root`. Behavior 3 (verbatim): `rootA`'s space (`command[2]` check) and `test_logs_argv_keeps_an_odd_root_verbatim`. Behavior 4 (unchanged): the early return, `logsStatus`, `logsLoading` and the runner are untouched by Step 3; the existing tests for them (`test_no_logs_launch_without_project_run_or_selection`, `test_a_project_switch_clears_the_logs_and_drops_the_late_reply`, …) run in Step 4/5. Spec's `tests/ui/tst_runs_flow.qml:222` pin: Step 1c. Suite gate: Step 5. Out-of-scope files: listed under Global Constraints as not changed; Step 5's `git status` checks it.
2. **Placeholders.** None: every code step carries the full text; every run step names the command and the expected output.
3. **Type consistency.** `logsCmd`, `rootA`, `rootB`, `openCard`, `doneCard`, `opened`, `makeWithProject`, `reply`, `okReply`, `treeEntry`, `logsReply`, `snapshot`, `argv`, `logsRunner.seq` (bumped by both `run` and `cancel`, `core/stores/HelperRunner.qml:24,33`), `logsRunner.current.command` all exist in the current files with these names (checked against `tst_run_store.qml:15-60`, `:923-955`, `:1175-1180`). The command is 7 elements in every check.
4. **Review Focus.** Five lines, each pinned by a named test in Step 1b.
<!-- task-pipeline: validated -->
