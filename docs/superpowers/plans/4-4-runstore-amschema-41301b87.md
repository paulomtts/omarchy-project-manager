# 4.4 RunStore: amSchema and amVersion from the watch hello: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `RunStore` gains `amSchema` / `amVersion`, set from the current watch's `{"hello": {"schema": N, "am": V}}` line and reset to `0` / `""` whenever there is no current watch hello.

**Architecture:** Two plain writable properties next to `amStatus`. `watchLine` gets a third branch (after `changed` and `ok: false`) that reads a non-null, non-array object `hello` into both properties and starts nothing. A small `forgetHello()` function resets both and is called from `stopWatch()`, `startWatch()` and the current watch's `watchExited()`. The existing `isCurrentWatch` guard already drops stale lines and exits.

**Tech Stack:** QML (Qt 6 / Quickshell), JavaScript in QML, `qmltestrunner` with the stub `Process` objects in `tests/stubs`, fixtures read through `tests/helpers/amFixtures.js`.

**Spec:** `docs/superpowers/specs/4-4-runstore-amschema-41301b87.md`. The full text is copied below.

## Spec (verbatim)

> # 4.4 RunStore: amSchema and amVersion from the watch hello (card 41301b87)
>
> This narrows `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
> (called "the parent" below). It draws on these parts of the parent:
> - Decision 8 (line 172).
> - "Both spellings, both schemas": lines 286-289, the `runs-watch.py` bullet at
>   lines 296-300 (the shape of the line this card reads) and the `RunStore`
>   bullet at lines 301-302 (this card).
> - The `watch-hello.json` fixture row (line 248) and the fixture rule (lines
>   257-267).
> - "Not changed" (line 314: `RunStore`'s public API changes only by `amSchema` /
>   `amVersion`).
>
> The parent story is 27d8a320, work breakdown item 4 (parent lines 329-330).
>
> This card covers only the `RunStore.amSchema` / `amVersion` part of item 4. The
> other parts are owned elsewhere:
> - `runs.js` (4.1), `runs-snapshot.py` (4.2) and `runs-watch.py` (4.3) are
>   already on this branch.
> - The Runs footer that shows these two properties (parent lines 303-304) is a
>   sibling card.
>
> ## Starting point
>
> - `core/backend/runs/runs-watch.py` (card 4.3) prints the first hello it
>   accepts as one line: `{"hello": {"schema": N, "am": V}}`. `N` is the integer 1
>   or 2. `V` is a string, or `""` when am sent no string (parent lines 296-297).
>   The hello comes before any `changed` line. It is printed once per watch
>   process.
> - `core/stores/RunStore.qml`:
>   - The public property block (lines ~25-52) has no `amSchema` / `amVersion`.
>   - `watchLine(proc, data)` (lines ~239-250) drops lines that are not from the
>     current watch (`isCurrentWatch`). It parses the line and ignores anything
>     that is not a JSON object. `changed` arrays restart the debounce, and
>     `ok: false` is stored as the envelope. Everything else is ignored,
>     including a `hello` line today.
>   - `stopWatch()` (~209) runs from `stopLive()` (the panel closes),
>     `projectSwitched()` (the project changes, including to `""`) and before
>     restarts.
>   - `startWatch()` (~217) bumps `watchSeq` but does not call `stopWatch()`.
>   - `watchExited(proc, exitCode)` (~255) clears `watching` on any exit of the
>     current watch. For `SchemaMismatch` and `CorruptJournal` it also starts the
>     5 s poll through `startPoll()`.
> - `tests/core/stores/tst_run_store.qml`:
>   - `test_garbage_watch_line_ignored` (line 454) already sends `{"hello": 1}`
>     and requires it to be ignored.
>   - The helpers `watchedStore`, `sendLine`, `endWatch` and `watchError` exist,
>     and `F.load` reads `tests/fixtures/am/<name>`.
> - `tests/fixtures/am/watch-hello.json` holds the raw am hello lines.
>   `schema_1` is real (`am: "0.1.0"`, `schema: 1`). `schema_2` is a derived copy
>   (`schema: 2`).
>
> ## Required behaviour
>
> 1. **Two new public properties** on `RunStore`, next to `amStatus`:
>    - `property int amSchema: 0`: the journal schema from the current watch's
>      hello. 0 means unknown.
>    - `property string amVersion: ""`: am's version from that hello. `""` means
>      unknown.
>
>    Each property has a short trailing comment that states this contract. Both
>    are plain writable properties, like `amStatus`, not read-only aliases.
>
> 2. **Reading the hello.** `watchLine` handles a line from the current watch
>    that parses to a non-array JSON object when all of these are true:
>    - its `changed` is not an array;
>    - its `ok` is not `false`;
>    - its `hello` is a non-null, non-array object.
>
>    For such a line:
>    - `amSchema` becomes `hello.schema` when that value is an integer of 1 or
>      more (`typeof` number and `Number.isInteger`, so `true`, `"2"`, `2.5`, `0`,
>      `-1`, `null` and a missing key don't qualify). Otherwise it becomes `0`.
>    - `amVersion` becomes `hello.am` when that value is a string. Otherwise it
>      becomes `""`.
>    - Both are written from the same line. A later hello line from the same
>      watch overwrites both the same way. The helper prints only one, but the
>      store does not rely on that.
>
> 3. **A hello has no other effect.** It does not do any of these:
>    - (re)start the debounce, launch a snapshot or touch the liveness timer;
>    - change `amStatus`, `lastError`, `watchWarning`, `watchSchemaError` or
>      `watching`;
>    - set `proc.envelope`.
>
>    Lines with a `changed` array or `ok: false` keep their current meaning even
>    if they also carry a `hello` key. A `hello` that is not an object (`1`,
>    `"x"`, `[]`, `null`) is ignored as today, and `amSchema` / `amVersion` keep
>    their values.
>
> 4. **Stale hellos are dropped.** A hello line from a watch that fails
>    `isCurrentWatch` changes nothing. That covers a watch that was stopped, an
>    older launch, and the old project after a switch.
>
> 5. **Reset to `0` / `""`.** Both properties go back to their defaults whenever
>    the store has no current watch hello:
>    - the watch is stopped (`stopWatch()`), which covers closing the panel
>      (`active = false`), a project switch (including clearing the project) and
>      every stop before a restart;
>    - the current watch exits with any code (`watchExited` of the current
>      watch). That includes exit 0, and the `SchemaMismatch` / `CorruptJournal`
>      exits after which the poll takes over;
>    - a new watch is launched (`startWatch()`), so a fresh watch starts from
>      unknown until its own hello arrives.
>
>    A watch exit that `isCurrentWatch` rejects resets nothing (rule 4).
>
> 6. **Nothing else about the watch changes.** The following keep their current
>    behaviour, and every existing test in `tst_run_store.qml` passes unchanged:
>    - the argv, `watchSeq` / `watchTried`;
>    - the debounce, the poll fallback and the liveness timer;
>    - the error and warning text;
>    - what a project switch or deactivation clears.
>
> 7. **Comments state the contract only.** The `watchLine` doc comment names the
>    hello line, what it sets, and that it starts nothing. The comments on the
>    reset points (if any are added) say what is reset. Don't write about am's
>    migration, cards or plans.
>
> ## Error paths
>
> | Input line (current watch) | `amSchema` | `amVersion` | Other effects |
> |---|---|---|---|
> | `{"hello": {"schema": 2, "am": "0.1.0"}}` | 2 | `"0.1.0"` | none |
> | `{"hello": {"schema": 1}}` | 1 | `""` | none |
> | `{"hello": {"schema": "2", "am": 5}}` | 0 | `""` | none |
> | `{"hello": {}}` | 0 | `""` | none |
> | `{"hello": 1}`, `{"hello": null}`, `{"hello": []}` | unchanged | unchanged | none (ignored) |
> | a hello line from a stopped / older / other-project watch | unchanged | unchanged | none |
>
> ## Tests (all in `tests/core/stores/tst_run_store.qml`, QML store tier)
>
> **Tier.** These tests belong in the QML store tier. The behaviour lives entirely
> in `RunStore.qml`'s watch handling, which only runs under `qmltestrunner` with
> the stubbed `Process` objects this file already drives. Every other watch test
> lives here, and `bash tests/run.sh` runs it. No pytest or contract test can see
> a QML property. No architecture test is affected, because no component, import
> or icon is added.
>
> **Inputs.** Hello lines come from the fixture through a helper, not typed by
> hand (parent lines 257-267):
>
> ```js
> // The helper's forwarded hello for watch-hello.json's `key` line.
> function helloLine(key) {
>   var h = F.load("watch-hello.json")[key]
>   return { hello: { schema: h.schema, am: h.am } }
> }
> ```
>
> Malformed variants (non-integer schema, non-string or missing `am`) are built on
> a fresh copy of `helloLine("schema_1")`, each with a comment that marks it
> `synthetic:`.
>
> **New tests.** Place them after `test_garbage_watch_line_ignored`, under a
> `// ---- the hello` heading.
>
> 1. `test_am_schema_and_version_default_unknown`: a fresh `make()` store and a
>    `watchedStore` before any line both have `amSchema === 0` and
>    `amVersion === ""` (rule 1).
> 2. `test_hello_sets_schema_and_version`: for `schema_1` and `schema_2`, a fresh
>    `watchedStore` receives `helloLine(key)`. Then `amSchema` is 1 or 2 and
>    `amVersion` is `"0.1.0"` (rule 2).
> 3. `test_hello_starts_nothing`: after `helloLine("schema_2")`, check all of
>    these (rule 3):
>    - `debounceTimer.running === false`;
>    - `snapshotRunner.seq` is unchanged;
>    - `watching === true`;
>    - `amStatus === "ok"`, and `lastError`, `watchWarning` and `watchSchemaError`
>      are all `""`;
>    - `watchProc.envelope` is unchanged (falsy).
>
>    Then a `{changed: ["a"]}` line still starts the debounce.
> 4. `test_malformed_hello_values`: these are synthetic copies, and the table
>    above gives the expected values (rule 2):
>    - schema `"2"`, `true`, `2.5`, `0`, `null` and missing each give
>      `amSchema === 0`;
>    - `am` missing, `5` and `null` each give `amVersion === ""`.
>
>    Each case first sets a known hello so that the reset to 0/`""` is observed.
> 5. `test_non_object_hello_ignored`: after `helloLine("schema_2")`, the lines
>    `{"hello": 1}`, `{"hello": null}` and `{"hello": []}` leave 2 / `"0.1.0"`
>    (rule 3).
> 6. `test_hello_reset_on_deactivate`: hello, then `store.active = false`. Both
>    values are back to 0/`""`. Reactivation alone does not restore them (rule 5).
> 7. `test_hello_reset_on_watch_exit`: hello, then `endWatch(proc, "", 0)`. Both
>    values are 0/`""` (rule 5).
> 8. `test_hello_reset_when_poll_takes_over`: for `SchemaMismatch` and
>    `CorruptJournal`, each on a fresh `watchedStore`:
>    - send the hello, then `endWatch(proc, watchError(type, "m"), 1)`;
>    - both values are 0/`""` and `pollTimer.running === true`;
>    - after a poll tick and its good reply, the values are still 0/`""` (rule 5).
> 9. `test_hello_reset_on_project_switch`: hello, then `store.project = rootB`.
>    Both values are 0/`""`. Then `store.project = ""` after a new hello on B's
>    watch also resets them (rule 5).
> 10. `test_old_watch_hello_ignored`, covering rule 4:
>     - hello on A's watch, then a switch to B, then B's first snapshot (B's
>       watch runs);
>     - a hello from A's old proc leaves 0/`""`;
>     - B's own `helloLine("schema_1")` sets 1/`"0.1.0"`;
>     - a late `exited(0)` from A's old proc leaves 1/`"0.1.0"`.
> 11. `test_new_watch_starts_unknown`: hello, then `active = false`, then
>     `active = true` and a good snapshot (a new watch). Both values are 0/`""`
>     until the new proc sends its own hello (rule 5, `startWatch`).
>
> **Red first.** All eleven fail on today's code. Tests 1, 3 and 5 fail only
> because the properties are missing, and once those exist they pin behaviour
> that is already there. Tests 2, 4 and 6-11 also need `watchLine` to read the
> hello and the reset points to clear it. `test_garbage_watch_line_ignored` is
> unchanged and must stay green.
>
> **Verification.** `bash tests/run.sh` is green, including `tests/architecture`
> and `tests/contract`.
>
> ## Out of scope
>
> - The `RunsScreen` footer text (`am <version> · schema N · watching`, parent
>   lines 303-304): a sibling card.
> - `runs-watch.py`, `runs-snapshot.py`, `runs.js` (cards 4.3, 4.2, 4.1, done).
> - Any new behaviour keyed on `amSchema`. For example, the store does not treat
>   schema 2 differently, does not change `amStatus`, and does not affect the
>   poll.
> - Fixtures, `tests/contract/*`, `docs/architecture.md` and the README (work
>   breakdown item 5).
> - Other `RunStore` API, timers, guards and error text (parent line 314).

## Global Constraints

- `property int amSchema: 0` (0 = unknown) and `property string amVersion: ""` ("" = unknown), plain writable properties next to `amStatus`, each with a short trailing comment stating that contract.
- `amSchema` takes `hello.schema` only when `typeof` is `"number"`, `Number.isInteger` is true and it is `>= 1`; otherwise `0`. `amVersion` takes `hello.am` only when it is a string; otherwise `""`. Both are written from the same line, on every hello line of the current watch.
- A hello is read only when the line's `changed` is not an array, its `ok` is not `false`, and its `hello` is a non-null, non-array object. A non-object `hello` (`1`, `"x"`, `[]`, `null`) leaves both values unchanged.
- A hello starts nothing: no debounce, snapshot or liveness change; `amStatus`, `lastError`, `watchWarning`, `watchSchemaError`, `watching` and `proc.envelope` untouched.
- Reset to `0` / `""` in `stopWatch()`, `startWatch()` and `watchExited()` of the current watch (any exit code). A stale line or exit (`isCurrentWatch` false) changes nothing.
- Argv, `watchSeq` / `watchTried`, debounce, poll, liveness, error/warning text and project-switch/deactivation clearing unchanged; every existing test in `tst_run_store.qml` passes unchanged (`test_garbage_watch_line_ignored` included).
- Comments state the contract only: no text about am's migration, cards or plans.
- Hello lines in tests come from `tests/fixtures/am/watch-hello.json` through `helloLine(key)`; hand-edited variants are fresh copies of `helloLine("schema_1")` with a `synthetic:` comment.
- All tests go in `tests/core/stores/tst_run_store.qml`, after `test_garbage_watch_line_ignored`, under a `// ---- the hello` heading.
- Verification: `bash tests/run.sh` green, `tests/architecture` and `tests/contract` included.
- Not edited: `RunsScreen` / any footer, `runs-watch.py`, `runs-snapshot.py`, `runs.js`, fixtures, `tests/contract/*`, `docs/architecture.md`, README.

## Review Focus

1. A line carrying both a `changed` array (or `ok: false`) and a `hello` object must keep its old meaning and not read the hello (a branch order bug would read both or the wrong one). Pinned in Task 1 by `test_hello_beside_changed_or_ok_false_keeps_its_meaning`.
2. A hello arriving while a `changed` burst is pending must neither cancel nor restart the debounce, and the burst must still cost exactly one snapshot. Pinned in Task 1 by `test_hello_mid_burst_keeps_the_debounce`.
3. A second hello from the same watch overwrites both values, including back to unknown when the second one is malformed (no "keep the first good value" logic). Pinned in Task 1 by `test_a_later_hello_overwrites_both`.
4. A hello object carrying extra keys (am's raw `event` / `runs_dir`, or a future key) and an empty `am: ""` must still read `schema` / `am` exactly. Pinned in Task 1 by `test_hello_extra_keys_are_ignored`.
5. A current watch that dies with a non-zero exit that is neither `SchemaMismatch` nor `CorruptJournal` (e.g. `HelperError`, or 137 with no envelope) must also forget the hello, not only exit 0 and the poll cases. Pinned in Task 2 by the extra cases in `test_hello_reset_on_watch_exit`.

---

## How to run the tests

- The store's QML tests (pytest runs first; that is how the script works): `bash tests/run.sh tst_run_store`
  - Output ends with `== tests/core/stores/tst_run_store.qml`, any `FAIL!  : StoresRunStore::<test>()` lines with their `   Loc:` lines, then `Totals: ...`.
- Everything: `bash tests/run.sh`
- Baseline before this plan: `Totals: 176 passed, 0 failed` for `tst_run_store.qml`; pytest `864 passed`.

## File Structure

- Modify `core/stores/RunStore.qml`:
  - property block (line 30, after `amStatus`): add `amSchema`, `amVersion`.
  - `stopWatch()` (lines 209-213), `startWatch()` (lines 215-230): call `forgetHello()`.
  - `watchLine()` doc comment and body (lines 239-250): read the hello.
  - new `forgetHello()` right after `watchLine()`.
  - `watchExited()` doc comment and body (lines 252-274): call `forgetHello()` for the current watch.
- Modify `tests/core/stores/tst_run_store.qml`: new `// ---- the hello` section inserted after `test_garbage_watch_line_ignored` (ends at line 464), before `// ---- liveness` (line 466). It uses existing helpers: `make()`, `watchedStore(entries)`, `entry(id, runStatus, live)`, `okReply(entries)`, `reply(proc, text, code)`, `sendLine(proc, value)`, `watchError(type, message)`, `endWatch(proc, line, code)`, `rootA`, `rootB`, and `F.load` (imported as `F`). `watchError` and `endWatch` are defined later in the file (line ~704); QML JS functions on the `TestCase` are visible regardless of order.

Two tasks: Task 1 adds the properties and reads the hello; Task 2 adds the resets. A reviewer could accept the reading and reject the reset points independently.

---

### Task 1: The properties and reading the hello

**Files:**
- Modify: `core/stores/RunStore.qml:30` (property block), `core/stores/RunStore.qml:239-250` (`watchLine`)
- Test: `tests/core/stores/tst_run_store.qml` (new section after line 464)

**Interfaces:**
- Consumes: the existing `watchLine(proc, data)`, `isCurrentWatch(proc)`, `debounceTimer`; test helpers listed under File Structure.
- Produces:
  - `RunStore.amSchema: int` (default `0`), `RunStore.amVersion: string` (default `""`).
  - Test helper `helloLine(key: string) -> { hello: { schema, am } }` in `tst_run_store.qml`, used again by Task 2.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_store.qml`, find the end of `test_garbage_watch_line_ignored`:

```js
    compare(store.watching, true, "the watch keeps running")
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
  }

  // ---- liveness
```

Replace it with (the first four lines are unchanged; everything between them and `// ---- liveness` is new):

```js
    compare(store.watching, true, "the watch keeps running")
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
  }

  // ---- the hello

  // The helper's forwarded hello for watch-hello.json's `key` line.
  function helloLine(key) {
    var h = F.load("watch-hello.json")[key]
    return { hello: { schema: h.schema, am: h.am } }
  }

  function test_am_schema_and_version_default_unknown() {
    var store = make(); if (!store) return
    compare(store.amSchema, 0, "a fresh store knows no schema")
    compare(store.amVersion, "", "nor am's version")
    var watched = watchedStore([entry("a", "done", false)]); if (!watched) return
    compare(watched.amSchema, 0, "a running watch before its hello")
    compare(watched.amVersion, "")
  }

  function test_hello_sets_schema_and_version() {
    var cases = [["schema_1", 1], ["schema_2", 2]]
    for (var i = 0; i < cases.length; i++) {
      var store = watchedStore([entry("a", "done", false)]); if (!store) return
      sendLine(store.watchProc, helloLine(cases[i][0]))
      compare(store.amSchema, cases[i][1], cases[i][0])
      compare(store.amVersion, "0.1.0", cases[i][0])
    }
  }

  function test_hello_starts_nothing() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var seq = store.snapshotRunner.seq
    var liveness = store.livenessTimer.running
    sendLine(store.watchProc, helloLine("schema_2"))
    compare(store.amSchema, 2)
    compare(store.debounceTimer.running, false, "a hello is not a change")
    compare(store.snapshotRunner.seq, seq, "no snapshot")
    compare(store.livenessTimer.running, liveness, "the liveness timer is left as it was")
    compare(store.watching, true)
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    compare(store.watchWarning, "")
    compare(store.watchSchemaError, "")
    verify(!store.watchProc.envelope, "a hello is not an envelope")
    sendLine(store.watchProc, { changed: ["a"] })
    compare(store.debounceTimer.running, true, "a changed line still starts the debounce")
  }

  function test_malformed_hello_values() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    var schemas = ["2", true, 2.5, 0, -1, null, undefined]
    for (var i = 0; i < schemas.length; i++) {
      sendLine(store.watchProc, helloLine("schema_2"))
      compare(store.amSchema, 2, "a known schema first")
      // synthetic: schema_1's forwarded hello with a schema that is not an
      // integer of 1 or more (undefined drops the key).
      var line = helloLine("schema_1")
      if (schemas[i] === undefined) delete line.hello.schema
      else line.hello.schema = schemas[i]
      sendLine(store.watchProc, line)
      compare(store.amSchema, 0, JSON.stringify(line))
      compare(store.amVersion, "0.1.0", JSON.stringify(line) + " keeps its string am")
    }
    var ams = [5, null, undefined]
    for (var j = 0; j < ams.length; j++) {
      sendLine(store.watchProc, helloLine("schema_2"))
      compare(store.amVersion, "0.1.0", "a known version first")
      // synthetic: schema_1's forwarded hello with an am that is not a string
      // (undefined drops the key).
      var amLine = helloLine("schema_1")
      if (ams[j] === undefined) delete amLine.hello.am
      else amLine.hello.am = ams[j]
      sendLine(store.watchProc, amLine)
      compare(store.amVersion, "", JSON.stringify(amLine))
      compare(store.amSchema, 1, JSON.stringify(amLine) + " keeps its integer schema")
    }
    // synthetic: the spec's error-table lines, typed as raw text.
    var raw = ['{"hello": {"schema": "2", "am": 5}}', '{"hello": {}}']
    for (var k = 0; k < raw.length; k++) {
      sendLine(store.watchProc, helloLine("schema_2"))
      sendLine(store.watchProc, raw[k])
      compare(store.amSchema, 0, raw[k])
      compare(store.amVersion, "", raw[k])
    }
  }

  function test_non_object_hello_ignored() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    sendLine(store.watchProc, helloLine("schema_2"))
    var lines = ['{"hello": 1}', '{"hello": null}', '{"hello": []}', '{"hello": "x"}']
    for (var i = 0; i < lines.length; i++) {
      sendLine(store.watchProc, lines[i])
      compare(store.amSchema, 2, lines[i] + " is ignored")
      compare(store.amVersion, "0.1.0", lines[i] + " is ignored")
      compare(store.debounceTimer.running, false, lines[i])
    }
  }

  function test_a_later_hello_overwrites_both() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    sendLine(store.watchProc, helloLine("schema_2"))
    sendLine(store.watchProc, helloLine("schema_1"))
    compare(store.amSchema, 1, "the latest hello wins")
    compare(store.amVersion, "0.1.0")
    // synthetic: schema_1's forwarded hello with neither a usable schema nor am.
    var line = helloLine("schema_1")
    line.hello.schema = "1"
    line.hello.am = 1
    sendLine(store.watchProc, line)
    compare(store.amSchema, 0, "a later malformed hello resets the schema")
    compare(store.amVersion, "", "and the version")
  }

  function test_hello_beside_changed_or_ok_false_keeps_its_meaning() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    // synthetic: a changed line that also carries schema_2's hello.
    var changed = helloLine("schema_2")
    changed.changed = ["a"]
    sendLine(store.watchProc, changed)
    compare(store.debounceTimer.running, true, "a changed array still restarts the debounce")
    compare(store.amSchema, 0, "its hello is not read")
    compare(store.amVersion, "")
    // synthetic: an ok:false envelope that also carries schema_2's hello.
    var refusal = helloLine("schema_2")
    refusal.ok = false
    refusal.error = { type: "HelperError", message: "m" }
    sendLine(store.watchProc, refusal)
    verify(store.watchProc.envelope, "ok:false is still kept as the envelope")
    compare(store.watchProc.envelope.error.type, "HelperError")
    compare(store.amSchema, 0, "its hello is not read")
    compare(store.amVersion, "")
  }

  function test_hello_mid_burst_keeps_the_debounce() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    var seq = store.snapshotRunner.seq
    sendLine(store.watchProc, { changed: ["a"] })
    compare(store.debounceTimer.running, true)
    sendLine(store.watchProc, helloLine("schema_2"))
    compare(store.amSchema, 2)
    compare(store.debounceTimer.running, true, "the pending refresh is kept")
    compare(store.snapshotRunner.seq, seq, "and not fired early")
    store.debounceTimer.triggered()
    compare(store.snapshotRunner.seq, seq + 1, "the burst still costs one snapshot")
  }

  function test_hello_extra_keys_are_ignored() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    // synthetic: am's raw hello object (event, runs_dir) as the hello value.
    sendLine(store.watchProc, { hello: F.load("watch-hello.json").schema_2 })
    compare(store.amSchema, 2)
    compare(store.amVersion, "0.1.0")
    // synthetic: schema_1's forwarded hello with an empty am and an unknown key.
    var line = helloLine("schema_1")
    line.hello.am = ""
    line.hello.extra = { schema: 9 }
    sendLine(store.watchProc, line)
    compare(store.amSchema, 1)
    compare(store.amVersion, "", "an empty string is still a string")
  }

  // ---- liveness
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: pytest passes; then `Totals: 176 passed, 9 failed`. The nine failures are exactly `test_am_schema_and_version_default_unknown`, `test_hello_sets_schema_and_version`, `test_hello_starts_nothing`, `test_malformed_hello_values`, `test_non_object_hello_ignored`, `test_a_later_hello_overwrites_both`, `test_hello_beside_changed_or_ok_false_keeps_its_meaning`, `test_hello_mid_burst_keeps_the_debounce`, `test_hello_extra_keys_are_ignored`, each a `FAIL!` line (the message is the compare's label or `Compared values are not the same`), because `amSchema` / `amVersion` do not exist yet. `test_garbage_watch_line_ignored` still passes.

- [ ] **Step 3: Add the two properties**

In `core/stores/RunStore.qml`, replace:

```qml
  property string amStatus: "ok"      // "ok" | "missing" | "schema" | "error"
  property string lastError: ""
```

with:

```qml
  property string amStatus: "ok"      // "ok" | "missing" | "schema" | "error"
  property int amSchema: 0            // journal schema from the current watch's hello; 0 = unknown
  property string amVersion: ""       // am's version from the current watch's hello; "" = unknown
  property string lastError: ""
```

- [ ] **Step 4: Read the hello in `watchLine`**

In `core/stores/RunStore.qml`, replace:

```qml
  // One stdout line of the watch. {"changed": [...]} (re)starts the debounce;
  // anything else -- blank, not JSON, not an object -- is ignored. Never throws.
  function watchLine(proc, data) {
    if (!store.isCurrentWatch(proc)) return
    var text = String(data || "").trim()
    if (text === "") return
    var value = null
    try { value = JSON.parse(text) } catch (e) { return }
    if (value === null || typeof value !== "object" || Array.isArray(value)) return
    if (Array.isArray(value.changed)) debounceTimer.restart()
    else if (value.ok === false) proc.envelope = value
  }
```

with:

```qml
  // One stdout line of the watch. {"changed": [...]} (re)starts the debounce;
  // {"ok": false, ...} is kept as the envelope its exit explains. The hello,
  // {"hello": {"schema": N, "am": V}}, sets amSchema to N (an integer of 1 or
  // more, else 0) and amVersion to V (a string, else "") and starts nothing.
  // Anything else -- blank, not JSON, not an object, a hello that is not an
  // object -- is ignored. Never throws.
  function watchLine(proc, data) {
    if (!store.isCurrentWatch(proc)) return
    var text = String(data || "").trim()
    if (text === "") return
    var value = null
    try { value = JSON.parse(text) } catch (e) { return }
    if (value === null || typeof value !== "object" || Array.isArray(value)) return
    if (Array.isArray(value.changed)) debounceTimer.restart()
    else if (value.ok === false) proc.envelope = value
    else if (value.hello !== null && typeof value.hello === "object" && !Array.isArray(value.hello)) {
      var schema = value.hello.schema
      store.amSchema = typeof schema === "number" && Number.isInteger(schema) && schema >= 1 ? schema : 0
      store.amVersion = typeof value.hello.am === "string" ? value.hello.am : ""
    }
  }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: pytest passes; `Totals: 185 passed, 0 failed`, and no `TypeError` / `ReferenceError` lines.

- [ ] **Step 6: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): RunStore reads amSchema and amVersion from the watch hello"
```

---

### Task 2: Forgetting the hello when there is no current watch

**Files:**
- Modify: `core/stores/RunStore.qml` — `stopWatch()` (lines ~211-215 after Task 1), `startWatch()` (~217-232), new `forgetHello()` after `watchLine()`, `watchExited()` (~258-280)
- Test: `tests/core/stores/tst_run_store.qml` (append to the `// ---- the hello` section, before `// ---- liveness`)

**Interfaces:**
- Consumes: `RunStore.amSchema`, `RunStore.amVersion` and the test helper `helloLine(key)` from Task 1; existing `stopWatch()`, `startWatch()`, `watchExited(proc, exitCode)`, `isCurrentWatch(proc)`; test helpers `watchedStore`, `entry`, `okReply`, `reply`, `sendLine`, `watchError(type, message)`, `endWatch(proc, line, code)`, `rootB`.
- Produces: `RunStore.forgetHello()` (no arguments, no return): sets `amSchema = 0`, `amVersion = ""`. Nothing outside the store calls it.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_store.qml`, find the end of `test_hello_extra_keys_are_ignored` (added in Task 1):

```js
    sendLine(store.watchProc, line)
    compare(store.amSchema, 1)
    compare(store.amVersion, "", "an empty string is still a string")
  }

  // ---- liveness
```

Replace it with (the first four lines are unchanged; everything between them and `// ---- liveness` is new):

```js
    sendLine(store.watchProc, line)
    compare(store.amSchema, 1)
    compare(store.amVersion, "", "an empty string is still a string")
  }

  function test_hello_reset_on_deactivate() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    sendLine(store.watchProc, helloLine("schema_2"))
    compare(store.amSchema, 2)
    store.active = false
    compare(store.amSchema, 0, "a closed panel has no watch hello")
    compare(store.amVersion, "")
    store.active = true
    compare(store.amSchema, 0, "reopening alone restores nothing")
    compare(store.amVersion, "")
  }

  function test_hello_reset_on_watch_exit() {
    var cases = [["", 0], [watchError("HelperError", "m"), 1], ["", 137]]
    for (var i = 0; i < cases.length; i++) {
      var label = "exit " + cases[i][1] + " " + cases[i][0]
      var store = watchedStore([entry("a", "done", false)]); if (!store) return
      sendLine(store.watchProc, helloLine("schema_2"))
      compare(store.amSchema, 2, label)
      endWatch(store.watchProc, cases[i][0], cases[i][1])
      compare(store.watching, false, label)
      compare(store.amSchema, 0, label + ": an ended watch has no hello")
      compare(store.amVersion, "", label)
    }
  }

  function test_hello_reset_when_poll_takes_over() {
    var types = ["SchemaMismatch", "CorruptJournal"]
    for (var i = 0; i < types.length; i++) {
      var store = watchedStore([entry("a", "done", false)]); if (!store) return
      sendLine(store.watchProc, helloLine("schema_2"))
      compare(store.amSchema, 2, types[i])
      endWatch(store.watchProc, watchError(types[i], "m"), 1)
      compare(store.amSchema, 0, types[i])
      compare(store.amVersion, "", types[i])
      compare(store.pollTimer.running, true, types[i] + " polls")
      store.pollTimer.triggered()
      reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
      compare(store.amSchema, 0, types[i] + ": a polled snapshot brings no hello")
      compare(store.amVersion, "", types[i])
    }
  }

  function test_hello_reset_on_project_switch() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    sendLine(store.watchProc, helloLine("schema_2"))
    store.project = rootB
    compare(store.amSchema, 0, "A's hello says nothing about B")
    compare(store.amVersion, "")
    reply(store.snapshotRunner.current, okReply([entry("b1", "done", false)]), 0)
    sendLine(store.watchProc, helloLine("schema_1"))
    compare(store.amSchema, 1, "B's watch says hello")
    compare(store.amVersion, "0.1.0")
    store.project = ""
    compare(store.amSchema, 0, "no project, no hello")
    compare(store.amVersion, "")
  }

  function test_old_watch_hello_ignored() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    var old = store.watchProc
    sendLine(old, helloLine("schema_2"))
    store.project = rootB
    reply(store.snapshotRunner.current, okReply([entry("b1", "done", false)]), 0)
    verify(store.watchProc !== old, "B runs its own watch")
    sendLine(old, helloLine("schema_2"))
    compare(store.amSchema, 0, "A's late hello is dropped")
    compare(store.amVersion, "")
    sendLine(store.watchProc, helloLine("schema_1"))
    compare(store.amSchema, 1, "B's own hello counts")
    compare(store.amVersion, "0.1.0")
    old.exited(0)
    compare(store.amSchema, 1, "A's late exit forgets nothing")
    compare(store.amVersion, "0.1.0")
  }

  function test_new_watch_starts_unknown() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    var old = store.watchProc
    sendLine(old, helloLine("schema_2"))
    store.active = false
    store.active = true
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    var fresh = store.watchProc
    verify(fresh !== old, "a new watch was started")
    compare(fresh.running, true)
    compare(store.amSchema, 0, "a new watch starts unknown")
    compare(store.amVersion, "")
    sendLine(fresh, helloLine("schema_1"))
    compare(store.amSchema, 1, "until its own hello")
    compare(store.amVersion, "0.1.0")
  }

  // ---- liveness
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: pytest passes; `Totals: 185 passed, 6 failed`. The six failures are exactly `test_hello_reset_on_deactivate`, `test_hello_reset_on_watch_exit`, `test_hello_reset_when_poll_takes_over`, `test_hello_reset_on_project_switch`, `test_old_watch_hello_ignored`, `test_new_watch_starts_unknown`, each a `FAIL!` line on the first `0` / `""` check after a reset point, because the hello's `2` / `"0.1.0"` is still there.

- [ ] **Step 3: Add `forgetHello()` and call it from the stop and start points**

In `core/stores/RunStore.qml`, replace:

```qml
  function stopWatch() {
    store.watchSeq += 1
    if (watchState.proc) watchState.proc.running = false
    watchState.watching = false
  }

  // runs-watch.py for this project and the runs the snapshot just listed, in
  // its order. Long-lived, so a plain Process rather than the HelperRunner.
  function startWatch() {
    store.watchSeq += 1
    store.watchTried = true
```

with:

```qml
  // No watch is left running, so am's schema and version are unknown again.
  function stopWatch() {
    store.watchSeq += 1
    if (watchState.proc) watchState.proc.running = false
    watchState.watching = false
    store.forgetHello()
  }

  // runs-watch.py for this project and the runs the snapshot just listed, in
  // its order. Long-lived, so a plain Process rather than the HelperRunner.
  // It starts with am's schema and version unknown until its own hello.
  function startWatch() {
    store.watchSeq += 1
    store.watchTried = true
    store.forgetHello()
```

Then, directly after the closing `}` of `watchLine` (from Task 1) and before the `// The watch ended.` comment, insert:

```qml

  // amSchema and amVersion back to unknown: no current watch has said hello.
  function forgetHello() {
    store.amSchema = 0
    store.amVersion = ""
  }
```

- [ ] **Step 4: Forget the hello when the current watch exits**

In `core/stores/RunStore.qml`, replace:

```qml
  // The watch ended. Exit 0: it was stopped (by us, or because am exited).
  // Otherwise the last envelope line it printed says why: a journal the helper
  // cannot read switches to the 5 s poll; anything else is reported and the
  // watch stays off until the next activation or project switch.
  function watchExited(proc, exitCode) {
    if (!store.isCurrentWatch(proc)) return
    watchState.watching = false
    if (exitCode === 0) return
```

with:

```qml
  // The watch ended, whatever the code: its hello no longer holds, so amSchema
  // and amVersion are reset. Exit 0: it was stopped (by us, or because am
  // exited). Otherwise the last envelope line it printed says why: a journal
  // the helper cannot read switches to the 5 s poll; anything else is reported
  // and the watch stays off until the next activation or project switch.
  function watchExited(proc, exitCode) {
    if (!store.isCurrentWatch(proc)) return
    watchState.watching = false
    store.forgetHello()
    if (exitCode === 0) return
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: pytest passes; `Totals: 191 passed, 0 failed`, no `TypeError` / `ReferenceError` lines.

- [ ] **Step 6: Run the whole suite**

Run: `bash tests/run.sh`
Expected: exit status 0; pytest all passed (including `tests/architecture` and `tests/contract`); every `Totals:` line shows `0 failed`.

- [ ] **Step 7: Check the comments say nothing about migration, cards or plans**

Run (covers both tasks: `HEAD~1` is the commit before Task 1): `git diff HEAD~1 -- core/stores/RunStore.qml | grep "^+" | grep -inE "migrat|card|plan|4\.4|sibling" || echo clean`
Expected: `clean`

- [ ] **Step 8: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): RunStore forgets the watch hello when its watch stops, exits or restarts"
```

---

## Self-review against the spec

- Rule 1 (two writable properties next to `amStatus`, trailing contract comments): Task 1 Step 3; `test_am_schema_and_version_default_unknown`.
- Rule 2 (when a hello is read; integer >= 1 schema; string am; both from one line; later hello overwrites): Task 1 Step 4; `test_hello_sets_schema_and_version`, `test_malformed_hello_values` (every value in the spec list plus `-1` and the error-table raw lines), `test_a_later_hello_overwrites_both`, `test_hello_extra_keys_are_ignored`.
- Rule 3 (a hello starts nothing; `changed` / `ok: false` keep their meaning; non-object hello ignored): `test_hello_starts_nothing`, `test_hello_beside_changed_or_ok_false_keeps_its_meaning`, `test_hello_mid_burst_keeps_the_debounce`, `test_non_object_hello_ignored`; `test_garbage_watch_line_ignored` unchanged.
- Rule 4 (stale hello / exit dropped): existing `isCurrentWatch` guard; `test_old_watch_hello_ignored`.
- Rule 5 (resets in `stopWatch`, current `watchExited` with any code, `startWatch`; stale exit resets nothing): Task 2 Steps 3-4; `test_hello_reset_on_deactivate`, `test_hello_reset_on_watch_exit`, `test_hello_reset_when_poll_takes_over`, `test_hello_reset_on_project_switch`, `test_old_watch_hello_ignored`, `test_new_watch_starts_unknown`. Note: every `startWatch()` today follows a `stopWatch()` or exit, so `test_new_watch_starts_unknown` is also satisfied by the `stopWatch` reset; the `startWatch` reset is required by the spec and has no separately observable test.
- Rule 6 (nothing else changes; existing tests pass unchanged): no existing test is edited; Task 1 Step 5 and Task 2 Steps 5-6 run the whole file / suite.
- Rule 7 (comments state the contract only): Task 1 Step 4 and Task 2 Steps 3-4 comment text; grep in Task 2 Step 7.
- Spec tests 1-11 with their exact names: Task 1 (1-5), Task 2 (6-11). Red first: Task 1 Step 2, Task 2 Step 2. Verification: Task 2 Step 6.
- Out of scope untouched: Global Constraints last line.
<!-- task-pipeline: validated -->
