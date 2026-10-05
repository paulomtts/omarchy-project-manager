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
