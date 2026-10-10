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
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.am_runs import AM_TIMEOUT, AmFailure, call_am, run_list  # noqa: E402
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-alerts.py"
IDLE_POLL = 1.0  # seconds; the longest the main loop blocks with nothing pending
BRD_TIMEOUT = 30  # seconds; the longest one `brd projects` may take
POLL_EVERY = 60  # seconds between lease polls while a run is tracked
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
