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
