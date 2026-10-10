# 3.3 RunOutputStore: recovering a broken follow — spec

Card `2bce8772-3ef5-4511-b8bc-6209c29f6b4f`, subtask of story `053768a8-6bfd-4141-8c91-918e98ea4cf5`
(Live output store). Parent design: `docs/superpowers/specs/2026-10-05-live-output-design.md`
(below: **LO**). Builds on 3.2 (`354d3953-…`, spec
`docs/superpowers/specs/3-2-runoutputstore-354d3953.md`: start, stop, latest wins, the end line,
App composition).

## Purpose

`core/stores/RunOutputStore.qml` follows a live attempt but gives up on every interruption: a
return to Run detail starts again from offset 0 into an empty buffer, any exit before the end
line is an error, and every `{"ok": false}` line is an error. This card makes the follow
recover: resume from the buffer's `nextOffset`, restart after a crash with a 1 s / 2 s / 4 s
backoff and a limit, and map each typed failure of `runs-logs-follow.py` to the state LO asks
for (unsupported with a sentence plus a snapshot request, stop, error, or a step's "no output").

## Starting point (as of `e643fc3`)

- `RunOutputStore.qml`: `reconcile()` (`:97-115`) restarts a same-key return with `start(k)`;
  `start(k)` (`:118-130`) always resets the buffer (`setBuffer(LogStream.emptyBuffer())`) and
  builds a 7-element argv; `followLine()` (`:149-169`) sets `error` + `Runs.errorText` for every
  refusal; `followExited()` (`:173-179`) sets `error` with `Live output stopped: the helper exited
  with code N`. The header comment (`:7-26`) states those rules.
- `core/domain/logStream.js`: `foldLine` returns kind `chunk` only for an accepted chunk (a
  duplicate below `nextOffset` is `ignored`, `:147`); `buffer.nextOffset` is the resume offset
  (`offset + utf8Length(text)`); a hello sets `nextOffset` only on an empty buffer.
- `core/backend/runs/runs-logs-follow.py`: `REPO RUN CARD PHASE ATTEMPT [OFFSET]`, an absent or
  `0` OFFSET omits `--since-offset`. Its own failure line is `{"ok": false, "error": {type,
  message}}` with type `AmMissing` (`am is not installed.`), `FollowUnsupported`,
  `SchemaMismatch` (message exactly `am logs speaks schema <json>; this helper reads schema 1 or
  2.`, `:107-108`), `StreamError`, `HelperError`, `Usage`; am's own refusal envelope (e.g.
  `UnknownAttemptError`, `tests/fixtures/am/logs-follow-refusal.json`) passes through unchanged.
  It exits 0 on every path but `Usage`.
- `core/domain/runs.js:507` `errorText(value)` → `"Type: message"`.
- `core/stores/BoardStore.qml:19-21,74` injects a clock as `property real nowMs: 0` (0 = real
  time); `BoardStore.qml:42,212-218` and `RunStore.qml:225-234` alias their Timers with an
  `objectName` so tests read `interval`/`running` and call `triggered()`.
- `docs/architecture.md:94` describes the store's contract, including the two rules this card
  replaces ("starts again from offset 0", "an exit before the end line sets `error`").
- App wiring (`App.qml`, `snapshotWanted()` → `runs.refreshLogs()`) is done; no App change.

## Inherited constraints

| constraint | source |
|---|---|
| State includes `reconnects`. | LO line 166-168 |
| Resume: coming back (panel reopened, Run detail re-entered) to the same key whose status was `following` restarts with `nextOffset`. | LO lines 177-178 |
| An unexpected exit (no end line, not stopped by the store, not a refusal) restarts after 1 s, 2 s, 4 s with `nextOffset`; a fourth exit within 60 s sets `error` with `Live output stopped: <reason>`. A good chunk resets the count. | LO lines 178-181; table line 224 ("resume from `nextOffset`, 3 tries") |
| `FollowUnsupported` / `SchemaMismatch` set `unsupported` with `This am cannot stream output (am logs --follow is missing)` / `Unknown output stream schema N` and emit `snapshotWanted()`; no reconnect. | LO lines 185-187; table lines 218-219 |
| `AmMissing` is `RunStore.amStatus`'s `missing` and stops (Run detail's missing state, not the store's error). | LO lines 187-188; table line 220 |
| A refusal or `StreamError` sets `error` with `Runs.errorText`. | LO line 188; table line 223 |
| A step's `UnknownAttemptError` sets `ended` with `endStatus` `""` and the sentence `This step records no output`. | LO lines 189-190, 108-109; table line 221 |
| Argv `REPO RUN CARD PHASE ATTEMPT [OFFSET]`, OFFSET `0` or absent omits `--since-offset`. | LO lines 114-116 |
| Store imports only QtQml, Quickshell, Quickshell.Io, `../domain/logStream.js`, `../domain/runs.js` (Timer comes from QtQml). | LO line 159; `tests/architecture/test_layers.py` |
| Stop rules, latest wins, end line, at most one process: unchanged from 3.2. | LO lines 171-176, 182-184, 227 |
| `tests/architecture` passes; docstrings/comments state the contract only, no narrative; `bash tests/run.sh` green; TDD. | card description |

## Behaviour

Terms from 3.2 are unchanged (selection key, equal keys, *live* = `Runs.isLiveSelection`,
*present* = `active && inRunDetail`, *can start* = key non-null, present, live, non-empty
`run.repo_dir`).

### New state

| property | type | meaning |
|---|---|---|
| `reconnects` | int, default 0 | unexpected exits counted toward the limit (see Backoff); 0 after a good chunk or a key change |
| `nowMs` | real, default 0 | the clock the 60 s window reads, epoch ms; 0 means `Date.now()` (same convention as `BoardStore.nowMs`) |
| `retryTimer` | `readonly property alias` to a `Timer` with `objectName: "retryTimer"`, `repeat: false` | the pending restart; `running` while one is scheduled |

The store also keeps the times of the counted exits (a private list); its shape is not part of
the contract.

### Starting a follow

`start(k, offset)` launches `runs-logs-follow.py` for key `k`:

- argv `["python3", backendDir + "runs/runs-logs-follow.py", run.repo_dir, run_id, card_id,
  phase, String(attempt)]`, plus `String(offset)` as an 8th element **only when `offset > 0`**
  (7 elements otherwise, so every existing argv assertion still holds);
- `followStatus` `connecting`, `endStatus` `""`, `followError` `""`, a fresh launch seq;
- the buffer is **not** touched by `start`. A new key reaches `start` only after `clear()`
  (empty buffer, `reconnects` 0), so a fresh key still begins at offset 0 with an empty buffer;
  a resume keeps the buffer it continues.

### Resume on return

`reconcile()` on the same key, present, no process, and `followStatus` `connecting` or
`following`:

- not live → `clear()` (unchanged from 3.2; it also cancels a pending restart);
- a restart is pending (`retryTimer.running`) and the selection is live → nothing; the pending
  restart stays in charge (a new snapshot of the same run during the backoff must not start a
  process early);
- can start → `start(followKey, buffer.nextOffset)`.

`followStatus` `ended`, `error`, `unsupported`, or `idle` with a held key (AmMissing, below) →
nothing restarts.

Leaving presence (panel closed, Run detail left) stops the process as before **and cancels a
pending restart**; the key, the buffer, `followStatus` and `reconnects` stay, so the return
resumes immediately from `nextOffset`.

A key change, `clear()` and `stop()` cancel a pending restart; `clear()` also sets `reconnects`
to 0 and forgets the counted exits.

### Unexpected exit and backoff

`followExited(proc, code)` of the current process (stopped processes stay ignored): the process
is gone (`followProc` null). Then:

- `followStatus` is not `connecting`/`following` (it ended, failed, fell back, or stopped on
  AmMissing) → nothing more;
- otherwise it is an unexpected exit at time *t* (`nowMs` or `Date.now()`): counted exits with
  *t − e ≥ 60000* are dropped, *t* is added, `reconnects` = the number of counted exits.
  - `reconnects` ≤ 3 → `retryTimer.interval` = 1000 · 2^(reconnects − 1) (1000, 2000, 4000) and
    the timer starts. `followStatus`, `followKey` and the buffer stay.
  - `reconnects` = 4 → `followStatus` `error`, `followError` `Live output stopped: the helper
    exited with code <code>`, no timer.

When `retryTimer` fires: `followKey` still equals the current selection key and can start →
`start(followKey, buffer.nextOffset)`; same key but not live → `clear()`; otherwise nothing
(a key change or leaving presence already cancelled it).

A **good chunk** — a line `LogStream.foldLine` returns as kind `chunk` — sets `reconnects` to 0
and forgets the counted exits. A hello, a duplicate chunk (`ignored`) or an unparseable line is
not a good chunk.

### Typed failure lines

A line folding to kind `refusal`, read while `followStatus` is `connecting` or `following`,
maps on `value.error.type` (a missing or non-string type is "other"):

| type | `followStatus` | `endStatus` | `followError` | `snapshotWanted()` |
|---|---|---|---|---|
| `FollowUnsupported` | `unsupported` | `""` | `This am cannot stream output (am logs --follow is missing)` | once |
| `SchemaMismatch` | `unsupported` | `""` | `Unknown output stream schema N` | once |
| `AmMissing` | `idle` (key and buffer kept) | `""` | `""` | no |
| `UnknownAttemptError`, followed key's `attempt` is 0 (a step) | `ended` | `""` | `This step records no output` | no |
| anything else (`StreamError`, `HelperError`, `Usage`, am refusals, an agent's `UnknownAttemptError`, no type) | `error` | unchanged | `Runs.errorText(value)` | no |

- **N** is the text of `error.message` between the prefix `am logs speaks schema ` and the first
  following `;` (e.g. `3`, `null`, `"1"`). A message without that shape gives the sentence
  `Unknown output stream schema` with nothing after it.
- In every row the buffer stays and no restart is scheduled; the helper's exit that follows
  changes nothing. Lines after any of these are ignored (`followLine` ignores lines unless the
  status is `connecting` or `following`).
- `AmMissing` leaves the store silent: Run detail shows `RunStore.amStatus` `missing`. Because
  the key is held with `idle`, neither a new snapshot nor a return restarts it; a new key does.

### Unchanged

Start conditions, stop rules, latest wins, the end line (`ended`, `endStatus`, one
`snapshotWanted()` for a step), "a key that stops being live keeps its process until the end
line or the exit", at most one process.

### Contract text

The header comment of `RunOutputStore.qml` and `docs/architecture.md:94` are updated to state
the rules above (resume offset, backoff 1/2/4 s with the 4-in-60-s limit and the good-chunk
reset, the typed-failure table, `reconnects`, `nowMs`, `retryTimer`), replacing "from offset 0"
on return and "an exit before the end line is an error". Contract only, no narrative.

## Tests

All in `tests/core/stores/tst_run_output_store.qml` (QtTest, run by `bash tests/run.sh`). Tier
reason for every row: the behaviour is the store's state machine driven by stubbed `Process`
objects and the aliased timer — no real process or wall clock is needed, and the domain
(`logStream.js`, `runs.js`) and helper already have their own tiers. Tests never wait on the
real timer: they read `retryTimer.interval`/`running`, call `retryTimer.triggered()`, and
`retryTimer.stop()` at the end of any test that leaves one running; the clock is pinned with
`store.nowMs`.

Existing tests to update (they encode the rules this card replaces):

- `test_an_exit_with_no_end_line` → becomes the first backoff step (status stays `following`,
  `retryTimer.running`, interval 1000, buffer kept, `followError` `""`).
- `test_leaving_run_detail_stops_and_keeps_then_returning_restarts` and
  `test_closing_the_panel_stops_and_keeps_then_reopening_restarts` → argv after the return ends
  `|explore|1|28` (hello + `chunkLine` gives `nextOffset` 28), buffer still
  `stub claude ok phase=review`.
- `test_an_ended_or_failed_follow_survives_leave_and_return` → its "failed" half reaches `error`
  through a refusal line (or four exits) instead of one exit.
- `test_at_most_one_follow_process_runs` keeps passing unchanged (no chunk is sent, offsets stay 0).

New tests:

| # | test | asserts |
|---|---|---|
| N1 | resume offset after the panel reopens | hello + chunk, `active=false`, `active=true` → one new process, 8-element argv ending `|explore|1|28`, `liveText` kept, `connecting`; a later chunk `{"offset":28,"text":"more\n"}` appends `more` |
| N2 | resume offset after Run detail re-entry | same through `inRunDetail` |
| N3 | resume with nothing read omits the offset | only a hello (offset 0), leave and return → 7-element argv |
| N4 | resume after a crash | chunk, `exited(0)` → `followProc` null, `reconnects` 1, `retryTimer.running`, interval 1000; `triggered()` → new process, argv ends `|28`, buffer kept |
| N5 | backoff timings | pinned `nowMs`; exits 1, 2, 3 (each followed by `triggered()`) give intervals 1000, 2000, 4000 and `reconnects` 1, 2, 3 |
| N6 | the retry limit | fourth exit within 60 s → `error`, `followError` `Live output stopped: the helper exited with code 0` (code 1 variant also), `retryTimer.running` false, no new process, buffer kept |
| N7 | a good chunk resets the count | two exits, then a new chunk on the restarted process → `reconnects` 0; next exit → interval 1000 |
| N8 | a hello or a duplicate chunk is not a good chunk | a chunk (offset 0, `nextOffset` 28), then two exits (pinned `nowMs`); on the restarted process a hello and a chunk at offset 0 (a duplicate, below `nextOffset`); `reconnects` still 2; next exit → interval 4000 |
| N9 | exits older than 60 s fall out of the window | `nowMs` is never 0 (0 reads the real clock): exits at 10000, 11000, 13000, then at 80000 → `reconnects` 1, interval 1000; and, in a second store, a fourth exit at 69999 after exits at 10000, 11000, 13000 still counts (→ `error`), while one at 70000 drops the first (→ `reconnects` 3, interval 4000) |
| N10 | a pending restart is cancelled | for each of: leaving Run detail, closing the panel, another selection, another run, a non-live selection → `retryTimer.running` false and calling `triggered()` afterwards starts no process for the old key; leave/return resumes at once with the offset |
| N11 | a new snapshot during the backoff starts nothing | exit, then `store.run = startedRun()` → no new process, timer still running |
| N12 | a key that stops being live during the backoff clears | exit, then `store.run = exploreOkRun()` → `clear()`: key null, `idle`, `liveText` `""`, `reconnects` 0, `retryTimer.running` false; a stray `retryTimer.triggered()` afterwards starts no process |
| N13 | FollowUnsupported falls back | envelope `{"ok":false,"error":{"type":"FollowUnsupported","message":"am logs cannot follow (exit 2)."}}` → `unsupported`, sentence, spy count 1; `exited(0)` → no timer, no process; leave/return → no process |
| N14 | SchemaMismatch falls back with N | message `am logs speaks schema 3; this helper reads schema 1 or 2.` → `Unknown output stream schema 3`, spy count 1, no retry; message `weird` → `Unknown output stream schema` |
| N15 | AmMissing stops silently | → `idle`, `followError` `""`, key kept, spy 0; `exited(0)` → no timer; new snapshot or leave/return → no process; another selection → starts normally |
| N16 | a refusal and a StreamError are errors | the refusal fixture on an agent attempt (`explore.1`) → `error`, `Runs.errorText(envelope)`; `{"ok":false,"error":{"type":"StreamError","message":"am logs: run left"}}` → `error`, `StreamError: am logs: run left`; exits after → no timer |
| N17 | a step's UnknownAttemptError has no output | `verifyStep()` + the refusal fixture → `ended`, `endStatus` `""`, `followError` `This step records no output`, spy 0, no retry, no restart on return |
| N18 | lines after a fallback or AmMissing are ignored | a chunk after `unsupported` / `idle` leaves `liveText` unchanged |

Tier for all: QML store test (`tests/core/stores/`); `tests/architecture` must stay green
(no new component, no glyphs, imports unchanged).

## Out of scope

- The UI labels for `unsupported`, `ended` with the step sentence, and `error` (pane work, a
  later card); `TailScroll`.
- `RunStore.amStatus` and its `missing` state (exists); `RunStore.refreshLogs()` (exists).
- Any change to `runs-logs-follow.py`, `logStream.js`, `runs.js`, `App.qml`, fixtures.
- A "follow the run" mode (LO open question, line 255).
