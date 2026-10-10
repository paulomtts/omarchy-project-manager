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

---

# 1.3 runs-alerts.py: dead runs by a lease poll — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `runs-alerts.py` also prints `{"alert": {run_id, root, project, state: "dead"}}` once when a run it has seen started with a live lease is later read started with a lease that is not live, by reading `am runs --repo-dir R` once per registered root at start and every 60 s for the roots that hold a started run.

**Architecture:** A new `Tracker` class in `core/backend/runs/runs-alerts.py` owns the tracked set (run id → registry key, root_path, name, armed), the 60 s interval and the `dead` alert; its only time source is an injected `clock` (default `time.monotonic`) and it never sleeps. It reads am through `common.am_runs.call_am` + `run_list`. `Watcher` (1.2) hands every run_upsert's status and registry key to the tracker after its escalation handling; `main` seeds the tracker before spawning `am watch`, and `stream` calls `tracker.poll_if_due()` at the top of every loop turn (after each am line and each 1 s idle wake).

**Tech Stack:** Python 3 stdlib (`subprocess`, `queue`, `threading`, `time`), pytest (subprocess tier with a fake `am`/`brd` on a temp PATH; in-process tier via `importlib.util.spec_from_file_location`).

**Spec:** `docs/superpowers/specs/1-3-runs-alerts-py-dead-b1ea30b8.md` (prepended above).

## Global Constraints

- Only documented `am` and `brd` commands, as argv lists, never a shell; am's database and on-disk layout are never read.
- A read of root R is exactly `[<am>, "runs", "--repo-dir", R]`, R the `root_path` as brd printed it, stdin `/dev/null`, bounded by `AM_TIMEOUT` (60 s), via `common.am_runs.call_am` and `run_list` — no second envelope parser.
- No second definition of `emit`, `inside`, `write_atomic`, `split_frontmatter`, `frontmatter_of`; `tests/architecture` passes unchanged.
- `common/am_runs.py` is not changed.
- The poll interval is 60 s; the main loop's idle wake stays `IDLE_POLL = 1.0`.
- The dead alert is one line, flushed at once, keys in order: `{"alert": {"run_id", "root", "project", "state": "dead"}}` — no `gseq`.
- Docstrings and comments state the contract only, no narrative. The module docstring keeps every 1.2 sentence that is still true.
- TDD: every test is written and seen failing before the code that passes it.
- Tests never `pkill`/`killall`/pattern-kill; they signal only recorded PIDs; every wait is bounded.
- Verification: `bash tests/run.sh` green. Quick loop: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_alerts.py tests/architecture -q`.

## Review Focus

1. **am prints bytes that are not UTF-8 on an `am runs` read** — `call_am` decodes with `text=True`, so a `UnicodeDecodeError` (a `ValueError`) would escape and end the helper with HelperError; expected: a failed read (nothing printed, runs kept). Pinned in Task 1 (`test_failed_poll_keeps_runs[undecodable]`).
2. **`am runs` hangs past its timeout** — expected: the child is killed and reaped, the read fails, the run stays tracked and is read again at the next due time. Pinned in Task 1 (`test_poll_timeout_keeps_runs`).
3. **am cannot start at poll time (binary replaced, permissions changed)** — `OSError` from `subprocess.run`; expected: a failed read, not a helper crash. Pinned in Task 1 (`test_poll_am_cannot_start_keeps_runs`).
4. **A poll answer whose run list is malformed (a row without an id)** — `run_list` raises `AmFailure`; expected: a failed read for that root only, nothing dropped. Pinned in Task 1 (`test_failed_poll_keeps_runs[row-without-id]`).
5. **A `started` run_upsert for a run the seed tracked unarmed (already dead at start), or a run_upsert with a non-string status** — expected: neither arms the run nor drops it, so no false `dead` alert at the next poll and polling continues. Pinned in Task 2 (`test_upsert_never_arms_and_non_string_status_keeps`).

---

## File Structure

- Modify `core/backend/runs/runs-alerts.py` — add `POLL_EVERY`, `live()`, class `Tracker`; split `Watcher.see` into the recording + `escalate()`, and hand off to the tracker; `stream` polls; `main` seeds; module docstring.
- Modify `tests/core/backend/runs/test_runs_alerts.py` — fake `am` answers `am runs` from `runs.json`; new helpers; in-process tier; new subprocess tests; `test_argv` updated.
- Modify `docs/architecture.md:197` — one sentence for `runs-alerts.py`; "All three use" → "They all use".

---

### Task 1: `Tracker` — seed, lease poll and the `dead` alert

**Files:**
- Modify: `core/backend/runs/runs-alerts.py:35-45` (imports), insert after `upsert()` (line 136)
- Test: `tests/core/backend/runs/test_runs_alerts.py`

**Interfaces:**
- Consumes: `common.am_runs.call_am(am, args, timeout)`, `run_list(data)`, `AmFailure`, `AM_TIMEOUT`; runs-alerts.py's `say(payload)`.
- Produces (later tasks rely on these exact names):
  - `POLL_EVERY = 60`
  - `live(row) -> bool`
  - `class Tracker(am: str, clock=time.monotonic)` with attribute `runs: dict[str, dict]` (run id → `{"key", "root", "name", "armed"}`) and methods
    - `seed(registry: dict[str, tuple[str, str]]) -> None`
    - `see(run_id: str, status, key: str | None, registry: dict[str, tuple[str, str]]) -> None`
    - `poll_if_due() -> None`
  - Test helpers in the test file: `RUN_A`, `RUN_B`, `LIVE`, `row()`, `done_row()`, `runs_reply()`, `RUNS_FAILURES`, `set_runs()`, `dead()`, `am_path()`, `runs_calls()`, `load_module()`, `Clock`, fixture `mod`, `registry()`, `printed()`, `at()`, `seeded()`.

- [ ] **Step 1: Teach the fake `am` to answer `am runs`, and add the shared test helpers**

In `tests/core/backend/runs/test_runs_alerts.py`, replace the module docstring AND the stdlib import block (lines 1-18, up to and including `import time`; `import pytest` at line 20 stays) with the block below, so no import appears twice:

```python
"""runs-alerts.py: escalation alerts from `am watch --all --follow --from-now` and
dead alerts from `am runs --repo-dir R`.

Hermetic: a fake `am` on a temp PATH. For `am runs` it answers from
FAKE_AM_DIR/runs.json: per --repo-dir value a list of answers ({stdout, exit},
optional sleep before answering), the Nth call for a root getting the Nth answer
(the last repeats), any other root the "default" answer; it writes its pid to
runs.pid. For every other argv (`am watch`) it replays FAKE_AM_DIR/script.json:
a list of steps (a JSON line, raw text, or a sleep), then a chosen stderr text
and exit code, and writes its pid to pid. A fake `brd` answers its Nth call from
FAKE_BRD_DIR/responses.json (the last answer repeats). The JSON lines are copies
of the committed captures in tests/fixtures/am/; a line no capture holds, or a
capture copy with edited fields, is labelled `synthetic:`. Both fakes log their
argv to calls.log. HOME and XDG_* are temp. The real `am`, the real `brd` and
real data are never touched. The in-process tests load the module with
importlib and drive `Tracker` with an injected clock; am is still the fake.
"""
import importlib.util
import json
import os
import queue
import signal
import stat
import subprocess
import sys
import threading
import time
```

(`queue` and `threading` are used by Task 3's tests; importing them now keeps the import block in one place.)

Replace `FAKE_AM` (lines 27-48) with:

```python
FAKE_AM = r'''#!/usr/bin/env python3
import json, os, sys, time
d = os.environ["FAKE_AM_DIR"]
argv = sys.argv[1:]
log = os.path.join(d, "calls.log")
before = []
if os.path.exists(log):
    with open(log) as f:
        before = f.read().splitlines()
with open(log, "a") as f:
    f.write(json.dumps(argv) + "\n")
if argv[:1] == ["runs"]:
    with open(os.path.join(d, "runs.pid"), "w") as f:
        f.write(str(os.getpid()))
    with open(os.path.join(d, "runs.json")) as f:
        table = json.load(f)
    root = argv[argv.index("--repo-dir") + 1] if "--repo-dir" in argv else None
    answers = table["answers"].get(root) or [table["default"]]
    answer = answers[min(before.count(json.dumps(argv)), len(answers) - 1)]
    time.sleep(answer.get("sleep", 0))
    sys.stdout.buffer.write(answer.get("stdout", "").encode("utf-8", "surrogateescape"))
    sys.stdout.flush()
    sys.exit(answer.get("exit", 0))
with open(os.path.join(d, "pid"), "w") as f:
    f.write(str(os.getpid()))
with open(os.path.join(d, "script.json")) as f:
    script = json.load(f)
for step in script["steps"]:
    if "sleep" in step:
        time.sleep(step["sleep"])
        continue
    if "raw" in step:
        sys.stdout.write(step["raw"] + "\n")
    else:
        sys.stdout.write(json.dumps(step["line"], separators=(",", ":")) + "\n")
    sys.stdout.flush()
sys.stderr.write(script.get("stderr", ""))
sys.stderr.flush()
sys.exit(script.get("exit", 0))
'''
```

Directly after `def set_brd(...)` (ends line 107), add:

```python
# The captured started run (row 0 of tests/fixtures/am/runs.json).
RUN_A = fixture("runs.json")["data"]["runs"][0]["id"]
RUN_B = "20261008T150000Z-0000000b"  # synthetic: a second run id
LIVE = object()


def row(run_id=RUN_A, status="started", lease=LIVE):
    """A copy of captured row 0 (started, lease live) with id set. synthetic:
    when run_id, status or lease is edited; MISSING drops lease, LIVE keeps the
    capture's live lease."""
    r = fixture("runs.json")["data"]["runs"][0]
    r["id"] = run_id
    r["status"] = status
    if lease is MISSING:
        r.pop("lease")
    elif lease is not LIVE:
        r["lease"] = lease
    return r


def done_row():
    """Captured row 1: done, lease null."""
    return fixture("runs.json")["data"]["runs"][1]


def runs_reply(*rows):
    """An `am runs` answer: the captured envelope (without the capture's _note)
    whose runs are `rows`."""
    reply = fixture("runs.json")
    reply.pop("_note")
    reply["data"]["runs"] = list(rows)
    return {"stdout": json.dumps(reply) + "\n", "exit": 0}


# synthetic: `am runs` answers that are failed reads.
RUNS_FAILURES = {
    "ok-false": {"stdout": json.dumps({"ok": False, "error": {
        "type": "StoreBusyError", "message": "the am store is busy; try again"}}) + "\n",
        "exit": 1},
    "not-json": {"stdout": "not json\n", "exit": 0},
    "no-runs": {"stdout": json.dumps({"ok": True, "data": {"as_of_seq": 1}}) + "\n",
                "exit": 0},
    "row-without-id": runs_reply({"status": "started", "lease": {"live": True}}),
    "undecodable": {"stdout": "\udcff\n", "exit": 0},
}


def set_runs(world, answers=None):
    """`am runs` answers per --repo-dir value (a path is keyed by its text), in
    call order, the last repeating; any other root gets runs_reply()."""
    table = {str(root): list(replies) for root, replies in (answers or {}).items()}
    (world["am"] / "runs.json").write_text(
        json.dumps({"answers": table, "default": runs_reply()}))
```

In the `world` fixture, after `set_brd(w, projects(project(repo)))` (line 128), add:

```python
    set_runs(w)
```

and change the fixture docstring to:

```python
    """A temp PATH with a fake am and a fake brd, their dirs, a temp HOME and an
    existing project dir `repo`, which brd registers unless a test says otherwise.
    Every `am runs` answers with an empty run list unless a test says otherwise."""
```

After `def alert(...)` (ends line 186), add:

```python
def dead(root, run_id=RUN_A, name=NAME):
    """The helper's dead alert line for `run_id` under the registered `root`."""
    return {"alert": {"run_id": run_id, "root": str(root), "project": name,
                      "state": "dead"}}
```

After `def brd_calls(...)` (ends line 217), add:

```python
def am_path(world):
    return str(world["bin"] / "am")


def runs_calls(world):
    """The fake am's `am runs` argv lists, in call order."""
    return [c for c in calls(world) if c[:1] == ["runs"]]
```

At the end of the file, add the in-process scaffold:

```python
# --- in-process: the Tracker with an injected clock ----------------------------------

def load_module():
    """Import the helper in-process (its file name is not a Python identifier)."""
    spec = importlib.util.spec_from_file_location("runs_alerts", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Clock:
    """The injected clock: returns `now`, which only the test moves."""

    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now


@pytest.fixture
def mod(world, monkeypatch):
    """The helper module, loaded in-process with the fake am and brd on PATH."""
    for name, value in env_for(world).items():
        monkeypatch.setenv(name, value)
    return load_module()


def registry(*entries):
    """A registry as read_registry builds it: realpath(root) -> (root text, name)."""
    return {os.path.realpath(str(root)): (str(root), name) for root, name in entries}


def printed(capsys):
    """The JSON lines printed since the last call."""
    return [json.loads(line) for line in capsys.readouterr().out.splitlines()]


def at(clock, tracker, now):
    """Move the clock to `now` and give the tracker its "poll if due" call."""
    clock.now = now
    tracker.poll_if_due()


def seeded(mod, world, *answers):
    """A Tracker on the fake am and a Clock at 0, seeded from a registry of
    `repo` alone whose `am runs` answers are `answers`."""
    set_runs(world, {world["repo"]: answers})
    clock = Clock()
    tracker = mod.Tracker(am_path(world), clock)
    tracker.seed(registry((world["repo"], NAME)))
    return tracker, clock
```

- [ ] **Step 2: Run the existing tests to confirm the scaffold change keeps them green**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_alerts.py -q`
Expected: PASS (all 1.2 tests; the helper does not call `am runs` yet, and only `watch` writes `pid`).

- [ ] **Step 3: Write the failing Tracker tests**

Append to `tests/core/backend/runs/test_runs_alerts.py`:

```python
def test_dead_once(world, mod, capsys):
    tracker, clock = seeded(mod, world, runs_reply(row()), runs_reply(row(lease=None)))
    assert printed(capsys) == []  # the seed prints nothing
    at(clock, tracker, 60)
    lines = printed(capsys)
    assert lines == [dead(world["repo"])]
    assert list(lines[0]) == ["alert"]
    assert list(lines[0]["alert"]) == ["run_id", "root", "project", "state"]
    at(clock, tracker, 120)
    assert printed(capsys) == []
    assert runs_calls(world) == [["runs", "--repo-dir", str(world["repo"])]] * 3


@pytest.mark.parametrize("lease", [None, MISSING, {}, {"live": False}, {"live": "true"},
                                   {"live": 1}, "live"],
                         ids=["synthetic: null", "synthetic: missing", "synthetic: empty",
                              "synthetic: false", "synthetic: string-true", "synthetic: one",
                              "synthetic: string"])
def test_not_live_shapes(world, mod, capsys, lease):
    tracker, clock = seeded(mod, world, runs_reply(row()), runs_reply(row(lease=lease)))
    at(clock, tracker, 60)
    assert printed(capsys) == [dead(world["repo"])]


def test_re_armed_after_resume(world, mod, capsys):
    tracker, clock = seeded(mod, world, runs_reply(row()), runs_reply(row(lease=None)),
                            runs_reply(row()), runs_reply(row(lease=None)))
    at(clock, tracker, 60)
    assert printed(capsys) == [dead(world["repo"])]
    at(clock, tracker, 120)
    assert printed(capsys) == []
    at(clock, tracker, 180)
    assert printed(capsys) == [dead(world["repo"])]


def test_seeded_dead_waits_for_live(world, mod, capsys):
    tracker, clock = seeded(mod, world, *[runs_reply(row(lease=None))] * 3,
                            runs_reply(row()), runs_reply(row(lease=None)))
    for now in (60, 120, 180):
        at(clock, tracker, now)
    assert printed(capsys) == []
    at(clock, tracker, 240)
    assert printed(capsys) == [dead(world["repo"])]
    assert len(runs_calls(world)) == 5


def test_poll_interval(world, mod):
    tracker, clock = seeded(mod, world, runs_reply(row()))
    at(clock, tracker, 59.9)
    assert len(runs_calls(world)) == 1
    at(clock, tracker, 60)
    assert len(runs_calls(world)) == 2
    at(clock, tracker, 60)  # the same instant: not due again
    at(clock, tracker, 119.9)
    assert len(runs_calls(world)) == 2
    at(clock, tracker, 120)
    assert len(runs_calls(world)) == 3


def test_no_poll_when_idle(world, mod):
    tracker, clock = seeded(mod, world, runs_reply(done_row()))
    for now in (60, 600, 3600):
        at(clock, tracker, now)
    assert len(runs_calls(world)) == 1


def test_polls_only_roots_with_started(world, mod):
    r1, r2 = world["tmp"] / "r1", world["tmp"] / "r2"
    r1.mkdir()
    r2.mkdir()
    set_runs(world, {r1: [runs_reply(row())]})
    clock = Clock()
    tracker = mod.Tracker(am_path(world), clock)
    tracker.seed(registry((r1, "one"), (r2, "two")))
    assert runs_calls(world) == [["runs", "--repo-dir", str(r1)],
                                 ["runs", "--repo-dir", str(r2)]]
    at(clock, tracker, 60)
    assert runs_calls(world)[2:] == [["runs", "--repo-dir", str(r1)]]


def test_polls_in_registry_order(world, mod):
    r1, r2 = world["tmp"] / "r1", world["tmp"] / "r2"
    r1.mkdir()
    r2.mkdir()
    set_runs(world, {r1: [runs_reply(row())], r2: [runs_reply(row(RUN_B))]})
    clock = Clock()
    tracker = mod.Tracker(am_path(world), clock)
    tracker.seed(registry((r2, "two"), (r1, "one")))
    at(clock, tracker, 60)
    assert runs_calls(world) == [["runs", "--repo-dir", str(r2)],
                                 ["runs", "--repo-dir", str(r1)]] * 2


@pytest.mark.parametrize("status", ["done", "stopped", "escalated", "cancelled", "canceled",
                                    "waiting"],
                         ids=["done", "stopped", "escalated", "cancelled", "canceled",
                              "synthetic: other"])
def test_terminal_dropped(world, mod, capsys, status):
    tracker, clock = seeded(mod, world, runs_reply(row()),
                            runs_reply(row(status=status, lease=None)))
    at(clock, tracker, 60)
    assert printed(capsys) == []
    at(clock, tracker, 120)
    at(clock, tracker, 600)
    assert len(runs_calls(world)) == 2


def test_absent_row_dropped(world, mod, capsys):
    tracker, clock = seeded(mod, world, runs_reply(row()), runs_reply())
    at(clock, tracker, 60)
    assert printed(capsys) == []
    at(clock, tracker, 120)
    at(clock, tracker, 600)
    assert len(runs_calls(world)) == 2


@pytest.mark.parametrize("failure", sorted(RUNS_FAILURES))
def test_failed_poll_keeps_runs(world, mod, capsys, failure):
    tracker, clock = seeded(mod, world, runs_reply(row()), RUNS_FAILURES[failure],
                            runs_reply(row(lease=None)))
    at(clock, tracker, 60)
    assert printed(capsys) == []
    assert len(runs_calls(world)) == 2
    at(clock, tracker, 119.9)
    assert len(runs_calls(world)) == 2
    at(clock, tracker, 120)
    assert printed(capsys) == [dead(world["repo"])]


def test_poll_timeout_keeps_runs(world, mod, capsys, monkeypatch):
    monkeypatch.setattr(mod, "AM_TIMEOUT", 1.0)
    slow = {**runs_reply(row(lease=None)), "sleep": 8}
    tracker, clock = seeded(mod, world, runs_reply(row()), slow, runs_reply(row(lease=None)))
    began = time.monotonic()
    at(clock, tracker, 60)
    assert time.monotonic() - began < 6
    assert printed(capsys) == []
    assert_gone(int((world["am"] / "runs.pid").read_text()))  # the slow am runs was reaped
    at(clock, tracker, 120)
    assert printed(capsys) == [dead(world["repo"])]


def test_poll_am_cannot_start_keeps_runs(world, mod, capsys):
    tracker, clock = seeded(mod, world, runs_reply(row()), runs_reply(row(lease=None)))
    am = world["bin"] / "am"
    am.chmod(0o644)
    at(clock, tracker, 60)
    assert printed(capsys) == []
    assert len(runs_calls(world)) == 1
    am.chmod(0o755)
    at(clock, tracker, 120)
    assert printed(capsys) == [dead(world["repo"])]


def test_new_started_row_in_poll(world, mod, capsys):
    tracker, clock = seeded(mod, world, runs_reply(row()),
                            runs_reply(row(), row(RUN_B, lease=None)),
                            runs_reply(row(), row(RUN_B)),
                            runs_reply(row(), row(RUN_B, lease=None)))
    at(clock, tracker, 60)
    assert printed(capsys) == []
    at(clock, tracker, 120)
    assert printed(capsys) == []
    at(clock, tracker, 180)
    assert printed(capsys) == [dead(world["repo"], run_id=RUN_B)]
```

- [ ] **Step 4: Run them to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_alerts.py -q -k "dead_once or not_live or re_armed or seeded_dead or poll_interval or no_poll_when_idle or polls_only or polls_in or terminal_dropped or absent_row or failed_poll or poll_timeout or cannot_start or new_started"`
Expected: FAIL — every one with `AttributeError: module 'runs_alerts' has no attribute 'Tracker'`, except `test_poll_timeout_keeps_runs`, which fails first on `monkeypatch.setattr(mod, "AM_TIMEOUT", ...)` with `AttributeError: ... has no attribute 'AM_TIMEOUT'`.

- [ ] **Step 5: Implement `Tracker`**

In `core/backend/runs/runs-alerts.py`, add `import time` to the stdlib imports (between `import threading` and the `sys.path.insert` line), so the block reads:

```python
import json
import os
import queue
import shutil
import signal
import subprocess
import sys
import threading
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.am_runs import AM_TIMEOUT, AmFailure, call_am, run_list  # noqa: E402
from common.json_line import emit  # noqa: E402
```

After the `BRD_TIMEOUT = 30 ...` line add:

```python
POLL_EVERY = 60  # seconds between lease polls while a run is tracked
```

After `def upsert(line): ...` (ends line 136) and before `class Watcher:`, add:

```python
def live(row):
    """True when the row's lease is an object whose live is the JSON true."""
    lease = row.get("lease")
    return isinstance(lease, dict) and lease.get("live") is True


class Tracker:
    """The runs last seen started, each under the root it was first tracked
    under (registry key, root_path, name) and armed or not, and when the next
    lease poll is due. `clock` is its only time source; it never sleeps."""

    def __init__(self, am, clock=time.monotonic):
        self.am = am
        self.clock = clock
        self.runs = {}  # run id -> {"key", "root", "name", "armed"}
        self.order = []  # registry keys, in the registry's order
        self.since = None  # when the poll interval last restarted

    def read(self, root):
        """The run list of one `am runs --repo-dir root`, or None when the read
        fails (am's ok:false envelope, other output, a malformed run list, a
        timeout, am failing to start)."""
        try:
            return run_list(call_am(self.am, ["runs", "--repo-dir", root], AM_TIMEOUT))
        except (AmFailure, subprocess.TimeoutExpired, OSError, ValueError):
            return None

    def track(self, run_id, key, root, name, armed):
        if not self.runs:
            self.since = self.clock()
        self.runs[run_id] = {"key": key, "root": root, "name": name, "armed": armed}

    def take(self, key, root, name, rows):
        """One successful read of the root `key`: each run tracked under it is
        armed (started, live), alerted dead and disarmed (started, not live,
        armed) or dropped (any other status, or no row); every untracked
        started row is tracked under it, armed when its lease is live."""
        by_id = {}
        for row in rows:
            by_id.setdefault(row["id"], row)
        for run_id, run in list(self.runs.items()):
            if run["key"] != key:
                continue
            row = by_id.get(run_id)
            if row is None or row["status"] != "started":
                del self.runs[run_id]
            elif live(row):
                run["armed"] = True
            elif run["armed"]:
                run["armed"] = False
                say({"alert": {"run_id": run_id, "root": run["root"],
                               "project": run["name"], "state": "dead"}})
        for run_id, row in by_id.items():
            if row["status"] == "started" and run_id not in self.runs:
                self.track(run_id, key, root, name, live(row))

    def seed(self, registry):
        """One read of each registered root, in the registry's order; a failed
        read skips that root. Prints nothing."""
        self.order = list(registry)
        for key, (root, name) in registry.items():
            rows = self.read(root)
            if rows is not None:
                self.take(key, root, name, rows)
        self.since = self.clock()

    def see(self, run_id, status, key, registry):
        """One run_upsert: status "started" tracks a run not yet tracked whose
        registry key is in `registry`, armed; any other string drops the run; a
        tracked started run and a non-string status change nothing."""
        if not isinstance(status, str):
            return
        if status != "started":
            self.runs.pop(run_id, None)
            return
        if run_id in self.runs or key is None or key not in registry:
            return
        self.order = list(registry)
        root, name = registry[key]
        self.track(run_id, key, root, name, True)

    def poll_if_due(self):
        """When a run is tracked and POLL_EVERY seconds have passed since the
        latest of the seed, the previous poll and the tracked set becoming
        non-empty: read each root holding a tracked run, in registry order, and
        restart the interval."""
        if not self.runs or self.clock() - self.since < POLL_EVERY:
            return
        held = {}
        for run in self.runs.values():
            held.setdefault(run["key"], (run["root"], run["name"]))
        keys = [k for k in self.order if k in held] + [k for k in held if k not in self.order]
        for key in keys:
            root, name = held[key]
            rows = self.read(root)
            if rows is not None:
                self.take(key, root, name, rows)
        self.since = self.clock()
```

- [ ] **Step 6: Run the Tracker tests and the whole file**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_alerts.py tests/architecture -q`
Expected: PASS (all tests, including every 1.2 test).

- [ ] **Step 7: Commit**

```bash
git add core/backend/runs/runs-alerts.py tests/core/backend/runs/test_runs_alerts.py
git commit -m "feat(runs): runs-alerts.py Tracker polls leases and alerts dead runs"
```

---

### Task 2: `Watcher` hands run_upserts to the tracker

**Files:**
- Modify: `core/backend/runs/runs-alerts.py` — `class Watcher` (the 1.2 lines 139-172) and `main` (`watcher = Watcher(read_registry() or {})`, line 260)
- Test: `tests/core/backend/runs/test_runs_alerts.py`

**Interfaces:**
- Consumes: `Tracker.see(run_id, status, key, registry)`, `Tracker(am, clock)`, `real(path)`; test helpers `seeded`, `registry`, `at`, `printed`, `runs_reply`, `row`, `dead`, `alert`, `runs_calls`, `brd_calls`, `RUN_A`, `RUN_B`.
- Produces: `Watcher(registry, tracker)` with attribute `tracker`; `Watcher.see(run_id, payload)` (unchanged signature); `Watcher.escalate(run_id)`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/core/backend/runs/test_runs_alerts.py`:

```python
def test_upsert_started_tracks(world, mod, capsys):
    repo = world["repo"]
    tracker, clock = seeded(mod, world, runs_reply(), runs_reply(row(lease=None)))
    watcher = mod.Watcher(registry((repo, NAME)), tracker)
    clock.now = 10
    watcher.see(RUN_A, {"status": "started", "repo_dir": str(repo)})
    at(clock, tracker, 60)  # 50 s after the tracked set became non-empty
    at(clock, tracker, 69.9)
    assert len(runs_calls(world)) == 1
    at(clock, tracker, 70)
    assert len(runs_calls(world)) == 2
    assert printed(capsys) == [dead(repo)]
    assert brd_calls(world) == []


def test_upsert_started_unregistered_not_tracked(world, mod, capsys):
    tracker, clock = seeded(mod, world, runs_reply())
    watcher = mod.Watcher(registry((world["repo"], NAME)), tracker)
    watcher.see(RUN_A, {"status": "started", "repo_dir": str(world["tmp"] / "elsewhere")})
    watcher.see(RUN_B, {"status": "started"})  # no repo_dir at all
    for now in (60, 600):
        at(clock, tracker, now)
    assert len(runs_calls(world)) == 1
    assert printed(capsys) == []
    assert brd_calls(world) == []  # no registry re-read for a started run


@pytest.mark.parametrize("status", ["escalated", "cancelled", "done"])
def test_upsert_other_status_drops(world, mod, capsys, status):
    repo = world["repo"]
    tracker, clock = seeded(mod, world, runs_reply(row()), runs_reply(row(lease=None)))
    watcher = mod.Watcher(registry((repo, NAME)), tracker)
    watcher.see(RUN_A, {"status": status, "repo_dir": str(repo)})
    for now in (60, 600):
        at(clock, tracker, now)
    assert len(runs_calls(world)) == 1
    assert printed(capsys) == ([alert(repo, run_id=RUN_A)] if status == "escalated" else [])
    assert brd_calls(world) == []


def test_upsert_never_arms_and_non_string_status_keeps(world, mod, capsys):
    repo = world["repo"]
    tracker, clock = seeded(mod, world, runs_reply(row(lease=None)))
    watcher = mod.Watcher(registry((repo, NAME)), tracker)
    watcher.see(RUN_A, {"status": "started", "repo_dir": str(repo)})
    watcher.see(RUN_A, {"status": None, "repo_dir": str(repo)})
    at(clock, tracker, 60)
    at(clock, tracker, 120)
    assert printed(capsys) == []  # seeded unarmed; an upsert never arms
    assert len(runs_calls(world)) == 3  # still tracked: polled at 60 and 120
```

- [ ] **Step 2: Run them to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_alerts.py -q -k upsert_`
Expected: FAIL — `TypeError: Watcher.__init__() takes 2 positional arguments but 3 were given`.

- [ ] **Step 3: Implement**

Replace `class Watcher` (the whole class, `class Watcher:` through the `say({"alert": ... "state": "escalated"}})` line) with:

```python
class Watcher:
    """Each run's last status and last repo_dir, the registry
    (realpath -> (root_path, name)) and the Tracker its run_upserts go to."""

    def __init__(self, registry, tracker):
        self.registry = registry
        self.tracker = tracker
        self.status = {}
        self.repo_dir = {}

    def see(self, run_id, payload):
        """Record a run_upsert's payload; on a transition into escalated,
        escalate(); then hand the tracker the run's status and, for "started",
        the realpath of its last repo_dir."""
        before = self.status.get(run_id)
        status, repo_dir = payload.get("status"), payload.get("repo_dir")
        if isinstance(status, str):
            self.status[run_id] = status
        if isinstance(repo_dir, str) and repo_dir:
            self.repo_dir[run_id] = repo_dir
        if status == "escalated" and before != "escalated":
            self.escalate(run_id)
        repo_dir = self.repo_dir.get(run_id)
        key = real(repo_dir) if status == "started" and repo_dir is not None else None
        self.tracker.see(run_id, status, key, self.registry)

    def escalate(self, run_id):
        """Print the escalation alert when the run's last repo_dir is
        registered, reading the registry again first when it is not (never for
        a repo_dir realpath cannot take)."""
        repo_dir = self.repo_dir.get(run_id)
        key = real(repo_dir) if repo_dir is not None else None
        if key is None:
            return
        if key not in self.registry:
            fresh = read_registry()
            if fresh is not None:
                self.registry = fresh
        if key in self.registry:
            root, name = self.registry[key]
            say({"alert": {"run_id": run_id, "root": root, "project": name,
                           "state": "escalated"}})
```

In `main`, replace

```python
    watcher = Watcher(read_registry() or {})
```

with

```python
    registry = read_registry() or {}
    watcher = Watcher(registry, Tracker(am))
```

- [ ] **Step 4: Run the tests**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_alerts.py tests/architecture -q`
Expected: PASS (new tests and every earlier one).

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-alerts.py tests/core/backend/runs/test_runs_alerts.py
git commit -m "feat(runs): runs-alerts.py tracks runs started while it watches"
```

---

### Task 3: the entry point seeds and polls; docstring and docs

**Files:**
- Modify: `core/backend/runs/runs-alerts.py` — module docstring (lines 1-34), `stream` (lines 205-234), `main`
- Modify: `docs/architecture.md:197`
- Test: `tests/core/backend/runs/test_runs_alerts.py` — replace `test_argv` (lines 269-276), add subprocess tests and two in-process `stream` tests

**Interfaces:**
- Consumes: `Tracker(am)`, `Tracker.seed(registry)`, `Tracker.poll_if_due()`, `Watcher(registry, tracker)`, `Watcher.tracker`, `EOF`, `stream(lines, watcher)`; test helpers `set_runs`, `runs_reply`, `row`, `RUNS_FAILURES`, `RUN_B`, `alert`, `calls`, `start_helper`, `assert_gone`, `seeded`, `registry`, `printed`, `dead`, `hello`.
- Produces: nothing new for other tasks.

- [ ] **Step 1: Write the failing tests**

In `tests/core/backend/runs/test_runs_alerts.py`, replace `test_argv` (lines 269-276) with:

```python
WATCH = ["watch", "--all", "--follow", "--from-now"]


def test_argv(world):
    set_script(world, [hello()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == []
    # argv lists, no shell: the fake am sees exactly these arguments.
    assert calls(world) == [["runs", "--repo-dir", str(world["repo"])], WATCH]


def test_argv_empty_registry(world):
    set_brd(world, projects())
    set_script(world, [hello()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == []
    assert calls(world) == [WATCH]


def test_seed_argv_order(world):
    real1 = world["tmp"] / "real1"
    real1.mkdir()
    r1 = world["tmp"] / "r1"
    r1.symlink_to(real1)
    r2 = world["tmp"] / "r2"
    r2.mkdir()
    set_brd(world, projects(project(r1, name="one"), project(r2, name="two")))
    set_script(world, [hello()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == []
    # once per root, brd's order, the root as brd printed it (the link), before the watch.
    assert calls(world) == [["runs", "--repo-dir", str(r1)],
                            ["runs", "--repo-dir", str(r2)], WATCH]


def test_seed_never_alerts(world):
    set_runs(world, {world["repo"]: [runs_reply(row(lease=None), row(RUN_B))]})
    set_script(world, [hello()])
    code, lines, err = run_helper(world)
    assert code == 0, err
    assert lines == []


@pytest.mark.parametrize("failure", ["ok-false", "not-json", "no-runs"])
def test_failed_seed_of_one_root(world, failure):
    r1, r2 = world["tmp"] / "r1", world["tmp"] / "r2"
    r1.mkdir()
    r2.mkdir()
    set_brd(world, projects(project(r1, name="one"), project(r2, name="two")))
    set_runs(world, {r1: [RUNS_FAILURES[failure]], r2: [runs_reply(row(RUN_B))]})
    set_script(world, [hello(), upsert("escalated", r2, run_id=RUN_B)])
    code, lines, err = run_helper(world)
    assert code == 0, err
    assert "Traceback" not in err
    assert lines == [alert(r2, run_id=RUN_B, name="two")]
    assert calls(world) == [["runs", "--repo-dir", str(r1)],
                            ["runs", "--repo-dir", str(r2)], WATCH]


def test_no_poll_when_idle_subprocess(world):
    set_script(world, [hello(), pause(2)])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == []
    assert calls(world) == [["runs", "--repo-dir", str(world["repo"])], WATCH]


def wait_for_runs(world, within=10.0):
    """The pid of the fake am's latest `am runs`, once one has started."""
    end = time.monotonic() + within
    while time.monotonic() < end:
        try:
            return int((world["am"] / "runs.pid").read_text())
        except (FileNotFoundError, ValueError):
            time.sleep(0.05)
    pytest.fail("am runs never started")


@pytest.mark.parametrize("sig", [signal.SIGTERM, signal.SIGINT], ids=["SIGTERM", "SIGINT"])
def test_signal_during_seed_leaves_no_am(world, sig):
    set_runs(world, {world["repo"]: [{**runs_reply(row()), "sleep": 30}]})
    set_script(world, [hello()])
    p = start_helper(world)
    try:
        pid = wait_for_runs(world)  # sync point: the seed read is running
        p.send_signal(sig)
        code = p.wait(timeout=10)
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
    out = p.stdout.read()
    err = p.stderr.read()
    p.stdout.close()
    p.stderr.close()
    assert code == 0, err
    assert out == ""
    assert "Traceback" not in err
    assert_gone(pid)
    assert calls(world) == [["runs", "--repo-dir", str(world["repo"])]]  # no watch spawned
```

Append to the end of the file (in-process tier):

```python
def test_stream_polls_when_due(world, mod, capsys):
    tracker, clock = seeded(mod, world, runs_reply(row()), runs_reply(row(lease=None)))
    watcher = mod.Watcher(registry((world["repo"], NAME)), tracker)
    lines = queue.Queue()
    lines.put(json.dumps(hello()["line"]) + "\n")
    lines.put(mod.EOF)
    clock.now = 60
    assert mod.stream(lines, watcher) is None
    assert printed(capsys) == [dead(world["repo"])]


def test_stream_polls_on_idle_wake(world, mod, capsys):
    tracker, clock = seeded(mod, world, runs_reply(row()), runs_reply(row(lease=None)))
    watcher = mod.Watcher(registry((world["repo"], NAME)), tracker)
    lines = queue.Queue()

    def later():
        time.sleep(0.3)
        clock.now = 60  # due while no am line is pending
        time.sleep(2.5)
        lines.put(mod.EOF)

    feeder = threading.Thread(target=later, daemon=True)
    feeder.start()
    assert mod.stream(lines, watcher) is None
    feeder.join(timeout=10)
    assert printed(capsys) == [dead(world["repo"])]
    assert len(runs_calls(world)) == 2
```

- [ ] **Step 2: Run them to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_alerts.py -q -k "argv or seed or no_poll_when_idle_subprocess or signal_during_seed or stream_polls"`
Expected: FAIL — `test_argv`, `test_seed_argv_order`, `test_failed_seed_of_one_root`, `test_no_poll_when_idle_subprocess`, `test_signal_during_seed_leaves_no_am` (calls lack `runs`; `wait_for_runs` fails "am runs never started"), `test_stream_polls_*` (no dead line). `test_argv_empty_registry` and `test_seed_never_alerts` already pass (they pin behaviour that must survive the change).

- [ ] **Step 3: Implement — seed in `main`, poll in `stream`**

In `stream`, replace the loop head

```python
    refusal, greeted = None, False
    while True:
        try:
            raw = lines.get(timeout=IDLE_POLL)
```

with

```python
    refusal, greeted = None, False
    while True:
        watcher.tracker.poll_if_due()
        try:
            raw = lines.get(timeout=IDLE_POLL)
```

and replace its docstring with:

```python
    """Read am's stream until it ends, line by line as it arrives, giving the
    tracker its "poll if due" call before each line and on each idle wake.
    Every hello line (event "watch") is checked; each run_upsert after the
    first hello goes to `watcher`; every other line is ignored. Returns am's
    refusal envelope (the last line with an "ok" key) if it printed one, else
    None. Raises SchemaMismatch."""
```

In `main`, replace

```python
    registry = read_registry() or {}
    watcher = Watcher(registry, Tracker(am))
```

with

```python
    registry = read_registry() or {}
    tracker = Tracker(am)
    tracker.seed(registry)
    watcher = Watcher(registry, tracker)
```

- [ ] **Step 4: Run the tests**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_alerts.py tests/architecture -q`
Expected: PASS (every test in the file, 1.2's included).

- [ ] **Step 5: Update the module docstring**

Replace the module docstring of `core/backend/runs/runs-alerts.py` (lines 1-34) with:

```python
#!/usr/bin/env python3
"""Print an alert when a run of a registered project escalates, from
`am watch --all --follow --from-now`, or dies, from `am runs --repo-dir R`.

    runs-alerts.py

Takes no argument; any argument is a Usage error (exit 2) and neither am nor
brd is looked up or run. Long-lived. Looks up `am` (AmMissing when it is not on
PATH), reads the registry, reads each registered root once in the registry's
order (the seed), then spawns `am watch --all --follow --from-now`; every am
and brd command is an argv list, never a shell. Prints one JSON object per
line, flushed at once:
  {"alert": {"run_id": R, "root": P, "project": N, "state": "escalated"}}
      for each transition into escalated of a run whose last repo_dir names
      (realpath) a registered root; P is that root as brd printed it, N its
      project name.
  {"alert": {"run_id": R, "root": P, "project": N, "state": "dead"}}
      when a read finds an armed tracked run started with a lease that is not
      live; the run is disarmed until a read finds it started with a live
      lease. P and N are those of the root it was first tracked under.
  {"ok": false, "error": {"type", "message"}}
      then exit 1, with type SchemaMismatch, CorruptJournal (am exited 3),
      HelperError or AmMissing (Usage exits 2). An am refusal envelope is
      re-emitted unchanged when am exits other than 3, or when its type is
      StoreBusyError.
Every hello line (event "watch") must carry an integer schema of 1 or 2, else
SchemaMismatch. A run_upsert (non-empty string run_id, object payload) after
the first hello sets the run's last status (payload.status, when a string) and
last repo_dir (payload.repo_dir, when a non-empty string). A transition into
escalated is a run_upsert whose payload.status is "escalated" while the run's
last status before it was anything else, or none. Every other line is ignored.
The registry maps realpath(root_path) to (root_path, name) for each entry of
`brd projects` with a non-empty string root_path and a string name, the first
entry winning. It is read at start and again when a transition names a
repo_dir it does not hold; a successful read replaces it, a failed one (brd
missing, non-zero exit, a 30 s timeout, any other output) keeps it and prints
nothing.
A read of root R is `am runs --repo-dir R`, R as brd printed it, bounded by
60 s; am's ok:false envelope, any other output, a malformed run list, a
timeout or am failing to start is a failed read, which prints nothing and
changes nothing. A lease is live when it is an object whose live is the JSON
true. Tracked runs are the runs last seen started. The seed tracks every
started row of each root it reads, armed when its lease is live, and prints
nothing. While a run is tracked, a poll is due 60 s after the latest of the
seed, the previous poll and the tracked set becoming non-empty, checked after
every am line and every 1 s idle wake; it reads each root holding a tracked
run, in registry order. A read of R arms each run tracked under R whose row is
started with a live lease, alerts dead (when armed) a started row whose lease
is not live, drops a run whose row has any other status or is absent, and
tracks an untracked started row without alerting. A run_upsert whose status is
"started" tracks, armed, a run not yet tracked whose last repo_dir is
registered; any other status string drops the run. No run tracked, no read.
am exiting 0, SIGINT, SIGTERM or a closed stdout end the helper with exit 0,
an `am runs` read in progress included (that am is killed and reaped). Only
the `am` and `brd` commands are used; am's database and on-disk layout are
never read.
"""
```

- [ ] **Step 6: Update `docs/architecture.md`**

In `docs/architecture.md` line 197, replace

```
 All three use only documented `am` commands,
```

with

```
 `runs-alerts.py` takes no argument and is long-lived: it follows `am watch --all --follow --from-now`, reads `am runs --repo-dir R` once per registered root at start and every 60 s for the roots holding a started run (none while no run is started), and prints `{"alert": {run_id, root, project, state}}` with `state` `escalated` or `dead`. They all use only documented `am` commands,
```

(The text sits mid-line after `exactly one JSON line.`; the leading space is part of the match.)

- [ ] **Step 7: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest all green, every QML test `Totals: ... 0 failed`, exit 0.

- [ ] **Step 8: Commit**

```bash
git add core/backend/runs/runs-alerts.py tests/core/backend/runs/test_runs_alerts.py docs/architecture.md
git commit -m "feat(runs): runs-alerts.py seeds and polls am runs for dead runs"
```

---

## Self-review against the spec

| spec item | task / test |
|---|---|
| Lease live rule | Task 1 `live()`, `test_not_live_shapes` |
| Read of root R: argv, `/dev/null`, 60 s, failed reads | Task 1 `Tracker.read` (via `call_am`), `test_failed_poll_keeps_runs`, `test_poll_timeout_keeps_runs`, `test_poll_am_cannot_start_keeps_runs`; Task 3 `test_seed_argv_order` |
| Seed: order, before watch, failed root skipped, never prints, dead-at-start unarmed | Task 1 `seed`, `test_seeded_dead_waits_for_live`; Task 3 tests 1-4 |
| Poll timing (60 s from latest of seed / poll end / set non-empty; ~1 s granularity) | Task 1 `poll_if_due`, `test_poll_interval`; Task 2 `test_upsert_started_tracks`; Task 3 `test_stream_polls_*` |
| No poll when nothing tracked | `test_no_poll_when_idle`, `test_no_poll_when_idle_subprocess`, tests 13/14/18 |
| Poll reads only roots with a tracked run, registry order | `test_polls_only_roots_with_started`, `test_polls_in_registry_order` |
| Per-read rules (arm, dead once, drop, absent, new started row) | tests 5, 7, 13, 14, 16 |
| Watch rules (started tracks armed if registered, no brd re-read; other string drops; non-string unchanged; tracked unchanged) | Task 2 tests 17, 17b, 18, RF5 |
| Dead alert shape/key order | `test_dead_once` |
| Ending: failed read never ends; signal during seed kills and reaps `am runs`, exit 0, no line | `test_failed_seed_of_one_root`, `test_signal_during_seed_leaves_no_am` (subprocess.run kills and waits its child on any exception) |
| Injected clock, in-process tier | Task 1 `Clock`, `mod`, `seeded` |
| 1.2 tests unchanged except `test_argv` | Task 1 Step 2; Task 3 Step 4 |
| Module docstring; docs/architecture.md | Task 3 Steps 5-6 |
<!-- task-pipeline: validated -->
