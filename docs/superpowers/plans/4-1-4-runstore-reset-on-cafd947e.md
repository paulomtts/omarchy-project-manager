<!-- The spec this plan implements, prepended verbatim from docs/superpowers/specs/4-1-4-runstore-reset-on-cafd947e.md. -->

# 4.1.4 RunStore: reset on a changed store_id — design

Card `cafd947e`, subtask of story 4.1 (`1b1f4f8b`), blocked by 4.1.3 (`8bc05ecf`, done on this
branch). Parent design:
`/home/mtts/Code/omarchy-project-manager/docs/superpowers/specs/2026-10-06-am-snapshots-cursors-design.md`
(untracked local file; cited below as **P** with line numbers). Code references are measured on
this branch at `57ceffb`; re-read before acting.

## Problem

A `cursorReset` hello (handled by 4.1.3, `core/stores/RunStore.qml:283`, `resetCursor()` at
`:331-341`) only fires when am's head is lower than the cursor the watch was given. A restored
or replaced `am.db` whose head is equal or higher passes that check, so the store keeps
`appliedSeq`, `asOfSeq`, `watchCursor`, the nudges and the runs of a different store and
compares the new store's seqs against them (P:302-305). am names its store with `store_id`
(P:271-275). The helpers already forward it:

- `runs-watch.py`'s hello carries `storeId` (`""` when am's `store_id` is not a string)
  (`core/backend/runs/runs-watch.py:92-106`).
- `runs-snapshot.py`'s list reply and its `--run RUN` reply carry `store_id`
  (`core/backend/runs/runs-snapshot.py:168`, `:174-177`).

`RunStore.qml` reads none of them (no `store_id`/`storeId` anywhere in it). No helper change is
needed.

## Goal

The store remembers the last `store_id` it saw. When a hello or a snapshot names a different
one, it forgets everything it knew about the old store, as a `cursorReset` does, and starts over
from one full list snapshot, raising no alerts for that snapshot (P:260, P:199). A `store_id`
seen for the first time resets nothing.

## Inherited constraints

- The plugin reads snapshots and treats watch lines as nudges; it never folds events into state
  (P:45-47, P:101-104).
- am calls are argv lists through the helpers only; no reading of `am.db`, journals or the data
  dir (P:58-59). This card changes no helper.
- The hello stays at schema 2 with additive `head`, `gseq`, `cursor_reset` and `store_id`; the
  plugin resets its cursor and list when the `store_id` changes (P:273-275, P:260).
- `cursorReset` behaviour is unchanged: clear `appliedSeq`, the cursor and the list, full
  snapshot, no alerts (P:199). A `store_id` change has the same outcome.
- In M4 the watch cursor is held in memory only; persisting it is the Alerts milestone's work
  (P:269). "The persisted cursor" of the card is therefore `watchCursor` alone: there is no
  persisted cursor to clear.
- Lines with an unknown event or key are ignored (P:79-80); no dead-run detection from events,
  the lease poll stays (P:61-62).
- Layering per `docs/architecture.md`; `tests/architecture` must pass (P:230-237). Stores import
  only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain`.
- Comments and docstrings state the contract only, no narrative.
- am output in tests comes from `tests/fixtures/am/` through `tests/helpers/amFixtures.js`; a
  hand-built edge case is labelled `synthetic:`. Every capture shares one `store_id`
  (`91b9e8afc25044c385859292bfabfde7`, `tests/contract/test_am_fixtures.py:383`), so every
  "different store" input is synthetic.
- Verification: `bash tests/run.sh` green. TDD: tests first.

## Behaviour

### Vocabulary

- **store id**: a non-empty string. Anything else (`""`, missing, a number, `null`, an object)
  is *no store id* and is ignored everywhere below: it neither resets nor is recorded.
- **seen id**: `store.storeId`, the last store id recorded; `""` before any.
- **changed**: a store id arrives while the seen id is non-empty and differs from it.
- **first sight**: a store id arrives while the seen id is `""`.

### New public member

```
property string storeId: ""   // am's store_id from the last hello or snapshot that named one; "" = none yet
```

Declared beside `asOfSeq`/`appliedSeq`/`watchCursor` (`RunStore.qml:56-62`). Replaced, never
derived.

### Sources

1. **Hello** (`watchLine`, `RunStore.qml:270-288`): `value.hello.storeId`.
2. **List snapshot** (`applySnapshot`, `:600-672`, `ok: true` only): `envelope.store_id`.
3. **Run read** (`applyRunRead` via `readReplied`, `:696-772`, `ok: true` only):
   `envelope.store_id`. A run read is the single-run snapshot (`am status`); a reply from a
   different store must not be applied against the old store's `appliedSeq`.

An `ok: false` envelope of any source never touches `storeId`.

### Hello source

On a hello (after `amSchema`/`amVersion` are set, as today):

- first sight: `storeId` becomes the id; nothing else changes.
- same id: nothing changes.
- changed: `storeId` becomes the new id, then `resetCursor()` runs **once**, whatever
  `cursorReset` says. A hello that is both changed and `cursorReset: true` launches exactly one
  list snapshot, not two.
- no store id: `storeId` is kept; `cursorReset` handling is as in 4.1.3.

Because the id is recorded before `resetCursor()` launches its list snapshot, that snapshot's
reply (carrying the new id) is "same id" and does not reset again: it applies and only arms
alerts (the existing `alertsArmed = false` path).

### List snapshot source

On an `ok: true` list reply, before its entries are applied:

- first sight: `storeId` becomes the id; the reply is applied exactly as today.
- same id / no store id: applied exactly as today; `storeId` kept.
- changed: `storeId` becomes the new id and the store forgets the old store's live state:
  `watchCursor = 0`, `nudges = {}`, the debounce stops, every run read in flight is dropped
  (`dropReads()`), `runs = []` and `alertsArmed = false`. Then the reply is applied as today: it
  *is* the full snapshot (it replaces `asOfSeq`, `appliedSeq`, `runs`), so **no further list
  snapshot is launched**. With `alertsArmed` false, `Runs.newAlerts` compares against `null`:
  the reply raises no toast, and while `active` it arms alerts as any first list does.
  Selection, logs, controls and dispatch stay, as with `resetCursor()`.

The shared clearing (cursor, nudges, debounce, dropped reads, emptied runs, disarmed alerts) is
one store function used by both `resetCursor()` and this path, so `resetCursor()` is that
function plus clearing `appliedSeq`/`asOfSeq` plus `refresh()`. Its observable behaviour is
unchanged (4.1.3's tests keep passing as written).

### Run read source

On an `ok: true` run-read reply that is current (latest for its run, same project — the
existing guard in `readReplied`):

- first sight: `storeId` becomes the id; the reply is applied as today.
- same id / no store id: applied as today.
- changed: `storeId` becomes the new id, the reply is **not** applied, and `resetCursor()` runs
  (one list snapshot). No toast; `amStatus`, `lastError` untouched.

A non-current reply (superseded, dropped, other project) changes nothing, `storeId` included.

### Kept across

`storeId` is not cleared by a project switch (`projectSwitched`, `:388`: the store id belongs to
am, not to the project, as `watchCursor` is kept there), by the watch ending (`forgetHello`,
`:344`), or by an `AmMissing` snapshot. An am that comes back with another store is caught by
the next snapshot or hello naming it.

### Header and doc comments

- Header (`RunStore.qml:6-25`): add that a hello or snapshot naming a `store_id` other than the
  one last seen starts over like a `cursorReset`, and that the first one seen resets nothing.
- `watchLine`: the hello shape gains `head` and `storeId` and the storeId rule.
- `applySnapshot`, `applyRunRead`/`readReplied`, `resetCursor`: the store_id rule of each.

## Known consequences (not changed here)

- A list snapshot that reveals a new store does not restart the watch; the watch's own next
  hello (if it reconnects) is then "same id". The watch helper's cursor handling is 4.1.1's.
- A list reply with the old store id that lands after a hello reset cannot apply: `resetCursor()`
  launches a new list snapshot and the snapshot runner is latest-wins.

## Error table

| case | behaviour |
|---|---|
| hello/snapshot/run read with the seen id | nothing beyond today's behaviour |
| first store id ever (seen id `""`) | recorded; nothing reset; reply applied |
| hello with a different id | recorded; `resetCursor()` once (one list snapshot), even with `cursorReset: true` |
| hello with a different id and a higher `head`, `cursorReset: false` | same as above (the case `cursorReset` misses) |
| list reply with a different id | recorded; cursor, nudges, debounce, in-flight reads, runs, alerts cleared; reply applied; no extra snapshot; no toast; arms while active |
| run read with a different id | recorded; reply not applied; `resetCursor()` (one list snapshot); no toast |
| store id `""`, missing, non-string | ignored: no reset, `storeId` kept |
| `ok: false` envelope (any source) | `storeId` untouched; today's error handling |
| project switch, watch exit, `AmMissing` | `storeId` kept |

## Tests

All in the **QML store tier** (`tests/core/stores/tst_run_store.qml`, TestCase
`StoresRunStore`), in a new section `// ---- store id reset (4.1.4)` after the cursor-reset
section (`:4393`). Why this tier: the behaviour is the store's reaction to helper stdout,
driven through stubbed `Process` objects (`reply`, `sendLine`, `readOf`, `nudge`,
`capturedStore`, `capturedList`, `resetHello`), which is what this tier exists for; no helper
or UI changes. Inputs: list replies from `capturedList` (runs.json rows + status data,
`store_id` and `as_of_seq` 989); hellos from `resetHello` (watch-hello.json `schema_2`). A
different store is the fixture id altered, labelled `synthetic:` (e.g. a helper
`otherStore()` returning the fixture id with its last character changed, and a hello builder
taking a store id and a head). Tests 1-4 in `capturedStore()` start with `storeId` equal to
the fixture id.

1. **Hello, same id keeps state**: `capturedStore()`, a cursor line, a nudge; hello with the
   fixture id, `cursorReset: false` → `snapshotRunner.seq` unchanged, `runs.length` 2,
   `asOfSeq` 989, `watchCursor` kept, nudges kept, `alertsArmed` true.
2. **Hello, different id resets then full snapshot**: `capturedStore()`, cursor 1005, a run read
   in flight (`readOf`), a nudge, a selection; synthetic hello with another id, head 1200
   (higher than 1005), `cursorReset: false` → `storeId` the new id; `appliedSeq` empty, `asOfSeq`
   0, `watchCursor` 0, nudges empty, debounce stopped, `runs` empty, `alertsArmed` false,
   selection kept, `snapshotRunner.seq` +1; the dropped read's reply changes nothing; the list
   reply (synthetic: `capturedList`-shape with the new id, a status turned escalated,
   as_of_seq 1200) applies with no toast, `alertsArmed` true, `asOfSeq` 1200, and launches no
   further snapshot (`seq` unchanged by the reply).
3. **Hello, different id with `cursorReset: true`** → exactly one list snapshot.
4. **List snapshot, same id keeps state**: `capturedStore()`, cursor line, nudge; `refresh()`
   and reply `capturedList()` → `watchCursor` kept, nudges kept, debounce still running,
   `storeId` unchanged.
5. **List snapshot, different id resets and applies in place**: `capturedStore()`, cursor 1005,
   run read in flight, nudge; `refresh()`; reply with another id, as_of_seq 1200 and the started
   run escalated (synthetic) → `storeId` new, `watchCursor` 0, nudges empty, debounce stopped,
   the in-flight read's reply changes nothing, runs replaced from the reply, `appliedSeq` 1200 for
   both runs, no toast (the escalation is not alerted), `alertsArmed` true, and
   `snapshotRunner.seq` not advanced by the reply.
6. **First sight via snapshot resets nothing**: `activeStore(capRoot)` whose first list is the
   captured list without `store_id` (synthetic) → `storeId` ""; cursor line and nudge; `refresh()`
   and reply `capturedList()` → `storeId` the fixture id, `watchCursor` and nudges kept, debounce
   running, `snapshotRunner.seq` not advanced by the reply.
7. **First sight via hello resets nothing**: same `""` store; hello with the fixture id →
   `storeId` recorded, `runs.length` 2, `asOfSeq` 989, `watchCursor` kept,
   `snapshotRunner.seq` unchanged.
8. **No store id is ignored**: `capturedStore()`; hellos with `storeId` `""`, `7`, `null`,
   missing, and list replies with `store_id` `""`, `7`, `null`, missing (all synthetic) → no
   reset (no list snapshot launched by the hello or the reply, `watchCursor` and nudges kept),
   `storeId` still the fixture id.
9. **Run read, different id**: `capturedStore()`, nudge and trigger so a read is in flight; its
   reply (synthetic: `runReply` with another id) → run not updated (`appliedSeq[run]` still 989),
   `storeId` new, `watchCursor` 0, `runs` empty, one list snapshot launched, no toast,
   `lastError` "".
10. **Run read, same id**: covered by 4.1.3's run-read tests (they carry the fixture id); add an
    assertion there or here that `storeId` is unchanged.
11. **Kept across a project switch and AmMissing**: `capturedStore()`; switch project →
    `storeId` kept; an `AmMissing` list reply → `storeId` kept.
12. **ok:false leaves it**: a `StoreBusyError` list reply carrying another id (synthetic) →
    `storeId` unchanged, nothing reset beyond today's `stale`.

Existing tests: unchanged and must pass, notably 4.1.3's cursor-reset tests (`:4401-4448`), the
hello tests (`:481-700`, hellos without `storeId`) and the project-switch cursor test (`:4077`).

Flow tier (`tests/core/stores/tst_app_runs.qml`, `tests/ui/tst_runs_flow.qml`,
`tests/ui/tst_runs_real_data.qml`): not extended; they must still pass (their fixtures share one
store id). Architecture tier (`tests/architecture`): unchanged, must pass.

## Out of scope

- Any change to `runs-watch.py`, `runs-snapshot.py` or `runs.js` (they already forward
  `store_id`; 4.1.1, 4.1.2, 4.0.3 are done).
- Persisting `watchCursor` or `storeId`, or passing `--since-seq` to the watch (Alerts
  milestone, P:269).
- Restarting the watch on a store change.
- 4.1.3's refresh-on-nudge and `cursorReset` behaviour beyond sharing the clearing function.
- Global Runs, the timeline, the alert cursor, start-run discovery (4.3, dropped from M4); the
  4.2 spec retargets; the 4.4 docs (`docs/architecture.md`, README).

---

# 4.1.4 RunStore: reset on a changed store_id Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `RunStore` remembers am's last `store_id` and, when a hello, a list snapshot or a run read names a different one, forgets the old store's state and starts over from one full list snapshot without raising alerts.

**Architecture:** One new public property (`storeId`) and two small store functions in `core/stores/RunStore.qml`: `seeStore(id)` records a store id and says whether it changed, and `forgetLive()` holds the live-state clearing that `resetCursor()` and the list-snapshot path share. Each source (list snapshot, hello, run read) calls `seeStore` on its `ok: true` envelope and reacts as the spec says. No helper, domain or UI change.

**Tech Stack:** QML / Quickshell (`QtQml`, `Quickshell`, `Quickshell.Io`), QtTest via `qmltestrunner` with stubbed `Process`es (`tests/stubs`), am fixtures through `tests/helpers/amFixtures.js`. Everything runs through `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/4-1-4-runstore-reset-on-cafd947e.md` (prepended above).

## Global Constraints

- The plugin reads snapshots and treats watch lines as nudges; it never folds events into state.
- No helper changes: `core/backend/runs/runs-watch.py`, `core/backend/runs/runs-snapshot.py` and `core/domain/runs.js` stay as they are.
- Stores import only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain`; `tests/architecture` must pass.
- `cursorReset` behaviour is unchanged: clear `appliedSeq`, the cursor and the list, full snapshot, no alerts. 4.1.3's tests keep passing as written.
- A store id is a non-empty string; anything else (`""`, missing, a number, `null`, an object) is ignored: no reset, `storeId` kept.
- `storeId` is kept across a project switch, the watch ending (`forgetHello`) and an `AmMissing` snapshot.
- `watchCursor` and `storeId` are held in memory only (no persistence in M4).
- Comments and docstrings state the contract only, no narrative.
- am output in tests comes from `tests/fixtures/am/` through `tests/helpers/amFixtures.js`; a hand-built edge case is labelled `synthetic:`. Every capture shares store id `91b9e8afc25044c385859292bfabfde7`, so every "different store" input is synthetic.
- Verification: `bash tests/run.sh` green. TDD: tests first.

## Review Focus

1. A list snapshot naming another store lands while the panel is closed: it is applied as the new store's full snapshot, alerts are not armed and no toast is raised (Task 1, `test_a_list_from_another_store_while_closed_is_applied_without_arming`).
2. A superseded or dropped run read whose reply names another store: it changes nothing, `storeId` included, and launches no list snapshot (Task 3, `test_a_superseded_run_read_naming_another_store_changes_nothing`; also asserted at the end of Task 1's and Task 2's in-place tests).
3. A store that changes and then changes back (A → B → A): each change starts over; going back to the first id is a change too (Task 2, `test_a_store_that_changes_back_starts_over_again`).
4. A list snapshot of the old store already in flight when a hello names a new store: it is never applied (the runner is latest-wins), and the new list is (Task 2, `test_a_list_of_the_old_store_in_flight_at_a_hello_reset_is_never_applied`).
5. A list snapshot naming another store while a run is selected: the selection and its attempt pane stay (Task 1, `test_a_list_from_another_store_keeps_the_selection`).

---

## File Structure

- Modify: `core/stores/RunStore.qml` — the `storeId` property (beside `asOfSeq`/`appliedSeq`/`watchCursor`/`nudges`, lines 52-62), `seeStore()` and `forgetLive()` (next to `resetCursor()`, lines 327-341), the `ok: true` branch of `applySnapshot()` (line 602), the hello branch of `watchLine()` (lines 279-283), the `ok: true` branch of `readReplied()` (lines 711-714), and the header and doc comments of those functions.
- Modify: `tests/core/stores/tst_run_store.qml` — a new section `// ---- store id reset (4.1.4)` appended after the last test of the cursor-reset section (`test_only_a_true_cursor_reset_starts_over`, ending at line 4448), i.e. immediately before the file's final closing `}` on line 4449. Every task appends its tests at the end of this section, again immediately before that final `}`.

Test helpers already in the file that the new tests use (do not redefine them):

- `make()`, `makeWithProject(root)`, `activeStore(root)` — stores (lines 25-36, 324-329).
- `reply(proc, text, code)` — sets `proc.outText` and emits `proc.exited(code)` (line 38).
- `sendLine(proc, value)` — one watch stdout line; objects are JSON-encoded (line 422).
- `fire(timer)` — triggers a timer synchronously (line 801).
- `endWatch(proc, line, code)` — last watch line, then exit (line 961).
- `ids(list)` — run ids joined by `,` (line 1120).
- `capturedList(extra, asOf)` — the captured list reply, `store_id` = fixture id, `as_of_seq` 989 unless `asOf` given (line 3881).
- `capturedStore(extra)` — active store on `tc.capRoot` whose first list was `capturedList(extra)`; its watch runs (line 3982).
- `nudge(store, pairs)` — one `{"changed": [...]}` line (line 3991).
- `runReply(run, name)` — a `--run` reply from fixture `name` (line 4092).
- `readOf(store, run, seq)` — nudge + debounce fire, returns the read's `Process` (line 4100).
- `resetHello(value)` — schema_2 hello (`head` 1005, `storeId` = fixture id) with `cursorReset: value` (line 4397).
- `tc.capRoot`, `tc.startedRun` (`20261008T143823Z-e795ad19`, runs[0]), `tc.doneRun` (`20261008T143807Z-63060df3`, runs[1]), `rootB`.

Running the store tests: `bash tests/run.sh tst_run_store` (it runs pytest first, then only QML test files whose path contains `tst_run_store`). A failing QML test prints a line `FAIL!  : StoresRunStore::<test_name>() ...` followed by its `Loc:` line; the `Totals:` line gives the pass/fail counts. The script exits non-zero on any failure.

---

### Task 1: `storeId`, the shared clearing, and the list-snapshot source

**Files:**
- Modify: `core/stores/RunStore.qml:52-62` (property), `:327-341` (`resetCursor`, new `seeStore`, `forgetLive`), `:589-602` (`applySnapshot` doc and `ok: true` branch)
- Test: `tests/core/stores/tst_run_store.qml` (new section before the final `}` at line 4449)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces:
  - `property string storeId` on the store (`""` until a store id is seen).
  - `function seeStore(id) -> bool`: records `id` when it is a non-empty string; returns `true` only when `storeId` was non-empty and differs from `id`.
  - `function forgetLive()`: `watchCursor = 0`, `nudges = {}`, `debounceTimer.stop()`, `dropReads()`, `runs = []`, `alertsArmed = false`.
  - `function resetCursor()`: unchanged behaviour, now `appliedSeq = {}`, `asOfSeq = 0`, `forgetLive()`, `refresh()`.
  - Test helpers `fixtureStore() -> string`, `otherStore() -> string`, `storeList(id, asOf, escalate) -> string`, `unnamedStore() -> store` (used by Tasks 2 and 3).

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_store.qml`, insert the following immediately before the file's final closing `}` (line 4449, right after `test_only_a_true_cursor_reset_starts_over`):

```qml

  // ---- store id reset (4.1.4)

  // The captures' store_id: every capture shares it.
  function fixtureStore() { return F.load("runs.json").data.store_id }

  // synthetic: another am store's id -- the fixture id with its last
  // character changed.
  function otherStore() {
    var id = fixtureStore()
    return id.slice(0, -1) + (id.charAt(id.length - 1) === "0" ? "1" : "0")
  }

  // synthetic: capturedList's reply at `asOf` (989 when undefined) with
  // store_id `id` (the key absent when undefined); with `escalate`, the
  // started run's status is status-escalated.json's data.
  function storeList(id, asOf, escalate) {
    var value = JSON.parse(capturedList([], asOf))
    if (id === undefined) delete value.store_id
    else value.store_id = id
    if (escalate) value.runs[0].status = F.load("status-escalated.json").data
    return JSON.stringify(value) + "\n"
  }

  // An active store on the captured runs' project whose first list named no
  // store (synthetic: storeList without store_id): storeId is still "" and
  // the watch runs.
  function unnamedStore() {
    var store = activeStore(tc.capRoot); if (!store) return null
    reply(store.snapshotRunner.current, storeList(undefined), 0)
    verify(store.watchProc, "the watch was started")
    return store
  }

  function test_a_store_id_starts_as_none() {
    var store = make(); if (!store) return
    compare(store.storeId, "")
  }

  function test_a_list_with_the_seen_store_id_keeps_the_live_state() {
    var store = capturedStore(); if (!store) return
    compare(store.storeId, fixtureStore(), "the first list named the store")
    sendLine(store.watchProc, { cursor: 1005 })
    nudge(store, [tc.doneRun, 1005])
    store.refresh()
    var seq = store.snapshotRunner.seq
    reply(store.snapshotRunner.current, capturedList(), 0)
    compare(store.storeId, fixtureStore())
    compare(store.watchCursor, 1005)
    compare(store.nudges[tc.doneRun], 1005)
    compare(store.debounceTimer.running, true)
    compare(store.snapshotRunner.seq, seq, "no further list snapshot")
  }

  function test_a_list_from_another_store_starts_over_in_place() {
    var store = capturedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    var proc = readOf(store, tc.doneRun, 1005)
    nudge(store, [tc.startedRun, 1006])
    store.refresh()
    var seq = store.snapshotRunner.seq
    reply(store.snapshotRunner.current, storeList(otherStore(), 1200, true), 0)
    compare(store.storeId, otherStore())
    compare(store.watchCursor, 0)
    compare(Object.keys(store.nudges).length, 0)
    compare(store.debounceTimer.running, false)
    compare(ids(store.runs), tc.startedRun + "," + tc.doneRun, "the reply is the new store's full snapshot")
    compare(store.runs[0].status, "escalated")
    compare(store.asOfSeq, 1200)
    compare(store.appliedSeq[tc.startedRun], 1200)
    compare(store.appliedSeq[tc.doneRun], 1200)
    compare(store.toasts.length, 0, "the new store's first list only arms")
    compare(store.alertsArmed, true)
    compare(store.snapshotRunner.seq, seq, "no further list snapshot")
    var before = store.runs
    // synthetic: status-done.json's run read under the new store, newer than the list.
    var late = JSON.parse(runReply(tc.doneRun, "status-done.json"))
    late.store_id = otherStore()
    late.as_of_seq = 1300
    reply(proc, JSON.stringify(late) + "\n", 0)
    verify(store.runs === before, "the old store's read in flight was dropped")
    compare(store.appliedSeq[tc.doneRun], 1200)
    compare(store.storeId, otherStore())
  }

  // Review Focus 1.
  function test_a_list_from_another_store_while_closed_is_applied_without_arming() {
    var store = makeWithProject(tc.capRoot); if (!store) return
    reply(store.snapshotRunner.current, capturedList(), 0)
    compare(store.storeId, fixtureStore())
    store.refresh()
    reply(store.snapshotRunner.current, storeList(otherStore(), 1200, true), 0)
    compare(store.storeId, otherStore())
    compare(store.runs[0].status, "escalated")
    compare(store.asOfSeq, 1200)
    compare(store.alertsArmed, false, "a closed panel never arms")
    compare(store.toasts.length, 0)
  }

  // Review Focus 5.
  function test_a_list_from_another_store_keeps_the_selection() {
    var store = capturedStore(); if (!store) return
    store.selectedRunId = tc.startedRun
    verify(store.selectedAttempt !== null, "its default attempt is shown")
    var attempt = store.selectedAttempt
    store.refresh()
    reply(store.snapshotRunner.current, storeList(otherStore(), 1200), 0)
    compare(store.storeId, otherStore())
    compare(store.selectedRunId, tc.startedRun)
    verify(store.selectedAttempt === attempt, "the pane stays on its attempt")
  }

  function test_the_first_store_id_a_list_names_resets_nothing() {
    var store = unnamedStore(); if (!store) return
    compare(store.storeId, "", "a list without store_id names no store")
    sendLine(store.watchProc, { cursor: 1005 })
    nudge(store, [tc.doneRun, 1005])
    store.refresh()
    var seq = store.snapshotRunner.seq
    reply(store.snapshotRunner.current, capturedList(), 0)
    compare(store.storeId, fixtureStore())
    compare(store.watchCursor, 1005)
    compare(store.nudges[tc.doneRun], 1005)
    compare(store.debounceTimer.running, true)
    compare(store.snapshotRunner.seq, seq, "no further list snapshot")
  }

  function test_a_list_without_a_store_id_is_ignored() {
    var store = capturedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    nudge(store, [tc.doneRun, 1005])
    var bad = ["", 7, null, { id: "x" }, undefined]
    for (var i = 0; i < bad.length; i++) {
      var label = "store_id " + JSON.stringify(bad[i])
      store.refresh()
      var seq = store.snapshotRunner.seq
      reply(store.snapshotRunner.current, storeList(bad[i]), 0)
      compare(store.storeId, fixtureStore(), label)
      compare(store.watchCursor, 1005, label)
      compare(store.nudges[tc.doneRun], 1005, label)
      compare(store.runs.length, 2, label)
      compare(store.snapshotRunner.seq, seq, label + ": no further list snapshot")
    }
  }

  function test_the_store_id_outlives_the_watch_a_project_switch_and_am_missing() {
    var store = capturedStore(); if (!store) return
    endWatch(store.watchProc, "", 0)
    compare(store.storeId, fixtureStore(), "the watch ending")
    store.active = false
    compare(store.storeId, fixtureStore(), "the panel closing")
    store.project = rootB
    compare(store.storeId, fixtureStore(), "a project switch")
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "AmMissing", "message": "am is not installed."}}\n', 1)
    compare(store.amStatus, "missing")
    compare(store.storeId, fixtureStore(), "AmMissing")
  }

  function test_a_refused_list_naming_another_store_changes_no_store_id() {
    var store = capturedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    store.refresh()
    // synthetic: am's StoreBusyError envelope carrying another store's id.
    reply(store.snapshotRunner.current, JSON.stringify({ ok: false, store_id: otherStore(),
          error: { type: "StoreBusyError", message: "the am store is busy; try again" } }) + "\n", 1)
    compare(store.storeId, fixtureStore())
    compare(store.stale, true)
    compare(ids(store.runs), tc.startedRun + "," + tc.doneRun)
    compare(store.watchCursor, 1005)
    compare(store.asOfSeq, 989)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL. The new tests fail because `store.storeId` does not exist (`compare` sees `undefined`), e.g. `FAIL!  : StoresRunStore::test_a_store_id_starts_as_none() Compared values are not the same`; `test_a_list_from_another_store_starts_over_in_place` also fails on `watchCursor` (1005, not 0) and on the toast count (the escalation is alerted). Every test that existed before still passes.

- [ ] **Step 3: Add the `storeId` property**

In `core/stores/RunStore.qml`, replace

```qml
  // {runId: seq}: the highest changed seq per run since the last debounce
  // trigger. Replaced, never changed in place.
  property var nudges: ({})
```

with

```qml
  // {runId: seq}: the highest changed seq per run since the last debounce
  // trigger. Replaced, never changed in place.
  property var nudges: ({})
  // am's store_id from the last hello or snapshot that named one; "" = none
  // yet. Replaced, never derived. A project switch, the watch ending and
  // AmMissing keep it.
  property string storeId: ""
```

- [ ] **Step 4: Split `resetCursor()` and add `seeStore()` and `forgetLive()`**

In `core/stores/RunStore.qml`, replace

```qml
  // The watch's hello says its cursor no longer holds: the coverage, the
  // cursor and the nudges are forgotten, the runs emptied, the alerts disarmed
  // (the next list snapshot only arms), every run read in flight dropped, and
  // one list snapshot launched. Selection, logs, controls and dispatch stay.
  function resetCursor() {
    store.appliedSeq = {}
    store.asOfSeq = 0
    store.watchCursor = 0
    store.nudges = {}
    debounceTimer.stop()
    store.runs = []
    store.alertsArmed = false
    store.dropReads()
    store.refresh()
  }
```

with

```qml
  // Starts over: the coverage (appliedSeq, asOfSeq) and the live state
  // (forgetLive) are forgotten and one list snapshot is launched.
  function resetCursor() {
    store.appliedSeq = {}
    store.asOfSeq = 0
    store.forgetLive()
    store.refresh()
  }

  // The live state of the store last seen is forgotten: the cursor, the
  // nudges and their debounce, every run read in flight (its reply changes
  // nothing), the runs, and the alerts (the next list snapshot only arms).
  // Selection, logs, controls and dispatch stay.
  function forgetLive() {
    store.watchCursor = 0
    store.nudges = {}
    debounceTimer.stop()
    store.dropReads()
    store.runs = []
    store.alertsArmed = false
  }

  // A store id seen in a hello or a good snapshot. A non-empty string is
  // recorded as storeId; anything else is no store id and changes nothing.
  // Returns whether it names another store than the one last seen: storeId
  // was non-empty and differs. The first one seen is no change.
  function seeStore(id) {
    if (typeof id !== "string" || id === "") return false
    var changed = store.storeId !== "" && store.storeId !== id
    store.storeId = id
    return changed
  }
```

- [ ] **Step 5: Read the list snapshot's `store_id`**

In `core/stores/RunStore.qml`, replace

```qml
  // entry with an id, of every project. StoreBusyError keeps everything and
  // only marks the runs stale. AmMissing empties them and the coverage: no
```

with

```qml
  // entry with an id, of every project. Its store_id is recorded (seeStore);
  // one naming another store than the one last seen first forgets the old
  // store's live state (forgetLive), so the reply is applied as the new
  // store's full snapshot, raises no toast and launches no other snapshot.
  // StoreBusyError keeps everything and
  // only marks the runs stale. AmMissing empties them and the coverage: no
```

Then, in `applySnapshot`, replace

```qml
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var list = Array.isArray(envelope.runs) ? envelope.runs : []
```

with

```qml
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      if (store.seeStore(envelope.store_id)) store.forgetLive()
      var list = Array.isArray(envelope.runs) ? envelope.runs : []
```

(`forgetLive()` sets `alertsArmed = false` before the existing `Runs.newAlerts(store.alertsArmed ? store.runs : null, out)` line, so the comparison is against `null` and nothing is alerted; the existing `if (store.active) { ... store.alertsArmed = true }` arms it.)

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: PASS — no `FAIL!` lines, `Totals:` shows 0 failed, exit status 0. 4.1.3's `test_a_cursor_reset_starts_over_from_a_list_snapshot` and `test_only_a_true_cursor_reset_starts_over` still pass.

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): record am's store_id and start over in place on a list from another store"
```

---

### Task 2: the hello source

**Files:**
- Modify: `core/stores/RunStore.qml` — the `watchLine` doc comment and its hello branch (currently lines 261-283)
- Test: `tests/core/stores/tst_run_store.qml` (append before the final `}`)

**Interfaces:**
- Consumes (Task 1): `store.storeId`, `store.seeStore(id) -> bool`, `store.resetCursor()`; test helpers `fixtureStore()`, `otherStore()`, `storeList(id, asOf, escalate)`, `unnamedStore()`.
- Produces: test helper `storeHello(id, head, reset) -> object` (a hello line value for `sendLine`).

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_store.qml`, insert the following immediately before the file's final closing `}` (after `test_a_refused_list_naming_another_store_changes_no_store_id`):

```qml

  // synthetic: runs-watch.py's forwarded schema_2 hello (resetHello) with
  // storeId `id` (the key absent when undefined), head `head` and
  // cursorReset `reset`.
  function storeHello(id, head, reset) {
    var value = resetHello(reset)
    value.hello.head = head
    if (id === undefined) delete value.hello.storeId
    else value.hello.storeId = id
    return value
  }

  function test_a_hello_with_the_seen_store_id_keeps_the_live_state() {
    var store = capturedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    nudge(store, [tc.doneRun, 1005])
    var seq = store.snapshotRunner.seq
    sendLine(store.watchProc, storeHello(fixtureStore(), 1005, false))
    compare(store.amSchema, 2)
    compare(store.storeId, fixtureStore())
    compare(store.snapshotRunner.seq, seq, "no list snapshot")
    compare(store.runs.length, 2)
    compare(store.asOfSeq, 989)
    compare(store.watchCursor, 1005)
    compare(store.nudges[tc.doneRun], 1005)
    compare(store.alertsArmed, true)
  }

  function test_a_hello_from_another_store_starts_over_from_a_list_snapshot() {
    var store = capturedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    var proc = readOf(store, tc.doneRun, 1005)
    nudge(store, [tc.startedRun, 1006])
    store.selectedRunId = tc.doneRun
    var seq = store.snapshotRunner.seq
    // A head above the cursor: cursorReset is false, yet the store changed.
    sendLine(store.watchProc, storeHello(otherStore(), 1200, false))
    compare(store.amSchema, 2, "still a hello")
    compare(store.storeId, otherStore())
    compare(Object.keys(store.appliedSeq).length, 0)
    compare(store.asOfSeq, 0)
    compare(store.watchCursor, 0)
    compare(Object.keys(store.nudges).length, 0)
    compare(store.debounceTimer.running, false)
    compare(store.runs.length, 0)
    compare(store.alertsArmed, false)
    compare(store.selectedRunId, tc.doneRun, "the selection is untouched")
    compare(store.snapshotRunner.seq, seq + 1, "one list snapshot")
    var list = store.snapshotRunner.current
    reply(proc, runReply(tc.doneRun, "status-done.json"), 0)
    compare(store.runs.length, 0, "the dropped read changes nothing")
    compare(Object.keys(store.appliedSeq).length, 0)
    compare(store.storeId, otherStore(), "the dropped read names no store")
    reply(list, storeList(otherStore(), 1200, true), 0)
    compare(store.runs[0].status, "escalated")
    compare(store.toasts.length, 0, "the new store's first list only arms")
    compare(store.alertsArmed, true)
    compare(store.asOfSeq, 1200)
    compare(store.snapshotRunner.seq, seq + 1, "its reply launches no further snapshot")
  }

  function test_a_hello_from_another_store_with_cursor_reset_launches_one_list() {
    var store = capturedStore(); if (!store) return
    var seq = store.snapshotRunner.seq
    sendLine(store.watchProc, storeHello(otherStore(), 900, true))
    compare(store.snapshotRunner.seq, seq + 1, "one list snapshot, not two")
    compare(store.storeId, otherStore())
    compare(store.runs.length, 0)
  }

  function test_the_first_store_id_a_hello_names_resets_nothing() {
    var store = unnamedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    var seq = store.snapshotRunner.seq
    sendLine(store.watchProc, storeHello(fixtureStore(), 1005, false))
    compare(store.storeId, fixtureStore())
    compare(store.runs.length, 2)
    compare(store.asOfSeq, 989)
    compare(store.watchCursor, 1005)
    compare(store.snapshotRunner.seq, seq, "no list snapshot")
  }

  function test_a_hello_without_a_store_id_is_ignored() {
    var store = capturedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    nudge(store, [tc.doneRun, 1005])
    var bad = ["", 7, null, { id: "x" }, undefined]
    for (var i = 0; i < bad.length; i++) {
      var label = "storeId " + JSON.stringify(bad[i])
      var seq = store.snapshotRunner.seq
      sendLine(store.watchProc, storeHello(bad[i], 1200, false))
      compare(store.storeId, fixtureStore(), label)
      compare(store.snapshotRunner.seq, seq, label + ": no list snapshot")
      compare(store.runs.length, 2, label)
      compare(store.watchCursor, 1005, label)
      compare(store.nudges[tc.doneRun], 1005, label)
    }
    var before = store.snapshotRunner.seq
    sendLine(store.watchProc, storeHello(undefined, 900, true))
    compare(store.snapshotRunner.seq, before + 1, "cursorReset alone still starts over")
    compare(store.storeId, fixtureStore())
  }

  // Review Focus 3.
  function test_a_store_that_changes_back_starts_over_again() {
    var store = capturedStore(); if (!store) return
    var seq = store.snapshotRunner.seq
    sendLine(store.watchProc, storeHello(otherStore(), 1200, false))
    reply(store.snapshotRunner.current, storeList(otherStore(), 1200), 0)
    compare(store.snapshotRunner.seq, seq + 1)
    sendLine(store.watchProc, { cursor: 1210 })
    sendLine(store.watchProc, storeHello(fixtureStore(), 1300, false))
    compare(store.storeId, fixtureStore(), "the first store again is a change too")
    compare(store.watchCursor, 0)
    compare(store.runs.length, 0)
    compare(store.snapshotRunner.seq, seq + 2)
  }

  // Review Focus 4.
  function test_a_list_of_the_old_store_in_flight_at_a_hello_reset_is_never_applied() {
    var store = capturedStore(); if (!store) return
    store.refresh()
    var old = store.snapshotRunner.current
    sendLine(store.watchProc, storeHello(otherStore(), 1200, false))
    reply(old, capturedList(), 0)
    compare(store.runs.length, 0, "the old store's list was superseded")
    compare(store.storeId, otherStore(), "and names no store")
    reply(store.snapshotRunner.current, storeList(otherStore(), 1200), 0)
    compare(store.asOfSeq, 1200)
    compare(store.runs.length, 2)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL. `test_a_hello_from_another_store_starts_over_from_a_list_snapshot`, `test_a_hello_from_another_store_with_cursor_reset_launches_one_list` (storeId not recorded), `test_the_first_store_id_a_hello_names_resets_nothing`, `test_a_store_that_changes_back_starts_over_again` and `test_a_list_of_the_old_store_in_flight_at_a_hello_reset_is_never_applied` print `FAIL!  : StoresRunStore::<name>()`. `test_a_hello_with_the_seen_store_id_keeps_the_live_state` and `test_a_hello_without_a_store_id_is_ignored` already pass (they pin what must not change). All Task 1 and older tests pass.

- [ ] **Step 3: Read the hello's `storeId`**

In `core/stores/RunStore.qml`, replace

```qml
  // {"ok": false, ...} is kept as the envelope its exit explains. The hello,
  // {"hello": {"schema": N, "am": V, "cursorReset": B}}, sets amSchema to N
  // (an integer of 1 or more, else 0) and amVersion to V (a string, else "");
  // B === true starts over (resetCursor), anything else starts nothing.
```

with

```qml
  // {"ok": false, ...} is kept as the envelope its exit explains. The hello,
  // {"hello": {"schema": N, "am": V, "head": H, "cursorReset": B,
  // "storeId": S}}, sets amSchema to N (an integer of 1 or more, else 0) and
  // amVersion to V (a string, else ""), and records S (seeStore). B === true,
  // or an S naming another store than the one last seen, starts over
  // (resetCursor) once; anything else starts nothing. H is not read.
```

Then replace

```qml
      store.amVersion = typeof value.hello.am === "string" ? value.hello.am : ""
      if (value.hello.cursorReset === true) store.resetCursor()
```

with

```qml
      store.amVersion = typeof value.hello.am === "string" ? value.hello.am : ""
      var changed = store.seeStore(value.hello.storeId)
      if (changed || value.hello.cursorReset === true) store.resetCursor()
```

(`seeStore` runs first and always, so a hello that is both a change and `cursorReset: true` still records the id and calls `resetCursor()` once; the list it launches carries the new id, which is then "same id".)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: PASS — no `FAIL!` lines, exit status 0. The hello tests at lines 481-700 (hellos without `storeId`) still pass.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): start over from a list snapshot on a hello naming another store"
```

---

### Task 3: the run-read source, the header, and the full suite

**Files:**
- Modify: `core/stores/RunStore.qml` — the header (lines 6-25, the sentence at lines 15-17), the `readReplied` doc comment and its `ok: true` branch (currently lines 689-714)
- Test: `tests/core/stores/tst_run_store.qml` (append before the final `}`)

**Interfaces:**
- Consumes (Task 1): `store.storeId`, `store.seeStore(id) -> bool`, `store.resetCursor()`; test helpers `fixtureStore()`, `otherStore()`, `storeList(id, asOf, escalate)`, `unnamedStore()`.
- Produces: test helper `storeRead(run, name, id) -> string`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_store.qml`, insert the following immediately before the file's final closing `}` (after `test_a_list_of_the_old_store_in_flight_at_a_hello_reset_is_never_applied`):

```qml

  // synthetic: runReply(run, name) with store_id `id` (the key absent when
  // undefined).
  function storeRead(run, name, id) {
    var value = JSON.parse(runReply(run, name))
    value.store_id = id
    return JSON.stringify(value) + "\n"
  }

  function test_a_run_read_from_another_store_is_not_applied_and_starts_over() {
    var store = capturedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    var proc = readOf(store, tc.startedRun, 1005)
    var seq = store.snapshotRunner.seq
    reply(proc, storeRead(tc.startedRun, "status-escalated.json", otherStore()), 0)
    compare(store.storeId, otherStore())
    compare(store.appliedSeq[tc.startedRun], undefined, "not applied: the coverage starts over")
    compare(store.asOfSeq, 0)
    compare(store.watchCursor, 0)
    compare(store.runs.length, 0)
    compare(store.alertsArmed, false)
    compare(store.toasts.length, 0, "the escalation is not alerted")
    compare(store.lastError, "")
    compare(store.amStatus, "ok")
    compare(store.snapshotRunner.seq, seq + 1, "one list snapshot")
    reply(store.snapshotRunner.current, storeList(otherStore(), 1200, true), 0)
    compare(store.runs[0].status, "escalated")
    compare(store.toasts.length, 0, "the new store's first list only arms")
    compare(store.alertsArmed, true)
    compare(store.snapshotRunner.seq, seq + 1, "its reply launches no further snapshot")
  }

  function test_a_run_read_with_the_seen_or_a_first_store_id_is_applied() {
    var store = capturedStore(); if (!store) return
    var seq = store.snapshotRunner.seq
    reply(readOf(store, tc.doneRun, 1005), runReply(tc.doneRun, "status-done.json"), 0)
    compare(store.appliedSeq[tc.doneRun], 1005, "the seen store")
    compare(store.storeId, fixtureStore())
    compare(store.snapshotRunner.seq, seq)
    var fresh = unnamedStore(); if (!fresh) return
    var freshSeq = fresh.snapshotRunner.seq
    reply(readOf(fresh, tc.doneRun, 1005), runReply(tc.doneRun, "status-done.json"), 0)
    compare(fresh.appliedSeq[tc.doneRun], 1005, "a first store id")
    compare(fresh.storeId, fixtureStore(), "is recorded")
    compare(fresh.snapshotRunner.seq, freshSeq)
  }

  function test_a_run_read_without_a_store_id_is_applied() {
    var store = capturedStore(); if (!store) return
    var bad = ["", 7, null, { id: "x" }, undefined]
    for (var i = 0; i < bad.length; i++) {
      var label = "store_id " + JSON.stringify(bad[i])
      var proc = readOf(store, tc.doneRun, 1006 + i)
      var seq = store.snapshotRunner.seq
      reply(proc, storeRead(tc.doneRun, "status-done.json", bad[i]), 0)
      compare(store.appliedSeq[tc.doneRun], 1005, label)
      compare(store.storeId, fixtureStore(), label)
      compare(store.runs.length, 2, label)
      compare(store.snapshotRunner.seq, seq, label + ": no list snapshot")
    }
  }

  function test_a_refused_run_read_naming_another_store_changes_no_store_id() {
    var store = capturedStore(); if (!store) return
    var proc = readOf(store, tc.doneRun, 1005)
    // synthetic: am's StoreBusyError envelope carrying another store's id.
    reply(proc, JSON.stringify({ ok: false, store_id: otherStore(),
          error: { type: "StoreBusyError", message: "the am store is busy; try again" } }) + "\n", 1)
    compare(store.storeId, fixtureStore())
    compare(store.stale, true)
    compare(store.runs.length, 2)
  }

  // Review Focus 2.
  function test_a_superseded_run_read_naming_another_store_changes_nothing() {
    var store = capturedStore(); if (!store) return
    var older = readOf(store, tc.doneRun, 1000)
    readOf(store, tc.doneRun, 1005)
    var seq = store.snapshotRunner.seq
    reply(older, storeRead(tc.doneRun, "status-done.json", otherStore()), 0)
    compare(store.storeId, fixtureStore())
    compare(store.runs.length, 2)
    compare(store.snapshotRunner.seq, seq, "no list snapshot")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL. `test_a_run_read_from_another_store_is_not_applied_and_starts_over` (the read is applied, a toast is raised, `storeId` unchanged) and `test_a_run_read_with_the_seen_or_a_first_store_id_is_applied` (`fresh.storeId` stays `""`) print `FAIL!  : StoresRunStore::<name>()`. `test_a_run_read_without_a_store_id_is_applied`, `test_a_refused_run_read_naming_another_store_changes_no_store_id` and `test_a_superseded_run_read_naming_another_store_changes_nothing` already pass (they pin what must not change). All earlier tests pass.

- [ ] **Step 3: Read the run read's `store_id`**

In `core/stores/RunStore.qml`, replace

```qml
  // One run read's reply. The runner leaves readRunners and is destroyed. A
  // reply that is not its run's latest read, or for a project the user has
  // left, changes nothing. ok:true goes to applyRunRead. UnknownRunError
```

with

```qml
  // One run read's reply. The runner leaves readRunners and is destroyed. A
  // reply that is not its run's latest read, or for a project the user has
  // left, changes nothing. ok:true records its store_id (seeStore): one
  // naming another store than the one last seen is not applied and starts
  // over (resetCursor), raising no toast and leaving amStatus and lastError;
  // else it goes to applyRunRead. UnknownRunError
```

Then replace

```qml
    if (envelope.ok === true) {
      store.applyRunRead(runId, envelope)
      return
    }
```

with

```qml
    if (envelope.ok === true) {
      if (store.seeStore(envelope.store_id)) store.resetCursor()
      else store.applyRunRead(runId, envelope)
      return
    }
```

(This sits after the existing `if (!current) return`, so a superseded, dropped or other-project reply never reaches `seeStore`.)

- [ ] **Step 4: Update the header**

In `core/stores/RunStore.qml`, replace

```qml
// it does not know. A cursorReset hello starts over from a list snapshot.
// asOfSeq is the last list's as_of_seq and watchCursor the watch's last
// cursor, held in memory only. Logs are fetched on a selection, on Refresh and
// when a snapshot changes the selected attempt's status -- never on a timer.
```

with

```qml
// it does not know. A cursorReset hello starts over from a list snapshot, as
// does a hello or a run read naming a store_id other than the one last seen
// (storeId); a list snapshot naming one is applied as the new store's full
// snapshot. The first store_id seen resets nothing. asOfSeq is the last
// list's as_of_seq and watchCursor the watch's last cursor, held in memory
// only. Logs are fetched on a selection, on Refresh and when a snapshot
// changes the selected attempt's status -- never on a timer.
```

- [ ] **Step 5: Run the store tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: PASS — no `FAIL!` lines, exit status 0.

- [ ] **Step 6: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest passes (including `tests/architecture`), every QML file prints a `Totals:` line with 0 failed — notably `tests/core/stores/tst_app_runs.qml`, `tests/ui/tst_runs_flow.qml` and `tests/ui/tst_runs_real_data.qml` — no `TypeError`/`ReferenceError` lines, and the script exits 0.

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): start over on a run read naming another store and state the store_id contract"
```

---

## Notes against the spec

- Spec test 9 says the run read from another store leaves `appliedSeq[run]` "still 989". That contradicts the spec's own behaviour for that case (`resetCursor()` clears `appliedSeq`). The plan follows the behaviour: the read is not applied, so `appliedSeq[run]` is never set to the read's `as_of_seq`; after `resetCursor()` it is `undefined` until the new list lands.
- Spec test 10 (run read, same id) and the error table's "first store id ever" for the run-read source are both covered by `test_a_run_read_with_the_seen_or_a_first_store_id_is_applied`.
- `resetCursor()` now calls `dropReads()` before `runs = []` (inside `forgetLive()`); the order of these assignments has no observable effect in the store, and 4.1.3's tests pin the outcome.
<!-- task-pipeline: validated -->
