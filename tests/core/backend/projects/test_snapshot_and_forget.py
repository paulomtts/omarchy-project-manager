"""snapshot-and-forget.py against a fake `brd`, in a throwaway HOME: the real
brd, the real registry, and the user's real ~/Snapshots are never touched."""
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "core", "backend", "projects", "snapshot-and-forget.py")

FAKE_BRD = """#!/bin/sh
echo "brd $* (cwd=$(pwd))" >> "$CALLS"
case "$1" in
  export)
    if [ "$FAKE_EXPORT_FAIL" = 1 ]; then
      echo '{"ok": false, "error": {"type": "ProjectNotFoundError", "message": "boom"}}'; exit 1
    fi
    echo '{"ok": true, "data": {"brd_export": 2, "projects": [{"project": {"id": "p"}, "cards": [{"id": "a", "title": "T"}], "issues": [], "documents": [], "comments": [], "tags": [], "refs": []}]}}' ;;
  forget)
    echo "snapshot_files_at_forget=$(ls "$OMARCHY_PROJECT_MANAGER_SNAPSHOT_DIR"/*/export.json "$OMARCHY_PROJECT_MANAGER_SNAPSHOT_DIR"/*/project.db 2>/dev/null | wc -l)" >> "$CALLS"
    if [ "$FAKE_FORGET_FAIL" = 1 ]; then
      echo '{"ok": false, "error": {"type": "ProjectNotFoundError", "message": "nope"}}'; exit 1
    fi
    echo '{"ok": true, "data": {}}' ;;
esac
"""


@pytest.fixture
def box(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    brd = bindir / "brd"
    brd.write_text(FAKE_BRD)
    brd.chmod(brd.stat().st_mode | stat.S_IEXEC)
    for tool in ("ls", "wc"):  # used by the fake brd itself
        (bindir / tool).symlink_to(shutil.which(tool))
    home = tmp_path / "home"
    home.mkdir()
    snaps = tmp_path / "snaps"
    project = tmp_path / "my project"
    project.mkdir()
    calls = tmp_path / "calls.log"
    calls.write_text("")
    env = {
        "HOME": str(home),
        "XDG_DATA_HOME": str(tmp_path / "xdg"),
        "PATH": str(bindir),
        "CALLS": str(calls),
        "OMARCHY_PROJECT_MANAGER_SNAPSHOT_DIR": str(snaps),
    }
    return {"env": env, "tmp": tmp_path, "snaps": snaps, "project": project, "calls": calls, "home": home}


def run(box, *args, extra_env=None):
    env = dict(box["env"], **(extra_env or {}))
    proc = subprocess.run([sys.executable, SCRIPT, *args], env=env, capture_output=True, text=True)
    out = proc.stdout.strip().splitlines()
    return proc.returncode, (json.loads(out[-1]) if out else None), proc.stderr


def calls(box):
    return box["calls"].read_text().splitlines()


def project_db(box, root):
    digest = hashlib.sha256(str(Path(root).resolve()).encode()).hexdigest()
    path = Path(box["env"]["XDG_DATA_HOME"]) / "brd" / "projects" / ("%s.db" % digest)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"SQLITE-FAKE")
    return path


def test_snapshots_then_forgets(box):
    code, result, err = run(box, str(box["project"]), "My Project")
    assert code == 0 and result["ok"] is True, (result, err)
    snap = Path(result["snapshot"])
    assert snap.is_dir() and str(snap).startswith(str(box["snaps"]))
    export = json.loads((snap / "export.json").read_text())
    assert export["data"]["brd_export"] == 2 and export["data"]["projects"][0]["cards"][0]["id"] == "a"
    assert not (snap / "tree.json").exists()
    meta = json.loads((snap / "project.json").read_text())
    assert meta["name"] == "My Project" and meta["root_path"] == str(box["project"])
    assert 'brd import "%s"' % (snap / "export.json") in (snap / "RESTORE.txt").read_text()
    log = calls(box)
    assert any(c.startswith("brd export") and c.endswith("(cwd=%s)" % box["project"]) for c in log)
    assert any(c.startswith("brd forget %s" % box["project"]) for c in log)


def test_snapshot_exists_before_forget_runs(box):
    code, result, _ = run(box, str(box["project"]), "p")
    assert code == 0
    assert "snapshot_files_at_forget=1" in calls(box)


def test_falls_back_to_raw_db_copy_when_export_fails(box):
    db = project_db(box, box["project"])
    code, result, err = run(box, str(box["project"]), "p", extra_env={"FAKE_EXPORT_FAIL": "1"})
    assert code == 0 and result["ok"] is True, (result, err)
    snap = Path(result["snapshot"])
    assert (snap / "project.db").read_bytes() == db.read_bytes()
    assert not (snap / "export.json").exists()
    assert not (snap / "project.docs").exists()
    restore = (snap / "RESTORE.txt").read_text()
    assert 'cp "%s" "%s"' % (snap / "project.db", db) in restore
    assert ".docs" not in restore
    assert any(c.startswith("brd forget") for c in calls(box))


def test_missing_project_dir_uses_the_db_copy(box):
    gone = box["tmp"] / "deleted-dir"
    db = project_db(box, gone)
    code, result, err = run(box, str(gone), "gone")
    assert code == 0 and result["ok"] is True, (result, err)
    assert (Path(result["snapshot"]) / "project.db").read_bytes() == db.read_bytes()
    assert not any(c.startswith("brd export") for c in calls(box))


def test_the_fallback_also_copies_the_document_backups(box):
    db = project_db(box, box["project"])
    docs = db.with_suffix(".docs")
    (docs / "nested").mkdir(parents=True)
    (docs / "spec.md").write_text("# spec")
    (docs / "nested" / "note.md").write_text("note")
    code, result, err = run(box, str(box["project"]), "p", extra_env={"FAKE_EXPORT_FAIL": "1"})
    assert code == 0 and result["ok"] is True, (result, err)
    snap = Path(result["snapshot"])
    assert (snap / "project.db").read_bytes() == db.read_bytes()
    assert (snap / "project.docs" / "spec.md").read_text() == "# spec"
    assert (snap / "project.docs" / "nested" / "note.md").read_text() == "note"
    restore = (snap / "RESTORE.txt").read_text()
    assert 'cp "%s" "%s"' % (snap / "project.db", db) in restore
    # Copies the contents, so an existing docs dir is filled, not nested into.
    assert 'mkdir -p "%s"' % docs in restore
    assert 'cp -r "%s/." "%s/"' % (snap / "project.docs", docs) in restore
    assert 'cp -r "%s" ' % (snap / "project.docs") not in restore


def test_refuses_to_forget_when_nothing_can_be_snapshotted(box):
    code, result, _ = run(box, str(box["project"]), "p", extra_env={"FAKE_EXPORT_FAIL": "1"})
    assert code != 0 and result["ok"] is False
    assert not any(c.startswith("brd forget") for c in calls(box))
    assert not box["snaps"].exists() or not any(box["snaps"].iterdir())


def test_forget_failure_is_reported_and_the_snapshot_is_kept(box):
    code, result, _ = run(box, str(box["project"]), "p", extra_env={"FAKE_FORGET_FAIL": "1"})
    assert code != 0 and result["ok"] is False
    assert "nope" in result["error"]
    assert list(box["snaps"].iterdir())


def test_two_snapshots_of_the_same_project_do_not_collide(box):
    first = run(box, str(box["project"]), "same")[1]["snapshot"]
    second = run(box, str(box["project"]), "same")[1]["snapshot"]
    assert first != second and Path(first).is_dir() and Path(second).is_dir()


def test_unsafe_names_are_sanitised_and_stay_inside_the_snapshot_dir(box):
    code, result, _ = run(box, str(box["project"]), "../../evil name/x")
    assert code == 0
    snap = Path(result["snapshot"]).resolve()
    assert snap.parent == box["snaps"].resolve()


def test_name_defaults_to_the_directory_name(box):
    code, result, _ = run(box, str(box["project"]))
    assert code == 0
    assert "my-project" in Path(result["snapshot"]).name


def test_default_snapshot_dir_is_under_home(box):
    env = dict(box["env"])
    del env["OMARCHY_PROJECT_MANAGER_SNAPSHOT_DIR"]
    box["env"] = env
    code, result, _ = run(box, str(box["project"]), "p")
    assert code == 0
    assert result["snapshot"].startswith(str(box["home"] / "Snapshots" / "omarchy-project-manager"))


def test_requires_a_path_argument(box):
    code, result, _ = run(box)
    assert code != 0 and result["ok"] is False
    assert calls(box) == []


def test_the_old_snapshot_dir_variable_is_still_honoured(box):
    env = dict(box["env"])
    env["BRD_VIEWER_SNAPSHOT_DIR"] = env.pop("OMARCHY_PROJECT_MANAGER_SNAPSHOT_DIR")
    box["env"] = env
    code, result, _ = run(box, str(box["project"]), "p")
    assert code == 0
    assert Path(result["snapshot"]).resolve().parent == box["snaps"].resolve()
