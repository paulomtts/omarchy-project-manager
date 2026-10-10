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
