# 1.2 QML fixture loader: `tests/helpers/amFixtures.js` — design

Card `9f7e9956`, a subtask of story `6596351c` ("Real am fixtures and contract
tests"), blocked by `f1f0e802` (1.1, the contract test). Parent spec:
`docs/superpowers/specs/2026-10-05-align-run-model-design.md` (below:
**parent**). Work breakdown item 1 (parent L321-323): this subtask is "the QML
fixture loader" only.

## Goal

QML tests get one way to read the committed real-am captures in
`tests/fixtures/am/`: `F.load(name)` from `tests/helpers/amFixtures.js`. It
returns a fresh parsed object on every call and throws an `Error` naming the
file when the file cannot be read or parsed. `tests/run.sh` lets
`qmltestrunner` read `file://` URLs. A new QML test,
`tests/helpers/tst_am_fixtures.qml`, pins the loader. No plugin code changes,
and no fixture changes.

## Inherited constraints

| constraint | source |
|---|---|
| Fixtures live in `tests/fixtures/am/`. The nine files are `runs.json`, `status-started.json`, `status-done.json`, `status-escalated.json`, `status-escalated-integrate.json`, `status-done-integrate.json`, `watch-events.json`, `watch-hello.json`, `logs-attempt.json` | parent L233-249 |
| Readers ignore keys starting with `_`. The loader does not strip them; it returns the file as parsed | parent L251 |
| Edits to a fixture inside a test are made on a fresh copy, so `load` never returns a shared object | parent L265-267 |
| `tests/helpers/amFixtures.js` is a `.pragma library`. `load(name)` returns a fresh parse of `tests/fixtures/am/<name>` through a synchronous `XMLHttpRequest`, resolved with `Qt.resolvedUrl` against the helper itself, and throws an Error naming the file when it cannot | parent L269-273 |
| `tests/run.sh` sets `QML_XHR_ALLOW_FILE_READ=1` for `qmltestrunner` | parent L273-274 |
| Python reads fixtures with `json.load`. This subtask adds no Python | parent L269 |
| `bash tests/run.sh` is green, and `tests/architecture` is green (no duplicated components, icon glyph rules, `docs/architecture.md` layering) | card |
| Docstrings and comments state the contract only, with no narrative | card |

## Verified platform behavior (Qt 6.11.2, `qmltestrunner`, 2026-10-05)

These probes ran outside the repo, and the loader's design rests on them:

- Inside a `.pragma library` file, `Qt.resolvedUrl("../fixtures/am/x")`
  resolves against the `.js` file's own directory, not the importing test's.
- With `QML_XHR_ALLOW_FILE_READ=1`:
  - an existing file gives `status` 200 and its full text;
  - a missing file gives `status` 0 and an empty `responseText`, with no throw;
  - a directory URL also gives `status` 0 and empty text;
  - a malformed file gives `status` 200 and its text, so `JSON.parse` throws.
- Without the variable, Qt prints `XMLHttpRequest: Using GET on a local file is
  disabled by default.` and `send()` throws `Error: Invalid state`.

## Observable behavior

### A. `tests/helpers/amFixtures.js`

- Line 1 is `.pragma library`. The style follows `tests/helpers/find.js`:
  2-space indent, no semicolons, and a contract-only comment above the
  function.
- It exports exactly one function, `load(name)`.
- `load(name)`:
  1. Builds the URL `Qt.resolvedUrl("../fixtures/am/" + name)`. Because the
     URL resolves against the helper file, the result does not depend on which
     directory the importing test is in.
  2. Reads the URL with a synchronous `XMLHttpRequest` GET (`open("GET", url,
     false)`, then `send()`).
  3. Treats the read as failed when `send()` throws, or when `status` is
     neither 0 nor 200, or when `responseText` is empty. Qt reports a missing
     file as status 0 with empty text, and every real fixture is non-empty.
  4. Returns `JSON.parse(responseText)`. A new object graph is built on every
     call, and nothing is cached.
  5. On any failure (a failed read or a `JSON.parse` exception), it throws a
     new `Error` whose `message` contains `name` exactly as the caller passed
     it. The message also names the cause. The form is
     `amFixtures: cannot load <name>: <cause>`, where `<cause>` is `not
     readable` for a failed read and the parser's or `send()`'s message
     otherwise. Tests assert only that the message contains `<name>`. They do
     not check the exact wording.
- `name` is a path relative to `tests/fixtures/am/`, for example
  `"status-done.json"`. The loader adds no extension and does not validate
  `name` against a list. Any name that does not lead to a readable JSON file
  throws as described above. That includes `""`, a directory, and an unknown
  file.
- The loader leaves the result as parsed. It does not strip `_`-prefixed keys
  and does not unwrap `{ok, data}` envelopes.

### B. `tests/run.sh`

- The `qmltestrunner` invocation (currently line 29, `out=$(QT_QPA_PLATFORM=offscreen
  "$runner" ...)`) also gets `QML_XHR_ALLOW_FILE_READ=1` in its environment,
  set on that command the same way `QT_QPA_PLATFORM` is. The variable is not
  exported for the pytest step.
- Nothing else in `run.sh` changes. Discovery is `find tests -name
  'tst_*.qml'`, so `tests/helpers/tst_am_fixtures.qml` runs without being
  registered, and the tar mirror already copies `tests/fixtures/`.

### C. `tests/helpers/README.md`

One short paragraph documents `amFixtures.js`: what `load(name)` returns,
that it throws, that it needs `QML_XHR_ALLOW_FILE_READ=1` (which `run.sh`
sets), and the import line for a test under `tests/<dir>/`, which is
`import "../helpers/amFixtures.js" as F`.

## Tests (`tests/helpers/tst_am_fixtures.qml`)

There is one QML `TestCase`, `name: "AmFixtures"`, with no window
(`when` is not needed). It imports `"amFixtures.js" as F`. It has a header
comment in the style of `tests/ui/tst_plugin_dir.qml`, kept to the contract
only. Throws are asserted with `try { …; fail(…) } catch (e) { … }`. QtTest
has no `verify(throws)`.

All the tests belong in the **QML tier** (`qmltestrunner` through `bash
tests/run.sh`). The thing under test is a QML JavaScript library that depends
on the QML engine's `XMLHttpRequest`, `Qt.resolvedUrl` and pragma-library URL
resolution, and on `run.sh` setting the environment, so no Python or pytest
tier can exercise it. No pytest is added.

| # | test | asserts | why it matters |
|---|---|---|---|
| 1 | `test_every_fixture_loads` | For each of the nine names in the parent's table (parent L239-249), `F.load(n)` returns a non-null `object` without throwing. | This is the card's "every fixture of the spec's table loads". It also proves that run.sh sets `QML_XHR_ALLOW_FILE_READ`, because without it every load throws. |
| 2 | `test_loads_real_content` | `F.load("runs.json").ok === true` and `Array.isArray(F.load("runs.json").data.runs)`; `F.load("watch-hello.json").schema_2.schema === 2`. | Shows that the loader returns the file's parsed content and not an empty or placeholder object, and that `_`-free paths are untouched. |
| 3 | `test_two_loads_are_distinct` | `a = F.load("status-done.json")`, `b = F.load("status-done.json")`: `verify(a !== b)`, `verify(a.data !== b.data)`, `compare(JSON.stringify(a), JSON.stringify(b))`. Then `a.data.run.status = "canceled"` (label: a mutation on a fresh copy), and `b.data.run.status` is unchanged and a third `F.load` still has the original. | This is the card's "two loads of one name are distinct objects". Parent L265-267 depends on a fresh copy per test. |
| 4 | `test_unknown_name_throws_naming_it` | `F.load("no-such-fixture.json")` throws; the caught value is an `Error` (`e instanceof Error`) whose `message` contains `"no-such-fixture.json"`. | This is the card's "an unknown name throws with the name in its message". It also pins that a status-0, empty-text read becomes an error and not `JSON.parse("")`'s nameless SyntaxError. |
| 5 | `test_directory_name_throws_naming_it` | `F.load("")` throws an `Error` whose message contains `amFixtures` (the name is empty, so the prefix is what identifies the loader). | A directory URL reads as status 0 with empty text, and it must not slip through as a parse of nothing. |

A malformed-JSON test would need a malformed file in `tests/fixtures/am/`. That
directory holds only real captures (parent L233-237), so no malformed file is
added there. Parse failures are covered by the same message path as test 4,
because the loader turns every failure into `amFixtures: cannot load <name>:
…`. The planner may add a malformed file elsewhere and reach it through
`../`, for example `F.load("../../helpers/testdata/bad.json")`, only if it
stays outside `tests/fixtures/am/` and carries a `synthetic:` note
(parent L260-262). That is optional and not required by this card.

Red state for TDD: before `amFixtures.js` exists, the import fails and the
whole file errors. That counts as a failing QML test in `run.sh`. Before the
`run.sh` edit, tests 1-3 fail because `send()` throws.

## Error paths, summarized

| input / condition | result |
|---|---|
| existing, valid fixture | fresh parsed object |
| unknown file name | `Error`, message contains the name |
| `""` or a directory | `Error`, message starts with `amFixtures: cannot load` |
| malformed JSON | `Error`, message contains the name and the parser's message |
| `QML_XHR_ALLOW_FILE_READ` unset | `Error`, message contains the name (`send()`'s `Invalid state`) |

## Out of scope

- Shape and key-set checks of the fixtures, and the live `am` check. Those are
  `tests/contract/test_am_fixtures.py`, sibling 1.1 (`f1f0e802`, parent
  L276-284).
- The helpers' fake `am` that serves the fixtures to the Python helpers. That
  is a sibling under item 1 (parent L322-323).
- Converting any existing QML test to use the loader. This includes
  `normalizeRun`, `rollup`, `runTree`, `logTail`, `RunStore` and the flow
  tests. That is work breakdown items 2-4 (parent L324-330).
- Any change to fixture files, to plugin code (`core/`, `ui/`, `vendor/`), or
  to `docs/` other than `tests/helpers/README.md`.
- Caching, name validation, `_`-key stripping, envelope unwrapping, and an
  async API.
- A pytest for the loader.

## Files

| file | change |
|---|---|
| `tests/helpers/amFixtures.js` | create |
| `tests/helpers/tst_am_fixtures.qml` | create |
| `tests/run.sh` | add `QML_XHR_ALLOW_FILE_READ=1` to the `qmltestrunner` command |
| `tests/helpers/README.md` | add the `amFixtures.js` paragraph |

## Verification

- `bash tests/run.sh tst_am_fixtures` shows `== tests/helpers/tst_am_fixtures.qml`
  and `Totals: 7 passed, 0 failed` (5 tests plus init and cleanup).
- `bash tests/run.sh` exits 0, which includes pytest `tests/architecture` and
  every existing QML test. The new environment variable must not change any
  other test's outcome. `tst_plugin_dir.qml` uses `FolderListModel`, not XHR.

---

# 1.2 QML fixture loader (`tests/helpers/amFixtures.js`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** QML tests read the committed real-am captures through `F.load(name)` from `tests/helpers/amFixtures.js`. Each call returns a fresh parsed object, and any failure throws an `Error` that names the file.

**Architecture:** A `.pragma library` JS file builds the URL with `Qt.resolvedUrl("../fixtures/am/" + name)`, which resolves against the helper itself. It reads the URL with a synchronous `XMLHttpRequest` and returns `JSON.parse` of the text. Every failure becomes one `Error`: `amFixtures: cannot load <name>: <cause>`. `tests/run.sh` sets `QML_XHR_ALLOW_FILE_READ=1` on the `qmltestrunner` command only. A QML `TestCase` in `tests/helpers/tst_am_fixtures.qml` pins the behavior.

**Tech Stack:** Qt 6.11 QML / QtTest (`qmltestrunner`), QML JavaScript, bash (`tests/run.sh`).

**Spec:** `docs/superpowers/specs/1-2-qml-fixture-loader-9f7e9956.md` (reproduced in full above this plan). Parent: `docs/superpowers/specs/2026-10-05-align-run-model-design.md`.

## Global Constraints

- Fixtures live in `tests/fixtures/am/`. The nine files are `runs.json`, `status-started.json`, `status-done.json`, `status-escalated.json`, `status-escalated-integrate.json`, `status-done-integrate.json`, `watch-events.json`, `watch-hello.json`, `logs-attempt.json`. Never edit them, and never add a file to that directory.
- The loader does not strip `_`-prefixed keys and does not unwrap `{ok, data}` envelopes. It returns the file as parsed.
- `load` never returns a shared object. Every call builds a new object graph, and nothing is cached.
- `tests/helpers/amFixtures.js` is a `.pragma library` (line 1). It exports exactly one function, `load(name)`. Its style follows `tests/helpers/find.js`: 2-space indent, no semicolons, and a contract-only comment above the function.
- The error message form is `amFixtures: cannot load <name>: <cause>`. `<cause>` is `not readable` for a failed read, and otherwise the message from the parser or from `send()`. Tests assert only that the message contains `<name>` (or `amFixtures` when the name is `""`).
- `tests/run.sh` sets `QML_XHR_ALLOW_FILE_READ=1` on the `qmltestrunner` command only, and does not export it for pytest.
- No Python and no pytest are added. Do not change plugin code (`core/`, `ui/`, `vendor/`), fixture files, or `docs/`.
- Docstrings and comments state the contract only, with no narrative.
- `bash tests/run.sh` is green, and that includes `tests/architecture`.

## Review Focus

1. **Malformed JSON.** A file that reads but does not parse must throw an `Error` that names the file and carries the parser's cause, not a bare `SyntaxError`. Pinned by `test_malformed_json_throws_naming_it_and_the_cause` (Task 2), through a synthetic file at `tests/helpers/testdata/bad.json`, which is outside `tests/fixtures/am/`.
2. **A name without its extension.** `F.load("runs")` must throw naming `runs`. The loader adds no extension and does not fall back to `runs.json`. Pinned by `test_a_name_without_extension_is_not_completed` (Task 2).
3. **A test in another directory.** A test under `tests/core/` that uses the README's import line, `import "../helpers/amFixtures.js" as F`, must get the same fixtures. Pinned by `test_a_test_in_another_dir_loads_through_the_documented_import` (Task 1).
4. **Mutating a nested array.** Pushing onto `data.runs` of one load must not show up in a later load. Pinned by `test_array_edits_do_not_leak_into_later_loads` (Task 1).
5. **`_`-prefixed keys.** These must come back untouched, because readers ignore them and the loader does not strip them. Pinned by `test_underscore_keys_are_kept` (Task 1).

These five tests come on top of the spec's five tests. The verification count therefore becomes **`Totals: 12 passed, 0 failed`** (10 tests plus init and cleanup), not the spec's 7.

---

## File Structure

| file | responsibility |
|---|---|
| `tests/helpers/amFixtures.js` (create) | the loader, `load(name)` |
| `tests/helpers/tst_am_fixtures.qml` (create) | QML `TestCase` `AmFixtures`, which pins the loader |
| `tests/helpers/testdata/bad.json` (create, Task 2) | synthetic malformed file for the parse-failure test |
| `tests/run.sh` (modify line 29) | `QML_XHR_ALLOW_FILE_READ=1` on the `qmltestrunner` command |
| `tests/helpers/README.md` (modify, Task 2) | one paragraph that documents `amFixtures.js` |

Notes for the engineer:
- `bash tests/run.sh <filter>` always runs the whole pytest suite first, then only the QML tests whose path contains `<filter>`. The QML tests run against a temp-dir copy of the repo, made with `tar`. `tests/fixtures/` and `tests/helpers/testdata/` are copied with it.
- run.sh prints only the `FAIL`, `Totals` and `   Loc` lines of each QML file. To see the full output of one file, run it directly:
  `QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/helpers/tst_am_fixtures.qml`
- QtTest's `fail()` records the failure and then throws. Inside `try { F.load(x); fail("…") } catch (e) { … }`, the `catch` also catches that throw. The failure is recorded either way, so the pattern is sound.

---

### Task 1: Loader happy path, the run.sh environment, and fresh copies

**Files:**
- Create: `tests/helpers/tst_am_fixtures.qml`
- Create: `tests/helpers/amFixtures.js`
- Modify: `tests/run.sh:29`

**Interfaces:**
- Consumes: nothing.
- Produces: `load(name: string) -> object` in `tests/helpers/amFixtures.js` (`.pragma library`), imported as `import "amFixtures.js" as F` from `tests/helpers/` and as `import "../helpers/amFixtures.js" as F` from `tests/<dir>/`. In this task it throws whatever `send()` / `JSON.parse` throw, and Task 2 wraps those errors. The task also produces the `TestCase` `id: tc`, `name: "AmFixtures"`, and the property `names` (the nine fixture names), which Task 2 appends tests to.

- [ ] **Step 1: Write the failing tests**

Create `tests/helpers/tst_am_fixtures.qml`:

```qml
// tests/helpers/tst_am_fixtures.qml
// amFixtures.js: load(name) returns a fresh parse of tests/fixtures/am/<name>
// on every call and throws an Error whose message names <name> when the file
// cannot be read or parsed. Needs QML_XHR_ALLOW_FILE_READ=1 (tests/run.sh).
import QtQuick
import QtTest
import "amFixtures.js" as F

TestCase {
  id: tc
  name: "AmFixtures"

  readonly property var names: [
    "runs.json", "status-started.json", "status-done.json", "status-escalated.json",
    "status-escalated-integrate.json", "status-done-integrate.json", "watch-events.json",
    "watch-hello.json", "logs-attempt.json"
  ]

  function test_every_fixture_loads() {
    for (var i = 0; i < names.length; i++) {
      var f = F.load(names[i])
      verify(f !== null && typeof f === "object", names[i])
    }
  }

  function test_loads_real_content() {
    var runs = F.load("runs.json")
    compare(runs.ok, true)
    verify(Array.isArray(runs.data.runs), "runs.json data.runs is an array")
    compare(F.load("watch-hello.json").schema_2.schema, 2)
  }

  function test_underscore_keys_are_kept() {
    compare(typeof F.load("watch-hello.json")._note, "string")
  }

  function test_two_loads_are_distinct() {
    var a = F.load("status-done.json")
    var b = F.load("status-done.json")
    verify(a !== b, "same object returned twice")
    verify(a.data !== b.data, "same data object returned twice")
    compare(JSON.stringify(a), JSON.stringify(b))
    // A mutation on a fresh copy.
    a.data.run.status = "canceled"
    compare(b.data.run.status, "done")
    compare(F.load("status-done.json").data.run.status, "done")
  }

  function test_array_edits_do_not_leak_into_later_loads() {
    var n = F.load("runs.json").data.runs.length
    var a = F.load("runs.json")
    // A mutation on a fresh copy.
    a.data.runs.push({ id: "extra" })
    compare(F.load("runs.json").data.runs.length, n)
  }

  function test_a_test_in_another_dir_loads_through_the_documented_import() {
    var o = Qt.createQmlObject(
      'import QtQml\nimport "../helpers/amFixtures.js" as F\nQtObject { property var r: F.load("runs.json") }',
      tc, Qt.resolvedUrl("../core/AmFixturesProbe.qml"))
    verify(o.r !== null && typeof o.r === "object", "no object from tests/core")
    compare(o.r.ok, true)
    o.destroy()
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_am_fixtures; echo "exit=$?"`
Expected: pytest passes. Then `== tests/helpers/tst_am_fixtures.qml` is printed with no `Totals: … 0 failed` line, because the import `"amFixtures.js"` does not resolve and the whole file errors. Last line: `exit=1`.

- [ ] **Step 3: Write the minimal loader**

Create `tests/helpers/amFixtures.js`:

```js
.pragma library

// A fresh parse of tests/fixtures/am/<name> on every call, resolved against
// this file. Needs QML_XHR_ALLOW_FILE_READ=1.
function load(name) {
  var xhr = new XMLHttpRequest()
  xhr.open("GET", Qt.resolvedUrl("../fixtures/am/" + name), false)
  xhr.send()
  return JSON.parse(xhr.responseText)
}
```

- [ ] **Step 4: Run the tests to verify they still fail, now for the missing env var**

Run: `bash tests/run.sh tst_am_fixtures; echo "exit=$?"`
Expected: the six tests appear as `FAIL!` lines. The direct run without the variable shows why:
`QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/helpers/tst_am_fixtures.qml`
prints `XMLHttpRequest: Using GET on a local file is disabled by default.` and `Error: Invalid state`. Last line: `exit=1`.

- [ ] **Step 5: Set the variable in run.sh**

In `tests/run.sh`, replace line 29:

```bash
  out=$(QT_QPA_PLATFORM=offscreen "$runner" -import "$work/repo/tests/stubs" -input "$work/repo/${test#$repo/}" 2>&1) || status=1
```

with:

```bash
  out=$(QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 "$runner" -import "$work/repo/tests/stubs" -input "$work/repo/${test#$repo/}" 2>&1) || status=1
```

Change nothing else in the file. The pytest lines above it stay as they are.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_am_fixtures; echo "exit=$?"`
Expected:
```
== tests/helpers/tst_am_fixtures.qml
Totals: 8 passed, 0 failed, 0 skipped, 0 blacklisted, …
exit=0
```

- [ ] **Step 7: Run the whole suite**

Run: `bash tests/run.sh; echo "exit=$?"`
Expected: pytest is green, including `tests/architecture`. Every QML file shows `Totals: N passed, 0 failed`, and the last line is `exit=0`.

- [ ] **Step 8: Commit**

```bash
git add tests/helpers/amFixtures.js tests/helpers/tst_am_fixtures.qml tests/run.sh
git commit -m "test(helpers): load the committed am fixtures from QML as fresh copies"
```

---

### Task 2: Every failure throws an Error naming the file, plus the README

**Files:**
- Modify: `tests/helpers/tst_am_fixtures.qml` (append four tests inside `TestCase`)
- Create: `tests/helpers/testdata/bad.json`
- Modify: `tests/helpers/amFixtures.js` (replace the whole file)
- Modify: `tests/helpers/README.md` (append one paragraph)

**Interfaces:**
- Consumes: `load(name)` and the `TestCase` `AmFixtures` (`id: tc`) from Task 1.
- Produces: `load(name)` throws `new Error("amFixtures: cannot load " + name + ": " + cause)` on every failure, where `cause` is `"not readable"` or the caught `e.message`.

- [ ] **Step 1: Write the failing tests**

Create `tests/helpers/testdata/bad.json` with exactly this one line. It is deliberately not JSON:

```
synthetic: deliberately malformed JSON for tst_am_fixtures.qml {
```

In `tests/helpers/tst_am_fixtures.qml`, add these four functions after `test_a_test_in_another_dir_loads_through_the_documented_import` and before the closing `}` of `TestCase`:

```qml
  function test_unknown_name_throws_naming_it() {
    try {
      F.load("no-such-fixture.json")
      fail("no throw for no-such-fixture.json")
    } catch (e) {
      verify(e instanceof Error, "not an Error: " + e)
      verify(e.message.indexOf("no-such-fixture.json") >= 0, e.message)
    }
  }

  function test_directory_name_throws_naming_it() {
    try {
      F.load("")
      fail("no throw for the fixtures directory")
    } catch (e) {
      verify(e instanceof Error, "not an Error: " + e)
      verify(e.message.indexOf("amFixtures") >= 0, e.message)
    }
  }

  function test_a_name_without_extension_is_not_completed() {
    try {
      F.load("runs")
      fail("no throw for runs")
    } catch (e) {
      verify(e instanceof Error, "not an Error: " + e)
      verify(e.message.indexOf("runs") >= 0, e.message)
      verify(e.message.indexOf("amFixtures") >= 0, e.message)
    }
  }

  function test_malformed_json_throws_naming_it_and_the_cause() {
    var name = "../../helpers/testdata/bad.json"
    try {
      F.load(name)
      fail("no throw for " + name)
    } catch (e) {
      verify(e instanceof Error, "not an Error: " + e)
      verify(e.message.indexOf(name) >= 0, e.message)
      verify(e.message.indexOf("not readable") < 0, "a parse failure reported as a read failure: " + e.message)
    }
  }
```

(`test_a_name_without_extension_is_not_completed` also checks for `amFixtures`, because the bare `SyntaxError` from `JSON.parse("")` never contains it. Without that check, the word `runs` alone could match by accident.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_am_fixtures; echo "exit=$?"`
Expected: the four new tests appear as `FAIL!` lines. The Task 1 loader lets `JSON.parse("")` or `JSON.parse` of the bad text throw a `SyntaxError` whose message (`JSON.parse: Parse error`) names neither the file nor `amFixtures`. The output shows `Totals: 8 passed, 4 failed`, and the last line is `exit=1`.

- [ ] **Step 3: Implement the error path**

Replace the whole of `tests/helpers/amFixtures.js` with:

```js
.pragma library

// A fresh parse of tests/fixtures/am/<name> on every call, resolved against
// this file. Throws Error("amFixtures: cannot load <name>: <cause>") when the
// file cannot be read or parsed. Needs QML_XHR_ALLOW_FILE_READ=1.
function load(name) {
  var cause
  try {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", Qt.resolvedUrl("../fixtures/am/" + name), false)
    xhr.send()
    if ((xhr.status === 0 || xhr.status === 200) && xhr.responseText !== "")
      return JSON.parse(xhr.responseText)
    cause = "not readable"
  } catch (e) {
    cause = e.message
  }
  throw new Error("amFixtures: cannot load " + name + ": " + cause)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_am_fixtures; echo "exit=$?"`
Expected:
```
== tests/helpers/tst_am_fixtures.qml
Totals: 12 passed, 0 failed, 0 skipped, 0 blacklisted, …
exit=0
```

- [ ] **Step 5: Document the loader**

Append to `tests/helpers/README.md`, after the existing last line, leaving one blank line between them:

```markdown

`amFixtures.js` is a `.pragma library` with `load(name)`. It returns a fresh
parse of `tests/fixtures/am/<name>` on every call, so edits never leak between
tests, and it throws an `Error` naming `<name>` when the file cannot be read or
parsed. It reads through `XMLHttpRequest`, which needs `QML_XHR_ALLOW_FILE_READ=1`;
`tests/run.sh` sets it. From a test under `tests/<dir>/`:

    import "../helpers/amFixtures.js" as F
```

- [ ] **Step 6: Run the whole suite**

Run: `bash tests/run.sh; echo "exit=$?"`
Expected: pytest is green, including `tests/architecture`. Every QML file shows `0 failed`, `tests/helpers/tst_am_fixtures.qml` shows `Totals: 12 passed, 0 failed`, and the last line is `exit=0`.

- [ ] **Step 7: Check that no out-of-scope file changed**

Run: `git status --porcelain`
Expected: only `tests/helpers/amFixtures.js`, `tests/helpers/tst_am_fixtures.qml`, `tests/helpers/README.md` and `tests/helpers/testdata/bad.json` appear. Nothing under `tests/fixtures/am/`, `core/`, `ui/`, `vendor/` or `docs/` appears, except the plan and spec, which the workflow commits.

- [ ] **Step 8: Commit**

```bash
git add tests/helpers/amFixtures.js tests/helpers/tst_am_fixtures.qml tests/helpers/README.md tests/helpers/testdata/bad.json
git commit -m "test(helpers): name the fixture in every amFixtures load failure"
```

---

## Self-review against the spec

- **A. amFixtures.js.** `.pragma library` on line 1, find.js style, a single `load`, the URL through `Qt.resolvedUrl("../fixtures/am/" + name)`, a sync XHR, the failure rule (send throws, or status not 0/200, or empty text), `JSON.parse` on every call, and the `amFixtures: cannot load <name>: <cause>` form with `not readable` or the caught message. Task 1 Step 3 and Task 2 Step 3 cover all of these. There is no stripping, unwrapping, caching or validation.
- **B. run.sh.** Task 1 Step 5 sets the variable on the `qmltestrunner` command only.
- **C. README.** Task 2 Step 5 covers what `load` returns, that it throws, the env var, run.sh setting it, and the import line.
- **Tests 1-5.** Tests 1-3 are in Task 1 (`test_every_fixture_loads`, `test_loads_real_content`, `test_two_loads_are_distinct`). Tests 4-5 are in Task 2 (`test_unknown_name_throws_naming_it`, `test_directory_name_throws_naming_it`). Throws are asserted with try/fail/catch, the `TestCase` is `name: "AmFixtures"` with no `when`, and the header comment states the contract only.
- **Error-path table.** Unknown name: test 4. `""` / directory: test 5. Malformed JSON: Review Focus 1, through the optional synthetic file outside `tests/fixtures/am/`, which carries a `synthetic:` note. Env unset: Task 1 Step 4 shows it as the RED state. With the variable unset, `send()` throws inside the `try`, so the error is wrapped with the name. No permanent test covers this, because run.sh always sets the variable.
- **Verification.** The spec says `Totals: 7 passed`. With the five Review Focus tests added it is `Totals: 12 passed`, as noted in Review Focus.
- **Probes.** Before this plan was written, two behaviors were probed on Qt 6.11.2: `Qt.createQmlObject` with a `../core/…` URL resolves `../helpers/amFixtures.js` and loads `runs.json`, and `JSON.parse` of the malformed text throws `SyntaxError: JSON.parse: Parse error`.
- **Placeholders.** None remain. Names are consistent across the tasks: `load`, `F`, `tc`, `names`.
<!-- task-pipeline: validated -->
