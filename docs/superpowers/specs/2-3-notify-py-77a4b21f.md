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
