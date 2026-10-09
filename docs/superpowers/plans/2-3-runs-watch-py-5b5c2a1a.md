# 2.3 `runs-watch.py`: several project roots — design

Card `5b5c2a1a`, a subtask of story `d1d142ee` ("Global runs backend"). It is
blocked by 2.2 (`835eb103`, `runs-snapshot-all.py`, which landed at `e4d0c32`).
Parent spec: `docs/superpowers/specs/2026-10-05-runs-all-projects-design.md`
(below: **parent**). Layering: `docs/architecture.md` (below: **arch**). The
script being changed is `core/backend/runs/runs-watch.py` (below: **script**).
Its tests are `tests/core/backend/runs/test_runs_watch.py` (below: **tests**).

## Goal

`runs-watch.py` takes one or more project roots and any number of run ids. It
prints `changed` nudges only for the runs it watches. A run is watched when its
id is on the command line, or when a `run_upsert` names one of the roots as its
`repo_dir`. Everything else about the helper stays as it is today: the spawned
am argv, hello handling, the 250 ms debounce, the cursor line, refusals and
exits.

## Where the code stands today (head `e4d0c32`)

The card assumes the helper already takes a root and run ids ("a single root
behaves exactly as today"). It does not:

- script `parse_args` (L78-89) accepts only `[]` or `["--since-seq", N]`.
  Anything else is `Usage`. `USAGE` (L44) is `usage: runs-watch.py [--since-seq N]`.
- Every nudge (`nudge`, L109-118) goes into the batch for any run. The code has
  no watched set, no `same_dir` and no root.
- Commit `727ff6c` removed the old roots design. The last version that had it
  is `727ff6c^:core/backend/runs/runs-watch.py`, with `same_dir` at L100 and
  `keep` at L105-125. This card brings the watched set back, on top of the
  current nudge rules: the ten `EVENTS`, an integer `gseq` of 1 or more, and
  no backlog drop.

So "a single root behaves exactly as today" means the following. With one root
argument, plus the run ids its stream uses, every existing test keeps its
expected output unchanged. Only its argv grows. See "Existing tests" below.

## Inherited constraints

| constraint | source |
|---|---|
| `core/backend/**` imports only the stdlib and `core/backend/common` (`os.path.realpath` is stdlib) | arch L12 |
| A helper is `core/backend/<domain>/name.py`, with a `sys.path` insert of its parent for `common`, no duplicated helpers, and pytest under `tests/core/backend/<domain>/` | arch L214-216 |
| No second `def emit(`, `def inside(`, `def write_atomic(`, `def split_frontmatter(` or `def frontmatter_of(`; keep using `common.json_line.emit` | `tests/architecture/test_layers.py` L231-241 |
| Only documented `am` commands, as argv lists, never a shell; am's database and on-disk layout are never read | arch L196; script docstring L28-29 |
| The spawned command stays `am watch --all-projects --follow [--since-seq N]` | arch L196; script `spawn` L121-125; parent L118-120 |
| The nudge contract: `changed` entries `{run, seq}` hold run ids and gseqs only, event contents are never forwarded, at most one `changed` line per 250 ms, never empty, directly followed by `{"cursor": C}` | arch L196; script docstring L15-19, L25-27 |
| Two registered roots that name one repository list its runs once | parent L168 |
| A stream that spans two repos is a required test | parent L182-183 |
| Usage is exit 2, and argv is checked before `am` is looked up | script `main` L219-225; tests `test_usage_before_am_lookup` |
| Docstrings and comments state the contract only, with no narrative; TDD with tests first; `bash tests/run.sh` green, including `tests/architecture` | card |

Known contradictions, resolved here:

- Parent L118-121 says "`runs-watch.py` takes no roots and no run ids … the
  registry filter happens in the store". Parent L182 says to test "no roots, no
  run ids". The card came later and says otherwise, and the card wins. The 2.2
  spec did the same for parent L113. This subtask does not edit the parent
  spec; the milestone's docs card owns that.
- arch L196 documents `runs-watch.py [--since-seq N]` with "any other argv is
  `Usage`". This card changes that contract, so it updates the `runs-watch.py`
  sentences of arch L196 (see "Docs").
- arch L84 and `core/stores/RunStore.qml` L247-255 start the watch with **no
  argument**. Once this card lands, that launch gets `Usage` (exit 2), and
  RunStore's watch is down until card 3.2 (`b54795cd`, "RunStore: the watch
  covers every root …", blocked) passes every root and the known run ids.
  RunStore, its QML tests and arch L84 are out of scope here; they belong to
  3.2. `tests/core/stores/tst_run_store.qml` only checks the command's script
  path (L374), never runs the script, and stays green.

## Behaviour

### CLI

```
runs-watch.py <root> [<root> ...] [run_id ...] [--since-seq N]
```

`USAGE` is exactly `usage: runs-watch.py <root> [<root> ...] [run_id ...] [--since-seq N]`.
The tests' `USAGE` constant changes to the same string.

Arguments are classified one at a time, left to right, in any order:

| argument | meaning |
|---|---|
| `--since-seq` | takes the next argument as `N`. `N` is one or more ASCII decimal digits and is passed on as its integer's decimal text (`007` becomes `7`, `0` stays `0`), exactly as today. A missing or invalid `N`, or a second `--since-seq`, is `Usage`. |
| starts with `/` | a root. The text is used as given and is never checked for existence. Repeats are allowed. |
| empty, or starts with `-` (other than `--since-seq` above) | `Usage`. This covers `--from-now`, `--since-seq=5` and `-x`. |
| anything else | a run id, watched from the start. Repeats are allowed. |

- No root at all is `Usage`, whatever else is given (for example `[RUN]`,
  `["--since-seq", "5"]`, `[]`).
- On `Usage` the helper prints exactly
  `{"ok": false, "error": {"type": "Usage", "message": USAGE}}` and exits 2.
  It never looks up or spawns `am`. That holds even when `am` is missing.
- Roots and run ids never reach am's argv. am is spawned as
  `["watch", "--all-projects", "--follow"]`, plus `["--since-seq", N]` when
  given.

### The watched set

- When the helper starts, the watched set is the argv run ids.
- A line is a **nudge candidate** exactly as `nudge` defines it today: a JSON
  object whose `event` is in `EVENTS`, whose `run_id` is a non-empty string and
  whose `gseq` is an integer of 1 or more (not a bool).
- A nudge candidate is **kept** in either of these cases:
  1. its `run_id` is already watched, or
  2. its `event` is `run_upsert`, its `payload` is a JSON object, and
     `payload.repo_dir` is a string that names the same directory as **any**
     root. In this case the run is added to the watched set for good, and the
     `run_upsert` that added it is itself kept.
- "Names the same directory" means `os.path.realpath(repo_dir) ==
  os.path.realpath(root)`. A trailing slash, `.`/`..` segments and symlinks
  therefore all match. Neither path has to exist. Each root's realpath is
  computed once, when the helper starts.
- Any other nudge candidate is dropped. A dropped line does not enter the
  batch, does not move the cursor, does not open a debounce window and prints
  nothing.
- Lines that are not nudge candidates are ignored, as today. That includes a
  `run_upsert` with `gseq` 0 or a missing `run_id`, and such a line never adds
  a run to the watched set.
- A run never leaves the watched set. A later `run_upsert` of a watched run
  that names some other `repo_dir` is still kept.
- Lines are handled in stream order. If a run's event comes before its
  `run_upsert`, that event is dropped, unless the run id was on the command
  line. In the capture this happens with `lease_acquired` (gseq 358), which
  comes before the `run_upsert` (gseq 359).

### Output (unchanged except for what is watched)

- The hello line, its checks (`SchemaMismatch`) and "only the first is
  printed" are unchanged. Hello lines are never filtered by root.
- `{"changed": [{"run", "seq"}, ...]}`: only kept nudges, at most one line per
  `WINDOW` (0.25 s), never empty, and one entry per run carrying its highest
  kept gseq in the window. Entries hold run ids only, never roots,
  `repo_dir`s or any event content. A run that two roots both match (two
  roots naming one repository) gets one entry.
- `{"cursor": C}` directly follows each `changed` line. `C` is the highest
  gseq of every **kept** nudge since the helper started. The script docstring
  says "kept".
- Refusals, `CorruptJournal`, `HelperError`, `AmMissing`, the flush of a
  pending batch at end of stream, exit 0 when am exits 0, SIGINT, SIGTERM and
  a closed stdout are all unchanged.

## Docs

- Script module docstring: the usage line becomes
  `runs-watch.py <root> [<root> ...] [run_id ...] [--since-seq N]`. The text
  states the argv classification, the watched set (argv run ids plus every run
  whose `run_upsert` `payload.repo_dir` is the same directory as any root) and
  that the cursor counts kept nudges. These are contract statements only.
- arch L196, the `runs-watch.py` sentences only. Replace
  `runs-watch.py [--since-seq N]` (N one or more ASCII digits; any other argv
  is `Usage`, exit 2) with the new usage and the Usage rule: at least one root,
  where an argument beginning with `/` is a root, any other non-flag argument
  is a run id, and an empty or other `-`-prefixed argument is `Usage`. Add one
  sentence on the watched set. "A nudge is …" becomes "a nudge is … for a
  watched run", and the cursor is the highest kept `gseq`. Nothing else in
  arch changes. arch L84 is 3.2's.

## Out of scope

- `core/stores/RunStore.qml`, `App.qml`, `tst_run_store.qml` and arch L84:
  passing roots and run ids from the store is card 3.2 (`b54795cd`).
- `runs-snapshot.py`, `runs-snapshot-all.py`, `common/am_runs.py` and
  `viewer-state.py` (sibling cards 2.1, 2.2 and `25dbf867`).
- The parent spec text (L118-121, L182-183) and `README.md`, which belong to
  the milestone docs card. `README.md` L235 still reads true, because the am
  command is unchanged.
- Bringing back the backlog drop (`is_backlog`), `--from-now`, or any new
  output line or key.
- Telling a root that does not exist apart from one that does (no
  `RootMissing` here; an unmatched root just matches nothing).

## Tests

All tests below go in `tests/core/backend/runs/test_runs_watch.py`. That is the
**backend pytest tier**: hermetic subprocess tests that run the real script
against the fake `am` that replays `script.json`. It is the right tier because
the behavior is the script's argv and stdout contract, and that file already
owns that contract. Nothing here touches QML, so no `tst_*.qml` or `tests/ui`
test. `tests/architecture` runs unchanged and must stay green, which proves no
duplicated helper was added.

The lines are copies of the captures in `tests/fixtures/am/`. A line that no
capture holds is labelled `synthetic:`, per the module docstring. New test
constants:

- `CAPTURE_ROOT = nth(1)["line"]["payload"]["repo_dir"]`, the captured
  `run_upsert`'s `repo_dir` (`/home/user/Code/omarchy-project-manager`).
  `test_lines_are_capture_copies` asserts that `nth(1)` is the capture's only
  `run_upsert`, and that `nth(0)` (`lease_acquired`) comes before it.
- `ARGS = [CAPTURE_ROOT, RUN, "r2"]`: the default argv of `run_helper` and
  `start_helper`.

### Existing tests (expectations unchanged; argv only)

The only change is that `run_helper` and `start_helper` default `args` to
`ARGS`. Every test that today calls them with no argv then watches the captured
run (via the root and the run id) and the synthetic `r2`, and its asserted
output stays exactly as it is. This covers `test_argv_default`, which still
asserts `calls == [["watch", "--all-projects", "--follow"]]`, plus hello,
batching, debounce, every-known-event, ignored lines, refusals, signals and
closed stdout. Explicit argv changes:

- `test_argv_since_seq`: argv `[CAPTURE_ROOT, "--since-seq", value]`, with the
  same `calls` expectation.
- `test_usage`: drop the `root` and `root-and-run` cases, because they are now
  valid. Every other current case stays `Usage`, since none has a root. Add
  these with-root cases, all `Usage` with `calls == []`:
  `[ROOT, "--since-seq"]`, `[ROOT, "--since-seq", "-1"]`,
  `[ROOT, "--since-seq", "abc"]`, `[ROOT, "--since-seq", "1", "--since-seq", "2"]`,
  `[ROOT, "--since-seq=5"]`, `[ROOT, "--from-now"]`, `[ROOT, "-x"]`,
  `[ROOT, ""]`, `[RUN, "--since-seq", "5"]` (no root), and `[]` (no
  argument). `ROOT` is `"/some/root"`.
- `test_usage_before_am_lookup`: argv `[RUN]` (no root) with an empty PATH
  still gives `Usage`, exit 2.

### New tests

| test | proves |
|---|---|
| `test_argv_roots_and_run_ids_never_reach_am` | `["/repoA", RUN, "/repoB", "--since-seq", "7", "x1"]` and `["x1", "/repoA"]` (any order) both run; `calls` is exactly `["watch", "--all-projects", "--follow", ...since-seq]`, with no root and no run id. |
| `test_single_root_watches_runs_upserted_there` | argv `[CAPTURE_ROOT]` only, stream `nth(1..19)`: a single `changed` holding `(RUN, gseq(nth(19)))` and cursor `gseq(nth(19))`. Upserting alone is enough to watch a run. |
| `test_event_before_its_run_upsert_is_dropped` | argv `[CAPTURE_ROOT]`, stream `hello, nth(0), pause(0.6), nth(1), pause(0.6)`: the first window prints nothing, and the output is `[HELLO, changed (RUN, gseq(nth(1))), cursor gseq(nth(1))]`. The cursor never saw 358. |
| `test_run_id_arg_is_watched_without_run_upsert` | argv `["/elsewhere", RUN]`, stream `nth(0)` (`lease_acquired`, before any `run_upsert`): RUN is nudged at 358. |
| `test_run_id_arg_of_an_unrelated_repo_is_watched` | argv `["/repoA", "rX"]`; synthetic `run_upsert` of `rX` with `repo_dir` `/repoZ`, then a `phase_upsert` of `rX`: both kept. |
| `test_two_repos_in_one_stream` | argv `["/repoA", "/repoB"]`; synthetic `run_upsert`s: `rA` in `/repoA`, `rB` in `/repoB`, `rC` in `/repoC`; then `phase_upsert` of each, plus the captured `nth(18)` for RUN, whose repo is not a root. The output is exactly one `changed` of `[(rA, top-A), (rB, top-B)]`, the cursor is the higher of those two, and `rC`'s and RUN's gseqs (the highest in the stream) never appear in a `changed` entry or the cursor. |
| `test_root_matches_by_realpath` | parametrized: root `/repoA/` against `repo_dir` `/repoA`; root `/repoA` against `repo_dir` `/repoA/./`; root `/x/../repoA` against `/repoA`; a `tmp_path` symlink `link -> real` as root against `repo_dir` `str(real)`, and the reverse. Each run is nudged. |
| `test_root_mismatch_is_not_watched` | root `/repoA` against `repo_dir` `/repoAB`, `/repo`, `repoA` (relative, resolved against the helper's cwd, which the test sets to `tmp_path`): never nudged. |
| `test_run_upsert_without_usable_repo_dir_is_ignored` | parametrized synthetic `run_upsert`s of `rX` under argv `["/repoA"]`: `payload` a list, a string, `null`, missing; `repo_dir` missing, `5`, `null`, `["/repoA"]`. A later `phase_upsert` of `rX` is not nudged, the output is `[HELLO]`, and there is no Traceback. |
| `test_invalid_run_upsert_does_not_watch` | synthetic `run_upsert` of `rX` in `/repoA` with gseq `0`, then a valid `phase_upsert` of `rX`: nothing printed. |
| `test_watched_run_keeps_nudging_after_upsert` | `run_upsert` of `rA` in `/repoA`, then `story_upsert`, `phase_upsert`, `attempt_upsert` and `control_requested` of `rA` across two windows: two `changed` lines, each carrying rA's highest gseq in its window. |
| `test_watched_run_stays_watched_after_repo_dir_changes` | `rA` upserted in `/repoA`, then upserted again in `/repoZ`, then a `phase_upsert`: all kept. |
| `test_two_roots_naming_one_repo_list_the_run_once` | argv `["/repoA", "/repoA/"]`: `rA`'s run_upsert and phase_upsert give exactly one entry for `rA` (the `changed()` helper already asserts no run appears twice). |
| `test_dropped_lines_never_move_the_cursor` | argv `["/repoA"]`: an unwatched `rZ` with gseq 9000, then watched `rA` at 100 and 101. Output is `changed [(rA, 101)]`, `cursor 101`. |

Timing uses `pause(0.6)` for window boundaries, as the current tests do. Every
synthetic line is built with `other(...)` and labelled `synthetic:` in a
comment. For example: `other("rA", 400, "run_upsert", payload_keys={"repo_dir": "/repoA"})`.
For a payload that is not an object, the test replaces
`step["line"]["payload"]`; to drop the key, it deletes it.

## Hand-off to the planner

Files:

- Modify `core/backend/runs/runs-watch.py`: the docstring, `USAGE`,
  `parse_args`, and a new `same_dir`/`watch` filter between `nudge` and the
  batch in `stream`. `main` passes the roots and run ids into `stream`. The
  spawn argv is unchanged.
- Modify `tests/core/backend/runs/test_runs_watch.py`: the constants,
  `run_helper`/`start_helper` defaults, the adjusted existing tests and the new
  tests above.
- Modify `docs/architecture.md` L196: the `runs-watch.py` sentences only.

Global constraints for the plan, copied from above: stdlib plus
`core/backend/common` only; no second `emit`; am argv is exactly
`watch --all-projects --follow [--since-seq N]`; `USAGE` is
`usage: runs-watch.py <root> [<root> ...] [run_id ...] [--since-seq N]`;
Usage is exit 2 before the `am` lookup; `WINDOW` is 0.25; `bash tests/run.sh`
green; run long tests under `timeout 300`; never `git stash` bare.

Suggested tasks, each TDD:

1. Argv parsing (`USAGE`, `parse_args`, the existing-test argv changes, the
   `test_usage` table, `test_argv_roots_and_run_ids_never_reach_am`).
2. The watched set and the root match in `stream` (every new behavior test).
3. The docstring and the arch L196 sentence.

Review focus, the inputs most likely to bite:

1. A root that matches through a symlink or trailing slash, which is the usual
   shape of `brd` root paths.
2. A `run_upsert` whose payload is not an object or whose `repo_dir` is not a
   string: it must never crash the long-lived helper.
3. An event for a run before its `run_upsert` while only roots are given: it
   is dropped, and the cursor does not move.
4. Argv where a run id looks like a flag, or is empty: `Usage`, never spawned.
5. A long stream where a watched run's gseqs come out of order: the highest
   still wins, as today.

---

# 2.3 `runs-watch.py`: several project roots — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `runs-watch.py` takes one or more project roots and any number of run ids, and prints `changed` nudges only for the runs it watches (argv run ids, plus every run whose `run_upsert` names one of the roots as its `repo_dir`).

**Architecture:** `parse_args` classifies argv left to right into roots, run ids and the `--since-seq` extra; `main` passes the roots' realpaths and the run ids into `stream`, which drops every nudge whose run is not watched (a new `watch` filter between `nudge` and the batch). The spawned am argv, hello handling, debounce and exits are untouched.

**Tech Stack:** Python 3 stdlib only (`os.path.realpath`), pytest (hermetic subprocess tests against a fake `am`).

**Spec:** `docs/superpowers/specs/2-3-runs-watch-py-5b5c2a1a.md` (copied in full above this plan).

## Global Constraints

- `core/backend/**` imports only the stdlib and `core/backend/common`.
- No second `def emit(` (nor `inside`, `write_atomic`, `split_frontmatter`, `frontmatter_of`); keep using `common.json_line.emit`.
- am argv is exactly `watch --all-projects --follow [--since-seq N]`; roots and run ids never reach it.
- `USAGE` is `usage: runs-watch.py <root> [<root> ...] [run_id ...] [--since-seq N]`.
- Usage is exit 2, printed as `{"ok": false, "error": {"type": "Usage", "message": USAGE}}`, before the `am` lookup.
- `WINDOW` is 0.25.
- "Names the same directory" is `os.path.realpath(repo_dir) == os.path.realpath(root)`; each root's realpath is computed once at start.
- Docstrings and comments state the contract only, no narrative.
- `bash tests/run.sh` green, including `tests/architecture`.
- Run long tests under `timeout 300`. Never run a bare `git stash`.
- `python3` here has no pytest: run tests as `uv run --with pytest python3 -m pytest ...` (this is what `tests/run.sh` falls back to).
- Name clash: the test module already has `ROOT` (the repo checkout). The spec's `test_usage` placeholder root `"/some/root"` is therefore named `SOME_ROOT` in the tests; `ROOT` keeps its current meaning.

## Review Focus

1. A root that matches through a symlink or a trailing slash (the usual shape of `brd` root paths): the run is watched. Test: `test_root_matches_by_realpath` (Task 2).
2. A `run_upsert` whose payload is not an object, whose `repo_dir` is not a string, or whose `repo_dir` holds a NUL character (`os.path.realpath` raises `ValueError` on it): never crashes the long-lived helper, never watches. Test: `test_run_upsert_without_usable_repo_dir_is_ignored`, including the `nul-in-repo-dir` case (Task 2).
3. An event for a run before its `run_upsert` while only roots are given: dropped, and the cursor does not move. Tests: `test_event_before_its_run_upsert_is_dropped`, `test_dropped_lines_never_move_the_cursor` (Task 2).
4. An argv run id that looks like a flag, or is empty: `Usage`, am never spawned. Test: `test_usage` cases `root-other-flag`, `root-empty`, `root-equals-form` (Task 1).
5. A watched run's gseqs arriving out of order across windows: the highest still wins and the cursor never lowers. Test: `test_watched_run_out_of_order_gseqs_keep_the_highest` (Task 2).

## File Structure

- Modify `core/backend/runs/runs-watch.py`: module docstring, `USAGE`, `parse_args`, new `same_dir` and `watch`, `stream(lines, roots, watched)`, `main`.
- Modify `tests/core/backend/runs/test_runs_watch.py`: constants `USAGE`, `CAPTURE_ROOT`, `ARGS`, `SOME_ROOT`; `run_helper`/`start_helper` defaults; adjusted argv tests; new tests.
- Modify `docs/architecture.md` L196: the `runs-watch.py` sentences only.

---

### Task 1: Argv: roots, run ids and `--since-seq` in any order

**Files:**
- Modify: `core/backend/runs/runs-watch.py:1-9` (docstring head), `:44` (`USAGE`), `:78-89` (`parse_args`), `:219-226` (`main`)
- Test: `tests/core/backend/runs/test_runs_watch.py`

**Interfaces:**
- Consumes: nothing new.
- Produces: `parse_args(argv) -> (roots: list[str], run_ids: list[str], extra: list[str]) | None`, where `extra` is `[]` or `["--since-seq", N]`. Test constants `CAPTURE_ROOT: str`, `ARGS: list[str]` (`[CAPTURE_ROOT, RUN, "r2"]`), `SOME_ROOT = "/some/root"`; `run_helper(world, args=ARGS, timeout=30, cwd=None, **extra)`; `start_helper(world, args=ARGS)`. Task 2 uses all of these.

- [ ] **Step 1: Write the failing tests (constants, defaults, argv tests)**

In `tests/core/backend/runs/test_runs_watch.py`:

Replace line 23:

```python
USAGE = "usage: runs-watch.py [--since-seq N]"
```

with:

```python
USAGE = "usage: runs-watch.py <root> [<root> ...] [run_id ...] [--since-seq N]"
```

After the `RUN = events()[0]["run_id"]` block (after line 65, before the `KINDS` comment), insert:

```python
# The project root of the captured run: its run_upsert's payload.repo_dir.
CAPTURE_ROOT = events()[1]["payload"]["repo_dir"]
# The default argv: the capture's root, the captured run and the synthetic r2.
ARGS = [CAPTURE_ROOT, RUN, "r2"]
# A root for argv tests; it never has to exist.
SOME_ROOT = "/some/root"
```

(`nth` is defined further down the module, so the constant reads `events()[1]` directly; `test_lines_are_capture_copies` pins that this is `nth(1)`.)

In `test_lines_are_capture_copies`, after the line `assert gseq(ev()) == 376`, append:

```python
    # The capture's only run_upsert is nth(1); nth(0) (lease_acquired) comes before it.
    assert [i for i, e in enumerate(captured) if e["event"] == "run_upsert"] == [1]
    assert captured[0]["event"] == "lease_acquired"
    assert CAPTURE_ROOT == nth(1)["line"]["payload"]["repo_dir"]
    assert CAPTURE_ROOT == "/home/user/Code/omarchy-project-manager"
```

Replace `run_helper` (lines 175-180) with:

```python
def run_helper(world, args=ARGS, timeout=30, cwd=None, **extra):
    """Run the helper until it exits (default argv: ARGS) in `cwd` (default: this
    process's). Every stdout line must be JSON. Returns (exit code, parsed lines,
    stderr)."""
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True,
                       env=env_for(world, **extra), timeout=timeout, cwd=cwd)
    return p.returncode, [json.loads(line) for line in p.stdout.splitlines()], p.stderr
```

Replace `test_argv_since_seq`'s call line:

```python
    code, lines, _ = run_helper(world, ["--since-seq", value])
```

with:

```python
    code, lines, _ = run_helper(world, [CAPTURE_ROOT, "--since-seq", value])
```

Replace the whole `test_usage` (its `@pytest.mark.parametrize` decorator through its body) with:

```python
@pytest.mark.parametrize("args", [
    [RUN], ["--since-seq"], ["--since-seq", "-1"],
    ["--since-seq", "abc"], ["--since-seq", "5.0"], ["--since-seq", ""],
    ["--since-seq", "1", "--since-seq", "2"], ["--since-seq=5"], ["--from-now"],
    ["--since-seq", "5", "extra"], ["--since-seq", "٣"], ["--since-seq", "+5"],
    ["--since-seq", " 5"],
    [SOME_ROOT, "--since-seq"], [SOME_ROOT, "--since-seq", "-1"],
    [SOME_ROOT, "--since-seq", "abc"], [SOME_ROOT, "--since-seq", "1", "--since-seq", "2"],
    [SOME_ROOT, "--since-seq=5"], [SOME_ROOT, "--from-now"], [SOME_ROOT, "-x"],
    [SOME_ROOT, ""], [RUN, "--since-seq", "5"], [],
], ids=["run", "no-value", "negative", "letters", "float", "empty",
        "twice", "equals-form", "other-flag", "trailing-arg", "arabic-indic-digit", "plus-sign",
        "leading-space",
        "root-no-value", "root-negative", "root-letters", "root-twice", "root-equals-form",
        "root-other-flag", "root-dash-x", "root-empty", "run-since-seq-no-root", "no-argument"])
def test_usage(world, args):
    set_script(world, [hello()])
    code, lines, _ = run_helper(world, args)
    assert code == 2
    assert lines == [{"ok": False, "error": {"type": "Usage", "message": USAGE}}]
    assert calls(world) == []  # am never spawned
```

Replace `test_usage_before_am_lookup`'s call line:

```python
    code, lines, _ = run_helper(world, ["/some/root"], PATH=str(empty))
```

with:

```python
    code, lines, _ = run_helper(world, [RUN], PATH=str(empty))  # no root
```

After `test_argv_since_seq`, add:

```python
@pytest.mark.parametrize("args, passed", [
    (["/repoA", RUN, "/repoB", "--since-seq", "7", "x1"], ["--since-seq", "7"]),
    (["x1", "/repoA"], []),
], ids=["mixed-with-since-seq", "run-id-first"])
def test_argv_roots_and_run_ids_never_reach_am(world, args, passed):
    set_script(world, [hello()])
    code, lines, _ = run_helper(world, args)
    assert code == 0
    assert lines == [HELLO]
    assert calls(world) == [["watch", "--all-projects", "--follow", *passed]]
```

Replace `start_helper` (lines 677-680) with:

```python
def start_helper(world, args=ARGS):
    return subprocess.Popen([sys.executable, SCRIPT, *args], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                            env=env_for(world))
```

Every other existing test is left exactly as it is: with the `ARGS` default it watches the captured run and `r2`, so its expected output does not change.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q`
Expected: many FAILs. Every test that runs the helper with `ARGS` gets `{"ok": false, "error": {"type": "Usage", "message": "usage: runs-watch.py [--since-seq N]"}}` and exit 2 instead of its expected output; `test_usage` fails on the message text. `test_lines_are_capture_copies` passes.

- [ ] **Step 3: Implement the argv rules**

In `core/backend/runs/runs-watch.py`, replace docstring lines 4-9:

```
    runs-watch.py [--since-seq N]

Long-lived. Spawns `am watch --all-projects --follow`, plus `--since-seq N` when
given (N: one or more ASCII decimal digits, passed as its integer), as an argv
list, never a shell. Any other argv is a Usage error (exit 2) and am is not
started. Prints one JSON object per line, flushed at once:
```

with:

```
    runs-watch.py <root> [<root> ...] [run_id ...] [--since-seq N]

Arguments, in any order: one beginning with `/` is a root (used as given, never
checked for existence), `--since-seq` takes the next one as N (one or more ASCII
decimal digits, passed as its integer), and any other non-empty one not
beginning with `-` is a run id. No root, a second --since-seq, or any other
argument is a Usage error (exit 2) and am is not looked up or started.
Long-lived. Spawns `am watch --all-projects --follow`, plus `--since-seq N` when
given, as an argv list, never a shell; roots and run ids never reach am. Prints
one JSON object per line, flushed at once:
```

Replace line 44:

```python
USAGE = "usage: runs-watch.py [--since-seq N]"
```

with:

```python
USAGE = "usage: runs-watch.py <root> [<root> ...] [run_id ...] [--since-seq N]"
```

Replace `parse_args` (lines 78-89) with:

```python
def parse_args(argv):
    """(roots, run ids, extra) for the helper's argv, or None for a Usage error.
    Left to right: `--since-seq` takes the next argument as N (one or more ASCII
    decimal digits; extra is ["--since-seq", N's integer as decimal text], else
    []); an argument beginning with `/` is a root; any other non-empty argument
    not beginning with `-` is a run id. No root, a second --since-seq, or an
    empty or other `-` argument is None."""
    roots, run_ids, extra = [], [], None
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--since-seq":
            value = argv[i + 1] if i + 1 < len(argv) else ""
            if extra is not None or not (value and value.isascii() and value.isdigit()):
                return None
            extra = ["--since-seq", value.lstrip("0") or "0"]
            i += 2
            continue
        if arg.startswith("/"):
            roots.append(arg)
        elif not arg or arg.startswith("-"):
            return None
        else:
            run_ids.append(arg)
        i += 1
    if not roots:
        return None
    return roots, run_ids, extra or []
```

In `main`, replace:

```python
    extra = parse_args(argv)
    if extra is None:
        return failure("Usage", USAGE, 2)
```

with:

```python
    parsed = parse_args(argv)
    if parsed is None:
        return failure("Usage", USAGE, 2)
    roots, run_ids, extra = parsed
```

(`roots` and `run_ids` are not used yet; Task 2 passes them into `stream`.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-watch.py tests/core/backend/runs/test_runs_watch.py
git commit -m "feat(runs): runs-watch.py takes project roots and run ids"
```

---

### Task 2: The watched set, the root match, and the arch sentence

**Files:**
- Modify: `core/backend/runs/runs-watch.py` (docstring nudge paragraph, new `same_dir` and `watch` after `nudge`, `stream`, `main`)
- Modify: `docs/architecture.md:196` (the `runs-watch.py` sentences only)
- Test: `tests/core/backend/runs/test_runs_watch.py`

**Interfaces:**
- Consumes: from Task 1, `parse_args(argv) -> (roots, run_ids, extra) | None`; test helpers `CAPTURE_ROOT`, `ARGS`, `run_helper(world, args=ARGS, timeout=30, cwd=None, **extra)`, plus the existing `hello`, `nth`, `gseq`, `other`, `pause`, `set_script`, `changed`, `split`, `HELLO`, `MISSING`, `RUN`.
- Produces: `same_dir(path, roots) -> bool` (`roots`: a set of realpaths); `watch(line, run_id, watched, roots) -> bool` (adds to `watched`); `stream(lines, roots, watched)`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/backend/runs/test_runs_watch.py`, insert a new section directly before the `# --- how am ended ---` comment line:

```python
# --- the watched set: argv run ids and runs upserted under a root ----------------

def upsert(run_id, seq, repo_dir):
    """synthetic: a run_upsert of `run_id` at gseq `seq` whose payload.repo_dir
    is `repo_dir`."""
    return other(run_id, seq, "run_upsert", payload_keys={"repo_dir": repo_dir})


def test_single_root_watches_runs_upserted_there(world):
    steps = [nth(i) for i in range(1, 20)]
    top = gseq(nth(19))
    set_script(world, [hello(), *steps, pause(0.6)])
    code, lines, _ = run_helper(world, [CAPTURE_ROOT])
    assert code == 0
    assert changed(split(lines)) == [([(RUN, top)], top)]


def test_event_before_its_run_upsert_is_dropped(world):
    # nth(0) (lease_acquired, 358) comes before the run_upsert (359).
    set_script(world, [hello(), nth(0), pause(0.6), nth(1), pause(0.6)])
    code, lines, _ = run_helper(world, [CAPTURE_ROOT])
    assert code == 0
    assert lines == [HELLO, {"changed": [{"run": RUN, "seq": gseq(nth(1))}]},
                     {"cursor": gseq(nth(1))}]


def test_run_id_arg_is_watched_without_run_upsert(world):
    set_script(world, [hello(), nth(0)])
    code, lines, _ = run_helper(world, ["/elsewhere", RUN])
    assert code == 0
    assert changed(split(lines)) == [([(RUN, gseq(nth(0)))], gseq(nth(0)))]


def test_run_id_arg_of_an_unrelated_repo_is_watched(world):
    # synthetic: rX lives in /repoZ, which is not a root.
    set_script(world, [hello(), upsert("rX", 400, "/repoZ"), pause(0.6),
                       other("rX", 401), pause(0.6)])
    code, lines, _ = run_helper(world, ["/repoA", "rX"])
    assert code == 0
    assert changed(split(lines)) == [([("rX", 400)], 400), ([("rX", 401)], 401)]


def test_two_repos_in_one_stream(world):
    # synthetic: rA in /repoA and rB in /repoB (both roots), rC in /repoC (not a
    # root); then each run's phase_upsert, and the captured nth(18) of RUN, whose
    # repo is not a root. rC's 500 and RUN's 376 are the highest gseqs.
    set_script(world, [hello(), upsert("rA", 100, "/repoA"), upsert("rB", 101, "/repoB"),
                       upsert("rC", 102, "/repoC"), other("rA", 103), other("rB", 104),
                       other("rC", 500), nth(18), pause(0.6)])
    code, lines, _ = run_helper(world, ["/repoA", "/repoB"])
    assert code == 0
    pairs = changed(split(lines))
    assert pairs == [([("rA", 103), ("rB", 104)], 104)]
    assert gseq(nth(18)) == 376


@pytest.mark.parametrize("case", ["trailing-slash-root", "dot-in-repo-dir", "dotdot-root",
                                  "symlink-root", "symlink-repo-dir"])
def test_root_matches_by_realpath(world, case):
    real = world["tmp"] / "real"
    real.mkdir()
    link = world["tmp"] / "link"
    link.symlink_to(real)
    root, repo_dir = {
        "trailing-slash-root": ("/repoA/", "/repoA"),
        "dot-in-repo-dir": ("/repoA", "/repoA/./"),
        "dotdot-root": ("/x/../repoA", "/repoA"),
        "symlink-root": (str(link), str(real)),
        "symlink-repo-dir": (str(real), str(link)),
    }[case]
    set_script(world, [hello(), upsert("rA", 400, repo_dir), pause(0.6)])
    code, lines, _ = run_helper(world, [root])
    assert code == 0
    assert changed(split(lines)) == [([("rA", 400)], 400)]


@pytest.mark.parametrize("repo_dir", ["/repoAB", "/repo", "repoA"],
                         ids=["longer", "prefix", "relative"])
def test_root_mismatch_is_not_watched(world, repo_dir):
    # A relative repo_dir resolves against the helper's cwd, here tmp.
    set_script(world, [hello(), upsert("rA", 400, repo_dir), other("rA", 401), pause(0.6)])
    code, lines, _ = run_helper(world, ["/repoA"], cwd=str(world["tmp"]))
    assert code == 0
    assert lines == [HELLO]


@pytest.mark.parametrize("key, value", [
    ("payload", ["/repoA"]), ("payload", "/repoA"), ("payload", None), ("payload", MISSING),
    ("repo_dir", MISSING), ("repo_dir", 5), ("repo_dir", None), ("repo_dir", ["/repoA"]),
    ("repo_dir", "/repoA\u0000x"),
], ids=["payload-list", "payload-string", "payload-null", "payload-missing",
        "repo-dir-missing", "repo-dir-number", "repo-dir-null", "repo-dir-list",
        "nul-in-repo-dir"])
def test_run_upsert_without_usable_repo_dir_is_ignored(world, key, value):
    # synthetic: a run_upsert of rX whose payload or payload.repo_dir is edited.
    step = upsert("rX", 400, "/repoA")
    target = step["line"] if key == "payload" else step["line"]["payload"]
    if value is MISSING:
        del target[key]
    else:
        target[key] = value
    set_script(world, [hello(), step, other("rX", 401), pause(0.6)])
    code, lines, err = run_helper(world, ["/repoA"])
    assert code == 0
    assert "Traceback" not in err
    assert lines == [HELLO]


@pytest.mark.parametrize("bad", [0, -1, True, "400"],
                         ids=["zero", "negative", "true", "string"])
def test_invalid_run_upsert_does_not_watch(world, bad):
    # synthetic: a run_upsert of rX in /repoA that is not a nudge, then a valid
    # phase_upsert of rX.
    set_script(world, [hello(), upsert("rX", bad, "/repoA"), other("rX", 401), pause(0.6)])
    code, lines, _ = run_helper(world, ["/repoA"])
    assert code == 0
    assert lines == [HELLO]


def test_watched_run_keeps_nudging_after_upsert(world):
    # synthetic: rA's later lines, across two windows.
    set_script(world, [hello(), upsert("rA", 400, "/repoA"), other("rA", 401, "story_upsert"),
                       other("rA", 402), pause(0.6), other("rA", 403, "attempt_upsert"),
                       other("rA", 404, "control_requested"), pause(0.6)])
    code, lines, _ = run_helper(world, ["/repoA"])
    assert code == 0
    assert changed(split(lines)) == [([("rA", 402)], 402), ([("rA", 404)], 404)]


def test_watched_run_out_of_order_gseqs_keep_the_highest(world):
    # synthetic: rA's gseqs arrive out of order; the second window holds a
    # lower gseq than the cursor.
    set_script(world, [hello(), upsert("rA", 400, "/repoA"), other("rA", 900),
                       other("rA", 500), pause(0.6), other("rA", 450), pause(0.6)])
    code, lines, _ = run_helper(world, ["/repoA"])
    assert code == 0
    assert changed(split(lines)) == [([("rA", 900)], 900), ([("rA", 450)], 900)]


def test_watched_run_stays_watched_after_repo_dir_changes(world):
    # synthetic: rA is upserted again under /repoZ, which is not a root.
    set_script(world, [hello(), upsert("rA", 400, "/repoA"), pause(0.6),
                       upsert("rA", 401, "/repoZ"), pause(0.6), other("rA", 402), pause(0.6)])
    code, lines, _ = run_helper(world, ["/repoA"])
    assert code == 0
    assert changed(split(lines)) == [([("rA", 400)], 400), ([("rA", 401)], 401),
                                     ([("rA", 402)], 402)]


def test_two_roots_naming_one_repo_list_the_run_once(world):
    # synthetic: rA in /repoA, which both roots name. changed() asserts no run
    # appears twice in a line.
    set_script(world, [hello(), upsert("rA", 400, "/repoA"), other("rA", 401), pause(0.6)])
    code, lines, _ = run_helper(world, ["/repoA", "/repoA/"])
    assert code == 0
    assert changed(split(lines)) == [([("rA", 401)], 401)]


def test_dropped_lines_never_move_the_cursor(world):
    # synthetic: rZ is upserted under /repoZ (not a root) at 9000, then nudges
    # again; rA is watched at 100 and 101.
    set_script(world, [hello(), upsert("rZ", 9000, "/repoZ"), other("rZ", 9001),
                       upsert("rA", 100, "/repoA"), other("rA", 101), pause(0.6)])
    code, lines, _ = run_helper(world, ["/repoA"])
    assert code == 0
    assert changed(split(lines)) == [([("rA", 101)], 101)]
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q -k "watched or upsert or root or repos or dropped or run_id_arg"`
Expected: FAIL for `test_event_before_its_run_upsert_is_dropped`, `test_two_repos_in_one_stream`, `test_root_mismatch_is_not_watched`, `test_run_upsert_without_usable_repo_dir_is_ignored`, `test_invalid_run_upsert_does_not_watch` and `test_dropped_lines_never_move_the_cursor`: today every nudge is kept, so each prints a `changed` entry for a run that is not watched. The other new tests (`test_single_root_watches_runs_upserted_there`, `test_run_id_arg_is_watched_without_run_upsert`, `test_run_id_arg_of_an_unrelated_repo_is_watched`, `test_root_matches_by_realpath`, `test_watched_run_*`, `test_two_roots_naming_one_repo_list_the_run_once`) already PASS for the same reason; they pin what the filter must keep.

- [ ] **Step 3: Implement the watched set**

In `core/backend/runs/runs-watch.py`, in the module docstring replace:

```
      at most once per 250 ms, never empty, one entry per run holding the
      highest gseq of that run's nudges in the window; directly followed by
  {"cursor": C}
      the highest gseq of every nudge since the helper started.
```

with:

```
      at most once per 250 ms, never empty, one entry per run holding the
      highest gseq of that run's kept nudges in the window; directly followed by
  {"cursor": C}
      the highest gseq of every kept nudge since the helper started.
```

and replace:

```
A nudge is a JSON object whose event is one of EVENTS, whose run_id is a
non-empty string and whose gseq is an integer of 1 or more. Every other line is
ignored; event contents are never forwarded. am exiting 0, SIGINT, SIGTERM or a
```

with:

```
A nudge is a JSON object whose event is one of EVENTS, whose run_id is a
non-empty string and whose gseq is an integer of 1 or more. Every other line is
ignored; event contents are never forwarded. A nudge is kept when its run is
watched: the argv run ids, plus every run whose run_upsert nudge has a
payload.repo_dir naming the same directory (realpath) as any root, from that
run_upsert on, for good. Every other nudge is dropped: it prints nothing and
moves neither the batch nor the cursor. am exiting 0, SIGINT, SIGTERM or a
```

After `nudge` (after its `return run_id, gseq` line), add:

```python
def same_dir(path, roots):
    """True when `path` names the same directory as one of `roots` (realpaths).
    A path realpath cannot take (an embedded NUL) names none."""
    try:
        return os.path.realpath(path) in roots
    except (ValueError, OSError):
        return False


def watch(line, run_id, watched, roots):
    """True when the nudge `line` of `run_id` is kept: the run is in `watched`,
    or the line is a run_upsert whose payload.repo_dir is a string naming the
    same directory as one of `roots` (realpaths), which adds the run to
    `watched` for good."""
    if run_id in watched:
        return True
    payload = line.get("payload")
    if not (line.get("event") == "run_upsert" and isinstance(payload, dict)):
        return False
    repo_dir = payload.get("repo_dir")
    if not (isinstance(repo_dir, str) and same_dir(repo_dir, roots)):
        return False
    watched.add(run_id)
    return True
```

Replace the head of `stream`:

```python
def stream(lines):
    """Turn am's stream into the hello line and debounced changed + cursor lines
    until it ends. Every hello line (event "watch") is checked; the first is
    printed at once without touching the batch; later ones print nothing.
```

with:

```python
def stream(lines, roots, watched):
    """Turn am's stream into the hello line and debounced changed + cursor lines
    until it ends. Every hello line (event "watch") is checked; the first is
    printed at once without touching the batch; later ones print nothing. Only
    nudges `watch` keeps (`roots`: realpaths; `watched`: run ids, grown in
    place) reach the batch and the cursor.
```

In `stream`'s loop, replace:

```python
        hit = nudge(line)
        if hit is None:
            continue
        run_id, gseq = hit
```

with:

```python
        hit = nudge(line)
        if hit is None:
            continue
        run_id, gseq = hit
        if not watch(line, run_id, watched, roots):
            continue
```

In `main`, replace:

```python
            refusal = stream(lines)
```

with:

```python
            refusal = stream(lines, {os.path.realpath(root) for root in roots}, set(run_ids))
```

- [ ] **Step 4: Run the whole helper test file to verify it passes**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q`
Expected: all PASS (the Task 1 tests too: `ARGS` watches RUN and r2, so their output is unchanged).

- [ ] **Step 5: Update the arch sentences**

In `docs/architecture.md` line 196, make exactly these three replacements (nothing else on the line or in the file changes; L84 is card 3.2's).

Replace:

```
`runs-watch.py [--since-seq N]` (N one or more ASCII digits; any other argv is `Usage`, exit 2) is long-lived:
```

with:

```
`runs-watch.py <root> [<root> ...] [run_id ...] [--since-seq N]` (at least one root; an argument beginning with `/` is a root, any other non-flag argument is a run id, N is one or more ASCII digits, and no root, a second `--since-seq`, or an empty or other `-`-prefixed argument is `Usage`, exit 2; roots and run ids never reach am) is long-lived:
```

Replace:

```
A nudge is a line whose `event` is one of its `EVENTS`
```

with:

```
It watches the argv run ids plus every run whose `run_upsert` `payload.repo_dir` names the same directory (realpath) as any root, from that `run_upsert` on. A nudge is a line for a watched run whose `event` is one of its `EVENTS`
```

Replace:

```
followed directly by `{"cursor": C}` (the highest `gseq` since the helper started).
```

with:

```
followed directly by `{"cursor": C}` (the highest kept `gseq` since the helper started).
```

Check each old string occurs exactly once before editing: `grep -c 'runs-watch.py \[--since-seq N\]' docs/architecture.md` prints `1`; `grep -c 'A nudge is a line whose' docs/architecture.md` prints `1`; `grep -c '(the highest `gseq` since the helper started)' docs/architecture.md` prints `1`.

- [ ] **Step 6: Run the full suite**

Run: `timeout 600 bash tests/run.sh`
Expected: pytest all pass (including `tests/architecture`), every QML test file reports `Totals` with 0 failed, exit 0.

- [ ] **Step 7: Commit**

```bash
git add core/backend/runs/runs-watch.py tests/core/backend/runs/test_runs_watch.py docs/architecture.md
git commit -m "feat(runs): runs-watch.py nudges only watched runs"
```
<!-- task-pipeline: validated -->
