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
