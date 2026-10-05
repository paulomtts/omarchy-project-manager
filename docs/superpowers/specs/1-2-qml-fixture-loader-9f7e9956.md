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
