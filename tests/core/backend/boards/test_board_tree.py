"""board-tree.py against a fake `brd` on PATH: tree mode runs only `brd tree`, once,
in ROOT; probe mode never runs brd. Every call prints one JSON line and exits 0."""
import importlib.util
import json
import os
import shutil
import stat
import subprocess
import sys
import time

import pytest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "core", "backend", "boards", "board-tree.py")

FAKE_BRD = """#!/bin/sh
echo "brd $* (cwd=$(pwd))" >> "$CALLS"
if [ -n "$FAKE_READ" ]; then
  read l
  echo "stdin=$l" >> "$CALLS"
fi
if [ -n "$FAKE_SLEEP" ]; then
  exec "$SLEEP_BIN" "$FAKE_SLEEP"
fi
printf '%s' "$FAKE_OUT"
printf '%s' "$FAKE_ERR" >&2
exit "${FAKE_EXIT:-0}"
"""

USAGE = "usage: board-tree.py ROOT | board-tree.py --probe ROOT [ROOT ...]"


@pytest.fixture
def box(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    brd = bindir / "brd"
    brd.write_text(FAKE_BRD)
    brd.chmod(brd.stat().st_mode | stat.S_IEXEC)
    empty = tmp_path / "empty"
    empty.mkdir()
    project = tmp_path / "my project"
    (project / ".brd").mkdir(parents=True)
    calls_log = tmp_path / "calls.log"
    calls_log.write_text("")
    env = {"PATH": str(bindir), "CALLS": str(calls_log), "SLEEP_BIN": shutil.which("sleep")}
    return {"env": env, "bindir": bindir, "empty": empty, "project": project, "calls": calls_log, "tmp": tmp_path}


def run(box, *args, extra_env=None, stdin_text="", cwd=None):
    env = dict(box["env"], **(extra_env or {}))
    proc = subprocess.run([sys.executable, SCRIPT, *args], env=env, input=stdin_text, cwd=cwd,
                          capture_output=True, text=True, timeout=60)
    lines = proc.stdout.splitlines()
    assert len(lines) == 1, proc.stdout + proc.stderr
    return proc.returncode, json.loads(lines[0])


def calls(box):
    return box["calls"].read_text().splitlines()


def load_module():
    spec = importlib.util.spec_from_file_location("board_tree", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


OK_TREE = {"ok": True, "data": []}


def test_tree_runs_brd_tree_once_in_root(box):
    code, out = run(box, str(box["project"]), extra_env={"FAKE_OUT": json.dumps(OK_TREE)})
    assert code == 0
    assert out == OK_TREE
    assert calls(box) == ["brd tree (cwd=%s)" % box["project"].resolve()]


def test_tree_passes_brds_payload_through_unchanged(box):
    payload = {"ok": True, "data": [{"id": "a", "children": [], "title": "é"}], "extra": 1}
    code, out = run(box, str(box["project"]), extra_env={"FAKE_OUT": json.dumps(payload, ensure_ascii=False)})
    assert code == 0
    assert out == payload
    assert list(out) == ["ok", "data", "extra"]


def test_pretty_printed_brd_output_passes_through_as_one_line(box):
    payload = {"ok": True, "data": [{"id": "a", "children": [{"id": "b", "children": []}]}]}
    code, out = run(box, str(box["project"]), extra_env={"FAKE_OUT": json.dumps(payload, indent=2)})
    assert code == 0
    assert out == payload


def test_brd_gets_devnull_as_stdin(box):
    code, out = run(box, str(box["project"]), stdin_text="leak\n",
                    extra_env={"FAKE_READ": "1", "FAKE_OUT": json.dumps(OK_TREE)})
    assert code == 0
    assert out == OK_TREE
    assert calls(box)[1] == "stdin="


def test_a_relative_root_resolves_against_the_helpers_cwd(box):
    code, out = run(box, "my project", cwd=str(box["tmp"]), extra_env={"FAKE_OUT": json.dumps(OK_TREE)})
    assert code == 0
    assert out == OK_TREE
    assert calls(box) == ["brd tree (cwd=%s)" % box["project"].resolve()]


@pytest.mark.parametrize("kind", ["missing", "file", "empty string"])
def test_a_missing_root_is_rootmissing_and_runs_nothing(box, kind):
    if kind == "missing":
        root = str(box["tmp"] / "nope")
    elif kind == "file":
        a_file = box["tmp"] / "a file"
        a_file.write_text("x")
        root = str(a_file)
    else:
        root = ""
    code, out = run(box, root)
    assert code == 0
    assert out == {"ok": False, "error": {"type": "RootMissing", "message": "project directory not found: %s" % root}}
    assert calls(box) == []


@pytest.mark.parametrize("stdout", ["not json", "[]", '{"ok": false}', '{"ok": true}', '{"ok": true, "data": {}}'])
def test_unexpected_output_with_exit_zero_is_brdbadoutput(box, stdout):
    code, out = run(box, str(box["project"]), extra_env={"FAKE_OUT": stdout})
    assert code == 0
    assert out == {"ok": False, "error": {"type": "BrdBadOutput", "message": "brd tree returned unexpected output"}}


@pytest.mark.parametrize("args", [[], ["a", "b"], ["--help"], ["-x"]])
def test_bad_usage_is_a_helpererror_and_runs_nothing(box, args):
    code, out = run(box, *args)
    assert code == 0
    assert out == {"ok": False, "error": {"type": "HelperError", "message": USAGE}}
    assert out["error"]["message"].startswith("usage:")
    assert calls(box) == []


def test_timeout_constant_is_twenty_seconds():
    assert load_module().TIMEOUT_SECONDS == 20
