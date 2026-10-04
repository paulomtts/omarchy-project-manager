# 2.3 notify.py: a desktop alert through notify-send (card 77a4b21f)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-controls-design.md` (S2):
"Alerts" item 2 (lines 119-123) and "Testing" (lines 155-156). Parent story
90acc3d7. Blocked by a36aac36 (2.2 `viewer-state.py` run settings), which is on
this branch and stores `notifyOnEscalation`; nothing in it is touched.

## Inherited constraints

- "`core/backend/runs/notify.py` calls `notify-send` with the run's title and
  reason, and does nothing if `notify-send` is missing" (parent lines 120-122).
- "Backend pytest ... `notify.py` with and without `notify-send`" (parent lines
  155-156).
- Desktop alerts are off by default and gated by "Notify on escalation"
  (parent lines 119-120). The gate is the **caller's** job: `notify.py` never
  reads `viewer-state.py` or `notifyOnEscalation`.
- Helper-script convention (`docs/architecture.md` lines 190-192):
  `core/backend/<domain>/name.py`, one JSON line on stdout, `sys.path` insert of
  its parent for `common`, no duplicated helpers, pytest under
  `tests/core/backend/<domain>/`.
- Backend code imports only the Python stdlib and `core/backend/common`
  (`docs/architecture.md` line 12). `emit` comes from `common.json_line` and is
  never redefined (`docs/architecture.md` lines 174-178;
  `tests/architecture/test_layers.py` `DUPLICATED_PY`).
- Verification: `bash tests/run.sh` green (card).

## Starting point

- `core/backend/runs/` holds `run-control.py`, `runs-logs.py`,
  `runs-snapshot.py`, `runs-watch.py`. `notify.py` does not exist.
- `core/backend/runs/run-control.py` lines 1-60 and 169-182 are the pattern to
  copy: a module docstring listing usage and every output line; a `USAGE`
  constant; `sys.path.insert(0, ...dirname(abspath(__file__)), "..")` then
  `from common.json_line import emit  # noqa: E402`; a `failure(kind, message,
  code=0)` envelope builder; `shutil.which` for the PATH lookup; subprocess as an
  argv list (no shell, `stdin=DEVNULL`, a timeout); a `guarded(argv)` wrapper
  that turns any unexpected exception into a `HelperError` line.
- `tests/core/backend/runs/test_run_control.py` lines 1-100 is the test pattern:
  a stub executable written into a temp `bin` dir (`write_exec`), argv appended
  to a `calls.log`, a temp `HOME`, the script run as
  `[sys.executable, SCRIPT, ...]` with an explicit `env`, and a `run()` that
  asserts stdout is exactly one JSON line.
- The real `notify-send` is at `/usr/bin/notify-send` on the dev machine, so a
  test PATH that contains `/usr/bin` would find it (and pop real notifications).

## Scope

Create `core/backend/runs/notify.py` and
`tests/core/backend/runs/test_notify.py`. Tests first.

### Out of scope

- Any caller: `RunStore.qml` / `HelperRunner` invoking `notify.py`, reading
  `notifyOnEscalation`, composing the title and reason text from a run, and the
  `newAlerts` decision (parent lines 111-113, 135-136): their own cards.
- In-panel toasts, `RunToast.qml`, `RunIndicator` (parent lines 115-118, 135).
- `viewer-state.py` (card 2.2), `run-control.py` (card 2.1): unchanged.
- `docs/architecture.md`: left for S2's docs card, as card 2.2 did.
- notify-send options beyond the two texts (urgency, icon, app name, expiry,
  actions): not sent. YAGNI until a caller needs one.
- An always-on watcher (parent "Open questions", lines 165-167).

## Behaviour

### Command line

```
notify.py TITLE BODY
```

- Exactly two arguments. `TITLE` must be non-empty after stripping whitespace
  (notify-send refuses an empty summary). `BODY` may be empty.
- Both are taken verbatim: a leading `-`, spaces, newlines, quotes, `$`, `;`,
  and non-ASCII text reach notify-send unaltered and are never interpreted by a
  shell.
- Any other command line (0, 1 or 3+ arguments, blank `TITLE`) prints
  `{"ok": false, "error": {"type": "Usage", "message": "usage: notify.py TITLE BODY"}}`
  and exits **2**. notify-send is not looked up or run.

### Sending

1. Look up `notify-send` on `PATH` with `shutil.which` (so a non-executable file
   named `notify-send` counts as missing).
2. **Missing:** print `{"ok": true, "sent": false}`, exit 0. Nothing is run.
3. **Present:** run it as the argv list `[<resolved path>, "--", TITLE, BODY]`
   (the `--` keeps a title starting with `-` from being read as an option), no
   shell, stdin `/dev/null`, stdout and stderr captured (never passed through to
   our stdout), with a **10 s** timeout (`NOTIFY_TIMEOUT = 10`).
   - Exit 0: print `{"ok": true, "sent": true}`, exit 0. Anything notify-send
     printed is ignored.
   - Non-zero exit: print
     `{"ok": false, "error": {"type": "NotifyFailed", "message": M}}`, exit 0.
     `M` is `"notify-send exited N: "` followed by the last 20 lines (at most 2000
     characters) of its stderr, decoded with `errors="replace"`; when stderr is
     empty, `M` is `"notify-send exited N with no output."`.
   - Timeout, or notify-send cannot be started (`OSError`), or any other
     unexpected exception: print
     `{"ok": false, "error": {"type": "HelperError", "message": "The notification failed: <reason>"}}`,
     exit 0. The timed-out child is killed (`subprocess.run`'s own behaviour).

### Output contract

Exactly one JSON line on stdout on every path, nothing else on stdout. Exit 0
whenever a line was printed, failures included; exit 2 for `Usage` only. No
traceback ever reaches stdout. The module docstring lists every line above.

The script does not read or write any file, and does not depend on `HOME` or
`XDG_*`.

## Tests

All in `tests/core/backend/runs/test_notify.py`, **backend pytest tier**: the
helper is a standalone Python process whose contract is its argv, stdout line
and exit code, which is exactly what a subprocess-level pytest observes
(parent line 155-156 places these tests there). No QML or UI tier: nothing in
this card has a UI.

Harness (hermetic; the real `notify-send` must never run):

- A temp `bin` dir is the **whole** `PATH` (no `/usr/bin`, no `/bin`). The
  script runs as `[sys.executable, SCRIPT, ...]` with an absolute interpreter
  path, so it needs nothing on `PATH`.
- The stub `notify-send` starts with `#!<sys.executable>` (absolute; `env
  python3` would not resolve on that PATH). It appends its argv (as a JSON list)
  to `$FAKE_NOTIFY_DIR/calls.log`, writes `$FAKE_NOTIFY_DIR/err` to stderr if
  present, prints `stdout noise` to stdout, sleeps `$FAKE_NOTIFY_DIR/sleep`
  seconds if present, and exits with `$FAKE_NOTIFY_DIR/code` (default 0).
- `run(world, args, **env)` asserts stdout is exactly one line, parses it and
  returns `(exit, payload)`.

| # | test | proves |
|---|---|---|
| 1 | without notify-send (empty `bin`) | `{"ok": true, "sent": false}`, exit 0 |
| 2 | a non-executable file named `notify-send` on PATH | treated as missing: `sent: false`, exit 0, file untouched |
| 3 | with the stub, exit 0 | `{"ok": true, "sent": true}`, exit 0; `calls.log` holds exactly one call, argv `["--", TITLE, BODY]`; the stub's stdout noise is not in our stdout |
| 4 | title `-u critical`, body with newline, `$HOME`, `;`, quotes, `é ‼` | argv reaches the stub byte-identical after `--` |
| 5 | empty body | sent, argv `["--", TITLE, ""]` |
| 6 | stub exits 1 with stderr `boom` | `NotifyFailed`, message `notify-send exited 1: boom`, exit 0 |
| 7 | stub exits 3 with no stderr | `NotifyFailed`, message `notify-send exited 3 with no output.` |
| 8 | stub stderr of 50 lines | message carries only the last 20 lines, at most 2000 chars after the prefix |
| 9 | stub stderr with invalid UTF-8 bytes | one valid JSON line (replacement chars), `NotifyFailed` |
| 10 | stub sleeps 5 s, module run in-process with `NOTIFY_TIMEOUT` lowered (see below) | `HelperError`, message starts `The notification failed:`; returns 0; one line |
| 11 | usage: no args, one arg, three args, blank title `"  "` | each prints the Usage envelope, exit 2; `calls.log` absent (stub never run) |
| 12 | stub present but `notify-send` started fails (`OSError`, e.g. stub with a shebang to a missing interpreter) | `HelperError`, exit 0, one line |

Test 10 must not wait 10 s: load `notify.py` with `importlib.util` (the
filename has no hyphen, but load by path for symmetry with the other helpers),
set `module.NOTIFY_TIMEOUT` to a fraction of a second, point `PATH` at the stub
with `monkeypatch.setenv`, call `module.guarded([TITLE, BODY])`, and read the
line with `capsys`.

`tests/architecture` must stay green: no `def emit(` in `notify.py`, stdlib and
`common` imports only, no `.py` at the repo root.

## Acceptance

- `bash tests/run.sh` green, including the new file and `tests/architecture`.
- Running `notify.py` by hand with `notify-send` present shows a desktop
  notification with the given title and body.

---

# notify.py Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `core/backend/runs/notify.py`, a one-JSON-line helper that shows a desktop notification via `notify-send -- TITLE BODY` and does nothing when `notify-send` is missing. Write it test-first, with every test in `tests/core/backend/runs/test_notify.py`.

**Architecture:** One stdlib-only script modelled on `core/backend/runs/run-control.py`. `main(argv)` checks the command line (`Usage`, exit 2), looks up `notify-send` with `shutil.which` (`sent: false` when missing), runs it with `subprocess.run` as an argv list and turns a non-zero exit into `NotifyFailed` with the stderr tail. `guarded(argv)` turns anything raised (timeout, `OSError`) into `HelperError`. Two tasks: (1) usage, missing, sent and the verbatim argv; (2) the failure paths (`NotifyFailed`, `HelperError`).

**Tech Stack:** Python 3 stdlib (`subprocess`, `shutil`, `os`, `sys`), `common.json_line.emit`, pytest with a stub `notify-send` on a temp `PATH`.

**Spec:** `docs/superpowers/specs/2-3-notify-py-77a4b21f.md` (prepended above). Parent design: `docs/superpowers/specs/2026-10-03-am-run-controls-design.md` (S2).

**Worktree / branch:** all paths are relative to `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/ctl/task-2-3-notify-py-77a4b21f`, branch `ctl/task-2-3-notify-py-77a4b21f`. Run every command from that directory.

**Running pytest:** `python3` here may be a uv-managed interpreter without pytest (see `tests/run.sh`). Every pytest command below is written as `uv run --with pytest python3 -m pytest ...`. If `python3 -c 'import pytest'` succeeds, `python3 -m pytest ...` works as well.

## Global Constraints

- Command line: `notify.py TITLE BODY`, exactly two arguments. `TITLE` must be non-empty after `.strip()`; `BODY` may be empty. USAGE is exactly `usage: notify.py TITLE BODY`. A `Usage` failure exits 2 and never looks up or runs notify-send.
- TITLE and BODY are passed verbatim (never stripped, never through a shell): argv is `[<resolved path>, "--", TITLE, BODY]`.
- notify-send is found with `shutil.which("notify-send")`; missing prints `{"ok": true, "sent": false}`, exit 0.
- notify-send runs with `capture_output=True`, `encoding="utf-8"`, `errors="replace"`, `stdin=subprocess.DEVNULL`, `timeout=NOTIFY_TIMEOUT`; `NOTIFY_TIMEOUT = 10` is a module constant.
- Error types and messages: `NotifyFailed` / `notify-send exited N: <tail>` or `notify-send exited N with no output.`; `HelperError` / `The notification failed: <reason>`; `Usage` / `usage: notify.py TITLE BODY`.
- The stderr tail is: trailing whitespace stripped, the last 20 lines (`TAIL_LINES = 20`), then the last 2000 characters (`TAIL_CHARS = 2000`).
- Exactly one JSON line on stdout on every path. Exit 0 for every printed line except `Usage` (exit 2). No traceback on stdout.
- Imports are the stdlib plus `common` only. `emit` comes from `common.json_line` and is never redefined (`tests/architecture/test_layers.py` `DUPLICATED_PY`). Shebang `#!/usr/bin/env python3`; `sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))` before `from common.json_line import emit  # noqa: E402`.
- The script reads and writes no file and does not depend on `HOME` or `XDG_*`. It never reads `viewer-state.py` or `notifyOnEscalation`.
- No notify-send options beyond `--`, TITLE and BODY (no urgency, icon, app name, expiry, actions).
- All source strings are ASCII: write non-ASCII test text as `\uXXXX` escapes.
- Do not touch `run-control.py`, `viewer-state.py`, any QML, `docs/architecture.md`, or any existing test.
- Verification: `bash tests/run.sh` green.

## Review Focus

The spec's twelve tests are all in the tasks below. These five further inputs are implied by the spec but not in its table. Each has a named test in the task that owns the code:

1. A bad command line on a machine without notify-send. The expected result is `Usage`, exit 2, not `sent: false`: arguments are checked before the lookup. Pinned by `test_usage_wins_over_missing_notify_send` (Task 1).
2. A title with leading/trailing spaces (the caller composes it from a run). The blank check strips, but the title sent must not be: `"  Run r1  "` reaches notify-send unchanged. Pinned by `test_title_whitespace_is_sent_verbatim` (Task 1).
3. A title that is exactly `--` and a body starting with `-`. Both must arrive as positionals after our own `--`. Pinned by `test_dashdash_title_and_dash_body_reach_notify_send` (Task 1).
4. A failing notify-send whose stderr is only whitespace/blank lines. The expected message is `notify-send exited N with no output.`, not `notify-send exited N: ` with nothing after it. Pinned by `test_failed_with_whitespace_only_stderr` (Task 2).
5. A failing notify-send whose stderr ends in blank lines (D-Bus errors often do). The tail must end at the last real line. Pinned by `test_failed_tail_drops_trailing_blank_lines` (Task 2).

Note for the reviewer: `stderr_tail` has the same body as `run-control.py`'s. `docs/architecture.md` says a second use should become shared, but the spec fixes `run-control.py` as unchanged and `DUPLICATED_PY` does not list `stderr_tail`. The plan keeps a local copy and leaves sharing it for a later card.

## File Structure

- Create: `core/backend/runs/notify.py`. The whole helper: `failure`, `stderr_tail`, `main`, `guarded`.
- Create: `tests/core/backend/runs/test_notify.py`. Every test, with its own stub `notify-send`.

No other file changes.

---

### Task 1: Usage, missing notify-send, sent, verbatim argv

**Files:**
- Create: `core/backend/runs/notify.py`
- Test: `tests/core/backend/runs/test_notify.py` (create)

**Interfaces:**
- Consumes: `common.json_line.emit(payload, code=0) -> int`. It prints `json.dumps(payload)` and returns `code`.
- Produces (Task 2 relies on these exact names):
  - `USAGE = "usage: notify.py TITLE BODY"`, `NOTIFY_TIMEOUT = 10`
  - `failure(kind: str, message: str, code: int = 0) -> int`
  - `main(argv: list[str]) -> int`
  - Test helpers in `test_notify.py`: `STUB`, `write_exec(path, text)`, fixture `world` -> `{"bin": Path, "notify": Path}`, `install_stub(world, text=None)`, `env_for(world, **extra) -> dict`, `run(world, args, **extra) -> (int, dict)`, `calls(world) -> list[list[str]]`, `set_fixture(world, name, data)`, constants `USAGE`, `SENT`, `NOT_SENT`.

- [ ] **Step 1: Write the failing tests**

Create `tests/core/backend/runs/test_notify.py`:

```python
"""notify.py: a desktop alert through notify-send, one JSON line on every path.

Hermetic: a temp bin dir is the WHOLE PATH (no /usr/bin, no /bin), so the real
notify-send can never run. The stub notify-send there logs its argv to
FAKE_NOTIFY_DIR/calls.log and behaves as the fixtures in FAKE_NOTIFY_DIR say.
"""
import json
import os
import stat
import subprocess
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "..")
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "notify.py")

# The stub appends its argv (a JSON list) to calls.log, writes
# FAKE_NOTIFY_DIR/err to stderr if present (as bytes, so it may be invalid
# UTF-8), prints "stdout noise", sleeps FAKE_NOTIFY_DIR/sleep seconds if present
# and exits with FAKE_NOTIFY_DIR/code (default 0). Its shebang is the absolute
# interpreter: `env python3` would not resolve on a PATH that is only bin/.
STUB = '''#!@PYTHON@
import json, os, sys, time
d = os.environ["FAKE_NOTIFY_DIR"]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
err = os.path.join(d, "err")
if os.path.exists(err):
    with open(err, "rb") as f:
        sys.stderr.buffer.write(f.read())
    sys.stderr.flush()
sys.stdout.write("stdout noise\\n")
sys.stdout.flush()
sleep = os.path.join(d, "sleep")
if os.path.exists(sleep):
    time.sleep(float(open(sleep).read()))
code = os.path.join(d, "code")
sys.exit(int(open(code).read()) if os.path.exists(code) else 0)
'''

USAGE = {"ok": False, "error": {"type": "Usage", "message": "usage: notify.py TITLE BODY"}}
SENT = {"ok": True, "sent": True}
NOT_SENT = {"ok": True, "sent": False}


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def world(tmp_path):
    """An empty temp bin dir (the whole PATH) and the stub's fixture dir."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    notify = tmp_path / "notify"
    notify.mkdir()
    return {"bin": bindir, "notify": notify}


def install_stub(world, text=None):
    """Put an executable notify-send in bin/: the logging stub, or `text`."""
    write_exec(world["bin"] / "notify-send",
               STUB.replace("@PYTHON@", sys.executable) if text is None else text)


def env_for(world, **extra):
    e = {"PATH": str(world["bin"]), "FAKE_NOTIFY_DIR": str(world["notify"])}
    e.update(extra)
    return e


def run(world, args, **extra):
    """Run the helper; assert stdout is exactly one JSON line; return (exit, payload)."""
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True,
                       env=env_for(world, **extra), timeout=60)
    lines = p.stdout.splitlines()
    assert len(lines) == 1, (p.stdout, p.stderr)
    return p.returncode, json.loads(lines[0])


def calls(world):
    log = world["notify"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def set_fixture(world, name, data):
    """FAKE_NOTIFY_DIR/<name> holds `data` (str or bytes)."""
    (world["notify"] / name).write_bytes(data if isinstance(data, bytes) else data.encode())


# --- notify-send missing ------------------------------------------------------

def test_without_notify_send_nothing_is_sent(world):
    assert run(world, ["Run r1", "needs a human"]) == (0, NOT_SENT)


def test_non_executable_notify_send_counts_as_missing(world):
    path = world["bin"] / "notify-send"
    path.write_text("#!/bin/sh\necho hi\n")
    path.chmod(0o644)
    assert run(world, ["Run r1", "needs a human"]) == (0, NOT_SENT)
    assert path.read_text() == "#!/bin/sh\necho hi\n"
    assert calls(world) == []


# --- sent -----------------------------------------------------------------------

def test_sent_with_title_and_body_after_dashdash(world):
    install_stub(world)
    assert run(world, ["Run r1", "needs a human"]) == (0, SENT)
    assert calls(world) == [["--", "Run r1", "needs a human"]]


def test_notify_send_stdout_never_reaches_ours(world):
    install_stub(world)
    p = subprocess.run([sys.executable, SCRIPT, "Run r1", "b"], capture_output=True, text=True,
                       env=env_for(world), timeout=60)
    assert "stdout noise" not in p.stdout
    assert json.loads(p.stdout) == SENT


def test_args_reach_notify_send_verbatim(world):
    install_stub(world)
    title = "-u critical"
    body = "line one\nline two $HOME; echo 'hi' \"there\" \u00e9 \u203c"
    assert run(world, [title, body]) == (0, SENT)
    assert calls(world) == [["--", title, body]]


def test_empty_body_is_sent(world):
    install_stub(world)
    assert run(world, ["Run r1", ""]) == (0, SENT)
    assert calls(world) == [["--", "Run r1", ""]]


def test_title_whitespace_is_sent_verbatim(world):
    install_stub(world)
    assert run(world, ["  Run r1  ", "b"]) == (0, SENT)
    assert calls(world) == [["--", "  Run r1  ", "b"]]


def test_dashdash_title_and_dash_body_reach_notify_send(world):
    install_stub(world)
    assert run(world, ["--", "-b"]) == (0, SENT)
    assert calls(world) == [["--", "--", "-b"]]


# --- usage ----------------------------------------------------------------------

@pytest.mark.parametrize("args", [[], ["Run r1"], ["Run r1", "b", "extra"],
                                  ["  ", "b"], ["", "b"], ["\t\n", "b"]])
def test_usage(world, args):
    install_stub(world)
    assert run(world, args) == (2, USAGE)
    assert not (world["notify"] / "calls.log").exists()


def test_usage_wins_over_missing_notify_send(world):
    assert run(world, []) == (2, USAGE)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_notify.py -v`
Expected: every test FAILs. The script does not exist, so stdout is empty and `run()` fails its assertion `assert len(lines) == 1` (stderr shows `can't open file ... notify.py`).

- [ ] **Step 3: Write the minimal implementation**

Create `core/backend/runs/notify.py`:

```python
#!/usr/bin/env python3
"""Show a desktop notification through notify-send.

    notify.py TITLE BODY

Runs `notify-send -- TITLE BODY` as an argv list (no shell, stdin /dev/null,
output captured, a NOTIFY_TIMEOUT s timeout). TITLE and BODY reach notify-send
verbatim; `--` keeps a TITLE starting with `-` from being read as an option.
TITLE must not be blank; BODY may be empty. Whether to alert at all is the
caller's call: this script reads no settings and no files.

Prints exactly one JSON line on EVERY path:
- {"ok": true, "sent": true} when notify-send ran;
- {"ok": true, "sent": false} when notify-send is not on PATH (nothing is run);
- {"ok": false, "error": {"type": "Usage", ...}} for any other command line.
Exit 0 whenever a line was printed; exit 2 for Usage only.
"""
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: notify.py TITLE BODY"
NOTIFY_TIMEOUT = 10


def failure(kind, message, code=0):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def main(argv):
    if len(argv) != 2 or not argv[0].strip():
        return failure("Usage", USAGE, 2)
    notify_send = shutil.which("notify-send")
    if notify_send is None:
        return emit({"ok": True, "sent": False})
    title, body = argv
    subprocess.run([notify_send, "--", title, body], capture_output=True, encoding="utf-8",
                   errors="replace", stdin=subprocess.DEVNULL, timeout=NOTIFY_TIMEOUT)
    return emit({"ok": True, "sent": True})


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_notify.py tests/architecture -v`
Expected: PASS, every test (the architecture tests confirm no `def emit(` and stdlib/`common` imports only).

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/notify.py tests/core/backend/runs/test_notify.py
git commit -m "$(cat <<'EOF'
feat(runs): notify.py sends TITLE and BODY through notify-send, or reports it missing (card 77a4b21f)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: NotifyFailed with the stderr tail; HelperError on timeout or a notify-send that cannot start

**Files:**
- Modify: `core/backend/runs/notify.py` (whole file shown below)
- Test: `tests/core/backend/runs/test_notify.py` (append; add two imports)

**Interfaces:**
- Consumes (from Task 1): `USAGE`, `NOTIFY_TIMEOUT`, `failure(kind, message, code=0)`, `main(argv)`; test helpers `world`, `install_stub(world, text=None)`, `env_for(world, **extra)`, `run(world, args, **extra)`, `calls(world)`, `set_fixture(world, name, data)`.
- Produces: `TAIL_LINES = 20`, `TAIL_CHARS = 2000`, `stderr_tail(stderr: str) -> str`, `guarded(argv: list[str]) -> int` (the `__main__` entry point). A future caller (RunStore) relies only on the command line and the JSON lines.

- [ ] **Step 1: Write the failing tests**

In `tests/core/backend/runs/test_notify.py`, replace the import block

```python
import json
import os
import stat
import subprocess
import sys

import pytest
```

with

```python
import importlib.util
import json
import os
import stat
import subprocess
import sys
import time

import pytest
```

Then append to the end of the file:

```python


# --- notify-send failed -------------------------------------------------------

def notify_failed(message):
    return {"ok": False, "error": {"type": "NotifyFailed", "message": message}}


def test_failed_carries_stderr(world):
    install_stub(world)
    set_fixture(world, "err", "boom\n")
    set_fixture(world, "code", "1")
    assert run(world, ["Run r1", "b"]) == (0, notify_failed("notify-send exited 1: boom"))
    assert calls(world) == [["--", "Run r1", "b"]]


def test_failed_without_stderr(world):
    install_stub(world)
    set_fixture(world, "code", "3")
    assert run(world, ["Run r1", "b"]) == (0, notify_failed("notify-send exited 3 with no output."))


def test_failed_with_whitespace_only_stderr(world):
    install_stub(world)
    set_fixture(world, "err", "  \n\n\t\n")
    set_fixture(world, "code", "2")
    assert run(world, ["Run r1", "b"]) == (0, notify_failed("notify-send exited 2 with no output."))


def test_failed_tail_drops_trailing_blank_lines(world):
    install_stub(world)
    set_fixture(world, "err", "first\nboom\n\n  \n")
    set_fixture(world, "code", "1")
    assert run(world, ["Run r1", "b"]) == (0, notify_failed("notify-send exited 1: first\nboom"))


def test_failed_message_keeps_the_last_20_lines(world):
    install_stub(world)
    set_fixture(world, "err", "".join("line %02d\n" % i for i in range(1, 51)))
    set_fixture(world, "code", "1")
    tail = "\n".join("line %02d" % i for i in range(31, 51))
    assert run(world, ["Run r1", "b"]) == (0, notify_failed("notify-send exited 1: " + tail))


def test_failed_message_is_capped_at_2000_chars(world):
    install_stub(world)
    lines = ["%02d " % i + "x" * 150 for i in range(1, 51)]
    set_fixture(world, "err", "\n".join(lines) + "\n")
    set_fixture(world, "code", "1")
    tail = "\n".join(lines[-20:])[-2000:]
    assert len(tail) == 2000
    code, payload = run(world, ["Run r1", "b"])
    assert (code, payload) == (0, notify_failed("notify-send exited 1: " + tail))


def test_failed_with_invalid_utf8_stderr(world):
    install_stub(world)
    set_fixture(world, "err", b"bad \xff\xfe bytes\n")
    set_fixture(world, "code", "1")
    assert run(world, ["Run r1", "b"]) == (
        0, notify_failed("notify-send exited 1: bad \ufffd\ufffd bytes"))


# --- helper errors --------------------------------------------------------------

def load_helper():
    """The script as a module, loaded by path like the other helpers' tests."""
    spec = importlib.util.spec_from_file_location("notify", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_timeout_is_a_helper_error(world, monkeypatch, capsys):
    install_stub(world)
    set_fixture(world, "sleep", "5")
    for key, value in env_for(world).items():
        monkeypatch.setenv(key, value)
    module = load_helper()
    monkeypatch.setattr(module, "NOTIFY_TIMEOUT", 0.3)
    start = time.monotonic()
    assert module.guarded(["Run r1", "b"]) == 0
    assert time.monotonic() - start < 4
    lines = capsys.readouterr().out.splitlines()
    assert len(lines) == 1, lines
    payload = json.loads(lines[0])
    assert payload["ok"] is False
    assert payload["error"]["type"] == "HelperError"
    assert payload["error"]["message"].startswith("The notification failed:")


def test_notify_send_that_cannot_start_is_a_helper_error(world):
    install_stub(world, "#!/nonexistent/interpreter\n")
    code, payload = run(world, ["Run r1", "b"])
    assert code == 0
    assert payload["ok"] is False
    assert payload["error"]["type"] == "HelperError"
    assert payload["error"]["message"].startswith("The notification failed:")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_notify.py -v`
Expected: the Task 1 tests PASS. The seven `test_failed_*` tests FAIL because the payload is `{"ok": true, "sent": true}` instead of `NotifyFailed`. `test_timeout_is_a_helper_error` FAILs with `AttributeError: module 'notify' has no attribute 'guarded'`. `test_notify_send_that_cannot_start_is_a_helper_error` FAILs at `assert len(lines) == 1` (the `FileNotFoundError` traceback goes to stderr; stdout is empty).

- [ ] **Step 3: Write the implementation**

Replace the whole of `core/backend/runs/notify.py` with:

```python
#!/usr/bin/env python3
"""Show a desktop notification through notify-send.

    notify.py TITLE BODY

Runs `notify-send -- TITLE BODY` as an argv list (no shell, stdin /dev/null,
output captured, a NOTIFY_TIMEOUT s timeout). TITLE and BODY reach notify-send
verbatim; `--` keeps a TITLE starting with `-` from being read as an option.
TITLE must not be blank; BODY may be empty. Whether to alert at all is the
caller's call: this script reads no settings and no files.

Prints exactly one JSON line on EVERY path:
- {"ok": true, "sent": true} when notify-send exited 0 (its output is ignored);
- {"ok": true, "sent": false} when notify-send is not on PATH (nothing is run);
- {"ok": false, "error": {"type": "NotifyFailed", ...}} when notify-send exited
  non-zero; the message is "notify-send exited N: " and the tail of its stderr,
  or "notify-send exited N with no output." when stderr is blank;
- {"ok": false, "error": {"type": "HelperError", ...}} on any unexpected
  failure (a timeout, a notify-send that cannot start);
- {"ok": false, "error": {"type": "Usage", ...}} for any other command line.
Exit 0 whenever a line was printed, failures included; exit 2 for Usage only.
"""
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: notify.py TITLE BODY"
NOTIFY_TIMEOUT = 10
TAIL_LINES = 20
TAIL_CHARS = 2000


def failure(kind, message, code=0):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def stderr_tail(stderr):
    """The end of notify-send's stderr, where a failure names its cause: at most
    TAIL_LINES lines, and of those at most TAIL_CHARS characters."""
    lines = stderr.rstrip().splitlines()[-TAIL_LINES:]
    return "\n".join(lines)[-TAIL_CHARS:]


def main(argv):
    if len(argv) != 2 or not argv[0].strip():
        return failure("Usage", USAGE, 2)
    notify_send = shutil.which("notify-send")
    if notify_send is None:
        return emit({"ok": True, "sent": False})
    title, body = argv
    proc = subprocess.run([notify_send, "--", title, body], capture_output=True,
                          encoding="utf-8", errors="replace", stdin=subprocess.DEVNULL,
                          timeout=NOTIFY_TIMEOUT)
    if proc.returncode != 0:
        exited = "notify-send exited " + str(proc.returncode)
        tail = stderr_tail(proc.stderr)
        return failure("NotifyFailed", exited + ": " + tail if tail else exited + " with no output.")
    return emit({"ok": True, "sent": True})


def guarded(argv):
    """The caller parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception (a timeout, a notify-send that cannot start) - may end
    without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The notification failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_notify.py tests/architecture -v`
Expected: PASS, every test. `test_timeout_is_a_helper_error` takes well under a second.

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest reports no failures, and no QML test prints `FAIL`. The script exits 0.

- [ ] **Step 6: Check by hand that a real notification appears (acceptance)**

Run: `python3 core/backend/runs/notify.py "notify.py check" "a body line"`
Expected: stdout is `{"ok": true, "sent": true}` and a desktop notification titled `notify.py check` with body `a body line` appears. Skip this step if there is no graphical session, and say so in the report.

- [ ] **Step 7: Commit**

```bash
git add core/backend/runs/notify.py tests/core/backend/runs/test_notify.py
git commit -m "$(cat <<'EOF'
feat(runs): notify.py reports a failed notify-send with its stderr tail and any unexpected failure as HelperError (card 77a4b21f)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**Spec coverage (test table -> test):**
1 `test_without_notify_send_nothing_is_sent`; 2 `test_non_executable_notify_send_counts_as_missing`; 3 `test_sent_with_title_and_body_after_dashdash` + `test_notify_send_stdout_never_reaches_ours`; 4 `test_args_reach_notify_send_verbatim`; 5 `test_empty_body_is_sent`; 6 `test_failed_carries_stderr`; 7 `test_failed_without_stderr`; 8 `test_failed_message_keeps_the_last_20_lines` + `test_failed_message_is_capped_at_2000_chars`; 9 `test_failed_with_invalid_utf8_stderr`; 10 `test_timeout_is_a_helper_error`; 11 `test_usage` (six cases); 12 `test_notify_send_that_cannot_start_is_a_helper_error`. Behaviour: argv list with `--`, no shell, `DEVNULL` stdin, captured output, `NOTIFY_TIMEOUT = 10` -> Task 1/2 code; module docstring lists every line -> Task 2 Step 3; no file/HOME/XDG use -> the harness env is only `PATH` and `FAKE_NOTIFY_DIR`; acceptance (`tests/run.sh` green, real notification) -> Task 2 Steps 5-6.

**Placeholders:** none; every code step shows full code.

**Type consistency:** `failure`, `main`, `guarded`, `stderr_tail`, `NOTIFY_TIMEOUT`, `TAIL_LINES`, `TAIL_CHARS` are named the same in both tasks; test helpers defined in Task 1 are the ones Task 2 uses.

**Review Focus:** five lines, each pinned by a named test in its owning task.
<!-- task-pipeline: validated -->
