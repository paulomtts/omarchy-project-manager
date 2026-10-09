# 1.1 Contract test: the installed `am logs --follow` — spec

Card `3762705f-2253-4aa3-bfb9-69634c17f4dd`, subtask of story `85b0f971-5e0f-488e-a8e5-a71e3663f314`
(Live run output). Parent design: `docs/superpowers/specs/2026-10-05-live-output-design.md`
(below: **LO**).

## Purpose

Pin, against the `am` actually installed on the machine, the `am logs --follow` stream that the
rest of the Live run output milestone parses, and commit three recordings of it as fixtures that
later cards (`logStream.js`, `runs-logs-follow.py`) test against. Nothing in `core/` or `ui/`
changes.

## Inherited constraints

| constraint | source |
|---|---|
| The installed `am logs --help` lists `--follow` and `--since-offset`; the test fails loudly when not, and is skipped only when `am` is absent. | LO §Testing, lines 231-232 |
| An agent attempt's stream and `verify`'s stream are recorded in a throwaway journal; the hello, chunk and end keys are pinned; the refusal for a step without a log is pinned. | LO §Testing, lines 232-234 |
| Fixture names: `tests/fixtures/am/logs-follow-agent.jsonl`, `logs-follow-step.jsonl`, `logs-follow-refusal.json`. | LO §Testing, lines 235-236 |
| Hello: `{"event":"logs","offset":B,"path":…,"schema":1}`; readers accept `schema` 1 or 2. | LO lines 52-53, 70-71 |
| Chunks `{"offset":O,"text":T}`, contiguous, `O` = byte position of the chunk's first byte, existing content first. | LO lines 54-57 |
| End `{"event":"end","status":S}`, exit 0, `S` ∈ `ok \| schema_invalid \| gate_failed \| harness_error`; a step's `S` is `ok` when its attempt is the phase's latest and the phase is `done`. | LO lines 58-61 |
| A refusal is ONE envelope `{"ok":false,"error":{type,message}}`, exit 3, before any stream line; a step with no log is refused with `UnknownAttemptError: phase '…' has no recorded attempt yet`. Only a refusal has an `ok` key; only a stream starts with `"event":"logs"`. | LO lines 36-40, 62-64 |
| A step is addressed with `--phase P` and no `--attempt`; only `verify` writes a log today; `worktree` does not. | LO lines 36-40 |
| Hermetic: `am` runs with HOME, XDG_DATA_HOME, XDG_STATE_HOME under `tmp_path`; the user's runs are never read or written; `am` is never imported and `am.db` never read. | `tests/contract/test_am_shapes.py:1-13` (module contract) |
| A recorded fixture rewrites only the scratch root, so paths read `/home/user/...`; nothing else is edited. | `tests/fixtures/am/logs-attempt.json` `_note` |
| If no throwaway journal can make `am` produce these streams, STOP and escalate rather than hand-shape fixtures. | card description |
| Docstrings and comments state the contract only, no narrative; `bash tests/run.sh` green; `tests/architecture` passes; TDD. | card description |

## Feasibility (verified while writing this spec)

On this machine (agent-manager 0.2.0 at `~/.local/bin/am`), a scratch store with a git repo, a brd
board of one story and one subtask, and a PATH holding only `am`, `brd`, `git` and a stub `claude`
that writes a schema-valid result for each agent phase: `am run --story S --branch-prefix p
--verify <cmd> --repo-dir .` finished `done` in about 2.3 s. Every agent phase (explore, spec,
validate_spec, plan, validate_plan, implement, review) recorded attempt 1. Then:

- `am logs RUN CARD --phase review --follow` printed the hello (offset 0, schema 1), one chunk
  `{"offset":0,"text":"<stub line>\n"}` and `{"event":"end","status":"ok"}`, exit 0.
- `am logs RUN CARD --phase verify --follow` printed the hello, one chunk
  `{"offset":0,"text":"==> <cmd> (exit 0)\n<cmd output>\n"}` and `{"event":"end","status":"ok"}`,
  exit 0.
- `am logs RUN CARD --phase worktree --follow` printed
  `{"error":{"message":"phase 'worktree' of card '<CARD>' has no recorded attempt yet","type":"UnknownAttemptError"},"ok":false}`,
  exit 3.

`am` resolves a `--verify` command's first word on PATH (a bare `echo` with PATH = the scratch bin
dir failed with `No such file or directory: 'echo'`), so the verify command must live in the
scratch bin dir. With no `claude` at all the run escalates at `explore` with that attempt left
`started`, so `--follow` never ends; the stub is required. The STOP-and-escalate branch of the
card does not apply.

## Behaviour

### B1. Help lists both options

`am logs --help` exits 0 and its stdout contains `--follow` and `--since-offset`. When either is
missing the test fails (never skips) with a message naming each missing option and the
reinstall hint used by `test_run_help_lists_the_story_option`
(`uv tool install --reinstall`). The check lives in a helper, `missing_logs_follow_options(help_text)`
→ list of the missing option strings in the order `--follow`, `--since-offset`; the test calls
`pytest.fail` when the list is non-empty. The module-level `pytestmark` skip (am absent) is the
only skip.

### B2. A finished run reaches `verify` in a throwaway journal

A new fixture `finished_run(am, story_board, tmp_path)`:

- Adds two executables to the `story_board` bin dir (`tmp_path / "bin"`, already am.env's whole
  PATH): `claude`, a copy of the in-repo stub `tests/contract/stub_claude.py` with a
  `#!<realpath of sys.executable>` first line; and `verify-ok`, a script with the same shebang
  that prints `verified` and exits 0.
- Runs `am run --story <S1> --branch-prefix p --verify verify-ok --repo-dir <repo>` through
  `am.run` (bounded by `AM_TIMEOUT`, raised for this call only if the measured run needs it;
  `story_board`'s S1 has two subtasks).
- Fails, never skips, unless that exits 0 and `am runs --repo-dir <repo>` shows exactly one run
  with status `done`. The failure message carries `am run`'s stdout and stderr (they name the
  failed phase and, for a stub failure, the stub's stderr line).
- Returns `SimpleNamespace(id=<run id>, card=story_board.s1_subtasks[0], root=tmp_path)`.

`story_board` and `test_story_board_reaches_only_am_brd_and_git_and_its_own_repo` are unchanged:
the stub and the verify script are added only by `finished_run`.

### B3. The stub `claude` (`tests/contract/stub_claude.py`)

Test infrastructure, standard library only, run under a bare shebang. Its contract:

- Reads the brief path from argv: the value after `-p` is the sentence
  `Read <path> and follow the instructions in it exactly. …`.
- Reads the phase from the brief's `# phase: <name>` header, the result path from the line after
  `write your result as valid JSON to exactly this path:` in `## Result contract`, and the JSON
  Schema from that section's ```` ```json ```` fence.
- Writes, at the result path, a payload with every schema property at its type's zero value
  (`$ref` resolved through `$defs`; an `anyOf` containing `null` → `null`; object → recursed;
  array → `[]`; string → `""`; number/integer → `0`; boolean → `false`), then sets the fields the
  phase's gates need, refusing (exit 1, message on stderr) a field name the schema did not
  produce:
  - `explore`: `refused=false`, `reason=null`, `summary=<SUMMARY>`, `verification` =
    `{full_suite: <the brief's ## verification JSON>, typecheck: "", lint: []}`.
  - `validate_spec`, `validate_plan`: `blockers=false`, `reason=null`, `summary=<SUMMARY>`.
  - `spec`: writes a one-line document at the brief's `## spec_path` (relative to its cwd);
    `path=<spec_path>`, `note=null`.
  - `plan`: same with `## plan_path`; `path=<plan_path>`, `self_reviewed=true`, `note=null`.
  - `implement`: writes `IMPLEMENTATION.md` in its cwd naming the plan path, `git add -A`,
    `git -c user.name=stub -c user.email=stub@example.com commit -m "feat: implement this card\n\nPlan-Hash: <## plan_hash>"`
    (the scratch HOME has no git identity, so it is passed with `-c`; skipped, with
    `resumed=true`, when nothing changed); `blocked=false`, `blocked_reason=null`,
    `resumed=<bool>`, `plan_hash=<## plan_hash>`, `report=<SUMMARY>`.
  - `review`: `findings=[]`, `unresolved_blockers=[]`, `fix_summary=<SUMMARY>`,
    `porcelain=<git status --porcelain, stripped>`, `commit_count=<git rev-list
    <## base_branch>..HEAD count>`, `tagged_count=<those whose message contains "Plan-Hash:
    <## plan_hash>">`, `plan_hash=<## plan_hash>`.
  - Any other phase: exit 1 with `stub claude: no behaviour for phase '<name>'` on stderr.
- `SUMMARY` is a fixed sentence longer than 60 characters (am's minimum summary length).
- On success prints exactly one stdout line, `stub claude ok phase=<phase>`, and exits 0. That
  line is what the agent fixture records.

The field lists above match `agent-manager/tests/e2e/fake_claude.py` `build_result` for am 0.2.0;
they are named here so the stub carries no dependency on a file outside this repository.

### B4. The agent attempt's stream

`am logs <run> <card> --phase review --attempt 1 --follow --repo-dir <repo>` (the attempt is
terminal, so am exits by itself; run through `am.run`, bounded by `AM_TIMEOUT`):

- exit 0 (stderr is not pinned); every stdout line is one JSON object;
- line 1 (hello): key set exactly `{event, offset, path, schema}`; `event == "logs"`;
  `offset == 0`; `schema in (1, 2)`; `path` is a string under
  `<am.data>/agent-manager/runs/` ending in `/<card>/review.1/stdout.log` (hermetic);
- middle lines (chunks): at least one; each key set exactly `{offset, text}`, `offset` an int,
  `text` a str; the first chunk's `offset` equals the hello's; each next chunk's `offset` equals
  the previous `offset` + UTF-8 byte length of its `text`; the joined text is
  `stub claude ok phase=review\n`;
- last line (end): key set exactly `{event, status}`; `event == "end"`; `status == "ok"`;
- no line has an `ok` key.

### B5. The step's stream

`am logs <run> <card> --phase verify --follow --repo-dir <repo>` with no `--attempt`: the same
rules as B4, except the hello `path` ends in `/<card>/verify.1/stdout.log` and the joined chunk
text is `==> verify-ok (exit 0)\nverified\n`. End `status == "ok"` (the phase is `done` and
`verify.1` is its latest).

### B6. The refusal for a step without a log

`am logs <run> <card> --phase worktree --follow --repo-dir <repo>`: exit 3; stdout is exactly one
line; it parses to a dict with key set exactly `{ok, error}`, `ok is False`, `error` key set
exactly `{type, message}`, `type == "UnknownAttemptError"`, `message` contains `'worktree'` and
`has no recorded attempt yet`. No stdout line starts a stream (`"event"` absent).

### B7. Fixtures equal a fresh capture

Each of B4, B5, B6 compares its live capture with its committed fixture after normalizing the
capture (the scratch root `tmp_path` → `/home/user` in every string value):

- `logs-follow-agent.jsonl` (B4) and `logs-follow-step.jsonl` (B5): one compact JSON object per
  line, exactly am's lines in order, with the trailing newline. Every chunk and the end line
  must be equal; the hello must be equal except `path`, whose run id and card id differ per
  capture, so for the hello only the key set, `event`, `offset`, `schema` and the
  `/home/user/data/agent-manager/runs/<run>/<card>/<phase>.1/stdout.log` shape are compared.
- `logs-follow-refusal.json` (B6): the envelope as am printed it (a single JSON object, compact or
  indented). `ok` and `error.type` must be equal; `error.message` is compared with its card id
  replaced by `<CARD>` on both sides.
- No `_note` key or extra line: the files hold am's output only. Provenance is the recording
  test itself.
- When the environment variable `AM_RECORD_FIXTURES` is `1`, each test writes its normalized
  capture to its fixture file instead of comparing (the only way the fixtures are produced). With
  it unset, a missing fixture fails naming the file and the variable.

The `.jsonl` fixtures are not added to `tests/contract/test_am_fixtures.py` `FIXTURE_NAMES`
(that loader uses `json.load` and requires a `_note`; `test_am_fixtures.py:35-39, 374-378`), nor
to `tests/helpers/amFixtures.js` (consumers are later cards).

## Error paths

| condition | result |
|---|---|
| `am` not on PATH | whole module skipped (existing `pytestmark`, `test_am_shapes.py:25`) |
| `am logs --help` lacks `--follow` and/or `--since-offset` | B1 fails naming each missing option |
| `brd` or `git` missing | `require_tool` fails (existing) |
| stub cannot satisfy a phase (renamed field, new agent phase) | `finished_run` fails with am's output, which carries the stub's stderr line naming the phase or field |
| run does not reach `done` | `finished_run` fails with am's stdout and stderr |
| `--follow` hangs | `am.run`'s timeout raises `TimeoutExpired`; the test fails, the suite does not hang |
| stream shape drifts (key added/removed, status changed) | B4/B5/B6 fail naming the line and its keys |
| committed fixture differs from a fresh capture | B7 fails showing both |

## Tests

All in **tier: contract** (`tests/contract/`, run by `pytest tests` inside `bash tests/run.sh`):
they exercise the real installed `am` binary at its process boundary, which is the contract tier's
job; the live ones skip only when `am` is absent.

| test (in `tests/contract/test_am_shapes.py`) | proves | tier / why |
|---|---|---|
| `test_logs_help_lists_the_follow_options` | B1 against the installed am | contract: reads the real binary's help |
| `test_missing_logs_follow_options_names_each_missing_option` | B1's helper returns `[]` for help naming both, `["--follow", "--since-offset"]` for help naming neither, `["--since-offset"]` for help naming only `--follow` | contract module, pure: pins the failure message's content without needing an old am |
| `test_finished_run_reaches_verify_and_is_done` | B2/B3: the run is `done`; `am status` shows `review` with attempt 1 and `verify` phase `done` with `attempts: []` | contract: real am drives the stub end to end |
| `test_logs_follow_of_an_agent_attempt_prints_hello_chunks_and_end` | B4 and B7 for `logs-follow-agent.jsonl` | contract: real stream |
| `test_logs_follow_of_a_step_prints_hello_chunks_and_end` | B5 and B7 for `logs-follow-step.jsonl` | contract: real stream |
| `test_logs_follow_of_a_step_without_a_log_is_one_refusal` | B6 and B7 for `logs-follow-refusal.json` | contract: real refusal |
| `test_follow_stream_checker_names_the_line_that_drifted` | the shared stream-checking helper fails, naming the line index and its keys, on (a) a hello with an extra key, (b) a chunk whose offset skips a byte, (c) an end line missing `status`, (d) a stream with an `ok` key | contract module, pure: the checker is the contract; a checker that never fails proves nothing |
| `test_normalize_rewrites_only_the_scratch_root` | the normalizer replaces the scratch root in nested string values and leaves other strings, ints and keys unchanged | contract module, pure |

## Out of scope

- `core/backend/runs/runs-logs-follow.py` and its tests, the `runs-logs.py` REPO/step rules
  (LO lines 112-135): sibling cards.
- `core/domain/logStream.js`, `tst_log_stream.qml` and any fixture loading there (LO lines
  137-155, 237-239).
- `Runs.isLiveSelection`, step rows, `RunOutputStore`, `TailScroll`, the pane UI (LO lines
  98-212).
- Adding the new fixtures to `test_am_fixtures.py`, `amFixtures.js` or `tst_am_fixtures.qml`.
- Live checks of `--since-offset` resume, the `am logs: <message>` post-hello error, SIGINT,
  schema 2, an `am` without `--follow` (exit 2) and a non-terminal attempt's waiting stream: LO
  documents them, but this card pins only help, the two streams and the refusal.
- Any change to `story_board`, `seeded_run` or the existing tests in the module, beyond sharing
  helpers.

---

# 1.1 Contract test: the installed `am logs --follow` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pin the installed `am logs --follow` stream (help options, an agent attempt's stream, a step's stream, the refusal for a step without a log) in `tests/contract/test_am_shapes.py`, and commit three recordings of it as fixtures under `tests/fixtures/am/`.

**Architecture:** Test-only change. Pure helpers (`missing_logs_follow_options`, `normalize`, `recorded_fixture`, `json_lines`, `follow_stream_text`, `hello_shape`, `masked_card`) are appended to `tests/contract/test_am_shapes.py` and pinned on synthetic input first. A new fixture `finished_run` drives a real `am run --story` to `done` in the existing hermetic `story_board` by adding a stdlib stub `claude` (`tests/contract/stub_claude.py`) and a `verify-ok` command to its bin dir; the three live tests then read `am logs --follow` from that run and compare with the committed fixtures, which `AM_RECORD_FIXTURES=1` writes.

**Tech Stack:** Python 3 (stdlib), pytest, the installed `am` (agent-manager 0.2.0), `brd` and `git` binaries.

**Spec:** `docs/superpowers/specs/1-1-contract-test-the-3762705f.md` (prepended above).

## Global Constraints

- Nothing in `core/` or `ui/` changes. Files touched: `tests/contract/test_am_shapes.py` (modify), `tests/contract/stub_claude.py` (create), `tests/fixtures/am/logs-follow-agent.jsonl`, `tests/fixtures/am/logs-follow-step.jsonl`, `tests/fixtures/am/logs-follow-refusal.json` (create, by recording only).
- Hermetic: `am` runs with HOME, XDG_DATA_HOME, XDG_STATE_HOME under `tmp_path` (the existing `am` fixture); the user's runs are never read or written; `am` is never imported and `am.db` never read. Every am call goes through `am.run(...)`, bounded by `AM_TIMEOUT` (30 s; the measured story run takes ~3.5 s, so it is not raised).
- The module-level `pytestmark` skip (am absent) is the only skip. Every other unmet precondition fails.
- Hello: `{"event":"logs","offset":B,"path":…,"schema":1}`; readers accept `schema` 1 or 2.
- Chunks `{"offset":O,"text":T}`, contiguous, `O` = byte position of the chunk's first byte (UTF-8 bytes), existing content first.
- End `{"event":"end","status":S}`, exit 0, `S` ∈ `ok | schema_invalid | gate_failed | harness_error`.
- A refusal is ONE envelope `{"ok":false,"error":{type,message}}`, exit 3, before any stream line. Only a refusal has an `ok` key; only a stream starts with `"event":"logs"`.
- Fixture names exactly: `tests/fixtures/am/logs-follow-agent.jsonl`, `logs-follow-step.jsonl`, `logs-follow-refusal.json`. They hold am's output only (no `_note`), with only the scratch root rewritten to `/home/user`. They are produced only by running the tests with `AM_RECORD_FIXTURES=1`; never hand-edit them.
- Do not add the new fixtures to `tests/contract/test_am_fixtures.py` `FIXTURE_NAMES` or to `tests/helpers/amFixtures.js`.
- `story_board`, `seeded_run` and every existing test in the module stay unchanged.
- Docstrings and comments state the contract only, no narrative.
- `bash tests/run.sh` green; `tests/architecture` passes; TDD (watch every new test fail first).

## Running the tests

`python3` on this machine may have no pytest. Run pytest as `tests/run.sh` does, always under `timeout`:

```bash
timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q
```

(If `python3 -c 'import pytest'` succeeds, `python3 -m pytest ...` works as well.) Never use `pkill`/`killall`.

Ground truth, observed from the installed am (agent-manager 0.2.0) with the stub and fixture of this plan. `am run --story S1 --branch-prefix p --verify verify-ok` exits 0 in ~3.5 s with `"done": true`; `am runs` shows one row, status `done`. Then, for `card = story_board.s1_subtasks[0]` (run and card ids vary per run):

```
$ am logs RUN CARD --phase review --attempt 1 --follow   # exit 0
{"event":"logs","offset":0,"path":"<tmp>/data/agent-manager/runs/RUN/CARD/review.1/stdout.log","schema":1}
{"offset":0,"text":"stub claude ok phase=review\n"}
{"event":"end","status":"ok"}
$ am logs RUN CARD --phase verify --follow                # exit 0
{"event":"logs","offset":0,"path":"<tmp>/data/agent-manager/runs/RUN/CARD/verify.1/stdout.log","schema":1}
{"offset":0,"text":"==> verify-ok (exit 0)\nverified\n"}
{"event":"end","status":"ok"}
$ am logs RUN CARD --phase worktree --follow              # exit 3
{"error":{"message":"phase 'worktree' of card 'CARD' has no recorded attempt yet","type":"UnknownAttemptError"},"ok":false}
```

`am status RUN` → `data.stories[].subtasks[]` each with `card_id` and `phases[]`, each phase `{name, status, kind, attempts: [{n, status, ...}], ...}`; for CARD, `review` has attempts `[(n=1, status "ok")]`, `verify` is `status "done"` with `attempts: []`, `worktree` has `attempts: []`.

## Review Focus

1. A chunk whose text holds multi-byte UTF-8 (`é`, emoji in an agent's output) — the next chunk's offset is the byte, not character, position; a checker counting `len(text)` would reject a correct am or accept a wrong one. Pinned in Task 3 by `test_follow_stream_text_joins_contiguous_chunks_counting_utf8_bytes`.
2. A stream with no chunk at all (an empty `stdout.log`: hello then end) — the checker must fail with a readable message, not pass vacuously or raise `IndexError`. Pinned in Task 3 by `test_follow_stream_checker_fails_on_a_stream_with_no_chunk`.
3. am renames a result field or adds an agent phase — the stub must stop naming the field or phase, so `finished_run` fails with that line instead of a run escalating for an unexplained reason. Pinned in Task 4 by `test_stub_claude_refuses_a_field_the_schema_lacks` and `test_stub_claude_exits_1_naming_a_phase_it_has_no_behaviour_for`.
4. A fresh checkout runs the suite with a fixture missing and `AM_RECORD_FIXTURES` unset — the failure must name the file and the variable, and recording must actually write the file. Pinned in Task 2 by `test_recorded_fixture_fails_naming_the_file_and_the_variable` and `test_recorded_fixture_writes_the_capture_when_recording`.
5. A fixture recorded un-normalized (still a `/tmp/pytest-of-…` path) or for the wrong phase — the hello comparison by shape must reject it rather than treat any path as equal. Pinned in Task 6 by `test_hello_shape_accepts_only_a_normalized_attempt_log_path`.

---

### Task 1: `am logs --help` lists `--follow` and `--since-offset`

**Files:**
- Modify: `tests/contract/test_am_shapes.py` (append at end of file, after `test_attempt_payloads_carry_no_cost_or_token_keys`)

**Interfaces:**
- Consumes: the existing `am` fixture (`am.run(*args) -> subprocess.CompletedProcess`).
- Produces: `missing_logs_follow_options(help_text: str) -> list[str]`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/contract/test_am_shapes.py`:

```python


def test_missing_logs_follow_options_names_each_missing_option():
    assert missing_logs_follow_options("--follow ... --since-offset BYTES") == []
    assert missing_logs_follow_options("--phase --attempt") == ["--follow", "--since-offset"]
    assert missing_logs_follow_options("--follow") == ["--since-offset"]


def test_logs_help_lists_the_follow_options(am):
    proc = am.run("logs", "--help")
    assert proc.returncode == 0, proc.stdout + proc.stderr
    missing = missing_logs_follow_options(proc.stdout)
    if missing:
        pytest.fail(f"the installed am logs has no {', '.join(missing)} option "
                    "(reinstall agent-manager: uv tool install --reinstall)")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "missing_logs_follow_options or logs_help"`
Expected: 2 FAIL with `NameError: name 'missing_logs_follow_options' is not defined`.

- [ ] **Step 3: Write the helper**

Insert directly above `def test_missing_logs_follow_options_names_each_missing_option():`:

```python


def missing_logs_follow_options(help_text):
    """The options `am logs --follow` readers need that `help_text` does not name, in the
    order --follow, --since-offset."""
    return [option for option in ("--follow", "--since-offset") if option not in help_text]
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "missing_logs_follow_options or logs_help"`
Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
git add tests/contract/test_am_shapes.py
git commit -m "test(contract): the installed am logs lists --follow and --since-offset"
```

---

### Task 2: `normalize` and `recorded_fixture`

**Files:**
- Modify: `tests/contract/test_am_shapes.py` (imports at lines 14-23; append at end of file)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces (module-level names later tasks use):
  - `FIXTURES: Path` = `tests/fixtures/am`
  - `RECORD_ENV = "AM_RECORD_FIXTURES"`
  - `SCRATCH_HOME = "/home/user"`
  - `normalize(value, root) -> value` — `root` (a `Path` or `str`) replaced by `/home/user` in every string value, recursing through dicts and lists; keys and non-strings untouched.
  - `recorded_fixture(name: str, text: str) -> str` — the committed fixture's text; writes `text` there first when `AM_RECORD_FIXTURES=1`; fails naming the file and the variable when the file is missing.

- [ ] **Step 1: Add the imports**

Replace the import block at the top of `tests/contract/test_am_shapes.py`:

```python
import json
import os
import queue
import shutil
import subprocess
import threading
import time
from types import SimpleNamespace

import pytest
```

with:

```python
import json
import os
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path
from types import SimpleNamespace

import pytest
```

- [ ] **Step 2: Write the failing tests**

Append to `tests/contract/test_am_shapes.py`:

```python


def test_normalize_rewrites_only_the_scratch_root():
    root = "/tmp/pytest-of-u/pytest-7/test_x0"
    value = {f"{root}/key": [f"{root}/data/a.log", {"text": f"see {root}/b"}],
             "offset": 12, "status": "ok", "other": "/tmp/pytest-of-u/elsewhere"}
    assert normalize(value, root) == {
        f"{root}/key": ["/home/user/data/a.log", {"text": "see /home/user/b"}],
        "offset": 12, "status": "ok", "other": "/tmp/pytest-of-u/elsewhere"}


def test_recorded_fixture_fails_naming_the_file_and_the_variable(monkeypatch, tmp_path):
    monkeypatch.setattr(sys.modules[__name__], "FIXTURES", tmp_path)
    monkeypatch.delenv(RECORD_ENV, raising=False)
    with pytest.raises(pytest.fail.Exception,
                       match=r"logs-follow-x\.jsonl is missing.*AM_RECORD_FIXTURES=1"):
        recorded_fixture("logs-follow-x.jsonl", "{}\n")


def test_recorded_fixture_writes_the_capture_when_recording(monkeypatch, tmp_path):
    monkeypatch.setattr(sys.modules[__name__], "FIXTURES", tmp_path)
    monkeypatch.setenv(RECORD_ENV, "1")
    assert recorded_fixture("logs-follow-x.jsonl", "{}\n") == "{}\n"
    assert (tmp_path / "logs-follow-x.jsonl").read_text() == "{}\n"
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "normalize or recorded_fixture"`
Expected: 3 FAIL with `NameError` (`normalize`, `FIXTURES`/`RECORD_ENV` not defined).

- [ ] **Step 4: Write the helpers**

Insert directly above `def test_normalize_rewrites_only_the_scratch_root():`:

```python


FIXTURES = Path(__file__).resolve().parent.parent / "fixtures" / "am"
RECORD_ENV = "AM_RECORD_FIXTURES"
SCRATCH_HOME = "/home/user"


def normalize(value, root):
    """`value` with `root` replaced by /home/user in every string, keys untouched."""
    if isinstance(value, str):
        return value.replace(str(root), SCRATCH_HOME)
    if isinstance(value, dict):
        return {key: normalize(item, root) for key, item in value.items()}
    if isinstance(value, list):
        return [normalize(item, root) for item in value]
    return value
```

and directly above `def test_recorded_fixture_fails_naming_the_file_and_the_variable(...)`:

```python


def recorded_fixture(name, text):
    """The committed tests/fixtures/am/`name`. With AM_RECORD_FIXTURES=1, `text` is written
    there first; with it unset, a missing file fails naming the file and the variable."""
    path = FIXTURES / name
    if os.environ.get(RECORD_ENV) == "1":
        path.write_text(text, encoding="utf-8")
    if not path.is_file():
        pytest.fail(f"{path} is missing: record it with {RECORD_ENV}=1")
    return path.read_text(encoding="utf-8")
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "normalize or recorded_fixture"`
Expected: 3 passed.

- [ ] **Step 6: Commit**

```bash
git add tests/contract/test_am_shapes.py
git commit -m "test(contract): normalize am captures and record or read their fixtures"
```

---

### Task 3: the `am logs --follow` stream checker

**Files:**
- Modify: `tests/contract/test_am_shapes.py` (append at end of file)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `LOGS_HELLO_KEYS`, `CHUNK_KEYS`, `END_KEYS`, `END_STATUSES` (sets of str).
  - `json_lines(stdout: str) -> list[dict]` — each line parsed; fails naming a line that is not a JSON object.
  - `follow_stream_text(lines: list[dict], path_prefix: str, path_suffix: str) -> str` — the joined chunk text; fails (`pytest.fail`) with `line <index> <why>: keys [<sorted keys>] in <line>` on any drifted line.

- [ ] **Step 1: Write the failing tests**

Append to `tests/contract/test_am_shapes.py`:

```python


STREAM = [{"event": "logs", "offset": 0, "path": "/d/runs/r/c/review.1/stdout.log", "schema": 1},
          {"offset": 0, "text": "é\n"}, {"offset": 3, "text": "b\n"},
          {"event": "end", "status": "ok"}]


def test_follow_stream_text_joins_contiguous_chunks_counting_utf8_bytes():
    assert follow_stream_text(STREAM, "/d/runs/", "/c/review.1/stdout.log") == "é\nb\n"


@pytest.mark.parametrize("index, line, message", [
    (0, {**STREAM[0], "am": "0.2.0"}, r"line 0 is not a logs hello: keys \['am', 'event'"),
    (2, {"offset": 4, "text": "b\n"}, r"line 2 does not start at byte 3: keys \['offset', 'text'\]"),
    (3, {"event": "end"}, r"line 3 is not an end line: keys \['event'\]"),
    (3, {"event": "end", "status": "ok", "ok": True},
     r"line 3 has an ok key: keys \['event', 'ok', 'status'\]"),
])
def test_follow_stream_checker_names_the_line_that_drifted(index, line, message):
    drifted = [*STREAM[:index], line, *STREAM[index + 1:]]
    with pytest.raises(pytest.fail.Exception, match=message):
        follow_stream_text(drifted, "/d/runs/", "/c/review.1/stdout.log")


def test_follow_stream_checker_fails_on_a_stream_with_no_chunk():
    with pytest.raises(pytest.fail.Exception, match="one or more chunks"):
        follow_stream_text([STREAM[0], STREAM[-1]], "/d/runs/", "/c/review.1/stdout.log")


def test_json_lines_names_a_line_that_is_not_a_json_object():
    with pytest.raises(pytest.fail.Exception, match=r"line 1 is not a JSON object: '\[1\]'"):
        json_lines('{"a": 1}\n[1]\n')
```

(`"é\n"` is 3 UTF-8 bytes, so the second chunk starts at byte 3, not 2.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "follow_stream or json_lines"`
Expected: 7 FAIL — the parametrized and no-chunk cases with `NameError: name 'follow_stream_text' is not defined` (raised inside `pytest.raises`, so reported as an error escaping it), the last with `NameError: name 'json_lines' is not defined`.

- [ ] **Step 3: Write the checker**

Insert directly above `STREAM = [...]`:

```python


LOGS_HELLO_KEYS = {"event", "offset", "path", "schema"}
CHUNK_KEYS = {"offset", "text"}
END_KEYS = {"event", "status"}
END_STATUSES = {"ok", "schema_invalid", "gate_failed", "harness_error"}


def json_lines(stdout):
    """Each stdout line of am parsed as one JSON object; fails naming a line that is not."""
    lines = []
    for index, raw in enumerate(stdout.splitlines()):
        try:
            line = json.loads(raw)
        except json.JSONDecodeError:
            pytest.fail(f"line {index} is not JSON: {raw!r}")
        if not isinstance(line, dict):
            pytest.fail(f"line {index} is not a JSON object: {raw!r}")
        lines.append(line)
    return lines


def follow_stream_text(lines, path_prefix, path_suffix):
    """The joined chunk text of one whole `am logs --follow` stream.

    The stream is a hello `{event: "logs", offset, path, schema}` whose path starts with
    `path_prefix` and ends with `path_suffix`, one or more contiguous `{offset, text}`
    chunks from the hello's offset, and an `{event: "end", status}` line. No line has an
    `ok` key. A line that breaks this fails naming its index and its keys.
    """
    def drift(index, why):
        pytest.fail(f"line {index} {why}: keys {sorted(lines[index])} in {lines[index]!r}")

    if len(lines) < 3:
        pytest.fail(f"a stream is a hello, one or more chunks and an end; got {lines!r}")
    for index, line in enumerate(lines):
        if "ok" in line:
            drift(index, "has an ok key")
    hello, chunks, end = lines[0], lines[1:-1], lines[-1]
    if set(hello) != LOGS_HELLO_KEYS or hello["event"] != "logs":
        drift(0, "is not a logs hello")
    if type(hello["offset"]) is not int or hello["schema"] not in (1, 2):
        drift(0, "has a bad offset or schema")
    path = hello["path"]
    if not (isinstance(path, str) and path.startswith(path_prefix) and path.endswith(path_suffix)):
        drift(0, f"has a path outside {path_prefix}...{path_suffix}")
    offset = hello["offset"]
    for index, chunk in enumerate(chunks, start=1):
        if set(chunk) != CHUNK_KEYS or not isinstance(chunk["text"], str):
            drift(index, "is not a chunk")
        if type(chunk["offset"]) is not int or chunk["offset"] != offset:
            drift(index, f"does not start at byte {offset}")
        offset += len(chunk["text"].encode("utf-8"))
    if set(end) != END_KEYS or end["event"] != "end" or end["status"] not in END_STATUSES:
        drift(len(lines) - 1, "is not an end line")
    return "".join(chunk["text"] for chunk in chunks)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "follow_stream or json_lines"`
Expected: 7 passed.

- [ ] **Step 5: Commit**

```bash
git add tests/contract/test_am_shapes.py
git commit -m "test(contract): a checker for the am logs --follow stream naming the drifted line"
```

---

### Task 4: the stub `claude`

**Files:**
- Create: `tests/contract/stub_claude.py`
- Modify: `tests/contract/test_am_shapes.py` (import after `import pytest`; append at end of file)

**Interfaces:**
- Consumes: `AM_TIMEOUT` (existing, 30).
- Produces:
  - module `stub_claude` (in `tests/contract/`, importable by the tests because pytest puts that dir on `sys.path`, as `test_am_fixtures.py`'s `from test_am_shapes import ...` already relies on): `StubError(Exception)`, `override(payload: dict, **fields) -> dict`, `zero_payload(schema: dict, defs: dict | None = None) -> dict`, `main(argv: list[str]) -> int`; run as a script it prints `stub claude ok phase=<phase>` and exits 0, or prints `stub claude: <error>` on stderr and exits 1.
  - `STUB_CLAUDE: Path` — `tests/contract/stub_claude.py`.

- [ ] **Step 1: Write the failing tests**

In `tests/contract/test_am_shapes.py`, after the line `import pytest` add:

```python

import stub_claude
```

Append to `tests/contract/test_am_shapes.py`:

```python


STUB_CLAUDE = Path(__file__).resolve().parent / "stub_claude.py"


def test_stub_claude_refuses_a_field_the_schema_lacks():
    with pytest.raises(stub_claude.StubError, match="no field 'summary'.*'synopsis'"):
        stub_claude.override({"synopsis": ""}, summary="x")


def test_stub_claude_zero_payload_follows_refs_and_nullable_fields():
    schema = {"$defs": {"V": {"properties": {"lint": {"type": "array"},
                                              "typecheck": {"type": "string"}}}},
              "properties": {"verification": {"$ref": "#/$defs/V"},
                             "reason": {"anyOf": [{"type": "string"}, {"type": "null"}]},
                             "refused": {"type": "boolean"}, "n": {"type": "integer"}}}
    assert stub_claude.zero_payload(schema) == {
        "verification": {"lint": [], "typecheck": ""}, "reason": None, "refused": False, "n": 0}


def test_stub_claude_exits_1_naming_a_phase_it_has_no_behaviour_for(tmp_path):
    result = tmp_path / "result.json"
    brief = tmp_path / "prompt.txt"
    brief.write_text("# phase: resolve\n# role: resolver\n\n## Result contract\n"
                     "When you are done, write your result as valid JSON to exactly this path:\n\n"
                     f"{result}\n\n```json\n{{\"properties\": {{}}}}\n```\n", encoding="utf-8")
    proc = subprocess.run([sys.executable, str(STUB_CLAUDE), "-p",
                           f"Read {brief} and follow the instructions in it exactly. Go."],
                          cwd=tmp_path, capture_output=True, text=True, timeout=AM_TIMEOUT)
    assert proc.returncode == 1, proc.stdout + proc.stderr
    assert "stub claude: no behaviour for phase 'resolve'" in proc.stderr, proc.stderr
    assert proc.stdout == "" and not result.exists()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q`
Expected: collection ERROR `ModuleNotFoundError: No module named 'stub_claude'`.

- [ ] **Step 3: Write the stub**

Create `tests/contract/stub_claude.py`:

```python
"""A stub `claude` for the contract tests: writes each agent phase's result from the brief alone.

Test infrastructure, standard library only, run as a script under a `#!<python>` line. The
brief path is the value after `-p` (`Read <path> and follow the instructions in it exactly.`);
the phase is the brief's `# phase: <name>` header, the result path the line after `write your
result as valid JSON to exactly this path:` in `## Result contract`, the JSON Schema that
section's ```json fence, and the phase inputs its `## <name>` sections. The result is every
schema property at its type's zero value, then the fields the phase's gates need. A field the
schema lacks, or a phase with no behaviour here, exits 1 naming it on stderr. On success it
prints exactly `stub claude ok phase=<phase>` and exits 0.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

PROMPT_SENTENCE = re.compile(r"^Read (?P<path>.+?) and follow the instructions in it exactly\.")
PHASE_HEADER = re.compile(r"^# phase: (?P<phase>\S+)$", re.M)
RESULT_HEADING = "## Result contract"
RESULT_PATH_LEAD = "write your result as valid JSON to exactly this path:"
SCHEMA_FENCE = re.compile(r"```json\n(?P<schema>.*?)\n```", re.S)
SECTION = re.compile(r"^## (?P<name>.+)$", re.M)
# Longer than am's minimum summary length (60).
SUMMARY = ("the stub claude wrote this result from the brief on disk alone: the schema's zero "
           "values plus the fields this phase's gates read")
# The scratch HOME has no git identity.
GIT_IDENTITY = ("-c", "user.name=stub", "-c", "user.email=stub@example.com")


class StubError(Exception):
    pass


def brief_path(argv):
    if "-p" not in argv or argv.index("-p") + 1 >= len(argv):
        raise StubError(f"no -p argument in argv: {argv!r}")
    sentence = argv[argv.index("-p") + 1]
    found = PROMPT_SENTENCE.match(sentence)
    if found is None:
        raise StubError(f"the -p text is not the brief sentence: {sentence!r}")
    return Path(found.group("path"))


def phase_of(text):
    found = PHASE_HEADER.search(text)
    if found is None:
        raise StubError("the brief carries no `# phase:` header")
    return found.group("phase")


def contract_of(text):
    start = text.find(RESULT_HEADING)
    if start < 0:
        raise StubError(f"the brief has no {RESULT_HEADING!r} section")
    return text[start:]


def result_path_of(text):
    contract = contract_of(text)
    lead = contract.find(RESULT_PATH_LEAD)
    if lead < 0:
        raise StubError(f"the result contract does not say {RESULT_PATH_LEAD!r}")
    for line in contract[lead + len(RESULT_PATH_LEAD):].splitlines():
        if line.strip():
            return Path(line.strip())
    raise StubError("the result contract names no path")


def schema_of(text):
    found = SCHEMA_FENCE.search(contract_of(text))
    if found is None:
        raise StubError("the result contract embeds no ```json schema fence")
    return json.loads(found.group("schema"))


def sections(text):
    """Every `## <name>` section after the `# phase:` header; the first of a name wins."""
    head = PHASE_HEADER.search(text)
    body = text[head.end():] if head is not None else text
    marks = list(SECTION.finditer(body))
    found = {}
    for index, mark in enumerate(marks):
        end = marks[index + 1].start() if index + 1 < len(marks) else len(body)
        found.setdefault(mark.group("name"), body[mark.end():end].strip("\n"))
    return found


def section(found, name, phase):
    if name not in found:
        raise StubError(f"the {phase!r} brief has no `## {name}` section")
    return found[name].strip()


def zero_payload(schema, defs=None):
    """Every property of `schema` at its type's zero value; `$ref` resolves through `$defs`."""
    table = schema.get("$defs", {}) if defs is None else defs
    return {name: zero_value(node, table) for name, node in schema.get("properties", {}).items()}


def zero_value(node, defs):
    if "$ref" in node:
        name = node["$ref"].rsplit("/", 1)[-1]
        if name not in defs:
            raise StubError(f"the schema references unknown $def {name!r}")
        return zero_payload(defs[name], defs)
    if "anyOf" in node:
        if any(option.get("type") == "null" for option in node["anyOf"]):
            return None
        return zero_value(node["anyOf"][0], defs)
    kind = node.get("type")
    if kind == "object":
        return zero_payload(node, defs)
    if kind == "array":
        return []
    if kind == "string":
        return ""
    if kind in ("integer", "number"):
        return 0
    if kind == "boolean":
        return False
    raise StubError(f"no zero value for schema node {node!r}")


def override(payload, **fields):
    """Set each field, refusing a name the schema did not produce."""
    for name, value in fields.items():
        if name not in payload:
            raise StubError(f"the schema has no field {name!r} (it has: {sorted(payload)})")
        payload[name] = value
    return payload


def git(*args):
    proc = subprocess.run(["git", *GIT_IDENTITY, *args], capture_output=True, text=True)
    if proc.returncode != 0:
        raise StubError(f"git {' '.join(args)} failed: {proc.stderr.strip() or proc.stdout.strip()}")
    return proc.stdout


def write_document(relative, kind):
    path = Path(relative)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"# {kind} for this card\n", encoding="utf-8")


def build_result(phase, payload, found):
    if phase == "explore":
        suite = json.loads(section(found, "verification", phase))
        override(payload["verification"], full_suite=suite, typecheck="", lint=[])
        return override(payload, refused=False, reason=None, summary=SUMMARY,
                        verification=payload["verification"])
    if phase in ("validate_spec", "validate_plan"):
        return override(payload, blockers=False, reason=None, summary=SUMMARY)
    if phase == "spec":
        relative = section(found, "spec_path", phase)
        write_document(relative, "spec")
        return override(payload, path=relative, note=None)
    if phase == "plan":
        relative = section(found, "plan_path", phase)
        write_document(relative, "plan")
        return override(payload, path=relative, self_reviewed=True, note=None)
    if phase == "implement":
        digest = section(found, "plan_hash", phase)
        relative = section(found, "plan_path", phase)
        Path("IMPLEMENTATION.md").write_text(f"# implementation of {relative}\n", encoding="utf-8")
        git("add", "-A")
        resumed = git("status", "--porcelain").strip() == ""
        if not resumed:
            git("commit", "-m", f"feat: implement this card\n\nPlan-Hash: {digest}")
        return override(payload, blocked=False, blocked_reason=None, resumed=resumed,
                        plan_hash=digest, report=SUMMARY)
    if phase == "review":
        base = section(found, "base_branch", phase)
        digest = section(found, "plan_hash", phase)
        revisions = git("rev-list", f"{base}..HEAD").split()
        tagged = [revision for revision in revisions
                  if f"Plan-Hash: {digest}" in git("show", "-s", "--format=%B", revision)]
        return override(payload, findings=[], unresolved_blockers=[], fix_summary=SUMMARY,
                        porcelain=git("status", "--porcelain").strip(),
                        commit_count=len(revisions), tagged_count=len(tagged), plan_hash=digest)
    raise StubError(f"no behaviour for phase {phase!r}")


def main(argv):
    text = brief_path(argv).read_text(encoding="utf-8")
    phase = phase_of(text)
    result_path = result_path_of(text)
    payload = build_result(phase, zero_payload(schema_of(text)), sections(text))
    result_path.parent.mkdir(parents=True, exist_ok=True)
    result_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"stub claude ok phase={phase}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except StubError as error:
        print(f"stub claude: {error}", file=sys.stderr)
        sys.exit(1)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k stub_claude`
Expected: 3 passed.

Then: `timeout 300 uv run --with pytest python3 -m pytest tests/contract -q`
Expected: all pass (`test_am_fixtures.py` still imports `test_am_shapes`, which now imports `stub_claude` from the same dir).

- [ ] **Step 5: Commit**

```bash
git add tests/contract/stub_claude.py tests/contract/test_am_shapes.py
git commit -m "test(contract): a stdlib stub claude that writes each agent phase's result"
```

---

### Task 5: `finished_run` — a story run to `done` in the throwaway journal

**Files:**
- Modify: `tests/contract/test_am_shapes.py` (module docstring lines 1-13; append at end of file)

**Interfaces:**
- Consumes: `am`, `story_board` fixtures (existing; `story_board.s1: str`, `story_board.s1_subtasks: list[str]`, bin dir `tmp_path / "bin"` is `am.env["PATH"]`), `STUB_CLAUDE` (Task 4).
- Produces:
  - `stub_executable(path: Path, body: str) -> None` — `body` as an executable at `path` with a `#!<realpath of sys.executable>` first line.
  - fixture `finished_run` → `SimpleNamespace(id: str, card: str, root: Path)` — the run id, `story_board.s1_subtasks[0]`, and `tmp_path`.
  - `phases_of(am, run, card) -> dict[str, dict]` — `am status RUN`'s phases of subtask `card`, keyed by phase name.

- [ ] **Step 1: Write the failing test**

Append to `tests/contract/test_am_shapes.py`:

```python


def test_finished_run_reaches_verify_and_is_done(am, finished_run):
    phases = phases_of(am, finished_run, finished_run.card)
    assert [(attempt["n"], attempt["status"]) for attempt in phases["review"]["attempts"]] \
        == [(1, "ok")], phases["review"]
    assert phases["verify"]["status"] == "done", phases["verify"]
    assert phases["verify"]["attempts"] == [], phases["verify"]
    assert phases["worktree"]["attempts"] == [], phases["worktree"]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k finished_run`
Expected: ERROR `fixture 'finished_run' not found`.

- [ ] **Step 3: Write the fixture and helpers**

Insert directly above `def test_finished_run_reaches_verify_and_is_done(...)`:

```python


def stub_executable(path, body):
    """`body` as an executable at `path`, run by this interpreter."""
    path.write_text(f"#!{os.path.realpath(sys.executable)}\n{body}", encoding="utf-8")
    path.chmod(0o755)


@pytest.fixture
def finished_run(am, story_board, tmp_path):
    """Story S1 run to done through the real am: the bin dir also holds the stub `claude`
    and `verify-ok` (prints `verified`, exits 0), the run's only verify command."""
    bin_dir = tmp_path / "bin"
    stub_executable(bin_dir / "claude", STUB_CLAUDE.read_text(encoding="utf-8"))
    stub_executable(bin_dir / "verify-ok", 'print("verified")\n')
    proc = am.run("run", "--story", story_board.s1, "--branch-prefix", "p", "--verify",
                  "verify-ok", "--repo-dir", am.repo)
    output = f"stdout={proc.stdout!r} stderr={proc.stderr!r}"
    if proc.returncode != 0:
        pytest.fail(f"am run of story S1 exited {proc.returncode}: {output}")
    runs = am.run("runs", "--repo-dir", am.repo)
    rows = json.loads(runs.stdout)["data"]["runs"] if runs.returncode == 0 else None
    if not rows or len(rows) != 1 or rows[0]["status"] != "done":
        pytest.fail(f"am run of story S1 did not finish as one done run: runs={runs.stdout!r} "
                    f"{output}")
    return SimpleNamespace(id=rows[0]["id"], card=story_board.s1_subtasks[0], root=tmp_path)


def phases_of(am, run, card):
    """`am status RUN`'s phases of subtask `card`, by name."""
    proc = am.run("status", run.id, "--repo-dir", am.repo)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    subtasks = [subtask for story in json.loads(proc.stdout)["data"]["stories"]
                for subtask in story["subtasks"] if subtask["card_id"] == card]
    assert len(subtasks) == 1, proc.stdout
    return {phase["name"]: phase for phase in subtasks[0]["phases"]}
```

- [ ] **Step 4: Update the module docstring**

Replace the module docstring's last paragraph:

```python
Story tests build a real git repo and brd board under tmp_path and run am with
a PATH holding only am, brd and git, so no agent CLI is reachable. When am is
present they fail, never skip, if am run lacks --story or brd or git is absent.
"""
```

with:

```python
Story tests build a real git repo and brd board under tmp_path and run am with
a PATH holding only am, brd and git, so no agent CLI is reachable. When am is
present they fail, never skip, if am run lacks --story or brd or git is absent.

Finished-run tests add to that PATH the stub claude (stub_claude.py, run by
this interpreter) and verify-ok, so story S1 runs to done; they fail, never
skip, when it does not. Their am logs --follow captures, with the scratch root
rewritten to /home/user, equal tests/fixtures/am/logs-follow-agent.jsonl,
logs-follow-step.jsonl and logs-follow-refusal.json; with AM_RECORD_FIXTURES=1
the captures are written there instead.
"""
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "finished_run or story_board"`
Expected: 2 passed (`test_story_board_reaches_only_am_brd_and_git_and_its_own_repo` still sees only `am`, `brd`, `git`: the stubs are added only by `finished_run`). If `finished_run` fails, its message carries am run's stdout/stderr; a `stub claude: ...` line there names the phase or field to fix in `stub_claude.py`.

- [ ] **Step 6: Commit**

```bash
git add tests/contract/test_am_shapes.py
git commit -m "test(contract): finished_run drives a story to done with the stub claude"
```

---

### Task 6: the agent attempt's stream and `logs-follow-agent.jsonl`

**Files:**
- Modify: `tests/contract/test_am_shapes.py` (append at end of file)
- Create (by recording): `tests/fixtures/am/logs-follow-agent.jsonl`

**Interfaces:**
- Consumes: `finished_run` (Task 5), `json_lines`, `follow_stream_text` (Task 3), `normalize`, `recorded_fixture`, `SCRATCH_HOME` (Task 2).
- Produces:
  - `follow(am, run, card, *selector) -> subprocess.CompletedProcess`
  - `jsonl(lines: list[dict]) -> str` — one compact JSON object per line, each ending `\n`.
  - `hello_shape(hello: dict, phase: str) -> dict` — `hello` with `path` replaced by a bool: whether it is `/home/user/data/agent-manager/runs/<run>/<card>/<phase>.1/stdout.log`.
  - `assert_stream_matches_fixture(lines: list[dict], name: str, phase: str) -> None`

- [ ] **Step 1: Write the failing tests**

Append to `tests/contract/test_am_shapes.py`:

```python


def test_hello_shape_accepts_only_a_normalized_attempt_log_path():
    hello = {"event": "logs", "offset": 0, "schema": 1,
             "path": "/home/user/data/agent-manager/runs/r1/c1/review.1/stdout.log"}
    assert hello_shape(hello, "review") == {**hello, "path": True}
    assert hello_shape(hello, "verify")["path"] is False
    assert hello_shape({**hello, "path": "/tmp/x/data/agent-manager/runs/r1/c1/review.1/stdout.log"},
                       "review")["path"] is False


def test_logs_follow_of_an_agent_attempt_prints_hello_chunks_and_end(am, finished_run):
    proc = follow(am, finished_run, finished_run.card, "--phase", "review", "--attempt", "1")
    assert proc.returncode == 0, proc.stdout + proc.stderr
    lines = json_lines(proc.stdout)
    text = follow_stream_text(lines, f"{am.data}/agent-manager/runs/",
                              f"/{finished_run.card}/review.1/stdout.log")
    assert text == "stub claude ok phase=review\n", lines
    assert lines[-1]["status"] == "ok", lines[-1]
    assert_stream_matches_fixture(normalize(lines, finished_run.root),
                                  "logs-follow-agent.jsonl", "review")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "hello_shape or agent_attempt"`
Expected: 2 FAIL with `NameError` (`hello_shape`, `follow`).

- [ ] **Step 3: Write the helpers**

Insert directly above `def test_hello_shape_accepts_only_a_normalized_attempt_log_path():`:

```python


def follow(am, run, card, *selector):
    """`am logs RUN CARD *selector --follow` on a terminal attempt, which exits by itself."""
    return am.run("logs", run.id, card, *selector, "--follow", "--repo-dir", am.repo)


def jsonl(lines):
    """`lines` as one compact JSON object per line, each ending in a newline."""
    return "".join(json.dumps(line, separators=(",", ":"), ensure_ascii=False) + "\n"
                   for line in lines)


def hello_shape(hello, phase):
    """`hello` with its path replaced by whether it reads
    /home/user/data/agent-manager/runs/<run>/<card>/<phase>.1/stdout.log."""
    shape = re.compile(rf"{SCRATCH_HOME}/data/agent-manager/runs/[^/]+/[^/]+/"
                       rf"{re.escape(phase)}\.1/stdout\.log")
    return {**hello, "path": bool(shape.fullmatch(str(hello.get("path"))))}


def assert_stream_matches_fixture(lines, name, phase):
    """The normalized stream `lines` equals tests/fixtures/am/`name` line for line; the
    hello's path is compared by shape only."""
    fixture = [json.loads(line) for line in recorded_fixture(name, jsonl(lines)).splitlines()]
    assert hello_shape(lines[0], phase)["path"] is True, lines[0]
    assert [hello_shape(fixture[0], phase), *fixture[1:]] == \
        [hello_shape(lines[0], phase), *lines[1:]], (name, fixture, lines)
```

- [ ] **Step 4: Run the tests and see the fixture missing**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "hello_shape or agent_attempt"`
Expected: `test_hello_shape_...` passes; `test_logs_follow_of_an_agent_attempt_...` FAILS with `.../tests/fixtures/am/logs-follow-agent.jsonl is missing: record it with AM_RECORD_FIXTURES=1`.

- [ ] **Step 5: Record the fixture**

Run: `AM_RECORD_FIXTURES=1 timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k agent_attempt`
Expected: 1 passed. Then `cat tests/fixtures/am/logs-follow-agent.jsonl` shows exactly three lines (run id and card id differ):

```
{"event":"logs","offset":0,"path":"/home/user/data/agent-manager/runs/<RUN>/<CARD>/review.1/stdout.log","schema":1}
{"offset":0,"text":"stub claude ok phase=review\n"}
{"event":"end","status":"ok"}
```

If any line holds a `/tmp/` path or differs otherwise, stop: do not edit the file by hand.

- [ ] **Step 6: Run the test without recording to verify it passes against the committed fixture**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "hello_shape or agent_attempt"`
Expected: 2 passed.

- [ ] **Step 7: Commit**

```bash
git add tests/contract/test_am_shapes.py tests/fixtures/am/logs-follow-agent.jsonl
git commit -m "test(contract): pin am logs --follow of an agent attempt and record its fixture"
```

---

### Task 7: the step's stream and `logs-follow-step.jsonl`

**Files:**
- Modify: `tests/contract/test_am_shapes.py` (append at end of file)
- Create (by recording): `tests/fixtures/am/logs-follow-step.jsonl`

**Interfaces:**
- Consumes: `finished_run` (Task 5), `json_lines`, `follow_stream_text` (Task 3), `normalize` (Task 2), `follow`, `assert_stream_matches_fixture` (Task 6).
- Produces: nothing new.

- [ ] **Step 1: Write the test**

Append to `tests/contract/test_am_shapes.py`:

```python


def test_logs_follow_of_a_step_prints_hello_chunks_and_end(am, finished_run):
    proc = follow(am, finished_run, finished_run.card, "--phase", "verify")
    assert proc.returncode == 0, proc.stdout + proc.stderr
    lines = json_lines(proc.stdout)
    text = follow_stream_text(lines, f"{am.data}/agent-manager/runs/",
                              f"/{finished_run.card}/verify.1/stdout.log")
    assert text == "==> verify-ok (exit 0)\nverified\n", lines
    assert lines[-1]["status"] == "ok", lines[-1]
    assert_stream_matches_fixture(normalize(lines, finished_run.root),
                                  "logs-follow-step.jsonl", "verify")
```

(No `--attempt`: a step is addressed by `--phase` alone.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "a_step_prints"`
Expected: FAIL with `.../tests/fixtures/am/logs-follow-step.jsonl is missing: record it with AM_RECORD_FIXTURES=1`.

- [ ] **Step 3: Record the fixture**

Run: `AM_RECORD_FIXTURES=1 timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "a_step_prints"`
Expected: 1 passed. Then `cat tests/fixtures/am/logs-follow-step.jsonl` shows exactly (ids differ):

```
{"event":"logs","offset":0,"path":"/home/user/data/agent-manager/runs/<RUN>/<CARD>/verify.1/stdout.log","schema":1}
{"offset":0,"text":"==> verify-ok (exit 0)\nverified\n"}
{"event":"end","status":"ok"}
```

If it differs, stop: do not edit the file by hand.

- [ ] **Step 4: Run the test without recording to verify it passes**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "a_step_prints"`
Expected: 1 passed.

- [ ] **Step 5: Commit**

```bash
git add tests/contract/test_am_shapes.py tests/fixtures/am/logs-follow-step.jsonl
git commit -m "test(contract): pin am logs --follow of a step and record its fixture"
```

---

### Task 8: the refusal for a step without a log and `logs-follow-refusal.json`

**Files:**
- Modify: `tests/contract/test_am_shapes.py` (append at end of file)
- Create (by recording): `tests/fixtures/am/logs-follow-refusal.json`

**Interfaces:**
- Consumes: `finished_run` (Task 5), `json_lines` (Task 3), `normalize`, `recorded_fixture` (Task 2), `follow`, `jsonl` (Task 6).
- Produces: `masked_card(refusal: dict) -> dict` — `refusal` with `card '<id>'` in `error.message` replaced by `card '<CARD>'`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/contract/test_am_shapes.py`:

```python


def test_masked_card_replaces_only_the_card_id_in_the_message():
    message = "phase 'worktree' of card 'c-1' has no recorded attempt yet"
    refusal = {"ok": False, "error": {"type": "UnknownAttemptError", "message": message}}
    assert masked_card(refusal) == {"ok": False, "error": {
        "type": "UnknownAttemptError",
        "message": "phase 'worktree' of card '<CARD>' has no recorded attempt yet"}}


def test_logs_follow_of_a_step_without_a_log_is_one_refusal(am, finished_run):
    proc = follow(am, finished_run, finished_run.card, "--phase", "worktree")
    assert proc.returncode == 3, proc.stdout + proc.stderr
    [refusal] = json_lines(proc.stdout)
    assert set(refusal) == {"ok", "error"} and refusal["ok"] is False, refusal
    assert set(refusal["error"]) == {"type", "message"}, refusal
    assert refusal["error"]["type"] == "UnknownAttemptError", refusal
    assert "'worktree'" in refusal["error"]["message"], refusal
    assert "has no recorded attempt yet" in refusal["error"]["message"], refusal
    capture = normalize(refusal, finished_run.root)
    fixture = json.loads(recorded_fixture("logs-follow-refusal.json", jsonl([capture])))
    assert masked_card(fixture) == masked_card(capture), (fixture, capture)
```

(`[refusal] = ...` fails unless stdout is exactly one line; `set(refusal) == {"ok", "error"}` means no `"event"` key, so no stream line was printed.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "masked_card or without_a_log"`
Expected: `test_masked_card_...` FAILS with `NameError: name 'masked_card' is not defined`; `test_logs_follow_of_a_step_without_a_log_...` FAILS with `.../tests/fixtures/am/logs-follow-refusal.json is missing: record it with AM_RECORD_FIXTURES=1`.

- [ ] **Step 3: Write the helper**

Insert directly above `def test_masked_card_replaces_only_the_card_id_in_the_message():`:

```python


def masked_card(refusal):
    """`refusal` with the card id in its error message replaced by <CARD>."""
    message = re.sub(r"card '[^']*'", "card '<CARD>'", refusal["error"]["message"])
    return {**refusal, "error": {**refusal["error"], "message": message}}
```

- [ ] **Step 4: Record the fixture**

Run: `AM_RECORD_FIXTURES=1 timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "masked_card or without_a_log"`
Expected: 2 passed. Then `cat tests/fixtures/am/logs-follow-refusal.json` shows exactly one line (card id differs):

```
{"error":{"message":"phase 'worktree' of card '<CARD>' has no recorded attempt yet","type":"UnknownAttemptError"},"ok":false}
```

If it differs, stop: do not edit the file by hand.

- [ ] **Step 5: Run the tests without recording to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "masked_card or without_a_log"`
Expected: 2 passed.

- [ ] **Step 6: Run the full gate**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/contract tests/architecture -q`
Expected: all pass (the module adds ~3 s per `finished_run` test, ~40 s for `test_am_shapes.py` in total).

Run: `timeout 600 bash tests/run.sh`
Expected: pytest all passed, every QML test `Totals: ... 0 failed`, exit 0.

Run: `git status --porcelain`
Expected: nothing under `tests/fixtures/am/` other than the three committed files is new or modified (the recording runs wrote only those).

- [ ] **Step 7: Commit**

```bash
git add tests/contract/test_am_shapes.py tests/fixtures/am/logs-follow-refusal.json
git commit -m "test(contract): pin the am logs --follow refusal for a step without a log"
```

---

## Spec coverage (self-review)

| spec item | task |
|---|---|
| B1 help lists `--follow`, `--since-offset`; helper `missing_logs_follow_options`; fail with reinstall hint | Task 1 |
| B2 `finished_run` (stub `claude`, `verify-ok`, `am run --story ... --verify verify-ok`, fails with am's output unless exit 0 and one `done` run, returns `id`/`card`/`root`); `story_board` unchanged | Task 5 |
| B3 stub `claude` (argv `-p`, phase header, result path, schema fence, zero payload, per-phase fields, refusal of unknown field and phase, single stdout line) | Task 4 |
| B4 agent attempt stream (hello keys/offset/schema/hermetic path, contiguous byte offsets, joined text, end `ok`, no `ok` key) | Tasks 3, 6 |
| B5 step stream, no `--attempt`, `verify.1` path, `==> verify-ok (exit 0)\nverified\n` | Tasks 3, 7 |
| B6 refusal: exit 3, one line, `{ok, error}`, `{type, message}`, `UnknownAttemptError`, `'worktree'`, `has no recorded attempt yet` | Task 8 |
| B7 normalization to `/home/user`; `.jsonl` compact with trailing newline; hello compared by shape; refusal compared with `<CARD>`; no `_note`; `AM_RECORD_FIXTURES=1` writes, unset + missing fails naming both | Tasks 2, 6, 7, 8 |
| Not added to `FIXTURE_NAMES` / `amFixtures.js` | Global Constraints |
| Error path: `--follow` hangs → `am.run` timeout | existing `am` fixture (`AM_TIMEOUT`); `follow` uses `am.run` |
| Tests table: `test_logs_help_lists_the_follow_options`, `test_missing_logs_follow_options_names_each_missing_option`, `test_finished_run_reaches_verify_and_is_done`, the three `test_logs_follow_of_...`, `test_follow_stream_checker_names_the_line_that_drifted` (a)-(d), `test_normalize_rewrites_only_the_scratch_root` | Tasks 1, 2, 3, 5, 6, 7, 8 |
<!-- task-pipeline: validated -->
