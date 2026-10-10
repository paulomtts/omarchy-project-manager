#!/usr/bin/env python3
"""One page of a project's older runs, newest first.

    runs-history.py ROOT --before ISO [--limit K] [--status S,...] [--since ISO]

ROOT is the one positional (non-empty, not starting with -), anywhere among the
options. Each option is the flag then its value as the next argument (no
--flag=value), at most once; a value is non-empty and does not start with -.
--before is required. --before and --since are ISO-8601 times as
datetime.fromisoformat reads them; a time without an offset is UTC. K is a
decimal integer >= 1 (ASCII digits), taken as 25 when larger; default 10.
S,... is a comma-separated list of non-empty status names matched exactly;
default done, escalated, stopped, cancelled, canceled. Any other argv is a
Usage error (exit 2) and am is not run.

Runs `am runs --repo-dir ROOT` (no --limit, no --before), ROOT as given. Every
listed row needs a started_at that parses (else AmBadOutput). Kept, in am's
newest-first order: the rows whose status is in the set, started strictly
before --before and, with --since, not before --since; times compare as
instants. The page is the first K kept rows; `more` is true exactly when more
than K rows were kept among those am listed. Then `am status <id>` once per
paged row, in order, never with --repo-dir.

Prints exactly one JSON line on EVERY path:
{"ok": true, "runs": [{<am runs row>, "status": <am status data>}], "more": bool}
or {"ok": false, "error": {"type", "message"}} with type Usage (exit 2),
AmMissing, AmBadOutput, SchemaMismatch (am status data without a non-negative
integer as_of_seq: the plugin needs the newer am) or HelperError. An `ok:false`
envelope from am (RepoDirError, UnknownRunError, StoreBusyError, ...) is
re-emitted unchanged. Exit 0 ok, 1 failure, 2 usage. A failure stops at the
failing am call; a list is never partial. Only `am` commands are used, always
as argv lists; am's database and on-disk layout are never read; nothing is
written.
"""
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.am_runs import (  # noqa: E402
    AM_TIMEOUT, TERMINAL, AmFailure, bad_output, call_am, parse_time, run_list, run_status)
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-history.py ROOT --before ISO [--limit K] [--status S,...] [--since ISO]"
OPTIONS = ("--before", "--limit", "--since", "--status")
DEFAULT_LIMIT = 10
MAX_LIMIT = 25
DIGITS = re.compile(r"[0-9]+")


def failure(kind, message, code=1):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def parse_args(argv):
    """{"root", "before", "since", "limit", "statuses"} for the helper's argv
    (since None when not given; limit capped at MAX_LIMIT; statuses a frozenset,
    TERMINAL when not given); None for anything the grammar does not accept."""
    root, values, i = None, {}, 0
    while i < len(argv):
        arg = argv[i]
        if arg in OPTIONS:
            value = argv[i + 1] if i + 1 < len(argv) else ""
            if arg in values or not value or value.startswith("-"):
                return None
            values[arg] = value
            i += 2
        elif root is None and arg and not arg.startswith("-"):
            root = arg
            i += 1
        else:
            return None
    if root is None or "--before" not in values:
        return None
    before = parse_time(values["--before"])
    since = parse_time(values["--since"]) if "--since" in values else None
    if before is None or ("--since" in values and since is None):
        return None
    digits = values.get("--limit", str(DEFAULT_LIMIT))
    significant = digits.lstrip("0")
    if not DIGITS.fullmatch(digits) or not significant:
        return None
    limit = MAX_LIMIT if len(significant) > 2 else min(int(significant), MAX_LIMIT)
    statuses = values["--status"].split(",") if "--status" in values else TERMINAL
    if not all(statuses):
        return None
    return {"root": root, "before": before, "since": since, "limit": limit,
            "statuses": frozenset(statuses)}


def history(am, args):
    """The success line for `args` (from parse_args): one `am runs --repo-dir ROOT`,
    every row's started_at checked, then the kept rows in am's order, paged, each
    paged row's status replaced by its `am status` data."""
    runs = run_list(call_am(am, ["runs", "--repo-dir", args["root"]], AM_TIMEOUT))
    kept = []
    for run in runs:
        when = parse_time(run.get("started_at"))
        if when is None:
            raise bad_output("am runs listed a run without a readable started_at.")
        if (run["status"] in args["statuses"] and when < args["before"]
                and (args["since"] is None or when >= args["since"])):
            kept.append(run)
    page = [dict(run, status=run_status(am, run["id"], AM_TIMEOUT))
            for run in kept[:args["limit"]]]
    return {"ok": True, "runs": page, "more": len(kept) > args["limit"]}


def main(argv):
    args = parse_args(argv)
    if args is None:
        return failure("Usage", USAGE, 2)
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    try:
        result = history(am, args)
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
        return failure("HelperError", "The runs history failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
