# 1.2 `runs-logs-follow.py`: one attempt's stdout as a stream — spec

Card `5a56adf9-7918-45f0-a6c8-6c405c5e644f`, subtask of story `85b0f971-5e0f-488e-a8e5-a71e3663f314`
(Live run output), blocked by card `3762705f` (1.1, the `am logs --follow` contract test and its
recorded fixtures, done). Parent design: `docs/superpowers/specs/2026-10-05-live-output-design.md`
(below: **LO**).

## Purpose

A new long-lived backend helper, `core/backend/runs/runs-logs-follow.py`, that runs
`am logs ... --follow` for one attempt and turns its stdout into a clean JSON-lines stream the
future `RunOutputStore` (a sibling card) can read line by line. This card delivers the helper, its
hermetic tests and one paragraph of `docs/architecture.md`. Nothing in `core/domain`,
`core/stores` or `ui/` changes.

## Inherited constraints

| constraint | source |
|---|---|
| Invocation `runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT [OFFSET]`, positional like `runs-logs.py`. | LO §Backend, lines 114-115 |
| ATTEMPT `0` omits `--attempt`; OFFSET omitted or `0` omits `--since-offset`. | LO lines 115-116 |
| am argv: `am logs RUN CARD --phase PHASE [--attempt N] --follow [--since-offset B] --repo-dir REPO`, an argv list (no shell), stdin `/dev/null`. | LO lines 116-117 |
| Long-lived; one JSON object per stdout line, flushed per line. | LO lines 117-118 |
| am's hello, chunk and end lines re-emitted as parsed JSON objects (compact), never altered; a line that is not a JSON object is skipped and counted. | LO lines 120-121 |
| am's refusal envelope, unchanged, as the only line. | LO line 122 |
| Own last line on failure `{"ok":false,"error":{"type","message"}}`: `AmMissing`, `FollowUnsupported` (am exited 2 before printing anything), `SchemaMismatch` (hello `schema` not 1 or 2; am stopped), `StreamError` (non-zero exit after the hello; message = am's stderr line), `HelperError` (anything else), `Usage` (exit 2). | LO lines 123-127 |
| SIGTERM terminates am, waits up to 2 s, kills it, exits 0 printing nothing more. Exit 0 on every other path except Usage. | LO lines 128-129 |
| Only the documented `am logs` command is used; no file under am's data dir is opened; the hello's `path` is never read or shown by the plugin (it is forwarded untouched, never opened). | LO lines 52-53, 131 |
| am stream shape: hello `{"event":"logs","offset":B,"path":…,"schema":1}`; chunks `{"offset":O,"text":T}`; end `{"event":"end","status":S}` then exit 0. Keys are additive; unknown keys are ignored. | LO lines 52-61, 70-71 |
| A refusal is ONE envelope, exit 3, before any stream line; only a refusal has an `ok` key; only a stream starts with `"event":"logs"`. | LO lines 62-64 |
| An error after the hello prints `am logs: <message>` on stderr, exit 3. Closing the pipe or SIGINT ends the stream with exit 0. | LO lines 65-66 |
| An `am` without `--follow` exits 2 with a usage error on stderr and nothing on stdout. | LO line 72 |
| Tests: `tests/core/backend/runs/test_runs_logs_follow.py` (fake `am`): argv with and without `--attempt` and `--since-offset`, `--repo-dir`, line passthrough, refusal passthrough, each error type, SIGTERM stops am and exits 0. | LO §Testing, lines 242-244 |
| `core/backend` uses the stdlib and `core/backend/common` only; no second `def emit(` (or other `DUPLICATED_PY` needle) anywhere. | `tests/architecture/test_layers.py:206-241` |
| Docstrings and comments state the contract only, no narrative; `bash tests/run.sh` green; `tests/architecture` passes; TDD (tests first). | card description |

## Behaviour

### B1. Arguments (Usage)

- Exactly 5 or 6 arguments: `REPO RUN CARD PHASE ATTEMPT [OFFSET]`. Any other count is `Usage`.
- ATTEMPT and OFFSET must each be one or more ASCII decimal digits (`isascii() and isdigit()`);
  anything else (`-1`, `1.5`, `x`, `""`, `٣`) is `Usage`. Their integer value is what reaches am, as
  decimal text without leading zeros (`007` → `7`; `00` → `0`, i.e. the flag is omitted).
- REPO, RUN, CARD and PHASE go to am verbatim; am refuses bad values itself (its refusal is
  passed through, B4).
- `Usage` prints `{"ok":false,"error":{"type":"Usage","message":"usage: runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT [OFFSET]"}}`
  and exits **2**. am is neither looked up nor started.

### B2. am argv

am is found with `shutil.which("am")` and started as
`[am, "logs", RUN, CARD, "--phase", PHASE, *A, "--follow", *O, "--repo-dir", REPO]`, with
`A = ["--attempt", N]` when ATTEMPT ≠ 0 else `[]`, and `O = ["--since-offset", B]` when OFFSET is
given and ≠ 0 else `[]`. stdin is `/dev/null`; stdout and stderr are pipes; no shell. stderr is
read concurrently so a chatty am never blocks.

Not on PATH → `AmMissing` line (`"am is not installed."`), exit 0.

### B3. Stream passthrough

Each line of am's stdout is parsed as JSON:

- Not JSON, or JSON that is not an object (array, string, number, `null`): printed nothing, and
  the skip is counted. When the helper ends with a non-zero count it writes
  `runs-logs-follow: skipped N non-JSON lines` (one line) to its **stderr**; stdout is unaffected.
- A JSON object whose `event` is `"logs"` is a hello: its `schema` is checked (B5); when it passes,
  it is printed.
- Any other JSON object without an `ok` key (a chunk, the end line, an object of a kind this helper
  does not know) is printed.
- Printing = `json.dumps(obj, separators=(",", ":"))` of the parsed object followed by a newline,
  then `sys.stdout.flush()` at once. Key order and every value are preserved, so the printed line
  parses equal to am's line. A line is readable by the consumer while am is still running.
- When am's stdout ends and am exits 0 (with or without an end line: a closed pipe or SIGINT on
  am's side), nothing more is printed; exit 0.

### B4. Refusal passthrough

A JSON object with an `ok` key, read before any line was printed, is am's refusal: it is printed
(compact, as in B3) as the helper's **only** line. Every later stdout line is ignored, am's exit
code (normally 3) adds no line, exit 0. An `ok`-keyed object read after a line was printed is not a
refusal: it is skipped and counted like a non-object.

### B5. SchemaMismatch

A hello whose `schema` is not the integer 1 or 2 (`type(schema) is int`, so `true`, `1.0`, `"1"`,
`3`, `0` and a missing key all fail) is not printed. The helper stops am (terminate, wait up to
2 s, kill, reap) and prints `SchemaMismatch` with message
`am logs speaks schema <json of the value>; this helper reads schema 1 or 2.`
(`null` for a missing key), exit 0. Lines printed before it stay printed.

### B6. How am ended (after its stdout closed, when no refusal and no SchemaMismatch)

Let `printed` be whether the helper printed any line and `stderr` am's whole stderr, its last
non-empty line stripped as `msg`.

| am exit | condition | last line |
|---|---|---|
| 0 | any | none |
| 2 | nothing at all on am's stdout (not even a skipped line) | `FollowUnsupported`, message `am logs cannot follow (exit 2): <msg>`, or `am logs cannot follow (exit 2).` when stderr is empty |
| ≠ 0 | a hello was printed | `StreamError`, message `msg`, or `am logs exited N.` when stderr is empty |
| ≠ 0 | any other case (exit 3 with no refusal, exit 2 after output, exit 1 before the hello, ...) | `HelperError`, message `msg`, or `am logs exited N.` when stderr is empty |

Exit 0 in every row.

### B7. Signals, closed stdout, unexpected failure

- SIGTERM or SIGINT: am is terminated, waited for up to 2 s, then killed if still alive, and
  reaped; the helper prints nothing more and exits 0. stdout is pointed at `/dev/null` before exit
  so the interpreter's final flush cannot raise.
- A closed stdout (`BrokenPipeError` while printing): same — am stopped, exit 0, no traceback.
- Any other exception (am cannot be started, an unexpected error): `HelperError` with message
  `The log follow failed: <reason>` (reason = `str(e)` or the exception's class name), exit 0; am,
  if started, is stopped first.
- On every path, am is no longer running when the helper exits.

### B8. Shape of the module

Same structure as `core/backend/runs/runs-watch.py` (closest helper; reuse its idioms, not its
code): a module docstring stating the contract above, and a compact printer named something
other than `emit` (e.g. `say`, doing `print(json.dumps(obj, separators=(",", ":")))` then a
flush). `common.json_line.emit` is not used, since its `json.dumps` is not compact, and a second
`def emit(` fails `tests/architecture/test_layers.py:234`. Stdlib only. `common/json_line.py` is
not modified.

### B9. Documentation

`docs/architecture.md` line 201 (the `core/backend/runs/` paragraph) gains one sentence describing
`runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT [OFFSET]`: its am argv rule (ATTEMPT 0 / OFFSET
absent or 0 omit the flags), compact per-line passthrough with non-objects skipped, the refusal as
the only line, the error types, Usage exit 2 / exit 0 otherwise, SIGTERM stopping am, and that no
store runs it yet. README.md is not changed (the plugin does not run the helper until the store
card).

## Tests

All in `tests/core/backend/runs/test_runs_logs_follow.py`, **tier: backend helper (pytest,
hermetic)** — the helper's contract is process-level (argv, stdout lines, exit code, signals), so it
is tested by running the script as a subprocess against a fake `am` on a temp PATH, exactly like
`tests/core/backend/runs/test_runs_watch.py` (copy its `FAKE_AM`/`world`/`env_for`/`fixture`
pattern; temp HOME and XDG_*; PATH `<bin>:/usr/bin:/bin`). The real `am` is never called. The fake
am logs argv to `calls.log` and its pid to `pid`, replays `script.json` steps (`line`, `raw`,
`sleep`, plus a new `ignore_term` step that sets SIGTERM to ignored), then writes `stderr` and exits
with `exit`. JSON lines come from `tests/fixtures/am/logs-follow-agent.jsonl`,
`logs-follow-step.jsonl` and `logs-follow-refusal.json`; any line no fixture holds is built in a
helper whose docstring labels it `synthetic:`.

| # | test | proves |
|---|---|---|
| T1 | argv, parametrized over ATTEMPT ∈ {`0`, `2`} × OFFSET ∈ {absent, `0`, `512`}: `calls.log` equals the exact list (flags present/absent, `--follow` before `--since-offset`, `--repo-dir REPO` last) | B2 |
| T2 | leading zeros: ATTEMPT `003`, OFFSET `0040` → `--attempt 3 --since-offset 40`; ATTEMPT `00` omits `--attempt` | B1 |
| T3 | Usage, parametrized: 4 args, 7 args, ATTEMPT `x`, `-1`, `1.5`, `""`, `٣`, OFFSET `-5`, `abc`: exit 2, the one Usage line, no `calls.log` (am not started) | B1 |
| T4 | Usage even when am is absent from PATH (Usage wins, am not looked up) | B1 |
| T5 | agent fixture passthrough: stdout lines parse equal to the three fixture lines, in order, each printed compact (no `": "` / `", "`), exit 0 | B3 |
| T6 | step fixture passthrough (ATTEMPT 0) likewise | B3 |
| T7 | non-JSON skipped: raw `not json`, `[1,2]`, `"s"`, `null` interleaved with fixture lines → only the fixture lines printed; stderr contains `skipped 4 non-JSON lines` | B3 |
| T8 | unknown object kept: a synthetic chunk with an extra key and a synthetic `{"event":"note"}` are printed unchanged | B3 |
| T9 | per-line flush: hello then chunk, then fake am sleeps 30 s; the test reads two lines from the live helper within 5 s, then SIGTERMs it | B3 |
| T10 | am exit 0 without an end line: hello + chunk, exit 0 → just those two lines, exit 0 | B3, B6 |
| T11 | refusal passthrough: fixture refusal + exit 3 (and stderr text) → exactly one line equal to the fixture, exit 0 | B4 |
| T12 | refusal is the only line: refusal followed by a synthetic chunk line → still exactly one line | B4 |
| T13 | an `ok` object after the hello is skipped (not printed, counted) | B4 |
| T14 | AmMissing: PATH without am → one `AmMissing` line, exit 0 | B2 |
| T15 | FollowUnsupported: no stdout, stderr `usage: am logs ... error: unrecognized arguments: --follow`, exit 2 → `FollowUnsupported` whose message contains that line, exit 0 | B6 |
| T16 | exit 2 after a skipped raw line is HelperError, not FollowUnsupported | B6 |
| T17 | SchemaMismatch, parametrized over schema `3`, `0`, `true`, `"1"`, `1.0`, missing: no hello printed, one `SchemaMismatch` line naming the value, exit 0; with the fake am set to sleep 30 s after the hello, its pid is gone when the helper exits (am stopped) and the helper exits within 5 s | B5 |
| T18 | schema 2 accepted: synthetic schema-2 copy of the agent hello is printed and the stream continues to the end line | B5 |
| T19 | StreamError: hello + chunk, stderr `am logs: run left the projection\n`, exit 3 → hello, chunk, then `StreamError` with message `am logs: run left the projection`, exit 0 | B6 |
| T20 | StreamError with empty stderr → message `am logs exited 3.` | B6 |
| T21 | HelperError, parametrized: exit 3 with no output; exit 1 with stderr `boom` before any line → `HelperError` (message `boom` / `am logs exited 3.`), exit 0 | B6 |
| T22 | HelperError on an unexpected failure: `am` on PATH is a non-executable-by-interpreter file (e.g. an exec bit set on a file whose shebang names a missing interpreter) → one `HelperError` line starting `The log follow failed:`, exit 0, no traceback on stderr | B7 |
| T23 | SIGTERM stops am: fake am prints hello then sleeps 30 s; after reading the hello, SIGTERM the helper → exit 0, no further stdout, fake am pid gone | B7 |
| T24 | SIGTERM kills an am that ignores SIGTERM: `ignore_term` step, hello, sleep 30 s → helper exits 0 within 5 s and the fake am pid is gone | B7 |
| T25 | closed stdout: the reader closes the helper's stdout after the hello while am keeps printing chunks → helper exits 0, no traceback on stderr, fake am pid gone | B7 |

`tests/architecture` (tier: architecture, unchanged) must stay green: it proves the layering and
the single `def emit(`.

## Out of scope

- `runs-logs.py` changes (REPO-first and the ATTEMPT-0 step rule; LO lines 133-135): sibling card.
- `core/domain/logStream.js`, `core/stores/RunOutputStore.qml`, `Runs.isLiveSelection`, step rows,
  and every UI change (LO lines 137-212): sibling cards.
- Retry/resume policy (`nextOffset`, 3 tries; LO line 224): the store's job; the helper only
  passes OFFSET through.
- Any change to `core/backend/common/` or README.md; any file outside `core/backend/runs/`,
  `tests/core/backend/runs/` and the one `docs/architecture.md` sentence.
- Contract tests against the real `am` (card 1.1, done).

## Hand-off to the planner

Plan in the writing-plans format (`docs/superpowers/plans/`). Suggested tasks, each with its own
test cycle: (1) Usage + argv + AmMissing (T1-T4, T14) creating the script skeleton and the test
module with the fake am; (2) passthrough, skip count, refusal, exit-0 ends (T5-T13); (3) error
typing after exit and SchemaMismatch with am stopped (T15-T22); (4) signals and closed stdout
(T23-T25); (5) the `docs/architecture.md` sentence. Every timing-dependent test bounds its wait
with a `timeout` and asserts on the recorded fake-am pid, never on process names; never `pkill`.

---

# 1.2 `runs-logs-follow.py` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A long-lived stdlib helper `core/backend/runs/runs-logs-follow.py` that runs `am logs ... --follow` for one attempt and re-prints its stdout as compact, per-line-flushed JSON objects, with typed failure lines, signal-safe shutdown, hermetic tests and one `docs/architecture.md` sentence.

**Architecture:** One script modelled on `core/backend/runs/runs-watch.py` (same idioms: `spawn`/`collect`/`stop`/`finish`/`main`/`guarded`/`quiet_exit`, a `Stop` exception raised from the signal handler). am's stdout is read line by line in the main thread (no debounce, so no queue); am's stderr is read whole in a daemon thread. A small `Seen` record tracks what was read and printed, which decides the last line after am exits. Tests run the script as a subprocess against a fake `am` on a temp PATH, copying `tests/core/backend/runs/test_runs_watch.py`'s pattern.

**Tech Stack:** Python 3.13 stdlib only (`json`, `os`, `shutil`, `signal`, `subprocess`, `sys`, `threading`); pytest (run as `uv run --with pytest python3 -m pytest ...`, because the system python3 has no pytest).

**Spec:** `docs/superpowers/specs/1-2-runs-logs-follow-py-5a56adf9.md` (the copy above this plan). Parent design: `docs/superpowers/specs/2026-10-05-live-output-design.md`.

## Global Constraints

- Invocation `runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT [OFFSET]`, positional.
- am argv: `am logs RUN CARD --phase PHASE [--attempt N] --follow [--since-offset B] --repo-dir REPO`, an argv list (no shell), stdin `/dev/null`.
- ATTEMPT `0` omits `--attempt`; OFFSET omitted or `0` omits `--since-offset`.
- Usage message, exactly: `usage: runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT [OFFSET]`; Usage exits **2**; every other path exits **0**.
- Failure line shape `{"ok":false,"error":{"type","message"}}`; types `AmMissing`, `FollowUnsupported`, `SchemaMismatch`, `StreamError`, `HelperError`, `Usage`.
- Exact messages: `am is not installed.`; `am logs cannot follow (exit 2): <msg>` / `am logs cannot follow (exit 2).`; `am logs speaks schema <json>; this helper reads schema 1 or 2.`; `am logs exited N.`; `The log follow failed: <reason>`.
- Skip count goes to the helper's **stderr** as `runs-logs-follow: skipped N non-JSON lines`.
- Printing is `json.dumps(obj, separators=(",", ":"))` + newline + `sys.stdout.flush()`.
- SIGTERM/SIGINT/closed stdout: terminate am, wait up to 2 s, kill, reap; nothing more printed; exit 0.
- `core/backend` uses the stdlib and `core/backend/common` only (this helper uses the stdlib only); `common/json_line.py` is not used or modified; the file must not contain the text `def emit(` (nor any other `DUPLICATED_PY` needle from `tests/architecture/test_layers.py:206`), not even in a comment.
- No file under am's data dir is opened; the hello's `path` is forwarded untouched, never opened.
- Docstrings and comments state the contract only, no narrative. TDD: tests first.
- Only files touched: `core/backend/runs/runs-logs-follow.py`, `tests/core/backend/runs/test_runs_logs_follow.py`, `docs/architecture.md` (one sentence). README.md and `core/backend/common/` are not changed.
- Tests never call the real `am`, never `pkill`/`killall`; every timing-dependent wait is bounded and asserts on the recorded fake-am pid.

## Review Focus

1. **RUN/CARD/PHASE/REPO holding spaces or shell metacharacters** (`/a repo/$(x)`, `run;echo pwned`, `` card`id` ``, `phase with space`): each must reach am as exactly one argv item, unchanged. Pinned by `test_argv_values_reach_am_verbatim` (Task 1).
2. **Non-ASCII chunk text** (accented letters, CJK, symbols written by am as raw UTF-8): must pass through and parse equal, never crash or be skipped. Pinned by `test_non_ascii_text_passes_through` (Task 2).
3. **A very large chunk line** (1 MB of agent output on one line): must come through whole as one printed line. Pinned by `test_long_chunk_passes_through_whole` (Task 2).
4. **A chatty am stderr** (hundreds of KB of warnings before exit): must never deadlock the helper, and the last stderr line still becomes the StreamError message. Pinned by `test_chatty_stderr_never_blocks` (Task 3).
5. **A second SIGTERM arriving while the helper is already stopping an am that ignores SIGTERM** (a store tearing down twice): the helper must still kill and reap am, exit 0, no traceback. Pinned by `test_second_sigterm_while_stopping_still_stops_am` (Task 4).

## File map

| file | responsibility |
|---|---|
| `core/backend/runs/runs-logs-follow.py` (create) | the helper: argv parsing, am spawn, stream passthrough, last-line typing, signals |
| `tests/core/backend/runs/test_runs_logs_follow.py` (create) | hermetic process-level tests with a fake `am` |
| `docs/architecture.md:201` (modify) | one sentence in the `core/backend/runs/` paragraph |

Test command used throughout (from the worktree root):
`timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_logs_follow.py -q`

---

### Task 1: Script skeleton — Usage, am argv, AmMissing (T1-T4, T14)

**Files:**
- Create: `core/backend/runs/runs-logs-follow.py`
- Create: `tests/core/backend/runs/test_runs_logs_follow.py`

**Interfaces:**
- Consumes: nothing.
- Produces (in `runs-logs-follow.py`, used by Tasks 2-4): `USAGE: str`; `say(payload, code=0) -> int` (prints one compact JSON line, flushes, returns `code`); `failure(kind, message, code=0) -> int`; `number(text) -> int | None`; `parse_args(argv) -> (repo, run, card, phase, attempt:int, offset:int) | None`; `command(am, repo, run, card, phase, attempt, offset) -> list[str]`; `spawn(argv) -> subprocess.Popen` (text, utf-8, errors="replace", stdin DEVNULL, stdout/stderr PIPE); `main(argv) -> int`.
- Produces (in the test module, used by Tasks 2-4): `SCRIPT`, `USAGE`, `REPO`, `RUN`, `CARD`, `PHASE`, `ARGS`, `MISSING`, `IGNORE_TERM`, `FAKE_AM`; fixtures/helpers `world`, `env_for(world, **extra)`, `write_exec(path, text)`, `lines_of(name) -> list[dict]`, `capture_text(name) -> list[str]`, `agent() -> [hello, chunk, end]`, `step_capture() -> [hello, chunk, end]`, `refusal() -> dict`, `compact(obj) -> str`, `edited(line, **edits) -> dict`, `step(line)`, `raw(text)`, `pause(seconds)`, `set_script(world, steps, exit=0, stderr="")`, `run_helper(world, args=ARGS, timeout=30, **extra) -> (code, lines, stderr, out_lines)`, `error(kind, message) -> dict`, `calls(world) -> list[list[str]]`, `start_helper(world, args=ARGS) -> Popen`, `am_pid(world) -> int`, `assert_gone(pid, within=5.0)`, `kill_am(world)`, `read_lines(p, n, within=5.0) -> list[dict]`, `reap(p)`.

- [ ] **Step 1: Write the test module with its fake am and the Task 1 tests**

Create `tests/core/backend/runs/test_runs_logs_follow.py`:

```python
"""runs-logs-follow.py: one attempt's `am logs --follow` stdout as a stream.

Hermetic: a fake `am` on a temp PATH replays FAKE_AM_DIR/script.json: a list of
steps (a JSON line, raw text, a sleep, or ignore_term, which makes it ignore
SIGTERM), then a chosen stderr text and exit code. The JSON lines are copies of
the committed captures tests/fixtures/am/logs-follow-agent.jsonl,
logs-follow-step.jsonl and logs-follow-refusal.json; a line no capture holds is
built by a helper labelled `synthetic:`. The fake am logs its argv to calls.log
and its pid to pid. HOME and XDG_* are temp. The real `am` and real data are
never touched.
"""
import json
import os
import signal
import stat
import subprocess
import sys
import threading
import time

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "..")
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "runs-logs-follow.py")
USAGE = "usage: runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT [OFFSET]"
FIXTURES = os.path.join(ROOT, "tests", "fixtures", "am")

# The run, card and phase of the agent capture (its hello's path); REPO never
# has to exist.
REPO = "/some/repo"
RUN = "20261009T185646Z-b772d3d6"
CARD = "f9027ac2-537c-4066-a83b-827a15d45c0e"
PHASE = "review"
ARGS = [REPO, RUN, CARD, PHASE, "1"]
MISSING = object()
IGNORE_TERM = {"ignore_term": True}

FAKE_AM = r'''#!/usr/bin/env python3
import json, os, signal, sys, time
d = os.environ["FAKE_AM_DIR"]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\n")
with open(os.path.join(d, "pid"), "w") as f:
    f.write(str(os.getpid()))
with open(os.path.join(d, "script.json")) as f:
    script = json.load(f)
out = sys.stdout.buffer
for step in script["steps"]:
    if "sleep" in step:
        time.sleep(step["sleep"])
        continue
    if "ignore_term" in step:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        continue
    if "raw" in step:
        text = step["raw"]
    else:
        text = json.dumps(step["line"], separators=(",", ":"))
    out.write((text + "\n").encode("utf-8"))
    out.flush()
sys.stderr.write(script.get("stderr", ""))
sys.stderr.flush()
sys.exit(script.get("exit", 0))
'''


def capture_text(name):
    """The raw lines of tests/fixtures/am/<name>."""
    with open(os.path.join(FIXTURES, name)) as f:
        return [line for line in f.read().splitlines() if line]


def lines_of(name):
    """A fresh parse of each line of tests/fixtures/am/<name>."""
    return [json.loads(line) for line in capture_text(name)]


def agent():
    """The agent capture: [hello, chunk, end] of review attempt 1."""
    return lines_of("logs-follow-agent.jsonl")


def step_capture():
    """The step capture: [hello, chunk, end] of a verify step (ATTEMPT 0)."""
    return lines_of("logs-follow-step.jsonl")


def refusal():
    """The captured refusal envelope (UnknownAttemptError)."""
    return lines_of("logs-follow-refusal.json")[0]


def compact(obj):
    return json.dumps(obj, separators=(",", ":"))


def edited(line, **edits):
    """synthetic: a copy of `line` with each of `edits` set (appended when new,
    so key order is kept), MISSING drops the key."""
    copy = dict(line)
    for key, value in edits.items():
        if value is MISSING:
            copy.pop(key, None)
        else:
            copy[key] = value
    return copy


def step(line):
    return {"line": line}


def raw(text):
    return {"raw": text}


def pause(seconds):
    return {"sleep": seconds}


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am, its script dir and a temp HOME."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "am", FAKE_AM)
    amdir = tmp_path / "am"
    amdir.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    return {"tmp": tmp_path, "bin": bindir, "am": amdir, "home": home}


def env_for(world, **extra):
    e = {
        "PATH": str(world["bin"]) + os.pathsep + "/usr/bin" + os.pathsep + "/bin",
        "HOME": str(world["home"]),
        "FAKE_AM_DIR": str(world["am"]),
    }
    for name in ("XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        e[name] = str(world["tmp"] / name.lower())
    e.update(extra)
    return e


def set_script(world, steps, exit=0, stderr=""):
    (world["am"] / "script.json").write_text(
        json.dumps({"steps": steps, "exit": exit, "stderr": stderr}))


def run_helper(world, args=ARGS, timeout=30, **extra):
    """Run the helper until it exits (default argv: ARGS). Every stdout line must
    be JSON. Returns (exit code, parsed lines, stderr, raw stdout lines)."""
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True,
                       env=env_for(world, **extra), timeout=timeout)
    out = p.stdout.splitlines()
    return p.returncode, [json.loads(line) for line in out], p.stderr, out


def error(kind, message):
    return {"ok": False, "error": {"type": kind, "message": message}}


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def start_helper(world, args=ARGS):
    return subprocess.Popen([sys.executable, SCRIPT, *args], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                            env=env_for(world))


def am_pid(world):
    return int((world["am"] / "pid").read_text())


def assert_gone(pid, within=5.0):
    """The fake am process no longer exists (no orphaned `am logs`)."""
    end = time.monotonic() + within
    while time.monotonic() < end:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    os.kill(pid, signal.SIGKILL)
    pytest.fail("am logs was left running after the helper exited")


def kill_am(world):
    """SIGKILL the recorded fake am if it is still alive (test cleanup only)."""
    pid_file = world["am"] / "pid"
    if not pid_file.exists():
        return
    try:
        os.kill(am_pid(world), signal.SIGKILL)
    except ProcessLookupError:
        pass


def read_lines(p, n, within=5.0):
    """The next `n` stdout lines of the running helper `p`, parsed; fails unless
    all of them arrive within `within` seconds."""
    got = []

    def reader():
        for _ in range(n):
            line = p.stdout.readline()
            if not line:
                return
            got.append(json.loads(line))

    t = threading.Thread(target=reader, daemon=True)
    t.start()
    t.join(within)
    assert len(got) == n and not t.is_alive(), got
    return got


def reap(p):
    """Kill the helper if a test left it running, and close its pipes."""
    if p.poll() is None:
        p.kill()
        p.wait()
    for pipe in (p.stdout, p.stderr):
        if pipe is not None and not pipe.closed:
            pipe.close()


# --- the lines are capture copies -----------------------------------------------

def test_lines_are_capture_copies():
    for name in ("logs-follow-agent.jsonl", "logs-follow-step.jsonl"):
        lines = lines_of(name)
        assert [compact(line) for line in lines] == capture_text(name)
        assert lines[0]["event"] == "logs" and lines[0]["schema"] == 1
        assert lines[-1] == {"event": "end", "status": "ok"}
        assert all("ok" not in line for line in lines)
    assert [compact(refusal())] == capture_text("logs-follow-refusal.json")
    assert refusal()["ok"] is False
    assert "/" + RUN + "/" + CARD + "/" + PHASE + ".1/" in agent()[0]["path"]


# --- argv, Usage, am missing ------------------------------------------------------

@pytest.mark.parametrize("attempt, attempt_flags", [("0", []), ("2", ["--attempt", "2"])],
                         ids=["attempt-0", "attempt-2"])
@pytest.mark.parametrize("offset, offset_flags",
                         [(None, []), ("0", []), ("512", ["--since-offset", "512"])],
                         ids=["no-offset", "offset-0", "offset-512"])
def test_argv(world, attempt, attempt_flags, offset, offset_flags):
    set_script(world, [])
    args = [REPO, RUN, CARD, PHASE, attempt] + ([] if offset is None else [offset])
    code, lines, _, _ = run_helper(world, args)
    assert code == 0
    assert lines == []
    assert calls(world) == [["logs", RUN, CARD, "--phase", PHASE, *attempt_flags, "--follow",
                             *offset_flags, "--repo-dir", REPO]]


@pytest.mark.parametrize("numbers, flags", [
    (["003", "0040"], ["--attempt", "3", "--follow", "--since-offset", "40"]),
    (["00"], ["--follow"]),
    (["00", "000"], ["--follow"]),
], ids=["leading-zeros", "attempt-00", "both-zero"])
def test_argv_leading_zeros(world, numbers, flags):
    set_script(world, [])
    code, _, _, _ = run_helper(world, [REPO, RUN, CARD, PHASE, *numbers])
    assert code == 0
    assert calls(world) == [["logs", RUN, CARD, "--phase", PHASE, *flags, "--repo-dir", REPO]]


def test_argv_values_reach_am_verbatim(world):
    repo, run, card, phase = "/a repo/$(x)", "run;echo pwned", "card`id`", "phase with space"
    set_script(world, [])
    code, _, _, _ = run_helper(world, [repo, run, card, phase, "1"])
    assert code == 0
    assert calls(world) == [["logs", run, card, "--phase", phase, "--attempt", "1", "--follow",
                             "--repo-dir", repo]]


@pytest.mark.parametrize("args", [
    [REPO, RUN, CARD, PHASE],
    [REPO, RUN, CARD, PHASE, "1", "0", "extra"],
    [REPO, RUN, CARD, PHASE, "x"],
    [REPO, RUN, CARD, PHASE, "-1"],
    [REPO, RUN, CARD, PHASE, "1.5"],
    [REPO, RUN, CARD, PHASE, ""],
    [REPO, RUN, CARD, PHASE, "٣"],
    [REPO, RUN, CARD, PHASE, "1", "-5"],
    [REPO, RUN, CARD, PHASE, "1", "abc"],
], ids=["four-args", "seven-args", "attempt-letters", "attempt-negative", "attempt-float",
        "attempt-empty", "attempt-arabic-indic-digit", "offset-negative", "offset-letters"])
def test_usage(world, args):
    set_script(world, [])
    code, lines, _, out = run_helper(world, args)
    assert code == 2
    assert lines == [error("Usage", USAGE)]
    assert out == [compact(error("Usage", USAGE))]
    assert calls(world) == []  # am never spawned


def test_usage_before_am_lookup(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, lines, _, _ = run_helper(world, [REPO, RUN], PATH=str(empty))
    assert code == 2
    assert lines == [error("Usage", USAGE)]


def test_am_missing(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, lines, _, _ = run_helper(world, PATH=str(empty))
    assert code == 0
    assert lines == [error("AmMissing", "am is not installed.")]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_logs_follow.py -q`
Expected: `test_lines_are_capture_copies` PASSES (it only reads fixtures); every other test FAILS, because `runs-logs-follow.py` does not exist (the subprocess exits 2 with `can't open file` on stderr, stdout empty, so `lines == [error(...)]` and `calls(world) == [...]` fail).

- [ ] **Step 3: Write the minimal script**

Create `core/backend/runs/runs-logs-follow.py` (the docstring is the whole contract; Tasks 2-4 add the code behind it):

```python
#!/usr/bin/env python3
"""One attempt's stdout as a stream, from `am logs ... --follow`.

    runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT [OFFSET]

ATTEMPT and OFFSET are one or more ASCII decimal digits, passed as their
integer. Any other argv is a Usage error (exit 2) and am is neither looked up
nor started. REPO, RUN, CARD and PHASE reach am verbatim; am refuses bad ones
itself. Long-lived. Spawns, as an argv list (no shell, stdin /dev/null),
    am logs RUN CARD --phase PHASE [--attempt ATTEMPT] --follow
        [--since-offset OFFSET] --repo-dir REPO
with --attempt omitted when ATTEMPT is 0 and --since-offset omitted when
OFFSET is absent or 0. Prints one compact JSON object per line, flushed at once:
  every JSON object am prints that has no `ok` key (the hello, each chunk, the
      end line, any other object), its keys and values unchanged; a hello
      (event "logs") must carry the integer schema 1 or 2, else SchemaMismatch;
  am's refusal envelope (an object with an `ok` key read before any line was
      printed), unchanged, as the only line; every later am line is ignored;
  {"ok": false, "error": {"type", "message"}}
      as the last line, with type AmMissing, FollowUnsupported (am exited 2
      without printing anything), SchemaMismatch (am is stopped), StreamError
      (am exited non-zero after a hello; message: am's last stderr line),
      HelperError (any other non-zero exit, or an unexpected failure) or Usage.
Any other line am prints (not JSON, not an object, or an `ok` object after a
printed line) is skipped; a non-zero count is written to stderr as
`runs-logs-follow: skipped N non-JSON lines`. am exiting 0 adds no line.
Exit 0 on every path except Usage. SIGINT, SIGTERM or a closed stdout stop am
(terminate, wait 2 s, kill) and end the helper with exit 0 and nothing more
printed. am is never left running. Only the `am logs` command is used; am's
data dir is never read and the hello's path is never opened.
"""
import json
import shutil
import subprocess
import sys

USAGE = "usage: runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT [OFFSET]"


def say(payload, code=0):
    """Print `payload` as one compact JSON line and flush it now: stdout is a
    pipe, so it is block-buffered."""
    print(json.dumps(payload, separators=(",", ":")))
    sys.stdout.flush()
    return code


def failure(kind, message, code=0):
    return say({"ok": False, "error": {"type": kind, "message": message}}, code)


def number(text):
    """The integer of one or more ASCII decimal digits, else None."""
    return int(text) if text.isascii() and text.isdigit() else None


def parse_args(argv):
    """(repo, run, card, phase, attempt, offset) for 5 or 6 arguments whose
    ATTEMPT and OFFSET (0 when absent) are ASCII digits, else None."""
    if len(argv) not in (5, 6):
        return None
    attempt = number(argv[4])
    offset = number(argv[5]) if len(argv) == 6 else 0
    if attempt is None or offset is None:
        return None
    return argv[0], argv[1], argv[2], argv[3], attempt, offset


def command(am, repo, run, card, phase, attempt, offset):
    """am's argv: --attempt only when attempt is not 0, --since-offset only when
    offset is not 0."""
    return [am, "logs", run, card, "--phase", phase,
            *(["--attempt", str(attempt)] if attempt else []), "--follow",
            *(["--since-offset", str(offset)] if offset else []), "--repo-dir", repo]


def spawn(argv):
    return subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, encoding="utf-8",
                            errors="replace")


def main(argv):
    parsed = parse_args(argv)
    if parsed is None:
        return failure("Usage", USAGE, 2)
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    proc = spawn(command(am, *parsed))
    proc.communicate()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_logs_follow.py tests/architecture -q`
Expected: all PASS (architecture included: no `def emit(` in the new file).

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-logs-follow.py tests/core/backend/runs/test_runs_logs_follow.py
git commit -m "feat(runs): runs-logs-follow.py builds the am logs --follow argv"
```

---

### Task 2: Stream passthrough, skip count, refusal (T5-T13)

**Files:**
- Modify: `core/backend/runs/runs-logs-follow.py` (imports; add `Seen`, `collect`, `stop`, `stream`, `finish`; replace `main`)
- Test: `tests/core/backend/runs/test_runs_logs_follow.py` (append)

**Interfaces:**
- Consumes: Task 1's `say`, `failure`, `parse_args`, `command`, `spawn`, `USAGE`; test helpers from Task 1.
- Produces: `class Seen` with attributes `lines:int`, `skipped:int`, `printed:bool`, `hello:bool`, `refusal:bool`; `collect(stream, parts)`; `stop(proc)`; `stream(lines, seen)` (iterates am's stdout lines; Task 3 adds the schema check inside it); `finish(code, seen, stderr) -> int` (Task 3 replaces its body); `main(argv) -> int` calling them.

- [ ] **Step 1: Append the failing tests**

Append to `tests/core/backend/runs/test_runs_logs_follow.py`:

```python
# --- passthrough --------------------------------------------------------------------

@pytest.mark.parametrize("name, attempt", [("logs-follow-agent.jsonl", "1"),
                                           ("logs-follow-step.jsonl", "0")],
                         ids=["agent", "step"])
def test_capture_passes_through(world, name, attempt):
    captured = lines_of(name)
    set_script(world, [step(line) for line in captured])
    code, lines, err, out = run_helper(world, [REPO, RUN, CARD, PHASE, attempt])
    assert code == 0
    assert lines == captured
    assert out == capture_text(name)  # compact, key order and values kept
    assert "skipped" not in err


def test_non_objects_skipped_and_counted(world):
    hello, chunk, end = agent()
    set_script(world, [raw("not json"), step(hello), raw("[1,2]"), step(chunk), raw('"s"'),
                       raw("null"), step(end)])
    code, lines, err, _ = run_helper(world)
    assert code == 0
    assert lines == [hello, chunk, end]
    assert "runs-logs-follow: skipped 4 non-JSON lines" in err


def test_unknown_objects_kept(world):
    hello, chunk, end = agent()
    extra = edited(chunk, later="synthetic")
    note = {"event": "note", "detail": [1, {"x": None}]}  # synthetic: a kind this helper does not know
    set_script(world, [step(hello), step(extra), step(note), step(end)])
    code, lines, _, out = run_helper(world)
    assert code == 0
    assert lines == [hello, extra, note, end]
    assert out[1] == compact(extra) and out[2] == compact(note)


def test_non_ascii_text_passes_through(world):
    hello, chunk, end = agent()
    wide = edited(chunk, text="café ✓ — 日本\n")
    set_script(world, [step(hello), raw(json.dumps(wide, separators=(",", ":"), ensure_ascii=False)),
                       step(end)])
    code, lines, err, _ = run_helper(world)
    assert code == 0
    assert lines == [hello, wide, end]
    assert "skipped" not in err


def test_long_chunk_passes_through_whole(world):
    hello, chunk, end = agent()
    big = edited(chunk, text="x" * 1_000_000 + "\n")
    set_script(world, [step(hello), step(big), step(end)])
    code, lines, _, _ = run_helper(world)
    assert code == 0
    assert lines == [hello, big, end]


def test_each_line_flushed_while_am_runs(world):
    hello, chunk, _ = agent()
    set_script(world, [step(hello), step(chunk), pause(30)])
    p = start_helper(world)
    try:
        assert read_lines(p, 2, within=5) == [hello, chunk]
        p.send_signal(signal.SIGTERM)
        p.wait(timeout=10)
    finally:
        reap(p)
        kill_am(world)


def test_am_exit_zero_without_end_line(world):
    hello, chunk, _ = agent()
    set_script(world, [step(hello), step(chunk)])
    code, lines, _, _ = run_helper(world)
    assert code == 0
    assert lines == [hello, chunk]


# --- refusal ------------------------------------------------------------------------

def test_refusal_passes_through(world):
    set_script(world, [step(refusal())], exit=3, stderr="am logs: refused\n")
    code, lines, _, out = run_helper(world)
    assert code == 0
    assert lines == [refusal()]
    assert out == capture_text("logs-follow-refusal.json")


def test_refusal_is_the_only_line(world):
    _, chunk, _ = agent()
    set_script(world, [step(refusal()), step(chunk), raw("noise")], exit=3)
    code, lines, err, _ = run_helper(world)
    assert code == 0
    assert lines == [refusal()]
    assert "skipped" not in err  # later lines are ignored, not counted


def test_refusal_after_a_skipped_line_is_still_the_refusal(world):
    set_script(world, [raw("noise"), step(refusal())], exit=3)
    code, lines, err, _ = run_helper(world)
    assert code == 0
    assert lines == [refusal()]
    assert "skipped 1 non-JSON lines" in err


def test_ok_object_after_a_printed_line_is_skipped(world):
    hello, chunk, end = agent()
    set_script(world, [step(hello), step(refusal()), step(chunk), step(end)])
    code, lines, err, _ = run_helper(world)
    assert code == 0
    assert lines == [hello, chunk, end]
    assert "runs-logs-follow: skipped 1 non-JSON lines" in err
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_logs_follow.py -q`
Expected: the new tests FAIL (Task 1's `main` discards am's stdout, so `lines == []`; `read_lines` in `test_each_line_flushed_while_am_runs` times out with `assert len(got) == n`). Task 1's tests still PASS.

- [ ] **Step 3: Implement streaming**

In `core/backend/runs/runs-logs-follow.py`, replace the import block with:

```python
import json
import shutil
import subprocess
import sys
import threading
```

Insert after `spawn` (before `main`):

```python
class Seen:
    """What the helper read from am's stdout and printed so far."""

    def __init__(self):
        self.lines = 0  # every stdout line am printed, skipped ones included
        self.skipped = 0
        self.printed = False
        self.hello = False  # a hello was printed
        self.refusal = False


def collect(stream, parts):
    """Reader thread: am's whole stderr, so a chatty am never blocks on a full pipe."""
    parts.append(stream.read())


def stop(proc):
    """Terminate am if it is still running (kill it after 2 s), and reap it."""
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def stream(lines, seen):
    """Print each of am's stdout `lines` that is a JSON object, recording in
    `seen`. An object with an `ok` key read before any printed line is the
    refusal: printed, and every later line ignored. Every other line that is not
    a JSON object without an `ok` key is skipped and counted."""
    for raw in lines:
        seen.lines += 1
        if seen.refusal:
            continue
        try:
            line = json.loads(raw)
        except ValueError:
            line = None
        if not isinstance(line, dict) or ("ok" in line and seen.printed):
            seen.skipped += 1
            continue
        if "ok" in line:
            seen.refusal = True
        elif line.get("event") == "logs":
            seen.hello = True
        say(line)
        seen.printed = True


def finish(code, seen, stderr):
    """Print the last line, if any, for how am ended; return the helper's exit code."""
    return 0
```

Replace `main` with:

```python
def main(argv):
    parsed = parse_args(argv)
    if parsed is None:
        return failure("Usage", USAGE, 2)
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    proc = spawn(command(am, *parsed))
    err, seen = [], Seen()
    err_reader = threading.Thread(target=collect, args=(proc.stderr, err), daemon=True)
    err_reader.start()
    try:
        stream(proc.stdout, seen)
        code = proc.wait()
        err_reader.join(timeout=2)
    finally:
        stop(proc)  # no-op once am has exited; terminates it on every other path
        if seen.skipped:
            sys.stderr.write("runs-logs-follow: skipped %d non-JSON lines\n" % seen.skipped)
            sys.stderr.flush()
    return finish(code, seen, "".join(err))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_logs_follow.py tests/architecture -q`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-logs-follow.py tests/core/backend/runs/test_runs_logs_follow.py
git commit -m "feat(runs): runs-logs-follow.py streams am's lines and passes a refusal through"
```

---

### Task 3: SchemaMismatch and the last line after am exits (T15-T22)

**Files:**
- Modify: `core/backend/runs/runs-logs-follow.py` (add `SchemaMismatch`, `check_hello`; call it in `stream`; replace `finish`; `main` catches `SchemaMismatch`; add `guarded`; the `__main__` block calls `guarded`)
- Test: `tests/core/backend/runs/test_runs_logs_follow.py` (append)

**Interfaces:**
- Consumes: Task 2's `Seen`, `stream`, `stop`, `finish`, `main`; Task 1's `failure`.
- Produces: `class SchemaMismatch(Exception)`; `check_hello(hello)` (raises `SchemaMismatch`); `finish(code, seen, stderr) -> int` with the full table; `guarded(argv) -> int` (Task 4 extends it with signals).

- [ ] **Step 1: Append the failing tests**

Append to `tests/core/backend/runs/test_runs_logs_follow.py`:

```python
# --- how am ended ---------------------------------------------------------------------

UNSUPPORTED = "usage: am logs ... error: unrecognized arguments: --follow"


@pytest.mark.parametrize("stderr, message", [
    (UNSUPPORTED + "\n", "am logs cannot follow (exit 2): " + UNSUPPORTED),
    ("usage: am logs [-h] RUN CARD\n" + UNSUPPORTED + "\n\n",
     "am logs cannot follow (exit 2): " + UNSUPPORTED),
    ("", "am logs cannot follow (exit 2)."),
], ids=["one-line", "last-non-empty-line", "empty-stderr"])
def test_follow_unsupported(world, stderr, message):
    set_script(world, [], exit=2, stderr=stderr)
    code, lines, _, _ = run_helper(world)
    assert code == 0
    assert lines == [error("FollowUnsupported", message)]


def test_exit_2_after_output_is_helper_error(world):
    set_script(world, [raw("noise")], exit=2, stderr="bad\n")
    code, lines, _, _ = run_helper(world)
    assert code == 0
    assert lines == [error("HelperError", "bad")]


@pytest.mark.parametrize("stderr, message", [
    ("am logs: run left the projection\n", "am logs: run left the projection"),
    ("", "am logs exited 3."),
], ids=["stderr-line", "empty-stderr"])
def test_stream_error(world, stderr, message):
    hello, chunk, _ = agent()
    set_script(world, [step(hello), step(chunk)], exit=3, stderr=stderr)
    code, lines, _, _ = run_helper(world)
    assert code == 0
    assert lines == [hello, chunk, error("StreamError", message)]


def test_chatty_stderr_never_blocks(world):
    hello, chunk, _ = agent()
    noise = "warning: chatty\n" * 20000 + "am logs: disk vanished\n"  # ~320 KB, past a pipe buffer
    set_script(world, [step(hello), step(chunk)], exit=3, stderr=noise)
    code, lines, _, _ = run_helper(world, timeout=20)
    assert code == 0
    assert lines == [hello, chunk, error("StreamError", "am logs: disk vanished")]


@pytest.mark.parametrize("steps, exit, stderr, message", [
    ([], 3, "", "am logs exited 3."),
    ([], 1, "boom\n", "boom"),
    ([raw("noise")], 1, "", "am logs exited 1."),
], ids=["exit-3-no-output", "exit-1-boom", "exit-1-after-skipped-line"])
def test_helper_error(world, steps, exit, stderr, message):
    set_script(world, steps, exit=exit, stderr=stderr)
    code, lines, _, _ = run_helper(world)
    assert code == 0
    assert lines == [error("HelperError", message)]


# --- schema ---------------------------------------------------------------------------

def mismatch(value):
    return error("SchemaMismatch", "am logs speaks schema " + json.dumps(value)
                 + "; this helper reads schema 1 or 2.")


@pytest.mark.parametrize("schema", [3, 0, True, "1", 1.0, MISSING],
                         ids=["synthetic: three", "synthetic: zero", "synthetic: true",
                              "synthetic: string-one", "synthetic: one-float",
                              "synthetic: missing"])
def test_schema_mismatch_stops_am(world, schema):
    set_script(world, [step(edited(agent()[0], schema=schema)), pause(30)])
    began = time.monotonic()
    code, lines, _, _ = run_helper(world, timeout=10)
    assert time.monotonic() - began < 5
    assert code == 0
    assert lines == [mismatch(None if schema is MISSING else schema)]
    assert_gone(am_pid(world))  # am was stopped, not left streaming


def test_schema_mismatch_keeps_lines_already_printed(world):
    hello, chunk, _ = agent()
    set_script(world, [step(hello), step(chunk), step(edited(hello, schema=3)), pause(30)])
    code, lines, _, _ = run_helper(world, timeout=10)
    assert code == 0
    assert lines == [hello, chunk, mismatch(3)]
    assert_gone(am_pid(world))


def test_schema_2_accepted(world):
    hello, chunk, end = agent()
    hello2 = edited(hello, schema=2)
    set_script(world, [step(hello2), step(chunk), step(end)])
    code, lines, _, _ = run_helper(world)
    assert code == 0
    assert lines == [hello2, chunk, end]


# --- unexpected failure -----------------------------------------------------------------

def test_unexpected_failure_is_helper_error(world):
    write_exec(world["bin"] / "am", "#!/nonexistent/interpreter\n")  # found on PATH, cannot start
    code, lines, err, _ = run_helper(world)
    assert code == 0
    assert len(lines) == 1, lines
    assert lines[0]["ok"] is False
    assert lines[0]["error"]["type"] == "HelperError"
    assert lines[0]["error"]["message"].startswith("The log follow failed: ")
    assert "Traceback" not in err
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_logs_follow.py -q`
Expected: FAIL — `test_follow_unsupported`, `test_exit_2_after_output_is_helper_error`, `test_stream_error`, `test_chatty_stderr_never_blocks`, `test_helper_error` (no last line yet: `lines` lacks the error); `test_schema_mismatch_stops_am` and `test_schema_mismatch_keeps_lines_already_printed` (`subprocess.TimeoutExpired`: the bad hello is printed and the helper waits for am); `test_unexpected_failure_is_helper_error` (traceback, exit 1, no line). `test_schema_2_accepted` already PASSES (it guards against an over-strict check).

- [ ] **Step 3: Implement the schema check, the last line and the catch-all**

In `core/backend/runs/runs-logs-follow.py`, insert after `USAGE = ...`:

```python


class SchemaMismatch(Exception):
    """A hello whose schema is not the integer 1 or 2."""
```

Insert before `def stream(`:

```python
def check_hello(hello):
    """Raises SchemaMismatch unless the hello's schema is the integer 1 or 2."""
    schema = hello.get("schema")
    if not (type(schema) is int and schema in (1, 2)):
        raise SchemaMismatch("am logs speaks schema " + json.dumps(schema)
                             + "; this helper reads schema 1 or 2.")


```

In `stream`, replace

```python
        elif line.get("event") == "logs":
            seen.hello = True
```

with

```python
        elif line.get("event") == "logs":
            check_hello(line)
            seen.hello = True
```

and append to `stream`'s docstring, before the closing `"""`, the sentence ` A hello is checked before it is printed. Raises SchemaMismatch.` (so the docstring ends `...is skipped and counted. A hello is checked before it is printed. Raises SchemaMismatch."""`).

Replace `finish` with:

```python
def finish(code, seen, stderr):
    """Print the last line, if any, for how am ended; return the helper's exit
    code. `stderr` is am's whole stderr; its last non-empty line is the message."""
    if seen.refusal or code == 0:
        return 0
    lines = [line.strip() for line in stderr.splitlines() if line.strip()]
    message = lines[-1] if lines else ""
    if code == 2 and seen.lines == 0:
        if message:
            return failure("FollowUnsupported", "am logs cannot follow (exit 2): " + message)
        return failure("FollowUnsupported", "am logs cannot follow (exit 2).")
    kind = "StreamError" if seen.hello else "HelperError"
    return failure(kind, message or "am logs exited " + str(code) + ".")
```

In `main`, replace

```python
    try:
        stream(proc.stdout, seen)
        code = proc.wait()
```

with

```python
    try:
        try:
            stream(proc.stdout, seen)
        except SchemaMismatch as e:
            stop(proc)
            return failure("SchemaMismatch", str(e))
        code = proc.wait()
```

Insert after `main`:

```python
def guarded(argv):
    """Any unexpected exception ends with one HelperError line, exit 0 (main's
    finally has already stopped am)."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The log follow failed: " + reason)
```

Replace the `__main__` block with:

```python
if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_logs_follow.py tests/architecture -q`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-logs-follow.py tests/core/backend/runs/test_runs_logs_follow.py
git commit -m "feat(runs): runs-logs-follow.py types how am ended and rejects an unknown schema"
```

---

### Task 4: Signals and a closed stdout (T23-T25)

**Files:**
- Modify: `core/backend/runs/runs-logs-follow.py` (imports; add `Stop`, `on_signal`, `quiet_exit`; `stop` ignores further signals; replace `guarded`)
- Test: `tests/core/backend/runs/test_runs_logs_follow.py` (append)

**Interfaces:**
- Consumes: Task 3's `guarded`, `main`; Task 2's `stop`.
- Produces: `class Stop(Exception)`; `on_signal(signum, frame)`; `quiet_exit() -> int`; final `guarded(argv) -> int`.

- [ ] **Step 1: Append the failing tests**

Append to `tests/core/backend/runs/test_runs_logs_follow.py`:

```python
# --- stopping: signals and a closed stdout ---------------------------------------------

@pytest.mark.parametrize("sig", [signal.SIGTERM, signal.SIGINT], ids=["SIGTERM", "SIGINT"])
def test_signal_stops_am_and_exits_zero(world, sig):
    hello = agent()[0]
    set_script(world, [step(hello), pause(30)])
    p = start_helper(world)
    try:
        assert read_lines(p, 1) == [hello]  # sync point: am is running, the helper is streaming
        p.send_signal(sig)
        code = p.wait(timeout=10)
        rest, err = p.communicate(timeout=10)
        assert code == 0, err
        assert rest == ""  # nothing more printed
        assert "Traceback" not in err
        assert_gone(am_pid(world))
    finally:
        reap(p)
        kill_am(world)


def test_sigterm_kills_an_am_that_ignores_it(world):
    hello = agent()[0]
    set_script(world, [IGNORE_TERM, step(hello), pause(30)])
    p = start_helper(world)
    try:
        assert read_lines(p, 1) == [hello]
        began = time.monotonic()
        p.send_signal(signal.SIGTERM)
        code = p.wait(timeout=10)
        assert time.monotonic() - began < 5
        _, err = p.communicate(timeout=10)
        assert code == 0, err
        assert "Traceback" not in err
        assert_gone(am_pid(world))
    finally:
        reap(p)
        kill_am(world)


def test_second_sigterm_while_stopping_still_stops_am(world):
    hello = agent()[0]
    set_script(world, [IGNORE_TERM, step(hello), pause(30)])
    p = start_helper(world)
    try:
        assert read_lines(p, 1) == [hello]
        p.send_signal(signal.SIGTERM)
        time.sleep(0.5)  # the helper is now inside its 2 s wait for am
        if p.poll() is None:
            p.send_signal(signal.SIGTERM)
        code = p.wait(timeout=10)
        _, err = p.communicate(timeout=10)
        assert code == 0, err
        assert "Traceback" not in err
        assert_gone(am_pid(world), within=0.5)  # killed and reaped before the helper exited
    finally:
        reap(p)
        kill_am(world)


def test_closed_stdout_exits_zero(world):
    hello, chunk, _ = agent()
    set_script(world, [step(hello)] + [pause(0.2), step(chunk)] * 20 + [pause(30)])
    p = start_helper(world)
    try:
        assert read_lines(p, 1) == [hello]
        p.stdout.close()  # the reader goes away while am keeps printing chunks
        code = p.wait(timeout=10)
        err = p.stderr.read()
        assert code == 0, err
        assert "Traceback" not in err
        assert "BrokenPipeError" not in err
        assert_gone(am_pid(world))
    finally:
        reap(p)
        kill_am(world)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_logs_follow.py -q`
Expected: FAIL — SIGTERM tests exit `-15` (default action, no handler); the SIGINT case prints a `HelperError` line (`rest != ""`); `test_closed_stdout_exits_zero` exits 1 with a `BrokenPipeError` traceback. Earlier tests still PASS.

- [ ] **Step 3: Implement signal handling**

In `core/backend/runs/runs-logs-follow.py`, replace the import block with:

```python
import json
import os
import shutil
import signal
import subprocess
import sys
import threading
```

Insert after the `SchemaMismatch` class:

```python


class Stop(Exception):
    """SIGINT or SIGTERM: the store (or a user) is done with this stream."""


def on_signal(signum, frame):
    raise Stop()
```

Replace `stop` with:

```python
def stop(proc):
    """Terminate am if it is still running (kill it after 2 s), and reap it.
    SIGINT and SIGTERM are ignored from here on, so a second one cannot leave am
    running."""
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
```

Replace `guarded` with:

```python
def quiet_exit():
    """Ended by a signal or a closed stdout: exit 0 without a traceback. stdout
    is pointed at /dev/null so the interpreter's final flush cannot raise."""
    try:
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
    except OSError:
        pass
    return 0


def guarded(argv):
    """SIGINT, SIGTERM and a closed stdout end the helper quietly with exit 0
    (main's finally has already stopped am). Any other unexpected exception ends
    with one HelperError line, exit 0."""
    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)  # explicit: SIGINT may be inherited as ignored
    try:
        return main(argv)
    except (Stop, KeyboardInterrupt, BrokenPipeError):
        return quiet_exit()
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        try:
            return failure("HelperError", "The log follow failed: " + reason)
        except BrokenPipeError:
            return quiet_exit()
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_logs_follow.py tests/architecture -q`
Expected: all PASS. Run the module twice more to check the timing tests are stable: `for i in 1 2; do timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_logs_follow.py -q || break; done` — expected PASS both times.

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-logs-follow.py tests/core/backend/runs/test_runs_logs_follow.py
git commit -m "feat(runs): runs-logs-follow.py stops am on a signal or a closed stdout"
```

---

### Task 5: `docs/architecture.md` sentence and full verification

**Files:**
- Modify: `docs/architecture.md:201` (the `core/backend/runs/` paragraph, one line)

**Interfaces:**
- Consumes: the finished helper's contract (Tasks 1-4).
- Produces: nothing code-facing.

- [ ] **Step 1: Add the sentence**

In `docs/architecture.md` line 201, find the text

```
`runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` is a one-shot `am logs RUN CARD --phase P --attempt N --repo-dir R` passthrough: a 60 s timeout, exactly one JSON line.
```

and insert directly after it (same line, separated by one space):

```
`runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT [OFFSET]` (ATTEMPT and OFFSET are ASCII digits; any other argv is `Usage`, exit 2) is long-lived and no store runs it yet: it runs `am logs RUN CARD --phase PHASE [--attempt N] --follow [--since-offset B] --repo-dir REPO` (ATTEMPT 0 omits `--attempt`; an absent or 0 OFFSET omits `--since-offset`) and re-prints every JSON object am prints (hello, chunks, end) compact and flushed per line, skipping and counting (on its stderr) any line that is not a JSON object; am's refusal envelope is printed unchanged as its only line; it ends on failure with an `{ok: false, error}` line -- `AmMissing`, `FollowUnsupported` (am exited 2 before printing anything), `SchemaMismatch` (a hello `schema` other than 1 or 2; am is stopped), `StreamError` (am failed after the hello; am's last stderr line) or `HelperError` -- and exits 0 on every path but `Usage`; SIGTERM, SIGINT or a closed stdout stop am (terminate, 2 s, kill) and end it with exit 0.
```

Use the Edit tool with the `runs-logs.py ... exactly one JSON line.` sentence as `old_string` and that sentence plus a space plus the new sentence as `new_string`.

- [ ] **Step 2: Check the sentence landed once, in the right paragraph**

Run: `grep -c 'runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT \[OFFSET\]' docs/architecture.md && grep -n 'runs-logs-follow' docs/architecture.md | cut -c1-80`
Expected: count `1`; the match is on line 201 (the line beginning `` `core/backend/runs/` is the run-monitor backend``).

- [ ] **Step 3: Run the whole suite**

Run: `timeout 600 bash tests/run.sh`
Expected: pytest reports all passed (including `tests/architecture` and the new module) and the QML loop ends with exit status 0. Then `git status --short` shows only the three intended files changed relative to the branch base (plus the spec/plan docs).

- [ ] **Step 4: Commit**

```bash
git add docs/architecture.md
git commit -m "docs: describe runs-logs-follow.py in the run-monitor backend paragraph"
```
<!-- task-pipeline: validated -->
