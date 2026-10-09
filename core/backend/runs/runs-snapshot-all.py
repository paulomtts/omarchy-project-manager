#!/usr/bin/env python3
"""Snapshot am runs for several project roots.

    runs-snapshot-all.py <root> [<root> ...]

Each <root> is non-empty and does not start with -. No roots, or any root that
breaks this rule, is a Usage error (exit 2) and am is not run. A root is used
exactly as given, as its entry's `root` and as the --repo-dir value; a repeated
root is snapshotted once per time it appears.

For each root: `am runs --repo-dir <root> --limit 200`, then `am status <id>`
(never with --repo-dir) for every non-terminal run and the first 10 terminal ones
(terminal: done, escalated, stopped, cancelled, canceled), in am's (newest-first)
order. Up to 4 roots run at once; each am call gets 60 s.

Prints exactly one JSON line on EVERY path:
{"ok": true, "projects": [<entry>, ...], "data_dir": D}
with one entry per root, in argv order, either
{"root": R, "ok": true, "runs": [{<am runs row>, "status": <am status data>}]}
or {"root": R, "ok": false, "error": E}, where E is am's own `ok:false`
envelope's error unchanged (StoreBusyError, RepoDirError, ...) or
{"type", "message"} with type RootMissing (R is not a directory; am is not run
for it), AmMissing (then in every entry), AmTimeout, AmBadOutput,
SchemaMismatch or HelperError. A failed root has no runs; it never changes
another root's entry. D is XDG_DATA_HOME when absolute, else ~/.local/share.
Otherwise {"ok": false, "error": {"type", "message"}} with type Usage (exit 2)
or HelperError (exit 1). Exit 0 whenever the projects line prints. Only `am`
commands are used, always as argv lists; am's database and on-disk layout are
never read.
"""
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.am_runs import AM_TIMEOUT, AmFailure, data_dir, list_snapshot  # noqa: E402
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-snapshot-all.py <root> [<root> ...]"
WORKERS = 4


def failure(kind, message, code=1):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def parse_args(argv):
    """The roots, as given, when there is at least one and each is non-empty and
    does not start with -; None otherwise."""
    if not argv or any(not root or root.startswith("-") for root in argv):
        return None
    return list(argv)


def entry_error(root, kind, message):
    return {"root": root, "ok": False, "error": {"type": kind, "message": message}}


def project_entry(am, root, timeout):
    """`root`'s entry. Never raises an Exception: every failure is the entry's error."""
    if not os.path.isdir(root):
        return entry_error(root, "RootMissing", root + " is not a directory.")
    try:
        snapshot = list_snapshot(am, ["--repo-dir", root], timeout)
    except AmFailure as e:
        return {"root": root, "ok": False, "error": e.payload.get("error")}
    except subprocess.TimeoutExpired:
        return entry_error(root, "AmTimeout", "am did not answer within " + str(timeout) + " s.")
    except Exception as e:  # noqa: BLE001 - one root's failure is its own entry
        reason = str(e) or e.__class__.__name__
        return entry_error(root, "HelperError", "The runs snapshot failed: " + reason)
    return {"root": root, "ok": True, "runs": snapshot["runs"]}


def main(argv):
    roots = parse_args(argv)
    if roots is None:
        return failure("Usage", USAGE, 2)
    am = shutil.which("am")
    if am is None:
        projects = [entry_error(root, "AmMissing", "am is not installed.") for root in roots]
    else:
        timeout = AM_TIMEOUT
        with ThreadPoolExecutor(max_workers=WORKERS) as pool:
            projects = list(pool.map(lambda root: project_entry(am, root, timeout), roots))
    return emit({"ok": True, "projects": projects, "data_dir": data_dir()})


def guarded(argv):
    """The caller parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The runs snapshot failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
