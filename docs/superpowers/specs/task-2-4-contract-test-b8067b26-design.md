# 2.4 Contract test pinning am's JSON shapes (card b8067b26)

Parent story: 92b4d150 "Run backend helpers" (milestone 4bf4fb2f). Blocked by 2.3 (4e4ae17d), which is done. Narrows `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md`, Testing section: "tests/contract/test_am_shapes.py: runs the installed am against a throwaway XDG_DATA_HOME and pins the runs, status and watch shapes; skipped when am is absent".

## Scope

One new file: `tests/contract/test_am_shapes.py`. There is no production code. It checks that the installed `am` binary still prints the JSON shapes the `core/backend/runs/*` helpers parse. It mirrors `tests/contract/test_brd_shapes.py` in structure and style.

Out of scope:
- Anything under `core/backend/runs/` or `tests/core/backend/runs/`. Those belong to siblings 2.1 to 2.3, which use stub-am tests.
- `am logs`, `pause`, `resume`, `cancel`.
- am's SQLite. The plugin uses only documented am commands and journal schema 1.
- Edits to `docs/architecture.md`. One optional change is allowed: the "Tests" bullet that documents `python3 -m pytest tests/contract -q` may also mention am.

## Hermetic setup

- Module docstring: the test runs the installed am against a throwaway HOME, XDG_DATA_HOME and XDG_STATE_HOME under `tmp_path`, so the user's real runs are never read or written. The module is skipped when am is absent.
- `pytestmark = pytest.mark.skipif(shutil.which("am") is None, reason="am is not installed here")`.
- Fixture: start from `dict(os.environ)`, then set `HOME=tmp/home` (created with mkdir), `XDG_DATA_HOME=tmp/data` and `XDG_STATE_HOME=tmp/state`. It also provides a repo dir `R` under `tmp_path` and a `run(*args)` helper that calls `subprocess.run(["am", *args], env=env, capture_output=True, text=True)`. The helper returns the completed process, and each test asserts the exit code itself, because the error-path test expects rc 3.
- Journal fixture writer: writes `$XDG_DATA_HOME/agent-manager/runs/<run_id>/journal.jsonl` with one JSON object per line. Each line has the same shape as `store.JournalLine` dumps in `/home/mtts/Code/agent-manager/tests/test_cli.py` (`_write_watch_journal`, around lines 7941-7962). The test writes the JSON by hand and does not import am. Example line: `{"seq":1,"ts":"2026-10-02T12:00:00+00:00","run_id":"run-a","event":"phase_upsert","card":"c1","phase":"implement","attempt":1,"payload":{"status":"started"}}`.
- The test file must not define `emit`, `inside`, `write_atomic`, `split_frontmatter` or `frontmatter_of`. This is the architecture duplicate rule. `tests/architecture` must pass unchanged.

## Observable behavior pinned

1. `am runs --repo-dir R` with no data dir: rc 0. The parsed stdout equals `{"ok": true, "data": {"runs": []}}` exactly.
2. `am status nope --repo-dir R`: rc 3. The parsed stdout has `ok is False`, `error.type == "UnknownRunError"`, and a non-empty string `error.message`. The message text is not pinned because it embeds the repo path.
3. `am watch --all` against a hand-written journal of one or more lines: rc 0. stdout is `{"ok": true, "data": {"events": [...]}}`. Each event has exactly the key set `{attempt, card, event, payload, phase, run_id, seq, story, ts}`. `story` is `null` when absent from the source line. `ts` ends in `Z` (normalised from `+00:00`). `seq`, `run_id`, `event`, `card`, `phase`, `attempt` and `payload` round-trip the written values.
4. `am watch --all --follow` against the same journal is started with `Popen(stdout=PIPE, text=True)`.
   - Line 1 is the hello line. It parses to an object with `event == "watch"`, `schema == 1`, `am` a non-empty string (the version) and `runs_dir` a string.
   - Lines 2 onward are journal lines with the same key set and normalisation as in test 3.
   - The test reads only the number of lines it expects. Each read is bounded by a timeout (for example a reader thread or `select` with a deadline), so a silent am fails the test instead of hanging it.
   - The process is always terminated, and killed if it does not exit, in a `finally` block.

The plugin ignores unknown journal events and keys. The tests check that the keys above are present and correct; they do not reject extra keys, except in test 3's exact key-set check, which pins today's schema 1 line.

## Error paths

- am missing: the whole module is skipped.
- An am refusal in test 2 must be exit 3 with the error envelope. Any other rc fails the test, and the failure message includes stdout and stderr.
- A hung `--follow` fails on the timeout instead of blocking the suite.

## Test list

All tests belong in the contract tier, `tests/contract/test_am_shapes.py`. Per `docs/architecture.md` "Tests" and the run-monitor spec, contract tests own "the installed external CLI still speaks the JSON shape our parsers read". They use the real binary, a throwaway data dir, and skip when the binary is absent. None of them belong in `tests/core/backend/runs/`, which holds stub-am helper tests owned by the siblings.

- `test_runs_with_no_data_dir_is_an_empty_list` (contract)
- `test_status_of_an_unknown_run_refuses_with_exit_3_and_unknown_run_error` (contract)
- `test_watch_all_returns_the_events_envelope_with_journal_line_keys` (contract)
- `test_watch_all_follow_prints_a_hello_line_then_journal_lines` (contract)

## Note

Siblings 2.1 to 2.3 are marked done in brd. Their `core/backend/runs/` and `tests/core/backend/runs/` files exist in this worktree but not in the main checkout `/home/mtts/Code/omarchy-project-manager`, which has not merged them. This card does not depend on them because it calls `am` directly, and it must not edit them.
