# 3.2 RunOutputStore: follow one live attempt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new store, `core/stores/RunOutputStore.qml`, runs `runs-logs-follow.py` for the one attempt or step Run detail shows while it is in flight, folds its stdout into a bounded live buffer, and is composed by `App` next to `RunStore`.

**Architecture:** One `Scope` store with five inputs (`backendDir`, `active`, `inRunDetail`, `run`, `selection`) and a single synchronous `reconcile()` run on every input change. The store compares a *selection key* `{run_id, card_id, phase, attempt}`, never run objects. It owns one follow `Process` at a time, built from a `Component` like `RunStore`'s watch: a `launchSeq` guard, a `SplitParser` whose every line goes through one `LogStream.foldLine`, and `running = false` to stop it. `App` binds the inputs and routes `snapshotWanted()` to `RunStore.refreshLogs()`.

**Tech Stack:** QML (Qt 6, Quickshell), the pure JS domain modules `core/domain/logStream.js` and `core/domain/runs.js`, QtTest through `tests/run.sh` (qmltestrunner, offscreen, stubbed `Quickshell.Io`).

**Spec:** `docs/superpowers/specs/3-2-runoutputstore-354d3953.md` (reproduced in full below)

---

## Spec

## 3.2 RunOutputStore: follow one live attempt — spec

Card `354d3953-88ac-4a11-9f9d-c621c3e78995`, subtask of story `053768a8-6bfd-4141-8c91-918e98ea4cf5`
(Live output store). Parent design: `docs/superpowers/specs/2026-10-05-live-output-design.md`
(below: **LO**). Builds on 3.1 (`RunStore` selects a step: `selectedAttempt` may be
`{card_id, phase, attempt: 0, step: true}`; `Runs.phaseStatus`; spec
`docs/superpowers/specs/3-1-runstore-selecting-52fec98e.md`). Followed by sibling 3.3
(`2bce8772-…`, "RunOutputStore: recovering a broken follow").

### Purpose

A new store, `core/stores/RunOutputStore.qml`, runs `runs-logs-follow.py` for the one attempt
(agent or step) that Run detail shows while that attempt is in flight, and folds its stdout into
a bounded live buffer. `App` composes it next to `RunStore` and wires it by properties and one
signal. This card delivers start, stop, latest-wins and the end line. Resuming, retries, the
fallback sentences and the error-type mapping are 3.3's.

### Starting point

- Nothing named `RunOutputStore` exists. `docs/architecture.md:201` says `runs-logs-follow.py` is
  run by no store yet.
- `core/domain/logStream.js`: `emptyBuffer(maxLines)`, `foldLine(buffer, line)` →
  `{buffer, kind}` with kind `hello | chunk | end | refusal | ignored` (`line` is a parsed
  value; a non-object is `ignored`), `bufferText(buffer)`. Pure, never throws, never mutates.
- `core/domain/runs.js`: `isLiveSelection(run, sel)` (running run, and the attempt started, or
  with `step: true` the phase started), `errorText(error)`.
- `core/backend/runs/runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT [OFFSET]`: ATTEMPT `0`
  omits `--attempt`; no OFFSET omits `--since-offset`. One JSON object per stdout line; exits 0
  on every path but `Usage`; SIGTERM stops am and exits 0 silently (`docs/architecture.md:201`).
- `core/stores/RunStore.qml`: `selectedAttempt` (`:116`), `selectedRunId`, `runById(id)`
  (`:779`), `refreshLogs()` (`:823`). Its watch (`startWatch`/`stopWatch` `:425-452`,
  `watchLine` `:507`, `watchExited` `:644`, `Component watchC` `:2281-2296`) is the one-`Process`
  pattern to copy: a `Component` holding a `Process` with `stdout: SplitParser { onRead }`,
  `stderr: StdioCollector { waitForEnd: true }`, `onExited` calling the store then `destroy()`,
  created with a `launchSeq`, stopped with `running = false` and a seq bump.
  `HelperRunner.qml` is not usable: it collects the whole stdout.
- `core/stores/NavigationStore.qml:9`: `viewMode`, `"run"` is Run detail. `App.panelOpen` is the
  panel being open.
- Test stubs `tests/stubs/Quickshell/Io/Process.qml` (`command`, `running`, `stdout`, `stderr`,
  `signal exited(int)`; no real process) and `SplitParser.qml` (`signal read(string)`).
- Recorded streams: `tests/fixtures/am/logs-follow-agent.jsonl` (hello, one chunk
  `"stub claude ok phase=review\n"`, `{"event":"end","status":"ok"}`),
  `logs-follow-step.jsonl` (hello, chunk `"==> verify-ok (exit 0)\nverified\n"`, end `ok`),
  `logs-follow-refusal.json`. `status-started.json`: run `20261008T143823Z-e795ad19`, running
  with a live lease; open subtask `2280a6ab-9c40-434b-9729-63fd1f373754` with `worktree` (step,
  `done`) then `explore` attempt 1 `started`; `runs.json`'s first row gives its `repo_dir`
  `/home/user/Code/omarchy-project-manager`.

### Inherited constraints

| constraint | source |
|---|---|
| Store imports QtQml, Quickshell, Quickshell.Io, `../domain/logStream.js`, `../domain/runs.js`; owns the one follow process and nothing else; snapshot logs stay in `RunStore`. | LO lines 157-160; `docs/architecture.md` Layers table |
| App hands it `backendDir`, `active` (panel open), Run-detail flag (view mode `run`), `run` (the selected run, normalized), `selection` (`RunStore.selectedAttempt`) and routes `snapshotWanted()` to `RunStore.refreshLogs()`. No store reaches another. | LO lines 161-163; card description |
| State `followKey` (`{run_id, card_id, phase, attempt}` or null), `followStatus` (`idle | connecting | following | ended | unsupported | error`), `endStatus` (am's `S`, `""` until the end), `liveText` (`bufferText`), `liveDropped`, `hasOutput`, `followError`. | LO lines 165-168; card |
| A plain `Process` with a `SplitParser`, like the watch: one line, one `foldLine`. | LO lines 168-169 |
| Start: while `active` and on Run detail and `Runs.isLiveSelection(run, selection)`, follow that selection from offset 0 with `run.repo_dir`. A different selection stops the current process first (latest wins). At most one process. | LO lines 171-173 |
| Stop: a selection that is not live, leaving Run detail, another run, or the panel closing stops the process (SIGTERM through `running = false`). A stop because of the panel or Run detail keeps the buffer and the key; anything else clears them. | LO lines 174-176 |
| End: the end line sets `ended` and `endStatus`. Agent: the buffer stays. Step: `snapshotWanted()` once. | LO lines 182-184 |
| Two attempts selected quickly: the older process is stopped; its late lines are dropped. | LO line 227 |
| Argv `REPO RUN CARD PHASE ATTEMPT [OFFSET]`; attempt `0` for a step. | LO lines 114-116, 105-106 |
| One followed attempt at a time, panel-wide; no background tails. | LO line 91 |
| `tests/architecture` passes; docstrings and comments state the contract only; `bash tests/run.sh` green; TDD. | card description; `docs/architecture.md` |

### Deviation from the card's wording

The card names the Run-detail input `onRunDetail`. A QML property whose name is `on` followed by
an upper-case letter cannot be assigned in an object declaration (`onRunDetail: …` is parsed as a
handler for a signal `runDetail`). The property is therefore **`inRunDetail`** (bool, default
`false`); the meaning is unchanged.

### Behaviour

**Terms.**
- The *selection key* of `(run, selection)`: `null` when `run` or `selection` is not an object,
  `run.id` is not a non-empty string, or `selection.card_id` / `selection.phase` is not a
  non-empty string; otherwise `{run_id: run.id, card_id, phase, attempt}` where `attempt` is `0`
  when `selection.step === true`, else `selection.attempt`. Two keys are *equal* when all four
  fields are `===`.
- *Live* means `Runs.isLiveSelection(run, selection)`.
- *Present* means `active && inRunDetail`.
- *Clear* sets `followKey` null, `followStatus "idle"`, `endStatus ""`, `followError ""`, the
  buffer to `LogStream.emptyBuffer()`, and the derived `liveText ""`, `liveDropped 0`,
  `hasOutput false`.

#### B1. Inputs and state

`property string backendDir`, `property bool active`, `property bool inRunDetail`,
`property var run` (null), `property var selection` (null). State properties as in the
constraint table, plain properties only the store writes (as in `RunStore`): `followKey: null`, `followStatus: "idle"`, `endStatus: ""`,
`liveText: ""`, `liveDropped: 0`, `hasOutput: false`, `followError: ""`. `followProc`: the
current follow `Process` or null (exposed for tests and for "at most one"). `signal
snapshotWanted()`.

`liveText` is `LogStream.bufferText(buffer)`, `liveDropped` is `buffer.dropped`, `hasOutput` is
`buffer.lines.length > 0 || buffer.partial !== "" || buffer.dropped > 0`; all three are updated
whenever the buffer is replaced.

#### B2. Reconcile

Every change of `active`, `inRunDetail`, `run` or `selection` runs one synchronous reconcile
(a new `run` object with the same id and the same attempt status, as every snapshot gives, must
not restart anything):

1. Compute the selection key `k`.
2. **Key changed** (`k` not equal to `followKey`, including either being null): stop the current
   process if any (B4), *clear*; then, if `k` is not null, *present*, *live*, and `run.repo_dir`
   is a non-empty string, start (B3).
3. **Same key, not present**: stop the current process if any; keep `followKey`, the buffer,
   `followStatus`, `endStatus` and `followError` as they are.
4. **Same key, present, a process running**: nothing (a key that stopped being live keeps its
   process; am's end line or the helper's exit ends it).
5. **Same key, present, no process**:
   - `followStatus` is `ended`, `error` or `unsupported`: nothing (an ended attempt keeps its
     buffer until another key).
   - otherwise (`idle`, `connecting`, `following`, i.e. after a step-3 stop): if *live* and
     `repo_dir` usable, start (B3) from offset 0 with a fresh buffer; if not live, *clear*.
     (3.3 replaces this with a resume from `nextOffset` that keeps the buffer.)

#### B3. Start

Bumps the launch sequence, sets `followKey` to `k`, the buffer to `emptyBuffer()` (derived
properties updated), `followStatus "connecting"`, `endStatus ""`, `followError ""`; creates one
`Process` carrying the new `launchSeq` with command

```
["python3", backendDir + "runs/runs-logs-follow.py", run.repo_dir, run.id, card_id, phase, String(attempt)]
```

(seven elements, no OFFSET), sets `followProc` to it and `running = true`.

#### B4. Stop

Bumps the launch sequence, sets the current process's `running = false` (SIGTERM), sets
`followProc` null. The stopped process's later lines and exit are ignored; its `onExited` still
destroys it.

#### B5. A line

`SplitParser` delivers one line; a line from a process whose `launchSeq` is not the current one
is ignored (latest wins). Otherwise, when `followStatus` is `ended` or `error`, the line is
ignored. Else the line is trimmed and `JSON.parse`d (a blank or unparseable line is passed to
`foldLine` as `null`, which is `ignored`), then exactly one `foldLine(buffer, value)`:

- `hello`: `followStatus "following"`; buffer replaced.
- `chunk`: buffer replaced (derived properties updated); `followStatus "following"`.
- `end`: `followStatus "ended"`, `endStatus` = `value.status` when a string, else `""`. When
  `followKey.attempt === 0` (a step) `snapshotWanted()` is emitted, once per followed key. The
  buffer is kept.
- `refusal` (any `{"ok": false, …}` line: am's refusal or the helper's own error):
  `followStatus "error"`, `followError = Runs.errorText(value)`. The buffer is kept. (3.3 maps
  `FollowUnsupported`, `SchemaMismatch`, `AmMissing`, `StreamError` and a step's
  `UnknownAttemptError` to their own outcomes.)
- `ignored`: nothing.

#### B6. Exit

An exit from a process that is not the current one is ignored. For the current one:
`followProc` becomes null; then when `followStatus` is `ended` or `error` nothing else changes;
otherwise (`connecting` or `following`, an exit with no end line and no error line)
`followStatus "error"` and `followError` `"Live output stopped: the helper exited with code N"`
(N the exit code). The process is destroyed after the store has seen the exit. (3.3 replaces this
branch with the 1 s / 2 s / 4 s retries.)

#### B7. App wiring (`core/stores/App.qml`)

Composed directly after `runs`:

```
readonly property RunOutputStore runOutput: RunOutputStore {
  backendDir: app.backendDir
  active: app.panelOpen
  inRunDetail: app.nav.viewMode === "run"
  run: app.runs.runById(app.runs.selectedRunId)
  selection: app.runs.selectedAttempt
  onSnapshotWanted: app.runs.refreshLogs()
}
```

with a contract comment in the style of the `runs` block (the store never imports RunStore; App
hands it the selected run, the selection and the two presence flags, and routes its snapshot
request to `refreshLogs`). `RunStore.qml` is not changed.

#### B8. Docs

`docs/architecture.md`: a `RunOutputStore.qml` bullet in the Stores list after `RunStore.qml`
stating B1-B7's contract in one paragraph, and the backend paragraph's "no store runs it yet"
(`:201`) becomes "`RunOutputStore` runs it as a plain `Process`".

### Out of scope

- Resume with `--since-offset nextOffset` after the panel or Run detail, the unexpected-exit
  retries (1 s, 2 s, 4 s; the fourth within 60 s), `reconnects`, the fallback sentences and
  `unsupported`, `AmMissing` handling, a step's `UnknownAttemptError` → `ended` with
  `This step records no output`: sibling 3.3 (LO lines 177-181, 185-190).
- Any UI: the output pane's live labels, `TailScroll`, the end line, `Jump ↓`
  (LO lines 192-212; a later story). `RunDetailScreen.qml` is not edited.
- `RunStore.qml`, `runs.js`, `logStream.js`, every backend file (3.1, 2.x, 1.x; done).
- Following the run's next attempt automatically (LO line 255-256: not in this milestone).

### Tests

Tier: QML store tests (`qmltestrunner`, `tests/core/stores/`), the only tier where a store's
state and the argv of a stubbed `Process` are observable. Lines are driven with
`proc.stdout.read(text)` and exits with `proc.exited(code)` on the stub. Runs are
`Runs.normalizeRun` of `status-started.json` built like `tst_runs.qml`'s `amRun`; a live step is
the same capture with `explore` finished and a `verify` phase `started` (synthetic, marked
`// synthetic:`, like `tst_runs.qml`'s `startedStepRaw`). Stream lines are the raw non-empty
lines of the recorded `logs-follow-*.jsonl` (a local reader like `tst_log_stream.qml`'s
`jsonLines`, returning strings). `argv(proc)` joins `command` with `|`.

`tests/core/stores/tst_run_output_store.qml` (new):

| # | test |
|---|---|
| T1 | Defaults: `followKey null`, `followStatus "idle"`, `endStatus ""`, `liveText ""`, `liveDropped 0`, `hasOutput false`, `followError ""`, `followProc null`. |
| T2 | Start on a live agent attempt: `active`, `inRunDetail`, the started run, selection `{openCard, "explore", 1}` → one process, `running true`, argv `python3|/plugin/core/backend/runs/runs-logs-follow.py|/home/user/Code/omarchy-project-manager|20261008T143823Z-e795ad19|<openCard>|explore|1` (seven elements); `followKey` deep-equals `{run_id, card_id, phase: "explore", attempt: 1}`; `followStatus "connecting"`. |
| T3 | Start on a live step: selection `{openCard, "verify", 0, step: true}` on the synthetic run → argv ends `|verify|0`; `followKey.attempt === 0`. |
| T4 | No start: each of not active, not in Run detail, a non-live selection (`worktree` step `done`; the `doneCard` `spec` attempt), selection null, run null, a run with an empty `repo_dir` (synthetic) → `followProc null`, `followStatus "idle"`. |
| T5 | Lines: the agent stream's hello → `following`, `hasOutput false`; its chunk → `liveText "stub claude ok phase=review"`, `hasOutput true`, `liveDropped 0`; a blank line and `not json` change nothing. |
| T6 | Stop on leaving Run detail and on the panel closing (each its own case): after a chunk, `inRunDetail = false` (resp. `active = false`) → the old process `running false`, `followProc null`, `followKey`, `liveText` and `followStatus` unchanged. Coming back on the same live key → exactly one new process, argv as T2 (no OFFSET), `followStatus "connecting"`. |
| T7 | Stop on a non-live selection: following explore.1, selection changes to the `worktree` step (done) → old process `running false`, cleared (`followKey null`, `liveText ""`, `idle`), no new process. |
| T8 | Stop on another run: following, `run` becomes another running run (synthetic id) with selection null → cleared; `run` null → cleared. |
| T9 | Latest wins: following explore.1 (process A), the selection changes to the live `verify` step (synthetic run where both are started) → A `running false`, process B the current one; `A.stdout.read(chunk)` and `A.exited(0)` change nothing; B's lines fold. |
| T10 | At most one process: across T9's sequence plus a leave/return, the number of created follow processes whose `running` is true is never above 1. The test collects every process the store ever held by recording `followProc` in an `onFollowProcChanged` handler (no test-only hook is added to the store); the created `Process` carries `objectName: "followProc"`. |
| T11 | A new snapshot object for the same key does not restart: assigning a fresh `Runs.normalizeRun` of the same capture to `run` keeps the same `followProc` and `liveText`. |
| T12 | End for an agent: the agent stream's three lines → `followStatus "ended"`, `endStatus "ok"`, `liveText` kept, `snapshotWanted` count 0; the following `exited(0)` changes nothing; a later line is ignored. A new run object where explore.1 is `ok` (synthetic) keeps the ended state and starts nothing. |
| T13 | End for a step: the step stream → `ended`, `endStatus "ok"`, `snapshotWanted` count exactly 1, also after a second end line and an exit. |
| T14 | End with a non-string status (synthetic `{"event":"end"}`) → `ended`, `endStatus ""`. |
| T15 | An error line: `logs-follow-refusal.json`'s envelope → `followStatus "error"`, `followError` equals `Runs.errorText` of it, buffer kept; the exit after it changes nothing. |
| T16 | An exit with no end line: after a chunk, `exited(0)` → `followStatus "error"`, `followError "Live output stopped: the helper exited with code 0"`, `followProc null`, `liveText` kept. |

`tests/core/stores/tst_app_runs.qml` (wiring only; behaviour stays in the store test):

| # | test |
|---|---|
| A1 | `app.runOutput` exists; `backendDir` follows `app.backendDir`; `active` follows `app.panelOpen`; `inRunDetail` is true exactly when `app.nav.viewMode === "run"`. |
| A2 | `run` is `app.runs.runById(app.runs.selectedRunId)` and re-evaluates when `runs` changes (a snapshot reply) and when `selectedRunId` changes; `selection` follows `app.runs.selectedAttempt`. |
| A3 | `snapshotWanted()` calls `app.runs.refreshLogs()`: with a step selected and its logs runner idle, emitting it launches one `runs-logs.py` fetch. |
| A4 | End to end: panel open, view mode `run`, the started run selected, its default attempt (explore.1) selected → `app.runOutput.followProc` runs with the T2 argv; closing the panel stops it. |

All existing tests, `tests/architecture` and `bash tests/run.sh` stay green.

### Review focus (for the planner)

1. Binding order in App: `run` and `selection` update in separate notifications; a transient
   `(new run, old selection)` must not leave two processes (latest wins; T9/T10).
2. Every snapshot hands a new `run` object: comparing keys, not objects, prevents a restart per
   snapshot (T11).
3. A followed key that stops being live while its process runs keeps the process so the end line
   lands (B2 step 4); after the end, the ended state survives later snapshots (T12).
4. The end for a step emits `snapshotWanted()` once even when am repeats lines or the exit
   follows (T13).
5. The stub `Process` never emits `exited` by itself; a stopped process's late `exited` must not
   null out or overwrite the current one (T9).

---

## Global Constraints

- Store imports exactly: `QtQml`, `Quickshell`, `Quickshell.Io`, `"../domain/logStream.js" as LogStream`, `"../domain/runs.js" as Runs`. `tests/architecture/test_layers.py` (`violations_store`) enforces it.
- The store owns the one follow process and nothing else. Snapshot logs stay in `RunStore`. No store reaches another: `App` wires them.
- The Run-detail input is named **`inRunDetail`** (bool, default `false`), not `onRunDetail` (spec, "Deviation from the card's wording").
- State names and defaults are exact: `followKey: null`, `followStatus: "idle"` (`idle | connecting | following | ended | unsupported | error`), `endStatus: ""`, `liveText: ""`, `liveDropped: 0`, `hasOutput: false`, `followError: ""`, `followProc: null`, and `signal snapshotWanted()`.
- Argv is exactly `["python3", backendDir + "runs/runs-logs-follow.py", run.repo_dir, run.id, card_id, phase, String(attempt)]`: seven elements, no OFFSET, attempt `0` for a step.
- At most one follow process, panel-wide. No background tails.
- The exit sentence is exactly `"Live output stopped: the helper exited with code N"`.
- `RunStore.qml`, `runs.js`, `logStream.js`, every backend file and `RunDetailScreen.qml` are not edited.
- Docstrings and comments state the contract only, not the history. TDD: RED before GREEN. `bash tests/run.sh` must be green at the end.
- Never use `pkill`/`killall`/pattern `kill`. Wrap long test runs in `timeout`, e.g. `timeout 900 bash tests/run.sh`.

## Review Focus

These are five inputs or conditions the spec implies but its T/A tables do not exercise. Each has a test in the task that owns the code:

1. **An equal selection object.** `RunStore.selectAttempt` assigns a new `selectedAttempt` object even when it re-selects the attempt already shown. A reasonable person expects the live text to stay, with no restart. Test: `test_an_equal_selection_object_does_not_restart` (Task 2).
2. **A snapshot says the attempt finished before its end line arrives.** The process must stay so the end line lands, and the end must still be recorded. Test: `test_a_key_that_stops_being_live_keeps_its_process` (Task 2).
3. **Leaving and returning after the follow ended or failed.** Closing the panel, or leaving Run detail, and coming back must not restart an ended or failed follow or erase its text. Test: `test_an_ended_or_failed_follow_survives_leave_and_return` (Task 3).
4. **App's transient `(new run, old selection)`, where the old selection is live in the new run too.** The old process stops, at most one runs, and the old process's late lines never fold. Test: `test_a_new_run_with_the_old_selection_then_its_own` (Task 2).
5. **Malformed inputs.** Examples: a run that is a string, an array, or has an empty or non-string id; a selection with an empty card id, a non-string phase, or a string attempt. These must start nothing and throw nothing (`tests/run.sh` fails on any `TypeError`). Test: `test_malformed_inputs_start_nothing` (Task 1).

---

## File Structure

- Create `core/stores/RunOutputStore.qml`: the store. It holds the inputs, the state, the selection key, `reconcile`, start and stop, the line fold, the exit, and the follow `Process` `Component`.
- Create `tests/core/stores/tst_run_output_store.qml`: the store's behaviour (T1-T16 and Review Focus 1-5).
- Modify `core/stores/App.qml`: compose `runOutput` directly after `runs` (B7).
- Modify `tests/core/stores/tst_app_runs.qml`: wiring tests A1-A4.
- Modify `docs/architecture.md`: a `RunOutputStore.qml` bullet after `RunStore.qml`'s block (after the line that starts `  Dispatch (S3 3.1)`), and line 201's "no store runs it yet" (B8).

Facts the tests rely on, all checked against the repo:
- `status-started.json`'s run is `20261008T143823Z-e795ad19`. `runs.json`'s first row (same id) has `repo_dir` `/home/user/Code/omarchy-project-manager`. `normalizeRun` takes `repo_dir` from the row, else from `status.run`.
- Open subtask `2280a6ab-9c40-434b-9729-63fd1f373754`: `phases[0]` is `worktree` (deterministic, `done`) and `phases[1]` is `explore` (`started`, attempt `n: 1` `started`). In the raw status it is `stories[1].subtasks[1]`.
- Done subtask `5560d0fe-2b8e-4ef9-ad71-96b50ee89daa`: `spec` attempt 1 is `ok`.
- `logs-follow-agent.jsonl` folds to `"stub claude ok phase=review"` and `logs-follow-step.jsonl` folds to `"==> verify-ok (exit 0)\nverified"`. Both end with `{"event":"end","status":"ok"}`.
- The stub `Process` (`tests/stubs/Quickshell/Io/Process.qml`) never runs anything and never emits `exited` by itself. Tests call `proc.stdout.read(line)` and `proc.exited(code)`. A `Process` without a `stdout:` binding has `stdout === null`.
- `RunStore` with a started step selects `{card_id, phase: "verify", attempt: 0, step: true}` by default (3.1). Without one, it selects explore.1.

---

### Task 1: The store starts and stops on the selection key

**Files:**
- Create: `core/stores/RunOutputStore.qml`
- Test: `tests/core/stores/tst_run_output_store.qml` (create)

**Interfaces:**
- Consumes: `LogStream.emptyBuffer()`, `LogStream.bufferText(buffer)` (`core/domain/logStream.js`); `Runs.isLiveSelection(run, sel)`, `Runs.normalizeRun(raw)` (`core/domain/runs.js`).
- Produces (later tasks rely on these exact names):
  - inputs `backendDir: string`, `active: bool`, `inRunDetail: bool`, `run: var`, `selection: var`
  - state `followKey`, `followStatus`, `endStatus`, `liveText`, `liveDropped`, `hasOutput`, `followError`, `followProc`, `followSeq: int`, `buffer: var`
  - `signal snapshotWanted()`
  - functions `isObject(v)`, `selectionKey(run, sel)`, `sameKey(a, b)`, `isPresent()`, `isLive()`, `canStart(k)`, `setBuffer(b)`, `clear()`, `reconcile()`, `start(k)`, `stop()`
  - `Component { id: followC; Process { id: fp; objectName: "followProc"; property int launchSeq } }`

- [ ] **Step 1: Write the failing tests**

Create `tests/core/stores/tst_run_output_store.qml`:

```qml
// tests/core/stores/tst_run_output_store.qml
// Run detail's live output store: when runs-logs-follow.py starts and stops
// for the selected attempt or step, its exact argv, how its stdout lines fold
// into the live buffer, the end line, an error line, an exit with no end, and
// latest wins. Built directly and driven through stubbed Process objects.
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs
import "../../helpers/amFixtures.js" as F

TestCase {
  id: tc
  name: "StoresRunOutputStore"

  // status-started.json: its run, its repo_dir (runs.json's first row), its
  // open subtask (worktree step done, explore attempt 1 started) and a done
  // subtask (spec attempt 1 ok).
  readonly property string runId: "20261008T143823Z-e795ad19"
  readonly property string repo: "/home/user/Code/omarchy-project-manager"
  readonly property string openCard: "2280a6ab-9c40-434b-9729-63fd1f373754"
  readonly property string doneCard: "5560d0fe-2b8e-4ef9-ad71-96b50ee89daa"
  readonly property string followCmd: "python3|/plugin/core/backend/runs/runs-logs-follow.py|" + repo + "|"
  readonly property string chunkLine: '{"offset":0,"text":"stub claude ok phase=review\\n"}'

  Component { id: spyC; SignalSpy {} }

  function make() {
    var comp = Qt.createComponent("../../../core/stores/RunOutputStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }

  // One am run as RunStore hands it to normalizeRun, fresh on every call:
  // runs.json's row with the fixture's run id, without `status`, and the
  // fixture's `am status` data.
  function amRun(name) {
    var fixture = F.load(name)
    var runs = F.load("runs.json").data.runs
    var row = fixture._am_runs_row
    for (var i = 0; i < runs.length; i++) {
      if (runs[i].id === fixture.data.run.id) row = runs[i]
    }
    delete row.status
    return { row: row, status: fixture.data }
  }

  function rawSubtask(raw, cardId) {
    var stories = raw.status.stories
    for (var i = 0; i < stories.length; i++) {
      for (var j = 0; j < stories[i].subtasks.length; j++) {
        if (stories[i].subtasks[j].card_id === cardId) return stories[i].subtasks[j]
      }
    }
    return null
  }

  // The started capture, normalized: explore.1 is live.
  function startedRun() { return Runs.normalizeRun(amRun("status-started.json")) }

  // The started capture with a deterministic `verify` phase started on
  // openCard; explore.1 stays started unless `exploreDone`.
  function stepRun(exploreDone) {
    var raw = amRun("status-started.json")
    var subtask = rawSubtask(raw, tc.openCard)
    // synthetic: a deterministic phase in flight -- no capture has one
    if (exploreDone) {
      subtask.phases[1].status = "done"
      subtask.phases[1].attempts[0].status = "ok"
    }
    subtask.phases.push({ name: "verify", kind: "deterministic", status: "started", started_at: "",
                          ended_at: null, detail: null, attempts: [] })
    return Runs.normalizeRun(raw)
  }

  // The started capture with explore.1 finished `ok` (its phase done).
  function exploreOkRun() {
    var raw = amRun("status-started.json")
    var subtask = rawSubtask(raw, tc.openCard)
    // synthetic: explore.1 finished
    subtask.phases[1].status = "done"
    subtask.phases[1].attempts[0].status = "ok"
    return Runs.normalizeRun(raw)
  }

  // The started capture under another run id; explore.1 is `status` there.
  function otherRun(id, status) {
    var raw = amRun("status-started.json")
    // synthetic: another running run
    raw.row.id = id
    raw.status.run.id = id
    rawSubtask(raw, tc.openCard).phases[1].attempts[0].status = status
    return Runs.normalizeRun(raw)
  }

  function explore() { return { card_id: tc.openCard, phase: "explore", attempt: 1 } }
  function verifyStep() { return { card_id: tc.openCard, phase: "verify", attempt: 0, step: true } }

  // The raw non-empty lines of tests/fixtures/am/<name>, as strings.
  function streamLines(name) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", Qt.resolvedUrl("../../fixtures/am/" + name), false)
    xhr.send()
    return xhr.responseText.split("\n").filter(function(r) { return r !== "" })
  }

  function argv(proc) { return proc.command.join("|") }
  function send(proc, line) { proc.stdout.read(line) }

  // A store on Run detail with the panel open, following `sel` (explore.1 by
  // default) of `run` (the started capture by default).
  function following(run, sel) {
    var store = make(); if (!store) return null
    store.run = run || startedRun()
    store.selection = sel || explore()
    store.active = true
    store.inRunDetail = true
    return store
  }

  // Every follow process the store holds, in order, recorded on followProcChanged.
  function recorder(store) {
    var seen = []
    store.followProcChanged.connect(function() { if (store.followProc) seen.push(store.followProc) })
    return seen
  }

  function runningCount(procs) {
    return procs.filter(function(p) { return p.running === true }).length
  }

  // T1
  function test_defaults() {
    var store = make(); if (!store) return
    compare(store.followKey, null)
    compare(store.followStatus, "idle")
    compare(store.endStatus, "")
    compare(store.liveText, "")
    compare(store.liveDropped, 0)
    compare(store.hasOutput, false)
    compare(store.followError, "")
    compare(store.followProc, null)
  }

  // T2
  function test_starts_on_a_live_agent_attempt() {
    var store = following(); if (!store) return
    var proc = store.followProc
    verify(proc, "a follow process")
    compare(proc.objectName, "followProc")
    compare(proc.running, true)
    compare(proc.command.length, 7, "no OFFSET")
    compare(argv(proc), tc.followCmd + tc.runId + "|" + tc.openCard + "|explore|1")
    compare(JSON.stringify(store.followKey),
            JSON.stringify({ run_id: tc.runId, card_id: tc.openCard, phase: "explore", attempt: 1 }))
    compare(store.followStatus, "connecting")
  }

  // T3
  function test_starts_on_a_live_step_with_attempt_0() {
    var store = following(stepRun(true), verifyStep()); if (!store) return
    var proc = store.followProc
    verify(proc, "a follow process")
    compare(proc.command.length, 7)
    compare(argv(proc), tc.followCmd + tc.runId + "|" + tc.openCard + "|verify|0")
    compare(store.followKey.attempt, 0)
    compare(store.followStatus, "connecting")
  }

  // T4
  function test_no_start_without_presence_or_a_live_selection() {
    var noRepo = amRun("status-started.json")
    // synthetic: a run with no repo_dir anywhere
    noRepo.row.repo_dir = ""
    noRepo.status.run.repo_dir = ""
    var cases = [
      ["not active", startedRun(), explore(), false, true],
      ["not in Run detail", startedRun(), explore(), true, false],
      ["a done step", startedRun(), { card_id: tc.openCard, phase: "worktree", attempt: 0, step: true }, true, true],
      ["a finished attempt", startedRun(), { card_id: tc.doneCard, phase: "spec", attempt: 1 }, true, true],
      ["no selection", startedRun(), null, true, true],
      ["no run", null, explore(), true, true],
      ["no repo_dir", Runs.normalizeRun(noRepo), explore(), true, true]
    ]
    for (var i = 0; i < cases.length; i++) {
      var store = make(); if (!store) return
      store.run = cases[i][1]
      store.selection = cases[i][2]
      store.active = cases[i][3]
      store.inRunDetail = cases[i][4]
      compare(store.followProc, null, cases[i][0])
      compare(store.followStatus, "idle", cases[i][0])
    }
  }

  // Review Focus 5
  function test_malformed_inputs_start_nothing() {
    var runs = [startedRun(), "run", [], { id: "" }, { id: 7, repo_dir: tc.repo }]
    var sels = [explore(), { card_id: "", phase: "explore", attempt: 1 }, { card_id: tc.openCard, phase: 7, attempt: 1 },
                { card_id: tc.openCard, phase: "explore", attempt: "1" }, "explore", [explore()]]
    for (var i = 0; i < runs.length; i++) {
      for (var j = 0; j < sels.length; j++) {
        if (i === 0 && j === 0) continue
        var store = make(); if (!store) return
        store.active = true
        store.inRunDetail = true
        store.run = runs[i]
        store.selection = sels[j]
        compare(store.followProc, null, "run " + i + ", selection " + j)
        compare(store.followStatus, "idle", "run " + i + ", selection " + j)
      }
    }
  }
}
```

(The helpers `exploreOkRun`, `otherRun`, `streamLines`, `send`, `recorder`, `runningCount` and `spyC` are used by Tasks 2 and 3. Write them now so later tasks only add test functions.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 bash tests/run.sh tst_run_output_store`
Expected: FAIL. Every test fails at `fail(comp.errorString())` with a message naming `RunOutputStore.qml` (no such file). The script exits non-zero.

- [ ] **Step 3: Write the minimal implementation**

Create `core/stores/RunOutputStore.qml`:

```qml
import QtQml
import Quickshell
import Quickshell.Io
import "../domain/logStream.js" as LogStream
import "../domain/runs.js" as Runs

// Run detail's live output: runs-logs-follow.py for the one attempt or step
// the pane shows while it is in flight, its stdout folded line by line
// (LogStream.foldLine) into a bounded buffer. At most one follow process, and
// no background tails. App hands it `backendDir`, `active` (the panel is
// open), `inRunDetail` (the view mode is "run"), `run` (the selected run,
// normalized) and `selection` (RunStore's selectedAttempt), and routes
// snapshotWanted() to RunStore.refreshLogs(); it never reaches for another
// store, and the snapshot logs stay in RunStore.
//
// The followed key is {run_id, card_id, phase, attempt} (attempt 0 for a
// step). Every input change reconciles once: another key stops the process
// (latest wins), clears the state and, while the panel is open on Run detail
// and the selection is live (Runs.isLiveSelection) with a usable repo_dir,
// follows it from offset 0. Leaving Run detail or closing the panel stops the
// process and keeps the key and the buffer; coming back on the same live key
// follows it again from offset 0, unless its follow ended or failed. A key
// that stops being live keeps its process until the end line or the exit.
// The end line sets `ended` and endStatus; for a step it asks for one logs
// snapshot. An {"ok": false} line, or an exit before the end line, is an
// error. A stopped process's lines and exit are ignored.
Scope {
  id: store

  property string backendDir: ""      // <plugin>/core/backend/
  property bool active: false         // App binds this to "panel open"
  property bool inRunDetail: false    // App binds this to view mode "run"
  property var run: null              // the selected run, normalized; null when none
  property var selection: null        // RunStore's selectedAttempt; null when none

  property var followKey: null        // {run_id, card_id, phase, attempt} or null
  property string followStatus: "idle" // idle | connecting | following | ended | unsupported | error
  property string endStatus: ""       // am's end status; "" until the end line
  property string liveText: ""        // LogStream.bufferText of the buffer
  property int liveDropped: 0         // lines dropped from the buffer's front
  property bool hasOutput: false      // the buffer holds a line, a partial line or dropped lines
  property string followError: ""     // why the follow failed; "" when it has not
  property var followProc: null       // the current follow Process, or null
  property int followSeq: 0           // bumped on every start and stop: the launch guard
  property var buffer: LogStream.emptyBuffer()

  // A followed step ended: RunStore should fetch its logs snapshot.
  signal snapshotWanted()

  function isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }

  // {run_id, card_id, phase, attempt} of (run, sel), attempt 0 for a step;
  // null without a run id, a card id or a phase.
  function selectionKey(run, sel) {
    if (!store.isObject(run) || !store.isObject(sel)) return null
    if (typeof run.id !== "string" || run.id === "") return null
    if (typeof sel.card_id !== "string" || sel.card_id === "" || typeof sel.phase !== "string" || sel.phase === "") return null
    return { run_id: run.id, card_id: sel.card_id, phase: sel.phase, attempt: sel.step === true ? 0 : sel.attempt }
  }

  function sameKey(a, b) {
    if (a === null || b === null) return a === b
    return a.run_id === b.run_id && a.card_id === b.card_id && a.phase === b.phase && a.attempt === b.attempt
  }

  // The panel is open on Run detail.
  function isPresent() { return store.active && store.inRunDetail }

  function isLive() { return Runs.isLiveSelection(store.run, store.selection) }

  // k can be followed now: present, live and the run has a repo_dir.
  function canStart(k) {
    return k !== null && store.isPresent() && store.isLive()
        && typeof store.run.repo_dir === "string" && store.run.repo_dir !== ""
  }

  function setBuffer(b) {
    store.buffer = b
    store.liveText = LogStream.bufferText(b)
    store.liveDropped = b.dropped
    store.hasOutput = b.lines.length > 0 || b.partial !== "" || b.dropped > 0
  }

  function clear() {
    store.followKey = null
    store.followStatus = "idle"
    store.endStatus = ""
    store.followError = ""
    store.setBuffer(LogStream.emptyBuffer())
  }

  function reconcile() {
    var k = store.selectionKey(store.run, store.selection)
    if (store.sameKey(k, store.followKey)) return
    if (store.followProc) store.stop()
    store.clear()
    if (store.canStart(k)) store.start(k)
  }

  // runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT, from offset 0, into a fresh buffer.
  function start(k) {
    store.followSeq += 1
    store.followKey = k
    store.setBuffer(LogStream.emptyBuffer())
    store.followStatus = "connecting"
    store.endStatus = ""
    store.followError = ""
    var proc = followC.createObject(store, { launchSeq: store.followSeq })
    proc.command = ["python3", store.backendDir + "runs/runs-logs-follow.py", store.run.repo_dir,
                    k.run_id, k.card_id, k.phase, String(k.attempt)]
    store.followProc = proc
    proc.running = true
  }

  // SIGTERM; the stopped process's later lines and exit are ignored.
  function stop() {
    store.followSeq += 1
    if (store.followProc) store.followProc.running = false
    store.followProc = null
  }

  onActiveChanged: store.reconcile()
  onInRunDetailChanged: store.reconcile()
  onRunChanged: store.reconcile()
  onSelectionChanged: store.reconcile()
  Component.onCompleted: store.reconcile()

  // One Process per follow launch, so each carries the launch it belongs to.
  Component {
    id: followC

    Process {
      id: fp
      objectName: "followProc"
      property int launchSeq: 0
      stderr: StdioCollector { waitForEnd: true }
      onExited: function(exitCode) { fp.destroy() }
    }
  }
}
```

The header comment states the whole contract. Tasks 2 and 3 implement the lines, the exit, and the same-key paths it describes. No later task edits the comment.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 bash tests/run.sh tst_run_output_store`
Expected: PASS. The pytest part passes. The QML output shows `== tests/core/stores/tst_run_output_store.qml` and `Totals: 7 passed, 0 failed` (5 tests plus qmltestrunner's `initTestCase`/`cleanupTestCase`), with no `TypeError` lines, and the script exits 0.

- [ ] **Step 5: Run the layer rule**

Run: `timeout 300 python3 -m pytest tests/architecture -q` (if `python3` has no pytest: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture -q`)
Expected: PASS. The store imports only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain/*.js`.

- [ ] **Step 6: Commit**

```bash
git add core/stores/RunOutputStore.qml tests/core/stores/tst_run_output_store.qml
git commit -m "feat(stores): RunOutputStore follows a live selection and stops on another key"
```

---

### Task 2: Lines, the end, errors, the exit, latest wins

**Files:**
- Modify: `core/stores/RunOutputStore.qml`. Add three functions after `stop()`, and give the `followC` `Process` a `stdout` and a store-aware `onExited`.
- Test: `tests/core/stores/tst_run_output_store.qml`. Add test functions before the final `}`.

**Interfaces:**
- Consumes (Task 1): `store.followProc`, `store.followSeq`, `store.followKey`, `store.followStatus`, `store.buffer`, `store.setBuffer(b)`, `store.stop()`, `followC`; `LogStream.foldLine(buffer, value)` → `{buffer, kind}` with kind `hello | chunk | end | refusal | ignored`; `Runs.errorText(envelope)`.
- Produces: `isCurrentFollow(proc) → bool`, `followLine(proc, data)`, `followExited(proc, exitCode)`. The follow `Process` gets `stdout: SplitParser { onRead → store.followLine(fp, data) }` and calls `store.followExited(fp, exitCode)` before `fp.destroy()`.

- [ ] **Step 1: Write the failing tests**

Add these functions to `tests/core/stores/tst_run_output_store.qml`, just before the file's final closing `}`:

```qml
  // T5
  function test_lines_fold_into_the_live_text() {
    var store = following(); if (!store) return
    var proc = store.followProc
    var lines = streamLines("logs-follow-agent.jsonl")
    send(proc, lines[0])
    compare(store.followStatus, "following", "the hello")
    compare(store.hasOutput, false)
    compare(store.liveText, "")
    send(proc, lines[1])
    compare(store.liveText, "stub claude ok phase=review")
    compare(store.hasOutput, true)
    compare(store.liveDropped, 0)
    compare(store.followStatus, "following")
    send(proc, "")
    send(proc, "   ")
    send(proc, "not json")
    compare(store.liveText, "stub claude ok phase=review", "blank and unparseable lines change nothing")
    compare(store.followStatus, "following")
    compare(store.followError, "")
  }

  // T7
  function test_a_non_live_selection_stops_and_clears() {
    var store = following(); if (!store) return
    var seen = recorder(store)
    var old = store.followProc
    send(old, tc.chunkLine)
    store.selection = { card_id: tc.openCard, phase: "worktree", attempt: 0, step: true }
    compare(old.running, false)
    compare(store.followProc, null)
    compare(store.followKey, null)
    compare(store.liveText, "")
    compare(store.hasOutput, false)
    compare(store.followStatus, "idle")
    compare(seen.length, 0, "no new process")
  }

  // T8
  function test_another_run_or_none_stops_and_clears() {
    var store = following(); if (!store) return
    var old = store.followProc
    send(old, tc.chunkLine)
    store.run = otherRun("20261009T000000Z-0th3r000", "ok")
    compare(old.running, false)
    compare(store.followProc, null)
    compare(store.followKey, null)
    compare(store.liveText, "")
    compare(store.followStatus, "idle")
    store.selection = null
    compare(store.followProc, null)
    compare(store.followKey, null)

    var again = following(); if (!again) return
    var proc = again.followProc
    send(proc, tc.chunkLine)
    again.run = null
    compare(proc.running, false)
    compare(again.followProc, null)
    compare(again.followKey, null)
    compare(again.liveText, "")
    compare(again.followStatus, "idle")
  }

  // T9
  function test_latest_wins_the_older_process_is_ignored() {
    var store = following(stepRun(false), explore()); if (!store) return
    var a = store.followProc
    verify(a, "process A follows explore.1")
    store.selection = verifyStep()
    var b = store.followProc
    compare(a.running, false, "A is stopped")
    verify(b && b !== a, "B is the current one")
    compare(argv(b), tc.followCmd + tc.runId + "|" + tc.openCard + "|verify|0")
    send(a, tc.chunkLine)
    compare(store.liveText, "", "A's late line is dropped")
    compare(store.followStatus, "connecting")
    a.exited(0)
    compare(store.followProc, b, "A's late exit does not null out B")
    compare(store.followStatus, "connecting")
    compare(store.followError, "")
    var lines = streamLines("logs-follow-step.jsonl")
    send(b, lines[0])
    send(b, lines[1])
    compare(store.liveText, "==> verify-ok (exit 0)\nverified")
    compare(store.followStatus, "following")
  }

  // T11
  function test_a_new_snapshot_of_the_same_key_does_not_restart() {
    var store = following(); if (!store) return
    var proc = store.followProc
    send(proc, tc.chunkLine)
    store.run = startedRun()
    compare(store.followProc, proc)
    compare(proc.running, true)
    compare(store.liveText, "stub claude ok phase=review")
    compare(store.followStatus, "following")
  }

  // T12
  function test_the_end_of_an_agent_attempt_keeps_the_buffer() {
    var store = following(); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "snapshotWanted" })
    var proc = store.followProc
    var lines = streamLines("logs-follow-agent.jsonl")
    for (var i = 0; i < lines.length; i++) send(proc, lines[i])
    compare(store.followStatus, "ended")
    compare(store.endStatus, "ok")
    compare(store.liveText, "stub claude ok phase=review")
    compare(spy.count, 0, "an agent attempt asks for no snapshot")
    send(proc, '{"offset":28,"text":"late\\n"}')
    compare(store.liveText, "stub claude ok phase=review", "a line after the end is ignored")
    proc.exited(0)
    compare(store.followStatus, "ended")
    compare(store.followError, "")
    compare(store.followProc, null)
    store.run = exploreOkRun()
    compare(store.followStatus, "ended", "a snapshot where it finished keeps the ended state")
    compare(store.endStatus, "ok")
    compare(store.liveText, "stub claude ok phase=review")
    compare(store.followProc, null, "nothing starts")
  }

  // T13
  function test_the_end_of_a_step_asks_for_one_snapshot() {
    var store = following(stepRun(true), verifyStep()); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "snapshotWanted" })
    var proc = store.followProc
    var lines = streamLines("logs-follow-step.jsonl")
    for (var i = 0; i < lines.length; i++) send(proc, lines[i])
    compare(store.followStatus, "ended")
    compare(store.endStatus, "ok")
    compare(store.liveText, "==> verify-ok (exit 0)\nverified")
    compare(spy.count, 1)
    send(proc, lines[2])
    compare(spy.count, 1, "a repeated end line asks again for nothing")
    proc.exited(0)
    compare(spy.count, 1, "nor does the exit")
    compare(store.followStatus, "ended")
  }

  // T14
  function test_an_end_without_a_string_status() {
    var store = following(); if (!store) return
    var proc = store.followProc
    send(proc, streamLines("logs-follow-agent.jsonl")[0])
    // synthetic: an end line with no status
    send(proc, '{"event":"end"}')
    compare(store.followStatus, "ended")
    compare(store.endStatus, "")
  }

  // T15
  function test_an_error_line() {
    var store = following(); if (!store) return
    var proc = store.followProc
    send(proc, tc.chunkLine)
    var envelope = F.load("logs-follow-refusal.json")
    send(proc, JSON.stringify(envelope))
    compare(store.followStatus, "error")
    compare(store.followError, Runs.errorText(envelope))
    compare(store.liveText, "stub claude ok phase=review", "the buffer stays")
    proc.exited(0)
    compare(store.followStatus, "error")
    compare(store.followError, Runs.errorText(envelope), "the exit after it changes nothing")
    compare(store.followProc, null)
  }

  // T16
  function test_an_exit_with_no_end_line() {
    var store = following(); if (!store) return
    var proc = store.followProc
    send(proc, tc.chunkLine)
    proc.exited(0)
    compare(store.followStatus, "error")
    compare(store.followError, "Live output stopped: the helper exited with code 0")
    compare(store.followProc, null)
    compare(store.liveText, "stub claude ok phase=review")
  }

  // Review Focus 1
  function test_an_equal_selection_object_does_not_restart() {
    var store = following(); if (!store) return
    var proc = store.followProc
    send(proc, tc.chunkLine)
    store.selection = explore()
    compare(store.followProc, proc)
    compare(proc.running, true)
    compare(store.liveText, "stub claude ok phase=review")
  }

  // Review Focus 2
  function test_a_key_that_stops_being_live_keeps_its_process() {
    var store = following(); if (!store) return
    var proc = store.followProc
    var lines = streamLines("logs-follow-agent.jsonl")
    send(proc, lines[0])
    send(proc, lines[1])
    store.run = exploreOkRun()
    compare(store.followProc, proc, "the process stays for the end line")
    compare(proc.running, true)
    send(proc, lines[2])
    compare(store.followStatus, "ended")
    compare(store.endStatus, "ok")
    compare(store.liveText, "stub claude ok phase=review")
  }

  // Review Focus 4
  function test_a_new_run_with_the_old_selection_then_its_own() {
    var store = following(); if (!store) return
    var seen = recorder(store)
    var a = store.followProc
    var other = "20261009T000000Z-0th3r000"
    store.run = otherRun(other, "started")
    compare(a.running, false, "the old run's process stops")
    compare(runningCount(seen), 1, "the old selection is live in the new run too")
    compare(store.followKey.run_id, other)
    compare(argv(store.followProc), tc.followCmd + other + "|" + tc.openCard + "|explore|1")
    var b = store.followProc
    store.selection = null
    compare(b.running, false)
    compare(store.followProc, null)
    compare(store.followKey, null)
    send(a, tc.chunkLine)
    send(b, tc.chunkLine)
    compare(store.liveText, "", "neither stopped process folds")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 bash tests/run.sh tst_run_output_store`
Expected: FAIL. All 13 new tests send a line, and each fails with `TypeError: Cannot call method 'read' of null`, because the Task 1 `Process` has no `stdout`. The 5 Task 1 tests still pass. The script exits non-zero.

- [ ] **Step 3: Implement lines, the end, errors and the exit**

In `core/stores/RunOutputStore.qml`, insert these functions directly after the `stop()` function (before `onActiveChanged:`):

```qml
  function isCurrentFollow(proc) {
    return proc !== null && proc === store.followProc && proc.launchSeq === store.followSeq
  }

  // One stdout line of the current process, after its end or error ignored:
  // trimmed and parsed (blank or not JSON is null), then one LogStream.foldLine.
  // A hello or a chunk replaces the buffer and is `following`; the end is
  // `ended` with am's status, and asks for a logs snapshot for a step (attempt
  // 0); an {"ok": false} line is `error` with its Runs.errorText. The buffer
  // stays on the end and on an error.
  function followLine(proc, data) {
    if (!store.isCurrentFollow(proc)) return
    if (store.followStatus === "ended" || store.followStatus === "error") return
    var text = String(data || "").trim()
    var value = null
    if (text !== "") {
      try { value = JSON.parse(text) } catch (e) { value = null }
    }
    var r = LogStream.foldLine(store.buffer, value)
    if (r.kind === "hello" || r.kind === "chunk") {
      store.setBuffer(r.buffer)
      store.followStatus = "following"
    } else if (r.kind === "end") {
      store.followStatus = "ended"
      store.endStatus = typeof value.status === "string" ? value.status : ""
      if (store.followKey.attempt === 0) store.snapshotWanted()
    } else if (r.kind === "refusal") {
      store.followStatus = "error"
      store.followError = Runs.errorText(value)
    }
  }

  // The current process exited: no process is left; with no end line and no
  // error line before it, the follow is an error naming the exit code.
  function followExited(proc, exitCode) {
    if (!store.isCurrentFollow(proc)) return
    store.followProc = null
    if (store.followStatus === "ended" || store.followStatus === "error") return
    store.followStatus = "error"
    store.followError = "Live output stopped: the helper exited with code " + exitCode
  }
```

Then replace the `followC` component's `Process` block. The old block:

```qml
    Process {
      id: fp
      objectName: "followProc"
      property int launchSeq: 0
      stderr: StdioCollector { waitForEnd: true }
      onExited: function(exitCode) { fp.destroy() }
    }
```

The new block:

```qml
    Process {
      id: fp
      objectName: "followProc"
      property int launchSeq: 0
      stdout: SplitParser { onRead: function(data) { store.followLine(fp, data) } }
      stderr: StdioCollector { waitForEnd: true }
      onExited: function(exitCode) {
        store.followExited(fp, exitCode)
        fp.destroy()
      }
    }
```

Why `snapshotWanted()` fires once per key: after the end line, `followStatus` is `ended` and every later line of that process is ignored. An ended key never restarts while it stays the followed key (Task 3's same-key paths leave `ended` alone), and another key clears the state first.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 bash tests/run.sh tst_run_output_store`
Expected: PASS, `Totals: 20 passed, 0 failed`, no `TypeError`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunOutputStore.qml tests/core/stores/tst_run_output_store.qml
git commit -m "feat(stores): RunOutputStore folds follow lines, ends, errors and ignores a stopped process"
```

---

### Task 3: Leaving and coming back (the same-key paths of reconcile)

**Files:**
- Modify: `core/stores/RunOutputStore.qml`. Replace the body of `reconcile()`.
- Test: `tests/core/stores/tst_run_output_store.qml`. Add test functions before the final `}`.

**Interfaces:**
- Consumes (Tasks 1-2): `selectionKey`, `sameKey`, `isPresent`, `isLive`, `canStart`, `clear`, `start`, `stop`, `followProc`, `followStatus`.
- Produces: the full B2 `reconcile()`. A same key that is not present stops and keeps everything. A same key that is present with no process restarts from offset 0 unless `ended`, `error` or `unsupported`, and clears when no longer live.

- [ ] **Step 1: Write the failing tests**

Add these functions to `tests/core/stores/tst_run_output_store.qml`, just before the file's final closing `}`:

```qml
  // T6
  function test_leaving_run_detail_stops_and_keeps_then_returning_restarts() {
    var store = following(); if (!store) return
    var seen = recorder(store)
    var old = store.followProc
    send(old, streamLines("logs-follow-agent.jsonl")[0])
    send(old, tc.chunkLine)
    var key = JSON.stringify(store.followKey)
    store.inRunDetail = false
    compare(old.running, false, "SIGTERM")
    compare(store.followProc, null)
    compare(JSON.stringify(store.followKey), key, "the key stays")
    compare(store.liveText, "stub claude ok phase=review", "the buffer stays")
    compare(store.followStatus, "following")
    store.inRunDetail = true
    compare(seen.length, 1, "exactly one new process")
    verify(store.followProc !== old)
    compare(store.followProc.running, true)
    compare(argv(store.followProc), tc.followCmd + tc.runId + "|" + tc.openCard + "|explore|1")
    compare(store.followStatus, "connecting")
  }

  // T6
  function test_closing_the_panel_stops_and_keeps_then_reopening_restarts() {
    var store = following(); if (!store) return
    var seen = recorder(store)
    var old = store.followProc
    send(old, streamLines("logs-follow-agent.jsonl")[0])
    send(old, tc.chunkLine)
    var key = JSON.stringify(store.followKey)
    store.active = false
    compare(old.running, false, "SIGTERM")
    compare(store.followProc, null)
    compare(JSON.stringify(store.followKey), key, "the key stays")
    compare(store.liveText, "stub claude ok phase=review", "the buffer stays")
    compare(store.followStatus, "following")
    store.active = true
    compare(seen.length, 1, "exactly one new process")
    verify(store.followProc !== old)
    compare(store.followProc.running, true)
    compare(argv(store.followProc), tc.followCmd + tc.runId + "|" + tc.openCard + "|explore|1")
    compare(store.followStatus, "connecting")
  }

  // T10
  function test_at_most_one_follow_process_runs() {
    var store = make(); if (!store) return
    var seen = recorder(store)
    store.run = stepRun(false)
    store.selection = explore()
    store.active = true
    store.inRunDetail = true
    compare(runningCount(seen), 1, "A")
    store.selection = verifyStep()
    compare(runningCount(seen), 1, "B replaces A")
    store.inRunDetail = false
    compare(runningCount(seen), 0, "left Run detail")
    store.inRunDetail = true
    compare(runningCount(seen), 1, "back on Run detail")
    store.selection = explore()
    compare(runningCount(seen), 1, "back to explore.1")
    store.active = false
    compare(runningCount(seen), 0, "panel closed")
    store.active = true
    compare(runningCount(seen), 1, "panel open")
    compare(seen.length, 5)
    for (var i = 0; i < seen.length; i++) compare(seen[i].objectName, "followProc")
  }

  // Review Focus 3
  function test_an_ended_or_failed_follow_survives_leave_and_return() {
    var store = following(); if (!store) return
    var seen = recorder(store)
    var proc = store.followProc
    var lines = streamLines("logs-follow-agent.jsonl")
    for (var i = 0; i < lines.length; i++) send(proc, lines[i])
    store.active = false
    store.active = true
    compare(seen.length, 0, "an ended follow does not restart")
    compare(store.followStatus, "ended")
    compare(store.liveText, "stub claude ok phase=review")

    var failed = following(); if (!failed) return
    var seen2 = recorder(failed)
    var p2 = failed.followProc
    send(p2, tc.chunkLine)
    p2.exited(0)
    failed.inRunDetail = false
    failed.inRunDetail = true
    compare(seen2.length, 0, "a failed follow does not restart")
    compare(failed.followStatus, "error")
    compare(failed.liveText, "stub claude ok phase=review")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 bash tests/run.sh tst_run_output_store`
Expected: FAIL. Exactly three tests fail:
- `test_leaving_run_detail_stops_and_keeps_then_returning_restarts` fails at `SIGTERM`.
- `test_closing_the_panel_stops_and_keeps_then_reopening_restarts` fails at `SIGTERM`.
- `test_at_most_one_follow_process_runs` fails at `left Run detail`.

`test_an_ended_or_failed_follow_survives_leave_and_return` already passes, because Task 1's reconcile ignores a same key. It guards the new code's `ended`/`error` branch. `Totals: 21 passed, 3 failed`.

- [ ] **Step 3: Implement the same-key paths**

In `core/stores/RunOutputStore.qml`, replace the whole `reconcile()` function. The old function:

```qml
  function reconcile() {
    var k = store.selectionKey(store.run, store.selection)
    if (store.sameKey(k, store.followKey)) return
    if (store.followProc) store.stop()
    store.clear()
    if (store.canStart(k)) store.start(k)
  }
```

The new function:

```qml
  // Another key: stop, clear, and start when it can be followed. The same key
  // off Run detail or with the panel closed: stop and keep the rest. The same
  // key back with no process: follow it again from offset 0 while live (clear
  // once it is not), unless it ended or failed. A running process of the same
  // key is left alone.
  function reconcile() {
    var k = store.selectionKey(store.run, store.selection)
    if (!store.sameKey(k, store.followKey)) {
      if (store.followProc) store.stop()
      store.clear()
      if (store.canStart(k)) store.start(k)
      return
    }
    if (k === null) return
    if (!store.isPresent()) {
      if (store.followProc) store.stop()
      return
    }
    if (store.followProc) return
    var s = store.followStatus
    if (s === "ended" || s === "error" || s === "unsupported") return
    if (store.canStart(k)) store.start(k)
    else if (!store.isLive()) store.clear()
  }
```

(`k === null` with an equal `followKey` means nothing is followed and the state is already clear. `start` is the only place `followKey` becomes non-null.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 bash tests/run.sh tst_run_output_store`
Expected: PASS, `Totals: 24 passed, 0 failed`, no `TypeError`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunOutputStore.qml tests/core/stores/tst_run_output_store.qml
git commit -m "feat(stores): RunOutputStore stops off Run detail and follows again on return"
```

---

### Task 4: App composes `runOutput`; architecture docs

**Files:**
- Modify: `core/stores/App.qml`. Insert a block between the `runs` block's closing `}` and `readonly property GraphStore graph: GraphStore {`.
- Modify: `tests/core/stores/tst_app_runs.qml`. Add an import line, and add helpers and tests before the final `}`.
- Modify: `docs/architecture.md`. Insert a bullet after the line that starts `  Dispatch (S3 3.1)` (line 93), and edit line 201.

**Interfaces:**
- Consumes: `RunOutputStore` (Tasks 1-3: `backendDir`, `active`, `inRunDetail`, `run`, `selection`, `followProc`, `followStatus`, `snapshotWanted()`); `RunStore` `runById(id)`, `selectedRunId`, `selectedAttempt`, `refreshLogs()`, `refresh()`, `snapshotRunner.current`, `logsRunner.current`, `logsRunner.busy`, `selectAttempt(cardId, phase, attempt)`; `app.nav.viewMode`; `app.panelOpen`.
- Produces: `app.runOutput` (a `RunOutputStore`).

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_app_runs.qml`, change the imports at the top from:

```qml
import QtQuick
import QtTest
```

to:

```qml
import QtQuick
import QtTest
import "../../helpers/amFixtures.js" as F
```

Then add this, just before the file's final closing `}` (after `test_titles_follow_the_board`):

```qml
  // ---- the live output store (live output 3.2)

  readonly property string startedId: "20261008T143823Z-e795ad19"
  readonly property string openCard: "2280a6ab-9c40-434b-9729-63fd1f373754"

  // The started capture as a runs-snapshot-all.py entry: runs.json's first row
  // whose `status` is status-started.json's data. With `step`, openCard's
  // explore is finished and a deterministic `verify` phase is started.
  function startedEntry(step) {
    var e = F.load("runs.json").data.runs[0]
    e.status = F.load("status-started.json").data
    if (step) {
      var subtask = e.status.stories[1].subtasks[1]
      // synthetic: a deterministic phase in flight -- no capture has one
      subtask.phases[1].status = "done"
      subtask.phases[1].attempts[0].status = "ok"
      subtask.phases.push({ name: "verify", kind: "deterministic", status: "started", started_at: "",
                            ended_at: null, detail: null, attempts: [] })
    }
    return e
  }

  // runs-snapshot-all.py's reply: pA's entry lists `entries` as given.
  function entriesReply(entries) {
    return JSON.stringify({ ok: true, projects: [{ root: tc.pA.root_path, ok: true, runs: entries }],
                            data_dir: "/home/u/.local/share" }) + "\n"
  }

  // App with pA selected and its snapshot listing the started capture (`step`
  // as in startedEntry) applied.
  function withStarted(step) {
    var app = make(); if (!app) return null
    var proc = app.runs.snapshotRunner.current
    proc.outText = entriesReply([startedEntry(step)])
    proc.exited(0)
    return app
  }

  // A1
  function test_app_composes_a_run_output_store() {
    var app = makeBare(); if (!app) return
    verify(app.runOutput, "App composes it as app.runOutput")
    compare(app.runOutput.followStatus, "idle")
    compare(app.runOutput.backendDir, "/plugin/core/backend/")
    app.backendDir = "/other/core/backend/"
    compare(app.runOutput.backendDir, "/other/core/backend/")
    compare(app.runOutput.active, false)
    app.panelOpen = true
    compare(app.runOutput.active, true)
    app.panelOpen = false
    compare(app.runOutput.active, false)
    compare(app.runOutput.inRunDetail, false, "board")
    app.nav.viewMode = "run"
    compare(app.runOutput.inRunDetail, true)
    app.nav.viewMode = "runs"
    compare(app.runOutput.inRunDetail, false, "the Runs list is not Run detail")
  }

  // A2
  function test_run_and_selection_follow_the_run_store() {
    var app = withStarted(false); if (!app) return
    compare(app.runOutput.run, null, "no run selected")
    compare(app.runOutput.selection, null)
    app.runs.selectedRunId = tc.startedId
    verify(app.runOutput.run === app.runs.runById(tc.startedId), "the selected run")
    compare(JSON.stringify(app.runOutput.selection), JSON.stringify(app.runs.selectedAttempt))
    compare(JSON.stringify(app.runOutput.selection), JSON.stringify({ card_id: tc.openCard, phase: "explore", attempt: 1 }))
    var before = app.runOutput.run
    app.runs.refresh()
    var proc = app.runs.snapshotRunner.current
    proc.outText = entriesReply([startedEntry(false)])
    proc.exited(0)
    verify(app.runOutput.run !== before, "a snapshot hands a new run object")
    verify(app.runOutput.run === app.runs.runById(tc.startedId))
    app.runs.selectAttempt("5560d0fe-2b8e-4ef9-ad71-96b50ee89daa", "spec", 1)
    compare(JSON.stringify(app.runOutput.selection), JSON.stringify(app.runs.selectedAttempt))
    app.runs.selectedRunId = ""
    compare(app.runOutput.run, null)
  }

  // A3
  function test_snapshot_wanted_refreshes_the_logs() {
    var app = withStarted(true); if (!app) return
    app.runs.selectedRunId = tc.startedId
    compare(JSON.stringify(app.runs.selectedAttempt),
            JSON.stringify({ card_id: tc.openCard, phase: "verify", attempt: 0, step: true }))
    var first = app.runs.logsRunner.current
    verify(first, "the step's logs were asked for")
    first.outText = ""
    first.exited(1)
    compare(app.runs.logsRunner.busy, false)
    app.runOutput.snapshotWanted()
    var fetch = app.runs.logsRunner.current
    verify(fetch !== first, "one new runs-logs.py fetch")
    compare(fetch.command.join("|"), "python3|/plugin/core/backend/runs/runs-logs.py|/home/user/Code/omarchy-project-manager|"
            + tc.startedId + "|" + tc.openCard + "|verify|0")
  }

  // A4
  function test_the_selected_live_attempt_is_followed_until_the_panel_closes() {
    var app = withStarted(false); if (!app) return
    app.panelOpen = true
    app.nav.viewMode = "run"
    app.runs.selectedRunId = tc.startedId
    var proc = app.runOutput.followProc
    verify(proc, "the default attempt, explore.1, is followed")
    compare(proc.running, true)
    compare(proc.command.join("|"), "python3|/plugin/core/backend/runs/runs-logs-follow.py|/home/user/Code/omarchy-project-manager|"
            + tc.startedId + "|" + tc.openCard + "|explore|1")
    app.panelOpen = false
    compare(proc.running, false, "closing the panel stops it")
    compare(app.runOutput.followProc, null)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 bash tests/run.sh tst_app_runs`
Expected: FAIL. The four new tests fail: `app.runOutput` is `undefined` (`verify` fails, or a `TypeError: Cannot read property ... of undefined`, which `run.sh` reports). The existing tests still pass (`Totals: 15 passed, 4 failed` or a `TypeError` line). The script exits non-zero.

- [ ] **Step 3: Compose the store in App**

In `core/stores/App.qml`, insert this between the `runs` block's closing `  }` and the blank line before `  readonly property GraphStore graph: GraphStore {`. It goes directly after `runs`:

```qml

  // The live output store never imports the run store: App hands it the
  // selected run (normalized, from the run store's snapshot), the attempt or
  // step Run detail shows (selectedAttempt) and the two presence flags --
  // the panel open and the view mode "run" -- and routes its snapshot
  // request to the run store's refreshLogs.
  readonly property RunOutputStore runOutput: RunOutputStore {
    backendDir: app.backendDir
    active: app.panelOpen
    inRunDetail: app.nav.viewMode === "run"
    run: app.runs.runById(app.runs.selectedRunId)
    selection: app.runs.selectedAttempt
    onSnapshotWanted: app.runs.refreshLogs()
  }
```

`RunOutputStore` resolves as a type because `App.qml` and `RunOutputStore.qml` share the `core/stores/` directory, the same way `RunStore` does. `run` re-evaluates whenever `app.runs.runs` or `app.runs.selectedRunId` changes, because `runById` reads both inside the binding.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 bash tests/run.sh tst_app_runs`
Expected: PASS, `Totals: 19 passed, 0 failed`, no `TypeError`, exit 0.

- [ ] **Step 5: Document the store in `docs/architecture.md`**

(a) Line 201 contains the phrase `is long-lived and no store runs it yet: it runs`. Replace exactly that phrase with:

```
is long-lived and `RunOutputStore` runs it as a plain `Process`: it runs
```

(b) Insert one new line after the line that starts with `  Dispatch (S3 3.1): the store also starts am runs.`. That is the last line of the `RunStore.qml` block, just before the blank line that precedes `Other \`ui/\` pieces:`. The new line is this bullet, as one line:

```
- `RunOutputStore.qml` Run detail's live output: `runs-logs-follow.py` for the one attempt or step the pane shows while it is in flight, a plain `Process` (not a `HelperRunner`) whose `SplitParser` lines each go through one `LogStream.foldLine` into a bounded buffer; at most one follow process, and no background tails. It never reaches for another store: `App` hands it `backendDir`, `active` (`panelOpen`), `inRunDetail` (view mode `run`), `run` (`app.runs.runById(app.runs.selectedRunId)`) and `selection` (`app.runs.selectedAttempt`), and routes `snapshotWanted()` to `app.runs.refreshLogs()`; the snapshot logs stay in `RunStore`. `followKey` is `{run_id, card_id, phase, attempt}` (attempt `0` for a step) or null; `followStatus` is `idle`, `connecting`, `following`, `ended`, `unsupported` or `error`; `endStatus` is am's end status (`""` until the end line); `liveText` (`LogStream.bufferText`), `liveDropped` and `hasOutput` follow the buffer; `followError` says why a follow failed; `followProc` is the current process or null. Every change of an input reconciles once, comparing keys, never run objects, so a new snapshot of the same attempt restarts nothing: another key stops the process (SIGTERM through `running = false`, latest wins: a stopped process's lines and exit are ignored), clears the state and, while the panel is open on Run detail and `Runs.isLiveSelection` holds with a non-empty `repo_dir`, starts `runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT` from offset 0. Leaving Run detail or closing the panel stops the process and keeps the key and the buffer; coming back on the same live key starts again from offset 0 unless the follow ended or failed. A key that stops being live keeps its process until the end line or the exit. The end line sets `ended` and `endStatus` and keeps the buffer; for a step it emits `snapshotWanted()` once. An `{ok: false}` line sets `error` with `Runs.errorText`; an exit before the end line sets `error` with `Live output stopped: the helper exited with code N`.
```

Check: `grep -n "no store runs it yet" docs/architecture.md` prints nothing, and `grep -c "RunOutputStore" docs/architecture.md` prints `2`.

- [ ] **Step 6: Run the whole suite**

Run: `timeout 900 bash tests/run.sh`
Expected: the pytest part passes (`tests/architecture` included). Every QML file prints `Totals: N passed, 0 failed`, and no `TypeError`/`ReferenceError`/`is not a function` lines are printed. The script exits 0.

- [ ] **Step 7: Commit**

```bash
git add core/stores/App.qml tests/core/stores/tst_app_runs.qml docs/architecture.md
git commit -m "feat(stores): App composes RunOutputStore next to RunStore"
```

---

## Self-review (against the spec)

- **B1** (inputs, state, `followProc`, `snapshotWanted`, derived buffer properties): Task 1, `setBuffer`. Tests T1, T5.
- **B2** (reconcile): step 2 is in Task 1 (T2-T4, T7, T8, T9, T11); steps 3-5 are in Task 3 (T6, T10, RF3); step 4 is RF2 (Task 2).
- **B3** (start argv, seven elements, fresh buffer, `connecting`): Task 1 `start`. T2, T3, T6.
- **B4** (stop, seq bump, `running = false`, `followProc` null): Task 1 `stop`. T6-T9.
- **B5** (one line, one `foldLine`; stale or ended/error lines ignored; hello/chunk/end/refusal/ignored): Task 2 `followLine`. T5, T9, T12-T15.
- **B6** (exit): Task 2 `followExited`. T9, T12, T15, T16.
- **B7** (App wiring): Task 4. A1-A4.
- **B8** (docs): Task 4, Step 5.
- **Spec Review focus 1-5**: T9/T10/RF4; T11/RF1; B2 step 4 RF2 and T12; T13; T9.
- Out-of-scope items (resume offset, retries, `unsupported` mapping, UI) are not implemented. `unsupported` is only named in the state comment and in reconcile's "do not restart" branch, as B2 step 5 states.
- The names stay the same across tasks: `followLine`, `followExited`, `isCurrentFollow`, `selectionKey`, `sameKey`, `canStart`, `isLive`, `isPresent`, `setBuffer`, `clear`, `start`, `stop`, `followC`, `followSeq`, `buffer`.
<!-- task-pipeline: validated -->
