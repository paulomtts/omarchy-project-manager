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
