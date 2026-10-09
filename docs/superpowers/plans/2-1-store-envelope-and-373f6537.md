# 2.1 Store envelope and map helpers as domain functions — design

Card: `373f6537` (subtask of story `a886bade`). Parent design:
`docs/superpowers/specs/2026-10-05-split-runstore-design.md`, cited below as "P l.N".

## Purpose

This is a pure refactor. `core/stores/RunStore.qml` has five private helpers today:

| helper | line | callers in `RunStore.qml` |
|---|---|---|
| `runById(id)` (the loop inside it) | 753-758 | 799, 821, 836, 1098, 1251, 1289 |
| `lastLine(text)` | 870-877 | 881 (`parseEnvelope`) only |
| `parseEnvelope(text)` | 880-886 | 852, 910, 1194, 1217, 1409, 1418, 1425, 1568, 1605, 1715, 1758 |
| `copyMap(map)` | 1080-1086 | 510, 983, 984, 1045, 1101, 1105, 1143, 1148, 1153, 1198, 1531, 1657, 1720 |
| `hasKey(map, key)` | 1088-1090 | 27 `store.hasKey(` sites, 442-1485 |

Each one becomes an exported pure function in `core/domain/`. `RunStore` imports and calls
them. When this card is done, `RunStore` keeps no copy of the logic. The later stores
(`RunControlStore`, `RunAlertsStore`, `RunDispatchStore`) import these same functions when
their code moves (P l.68-71). Every observable behaviour of `RunStore` stays exactly as it is.

## Inherited constraints

- The four helpers and the run lookup inside `runById` become pure functions in
  `core/domain/` before anything moves. Each store imports them, and none keeps a private copy
  (P l.68-71, rule 2).
- `results.js` already holds the one-JSON-line reading (`parseJsonLine`) (P l.70). The card
  says to reuse it where it gives the same result, and otherwise to add the function next to
  it.
- No behaviour change, and no public member is renamed (P l.146-147). Rule 2 only moves
  helper functions into the domain. `runs.js` semantics do not change (P l.148-149). Adding
  new exports to `runs.js` is allowed, but no existing function in it changes.
- `runById` stays a `RunStore` member (P l.54). `ui/Shortcuts.qml:70`, `ui/Navigator.qml:392,
  408`, `ui/Panel.qml:242, 834` and `tests/core/stores/tst_run_store.qml` call
  `store.runById(id)`. Appendix A gives the lookup to the domain (P l.440-441).
- Appendix A puts `lastLine`, `parseEnvelope`, `copyMap` and `hasKey` in `core/domain`
  (P l.325, 326, 332, 333).
- `tests/architecture` stays green (P l.105-106, rule 6). That includes the layer allowlist
  for `core/domain/*.js`: `.pragma library`, `.import "x.js"` of other domain files only, and
  no QML (`docs/architecture.md:11`). The stores may import `../domain/*.js`
  (`docs/architecture.md:14`).
- From the card:
  - `tests/core/stores/tst_run_store.qml` passes and is not edited;
  - domain tests go in `tests/core/domain`;
  - `bash tests/run.sh` is green;
  - TDD: tests first;
  - docstrings and comments state the contract only, with no narrative.

## Where each function lives

| function | module | why |
|---|---|---|
| `lastLine(text)` | `core/domain/results.js` | this is the one-JSON-line reading module (P l.70) |
| `parseEnvelope(text)` | `core/domain/results.js` | same |
| `runById(runs, id)` | `core/domain/runs.js` | a lookup over normalized runs, beside `_findByCardId` (runs.js:201) |
| `copyMap(map)` | `core/domain/runs.js` | `RunStore` and every store that will be split from it already import `runs.js` as `Runs`, so this adds no new module |
| `hasKey(map, key)` | `core/domain/runs.js` | same |

**Not reused: `parseJsonLine`.** `parseJsonLine(text, 0, "", false).data` agrees with
`parseEnvelope` on ordinary input, but not on all input. `parseJsonLine` parses the
untrimmed line, and `lastLine` trims with `String.prototype.trim`. That trim also strips
characters that JSON does not count as whitespace (U+00A0, U+FEFF, U+2028 and others). For
example, `'{"a":1}\u00A0'` (trailing no-break space) gives an object from `parseEnvelope` today and `null` from
`parseJsonLine`. So `parseEnvelope` is its own function next to `parseJsonLine`, and
`parseJsonLine` is not changed. It must not be rewritten in terms of `lastLine`, because that
would change its results for the same input.

**Not reused: `graph.js`'s `has(map, key)` (graph.js:40).** It has the same own-key rule, but it
belongs to the graph module. Importing `graph.js` into the run stores only to get it would
couple two unrelated domains. `hasKey` gets the same null-safety (see below).

## Behaviour

Each function is pure: no QML, no I/O, and it never mutates its input. Apart from the one
exception marked below, the semantics are exactly today's store code.

### `Results.lastLine(text)` → string

- `text` is converted with `String(text || "")`. So `null`, `undefined`, `""`, `0`,
  `false` and `NaN` all read as `""`. Any other value goes through `String(...)` (for
  example, the number `5` reads as `"5"`).
- The text is split on `"\n"`. The lines are scanned from the last one back to the first, and
  the function returns the first line that is non-empty after `trim()`, **trimmed**.
- If there is no such line, it returns `""`.
- A `\r\n` line ending leaves no `\r` in the result, because `trim()` removes it.

### `Results.parseEnvelope(text)` → object | null

- Reads `lastLine(text)`. If that is `""`, it returns `null`.
- It runs `JSON.parse` on that line and returns `null` on a parse error. It never throws.
- It returns the parsed value only when it is a non-null, non-array object. Otherwise it
  returns `null`. That covers an array, a number, a string, `true` / `false` and the literal
  `null`.
- Only the last non-empty line counts. An object on an earlier line followed by garbage on
  the last line gives `null`.

### `Runs.runById(runs, id)` → run | null

- Returns the first entry `e` of `runs`, in order, for which `e` is truthy and
  `e.id === id` (strict equality, no coercion). If there is none, it returns `null`.
- If `runs` is not an array (`null`, `undefined`, an object, a string), it returns `null`.
  This is new null-safety that today's store code does not have. `store.runs` is always an
  array, so `RunStore.runById` behaves the same.
- Entries that are `null`, `undefined`, `0` or `""` are skipped.
- It looks at entry `id` values only. It never reads `runs` as a map. So an `id` that names an
  `Object.prototype` member (`"constructor"`, `"toString"`, `"__proto__"`,
  `"hasOwnProperty"`, `"valueOf"`) matches only a run whose `id` is that string.
- It returns the entry itself, not a copy: `runById(list, x) === list[i]`.

### `Runs.hasKey(map, key)` → boolean

- If `map` is `null` or `undefined`, it returns `false`. This replaces a `TypeError` that
  today's code would throw. No call site in `RunStore` passes `null` or `undefined`: every
  argument is a store map initialized to `{}`, a parsed envelope that was null-checked
  first, or a value guarded by `isMap` (1485). So `RunStore`'s behaviour does not change.
- Otherwise it returns `Object.prototype.hasOwnProperty.call(map, key)`. Only own keys count:
  - an inherited member (`"toString"`, `"constructor"`, `"hasOwnProperty"`, `"valueOf"`,
    `"__proto__"`) is `false` unless the map has its own key of that name;
  - a map with its own `hasOwnProperty` key (a value that is not a function) is still read
    correctly.

### `Runs.copyMap(map)` → object

- Returns a new plain object `{}` that holds every own enumerable key of `map` (found by
  `for…in` plus an own-key check) with the same values. The copy is shallow.
- The result is a different object from `map` (`copyMap(m) !== m`). Changing the copy leaves
  `map` unchanged.
- Inherited enumerable keys (from `Object.create(proto)`) are not copied.
- `null` and `undefined` give `{}`, because `for…in` over them does nothing.
- The `__proto__` own key keeps today's semantics: the copy assigns `out["__proto__"] = v`.
  No test pins this, and this card does not change it.

## `RunStore` after the change

- `RunStore.qml` adds the import `import "../domain/results.js" as Results` beside the
  existing `import "../domain/runs.js" as Runs` (line 4).
- `function runById(id)` stays, with its contract comment, and its body is the single line
  `return Runs.runById(store.runs, id)`.
- `lastLine`, `parseEnvelope`, `copyMap` and `hasKey` are deleted from the store. Every
  `store.parseEnvelope(` call becomes `Results.parseEnvelope(`, every `store.copyMap(`
  becomes `Runs.copyMap(`, and every `store.hasKey(` becomes `Runs.hasKey(`. The one inline
  own-key check, `Object.prototype.hasOwnProperty.call(entry, key)` at 894 (inside the
  `for…in` that drops `status` from the `am runs` summary), also becomes
  `Runs.hasKey(entry, key)`. It only runs when `for…in` yields a key, so `entry` is never
  null there. No call site changes in any other way.
- When the change is done, a grep of `core/stores/RunStore.qml` finds no
  `function lastLine`, `function parseEnvelope`, `function copyMap`, `function hasKey`,
  `store.lastLine`, `store.parseEnvelope`, `store.copyMap` or `store.hasKey`, and no
  `hasOwnProperty` either.

## Error paths

- Garbage, a truncated JSON line, an empty reply or a reply of only whitespace gives `null`
  from `parseEnvelope`. Every call site already treats `null` as "no usable reply", so the
  error states and messages each one sets (for example `logsError`, and the snapshot's
  `amStatus` / `lastError`) stay the same. `tst_run_store.qml` already pins this, for example
  `test_json_that_is_not_an_envelope_is_an_error` and `test_the_last_non_empty_line_is_the_reply`.
- None of the five functions throws, whatever input it gets.

## Tests

All new tests are QML `TestCase` functions in the existing domain suites, which already
import the module under test. Each test name is snake_case `test_…` and uses
`compare` / `verify`.

**Tier: domain unit (`tests/core/domain`).** These are pure functions, so they are tested
directly, without a store, runner or timer. This is the tier the card names.

`tests/core/domain/tst_results.qml` (`DomainResults`):

1. `test_last_line_is_the_last_non_empty_line_trimmed`: given `"noise\n  {\"a\":1}  \n\n \n"`,
   the result is `'{"a":1}'`.
2. `test_last_line_of_nothing_is_empty`: `null`, `undefined`, `""`, `"\n \n\t"` and `0` all
   give `""`.
3. `test_last_line_drops_a_carriage_return`: `"x\r\ny\r\n"` gives `"y"`.
4. `test_parse_envelope_reads_the_last_line_object`: a warning line, then `{"ok":true,"n":2}`,
   then a blank line gives an object with `n === 2`.
5. `test_parse_envelope_rejects_json_that_is_not_an_object`: `[1]`, `3`, `"\"s\""`, `true` and
   `null` (as text) each give `null`.
6. `test_parse_envelope_rejects_garbage`: `"{not json"`, `"ok"`, and a valid object line
   followed by a garbage last line each give `null`, and none of them throws.
7. `test_parse_envelope_of_nothing_is_null`: `""`, `null`, `undefined` and `"\n\n"` give `null`.
8. `test_parse_envelope_trims_what_trim_strips`: `'{"a":1}\u00A0'` (trailing no-break space) gives an object with `a === 1`.
   This pins the reason `parseJsonLine` is not reused.

`tests/core/domain/tst_runs.qml` (`DomainRuns`):

9. `test_run_by_id_returns_the_entry_itself`: `runById(list, "b")` is `=== list[1]`, and a
   missing id gives `null`.
10. `test_run_by_id_skips_empty_entries`: in `[null, undefined, 0, {id:"a"}]`, `"a"` is found.
11. `test_run_by_id_on_a_non_list_is_null`: `null`, `undefined`, `{}` and `"abc"` as `runs` give
    `null`.
12. `test_run_by_id_with_a_prototype_member_name`: for each of `"constructor"`, `"toString"`,
    `"__proto__"`, `"hasOwnProperty"` and `"valueOf"`, a list with no such run gives `null`,
    and a list that has `{id: name}` returns that entry.
13. `test_run_by_id_is_strict`: the id `1` does not match `{id: "1"}`.
14. `test_has_key_counts_own_keys_only`: `hasKey({a:1}, "a")` is `true`. On `{}`, each of
    `"toString"`, `"constructor"`, `"hasOwnProperty"`, `"valueOf"` and `"__proto__"` is
    `false`. An own key of each of those names (set with `JSON.parse` for `__proto__`) is `true`.
15. `test_has_key_with_a_shadowed_has_own_property`: on `{hasOwnProperty: 1, a: 2}`, `"a"` is
    `true` and `"b"` is `false`.
16. `test_has_key_on_nothing_is_false`: a `null` or `undefined` map gives `false` and does not
    throw.
17. `test_copy_map_is_a_new_shallow_copy`: the result `!==` the input and has the same keys and
    values. A nested object is the same reference. Writing to the copy leaves the input as it
    was.
18. `test_copy_map_copies_own_keys_only`: from `Object.create({inherited: 1})` with own `a`,
    the copy has `a` and no `inherited`. Own keys `"constructor"`, `"toString"` and
    `"hasOwnProperty"` are copied as own keys.
19. `test_copy_map_of_nothing_is_empty`: `null` and `undefined` give a new empty object.

**Tier: store characterization (`tests/core/stores/tst_run_store.qml`, unchanged).** This
suite proves that the store behaves the same after the call sites are rewritten. It runs
untouched, and every existing test passes. No test is added there, because the behaviour has
not changed.

**Tier: architecture (`tests/architecture`, unchanged).** These tests prove that the layering
holds after the new `results.js` import in the store, and that the domain files still import
no QML.

## Out of scope

- Moving any member to `RunControlStore`, `RunAlertsStore` or `RunDispatchStore`, and any shim
  (sibling cards; P l.108-130).
- `ui/screens/RunDetailScreen.qml:43`'s own `runById(list, id)`. `ui/` is not touched until the
  last story (P l.115, 128).
- Changing `parseJsonLine`, or moving the store's other parsing (`isSeq`, the run-row
  normalizing) into the domain.
- Changing the `__proto__` semantics of `copyMap`, or adding any other new behaviour.
- Editing `tests/core/stores/tst_run_store.qml` or `tst_app_runs.qml`.
- `docs/architecture.md`'s domain helper list (l.173-174) needs no edit. It names the
  modules, not every function, and this card adds no module.

## Verification

`bash tests/run.sh` is green: pytest (including `tests/architecture`) and every QML suite,
with no `TypeError` / `ReferenceError` / `is not a function` lines.

---

# 2.1 Store Envelope and Map Helpers as Domain Functions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `RunStore`'s five private helpers (`lastLine`, `parseEnvelope`, the `runById` lookup, `copyMap`, `hasKey`) into pure exported functions in `core/domain/`, and make `RunStore` call them, with no observable change.

**Architecture:** `lastLine` and `parseEnvelope` are added to `core/domain/results.js` next to `parseJsonLine` (which is not touched). `runById(runs, id)`, `hasKey(map, key)` and `copyMap(map)` are appended to `core/domain/runs.js` in a new section. `core/stores/RunStore.qml` imports `results.js` as `Results`, keeps `runById(id)` as a one-line delegate, deletes the other four helpers, and rewrites every call site mechanically.

**Tech Stack:** QML (Qt 6, Quickshell), `.pragma library` JavaScript, QtTest `TestCase` suites run by `qmltestrunner` through `bash tests/run.sh`, pytest for `tests/architecture`.

**Spec:** `docs/superpowers/specs/2-1-store-envelope-and-373f6537.md` (reproduced above this plan).

## Global Constraints

- Pure refactor: no behaviour change of `RunStore`, and no public member is renamed (P l.146-147).
- No existing function in `core/domain/runs.js` changes; only new exports are added (P l.148-149).
- `parseJsonLine` in `core/domain/results.js` is not changed and must not be rewritten in terms of `lastLine`.
- `runById` stays a `RunStore` member: `function runById(id)` with the body `return Runs.runById(store.runs, id)`.
- `core/domain/*.js`: `.pragma library`, `.import "x.js"` of other domain files only, no QML. Stores may import `../domain/*.js`.
- `tests/core/stores/tst_run_store.qml` and `tst_app_runs.qml` pass and are not edited.
- Domain tests go in `tests/core/domain` (`tst_results.qml`, `tst_runs.qml`), snake_case `test_…`, using `compare` / `verify`.
- TDD: tests first.
- Docstrings and comments state the contract only, with no narrative.
- `ui/` is not touched (including `ui/screens/RunDetailScreen.qml`'s own `runById`).
- Final gate: `bash tests/run.sh` green, with no `TypeError` / `ReferenceError` / `is not a function` lines.
- Never use `pkill -f`, `pkill` by name, `killall`, or `kill` with a pattern. Bound long runs with `timeout`.

## Review Focus

1. A helper reply with CRLF line endings (`'warn\r\n{"ok":true}\r\n'`) — `parseEnvelope` must still return the object (trim removes `\r`). Test added to Task 1 (`test_parse_envelope_reads_a_crlf_reply`).
2. A non-string stdout (a number such as `5`, or `true`) — `parseEnvelope` must return `null` without throwing. Test added to Task 1 (`test_parse_envelope_of_a_non_string_is_null`).
3. No run selected: the store calls `runById("")` while `selectedRunId` is `""`; entries with no `id` must not match. Test added to Task 2 (`test_run_by_id_of_the_empty_id_matches_no_idless_entry`).
4. Primitive entries in the runs list (`"a"`, `5`, `true`) — `runById` must skip them and not throw. Test added to Task 2 (`test_run_by_id_skips_primitive_entries`).
5. A numeric key, as `hasOwnProperty` coerces it: `hasKey({"1": x}, 1)` is `true`, same as today's store code. Test added to Task 2 (`test_has_key_coerces_the_key_like_has_own_property`).

---

## File Structure

| file | change | responsibility |
|---|---|---|
| `core/domain/results.js` | modify (append) | adds `lastLine(text)` and `parseEnvelope(text)`: reading a helper's one JSON envelope line |
| `core/domain/runs.js` | modify (append a section at end of file) | adds `runById(runs, id)`, `hasKey(map, key)`, `copyMap(map)` |
| `tests/core/domain/tst_results.qml` | modify (append tests) | domain unit tests 1-8 plus Review Focus 1-2 |
| `tests/core/domain/tst_runs.qml` | modify (append tests) | domain unit tests 9-19 plus Review Focus 3-5 |
| `core/stores/RunStore.qml` | modify | imports `Results`, delegates `runById`, deletes the four helpers, rewrites call sites |

How to run one QML suite: `bash tests/run.sh <substring>` runs pytest first, then only the QML test files whose path contains `<substring>`. It exits non-zero on any `FAIL` or any `TypeError` / `ReferenceError` / `is not a function` line. Wrap with `timeout 600`.

---

### Task 1: `Results.lastLine` and `Results.parseEnvelope`

**Files:**
- Modify: `core/domain/results.js` (append after `parseJsonLine`, which ends at line 28)
- Test: `tests/core/domain/tst_results.qml` (append before the final closing `}` of `TestCase`, after `test_parse_json_line_without_require_ok_accepts_a_plain_object`)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Results.lastLine(text: any) -> string` — the last line of `String(text || "")` (split on `"\n"`) that is non-empty after `trim()`, trimmed; `""` when there is none.
  - `Results.parseEnvelope(text: any) -> object | null` — `JSON.parse(lastLine(text))` when that is a non-null, non-array object; otherwise `null`. Never throws.

- [ ] **Step 1: Write the failing tests**

In `tests/core/domain/tst_results.qml`, insert these functions just before the last line (`}`) of the file:

```qml

  function test_last_line_is_the_last_non_empty_line_trimmed() {
    compare(Results.lastLine("noise\n  {\"a\":1}  \n\n \n"), '{"a":1}')
  }

  function test_last_line_of_nothing_is_empty() {
    compare(Results.lastLine(null), "")
    compare(Results.lastLine(undefined), "")
    compare(Results.lastLine(""), "")
    compare(Results.lastLine("\n \n\t"), "")
    compare(Results.lastLine(0), "")
  }

  function test_last_line_drops_a_carriage_return() {
    compare(Results.lastLine("x\r\ny\r\n"), "y")
  }

  function test_parse_envelope_reads_the_last_line_object() {
    var envelope = Results.parseEnvelope('warning: something\n{"ok":true,"n":2}\n\n')
    verify(envelope !== null, "an object")
    compare(envelope.n, 2)
    compare(envelope.ok, true)
  }

  function test_parse_envelope_rejects_json_that_is_not_an_object() {
    compare(Results.parseEnvelope("[1]"), null)
    compare(Results.parseEnvelope("3"), null)
    compare(Results.parseEnvelope("\"s\""), null)
    compare(Results.parseEnvelope("true"), null)
    compare(Results.parseEnvelope("null"), null)
  }

  function test_parse_envelope_rejects_garbage() {
    compare(Results.parseEnvelope("{not json"), null)
    compare(Results.parseEnvelope("ok"), null)
    compare(Results.parseEnvelope('{"ok":true}\ngarbage'), null)
  }

  function test_parse_envelope_of_nothing_is_null() {
    compare(Results.parseEnvelope(""), null)
    compare(Results.parseEnvelope(null), null)
    compare(Results.parseEnvelope(undefined), null)
    compare(Results.parseEnvelope("\n\n"), null)
  }

  // String.prototype.trim strips U+00A0, which JSON.parse does not accept as whitespace.
  function test_parse_envelope_trims_what_trim_strips() {
    var envelope = Results.parseEnvelope('{"a":1} ')
    verify(envelope !== null, "an object")
    compare(envelope.a, 1)
  }

  function test_parse_envelope_reads_a_crlf_reply() {
    var envelope = Results.parseEnvelope('warn\r\n{"ok":true}\r\n')
    verify(envelope !== null, "an object")
    compare(envelope.ok, true)
  }

  function test_parse_envelope_of_a_non_string_is_null() {
    compare(Results.parseEnvelope(5), null)
    compare(Results.parseEnvelope(true), null)
    compare(Results.parseEnvelope({}), null)
  }
```

Note on `test_parse_envelope_of_a_non_string_is_null`: `String(5)` is `"5"`, which parses to a number → `null`; `String(true)` is `"true"` → boolean → `null`; `String({})` is `"[object Object]"` → parse error → `null`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_results`
Expected: FAIL. The output lists `FAIL!  : DomainResults::test_last_line_…` / `test_parse_envelope_…` lines with `TypeError: Property 'lastLine' of object [object Object] is not a function` (or `parseEnvelope`), and the script exits non-zero. The existing `test_parse_json_line_…` tests still pass.

- [ ] **Step 3: Write the minimal implementation**

Append to the end of `core/domain/results.js`:

```js

// The last line of `text` (String(text || ""), split on "\n") that is
// non-empty after trim(), trimmed; "" when there is none.
function lastLine(text) {
  var lines = String(text || "").split("\n")
  for (var i = lines.length - 1; i >= 0; i--) {
    var line = lines[i].trim()
    if (line !== "") return line
  }
  return ""
}

// The object JSON-parsed from lastLine(text), or null when that line is
// empty, is not JSON, or is not a plain object (an array, a scalar, null).
// Never throws.
function parseEnvelope(text) {
  var line = lastLine(text)
  if (line === "") return null
  var value = null
  try { value = JSON.parse(line) } catch (e) { return null }
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value : null
}
```

Do not change `parseJsonLine`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_results`
Expected: pytest passes; `== tests/core/domain/tst_results.qml` then `Totals: N passed, 0 failed, …` with no `FAIL` line and no `TypeError` line; exit code 0.

- [ ] **Step 5: Commit**

```bash
git add core/domain/results.js tests/core/domain/tst_results.qml
git commit -m "feat(domain): lastLine and parseEnvelope in results.js"
```

---

### Task 2: `Runs.runById`, `Runs.hasKey`, `Runs.copyMap`

**Files:**
- Modify: `core/domain/runs.js` (append a new section after the last function, `previewSummary`, at the end of the file)
- Test: `tests/core/domain/tst_runs.qml` (append before the final closing `}` of `TestCase`, after `test_display_order_garbage`)

**Interfaces:**
- Consumes: nothing (no other `runs.js` function is used or changed).
- Produces:
  - `Runs.runById(runs: any, id: any) -> object | null` — first truthy entry `e` of the array `runs` with `e.id === id`; `null` when none or when `runs` is not an array. Returns the entry itself.
  - `Runs.hasKey(map: any, key: any) -> boolean` — `false` for a `null`/`undefined` map, else `Object.prototype.hasOwnProperty.call(map, key)`.
  - `Runs.copyMap(map: any) -> object` — a new plain object with every own enumerable key of `map` and its value (shallow); `{}` for `null`/`undefined`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/domain/tst_runs.qml`, insert these functions just before the last line (`}`) of the file:

```qml

  function test_run_by_id_returns_the_entry_itself() {
    var list = [{ id: "a" }, { id: "b" }, { id: "c" }]
    verify(Runs.runById(list, "b") === list[1], "the entry itself")
    compare(Runs.runById(list, "z"), null)
  }

  function test_run_by_id_skips_empty_entries() {
    var list = [null, undefined, 0, { id: "a" }]
    verify(Runs.runById(list, "a") === list[3], "found past the empty entries")
  }

  function test_run_by_id_on_a_non_list_is_null() {
    compare(Runs.runById(null, "a"), null)
    compare(Runs.runById(undefined, "a"), null)
    compare(Runs.runById({}, "a"), null)
    compare(Runs.runById({ a: { id: "a" } }, "a"), null)
    compare(Runs.runById("abc", "a"), null)
  }

  function test_run_by_id_with_a_prototype_member_name() {
    var names = ["constructor", "toString", "__proto__", "hasOwnProperty", "valueOf"]
    for (var i = 0; i < names.length; i++) {
      compare(Runs.runById([{ id: "a" }], names[i]), null, names[i] + " absent")
      var list = [{ id: "a" }, { id: names[i] }]
      verify(Runs.runById(list, names[i]) === list[1], names[i] + " present")
    }
  }

  function test_run_by_id_is_strict() {
    compare(Runs.runById([{ id: "1" }], 1), null)
  }

  function test_run_by_id_of_the_empty_id_matches_no_idless_entry() {
    compare(Runs.runById([{}, { id: "a" }, { id: null }], ""), null)
  }

  function test_run_by_id_skips_primitive_entries() {
    compare(Runs.runById(["a", 5, true], "a"), null)
    var list = ["a", 5, true, { id: "a" }]
    verify(Runs.runById(list, "a") === list[3], "the object entry")
  }

  function test_has_key_counts_own_keys_only() {
    compare(Runs.hasKey({ a: 1 }, "a"), true)
    var names = ["toString", "constructor", "hasOwnProperty", "valueOf", "__proto__"]
    for (var i = 0; i < names.length; i++) {
      compare(Runs.hasKey({}, names[i]), false, names[i] + " inherited")
      var own = JSON.parse("{\"" + names[i] + "\": 1}")
      compare(Runs.hasKey(own, names[i]), true, names[i] + " own")
    }
  }

  function test_has_key_with_a_shadowed_has_own_property() {
    var map = { hasOwnProperty: 1, a: 2 }
    compare(Runs.hasKey(map, "a"), true)
    compare(Runs.hasKey(map, "b"), false)
  }

  function test_has_key_on_nothing_is_false() {
    compare(Runs.hasKey(null, "a"), false)
    compare(Runs.hasKey(undefined, "a"), false)
  }

  function test_has_key_coerces_the_key_like_has_own_property() {
    compare(Runs.hasKey({ "1": "x" }, 1), true)
    compare(Runs.hasKey({ "1": "x" }, 2), false)
  }

  function test_copy_map_is_a_new_shallow_copy() {
    var nested = { deep: true }
    var map = { a: 1, b: "two", c: nested }
    var copy = Runs.copyMap(map)
    verify(copy !== map, "a new object")
    compare(Object.keys(copy).sort().join(","), "a,b,c")
    compare(copy.a, 1)
    compare(copy.b, "two")
    verify(copy.c === nested, "shallow: the nested object is the same reference")
    copy.a = 99
    copy.d = 4
    compare(map.a, 1, "input value unchanged")
    compare(Object.prototype.hasOwnProperty.call(map, "d"), false, "input keys unchanged")
  }

  function test_copy_map_copies_own_keys_only() {
    var map = Object.create({ inherited: 1 })
    map.a = 2
    var copy = Runs.copyMap(map)
    compare(Object.prototype.hasOwnProperty.call(copy, "a"), true)
    compare(copy.a, 2)
    compare(Object.prototype.hasOwnProperty.call(copy, "inherited"), false)
    compare(copy.inherited, undefined)
    var named = Runs.copyMap({ constructor: 1, toString: 2 })
    compare(Object.prototype.hasOwnProperty.call(named, "constructor"), true)
    compare(Object.prototype.hasOwnProperty.call(named, "toString"), true)
    compare(named.constructor, 1)
    compare(named.toString, 2)
  }

  function test_copy_map_of_nothing_is_empty() {
    var a = Runs.copyMap(null)
    var b = Runs.copyMap(undefined)
    compare(typeof a, "object")
    verify(a !== null, "an object, not null")
    compare(Object.keys(a).length, 0)
    compare(Object.keys(b).length, 0)
    verify(a !== b, "a new object on each call")
  }
```

Deviation from spec test 18: it lists `"hasOwnProperty"` among the own keys `copyMap` copies. In this QML engine, `out["hasOwnProperty"] = v` on a plain object is silently ignored (checked with `qmltestrunner`: `var o = {}; o["hasOwnProperty"] = 3; Object.keys(o)` is empty), and today's store `copyMap` assigns the same way. Copying it would need `Object.defineProperty`, which changes behaviour and the spec forbids that. So the test checks `"constructor"` and `"toString"` only. `hasKey` on a map with its own `hasOwnProperty` key is still covered by `test_has_key_counts_own_keys_only` and `test_has_key_with_a_shadowed_has_own_property`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh domain/tst_runs`
Expected: FAIL. The output lists `FAIL!  : DomainRuns::test_run_by_id_…`, `test_has_key_…` and `test_copy_map_…` lines with `TypeError: Property 'runById' of object [object Object] is not a function` (or `hasKey` / `copyMap`); exit code non-zero. All pre-existing `DomainRuns` tests still pass.

- [ ] **Step 3: Write the minimal implementation**

Append to the end of `core/domain/runs.js` (after the closing `}` of `previewSummary`):

```js

// ---- Store helpers (split-runstore 2.1) --------------------------------------------------

// The first entry of `runs`, in order, that is truthy and whose `id` is ===
// `id`; null when there is none or `runs` is not an array. The entry itself,
// not a copy.
function runById(runs, id) {
  if (!Array.isArray(runs)) return null
  for (var i = 0; i < runs.length; i++) {
    if (runs[i] && runs[i].id === id) return runs[i]
  }
  return null
}

// Whether `map` has `key` as an own property; false for a null or undefined map.
function hasKey(map, key) {
  if (map === null || map === undefined) return false
  return Object.prototype.hasOwnProperty.call(map, key)
}

// A new plain object with every own enumerable key of `map` and its value
// (a shallow copy); {} for null or undefined.
function copyMap(map) {
  var out = {}
  for (var key in map) {
    if (hasKey(map, key)) out[key] = map[key]
  }
  return out
}
```

The section header line is 93 characters wide, like the other `// ---- … ----` headers in this file. Do not edit any existing function in `runs.js`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh domain/tst_runs`
Expected: `== tests/core/domain/tst_runs.qml` then `Totals: N passed, 0 failed, …`, no `FAIL` line, no `TypeError` line; exit code 0.

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(domain): runById, hasKey and copyMap in runs.js"
```

---

### Task 3: `RunStore` calls the domain functions

This task changes no behaviour. Its tests are the existing store characterization suite (`tests/core/stores/tst_run_store.qml`, `tst_app_runs.qml`, not edited) and `tests/architecture`, plus a grep that must come back empty. The grep is the RED step.

**Files:**
- Modify: `core/stores/RunStore.qml` — line 4 (imports), 752-758 (`runById`), 868-886 (`lastLine`, `parseEnvelope`), 894 (`rowOf`), 1079-1090 (`copyMap`, `hasKey`), and every `store.parseEnvelope(` / `store.copyMap(` / `store.hasKey(` call site (lines 442-1758).

**Interfaces:**
- Consumes: `Results.parseEnvelope(text)` (Task 1), `Runs.runById(runs, id)`, `Runs.hasKey(map, key)`, `Runs.copyMap(map)` (Task 2).
- Produces: `RunStore.runById(id) -> object | null` unchanged in signature and result. `RunStore` no longer has members `lastLine`, `parseEnvelope`, `copyMap`, `hasKey` (they were private helpers; nothing outside `RunStore.qml` calls them — verified by grep of `.qml`, `.js`, `.py` in the repo).

- [ ] **Step 1: Run the grep that must end up empty (RED)**

Run:
```bash
grep -nE 'function (lastLine|parseEnvelope|copyMap|hasKey)|store\.(lastLine|parseEnvelope|copyMap|hasKey)\(|hasOwnProperty' core/stores/RunStore.qml
```
Expected: many matches (the four `function` lines, 11 `store.parseEnvelope(`, 13 `store.copyMap(`, 29 `store.hasKey(` (on 27 lines), one `store.lastLine(`, and the `hasOwnProperty` lines at 894, 1083, 1089).

- [ ] **Step 2: Add the `Results` import**

In `core/stores/RunStore.qml`, replace:

```qml
import "../domain/runs.js" as Runs
```

with:

```qml
import "../domain/results.js" as Results
import "../domain/runs.js" as Runs
```

- [ ] **Step 3: Make `runById` a delegate**

Replace:

```qml
  // The run with this id in the snapshot, or null.
  function runById(id) {
    var list = store.runs
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id) return list[i]
    }
    return null
  }
```

with:

```qml
  // The run with this id in the snapshot, or null.
  function runById(id) {
    return Runs.runById(store.runs, id)
  }
```

- [ ] **Step 4: Delete `lastLine` and `parseEnvelope` from the store**

Delete this block (it sits between the end of the logs-reply handler and the `rowOf` comment), including the blank line after it:

```qml
  // The helper prints exactly one JSON line; anything before it (a warning) and
  // blank lines after it are ignored.
  function lastLine(text) {
    var lines = String(text || "").split("\n")
    for (var i = lines.length - 1; i >= 0; i--) {
      var line = lines[i].trim()
      if (line !== "") return line
    }
    return ""
  }

  // The reply's envelope object, or null when there is none to read.
  function parseEnvelope(text) {
    var line = store.lastLine(text)
    if (line === "") return null
    var value = null
    try { value = JSON.parse(line) } catch (e) { return null }
    return value !== null && typeof value === "object" && !Array.isArray(value) ? value : null
  }

```

so that the `// The \`am runs\` summary without its \`status\` key: …` comment of `rowOf` follows the previous function's closing `}` and one blank line.

- [ ] **Step 5: Use `Runs.hasKey` in `rowOf`**

Replace:

```qml
      if (key !== "status" && Object.prototype.hasOwnProperty.call(entry, key)) row[key] = entry[key]
```

with:

```qml
      if (key !== "status" && Runs.hasKey(entry, key)) row[key] = entry[key]
```

- [ ] **Step 6: Delete `copyMap` and `hasKey` from the store**

Under `// ---- run controls (S2 4.1)`, delete this block, including the blank line after it:

```qml
  // A copy of a {key: value} map, so a change is a new object.
  function copyMap(map) {
    var out = {}
    for (var key in map) {
      if (Object.prototype.hasOwnProperty.call(map, key)) out[key] = map[key]
    }
    return out
  }

  function hasKey(map, key) {
    return Object.prototype.hasOwnProperty.call(map, key)
  }

```

so that `// ---- run controls (S2 4.1)`, one blank line, then `// Starts a pause, resume or cancel of one run in \`runs\`, …` follow each other.

- [ ] **Step 7: Rewrite every call site**

Run:
```bash
sed -i -e 's/store\.parseEnvelope(/Results.parseEnvelope(/g' \
       -e 's/store\.copyMap(/Runs.copyMap(/g' \
       -e 's/store\.hasKey(/Runs.hasKey(/g' core/stores/RunStore.qml
```

This only renames the callee; arguments are untouched (for example line 442 becomes `var list = Runs.hasKey(store.runsByProject, usable[i].root) ? store.runsByProject[usable[i].root] : []`).

- [ ] **Step 8: Run the grep again (GREEN)**

Run:
```bash
grep -nE 'function (lastLine|parseEnvelope|copyMap|hasKey)|store\.(lastLine|parseEnvelope|copyMap|hasKey)\(|hasOwnProperty' core/stores/RunStore.qml; echo "exit=$?"
```
Expected: no matches, `exit=1`.

Then check the counts of the new calls:
```bash
grep -c 'Results\.parseEnvelope(' core/stores/RunStore.qml
grep -o 'Runs\.copyMap(' core/stores/RunStore.qml | wc -l
grep -o 'Runs\.hasKey(' core/stores/RunStore.qml | wc -l
grep -n 'Runs\.runById(' core/stores/RunStore.qml
git diff --stat core/stores/RunStore.qml
```
Expected: `11`; `13`; `30` (the 29 renamed `store.hasKey(` calls plus the `rowOf` site); one line, inside `function runById(id)`. Review `git diff core/stores/RunStore.qml`: every changed line is an import, the `runById` body, a deleted helper, or a callee rename — no argument or other token changed.

- [ ] **Step 9: Run the store and architecture suites**

Run: `timeout 900 bash tests/run.sh core/stores`
Expected: pytest (which includes `tests/architecture/test_layers.py`) passes; every `tests/core/stores/tst_*.qml` prints `Totals: … 0 failed …`, no `FAIL` line, no `TypeError` / `ReferenceError` / `is not a function` line; exit code 0.

Run: `timeout 900 bash tests/run.sh tst_app_runs`
Expected: `Totals: … 0 failed …`, exit code 0.

- [ ] **Step 10: Run the whole suite**

Run: `timeout 1800 bash tests/run.sh`
Expected: pytest passes, every QML suite reports `0 failed`, no `TypeError` / `ReferenceError` / `is not a function` line, exit code 0.

- [ ] **Step 11: Commit**

```bash
git add core/stores/RunStore.qml
git commit -m "refactor(runs): RunStore calls the domain envelope and map helpers"
```
<!-- task-pipeline: validated -->
