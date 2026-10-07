#!/usr/bin/env python3
"""Print the on-disk path of the brd database to watch for changes, without
touching it.

brd now keeps every project's data in one consolidated database (see
brd/src/brd/paths.py:brd_db_path() -- "Read and write every project in
brd.db"); the per-project hashed file this script used to print is a
pre-consolidation path that brd only ever writes to once, during its
one-time migration, and then renames to "<hash>.db.migrated". Watching it
is watching a file that never changes again, which is why Panel.qml's
auto-refresh stopped firing. live_db_path() is what Panel.qml should watch
instead; project_db_path() is kept only for snapshot-and-forget.py's
legacy fallback (copying a pre-consolidation project database when
`brd export` cannot run). This script never opens or reads either
database; see brd/src/brd/paths.py for the originals.
"""
import hashlib
import os
import sys
from pathlib import Path


def _data_dir():
    xdg = os.environ.get("XDG_DATA_HOME")
    if xdg:
        return Path(xdg) / "brd"
    if os.environ.get("HOME"):
        return Path(os.environ["HOME"]) / ".local" / "share" / "brd"
    return None


def project_db_path(root_path):
    base = _data_dir()
    if base is None:
        return None
    digest = hashlib.sha256(str(Path(root_path).resolve()).encode()).hexdigest()
    return base / "projects" / f"{digest}.db"


def live_db_path():
    base = _data_dir()
    if base is None:
        return None
    return base / "brd.db"


def main():
    if len(sys.argv) != 2 or sys.argv[1] == "":
        return 1
    # root_path is still required (and resolved) so a project whose directory
    # is gone fails the same way it always has; the printed path no longer
    # depends on it now that brd shares one database across all projects.
    Path(sys.argv[1]).resolve()
    path = live_db_path()
    if path is None:
        return 1
    print(str(path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
