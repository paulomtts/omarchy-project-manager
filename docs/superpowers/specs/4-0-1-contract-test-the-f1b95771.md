# 4.0.1 Contract test: the installed `am` has `as_of_seq` and `head` — design

Card: `f1b95771` (subtask of story `0cf1ca04`, 4.0 Contract). Parent design:
`docs/superpowers/specs/2026-10-06-am-snapshots-cursors-design.md` in the main checkout (untracked
there; cited below as **M4**). It changes one file: `tests/contract/test_am_fixtures.py`. No plugin
code, no fixture, no QML changes.

## Purpose

M4's precondition gate (M4 §"Order and sizing", line 254: "contract test that fails naming the
missing capability when `am` lacks `as_of_seq` / `head` (skips only when `am` is absent)"; M4
§"Testing", lines 214-215). Every later M4 subtask reads `as_of_seq` from snapshots and `head` from
the watch hello; this test makes an old `am` on the PATH fail the suite loudly instead of letting
those subtasks build against a capability that is not there.

## Inherited constraints

- `am` is called only as argv lists; nothing reads `am.db`, journals or the data-dir layout
  (M4 §"Non-goals", lines 58-59).
- The live check runs against a scratch data dir, never the user's real runs (M4 §"Dev safety",
  lines 187-189; card).
- A hello without `head` and a `runs` without `as_of_seq` mean "the plugin needs the newer am"
  (M4 §"Errors", line 198; M4 §"Design" hello rule, lines 92-94).
- The hello stays at schema 2 with additive `head`, `gseq`, `cursor_reset`, `store_id`
  (M4 §"Decisions", lines 273-275): the check keys on the presence of `head`, not on the schema
  number (M4 open question 5, lines 293-294).
- Test inputs of `am` output come from `tests/fixtures/am/`, never hand-written; a synthetic edge
  case is labelled `synthetic:` (card).
- Docstrings and comments state the contract only, no narrative (card).
- `bash tests/run.sh` green, including `tests/architecture` (card).

## Observed behavior of the installed `am` (2026-10-08)

Measured by the spec author with `HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` pointing into a fresh
temp dir (`~/.local/bin/am`):

1. `am runs --repo-dir <empty dir>` exits 0 and prints
   `{"data":{"as_of_seq":0,"runs":[],"store_id":null},"ok":true}` (also pinned in
   `tests/contract/test_am_shapes.py:77-82`).
2. `am watch --all --follow` prints, within ~0.2 s, one hello line
   `{"am":"0.1.0","cursor_reset":false,"event":"watch","head":0,"runs_dir":"<scratch>/data/agent-manager/runs","schema":2,"store_id":null}`
   and then blocks waiting for events until terminated (exit -15 on SIGTERM).
3. Neither call creates the scratch data dir.

So a fresh scratch store needs no seeded run for either capability check.

## Required behavior

### The live check

A module-level function `live_check(env, repo_dir)` performs the whole live check; the live test
calls it with a scratch environment. `env` is the full environment passed to every `am`
subprocess; `repo_dir` is the directory passed as `--repo-dir`.

In order:

1. **`am runs` has `as_of_seq`.** Runs `["am", "runs", "--repo-dir", repo_dir]` with `env`,
   timeout `AM_TIMEOUT`.
   - Non-zero exit → fails: `live am runs exited <code>: <stdout><stderr>`.
   - stdout not JSON, or no `data` object → fails naming `live am runs`.
   - `data` has no `as_of_seq` key → fails with exactly
     `live am runs data: no as_of_seq: the plugin needs the newer am`.
   - `as_of_seq` present but not a non-negative `int` (a `bool` is not an int here) → fails
     `live am runs data.as_of_seq: <repr>`.
2. **Rows and status, when there are rows.** For each row in `data.runs`: the existing
   `check_runs_rows("live am runs", rows, LIVE_EXTRA)` and `project` key-set checks; then
   `am status <newest id> --repo-dir repo_dir` with `env` and `check_status_data(...)`, exactly as
   today. A store with no rows checks nothing here and **does not skip**. (A fresh scratch store
   has no rows; seeded-run key sets are pinned by `test_am_shapes.py`.)
3. **The `am watch` hello has `head`.** Starts `["am", "watch", "--all", "--follow"]` with `env`
   (stdout piped, text mode), reads exactly one line bounded by `FOLLOW_TIMEOUT` (a hung or
   silent `am` fails with what it printed, never hangs the suite), then terminates the process
   (kill after a bounded wait) in a `finally`.
   - No line within the timeout → fails (the `read_lines` message:
     `am printed 0 of 1 lines within <t>s: []`).
   - First line not a JSON object → fails naming `live am watch hello`.
   - The object has `"event" != "watch"` → fails `live am watch hello: event <repr>`.
   - No `head` key → fails with exactly
     `live am watch hello: no head: the plugin needs the newer am`.
   - `head` present but not a non-negative `int` → fails `live am watch hello.head: <repr>`.

Failures use `pytest.fail` (or `assert` with the same message); messages follow the module's
`<source> <where>: ...` form. Every failure message for a missing capability contains the
capability's key name (`as_of_seq` or `head`) and `the plugin needs the newer am`.

### The live test

`test_installed_am_prints_the_fixture_key_sets(tmp_path)` (name kept):

- Skips with `am is not installed here` when `shutil.which("am") is None` — the **only** skip.
- Otherwise builds the scratch environment: a copy of `os.environ` with `HOME`,
  `XDG_DATA_HOME`, `XDG_STATE_HOME` set to `tmp_path/"home"`, `tmp_path/"data"`,
  `tmp_path/"state"` (the `am` fixture of `test_am_shapes.py:30-36`), `tmp_path/"home"` and
  `tmp_path/"repo"` created; then calls `live_check(env, tmp_path/"repo")`.
- It no longer resolves the main checkout and never passes the user's real environment's data
  dir: `git_main_checkout()` and `test_live_check_reads_the_main_checkout_not_a_worktree` are
  removed (git is no longer needed, so git's absence no longer skips).
- The skips "git could not name the main checkout", "am runs exited N" and "am has no runs" are
  gone: a non-zero `am runs` fails.

`am_json` takes the environment: `am_json(env, *args)` passes `env=env` to `subprocess.run`.

### Module docstring

The "Live check" paragraph (lines 9-15) is rewritten to state the new contract: the check runs
`am` under a scratch `HOME`/`XDG_DATA_HOME`/`XDG_STATE_HOME`, never the user's data dir; `am runs`
data must carry `as_of_seq` and the `am watch --all --follow` hello must carry `head`, else it
fails naming the missing key and "the plugin needs the newer am"; rows present are checked against
the capture key sets with the `LIVE_EXTRA` allowances (unchanged list); skipped only when `am` is
absent. Contract wording only.

## Tests (all pytest, `tests/contract/test_am_fixtures.py`)

The stub tests use a **stub `am`**: an executable `/bin/sh` script written into `tmp_path/"bin"`
(mode `0o755`), put first on the env's `PATH` (keeping the rest of `PATH` so `/bin/sh` and `sleep`
resolve). `am runs` makes it `cat` a JSON file; `am watch` makes it `cat` a hello file and then
`exec sleep 30` (the PID being terminated is then the sleeper itself, mirroring a real `am` that
blocks). On every call the stub writes `$XDG_DATA_HOME` to `tmp_path/"seen-xdg"` and appends its first argument (`runs` or `watch`) as a line to `tmp_path/"calls"`. Its JSON files
are derived from the fixtures with `json.dump`, never hand-written:

- runs output = `load("runs.json")` (its `data` has only `runs`: the missing case removes nothing; `pop("as_of_seq", None)` is harmless) with `data["as_of_seq"]` set to `0` for the present case
  (`synthetic: as_of_seq added`), and `data["runs"] = []` so step 2 has nothing to check;
- hello output = `load("watch-hello.json")["schema_2"]` (which has no `head`: the missing case removes nothing) with `head` set to `0` for the present case
  (`synthetic: head added`), `_`-prefixed keys dropped.

These are unit tests of the live check's failure paths; they are in the pytest contract tier
because the live check lives there and they run `live_check` as a subprocess consumer exactly as
the real check does. None needs the real `am`; none is skipped when `am` is absent.

| # | test | tier / why | proves |
|---|---|---|---|
| 1 | `test_live_check_fails_naming_as_of_seq_when_am_runs_lacks_it` | pytest contract: drives `live_check` against a stub `am` process | stub runs without `as_of_seq` → `pytest.fail.Exception` whose message is `live am runs data: no as_of_seq: the plugin needs the newer am`; `calls` holds no `watch` line (order) |
| 2 | `test_live_check_fails_naming_head_when_the_watch_hello_lacks_it` | same | stub runs with `as_of_seq` (synthetic), hello without `head` → fails with `live am watch hello: no head: the plugin needs the newer am`; the stub's sleeper is terminated (the test returns well under the stub's 30 s sleep) |
| 3 | `test_live_check_passes_when_am_has_as_of_seq_and_head` | same | stub with both (synthetic) → `live_check` returns without failing; guards against a check that fails everything |
| 4 | `test_live_check_runs_am_under_the_scratch_data_dir` | same | after the live test's env builder + `live_check` on the stub, `seen-xdg` holds `tmp_path/"data"` and not the caller's `XDG_DATA_HOME` / `~/.local/share` |
| 5 | `test_live_check_fails_when_am_runs_exits_non_zero` | same | stub `runs` exits 3 → fails with `live am runs exited 3` (not a skip) |
| 6 | `test_live_check_skips_when_am_is_not_on_path` (existing, kept) | pytest contract | `PATH=tmp_path` (no `am`) → the live test raises `pytest.skip.Exception` matching `am is not installed here`; adapt the call to pass `tmp_path` |
| 7 | `test_installed_am_prints_the_fixture_key_sets` (existing, rewritten) | pytest contract, live | the real installed `am` on a scratch store passes `live_check`; skips only when `am` is absent |

To let test 4 reuse the env builder, the scratch env is built by a helper
`scratch_env(tmp_path, path=None)` (returns `(env, repo_dir)`; `path` overrides `PATH`), used by
the live test and the stub tests.

The bounded one-line read reuses `read_lines` and `FOLLOW_TIMEOUT` from `test_am_shapes.py`
(`from test_am_shapes import FOLLOW_TIMEOUT, read_lines`; pytest's default prepend import mode puts
`tests/contract` on `sys.path`), so the deadline rule has one definition.

## Errors and edge cases the check must not mishandle

- `am` hangs before printing the hello → bounded failure, process terminated, no hang.
- `am watch` exits immediately (old `am` refusing `--all`) → fails with the lines it printed
  (none), not a JSON error trace.
- `as_of_seq: null` or `head: null` → fails on the type rule, naming the key path.
- Extra unknown keys in the runs data or hello → accepted (unknown keys are ignored, M4 line 80).
- A hello at schema 1 that has `head` → accepted (presence of `head` is the rule).

## Out of scope

- Regenerating or re-pinning `tests/fixtures/am/*.json`, `HELLO_KEYS`, `EVENT_KEYS`, adding
  `events.json` (sibling 4.0.2). The committed fixture keys are not changed here; the QML tier
  (`tests/helpers/amFixtures.js`, `tst_am_fixtures.qml`) reads them unchanged.
- `normalizeRun` and `tst_runs.qml` (4.0.3).
- `runs-watch.py` `SchemaMismatch` on a hello without `head` (4.1.1), `runs-snapshot.py` (4.1.2),
  `RunStore` (4.1.3, 4.1.4).
- `tests/contract/test_am_shapes.py` (unchanged; only imported from).
- Story 4.2 (spec retargets docs PR) and the 4.3 behaviour cards (Global Runs, timeline, alert
  cursor, start-run discovery).
- Any check of `store_id`, `cursor_reset` or `gseq` (not this card's capabilities).

## Verification

`bash tests/run.sh` green (pytest `tests -q`, including `tests/architecture`, then every
`tst_*.qml`). The live test (7) runs, not skips, on this machine because `am` is installed.
