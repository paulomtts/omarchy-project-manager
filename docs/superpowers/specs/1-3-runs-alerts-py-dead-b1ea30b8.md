# 1.3 runs-alerts.py: dead runs by a lease poll (card b1ea30b8)

Narrowed from `docs/superpowers/specs/2026-10-05-alerts-panel-closed-design.md` (below "the
parent"): fact 7, what `dead` is (lines 71-72); Behaviour, "What alerts" (lines 88-91) and
"Dead detection" (lines 120-127); Architecture, the `runs-alerts.py` bullet (lines 134-145);
Resource use when idle (lines 166-171); Testing, the `test_runs_alerts.py` bullet (lines
192-199). Parent story 11ef73c2. Blocked by a65dfeb3 (1.2, landed: the helper, its escalation
alerts and its tests; spec `docs/superpowers/specs/1-2-runs-alerts-py-a65dfeb3.md`, below
"the 1.2 spec").

**The card overrides the parent where they differ.** The parent seeds and polls with
`am runs --all-projects` and puts a `gseq` in the alert (lines 122-124, 142). The card reads
`am runs --repo-dir R` once per registered root, and the alert has no `gseq`, as in 1.2. The
1.2 contract (no argument, `am watch --all --follow --from-now`, hello schema 1 or 2,
escalation alerts, every ending in its table) is unchanged except where this spec says so.

## Starting point

- `core/backend/runs/runs-alerts.py` (from 1.2): `read_registry()` maps
  `realpath(root_path)` → (`root_path` as brd printed it, `name`); `Watcher.see(run_id,
  payload)` keeps each run's last status and repo_dir and prints escalation alerts;
  `stream()` reads am's lines from a queue with a 1 s timeout (`IDLE_POLL`), so the main loop
  wakes at least once a second with nothing pending.
- `core/backend/common/am_runs.py`: `call_am(am, args, timeout)` (envelope's `data`, raises
  `AmFailure` on `ok:false` or non-envelope output; lets `subprocess.TimeoutExpired` and
  `OSError` through), `run_list(data)` (a list of objects with a non-empty string `id` and a
  string `status`, else `AmFailure`), `AM_TIMEOUT = 60`, `TERMINAL`.
- `tests/fixtures/am/runs.json`: a captured `am runs --repo-dir … --limit 2`; row 0 is
  `started` with `lease.live` true, row 1 `done` with `lease: null`.
- `tests/core/backend/runs/test_runs_alerts.py` (from 1.2): subprocess-only scaffold. Its
  fake `am` replays one `script.json` for every invocation and writes its pid to `pid` on
  every invocation; the `world` fixture registers one root, `repo`.
  `tests/core/backend/milestones/test_run_setup_milestone.py:502-507` loads a hyphenated
  helper in-process with `importlib.util.spec_from_file_location`; that is the precedent for
  an in-process test.

## Constraints

- Layering (`docs/architecture.md`, enforced by `tests/architecture/test_layers.py`): no
  second definition of `emit`, `inside`, `write_atomic`, `split_frontmatter`,
  `frontmatter_of`. Reuse `common.am_runs` (`call_am`, `run_list`, `AM_TIMEOUT`) rather than
  a second envelope parser. `tests/architecture` must pass unchanged.
- Parent line 145: only documented `am` and `brd` commands, as argv lists, never a shell;
  am's database and on-disk layout are never read.
- Card: docstrings and comments state the contract only, no narrative. TDD: tests first.
  The module docstring is updated to state the seed, the poll and the `dead` line; its
  remaining 1.2 sentences stay true and stay.
- Verification: `bash tests/run.sh` green. Quick loop:
  `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_alerts.py tests/architecture -q`.
- Never `pkill`/`killall`/pattern kills in tests; signal only recorded PIDs; every wait
  bounded.

## Behaviour

### Terms

- **The lease is live** when the run row's `lease` is an object whose `live` is the JSON
  `true`. Anything else — `lease` null, missing, not an object, `live` false, missing or not
  a bool — is not live (parent line 72; `core/domain/runs.js:153-155` reads it the same way).
- **A read of root R** is one `am runs --repo-dir R`: argv exactly
  `[<am>, "runs", "--repo-dir", R]` with R the `root_path` as brd printed it, stdin
  `/dev/null`, bounded by 60 s (`AM_TIMEOUT`). It **succeeds** when am prints an `ok:true`
  envelope whose `data.runs` passes `run_list`. Anything else — an `ok:false` envelope (any
  exit), output that is not an envelope, a malformed run list, a timeout, am failing to
  start — is a **failed read**: it prints nothing, does not end the helper, and changes
  nothing that read would have changed.
- **Tracked runs**: the helper keeps a set of runs, each with the registry key (realpath)
  and the (`root_path`, `name`) of the root it belongs to, and an **armed** flag. Only runs
  last seen with status `started` are tracked. The root's (`root_path`, `name`) is captured
  when the run is first tracked and is what the run's `dead` alert prints.

### The seed (once, at start)

Start order becomes: `am` looked up (AmMissing as before), the registry read, **then one
read of each registered root, in the registry's order (brd's order, first realpath
wins)**, then `am watch --all --follow --from-now` spawned. An empty registry (or a failed
registry read) means no seed reads.

For each root whose read succeeds, every row whose `status` is `started` is tracked under
that root: armed when its lease is live, not armed when it is not. A failed read only skips
that root's seed (card); the other roots are seeded normally. **The seed never prints
anything**, not even for a `started` run whose lease is already not live: such a run is
tracked unarmed, so it does not alert at a later poll either until it has been seen live
(parent line 126: a run already dead when the helper starts is not caught up).

### The poll

- **When:** while at least one run is tracked, a poll is due 60 s after the latest of: the
  end of the seed, the end of the previous poll, the moment the tracked set last went from
  empty to non-empty. The main loop checks for a due poll after every am line and on every
  1 s idle wake, so a poll starts at most about 1 s after it is due. While no run is
  tracked, no poll is ever due and nothing is read (card; parent lines 125, 168-170).
- **What:** one read of each root that holds at least one tracked run, in registry order
  (roots with no tracked run are not read). Roots are read one after another; am's watch
  lines arriving meanwhile are queued, never dropped, and handled after the poll.
- **Per successful read of root R**, for each run tracked under R:
  - its row has status `started` and a live lease → armed (re-armed if it was not);
  - its row has status `started` and a lease that is not live → if armed, print the `dead`
    alert and disarm; if not armed, nothing;
  - its row has any other status (`done`, `escalated`, `stopped`, `cancelled`, `canceled`,
    or anything else) → dropped from the tracked set;
  - no row has its id → dropped.

  A `started` row of R whose run is not tracked is tracked under R exactly as the seed
  does (armed when live, else unarmed) and never alerts on that read.
- **Per failed read of root R:** the runs tracked under R are unchanged; R is read again at
  the next poll.

### Runs learned from the watch

A `run_upsert` the helper handles (after the first hello, as in 1.2) also updates the
tracked set, after the 1.2 escalation handling of the same line:

- `payload.status` is `started`, the run is not tracked, and the run's last repo_dir (as
  1.2 keeps it) has a realpath in the current registry → tracked under that root, armed (a
  run that is writing events has a process). The registry is **not** read again for this
  (1.2's re-read stays reserved to escalation transitions).
- `payload.status` is `started` and the run is already tracked → unchanged (only a poll
  arms or disarms).
- `payload.status` is any other string → the run is dropped if tracked.
- `payload.status` not a string → unchanged.

### The dead alert

One line, flushed at once, key order as shown, the same shape as the escalation alert
(1.2 spec, "Per-run state and the alert"; parent line 142 minus `gseq`):

```json
{"alert": {"run_id": "<run id>", "root": "<root_path as brd printed it>", "project": "<name>", "state": "dead"}}
```

So a run that dies alerts `dead` once; it alerts again only after a poll has seen it
started with a live lease (resumed) and a later poll sees it not live (parent lines 90-91:
"one notification per run and state; a run that is resumed … alerts again"). Escalation
alerts are independent of this: 1.2's rules, lines and tests are unchanged.

### Ending

The 1.2 ending table is unchanged. Additionally: a failed seed or poll read never ends the
helper; on SIGINT, SIGTERM or a closed stdout during a seed or poll read, the `am runs`
child is not left running (it is killed and reaped) and the helper exits 0 with no line.

### Testability: the injected clock

The card requires an injected clock. The poll's timing is driven by a clock callable
(default `time.monotonic`) passed to the unit that owns the tracked set; that unit has no
other time source and never sleeps. Tests load `runs-alerts.py` in-process with
`importlib.util.spec_from_file_location` (precedent above), construct that unit with a fake
clock and the fake `am`'s path, and call it directly; am is still a real subprocess (the
fake `am` on a temp PATH). The planner names the unit and its methods; the unit must expose:
seeding from a registry, handling one run_upsert's (run id, status, registry key) and a
"poll if due" call.

## Tests

All in `tests/core/backend/runs/test_runs_alerts.py`. Two tiers:

- **in-process** (module loaded by importlib, fake clock, fake `am` on PATH via
  `monkeypatch.setenv`, stdout via `capsys`): the 60 s interval is only testable with an
  injected clock, and a subprocess cannot take one.
- **subprocess** (the 1.2 scaffold): argv order at start, that the helper stays up and
  watches after a failed seed, and process lifecycle, which only the real entry point shows.

Fake `am` changes (scaffold): for argv `runs …` it answers from `FAKE_AM_DIR/runs.json`,
keyed by the `--repo-dir` value, the Nth call for that root getting the Nth answer (the last
repeats), each answer `{stdout, exit}` plus an optional `sleep` (seconds before it answers, for test 19); a root with no entry gets a capture-shaped
`ok:true` envelope with an empty `runs` list. Answers are built from
`tests/fixtures/am/runs.json` copies (row 0 for `started`/live, edited copies labelled
`synthetic:`). Every `runs` invocation also writes its pid to `runs.pid` (test 19). Only `watch` invocations write `pid`, so `wait_for_am` still returns the
watch's pid. Every invocation still appends its argv to `calls.log`.

| # | test | tier | proves |
|---|---|---|---|
| 1 | `test_seed_argv_order` — two registered roots: `calls.log` is `runs --repo-dir r1`, `runs --repo-dir r2`, then `watch --all --follow --from-now`; root as brd printed it (a symlink stays the link) | subprocess | seed is once per root, before the watch, argv list |
| 2 | update `test_argv`: one root → `[["runs","--repo-dir",repo],["watch",…]]`; empty registry → watch only | subprocess | 1.2 argv test under the seed |
| 3 | `test_seed_never_alerts` — seed row started with lease null; helper runs to am exit 0 → no line | subprocess | seeded runs never alert by themselves at start |
| 4 | `test_failed_seed_of_one_root` — r1's read fails, parametrized: `ok:false` envelope exit 1, not JSON, `data` without `runs`; r2 started → no line; watch still spawned; a later escalation of r2 still alerts | subprocess | a failed read only skips that root's seed |
| 5 | `test_dead_once` — seed live; clock +60 poll not live → exactly one `dead` line (shape and key order); +120 still not live → none | in-process | dead once |
| 6 | `test_not_live_shapes` — parametrized lease null, missing, `{}`, `live:false`, `live:"true"`, lease a string → dead | in-process | the live rule |
| 7 | `test_re_armed_after_resume` — live → not live (alert) → live → not live (second alert) | in-process | once until seen started-and-live again |
| 8 | `test_seeded_dead_waits_for_live` — seed not live; polls at +60, +120 not live → nothing; live then not live → one alert | in-process | seeded dead never alerts until seen live |
| 9 | `test_poll_interval` — seed live; "poll if due" at +59.9 → no `runs` call; at +60 → one; next due 60 s after that poll's end | in-process | every 60 s |
| 10 | `test_no_poll_when_idle` — seed with no started row (row 1 `done` only); calls at +60, +600, +3600 → no `runs` call after the seed | in-process | with no started run, no poll |
| 11 | `test_no_poll_when_idle_subprocess` — empty seed, helper alive ~2 s then am exits 0 → `calls.log` holds only seed and watch | subprocess | no poll at the entry point |
| 12 | `test_polls_only_roots_with_started` — r1 started, r2 none → poll reads r1 only | in-process | roots with one |
| 13 | `test_terminal_dropped` — parametrized poll status `done`, `stopped`, `escalated`, `cancelled`, `canceled` → no line, run dropped, and (as the only run) no poll at +120, +600 | in-process | terminal runs dropped, both cancel spellings |
| 14 | `test_absent_row_dropped` — tracked run missing from its root's poll → dropped, no further poll | in-process | absent means dropped |
| 15 | `test_failed_poll_keeps_runs` — poll read fails (`ok:false`; not JSON) → no line, run still tracked, read again at the next due time, then dead alerts | in-process | a failed poll changes nothing |
| 16 | `test_new_started_row_in_poll` — poll of r1 lists an untracked started run not live → no line on that read; live then not live later → alert | in-process | runs learned from a read never alert on it |
| 17 | `test_upsert_started_tracks` — empty seed; a started upsert of a registered repo_dir → tracked armed, poll due 60 s later, not live → alert; an unregistered repo_dir → not tracked, no poll, no `brd` call | in-process | a run started while the helper runs is watched |
| 18 | `test_upsert_other_status_drops` — tracked run, upsert `escalated` (and `cancelled`) → dropped, no further poll | in-process | the watch also drops |
| 19 | `test_signal_during_seed_leaves_no_am` — fake `am runs` answer sleeps; SIGTERM the helper mid-seed → exit 0, no output, the `runs` child gone (pid recorded by the fake to a separate file) | subprocess | no `am runs` left behind |
| 20 | all 1.2 tests pass unchanged except `test_argv` (row 2) | subprocess | escalation contract untouched |

## Docs

`docs/architecture.md`, the `core/backend/runs/` paragraph (line 197): one sentence for
`runs-alerts.py`: long-lived, no argument, follows `am watch --all --follow --from-now`,
reads `am runs --repo-dir R` once per registered root at start and every 60 s for the roots
holding a started run (none while no run is started), and prints
`{"alert": {run_id, root, project, state}}` with `state` `escalated` or `dead`. Change
"All three use" to "They all use" so the sentence covers it.

## Out of scope

- Everything the parent adds beyond the card: `am runs --all-projects`, `gseq` in the alert,
  the cursor argument and `{"cursor": N}` lines, `--since-seq`, `am events --escalations`,
  the `head` requirement, `cursor_reset`/`store_id` handling.
- Any change to the 1.2 escalation rules, the registry rules (no new registry re-reads) or
  the ending table.
- `RunAlertsService.qml`, `notify.py` wiring, `alertNotification` use, the switch, the
  manifest, `RunAlertsStore.qml`, `RunsScreen.qml`: sibling cards of story 11ef73c2.
- `common/am_runs.py` changes: it is reused as is.
