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
