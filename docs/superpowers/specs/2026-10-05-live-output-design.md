# Live run output — design

Status: proposed. Builds on `2026-10-03-am-run-monitor-design.md` (S1: Run detail and its
output pane) and on the queued milestones before it: **Align the run model with real am**
(the normalized run shape and the `tests/fixtures/am/*` fixtures), **Runs: a global
destination** (a run of any project, `run.repo_dir`), **Run events timeline** (the
`EventsPane` follow/Jump list) and **Split RunStore** (`RunStore` holds snapshot, watch,
selection and events; `RunControlStore`, `RunAlertsStore`, `RunDispatchStore` the rest).
Written against the post-split store names.

## Problem

Run detail's output pane shows one attempt's `am logs` snapshot: the last 200 lines of
stdout then stderr (`Runs.logTail`, `core/domain/runs.js:438`), labelled `snapshot <age>
ago`, with a Refresh button (`ui/screens/RunDetailScreen.qml:244-306`). Logs are fetched
on a selection, on Refresh and after a snapshot that moved the attempt's status
(`core/stores/RunStore.qml:303-364`), never as a live tail. While an attempt runs, the user
presses Refresh to see progress.

Three facts found while checking the real interfaces (installed `am`, finished run
`20261004T204141Z-cb11063d`, live run `20261005T021400Z-837c4431`):

1. **`am logs` resolves the run against `--repo-dir`, default `.`.** From a directory
   outside the repository it answers `UnknownRunError: run '…' is not in the projection for
   <cwd>`. `runs-logs.py` sends no `--repo-dir` (`core/backend/runs/runs-logs.py:56-58`,
   whose docstring says "am resolves the run by id") and the plugin's processes inherit the
   shell's working directory. The README's `am logs` shape lists `[--repo-dir DIR]`.
2. **A step has no attempts in `am status`.** Deterministic phases (`kind:
   "deterministic"`: `worktree`, `mark_in_progress`, `plan_check`, `docs_commit`, `verify`,
   `mark_done`, ...) carry `attempts: []`, and their flat rows carry `attempt: null`. Run
   detail lists attempts only (`runs.js:519-545`), so a running `verify` cannot be selected
   at all. `am logs RUN CARD --phase verify` (no `--attempt`) works: am answers a step from
   its `<phase>.N` directories on disk (`agent_manager/cli.py` `select_logs`). Only steps that
   write a log directory have one (today `verify`); `--phase worktree` or `docs_commit` is
   refused with `UnknownAttemptError: phase '…' has no recorded attempt yet`.
3. **Output arrives in bursts.** An agent harness (`claude -p`) writes little or nothing
   until it ends (the live run's `review.1` held one 498-byte line). `verify` appends one
   `==> <command> (<exit>)` section per command AFTER that command finishes
   (`agent_manager/steps/verify.py` `_log_command`), so `bash tests/run.sh` shows nothing
   until the suite ends. A live tail is still the right tool (no Refresh, and the `end`
   line), but the pane must say "waiting for output" rather than look broken.

## The `am` interface (documented, `am logs --help` and the agent-manager README "Following an attempt with `--follow`")

`am logs RUN CARD [--phase P] [--attempt N] --follow [--since-offset B] [--repo-dir DIR]`:

- First line, the hello: `{"event":"logs","offset":B,"path":…,"schema":1}`. The plugin
  never shows or reads `path` (am's on-disk layout).
- Then `{"offset":O,"text":T}` chunks: existing content first, then each append. Chunks
  are contiguous; `O` is the byte position of the chunk's first byte. am decodes UTF-8 and
  holds a split character back (UTF-8 boundaries are am's job); invalid bytes come out as
  U+FFFD.
- Last, once the attempt is terminal and the file stopped growing:
  `{"event":"end","status":S}`, exit 0. `S` ∈ `ok | schema_invalid | gate_failed |
  harness_error`. For a step: `ok` when this attempt is the phase's latest and the phase is
  `done`, otherwise `gate_failed`.
- A refusal is ONE envelope `{"ok":false,"error":{type,message}}`, exit 3, before any stream
  line (unknown run/card/phase/attempt, a step with no log, an agent attempt with no stdout
  path). Only a refusal has an `ok` key; only a stream starts with `"event":"logs"`.
- An error after the hello (the run left the projection) prints `am logs: <message>` on
  stderr, exit 3. Closing the pipe or SIGINT ends the stream with exit 0.
- Resume: `--since-offset B`, `B` = the last chunk's `offset` + the UTF-8 byte length of its
  `text` (may overcount after U+FFFD; the next chunk's `offset` is exact). `--since-offset`
  without `--follow` is a `CliError`.
- Keys are additive; unknown keys are ignored. The hello `schema` is 1; readers accept 1 or 2
  (maintainer rule for the pending `am` migration).
- An `am` without `--follow` exits 2 with a usage error on stderr and nothing on stdout.

Verified on this machine: `--follow` of `verify` (no `--attempt`) printed the hello, one
chunk and `{"event":"end","status":"ok"}`; `--since-offset 999999999` printed the hello and
the end only; the live `review.1` printed the hello and one chunk, then waited.

## Goal

While an attempt (agent or step) is running, Run detail shows its stdout as it grows,
labelled `live`, following the bottom, until am's `end` line, which the pane shows. A
finished attempt keeps today's snapshot. An `am` that cannot stream falls back to the
snapshot and says so.

## Non-goals

- No stderr stream: am's `--follow` reads stdout only (an agent's stderr is merged into
  it; a step's `stderr.log` is not). The snapshot stays the way to see a step's stderr.
- No search, copy or save in the pane; no ANSI colour rendering (control sequences are
  removed, not interpreted).
- One followed attempt at a time, panel-wide. No background tails.
- No change to the Events pane, the snapshot's 200-line cap or the watch.

## Design

### Which attempt is live

`Runs.isLiveSelection(run, sel)` (pure): true when the run's state is `running` and the
selection's attempt is in flight: an agent attempt whose status is `started`, or a step
whose phase status is `started`. Everything else (an ended attempt, a parked, dead,
escalated, cancelled/canceled or done run) is a snapshot.

A **step selection** is `{card_id, phase, attempt: 0, step: true}`: attempt 0 means
"the step's latest", sent to am as no `--attempt`. The Run detail tree lists a step row
for every deterministic phase that has started (`verify ⟳`, `docs_commit ✔`); selecting a
step whose log does not exist shows `This step records no output` (the `UnknownAttemptError`
of a step), never an error in `urgent`. `Runs.defaultAttempt` prefers the current started
phase, step or agent, so opening a run whose subtask is in `verify` opens `verify`.

### Backend: `core/backend/runs/runs-logs-follow.py`

`runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT [OFFSET]` (positional, like
`runs-logs.py`; ATTEMPT `0` omits `--attempt`; OFFSET omitted or `0` omits
`--since-offset`). Runs `am logs RUN CARD --phase PHASE [--attempt N] --follow
[--since-offset B] --repo-dir REPO` as an argv list, stdin `/dev/null`. Long-lived, one JSON
object per stdout line, flushed per line:

- am's hello, chunk and end lines, re-emitted as parsed JSON objects (compact), never
  altered; a line that is not a JSON object is skipped and counted.
- am's refusal envelope, unchanged, as the only line.
- Its own last line on a failure: `{"ok":false,"error":{"type","message"}}` with type
  `AmMissing` (not on PATH), `FollowUnsupported` (am exited 2 before printing anything:
  an `am` without `--follow`), `SchemaMismatch` (hello `schema` not 1 or 2; am is stopped),
  `StreamError` (am exited non-zero after the hello; the message is am's stderr line),
  `HelperError` (anything else), `Usage` (exit 2).
- SIGTERM (the store stopping it) terminates am, waits up to 2 s, kills it, and exits 0 with
  nothing more printed. Exit 0 on every other path except Usage.

Only the documented `am logs` command is used; no file under am's data dir is opened.

`runs-logs.py` (the snapshot) gets the same two rules: it takes REPO first and passes
`--repo-dir`, and ATTEMPT `0` omits `--attempt` (a step). If the Align milestone already
passes the repository, its argument order is kept and only the step rule is added.

### Domain: `core/domain/logStream.js` (pure, never throws)

- `sanitize(text)`: removes ANSI CSI (`ESC [ … final`), OSC (`ESC ] … BEL|ESC \`) and other
  `ESC` sequences; turns `\r\n` into `\n`; a lone `\r` keeps only what follows it on that
  line (a progress bar's last frame); drops every other C0 control except `\t` and `\n`, and
  DEL. U+FFFD is kept.
- `utf8Length(text)`: the UTF-8 byte length (for the resume offset).
- `emptyBuffer(maxLines)`: `{lines: [], partial: "", dropped: 0, nextOffset: 0,
  gapBytes: 0, maxLines}`; a bad `maxLines` is 1000.
- `foldLine(buffer, line)` → `{buffer, kind}` with kind `hello | chunk | end | refusal |
  ignored`. A chunk is sanitized, joined to `partial`, split on `\n`; complete lines are
  appended, the unterminated tail stays `partial`. A line longer than 2000 characters is cut
  to 2000 plus `…`. Lines beyond `maxLines` are dropped from the front and counted in
  `dropped`. A chunk whose `offset` is below `nextOffset` (a duplicate after a resume) is
  ignored; one above it adds the gap to `gapBytes` and a `[… N bytes not shown]` line.
  `nextOffset` becomes `offset + utf8Length(text)`. A hello sets `nextOffset` to its
  `offset` when the buffer is empty.
- `bufferText(buffer)`: the lines plus `partial`, prefixed with `… N earlier lines` when
  `dropped > 0`.

### Store: `core/stores/RunOutputStore.qml` (new)

Imports QtQml, Quickshell, Quickshell.Io and `../domain/logStream.js`, `../domain/runs.js`.
Owns the one follow process and nothing else; the snapshot logs stay in `RunStore`.
`App` hands it `backendDir`, `active` (panel open), `onRunDetail` (view mode `run`),
`run` (the selected run, normalized) and `selection` (`RunStore.selectedAttempt`), and
routes its `snapshotWanted()` to `RunStore.refreshLogs()`.

State: `followKey` (`{run_id, card_id, phase, attempt}` or null), `followStatus`
(`idle | connecting | following | ended | unsupported | error`), `endStatus` (am's
`S`, `""` until the end), `liveText` (`bufferText`), `liveDropped`, `hasOutput`,
`followError`, `reconnects`. A plain `Process` with a `SplitParser`, like the watch
(`RunStore.qml:1016-1020`): one line, one `foldLine`.

- **Start**: while `active && onRunDetail` and `Runs.isLiveSelection(run, selection)`, the
  store follows that selection from offset 0 with `run.repo_dir`. A different selection
  stops the current process first (latest wins). At most one process exists.
- **Stop**: a selection that is not live, leaving Run detail, another run, or the panel
  closing stops the process (SIGTERM through `running = false`). A stop because of the
  panel or Run detail keeps the buffer and the key; anything else clears them.
- **Resume**: coming back (panel reopened, Run detail re-entered) to the same key whose
  status was `following` restarts with `nextOffset`. An unexpected exit (no end line, not
  stopped by the store, not a refusal) restarts after 1 s, 2 s, 4 s with `nextOffset`; a
  fourth exit within 60 s sets `error` with `Live output stopped: <reason>`. A good chunk
  resets the count.
- **End**: the end line sets `ended` and `endStatus`. For an agent attempt the buffer stays
  (stderr is already in it). For a step the store emits `snapshotWanted()` once, because the
  step's stderr is only in the snapshot, and the pane shows the snapshot.
- **Fallback**: `FollowUnsupported` and `SchemaMismatch` set `unsupported` with the sentence
  (`This am cannot stream output (am logs --follow is missing)` / `Unknown output stream
  schema N`) and emit `snapshotWanted()`; no reconnect. `AmMissing` is `RunStore.amStatus`'s
  `missing` and stops. A refusal or `StreamError` sets `error` with `Runs.errorText`; a step's
  `UnknownAttemptError` sets `ended` with `endStatus` `""` and the sentence `This step records
  no output`.

### UI

```
┌ Output · adff6c85-… implement.2 ─────────────────────────────────────────────┐
│ ⟳ live · following                                              [Jump ↓]     │
│ … 312 earlier lines                                                          │
│ Running uv run pytest                                                        │
│ ........................................ [ 61%]                             │
└──────────────────────────────────────────────────────────────────────────────┘
```

- The label line reads `⟳ live` (glyph from `runGlyphs.js`) while following, `⟳ live ·
  waiting for output` before the first chunk, `ended · <status>` after the end line
  (`gate_failed`, `schema_invalid`, `harness_error` in `urgent` with `‼`), `snapshot <age>
  ago` for a snapshot, and the fallback sentence before `snapshot …` when `unsupported`.
  Refresh is shown for a snapshot only.
- The text has its own bounded height and scrolling, using the follow-the-bottom list the
  Events pane introduced, extracted first into a shared component (`TailScroll`): it follows
  new text while scrolled to the bottom; scrolled up it stays put and shows `Jump ↓`.
- The end line is drawn as the pane's last line (`— ended: ok —`), not mixed into the text.
- The step row in the tree reads `verify` with its phase glyph and no attempt number.

## Limits and failure modes

| case | behaviour |
|---|---|
| `am` without `--follow` | snapshot, with the fallback sentence; Refresh works |
| hello schema not 1 or 2 | same, `Unknown output stream schema N` |
| `am` missing | Run detail's missing state (S1) |
| step that writes no log | `This step records no output` |
| agent harness quiet until its end | `⟳ live · waiting for output` |
| the run left the projection mid-stream | `error`, am's message |
| helper or am killed | resume from `nextOffset`, 3 tries |
| a very long output | 1000 lines held, `… N earlier lines` |
| a run started in another repository | `--repo-dir` is that run's `repo_dir` |
| two attempts selected quickly | the older process is stopped; its late lines are dropped |

## Testing

- `tests/contract/test_am_shapes.py`: the installed `am logs --help` lists `--follow` and
  `--since-offset` (fails loudly when not; skipped only when `am` is absent); a recorded
  stream of an agent attempt and of `verify` in a throwaway journal pins the hello, chunk and
  end keys; the refusal for a step without a log; recorded fixtures
  `tests/fixtures/am/logs-follow-agent.jsonl`, `logs-follow-step.jsonl`,
  `logs-follow-refusal.json`.
- `tests/core/domain/tst_log_stream.qml`: `sanitize` (CSI, OSC, `\r\n`, lone `\r`, C0,
  U+FFFD kept), `utf8Length`, `foldLine` for every kind, partial lines across chunks,
  the cap and `dropped`, long-line cut, duplicate and gap offsets, the fixtures.
- `tests/core/domain/tst_runs.qml`: step rows in `runTree`, `defaultAttempt` on a started
  step, `isLiveSelection` for every state, `cancelled` and `canceled`.
- `tests/core/backend/runs/test_runs_logs_follow.py` (fake `am`): argv with and without
  `--attempt` and `--since-offset`, `--repo-dir`, line passthrough, refusal passthrough,
  each error type, SIGTERM stops am and exits 0. `test_runs_logs.py`: REPO and the step rule.
- `tests/core/stores/tst_run_output_store.qml`: start on a live selection, stop on each
  trigger, latest wins, end for an agent and for a step, resume with `nextOffset` after the
  panel reopens and after a crash, the retry limit, the fallback emits `snapshotWanted()`.
  `tst_run_store.qml`: selecting a step.
- `tests/ui/`: `TailScroll` (follow, Jump), the pane's labels for each status, the end line,
  the step row, Refresh only for a snapshot.

## Open questions

- Does Align already pass `--repo-dir` to `runs-logs.py`? The card handles both.
- Should the pane move to the run's next attempt by itself when the followed attempt ends
  (a "follow the run" mode)? Not in this milestone: the selection stays where the user put it.
