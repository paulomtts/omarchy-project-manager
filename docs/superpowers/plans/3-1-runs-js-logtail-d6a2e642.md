# 3.1 runs.js: logTail reads am logs' artifact texts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Runs.logTail` reads an `am logs` data object's `artifacts.stdout.text` and `artifacts.stderr.text` (am's real shape) instead of the guessed top-level `data.stdout` / `data.stderr`, so Run detail's output pane shows a real attempt's output.

**Architecture:** One function changes in `core/domain/runs.js`: `logTail` (lines 511-523 today) and its contract comment. It takes `data.artifacts` when it is a plain object, and for each stream reads `.text` of the artifact when the artifact is a plain object; `_linesOf` (unchanged) already turns a non-string into no lines. No production change elsewhere: `RunStore.applyLogs` (`core/stores/RunStore.qml:420`) already passes the envelope's `data`. Tests: `tests/core/domain/tst_runs.qml` gets a real-fixture test and its `test_log_tail` rebuilt on the fixture; the hand-written logs replies in `tests/core/stores/tst_run_store.qml` (`logsReply`) and `tests/ui/tst_runs_flow.qml` (`logsOk`) are rebuilt from `tests/fixtures/am/logs-attempt.json`, plus one new store test on the unmodified capture.

**Tech Stack:** Qt 6 QML / V4 JavaScript (`.pragma library`), QtTest via `qmltestrunner`, driven by `bash tests/run.sh [path-substring]` (pytest runs first, then every `tst_*.qml` whose path contains the substring; `core/domain/tst_runs` matches only `tests/core/domain/tst_runs.qml`, `tst_run_store` only `tests/core/stores/tst_run_store.qml`, `tst_runs_flow` only `tests/ui/tst_runs_flow.qml`). Fixtures are loaded with `tests/helpers/amFixtures.js` `load(name)` — a fresh `JSON.parse` on every call, so editing the result never affects another call.

**Spec:** `docs/superpowers/specs/3-1-runs-js-logtail-d6a2e642.md` (prepended below, headings demoted one level; executors read both).

## Global Constraints

- Code: only `logTail` and the comment above it change in `core/domain/runs.js`. `_linesOf`, `snapshotAgeText`, every other function, `core/stores/RunStore.qml`, every screen: **not edited**.
- `am logs` data shape: `run_id, story_id, card, phase, attempt, status, exit_code, artifacts`; `artifacts.prompt`, `.result`, `.stdout`, `.stderr` each `{path, present, text}`, `text` null when absent; no `data.stdout` string.
- `logTail` reads `artifacts.stdout.text` then `artifacts.stderr.text`; a null, missing or non-string `text`, a missing / non-object artifact, a missing / non-object `artifacts`, a non-object (or array) `data` is no lines. `present` and `path` are not consulted. `prompt`, `result` and a top-level `data.stdout` / `data.stderr` are ignored.
- Truncation per stream, unchanged: each stream keeps its last `max` lines; `truncated` is true when either stream had more than `max`; `max` is `Math.floor(maxLines)` for a finite `maxLines >= 1`, else 200.
- Never throws; never mutates `data`. `core/domain/runs.js` stays `.pragma library` with exactly `.import "board.js" as Board`; `docs/architecture.md` layering holds and `tests/architecture` passes.
- Not changed: `RunStore`'s public API; screen layouts; deterministic-phase logs; `docs/architecture.md`; the fixtures.
- Every unit test of code reading am output builds its input from `tests/fixtures/am/` via `F.load(name)`; a hand-written am payload only for a synthetic edge case, with a `// synthetic:` comment; edits to a fixture in a test are on a fresh copy and never change its shape.
- Docstrings and comments state the contract only, no narrative.
- No QML test function name may end in `_data` (QtTest treats it as a data provider).
- `bash tests/run.sh` green at the end; tests first (red before green). Never `git stash`.

## Review Focus

1. An `am logs` reply in the old guessed shape (top-level `stdout` / `stderr` strings, alone or next to real `artifacts`): expected those strings to be ignored — only the artifact texts show. Pinned in Task 1 Step 2 (`test_log_tail_reads_only_the_stream_artifacts`, legacy and old-shape-alone cases).
2. A stderr artifact with `present: false` but a string `text`: expected the text to be shown after stdout (am, not `present`, decides whether `text` is null). Pinned in Task 1 Step 2.
3. A reply whose `artifacts` or a stream artifact is missing, null, an array or a number, or whose `text` is a number / array / null: expected an empty, untruncated pane, never a thrown error that would leave the store in `logsLoading`. Pinned in Task 1 Step 1 (garbage list) and Step 2 (stdout artifact deleted).
4. A real attempt longer than the limit: expected the last `maxLines` lines of the real text and `truncated` true. Pinned in Task 1 Step 2 (`test_log_tail_of_a_real_attempt` with `maxLines` 10).
5. A stdout text that is only `"\n"`: expected no lines (empty pane, not one blank line), and the fixture data object left unmodified by the call. Pinned in Task 1 Step 1 (`"\n"` case) and Step 2 (`JSON.stringify` before/after).

---

## Spec (prepended; headings demoted one level)

## 3.1 runs.js: logTail reads am logs' artifact texts — design

Card `d6a2e642`, a subtask of story `44b929b5` ("Attempt output from real am
logs"). Parent spec: `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
(below: **parent**). Work breakdown item 3 (parent L327-328) lists "`logTail`,
`runs-logs.py --repo-dir`, `RunStore` passing the root, and a real-data flow
test": this subtask is `logTail` only (`core/domain/runs.js:511-523`), plus the
hand-written logs replies in the store and flow tests that hid the defect.

### Goal

Run detail's output pane shows a real attempt's output. Real `am logs` data has
no `data.stdout` string; the output is in `data.artifacts.stdout.text` and
`data.artifacts.stderr.text` (parent L55-58). Today `logTail` reads
`data.stdout` / `data.stderr`, so on real data it returns `{text: "",
truncated: false}` (parent L86, L103) and the pane is empty even for a loaded
attempt (parent L113). After this subtask `logTail` of `logs-attempt.json`'s
data is that attempt's 19 stdout lines.

### Inherited constraints

| constraint | source |
|---|---|
| `am logs` data: `run_id, story_id, card, phase, attempt, status, exit_code, artifacts`; `artifacts.prompt`, `.result`, `.stdout`, `.stderr` each `{path, present, text}`, `text` null when absent; no `data.stdout` string | parent L55-58 |
| Decision 7: the output pane reads `artifacts.stdout.text`, then `artifacts.stderr.text`; a null `text` is no lines | parent L169-171 |
| Acceptance: `logTail(logs-attempt.json data)` is the 19 lines of `artifacts.stdout.text` (stderr `text` null: no lines), not truncated | parent L227-228 |
| Consumers of the wrong shape: `logTail` (`data.stdout`, `data.stderr` as strings); `RunStore` calls it; `tst_run_store.qml:925` and `tst_runs_flow.qml:201` hand-write `data.stdout` strings | parent L103, L113, L132 |
| Every unit test of code reading am output (`logTail`, `RunStore`'s logs handling) builds its input from `tests/fixtures/am/`; a hand-written am payload only for a synthetic edge case (garbage, a missing key, a value no capture contains), with a `synthetic:` comment; edits to a fixture in a test are on a fresh copy, labelled, and never change the shape | parent L257-267, card |
| QML loads fixtures with `tests/helpers/amFixtures.js` `load(name)` (fresh parse per call; needs `QML_XHR_ALLOW_FILE_READ=1`, set by `tests/run.sh`) | parent L269-274 |
| Not changed: `RunStore`'s public API; screen layouts; deterministic-phase logs (`am logs` without an attempt) | parent L306-317 |
| `docs/architecture.md` layering (`core/domain/*.js` pure JS, never throws); `tests/architecture` passes | card |
| Docstrings and comments state the contract only, no narrative | card |
| `bash tests/run.sh` green; tests first | card |

### Fixture facts this design relies on (checked 2026-10-05)

`tests/fixtures/am/logs-attempt.json` is `{ok: true, data}`; `data` has keys
`artifacts, attempt, card, exit_code, phase, run_id, status, story_id`.

- `data.artifacts.stdout`: `present: true`, `text` of 1531 characters, 19
  `\n`-terminated lines (`text.split("\n")` is 20 items, the last `""`). First
  line begins `Permission allow rule (/home/user/.claude/settings.json)`; last
  line is ``| plan_hash | `e8f781ba` |``.
- `data.artifacts.stderr`: `{path: null, present: false, text: null}`.
- `data.artifacts.prompt`: `present: true`, text begins `# Reviewer` (141
  lines). `data.artifacts.result`: `present: true`, one line of JSON.
- No capture has a non-null stderr text, a long text, or a missing artifact.

### Behavior

`logTail(data, maxLines)` returns `{text, truncated}`:

1. `max` is `Math.floor(maxLines)` when `maxLines` is a finite number `>= 1`,
   else 200 (unchanged).
2. The stdout lines are the lines of `data.artifacts.stdout.text`; the stderr
   lines are the lines of `data.artifacts.stderr.text`. Lines of a text are as
   today (`_linesOf`): one trailing `\n` is dropped, then split on `\n`; `""` is
   no lines.
3. Any of these is **no lines** for that stream, never an error: `data` not an
   object (or an array); `data.artifacts` missing or not an object; the
   stream's artifact missing or not an object; its `text` `null`, missing or
   not a string.
4. The artifact's `present` and `path` are not consulted: a string `text` is
   read whatever `present` says (am sets `text` null when absent).
5. The `prompt` and `result` artifacts and every other key of `data`, including
   a top-level `data.stdout` / `data.stderr` of the old guessed shape, are
   ignored.
6. Truncation per stream, unchanged: each stream keeps its last `max` lines;
   `truncated` is true when either stream had more than `max`. `text` is the
   kept stdout lines followed by the kept stderr lines, joined by `\n`.
7. Never throws; never mutates `data`.

#### Contract comment

The comment above `logTail` (`runs.js:511-513`) states: the last `maxLines`
lines of an `am logs` data object's `artifacts.stdout.text`, then the last
`maxLines` of its `artifacts.stderr.text`, as one string; a missing artifact or
a text that is not a string is no lines; `truncated` says lines were cut; a bad
`maxLines` is 200. No narrative.

#### Consumers

No production change outside `logTail`. Its only caller,
`RunStore.applyLogs` (`core/stores/RunStore.qml:420`,
`Runs.logTail(envelope.data, 200)`), already passes the envelope's `data`; with
a real reply `logsText` becomes the attempt's output. `docs/architecture.md:94`
and `:184` describe `logTail` generically and stay correct.

### Tests

All tiers run under `bash tests/run.sh` (`qmltestrunner`, offscreen, with
`QML_XHR_ALLOW_FILE_READ=1`).

#### 1. `tests/core/domain/tst_runs.qml` (TestCase `DomainRuns`)

Tier: QML domain unit. Why: `logTail` is pure domain JS and its existing test
lives here; the file already imports `amFixtures.js` as `F` (line 5). No store,
UI or process boundary.

A test helper `logsData(stdout, stderr)` returns `F.load("logs-attempt.json").data`
(a fresh copy) with `artifacts.stdout.text` / `artifacts.stderr.text` replaced
by the given values (a value left `undefined` keeps the fixture's), carrying a
`// synthetic:` comment that the texts are the test's and the shape is the
capture's.

- **`test_log_tail_of_a_real_attempt`** (new; fails first). `logTail(F.load(
  "logs-attempt.json").data, 200)`: `text` equals the fixture's
  `artifacts.stdout.text` without its trailing `\n`; `text.split("\n").length`
  is 19; first line begins `Permission allow rule`; last line is
  ``| plan_hash | `e8f781ba` |``; `truncated` is false; `text` does not contain
  `# Reviewer` (the prompt artifact is not shown). With `maxLines` 10 on the same
  data: the fixture's last 10 lines, `truncated` true.
- **`test_log_tail`** (existing, `tst_runs.qml:1481-1520`, rewritten on
  `logsData`; every case keeps its current expectation): under the limit
  (`"collecting...\n3 passed\n"` → `"collecting...\n3 passed"`, not
  truncated); exactly 200 lines not truncated; 5000 lines → `line 4800` …
  `line 4999`, truncated; stderr follows stdout (`"out\n"`, `"err1\nerr2\n"` →
  `"out\nerr1\nerr2"`); stderr only (`""`, `"boom"` → `"boom"`); a huge stderr
  is bounded (201 lines: `out`, then `line 100` …); a bad `maxLines` is 200.
- **`test_log_tail_reads_only_the_stream_artifacts`** (new; fails first; each
  input labelled `synthetic:`):
  - a fresh fixture copy with a top-level `data.stdout = "legacy\n"` and
    `data.stderr = "legacy\n"` added gives exactly the fixture's 19 lines (the
    old shape is ignored);
  - `{stdout: "x\n", stderr: "y\n"}` (old shape alone) gives `""`, not
    truncated;
  - a copy with `artifacts.stdout` deleted and stderr text `"boom\n"` gives
    `"boom"`;
  - a copy with stderr `present: false` and text `"late\n"` gives the 19
    stdout lines then `late` (`present` is not consulted);
  - the fixture data is unchanged by `logTail` (`JSON.stringify` before and
    after the call compare equal).
- **Garbage** (in `test_log_tail`, labelled `synthetic:`): each of `undefined,
  null, "x", 5, [], {}, {artifacts: null}, {artifacts: "x"}, {artifacts: []},
  {artifacts: {}}, {artifacts: {stdout: 5, stderr: {}}}, {artifacts: {stdout:
  {text: 5}, stderr: {text: []}}}, {artifacts: {stdout: {text: null}, stderr:
  {text: null}}}, {artifacts: {stdout: {text: ""}}}` gives `{text: "",
  truncated: false}` and does not throw.

#### 2. `tests/core/stores/tst_run_store.qml` (TestCase for `RunStore`)

Tier: QML store unit. Why: `RunStore.applyLogs` is the code that reads an `am
logs` reply; its tests must feed that reply in am's real shape, or they keep
hiding the defect (parent L132). `F` is already imported (line 9).

- **`logsReply(stdout, stderr)`** (`tst_run_store.qml:933-935`) returns
  `JSON.stringify(<fresh F.load("logs-attempt.json")>) + "\n"` with
  `data.artifacts.stdout.text = stdout` and, when `stderr` is given,
  `data.artifacts.stderr.text = stderr`; labelled `synthetic:` (the texts are
  the test's, the envelope is the capture's). Its 13 call sites
  (`:1014` … `:1166`) and their expectations are unchanged; they must still
  pass (e.g. `:1016` `"collecting...\n3 passed"`, `:1024-1031` 201 lines ending
  `boom`, truncated).
- **`test_a_real_logs_reply_shows_the_attempts_output`** (new; fails first):
  set up like `test_an_ok_logs_reply_sets_text_truncation_and_time`
  (`:1011-1014`, `opened()` then `reply(store.logsRunner.current, …, 0)`);
  reply with the unmodified `F.load("logs-attempt.json")` envelope
  (`JSON.stringify(…) + "\n"`). `applyLogs` does not check the reply's
  `run_id` / `card` against the selection, so the capture's ids need no edit. `logsText`
  is the fixture's stdout text without its trailing newline (19 lines),
  `logsTruncated` false, `logsError` `""`, `logsLoading` false.

#### 3. `tests/ui/tst_runs_flow.qml` (TestCase `RunsFlow`)

Tier: QML UI flow. Why: it drives the panel end to end from a logs reply to the
`runOutputText` the user reads; its reply must be am's shape too (parent L132).

- Add `import "../helpers/amFixtures.js" as F` (the file has none).
- **`logsOk(text)`** (`tst_runs_flow.qml:201`) returns the fresh
  `logs-attempt.json` envelope with `data.artifacts.stdout.text = text`, as one
  JSON line; labelled `synthetic:`. Call sites `:215`, `:225`, `:245` and their
  expectations (`"3 passed"`, `""` after a project switch) are unchanged.

### Out of scope

- `core/backend/runs/runs-logs.py` taking the project root and passing
  `--repo-dir` (3.2, `f7473bf0`); `RunStore` passing the root to it (3.3,
  `27704601`); the real-data flow test of the whole chain,
  `tests/ui/tst_runs_real_data.qml` (3.4, `c73f0325`).
- Any change to `RunStore.qml`, `RunDetailScreen`, the 200-line limit, line
  splitting (`\r\n`), or showing the `prompt` / `result` artifacts.
- Deterministic-phase logs (parent L316).
- `docs/architecture.md` (work breakdown item 5, parent L331).
- Python tests of `runs-logs.py` (`test_runs_logs.py`): already fixture-based.

---

## File Structure

| file | change |
|---|---|
| `core/domain/runs.js:511-523` | `logTail` reads `data.artifacts.stdout.text` / `.stderr.text`; contract comment restated |
| `tests/core/domain/tst_runs.qml:1475-1520` | `logsData` helper; `test_log_tail` rebuilt on the fixture with the extended garbage list; new `test_log_tail_of_a_real_attempt`, `test_log_tail_reads_only_the_stream_artifacts` |
| `tests/core/stores/tst_run_store.qml:933-935` | `logsReply` builds the reply from `logs-attempt.json`; new `test_a_real_logs_reply_shows_the_attempts_output` |
| `tests/ui/tst_runs_flow.qml:8`, `:201` | import `amFixtures.js` as `F`; `logsOk` builds the reply from `logs-attempt.json` |

One task: the domain change and the three test files' replies all describe one contract (am's `artifacts` shape), and the store and flow helpers can only go red against the old `logTail`, so they are written in the same red phase.

## Task 1: `logTail` reads am's artifact texts

**Files:**
- Modify: `core/domain/runs.js:511-523`
- Test: `tests/core/domain/tst_runs.qml:1475-1520`
- Test: `tests/core/stores/tst_run_store.qml:933-935` and a new test after `test_an_ok_logs_reply_sets_text_truncation_and_time` (ends at `:1031`)
- Test: `tests/ui/tst_runs_flow.qml:8`, `:201`

**Interfaces:**
- Consumes: `F.load(name)` from `tests/helpers/amFixtures.js` (fresh parse; throws `Error("amFixtures: cannot load …")` when unreadable); `_isObject(v)` (`runs.js:168`, true for a non-null, non-array object); `_isFiniteNumber(v)` (`runs.js:171`); `_linesOf(text)` (`runs.js:505`, `[]` for `""` or a non-string, else the lines without one trailing `\n`).
- Produces: `Runs.logTail(data, maxLines) -> { text: string, truncated: bool }` — signature unchanged, `data` is now read as `am logs` data. Test helpers: `logsData(stdout, stderr)` in `tst_runs.qml`, `logsReply(stdout, stderr)` in `tst_run_store.qml`, `logsOk(text)` in `tst_runs_flow.qml` (names and call signatures of the latter two unchanged).

- [ ] **Step 1: Rebuild `test_log_tail` on the fixture**

In `tests/core/domain/tst_runs.qml`, replace lines 1475-1520 (from `function numbered(n, from) {` through the closing `}` of `test_log_tail`, the line before `function test_snapshot_age_text() {`) with:

```qml
  function numbered(n, from) {
    var out = []
    for (var i = 0; i < n; i++) out.push("line " + ((from || 0) + i))
    return out.join("\n") + "\n"
  }

  // A fresh logs-attempt.json `am logs` data object whose stdout and stderr
  // artifact texts are `stdout` and `stderr`; an undefined argument keeps the
  // fixture's text (stdout: 19 lines, stderr: null).
  function logsData(stdout, stderr) {
    var data = F.load("logs-attempt.json").data
    // synthetic: the texts are the test's; the shape is the capture's.
    if (stdout !== undefined) data.artifacts.stdout.text = stdout
    if (stderr !== undefined) data.artifacts.stderr.text = stderr
    return data
  }

  // The capture's stdout text as its 19 lines.
  function fixtureStdoutLines() {
    var text = F.load("logs-attempt.json").data.artifacts.stdout.text
    return text.slice(0, -1).split("\n")
  }

  function test_log_tail() {
    var under = Runs.logTail(logsData("collecting...\n3 passed\n"), 200)
    compare(under.text, "collecting...\n3 passed")
    compare(under.truncated, false)

    var exact = Runs.logTail(logsData(numbered(200)), 200)
    compare(exact.text.split("\n").length, 200)
    compare(exact.truncated, false, "exactly 200 lines is not cut")

    var big = Runs.logTail(logsData(numbered(5000), ""), 200)
    var lines = big.text.split("\n")
    compare(lines.length, 200)
    compare(lines[0], "line 4800")
    compare(lines[199], "line 4999")
    compare(big.truncated, true)

    var withErr = Runs.logTail(logsData("out\n", "err1\nerr2\n"), 200)
    compare(withErr.text, "out\nerr1\nerr2", "stderr follows stdout")
    compare(withErr.truncated, false)

    var errOnly = Runs.logTail(logsData("", "boom"), 200)
    compare(errOnly.text, "boom")

    // A huge stderr is bounded too.
    var hugeErr = Runs.logTail(logsData("out\n", numbered(300)), 200)
    var errLines = hugeErr.text.split("\n")
    compare(errLines.length, 201, "stdout, then the last 200 stderr lines")
    compare(errLines[0], "out")
    compare(errLines[1], "line 100")
    compare(hugeErr.truncated, true)

    compare(Runs.logTail(logsData(numbered(250)), undefined).text.split("\n").length, 200, "a bad maxLines is 200")

    var newlineOnly = Runs.logTail(logsData("\n"), 200)
    compare(newlineOnly.text, "", "a lone newline is no lines")
    compare(newlineOnly.truncated, false)

    // synthetic: garbage in place of an `am logs` data object.
    var bad = [undefined, null, "x", 5, [], {}, { artifacts: null }, { artifacts: "x" }, { artifacts: [] },
               { artifacts: {} }, { artifacts: { stdout: 5, stderr: {} } },
               { artifacts: { stdout: { text: 5 }, stderr: { text: [] } } },
               { artifacts: { stdout: { text: null }, stderr: { text: null } } },
               { artifacts: { stdout: { text: "" } } }]
    for (var i = 0; i < bad.length; i++) {
      var t = Runs.logTail(bad[i], 200)
      compare(t.text, "", "garbage " + i)
      compare(t.truncated, false, "garbage " + i)
    }
  }
```

- [ ] **Step 2: Add the real-attempt and stream-artifact tests**

In `tests/core/domain/tst_runs.qml`, directly after the closing `}` of `test_log_tail` (before `function test_snapshot_age_text() {`), add:

```qml
  function test_log_tail_of_a_real_attempt() {
    var data = F.load("logs-attempt.json").data
    var stdout = data.artifacts.stdout.text
    var tail = Runs.logTail(data, 200)
    compare(tail.text, stdout.slice(0, -1), "the stdout artifact without its trailing newline")
    var lines = tail.text.split("\n")
    compare(lines.length, 19)
    verify(lines[0].indexOf("Permission allow rule") === 0, lines[0])
    compare(lines[18], "| plan_hash | `e8f781ba` |")
    compare(tail.truncated, false)
    verify(tail.text.indexOf("# Reviewer") < 0, "the prompt artifact is not shown")

    var ten = Runs.logTail(F.load("logs-attempt.json").data, 10)
    compare(ten.text, lines.slice(9).join("\n"), "the last 10 of the 19 lines")
    compare(ten.truncated, true)
  }

  function test_log_tail_reads_only_the_stream_artifacts() {
    // synthetic: a top-level stdout/stderr of the old guessed shape added to a fresh copy.
    var legacy = F.load("logs-attempt.json").data
    legacy.stdout = "legacy\n"
    legacy.stderr = "legacy\n"
    compare(Runs.logTail(legacy, 200).text, fixtureStdoutLines().join("\n"), "the old shape is ignored")

    // synthetic: the old guessed shape alone.
    var old = Runs.logTail({ stdout: "x\n", stderr: "y\n" }, 200)
    compare(old.text, "")
    compare(old.truncated, false)

    // synthetic: a fresh copy with no stdout artifact and a stderr text.
    var noOut = logsData(undefined, "boom\n")
    delete noOut.artifacts.stdout
    compare(Runs.logTail(noOut, 200).text, "boom")

    // synthetic: a fresh copy whose stderr says present: false yet has a text.
    var late = logsData(undefined, "late\n")
    late.artifacts.stderr.present = false
    compare(Runs.logTail(late, 200).text, fixtureStdoutLines().concat(["late"]).join("\n"), "present is not consulted")

    var data = F.load("logs-attempt.json").data
    var before = JSON.stringify(data)
    Runs.logTail(data, 10)
    compare(JSON.stringify(data), before, "data is not mutated")
  }
```

- [ ] **Step 3: Rebuild `logsReply` and add the real-reply store test**

In `tests/core/stores/tst_run_store.qml`, replace lines 933-935:

```qml
  function logsReply(stdout, stderr) {
    return JSON.stringify({ ok: true, data: { stdout: stdout, stderr: stderr || "" } }) + "\n"
  }
```

with:

```qml
  // A fresh logs-attempt.json `am logs` reply, as one JSON line, whose stdout
  // artifact text is `stdout` and, when given, whose stderr artifact text is
  // `stderr` (else the capture's null).
  function logsReply(stdout, stderr) {
    var envelope = F.load("logs-attempt.json")
    // synthetic: the texts are the test's; the envelope is the capture's.
    envelope.data.artifacts.stdout.text = stdout
    if (stderr !== undefined) envelope.data.artifacts.stderr.text = stderr
    return JSON.stringify(envelope) + "\n"
  }
```

Then, directly after the closing `}` of `test_an_ok_logs_reply_sets_text_truncation_and_time` (the line after `compare(store.logsTruncated, true)` at `:1031`), add:

```qml
  function test_a_real_logs_reply_shows_the_attempts_output() {
    var store = opened(); if (!store) return
    var envelope = F.load("logs-attempt.json")
    reply(store.logsRunner.current, JSON.stringify(envelope) + "\n", 0)
    compare(store.logsText, envelope.data.artifacts.stdout.text.slice(0, -1), "the attempt's stdout")
    compare(store.logsText.split("\n").length, 19)
    compare(store.logsTruncated, false)
    compare(store.logsError, "")
    compare(store.logsLoading, false)
  }
```

The 13 existing `logsReply(...)` call sites (`:1014` … `:1166`) and their expectations are not edited.

- [ ] **Step 4: Rebuild `logsOk` in the flow test**

In `tests/ui/tst_runs_flow.qml`, after line 8 (`import "../helpers/find.js" as H`) add:

```qml
import "../helpers/amFixtures.js" as F
```

and replace line 201:

```qml
  function logsOk(text) { return JSON.stringify({ ok: true, data: { stdout: text, stderr: "" } }) + "\n" }
```

with:

```qml
  // A fresh logs-attempt.json `am logs` reply, as one JSON line, whose stdout
  // artifact text is `text`.
  function logsOk(text) {
    var envelope = F.load("logs-attempt.json")
    // synthetic: the text is the test's; the envelope is the capture's.
    envelope.data.artifacts.stdout.text = text
    return JSON.stringify(envelope) + "\n"
  }
```

Call sites `:215`, `:225`, `:245` (line numbers shift by +7 after this edit) and their expectations are not edited.

- [ ] **Step 5: Run the three test files to verify they fail**

Run: `bash tests/run.sh core/domain/tst_runs; bash tests/run.sh tst_run_store; bash tests/run.sh tst_runs_flow`
Expected: each prints `FAIL!` lines and a non-zero `failed` count, none print `TypeError`/`ReferenceError`/`amFixtures: cannot load`:
- `tst_runs`: `test_log_tail` fails at its first compare (`""` vs `"collecting...\n3 passed"`), `test_log_tail_of_a_real_attempt` fails (`""` vs the stdout text), `test_log_tail_reads_only_the_stream_artifacts` fails (`"legacy\nlegacy"` vs the 19 lines).
- `tst_run_store`: `test_a_real_logs_reply_shows_the_attempts_output` and the existing logs tests that compare a non-empty `logsText` (e.g. `test_an_ok_logs_reply_sets_text_truncation_and_time`: `""` vs `"collecting...\n3 passed"`) fail.
- `tst_runs_flow`: `test_opening_a_run_shows_it_and_fetches_its_default_attempt` and `test_escape_returns_to_runs_and_clears_the_logs` fail (`""` vs `"3 passed"`).

- [ ] **Step 6: Implement `logTail` on the artifact texts**

In `core/domain/runs.js`, replace lines 511-523:

```js
// The last `maxLines` lines of an `am logs` data object's stdout, then the last
// `maxLines` of its stderr, as one string. `truncated` says lines were cut, so
// the pane can say "last 200 lines". A bad maxLines is 200.
function logTail(data, maxLines) {
  var max = _isFiniteNumber(maxLines) && maxLines >= 1 ? Math.floor(maxLines) : 200
  var out = _isObject(data) ? _linesOf(data.stdout) : []
  var err = _isObject(data) ? _linesOf(data.stderr) : []
  var truncated = out.length > max || err.length > max
  if (out.length > max) out = out.slice(out.length - max)
  if (err.length > max) err = err.slice(err.length - max)
  return { text: out.concat(err).join("\n"), truncated: truncated }
}
```

with:

```js
// The last `maxLines` lines of an `am logs` data object's
// artifacts.stdout.text, then the last `maxLines` of its artifacts.stderr.text,
// as one string. A missing artifact or a text that is not a string is no lines.
// `truncated` says lines were cut. A bad maxLines is 200.
function logTail(data, maxLines) {
  var max = _isFiniteNumber(maxLines) && maxLines >= 1 ? Math.floor(maxLines) : 200
  var artifacts = _isObject(data) && _isObject(data.artifacts) ? data.artifacts : {}
  var out = _isObject(artifacts.stdout) ? _linesOf(artifacts.stdout.text) : []
  var err = _isObject(artifacts.stderr) ? _linesOf(artifacts.stderr.text) : []
  var truncated = out.length > max || err.length > max
  if (out.length > max) out = out.slice(out.length - max)
  if (err.length > max) err = err.slice(err.length - max)
  return { text: out.concat(err).join("\n"), truncated: truncated }
}
```

- [ ] **Step 7: Run the three test files to verify they pass**

Run: `bash tests/run.sh core/domain/tst_runs && bash tests/run.sh tst_run_store && bash tests/run.sh tst_runs_flow`
Expected: each prints `Totals: N passed, 0 failed, …`, no `TypeError`/`ReferenceError` lines, exit 0.

- [ ] **Step 8: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest passes (including `tests/architecture`), every `tst_*.qml` prints `0 failed`, no `TypeError`/`ReferenceError` lines, exit 0.

- [ ] **Step 9: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml tests/core/stores/tst_run_store.qml tests/ui/tst_runs_flow.qml
git commit -m "feat(runs): logTail reads am logs' artifact texts"
```

---

## Self-Review

- **Spec coverage:** Behavior 1 (`max`) → Step 6 unchanged line, pinned by the bad-`maxLines` case (Step 1). Behavior 2 (artifact texts, `_linesOf`) → Step 6; Steps 1-2. Behavior 3 (no lines for each bad level) → Step 6 `_isObject` guards; Step 1 garbage list (all 14 spec inputs) and Step 2 deleted stdout artifact. Behavior 4 (`present`/`path` ignored) → Step 2 `present: false` case. Behavior 5 (prompt/result/legacy ignored) → Step 2 legacy cases, Step 2 `# Reviewer` check. Behavior 6 (per-stream truncation) → Step 1 big/hugeErr, Step 2 `maxLines` 10. Behavior 7 (never throws, never mutates) → Step 1 garbage, Step 2 `JSON.stringify` check. Contract comment → Step 6. Store tests (`logsReply`, new real-reply test, 13 call sites unchanged) → Step 3. Flow test (import, `logsOk`) → Step 4. Full suite → Step 8.
- **Fixture facts re-checked** (2026-10-05): `logs-attempt.json` keys `data, ok`; stdout text starts `Permission allow rule`, ends `\n`, 19 lines, last ``| plan_hash | `e8f781ba` |``, no `# Reviewer`, no `\r`; stderr `{path: null, present: false, text: null}`.
- **Placeholders:** none. **Types:** `logTail(data, maxLines) -> {text, truncated}` unchanged; `logsReply(stdout, stderr)` / `logsOk(text)` keep their call signatures; `logsData` and `fixtureStdoutLines` are defined in Step 1 before use in Step 2.
<!-- task-pipeline: validated -->
