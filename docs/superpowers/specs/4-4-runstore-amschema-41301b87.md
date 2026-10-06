# 4.4 RunStore: amSchema and amVersion from the watch hello (card 41301b87)

This narrows `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
(called "the parent" below). It draws on these parts of the parent:
- Decision 8 (line 172).
- "Both spellings, both schemas": lines 286-289, the `runs-watch.py` bullet at
  lines 296-300 (the shape of the line this card reads) and the `RunStore`
  bullet at lines 301-302 (this card).
- The `watch-hello.json` fixture row (line 248) and the fixture rule (lines
  257-267).
- "Not changed" (line 314: `RunStore`'s public API changes only by `amSchema` /
  `amVersion`).

The parent story is 27d8a320, work breakdown item 4 (parent lines 329-330).

This card covers only the `RunStore.amSchema` / `amVersion` part of item 4. The
other parts are owned elsewhere:
- `runs.js` (4.1), `runs-snapshot.py` (4.2) and `runs-watch.py` (4.3) are
  already on this branch.
- The Runs footer that shows these two properties (parent lines 303-304) is a
  sibling card.

## Starting point

- `core/backend/runs/runs-watch.py` (card 4.3) prints the first hello it
  accepts as one line: `{"hello": {"schema": N, "am": V}}`. `N` is the integer 1
  or 2. `V` is a string, or `""` when am sent no string (parent lines 296-297).
  The hello comes before any `changed` line. It is printed once per watch
  process.
- `core/stores/RunStore.qml`:
  - The public property block (lines ~25-52) has no `amSchema` / `amVersion`.
  - `watchLine(proc, data)` (lines ~239-250) drops lines that are not from the
    current watch (`isCurrentWatch`). It parses the line and ignores anything
    that is not a JSON object. `changed` arrays restart the debounce, and
    `ok: false` is stored as the envelope. Everything else is ignored,
    including a `hello` line today.
  - `stopWatch()` (~209) runs from `stopLive()` (the panel closes),
    `projectSwitched()` (the project changes, including to `""`) and before
    restarts.
  - `startWatch()` (~217) bumps `watchSeq` but does not call `stopWatch()`.
  - `watchExited(proc, exitCode)` (~255) clears `watching` on any exit of the
    current watch. For `SchemaMismatch` and `CorruptJournal` it also starts the
    5 s poll through `startPoll()`.
- `tests/core/stores/tst_run_store.qml`:
  - `test_garbage_watch_line_ignored` (line 454) already sends `{"hello": 1}`
    and requires it to be ignored.
  - The helpers `watchedStore`, `sendLine`, `endWatch` and `watchError` exist,
    and `F.load` reads `tests/fixtures/am/<name>`.
- `tests/fixtures/am/watch-hello.json` holds the raw am hello lines.
  `schema_1` is real (`am: "0.1.0"`, `schema: 1`). `schema_2` is a derived copy
  (`schema: 2`).

## Required behaviour

1. **Two new public properties** on `RunStore`, next to `amStatus`:
   - `property int amSchema: 0`: the journal schema from the current watch's
     hello. 0 means unknown.
   - `property string amVersion: ""`: am's version from that hello. `""` means
     unknown.

   Each property has a short trailing comment that states this contract. Both
   are plain writable properties, like `amStatus`, not read-only aliases.

2. **Reading the hello.** `watchLine` handles a line from the current watch
   that parses to a non-array JSON object when all of these are true:
   - its `changed` is not an array;
   - its `ok` is not `false`;
   - its `hello` is a non-null, non-array object.

   For such a line:
   - `amSchema` becomes `hello.schema` when that value is an integer of 1 or
     more (`typeof` number and `Number.isInteger`, so `true`, `"2"`, `2.5`, `0`,
     `-1`, `null` and a missing key don't qualify). Otherwise it becomes `0`.
   - `amVersion` becomes `hello.am` when that value is a string. Otherwise it
     becomes `""`.
   - Both are written from the same line. A later hello line from the same
     watch overwrites both the same way. The helper prints only one, but the
     store does not rely on that.

3. **A hello has no other effect.** It does not do any of these:
   - (re)start the debounce, launch a snapshot or touch the liveness timer;
   - change `amStatus`, `lastError`, `watchWarning`, `watchSchemaError` or
     `watching`;
   - set `proc.envelope`.

   Lines with a `changed` array or `ok: false` keep their current meaning even
   if they also carry a `hello` key. A `hello` that is not an object (`1`,
   `"x"`, `[]`, `null`) is ignored as today, and `amSchema` / `amVersion` keep
   their values.

4. **Stale hellos are dropped.** A hello line from a watch that fails
   `isCurrentWatch` changes nothing. That covers a watch that was stopped, an
   older launch, and the old project after a switch.

5. **Reset to `0` / `""`.** Both properties go back to their defaults whenever
   the store has no current watch hello:
   - the watch is stopped (`stopWatch()`), which covers closing the panel
     (`active = false`), a project switch (including clearing the project) and
     every stop before a restart;
   - the current watch exits with any code (`watchExited` of the current
     watch). That includes exit 0, and the `SchemaMismatch` / `CorruptJournal`
     exits after which the poll takes over;
   - a new watch is launched (`startWatch()`), so a fresh watch starts from
     unknown until its own hello arrives.

   A watch exit that `isCurrentWatch` rejects resets nothing (rule 4).

6. **Nothing else about the watch changes.** The following keep their current
   behaviour, and every existing test in `tst_run_store.qml` passes unchanged:
   - the argv, `watchSeq` / `watchTried`;
   - the debounce, the poll fallback and the liveness timer;
   - the error and warning text;
   - what a project switch or deactivation clears.

7. **Comments state the contract only.** The `watchLine` doc comment names the
   hello line, what it sets, and that it starts nothing. The comments on the
   reset points (if any are added) say what is reset. Don't write about am's
   migration, cards or plans.

## Error paths

| Input line (current watch) | `amSchema` | `amVersion` | Other effects |
|---|---|---|---|
| `{"hello": {"schema": 2, "am": "0.1.0"}}` | 2 | `"0.1.0"` | none |
| `{"hello": {"schema": 1}}` | 1 | `""` | none |
| `{"hello": {"schema": "2", "am": 5}}` | 0 | `""` | none |
| `{"hello": {}}` | 0 | `""` | none |
| `{"hello": 1}`, `{"hello": null}`, `{"hello": []}` | unchanged | unchanged | none (ignored) |
| a hello line from a stopped / older / other-project watch | unchanged | unchanged | none |

## Tests (all in `tests/core/stores/tst_run_store.qml`, QML store tier)

**Tier.** These tests belong in the QML store tier. The behaviour lives entirely
in `RunStore.qml`'s watch handling, which only runs under `qmltestrunner` with
the stubbed `Process` objects this file already drives. Every other watch test
lives here, and `bash tests/run.sh` runs it. No pytest or contract test can see
a QML property. No architecture test is affected, because no component, import
or icon is added.

**Inputs.** Hello lines come from the fixture through a helper, not typed by
hand (parent lines 257-267):

```js
// The helper's forwarded hello for watch-hello.json's `key` line.
function helloLine(key) {
  var h = F.load("watch-hello.json")[key]
  return { hello: { schema: h.schema, am: h.am } }
}
```

Malformed variants (non-integer schema, non-string or missing `am`) are built on
a fresh copy of `helloLine("schema_1")`, each with a comment that marks it
`synthetic:`.

**New tests.** Place them after `test_garbage_watch_line_ignored`, under a
`// ---- the hello` heading.

1. `test_am_schema_and_version_default_unknown`: a fresh `make()` store and a
   `watchedStore` before any line both have `amSchema === 0` and
   `amVersion === ""` (rule 1).
2. `test_hello_sets_schema_and_version`: for `schema_1` and `schema_2`, a fresh
   `watchedStore` receives `helloLine(key)`. Then `amSchema` is 1 or 2 and
   `amVersion` is `"0.1.0"` (rule 2).
3. `test_hello_starts_nothing`: after `helloLine("schema_2")`, check all of
   these (rule 3):
   - `debounceTimer.running === false`;
   - `snapshotRunner.seq` is unchanged;
   - `watching === true`;
   - `amStatus === "ok"`, and `lastError`, `watchWarning` and `watchSchemaError`
     are all `""`;
   - `watchProc.envelope` is unchanged (falsy).

   Then a `{changed: ["a"]}` line still starts the debounce.
4. `test_malformed_hello_values`: these are synthetic copies, and the table
   above gives the expected values (rule 2):
   - schema `"2"`, `true`, `2.5`, `0`, `null` and missing each give
     `amSchema === 0`;
   - `am` missing, `5` and `null` each give `amVersion === ""`.

   Each case first sets a known hello so that the reset to 0/`""` is observed.
5. `test_non_object_hello_ignored`: after `helloLine("schema_2")`, the lines
   `{"hello": 1}`, `{"hello": null}` and `{"hello": []}` leave 2 / `"0.1.0"`
   (rule 3).
6. `test_hello_reset_on_deactivate`: hello, then `store.active = false`. Both
   values are back to 0/`""`. Reactivation alone does not restore them (rule 5).
7. `test_hello_reset_on_watch_exit`: hello, then `endWatch(proc, "", 0)`. Both
   values are 0/`""` (rule 5).
8. `test_hello_reset_when_poll_takes_over`: for `SchemaMismatch` and
   `CorruptJournal`, each on a fresh `watchedStore`:
   - send the hello, then `endWatch(proc, watchError(type, "m"), 1)`;
   - both values are 0/`""` and `pollTimer.running === true`;
   - after a poll tick and its good reply, the values are still 0/`""` (rule 5).
9. `test_hello_reset_on_project_switch`: hello, then `store.project = rootB`.
   Both values are 0/`""`. Then `store.project = ""` after a new hello on B's
   watch also resets them (rule 5).
10. `test_old_watch_hello_ignored`, covering rule 4:
    - hello on A's watch, then a switch to B, then B's first snapshot (B's
      watch runs);
    - a hello from A's old proc leaves 0/`""`;
    - B's own `helloLine("schema_1")` sets 1/`"0.1.0"`;
    - a late `exited(0)` from A's old proc leaves 1/`"0.1.0"`.
11. `test_new_watch_starts_unknown`: hello, then `active = false`, then
    `active = true` and a good snapshot (a new watch). Both values are 0/`""`
    until the new proc sends its own hello (rule 5, `startWatch`).

**Red first.** All eleven fail on today's code. Tests 1, 3 and 5 fail only
because the properties are missing, and once those exist they pin behaviour
that is already there. Tests 2, 4 and 6-11 also need `watchLine` to read the
hello and the reset points to clear it. `test_garbage_watch_line_ignored` is
unchanged and must stay green.

**Verification.** `bash tests/run.sh` is green, including `tests/architecture`
and `tests/contract`.

## Out of scope

- The `RunsScreen` footer text (`am <version> · schema N · watching`, parent
  lines 303-304): a sibling card.
- `runs-watch.py`, `runs-snapshot.py`, `runs.js` (cards 4.3, 4.2, 4.1, done).
- Any new behaviour keyed on `amSchema`. For example, the store does not treat
  schema 2 differently, does not change `amStatus`, and does not affect the
  poll.
- Fixtures, `tests/contract/*`, `docs/architecture.md` and the README (work
  breakdown item 5).
- Other `RunStore` API, timers, guards and error text (parent line 314).
