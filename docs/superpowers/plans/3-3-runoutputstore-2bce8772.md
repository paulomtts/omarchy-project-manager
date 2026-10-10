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

---

# 3.3 RunOutputStore: recovering a broken follow — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `core/stores/RunOutputStore.qml` resumes a follow from the buffer's `nextOffset`, restarts after an unexpected helper exit with a 1 s / 2 s / 4 s backoff (four exits within 60 s is an error), and maps each typed `{"ok": false}` line of `runs-logs-follow.py` to the state the live-output design asks for.

**Architecture:** All changes live in one QML store and its QtTest file. `start(k, offset)` stops resetting the buffer and appends OFFSET when > 0; a `Timer` (`retryTimer`, aliased for tests) drives restarts; `followExited` counts exits in a 60 s window read from `nowMs`; a new `refuse(value)` maps `error.type` to `unsupported` / `idle` / `ended` / `error`. The header comment and `docs/architecture.md:94` are rewritten to state the new contract.

**Tech Stack:** QML (QtQml, Quickshell, Quickshell.Io), plain JS domain modules (`core/domain/logStream.js`, `core/domain/runs.js`), QtTest via `qmltestrunner`, pytest for `tests/architecture`.

**Spec:** `docs/superpowers/specs/3-3-runoutputstore-2bce8772.md` (prepended above).

## Global Constraints

- Store imports only `QtQml`, `Quickshell`, `Quickshell.Io`, `../domain/logStream.js`, `../domain/runs.js` (`Timer` comes from `QtQml`); `tests/architecture` must pass.
- Argv `REPO RUN CARD PHASE ATTEMPT [OFFSET]`: OFFSET is appended as `String(offset)` **only when `offset > 0`** (7 elements otherwise).
- Backoff intervals exactly `1000`, `2000`, `4000` ms; the 4th exit with `t − e < 60000` for the 3 earlier ones is `error`; an exit with `t − e ≥ 60000` is dropped from the window.
- `nowMs` 0 means `Date.now()` (same convention as `BoardStore.nowMs`).
- Exact sentences: `Live output stopped: the helper exited with code <code>`, `This am cannot stream output (am logs --follow is missing)`, `Unknown output stream schema N` / `Unknown output stream schema`, `This step records no output`.
- Stop rules, latest wins, end line, at most one process: unchanged from 3.2.
- Docstrings/comments state the contract only, no narrative; TDD; `bash tests/run.sh` green.
- No change to `runs-logs-follow.py`, `logStream.js`, `runs.js`, `App.qml`, fixtures.

## Review Focus

1. Leaving a key while its restart is pending and coming back to it later (via another selection) must start fresh: offset 0 (7-element argv), empty buffer, `reconnects` 0 — not resume a stale buffer. → Task 3, `test_away_during_the_wait_and_back_starts_fresh`.
2. On a resume, am's hello repeats the resume offset (`"offset":28`) on a non-empty buffer: it must not reset `nextOffset` or insert a "bytes not shown" gap; the next chunk at 28 appends cleanly. → Task 1, `test_returning_to_run_detail_resumes_from_next_offset`.
3. A stray `retryTimer` fire after the follow already failed (four exits) must start nothing. → Task 2, `test_the_fourth_exit_within_60_s_is_an_error`.
4. `SchemaMismatch` with an odd schema value (`null`, `"1"`) or a non-string message must still produce a sentence and fall back, not throw. → Task 4, `test_schema_mismatch_falls_back_with_its_schema`.
5. A malformed refusal envelope (`{"ok":false,"error":"boom"}`, `{"ok":false}`) must be an `error` with `Runs.errorText`, not a TypeError on `value.error.type`. → Task 4, `test_a_refusal_or_a_stream_error_is_an_error`.

## How to run the store tests

Run the store's QML test file directly (fast, ~0.3 s) from the worktree root:

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_output_store.qml 2>&1 | grep -E "^(FAIL|Totals)|^   Loc|TypeError|ReferenceError"
```

A single test: append `StoresRunOutputStore::test_name` after the `.qml` path. A `TypeError` or `ReferenceError` line counts as a failure (`tests/run.sh` treats it as one). The full gate is `timeout 600 bash tests/run.sh` (pytest ~2.5 min, then every QML test).

## File Structure

- Modify: `core/stores/RunOutputStore.qml` — the store (header comment `:7-26`, properties `:30-45`, `clear` `:84-90`, `reconcile` `:97-115`, `start` `:118-130`, `stop` `:133-137`, `followLine` `:149-169`, `followExited` `:173-179`, new `retry`, `refuse`, `schemaSentence`, a `Timer`).
- Modify: `tests/core/stores/tst_run_output_store.qml` — update 4 existing tests, add N1–N18 and Review Focus tests.
- Modify: `docs/architecture.md:94` — the store's contract paragraph.

---

### Task 1: Resume from `nextOffset`

**Files:**
- Modify: `core/stores/RunOutputStore.qml:92-130` (`reconcile`, `start`)
- Test: `tests/core/stores/tst_run_output_store.qml`

**Interfaces:**
- Consumes: `LogStream.foldLine`, `store.buffer.nextOffset` (existing).
- Produces: `start(k, offset)` — `k` a followed key `{run_id, card_id, phase, attempt}`, `offset` a non-negative int; does not touch the buffer; argv gets `String(offset)` as 8th element only when `offset > 0`. Test constants `tc.resumeHello`, `tc.moreLine`.

- [ ] **Step 1: Add test constants**

In `tests/core/stores/tst_run_output_store.qml`, right after the `chunkLine` property (line 23), add:

```qml
  // A hello on a resumed follow: am repeats the offset it resumes from.
  readonly property string resumeHello: '{"event":"logs","offset":28,"path":"/x/stdout.log","schema":1}'
  // The chunk right after chunkLine (which ends at byte 28).
  readonly property string moreLine: '{"offset":28,"text":"more\\n"}'
```

- [ ] **Step 2: Update the two T6 tests to expect the resume offset**

In `test_leaving_run_detail_stops_and_keeps_then_returning_restarts`, replace the last two lines

```qml
    compare(argv(store.followProc), tc.followCmd + tc.runId + "|" + tc.openCard + "|explore|1")
    compare(store.followStatus, "connecting")
```

with

```qml
    compare(store.followProc.command.length, 8, "OFFSET")
    compare(argv(store.followProc), tc.followCmd + tc.runId + "|" + tc.openCard + "|explore|1|28")
    compare(store.liveText, "stub claude ok phase=review", "the buffer it resumes")
    compare(store.followStatus, "connecting")
```

Make the identical replacement in `test_closing_the_panel_stops_and_keeps_then_reopening_restarts` (same two lines at its end, same four replacement lines).

- [ ] **Step 3: Write the new tests N1–N3 (N2 carries Review Focus 2)**

Append inside the `TestCase`, before its closing `}`:

```qml
  // N1
  function test_reopening_the_panel_resumes_from_next_offset() {
    var store = following(); if (!store) return
    var seen = recorder(store)
    var old = store.followProc
    send(old, streamLines("logs-follow-agent.jsonl")[0])
    send(old, tc.chunkLine)
    compare(store.buffer.nextOffset, 28)
    store.active = false
    store.active = true
    compare(seen.length, 1, "exactly one new process")
    var proc = store.followProc
    compare(proc.command.length, 8)
    compare(argv(proc), tc.followCmd + tc.runId + "|" + tc.openCard + "|explore|1|28")
    compare(store.liveText, "stub claude ok phase=review")
    compare(store.followStatus, "connecting")
    send(proc, tc.moreLine)
    compare(store.liveText, "stub claude ok phase=review\nmore")
    compare(store.followStatus, "following")
  }

  // N2, Review Focus 2 (3.3): the resumed hello repeats offset 28
  function test_returning_to_run_detail_resumes_from_next_offset() {
    var store = following(); if (!store) return
    var seen = recorder(store)
    var old = store.followProc
    send(old, streamLines("logs-follow-agent.jsonl")[0])
    send(old, tc.chunkLine)
    store.inRunDetail = false
    store.inRunDetail = true
    compare(seen.length, 1, "exactly one new process")
    var proc = store.followProc
    compare(proc.command.length, 8)
    compare(argv(proc), tc.followCmd + tc.runId + "|" + tc.openCard + "|explore|1|28")
    send(proc, tc.resumeHello)
    compare(store.buffer.nextOffset, 28, "the hello does not move the offset")
    compare(store.liveText, "stub claude ok phase=review", "no gap marker")
    send(proc, tc.moreLine)
    compare(store.liveText, "stub claude ok phase=review\nmore")
  }

  // N3
  function test_resuming_with_nothing_read_omits_the_offset() {
    var store = following(); if (!store) return
    var seen = recorder(store)
    send(store.followProc, streamLines("logs-follow-agent.jsonl")[0])
    store.inRunDetail = false
    store.inRunDetail = true
    compare(seen.length, 1)
    compare(store.followProc.command.length, 7, "no OFFSET at 0")
    compare(argv(store.followProc), tc.followCmd + tc.runId + "|" + tc.openCard + "|explore|1")
  }
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_output_store.qml 2>&1 | grep -E "^(FAIL|Totals)|^   Loc|TypeError|ReferenceError"`

Expected: FAIL for `test_leaving_run_detail_stops_and_keeps_then_returning_restarts`, `test_closing_the_panel_stops_and_keeps_then_reopening_restarts`, `test_reopening_the_panel_resumes_from_next_offset`, `test_returning_to_run_detail_resumes_from_next_offset` (command length 7, not 8). `test_resuming_with_nothing_read_omits_the_offset` passes already (it pins that offset 0 stays out of argv).

- [ ] **Step 5: Implement `start(k, offset)` and the resume in `reconcile`**

In `core/stores/RunOutputStore.qml`, replace the comment + `reconcile()` + comment + `start(k)` block (lines 92-130) with:

```qml
  // Another key: stop, clear, and start when it can be followed. The same key
  // off Run detail or with the panel closed: stop and keep the rest. The same
  // key back with no process: resume it from the buffer's nextOffset while
  // live (clear once it is not), unless it ended or failed. A running process
  // of the same key is left alone.
  function reconcile() {
    var k = store.selectionKey(store.run, store.selection)
    if (!store.sameKey(k, store.followKey)) {
      if (store.followProc) store.stop()
      store.clear()
      if (store.canStart(k)) store.start(k, 0)
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
    if (store.canStart(k)) store.start(k, store.buffer.nextOffset)
    else if (!store.isLive()) store.clear()
  }

  // runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT, plus OFFSET when offset
  // > 0. The buffer is kept: a new key reaches here only after clear().
  function start(k, offset) {
    store.followSeq += 1
    store.followKey = k
    store.followStatus = "connecting"
    store.endStatus = ""
    store.followError = ""
    var proc = followC.createObject(store, { launchSeq: store.followSeq })
    var command = ["python3", store.backendDir + "runs/runs-logs-follow.py", store.run.repo_dir,
                   k.run_id, k.card_id, k.phase, String(k.attempt)]
    if (offset > 0) command.push(String(offset))
    proc.command = command
    store.followProc = proc
    proc.running = true
  }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_output_store.qml 2>&1 | grep -E "^(FAIL|Totals)|^   Loc|TypeError|ReferenceError"`

Expected: `Totals: 28 passed, 0 failed` (26 test functions plus initTestCase/cleanupTestCase), no FAIL, no TypeError/ReferenceError lines.

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunOutputStore.qml tests/core/stores/tst_run_output_store.qml
git commit -m "feat(stores): RunOutputStore resumes a returning follow from nextOffset"
```

---

### Task 2: Restart after an unexpected exit, with backoff and a limit

**Files:**
- Modify: `core/stores/RunOutputStore.qml` (properties after line 45; `start`; `followExited`; new `retry`; new `Timer` before the `followC` Component)
- Test: `tests/core/stores/tst_run_output_store.qml`

**Interfaces:**
- Consumes: `start(k, offset)` from Task 1; `canStart(k)`, `isLive()`, `selectionKey`, `sameKey`, `clear()` (existing).
- Produces: `property int reconnects` (default 0), `property real nowMs` (default 0), `property var exitTimes` (private list of epoch ms), `readonly property alias retryTimer` (a `Timer`, `objectName: "retryTimer"`, `repeat: false`, `onTriggered: store.retry()`), `function retry()`. Test helpers `crash(store, code)` and `crashesAt(store, times)`.

- [ ] **Step 1: Add the test helpers**

In `tests/core/stores/tst_run_output_store.qml`, after the `runningCount` function, add:

```qml
  // The current follow process exits with `code` (0 by default).
  function crash(store, code) { store.followProc.exited(code === undefined ? 0 : code) }

  // One exit at each epoch-ms time in `times`, each followed by its restart.
  function crashesAt(store, times) {
    for (var i = 0; i < times.length; i++) {
      store.nowMs = times[i]
      crash(store)
      store.retryTimer.triggered()
    }
  }
```

- [ ] **Step 2: Rewrite T16 as the first backoff step**

Replace the whole `test_an_exit_with_no_end_line` function with:

```qml
  // T16
  function test_an_exit_with_no_end_line() {
    var store = following(); if (!store) return
    var proc = store.followProc
    send(proc, tc.chunkLine)
    proc.exited(0)
    compare(store.followProc, null)
    compare(store.followStatus, "following", "a restart is pending, not an error")
    compare(store.followError, "")
    compare(store.reconnects, 1)
    compare(store.retryTimer.running, true)
    compare(store.retryTimer.interval, 1000)
    compare(store.liveText, "stub claude ok phase=review")
    store.retryTimer.stop()
  }
```

- [ ] **Step 3: Rewrite the "failed" half of Review Focus 3 (3.2) to fail through a line**

In `test_an_ended_or_failed_follow_survives_leave_and_return`, replace

```qml
    send(p2, tc.chunkLine)
    p2.exited(0)
```

with

```qml
    send(p2, tc.chunkLine)
    send(p2, '{"ok":false,"error":{"type":"StreamError","message":"am logs: run left"}}')
    p2.exited(0)
```

- [ ] **Step 4: Write the new tests N4, N5, N6 (with Review Focus 3), N9**

Append inside the `TestCase`:

```qml
  // N4
  function test_a_crash_resumes_from_next_offset() {
    var store = following(); if (!store) return
    var seen = recorder(store)
    var old = store.followProc
    send(old, streamLines("logs-follow-agent.jsonl")[0])
    send(old, tc.chunkLine)
    old.exited(0)
    compare(store.followProc, null)
    compare(store.reconnects, 1)
    compare(store.retryTimer.running, true)
    compare(store.retryTimer.interval, 1000)
    compare(seen.length, 0, "nothing starts before the timer fires")
    store.retryTimer.triggered()
    compare(seen.length, 1)
    compare(store.retryTimer.running, false)
    compare(store.followProc.command.length, 8)
    compare(argv(store.followProc), tc.followCmd + tc.runId + "|" + tc.openCard + "|explore|1|28")
    compare(store.followStatus, "connecting")
    compare(store.liveText, "stub claude ok phase=review", "the buffer is kept")
  }

  // N5
  function test_restarts_back_off_1_2_4_seconds() {
    var store = following(); if (!store) return
    store.nowMs = 100000
    send(store.followProc, tc.chunkLine)
    var expected = [1000, 2000, 4000]
    for (var i = 0; i < expected.length; i++) {
      crash(store)
      compare(store.reconnects, i + 1)
      compare(store.retryTimer.interval, expected[i])
      compare(store.retryTimer.running, true)
      store.retryTimer.triggered()
      verify(store.followProc, "restarted after exit " + (i + 1))
    }
    store.retryTimer.stop()
  }

  // N6, Review Focus 3 (3.3): a stray fire after the error starts nothing
  function test_the_fourth_exit_within_60_s_is_an_error() {
    var codes = [0, 1]
    for (var c = 0; c < codes.length; c++) {
      var store = following(); if (!store) return
      var seen = recorder(store)
      store.nowMs = 100000
      send(store.followProc, tc.chunkLine)
      for (var i = 0; i < 3; i++) {
        crash(store, codes[c])
        store.retryTimer.triggered()
      }
      compare(seen.length, 3)
      crash(store, codes[c])
      compare(store.reconnects, 4)
      compare(store.followStatus, "error")
      compare(store.followError, "Live output stopped: the helper exited with code " + codes[c])
      compare(store.retryTimer.running, false)
      compare(store.followProc, null)
      compare(store.liveText, "stub claude ok phase=review")
      store.retryTimer.triggered()
      compare(seen.length, 3, "a stray fire after the error starts nothing")
      store.inRunDetail = false
      store.inRunDetail = true
      compare(seen.length, 3, "nor does a return")
    }
  }

  // N9
  function test_exits_older_than_60_s_leave_the_window() {
    var store = following(); if (!store) return
    send(store.followProc, tc.chunkLine)
    crashesAt(store, [10000, 11000, 13000])
    store.nowMs = 80000
    crash(store)
    compare(store.reconnects, 1)
    compare(store.retryTimer.interval, 1000)
    store.retryTimer.stop()

    var edge = following(); if (!edge) return
    send(edge.followProc, tc.chunkLine)
    crashesAt(edge, [10000, 11000, 13000])
    edge.nowMs = 69999
    crash(edge)
    compare(edge.reconnects, 4, "59999 ms after the first still counts")
    compare(edge.followStatus, "error")

    var past = following(); if (!past) return
    send(past.followProc, tc.chunkLine)
    crashesAt(past, [10000, 11000, 13000])
    past.nowMs = 70000
    crash(past)
    compare(past.reconnects, 3, "60000 ms after the first drops it")
    compare(past.retryTimer.interval, 4000)
    compare(past.followStatus, "following")
    past.retryTimer.stop()
  }
```

- [ ] **Step 5: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_output_store.qml 2>&1 | grep -E "^(FAIL|Totals)|^   Loc|TypeError|ReferenceError"`

Expected: FAIL for `test_an_exit_with_no_end_line` (status `error`), `test_a_crash_resumes_from_next_offset`, `test_restarts_back_off_1_2_4_seconds`, `test_the_fourth_exit_within_60_s_is_an_error`, `test_exits_older_than_60_s_leave_the_window` (`reconnects`/`retryTimer` undefined → TypeError). `test_an_ended_or_failed_follow_survives_leave_and_return` passes.

- [ ] **Step 6: Add the properties**

In `core/stores/RunOutputStore.qml`, after `property var buffer: LogStream.emptyBuffer()` (line 45), add:

```qml
  property int reconnects: 0          // unexpected exits counted toward the limit; 0 after a good chunk or clear()
  property real nowMs: 0              // the restart window's clock, epoch ms; 0 = Date.now()
  property var exitTimes: []          // the counted exits' times, epoch ms
  readonly property alias retryTimer: retryTimer   // the pending restart; running while one is scheduled
```

- [ ] **Step 7: Cancel a pending restart in `start`**

In `start(k, offset)`, make the first line of the body:

```qml
    store.retryTimer.stop()
```

(so the body begins `store.retryTimer.stop()` then `store.followSeq += 1`).

- [ ] **Step 8: Replace `followExited` and add `retry`**

Replace the comment + `followExited` function (the block starting `// The current process exited: no process is left; with no end line and no`) with:

```qml
  // The current process exited: no process is left. While connecting or
  // following it is an unexpected exit: exits 60 s or older leave the window,
  // this one is counted in `reconnects`, and the same key restarts after 1 s,
  // 2 s, then 4 s (retryTimer); the fourth within 60 s is an error naming the
  // exit code.
  function followExited(proc, exitCode) {
    if (!store.isCurrentFollow(proc)) return
    store.followProc = null
    if (store.followStatus !== "connecting" && store.followStatus !== "following") return
    var t = store.nowMs > 0 ? store.nowMs : Date.now()
    var kept = store.exitTimes.filter(function(e) { return t - e < 60000 })
    kept.push(t)
    store.exitTimes = kept
    store.reconnects = kept.length
    if (store.reconnects <= 3) {
      store.retryTimer.interval = 1000 * Math.pow(2, store.reconnects - 1)
      store.retryTimer.start()
      return
    }
    store.followStatus = "error"
    store.followError = "Live output stopped: the helper exited with code " + exitCode
  }

  // The pending restart is due: the same key, with no process and still
  // connecting or following, resumes from nextOffset when it can be followed
  // and is cleared once it is not live; any other fire does nothing.
  function retry() {
    var k = store.selectionKey(store.run, store.selection)
    if (k === null || !store.sameKey(k, store.followKey) || store.followProc) return
    if (store.followStatus !== "connecting" && store.followStatus !== "following") return
    if (store.canStart(k)) store.start(k, store.buffer.nextOffset)
    else if (!store.isLive()) store.clear()
  }
```

- [ ] **Step 9: Add the Timer**

Between `Component.onCompleted: store.reconcile()` and the `// One Process per follow launch, ...` comment, add:

```qml
  Timer {
    id: retryTimer
    objectName: "retryTimer"
    repeat: false
    onTriggered: store.retry()
  }

```

- [ ] **Step 10: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_output_store.qml 2>&1 | grep -E "^(FAIL|Totals)|^   Loc|TypeError|ReferenceError"`

Expected: `Totals: 32 passed, 0 failed`, no TypeError/ReferenceError lines.

- [ ] **Step 11: Run the architecture tests**

Run: `timeout 300 python3 -m pytest tests/architecture -q` (if `python3` has no pytest: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture -q`)
Expected: all passed.

- [ ] **Step 12: Commit**

```bash
git add core/stores/RunOutputStore.qml tests/core/stores/tst_run_output_store.qml
git commit -m "feat(stores): RunOutputStore restarts an exited follow after 1, 2, 4 s, up to 4 exits in 60 s"
```

---

### Task 3: Good-chunk reset and cancelling a pending restart

**Files:**
- Modify: `core/stores/RunOutputStore.qml` (`clear`, `reconcile`, `stop`, `followLine`)
- Test: `tests/core/stores/tst_run_output_store.qml`

**Interfaces:**
- Consumes: `reconnects`, `exitTimes`, `retryTimer`, `retry()`, `start(k, offset)` from Tasks 1-2; test helpers `crash`, `crashesAt`, constants `tc.resumeHello`, `tc.moreLine`.
- Produces: `clear()` also stops `retryTimer`, sets `reconnects` 0 and `exitTimes` []; `stop()` also stops `retryTimer`; `reconcile()` final form (below); a folded `chunk` resets the count.

- [ ] **Step 1: Write the tests N7, N8, N10, N11, N12 and Review Focus 1**

Append inside the `TestCase`:

```qml
  // N7
  function test_a_good_chunk_resets_the_count() {
    var store = following(); if (!store) return
    store.nowMs = 100000
    send(store.followProc, tc.chunkLine)
    crash(store); store.retryTimer.triggered()
    crash(store); store.retryTimer.triggered()
    compare(store.reconnects, 2)
    send(store.followProc, tc.moreLine)
    compare(store.reconnects, 0)
    compare(store.liveText, "stub claude ok phase=review\nmore")
    crash(store)
    compare(store.reconnects, 1)
    compare(store.retryTimer.interval, 1000)
    store.retryTimer.stop()
  }

  // N8
  function test_a_hello_or_a_duplicate_chunk_is_not_a_good_chunk() {
    var store = following(); if (!store) return
    store.nowMs = 100000
    send(store.followProc, tc.chunkLine)
    compare(store.buffer.nextOffset, 28)
    crash(store); store.retryTimer.triggered()
    crash(store); store.retryTimer.triggered()
    send(store.followProc, tc.resumeHello)
    send(store.followProc, tc.chunkLine)
    compare(store.reconnects, 2)
    compare(store.liveText, "stub claude ok phase=review", "the duplicate is dropped")
    crash(store)
    compare(store.reconnects, 3)
    compare(store.retryTimer.interval, 4000)
    store.retryTimer.stop()
  }

  // N10
  function test_a_pending_restart_is_cancelled() {
    var props = ["inRunDetail", "active"]
    for (var i = 0; i < props.length; i++) {
      var store = following(); if (!store) return
      send(store.followProc, tc.chunkLine)
      crash(store)
      var seen = recorder(store)
      store[props[i]] = false
      compare(store.retryTimer.running, false, props[i] + " false cancels")
      store.retryTimer.triggered()
      compare(seen.length, 0, props[i] + ": a stray fire starts nothing")
      compare(store.reconnects, 1, "the count stays")
      compare(store.followStatus, "following")
      store[props[i]] = true
      compare(seen.length, 1, props[i] + ": the return resumes at once")
      compare(argv(store.followProc), tc.followCmd + tc.runId + "|" + tc.openCard + "|explore|1|28")
    }

    var sel = following(stepRun(false), explore()); if (!sel) return
    send(sel.followProc, tc.chunkLine)
    crash(sel)
    var seenSel = recorder(sel)
    sel.selection = verifyStep()
    compare(sel.retryTimer.running, false, "another selection cancels")
    compare(seenSel.length, 1, "verify starts")
    var b = sel.followProc
    sel.retryTimer.triggered()
    compare(seenSel.length, 1, "a stray fire starts nothing")
    compare(sel.followProc, b)
    compare(argv(b), tc.followCmd + tc.runId + "|" + tc.openCard + "|verify|0")

    var cases = [
      ["another run", function(s) { s.run = otherRun("20261009T000000Z-0th3r000", "ok") }],
      ["a non-live selection", function(s) { s.selection = { card_id: tc.openCard, phase: "worktree", attempt: 0, step: true } }]
    ]
    for (var j = 0; j < cases.length; j++) {
      var st = following(); if (!st) return
      send(st.followProc, tc.chunkLine)
      crash(st)
      var seenSt = recorder(st)
      cases[j][1](st)
      compare(st.retryTimer.running, false, cases[j][0] + " cancels")
      compare(st.followKey, null, cases[j][0])
      st.retryTimer.triggered()
      compare(seenSt.length, 0, cases[j][0] + ": a stray fire starts nothing")
    }
  }

  // N11
  function test_a_new_snapshot_during_the_wait_starts_nothing() {
    var store = following(); if (!store) return
    send(store.followProc, tc.chunkLine)
    crash(store)
    var seen = recorder(store)
    store.run = startedRun()
    compare(seen.length, 0, "no early start")
    compare(store.retryTimer.running, true)
    compare(store.followStatus, "following")
    store.retryTimer.triggered()
    compare(seen.length, 1, "the pending restart stays in charge")
  }

  // N12
  function test_a_key_that_stops_being_live_during_the_wait_clears() {
    var store = following(); if (!store) return
    send(store.followProc, tc.chunkLine)
    crash(store)
    var seen = recorder(store)
    store.run = exploreOkRun()
    compare(store.followKey, null)
    compare(store.followStatus, "idle")
    compare(store.liveText, "")
    compare(store.reconnects, 0)
    compare(store.retryTimer.running, false)
    store.retryTimer.triggered()
    compare(seen.length, 0, "a stray fire starts nothing")
  }

  // Review Focus 1 (3.3)
  function test_away_during_the_wait_and_back_starts_fresh() {
    var store = following(stepRun(false), explore()); if (!store) return
    store.nowMs = 100000
    send(store.followProc, tc.chunkLine)
    crash(store)
    store.selection = verifyStep()
    store.selection = explore()
    compare(store.followProc.command.length, 7, "from offset 0")
    compare(argv(store.followProc), tc.followCmd + tc.runId + "|" + tc.openCard + "|explore|1")
    compare(store.liveText, "")
    compare(store.reconnects, 0)
    compare(store.retryTimer.running, false)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_output_store.qml 2>&1 | grep -E "^(FAIL|Totals)|^   Loc|TypeError|ReferenceError"`

Expected: FAIL for `test_a_good_chunk_resets_the_count` (reconnects 2, not 0), `test_a_pending_restart_is_cancelled` (timer still running), `test_a_new_snapshot_during_the_wait_starts_nothing` (a process starts early), `test_a_key_that_stops_being_live_during_the_wait_clears` (reconnects 1), `test_away_during_the_wait_and_back_starts_fresh` (reconnects 1 / timer running). `test_a_hello_or_a_duplicate_chunk_is_not_a_good_chunk` passes already (it pins that only a folded chunk will reset).

- [ ] **Step 3: Reset on a good chunk**

In `followLine`, replace

```qml
    if (r.kind === "hello" || r.kind === "chunk") {
      store.setBuffer(r.buffer)
      store.followStatus = "following"
    } else if (r.kind === "end") {
```

with

```qml
    if (r.kind === "hello" || r.kind === "chunk") {
      store.setBuffer(r.buffer)
      store.followStatus = "following"
      if (r.kind === "chunk") {
        store.reconnects = 0
        store.exitTimes = []
      }
    } else if (r.kind === "end") {
```

and in its comment replace `// A hello or a chunk replaces the buffer and is `following`; the end is` with

```qml
  // A hello or a chunk replaces the buffer and is `following`; a chunk (new
  // output, not a duplicate) also resets `reconnects`. The end is
```

- [ ] **Step 4: Cancel in `clear` and `stop`**

Replace `clear()` with:

```qml
  // No key, idle, an empty buffer, no counted exits and no pending restart.
  function clear() {
    store.retryTimer.stop()
    store.followKey = null
    store.followStatus = "idle"
    store.endStatus = ""
    store.followError = ""
    store.reconnects = 0
    store.exitTimes = []
    store.setBuffer(LogStream.emptyBuffer())
  }
```

Replace the comment + `stop()` with:

```qml
  // SIGTERM and no pending restart; the stopped process's later lines and
  // exit are ignored.
  function stop() {
    store.retryTimer.stop()
    store.followSeq += 1
    if (store.followProc) store.followProc.running = false
    store.followProc = null
  }
```

- [ ] **Step 5: Final `reconcile`**

Replace the comment + `reconcile()` with:

```qml
  // Another key: stop, clear, and start when it can be followed. The same key
  // off Run detail or with the panel closed: stop, cancel a pending restart
  // and keep the rest. The same key back with no process while connecting or
  // following: clear it once it is not live, leave a pending restart in
  // charge, else resume it from the buffer's nextOffset. A running process of
  // the same key is left alone.
  function reconcile() {
    var k = store.selectionKey(store.run, store.selection)
    if (!store.sameKey(k, store.followKey)) {
      if (store.followProc) store.stop()
      store.clear()
      if (store.canStart(k)) store.start(k, 0)
      return
    }
    if (k === null) return
    if (!store.isPresent()) {
      if (store.followProc) store.stop()
      store.retryTimer.stop()
      return
    }
    if (store.followProc) return
    var s = store.followStatus
    if (s !== "connecting" && s !== "following") return
    if (!store.isLive()) store.clear()
    else if (store.retryTimer.running) return
    else if (store.canStart(k)) store.start(k, store.buffer.nextOffset)
  }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_output_store.qml 2>&1 | grep -E "^(FAIL|Totals)|^   Loc|TypeError|ReferenceError"`

Expected: `Totals: 38 passed, 0 failed`, no TypeError/ReferenceError lines. (`test_returning_to_a_key_that_is_no_longer_live_clears` and `test_at_most_one_follow_process_runs` keep passing.)

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunOutputStore.qml tests/core/stores/tst_run_output_store.qml
git commit -m "feat(stores): RunOutputStore resets the count on new output and cancels a pending restart"
```

---

### Task 4: Typed failure lines, and the contract text

**Files:**
- Modify: `core/stores/RunOutputStore.qml` (header comment `:7-26`, `followLine`, new `schemaSentence`, new `refuse`)
- Modify: `docs/architecture.md:94`
- Test: `tests/core/stores/tst_run_output_store.qml` (header comment `:1-5`, new tests)

**Interfaces:**
- Consumes: everything from Tasks 1-3; `Runs.errorText(value)`; `snapshotWanted()`.
- Produces: `function refuse(value)` (value an `{"ok": false, ...}` object), `function schemaSentence(message)` → string. Test helper `refusal(type, message)` → JSON string.

- [ ] **Step 1: Add the test helper**

After `crashesAt` in the test file, add:

```qml
  // A runs-logs-follow.py failure line of `type` with `message`.
  function refusal(type, message) { return JSON.stringify({ ok: false, error: { type: type, message: message } }) }
```

- [ ] **Step 2: Write the tests N13–N18 (with Review Focus 4 and 5)**

Append inside the `TestCase`:

```qml
  // N13
  function test_follow_unsupported_falls_back_to_snapshots() {
    var store = following(); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "snapshotWanted" })
    var seen = recorder(store)
    var proc = store.followProc
    send(proc, refusal("FollowUnsupported", "am logs cannot follow (exit 2)."))
    compare(store.followStatus, "unsupported")
    compare(store.endStatus, "")
    compare(store.followError, "This am cannot stream output (am logs --follow is missing)")
    compare(spy.count, 1)
    proc.exited(0)
    compare(store.followProc, null)
    compare(store.retryTimer.running, false, "no reconnect")
    store.inRunDetail = false
    store.inRunDetail = true
    compare(seen.length, 0, "no process on return")
    compare(store.followStatus, "unsupported")
    compare(spy.count, 1)
  }

  // N14, Review Focus 4 (3.3)
  function test_schema_mismatch_falls_back_with_its_schema() {
    var cases = [
      ["am logs speaks schema 3; this helper reads schema 1 or 2.", "Unknown output stream schema 3"],
      ["am logs speaks schema null; this helper reads schema 1 or 2.", "Unknown output stream schema null"],
      ['am logs speaks schema "1"; this helper reads schema 1 or 2.', 'Unknown output stream schema "1"'],
      ["weird", "Unknown output stream schema"],
      [7, "Unknown output stream schema"]
    ]
    for (var i = 0; i < cases.length; i++) {
      var store = following(); if (!store) return
      var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "snapshotWanted" })
      var proc = store.followProc
      send(proc, refusal("SchemaMismatch", cases[i][0]))
      compare(store.followStatus, "unsupported", String(cases[i][0]))
      compare(store.followError, cases[i][1])
      compare(spy.count, 1)
      proc.exited(0)
      compare(store.retryTimer.running, false, "no reconnect")
    }
  }

  // N15
  function test_am_missing_stops_silently() {
    var store = following(stepRun(false), explore()); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "snapshotWanted" })
    var proc = store.followProc
    send(proc, streamLines("logs-follow-agent.jsonl")[0])
    send(proc, tc.chunkLine)
    send(proc, refusal("AmMissing", "am is not installed."))
    compare(store.followStatus, "idle")
    compare(store.followError, "")
    compare(store.endStatus, "")
    compare(store.followKey.phase, "explore", "the key is held")
    compare(store.liveText, "stub claude ok phase=review", "the buffer is held")
    compare(spy.count, 0)
    var seen = recorder(store)
    proc.exited(0)
    compare(store.retryTimer.running, false)
    store.run = stepRun(false)
    compare(seen.length, 0, "a new snapshot starts nothing")
    store.inRunDetail = false
    store.inRunDetail = true
    compare(seen.length, 0, "a return starts nothing")
    store.selection = verifyStep()
    compare(seen.length, 1, "another selection starts normally")
    compare(argv(store.followProc), tc.followCmd + tc.runId + "|" + tc.openCard + "|verify|0")
    compare(store.followStatus, "connecting")
  }

  // N16, Review Focus 5 (3.3): malformed envelopes are errors too
  function test_a_refusal_or_a_stream_error_is_an_error() {
    var envelope = F.load("logs-follow-refusal.json")
    var cases = [
      [JSON.stringify(envelope), Runs.errorText(envelope)],
      [refusal("StreamError", "am logs: run left"), "StreamError: am logs: run left"],
      ['{"ok":false,"error":"boom"}', Runs.errorText({ ok: false, error: "boom" })],
      ['{"ok":false}', Runs.errorText({ ok: false })]
    ]
    for (var i = 0; i < cases.length; i++) {
      var store = following(); if (!store) return
      var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "snapshotWanted" })
      var proc = store.followProc
      send(proc, tc.chunkLine)
      send(proc, cases[i][0])
      compare(store.followStatus, "error", cases[i][0])
      compare(store.followError, cases[i][1])
      compare(store.liveText, "stub claude ok phase=review")
      compare(spy.count, 0)
      proc.exited(0)
      compare(store.retryTimer.running, false, "no reconnect")
      compare(store.followStatus, "error")
    }
  }

  // N17
  function test_a_step_with_no_recorded_attempt_has_no_output() {
    var store = following(stepRun(true), verifyStep()); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "snapshotWanted" })
    var seen = recorder(store)
    var proc = store.followProc
    send(proc, JSON.stringify(F.load("logs-follow-refusal.json")))
    compare(store.followStatus, "ended")
    compare(store.endStatus, "")
    compare(store.followError, "This step records no output")
    compare(spy.count, 0)
    proc.exited(0)
    compare(store.retryTimer.running, false)
    store.active = false
    store.active = true
    compare(seen.length, 0, "no restart on return")
    compare(store.followStatus, "ended")
  }

  // N18
  function test_lines_after_a_fallback_or_am_missing_are_ignored() {
    var cases = [["FollowUnsupported", "unsupported"], ["AmMissing", "idle"]]
    for (var i = 0; i < cases.length; i++) {
      var store = following(); if (!store) return
      var proc = store.followProc
      send(proc, tc.chunkLine)
      send(proc, refusal(cases[i][0], "x"))
      send(proc, tc.moreLine)
      compare(store.liveText, "stub claude ok phase=review", cases[i][0])
      compare(store.followStatus, cases[i][1])
    }
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_output_store.qml 2>&1 | grep -E "^(FAIL|Totals)|^   Loc|TypeError|ReferenceError"`

Expected: FAIL for `test_follow_unsupported_falls_back_to_snapshots`, `test_schema_mismatch_falls_back_with_its_schema`, `test_am_missing_stops_silently`, `test_a_step_with_no_recorded_attempt_has_no_output`, `test_lines_after_a_fallback_or_am_missing_are_ignored` (each reads `error`). `test_a_refusal_or_a_stream_error_is_an_error` passes already (it pins the "anything else" row).

- [ ] **Step 4: Implement `schemaSentence`, `refuse` and the `followLine` guard**

Replace the block from `// One stdout line of the current process` through the closing `}` of `followLine` (its comment as edited in Task 3, and the function) with:

```qml
  // One stdout line of the current process while connecting or following
  // (any other status ignores it): trimmed and parsed (blank or not JSON is
  // null), then one LogStream.foldLine. A hello or a chunk replaces the buffer
  // and is `following`; a chunk (new output, not a duplicate) also resets
  // `reconnects`. The end is `ended` with am's status, and asks for a logs
  // snapshot for a step (attempt 0); an {"ok": false} line goes to refuse().
  // The buffer stays on the end and on a refusal.
  function followLine(proc, data) {
    if (!store.isCurrentFollow(proc)) return
    if (store.followStatus !== "connecting" && store.followStatus !== "following") return
    var text = String(data || "").trim()
    var value = null
    if (text !== "") {
      try { value = JSON.parse(text) } catch (e) { value = null }
    }
    var r = LogStream.foldLine(store.buffer, value)
    if (r.kind === "hello" || r.kind === "chunk") {
      store.setBuffer(r.buffer)
      store.followStatus = "following"
      if (r.kind === "chunk") {
        store.reconnects = 0
        store.exitTimes = []
      }
    } else if (r.kind === "end") {
      store.followStatus = "ended"
      store.endStatus = typeof value.status === "string" ? value.status : ""
      if (store.followKey.attempt === 0) store.snapshotWanted()
    } else if (r.kind === "refusal") {
      store.refuse(value)
    }
  }

  // "Unknown output stream schema N", N the text of a SchemaMismatch message
  // "am logs speaks schema N; ..."; with no N in that shape, the sentence alone.
  function schemaSentence(message) {
    var prefix = "am logs speaks schema "
    var text = typeof message === "string" ? message : ""
    var end = text.indexOf(";", prefix.length)
    if (text.indexOf(prefix) !== 0 || end <= prefix.length) return "Unknown output stream schema"
    return "Unknown output stream schema " + text.slice(prefix.length, end)
  }

  // An {"ok": false} line, by error.type: FollowUnsupported and SchemaMismatch
  // are `unsupported` with their sentence and ask for one logs snapshot;
  // AmMissing is `idle` with the key and buffer held; UnknownAttemptError on a
  // step (attempt 0) is `ended` "This step records no output"; anything else
  // is `error` with its Runs.errorText. None schedules a restart.
  function refuse(value) {
    var e = store.isObject(value.error) ? value.error : {}
    var type = typeof e.type === "string" ? e.type : ""
    if (type === "FollowUnsupported" || type === "SchemaMismatch") {
      store.followStatus = "unsupported"
      store.endStatus = ""
      store.followError = type === "FollowUnsupported"
          ? "This am cannot stream output (am logs --follow is missing)"
          : store.schemaSentence(e.message)
      store.snapshotWanted()
    } else if (type === "AmMissing") {
      store.followStatus = "idle"
      store.endStatus = ""
      store.followError = ""
    } else if (type === "UnknownAttemptError" && store.followKey.attempt === 0) {
      store.followStatus = "ended"
      store.endStatus = ""
      store.followError = "This step records no output"
    } else {
      store.followStatus = "error"
      store.followError = Runs.errorText(value)
    }
  }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_output_store.qml 2>&1 | grep -E "^(FAIL|Totals)|^   Loc|TypeError|ReferenceError"`

Expected: `Totals: 44 passed, 0 failed`, no TypeError/ReferenceError lines.

- [ ] **Step 6: Rewrite the store's header comment**

Replace lines 7-26 of `core/stores/RunOutputStore.qml` (from `// Run detail's live output: runs-logs-follow.py for the one attempt or step` through `// error. A stopped process's lines and exit are ignored.`) with:

```qml
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
// follows it from offset 0 into an empty buffer. Leaving Run detail or
// closing the panel stops the process, cancels a pending restart and keeps
// the key, the buffer and `reconnects`; coming back on the same live key
// while it is connecting or following resumes from the buffer's nextOffset
// (OFFSET is passed only when > 0). A key that stops being live keeps its
// process until the end line or the exit, and is cleared once no process is
// left.
//
// An exit of the current process before its end line or a failure line
// restarts the same key from nextOffset after 1 s, 2 s, then 4 s
// (`retryTimer`); a new snapshot of the same key during the wait starts
// nothing early. The fourth such exit within 60 s (clock `nowMs`, 0 =
// Date.now()) is `error` "Live output stopped: the helper exited with code
// N". `reconnects` counts those exits; a chunk of new output resets it.
//
// The end line sets `ended` and endStatus; for a step it asks for one logs
// snapshot. An {"ok": false} line, by error.type: FollowUnsupported is
// `unsupported` "This am cannot stream output (am logs --follow is
// missing)" and SchemaMismatch `unsupported` "Unknown output stream schema
// N", each asking for one logs snapshot; AmMissing is `idle` with the key and
// buffer held (Run detail shows RunStore.amStatus); a step's
// UnknownAttemptError is `ended` "This step records no output"; anything
// else is `error` with its Runs.errorText. After any of them, and after the
// end, lines are ignored and nothing restarts. A stopped process's lines and
// exit are ignored.
```

- [ ] **Step 7: Update the test file's header comment**

Replace lines 2-5 of `tests/core/stores/tst_run_output_store.qml` (from `// Run detail's live output store: when runs-logs-follow.py starts and stops` through `// latest wins. Built directly and driven through stubbed Process objects.`) with:

```qml
// Run detail's live output store: when runs-logs-follow.py starts and stops
// for the selected attempt or step, its exact argv (OFFSET on a resume), how
// its stdout lines fold into the live buffer, the end line, typed failure
// lines, the restart backoff and its limit, and latest wins. Built directly
// and driven through stubbed Process objects and the aliased retryTimer.
```

- [ ] **Step 8: Update `docs/architecture.md:94`**

In line 94, replace

```
`followError` says why a follow failed; `followProc` is the current process or null.
```

with

```
`followError` says why a follow failed or stopped; `followProc` is the current process or null; `reconnects` counts unexpected exits toward the restart limit; `nowMs` is the restart window's clock (epoch ms, `0` = `Date.now()`); `retryTimer` (objectName `retryTimer`) is the pending restart.
```

Then, in the same line, replace

```
starts `runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT` from offset 0. Leaving Run detail or closing the panel stops the process and keeps the key and the buffer; coming back on the same live key starts again from offset 0 unless the follow ended or failed. A key that stops being live keeps its process until the end line or the exit. The end line sets `ended` and `endStatus` and keeps the buffer; for a step it emits `snapshotWanted()` once. An `{ok: false}` line sets `error` with `Runs.errorText`; an exit before the end line sets `error` with `Live output stopped: the helper exited with code N`.
```

with

```
starts `runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT` from offset 0 into an empty buffer. Leaving Run detail or closing the panel stops the process, cancels a pending restart and keeps the key, the buffer and `reconnects`; coming back on the same live key while it is `connecting` or `following` resumes with `OFFSET` = the buffer's `nextOffset` (passed only when > 0). A key that stops being live keeps its process until the end line or the exit, and is cleared once no process is left. An exit of the current process before its end line or a failure line restarts the same key from `nextOffset` after 1 s, 2 s, then 4 s; a new snapshot of the same key during the wait starts nothing early; the fourth such exit within 60 s sets `error` with `Live output stopped: the helper exited with code N`; a chunk of new output (not a hello, not a duplicate) resets `reconnects`. The end line sets `ended` and `endStatus` and keeps the buffer; for a step it emits `snapshotWanted()` once. An `{ok: false}` line maps on `error.type`: `FollowUnsupported` sets `unsupported` with `This am cannot stream output (am logs --follow is missing)` and `SchemaMismatch` sets `unsupported` with `Unknown output stream schema N`, each emitting `snapshotWanted()` once; `AmMissing` sets `idle` and holds the key and the buffer (Run detail shows `RunStore.amStatus` `missing`); a step's `UnknownAttemptError` sets `ended` with `endStatus` `""` and `This step records no output`; anything else sets `error` with `Runs.errorText`. None of them restarts, and later lines are ignored.
```

- [ ] **Step 9: Run the full gate**

Run: `timeout 600 bash tests/run.sh 2>&1 | tail -40`
Expected: pytest `N passed` with no failures (includes `tests/architecture`), every QML file prints `Totals: ... 0 failed`, no TypeError/ReferenceError lines, exit code 0 (`echo $?` → `0`).

- [ ] **Step 10: Commit**

```bash
git add core/stores/RunOutputStore.qml tests/core/stores/tst_run_output_store.qml docs/architecture.md
git commit -m "feat(stores): RunOutputStore maps typed follow failures to unsupported, idle, ended or error"
```
<!-- task-pipeline: validated -->
