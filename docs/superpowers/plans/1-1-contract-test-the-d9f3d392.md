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

---

# 1.1 Contract Test for `am run --story` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `tests/contract/test_am_shapes.py` so that it pins how the installed `am` handles a story run: the `--story` gate, the dry-run preview, the blocked-story refusal at both entry points, and the run row's story fields.

**Architecture:** One pytest module in the contract tier. A new `story_board` fixture builds on the existing `am` fixture. It narrows `am.env["PATH"]` to a `tmp_path/bin` dir that holds symlinks to `am`, `brd` and `git` only, and it removes any inherited `GIT_*` variables. It then turns `am.repo` into a git repo on `master` and builds a real brd board there: milestone M, story S1, story S2 blocked by S1, and two subtasks under each story. The tests call the real `am` through `am.run(...)` and assert on `json.loads(proc.stdout)`. No plugin code changes.

**Tech Stack:** Python 3 stdlib (`json`, `os`, `shutil`, `subprocess`, `types.SimpleNamespace`), pytest, the installed `am` (editable uv tool from `/home/mtts/Code/agent-manager`), `brd` and `git`.

**Spec:** `docs/superpowers/specs/1-1-contract-test-the-d9f3d392.md` (prepended verbatim above). Parent design: `docs/superpowers/specs/2026-10-05-dispatch-story-level-design.md`.

**Working directory for every command:** `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/dispatch-at-story-level-5d48ef7a/task-1-1-contract-test-the-d9f3d392`.

**pytest invocation:** this machine's `python3` has no pytest, so every pytest command below runs through `uv run --with pytest python3 -m pytest ...`, the same fallback `tests/run.sh:12-17` uses. If `python3 -c 'import pytest'` succeeds on your machine, `python3 -m pytest ...` works the same way.

**Pre-validated:** the planner ran the exact code in this plan against the installed `am` on 2026-10-06. All 11 tests in the module passed (the 4 existing ones plus the 7 new ones) in about 5 s, including with `GIT_DIR=/nonexistent` exported. With the gate's string misspelled, test 1 failed with the expected message.

## Global Constraints

- Only `tests/contract/test_am_shapes.py` changes. No plugin code changes (`core/**`, `ui/**`), and nothing under `tests/core`, `tests/ui` or any `tst_*.qml` changes.
- Module skip stays exactly: `pytestmark = pytest.mark.skipif(shutil.which("am") is None, reason="am is not installed here")`. Nothing else may skip.
- If `am` is present but `am run --help` lacks `--story`, test 1 **fails** with: `the installed am has no --story option on am run (reinstall agent-manager: uv tool install --reinstall)`.
- If `am` is present but `brd` or `git` is absent, the `story_board` fixture **fails** (`pytest.fail`) with a message naming the missing tool. It never skips.
- Never stub, wrap or import `am`. If a test cannot pass against the installed `am`, stop and escalate. Do not loosen the assertion.
- `am.env["PATH"]` is the `tmp_path / "bin"` dir **only**, holding symlinks to the resolved `am`, `brd`, `git`.
- Git identity is passed as `-c user.name=tester -c user.email=tester@example.com` because `HOME` is throwaway. The repo is on branch `master` with one empty commit.
- brd runs with `am.env` plus `BRD_AUTHOR=tester`. The last stdout line is the `{ok, data}` payload (as in `tests/contract/test_brd_shapes.py:27-32`).
- Branch prefix `p` everywhere. `AM_TIMEOUT = 30` (existing) bounds every `am` call.
- Docstrings and comments state the contract only, no narrative.
- The module must not define `emit`, `inside`, `write_atomic`, `split_frontmatter` or `frontmatter_of` (`tests/architecture/test_layers.py:231`).
- Idiom: `am.run(...)`, `json.loads(proc.stdout)`, assertion messages `proc.stdout + proc.stderr` / `payload` / `row`.
- Verification: `bash tests/run.sh` green.

## Review Focus

1. **Inherited `GIT_*` variables** (e.g. the suite run from a git hook, where `GIT_DIR`/`GIT_INDEX_FILE` point at the real repo, or a user `GIT_CONFIG_GLOBAL`). Expected: the fixture's git and the `am` it spawns touch only `tmp_path/repo`. The fixture deletes every `GIT_*` key from `am.env`. `test_story_board_reaches_only_am_brd_and_git_and_its_own_repo` asserts that none remain and that `git rev-parse --show-toplevel` inside `am.repo` is `am.repo` on `master`.
2. **An agent CLI (`claude`, `codex`) on the user's PATH.** Expected: a story run that is not refused escalates at its first phase and never launches an agent or spends money. The same test pins `am.env["PATH"] == str(tmp_path / "bin")` and that the dir holds exactly `am`, `brd`, `git`.
3. **`brd` or `git` missing while `am` is present.** Expected: a loud failure naming the tool, never a skip. `test_require_tool_fails_naming_the_missing_tool` pins `require_tool`'s message with `shutil.which` monkeypatched to return `None`. Only `shutil.which` is patched. `am` is not stubbed.
4. **A user `init.defaultBranch` other than `master`.** Expected: the base branch is still `master`, so `first["base"] == "master"` holds. The fixture uses `git init -b master` under a throwaway `HOME`. The same rev-parse assertion as item 1 checks this.
5. **An `am` that hangs, or a detached child that keeps running.** Expected: the test fails within `AM_TIMEOUT` instead of hanging the suite. `am.run` already passes `timeout=AM_TIMEOUT`, and the restricted PATH makes any detached child escalate at once. No new test is needed because the existing `run` closure covers it.

---

### Task 1: Story-run contract tests in `tests/contract/test_am_shapes.py`

**Files:**
- Modify: `tests/contract/test_am_shapes.py:1-8` (module docstring)
- Modify: `tests/contract/test_am_shapes.py` (append after line 167, the end of `test_watch_all_follow_prints_a_hello_line_then_journal_lines`)
- Test: `tests/contract/test_am_shapes.py` (the module is its own test)

**Interfaces:**
- Consumes: the existing `am` fixture (`tests/contract/test_am_shapes.py:25-39`), which returns `SimpleNamespace(run=run, env=env, repo=str(repo), data=tmp_path / "data")`. `run(*args)` calls `subprocess.run(["am", *args], env=env, capture_output=True, text=True, timeout=AM_TIMEOUT)` and closes over the **same** `env` dict, so changes to `am.env` take effect in later `am.run` calls.
- Produces (module-local):
  - `STORY_DATA_KEYS: set[str]`, `RUN_ROW_KEYS: set[str]`
  - `require_tool(name: str) -> str`: the realpath of `name` on the PATH, or `pytest.fail(...)`.
  - fixture `story_board(am, tmp_path) -> SimpleNamespace(milestone: str, s1: str, s2: str, s1_subtasks: list[str])`
  - `assert_story_blocked(proc: subprocess.CompletedProcess, blocker: str) -> None`

- [ ] **Step 1: Extend the module docstring**

Replace lines 1-8 of `tests/contract/test_am_shapes.py`:

```python
"""The installed am still speaks the JSON shapes core/backend/runs/* parse.

Hermetic: am runs with its own HOME, XDG_DATA_HOME and XDG_STATE_HOME under
tmp_path (am keeps runs under $XDG_DATA_HOME/agent-manager/runs), so the
user's real runs are never read or written. Journals are hand-written in the
shape am's store.JournalLine dumps (journal schema 1); am is never imported and
its SQLite is never read. Skipped when am is absent.
"""
```

with:

```python
"""The installed am still speaks the JSON shapes core/backend/runs/* parse.

Hermetic: am runs with its own HOME, XDG_DATA_HOME and XDG_STATE_HOME under
tmp_path (am keeps runs under $XDG_DATA_HOME/agent-manager/runs), so the
user's real runs are never read or written. Journals are hand-written in the
shape am's store.JournalLine dumps (journal schema 1); am is never imported and
its SQLite is never read. Skipped when am is absent.

Story tests build a real git repo and brd board under tmp_path and run am with
a PATH holding only am, brd and git, so no agent CLI is reachable. When am is
present they fail, never skip, if am run lacks --story or brd or git is absent.
"""
```

- [ ] **Step 2: Write the gate test with a deliberately misspelled option (RED)**

Append to the end of `tests/contract/test_am_shapes.py`. The `"--storyX"` is deliberate, so the gate's failure message can be seen once:

```python


def test_run_help_lists_the_story_option(am):
    proc = am.run("run", "--help")
    assert proc.returncode == 0, proc.stdout + proc.stderr
    if "--storyX" not in proc.stdout:
        pytest.fail("the installed am has no --story option on am run "
                    "(reinstall agent-manager: uv tool install --reinstall)")
```

- [ ] **Step 3: Run it to verify it fails with the gate message**

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k test_run_help_lists_the_story_option`
Expected: `1 failed`, with the line `Failed: the installed am has no --story option on am run (reinstall agent-manager: uv tool install --reinstall)`.

- [ ] **Step 4: Restore the real option name**

In `test_run_help_lists_the_story_option`, change `if "--storyX" not in proc.stdout:` to:

```python
    if "--story" not in proc.stdout:
```

- [ ] **Step 5: Run it to verify it passes**

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k test_run_help_lists_the_story_option`
Expected: `1 passed`.

- [ ] **Step 6: Write the fixture-guard tests (RED: `require_tool` and `story_board` do not exist yet)**

Append to the end of `tests/contract/test_am_shapes.py`:

```python


def test_require_tool_fails_naming_the_missing_tool(monkeypatch):
    monkeypatch.setattr(shutil, "which", lambda name: None)
    with pytest.raises(pytest.fail.Exception, match="brd is not on the PATH"):
        require_tool("brd")


def test_story_board_reaches_only_am_brd_and_git_and_its_own_repo(am, story_board, tmp_path):
    assert am.env["PATH"] == str(tmp_path / "bin")
    assert sorted(os.listdir(tmp_path / "bin")) == ["am", "brd", "git"]
    assert not [key for key in am.env if key.startswith("GIT_")], am.env
    proc = subprocess.run(["git", "rev-parse", "--show-toplevel", "--abbrev-ref", "HEAD"],
                          cwd=am.repo, env=am.env, capture_output=True, text=True)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert proc.stdout.split() == [os.path.realpath(am.repo), "master"], proc.stdout
```

- [ ] **Step 7: Run them to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "require_tool or reaches_only"`
Expected: `2 failed` or errored. `test_require_tool_fails_naming_the_missing_tool` fails with `NameError: name 'require_tool' is not defined`. `test_story_board_reaches_only_...` errors with `fixture 'story_board' not found`.

- [ ] **Step 8: Add the constants, `require_tool` and the `story_board` fixture**

Insert this block directly **after** `test_watch_all_follow_prints_a_hello_line_then_journal_lines` (the existing last test, ending at the line `    assert events == expected`) and **before** `test_run_help_lists_the_story_option`:

```python


STORY_DATA_KEYS = {"already_done", "integrate", "levels", "max_concurrent"}
RUN_ROW_KEYS = {"id", "story_id", "milestone_id", "branch_prefix", "started_at"}


def require_tool(name):
    """The resolved path of `name` on the PATH; fails the test when it is absent."""
    path = shutil.which(name)
    if path is None:
        pytest.fail(f"{name} is not on the PATH: the story tests need am, brd and git")
    return os.path.realpath(path)


@pytest.fixture
def story_board(am, tmp_path):
    """A git repo on master and a brd board in am.repo: milestone M holding
    story S1 and story S2 (blocked by S1), two subtasks each. am.env's PATH is
    only a dir of am, brd and git, and it carries no GIT_* variable."""
    tools = {name: require_tool(name) for name in ("am", "brd", "git")}
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    for name, path in tools.items():
        (bin_dir / name).symlink_to(path)
    am.env["PATH"] = str(bin_dir)
    for key in [key for key in am.env if key.startswith("GIT_")]:
        del am.env[key]

    def git(*args):
        proc = subprocess.run(["git", "-c", "user.name=tester", "-c", "user.email=tester@example.com",
                               *args], cwd=am.repo, env=am.env, capture_output=True, text=True)
        assert proc.returncode == 0, proc.stdout + proc.stderr

    git("init", "-b", "master")
    git("commit", "--allow-empty", "-m", "init")

    brd_env = {**am.env, "BRD_AUTHOR": "tester"}

    def brd(*args):
        proc = subprocess.run(["brd", *args], cwd=am.repo, env=brd_env, capture_output=True,
                              text=True)
        assert proc.returncode == 0, proc.stdout + proc.stderr
        payload = json.loads(proc.stdout.strip().splitlines()[-1])
        assert payload["ok"] is True, payload
        return payload["data"]

    brd("init", "--name", "contract")
    milestone = brd("add", "--title", "Milestone M")["id"]
    s1 = brd("add", "--title", "Story A", "--parent", milestone)["id"]
    s2 = brd("add", "--title", "Story B", "--parent", milestone, "--blocked-by", s1)["id"]
    s1_subtasks = [brd("add", "--title", f"Subtask A{n}", "--parent", s1)["id"] for n in (1, 2)]
    for n in (1, 2):
        brd("add", "--title", f"Subtask B{n}", "--parent", s2)
    return SimpleNamespace(milestone=milestone, s1=s1, s2=s2, s1_subtasks=s1_subtasks)
```

Notes for the implementer:
- `am.env` is the dict the `am` fixture's `run` closes over. Mutating it in place, not rebinding it, is what makes every later `am.run` use the restricted PATH.
- `require_tool` resolves through `os.path.realpath` so each symlink points at the real binary. `am` is a uv-tool script whose shebang is an absolute venv python, so it runs with a PATH that holds nothing else.

- [ ] **Step 9: Run them to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "require_tool or reaches_only"`
Expected: `2 passed`.

- [ ] **Step 10: Write the four story contract tests and their shared assertion helper**

Append to the end of `tests/contract/test_am_shapes.py`:

```python


def assert_story_blocked(proc, blocker):
    """Exit 3 with a StoryBlockedError envelope whose message names `blocker`."""
    assert proc.returncode == 3, proc.stdout + proc.stderr
    payload = json.loads(proc.stdout)
    assert payload["ok"] is False, payload
    assert payload["error"]["type"] == "StoryBlockedError", payload
    message = payload["error"]["message"]
    assert isinstance(message, str) and blocker in message, payload


def test_story_dry_run_previews_one_level_with_no_integrate(am, story_board):
    proc = am.run("run", "--story", story_board.s1, "--branch-prefix", "p", "--dry-run",
                  "--repo-dir", am.repo)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    payload = json.loads(proc.stdout)
    assert payload["ok"] is True, payload
    data = payload["data"]
    assert set(data) == STORY_DATA_KEYS, payload
    assert data["already_done"] == [], payload
    assert data["integrate"] is None, payload
    [level] = data["levels"]
    [story] = level["stories"]
    assert story["story"] == story_board.s1, payload
    first, second = story["subtasks"]
    assert {first["id"], second["id"]} == set(story_board.s1_subtasks), payload
    assert first["base"] == "master", payload
    assert second["base"] == first["branch"], payload


def test_blocked_story_is_refused_at_dry_run_with_story_blocked_error(am, story_board):
    proc = am.run("run", "--story", story_board.s2, "--branch-prefix", "p", "--dry-run",
                  "--repo-dir", am.repo)
    assert_story_blocked(proc, story_board.s1)


def test_blocked_story_is_refused_at_a_detached_start_and_nothing_is_recorded(am, story_board):
    """Both the dry-run and the detached start refuse a blocked story; the
    refused start records no run."""
    proc = am.run("run", "--story", story_board.s2, "--branch-prefix", "p", "--detach",
                  "--allow-no-verification", "--repo-dir", am.repo)
    assert_story_blocked(proc, story_board.s1)
    runs = am.run("runs", "--repo-dir", am.repo)
    assert runs.returncode == 0, runs.stdout + runs.stderr
    assert json.loads(runs.stdout) == {"ok": True, "data": {"runs": []}}


def test_a_story_run_row_carries_story_id(am, story_board):
    # No agent CLI is on the PATH: the run is recorded, then escalates at its first phase.
    am.run("run", "--story", story_board.s1, "--branch-prefix", "p", "--allow-no-verification",
           "--repo-dir", am.repo)
    proc = am.run("runs", "--repo-dir", am.repo)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    [row] = json.loads(proc.stdout)["data"]["runs"]
    assert RUN_ROW_KEYS <= set(row), row
    assert row["story_id"] == story_board.s1, row
    assert row["milestone_id"] == story_board.milestone, row
    assert row["branch_prefix"] == "p", row
    assert isinstance(row["started_at"], str) and row["started_at"], row
    if "project" in row:
        assert isinstance(row["project"], dict), row
        assert {"id", "repo_dir"} <= set(row["project"]), row
```

What each test pins (spec "Tests" 2-5):
- The dry-run test asserts the exact `data` key set, `already_done == []`, `integrate is None`, exactly one level (`[level] = ...` raises on any other count) holding exactly one story with id `s1`, and the stack relation (first `base == "master"`, second `base == first["branch"]`). Titles, branch strings and statuses are deliberately not pinned.
- The blocked-story tests pin exit 3, `ok is False`, `error.type == "StoryBlockedError"`, and a non-empty message containing `s1`. `blocker in message` with a non-empty `blocker` implies the message is non-empty.
- The run-row test does not pin the foreground run's exit code or envelope. It must only finish within `AM_TIMEOUT`, which `am.run` enforces. The key check is a subset (`<=`), so a future `project` key cannot break it. When `project` is present, its shape is checked.

- [ ] **Step 11: Run the four new tests against the installed `am`**

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q -k "story_dry_run or blocked_story or story_run_row"`
Expected: `4 passed`. These pin behavior that already exists, so they pass at once. If any fails, do **not** loosen the assertion, stub `am` or skip. Stop and escalate with the failing output: the installed `am` disagrees with the recorded observations.

- [ ] **Step 12: Run the whole module**

Run: `uv run --with pytest python3 -m pytest tests/contract/test_am_shapes.py -q`
Expected: `11 passed` (4 existing + 7 new), in seconds.

- [ ] **Step 13: Confirm nothing leaked outside `tmp_path`**

Run: `git status --porcelain`
Expected: only `tests/contract/test_am_shapes.py` modified (plus the spec/plan docs if still uncommitted). No `.claude/worktrees/` entries or new branches from the test: `git branch --list 'p/*'` prints nothing.

- [ ] **Step 14: Run the full verification**

Run: `bash tests/run.sh`
Expected: pytest reports all tests passed (including `tests/architecture`), then every QML test prints `Totals` with `0 failed`, and the script exits 0 (`echo $?` → `0`).

- [ ] **Step 15: Commit**

```bash
git add tests/contract/test_am_shapes.py
git commit -m "test(contract): pin the installed am run --story preview, refusal and run row"
```

---

## Self-review (planner)

- **Spec coverage:** skip rule (module `pytestmark` unchanged); `--story` gate fails, never skips (Steps 2-5); `brd`/`git` absent fails (`require_tool`, Step 6/8); hermetic story board with the bin-only PATH, a master repo with an empty commit, and the brd board M/S1/S2 with 2+2 subtasks returning `milestone, s1, s2, s1_subtasks` (Step 8); spec tests 1-5 (Steps 2 and 10); docstring extended (Step 1); `tests/architecture` and `bash tests/run.sh` (Step 14); out-of-scope files untouched (Global Constraints, Step 13). No gaps.
- **Placeholders:** none. Every code step carries the full code.
- **Type consistency:** `story_board.milestone/s1/s2/s1_subtasks`, `require_tool`, `assert_story_blocked`, `STORY_DATA_KEYS` and `RUN_ROW_KEYS` are used with the same names and shapes everywhere.
- **Review Focus:** items 1-4 each have a test in this task (Step 6). Item 5 is covered by the existing `AM_TIMEOUT` in `am.run`.
<!-- task-pipeline: validated -->
