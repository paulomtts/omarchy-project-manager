# 2.1 runs-logs.py: attempt 0 means am's newest (card e69a6c2d)

Parent: story d44f2afe. Milestone spec: `docs/superpowers/specs/2026-10-05-resume-recover-design.md`
(cited below as "design").

## Why

A failed deterministic step (for example `verify`) records no attempts in `am status`
(`attempts: []`), yet `am logs RUN CARD --phase verify` with no `--attempt` returns that
phase's newest recorded output (design, Problem, lines 48-56). Later subtasks select such a
step as "attempt 0" (design, Behaviour, lines 156-160; Architecture, line 245). This card
makes the helper translate attempt 0 into "no `--attempt`", so that output becomes reachable.

## Behaviour

`core/backend/runs/runs-logs.py <project_root> RUN CARD PHASE ATTEMPT`:

1. When `ATTEMPT` is exactly the string `0`, the helper runs
   `am logs RUN CARD --phase PHASE --repo-dir ROOT`, with no `--attempt` flag and no `0`
   anywhere in the argv (design, Architecture, lines 253-254).
2. Any other `ATTEMPT` value is passed verbatim, as today:
   `am logs RUN CARD --phase PHASE --attempt ATTEMPT --repo-dir ROOT`. Only the exact string
   `0` is special. `00`, `-0`, ` 0`, `+0`, `-1` and the empty string all go through
   unchanged, and am refuses them itself. The helper still validates nothing.
3. Everything else stays as it is (design, line 254: "Everything else unchanged (`am logs`
   keeps `--repo-dir`)"):
   - argument order;
   - `--repo-dir ROOT` last;
   - no shell, stdin `/dev/null`, 60 s timeout;
   - exactly one JSON line on every path;
   - envelope passthrough (`ok` decides, not the exit code);
   - the `AmMissing`, `AmBadOutput`, `HelperError` and `Usage` envelopes;
   - exit codes (0, or 2 for Usage);
   - the `USAGE` string (still five arguments).
4. With attempt 0, am's envelope is passed through unchanged, exactly as for any other
   attempt, and that includes an `ok: false` refusal when am has no output for the phase.
   Showing that error is the store's job (design, Errors table, line 294: "`am logs` has no
   output for the step → the pane's existing error line").

### Docstrings (contract only, no narrative)

- Module docstring:
  - The usage line stays.
  - The command sentence states both forms. With ATTEMPT `0`, no `--attempt` is sent, so am
    returns the phase's newest recorded output; this is how a step's output is read, because
    steps record no attempts in `am status`. Any other ATTEMPT is sent verbatim with
    `--attempt`.
  - Replace "The five arguments go to am verbatim" with a sentence that stays true: the
    arguments reach am unvalidated, attempt `0` is the one exception, and am refuses bad
    arguments itself.
  - The rest of the docstring is unchanged.
- `logs_argv` docstring: states the same rule. It returns am's argv after the executable,
  with `--attempt ATTEMPT` omitted when ATTEMPT is `"0"`, then `--repo-dir ROOT`.
- The module's one-line summary ("One attempt's output snapshot") may say "one attempt's (or
  the phase's newest) output snapshot". It must not describe history.

## Tests

All new tests go in `tests/core/backend/runs/test_runs_logs.py`. They are integration tier:
the real script runs as a subprocess against the file's existing hermetic fake `am` on a temp
PATH. This is the tier the file already uses, and the behaviour under test is the argv that
actually reaches the `am` executable. Use the existing helpers: `world`, `run`, `set_logs`,
`calls`, `logs_data`, and `RUN_ARGS`. Write the tests first.

1. `test_attempt_zero_sends_no_attempt_flag`: args `[proj, "r1", "c1", "verify", "0"]`. The
   assertions:
   - `calls(world) == [["logs", "r1", "c1", "--phase", "verify", "--repo-dir", proj]]`;
   - `"--attempt"` is not in the argv;
   - the ok envelope comes out unchanged;
   - the exit code is 0.
2. `test_nonzero_attempt_is_sent_verbatim`: parametrized over `"2"` and `"1"`. The argv is
   the full form with `"--attempt", <value>`. `test_exact_am_argv` already covers `"2"`; this
   test pins the contrast with 0 next to it.
3. `test_only_exact_zero_is_special`: parametrized over `"00"`, `"-0"`, `" 0"` and `""`.
   Each value arrives as `"--attempt", <value>`, unchanged. This keeps the "exact string"
   rule: the helper does not parse integers.
4. `test_attempt_zero_refusal_passed_through`: attempt `0`, and the fake am returns a
   synthetic `ok: false` envelope (labelled `# synthetic:`; no capture holds one) with exit 3.
   The output is that envelope, with exit 0.

The existing tests stay unchanged and must still pass: every existing argv assertion uses
attempt `2` or `-1`.

Verification: `bash tests/run.sh` must be green. That covers pytest, including
`tests/architecture`, and the QML tests.

## Out of scope

- `core/stores/RunStore.qml`:
  - `selectAttempt` accepting attempt 0;
  - opening the stop report's attempt;
  - the `(newest)` heading.

  These belong to the store/selection sibling cards (design, lines 262-265 and 313-314).
- `core/domain/runs.js` `stopReport` producing `attempt: 0` (done in story 1).
- `run-control.py` dropping `--repo-dir` from `am status` (design, lines 255-256; another
  card).
- Any other change to `runs-logs.py`'s behaviour, its usage text or its error types.
- Docs outside the two docstrings (`docs/architecture.md` and the README belong to the docs
  card).

## Constraints inherited

- `am logs` keeps `--repo-dir` (design, line 254).
- Only documented `am` commands are used, and am's database is never read (the module
  docstring today; design, Architecture).
- `docs/architecture.md` layering: the helper stays in `core/backend/runs/`, and
  `tests/architecture` must pass.
