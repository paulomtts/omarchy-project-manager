# 2.1 dispatch-preview.py and default-branch lookup (card a19ca446)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-dispatch-design.md` (S3):
"Dispatch levels" (lines 30-41), "Flow" bullets 1-2 (lines 71-79),
"Architecture" bullet 2 (lines 93-94), "Errors" rows 1-2 (lines 140-141) and
"Testing" bullet 3 (lines 154-156). Parent story d3d879b9. Not blocked by
anything. The `runs.js` half of S3 (`dispatchPlan`, `dispatchDefaults`,
`validateDispatch`, `previewSummary`) is already on this branch (commits f8334dc,
4cc1997, c7c2d77, 26d6a59) and is not touched.

## Starting point

- `core/backend/runs/` holds `runs-snapshot.py`, `runs-watch.py`,
  `runs-logs.py` and `run-control.py`. `run-control.py` is the closest model for
  argv building and verify forwarding (`parse`, `control_argv`, `envelope_of`,
  `stderr_tail` with `TAIL_LINES = 20` / `TAIL_CHARS = 2000`, `report`,
  `guarded`); `runs-logs.py` for a plain one-shot passthrough. Both find `am`
  with `shutil.which`, run it as an argv list with `capture_output`,
  `stdin=DEVNULL`, a 60 s timeout, check only the envelope's shape, and print
  one line on every path (exit 0, except `Usage`, exit 2).
- `emit(payload, code=0)` comes from `core/backend/common/json_line.py` and must
  be imported, never redefined (`tests/architecture/test_layers.py` rejects a
  second `def emit(`, `inside`, `write_atomic`, `split_frontmatter`,
  `frontmatter_of`; `docs/architecture.md` lines 191-197). Backend code imports
  only the stdlib and `core/backend/common` (`docs/architecture.md` lines 7-13).
- `core/stores/HelperRunner.qml` runs one process at a time and SIGTERMs the
  current one when the next `run(args)` starts. "Latest run wins" (parent spec
  line 94) is therefore the store's job; the helper only has to be a short,
  killable process that writes nothing.
- `dispatchDefaults(project, card)` (`core/domain/runs.js:874-897`) reads the
  base branch from `project.defaultBranch` (a string; anything else becomes
  `""`). The store that fills `defaultBranch` from this helper's `--defaults`
  output is a later card.
- The real `am` (checked with `am run --help` and against this repo; `--dry-run`
  writes nothing):
  - `am run --milestone <id|title substring> | --board`, `--dry-run`,
    `--repo-dir <path>`, `--base-branch <str>` (default `master`),
    `--branch-prefix <str>` (required with `--milestone`, optional with
    `--board`), `--max-concurrent <int>` (>= 1), `--verify <str>` (repeatable,
    verbatim, ordered), `--allow-no-verification`, `--pretty`.
  - `--dry-run` with `--milestone` prints `{"data": {"already_done", "integrate",
    "levels", ...}, "ok": true}`, exit 0; with `--board`, `{"data": {"board":
    true, "levels": [...]}, "ok": true}`. A dry run does not require `--verify`.
  - A refusal prints `{"error": {"message", "type"}, "ok": false}` and exits 3
    (seen: `MilestoneNotFoundError`).
  - A command line click rejects (no `--branch-prefix` with `--milestone`,
    `--max-concurrent 0`) prints **no envelope**: a usage box on stderr, exit 2.
- `git -C <repo> symbolic-ref refs/remotes/origin/HEAD` prints
  `refs/remotes/origin/main` here; it exits non-zero (128 or 1) when there is
  no `origin/HEAD`. `git -C <repo> symbolic-ref --short HEAD` prints the current
  branch (also for an unborn branch in a fresh `git init`) and exits non-zero on
  a detached HEAD.

## Scope

One new helper, `core/backend/runs/dispatch-preview.py`, and its pytest file,
`tests/core/backend/runs/test_dispatch_preview.py`. Tests first.

### Out of scope

- `start-run.py`, the detached launcher and run-id discovery (parent spec lines
  95-107): sibling card 2.2.
- The per-project dispatch settings in `viewer-state.py` (parent spec lines
  113-117): sibling card 2.3.
- `RunStore.qml` dispatch state, the 400 ms debounce, latest-preview-wins wiring
  through `HelperRunner`, mapping `--defaults` output onto
  `project.defaultBranch` (parent spec lines 71-72, 108-112): the RunStore
  card(s).
- `DispatchDialog.qml`, the Dispatch button, key `d`, `tests/ui/` flows.
- `--card` dispatch: am has no dry run for it (parent spec line 35); this helper
  never sends `--card`.
- `tests/contract/test_am_shapes.py` `--dry-run` payloads (parent spec lines
  159-160): not in this card's description; left for the contract card.
- `docs/architecture.md`'s `core/backend/runs/` paragraph (line 189): left for
  S3's docs card, as S2 did with `run-control.py`.
- Interpreting the dry-run payload (counting levels, subtasks): `previewSummary`
  in `runs.js` already does it. This helper never inspects `data`.
- Every existing helper, test and `runs.js`: unchanged.

## Behaviour

### Command line

Two forms, nothing else:

```
dispatch-preview.py ROOT milestone ID [OPTIONS]
dispatch-preview.py ROOT board [OPTIONS]
dispatch-preview.py --defaults ROOT
```

OPTIONS, in any order:

| option | value | repeat |
|---|---|---|
| `--base-branch B` | next argument, verbatim | at most once |
| `--branch-prefix P` | next argument, verbatim | at most once |
| `--max-concurrent N` | next argument, verbatim (not checked as a number) | at most once |
| `--verify CMD` | next argument, verbatim (may hold spaces, shell metacharacters, or start with `-`) | any number, order kept |
| `--allow-no-verification` | none | at most once |

- The target word is the second argument and is exactly `milestone` or `board`.
  `milestone` takes one more positional, ID (a milestone card id; am also
  accepts a title substring, and the helper passes it on verbatim). `board`
  takes none. A literal word, not `--milestone`/`--board`, so a milestone whose
  title is "board" can never be mistaken for the board target.
- ROOT must be non-empty and must not start with `-`; ID must be non-empty.
  Neither is otherwise checked: a missing directory, a repo with no brd board,
  an unknown milestone are am's refusals to report.
- The helper does **not** require `--branch-prefix` with `milestone` or
  `--verify`/`--allow-no-verification` at all: `validateDispatch` already blocks
  an empty prefix, a dry run does not need verification, and am rejects the
  rest itself (see rule 2 below).
- `--defaults` takes exactly one more argument, ROOT (same rule: non-empty, not
  starting with `-`), and no options.
- Any other shape is a `Usage` failure: no arguments, an unknown target word,
  `milestone` without ID, an extra positional, an unknown option, a valued
  option as the last argument, a once-only option given twice, an empty or
  `-`-leading ROOT, an empty ID, `--defaults` with zero or more than one
  argument or with options. `Usage` prints
  `{"ok": false, "error": {"type": "Usage", "message": USAGE}}`, exits 2 and
  runs neither am nor git. USAGE is exactly:

  `usage: dispatch-preview.py ROOT (milestone ID | board) [--base-branch B] [--branch-prefix P] [--max-concurrent N] [--verify CMD]... [--allow-no-verification] | dispatch-preview.py --defaults ROOT`

### Preview: am argv

The argv after the `am` executable, always a list, never a shell. A fixed
order, whatever order the options came in: target, `--dry-run`, `--repo-dir`,
then `--base-branch`, `--branch-prefix`, `--max-concurrent`, every `--verify`
pair in the order given, `--allow-no-verification`. Options not given are not
sent. `--pretty` and `--detach` are never sent.

| call | am argv |
|---|---|
| `/p milestone m1` | `["run", "--milestone", "m1", "--dry-run", "--repo-dir", "/p"]` |
| `/p board` | `["run", "--board", "--dry-run", "--repo-dir", "/p"]` |
| `/p milestone m1 --verify "uv run pytest" --max-concurrent 2 --branch-prefix m3 --base-branch main --verify "-x" --allow-no-verification` | `["run", "--milestone", "m1", "--dry-run", "--repo-dir", "/p", "--base-branch", "main", "--branch-prefix", "m3", "--max-concurrent", "2", "--verify", "uv run pytest", "--verify", "-x", "--allow-no-verification"]` |

Every value arrives as one argv element, unaltered. am's stdin is `/dev/null`,
its cwd is the helper's, and its environment (`HOME`, `XDG_DATA_HOME`, where am
keeps its data) is the helper's, unchanged. am runs with `AM_TIMEOUT = 60`
seconds; it is not put in its own session (a dry run writes nothing, so a
SIGTERM to the helper that leaves am to finish on its own harms nothing).

### Preview: output, exactly one JSON line on every path

The envelope's `ok` decides what is printed, not am's exit code. am's stderr
never reaches stdout except as the `AmFailed` tail.

1. **Envelope.** am's stdout parses as a JSON object with a boolean `ok`: the
   helper prints that object unchanged on one line and exits 0. This covers the
   milestone and board plans (`ok: true`) and every refusal (`ok: false`, any
   `error.type`, e.g. `ClaimedError`, `MilestoneNotFoundError`, a dependency
   cycle, `RepoDirError`). `data` and `error` are never inspected or trimmed.
2. **AmFailed.** am exited non-zero without an envelope (empty, not JSON, not an
   object, no boolean `ok`): `{"ok": false, "error": {"type": "AmFailed",
   "message": M}}`, exit 0. M is am's stderr with trailing whitespace stripped,
   its last 20 lines, of that the last 2000 characters; if empty,
   `am run exited <code> with no output.`. This is how click's own rejections
   (missing `--branch-prefix`, `--max-concurrent 0`, a non-numeric
   `--max-concurrent`) reach the dialog.
3. **AmBadOutput.** am exited 0 without an envelope: `{"ok": false, "error":
   {"type": "AmBadOutput", "message": M}}`, exit 0, M one of
   `am run did not print JSON (exit 0).`,
   `am run printed JSON that is not an object (exit 0).`,
   `am run printed an object without a boolean ok field (exit 0).`.
4. **AmMissing.** `am` is not on `PATH`: `{"ok": false, "error": {"type":
   "AmMissing", "message": "am is not installed."}}`, exit 0. Checked after
   the arguments are valid.
5. **HelperError.** Anything unexpected (am times out, cannot start, anything
   raised): `{"ok": false, "error": {"type": "HelperError", "message":
   "The dispatch preview failed: <reason>"}}`, exit 0; `<reason>` is the
   exception's text, else its class name.
6. **Usage**: above, exit 2.

### Defaults: the repo's default branch

`--defaults ROOT` never runs am. It asks git, as argv lists with `stdin=DEVNULL`,
captured output and `GIT_TIMEOUT = 10` seconds each:

1. `git -C ROOT symbolic-ref refs/remotes/origin/HEAD`. If it exits 0 and its
   trimmed stdout starts with `refs/remotes/origin/` followed by a non-empty
   rest, the default branch is that rest (`refs/remotes/origin/main` → `main`;
   `refs/remotes/origin/release/2` → `release/2`), source `origin`.
2. Otherwise `git -C ROOT symbolic-ref --short HEAD`. If it exits 0 with a
   non-empty trimmed stdout, that is the default branch (an unborn branch in a
   fresh repo counts), source `current`.
3. Otherwise the branch is unknown (see errors).

Output, one JSON line, exit 0:

- `{"ok": true, "data": {"default_branch": B, "source": "origin" | "current"}}`.
  The store copies `default_branch` into `project.defaultBranch`
  (`runs.js:892`); `source` is informational.
- `{"ok": false, "error": {"type": "NotAGitRepo", "message":
  "<ROOT> is not a git repository."}}` when `git -C ROOT rev-parse --git-dir`
  exits non-zero (this check runs first; it also covers a ROOT that does not
  exist).
- `{"ok": false, "error": {"type": "NoDefaultBranch", "message": "No
  origin/HEAD and HEAD is detached; enter a base branch."}}` when steps 1 and 2
  both fail (detached HEAD with no `origin/HEAD`). The form then starts with an
  empty base, which `dispatchDefaults` already allows.
- `{"ok": false, "error": {"type": "GitMissing", "message": "git is not
  installed."}}` when `git` is not on `PATH`.
- `HelperError` as in preview rule 5 (e.g. a git timeout).

The defaults mode never fetches, never runs `git remote set-head`, and never
writes to the repo.

## Tests (all in `tests/core/backend/runs/test_dispatch_preview.py`)

Tier: **backend pytest** (parent spec lines 154-156: "Backend pytest with a stub
`am`"; `docs/architecture.md` lines 207-209: helpers are tested under
`tests/core/backend/<domain>/`). Right tier because the helper's whole contract
is argv in, one JSON line and an exit code out: no Qt is involved, and the real
`am` cannot be made to answer each error path on demand. Every subprocess test
asserts stdout is exactly one JSON line and checks the exit code.

Preview tests use a fake `am` on a temp `PATH` (`tmpbin:/usr/bin:/bin`), with
temp `HOME`, `XDG_DATA_HOME` and `FAKE_AM_DIR`, modelled on
`test_runs_logs.py`: it appends its argv as JSON to `calls.log`, keys on the
subcommand (`run`), writes `run.err` to stderr if present, prints `run.out`
verbatim and exits with `run.code` (default 0); with no `run.out` it answers
like real am for an unknown milestone (`MilestoneNotFoundError` envelope,
exit 3).

Defaults tests build real throwaway repos in `tmp_path` with the real `git`
(the system tool, not a stub: the behaviour under test *is* what git's
`symbolic-ref` does), with `HOME` and `GIT_CONFIG_GLOBAL` pointed at temp files,
`GIT_CONFIG_NOSYSTEM=1`, and author/committer env vars set, so the user's git
config never leaks in. `origin/HEAD` is set without a network with
`git update-ref refs/remotes/origin/main HEAD` plus
`git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main`.

Argv (fake am):
1. `test_milestone_argv` — `/p milestone m1`: exact argv, `--dry-run` and
   `--repo-dir` present, no `--pretty`, no `--detach`.
2. `test_board_argv` — `/p board`: exact argv, no `--milestone`.
3. `test_options_forwarded_in_fixed_order` — options given in scrambled order
   (third table row): exact argv.
4. `test_verify_values_verbatim` — `--verify` values with spaces, `;`, `$HOME`,
   a leading `-`, and an empty string arrive as single unaltered elements.
5. `test_board_with_branch_prefix` — `board --branch-prefix x` forwards it.
6. `test_environment_passed_to_am` — the fake records `XDG_DATA_HOME` and
   `HOME`; both equal the helper's.

Output (fake am):
7. `test_milestone_plan_passthrough` — a recorded milestone dry-run envelope
   (`already_done`, `integrate`, `levels`) printed unchanged.
8. `test_board_plan_passthrough` — a recorded board envelope unchanged.
9. `test_pretty_envelope_reserialised_to_one_line` — am prints indented JSON;
   one line out, equal object.
10. `test_refusal_passthrough_exit_3` — a `ClaimedError` envelope with exit 3
    is printed unchanged, helper exit 0.
11. `test_default_fake_refusal` — no fixture: the `MilestoneNotFoundError`
    envelope comes through.
12. `test_ok_true_with_nonzero_exit_still_envelope` — envelope `ok: true`,
    exit 1: printed unchanged (envelope decides).
13. `test_am_failed_stderr_tail` — exit 2, no stdout, 30 stderr lines: message
    is the last 20; and a 5000-char line is cut to its last 2000.
14. `test_am_failed_no_output` — exit 2, nothing on either stream: message
    `am run exited 2 with no output.`.
15. `test_am_bad_output` — exit 0 with `not json`, `[1]`, `{"ok": "yes"}`: the
    three AmBadOutput messages.
16. `test_am_missing` — `PATH` without the fake: `AmMissing`, and nothing
    logged.
17. `test_timeout_is_helper_error` — module loaded with `AM_TIMEOUT` shortened
    and a fake that sleeps: `HelperError` starting
    `The dispatch preview failed: `.
18. `test_am_that_cannot_start_is_helper_error` — `am` on `PATH` is a
    non-executable-format file (exec fails): `HelperError`.

Usage (fake am; each asserts exit 2, the exact USAGE message, and an empty
`calls.log`):
19. `test_usage_shapes` — parametrized: `[]`, `["/p"]`, `["/p", "story", "x"]`,
    `["/p", "milestone"]`, `["/p", "milestone", ""]`, `["", "board"]`,
    `["-p", "board"]`, `["/p", "board", "extra"]`,
    `["/p", "milestone", "m1", "extra"]`, `["/p", "board", "--pretty"]`,
    `["/p", "board", "--verify"]`, `["/p", "board", "--base-branch", "a",
    "--base-branch", "b"]`, `["/p", "board", "--allow-no-verification",
    "--allow-no-verification"]`, `["--defaults"]`, `["--defaults", "/a", "/b"]`,
    `["--defaults", "/p", "--verify", "x"]`, `["--defaults", "-x"]`.

Defaults (real git; no fake am is called, asserted via an empty `calls.log`):
20. `test_defaults_origin_head` — origin/HEAD → `main`:
    `{"default_branch": "main", "source": "origin"}`, while the checked-out
    branch is something else (`feature`), proving origin wins.
21. `test_defaults_origin_head_with_slash` — origin/HEAD →
    `refs/remotes/origin/release/2`: `release/2`.
22. `test_defaults_no_origin_falls_back_to_current` — no remote, on branch
    `trunk`: `{"default_branch": "trunk", "source": "current"}`.
23. `test_defaults_unborn_branch` — fresh `git init -b dev`, no commits: `dev`,
    `current`.
24. `test_defaults_detached_no_origin` — detached HEAD, no origin/HEAD:
    `NoDefaultBranch`.
25. `test_defaults_detached_with_origin` — detached HEAD, origin/HEAD set: the
    origin branch (step 1 does not need HEAD).
26. `test_defaults_not_a_repo` — a plain temp dir, and a path that does not
    exist: `NotAGitRepo` with the ROOT in the message.
27. `test_defaults_git_missing` — `PATH` holding only a dir with `python3`
    symlinked in (no git): `GitMissing`.
28. `test_defaults_writes_nothing` — the repo's `.git` tree (file list and
    `HEAD`/refs contents) is identical before and after.

## Hand-off notes for the planner

- Follow the writing-plans format; one or two tasks is right (preview with its
  tests, then defaults with its tests), each red→green→commit.
- Reuse the `run-control.py` shapes (`failure`, `BadOutput`, `envelope_of`,
  `stderr_tail`, `report`, `guarded`) as local functions; do not move them to
  `common` in this card and do not redefine `emit`.
- Verification: `uv run --with pytest python3 -m pytest
  tests/core/backend/runs/test_dispatch_preview.py tests/architecture -q` while
  iterating; `bash tests/run.sh` green at the end. `ruff check` on the two new
  files is optional hygiene, not a gate.

---

# dispatch-preview.py Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A backend helper, `core/backend/runs/dispatch-preview.py`, that previews an `am run` dispatch through `am run --dry-run` and, with `--defaults ROOT`, reports the repo's default branch from git. Every path prints exactly one JSON line.

**Architecture:** One stdlib-only script modelled on `core/backend/runs/run-control.py`: `parse` turns argv into a tuple or `None` (Usage); `preview_argv` builds am's argv in a fixed order; `envelope_of`/`stderr_tail`/`report` map am's output to one envelope; `defaults` asks git (`rev-parse --git-dir`, `symbolic-ref refs/remotes/origin/HEAD`, `symbolic-ref --short HEAD`) read-only; `guarded` turns any exception into a `HelperError` line. `emit` is imported from `core/backend/common/json_line.py`, never redefined.

**Tech Stack:** Python 3 stdlib (`json`, `os`, `shutil`, `subprocess`, `sys`), pytest (run via `uv run --with pytest`), real `git` in the defaults tests, a fake `am` script on a temp `PATH` in the preview tests.

**Spec:** `docs/superpowers/specs/2-1-dispatch-preview-py-a19ca446.md` (prepended above).

## Global Constraints

- Backend code imports only the stdlib and `core/backend/common`; `emit(payload, code=0)` comes from `common.json_line` and must never be redefined (no second `def emit(` anywhere — `tests/architecture/test_layers.py::test_shared_python_helpers_are_defined_once`).
- Exactly one JSON line on stdout on every path; exit 0 on every path except `Usage`, which exits 2.
- USAGE is exactly: `usage: dispatch-preview.py ROOT (milestone ID | board) [--base-branch B] [--branch-prefix P] [--max-concurrent N] [--verify CMD]... [--allow-no-verification] | dispatch-preview.py --defaults ROOT`
- am argv order: target, `--dry-run`, `--repo-dir ROOT`, then `--base-branch`, `--branch-prefix`, `--max-concurrent`, every `--verify` pair in the order given, `--allow-no-verification`. `--pretty`, `--detach` and `--card` are never sent.
- `AM_TIMEOUT = 60`, `GIT_TIMEOUT = 10`, `TAIL_LINES = 20`, `TAIL_CHARS = 2000`.
- am and git run as argv lists (no shell), `stdin=subprocess.DEVNULL`, output captured, environment and cwd unchanged; am is not put in its own session.
- Error messages verbatim: `am is not installed.`, `am run exited <code> with no output.`, `am run did not print JSON (exit 0).`, `am run printed JSON that is not an object (exit 0).`, `am run printed an object without a boolean ok field (exit 0).`, `The dispatch preview failed: <reason>`, `<ROOT> is not a git repository.`, `No origin/HEAD and HEAD is detached; enter a base branch.`, `git is not installed.`
- `--defaults` never runs am, never fetches, never runs `git remote set-head`, never writes to the repo.
- No other file changes: every existing helper, test, `runs.js` and `docs/architecture.md` stay as they are.

## Review Focus

1. A milestone whose id/title is literally `board` (`ROOT milestone board`) must go to am as `--milestone board`, never `--board` — tested in Task 1 (`test_milestone_named_board`).
2. ROOT and ID holding spaces and shell metacharacters (`/my repo; x`, a title substring like `M3 Dispatch & preview`) must reach am and git as single, unaltered argv elements — tested in Task 1 (`test_root_and_id_verbatim`) and Task 2 (`test_defaults_root_with_spaces`).
3. am output (stdout or stderr) holding non-ASCII or invalid UTF-8 bytes must still give exactly one valid JSON line, not a decode crash — tested in Task 1 (`test_non_utf8_output_still_one_line`).
4. An am that reads stdin must get EOF at once (stdin is `/dev/null`), not hang on the store's pipe — tested in Task 1 (`test_am_does_not_inherit_stdin`).
5. `--defaults` pointed at a regular file (a mistyped project path) must be `NotAGitRepo`, and a hung git must become `HelperError` within `GIT_TIMEOUT` — tested in Task 2 (`test_defaults_not_a_repo`, `test_defaults_git_timeout_is_helper_error`).

## File Structure

- Create `core/backend/runs/dispatch-preview.py` — the helper (both modes; one responsibility: answer the dispatch dialog's two questions with one JSON line).
- Create `tests/core/backend/runs/test_dispatch_preview.py` — all of its tests (backend pytest tier).

Nothing else is touched.

---

### Task 1: Preview mode — command line, am argv, envelope passthrough, AmFailed/AmBadOutput/AmMissing/HelperError/Usage

**Files:**
- Create: `core/backend/runs/dispatch-preview.py`
- Test: `tests/core/backend/runs/test_dispatch_preview.py` (create)

**Interfaces:**
- Consumes: `emit(payload, code=0)` from `core/backend/common/json_line.py` (prints `json.dumps(payload)`, returns `code`).
- Produces (Task 2 extends these; names must not change):
  - `USAGE: str`, `VALUED = ("--base-branch", "--branch-prefix", "--max-concurrent")`, `AM_TIMEOUT = 60`, `TAIL_LINES = 20`, `TAIL_CHARS = 2000`
  - `failure(kind: str, message: str, code: int = 0) -> int`
  - `good_root(root: str) -> bool`
  - `parse(argv: list[str]) -> tuple | None` — returns `("preview", root, milestone_or_None, options)`; `options` is a dict with key `"--verify"` (list of str) always present, each given `VALUED` flag mapped to its str value, `"--allow-no-verification"` mapped to `True` when given.
  - `preview_argv(root, milestone, options) -> list[str]`
  - `preview(root, milestone, options) -> int`
  - `main(argv) -> int`, `guarded(argv) -> int`
  - Test-file helpers used by Task 2: fixture `world`, `write_exec(path, text)`, `env_for(world, **extra)`, `run(world, args, **extra) -> (exit, payload)`, `calls(world) -> list`, `load_helper()`, `one_line(capsys)`, constant `USAGE_LINE`.

- [ ] **Step 1: Write the failing tests**

Create `tests/core/backend/runs/test_dispatch_preview.py` with exactly this content:

```python
"""dispatch-preview.py: an `am run --dry-run` passthrough and the repo's default
branch, one JSON line on every path.

Hermetic: a fake `am` lives on a temp PATH and serves hand-written fixtures from
FAKE_AM_DIR, appending each call's argv to calls.log; HOME and XDG_DATA_HOME are
temp. The real `am` and real data are never touched.
"""
import importlib.util
import json
import os
import stat
import subprocess
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "..")
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "dispatch-preview.py")

# The fake am logs its argv, then (keyed on the subcommand, so "run") writes
# FAKE_AM_DIR/run.err to stderr if present, prints FAKE_AM_DIR/run.out verbatim
# and exits with FAKE_AM_DIR/run.code (default 0). Fixtures are copied as bytes,
# so they may hold invalid UTF-8. A missing .out fixture behaves like real am for
# an unknown milestone: a MilestoneNotFoundError envelope and exit 3.
FAKE_AM = '''#!/usr/bin/env python3
import json, os, sys
d = os.environ["FAKE_AM_DIR"]
args = sys.argv[1:]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(args) + "\\n")
name = "run" if args[:1] == ["run"] else "other"
out = os.path.join(d, name + ".out")
if not os.path.exists(out):
    sys.stdout.write(json.dumps({"error": {"message": "milestone not found", "type": "MilestoneNotFoundError"}, "ok": False}) + "\\n")
    sys.exit(3)
err = os.path.join(d, name + ".err")
if os.path.exists(err):
    with open(err, "rb") as f:
        sys.stderr.buffer.write(f.read())
with open(out, "rb") as f:
    sys.stdout.buffer.write(f.read())
code = os.path.join(d, name + ".code")
sys.exit(int(open(code).read()) if os.path.exists(code) else 0)
'''

NOT_FOUND = {"error": {"message": "milestone not found", "type": "MilestoneNotFoundError"}, "ok": False}
USAGE_LINE = {"ok": False, "error": {"type": "Usage", "message":
              "usage: dispatch-preview.py ROOT (milestone ID | board) [--base-branch B]"
              " [--branch-prefix P] [--max-concurrent N] [--verify CMD]..."
              " [--allow-no-verification] | dispatch-preview.py --defaults ROOT"}}

# Recorded shapes of `am run --dry-run` data. Opaque to the helper: it must pass
# them through untouched (previewSummary in runs.js reads them).
MILESTONE_PLAN = {"ok": True, "data": {
    "max_concurrent": 4,
    "levels": [
        {"level": 0, "concurrent": 1, "stories": [
            {"story": "s1", "title": "Story one", "root": "main",
             "subtasks": [{"card": "c1", "branch": "m3-c1", "base": "main"}]}]},
    ],
    "already_done": [{"kind": "story", "id": "s4", "title": "Story four"}],
    "integrate": {"branch": "m3-integrate", "worktree": "/p/.worktrees/m3-integrate",
                  "order": [{"story": "s1", "tip": "m3-c1"}]},
}}
BOARD_PLAN = {"ok": True, "data": {
    "board": True,
    "max_concurrent": 4,
    "levels": [{"level": 0, "milestones": [
        {"milestone_id": "m1", "title": "M1 First", "branch_prefix": "m1",
         "base_branch": "main", "plan": {"levels": [], "already_done": []}}]}],
}}
CLAIMED = {"ok": False, "error": {"type": "ClaimedError",
                                  "message": "card c1 is claimed by run r9"}}


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am, its fixture dir, and a temp HOME/XDG_DATA_HOME."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "am", FAKE_AM)
    amdir = tmp_path / "am"
    amdir.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    return {"tmp": tmp_path, "bin": bindir, "am": amdir, "home": home,
            "data": tmp_path / "data"}


def env_for(world, **extra):
    e = {
        "PATH": str(world["bin"]) + os.pathsep + "/usr/bin" + os.pathsep + "/bin",
        "HOME": str(world["home"]),
        "XDG_DATA_HOME": str(world["data"]),
        "FAKE_AM_DIR": str(world["am"]),
    }
    e.update(extra)
    return e


def run(world, args, **extra):
    """Run the helper; assert stdout is exactly one JSON line; return (exit, payload)."""
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True,
                       env=env_for(world, **extra), timeout=60)
    lines = p.stdout.splitlines()
    assert len(lines) == 1, (p.stdout, p.stderr)
    return p.returncode, json.loads(lines[0])


def set_raw(world, text, code=0, stderr=None):
    """am run prints `text` (str or bytes), writes `stderr` and exits `code`."""
    out = world["am"] / "run.out"
    out.write_bytes(text if isinstance(text, bytes) else text.encode())
    (world["am"] / "run.code").write_text(str(code))
    if stderr is not None:
        err = world["am"] / "run.err"
        err.write_bytes(stderr if isinstance(stderr, bytes) else stderr.encode())


def set_envelope(world, envelope, code=0):
    set_raw(world, json.dumps(envelope) + "\n", code)


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def load_helper():
    """The script as a module (its name has a hyphen, so no plain import)."""
    spec = importlib.util.spec_from_file_location("dispatch_preview", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def use_world(world, monkeypatch):
    for key, value in env_for(world).items():
        monkeypatch.setenv(key, value)


def one_line(capsys):
    lines = capsys.readouterr().out.splitlines()
    assert len(lines) == 1, lines
    return json.loads(lines[0])


# --- am argv -----------------------------------------------------------------

def test_milestone_argv(world):
    set_envelope(world, MILESTONE_PLAN)
    code, _ = run(world, ["/p", "milestone", "m1"])
    assert code == 0
    made = calls(world)
    assert made == [["run", "--milestone", "m1", "--dry-run", "--repo-dir", "/p"]]
    assert "--pretty" not in made[0]
    assert "--detach" not in made[0]


def test_board_argv(world):
    set_envelope(world, BOARD_PLAN)
    code, _ = run(world, ["/p", "board"])
    assert code == 0
    made = calls(world)
    assert made == [["run", "--board", "--dry-run", "--repo-dir", "/p"]]
    assert "--milestone" not in made[0]


def test_milestone_named_board(world):
    # The target is a literal word, so a milestone titled "board" stays a milestone.
    set_envelope(world, MILESTONE_PLAN)
    code, _ = run(world, ["/p", "milestone", "board"])
    assert code == 0
    assert calls(world) == [["run", "--milestone", "board", "--dry-run", "--repo-dir", "/p"]]


def test_options_forwarded_in_fixed_order(world):
    set_envelope(world, MILESTONE_PLAN)
    code, _ = run(world, ["/p", "milestone", "m1",
                          "--verify", "uv run pytest", "--max-concurrent", "2",
                          "--branch-prefix", "m3", "--base-branch", "main",
                          "--verify", "-x", "--allow-no-verification"])
    assert code == 0
    assert calls(world) == [["run", "--milestone", "m1", "--dry-run", "--repo-dir", "/p",
                             "--base-branch", "main", "--branch-prefix", "m3",
                             "--max-concurrent", "2",
                             "--verify", "uv run pytest", "--verify", "-x",
                             "--allow-no-verification"]]


def test_verify_values_verbatim(world):
    # Spaces, shell metacharacters, a leading dash and an empty string each arrive
    # as one unaltered argv element: no shell, no validation by the helper.
    values = ["uv run pytest -q", "make test; echo done", "echo $HOME", "-x", ""]
    args = ["/p", "board"]
    for value in values:
        args += ["--verify", value]
    set_envelope(world, BOARD_PLAN)
    code, _ = run(world, args)
    assert code == 0
    expected = ["run", "--board", "--dry-run", "--repo-dir", "/p"]
    for value in values:
        expected += ["--verify", value]
    assert calls(world) == [expected]


def test_root_and_id_verbatim(world):
    set_envelope(world, MILESTONE_PLAN)
    code, _ = run(world, ["/my repo; x", "milestone", "M3 Dispatch & preview",
                          "--max-concurrent", "two"])
    assert code == 0
    assert calls(world) == [["run", "--milestone", "M3 Dispatch & preview", "--dry-run",
                             "--repo-dir", "/my repo; x", "--max-concurrent", "two"]]


def test_board_with_branch_prefix(world):
    set_envelope(world, BOARD_PLAN)
    code, _ = run(world, ["/p", "board", "--branch-prefix", "x"])
    assert code == 0
    assert calls(world) == [["run", "--board", "--dry-run", "--repo-dir", "/p",
                             "--branch-prefix", "x"]]


def test_environment_passed_to_am(world):
    # am keeps its data under XDG_DATA_HOME/HOME, so it must see the helper's own;
    # its cwd is the helper's too.
    write_exec(world["bin"] / "am",
               "#!/usr/bin/env python3\nimport json, os\n"
               "with open(os.path.join(os.environ['FAKE_AM_DIR'], 'env.json'), 'w') as f:\n"
               "    json.dump({'HOME': os.environ.get('HOME'),"
               " 'XDG_DATA_HOME': os.environ.get('XDG_DATA_HOME'), 'cwd': os.getcwd()}, f)\n"
               "print(json.dumps({'ok': True, 'data': {'board': True, 'levels': []}}))\n")
    code, out = run(world, ["/p", "board"])
    assert code == 0
    assert out == {"ok": True, "data": {"board": True, "levels": []}}
    seen = json.loads((world["am"] / "env.json").read_text())
    assert seen == {"HOME": str(world["home"]), "XDG_DATA_HOME": str(world["data"]),
                    "cwd": os.getcwd()}


# --- envelope passthrough ------------------------------------------------------

def test_milestone_plan_passthrough(world):
    set_envelope(world, MILESTONE_PLAN)
    code, out = run(world, ["/p", "milestone", "m1", "--branch-prefix", "m3"])
    assert code == 0
    assert out == MILESTONE_PLAN


def test_board_plan_passthrough(world):
    set_envelope(world, BOARD_PLAN)
    code, out = run(world, ["/p", "board"])
    assert code == 0
    assert out == BOARD_PLAN


def test_pretty_envelope_reserialised_to_one_line(world):
    set_raw(world, json.dumps(MILESTONE_PLAN, indent=2) + "\n")
    code, out = run(world, ["/p", "milestone", "m1"])  # run() asserts exactly one line
    assert code == 0
    assert out == MILESTONE_PLAN


def test_refusal_passthrough_exit_3(world):
    set_envelope(world, CLAIMED, code=3)
    code, out = run(world, ["/p", "milestone", "m1"])
    assert code == 0
    assert out == CLAIMED


def test_default_fake_refusal(world):
    # No run.out: the fake answers like real am for an unknown milestone.
    code, out = run(world, ["/p", "milestone", "nope"])
    assert code == 0
    assert out == NOT_FOUND
    assert calls(world) == [["run", "--milestone", "nope", "--dry-run", "--repo-dir", "/p"]]


def test_ok_true_with_nonzero_exit_still_envelope(world):
    # The envelope's ok decides, not am's exit code; stderr never reaches stdout.
    set_raw(world, json.dumps(BOARD_PLAN) + "\n", code=1, stderr="warning: noisy\n")
    code, out = run(world, ["/p", "board"])
    assert code == 0
    assert out == BOARD_PLAN


def test_non_utf8_output_still_one_line(world):
    # Undecodable bytes are replaced, never a crash; non-ASCII text round-trips.
    set_raw(world, b'{"ok": true, "data": {"title": "caf\xc3\xa9 \xe2\x9c\x93 \xff"}}\n')
    code, out = run(world, ["/p", "board"])
    assert code == 0
    assert out == {"ok": True, "data": {"title": "caf\u00e9 \u2713 \ufffd"}}
    set_raw(world, b"", code=2, stderr=b"Error: bad \xff value\n")
    code, out = run(world, ["/p", "board"])
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmFailed", "message": "Error: bad \ufffd value"}}


def test_am_does_not_inherit_stdin(world):
    # The helper's stdin is an open pipe that never sends EOF. An am that reads
    # stdin must get EOF at once (stdin is /dev/null), not block on that pipe.
    write_exec(world["bin"] / "am",
               "#!/usr/bin/env python3\nimport json, sys\nsys.stdin.read()\n"
               "print(json.dumps({'ok': True, 'data': {'board': True, 'levels': []}}))\n")
    p = subprocess.Popen([sys.executable, SCRIPT, "/p", "board"], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                         env=env_for(world))
    try:
        code = p.wait(timeout=15)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait()
        pytest.fail("am blocked reading the helper's stdin")
    finally:
        p.stdin.close()
    lines = p.stdout.read().splitlines()
    p.stdout.close()
    p.stderr.close()
    assert code == 0
    assert len(lines) == 1
    assert json.loads(lines[0]) == {"ok": True, "data": {"board": True, "levels": []}}


# --- failures --------------------------------------------------------------------

def test_am_failed_stderr_tail(world):
    # click's own rejections (missing --branch-prefix, --max-concurrent 0) print no
    # envelope, only a usage box on stderr: the tail is the message.
    stderr = "".join("line %d\n" % i for i in range(30))
    set_raw(world, "", code=2, stderr=stderr)
    code, out = run(world, ["/p", "milestone", "m1"])
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmFailed", "message":
                   "\n".join("line %d" % i for i in range(10, 30))}}
    set_raw(world, "", code=2, stderr="a" * 3000 + "b" * 2000 + "\n")
    code, out = run(world, ["/p", "milestone", "m1"])
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmFailed", "message": "b" * 2000}}


def test_am_failed_no_output(world):
    set_raw(world, "", code=2)
    code, out = run(world, ["/p", "board"])
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmFailed",
                                          "message": "am run exited 2 with no output."}}


@pytest.mark.parametrize("text,message", [
    ("not json\n", "am run did not print JSON (exit 0)."),
    ("[1]\n", "am run printed JSON that is not an object (exit 0)."),
    ('{"ok": "yes"}\n', "am run printed an object without a boolean ok field (exit 0)."),
], ids=["not-json", "list", "ok-string"])
def test_am_bad_output(world, text, message):
    set_raw(world, text, code=0)
    code, out = run(world, ["/p", "board"])
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmBadOutput", "message": message}}


def test_am_missing(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, out = run(world, ["/p", "board"], PATH=str(empty))
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmMissing", "message": "am is not installed."}}
    assert calls(world) == []
    # Checked only after the arguments are valid: a bad command line is still Usage.
    code, out = run(world, ["/p"], PATH=str(empty))
    assert code == 2
    assert out == USAGE_LINE


def test_timeout_is_helper_error(world, monkeypatch, capsys):
    # An am that hangs is cut off after AM_TIMEOUT (shortened here so the test does
    # not wait the real 60 s) and reported as HelperError.
    write_exec(world["bin"] / "am", "#!/usr/bin/env python3\nimport time\ntime.sleep(10)\n")
    helper = load_helper()
    assert helper.AM_TIMEOUT == 60
    monkeypatch.setattr(helper, "AM_TIMEOUT", 0.5)
    use_world(world, monkeypatch)
    code = helper.guarded(["/p", "board"])
    out = one_line(capsys)
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The dispatch preview failed: ")


def test_am_that_cannot_start_is_helper_error(world):
    # Executable (so shutil.which finds it) but unstartable: subprocess raises
    # OSError and guarded() must still print exactly one JSON line.
    write_exec(world["bin"] / "am", "#!/nonexistent/interpreter\n")
    code, out = run(world, ["/p", "board"])
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The dispatch preview failed: ")


# --- usage -------------------------------------------------------------------------

@pytest.mark.parametrize("args", [
    [],
    ["/p"],
    ["/p", "story", "x"],
    ["/p", "milestone"],
    ["/p", "milestone", ""],
    ["", "board"],
    ["-p", "board"],
    ["/p", "board", "extra"],
    ["/p", "milestone", "m1", "extra"],
    ["/p", "board", "--pretty"],
    ["/p", "board", "--verify"],
    ["/p", "board", "--base-branch", "a", "--base-branch", "b"],
    ["/p", "board", "--allow-no-verification", "--allow-no-verification"],
    ["--defaults"],
    ["--defaults", "/a", "/b"],
    ["--defaults", "/p", "--verify", "x"],
    ["--defaults", "-x"],
])
def test_usage_shapes(world, args):
    code, out = run(world, args)
    assert code == 2
    assert out == USAGE_LINE
    assert calls(world) == []
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_dispatch_preview.py -q`
Expected: FAIL — every subprocess test fails `assert len(lines) == 1` (python cannot open `dispatch-preview.py`, stdout is empty), and `test_timeout_is_helper_error` fails with `FileNotFoundError`.

- [ ] **Step 3: Write the minimal implementation**

Create `core/backend/runs/dispatch-preview.py` with exactly this content:

```python
#!/usr/bin/env python3
"""Preview a dispatch: an `am run --dry-run` passthrough.

    dispatch-preview.py ROOT (milestone ID | board) [--base-branch B] [--branch-prefix P]
                        [--max-concurrent N] [--verify CMD]... [--allow-no-verification]

Runs `am run (--milestone ID | --board) --dry-run --repo-dir ROOT`, then the
options given in a fixed order (--base-branch, --branch-prefix,
--max-concurrent, every --verify pair in the order given,
--allow-no-verification), as an argv list (no shell, stdin /dev/null, 60 s
timeout). Every value is the next argument verbatim, even if it starts with
`-`; am refuses bad ones itself. --pretty, --detach and --card are never sent.
A dry run writes nothing, so am is not detached: the store SIGTERMs this helper
when a newer preview starts, and am finishing alone harms nothing.

Prints exactly one JSON line on EVERY path:
- am's envelope, unchanged, whether {"ok": true, "data": ...} or
  {"ok": false, "error": ...}. The envelope's `ok` decides, not am's exit code;
  `data` is never inspected (previewSummary in runs.js reads it);
- {"ok": false, "error": {"type": "AmFailed", ...}} when am exited non-zero
  without an envelope; the message is the tail of am's stderr;
- {"ok": false, "error": {"type": "AmBadOutput", ...}} when am exited 0
  without an envelope;
- {"ok": false, "error": {"type": "AmMissing", ...}} when am is not on PATH;
- {"ok": false, "error": {"type": "HelperError", ...}} on any unexpected
  failure (a timeout, an am that cannot start);
- {"ok": false, "error": {"type": "Usage", ...}} for any other command line.
Exit 0 whenever a line was printed, refusals and errors included; exit 2 for
Usage only.
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = ("usage: dispatch-preview.py ROOT (milestone ID | board) [--base-branch B]"
         " [--branch-prefix P] [--max-concurrent N] [--verify CMD]..."
         " [--allow-no-verification] | dispatch-preview.py --defaults ROOT")
VALUED = ("--base-branch", "--branch-prefix", "--max-concurrent")
AM_TIMEOUT = 60
TAIL_LINES = 20
TAIL_CHARS = 2000


class BadOutput(Exception):
    """am printed something that is not an envelope; the message says what."""


def failure(kind, message, code=0):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def good_root(root):
    return bool(root) and not root.startswith("-")


def parse(argv):
    """("preview", root, milestone, options) for a command line USAGE allows, else None.

    milestone is None for the board. options always maps "--verify" to the list
    of commands in the order given, maps each given VALUED flag to its value and
    "--allow-no-verification" to True when given; a once-only flag given twice
    is a usage error."""
    if len(argv) < 2 or not good_root(argv[0]):
        return None
    root, target, rest = argv[0], argv[1], argv[2:]
    if target == "milestone":
        if not rest or not rest[0]:
            return None
        milestone, rest = rest[0], rest[1:]
    elif target == "board":
        milestone = None
    else:
        return None
    options = {"--verify": []}
    while rest:
        flag = rest[0]
        if flag == "--verify" and len(rest) > 1:
            options["--verify"].append(rest[1])
            rest = rest[2:]
        elif flag in VALUED and len(rest) > 1 and flag not in options:
            options[flag] = rest[1]
            rest = rest[2:]
        elif flag == "--allow-no-verification" and flag not in options:
            options[flag] = True
            rest = rest[1:]
        else:
            return None
    return "preview", root, milestone, options


def preview_argv(root, milestone, options):
    """am's argv after the executable, in a fixed order whatever order the options came in."""
    argv = ["run", "--board"] if milestone is None else ["run", "--milestone", milestone]
    argv += ["--dry-run", "--repo-dir", root]
    for flag in VALUED:
        if flag in options:
            argv += [flag, options[flag]]
    for cmd in options["--verify"]:
        argv += ["--verify", cmd]
    if "--allow-no-verification" in options:
        argv.append("--allow-no-verification")
    return argv


def envelope_of(stdout, returncode):
    """am's envelope, checked only for shape: a JSON object with a boolean `ok`."""
    exit_note = " (exit " + str(returncode) + ")."
    try:
        envelope = json.loads(stdout)
    except ValueError:
        raise BadOutput("am run did not print JSON" + exit_note)
    if not isinstance(envelope, dict):
        raise BadOutput("am run printed JSON that is not an object" + exit_note)
    if not isinstance(envelope.get("ok"), bool):
        raise BadOutput("am run printed an object without a boolean ok field" + exit_note)
    return envelope


def stderr_tail(stderr):
    """The end of am's stderr, where click's usage box or a crash names its cause:
    at most TAIL_LINES lines, and of those at most TAIL_CHARS characters."""
    lines = stderr.rstrip().splitlines()[-TAIL_LINES:]
    return "\n".join(lines)[-TAIL_CHARS:]


def report(stdout, stderr, returncode):
    try:
        envelope = envelope_of(stdout, returncode)
    except BadOutput as e:
        if returncode == 0:
            return failure("AmBadOutput", str(e))
        tail = stderr_tail(stderr)
        return failure("AmFailed", tail or "am run exited " + str(returncode) + " with no output.")
    return emit(envelope)


def run_am(am, argv):
    """(stdout, stderr, returncode) of one dry run."""
    proc = subprocess.run([am, *argv], capture_output=True, encoding="utf-8",
                          errors="replace", stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    return proc.stdout, proc.stderr, proc.returncode


def preview(root, milestone, options):
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    return report(*run_am(am, preview_argv(root, milestone, options)))


def main(argv):
    parsed = parse(argv)
    if parsed is None:
        return failure("Usage", USAGE, 2)
    return preview(*parsed[1:])


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception (a timeout, an am that cannot start) - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The dispatch preview failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
```

Then make it executable like its siblings: `chmod +x core/backend/runs/dispatch-preview.py` (check with `ls -l core/backend/runs/` that `run-control.py` is executable; match whatever mode it has).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_dispatch_preview.py tests/architecture -q`
Expected: PASS (all tests; the architecture tests confirm no second `def emit(` and that the new file respects the backend layer rules).

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/dispatch-preview.py tests/core/backend/runs/test_dispatch_preview.py
git commit -m "dispatch-preview.py: am run --dry-run passthrough, one JSON line on every path (S3 2.1)"
```

---

### Task 2: Defaults mode — the repo's default branch from git

**Files:**
- Modify: `core/backend/runs/dispatch-preview.py` (module docstring, constants, `parse`, new `git`/`defaults`, `main`)
- Test: `tests/core/backend/runs/test_dispatch_preview.py` (append)

**Interfaces:**
- Consumes (from Task 1, unchanged): `failure`, `good_root`, `emit`, `guarded`, `preview`; test helpers `world`, `write_exec`, `env_for`, `run`, `calls`, `load_helper`, `use_world`, `one_line`.
- Produces:
  - `GIT_TIMEOUT = 10`, `ORIGIN = "refs/remotes/origin/"`
  - `parse(argv)` also returns `("defaults", root)` for `--defaults ROOT`.
  - `git(exe: str, root: str, *args: str) -> tuple[int, str]` — `(returncode, stripped stdout)`.
  - `defaults(root: str) -> int` — prints `{"ok": true, "data": {"default_branch": B, "source": "origin" | "current"}}` or a `NotAGitRepo` / `NoDefaultBranch` / `GitMissing` failure.

- [ ] **Step 1: Write the failing tests**

Append exactly this to the end of `tests/core/backend/runs/test_dispatch_preview.py`:

```python


# --- defaults: the repo's default branch (real git) --------------------------------
# Real throwaway repos: the behaviour under test *is* what git's symbolic-ref does.
# The user's git config never leaks in, and discovery never climbs above tmp.

def git_env(world):
    config = world["tmp"] / "gitconfig"
    config.touch()
    return {"GIT_CONFIG_GLOBAL": str(config), "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CEILING_DIRECTORIES": str(world["tmp"]),
            "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.com"}


def sh_git(world, repo, *args):
    subprocess.run(["git", "-C", str(repo), *args], env=env_for(world, **git_env(world)),
                   check=True, capture_output=True, timeout=30)


def make_repo(world, branch, name="repo", commit=True):
    repo = world["tmp"] / name
    repo.mkdir()
    sh_git(world, repo, "init", "-q", "-b", branch)
    if commit:
        sh_git(world, repo, "commit", "-q", "--allow-empty", "-m", "init")
    return repo


def set_origin_head(world, repo, branch):
    """origin/HEAD -> origin/<branch>, without a network or a remote."""
    sh_git(world, repo, "update-ref", "refs/remotes/origin/" + branch, "HEAD")
    sh_git(world, repo, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/" + branch)


def ask_defaults(world, root, **extra):
    """Run --defaults ROOT; assert am was never called; return (exit, payload)."""
    env = git_env(world)
    env.update(extra)
    code, out = run(world, ["--defaults", str(root)], **env)
    assert calls(world) == []
    return code, out


def found(branch, source):
    return {"ok": True, "data": {"default_branch": branch, "source": source}}


NO_DEFAULT = {"ok": False, "error": {"type": "NoDefaultBranch", "message":
              "No origin/HEAD and HEAD is detached; enter a base branch."}}


def test_defaults_origin_head(world):
    repo = make_repo(world, "main")
    set_origin_head(world, repo, "main")
    sh_git(world, repo, "checkout", "-q", "-b", "feature")
    code, out = ask_defaults(world, repo)
    assert code == 0
    assert out == found("main", "origin")


def test_defaults_origin_head_with_slash(world):
    repo = make_repo(world, "main")
    set_origin_head(world, repo, "release/2")
    code, out = ask_defaults(world, repo)
    assert code == 0
    assert out == found("release/2", "origin")


def test_defaults_no_origin_falls_back_to_current(world):
    repo = make_repo(world, "trunk")
    code, out = ask_defaults(world, repo)
    assert code == 0
    assert out == found("trunk", "current")


def test_defaults_unborn_branch(world):
    repo = make_repo(world, "dev", commit=False)
    code, out = ask_defaults(world, repo)
    assert code == 0
    assert out == found("dev", "current")


def test_defaults_detached_no_origin(world):
    repo = make_repo(world, "main")
    sh_git(world, repo, "checkout", "-q", "--detach")
    code, out = ask_defaults(world, repo)
    assert code == 0
    assert out == NO_DEFAULT


def test_defaults_detached_with_origin(world):
    # Step 1 does not need HEAD at all.
    repo = make_repo(world, "main")
    set_origin_head(world, repo, "main")
    sh_git(world, repo, "checkout", "-q", "--detach")
    code, out = ask_defaults(world, repo)
    assert code == 0
    assert out == found("main", "origin")


def test_defaults_root_with_spaces(world):
    repo = make_repo(world, "main", name="my repo; $x")
    code, out = ask_defaults(world, repo)
    assert code == 0
    assert out == found("main", "current")


def test_defaults_not_a_repo(world):
    plain = world["tmp"] / "plain"
    plain.mkdir()
    afile = world["tmp"] / "a-file"
    afile.write_text("not a repo\n")
    for root in (plain, world["tmp"] / "does-not-exist", afile):
        code, out = ask_defaults(world, root)
        assert code == 0
        assert out == {"ok": False, "error": {"type": "NotAGitRepo",
                                              "message": str(root) + " is not a git repository."}}


def test_defaults_git_missing(world):
    repo = make_repo(world, "main")
    only_python = world["tmp"] / "only-python"
    only_python.mkdir()
    (only_python / "python3").symlink_to(sys.executable)
    code, out = ask_defaults(world, repo, PATH=str(only_python))
    assert code == 0
    assert out == {"ok": False, "error": {"type": "GitMissing", "message": "git is not installed."}}


def test_defaults_git_timeout_is_helper_error(world, monkeypatch, capsys):
    # A git that hangs is cut off after GIT_TIMEOUT (shortened here).
    write_exec(world["bin"] / "git", "#!/usr/bin/env python3\nimport time\ntime.sleep(10)\n")
    helper = load_helper()
    assert helper.GIT_TIMEOUT == 10
    monkeypatch.setattr(helper, "GIT_TIMEOUT", 0.5)
    use_world(world, monkeypatch)
    code = helper.guarded(["--defaults", str(world["tmp"])])
    out = one_line(capsys)
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The dispatch preview failed: ")


def tree_of(path):
    """Every file under path, by relative name, with its bytes."""
    return {str(p.relative_to(path)): p.read_bytes()
            for p in sorted(path.rglob("*")) if p.is_file()}


def test_defaults_writes_nothing(world):
    # One repo answered from origin/HEAD, one that falls through to HEAD: all three
    # git calls run, and neither repo's .git changes.
    with_origin = make_repo(world, "main", name="with-origin")
    set_origin_head(world, with_origin, "main")
    without_origin = make_repo(world, "trunk", name="without-origin")
    for repo in (with_origin, without_origin):
        before = tree_of(repo / ".git")
        code, _ = ask_defaults(world, repo)
        assert code == 0
        assert tree_of(repo / ".git") == before
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_dispatch_preview.py -q -k defaults`
Expected: FAIL — every `test_defaults_*` gets the `Usage` line with exit 2 instead of its expected payload (Task 1's `parse` rejects `--defaults` because ROOT starts with `-`); `test_defaults_git_timeout_is_helper_error` fails with `AttributeError: ... has no attribute 'GIT_TIMEOUT'`. (`test_usage_shapes[...--defaults...]` cases still pass, which is correct.)

- [ ] **Step 3: Write the implementation**

Replace the whole content of `core/backend/runs/dispatch-preview.py` with exactly this (Task 1's code plus the `--defaults` branch in `parse`, `GIT_TIMEOUT`/`ORIGIN`, `git`, `defaults`, the dispatch in `main`, and the docstring for both modes):

```python
#!/usr/bin/env python3
"""Preview a dispatch: an `am run --dry-run` passthrough, and the repo's default branch.

    dispatch-preview.py ROOT (milestone ID | board) [--base-branch B] [--branch-prefix P]
                        [--max-concurrent N] [--verify CMD]... [--allow-no-verification]
    dispatch-preview.py --defaults ROOT

Preview runs `am run (--milestone ID | --board) --dry-run --repo-dir ROOT`,
then the options given in a fixed order (--base-branch, --branch-prefix,
--max-concurrent, every --verify pair in the order given,
--allow-no-verification), as an argv list (no shell, stdin /dev/null, 60 s
timeout). Every value is the next argument verbatim, even if it starts with
`-`; am refuses bad ones itself. --pretty, --detach and --card are never sent.
A dry run writes nothing, so am is not detached: the store SIGTERMs this helper
when a newer preview starts, and am finishing alone harms nothing.

--defaults never runs am. It asks git, read-only (stdin /dev/null, 10 s timeout
each): `git -C ROOT symbolic-ref refs/remotes/origin/HEAD` names the default
branch (source "origin"), else `git -C ROOT symbolic-ref --short HEAD` names
the checked-out one, unborn included (source "current"). It never fetches and
never writes to the repo.

Prints exactly one JSON line on EVERY path:
- preview: am's envelope, unchanged, whether {"ok": true, "data": ...} or
  {"ok": false, "error": ...}. The envelope's `ok` decides, not am's exit code;
  `data` is never inspected (previewSummary in runs.js reads it);
- {"ok": false, "error": {"type": "AmFailed", ...}} when am exited non-zero
  without an envelope; the message is the tail of am's stderr;
- {"ok": false, "error": {"type": "AmBadOutput", ...}} when am exited 0
  without an envelope;
- {"ok": false, "error": {"type": "AmMissing", ...}} when am is not on PATH;
- defaults: {"ok": true, "data": {"default_branch": B, "source": S}}, or an
  error of type NotAGitRepo, NoDefaultBranch (detached HEAD, no origin/HEAD)
  or GitMissing;
- {"ok": false, "error": {"type": "HelperError", ...}} on any unexpected
  failure (a timeout, an am that cannot start);
- {"ok": false, "error": {"type": "Usage", ...}} for any other command line.
Exit 0 whenever a line was printed, refusals and errors included; exit 2 for
Usage only.
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = ("usage: dispatch-preview.py ROOT (milestone ID | board) [--base-branch B]"
         " [--branch-prefix P] [--max-concurrent N] [--verify CMD]..."
         " [--allow-no-verification] | dispatch-preview.py --defaults ROOT")
VALUED = ("--base-branch", "--branch-prefix", "--max-concurrent")
AM_TIMEOUT = 60
GIT_TIMEOUT = 10
TAIL_LINES = 20
TAIL_CHARS = 2000
ORIGIN = "refs/remotes/origin/"


class BadOutput(Exception):
    """am printed something that is not an envelope; the message says what."""


def failure(kind, message, code=0):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def good_root(root):
    return bool(root) and not root.startswith("-")


def parse(argv):
    """("defaults", root) or ("preview", root, milestone, options) for a command
    line USAGE allows, else None.

    milestone is None for the board. options always maps "--verify" to the list
    of commands in the order given, maps each given VALUED flag to its value and
    "--allow-no-verification" to True when given; a once-only flag given twice
    is a usage error."""
    if argv[:1] == ["--defaults"]:
        if len(argv) != 2 or not good_root(argv[1]):
            return None
        return "defaults", argv[1]
    if len(argv) < 2 or not good_root(argv[0]):
        return None
    root, target, rest = argv[0], argv[1], argv[2:]
    if target == "milestone":
        if not rest or not rest[0]:
            return None
        milestone, rest = rest[0], rest[1:]
    elif target == "board":
        milestone = None
    else:
        return None
    options = {"--verify": []}
    while rest:
        flag = rest[0]
        if flag == "--verify" and len(rest) > 1:
            options["--verify"].append(rest[1])
            rest = rest[2:]
        elif flag in VALUED and len(rest) > 1 and flag not in options:
            options[flag] = rest[1]
            rest = rest[2:]
        elif flag == "--allow-no-verification" and flag not in options:
            options[flag] = True
            rest = rest[1:]
        else:
            return None
    return "preview", root, milestone, options


def preview_argv(root, milestone, options):
    """am's argv after the executable, in a fixed order whatever order the options came in."""
    argv = ["run", "--board"] if milestone is None else ["run", "--milestone", milestone]
    argv += ["--dry-run", "--repo-dir", root]
    for flag in VALUED:
        if flag in options:
            argv += [flag, options[flag]]
    for cmd in options["--verify"]:
        argv += ["--verify", cmd]
    if "--allow-no-verification" in options:
        argv.append("--allow-no-verification")
    return argv


def envelope_of(stdout, returncode):
    """am's envelope, checked only for shape: a JSON object with a boolean `ok`."""
    exit_note = " (exit " + str(returncode) + ")."
    try:
        envelope = json.loads(stdout)
    except ValueError:
        raise BadOutput("am run did not print JSON" + exit_note)
    if not isinstance(envelope, dict):
        raise BadOutput("am run printed JSON that is not an object" + exit_note)
    if not isinstance(envelope.get("ok"), bool):
        raise BadOutput("am run printed an object without a boolean ok field" + exit_note)
    return envelope


def stderr_tail(stderr):
    """The end of am's stderr, where click's usage box or a crash names its cause:
    at most TAIL_LINES lines, and of those at most TAIL_CHARS characters."""
    lines = stderr.rstrip().splitlines()[-TAIL_LINES:]
    return "\n".join(lines)[-TAIL_CHARS:]


def report(stdout, stderr, returncode):
    try:
        envelope = envelope_of(stdout, returncode)
    except BadOutput as e:
        if returncode == 0:
            return failure("AmBadOutput", str(e))
        tail = stderr_tail(stderr)
        return failure("AmFailed", tail or "am run exited " + str(returncode) + " with no output.")
    return emit(envelope)


def run_am(am, argv):
    """(stdout, stderr, returncode) of one dry run."""
    proc = subprocess.run([am, *argv], capture_output=True, encoding="utf-8",
                          errors="replace", stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    return proc.stdout, proc.stderr, proc.returncode


def preview(root, milestone, options):
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    return report(*run_am(am, preview_argv(root, milestone, options)))


def git(exe, root, *args):
    """(returncode, stripped stdout) of one read-only `git -C ROOT ARGS`."""
    proc = subprocess.run([exe, "-C", root, *args], capture_output=True, encoding="utf-8",
                          errors="replace", stdin=subprocess.DEVNULL, timeout=GIT_TIMEOUT)
    return proc.returncode, proc.stdout.strip()


def defaults(root):
    """The branch a dispatch should start from: origin/HEAD's, else the checked-out one."""
    exe = shutil.which("git")
    if exe is None:
        return failure("GitMissing", "git is not installed.")
    if git(exe, root, "rev-parse", "--git-dir")[0] != 0:
        return failure("NotAGitRepo", root + " is not a git repository.")
    code, ref = git(exe, root, "symbolic-ref", ORIGIN + "HEAD")
    if code == 0 and ref.startswith(ORIGIN) and ref[len(ORIGIN):]:
        return emit({"ok": True, "data": {"default_branch": ref[len(ORIGIN):], "source": "origin"}})
    code, branch = git(exe, root, "symbolic-ref", "--short", "HEAD")
    if code == 0 and branch:
        return emit({"ok": True, "data": {"default_branch": branch, "source": "current"}})
    return failure("NoDefaultBranch", "No origin/HEAD and HEAD is detached; enter a base branch.")


def main(argv):
    parsed = parse(argv)
    if parsed is None:
        return failure("Usage", USAGE, 2)
    if parsed[0] == "defaults":
        return defaults(parsed[1])
    return preview(*parsed[1:])


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception (a timeout, an am or git that cannot start) - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The dispatch preview failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_dispatch_preview.py tests/architecture -q`
Expected: PASS (all preview and defaults tests, all architecture tests).

Then the whole suite: `bash tests/run.sh`
Expected: pytest all passed, every QML test `Totals: ... 0 failed`, exit status 0.

Optional hygiene (not a gate): `uvx ruff check core/backend/runs/dispatch-preview.py tests/core/backend/runs/test_dispatch_preview.py`.

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/dispatch-preview.py tests/core/backend/runs/test_dispatch_preview.py
git commit -m "dispatch-preview.py: --defaults reports the repo's default branch from git (S3 2.1)"
```

---

## Self-Review

- **Spec coverage:** Command line and every Usage shape → Task 1 `parse` + `test_usage_shapes` (all 17 shapes; the four `--defaults` shapes are already Usage under Task 1 and stay Usage after Task 2's `--defaults` branch). am argv and fixed order → Task 1 tests 1-6 (`test_milestone_argv`, `test_board_argv`, `test_options_forwarded_in_fixed_order`, `test_verify_values_verbatim`, `test_board_with_branch_prefix`, `test_environment_passed_to_am`). Output rules 1-6 → Task 1 tests 7-19. Defaults steps 1-3, NotAGitRepo, NoDefaultBranch, GitMissing, HelperError, writes nothing → Task 2 tests 20-28 plus the git timeout. AM_TIMEOUT/GIT_TIMEOUT values asserted in the timeout tests. Out-of-scope items untouched.
- **Placeholders:** none; every code step holds the full code.
- **Type consistency:** `parse` returns `("preview", root, milestone, options)` in both tasks and `main` unpacks `parsed[1:]` into `preview(root, milestone, options)`; `("defaults", root)` → `defaults(root)`; test helpers `run(world, args, **extra)`, `calls(world)`, `load_helper()`, `use_world`, `one_line` are defined in Task 1 and only used in Task 2.
- **Review Focus:** each of the five lines has its test in the owning task (named in the section).
<!-- task-pipeline: validated -->
