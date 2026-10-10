# 3.2 RunOutputStore: follow one live attempt — spec

Card `354d3953-88ac-4a11-9f9d-c621c3e78995`, subtask of story `053768a8-6bfd-4141-8c91-918e98ea4cf5`
(Live output store). Parent design: `docs/superpowers/specs/2026-10-05-live-output-design.md`
(below: **LO**). Builds on 3.1 (`RunStore` selects a step: `selectedAttempt` may be
`{card_id, phase, attempt: 0, step: true}`; `Runs.phaseStatus`; spec
`docs/superpowers/specs/3-1-runstore-selecting-52fec98e.md`). Followed by sibling 3.3
(`2bce8772-…`, "RunOutputStore: recovering a broken follow").

## Purpose

A new store, `core/stores/RunOutputStore.qml`, runs `runs-logs-follow.py` for the one attempt
(agent or step) that Run detail shows while that attempt is in flight, and folds its stdout into
a bounded live buffer. `App` composes it next to `RunStore` and wires it by properties and one
signal. This card delivers start, stop, latest-wins and the end line. Resuming, retries, the
fallback sentences and the error-type mapping are 3.3's.

## Starting point

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

## Inherited constraints

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

## Deviation from the card's wording

The card names the Run-detail input `onRunDetail`. A QML property whose name is `on` followed by
an upper-case letter cannot be assigned in an object declaration (`onRunDetail: …` is parsed as a
handler for a signal `runDetail`). The property is therefore **`inRunDetail`** (bool, default
`false`); the meaning is unchanged.

## Behaviour

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

### B1. Inputs and state

`property string backendDir`, `property bool active`, `property bool inRunDetail`,
`property var run` (null), `property var selection` (null). State properties as in the
constraint table, plain properties only the store writes (as in `RunStore`): `followKey: null`, `followStatus: "idle"`, `endStatus: ""`,
`liveText: ""`, `liveDropped: 0`, `hasOutput: false`, `followError: ""`. `followProc`: the
current follow `Process` or null (exposed for tests and for "at most one"). `signal
snapshotWanted()`.

`liveText` is `LogStream.bufferText(buffer)`, `liveDropped` is `buffer.dropped`, `hasOutput` is
`buffer.lines.length > 0 || buffer.partial !== "" || buffer.dropped > 0`; all three are updated
whenever the buffer is replaced.

### B2. Reconcile

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

### B3. Start

Bumps the launch sequence, sets `followKey` to `k`, the buffer to `emptyBuffer()` (derived
properties updated), `followStatus "connecting"`, `endStatus ""`, `followError ""`; creates one
`Process` carrying the new `launchSeq` with command

```
["python3", backendDir + "runs/runs-logs-follow.py", run.repo_dir, run.id, card_id, phase, String(attempt)]
```

(seven elements, no OFFSET), sets `followProc` to it and `running = true`.

### B4. Stop

Bumps the launch sequence, sets the current process's `running = false` (SIGTERM), sets
`followProc` null. The stopped process's later lines and exit are ignored; its `onExited` still
destroys it.

### B5. A line

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

### B6. Exit

An exit from a process that is not the current one is ignored. For the current one:
`followProc` becomes null; then when `followStatus` is `ended` or `error` nothing else changes;
otherwise (`connecting` or `following`, an exit with no end line and no error line)
`followStatus "error"` and `followError` `"Live output stopped: the helper exited with code N"`
(N the exit code). The process is destroyed after the store has seen the exit. (3.3 replaces this
branch with the 1 s / 2 s / 4 s retries.)

### B7. App wiring (`core/stores/App.qml`)

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

### B8. Docs

`docs/architecture.md`: a `RunOutputStore.qml` bullet in the Stores list after `RunStore.qml`
stating B1-B7's contract in one paragraph, and the backend paragraph's "no store runs it yet"
(`:201`) becomes "`RunOutputStore` runs it as a plain `Process`".

## Out of scope

- Resume with `--since-offset nextOffset` after the panel or Run detail, the unexpected-exit
  retries (1 s, 2 s, 4 s; the fourth within 60 s), `reconnects`, the fallback sentences and
  `unsupported`, `AmMissing` handling, a step's `UnknownAttemptError` → `ended` with
  `This step records no output`: sibling 3.3 (LO lines 177-181, 185-190).
- Any UI: the output pane's live labels, `TailScroll`, the end line, `Jump ↓`
  (LO lines 192-212; a later story). `RunDetailScreen.qml` is not edited.
- `RunStore.qml`, `runs.js`, `logStream.js`, every backend file (3.1, 2.x, 1.x; done).
- Following the run's next attempt automatically (LO line 255-256: not in this milestone).

## Tests

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

## Review focus (for the planner)

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
