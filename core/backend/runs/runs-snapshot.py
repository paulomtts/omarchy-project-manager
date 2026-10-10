#!/usr/bin/env python3
"""Snapshot am runs: every project's, one project's, or a single run.

    runs-snapshot.py                   all projects
    runs-snapshot.py <project_root>    one project
    runs-snapshot.py --run RUN         one run

<project_root> and RUN are non-empty and do not start with -. Any other argv is
a Usage error (exit 2) and am is not run.

List modes run `am runs --all-projects --limit 200` (or `am runs --repo-dir R
--limit 200` for one project), then `am status <id>` for every selected run, in
am's (newest-first) order. Selected: every non-terminal run plus the first 10
terminal ones (terminal: done, escalated, stopped, cancelled, canceled; exact
match) among those 200 rows; a run older than the 200th row is not in the
snapshot. Single-run mode runs `am status RUN` alone. `am status` never gets
--repo-dir.

Prints exactly one JSON line on EVERY path:
{"ok": true, "as_of_seq": <am runs as_of_seq>, "store_id": <am runs store_id>,
 "runs": [{<am runs row>, "status": <am status data>}], "data_dir": D}
or, for --run,
{"ok": true, "run": RUN, "as_of_seq": <am status as_of_seq>,
 "store_id": <am status store_id>, "status": <am status data>, "data_dir": D}
where store_id is "" when am's is not a string and D is XDG_DATA_HOME when
absolute, else ~/.local/share;
or {"ok": false, "error": {"type", "message"}} with type Usage (exit 2),
AmMissing, AmBadOutput, SchemaMismatch (am runs or am status data without a
non-negative integer as_of_seq: the plugin needs the newer am) or HelperError.
An `ok:false` envelope from am (StoreBusyError, UnknownRunError, RepoDirError,
...) is re-emitted unchanged. Exit 0 ok, 1 failure, 2 usage. A failure stops at
the failing am call; a list is never partial. Only `am` commands are used,
always as argv lists; am's database and on-disk layout are never read.
"""
import os
import shutil
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.am_runs import AM_TIMEOUT, AmFailure, list_snapshot, single_snapshot  # noqa: E402
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-snapshot.py [<project_root> | --run RUN]"


def failure(kind, message, code=1):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def parse_args(argv):
    """("list", the `am runs` scope arguments) or ("run", RUN) for the helper's
    argv: --all-projects for none, --repo-dir R for one <project_root>, RUN for
    `--run RUN` (R and RUN non-empty, not starting with -); None for anything
    else."""
    if not argv:
        return "list", ["--all-projects"]
    if len(argv) == 1 and argv[0] and not argv[0].startswith("-"):
        return "list", ["--repo-dir", argv[0]]
    if len(argv) == 2 and argv[0] == "--run" and argv[1] and not argv[1].startswith("-"):
        return "run", argv[1]
    return None


def main(argv):
    mode = parse_args(argv)
    if mode is None:
        return failure("Usage", USAGE, 2)
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    kind, arg = mode
    try:
        result = (list_snapshot(am, arg, AM_TIMEOUT) if kind == "list"
                  else single_snapshot(am, arg, AM_TIMEOUT))
    except AmFailure as e:
        return emit(e.payload, 1)
    return emit(result)


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception (a timeout, an am that cannot start) - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The runs snapshot failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
