# 1.2 runs-alerts.py: escalations from the journal (card a65dfeb3)

Narrowed from `docs/superpowers/specs/2026-10-05-alerts-panel-closed-design.md` (below "the
parent"): Behaviour, "What alerts" (lines 88-91); Architecture, the `runs-alerts.py` bullet
(lines 134-145); Failure modes (lines 175-183); Testing, the `test_runs_alerts.py` bullet
(lines 192-199). Parent story 11ef73c2. Blocked by 54739fc3 (1.1 `alertNotification`,
already landed in `core/domain/runs.js`; this card does not use it).

**The card overrides the parent where they differ.** The parent describes a later design: a
cursor argument, `--since-seq`, `am events --escalations`, a hello that must carry `head`,
an `am runs --all-projects` seed, `dead` detection, `{"cursor": N}` lines and a `gseq` in
the alert (parent lines 101-127, 134-145). None of that is in this card. This card's helper
takes no argument, follows `am watch --all --follow --from-now` (the command the parent
measured, line 65), accepts hello schema 1 or 2 with or without `head`, and alerts
`escalated` only.

## Starting point

- `core/backend/runs/runs-alerts.py` and `tests/core/backend/runs/test_runs_alerts.py` do
  not exist. Create both.
- `core/backend/runs/runs-watch.py` is the model: a long-lived helper that spawns `am watch`,
  pumps its stdout through a reader thread into a queue, collects stderr on a second thread,
  checks hello lines, treats any line with an `ok` key as am's refusal envelope, and maps
  am's exit (`finish`) to the helper's last line. Its signal handling (`guarded`,
  `quiet_exit`, `stop`) is the pattern to copy. `tests/core/backend/runs/test_runs_watch.py`
  is the model for the test scaffolding (fake `am` replaying a `script.json`, `world`
  fixture, `env_for`).
- `core/backend/common/json_line.py` provides `emit`. Import it as runs-watch.py does
  (`sys.path.insert(0, <this dir>/..)`, `from common.json_line import emit`).
- `brd projects` prints `{"ok": true, "data": [{"id", "name", "root_path", "created_at"},
  ...]}` (verified on this machine).
- Fixtures: `tests/fixtures/am/watch-hello.json` (`schema_1`: no `head`; `schema_2`: `head`,
  `store_id`, `cursor_reset`), `tests/fixtures/am/watch-events.json` (`data.events[]`, whose
  `run_upsert` lines carry `payload.status` `started` and `payload.repo_dir`
  `/home/user/Code/omarchy-project-manager`). No captured line is `escalated`.

## Constraints

- Layering (`docs/architecture.md`, enforced by `tests/architecture/test_layers.py`): files
  under `core/backend/` are not `.qml`/`.js`; no second definition of a shared Python helper
  (`def emit(`, `def inside(`, `write_atomic(`, `split_frontmatter(`, `frontmatter_of(`) —
  `test_shared_python_helpers_are_defined_once`. `tests/architecture` must pass unchanged.
- Parent line 145: only documented `am` and `brd` commands, as argv lists, never a shell.
  am's database and on-disk layout are never read.
- Card: docstrings and comments state the contract only, no narrative. TDD: tests first.
- Verification: `bash tests/run.sh` green. Quick loop:
  `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_alerts.py tests/architecture -q`.
- Never `pkill`/`killall`/pattern kills in tests or tooling; signal only recorded PIDs; bound
  every wait with a timeout.

## Behaviour

### Invocation

`runs-alerts.py` takes no argument. Any argument at all is a `Usage` error:
`{"ok": false, "error": {"type": "Usage", "message": "usage: runs-alerts.py"}}`, exit 2; neither
`am` nor `brd` is looked up or run. (The card lists no `Usage`; this is the sibling helpers'
convention for argv the contract does not allow.)

### Start order

1. `am` is looked up on `PATH` (`shutil.which("am")`). Not found: `AmMissing` envelope
   (`"am is not installed."`), exit 1; `brd` is not run.
2. The registry is read (below).
3. `am` is spawned with argv exactly `[<am>, "watch", "--all", "--follow", "--from-now"]`,
   stdin `/dev/null`, stdout and stderr piped, UTF-8 with replacement for bad bytes.

### The registry

Read by running `brd projects` (argv list, stdin `/dev/null`, 30 s timeout) at start, and
again each time an escalation transition (below) names a `repo_dir` that is not in the
current registry. It is never read at any other time.

- A successful read is: brd exits 0 and prints a JSON object with `ok` true and a list
  `data`. Each entry that is an object with a non-empty string `root_path` and a string
  `name` registers `realpath(root_path)` → (`root_path` as printed, `name`). Other entries
  are skipped, as is one whose `root_path` `realpath` cannot take (an embedded NUL raises
  `ValueError`; it must not end the helper). When two entries share a realpath, the first wins. A successful read
  **replaces** the registry.
- Anything else — `brd` not on `PATH`, non-zero exit, timeout, output that is not that JSON
  shape — is a failed read. A failed read **keeps** the registry as it was (empty at start).
  It prints nothing and does not end the helper (parent line 183: "no registered root is
  known; nothing alerts; retried at the next candidate").

### The stream

Each line am prints is handled in order, as it arrives; nothing is batched or delayed.

- **Not JSON, or not a JSON object:** ignored.
- **A line with an `ok` key:** am's refusal envelope; remembered (the last one wins) for the
  end, otherwise ignored.
- **A hello** (`event == "watch"`): every hello is checked. `schema` must be an integer
  (a JSON `true`/`false` is not) equal to 1 or 2; otherwise `SchemaMismatch` envelope, exit 1,
  am stopped. The message names the schema received, e.g.
  `am watch speaks schema 3; this helper reads schema 1 or 2.` `head` and every other hello
  key are neither required nor read. A hello prints nothing.
- **A `run_upsert`** (`event == "run_upsert"`, `run_id` a non-empty string, `payload` an
  object) **after the first hello**: updates the run's state. Every other line, including a
  `run_upsert` before any hello, is ignored. `gseq` is not required (schema 1 has none).

### Per-run state and the alert

For each `run_id` the helper keeps the last `status` and the last `repo_dir` it saw:

- `payload.status`, when a string, becomes the run's last status; otherwise the last status
  is unchanged.
- `payload.repo_dir`, when a non-empty string, becomes the run's last repo_dir; otherwise
  it is unchanged.

A **transition into escalated** is a `run_upsert` whose `payload.status` is the string
`"escalated"` while the run's previous last status was anything else (another string, or
none: a run first seen escalated is a transition, since `--from-now` means everything seen
is new). The state is updated before deciding, and the transition is decided against the
status held before this line.

On a transition, with the run's (updated) last repo_dir:

1. No repo_dir known: nothing printed.
2. `realpath(repo_dir)` in the registry: alert.
3. Not in the registry: the registry is read again; then alert if it is now registered,
   else nothing printed. (A `repo_dir` realpath cannot take — an embedded NUL — is never
   registered and triggers no read.)

The alert is one line, flushed at once, key order as shown:

```json
{"alert": {"run_id": "<run_id>", "root": "<root_path as brd printed it>", "project": "<name>", "state": "escalated"}}
```

So: consecutive `escalated` upserts of a run print once; a run seen `started` (or any other
status) after its escalation and then `escalated` again prints again (parent line 90-91:
"a run that is resumed and escalates again alerts again"); runs of unregistered repos print
nothing; a run whose project is registered while the helper runs alerts at its next
transition. Nothing other than alert lines and the final envelope is ever printed.

### Ending

| how it ends | last line | exit |
|---|---|---|
| any argument | `Usage` | 2 |
| `am` not on `PATH` | `AmMissing` | 1 |
| a hello with schema not 1 or 2 | `SchemaMismatch` | 1 |
| am exits 0, no refusal envelope | none | 0 |
| am exits 3 with a refusal envelope of type `StoreBusyError` | that envelope, unchanged | 1 |
| am exits 3 otherwise | `CorruptJournal`; message from the envelope's `error.message` when a non-empty string, else am's stderr, else `am watch exited 3.` | 1 |
| am exits non-zero other than 3 with a refusal envelope | that envelope, unchanged | 1 |
| am exits non-zero other than 3, no envelope | `HelperError`; am's stderr, else `am watch exited <code>.` | 1 |
| am exits 0 having printed a refusal envelope | that envelope, unchanged | 1 |
| SIGTERM or SIGINT | none | 0 |
| stdout closed (broken pipe) | none | 0 |
| any other unexpected exception | `HelperError`, `The runs alerts failed: <reason>` | 1 |

(The am-exit rows are runs-watch.py's `finish` unchanged.) Every envelope is
`{"ok": false, "error": {"type": T, "message": M}}` on one flushed line. On every path that
ends while am still runs, am is terminated (killed after 2 s) and reaped; am is never left
behind.

## Out of scope

- Everything the parent adds beyond the card: cursor argument and `{"cursor": N}` lines,
  `--since-seq`, `am events --escalations`, `head` requirement, `cursor_reset`/`store_id`
  handling, the `am runs --all-projects` seed, `dead` detection and its poll, `gseq` in the
  alert line, `--all-projects` spelling, terminal-status handling for cancel spellings.
- Sibling cards: `core/stores/RunAlertsService.qml`, the manifest `service` kind and entry
  points, `RunAlertsStore` dropping `notify.py`, the Runs screen switch label and caption,
  `docs/architecture.md` entries, `install.sh`. No file outside the two named here changes.
- Calling `notify.py`, reading `get-global-settings`, taking a run snapshot: the service's
  job.

## Tests

All in `tests/core/backend/runs/test_runs_alerts.py`. **Tier: hermetic Python
subprocess tests (pytest)** — the deliverable is a standalone executable whose contract is
its argv, stdout lines and exit code against external `am` and `brd`, so each test runs the
real script with `subprocess.Popen` against fake `am` and `brd` executables on a temp `PATH`
(`<tmp>/bin:/usr/bin:/bin`), temp `HOME` and `XDG_*`. No real `am`/`brd`, no network.
Every wait has a timeout.

Scaffolding, copied (not imported) from `test_runs_watch.py`:

- `FAKE_AM`: replays `$FAKE_AM_DIR/script.json` steps (`line` object, `raw` text, `sleep`
  seconds), then writes `stderr` and exits with `exit`; appends its argv to `calls.log` and
  writes its pid; an option to block forever after the steps (for signal tests).
- `FAKE_BRD`: appends each call's argv to a log; answers the Nth call from
  `responses[N]` (the last one repeats): `stdout` text, `exit` code; a missing `brd` is
  simply not installed.
- Lines from fixtures are built from `watch-hello.json` and a copy of a captured
  `run_upsert` from `watch-events.json` with `payload.status`/`repo_dir` edited; such
  edited and hand-made lines are labelled `synthetic:` in a comment, as test_runs_watch.py
  does.

Cases (each one test unless noted):

1. **argv:** am is called with exactly `watch --all --follow --from-now` (asserts
   `--from-now` present).
2. **no backlog alert:** a registered `run_upsert` `escalated` before the hello prints
   nothing; the same run escalating after the hello alerts once.
3. **hello accepted:** schema 1 fixture and schema 2 fixture each followed by an escalation
   of a registered run alert (parametrised).
4. **hello refused:** schema 3, missing, `"2"` string, `true` each give `SchemaMismatch`,
   exit 1, no alert (parametrised); a second hello with schema 3 after a good one also
   refuses.
5. **alert line:** exact JSON object and key set; `root` is `root_path` as brd printed it,
   `project` is `name`; matched by realpath (registry root given through a symlink).
6. **no duplicate:** three consecutive `escalated` upserts of one run print one alert.
7. **re-alert:** `escalated`, `started`, `escalated` prints two alerts.
8. **repo_dir carried:** `started` with repo_dir, then `escalated` without repo_dir alerts.
9. **unregistered ignored:** an escalation of an unregistered repo prints nothing; brd is
   called twice (start + one re-read).
10. **root learned:** brd's first answer lacks the root, its second has it; the escalation
    alerts and brd was called exactly twice.
11. **registered root does not re-read:** an escalation of a registered root leaves brd at
    one call; non-escalated upserts of unknown repos never call brd again.
12. **brd failing:** brd missing / exit 1 / garbage stdout at start: the helper keeps
    running, prints no alert for a registered-elsewhere repo, ends with exit 0 when am exits
    0 (parametrised); a failed re-read keeps the earlier registry (second answer exit 1,
    a registered run still alerts afterwards).
13. **AmMissing:** no `am` on `PATH`: `AmMissing`, exit 1, brd never called.
14. **Usage:** any argument gives `Usage`, exit 2, neither am nor brd called.
15. **am exit 0:** no envelope, exit 0.
16. **CorruptJournal:** am exit 3 with stderr; and with a refusal envelope (its message).
17. **StoreBusyError:** am exit 3 with a `StoreBusyError` envelope re-emits it, exit 1.
18. **HelperError:** am exit 2 with stderr, no envelope: `HelperError` with that stderr.
19. **signals:** SIGTERM and SIGINT to the helper (its own Popen pid) while fake am blocks:
    exit 0, no envelope, the recorded fake-am pid is gone afterwards (parametrised).
20. **ignored lines:** non-JSON text, a JSON array, a `run_upsert` with empty `run_id` or a
    non-object payload, other event kinds: no alert, no crash.
21. **flushed at once:** with fake am sleeping after an escalation, the alert line is read
    before am exits.

`tests/architecture` must still pass with the new file in place (no duplicated shared
helper).

---

# runs-alerts.py Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A long-lived helper `core/backend/runs/runs-alerts.py` that follows `am watch --all --follow --from-now` and prints one `{"alert": ...}` line for each transition into `escalated` of a run whose repo is a project registered with `brd`.

**Architecture:** One standalone Python 3 script modelled on `core/backend/runs/runs-watch.py`: a reader thread pumps am's stdout into a queue, a second thread collects stderr, the main loop checks hellos and feeds `run_upsert` lines to a small `Watcher` that keeps per-run last status/repo_dir and a registry read from `brd projects`. am's exit maps to the last line through `finish`, copied unchanged from runs-watch.py. Signals and a closed stdout end quietly through `guarded`/`quiet_exit`.

**Tech Stack:** Python 3 standard library only (`json`, `os`, `queue`, `shutil`, `signal`, `subprocess`, `sys`, `threading`); `common.json_line.emit`; pytest for hermetic subprocess tests with fake `am` and `brd` executables.

**Spec:** `docs/superpowers/specs/1-2-runs-alerts-py-a65dfeb3.md` (prepended above).

## Global Constraints

- Only two files are created: `core/backend/runs/runs-alerts.py` (mode 755, like its siblings) and `tests/core/backend/runs/test_runs_alerts.py`. No other file changes.
- Files under `core/backend/` are not `.qml`/`.js`. Never define `def emit(`, `def inside(`, `def write_atomic(`, `def split_frontmatter(`, `def frontmatter_of(` in the new files (`test_shared_python_helpers_are_defined_once`). Import `emit` with `sys.path.insert(0, <this dir>/..)` then `from common.json_line import emit`.
- Only documented `am` and `brd` commands, as argv lists, never a shell. am's database and on-disk layout are never read.
- am argv exactly `[<am>, "watch", "--all", "--follow", "--from-now"]`, stdin `/dev/null`, stdout and stderr piped, UTF-8 with `errors="replace"`.
- brd argv exactly `[<brd>, "projects"]`, stdin `/dev/null`, 30 s timeout.
- Usage envelope: `{"ok": false, "error": {"type": "Usage", "message": "usage: runs-alerts.py"}}`, exit 2.
- AmMissing message: `am is not installed.`; SchemaMismatch message: `am watch speaks schema <json of value>; this helper reads schema 1 or 2.`; unexpected exception: `The runs alerts failed: <reason>`.
- Alert line, key order exactly: `{"alert": {"run_id": R, "root": <root_path as brd printed it>, "project": <name>, "state": "escalated"}}`, flushed at once.
- Docstrings and comments state the contract only, no narrative. TDD: tests first.
- Tests: never `pkill`/`killall`/pattern kills; signal only recorded PIDs; every wait bounded by a timeout. Test PATH is `<tmp>/bin:/usr/bin:/bin` (the real `am`/`brd` live in `~/.local/bin`, never on it).
- Verification: `bash tests/run.sh` green; quick loop `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_alerts.py tests/architecture -q`.

## Review Focus

1. A run_upsert of an escalated run whose `payload.status` is `null` (not a string), followed by another `escalated`: the status is unchanged, so no second alert. (Task 2: `test_non_string_status_keeps_last_status`.)
2. A `repo_dir` containing an embedded NUL (`"\u0000"`): realpath raises `ValueError`; the helper must not die, must print nothing and must not re-read brd; later runs still alert. (Task 2: `test_repo_dir_with_nul_is_ignored`.)
3. A `brd projects` entry whose `root_path` contains a NUL, or which is not an object / lacks a string `name`: skipped, while the other entries still register. (Task 2: `test_bad_registry_entries_are_skipped`.)
4. Two `brd projects` entries naming the same directory (one through a symlink): the first wins for `root` and `project`. (Task 2: `test_first_registry_entry_wins`.)
5. Two runs escalating interleaved: per-run state is independent; each alerts once. (Task 2: `test_runs_are_tracked_separately`.)

---

### Task 1: The helper's shell — argv, am lookup and spawn, hello check, how it ends

**Files:**
- Create: `core/backend/runs/runs-alerts.py`
- Test: `tests/core/backend/runs/test_runs_alerts.py`

**Interfaces:**
- Consumes: `common.json_line.emit(payload, code=0)` from `core/backend/common/json_line.py` (prints `json.dumps(payload)`, returns `code`).
- Produces (for Task 2): in the script, `say(payload, code=0)`, `failure(kind, message, code=1)`, `check_hello(hello)` (raises `SchemaMismatch`), `spawn(am)`, `pump`, `collect`, `stop(proc)`, `stream(lines)`, `finish(code, refusal, stderr)`, `main(argv)`, `quiet_exit()`, `guarded(argv)`, constants `USAGE`, `IDLE_POLL`, `EOF`. In the test file, the scaffolding `FAKE_AM`, `FAKE_BRD`, `MISSING`, `fixture`, `events`, `RUN`, `NAME`, `write_exec`, `world` (keys `tmp`, `bin`, `am`, `brd`, `home`, `repo`; brd registers `repo` by default), `env_for`, `project`, `projects`, `set_brd`, `hello`, `ev`, `upsert`, `alert`, `pause`, `raw`, `set_script`, `run_helper`, `calls`, `brd_calls`, `start_helper`, `am_pid`, `wait_for_am`, `assert_gone`.

- [ ] **Step 1: Write the failing tests**

Create `tests/core/backend/runs/test_runs_alerts.py` with exactly this content:

```python
"""runs-alerts.py: `am watch --all --follow --from-now` turned into escalation alerts.

Hermetic: a fake `am` on a temp PATH replays FAKE_AM_DIR/script.json: a list of
steps (a JSON line, raw text, or a sleep), then a chosen stderr text and exit
code. A fake `brd` answers its Nth call from FAKE_BRD_DIR/responses.json (the
last answer repeats). The JSON lines are copies of the committed captures in
tests/fixtures/am/; a line no capture holds, or a capture copy with edited
fields, is labelled `synthetic:`. Both fakes log their argv to calls.log; the
fake am writes its pid to pid. HOME and XDG_* are temp. The real `am`, the real
`brd` and real data are never touched.
"""
import json
import os
import signal
import stat
import subprocess
import sys
import time

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "..")
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "runs-alerts.py")
USAGE = "usage: runs-alerts.py"

FAKE_AM = r'''#!/usr/bin/env python3
import json, os, sys, time
d = os.environ["FAKE_AM_DIR"]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\n")
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

FAKE_BRD = r'''#!/usr/bin/env python3
import json, os, sys
d = os.environ["FAKE_BRD_DIR"]
log = os.path.join(d, "calls.log")
n = 0
if os.path.exists(log):
    with open(log) as f:
        n = len(f.read().splitlines())
with open(log, "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\n")
with open(os.path.join(d, "responses.json")) as f:
    answers = json.load(f)
answer = answers[min(n, len(answers) - 1)]
sys.stdout.write(answer.get("stdout", ""))
sys.stdout.flush()
sys.exit(answer.get("exit", 0))
'''

MISSING = object()
FIXTURES = os.path.join(ROOT, "tests", "fixtures", "am")


def fixture(name):
    """A fresh json.load of tests/fixtures/am/<name>, so an edit never reaches
    another call."""
    with open(os.path.join(FIXTURES, name)) as f:
        return json.load(f)


def events():
    """A fresh copy of the captured journal lines, in gseq order."""
    return fixture("watch-events.json")["data"]["events"]


# The run of every captured journal line.
RUN = events()[0]["run_id"]
# The project name of every synthetic `brd projects` entry unless a test says otherwise.
NAME = "omarchy-project-manager"


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def project(root, name=NAME):
    """synthetic: one `brd projects` entry in the shape brd prints."""
    return {"id": 1, "name": name, "root_path": str(root), "created_at": "2026-10-01T00:00:00Z"}


def projects(*entries):
    """synthetic: a successful `brd projects` answer listing `entries`."""
    return {"stdout": json.dumps({"ok": True, "data": list(entries)}) + "\n", "exit": 0}


def set_brd(world, *answers):
    """brd's answers, in call order; the last one repeats."""
    (world["brd"] / "responses.json").write_text(json.dumps(list(answers)))


@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am and a fake brd, their dirs, a temp HOME and an
    existing project dir `repo`, which brd registers unless a test says otherwise."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "am", FAKE_AM)
    write_exec(bindir / "brd", FAKE_BRD)
    amdir = tmp_path / "am"
    amdir.mkdir()
    brddir = tmp_path / "brd"
    brddir.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    repo = tmp_path / "repo"
    repo.mkdir()
    w = {"tmp": tmp_path, "bin": bindir, "am": amdir, "brd": brddir, "home": home,
         "repo": repo}
    set_brd(w, projects(project(repo)))
    return w


def env_for(world, **extra):
    e = {
        "PATH": str(world["bin"]) + os.pathsep + "/usr/bin" + os.pathsep + "/bin",
        "HOME": str(world["home"]),
        "FAKE_AM_DIR": str(world["am"]),
        "FAKE_BRD_DIR": str(world["brd"]),
    }
    for name in ("XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        e[name] = str(world["tmp"] / name.lower())
    e.update(extra)
    return e


def hello(schema=2, **edits):
    """The --follow hello: the captured schema_2 line, or the captured schema_1
    line (no head) for schema=1. synthetic: any other schema value is set on a
    schema_2 copy, MISSING drops the key. synthetic: each of edits is set on
    the copy, MISSING drops the key."""
    lines = fixture("watch-hello.json")
    if type(schema) is int and schema in (1, 2):
        line = lines["schema_%d" % schema]
    else:
        line = lines["schema_2"]
        edits = {"schema": schema, **edits}
    for key, value in edits.items():
        if value is MISSING:
            line.pop(key, None)
        else:
            line[key] = value
    return {"line": line}


def ev(event):
    """The first captured journal line whose event is `event`."""
    return {"line": next(e for e in events() if e["event"] == event)}


def upsert(status, repo_dir=MISSING, run_id=RUN):
    """synthetic: a copy of the captured run_upsert with run_id set, and
    payload.status and payload.repo_dir set to the given values (a path is
    passed as its text); MISSING drops the key."""
    line = ev("run_upsert")["line"]
    line["run_id"] = run_id
    for key, value in (("status", status), ("repo_dir", repo_dir)):
        if value is MISSING:
            line["payload"].pop(key, None)
        else:
            line["payload"][key] = os.fspath(value) if isinstance(value, os.PathLike) else value
    return {"line": line}


def alert(root, run_id=RUN, name=NAME):
    """The helper's alert line for `run_id` under the registered `root`."""
    return {"alert": {"run_id": run_id, "root": str(root), "project": name,
                      "state": "escalated"}}


def pause(seconds):
    return {"sleep": seconds}


def raw(text):
    return {"raw": text}


def set_script(world, steps, exit=0, stderr=""):
    (world["am"] / "script.json").write_text(
        json.dumps({"steps": steps, "exit": exit, "stderr": stderr}))


def run_helper(world, args=(), timeout=30, **extra):
    """Run the helper until it exits. Every stdout line must be JSON. Returns
    (exit code, parsed lines, stderr)."""
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True,
                       env=env_for(world, **extra), timeout=timeout)
    return p.returncode, [json.loads(line) for line in p.stdout.splitlines()], p.stderr


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def brd_calls(world):
    log = world["brd"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def start_helper(world):
    return subprocess.Popen([sys.executable, SCRIPT], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                            env=env_for(world))


def am_pid(world):
    return int((world["am"] / "pid").read_text())


def wait_for_am(world, within=10.0):
    """The fake am's pid, once it has started."""
    end = time.monotonic() + within
    while time.monotonic() < end:
        try:
            return am_pid(world)
        except (FileNotFoundError, ValueError):
            time.sleep(0.05)
    pytest.fail("am watch never started")


def assert_gone(pid, within=5.0):
    """The fake am process no longer exists (no orphaned `am watch`)."""
    end = time.monotonic() + within
    while time.monotonic() < end:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    os.kill(pid, signal.SIGKILL)
    pytest.fail("am watch was left running after the helper exited")


# --- the lines are capture copies -----------------------------------------------

def test_lines_are_capture_copies():
    captured = events()
    assert ev("run_upsert")["line"] == captured[1]
    assert captured[1]["payload"]["status"] == "started"
    assert captured[1]["payload"]["repo_dir"] == "/home/user/Code/omarchy-project-manager"
    assert {e["run_id"] for e in captured} == {RUN}
    assert hello(1) == {"line": fixture("watch-hello.json")["schema_1"]}
    assert "head" not in hello(1)["line"]
    assert hello() == hello(2) == {"line": fixture("watch-hello.json")["schema_2"]}


# --- argv, Usage, am missing ----------------------------------------------------

def test_argv(world):
    set_script(world, [hello()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == []
    # argv list, no shell: the fake am sees exactly these arguments.
    assert calls(world) == [["watch", "--all", "--follow", "--from-now"]]
    assert "--from-now" in calls(world)[0]


@pytest.mark.parametrize("args", [["x"], ["--from-now"], [""], ["/some/root"], ["a", "b"]],
                         ids=["word", "flag", "empty", "root", "two"])
def test_usage(world, args):
    set_script(world, [hello()])
    code, lines, _ = run_helper(world, args)
    assert code == 2
    assert lines == [{"ok": False, "error": {"type": "Usage", "message": USAGE}}]
    assert calls(world) == []  # am never spawned
    assert brd_calls(world) == []  # brd never run


def test_usage_before_am_lookup(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, lines, _ = run_helper(world, ["x"], PATH=str(empty))
    assert code == 2
    assert lines == [{"ok": False, "error": {"type": "Usage", "message": USAGE}}]


def test_am_missing(world):
    only_brd = world["tmp"] / "only-brd"
    only_brd.mkdir()
    write_exec(only_brd / "brd", FAKE_BRD)
    code, lines, _ = run_helper(world, PATH=str(only_brd))
    assert code == 1
    assert lines == [{"ok": False, "error": {"type": "AmMissing",
                                             "message": "am is not installed."}}]
    assert brd_calls(world) == []  # brd is not run when am is missing


# --- the hello line ---------------------------------------------------------------

def test_clean_exit_zero(world):
    set_script(world, [hello(), ev("phase_upsert")])
    code, lines, err = run_helper(world)
    assert code == 0
    assert lines == []
    assert "Traceback" not in err


@pytest.mark.parametrize("schema", [1, 2], ids=["schema-1", "schema-2"])
def test_hello_accepted_prints_nothing(world, schema):
    set_script(world, [hello(schema)])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == []


def assert_schema_mismatch(world, lines, began, received):
    assert time.monotonic() - began < 5
    assert len(lines) == 1, lines
    assert lines[0]["ok"] is False, lines
    assert lines[0]["error"]["type"] == "SchemaMismatch", lines
    assert lines[0]["error"]["message"] == (
        "am watch speaks schema " + received + "; this helper reads schema 1 or 2.")
    assert_gone(am_pid(world))  # am was terminated, not left streaming


@pytest.mark.parametrize("schema", [3, MISSING, "2", True],
                         ids=["synthetic: three", "synthetic: missing",
                              "synthetic: string-two", "synthetic: true"])
def test_schema_mismatch(world, schema):
    set_script(world, [hello(schema), pause(8)])
    began = time.monotonic()
    code, lines, _ = run_helper(world)
    assert code == 1
    assert_schema_mismatch(world, lines, began,
                           json.dumps(None if schema is MISSING else schema))


def test_second_hello_is_checked(world):
    set_script(world, [hello(2), hello(3), pause(8)])
    began = time.monotonic()
    code, lines, _ = run_helper(world)
    assert code == 1
    assert_schema_mismatch(world, lines, began, "3")


# --- how am ends -------------------------------------------------------------------

def test_exit_3_corrupt_journal(world):
    # synthetic: am's stderr text for a corrupt journal.
    set_script(world, [hello()], exit=3,
               stderr="am watch: journal line 4 of run r1 is not JSON\n")
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [{"ok": False, "error": {
        "type": "CorruptJournal",
        "message": "am watch: journal line 4 of run r1 is not JSON"}}]


def test_exit_3_without_stderr(world):
    set_script(world, [hello()], exit=3)
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [{"ok": False, "error": {"type": "CorruptJournal",
                                             "message": "am watch exited 3."}}]


def test_refusal_exit_3_is_corrupt_journal(world):
    # synthetic: an am refusal envelope; no capture holds one.
    envelope = {"error": {"message": "run r1: journal line 2 is not JSON",
                          "type": "CorruptJournalError"}, "ok": False}
    set_script(world, [{"line": envelope}], exit=3, stderr="ignored\n")
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [{"ok": False, "error": {"type": "CorruptJournal",
                                             "message": "run r1: journal line 2 is not JSON"}}]


def test_refusal_exit_3_empty_message_uses_stderr(world):
    # synthetic: an am refusal envelope with an empty message.
    envelope = {"error": {"message": "", "type": "CorruptJournalError"}, "ok": False}
    set_script(world, [{"line": envelope}], exit=3, stderr="bad journal\n")
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [{"ok": False, "error": {"type": "CorruptJournal",
                                             "message": "bad journal"}}]


# synthetic: am's StoreBusyError envelope; no capture holds one.
STORE_BUSY = {"error": {"message": "the am store is busy; try again",
                        "type": "StoreBusyError"}, "ok": False}


def test_refusal_store_busy_is_reemitted(world):
    set_script(world, [hello(), {"line": STORE_BUSY}], exit=3)
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [STORE_BUSY]


def test_other_exit_is_helper_error(world):
    # synthetic: am's stderr text for a crash.
    set_script(world, [hello()], exit=2, stderr="boom\n")
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [{"ok": False, "error": {"type": "HelperError", "message": "boom"}}]


def test_other_exit_without_stderr(world):
    set_script(world, [hello()], exit=2)
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [{"ok": False, "error": {"type": "HelperError",
                                             "message": "am watch exited 2."}}]


@pytest.mark.parametrize("exit", [0, 1], ids=["exit-0", "exit-1"])
def test_refusal_other_exit_is_reemitted(world, exit):
    # synthetic: an am refusal envelope; no capture holds one.
    envelope = {"error": {"message": "something else", "type": "OddError"}, "ok": False}
    set_script(world, [hello(), {"line": envelope}], exit=exit)
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [envelope]


# --- stopping: signals -------------------------------------------------------------

@pytest.mark.parametrize("sig", [signal.SIGTERM, signal.SIGINT], ids=["SIGTERM", "SIGINT"])
def test_signal_stops_am_and_exits_zero(world, sig):
    set_script(world, [hello(), pause(30)])
    p = start_helper(world)
    try:
        pid = wait_for_am(world)  # sync point: the helper has spawned am
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
    assert out == ""  # no envelope
    assert "Traceback" not in err
    assert_gone(pid)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_alerts.py -q`
Expected: FAIL — every test except `test_lines_are_capture_copies` fails (python3 reports `can't open file '.../runs-alerts.py'`, exit code 2, so the code/line assertions fail; the signal tests fail with "am watch never started").

- [ ] **Step 3: Write the helper**

Create `core/backend/runs/runs-alerts.py` with exactly this content:

```python
#!/usr/bin/env python3
"""Print an alert when a run of a registered project escalates, from
`am watch --all --follow --from-now`.

    runs-alerts.py

Takes no argument; any argument is a Usage error (exit 2) and neither am nor
brd is looked up or run. Long-lived. Spawns `am watch --all --follow
--from-now` as an argv list, never a shell. Prints one JSON object per line,
flushed at once:
  {"ok": false, "error": {"type", "message"}}
      then exit 1, with type SchemaMismatch, CorruptJournal (am exited 3),
      HelperError or AmMissing (Usage exits 2). An am refusal envelope is
      re-emitted unchanged when am exits other than 3, or when its type is
      StoreBusyError.
Every hello line (event "watch") must carry an integer schema of 1 or 2, else
SchemaMismatch. Every other line is ignored. am exiting 0, SIGINT, SIGTERM or
a closed stdout end the helper with exit 0. Only the `am` command is used;
am's database and on-disk layout are never read.
"""
import json
import os
import queue
import shutil
import signal
import subprocess
import sys
import threading

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-alerts.py"
IDLE_POLL = 1.0  # seconds; the longest the main loop blocks with nothing pending
EOF = object()


class SchemaMismatch(Exception):
    """A hello line whose schema is not the integer 1 or 2."""


class Stop(Exception):
    """SIGINT or SIGTERM: the service (or a user) is done with these alerts."""


def on_signal(signum, frame):
    raise Stop()


def say(payload, code=0):
    """emit() one line and flush it now: stdout is a pipe, so it is block-buffered."""
    emit(payload)
    sys.stdout.flush()
    return code


def failure(kind, message, code=1):
    return say({"ok": False, "error": {"type": kind, "message": message}}, code)


def check_hello(hello):
    """Raises SchemaMismatch unless the hello line's schema is the integer 1 or 2."""
    schema = hello.get("schema")
    if not (type(schema) is int and schema in (1, 2)):
        raise SchemaMismatch("am watch speaks schema " + json.dumps(schema)
                             + "; this helper reads schema 1 or 2.")


def spawn(am):
    return subprocess.Popen([am, "watch", "--all", "--follow", "--from-now"],
                            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, encoding="utf-8",
                            errors="replace")


def pump(stream, sink):
    """Reader thread: every line am prints, then EOF."""
    for raw in stream:
        sink.put(raw)
    sink.put(EOF)


def collect(stream, parts):
    """Reader thread: am's whole stderr, so a chatty am never blocks on a full pipe."""
    parts.append(stream.read())


def stop(proc):
    """Terminate am if it is still running, and reap it."""
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def stream(lines):
    """Read am's stream until it ends. Every hello line (event "watch") is
    checked; every other line is ignored. Returns am's refusal envelope (the
    last line with an "ok" key) if it printed one, else None. Raises
    SchemaMismatch."""
    refusal = None
    while True:
        try:
            raw = lines.get(timeout=IDLE_POLL)
        except queue.Empty:
            continue
        if raw is EOF:
            return refusal
        try:
            line = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(line, dict):
            continue
        if "ok" in line:
            refusal = line
            continue
        if line.get("event") == "watch":
            check_hello(line)


def finish(code, refusal, stderr):
    """Print the last line, if any, for how am ended; return the helper's exit code."""
    if refusal is not None:
        error = refusal.get("error")
        if code != 3 or (isinstance(error, dict) and error.get("type") == "StoreBusyError"):
            return say(refusal, 1)
        message = error.get("message") if isinstance(error, dict) else None
        if not (isinstance(message, str) and message):
            message = stderr or "am watch refused with exit 3."
        return failure("CorruptJournal", message)
    if code == 0:
        return 0
    if code == 3:
        return failure("CorruptJournal", stderr or "am watch exited 3.")
    return failure("HelperError", stderr or "am watch exited " + str(code) + ".")


def main(argv):
    if argv:
        return failure("Usage", USAGE, 2)
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    proc = spawn(am)
    lines, err = queue.Queue(), []
    threading.Thread(target=pump, args=(proc.stdout, lines), daemon=True).start()
    err_reader = threading.Thread(target=collect, args=(proc.stderr, err), daemon=True)
    err_reader.start()
    try:
        try:
            refusal = stream(lines)
        except SchemaMismatch as e:
            return failure("SchemaMismatch", str(e))
        code = proc.wait()
        err_reader.join(timeout=2)
    finally:
        stop(proc)  # no-op once am has exited; terminates it on every other path
    return finish(code, refusal, "".join(err).strip())


def quiet_exit():
    """Ended by a signal or a closed stdout: exit 0 without a traceback. stdout
    is pointed at /dev/null so the interpreter's final flush cannot raise."""
    try:
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
    except OSError:
        pass
    return 0


def guarded(argv):
    """SIGINT, SIGTERM and a closed stdout end the helper quietly with exit 0
    (main's finally has already stopped am). Any other unexpected exception
    still ends with one HelperError line."""
    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)  # explicit: SIGINT may be inherited as ignored
    try:
        return main(argv)
    except (Stop, KeyboardInterrupt, BrokenPipeError):
        return quiet_exit()
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        try:
            return failure("HelperError", "The runs alerts failed: " + reason)
        except BrokenPipeError:
            return quiet_exit()


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
```

Then make it executable like its siblings:

```bash
chmod 755 core/backend/runs/runs-alerts.py
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_alerts.py tests/architecture -q`
Expected: PASS (all tests in both).

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-alerts.py tests/core/backend/runs/test_runs_alerts.py
git commit -m "feat(runs): runs-alerts.py follows am watch --from-now, checks hellos and maps am's exit"
```

---

### Task 2: The registry and the escalation alert

**Files:**
- Modify: `core/backend/runs/runs-alerts.py` (whole file replaced below)
- Test: `tests/core/backend/runs/test_runs_alerts.py` (tests appended at the end)

**Interfaces:**
- Consumes (from Task 1): the script's `say`, `failure`, `check_hello`, `spawn`, `pump`, `collect`, `stop`, `finish`, `quiet_exit`, `guarded`, `USAGE`, `IDLE_POLL`, `EOF`; the test file's `world` (brd registers `world["repo"]` with name `NAME` by default), `set_brd`, `projects`, `project`, `hello`, `ev`, `upsert(status, repo_dir=MISSING, run_id=RUN)`, `alert(root, run_id=RUN, name=NAME)`, `pause`, `raw`, `set_script`, `run_helper`, `brd_calls`, `start_helper`, `am_pid`, `assert_gone`, `MISSING`, `RUN`, `NAME`.
- Produces: in the script, `BRD_TIMEOUT = 30`, `real(path) -> str | None`, `read_registry() -> dict[str, tuple[str, str]] | None`, `upsert(line) -> tuple[str, dict] | None`, class `Watcher(registry)` with `see(run_id, payload) -> None`, `stream(lines, watcher)`. Nothing later depends on them.

- [ ] **Step 1: Write the failing tests**

Append exactly this to the end of `tests/core/backend/runs/test_runs_alerts.py`:

```python


# --- the alert ---------------------------------------------------------------------

def test_no_backlog_alert(world):
    # synthetic: an escalated upsert before the hello is ignored, state and all.
    set_script(world, [upsert("escalated", world["repo"]), hello(),
                       upsert("escalated", world["repo"])])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"])]


@pytest.mark.parametrize("schema", [1, 2], ids=["schema-1", "schema-2"])
def test_hello_accepted_then_alert(world, schema):
    set_script(world, [hello(schema), upsert("escalated", world["repo"])])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"])]


def test_alert_line_shape_and_realpath_match(world):
    real_dir = world["tmp"] / "real"
    real_dir.mkdir()
    link = world["tmp"] / "link"
    link.symlink_to(real_dir)
    set_brd(world, projects(project(link, name="proj")))
    # synthetic: the run's repo_dir is the real directory, brd printed the link.
    set_script(world, [hello(), upsert("escalated", real_dir)])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [{"alert": {"run_id": RUN, "root": str(link), "project": "proj",
                                "state": "escalated"}}]
    assert list(lines[0]) == ["alert"]
    assert list(lines[0]["alert"]) == ["run_id", "root", "project", "state"]


def test_no_duplicate(world):
    set_script(world, [hello()] + [upsert("escalated", world["repo"])] * 3)
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"])]


def test_re_alert_after_resume(world):
    set_script(world, [hello(), upsert("escalated", world["repo"]),
                       upsert("started", world["repo"]), upsert("escalated", world["repo"])])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"])] * 2


def test_repo_dir_carried(world):
    set_script(world, [hello(), upsert("started", world["repo"]), upsert("escalated")])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"])]


def test_no_repo_dir_no_alert(world):
    set_script(world, [hello(), upsert("escalated"), upsert("escalated", "")])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == []
    assert brd_calls(world) == [["projects"]]


# --- the registry ------------------------------------------------------------------

def test_unregistered_is_ignored(world):
    set_script(world, [hello(), upsert("escalated", world["tmp"] / "elsewhere")])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == []
    assert brd_calls(world) == [["projects"], ["projects"]]  # start + one re-read


def test_root_learned(world):
    set_brd(world, projects(), projects(project(world["repo"])))
    set_script(world, [hello(), upsert("escalated", world["repo"])])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"])]
    assert brd_calls(world) == [["projects"], ["projects"]]


def test_registered_root_does_not_re_read(world):
    set_script(world, [hello(),
                       upsert("started", world["tmp"] / "a"),
                       upsert("started", world["tmp"] / "b", run_id="r2"),
                       upsert("escalated", world["repo"])])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"])]
    assert brd_calls(world) == [["projects"]]


BRD_FAILURES = ["missing", "exit-1", "garbage", "ok-false", "data-not-list"]


@pytest.mark.parametrize("failure", BRD_FAILURES)
def test_brd_failing_at_start(world, failure):
    registering = projects(project(world["repo"]))["stdout"]
    answers = {
        "exit-1": {"stdout": registering, "exit": 1},
        "garbage": {"stdout": "not json\n", "exit": 0},
        # synthetic: brd refusal envelope.
        "ok-false": {"stdout": json.dumps({"ok": False, "error": {"type": "X",
                                                                   "message": "no"}}) + "\n"},
        "data-not-list": {"stdout": json.dumps({"ok": True, "data": {}}) + "\n"},
    }
    if failure == "missing":
        os.unlink(world["bin"] / "brd")
    else:
        set_brd(world, answers[failure])
    set_script(world, [hello(), upsert("escalated", world["repo"])])
    code, lines, err = run_helper(world)
    assert code == 0, err
    assert lines == []
    assert "Traceback" not in err
    assert brd_calls(world) == ([] if failure == "missing" else [["projects"], ["projects"]])


def test_failed_re_read_keeps_registry(world):
    set_brd(world, projects(project(world["repo"])), {"stdout": "", "exit": 1})
    set_script(world, [hello(),
                       upsert("escalated", world["tmp"] / "elsewhere"),
                       upsert("escalated", world["repo"], run_id="r2")])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"], run_id="r2")]
    assert brd_calls(world) == [["projects"], ["projects"]]


# --- review focus ------------------------------------------------------------------

def test_non_string_status_keeps_last_status(world):
    set_script(world, [hello(), upsert("escalated", world["repo"]),
                       upsert(None, world["repo"]), upsert("escalated", world["repo"])])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"])]


def test_repo_dir_with_nul_is_ignored(world):
    # synthetic: a repo_dir realpath cannot take.
    set_script(world, [hello(), upsert("escalated", str(world["repo"]) + "\u0000x"),
                       upsert("escalated", world["repo"], run_id="r2")])
    code, lines, err = run_helper(world)
    assert code == 0, err
    assert lines == [alert(world["repo"], run_id="r2")]
    assert brd_calls(world) == [["projects"]]  # no re-read for the NUL path


def test_bad_registry_entries_are_skipped(world):
    good = project(world["repo"], name="good")
    nameless = project(world["tmp"] / "nameless")
    del nameless["name"]
    set_brd(world, projects("not an object", project(str(world["tmp"]) + "\u0000x"),
                            {**project(""), "root_path": ""}, nameless,
                            {**project(world["tmp"] / "n"), "root_path": 5}, good))
    set_script(world, [hello(), upsert("escalated", world["repo"])])
    code, lines, err = run_helper(world)
    assert code == 0, err
    assert lines == [alert(world["repo"], name="good")]


def test_first_registry_entry_wins(world):
    link = world["tmp"] / "link"
    link.symlink_to(world["repo"])
    set_brd(world, projects(project(link, name="first"), project(world["repo"], name="second")))
    set_script(world, [hello(), upsert("escalated", world["repo"])])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(link, name="first")]


def test_runs_are_tracked_separately(world):
    set_script(world, [hello(),
                       upsert("escalated", world["repo"], run_id="r1"),
                       upsert("escalated", world["repo"], run_id="r2"),
                       upsert("escalated", world["repo"], run_id="r1"),
                       upsert("escalated", world["repo"], run_id="r2")])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [alert(world["repo"], run_id="r1"), alert(world["repo"], run_id="r2")]


# --- ignored lines -----------------------------------------------------------------

def test_ignored_lines(world):
    empty_run = upsert("escalated", world["repo"], run_id="")
    bad_payload = upsert("escalated", world["repo"])
    bad_payload["line"]["payload"] = "escalated"
    # synthetic: another event kind carrying an escalated status and a repo_dir.
    phase = ev("phase_upsert")
    phase["line"]["payload"] = {"status": "escalated", "repo_dir": str(world["repo"])}
    set_script(world, [hello(), raw("not json"), raw("[1, 2]"), raw('"text"'), empty_run,
                       bad_payload, phase, upsert("escalated", world["repo"])])
    code, lines, err = run_helper(world)
    assert code == 0, err
    assert "Traceback" not in err
    assert lines == [alert(world["repo"])]
    assert brd_calls(world) == [["projects"]]


# --- flushing and a closed stdout --------------------------------------------------

def test_alert_flushed_at_once(world):
    set_script(world, [hello(), upsert("escalated", world["repo"]), pause(30)])
    p = start_helper(world)
    try:
        began = time.monotonic()
        line = p.stdout.readline()
        assert time.monotonic() - began < 10  # read while am still runs
        assert json.loads(line) == alert(world["repo"])
        pid = am_pid(world)
        p.send_signal(signal.SIGTERM)
        code = p.wait(timeout=10)
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
    p.stdout.close()
    p.stderr.close()
    assert code == 0
    assert_gone(pid)


def test_closed_stdout_exits_zero(world):
    set_script(world, [hello(), pause(0.6), upsert("escalated", world["repo"]), pause(30)])
    p = start_helper(world)
    p.stdout.close()  # the reader goes away before the alert
    try:
        code = p.wait(timeout=10)
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
    err = p.stderr.read()
    p.stderr.close()
    assert code == 0, err
    assert "Traceback" not in err
    assert_gone(am_pid(world))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_alerts.py -q`
Expected: FAIL — the alert tests fail with `assert [] == [{'alert': ...}]`, the brd-call tests with `assert [] == [['projects'], ...]`, and `test_alert_flushed_at_once` / `test_closed_stdout_exits_zero` fail (no alert line within 10 s; helper still running at the 10 s wait). Task 1's tests still pass.

- [ ] **Step 3: Replace the helper with the full implementation**

Replace the whole of `core/backend/runs/runs-alerts.py` with exactly this content (it keeps mode 755):

```python
#!/usr/bin/env python3
"""Print an alert when a run of a registered project escalates, from
`am watch --all --follow --from-now`.

    runs-alerts.py

Takes no argument; any argument is a Usage error (exit 2) and neither am nor
brd is looked up or run. Long-lived. Looks up `am` (AmMissing when it is not on
PATH), reads the registry, then spawns `am watch --all --follow --from-now` as
an argv list, never a shell. Prints one JSON object per line, flushed at once:
  {"alert": {"run_id": R, "root": P, "project": N, "state": "escalated"}}
      for each transition into escalated of a run whose last repo_dir names
      (realpath) a registered root; P is that root as brd printed it, N its
      project name.
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
nothing. am exiting 0, SIGINT, SIGTERM or a closed stdout end the helper with
exit 0. Only the `am` and `brd` commands are used; am's database and on-disk
layout are never read.
"""
import json
import os
import queue
import shutil
import signal
import subprocess
import sys
import threading

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-alerts.py"
IDLE_POLL = 1.0  # seconds; the longest the main loop blocks with nothing pending
BRD_TIMEOUT = 30  # seconds; the longest one `brd projects` may take
EOF = object()


class SchemaMismatch(Exception):
    """A hello line whose schema is not the integer 1 or 2."""


class Stop(Exception):
    """SIGINT or SIGTERM: the service (or a user) is done with these alerts."""


def on_signal(signum, frame):
    raise Stop()


def say(payload, code=0):
    """emit() one line and flush it now: stdout is a pipe, so it is block-buffered."""
    emit(payload)
    sys.stdout.flush()
    return code


def failure(kind, message, code=1):
    return say({"ok": False, "error": {"type": kind, "message": message}}, code)


def check_hello(hello):
    """Raises SchemaMismatch unless the hello line's schema is the integer 1 or 2."""
    schema = hello.get("schema")
    if not (type(schema) is int and schema in (1, 2)):
        raise SchemaMismatch("am watch speaks schema " + json.dumps(schema)
                             + "; this helper reads schema 1 or 2.")


def real(path):
    """realpath of `path`, or None when realpath cannot take it (an embedded NUL)."""
    try:
        return os.path.realpath(path)
    except (ValueError, OSError):
        return None


def read_registry():
    """The registry from `brd projects`: realpath(root_path) -> (root_path,
    name) for each entry that is an object with a non-empty string root_path
    realpath can take and a string name, the first entry winning. None when
    the read fails."""
    brd = shutil.which("brd")
    if brd is None:
        return None
    try:
        done = subprocess.run([brd, "projects"], stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, encoding="utf-8",
                              errors="replace", timeout=BRD_TIMEOUT)
    except (subprocess.TimeoutExpired, OSError):
        return None
    if done.returncode != 0:
        return None
    try:
        reply = json.loads(done.stdout)
    except ValueError:
        return None
    if not (isinstance(reply, dict) and reply.get("ok") is True
            and isinstance(reply.get("data"), list)):
        return None
    registry = {}
    for entry in reply["data"]:
        if not isinstance(entry, dict):
            continue
        root, name = entry.get("root_path"), entry.get("name")
        if not (isinstance(root, str) and root and isinstance(name, str)):
            continue
        key = real(root)
        if key is not None and key not in registry:
            registry[key] = (root, name)
    return registry


def upsert(line):
    """(run id, payload) for a parsed line that is a run_upsert with a non-empty
    string run_id and an object payload, else None."""
    run_id, payload = line.get("run_id"), line.get("payload")
    if line.get("event") != "run_upsert":
        return None
    if not (isinstance(run_id, str) and run_id and isinstance(payload, dict)):
        return None
    return run_id, payload


class Watcher:
    """Each run's last status and last repo_dir, and the registry
    (realpath -> (root_path, name))."""

    def __init__(self, registry):
        self.registry = registry
        self.status = {}
        self.repo_dir = {}

    def see(self, run_id, payload):
        """Record a run_upsert's payload. On a transition into escalated, print
        the alert when the run's last repo_dir is registered, reading the
        registry again first when it is not (never for a repo_dir realpath
        cannot take)."""
        before = self.status.get(run_id)
        status, repo_dir = payload.get("status"), payload.get("repo_dir")
        if isinstance(status, str):
            self.status[run_id] = status
        if isinstance(repo_dir, str) and repo_dir:
            self.repo_dir[run_id] = repo_dir
        if status != "escalated" or before == "escalated":
            return
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


def spawn(am):
    return subprocess.Popen([am, "watch", "--all", "--follow", "--from-now"],
                            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, encoding="utf-8",
                            errors="replace")


def pump(stream, sink):
    """Reader thread: every line am prints, then EOF."""
    for raw in stream:
        sink.put(raw)
    sink.put(EOF)


def collect(stream, parts):
    """Reader thread: am's whole stderr, so a chatty am never blocks on a full pipe."""
    parts.append(stream.read())


def stop(proc):
    """Terminate am if it is still running, and reap it."""
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def stream(lines, watcher):
    """Read am's stream until it ends, line by line as it arrives. Every hello
    line (event "watch") is checked; each run_upsert after the first hello goes
    to `watcher`; every other line is ignored. Returns am's refusal envelope
    (the last line with an "ok" key) if it printed one, else None. Raises
    SchemaMismatch."""
    refusal, greeted = None, False
    while True:
        try:
            raw = lines.get(timeout=IDLE_POLL)
        except queue.Empty:
            continue
        if raw is EOF:
            return refusal
        try:
            line = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(line, dict):
            continue
        if "ok" in line:
            refusal = line
            continue
        if line.get("event") == "watch":
            check_hello(line)
            greeted = True
            continue
        hit = upsert(line)
        if greeted and hit is not None:
            watcher.see(*hit)


def finish(code, refusal, stderr):
    """Print the last line, if any, for how am ended; return the helper's exit code."""
    if refusal is not None:
        error = refusal.get("error")
        if code != 3 or (isinstance(error, dict) and error.get("type") == "StoreBusyError"):
            return say(refusal, 1)
        message = error.get("message") if isinstance(error, dict) else None
        if not (isinstance(message, str) and message):
            message = stderr or "am watch refused with exit 3."
        return failure("CorruptJournal", message)
    if code == 0:
        return 0
    if code == 3:
        return failure("CorruptJournal", stderr or "am watch exited 3.")
    return failure("HelperError", stderr or "am watch exited " + str(code) + ".")


def main(argv):
    if argv:
        return failure("Usage", USAGE, 2)
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    watcher = Watcher(read_registry() or {})
    proc = spawn(am)
    lines, err = queue.Queue(), []
    threading.Thread(target=pump, args=(proc.stdout, lines), daemon=True).start()
    err_reader = threading.Thread(target=collect, args=(proc.stderr, err), daemon=True)
    err_reader.start()
    try:
        try:
            refusal = stream(lines, watcher)
        except SchemaMismatch as e:
            return failure("SchemaMismatch", str(e))
        code = proc.wait()
        err_reader.join(timeout=2)
    finally:
        stop(proc)  # no-op once am has exited; terminates it on every other path
    return finish(code, refusal, "".join(err).strip())


def quiet_exit():
    """Ended by a signal or a closed stdout: exit 0 without a traceback. stdout
    is pointed at /dev/null so the interpreter's final flush cannot raise."""
    try:
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
    except OSError:
        pass
    return 0


def guarded(argv):
    """SIGINT, SIGTERM and a closed stdout end the helper quietly with exit 0
    (main's finally has already stopped am). Any other unexpected exception
    still ends with one HelperError line."""
    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)  # explicit: SIGINT may be inherited as ignored
    try:
        return main(argv)
    except (Stop, KeyboardInterrupt, BrokenPipeError):
        return quiet_exit()
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        try:
            return failure("HelperError", "The runs alerts failed: " + reason)
        except BrokenPipeError:
            return quiet_exit()


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_alerts.py tests/architecture -q`
Expected: PASS (all tests in both).

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest reports no failures and the script exits 0 (every QML `Totals` line shows 0 failed).

- [ ] **Step 6: Commit**

```bash
git add core/backend/runs/runs-alerts.py tests/core/backend/runs/test_runs_alerts.py
git commit -m "feat(runs): runs-alerts.py alerts escalations of registered projects"
```
<!-- task-pipeline: validated -->
