# 3.2 runs-logs.py: takes the project root and passes --repo-dir — design

Card `f7473bf0`, a subtask of story `44b929b5` ("Attempt output from real am
logs"), blocked by `d6a2e642` (3.1, `logTail`, landed as `eb63dbe`). Parent
spec: `docs/superpowers/specs/2026-10-05-align-run-model-design.md` (below:
**parent**). Work breakdown item 3 (parent L327-328) lists "`logTail`,
`runs-logs.py --repo-dir`, `RunStore` passing the root, and a real-data flow
test": this subtask is `runs-logs.py --repo-dir` only.

## Goal

`am logs` resolves a run against `--repo-dir`, which defaults to `.`; from any
other directory am refuses with `UnknownRunError` (parent L58-60). The helper
sends no `--repo-dir` today (`core/backend/runs/runs-logs.py:46-48`), so every
logs fetch from the panel is `UnknownRunError` (parent L112). After this
subtask the helper takes the project root as its first argument and passes it
to am as `--repo-dir`, so a fetch works from any cwd.

## Inherited constraints

| constraint | source |
|---|---|
| `am logs RUN CARD --phase P --attempt N --repo-dir R` is the command; `--repo-dir` defaults to `.`; without it, from any other directory, am refuses with `UnknownRunError` | parent L55-60 |
| The defect: `runs-logs.py:44-48` builds the `am logs` argv without `--repo-dir`; every logs fetch is `UnknownRunError` | parent L112 |
| Decision 7: `runs-logs.py` takes the project root first and passes `--repo-dir` | parent L169-171 |
| Work item 3 splits into `logTail`, `runs-logs.py --repo-dir`, `RunStore` passing the root, a real-data flow test | parent L327-328 |
| Every unit test of the `runs-*` helpers builds am output from `tests/fixtures/am/` (`json.load` in Python); a hand-written am payload only for a synthetic edge case, with a `synthetic:` comment | parent L257-267, L269, card |
| Usage becomes `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT`; am's argv is `logs RUN CARD --phase PHASE --attempt ATTEMPT --repo-dir ROOT`; everything else unchanged | card |
| Tests in `tests/core/backend/runs/test_runs_logs.py`: argv pinned; the old 4 args is `Usage` | card |
| `docs/architecture.md` layering; `tests/architecture` passes | card |
| Docstrings and comments state the contract only, no narrative | card |
| `bash tests/run.sh` green; tests first | card |

Model: `core/backend/runs/runs-snapshot.py` already takes `<project_root>`
(`USAGE` L29, `len(argv) != 1` L122) and passes it verbatim as `--repo-dir`
(L112, L129); its test pins this with a project dir named `my proj; echo x`
(`tests/core/backend/runs/test_runs_snapshot.py:73`, `:174`, `:358-366`).

## Behavior

Command line: `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT`, exactly
five arguments.

1. **Usage.** Any argument count other than five (zero, four — the old form —,
   six, …) prints exactly one line
   `{"ok": false, "error": {"type": "Usage", "message": "usage: runs-logs.py <project_root> RUN CARD PHASE ATTEMPT"}}`
   and exits 2. am is not looked up and not run.
2. **am's argv.** With five arguments `ROOT RUN CARD PHASE ATTEMPT`, am is run
   once with exactly
   `["logs", RUN, CARD, "--phase", PHASE, "--attempt", ATTEMPT, "--repo-dir", ROOT]`
   after the executable: `--repo-dir` last, no `--pretty`, no other option.
3. **Verbatim.** All five arguments reach am as single argv elements, unchanged:
   spaces, shell metacharacters (`;`, `$(…)`, `&`) and a leading dash are not
   interpreted, split or validated. The helper does not check that `ROOT`
   exists or is a directory, does not normalise it, and does not `chdir` into
   it; am refuses a bad root itself (its envelope is passed through, rule 4).
4. **Unchanged.** Everything after the argv is as today: am's stdin is
   `/dev/null`; 60 s timeout (`AM_TIMEOUT = 60`); am's envelope printed as one
   JSON line whatever am's exit code (`ok` decides); `AmMissing` when am is not
   on PATH; `AmBadOutput` (message names `am logs` and am's exit code) when
   stdout is not a JSON object with a boolean `ok`; `HelperError` ("The logs
   snapshot failed: …") on a timeout or an am that cannot start; exit 0 on
   every path but Usage; exactly one JSON line on every path.

### Contract text

- Module docstring: the usage line is `runs-logs.py <project_root> RUN CARD
  PHASE ATTEMPT`; it runs `am logs RUN CARD --phase PHASE --attempt ATTEMPT
  --repo-dir ROOT`; the five arguments go to am verbatim. The sentence "No
  --repo-dir is sent: am resolves the run by id." is removed (it is false).
  The Usage bullet says "exactly five arguments".
- `USAGE = "usage: runs-logs.py <project_root> RUN CARD PHASE ATTEMPT"`.
- `logs_argv` takes the root and returns the argv of rule 2; its docstring
  states am's argv after the executable, with no "No --repo-dir" claim.
- `docs/architecture.md:199`: the `runs-logs.py` sentence becomes
  `` `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` is a one-shot `am logs RUN CARD --phase P --attempt N --repo-dir R` passthrough: a 60 s timeout, exactly one JSON line. ``
  (the false "no `--repo-dir` (am resolves the run by id)" clause goes; the
  rest of the paragraph is untouched). This keeps the architecture doc true
  for the code on this branch; the milestone's docs pass (parent L331) is not
  pre-empted.

## Tests

All in `tests/core/backend/runs/test_runs_logs.py`. Tier: pytest backend
helper, hermetic (fake `am` on a temp PATH serving `tests/fixtures/am/`, temp
HOME / XDG_DATA_HOME). Why this tier: the change is the helper's command line
and the argv it hands a subprocess; the fake am records argv in `calls.log`,
which is exactly the observable, and no QML, store or real am is involved.

Fixture setup: the `world` fixture gains `proj`, a temp directory named
`my proj; echo x` (as `test_runs_snapshot.py:73`), so every default call
carries a root that would break through a shell. The default argv becomes
`[str(world["proj"]), "r1", "c1", "implement", "2"]`; every caller of the old
module-level `ARGS` (`run()` default, the stdin test's `Popen`, the timeout
test's `guarded(...)`) uses it. am payloads keep coming from
`fixture("logs-attempt.json")` via `json.load`; existing `synthetic:` labels
stay. The fake am needs no change (it keys on the subcommand `logs`).

Changed tests (each fails against the current helper first):

- **`test_exact_am_argv`**: am called once with
  `["logs", "r1", "c1", "--phase", "implement", "--attempt", "2", "--repo-dir", <proj>]`;
  `"--pretty"` not in it. The old `"--repo-dir" not in made[0]` assertion is
  removed.
- **`test_args_reach_am_verbatim`**: root `str(world["tmp"] / "r$(id) & z")`
  (not created) plus the existing `["r 1; echo x", "c$(whoami)", "plan & review", "-1"]`; am gets
  `["logs", "r 1; echo x", "c$(whoami)", "--phase", "plan & review", "--attempt", "-1", "--repo-dir", <root>]`.
  Also shows the root is not checked for existence.
- **`test_missing_fixture_unknown_run`**: the recorded argv ends with
  `["--repo-dir", <proj>]` (full list as in `test_exact_am_argv`).
- **`test_usage_wrong_argc`** (parametrized): `[]` ("none"), the old four
  `["r1", "c1", "implement", "2"]` ("old-four"), the root plus three
  (`[proj, "r1", "c1", "implement"]`, "four-with-root"), and six
  (`[proj, "r1", "c1", "implement", "2", "extra"]`, "six") each exit 2 with
  exactly `{"ok": false, "error": {"type": "Usage", "message": "usage: runs-logs.py <project_root> RUN CARD PHASE ATTEMPT"}}`
  and `calls(world) == []`.

Unchanged tests, run with the new default argv and still green: capture
identity, ok passthrough, pretty-printed output to one line, refusal passthrough,
`ok` over exit code and stderr, large/unicode output, am ignores stdin,
non-JSON / non-object / no-`ok` → `AmBadOutput`, `AmMissing`, cannot start →
`HelperError`, timeout → `HelperError` (`AM_TIMEOUT == 60`).

Suite gate: `bash tests/run.sh` green, including `tests/architecture` (no new
component, no icon) and the QML store and flow tests, which stub `HelperRunner`
and so do not run the helper.

## Out of scope

- `core/stores/RunStore.qml` passing the project root to `logsRunner.run`
  (`:370` sends four arguments today), and the QML tests that pin that command
  (`tests/core/stores/tst_run_store.qml:17`, `tests/ui/tst_runs_flow.qml:221-222`):
  the "`RunStore` passing the root" subtask of this story (parent L327-328).
  Until it lands, a real panel fetch gets `Usage` instead of `UnknownRunError`;
  the QML tests stay green because they stub the runner.
- The real-data flow test of the whole chain: the same story's later subtask.
- `logTail` (3.1, done); `runs-snapshot.py`, `runs-watch.py`, `run-control.py`;
  cancel spellings and hello schemas (work item 4).
- ATTEMPT `0` / omitted `--attempt` (deterministic-phase logs; parent L316-317)
  and any validation of RUN, CARD, PHASE, ATTEMPT or ROOT by the helper.
- `README.md` and the rest of `docs/architecture.md` beyond the one sentence at
  `:199` (work item 5, parent L331).
