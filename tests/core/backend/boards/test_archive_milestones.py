"""archive-milestones.py against a fake `brd` on PATH: only `brd update <id>
--status archived` is ever run, once per id passed, continuing past failures."""
import json
import os
import stat
import subprocess
import sys

import pytest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "core", "backend", "boards", "archive-milestones.py")

FAKE_BRD = """#!/bin/sh
echo "brd $* (cwd=$(pwd))" >> "$CALLS"
case " $FAKE_FAIL_IDS " in
  *" $2 "*)
    echo '{"ok": false, "error": {"type": "CardNotFoundError", "message": "no card '"$2"'"}}'; exit 1 ;;
esac
echo '{"ok": true, "data": {}}'
"""


@pytest.fixture
def box(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    brd = bindir / "brd"
    brd.write_text(FAKE_BRD)
    brd.chmod(brd.stat().st_mode | stat.S_IEXEC)
    project = tmp_path / "my project"
    project.mkdir()
    calls = tmp_path / "calls.log"
    calls.write_text("")
    return {"env": {"PATH": str(bindir), "CALLS": str(calls)}, "project": project, "calls": calls, "tmp": tmp_path}


def run(box, *args, extra_env=None):
    env = dict(box["env"], **(extra_env or {}))
    proc = subprocess.run([sys.executable, SCRIPT, *args], env=env, capture_output=True, text=True)
    out = proc.stdout.strip().splitlines()
    return proc.returncode, (json.loads(out[-1]) if out else None)


def calls(box):
    return box["calls"].read_text().splitlines()


def test_archives_each_id_with_update_status_archived_in_the_project(box):
    code, out = run(box, str(box["project"]), "m1", "m2")
    assert code == 0
    assert out == {"ok": True, "results": [{"id": "m1", "ok": True}, {"id": "m2", "ok": True}]}
    assert calls(box) == [
        "brd update m1 --status archived (cwd=%s)" % box["project"].resolve(),
        "brd update m2 --status archived (cwd=%s)" % box["project"].resolve(),
    ]


def test_a_failure_is_reported_per_id_and_the_rest_still_run(box):
    code, out = run(box, str(box["project"]), "m1", "bad", "m3", extra_env={"FAKE_FAIL_IDS": "bad"})
    assert code == 1
    assert out["ok"] is False
    assert [r["id"] for r in out["results"]] == ["m1", "bad", "m3"]
    assert [r["ok"] for r in out["results"]] == [True, False, True]
    assert out["results"][1]["error"] == "no card bad"
    assert len(calls(box)) == 3


def test_missing_brd_is_reported_per_id(box):
    code, out = run(box, str(box["project"]), "m1", extra_env={"PATH": str(box["tmp"] / "empty")})
    assert code == 1
    assert out["results"][0]["ok"] is False
    assert "brd" in out["results"][0]["error"]


def test_no_ids_is_an_error_and_runs_nothing(box):
    code, out = run(box, str(box["project"]))
    assert code == 1
    assert out["ok"] is False and "error" in out
    assert calls(box) == []


def test_a_missing_project_root_runs_nothing(box):
    code, out = run(box, str(box["tmp"] / "nope"), "m1")
    assert code == 1
    assert out["ok"] is False and "error" in out
    assert calls(box) == []


def test_ids_that_look_like_options_are_refused_not_passed_to_brd(box):
    code, out = run(box, str(box["project"]), "--title", "m1")
    assert code == 1
    assert out["results"][0] == {"id": "--title", "ok": False, "error": "not a card id"}
    assert [c.split(" (")[0] for c in calls(box)] == ["brd update m1 --status archived"]


def test_duplicate_ids_are_archived_once(box):
    code, out = run(box, str(box["project"]), "m1", "m1")
    assert code == 0
    assert [r["id"] for r in out["results"]] == ["m1"]
    assert len(calls(box)) == 1
