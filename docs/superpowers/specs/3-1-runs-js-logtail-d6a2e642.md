# 3.1 runs.js: logTail reads am logs' artifact texts — design

Card `d6a2e642`, a subtask of story `44b929b5` ("Attempt output from real am
logs"). Parent spec: `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
(below: **parent**). Work breakdown item 3 (parent L327-328) lists "`logTail`,
`runs-logs.py --repo-dir`, `RunStore` passing the root, and a real-data flow
test": this subtask is `logTail` only (`core/domain/runs.js:511-523`), plus the
hand-written logs replies in the store and flow tests that hid the defect.

## Goal

Run detail's output pane shows a real attempt's output. Real `am logs` data has
no `data.stdout` string; the output is in `data.artifacts.stdout.text` and
`data.artifacts.stderr.text` (parent L55-58). Today `logTail` reads
`data.stdout` / `data.stderr`, so on real data it returns `{text: "",
truncated: false}` (parent L86, L103) and the pane is empty even for a loaded
attempt (parent L113). After this subtask `logTail` of `logs-attempt.json`'s
data is that attempt's 19 stdout lines.

## Inherited constraints

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

## Fixture facts this design relies on (checked 2026-10-05)

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

## Behavior

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

### Contract comment

The comment above `logTail` (`runs.js:511-513`) states: the last `maxLines`
lines of an `am logs` data object's `artifacts.stdout.text`, then the last
`maxLines` of its `artifacts.stderr.text`, as one string; a missing artifact or
a text that is not a string is no lines; `truncated` says lines were cut; a bad
`maxLines` is 200. No narrative.

### Consumers

No production change outside `logTail`. Its only caller,
`RunStore.applyLogs` (`core/stores/RunStore.qml:420`,
`Runs.logTail(envelope.data, 200)`), already passes the envelope's `data`; with
a real reply `logsText` becomes the attempt's output. `docs/architecture.md:94`
and `:184` describe `logTail` generically and stay correct.

## Tests

All tiers run under `bash tests/run.sh` (`qmltestrunner`, offscreen, with
`QML_XHR_ALLOW_FILE_READ=1`).

### 1. `tests/core/domain/tst_runs.qml` (TestCase `DomainRuns`)

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

### 2. `tests/core/stores/tst_run_store.qml` (TestCase for `RunStore`)

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

### 3. `tests/ui/tst_runs_flow.qml` (TestCase `RunsFlow`)

Tier: QML UI flow. Why: it drives the panel end to end from a logs reply to the
`runOutputText` the user reads; its reply must be am's shape too (parent L132).

- Add `import "../helpers/amFixtures.js" as F` (the file has none).
- **`logsOk(text)`** (`tst_runs_flow.qml:201`) returns the fresh
  `logs-attempt.json` envelope with `data.artifacts.stdout.text = text`, as one
  JSON line; labelled `synthetic:`. Call sites `:215`, `:225`, `:245` and their
  expectations (`"3 passed"`, `""` after a project switch) are unchanged.

## Out of scope

- `core/backend/runs/runs-logs.py` taking the project root and passing
  `--repo-dir` (3.2, `f7473bf0`); `RunStore` passing the root to it (3.3,
  `27704601`); the real-data flow test of the whole chain,
  `tests/ui/tst_runs_real_data.qml` (3.4, `c73f0325`).
- Any change to `RunStore.qml`, `RunDetailScreen`, the 200-line limit, line
  splitting (`\r\n`), or showing the `prompt` / `result` artifacts.
- Deterministic-phase logs (parent L316).
- `docs/architecture.md` (work breakdown item 5, parent L331).
- Python tests of `runs-logs.py` (`test_runs_logs.py`): already fixture-based.
