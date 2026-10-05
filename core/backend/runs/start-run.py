#!/usr/bin/env python3
"""Start a dispatch: `am run`, detached, and the id of the run it started.

    start-run.py ROOT (milestone ID | card ID | board) [--base-branch B] [--branch-prefix P]
                 [--max-concurrent N] [--verify CMD]... [--allow-no-verification]

Spawns `am run (--milestone ID | --card ID | --board) --repo-dir ROOT`, then the
options given in a fixed order (--base-branch, --branch-prefix, --max-concurrent,
every --verify pair in the order given, --allow-no-verification), as an argv list
(no shell), ROOT made absolute. Every value is the next argument verbatim, even if
it starts with `-`; am refuses bad ones itself. --dry-run, --detach and --pretty
are never sent.

The child runs in ROOT, in its own session (so a signal to the helper's process
group never reaches it), stdin /dev/null, stdout and stderr in a fresh log,
<state>/omarchy-project-manager/am-runs/<UTC stamp>-<project>-<8 hex>.log (dir
0700, file 0600), <state> being XDG_STATE_HOME when absolute, else
~/.local/state. am prints its envelope only when the run ends, so the helper
never blocks on it, signals it or ends it: the run outlives the helper, the
panel and the shell. The helper only polls whether it has exited.

For up to POLL_WINDOW seconds after the spawn it asks `am runs --repo-dir ROOT`
every POLL_INTERVAL seconds for the run this launch started: a row with an id,
started at or after the spawn (to the second), whose branch_prefix is the one
given (for the board, also `<prefix>-<stem>`; any, when none was given); the
earliest such row wins. A failing `am runs` is retried on the next tick.

Prints exactly one JSON line on EVERY path; pid, log and started_at are the
child's pid, the absolute log path and the spawn time (YYYY-MM-DDTHH:MM:SSZ):
- {"ok": true, "pid", "log", "started_at", "run_id": ID, "message": ""} when the
  run was found (even if am has exited since);
- {"ok": true, "pid", "log", "started_at", "run_id": null, "message": "started,
  run not visible yet"} when the window ended with am still running;
- {"ok": false, "error", "pid", "log", "started_at", "exit_code", "log_tail"}
  when am exited before its run appeared: the error is am's own refusal (the
  log's last non-empty line, if an {"ok": false, "error": {...}} envelope),
  else {"type": "AmExited", ...}; log_tail is the end of the log;
- {"ok": false, "error": {"type": "SpawnFailed", ...}, "log"} when am could not
  be started (ROOT missing, am not executable); the log says why;
- {"ok": false, "error": {"type": "AmMissing", ...}} when am is not on PATH;
- {"ok": false, "error": {"type": "HelperError", ...}} on any unexpected
  failure, with pid, log and started_at too if it came after the spawn;
- {"ok": false, "error": {"type": "Usage", ...}} for any other command line.
Exit 0 whenever a line was printed, refusals and errors included; exit 2 for
Usage only.
"""
import datetime
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = ("usage: start-run.py ROOT (milestone ID | card ID | board) [--base-branch B]"
         " [--branch-prefix P] [--max-concurrent N] [--verify CMD]..."
         " [--allow-no-verification]")
VALUED = ("--base-branch", "--branch-prefix", "--max-concurrent")
TARGETS = ("milestone", "card")
POLL_WINDOW = 20
POLL_INTERVAL = 0.5
RUNS_TIMEOUT = 5
TAIL_LINES = 20
TAIL_CHARS = 2000
LOG_DIR_NAME = "am-runs"
STAMP = "%Y-%m-%dT%H:%M:%SZ"
NOT_VISIBLE = "started, run not visible yet"


class SpawnError(Exception):
    """am could not be started; the message is the OS error's text."""


def failure(kind, message, code=0, **extra):
    return emit({"ok": False, "error": {"type": kind, "message": message}, **extra}, code)


def good_root(root):
    return bool(root) and not root.startswith("-")


def parse(argv):
    """(root, target, id, options) for a command line USAGE allows, else None.

    target is "milestone", "card" or "board"; id is None for the board. options
    always maps "--verify" to the list of commands in the order given, maps each
    given VALUED flag to its value and "--allow-no-verification" to True when
    given; a once-only flag given twice is a usage error."""
    if len(argv) < 2 or not good_root(argv[0]):
        return None
    root, target, rest = argv[0], argv[1], argv[2:]
    if target in TARGETS:
        if not rest or not rest[0]:
            return None
        ident, rest = rest[0], rest[1:]
    elif target == "board":
        ident = None
    else:
        return None
    options = {"--verify": []}
    while rest:
        flag = rest[0]
        if flag == "--verify" and len(rest) > 1:
            options["--verify"].append(rest[1])
            rest = rest[2:]
        elif flag in VALUED and len(rest) > 1 and flag not in options:
            options[flag] = rest[1]
            rest = rest[2:]
        elif flag == "--allow-no-verification" and flag not in options:
            options[flag] = True
            rest = rest[1:]
        else:
            return None
    return root, target, ident, options


def run_argv(root, target, ident, options):
    """am's argv after the executable, in a fixed order whatever order the options came in."""
    argv = ["run", "--board"] if target == "board" else ["run", "--" + target, ident]
    argv += ["--repo-dir", root]
    for flag in VALUED:
        if flag in options:
            argv += [flag, options[flag]]
    for cmd in options["--verify"]:
        argv += ["--verify", cmd]
    if "--allow-no-verification" in options:
        argv.append("--allow-no-verification")
    return argv


def state_home():
    """XDG_STATE_HOME, but only when it is absolute; a relative value is ignored so
    the log tree never lands under whatever the working directory happens to be."""
    state = os.environ.get("XDG_STATE_HOME") or ""
    if not os.path.isabs(state):
        return os.path.join(os.path.expanduser("~"), ".local", "state")
    return state


def log_path(root):
    """A fresh log path for this launch; the random suffix keeps two launches in the
    same second apart. Creates the (private) directory."""
    directory = os.path.join(state_home(), "omarchy-project-manager", LOG_DIR_NAME)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    os.chmod(directory, 0o700)
    project = re.sub(r"[^A-Za-z0-9._-]", "_", os.path.basename(os.path.abspath(root))) or "project"
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    name = stamp + "-" + project + "-" + secrets.token_hex(4) + ".log"
    return os.path.abspath(os.path.join(directory, name))


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc)


def list_runs(am, root):
    """The rows of `am runs --repo-dir ROOT`, or [] when it gives none this tick
    (a failure, a timeout, bad JSON, a refusal): the next tick asks again."""
    try:
        proc = subprocess.run([am, "runs", "--repo-dir", root], capture_output=True,
                              encoding="utf-8", errors="replace", stdin=subprocess.DEVNULL,
                              timeout=RUNS_TIMEOUT)
        envelope = json.loads(proc.stdout)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return []
    if not isinstance(envelope, dict) or envelope.get("ok") is not True:
        return []
    data = envelope.get("data")
    runs = data.get("runs") if isinstance(data, dict) else None
    return runs if isinstance(runs, list) else []


def parse_time(value):
    """An ISO-8601 time (`Z` or an offset) as an aware datetime; no offset means UTC.
    None when it does not parse."""
    if not isinstance(value, str):
        return None
    try:
        when = datetime.datetime.fromisoformat(value)
    except ValueError:
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=datetime.timezone.utc)
    return when


def matches(row, target, prefix, since):
    """Whether an `am runs` row can be the run this launch started: it has an id,
    started at or after `since`, and carries the prefix given (the board's runs may
    carry `<prefix>-<stem>`); with no prefix given, any."""
    if not isinstance(row, dict) or not isinstance(row.get("id"), str) or not row["id"]:
        return False
    when = parse_time(row.get("started_at"))
    if when is None or when < since:
        return False
    if prefix is None:
        return True
    got = row.get("branch_prefix")
    if not isinstance(got, str):
        return False
    return got == prefix or (target == "board" and got.startswith(prefix + "-"))


def find_run(rows, target, prefix, since):
    """The id of the earliest matching row (on a tie, the one listed last: the
    oldest in am's newest-first order), else None."""
    best = None
    for row in rows:
        if matches(row, target, prefix, since):
            when = parse_time(row["started_at"])
            if best is None or when <= best[0]:
                best = (when, row["id"])
    return best[1] if best else None


def spawn(am, argv, root, log):
    """(proc, started) of the detached `am run`. started is the UTC time just before
    the spawn, floored to the second as am stamps its runs, so a run am stamps in
    the same second still counts as started at or after it."""
    fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.fchmod(fd, 0o600)
        started = utc_now().replace(microsecond=0)
        try:
            proc = subprocess.Popen([am, *argv], cwd=root, stdin=subprocess.DEVNULL, stdout=fd,
                                    stderr=subprocess.STDOUT, start_new_session=True)
        except OSError as e:
            os.write(fd, ("start-run: could not start am: " + str(e) + "\n").encode("utf-8", "replace"))
            raise SpawnError(str(e)) from e
        return proc, started
    finally:
        os.close(fd)


def read_log(path):
    with open(path, "rb") as f:
        return f.read().decode("utf-8", "replace")


def log_tail(text):
    """The end of the log, where am's refusal or a crash names its cause: at most
    TAIL_LINES lines, and of those at most TAIL_CHARS characters."""
    lines = text.rstrip().splitlines()[-TAIL_LINES:]
    return "\n".join(lines)[-TAIL_CHARS:]


def refusal_of(text):
    """am's own error object when the log's last non-empty line is its refusal
    envelope ({"ok": false, "error": {...}}), else None."""
    lines = [line for line in text.splitlines() if line.strip()]
    if not lines:
        return None
    try:
        envelope = json.loads(lines[-1])
    except ValueError:
        return None
    if (isinstance(envelope, dict) and envelope.get("ok") is False
            and isinstance(envelope.get("error"), dict)):
        return envelope["error"]
    return None


def early_exit(proc, launch):
    """am exited before its run appeared: its refusal if it printed one (a
    ClaimedError, a missing milestone, missing verification), else AmExited."""
    code = proc.returncode
    text = read_log(launch["log"])
    error = refusal_of(text) or {"type": "AmExited", "message":
                                 "am run exited " + str(code) + " before its run appeared."}
    return emit({"ok": False, "error": error, **launch, "exit_code": code,
                 "log_tail": log_tail(text)})


def watch(proc, am, root, target, prefix, launch, started, deadline):
    """Tick every POLL_INTERVAL until the run appears, am exits or the window ends;
    one last tick runs at or after the deadline. Whether am has exited is read
    before `am runs` is asked: an exit seen first means its row, if any, was
    already written, so an exit during the query is never taken for an early exit."""
    while True:
        last = time.monotonic() >= deadline
        exited = proc.poll() is not None
        run_id = find_run(list_runs(am, root), target, prefix, started)
        if run_id is not None:
            return emit({"ok": True, **launch, "run_id": run_id, "message": ""})
        if exited:
            return early_exit(proc, launch)
        if last:
            return emit({"ok": True, **launch, "run_id": None, "message": NOT_VISIBLE})
        time.sleep(POLL_INTERVAL)


def main(argv, launch):
    parsed = parse(argv)
    if parsed is None:
        return failure("Usage", USAGE, 2)
    root, target, ident, options = parsed
    # am run starts in ROOT, so a relative --repo-dir would name ROOT/ROOT to it.
    root = os.path.abspath(root)
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    log = log_path(root)
    try:
        proc, started = spawn(am, run_argv(root, target, ident, options), root, log)
    except SpawnError as e:
        return failure("SpawnFailed", "Could not start am run: " + str(e), log=log)
    deadline = time.monotonic() + POLL_WINDOW
    launch.update({"pid": proc.pid, "log": log, "started_at": started.strftime(STAMP)})
    return watch(proc, am, root, target, options.get("--branch-prefix"), launch, started, deadline)


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception - may end without one. After the spawn the line also
    carries pid, log and started_at: the run may be going."""
    launch = {}
    try:
        return main(argv, launch)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The launch failed: " + reason, **launch)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
