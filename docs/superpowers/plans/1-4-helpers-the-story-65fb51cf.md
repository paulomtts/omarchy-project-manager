# 1.4 Helpers: the story target kind in dispatch-preview.py and start-run.py — design

Card: `65fb51cf` (subtask of story `5c0430d9`). Parent design:
`docs/superpowers/specs/2026-10-05-dispatch-story-level-design.md` (S7), cited below as
"S7 l.N".

## Purpose

The two backend helpers that the dispatch dialog calls know three target kinds today:
`milestone ID`, `card ID` (start only) and `board`. S7 adds a fourth kind, `story ID`, which
maps to `am run --story ID` (S7 l.29-34, l.82-84). This card teaches both helpers that kind.
It also makes `start-run.py` tell two story runs apart when they share one prefix and start
in the same window (S7 l.67-70).

## Inherited constraints

- The helpers accept the target kind `story` and build the argv with `--story`. Everything
  else is unchanged: timeouts, envelope handling, the detached session (S7 l.82-84).
- Run-id discovery for a story run matches `started_at`, prefix **and** `story_id`. The
  `am runs` row carries `story_id` (S7 l.67-70, l.94). The alternative, reading `run_id` from
  an `am run --detach` envelope, does not apply: `start-run.py` does not use `--detach`. It
  polls `am runs` (`core/backend/runs/start-run.py:22-26`).
- A `StoryBlockedError` from `am` must reach the dialog with its type intact, both at preview
  and at start (S7 l.55-61). Other refusals (`ClaimedError`, no match) pass through the same
  way (S7 l.62-64).
- Tests: backend pytest with a fake `am` covers the `--story` argv for preview and start,
  `StoryBlockedError` passthrough, and run-id discovery for a story run, including two story
  runs that share one prefix (S7 l.99-101).
- Layering: backend helpers live in `core/backend` and import only `common.json_line`.
  `tests/architecture` must pass. No new components (card; `docs/architecture.md`).
- Docstrings and comments state the contract only, with no narrative (card).

## Behavior

### dispatch-preview.py

Command line (the `--defaults` form is unchanged):

```
dispatch-preview.py ROOT (milestone ID | story ID | board) [--base-branch B] [--branch-prefix P]
                    [--max-concurrent N] [--verify CMD]... [--allow-no-verification]
dispatch-preview.py --defaults ROOT
```

- `ROOT story ID [options]` runs exactly
  `am run --story ID --dry-run --repo-dir ROOT`, followed by the options in the existing
  fixed order (`--base-branch`, `--branch-prefix`, `--max-concurrent`, each `--verify`
  pair, `--allow-no-verification`). The flags `--pretty`, `--detach`, `--card` and
  `--milestone` are never sent.
- `story` is a literal word. A story whose id is `board` or `milestone` is still a story
  (`ROOT story board` → `--story board`).
- These are usage errors: `story` with no ID, `story` with an empty ID, and anything extra
  after the ID that is not an allowed option. A usage error prints the Usage envelope and
  exits 2, and `am` is never called. The `USAGE` string and the module docstring name
  `story ID` (as `(milestone ID | story ID | board)`, preview form) and the argv
  `am run (--milestone ID | --story ID | --board) --dry-run --repo-dir ROOT`.
- Whatever `am` prints goes back through the existing path, unchanged.
  `{"ok": false, "error": {"type": "StoryBlockedError", "message": ...}}`, with `am`
  exiting 3, is printed verbatim as one line and the helper exits 0. The same holds for
  `{"ok": true, "data": ...}` story plans (`integrate: null`). `AmFailed`, `AmBadOutput`,
  `AmMissing` and `HelperError` behave as they do for the other kinds.
- The internal parse result carries a target kind, not a "milestone or None" slot. The
  milestone and board argv stay byte-for-byte what they are today.

### start-run.py

Command line:

```
start-run.py ROOT (milestone ID | story ID | card ID | board) [--base-branch B] [--branch-prefix P]
             [--max-concurrent N] [--verify CMD]... [--allow-no-verification]
```

- `ROOT story ID [options]` spawns exactly `am run --story ID --repo-dir ROOT_ABS`,
  followed by the options in the fixed order. It never sends `--dry-run`, `--detach` or
  `--pretty`. The spawn (own session, cwd ROOT, stdin /dev/null, log file and its
  permissions), the poll window and the output shapes are unchanged.
- The usage rules match the preview helper: `story` with no ID or an empty ID is a usage
  error, exit 2, `am` not called, no log directory created. `USAGE`, `TARGETS` and the
  module docstring name `story ID`.
- **Run-id discovery.** A row can be this launch's run when it meets every existing
  condition: an id, `started_at` at or after the spawn second, and the prefix rule.
  - For a story launch only, the row must also carry `story_id` equal to the launched ID.
    The comparison is exact, string to string. A row with no `story_id`, a null one, a
    non-string one, or a different one never matches a story launch.
  - The `story_id` condition applies whether or not `--branch-prefix` was given.
  - The prefix rule for a story is the milestone rule: the row's `branch_prefix` must equal
    the given prefix. Only the board accepts `<prefix>-<stem>`.
  - Earliest match wins, as today. A tie goes to the row listed last.
  - Two story runs with one prefix, started in the same window, resolve each launch to its
    own story's row.
  - For `milestone`, `card` and `board` launches, discovery is unchanged. `story_id` is not
    consulted.
- **Refusal passthrough at start.** Say `am` exits before its run appears and the log's last
  non-empty line is `{"ok": false, "error": {"type": "StoryBlockedError", ...}}`. The
  helper prints the existing early-exit shape (`ok`, `error`, `pid`, `log`, `started_at`,
  `exit_code`, `log_tail`). Its `error` is `am`'s error object, verbatim, and the type is
  preserved. Exit 0.

## Error paths (summary)

| Input / condition | Helper | Result |
|---|---|---|
| `ROOT story` (no ID) or `ROOT story ""` | both | Usage envelope, exit 2, no `am` call |
| `ROOT story S --pretty` / unknown option | both | Usage envelope, exit 2 |
| `am` dry run prints `StoryBlockedError` (exit 3) | preview | that envelope verbatim, exit 0 |
| `am run --story` exits early with `StoryBlockedError` | start | early-exit line, `error` = am's object, exit 0 |
| `am run --story` exits early with `ClaimedError` | start | same, type `ClaimedError` |
| a row with matching prefix/time but other or missing `story_id` | start | not this run; if nothing else matches: `run_id: null`, "started, run not visible yet" (am still running) or the early exit (am exited) |

## Tests (all pytest, tier `tests/core/backend/runs/`)

These are hermetic helper tests with a fake `am` on a temporary PATH. That is the tier where
the helpers' argv, envelopes and discovery are already pinned. The real `am` shapes they rely
on (`story_id` on the row, the `StoryBlockedError` envelope) are pinned by the contract tier
(`tests/contract/test_am_shapes.py`, card 1.1), so these tests do not repeat them.

`tests/core/backend/runs/test_dispatch_preview.py`:

1. `test_story_argv`: `["/p", "story", "s1"]` → calls are exactly
   `[["run", "--story", "s1", "--dry-run", "--repo-dir", "/p"]]`, with no `--milestone`,
   `--board`, `--pretty` or `--detach`.
2. `test_story_options_forwarded_in_fixed_order`: a story with options given out of order →
   options in the fixed order after `--repo-dir`.
3. `test_story_named_board`: `["/p", "story", "board"]` → `--story board`.
4. `test_story_blocked_passthrough`: the fake `am` prints a `StoryBlockedError` envelope and
   exits 3 → the helper exits 0 and prints exactly that envelope.
5. `test_story_plan_passthrough`: a story plan envelope (`integrate: null`) prints verbatim.
6. `test_usage_shapes`: remove `["/p", "story", "x"]` (now valid). Add `["/p", "story"]`,
   `["/p", "story", ""]` and `["/p", "story", "s1", "extra"]`. The expected USAGE text is
   updated.

`tests/core/backend/runs/test_start_run.py`:

7. `test_story_argv`: `[root, "story", "s1", "--branch-prefix", "m3"]` → run calls are exactly
   `[["run", "--story", "s1", "--repo-dir", root, "--branch-prefix", "m3"]]`, with no
   `--dry-run`, `--detach` or `--pretty`.
8. `test_story_blocked_early_exit`: the log's last line is a `StoryBlockedError` envelope and
   `am` exits 3 → early-exit keys, `error` equals am's error object, `exit_code == 3`.
9. `test_story_run_matches_story_id` (unit, `find_run`): two rows with prefix `m3`, both
   after SINCE, with `story_id` `s1` and `s2`. A story launch for `s1` finds the `s1` row and
   one for `s2` finds the `s2` row, even when the other story's row is earlier.
10. `test_story_run_requires_story_id` (unit): with a story launch, a row with no `story_id`,
    with `story_id: null`, or with `story_id: 5` → None. This holds with a prefix given and
    with no prefix.
11. `test_story_prefix_rule` (unit): a story launch with prefix `x` does not match a row
    with `branch_prefix: "x-m3"`, even when `story_id` matches.
12. `test_non_story_targets_ignore_story_id` (unit): milestone and board discovery still find
    a row whatever its `story_id` is, so the existing tests stay valid unchanged.
13. `test_two_story_launches_one_prefix` (end to end through `guarded`, with the helper's
    clock at NOON): `am runs` serves two story rows with prefix `m3`, `s2` earlier than `s1`.
    Launching `story s1` reports `s1`'s run id.
14. `test_usage_shapes`: remove `["/p", "story", "x"]`. Add `["/p", "story"]` and
    `["/p", "story", ""]`. `USAGE_LINE` is updated to the new text.

The `row()` test helper gains an optional `story_id` keyword. When it is omitted, the key is
absent, so the existing rows keep their shape.

Verification: `bash tests/run.sh` green, which includes `tests/architecture`.

## Out of scope

- `core/domain/runs.js` (`dispatchPlan`, `previewSummary`, `dispatchDefaults`): cards 1.2
  and 1.3.
- `viewer-state.py` `prefixByMilestone`: its own card.
- `RunStore.qml`, `DispatchDialog.qml`, `CardDetailScreen`, `Shortcuts.qml`, the retarget
  action, UI tests: later cards (S7 l.87-88, l.102-105).
- Contract tests and the `tests/fixtures/am/*.json` fixtures (card 1.1). Leave the fixtures
  as they are.
- Using `am run --detach`, and any change to timeouts, the poll window, the log location or
  the output shapes.
- Excluding story runs from milestone-launch discovery. A milestone launch's discovery is
  unchanged by this card.

## Notes for the planner

Follow `docs/superpowers/plans/` and the writing-plans format. The two helpers can be two
tasks (preview, then start). In each task, tests come first. Keep `find_run` and `matches`
callable with the existing positional arguments, for example by adding the launched id as a
trailing optional parameter, so the current unit tests run unchanged. `watch` and `main`
thread the id through.

---

# 1.4 Helpers: the story target kind in dispatch-preview.py and start-run.py — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `dispatch-preview.py` and `start-run.py` accept the target kind `story ID`, send `am run --story ID`, and `start-run.py` finds a story run's id by `started_at`, prefix **and** `story_id`.

**Architecture:** Two Python helpers in `core/backend/runs/`, each changed in place. Task 1 teaches `dispatch-preview.py` the kind: its parse result carries `(target, ident)` instead of a "milestone or None" slot, and the argv builder becomes the same `--<target> ID` rule `start-run.py` already uses. Task 2 adds `story` to `start-run.py`'s `TARGETS`, gives `matches`/`find_run` a trailing optional `ident` parameter that a story launch requires to equal the row's `story_id`, and threads the id through `watch` and `main`.

**Tech Stack:** Python 3 standard library only (helpers import only `common.json_line`), pytest with a fake `am` on a temporary PATH.

**Spec:** `docs/superpowers/specs/1-4-helpers-the-story-65fb51cf.md` (prepended above).

## Global Constraints

- The helpers accept the target kind `story` and build the argv with `--story`. Everything else is unchanged: timeouts, envelope handling, the detached session.
- `story` is a literal word. A story whose id is `board` or `milestone` is still a story (`ROOT story board` → `--story board`).
- `story` with no ID, `story` with an empty ID, or anything extra after the ID that is not an allowed option is a usage error: Usage envelope, exit 2, `am` never called (and, for `start-run.py`, no log directory created).
- Preview argv: `am run --story ID --dry-run --repo-dir ROOT`, then `--base-branch`, `--branch-prefix`, `--max-concurrent`, each `--verify` pair, `--allow-no-verification`. Never `--pretty`, `--detach`, `--card`, `--milestone`.
- Start argv: `am run --story ID --repo-dir ROOT_ABS`, then the options in the same fixed order. Never `--dry-run`, `--detach`, `--pretty`.
- The milestone, card and board argv stay byte-for-byte what they are today.
- Run-id discovery for a story launch: every existing condition plus `story_id` equal to the launched ID, exact string to string; a row with no, null, non-string or different `story_id` never matches. Applies with or without `--branch-prefix`. The story prefix rule is the milestone rule (equal only). Earliest wins, tie to the row listed last. For `milestone`, `card`, `board` launches `story_id` is not consulted.
- `find_run` and `matches` stay callable with the existing positional arguments; the launched id is a trailing optional parameter.
- Backend helpers live in `core/backend` and import only `common.json_line`; `tests/architecture` must pass; no new components.
- Docstrings and comments state the contract only, with no narrative (no "now", "new", "used to", "no longer").
- `tests/fixtures/am/*.json` and `tests/contract/` are not touched.

## Review Focus

1. A story whose ID is a reserved word (`board`) launched through `start-run.py` — a person expects `--story board`, not a board run. Pinned in `test_story_named_board` (Task 2).
2. A row whose `story_id` is the number `5` while the launched story's ID is the string `"5"` — a person expects no match (exact string comparison). Pinned in `test_story_run_requires_story_id` (Task 2).
3. `am run --story` exiting early with `ClaimedError` (not only `StoryBlockedError`) — a person expects that refusal, type intact, in the early-exit line. Pinned in `test_story_claimed_early_exit` (Task 2).
4. A story start with its options given out of order — a person expects the same fixed order as a milestone start. Pinned in `test_story_options_forwarded_in_fixed_order` (Task 2).
5. A story preview or start given a flag `am` must never receive (`--pretty`, `--detach`, `--milestone m1`) — a person expects a usage error, never an `am` call. Pinned in `test_usage_shapes` (Task 1 and Task 2).

## How to run the tests

The system `python3` has no pytest; run it through uv:

- One file: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_dispatch_preview.py -q`
- One test: `uv run --with pytest python3 -m pytest "tests/core/backend/runs/test_start_run.py::test_story_argv" -q`
- Everything (pytest tiers including `tests/architecture`, then every QML test): `bash tests/run.sh`. It takes a few minutes; give it a 10-minute timeout.

---

### Task 1: dispatch-preview.py accepts `story ID`

**Files:**
- Modify: `core/backend/runs/dispatch-preview.py:1-15` (module docstring), `:50-52` (`USAGE`), `:53` (add `TARGETS`), `:73-110` (`parse`), `:113-124` (`preview_argv`), `:166-170` (`preview`)
- Test: `tests/core/backend/runs/test_dispatch_preview.py` (`USAGE_LINE` at `:48-51`, new constants after `CLAIMED` at `:73-74`, new tests after `test_milestone_named_board` at `:175-180` and after `test_refusal_passthrough_exit_3` at `:270-274`, `test_usage_shapes` parameters at `:409-427`)

**Interfaces:**
- Consumes: nothing from Task 2.
- Produces: `parse(argv)` returns `("defaults", root)` or `("preview", root, target, ident, options)` with `target in ("milestone", "story", "board")` and `ident` a non-empty `str` (or `None` for `"board"`); `preview_argv(root, target, ident, options) -> list[str]`; `preview(root, target, ident, options) -> int`. `main` is unchanged (`preview(*parsed[1:])`). No other module imports these.

- [ ] **Step 1: Write the failing tests**

In `tests/core/backend/runs/test_dispatch_preview.py`, replace the `USAGE_LINE` definition (lines 48-51):

```python
USAGE_LINE = {"ok": False, "error": {"type": "Usage", "message":
              "usage: dispatch-preview.py ROOT (milestone ID | board) [--base-branch B]"
              " [--branch-prefix P] [--max-concurrent N] [--verify CMD]..."
              " [--allow-no-verification] | dispatch-preview.py --defaults ROOT"}}
```

with:

```python
USAGE_LINE = {"ok": False, "error": {"type": "Usage", "message":
              "usage: dispatch-preview.py ROOT (milestone ID | story ID | board) [--base-branch B]"
              " [--branch-prefix P] [--max-concurrent N] [--verify CMD]..."
              " [--allow-no-verification] | dispatch-preview.py --defaults ROOT"}}
```

Right after the `CLAIMED = ...` definition (lines 73-74), add:

```python
STORY_PLAN = {"ok": True, "data": {
    "max_concurrent": 4,
    "levels": [
        {"level": 0, "concurrent": 1, "stories": [
            {"story": "s1", "title": "Story one", "root": "m3-c0",
             "subtasks": [{"card": "c1", "branch": "m3-c1", "base": "m3-c0"}]}]},
    ],
    "already_done": [],
    "integrate": None,
}}
STORY_BLOCKED = {"ok": False, "error": {"type": "StoryBlockedError",
                                        "message": "story s1 is blocked by s0 (todo)"}}
```

Right after `test_milestone_named_board` (ends line 180), add:

```python
def test_story_argv(world):
    set_envelope(world, STORY_PLAN)
    code, _ = run(world, ["/p", "story", "s1"])
    assert code == 0
    made = calls(world)
    assert made == [["run", "--story", "s1", "--dry-run", "--repo-dir", "/p"]]
    for never in ("--milestone", "--board", "--card", "--pretty", "--detach"):
        assert never not in made[0]


def test_story_options_forwarded_in_fixed_order(world):
    set_envelope(world, STORY_PLAN)
    code, _ = run(world, ["/p", "story", "s1",
                          "--verify", "uv run pytest", "--max-concurrent", "2",
                          "--branch-prefix", "m3", "--base-branch", "main",
                          "--verify", "-x", "--allow-no-verification"])
    assert code == 0
    assert calls(world) == [["run", "--story", "s1", "--dry-run", "--repo-dir", "/p",
                             "--base-branch", "main", "--branch-prefix", "m3",
                             "--max-concurrent", "2",
                             "--verify", "uv run pytest", "--verify", "-x",
                             "--allow-no-verification"]]


def test_story_named_board(world):
    # The target is a literal word, so a story whose id is "board" stays a story.
    set_envelope(world, STORY_PLAN)
    code, _ = run(world, ["/p", "story", "board"])
    assert code == 0
    assert calls(world) == [["run", "--story", "board", "--dry-run", "--repo-dir", "/p"]]
    code, _ = run(world, ["/p", "story", "milestone"])
    assert code == 0
    assert calls(world)[-1] == ["run", "--story", "milestone", "--dry-run", "--repo-dir", "/p"]
```

Right after `test_refusal_passthrough_exit_3` (ends line 274), add:

```python
def test_story_blocked_passthrough(world):
    set_envelope(world, STORY_BLOCKED, code=3)
    code, out = run(world, ["/p", "story", "s1", "--branch-prefix", "m3"])
    assert code == 0
    assert out == STORY_BLOCKED


def test_story_plan_passthrough(world):
    set_envelope(world, STORY_PLAN)
    code, out = run(world, ["/p", "story", "s1", "--branch-prefix", "m3"])
    assert code == 0
    assert out == STORY_PLAN
```

In `test_usage_shapes`'s parameter list (lines 409-427), replace the line

```python
    ["/p", "story", "x"],
```

with:

```python
    ["/p", "story"],
    ["/p", "story", ""],
    ["/p", "story", "s1", "extra"],
    ["/p", "story", "s1", "--pretty"],
    ["/p", "story", "s1", "--detach"],
    ["/p", "story", "s1", "--milestone", "m1"],
    ["/p", "story", "s1", "--branch-prefix"],
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_dispatch_preview.py -q`
Expected: FAIL. `test_story_argv`, `test_story_options_forwarded_in_fixed_order`, `test_story_named_board`, `test_story_blocked_passthrough` and `test_story_plan_passthrough` fail with `assert 2 == 0` (the helper rejects `story` as Usage); every `test_usage_shapes[...]` case and `test_am_missing` fail on the Usage message (`(milestone ID | board)` vs `(milestone ID | story ID | board)`).

- [ ] **Step 3: Implement**

In `core/backend/runs/dispatch-preview.py`, replace the start of the module docstring (lines 2-13):

```python
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
```

with:

```python
"""Preview a dispatch: an `am run --dry-run` passthrough, and the repo's default branch.

    dispatch-preview.py ROOT (milestone ID | story ID | board) [--base-branch B]
                        [--branch-prefix P] [--max-concurrent N] [--verify CMD]...
                        [--allow-no-verification]
    dispatch-preview.py --defaults ROOT

Preview runs `am run (--milestone ID | --story ID | --board) --dry-run --repo-dir ROOT`,
then the options given in a fixed order (--base-branch, --branch-prefix,
--max-concurrent, every --verify pair in the order given,
--allow-no-verification), as an argv list (no shell, stdin /dev/null, 60 s
timeout). The target is a literal word: `story board` names the story "board".
Every value is the next argument verbatim, even if it starts with `-`; am
refuses bad ones itself. --pretty, --detach and --card are never sent.
```

Replace `USAGE` and the `VALUED` line (lines 50-53):

```python
USAGE = ("usage: dispatch-preview.py ROOT (milestone ID | board) [--base-branch B]"
         " [--branch-prefix P] [--max-concurrent N] [--verify CMD]..."
         " [--allow-no-verification] | dispatch-preview.py --defaults ROOT")
VALUED = ("--base-branch", "--branch-prefix", "--max-concurrent")
```

with:

```python
USAGE = ("usage: dispatch-preview.py ROOT (milestone ID | story ID | board) [--base-branch B]"
         " [--branch-prefix P] [--max-concurrent N] [--verify CMD]..."
         " [--allow-no-verification] | dispatch-preview.py --defaults ROOT")
VALUED = ("--base-branch", "--branch-prefix", "--max-concurrent")
TARGETS = ("milestone", "story")
```

Replace the head of `parse` (lines 73-95):

```python
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
```

with:

```python
def parse(argv):
    """("defaults", root) or ("preview", root, target, id, options) for a command
    line USAGE allows, else None.

    target is "milestone", "story" or "board"; id is None for the board. options
    always maps "--verify" to the list of commands in the order given, maps each
    given VALUED flag to its value and "--allow-no-verification" to True when
    given; a once-only flag given twice is a usage error."""
    if argv[:1] == ["--defaults"]:
        if len(argv) != 2 or not good_root(argv[1]):
            return None
        return "defaults", argv[1]
    if len(argv) < 2 or not good_root(argv[0]):
        return None
    root, target, rest = argv[0], argv[1], argv[2:]
    if target in TARGETS:
        if not rest or not rest[0]:
            return None
        ident, rest = rest[0], rest[1:]
    elif target == "board":
        ident = None
    else:
        return None
```

Replace the last line of `parse` (line 110):

```python
    return "preview", root, milestone, options
```

with:

```python
    return "preview", root, target, ident, options
```

Replace `preview_argv`'s signature and first line (lines 113-115):

```python
def preview_argv(root, milestone, options):
    """am's argv after the executable, in a fixed order whatever order the options came in."""
    argv = ["run", "--board"] if milestone is None else ["run", "--milestone", milestone]
```

with:

```python
def preview_argv(root, target, ident, options):
    """am's argv after the executable, in a fixed order whatever order the options came in."""
    argv = ["run", "--board"] if target == "board" else ["run", "--" + target, ident]
```

Replace `preview` (lines 166-170):

```python
def preview(root, milestone, options):
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    return report(*run_am(am, preview_argv(root, milestone, options)))
```

with:

```python
def preview(root, target, ident, options):
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    return report(*run_am(am, preview_argv(root, target, ident, options)))
```

`main` stays as it is: `return preview(*parsed[1:])` now passes `root, target, ident, options`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_dispatch_preview.py tests/architecture -q`
Expected: PASS, every test (the existing milestone and board argv tests unchanged and green).

Then: `grep -n "milestone" core/backend/runs/dispatch-preview.py`
Expected: no remaining reference to a `milestone` variable (only the docstring, `USAGE` and `TARGETS` strings).

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/dispatch-preview.py tests/core/backend/runs/test_dispatch_preview.py
git commit -m "feat(runs): dispatch-preview.py previews a story as am run --story"
```

---

### Task 2: start-run.py starts `story ID` and finds its run by `story_id`

**Files:**
- Modify: `core/backend/runs/start-run.py:1-26` (module docstring), `:60-64` (`USAGE`, `TARGETS`), `:87-93` (`parse` docstring), `:192-218` (`matches`, `find_run`), `:279-287` (`watch`), `:314` (`main`'s call to `watch`)
- Test: `tests/core/backend/runs/test_start_run.py` (`USAGE_LINE` at `:96-99`, new constant after `CLAIMED` at `:100-101`, new argv tests after `test_board_argv` at `:223-229`, `test_usage_shapes` parameters at `:437-452`, new early-exit tests after `test_early_exit_with_am_refusal` at `:464-476`, `row()` at `:532-534`, new discovery tests after `test_malformed_rows_skipped` at `:614-620`)

**Interfaces:**
- Consumes: nothing from Task 1 (the helpers share no code).
- Produces: `TARGETS = ("milestone", "story", "card")`; `parse(argv) -> (root, target, ident, options) | None`; `run_argv(root, target, ident, options)` unchanged; `matches(row, target, prefix, since, ident=None) -> bool`; `find_run(rows, target, prefix, since, ident=None) -> str | None`; `watch(proc, am, root, target, ident, prefix, launch, started, deadline) -> int`. Test helper `row(run_id, started_at, prefix="m3", story_id=ABSENT)` in the test file.

- [ ] **Step 1: Write the failing tests**

In `tests/core/backend/runs/test_start_run.py`, replace the `USAGE_LINE` definition (lines 96-99):

```python
USAGE_LINE = {"ok": False, "error": {"type": "Usage", "message":
              "usage: start-run.py ROOT (milestone ID | card ID | board) [--base-branch B]"
              " [--branch-prefix P] [--max-concurrent N] [--verify CMD]..."
              " [--allow-no-verification]"}}
```

with:

```python
USAGE_LINE = {"ok": False, "error": {"type": "Usage", "message":
              "usage: start-run.py ROOT (milestone ID | story ID | card ID | board)"
              " [--base-branch B] [--branch-prefix P] [--max-concurrent N] [--verify CMD]..."
              " [--allow-no-verification]"}}
```

Right after the `CLAIMED = ...` definition (lines 100-101), add:

```python
STORY_BLOCKED = {"ok": False, "error": {"type": "StoryBlockedError",
                                        "message": "story s1 is blocked by s0 (todo)"}}
```

Right after `test_board_argv` (ends line 229), add:

```python
def test_story_argv(world):
    root = str(world["project"])
    code, _ = run(world, [root, "story", "s1", "--branch-prefix", "m3"])
    assert code == 0
    made = run_calls(world)
    assert made == [["run", "--story", "s1", "--repo-dir", root, "--branch-prefix", "m3"]]
    for never in ("--dry-run", "--detach", "--pretty", "--milestone", "--card", "--board"):
        assert never not in made[0]


def test_story_options_forwarded_in_fixed_order(world):
    root = str(world["project"])
    code, _ = run(world, [root, "story", "s1",
                          "--verify", "uv run pytest", "--max-concurrent", "2",
                          "--branch-prefix", "m3", "--base-branch", "main",
                          "--verify", "-x", "--allow-no-verification"])
    assert code == 0
    assert run_calls(world) == [["run", "--story", "s1", "--repo-dir", root,
                                 "--base-branch", "main", "--branch-prefix", "m3",
                                 "--max-concurrent", "2",
                                 "--verify", "uv run pytest", "--verify", "-x",
                                 "--allow-no-verification"]]


def test_story_named_board(world):
    # The target is a literal word, so a story whose id is "board" stays a story.
    root = str(world["project"])
    code, _ = run(world, [root, "story", "board"])
    assert code == 0
    assert run_calls(world) == [["run", "--story", "board", "--repo-dir", root]]
```

In `test_usage_shapes`'s parameter list (lines 437-452), replace the line

```python
    ["/p", "story", "x"],
```

with:

```python
    ["/p", "story"],
    ["/p", "story", ""],
    ["/p", "story", "s1", "extra"],
    ["/p", "story", "s1", "--pretty"],
    ["/p", "story", "s1", "--dry-run"],
    ["/p", "story", "s1", "--milestone", "m1"],
```

Right after `test_early_exit_with_am_refusal` (ends line 476), add:

```python
def test_story_blocked_early_exit(world):
    (world["am"] / "run.out").write_text(json.dumps(STORY_BLOCKED) + "\n")
    (world["am"] / "run.code").write_text("3")
    root = str(world["project"])
    code, out = run(world, [root, "story", "s1", "--branch-prefix", "m3"])
    assert code == 0
    assert set(out) == EARLY_KEYS
    assert out["ok"] is False
    assert out["error"] == STORY_BLOCKED["error"]
    assert out["exit_code"] == 3
    assert json.dumps(STORY_BLOCKED) in out["log_tail"]
    assert run_calls(world) == [["run", "--story", "s1", "--repo-dir", root,
                                 "--branch-prefix", "m3"]]


def test_story_claimed_early_exit(world):
    (world["am"] / "run.out").write_text(json.dumps(CLAIMED) + "\n")
    (world["am"] / "run.code").write_text("3")
    code, out = run(world, [str(world["project"]), "story", "s1", "--branch-prefix", "m3"])
    assert code == 0
    assert set(out) == EARLY_KEYS
    assert out["error"] == CLAIMED["error"]
    assert out["exit_code"] == 3
```

Replace the `row` helper (lines 532-534):

```python
def row(run_id, started_at, prefix="m3"):
    return {"id": run_id, "workflow": "orchestrator", "repo_dir": "/p", "base_branch": "main",
            "branch_prefix": prefix, "status": "running", "started_at": started_at}
```

with:

```python
ABSENT = object()


def row(run_id, started_at, prefix="m3", story_id=ABSENT):
    """An `am runs` row; `story_id` is set only when given, so by default the key is absent."""
    r = {"id": run_id, "workflow": "orchestrator", "repo_dir": "/p", "base_branch": "main",
         "branch_prefix": prefix, "status": "running", "started_at": started_at}
    if story_id is not ABSENT:
        r["story_id"] = story_id
    return r
```

Right after `test_malformed_rows_skipped` (ends line 620), add:

```python
def test_story_run_matches_story_id():
    helper = load_helper()
    # am lists newest first; the other story's row is the earlier one each time.
    rows = [row("r-s1", "2026-10-05T12:00:05Z", story_id="s1"),
            row("r-s2", "2026-10-05T12:00:02Z", story_id="s2")]
    assert helper.find_run(rows, "story", "m3", SINCE, "s1") == "r-s1"
    assert helper.find_run(rows, "story", "m3", SINCE, "s2") == "r-s2"
    rows = [row("r-s2", "2026-10-05T12:00:06Z", story_id="s2"),
            row("r-s1", "2026-10-05T12:00:01Z", story_id="s1")]
    assert helper.find_run(rows, "story", "m3", SINCE, "s2") == "r-s2"
    assert helper.find_run(rows, "story", "m3", SINCE, "s1") == "r-s1"
    # Among one story's rows, the earliest still wins, a tie to the one listed last.
    rows = [row("later", "2026-10-05T12:00:09Z", story_id="s1"),
            row("tie-first", "2026-10-05T12:00:02Z", story_id="s1"),
            row("tie-last", "2026-10-05T12:00:02Z", story_id="s1")]
    assert helper.find_run(rows, "story", "m3", SINCE, "s1") == "tie-last"


@pytest.mark.parametrize("prefix", ["m3", None], ids=["prefix", "no-prefix"])
def test_story_run_requires_story_id(prefix):
    helper = load_helper()
    when = "2026-10-05T12:00:01Z"
    assert helper.find_run([row("r", when)], "story", prefix, SINCE, "s1") is None
    assert helper.find_run([row("r", when, story_id=None)], "story", prefix, SINCE, "s1") is None
    assert helper.find_run([row("r", when, story_id=5)], "story", prefix, SINCE, "5") is None
    assert helper.find_run([row("r", when, story_id="s2")], "story", prefix, SINCE, "s1") is None
    assert helper.find_run([row("r", when, story_id="S1")], "story", prefix, SINCE, "s1") is None
    assert helper.find_run([row("r", when, story_id="s1")], "story", prefix, SINCE, "s1") == "r"
    # A story launch with no id given matches no row.
    assert helper.find_run([row("r", when, story_id="s1")], "story", prefix, SINCE) is None
    assert helper.find_run([row("r", when)], "story", prefix, SINCE) is None
    # The time rule still holds for a story.
    assert helper.find_run([row("r", "2026-10-05T11:59:59Z", story_id="s1")],
                           "story", prefix, SINCE, "s1") is None


def test_story_prefix_rule():
    helper = load_helper()
    when = "2026-10-05T12:00:01Z"
    # Only the board derives <prefix>-<stem>; a story's prefix must be equal.
    assert helper.find_run([row("r", when, prefix="x-m3", story_id="s1")],
                           "story", "x", SINCE, "s1") is None
    assert helper.find_run([row("r", when, prefix="x", story_id="s1")],
                           "story", "x", SINCE, "s1") == "r"
    assert helper.find_run([row("r", when, prefix=None, story_id="s1")],
                           "story", "x", SINCE, "s1") is None


def test_non_story_targets_ignore_story_id():
    helper = load_helper()
    when = "2026-10-05T12:00:01Z"
    for story_id in (ABSENT, "s1", None, 5):
        r = row("r", when, story_id=story_id)
        assert helper.find_run([r], "milestone", "m3", SINCE) == "r"
        assert helper.find_run([r], "milestone", "m3", SINCE, "m1") == "r"
        assert helper.find_run([r], "card", "m3", SINCE, "c1") == "r"
        assert helper.find_run([r], "board", None, SINCE) == "r"
        assert helper.matches(r, "milestone", "m3", SINCE) is True


@pytest.mark.parametrize("story,expected", [("s1", "r-s1"), ("s2", "r-s2")])
def test_two_story_launches_one_prefix(world, monkeypatch, capsys, story, expected):
    helper = fast_helper(monkeypatch, world)
    at_noon(helper, monkeypatch)
    # Newest first: s1's run is the later one, a milestone run without story_id the earliest.
    seed_runs(world, [row("r-s1", "2026-10-05T12:00:04Z", story_id="s1"),
                      row("r-s2", "2026-10-05T12:00:02Z", story_id="s2"),
                      row("r-m", "2026-10-05T12:00:01Z")])
    (world["am"] / "run.sleep").write_text("2")
    root = str(world["project"])
    assert helper.guarded([root, "story", story, "--branch-prefix", "m3"]) == 0
    out = one_line(capsys)
    assert out == {"ok": True, "pid": read_pid(world), "log": out["log"],
                   "started_at": "2026-10-05T12:00:00Z", "run_id": expected, "message": ""}
    assert run_calls(world) == [["run", "--story", story, "--repo-dir", root,
                                 "--branch-prefix", "m3"]]


def test_story_run_not_visible_when_no_row_carries_its_id(world, monkeypatch, capsys):
    helper = fast_helper(monkeypatch, world, window=0.3)
    at_noon(helper, monkeypatch)
    seed_runs(world, [row("r-s2", "2026-10-05T12:00:02Z", story_id="s2"),
                      row("r-m", "2026-10-05T12:00:01Z")])
    (world["am"] / "run.sleep").write_text("5")
    assert helper.guarded([str(world["project"]), "story", "s1", "--branch-prefix", "m3"]) == 0
    out = one_line(capsys)
    assert out["ok"] is True
    assert out["run_id"] is None
    assert out["message"] == "started, run not visible yet"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_start_run.py -q`
Expected: FAIL. The argv, early-exit and end-to-end story tests fail because `story` is a usage error (exit 2 instead of 0; `guarded` returns 2); `test_story_run_matches_story_id`, `test_story_run_requires_story_id`, `test_story_prefix_rule` and `test_non_story_targets_ignore_story_id` fail with `TypeError: find_run() takes 4 positional arguments but 5 were given`; every `test_usage_shapes[...]` case fails on the Usage message. The existing tests that do not use `story` still pass.

- [ ] **Step 3: Implement**

In `core/backend/runs/start-run.py`, replace the start of the module docstring (lines 2-12):

```python
"""Start a dispatch: `am run`, detached, and the id of the run it started.

    start-run.py ROOT (milestone ID | card ID | board) [--base-branch B] [--branch-prefix P]
                 [--max-concurrent N] [--verify CMD]... [--allow-no-verification]

Spawns `am run (--milestone ID | --card ID | --board) --repo-dir ROOT`, then the
options given in a fixed order (--base-branch, --branch-prefix, --max-concurrent,
every --verify pair in the order given, --allow-no-verification), as an argv list
(no shell), ROOT made absolute. Every value is the next argument verbatim, even if
it starts with `-`; am refuses bad ones itself. --dry-run, --detach and --pretty
are never sent.
```

with:

```python
"""Start a dispatch: `am run`, detached, and the id of the run it started.

    start-run.py ROOT (milestone ID | story ID | card ID | board) [--base-branch B]
                 [--branch-prefix P] [--max-concurrent N] [--verify CMD]...
                 [--allow-no-verification]

Spawns `am run (--milestone ID | --story ID | --card ID | --board) --repo-dir ROOT`,
then the options given in a fixed order (--base-branch, --branch-prefix,
--max-concurrent, every --verify pair in the order given, --allow-no-verification),
as an argv list (no shell), ROOT made absolute. The target is a literal word:
`story board` names the story "board". Every value is the next argument verbatim,
even if it starts with `-`; am refuses bad ones itself. --dry-run, --detach and
--pretty are never sent.
```

Replace the discovery paragraph of the module docstring (lines 22-26):

```python
For up to POLL_WINDOW seconds after the spawn it asks `am runs --repo-dir ROOT`
every POLL_INTERVAL seconds for the run this launch started: a row with an id,
started at or after the spawn (to the second), whose branch_prefix is the one
given (for the board, also `<prefix>-<stem>`; any, when none was given); the
earliest such row wins. A failing `am runs` is retried on the next tick.
```

with:

```python
For up to POLL_WINDOW seconds after the spawn it asks `am runs --repo-dir ROOT`
every POLL_INTERVAL seconds for the run this launch started: a row with an id,
started at or after the spawn (to the second), whose branch_prefix is the one
given (for the board, also `<prefix>-<stem>`; any, when none was given) and, for
a story, whose story_id is the story's ID, string for string; the earliest such
row wins, on a tie the one listed last. A failing `am runs` is retried on the
next tick.
```

Replace `USAGE` through `TARGETS` (lines 60-64):

```python
USAGE = ("usage: start-run.py ROOT (milestone ID | card ID | board) [--base-branch B]"
         " [--branch-prefix P] [--max-concurrent N] [--verify CMD]..."
         " [--allow-no-verification]")
VALUED = ("--base-branch", "--branch-prefix", "--max-concurrent")
TARGETS = ("milestone", "card")
```

with:

```python
USAGE = ("usage: start-run.py ROOT (milestone ID | story ID | card ID | board)"
         " [--base-branch B] [--branch-prefix P] [--max-concurrent N] [--verify CMD]..."
         " [--allow-no-verification]")
VALUED = ("--base-branch", "--branch-prefix", "--max-concurrent")
TARGETS = ("milestone", "story", "card")
```

In `parse`'s docstring (line 90), replace:

```python
    target is "milestone", "card" or "board"; id is None for the board. options
```

with:

```python
    target is "milestone", "story", "card" or "board"; id is None for the board. options
```

Replace `matches` and `find_run` (lines 192-218):

```python
def matches(row, target, prefix, since):
    """Whether an `am runs` row can be the run this launch started: it has an id,
    started at or after `since`, and carries the prefix given (the board's runs may
    carry `<prefix>-<stem>`); with no prefix given, any."""
    if not isinstance(row, dict) or not isinstance(row.get("id"), str) or not row["id"]:
        return False
    when = parse_time(row.get("started_at"))
```

with:

```python
def matches(row, target, prefix, since, ident=None):
    """Whether an `am runs` row can be the run this launch started: it has an id,
    started at or after `since`, carries the prefix given (the board's runs may
    carry `<prefix>-<stem>`; with no prefix given, any) and, for a story launch,
    carries a string story_id equal to `ident`. Other targets ignore story_id."""
    if not isinstance(row, dict) or not isinstance(row.get("id"), str) or not row["id"]:
        return False
    if target == "story" and (not isinstance(row.get("story_id"), str)
                              or row["story_id"] != ident):
        return False
    when = parse_time(row.get("started_at"))
```

and then (same region) replace:

```python
def find_run(rows, target, prefix, since):
    """The id of the earliest matching row (on a tie, the one listed last: the
    oldest in am's newest-first order), else None."""
    best = None
    for row in rows:
        if matches(row, target, prefix, since):
```

with:

```python
def find_run(rows, target, prefix, since, ident=None):
    """The id of the earliest matching row (on a tie, the one listed last: the
    oldest in am's newest-first order), else None."""
    best = None
    for row in rows:
        if matches(row, target, prefix, since, ident):
```

Replace the head of `watch` (lines 279-287):

```python
def watch(proc, am, root, target, prefix, launch, started, deadline):
    """Tick every POLL_INTERVAL until the run appears, am exits or the window ends;
    one last tick runs at or after the deadline. Whether am has exited is read
    before `am runs` is asked: an exit seen first means its row, if any, was
    already written, so an exit during the query is never taken for an early exit."""
    while True:
        last = time.monotonic() >= deadline
        exited = proc.poll() is not None
        run_id = find_run(list_runs(am, root), target, prefix, started)
```

with:

```python
def watch(proc, am, root, target, ident, prefix, launch, started, deadline):
    """Tick every POLL_INTERVAL until the run appears, am exits or the window ends;
    one last tick runs at or after the deadline. Whether am has exited is read
    before `am runs` is asked: an exit seen first means its row, if any, was
    already written, so an exit during the query is never taken for an early exit."""
    while True:
        last = time.monotonic() >= deadline
        exited = proc.poll() is not None
        run_id = find_run(list_runs(am, root), target, prefix, started, ident)
```

Replace the last line of `main` (line 314):

```python
    return watch(proc, am, root, target, options.get("--branch-prefix"), launch, started, deadline)
```

with:

```python
    return watch(proc, am, root, target, ident, options.get("--branch-prefix"), launch, started,
                 deadline)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/ tests/architecture -q`
Expected: PASS, every test in both helper files (the existing milestone, card and board discovery tests unchanged and green) and the architecture tier.

Then run the full suite: `bash tests/run.sh` (10-minute timeout).
Expected: pytest reports no failures, every QML file prints a `Totals:` line with `0 failed`, exit status 0.

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/start-run.py tests/core/backend/runs/test_start_run.py
git commit -m "feat(runs): start-run.py starts a story and finds its run by story_id"
```

---

## Self-review (planner)

1. **Spec coverage.** Preview `story ID` argv and fixed order → Task 1 tests 1-3; literal word (`story board`, `story milestone`) → `test_story_named_board` (both tasks); usage errors (no ID, empty ID, extra, disallowed flags) → `test_usage_shapes` (both tasks), including "no log directory" (the existing assertion in start's `test_usage_shapes`); USAGE/docstring text → `USAGE_LINE` and Step 3 docstrings; `StoryBlockedError` passthrough at preview (exit 3 → helper exit 0) → `test_story_blocked_passthrough`; story plan with `integrate: null` → `test_story_plan_passthrough`; parse result carries a target kind → Task 1 Step 3 (`("preview", root, target, ident, options)`); milestone/board argv unchanged → existing tests. Start `story ID` argv, never `--dry-run/--detach/--pretty` → `test_story_argv`; `TARGETS` names story → Task 2 Step 3; discovery `story_id` exact, absent/null/non-string/different → `test_story_run_requires_story_id`, with and without prefix (parametrized); story prefix rule = milestone rule → `test_story_prefix_rule`; earliest wins, tie last → `test_story_run_matches_story_id`; two story runs, one prefix → `test_story_run_matches_story_id` and `test_two_story_launches_one_prefix`; non-story discovery ignores `story_id` → `test_non_story_targets_ignore_story_id`; "not visible yet" when no row carries the id → `test_story_run_not_visible_when_no_row_carries_its_id`; refusal passthrough at start (`StoryBlockedError`, `ClaimedError`) → `test_story_blocked_early_exit`, `test_story_claimed_early_exit`; `row()` gains optional `story_id`, absent by default → Task 2 Step 1; `find_run`/`matches` keep their positional signature → trailing `ident=None`; `watch`/`main` thread the id → Task 2 Step 3. Layering: no imports added. Fixtures and contract tests untouched.
2. **Placeholders.** None: every code step carries the full replacement text.
3. **Type consistency.** `ident` is the name for the launched id in `parse`, `run_argv`, `matches`, `find_run`, `watch`, `main` (start) and `parse`, `preview_argv`, `preview` (preview). `find_run(rows, target, prefix, since, ident=None)` is called with `ident` last in tests and in `watch`. `ABSENT` sentinel is defined before `row` and used by `test_non_story_targets_ignore_story_id`.
4. **Review Focus.** Each of its five lines has a pinning test in the owning task (named in the line).
<!-- task-pipeline: validated -->
