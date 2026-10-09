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
