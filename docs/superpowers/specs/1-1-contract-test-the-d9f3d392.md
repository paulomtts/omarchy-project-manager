# 1.1 Contract test: the installed `am run --story` — design

Card: `d9f3d392` (subtask of story `5c0430d9`). Parent design:
`docs/superpowers/specs/2026-10-05-dispatch-story-level-design.md` (cited below as **S7**).

## Purpose

This is the milestone's precondition gate (S7 §"Precondition (checked, not assumed)", lines 12-18).
It pins what the **installed** `am` does for a story run, so every later subtask builds against
recorded behavior rather than against `am`'s own spec. It changes one file:
`tests/contract/test_am_shapes.py`. No plugin code changes.

## Observed behavior of the installed `am` (2026-10-06)

The spec author ran these commands against a throwaway board before writing this spec (installed
`am` is the editable uv tool from `/home/mtts/Code/agent-manager`, at commit `2acfa25`, which
includes `6639083 am run --story`). The tests below pin this behavior.

1. `am run --help` lists `--story`.
2. `am run --story <S1> --branch-prefix p --dry-run --repo-dir R` exits 0 and prints
   `{"ok": true, "data": {...}}` where `data` has exactly the keys
   `already_done`, `integrate`, `levels`, `max_concurrent`:
   - `already_done == []`, `integrate is None`, `max_concurrent == 1`;
   - `levels` has one entry: `{"level": 0, "concurrent": 1, "stories": [one story]}`;
   - that story is `{"story": S1, "title": "Story A", "root": "master", "subtasks": [...]}`;
   - each subtask has `id`, `title`, `status` (`"todo"`), `branch`, `base`. The first subtask's
     `base` is `"master"` (the base branch); the second's `base` is the first's `branch`
     (the stack). Branches start with `p/`.
3. **Both** entry points refuse the blocked story S2 with the same envelope:
   - `am run --story <S2> --branch-prefix p --dry-run --repo-dir R` → exit 3;
   - `am run --story <S2> --branch-prefix p --detach --allow-no-verification --repo-dir R` → exit 3;
   - payload `{"ok": false, "error": {"type": "StoryBlockedError", "message": <str>}}`;
     the message names the blocker story's id;
   - afterwards `am runs --repo-dir R` still returns `{"runs": []}` (nothing was written,
     S7 line 55-56).
   This answers S7's open point (lines 57-61): today the dry-run refuses, so the dialog's
   preview-refusal path is the one a user meets; the start-refusal path stays because
   `--detach` refuses too.
4. A real foreground story run with `claude` absent from the PATH,
   `am run --story <S1> --branch-prefix p --allow-no-verification --repo-dir R`, records the run
   and escalates in under a second at the first phase (`FileNotFoundError: ... 'claude'`; exit 1,
   `ok: true`, `data.escalated: true`). No agent is launched. `am runs --repo-dir R` then lists
   one row carrying `"story_id": S1`, `"milestone_id": M`, `"branch_prefix": "p"`, a non-empty
   `started_at` string, `"workflow": "milestone"` and `"status": "escalated"`. The installed `am`
   has no `project` key on the row yet (S7 line 94 expects the store change to add
   `project: {id, repo_dir}` later).
   Every side effect (worktree under `R/.claude/worktrees/`, branch, data dir) stays under the
   test's `tmp_path`.

## Required behavior of the test module

### Skip and fail rules

- The module keeps its existing `pytestmark` skip: the module skips **only** when `am` is not on
  the PATH (`shutil.which("am") is None`) (S7 line 16; card).
- When `am` is on the PATH and `am run --help` stdout does not contain `--story`, the test
  **fails** (never skips) with a message naming the missing option, e.g.
  `"the installed am has no --story option on am run (reinstall agent-manager: uv tool install --reinstall)"`.
- When `am` is present but `brd` or `git` is not on the PATH, the story-board fixture **fails**
  with a message naming the missing tool. It never skips: `am` cannot read a board without `brd`.
- The test never stubs, wraps or imports `am`. If it cannot pass against the installed `am`,
  the task stops and escalates (card; S7 lines 17-18).

### Hermetic story board (new fixture)

A new fixture, `story_board`, builds on the existing `am` fixture
(`tests/contract/test_am_shapes.py:25-39`) and produces, inside `tmp_path`:

- a tool dir `tmp_path / "bin"` holding symlinks to the resolved `am`, `brd` and `git`, and
  `am.env["PATH"]` set to that dir **only**. The `am` fixture's `run` closes over the same
  `env` dict, so every later `am.run` call uses it. Purpose: no agent CLI (`claude`, `codex`)
  is reachable, so a story run that is not refused escalates at its first phase instead of
  launching an agent. This holds for the `--detach` refusal test as well: if a future `am`
  stopped refusing there, its detached child would escalate at once instead of spending money.
- `am.repo` turned into a git repo on branch `master` with one empty commit (identity passed
  with `-c user.name=... -c user.email=...`, since `HOME` is throwaway).
- a brd board in `am.repo`, built with `brd` in `am.env` plus `BRD_AUTHOR=tester`, the same
  way as `tests/contract/test_brd_shapes.py:17-41` (last stdout line is the `{ok, data}` payload):
  `brd init --name contract`; milestone `M`; story `S1` (`--parent M`); story `S2`
  (`--parent M --blocked-by S1`); two subtasks under each story (`--parent S1` / `--parent S2`).
- returns a `SimpleNamespace` with `milestone`, `s1`, `s2` (ids) and `s1_subtasks`
  (the two subtask ids, in creation order).

### Tests (all in `tests/contract/test_am_shapes.py`, tier: contract)

Tier for every test: **contract**. They exist to catch drift between the plugin's assumptions
and the real installed `am`. A fake `am` (backend tier) cannot catch that, and the board must be
real because `am` reads it through `brd`.

1. `test_run_help_lists_the_story_option`: `am run --help` exits 0 and its stdout contains
   `--story`, else `pytest.fail` with the message above. This test does not use `story_board`.
   A missing `brd` must not mask the gate.
2. `test_story_dry_run_previews_one_level_with_no_integrate`: pins observation 2. Assert the
   exact `data` key set, `already_done == []`, `integrate is None`, one level, one story with
   `story == s1`, subtask ids `== s1_subtasks` as a set, the first subtask's `base == "master"`,
   and the second's `base` equal to the first's `branch`. Titles, branch strings and statuses
   other than these relations are not pinned (they are `am`'s naming).
3. `test_blocked_story_is_refused_at_dry_run_with_story_blocked_error`: pins observation 3
   (dry-run): exit 3, `ok is False`, `error.type == "StoryBlockedError"`, the message is a
   non-empty string containing `s1`.
4. `test_blocked_story_is_refused_at_a_detached_start_and_nothing_is_recorded`: pins
   observation 3 (`--detach`, with `--allow-no-verification`): same envelope assertions as
   test 3, then `am runs --repo-dir R` returns `{"ok": true, "data": {"runs": []}}`.
   The test's docstring records the contract: both the dry-run and the detached start refuse.
5. `test_a_story_run_row_carries_story_id`: runs observation 4's foreground command (its
   exit code and envelope are not pinned; it must finish within `AM_TIMEOUT`), then
   `am runs --repo-dir R`: exactly one row; `row["story_id"] == s1`,
   `row["milestone_id"] == milestone`, `row["branch_prefix"] == "p"`,
   `row["started_at"]` a non-empty string. The keys are checked as a **subset**
   (`{"id", "story_id", "milestone_id", "branch_prefix", "started_at"} <= set(row)`), not as
   an exact set, so the store change's `project` key does not break it. When `project` is
   present, it is a dict whose keys include `id` and `repo_dir` (S7 lines 92-96).

### Error paths covered

- `am` without `--story` → test 1 fails loudly. The other tests then fail on their own
  envelopes (`am` rejects the unknown option), which is acceptable. The gate message is in test 1.
- A hung `am` → `subprocess.TimeoutExpired` from the existing `AM_TIMEOUT` (30 s) fails the test.
- `am` stops refusing the blocked story at `--detach` → test 4 fails on the exit code. The
  restricted PATH makes the detached child escalate without an agent.

## Constraints

- Docstrings and comments state the contract only, no narrative (card). The module docstring
  is extended to say story tests build a real brd board and run `am` with a PATH holding only
  `am`, `brd` and `git`.
- `tests/architecture` must still pass (card). It is untouched by a contract-test change.
- Verification: `bash tests/run.sh` green (card). pytest runs through `uv run --with pytest`
  when `python3` lacks it (`tests/run.sh:12-17`).
- Follow the existing module's idiom: `am.run(...)`, `json.loads(proc.stdout)`, assertion
  messages `proc.stdout + proc.stderr` / `payload`.

## Out of scope

- Any plugin code: `core/domain/runs.js` (`dispatchPlan`, `previewSummary`,
  `dispatchDefaults`), `core/backend/runs/dispatch-preview.py`, `start-run.py`,
  `viewer-state.py` `prefixByMilestone`, `RunStore`, `DispatchDialog`, `CardDetailScreen`,
  `Shortcuts.qml` (S7 §Architecture lines 74-88). Those belong to sibling cards.
- Fake-`am` backend tests, `tst_runs.qml`, `tst_run_store.qml`, `tests/ui/` (S7 lines 97-105).
- Pinning the `project` key's presence (the store change is not in the installed `am`).
- Milestone, card or board dispatch contracts already covered by S3.
- Reinstalling or modifying `am`/agent-manager.

## Handoff to the planner

One task is enough: the fixture and the five tests ship together, and a reviewer cannot
usefully approve the fixture without the tests that use it. Follow the writing-plans format.
Write the tests first and run them against the installed `am` before considering anything
done. They are expected to pass at once (the behavior already exists); the TDD "red" step is
running test 1 with a deliberately misspelled option to see its failure message, then
restoring it.
